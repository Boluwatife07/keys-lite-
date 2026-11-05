import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { q } from '../src/db/pool.js';
import { call, finishProfile, PNG, pioneerStreet, placeId, setup, signUp, teardown, upload, withAddress } from './helpers.js';

beforeAll(setup);
afterAll(teardown);

describe('ONB-11 home address', () => {
  it('ONB-11.1 suggestions come from the address provider', async () => {
    const t = await signUp('a1@keys.test');
    const r = await call('GET', '/addresses/autocomplete?q=12%20Map', { token: t });
    expect(r.body.suggestions[0]).toMatchObject({ primary: '12 Maple Road', secondary: 'London SE1 7AA' });
  });
  it('ONB-11.3 an address that does not exist is refused', async () => {
    const t = await signUp('a2@keys.test');
    expect((await call('GET', '/addresses/autocomplete?q=nowhere', { token: t })).body.suggestions).toEqual([]);
    const r = await call('POST', '/onboarding/address', { token: t, body: { placeId: 'mock|999|1|' } });
    expect(r.body.error.message).toBe('Address not found. Please use a valid address.');
  });
});

describe('ONB-13 / ONB-15 matching and pioneering a street', () => {
  it('ONB-13.3 no community -> "Your area isn\'t on Keys yet"; ONB-15.2 pioneer creates it', async () => {
    const { token, match } = await withAddress('p1@keys.test', '3 Cedar Close');
    expect(match.kind).toBe('none');
    const s = await call('POST', '/onboarding/street', { token });
    expect(s.body.community).toMatchObject({ type: 'street', typeLabel: 'STREET COMMUNITY', name: 'Cedar Close' });
    expect(s.body.onboardingStep).toBe('home_type');
    // ONB-16.1 / ONB-21.1: the pioneer sees "[Name] is live."
    const h = await call('POST', '/onboarding/home-type', { token, body: { type: 'house', subtype: 'Bungalow' } });
    expect(h.body).toMatchObject({ screen: 'live', name: 'Cedar Close', onboardingStep: 'profile' });
  });
  it('ONB-13.1 next resident on the street sees one card; ONB-13.4 counts hidden under 500', async () => {
    const { token, match } = await withAddress('p2@keys.test', '9 Cedar Close');
    expect(match.kind).toBe('single');
    expect(match.communities[0].name).toBe('Cedar Close');
    expect(match.communities[0]).not.toHaveProperty('residents');
    expect(match.communities[0]).not.toHaveProperty('committeeMembers');
    await call('POST', '/onboarding/join', { token, body: { communityId: match.communities[0].id } });
    // ONB-21.2: joiners see "Welcome to [Community]".
    const h = await call('POST', '/onboarding/home-type', { token, body: { type: 'house' } });
    expect(h.body).toMatchObject({ screen: 'welcome', name: 'Cedar Close' });
  });
  it('ONB-13.4 counts show at 500+ residents', async () => {
    const c = (await q(`select id from communities where name = 'Cedar Close'`))[0];
    await q(
      `with u as (insert into users(email, first_name, last_name) select 'bulk'||g||'@keys.test','B','C' from generate_series(1,498) g returning id)
       insert into memberships(user_id, community_id, level) select id, $1, 'house' from u`, [c.id],
    );
    const { match } = await withAddress('p3@keys.test', '20 Cedar Close');
    expect(match.communities[0]).toMatchObject({ residents: 500, committeeMembers: 0 });
  });
  it('ONB-15.3 two pioneers at the same time: the second is sent to join', async () => {
    const a = await withAddress('r1@keys.test', '1 Ash Grove');
    const b = await withAddress('r2@keys.test', '2 Ash Grove');
    const [x, y] = await Promise.all([call('POST', '/onboarding/street', { token: a.token }), call('POST', '/onboarding/street', { token: b.token })]);
    const statuses = [x.status, y.status].sort();
    expect(statuses).toEqual([200, 409]);
    const loser = x.status === 409 ? x : y;
    expect(loser.body.error.code).toBe('STREET_COMMUNITY_EXISTS');
    expect(loser.body.error.community.name).toBe('Ash Grove');
  });
  it('cannot join a community that does not cover your street', async () => {
    const other = (await q(`select id from communities where name = 'Cedar Close'`))[0];
    const { token } = await withAddress('r3@keys.test', '5 Birch Lane');
    const r = await call('POST', '/onboarding/join', { token, body: { communityId: other.id } });
    expect(r.body.error.code).toBe('NOT_ELIGIBLE');
  });
});

describe('ONB-18 - ONB-20 developments', () => {
  it('ONB-20.1 lists only directly connected streets', async () => {
    const { token } = await withAddress('d1@keys.test', '4 Elm Street');
    const r = await call('GET', '/onboarding/development/connected-streets', { token });
    expect(r.body.streets.map((s: any) => s.name)).toEqual(['Oak Avenue', 'Hazel Drive', 'Rowan Court', 'Poplar Place', 'Linden Mews', 'Chestnut Row']);
  });
  it('ONB-20.2 at most 5 streets; non-connected streets refused', async () => {
    const { token } = await withAddress('d2@keys.test', '6 Elm Street');
    const all = (await call('GET', '/onboarding/development/connected-streets', { token })).body.streets.map((s: any) => s.key);
    const six = await call('POST', '/onboarding/development', { token, body: { name: 'Elm Park', streetKeys: all } });
    expect(six.body.error.message).toBe('Maximum of 5 streets can be linked');
    const bad = await call('POST', '/onboarding/development', { token, body: { name: 'Elm Park', streetKeys: ['harbour street|brighton'] } });
    expect(bad.body.error.code).toBe('STREET_NOT_CONNECTED');
  });
  it('ONB-20.4 / ONB-13.2 / ONB-13.5 a linked street keeps its community and new residents see both', async () => {
    await pioneerStreet('d3@keys.test', '1 Maple Road');
    const { token } = await withAddress('d4@keys.test', '2 Oak Avenue');
    const streets = (await call('GET', '/onboarding/development/connected-streets', { token })).body.streets;
    const maple = streets.find((s: any) => s.name === 'Maple Road');
    expect(maple.hasStreetCommunity).toBe(true);
    const dev = await call('POST', '/onboarding/development', { token, body: { name: 'New Keys Capital', streetKeys: [maple.key] } });
    expect(dev.body.community).toMatchObject({ type: 'development', typeLabel: 'DEVELOPMENT', name: 'New Keys Capital' });
    const later = await withAddress('d5@keys.test', '40 Maple Road');
    expect(later.match.kind).toBe('multiple');
    expect(later.match.communities.map((c: any) => c.name)).toEqual(['Maple Road', 'New Keys Capital']);
  });
  it('ONB-20.3 skipping creates the development with only your street', async () => {
    const { token } = await withAddress('d6@keys.test', '3 Willow Way');
    const dev = await call('POST', '/onboarding/development', { token, body: { name: 'Willow Gardens' } });
    const streets = await q(`select s.name from street_links l join streets s on s.id = l.street_id where l.community_id = $1`, [dev.body.community.id]);
    expect(streets.map((s) => s.name)).toEqual(['Willow Way']);
  });
  it('ONB-18.2 / ONB-19.1 similar names within 10 km, case insensitive, with distance', async () => {
    const { token } = await withAddress('d7@keys.test', '8 Hazel Drive');
    const r = await call('POST', '/onboarding/development/check', { token, body: { name: 'new keys' } });
    expect(r.body.similar).toHaveLength(1);
    expect(r.body.similar[0]).toMatchObject({ name: 'New Keys Capital', residents: 1, committeeMembers: 0 });
    expect(typeof r.body.similar[0].distanceKm).toBe('number');
    const far = await withAddress('d8@keys.test', '8 Harbour Street');
    const none = await call('POST', '/onboarding/development/check', { token: far.token, body: { name: 'New Keys Capital' } });
    expect(none.body.similar).toEqual([]);
  });
  it('ONB-19.2 / ONB-19.3 joining an existing development adds your street at once', async () => {
    const { token } = await withAddress('d9@keys.test', '8 Rowan Court');
    const sim = (await call('POST', '/onboarding/development/check', { token, body: { name: 'New Keys Capital' } })).body.similar[0];
    const preview = await call('GET', `/onboarding/development/${sim.id}/join-preview`, { token });
    expect(preview.body).toMatchObject({ yourStreet: 'Rowan Court', streets: ['Oak Avenue', 'Maple Road'] });
    const j = await call('POST', `/onboarding/development/${sim.id}/join`, { token });
    expect(j.body.onboardingStep).toBe('home_type');
    const next = await withAddress('d10@keys.test', '9 Rowan Court');
    expect(next.match.communities.map((c: any) => c.name)).toEqual(['New Keys Capital']);
  });
});

describe('ONB-16 / ONB-17 buildings', () => {
  let streetCommunity: any;
  it('ONB-17.2 first resident names the building and sees "[Building] is live"', async () => {
    const p = await pioneerStreet('b0@keys.test', '1 Linden Mews');
    streetCommunity = p.community;
    const { token, match } = await withAddress('b1@keys.test', 'Flat 2, 30 Linden Mews');
    await call('POST', '/onboarding/join', { token, body: { communityId: match.communities[0].id } });
    const h = await call('POST', '/onboarding/home-type', { token, body: { type: 'building', subtype: 'Apartment' } });
    expect(h.body).toMatchObject({ next: 'building', buildings: [] });
    const empty = await call('POST', '/onboarding/building', { token, body: { name: '  ' } });
    expect(empty.status).toBe(400);
    const b = await call('POST', '/onboarding/building', { token, body: { name: 'Linden House' } });
    expect(b.body).toMatchObject({ screen: 'live', name: 'Linden House', onboardingStep: 'profile' });
  });
  it('ONB-17.3 duplicate name on the street', async () => {
    const { token, match } = await withAddress('b2@keys.test', '50 Linden Mews');
    await call('POST', '/onboarding/join', { token, body: { communityId: match.communities[0].id } });
    await call('POST', '/onboarding/home-type', { token, body: { type: 'building' } });
    const r = await call('POST', '/onboarding/building', { token, body: { name: 'linden house' } });
    expect(r.body.error.message).toBe('"linden house" already exists on this street. Choose a different name.');
  });
  it('ONB-17.4 existing buildings are listed with resident counts and can be joined', async () => {
    const { token, match } = await withAddress('b3@keys.test', 'Flat 9, 30 Linden Mews');
    await call('POST', '/onboarding/join', { token, body: { communityId: match.communities[0].id } });
    const h = await call('POST', '/onboarding/home-type', { token, body: { type: 'building' } });
    expect(h.body.buildings).toEqual([{ id: expect.any(String), name: 'Linden House', residents: 1 }]);
    const j = await call('POST', `/onboarding/building/${h.body.buildings[0].id}/join`, { token });
    expect(j.body).toMatchObject({ screen: 'welcome', name: streetCommunity.name });
  });
});

describe('ONB-12 community code', () => {
  async function codeOf(name: string) {
    return (await q(`select code from communities where name = $1`, [name]))[0].code as string;
  }
  it('ONB-12.2 unknown code', async () => {
    const t = await signUp('k1@keys.test');
    const r = await call('POST', '/onboarding/address', { token: t, body: { placeId: await placeId(t, '1 Poplar Place'), communityCode: 'ZZZZZZ' } });
    expect(r.body.error.message).toBe('Invalid community code. Please check and try again.');
  });
  it('ONB-12.3 valid code and address inside', async () => {
    const { match } = await withAddress('k2@keys.test', '77 Maple Road', await codeOf('New Keys Capital'));
    expect(match.kind).toBe('code_match');
    expect(match.communities[0].name).toBe('New Keys Capital');
  });
  it('ONB-12.4 valid code but address outside', async () => {
    const { match } = await withAddress('k3@keys.test', '5 Chestnut Row', await codeOf('Cedar Close'));
    expect(match.kind).toBe('code_ineligible');
    // "Proceed with my address" re-runs matching without the code.
    const t = (await call('POST', '/auth/login', { body: { email: 'k3@keys.test', password: 'Keys2026!' } })).body.token;
    expect((await call('POST', '/onboarding/match', { token: t, body: {} })).body.match.kind).toBe('none');
  });
  it('ONB-12.5 building code, same street, different building -> parent community', async () => {
    const { match } = await withAddress('k4@keys.test', '12 Linden Mews', await codeOf('Linden House'));
    expect(match.kind).toBe('code_parent');
    expect(match.communities[0].name).toBe('Linden Mews');
  });
  it('building code, same building -> joins the building directly', async () => {
    const { token, match } = await withAddress('k5@keys.test', 'Flat 4, 30 Linden Mews', await codeOf('Linden House'));
    expect(match.kind).toBe('code_match');
    expect(match.communities[0]).toMatchObject({ type: 'building', name: 'Linden House', parentName: 'Linden Mews' });
    const j = await call('POST', '/onboarding/join', { token, body: { communityId: match.communities[0].id } });
    expect(j.body).toMatchObject({ onboardingStep: 'profile', screen: 'welcome', name: 'Linden Mews' });
  });
});

describe('ONB-22 profile, ONB-24 invite, ONB-25 welcome, ONB-26 resume, LRN-01', () => {
  it('runs the end of onboarding', async () => {
    const { token } = await withAddress('e1@keys.test', '10 Chestnut Row');
    // ONB-26.1: logging in again resumes at the first unfinished step.
    expect((await call('GET', '/me', { token })).body.onboardingStep).toBe('community');
    await call('POST', '/onboarding/street', { token });
    expect((await call('GET', '/me', { token })).body.onboardingStep).toBe('home_type');
    await call('POST', '/onboarding/home-type', { token, body: { type: 'house' } });
    expect((await call('GET', '/me', { token })).body.onboardingStep).toBe('profile');

    // ONB-22.1 photo required, ONB-22.5 bio <= 160, ONB-22.6 safety ack required.
    const noPhoto = await call('POST', '/onboarding/profile', { token, body: { safetyAccepted: true } });
    expect(noPhoto.status).toBe(400);
    const photo = await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: PNG });
    const longBio = await call('POST', '/onboarding/profile', { token, body: { photoMediaId: photo.body.id, bio: 'x'.repeat(161), safetyAccepted: true } });
    expect(longBio.body.error.message).toBe('Bio can be up to 160 characters');
    const noAck = await call('POST', '/onboarding/profile', { token, body: { photoMediaId: photo.body.id, safetyAccepted: false } });
    expect(noAck.status).toBe(400);
    // ONB-22.4: preset bio when left as is.
    const ok = await call('POST', '/onboarding/profile', { token, body: { photoMediaId: photo.body.id, safetyAccepted: true } });
    expect(ok.body.onboardingStep).toBe('complete');

    const me = (await call('GET', '/me', { token })).body;
    expect(me.bio).toBe((await call('GET', '/onboarding/defaults')).body.bio);
    // ONB-23.2 skipped verification -> unverified; ONB-26.2 goes to Home.
    expect(me).toMatchObject({ onboardingStep: 'complete', verificationStatus: 'unverified', showWelcomePrompt: true, showLearning: true });

    // ONB-24.1 / 24.2 invite link and message.
    const inv = (await call('GET', '/communities/mine/invite', { token })).body;
    expect(inv.link).toBe(`https://keys.app/c/${me.community.code}`);
    expect(inv.message).toContain("Hey! I'm using the Keys app to stay connected to our community. Download it and join us!");

    // ONB-24.4 link resolves to the community; signed-in member sees already_member.
    const by = await call('GET', `/communities/by-code/${me.community.code}`, { token });
    expect(by.body).toMatchObject({ community: { name: 'Chestnut Row' }, eligibility: { kind: 'already_member' } });
    // App not installed: the share page sends the visitor to the store.
    const page = await call('GET', `/l/c/${me.community.code}`);
    expect(page.body).toContain('Join Chestnut Row on Keys');
    expect(page.body).toContain('apps.apple.com');

    // ONB-25 welcome prompt once.
    const wp = await call('GET', '/onboarding/welcome-post', { token });
    expect(wp.body.audience).toBe('everyone');
    await call('POST', '/onboarding/welcome-prompt/done', { token });
    // LRN-01.4 skip -> not shown again on any device.
    await call('POST', '/learning/done', { token, body: { outcome: 'skipped' } });
    const other = (await call('POST', '/auth/login', { body: { email: 'e1@keys.test', password: 'Keys2026!' } })).body.token;
    expect((await call('GET', '/me', { token: other })).body).toMatchObject({ showWelcomePrompt: false, showLearning: false });

    // Address cannot be changed through onboarding once complete.
    const again = await call('POST', '/onboarding/address', { token, body: { placeId: 'mock|0|1|' } });
    expect(again.body.error.code).toBe('ONBOARDING_DONE');
  });
  it('ONB-22 profile cannot be skipped ahead of earlier steps', async () => {
    const t = await signUp('e2@keys.test');
    const r = await finishProfile(t);
    expect(r.body.error.code).toBe('STEP_ORDER');
  });
});
