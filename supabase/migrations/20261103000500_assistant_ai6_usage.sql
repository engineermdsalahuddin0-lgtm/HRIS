-- =============================================================================
-- AI assistant AI6: usage figures and the retention purge.
-- Design: docs/Part04Architecture.md (sections 7 Usage, 8.7; decisions D6, D7).
--
-- Usage (assistant.view_usage, Admin only): questions per day and per role,
-- tokens this month against the cap, questions the assistant could not answer
-- (gaps in the documents) and answers marked "not helpful".
-- Purge (D6 / D7): after retention_days (90) the question text is removed from
-- the log (counts stay) and old conversations are deleted. No pg_cron yet: the
-- Admin runs it from the Usage tab; schedule private.purge_assistant_logs()
-- with the other jobs when pg_cron is set up.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.assistant_prepare') is null then
    raise exception 'Apply 20261103000400_assistant_ai5_ask.sql first, then run this file again';
  end if;
end;
$guard$;

create or replace function public.get_assistant_usage(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_tz   text := (select timezone from public.organizations where id = private.current_org_id());
begin
  perform private.require_permission('assistant.view_usage');
  return jsonb_build_object(
    'days', v_days,
    'total', (select count(*) from public.assistant_query_log where org_id = v_org and asked_at > now() - v_days * interval '1 day'),
    'by_kind', coalesce((select jsonb_object_agg(kind, n) from (
        select kind, count(*) n from public.assistant_query_log
        where org_id = v_org and asked_at > now() - v_days * interval '1 day' group by kind) k), '{}'::jsonb),
    'per_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'questions', n) order by d) from (
        select (asked_at at time zone v_tz)::date d, count(*) n from public.assistant_query_log
        where org_id = v_org and asked_at > now() - v_days * interval '1 day' group by 1) x), '[]'::jsonb),
    'per_role', coalesce((select jsonb_agg(jsonb_build_object('role', coalesce(r.name, 'Removed role'), 'questions', n, 'people', p) order by n desc) from (
        select role_id, count(*) n, count(distinct user_id) p from public.assistant_query_log
        where org_id = v_org and asked_at > now() - v_days * interval '1 day' group by role_id) x
        left join public.roles r on r.id = x.role_id), '[]'::jsonb),
    'tokens_month', coalesce((select sum(tokens_in + tokens_out) from public.assistant_query_log
                              where org_id = v_org and asked_at >= date_trunc('month', now())), 0),
    'monthly_cap', (select monthly_token_cap from public.assistant_settings where org_id = v_org),
    -- Question text is kept only for the retention period; names are not shown.
    'unanswered', coalesce((select jsonb_agg(jsonb_build_object('question', question, 'route', route, 'asked_at', asked_at) order by asked_at desc) from (
        select question, route, asked_at from public.assistant_query_log
        where org_id = v_org and kind in ('dont_know', 'not_allowed') and question is not null
          and asked_at > now() - v_days * interval '1 day' order by asked_at desc limit 25) x), '[]'::jsonb),
    'not_helpful', coalesce((select jsonb_agg(jsonb_build_object('question', question, 'route', route, 'asked_at', asked_at) order by asked_at desc) from (
        select question, route, asked_at from public.assistant_query_log
        where org_id = v_org and helpful = false and question is not null
          and asked_at > now() - v_days * interval '1 day' order by asked_at desc limit 25) x), '[]'::jsonb),
    'retention_days', (select retention_days from public.assistant_settings where org_id = v_org));
end;
$$;

create or replace function private.purge_assistant_logs(p_org_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_questions integer;
  v_messages  integer;
  v_chats     integer;
begin
  update public.assistant_query_log q set question = null
    from public.assistant_settings s
   where s.org_id = q.org_id and (p_org_id is null or q.org_id = p_org_id)
     and q.question is not null and q.asked_at < now() - s.retention_days * interval '1 day';
  get diagnostics v_questions = row_count;
  with old as (
    select c.id from public.assistant_conversations c join public.assistant_settings s on s.org_id = c.org_id
    where (p_org_id is null or c.org_id = p_org_id) and c.last_at < now() - s.retention_days * interval '1 day')
  delete from public.assistant_messages m using old where m.conversation_id = old.id;
  get diagnostics v_messages = row_count;
  delete from public.assistant_conversations c using public.assistant_settings s
   where s.org_id = c.org_id and (p_org_id is null or c.org_id = p_org_id) and c.last_at < now() - s.retention_days * interval '1 day';
  get diagnostics v_chats = row_count;
  return jsonb_build_object('questions_cleared', v_questions, 'messages_deleted', v_messages, 'conversations_deleted', v_chats);
end;
$$;

create or replace function public.run_assistant_purge()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  perform private.require_permission('assistant.view_usage');
  v := private.purge_assistant_logs(private.current_org_id());
  perform private.write_audit(private.current_org_id(), 'assistant.purged', 'assistant_query_log', null, null, v);
  return v;
end;
$$;

revoke all on function public.get_assistant_usage(integer), public.run_assistant_purge() from public, anon;
grant execute on function public.get_assistant_usage(integer), public.run_assistant_purge() to authenticated;
revoke all on function private.purge_assistant_logs(uuid) from public, anon, authenticated;
