import { createServer } from 'node:http';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { q } from '../src/db/pool.js';
import { clock, DAY, HOUR } from '../src/lib/clock.js';
import { closeDuePolls } from '../src/modules/feed/polls.js';
import { call, joinStreet, me, PDF, pioneerStreet, PNG, seat, setup, teardown, upload, verify } from './helpers.js';

let amy: string; let ben: string; let cat: string; let far: string;
let amyId: string; let benId: string; let catId: string;
let site: ReturnType<typeof createServer>;

beforeAll(async () => {
  process.env.LINK_PREVIEW_ALLOW_PRIVATE = '1';
  site = createServer((_, res) => res.end('<html><head><meta property="og:title" content="Street party"><meta property="og:image" content="/p.png"></head></html>')).listen(4567);
  await setup();
  amy = (await pioneerStreet('amy@keys.test', '1 Maple Road')).token;
  ben = await joinStreet('ben@keys.test', '2 Maple Road', 'Ben', 'Ade');
  cat = await joinStreet('cat@keys.test', '3 Maple Road', 'Cat', 'Obi');
  far = (await pioneerStreet('far@keys.test', '1 Oak Avenue')).token;
  [amyId, benId, catId] = await Promise.all([amy, ben, cat].map(async (t) => (await me(t)).id));
});
afterAll(async () => { site.close(); await teardown(); });

const photo = async (t: string) => (await upload('/media?kind=photo', t, { name: 'a.png', mime: 'image/png', data: PNG })).body.id;

describe('FED-02 / FED-04 / FED-05 create', () => {
  it('text up to 200; empty refused; one attachment type only; up to 10 photos', async () => {
    expect((await call('POST', '/posts', { token: amy, body: { text: 'x'.repeat(201) } })).status).toBe(400);
    expect((await call('POST', '/posts', { token: amy, body: { text: '  ' } })).body.error.code).toBe('EMPTY_POST');
    const p1 = await photo(amy);
    const doc = (await upload('/media?kind=document', amy, { name: 'minutes.pdf', mime: 'application/pdf', data: PDF })).body.id;
    const mix = await call('POST', '/posts', { token: amy, body: { text: 'x', photoIds: [p1], document: { mediaId: doc, title: 'Minutes' } } });
    expect(mix.body.error.code).toBe('ONE_ATTACHMENT_TYPE');
    const eleven = await call('POST', '/posts', { token: amy, body: { photoIds: Array.from({ length: 11 }, () => p1) } });
    expect(eleven.body.error.message).toBe('You can add up to 10 photos');
    const notMine = await call('POST', '/posts', { token: ben, body: { photoIds: [p1] } });
    expect(notMine.body.error.code).toBe('MEDIA_INVALID');
    const ok = await call('POST', '/posts', { token: amy, body: { text: 'Hello Maple Road', photoIds: [p1, await photo(amy)] } });
    expect(ok.body.message).toBe('Your post has been sent');
    expect(ok.body.post).toMatchObject({ attachment: 'photos', author: { name: 'Amy Duncan', verified: false }, likeCount: 0, commentCount: 0, isMine: true });
    expect(ok.body.post.photos).toHaveLength(2);
  });
  it('FED-04.4 document needs a title (max 100) and shows pages, type, size and downloads', async () => {
    const doc = (await upload('/media?kind=document', amy, { name: 'minutes.pdf', mime: 'application/pdf', data: Buffer.from('%PDF-1.4\n/Type /Pages\n/Type /Page\n/Type /Page\n%%EOF') })).body.id;
    expect((await call('POST', '/posts', { token: amy, body: { document: { mediaId: doc, title: '' } } })).body.error.message).toBe('Add a document title');
    const r = await call('POST', '/posts', { token: amy, body: { document: { mediaId: doc, title: 'AGM minutes' } } });
    expect(r.body.post.document).toMatchObject({ title: 'AGM minutes', pages: 2, fileType: 'PDF', downloads: 0 });
    const d = await call('POST', `/posts/${r.body.post.id}/document/download`, { token: ben });
    expect(d.body.url).toMatch(/^\/media\/files\/document\//);
    expect((await call('GET', `/posts/${r.body.post.id}`, { token: ben })).body.post.document.downloads).toBe(1);
  });
  it('FED-04.5 link preview with title and image', async () => {
    const r = await call('POST', '/posts', { token: ben, body: { text: 'Look', linkUrl: 'http://127.0.0.1:4567/party' } });
    expect(r.body.post.link).toMatchObject({ title: 'Street party', image: 'http://127.0.0.1:4567/p.png' });
  });
  it('blocks private addresses for link previews in production mode', async () => {
    process.env.LINK_PREVIEW_ALLOW_PRIVATE = '0';
    const r = await call('POST', '/link-preview', { token: ben, body: { url: 'http://127.0.0.1:4567/party' } });
    expect(r.body).toEqual({ url: 'http://127.0.0.1:4567/party', title: '127.0.0.1' });
    process.env.LINK_PREVIEW_ALLOW_PRIVATE = '1';
  });
});

describe('FED-01 feed', () => {
  it('community only, newest first, paged by 20', async () => {
    for (let i = 0; i < 22; i++) await call('POST', '/posts', { token: cat, body: { text: `post ${i}` } });
    const p1 = (await call('GET', '/feed', { token: ben })).body;
    expect(p1.posts).toHaveLength(20);
    expect(p1.posts[0].text).toBe('post 21');
    const p2 = (await call('GET', `/feed?cursor=${p1.nextCursor}`, { token: ben })).body;
    expect(p2.posts[0].text).toBe('post 1');
    expect((await call('GET', '/feed', { token: far })).body.posts).toEqual([]);
  });
  it('FED-01.2 author shows committee role or Unverified', async () => {
    await seat(amy, 'Chair');
    await verify(amy);
    const p = (await call('POST', '/posts', { token: amy, body: { text: 'From the chair' } })).body.post;
    expect(p.author).toMatchObject({ role: 'Chair', verified: true });
  });
});

describe('FED-03 tags', () => {
  it('only members not blocked; tagged residents are notified; no community notification', async () => {
    const r = await call('POST', '/posts', { token: ben, body: { text: 'Thanks @Cat Obi', mentionIds: [catId, (await me(far)).id] } });
    expect(r.body.post.mentions).toEqual([{ id: catId, name: 'Cat Obi' }]);
    const n = (await call('GET', '/notifications', { token: cat })).body.notifications;
    expect(n.filter((x: any) => x.type === 'mention')).toHaveLength(1);
    expect((await call('GET', '/notifications', { token: amy })).body.notifications.filter((x: any) => x.itemId === r.body.post.id)).toHaveLength(0);
  });
});

describe('FED-11 likes', () => {
  it('toggles, counts, lists, notifies the author but not for own posts', async () => {
    const p = (await call('POST', '/posts', { token: ben, body: { text: 'Like me' } })).body.post;
    expect((await call('POST', `/posts/${p.id}/like`, { token: cat })).body.likeCount).toBe(1);
    expect((await call('POST', `/posts/${p.id}/like`, { token: cat })).body.likeCount).toBe(1);
    await call('POST', `/posts/${p.id}/like`, { token: ben });
    expect((await call('GET', `/posts/${p.id}/likes`, { token: ben })).body.people.map((x: any) => x.name).sort()).toEqual(['Ben Ade', 'Cat Obi']);
    const likesForBen = (await call('GET', '/notifications', { token: ben })).body.notifications.filter((x: any) => x.type === 'post_like' && x.itemId === p.id);
    expect(likesForBen).toHaveLength(1);
    expect((await call('DELETE', `/posts/${p.id}/like`, { token: cat })).body.likeCount).toBe(1);
  });
});

describe('FED-12 - FED-14 comments and replies', () => {
  it('comments oldest first, replies one level, edit marks edited, delete keeps a placeholder when replies exist', async () => {
    const p = (await call('POST', '/posts', { token: ben, body: { text: 'Discuss' } })).body.post;
    expect((await call('POST', `/posts/${p.id}/comments`, { token: cat, body: { text: ' ' } })).body.error.code).toBe('EMPTY_COMMENT');
    const c1 = (await call('POST', `/posts/${p.id}/comments`, { token: cat, body: { text: 'First', mediaId: await photo(cat) } })).body.comment;
    expect(c1.imageUrl).toBeTruthy();
    const c2 = (await call('POST', `/posts/${p.id}/comments`, { token: amy, body: { text: 'Second' } })).body.comment;
    const r1 = (await call('POST', `/posts/${p.id}/comments`, { token: ben, body: { text: 'Reply', parentId: c1.id } })).body.comment;
    // A reply to a reply attaches to the top comment.
    const r2 = (await call('POST', `/posts/${p.id}/comments`, { token: amy, body: { text: 'Reply 2', parentId: r1.id } })).body.comment;
    expect(r2.parentId).toBe(c1.id);
    let list = (await call('GET', `/posts/${p.id}/comments`, { token: ben })).body.comments;
    expect(list.map((c: any) => c.text)).toEqual(['First', 'Second']);
    expect(list[0].replyCount).toBe(2);
    expect((await call('GET', `/comments/${c1.id}/replies`, { token: ben })).body.replies.map((c: any) => c.text)).toEqual(['Reply', 'Reply 2']);
    // Notifications: comment -> post author, reply -> comment author.
    const benN = (await call('GET', '/notifications', { token: ben })).body.notifications.filter((n: any) => n.itemId === p.id);
    expect(benN.map((n: any) => n.type).sort()).toEqual(['post_comment', 'post_comment']);
    const catN = (await call('GET', '/notifications', { token: cat })).body.notifications.filter((n: any) => n.itemId === p.id);
    expect(catN.map((n: any) => n.type)).toEqual(['comment_reply', 'comment_reply']);
    // Edit
    expect((await call('PATCH', `/comments/${c2.id}`, { token: cat, body: { text: 'hack' } })).status).toBe(403);
    expect((await call('PATCH', `/comments/${c2.id}`, { token: amy, body: { text: 'Second (fixed)' } })).body.comment.editedAt).toBeTruthy();
    // Delete
    expect((await call('DELETE', `/comments/${c1.id}`, { token: cat })).body.message).toBe('Comment deleted.');
    await call('DELETE', `/comments/${c2.id}`, { token: amy });
    list = (await call('GET', `/posts/${p.id}/comments`, { token: ben })).body.comments;
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ deleted: true, text: 'Comment is no longer available.' });
    expect((await call('GET', `/posts/${p.id}`, { token: ben })).body.post.commentCount).toBe(2);
  });
});

describe('FED-10 / FED-18 edit, delete, removed', () => {
  it('author edits and deletes; deleted and removed states', async () => {
    const p = (await call('POST', '/posts', { token: ben, body: { text: 'Typo' } })).body.post;
    expect((await call('PATCH', `/posts/${p.id}`, { token: cat, body: { text: 'no' } })).status).toBe(403);
    const e = await call('PATCH', `/posts/${p.id}`, { token: ben, body: { text: 'Fixed' } });
    expect(e.body).toMatchObject({ message: 'Changes saved to post.', post: { text: 'Fixed' } });
    expect((await call('DELETE', `/posts/${p.id}`, { token: ben })).body.message).toBe('Your post has been deleted.');
    const gone = await call('GET', `/posts/${p.id}`, { token: cat });
    expect(gone.status).toBe(410);
    expect(gone.body.error).toMatchObject({ code: 'POST_DELETED', title: 'Post unavailable', message: 'This post has been deleted by the author.' });
    const p2 = (await call('POST', '/posts', { token: ben, body: { text: 'Bad' } })).body.post;
    await q(`update posts set status = 'removed' where id = $1`, [p2.id]);
    for (const t of [ben, cat]) {
      expect((await call('GET', `/posts/${p2.id}`, { token: t })).body.error.message).toBe('This post has been removed for violating Keys Guidelines');
    }
    expect((await call('GET', `/posts/${p2.id}`, { token: far })).status).toBe(404);
  });
});

describe('POL polls', () => {
  it('POL-01.2 only committee members (not champions) can create', async () => {
    const body = { question: 'Bins on Tuesday?', options: [{ text: 'Yes' }, { text: 'No' }] };
    expect((await call('POST', '/polls', { token: ben, body })).body.error.code).toBe('COMMITTEE_ONLY');
    await seat(cat, 'Champion', 'champion');
    expect((await call('POST', '/polls', { token: cat, body })).body.error.code).toBe('COMMITTEE_ONLY');
    expect((await call('GET', '/polls/can-create', { token: amy })).body.canCreate).toBe(true);
  });
  it('POL-02 / POL-03 validation', async () => {
    expect((await call('POST', '/polls', { token: amy, body: { question: '', options: [{ text: 'a' }, { text: 'b' }] } })).body.error.message).toBe('Add a question');
    expect((await call('POST', '/polls', { token: amy, body: { question: 'Q', options: [{ text: 'a' }] } })).body.error.message).toBe('Add at least 2 options');
    expect((await call('POST', '/polls', { token: amy, body: { question: 'Q', options: Array.from({ length: 6 }, (_, i) => ({ text: `o${i}` })) } })).body.error.message).toBe('You can add up to 5 options');
    expect((await call('POST', '/polls', { token: amy, body: { question: 'Q', options: [{ text: 'a' }, { text: 'x'.repeat(41) }] } })).status).toBe(400);
    expect((await call('POST', '/polls', { token: amy, body: { question: 'Q', options: [{ text: 'a' }, { text: '' }] } })).body.error).toMatchObject({ code: 'OPTION_REQUIRED', indexes: [1] });
    const img = await photo(amy);
    const missing = await call('POST', '/polls', { token: amy, body: { question: 'Q', options: [{ text: 'a', mediaId: img }, { text: 'b' }, { text: 'c' }] } });
    expect(missing.body.error).toMatchObject({ message: 'Please add an image', indexes: [1, 2] });
  });
  it('POL-05 / POL-06 / POL-08 / POL-09 publish, vote once (final), results, close', async () => {
    const r = await call('POST', '/polls', { token: amy, body: { question: 'Street party date?', promise: 'Pick the date', options: [{ text: 'June' }, { text: 'July' }], duration: '48h' } });
    expect(r.body.message).toBe('Your post has been sent');
    const id = r.body.post.id;
    expect(r.body.post.poll).toMatchObject({ multi: false, closed: false, totalVotes: 0 });
    expect((await call('PATCH', `/posts/${id}`, { token: amy, body: { text: 'x' } })).body.error.code).toBe('POLL_LOCKED');
    // Feed shows polls as posts; results hidden before voting.
    const inFeed = (await call('GET', '/feed', { token: ben })).body.posts.find((p: any) => p.id === id);
    expect(inFeed.poll.options[0].votes).toBeNull();
    // POL-06.4: unverified cannot vote.
    const opt = inFeed.poll.options;
    expect((await call('POST', `/polls/${id}/vote`, { token: ben, body: { optionIds: [opt[0].id] } })).body.error.code).toBe('VERIFICATION_REQUIRED');
    await verify(ben); await verify(cat);
    expect((await call('POST', `/polls/${id}/vote`, { token: ben, body: { optionIds: [opt[0].id, opt[1].id] } })).body.error.message).toBe('Select one');
    const v = await call('POST', `/polls/${id}/vote`, { token: ben, body: { optionIds: [opt[0].id] } });
    expect(v.body.post.poll).toMatchObject({ totalVotes: 1, myVote: [opt[0].id], canVote: false });
    expect(v.body.post.poll.options[0]).toMatchObject({ votes: 1, percent: 100 });
    expect((await call('POST', `/polls/${id}/vote`, { token: ben, body: { optionIds: [opt[1].id] } })).body.error.message).toBe('Already voted');
    await call('POST', `/polls/${id}/vote`, { token: cat, body: { optionIds: [opt[1].id] } });
    clock.advance(48 * HOUR + 1000);
    expect((await call('POST', `/polls/${id}/vote`, { token: amy, body: { optionIds: [opt[0].id] } })).body.error.code).toBe('POLL_CLOSED');
    const closed = (await call('GET', `/posts/${id}`, { token: far === '' ? amy : amy })).body.post.poll;
    expect(closed.closed).toBe(true);
    expect(closed.options.map((o: any) => o.winner)).toEqual([true, true]); // tie
    expect(await closeDuePolls()).toBeGreaterThan(0);
    expect((await call('GET', '/notifications', { token: ben })).body.notifications.some((n: any) => n.type === 'poll_closed' && n.itemId === id)).toBe(true);
    expect(await closeDuePolls()).toBe(0);
  });
  it('POL-07 multi-select shares of voters; POL-11 creator deletes and votes go', async () => {
    const r = await call('POST', '/polls', { token: amy, body: { question: 'Which days?', multi: true, options: [{ text: 'Sat' }, { text: 'Sun' }, { text: 'Mon' }] } });
    const id = r.body.post.id;
    const o = r.body.post.poll.options;
    await call('POST', `/polls/${id}/vote`, { token: ben, body: { optionIds: [o[0].id, o[1].id] } });
    const v = await call('POST', `/polls/${id}/vote`, { token: cat, body: { optionIds: [o[0].id] } });
    expect(v.body.post.poll.options.map((x: any) => x.percent)).toEqual([100, 50, 0]);
    expect((await call('DELETE', `/posts/${id}`, { token: ben })).status).toBe(403);
    expect((await call('DELETE', `/posts/${id}`, { token: amy })).body.message).toBe('Your post has been deleted.');
    expect(await q('select 1 from poll_votes where post_id = $1', [id])).toHaveLength(0);
    void DAY; void benId; void amyId;
  });
});
