-- =============================================================================
-- Onboarding process R6: selection decision, offer (maker-checker), rejection
-- email, pre-joining form (NID, photo, nominees, bank / wallet).
-- Module handbook: src/onboarding-process/architecture.md (sections 2, 5-8).
--
-- HR decides each interviewed applicant: selected (within the post's seats),
-- waitlisted or rejected (rejection email optional). HR prepares an offer
-- (salary template, gross, joining date, expiry, probation); someone with
-- offer.approve who did not prepare it approves (Admin by default). HR sends
-- it: the applicant gets a private link (/offer/<token>) to accept or decline.
-- Accepting opens the pre-joining form on the same link: personal details, NID,
-- nominees, salary account and a photo. NID and account numbers are encrypted
-- at once and never shown back (last 4 only); HR verifies or returns the form.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.interview_scores') is null then
    raise exception 'Apply 20261029000100_recruit_r5_messages_interviews.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('offer.approve', 'recruitment', 'Approve job offers (never one you prepared)', false)
on conflict (key) do nothing;

-- New template keys for R6 / R7.
alter table public.message_templates drop constraint message_templates_key_check;
alter table public.message_templates add constraint message_templates_key_check
  check (key in ('test_invite', 'interview_invite', 'rejection', 'offer', 'joining_feedback'));

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.candidate_decisions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  applicant_id  uuid not null,
  job_post_id   uuid not null,
  decision      text not null check (decision in ('selected', 'waitlist', 'rejected')),
  composite     numeric(6, 2),
  note          text check (note is null or char_length(note) <= 500),
  decided_by    uuid references public.user_profiles (id) default auth.uid(),
  created_at    timestamptz not null default now(),
  constraint candidate_decisions_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id)
);
create trigger candidate_decisions_append_only before update or delete on public.candidate_decisions
  for each row execute function private.history_append_only();

create table public.offers (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null,
  applicant_id       uuid not null,
  job_post_id        uuid not null,
  department_id      uuid not null,
  designation_id     uuid not null,
  office_id          uuid not null,
  employment_type    text not null check (employment_type in ('permanent', 'contract', 'probation', 'intern', 'part_time')),
  salary_template_id uuid not null,
  gross              numeric(12, 2) not null check (gross > 0 and gross <= 99999999),
  joining_date       date not null,
  expires_on         date not null,
  probation_months   smallint not null default 6 check (probation_months between 0 and 12),
  terms              text check (terms is null or char_length(terms) <= 3000),
  status             text not null default 'draft'
                     check (status in ('draft', 'approved', 'sent', 'accepted', 'declined', 'expired', 'withdrawn')),
  token_hash         text unique,
  approved_by        uuid references public.user_profiles (id),
  approved_at        timestamptz,
  approval_note      text check (approval_note is null or char_length(approval_note) <= 500),
  sent_at            timestamptz,
  responded_at       timestamptz,
  response_note      text check (response_note is null or char_length(response_note) <= 500),
  withdraw_reason    text check (withdraw_reason is null or char_length(withdraw_reason) <= 300),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint offers_org_id_id_uq unique (org_id, id),
  constraint offers_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint offers_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id),
  constraint offers_designation_fk foreign key (org_id, department_id, designation_id) references public.designations (org_id, department_id, id),
  constraint offers_office_fk foreign key (org_id, office_id) references public.offices (org_id, id),
  constraint offers_template_fk foreign key (salary_template_id) references public.salary_templates (id),
  constraint offers_dates check (expires_on <= joining_date)
);
create unique index offers_active_uq on public.offers (applicant_id) where status in ('draft', 'approved', 'sent', 'accepted');
create trigger set_row_meta before insert or update on public.offers
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.offers
  for each row execute function private.audit_row_change();

-- The pre-joining form. Holds personal data: no row audit (RPCs log ids and status); purged in R7.
create table public.prehire_records (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null,
  applicant_id       uuid not null,
  offer_id           uuid not null unique,
  status             text not null default 'pending' check (status in ('pending', 'submitted', 'returned', 'verified')),
  data               jsonb not null default '{}',
  nid_enc            bytea,
  nid_last4          text,
  payment_method     text check (payment_method in ('bank', 'mobile_wallet', 'cash')),
  bank_name          text,
  branch_name        text,
  routing_number     text,
  account_name       text,
  account_enc        bytea,
  wallet_provider    text,
  wallet_enc         bytea,
  number_last4       text,
  photo_path         text,
  photo_pending_path text,
  submitted_at       timestamptz,
  verified_by        uuid references public.user_profiles (id),
  verified_at        timestamptz,
  return_note        text check (return_note is null or char_length(return_note) <= 500),
  employee_id        uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint prehire_records_org_id_id_uq unique (org_id, id),
  constraint prehire_records_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint prehire_records_offer_fk foreign key (org_id, offer_id) references public.offers (org_id, id)
);

-- -----------------------------------------------------------------------------
-- Templates (rejection, offer) for every company
-- -----------------------------------------------------------------------------
create or replace function private.seed_r6_templates(p_org_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.message_templates (org_id, key, channel, subject, body) values
    (p_org_id, 'rejection', 'email', 'Your application for {job_title} — {company}',
     E'Dear {name},\n\nThank you for your interest in {job_title} at {company} and for the time you gave us.\n\n'
     || E'After careful review we have decided to go ahead with other candidates this time. We wish you every success.\n\n'
     || E'Best regards,\n{company}'),
    (p_org_id, 'offer', 'email', 'Offer for {job_title} — {company}',
     E'Dear {name},\n\nWe are happy to offer you the position of {job_title} at {company}.\n\n'
     || E'Monthly gross salary: {gross}\nJoining date: {joining_date}\n\nPlease read the offer and reply by {expires_on}:\n{offer_link}\n\n'
     || E'After accepting, fill in the pre-joining form on the same page (NID, photo, nominee and salary account).\n\nBest regards,\n{company}'),
    (p_org_id, 'offer', 'sms', null,
     '{company}: offer for {job_title}. Please reply by {expires_on}: {offer_link}'),
    (p_org_id, 'joining_feedback', 'email', 'Welcome to {company} — how was your first day?',
     E'Dear {name},\n\nWelcome to {company}! Please tell us how your recruitment and first day went. It takes two minutes:\n{feedback_link}\n\n'
     || E'Your answers help us treat every new colleague well.\n\nBest regards,\n{company}')
  on conflict (org_id, key, channel) do nothing
$$;

create or replace function private.seed_message_templates(p_org_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.message_templates (org_id, key, channel, subject, body) values
    (p_org_id, 'test_invite', 'email', 'Online test for {job_title} — {company}',
     E'Dear {name},\n\nThank you for applying for {job_title} at {company}. Please take the online test using your personal link:\n\n{test_link}\n\n'
     || E'The test takes {duration} minutes and can be taken only once. The clock starts when you press Start. The link is valid until {valid_until}.\n\n'
     || E'Best regards,\n{company}'),
    (p_org_id, 'test_invite', 'sms', null,
     '{company}: online test for {job_title}. Open {test_link} ({duration} min, once, until {valid_until}).'),
    (p_org_id, 'interview_invite', 'email', 'Interview for {job_title} — {company}',
     E'Dear {name},\n\nWe are pleased to invite you to an interview for {job_title} at {company}.\n\n'
     || E'When: {interview_time}\nWhere: {interview_place}\n\nBefore the interview, please fill in this short form:\n{form_link}\n\n'
     || E'Please bring your original certificates and a copy of your NID.\n\nBest regards,\n{company}'),
    (p_org_id, 'interview_invite', 'sms', null,
     '{company}: interview for {job_title} on {interview_time} at {interview_place}. Please fill the form: {form_link}')
  on conflict (org_id, key, channel) do nothing;
  select private.seed_r6_templates(p_org_id);
$$;

select private.seed_message_templates(id) from public.organizations;

create or replace function public.save_message_template(p_key text, p_channel text, p_subject text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  if p_key not in ('test_invite', 'interview_invite', 'rejection', 'offer', 'joining_feedback') or p_channel not in ('email', 'sms') then
    raise exception 'Unknown template' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 5 and (case when p_channel = 'sms' then 480 else 5000 end) then
    raise exception 'The message is empty or too long' using errcode = '22023';
  end if;
  if p_channel = 'email' and char_length(btrim(coalesce(p_subject, ''))) not between 3 and 200 then
    raise exception 'Give a subject' using errcode = '22023';
  end if;
  insert into public.message_templates (org_id, key, channel, subject, body)
  values (private.current_org_id(), p_key, p_channel, case when p_channel = 'email' then btrim(p_subject) end, btrim(p_body))
  on conflict (org_id, key, channel) do update set subject = excluded.subject, body = excluded.body;
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: pre-joining photos (private)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('prehire-files', 'prehire-files', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Anon may upload exactly the photo path the form asked for (prehire-files/{org}/{applicant}/photo-xxxx.ext).
create or replace function policy_checks.prehire_photo_pending(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.prehire_records r
                 where r.photo_pending_path = p_name and r.status in ('pending', 'returned'))
$$;

create or replace function private.prehire_file_access(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' then
    return false;
  end if;
  return v_parts[1]::uuid = private.current_org_id() and private.has_permission('recruit.manage')
     and exists (select 1 from public.prehire_records r where r.org_id = v_parts[1]::uuid and r.applicant_id::text = v_parts[2]);
end;
$$;

revoke all on function policy_checks.prehire_photo_pending(text), private.prehire_file_access(text) from public, anon;
grant execute on function policy_checks.prehire_photo_pending(text) to anon, authenticated;
grant execute on function private.prehire_file_access(text) to authenticated;

drop policy if exists olympus_prehire_upload on storage.objects;
drop policy if exists olympus_prehire_select on storage.objects;
drop policy if exists olympus_prehire_delete on storage.objects;
create policy olympus_prehire_upload on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'prehire-files' and policy_checks.prehire_photo_pending(name));
create policy olympus_prehire_select on storage.objects for select to authenticated
  using (bucket_id = 'prehire-files' and private.prehire_file_access(name));
create policy olympus_prehire_delete on storage.objects for delete to authenticated
  using (bucket_id = 'prehire-files' and private.prehire_file_access(name));

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.money_text(p numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'Tk ' || to_char(p, 'FM99,99,99,990')
$$;

-- Applicants holding or heading for a seat of the post.
create or replace function private.post_seats_taken(p_job_post_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.applicants a
  where a.job_post_id = p_job_post_id and a.purged_at is null
    and a.status in ('selected', 'offer_sent', 'offer_accepted', 'prejoining_done', 'joined')
$$;

create or replace function private.offer_by_token(p_token text)
returns public.offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.offers;
begin
  select * into v_o from public.offers
   where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and status in ('sent', 'accepted', 'declined', 'expired');
  if not found then
    raise exception 'This offer link is not valid' using errcode = 'P0002';
  end if;
  if v_o.status = 'sent' and v_o.expires_on < private.org_today(v_o.org_id) then
    update public.offers set status = 'expired' where id = v_o.id returning * into v_o;
    update public.applicants set status = 'selected' where id = v_o.applicant_id and status = 'offer_sent';
    perform private.applicant_event(v_o.applicant_id, 'offer_expired', 'offer_sent', 'selected');
  end if;
  return v_o;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: decisions
-- -----------------------------------------------------------------------------
-- p_decision: selected | waitlist | rejected. p_send: queue the rejection email.
create or replace function public.decide_candidate(p_applicant_id uuid, p_decision text, p_note text default null,
                                                   p_send boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app    public.applicants;
  v_post   public.job_posts;
  v_comp   numeric;
  v_to     text;
  v_queued integer := 0;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null for update;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  select * into v_post from public.job_posts where id = v_app.job_post_id;
  if p_decision not in ('selected', 'waitlist', 'rejected') then
    raise exception 'Decision is selected, waitlist or rejected' using errcode = '22023';
  end if;
  if p_decision in ('selected', 'waitlist') and v_app.status <> 'interviewed' then
    raise exception 'Only an interviewed applicant can be %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'rejected' and v_app.status not in ('shortlisted', 'test_invited', 'test_done', 'written_done',
                                                      'interview_scheduled', 'interviewed') then
    raise exception 'An applicant who is % cannot be rejected here', v_app.status using errcode = '22023';
  end if;
  if p_decision = 'selected' and private.post_seats_taken(v_post.id) >= v_post.seats then
    raise exception 'All % seat(s) of this post are taken' , v_post.seats using errcode = '23514';
  end if;

  select (r -> 'figures' ->> 'composite')::numeric into v_comp
  from jsonb_array_elements(public.get_candidate_results(v_post.id) -> 'rows') r where r ->> 'applicant_id' = v_app.id::text;
  v_to := case p_decision when 'selected' then 'selected' when 'rejected' then 'rejected' else v_app.status end;
  update public.applicants set status = v_to where id = v_app.id;
  if p_decision = 'rejected' then
    update public.assessment_invites set status = 'cancelled' where applicant_id = v_app.id and status = 'invited';
    update public.interview_schedules set status = 'cancelled', cancel_reason = 'Not selected'
     where applicant_id = v_app.id and status = 'scheduled';
    if coalesce(p_send, false) then
      v_queued := private.queue_message(v_app.id, 'rejection', '{}'::jsonb);
    end if;
  end if;
  insert into public.candidate_decisions (org_id, applicant_id, job_post_id, decision, composite, note)
  values (v_app.org_id, v_app.id, v_post.id, p_decision, v_comp, left(nullif(btrim(coalesce(p_note, '')), ''), 500));
  perform private.applicant_event(v_app.id, 'decided_' || p_decision, v_app.status, v_to);
  return jsonb_build_object('status', v_to, 'composite', v_comp, 'queued', v_queued);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: offers (HR prepares and sends; offer.approve approves, never the preparer)
-- -----------------------------------------------------------------------------
create or replace function public.get_offer_context(p_applicant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_app  public.applicants;
  v_post public.job_posts;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  select * into v_post from public.job_posts where id = v_app.job_post_id;
  return jsonb_build_object(
    'applicant', jsonb_build_object('id', v_app.id, 'full_name', v_app.full_name, 'status', v_app.status),
    'post', jsonb_build_object('id', v_post.id, 'title', v_post.title, 'employment_type', v_post.employment_type,
                               'show_salary', v_post.show_salary, 'salary_min', v_post.salary_min, 'salary_max', v_post.salary_max,
                               'department_name', (select d.name from public.departments d where d.id = v_post.department_id),
                               'designation_name', (select ds.name from public.designations ds where ds.id = v_post.designation_id)),
    'expected_salary', (select (f.answers ->> 'expected_salary')::numeric from public.preinterview_forms f
                        where f.applicant_id = v_app.id order by f.created_at desc limit 1),
    'notice_period_days', (select (f.answers ->> 'notice_period_days')::integer from public.preinterview_forms f
                           where f.applicant_id = v_app.id order by f.created_at desc limit 1),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) order by t.name)
                           from public.salary_templates t where t.org_id = v_app.org_id and t.status = 'active'), '[]'::jsonb),
    'offices', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'branch_name', b.name) order by b.name, o.name)
                         from public.offices o join public.branches b on b.id = o.branch_id
                         where o.org_id = v_app.org_id and o.status = 'active'), '[]'::jsonb),
    'default_office_id', (select v.office_id from public.vacancies v where v.id = v_post.vacancy_id),
    'today', private.org_today(v_app.org_id));
end;
$$;

-- p: salary_template_id, gross, joining_date, expires_on, office_id, probation_months, employment_type, terms.
-- Creates the draft, or updates the applicant's current draft (back to draft after "send back").
create or replace function public.prepare_offer(p_applicant_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app     public.applicants;
  v_post    public.job_posts;
  v_today   date;
  v_gross   numeric := (private.jtext(p, 'gross'))::numeric;
  v_join    date := (private.jtext(p, 'joining_date'))::date;
  v_expires date := (private.jtext(p, 'expires_on'))::date;
  v_office  uuid := (private.jtext(p, 'office_id'))::uuid;
  v_tpl     uuid := (private.jtext(p, 'salary_template_id'))::uuid;
  v_prob    integer := coalesce((private.jtext(p, 'probation_months'))::integer, 6);
  v_type    text;
  v_id      uuid;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null for update;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  if v_app.status <> 'selected' then
    raise exception 'Select the applicant first (now %)', v_app.status using errcode = '22023';
  end if;
  select * into v_post from public.job_posts where id = v_app.job_post_id;
  v_today := private.org_today(v_app.org_id);
  v_type := coalesce(private.jtext(p, 'employment_type'), v_post.employment_type);
  if v_gross is null or v_gross <= 0 or v_gross > 99999999 then
    raise exception 'Enter the monthly gross salary' using errcode = '22023';
  end if;
  if v_join is null or v_join < v_today then
    raise exception 'The joining date cannot be in the past' using errcode = '22023';
  end if;
  if v_expires is null or v_expires < v_today or v_expires > v_join then
    raise exception 'The reply date must be between today and the joining date' using errcode = '22023';
  end if;
  if not exists (select 1 from public.salary_templates t where t.id = v_tpl and t.org_id = v_app.org_id and t.status = 'active') then
    raise exception 'Choose a salary template' using errcode = '22023';
  end if;
  if not exists (select 1 from public.offices o where o.id = v_office and o.org_id = v_app.org_id and o.status = 'active') then
    raise exception 'Choose the office' using errcode = '22023';
  end if;
  if v_prob not between 0 and 12 then
    raise exception 'Probation is 0 to 12 months' using errcode = '22023';
  end if;
  if v_type not in ('permanent', 'contract', 'probation', 'intern', 'part_time') then
    raise exception 'Unknown employment type' using errcode = '22023';
  end if;

  select id into v_id from public.offers where applicant_id = v_app.id and status = 'draft' for update;
  if v_id is not null then
    update public.offers
       set salary_template_id = v_tpl, gross = v_gross, joining_date = v_join, expires_on = v_expires, office_id = v_office,
           probation_months = v_prob, employment_type = v_type, terms = left(nullif(btrim(coalesce(p ->> 'terms', '')), ''), 3000)
     where id = v_id;
    return v_id;
  end if;
  if exists (select 1 from public.offers where applicant_id = v_app.id and status in ('approved', 'sent', 'accepted')) then
    raise exception 'This applicant already has an offer in progress' using errcode = '23505';
  end if;
  insert into public.offers (org_id, applicant_id, job_post_id, department_id, designation_id, office_id, employment_type,
                             salary_template_id, gross, joining_date, expires_on, probation_months, terms)
  values (v_app.org_id, v_app.id, v_post.id, v_post.department_id, v_post.designation_id, v_office, v_type, v_tpl, v_gross,
          v_join, v_expires, v_prob, left(nullif(btrim(coalesce(p ->> 'terms', '')), ''), 3000))
  returning id into v_id;
  perform private.applicant_event(v_app.id, 'offer_prepared', v_app.status, v_app.status);
  return v_id;
end;
$$;

-- p_decision: approve | send_back (note required).
create or replace function public.decide_offer(p_offer_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.offers;
begin
  perform private.require_permission('offer.approve');
  select * into v_o from public.offers where id = p_offer_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  if v_o.status <> 'draft' then
    raise exception 'Only a draft offer can be approved (now %)', v_o.status using errcode = '22023';
  end if;
  if v_o.created_by = auth.uid() then
    raise exception 'Someone other than the person who prepared this offer must approve it' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'send_back') then
    raise exception 'Decision is approve or send back' using errcode = '22023';
  end if;
  if p_decision = 'send_back' and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  update public.offers
     set status = case when p_decision = 'approve' then 'approved' else 'draft' end,
         approved_by = case when p_decision = 'approve' then auth.uid() end,
         approved_at = case when p_decision = 'approve' then now() end,
         approval_note = left(nullif(btrim(coalesce(p_note, '')), ''), 500)
   where id = v_o.id;
  perform private.applicant_event(v_o.applicant_id, 'offer_' || case when p_decision = 'approve' then 'approved' else 'sent_back' end, null, null);
end;
$$;

-- Sends an approved offer: a private link by email (and SMS when on). Returns the link once.
create or replace function public.send_offer(p_offer_id uuid, p_base_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o      public.offers;
  v_base   text := private.clean_base_url(p_base_url);
  v_token  text := encode(extensions.gen_random_bytes(24), 'hex');
  v_queued integer;
begin
  perform private.require_permission('recruit.manage');
  select * into v_o from public.offers where id = p_offer_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  if v_o.status not in ('approved', 'sent') then
    raise exception 'The offer must be approved first (now %)', v_o.status using errcode = '22023';
  end if;
  if v_o.expires_on < private.org_today(v_o.org_id) then
    raise exception 'The reply date has passed; prepare a new offer' using errcode = '22023';
  end if;
  update public.offers set status = 'sent', sent_at = now(), token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex')
   where id = v_o.id;
  update public.applicants set status = 'offer_sent' where id = v_o.applicant_id and status = 'selected';
  v_queued := private.queue_message(v_o.applicant_id, 'offer', jsonb_build_object(
    'offer_link', v_base || '/offer/' || v_token, 'gross', private.money_text(v_o.gross),
    'joining_date', to_char(v_o.joining_date, 'DD Mon YYYY'), 'expires_on', to_char(v_o.expires_on, 'DD Mon YYYY')));
  perform private.applicant_event(v_o.applicant_id, 'offer_sent', 'selected', 'offer_sent');
  return jsonb_build_object('queued', v_queued, 'offer_link', v_base || '/offer/' || v_token);
end;
$$;

create or replace function public.withdraw_offer(p_offer_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.offers;
begin
  perform private.require_permission('recruit.manage');
  select * into v_o from public.offers where id = p_offer_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  if v_o.status not in ('draft', 'approved', 'sent') then
    raise exception 'A % offer cannot be withdrawn', v_o.status using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  update public.offers set status = 'withdrawn', withdraw_reason = left(btrim(p_reason), 300), token_hash = null where id = v_o.id;
  update public.applicants set status = 'selected' where id = v_o.applicant_id and status = 'offer_sent';
  perform private.applicant_event(v_o.applicant_id, 'offer_withdrawn', null, 'selected');
end;
$$;

-- -----------------------------------------------------------------------------
-- API: the offer page and the pre-joining form (no login; the offer link is the key)
-- -----------------------------------------------------------------------------
create or replace function private.prehire_state(p_offer public.offers)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('status', r.status, 'data', r.data, 'nid_last4', r.nid_last4,
                            'payment_method', r.payment_method, 'bank_name', r.bank_name, 'branch_name', r.branch_name,
                            'routing_number', r.routing_number, 'account_name', r.account_name,
                            'wallet_provider', r.wallet_provider, 'number_last4', r.number_last4,
                            'has_photo', r.photo_path is not null, 'return_note', r.return_note, 'submitted_at', r.submitted_at)
  from public.prehire_records r where r.offer_id = p_offer.id
$$;

create or replace function public.get_offer(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.offers := private.offer_by_token(p_token);
begin
  return jsonb_build_object(
    'status', v_o.status,
    'organization', (select o.name from public.organizations o where o.id = v_o.org_id),
    'full_name', (select a.full_name from public.applicants a where a.id = v_o.applicant_id),
    'designation', (select ds.name from public.designations ds where ds.id = v_o.designation_id),
    'department', (select d.name from public.departments d where d.id = v_o.department_id),
    'office', (select o.name || ', ' || b.name from public.offices o join public.branches b on b.id = o.branch_id where o.id = v_o.office_id),
    'employment_type', v_o.employment_type, 'gross', v_o.gross, 'joining_date', v_o.joining_date, 'expires_on', v_o.expires_on,
    'probation_months', v_o.probation_months, 'terms', v_o.terms, 'responded_at', v_o.responded_at,
    'prejoining', case when v_o.status = 'accepted' then private.prehire_state(v_o) end);
end;
$$;

-- p_answer: accept | decline.
create or replace function public.respond_offer(p_token text, p_answer text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.offers := private.offer_by_token(p_token);
begin
  if v_o.status <> 'sent' then
    raise exception 'This offer is %', v_o.status using errcode = '22023';
  end if;
  if p_answer not in ('accept', 'decline') then
    raise exception 'Answer accept or decline' using errcode = '22023';
  end if;
  update public.offers set status = case when p_answer = 'accept' then 'accepted' else 'declined' end, responded_at = now(),
         response_note = left(nullif(btrim(coalesce(p_note, '')), ''), 500)
   where id = v_o.id;
  update public.applicants set status = case when p_answer = 'accept' then 'offer_accepted' else 'offer_declined' end
   where id = v_o.applicant_id;
  if p_answer = 'accept' then
    insert into public.prehire_records (org_id, applicant_id, offer_id) values (v_o.org_id, v_o.applicant_id, v_o.id)
    on conflict (offer_id) do nothing;
  end if;
  perform private.applicant_event(v_o.applicant_id, case when p_answer = 'accept' then 'offer_accepted' else 'offer_declined' end, 'offer_sent',
                                  case when p_answer = 'accept' then 'offer_accepted' else 'offer_declined' end);
  return public.get_offer(p_token);
end;
$$;

-- Where to upload the photo (jpg / png / webp); the next submit picks it up.
create or replace function public.start_prejoining_photo(p_token text, p_ext text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o    public.offers := private.offer_by_token(p_token);
  v_path text;
begin
  if v_o.status <> 'accepted' then
    raise exception 'Accept the offer first' using errcode = '22023';
  end if;
  if coalesce(p_ext, '') not in ('jpg', 'png', 'webp') then
    raise exception 'The photo must be JPG, PNG or WEBP' using errcode = '22023';
  end if;
  v_path := v_o.org_id || '/' || v_o.applicant_id || '/photo-' || left(encode(extensions.gen_random_bytes(6), 'hex'), 10) || '.' || p_ext;
  update public.prehire_records set photo_pending_path = v_path
   where offer_id = v_o.id and status in ('pending', 'returned');
  if not found then
    raise exception 'The form is already with HR' using errcode = '22023';
  end if;
  return v_path;
end;
$$;

-- p: father_name, mother_name, date_of_birth, gender, marital_status, blood_group, religion, present_address,
--    permanent_address, emergency_name, emergency_phone, nominees [{name, relation, phone}],
--    nid_number (write-only), payment_method (bank | mobile_wallet | cash), bank_name, branch_name, routing_number,
--    account_name, account_number (write-only), wallet_provider, wallet_number (write-only)
create or replace function public.submit_prejoining(p_token text, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o       public.offers := private.offer_by_token(p_token);
  v_r       public.prehire_records;
  v_nid     text := nullif(regexp_replace(coalesce(p ->> 'nid_number', ''), '\s', '', 'g'), '');
  v_method  text := private.jtext(p, 'payment_method');
  v_account text := nullif(regexp_replace(coalesce(p ->> 'account_number', ''), '[\s-]', '', 'g'), '');
  v_wallet  text := nullif(btrim(coalesce(p ->> 'wallet_number', '')), '');
  v_dob     date := (private.jtext(p, 'date_of_birth'))::date;
  v_nominee jsonb := '[]'::jsonb;
  v_n       jsonb;
  v_photo   text;
begin
  if v_o.status <> 'accepted' then
    raise exception 'Accept the offer first' using errcode = '22023';
  end if;
  select * into v_r from public.prehire_records where offer_id = v_o.id for update;
  if v_r.status not in ('pending', 'returned') then
    raise exception 'The form is already with HR' using errcode = '22023';
  end if;
  if v_dob is null or v_dob > private.org_today(v_o.org_id) - interval '18 years' or v_dob < date '1940-01-01' then
    raise exception 'Enter the date of birth (18 years or older)' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p ->> 'father_name', ''))) < 2 or char_length(btrim(coalesce(p ->> 'mother_name', ''))) < 2 then
    raise exception 'Enter the father''s and mother''s names' using errcode = '23502';
  end if;
  if char_length(btrim(coalesce(p ->> 'present_address', ''))) < 5 or char_length(btrim(coalesce(p ->> 'permanent_address', ''))) < 5 then
    raise exception 'Enter the present and permanent addresses' using errcode = '23502';
  end if;
  if coalesce(p ->> 'gender', '') not in ('', 'male', 'female', 'other') then
    raise exception 'Unknown gender' using errcode = '22023';
  end if;
  if v_nid is not null and v_nid !~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$' then
    raise exception 'The NID number has 10, 13 or 17 digits' using errcode = '22023';
  end if;
  if v_nid is null and v_r.nid_enc is null then
    raise exception 'Enter the NID number' using errcode = '23502';
  end if;
  if jsonb_typeof(p -> 'nominees') is distinct from 'array' or jsonb_array_length(p -> 'nominees') not between 1 and 5 then
    raise exception 'Add 1 to 5 nominees' using errcode = '23502';
  end if;
  for v_n in select * from jsonb_array_elements(p -> 'nominees') loop
    if char_length(btrim(coalesce(v_n ->> 'name', ''))) < 2 or char_length(btrim(coalesce(v_n ->> 'relation', ''))) < 2 then
      raise exception 'Each nominee needs a name and a relation' using errcode = '23502';
    end if;
    v_nominee := v_nominee || jsonb_build_array(jsonb_build_object('name', left(btrim(v_n ->> 'name'), 150),
      'relation', left(btrim(v_n ->> 'relation'), 50), 'phone', private.normalize_bd_phone(nullif(btrim(coalesce(v_n ->> 'phone', '')), ''))));
  end loop;
  if v_method not in ('bank', 'mobile_wallet', 'cash') then
    raise exception 'Choose how you want to be paid' using errcode = '23502';
  end if;
  if v_method = 'bank' then
    if char_length(btrim(coalesce(p ->> 'bank_name', ''))) < 2 then
      raise exception 'Enter the bank name' using errcode = '23502';
    end if;
    if v_account is not null and v_account !~ '^[0-9]{6,20}$' then
      raise exception 'The account number must be 6 to 20 digits' using errcode = '22023';
    end if;
    if v_account is null and (v_r.account_enc is null or v_r.payment_method <> 'bank') then
      raise exception 'Enter the account number' using errcode = '23502';
    end if;
    if private.jtext(p, 'routing_number') is not null and private.jtext(p, 'routing_number') !~ '^[0-9]{9}$' then
      raise exception 'The routing number has 9 digits' using errcode = '22023';
    end if;
  elsif v_method = 'mobile_wallet' then
    if coalesce(p ->> 'wallet_provider', '') not in ('bkash', 'nagad', 'rocket', 'upay', 'other') then
      raise exception 'Choose the wallet' using errcode = '23502';
    end if;
    if v_wallet is not null then
      v_wallet := private.normalize_bd_phone(v_wallet);
    elsif v_r.wallet_enc is null or v_r.payment_method <> 'mobile_wallet' then
      raise exception 'Enter the wallet number' using errcode = '23502';
    end if;
  end if;

  -- The photo: the pending upload if it arrived, else the one already on file.
  if v_r.photo_pending_path is not null
     and exists (select 1 from storage.objects o where o.bucket_id = 'prehire-files' and o.name = v_r.photo_pending_path) then
    v_photo := v_r.photo_pending_path;
  else
    v_photo := v_r.photo_path;
  end if;
  if v_photo is null then
    raise exception 'Upload your photo' using errcode = '23502';
  end if;

  update public.prehire_records
     set data = jsonb_build_object(
           'father_name', left(btrim(p ->> 'father_name'), 150), 'mother_name', left(btrim(p ->> 'mother_name'), 150),
           'date_of_birth', v_dob, 'gender', nullif(p ->> 'gender', ''), 'marital_status', nullif(left(p ->> 'marital_status', 20), ''),
           'blood_group', nullif(left(p ->> 'blood_group', 5), ''), 'religion', nullif(left(p ->> 'religion', 30), ''),
           'present_address', left(btrim(p ->> 'present_address'), 300), 'permanent_address', left(btrim(p ->> 'permanent_address'), 300),
           'emergency_name', nullif(left(btrim(coalesce(p ->> 'emergency_name', '')), 150), ''),
           'emergency_phone', private.normalize_bd_phone(nullif(btrim(coalesce(p ->> 'emergency_phone', '')), '')),
           'nominees', v_nominee),
         nid_enc = coalesce(private.encrypt_secret(v_nid), nid_enc), nid_last4 = coalesce(right(v_nid, 4), nid_last4),
         payment_method = v_method,
         bank_name = case when v_method = 'bank' then left(btrim(p ->> 'bank_name'), 120) end,
         branch_name = case when v_method = 'bank' then nullif(left(btrim(coalesce(p ->> 'branch_name', '')), 120), '') end,
         routing_number = case when v_method = 'bank' then private.jtext(p, 'routing_number') end,
         account_name = nullif(left(btrim(coalesce(p ->> 'account_name', '')), 150), ''),
         account_enc = case when v_method = 'bank' then coalesce(private.encrypt_secret(v_account), account_enc) end,
         wallet_provider = case when v_method = 'mobile_wallet' then p ->> 'wallet_provider' end,
         wallet_enc = case when v_method = 'mobile_wallet' then coalesce(private.encrypt_secret(v_wallet), wallet_enc) end,
         number_last4 = case v_method when 'bank' then coalesce(right(v_account, 4), number_last4)
                                      when 'mobile_wallet' then coalesce(right(v_wallet, 4), number_last4) end,
         photo_path = v_photo, photo_pending_path = null, status = 'submitted', submitted_at = now(), updated_at = now()
   where id = v_r.id;
  update public.applicants set status = 'prejoining_done' where id = v_o.applicant_id and status = 'offer_accepted';
  perform private.applicant_event(v_o.applicant_id, 'prejoining_submitted', 'offer_accepted', 'prejoining_done');
  perform private.write_audit(v_o.org_id, 'prehire.submitted', 'prehire_records', v_r.id, null, jsonb_build_object('status', 'submitted'));
  return private.prehire_state((select o from public.offers o where o.id = v_o.id));
end;
$$;

-- -----------------------------------------------------------------------------
-- API: HR views offers and pre-joining forms
-- -----------------------------------------------------------------------------
create or replace function public.list_offers(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  perform private.require_permission('recruit.manage');
  if not exists (select 1 from public.job_posts where id = p_job_post_id and org_id = v_org_id) then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'can', jsonb_build_object('approve', private.has_permission('offer.approve'), 'user_id', auth.uid()),
    'seats', (select jp.seats from public.job_posts jp where jp.id = p_job_post_id),
    'seats_taken', private.post_seats_taken(p_job_post_id),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'applicant_id', a.id, 'full_name', a.full_name, 'email', a.email, 'status', a.status,
        'decision', (select jsonb_build_object('decision', d.decision, 'composite', d.composite, 'note', d.note, 'created_at', d.created_at)
                     from public.candidate_decisions d where d.applicant_id = a.id order by d.created_at desc limit 1),
        'offer', (select to_jsonb(o) - array['org_id', 'token_hash', 'updated_by']
                         || jsonb_build_object('template_name', t.name, 'office_name', off.name,
                                               'prepared_by_name', pu.full_name, 'approved_by_name', au.full_name)
                  from public.offers o
                  join public.salary_templates t on t.id = o.salary_template_id
                  join public.offices off on off.id = o.office_id
                  left join public.user_profiles pu on pu.id = o.created_by
                  left join public.user_profiles au on au.id = o.approved_by
                  where o.applicant_id = a.id order by o.created_at desc limit 1),
        'prehire', (select jsonb_build_object('id', r.id, 'status', r.status, 'submitted_at', r.submitted_at, 'employee_id', r.employee_id)
                    from public.prehire_records r where r.applicant_id = a.id order by r.created_at desc limit 1))
        order by a.full_name)
      from public.applicants a
      where a.job_post_id = p_job_post_id and a.purged_at is null
        and (a.status in ('selected', 'offer_sent', 'offer_accepted', 'offer_declined', 'prejoining_done', 'joined')
             or exists (select 1 from public.candidate_decisions d where d.applicant_id = a.id and d.decision = 'waitlist'
                        and a.status = 'interviewed'))), '[]'::jsonb));
end;
$$;

create or replace function public.get_prehire(p_prehire_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.prehire_records;
begin
  perform private.require_permission('recruit.manage');
  select * into v_r from public.prehire_records where id = p_prehire_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Pre-joining form not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object('id', v_r.id, 'status', v_r.status, 'data', v_r.data,
                            'nid', private.mask_number(v_r.nid_last4), 'payment_method', v_r.payment_method,
                            'bank_name', v_r.bank_name, 'branch_name', v_r.branch_name, 'routing_number', v_r.routing_number,
                            'account_name', v_r.account_name, 'wallet_provider', v_r.wallet_provider,
                            'number', private.mask_number(v_r.number_last4), 'photo_path', v_r.photo_path,
                            'submitted_at', v_r.submitted_at, 'verified_at', v_r.verified_at, 'return_note', v_r.return_note,
                            'employee_id', v_r.employee_id,
                            'applicant', (select jsonb_build_object('full_name', a.full_name, 'email', a.email, 'phone', a.phone)
                                          from public.applicants a where a.id = v_r.applicant_id));
end;
$$;

-- p_decision: verify | return (note required: what to fix).
create or replace function public.verify_prehire(p_prehire_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r public.prehire_records;
begin
  perform private.require_permission('recruit.manage');
  select * into v_r from public.prehire_records where id = p_prehire_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Pre-joining form not found' using errcode = 'P0002';
  end if;
  if v_r.status <> 'submitted' then
    raise exception 'Only a submitted form can be checked (now %)', v_r.status using errcode = '22023';
  end if;
  if p_decision not in ('verify', 'return') then
    raise exception 'Decision is verify or return' using errcode = '22023';
  end if;
  if p_decision = 'return' and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Tell the applicant what to fix (at least 5 characters)' using errcode = '23502';
  end if;
  update public.prehire_records
     set status = case when p_decision = 'verify' then 'verified' else 'returned' end,
         verified_by = case when p_decision = 'verify' then auth.uid() end,
         verified_at = case when p_decision = 'verify' then now() end,
         return_note = case when p_decision = 'return' then left(btrim(p_note), 500) end, updated_at = now()
   where id = v_r.id;
  if p_decision = 'return' then
    update public.applicants set status = 'offer_accepted' where id = v_r.applicant_id and status = 'prejoining_done';
  end if;
  perform private.applicant_event(v_r.applicant_id, 'prejoining_' || case when p_decision = 'verify' then 'verified' else 'returned' end, null, null);
  perform private.write_audit(v_r.org_id, 'prehire.' || p_decision, 'prehire_records', v_r.id, null, null);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.candidate_decisions enable row level security;
alter table public.offers              enable row level security;
alter table public.prehire_records     enable row level security;
revoke all on table public.candidate_decisions, public.offers, public.prehire_records from anon, authenticated;

revoke all on function
  public.save_message_template(text, text, text, text), public.decide_candidate(uuid, text, text, boolean),
  public.get_offer_context(uuid), public.prepare_offer(uuid, jsonb), public.decide_offer(uuid, text, text),
  public.send_offer(uuid, text), public.withdraw_offer(uuid, text), public.get_offer(text), public.respond_offer(text, text, text),
  public.start_prejoining_photo(text, text), public.submit_prejoining(text, jsonb), public.list_offers(uuid),
  public.get_prehire(uuid), public.verify_prehire(uuid, text, text)
from public, anon;
grant execute on function
  public.save_message_template(text, text, text, text), public.decide_candidate(uuid, text, text, boolean),
  public.get_offer_context(uuid), public.prepare_offer(uuid, jsonb), public.decide_offer(uuid, text, text),
  public.send_offer(uuid, text), public.withdraw_offer(uuid, text), public.list_offers(uuid),
  public.get_prehire(uuid), public.verify_prehire(uuid, text, text)
to authenticated;
grant execute on function
  public.get_offer(text), public.respond_offer(text, text, text), public.start_prejoining_photo(text, text),
  public.submit_prejoining(text, jsonb)
to anon, authenticated;

revoke all on function
  private.seed_r6_templates(uuid), private.seed_message_templates(uuid), private.money_text(numeric),
  private.post_seats_taken(uuid), private.offer_by_token(text), private.prehire_state(public.offers)
from public, anon, authenticated;
