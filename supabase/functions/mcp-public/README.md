# mcp-public

Public, authless PharmaGuide MCP server: product discovery and verified catalog facts. It takes no
account, reads no profile, and returns no personal data. Streamable HTTP with stateless JSON responses
(no sessions, no SSE stream; `GET` returns 405).

Tools: `search_products(query, brand?, form?)`, `get_product(dsld_id)`, `lookup_barcode(upc)`. Every
result is wrapped as `{ data, name_source: "catalog", catalog_version, generated_at }`. Product
facts come from `_shared/catalog.ts`, which mirrors the app's semantics owners (see its header).

## Prerequisites

- Pipeline `scripts/sql/supabase_schema.sql` section 9 applied (`catalog_search`, the
  `catalog_search_current` view, `search_catalog()`), and a sync that published `catalog_search` rows.
- Function secrets: `SUPABASE_URL` and the service-role/secret key (provided automatically on hosted
  Edge Functions). `verify_jwt = false` is set in `supabase/config.toml`.

## Run locally

```bash
supabase functions serve mcp-public
npx @modelcontextprotocol/inspector   # transport: Streamable HTTP, URL below
# URL: http://127.0.0.1:54321/functions/v1/mcp-public
deno test --allow-read --allow-env supabase/functions   # hermetic tests (no network)
```

## Connect an assistant

- **Claude:** Settings → Connectors → Add custom connector → the deployed URL
  `https://<project>.supabase.co/functions/v1/mcp-public` (no OAuth).
- **ChatGPT:** Settings → Apps & Connectors → Developer mode → create a connector with the same URL,
  authentication "No authentication".

Directory listings (Claude / ChatGPT app directories) are for this public server only; never list a
server that can read personal data.

## Limits

In-memory per-IP token bucket (60 requests/minute, 429 with `Retry-After`), manifest cached 60 s,
detail index cached per catalog version, mapped facts cached (200 entries). Caches and limits are per
isolate, so they bound but do not globally cap traffic.
