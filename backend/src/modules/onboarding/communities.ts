import type pg from 'pg';
import { one, q, type Db } from '../../db/pool.js';
import { communityCode } from '../../lib/crypto.js';
import { LIMITS } from '../../lib/rules.js';
import { normalise, streetKey, type ResolvedAddress, type StreetRef } from '../../services/places.js';

export type CommunityType = 'street' | 'development' | 'building';
export interface CommunityRow {
  id: string; type: CommunityType; name: string; code: string; parent_id: string | null;
  anchor_street_id: string | null; building_premise: string | null; lat: number; lng: number; created_by: string | null;
}

const TYPE_LABEL: Record<CommunityType, string> = { street: 'STREET COMMUNITY', development: 'DEVELOPMENT', building: 'BUILDING' };

export async function upsertStreet(s: StreetRef, db: Db) {
  return (await one<{ id: string; name: string; town: string; lat: number; lng: number }>(
    `insert into streets(street_key, name, town, lat, lng) values ($1,$2,$3,$4,$5)
     on conflict (street_key) do update set name = excluded.name
     returning id, name, town, lat, lng`,
    [streetKey(s.name, s.town), s.name, s.town, s.lat, s.lng], db,
  ))!;
}

export async function saveAddress(a: ResolvedAddress, db: Db) {
  const street = await upsertStreet({ name: a.streetName, town: a.town, lat: a.lat, lng: a.lng }, db);
  const addr = await one<{ id: string }>(
    `insert into addresses(place_id, line1, line2, premise, street_id, postcode, town, lat, lng, formatted)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning id`,
    [a.placeId, a.line1, a.line2 ?? null, normalise(a.premise), street.id, a.postcode, a.town, a.lat, a.lng, a.formatted], db,
  );
  return { addressId: addr!.id, street };
}

export async function counts(communityId: string, db: Db = undefined as any) {
  const r = await one<{ residents: number }>(
    `select count(*)::int as residents from memberships where community_id = $1 or building_id = $1`,
    [communityId], db,
  );
  // Committee seats arrive with the Committee board milestone; the helper
  // checks for the table so onboarding works before it exists.
  const hasBoard = await one<{ t: string | null }>(`select to_regclass('board_seats')::text as t`, [], db);
  let committee = 0;
  if (hasBoard?.t) {
    const c = await one<{ n: number }>(
      `select count(*)::int as n from board_seats s join boards b on b.id = s.board_id
        where b.community_id = $1 and s.occupant_id is not null and s.kind <> 'champion'`,
      [communityId], db,
    );
    committee = c?.n ?? 0;
  }
  return { residents: r?.residents ?? 0, committee };
}

// Card shown on match screens. ONB-13.4: counts only for 500+ residents.
export async function card(c: CommunityRow, opts: { alwaysCounts?: boolean; db?: Db } = {}) {
  const n = await counts(c.id, opts.db);
  const show = opts.alwaysCounts || n.residents >= LIMITS.countsVisibleFrom;
  let parentName: string | undefined;
  if (c.parent_id) parentName = (await one<{ name: string }>('select name from communities where id = $1', [c.parent_id], opts.db))?.name;
  return {
    id: c.id,
    type: c.type,
    typeLabel: TYPE_LABEL[c.type],
    name: c.name,
    code: c.code,
    parentName,
    residents: show ? n.residents : undefined,
    committeeMembers: show ? n.committee : undefined,
  };
}

// Top-level communities (street + developments) that cover a street.
export async function communitiesForStreet(streetId: string, db?: Db) {
  return q<CommunityRow>(
    `select c.* from street_links l join communities c on c.id = l.community_id
      where l.street_id = $1 and c.type in ('street','development')
      order by (c.type = 'street') desc, c.created_at`,
    [streetId], db,
  );
}

export async function newCode(db: Db) {
  for (let i = 0; i < 10; i++) {
    const code = communityCode();
    if (!(await one('select 1 from communities where code = $1', [code], db))) return code;
  }
  throw new Error('could not allocate community code');
}

export async function createCommunity(
  c: pg.PoolClient,
  v: { type: CommunityType; name: string; parentId?: string; anchorStreetId?: string; premise?: string; lat: number; lng: number; createdBy: string },
) {
  return (await one<CommunityRow>(
    `insert into communities(type, name, code, parent_id, anchor_street_id, building_premise, lat, lng, created_by)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9) returning *`,
    [v.type, v.name, await newCode(c), v.parentId ?? null, v.anchorStreetId ?? null, v.premise ?? null, v.lat, v.lng, v.createdBy], c,
  ))!;
}

export const haversineSql = (lat: string, lng: string) =>
  `(6371 * 2 * asin(sqrt(power(sin(radians(c.lat - ${lat}) / 2), 2) + cos(radians(${lat})) * cos(radians(c.lat)) * power(sin(radians(c.lng - ${lng}) / 2), 2))))`;
