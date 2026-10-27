-- =============================================================================
-- AI assistant AI4: resources (upload; DMS later), indexing, and the app guide.
-- Design: docs/Part04Architecture.md (sections 8, 9.2, 12).
--
-- Upload: the browser hashes the file, registers it (duplicates refused BEFORE
-- the upload), uploads to assistant-resources/{org}/{resource}/v{n}.{ext},
-- confirms, then asks the Edge Function to index it in batches (resume point
-- processed_through), so a closed browser simply resumes next time.
-- The Edge Function writes chunks only through service RPCs (service role).
-- App guide: articles we ship (seeded here, same for every company) are indexed
-- into each company's store with that company's embedding key.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.assistant_updates') is null then
    raise exception 'Apply 20261103000200_assistant_ai3_updates.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Storage
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('assistant-resources', 'assistant-resources', false, 20971520,
   array['application/pdf', 'application/json', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.assistant_resource_path(r public.assistant_resources)
returns text
language sql
immutable
set search_path = ''
as $$
  select r.org_id || '/' || r.id || '/v' || r.version || '.' || r.kind
$$;

-- Read: managers, or anyone whose role may read the resource. Write: managers while the row waits for its file.
create or replace function private.assistant_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  r       public.assistant_resources;
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$' then
    return false;
  end if;
  select * into r from public.assistant_resources where id = v_parts[2]::uuid and org_id = v_parts[1]::uuid;
  if not found or r.org_id is distinct from private.current_org_id() or p_name <> private.assistant_resource_path(r) then
    return false;
  end if;
  if p_write then
    return r.status = 'uploading' and private.has_permission('assistant.manage');
  end if;
  return private.has_permission('assistant.manage')
      or private.assistant_can_read_resource(r, private.current_role_id(), private.assistant_allowed_topics(private.current_role_id()));
end;
$$;

drop policy if exists olympus_assistant_files_select on storage.objects;
drop policy if exists olympus_assistant_files_insert on storage.objects;
create policy olympus_assistant_files_select on storage.objects for select to authenticated
  using (bucket_id = 'assistant-resources' and private.assistant_file_access(name, false));
create policy olympus_assistant_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'assistant-resources' and private.assistant_file_access(name, true));

-- -----------------------------------------------------------------------------
-- API: resources (assistant.manage)
-- -----------------------------------------------------------------------------
create or replace function private.assistant_resource_json(r public.assistant_resources)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'source', r.source, 'name', r.name, 'kind', r.kind, 'size_bytes', r.size_bytes, 'topic_key', r.topic_key,
    'audience_role_ids', to_jsonb(r.audience_role_ids), 'version', r.version, 'replaces_id', r.replaces_id, 'status', r.status,
    'error', r.error, 'units', r.units, 'chunks', r.chunks, 'processed_through', r.processed_through,
    'embedding_model', r.embedding_model, 'uploaded_at', r.uploaded_at, 'updated_at', r.updated_at, 'path', private.assistant_resource_path(r),
    'uploaded_by', (select up.full_name from public.user_profiles up where up.id = r.uploaded_by))
$$;

-- p: {name, kind, size_bytes, file_hash, topic_key, audience_role_ids, replaces_id}
create or replace function public.register_assistant_resource(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_kind    text := p ->> 'kind';
  v_hash    text := lower(coalesce(p ->> 'file_hash', ''));
  v_topic   text := p ->> 'topic_key';
  v_roles   uuid[] := private.uuid_array(p, 'audience_role_ids');
  v_old     public.assistant_resources;
  v_dup     text;
  r         public.assistant_resources;
begin
  perform private.require_permission('assistant.manage');
  if v_kind not in ('pdf', 'docx', 'json') then
    raise exception 'Only PDF, DOCX and JSON files can be used' using errcode = '22023';
  end if;
  if coalesce((p ->> 'size_bytes')::integer, 0) not between 1 and 20971520 then
    raise exception 'The file must be smaller than 20 MB' using errcode = '22023';
  end if;
  if v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'The file fingerprint is missing' using errcode = '22023';
  end if;
  if not exists (select 1 from public.assistant_topics where key = v_topic and topic_group = 'knowledge' and key <> 'kb.app_guide') then
    raise exception 'Choose a topic for the file' using errcode = '22023';
  end if;
  if (select count(*) from public.roles where id = any (v_roles) and org_id = v_org) <> cardinality(v_roles) then
    raise exception 'Choose roles of your company' using errcode = '22023';
  end if;
  select name into v_dup from public.assistant_resources where org_id = v_org and file_hash = v_hash and status <> 'archived';
  if v_dup is not null then
    raise exception 'This file is already uploaded as "%"', v_dup using errcode = '23505';
  end if;
  if nullif(p ->> 'replaces_id', '') is not null then
    select * into v_old from public.assistant_resources where id = (p ->> 'replaces_id')::uuid and org_id = v_org;
    if not found or v_old.status not in ('ready', 'failed') then
      raise exception 'Only a ready or failed resource gets a new version' using errcode = '23514';
    end if;
  end if;
  insert into public.assistant_resources (org_id, name, kind, size_bytes, file_hash, topic_key, audience_role_ids, version, replaces_id)
  values (v_org, left(btrim(p ->> 'name'), 200), v_kind, (p ->> 'size_bytes')::integer, v_hash,
          coalesce(v_old.topic_key, v_topic), case when v_old.id is not null then v_old.audience_role_ids else v_roles end,
          coalesce(v_old.version, 0) + 1, v_old.id)
  returning * into r;
  update public.assistant_resources set file_path = private.assistant_resource_path(r) where id = r.id returning * into r;
  return private.assistant_resource_json(r);
end;
$$;

-- The file is in storage: index it. A new version archives the one it replaces.
create or replace function public.confirm_assistant_upload(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.assistant_resources;
begin
  perform private.require_permission('assistant.manage');
  select * into r from public.assistant_resources where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Resource not found' using errcode = 'P0002';
  end if;
  if r.status <> 'uploading' then
    raise exception 'This resource is already confirmed' using errcode = '23514';
  end if;
  update public.assistant_resources set status = 'processing', processed_through = 0 where id = r.id;
  if r.replaces_id is not null then
    update public.assistant_resources set status = 'archived' where id = r.replaces_id;
    delete from public.assistant_chunks where resource_id = r.replaces_id;
  end if;
end;
$$;

-- p: {topic_key, audience_role_ids, action: archive | restore | retry}
create or replace function public.update_assistant_resource(p_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  r     public.assistant_resources;
  v_roles uuid[];
begin
  perform private.require_permission('assistant.manage');
  select * into r from public.assistant_resources where id = p_id and org_id = v_org for update;
  if not found then
    raise exception 'Resource not found' using errcode = 'P0002';
  end if;
  if p ? 'topic_key' then
    if not exists (select 1 from public.assistant_topics where key = p ->> 'topic_key' and topic_group = 'knowledge' and key <> 'kb.app_guide') then
      raise exception 'Choose a topic for the file' using errcode = '22023';
    end if;
    update public.assistant_resources set topic_key = p ->> 'topic_key' where id = r.id;
  end if;
  if p ? 'audience_role_ids' then
    v_roles := private.uuid_array(p, 'audience_role_ids');
    if (select count(*) from public.roles where id = any (v_roles) and org_id = v_org) <> cardinality(v_roles) then
      raise exception 'Choose roles of your company' using errcode = '22023';
    end if;
    update public.assistant_resources set audience_role_ids = v_roles where id = r.id;
  end if;
  case p ->> 'action'
    when 'archive' then
      if r.status in ('uploading', 'archived') then
        raise exception 'Only an uploaded resource can be archived' using errcode = '23514';
      end if;
      update public.assistant_resources set status = 'archived' where id = r.id;
      delete from public.assistant_chunks where resource_id = r.id;
    when 'restore' then
      if r.status <> 'archived' then
        raise exception 'Only an archived resource can be restored' using errcode = '23514';
      end if;
      if exists (select 1 from public.assistant_resources x where x.org_id = v_org and x.status <> 'archived'
                 and (x.file_hash = r.file_hash or x.replaces_id = r.id)) then
        raise exception 'A newer version (or the same file) is active; archive it first' using errcode = '23514';
      end if;
      update public.assistant_resources set status = 'processing', processed_through = 0, error = null where id = r.id;
    when 'retry' then
      if r.status not in ('failed', 'processing') then
        raise exception 'Only a failed resource can be retried' using errcode = '23514';
      end if;
      update public.assistant_resources set status = 'processing', processed_through = 0, error = null where id = r.id;
    else
      null;
  end case;
end;
$$;

create or replace function public.list_assistant_resources()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('assistant.manage');
  return coalesce((select jsonb_agg(private.assistant_resource_json(r) order by r.status = 'archived', r.uploaded_at desc)
                   from public.assistant_resources r where r.org_id = v_org and r.status <> 'uploading'), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- Service RPCs (Edge Function, service role only)
-- -----------------------------------------------------------------------------
create or replace function public.service_assistant_resource(p_id uuid, p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.assistant_resource_json(r) || jsonb_build_object(
           'hyper', (select s.hyper from public.assistant_settings s where s.org_id = r.org_id))
  from public.assistant_resources r where r.id = p_id and r.org_id = p_org_id
$$;

-- p_chunks: [{chunk_index, location, section, passage, token_count, embedding: [1024 numbers]}]
create or replace function public.service_save_assistant_chunks(p_id uuid, p_org_id uuid, p_from integer, p_chunks jsonb,
                                                                p_done boolean, p_units integer, p_total integer, p_model text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.assistant_resources;
begin
  select * into r from public.assistant_resources where id = p_id and org_id = p_org_id for update;
  if not found or r.status <> 'processing' then
    raise exception 'This resource is not waiting to be indexed' using errcode = '23514';
  end if;
  if p_from = 0 then
    delete from public.assistant_chunks where resource_id = r.id;
  end if;
  insert into public.assistant_chunks (org_id, source, resource_id, chunk_index, location, section, passage, token_count, embedding, embedding_model)
  select r.org_id, 'resource', r.id, (c ->> 'chunk_index')::integer, left(c ->> 'location', 200), left(coalesce(c ->> 'section', ''), 300),
         c ->> 'passage', coalesce((c ->> 'token_count')::integer, 0), (c ->> 'embedding')::extensions.vector, p_model
  from jsonb_array_elements(coalesce(p_chunks, '[]'::jsonb)) c;
  update public.assistant_resources
     set processed_through = p_from + jsonb_array_length(coalesce(p_chunks, '[]'::jsonb)), units = p_units, chunks = p_total,
         status = case when p_done then 'ready' else status end, embedding_model = p_model, error = null
   where id = r.id;
end;
$$;

create or replace function public.service_fail_assistant_resource(p_id uuid, p_org_id uuid, p_error text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.assistant_resources set status = 'failed', error = left(coalesce(p_error, 'Indexing failed'), 500)
  where id = p_id and org_id = p_org_id and status = 'processing'
$$;

create or replace function public.service_guide_articles()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', a.key, 'route', a.route, 'title', a.title, 'title_bn', a.title_bn, 'body', a.body,
                                               'keywords', to_jsonb(a.keywords)) order by a.sort, a.key), '[]'::jsonb)
  from public.assistant_guide_articles a
$$;

-- Replaces the company's guide chunks (p_chunks like service_save_assistant_chunks, plus guide_key).
create or replace function public.service_save_guide_chunks(p_org_id uuid, p_chunks jsonb, p_model text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.assistant_chunks where org_id = p_org_id and source = 'guide';
  insert into public.assistant_chunks (org_id, source, guide_key, chunk_index, location, section, passage, token_count, embedding, embedding_model)
  select p_org_id, 'guide', c ->> 'guide_key', (c ->> 'chunk_index')::integer, c ->> 'location', coalesce(c ->> 'section', ''),
         c ->> 'passage', coalesce((c ->> 'token_count')::integer, 0), (c ->> 'embedding')::extensions.vector, p_model
  from jsonb_array_elements(coalesce(p_chunks, '[]'::jsonb)) c;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- The app guide (what each page does, how to use it, who may open it).
-- needs_any_of empty = every signed-in person; tour_targets = data-tour ids the widget can highlight.
-- -----------------------------------------------------------------------------
insert into public.assistant_guide_articles (key, route, title, body, needs_any_of, tour_targets, keywords, sort) values
('dashboard', '/', 'Dashboard',
 'The dashboard is the home page. People who can see employees get company figures (headcount, joiners and leavers, departments); everyone else gets a personal home with their profile and role. The notice banner at the top shows pinned notices, unread notices and notices you still have to acknowledge. The question mark button in the top bar replays the dashboard guide. The left sidebar lists every page your role may open; on a phone open it with the menu button.',
 '{}', '{sidebar,kpis,tour-help,user-menu}', '{home,start,menu,sidebar}', 1),
('my_profile', '/me', 'My profile',
 'My profile shows your personal details, job history and reporting chain. Some of your own fields can be edited when HR allows it (Roles & access, field visibility). The user menu at the top right also has Change password and Sign out.',
 '{}', '{user-menu}', '{profile,password,personal}', 2),
('my_attendance', '/attendance/me', 'My attendance',
 'My attendance is where you check in and check out for the day, from the browser (GPS, if your office requires the location) or by scanning the office QR code. It also shows your days of the month. If a punch is missing or wrong, send a request from this page; your manager or HR fixes it with a reason.',
 '{attendance.view_own}', '{}', '{check in,check out,punch,late,qr,gps}', 3),
('leave', '/leave', 'Leave',
 'Leave has the tabs My leave, Approvals and All requests. In My leave you see your balance per leave type and apply: pick the type and dates (half day where allowed) and press Submit; the days are reserved until your manager decides. You can cancel a pending request. Managers approve or reject in Approvals; nobody approves their own leave. HR sees every request in All requests.',
 '{leave.request,leave.approve,leave.view_all}', '{}', '{leave,holiday,apply,balance,casual,sick,approve}', 4),
('payslips', '/payslips', 'My payslips',
 'My payslips lists your monthly payslips once payroll is approved and released. Open one to see earnings, deductions and net pay in English or Bangla, see how each line was calculated, and print or save it as PDF.',
 '{payroll.view_own}', '{}', '{salary,payslip,pay,net}', 5),
('notices', '/notices', 'Notices',
 'Notices shows company announcements meant for you in the tab For me: pinned ones first, a dot for unread ones, and an English / বাংলা switch when a Bangla version exists. Some notices need "I have read and agree"; press it after reading. HR (and managers for their own department) also see the Manage tab: New notice, audience, schedule, expiry, pin, attachment, email copy and read receipts.',
 '{}', '{new-notice}', '{notice,announcement,circular,acknowledge,policy}', 6),
('helpdesk', '/helpdesk', 'Helpdesk',
 'Helpdesk is for support tickets. Press New ticket, choose a category and priority, describe the problem and attach files. The ticket goes to the handler of that category (or HR). You follow it in My tickets, reply in the thread, and when it is resolved you rate it or reopen it with a reason; without an answer it closes after a few working days. Handlers see Assigned to me; HR also sees All tickets and Setup (categories, handlers, SLA).',
 '{}', '{new-ticket}', '{ticket,support,it,problem,help,sla}', 7),
('my_reviews', '/my-reviews', 'My reviews',
 'My reviews shows the performance reviews written about you. Read the scores and comments and acknowledge the review.',
 '{}', '{}', '{review,performance,appraisal}', 8),
('my_interviews', '/my-interviews', 'My interviews',
 'My interviews lists the interviews where you sit on the panel. Open one for the interviewer kit (candidate summary, suggested questions) and submit your scores.',
 '{}', '{}', '{interview,panel,candidate}', 9),
('team_attendance', '/attendance', 'Attendance (team)',
 'Attendance has the tabs Daily, Monthly summary, Calendar, Reconciliation and Shift swaps. Managers see their team, HR the whole company. Fix a wrong day with Save fix (a reason is required), and approve shift swaps here.',
 '{attendance.view_team,attendance.view_all}', '{}', '{attendance,team,absent,late,swap,reconciliation}', 10),
('overtime', '/overtime', 'Overtime',
 'Overtime lists overtime records in the tabs Pending, Approved and Rejected. Approve or reject pending overtime of your team; HR can add manual overtime with Add.',
 '{overtime.view,overtime.approve}', '{}', '{overtime,ot,extra hours}', 11),
('employees', '/employees', 'Employees',
 'Employees is the people list with search and filters. Open a person for their profile (personal, history, reporting, financial). From the profile you can edit, transfer or promote, set the reporting manager, give or revoke portal access, print the ID card and deactivate.',
 '{employees.view}', '{}', '{employee,staff,people,profile,transfer,portal access}', 12),
('add_employee', '/employees/new', 'Add employee',
 'Add employee takes two steps: personal details, then job details (department, designation, branch, office, join date, employment type). The card ID is generated or typed, depending on the company setting. After saving, set the starting pay and give portal access from the profile.',
 '{employees.create}', '{}', '{new employee,hire,add staff,card id}', 13),
('payroll', '/payroll', 'Payroll runs',
 'Payroll runs: create a run for a month and scope (whole organization, one branch or one department) with Create and calculate, review it, Submit for approval; an Admin approves (the preparer cannot). Then download payment sheets, mark batches paid and lock the month. Adjustments (correction, arrear, manual) are in the Adjustments tab.',
 '{payroll.prepare,payroll.review,payroll.approve,payroll.reopen,payroll.lock}', '{}', '{payroll,salary run,payment,approve,lock}', 14),
('compensation', '/compensation', 'Compensation',
 'Compensation has the tabs Employee pay, Increments, Bonuses and Loans & advances. Increments need approval by someone else; back-dated ones create arrears.',
 '{compensation.view,increments.approve,bonuses.manage,deductions.manage}', '{}', '{increment,bonus,loan,advance,pay}', 15),
('salary_structure', '/salary', 'Salary structure',
 'Salary structure holds the salary components (earnings and deductions, fixed or percent of basic or gross) and templates used to set an employee''s pay.',
 '{compensation.view,compensation.edit}', '{}', '{component,template,basic,gross}', 16),
('time_setup', '/time', 'Time setup',
 'Time setup has the tabs Shifts, Roster, Holidays, Leave types, Overtime policy, Work rules and Geofences & QR. Work rules hold the labour law, weekly off days and the late policy.',
 '{shifts.manage,roster.manage,holidays.manage,attendance.settings,geofences.manage,leave.manage_types,overtime.manage_policy}', '{}', '{shift,roster,holiday,leave type,weekly off,geofence,qr}', 17),
('organization', '/organization', 'Organization',
 'Organization holds the structure: branches, offices, departments, designations (with grade) and operations. Deactivating a unit shows what it affects first.',
 '{org.view}', '{}', '{department,branch,office,designation,structure}', 18),
('roles', '/settings/roles', 'Roles & access',
 'Roles & access: each role has permissions and field visibility. Only an Admin creates roles and changes ticks; the Admin role always has everything.',
 '{roles.view}', '{}', '{role,permission,access,field visibility}', 19),
('password_requests', '/password-requests', 'Password requests',
 'Password requests lists people who pressed "Forgot password? Ask HR" on the login page. Press Reset to give a temporary password (they must change it when they sign in) or Dismiss with a reason.',
 '{users.reset_password}', '{}', '{password,reset,forgot,login}', 20),
('forgot_password', '/login', 'Forgot your password',
 'On the login page press "Forgot password? Ask HR" and enter your email or mobile number. HR gets the request and gives you a temporary password; you change it when you sign in.',
 '{}', '{}', '{forgot,password,login,sign in}', 21),
('tax', '/tax', 'Income tax & TDS',
 'Income tax & TDS: tax calculator, tax tables of the fiscal year, employee tax profiles and the TDS ledger with challans.',
 '{tax.view_profiles,tax.manage,payroll.prepare,payroll_settings.manage}', '{}', '{tax,tds,challan,tin}', 22),
('performance', '/performance', 'Performance',
 'Performance: review cycles with weighted criteria; HR and managers score their people, employees acknowledge in My reviews.',
 '{performance.manage,performance.review}', '{}', '{performance,cycle,criteria,score}', 23),
('hiring', '/job-posts', 'Hiring',
 'Hiring: Workforce plans headcount, Vacancies are reviewed and approved, Job posts publish an approved vacancy with a careers page, then applicants are screened, tested, interviewed, offered and joined.',
 '{recruit.manage,recruit.department,workforce.view,vacancy.request}', '{}', '{job,vacancy,applicant,recruit,hire,interview,offer}', 24),
('audit', '/audit', 'Audit log',
 'Audit log lists every important change: who, when and what, with filters. Only the Admin sees it.',
 '{audit.view}', '{}', '{audit,history,log}', 25),
('ai_setup', '/settings/assistant', 'AI assistant setup',
 'AI assistant setup: give the chat key and the embedding key, upload resources (PDF, DOCX, JSON), tune the model settings, decide per role what the assistant may show, and write the messages. The Admin can hand this page to the HR Manager.',
 '{assistant.manage}', '{}', '{assistant,ai,api key,resources}', 26)
on conflict (key) do update
  set route = excluded.route, title = excluded.title, body = excluded.body, needs_any_of = excluded.needs_any_of,
      tour_targets = excluded.tour_targets, keywords = excluded.keywords, sort = excluded.sort, updated_at = now();

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke all on function
  public.register_assistant_resource(jsonb), public.confirm_assistant_upload(uuid), public.update_assistant_resource(uuid, jsonb),
  public.list_assistant_resources(), public.service_assistant_resource(uuid, uuid),
  public.service_save_assistant_chunks(uuid, uuid, integer, jsonb, boolean, integer, integer, text),
  public.service_fail_assistant_resource(uuid, uuid, text), public.service_guide_articles(), public.service_save_guide_chunks(uuid, jsonb, text)
from public, anon;
grant execute on function
  public.register_assistant_resource(jsonb), public.confirm_assistant_upload(uuid), public.update_assistant_resource(uuid, jsonb),
  public.list_assistant_resources()
to authenticated;
revoke all on function
  public.service_assistant_resource(uuid, uuid), public.service_save_assistant_chunks(uuid, uuid, integer, jsonb, boolean, integer, integer, text),
  public.service_fail_assistant_resource(uuid, uuid, text), public.service_guide_articles(), public.service_save_guide_chunks(uuid, jsonb, text)
from authenticated;
grant execute on function
  public.service_assistant_resource(uuid, uuid), public.service_save_assistant_chunks(uuid, uuid, integer, jsonb, boolean, integer, integer, text),
  public.service_fail_assistant_resource(uuid, uuid, text), public.service_guide_articles(), public.service_save_guide_chunks(uuid, jsonb, text)
to service_role;

revoke all on function private.assistant_resource_path(public.assistant_resources), private.assistant_resource_json(public.assistant_resources)
from public, anon, authenticated;
grant execute on function private.assistant_file_access(text, boolean) to authenticated;
revoke all on function private.assistant_file_access(text, boolean) from public, anon;
