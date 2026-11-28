-- Noventra Phase 1 — Controlled clause ingestion RPC
-- Requires phase1/sql/002_noventra_foundation_schema.sql.

begin;

create or replace function public.ingest_regulatory_document_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_source_org text;
  v_source_url text;
  v_document_type text;
  v_version_label text;
  v_checksum text;
  v_effective_date date;
  v_publication_date date;
  v_document_id uuid;
  v_version_id uuid;
  v_clause_count integer;
  v_review_count integer;
  v_existing_id uuid;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object';
  end if;

  v_title := nullif(btrim(p_payload->>'title'), '');
  v_source_org := coalesce(nullif(btrim(p_payload->>'source_org'), ''), 'Bank Negara Malaysia');
  v_source_url := nullif(btrim(p_payload->>'source_url'), '');
  v_document_type := coalesce(nullif(btrim(p_payload->>'document_type'), ''), 'policy_document');
  v_version_label := coalesce(nullif(btrim(p_payload->>'version_label'), ''), 'Current version');
  v_checksum := lower(nullif(btrim(p_payload->>'checksum_sha256'), ''));

  if v_title is null then
    raise exception 'title is required';
  end if;

  if v_checksum is null or v_checksum !~ '^[0-9a-f]{64}$' then
    raise exception 'checksum_sha256 must be a 64-character hexadecimal SHA-256 value';
  end if;

  if jsonb_typeof(p_payload->'clauses') <> 'array'
     or jsonb_array_length(p_payload->'clauses') = 0 then
    raise exception 'clauses must be a non-empty JSON array';
  end if;

  if nullif(p_payload->>'effective_date', '') is not null then
    v_effective_date := (p_payload->>'effective_date')::date;
  end if;

  if nullif(p_payload->>'publication_date', '') is not null then
    v_publication_date := (p_payload->>'publication_date')::date;
  end if;

  select id
    into v_existing_id
  from public.regulatory_documents
  where checksum_sha256 = v_checksum
  limit 1;

  if v_existing_id is not null then
    select count(*)::integer
      into v_clause_count
    from public.regulatory_clauses
    where document_id = v_existing_id;

    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'document_id', v_existing_id,
      'clauses_stored', v_clause_count,
      'review_required', 0
    );
  end if;

  insert into public.regulatory_documents (
    title,
    source_org,
    source_type,
    source_url,
    version_label,
    effective_date,
    publication_date,
    document_type,
    document_code,
    jurisdiction,
    status,
    applicability_status,
    ingestion_status,
    file_name,
    storage_path,
    checksum_sha256,
    ingested_at,
    metadata
  ) values (
    v_title,
    v_source_org,
    v_document_type,
    v_source_url,
    v_version_label,
    v_effective_date,
    v_publication_date,
    v_document_type,
    nullif(btrim(p_payload->>'document_code'), ''),
    coalesce(nullif(btrim(p_payload->>'jurisdiction'), ''), 'Malaysia'),
    'active',
    'pending_review',
    'review_required',
    nullif(btrim(p_payload->>'file_name'), ''),
    nullif(btrim(p_payload->>'storage_path'), ''),
    v_checksum,
    now(),
    jsonb_build_object(
      'ingest_request_id', p_payload->>'request_id',
      'extraction_model', p_payload->>'extraction_model',
      'source_traceability', true
    )
  )
  returning id into v_document_id;

  insert into public.regulatory_document_versions (
    document_id,
    version_label,
    publication_date,
    effective_date,
    source_url,
    file_name,
    storage_path,
    checksum_sha256,
    is_current,
    extraction_status,
    extraction_metadata
  ) values (
    v_document_id,
    v_version_label,
    v_publication_date,
    v_effective_date,
    v_source_url,
    nullif(btrim(p_payload->>'file_name'), ''),
    nullif(btrim(p_payload->>'storage_path'), ''),
    v_checksum,
    true,
    'review_required',
    jsonb_build_object(
      'request_id', p_payload->>'request_id',
      'model', p_payload->>'extraction_model',
      'clause_count_received', jsonb_array_length(p_payload->'clauses')
    )
  )
  returning id into v_version_id;

  insert into public.regulatory_clauses (
    document_id,
    document_version_id,
    clause_number,
    clause_title,
    section_title,
    page_start,
    page_end,
    classification,
    requirement_text,
    guidance_text,
    applicability_status,
    extraction_confidence,
    review_status,
    metadata
  )
  select
    v_document_id,
    v_version_id,
    coalesce(nullif(btrim(c.item->>'clause_number'), ''), 'UNNUMBERED-' || c.ordinality::text),
    nullif(btrim(c.item->>'clause_title'), ''),
    nullif(btrim(c.item->>'section_title'), ''),
    case when (c.item->>'page_start') ~ '^[0-9]+$' then (c.item->>'page_start')::integer end,
    case when (c.item->>'page_end') ~ '^[0-9]+$' then (c.item->>'page_end')::integer end,
    case
      when upper(c.item->>'classification') in ('S','G') then upper(c.item->>'classification')
      else 'unclassified'
    end,
    nullif(btrim(c.item->>'requirement_text'), ''),
    nullif(btrim(c.item->>'guidance_text'), ''),
    'pending_review',
    case
      when (c.item->>'confidence') ~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
        then (c.item->>'confidence')::numeric(5,4)
      else null
    end,
    case
      when upper(c.item->>'classification') not in ('S','G')
        or not ((c.item->>'confidence') ~ '^(0(\.[0-9]+)?|1(\.0+)?)$')
        or (c.item->>'confidence')::numeric < 0.85
        then 'review_required'
      else 'ai_extracted'
    end,
    jsonb_build_object(
      'source_quote', c.item->>'source_quote',
      'extraction_notes', c.item->>'extraction_notes'
    )
  from jsonb_array_elements(p_payload->'clauses') with ordinality as c(item, ordinality)
  where nullif(btrim(c.item->>'requirement_text'), '') is not null;

  get diagnostics v_clause_count = row_count;

  if v_clause_count = 0 then
    raise exception 'no clauses contained a non-empty requirement_text';
  end if;

  select count(*)::integer
    into v_review_count
  from public.regulatory_clauses
  where document_id = v_document_id
    and review_status = 'review_required';

  insert into public.audit_events (
    actor_type,
    action,
    entity_type,
    entity_id,
    module_key,
    request_id,
    after_state,
    metadata
  ) values (
    'workflow',
    'regulatory_document_ingested',
    'regulatory_document',
    v_document_id::text,
    'regulatory_intelligence',
    p_payload->>'request_id',
    jsonb_build_object(
      'document_id', v_document_id,
      'version_id', v_version_id,
      'clauses_stored', v_clause_count,
      'review_required', v_review_count
    ),
    jsonb_build_object('source', 'ingest_regulatory_document_v1')
  );

  return jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'document_id', v_document_id,
    'version_id', v_version_id,
    'title', v_title,
    'version_label', v_version_label,
    'clauses_stored', v_clause_count,
    'review_required', v_review_count,
    'ingestion_status', 'review_required'
  );
end;
$$;

revoke all on function public.ingest_regulatory_document_v1(jsonb)
  from public, anon, authenticated;

grant execute on function public.ingest_regulatory_document_v1(jsonb)
  to service_role;

comment on function public.ingest_regulatory_document_v1(jsonb) is
  'Noventra controlled server-side ingestion for versioned clause-level regulatory requirements.';

commit;
