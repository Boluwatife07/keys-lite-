import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { q } from '../src/db/pool.js';
import { clock, DAY } from '../src/lib/clock.js';
import { call, joinStreet, pioneerStreet, setup, teardown } from './helpers.js';

/** Adds [n] residents straight into the community, joined [daysAgo] days ago. */
async function bulk(communityId: string, n: number, tag: string, daysAgo = 1) {
  await q(
    `with u as (insert into users(email, first_name, last_name) select '${tag}'||g||'@keys.test','New','Resident' from generate_series(1,$2::int) g returning id)
     insert into memberships(user_id, community_id, level, joined_at) select id, $1, 'house', $3 from u`,
    [communityId, n, new Date(clock.now().getTime() - daysAgo * DAY)],
  );
}
const community = async (t: string) => (await call('GET', '/community', { token: t })).body;

let pioneer: string;
let communityId: string;

beforeAll(async () => {
  await setup();
  const p = await pioneerStreet('pioneer@keys.test', '1 Maple Road');
  pioneer = p.token;
  communityId = p.community.id;
});
afterAll(teardown);

describe('CBM-Q2 community milestone prompts', () => {
  it('nothing below 100 residents, even with no committee board', async () => {
    await bulk(communityId, 97, 'a', 3);
    expect((await community(pioneer)).milestone).toBeNull();
    expect((await community(pioneer)).board).toBeNull();
  });

  it('the join that reaches 100 fires "100 members strong" for existing residents only', async () => {
    const t99 = await joinStreet('n99@keys.test', '99 Maple Road');
    expect((await community(t99)).milestone).toBeNull(); // 99 residents
    const t100 = await joinStreet('n100@keys.test', '100 Maple Road');
    const m = (await community(pioneer)).milestone;
    expect(m).toEqual({
      threshold: 100,
      title: '100 members strong',
      body: "Exciting news! Your community has welcomed 100 new residents. Let's come together to greet them and make them feel at home!",
      newResidents: 100,
    });
    // The resident whose join reached it was a member at that moment too.
    expect((await community(t100)).milestone?.threshold).toBe(100);
    clock.advance(1000);
    const later = await joinStreet('n101@keys.test', '101 Maple Road');
    expect((await community(later)).milestone).toBeNull();
  });

  it('"View new residents" lists newest first, without the viewer; closing it hides it for good', async () => {
    const list = (await call('GET', '/community/new-members', { token: pioneer })).body.members;
    expect(list[0].name).toBe('Ben Ade');
    expect(list).toHaveLength(100);
    const bad = await call('POST', '/community/milestone/seen', { token: pioneer, body: { threshold: 150 } });
    expect(bad.status).toBe(400);
    expect((await call('POST', '/community/milestone/seen', { token: pioneer, body: { threshold: 100 } })).status).toBe(200);
    expect((await community(pioneer)).milestone).toBeNull();
  });

  it('400 counts only residents who joined since the 100 milestone; the prompt ends after 30 days', async () => {
    const before = (await q<{ n: number }>('select count(*)::int as n from memberships where community_id = $1', [communityId]))[0].n;
    await bulk(communityId, 399 - before, 'b', 0);
    clock.advance(1000);
    await joinStreet('n400@keys.test', '140 Maple Road');
    const m = (await community(pioneer)).milestone;
    expect(m.threshold).toBe(400);
    expect(m.newResidents).toBe(400 - 100);
    expect(m.title).toBe('400 members strong');
    clock.advance(31 * DAY);
    expect((await community(pioneer)).milestone).toBeNull();
  });

  it('a milestone is reached once: dropping below and rising again does not repeat it', async () => {
    await q(`delete from memberships where user_id in (select id from users where email like 'b%@keys.test')`);
    const now = (await q<{ n: number }>('select count(*)::int as n from memberships where community_id = $1', [communityId]))[0].n;
    expect(now).toBeLessThan(400);
    await bulk(communityId, 399 - now, 'c', 0);
    clock.advance(1000);
    await joinStreet('again@keys.test', '142 Maple Road');
    const rows = await q('select threshold from community_milestones where community_id = $1 order by threshold', [communityId]);
    expect(rows.map((r: any) => r.threshold)).toEqual([100, 400]);
  });
});
