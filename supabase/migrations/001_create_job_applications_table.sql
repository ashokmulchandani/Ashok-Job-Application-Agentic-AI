-- Job Applications Vector Table for Semantic Search
-- Run this in Supabase SQL Editor

-- Enable pgvector if not already enabled
create extension if not exists vector;

-- Create the job_applications table with vector column
create table if not exists job_applications (
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

-- Create index for vector similarity search
create index if not exists job_applications_embedding_idx 
  on job_applications 
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 50);

-- Create index for filtering
create index if not exists job_applications_status_idx on job_applications(status);
create index if not exists job_applications_company_idx on job_applications(company_name);
create index if not exists job_applications_job_id_idx on job_applications(job_id);

-- Create the match function for vector search
create or replace function match_job_applications(
  query_embedding vector(1536),
  match_count int default 5,
  filter jsonb default '{}'::jsonb
)
returns table (
  id bigint,
  job_id text,
  title text,
  company_name text,
  location text,
  industry text,
  status text,
  fit_score integer,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    ja.id,
    ja.job_id,
    ja.title,
    ja.company_name,
    ja.location,
    ja.industry,
    ja.status,
    ja.fit_score,
    ja.content,
    ja.metadata,
    1 - (ja.embedding <=> query_embedding) as similarity
  from job_applications ja
  where
    (filter->>'status' is null or ja.status = filter->>'status')
    and (filter->>'company_name' is null or ja.company_name = filter->>'company_name')
    and (filter->>'industry' is null or ja.industry = filter->>'industry')
  order by ja.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- Create upsert function for n8n to call
create or replace function upsert_job_application(
  p_job_id text,
  p_title text,
  p_company_name text,
  p_location text,
  p_industry text,
  p_status text,
  p_fit_score integer,
  p_content text,
  p_metadata jsonb,
  p_embedding vector(1536)
)
returns void
language plpgsql
as $$
begin
  insert into job_applications (job_id, title, company_name, location, industry, status, fit_score, content, metadata, embedding, updated_at)
  values (p_job_id, p_title, p_company_name, p_location, p_industry, p_status, p_fit_score, p_content, p_metadata, p_embedding, now())
  on conflict (job_id)
  do update set
    title = excluded.title,
    company_name = excluded.company_name,
    location = excluded.location,
    industry = excluded.industry,
    status = excluded.status,
    fit_score = excluded.fit_score,
    content = excluded.content,
    metadata = excluded.metadata,
    embedding = excluded.embedding,
    updated_at = now();
end;
$$;
