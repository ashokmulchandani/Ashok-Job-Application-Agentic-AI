# Architecture

## System Overview

The AI Job Application Agent is a 4-workflow pipeline orchestrated by n8n Cloud. It discovers jobs from Seek, enriches them with company research, scores fit against a unified master resume, generates tailored resumes with industry-specific project examples, and outputs both HTML and Google Doc formats.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   WF01      │────▶│   WF02      │────▶│   WF03      │────▶│   WF04      │
│ Discovery   │     │ Enrichment  │     │ Score+Resume│     │ Approval    │
│             │     │             │     │             │     │ +Doc Create │
│ Firecrawl   │     │ Firecrawl   │     │ Azure GPT-4o│     │ Google Drive│
│ → Sheets    │     │ + Azure AI  │     │ + Sheets    │     │ + Docs      │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
   discovered          enriched          needs_review         resume_generated
```

## Component Architecture

```
                    ┌──────────────────────────────────┐
                    │         n8n Cloud                 │
                    │  (Workflow Orchestration Engine)   │
                    └──────────┬───────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    ┌─────▼─────┐      ┌──────▼──────┐     ┌──────▼──────┐
    │ Firecrawl  │      │ Azure OpenAI│     │   Google    │
    │            │      │   GPT-4o    │     │  Workspace  │
    │ • Scrape   │      │             │     │             │
    │ • Screenshot│     │ • Fit Score │     │ • Sheets    │
    │ • Map      │      │ • Company   │     │ • Docs      │
    │ • waitFor  │      │   Research  │     │ • Drive     │
    └────────────┘      │ • Resume Gen│     └─────────────┘
                        │ • Revision  │
                        └─────────────┘
```

## Data Flow

### WF01: Job Discovery

```
Seek Search URLs → Firecrawl Scrape → Extract Jobs from Markdown
→ Dedup (hash + URL) → Append to Google Sheets [status: discovered]
```

**Key decisions:**
- Seek URLs are constructed from keyword + location combinations
- Jobs are hashed by `company_name|title` for within-run dedup
- Cross-run dedup checks `job_url_hash` and `job_url` against existing sheet rows
- Each job gets a unique `job_id` derived from the hash

### WF02: Company Enrichment

```
Read discovered jobs → Prepare Job Scrape (set scrape_url)
→ PARALLEL:
    Branch A: Firecrawl Scrape Job Page (waitFor: 5000ms) → Extract Full Description
    Branch B: Firecrawl Screenshot → Has Screenshot? → Download PNG → Upload to Drive → Set PDF URL

Extract Full Description → Extract company_website from JD
→ Has Company Website?
    Yes → Firecrawl Map → Pick Top Pages → Scrape & Combine → Prepare Azure Request
        → Azure OpenAI Company Summary → Parse Company Summary [JSON.stringify] → Update Sheet
    No  → DuckDuckGo search → Extract Company URL → retry or Skip
```

**Key decisions:**
- `waitFor: 5000` ensures Seek's JS-rendered content loads fully
- Company research is `JSON.stringify()`'d before writing to Sheets (prevents `[object Object]`)
- Azure request text is sanitized (control characters stripped) to prevent JSON parse errors
- Screenshot flow runs in parallel, doesn't block main enrichment
- Company website extraction excludes job board domains (seek, linkedin, etc.)

### WF03: Relevance And Resume

```
Read enriched jobs + Read Master Resume → Filter Enriched Only
→ Prepare Fit Input:
    • Uses ALL rows from Master Resume (unified format, no resume_type filtering)
    • Deduplicates by section name (prevents pipeline data duplication)
    • Parses company_research from JSON string back to object
→ Prepare Fit Request → Azure OpenAI Fit Score → Parse Fit Score
→ Score >= 80?
    Yes → Prepare Resume Request → Azure OpenAI Generate Resume → Parse Resume
    No  → Score < 80 - No Resume (status: needs_review if >= 65, rejected if < 65)
→ Update Google Sheets
```

**Key decisions:**
- Master resume is unified (2-column: section|content) with all 7+ employers
- GPT-4o selects relevant employers per job — no pre-filtering by resume type
- Company research is injected into both fit scoring and resume generation prompts
- Resume prompt specifies exact HTML formatting (Google Sans Text, 10pt, 13pt headers, #1B1C1D)
- Resume includes 5 SMART-format project examples tailored to target company's industry
- `max_tokens: 6000` to accommodate resume + projects

### WF04: Resume Approval and Doc Creation

```
Read approved jobs → Filter Approved Only (trim + lowercase status check)
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
- Filter uses `trim().toLowerCase()` to handle trailing spaces in status
- HTML file preserves all CSS formatting (open in browser → Print to PDF)
- Google Doc has text content with structure (headings, bullets) but simplified styling
- Both files saved to same Google Drive folder
- Review notes trigger GPT-4o revision before doc creation

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
→ Azure OpenAI extracts structured research:
    {
      company_summary: "2-3 sentences",
      products: [...],
      customers: [...],
      values: [...],
      technical_signals: [...],
      hiring_signals: [...],
      keywords: [...]
    }
→ JSON.stringify() → Store in Google Sheets company_research column
→ WF03 parses back to object → Injects into fit scoring + resume generation prompts
```

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
- No personal data stored in vector DB (planned)
- Resume content is truthful — GPT-4o instructed to never fabricate
- Company research used for positioning only, not inventing experience

## Planned: Supabase pgvector Integration

```
WF02 (after enrichment) → Azure OpenAI text-embedding-3-small → Supabase pgvector
    Content: job_description + company_research + fit_analysis
    Metadata: job_id, title, company, score, status, industry

Use cases:
    • Semantic job search ("find similar roles")
    • Company intelligence clustering
    • Skill gap tracking across applications
    • Interview preparation
```

## Known n8n Cloud Limitations

- Code nodes may import with default template code — always verify after import
- Node names may get numbers appended on import — `$()` references must match exactly
- `helpers.httpRequestWithAuthentication` not available in Code nodes
- Google Drive upload doesn't support `convert` option for HTML-to-Doc
- Expression mode can embed literal `=` prefix in field values
- Sequential Google Sheets nodes can leak data between pipeline stages (solved with section dedup)
