---
name: bron-balances-read
description: |
  Read account balances on the Bron treasury platform. Use when the user asks
  "what's in account X", "show me balances", "what's our USD position",
  "list all non-zero positions", etc. Read-only — no state changes, no
  confirmation needed. Knows how to project to specific columns, fold USD totals
  in via `--embed prices`, and pipe to jq for custom aggregations.
license: MIT
compatibility: |
  Requires bron-cli >= 0.3.6 in PATH and an active profile with API key
  authentication. The `bron mcp` subcommand exposes typed MCP tools — prefer
  those over bash CLI when the Claude Code session has the `bron` MCP server
  registered.
allowed-tools: |
  Bash(bron balances:*) Bash(bron accounts:*) Bash(bron assets:*) Bash(bron --schema:*) Read
  mcp__bron__bron_balances_list mcp__bron__bron_balances_get
  mcp__bron__bron_accounts_list mcp__bron__bron_accounts_get
  mcp__bron__bron_assets_list mcp__bron__bron_assets_get mcp__bron__bron_assets_prices
metadata:
  vendor: bronlabs
  version: "0.2.1"
  bron-cli-min: "0.3.7"
---

# Bron balances: read

Read-only skill. No state changes; safe to invoke without confirmation.

## Pick your surface — once, on the first turn

Two surfaces drive the same reads: **MCP** (typed tools `mcp__bron__bron_*`) and **CLI** (`bash bron …`). They wrap the same backend.

| Signal | Mode | Use |
|---|---|---|
| `mcp__bron__bron_balances_list` etc. listed | MCP available | Use MCP for all reads. |
| `bash which bron` returns a path | CLI available | Falls back to bash. |
| Both | Hybrid | Use MCP for reads — typed inputs, structured errors, no shell quoting. |

**Don't switch surfaces mid-session for the same workflow.** Pick once and stay there. The most common drift is: agent reads via MCP, then "for some reason" jumps to bash for a follow-up filter. That's a bug — the same MCP tool with different arguments will work. See the `bron-tx-send` skill for the full mode picker.

## Default flow — MCP

```text
mcp__bron__bron_balances_list { nonEmpty: true, limit: 100 }
```

Returns the full `Balances` envelope. Pass `embed: "prices"` to attach USD price + USD value per balance under `_embedded`:

```text
mcp__bron__bron_balances_list { nonEmpty: true, limit: 100, embed: "prices" }
```

`embed` accepts a comma-separated list of tokens — currently only `prices` is supported. The MCP server does the same CLI-side join the bash CLI does (one extra REST call to `/dictionary/asset-market-prices`).

## Default flow — CLI fallback

```bash
# Every non-empty balance in the active workspace.
bron balances list --nonEmpty true --output table

# Same, with USD price + USD value folded in (HATEOAS-style _embedded).
bron balances list --nonEmpty true --embed prices \
  --output table \
  --columns symbol,totalBalance,_embedded.usdPrice,_embedded.usdValue
```

`--embed prices` saves a follow-up `bron symbols prices` call per balance — server-side join under `_embedded`. Use it whenever the user wants USD context.

## Filters

| Filter | Use |
|---|---|
| `--accountId <id>` | balances for one account |
| `--assetId <id>` | balances for one asset (across accounts) |
| `--networkId <id>` | one network (e.g. `ETH`, `TRX`, `BTC`) |
| `--nonEmpty true` | drop zero-balance rows (almost always what you want) |
| `--limit <N>` | cap row count |

Combine freely: `bron balances list --accountId <a> --networkId ETH --nonEmpty true`.

## Output projection

`--columns` accepts dot-paths and works for every output format:

```bash
# Table view — flat columns, headers from the dot-paths.
bron balances list --output table \
  --columns accountId,symbol,totalBalance,_embedded.usdValue

# JSON projection — emit only the listed fields per item.
bron balances list --output json \
  --columns accountId,symbol,totalBalance

# JSONL for shell pipelines.
bron balances list --output jsonl --embed prices \
  --columns symbol,totalBalance,_embedded.usdValue
```

For ad-hoc aggregations, pipe JSONL through `jq`:

```bash
# Sum USD value of every non-empty balance in the workspace.
bron balances list --nonEmpty true --embed prices --output jsonl \
  | jq -s 'map(._embedded.usdValue | tonumber) | add'

# Group by symbol; sum balance per symbol.
bron balances list --nonEmpty true --output jsonl \
  | jq -s 'group_by(.symbol) | map({symbol: .[0].symbol, total: (map(.totalBalance | tonumber) | add)})'
```

Decimals stay strings end-to-end (no `float64` precision loss) — coerce with `tonumber` only when summing in `jq`.

## Discovery

```bash
bron balances list --help
bron balances list --schema       # full request + response schema as OpenAPI 3.1
bron assets list --search btc     # find an assetId by symbol or name
bron accounts list --statuses active --limit 50
```

If the user gives you an asset by symbol ("USDC", "BTC"), resolve it to `assetId` with `bron assets list --search <symbol>` first — symbols can map to multiple `assetId`s (one per network).

## Common aggregations

```bash
# All balances for one account, sorted by USD value desc.
bron balances list --accountId <a> --nonEmpty true --embed prices --output jsonl \
  | jq -s 'sort_by(-(._embedded.usdValue // "0" | tonumber)) | .[]'

# How many distinct (account, asset, network) tuples have a position.
bron balances list --nonEmpty true --output jsonl | wc -l

# Top 5 holdings by USD across the workspace.
bron balances list --nonEmpty true --embed prices --output jsonl \
  | jq -s 'sort_by(-(._embedded.usdValue // "0" | tonumber)) | .[:5]'
```

## Performance

- `bron balances list` paginates server-side — `--limit` caps the page size; use `--cursor` (returned in response) to walk if needed. For most workspaces a single page is plenty.
- `--embed prices` adds a per-call price lookup but reuses cached prices server-side; cheap.

## What this skill does NOT do

- No transaction creation. For sending funds, use `bron-tx-send`.
- No address-book operations. For routing transactions to saved recipients, use `bron-address-book`.
- No live updates. For streaming balance changes, you'd subscribe to transactions (see `bron-tx-subscribe`) and recompute — there's no public balance-stream endpoint.
