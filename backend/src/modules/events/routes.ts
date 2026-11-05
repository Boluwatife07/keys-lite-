import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx, type Db } from '../../db/pool.js';
import { requireUser, requireVerified } from '../../lib/auth.js';
import { clock, DAY } from '../../lib/clock.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { notify, notifyAndEmail } from '../../lib/notify.js';
import { areBlocked, communityOf, isCommittee, people, person } from '../../lib/people.js';
import { places } from '../../services/places.js';
import { addMember, removeMember, system } from '../chat/service.js';
import { boardFor, seats, withinAllowance } from '../board/service.js';
import { managedClubs } from '../clubs/service.js';
import { shareLink } from '../links/routes.js';
import {
  activeTickets, CANCEL_REASONS, canManageEvent, canScan, canSeeEvent, CAPACITY_MIN, COHOSTS_MAX, cancelEvent, DESCRIPTION_MAX, ensureChat,
  EVENT_TAGS, eventCard, FEEDBACK_MAX, hostsOf, isCompleted, MEDIA_MAX, PLATFORMS, roleFor, TAGS_MAX, teamIds, ticketCode, ticketHolderIds,
  ticketView, TITLE_MAX, ukDay, ukTime, type Event,
} from './service.js';
import { EVENT_TEMPLATES } from './templates.js';

const uuid = z.string().uuid();
const when = z.string().datetime({ offset: true });

const guest = z.object({ name: z.string().trim().min(1, 'Add the guest name').max(60), title: z.string().trim().max(60).default(''), photoMediaId: uuid.nullable().optional() });
const form = z.object({
  category: z.enum(['residential', 'administrative', 'club']),
  clubId: uuid.nullable().optional(),
  audience: z.enum(['all', 'members']).default('all'),
  title: z.string().trim().max(TITLE_MAX, `Event titles can be up to ${TITLE_MAX} characters`).default(''),
  description: z.string().trim().max(DESCRIPTION_MAX, `Descriptions can be up to ${DESCRIPTION_MAX} characters`).default(''),
  mediaIds: z.array(uuid).max(MEDIA_MAX, `You can add up to ${MEDIA_MAX} files`).default([]),
  startAt: when.nullable().optional(),
  endAt: when.nullable().optional(),
  format: z.enum(['physical', 'online']).nullable().optional(),
  placeId: z.string().max(200).nullable().optional(),
  platform: z.enum(['zoom', 'google_meet', 'facebook_live', 'other']).nullable().optional(),
  link: z.string().trim().url('Enter a valid link').nullable().optional().or(z.literal('').transform(() => null)),
  meetingId: z.string().trim().max(60).nullable().optional(),
  meetingPassword: z.string().trim().max(60).nullable().optional(),
  tags: z.array(z.enum(EVENT_TAGS)).max(TAGS_MAX, `You can add a maximum of ${TAGS_MAX} tags`).default([]),
  capacity: z.number().int().min(CAPACITY_MIN, `Minimum of ${CAPACITY_MIN}`).nullable().optional(),
  lineup: z.array(guest).max(20).default([]),
  cohostIds: z.array(uuid).default([]),
  externalCohosts: z.array(z.string().trim().min(1).max(60)).default([]),
  acceptVolunteers: z.boolean().default(false),
  volunteerCap: z.number().int().min(1, 'Add the number of volunteers').nullable().optional(),
  saveAsTemplate: z.boolean().optional(),
});
type Form = z.infer<typeof form>;

async function boardIsFull(communityId: string) {
  const board = await boardFor(communityId);
  if (!board) return false;
  return !(await seats(board.id)).some((s) => !s.occupant_id && s.active && withinAllowance(s, board.tier) && s.kind !== 'champion');
}

/** EVT-04.2 - EVT-04.4: who may create which category. */
async function categoryProblem(userId: string, communityId: string, category: string, clubId?: string | null) {
  if (category === 'administrative' && !(await isCommittee(userId))) {
    const full = await boardIsFull(communityId);
    return { code: 'NOT_COMMITTEE', message: full ? 'The committee board is presently full.' : 'To create an administrative event, you must be a member of the committee board. Would you be interested in applying for membership?', boardFull: full };
  }
  if (category === 'club') {
    const clubs = await managedClubs(userId);
    if (!clubs.length) return { code: 'NO_CLUB', message: 'To create a club event, you must own a club or be an admin member of a club. Would you like to explore clubs?' };
    if (clubId && !clubs.find((c) => c.id === clubId)) return { code: 'NO_CLUB', message: 'Choose a club you own or are an admin of.' };
  }
  return null;
}

async function loadEvent(id: string, viewer: string) {
  const e = await one<Event>('select * from events where id = $1', [id]);
  if (!e || !(await canSeeEvent(e, viewer, await communityOf(viewer)))) throw notFound('This event is not available.');
  return e;
}

async function requireManager(e: Event, userId: string) {
  const r = await roleFor(e, userId);
  if (!canManageEvent(r)) throw forbidden('NOT_HOST', 'Only the host and co-hosts can do this.');
  return r;
}

/** Problems that stop a launch (EVT-05.5); a draft can be saved without them. */
function launchProblems(e: Event, mediaCount: number) {
  const p: string[] = [];
  if (!e.title.trim()) p.push('Add an event title');
  if (!e.description.trim()) p.push('Add a description');
  if (!mediaCount) p.push('Add at least one photo or video');
  if (!e.start_at || !e.end_at) p.push('Set the date and time');
  else {
    if (e.end_at <= e.start_at) p.push('The end must be after the start');
    if (e.start_at <= clock.now()) p.push('The start must be in the future');
    if (ukDay(e.start_at) !== ukDay(e.end_at)) p.push('Residential, administrative and club events are single-day');
  }
  if (!e.format) p.push('Choose physical or online');
  if (e.format === 'physical' && !e.location_name) p.push('Enter location of your event');
  if (e.format === 'online' && (!e.platform || !e.link)) p.push('Select the platform and add the link');
  if (!e.tags.length) p.push('Add at least 1 tag');
  if (e.accept_volunteers && !e.volunteer_cap) p.push('Add the number of volunteers');
  return p;
}

async function ownMedia(ids: string[], owner: string, kinds: string[]) {
  if (!ids.length) return;
  const rows = await q(`select id from media where id = any($1) and owner_id = $2 and kind = any($3)`, [ids, owner, kinds]);
  if (rows.length !== new Set(ids).size) throw badRequest('MEDIA_INVALID', 'One of the files could not be found. Please add it again.');
}

/**
 * Writes the form. After launch, title, date, category, audience and format
 * stay as they were (EVT-13.1). Returns residents newly invited as co-hosts.
 */
async function saveForm(c: Db, e: Event, b: Form, actor: string) {
  const live = e.status !== 'draft';
  // Media must be the editor's own uploads or already on this event (co-hosts edit too).
  const kept = (await q<{ media_id: string }>('select media_id from event_media where event_id = $1', [e.id], c)).map((r) => r.media_id);
  await ownMedia(b.mediaIds.filter((m) => !kept.includes(m)), actor, ['photo', 'video']);
  const keptGuests = (await q<{ photo_media_id: string | null }>('select photo_media_id from event_guests where event_id = $1', [e.id], c)).map((r) => r.photo_media_id);
  await ownMedia(b.lineup.map((g) => g.photoMediaId).filter((m): m is string => !!m && !keptGuests.includes(m)), actor, ['photo']);
  let loc: { name: string | null; address: string | null; lat: number | null; lng: number | null; placeId: string | null } = {
    name: e.location_name, address: e.location_address, lat: e.lat, lng: e.lng, placeId: e.location_place_id,
  };
  if (b.placeId && b.placeId !== e.location_place_id) {
    const r = await places.resolve(b.placeId);
    if (!r) throw badRequest('PLACE_INVALID', 'Choose a location from the suggestions.');
    loc = { name: r.line1, address: r.formatted, lat: r.lat, lng: r.lng, placeId: r.placeId };
  }
  if (b.placeId === null) loc = { name: null, address: null, lat: null, lng: null, placeId: null };
  const format = live ? e.format : b.format ?? null;
  const going = await activeTickets(e.id, c);
  if (b.capacity != null && b.capacity < going) throw badRequest('CAPACITY_TOO_LOW', `${going} tickets are already taken. Capacity cannot be lower.`);
  await q(
    `update events set title = $2, description = $3, start_at = $4, end_at = $5, format = $6, location_place_id = $7, location_name = $8,
       location_address = $9, lat = $10, lng = $11, platform = $12, link = $13, meeting_id = $14, meeting_password = $15, tags = $16,
       capacity = $17, accept_volunteers = $18, volunteer_cap = $19, audience = $20, updated_at = $21 where id = $1`,
    [
      e.id, live ? e.title : b.title, b.description, live ? e.start_at : b.startAt ?? null, live ? e.end_at : b.endAt ?? null, format,
      format === 'physical' ? loc.placeId : null, format === 'physical' ? loc.name : null, format === 'physical' ? loc.address : null,
      format === 'physical' ? loc.lat : null, format === 'physical' ? loc.lng : null,
      format === 'online' ? b.platform ?? null : null, format === 'online' ? b.link ?? null : null,
      format === 'online' && b.platform === 'zoom' ? b.meetingId ?? null : null, format === 'online' && b.platform === 'zoom' ? b.meetingPassword ?? null : null,
      b.tags, b.capacity ?? null, b.acceptVolunteers, b.acceptVolunteers ? b.volunteerCap ?? null : null, live ? e.audience : b.audience, clock.now(),
    ], c,
  );
  await q('delete from event_media where event_id = $1', [e.id], c);
  for (const [i, m] of b.mediaIds.entries()) await q('insert into event_media(event_id, media_id, position) values ($1,$2,$3)', [e.id, m, i], c);
  await q('delete from event_guests where event_id = $1', [e.id], c);
  for (const [i, g] of b.lineup.entries()) {
    await q('insert into event_guests(event_id, name, title, photo_media_id, position) values ($1,$2,$3,$4,$5)', [e.id, g.name, g.title, g.photoMediaId ?? null, i], c);
  }
  // EVT-09: co-hosts, up to 5 including external names.
  const ids = [...new Set(b.cohostIds)].filter((i) => i !== e.host_id);
  if (ids.length + b.externalCohosts.length > COHOSTS_MAX) throw badRequest('TOO_MANY_COHOSTS', `You can add up to ${COHOSTS_MAX} members of the community`);
  for (const id of ids) {
    if (e.host_id && (await areBlocked(e.host_id, id, c))) throw badRequest('COHOST_BLOCKED', 'This resident cannot be added as a co-host.');
    if ((await communityOf(id, c)) !== e.community_id) throw badRequest('COHOST_INVALID', 'Co-hosts must live in your community.');
  }
  const before = await q<{ id: string; user_id: string | null; status: string }>('select id, user_id, status from event_cohosts where event_id = $1', [e.id], c);
  const removed = before.filter((r) => r.user_id && !ids.includes(r.user_id));
  for (const r of removed) {
    await q('delete from event_cohosts where id = $1', [r.id], c);
    if (e.chat_id && r.status === 'accepted') await removeMember(e.chat_id, r.user_id!, 'removed', c);
  }
  await q('delete from event_cohosts where event_id = $1 and user_id is null', [e.id], c);
  const invited: string[] = [];
  for (const id of ids) {
    const r = await one(`insert into event_cohosts(event_id, user_id) values ($1,$2) on conflict do nothing returning id`, [e.id, id], c);
    if (r) invited.push(id);
  }
  // External names after residents, a moment later so the order holds.
  for (const n of b.externalCohosts) await q(`insert into event_cohosts(event_id, external_name, status, created_at) values ($1,$2,'accepted', clock_timestamp() + interval '1 second')`, [e.id, n], c);
  if (e.chat_id && !live && b.title && b.title !== e.title) await q('update chats set name = $2 where id = $1', [e.chat_id, b.title], c);
  return invited;
}

async function inviteCohosts(e: Event, ids: string[]) {
  const host = e.host_id ? await person(e.host_id) : undefined;
  for (const id of ids) {
    await notifyAndEmail(id, 'event_cohost_invite', e.host_id, { type: 'event', id: e.id }, { title: e.title }, {
      subject: 'You have been added as a co-host!',
      text: `${host?.name ?? 'A resident'} has added you as a co-host for ${e.title || 'an event'}. Open Keys to accept or decline the invitation.`,
    });
  }
}

async function detail(e: Event, viewer: string) {
  const role = await roleFor(e, viewer);
  const [card, media, guests, hosts, vols, ticket, attendees, me] = await Promise.all([
    eventCard(e, viewer),
    q<any>(`select m.id, m.url, m.kind, m.duration_seconds from event_media em join media m on m.id = em.media_id where em.event_id = $1 order by em.position`, [e.id]),
    q<any>(`select g.id, g.name, g.title, g.photo_media_id, m.url as photo from event_guests g left join media m on m.id = g.photo_media_id where g.event_id = $1 order by g.position`, [e.id]),
    hostsOf(e),
    q<{ user_id: string }>(`select user_id from event_volunteers where event_id = $1 and status = 'active' order by created_at`, [e.id]),
    one<any>(`select * from tickets where event_id = $1 and user_id = $2 order by created_at desc limit 1`, [e.id, viewer]),
    q<{ user_id: string }>(`select user_id from tickets where event_id = $1 and status = 'active' order by created_at limit 5`, [e.id]),
    one<{ verification_status: string }>('select verification_status from users where id = $1', [viewer]),
  ]);
  const vp = await people([...vols.map((v) => v.user_id), ...attendees.map((a) => a.user_id)]);
  const completed = isCompleted(e);
  const removedVolunteer = await one(`select 1 from event_volunteers where event_id = $1 and user_id = $2 and status = 'removed'`, [e.id, viewer]);
  const volunteerState = !e.accept_volunteers ? null
    : role === 'volunteer' ? 'volunteering'
      : role ? null
        : removedVolunteer ? 'removed'
          : vols.length >= (e.volunteer_cap ?? 0) ? 'full'
            : 'open';
  let ratings = null;
  if (completed) {
    const r = await one<{ avg: number | null; n: number }>(`select avg(stars)::float as avg, count(stars)::int as n from event_ratings where event_id = $1 and stars is not null`, [e.id]);
    ratings = { average: r?.avg ? Math.round(r.avg * 10) / 10 : null, count: r?.n ?? 0 };
  }
  const myRating = await one<{ stars: number | null }>('select stars from event_ratings where event_id = $1 and user_id = $2', [e.id, viewer]);
  const going = card.going;
  const also = e.status === 'live' && !completed
    ? await q<Event>(
      `select * from events where community_id = $1 and status = 'live' and id <> $2 and end_at > $3 and audience = 'all'
        order by (tags && $4::text[]) desc, start_at limit 4`,
      [e.community_id, e.id, clock.now(), e.tags],
    )
    : [];
  const team = canScan(role);
  return {
    ...card,
    description: e.description,
    media: media.map((m) => ({ id: m.id, url: m.url, kind: m.kind, durationSeconds: m.duration_seconds })),
    lat: e.lat,
    lng: e.lng,
    placeId: e.location_place_id,
    platformKey: e.platform,
    // Joining details for ticket holders and the team only (EVT-19.5).
    link: (ticket?.status === 'active' || team) ? e.link : null,
    meetingId: (ticket?.status === 'active' || team) ? e.meeting_id : null,
    meetingPassword: (ticket?.status === 'active' || team) ? e.meeting_password : null,
    lineup: guests.map((g) => ({ id: g.id, name: g.name, title: g.title, photoMediaId: g.photo_media_id, photoUrl: g.photo })),
    hosts,
    attendingPreview: attendees.map((a) => vp.get(a.user_id)),
    acceptVolunteers: e.accept_volunteers,
    volunteerCap: e.volunteer_cap,
    volunteers: vols.map((v) => vp.get(v.user_id)),
    volunteerState,
    myRole: role,
    myTicket: ticket ? await ticketView(ticket, e, viewer) : null,
    canGetTicket: e.status === 'live' && !completed && role !== 'host' && ticket?.status !== 'active' && !card.soldOut,
    verified: me?.verification_status === 'verified',
    canEdit: canManageEvent(role) && e.status !== 'cancelled' && !completed,
    canScan: team && e.status === 'live',
    chatId: role && role !== 'cohost_invited' ? e.chat_id : null,
    launchProblems: e.status === 'draft' ? launchProblems(e, media.length) : [],
    cancelReason: e.cancel_reason,
    ratings,
    canRate: completed && role !== 'host' && ticket?.status === 'active' && !myRating?.stars,
    myRating: myRating?.stars ?? null,
    youMightAlsoLike: await Promise.all(also.map((x) => eventCard(x, viewer))),
    shareLink: shareLink('event', e.id),
    shareText: `I'm attending the ${e.title}, and I think you'd really enjoy it. You should come along!`,
    createdAt: e.created_at,
  };
}

/** Events the viewer may browse: live, upcoming, in their community and audience. */
async function browsable(viewer: string, extra = '', params: unknown[] = []) {
  const c = await communityOf(viewer);
  const rows = await q<Event>(
    `select e.* from events e where e.community_id = $1 and e.status = 'live' and e.end_at > $2
       and (e.audience = 'all' or exists (select 1 from club_members m where m.club_id = e.club_id and m.user_id = $3) or e.host_id = $3)
       ${extra} order by e.start_at`,
    [c, clock.now(), viewer, ...params],
  );
  return rows;
}

export async function eventRoutes(app: FastifyInstance) {
  // EVT-01: Discover: trending (top 5 by tickets), happening soon by tag, templates.
  app.get('/events/discover', async (req) => {
    const u = requireUser(req);
    const { tag } = z.object({ tag: z.string().optional() }).parse(req.query);
    const all = await browsable(u.id);
    const counts = new Map<string, number>();
    for (const e of all) counts.set(e.id, await activeTickets(e.id));
    const trending = [...all].filter((e) => (counts.get(e.id) ?? 0) > 0).sort((a, b) => (counts.get(b.id)! - counts.get(a.id)!) || +a.start_at! - +b.start_at!).slice(0, 5);
    const soon = tag && tag !== 'All' ? all.filter((e) => e.tags.includes(tag)) : all;
    return {
      trending: await Promise.all(trending.map((e) => eventCard(e, u.id))),
      tags: ['All', ...EVENT_TAGS],
      happeningSoon: await Promise.all(soon.map((e) => eventCard(e, u.id))),
      templates: EVENT_TEMPLATES.map((t) => ({ id: t.id, name: t.name, category: t.category, image: t.image })),
    };
  });

  // EVT-03: search by name, letters anywhere.
  app.get('/events/search', async (req) => {
    const u = requireUser(req);
    const { q: text } = z.object({ q: z.string().trim().min(1) }).parse(req.query);
    const rows = await browsable(u.id, `and e.title ilike '%' || $4 || '%'`, [text]);
    return { events: await Promise.all(rows.map((e) => eventCard(e, u.id))) };
  });

  // EVT-02: My events.
  app.get('/events/mine', async (req) => {
    const u = requireUser(req);
    const { tab, status } = z.object({
      tab: z.enum(['attending', 'saved', 'hosting', 'cohosting']),
      status: z.enum(['upcoming', 'completed', 'cancelled']).default('upcoming'),
    }).parse(req.query);
    const now = clock.now();
    const join = {
      attending: `exists (select 1 from tickets t where t.event_id = e.id and t.user_id = $1 and (t.status = 'active' or (t.status = 'void' and e.status = 'cancelled')))`,
      saved: `exists (select 1 from event_saves s where s.event_id = e.id and s.user_id = $1)`,
      hosting: `e.host_id = $1`,
      cohosting: `exists (select 1 from event_cohosts c where c.event_id = e.id and c.user_id = $1 and c.status in ('accepted','invited'))`,
    }[tab];
    const filter = tab === 'saved'
      ? `e.status = 'live' and $2::timestamptz is not null`
      : {
        upcoming: tab === 'hosting' ? `(e.status = 'draft' or (e.status = 'live' and e.end_at > $2))` : `e.status in ('live','draft') and (e.end_at is null or e.end_at > $2)`,
        completed: `e.status = 'live' and e.end_at <= $2`,
        cancelled: `e.status = 'cancelled' and $2::timestamptz is not null`,
      }[status];
    const rows = await q<Event>(`select e.* from events e where ${join} and ${filter} order by coalesce(e.start_at, e.created_at) ${status === 'upcoming' ? 'asc' : 'desc'}`, [u.id, now]);
    return { events: await Promise.all(rows.map((e) => eventCard(e, u.id))) };
  });

  // EVT-11: templates, ready-made and personal.
  app.get('/events/templates', async (req) => {
    const u = requireUser(req);
    const mine = await q<{ id: string; name: string; data: any }>('select id, name, data from event_templates where user_id = $1 order by created_at desc', [u.id]);
    return {
      templates: EVENT_TEMPLATES.map((t) => ({ id: t.id, name: t.name, category: t.category, image: t.image, data: t.data, personal: false })),
      personal: mine.map((t) => ({ id: t.id, name: t.name, category: t.data.category, image: null, data: t.data, personal: true })),
    };
  });

  // EVT-04: category check before the form opens.
  app.get('/events/create-check', async (req) => {
    const u = await requireVerified(req);
    const { category } = z.object({ category: z.enum(['residential', 'administrative', 'club', 'vendor']) }).parse(req.query);
    if (category === 'vendor') return { ok: false, code: 'VENDOR', message: 'Set up your vendor event in Vendor Hub.' };
    const p = await categoryProblem(u.id, (await communityOf(u.id))!, category);
    return p ? { ok: false, ...p } : { ok: true, clubs: category === 'club' ? await managedClubs(u.id) : [] };
  });

  // EVT-05 / EVT-12.1: save a draft (the planning chat is created now).
  app.post('/events', async (req) => {
    const u = await requireVerified(req);
    const b = form.parse(req.body);
    const community = (await communityOf(u.id))!;
    const p = await categoryProblem(u.id, community, b.category, b.clubId);
    if (p) throw forbidden(p.code, p.message);
    if (b.category === 'club' && !b.clubId) throw badRequest('CLUB_REQUIRED', 'Select your club');
    if (b.category !== 'club' && b.audience !== 'all') throw badRequest('AUDIENCE_INVALID', 'Residential and administrative events are for everyone in this community.');
    const { e, invited } = await tx(async (c) => {
      const row = (await one<Event>(
        `insert into events(community_id, host_id, category, club_id, audience, title, created_at, updated_at) values ($1,$2,$3,$4,$5,$6,$7,$7) returning *`,
        [community, u.id, b.category, b.category === 'club' ? b.clubId : null, b.audience, b.title, clock.now()], c,
      ))!;
      row.chat_id = await ensureChat(row, c);
      const invited = await saveForm(c, { ...row, title: '' }, b, u.id);
      return { e: (await one<Event>('select * from events where id = $1', [row.id], c))!, invited };
    });
    await inviteCohosts(e, invited);
    return {
      event: await detail(e, u.id),
      title: 'Event saved as a draft',
      message: 'You can now plan with your team in the group chat and make any changes until your event is ready to go live.',
    };
  });

  app.get('/events/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    return { event: await detail(await loadEvent(id, u.id), u.id) };
  });

  // EVT-13: edit (draft: everything; live: some fields locked). Ticket holders are told.
  app.patch('/events/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    await requireManager(e, u.id);
    if (e.status === 'cancelled' || isCompleted(e)) throw conflict('EVENT_CLOSED', 'This event can no longer be edited.');
    const b = form.parse({ ...(req.body as object), category: e.category, clubId: e.club_id });
    if (e.status === 'draft' && b.category !== 'club' && b.audience !== 'all') throw badRequest('AUDIENCE_INVALID', 'Residential and administrative events are for everyone in this community.');
    const invited = await tx((c) => saveForm(c, e, b, u.id));
    const fresh = (await one<Event>('select * from events where id = $1', [id]))!;
    await inviteCohosts(fresh, invited);
    if (e.status === 'live') {
      for (const h of await ticketHolderIds(id)) {
        await notifyAndEmail(h, 'event_updated', u.id, { type: 'event', id }, { title: e.title }, {
          subject: `Important update for ${e.title}`,
          text: `The host has made changes to ${e.title}. Open Keys to see the latest details.`,
        });
      }
      for (const t of await teamIds(e)) if (t !== u.id) await notify(t, 'event_updated', u.id, { type: 'event', id }, { title: e.title });
      return { event: await detail(fresh, u.id), title: 'Event updated!', message: 'Your event changes have been saved.' };
    }
    return { event: await detail(fresh, u.id), message: 'Event saved as a draft' };
  });

  // Drafts can be deleted.
  app.delete('/events/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (e.host_id !== u.id) throw forbidden('NOT_HOST', 'Only the host can delete this draft.');
    if (e.status !== 'draft') throw conflict('NOT_DRAFT', 'Launched events are cancelled, not deleted.');
    await q('delete from events where id = $1', [id]);
    if (e.chat_id) await q('update chats set read_only = true where id = $1', [e.chat_id]);
    return { message: 'Draft deleted' };
  });

  // EVT-12.3 / EVT-12.4 / EVT-11.4: launch.
  app.post('/events/:id/launch', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { saveAsTemplate } = z.object({ saveAsTemplate: z.boolean().default(false) }).parse(req.body ?? {});
    const e = await loadEvent(id, u.id);
    if (e.host_id !== u.id) throw forbidden('NOT_HOST', 'Only the host can launch this event.');
    if (e.status !== 'draft') throw conflict('ALREADY_LIVE', 'This event is already live.');
    const mediaCount = (await one<{ n: number }>('select count(*)::int as n from event_media where event_id = $1', [id]))!.n;
    const problems = launchProblems(e, mediaCount);
    if (problems.length) throw badRequest('NOT_READY', problems[0], { problems });
    await q(`update events set status = 'live', launched_at = $2 where id = $1`, [id, clock.now()]);
    if (saveAsTemplate) {
      const tpl = {
        category: e.category, title: e.title, description: e.description, tags: e.tags, capacity: e.capacity, format: e.format,
        platform: e.platform, acceptVolunteers: e.accept_volunteers, volunteerCap: e.volunteer_cap, clubId: e.club_id, audience: e.audience,
      };
      await q('insert into event_templates(user_id, name, data) values ($1,$2,$3)', [u.id, e.title, tpl]);
    }
    const fresh = (await one<Event>('select * from events where id = $1', [id]))!;
    await notify(u.id, 'event_published', null, { type: 'event', id }, { title: e.title });
    for (const t of await teamIds(fresh)) if (t !== u.id) await notify(t, 'event_published', u.id, { type: 'event', id }, { title: e.title });
    if (e.category === 'club' && e.club_id) {
      const members = await q<{ user_id: string }>('select user_id from club_members where club_id = $1', [e.club_id]);
      for (const m of members) if (m.user_id !== u.id) await notify(m.user_id, 'club_event', u.id, { type: 'event', id }, { title: e.title });
    }
    return { event: await detail(fresh, u.id), title: 'Your event is live!', message: 'Your event is now on the feed, residents can now see it and get their tickets.' };
  });

  // EVT-14: cancel with a reason.
  app.get('/events/cancel-reasons', async () => ({ reasons: CANCEL_REASONS }));
  app.post('/events/:id/cancel', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({ reason: z.enum(CANCEL_REASONS), text: z.string().trim().max(300).optional() }).parse(req.body);
    if (b.reason === 'Other (please specify)' && !b.text) throw badRequest('VALIDATION', 'Tell us why you are canceling this event', { field: 'text' });
    const e = await loadEvent(id, u.id);
    if (e.host_id !== u.id) throw forbidden('NOT_HOST', 'Only the host can cancel this event.');
    if (e.status !== 'live' || isCompleted(e)) throw conflict('NOT_LIVE', 'Only upcoming live events can be cancelled.');
    await cancelEvent(e, b.reason, b.text ?? null, u.id);
    return { message: 'Event canceled' };
  });

  // EVT-25.1: cancelled pop-up for ticket holders, shown once.
  app.get('/events/cancelled-popups', async (req) => {
    const u = requireUser(req);
    const rows = await q<{ id: string; event_id: string; title: string }>(
      `select t.id, t.event_id, e.title from tickets t join events e on e.id = t.event_id where t.user_id = $1 and t.status = 'void' and t.cancel_seen_at is null and e.status = 'cancelled'`,
      [u.id],
    );
    return { popups: rows.map((r) => ({ ticketId: r.id, eventId: r.event_id, title: 'Event cancelled', message: `We're sorry, ${r.title} has been cancelled by the host.` })) };
  });
  app.post('/tickets/:id/cancel-seen', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await q('update tickets set cancel_seen_at = $3 where id = $1 and user_id = $2', [id, u.id, clock.now()]);
    return { ok: true };
  });

  // EVT-02.5: bookmark.
  app.post('/events/:id/save', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadEvent(id, u.id);
    await q('insert into event_saves(user_id, event_id) values ($1,$2) on conflict do nothing', [u.id, id]);
    return { saved: true, message: 'Event added to your bookmark.' };
  });
  app.delete('/events/:id/save', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await q('delete from event_saves where user_id = $1 and event_id = $2', [u.id, id]);
    return { saved: false, message: 'Event removed from your bookmark.' };
  });

  // EVT-19: one free ticket per verified resident, while places last.
  app.post('/events/:id/tickets', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (e.status !== 'live' || isCompleted(e)) throw conflict('NOT_LIVE', 'Tickets are not available for this event.');
    if (e.host_id === u.id) throw conflict('HOST', 'You are hosting this event.');
    const t = await tx(async (c) => {
      // Lock the event row so the last place goes to one person only.
      await q('select id from events where id = $1 for update', [id], c);
      if (await one(`select 1 from tickets where event_id = $1 and user_id = $2 and status = 'active'`, [id, u.id], c)) throw conflict('HAS_TICKET', 'You already have a ticket for this event.');
      if (e.capacity != null && (await activeTickets(id, c)) >= e.capacity) throw conflict('SOLD_OUT', 'This event is sold out.');
      const seat = (await one<{ n: number }>('select coalesce(max(seat), 0)::int + 1 as n from tickets where event_id = $1', [id], c))!.n;
      return (await one<any>(
        `insert into tickets(event_id, user_id, seat, code, created_at) values ($1,$2,$3,$4,$5) returning *`,
        [id, u.id, seat, ticketCode(), clock.now()], c,
      ))!;
    });
    const when = e.start_at ? `${e.start_at.toLocaleDateString('en-GB', { timeZone: 'Europe/London', weekday: 'long', day: 'numeric', month: 'long' })} at ${ukTime(e.start_at)}` : '';
    await notifyAndEmail(u.id, 'event_ticket', null, { type: 'ticket', id: t.id }, { title: e.title }, {
      subject: `Your ticket for ${e.title}`,
      text: `You're going to ${e.title} on ${when}. Seat ${String(t.seat).padStart(3, '0')}.${e.format === 'online' && e.link ? ` Join online: ${e.link}` : ''}`,
    });
    return { ticket: await ticketView(t, e, u.id), title: "You're going", message: 'Congratulations, your ticket has been booked successfully' };
  });

  // EVT-20
  app.get('/tickets/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const t = await one<any>('select * from tickets where id = $1', [id]);
    if (!t) throw notFound('This ticket is not available.');
    const e = (await one<Event>('select * from events where id = $1', [t.event_id]))!;
    if (t.user_id !== u.id && !canManageEvent(await roleFor(e, u.id))) throw notFound('This ticket is not available.');
    return { ticket: await ticketView(t, e, u.id) };
  });
  app.post('/tickets/:id/cancel', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const t = await one<any>('select * from tickets where id = $1 and user_id = $2', [id, u.id]);
    if (!t) throw notFound('This ticket is not available.');
    if (t.status !== 'active') throw conflict('NOT_ACTIVE', 'This ticket is no longer active.');
    if (t.checked_in_at) throw conflict('CHECKED_IN', 'This ticket has already been checked in.');
    await q(`update tickets set status = 'cancelled' where id = $1`, [id]);
    const e = (await one<Event>('select * from events where id = $1', [t.event_id]))!;
    return { ticket: await ticketView({ ...t, status: 'cancelled' }, e, u.id), title: 'TICKET CANCELLED', message: 'Your ticket has been cancelled.' };
  });

  // EVT-16: attendees for the host and co-hosts.
  app.get('/events/:id/attendees', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { q: text } = z.object({ q: z.string().trim().default('') }).parse(req.query);
    const e = await loadEvent(id, u.id);
    await requireManager(e, u.id);
    const rows = await q<any>(
      `select t.* from tickets t join users u on u.id = t.user_id where t.event_id = $1 and t.status = 'active'
         and ($2 = '' or (u.first_name || ' ' || u.last_name) ilike '%' || $2 || '%' or lpad(t.seat::text, 3, '0') like '%' || $2 || '%')
       order by t.created_at desc`,
      [id, text],
    );
    const ps = await people(rows.map((r) => r.user_id));
    const view = (t: any) => ({ ticketId: t.id, person: ps.get(t.user_id), seat: String(t.seat).padStart(3, '0'), takenAt: t.created_at, checkedInAt: t.checked_in_at });
    return {
      taken: await activeTickets(id),
      capacity: e.capacity,
      checkedIn: rows.filter((r) => r.checked_in_at).length,
      recent: rows.slice(0, 10).map(view),
      all: rows.map(view),
      canDownload: false, // EVT-16.4
    };
  });

  // EVT-22: volunteering.
  app.post('/events/:id/volunteer', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (e.status !== 'live' || isCompleted(e) || !e.accept_volunteers) throw conflict('NOT_ACCEPTING', 'This event is not accepting volunteers.');
    const role = await roleFor(e, u.id);
    if (role) throw conflict('ALREADY_TEAM', role === 'volunteer' ? 'You are already volunteering for this event.' : 'You are already part of the team for this event.');
    if (await one(`select 1 from event_volunteers where event_id = $1 and user_id = $2 and status = 'removed'`, [id, u.id])) {
      throw forbidden('VOLUNTEER_REMOVED', 'You were removed as a volunteer and cannot volunteer again for this event.');
    }
    const n = (await one<{ n: number }>(`select count(*)::int as n from event_volunteers where event_id = $1 and status = 'active'`, [id]))!.n;
    if (n >= (e.volunteer_cap ?? 0)) throw conflict('VOLUNTEERS_FULL', 'This event has all the volunteers it needs.');
    await q(`insert into event_volunteers(event_id, user_id, status, created_at) values ($1,$2,'active',$3) on conflict (event_id, user_id) do update set status = 'active', created_at = excluded.created_at`, [id, u.id, clock.now()]);
    if (e.chat_id) {
      await addMember(e.chat_id, u.id, 'member');
      await system(e.chat_id, 'joined', u.id, null, `${(await person(u.id))!.name} joined as a volunteer`);
    }
    if (e.host_id) await notify(e.host_id, 'event_volunteer_joined', u.id, { type: 'event', id }, { title: e.title });
    return { title: 'Thanks for volunteering!', message: "You've been added to the planning group chat for this event.", chatId: e.chat_id };
  });
  app.delete('/events/:id/volunteers/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    await requireManager(e, u.id);
    const r = await one(`update event_volunteers set status = 'removed' where event_id = $1 and user_id = $2 and status = 'active' returning 1`, [id, userId]);
    if (!r) throw notFound('This volunteer is not on the team.');
    if (e.chat_id) await removeMember(e.chat_id, userId, 'removed');
    return { message: 'Volunteer removed' };
  });

  // EVT-15: co-host invitations.
  for (const action of ['accept', 'decline'] as const) {
    app.post(`/events/:id/cohost/${action}`, async (req) => {
      const u = requireUser(req);
      const { id } = z.object({ id: uuid }).parse(req.params);
      const e = await loadEvent(id, u.id);
      const row = await one<{ id: string }>(`select id from event_cohosts where event_id = $1 and user_id = $2 and status = 'invited'`, [id, u.id]);
      if (!row) throw notFound('This invitation is no longer available.');
      if (action === 'accept') {
        await q(`update event_cohosts set status = 'accepted' where id = $1`, [row.id]);
        if (e.chat_id) await addMember(e.chat_id, u.id, 'admin');
        if (e.host_id) await notify(e.host_id, 'event_cohost_accepted', u.id, { type: 'event', id }, { title: e.title });
        return { message: 'You are now a co-host of this event.', chatId: e.chat_id };
      }
      await q('delete from event_cohosts where id = $1', [row.id]);
      if (e.host_id) await notify(e.host_id, 'event_cohost_declined', u.id, { type: 'event', id }, { title: e.title });
      return { message: 'Co-hosting invitation declined.' };
    });
  }
  app.delete('/events/:id/cohosts/:cohostId', async (req) => {
    const u = requireUser(req);
    const { id, cohostId } = z.object({ id: uuid, cohostId: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (e.host_id !== u.id) throw forbidden('NOT_HOST', 'Only the host can remove a co-host.');
    const r = await one<{ user_id: string | null }>('delete from event_cohosts where id = $1 and event_id = $2 returning user_id', [cohostId, id]);
    if (!r) throw notFound('This co-host is not on the event.');
    if (r.user_id && e.chat_id) await removeMember(e.chat_id, r.user_id, 'removed');
    return { message: 'Co-host removed' };
  });

  // EVT-23: check-in by QR code.
  app.post('/events/:id/scan', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { code } = z.object({ code: z.string().trim().min(1).max(200) }).parse(req.body);
    const e = await loadEvent(id, u.id);
    if (!canScan(await roleFor(e, u.id))) throw forbidden('NOT_TEAM', 'Only the host, co-hosts and volunteers can scan tickets.');
    const counts = async () => {
      const r = (await one<{ n: number; c: number }>(
        `select count(*)::int as n, count(checked_in_at)::int as c from tickets where event_id = $1 and status = 'active'`, [id],
      ))!;
      return { checkedIn: r.c, total: r.n };
    };
    const t = await one<any>('select * from tickets where code = $1', [code]);
    if (!t || t.event_id !== id || t.status !== 'active') {
      return { result: 'invalid', title: 'Invalid ticket!', message: 'This QR code does not belong to any tickets in this event.', ...(await counts()) };
    }
    if (!e.start_at || ukDay(clock.now()) !== ukDay(e.start_at)) {
      return { result: 'wrong_day', title: 'Not the event day', message: 'This QR code is only available on the event day(s)', ...(await counts()) };
    }
    const holder = await person(t.user_id);
    const ticket = { seat: String(t.seat).padStart(3, '0'), holder, eventTitle: e.title };
    if (t.checked_in_at) {
      return { result: 'used', title: 'Ticket void!', message: 'This ticket has already been checked in earlier.', ticket, checkedInAt: t.checked_in_at, ...(await counts()) };
    }
    const now = clock.now();
    const done = await one(`update tickets set checked_in_at = $2, checked_in_by = $3 where id = $1 and checked_in_at is null returning 1`, [t.id, now, u.id]);
    if (!done) return { result: 'used', title: 'Ticket void!', message: 'This ticket has already been checked in earlier.', ticket, ...(await counts()) };
    await notify(t.user_id, 'event_checked_in', null, { type: 'event', id }, { title: e.title });
    return { result: 'valid', title: 'Let them in!', message: 'Valid ticket.', ticket, checkedInAt: now, checkedInLabel: `Checked in ${ukTime(now)}`, ...(await counts()) };
  });
  app.get('/events/:id/checkins', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (!canScan(await roleFor(e, u.id))) throw forbidden('NOT_TEAM', 'Only the host, co-hosts and volunteers can scan tickets.');
    const r = (await one<{ n: number; c: number }>(`select count(*)::int as n, count(checked_in_at)::int as c from tickets where event_id = $1 and status = 'active'`, [id]))!;
    return { checkedIn: r.c, total: r.n };
  });

  // EVT-24: ratings.
  app.get('/events/rating-prompts', async (req) => {
    const u = requireUser(req);
    const rows = await q<Event>(
      `select e.* from events e join tickets t on t.event_id = e.id and t.user_id = $1 and t.status = 'active'
        where e.status = 'live' and e.end_at <= $2 and e.host_id <> $1
          and not exists (select 1 from event_ratings r where r.event_id = e.id and r.user_id = $1)
        order by e.end_at desc`,
      [u.id, clock.now()],
    );
    // "The day after": shown from the next UK day.
    const today = ukDay(clock.now());
    const due = rows.filter((e) => ukDay(e.end_at!) < today);
    return { prompts: await Promise.all(due.map((e) => eventCard(e, u.id))) };
  });
  app.post('/events/:id/rating', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({ stars: z.number().int().min(1).max(5), text: z.string().trim().max(FEEDBACK_MAX).default('') }).parse(req.body);
    const e = await loadEvent(id, u.id);
    if (!isCompleted(e)) throw conflict('NOT_COMPLETED', 'You can rate this event once it has ended.');
    if (e.host_id === u.id) throw forbidden('HOST', 'You cannot rate your own event.');
    if (!(await one(`select 1 from tickets where event_id = $1 and user_id = $2 and status = 'active'`, [id, u.id]))) throw forbidden('NO_TICKET', 'Only attendees can rate this event.');
    const r = await one(
      `insert into event_ratings(event_id, user_id, stars, text, created_at) values ($1,$2,$3,$4,$5)
       on conflict (event_id, user_id) do update set stars = excluded.stars, text = excluded.text, created_at = excluded.created_at where event_ratings.stars is null returning 1`,
      [id, u.id, b.stars, b.text, clock.now()],
    );
    if (!r) throw conflict('ALREADY_RATED', 'You have already rated this event.');
    if (e.host_id) await notify(e.host_id, 'event_feedback', null, { type: 'event', id }, { title: e.title });
    return { title: 'Rating submitted', message: 'Thanks for sharing your feedback!' };
  });
  app.post('/events/:id/rating/dismiss', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await q(`insert into event_ratings(event_id, user_id, stars) values ($1,$2,null) on conflict do nothing`, [id, u.id]);
    return { ok: true };
  });
  app.get('/events/:id/ratings', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { sort } = z.object({ sort: z.enum(['newest', 'oldest', 'highest', 'lowest']).default('newest') }).parse(req.query);
    const e = await loadEvent(id, u.id);
    await requireManager(e, u.id);
    const order = { newest: 'created_at desc', oldest: 'created_at asc', highest: 'stars desc, created_at desc', lowest: 'stars asc, created_at desc' }[sort];
    const rows = await q<any>(`select * from event_ratings where event_id = $1 and stars is not null order by ${order}`, [id]);
    const ps = await people(rows.map((r) => r.user_id));
    const n = rows.length;
    const avg = n ? Math.round((rows.reduce((s, r) => s + r.stars, 0) / n) * 10) / 10 : null;
    return {
      average: avg,
      count: n,
      breakdown: [5, 4, 3, 2, 1].map((s) => ({ stars: s, count: rows.filter((r) => r.stars === s).length })),
      reviews: rows.map((r) => ({ person: ps.get(r.user_id), stars: r.stars, text: r.text, createdAt: r.created_at })),
    };
  });

  // EVT-24.5: redo a completed event as a new draft.
  app.post('/events/:id/redo', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const e = await loadEvent(id, u.id);
    if (e.host_id !== u.id) throw forbidden('NOT_HOST', 'Only the host can redo this event.');
    const p = await categoryProblem(u.id, e.community_id, e.category, e.club_id);
    if (p) throw forbidden(p.code, p.message);
    const copy = await tx(async (c) => {
      const row = (await one<Event>(
        `insert into events(community_id, host_id, category, club_id, audience, title, description, format, location_place_id, location_name,
           location_address, lat, lng, platform, link, meeting_id, meeting_password, tags, capacity, accept_volunteers, volunteer_cap, created_at, updated_at)
         select community_id, host_id, category, club_id, audience, title, description, format, location_place_id, location_name, location_address,
           lat, lng, platform, link, meeting_id, meeting_password, tags, capacity, accept_volunteers, volunteer_cap, $2, $2 from events where id = $1 returning *`,
        [id, clock.now()], c,
      ))!;
      await q('insert into event_media(event_id, media_id, position) select $2, media_id, position from event_media where event_id = $1', [id, row.id], c);
      await q('insert into event_guests(event_id, name, title, photo_media_id, position) select $2, name, title, photo_media_id, position from event_guests where event_id = $1', [id, row.id], c);
      await ensureChat(row, c);
      return row;
    });
    return { event: await detail((await one<Event>('select * from events where id = $1', [copy.id]))!, u.id) };
  });
}

/** Every minute: day-before reminders, completion, feedback requests, draft reminders (EVT-26). */
export async function eventJobs() {
  const now = clock.now();
  const soon = await q<Event>(`select * from events where status = 'live' and reminder_sent_at is null and start_at > $1 and start_at <= $2`, [now, new Date(now.getTime() + DAY)]);
  for (const e of soon) {
    await q('update events set reminder_sent_at = $2 where id = $1', [e.id, now]);
    for (const h of await ticketHolderIds(e.id)) {
      await notify(h, 'event_reminder', null, { type: 'event', id: e.id }, { title: e.title, text: `Reminder! "${e.title}" is tomorrow at ${ukTime(e.start_at!)}.` });
    }
  }
  const done = await q<Event>(`select * from events where status = 'live' and completed_notified_at is null and end_at <= $1`, [now]);
  for (const e of done) {
    await q('update events set completed_notified_at = $2 where id = $1', [e.id, now]);
    if (e.host_id) await notify(e.host_id, 'event_completed', null, { type: 'event', id: e.id }, { title: e.title });
  }
  const today = ukDay(now);
  const ask = await q<Event>(`select * from events where status = 'live' and feedback_requested_at is null and end_at <= $1`, [now]);
  for (const e of ask.filter((x) => ukDay(x.end_at!) < today)) {
    await q('update events set feedback_requested_at = $2 where id = $1', [e.id, now]);
    for (const h of await ticketHolderIds(e.id)) await notify(h, 'event_feedback_request', null, { type: 'event', id: e.id }, { title: e.title });
  }
  // EVT-12.5: a draft untouched for 3 days.
  const stale = await q<Event>(`select * from events where status = 'draft' and draft_reminder_at is null and updated_at <= $1`, [new Date(now.getTime() - 3 * DAY)]);
  for (const e of stale) {
    await q('update events set draft_reminder_at = $2 where id = $1', [e.id, now]);
    if (e.host_id) {
      await notifyAndEmail(e.host_id, 'event_draft_reminder', null, { type: 'event', id: e.id }, { title: e.title }, {
        subject: `Still planning ${e.title || 'your event'}?`,
        text: `Your event ${e.title || ''} is saved as a draft. Launch it when you're ready so residents can get their tickets.`,
      });
    }
  }
}

export { AppError };
