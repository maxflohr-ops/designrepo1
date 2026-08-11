-- TikTok OAuth tokens (identity module owns these; the counting job reads
-- videos through each clipper's own token) and App Attest key registrations
-- for cash-out.

create table tiktok_token (
  tiktok_open_id text primary key,
  access_token   text not null,
  refresh_token  text,
  expires_at     timestamptz not null,
  scopes         text[] not null default '{}',
  updated_at     timestamptz not null default now()
);

create table attest_key (
  account_id uuid not null references account(id),
  key_id     text not null,
  created_at timestamptz not null default now(),
  primary key (account_id, key_id)
);
