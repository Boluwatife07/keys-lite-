import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { one, q } from '../src/db/pool.js';
import { clock, DAY, HOUR } from '../src/lib/clock.js';
import { clubJobs } from '../src/modules/clubs/routes.js';
import { call, eventBasics, joinStreet, me, pioneerStreet, placeId, PNG, setup, teardown, upload, verify } from './helpers.js';

let pres: string; let ben: string; let cara: string; let dan: string; let unverified: string;
let benId: string; let caraId: string; let danId: string;
let cover: string;
const notes = async (t: string) => (await call('GET', '/notifications', { token: t })).body.notifications.map((n: any) => n.type);
const inDays = (d: number, hour = 18) => {
  const t = new Date(clock.now().getTime() + d * DAY);
  t.setUTCHours(hour, 0, 0, 0);
  return t.toISOString();
};

async function club(token: string, name: string, extra: Record<string, unknown> = {}) {
  const img = (await upload('/media?kind=photo', token, { name: 'c.png', mime: 'image/png', data: PNG })).body.id;
  return call('POST', '/clubs', { token, body: { name, description: 'For fans', category: 'Sports', memberLimit: 10, coverMediaId: img, ...extra } });
}

beforeAll(async () => {
  await setup();
  pres = (await pioneerStreet('pres@keys.test', '1 Maple Road')).token;
  ben = await joinStreet('ben@keys.test', '2 Maple Road', 'Ben', 'Ade');
  cara = await joinStreet('cara@keys.test', '3 Maple Road', 'Cara', 'Lee');
  dan = await joinStreet('dan@keys.test', '4 Maple Road', 'Dan', 'Moss');
  unverified = await joinStreet('unv@keys.test', '5 Maple Road', 'Una', 'Ver');
  for (const t of [pres, ben, cara, dan]) await verify(t);
  benId = (await me(ben)).id; caraId = (await me(cara)).id; danId = (await me(dan)).id;
  cover = (await upload('/media?kind=photo', pres, { name: 'c.png', mime: 'image/png', data: PNG })).body.id;
});
afterAll(teardown);

let blues: any;
describe('CLB-03 create', () => {
  it('verified only; name unique and 60 max; description 300; limit 10+; cover required; invites; chat', async () => {
    expect((await club(unverified, 'Nope')).body.error.code).toBe('VERIFICATION_REQUIRED');
    expect((await club(pres, 'x'.repeat(61))).status).toBe(400);
    expect((await club(pres, 'Long', { description: 'x'.repeat(301) })).status).toBe(400);
    expect((await club(pres, 'Small', { memberLimit: 9 })).body.error.message).toBe('Minimum of 10');
    expect((await call('POST', '/clubs', { token: pres, body: { name: 'No cover', category: 'Sports', memberLimit: 10 } })).status).toBe(400);
    const r = await club(pres, 'Blues United FC Fans', { inviteIds: [benId] });
    expect(r.body).toMatchObject({ title: 'Club created!', message: "You've successfully created Blues United FC Fans.", invited: 1 });
    blues = r.body.club;
    expect(blues).toMatchObject({ myRole: 'president', memberCount: 1, price: 'Free' });
    expect(blues.chatId).toBeTruthy();
    expect(await notes(ben)).toContain('club_invite');
    expect((await club(cara, 'blues united fc fans')).body.error.code).toBe('NAME_TAKEN');
  });

  it('CLB-04 templates and CLB-01 / CLB-02 discover and search', async () => {
    const t = (await call('GET', '/clubs/templates', { token: ben })).body.templates;
    expect(t.map((x: any) => x.label)).toEqual(['Baking', 'Photography', 'Golf', 'Cycling', 'Running', 'Gaming', 'Dog Owners', 'Gastro']);
    expect(t.every((x: any) => x.description.length <= 300)).toBe(true);
    const d = (await call('GET', '/clubs/discover?q=un', { token: ben })).body;
    expect(d.clubs.map((c: any) => c.name)).toEqual(['Blues United FC Fans']);
    expect(d.clubs[0]).toMatchObject({ isMember: false, othersText: '+1 other is in this club' });
    expect((await call('GET', '/clubs/discover?q=zzz', { token: ben })).body.clubs).toEqual([]);
    expect((await call('GET', '/clubs/discover?category=Music', { token: ben })).body.clubs).toEqual([]);
    expect((await call('GET', '/clubs/home', { token: ben })).body.myClubs).toEqual([]);
  });
});

describe('CLB-06 join, CLB-15 chat mirrors membership, CLB-08 leave and mute', () => {
  it('join adds to the chat and sends the welcome; leaving removes from the chat', async () => {
    expect((await call('POST', `/clubs/${blues.id}/join`, { token: unverified })).body.error.code).toBe('VERIFICATION_REQUIRED');
    const j = await call('POST', `/clubs/${blues.id}/join`, { token: ben });
    expect(j.body.message).toBe("You've joined the Blues United FC Fans");
    expect(await notes(ben)).toContain('club_welcome');
    expect((await call('GET', `/chats/${blues.chatId}`, { token: ben })).body.myRole).toBe('member');
    // The club chat cannot be left or joined on its own.
    expect((await call('POST', `/chats/${blues.chatId}/exit`, { token: ben })).body.error.code).toBe('CLUB_CHAT');
    expect((await call('PUT', `/clubs/${blues.id}/mute`, { token: ben, body: { duration: '1w' } })).body.message).toBe('You muted Blues United FC Fans');
    expect((await call('POST', `/clubs/${blues.id}/leave`, { token: ben })).body.message).toBe('You exited Blues United FC Fans');
    expect((await call('GET', `/chats/${blues.chatId}`, { token: ben })).body.myRole).toBeNull();
    expect((await call('POST', `/clubs/${blues.id}/leave`, { token: pres })).body.error.code).toBe('PRESIDENT');
  });

  it('full club: refused, President told when full and after 10 attempts in 7 days', async () => {
    const r = (await club(cara, 'Tiny Club')).body.club;
    for (let i = 0; i < 9; i++) {
      const u = (await one<{ id: string }>(`insert into users(email, first_name, last_name, verification_status) values ($1,'Fill','Er','verified') returning id`, [`f${i}@keys.test`]))!;
      await q(`insert into club_members(club_id, user_id, role) values ($1,$2,'member')`, [r.id, u.id]);
    }
    const full = await call('POST', `/clubs/${r.id}/join`, { token: dan });
    expect(full.body.error).toMatchObject({ code: 'CLUB_FULL', title: 'This club is currently full' });
    for (let i = 0; i < 9; i++) {
      const u = (await one<{ id: string }>(`insert into users(email, first_name, last_name) values ($1,'Try','Er') returning id`, [`t${i}@keys.test`]))!;
      await q(`insert into club_join_attempts(club_id, user_id, attempted_at) values ($1,$2,now())`, [r.id, u.id]);
    }
    await call('POST', `/clubs/${r.id}/join`, { token: dan });
    expect(await notes(cara)).toContain('club_join_attempts');
    // CLB-09.1: the limit cannot drop below the member count.
    expect((await call('PATCH', `/clubs/${r.id}`, { token: cara, body: { memberLimit: 10 } })).status).toBe(200);
    await call('PATCH', `/clubs/${r.id}`, { token: cara, body: { memberLimit: 11 } });
    await call('POST', `/clubs/${r.id}/join`, { token: dan });
    expect(await notes(cara)).toContain('club_full');
  });
});

describe('CLB-09 / CLB-10 manage', () => {
  it('admins edit all but the name and remove members but not admins; President manages admins', async () => {
    await call('POST', `/clubs/${blues.id}/join`, { token: ben });
    await call('POST', `/clubs/${blues.id}/join`, { token: cara });
    expect((await call('POST', `/clubs/${blues.id}/admins/${benId}`, { token: cara })).body.error.code).toBe('NOT_ALLOWED');
    expect((await call('POST', `/clubs/${blues.id}/admins/${benId}`, { token: pres })).body.message).toBe('Ben Ade is now an admin');
    expect(await notes(ben)).toContain('club_role');
    expect((await call('GET', `/chats/${blues.chatId}`, { token: ben })).body.myRole).toBe('admin');
    expect((await call('PATCH', `/clubs/${blues.id}`, { token: ben, body: { name: 'Reds' } })).body.error.code).toBe('NAME_PRESIDENT_ONLY');
    expect((await call('PATCH', `/clubs/${blues.id}`, { token: ben, body: { description: 'All blues welcome' } })).body.message).toBe('Changes saved!');
    const m = (await call('GET', `/clubs/${blues.id}/members`, { token: dan })).body;
    expect(m.members.map((x: any) => x.roleLabel)).toEqual(['Club president', 'Admin', 'Member']);
    expect(m.countLabel).toBe('3/10 members');
    expect((await call('DELETE', `/clubs/${blues.id}/members/${caraId}`, { token: ben })).body.message).toBe('You removed Cara Lee');
    expect(await notes(cara)).toContain('club_removed');
    expect((await call('DELETE', `/clubs/${blues.id}/admins/${benId}`, { token: pres })).body.message).toBe('Ben Ade is no longer an admin');
  });
});

describe('CLB-13 announcements', () => {
  it('admins post; members-only hidden from visitors; likes only; feed excludes them; President deletes', async () => {
    expect((await call('POST', '/posts', { token: ben, body: { text: 'Hi', clubId: blues.id } })).body.error.code).toBe('NOT_CLUB_ADMIN');
    const all = (await call('POST', '/posts', { token: pres, body: { text: 'Match day Saturday!', clubId: blues.id, audience: 'all' } })).body;
    expect(all.message).toBe('Your post has been sent');
    const mem = (await call('POST', '/posts', { token: pres, body: { text: 'Members drinks', clubId: blues.id, audience: 'members' } })).body.post;
    expect(await notes(ben)).toContain('club_announcement');
    const visitor = (await call('GET', `/clubs/${blues.id}/announcements`, { token: dan })).body;
    expect(visitor.announcements.map((p: any) => p.text)).toEqual(['Match day Saturday!']);
    expect(visitor.membersOnlyHidden).toBe(true);
    expect((await call('GET', `/posts/${mem.id}`, { token: dan })).status).toBe(404);
    expect((await call('GET', `/clubs/${blues.id}/announcements`, { token: ben })).body.announcements).toHaveLength(2);
    expect((await call('POST', `/posts/${all.post.id}/comments`, { token: ben, body: { text: 'Yes!' } })).body.error.code).toBe('NO_COMMENTS');
    expect((await call('POST', `/posts/${all.post.id}/like`, { token: ben })).body.liked).toBe(true);
    expect((await call('GET', '/feed', { token: ben })).body.posts.some((p: any) => p.club)).toBe(false);
    expect((await call('GET', '/clubs/home', { token: ben })).body.announcements.map((p: any) => p.club.name)).toContain('Blues United FC Fans');
    expect((await call('DELETE', `/posts/${mem.id}`, { token: pres })).status).toBe(200);
  });
});

describe('CLB-14 club events', () => {
  it('owners and admins create club events for everyone or members only', async () => {
    expect((await call('GET', '/events/create-check?category=club', { token: pres })).body.clubs.map((c: any) => c.name)).toContain('Blues United FC Fans');
    const pid = await placeId(pres, '1 Maple Road');
    const d = await call('POST', '/events', { token: pres, body: { ...(await eventBasics(pres)), category: 'club', clubId: blues.id, audience: 'members', title: 'Watch party', startAt: inDays(5), endAt: inDays(5, 21), format: 'physical', placeId: pid, tags: ['Social'] } });
    expect(d.status).toBe(200);
    await call('POST', `/events/${d.body.event.id}/launch`, { token: pres });
    expect(await notes(ben)).toContain('club_event');
    expect((await call('GET', `/events/${d.body.event.id}`, { token: dan })).status).toBe(404);
    expect((await call('GET', `/clubs/${blues.id}/events`, { token: ben })).body.events.map((e: any) => e.title)).toEqual(['Watch party']);
    expect((await call('GET', `/clubs/${blues.id}/events`, { token: dan })).body.events).toEqual([]);
  });
});

describe('CLB-11 transfer ownership', () => {
  it('offer, awaiting, accept: new President, old one leaves, community-wide announcement', async () => {
    expect((await call('POST', `/clubs/${blues.id}/transfer`, { token: pres, body: { userId: danId } })).body.error.code).toBe('NOT_MEMBER');
    const t = (await call('POST', `/clubs/${blues.id}/transfer`, { token: pres, body: { userId: benId } })).body;
    expect(t.message).toBe('Ownership offer sent');
    expect((await call('GET', `/clubs/${blues.id}`, { token: pres })).body.club.transfer.status).toBe('Awaiting response');
    expect(await notes(ben)).toContain('club_transfer_offer');
    // CLB-11.4: a President cannot leave the community or deactivate.
    expect((await call('GET', '/me/exit-check?reason=move', { token: pres })).body.blockers.map((b: any) => b.code)).toContain('CLUB_PRESIDENT');
    expect((await call('POST', `/club-transfers/${t.transferId}/accept`, { token: ben })).body.message).toBe('Club ownership transferred.');
    const c = (await call('GET', `/clubs/${blues.id}`, { token: ben })).body.club;
    expect(c.myRole).toBe('president');
    expect((await call('GET', `/clubs/${blues.id}`, { token: pres })).body.club.isMember).toBe(false);
    // Club events of the old President pass on.
    expect((await one<any>(`select host_id from events where title = 'Watch party'`))!.host_id).toBe(benId);
    const ann = (await call('GET', `/clubs/${blues.id}/announcements`, { token: dan })).body.announcements;
    expect(ann[0].text).toBe('New President: Ben Ade is the new President of Blues United FC Fans.');
  });

  it('declining keeps the member and tells the President', async () => {
    await call('POST', `/clubs/${blues.id}/join`, { token: cara });
    const t = (await call('POST', `/clubs/${blues.id}/transfer`, { token: ben, body: { userId: caraId } })).body;
    expect((await call('POST', `/club-transfers/${t.transferId}/decline`, { token: cara })).body.message).toBe('You will remain a member of the club.');
    expect(await notes(ben)).toContain('club_transfer_declined');
  });
});

describe('CLB-12 close', () => {
  it('closes in 48 hours; then events are cancelled and members told', async () => {
    expect((await call('POST', `/clubs/${blues.id}/delete`, { token: cara })).body.error.code).toBe('NOT_ALLOWED');
    const r = (await call('POST', `/clubs/${blues.id}/delete`, { token: ben })).body;
    expect(r).toMatchObject({ title: 'Club deleted', message: 'Your club Blues United FC Fans would be closed permanently in 48hours.' });
    expect((await call('GET', `/clubs/${blues.id}`, { token: cara })).body.club.status).toBe('closing');
    expect(await notes(cara)).toContain('club_closing');
    clock.advance(CLOSE + HOUR);
    await clubJobs();
    expect((await call('GET', `/clubs/${blues.id}`, { token: cara })).status).toBe(404);
    expect((await one<any>(`select status from events where title = 'Watch party'`))!.status).toBe('cancelled');
    expect(await notes(cara)).toContain('club_closed');
    // The name is free again.
    expect((await club(dan, 'Blues United FC Fans')).status).toBe(200);
    clock.reset();
  });
});
const CLOSE = 48 * HOUR;

describe('CLB-16.2 milestones', () => {
  it('members hear once when the club reaches 50', async () => {
    const r = (await club(dan, 'Big Club', { memberLimit: 100 })).body.club;
    for (let i = 0; i < 48; i++) {
      const u = (await one<{ id: string }>(`insert into users(email, first_name, last_name) values ($1,'M','Em') returning id`, [`m${i}@keys.test`]))!;
      await q(`insert into club_members(club_id, user_id) values ($1,$2)`, [r.id, u.id]);
    }
    await call('POST', `/clubs/${r.id}/join`, { token: cara });
    expect((await notes(cara)).filter((t: string) => t === 'club_milestone')).toHaveLength(1);
    expect((await one<any>('select milestones from clubs where id = $1', [r.id]))!.milestones).toEqual([50]);
  });
});
