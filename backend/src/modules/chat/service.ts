import { one, q, type Db } from '../../db/pool.js';
import { clock } from '../../lib/clock.js';
import { AppError, badRequest, forbidden, notFound } from '../../lib/errors.js';
import { linkPreview } from '../../lib/linkPreview.js';
import { people, person } from '../../lib/people.js';

export const TEXT_MAX = 5000;
export const NAME_MAX = 100;
export const DESCRIPTION_MAX = 400;
export const PIN_MAX = 3;
export const FORWARD_MAX = 5;
export const REQUEST_LIMIT = 2;
export const PAST_MEMBER_DAYS = 60;

export interface Chat {
  id: string; community_id: string; type: string; name: string | null; description: string | null; icon_url: string | null;
  created_by: string | null; requester_id: string | null; accepted_at: Date | null; members_can_message: boolean;
  members_can_invite: boolean; approval_required: boolean; committee_only: boolean; invite_code: string | null;
  read_only: boolean; update_id: string | null; last_message_at: Date; created_at: Date;
}
export interface Member { chat_id: string; user_id: string; role: 'admin' | 'member'; joined_at: Date; left_at: Date | null; muted_until: Date | null; pinned_at: Date | null; cleared_at: Date | null; hidden_at: Date | null; request_deleted_at: Date | null; delivered_at: Date | null; read_at: Date | null }

// ------------------------------------------------------------ realtime hub
type Socket = { send: (s: string) => void; readyState: number };
const sockets = new Map<string, Set<Socket>>();
const typing = new Map<string, Map<string, number>>(); // chatId -> userId -> until(ms)

export function addSocket(userId: string, s: Socket) {
  if (!sockets.has(userId)) sockets.set(userId, new Set());
  sockets.get(userId)!.add(s);
}
export function removeSocket(userId: string, s: Socket) {
  sockets.get(userId)?.delete(s);
}
export function emit(userIds: string[], event: Record<string, unknown>) {
  const data = JSON.stringify(event);
  for (const u of new Set(userIds)) for (const s of sockets.get(u) ?? []) if (s.readyState === 1) s.send(data);
}
export function setTyping(chatId: string, userId: string) {
  if (!typing.has(chatId)) typing.set(chatId, new Map());
  typing.get(chatId)!.set(userId, Date.now() + 6000);
}
export function typingIn(chatId: string, except: string) {
  const m = typing.get(chatId);
  if (!m) return [];
  return [...m.entries()].filter(([u, until]) => u !== except && until > Date.now()).map(([u]) => u);
}

// ------------------------------------------------------------ lookups
export async function chatOr404(id: string, db?: Db) {
  const c = await one<Chat>('select * from chats where id = $1', [id], db);
  if (!c) throw notFound('This chat is not available.');
  return c;
}
export async function membership(chatId: string, userId: string, db?: Db) {
  return one<Member>('select * from chat_members where chat_id = $1 and user_id = $2', [chatId, userId], db);
}
export async function activeMember(chatId: string, userId: string, db?: Db) {
  const m = await membership(chatId, userId, db);
  return m && !m.left_at ? m : undefined;
}
export async function requireMember(chatId: string, userId: string) {
  const c = await chatOr404(chatId);
  const m = await membership(chatId, userId);
  if (!m) throw notFound('This chat is not available.');
  return { c, m };
}
export async function requireAdmin(chatId: string, userId: string) {
  const x = await requireMember(chatId, userId);
  if (x.m.left_at || x.m.role !== 'admin') throw forbidden('ADMIN_ONLY', 'Only group admins can do this.');
  if (x.c.type === 'direct') throw badRequest('NOT_A_GROUP', 'This is not a group.');
  return x;
}
export async function activeMemberIds(chatId: string, db?: Db) {
  return (await q<{ user_id: string }>('select user_id from chat_members where chat_id = $1 and left_at is null', [chatId], db)).map((r) => r.user_id);
}
export async function otherMember(chatId: string, userId: string) {
  return (await one<{ user_id: string }>('select user_id from chat_members where chat_id = $1 and user_id <> $2', [chatId, userId]))?.user_id;
}
export async function blockedEither(a: string, b: string) {
  return {
    iBlocked: !!(await one('select 1 from blocks where user_id = $1 and target_id = $2', [a, b])),
    theyBlocked: !!(await one('select 1 from blocks where user_id = $1 and target_id = $2', [b, a])),
  };
}

// ------------------------------------------------------------ system messages (CHT-17)
export async function system(chatId: string, type: string, actorId: string | null, targetId: string | null, text: string, db?: Db) {
  const m = (await one<{ id: string; created_at: Date }>(
    `insert into messages(chat_id, kind, text, system, created_at) values ($1,'system',$2,$3,$4) returning id, created_at`,
    [chatId, text, { type, actorId, targetId }, clock.now()], db,
  ))!;
  await q('update chats set last_message_at = $2 where id = $1', [chatId, m.created_at], db);
  const members = await activeMemberIds(chatId, db);
  emit(members, { type: 'message', chatId });
  return m.id;
}

export async function addMember(chatId: string, userId: string, role: 'admin' | 'member', db?: Db) {
  await q(
    `insert into chat_members(chat_id, user_id, role, joined_at) values ($1,$2,$3,$4)
     on conflict (chat_id, user_id) do update set left_at = null, left_reason = null, role = excluded.role, joined_at = excluded.joined_at, hidden_at = null`,
    [chatId, userId, role, clock.now()], db,
  );
}

export async function removeMember(chatId: string, userId: string, reason: 'left' | 'removed', db?: Db) {
  await q(`update chat_members set left_at = $3, left_reason = $4 where chat_id = $1 and user_id = $2 and left_at is null`, [chatId, userId, clock.now(), reason], db);
  // EVT-17.3: leaving the event chat ends volunteering; removal also stops them volunteering again.
  await q(
    `update event_volunteers set status = $3 where user_id = $2 and status = 'active' and event_id in (select id from events where chat_id = $1)`,
    [chatId, userId, reason], db,
  );
}

// ------------------------------------------------------------ sending
export interface SendInput {
  text?: string;
  mediaIds?: string[];
  documentId?: string;
  voiceId?: string;
  replyToId?: string;
  forwarded?: boolean;
}

async function ownMedia(ids: string[], owner: string, kinds: string[]) {
  if (!ids.length) return;
  const rows = await q<{ id: string }>(`select id from media where id = any($1) and owner_id = $2 and kind = any($3)`, [ids, owner, kinds]);
  if (rows.length !== new Set(ids).size) throw badRequest('MEDIA_INVALID', 'One of the files could not be found. Please add it again.');
}

/** Sends a message, enforcing every chat rule (CHT-04, CHT-05, CHT-12.3, UCH-04). */
export async function send(chatId: string, senderId: string, input: SendInput, opts: { skipMediaOwner?: boolean } = {}) {
  const c = await chatOr404(chatId);
  const m = await activeMember(chatId, senderId);
  if (!m) throw forbidden('NOT_A_MEMBER', 'You cannot send messages to this group because you are no longer a member');
  if (c.read_only) throw forbidden('READ_ONLY', 'This chat is closed. You can still read the messages.');
  if (c.type !== 'direct' && !c.members_can_message && m.role !== 'admin') throw forbidden('ADMINS_ONLY', 'Only admins can send messages in this group.');
  const text = (input.text ?? '').trim();
  if (text.length > TEXT_MAX) throw badRequest('TOO_LONG', `Messages can be up to ${TEXT_MAX.toLocaleString('en-GB')} characters`);
  const media = input.mediaIds ?? [];
  const kinds = [media.length ? 'media' : null, input.documentId ? 'document' : null, input.voiceId ? 'voice' : null].filter(Boolean) as string[];
  if (kinds.length > 1) throw badRequest('ONE_KIND', 'Send photos, a document or a voice note separately.');
  if (!text && !kinds.length) throw badRequest('EMPTY', 'Write a message.');
  if (!opts.skipMediaOwner) {
    await ownMedia(media, senderId, ['photo', 'video']);
    if (input.documentId) await ownMedia([input.documentId], senderId, ['document']);
    if (input.voiceId) await ownMedia([input.voiceId], senderId, ['audio']);
  }
  if (input.replyToId && !(await one('select 1 from messages where id = $1 and chat_id = $2', [input.replyToId, chatId]))) {
    throw badRequest('REPLY_INVALID', 'The message you replied to is no longer available.');
  }

  let hiddenFrom: string[] = [];
  let accept = false;
  if (c.type === 'direct') {
    const other = (await otherMember(chatId, senderId))!;
    const b = await blockedEither(senderId, other);
    if (b.iBlocked) throw forbidden('BLOCKED', 'You blocked this user. Tap to unblock.');
    // CHT-05.5: the blocked person's messages show Sent and are never delivered.
    if (b.theyBlocked) hiddenFrom = [other];
    if (!c.accepted_at) {
      if (c.requester_id === senderId) {
        const sent = (await one<{ n: number }>(`select count(*)::int as n from messages where chat_id = $1 and sender_id = $2`, [chatId, senderId]))!.n;
        if (sent >= REQUEST_LIMIT) {
          throw forbidden('REQUEST_LIMIT', "You've reached your 2-message limit. You'll be able to send more messages once this user replies you.");
        }
      } else {
        accept = !b.theyBlocked; // CHT-04.3: replying lifts the limit
      }
    }
  }

  let link = null;
  const url = !kinds.length ? text.match(/https?:\/\/[^\s]+/)?.[0] : undefined;
  if (url) {
    try {
      link = await linkPreview(url);
    } catch {
      link = { url, title: url.replace(/^https?:\/\//, '').split('/')[0] };
    }
  }
  const kind = kinds[0] ?? 'text';
  const ids = kind === 'media' ? media : kind === 'document' ? [input.documentId!] : kind === 'voice' ? [input.voiceId!] : [];
  const now = clock.now();
  const row = (await one<any>(
    `insert into messages(chat_id, sender_id, kind, text, media_ids, link, reply_to_id, forwarded, hidden_from, created_at)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning *`,
    [chatId, senderId, kind, text, ids, link, input.replyToId ?? null, !!input.forwarded, hiddenFrom, now],
  ))!;
  await q('update chats set last_message_at = $2 where id = $1', [chatId, now]);
  if (accept) await q('update chats set accepted_at = $2 where id = $1', [chatId, now]);
  // Deleted-for-me chats come back with a new message (except a deleted request, CHT-04.4).
  await q(`update chat_members set hidden_at = null where chat_id = $1 and hidden_at is not null and user_id <> all($2)`, [chatId, hiddenFrom]);
  await q(`update chat_members set delivered_at = $3, read_at = $3 where chat_id = $1 and user_id = $2`, [chatId, senderId, now]);
  const recipients = (await activeMemberIds(chatId)).filter((u) => !hiddenFrom.includes(u));
  emit(recipients, { type: 'message', chatId, messageId: row.id });
  return row;
}

// ------------------------------------------------------------ views
export function durationLabel(sec: number | null | undefined) {
  const s = Math.round(sec ?? 0);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

async function mediaRows(ids: string[]) {
  if (!ids.length) return [];
  const rows = await q<any>('select id, kind, mime, url, size_bytes, duration_seconds, original_name from media where id = any($1)', [ids]);
  return ids.map((i) => rows.find((r) => r.id === i)).filter(Boolean);
}

export function preview(m: any, media: any[] = []) {
  if (m.deleted_for_all_at) return 'This message was deleted';
  switch (m.kind) {
    case 'media': return m.text || (media[0]?.kind === 'video' ? 'Video' : media.length > 1 ? `${media.length} photos` : 'Photo');
    case 'document': return media[0]?.original_name ?? 'Document';
    case 'voice': return `Voice message (${durationLabel(media[0]?.duration_seconds)})`;
    default: return m.text;
  }
}

/** Sent / delivered / Seen for the viewer's own messages (CHT-05.3). */
async function statusOf(m: any, c: Chat, others: Member[]) {
  if (m.hidden_from?.length) return 'sent';
  if (!others.length) return 'sent';
  const t = new Date(m.created_at).getTime();
  const seen = others.every((o) => o.read_at && o.read_at.getTime() >= t);
  // Read receipts only once a message request is accepted.
  if (seen && (c.type !== 'direct' || c.accepted_at)) return 'seen';
  return others.every((o) => o.delivered_at && o.delivered_at.getTime() >= t) ? 'delivered' : 'sent';
}

export async function messageViews(rows: any[], viewer: string, c: Chat) {
  const ps = await people(rows.map((r) => r.sender_id).filter(Boolean));
  const others = (await q<Member>('select * from chat_members where chat_id = $1 and user_id <> $2 and left_at is null', [c.id, viewer]));
  const replies = await q<any>('select * from messages where id = any($1)', [rows.map((r) => r.reply_to_id).filter(Boolean)]);
  const out = [];
  for (const m of rows) {
    const media = await mediaRows(m.media_ids ?? []);
    const reacts = await q<{ emoji: string; user_id: string }>('select emoji, user_id from message_reactions where message_id = $1', [m.id]);
    const grouped = new Map<string, { emoji: string; count: number; mine: boolean }>();
    for (const r of reacts) {
      const g = grouped.get(r.emoji) ?? { emoji: r.emoji, count: 0, mine: false };
      g.count++;
      if (r.user_id === viewer) g.mine = true;
      grouped.set(r.emoji, g);
    }
    const rep = m.reply_to_id ? replies.find((r) => r.id === m.reply_to_id) : undefined;
    const deleted = !!m.deleted_for_all_at;
    out.push({
      id: m.id,
      chatId: m.chat_id,
      kind: m.kind,
      sender: m.sender_id ? ps.get(m.sender_id) ?? null : null,
      isMine: m.sender_id === viewer,
      text: deleted ? 'This message was deleted' : m.text,
      deleted,
      media: deleted || m.kind !== 'media' ? [] : media.map((x) => ({ id: x.id, kind: x.kind, url: x.url, durationSeconds: x.duration_seconds })),
      document: deleted || m.kind !== 'document' ? null : media[0] && { id: media[0].id, url: media[0].url, name: media[0].original_name, mime: media[0].mime, sizeBytes: media[0].size_bytes },
      voice: deleted || m.kind !== 'voice' ? null : media[0] && { id: media[0].id, url: media[0].url, durationSeconds: media[0].duration_seconds, label: durationLabel(media[0].duration_seconds) },
      link: deleted ? null : m.link,
      replyTo: rep ? { id: rep.id, sender: rep.sender_id ? (await person(rep.sender_id))?.name : null, preview: preview(rep, await mediaRows(rep.media_ids ?? [])) } : null,
      forwarded: m.forwarded,
      system: m.kind === 'system' ? m.system : null,
      reactions: deleted ? [] : [...grouped.values()],
      status: m.sender_id === viewer && m.kind !== 'system' ? await statusOf(m, c, others) : null,
      createdAt: m.created_at,
    });
  }
  return out;
}

/** Messages the viewer can see: not hidden for them, not before they cleared or joined. */
export function visibleSql(viewerParam: string, memberAlias = 'cm') {
  return `not (${viewerParam} = any(m.hidden_from))
    and not exists (select 1 from message_hidden h where h.message_id = m.id and h.user_id = ${viewerParam})
    and (${memberAlias}.cleared_at is null or m.created_at > ${memberAlias}.cleared_at)
    and (${memberAlias}.left_at is null or m.created_at <= ${memberAlias}.left_at)`;
}

export async function chatTitle(c: Chat, viewer: string) {
  if (c.type === 'direct') {
    const other = await otherMember(c.id, viewer);
    const p = other ? await person(other) : undefined;
    return { name: p?.name ?? 'Keys user', iconUrl: p?.photoUrl ?? null, other: p ?? null };
  }
  if (c.name) return { name: c.name, iconUrl: c.icon_url, other: null };
  const ids = (await activeMemberIds(c.id)).filter((i) => i !== viewer).slice(0, 3);
  const ps = await people(ids);
  return { name: ids.map((i) => ps.get(i)?.firstName).filter(Boolean).join(', ') || 'Group', iconUrl: c.icon_url, other: null };
}

export function muteUntil(d: '1h' | '24h' | '1w' | 'forever') {
  const now = clock.now().getTime();
  return d === 'forever' ? new Date('9999-12-31T00:00:00Z') : new Date(now + { '1h': 3600e3, '24h': 86400e3, '1w': 7 * 86400e3 }[d]);
}

/** UCH-04.2: someone leaving the community or the board leaves its update chats. */
export async function leaveUpdateChats(userId: string, communityId: string) {
  const chats = await q<{ id: string }>(
    `select c.id from chats c join chat_members m on m.chat_id = c.id where c.type = 'update' and c.community_id = $1 and m.user_id = $2 and m.left_at is null`,
    [communityId, userId],
  );
  for (const c of chats) {
    await q(`update chat_members set left_at = $3, left_reason = 'removed' where chat_id = $1 and user_id = $2`, [c.id, userId, clock.now()]);
    await system(c.id, 'exited', userId, null, `${(await person(userId))?.name ?? 'A member'} left`);
  }
}

export { AppError };
