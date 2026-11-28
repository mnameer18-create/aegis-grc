-- Noventra Phase 3 — Regulatory Requirements Library query API
-- Additive and idempotent.
-- Requires Phase 1/2 foundation migrations.

begin;

create or replace function public.list_regulatory_requirements_v1(
  p_search text default null,
  p_document_id uuid default null,
  p_classification text default null,
  p_applicability_status text default null,
  p_review_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  document_id uuid,
  document_title text,
  document_code text,
  source_org text,
  version_label text,
  effective_date date,
  clause_id uuid,
  clause_number text,
  clause_title text,
  section_title text,
  page_start integer,
  page_end integer,
  classification text,
  requirement_text text,
  guidance_text text,
  applicability_status text,
  applicability_rationale text,
  review_status text,
  extraction_confidence numeric,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with filtered as (
    select
      r.document_id,
      r.document_title,
      r.document_code,
      r.source_org,
      r.version_label,
      r.effective_date,
      r.clause_id,
      r.clause_number,
      r.clause_title,
      r.section_title,
      r.page_start,
      r.page_end,
      r.classification,
      r.requirement_text,
      r.guidance_text,
      r.applicability_status,
      r.applicability_rationale,
      r.review_status,
      r.extraction_confidence
    from public.regulatory_requirements_library r
    where
      (p_document_id is null or r.document_id = p_document_id)
      and (
        p_classification is null
        or btrim(p_classification) = ''
        or r.classification = upper(btrim(p_classification))
      )
      and (
        p_applicability_status is null
        or btrim(p_applicability_status) = ''
        or r.applicability_status = btrim(p_applicability_status)
      )
      and (
        p_review_status is null
        or btrim(p_review_status) = ''
        or r.review_status = btrim(p_review_status)
      )
      and (
        p_search is null
        or btrim(p_search) = ''
        or r.document_title ilike '%' || btrim(p_search) || '%'
        or coalesce(r.document_code,'') ilike '%' || btrim(p_search) || '%'
        or r.clause_number ilike '%' || btrim(p_search) || '%'
        or coalesce(r.clause_title,'') ilike '%' || btrim(p_search) || '%'
        or coalesce(r.section_title,'') ilike '%' || btrim(p_search) || '%'
        or r.requirement_text ilike '%' || btrim(p_search) || '%'
      )
  )
  select
    f.document_id,
    f.document_title,
    f.document_code,
    f.source_org,
    f.version_label,
    f.effective_date,
    f.clause_id,
    f.clause_number,
    f.clause_title,
    f.section_title,
    f.page_start,
    f.page_end,
    f.classification,
    f.requirement_text,
    f.guidance_text,
    f.applicability_status,
    f.applicability_rationale,
    f.review_status,
    f.extraction_confidence,
    count(*) over() as total_count
  from filtered f
  order by
    f.document_title,
    case
      when f.clause_number ~ '^[0-9]+(\\.[0-9]+)*$' then string_to_array(f.clause_number,'.')::int[]
      else null
    end nulls last,
    f.clause_number,
    f.clause_id
  limit greatest(1, least(coalesce(p_limit,50),200))
  offset greatest(coalesce(p_offset,0),0);
$$;

revoke all on function public.list_regulatory_requirements_v1(
  text, uuid, text, text, text, integer, integer
) from public, anon, authenticated;

grant execute on function public.list_regulatory_requirements_v1(
  text, uuid, text, text, text, integer, integer
) to service_role;

comment on function public.list_regulatory_requirements_v1(
  text, uuid, text, text, text, integer, integer
) is
  'Server-side Noventra Requirements Library query with search, filters and pagination.';

commit;
