import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { migrate } from '../src/db/migrate.js';
import { one, pool } from '../src/db/pool.js';
import { clock } from '../src/lib/clock.js';

let app: FastifyInstance;

export async function setup() {
  clock.reset();
  await pool.query('drop schema public cascade; create schema public;');
  await migrate();
  app = await buildApp();
  return app;
}
export async function teardown() {
  await app?.close();
}

export interface Res { status: number; body: any }
export async function call(method: string, url: string, opts: { token?: string; body?: unknown } = {}): Promise<Res> {
  const r = await app.inject({
    method: method as any,
    url,
    headers: opts.token ? { authorization: `Bearer ${opts.token}` } : {},
    payload: opts.body as any,
  });
  let body: any = r.body;
  try { body = JSON.parse(r.body); } catch { /* html */ }
  return { status: r.statusCode, body };
}

export async function upload(url: string, token: string, file: { name: string; mime: string; data: Buffer }): Promise<Res> {
  const boundary = '----keys' + Math.random().toString(16).slice(2);
  const payload = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.mime}\r\n\r\n`),
    file.data,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const r = await app.inject({
    method: 'POST', url, payload,
    headers: { authorization: `Bearer ${token}`, 'content-type': `multipart/form-data; boundary=${boundary}` },
  });
  return { status: r.statusCode, body: JSON.parse(r.body) };
}

export async function lastCode(email: string): Promise<string> {
  const r = await one<{ data: { code: string } }>(
    `select data from email_outbox where to_email = $1 and template like '%code' order by id desc limit 1`, [email],
  );
  return r!.data.code;
}

// Small valid files for upload tests.
export const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6300010000000500010d0a2db40000000049454e44ae426082', 'hex');
export const JPG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100), Buffer.from([0xff, 0xd9])]);
export const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF');
export const big = (head: Buffer, bytes: number) => Buffer.concat([head, Buffer.alloc(bytes - head.length)]);

// Full sign-up through to a chosen onboarding point.
export async function signUp(email: string, first = 'Amy', last = 'Duncan') {
  await call('POST', '/auth/email/start', { body: { email } });
  const v = await call('POST', '/auth/email/verify', { body: { email, code: await lastCode(email) } });
  const s = await call('POST', '/auth/signup', {
    body: { ticket: v.body.ticket, firstName: first, lastName: last, password: 'Keys2026!', confirmPassword: 'Keys2026!' },
  });
  return s.body.token as string;
}

export async function placeId(token: string, text: string) {
  const r = await call('GET', `/addresses/autocomplete?q=${encodeURIComponent(text)}`, { token });
  return r.body.suggestions[0].placeId as string;
}

export async function withAddress(email: string, address: string, code?: string) {
  const token = await signUp(email);
  const r = await call('POST', '/onboarding/address', { token, body: { placeId: await placeId(token, address), communityCode: code } });
  return { token, match: r.body.match, res: r };
}

export async function finishProfile(token: string) {
  const m = await upload('/media?kind=photo', token, { name: 'me.png', mime: 'image/png', data: PNG });
  return call('POST', '/onboarding/profile', { token, body: { photoMediaId: m.body.id, safetyAccepted: true } });
}

// A resident who pioneers the street community for an address, as a house.
export async function pioneerStreet(email: string, address: string) {
  const { token } = await withAddress(email, address);
  const s = await call('POST', '/onboarding/street', { token });
  await call('POST', '/onboarding/home-type', { token, body: { type: 'house', subtype: 'Townhouse' } });
  await finishProfile(token);
  return { token, community: s.body.community };
}

/** A resident who joins an existing community on the street of [address]. */
export async function joinStreet(email: string, address: string, first = 'Ben', last = 'Ade') {
  const token = await signUp(email, first, last);
  const r = await call('POST', '/onboarding/address', { token, body: { placeId: await placeId(token, address) } });
  await call('POST', '/onboarding/join', { token, body: { communityId: r.body.match.communities[0].id } });
  await call('POST', '/onboarding/home-type', { token, body: { type: 'house' } });
  await finishProfile(token);
  return token;
}

export async function me(token: string) {
  return (await call('GET', '/me', { token })).body;
}

export async function verify(token: string) {
  await call('POST', '/verification/check', { token, body: { method: 'card', paymentMethodId: 'pm_mock_pass_visa_4242' } });
}

/** Seat a resident on the committee board directly (board API arrives in milestone 3). */
export async function seat(token: string, role = 'Chair', kind: 'preset' | 'extra' | 'champion' = 'preset') {
  const m = await me(token);
  const { one } = await import('../src/db/pool.js');
  const b = (await one<{ id: string }>(
    `insert into boards(community_id) values ($1) on conflict (community_id) do update set community_id = excluded.community_id returning id`, [m.community.id],
  ))!;
  const pos = (await one<{ n: number }>('select count(*)::int as n from board_seats where board_id = $1', [b.id]))!.n;
  await one(`insert into board_seats(board_id, kind, role, position, occupant_id, occupied_at) values ($1,$2,$3,$4,$5,now())`, [b.id, kind, role, pos, m.id]);
}

/** Description and one photo: what a launch needs besides date, place and tags. */
export async function eventBasics(token: string) {
  const img = (await upload('/media?kind=photo', token, { name: 'e.png', mime: 'image/png', data: PNG })).body.id;
  return { description: 'Come along and meet your neighbours.', mediaIds: [img] };
}
