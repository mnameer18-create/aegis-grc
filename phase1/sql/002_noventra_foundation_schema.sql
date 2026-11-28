-- Noventra Phase 1 — Foundation schema
-- Additive migration. Preserves the working Phase 2/3 RAG tables and workflows.
-- Run after phase3/sql/001_rag_schema.sql in the Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

-- Preserve the existing regulatory_documents table while adding Phase 1 fields.
alter table public.regulatory_documents
  add column if not exists document_code text,
  add column if not exists document_type text not null default 'policy_document',
  add column if not exists publication_date date,
  add column if not exists supersedes_document_id uuid references public.regulatory_documents(id),
  add column if not exists applicability_status text not null default 'pending_review',
  add column if not exists ingestion_status text not null default 'registered',
  add column if not exists file_name text,
  add column if not exists storage_path text,
  add column if not exists checksum_sha256 text,
  add column if not exists ingested_at timestamptz,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'regulatory_documents_applicability_status_check'
  ) then
    alter table public.regulatory_documents
      add constraint regulatory_documents_applicability_status_check
      check (applicability_status in ('pending_review','applicable','partially_applicable','not_applicable'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'regulatory_documents_ingestion_status_check'
  ) then
    alter table public.regulatory_documents
      add constraint regulatory_documents_ingestion_status_check
      check (ingestion_status in ('registered','extracting','extracted','review_required','approved','failed'));
  end if;
end
$$;

create unique index if not exists regulatory_documents_checksum_uq
  on public.regulatory_documents(checksum_sha256)
  where checksum_sha256 is not null;

create index if not exists regulatory_documents_library_idx
  on public.regulatory_documents(status, applicability_status, effective_date desc);

create table if not exists public.regulatory_document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.regulatory_documents(id) on delete cascade,
  version_label text not null,
  publication_date date,
  effective_date date,
  source_url text,
  file_name text,
  storage_path text,
  checksum_sha256 text,
  is_current boolean not null default true,
  extraction_status text not null default 'registered',
  extraction_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique(document_id, version_label)
);

create table if not exists public.regulatory_clauses (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.regulatory_documents(id) on delete cascade,
  document_version_id uuid references public.regulatory_document_versions(id) on delete cascade,
  parent_clause_id uuid references public.regulatory_clauses(id) on delete cascade,
  clause_number text not null,
  clause_title text,
  section_title text,
  page_start integer,
  page_end integer,
  classification text not null default 'unclassified',
  requirement_text text not null,
  guidance_text text,
  applicability_status text not null default 'pending_review',
  applicability_rationale text,
  extraction_confidence numeric(5,4),
  review_status text not null default 'ai_extracted',
  reviewed_by uuid,
  reviewed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(document_id, document_version_id, clause_number)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'regulatory_clauses_classification_check'
  ) then
    alter table public.regulatory_clauses
      add constraint regulatory_clauses_classification_check
      check (classification in ('S','G','unclassified'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'regulatory_clauses_applicability_status_check'
  ) then
    alter table public.regulatory_clauses
      add constraint regulatory_clauses_applicability_status_check
      check (applicability_status in ('pending_review','applicable','partially_applicable','not_applicable'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'regulatory_clauses_review_status_check'
  ) then
    alter table public.regulatory_clauses
      add constraint regulatory_clauses_review_status_check
      check (review_status in ('ai_extracted','review_required','confirmed','rejected'));
  end if;
end
$$;

create index if not exists regulatory_clauses_library_idx
  on public.regulatory_clauses(document_id, classification, applicability_status, review_status);

create index if not exists regulatory_clauses_clause_number_idx
  on public.regulatory_clauses(document_id, clause_number);

create table if not exists public.internal_documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  document_code text,
  document_type text not null default 'policy',
  owner_business_unit text,
  version_label text,
  approval_date date,
  effective_date date,
  review_date date,
  status text not null default 'draft',
  file_name text,
  storage_path text,
  checksum_sha256 text,
  ingestion_status text not null default 'registered',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.internal_document_sections (
  id uuid primary key default gen_random_uuid(),
  internal_document_id uuid not null references public.internal_documents(id) on delete cascade,
  parent_section_id uuid references public.internal_document_sections(id) on delete cascade,
  section_number text,
  section_title text,
  page_start integer,
  page_end integer,
  content text not null,
  extraction_confidence numeric(5,4),
  review_status text not null default 'ai_extracted',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists internal_document_sections_document_idx
  on public.internal_document_sections(internal_document_id, section_number);

create table if not exists public.gap_assessments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  regulatory_document_id uuid not null references public.regulatory_documents(id),
  regulatory_document_version_id uuid references public.regulatory_document_versions(id),
  assessment_period_start date,
  assessment_period_end date,
  scope text,
  business_unit text,
  owner_id uuid,
  reviewer_id uuid,
  status text not null default 'draft',
  overall_outcome text not null default 'not_assessed',
  due_date date,
  started_at timestamptz,
  submitted_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.gap_assessment_sources (
  assessment_id uuid not null references public.gap_assessments(id) on delete cascade,
  internal_document_id uuid not null references public.internal_documents(id) on delete cascade,
  primary key (assessment_id, internal_document_id)
);

create table if not exists public.gap_assessment_findings (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.gap_assessments(id) on delete cascade,
  regulatory_clause_id uuid not null references public.regulatory_clauses(id),
  internal_document_section_id uuid references public.internal_document_sections(id),
  outcome text not null default 'not_assessed',
  finding_summary text,
  gap_description text,
  existing_control text,
  assessor_rationale text,
  ai_analysis text,
  ai_confidence numeric(5,4),
  reviewer_comment text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(assessment_id, regulatory_clause_id, internal_document_section_id)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'gap_assessments_status_check'
  ) then
    alter table public.gap_assessments
      add constraint gap_assessments_status_check
      check (status in ('draft','in_progress','pending_review','returned','approved','closed','cancelled'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'gap_assessments_outcome_check'
  ) then
    alter table public.gap_assessments
      add constraint gap_assessments_outcome_check
      check (overall_outcome in ('not_assessed','compliant','partially_compliant','non_compliant','not_applicable'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'gap_assessment_findings_outcome_check'
  ) then
    alter table public.gap_assessment_findings
      add constraint gap_assessment_findings_outcome_check
      check (outcome in ('not_assessed','compliant','partially_compliant','non_compliant','not_applicable'));
  end if;
end
$$;

create index if not exists gap_assessment_findings_assessment_idx
  on public.gap_assessment_findings(assessment_id, outcome, status);

create table if not exists public.remediation_actions (
  id uuid primary key default gen_random_uuid(),
  finding_id uuid not null references public.gap_assessment_findings(id) on delete cascade,
  action_title text not null,
  action_description text,
  owner_id uuid,
  owner_business_unit text,
  priority text not null default 'medium',
  status text not null default 'open',
  due_date date not null,
  revised_due_date date,
  completion_percent integer not null default 0,
  completion_notes text,
  submitted_for_validation_at timestamptz,
  validated_at timestamptz,
  validated_by uuid,
  closure_comment text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  check (completion_percent between 0 and 100)
);

create table if not exists public.evidence_items (
  id uuid primary key default gen_random_uuid(),
  action_id uuid references public.remediation_actions(id) on delete cascade,
  finding_id uuid references public.gap_assessment_findings(id) on delete cascade,
  evidence_type text not null default 'document',
  title text not null,
  description text,
  file_name text,
  storage_path text,
  source_url text,
  checksum_sha256 text,
  evidence_date date,
  uploaded_by uuid,
  review_status text not null default 'pending_review',
  reviewed_by uuid,
  reviewed_at timestamptz,
  reviewer_comment text,
  created_at timestamptz not null default now(),
  check (action_id is not null or finding_id is not null)
);

create index if not exists remediation_actions_work_queue_idx
  on public.remediation_actions(status, due_date, owner_id);

create index if not exists evidence_items_review_queue_idx
  on public.evidence_items(review_status, created_at);

create table if not exists public.cet_assessments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  assessment_type text not null default 'compliance_evaluation',
  business_unit text,
  owner_id uuid,
  reviewer_id uuid,
  period_start date,
  period_end date,
  status text not null default 'draft',
  due_date date,
  score numeric(7,2),
  rating text,
  summary text,
  approved_at timestamptz,
  approved_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.cet_items (
  id uuid primary key default gen_random_uuid(),
  cet_assessment_id uuid not null references public.cet_assessments(id) on delete cascade,
  item_order integer not null,
  question text not null,
  response_type text not null default 'compliance_outcome',
  response_value text,
  score numeric(7,2),
  finding_id uuid references public.gap_assessment_findings(id),
  evidence_required boolean not null default false,
  assessor_comment text,
  reviewer_comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cet_assessment_id, item_order)
);

create table if not exists public.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  module_key text not null,
  description text,
  version integer not null default 1,
  is_active boolean not null default true,
  definition jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique(name, version)
);

create table if not exists public.workflow_instances (
  id uuid primary key default gen_random_uuid(),
  workflow_definition_id uuid not null references public.workflow_definitions(id),
  entity_type text not null,
  entity_id uuid not null,
  current_step_key text,
  status text not null default 'active',
  context jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  started_by uuid
);

create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  recipient_user_id uuid,
  reminder_type text not null default 'due_date',
  channel text not null default 'in_app',
  scheduled_for timestamptz not null,
  status text not null default 'pending',
  escalation_level integer not null default 0,
  payload jsonb not null default '{}'::jsonb,
  sent_at timestamptz,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists reminders_dispatch_idx
  on public.reminders(status, scheduled_for);

create table if not exists public.dashboard_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  dashboard_key text not null default 'compliance_home',
  layout jsonb not null default '[]'::jsonb,
  filters jsonb not null default '{}'::jsonb,
  visible_widgets jsonb not null default '[]'::jsonb,
  refresh_interval_seconds integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, dashboard_key)
);

create table if not exists public.audit_events (
  id bigint generated by default as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_user_id uuid,
  actor_type text not null default 'user',
  action text not null,
  entity_type text not null,
  entity_id text,
  module_key text,
  request_id text,
  before_state jsonb,
  after_state jsonb,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists audit_events_entity_idx
  on public.audit_events(entity_type, entity_id, occurred_at desc);

create or replace view public.regulatory_requirements_library as
select
  d.id as document_id,
  d.title as document_title,
  d.document_code,
  d.source_org,
  d.document_type,
  d.version_label,
  d.effective_date,
  d.status as document_status,
  d.applicability_status as document_applicability,
  c.id as clause_id,
  c.clause_number,
  c.clause_title,
  c.section_title,
  c.page_start,
  c.page_end,
  c.classification,
  c.requirement_text,
  c.guidance_text,
  c.applicability_status,
  c.applicability_rationale,
  c.review_status,
  c.extraction_confidence,
  c.updated_at
from public.regulatory_documents d
join public.regulatory_clauses c on c.document_id = d.id;

-- Keep all Phase 1 business tables server-side until role policies are added.
alter table public.regulatory_document_versions enable row level security;
alter table public.regulatory_clauses enable row level security;
alter table public.internal_documents enable row level security;
alter table public.internal_document_sections enable row level security;
alter table public.gap_assessments enable row level security;
alter table public.gap_assessment_sources enable row level security;
alter table public.gap_assessment_findings enable row level security;
alter table public.remediation_actions enable row level security;
alter table public.evidence_items enable row level security;
alter table public.cet_assessments enable row level security;
alter table public.cet_items enable row level security;
alter table public.workflow_definitions enable row level security;
alter table public.workflow_instances enable row level security;
alter table public.reminders enable row level security;
alter table public.dashboard_preferences enable row level security;
alter table public.audit_events enable row level security;

revoke all on public.regulatory_requirements_library from anon, authenticated;
grant select on public.regulatory_requirements_library to service_role;

comment on view public.regulatory_requirements_library is
  'Noventra clause-level requirements library with source, S/G classification, applicability and review status.';

comment on table public.audit_events is
  'Append-only Noventra source-to-decision audit history.';

commit;
