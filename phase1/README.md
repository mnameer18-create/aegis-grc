# Noventra Phase 1 — Foundation

**Brand:** Noventra — Powered by AI
**Working branch:** `noventra-phase1-foundation`
**Preserved baseline:** `phase3-rag-mvp`
**Status:** In progress

## Master build tracker

### 1. Preserve the working setup

- [x] Create a dedicated Noventra Phase 1 branch from the working Phase 3 RAG branch.
- [x] Leave the existing Phase 2 and Phase 3 branches and n8n workflows unchanged.
- [x] Keep the existing `regulatory_documents`, `regulatory_chunks`, and grounded RAG function compatible.

### 2. Rebrand AEGIS to Noventra

- [x] Change user-facing product name to **Noventra**.
- [x] Apply the tagline **Powered by AI**.
- [x] Update the frontend title, navigation, descriptions, and assistant labels.
- [ ] Rename new workflow and credential display names without breaking existing credentials.
- [x] Verify no secret, endpoint, or workflow reference is accidentally changed.

### 3. Establish the Supabase foundation

- [x] Add document versioning and ingestion lifecycle fields.
- [x] Add clause-level regulatory requirements with page, section, and S/G classification.
- [x] Add internal policy, OSOPM, process, and section storage.
- [x] Add gap assessments and clause-level findings.
- [x] Add remediation actions and evidence records.
- [x] Add CET assessment and response records.
- [x] Add configurable workflow definitions and instances.
- [x] Add reminders and escalation records.
- [x] Add dashboard preferences.
- [x] Add source-to-decision audit history.
- [x] Enable RLS and keep the new tables server-side pending the RBAC phase.
- [x] Create the `regulatory_requirements_library` view.
- [x] Apply the migration to Supabase and confirm all 16 foundation tables exist.

### 4. Upgrade regulatory ingestion

- [ ] Accept BNM policy documents and approved extracted text.
- [x] Preserve document title, version, source URL, file name, checksum, page, and section in the controlled clause-ingestion contract.
- [ ] Extract each clause as a separate requirement.
- [x] Classify stored clauses as **S — Standard**, **G — Guidance**, or unclassified.
- [x] Store extraction confidence and route uncertain clauses to human review.
- [x] Prevent duplicate ingestion using checksum and document-version controls.
- [x] Return a controlled ingestion receipt with document, version, clause count, and review count.

### 5. Build the Regulatory Requirements Library

- [ ] Browse by regulatory document.
- [ ] Search by clause number or requirement text.
- [ ] Filter by S/G classification.
- [ ] Filter by applicability and review status.
- [x] Verify backend clause traceability for page, section, source, version, classification, confidence, and review status.
- [x] Restrict the new view and ingestion function to the server-side service role until RBAC policies are implemented.

## Phase 1 acceptance criteria

Phase 1 is complete only when:

- the working Phase 2/3 setup remains operational;
- the product is visibly branded Noventra — Powered by AI;
- the foundation schema is applied and verified;
- ingestion stores clause number, page, section, classification, confidence, and source version;
- the Regulatory Requirements Library exposes the extracted requirements with traceability;
- a controlled test BNM document can be ingested without exposing secrets;
- the result is verified in Supabase and the tracker is updated.

## Implemented migrations

Run after `phase3/sql/001_rag_schema.sql`:

```
phase1/sql/002_noventra_foundation_schema.sql
phase1/sql/003_regulatory_ingestion_rpc.sql
```

The migrations are additive and intentionally do not modify the live Phase 2/3 n8n workflows.

## Latest controlled verification

- Synthetic clause ingestion stored 2 clauses with S/G classification and page traceability.
- One lower-confidence clause was routed to human review.
- The duplicate checksum probe returned the original document with 2 stored clauses and 1 review-required clause.
- The Requirements Library view returned both clauses with their source metadata.
