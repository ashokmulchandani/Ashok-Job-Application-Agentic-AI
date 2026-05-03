# Data Model

## Google Sheets: `Jobs`

Recommended columns:

| Column | Purpose |
| --- | --- |
| job_id | Stable internal ID. |
| job_url | Original job posting URL. |
| job_url_hash | Deduplication key. |
| title | Job title. |
| company_name | Company name. |
| company_url | LinkedIn/company URL. |
| company_website | Resolved website used by Firecrawl. |
| location | Job location. |
| remote_policy | remote, hybrid, onsite, unknown. |
| salary | Salary range if available. |
| contract_type | full-time, contract, part-time, internship. |
| posted_at | Posting date. |
| apply_url | Application URL. |
| description | Raw or truncated job description. |
| source | Apify actor/source name. |
| status | Pipeline status. |
| fit_score | 0-100 relevance score. |
| fit_decision | reject, needs_review, generate_resume. |
| fit_rationale | Short explanation. |
| matched_requirements | Comma-separated summary. |
| missing_requirements | Comma-separated summary. |
| company_summary | Firecrawl-generated company summary. |
| resume_doc_url | Generated Google Doc URL. |
| resume_html_url | Optional Drive link for HTML. |
| review_notes | Human feedback for regeneration. |
| applied_at | Timestamp after application. |
| created_at | First seen timestamp. |
| updated_at | Last update timestamp. |
| error | Last error message. |

## Pipeline Status Values

- discovered
- duplicate
- enrichment_pending
- enriched
- scoring_pending
- scored
- rejected
- needs_review
- resume_generated
- approved
- applied
- failed

## Vector Records

### Resume Chunk

```json
{
  "id": "resume_chunk_001",
  "text": "Built workflow automation system...",
  "metadata": {
    "type": "resume_chunk",
    "section": "experience",
    "skill_tags": ["n8n", "automation", "AI"],
    "source": "master_resume",
    "updated_at": "2026-05-02T00:00:00Z"
  }
}
```

### Job Description

```json
{
  "id": "job_abc123_description",
  "text": "We are hiring a Principal AI Engineer...",
  "metadata": {
    "type": "job_description",
    "job_id": "job_abc123",
    "company_name": "Example Co",
    "role_title": "Principal AI Engineer",
    "source_url": "https://example.com/job",
    "created_at": "2026-05-02T00:00:00Z"
  }
}
```

### Company Page

```json
{
  "id": "company_exampleco_about",
  "text": "Example Co builds workflow automation...",
  "metadata": {
    "type": "company_page",
    "company_name": "Example Co",
    "source_url": "https://example.com/about",
    "page_type": "about",
    "created_at": "2026-05-02T00:00:00Z"
  }
}
```

