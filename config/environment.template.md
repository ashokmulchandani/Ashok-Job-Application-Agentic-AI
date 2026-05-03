# Environment Configuration Template

Do not store real secrets in this file. Add credentials inside n8n Credentials and `config/.env` (gitignored).

## Google Custom Search API

- API key stored in: `config/.env` as `GOOGLE_CSE_API_KEY`
- Search Engine ID (cx): `config/.env` as `GOOGLE_CSE_CX`
- Free limit: 100 queries/day
- Configured sites: jobs.lever.co, boards.greenhouse.io, apply.workable.com, seek.com.au, indeed.com.au, linkedin.com/jobs

## Firecrawl

- API key stored in: `config/.env` as `FIRECRAWL_API_KEY`
- Crawl limit per company: 5 pages
- Scrape format: markdown
- Use n8n Firecrawl node: yes

## OpenAI

- API key stored in: `config/.env` as `OPENAI_API_KEY`
- Model for scoring: gpt-4o-mini
- Model for resume generation: gpt-4o
- Embedding model: text-embedding-3-small
- Use Responses API: yes
- Use Structured Outputs: yes

## Vector Store

- Provider: Supabase pgvector
- Table name: job_application_documents
- Embedding dimension: 1536
- Stored in: `config/.env` as `SUPABASE_URL` and `SUPABASE_ANON_KEY`

## Google Sheets / Docs / Drive

- Spreadsheet ID stored in: `config/.env` as `GOOGLE_SHEETS_JOB_TRACKER_ID`
- Resume output folder stored in: `config/.env` as `GOOGLE_RESUME_FOLDER_ID`

## n8n

- Webhook base URL stored in: `config/.env` as `N8N_WEBHOOK_BASE_URL`
- Timezone: Australia/Sydney
- Human approval required: yes

## Safety

- Auto-submit enabled: no
- Minimum fit score for resume: 80
- Minimum fit score for review: 65
- Max resumes per day: 20
- Excluded companies: (configure in Google Sheet)
- Excluded titles: (configure in Google Sheet)
