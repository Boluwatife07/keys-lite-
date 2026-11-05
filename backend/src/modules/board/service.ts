import type pg from 'pg';
import { one, q, tx, type Db } from '../../db/pool.js';
import { clock, DAY } from '../../lib/clock.js';
import { notify } from '../../lib/notify.js';
import { person } from '../../lib/people.js';
import { leaveUpdateChats } from '../chat/service.js';
import { passEvents } from '../events/service.js';

export const PRESET_ROLES = [
  'Chair', 'Vice Chair', 'Treasurer', 'Secretary', 'Projects Lead', 'Events Lead', 'Clubs Lead', 'Communications Lead',
] as const;

// Phase 1 role descriptions (no wallet or project sign-off powers yet, CBM-20.1).
export const ROLE_ABOUT: Record<string, string[]> = {
  Chair: ['Leads committee meetings and sets priorities with the board', 'Manages available committee and champion seats', 'Speaks for the committee to residents'],
  'Vice Chair': ['Supports the Chair and steps in when the Chair is away', 'Takes over as Chair if the Chair leaves the board'],
  Treasurer: ['Keeps track of community money and spending', 'Shares clear money updates with residents'],
  Secretary: ['Keeps notes of committee decisions', 'Makes sure residents get the information they need'],
  'Projects Lead': ['Gathers ideas for community improvements', 'Keeps residents updated on progress'],
  'Events Lead': ['Plans and runs community events', 'Works with volunteers and hosts'],
  'Clubs Lead': ['Supports clubs in the community', 'Helps residents start new clubs'],
  'Communications Lead': ['Posts committee updates and announcements', 'Keeps residents informed and engaged'],
  'Committee Member': ['Takes part in committee decisions and votes on proposals'],
  Champion: ['Represents residents and helps the committee reach neighbours', 'Does not vote on proposals'],
};

export const TIERS = [
  { tier: 1, min: 0, max: 99, committee: 8, champions: 10 },
  { tier: 2, min: 100, max: 399, committee: 12, champions: 14 },
  { tier: 3, min: 400, max: 699, committee: 16, champions: 18 },
  { tier: 4, min: 700, max: null, committee: 20, champions: 22 },
] as const;

export const VOTE_MIN_BOARD = 5;    // VOT-05.1: proposals need 5+ committee members (any tier)
export const VOTE_DAYS = 7;

export const tierFor = (residents: number) => [...TIERS].reverse().find((t) => residents >= t.min)!;

export interface Board { id: string; community_id: string; tier: number; tier_up_at: Date | null }
export interface SeatRow { id: string; board_id: string; kind: 'preset' | 'extra' | 'champion'; role: string; position: number; active: boolean; occupant_id: string | null; occupied_at: Date | null }

export async function residentCount(communityId: string, db?: Db) {
  return (await one<{ n: number }>('select count(*)::int as n from memberships where community_id = $1', [communityId], db))!.n;
}

export async function boardFor(communityId: string, db?: Db) {
  return one<Board>('select * from boards where community_id = $1', [communityId], db);
}

/** Make sure seat rows exist for the tier: extra committee seats and champion seats start inactive. */
export async function syncSeats(boardId: string, tier: number, db: Db) {
  const t = TIERS[tier - 1];
  for (let i = 0; i < t.committee - PRESET_ROLES.length; i++) {
    await q(`insert into board_seats(board_id, kind, role, position, active) values ($1,'extra','Committee Member',$2,false) on conflict do nothing`, [boardId, i], db);
  }
  for (let i = 0; i < t.champions; i++) {
    await q(`insert into board_seats(board_id, kind, role, position, active) values ($1,'champion','Champion',$2,false) on conflict do nothing`, [boardId, i], db);
  }
}

/** Seats usable under the current tier. After a tier drop, seats above the allowance are not refilled (CBM-12.4). */
export function withinAllowance(seat: SeatRow, tier: number) {
  const t = TIERS[tier - 1];
  if (seat.kind === 'preset') return true;
  if (seat.kind === 'extra') return seat.position < t.committee - PRESET_ROLES.length;
  return seat.position < t.champions;
}

export async function seats(boardId: string, db?: Db) {
  return q<SeatRow>(`select * from board_seats where board_id = $1 order by case kind when 'preset' then 0 when 'extra' then 1 else 2 end, position`, [boardId], db);
}

export async function committeeIds(boardId: string, db?: Db) {
  return (await q<{ occupant_id: string }>(
    `select occupant_id from board_seats where board_id = $1 and kind <> 'champion' and occupant_id is not null`, [boardId], db,
  )).map((r) => r.occupant_id);
}

/** CBM-12: recompute the tier; on a rise, unlock seats and tell the Chair. */
export async function refreshTier(board: Board) {
  const tier = tierFor(await residentCount(board.community_id)).tier;
  if (tier === board.tier) return board;
  const up = tier > board.tier;
  await tx(async (c) => {
    await q('update boards set tier = $2, tier_up_at = case when $3 then $4 else tier_up_at end where id = $1', [board.id, tier, up, clock.now()], c);
    await syncSeats(board.id, tier, c);
  });
  if (up) {
    const chair = await one<{ occupant_id: string }>(`select occupant_id from board_seats where board_id = $1 and role = 'Chair' and occupant_id is not null`, [board.id]);
    if (chair) await notify(chair.occupant_id, 'tier_up', null, { type: 'board', id: board.id }, { tier });
  }
  return (await one<Board>('select * from boards where id = $1', [board.id]))!;
}

export async function announce(c: Db, board: Board, type: 'new_member' | 'role_change' | 'board_exit' | 'member_removal', subjectId: string, role: string, reason?: string) {
  const p = (await person(subjectId, c))!;
  const text = {
    new_member: role === 'Champion' ? `${p.name} has just joined the board as a Champion.` : `${p.name} has just joined the committee board as the ${role}.`,
    role_change: `${p.name} has been assigned as ${role}`,
    board_exit: `${p.name} has exited the committee board, relieving their role as the ${role}.`,
    member_removal: `${p.name} has been removed from the committee board, relieving their role as the ${role}.`,
  }[type];
  const a = (await one<{ id: string }>(
    `insert into board_announcements(board_id, type, subject_id, role, text, reason, created_at) values ($1,$2,$3,$4,$5,$6,$7) returning id`,
    [board.id, type, subjectId, role, text, reason ?? null, clock.now()], c,
  ))!;
  return { id: a.id, text };
}

/** Sends board announcement notifications to everyone in the community (VOT-06.4). */
export async function broadcast(board: Board, announcementIds: { id: string; text: string }[]) {
  const members = await q<{ user_id: string }>('select user_id from memberships where community_id = $1', [board.community_id]);
  for (const a of announcementIds) for (const m of members) await notify(m.user_id, 'board_announcement', null, { type: 'announcement', id: a.id }, { text: a.text });
}

/** Puts [userId] in an empty seat; false if someone got there first (CBM-05.3). */
export async function occupy(c: pg.PoolClient, seatId: string, userId: string) {
  const r = await one(
    `update board_seats set occupant_id = $2, occupied_at = $3 where id = $1 and occupant_id is null and active returning id`,
    [seatId, userId, clock.now()], c,
  );
  return !!r;
}

/** After [seatId] is filled, other open join proposals for it are declined (CBM-06.4, VOT-05.6). */
export async function protectSeat(c: pg.PoolClient, seatId: string, exceptProposal?: string) {
  const losers = await q<{ id: string; application_id: string | null; subject_id: string }>(
    `update proposals set status = 'declined', outcome_note = 'NEW_SEAT_PROTECTION', closed_at = $3
      where seat_id = $1 and type = 'join' and status = 'pending' and id <> coalesce($2::uuid, '00000000-0000-0000-0000-000000000000')
      returning id, application_id, subject_id`,
    [seatId, exceptProposal ?? null, clock.now()], c,
  );
  for (const l of losers) if (l.application_id) await q(`update board_applications set status = 'declined' where id = $1`, [l.application_id], c);
  return losers;
}

/**
 * The resident leaves their seat: exit, removal, moving home or deactivating.
 * Their pending applications are cancelled and proposals about them become
 * "No longer applicable" (CBM-19.2, VOT-05.7). A leaving Chair hands over to
 * the Vice Chair; with no Vice Chair the Chair seat is left empty (CBM-14).
 */
export async function leaveBoard(userId: string, opts: { reason?: string; why: 'exit' | 'removed' | 'left_community' }) {
  const out = await tx(async (c) => {
    const notes: { id: string; text: string }[] = [];
    await q(`update board_applications set status = 'cancelled' where user_id = $1 and status = 'pending'`, [userId], c);
    const nlaWhere = opts.why === 'left_community' ? '(subject_id = $1 or creator_id = $1)' : 'subject_id = $1';
    await q(`update proposals set status = 'no_longer_applicable', closed_at = $2 where status = 'pending' and ${nlaWhere}`, [userId, clock.now()], c);
    const seat = await one<SeatRow>('select * from board_seats where occupant_id = $1', [userId], c);
    if (!seat) return { board: undefined, notes };
    const board = (await one<Board>('select * from boards where id = $1', [seat.board_id], c))!;
    await q('update board_seats set occupant_id = null, occupied_at = null where id = $1', [seat.id], c);
    if (opts.why !== 'removed') notes.push(await announce(c, board, 'board_exit', userId, seat.role, opts.reason));
    if (seat.role === 'Chair') {
      // Vice Chair steps up (CBM-14.1). With no Vice Chair the Chair seat stays
      // empty and is filled the normal way (Dorcas, 5 Nov 2026).
      const next = await one<SeatRow>(`select * from board_seats where board_id = $1 and role = 'Vice Chair' and occupant_id is not null`, [board.id], c);
      if (next) {
        await q('update board_seats set occupant_id = null, occupied_at = null where id = $1', [next.id], c);
        await q('update board_seats set occupant_id = $2, occupied_at = $3 where id = $1', [seat.id, next.occupant_id, clock.now()], c);
        notes.push(await announce(c, board, 'role_change', next.occupant_id!, 'Chair'));
      }
    }
    return { board, notes, seat };
  });
  if (out.board) await broadcast(out.board, out.notes);
  // EVT-27.2: administrative events of a removed member pass to the Chair.
  if (out.board && opts.why === 'removed') {
    const chair = await one<{ occupant_id: string }>(`select occupant_id from board_seats where board_id = $1 and role = 'Chair' and occupant_id is not null`, [out.board.id]);
    if (chair && chair.occupant_id !== userId) await passEvents(userId, chair.occupant_id, { category: 'administrative' });
  }
  // UCH-04.2: leaving the board (or the community) also leaves update chats.
  const community = out.board?.community_id ?? (await one<{ community_id: string }>('select community_id from memberships where user_id = $1', [userId]))?.community_id;
  if (community) await leaveUpdateChats(userId, community);
  return out;
}

export const closesAt = () => new Date(clock.now().getTime() + VOTE_DAYS * DAY);
