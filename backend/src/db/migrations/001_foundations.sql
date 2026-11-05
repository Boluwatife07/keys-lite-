-- Keys Lite Phase 1: foundations, onboarding, learning, address verification.
create extension if not exists pg_trgm;
create extension if not exists citext;
create extension if not exists pgcrypto;

-- Streets come from the address provider (Google Places "route" + postal town).
create table streets (
  id uuid primary key default gen_random_uuid(),
  street_key text not null unique,          -- normalised "route|town"
  name text not null,
  town text not null,
  lat double precision not null,
  lng double precision not null,
  created_at timestamptz not null default now()
);

create table addresses (
  id uuid primary key default gen_random_uuid(),
  place_id text,
  line1 text not null,
  line2 text,
  premise text,                             -- house number / building number, used for building matching
  street_id uuid not null references streets(id),
  postcode text not null,
  town text not null,
  lat double precision not null,
  lng double precision not null,
  formatted text not null,
  created_at timestamptz not null default now()
);

create type verification_status as enum ('unverified', 'under_review', 'verified');
create type onboarding_step as enum ('account', 'address', 'community', 'home_type', 'profile', 'complete');

create table users (
  id uuid primary key default gen_random_uuid(),
  email citext not null unique,
  email_verified boolean not null default false,
  first_name text not null,
  last_name text not null,
  password_hash text,
  onboarding_step onboarding_step not null default 'address',
  verification_status verification_status not null default 'unverified',
  home_address_id uuid references addresses(id),
  photo_url text,
  bio text,
  safety_ack_at timestamptz,
  learning_done_at timestamptz,
  welcome_prompt_done_at timestamptz,
  failed_logins int not null default 0,
  locked_until timestamptz,
  deactivated_at timestamptz,
  last_deactivated_at timestamptz,
  created_at timestamptz not null default now()
);

create table social_identities (
  provider text not null check (provider in ('apple', 'google')),
  provider_user_id text not null,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (provider, provider_user_id)
);

create table sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  token_hash text not null unique,
  device text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index sessions_user on sessions(user_id);

-- One-time email codes for sign-up, password reset and change of email.
create table email_codes (
  id uuid primary key default gen_random_uuid(),
  email citext not null,
  purpose text not null check (purpose in ('signup', 'reset', 'change_email')),
  user_id uuid references users(id) on delete cascade,
  code_hash text not null,
  attempts int not null default 0,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  invalidated_at timestamptz,
  ticket_hash text,                         -- issued after a correct code; spent by the next step
  ticket_expires_at timestamptz,
  ticket_used_at timestamptz,
  created_at timestamptz not null default now()
);
create index email_codes_lookup on email_codes(email, purpose, created_at desc);
create table code_send_log (
  id bigserial primary key,
  email citext not null,
  ip text,
  created_at timestamptz not null default now()
);

create type community_type as enum ('street', 'development', 'building');

create table communities (
  id uuid primary key default gen_random_uuid(),
  type community_type not null,
  name text not null,
  code char(6) not null unique,
  parent_id uuid references communities(id),        -- buildings only
  anchor_street_id uuid references streets(id),     -- street communities and buildings
  building_premise text,                            -- buildings: the shared house/building number
  lat double precision not null,
  lng double precision not null,
  created_by uuid references users(id),
  created_at timestamptz not null default now()
);
-- One street community per street (ONB-15.3).
create unique index one_street_community on communities(anchor_street_id) where type = 'street';
-- Building names unique per street (ONB-17.3).
create unique index building_name_per_street on communities(anchor_street_id, lower(name)) where type = 'building';
create index communities_name_trgm on communities using gin (lower(name) gin_trgm_ops);

-- Which streets a street or development community covers.
create table street_links (
  street_id uuid not null references streets(id),
  community_id uuid not null references communities(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (street_id, community_id)
);
create index street_links_community on street_links(community_id);

create type membership_level as enum ('house', 'building');

-- A resident belongs to one top-level community (street or development),
-- optionally inside a building of it.
create table memberships (
  user_id uuid primary key references users(id) on delete cascade,
  community_id uuid not null references communities(id),
  level membership_level,
  building_id uuid references communities(id),
  home_subtype text,
  joined_at timestamptz not null default now()
);
create index memberships_community on memberships(community_id);
create index memberships_building on memberships(building_id);

-- Address verification (AVW). Only pass/fail, method and last 4 digits are kept.
create table verification_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  method text not null check (method in ('card', 'apple_pay', 'google_pay')),
  brand text,
  last4 text,
  result text not null check (result in ('pass', 'fail', 'cancelled', 'error')),
  created_at timestamptz not null default now()
);
create index verification_attempts_user on verification_attempts(user_id, created_at desc);

create table review_cases (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  user_id uuid not null references users(id) on delete cascade,
  document_key text not null,               -- encrypted file in storage
  document_name text not null,
  document_mime text not null,
  document_size int not null,
  status text not null default 'under_review' check (status in ('under_review', 'approved', 'rejected')),
  decided_by text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

-- Shared media pipeline (BE-90.1).
create table media (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('photo', 'video', 'document')),
  mime text not null,
  size_bytes int not null,
  duration_seconds double precision,
  original_name text,
  storage_key text not null,
  url text not null,
  created_at timestamptz not null default now()
);

-- Reports go to the Admin Panel moderation queue (BE-90.4).
create table reports (
  id uuid primary key default gen_random_uuid(),
  item_type text not null,
  item_id text not null,
  reporter_id uuid not null references users(id) on delete cascade,
  reason text not null,
  text text,
  status text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);

-- Outgoing email log (mock and real) for audit and tests.
create table email_outbox (
  id bigserial primary key,
  to_email text not null,
  template text not null,
  data jsonb not null,
  created_at timestamptz not null default now()
);
