import { one, q, type Db } from '../db/pool.js';
import { clock } from './clock.js';
import { notFound } from './errors.js';

/** The resident's top-level community, or undefined before onboarding ends. */
export async function communityOf(userId: string, db?: Db) {
  return (await one<{ community_id: string }>('select community_id from memberships where user_id = $1', [userId], db))?.community_id;
}

export async function requireCommunity(userId: string) {
  const c = await communityOf(userId);
  if (!c) throw notFound('Join a community first.');
  return c;
}

/** True if either has blocked the other (two-way hide, PRF-05.3). */
export async function areBlocked(a: string, b: string, db?: Db) {
  return !!(await one('select 1 from blocks where (user_id = $1 and target_id = $2) or (user_id = $2 and target_id = $1)', [a, b], db));
}

/** SQL condition: column holds someone the viewer ($viewer) must not see. */
export const hiddenAuthorSql = (col: string, viewerParam: string) => `(
  exists (select 1 from blocks b where (b.user_id = ${viewerParam} and b.target_id = ${col}) or (b.user_id = ${col} and b.target_id = ${viewerParam}))
)`;
export const mutedAuthorSql = (col: string, viewerParam: string, nowParam: string) =>
  `exists (select 1 from mutes m where m.user_id = ${viewerParam} and m.target_id = ${col} and m.until > ${nowParam})`;

export async function isMuted(viewer: string, target: string) {
  return !!(await one('select 1 from mutes where user_id = $1 and target_id = $2 and until > $3', [viewer, target, clock.now()]));
}

export interface Seat { role: string; kind: 'preset' | 'extra' | 'champion' }

export async function seatOf(userId: string, db?: Db): Promise<Seat | undefined> {
  return one<Seat>('select role, kind from board_seats where occupant_id = $1', [userId], db);
}
/** Committee member = holds a preset or extra seat. Champions are not committee. */
export async function isCommittee(userId: string, db?: Db) {
  const s = await seatOf(userId, db);
  return !!s && s.kind !== 'champion';
}

export interface Person {
  id: string;
  name: string;
  firstName: string;
  photoUrl: string | null;
  verified: boolean;
  role: string | null;     // "Chair", "Champion"... shown as the label next to the name
}

/** Author cards for a list of users (FED-01.2: role label or "Unverified"). */
export async function people(ids: string[], db?: Db): Promise<Map<string, Person>> {
  const uniq = [...new Set(ids.filter(Boolean))];
  if (!uniq.length) return new Map();
  const rows = await q<any>(
    `select u.id, u.first_name, u.last_name, u.photo_url, u.verification_status, s.role
       from users u left join board_seats s on s.occupant_id = u.id where u.id = any($1)`,
    [uniq], db,
  );
  return new Map(rows.map((r) => [r.id, {
    id: r.id,
    name: `${r.first_name} ${r.last_name}`.trim(),
    firstName: r.first_name,
    photoUrl: r.photo_url,
    verified: r.verification_status === 'verified',
    role: r.role ?? null,
  }]));
}

export async function person(id: string, db?: Db) {
  return (await people([id], db)).get(id);
}
