import { createPublicKey, createVerify } from 'node:crypto';
import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

export type SocialProvider = 'apple' | 'google';
export interface SocialProfile { sub: string; email: string; firstName?: string; lastName?: string }

const JWKS: Record<SocialProvider, { url: string; iss: string[]; aud: () => string[] }> = {
  apple: {
    url: 'https://appleid.apple.com/auth/keys',
    iss: ['https://appleid.apple.com'],
    aud: () => (process.env.APPLE_CLIENT_IDS ?? '').split(',').filter(Boolean),
  },
  google: {
    url: 'https://www.googleapis.com/oauth2/v3/certs',
    iss: ['accounts.google.com', 'https://accounts.google.com'],
    aud: () => (process.env.GOOGLE_CLIENT_IDS ?? '').split(',').filter(Boolean),
  },
};

const invalid = () => new AppError(401, 'SOCIAL_TOKEN_INVALID', 'We could not sign you in. Please try again.');

// Verifies an Apple or Google identity token (RS256 JWT) against the
// provider's public keys. In mock mode, tokens look like "mock:<sub>:<email>".
export async function verifySocialToken(provider: SocialProvider, idToken: string): Promise<SocialProfile> {
  if (config.mocks.social) {
    const [m, sub, email, firstName, lastName] = idToken.split(':');
    if (m !== 'mock' || !sub || !email) throw invalid();
    return { sub, email, firstName, lastName };
  }
  const [h, p, s] = idToken.split('.');
  if (!h || !p || !s) throw invalid();
  const header = JSON.parse(Buffer.from(h, 'base64url').toString());
  const payload = JSON.parse(Buffer.from(p, 'base64url').toString());
  const spec = JWKS[provider];
  const keys = (await (await fetch(spec.url)).json()) as { keys: any[] };
  const jwk = keys.keys.find((k) => k.kid === header.kid);
  if (!jwk || header.alg !== 'RS256') throw invalid();
  const ok = createVerify('RSA-SHA256').update(`${h}.${p}`).verify(createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(s, 'base64url'));
  if (!ok) throw invalid();
  if (!spec.iss.includes(payload.iss) || !spec.aud().includes(payload.aud)) throw invalid();
  if (payload.exp * 1000 < Date.now()) throw invalid();
  if (!payload.email) throw invalid();
  return { sub: String(payload.sub), email: String(payload.email) };
}
