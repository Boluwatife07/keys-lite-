import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx, type Db } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { clock } from '../../lib/clock.js';
import { badRequest, forbidden, notFound } from '../../lib/errors.js';
import { linkPreview } from '../../lib/linkPreview.js';
import { notify } from '../../lib/notify.js';
import { hiddenAuthorSql, people, requireCommunity } from '../../lib/people.js';
import { getObject } from '../../services/storage.js';
import { loadPost, postView, postsFor } from './read.js';

export const POST_MAX = 200;
export const COMMENT_MAX = 1000;
const MAX_PHOTOS = 10;

const uuid = z.string().uuid();

/** Mentioned residents must be in the community and not blocked either way (FED-03.4). */
export async function validMentions(ids: string[] | undefined, author: string, community: string, db?: Db) {
  const uniq = [...new Set(ids ?? [])].filter((i) => i !== author);
  if (!uniq.length) return [];
  const rows = await q<{ user_id: string }>(
    `select m.user_id from memberships m where m.community_id = $1 and m.user_id = any($2) and not ${hiddenAuthorSql('m.user_id', '$3')}`,
    [community, uniq, author], db,
  );
  return rows.map((r) => r.user_id);
}

async function ownMedia(ids: string[], owner: string, kind: string) {
  const rows = await q<{ id: string }>(`select id from media where id = any($1) and owner_id = $2 and kind = $3`, [ids, owner, kind]);
  if (rows.length !== new Set(ids).size) throw badRequest('MEDIA_INVALID', 'One of the files could not be found. Please add it again.');
}

function pdfPages(buf: Buffer) {
  const n = buf.toString('latin1').match(/\/Type\s*\/Page(?![s\w])/g)?.length;
  return n || null;
}

async function commentView(c: any, viewer: string) {
  const [authors, likes, liked, replies, mentions, image] = await Promise.all([
    people([c.author_id]),
    one<{ n: number }>(`select count(*)::int as n from likes where item_type = 'comment' and item_id = $1`, [c.id]),
    one(`select 1 from likes where item_type = 'comment' and item_id = $1 and user_id = $2`, [c.id, viewer]),
    c.parent_id ? Promise.resolve({ n: 0 }) : one<{ n: number }>(
      `select count(*)::int as n from comments where parent_id = $1 and deleted_at is null and not ${hiddenAuthorSql('author_id', '$2')}`, [c.id, viewer],
    ),
    q<any>(`select u.id, u.first_name, u.last_name from mentions x join users u on u.id = x.user_id where x.comment_id = $1`, [c.id]),
    c.media_id ? one<{ url: string }>('select url from media where id = $1', [c.media_id]) : Promise.resolve(undefined),
  ]);
  if (c.deleted_at) {
    // FED-14.3: placeholder kept only where replies exist.
    return { id: c.id, parentId: c.parent_id, deleted: true, text: 'Comment is no longer available.', replyCount: replies?.n ?? 0, createdAt: c.created_at };
  }
  return {
    id: c.id,
    parentId: c.parent_id,
    deleted: false,
    author: authors.get(c.author_id),
    text: c.text,
    imageUrl: image?.url ?? null,
    mentions: mentions.map((m) => ({ id: m.id, name: `${m.first_name} ${m.last_name}` })),
    likeCount: likes?.n ?? 0,
    likedByMe: !!liked,
    replyCount: replies?.n ?? 0,
    isMine: c.author_id === viewer,
    createdAt: c.created_at,
    editedAt: c.edited_at,
  };
}

async function loadComment(id: string, viewer: string) {
  const c = await one<any>('select * from comments where id = $1', [id]);
  if (!c) throw notFound('This comment is not available.');
  await loadPost(c.post_id, viewer);
  return c;
}

export async function feedRoutes(app: FastifyInstance) {
  app.get('/feed', async (req) => {
    const u = requireUser(req);
    const { cursor } = z.object({ cursor: z.string().optional() }).parse(req.query);
    return postsFor(u.id, { cursor });
  });

  app.post('/link-preview', async (req) => {
    requireUser(req);
    const { url } = z.object({ url: z.string().url('Enter a valid link') }).parse(req.body);
    try {
      return await linkPreview(url);
    } catch {
      return { url, title: new URL(url).hostname };
    }
  });

  // FED-02 - FED-05: create a post with at most one attachment type.
  app.post('/posts', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      text: z.string().max(POST_MAX, `Posts can be up to ${POST_MAX} characters`).default(''),
      photoIds: z.array(uuid).max(MAX_PHOTOS, `You can add up to ${MAX_PHOTOS} photos`).optional(),
      videoId: uuid.optional(),
      document: z.object({ mediaId: uuid, title: z.string().trim().min(1, 'Add a document title').max(100) }).optional(),
      linkUrl: z.string().url('Enter a valid link').optional(),
      mentionIds: z.array(uuid).optional(),
    }).parse(req.body);
    const community = await requireCommunity(u.id);
    const types = [b.photoIds?.length ? 'photos' : null, b.videoId ? 'video' : null, b.document ? 'document' : null, b.linkUrl ? 'link' : null].filter(Boolean);
    if (types.length > 1) throw badRequest('ONE_ATTACHMENT_TYPE', 'A post can have photos, one video, one document or one link, not a mix.');
    const text = b.text.trim();
    if (!text && !types.length) throw badRequest('EMPTY_POST', "Write something or add an attachment.");
    if (b.photoIds?.length) await ownMedia(b.photoIds, u.id, 'photo');
    if (b.videoId) await ownMedia([b.videoId], u.id, 'video');
    let pages: number | null = null;
    if (b.document) {
      await ownMedia([b.document.mediaId], u.id, 'document');
      const m = (await one<{ storage_key: string; mime: string }>('select storage_key, mime from media where id = $1', [b.document.mediaId]))!;
      if (m.mime === 'application/pdf') pages = pdfPages(await getObject(m.storage_key));
    }
    let link: { title?: string; description?: string; image?: string } = {};
    if (b.linkUrl) {
      try { link = await linkPreview(b.linkUrl); } catch { link = { title: new URL(b.linkUrl).hostname }; }
    }
    const mentions = await validMentions(b.mentionIds, u.id, community);
    const post = await tx(async (c) => {
      const p = (await one<any>(
        `insert into posts(community_id, author_id, text, attachment, document_media_id, document_title, document_pages, link_url, link_title, link_description, link_image, created_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) returning *`,
        [community, u.id, text, types[0] ?? 'none', b.document?.mediaId ?? null, b.document?.title ?? null, pages,
          b.linkUrl ?? null, link.title ?? null, link.description ?? null, link.image ?? null, clock.now()], c,
      ))!;
      const media = b.photoIds ?? (b.videoId ? [b.videoId] : []);
      for (const [i, m] of media.entries()) await q('insert into post_media(post_id, media_id, position) values ($1,$2,$3)', [p.id, m, i], c);
      for (const m of mentions) await q('insert into mentions(post_id, user_id) values ($1,$2)', [p.id, m], c);
      return p;
    });
    // FED-05.3: no notification to the community; only tagged residents.
    for (const m of mentions) await notify(m, 'mention', u.id, { type: 'post', id: post.id });
    return { post: await postView(post, u.id), message: 'Your post has been sent' };
  });

  // FED-08 / FED-10
  app.get('/posts/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    return { post: await postView(await loadPost(id, u.id), u.id) };
  });

  // FED-18.2: edit text (and tags). Polls cannot be edited (POL-05.3).
  app.patch('/posts/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({ text: z.string().max(POST_MAX, `Posts can be up to ${POST_MAX} characters`), mentionIds: z.array(uuid).optional() }).parse(req.body);
    const p = await loadPost(id, u.id);
    if (p.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the author can edit this post.');
    if (p.kind === 'poll') throw forbidden('POLL_LOCKED', 'Polls cannot be edited after publishing.');
    if (!b.text.trim() && p.attachment === 'none') throw badRequest('EMPTY_POST', 'Write something or add an attachment.');
    const mentions = await validMentions(b.mentionIds, u.id, p.community_id);
    const before = new Set((await q<{ user_id: string }>('select user_id from mentions where post_id = $1', [id])).map((r) => r.user_id));
    await tx(async (c) => {
      await q('update posts set text = $2, edited_at = $3 where id = $1', [id, b.text.trim(), clock.now()], c);
      await q('delete from mentions where post_id = $1', [id], c);
      for (const m of mentions) await q('insert into mentions(post_id, user_id) values ($1,$2)', [id, m], c);
    });
    for (const m of mentions) if (!before.has(m)) await notify(m, 'mention', u.id, { type: 'post', id });
    return { post: await postView(await loadPost(id, u.id), u.id), message: 'Changes saved to post.' };
  });

  // FED-18.3 / POL-11: author deletes; poll votes go with it.
  app.delete('/posts/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const p = await loadPost(id, u.id);
    if (p.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the author can delete this post.');
    await tx(async (c) => {
      await q(`update posts set status = 'deleted', deleted_at = $2 where id = $1`, [id, clock.now()], c);
      await q('delete from poll_votes where post_id = $1', [id], c);
    });
    return { ok: true, message: 'Your post has been deleted.' };
  });

  // FED-06.3: document download, counted.
  app.post('/posts/:id/document/download', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const p = await loadPost(id, u.id);
    if (p.attachment !== 'document') throw notFound('This post has no document.');
    const m = (await one<{ url: string; original_name: string }>('select url, original_name from media where id = $1', [p.document_media_id]))!;
    await q('update posts set document_downloads = document_downloads + 1 where id = $1', [id]);
    return { url: m.url, name: m.original_name };
  });

  // FED-11: likes on posts.
  app.post('/posts/:id/like', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const p = await loadPost(id, u.id);
    const r = await one(`insert into likes(item_type, item_id, user_id, created_at) values ('post',$1,$2,$3) on conflict do nothing returning 1`, [id, u.id, clock.now()]);
    if (r) await notify(p.author_id, 'post_like', u.id, { type: 'post', id });
    return { liked: true, likeCount: (await one<{ n: number }>(`select count(*)::int as n from likes where item_type = 'post' and item_id = $1`, [id]))!.n };
  });
  app.delete('/posts/:id/like', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadPost(id, u.id);
    await q(`delete from likes where item_type = 'post' and item_id = $1 and user_id = $2`, [id, u.id]);
    return { liked: false, likeCount: (await one<{ n: number }>(`select count(*)::int as n from likes where item_type = 'post' and item_id = $1`, [id]))!.n };
  });

  async function likers(type: 'post' | 'comment', id: string, viewer: string) {
    const rows = await q<{ user_id: string }>(
      `select user_id from likes where item_type = $1 and item_id = $2 and not ${hiddenAuthorSql('user_id', '$3')} order by created_at desc`, [type, id, viewer],
    );
    const ps = await people(rows.map((r) => r.user_id));
    return rows.map((r) => ps.get(r.user_id));
  }
  app.get('/posts/:id/likes', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadPost(id, u.id);
    return { people: await likers('post', id, u.id) };
  });

  // FED-12 / FED-13: comments (oldest first, newest at the bottom) and replies.
  app.get('/posts/:id/comments', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadPost(id, u.id);
    const rows = await q<any>(
      `select c.* from comments c where c.post_id = $1 and c.parent_id is null and not ${hiddenAuthorSql('c.author_id', '$2')}
         and (c.deleted_at is null or exists (select 1 from comments r where r.parent_id = c.id and r.deleted_at is null))
       order by c.created_at`, [id, u.id],
    );
    return { comments: await Promise.all(rows.map((c) => commentView(c, u.id))) };
  });
  app.get('/comments/:id/replies', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadComment(id, u.id);
    const rows = await q<any>(
      `select * from comments where parent_id = $1 and deleted_at is null and not ${hiddenAuthorSql('author_id', '$2')} order by created_at`, [id, u.id],
    );
    return { replies: await Promise.all(rows.map((c) => commentView(c, u.id))) };
  });

  app.post('/posts/:id/comments', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({
      text: z.string().max(COMMENT_MAX).default(''),
      mediaId: uuid.optional(),
      parentId: uuid.optional(),
      mentionIds: z.array(uuid).optional(),
    }).parse(req.body);
    const p = await loadPost(id, u.id);
    if (!b.text.trim() && !b.mediaId) throw badRequest('EMPTY_COMMENT', 'Write a comment or add an image.');
    if (b.mediaId) await ownMedia([b.mediaId], u.id, 'photo');
    let parent: any;
    if (b.parentId) {
      parent = await one<any>('select * from comments where id = $1 and post_id = $2', [b.parentId, id]);
      if (!parent || parent.deleted_at) throw notFound('This comment is no longer available.');
      if (parent.parent_id) parent = await one<any>('select * from comments where id = $1', [parent.parent_id]); // one level deep
      if (await one(`select 1 where ${hiddenAuthorSql('$1::uuid', '$2::uuid')}`, [parent.author_id, u.id])) throw notFound('This comment is no longer available.');
    }
    const mentions = await validMentions(b.mentionIds, u.id, p.community_id);
    const c = await tx(async (db) => {
      const row = (await one<any>(
        `insert into comments(post_id, parent_id, author_id, text, media_id, created_at) values ($1,$2,$3,$4,$5,$6) returning *`,
        [id, parent?.id ?? null, u.id, b.text.trim(), b.mediaId ?? null, clock.now()], db,
      ))!;
      for (const m of mentions) await q('insert into mentions(comment_id, user_id) values ($1,$2)', [row.id, m], db);
      return row;
    });
    if (parent) await notify(parent.author_id, 'comment_reply', u.id, { type: 'post', id }, { commentId: c.id });
    else await notify(p.author_id, 'post_comment', u.id, { type: 'post', id }, { commentId: c.id });
    for (const m of mentions) await notify(m, 'mention', u.id, { type: 'post', id }, { commentId: c.id });
    return { comment: await commentView(c, u.id) };
  });

  // FED-14: edit / delete own comment or reply.
  app.patch('/comments/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const b = z.object({ text: z.string().max(COMMENT_MAX), mentionIds: z.array(uuid).optional() }).parse(req.body);
    const c = await loadComment(id, u.id);
    if (c.author_id !== u.id || c.deleted_at) throw forbidden('NOT_AUTHOR', 'Only the author can edit this comment.');
    if (!b.text.trim() && !c.media_id) throw badRequest('EMPTY_COMMENT', 'Write a comment or add an image.');
    await q('update comments set text = $2, edited_at = $3 where id = $1', [id, b.text.trim(), clock.now()]);
    return { comment: await commentView(await one('select * from comments where id = $1', [id]), u.id) };
  });
  app.delete('/comments/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await loadComment(id, u.id);
    if (c.author_id !== u.id) throw forbidden('NOT_AUTHOR', 'Only the author can delete this comment.');
    await q('update comments set deleted_at = $2 where id = $1', [id, clock.now()]);
    return { ok: true, message: 'Comment deleted.' };
  });

  app.post('/comments/:id/like', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    const c = await loadComment(id, u.id);
    if (c.deleted_at) throw notFound('This comment is no longer available.');
    const r = await one(`insert into likes(item_type, item_id, user_id, created_at) values ('comment',$1,$2,$3) on conflict do nothing returning 1`, [id, u.id, clock.now()]);
    if (r) await notify(c.author_id, 'comment_like', u.id, { type: 'post', id: c.post_id }, { commentId: id });
    return { liked: true };
  });
  app.delete('/comments/:id/like', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadComment(id, u.id);
    await q(`delete from likes where item_type = 'comment' and item_id = $1 and user_id = $2`, [id, u.id]);
    return { liked: false };
  });
  app.get('/comments/:id/likes', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: uuid }).parse(req.params);
    await loadComment(id, u.id);
    return { people: await likers('comment', id, u.id) };
  });

  // In-app notifications list (copy and grouping come from the Notifications task).
  app.get('/notifications', async (req) => {
    const u = requireUser(req);
    const rows = await q<any>('select * from notifications where user_id = $1 order by created_at desc limit 50', [u.id]);
    const ps = await people(rows.map((r) => r.actor_id));
    return { notifications: rows.map((r) => ({ id: r.id, type: r.type, actor: ps.get(r.actor_id) ?? null, itemType: r.item_type, itemId: r.item_id, data: r.data, createdAt: r.created_at, read: !!r.read_at })) };
  });

}
