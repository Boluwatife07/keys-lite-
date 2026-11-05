// All settings come from environment variables. Every external service has a
// mock so the app runs end to end without real keys.
import { existsSync } from 'node:fs';

// Load backend/.env when present (Node 22 built-in, no extra package).
if (existsSync('.env') && process.env.NODE_ENV !== 'test') process.loadEnvFile('.env');

const env = process.env;

function bool(v: string | undefined, fallback: boolean) {
  if (v === undefined) return fallback;
  return v === '1' || v.toLowerCase() === 'true';
}

export const config = {
  port: Number(env.PORT ?? 3000),
  databaseUrl: env.DATABASE_URL ?? 'postgres://keys@localhost:5433/keys',
  // Public base for share links and deep links (XFR-02).
  linkBaseUrl: env.LINK_BASE_URL ?? 'https://keys.app',
  appStoreUrl: env.APP_STORE_URL ?? 'https://apps.apple.com/app/keys',
  playStoreUrl: env.PLAY_STORE_URL ?? 'https://play.google.com/store/apps/details?id=app.keys',
  // Media is stored on local disk for now; swap for S3/GCS + CDN later.
  storageDir: env.STORAGE_DIR ?? './storage',
  publicMediaBase: env.PUBLIC_MEDIA_BASE ?? '/media/files',
  // 32-byte hex key used to encrypt verification documents at rest (AVW-05.5).
  documentKeyHex: env.DOCUMENT_KEY_HEX ?? '0'.repeat(64),
  mocks: {
    email: bool(env.MOCK_EMAIL, true),
    places: bool(env.MOCK_PLACES, true),
    stripe: bool(env.MOCK_STRIPE, true),
    social: bool(env.MOCK_SOCIAL, true),
  },
  resendApiKey: env.RESEND_API_KEY ?? '',
  emailFrom: env.EMAIL_FROM ?? 'Keys <hello@keys.app>',
  googlePlacesKey: env.GOOGLE_PLACES_KEY ?? '',
  stripeSecretKey: env.STRIPE_SECRET_KEY ?? '',
  legal: {
    // Placeholders until Legal signs off the final documents (XFR-08.1).
    termsUrl: env.TERMS_URL ?? 'https://keys.app/legal/terms',
    privacyUrl: env.PRIVACY_URL ?? 'https://keys.app/legal/privacy',
    safetyUrl: env.SAFETY_URL ?? 'https://keys.app/legal/safety',
    communityGuidelinesUrl: env.GUIDELINES_URL ?? 'https://keys.app/legal/community-guidelines',
  },
};
