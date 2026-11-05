import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { requireUser, requireVerified } from '../../lib/auth.js';
import { clock, DAY } from '../../lib/clock.js';
import { badRequest, conflict, forbidden } from '../../lib/errors.js';
import { notify } from '../../lib/notify.js';
import { isCommittee, requireCommunity } from '../../lib/people.js';
import { loadPost, postView } from './read.js';

export const DURATIONS = { '24h': DAY, '48h': 2 * DAY, '7d': 7 * DAY, '2w': 14 * DAY } as const;
export const QUESTION_MAX = 200;
export const PROMISE_MAX = 200; // POL-D3: design shows 0/50 and 116/200; 200 used (needs check)
export const OPTION_MAX = 40;
export const OPTIONS_MIN = 2;
export const OPTIONS_MAX = 5;

/** Closes polls whose time is up and tells the creator and voters (default for POL-Q3). */
export async function closeDuePolls() {
  const due = await q<{ post_id: string; author_id: string }>(
    `update polls set closed_notified_at = $1 from posts p
      where p.id = polls.post_id and p.status = 'live' and polls.closes_at <= $1 and polls.closed_notified_at is null
      returning polls.post_id, p.author_id`,
    [clock.now()],
  );
  for (const d of due) {
    const voters = await q<{ user_id: string }>('select user_id from poll_votes where post_id = $1', [d.post_id]);
    const who = new Set([d.author_id, ...voters.map((v) => v.user_id)]);
    for (const id of who) await notify(id, 'poll_closed', null, { type: 'post', id: d.post_id });
  }
  return due.length;
}

export async function pollRoutes(app: FastifyInstance) {
  // POL-01.2: committee members only (champions and residents cannot).
  app.get('/polls/can-create', async (req) => ({ canCreate: await isCommittee(requireUser(req).id) }));

  // POL-02 - POL-05
  app.post('/polls', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      question: z.string().trim().min(1, 'Add a question').max(QUESTION_MAX),
      promise: z.string().trim().max(PROMISE_MAX).optional(),
      options: z.array(z.object({ text: z.string().trim().max(OPTION_MAX, `Options can be up to ${OPTION_MAX} characters`), mediaId: z.string().uuid().optional() }))
        .min(OPTIONS_MIN, `Add at least ${OPTIONS_MIN} options`).max(OPTIONS_MAX, `You can add up to ${OPTIONS_MAX} options`),
      multi: z.boolean().default(false),
      duration: z.enum(['24h', '48h', '7d', '2w']).default('24h'),
    }).parse(req.body);
    if (!(await isCommittee(u.id))) throw forbidden('COMMITTEE_ONLY', 'Only committee members can create polls.');
    const community = await requireCommunity(u.id);
    const empty = b.options.map((o, i) => (o.text ? -1 : i)).filter((i) => i >= 0);
    if (empty.length) throw badRequest('OPTION_REQUIRED', 'Add an option', { field: `options.${empty[0]}`, indexes: empty });
    // POL-03.3: images on all options or none.
    const withImg = b.options.filter((o) => o.mediaId).length;
    if (withImg && withImg !== b.options.length) {
      const missing = b.options.map((o, i) => (o.mediaId ? -1 : i)).filter((i) => i >= 0);
      throw badRequest('OPTION_IMAGE_REQUIRED', 'Please add an image', { field: `options.${missing[0]}`, indexes: missing });
    }
    const ids = b.options.map((o) => o.mediaId).filter(Boolean) as string[];
    if (ids.length) {
      const ok = await q(`select id from media where id = any($1) and owner_id = $2 and kind = 'photo'`, [ids, u.id]);
      if (ok.length !== new Set(ids).size) throw badRequest('MEDIA_INVALID', 'One of the images could not be found. Please add it again.');
    }
    const now = clock.now();
    const post = await tx(async (c) => {
      const p = (await one<any>(
        `insert into posts(community_id, author_id, kind, text, created_at) values ($1,$2,'poll',$3,$4) returning *`,
        [community, u.id, b.question, now], c,
      ))!;
      await q(
        `insert into polls(post_id, question, promise, multi, duration, closes_at) values ($1,$2,$3,$4,$5,$6)`,
        [p.id, b.question, b.promise || null, b.multi, b.duration, new Date(now.getTime() + DURATIONS[b.duration])], c,
      );
      for (const [i, o] of b.options.entries()) {
        await q('insert into poll_options(post_id, position, text, media_id) values ($1,$2,$3,$4)', [p.id, i, o.text, o.mediaId ?? null], c);
      }
      return p;
    });
    return { post: await postView(post, u.id), message: 'Your post has been sent' };
  });

  // POL-06 / POL-07: verified residents vote once; votes are final (POL-Q1 decided).
  app.post('/polls/:id/vote', async (req) => {
    const u = await requireVerified(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const { optionIds } = z.object({ optionIds: z.array(z.string().uuid()).min(1, 'Choose an option') }).parse(req.body);
    const post = await loadPost(id, u.id);
    const poll = await one<any>('select * from polls where post_id = $1', [id]);
    if (!poll) throw badRequest('NOT_A_POLL', 'This post is not a poll.');
    if (poll.closes_at <= clock.now()) throw conflict('POLL_CLOSED', 'This poll has closed.');
    const picked = [...new Set(optionIds)];
    if (!poll.multi && picked.length !== 1) throw badRequest('ONE_OPTION', 'Select one');
    const valid = await q('select id from poll_options where post_id = $1 and id = any($2)', [id, picked]);
    if (valid.length !== picked.length) throw badRequest('OPTION_INVALID', 'Choose an option from this poll.');
    const r = await one(
      `insert into poll_votes(post_id, user_id, option_ids, created_at) values ($1,$2,$3,$4) on conflict do nothing returning 1`,
      [id, u.id, picked, clock.now()],
    );
    if (!r) throw conflict('ALREADY_VOTED', 'Already voted');
    return { post: await postView(post, u.id) };
  });

}
