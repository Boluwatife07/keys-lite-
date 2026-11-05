import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { q } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { clock, DAY } from '../../lib/clock.js';
import { communityOf } from '../../lib/people.js';
import { cover, PLATFORMS, ukDay, ukTime, type Event } from '../events/service.js';
import { canSee } from '../updates/routes.js';

/**
 * CAL-01: one calendar any feature can feed. Each item type registers its
 * colour, time, title, subtitle and what a tap opens. Phase 1 registers
 * Updates (red) and Events (teal); Services (green) arrive with bookings.
 */
export const ITEM_TYPES = {
  event: { color: '#1C8C86', label: 'Event' },
  update: { color: '#D92D20', label: 'Update' },
  service: { color: '#21AE48', label: 'Service' },
} as const;
type ItemType = keyof typeof ITEM_TYPES;

export interface CalendarItem {
  type: ItemType; color: string; id: string; title: string; subtitle: string; at: Date; endAt: Date | null; day: string;
  time: string; imageUrl: string | null; open: { type: string; id: string };
}

/** CAL-04.2: events for ticket holders, host, co-hosts and volunteers. */
async function eventItems(viewer: string, from: Date, to: Date): Promise<CalendarItem[]> {
  const rows = await q<Event>(
    `select distinct e.* from events e
      where e.status = 'live' and e.start_at >= $2 and e.start_at < $3
        and (e.host_id = $1
          or exists (select 1 from tickets t where t.event_id = e.id and t.user_id = $1 and t.status = 'active')
          or exists (select 1 from event_cohosts c where c.event_id = e.id and c.user_id = $1 and c.status = 'accepted')
          or exists (select 1 from event_volunteers v where v.event_id = e.id and v.user_id = $1 and v.status = 'active'))
      order by e.start_at`,
    [viewer, from, to],
  );
  const out: CalendarItem[] = [];
  for (const e of rows) {
    const c = await cover(e.id);
    out.push({
      type: 'event', color: ITEM_TYPES.event.color, id: e.id, title: e.title,
      subtitle: `${ukTime(e.start_at!)} - ${ukTime(e.end_at!)} • ${e.format === 'online' ? (e.platform ? PLATFORMS[e.platform] : 'Online') : e.location_name ?? ''}`,
      at: e.start_at!, endAt: e.end_at, day: ukDay(e.start_at!), time: ukTime(e.start_at!), imageUrl: c?.kind === 'photo' ? c.url : null,
      open: { type: 'event', id: e.id },
    });
  }
  return out;
}

/** CAL-04.1: live updates in the viewer's audience, on the day they were posted. */
async function updateItems(viewer: string, from: Date, to: Date): Promise<CalendarItem[]> {
  const rows = await q<any>(
    `select * from updates where community_id = $1 and status = 'live' and created_at >= $2 and created_at < $3
       and not exists (select 1 from update_hides h where h.user_id = $4 and h.update_id = updates.id) order by created_at`,
    [await communityOf(viewer), from, to, viewer],
  );
  const out: CalendarItem[] = [];
  for (const u of rows) {
    if (!(await canSee(u, viewer))) continue;
    out.push({
      type: 'update', color: ITEM_TYPES.update.color, id: u.id, title: u.title, subtitle: u.details.slice(0, 80),
      at: u.created_at, endAt: null, day: ukDay(u.created_at), time: ukTime(u.created_at), imageUrl: null, open: { type: 'update', id: u.id },
    });
  }
  return out;
}

export async function calendarItems(viewer: string, from: Date, to: Date, types: ItemType[] = ['event', 'update']) {
  const all = [
    ...(types.includes('event') ? await eventItems(viewer, from, to) : []),
    ...(types.includes('update') ? await updateItems(viewer, from, to) : []),
  ];
  return all.sort((a, b) => +a.at - +b.at);
}

export async function calendarRoutes(app: FastifyInstance) {
  // CAL-03: a range (the month view asks for one month at a time).
  app.get('/calendar', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      from: z.string().datetime({ offset: true }),
      to: z.string().datetime({ offset: true }),
      types: z.string().default('event,update'),
    }).parse(req.query);
    const types = b.types.split(',').filter((t): t is ItemType => t in ITEM_TYPES);
    const items = await calendarItems(u.id, new Date(b.from), new Date(b.to), types);
    return { types: ITEM_TYPES, items, today: ukDay(clock.now()) };
  });

  // CAL-03.3: "Go to nearest schedule" from a day.
  app.get('/calendar/nearest', async (req) => {
    const u = requireUser(req);
    const { from, types } = z.object({ from: z.string().datetime({ offset: true }), types: z.string().default('event,update') }).parse(req.query);
    const list = types.split(',').filter((t): t is ItemType => t in ITEM_TYPES);
    const start = new Date(from);
    const items = await calendarItems(u.id, start, new Date(start.getTime() + 365 * DAY), list);
    return { item: items[0] ?? null };
  });

  // CAL-02: Home "Upcoming": the nearest day within 4 weeks that has items.
  app.get('/calendar/upcoming', async (req) => {
    const u = requireUser(req);
    const now = clock.now();
    const startOfToday = new Date(`${ukDay(now)}T00:00:00Z`);
    // UK midnight can differ from UTC by an hour; widen and filter by UK day.
    const items = (await calendarItems(u.id, new Date(startOfToday.getTime() - DAY), new Date(now.getTime() + 28 * DAY)))
      .filter((i) => i.day >= ukDay(now) && (i.type !== 'event' || (i.endAt ?? i.at) > now));
    if (!items.length) return { day: null, items: [], today: false, more: 0 };
    const day = items[0].day;
    const onDay = items.filter((i) => i.day === day);
    return { day, today: day === ukDay(now), items: onDay.slice(0, 2), more: Math.max(0, onDay.length - 2) };
  });
}

