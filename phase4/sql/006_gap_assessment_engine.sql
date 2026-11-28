-- Noventra Phase 4: AI Gap Assessment Engine
-- Additive migration. Preserves all Phase 1-3 objects.

create or replace function public.ingest_internal_document_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_id uuid;
  v_document_id uuid;
  v_title text;
  v_document_code text;
  v_document_type text;
  v_checksum text;
  v_sections jsonb;
  v_section_count integer := 0;
  v_request_id text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object';
  end if;

  v_request_id := nullif(btrim(p_payload->>'request_id'), '');

  if nullif(p_payload->>'internal_document_id', '') is not null then
    v_document_id := (p_payload->>'internal_document_id')::uuid;
    select id into v_existing_id from public.internal_documents where id = v_document_id;
    if v_existing_id is null then raise exception 'selected internal document does not exist'; end if;
    select count(*)::integer into v_section_count
      from public.internal_document_sections where internal_document_id = v_document_id;
    return jsonb_build_object('ok', true, 'selected', true, 'duplicate', false,
      'internal_document_id', v_document_id, 'sections_stored', v_section_count);
  end if;

  v_title := nullif(btrim(p_payload->>'title'), '');
  v_document_code := nullif(btrim(p_payload->>'document_code'), '');
  v_document_type := lower(coalesce(nullif(btrim(p_payload->>'document_type'), ''), 'policy'));
  if v_title is null then raise exception 'internal document title is required'; end if;
  if v_document_type not in ('policy','sop','osopm','process') then
    raise exception 'document_type must be policy, sop, osopm, or process';
  end if;

  v_sections := p_payload->'sections';
  if jsonb_typeof(v_sections) <> 'array' or jsonb_array_length(v_sections) = 0 then
    if nullif(btrim(p_payload->>'content'), '') is null then
      raise exception 'content or a non-empty sections array is required';
    end if;
    v_sections := jsonb_build_array(jsonb_build_object(
      'section_number','FULL','section_title','Complete document',
      'page_start',1,'page_end',1,'content',p_payload->>'content',
      'extraction_confidence',1,'review_status','confirmed'
    ));
  end if;

  v_checksum := lower(nullif(btrim(p_payload->>'checksum_sha256'), ''));
  if v_checksum is null then
    v_checksum := encode(digest(v_title || '|' || coalesce(v_document_code,'') || '|' || v_sections::text, 'sha256'), 'hex');
  end if;

  select id into v_existing_id
    from public.internal_documents
   where checksum_sha256 = v_checksum
   limit 1;

  if v_existing_id is not null then
    select count(*)::integer into v_section_count
      from public.internal_document_sections where internal_document_id = v_existing_id;
    return jsonb_build_object('ok', true, 'selected', false, 'duplicate', true,
      'internal_document_id', v_existing_id, 'sections_stored', v_section_count);
  end if;

  insert into public.internal_documents (
    title, document_code, document_type, owner_business_unit, version_label,
    approval_date, effective_date, review_date, status, file_name, storage_path,
    checksum_sha256, ingestion_status, metadata
  ) values (
    v_title, v_document_code, v_document_type,
    nullif(btrim(p_payload->>'owner_business_unit'), ''),
    nullif(btrim(p_payload->>'version_label'), ''),
    nullif(p_payload->>'approval_date','')::date,
    nullif(p_payload->>'effective_date','')::date,
    nullif(p_payload->>'review_date','')::date,
    coalesce(nullif(btrim(p_payload->>'status'), ''), 'active'),
    nullif(btrim(p_payload->>'file_name'), ''),
    nullif(btrim(p_payload->>'storage_path'), ''),
    v_checksum, 'complete',
    coalesce(p_payload->'metadata','{}'::jsonb) || jsonb_build_object('request_id',v_request_id)
  ) returning id into v_document_id;

  insert into public.internal_document_sections (
    internal_document_id, section_number, section_title, page_start, page_end,
    content, extraction_confidence, review_status, metadata
  )
  select v_document_id,
    nullif(btrim(s.item->>'section_number'),''),
    nullif(btrim(s.item->>'section_title'),''),
    case when s.item->>'page_start' ~ '^[0-9]+$' then (s.item->>'page_start')::integer end,
    case when s.item->>'page_end' ~ '^[0-9]+$' then (s.item->>'page_end')::integer end,
    nullif(btrim(s.item->>'content'),''),
    case when coalesce(s.item->>'extraction_confidence',s.item->>'confidence') ~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
      then coalesce(s.item->>'extraction_confidence',s.item->>'confidence')::numeric(5,4) else null end,
    case when lower(coalesce(s.item->>'review_status','')) in ('ai_extracted','review_required','confirmed')
      then lower(s.item->>'review_status') else 'review_required' end,
    coalesce(s.item->'metadata','{}'::jsonb)
  from jsonb_array_elements(v_sections) with ordinality as s(item, ordinality)
  where nullif(btrim(s.item->>'content'),'') is not null;

  get diagnostics v_section_count = row_count;
  if v_section_count = 0 then raise exception 'no internal sections contained content'; end if;

  insert into public.audit_events (
    actor_type, action, entity_type, entity_id, module_key, request_id, after_state, metadata
  ) values (
    'workflow','internal_document_ingested','internal_document',v_document_id::text,
    'compliance_gap_assessment',v_request_id,
    jsonb_build_object('title',v_title,'document_type',v_document_type,'sections_stored',v_section_count),
    jsonb_build_object('source','ingest_internal_document_v1')
  );

  return jsonb_build_object('ok', true, 'selected', false, 'duplicate', false,
    'internal_document_id', v_document_id, 'sections_stored', v_section_count,
    'title', v_title, 'document_type', v_document_type);
end;
$$;

create or replace function public.prepare_gap_assessment_context_v1(
  p_regulatory_document_code text,
  p_internal_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regulatory_document_id uuid;
  v_version_id uuid;
  v_internal_title text;
  v_clauses jsonb;
  v_sections jsonb;
begin
  select d.id, v.id into v_regulatory_document_id, v_version_id
    from public.regulatory_documents d
    left join public.regulatory_document_versions v on v.document_id=d.id and v.is_current=true
   where d.document_code=p_regulatory_document_code
   order by v.created_at desc nulls last
   limit 1;
  if v_regulatory_document_id is null then raise exception 'regulatory document code not found'; end if;

  select title into v_internal_title from public.internal_documents where id=p_internal_document_id;
  if v_internal_title is null then raise exception 'internal document not found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'regulatory_clause_id',c.id,'clause_number',c.clause_number,'clause_title',c.clause_title,
    'classification',c.classification,'requirement_text',c.requirement_text,
    'guidance_text',c.guidance_text,'page_start',c.page_start,'page_end',c.page_end,
    'review_status',c.review_status
  ) order by c.clause_number),'[]'::jsonb) into v_clauses
  from public.regulatory_clauses c
  where c.document_id=v_regulatory_document_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'internal_document_section_id',s.id,'section_number',s.section_number,
    'section_title',s.section_title,'content',s.content,
    'page_start',s.page_start,'page_end',s.page_end,'review_status',s.review_status
  ) order by s.section_number),'[]'::jsonb) into v_sections
  from public.internal_document_sections s
  where s.internal_document_id=p_internal_document_id;

  if jsonb_array_length(v_clauses)=0 then raise exception 'regulatory document has no clauses'; end if;
  if jsonb_array_length(v_sections)=0 then raise exception 'internal document has no sections'; end if;

  return jsonb_build_object(
    'ok',true,'regulatory_document_id',v_regulatory_document_id,
    'regulatory_document_version_id',v_version_id,
    'regulatory_document_code',p_regulatory_document_code,
    'internal_document_id',p_internal_document_id,'internal_document_title',v_internal_title,
    'clauses',v_clauses,'internal_sections',v_sections
  );
end;
$$;

create or replace function public.create_gap_assessment_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assessment_id uuid;
  v_regulatory_document_id uuid;
  v_version_id uuid;
  v_internal_document_id uuid;
  v_findings jsonb;
  v_count integer := 0;
  v_request_id text;
  v_overall text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object';
  end if;
  v_regulatory_document_id := (p_payload->>'regulatory_document_id')::uuid;
  v_version_id := nullif(p_payload->>'regulatory_document_version_id','')::uuid;
  v_internal_document_id := (p_payload->>'internal_document_id')::uuid;
  v_request_id := nullif(btrim(p_payload->>'request_id'),'');
  v_findings := p_payload->'findings';
  v_overall := lower(coalesce(nullif(p_payload->>'overall_outcome',''),'not_assessed'));

  if v_overall not in ('not_assessed','compliant','partially_compliant','non_compliant','not_applicable') then
    v_overall := 'not_assessed';
  end if;
  if jsonb_typeof(v_findings) <> 'array' or jsonb_array_length(v_findings)=0 then
    raise exception 'findings must be a non-empty array';
  end if;

  insert into public.gap_assessments (
    title, regulatory_document_id, regulatory_document_version_id, scope,
    business_unit, status, overall_outcome, started_at, submitted_at, summary, metadata
  ) values (
    coalesce(nullif(btrim(p_payload->>'title'),''),'AI Gap Assessment'),
    v_regulatory_document_id, v_version_id, nullif(btrim(p_payload->>'scope'),''),
    nullif(btrim(p_payload->>'business_unit'),''),'pending_review',v_overall,
    now(),now(),nullif(btrim(p_payload->>'summary'),''),
    coalesce(p_payload->'metadata','{}'::jsonb) || jsonb_build_object(
      'request_id',v_request_id,'ai_model',p_payload->>'ai_model','human_confirmation_required',true
    )
  ) returning id into v_assessment_id;

  insert into public.gap_assessment_sources(assessment_id,internal_document_id)
  values(v_assessment_id,v_internal_document_id);

  insert into public.gap_assessment_findings (
    assessment_id, regulatory_clause_id, internal_document_section_id, outcome,
    finding_summary, gap_description, existing_control, assessor_rationale,
    ai_analysis, ai_confidence, status
  )
  select v_assessment_id,
    (f.item->>'regulatory_clause_id')::uuid,
    nullif(f.item->>'internal_document_section_id','')::uuid,
    case when lower(f.item->>'outcome') in ('compliant','partially_compliant','non_compliant','not_applicable')
      then lower(f.item->>'outcome') else 'not_assessed' end,
    nullif(btrim(f.item->>'finding_summary'),''),
    nullif(btrim(f.item->>'gap_description'),''),
    nullif(btrim(f.item->>'existing_control'),''),
    nullif(btrim(f.item->>'rationale'),''),
    nullif(btrim(f.item->>'evidence_quote'),''),
    case when coalesce(f.item->>'confidence',f.item->>'ai_confidence') ~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
      then coalesce(f.item->>'confidence',f.item->>'ai_confidence')::numeric(5,4) else null end,
    'pending_review'
  from jsonb_array_elements(v_findings) with ordinality as f(item, ordinality)
  where nullif(f.item->>'regulatory_clause_id','') is not null;

  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'no valid findings were supplied'; end if;

  insert into public.audit_events (
    actor_type, action, entity_type, entity_id, module_key, request_id, after_state, metadata
  ) values (
    'workflow','gap_assessment_created','gap_assessment',v_assessment_id::text,
    'compliance_gap_assessment',v_request_id,
    jsonb_build_object('assessment_id',v_assessment_id,'overall_outcome',v_overall,'findings_stored',v_count),
    jsonb_build_object('source','create_gap_assessment_v1')
  );

  return jsonb_build_object(
    'ok',true,'assessment_id',v_assessment_id,'status','pending_review',
    'overall_outcome',v_overall,'findings_stored',v_count,
    'human_confirmation_required',true
  );
end;
$$;

create or replace function public.review_gap_assessment_finding_v1(
  p_finding_id uuid,
  p_outcome text,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assessment_id uuid;
  v_remaining integer;
  v_overall text;
begin
  p_outcome := lower(p_outcome);
  if p_outcome not in ('compliant','partially_compliant','non_compliant','not_applicable') then
    raise exception 'invalid reviewer outcome';
  end if;

  update public.gap_assessment_findings
     set outcome=p_outcome, reviewer_comment=nullif(btrim(p_comment),''),
         reviewed_by=auth.uid(), reviewed_at=now(), status='confirmed', updated_at=now()
   where id=p_finding_id
   returning assessment_id into v_assessment_id;
  if v_assessment_id is null then raise exception 'finding not found'; end if;

  select count(*)::integer into v_remaining
    from public.gap_assessment_findings
   where assessment_id=v_assessment_id and status<>'confirmed';

  select case
    when count(*) filter(where outcome='non_compliant')>0 then 'non_compliant'
    when count(*) filter(where outcome='partially_compliant')>0 then 'partially_compliant'
    when count(*) filter(where outcome='compliant')>0 then 'compliant'
    when count(*) filter(where outcome='not_applicable')=count(*) then 'not_applicable'
    else 'not_assessed' end
    into v_overall
  from public.gap_assessment_findings where assessment_id=v_assessment_id;

  update public.gap_assessments
     set overall_outcome=v_overall,
         status=case when v_remaining=0 then 'approved' else 'pending_review' end,
         approved_at=case when v_remaining=0 then now() else approved_at end,
         approved_by=case when v_remaining=0 then auth.uid() else approved_by end,
         updated_at=now()
   where id=v_assessment_id;

  insert into public.audit_events (
    actor_type, action, entity_type, entity_id, module_key, after_state, metadata
  ) values (
    'reviewer','gap_finding_confirmed','gap_assessment_finding',p_finding_id::text,
    'compliance_gap_assessment',
    jsonb_build_object('outcome',p_outcome,'assessment_id',v_assessment_id,'remaining',v_remaining),
    jsonb_build_object('source','review_gap_assessment_finding_v1')
  );

  return jsonb_build_object('ok',true,'finding_id',p_finding_id,
    'assessment_id',v_assessment_id,'outcome',p_outcome,
    'assessment_status',case when v_remaining=0 then 'approved' else 'pending_review' end,
    'remaining_reviews',v_remaining,'overall_outcome',v_overall);
end;
$$;

create or replace view public.gap_assessment_summary_v1 as
select
  a.id as assessment_id, a.title, a.status, a.overall_outcome, a.business_unit,
  a.summary, a.created_at, a.submitted_at, a.approved_at,
  d.title as regulatory_document_title, d.document_code,
  count(f.id)::integer as total_findings,
  count(f.id) filter(where f.outcome='compliant')::integer as compliant_count,
  count(f.id) filter(where f.outcome='partially_compliant')::integer as partially_compliant_count,
  count(f.id) filter(where f.outcome='non_compliant')::integer as non_compliant_count,
  count(f.id) filter(where f.outcome='not_applicable')::integer as not_applicable_count,
  count(f.id) filter(where f.status<>'confirmed')::integer as pending_review_count
from public.gap_assessments a
join public.regulatory_documents d on d.id=a.regulatory_document_id
left join public.gap_assessment_findings f on f.assessment_id=a.id
group by a.id,d.id;

create or replace function public.list_gap_assessment_findings_v1(p_assessment_id uuid)
returns table (
  finding_id uuid, clause_number text, classification text, requirement_text text,
  outcome text, finding_summary text, gap_description text, existing_control text,
  evidence_quote text, rationale text, ai_confidence numeric, finding_status text,
  reviewer_comment text, reviewed_at timestamptz, internal_section_number text,
  internal_section_title text, internal_section_content text
)
language sql
security definer
set search_path=public
as $$
  select f.id,c.clause_number,c.classification,c.requirement_text,
    f.outcome,f.finding_summary,f.gap_description,f.existing_control,
    f.ai_analysis,f.assessor_rationale,f.ai_confidence,f.status,
    f.reviewer_comment,f.reviewed_at,s.section_number,s.section_title,s.content
  from public.gap_assessment_findings f
  join public.regulatory_clauses c on c.id=f.regulatory_clause_id
  left join public.internal_document_sections s on s.id=f.internal_document_section_id
  where f.assessment_id=p_assessment_id
  order by c.clause_number;
$$;

revoke all on function public.ingest_internal_document_v1(jsonb) from public, anon, authenticated;
revoke all on function public.prepare_gap_assessment_context_v1(text,uuid) from public, anon, authenticated;
revoke all on function public.create_gap_assessment_v1(jsonb) from public, anon, authenticated;
revoke all on function public.review_gap_assessment_finding_v1(uuid,text,text) from public, anon, authenticated;
revoke all on function public.list_gap_assessment_findings_v1(uuid) from public, anon, authenticated;
grant execute on function public.ingest_internal_document_v1(jsonb) to service_role;
grant execute on function public.prepare_gap_assessment_context_v1(text,uuid) to service_role;
grant execute on function public.create_gap_assessment_v1(jsonb) to service_role;
grant execute on function public.review_gap_assessment_finding_v1(uuid,text,text) to service_role;
grant execute on function public.list_gap_assessment_findings_v1(uuid) to service_role;
revoke all on public.gap_assessment_summary_v1 from public, anon, authenticated;
grant select on public.gap_assessment_summary_v1 to service_role;
