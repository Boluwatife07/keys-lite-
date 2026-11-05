import { one, q, type Db } from '../../db/pool.js';
import { notFound } from '../../lib/errors.js';
import { addMember as addChatMember, removeMember as removeChatMember, system } from '../chat/service.js';
import { person } from '../../lib/people.js';

export interface Club {
  id: string; community_id: string; name: string; description: string; category: string; member_limit: number;
  cover_media_id: string | null; president_id: string | null; status: 'active' | 'closing' | 'closed'; closing_at: Date | null;
  closed_at: Date | null; chat_id: string | null; full_notified_at: Date | null; attempts_notified_at: Date | null; milestones: number[]; created_at: Date;
}
export type ClubRole = 'president' | 'admin' | 'member';

export async function clubOr404(id: string, communityId: string | undefined, db?: Db) {
  const c = await one<Club>('select * from clubs where id = $1', [id], db);
  if (!c || c.community_id !== communityId || c.status === 'closed') throw notFound('This club is not available.');
  return c;
}

export async function roleIn(clubId: string, userId: string, db?: Db) {
  return (await one<{ role: ClubRole }>('select role from club_members where club_id = $1 and user_id = $2', [clubId, userId], db))?.role;
}

export const canManage = (r?: ClubRole) => r === 'president' || r === 'admin';

export async function memberCount(clubId: string, db?: Db) {
  return (await one<{ n: number }>('select count(*)::int as n from club_members where club_id = $1', [clubId], db))!.n;
}

/** Clubs the user owns or admins (EVT-06.2 "Select your club"). */
export async function managedClubs(userId: string) {
  return q<{ id: string; name: string }>(
    `select c.id, c.name from clubs c join club_members m on m.club_id = c.id
      where m.user_id = $1 and m.role in ('president','admin') and c.status = 'active' order by c.name`,
    [userId],
  );
}

/** CLB-15.1: club chat membership mirrors club membership; President and admins are chat admins. */
export async function syncChat(club: Club, userId: string, role: ClubRole | null, db?: Db) {
  if (!club.chat_id) return;
  if (role) await addChatMember(club.chat_id, userId, role === 'member' ? 'member' : 'admin', db);
  else await removeChatMember(club.chat_id, userId, 'left', db);
}

export async function addToClub(club: Club, userId: string, role: ClubRole, db?: Db) {
  await q(
    `insert into club_members(club_id, user_id, role) values ($1,$2,$3) on conflict (club_id, user_id) do update set role = excluded.role`,
    [club.id, userId, role], db,
  );
  await q('delete from club_invites where club_id = $1 and user_id = $2', [club.id, userId], db);
  await syncChat(club, userId, role, db);
  if (club.chat_id && role === 'member') await system(club.chat_id, 'joined', userId, null, `${(await person(userId, db))?.name ?? 'A member'} joined`, db);
}

export async function removeFromClub(club: Club, userId: string, db?: Db) {
  await q('delete from club_members where club_id = $1 and user_id = $2', [club.id, userId], db);
  await syncChat(club, userId, null, db);
}

export async function clubMemberIds(clubId: string, db?: Db) {
  return (await q<{ user_id: string }>('select user_id from club_members where club_id = $1', [clubId], db)).map((r) => r.user_id);
}
