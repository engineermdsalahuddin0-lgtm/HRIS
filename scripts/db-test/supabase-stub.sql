-- Minimal stand-in for the parts of Supabase the migrations rely on, so they can
-- run in PGlite (in-process Postgres). Used only by scripts/db-test/run.mjs.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create schema extensions;
create schema storage;

create table auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text unique, phone text unique,
  encrypted_password text, email_confirmed_at timestamptz, phone_confirmed_at timestamptz,
  raw_user_meta_data jsonb default '{}'::jsonb, raw_app_meta_data jsonb default '{}'::jsonb,
  confirmation_token text, recovery_token text, email_change_token_new text, email_change text,
  email_change_token_current text, phone_change text, phone_change_token text, reauthentication_token text,
  banned_until timestamptz, created_at timestamptz, updated_at timestamptz);
create table auth.identities (
  id uuid primary key default gen_random_uuid(), provider_id text not null, user_id uuid not null references auth.users (id),
  identity_data jsonb not null, provider text not null, last_sign_in_at timestamptz, created_at timestamptz,
  updated_at timestamptz, unique (provider_id, provider));
create table auth.sessions (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users (id));
create table auth.refresh_tokens (id bigserial primary key, user_id varchar(255),
  session_id uuid references auth.sessions (id) on delete cascade);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid $$;

create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint,
  allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id),
  name text, owner uuid, created_at timestamptz default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;

grant usage on schema auth, storage to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
