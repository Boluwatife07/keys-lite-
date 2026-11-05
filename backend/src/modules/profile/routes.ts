import type { FastifyInstance } from 'fastify';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { clock, DAY } from '../../lib/clock.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { exitCheck } from '../../lib/exit.js';
import { PREF_DEFAULTS, prefs } from '../../lib/notify.js';
import { communityOf, hiddenAuthorSql, isMuted, person } from '../../lib/people.js';
import { EMAIL_RE, LIMITS, passwordProblems } from '../../lib/rules.js';
import { issueCode, spendTicket, verifyCode, INVALID_CODE } from '../auth/codes.js';
import { shareLink } from '../links/routes.js';
import { postsFor } from '../feed/read.js';
import { leaveBoard } from '../board/service.js';

const MUTE_DAYS = 30;

function checkNewPassword(password: string, confirm: string) {
  const problems = passwordProblems(password);
  if (problems.length) throw badRequest('PASSWORD_RULES', 'Your password does not meet the rules.', { rules: problems });
  if (password !== confirm) throw badRequest('PASSWORD_MISMATCH', 'Passwords do not match', { field: 'confirmPassword' });
}

async function checkPassword(userId: string, password: string, field = 'password') {
  const u = (await one<{ password_hash: string | null }>('select password_hash from users where id = $1', [userId]))!;
  if (!u.password_hash) throw conflict('PASSWORD_REQUIRED', 'Add a password first');
  if (!(await bcrypt.compare(password, u.password_hash))) throw badRequest('INCORRECT_PASSWORD', 'Incorrect password', { field });
}

/** Target must be a live resident in the viewer's community (PRF-03.3). */
async function visibleTarget(viewer: string, targetId: string) {
  const [mine, theirs] = await Promise.all([communityOf(viewer), communityOf(targetId)]);
  const live = await one('select 1 from users where id = $1 and deactivated_at is null', [targetId]);
  if (!live || !mine || mine !== theirs) throw notFound('This profile is not available.');
  // The blocked person cannot see the blocker; the blocker still sees an "Unblock" profile.
  if (await one('select 1 from blocks where user_id = $1 and target_id = $2', [targetId, viewer])) throw notFound('This profile is not available.');
}

export async function profileRoutes(app: FastifyInstance) {
  // PRF-02: another resident's profile.
  app.get('/users/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    if (id !== u.id) await visibleTarget(u.id, id);
    const r = await one<any>(
      `select u.bio, m.joined_at, c.name as community from users u
         join memberships m on m.user_id = u.id join communities c on c.id = m.community_id where u.id = $1`, [id],
    );
    if (!r) throw notFound('This profile is not available.');
    const p = (await person(id))!;
    const blockedByMe = !!(await one('select 1 from blocks where user_id = $1 and target_id = $2', [u.id, id]));
    return {
      ...p,
      bio: r.bio,
      community: r.community,
      joinedAt: r.joined_at,
      isMe: id === u.id,
      isMuted: await isMuted(u.id, id),
      isBlocked: blockedByMe,
      shareLink: shareLink('profile', id),
    };
  });

  // PRF-01.1 "My feed", PRF-19 My Activities (my posts only in Phase 1).
  app.get('/users/:id/posts', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const { cursor } = z.object({ cursor: z.string().optional() }).parse(req.query);
    if (id !== u.id) {
      await visibleTarget(u.id, id);
      if (await one('select 1 from blocks where user_id = $1 and target_id = $2', [u.id, id])) return { posts: [], total: 0 };
    }
    const total = (await one<{ n: number }>(`select count(*)::int as n from posts where author_id = $1 and status = 'live'`, [id]))!.n;
    return { ...(await postsFor(u.id, { authorId: id, cursor })), total };
  });

  // PRF-04: mute for 30 days; ends automatically.
  app.post('/users/:id/mute', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    if (id === u.id) throw badRequest('SELF', 'You cannot mute yourself.');
    await visibleTarget(u.id, id);
    const until = new Date(clock.now().getTime() + MUTE_DAYS * DAY);
    await q(
      `insert into mutes(user_id, target_id, until, created_at) values ($1,$2,$3,$4)
       on conflict (user_id, target_id) do update set until = excluded.until, created_at = excluded.created_at`,
      [u.id, id, until, clock.now()],
    );
    const p = (await person(id))!;
    return { ok: true, until, message: `You muted ${p.name}` };
  });
  app.delete('/users/:id/mute', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    await q('delete from mutes where user_id = $1 and target_id = $2', [u.id, id]);
    const p = await person(id);
    return { ok: true, message: `You unmuted ${p?.name ?? ''}`.trim() };
  });

  // PRF-05: block. Two-way hide, the other person is not told.
  app.post('/users/:id/block', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    if (id === u.id) throw badRequest('SELF', 'You cannot block yourself.');
    await visibleTarget(u.id, id);
    await q('insert into blocks(user_id, target_id, created_at) values ($1,$2,$3) on conflict do nothing', [u.id, id, clock.now()]);
    const p = (await person(id))!;
    return { ok: true, message: `You blocked ${p.name}` };
  });
  app.delete('/users/:id/block', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    await q('delete from blocks where user_id = $1 and target_id = $2', [u.id, id]);
    const p = await person(id);
    return { ok: true, message: `You have unblocked ${p?.name ?? ''}`.trim() };
  });

  // PRF-13: lists.
  app.get('/me/muted', async (req) => {
    const u = requireUser(req);
    const rows = await q<any>(
      `select m.target_id, m.created_at, u.first_name, u.last_name, u.photo_url from mutes m join users u on u.id = m.target_id
        where m.user_id = $1 and m.until > $2 order by m.created_at desc`, [u.id, clock.now()],
    );
    return { accounts: rows.map((r) => ({ id: r.target_id, name: `${r.first_name} ${r.last_name}`, photoUrl: r.photo_url, since: r.created_at })) };
  });
  app.get('/me/blocked', async (req) => {
    const u = requireUser(req);
    const rows = await q<any>(
      `select b.target_id, b.created_at, u.first_name, u.last_name, u.photo_url from blocks b join users u on u.id = b.target_id
        where b.user_id = $1 order by b.created_at desc`, [u.id],
    );
    return { accounts: rows.map((r) => ({ id: r.target_id, name: `${r.first_name} ${r.last_name}`, photoUrl: r.photo_url, since: r.created_at })) };
  });

  // PRF-08: replace (never remove) the photo.
  app.put('/me/photo', async (req) => {
    const u = requireUser(req);
    const { mediaId } = z.object({ mediaId: z.string().uuid() }).parse(req.body);
    const m = await one<{ url: string }>(`select url from media where id = $1 and owner_id = $2 and kind = 'photo'`, [mediaId, u.id]);
    if (!m) throw badRequest('PHOTO_REQUIRED', 'Choose a photo.');
    await q('update users set photo_url = $2 where id = $1', [u.id, m.url]);
    return { photoUrl: m.url, message: 'Picture changed successfully' };
  });

  // PRF-09
  app.put('/me/bio', async (req) => {
    const u = requireUser(req);
    const { bio } = z.object({ bio: z.string().max(LIMITS.bio, `Bio can be up to ${LIMITS.bio} characters`) }).parse(req.body);
    await q('update users set bio = $2 where id = $1', [u.id, bio.trim()]);
    return { bio: bio.trim(), message: 'Bio changed successfully' };
  });

  // PRF-10: change email = password, new email, code to the new email.
  app.post('/me/email/password', async (req) => {
    const u = requireUser(req);
    const { password } = z.object({ password: z.string() }).parse(req.body);
    await checkPassword(u.id, password);
    return { ok: true, currentEmail: u.email };
  });
  app.post('/me/email/start', async (req) => {
    const u = requireUser(req);
    const body = z.object({
      password: z.string(),
      newEmail: z.string().trim().toLowerCase().refine((e) => EMAIL_RE.test(e), 'Enter a valid email address'),
    }).parse(req.body);
    await checkPassword(u.id, body.password);
    if (body.newEmail === u.email.toLowerCase()) throw badRequest('SAME_EMAIL', 'This is already your email address.', { field: 'newEmail' });
    if (await one('select 1 from users where email = $1', [body.newEmail])) {
      throw conflict('EMAIL_IN_USE', 'This email is already linked to another Keys account.', { field: 'newEmail' });
    }
    return issueCode({ email: body.newEmail, purpose: 'change_email', userId: u.id, ip: req.ip });
  });
  app.post('/me/email/resend', async (req) => {
    const u = requireUser(req);
    const { newEmail } = z.object({ newEmail: z.string().trim().toLowerCase() }).parse(req.body);
    return issueCode({ email: newEmail, purpose: 'change_email', userId: u.id, ip: req.ip, isResend: true });
  });
  app.post('/me/email/verify', async (req) => {
    const u = requireUser(req);
    const body = z.object({ newEmail: z.string().trim().toLowerCase(), code: z.string().regex(/^\d{6}$/, INVALID_CODE) }).parse(req.body);
    const ticket = await verifyCode(body.newEmail, 'change_email', body.code);
    const t = await spendTicket(ticket, 'change_email');
    if (t.user_id !== u.id) throw badRequest('INVALID_CODE', INVALID_CODE);
    try {
      await q('update users set email = $2, email_verified = true where id = $1', [u.id, body.newEmail]);
    } catch (e: any) {
      if (e.code === '23505') throw conflict('EMAIL_IN_USE', 'This email is already linked to another Keys account.');
      throw e;
    }
    return { email: body.newEmail, message: 'Your email has been verified.' };
  });

  // PRF-15: change password. Other sessions are signed out.
  app.put('/me/password', async (req) => {
    const u = requireUser(req);
    const body = z.object({ current: z.string(), password: z.string(), confirmPassword: z.string() }).parse(req.body);
    await checkPassword(u.id, body.current, 'current');
    checkNewPassword(body.password, body.confirmPassword);
    await q('update users set password_hash = $2 where id = $1', [u.id, await bcrypt.hash(body.password, 10)]);
    await q('update sessions set revoked_at = $3 where user_id = $1 and id <> $2 and revoked_at is null', [u.id, u.session_id, clock.now()]);
    return { message: 'Your password has been changed successfully' };
  });

  // PRF-16: social accounts add a password with an email code.
  app.post('/me/password/create/start', async (req) => {
    const u = requireUser(req);
    const has = await one(`select 1 from users where id = $1 and password_hash is not null`, [u.id]);
    if (has) throw conflict('HAS_PASSWORD', 'You already have a password. Use Change password.');
    return issueCode({ email: u.email, purpose: 'create_password', userId: u.id, ip: req.ip });
  });
  app.post('/me/password/create', async (req) => {
    const u = requireUser(req);
    const body = z.object({ code: z.string().regex(/^\d{6}$/, INVALID_CODE), password: z.string(), confirmPassword: z.string() }).parse(req.body);
    checkNewPassword(body.password, body.confirmPassword);
    const ticket = await verifyCode(u.email, 'create_password', body.code);
    await spendTicket(ticket, 'create_password');
    await q('update users set password_hash = $2 where id = $1 and password_hash is null', [u.id, await bcrypt.hash(body.password, 10)]);
    return { message: 'Your password has been created successfully' };
  });

  // PRF-14
  app.get('/me/notification-prefs', async (req) => ({ prefs: await prefs(requireUser(req).id) }));
  app.put('/me/notification-prefs', async (req) => {
    const u = requireUser(req);
    const body = z.record(z.string(), z.boolean()).parse(req.body);
    for (const [k, v] of Object.entries(body)) {
      if (!(k in PREF_DEFAULTS)) throw badRequest('UNKNOWN_TOGGLE', `Unknown setting ${k}`);
      await q(`insert into notification_prefs(user_id, key, enabled) values ($1,$2,$3) on conflict (user_id, key) do update set enabled = excluded.enabled`, [u.id, k, v]);
    }
    return { prefs: await prefs(u.id) };
  });

  // PRF-17.2: push token registration and removal at logout.
  app.post('/me/push-token', async (req) => {
    const u = requireUser(req);
    const body = z.object({ token: z.string().min(10), platform: z.enum(['ios', 'android', 'web']).optional() }).parse(req.body);
    await q(`insert into push_tokens(token, user_id, platform) values ($1,$2,$3) on conflict (token) do update set user_id = excluded.user_id`, [body.token, u.id, body.platform ?? null]);
    return { ok: true };
  });

  // PRF-11.1 / PRF-11.5 / PRF-18.5: pre-exit check.
  app.get('/me/exit-check', async (req) => {
    const u = requireUser(req);
    const { reason } = z.object({ reason: z.enum(['move', 'deactivate']) }).parse(req.query);
    return exitCheck(u.id, reason);
  });

  // PRF-11: change home address. Leaves the community, frees any seat,
  // resets verification, then reuses onboarding from the address step.
  app.post('/me/move', async (req) => {
    const u = requireUser(req);
    const check = await exitCheck(u.id, 'move');
    if (check.blockers.length) throw forbidden('EXIT_BLOCKED', check.blockers[0].message);
    // PRF-11.3 / CBM-19.2: the seat is revoked and open applications and proposals end.
    await leaveBoard(u.id, { why: 'left_community', reason: 'Moved home' });
    await tx(async (c) => {
      await q('delete from memberships where user_id = $1', [u.id], c);
      await q(
        `update users set onboarding_step = 'address', verification_status = 'unverified', welcome_prompt_done_at = null where id = $1`,
        [u.id], c,
      );
    });
    return { onboardingStep: 'address' };
  });

  // PRF-18: deactivate with password; once per 7 days; deleted after 30 days.
  app.post('/me/deactivate', async (req) => {
    const u = requireUser(req);
    const { password } = z.object({ password: z.string() }).parse(req.body);
    await checkPassword(u.id, password);
    const r = (await one<{ last: Date | null }>('select last_deactivated_at as last from users where id = $1', [u.id]))!;
    if (r.last && clock.now().getTime() - r.last.getTime() < LIMITS.redeactivateBlockDays * DAY) {
      throw new AppError(429, 'DEACTIVATE_TOO_SOON', 'You cannot deactivate your account for the next 7 days');
    }
    const check = await exitCheck(u.id, 'deactivate');
    if (check.blockers.length) throw forbidden('EXIT_BLOCKED', check.blockers[0].message);
    const now = clock.now();
    await leaveBoard(u.id, { why: 'left_community' });
    await q('update users set deactivated_at = $2, last_deactivated_at = $2 where id = $1', [u.id, now]);
    await q('update sessions set revoked_at = $2 where user_id = $1 and revoked_at is null', [u.id, now]);
    await q('delete from push_tokens where user_id = $1', [u.id]);
    return { ok: true, deleteAfter: new Date(now.getTime() + LIMITS.deactivationWindowDays * DAY) };
  });

  // FED-03.1: @ suggestions = community members, minus blocked either way.
  app.get('/members/search', async (req) => {
    const u = requireUser(req);
    const { q: text } = z.object({ q: z.string().default('') }).parse(req.query);
    const c = await communityOf(u.id);
    if (!c) return { members: [] };
    const rows = await q<any>(
      `select u.id, u.first_name, u.last_name, u.photo_url, s.role from memberships m
         join users u on u.id = m.user_id left join board_seats s on s.occupant_id = u.id
        where m.community_id = $1 and u.id <> $2 and u.deactivated_at is null
          and not ${hiddenAuthorSql('u.id', '$2')}
          and (u.first_name || ' ' || u.last_name) ilike '%' || $3 || '%'
        order by u.first_name, u.last_name limit 20`,
      [c, u.id, text.trim()],
    );
    return { members: rows.map((r) => ({ id: r.id, name: `${r.first_name} ${r.last_name}`, photoUrl: r.photo_url, role: r.role })) };
  });
}
