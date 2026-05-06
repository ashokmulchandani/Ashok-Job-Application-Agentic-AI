# AI Job Application Agent

An AI-powered job application pipeline built with n8n workflows, Firecrawl, Azure OpenAI GPT-4o, Google Sheets, Google Docs, and Google Drive.

Automatically discovers jobs on Seek, enriches them with company research, scores fit against your master resume, generates tailored resumes with industry-specific project examples, and creates formatted HTML + Google Doc outputs ready for application.

## Architecture

```
Firecrawl (Seek Job Boards) → n8n Workflows → Azure OpenAI GPT-4o (Scoring + Resume)
                                             → Google Sheets (Job Tracker + Master Resume)
                                             → Google Drive (HTML Resume + Google Doc + Screenshots)
                                             → Supabase pgvector (Vector Search + Full Data Store)
```

### Workflow Pipeline

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ 01 Job Discovery │───▶│ 02 Enrichment    │───▶│ 03 Score+Resume  │───▶│ 04 Approval+Doc  │
│                  │    │                  │    │                  │    │                  │
│ Firecrawl scrapes│    │ Scrape full JD   │    │ Azure OpenAI     │    │ Review in Sheet  │
│ Seek search pages│    │ + company website │    │ scores fit,      │    │ approve/edit,    │
│ Extract + dedup  │    │ + screenshot     │    │ generates resume │    │ creates HTML +   │
│ Save to Sheet    │    │ Company research │    │ + 5 SMART projects│   │ Google Doc       │
└──────────────────┘    └──────────────────┘    └──────────────────┘    └──────────────────┘
```

| Workflow | Purpose | Trigger | Input Status | Output Status |
|----------|---------|---------|-------------|---------------|
| **01 - Job Discovery** | Scrapes Seek search pages via Firecrawl, extracts jobs, deduplicates, saves to Google Sheets | Manual | N/A | `discovered` |
| **02 - Company Enrichment** | Scrapes full JD (waitFor: 5s), company website, generates company research, embeds + upserts to Supabase, takes screenshot | Manual | `discovered` | `enriched` |
| **03 - Relevance And Resume** | Scores fit against unified master resume, generates tailored resume + 5 SMART projects, upserts to Supabase | Manual | `enriched` | `needs_review` |
| **04 - Resume Approval** | Fetches resume from Supabase, optionally revises from review notes, creates HTML file + Google Doc in Drive | Manual | `approved` | `resume_generated` |
| **06 - Chat with Jobs** | Natural language Q&A over job data using Supabase + Azure OpenAI | Manual (chat) | Any | N/A |

## Key Features

- **Unified Master Resume** — All 7+ employers with full project details, GPT-4o selects relevant ones per job
- **Company Research Integration** — Scraped company data (products, values, tech signals) used to reframe achievements with industry-specific language
- **HTML Resume Output** — Google Sans Text font, 10pt body, 13pt bold headers, #1B1C1D color, 114% line-height, disc bullets
- **5 SMART Project Examples** — Hypothetical but realistic AI/automation projects tailored to target company's industry, written in first person with specific metrics
- **Seek Full Description Scraping** — Firecrawl waitFor: 5000ms ensures JS-rendered content loads completely
- **Smart URL Selection** — Pick Top Pages uses priority patterns (about, clients, services, specialisations) and exclude patterns (blog, job listings, video) to select 10 high-value pages from sitemap + /map results
- **Job Screenshots** — Full-page screenshots saved to Google Drive with hyperlink in sheet
- **Dual Output** — Both HTML file (pixel-perfect formatting) and Google Doc (editable text) created per job
- **Supabase Vector Store** — Full job data (description, company research, resume, embeddings) stored in Supabase; Google Sheet kept lightweight with pointers
- **Metadata Merge** — Supabase upsert function merges metadata across workflows (WF02 + WF03 data coexists)

## Deduplication

Jobs are deduplicated at two levels:
1. **Within a search run**: Hash of `company_name|title` prevents duplicates from the same search page
2. **Across runs**: New jobs are checked against existing `job_url_hash` and `job_url` in Google Sheets before appending

## Human Review Flow

```
Score >= 80  → status: needs_review  → resume + projects generated, stored in Supabase
Score 65-79  → status: needs_review  → no resume generated
Score < 65   → status: rejected      → no resume generated

You review in Google Sheet:
  → Set status to "approved"                    → WF04 creates HTML + Doc as-is
  → Edit resume_markdown + set "approved"       → WF04 uses your edited version
  → Write review_notes + set "approved"         → WF04 asks GPT-4o to revise first
  → Set status to "rejected"                    → Skipped
```

## Search Criteria

Configured in Workflow 01 `Build Search URLs` node:

| Keywords | Location | Site |
|----------|----------|------|
| AI Engineer | Sydney NSW | Seek |
| AI ML Engineer | Sydney NSW | Seek |
| Continuous Improvement Specialist | Sydney NSW | Seek |
| Continuous Improvement Manager | Sydney NSW | Seek |
| Process Improvement Analyst | Sydney NSW | Seek |
| Operations Improvement Manager | Sydney NSW | Seek |
| Operations Improvement Analyst | Sydney NSW | Seek |
| Agentic AI Automation Engineer | Sydney NSW | Seek |
| ISO 9001 Quality Manager | Sydney NSW | Seek |
| Quality Assurance Manager | Sydney NSW | Seek |
| Quality Manager | Sydney NSW | Seek |
| Lean Six Sigma | Sydney NSW | Seek |
| AI Adoption Specialist | Sydney NSW | Seek |
| AI Adoption Manager | Sydney NSW | Seek |
| Change Manager | Sydney NSW | Seek |
| Process Automation Engineer | All Australia | Seek |

## Services & Infrastructure

| Service | Purpose | Details |
|---------|---------|---------|
| **n8n Cloud** | Workflow orchestration | 5 workflows + chat, manual triggers |
| **Firecrawl** | Job board + company website scraping | waitFor: 5s for Seek, screenshot@fullPage |
| **Azure OpenAI GPT-4o** | Job scoring, company research, resume generation | Deployment: `Test-Ashok-1-gpt-4o` |
| **Azure OpenAI GPT-4o-mini** | Company summary generation | Deployment: `testashok1-gpt-4o-mini` |
| **Azure OpenAI Embeddings** | Vector embeddings for job data | Deployment: `testashok1-noble-oak-text-embedding-3-small` |
| **Google Sheets** | Lightweight job tracker + master resume | Service Account auth |
| **Google Docs** | Generated resume documents (text) | OAuth2 auth |
| **Google Drive** | HTML resumes + screenshots storage | OAuth2 auth |
| **Supabase** | Full data store + pgvector search | `job_applications` table, 1536-dim embeddings |

### Azure OpenAI Deployments

| Model | Deployment Name | Purpose |
|-------|-----------------|---------|
| GPT-4o | `Test-Ashok-1-gpt-4o` | Fit scoring, resume generation |
| GPT-4o-mini | `testashok1-gpt-4o-mini` | Company summary generation |
| text-embedding-3-small | `testashok1-noble-oak-text-embedding-3-small` | Vector embeddings (1536 dim) |

## Data Storage Strategy

| Data | Location | Notes |
|------|----------|-------|
| Job metadata (title, company, status, score) | Google Sheets | Lightweight, human-readable |
| Full job description | Supabase `content` + `metadata.description` | Too large for sheet cells |
| Company research (JSON) | Supabase `metadata.company_research` | Includes `scraped_urls`, `discovery` stats |
| Resume HTML + Markdown | Supabase `metadata.resume_html/resume_markdown` | Sheet shows "See Supabase" |
| Fit rationale | Google Sheets `fit_rationale` | Short enough for sheet |
| Vector embeddings | Supabase `embedding` (1536-dim) | For semantic search |
| Screenshots | Google Drive | Hyperlinked from sheet |

## Google Sheets Structure

### Tab: Jobs

Key columns: `job_id`, `title`, `company_name`, `status`, `fit_score`, `fit_decision`, `fit_rationale`, `matched_requirements`, `missing_requirements`, `company_summary`, `company_research` (shows "Full data in Supabase"), `resume_markdown` (shows "See Supabase"), `resume_html` (shows "See Supabase"), `resume_doc_url`, `review_notes`

### Tab: Master Resume (Unified)

| Column | Purpose |
|--------|---------|
| section | Resume section name (summary, contact, experience_current, experience_fspr, etc.) |
| content | The actual resume text for that section |

18 data rows covering: summary, contact, expertise_areas, 9 employer experiences (current through L&T), skills_technical, skills_methodologies, certifications, education, industries_served, key_metrics.

## Setup

### Prerequisites

- n8n Cloud account (or self-hosted n8n)
- Azure OpenAI resource with GPT-4o deployment
- Firecrawl API key
- Google Cloud project with Sheets, Docs, Drive APIs enabled
- Google Service Account (for Sheets) + OAuth2 credentials (for Docs/Drive)

### 1. Configure Credentials

```bash
cp config/.env.example config/.env
# Fill in your API keys and IDs
```

### 2. Create Google Sheet

Create a spreadsheet with tabs: `Jobs`, `Master Resume`

Paste `Ashok-Master_Resume/master_resume_UNIFIED_for_google_sheet.tsv` into the Master Resume tab (2 columns: section, content).

### 3. Import Workflows to n8n

Import each JSON from `n8n/workflows/` into n8n:
1. `Job Agent - 01 Job Discovery.json`
2. `Job Agent - 02 Company Enrichment.json`
3. `Job Agent - 03 Relevance And Resume.json`
4. `Job Agent - 04 Resume Approval and Doc Creation.json`

Configure credentials (Firecrawl HTTP Header Auth, Azure OpenAI HTTP Header Auth, Google Service Account, Google OAuth2).

**Important n8n import notes:**
- Code nodes may import with default template code — verify each Code node has the correct code from the JSON
- Node names may get numbers appended — Code node `$()` references must match exactly
- Verify all connections match the expected flow after import

### 4. Daily Usage

```
1. Run WF01 → discovers new jobs from Seek
2. Run WF02 → enriches discovered jobs (full JD + company research + screenshot)
3. Run WF03 → scores fit + generates tailored resumes with 5 project examples
4. Review in Google Sheet → set status to "approved"
5. Run WF04 → creates HTML file + Google Doc in Drive
6. Open HTML in browser → Print to PDF → Apply
```

## Project Structure

```
├── .gitignore
├── README.md
├── Ashok-Master_Resume/
│   ├── master_resume_UNIFIED_for_google_sheet.tsv   # 2-column unified resume (use this)
│   ├── master_resume_all_versions.tsv               # Multi-type resume versions
│   └── master_resume_for_google_sheet.tsv            # Original unified version
├── config/
│   ├── .env                              # Secrets (gitignored)
│   └── environment.template.md           # Credential reference
├── docs/
│   ├── architecture.md                   # System architecture
│   ├── data-model.md                     # Data model (Sheets + Supabase)
│   └── implementation-plan.md            # Original implementation plan
├── n8n/
│   ├── prompts/
│   │   ├── relevance-scoring-prompt.md   # Fit scoring prompt reference
│   │   └── resume-generation-prompt.md   # Resume generation prompt reference
│   ├── schemas/
│   │   ├── job-fit-analysis.schema.json
│   │   └── tailored-resume.schema.json
│   └── workflows/
│       ├── Job Agent - 01 Job Discovery.json
│       ├── Job Agent - 02 Company Enrichment.json
│       ├── Job Agent - 03 Relevance And Resume.json
│       ├── Job Agent - 04 Resume Approval and Doc Creation.json
│       └── Job Agent - 06 Chat with Jobs.json
├── supabase/
│   └── migrations/
│       └── 001_create_job_applications_table.sql    # Table + upsert function + vector index
└── Sample_test_Job_Application_Case_Ashok/
    └── (test PDFs)
```

## Workflow Node Details

### WF01 - Job Discovery
```
Manual Trigger → Build Search URLs → Firecrawl Scrape Search Page → Extract Jobs From Markdown
→ Filter Empty Results → Read Existing Jobs → Deduplicate Against Sheet → Has New Jobs?
→ Append New Jobs to Sheet → Summary
```

### WF02 - Company Enrichment
```
Manual Trigger → Read Discovered Jobs → Filter Discovered Only → Prepare Job Scrape
→ [Firecrawl Scrape Job Page (waitFor:5s), Firecrawl Screenshot Job Page] (parallel)
→ Extract Full Description → Has Company Website?
  → Yes: Firecrawl Map Company → Fetch Robots.txt → Parse Robots Sitemap
         → Fetch Sitemap XML → Merge Sitemap + Map URLs → Pick Top Pages (10 URLs)
         → Scrape Company Page (HTTP Request, batched) → Combine Scraped Pages
         → Prepare Azure Request → Azure OpenAI Company Summary → Parse Company Summary
         → Prepare Vector Data → Generate Embedding → Upsert to Supabase
         → Prepare Sheet Data → Update Job Row
  → No:  Google Company Website (DuckDuckGo, waitFor:3s) → Extract Company URL → Has URL Now? → ...
Screenshot branch: Has Screenshot? → Prepare Screenshot Binary → Download PNG → Upload to Drive → Set PDF URL
```

### WF03 - Relevance And Resume
```
Manual Trigger → Read Enriched Jobs → Read Master Resume → Filter Enriched Only
→ Fetch from Supabase → Prepare Fit Input (unified resume, dedup sections, parse company_research)
→ Prepare Fit Request → Azure OpenAI Fit Score → Parse Fit Score → Score >= 80?
  → Yes: Prepare Resume Request (HTML template + 5 SMART projects) → Azure OpenAI Generate Resume
         → Parse Resume → Upsert Resume to Supabase → Restore Job Data → Update Google Sheets
  → No:  Score < 80 - No Resume → Update Google Sheets
```

### WF04 - Resume Approval and Doc Creation
```
Manual Trigger → Read Approved Jobs → Filter Approved Only (trim+lowercase)
→ Fetch Resume from Supabase → Merge Supabase Resume → Has Review Notes?
  → Yes: Prepare Revision Request (HTML template) → Azure OpenAI Revise Resume → Parse Revised Resume
  → No:  (skip revision)
→ Prepare Doc Data → Prepare HTML Binary
→ [Upload HTML File (fire-and-forget), Create Google Doc → Prepare Doc Content → Insert Doc Text] (parallel)
→ Prepare Sheet Update → Update Google Sheets
```

### WF06 - Chat with Jobs
```
Manual Trigger (chat input) → Embed Query (Azure OpenAI)
→ Fetch Jobs from Supabase (GET with filters) → Build Chat Prompt
→ Azure OpenAI GPT-4o → Return Response
```

## Manual LinkedIn Jobs

For LinkedIn-only jobs, paste directly into the Google Sheet `Jobs` tab:
1. Copy job title, company, location, and full description from LinkedIn
2. Paste into the appropriate columns
3. Set status to `discovered`
4. Run Workflow 02 onwards — pipeline handles the rest

## Supabase Vector Store

### Table: `job_applications`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | bigserial | Primary key |
| `job_id` | text (unique) | Links to Google Sheet |
| `title` | text | Job title |
| `company_name` | text | Company |
| `location` | text | Location |
| `industry` | text | Auto-detected industry |
| `status` | text | Pipeline status |
| `fit_score` | integer | 0-100 relevance score |
| `content` | text | Full searchable text (description + company research) |
| `metadata` | jsonb | All rich data (see below) |
| `embedding` | vector(1536) | text-embedding-3-small |

### Metadata JSONB Structure (merged across WF02 + WF03)

```json
{
  "description": "Full job description from Seek",
  "job_url": "https://au.seek.com/job/...",
  "company_website": "https://...",
  "salary": "",
  "contract_type": "full time",
  "remote_policy": "hybrid",
  "enriched_at": "2026-05-06T...",
  "company_research": {
    "company_summary": "...",
    "products": [...],
    "customers": [...],
    "values": [...],
    "technical_signals": [...],
    "hiring_signals": [...],
    "keywords": [...],
    "scraped_urls": [...],
    "discovery": {
      "sitemap_source": "...",
      "sitemap_urls_found": 5,
      "map_urls_found": 5,
      "total_discovered": 10,
      "pages_scraped": 5
    }
  },
  "resume_html": "<html>...",
  "resume_markdown": "# Ashok...",
  "fit_rationale": "...",
  "matched_requirements": "...",
  "missing_requirements": "...",
  "tailoring_rationale": "..."
}
```

### Upsert Function

The `upsert_job_application` function uses:
- **JSONB merge** (`||`) — WF02 and WF03 metadata coexists without overwriting
- **COALESCE for embeddings** — WF03 (null embedding) doesn't overwrite WF02's embedding
- **COALESCE for all fields** — null values don't wipe existing data

### Use Cases

- Semantic job search ("find similar roles")
- Company intelligence clustering
- Interview prep ("common requirements for AI Engineer roles")
- Skill gap tracking across applications
- Chat workflow (WF06) for natural language Q&A over job data

## License

Private — internal use.
