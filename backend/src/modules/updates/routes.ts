import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx, type Db } from '../../db/pool.js';
import { requireUser, requireVerified } from '../../lib/auth.js';
import { clock } from '../../lib/clock.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { notify } from '../../lib/notify.js';
import { communityOf, isCommittee, people, person, seatOf } from '../../lib/people.js';
import { shareLink } from '../links/routes.js';
import { addMember, emit, muteUntil, system } from '../chat/service.js';
import { committeeIds, boardFor } from '../board/service.js';

const uuid = z.string().uuid();
export const TITLE_MAX = 100;
export const DETAILS_MAX = 700;
export const IMAGES_MAX = 10; // UPD-D2: no maximum in design or PRD (needs check)
export const PIN_MAX = 3;

interface Update {
  id: string; community_id: string; author_id: string; title: string; details: string; audience: 'all' | 'sub';
  document_media_id: string | null; document_downloads: number; chat_id: string | null; status: string;
  resolved_at: Date | null; resolved_by: string | null; created_at: Date; edited_at: Date | null;
}

/** Where the viewer lives inside their community: their street and building. */
async function homeOf(userId: string) {
  return one<{ community_id: string; street_id: string; building_id: string | null }>(
    `select m.community_id, a.street_id, m.building_id from memberships m join users u on u.id = m.user_id join addresses a on a.id = u.home_address_id where m.user_id = $1`,
    [userId],
  );
}

/** UPD-01.4: residents see updates for their audience; committee members see all to manage them. */
export async function canSee(up: Update, userId: string) {
  const h = await homeOf(userId);
  if (!h || h.community_id !== up.community_id) return false;
  if (up.audience === 'all' || up.author_id === userId || (await isCommittee(userId))) return true;
  return !!(await one(
    `select 1 from update_targets where update_id = $1 and (street_id = $2 or ($3::uuid is not null and building_id = $3))`,
    [up.id, h.street_id, h.building_id],
  ));
}

/** Residents in the audience (for notifications and the chat join check). */
export async function audienceIds(up: Update, db?: Db) {
  if (up.audience === 'all') return (await q<{ user_id: string }>('select user_id from memberships where community_id = $1', [up.community_id], db)).map((r) => r.user_id);
  return (await q<{ user_id: string }>(
    `select m.user_id from memberships m join users u on u.id = m.user_id join addresses a on a.id = u.home_address_id
      where m.community_id = $1 and exists (select 1 from update_targets t where t.update_id = $2 and (t.street_id = a.street_id or t.building_id = m.building_id))`,
    [up.community_id, up.id], db,
  )).map((r) => r.user_id);
}

async function loadUpdate(id: string, viewer: string, { allowGone = false } = {}) {
  const up = await one<Update>('select * from updates where id = $1', [id]);
  if (!up || !(await canSee(up, viewer))) throw notFound('This update is not available.');
  if (!allowGone && up.status === 'deleted') throw new AppError(410, 'POST_DELETED', 'This post has been deleted by the author.', { title: 'Post unavailable' });
  if (!allowGone && up.status === 'removed') throw new AppError(410, 'POST_REMOVED', 'This post has been removed for violating Keys Guidelines', { title: 'Post unavailable' });
  return up;
}

async function locations(up: Update) {
  if (up.audience === 'all') return { names: [] as string[], label: 'All residents' };
  const rows = await q<{ name: string }>(
    `select coalesce(s.name, b.name) as name from update_targets t left join streets s on s.id = t.street_id left join communities b on b.id = t.building_id where t.update_id = $1`,
    [up.id],
  );
  const names = rows.map((r) => r.name);
  return { names, label: names.length > 2 ? `${names.slice(0, 2).join(', ')} +${names.length - 2} others` : names.join(', ') };
}

async function notifyAudience(up: Update, actor: string, type: 'update_new' | 'update_additional') {
  const now = clock.now();
  for (const u of await audienceIds(up)) {
    if (u === actor) continue;
    if (await one('select 1 from update_mutes where user_id = $1 and update_id = $2 and until > $3', [u, up.id, now])) continue;
    await notify(u, type, actor, { type: 'update', id: up.id }, { title: up.title });
  }
}

/** UCH-01: the update group chat. Named after the update; committee added; creator is admin. */
async function createUpdateChat(c: Db, up: Update) {
  const chat = (await one<{ id: string }>(
    `insert into chats(community_id, type, name, created_by, update_id, members_can_invite) values ($1,'update',$2,$3,$4,false) returning id`,
    [up.community_id, up.title, up.author_id, up.id], c,
  ))!;
  await addMember(chat.id, up.author_id, 'admin', c);
  const board = await boardFor(up.community_id, c);
  if (board) for (const m of await committeeIds(board.id, c)) if (m !== up.author_id) await addMember(chat.id, m, 'member', c);
  await q('update updates set chat_id = $2 where id = $1', [up.id, chat.id], c);
  return chat.id;
}

async function closeChat(up: Update) {
  if (!up.chat_id) return;
  await q('update chats set read_only = true where id = $1', [up.chat_id]);
  emit((await q<{ user_id: string }>('select user_id from chat_members where chat_id = $1', [up.chat_id])).map((r) => r.user_id), { type: 'chat', chatId: up.chat_id });
}

async function card(up: Update, viewer: string) {
  const [author, loc, pin, mute, read, extra] = await Promise.all([
    person(up.author_id),
    locations(up),
    one('select 1 from update_pins where user_id = $1 and update_id = $2', [viewer, up.id]),
    one<{ until: Date }>('select until from update_mutes where user_id = $1 and update_id = $2 and until > $3', [viewer, up.id, clock.now()]),
    one<{ seen_at: Date }>('select seen_at from update_reads where user_id = $1 and update_id = $2', [viewer, up.id]),
    q<{ created_at: Date }>('select created_at from additional_updates where update_id = $1 and deleted_at is null', [up.id]),
  ]);
  const unseen = read ? extra.filter((e) => e.created_at > read.seen_at).length : extra.length;
  const images = await q<{ id: string; url: string }>('select m.id, m.url from update_media um join media m on m.id = um.media_id where um.update_id = $1 order by um.position', [up.id]);
  return {
    id: up.id,
    title: up.title,
    details: up.details,
    author,
    date: up.created_at,
    locations: loc.label,
    locationNames: loc.names,
    audience: up.audience,
    images: images.map((i) => i.url),
    imageMedia: images,
    documentId: up.document_media_id,
    // Unread: never opened, or new additional updates since last opened.
    seen: !!read && unseen === 0,
    additionalCount: extra.length,
    newAdditional: unseen,
    pinned: !!pin,
    muted: !!mute,
    status: up.status,
    resolvedAt: up.resolved_at,
    isMine: up.author_id === viewer,
    canResolve: up.status === 'live' && (up.author_id === viewer || (await seatOf(viewer))?.role === 'Chair'),
    chatId: up.chat_id,
    editedAt: up.edited_at,
    shareLink: shareLink('update', up.id),
  };
}

async function visibleList(viewer: string, status: 'live' | 'resolved', search?: string) {
  const c = await communityOf(viewer);
  const rows = await q<Update>(
    `select * from updates u where community_id = $1 and status = $2
       and not exists (select 1 from update_hides h where h.user_id = $3 and h.update_id = u.id)
       and ($4::text is null or title ilike '%' || $4 || '%')
     order by created_at desc`,
    [c, status, viewer, search ?? null],
  );
  const out = [];
  for (const r of rows) if (await canSee(r, viewer)) out.push(r);
  return out;
}

const formBody = z.object({
  title: z.string().trim().min(1, 'Add a title').max(TITLE_MAX),
  details: z.string().trim().min(1, 'Add the details of the update').max(DETAILS_MAX),
  imageIds: z.array(uuid).max(IMAGES_MAX, `You can add up to ${IMAGES_MAX} images`).default([]),
  documentId: uuid.nullable().optional(),
  audience: z.enum(['all', 'sub']).default('all'),
  streetIds: z.array(uuid).default([]),
  buildingIds: z.array(uuid).default([]),
  groupChat: z.boolean().default(false),
});

async function checkForm(b: z.infer<typeof formBody>, userId: string, communityId: string) {
  if (b.imageIds.length) {
    const ok = await q(`select id from media where id = any($1) and owner_id = $2 and kind = 'photo'`, [b.imageIds, userId]);
    if (ok.length !== new Set(b.imageIds).size) throw badRequest('MEDIA_INVALID', 'One of the images could not be found. Please add it again.');
  }
  if (b.documentId && !(await one(`select 1 from media where id = $1 and owner_id = $2 and kind = 'document'`, [b.documentId, userId]))) {
    throw badRequest('MEDIA_INVALID', 'The document could not be found. Please add it again.');
  }
  if (b.audience === 'sub') {
    if (!b.streetIds.length && !b.buildingIds.length) throw badRequest('AUDIENCE_REQUIRED', 'Choose at least one street or building.');
    const opts = await audienceOptions(communityId);
    if (b.streetIds.some((s) => !opts.streets.find((x) => x.id === s)) || b.buildingIds.some((s) => !opts.buildings.find((x) => x.id === s))) {
      throw badRequest('AUDIENCE_INVALID', 'Choose streets and buildings in your community.');
    }
  }
}

async function audienceOptions(communityId: string, search = '') {
  const streets = await q<{ id: string; name: string }>(
    `select s.id, s.name from street_links l join streets s on s.id = l.street_id where l.community_id = $1 and s.name ilike '%' || $2 || '%' order by s.name`,
    [communityId, search],
  );
  const buildings = await q<{ id: string; name: string }>(
    `select id, name from communities where type = 'building' and parent_id = $1 and name ilike '%' || $2 || '%' order by name`,
    [communityId, search],
  );
  return { streets, buildings };
}

async function saveTargets(c: Db, id: string, b: z.infer<typeof formBody>) {
  await q('delete from update_targets where update_id = $1', [id], c);
  await q('delete from update_media where update_id = $1', [id], c);
  if (b.audience === 'sub') {
    for (const s of b.streetIds) await q('insert into update_targets(update_id, street_id) values ($1,$2)', [id, s], c);
    for (const x of b.buildingIds) await q('insert into update_targets(update_id, building_id) values ($1,$2)', [id, x], c);
  }
  for (const [i, m] of b.imageIds.entries()) await q('insert into update_media(update_id, media_id, position) values ($1,$2,$3)', [id, m, i], c);
}

async function additionalView(a: any, viewer: string) {
  if (a.deleted_at) return { id: a.id, deleted: true, text: 'Additional update is no longer available.', createdAt: a.created_at };
  const [author, img, ment] = await Promise.all([
    person(a.author_id),
    a.media_id ? one<{ url: string }>('select url from media where id = $1', [a.media_id]) : Promise.resolve(undefined),
    people(a.mention_ids ?? []),
  ]);
  return {
    id: a.id, deleted: false, author, text: a.text, imageUrl: img?.url ?? null,
    mentions: [...ment.values()].map((p) => ({ id: p.id, name: p.name })),
    isMine: a.author_id === viewer, createdAt: a.created_at, editedAt: a.edited_at,
  };
}

export async function updateRoutes(app: FastifyInstance) {
  // UPD-01: list, pinned (max 3, per user) on top.
  app.get('/updates', async (req) => {
    const u = requireUser(req);
    const live = await visibleList(u.id, 'live');
    const cards = await Promise.all(live.map((x) => card(x, u.id)));
    const pinned = cards.filter((c) => c.pinned);
    const rest = cards.filter((c) => !c.pinned);
    const resolved = (await visibleList(u.id, 'resolved')).length;
    return { updates: [...pinned, ...rest], hasResolved: resolved > 0, canCreate: await isCommittee(u.id) };
  });

  // UPD-14: resolved updates with title search.
  app.get('/updates/resolved', async (req) => {
    const u = requireUser(req);
    const { q: search } = z.object({ q: z.string().trim().optional() }).parse(req.query);
    const rows = await visibleList(u.id, 'resolved', search || undefined);
    return { updates: await Promise.all(rows.map((x) => card(x, u.id))) };
  });

  app.get('/updates/audience-options', async (req) => {
    const u = requireUser(req);
    const { q: search } = z.object({ q: z.string().trim().default('') }).parse(req.query);
    return audienceOptions((await communityOf(u.id))!, search);
  });

  // UPD-02 - UPD-04: committee only.
  app.post('/updates', async (req) => {
    const u = requireUser(req);
    const b = formBody.parse(req.body);
    if (!(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee members can post updates.');
    const community = (await communityOf(u.id))!;
    await checkForm(b, u.id, community);
    const up = await tx(async (c) => {
      const row = (await one<Update>(
        `insert into updates(community_id, author_id, title, details, audience, document_media_id, created_at) values ($1,$2,$3,$4,$5,$6,$7) returning *`,
        [community, u.id, b.title, b.details, b.audience, b.documentId ?? null, clock.now()], c,
      ))!;
      await saveTargets(c, row.id, b);
      // The author has read their own update.
      await q('insert into update_reads(user_id, update_id, seen_at) values ($1,$2,$3)', [u.id, row.id, row.created_at], c);
      if (b.groupChat) row.chat_id = await createUpdateChat(c, row);
      return row;
    });
    // UPD-04.2: only the audience is notified.
    await notifyAudience(up, u.id, 'update_new');
    return { update: await card(up, u.id), message: 'Your update is now live.', chatId: up.chat_id };
  });

  // UPD-05: detail; opening it marks additional updates as seen.
  app.get('/updates/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const up = await loadUpdate(id, u.id);
    const extras = await q<any>('select * from additional_updates where update_id = $1 and (deleted_at is null or true) order by created_at', [id]);
    await q(`insert into update_reads(user_id, update_id, seen_at) values ($1,$2,$3) on conflict (user_id, update_id) do update set seen_at = excluded.seen_at`, [u.id, id, clock.now()]);
    let document = null;
    if (up.document_media_id) {
      const d = await one<any>('select original_name, size_bytes, mime from media where id = $1', [up.document_media_id]);
      document = { name: d?.original_name, sizeBytes: d?.size_bytes, fileType: (d?.original_name?.split('.').pop() ?? 'pdf').toUpperCase(), downloads: up.document_downloads };
    }
    const committee = await isCommittee(u.id);
    let chat = null;
    if (up.chat_id) {
      const m = await one<{ left_at: Date | null }>('select left_at from chat_members where chat_id = $1 and user_id = $2', [up.chat_id, u.id]);
      chat = { id: up.chat_id, joined: !!m && !m.left_at };
    }
    return {
      update: {
        ...(await card(up, u.id)),
        document,
        additional: await Promise.all(extras.filter((e) => !e.deleted_at || true).map((e) => additionalView(e, u.id))),
        canAddAdditional: committee && up.status === 'live',
        chat,
      },
    };
  });

  // UPD-11: creator edits (can turn the chat on, never off).
  app.patch('/updates/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = formBody.parse(req.body);
    const up = await loadUpdate(id, u.id);
    if (up.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the creator can edit this update.');
    if (up.status !== 'live') throw conflict('NOT_LIVE', 'Resolved updates cannot be edited.');
    if (up.chat_id && !b.groupChat) throw badRequest('CHAT_LOCKED', 'The group chat for this update cannot be turned off.');
    await checkForm(b, u.id, up.community_id);
    await tx(async (c) => {
      await q(`update updates set title = $2, details = $3, audience = $4, document_media_id = $5, edited_at = $6 where id = $1`, [id, b.title, b.details, b.audience, b.documentId ?? null, clock.now()], c);
      await saveTargets(c, id, b);
      if (up.chat_id) await q('update chats set name = $2 where id = $1', [up.chat_id, b.title], c);
      if (b.groupChat && !up.chat_id) await createUpdateChat(c, { ...up, title: b.title });
    });
    const fresh = (await one<Update>('select * from updates where id = $1', [id]))!;
    return { update: await card(fresh, u.id), message: 'Changes saved to update.' };
  });

  // UPD-12: creator or the Chair resolves.
  app.post('/updates/:id/resolve', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const up = await loadUpdate(id, u.id);
    const chair = (await seatOf(u.id))?.role === 'Chair';
    if (up.author_id !== u.id && !chair) throw forbidden('NOT_ALLOWED', 'Only the creator or the Chair can resolve this update.');
    if (up.status !== 'live') throw conflict('NOT_LIVE', 'This update is already resolved.');
    await q(`update updates set status = 'resolved', resolved_at = $2, resolved_by = $3 where id = $1`, [id, clock.now(), u.id]);
    await closeChat(up);
    return { message: 'Update has been resolved' };
  });

  // UPD-13: creator deletes for everyone.
  app.delete('/updates/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const up = await loadUpdate(id, u.id);
    if (up.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the creator can delete this update.');
    await q(`update updates set status = 'deleted' where id = $1`, [id]);
    await closeChat(up);
    return { message: 'Your update has been deleted.' };
  });

  // UPD-05.3: unverified residents cannot download update documents.
  app.post('/updates/:id/document/download', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const up = await loadUpdate(id, u.id, { allowGone: false });
    if (!up.document_media_id) throw notFound('This update has no document.');
    const m = (await one<{ url: string; original_name: string }>('select url, original_name from media where id = $1', [up.document_media_id]))!;
    await q('update updates set document_downloads = document_downloads + 1 where id = $1', [id]);
    return { url: m.url, name: m.original_name };
  });

  // UPD-06: committee adds follow-ups; @tags of committee members only.
  app.post('/updates/:id/additional', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({ text: z.string().trim().max(DETAILS_MAX).default(''), mediaId: uuid.optional(), mentionIds: z.array(uuid).default([]) }).parse(req.body);
    const up = await loadUpdate(id, u.id);
    if (!(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee members can add additional updates.');
    if (up.status !== 'live') throw conflict('NOT_LIVE', 'This update is resolved. Additional updates are read-only.');
    if (!b.text && !b.mediaId) throw badRequest('EMPTY', 'Write an additional update or add an image.');
    if (b.mediaId && !(await one(`select 1 from media where id = $1 and owner_id = $2 and kind = 'photo'`, [b.mediaId, u.id]))) throw badRequest('MEDIA_INVALID', 'Choose an image.');
    const board = await boardFor(up.community_id);
    const committee = board ? new Set(await committeeIds(board.id)) : new Set<string>();
    const mentions = [...new Set(b.mentionIds)].filter((m) => committee.has(m) && m !== u.id);
    const a = (await one<any>(
      `insert into additional_updates(update_id, author_id, text, media_id, mention_ids, created_at) values ($1,$2,$3,$4,$5,$6) returning *`,
      [id, u.id, b.text, b.mediaId ?? null, mentions, clock.now()],
    ))!;
    await q(`insert into update_reads(user_id, update_id, seen_at) values ($1,$2,$3) on conflict (user_id, update_id) do update set seen_at = excluded.seen_at`, [u.id, id, a.created_at]);
    await notifyAudience(up, u.id, 'update_additional');
    for (const m of mentions) await notify(m, 'mention', u.id, { type: 'update', id });
    return { additional: await additionalView(a, u.id) };
  });
  // UPD-07
  app.patch('/additional-updates/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { text } = z.object({ text: z.string().trim().min(1).max(DETAILS_MAX) }).parse(req.body);
    const a = await one<any>('select * from additional_updates where id = $1', [id]);
    if (!a || a.deleted_at) throw notFound('Additional update is no longer available.');
    if (a.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the author can edit this.');
    const up = await loadUpdate(a.update_id, u.id);
    if (up.status !== 'live') throw conflict('NOT_LIVE', 'Additional updates on resolved updates are read-only.');
    await q('update additional_updates set text = $2, edited_at = $3 where id = $1', [id, text, clock.now()]);
    return { additional: await additionalView(await one('select * from additional_updates where id = $1', [id]), u.id) };
  });
  app.delete('/additional-updates/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const a = await one<any>('select * from additional_updates where id = $1', [id]);
    if (!a || a.deleted_at) throw notFound('Additional update is no longer available.');
    if (a.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the author can delete this.');
    await q('update additional_updates set deleted_at = $2 where id = $1', [id, clock.now()]);
    return { message: 'Additional update deleted.' };
  });

  // UPD-08: per-user pin, max 3.
  app.post('/updates/:id/pin', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadUpdate(id, u.id);
    const n = (await one<{ n: number }>(
      `select count(*)::int as n from update_pins p join updates x on x.id = p.update_id where p.user_id = $1 and x.status = 'live' and p.update_id <> $2`, [u.id, id],
    ))!.n;
    if (n >= PIN_MAX) throw conflict('PIN_LIMIT', 'You can only pin 3 updates');
    await q('insert into update_pins(user_id, update_id) values ($1,$2) on conflict do nothing', [u.id, id]);
    return { pinned: true };
  });
  app.delete('/updates/:id/pin', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await q('delete from update_pins where user_id = $1 and update_id = $2', [u.id, id]);
    return { pinned: false };
  });
  // UPD-09: mute one update.
  app.put('/updates/:id/mute', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { duration } = z.object({ duration: z.enum(['1h', '24h', '1w', 'forever']).nullable() }).parse(req.body);
    await loadUpdate(id, u.id);
    if (duration) await q(`insert into update_mutes(user_id, update_id, until) values ($1,$2,$3) on conflict (user_id, update_id) do update set until = excluded.until`, [u.id, id, muteUntil(duration)]);
    else await q('delete from update_mutes where user_id = $1 and update_id = $2', [u.id, id]);
    return { muted: !!duration };
  });
  // UPD-10: delete for me.
  app.post('/updates/:id/hide', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadUpdate(id, u.id, { allowGone: true });
    await q('insert into update_hides(user_id, update_id) values ($1,$2) on conflict do nothing', [u.id, id]);
    return { message: 'Update deleted.' };
  });

  // UCH-02: residents in the audience join from the update; no invite link.
  app.post('/updates/:id/chat/join', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const up = await loadUpdate(id, u.id);
    if (!up.chat_id) throw notFound('This update has no group chat.');
    const inAudience = (await audienceIds(up)).includes(u.id) || (await isCommittee(u.id));
    if (!inAudience) throw forbidden('NOT_IN_AUDIENCE', 'This group chat is for residents this update affects.');
    const chat = await one<{ read_only: boolean }>('select read_only from chats where id = $1', [up.chat_id]);
    if (chat?.read_only) throw conflict('READ_ONLY', 'This chat is closed. You can still read the messages.');
    const m = await one<{ left_at: Date | null }>('select left_at from chat_members where chat_id = $1 and user_id = $2', [up.chat_id, u.id]);
    if (!m || m.left_at) {
      await addMember(up.chat_id, u.id, 'member');
      await system(up.chat_id, 'joined', u.id, null, `${(await person(u.id))!.name} joined this group`);
    }
    return { chatId: up.chat_id };
  });
}

