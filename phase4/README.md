# Noventra Phase 4 — AI Gap Assessment Engine

**Status:** Complete and verified  
**Workflow:** [Noventra AI Gap Assessment Engine](https://woolly-mediumblue-frog-03.hostingersite.com/workflow/Zucj5bXk3spqJsuD)

## Delivered

- Register a new internal Policy, SOP, OSOPM or Process document, or select an existing document.
- Store section-level internal evidence with page and review traceability.
- Load every clause for the selected BNM regulatory document.
- Compare each regulatory clause against grounded internal sections using OpenAI.
- Propose Compliant, Partially Compliant, Non-Compliant or Not Applicable.
- Store evidence quotes, rationale, gaps, existing controls and confidence.
- Require human confirmation for every AI finding.
- Maintain assessment summaries, status counts and decision history.
- Keep the workflow and APIs restricted to protected server-side credentials.

## Components

- `phase4/sql/006_gap_assessment_engine.sql`
- `phase4/n8n/Noventra_AI_Gap_Assessment_Engine_v1.json`
- `phase4/gap-assessment.html`

## Controlled verification

A synthetic internal Customer Due Diligence and Beneficial Ownership Policy with four sections was assessed against the eight stored clauses from the BNM Guidance on Beneficial Ownership document.

- 8 regulatory clauses loaded
- 4 internal-policy sections loaded
- 8 clause-level findings stored
- Overall AI proposal: Non-Compliant
- Assessment status: Pending Review
- One reviewer confirmation completed successfully
- Remaining reviewer confirmations reduced from 8 to 7
- Summary/history view verified
- Audit events written for assessment creation and reviewer confirmation

AI outcomes remain proposals until confirmed by a reviewer.
