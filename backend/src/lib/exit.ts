import { one } from '../db/pool.js';
import { clock } from './clock.js';
import { seatOf } from './people.js';

export interface ExitItem { code: string; message: string }

/**
 * Member exit pre-check (PRF-11.5, PRF-18.5, CBM-13.4).
 * - Changing address: a committee seat is a warning (the seat is revoked).
 * - Deactivating: a committee seat blocks until the member exits the board.
 * - Hosting an upcoming event with tickets issued, or being a club
 *   President, blocks both (checked once those tables exist).
 */
export async function exitCheck(userId: string, reason: 'move' | 'deactivate') {
  const blockers: ExitItem[] = [];
  const warnings: ExitItem[] = [];
  const seat = await seatOf(userId);
  if (seat) {
    const item = {
      code: 'COMMITTEE_SEAT',
      message: reason === 'move'
        ? `Your ${seat.kind === 'champion' ? 'champion' : 'committee'} role (${seat.role}) will be revoked.`
        : `You hold the ${seat.role} role. Exit the committee board before deactivating your account.`,
    };
    (reason === 'move' ? warnings : blockers).push(item);
  }
  if ((await one<{ t: string | null }>(`select to_regclass('events')::text as t`))?.t) {
    const ev = await one<{ title: string }>(
      `select e.title from events e where e.host_id = $1 and e.status = 'live' and e.end_at > $2
         and exists (select 1 from tickets t where t.event_id = e.id and t.status = 'active') limit 1`,
      [userId, clock.now()],
    );
    if (ev) blockers.push({ code: 'EVENT_WITH_TICKETS', message: `You are hosting "${ev.title}" and tickets have been issued. Cancel the event or pass it on first.` });
  }
  if ((await one<{ t: string | null }>(`select to_regclass('club_members')::text as t`))?.t) {
    const club = await one<{ name: string }>(
      `select c.name from club_members m join clubs c on c.id = m.club_id where m.user_id = $1 and m.role = 'president' and c.status <> 'closed' limit 1`,
      [userId],
    );
    if (club) blockers.push({ code: 'CLUB_PRESIDENT', message: `You are the President of ${club.name}. Transfer ownership or close the club first.` });
  }
  if (reason === 'move') {
    warnings.push(
      { code: 'UNVERIFIED', message: 'Your profile will be unverified until you verify your new address.' },
      { code: 'LEAVE_COMMUNITY', message: 'You will no longer see posts, events, clubs and members of your current community.' },
    );
  }
  return { blockers, warnings };
}
