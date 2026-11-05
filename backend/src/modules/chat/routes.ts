import type { FastifyInstance } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { loadUser, requireUser } from '../../lib/auth.js';
import { clock, DAY, MINUTE } from '../../lib/clock.js';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { communityOf, hiddenAuthorSql, isCommittee, people, person } from '../../lib/people.js';
import {
  activeMember, activeMemberIds, addMember, addSocket, blockedEither, chatOr404, chatTitle, DESCRIPTION_MAX, emit, FORWARD_MAX,
  membership, messageViews, muteUntil, NAME_MAX, PAST_MEMBER_DAYS, PIN_MAX, preview, removeMember, removeSocket,
  requireAdmin, requireMember, send, setTyping, system, typingIn, visibleSql, type Chat,
} from './service.js';

const uuid = z.string().uuid();
const PAGE = 50;
const TABS = { all: null, primary: ['direct'], groups: ['group', 'update', 'club'], services: ['services'], volunteering: ['volunteering'], clubs: ['club'], events: ['event'] } as const;

async function sameCommunity(a: string, b: string) {
  const [x, y] = await Promise.all([communityOf(a), communityOf(b)]);
  return !!x && x === y;
}

/** One chat list cell (CHT-01.1). */
async function cell(c: Chat, viewer: string) {
  const m = (await membership(c.id, viewer))!;
  const title = await chatTitle(c, viewer);
  const last = await one<any>(
    `select m.* from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $2
      where m.chat_id = $1 and ${visibleSql('$2')} order by m.created_at desc limit 1`,
    [c.id, viewer],
  );
  const unread = (await one<{ n: number }>(
    `select count(*)::int as n from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $2
      where m.chat_id = $1 and m.sender_id is distinct from $2 and m.kind <> 'system' and (cm.read_at is null or m.created_at > cm.read_at) and ${visibleSql('$2')}`,
    [c.id, viewer],
  ))!.n;
  let blockedByMe = false;
  let online = false;
  if (c.type === 'direct' && title.other) {
    blockedByMe = (await blockedEither(viewer, title.other.id)).iBlocked;
    online = !!(await one(`select 1 from sessions where user_id = $1 and revoked_at is null and last_seen_at > $2`, [title.other.id, new Date(clock.now().getTime() - 5 * MINUTE)]));
  }
  const media = last ? await q<any>('select kind, original_name, duration_seconds from media where id = any($1)', [last.media_ids ?? []]) : [];
  const typers = typingIn(c.id, viewer);
  return {
    id: c.id,
    type: c.type,
    name: title.name,
    iconUrl: title.iconUrl,
    otherUserId: title.other?.id ?? null,
    lastMessage: last ? { text: last.kind === 'system' ? last.text : preview(last, media), isMine: last.sender_id === viewer, at: last.created_at } : null,
    typing: typers.length > 0,
    unread,
    muted: !!m.muted_until && m.muted_until > clock.now(),
    pinned: !!m.pinned_at,
    isRequest: c.type === 'direct' && !c.accepted_at && c.requester_id !== viewer,
    blockedByMe,
    online,
    left: !!m.left_at,
    readOnly: c.read_only,
    at: c.last_message_at,
  };
}

export async function chatRoutes(app: FastifyInstance) {
  // Realtime: new messages, typing and receipts are pushed over a websocket.
  app.get('/ws', { websocket: true }, async (socket, req) => {
    const token = (req.query as any).token as string | undefined;
    if (token) req.headers.authorization = `Bearer ${token}`;
    const u = await loadUser(req);
    if (!u) return socket.close(4401, 'unauthorized');
    addSocket(u.id, socket as any);
    socket.on('close', () => removeSocket(u.id, socket as any));
  });

  // CHT-01: chat list with tabs; pinned first, then latest activity.
  app.get('/chats', async (req) => {
    const u = requireUser(req);
    const { tab } = z.object({ tab: z.enum(Object.keys(TABS) as [keyof typeof TABS]).default('all') }).parse(req.query);
    const types = TABS[tab];
    const rows = await q<Chat>(
      `select c.* from chats c join chat_members cm on cm.chat_id = c.id and cm.user_id = $1
        where cm.hidden_at is null and cm.request_deleted_at is null
          and ($2::text[] is null or c.type = any($2))
          and (c.type <> 'direct' or c.requester_id = $1 or c.accepted_at is not null
               or exists (select 1 from messages m where m.chat_id = c.id and not ($1 = any(m.hidden_from))))
        order by cm.pinned_at desc nulls last, c.last_message_at desc`,
      [u.id, types],
    );
    // Opening the list counts as delivered.
    await q('update chat_members set delivered_at = $2 where user_id = $1', [u.id, clock.now()]);
    return { tabs: Object.keys(TABS), chats: await Promise.all(rows.map((c) => cell(c, u.id))) };
  });

  // CHT-01.4: residents active in the last 5 minutes.
  app.get('/chats/active', async (req) => {
    const u = requireUser(req);
    const c = await communityOf(u.id);
    const rows = await q<{ user_id: string }>(
      `select distinct m.user_id from memberships m join sessions s on s.user_id = m.user_id
        where m.community_id = $1 and m.user_id <> $2 and s.revoked_at is null and s.last_seen_at > $3 and not ${hiddenAuthorSql('m.user_id', '$2')}`,
      [c, u.id, new Date(clock.now().getTime() - 5 * MINUTE)],
    );
    return { people: [...(await people(rows.map((r) => r.user_id))).values()] };
  });

  // CHT-03.1: residents A to Z with roles; vendors are not residents so never listed.
  app.get('/chats/people', async (req) => {
    const u = requireUser(req);
    const { q: text, committeeOnly } = z.object({ q: z.string().default(''), committeeOnly: z.enum(['1']).optional() }).parse(req.query);
    const c = await communityOf(u.id);
    const rows = await q<{ id: string }>(
      `select u.id from memberships m join users u on u.id = m.user_id left join board_seats s on s.occupant_id = u.id
        where m.community_id = $1 and u.id <> $2 and u.deactivated_at is null and not ${hiddenAuthorSql('u.id', '$2')}
          and (u.first_name || ' ' || u.last_name) ilike '%' || $3 || '%'
          and ($4::boolean is false or (s.kind is not null and s.kind <> 'champion'))
        order by u.first_name, u.last_name`,
      [c, u.id, text.trim(), !!committeeOnly],
    );
    const ps = await people(rows.map((r) => r.id));
    return { people: rows.map((r) => ps.get(r.id)) };
  });

  // CHT-03.3: open (or create) a direct chat.
  app.post('/chats/direct', async (req) => {
    const u = requireUser(req);
    const { userId } = z.object({ userId: uuid }).parse(req.body);
    if (userId === u.id) throw badRequest('SELF', 'You cannot message yourself.');
    if (!(await sameCommunity(u.id, userId))) throw notFound('This resident is not available.');
    if (await one('select 1 from users where id = $1 and deactivated_at is not null', [userId])) throw notFound('This resident is not available.');
    const existing = await one<Chat>(
      `select c.* from chats c where c.type = 'direct'
         and exists (select 1 from chat_members a where a.chat_id = c.id and a.user_id = $1)
         and exists (select 1 from chat_members b where b.chat_id = c.id and b.user_id = $2)`,
      [u.id, userId],
    );
    if (existing) {
      await q('update chat_members set hidden_at = null where chat_id = $1 and user_id = $2', [existing.id, u.id]);
      return { chat: await cell(existing, u.id) };
    }
    const c = await tx(async (db) => {
      const row = (await one<Chat>(
        `insert into chats(community_id, type, created_by, requester_id) values ($1,'direct',$2,$2) returning *`,
        [await communityOf(u.id), u.id], db,
      ))!;
      await addMember(row.id, u.id, 'member', db);
      await addMember(row.id, userId, 'member', db);
      return row;
    });
    return { chat: await cell(c, u.id) };
  });

  app.get('/chats/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { c, m } = await requireMember(id, u.id);
    const title = await chatTitle(c, u.id);
    const base: any = {
      ...(await cell(c, u.id)),
      description: c.description,
      myRole: m.left_at ? null : m.role,
      isCreator: c.created_by === u.id,
      settings: { membersCanMessage: c.members_can_message, membersCanInvite: c.members_can_invite, approvalRequired: c.approval_required, committeeOnly: c.committee_only },
      canSend: !m.left_at && !c.read_only && (c.type === 'direct' || c.members_can_message || m.role === 'admin'),
      updateId: c.update_id,
      memberCount: (await activeMemberIds(c.id)).length,
    };
    if (c.type === 'direct' && title.other) {
      const sent = (await one<{ n: number }>(`select count(*)::int as n from messages where chat_id = $1 and sender_id = $2`, [c.id, u.id]))!.n;
      base.request = c.accepted_at
        ? null
        : c.requester_id === u.id
          ? { role: 'sender', remaining: Math.max(0, 2 - sent) }
          : { role: 'recipient', prompt: `Do you want to let ${title.other.name} message you? If you accept, they will also be able to see when you've read their messages.` };
      base.blockedByMe = (await blockedEither(u.id, title.other.id)).iBlocked;
    }
    if (m.left_at) base.leftReason = m.left_at ? 'You are no longer a member of this group' : null;
    return base;
  });

  // Messages, newest page first.
  app.get('/chats/:id/messages', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { before } = z.object({ before: z.string().datetime().optional() }).parse(req.query);
    const { c } = await requireMember(id, u.id);
    const rows = await q<any>(
      `select m.* from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $2
        where m.chat_id = $1 and ${visibleSql('$2')} and ($3::timestamptz is null or m.created_at < $3)
        order by m.created_at desc limit ${PAGE + 1}`,
      [id, u.id, before ?? null],
    );
    const page = rows.slice(0, PAGE).reverse();
    return { messages: await messageViews(page, u.id, c), hasMore: rows.length > PAGE };
  });

  app.post('/chats/:id/messages', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({
      text: z.string().optional(),
      mediaIds: z.array(uuid).max(10).optional(),
      documentId: uuid.optional(),
      voiceId: uuid.optional(),
      replyToId: uuid.optional(),
    }).parse(req.body);
    const row = await send(id, u.id, b);
    const c = await chatOr404(id);
    const out: any = { message: (await messageViews([row], u.id, c))[0] };
    // CHT-04.1: copy shown to the requester.
    if (c.type === 'direct' && !c.accepted_at && c.requester_id === u.id) {
      const sent = (await one<{ n: number }>(`select count(*)::int as n from messages where chat_id = $1 and sender_id = $2`, [id, u.id]))!.n;
      out.notice = sent >= 2
        ? "You've reached your 2-message limit. You'll be able to send more messages once this user replies you."
        : 'Your message request has been sent';
    }
    return out;
  });

  app.post('/chats/:id/read', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await requireMember(id, u.id);
    const now = clock.now();
    await q('update chat_members set read_at = $3, delivered_at = $3 where chat_id = $1 and user_id = $2', [id, u.id, now]);
    emit(await activeMemberIds(id), { type: 'read', chatId: id, userId: u.id });
    return { ok: true };
  });

  app.post('/chats/:id/typing', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    if (!(await activeMember(id, u.id))) throw notFound('This chat is not available.');
    setTyping(id, u.id);
    emit((await activeMemberIds(id)).filter((x) => x !== u.id), { type: 'typing', chatId: id, userId: u.id });
    return { ok: true };
  });

  // CHT-04.2 - CHT-04.4: accept or delete a message request.
  app.post('/chats/:id/accept', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { c } = await requireMember(id, u.id);
    if (c.type !== 'direct' || c.requester_id === u.id) throw badRequest('NOT_A_REQUEST', 'This is not a message request.');
    await q('update chats set accepted_at = coalesce(accepted_at, $2) where id = $1', [id, clock.now()]);
    return { ok: true };
  });
  app.post('/chats/:id/request/delete', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { c } = await requireMember(id, u.id);
    if (c.type !== 'direct' || c.requester_id === u.id || c.accepted_at) throw badRequest('NOT_A_REQUEST', 'This is not a message request.');
    await q('update chat_members set request_deleted_at = $3 where chat_id = $1 and user_id = $2', [id, u.id, clock.now()]);
    return { ok: true };
  });

  // CHT-02: pin (max 3), mute, delete for me, clear.
  app.post('/chats/:id/pin', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await requireMember(id, u.id);
    const n = (await one<{ n: number }>('select count(*)::int as n from chat_members where user_id = $1 and pinned_at is not null and chat_id <> $2', [u.id, id]))!.n;
    if (n >= PIN_MAX) throw conflict('PIN_LIMIT', 'You can only pin 3 chats');
    await q('update chat_members set pinned_at = coalesce(pinned_at, $3) where chat_id = $1 and user_id = $2', [id, u.id, clock.now()]);
    return { pinned: true };
  });
  app.delete('/chats/:id/pin', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await q('update chat_members set pinned_at = null where chat_id = $1 and user_id = $2', [id, u.id]);
    return { pinned: false };
  });
  app.put('/chats/:id/mute', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { duration } = z.object({ duration: z.enum(['1h', '24h', '1w', 'forever']).nullable() }).parse(req.body);
    await requireMember(id, u.id);
    await q('update chat_members set muted_until = $3 where chat_id = $1 and user_id = $2', [id, u.id, duration ? muteUntil(duration) : null]);
    return { muted: !!duration };
  });
  app.post('/chats/:id/hide', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await requireMember(id, u.id);
    await q('update chat_members set hidden_at = $3, cleared_at = $3, pinned_at = null where chat_id = $1 and user_id = $2', [id, u.id, clock.now()]);
    return { ok: true, message: 'Chat deleted' };
  });
  app.post('/chats/:id/clear', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await requireMember(id, u.id);
    await q('update chat_members set cleared_at = $3 where chat_id = $1 and user_id = $2', [id, u.id, clock.now()]);
    return { ok: true };
  });

  // CHT-08: delete, react, forward.
  async function myMessage(id: string, viewer: string) {
    const m = await one<any>('select * from messages where id = $1', [id]);
    if (!m || !(await membership(m.chat_id, viewer))) throw notFound('This message is not available.');
    return m;
  }
  app.delete('/messages/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { scope } = z.object({ scope: z.enum(['me', 'all']).default('me') }).parse(req.query);
    const m = await myMessage(id, u.id);
    if (scope === 'all') {
      if (m.sender_id !== u.id) throw forbidden('NOT_SENDER', 'You can only delete your own messages for everyone.');
      await q('update messages set deleted_for_all_at = $2 where id = $1', [id, clock.now()]);
      emit(await activeMemberIds(m.chat_id), { type: 'message', chatId: m.chat_id });
    } else {
      await q('insert into message_hidden(message_id, user_id) values ($1,$2) on conflict do nothing', [id, u.id]);
    }
    return { ok: true };
  });
  // CHT-08.6: one reaction per person; same emoji removes, another replaces.
  app.post('/messages/:id/react', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { emoji } = z.object({ emoji: z.string().min(1).max(16) }).parse(req.body);
    const m = await myMessage(id, u.id);
    if (!(await activeMember(m.chat_id, u.id))) throw forbidden('NOT_A_MEMBER', 'You are no longer a member of this chat.');
    const cur = await one<{ emoji: string }>('select emoji from message_reactions where message_id = $1 and user_id = $2', [id, u.id]);
    if (cur?.emoji === emoji) await q('delete from message_reactions where message_id = $1 and user_id = $2', [id, u.id]);
    else await q(`insert into message_reactions(message_id, user_id, emoji) values ($1,$2,$3) on conflict (message_id, user_id) do update set emoji = excluded.emoji`, [id, u.id, emoji]);
    emit(await activeMemberIds(m.chat_id), { type: 'message', chatId: m.chat_id });
    return { reaction: cur?.emoji === emoji ? null : emoji };
  });
  app.get('/messages/:id/reactions', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await myMessage(id, u.id);
    const rows = await q<{ user_id: string; emoji: string }>('select user_id, emoji from message_reactions where message_id = $1 order by created_at', [id]);
    const ps = await people(rows.map((r) => r.user_id));
    return { reactions: rows.map((r) => ({ emoji: r.emoji, person: ps.get(r.user_id) })) };
  });
  // CHT-08.4: up to 5 recipients (chats or residents), optional note sent separately.
  app.post('/messages/forward', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      messageIds: z.array(uuid).min(1).max(20),
      chatIds: z.array(uuid).default([]),
      userIds: z.array(uuid).default([]),
      note: z.string().max(5000).optional(),
    }).parse(req.body);
    if (b.chatIds.length + b.userIds.length === 0) throw badRequest('NO_RECIPIENT', 'Choose who to forward to.');
    if (b.chatIds.length + b.userIds.length > FORWARD_MAX) throw badRequest('TOO_MANY', `You can forward to up to ${FORWARD_MAX} chats`);
    const msgs = [];
    for (const id of b.messageIds) {
      const m = await myMessage(id, u.id);
      if (m.deleted_for_all_at || m.kind === 'system') throw badRequest('CANNOT_FORWARD', 'This message cannot be forwarded.');
      msgs.push(m);
    }
    const targets = [...b.chatIds];
    for (const uid of b.userIds) {
      if (!(await sameCommunity(u.id, uid))) continue;
      const r = await app.inject({ method: 'POST', url: '/chats/direct', headers: { authorization: req.headers.authorization! }, payload: { userId: uid } });
      targets.push(JSON.parse(r.body).chat.id);
    }
    const sent = [];
    for (const chatId of [...new Set(targets)]) {
      for (const m of msgs) {
        const input = { text: m.text, forwarded: true, ...(m.kind === 'media' ? { mediaIds: m.media_ids } : m.kind === 'document' ? { documentId: m.media_ids[0] } : m.kind === 'voice' ? { voiceId: m.media_ids[0] } : {}) };
        sent.push((await send(chatId, u.id, input, { skipMediaOwner: true })).id);
      }
      if (b.note?.trim()) await send(chatId, u.id, { text: b.note });
    }
    return { ok: true, count: sent.length };
  });

  // CHT-09: global and in-chat search over chats the user belongs to.
  app.get('/chats/search', async (req) => {
    const u = requireUser(req);
    const { q: text, type } = z.object({ q: z.string().trim().default(''), type: z.enum(['all', 'photos', 'videos', 'links', 'documents']).default('all') }).parse(req.query);
    const mine = await q<Chat>(`select c.* from chats c join chat_members cm on cm.chat_id = c.id where cm.user_id = $1 and cm.hidden_at is null`, [u.id]);
    const chats = [];
    if (type === 'all' && text) for (const c of mine) {
      const t = await chatTitle(c, u.id);
      if (t.name.toLowerCase().includes(text.toLowerCase())) chats.push(await cell(c, u.id));
    }
    const kindFilter = { all: '', photos: `and m.kind = 'media' and exists (select 1 from media x where x.id = any(m.media_ids) and x.kind = 'photo')`, videos: `and m.kind = 'media' and exists (select 1 from media x where x.id = any(m.media_ids) and x.kind = 'video')`, links: `and m.link is not null`, documents: `and m.kind = 'document'` }[type];
    const rows = await q<any>(
      `select m.* from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $1
        where cm.hidden_at is null and m.kind <> 'system' and m.deleted_for_all_at is null and ${visibleSql('$1')}
          and ($2 = '' or m.text ilike '%' || $2 || '%' or exists (select 1 from media x where x.id = any(m.media_ids) and x.original_name ilike '%' || $2 || '%'))
          ${kindFilter}
        order by m.created_at desc limit 50`,
      [u.id, text],
    );
    const byChat = new Map(mine.map((c) => [c.id, c]));
    const messages = [];
    for (const r of rows) messages.push({ ...(await messageViews([r], u.id, byChat.get(r.chat_id)!))[0], chatName: (await chatTitle(byChat.get(r.chat_id)!, u.id)).name });
    return { chats, messages };
  });
  app.get('/chats/:id/search', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { q: text } = z.object({ q: z.string().trim().min(1) }).parse(req.query);
    const { c } = await requireMember(id, u.id);
    const rows = await q<any>(
      `select m.* from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $2
        where m.chat_id = $1 and m.kind <> 'system' and m.deleted_for_all_at is null and ${visibleSql('$2')}
          and (m.text ilike '%' || $3 || '%' or exists (select 1 from media x where x.id = any(m.media_ids) and x.original_name ilike '%' || $3 || '%'))
        order by m.created_at`,
      [id, u.id, text],
    );
    return { matches: await messageViews(rows, u.id, c) };
  });

  // CHT-18: shared media, links and documents grouped by month.
  app.get('/chats/:id/shared', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { tab } = z.object({ tab: z.enum(['media', 'links', 'documents']) }).parse(req.query);
    const { c } = await requireMember(id, u.id);
    const where = { media: `m.kind = 'media'`, links: `m.link is not null`, documents: `m.kind = 'document'` }[tab];
    const rows = await q<any>(
      `select m.* from messages m join chat_members cm on cm.chat_id = m.chat_id and cm.user_id = $2
        where m.chat_id = $1 and ${where} and m.deleted_for_all_at is null and ${visibleSql('$2')} order by m.created_at desc`,
      [id, u.id],
    );
    const views = await messageViews(rows, u.id, c);
    const groups = new Map<string, any[]>();
    for (const v of views) {
      const key = new Date(v.createdAt).toLocaleString('en-GB', { month: 'long', year: 'numeric', timeZone: 'Europe/London' });
      groups.set(key, [...(groups.get(key) ?? []), v]);
    }
    return { groups: [...groups.entries()].map(([label, items]) => ({ label, items })) };
  });

  // ---------------------------------------------------------------- groups (CHT-11 - CHT-17)
  async function allowedMembers(creator: string, ids: string[], committeeOnly: boolean) {
    const out = [];
    for (const id of [...new Set(ids)].filter((i) => i !== creator)) {
      if (!(await sameCommunity(creator, id))) continue;
      if ((await blockedEither(creator, id)).iBlocked || (await blockedEither(creator, id)).theyBlocked) continue;
      if (committeeOnly && !(await isCommittee(id))) continue;
      out.push(id);
    }
    return out;
  }

  app.post('/chats/groups', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      name: z.string().trim().max(NAME_MAX).optional(),
      iconMediaId: uuid.optional(),
      memberIds: z.array(uuid).min(1, 'Select members'),
      membersCanMessage: z.boolean().default(true),
      membersCanInvite: z.boolean().default(true),
      approvalRequired: z.boolean().default(false),
      committeeOnly: z.boolean().default(false),
    }).parse(req.body);
    if (b.committeeOnly && !(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee members can create committee board groups.');
    const icon = b.iconMediaId ? await one<{ url: string }>(`select url from media where id = $1 and owner_id = $2 and kind = 'photo'`, [b.iconMediaId, u.id]) : undefined;
    const members = await allowedMembers(u.id, b.memberIds, b.committeeOnly);
    if (!members.length) throw badRequest('NO_MEMBERS', 'Select members');
    const c = await tx(async (db) => {
      const row = (await one<Chat>(
        `insert into chats(community_id, type, name, icon_url, created_by, members_can_message, members_can_invite, approval_required, committee_only)
         values ($1,'group',$2,$3,$4,$5,$6,$7,$8) returning *`,
        [await communityOf(u.id), b.name || null, icon?.url ?? null, u.id, b.membersCanMessage, b.membersCanInvite, b.approvalRequired, b.committeeOnly], db,
      ))!;
      await addMember(row.id, u.id, 'admin', db);
      for (const m of members) await addMember(row.id, m, 'member', db);
      return row;
    });
    const me = (await person(u.id))!;
    await system(c.id, 'created', u.id, null, `${me.name} created this group`);
    return { chat: await cell(c, u.id) };
  });

  app.patch('/chats/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({
      name: z.string().trim().max(NAME_MAX).optional(),
      description: z.string().trim().max(DESCRIPTION_MAX).optional(),
      iconMediaId: uuid.optional(),
    }).parse(req.body);
    const { c } = await requireAdmin(id, u.id);
    const me = (await person(u.id))!;
    const messages: string[] = [];
    if (b.name !== undefined) {
      if (c.type === 'update') throw forbidden('NAME_LOCKED', 'The name of an update chat follows the update title.');
      await q('update chats set name = $2 where id = $1', [id, b.name || null]);
      await system(id, 'renamed', u.id, null, `${me.name} changed the group name to "${b.name}"`);
      messages.push('Group name updated.');
    }
    if (b.description !== undefined) {
      await q('update chats set description = $2 where id = $1', [id, b.description || null]);
      await system(id, 'description', u.id, null, `${me.name} changed the group description`);
      messages.push('Group description updated.');
    }
    if (b.iconMediaId) {
      const icon = await one<{ url: string }>(`select url from media where id = $1 and owner_id = $2 and kind = 'photo'`, [b.iconMediaId, u.id]);
      if (!icon) throw badRequest('MEDIA_INVALID', 'Choose a photo.');
      await q('update chats set icon_url = $2 where id = $1', [id, icon.url]);
      await system(id, 'icon', u.id, null, `${me.name} changed the group icon`);
      messages.push('Group icon updated.');
    }
    return { ok: true, message: messages.join(' ') };
  });

  app.put('/chats/:id/settings', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({
      membersCanMessage: z.boolean().optional(),
      membersCanInvite: z.boolean().optional(),
      approvalRequired: z.boolean().optional(),
      committeeOnly: z.boolean().optional(),
    }).parse(req.body);
    const { c } = await requireAdmin(id, u.id);
    if (b.committeeOnly && !(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee members can make a committee board group.');
    const me = (await person(u.id))!;
    if (b.membersCanMessage !== undefined && b.membersCanMessage !== c.members_can_message) {
      await q('update chats set members_can_message = $2 where id = $1', [id, b.membersCanMessage]);
      await system(id, 'settings', u.id, null, b.membersCanMessage
        ? `${me.name} changed this group's settings to allow all members to send messages`
        : `${me.name} changed this group's settings to allow only admins to send messages`);
    }
    if (b.membersCanInvite !== undefined && b.membersCanInvite !== c.members_can_invite) {
      await q('update chats set members_can_invite = $2 where id = $1', [id, b.membersCanInvite]);
      await system(id, 'settings', u.id, null, b.membersCanInvite
        ? `${me.name} changed this group's settings to allow all members to add others`
        : `${me.name} changed this group's settings to allow only admins to add others`);
    }
    let approved = 0;
    if (b.approvalRequired !== undefined && b.approvalRequired !== c.approval_required) {
      await q('update chats set approval_required = $2 where id = $1', [id, b.approvalRequired]);
      if (!b.approvalRequired) {
        // CHT-12.2: turning approval off approves everyone waiting.
        const pending = await q<{ user_id: string }>(`update chat_join_requests set status = 'approved' where chat_id = $1 and status = 'pending' returning user_id`, [id]);
        for (const p of pending) await addMember(id, p.user_id, 'member');
        approved = pending.length;
      }
      await system(id, 'settings', u.id, null, b.approvalRequired ? `${me.name} turned on admin approval to join this group` : `${me.name} turned off admin approval to join this group`);
    }
    if (b.committeeOnly !== undefined) await q('update chats set committee_only = $2 where id = $1', [id, b.committeeOnly]);
    return { ok: true, approved };
  });

  // CHT-14.1 / CHT-14.2: add members (or pending approval).
  app.post('/chats/:id/members', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { userIds } = z.object({ userIds: z.array(uuid).min(1) }).parse(req.body);
    const { c, m } = await requireMember(id, u.id);
    if (m.left_at) throw forbidden('NOT_A_MEMBER', 'You are no longer a member of this group.');
    if (c.type === 'direct') throw badRequest('NOT_A_GROUP', 'This is not a group.');
    if (c.type === 'update') throw forbidden('UPDATE_CHAT', 'Residents join update chats from the update.');
    const admin = m.role === 'admin';
    if (!admin && !c.members_can_invite) throw forbidden('ADMINS_ADD_ONLY', 'Only admins can add others to this group');
    const ids = await allowedMembers(u.id, userIds, c.committee_only);
    const me = (await person(u.id))!;
    if (c.approval_required && !admin) {
      for (const x of ids) await q(`insert into chat_join_requests(chat_id, user_id, added_by) values ($1,$2,$3) on conflict (chat_id, user_id) do update set status = 'pending', added_by = excluded.added_by`, [id, x, u.id]);
      return { added: 0, pending: ids.length, message: 'Members pending approval' };
    }
    for (const x of ids) {
      await addMember(id, x, 'member');
      await system(id, 'added', u.id, x, `${me.name} added ${(await person(x))!.name}`);
    }
    return { added: ids.length, pending: 0, message: `Users added to ${(await chatTitle(c, u.id)).name}.` };
  });

  // CHT-15: remove, make / dismiss admin; the creator is protected.
  app.delete('/chats/:id/members/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const { c } = await requireAdmin(id, u.id);
    const target = (await person(userId))!;
    if (c.created_by === userId) throw forbidden('CREATOR', `You can't remove ${target.name} as admin because they created this group chat`);
    if (!(await activeMember(id, userId))) throw notFound('This member is not in the group.');
    await removeMember(id, userId, 'removed');
    await system(id, 'removed', u.id, userId, `${(await person(u.id))!.name} removed ${target.name}`);
    return { ok: true, message: 'Member removed' };
  });
  app.post('/chats/:id/admins/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    await requireAdmin(id, u.id);
    if (!(await activeMember(id, userId))) throw notFound('This member is not in the group.');
    await q(`update chat_members set role = 'admin' where chat_id = $1 and user_id = $2`, [id, userId]);
    await system(id, 'admin_added', u.id, userId, `${(await person(u.id))!.name} made ${(await person(userId))!.name} an admin`);
    return { ok: true };
  });
  app.delete('/chats/:id/admins/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const { c } = await requireAdmin(id, u.id);
    const target = (await person(userId))!;
    if (c.created_by === userId) throw forbidden('CREATOR', `You can't dismiss ${target.name} as admin because they created this group chat`);
    await q(`update chat_members set role = 'member' where chat_id = $1 and user_id = $2`, [id, userId]);
    await system(id, 'admin_removed', u.id, userId, `${(await person(u.id))!.name} dismissed ${target.name} as admin`);
    return { ok: true };
  });

  // CHT-16: exit; the only admin must hand over first.
  app.post('/chats/:id/exit', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { newAdminId } = z.object({ newAdminId: uuid.optional() }).parse(req.body ?? {});
    const { c, m } = await requireMember(id, u.id);
    if (c.type === 'direct') throw badRequest('NOT_A_GROUP', 'This is not a group.');
    if (m.left_at) throw badRequest('ALREADY_LEFT', 'You are no longer a member of this group');
    const others = (await activeMemberIds(id)).filter((x) => x !== u.id);
    if (m.role === 'admin' && others.length) {
      const admins = await q('select 1 from chat_members where chat_id = $1 and role = $2 and left_at is null and user_id <> $3', [id, 'admin', u.id]);
      if (!admins.length) {
        if (!newAdminId) throw conflict('ASSIGN_ADMIN', 'You are the only admin in this group, assign a new admin before leaving.');
        if (!others.includes(newAdminId)) throw badRequest('VALIDATION', 'Choose a member of this group.');
        await q(`update chat_members set role = 'admin' where chat_id = $1 and user_id = $2`, [id, newAdminId]);
        await system(id, 'admin_added', u.id, newAdminId, `${(await person(u.id))!.name} made ${(await person(newAdminId))!.name} an admin`);
      }
    }
    await removeMember(id, u.id, 'left');
    await system(id, 'exited', u.id, null, `${(await person(u.id))!.name} left`);
    return { ok: true, message: 'You are no longer a member of this group' };
  });

  // CHT-15.4: members with roles; past members (60 days) for admins.
  app.get('/chats/:id/members', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { m } = await requireMember(id, u.id);
    const rows = await q<any>('select * from chat_members where chat_id = $1 order by role, joined_at', [id]);
    const ps = await people(rows.map((r) => r.user_id));
    const active = rows.filter((r) => !r.left_at).map((r) => ({ person: ps.get(r.user_id), chatRole: r.role }));
    const past = m.role === 'admin' && !m.left_at
      ? rows.filter((r) => r.left_at && r.left_at.getTime() > clock.now().getTime() - PAST_MEMBER_DAYS * DAY).map((r) => ({ person: ps.get(r.user_id), leftAt: r.left_at, reason: r.left_reason }))
      : null;
    return { members: active, pastMembers: past };
  });

  // CHT-14.3 - CHT-14.6: invite link and join requests.
  app.post('/chats/:id/invite-link', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { c, m } = await requireMember(id, u.id);
    if (c.type !== 'group') throw forbidden('NO_LINK', 'This chat has no invite link.');
    if (m.left_at || (m.role !== 'admin' && !c.members_can_invite)) throw forbidden('ADMINS_ADD_ONLY', 'Only admins can add others to this group');
    let code = c.invite_code;
    if (!code) {
      code = randomBytes(9).toString('base64url');
      await q('update chats set invite_code = $2 where id = $1', [id, code]);
    }
    return { link: `${process.env.LINK_BASE_URL ?? 'https://keys.app'}/chat/${code}`, code, message: 'Group link copied.' };
  });
  app.get('/chats/join/:code', async (req) => {
    const u = requireUser(req);
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const c = await one<Chat>('select * from chats where invite_code = $1', [code]);
    if (!c || c.community_id !== (await communityOf(u.id))) throw notFound('This group link is not available.');
    const m = await activeMember(c.id, u.id);
    const r = await one<{ status: string }>('select status from chat_join_requests where chat_id = $1 and user_id = $2', [c.id, u.id]);
    return {
      chatId: c.id,
      name: (await chatTitle(c, u.id)).name,
      memberCount: (await activeMemberIds(c.id)).length,
      approvalRequired: c.approval_required,
      state: m ? 'member' : r?.status === 'pending' ? 'awaiting' : 'can_join',
      message: c.approval_required ? 'This group require admin permission to join' : null,
    };
  });
  app.post('/chats/join/:code', async (req) => {
    const u = requireUser(req);
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const c = await one<Chat>('select * from chats where invite_code = $1', [code]);
    if (!c || c.community_id !== (await communityOf(u.id))) throw notFound('This group link is not available.');
    if (c.committee_only && !(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee board members can join this group.');
    if (await activeMember(c.id, u.id)) return { state: 'member', chatId: c.id };
    const me = (await person(u.id))!;
    if (c.approval_required) {
      await q(`insert into chat_join_requests(chat_id, user_id) values ($1,$2) on conflict (chat_id, user_id) do update set status = 'pending'`, [c.id, u.id]);
      const n = (await one<{ n: number }>(`select count(*)::int as n from chat_join_requests where chat_id = $1 and status = 'pending'`, [c.id]))!.n;
      await system(c.id, 'requested', u.id, null, n > 1 ? `${n} new join requests` : `${me.name} requested to join`);
      return { state: 'awaiting', chatId: c.id, message: 'Awaiting admin approval' };
    }
    await addMember(c.id, u.id, 'member');
    await system(c.id, 'joined_link', u.id, null, `${me.name} joined via this group's link`);
    return { state: 'member', chatId: c.id };
  });
  app.delete('/chats/join/:code', async (req) => {
    const u = requireUser(req);
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const c = await one<Chat>('select * from chats where invite_code = $1', [code]);
    if (c) await q(`update chat_join_requests set status = 'cancelled' where chat_id = $1 and user_id = $2 and status = 'pending'`, [c.id, u.id]);
    return { ok: true };
  });
  app.get('/chats/:id/requests', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await requireAdmin(id, u.id);
    const rows = await q<any>(`select * from chat_join_requests where chat_id = $1 and status = 'pending' order by created_at`, [id]);
    const ps = await people(rows.map((r) => r.user_id));
    return { requests: rows.map((r) => ({ person: ps.get(r.user_id), requestedAt: r.created_at })) };
  });
  for (const action of ['approve', 'decline'] as const) {
    app.post(`/chats/:id/requests/:userId/${action}`, async (req) => {
      const u = requireUser(req);
      const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
      await requireAdmin(id, u.id);
      const r = await one(`update chat_join_requests set status = $3 where chat_id = $1 and user_id = $2 and status = 'pending' returning 1`, [id, userId, action === 'approve' ? 'approved' : 'declined']);
      if (!r) throw notFound('This request is no longer pending.');
      if (action === 'approve') {
        await addMember(id, userId, 'member');
        await system(id, 'added', u.id, userId, `${(await person(u.id))!.name} added ${(await person(userId))!.name}`);
      }
      return { ok: true };
    });
  }

}
