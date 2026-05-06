# Data Model

## Overview

Data is split between Google Sheets (lightweight tracker) and Supabase (full data store):
- **Google Sheets** — human-readable job tracker with status, scores, and pointers
- **Supabase** — full job descriptions, company research, resumes, and vector embeddings

## Google Sheets: `Jobs` Tab

| Column | Purpose | Example |
| --- | --- | --- |
| serial_no | Row number | 1 |
| job_id | Stable internal ID | `job_4d3e2950fd80` |
| job_url_hash | Deduplication key | `4d3e2950fd80ecdd` |
| job_url | Original job posting URL | `https://au.seek.com/job/91772063` |
| title | Job title | AI Engineer |
| company_name | Company name | Arkadia Talent |
| company_url | Seek company page | `https://au.seek.com/Arkadia-Talent-jobs` |
| company_website | Resolved website | `https://arkadiatalent.com.au` |
| location | Job location | Sydney NSW |
| remote_policy | remote, hybrid, onsite | hybrid |
| salary | Salary range if available | $850 |
| contract_type | full-time, contract, part-time | full time |
| posted_at | Posting date | |
| apply_url | Application URL | `https://au.seek.com/job/91772063` |
| description | "See Supabase" pointer | See Supabase |
| source | Search source | seek_AI Engineer |
| search_keywords | Keywords used | AI Engineer |
| status | Pipeline status | enriched |
| fit_score | 0-100 relevance score | 82 |
| fit_decision | reject, needs_review, generate_resume | generate_resume |
| fit_rationale | Short explanation | The candidate... |
| matched_requirements | Comma-separated | Python, AI experience... |
| missing_requirements | Comma-separated | PhD, LLM orchestration... |
| company_summary | 2-3 sentence summary | Company builds AI... |
| company_research | "Full data in Supabase" pointer | Full data in Supabase |
| resume_markdown | "See Supabase" pointer | See Supabase |
| resume_html | "See Supabase" pointer | See Supabase |
| resume_doc_url | Generated Google Doc URL | |
| job_pdf_url | Drive screenshot hyperlink | =HYPERLINK("...","View Screenshot") |
| review_notes | Human feedback for regeneration | |
| applied_at | Timestamp after application | |
| created_at | First seen timestamp | 2026-05-05T04:20:23Z |
| updated_at | Last update timestamp | 2026-05-06T02:16:56Z |
| error | Last error message | |

## Google Sheets: `Master Resume` Tab

| Column | Purpose |
|--------|---------|
| section | Resume section name |
| content | The actual resume text for that section |

18 data rows: summary, contact, expertise_areas, experience_current, experience_fspr, experience_stramit, experience_ugl, experience_justice, experience_serco, experience_vfx, experience_health, experience_lt, skills_technical, skills_methodologies, certifications, education, industries_served, key_metrics.

## Pipeline Status Values

| Status | Set By | Meaning |
|--------|--------|---------|
| `discovered` | WF01 | Job found on Seek, basic info extracted |
| `enriched` | WF02 | Full description + company research + embedding stored |
| `needs_review` | WF03 | Scored (fit >= 65), awaiting human review |
| `rejected` | WF03 | Scored (fit < 65), not worth pursuing |
| `approved` | Human | Ready for doc generation |
| `resume_generated` | WF04 | HTML + Google Doc created |
| `applied` | Human | Application submitted |

## Supabase: `job_applications` Table

| Column | Type | Purpose |
|--------|------|---------|
| `id` | bigserial | Primary key |
| `job_id` | text (unique) | Links to Google Sheet |
| `title` | text | Job title |
| `company_name` | text | Company |
| `location` | text | Location |
| `industry` | text | Auto-detected (Finance, Healthcare, etc.) |
| `status` | text | Pipeline status |
| `fit_score` | integer | 0-100 relevance score |
| `content` | text | Full searchable text for embedding |
| `metadata` | jsonb | All rich data (merged across workflows) |
| `embedding` | vector(1536) | text-embedding-3-small |
| `created_at` | timestamptz | First insert |
| `updated_at` | timestamptz | Last upsert |

### `content` Field Structure

Built by WF02's `Prepare Vector Data` node:

```
Job Title: Staff AI Engineer
Company: Future Secure AI Pty Ltd
Location: Sydney NSW
Description: [full job description from Seek]
Company Summary: [2-3 sentences]
Products: [comma-separated]
Customers: [comma-separated]
Values: [comma-separated]
Technical Signals: [comma-separated]
Hiring Signals: [comma-separated]
Keywords: [comma-separated]
```

### `metadata` JSONB Structure

Merged across WF02 + WF03 via `||` operator:

```json
{
  "description": "Full job description from Seek (up to 10KB)",
  "job_url": "https://au.seek.com/job/...",
  "company_website": "https://...",
  "salary": "",
  "contract_type": "full time",
  "remote_policy": "hybrid",
  "search_keywords": "AI Engineer",
  "enriched_at": "2026-05-06T02:15:18.860Z",
  "company_research": {
    "company_summary": "2-3 sentences about the company",
    "products": ["product1", "product2"],
    "customers": ["customer segment 1"],
    "values": ["innovation", "collaboration"],
    "technical_signals": ["Python", "LLM", "MLOps"],
    "hiring_signals": ["rapid expansion", "mentorship"],
    "keywords": ["AI Engineer", "autonomous systems"],
    "scraped_urls": ["https://company.com", "https://company.com/about", "..."],
    "discovery": {
      "sitemap_source": "https://company.com/sitemap.xml",
      "sitemap_urls_found": 15,
      "map_urls_found": 5,
      "total_discovered": 20,
      "pages_scraped": 5
    }
  },
  "resume_html": "<html>...(full HTML resume)...</html>",
  "resume_markdown": "# Ashok Mulchandani\n...",
  "fit_rationale": "The candidate...",
  "matched_requirements": "Python, AI experience...",
  "missing_requirements": "PhD, LLM orchestration...",
  "tailoring_rationale": "This resume emphasizes..."
}
```

### Indexes

```sql
-- Vector similarity search (IVFFlat, cosine)
create index job_applications_embedding_idx
  on job_applications using ivfflat (embedding vector_cosine_ops) with (lists = 50);

-- Filtering
create index job_applications_status_idx on job_applications(status);
create index job_applications_company_idx on job_applications(company_name);
create index job_applications_job_id_idx on job_applications(job_id);
```

### Upsert Behavior

The `upsert_job_application` function handles multi-workflow writes:

| Field | Behavior |
|-------|----------|
| `metadata` | **Merge** — `existing || new` (JSONB `||` operator) |
| `embedding` | **Preserve** — `COALESCE(new, existing)` |
| `content` | **Preserve if empty** — `CASE WHEN new = '' THEN existing ELSE new END` |
| Other fields | **Preserve if null** — `COALESCE(new, existing)` |

This means:
- WF02 writes: description, company_research, enriched_at, embedding
- WF03 writes: resume_html, resume_markdown, fit_rationale, tailoring_rationale
- Both coexist in the same metadata JSONB without overwriting each other
