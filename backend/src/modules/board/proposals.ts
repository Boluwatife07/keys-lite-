import { one, q, tx } from '../../db/pool.js';
import { clock, DAY } from '../../lib/clock.js';
import { notify } from '../../lib/notify.js';
import { person } from '../../lib/people.js';
import { announce, broadcast, committeeIds, occupy, protectSeat, type Board, type SeatRow } from './service.js';

/** Everyone who may vote: committee members, minus the subject of a removal (VOT-04.3). */
export async function eligibleVoters(p: { board_id: string; type: string; subject_id: string }) {
  const ids = await committeeIds(p.board_id);
  return p.type === 'remove' ? ids.filter((i) => i !== p.subject_id) : ids;
}

export async function tally(proposalId: string) {
  const r = await one<{ yes: number; no: number }>(
    `select count(*) filter (where choice = 'yes')::int as yes, count(*) filter (where choice = 'no')::int as no from proposal_votes where proposal_id = $1`,
    [proposalId],
  );
  return r!;
}

/**
 * VOT-05.3 / VOT-05.4: closes early when more than half of eligible voters
 * cast the same vote; at 7 days only cast votes count, ties (and 0-0) pass.
 */
export async function evaluate(proposalId: string) {
  const p = await one<any>('select * from proposals where id = $1', [proposalId]);
  if (!p || p.status !== 'pending') return p?.status;
  const eligible = (await eligibleVoters(p)).length;
  const { yes, no } = await tally(proposalId);
  let result: 'approved' | 'declined' | undefined;
  if (yes * 2 > eligible) result = 'approved';
  else if (no * 2 > eligible) result = 'declined';
  else if (p.closes_at <= clock.now()) result = yes >= no ? 'approved' : 'declined';
  if (!result) return 'pending';
  return result === 'approved' ? apply(p) : decline(p);
}

async function finish(p: any, status: string, note?: string) {
  await q(`update proposals set status = $2, outcome_note = $3, closed_at = $4 where id = $1 and status = 'pending'`, [p.id, status, note ?? null, clock.now()]);
}

async function decline(p: any, note?: string) {
  await finish(p, 'declined', note);
  if (p.application_id) await q(`update board_applications set status = 'declined' where id = $1`, [p.application_id]);
  const msg = {
    join: 'Sorry, your request to join the committee was declined',
    reassign: 'The request to reassign the role was declined by the committee board',
    remove: 'The request to remove a member was declined by the committee board',
  }[p.type as 'join' | 'reassign' | 'remove'];
  for (const u of new Set([p.creator_id, p.subject_id])) await notify(u, 'proposal_result', null, { type: 'proposal', id: p.id }, { result: 'declined', message: msg });
  return 'declined';
}

async function apply(p: any): Promise<string> {
  const board = (await one<Board>('select * from boards where id = $1', [p.board_id]))!;
  const done = await tx(async (c) => {
    const notes: { id: string; text: string }[] = [];
    if (p.type === 'join') {
      const already = await one('select 1 from board_seats where occupant_id = $1', [p.subject_id], c);
      if (already) return { status: 'no_longer_applicable' as const };
      if (!(await occupy(c, p.seat_id, p.subject_id))) return { status: 'declined' as const, note: 'NEW_SEAT_PROTECTION' };
      await q(`update board_applications set status = 'added' where id = $1`, [p.application_id], c);
      await q(`update board_applications set status = 'cancelled' where user_id = $1 and status = 'pending'`, [p.subject_id], c);
      await protectSeat(c, p.seat_id, p.id);
      const seat = (await one<SeatRow>('select * from board_seats where id = $1', [p.seat_id], c))!;
      notes.push(await announce(c, board, 'new_member', p.subject_id, seat.role));
      return { status: 'approved' as const, notes, champion: seat.kind === 'champion' };
    }
    const current = await one<SeatRow>('select * from board_seats where occupant_id = $1', [p.subject_id], c);
    if (!current || current.id !== p.from_seat_id) return { status: 'no_longer_applicable' as const };
    if (p.type === 'remove') {
      await q('update board_seats set occupant_id = null, occupied_at = null where id = $1', [current.id], c);
      await q(`update proposals set status = 'no_longer_applicable', closed_at = $2 where status = 'pending' and subject_id = $1 and id <> $3`, [p.subject_id, clock.now(), p.id], c);
      notes.push(await announce(c, board, 'member_removal', p.subject_id, current.role));
      return { status: 'approved' as const, notes };
    }
    // Reassign: into an empty seat, or swap with its holder (VOT-03.3).
    const target = (await one<SeatRow>('select * from board_seats where id = $1', [p.seat_id], c))!;
    if ((target.occupant_id ?? null) !== (p.swap_with_id ?? null)) return { status: 'no_longer_applicable' as const };
    const now = clock.now();
    await q('update board_seats set occupant_id = null, occupied_at = null where id = any($1)', [[current.id, target.id]], c);
    await q('update board_seats set occupant_id = $2, occupied_at = $3, active = true where id = $1', [target.id, p.subject_id, now], c);
    notes.push(await announce(c, board, 'role_change', p.subject_id, target.role));
    if (p.swap_with_id) {
      await q('update board_seats set occupant_id = $2, occupied_at = $3 where id = $1', [current.id, p.swap_with_id, now], c);
      notes.push(await announce(c, board, 'role_change', p.swap_with_id, current.role));
    }
    return { status: 'approved' as const, notes };
  });
  if (done.status !== 'approved') {
    if (done.status === 'declined') return decline(p, done.note);
    await finish(p, 'no_longer_applicable');
    return 'no_longer_applicable';
  }
  await finish(p, 'approved');
  const subject = await person(p.subject_id);
  const msg = {
    join: (done as any).champion ? "Congratulations! You've been appointed as a community champion." : 'Congratulations! Your request to become a committee member has been approved.',
    reassign: `${subject?.name ?? 'The member'} has been reassigned by the committee board.`,
    remove: "You've been voted out of the Board. Your committee role has ended following a community vote. Thank you for your service.",
  }[p.type as 'join' | 'reassign' | 'remove'];
  for (const u of new Set([p.creator_id, p.subject_id])) await notify(u, 'proposal_result', null, { type: 'proposal', id: p.id }, { result: 'approved', message: msg });
  await broadcast(board, done.notes ?? []);
  return 'approved';
}

/** Job: close proposals at 7 days; remind non-voters 24 hours before (VOT-06.2). */
export async function proposalJobs() {
  const now = clock.now();
  const due = await q<{ id: string }>(`select id from proposals where status = 'pending' and closes_at <= $1`, [now]);
  for (const d of due) await evaluate(d.id);
  const soon = await q<any>(
    `update proposals set reminded_at = $1 where status = 'pending' and reminded_at is null and closes_at <= $2 returning *`,
    [now, new Date(now.getTime() + DAY)],
  );
  for (const p of soon) {
    const voted = new Set((await q<{ voter_id: string }>('select voter_id from proposal_votes where proposal_id = $1', [p.id])).map((r) => r.voter_id));
    for (const v of await eligibleVoters(p)) if (!voted.has(v)) await notify(v, 'proposal_reminder', null, { type: 'proposal', id: p.id });
  }
  return { closed: due.length, reminded: soon.length };
}
