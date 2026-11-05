import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { q } from '../src/db/pool.js';
import { clock, DAY, SECOND } from '../src/lib/clock.js';
import { call, finishProfile, joinStreet, lastCode, me, pioneerStreet, PNG, seat, setup, signUp, teardown, upload, withAddress } from './helpers.js';

let amy: string; let ben: string; let cat: string; let outsider: string;
let amyId: string; let benId: string; let catId: string; let outsiderId: string;

beforeAll(async () => {
  await setup();
  amy = (await pioneerStreet('amy@keys.test', '1 Maple Road')).token;
  ben = await joinStreet('ben@keys.test', '2 Maple Road', 'Ben', 'Ade');
  cat = await joinStreet('cat@keys.test', '3 Maple Road', 'Cat', 'Obi');
  outsider = (await pioneerStreet('out@keys.test', '1 Oak Avenue')).token;
  [amyId, benId, catId, outsiderId] = await Promise.all([amy, ben, cat, outsider].map(async (t) => (await me(t)).id));
});
afterAll(teardown);

describe('PRF-02 / PRF-03 other profiles', () => {
  it('shows name, bio, community, joined date, verification and committee role', async () => {
    await seat(amy, 'Committee Chair');
    const r = await call('GET', `/users/${amyId}`, { token: ben });
    expect(r.body).toMatchObject({ name: 'Amy Duncan', community: 'Maple Road', verified: false, role: 'Committee Chair', isMe: false });
    expect(r.body.joinedAt).toBeTruthy();
    expect(r.body.shareLink).toBe(`https://keys.app/profile/${amyId}`);
  });
  it('PRF-03.3 someone outside the community gets not-available', async () => {
    const r = await call('GET', `/users/${amyId}`, { token: outsider });
    expect(r.status).toBe(404);
    expect(r.body.error.code).toBe('NOT_AVAILABLE');
  });
});

describe('PRF-04 mute', () => {
  it('mutes for 30 days, hides posts, then ends by itself', async () => {
    await call('POST', '/posts', { token: cat, body: { text: 'Cat here' } });
    const r = await call('POST', `/users/${catId}/mute`, { token: ben });
    expect(r.body.message).toBe('You muted Cat Obi');
    expect((await call('GET', `/users/${catId}`, { token: ben })).body.isMuted).toBe(true);
    let feed = (await call('GET', '/feed', { token: ben })).body.posts;
    expect(feed.some((p: any) => p.author.id === catId)).toBe(false);
    expect((await call('GET', '/me/muted', { token: ben })).body.accounts.map((a: any) => a.name)).toEqual(['Cat Obi']);
    clock.advance(30 * DAY + SECOND);
    feed = (await call('GET', '/feed', { token: ben })).body.posts;
    expect(feed.some((p: any) => p.author.id === catId)).toBe(true);
    expect((await call('GET', '/me/muted', { token: ben })).body.accounts).toEqual([]);
  });
  it('PRF-04.4 unmute', async () => {
    await call('POST', `/users/${catId}/mute`, { token: ben });
    const r = await call('DELETE', `/users/${catId}/mute`, { token: ben });
    expect(r.body.message).toBe('You unmuted Cat Obi');
  });
});

describe('PRF-05 block (two-way hide)', () => {
  it('hides posts both ways, the blocked person cannot open the profile, the blocker sees Unblock', async () => {
    const r = await call('POST', `/users/${catId}/block`, { token: amy });
    expect(r.body.message).toBe('You blocked Cat Obi');
    expect((await call('GET', '/feed', { token: amy })).body.posts.some((p: any) => p.author.id === catId)).toBe(false);
    await call('POST', '/posts', { token: amy, body: { text: 'Amy here' } });
    expect((await call('GET', '/feed', { token: cat })).body.posts.some((p: any) => p.author.id === amyId)).toBe(false);
    expect((await call('GET', `/users/${amyId}`, { token: cat })).status).toBe(404);
    expect((await call('GET', `/users/${catId}`, { token: amy })).body.isBlocked).toBe(true);
    // FED-03.4: not in @ suggestions either way.
    expect((await call('GET', '/members/search?q=', { token: amy })).body.members.map((m: any) => m.name)).toEqual(['Ben Ade']);
    expect((await call('GET', '/members/search?q=', { token: cat })).body.members.map((m: any) => m.name)).toEqual(['Ben Ade']);
    expect((await call('GET', '/me/blocked', { token: amy })).body.accounts[0].name).toBe('Cat Obi');
    const un = await call('DELETE', `/users/${catId}/block`, { token: amy });
    expect(un.body.message).toBe('You have unblocked Cat Obi');
    expect((await call('GET', `/users/${amyId}`, { token: cat })).status).toBe(200);
  });
});

describe('PRF-06 report a resident', () => {
  it('goes to the queue', async () => {
    const r = await call('POST', '/reports', { token: ben, body: { itemType: 'user', itemId: catId, reason: 'Impersonation' } });
    expect(r.body.ok).toBe(true);
  });
});

describe('PRF-08 / PRF-09 photo and bio', () => {
  it('replaces the photo and saves a bio up to 160', async () => {
    const m = await upload('/media?kind=photo', ben, { name: 'n.png', mime: 'image/png', data: PNG });
    const r = await call('PUT', '/me/photo', { token: ben, body: { mediaId: m.body.id } });
    expect(r.body.message).toBe('Picture changed successfully');
    expect((await call('PUT', '/me/bio', { token: ben, body: { bio: 'x'.repeat(161) } })).status).toBe(400);
    expect((await call('PUT', '/me/bio', { token: ben, body: { bio: 'Gardener' } })).body.message).toBe('Bio changed successfully');
  });
});

describe('PRF-10 change email', () => {
  it('password, new email, code, swap; in-use email is refused', async () => {
    expect((await call('POST', '/me/email/password', { token: ben, body: { password: 'nope' } })).body.error.message).toBe('Incorrect password');
    const inUse = await call('POST', '/me/email/start', { token: ben, body: { password: 'Keys2026!', newEmail: 'amy@keys.test' } });
    expect(inUse.body.error.code).toBe('EMAIL_IN_USE');
    expect(await q(`select 1 from email_outbox where to_email = 'amy@keys.test' and template = 'change_email_code'`)).toHaveLength(0);
    await call('POST', '/me/email/start', { token: ben, body: { password: 'Keys2026!', newEmail: 'ben.new@keys.test' } });
    const code = await lastCode('ben.new@keys.test');
    const wrong = await call('POST', '/me/email/verify', { token: ben, body: { newEmail: 'ben.new@keys.test', code: code === '000000' ? '111111' : '000000' } });
    expect(wrong.body.error.message).toBe('Invalid verification code. Please check and try again');
    const ok = await call('POST', '/me/email/verify', { token: ben, body: { newEmail: 'ben.new@keys.test', code } });
    expect(ok.body.message).toBe('Your email has been verified.');
    expect((await me(ben)).email).toBe('ben.new@keys.test');
  });
  it('PRF-10.7 social account without a password must add one first', async () => {
    const s = await call('POST', '/auth/social', { body: { provider: 'google', idToken: 'mock:g9:soc@keys.test:So:Cial' } });
    const r = await call('POST', '/me/email/password', { token: s.body.token, body: { password: 'x' } });
    expect(r.body.error).toMatchObject({ code: 'PASSWORD_REQUIRED', message: 'Add a password first' });
    // PRF-16: create a password with an email code.
    await call('POST', '/me/password/create/start', { token: s.body.token });
    const code = await lastCode('soc@keys.test');
    const c = await call('POST', '/me/password/create', { token: s.body.token, body: { code, password: 'Keys2026!', confirmPassword: 'Keys2026!' } });
    expect(c.body.message).toBe('Your password has been created successfully');
    expect((await call('POST', '/auth/login', { body: { email: 'soc@keys.test', password: 'Keys2026!' } })).body.token).toBeTruthy();
  });
});

describe('PRF-15 change password', () => {
  it('checks the current password, the match, and signs out other sessions', async () => {
    const t = await signUp('pw@keys.test');
    const other = (await call('POST', '/auth/login', { body: { email: 'pw@keys.test', password: 'Keys2026!' } })).body.token;
    expect((await call('PUT', '/me/password', { token: t, body: { current: 'bad', password: 'New2026!x', confirmPassword: 'New2026!x' } })).body.error.message).toBe('Incorrect password');
    expect((await call('PUT', '/me/password', { token: t, body: { current: 'Keys2026!', password: 'New2026!x', confirmPassword: 'New2026!y' } })).body.error.message).toBe('Passwords do not match');
    const ok = await call('PUT', '/me/password', { token: t, body: { current: 'Keys2026!', password: 'New2026!x', confirmPassword: 'New2026!x' } });
    expect(ok.body.message).toBe('Your password has been changed successfully');
    expect((await call('GET', '/me', { token: t })).status).toBe(200);
    expect((await call('GET', '/me', { token: other })).status).toBe(401);
  });
});

describe('PRF-14 notification settings', () => {
  it('newsletter starts off; toggles apply at once', async () => {
    expect((await call('GET', '/me/notification-prefs', { token: ben })).body.prefs).toMatchObject({ newsletter: false, likes: true });
    await call('PUT', '/me/notification-prefs', { token: ben, body: { likes: false } });
    const p = (await call('POST', '/posts', { token: ben, body: { text: 'Ben post' } })).body.post;
    await call('POST', `/posts/${p.id}/like`, { token: amy });
    expect((await call('GET', '/notifications', { token: ben })).body.notifications.filter((n: any) => n.type === 'post_like')).toHaveLength(0);
  });
});

describe('PRF-11 change home address', () => {
  it('warns about the seat, leaves the community, resets verification, skips profile setup', async () => {
    const t = await joinStreet('mover@keys.test', '9 Maple Road', 'Mo', 'Ver');
    await call('POST', '/verification/check', { token: t, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_4242' } });
    await seat(t, 'Treasurer');
    const check = await call('GET', '/me/exit-check?reason=move', { token: t });
    expect(check.body.blockers).toEqual([]);
    expect(check.body.warnings.map((w: any) => w.code)).toEqual(['COMMITTEE_SEAT', 'UNVERIFIED', 'LEAVE_COMMUNITY']);
    const mv = await call('POST', '/me/move', { token: t });
    expect(mv.body.onboardingStep).toBe('address');
    const m = await me(t);
    expect(m).toMatchObject({ verificationStatus: 'unverified', community: null });
    expect(await q(`select 1 from board_seats where role = 'Treasurer' and occupant_id is not null`)).toHaveLength(0);
    const s = await call('GET', '/addresses/autocomplete?q=4%20Birch', { token: t });
    const a = await call('POST', '/onboarding/address', { token: t, body: { placeId: s.body.suggestions[0].placeId } });
    expect(a.body.match.kind).toBe('none');
    await call('POST', '/onboarding/street', { token: t });
    const h = await call('POST', '/onboarding/home-type', { token: t, body: { type: 'house' } });
    expect(h.body.onboardingStep).toBe('complete');
    // PRF-11.4: welcome prompt shows again in the new community.
    expect(await me(t)).toMatchObject({ showWelcomePrompt: true, community: { name: 'Birch Lane' } });
  });
});

describe('PRF-18 deactivate', () => {
  it('needs the password, blocks committee seat holders, once per 7 days', async () => {
    const t = await joinStreet('deact@keys.test', '11 Maple Road', 'De', 'Act');
    expect((await call('POST', '/me/deactivate', { token: t, body: { password: 'bad' } })).body.error.message).toBe('Incorrect password');
    await seat(t, 'Secretary');
    const blocked = await call('POST', '/me/deactivate', { token: t, body: { password: 'Keys2026!' } });
    expect(blocked.body.error.code).toBe('EXIT_BLOCKED');
    await q(`update board_seats set occupant_id = null where role = 'Secretary'`);
    const ok = await call('POST', '/me/deactivate', { token: t, body: { password: 'Keys2026!' } });
    expect(ok.body.ok).toBe(true);
    expect((await call('GET', '/me', { token: t })).status).toBe(401);
    const back = (await call('POST', '/auth/login', { body: { email: 'deact@keys.test', password: 'Keys2026!' } })).body;
    expect(back.reactivated).toBe(true);
    const again = await call('POST', '/me/deactivate', { token: back.token, body: { password: 'Keys2026!' } });
    expect(again.body.error.message).toBe('You cannot deactivate your account for the next 7 days');
  });
});

it('PRF-17.2 push tokens are stored and removed on deactivation', async () => {
  const t = await withAddress('push@keys.test', '12 Maple Road');
  await call('POST', '/me/push-token', { token: t.token, body: { token: 'fcm-token-123456', platform: 'ios' } });
  expect(await q(`select 1 from push_tokens where token = 'fcm-token-123456'`)).toHaveLength(1);
  await call('POST', '/auth/logout', { token: t.token, body: { pushToken: 'fcm-token-123456' } });
  expect(await q(`select 1 from push_tokens where token = 'fcm-token-123456'`)).toHaveLength(0);
  void finishProfile;
});
