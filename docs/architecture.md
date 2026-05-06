# Architecture

## System Overview

The AI Job Application Agent is a 5-workflow + chat pipeline orchestrated by n8n Cloud. It discovers jobs from Seek, enriches them with company research, stores full data + embeddings in Supabase, scores fit against a unified master resume, generates tailored resumes with industry-specific project examples, and outputs both HTML and Google Doc formats.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   WF01      │────▶│   WF02      │────▶│   WF03      │────▶│   WF04      │
│ Discovery   │     │ Enrichment  │     │ Score+Resume│     │ Approval    │
│             │     │             │     │             │     │ +Doc Create │
│ Firecrawl   │     │ Firecrawl   │     │ Azure GPT-4o│     │ Google Drive│
│ → Sheets    │     │ + Azure AI  │     │ + Supabase  │     │ + Docs      │
│             │     │ + Supabase  │     │             │     │ + Supabase  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
   discovered          enriched          needs_review         resume_generated

                    ┌─────────────┐
                    │   WF06      │
                    │ Chat w/Jobs │
                    │             │
                    │ Supabase    │
                    │ + GPT-4o    │
                    └─────────────┘
```

## Component Architecture

```
                    ┌──────────────────────────────────┐
                    │         n8n Cloud                 │
                    │  (Workflow Orchestration Engine)   │
                    └──────────┬───────────────────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
 ┌─────▼─────┐         ┌──────▼──────┐         ┌──────▼──────┐
 │ Firecrawl  │         │ Azure OpenAI│         │   Google    │
 │            │         │             │         │  Workspace  │
 │ • Scrape   │         │ • GPT-4o    │         │             │
 │ • Screenshot│        │ • GPT-4o-mini│        │ • Sheets    │
 │ • Map      │         │ • Embeddings│         │ • Docs      │
 │ • waitFor  │         │ • Revision  │         │ • Drive     │
 └────────────┘         └─────────────┘         └─────────────┘
                               │
                        ┌──────▼──────┐
                        │  Supabase   │
                        │             │
                        │ • pgvector  │
                        │ • JSONB     │
                        │ • Full data │
                        │ • Metadata  │
                        │   merge     │
                        └─────────────┘
```

## Data Storage Strategy

Google Sheets is kept lightweight (metadata + pointers). All heavy content lives in Supabase:

| Data | Google Sheet | Supabase |
|------|-------------|----------|
| Job title, company, status | ✓ | ✓ |
| Fit score + rationale | ✓ | ✓ (in metadata) |
| Full job description | "See Supabase" | `content` + `metadata.description` |
| Company research (JSON) | "Full data in Supabase" | `metadata.company_research` |
| Resume HTML + Markdown | "See Supabase" | `metadata.resume_html/resume_markdown` |
| Vector embedding | ✘ | `embedding` (1536-dim) |
| Screenshots | Drive hyperlink | ✘ |

## Data Flow

### WF01: Job Discovery

```
Seek Search URLs → Firecrawl Scrape → Extract Jobs from Markdown
→ Dedup (hash + URL) → Append to Google Sheets [status: discovered]
```

**Key decisions:**
- Seek URLs use `au.seek.com` (not www.seek.com.au)
- Jobs are hashed by `company_name|title` for within-run dedup
- Cross-run dedup checks `job_url_hash` and `job_url` against existing sheet rows
- Each job gets a unique `job_id` derived from the hash
- Optional keyword override via manual trigger input JSON `{ "keyword": "...", "location": "..." }`
- HTTP Request uses batching (2 items, 5s interval) with `onError: continueRegularOutput`

### WF02: Company Enrichment

```
Read discovered jobs → Filter Discovered Only → Prepare Job Scrape (set scrape_url)
→ PARALLEL:
    Branch A: Firecrawl Scrape Job Page (waitFor: 5000ms) → Extract Full Description
    Branch B: Firecrawl Screenshot → Has Screenshot? → Download PNG → Upload to Drive → Set PDF URL

Extract Full Description → Extract company_website from JD
→ Has Company Website?
    Yes → Firecrawl Map → Pick Top Pages → Scrape & Combine → Prepare Azure Request
        → Azure OpenAI Company Summary → Parse Company Summary
        → Prepare Vector Data → Generate Embedding → Upsert to Supabase
        → Prepare Sheet Data → Update Sheet
    No  → DuckDuckGo search → Extract Company URL → retry or Skip
```

**Key decisions:**
- `waitFor: 5000` ensures Seek's JS-rendered content loads fully
- Full data (description, company_research as JSON object, embedding) stored in Supabase
- Google Sheet only gets lightweight fields + "See Supabase" / "Full data in Supabase" pointers
- `Prepare Vector Data` builds searchable `content` field + structured `metadata` JSONB
- `company_research` stored as proper JSON object in metadata (includes `scraped_urls`, `discovery` stats)
- Azure request text is sanitized (control characters stripped) to prevent JSON parse errors
- Screenshot flow runs in parallel, doesn't block main enrichment
- Company website extraction excludes job board domains (seek, linkedin, etc.)

### WF03: Relevance And Resume

```
Read enriched jobs + Read Master Resume → Filter Enriched Only
→ Fetch from Supabase (get full description + company_research from metadata)
→ Prepare Fit Input:
    • Uses ALL rows from Master Resume (unified format, no resume_type filtering)
    • Deduplicates by section name (prevents pipeline data duplication)
    • Parses company_research from Supabase metadata
→ Prepare Fit Request → Azure OpenAI Fit Score → Parse Fit Score
→ Score >= 80?
    Yes → Prepare Resume Request → Azure OpenAI Generate Resume → Parse Resume
        → Upsert Resume to Supabase (metadata merge: resume_html, resume_markdown, fit_rationale)
        → Restore Job Data (only sheet-relevant fields) → Update Google Sheets
    No  → Score < 80 - No Resume (status: needs_review if >= 65, rejected if < 65)
        → Update Google Sheets (only sheet-relevant fields)
```

**Key decisions:**
- Master resume is unified (2-column: section|content) with all 7+ employers
- GPT-4o selects relevant employers per job — no pre-filtering by resume type
- Company research is injected into both fit scoring and resume generation prompts
- Resume prompt specifies exact HTML formatting (Google Sans Text, 10pt, 13pt headers, #1B1C1D)
- Resume includes 5 SMART-format project examples tailored to target company's industry
- `max_tokens: 8000` to accommodate resume + projects
- `Restore Job Data` outputs ONLY sheet-relevant fields (job_id, status, fit_score, fit_decision, fit_rationale, matched/missing requirements, "See Supabase" pointers)
- Supabase upsert uses JSONB merge (`||`) — WF03 metadata merges with WF02 metadata, doesn't overwrite
- Embedding preserved via `COALESCE(excluded.embedding, job_applications.embedding)`

### WF04: Resume Approval and Doc Creation

```
Read approved jobs → Filter Approved Only (trim + lowercase status check)
→ Fetch Resume from Supabase → Merge Supabase Resume
→ Has Review Notes?
    Yes → Prepare Revision Request → Azure OpenAI Revise → Parse Revised Resume
    No  → Pass through
→ Prepare Doc Data (build filename + HTML content)
→ Prepare HTML Binary (create binary from HTML string)
→ PARALLEL:
    Branch A: Upload HTML File to Drive (fire-and-forget)
    Branch B: Create Google Doc → Prepare Doc Content → Insert Doc Text
→ Prepare Sheet Update → Update Google Sheets [status: resume_generated]
```

**Key decisions:**
- Resume content fetched from Supabase (not Google Sheet) — sheet only has "See Supabase"
- Filter uses `trim().toLowerCase()` to handle trailing spaces in status
- HTML file preserves all CSS formatting (open in browser → Print to PDF)
- Google Doc has text content with structure (headings, bullets) but simplified styling
- Both files saved to same Google Drive folder
- Review notes trigger GPT-4o revision before doc creation

### WF06: Chat with Jobs

```
Manual Trigger (chat input) → Embed Query (Azure OpenAI text-embedding-3-small)
→ Fetch Jobs from Supabase (GET with filters) → Build Chat Prompt
→ Azure OpenAI GPT-4o → Return Response
```

**Key decisions:**
- Uses simple GET query (not RPC) due to Supabase REST API vector type limitations
- `Build Chat Prompt` uses `$input.all().map(i => i.json)` to get all items

## Master Resume Strategy

The system uses a **unified master resume** approach:

```
┌─────────────────────────────────────────────┐
│           Master Resume (Google Sheet)       │
│                                             │
│  summary          → Professional summary    │
│  contact          → Contact details         │
│  expertise_areas  → Key skills & expertise  │
│  experience_current → Govt Procurement      │
│  experience_fspr    → Aurion/FSPR           │
│  experience_stramit → Stramit-Fletchers     │
│  experience_ugl     → UGL Unipart          │
│  experience_justice  → Justice NSW          │
│  experience_serco    → Serco Defence        │
│  experience_vfx      → VFX Print Group     │
│  experience_health   → NSW Health           │
│  experience_lt       → L&T Medical Devices  │
│  skills_technical   → Tools & platforms     │
│  skills_methodologies → Lean, Six Sigma etc │
│  certifications     → Professional certs    │
│  education          → Degree                │
│  industries_served  → Sector experience     │
│  key_metrics        → Headline numbers      │
└─────────────────────────────────────────────┘
         │
         ▼ GPT-4o selects relevant employers per job
         │
    ┌────┴────┐
    │ AI Role │ → Emphasizes: Govt Procurement (AI chatbot), FSPR (CRM bot), L&T (dashboards)
    ├─────────┤
    │ Quality │ → Emphasizes: Govt Procurement (ISO), Stramit (multi-cert), UGL (ISO 55001)
    ├─────────┤
    │ Change  │ → Emphasizes: Govt Procurement (14 units), FSPR (BMS migration), Serco (PLM)
    └─────────┘
```

## Company Research Flow

```
Job Description → Extract company_website URL
→ Firecrawl /map endpoint → discover site pages
→ Pick priority pages (about, products, services, careers)
→ Scrape & combine markdown (up to 12KB)
→ Azure OpenAI GPT-4o-mini extracts structured research:
    {
      company_summary: "2-3 sentences",
      products: [...],
      customers: [...],
      values: [...],
      technical_signals: [...],
      hiring_signals: [...],
      keywords: [...],
      scraped_urls: [...],
      discovery: { sitemap_source, sitemap_urls_found, map_urls_found, total_discovered, pages_scraped }
    }
→ Stored as JSON object in Supabase metadata.company_research
→ Google Sheet gets "Full data in Supabase" pointer
→ WF03 reads from Supabase → Injects into fit scoring + resume generation prompts
```

## Supabase Schema

### Table: `job_applications`

```sql
create table job_applications (
  id bigserial primary key,
  job_id text unique not null,
  title text,
  company_name text,
  location text,
  industry text,
  status text,
  fit_score integer,
  content text not null,
  metadata jsonb default '{}'::jsonb,
  embedding vector(1536),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
```

### Upsert Function (metadata merge)

```sql
on conflict (job_id) do update set
  metadata = COALESCE(job_applications.metadata, '{}'::jsonb) || COALESCE(excluded.metadata, '{}'::jsonb),
  embedding = COALESCE(excluded.embedding, job_applications.embedding),
  -- other fields use COALESCE to preserve existing values
```

This ensures:
- WF02 metadata (description, company_research, enriched_at) persists when WF03 adds resume data
- WF03's null embedding doesn't overwrite WF02's embedding
- Empty strings don't wipe existing content

## Resume Generation Output

Each generated resume includes:

1. **Professional Summary** — tailored to job + company language
2. **Key Expertise** — reordered to match job requirements
3. **Professional Experience** — relevant employers with reframed achievements
4. **Key Achievements** — headline metrics
5. **Education & Certifications**
6. **Technical Skills** — prioritized to match job description
7. **5 Relevant Project Examples** — SMART format, 4-5 sentences each:
   - Hypothetical but realistic AI/automation projects
   - Tailored to target company's industry and challenges
   - Reference tools from job description
   - Include specific metrics and business impact

## HTML Formatting Specification

```css
body {
  font-family: 'Google Sans Text', Arial, sans-serif;
  font-size: 10pt;
  color: #1B1C1D;
  line-height: 114%;
}
h1 { font-size: 16pt; font-weight: bold; text-align: center; }
h2 { font-size: 13pt; font-weight: bold; }
hr { border: 1px solid #1B1C1D; }  /* thin separator under name */
ul { list-style-type: disc; }
```

## Security & Data Handling

- API keys stored in n8n credentials and `.env` (gitignored)
- Google Sheets accessed via Service Account (read/write)
- Google Docs/Drive accessed via OAuth2
- Supabase accessed via service role JWT in HTTP headers
- Resume content is truthful — GPT-4o instructed to never fabricate
- Company research used for positioning only, not inventing experience

## Known n8n Cloud Limitations

- Code nodes may import with default template code — always verify after import
- Node names may get numbers appended on import — `$()` references must match exactly
- `helpers.httpRequestWithAuthentication` not available in Code nodes
- Google Drive upload doesn't support `convert` option for HTML-to-Doc
- Expression mode can embed literal `=` prefix in field values
- Sequential Google Sheets nodes can leak data between pipeline stages (solved with section dedup)
- 60-second timeout on Code nodes
- No `fetch` available in Code nodes (use HTTP Request nodes instead)
- Google Sheets API: 60 read requests per minute per user — space out workflow runs
- Supabase REST API cannot pass `vector(1536)` type through RPC calls reliably — use simple GET for reads
- Code nodes that create new items break the paired item chain — downstream nodes can't reference upstream by name (use `$json` or try/catch)
