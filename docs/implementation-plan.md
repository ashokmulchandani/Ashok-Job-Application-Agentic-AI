# Implementation Plan

## Phase 1: Manual MVP

Goal: process a small batch of jobs and generate useful tailored resumes.

Tasks:

- Create Google Sheet with the tracking columns in `data-model.md`.
- Add master resume and career profile.
- Run Apify manually from n8n.
- Normalize job data.
- Score each job using OpenAI.
- Generate resume HTML for approved jobs.
- Create Google Docs.
- Log results.

Acceptance criteria:

- 20 jobs can be ingested.
- Duplicates are removed.
- Irrelevant jobs are rejected.
- Relevant jobs receive a fit score and rationale.
- Generated resume has no fabricated experience.
- Google Sheet is updated end to end.

## Phase 2: Company Enrichment

Goal: improve resume quality with company-specific context.

Tasks:

- Add Firecrawl scrape/crawl step.
- Extract company mission, product signals, industry, values, and technical keywords.
- Store company research in vector DB.
- Add company context to relevance and resume prompts.

Acceptance criteria:

- Resume bullets reflect the company and role without inventing facts.
- Company context is visible in the job row.
- Failed company scrape does not block scoring.

## Phase 3: Vector Memory

Goal: retrieve the best resume evidence for each job.

Tasks:

- Chunk master resume and project stories.
- Generate embeddings.
- Store chunks in Pinecone or Supabase pgvector.
- Store job descriptions and company pages.
- Retrieve top matching resume chunks for each job.

Acceptance criteria:

- Every generated resume cites only real resume evidence.
- The relevance score includes matched and missing requirements.

## Phase 4: Human Review Workflow

Goal: make the system safe for real applications.

Tasks:

- Add status states: discovered, enriched, scored, rejected, needs_review, resume_generated, approved, applied.
- Add manual approval column.
- Add notification for high-fit jobs.
- Add review notes.

Acceptance criteria:

- No application is submitted without approval.
- User can rerun generation after editing review notes.

## Phase 5: Production Hardening

Goal: make it reliable enough for daily use.

Tasks:

- Add idempotency store.
- Add rate limits.
- Add dead-letter workflow.
- Add execution summaries.
- Add cost tracking.
- Add prompt versioning.
- Add evaluation set of jobs with expected decisions.

Acceptance criteria:

- Failed jobs are recoverable.
- Duplicate documents are not created.
- Generated resumes are traceable to prompts, model, input job, and resume source.

