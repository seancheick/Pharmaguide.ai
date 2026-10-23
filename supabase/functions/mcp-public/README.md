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

Use **https://mcp.pharmaguide.io/public**, transport **Streamable HTTP**, authentication
**None**. No account, API key, local server or PharmaGuide app installation is needed.
This connector exposes published catalog facts only. Personal connections and snapshot
sharing are not enabled; connecting this public server does not grant access to a
supplement list, medications or a health profile.

### Claude Code

```bash
claude mcp add --transport http pharmaguide_public --scope user https://mcp.pharmaguide.io/public
claude mcp get pharmaguide_public
```

Open a new Claude Code session and use `/mcp` to check the connection. Allow the
PharmaGuide read-only tools when prompted. User scope makes it available across projects.
If this server name is already configured with this URL, use that connection; do not add
another alias. Inspect an existing entry before changing it.

### Codex CLI and desktop

```bash
codex mcp add pharmaguide_public --url https://mcp.pharmaguide.io/public
codex mcp get pharmaguide_public
```

Start a new Codex chat/session after adding it. The CLI uses the user MCP configuration;
verify the same entry is enabled in the desktop app's MCP settings if using desktop.
Do not run `codex mcp login`: this public endpoint has no OAuth flow. If it is already
configured under `pharmaguide_public`, keep the existing entry instead of duplicating it.

### Claude, ChatGPT and other MCP clients

In the client's custom connector/MCP settings, enter the same public URL and choose
no authentication. Availability of custom connectors depends on the client/account.
For clients that accept an `mcpServers` configuration:

```json
{
  "mcpServers": {
    "pharmaguide_public": {
      "type": "http",
      "url": "https://mcp.pharmaguide.io/public"
    }
  }
}
```

Some clients use a different configuration format: retain the URL, Streamable HTTP
transport and no-auth setting. Directory listings are for this public server only.

### End-to-end acceptance prompt

Paste this into a new connected chat:

> Use only the PharmaGuide MCP for product facts. Search for magnesium glycinate,
> with form capsule, supplement_type single_mineral and sort quality. Report the
> catalog version and total matches. Fetch details for the first two candidates;
> verify that their declared forms match the request before comparing their published
> quality, serving basis and evidence limitations. Do not treat label variants as
> interchangeable or quality as personal suitability. Then look up barcode
> 693749006442 and fetch the returned product. Search for zzzznonexistentproductxyz
> and explain the missing result without inventing facts. State whether you can
> access my medications or personal supplement list through this connector.

Expected: the assistant actually calls the tools; no account/login prompt; catalog
versions are reported; exact full-text matches are not mixed with fuzzy alternatives
once the precision migration is deployed; barcode identity comes from the tool rather
than a hard-coded product assertion; a missing product is not evaluated; personal
access is unavailable. Product scores, match counts and versions can change with a
catalog release. Search and details must be checked together; connecting successfully
alone is not end-to-end acceptance.

### Troubleshooting

- A browser visit or HTTP GET returns 405 by design. Clients connect with JSON-RPC POST.
- Login requested: check that the URL ends in `/public` and authentication is None.
- No tools after setup: start a new chat and inspect the client's MCP connection status.
- No match: try the barcode or separate product name and brand; do not assume coverage.
- A fuzzy alternative is not an exact chemical match. Read the ingredients/forms before
  comparing. Search is not an exhaustive ingredient inventory.
- Catalog changed while paging: restart at offset 0 and use the new catalog version.
- HTTP 429: respect `Retry-After`; do not loop immediately.
- Personal/snapshot HTTP 503: those features are disabled. Reconnecting or retrying
  does not enable them. Use the public URL for product facts only.
- Public catalog unavailable: no assessment was returned; retry later, without
  substituting an invented result or interpreting the failure as no concerns.

Command references, verified October 23, 2026: [Claude Code MCP](https://code.claude.com/docs/en/mcp)
and [Codex MCP](https://developers.openai.com/codex/mcp). Installed CLI help also confirms
both commands. Client-specific UI labels may change.

## Limits

In-memory per-IP token bucket (60 requests/minute, 429 with `Retry-After`), manifest cached 60 s,
detail index cached per catalog version, mapped facts cached (200 entries). Caches and limits are per
isolate, so they bound but do not globally cap traffic.

## Comparing public products

Use `sort: "quality"` for a descending comparison of the existing exported
`quality_score_v4_100`, across the selected name-matched set before paging. The existing database search owner
selects full-text matches within the filters first; only if none exist does it return
fuzzy alternatives. This does not resolve chemical synonyms or establish ingredient identity. No score is
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

## Deploying the search/availability update

Apply pipeline migration `20261023190000_public_catalog_search_precision.sql` before
updating the public function/tool description. It replaces only the existing
`search_catalog` function; it changes no catalog rows, scores, clinical data or
permissions and requires no corpus rebuild. Then deploy the coordinated public,
personal and snapshot functions. The latter two retain containment and authenticated
snapshot deletion; this is not authorization to activate personal sharing.
Run the acceptance prompt against the deployed URL in both clients after deployment.
Local fixture acceptance does not prove that production contains the candidate.
