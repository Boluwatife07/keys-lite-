import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { requireUser, requireVerified } from '../../lib/auth.js';
import { clock, DAY, HOUR } from '../../lib/clock.js';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { notify, notifyAndEmail } from '../../lib/notify.js';
import { communityOf, people, person } from '../../lib/people.js';
import { addMember as addChatMember, muteUntil, system } from '../chat/service.js';
import { cancelEvent, eventCard, isCompleted, passEvents, type Event } from '../events/service.js';
import { postView } from '../feed/read.js';
import { shareLink } from '../links/routes.js';
import { addToClub, canManage, clubMemberIds, clubOr404, memberCount, removeFromClub, roleIn, type Club } from './service.js';
import { CLUB_CATEGORIES, CLUB_TEMPLATES } from './templates.js';

const uuid = z.string().uuid();
export const NAME_MAX = 60;
export const DESCRIPTION_MAX = 300;
export const LIMIT_MIN = 10;
export const CLOSE_HOURS = 48;
const MILESTONES = [50, 100, 250, 500, 1000];
const ATTEMPTS = 10;

async function coverUrl(c: Club) {
  return c.cover_media_id ? (await one<{ url: string }>('select url from media where id = $1', [c.cover_media_id]))?.url ?? null : null;
}

/** Club card (CLB-01.3). */
async function card(c: Club, viewer: string) {
  const [n, role, preview, president] = await Promise.all([
    memberCount(c.id),
    roleIn(c.id, viewer),
    q<{ user_id: string }>(`select user_id from club_members where club_id = $1 and user_id <> $2 order by case role when 'president' then 0 when 'admin' then 1 else 2 end, joined_at limit 3`, [c.id, viewer]),
    c.president_id ? person(c.president_id) : Promise.resolve(undefined),
  ]);
  const ps = await people(preview.map((p) => p.user_id));
  const names = preview.map((p) => ps.get(p.user_id)?.firstName).filter(Boolean) as string[];
  const others = Math.max(0, n - names.length - (role ? 1 : 0));
  return {
    id: c.id,
    name: c.name,
    description: c.description,
    category: c.category,
    price: 'Free',
    coverUrl: await coverUrl(c),
    memberCount: n,
    memberLimit: c.member_limit,
    full: n >= c.member_limit,
    president: president ?? null,
    myRole: role ?? null,
    isMember: !!role,
    membersPreview: preview.map((p) => ps.get(p.user_id)),
    // CLB-05.1: "[Names] and N others are in this club".
    membersText: names.length ? `${names.join(', ')}${others ? ` and ${others} other${others === 1 ? '' : 's'}` : ''} ${names.length + others === 1 ? 'is' : 'are'} in this club` : null,
    othersText: n > 0 ? `+${n} ${n === 1 ? 'other is' : 'others are'} in this club` : null,
    status: c.status,
    closingAt: c.closing_at,
    createdAt: c.created_at,
  };
}

async function detail(c: Club, viewer: string) {
  const base = await card(c, viewer);
  const muted = await one<{ muted_until: Date | null }>('select muted_until from club_members where club_id = $1 and user_id = $2', [c.id, viewer]);
  const transfer = await one<any>(`select * from club_transfers where club_id = $1 and status = 'pending' order by created_at desc limit 1`, [c.id]);
  const upcoming = (await one<{ n: number }>(`select count(*)::int as n from events where club_id = $1 and status = 'live' and end_at > $2`, [c.id, clock.now()]))!.n;
  return {
    ...base,
    chatId: base.isMember ? c.chat_id : null,
    muted: !!muted?.muted_until && muted.muted_until > clock.now(),
    upcomingEvents: upcoming,
    // CLB-11.2: the President sees the pending offer; the recipient sees it to answer.
    transfer: transfer && (base.myRole === 'president' || transfer.to_id === viewer)
      ? { id: transfer.id, to: await person(transfer.to_id), status: 'Awaiting response', forMe: transfer.to_id === viewer }
      : null,
    canEdit: canManage(base.myRole ?? undefined) && c.status === 'active',
    canEditName: base.myRole === 'president',
    shareLink: shareLink('club', c.id),
    shareText: `You've been invited to join the ${c.name} Club on Keys.`,
    inviteLink: shareLink('club-invite', c.id),
  };
}

const form = z.object({
  name: z.string().trim().min(1, 'Add a club name').max(NAME_MAX, `Club names can be up to ${NAME_MAX} characters`),
  description: z.string().trim().max(DESCRIPTION_MAX, `Descriptions can be up to ${DESCRIPTION_MAX} characters`).default(''),
  category: z.enum(CLUB_CATEGORIES, { message: 'Select club category' }),
  memberLimit: z.number().int().min(LIMIT_MIN, `Minimum of ${LIMIT_MIN}`).max(100000),
  coverMediaId: uuid,
});

async function nameTaken(communityId: string, name: string, except?: string) {
  return !!(await one(`select 1 from clubs where community_id = $1 and lower(name) = lower($2) and status <> 'closed' and id <> coalesce($3::uuid, '00000000-0000-0000-0000-000000000000')`, [communityId, name, except ?? null]));
}

async function ownCover(id: string, userId: string, except?: string | null) {
  if (id === except) return;
  if (!(await one(`select 1 from media where id = $1 and owner_id = $2 and kind = 'photo'`, [id, userId]))) throw badRequest('MEDIA_INVALID', 'Set a cover image.');
}

async function invite(c: Club, by: string, ids: string[]) {
  const from = await person(by);
  let n = 0;
  for (const id of [...new Set(ids)]) {
    if (id === by || (await communityOf(id)) !== c.community_id || (await roleIn(c.id, id))) continue;
    await q('insert into club_invites(club_id, user_id, invited_by) values ($1,$2,$3) on conflict do nothing', [c.id, id, by]);
    await notifyAndEmail(id, 'club_invite', by, { type: 'club', id: c.id }, { club: c.name }, {
      subject: `You've been invited to join ${c.name}`, text: `${from?.name ?? 'A neighbour'} invited you to join the ${c.name} Club on Keys.`,
    });
    n++;
  }
  return n;
}

/** CLB-16.2: membership milestones, once each. */
async function milestones(c: Club) {
  const n = await memberCount(c.id);
  const hit = MILESTONES.filter((m) => n >= m && !c.milestones.includes(m));
  if (!hit.length) return;
  await q('update clubs set milestones = milestones || $2::int[] where id = $1', [c.id, hit]);
  const top = Math.max(...hit);
  for (const u of await clubMemberIds(c.id)) {
    await notifyAndEmail(u, 'club_milestone', null, { type: 'club', id: c.id }, { club: c.name, count: top }, {
      subject: `${c.name} is ${top} members strong!`, text: `${c.name} has reached ${top} members. Thanks for being part of it.`,
    });
  }
}

async function load(id: string, viewer: string) {
  return clubOr404(id, await communityOf(viewer));
}

async function requireRole(c: Club, userId: string, roles: string[]) {
  const r = await roleIn(c.id, userId);
  if (!r || !roles.includes(r)) throw forbidden('NOT_ALLOWED', roles.length === 1 ? 'Only the club President can do this.' : 'Only the President and admins can do this.');
  return r;
}

export async function clubRoutes(app: FastifyInstance) {
  // CLB-01.1: Home with My clubs and announcements from them.
  app.get('/clubs/home', async (req) => {
    const u = requireUser(req);
    const mine = await q<Club>(
      `select c.* from clubs c join club_members m on m.club_id = c.id where m.user_id = $1 and c.status <> 'closed' order by m.joined_at desc`, [u.id],
    );
    const posts = await q<any>(
      `select p.* from posts p join club_members m on m.club_id = p.club_id and m.user_id = $1 join clubs c on c.id = p.club_id
        where p.status = 'live' and c.status <> 'closed' order by p.created_at desc limit 30`,
      [u.id],
    );
    return {
      myClubs: await Promise.all(mine.map((c) => card(c, u.id))),
      announcements: await Promise.all(posts.map((p) => postView(p, u.id))),
      templates: CLUB_TEMPLATES.map((t) => ({ id: t.id, label: t.label, name: t.name, category: t.category, image: t.image })),
    };
  });

  // CLB-01.3 / CLB-02: Discover with categories and search.
  app.get('/clubs/discover', async (req) => {
    const u = requireUser(req);
    const { category, q: text } = z.object({ category: z.string().optional(), q: z.string().trim().default('') }).parse(req.query);
    const rows = await q<Club>(
      `select * from clubs where community_id = $1 and status <> 'closed' and ($2::text is null or category = $2) and ($3 = '' or name ilike '%' || $3 || '%') order by created_at desc`,
      [await communityOf(u.id), category && category !== 'All' ? category : null, text],
    );
    return { categories: ['All', ...CLUB_CATEGORIES], clubs: await Promise.all(rows.map((c) => card(c, u.id))) };
  });

  app.get('/clubs/templates', async (req) => {
    requireUser(req);
    return { templates: CLUB_TEMPLATES, categories: CLUB_CATEGORIES };
  });

  // CLB-03: create (verified residents only).
  app.post('/clubs', async (req) => {
    const u = await requireVerified(req);
    const b = form.extend({ inviteIds: z.array(uuid).default([]) }).parse(req.body);
    const community = (await communityOf(u.id))!;
    if (await nameTaken(community, b.name)) throw conflict('NAME_TAKEN', 'A club with this name already exists in your community.', { field: 'name' });
    await ownCover(b.coverMediaId, u.id);
    const c = await tx(async (db) => {
      const chat = (await one<{ id: string }>(
        `insert into chats(community_id, type, name, created_by, members_can_invite) values ($1,'club',$2,$3,false) returning id`, [community, b.name, u.id], db,
      ))!;
      const row = (await one<Club>(
        `insert into clubs(community_id, name, description, category, member_limit, cover_media_id, president_id, chat_id, created_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9) returning *`,
        [community, b.name, b.description, b.category, b.memberLimit, b.coverMediaId, u.id, chat.id, clock.now()], db,
      ))!;
      await q('update chats set icon_url = (select url from media where id = $2) where id = $1', [chat.id, b.coverMediaId], db);
      await q(`insert into club_members(club_id, user_id, role) values ($1,$2,'president')`, [row.id, u.id], db);
      await addChatMember(chat.id, u.id, 'admin', db);
      return row;
    });
    await system(c.chat_id!, 'created', u.id, null, `${(await person(u.id))!.name} created this group`);
    const invited = await invite(c, u.id, b.inviteIds);
    return {
      club: await detail(c, u.id),
      invited,
      title: 'Club created!',
      message: `You've successfully created ${c.name}.`,
      // CLB-03.5 "Welcome!" owner actions (free club: no virtual card line).
      welcome: ['Post announcements for members or the whole community', 'Create club events', 'Invite residents and manage members', 'Chat with members in the club group chat'],
    };
  });

  app.get('/clubs/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    return { club: await detail(c, u.id) };
  });

  // CLB-09: President edits everything; admins everything but the name.
  app.patch('/clubs/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    const role = await requireRole(c, u.id, ['president', 'admin']);
    if (c.status !== 'active') throw conflict('CLOSING', 'This club is closing and can no longer be edited.');
    const b = form.partial().parse(req.body);
    if (b.name !== undefined && b.name !== c.name) {
      if (role !== 'president') throw forbidden('NAME_PRESIDENT_ONLY', 'Only the President can change the club name.');
      if (await nameTaken(c.community_id, b.name, c.id)) throw conflict('NAME_TAKEN', 'A club with this name already exists in your community.', { field: 'name' });
    }
    if (b.memberLimit !== undefined && b.memberLimit < (await memberCount(c.id))) {
      throw badRequest('LIMIT_TOO_LOW', 'The members limit cannot be lower than the number of members.', { field: 'memberLimit' });
    }
    if (b.coverMediaId) await ownCover(b.coverMediaId, u.id, c.cover_media_id);
    await q(
      `update clubs set name = coalesce($2, name), description = coalesce($3, description), category = coalesce($4, category),
         member_limit = coalesce($5, member_limit), cover_media_id = coalesce($6, cover_media_id), full_notified_at = case when $5::int > member_limit then null else full_notified_at end where id = $1`,
      [id, b.name ?? null, b.description ?? null, b.category ?? null, b.memberLimit ?? null, b.coverMediaId ?? null],
    );
    if (c.chat_id && b.name && b.name !== c.name) await q('update chats set name = $2 where id = $1', [c.chat_id, b.name]);
    if (c.chat_id && b.coverMediaId) await q('update chats set icon_url = (select url from media where id = $2) where id = $1', [c.chat_id, b.coverMediaId]);
    return { club: await detail((await one<Club>('select * from clubs where id = $1', [id]))!, u.id), message: 'Changes saved!' };
  });

  // CLB-06: join while there is space.
  app.post('/clubs/:id/join', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    if (c.status !== 'active') throw conflict('CLOSING', 'This club is closing and is not accepting new members.');
    if (await roleIn(c.id, u.id)) return { club: await detail(c, u.id), message: `You've joined the ${c.name}` };
    const joined = await tx(async (db) => {
      await q('select id from clubs where id = $1 for update', [id], db);
      if ((await memberCount(id, db)) >= c.member_limit) return false;
      await addToClub(c, u.id, 'member', db);
      return true;
    });
    if (!joined) {
      // CLB-06.3: 10 different people within 7 days tell the President.
      const now = clock.now();
      await q(`insert into club_join_attempts(club_id, user_id, attempted_at) values ($1,$2,$3) on conflict (club_id, user_id) do update set attempted_at = excluded.attempted_at`, [id, u.id, now]);
      const n = (await one<{ n: number }>(`select count(*)::int as n from club_join_attempts where club_id = $1 and attempted_at > $2`, [id, new Date(now.getTime() - 7 * DAY)]))!.n;
      if (n >= ATTEMPTS && c.president_id && (!c.attempts_notified_at || c.attempts_notified_at < new Date(now.getTime() - 7 * DAY))) {
        await q('update clubs set attempts_notified_at = $2 where id = $1', [id, now]);
        await notify(c.president_id, 'club_join_attempts', null, { type: 'club', id }, {
          club: c.name, text: `Several people have tried to join ${c.name}, but the member limit has been reached. Increase the limit to let them in.`,
        });
      }
      throw conflict('CLUB_FULL', `${c.name} has reached its member limit and isn't accepting new members right now. Please check back later.`, { title: 'This club is currently full' });
    }
    await notifyAndEmail(u.id, 'club_welcome', null, { type: 'club', id }, { club: c.name }, {
      subject: `Welcome to ${c.name}`, text: `You've joined ${c.name} on Keys. Say hello in the club group chat.`,
    });
    // CLB-06.4: the club just filled up.
    if ((await memberCount(id)) >= c.member_limit && c.president_id && !c.full_notified_at) {
      await q('update clubs set full_notified_at = $2 where id = $1', [id, clock.now()]);
      await notify(c.president_id, 'club_full', null, { type: 'club', id }, { club: c.name, text: `${c.name} has reached it's member limit. Increase the limit to welcome more members.` });
    }
    await milestones((await one<Club>('select * from clubs where id = $1', [id]))!);
    return { club: await detail(c, u.id), message: `You've joined the ${c.name}`, chatId: c.chat_id };
  });

  // CLB-08.3: members leave; the President transfers first.
  app.post('/clubs/:id/leave', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    const role = await roleIn(id, u.id);
    if (!role) throw badRequest('NOT_MEMBER', 'You are not a member of this club.');
    if (role === 'president') throw forbidden('PRESIDENT', 'Transfer ownership of the club before leaving it.');
    await removeFromClub(c, u.id);
    if (role === 'admin' && c.president_id) await passEvents(u.id, c.president_id, { category: 'club', clubId: id });
    if (c.chat_id) await system(c.chat_id, 'exited', u.id, null, `${(await person(u.id))!.name} left`);
    return { message: `You exited ${c.name}` };
  });

  // CLB-08.2
  app.put('/clubs/:id/mute', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { duration } = z.object({ duration: z.enum(['1h', '24h', '1w', 'forever']).nullable() }).parse(req.body);
    const c = await load(id, u.id);
    if (!(await roleIn(id, u.id))) throw badRequest('NOT_MEMBER', 'You are not a member of this club.');
    await q('update club_members set muted_until = $3 where club_id = $1 and user_id = $2', [id, u.id, duration ? muteUntil(duration) : null]);
    if (c.chat_id) await q('update chat_members set muted_until = $3 where chat_id = $1 and user_id = $2', [c.chat_id, u.id, duration ? muteUntil(duration) : null]);
    return { muted: !!duration, message: duration ? `You muted ${c.name}` : `You unmuted ${c.name}` };
  });

  // CLB-05.2 / CLB-10.1: members with roles, searchable.
  app.get('/clubs/:id/members', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { q: text } = z.object({ q: z.string().trim().default('') }).parse(req.query);
    const c = await load(id, u.id);
    const rows = await q<{ user_id: string; role: string }>(
      `select m.user_id, m.role from club_members m join users u on u.id = m.user_id where m.club_id = $1
         and ($2 = '' or (u.first_name || ' ' || u.last_name) ilike '%' || $2 || '%')
       order by case m.role when 'president' then 0 when 'admin' then 1 else 2 end, u.first_name`,
      [id, text],
    );
    const ps = await people(rows.map((r) => r.user_id));
    return {
      members: rows.map((r) => ({ person: ps.get(r.user_id), role: r.role, roleLabel: r.role === 'president' ? 'Club president' : r.role === 'admin' ? 'Admin' : 'Member' })),
      countLabel: `${await memberCount(id)}/${c.member_limit} members`,
      myRole: await roleIn(id, u.id) ?? null,
    };
  });

  app.post('/clubs/:id/invite', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { userIds } = z.object({ userIds: z.array(uuid).min(1) }).parse(req.body);
    const c = await load(id, u.id);
    if (!(await roleIn(id, u.id))) throw forbidden('NOT_MEMBER', 'Only members can invite others.');
    const n = await invite(c, u.id, userIds);
    return { invited: n, message: n === 1 ? 'Invitation sent' : `${n} invitations sent` };
  });

  // CLB-10.2 - CLB-10.4: President makes or dismisses admins.
  app.post('/clubs/:id/admins/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const c = await load(id, u.id);
    await requireRole(c, u.id, ['president']);
    if ((await roleIn(id, userId)) !== 'member') throw badRequest('NOT_MEMBER', 'Choose a member of this club.');
    await q(`update club_members set role = 'admin' where club_id = $1 and user_id = $2`, [id, userId]);
    if (c.chat_id) await addChatMember(c.chat_id, userId, 'admin');
    const p = (await person(userId))!;
    await notifyAndEmail(userId, 'club_role', u.id, { type: 'club', id }, { club: c.name, role: 'admin' }, {
      subject: `You're now an admin of ${c.name}`, text: `You can now remove members, create club events and post club activities in ${c.name}.`,
    });
    return { message: `${p.name} is now an admin` };
  });
  app.delete('/clubs/:id/admins/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const c = await load(id, u.id);
    await requireRole(c, u.id, ['president']);
    if ((await roleIn(id, userId)) !== 'admin') throw badRequest('NOT_ADMIN', 'This member is not an admin.');
    await q(`update club_members set role = 'member' where club_id = $1 and user_id = $2`, [id, userId]);
    if (c.chat_id) await addChatMember(c.chat_id, userId, 'member');
    // EVT-27.3: their club events pass to the President.
    await passEvents(userId, u.id, { category: 'club', clubId: id });
    return { message: `${(await person(userId))!.name} is no longer an admin` };
  });

  // CLB-10.5 / CLB-10.6: President or admins remove members (admins cannot remove admins).
  app.delete('/clubs/:id/members/:userId', async (req) => {
    const u = requireUser(req);
    const { id, userId } = z.object({ id: uuid, userId: uuid }).parse(req.params);
    const c = await load(id, u.id);
    const mine = await requireRole(c, u.id, ['president', 'admin']);
    const theirs = await roleIn(id, userId);
    if (!theirs) throw notFound('This person is not a member of this club.');
    if (theirs === 'president' || (mine === 'admin' && theirs === 'admin')) throw forbidden('NOT_ALLOWED', 'You cannot remove this member.');
    await removeFromClub(c, userId);
    if (theirs === 'admin' && c.president_id) await passEvents(userId, c.president_id, { category: 'club', clubId: id });
    const p = (await person(userId))!;
    if (c.chat_id) await system(c.chat_id, 'removed', u.id, userId, `${(await person(u.id))!.name} removed ${p.name}`);
    await notifyAndEmail(userId, 'club_removed', u.id, { type: 'club', id }, { club: c.name }, {
      subject: `You've been removed from ${c.name}`, text: `You've been removed from ${c.name} by the club's President or an admin.`,
    });
    return { message: `You removed ${p.name}` };
  });

  // CLB-11: transfer ownership.
  app.post('/clubs/:id/transfer', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { userId } = z.object({ userId: uuid }).parse(req.body);
    const c = await load(id, u.id);
    await requireRole(c, u.id, ['president']);
    if (userId === u.id || !(await roleIn(id, userId))) throw badRequest('NOT_MEMBER', 'Choose a member of this club.');
    if (await one(`select 1 from club_transfers where club_id = $1 and status = 'pending'`, [id])) throw conflict('TRANSFER_PENDING', 'An ownership offer is already awaiting a response.');
    const t = (await one<{ id: string }>(`insert into club_transfers(club_id, from_id, to_id, created_at) values ($1,$2,$3,$4) returning id`, [id, u.id, userId, clock.now()]))!;
    await notifyAndEmail(userId, 'club_transfer_offer', u.id, { type: 'club', id }, { club: c.name, transferId: t.id }, {
      subject: 'Club Ownership Transfer', text: `${(await person(u.id))!.name} would like to transfer ownership of ${c.name} to you. Open Keys to accept or decline.`,
    });
    return { message: 'Ownership offer sent', transferId: t.id };
  });
  app.delete('/clubs/:id/transfer', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    await requireRole(c, u.id, ['president']);
    await q(`update club_transfers set status = 'cancelled', decided_at = $2 where club_id = $1 and status = 'pending'`, [id, clock.now()]);
    return { message: 'Ownership offer withdrawn' };
  });
  for (const action of ['accept', 'decline'] as const) {
    app.post(`/club-transfers/:id/${action}`, async (req) => {
      const u = requireUser(req);
      const { id } = z.object({ id: uuid }).parse(req.params);
      const t = await one<any>(`select * from club_transfers where id = $1 and to_id = $2 and status = 'pending'`, [id, u.id]);
      if (!t) throw notFound('This offer is no longer available.');
      const c = await load(t.club_id, u.id);
      if (action === 'decline') {
        await q(`update club_transfers set status = 'declined', decided_at = $2 where id = $1`, [id, clock.now()]);
        await notify(t.from_id, 'club_transfer_declined', u.id, { type: 'club', id: c.id }, { club: c.name });
        return { message: 'You will remain a member of the club.' };
      }
      await tx(async (db) => {
        await q(`update club_transfers set status = 'accepted', decided_at = $2 where id = $1`, [id, clock.now()], db);
        await q(`update club_members set role = 'president' where club_id = $1 and user_id = $2`, [c.id, u.id], db);
        await q('update clubs set president_id = $2 where id = $1', [c.id, u.id], db);
        if (c.chat_id) await addChatMember(c.chat_id, u.id, 'admin', db);
      });
      // Design: the old President leaves the club after the transfer; their club events pass on.
      await passEvents(t.from_id, u.id, { category: 'club', clubId: c.id });
      await removeFromClub({ ...c, president_id: u.id }, t.from_id);
      const p = (await person(u.id))!;
      // CLB-11.3: community-wide "New President" announcement.
      await q(
        `insert into posts(community_id, author_id, text, attachment, club_id, club_audience, created_at) values ($1,$2,$3,'none',$4,'all',$5)`,
        [c.community_id, u.id, `New President: ${p.name} is the new President of ${c.name}.`, c.id, clock.now()],
      );
      for (const m of await clubMemberIds(c.id)) if (m !== u.id) await notify(m, 'club_new_president', u.id, { type: 'club', id: c.id }, { club: c.name });
      return { message: 'Club ownership transferred.' };
    });
  }

  // CLB-12: close in 48 hours.
  app.post('/clubs/:id/delete', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await load(id, u.id);
    await requireRole(c, u.id, ['president']);
    if (c.status !== 'active') throw conflict('CLOSING', 'This club is already closing.');
    const at = new Date(clock.now().getTime() + CLOSE_HOURS * HOUR);
    await q(`update clubs set status = 'closing', closing_at = $2 where id = $1`, [id, at]);
    for (const m of await clubMemberIds(id)) {
      if (m === u.id) continue;
      await notifyAndEmail(m, 'club_closing', u.id, { type: 'club', id }, { club: c.name }, {
        subject: `${c.name} is closing`, text: `${c.name} will be closed permanently in 48 hours.`,
      });
    }
    return { title: 'Club deleted', message: `Your club ${c.name} would be closed permanently in 48hours.`, closingAt: at };
  });

  // CLB-14.3: club events by status.
  app.get('/clubs/:id/events', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const { status } = z.object({ status: z.enum(['upcoming', 'completed', 'cancelled']).default('upcoming') }).parse(req.query);
    await load(id, u.id);
    const member = !!(await roleIn(id, u.id));
    const rows = await q<Event>(
      `select * from events where club_id = $1 and status <> 'draft' and ($2 or audience = 'all') order by start_at`, [id, member],
    );
    const pick = rows.filter((e) => (status === 'cancelled' ? e.status === 'cancelled' : status === 'completed' ? isCompleted(e) : e.status === 'live' && !isCompleted(e)));
    return { events: await Promise.all(pick.map((e) => eventCard(e, u.id))) };
  });

  // CLB-05.1 / CLB-13: announcements. Non-members see "All" ones only (CLB-05.3).
  app.get('/clubs/:id/announcements', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await load(id, u.id);
    const member = !!(await roleIn(id, u.id));
    const rows = await q<any>(`select * from posts where club_id = $1 and status = 'live' and ($2 or club_audience = 'all') order by created_at desc`, [id, member]);
    return { announcements: await Promise.all(rows.map((p) => postView(p, u.id))), membersOnlyHidden: !member };
  });
}

/** CLB-12.3: closing clubs close after 48 hours; their events are cancelled. */
export async function clubJobs() {
  const due = await q<Club>(`select * from clubs where status = 'closing' and closing_at <= $1`, [clock.now()]);
  for (const c of due) {
    await q(`update clubs set status = 'closed', closed_at = $2 where id = $1`, [c.id, clock.now()]);
    const events = await q<Event>(`select * from events where club_id = $1 and status = 'live' and end_at > $2`, [c.id, clock.now()]);
    for (const e of events) await cancelEvent(e, 'Club closed', null, null);
    await q(`update events set status = 'cancelled', cancelled_at = $2 where club_id = $1 and status = 'draft'`, [c.id, clock.now()]);
    if (c.chat_id) await q('update chats set read_only = true where id = $1', [c.chat_id]);
    for (const m of await clubMemberIds(c.id)) {
      await notifyAndEmail(m, 'club_closed', null, { type: 'club', id: c.id }, { club: c.name }, {
        subject: `${c.name} has been closed`, text: `${c.name} has been closed by its President. Its events have been cancelled.`,
      });
    }
  }
}
