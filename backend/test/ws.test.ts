import WebSocket from 'ws';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { call, joinStreet, me, pioneerStreet, setup, teardown } from './helpers.js';

let app: Awaited<ReturnType<typeof buildApp>>;
beforeAll(async () => {
  await setup();
  app = await buildApp();
  await app.listen({ port: 0, host: '127.0.0.1' });
});
afterAll(async () => { await app.close(); await teardown(); });

it('new messages and typing are pushed over the websocket', async () => {
  const a = (await pioneerStreet('wa@keys.test', '1 Maple Road')).token;
  const b = await joinStreet('wb@keys.test', '2 Maple Road', 'Web', 'Sock');
  const chat = (await call('POST', '/chats/direct', { token: a, body: { userId: (await me(b)).id } })).body.chat.id;
  const port = (app.server.address() as any).port;
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${b}`);
  await new Promise((r) => ws.on('open', r));
  const events: any[] = [];
  ws.on('message', (d) => events.push(JSON.parse(String(d))));
  await call('POST', `/chats/${chat}/messages`, { token: a, body: { text: 'ping' } });
  await call('POST', `/chats/${chat}/typing`, { token: a });
  await new Promise((r) => setTimeout(r, 200));
  expect(events.map((e) => e.type)).toEqual(['message', 'typing']);
  expect(events[0].chatId).toBe(chat);
  expect((await call('GET', '/chats', { token: b })).body.chats[0].typing).toBe(true);
  ws.close();
  const bad = new WebSocket(`ws://127.0.0.1:${port}/ws?token=nope`);
  const code = await new Promise((r) => bad.on('close', (c) => r(c)));
  expect(code).toBe(4401);
});
