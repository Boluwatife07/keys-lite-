import type { FastifyInstance } from 'fastify';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { createSession, requireUser } from '../../lib/auth.js';
import { clock, DAY, MINUTE } from '../../lib/clock.js';
import { AppError, badRequest } from '../../lib/errors.js';
import { EMAIL_RE, LIMITS, passwordProblems } from '../../lib/rules.js';
import { verifySocialToken } from '../../services/social.js';
import { issueCode, spendTicket, verifyCode } from './codes.js';

const email = z.string().trim().toLowerCase().refine((e) => EMAIL_RE.test(e), 'Enter a valid email address');
const code = z.string().regex(/^\d{6}$/, 'Invalid verification code. Please check and try again');

function checkNewPassword(password: string, confirm: string) {
  const problems = passwordProblems(password);
  if (problems.length) throw badRequest('PASSWORD_RULES', 'Your password does not meet the rules.', { rules: problems });
  if (password !== confirm) throw badRequest('PASSWORD_MISMATCH', 'Passwords do not match', { field: 'confirmPassword' });
}

// Users deactivated more than 30 days ago are treated as deleted (PRF-18).
const LIVE_USER = `(deactivated_at is null or deactivated_at > $2)`;
const deletionCutoff = () => new Date(clock.now().getTime() - LIMITS.deactivationWindowDays * DAY);

export async function authRoutes(app: FastifyInstance) {
  // ONB-05: email entry. Existing account -> password screen, otherwise send a code.
  app.post('/auth/email/start', async (req) => {
    const body = z.object({ email }).parse(req.body);
    const user = await one<{ first_name: string; password_hash: string | null }>(
      `select first_name, password_hash from users where email = $1 and ${LIVE_USER}`,
      [body.email, deletionCutoff()],
    );
    if (user) return { status: 'existing', firstName: user.first_name, hasPassword: !!user.password_hash };
    const sent = await issueCode({ email: body.email, purpose: 'signup', ip: req.ip });
    return { status: 'code_sent', ...sent };
  });

  app.post('/auth/code/resend', async (req) => {
    const body = z.object({ email, purpose: z.enum(['signup', 'reset']) }).parse(req.body);
    if (body.purpose === 'reset') {
      const u = await one('select id from users where email = $1', [body.email]);
      if (!u) return { resendInSeconds: LIMITS.resendAfterSeconds };
    }
    return issueCode({ email: body.email, purpose: body.purpose, ip: req.ip, isResend: true });
  });

  // ONB-07: verify the sign-up code.
  app.post('/auth/email/verify', async (req) => {
    const body = z.object({ email, code }).parse(req.body);
    return { ticket: await verifyCode(body.email, 'signup', body.code) };
  });

  // ONB-08: legal name + password, account created.
  app.post('/auth/signup', async (req) => {
    const body = z.object({
      ticket: z.string(),
      firstName: z.string().trim(),
      lastName: z.string().trim(),
      password: z.string(),
      confirmPassword: z.string(),
    }).parse(req.body);
    if (!body.firstName) throw badRequest('FIRST_NAME_REQUIRED', 'Add a first name', { field: 'firstName' });
    if (!body.lastName) throw badRequest('LAST_NAME_REQUIRED', 'Add a last name', { field: 'lastName' });
    checkNewPassword(body.password, body.confirmPassword);
    const t = await spendTicket(body.ticket, 'signup');
    const hash = await bcrypt.hash(body.password, 10);
    const user = await one<{ id: string }>(
      `insert into users(email, email_verified, first_name, last_name, password_hash, onboarding_step)
       values ($1, true, $2, $3, $4, 'address')
       on conflict (email) do nothing returning id`,
      [t.email, body.firstName, body.lastName, hash],
    );
    if (!user) throw new AppError(409, 'EMAIL_IN_USE', 'An account already exists for this email.');
    return { token: await createSession(user.id, req.headers['user-agent']), onboardingStep: 'address' };
  });

  // ONB-09: password login, lockout, reactivation inside the 30-day window.
  app.post('/auth/login', async (req) => {
    const body = z.object({ email, password: z.string() }).parse(req.body);
    const now = clock.now();
    const u = await one<any>(`select * from users where email = $1 and ${LIVE_USER}`, [body.email, deletionCutoff()]);
    if (!u) throw badRequest('NO_ACCOUNT', 'No account found for this email.');
    if (u.locked_until && u.locked_until > now) {
      throw new AppError(429, 'LOCKED', `Too many attempts. Try again in ${Math.ceil((u.locked_until - +now) / MINUTE)} minutes.`);
    }
    if (!u.password_hash || !(await bcrypt.compare(body.password, u.password_hash))) {
      const failed = u.failed_logins + 1;
      const lock = failed >= LIMITS.maxFailedLogins ? new Date(now.getTime() + LIMITS.lockoutMinutes * MINUTE) : null;
      await q('update users set failed_logins = $2, locked_until = $3 where id = $1', [u.id, lock ? 0 : failed, lock]);
      throw badRequest('INCORRECT_PASSWORD', 'Incorrect password', { field: 'password' });
    }
    const reactivated = !!u.deactivated_at;
    await q('update users set failed_logins = 0, locked_until = null, deactivated_at = null where id = $1', [u.id]);
    return { token: await createSession(u.id, req.headers['user-agent']), onboardingStep: u.onboarding_step, reactivated };
  });

  // ONB-06: Apple / Google. One account per email; social login links to it.
  app.post('/auth/social', async (req) => {
    const body = z.object({
      provider: z.enum(['apple', 'google']),
      idToken: z.string(),
      firstName: z.string().trim().optional(),
      lastName: z.string().trim().optional(),
    }).parse(req.body);
    const profile = await verifySocialToken(body.provider, body.idToken);
    const mail = profile.email.trim().toLowerCase();
    const result = await tx(async (c) => {
      const linked = await one<any>(
        `select u.* from social_identities s join users u on u.id = s.user_id where s.provider = $1 and s.provider_user_id = $2`,
        [body.provider, profile.sub], c,
      );
      if (linked) return { user: linked, isNew: false };
      let user = await one<any>('select * from users where email = $1', [mail], c);
      let isNew = false;
      if (!user) {
        isNew = true;
        user = await one<any>(
          `insert into users(email, email_verified, first_name, last_name, onboarding_step)
           values ($1, true, $2, $3, 'account') returning *`,
          [mail, body.firstName ?? profile.firstName ?? '', body.lastName ?? profile.lastName ?? ''], c,
        );
      }
      await q('insert into social_identities(provider, provider_user_id, user_id) values ($1,$2,$3)', [body.provider, profile.sub, user.id], c);
      return { user, isNew };
    });
    if (result.user.deactivated_at) {
      if (result.user.deactivated_at <= deletionCutoff()) throw badRequest('NO_ACCOUNT', 'No account found for this email.');
      await q('update users set deactivated_at = null where id = $1', [result.user.id]);
    }
    return {
      token: await createSession(result.user.id, req.headers['user-agent']),
      isNew: result.isNew,
      onboardingStep: result.user.onboarding_step,
      firstName: result.user.first_name,
      lastName: result.user.last_name,
    };
  });

  // ONB-10: forgot password. Same answer whether or not the email exists.
  app.post('/auth/password/forgot', async (req) => {
    const body = z.object({ email }).parse(req.body);
    const u = await one<{ id: string }>(`select id from users where email = $1 and ${LIVE_USER}`, [body.email, deletionCutoff()]);
    if (u) await issueCode({ email: body.email, purpose: 'reset', userId: u.id, ip: req.ip });
    return { resendInSeconds: LIMITS.resendAfterSeconds };
  });

  app.post('/auth/password/verify', async (req) => {
    const body = z.object({ email, code }).parse(req.body);
    return { ticket: await verifyCode(body.email, 'reset', body.code) };
  });

  app.post('/auth/password/reset', async (req) => {
    const body = z.object({ ticket: z.string(), password: z.string(), confirmPassword: z.string() }).parse(req.body);
    checkNewPassword(body.password, body.confirmPassword);
    const t = await spendTicket(body.ticket, 'reset');
    const hash = await bcrypt.hash(body.password, 10);
    await q('update users set password_hash = $2, failed_logins = 0, locked_until = null where email = $1', [t.email, hash]);
    // ONB-10.4: every session signed out.
    await q('update sessions set revoked_at = $2 where user_id = (select id from users where email = $1) and revoked_at is null', [t.email, clock.now()]);
    return { ok: true };
  });

  app.post('/auth/logout', async (req) => {
    const u = requireUser(req);
    await q('update sessions set revoked_at = $2 where id = $1', [u.session_id, clock.now()]);
    return { ok: true };
  });
}
