# mcp-public

Public, authless PharmaGuide MCP server: product discovery and verified catalog facts. It takes no
account, reads no profile, and returns no personal data. Streamable HTTP with stateless JSON responses
(no sessions, no SSE stream; `GET` returns 405).

Tools: `search_products(query, brand?, form?, supplement_type?, sort?, offset?, catalog_version?)`, `get_product(dsld_id)`, `lookup_barcode(upc)`. Every
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

## Comparing public products

Use `sort: "quality"` for a descending comparison of the existing exported
`quality_score_v4_100`, across the whole name-matched set before paging. No score is
recomputed. Only completed/scored values rank numerically; other records remain
visible after them. Quality does not establish safety or personal suitability.
`match_confidence` is text relevance, not quality. Report `total_matches` and filters;
use `next_offset` with the returned `catalog_version` for another page. A changed
version is refused. A name match is not an exhaustive ingredient inventory.

`sort: "relevance"` remains the default for identifying a named product. Ambiguity
requires identity clarification for an owned product, not for browsing alternatives.
Use the existing `supplement_type` classification (e.g. `single_mineral`) to compare
like products. Fetch `get_product` before describing candidates. Different record IDs
can represent label variants; names alone do not establish equivalent formulas.

Details preserve pipeline pillar scores/reasons, confidence, serving_info, display
forms, claim-scoped form references and row_ledger ownership. Ingredient amounts use
the published serving basis. `owner_row_ref` refers to another ingredient's
`raw_source_path`: never add a component to its parent. Missing relationships or dose
basis remain unknown. Daily-serving ranges are label directions, not personalized doses.

Clinical warning statements retain their full qualifications up to 20,000 characters;
oversized statements are omitted with a limitation rather than clipped. Missing evidence
grades and citations are explicitly disclosed; a registry identifier is not a clinical
citation. This projection does not invent references or expand conditional-warning policy.

Schema prerequisite: pipeline migration `20261013213803_public_catalog_comparison.sql`.
Backfill the new score column only from the checksum-verified published core DB; do not
substitute current development output or infer scores from tiers. Apply schema/backfill
before deploying the consumer. The prior public consumer is compatible with this upgrade.
