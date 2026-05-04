import json

f = r'c:\Users\ashok\OneDrive\NOblox\Job_Application_Agent_Ashok\n8n\workflows\Job Agent - 02 Company Enrichment.json'
with open(f, 'r', encoding='utf-8') as fh:
    wf = json.load(fh)

for n in wf['nodes']:
    if n['name'] == 'Parse Company Summary':
        n['parameters']['jsCode'] = r"""const job = $('Extract Full Description').item.json;
const raw = $json.choices?.[0]?.message?.content || '{}';
let company;
try { company = JSON.parse(raw); } catch (e) { company = { parse_error: true, raw: raw.slice(0, 500) }; }

const pdfUrl = job.job_pdf_url || '';

// Get discovery metadata from Scrape and Combine Pages
let scrapeInput = {};
try { scrapeInput = $('Scrape and Combine Pages').item.json || {}; } catch(e) {}

company.scraped_urls = scrapeInput.scrape_urls || [];
company.discovery = {
  sitemap_urls_found: scrapeInput.sitemap_urls_found || 0,
  map_urls_found: scrapeInput.map_urls_found || 0,
  total_discovered: scrapeInput.total_discovered || 0,
  pages_scraped: (scrapeInput.scrape_urls || []).length
};

return [{ json: {
  ...job,
  company_summary: company.company_summary || JSON.stringify(company).slice(0, 500),
  company_research: company,
  job_pdf_url: pdfUrl,
  status: 'enriched',
  updated_at: new Date().toISOString()
} }];"""
        print('Updated: Parse Company Summary with discovery metadata')

with open(f, 'w', encoding='utf-8') as fh:
    json.dump(wf, fh, indent=2)
print('Done')
