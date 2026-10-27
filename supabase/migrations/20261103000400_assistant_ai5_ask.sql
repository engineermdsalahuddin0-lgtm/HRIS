-- =============================================================================
-- AI assistant AI5: asking (retrieval, limits, conversations, log, preview).
-- Design: docs/Part04Architecture.md (sections 6, 8.4, 9.1, 12).
--
-- The Edge Function embeds the question with the company's key and calls
-- assistant_prepare AS THE USER. Retrieval runs here: only chunks of the
-- current embedding model, of this company, that the caller's role may read
-- (resources: topic ticked + audience; guide articles: kb.app_guide ticked AND
-- the article's permission held). Score = cosine similarity, plus a boost for
-- guide articles of the page the user is on (page-aware), merged with keyword
-- rank. When the best match is only in something the role may not read, the
-- answer is refused without its content: a guide article the role lacks gives
-- "Your role is not permitted for that feature."; a hidden resource gives the
-- role's "not allowed" message.
-- Limits: daily questions per role, monthly token cap, plan (D5).
-- =============================================================================

do $guard$
begin
  if to_regproc('public.register_assistant_resource') is null then
    raise exception 'Apply 20261103000300_assistant_ai4_resources.sql first, then run this file again';
  end if;
end;
$guard$;

create or replace function private.assistant_role_holds_any(p_role_id uuid, p_keys text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select cardinality(p_keys) = 0 or exists (select 1 from unnest(p_keys) k where private.role_has_permission(p_role_id, k))
$$;

-- Ranked candidates for one question. p_visible = true: what the role may read; false: what it may not.
create or replace function private.assistant_search(p_org_id uuid, p_role_id uuid, p_embedding extensions.vector, p_query text,
                                                    p_route text, p_model text, p_limit integer, p_visible boolean)
returns table (chunk_id uuid, source text, resource_id uuid, guide_key text, name text, topic_key text, location text,
               section text, passage text, similarity double precision, score double precision, route text, tour_targets text[])
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_allowed text[] := private.assistant_allowed_topics(p_role_id);
  v_tsq     tsquery := websearch_to_tsquery('simple', coalesce(p_query, ''));
begin
  return query
  with candidates as (
    select c.id, c.source, c.resource_id, c.guide_key, c.location, c.section, c.passage, c.embedding, c.fts,
           coalesce(r.name, g.title) as name, coalesce(r.topic_key, 'kb.app_guide') as topic_key, g.route, g.tour_targets,
           case when c.source = 'resource' then private.assistant_can_read_resource(r, p_role_id, v_allowed)
                else 'kb.app_guide' = any (v_allowed) and private.assistant_role_holds_any(p_role_id, g.needs_any_of) end as readable
    from public.assistant_chunks c
    left join public.assistant_resources r on r.id = c.resource_id
    left join public.assistant_guide_articles g on g.key = c.guide_key
    where c.org_id = p_org_id and c.embedding_model = p_model and c.embedding is not null
      and (c.source = 'guide' or r.status = 'ready')
  ), scoped as (
    select * from candidates where readable = p_visible
  ), semantic as (
    select s.id, 1 - (s.embedding operator(extensions.<=>) p_embedding) as sim,
           row_number() over (order by s.embedding operator(extensions.<=>) p_embedding) as rnk
    from scoped s order by s.embedding operator(extensions.<=>) p_embedding limit 40
  ), keyword as (
    select s.id, row_number() over (order by ts_rank_cd(s.fts, v_tsq) desc) as rnk
    from scoped s where s.fts @@ v_tsq limit 40
  )
  select s.id, s.source, s.resource_id, s.guide_key, s.name, s.topic_key, s.location, s.section, s.passage,
         coalesce(se.sim, 0)::double precision,
         (coalesce(se.sim, 0) + coalesce(1.0 / (60 + kw.rnk), 0) * 6
          + case when s.source = 'guide' and p_route is not null and s.route = p_route then 0.15 else 0 end)::double precision,
         s.route, s.tour_targets
  from scoped s
  left join semantic se on se.id = s.id
  left join keyword kw on kw.id = s.id
  where se.id is not null or kw.id is not null
  order by 11 desc
  limit greatest(p_limit, 1);
end;
$$;

-- Everything the answer step needs, or a refusal. Called by the Edge Function as the user.
-- p_preview_role: assistant.manage previews another role (no limits, no digest, not logged).
create or replace function private.assistant_prepare_core(p_question text, p_embedding text, p_route text,
                                                          p_conversation_id uuid, p_preview_role uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_role    uuid := coalesce(p_preview_role, private.current_role_id());
  s         public.assistant_settings;
  rs        public.assistant_role_settings;
  e         record;
  v_vec     extensions.vector;
  v_k       integer;
  v_min     double precision;
  v_used    integer;
  v_month   bigint;
  v_rows    jsonb;
  v_best    double precision;
  v_hid_sim double precision;
  v_hid_src text;
  v_hist    jsonb := '[]'::jsonb;
  v_routes  jsonb;
begin
  if v_org is null then
    raise exception 'Sign in to a company first' using errcode = '42501';
  end if;
  if char_length(coalesce(btrim(p_question), '')) not between 2 and 2000 then
    raise exception 'Ask a question of 2 to 2000 characters' using errcode = '22023';
  end if;
  select * into s from public.assistant_settings where org_id = v_org;
  select * into rs from public.assistant_role_settings where role_id = v_role;
  select * into e from private.assistant_embed_source(v_org);
  if not coalesce(s.enabled, false) or not coalesce(rs.enabled, false) then
    return jsonb_build_object('refusal', 'The assistant is switched off for your role.');
  end if;
  if p_preview_role is null then
    if not private.assistant_plan_allows_ask(v_org) then
      return jsonb_build_object('refusal', 'Asking questions needs the Professional or Enterprise plan.');
    end if;
    v_used := private.assistant_questions_today(auth.uid(), v_org);
    if rs.daily_limit is not null and v_used >= rs.daily_limit then
      return jsonb_build_object('refusal', 'You reached today''s limit of ' || rs.daily_limit || ' questions. Try again tomorrow.');
    end if;
    v_month := coalesce((select sum(tokens_in + tokens_out) from public.assistant_query_log
                         where org_id = v_org and asked_at >= date_trunc('month', now())), 0);
    if s.monthly_token_cap is not null and v_month >= s.monthly_token_cap then
      return jsonb_build_object('refusal', 'The company''s monthly AI limit is reached.');
    end if;
  end if;
  if e.model is null then
    return jsonb_build_object('refusal', 'The company has not connected an embedding key yet.');
  end if;

  v_vec := p_embedding::extensions.vector;
  v_k := coalesce((s.hyper ->> 'top_k')::integer, 6);
  v_min := coalesce((s.hyper ->> 'min_score')::numeric, 0.3);
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);

  select coalesce(jsonb_agg(jsonb_build_object('n', n, 'chunk_id', chunk_id, 'source', source, 'resource_id', resource_id,
                                               'guide_key', guide_key, 'name', name, 'topic_key', topic_key, 'location', location,
                                               'section', section, 'passage', passage, 'similarity', round(similarity::numeric, 3),
                                               'route', route, 'tour_targets', to_jsonb(tour_targets)) order by n), '[]'::jsonb),
         max(similarity)
    into v_rows, v_best
  from (select x.*, row_number() over (order by x.score desc) as n
        from private.assistant_search(v_org, v_role, v_vec, p_question, p_route, e.model, v_k, true) x
        where x.similarity >= v_min) t;

  -- Something better only in what the role may not read? Say so, never show it.
  select h.similarity, h.source into v_hid_sim, v_hid_src
  from private.assistant_search(v_org, v_role, v_vec, p_question, null, e.model, 1, false) h
  where h.similarity >= greatest(v_min, 0.5) limit 1;

  if p_preview_role is null and p_conversation_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('sender', m.sender, 'content', left(m.content, 1500)) order by m.created_at), '[]'::jsonb)
      into v_hist
    from (select m.* from public.assistant_messages m
          join public.assistant_conversations c on c.id = m.conversation_id
          where m.conversation_id = p_conversation_id and c.user_id = auth.uid()
          order by m.created_at desc limit 8) m;
  end if;

  -- Pages the caller may open (for links in the answer).
  select coalesce(jsonb_agg(jsonb_build_object('route', g.route, 'title', g.title) order by g.sort), '[]'::jsonb) into v_routes
  from public.assistant_guide_articles g where private.assistant_role_holds_any(v_role, g.needs_any_of);

  return jsonb_build_object(
    'passages', v_rows,
    'hidden', case when v_hid_sim is null or (v_best is not null and v_best >= v_hid_sim) then 'none'
                   when v_hid_src = 'guide' then 'feature' else 'resource' end,
    'digest', case when p_preview_role is null then private.assistant_digest() else '[]'::jsonb end,
    'history', v_hist,
    'routes', v_routes,
    'language_mode', s.language_mode, 'hyper', s.hyper, 'company', (select o.name from public.organizations o where o.id = v_org),
    'not_allowed', rs.not_allowed_message, 'assistant_name', s.name, 'embedding_model', e.model);
end;
$$;

create or replace function public.assistant_prepare(p_question text, p_embedding text, p_route text default null, p_conversation_id uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.assistant_prepare_core(p_question, p_embedding, p_route, p_conversation_id, null)
$$;

create or replace function public.assistant_preview_as_role(p_role_id uuid, p_question text, p_embedding text, p_route text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('assistant.manage');
  if not exists (select 1 from public.roles where id = p_role_id and org_id = private.current_org_id()) then
    raise exception 'Role not found' using errcode = 'P0002';
  end if;
  return private.assistant_prepare_core(p_question, p_embedding, p_route, null, p_role_id);
end;
$$;

-- p: {conversation_id, question, answer, kind, citations, route, chunk_ids, topics, tokens_in, tokens_out}
create or replace function public.assistant_record_answer(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_conv uuid := nullif(p ->> 'conversation_id', '')::uuid;
  v_kind text := coalesce(p ->> 'kind', 'answer');
  v_log  bigint;
begin
  if v_org is null then
    raise exception 'Sign in to a company first' using errcode = '42501';
  end if;
  if v_kind not in ('answer', 'dont_know', 'not_allowed', 'personal_data', 'updates', 'refused') then
    raise exception 'Unknown answer kind' using errcode = '22023';
  end if;
  if v_conv is null or not exists (select 1 from public.assistant_conversations where id = v_conv and user_id = auth.uid()) then
    insert into public.assistant_conversations (org_id, user_id) values (v_org, auth.uid()) returning id into v_conv;
  end if;
  update public.assistant_conversations set last_at = now() where id = v_conv;
  insert into public.assistant_messages (org_id, conversation_id, sender, content, route)
  values (v_org, v_conv, 'user', left(coalesce(p ->> 'question', ''), 4000), left(p ->> 'route', 200));
  insert into public.assistant_messages (org_id, conversation_id, sender, content, kind, citations, route)
  values (v_org, v_conv, 'ai', left(coalesce(p ->> 'answer', ''), 20000), v_kind, coalesce(p -> 'citations', '[]'::jsonb), left(p ->> 'route', 200));
  insert into public.assistant_query_log (org_id, user_id, role_id, question, route, kind, topics_used, chunk_ids, tokens_in, tokens_out)
  values (v_org, auth.uid(), private.current_role_id(), left(coalesce(p ->> 'question', ''), 4000), left(p ->> 'route', 200), v_kind,
          coalesce(array(select jsonb_array_elements_text(coalesce(p -> 'topics', '[]'::jsonb))), '{}'),
          coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(p -> 'chunk_ids', '[]'::jsonb)) x), '{}'),
          greatest(coalesce((p ->> 'tokens_in')::integer, 0), 0), greatest(coalesce((p ->> 'tokens_out')::integer, 0), 0))
  returning id into v_log;
  return jsonb_build_object('conversation_id', v_conv, 'log_id', v_log,
                            'left', (select case when rs.daily_limit is null then null
                                                 else greatest(rs.daily_limit - private.assistant_questions_today(auth.uid(), v_org), 0) end
                                     from public.assistant_role_settings rs where rs.role_id = private.current_role_id()));
end;
$$;

create or replace function public.assistant_feedback(p_log_id bigint, p_helpful boolean)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.assistant_query_log set helpful = p_helpful where id = p_log_id and user_id = auth.uid()
$$;

-- My latest conversation (D6: own only, 90 days), oldest message first.
create or replace function public.assistant_history()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('conversation_id', c.id, 'messages', coalesce((
    select jsonb_agg(jsonb_build_object('sender', m.sender, 'content', m.content, 'kind', m.kind, 'citations', m.citations,
                                        'created_at', m.created_at) order by m.created_at)
    from (select * from public.assistant_messages m where m.conversation_id = c.id order by m.created_at desc limit 40) m), '[]'::jsonb))
  from public.assistant_conversations c
  where c.user_id = auth.uid() and c.org_id = private.current_org_id() and c.last_at > now() - interval '90 days'
  order by c.last_at desc limit 1
$$;

-- A signed URL is only issued by storage when the policy allows it; this gives the path for a cited resource.
create or replace function public.assistant_resource_path(p_resource_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select private.assistant_resource_path(r) from public.assistant_resources r
  where r.id = p_resource_id and r.org_id = private.current_org_id()
    and (private.has_permission('assistant.manage')
         or private.assistant_can_read_resource(r, private.current_role_id(), private.assistant_allowed_topics(private.current_role_id())))
$$;

revoke all on function
  public.assistant_prepare(text, text, text, uuid), public.assistant_preview_as_role(uuid, text, text, text),
  public.assistant_record_answer(jsonb), public.assistant_feedback(bigint, boolean), public.assistant_history(),
  public.assistant_resource_path(uuid)
from public, anon;
grant execute on function
  public.assistant_prepare(text, text, text, uuid), public.assistant_preview_as_role(uuid, text, text, text),
  public.assistant_record_answer(jsonb), public.assistant_feedback(bigint, boolean), public.assistant_history(),
  public.assistant_resource_path(uuid)
to authenticated;
revoke all on function
  private.assistant_role_holds_any(uuid, text[]),
  private.assistant_search(uuid, uuid, extensions.vector, text, text, text, integer, boolean),
  private.assistant_prepare_core(text, text, text, uuid, uuid)
from public, anon, authenticated;
