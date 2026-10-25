-- =============================================================================
-- Onboarding process R5: messages (email now, SMS coded but off), pre-interview
-- form, interviewer kit, panel scoring, composite result.
-- Module handbook: src/onboarding-process/architecture.md (sections 2, 5-9).
--
-- Messages: templates per company (placeholders like {name}); sending a test
-- link or an interview invitation queues one email (and an SMS when the SMS
-- gateway is switched on). The Edge Function recruit-notify sends the queue
-- with the company's provider (Resend for email; a generic HTTP adapter for
-- Bangladeshi SMS gateways). Provider keys: Admin only, write-only, encrypted.
-- Pre-interview form: a private link (/f/<token>) in the interview email;
-- the applicant confirms attendance, notice period, expected salary.
-- Interviewer kit: any employee on the panel sees the applicant's screening,
-- test results and form, suggested questions, and scores 1-5 in five
-- categories (confidence included). Other interviewers' scores stay hidden
-- until one has submitted. When the whole panel has scored, the interview is
-- done and the applicant "interviewed".
-- Composite = sum(weight x component %) / sum(weights of the components
-- present); interview % = (panel mean - 1) / 4 x 100; spread flag when the
-- interviewers' means differ by more than 1.5. HR decides in R6.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.interview_schedules') is null then
    raise exception 'Apply 20261028000100_recruit_r4_tests_interviews.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
-- Email / SMS provider per company. Keys are write-only; no row audit (the RPCs log the event).
create table public.org_messaging (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  channel      text not null check (channel in ('email', 'sms')),
  provider     text not null check (provider in ('resend', 'http')),
  enabled      boolean not null default false,
  config       jsonb not null default '{}',
  secret_enc   bytea,
  secret_last4 text,
  tested_at    timestamptz,
  test_status  text check (test_status is null or test_status in ('ok', 'failed')),
  test_message text check (test_message is null or char_length(test_message) <= 300),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint org_messaging_channel_uq unique (org_id, channel),
  constraint org_messaging_provider check ((channel = 'email' and provider = 'resend') or (channel = 'sms' and provider = 'http'))
);
create trigger set_row_meta before insert or update on public.org_messaging
  for each row execute function private.set_row_meta();

create table public.message_templates (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  key        text not null check (key in ('test_invite', 'interview_invite', 'rejection', 'offer')),
  channel    text not null check (channel in ('email', 'sms')),
  subject    text check (subject is null or char_length(subject) <= 200),
  body       text not null check (char_length(body) between 5 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  constraint message_templates_uq unique (org_id, key, channel),
  constraint message_templates_subject check (channel = 'sms' or subject is not null)
);
select private.attach_standard_triggers('public.message_templates');

-- The outbox. Bodies hold names and links: no row audit; removed by the purge (R7).
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null,
  applicant_id uuid not null,
  job_post_id  uuid not null,
  template_key text not null,
  channel      text not null check (channel in ('email', 'sms')),
  to_address   text not null,
  subject      text,
  body         text not null,
  status       text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed')),
  provider_ref text,
  error        text check (error is null or char_length(error) <= 500),
  attempts     smallint not null default 0,
  claimed_at   timestamptz,
  sent_at      timestamptz,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id) default auth.uid(),
  constraint notifications_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint notifications_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id)
);
create index notifications_queue_idx on public.notifications (org_id, status, created_at);
create index notifications_post_idx on public.notifications (job_post_id, created_at);

create table public.preinterview_forms (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null,
  applicant_id uuid not null,
  interview_id uuid not null unique references public.interview_schedules (id),
  token_hash   text not null unique,
  expires_at   timestamptz not null,
  answers      jsonb,
  submitted_at timestamptz,
  created_at   timestamptz not null default now(),
  constraint preinterview_forms_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id)
);

create table public.interview_scores (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  interview_id   uuid not null references public.interview_schedules (id),
  applicant_id   uuid not null,
  employee_id    uuid not null,
  scores         jsonb not null,
  mean           numeric(4, 2) not null check (mean between 1 and 5),
  recommendation text not null check (recommendation in ('strong_yes', 'yes', 'no', 'strong_no')),
  comment        text check (comment is null or char_length(comment) <= 2000),
  submitted_at   timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint interview_scores_uq unique (interview_id, employee_id),
  constraint interview_scores_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint interview_scores_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);
create trigger audit after insert or update on public.interview_scores
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Default templates
-- -----------------------------------------------------------------------------
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
  on conflict (org_id, key, channel) do nothing
$$;

create or replace function private.seed_recruit_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.recruit_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['recruit.manage']
    when 'manager'    then array['recruit.department']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
  perform private.seed_message_templates(p_org_id);
end;
$$;

select private.seed_recruit_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Pure helpers (mirror: core/messages.ts, core/composite.ts)
-- -----------------------------------------------------------------------------
-- Replaces {key} with the value of key; unknown placeholders stay as they are.
create or replace function private.render_template(p_text text, p_vars jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out text := coalesce(p_text, '');
  v_key text;
begin
  for v_key in select jsonb_object_keys(coalesce(p_vars, '{}'::jsonb)) loop
    v_out := replace(v_out, '{' || v_key || '}', coalesce(p_vars ->> v_key, ''));
  end loop;
  return v_out;
end;
$$;

-- p: weights {ats, objective, written, interview}, ats, objective, written (percent or null),
--    interview_means [each interviewer's mean 1-5]
create or replace function private.composite_figures(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_means      numeric[] := array(select x::numeric from jsonb_array_elements_text(coalesce(p -> 'interview_means', '[]')) x);
  v_panel_mean numeric;
  v_interview  numeric;
  v_spread     numeric;
  v_parts      jsonb := '[]'::jsonb;
  v_key        text;
  v_value      numeric;
  v_weight     numeric;
  v_sum_w      numeric := 0;
  v_sum        numeric := 0;
begin
  if cardinality(v_means) > 0 then
    v_panel_mean := (select avg(m) from unnest(v_means) m);
    v_interview := round((v_panel_mean - 1) / 4 * 100, 2);
    v_spread := (select max(m) - min(m) from unnest(v_means) m);
  end if;
  foreach v_key in array array['ats', 'objective', 'written', 'interview'] loop
    v_value := case when v_key = 'interview' then v_interview else (p ->> v_key)::numeric end;
    v_weight := coalesce((p -> 'weights' ->> v_key)::numeric, 0);
    if v_value is not null and v_weight > 0 then
      v_sum_w := v_sum_w + v_weight;
      v_sum := v_sum + v_weight * v_value;
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('key', v_key, 'percent', v_value, 'weight', v_weight));
    end if;
  end loop;
  return jsonb_build_object(
    'components', (select coalesce(jsonb_agg(c || jsonb_build_object('effective_weight', round((c ->> 'weight')::numeric / v_sum_w * 100, 2),
                                                                     'points', round((c ->> 'weight')::numeric * (c ->> 'percent')::numeric / v_sum_w, 2))), '[]'::jsonb)
                   from jsonb_array_elements(v_parts) c),
    'composite', case when v_sum_w > 0 then round(v_sum / v_sum_w, 2) end,
    'interview_percent', v_interview, 'panel_mean', round(v_panel_mean, 2), 'interviewers', cardinality(v_means),
    'spread', round(v_spread, 2), 'spread_flag', coalesce(v_spread > 1.5, false));
end;
$$;

-- Queues the email (and SMS when switched on) of one template for one applicant.
create or replace function private.queue_message(p_applicant_id uuid, p_key text, p_vars jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app   public.applicants;
  v_t     public.message_templates;
  v_count integer := 0;
  v_vars  jsonb;
begin
  select * into v_app from public.applicants where id = p_applicant_id;
  perform private.seed_message_templates(v_app.org_id);
  v_vars := jsonb_build_object('name', v_app.full_name,
                               'company', (select o.name from public.organizations o where o.id = v_app.org_id),
                               'job_title', (select jp.title from public.job_posts jp where jp.id = v_app.job_post_id))
            || coalesce(p_vars, '{}'::jsonb);
  for v_t in select * from public.message_templates where org_id = v_app.org_id and key = p_key loop
    if v_t.channel = 'email' and v_app.email is not null then
      insert into public.notifications (org_id, applicant_id, job_post_id, template_key, channel, to_address, subject, body)
      values (v_app.org_id, v_app.id, v_app.job_post_id, p_key, 'email', v_app.email,
              private.render_template(v_t.subject, v_vars), private.render_template(v_t.body, v_vars));
      v_count := v_count + 1;
    elsif v_t.channel = 'sms' and v_app.phone is not null
          and exists (select 1 from public.org_messaging m where m.org_id = v_app.org_id and m.channel = 'sms' and m.enabled) then
      insert into public.notifications (org_id, applicant_id, job_post_id, template_key, channel, to_address, body)
      values (v_app.org_id, v_app.id, v_app.job_post_id, p_key, 'sms', v_app.phone, private.render_template(v_t.body, v_vars));
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function private.clean_base_url(p_url text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := rtrim(btrim(coalesce(p_url, '')), '/');
begin
  if v !~ '^https?://[A-Za-z0-9.-]+(:[0-9]+)?$' then
    raise exception 'The app address must look like https://hr.example.com' using errcode = '22023';
  end if;
  return v;
end;
$$;

create or replace function private.local_text(p_org_id uuid, p_at timestamptz)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select to_char(p_at at time zone (select timezone from public.organizations where id = p_org_id), 'Dy DD Mon YYYY, HH12:MI AM')
$$;

-- -----------------------------------------------------------------------------
-- API: messaging settings and templates
-- -----------------------------------------------------------------------------
create or replace function public.get_messaging_settings()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  perform private.require_permission('recruit.manage');
  perform private.seed_message_templates(v_org_id);
  return jsonb_build_object(
    'is_admin', private.is_org_admin(),
    'channels', coalesce((select jsonb_object_agg(m.channel, jsonb_build_object(
                  'provider', m.provider, 'enabled', m.enabled, 'config', m.config, 'configured', m.secret_enc is not null,
                  'last4', m.secret_last4, 'tested_at', m.tested_at, 'test_status', m.test_status, 'test_message', m.test_message))
                from public.org_messaging m where m.org_id = v_org_id), '{}'::jsonb),
    'templates', (select jsonb_agg(jsonb_build_object('key', t.key, 'channel', t.channel, 'subject', t.subject, 'body', t.body,
                                                      'updated_at', t.updated_at) order by t.key, t.channel)
                  from public.message_templates t where t.org_id = v_org_id));
end;
$$;

-- Admin. email p: from_name, from_address, api_key (write-only), enabled.
--        sms   p: url, method (GET | POST), to_param, text_param, key_param, sender_param, sender_id, api_key, enabled.
create or replace function public.save_messaging_channel(p_channel text, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_key    text := nullif(btrim(coalesce(p ->> 'api_key', '')), '');
  v_config jsonb;
  v_has    boolean;
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can change email or SMS settings' using errcode = '42501';
  end if;
  if p_channel = 'email' then
    if coalesce(p ->> 'from_address', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Give the sender address (on a domain verified with the provider)' using errcode = '22023';
    end if;
    if char_length(btrim(coalesce(p ->> 'from_name', ''))) not between 2 and 80 then
      raise exception 'Give the sender name' using errcode = '22023';
    end if;
    v_config := jsonb_build_object('from_name', btrim(p ->> 'from_name'), 'from_address', lower(btrim(p ->> 'from_address')));
  elsif p_channel = 'sms' then
    if coalesce(p ->> 'url', '') !~ '^https://' then
      raise exception 'The gateway address must start with https://' using errcode = '22023';
    end if;
    if coalesce(p ->> 'method', 'POST') not in ('GET', 'POST') then
      raise exception 'Method is GET or POST' using errcode = '22023';
    end if;
    if char_length(coalesce(p ->> 'to_param', '')) not between 1 and 40 or char_length(coalesce(p ->> 'text_param', '')) not between 1 and 40 then
      raise exception 'Give the names of the number and message fields of the gateway' using errcode = '22023';
    end if;
    v_config := jsonb_build_object('url', btrim(p ->> 'url'), 'method', coalesce(p ->> 'method', 'POST'),
                                   'to_param', p ->> 'to_param', 'text_param', p ->> 'text_param',
                                   'key_param', nullif(p ->> 'key_param', ''), 'sender_param', nullif(p ->> 'sender_param', ''),
                                   'sender_id', nullif(p ->> 'sender_id', ''));
  else
    raise exception 'Channel is email or sms' using errcode = '22023';
  end if;
  v_has := exists (select 1 from public.org_messaging where org_id = v_org_id and channel = p_channel and secret_enc is not null);
  if v_key is null and not v_has then
    raise exception 'Paste the provider API key' using errcode = '23502';
  end if;
  if v_key is not null and char_length(v_key) not between 8 and 300 then
    raise exception 'The API key looks too short or too long' using errcode = '22023';
  end if;

  insert into public.org_messaging (org_id, channel, provider, enabled, config, secret_enc, secret_last4)
  values (v_org_id, p_channel, case p_channel when 'email' then 'resend' else 'http' end,
          coalesce((p ->> 'enabled')::boolean, p_channel = 'email'), v_config, private.encrypt_secret(v_key), right(v_key, 4))
  on conflict (org_id, channel) do update
    set enabled = excluded.enabled, config = excluded.config,
        secret_enc = coalesce(excluded.secret_enc, public.org_messaging.secret_enc),
        secret_last4 = coalesce(excluded.secret_last4, public.org_messaging.secret_last4),
        tested_at = case when excluded.secret_enc is not null then null else public.org_messaging.tested_at end,
        test_status = case when excluded.secret_enc is not null then null else public.org_messaging.test_status end;
  perform private.write_audit(v_org_id, 'messaging.saved', 'org_messaging', null, null,
                              jsonb_build_object('channel', p_channel, 'enabled', coalesce((p ->> 'enabled')::boolean, p_channel = 'email'),
                                                 'key_changed', v_key is not null));
end;
$$;

create or replace function public.remove_messaging_channel(p_channel text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can change email or SMS settings' using errcode = '42501';
  end if;
  delete from public.org_messaging where org_id = private.current_org_id() and channel = p_channel;
  perform private.write_audit(private.current_org_id(), 'messaging.removed', 'org_messaging', null, null,
                              jsonb_build_object('channel', p_channel));
end;
$$;

create or replace function public.save_message_template(p_key text, p_channel text, p_subject text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  if p_key not in ('test_invite', 'interview_invite', 'rejection', 'offer') or p_channel not in ('email', 'sms') then
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

-- Admin, for the Edge Function's "send a test message".
create or replace function public.messaging_test_context(p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can test email or SMS' using errcode = '42501';
  end if;
  return jsonb_build_object('org_id', private.current_org_id(), 'channel', p_channel,
                            'company', (select o.name from public.organizations o where o.id = private.current_org_id()));
end;
$$;

create or replace function public.record_messaging_test(p_channel text, p_ok boolean, p_message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can test email or SMS' using errcode = '42501';
  end if;
  update public.org_messaging
     set tested_at = now(), test_status = case when p_ok then 'ok' else 'failed' end, test_message = left(nullif(btrim(p_message), ''), 300)
   where org_id = private.current_org_id() and channel = p_channel;
end;
$$;

-- Service role only: provider config with the decrypted key.
create or replace function public.service_messaging_config(p_org_id uuid, p_channel text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select m.config || jsonb_build_object('provider', m.provider, 'enabled', m.enabled, 'api_key', private.decrypt_secret(m.secret_enc))
  from public.org_messaging m
  where m.org_id = p_org_id and m.channel = p_channel and m.secret_enc is not null
$$;

-- -----------------------------------------------------------------------------
-- API: the outbox
-- -----------------------------------------------------------------------------
create or replace function public.list_notifications(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', n.id, 'applicant_id', n.applicant_id, 'full_name', a.full_name,
                                        'template_key', n.template_key, 'channel', n.channel, 'to_address', n.to_address,
                                        'subject', n.subject, 'status', n.status, 'error', n.error, 'attempts', n.attempts,
                                        'created_at', n.created_at, 'sent_at', n.sent_at) order by n.created_at desc)
    from public.notifications n join public.applicants a on a.id = n.applicant_id
    where n.job_post_id = v_post.id), '[]'::jsonb);
end;
$$;

-- The Edge Function (as HR) takes queued messages of the channels that are set up and switched on.
create or replace function public.claim_notifications(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_ids    uuid[];
begin
  perform private.require_permission('recruit.manage');
  select array_agg(n.id) into v_ids from (
    select n.id from public.notifications n
    where n.org_id = v_org_id
      and (n.status = 'queued' or (n.status = 'sending' and n.claimed_at < now() - interval '10 minutes'))
      and exists (select 1 from public.org_messaging m where m.org_id = v_org_id and m.channel = n.channel
                  and m.enabled and m.secret_enc is not null)
    order by n.created_at
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
    for update skip locked) n;
  if v_ids is null then
    return jsonb_build_object('org_id', v_org_id, 'items', '[]'::jsonb);
  end if;
  update public.notifications set status = 'sending', claimed_at = now(), attempts = attempts + 1 where id = any (v_ids);
  return jsonb_build_object('org_id', v_org_id, 'items', (
    select jsonb_agg(jsonb_build_object('id', n.id, 'channel', n.channel, 'to', n.to_address, 'subject', n.subject, 'body', n.body))
    from public.notifications n where n.id = any (v_ids)));
end;
$$;

create or replace function public.mark_notification(p_id uuid, p_ok boolean, p_provider_ref text, p_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  update public.notifications
     set status = case when p_ok then 'sent' else 'failed' end, sent_at = case when p_ok then now() end,
         provider_ref = left(p_provider_ref, 200), error = case when p_ok then null else left(coalesce(p_error, 'Not sent'), 500) end
   where id = p_id and org_id = private.current_org_id() and status = 'sending';
end;
$$;

create or replace function public.retry_notification(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  update public.notifications set status = 'queued', error = null
   where id = p_id and org_id = private.current_org_id() and status = 'failed';
  if not found then
    raise exception 'Only a failed message can be sent again' using errcode = '22023';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: test links now also queue the email (R4 function with two more parameters)
-- -----------------------------------------------------------------------------
drop function public.invite_to_test(uuid, uuid[], integer);
create or replace function public.invite_to_test(p_job_post_id uuid, p_ids uuid[], p_valid_days integer default 3,
                                                 p_base_url text default null, p_send boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post   public.job_posts;
  v_paper  public.question_papers;
  v_app    record;
  v_token  text;
  v_out    jsonb := '[]'::jsonb;
  v_days   integer := coalesce(p_valid_days, 3);
  v_base   text;
  v_until  timestamptz;
  v_queued integer := 0;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  select * into v_paper from public.question_papers where job_post_id = v_post.id and kind = 'objective' for update;
  if not found or v_paper.question_count = 0 then
    raise exception 'Set the objective paper first (Question papers tab)' using errcode = 'P0002';
  end if;
  if v_days not between 1 and 14 then
    raise exception 'A link may stay valid for 1 to 14 days' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_ids), 0) = 0 then
    raise exception 'Pick at least one applicant' using errcode = '22023';
  end if;
  if coalesce(p_send, false) then
    v_base := private.clean_base_url(p_base_url);
  end if;
  v_until := now() + make_interval(days => v_days);
  update public.question_papers set locked_at = coalesce(locked_at, now()) where id = v_paper.id;

  for v_app in
    select a.id, a.full_name, a.email, a.status from public.applicants a
    where a.id = any (p_ids) and a.job_post_id = v_post.id and a.purged_at is null for update
  loop
    if v_app.status not in ('shortlisted', 'test_invited') then
      raise exception '% is % and cannot be invited to the test', v_app.full_name, v_app.status using errcode = '22023';
    end if;
    if exists (select 1 from public.assessment_invites where applicant_id = v_app.id and paper_id = v_paper.id
               and status in ('started', 'submitted')) then
      raise exception '% has already started or taken the test', v_app.full_name using errcode = '22023';
    end if;
    update public.assessment_invites set status = 'cancelled'
     where applicant_id = v_app.id and paper_id = v_paper.id and status = 'invited';
    v_token := encode(extensions.gen_random_bytes(24), 'hex');
    insert into public.assessment_invites (org_id, applicant_id, paper_id, paper_version, token_hash, question_order, expires_at)
    values (v_post.org_id, v_app.id, v_paper.id, v_paper.version, encode(extensions.digest(v_token, 'sha256'), 'hex'),
            (select array_agg(q.position order by random()) from public.paper_questions q where q.paper_id = v_paper.id),
            v_until);
    update public.applicants set status = 'test_invited' where id = v_app.id;
    perform private.applicant_event(v_app.id, 'test_invited', v_app.status, 'test_invited');
    if coalesce(p_send, false) then
      v_queued := v_queued + private.queue_message(v_app.id, 'test_invite', jsonb_build_object(
        'test_link', v_base || '/t/' || v_token, 'duration', v_paper.duration_minutes,
        'valid_until', private.local_text(v_post.org_id, v_until)));
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('applicant_id', v_app.id, 'full_name', v_app.full_name,
                                                           'email', v_app.email, 'token', v_token));
  end loop;
  if jsonb_array_length(v_out) <> cardinality(p_ids) then
    raise exception 'Some applicants were not found in this job post' using errcode = 'P0002';
  end if;
  return v_out;
end;
$$;

-- Creates (or renews) the pre-interview form link and queues the interview invitation.
create or replace function public.send_interview_invite(p_interview_id uuid, p_base_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s      public.interview_schedules;
  v_base   text := private.clean_base_url(p_base_url);
  v_token  text := encode(extensions.gen_random_bytes(24), 'hex');
  v_queued integer;
begin
  select * into v_s from public.interview_schedules where id = p_interview_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Interview not found' using errcode = 'P0002';
  end if;
  perform private.recruit_post(v_s.job_post_id);
  if v_s.status <> 'scheduled' then
    raise exception 'This interview is %', v_s.status using errcode = '22023';
  end if;
  insert into public.preinterview_forms (org_id, applicant_id, interview_id, token_hash, expires_at)
  values (v_s.org_id, v_s.applicant_id, v_s.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), v_s.starts_at)
  on conflict (interview_id) do update set token_hash = excluded.token_hash, expires_at = excluded.expires_at;
  v_queued := private.queue_message(v_s.applicant_id, 'interview_invite', jsonb_build_object(
    'interview_time', private.local_text(v_s.org_id, v_s.starts_at),
    'interview_place', case when v_s.mode = 'online' then 'Online: ' || v_s.online_link else v_s.location end,
    'form_link', v_base || '/f/' || v_token));
  perform private.applicant_event(v_s.applicant_id, 'interview_invite_sent', 'interview_scheduled', 'interview_scheduled');
  return jsonb_build_object('queued', v_queued, 'form_link', v_base || '/f/' || v_token);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: the pre-interview form (no login; the token is the key)
-- -----------------------------------------------------------------------------
create or replace function private.form_by_token(p_token text)
returns public.preinterview_forms
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_f public.preinterview_forms;
begin
  select * into v_f from public.preinterview_forms
   where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    raise exception 'This form link is not valid' using errcode = 'P0002';
  end if;
  return v_f;
end;
$$;

create or replace function public.get_preinterview_form(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_f public.preinterview_forms := private.form_by_token(p_token);
  v_s public.interview_schedules;
begin
  select * into v_s from public.interview_schedules where id = v_f.interview_id;
  return jsonb_build_object(
    'organization', (select o.name from public.organizations o where o.id = v_f.org_id),
    'job_title', (select jp.title from public.job_posts jp where jp.id = v_s.job_post_id),
    'first_name', (select split_part(a.full_name, ' ', 1) from public.applicants a where a.id = v_f.applicant_id),
    'interview_time', private.local_text(v_f.org_id, v_s.starts_at),
    'interview_place', case when v_s.mode = 'online' then 'Online' else v_s.location end,
    'online_link', case when v_s.mode = 'online' then v_s.online_link end,
    'status', case when v_s.status = 'cancelled' then 'cancelled' when now() > v_f.expires_at then 'closed'
                   when v_f.submitted_at is not null then 'submitted' else 'open' end,
    'answers', v_f.answers);
end;
$$;

-- p: can_attend (bool), current_employer, current_designation, notice_period_days (0-180),
--    current_salary, expected_salary (Tk / month, >= 0), questions (text)
create or replace function public.submit_preinterview_form(p_token text, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_f      public.preinterview_forms := private.form_by_token(p_token);
  v_notice integer := (private.jtext(p, 'notice_period_days'))::integer;
  v_exp    numeric := (private.jtext(p, 'expected_salary'))::numeric;
  v_cur    numeric := (private.jtext(p, 'current_salary'))::numeric;
begin
  if now() > v_f.expires_at or (select status from public.interview_schedules where id = v_f.interview_id) = 'cancelled' then
    raise exception 'This form is closed' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'can_attend') is distinct from 'boolean' then
    raise exception 'Tell us whether you can attend' using errcode = '23502';
  end if;
  if v_notice is not null and v_notice not between 0 and 180 then
    raise exception 'Notice period is 0 to 180 days' using errcode = '22023';
  end if;
  if (v_exp is not null and (v_exp < 0 or v_exp > 99999999)) or (v_cur is not null and (v_cur < 0 or v_cur > 99999999)) then
    raise exception 'Enter salary as a monthly amount in Taka' using errcode = '22023';
  end if;
  if char_length(coalesce(p ->> 'questions', '')) > 1000 or char_length(coalesce(p ->> 'current_employer', '')) > 120
     or char_length(coalesce(p ->> 'current_designation', '')) > 120 then
    raise exception 'Some answers are too long' using errcode = '22023';
  end if;
  update public.preinterview_forms
     set answers = jsonb_build_object('can_attend', (p ->> 'can_attend')::boolean,
                                      'current_employer', nullif(btrim(coalesce(p ->> 'current_employer', '')), ''),
                                      'current_designation', nullif(btrim(coalesce(p ->> 'current_designation', '')), ''),
                                      'notice_period_days', v_notice, 'current_salary', v_cur, 'expected_salary', v_exp,
                                      'questions', nullif(btrim(coalesce(p ->> 'questions', '')), '')),
         submitted_at = now()
   where id = v_f.id;
  perform private.applicant_event(v_f.applicant_id, 'preinterview_form_submitted', null, null);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: interviewers (any employee on the panel) and results
-- -----------------------------------------------------------------------------
-- May the caller open this interview? Panel member, or HR / the department Manager.
create or replace function private.interview_access(p_interview_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_s public.interview_schedules;
begin
  select * into v_s from public.interview_schedules where id = p_interview_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Interview not found' using errcode = 'P0002';
  end if;
  if private.current_employee_id() = any (v_s.panel) then
    return 'panel';
  end if;
  if private.recruit_scope((select jp.department_id from public.job_posts jp where jp.id = v_s.job_post_id)) then
    return 'hr';
  end if;
  raise exception 'Only the interview panel can open this' using errcode = '42501';
end;
$$;

create or replace function public.list_my_interviews()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'starts_at', s.starts_at, 'duration_minutes', s.duration_minutes, 'mode', s.mode,
    'location', s.location, 'online_link', s.online_link, 'status', s.status,
    'applicant_name', a.full_name, 'job_title', jp.title,
    'scored', exists (select 1 from public.interview_scores sc where sc.interview_id = s.id and sc.employee_id = private.current_employee_id()),
    'timezone', o.timezone) order by s.starts_at), '[]'::jsonb)
  from public.interview_schedules s
  join public.applicants a on a.id = s.applicant_id
  join public.job_posts jp on jp.id = s.job_post_id
  join public.organizations o on o.id = s.org_id
  where s.org_id = private.current_org_id() and private.current_employee_id() = any (s.panel)
    and s.status in ('scheduled', 'done') and s.starts_at > now() - interval '60 days'
$$;

create or replace function public.get_interviewer_kit(p_interview_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_access text := private.interview_access(p_interview_id);
  v_s      public.interview_schedules;
  v_me     uuid := private.current_employee_id();
  v_mine   boolean;
begin
  select * into v_s from public.interview_schedules where id = p_interview_id;
  perform private.close_overdue_tests(v_s.job_post_id);
  v_mine := exists (select 1 from public.interview_scores sc where sc.interview_id = v_s.id and sc.employee_id = v_me);
  return jsonb_build_object(
    'access', v_access, 'timezone', (select o.timezone from public.organizations o where o.id = v_s.org_id),
    'interview', jsonb_build_object('id', v_s.id, 'starts_at', v_s.starts_at, 'duration_minutes', v_s.duration_minutes,
                                    'mode', v_s.mode, 'location', v_s.location, 'online_link', v_s.online_link,
                                    'status', v_s.status, 'note', v_s.note,
                                    'panel', (select jsonb_agg(jsonb_build_object('employee_id', e.id, 'full_name', e.full_name,
                                                'scored', exists (select 1 from public.interview_scores sc where sc.interview_id = v_s.id and sc.employee_id = e.id)))
                                              from public.employees e where e.id = any (v_s.panel))),
    'applicant', (select jsonb_build_object('id', a.id, 'full_name', a.full_name, 'email', a.email, 'phone', a.phone,
                                            'source', a.source, 'cover_note', a.cover_note)
                  from public.applicants a where a.id = v_s.applicant_id),
    'job', (select jsonb_build_object('title', jp.title, 'profile', jp.profile, 'department_name', d.name)
            from public.job_posts jp join public.departments d on d.id = jp.department_id where jp.id = v_s.job_post_id),
    'screening', (select jsonb_build_object('ats_score', ap.ats_score, 'gate', ap.gate, 'years', ap.years,
                                            'education_level', ap.education_level, 'matched_required', to_jsonb(ap.matched_required),
                                            'matched_nice', to_jsonb(ap.matched_nice), 'summary', ap.summary)
                  from public.applicant_profiles ap where ap.applicant_id = v_s.applicant_id),
    'objective', (select jsonb_build_object('percent', r.percent, 'score', r.score, 'total', r.total, 'passed', r.passed,
                                            'sections', r.section_scores)
                  from public.assessment_results r join public.question_papers qp on qp.id = r.paper_id
                  where r.applicant_id = v_s.applicant_id and qp.job_post_id = v_s.job_post_id order by r.created_at desc limit 1),
    'written', (select jsonb_build_object('percent', w.percent, 'score', w.score, 'total', w.total, 'passed', w.passed)
                from public.written_marks w join public.question_papers qp on qp.id = w.paper_id
                where w.applicant_id = v_s.applicant_id and qp.job_post_id = v_s.job_post_id),
    'form', (select jsonb_build_object('answers', f.answers, 'submitted_at', f.submitted_at)
             from public.preinterview_forms f where f.interview_id = v_s.id),
    'my_score', (select jsonb_build_object('scores', sc.scores, 'recommendation', sc.recommendation, 'comment', sc.comment,
                                           'submitted_at', sc.submitted_at)
                 from public.interview_scores sc where sc.interview_id = v_s.id and sc.employee_id = v_me),
    -- Other interviewers' scores: HR always; a panel member only after scoring.
    'all_scores', case when v_access = 'hr' or v_mine then (
      select jsonb_agg(jsonb_build_object('full_name', e.full_name, 'scores', sc.scores, 'mean', sc.mean,
                                          'recommendation', sc.recommendation, 'comment', sc.comment) order by e.full_name)
      from public.interview_scores sc join public.employees e on e.id = sc.employee_id where sc.interview_id = v_s.id) end);
end;
$$;

-- p: scores {job_knowledge, communication, problem_solving, confidence, culture_fit} (1-5 each),
--    recommendation (strong_yes | yes | no | strong_no), comment
create or replace function public.submit_interview_score(p_interview_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s      public.interview_schedules;
  v_me     uuid := private.current_employee_id();
  v_key    text;
  v_value  numeric;
  v_scores jsonb := '{}'::jsonb;
  v_mean   numeric;
  v_rec    text := coalesce(p ->> 'recommendation', '');
  v_done   boolean;
begin
  select * into v_s from public.interview_schedules where id = p_interview_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Interview not found' using errcode = 'P0002';
  end if;
  if v_me is null or not (v_me = any (v_s.panel)) then
    raise exception 'Only a member of the panel can score this interview' using errcode = '42501';
  end if;
  if v_s.status = 'cancelled' then
    raise exception 'This interview was cancelled' using errcode = '22023';
  end if;
  if v_s.starts_at > now() + interval '1 hour' then
    raise exception 'Scores can be given from one hour before the interview' using errcode = '22023';
  end if;
  foreach v_key in array array['job_knowledge', 'communication', 'problem_solving', 'confidence', 'culture_fit'] loop
    v_value := (p -> 'scores' ->> v_key)::numeric;
    if v_value is null or v_value not in (1, 2, 3, 4, 5) then
      raise exception 'Score every category from 1 to 5 (%)', replace(v_key, '_', ' ') using errcode = '22023';
    end if;
    v_scores := v_scores || jsonb_build_object(v_key, v_value);
  end loop;
  if v_rec not in ('strong_yes', 'yes', 'no', 'strong_no') then
    raise exception 'Give your recommendation' using errcode = '22023';
  end if;
  v_mean := round((select avg(value::numeric) from jsonb_each_text(v_scores)), 2);
  insert into public.interview_scores (org_id, interview_id, applicant_id, employee_id, scores, mean, recommendation, comment)
  values (v_s.org_id, v_s.id, v_s.applicant_id, v_me, v_scores, v_mean, v_rec, left(nullif(btrim(coalesce(p ->> 'comment', '')), ''), 2000))
  on conflict (interview_id, employee_id) do update
    set scores = excluded.scores, mean = excluded.mean, recommendation = excluded.recommendation, comment = excluded.comment,
        updated_at = now();
  v_done := (select count(*) from public.interview_scores sc where sc.interview_id = v_s.id and sc.employee_id = any (v_s.panel))
            = cardinality(v_s.panel);
  if v_done and v_s.status = 'scheduled' then
    update public.interview_schedules set status = 'done' where id = v_s.id;
    update public.applicants set status = 'interviewed' where id = v_s.applicant_id and status = 'interview_scheduled';
    perform private.applicant_event(v_s.applicant_id, 'interviewed', 'interview_scheduled', 'interviewed');
  end if;
  return jsonb_build_object('mean', v_mean, 'panel_complete', v_done);
end;
$$;

-- Ranked results of a post: every component, the composite and the spread flag.
create or replace function public.get_candidate_results(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  return jsonb_build_object(
    'weights', v_post.weights, 'has_written_test', v_post.has_written_test,
    'rows', coalesce((
      select jsonb_agg(x.item order by (x.item -> 'figures' ->> 'composite')::numeric desc nulls last) from (
        select jsonb_build_object(
          'applicant_id', a.id, 'full_name', a.full_name, 'status', a.status,
          'interview_status', s.status, 'panel_size', cardinality(s.panel),
          'scores', (select coalesce(jsonb_agg(jsonb_build_object('full_name', e.full_name, 'mean', sc.mean,
                                                                  'recommendation', sc.recommendation, 'scores', sc.scores) order by e.full_name), '[]'::jsonb)
                     from public.interview_scores sc join public.employees e on e.id = sc.employee_id where sc.interview_id = s.id),
          'figures', private.composite_figures(jsonb_build_object(
            'weights', case when v_post.has_written_test then v_post.weights else v_post.weights || '{"written":0}'::jsonb end,
            'ats', ap.ats_score,
            'objective', (select r.percent from public.assessment_results r join public.question_papers qp on qp.id = r.paper_id
                          where r.applicant_id = a.id and qp.job_post_id = v_post.id order by r.created_at desc limit 1),
            'written', (select w.percent from public.written_marks w join public.question_papers qp on qp.id = w.paper_id
                        where w.applicant_id = a.id and qp.job_post_id = v_post.id),
            'interview_means', (select coalesce(jsonb_agg(sc.mean), '[]'::jsonb) from public.interview_scores sc where sc.interview_id = s.id)))
        ) as item
        from public.applicants a
        join lateral (select * from public.interview_schedules s0 where s0.applicant_id = a.id and s0.status <> 'cancelled'
                      order by s0.starts_at desc limit 1) s on true
        left join public.applicant_profiles ap on ap.applicant_id = a.id
        where a.job_post_id = v_post.id and a.purged_at is null
      ) x), '[]'::jsonb));
end;
$$;

-- The board now keeps interviewed applicants and shows the latest interview (R4 function, extended).
create or replace function public.get_assessment_board(p_job_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  perform private.close_overdue_tests(v_post.id);
  return jsonb_build_object(
    'can', jsonb_build_object('manage', private.has_permission('recruit.manage'), 'schedule', true),
    'today', private.org_today(v_post.org_id),
    'timezone', (select o.timezone from public.organizations o where o.id = v_post.org_id),
    'email_ready', exists (select 1 from public.org_messaging m where m.org_id = v_post.org_id and m.channel = 'email'
                           and m.enabled and m.secret_enc is not null),
    'papers', (select coalesce(jsonb_object_agg(qp.kind, jsonb_build_object(
                 'id', qp.id, 'question_count', qp.question_count, 'total_marks', qp.total_marks,
                 'duration_minutes', qp.duration_minutes, 'pass_percent', qp.pass_percent, 'locked', qp.locked_at is not null,
                 'questions', case when qp.kind = 'written' then (
                   select jsonb_agg(jsonb_build_object('position', q.position, 'stem', q.stem, 'marks', q.marks,
                                                       'model_answer', q.model_answer) order by q.position)
                   from public.paper_questions q where q.paper_id = qp.id) end)), '{}'::jsonb)
               from public.question_papers qp where qp.job_post_id = v_post.id),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'applicant_id', a.id, 'full_name', a.full_name, 'email', a.email, 'phone', a.phone, 'status', a.status,
        'ats_score', ap.ats_score, 'gate', ap.gate,
        'invite', (select jsonb_build_object('id', i.id, 'status', i.status, 'expires_at', i.expires_at,
                                             'started_at', i.started_at, 'submitted_at', i.submitted_at,
                                             'auto_submitted', i.auto_submitted, 'created_at', i.created_at)
                   from public.assessment_invites i join public.question_papers qp on qp.id = i.paper_id
                   where i.applicant_id = a.id and qp.job_post_id = v_post.id
                   order by i.created_at desc limit 1),
        'objective', (select jsonb_build_object('score', r.score, 'total', r.total, 'percent', r.percent, 'passed', r.passed,
                                                'answered', r.answered, 'correct', r.correct, 'sections', r.section_scores)
                      from public.assessment_results r join public.question_papers qp on qp.id = r.paper_id
                      where r.applicant_id = a.id and qp.job_post_id = v_post.id
                      order by r.created_at desc limit 1),
        'written', (select jsonb_build_object('score', w.score, 'total', w.total, 'percent', w.percent, 'passed', w.passed,
                                              'marks', w.marks, 'updated_at', w.updated_at)
                    from public.written_marks w join public.question_papers qp on qp.id = w.paper_id
                    where w.applicant_id = a.id and qp.job_post_id = v_post.id),
        'interview', (select jsonb_build_object(
                         'id', s.id, 'status', s.status, 'starts_at', s.starts_at, 'duration_minutes', s.duration_minutes, 'mode', s.mode,
                         'location', s.location, 'online_link', s.online_link, 'panel', to_jsonb(s.panel),
                         'panel_names', (select jsonb_agg(e.full_name order by e.full_name) from public.employees e where e.id = any (s.panel)),
                         'due_by', s.due_by, 'late_reason', s.late_reason, 'note', s.note, 'proposed_by', s.proposed_by,
                         'scores_in', (select count(*) from public.interview_scores sc where sc.interview_id = s.id),
                         'invite_sent', exists (select 1 from public.preinterview_forms f where f.interview_id = s.id),
                         'form_submitted', exists (select 1 from public.preinterview_forms f where f.interview_id = s.id and f.submitted_at is not null))
                       from public.interview_schedules s where s.applicant_id = a.id and s.status <> 'cancelled'
                       order by s.starts_at desc limit 1),
        'due_by', private.interview_due_by(a.id))
        order by ap.ats_score desc nulls last, a.created_at)
      from public.applicants a
      left join public.applicant_profiles ap on ap.applicant_id = a.id
      where a.job_post_id = v_post.id and a.purged_at is null
        and a.status in ('shortlisted', 'test_invited', 'test_done', 'written_done', 'interview_scheduled', 'interviewed')), '[]'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.org_messaging      enable row level security;
alter table public.message_templates  enable row level security;
alter table public.notifications      enable row level security;
alter table public.preinterview_forms enable row level security;
alter table public.interview_scores   enable row level security;
revoke all on table public.org_messaging, public.message_templates, public.notifications, public.preinterview_forms,
                    public.interview_scores
from anon, authenticated;

revoke all on function
  public.get_messaging_settings(), public.save_messaging_channel(text, jsonb), public.remove_messaging_channel(text),
  public.save_message_template(text, text, text, text), public.messaging_test_context(text),
  public.record_messaging_test(text, boolean, text), public.service_messaging_config(uuid, text),
  public.list_notifications(uuid), public.claim_notifications(integer), public.mark_notification(uuid, boolean, text, text),
  public.retry_notification(uuid), public.invite_to_test(uuid, uuid[], integer, text, boolean),
  public.send_interview_invite(uuid, text), public.get_preinterview_form(text), public.submit_preinterview_form(text, jsonb),
  public.list_my_interviews(), public.get_interviewer_kit(uuid), public.submit_interview_score(uuid, jsonb),
  public.get_candidate_results(uuid), public.get_assessment_board(uuid)
from public, anon;
grant execute on function
  public.get_messaging_settings(), public.save_messaging_channel(text, jsonb), public.remove_messaging_channel(text),
  public.save_message_template(text, text, text, text), public.messaging_test_context(text),
  public.record_messaging_test(text, boolean, text),
  public.list_notifications(uuid), public.claim_notifications(integer), public.mark_notification(uuid, boolean, text, text),
  public.retry_notification(uuid), public.invite_to_test(uuid, uuid[], integer, text, boolean),
  public.send_interview_invite(uuid, text), public.list_my_interviews(), public.get_interviewer_kit(uuid),
  public.submit_interview_score(uuid, jsonb), public.get_candidate_results(uuid), public.get_assessment_board(uuid)
to authenticated;
grant execute on function public.get_preinterview_form(text), public.submit_preinterview_form(text, jsonb) to anon, authenticated;
revoke all on function public.service_messaging_config(uuid, text) from authenticated;
grant execute on function public.service_messaging_config(uuid, text) to service_role;

revoke all on function
  private.seed_message_templates(uuid), private.seed_recruit_defaults(uuid), private.render_template(text, jsonb),
  private.composite_figures(jsonb), private.queue_message(uuid, text, jsonb), private.clean_base_url(text),
  private.local_text(uuid, timestamptz), private.form_by_token(text), private.interview_access(uuid)
from public, anon, authenticated;
