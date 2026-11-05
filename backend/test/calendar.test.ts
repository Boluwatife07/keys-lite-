import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { clock, DAY } from '../src/lib/clock.js';
import { call, joinStreet, pioneerStreet, placeId, seat, setup, teardown, verify } from './helpers.js';

let chair: string; let ben: string; let cara: string;
const day = (d: number, hour = 18) => {
  const t = new Date(clock.now().getTime() + d * DAY);
  t.setUTCHours(hour, 0, 0, 0);
  return t;
};

beforeAll(async () => {
  await setup();
  chair = (await pioneerStreet('chair@keys.test', '1 Maple Road')).token;
  await verify(chair);
  await seat(chair, 'Chair');
  ben = await joinStreet('ben@keys.test', '2 Maple Road', 'Ben', 'Ade');
  cara = await joinStreet('cara@keys.test', '3 Maple Road', 'Cara', 'Lee');
  await verify(ben);
});
afterAll(teardown);

describe('CAL calendar', () => {
  it('empty: the Home preview collapses', async () => {
    expect((await call('GET', '/calendar/upcoming', { token: ben })).body).toMatchObject({ day: null, items: [] });
  });

  it('CAL-04: events for ticket holders and the team; updates for their audience on the posting day', async () => {
    const pid = await placeId(chair, '1 Maple Road');
    const d = (await call('POST', '/events', { token: chair, body: { category: 'residential', title: 'Movie night', startAt: day(5).toISOString(), endAt: day(5, 21).toISOString(), format: 'physical', placeId: pid, tags: ['Social'] } })).body.event;
    await call('POST', `/events/${d.id}/launch`, { token: chair });
    await call('POST', '/updates', { token: chair, body: { title: 'Bins tomorrow', details: 'Put them out tonight.' } });
    const from = day(-1, 0).toISOString();
    const to = day(30, 0).toISOString();
    // Ben has no ticket yet: he sees the update only.
    let items = (await call('GET', `/calendar?from=${from}&to=${to}`, { token: ben })).body.items;
    expect(items.map((i: any) => [i.type, i.title])).toEqual([['update', 'Bins tomorrow']]);
    expect(items[0]).toMatchObject({ color: '#D92D20', open: { type: 'update' } });
    await call('POST', `/events/${d.id}/tickets`, { token: ben });
    items = (await call('GET', `/calendar?from=${from}&to=${to}`, { token: ben })).body.items;
    expect(items.map((i: any) => i.type)).toEqual(['update', 'event']);
    expect(items[1]).toMatchObject({ color: '#1C8C86', open: { type: 'event', id: d.id } });
    // Events only (Events Discover calendar).
    expect((await call('GET', `/calendar?from=${from}&to=${to}&types=event`, { token: ben })).body.items).toHaveLength(1);
    // The host sees their event; Cara (no ticket) does not.
    expect((await call('GET', `/calendar?from=${from}&to=${to}&types=event`, { token: chair })).body.items).toHaveLength(1);
    expect((await call('GET', `/calendar?from=${from}&to=${to}&types=event`, { token: cara })).body.items).toHaveLength(0);
  });

  it('CAL-02: the nearest day with items, today tag; CAL-03.3 nearest schedule', async () => {
    const up = (await call('GET', '/calendar/upcoming', { token: ben })).body;
    expect(up.today).toBe(true);
    expect(up.items[0].title).toBe('Bins tomorrow');
    const next = (await call('GET', `/calendar/nearest?from=${day(1, 0).toISOString()}`, { token: ben })).body.item;
    expect(next.title).toBe('Movie night');
  });

  it('resolved updates leave the calendar', async () => {
    const u = (await call('GET', '/updates', { token: chair })).body.updates[0];
    await call('POST', `/updates/${u.id}/resolve`, { token: chair });
    const items = (await call('GET', `/calendar?from=${day(-1, 0).toISOString()}&to=${day(30, 0).toISOString()}&types=update`, { token: ben })).body.items;
    expect(items).toEqual([]);
  });
});
