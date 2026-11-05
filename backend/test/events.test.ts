import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { one, q } from '../src/db/pool.js';
import { clock, DAY, HOUR } from '../src/lib/clock.js';
import { eventJobs } from '../src/modules/events/routes.js';
import { call, eventBasics, joinStreet, me, pioneerStreet, placeId, PNG, seat, setup, teardown, upload, verify } from './helpers.js';

let host: string; let ben: string; let cara: string; let dan: string; let unverified: string;
let benId: string; let caraId: string; let danId: string;

const inDays = (d: number, hour = 18) => {
  const t = new Date(clock.now().getTime() + d * DAY);
  t.setUTCHours(hour, 0, 0, 0);
  return t.toISOString();
};
const notes = async (t: string) => (await call('GET', '/notifications', { token: t })).body.notifications.map((n: any) => n.type);

async function draft(token: string, extra: Record<string, unknown> = {}) {
  return call('POST', '/events', { token, body: { category: 'residential', title: 'Street party', ...extra } });
}
async function liveEvent(token: string, extra: Record<string, unknown> = {}) {
  const pid = await placeId(token, '1 Maple Road');
  const d = await draft(token, { ...(await eventBasics(token)), startAt: inDays(3), endAt: inDays(3, 21), format: 'physical', placeId: pid, tags: ['Social'], ...extra });
  const r = await call('POST', `/events/${d.body.event.id}/launch`, { token });
  expect(r.status).toBe(200);
  return r.body.event;
}

beforeAll(async () => {
  await setup();
  host = (await pioneerStreet('host@keys.test', '1 Maple Road')).token;
  await verify(host);
  ben = await joinStreet('ben@keys.test', '2 Maple Road', 'Ben', 'Ade');
  cara = await joinStreet('cara@keys.test', '3 Maple Road', 'Cara', 'Lee');
  dan = await joinStreet('dan@keys.test', '4 Maple Road', 'Dan', 'Moss');
  unverified = await joinStreet('unv@keys.test', '5 Maple Road', 'Una', 'Ver');
  for (const t of [ben, cara, dan]) await verify(t);
  benId = (await me(ben)).id; caraId = (await me(cara)).id; danId = (await me(dan)).id;
});
afterAll(teardown);

describe('EVT-04 category checks', () => {
  it('unverified cannot create; administrative needs the committee; club needs a club; vendor goes to Vendor Hub', async () => {
    expect((await call('GET', '/events/create-check?category=residential', { token: unverified })).body.error.code).toBe('VERIFICATION_REQUIRED');
    expect((await call('GET', '/events/create-check?category=residential', { token: ben })).body.ok).toBe(true);
    const admin = (await call('GET', '/events/create-check?category=administrative', { token: ben })).body;
    expect(admin).toMatchObject({ ok: false, code: 'NOT_COMMITTEE' });
    expect(admin.message).toContain('you must be a member of the committee board');
    expect((await call('GET', '/events/create-check?category=club', { token: ben })).body.code).toBe('NO_CLUB');
    expect((await call('GET', '/events/create-check?category=vendor', { token: ben })).body.message).toBe('Set up your vendor event in Vendor Hub.');
    expect((await call('POST', '/events', { token: ben, body: { category: 'administrative', title: 'AGM' } })).body.error.code).toBe('NOT_COMMITTEE');
  });
});

describe('EVT-05 / EVT-12 draft, form rules and launch', () => {
  it('saves a draft with a planning chat; launch needs the required fields', async () => {
    const d = await draft(host);
    expect(d.body.title).toBe('Event saved as a draft');
    expect(d.body.event.status).toBe('draft');
    expect(d.body.event.chatId).toBeTruthy();
    expect(d.body.event.launchProblems).toContain('Set the date and time');
    const id = d.body.event.id;
    // Drafts are hidden from everyone else.
    expect((await call('GET', `/events/${id}`, { token: ben })).status).toBe(404);
    expect((await call('POST', `/events/${id}/launch`, { token: host })).body.error.code).toBe('NOT_READY');
    expect((await call('PATCH', `/events/${id}`, { token: host, body: { title: 'x'.repeat(61) } })).status).toBe(400);
    expect((await call('PATCH', `/events/${id}`, { token: host, body: { title: 'Party', tags: ['Music', 'Social', 'Tech', 'Culture'] } })).body.error.message).toBe('You can add a maximum of 3 tags');
    expect((await call('PATCH', `/events/${id}`, { token: host, body: { title: 'Party', capacity: 9 } })).body.error.message).toBe('Minimum of 10');
    // EVT-07.2: single-day.
    await call('PATCH', `/events/${id}`, { token: host, body: { ...(await eventBasics(host)), title: 'Party', startAt: inDays(3), endAt: inDays(4), format: 'online', platform: 'zoom', link: 'https://zoom.us/j/1', meetingId: '123', tags: ['Social'] } });
    expect((await call('POST', `/events/${id}/launch`, { token: host })).body.error.message).toBe('Residential, administrative and club events are single-day');
    await call('PATCH', `/events/${id}`, { token: host, body: { ...(await eventBasics(host)), title: 'Party', startAt: inDays(3), endAt: inDays(3, 22), format: 'online', platform: 'zoom', link: 'https://zoom.us/j/1', meetingId: '123', tags: ['Social'] } });
    const l = await call('POST', `/events/${id}/launch`, { token: host, body: { saveAsTemplate: true } });
    expect(l.body.title).toBe('Your event is live!');
    expect((await notes(host))).toContain('event_published');
    expect((await call('GET', '/events/templates', { token: host })).body.personal.map((t: any) => t.name)).toEqual(['Party']);
    // EVT-13.1: title, date and format are locked after launch.
    const e = await call('PATCH', `/events/${id}`, { token: host, body: { ...(await eventBasics(host)), title: 'Renamed', description: 'Bring snacks', startAt: inDays(5), endAt: inDays(5, 22), format: 'physical', tags: ['Music'] } });
    expect(e.body.title).toBe('Event updated!');
    expect(e.body.event).toMatchObject({ title: 'Party', description: 'Bring snacks', format: 'online', tags: ['Music'] });
    // The join link is only for ticket holders and the team.
    expect((await call('GET', `/events/${id}`, { token: ben })).body.event.link).toBeNull();
  });

  it('EVT-11 ready-made templates and free category list', async () => {
    const t = (await call('GET', '/events/templates', { token: ben })).body.templates.map((x: any) => x.name);
    expect(t).toEqual(['Wine tasting', 'Football tournament', 'Mum2Mum market', 'Flea market', 'Annual General Meeting']);
    const d = (await call('GET', '/events/discover', { token: ben })).body;
    expect(d.tags).toEqual(['All', 'Music', 'Culture', 'Networking', 'Food & Drink', 'Fashion', 'Education', 'Tech', 'Social', 'Others']);
  });
});

describe('EVT-19 / EVT-20 tickets', () => {
  let ev: any;
  it('one free ticket per verified resident, seats from 001, sold out at capacity', async () => {
    ev = await liveEvent(host, { title: 'Quiz night', capacity: 10 });
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: unverified })).body.error.code).toBe('VERIFICATION_REQUIRED');
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: host })).body.error.code).toBe('HOST');
    const t = await call('POST', `/events/${ev.id}/tickets`, { token: ben });
    expect(t.body).toMatchObject({ title: "You're going", message: 'Congratulations, your ticket has been booked successfully' });
    expect(t.body.ticket).toMatchObject({ seat: '001', price: 'Free', status: 'active' });
    expect(t.body.ticket.qr).toMatch(/^KEYS-/);
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: ben })).body.error.code).toBe('HAS_TICKET');
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: cara })).body.ticket.seat).toBe('002');
    expect((await notes(ben))).toContain('event_ticket');
    expect((await one<any>(`select data from email_outbox where to_email = 'ben@keys.test' order by id desc limit 1`))!.data.subject).toBe('Your ticket for Quiz night');
    // Fill the rest with other residents.
    for (let i = 0; i < 8; i++) {
      const u = (await one<{ id: string }>(`insert into users(email, first_name, last_name) values ($1,'Fill','Er') returning id`, [`fill${i}@keys.test`]))!;
      await q(`insert into tickets(event_id, user_id, seat, code) values ($1,$2,$3,$4)`, [ev.id, u.id, 10 + i, `KEYS-fill-${i}`]);
    }
    const page = (await call('GET', `/events/${ev.id}`, { token: dan })).body.event;
    expect(page).toMatchObject({ soldOut: true, canGetTicket: false, going: 10 });
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: dan })).body.error.code).toBe('SOLD_OUT');
  });

  it('cancelling a ticket removes the QR and seat and frees the place', async () => {
    const mine = (await call('GET', `/events/${ev.id}`, { token: cara })).body.event.myTicket;
    const c = await call('POST', `/tickets/${mine.id}/cancel`, { token: cara });
    expect(c.body).toMatchObject({ title: 'TICKET CANCELLED', message: 'Your ticket has been cancelled.' });
    expect(c.body.ticket).toMatchObject({ qr: null, seat: null, link: null, shareLink: null });
    expect((await call('POST', `/events/${ev.id}/tickets`, { token: dan })).body.ticket.seat).toBe('018');
  });

  it('EVT-16 attendees for the host: counts, recent, search; no spreadsheet', async () => {
    const a = (await call('GET', `/events/${ev.id}/attendees?q=ben`, { token: host })).body;
    expect(a).toMatchObject({ taken: 10, capacity: 10, canDownload: false });
    expect(a.all.map((x: any) => x.person.name)).toEqual(['Ben Ade']);
    expect((await call('GET', `/events/${ev.id}/attendees?q=018`, { token: host })).body.all[0].person.name).toBe('Dan Moss');
    expect((await call('GET', `/events/${ev.id}/attendees`, { token: ben })).body.error.code).toBe('NOT_HOST');
  });

  it('EVT-02 My events: attending, saved, hosting with drafts', async () => {
    expect((await call('GET', '/events/mine?tab=attending', { token: ben })).body.events.map((e: any) => e.title)).toContain('Quiz night');
    expect((await call('POST', `/events/${ev.id}/save`, { token: ben })).body.message).toBe('Event added to your bookmark.');
    expect((await call('GET', '/events/mine?tab=saved', { token: ben })).body.events).toHaveLength(1);
    expect((await call('DELETE', `/events/${ev.id}/save`, { token: ben })).body.message).toBe('Event removed from your bookmark.');
    await draft(host, { title: 'Draft idea' });
    const hosting = (await call('GET', '/events/mine?tab=hosting', { token: host })).body.events;
    expect(hosting.some((e: any) => e.status === 'draft')).toBe(true);
    expect(hosting.some((e: any) => e.title === 'Quiz night' && e.status === 'live')).toBe(true);
  });

  it('EVT-01 / EVT-03 discover trending by tickets, filter by tag, search letters anywhere', async () => {
    const d = (await call('GET', '/events/discover', { token: ben })).body;
    expect(d.trending[0].title).toBe('Quiz night');
    expect((await call('GET', '/events/discover?tag=Music', { token: ben })).body.happeningSoon.map((e: any) => e.title)).toEqual(['Party']);
    expect((await call('GET', '/events/search?q=uiz', { token: ben })).body.events.map((e: any) => e.title)).toEqual(['Quiz night']);
    expect((await call('GET', '/events/search?q=zzz', { token: ben })).body.events).toEqual([]);
  });
});

describe('EVT-09 / EVT-15 co-hosts, EVT-22 volunteers, EVT-17 chat', () => {
  it('co-host invite, accept into the chat as admin; volunteers join the chat; removed volunteers cannot return', async () => {
    const ev = await liveEvent(host, { title: 'Clean up', cohostIds: [benId], externalCohosts: ['Green Org'], acceptVolunteers: true, volunteerCap: 1 });
    expect(ev.hosts.map((h: any) => [h.name, h.role, h.external])).toEqual([['Amy Duncan', 'Host', false], ['Ben Ade', 'Co-host', false], ['Green Org', 'Co-host', true]]);
    expect((await notes(ben))).toContain('event_cohost_invite');
    expect((await call('GET', `/events/${ev.id}`, { token: ben })).body.event.myRole).toBe('cohost_invited');
    const a = await call('POST', `/events/${ev.id}/cohost/accept`, { token: ben });
    expect(a.status).toBe(200);
    expect(await notes(host)).toContain('event_cohost_accepted');
    const chat = (await call('GET', `/chats/${ev.chatId}`, { token: ben })).body;
    expect(chat.myRole).toBe('admin');
    // Co-hosts can see attendees and edit.
    expect((await call('GET', `/events/${ev.id}/attendees`, { token: ben })).status).toBe(200);
    // Too many co-hosts.
    const six = Array.from({ length: 5 }, (_, i) => `Org ${i}`);
    expect((await call('PATCH', `/events/${ev.id}`, { token: host, body: { cohostIds: [benId], externalCohosts: six, acceptVolunteers: true, volunteerCap: 1, tags: ['Social'] } })).body.error.code).toBe('TOO_MANY_COHOSTS');

    const v = await call('POST', `/events/${ev.id}/volunteer`, { token: cara });
    expect(v.body).toMatchObject({ title: 'Thanks for volunteering!', message: "You've been added to the planning group chat for this event." });
    expect((await call('GET', `/events/${ev.id}`, { token: dan })).body.event.volunteerState).toBe('full');
    expect((await call('POST', `/events/${ev.id}/volunteer`, { token: dan })).body.error.code).toBe('VOLUNTEERS_FULL');
    // EVT-22.5: volunteers cannot see attendees.
    expect((await call('GET', `/events/${ev.id}/attendees`, { token: cara })).status).toBe(403);
    await call('DELETE', `/events/${ev.id}/volunteers/${caraId}`, { token: ben });
    expect((await call('GET', `/chats/${ev.chatId}`, { token: cara })).body.myRole).toBeNull();
    expect((await call('POST', `/events/${ev.id}/volunteer`, { token: cara })).body.error.code).toBe('VOLUNTEER_REMOVED');
    // EVT-17.3: leaving the chat ends volunteering.
    await call('POST', `/events/${ev.id}/volunteer`, { token: dan });
    await call('POST', `/chats/${ev.chatId}/exit`, { token: dan });
    expect((await call('GET', `/events/${ev.id}`, { token: dan })).body.event.myRole).toBeNull();
  });

  it('EVT-09.3 / EVT-27.5 a blocked resident cannot be a co-host; the event stays visible', async () => {
    await call('POST', `/users/${danId}/block`, { token: host });
    expect((await draft(host, { cohostIds: [danId] })).body.error.code).toBe('COHOST_BLOCKED');
    expect((await call('GET', '/events/discover', { token: dan })).body.happeningSoon.length).toBeGreaterThan(0);
    await call('DELETE', `/users/${danId}/block`, { token: host });
  });

  it('EVT-15.3 declining removes the invitation and tells the host', async () => {
    const ev = await liveEvent(host, { title: 'Book swap', cohostIds: [caraId] });
    expect((await call('POST', `/events/${ev.id}/cohost/decline`, { token: cara })).body.message).toBe('Co-hosting invitation declined.');
    expect(await notes(host)).toContain('event_cohost_declined');
    expect((await call('GET', `/events/${ev.id}`, { token: host })).body.event.hosts).toHaveLength(1);
  });
});

describe('EVT-23 scanning', () => {
  it('valid, used, other event, not today; only the team scans', async () => {
    const ev = await liveEvent(host, { title: 'Gig', acceptVolunteers: true, volunteerCap: 2 });
    const t = (await call('POST', `/events/${ev.id}/tickets`, { token: ben })).body.ticket;
    expect((await call('POST', `/events/${ev.id}/scan`, { token: cara, body: { code: t.qr } })).body.error.code).toBe('NOT_TEAM');
    expect((await call('POST', `/events/${ev.id}/scan`, { token: host, body: { code: t.qr } })).body).toMatchObject({ result: 'wrong_day', message: 'This QR code is only available on the event day(s)' });
    clock.advance(3 * DAY);
    await call('POST', `/events/${ev.id}/volunteer`, { token: cara }).catch(() => null);
    // Volunteering closes once the event... still upcoming today, so it is open.
    const ok = (await call('POST', `/events/${ev.id}/scan`, { token: host, body: { code: t.qr } })).body;
    expect(ok).toMatchObject({ result: 'valid', title: 'Let them in!', message: 'Valid ticket.', checkedIn: 1, total: 1 });
    expect(ok.checkedInLabel).toMatch(/^Checked in /);
    expect(await notes(ben)).toContain('event_checked_in');
    expect((await call('POST', `/events/${ev.id}/scan`, { token: host, body: { code: t.qr } })).body).toMatchObject({ result: 'used', title: 'Ticket void!' });
    expect((await call('POST', `/events/${ev.id}/scan`, { token: host, body: { code: 'KEYS-nope' } })).body).toMatchObject({ result: 'invalid', title: 'Invalid ticket!' });
    clock.reset();
  });
});

describe('EVT-14 / EVT-25 cancel', () => {
  it('needs a reason; voids tickets; holders get the pop-up, notification and email', async () => {
    const ev = await liveEvent(host, { title: 'Picnic' });
    const t = (await call('POST', `/events/${ev.id}/tickets`, { token: ben })).body.ticket;
    expect((await call('GET', '/events/cancel-reasons', { token: host })).body.reasons).toHaveLength(5);
    expect((await call('POST', `/events/${ev.id}/cancel`, { token: host, body: { reason: 'Other (please specify)' } })).body.error.field).toBe('text');
    expect((await call('POST', `/events/${ev.id}/cancel`, { token: ben, body: { reason: 'Technical issue' } })).body.error.code).toBe('NOT_HOST');
    expect((await call('POST', `/events/${ev.id}/cancel`, { token: host, body: { reason: 'Technical issue' } })).body.message).toBe('Event canceled');
    expect((await call('GET', `/tickets/${t.id}`, { token: ben })).body.ticket.status).toBe('void');
    const pop = (await call('GET', '/events/cancelled-popups', { token: ben })).body.popups;
    expect(pop[0]).toMatchObject({ title: 'Event cancelled', message: "We're sorry, Picnic has been cancelled by the host." });
    await call('POST', `/tickets/${pop[0].ticketId}/cancel-seen`, { token: ben });
    expect((await call('GET', '/events/cancelled-popups', { token: ben })).body.popups).toEqual([]);
    expect(await notes(ben)).toContain('event_cancelled');
    const mail = (await one<any>(`select data from email_outbox where to_email = 'ben@keys.test' order by id desc limit 1`))!.data;
    expect(mail.text).toContain('Since this was a free event, no further action is required.');
    expect((await one<any>(`select data from email_outbox where to_email = 'host@keys.test' order by id desc limit 1`))!.data.subject).toBe("You've canceled Picnic");
    expect((await call('GET', '/events/mine?tab=attending&status=cancelled', { token: ben })).body.events[0].status).toBe('cancelled');
  });
});

describe('EVT-24 completion and ratings; EVT-26 jobs', () => {
  it('reminder the day before, completed, rating prompt the day after, one rating, breakdown, redo', async () => {
    const ev = await liveEvent(host, { title: 'Bake off' });
    await call('POST', `/events/${ev.id}/tickets`, { token: ben });
    await call('POST', `/events/${ev.id}/tickets`, { token: cara });
    // 12 hours before it starts.
    clock.advance(new Date(ev.startAt).getTime() - clock.now().getTime() - 12 * HOUR);
    await eventJobs();
    expect(await notes(ben)).toContain('event_reminder');
    clock.advance(16 * HOUR); // after it ends
    await eventJobs();
    expect(await notes(host)).toContain('event_completed');
    expect((await call('GET', `/events/${ev.id}`, { token: ben })).body.event.status).toBe('completed');
    expect((await call('GET', '/events/rating-prompts', { token: ben })).body.prompts).toEqual([]); // same day
    clock.advance(DAY);
    await eventJobs();
    expect(await notes(ben)).toContain('event_feedback_request');
    expect((await call('GET', '/events/rating-prompts', { token: ben })).body.prompts.map((p: any) => p.title)).toContain('Bake off');
    expect((await call('POST', `/events/${ev.id}/rating`, { token: host, body: { stars: 5 } })).body.error.code).toBe('HOST');
    expect((await call('POST', `/events/${ev.id}/rating`, { token: ben, body: { stars: 4, text: 'x'.repeat(401) } })).status).toBe(400);
    expect((await call('POST', `/events/${ev.id}/rating`, { token: ben, body: { stars: 4, text: 'Lovely' } })).body.title).toBe('Rating submitted');
    expect((await call('POST', `/events/${ev.id}/rating`, { token: ben, body: { stars: 5 } })).body.error.code).toBe('ALREADY_RATED');
    await call('POST', `/events/${ev.id}/rating`, { token: cara, body: { stars: 5 } });
    expect(await notes(host)).toContain('event_feedback');
    const r = (await call('GET', `/events/${ev.id}/ratings?sort=lowest`, { token: host })).body;
    expect(r).toMatchObject({ average: 4.5, count: 2 });
    expect(r.breakdown.find((b: any) => b.stars === 5).count).toBe(1);
    expect(r.reviews[0].stars).toBe(4);
    const redo = (await call('POST', `/events/${ev.id}/redo`, { token: host })).body.event;
    expect(redo).toMatchObject({ title: 'Bake off', status: 'draft', startAt: null });
    clock.reset();
  });
});

describe('EVT-27 rules', () => {
  it('a host with tickets taken cannot leave the community or step down', async () => {
    const ev = await liveEvent(host, { title: 'Fair' });
    await call('POST', `/events/${ev.id}/tickets`, { token: ben });
    const check = (await call('GET', '/me/exit-check?reason=move', { token: host })).body;
    expect(check.blockers.map((b: any) => b.code)).toContain('EVENT_WITH_TICKETS');
    await seat(host, 'Chair');
    expect((await call('POST', '/board/exit', { token: host, body: { reason: 'Busy' } })).body.error.code).toBe('EXIT_BLOCKED');
  });
});

describe('Media on events', () => {
  it('up to 6 files, own uploads only', async () => {
    const img = (await upload('/media?kind=photo', host, { name: 'a.png', mime: 'image/png', data: PNG })).body.id;
    expect((await draft(host, { mediaIds: Array(7).fill(img) })).body.error.message).toBe('You can add up to 6 files');
    const other = (await upload('/media?kind=photo', ben, { name: 'b.png', mime: 'image/png', data: PNG })).body.id;
    expect((await draft(host, { mediaIds: [other] })).body.error.code).toBe('MEDIA_INVALID');
    const ok = (await draft(host, { mediaIds: [img] })).body.event;
    expect(ok.cover.url).toBeTruthy();
  });
});
