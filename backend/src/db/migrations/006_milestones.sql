-- CBM-Q2: community milestone prompts. A milestone is reached once, the first
-- time the community's resident count reaches a tier threshold (100, 400, 700).
create table community_milestones (
  community_id uuid not null references communities(id) on delete cascade,
  threshold int not null,
  reached_at timestamptz not null,
  primary key (community_id, threshold)
);

-- Residents who have closed the prompt or opened "View new residents".
create table milestone_seen (
  user_id uuid not null references users(id) on delete cascade,
  community_id uuid not null references communities(id) on delete cascade,
  threshold int not null,
  seen_at timestamptz not null,
  primary key (user_id, community_id, threshold)
);
