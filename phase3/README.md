# AEGIS Phase 3 — Regulatory RAG MVP

This branch adds a source-grounded Regulatory Intelligence proof of concept without changing the working Phase 2 production path.

## Goal

Prove this flow first:

1. Register one authoritative regulatory document.
2. Chunk the source text.
3. Generate embeddings with OpenAI `text-embedding-3-small`.
4. Store chunks and vectors in Supabase pgvector.
5. Embed a user question.
6. Retrieve the most relevant regulatory passages.
7. Generate an answer constrained to those passages.
8. Return explicit source references and keep human review mandatory.

## Files

- `sql/001_rag_schema.sql` — creates `regulatory_documents`, `regulatory_chunks`, vector index and `match_regulatory_chunks()`.
- `n8n/AEGIS_RAG_Ingestion_v01.json` — protected text-ingestion workflow.
- `n8n/AEGIS_RAG_Query_v01.json` — protected grounded-query workflow.

## Security model

The browser must never receive a Supabase secret key or OpenAI key.

For n8n:
- Reuse the existing **AEGIS webhook Header Auth** credential for both new webhook nodes.
- Reuse the existing **OpenAI Bearer Auth** credential for embedding and chat nodes.
- Create one new n8n **Header Auth** credential for Supabase:
  - Header Name: `apikey`
  - Header Value: your Supabase **secret key** (`sb_secret_...`)
  - Suggested credential name: `AEGIS Supabase Server API`

Attach this Supabase credential only to the HTTP Request nodes that call `https://ekndgnhiivfoczewmgpz.supabase.co/rest/v1/...`.

Do not paste the Supabase secret into GitHub, JavaScript, workflow JSON, screenshots or chat.

## Step 1 — Database

Open Supabase → SQL Editor → New query.

Paste and run:
`phase3/sql/001_rag_schema.sql`

Expected result: success with two tables and the `match_regulatory_chunks` RPC function.

The schema uses 1536-dimensional vectors to match the default output of `text-embedding-3-small`.

## Step 2 — Import n8n ingestion workflow

Import:
`phase3/n8n/AEGIS_RAG_Ingestion_v01.json`

Configure:
- **Protected RAG Ingest Webhook** → existing AEGIS Header Auth credential.
- **Create Document Record** → `AEGIS Supabase Server API`.
- **Create Chunk Embedding** → existing OpenAI Bearer Auth credential.
- **Store Chunk in Supabase** → `AEGIS Supabase Server API`.

Do not publish until a manual/test execution succeeds.

### Initial ingestion request

This MVP intentionally accepts extracted text first. It does **not** parse a PDF yet.

Example body:

```json
{
  "title": "Example BNM policy document",
  "source_org": "Bank Negara Malaysia",
  "source_type": "policy_document",
  "source_url": "https://authoritative-source.example/document.pdf",
  "version_label": "Current version",
  "effective_date": "2026-01-01",
  "content": "Paste the document text here for the first controlled test..."
}
```

A successful response includes:
- `document_id`
- `chunks_stored`
- `embedding_model`
- `request_id`

## Step 3 — Import grounded query workflow

Import:
`phase3/n8n/AEGIS_RAG_Query_v01.json`

Configure:
- **Protected RAG Query Webhook** → existing AEGIS Header Auth credential.
- **Embed Question** → existing OpenAI Bearer Auth credential.
- **Retrieve Regulatory Evidence** → `AEGIS Supabase Server API`.
- **Generate Grounded Answer** → existing OpenAI Bearer Auth credential.

Publish only after a successful test.

## Step 4 — Acceptance test

Ask a question that is clearly answered by the ingested document.

Expected response:

```json
{
  "answer": "Grounded answer with [S1] style citations...",
  "mode": "grounded_rag",
  "sources": [
    {
      "citation_id": "S1",
      "document_title": "...",
      "source_org": "Bank Negara Malaysia",
      "source_url": "...",
      "page_number": null,
      "section_title": null,
      "similarity": 0.0
    }
  ],
  "regulatory_sources_verified": true,
  "human_review_required": true
}
```

Then ask something **not covered** by the indexed document. The workflow should decline to invent an answer and return the no-evidence message.

## Important MVP limitation

This first Phase 3 implementation proves retrieval and grounded generation using source text supplied to the ingestion workflow.

It does not yet:
- download or parse PDFs automatically;
- preserve PDF page numbers automatically;
- detect document supersession/version conflicts;
- compare internal policies against regulations;
- monitor BNM websites for regulatory change.

Those come after the retrieval/citation loop is proven.

## Phase 3B after acceptance

Once the grounded test passes:
1. automate PDF download and text extraction;
2. preserve page/section metadata;
3. add document version and supersession controls;
4. route the existing Aegis `aegis-ai` gateway to the grounded query workflow;
5. display clickable sources inside the Aegis UI.
