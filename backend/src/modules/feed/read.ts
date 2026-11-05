import { one, q } from '../../db/pool.js';
import { clock } from '../../lib/clock.js';
import { AppError, notFound } from '../../lib/errors.js';
import { communityOf, hiddenAuthorSql, mutedAuthorSql, people } from '../../lib/people.js';
import { shareLink } from '../links/routes.js';

export const PAGE = 20;
export const DELETED_MSG = 'This post has been deleted by the author.';
export const REMOVED_MSG = 'This post has been removed for violating Keys Guidelines';

const enc = (r: { created_at: Date; id: string }) => Buffer.from(`${r.created_at.toISOString()}|${r.id}`).toString('base64url');
const dec = (c?: string) => {
  if (!c) return undefined;
  const [t, id] = Buffer.from(c, 'base64url').toString().split('|');
  return { t: new Date(t), id };
};

/** Poll block for a post (POL-06 - POL-09). Counts show once you voted, the poll closed, or you made it. */
export async function pollView(postId: string, viewer: string, authorId: string) {
  const p = await one<any>('select * from polls where post_id = $1', [postId]);
  if (!p) return undefined;
  const opts = await q<any>(
    `select o.id, o.text, m.url as image from poll_options o left join media m on m.id = o.media_id where o.post_id = $1 order by o.position`, [postId],
  );
  const votes = await q<{ option_ids: string[]; user_id: string }>('select option_ids, user_id from poll_votes where post_id = $1', [postId]);
  const mine = votes.find((v) => v.user_id === viewer)?.option_ids ?? null;
  const closed = p.closes_at <= clock.now();
  const voters = votes.length;
  const counts = new Map<string, number>();
  for (const v of votes) for (const o of v.option_ids) counts.set(o, (counts.get(o) ?? 0) + 1);
  const show = !!mine || closed || viewer === authorId;
  const max = Math.max(0, ...opts.map((o) => counts.get(o.id) ?? 0));
  return {
    question: p.question,
    promise: p.promise,
    multi: p.multi,
    duration: p.duration,
    closesAt: p.closes_at,
    closed,
    totalVotes: voters,
    myVote: mine,
    canVote: !closed && !mine,
    resultsVisible: show,
    options: opts.map((o) => {
      const n = counts.get(o.id) ?? 0;
      return {
        id: o.id,
        text: o.text,
        imageUrl: o.image,
        votes: show ? n : null,
        percent: show ? (voters ? Math.round((n / voters) * 100) : 0) : null,
        winner: closed && voters > 0 && n === max,
      };
    }),
  };
}

export async function postView(r: any, viewer: string) {
  const [authors, photos, mentions, likes, comments, liked] = await Promise.all([
    people([r.author_id]),
    q<any>(`select m.id, m.url, m.kind, m.duration_seconds from post_media pm join media m on m.id = pm.media_id where pm.post_id = $1 order by pm.position`, [r.id]),
    q<any>(`select u.id, u.first_name, u.last_name from mentions x join users u on u.id = x.user_id where x.post_id = $1`, [r.id]),
    one<{ n: number }>(`select count(*)::int as n from likes where item_type = 'post' and item_id = $1`, [r.id]),
    one<{ n: number }>(`select count(*)::int as n from comments where post_id = $1 and deleted_at is null and not ${hiddenAuthorSql('author_id', '$2')}`, [r.id, viewer]),
    one(`select 1 from likes where item_type = 'post' and item_id = $1 and user_id = $2`, [r.id, viewer]),
  ]);
  let document;
  if (r.attachment === 'document' && r.document_media_id) {
    const d = await one<any>('select mime, size_bytes, original_name from media where id = $1', [r.document_media_id]);
    document = { title: r.document_title, pages: r.document_pages, sizeBytes: d?.size_bytes, fileType: (d?.original_name?.split('.').pop() ?? 'pdf').toUpperCase(), downloads: r.document_downloads };
  }
  return {
    id: r.id,
    kind: r.kind,
    author: authors.get(r.author_id),
    text: r.text,
    mentions: mentions.map((m) => ({ id: m.id, name: `${m.first_name} ${m.last_name}` })),
    attachment: r.attachment,
    photos: r.attachment === 'photos' ? photos.map((p) => ({ id: p.id, url: p.url })) : [],
    video: r.attachment === 'video' && photos[0] ? { url: photos[0].url, durationSeconds: photos[0].duration_seconds } : null,
    document: document ?? null,
    link: r.attachment === 'link' ? { url: r.link_url, title: r.link_title, description: r.link_description, image: r.link_image } : null,
    poll: r.kind === 'poll' ? await pollView(r.id, viewer, r.author_id) : null,
    likeCount: likes?.n ?? 0,
    commentCount: comments?.n ?? 0,
    likedByMe: !!liked,
    isMine: r.author_id === viewer,
    createdAt: r.created_at,
    editedAt: r.edited_at,
    shareLink: shareLink(r.kind === 'poll' ? 'poll' : 'post', r.id),
    club: r.club_id ? { id: r.club_id, name: (await one<{ name: string }>('select name from clubs where id = $1', [r.club_id]))?.name ?? '', audience: r.club_audience } : null,
    // CLB-13.3: club announcements take likes only.
    canComment: !r.club_id,
    // CLB-13.4: the club President may delete any announcement.
    canDelete: r.author_id === viewer || (!!r.club_id && !!(await one(`select 1 from club_members where club_id = $1 and user_id = $2 and role = 'president'`, [r.club_id, viewer]))),
  };
}

/** FED-01.2 / FED-01.5: community feed, newest first, muted and blocked authors hidden. */
export async function postsFor(viewer: string, opts: { authorId?: string; cursor?: string }) {
  const c = await communityOf(viewer);
  if (!c) return { posts: [], nextCursor: null };
  const cur = dec(opts.cursor);
  const params: unknown[] = [c, viewer, cur?.t ?? null, cur?.id ?? null, PAGE + 1];
  let where = `p.community_id = $1 and p.status = 'live' and p.club_id is null and not ${hiddenAuthorSql('p.author_id', '$2')}
    and ($3::timestamptz is null or (p.created_at, p.id) < ($3::timestamptz, $4::uuid))`;
  if (opts.authorId) {
    params.push(opts.authorId);
    where += ` and p.author_id = $${params.length}`;
  } else {
    params.push(clock.now());
    where += ` and not ${mutedAuthorSql('p.author_id', '$2', `$${params.length}`)}`;
  }
  const rows = await q<any>(`select p.* from posts p where ${where} order by p.created_at desc, p.id desc limit $5`, params);
  const page = rows.slice(0, PAGE);
  return {
    posts: await Promise.all(page.map((r) => postView(r, viewer))),
    nextCursor: rows.length > PAGE ? enc(page[page.length - 1]) : null,
  };
}

/** One post the viewer may see; deleted and removed posts get their unavailable states (FED-10). */
export async function loadPost(id: string, viewer: string, { allowGone = false } = {}) {
  const r = await one<any>('select * from posts where id = $1', [id]);
  const c = await communityOf(viewer);
  if (!r || r.community_id !== c) throw notFound('This post is not available.');
  if (!allowGone) {
    if (r.status === 'deleted') throw new AppError(410, 'POST_DELETED', DELETED_MSG, { title: 'Post unavailable' });
    if (r.status === 'removed') throw new AppError(410, 'POST_REMOVED', REMOVED_MSG, { title: 'Post unavailable' });
  }
  if (await one(`select 1 where ${hiddenAuthorSql('$1::uuid', '$2::uuid')}`, [r.author_id, viewer])) throw notFound('This post is not available.');
  // CLB-13.1: members-only announcements.
  if (r.club_id && r.club_audience === 'members' && !(await one('select 1 from club_members where club_id = $1 and user_id = $2', [r.club_id, viewer]))) {
    throw notFound('This post is not available.');
  }
  return r;
}
