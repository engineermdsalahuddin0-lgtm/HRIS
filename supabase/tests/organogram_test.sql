-- =============================================================================
-- Department organogram tests: budget, grade slots, position states, live updates.
--
-- Finance: budget 10, slots ED 1 · DGM 3 · AGM 3 · Senior Executive 3 (= 10).
--   People: 1 ED, 1 DGM, 5 AGM (joined 2020…2024) -> ED filled; DGM 1 filled + 2 vacant;
--   AGM 3 filled + 2 EXTRA (the two who joined last); Senior Executive 3 vacant.
--   Toggle a DGM slot vacant <-> blocked; block all unfilled DGM.
--   An approved requisition for Senior Executive turns one vacant card into "in recruitment"
--   (stage, candidates).
--   AGM A1 resigns (after-separation = vacant): A4 moves from extra into the freed slot and a
--   replacement is drafted. Policy -> blocked; A2 resigns: the slot is blocked, A5 stays extra,
--   no replacement drafted.
--   Hard rule: 5 filled + offers in process may not pass the budget; the budget cannot drop below
--   filled + offers; slots may not add up to more than the budget.
--   R1 reads the budget; approving a new position raises budget and the grade slot.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL ORGANOGRAM CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000aaa1', 'authenticated', 'authenticated', 'orgplatform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-00000000aaa2', 'authenticated', 'authenticated', 'orgowner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-00000000aaa3', 'authenticated', 'authenticated', 'orgowner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-00000000aaa1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Chart', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Chart', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-00000000aaa2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-00000000aaa3'));
end $$;

-- Alpha admin: Finance with four designations mapped to organogram grades.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
do $$
declare
  v_fin    uuid;
  v_ops    uuid;
  v_branch uuid;
  v_office uuid;
  v_g      jsonb := public.list_organogram_grades();
  v_id     uuid;
  r        record;
begin
  assert (select array_agg(g ->> 'code' order by (g ->> 'rank')::int) from jsonb_array_elements(v_g -> 'grades') g)
         = array['CEO', 'ED', 'GM', 'DGM', 'AGM', 'SREXEC', 'EXEC', 'JREXEC'], 'default ladder';
  for r in select g ->> 'code' as code, (g ->> 'id') as id from jsonb_array_elements(v_g -> 'grades') g loop
    perform set_config('t.g_' || lower(r.code), r.id, true);
  end loop;
  insert into public.departments (name) values ('Finance') returning id into v_fin;
  insert into public.departments (name) values ('Operations') returning id into v_ops;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Head Office') returning id into v_office;
  perform set_config('t.fin', v_fin::text, true);
  perform set_config('t.ops', v_ops::text, true);
  perform set_config('t.branch', v_branch::text, true);
  perform set_config('t.office', v_office::text, true);
  perform set_config('t.org_id', private.current_org_id()::text, true);
  insert into public.designations (department_id, grade_id, name) values (v_fin, (select id from public.grades where code = 'OWNER01'), 'Executive Director') returning id into v_id;
  perform set_config('t.d_ed', v_id::text, true);
  insert into public.designations (department_id, grade_id, name) values (v_fin, (select id from public.grades where code = 'MS2'), 'DGM Finance') returning id into v_id;
  perform set_config('t.d_dgm', v_id::text, true);
  insert into public.designations (department_id, grade_id, name) values (v_fin, (select id from public.grades where code = 'MS1'), 'AGM Finance') returning id into v_id;
  perform set_config('t.d_agm', v_id::text, true);
  insert into public.designations (department_id, grade_id, name) values (v_fin, (select id from public.grades where code = 'MS0'), 'Senior Executive') returning id into v_id;
  perform set_config('t.d_sr', v_id::text, true);
  insert into public.designations (department_id, grade_id, name) values (v_ops, (select id from public.grades where code = 'MS1'), 'AGM Operations') returning id into v_id;
  perform set_config('t.d_ops', v_id::text, true);
  perform public.set_designation_organogram_grade(current_setting('t.d_ed')::uuid, current_setting('t.g_ed')::uuid);
  perform public.set_designation_organogram_grade(current_setting('t.d_dgm')::uuid, current_setting('t.g_dgm')::uuid);
  perform public.set_designation_organogram_grade(current_setting('t.d_agm')::uuid, current_setting('t.g_agm')::uuid);
  perform public.set_designation_organogram_grade(current_setting('t.d_sr')::uuid, current_setting('t.g_srexec')::uuid);
  perform public.set_designation_organogram_grade(current_setting('t.d_ops')::uuid, current_setting('t.g_agm')::uuid);
end $$;

-- ======================================================= 1. budget and slots
do $$
declare
  v_slots jsonb := jsonb_build_array(
    jsonb_build_object('grade_id', current_setting('t.g_ed'), 'planned', 1), jsonb_build_object('grade_id', current_setting('t.g_dgm'), 'planned', 3),
    jsonb_build_object('grade_id', current_setting('t.g_agm'), 'planned', 3), jsonb_build_object('grade_id', current_setting('t.g_srexec'), 'planned', 3));
  v jsonb;
begin
  begin
    perform public.save_department_budget(current_setting('t.fin')::uuid, jsonb_build_object('approved_headcount', 9, 'slots', v_slots));
    raise exception 'FAIL: slots (10) above the budget (9) accepted';
  exception when check_violation then null;
  end;
  v := public.save_department_budget(current_setting('t.fin')::uuid, jsonb_build_object('approved_headcount', 10, 'slots', v_slots));
  assert (v ->> 'budget')::int = 10 and (v ->> 'filled')::int = 0, 'budget saved ' || v::text;
  v := public.get_department_organogram(current_setting('t.fin')::uuid);
  assert (select count(*) from jsonb_array_elements(v -> 'grades') g, jsonb_array_elements(g -> 'positions') p where p ->> 'state' = 'vacant') = 10,
         'ten vacant positions before anyone is placed';
  raise notice 'PASS: slots may not exceed the budget; the tree starts with one vacant position per slot';
end $$;

-- People join: 1 ED, 1 DGM, 5 AGM.
do $$
declare
  v_common jsonb := jsonb_build_object('employment_type', 'permanent', 'department_id', current_setting('t.fin'),
                                       'branch_id', current_setting('t.branch'), 'office_id', current_setting('t.office'));
  i integer;
begin
  perform public.create_employee(v_common || jsonb_build_object('full_name', 'Ed Person', 'designation_id', current_setting('t.d_ed'), 'join_date', '2019-01-01'));
  perform set_config('t.e_dgm', public.create_employee(v_common || jsonb_build_object('full_name', 'Dgm Person', 'designation_id', current_setting('t.d_dgm'),
                                                                                      'join_date', '2019-06-01'))::text, true);
  for i in 1..5 loop
    perform set_config('t.agm' || i, public.create_employee(v_common || jsonb_build_object('full_name', 'Agm ' || i,
      'designation_id', current_setting('t.d_agm'), 'join_date', (2019 + i) || '-01-01'))::text, true);
  end loop;
end $$;

create temp table chart_state on commit drop as select 1 as dummy;
do $$
declare
  v jsonb := public.get_department_organogram(current_setting('t.fin')::uuid);
  agm jsonb := (select g from jsonb_array_elements(v -> 'grades') g where g ->> 'code' = 'AGM');
  dgm jsonb := (select g from jsonb_array_elements(v -> 'grades') g where g ->> 'code' = 'DGM');
begin
  assert (v -> 'counts' ->> 'filled')::int = 7 and (v -> 'counts' ->> 'headroom')::int = 3, 'counts ' || (v -> 'counts')::text;
  assert (select count(*) from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'filled') = 3
         and (select count(*) from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'extra') = 2, 'AGM 3 filled + 2 extra';
  assert (select array_agg(p -> 'employee' ->> 'full_name' order by p -> 'employee' ->> 'full_name') from jsonb_array_elements(agm -> 'positions') p
          where p ->> 'state' = 'extra') = array['Agm 4', 'Agm 5'], 'the latest joiners are extra';
  assert (select count(*) from jsonb_array_elements(dgm -> 'positions') p where p ->> 'state' = 'vacant') = 2, 'DGM 2 vacant';
  raise notice 'PASS: people fill planned slots of their grade; above the slots extra positions appear';
end $$;

-- ======================================================= 2. vacant <-> blocked
do $$
declare
  v_pos uuid := (select (p ->> 'id')::uuid from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g,
                 jsonb_array_elements(g -> 'positions') p where g ->> 'code' = 'DGM' and p ->> 'state' = 'vacant' order by (p ->> 'slot_no')::int desc limit 1);
  v_filled uuid := (select (p ->> 'id')::uuid from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g,
                    jsonb_array_elements(g -> 'positions') p where g ->> 'code' = 'DGM' and p ->> 'state' = 'filled');
  st text;
begin
  perform public.set_position_hold(v_pos, 'blocked');
  select p ->> 'state' into st from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g,
         jsonb_array_elements(g -> 'positions') p where (p ->> 'id')::uuid = v_pos;
  assert st = 'blocked', 'slot blocked';
  perform public.set_position_hold(v_pos, 'vacant');
  begin
    perform public.set_position_hold(v_filled, 'blocked');
    raise exception 'FAIL: a filled position was blocked';
  exception when invalid_parameter_value then null;
  end;
  assert public.set_department_holds(current_setting('t.fin')::uuid, 'blocked', current_setting('t.g_dgm')::uuid) = 2, 'two DGM slots blocked';
  raise notice 'PASS: per-slot toggle vacant <-> blocked, bulk block of a grade; filled positions are never blocked';
end $$;

-- ======================================================= 3. in recruitment
do $$
declare
  v_vac uuid := public.draft_vacancy(jsonb_build_object('department_id', current_setting('t.fin'), 'designation_id', current_setting('t.d_sr'),
                                                        'seats', 1, 'reason', 'replacement'));
begin
  perform set_config('t.vac', v_vac::text, true);
end $$;
-- HR forwards (maker-checker), the owner approves.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
do $$
declare
  v_hr uuid;
begin
  v_hr := public.create_employee(jsonb_build_object('employment_type', 'permanent', 'department_id', current_setting('t.ops'),
          'designation_id', current_setting('t.d_ops'), 'branch_id', current_setting('t.branch'), 'office_id', current_setting('t.office'),
          'join_date', '2021-01-01', 'full_name', 'Hr Person'));
  perform set_config('t.u_hr', public.grant_portal_access(v_hr, 'hr@chart.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');
do $$
declare
  sr jsonb := (select g from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g where g ->> 'code' = 'SREXEC');
  rec jsonb;
begin
  assert (select count(*) from jsonb_array_elements(sr -> 'positions') p where p ->> 'state' = 'in_recruitment') = 1
         and (select count(*) from jsonb_array_elements(sr -> 'positions') p where p ->> 'state' = 'vacant') = 2, 'one in recruitment ' || sr::text;
  rec := (select p -> 'recruitment' from jsonb_array_elements(sr -> 'positions') p where p ->> 'state' = 'in_recruitment');
  assert rec ->> 'stage' = 'Requisition approved' and (rec ->> 'candidates')::int = 0, 'stage ' || rec::text;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_post uuid;
  rec    jsonb;
begin
  perform public.save_job_profile(current_setting('t.d_sr')::uuid, '{"duties":"Prepare and check vouchers"}'::jsonb);
  v_post := public.create_job_post_from_vacancy(current_setting('t.vac')::uuid);
  perform public.publish_job_post(v_post);
  perform set_config('t.post', v_post::text, true);
  perform public.add_applicants(v_post, '[{"full_name":"Cand One","email":"one@example.com"},{"full_name":"Cand Two","email":"two@example.com"}]'::jsonb, 'email');
  rec := (select p -> 'recruitment' from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g,
          jsonb_array_elements(g -> 'positions') p where g ->> 'code' = 'SREXEC' and p ->> 'state' = 'in_recruitment');
  assert rec ->> 'stage' = 'Applications' and (rec ->> 'candidates')::int = 2, 'stage with candidates ' || rec::text;
  raise notice 'PASS: an approved requisition shows as in recruitment with its stage and candidate count';
end $$;

-- ======================================================= 4. separations update the tree live
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
do $$
declare
  v_before integer := (select count(*) from jsonb_array_elements(public.list_vacancies()));
  agm jsonb;
begin
  perform public.deactivate_employee(current_setting('t.agm1')::uuid, 'inactive', '2026-08-20', 'Resigned');
  agm := (select g from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g where g ->> 'code' = 'AGM');
  assert (select count(*) from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'filled') = 3
         and (select array_agg(p -> 'employee' ->> 'full_name') from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'extra') = array['Agm 5'],
         'Agm 4 moved from extra into the freed slot ' || agm::text;
  assert (select count(*) from jsonb_array_elements(public.list_vacancies())) = v_before + 1, 'replacement drafted';

  perform public.save_department_budget(current_setting('t.fin')::uuid, jsonb_build_object('approved_headcount', 10, 'after_separation', 'blocked',
    'slots', jsonb_build_array(jsonb_build_object('grade_id', current_setting('t.g_ed'), 'planned', 1), jsonb_build_object('grade_id', current_setting('t.g_dgm'), 'planned', 3),
      jsonb_build_object('grade_id', current_setting('t.g_agm'), 'planned', 3), jsonb_build_object('grade_id', current_setting('t.g_srexec'), 'planned', 3))));
  perform public.deactivate_employee(current_setting('t.agm2')::uuid, 'inactive', '2026-08-21', 'Resigned');
  agm := (select g from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g where g ->> 'code' = 'AGM');
  assert (select count(*) from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'blocked') = 1
         and (select count(*) from jsonb_array_elements(agm -> 'positions') p where p ->> 'state' = 'extra') = 1, 'freed slot blocked, Agm 5 stays extra';
  assert (select count(*) from jsonb_array_elements(public.list_vacancies())) = v_before + 1, 'no replacement for a blocked slot';
  assert (public.get_department_organogram(current_setting('t.fin')::uuid) -> 'counts' ->> 'filled')::int = 5, 'five filled';
  raise notice 'PASS: a leaver frees the position (vacant -> extra moves in, replacement drafted; blocked -> no replacement)';
end $$;

-- ======================================================= 5. the hard budget rule
reset role;
do $$
declare
  v_tpl uuid;
  v_app uuid;
begin
  insert into public.salary_templates (org_id, name, basic_amount) values (current_setting('t.org_id')::uuid, 'Basic only', 10000) returning id into v_tpl;
  perform set_config('t.tpl', v_tpl::text, true);
  -- Budget 10, filled 5: put four approved offers in process (5 + 4 = 9).
  for v_app in select id from public.applicants where job_post_id = current_setting('t.post')::uuid loop
    insert into public.offers (org_id, applicant_id, job_post_id, department_id, designation_id, office_id, employment_type,
                               salary_template_id, gross, joining_date, expires_on, status)
    values (current_setting('t.org_id')::uuid, v_app, current_setting('t.post')::uuid, current_setting('t.fin')::uuid, current_setting('t.d_sr')::uuid,
            current_setting('t.office')::uuid, 'permanent', v_tpl, 30000, current_date + 20, current_date + 5, 'approved');
  end loop;
end $$;
do $$
declare
  v_c jsonb := private.department_counts(current_setting('t.fin')::uuid);
begin
  assert (v_c ->> 'filled')::int = 5 and (v_c ->> 'offers_in_process')::int = 2 and (v_c ->> 'available')::int = 3, 'counts ' || v_c::text;
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
do $$
declare
  v_slots jsonb := jsonb_build_array(jsonb_build_object('grade_id', current_setting('t.g_ed'), 'planned', 1),
                                     jsonb_build_object('grade_id', current_setting('t.g_agm'), 'planned', 3),
                                     jsonb_build_object('grade_id', current_setting('t.g_dgm'), 'planned', 1),
                                     jsonb_build_object('grade_id', current_setting('t.g_srexec'), 'planned', 1));
begin
  begin
    perform public.save_department_budget(current_setting('t.fin')::uuid, jsonb_build_object('approved_headcount', 6, 'slots', v_slots));
    raise exception 'FAIL: budget cut below filled + offers';
  exception when check_violation then null;
  end;
  -- Budget 7 = 5 filled + 2 offers: legal, but full.
  perform public.save_department_budget(current_setting('t.fin')::uuid, jsonb_build_object('approved_headcount', 7, 'slots', v_slots));
end $$;
reset role;
do $$
declare
  v_app uuid;
begin
  insert into public.applicants (org_id, job_post_id, full_name, email, source)
  values (current_setting('t.org_id')::uuid, current_setting('t.post')::uuid, 'Cand Three', 'three@example.com', 'email') returning id into v_app;
  begin
    insert into public.offers (org_id, applicant_id, job_post_id, department_id, designation_id, office_id, employment_type,
                               salary_template_id, gross, joining_date, expires_on)
    values (current_setting('t.org_id')::uuid, v_app, current_setting('t.post')::uuid, current_setting('t.fin')::uuid, current_setting('t.d_sr')::uuid,
            current_setting('t.office')::uuid, 'permanent', current_setting('t.tpl')::uuid, 30000, current_date + 20, current_date + 5);
    raise exception 'FAIL: an offer above the budget was created';
  exception when check_violation then null;
  end;
  -- The surplus planned slots went: DGM keeps 1 (filled), the blocked AGM slot stays, SREXEC 1.
  assert (select count(*) from public.positions where department_id = current_setting('t.fin')::uuid and kind = 'planned') = 6, 'planned = slots';
  raise notice 'PASS: filled + offers in process never pass the budget; the budget cannot drop below them';
end $$;

-- ======================================================= 6. R1 reads the budget; new positions raise it
do $$
begin
  assert private.department_sanctioned(current_setting('t.fin')::uuid) = 7, 'R1 sanctioned = budget';
  assert (private.department_workload(current_setting('t.org_id')::uuid, current_setting('t.fin')::uuid, date_trunc('month', current_date)::date) ->> 'sanctioned')::int = 7,
         'workload uses the budget';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
select set_config('t.vac2', public.draft_vacancy(jsonb_build_object('department_id', current_setting('t.fin'), 'designation_id', current_setting('t.d_sr'),
                                                                    'seats', 2, 'reason', 'new_position'))::text, true);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac2')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac2')::uuid, 'approve');
do $$
declare
  v jsonb := public.get_department_organogram(current_setting('t.fin')::uuid);
begin
  assert (v -> 'budget' ->> 'approved_headcount')::int = 9
         and (select (g ->> 'planned')::int from jsonb_array_elements(v -> 'grades') g where g ->> 'code' = 'SREXEC') = 3, 'budget 9, Sr Exec slots 3';
  raise notice 'PASS: R1 workload reads the budget; approving a new position raises the budget and the grade slot';
end $$;

-- ======================================================= 7. grades, transfers, permissions
do $$
begin
  begin
    perform public.save_organogram_grade(current_setting('t.g_agm')::uuid, '{"code":"AGM","name":"AGM","rank":5,"status":"inactive"}');
    raise exception 'FAIL: a grade with positions was deactivated';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_organogram_grade(null, '{"code":"MGR","name":"Manager","rank":5}');
  -- Transfer the DGM to Operations: the Finance DGM slot becomes vacant again.
  perform public.transfer_employee(current_setting('t.e_dgm')::uuid,
    jsonb_build_object('department_id', current_setting('t.ops'), 'designation_id', current_setting('t.d_ops'),
                       'branch_id', current_setting('t.branch'), 'office_id', current_setting('t.office'),
                       'effective_date', current_date, 'reason', 'Moved'));
  assert (select count(*) from jsonb_array_elements(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') g,
          jsonb_array_elements(g -> 'positions') p where g ->> 'code' = 'DGM' and p ->> 'state' = 'filled') = 0, 'DGM freed by the transfer';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.save_department_budget(current_setting('t.fin')::uuid, '{"approved_headcount":50}');
    raise exception 'FAIL: HR changed the budget';
  exception when insufficient_privilege then null;
  end;
  assert jsonb_array_length(public.get_department_organogram(current_setting('t.fin')::uuid) -> 'grades') >= 8, 'HR may view';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000aaa3","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_department_organogram(current_setting('t.fin')::uuid);
    raise exception 'FAIL: Beta opened an Alpha organogram';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: grades editable (not while in use), transfers free positions, budget is Admin-only, company isolation';
end $$;

select '==== ALL ORGANOGRAM CHECKS PASSED ====' as result;
rollback;
