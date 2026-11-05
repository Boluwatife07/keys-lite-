import { randomBytes } from 'node:crypto';
import { one, q, type Db } from '../../db/pool.js';
import { clock } from '../../lib/clock.js';
import { notify, notifyAndEmail } from '../../lib/notify.js';
import { people, person } from '../../lib/people.js';
import { addMember, removeMember, system } from '../chat/service.js';
import { shareLink } from '../links/routes.js';
import { sendEmail } from '../../services/email.js';

export const TITLE_MAX = 60;
export const DESCRIPTION_MAX = 500;
export const MEDIA_MAX = 6;
export const TAGS_MAX = 3;
export const CAPACITY_MIN = 10;
export const COHOSTS_MAX = 5;
export const FEEDBACK_MAX = 400;
// EVT-01.2 category chips; an event's tags come from this list.
export const EVENT_TAGS = ['Music', 'Culture', 'Networking', 'Food & Drink', 'Fashion', 'Education', 'Tech', 'Social', 'Others'] as const;
export const CANCEL_REASONS = [
  'Low number of attendees / poor turnout',
  'Personal emergency or change of plans',
  'Technical issue',
  'Posted by mistake',
  'Other (please specify)',
] as const;
export const PLATFORMS = { zoom: 'Zoom', google_meet: 'Google meet', facebook_live: 'Facebook live', other: 'Other' } as const;

export interface Event {
  id: string; community_id: string; host_id: string | null; category: 'residential' | 'administrative' | 'club'; club_id: string | null;
  audience: 'all' | 'members'; title: string; description: string; start_at: Date | null; end_at: Date | null; format: 'physical' | 'online' | null;
  location_place_id: string | null; location_name: string | null; location_address: string | null; lat: number | null; lng: number | null;
  platform: keyof typeof PLATFORMS | null; link: string | null; meeting_id: string | null; meeting_password: string | null; tags: string[];
  capacity: number | null; accept_volunteers: boolean; volunteer_cap: number | null; status: 'draft' | 'live' | 'cancelled';
  cancel_reason: string | null; cancel_text: string | null; chat_id: string | null; launched_at: Date | null; cancelled_at: Date | null;
  reminder_sent_at: Date | null; draft_reminder_at: Date | null; completed_notified_at: Date | null; feedback_requested_at: Date | null;
  created_at: Date; updated_at: Date;
}

export type EventRole = 'host' | 'cohost' | 'cohost_invited' | 'volunteer' | null;

/** "2026-11-05" in UK time, for single-day and event-day rules. */
export const ukDay = (d: Date) => d.toLocaleDateString('en-CA', { timeZone: 'Europe/London' });
export const ukTime = (d: Date) => d.toLocaleTimeString('en-GB', { timeZone: 'Europe/London', hour: 'numeric', minute: '2-digit', hour12: true }).replace(' ', '').toLowerCase();
export const ukDate = (d: Date) => d.toLocaleDateString('en-GB', { timeZone: 'Europe/London', weekday: 'short', day: 'numeric', month: 'short' });

export const isCompleted = (e: Event) => e.status === 'live' && !!e.end_at && e.end_at <= clock.now();
export const displayStatus = (e: Event) => (isCompleted(e) ? 'completed' : e.status);

export async function roleFor(e: Event, userId: string, db?: Db): Promise<EventRole> {
  if (e.host_id === userId) return 'host';
  const c = await one<{ status: string }>('select status from event_cohosts where event_id = $1 and user_id = $2', [e.id, userId], db);
  if (c?.status === 'accepted') return 'cohost';
  if (c?.status === 'invited') return 'cohost_invited';
  if (await one(`select 1 from event_volunteers where event_id = $1 and user_id = $2 and status = 'active'`, [e.id, userId], db)) return 'volunteer';
  return null;
}
export const canManageEvent = (r: EventRole) => r === 'host' || r === 'cohost';
export const canScan = (r: EventRole) => r === 'host' || r === 'cohost' || r === 'volunteer';

/** Who can see the event: same community; drafts only for hosts; members-only club events for members. */
export async function canSeeEvent(e: Event, viewer: string, communityId: string | undefined) {
  if (e.community_id !== communityId) return false;
  const role = await roleFor(e, viewer);
  if (e.status === 'draft') return role === 'host' || role === 'cohost' || role === 'cohost_invited';
  if (e.audience === 'members' && e.club_id && !role) {
    const member = await one('select 1 from club_members where club_id = $1 and user_id = $2', [e.club_id, viewer]);
    const ticket = await one('select 1 from tickets where event_id = $1 and user_id = $2', [e.id, viewer]);
    return !!member || !!ticket;
  }
  return true;
}

export async function activeTickets(eventId: string, db?: Db) {
  return (await one<{ n: number }>(`select count(*)::int as n from tickets where event_id = $1 and status = 'active'`, [eventId], db))!.n;
}

export async function ticketHolderIds(eventId: string, db?: Db) {
  return (await q<{ user_id: string }>(`select user_id from tickets where event_id = $1 and status = 'active'`, [eventId], db)).map((r) => r.user_id);
}

export async function teamIds(e: Event, db?: Db) {
  const co = await q<{ user_id: string }>(`select user_id from event_cohosts where event_id = $1 and status = 'accepted' and user_id is not null`, [e.id], db);
  return [...(e.host_id ? [e.host_id] : []), ...co.map((c) => c.user_id)];
}

/** EVT-17.1: planning chat named after the event; host and accepted co-hosts are admins. */
export async function ensureChat(e: Event, db: Db) {
  if (e.chat_id) return e.chat_id;
  const chat = (await one<{ id: string }>(
    `insert into chats(community_id, type, name, created_by, members_can_invite) values ($1,'event',$2,$3,false) returning id`,
    [e.community_id, e.title || 'Event planning', e.host_id], db,
  ))!;
  if (e.host_id) await addMember(chat.id, e.host_id, 'admin', db);
  await q('update events set chat_id = $2 where id = $1', [e.id, chat.id], db);
  return chat.id;
}

export async function cover(eventId: string, db?: Db) {
  return (await one<{ url: string; kind: string }>(
    `select m.url, m.kind from event_media em join media m on m.id = em.media_id where em.event_id = $1 order by em.position limit 1`, [eventId], db,
  )) ?? null;
}

/** Card used in lists (EVT-01.3). */
export async function eventCard(e: Event, viewer: string) {
  const [going, c, saved, club] = await Promise.all([
    activeTickets(e.id),
    cover(e.id),
    one('select 1 from event_saves where user_id = $1 and event_id = $2', [viewer, e.id]),
    e.club_id ? one<{ name: string }>('select name from clubs where id = $1', [e.club_id]) : Promise.resolve(undefined),
  ]);
  let rating = null;
  if (isCompleted(e)) {
    const r = await one<{ avg: number | null; n: number }>(`select avg(stars)::float as avg, count(stars)::int as n from event_ratings where event_id = $1 and stars is not null`, [e.id]);
    rating = { average: r?.avg ? Math.round(r.avg * 10) / 10 : null, count: r?.n ?? 0 };
  }
  return {
    id: e.id,
    title: e.title,
    category: e.category,
    clubId: e.club_id,
    clubName: club?.name ?? null,
    audience: e.audience,
    startAt: e.start_at,
    endAt: e.end_at,
    format: e.format,
    locationName: e.location_name,
    locationAddress: e.location_address,
    platform: e.platform ? PLATFORMS[e.platform] : null,
    cover: c,
    tags: e.tags,
    price: 'Free',
    going,
    capacity: e.capacity,
    soldOut: e.capacity != null && going >= e.capacity,
    status: displayStatus(e),
    saved: !!saved,
    rating,
    isMine: e.host_id === viewer,
  };
}

export async function hostsOf(e: Event) {
  const co = await q<{ id: string; user_id: string | null; external_name: string | null; status: string }>(
    `select id, user_id, external_name, status from event_cohosts where event_id = $1 order by created_at`, [e.id],
  );
  const ps = await people([...(e.host_id ? [e.host_id] : []), ...co.map((c) => c.user_id).filter(Boolean) as string[]]);
  return [
    ...(e.host_id ? [{ id: null, person: ps.get(e.host_id) ?? null, name: ps.get(e.host_id)?.name ?? 'Host', role: 'Host', external: false, status: 'accepted' }] : []),
    ...co.filter((c) => c.status !== 'declined').map((c) => ({
      id: c.id,
      person: c.user_id ? ps.get(c.user_id) ?? null : null,
      name: c.user_id ? ps.get(c.user_id)?.name ?? '' : c.external_name!,
      role: 'Co-host',
      external: !c.user_id,
      status: c.status,
    })),
  ];
}

export async function ticketView(t: any, e: Event, viewer: string) {
  const active = t.status === 'active';
  const holder = await person(t.user_id);
  return {
    id: t.id,
    eventId: e.id,
    eventTitle: e.title,
    startAt: e.start_at,
    endAt: e.end_at,
    format: e.format,
    locationName: e.location_name,
    locationAddress: e.location_address,
    platform: e.platform ? PLATFORMS[e.platform] : null,
    // Removed once cancelled (EVT-20.3).
    link: active && t.user_id === viewer ? e.link : null,
    meetingId: active && t.user_id === viewer ? e.meeting_id : null,
    meetingPassword: active && t.user_id === viewer ? e.meeting_password : null,
    qr: active ? t.code : null,
    seat: active ? String(t.seat).padStart(3, '0') : null,
    price: 'Free',
    status: t.status,
    checkedInAt: t.checked_in_at,
    holder,
    shareLink: active ? shareLink('ticket', t.id) : null,
    createdAt: t.created_at,
  };
}

export const ticketCode = () => `KEYS-${randomBytes(12).toString('base64url')}`;

/** EVT-14.2 / EVT-27.4: cancel, void tickets and tell everyone. */
export async function cancelEvent(e: Event, reason: string, text: string | null, actorId: string | null) {
  const holders = await ticketHolderIds(e.id);
  const team = await teamIds(e);
  await q(`update events set status = 'cancelled', cancel_reason = $2, cancel_text = $3, cancelled_at = $4 where id = $1`, [e.id, reason, text, clock.now()]);
  await q(`update tickets set status = 'void' where event_id = $1 and status = 'active'`, [e.id]);
  if (e.chat_id) await system(e.chat_id, 'event_cancelled', actorId, null, 'This event has been cancelled');
  for (const u of holders) {
    await notifyAndEmail(u, 'event_cancelled', actorId, { type: 'event', id: e.id }, { title: e.title }, {
      subject: `${e.title} has been canceled`,
      text: `${e.title} has been canceled by the host. Since this was a free event, no further action is required.`,
    });
  }
  for (const u of team) if (u !== actorId) await notify(u, 'event_cancelled', actorId, { type: 'event', id: e.id }, { title: e.title });
  // EVT-14.3: the host gets a confirmation email.
  const h = e.host_id ? await one<{ email: string }>('select email from users where id = $1', [e.host_id]) : undefined;
  if (h) await sendEmail(h.email, 'notice', { subject: `You've canceled ${e.title}`, text: `You've canceled ${e.title}. Ticket holders have been told.` });
}

/** EVT-27.2 / EVT-27.3: events pass to someone else when their creator loses the right. */
export async function passEvents(fromId: string, toId: string, where: { category: 'administrative' | 'club'; clubId?: string }) {
  const rows = await q<Event>(
    `select * from events where host_id = $1 and category = $2 and status <> 'cancelled' and (end_at is null or end_at > $3) and ($4::uuid is null or club_id = $4)`,
    [fromId, where.category, clock.now(), where.clubId ?? null],
  );
  for (const e of rows) {
    await q('update events set host_id = $2 where id = $1', [e.id, toId]);
    await q('delete from event_cohosts where event_id = $1 and user_id = $2', [e.id, toId]);
    if (e.chat_id) {
      await addMember(e.chat_id, toId, 'admin');
      await removeMember(e.chat_id, fromId, 'removed');
    }
  }
  return rows.length;
}
