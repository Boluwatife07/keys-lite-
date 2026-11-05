import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { one, q } from '../src/db/pool.js';
import { clock, DAY, HOUR } from '../src/lib/clock.js';
import { proposalJobs } from '../src/modules/board/proposals.js';
import { call, joinStreet, me, pioneerStreet, setup, teardown, verify } from './helpers.js';

const A = { pledge: true, hasLeadership: false, qualified: 'I run the residents WhatsApp group', aim: 'Cleaner streets' };
const ROLES = ['Chair', 'Vice Chair', 'Treasurer', 'Secretary', 'Projects Lead', 'Events Lead', 'Clubs Lead', 'Communications Lead'];

let n = 0;
async function resident(street = 'Maple Road', verified = true) {
  n++;
  const t = await joinStreet(`r${n}@keys.test`, `${n + 10} ${street}`, `Res${n}`, 'Ident');
  if (verified) await verify(t);
  return { t, id: (await me(t)).id };
}
const notes = async (t: string, type: string) => (await call('GET', '/notifications', { token: t })).body.notifications.filter((x: any) => x.type === type);

let chair: { t: string; id: string };
const members: { t: string; id: string }[] = [];

beforeAll(async () => {
  await setup();
  chair = { t: (await pioneerStreet('chair@keys.test', '1 Maple Road')).token, id: '' };
  chair.id = (await me(chair.t)).id;
});
afterAll(teardown);

describe('CBM-02 / CBM-04 create the board', () => {
  it('needs verification; the first member creates the board in a role', async () => {
    expect((await call('GET', '/community', { token: chair.t })).body.board).toBeNull();
    expect((await call('POST', '/board', { token: chair.t, body: { ...A, role: 'Chair' } })).body.error.code).toBe('VERIFICATION_REQUIRED');
    await verify(chair.t);
    expect((await call('POST', '/board', { token: chair.t, body: { ...A, pledge: false, role: 'Chair' } })).status).toBe(400);
    expect((await call('POST', '/board', { token: chair.t, body: { ...A, qualified: '', role: 'Chair' } })).body.error.message).toBe('Tell us what makes you qualified for this role');
    const r = await call('POST', '/board', { token: chair.t, body: { ...A, role: 'Chair' } });
    expect(r.body.message).toBe('Committee board for your community has been created successfully.');
    const c = (await call('GET', '/community', { token: chair.t })).body;
    expect(c.board).toMatchObject({ committeeCount: 1, tier: 1, votingAvailable: false });
    expect(c.me).toMatchObject({ role: 'Chair', isCommittee: true, isChair: true });
    expect(c.proposalsTab).toBe(true);
    expect(c.announcements[0]).toMatchObject({ label: 'New member', text: 'Res0 Ident has just joined the committee board as the Chair.'.replace('Res0 Ident', 'Amy Duncan') });
    expect(c.community.location).toBe('Street | London, SE1, UK');
    expect((await call('POST', '/board', { token: chair.t, body: { ...A, role: 'Chair' } })).body.error.code).toBe('BOARD_EXISTS');
  });
});

describe('CBM-05 preset roles: first come, first served', () => {
  it('fills the 8 preset roles; a race for one role loses cleanly', async () => {
    const [x, y] = [await resident(), await resident()];
    const [r1, r2] = await Promise.all([
      call('POST', '/board/join', { token: x.t, body: { ...A, role: 'Vice Chair' } }),
      call('POST', '/board/join', { token: y.t, body: { ...A, role: 'Vice Chair' } }),
    ]);
    expect([r1.status, r2.status].sort()).toEqual([200, 409]);
    const loser = r1.status === 409 ? x : y;
    const winner = r1.status === 409 ? y : x;
    expect((r1.status === 409 ? r1 : r2).body.error.message).toBe('This seat has just been filled. Please choose another role.');
    members.push(winner);
    const tj = await call('POST', '/board/join', { token: loser.t, body: { ...A, role: 'Treasurer' } });
    expect(tj.body.message).toBe('You are now a member of the committee board.');
    members.push(loser);
    const roles = (await call('GET', '/board/roles', { token: loser.t })).body.roles;
    expect(roles.filter((r: any) => r.available).map((r: any) => r.role)).toEqual(ROLES.slice(3));
    expect(roles[0].about.length).toBeGreaterThan(0);
    for (const role of ROLES.slice(3)) {
      const m = await resident();
      await call('POST', '/board/join', { token: m.t, body: { ...A, role } });
      members.push(m);
    }
    const b = (await call('GET', '/board', { token: chair.t })).body;
    expect(b.counts).toMatchObject({ members: 8, champions: 0 });
    expect(b.votingAvailable).toBe(true);
    expect((await call('POST', '/board/join', { token: members[0].t, body: { ...A, role: 'Chair' } })).body.error.code).toBe('ALREADY_ON_BOARD');
  });
  it('unverified residents cannot join (CBM-19.3)', async () => {
    const u = await resident('Maple Road', false);
    expect((await call('POST', '/board/join', { token: u.t, body: { ...A, role: 'Chair' } })).body.error.code).toBe('VERIFICATION_REQUIRED');
  });
});

let champSeat: string;
describe('CBM-11 manage seats (Chair only)', () => {
  it('Tier 1 champions unlock after the 8 preset roles; only empty seats toggle', async () => {
    expect((await call('GET', '/board/manage', { token: members[0].t })).body.error.code).toBe('CHAIR_ONLY');
    const m = (await call('GET', '/board/manage', { token: chair.t })).body;
    expect(m).toMatchObject({ tier: 1, tierLabel: 'Tier 1 · up to 100 residents', additionalSeats: [], championsLockedReason: null });
    expect(m.championSeats).toHaveLength(10);
    expect(m.presetRoles.every((s: any) => !s.canToggle)).toBe(true);
    champSeat = m.championSeats[0].id;
    expect((await call('POST', `/board/seats/${champSeat}/activate`, { token: chair.t })).body.message).toBe('Seat activated.');
    expect((await call('POST', `/board/seats/${m.presetRoles[0].id}/deactivate`, { token: chair.t })).body.error.code).toBe('PRESET_LOCKED');
    const b = (await call('GET', '/board', { token: members[0].t })).body;
    expect(b.seats.filter((s: any) => s.kind === 'champion')).toEqual([expect.objectContaining({ status: 'unoccupied', role: 'Champion' })]);
  });
});

describe('VOT join proposals', () => {
  let p1: string; let a1: { t: string; id: string }; let a2: { t: string; id: string };
  it('CBM-06 applying makes a proposal; one application at a time; committee are told', async () => {
    a1 = await resident(); a2 = await resident();
    const r = await call('POST', '/board/join', { token: a1.t, body: { ...A, seatId: champSeat } });
    expect(r.body).toMatchObject({ status: 'pending', title: 'Application in review' });
    p1 = r.body.proposalId;
    expect((await call('POST', '/board/join', { token: a1.t, body: { ...A, role: 'Chair' } })).body.error.code).toBe('APPLICATION_PENDING');
    expect((await call('GET', '/board', { token: a1.t })).body.seats.find((s: any) => s.id === champSeat).status).toBe('pending');
    expect((await notes(chair.t, 'proposal_created'))[0].data.message).toBe('Res11 Ident has requested to join the committee'.replace('Res11', `Res${n - 1}`));
    await call('POST', '/board/join', { token: a2.t, body: { ...A, seatId: champSeat } });
  });
  it('VOT-01.5 residents and applicants cannot see proposals', async () => {
    expect((await call('GET', '/board/proposals', { token: a1.t })).body.error.code).toBe('COMMITTEE_ONLY');
  });
  it('VOT-02 detail shows answers; results after voting; VOT-05.3 closes early at >50%', async () => {
    const d = (await call('GET', `/board/proposals/${p1}`, { token: chair.t })).body.proposal;
    expect(d).toMatchObject({ typeLabel: 'Join board', role: 'Champion', status: 'pending', canVote: true, answers: { qualified: A.qualified, aim: A.aim } });
    expect(d.results).toBeUndefined();
    const v = await call('POST', `/board/proposals/${p1}/vote`, { token: chair.t, body: { choice: 'yes' } });
    expect(v.body.proposal).toMatchObject({ status: 'awaiting_approval', results: { yes: 1, no: 0, yesPercent: 100, eligible: 8 } });
    expect((await call('POST', `/board/proposals/${p1}/vote`, { token: chair.t, body: { choice: 'no' } })).body.error.message).toBe('Already voted');
    for (const m of members.slice(0, 3)) await call('POST', `/board/proposals/${p1}/vote`, { token: m.t, body: { choice: 'yes' } });
    expect((await call('GET', `/board/proposals/${p1}`, { token: chair.t })).body.proposal.status).toBe('awaiting_approval'); // 4 of 8 is not more than half
    const last = await call('POST', `/board/proposals/${p1}/vote`, { token: members[3].t, body: { choice: 'yes' } });
    expect(last.body.proposal.status).toBe('added');
    expect((await call('GET', '/community', { token: a1.t })).body.me).toMatchObject({ isChampion: true, isCommittee: false });
    expect((await notes(a1.t, 'proposal_result'))[0].data.message).toBe("Congratulations! You've been appointed as a community champion.");
  });
  it('CBM-06.4 / VOT-05.6 the other applicant for that seat is declined with NEW SEAT PROTECTION', async () => {
    const list = (await call('GET', '/board/proposals?status=declined', { token: chair.t })).body.proposals;
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ subject: { id: a2.id }, outcomeNote: 'This proposal was turned down because the seat is already filled by the first winning applicant.' });
  });
  it('VOT-05.5 champions cannot vote or create proposals', async () => {
    expect((await call('POST', '/board/proposals', { token: a1.t, body: { type: 'remove', subjectId: members[0].id, reason: 'x' } })).body.error.code).toBe('COMMITTEE_ONLY');
  });
});

describe('VOT reassign and remove', () => {
  it('CBM-15 / VOT-03 swap roles: creator votes yes; No needs a reason; approval swaps both', async () => {
    const treasurer = members[1]; // Treasurer
    const secSeat = (await call('GET', '/board', { token: chair.t })).body.seats.find((s: any) => s.role === 'Secretary');
    const r = await call('POST', '/board/proposals', { token: treasurer.t, body: { type: 'reassign', subjectId: treasurer.id, seatId: secSeat.id, reason: 'I keep the minutes anyway' } });
    expect(r.body.message).toBe('Your request to reassign to the role of Secretary has been submitted and sent to the committee board for approval');
    const d = (await call('GET', `/board/proposals/${r.body.proposalId}`, { token: chair.t })).body.proposal;
    expect(d).toMatchObject({ typeLabel: 'Reassign role', role: 'Treasurer', proposedRole: 'Secretary' });
    expect(d.swap.note).toBe(`If this proposal is approved by the board, ${secSeat.occupant.name}'s current role would be reassigned to ${(await me(treasurer.t)).firstName} Ident as well.`);
    expect((await call('POST', `/board/proposals/${r.body.proposalId}/vote`, { token: chair.t, body: { choice: 'no' } })).body.error.code).toBe('REASON_REQUIRED');
    for (const m of [chair, members[0], members[3], members[4]]) await call('POST', `/board/proposals/${r.body.proposalId}/vote`, { token: m.t, body: { choice: 'yes' } });
    const b = (await call('GET', '/board', { token: chair.t })).body;
    expect(b.seats.find((s: any) => s.role === 'Secretary').occupant.id).toBe(treasurer.id);
    expect(b.seats.find((s: any) => s.role === 'Treasurer').occupant.id).toBe(secSeat.occupant.id);
    const ann = (await call('GET', '/board/announcements', { token: chair.t })).body.announcements;
    expect(ann.slice(0, 2).map((a: any) => a.label)).toEqual(['Role change', 'Role change']);
  });
  it('CBM-16 / VOT-04 remove: the subject cannot vote; approval empties the seat', async () => {
    const target = members[5];
    const r = await call('POST', '/board/proposals', { token: chair.t, body: { type: 'remove', subjectId: target.id, reason: 'Inactive for months' } });
    expect(r.body.message).toMatch(/^Your request to remove .* has been submitted and sent to the committee board for approval$/);
    expect((await call('POST', `/board/proposals/${r.body.proposalId}/vote`, { token: target.t, body: { choice: 'no', reason: 'no' } })).body.error.code).toBe('CANNOT_VOTE');
    expect((await call('POST', '/board/proposals', { token: members[0].t, body: { type: 'remove', subjectId: target.id, reason: 'again' } })).body.error.code).toBe('PROPOSAL_OPEN');
    for (const m of members.slice(0, 3)) await call('POST', `/board/proposals/${r.body.proposalId}/vote`, { token: m.t, body: { choice: 'yes' } });
    expect((await call('GET', `/board/proposals/${r.body.proposalId}`, { token: chair.t })).body.proposal.status).toBe('approved');
    expect((await call('GET', '/community', { token: target.t })).body.me.isCommittee).toBe(false);
    expect((await call('GET', '/board/announcements', { token: chair.t })).body.announcements[0].label).toBe('Member removal');
    expect((await notes(target.t, 'proposal_result'))[0].data.message).toMatch(/^You've been voted out of the Board/);
  });
  it('VOT-05.4 at 7 days only cast votes count and a tie passes; VOT-06.2 reminders 24h before', async () => {
    const empty = (await call('GET', '/board', { token: chair.t })).body.seats.find((s: any) => s.kind === 'preset' && !s.occupant);
    const x = await resident();
    const j = await call('POST', '/board/join', { token: x.t, body: { ...A, role: empty.role } });
    expect(j.body.status).toBe('added'); // preset role, no vote
    const r = await call('POST', '/board/proposals', { token: chair.t, body: { type: 'remove', subjectId: x.id, reason: 'test tie' } });
    await call('POST', `/board/proposals/${r.body.proposalId}/vote`, { token: members[0].t, body: { choice: 'no', reason: 'Give them time' } });
    clock.advance(6 * DAY + HOUR);
    expect((await proposalJobs()).reminded).toBeGreaterThan(0);
    expect((await notes(members[1].t, 'proposal_reminder')).length).toBeGreaterThan(0);
    expect((await notes(members[0].t, 'proposal_reminder')).filter((z: any) => z.itemId === r.body.proposalId)).toHaveLength(0);
    clock.advance(DAY);
    await proposalJobs();
    expect((await call('GET', `/board/proposals/${r.body.proposalId}`, { token: chair.t })).body.proposal.status).toBe('approved');
  });
});

describe('CBM-13 / CBM-14 exit and Chair handover', () => {
  it('Chair exits: Vice Chair becomes Chair with exit and role change announcements', async () => {
    const vice = members[0];
    expect((await call('POST', '/board/exit', { token: chair.t, body: { reason: '' } })).status).toBe(400);
    const r = await call('POST', '/board/exit', { token: chair.t, body: { reason: 'Moving abroad soon' } });
    expect(r.body).toEqual({ title: 'Sad to see you leave!', message: "Your access in the community has been reverted to a resident's." });
    const c = (await call('GET', '/community', { token: vice.t })).body;
    expect(c.me.role).toBe('Chair');
    expect(c.announcements.slice(0, 2).map((a: any) => a.label)).toEqual(['Role change', 'Board exit']);
    expect(c.announcements[1].reason).toBe('Moving abroad soon');
    expect(c.announcements[0].text).toMatch(/has been assigned as Chair$/);
  });
  it('VOT-05.7 a proposer who moves away makes their proposals no longer applicable', async () => {
    const newChair = members[0];
    const sub = members[3];
    const r = await call('POST', '/board/proposals', { token: members[4].t, body: { type: 'remove', subjectId: sub.id, reason: 'x' } });
    await call('POST', '/me/move', { token: members[4].t });
    expect((await call('GET', `/board/proposals/${r.body.proposalId}`, { token: newChair.t })).body.proposal.status).toBe('no_longer_applicable');
  });
});

describe('CBM-06.5 / CBM-Q1 boards under 5 members join without a vote', () => {
  it('Tier 2 community, 1-member board: an extra seat is joined straight away', async () => {
    const t = (await pioneerStreet('small@keys.test', '1 Hazel Drive')).token;
    await verify(t);
    const c = (await me(t)).community.id;
    await q(`with u as (insert into users(email, first_name, last_name) select 'bulk'||g||'@keys.test','B','C' from generate_series(1,120) g returning id)
             insert into memberships(user_id, community_id, level) select id, $1, 'house' from u`, [c]);
    await call('POST', '/board', { token: t, body: { ...A, role: 'Chair' } });
    const m = (await call('GET', '/board/manage', { token: t })).body;
    expect(m.tier).toBe(2);
    expect(m.additionalSeats).toHaveLength(4);
    expect(m.championSeats).toHaveLength(14);
    expect(m.championsLockedReason).toBeNull(); // CBM-11.3: Tier 2 champions do not wait
    await call('POST', `/board/seats/${m.additionalSeats[0].id}/activate`, { token: t });
    const x = await joinStreet('x2@keys.test', '9 Hazel Drive', 'Xan', 'Der');
    await verify(x);
    const r = await call('POST', '/board/join', { token: x, body: { ...A, seatId: m.additionalSeats[0].id } });
    expect(r.body).toMatchObject({ status: 'added', role: 'Committee Member' });
    expect((await call('POST', '/board/proposals', { token: t, body: { type: 'remove', subjectId: (await me(x)).id, reason: 'x' } })).body.error.code).toBe('BOARD_TOO_SMALL');
    expect((await call('POST', `/board/seats/${m.additionalSeats[0].id}/deactivate`, { token: t })).body.error.code).toBe('SEAT_OCCUPIED');
  });
  it('CBM-10 tiers table', async () => {
    const r = (await call('GET', '/board/tiers', { token: (await call('POST', '/auth/login', { body: { email: 'small@keys.test', password: 'Keys2026!' } })).body.token })).body;
    expect(r.currentTier).toBe(2);
    expect(r.tiers.map((t: any) => [t.residentsLabel, t.committee, t.champions])).toEqual([['0-99', 8, 10], ['100-399', 12, 14], ['400-699', 16, 18], ['700+', 20, 22]]);
  });
});

it('CBM-12.1 a tier rise tells the Chair', async () => {
  const t = (await call('POST', '/auth/login', { body: { email: 'small@keys.test', password: 'Keys2026!' } })).body.token;
  const c = (await me(t)).community.id;
  await q(`with u as (insert into users(email, first_name, last_name) select 'more'||g||'@keys.test','B','C' from generate_series(1,300) g returning id)
           insert into memberships(user_id, community_id, level) select id, $1, 'house' from u`, [c]);
  const r = (await call('GET', '/community', { token: t })).body;
  expect(r.tierUp).toEqual({ tier: 3 });
  expect((await notes(t, 'tier_up'))).toHaveLength(1);
  void one;
});
