import { one, q } from '../../db/pool.js';
import { clock, SECOND, MINUTE, HOUR } from '../../lib/clock.js';
import { randomToken, sha256, sixDigitCode } from '../../lib/crypto.js';
import { AppError, badRequest, tooMany } from '../../lib/errors.js';
import { LIMITS } from '../../lib/rules.js';
import { sendEmail, type EmailTemplate } from '../../services/email.js';

export type CodePurpose = 'signup' | 'reset' | 'change_email';
const TEMPLATE: Record<CodePurpose, EmailTemplate> = {
  signup: 'signup_code',
  reset: 'reset_code',
  change_email: 'change_email_code',
};
// Copy from design (ONB-07.4). Design says "Pls"; we use "Please" (sheet note suggests it).
export const INVALID_CODE = 'Invalid verification code. Please check and try again';

// Sends a fresh 6-digit code. Any older live code for the same email and
// purpose stops working (ONB-07.2). A resend is allowed 60 s after the last.
export async function issueCode(opts: { email: string; purpose: CodePurpose; userId?: string; ip?: string; isResend?: boolean }) {
  const now = clock.now();
  const last = await one<{ created_at: Date }>(
    'select created_at from email_codes where email = $1 and purpose = $2 order by created_at desc limit 1',
    [opts.email, opts.purpose],
  );
  if (opts.isResend && last) {
    const wait = LIMITS.resendAfterSeconds - Math.floor((now.getTime() - last.created_at.getTime()) / SECOND);
    if (wait > 0) throw new AppError(429, 'RESEND_TOO_SOON', `Resend code in ${wait}s`, { retryInSeconds: wait });
  }
  const since = new Date(now.getTime() - HOUR);
  const perEmail = await one<{ n: number }>('select count(*)::int as n from code_send_log where email = $1 and created_at > $2', [opts.email, since]);
  const perIp = opts.ip
    ? await one<{ n: number }>('select count(*)::int as n from code_send_log where ip = $1 and created_at > $2', [opts.ip, since])
    : { n: 0 };
  if ((perEmail?.n ?? 0) >= LIMITS.maxCodeSendsPerHour || (perIp?.n ?? 0) >= LIMITS.maxCodeSendsPerIpHour) {
    throw tooMany('Too many codes requested. Please try again later.');
  }

  await q(
    `update email_codes set invalidated_at = $3 where email = $1 and purpose = $2 and consumed_at is null and invalidated_at is null`,
    [opts.email, opts.purpose, now],
  );
  const code = sixDigitCode();
  await q(
    `insert into email_codes(email, purpose, user_id, code_hash, expires_at, created_at) values ($1,$2,$3,$4,$5,$6)`,
    [opts.email, opts.purpose, opts.userId ?? null, sha256(code), new Date(now.getTime() + LIMITS.codeTtlSeconds * SECOND), now],
  );
  await q('insert into code_send_log(email, ip, created_at) values ($1,$2,$3)', [opts.email, opts.ip ?? null, now]);
  await sendEmail(opts.email, TEMPLATE[opts.purpose], { code });
  return { resendInSeconds: LIMITS.resendAfterSeconds };
}

// Checks a code. Wrong, expired and replaced codes all get the same error
// (ONB-07.4, ONB-07.5). A correct code returns a one-time ticket for the next step.
export async function verifyCode(email: string, purpose: CodePurpose, code: string) {
  const now = clock.now();
  const row = await one<{ id: string; code_hash: string; attempts: number; expires_at: Date }>(
    `select id, code_hash, attempts, expires_at from email_codes
      where email = $1 and purpose = $2 and consumed_at is null and invalidated_at is null
      order by created_at desc limit 1`,
    [email, purpose],
  );
  if (!row || row.expires_at <= now || row.attempts >= LIMITS.maxCodeAttempts) throw badRequest('INVALID_CODE', INVALID_CODE);
  if (row.code_hash !== sha256(code)) {
    await q('update email_codes set attempts = attempts + 1 where id = $1', [row.id]);
    throw badRequest('INVALID_CODE', INVALID_CODE);
  }
  const ticket = randomToken();
  await q(
    'update email_codes set consumed_at = $2, ticket_hash = $3, ticket_expires_at = $4 where id = $1',
    [row.id, now, sha256(ticket), new Date(now.getTime() + 30 * MINUTE)],
  );
  return ticket;
}

export async function spendTicket(ticket: string, purpose: CodePurpose) {
  const now = clock.now();
  const row = await one<{ id: string; email: string; user_id: string | null }>(
    `update email_codes set ticket_used_at = $3
      where ticket_hash = $1 and purpose = $2 and ticket_used_at is null and ticket_expires_at > $3
      returning id, email, user_id`,
    [sha256(ticket), purpose, now],
  );
  if (!row) throw badRequest('TICKET_INVALID', 'This step has expired. Please start again.');
  return row;
}
