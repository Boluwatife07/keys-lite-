import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { one, q } from '../src/db/pool.js';
import { clock, DAY } from '../src/lib/clock.js';
import { decrypt } from '../src/lib/crypto.js';
import { MB } from '../src/lib/rules.js';
import { decideReviewCase } from '../src/modules/verification/service.js';
import { big, call, JPG, PDF, PNG, pioneerStreet, setup, teardown, upload } from './helpers.js';

let short: Buffer;
let long: Buffer;
beforeAll(async () => {
  await setup();
  mkdirSync('.test-storage/tmp', { recursive: true });
  const mk = (secs: number, out: string) =>
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'lavfi', '-i', `color=c=black:s=16x16:d=${secs}`, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', out]);
  mk(5, '.test-storage/tmp/short.mp4');
  mk(62, '.test-storage/tmp/long.mp4');
  short = readFileSync('.test-storage/tmp/short.mp4');
  long = readFileSync('.test-storage/tmp/long.mp4');
});
afterAll(teardown);

describe('AVW-02 / AVW-04 bank card check', () => {
  it('fail -> mismatch data, pass -> verified; only pass/fail, method and last 4 are kept', async () => {
    const { token } = await pioneerStreet('v1@keys.test', '3 Maple Road');
    const s0 = await call('GET', '/verification', { token });
    expect(s0.body).toMatchObject({ status: 'unverified', reviewCase: null });
    expect(s0.body.acceptedDocuments).toEqual(['Utility bill', 'Bank statement', 'Council tax letter', 'Tenancy agreement', 'Government-issued letter']);

    const fail = await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_fail_visa_4821' } });
    // AVW-04.1: method used and the address on Keys.
    expect(fail.body).toMatchObject({ result: 'fail', brand: 'visa', last4: '4821', homeAddress: '3 Maple Road, London SE1 7AA' });
    expect((await call('GET', '/me', { token })).body.verificationStatus).toBe('unverified');

    const pass = await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_4242' } });
    expect(pass.body.result).toBe('pass');
    expect((await call('GET', '/me', { token })).body.verificationStatus).toBe('verified');

    const cols = (await q(`select column_name from information_schema.columns where table_name = 'verification_attempts'`)).map((r) => r.column_name);
    expect(cols.sort()).toEqual(['brand', 'created_at', 'id', 'last4', 'method', 'result', 'user_id']);

    const again = await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_4242' } });
    expect(again.body.error.code).toBe('ALREADY_VERIFIED');
  });
  it('AVW-03.2 cancelling the wallet sheet is logged with no error', async () => {
    const { token } = await pioneerStreet('v2@keys.test', '4 Maple Road');
    const r = await call('POST', '/verification/cancelled', { token, body: { method: 'apple_pay' } });
    expect(r.body.ok).toBe(true);
  });
  it('limits attempts per day', async () => {
    const { token } = await pioneerStreet('v3@keys.test', '5 Maple Road');
    for (let i = 0; i < 5; i++) await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_fail_visa_1111' } });
    const r = await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_1111' } });
    expect(r.status).toBe(429);
    clock.advance(DAY + 1000);
    expect((await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_1111' } })).body.result).toBe('pass');
  });
});

describe('AVW-05 / AVW-06 contest and manual review', () => {
  it('uploads an encrypted document, shows under review, admin outcome emails the resident', async () => {
    const { token } = await pioneerStreet('v4@keys.test', '6 Maple Road');
    const early = await upload('/verification/contest', token, { name: 'bill.pdf', mime: 'application/pdf', data: PDF });
    expect(early.body.error.code).toBe('NOTHING_TO_CONTEST');
    await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_fail_visa_4821' } });

    const wrongType = await upload('/verification/contest', token, { name: 'x.txt', mime: 'text/plain', data: Buffer.from('hello') });
    expect(wrongType.status).toBe(400);
    const tooBig = await upload('/verification/contest', token, { name: 'big.pdf', mime: 'application/pdf', data: big(PDF, 10 * MB + 1) });
    expect(tooBig.body.error.code).toBe('FILE_TOO_LARGE');

    const ok = await upload('/verification/contest', token, { name: 'bill.pdf', mime: 'application/pdf', data: PDF });
    expect(ok.body.status).toBe('under_review');
    expect(ok.body.reviewCase.ref).toMatch(/^KYS-\d{4}-\d{2}-\d{4}$/);
    expect(ok.body.reviewCase.estimate).toBe('Est. 1-2 business days');

    // AVW-05.4: verification now opens on the under-review screen.
    const s = await call('GET', '/verification', { token });
    expect(s.body).toMatchObject({ status: 'under_review', reviewCase: { documentName: 'bill.pdf' } });
    // AVW-05.5: stored encrypted.
    const rc = await one<any>(`select * from review_cases where ref = $1`, [ok.body.reviewCase.ref]);
    const raw = readFileSync(`.test-storage/${rc.document_key}`);
    expect(raw.includes(Buffer.from('%PDF'))).toBe(false);
    expect(decrypt(raw).equals(PDF)).toBe(true);

    expect(await decideReviewCase(rc.id, false, 'admin-1')).toBe(true);
    expect((await call('GET', '/me', { token })).body.verificationStatus).toBe('unverified');
    const mail = await one<any>(`select template from email_outbox where to_email = 'v4@keys.test' order by id desc limit 1`);
    expect(mail.template).toBe('verification_rejected');
    expect(await decideReviewCase(rc.id, true, 'admin-1')).toBe(false); // already decided
  });
});

describe('XFR-01 media limits', () => {
  let token: string;
  beforeAll(async () => { token = (await pioneerStreet('m1@keys.test', '7 Maple Road')).token; });

  it('photos: JPG/PNG up to 15 MB; type is read from the bytes', async () => {
    expect((await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: PNG })).body.kind).toBe('photo');
    expect((await upload('/media?kind=photo', token, { name: 'a.jpg', mime: 'image/jpeg', data: JPG })).body.mime).toBe('image/jpeg');
    const fake = await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: PDF });
    expect(fake.body.error.code).toBe('FILE_TYPE');
    const huge = await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: big(PNG, 15 * MB + 1) });
    expect(huge.body.error.message).toBe('The image you selected is too large. Please choose a different image.');
    expect((await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: big(PNG, 15 * MB) })).status).toBe(200);
  });
  it('videos: 60 s or less, checked on the server', async () => {
    const ok = await upload('/media?kind=video', token, { name: 'v.mp4', mime: 'video/mp4', data: short });
    expect(ok.body.durationSeconds).toBeCloseTo(5, 0);
    const tooLong = await upload('/media?kind=video', token, { name: 'l.mp4', mime: 'video/mp4', data: long });
    expect(tooLong.body.error.code).toBe('VIDEO_TOO_LONG');
  });
  it('documents: up to 25 MB', async () => {
    expect((await upload('/media?kind=document', token, { name: 'd.pdf', mime: 'application/pdf', data: PDF })).status).toBe(200);
    const huge = await upload('/media?kind=document', token, { name: 'd.pdf', mime: 'application/pdf', data: big(PDF, 25 * MB + 1) });
    expect(huge.body.error.code).toBe('FILE_TOO_LARGE');
  });
  it('uploaded files are served back', async () => {
    const m = await upload('/media?kind=photo', token, { name: 'a.png', mime: 'image/png', data: PNG });
    const r = await call('GET', m.body.url);
    expect(r.status).toBe(200);
  });
});

describe('XFR-03 reports', () => {
  it('one reason list; Other needs text; goes to the queue', async () => {
    const { token } = await pioneerStreet('r1@keys.test', '8 Maple Road');
    const reasons = (await call('GET', '/reports/reasons')).body.reasons;
    expect(reasons.at(-1)).toBe('Other');
    const noText = await call('POST', '/reports', { token, body: { itemType: 'post', itemId: 'p1', reason: 'Other' } });
    expect(noText.body.error.code).toBe('REPORT_TEXT_REQUIRED');
    const ok = await call('POST', '/reports', { token, body: { itemType: 'post', itemId: 'p1', reason: reasons[0] } });
    expect(ok.body.ok).toBe(true);
    expect((await q(`select * from reports`)).length).toBe(1);
  });
});

it('storage leaves no plain verification documents', () => {
  const files = readdirSync('.test-storage/verification');
  expect(files.every((f) => f.endsWith('.bin'))).toBe(true);
});
