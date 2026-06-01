---
name: bron-balances-read
description: |
  Read account balances on the Bron treasury platform. Use when the user asks
  "what's in account X", "show me balances", "what's our USD position",
  "list all non-zero positions", etc. Read-only — no state changes, no
  confirmation needed. Knows how to project to specific columns, fold USD totals
  in via `--embed prices`, and pipe to jq for custom aggregations.
license: MIT
allowed-tools: |
  Bash(bron balances:*) Bash(bron accounts:*) Bash(bron assets:*) Bash(bron --schema:*) Read
  mcp__bron__bron_balances_list mcp__bron__bron_balances_get
  mcp__bron__bron_accounts_list mcp__bron__bron_accounts_get
  mcp__bron__bron_assets_list mcp__bron__bron_assets_get mcp__bron__bron_assets_prices
metadata:
  vendor: bronlabs
  version: "0.4.0"
  bron-cli-min: "0.3.11"
---

# Bron balances: read

Read-only. No state changes; safe without confirmation.

Two surfaces wrap the same backend: MCP (`mcp__bron__bron_balances_*`) and CLI (`bron balances …`). Pick one and stay there. See the `bron-tx-send` skill for the surface-picker rationale.

## Default flow

```text
mcp__bron__bron_balances_list { nonEmpty: true, embed: "prices" }
```

```bash
bron balances list --nonEmpty true --embed prices --output jsonl \
  --columns accountId,symbol,networkId,totalBalance,_embedded.usdPrice,_embedded.usdValue
```

`--embed prices` (CLI) / `embed: "prices"` (MCP) attaches USD price + USD value per balance under `_embedded`. Decimals stay strings end-to-end — coerce with `tonumber` only when summing.

`--nonEmpty true` is almost always what you want.

For full filter set, body, and response shape: `bron balances list --help` / `bron balances list --schema`.

## Aggregations

```bash
# Sum USD value of every non-empty priced balance.
bron balances list --nonEmpty true --embed prices --output jsonl \
  | jq -s 'map(._embedded.usdValue // "0" | tonumber) | add'

# Group by symbol; sum balance per symbol.
bron balances list --nonEmpty true --output jsonl \
  | jq -s 'group_by(.symbol)
           | map({symbol: .[0].symbol,
                  total: (map(.totalBalance // "0" | tonumber) | add)})'

# Top 5 holdings by USD across the workspace.
bron balances list --nonEmpty true --embed prices --output jsonl \
  | jq -s 'sort_by(-(._embedded.usdValue // "0" | tonumber)) | .[:5]'
```

**`tonumber?` footgun.** The postfix `?` (jq error suppression) silently drops the whole object literal when applied to a null/non-numeric input — you lose rows without any sign of it. Use `(.path // "0" | tonumber)` for null-safe coercion. A workspace with mixed priced/unpriced balances aggregated through `tonumber?` will silently shrink to whatever subset has prices.

On the MCP surface, push the aggregation server-side with the `jq` tool argument instead of piping — only the total returns into context: `mcp__bron__bron_balances_list { nonEmpty: true, embed: "prices", jq: "[.balances[]._embedded.usdValue // \"0\" | tonumber] | add" }`. The same null-safe coercion applies.

When grouping for a portfolio view, key on `assetId` not `symbol` — USDC-on-ETH and USDC-on-BASE share a symbol but are different assets.

## Symbol lookup

If the user gives an asset by symbol ("USDC", "BTC"), resolve to `assetId` first:

```bash
bron assets list --search <symbol>
```

A single symbol can map to multiple `assetId`s (one per network).

## Discovery

```bash
bron balances list --help
bron balances list --schema
bron --schema             # whole CLI as one OpenAPI 3.1 doc
```

## What this skill does NOT do

- No transaction creation → `bron-tx-send`.
- No address-book CRUD → `bron-address-book`.
- No live balance stream — there's no public balance-stream endpoint. Subscribe to transactions (`bron-tx-subscribe`) and recompute if you need that.
