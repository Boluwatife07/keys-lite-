import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { clock, DAY, SECOND } from '../src/lib/clock.js';
import { q } from '../src/db/pool.js';
import { call, lastCode, setup, signUp, teardown } from './helpers.js';

beforeAll(setup);
afterAll(teardown);

describe('ONB-05 email entry', () => {
  it('ONB-05.4 rejects a badly formatted email and sends no code', async () => {
    const r = await call('POST', '/auth/email/start', { body: { email: 'amy@' } });
    expect(r.status).toBe(400);
    expect(r.body.error.message).toBe('Enter a valid email address');
  });
  it('ONB-05.2 new email gets a code', async () => {
    const r = await call('POST', '/auth/email/start', { body: { email: 'new@keys.test' } });
    expect(r.body).toMatchObject({ status: 'code_sent', resendInSeconds: 60 });
    expect(await lastCode('new@keys.test')).toMatch(/^\d{6}$/);
  });
  it('ONB-05.3 existing email goes to "Welcome, [first name]"', async () => {
    await signUp('exists@keys.test', 'Bola');
    const r = await call('POST', '/auth/email/start', { body: { email: 'EXISTS@keys.test' } });
    expect(r.body).toEqual({ status: 'existing', firstName: 'Bola', hasPassword: true });
  });
});

describe('ONB-07 verify email code', () => {
  it('ONB-07.4 wrong code shows the invalid-code error', async () => {
    await call('POST', '/auth/email/start', { body: { email: 'c1@keys.test' } });
    const right = await lastCode('c1@keys.test');
    const wrong = right === '000000' ? '111111' : '000000';
    const r = await call('POST', '/auth/email/verify', { body: { email: 'c1@keys.test', code: wrong } });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('INVALID_CODE');
  });
  it('ONB-07.5 a code older than 60 s is rejected with the same error', async () => {
    await call('POST', '/auth/email/start', { body: { email: 'c2@keys.test' } });
    const code = await lastCode('c2@keys.test');
    clock.advance(61 * SECOND);
    const r = await call('POST', '/auth/email/verify', { body: { email: 'c2@keys.test', code } });
    expect(r.body.error.code).toBe('INVALID_CODE');
  });
  it('ONB-07.2 resend only after 60 s, and the old code stops working', async () => {
    await call('POST', '/auth/email/start', { body: { email: 'c3@keys.test' } });
    const first = await lastCode('c3@keys.test');
    const early = await call('POST', '/auth/code/resend', { body: { email: 'c3@keys.test', purpose: 'signup' } });
    expect(early.status).toBe(429);
    expect(early.body.error.code).toBe('RESEND_TOO_SOON');
    clock.advance(60 * SECOND);
    const ok = await call('POST', '/auth/code/resend', { body: { email: 'c3@keys.test', purpose: 'signup' } });
    expect(ok.body.resendInSeconds).toBe(60);
    const second = await lastCode('c3@keys.test');
    if (first !== second) {
      const old = await call('POST', '/auth/email/verify', { body: { email: 'c3@keys.test', code: first } });
      expect(old.body.error.code).toBe('INVALID_CODE');
    }
    const r = await call('POST', '/auth/email/verify', { body: { email: 'c3@keys.test', code: second } });
    expect(r.body.ticket).toBeTruthy();
  });
  it('locks a code after 5 wrong tries', async () => {
    await call('POST', '/auth/email/start', { body: { email: 'c4@keys.test' } });
    const code = await lastCode('c4@keys.test');
    const wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) await call('POST', '/auth/email/verify', { body: { email: 'c4@keys.test', code: wrong } });
    const r = await call('POST', '/auth/email/verify', { body: { email: 'c4@keys.test', code } });
    expect(r.body.error.code).toBe('INVALID_CODE');
  });
});

describe('ONB-08 account details and password', () => {
  async function ticket(email: string) {
    await call('POST', '/auth/email/start', { body: { email } });
    return (await call('POST', '/auth/email/verify', { body: { email, code: await lastCode(email) } })).body.ticket;
  }
  it('ONB-08.3 empty names', async () => {
    const t = await ticket('n1@keys.test');
    const r = await call('POST', '/auth/signup', { body: { ticket: t, firstName: '', lastName: 'X', password: 'Keys2026!', confirmPassword: 'Keys2026!' } });
    expect(r.body.error.message).toBe('Add a first name');
    const r2 = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'A', lastName: ' ', password: 'Keys2026!', confirmPassword: 'Keys2026!' } });
    expect(r2.body.error.message).toBe('Add a last name');
  });
  it('ONB-08.2 password rules', async () => {
    const t = await ticket('n2@keys.test');
    const r = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'A', lastName: 'B', password: 'short', confirmPassword: 'short' } });
    expect(r.body.error.rules).toEqual(['Between 8-15 characters', 'Contain letters and numbers', 'At least one special character']);
    const r2 = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'A', lastName: 'B', password: 'abcdefgh1234567!', confirmPassword: 'abcdefgh1234567!' } });
    expect(r2.body.error.rules).toEqual(['Between 8-15 characters']);
  });
  it('ONB-08.4 passwords must match', async () => {
    const t = await ticket('n3@keys.test');
    const r = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'A', lastName: 'B', password: 'Keys2026!', confirmPassword: 'Keys2026?' } });
    expect(r.body.error.message).toBe('Passwords do not match');
  });
  it('ONB-08.5 creates the account and opens the address step', async () => {
    const t = await ticket('n4@keys.test');
    const r = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'Amy', lastName: 'Duncan', password: 'Keys2026!', confirmPassword: 'Keys2026!' } });
    expect(r.body.onboardingStep).toBe('address');
    const me = await call('GET', '/me', { token: r.body.token });
    expect(me.body).toMatchObject({ firstName: 'Amy', lastName: 'Duncan', verificationStatus: 'unverified' });
    // The ticket cannot be reused.
    const again = await call('POST', '/auth/signup', { body: { ticket: t, firstName: 'X', lastName: 'Y', password: 'Keys2026!', confirmPassword: 'Keys2026!' } });
    expect(again.body.error.code).toBe('TICKET_INVALID');
  });
});

describe('ONB-09 login', () => {
  it('ONB-09.1 / 09.2 right and wrong password', async () => {
    await signUp('l1@keys.test');
    const bad = await call('POST', '/auth/login', { body: { email: 'l1@keys.test', password: 'nope' } });
    expect(bad.body.error.message).toBe('Incorrect password');
    const ok = await call('POST', '/auth/login', { body: { email: 'l1@keys.test', password: 'Keys2026!' } });
    expect(ok.body.token).toBeTruthy();
    expect(ok.body.onboardingStep).toBe('address');
  });
  it('locks the account for 15 minutes after 5 wrong passwords', async () => {
    await signUp('l2@keys.test');
    for (let i = 0; i < 5; i++) await call('POST', '/auth/login', { body: { email: 'l2@keys.test', password: 'nope' } });
    const r = await call('POST', '/auth/login', { body: { email: 'l2@keys.test', password: 'Keys2026!' } });
    expect(r.body.error.code).toBe('LOCKED');
    clock.advance(16 * 60 * SECOND);
    expect((await call('POST', '/auth/login', { body: { email: 'l2@keys.test', password: 'Keys2026!' } })).body.token).toBeTruthy();
  });
  it('ONB-09.3 login inside the 30-day window reactivates; after it the account is gone', async () => {
    await signUp('l3@keys.test');
    await q(`update users set deactivated_at = $2 where email = $1`, ['l3@keys.test', new Date(clock.now().getTime() - 10 * DAY)]);
    const r = await call('POST', '/auth/login', { body: { email: 'l3@keys.test', password: 'Keys2026!' } });
    expect(r.body.reactivated).toBe(true);
    await q(`update users set deactivated_at = $2 where email = $1`, ['l3@keys.test', new Date(clock.now().getTime() - 31 * DAY)]);
    const gone = await call('POST', '/auth/login', { body: { email: 'l3@keys.test', password: 'Keys2026!' } });
    expect(gone.body.error.code).toBe('NO_ACCOUNT');
  });
});

describe('ONB-10 forgot password', () => {
  it('resets with a code and signs out every session', async () => {
    const token = await signUp('f1@keys.test');
    await call('POST', '/auth/password/forgot', { body: { email: 'f1@keys.test' } });
    const code = await lastCode('f1@keys.test');
    const wrong = await call('POST', '/auth/password/verify', { body: { email: 'f1@keys.test', code: code === '000000' ? '111111' : '000000' } });
    expect(wrong.body.error.code).toBe('INVALID_CODE');
    const v = await call('POST', '/auth/password/verify', { body: { email: 'f1@keys.test', code } });
    const bad = await call('POST', '/auth/password/reset', { body: { ticket: v.body.ticket, password: 'New2026!x', confirmPassword: 'New2026!y' } });
    expect(bad.body.error.message).toBe('Passwords do not match');
    const ok = await call('POST', '/auth/password/reset', { body: { ticket: v.body.ticket, password: 'New2026!x', confirmPassword: 'New2026!x' } });
    expect(ok.body.ok).toBe(true);
    expect((await call('GET', '/me', { token })).status).toBe(401);
    expect((await call('POST', '/auth/login', { body: { email: 'f1@keys.test', password: 'New2026!x' } })).body.token).toBeTruthy();
  });
  it('answers the same for unknown emails', async () => {
    const r = await call('POST', '/auth/password/forgot', { body: { email: 'nobody@keys.test' } });
    expect(r.status).toBe(200);
  });
});

describe('ONB-06 social sign-in', () => {
  it('ONB-06.1 creates a new account that confirms its legal name first', async () => {
    const r = await call('POST', '/auth/social', { body: { provider: 'apple', idToken: 'mock:apple-1:s1@keys.test:Sam:Lee' } });
    expect(r.body).toMatchObject({ isNew: true, onboardingStep: 'account', firstName: 'Sam' });
    const n = await call('POST', '/onboarding/account', { token: r.body.token, body: { firstName: 'Samuel', lastName: 'Lee' } });
    expect(n.body.onboardingStep).toBe('address');
    const again = await call('POST', '/auth/social', { body: { provider: 'apple', idToken: 'mock:apple-1:s1@keys.test' } });
    expect(again.body.isNew).toBe(false);
  });
  it('ONB-06.3 links to an existing password account instead of a second one', async () => {
    await signUp('s2@keys.test', 'Tobi');
    const r = await call('POST', '/auth/social', { body: { provider: 'google', idToken: 'mock:g-2:s2@keys.test' } });
    expect(r.body).toMatchObject({ isNew: false, firstName: 'Tobi' });
    const rows = await q(`select count(*)::int as n from users where email = 's2@keys.test'`);
    expect(rows[0].n).toBe(1);
  });
  it('rejects a bad token', async () => {
    const r = await call('POST', '/auth/social', { body: { provider: 'google', idToken: 'garbage' } });
    expect(r.status).toBe(401);
  });
});

describe('logout', () => {
  it('revokes the session', async () => {
    const token = await signUp('o1@keys.test');
    await call('POST', '/auth/logout', { token });
    expect((await call('GET', '/me', { token })).status).toBe(401);
  });
});
