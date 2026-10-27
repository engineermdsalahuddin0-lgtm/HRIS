-- =============================================================================
-- AI assistant AI4 tests: resources, storage access, indexing, app guide.
--
-- Alpha: the Admin uploads a leave policy (company policy) and a disciplinary SOP (confidential). Sam is an employee.
--   1. Register: duplicates refused before the upload; the storage path is fixed by the database; only a row that
--      waits for its file accepts an upload; Sam cannot read the confidential file, but can read the leave policy.
--   2. Indexing through the service role: chunks with 1024-dim vectors, resource ready; users cannot call it.
--   3. New version archives the old one and drops its chunks; restore refused while the newer one is active.
--   4. Changed chunking returns the ready PDFs to process; a new embedding model re-indexes everything.
--   5. The app guide ships with every page article; the service role saves guide chunks per company.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL AI4 ASSISTANT CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000a4001', 'authenticated', 'authenticated', 'ai4platform@olympus.test', now(), '{"full_name":"AI4 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a4002', 'authenticated', 'authenticated', 'ai4owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000a4001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a4002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Index', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a4001","role":"authenticated"}', true);
select set_config('t.org', public.approve_org_signup_request(
  (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a4002'))::text, true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a4002","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_des uuid; v_branch uuid; v_office uuid;
begin
  insert into public.departments (name) values ('Ops') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name) values (v_dept, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
    'department_id', v_dept, 'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Sam Staff')),
    'sam@ai4.test', null, 'Passw0rd1', null)::text, true);
  perform public.save_assistant_key('{"slot":"chat","provider":"openai","model":"gpt-4.1-mini","api_key":"sk-openai-abcdefghijklmnop1234"}');
  perform public.record_assistant_key_test('chat', true, 'ok');
end $$;

-- ======================================================= 1. register and storage
do $$
declare
  v_leave jsonb;
  v_sop   jsonb;
begin
  v_leave := public.register_assistant_resource(jsonb_build_object('name', 'Leave Policy 2026.pdf', 'kind', 'pdf', 'size_bytes', 400000,
             'file_hash', repeat('a', 64), 'topic_key', 'kb.company_policy'));
  v_sop := public.register_assistant_resource(jsonb_build_object('name', 'Disciplinary SOP.docx', 'kind', 'docx', 'size_bytes', 90000,
             'file_hash', repeat('b', 64), 'topic_key', 'kb.confidential'));
  perform set_config('t.leave', v_leave ->> 'id', true);
  perform set_config('t.leave_path', v_leave ->> 'path', true);
  perform set_config('t.sop', v_sop ->> 'id', true);
  perform set_config('t.sop_path', v_sop ->> 'path', true);
  assert v_leave ->> 'path' = current_setting('t.org') || '/' || (v_leave ->> 'id') || '/v1.pdf', 'path fixed by the database';
  begin
    perform public.register_assistant_resource(jsonb_build_object('name', 'Copy.pdf', 'kind', 'pdf', 'size_bytes', 400000,
            'file_hash', repeat('a', 64), 'topic_key', 'kb.company_policy'));
    raise exception 'FAIL: a duplicate file registered';
  exception when unique_violation then null;
  end;
  begin
    perform public.register_assistant_resource(jsonb_build_object('name', 'Guide.pdf', 'kind', 'pdf', 'size_bytes', 10,
            'file_hash', repeat('c', 64), 'topic_key', 'kb.app_guide'));
    raise exception 'FAIL: uploaded into the app guide topic';
  exception when invalid_parameter_value then null;
  end;
  insert into storage.objects (bucket_id, name) values ('assistant-resources', current_setting('t.leave_path'));
  insert into storage.objects (bucket_id, name) values ('assistant-resources', current_setting('t.sop_path'));
  begin
    insert into storage.objects (bucket_id, name) values ('assistant-resources', current_setting('t.org') || '/' || current_setting('t.leave') || '/other.pdf');
    raise exception 'FAIL: a file outside the fixed path';
  exception when insufficient_privilege then null;
  end;
  perform public.confirm_assistant_upload(current_setting('t.leave')::uuid);
  perform public.confirm_assistant_upload(current_setting('t.sop')::uuid);
  begin
    insert into storage.objects (bucket_id, name) values ('assistant-resources', current_setting('t.leave_path'));
    raise exception 'FAIL: overwrote a confirmed file';
  exception when insufficient_privilege or unique_violation then null;
  end;
end $$;
-- Both are readable for Sam only after indexing (ready); index them first.
reset role;
set local role service_role;
do $$
declare
  v_vec jsonb := to_jsonb(array_fill(0.01::real, array[1024]));
begin
  perform public.service_save_assistant_chunks(current_setting('t.leave')::uuid, current_setting('t.org')::uuid, 0,
    jsonb_build_array(jsonb_build_object('chunk_index', 0, 'location', '2', 'section', 'Casual leave', 'passage', '10 days of casual leave', 'token_count', 6, 'embedding', v_vec),
                      jsonb_build_object('chunk_index', 1, 'location', '3', 'section', 'Sick leave', 'passage', '14 days of sick leave', 'token_count', 6, 'embedding', v_vec)),
    true, 9, 2, 'text-embedding-3-small');
  perform public.service_save_assistant_chunks(current_setting('t.sop')::uuid, current_setting('t.org')::uuid, 0,
    jsonb_build_array(jsonb_build_object('chunk_index', 0, 'location', '1', 'section', 'Show-cause', 'passage', '7 days to reply', 'embedding', v_vec)),
    true, 2, 1, 'text-embedding-3-small');
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.assistant_chunks where org_id = current_setting('t.org')::uuid and source = 'resource') = 3, 'chunks saved';
  assert (select extensions.vector_dims(embedding) from public.assistant_chunks limit 1) = 1024, '1024 dimensions';
  assert (select status from public.assistant_resources where id = current_setting('t.leave')::uuid) = 'ready', 'ready';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert (select count(*) from storage.objects where bucket_id = 'assistant-resources' and name = current_setting('t.leave_path')) = 1, 'Sam reads the leave policy';
  assert (select count(*) from storage.objects where bucket_id = 'assistant-resources' and name = current_setting('t.sop_path')) = 0, 'Sam cannot read the confidential SOP';
  begin
    perform public.service_save_assistant_chunks(current_setting('t.leave')::uuid, current_setting('t.org')::uuid, 0, '[]', true, 0, 0, 'x');
    raise exception 'FAIL: a user wrote chunks';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.list_assistant_resources();
    raise exception 'FAIL: an employee listed resources';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: duplicates refused before upload; fixed paths; readers follow topic and role; only the service role indexes';
end $$;

-- ======================================================= 3. versions
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a4002","role":"authenticated"}', true);
do $$
declare
  v jsonb;
begin
  v := public.register_assistant_resource(jsonb_build_object('name', 'Leave Policy 2027.pdf', 'kind', 'pdf', 'size_bytes', 410000,
       'file_hash', repeat('d', 64), 'topic_key', 'kb.hr_rules', 'replaces_id', current_setting('t.leave')));
  assert (v ->> 'version')::int = 2 and v ->> 'topic_key' = 'kb.company_policy', 'version 2 keeps the topic';
  perform set_config('t.leave2', v ->> 'id', true);
  insert into storage.objects (bucket_id, name) values ('assistant-resources', v ->> 'path');
  perform public.confirm_assistant_upload((v ->> 'id')::uuid);
  assert (select x ->> 'status' from jsonb_array_elements(public.list_assistant_resources()) x where x ->> 'id' = current_setting('t.leave')) = 'archived',
         'the old version is archived';
  begin
    perform public.update_assistant_resource(current_setting('t.leave')::uuid, '{"action":"restore"}');
    raise exception 'FAIL: restored while the newer version is active';
  exception when check_violation then null;
  end;
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.assistant_chunks where resource_id = current_setting('t.leave')::uuid) = 0, 'old chunks dropped';
  raise notice 'PASS: a new version archives the old one and drops its chunks';
end $$;
set local role authenticated;

-- ======================================================= 4. re-indexing
do $$
declare
  v uuid[];
begin
  v := public.save_assistant_hyper('{"temperature":0.2,"max_answer_tokens":600,"answer_style":"short","top_k":6,"min_score":0.3,"chunk_size":500,"chunk_overlap":15}');
  -- Ready PDF / DOCX: only the SOP (the new leave version is still processing).
  assert v = array[current_setting('t.sop')::uuid], 'changed chunking re-processes ready documents ' || v::text;
  perform public.save_assistant_key('{"slot":"embed","provider":"voyage","model":"voyage-3.5","api_key":"pa-voyage-key-0123456789abcd"}');
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from public.assistant_resources where org_id = current_setting('t.org')::uuid and status = 'ready'),
         'a new embedding model sends every resource back to indexing';
  raise notice 'PASS: chunking and embedding changes re-index';
end $$;

-- ======================================================= 5. app guide
set local role service_role;
do $$
declare
  v jsonb := public.service_guide_articles();
  v_vec jsonb := to_jsonb(array_fill(0.02::real, array[1024]));
begin
  assert jsonb_array_length(v) >= 20 and exists (select 1 from jsonb_array_elements(v) a where a ->> 'route' = '/leave'), 'guide articles shipped';
  assert public.service_save_guide_chunks(current_setting('t.org')::uuid, (
    select jsonb_agg(jsonb_build_object('guide_key', a ->> 'key', 'chunk_index', 0, 'location', a ->> 'route', 'section', a ->> 'title',
                                        'passage', a ->> 'body', 'embedding', v_vec))
    from jsonb_array_elements(v) a), 'voyage-3.5') = jsonb_array_length(v), 'one guide chunk per article';
  raise notice 'PASS: the app guide is shipped once and indexed per company';
end $$;

select '==== ALL AI4 ASSISTANT CHECKS PASSED ====' as result;
rollback;
