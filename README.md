# AI Job Application Agent

An AI-powered job application pipeline built with n8n workflows, Firecrawl, Azure OpenAI, Supabase, Google Sheets, and Google Docs.

## Architecture

```
Firecrawl (Job Boards) → n8n Workflows → Azure OpenAI (GPT-4o + Embeddings)
                                        → Google Sheets (Tracking)
                                        → Google Docs (Tailored Resumes)
                                        → Supabase pgvector (Vector Search)
```

### Workflow Pipeline

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ 01 Job Discovery │───▶│ 02 Enrichment    │───▶│ 03 Score+Resume  │───▶│ 04 Approval+Doc  │
│                  │    │                  │    │                  │    │                  │
│ Firecrawl scrapes│    │ Firecrawl scrapes│    │ Azure OpenAI     │    │ You review in    │
│ Seek, Lever,     │    │ job page + company│   │ scores fit,      │    │ Google Sheet,    │
│ Greenhouse       │    │ website, Azure   │    │ generates resume │    │ approve/edit,    │
│                  │    │ OpenAI summarizes │    │ markdown         │    │ creates Google   │
│ Dedup by hash    │    │                  │    │                  │    │ Doc              │
└──────────────────┘    └──────────────────┘    └──────────────────┘    └──────────────────┘
```

| Workflow | Purpose | Trigger |
|----------|---------|---------|
| **01 - Job Discovery** | Scrapes job board search pages via Firecrawl, extracts jobs, deduplicates, saves to Google Sheets | Manual / Schedule |
| **02 - Company Enrichment** | Scrapes full job description + company website, summarizes with Azure OpenAI | Manual (reads `discovered` jobs) |
| **03 - Relevance And Resume** | Scores fit against master resume, generates tailored resume for high-scoring jobs | Manual (reads `enriched` jobs) |
| **04 - Resume Approval** | Reads `approved` jobs, optionally revises resume from review notes, creates Google Doc | Manual (reads `approved` jobs) |

## Deduplication

Jobs are deduplicated at two levels:
1. **Within a search run**: Hash of `company_name|title` prevents duplicates from the same search page
2. **Across runs**: New jobs are checked against existing `job_url_hash` and `job_url` in Google Sheets before appending

## Human Review Flow

```
Score >= 80  → status: needs_review  → resume_markdown visible in Sheet
Score 65-79  → status: needs_review  → no resume generated yet
Score < 65   → status: rejected

You review in Google Sheet:
  → Set status to "approved"                    → Workflow 04 creates Google Doc as-is
  → Edit resume_markdown + set "approved"       → Workflow 04 uses your edited version
  → Write review_notes + set "approved"         → Workflow 04 asks Azure OpenAI to revise first
  → Set status to "rejected"                    → Skipped
```

## Search Criteria

Configured in Workflow 01 `Build Search URLs` node:

| Keywords | Location | Site |
|----------|----------|------|
| AI Engineer | Sydney NSW | Seek |
| AI ML Engineer | Sydney NSW | Seek |
| Continuous Improvement Specialist/Manager | Sydney NSW | Seek |
| Process Improvement Analyst | Sydney NSW | Seek |
| Operations Improvement Specialist/Manager/Analyst | Sydney NSW | Seek |
| Agentic AI Automation Engineer | Sydney NSW | Seek |
| ISO 9001 Quality Manager | Sydney NSW | Seek |
| Quality Assurance Manager | Sydney NSW | Seek |
| Quality Manager | Sydney NSW | Seek |
| Lean Six Sigma | Sydney NSW | Seek |
| Process Automation Engineer | All Australia | Seek |

## Services & Infrastructure

| Service | Purpose |
|---------|---------|
| **n8n Cloud** | Workflow orchestration |
| **Firecrawl** | Job board + company website scraping |
| **Azure OpenAI (GPT-4o)** | Job scoring, company summarization, resume generation |
| **Azure OpenAI (ada-002)** | Embeddings for vector search |
| **Google Sheets** | Job tracking database + master resume |
| **Google Docs** | Generated tailored resume documents |
| **Supabase pgvector** | Vector storage for semantic search |

## Google Sheets Structure

### Tab: Jobs

See [docs/data-model.md](docs/data-model.md) for full column list.

### Tab: Master Resume

| Column | Purpose |
|--------|---------|
| section | Resume section (summary, experience, skills, education, etc.) |
| content | The actual resume text for that section |

### Tab: Search Criteria (optional)

| Column | Purpose |
|--------|---------|
| keywords | Search terms |
| location | Job location |
| site | Job board (seek, lever, greenhouse) |
| active | yes/no |

## Setup

### 1. Configure Credentials

```bash
# Secrets are in config/.env (gitignored)
# See config/environment.template.md for reference
```

### 2. Create Google Sheet

Create a spreadsheet with tabs: `Jobs`, `Master Resume`

Add your resume content to the `Master Resume` tab.

Copy the Spreadsheet ID into `config/.env` as `GOOGLE_SHEETS_JOB_TRACKER_ID`.

### 3. Import Workflows to n8n

Import each JSON from `n8n/workflows/` into n8n:
1. 01 - Job Discovery
2. 02 - Company Enrichment
3. 03 - Relevance And Resume
4. 04 - Resume Approval

Configure credentials (Firecrawl HTTP Header Auth, Azure OpenAI HTTP Header Auth, Google Sheets OAuth).

### 4. Run

1. Run Workflow 01 → discovers jobs, saves to Sheet
2. Run Workflow 02 → enriches discovered jobs
3. Run Workflow 03 → scores and generates resumes
4. Review in Google Sheet → set status to `approved`
5. Run Workflow 04 → creates Google Docs

## Project Structure

```
├── .gitignore
├── README.md
├── config/
│   ├── .env                              # Secrets (gitignored)
│   └── environment.template.md           # Credential reference
├── docs/
│   ├── architecture.md
│   ├── data-model.md
│   └── implementation-plan.md
└── n8n/
    ├── prompts/
    │   ├── relevance-scoring-prompt.md
    │   └── resume-generation-prompt.md
    ├── schemas/
    │   ├── job-fit-analysis.schema.json
    │   └── tailored-resume.schema.json
    └── workflows/
        ├── job-discovery.workflow.json
        ├── company-enrichment.workflow.json
        ├── relevance-and-resume.workflow.json
        └── resume-approval.workflow.json
```

## Manual LinkedIn Jobs

For LinkedIn-only jobs, paste directly into the Google Sheet `Jobs` tab:
1. Copy job title, company, location, and full description from LinkedIn
2. Paste into the appropriate columns
3. Set status to `discovered`
4. Run Workflow 02 onwards — pipeline handles the rest

## License

Private — internal use.
