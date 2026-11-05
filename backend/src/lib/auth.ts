import type { FastifyRequest } from 'fastify';
import { one, q } from '../db/pool.js';
import { sha256, randomToken } from './crypto.js';
import { unauthorized, verificationRequired } from './errors.js';
import { clock } from './clock.js';

export interface AuthUser {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  verification_status: 'unverified' | 'under_review' | 'verified';
  onboarding_step: string;
  session_id: string;
}

declare module 'fastify' {
  interface FastifyRequest { authUser?: AuthUser }
}

export async function createSession(userId: string, device?: string) {
  const token = randomToken();
  await q('insert into sessions(user_id, token_hash, device) values ($1,$2,$3)', [userId, sha256(token), device ?? null]);
  return token;
}

export async function loadUser(req: FastifyRequest): Promise<AuthUser | undefined> {
  const h = req.headers.authorization;
  if (!h?.startsWith('Bearer ')) return undefined;
  const row = await one<AuthUser>(
    `select u.id, u.email, u.first_name, u.last_name, u.verification_status, u.onboarding_step, s.id as session_id
       from sessions s join users u on u.id = s.user_id
      where s.token_hash = $1 and s.revoked_at is null and u.deactivated_at is null`,
    [sha256(h.slice(7))],
  );
  if (row) await q('update sessions set last_seen_at = $2 where id = $1', [row.session_id, clock.now()]);
  return row;
}

export function requireUser(req: FastifyRequest): AuthUser {
  if (!req.authUser) throw unauthorized();
  return req.authUser;
}

// BE-10.3: the single server-side check for actions unverified residents
// cannot take (AVW-09.1). Always re-read status so a fresh pass applies at once.
export async function requireVerified(req: FastifyRequest): Promise<AuthUser> {
  const u = requireUser(req);
  const row = await one<{ verification_status: string }>('select verification_status from users where id = $1', [u.id]);
  if (row?.verification_status !== 'verified') throw verificationRequired();
  return u;
}
