-- =============================================================================
-- Onboarding process R7: joining. Pre-hire -> employee, joining checklist,
-- documents to print and sign, named joining feedback, and the purge that
-- closes a post's hiring (no CV or applicant data is kept afterwards).
-- Module handbook: src/onboarding-process/architecture.md (sections 2, 5-8).
--
-- Convert (HR, after verifying the pre-joining form): creates the employee
-- through create_employee (card ID, history, NID, nominees), the starting pay
-- from the approved offer (salary template + gross; the offer approval is the
-- maker-checker), and the salary account (the encrypted number is copied, never
-- decrypted). The applicant becomes "joined"; a case with a checklist and four
-- documents opens; a named feedback link goes to the new employee.
-- Close hiring (HR): when no offer is open, the CV and photo files are listed
-- for deletion (the app deletes them through Storage), then every applicant of
-- the post loses name, email, phone, CV text, forms and messages; counts and
-- scores stay for the funnel. The vacancy becomes "filled" when all seats joined.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.prehire_records') is null then
    raise exception 'Apply 20261030000100_recruit_r6_offers.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.onboarding_cases (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null,
  applicant_id        uuid not null unique,
  job_post_id         uuid not null,
  offer_id            uuid not null unique,
  employee_id         uuid not null,
  joining_date        date not null,
  status              text not null default 'open' check (status in ('open', 'completed')),
  feedback_token_hash text unique,
  completed_at        timestamptz,
  completed_by        uuid references public.user_profiles (id),
  created_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id) default auth.uid(),
  constraint onboarding_cases_org_id_id_uq unique (org_id, id),
  constraint onboarding_cases_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint onboarding_cases_offer_fk foreign key (org_id, offer_id) references public.offers (org_id, id),
  constraint onboarding_cases_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);

create table public.onboarding_tasks (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null,
  case_id    uuid not null,
  key        text not null check (key in ('documents_signed', 'id_card', 'portal_access', 'workstation', 'orientation',
                                          'reporting_manager', 'photo_copied')),
  position   smallint not null,
  done_at    timestamptz,
  done_by    uuid references public.user_profiles (id),
  constraint onboarding_tasks_uq unique (case_id, key),
  constraint onboarding_tasks_case_fk foreign key (org_id, case_id) references public.onboarding_cases (org_id, id)
);

create table public.onboarding_documents (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  case_id     uuid not null,
  kind        text not null check (kind in ('appointment_letter', 'joining_report', 'nominee_form', 'code_of_conduct')),
  printed_at  timestamptz,
  signed_path text,
  signed_at   timestamptz,
  uploaded_by uuid references public.user_profiles (id),
  constraint onboarding_documents_uq unique (case_id, kind),
  constraint onboarding_documents_case_fk foreign key (org_id, case_id) references public.onboarding_cases (org_id, id)
);

create table public.joining_feedback (
  case_id      uuid primary key references public.onboarding_cases (id),
  org_id       uuid not null,
  employee_id  uuid not null,
  ratings      jsonb not null,
  comment      text check (comment is null or char_length(comment) <= 2000),
  submitted_at timestamptz not null default now(),
  constraint joining_feedback_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);

alter table public.applicants add column employee_id_joined uuid;   -- kept after the purge (applicants.employee_id is for internal candidates)

-- -----------------------------------------------------------------------------
-- Storage: signed documents (private; HR of the company)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('onboarding-docs', 'onboarding-docs', false, 5242880, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- onboarding-docs/{org}/{case}/{kind}.{pdf|jpg|png}
create or replace function private.onboarding_doc_access(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$'
     or v_parts[3] !~ '^(appointment_letter|joining_report|nominee_form|code_of_conduct)\.(pdf|jpg|png)$' then
    return false;
  end if;
  return v_parts[1]::uuid = private.current_org_id() and private.has_permission('recruit.manage')
     and exists (select 1 from public.onboarding_cases c where c.id = v_parts[2]::uuid and c.org_id = v_parts[1]::uuid);
end;
$$;
revoke all on function private.onboarding_doc_access(text) from public, anon;
grant execute on function private.onboarding_doc_access(text) to authenticated;

drop policy if exists olympus_onboarding_docs_select on storage.objects;
drop policy if exists olympus_onboarding_docs_insert on storage.objects;
drop policy if exists olympus_onboarding_docs_update on storage.objects;
drop policy if exists olympus_onboarding_docs_delete on storage.objects;
create policy olympus_onboarding_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'onboarding-docs' and private.onboarding_doc_access(name));
create policy olympus_onboarding_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'onboarding-docs' and private.onboarding_doc_access(name));
create policy olympus_onboarding_docs_update on storage.objects for update to authenticated
  using (bucket_id = 'onboarding-docs' and private.onboarding_doc_access(name))
  with check (bucket_id = 'onboarding-docs' and private.onboarding_doc_access(name));
create policy olympus_onboarding_docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'onboarding-docs' and private.onboarding_doc_access(name));

-- -----------------------------------------------------------------------------
-- API: convert the pre-hire into an employee
-- -----------------------------------------------------------------------------
-- p: card_id (only when the company uses custom card IDs), send_feedback (bool), base_url
create or replace function public.convert_to_employee(p_prehire_id uuid, p jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r      public.prehire_records;
  v_o      public.offers;
  v_app    public.applicants;
  v_office public.offices;
  v_emp    uuid;
  v_case   uuid;
  v_token  text := encode(extensions.gen_random_bytes(24), 'hex');
  v_link   text;
  v_seats  integer;
  v_joined integer;
  v_vac    uuid;
begin
  perform private.require_permission('recruit.manage');
  select * into v_r from public.prehire_records where id = p_prehire_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Pre-joining form not found' using errcode = 'P0002';
  end if;
  if v_r.status <> 'verified' then
    raise exception 'Verify the pre-joining form first (now %)', v_r.status using errcode = '22023';
  end if;
  if v_r.employee_id is not null then
    raise exception 'This person is already an employee' using errcode = '23505';
  end if;
  select * into v_o from public.offers where id = v_r.offer_id;
  select * into v_app from public.applicants where id = v_r.applicant_id for update;
  select * into v_office from public.offices where id = v_o.office_id;

  -- create_employee checks employees.create and writes the card ID, history, NID and nominees.
  v_emp := public.create_employee(jsonb_build_object(
    'full_name', v_app.full_name, 'phone', v_app.phone, 'email', v_app.email,
    'date_of_birth', v_r.data ->> 'date_of_birth', 'gender', v_r.data ->> 'gender',
    'marital_status', v_r.data ->> 'marital_status', 'religion', v_r.data ->> 'religion', 'blood_group', v_r.data ->> 'blood_group',
    'join_date', v_o.joining_date, 'employment_type', v_o.employment_type,
    'department_id', v_o.department_id, 'designation_id', v_o.designation_id,
    'branch_id', v_office.branch_id, 'office_id', v_office.id,
    'present_address', v_r.data ->> 'present_address', 'permanent_address', v_r.data ->> 'permanent_address',
    'probation_end_date', case when v_o.probation_months > 0 then (v_o.joining_date + make_interval(months => v_o.probation_months))::date end,
    'nid_number', private.decrypt_secret(v_r.nid_enc),
    'nominees', v_r.data -> 'nominees',
    'card_id', private.jtext(p, 'card_id')));

  -- Starting pay = the approved offer (approval was the second pair of eyes).
  perform private.create_compensation(v_emp, v_o.salary_template_id, null, v_o.gross, v_o.joining_date, 'initial', null,
                                      'Offer accepted');
  -- Salary account: the encrypted number is copied as it is.
  insert into public.employee_payment_accounts (org_id, employee_id, method, bank_name, branch_name, routing_number,
                                                account_name, account_number_enc, wallet_provider, wallet_number_enc,
                                                number_last4, is_primary, status)
  values (v_r.org_id, v_emp, v_r.payment_method,
          case when v_r.payment_method = 'bank' then v_r.bank_name end,
          case when v_r.payment_method = 'bank' then v_r.branch_name end,
          case when v_r.payment_method = 'bank' then v_r.routing_number end,
          coalesce(v_r.account_name, v_app.full_name),
          case when v_r.payment_method = 'bank' then v_r.account_enc end,
          case when v_r.payment_method = 'mobile_wallet' then v_r.wallet_provider end,
          case when v_r.payment_method = 'mobile_wallet' then v_r.wallet_enc end,
          case when v_r.payment_method <> 'cash' then v_r.number_last4 end, true, 'active');

  update public.prehire_records set employee_id = v_emp, updated_at = now() where id = v_r.id;
  update public.applicants set status = 'joined', employee_id_joined = v_emp where id = v_app.id;

  insert into public.onboarding_cases (org_id, applicant_id, job_post_id, offer_id, employee_id, joining_date, feedback_token_hash)
  values (v_r.org_id, v_app.id, v_app.job_post_id, v_o.id, v_emp, v_o.joining_date, encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning id into v_case;
  insert into public.onboarding_tasks (org_id, case_id, key, position)
  select v_r.org_id, v_case, k, n
  from unnest(array['photo_copied', 'documents_signed', 'id_card', 'portal_access', 'reporting_manager', 'workstation', 'orientation'])
       with ordinality as t(k, n);
  insert into public.onboarding_documents (org_id, case_id, kind)
  select v_r.org_id, v_case, k from unnest(array['appointment_letter', 'joining_report', 'nominee_form', 'code_of_conduct']) k;

  if coalesce((p ->> 'send_feedback')::boolean, false) then
    v_link := private.clean_base_url(p ->> 'base_url') || '/joining-feedback/' || v_token;
    perform private.queue_message(v_app.id, 'joining_feedback', jsonb_build_object('feedback_link', v_link));
  end if;

  -- The vacancy is filled when every seat has joined.
  select jp.seats, jp.vacancy_id into v_seats, v_vac from public.job_posts jp where jp.id = v_app.job_post_id;
  select count(*) into v_joined from public.applicants a where a.job_post_id = v_app.job_post_id and a.status = 'joined';
  if v_joined >= v_seats then
    update public.vacancies set status = 'filled' where id = v_vac and status = 'approved';
    perform private.vacancy_event(v_vac, 'filled', 'approved', 'filled', 'All seats joined');
  end if;

  perform private.applicant_event(v_app.id, 'joined', v_app.status, 'joined');
  perform private.write_audit(v_r.org_id, 'onboarding.converted', 'onboarding_cases', v_case, null,
                              jsonb_build_object('employee_id', v_emp, 'offer_id', v_o.id));
  return jsonb_build_object('employee_id', v_emp, 'case_id', v_case,
                            'card_id', (select e.card_id from public.employees e where e.id = v_emp),
                            'feedback_link_path', '/joining-feedback/' || v_token, 'feedback_queued', v_link is not null,
                            'photo_path', v_r.photo_path);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: the onboarding case (checklist, documents)
-- -----------------------------------------------------------------------------
create or replace function public.get_onboarding_case(p_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.onboarding_cases;
begin
  perform private.require_permission('recruit.manage');
  select * into v_c from public.onboarding_cases where id = p_case_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Onboarding case not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', v_c.id, 'status', v_c.status, 'joining_date', v_c.joining_date, 'completed_at', v_c.completed_at,
    'org_id', v_c.org_id,
    'employee', (select jsonb_build_object('id', e.id, 'card_id', e.card_id, 'full_name', e.full_name, 'email', e.email,
                                           'phone', e.phone, 'present_address', e.present_address, 'permanent_address', e.permanent_address,
                                           'date_of_birth', e.date_of_birth, 'probation_end_date', e.probation_end_date,
                                           'employment_type', e.employment_type,
                                           'designation', ds.name, 'department', d.name, 'office', o.name, 'branch', b.name)
                 from public.employees e
                 left join public.designations ds on ds.id = e.designation_id
                 left join public.departments d on d.id = e.department_id
                 left join public.offices o on o.id = e.office_id
                 left join public.branches b on b.id = e.branch_id
                 where e.id = v_c.employee_id),
    'company', (select jsonb_build_object('name', og.name, 'org_code', og.org_code) from public.organizations og where og.id = v_c.org_id),
    'offer', (select jsonb_build_object('gross', ofr.gross, 'joining_date', ofr.joining_date, 'probation_months', ofr.probation_months,
                                        'terms', ofr.terms, 'employment_type', ofr.employment_type)
              from public.offers ofr where ofr.id = v_c.offer_id),
    'nominees', coalesce((select jsonb_agg(jsonb_build_object('name', n.name, 'relation', n.relation, 'phone', n.phone) order by n.created_at)
                          from public.employee_nominees n where n.employee_id = v_c.employee_id and n.status = 'active'), '[]'::jsonb),
    'tasks', (select jsonb_agg(jsonb_build_object('id', t.id, 'key', t.key, 'done_at', t.done_at, 'done_by_name', u.full_name) order by t.position)
              from public.onboarding_tasks t left join public.user_profiles u on u.id = t.done_by where t.case_id = v_c.id),
    'documents', (select jsonb_agg(jsonb_build_object('kind', dc.kind, 'printed_at', dc.printed_at, 'signed_path', dc.signed_path,
                                                      'signed_at', dc.signed_at) order by dc.kind)
                  from public.onboarding_documents dc where dc.case_id = v_c.id),
    'feedback', (select jsonb_build_object('ratings', f.ratings, 'comment', f.comment, 'submitted_at', f.submitted_at)
                 from public.joining_feedback f where f.case_id = v_c.id));
end;
$$;

create or replace function public.set_onboarding_task(p_task_id uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  update public.onboarding_tasks t
     set done_at = case when p_done then now() end, done_by = case when p_done then auth.uid() end
    from public.onboarding_cases c
   where t.id = p_task_id and c.id = t.case_id and c.org_id = private.current_org_id() and c.status = 'open';
  if not found then
    raise exception 'Task not found or the case is completed' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.mark_document_printed(p_case_id uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  update public.onboarding_documents d set printed_at = coalesce(d.printed_at, now())
    from public.onboarding_cases c
   where d.case_id = p_case_id and d.kind = p_kind and c.id = d.case_id and c.org_id = private.current_org_id();
  if not found then
    raise exception 'Document not found' using errcode = 'P0002';
  end if;
end;
$$;

-- After HR uploads the signed scan to onboarding-docs/{org}/{case}/{kind}.{ext}.
create or replace function public.attach_signed_document(p_case_id uuid, p_kind text, p_ext text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c    public.onboarding_cases;
  v_path text;
begin
  perform private.require_permission('recruit.manage');
  select * into v_c from public.onboarding_cases where id = p_case_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Onboarding case not found' using errcode = 'P0002';
  end if;
  if coalesce(p_ext, '') not in ('pdf', 'jpg', 'png') then
    raise exception 'Upload a PDF, JPG or PNG' using errcode = '22023';
  end if;
  v_path := v_c.org_id || '/' || v_c.id || '/' || p_kind || '.' || p_ext;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'onboarding-docs' and o.name = v_path) then
    raise exception 'The scan was not found; upload it again' using errcode = 'P0002';
  end if;
  update public.onboarding_documents set signed_path = v_path, signed_at = now(), uploaded_by = auth.uid()
   where case_id = v_c.id and kind = p_kind;
  if not found then
    raise exception 'Unknown document' using errcode = '22023';
  end if;
  if not exists (select 1 from public.onboarding_documents where case_id = v_c.id and signed_path is null) then
    update public.onboarding_tasks set done_at = coalesce(done_at, now()), done_by = coalesce(done_by, auth.uid())
     where case_id = v_c.id and key = 'documents_signed';
  end if;
end;
$$;

create or replace function public.complete_onboarding(p_case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.onboarding_cases;
begin
  perform private.require_permission('recruit.manage');
  select * into v_c from public.onboarding_cases where id = p_case_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Onboarding case not found' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.onboarding_tasks where case_id = v_c.id and done_at is null) then
    raise exception 'Finish every checklist item first' using errcode = '22023';
  end if;
  update public.onboarding_cases set status = 'completed', completed_at = now(), completed_by = auth.uid() where id = v_c.id;
end;
$$;

create or replace function public.list_onboarding_cases(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'applicant_id', c.applicant_id, 'employee_id', c.employee_id, 'status', c.status, 'joining_date', c.joining_date,
      'employee_name', e.full_name, 'card_id', e.card_id,
      'tasks_done', (select count(*) from public.onboarding_tasks t where t.case_id = c.id and t.done_at is not null),
      'tasks_total', (select count(*) from public.onboarding_tasks t where t.case_id = c.id),
      'feedback', exists (select 1 from public.joining_feedback f where f.case_id = c.id)) order by c.joining_date)
    from public.onboarding_cases c join public.employees e on e.id = c.employee_id
    where c.job_post_id = p_job_post_id and c.org_id = private.current_org_id()), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: named joining feedback (no login; the link from the welcome email)
-- -----------------------------------------------------------------------------
create or replace function private.case_by_feedback_token(p_token text)
returns public.onboarding_cases
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.onboarding_cases;
begin
  select * into v_c from public.onboarding_cases
   where feedback_token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    raise exception 'This feedback link is not valid' using errcode = 'P0002';
  end if;
  return v_c;
end;
$$;

create or replace function public.get_joining_feedback(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.onboarding_cases := private.case_by_feedback_token(p_token);
begin
  return jsonb_build_object(
    'organization', (select o.name from public.organizations o where o.id = v_c.org_id),
    'full_name', (select e.full_name from public.employees e where e.id = v_c.employee_id),
    'joining_date', v_c.joining_date,
    'submitted', exists (select 1 from public.joining_feedback f where f.case_id = v_c.id),
    'open', v_c.created_at > now() - interval '60 days');
end;
$$;

-- p: ratings {overall, recruiter_behaviour, clarity, first_day} 1-5, comment. Named (linked to the employee).
create or replace function public.submit_joining_feedback(p_token text, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       public.onboarding_cases := private.case_by_feedback_token(p_token);
  v_key     text;
  v_value   numeric;
  v_ratings jsonb := '{}'::jsonb;
begin
  if v_c.created_at < now() - interval '60 days' then
    raise exception 'This feedback form is closed' using errcode = '22023';
  end if;
  foreach v_key in array array['overall', 'recruiter_behaviour', 'clarity', 'first_day'] loop
    v_value := (p -> 'ratings' ->> v_key)::numeric;
    if v_value is null or v_value not in (1, 2, 3, 4, 5) then
      raise exception 'Rate every question from 1 to 5' using errcode = '22023';
    end if;
    v_ratings := v_ratings || jsonb_build_object(v_key, v_value);
  end loop;
  insert into public.joining_feedback (case_id, org_id, employee_id, ratings, comment)
  values (v_c.id, v_c.org_id, v_c.employee_id, v_ratings, left(nullif(btrim(coalesce(p ->> 'comment', '')), ''), 2000))
  on conflict (case_id) do update set ratings = excluded.ratings, comment = excluded.comment, submitted_at = now();
end;
$$;

-- -----------------------------------------------------------------------------
-- API: close a post's hiring and purge applicant data (decision 10)
-- -----------------------------------------------------------------------------
-- What will be deleted: file paths per bucket and counts. Refused while an offer is open.
create or replace function public.get_purge_plan(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'blocking', (select count(*) from public.offers o where o.job_post_id = v_post.id and o.status in ('draft', 'approved', 'sent'))
                + (select count(*) from public.offers o where o.job_post_id = v_post.id and o.status = 'accepted'
                   and not exists (select 1 from public.onboarding_cases c where c.offer_id = o.id)),
    'applicants', (select count(*) from public.applicants a where a.job_post_id = v_post.id and a.purged_at is null),
    'joined', (select count(*) from public.applicants a where a.job_post_id = v_post.id and a.status = 'joined'),
    'files', jsonb_build_object(
      'recruit-cvs', coalesce((select jsonb_agg(o.name) from storage.objects o
                               where o.bucket_id = 'recruit-cvs' and o.name like v_post.org_id || '/' || v_post.id || '/%'), '[]'::jsonb),
      'prehire-files', coalesce((select jsonb_agg(o.name) from storage.objects o
                                 where o.bucket_id = 'prehire-files'
                                   and split_part(o.name, '/', 2) in (select a.id::text from public.applicants a where a.job_post_id = v_post.id)), '[]'::jsonb)));
end;
$$;

-- After the app deleted the files: clears every applicant's personal data and recruitment records.
create or replace function public.purge_post_applicants(p_job_post_id uuid, p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post  public.job_posts;
  v_ids   uuid[];
  v_count integer;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if coalesce(p_confirm, '') <> 'DELETE' then
    raise exception 'Type DELETE to confirm' using errcode = '22023';
  end if;
  if (public.get_purge_plan(v_post.id) ->> 'blocking')::integer > 0 then
    raise exception 'Finish or withdraw the open offers first' using errcode = '22023';
  end if;
  if exists (select 1 from storage.objects o where o.bucket_id = 'recruit-cvs' and o.name like v_post.org_id || '/' || v_post.id || '/%') then
    raise exception 'Delete the CV files first (the app does this before calling the purge)' using errcode = '22023';
  end if;

  select array_agg(a.id) into v_ids from public.applicants a where a.job_post_id = v_post.id and a.purged_at is null;
  v_count := coalesce(cardinality(v_ids), 0);
  if v_count > 0 then
    delete from public.applicant_profiles where applicant_id = any (v_ids);
    delete from public.assessment_answers where invite_id in (select i.id from public.assessment_invites i where i.applicant_id = any (v_ids));
    delete from public.notifications where applicant_id = any (v_ids);
    delete from public.preinterview_forms where applicant_id = any (v_ids);
    delete from public.prehire_records where applicant_id = any (v_ids);
    update public.interview_scores set comment = null where applicant_id = any (v_ids);
    update public.applicants
       set full_name = null, email = null, phone = null, cover_note = null, cv_path = null, cv_upload_token_hash = null,
           purged_at = now(), status = case when status = 'joined' then status else 'purged' end
     where id = any (v_ids);
  end if;
  if v_post.status in ('draft', 'published') then
    update public.job_posts set status = case when status = 'draft' then 'cancelled' else 'closed' end,
                                closed_at = now(), closed_by = auth.uid(), close_note = 'Hiring closed' where id = v_post.id;
  end if;
  perform private.write_audit(v_post.org_id, 'recruitment.purged', 'job_posts', v_post.id, null, jsonb_build_object('applicants', v_count));
  return jsonb_build_object('purged', v_count);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.onboarding_cases     enable row level security;
alter table public.onboarding_tasks     enable row level security;
alter table public.onboarding_documents enable row level security;
alter table public.joining_feedback     enable row level security;
revoke all on table public.onboarding_cases, public.onboarding_tasks, public.onboarding_documents, public.joining_feedback
from anon, authenticated;

revoke all on function
  public.convert_to_employee(uuid, jsonb), public.get_onboarding_case(uuid), public.set_onboarding_task(uuid, boolean),
  public.mark_document_printed(uuid, text), public.attach_signed_document(uuid, text, text), public.complete_onboarding(uuid),
  public.list_onboarding_cases(uuid), public.get_joining_feedback(text), public.submit_joining_feedback(text, jsonb),
  public.get_purge_plan(uuid), public.purge_post_applicants(uuid, text)
from public, anon;
grant execute on function
  public.convert_to_employee(uuid, jsonb), public.get_onboarding_case(uuid), public.set_onboarding_task(uuid, boolean),
  public.mark_document_printed(uuid, text), public.attach_signed_document(uuid, text, text), public.complete_onboarding(uuid),
  public.list_onboarding_cases(uuid), public.get_purge_plan(uuid), public.purge_post_applicants(uuid, text)
to authenticated;
grant execute on function public.get_joining_feedback(text), public.submit_joining_feedback(text, jsonb) to anon, authenticated;

revoke all on function private.case_by_feedback_token(text) from public, anon, authenticated;
