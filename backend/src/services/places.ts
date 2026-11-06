import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

// Address lookup (BE-02.1). Google Places in production, a small fake
// neighbourhood in mock mode so every onboarding path can be exercised.

export interface AddressSuggestion { placeId: string; primary: string; secondary: string }
export interface ResolvedAddress {
  placeId: string;
  line1: string;
  line2?: string;
  premise: string;      // house or building number/name shared by flats in one building
  streetName: string;
  town: string;
  postcode: string;
  lat: number;
  lng: number;
  formatted: string;
}
export interface StreetRef { name: string; town: string; lat: number; lng: number }

export interface PlacesProvider {
  autocomplete(input: string, sessionToken?: string): Promise<AddressSuggestion[]>;
  resolve(placeId: string, sessionToken?: string): Promise<ResolvedAddress | null>;
  // Streets that physically meet the given street (ONB-20.1).
  connectedStreets(street: StreetRef): Promise<StreetRef[]>;
}

export const normalise = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ');
export const streetKey = (name: string, town: string) => `${normalise(name)}|${normalise(town)}`;

// ---------------------------------------------------------------- mock
interface MockStreet { name: string; town: string; postcode: string; lat: number; lng: number; links: string[] }
export const MOCK_STREETS: MockStreet[] = [
  { name: 'Maple Road', town: 'London', postcode: 'SE1 7AA', lat: 51.5, lng: -0.1, links: ['Oak Avenue', 'Birch Lane', 'Cedar Close'] },
  { name: 'Oak Avenue', town: 'London', postcode: 'SE1 7AB', lat: 51.5012, lng: -0.1015, links: ['Maple Road', 'Elm Street', 'Willow Way'] },
  { name: 'Birch Lane', town: 'London', postcode: 'SE1 7AD', lat: 51.4991, lng: -0.0988, links: ['Maple Road', 'Ash Grove'] },
  { name: 'Cedar Close', town: 'London', postcode: 'SE1 7AE', lat: 51.4996, lng: -0.1012, links: ['Maple Road'] },
  { name: 'Elm Street', town: 'London', postcode: 'SE1 7AF', lat: 51.5025, lng: -0.1031, links: ['Oak Avenue', 'Hazel Drive', 'Rowan Court', 'Poplar Place', 'Linden Mews', 'Chestnut Row'] },
  { name: 'Willow Way', town: 'London', postcode: 'SE1 7AG', lat: 51.5019, lng: -0.0999, links: ['Oak Avenue'] },
  { name: 'Ash Grove', town: 'London', postcode: 'SE1 7AH', lat: 51.4983, lng: -0.0975, links: ['Birch Lane'] },
  { name: 'Hazel Drive', town: 'London', postcode: 'SE1 7AJ', lat: 51.5033, lng: -0.1042, links: ['Elm Street'] },
  { name: 'Rowan Court', town: 'London', postcode: 'SE1 7AL', lat: 51.5029, lng: -0.1051, links: ['Elm Street'] },
  { name: 'Poplar Place', town: 'London', postcode: 'SE1 7AN', lat: 51.5038, lng: -0.1025, links: ['Elm Street'] },
  { name: 'Linden Mews', town: 'London', postcode: 'SE1 7AP', lat: 51.5021, lng: -0.1046, links: ['Elm Street'] },
  { name: 'Chestnut Row', town: 'London', postcode: 'SE1 7AQ', lat: 51.5031, lng: -0.1018, links: ['Elm Street'] },
  // About 75 km away, used to prove the 10 km development name check.
  { name: 'Harbour Street', town: 'Brighton', postcode: 'BN1 1AA', lat: 50.8225, lng: -0.1372, links: [] },
];

function mockAddress(si: number, num: number, flat?: number): ResolvedAddress {
  const s = MOCK_STREETS[si];
  const line1 = `${flat ? `Flat ${flat}, ` : ''}${num} ${s.name}`;
  return {
    placeId: `mock|${si}|${num}|${flat ?? ''}`,
    line1,
    premise: String(num),
    streetName: s.name,
    town: s.town,
    postcode: s.postcode,
    lat: s.lat + num * 0.00001,
    lng: s.lng + num * 0.00001,
    formatted: `${line1}, ${s.town} ${s.postcode}`,
  };
}

export const mockPlaces: PlacesProvider = {
  async autocomplete(input) {
    const m = normalise(input).match(/^(?:flat (\d+),?\s*)?(\d+)\s+(.+)$/);
    if (!m) return [];
    const flat = m[1] ? Number(m[1]) : undefined;
    const num = Number(m[2]);
    if (num < 1 || num > 200) return [];
    const out: AddressSuggestion[] = [];
    MOCK_STREETS.forEach((s, i) => {
      if (normalise(s.name).startsWith(m[3])) {
        const a = mockAddress(i, num, flat);
        out.push({ placeId: a.placeId, primary: a.line1, secondary: `${s.town} ${s.postcode}` });
      }
    });
    return out.slice(0, 5);
  },
  async resolve(placeId) {
    const [m, si, num, flat] = placeId.split('|');
    if (m !== 'mock' || !MOCK_STREETS[Number(si)]) return null;
    return mockAddress(Number(si), Number(num), flat ? Number(flat) : undefined);
  },
  async connectedStreets(street) {
    const s = MOCK_STREETS.find((x) => streetKey(x.name, x.town) === streetKey(street.name, street.town));
    if (!s) return [];
    return s.links
      .map((n) => MOCK_STREETS.find((x) => x.name === n && x.town === s.town)!)
      .map(({ name, town, lat, lng }) => ({ name, town, lat, lng }));
  },
};

// ---------------------------------------------------------------- Google
const G = 'https://places.googleapis.com/v1';
function gHeaders(fieldMask: string, token?: string) {
  return {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': config.googlePlacesKey,
    'X-Goog-FieldMask': fieldMask,
    ...(token ? { 'X-Goog-Session-Token': token } : {}),
  };
}
const comp = (cs: any[], type: string) => cs.find((c) => c.types?.includes(type))?.longText as string | undefined;

export const googlePlaces: PlacesProvider = {
  async autocomplete(input, sessionToken) {
    const res = await fetch(`${G}/places:autocomplete`, {
      method: 'POST',
      headers: gHeaders('suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat'),
      body: JSON.stringify({
        input,
        includedRegionCodes: ['gb'],
        includedPrimaryTypes: ['street_address', 'premise', 'subpremise'],
        sessionToken,
      }),
    });
    if (!res.ok) throw new AppError(502, 'ADDRESS_LOOKUP_FAILED', 'Address search is not available right now.');
    const json = (await res.json()) as any;
    return (json.suggestions ?? []).map((s: any) => ({
      placeId: s.placePrediction.placeId,
      primary: s.placePrediction.structuredFormat?.mainText?.text ?? '',
      secondary: s.placePrediction.structuredFormat?.secondaryText?.text ?? '',
    }));
  },
  async resolve(placeId, sessionToken) {
    const res = await fetch(`${G}/places/${encodeURIComponent(placeId)}${sessionToken ? `?sessionToken=${sessionToken}` : ''}`, {
      headers: gHeaders('id,formattedAddress,addressComponents,location'),
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new AppError(502, 'ADDRESS_LOOKUP_FAILED', 'Address search is not available right now.');
    const p = (await res.json()) as any;
    const cs = p.addressComponents ?? [];
    const route = comp(cs, 'route');
    const postcode = comp(cs, 'postal_code');
    const town = comp(cs, 'postal_town') ?? comp(cs, 'locality');
    const number = comp(cs, 'street_number') ?? comp(cs, 'premise');
    if (!route || !postcode || !town || !number) return null; // not a real home address (ONB-11.3)
    const sub = comp(cs, 'subpremise');
    const line1 = `${sub ? `${sub}, ` : ''}${number} ${route}`;
    return {
      placeId: p.id, line1, premise: number, streetName: route, town, postcode,
      lat: p.location.latitude, lng: p.location.longitude, formatted: p.formattedAddress,
    };
  },
  // Google has no "which streets meet this one" call. We reverse geocode a
  // ring of points about 120 m around the street and keep distinct roads.
  // Needs check with engineering: swap for OS MasterMap / OSM road graph if
  // results are not good enough.
  async connectedStreets(street) {
    const out = new Map<string, StreetRef>();
    const r = 0.0011;
    for (let i = 0; i < 8; i++) {
      const a = (Math.PI * 2 * i) / 8;
      const lat = street.lat + r * Math.sin(a);
      const lng = street.lng + (r * Math.cos(a)) / Math.cos((street.lat * Math.PI) / 180);
      const res = await fetch(
        // The Geocoding web service only reads the key from the URL (it ignores
        // the X-Goog-Api-Key header), so it goes in the query string here.
        `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&result_type=route&key=${encodeURIComponent(config.googlePlacesKey)}`,
      );
      if (!res.ok) continue;
      const j = (await res.json()) as any;
      for (const r0 of j.results ?? []) {
        const name = r0.address_components?.find((c: any) => c.types.includes('route'))?.long_name;
        const town = r0.address_components?.find((c: any) => c.types.includes('postal_town'))?.long_name ?? street.town;
        if (!name || streetKey(name, town) === streetKey(street.name, street.town)) continue;
        out.set(streetKey(name, town), { name, town, lat: r0.geometry.location.lat, lng: r0.geometry.location.lng });
      }
    }
    return [...out.values()];
  },
};

export const places: PlacesProvider = config.mocks.places ? mockPlaces : googlePlaces;
