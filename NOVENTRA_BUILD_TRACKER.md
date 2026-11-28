# Noventra Compliance — Master Build Tracker

Status legend: ⬜ Not started · 🟡 In progress · ✅ Completed · 🔴 Blocked

## Phase 1 — Foundation & Rebrand ✅
- [x] Rename user-facing Aegis branding to Noventra
- [x] Add “Powered by AI” tagline
- [x] Update frontend title, assistant labels, sign-in and export naming
- [x] Preserve working Phase 2 and Phase 3 branches/workflows
- [x] Create dedicated Noventra development branch
- [x] Confirm Noventra branch is additive and ahead of preserved Phase 3 baseline

## Phase 2 — Core Data Model & Compliance Architecture ✅
- [x] Regulatory documents and versions
- [x] Regulatory clauses / requirements
- [x] S / G classification
- [x] Applicability and review status
- [x] Internal documents and sections
- [x] Gap assessments and clause-level findings
- [x] Remediation actions
- [x] Evidence records
- [x] CET assessment structures
- [x] Workflow definitions and instances
- [x] Reminder dispatch records
- [x] Dashboard preferences
- [x] Audit events
- [x] RLS enabled on new business tables
- [x] Business Unit master and relational references (migration prepared)
- [x] Configurable workflow approval-step definitions (migration prepared)
- [x] Reminder / escalation rule definitions (migration prepared)
- [x] Apply and verify Phase 2 completion migration in Supabase

## Phase 3 — Regulatory Document Ingestion & Requirements Library 🟡
- [x] Controlled clause-ingestion RPC
- [x] Version/checksum duplicate protection
- [x] Page/section/source traceability contract
- [x] S / G / unclassified storage
- [x] Extraction confidence + human review routing
- [x] Regulatory Requirements Library backend view
- [ ] Automatic BNM document/PDF ingestion
- [x] AI clause extraction from source document
- [x] Controlled AI extraction test stored S/G clauses with page, section, confidence and review status
- [x] Protected extracted-text clause ingestion workflow tested and published
- [x] Requirements Library frontend
- [x] Requirements Library server-side search/filter API prepared
- [x] Search by document / clause / requirement
- [x] Filters for S/G, applicability and review status
- [x] Compliance applicability confirmation UI

## Phase 4 — AI Gap Assessment Engine ⬜
- [ ] Upload/select internal Policy, SOP/OSOPM and Process documents
- [ ] Clause-by-clause regulatory comparison
- [ ] AI proposed outcome: Compliant / Partially Compliant / Non-Compliant / Not Applicable
- [ ] Source evidence and rationale
- [ ] Human reviewer confirmation
- [ ] Assessment summary and history

## Phase 5 — Action, Remediation & Evidence Management ⬜
- [ ] Convert gaps to actions
- [ ] Assign Business Unit, owner, severity and due date
- [ ] Evidence upload/submission
- [ ] Compliance evidence review
- [ ] Date extension approval
- [ ] Verified closure

## Phase 6 — Reminder, Due Date & Escalation Engine ⬜
- [ ] Upcoming-due reminders
- [ ] Due-date reminders
- [ ] Overdue flagging
- [ ] Repeated reminders
- [ ] BU / Compliance / management escalation
- [ ] Audit reminder events

## Phase 7 — Regulatory CET / Control Effectiveness Testing ⬜
- [ ] Regulatory requirement → control mapping
- [ ] Test frequency / methodology / evidence
- [ ] Tester and reviewer
- [ ] Effective / Partially Effective / Ineffective / Not Tested / Not Applicable
- [ ] Auto-create remediation from ineffective control

## Phase 8 — Configurable Workflow & Form Builder ⬜
- [ ] Workflow builder
- [ ] Approval routing
- [ ] Conditional/risk-based routing
- [ ] Form builder
- [ ] Reusable/versioned templates

## Phase 9 — Customizable Dashboard ⬜
- [ ] Widget framework
- [ ] User-specific add/remove/reorder/resize
- [ ] Gap, action, pending, overdue, evidence, CET and trend widgets
- [ ] User filters and saved layouts

## Phase 10 — Noventra Intelligence ⬜
- [ ] Platform-wide grounded AI
- [ ] Exact regulatory citations
- [ ] Gap/remediation/evidence/CET assistance
- [ ] No-evidence fallback
- [ ] Human approval guardrails

## Phase 11 — Reporting, Management Information & Exports ⬜
- [ ] Gap, action, overdue, BU exposure and CET reports
- [ ] Regulatory requirement coverage
- [ ] Excel/PDF export
- [ ] Management packs and scheduled reporting

## Phase 12 — Roles, Permissions & Audit Trail ⬜
- [ ] Compliance / Reviewer / Manager / Head / BU / Admin roles
- [ ] Page and record-level access
- [ ] RLS by role
- [ ] Segregation of duties
- [ ] Full decision/evidence/approval history

## Phase 13 — Production Readiness & Reliability ⬜
- [ ] Rate limiting
- [ ] Central logs/error tracking
- [ ] Retry and failed-job handling
- [ ] Backup/restore/fallback
- [ ] CI/CD and automated regression tests
- [ ] Security hardening and secrets management
- [ ] Performance/scaling review

## Current build position
Phase 1 is complete. Phase 2 is applied and verified in Supabase. Phase 3 now has the protected AI clause-extraction workflow, live query API, Requirements Library frontend, search, filters and applicability confirmation UI. A controlled OpenAI test stored both Standard and Guidance clauses with page, section, confidence and review traceability. Remaining Phase 3 work: automatic BNM document/PDF ingestion.
