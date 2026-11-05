import { one, q, type Db } from '../../db/pool.js';
import { clock } from '../../lib/clock.js';
import { TIERS } from './service.js';

/**
 * CBM-Q2: community milestone prompts fire when the community moves up a tier.
 * Thresholds come from the tier table (100, 400, 700 residents), so they move
 * with it. Each milestone is reached once: a later drop and rise does not
 * fire it again.
 */
export const MILESTONES: number[] = TIERS.slice(1).map((t) => t.min);
/** The prompt shows for this long after the milestone is reached. */
export const MILESTONE_PROMPT_DAYS = 30;

/** Records every threshold the community has reached. Called whenever someone joins. */
export async function recordMilestones(communityId: string, db?: Db) {
  const n = (await one<{ n: number }>('select count(*)::int as n from memberships where community_id = $1', [communityId], db))!.n;
  for (const t of MILESTONES.filter((m) => n >= m)) {
    await q(
      'insert into community_milestones(community_id, threshold, reached_at) values ($1,$2,$3) on conflict do nothing',
      [communityId, t, clock.now()], db,
    );
  }
}

interface Reached { threshold: number; reached_at: Date }

async function reached(communityId: string) {
  const rows = await q<Reached>('select threshold, reached_at from community_milestones where community_id = $1 order by threshold desc', [communityId]);
  return { current: rows[0] as Reached | undefined, previous: rows[1] as Reached | undefined };
}

/** Residents who joined since the previous milestone, or since the community began. */
const EPOCH = new Date(0);

/**
 * The prompt for [userId]: the community's highest milestone while it is
 * recent, for residents who were already members when it was reached and
 * have not closed it.
 */
export async function milestonePrompt(userId: string, communityId: string) {
  const { current, previous } = await reached(communityId);
  if (!current) return null;
  if (clock.now().getTime() - current.reached_at.getTime() > MILESTONE_PROMPT_DAYS * 86400000) return null;
  const me = await one<{ joined_at: Date }>('select joined_at from memberships where user_id = $1 and community_id = $2', [userId, communityId]);
  if (!me || me.joined_at > current.reached_at) return null;
  const seen = await one('select 1 from milestone_seen where user_id = $1 and community_id = $2 and threshold = $3', [userId, communityId, current.threshold]);
  if (seen) return null;
  const n = (await one<{ n: number }>(
    'select count(*)::int as n from memberships where community_id = $1 and joined_at > $2',
    [communityId, previous?.reached_at ?? EPOCH],
  ))!.n;
  return {
    threshold: current.threshold,
    title: `${current.threshold} members strong`,
    body: `Exciting news! Your community has welcomed ${n} new ${n === 1 ? 'resident' : 'residents'}. Let's come together to greet them and make them feel at home!`,
    newResidents: n,
  };
}

export async function markMilestoneSeen(userId: string, communityId: string, threshold: number) {
  await q(
    'insert into milestone_seen(user_id, community_id, threshold, seen_at) values ($1,$2,$3,$4) on conflict do nothing',
    [userId, communityId, threshold, clock.now()],
  );
}

/** "New members": residents who joined since the previous milestone, newest first, without blocked people or the viewer. */
export async function newMemberIds(viewerId: string, communityId: string) {
  const { previous } = await reached(communityId);
  const rows = await q<{ user_id: string }>(
    `select m.user_id from memberships m
      where m.community_id = $1 and m.joined_at > $2 and m.user_id <> $3
        and not exists (select 1 from blocks b where (b.user_id = $3 and b.target_id = m.user_id) or (b.user_id = m.user_id and b.target_id = $3))
      order by m.joined_at desc limit 500`,
    [communityId, previous?.reached_at ?? EPOCH, viewerId],
  );
  return rows.map((r) => r.user_id);
}
