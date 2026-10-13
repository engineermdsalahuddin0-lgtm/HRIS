-- =============================================================================
-- Olympus HRIS — Platform (super) admins
--
-- Allow-listed emails become platform admins as soon as their email is
-- confirmed (never before, so nobody can claim the address by signing up
-- with it first). Accounts that already exist and are confirmed are promoted now.
-- =============================================================================

create table private.platform_admin_allowlist (
  email      text primary key check (email = lower(email)),
  created_at timestamptz not null default now()
);

insert into private.platform_admin_allowlist (email) values
  ('sarwar@gmail.com'),
  ('nabidbhuia313@gmail.com')
on conflict do nothing;

create or replace function private.promote_allowlisted_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email_confirmed_at is not null
     and exists (select 1 from private.platform_admin_allowlist where email = lower(new.email)) then
    insert into public.platform_admins (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end;
$$;

-- Runs after on_auth_user_created (triggers fire in name order), so the
-- user_profiles row already exists.
create trigger zz_promote_platform_admin
  after insert or update of email_confirmed_at on auth.users
  for each row execute function private.promote_allowlisted_admin();

-- Promote existing confirmed accounts.
insert into public.platform_admins (user_id)
select u.id
from auth.users u
join public.user_profiles p on p.id = u.id
where u.email_confirmed_at is not null
  and lower(u.email) in (select email from private.platform_admin_allowlist)
on conflict do nothing;

revoke all on table private.platform_admin_allowlist from public, anon, authenticated;
revoke all on function private.promote_allowlisted_admin() from public, anon, authenticated;

-- Who is a platform admin now (shown in the Results tab).
select u.email, pa.created_at as platform_admin_since
from public.platform_admins pa
join auth.users u on u.id = pa.user_id
order by u.email;
