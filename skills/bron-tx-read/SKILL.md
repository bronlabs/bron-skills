---
name: bron-tx-read
description: |
  Read and analyse transactions on the Bron treasury platform. Use when the
  user asks "show me my last transactions", "what was the volume last week",
  "what did this swap actually trade", "find the deposit from address X",
  "summarise activity for account Y", "did this withdrawal complete?", etc.
  Read-only — no state changes, no confirmation needed. Knows the
  transaction-vs-events mental model (transactions are sagas, events carry
  real money movement) and how to drive `bron tx list` / `bron tx events`
  with `--embed events` for accurate per-asset / per-USD analysis.
  For state changes (creating, approving, cancelling) use `bron-tx-send`.
  For live streaming, use `bron-tx-subscribe`.
license: MIT
allowed-tools: |
  Bash(bron tx:*) Bash(bron accounts:*) Bash(bron assets:*) Bash(bron --schema:*) Read
  mcp__bron__bron_tx_list mcp__bron__bron_tx_get mcp__bron__bron_tx_events
  mcp__bron__bron_accounts_list mcp__bron__bron_accounts_get
  mcp__bron__bron_assets_list mcp__bron__bron_assets_get
metadata:
  vendor: bronlabs
  version: "0.2.0"
  bron-cli-min: "0.3.11"
---

# Bron transactions: read

Read-only. No state changes; safe without confirmation.

## The mental model that matters: saga vs events

A `Transaction` is a **saga** — the request the user submitted plus the state-machine that walks it to a terminal status. `params`, `transactionType`, `status`, `extra` describe *intent* and *lifecycle*.

Real money movement lives in **events** attached to the saga. Each event = one concrete blockchain transfer (or accounting entry) that actually settled. One saga → 1, 2, or N events:

| Type | Typical events | What's in them |
|---|---|---|
| `deposit` | 1 × `in` | Inbound transfer credited. `params.amount` matches the event (deposits are passive). |
| `withdrawal` | 1 × `out` + 1 × `fee` | What left + the gas fee (often a different `assetId`). |
| `swap-lifi`, `intents`, `bridge` | `out` + `in` (+ optional `fee`) | The *out* and the *in* are independent assets/networks/amounts. Different `networkId`s on `out` vs `in` ⇒ cross-chain. `params` is the *quote*, events are the *fill* (slippage included). |
| `nft-deposit`, `nft-withdrawal` | `nft-in` / `nft-out` | NFT IDs in `event.extra`, not `amount`. |
| `stake-*`, `loyalty-*`, `allowance` | type-specific events | See `bron tx events --schema` for the EventType enum. |

**Rule of thumb:** if the user is asking *what was actually transferred*, *how much was it worth*, *where did the money go*, or *which on-chain hash settled this*, look at events. If they're asking *what was attempted* / *what's the status*, the bare saga is enough. In practice "give me a summary / report / digest" means events — pass `includeEvents: true`. Don't trust `params.amount` for anything except deposits.

## Pick your surface — once

Two surfaces wrap the same backend: **MCP** (`mcp__bron__bron_tx_*`) and **CLI** (`bash bron tx …`). Pick one and stay there. `bron` is the public Homebrew CLI — don't run repo binaries from `libs/sdk/bron-cli/bin/`.

## Default flow — MCP

```text
mcp__bron__bron_tx_list { limit: 20, includeEvents: true,
                          sortBy: "activity", sortDirection: "DESC" }
```

**`includeEvents: true` is mandatory by default — set it on every `bron_tx_list` / `bron tx list` call unless the user explicitly asked for status-only / count-only.** Without it the response only carries `params` (the *quote*, see "saga vs events" above), and any number you cite — amount, symbol, USD value, on-chain hash, slippage, fee — is the request, not what actually happened. For deposits `params` happens to match the event so the answer looks correct; for `withdrawal`, `swap-lifi`, `intents`, `bridge`, `fiat-*` it silently differs. The cost of `includeEvents: true` is one already-cached server-side join — there's no reason to skip it.

`embed: "assets"` is **only useful when `includeEvents: false`** — events already carry `symbol`, `networkId`, `assetId`, so combining `includeEvents: true` with `embed: "assets"` is redundant. Pick one: `includeEvents: true` for analysis (default), `embed: "assets"` only when you need just the saga shell with resolved primary asset (rare). MCP `embed` accepts only `assets` — events go through `includeEvents`, not an `embed` token.

**Aggregate on the server with `jq`.** Read tools accept a `jq` argument (a sandboxed gojq program) and a `fields` argument (dot-path projection). On MCP there's no shell to pipe through, so push the aggregation into the call — only the result enters context, not the raw list:

```text
mcp__bron__bron_tx_list { createdAtFrom: "2026-05-01", includeEvents: true,
  jq: "[.transactions[]._embedded.events[]? | (.usdAmount // \"0\" | tonumber)] | add" }
```

New to the shape? `mcp__bron__bron_help { tool: "bron_tx_list" }` prints the response fields (wire-correct, so `_embedded.…`); `bron_help { topic: "tx-aggregation" }` prints these recipes.

For one tx in isolation:

```text
mcp__bron__bron_tx_events { transactionId: "<id>" }
```

`mcp__bron__bron_tx_get` doesn't support `includeEvents` — pair it with `bron_tx_events`.

Date filters (`createdAtFrom`, `createdAtTo`, `updatedAt*`, `terminatedAt*`) accept ISO-8601 (`2026-04-01` or `…T00:00:00Z`) and epoch millis — auto-coerced.

## CLI fallback

```bash
bron tx list --limit 20 --embed events --sortBy activity --sortDirection DESC --output json
bron tx get <id> --embed events --output json
bron tx events <id> --output json
```

`--embed events` is the CLI alias for `--includeEvents true` — same default-on rule as the MCP path: include it on every call unless the user explicitly asked for status/count only. Mixing `--embed events,assets` is redundant for the same reason as on MCP. `--sortBy` is `updated|activity` only (no `createdAt`); `--sortDirection` requires uppercase `ASC|DESC`. For everything else — flags, enums, body shapes — read `bron tx list --help` / `bron tx list --schema`.

## Common analyses

```bash
# Per-event flat stream (one event per JSONL row), with parent saga id and type.
bron tx list --limit 100 --embed events --output json \
  | jq -c '.transactions[] as $t | $t._embedded.events[]?
           | . + {_txType: $t.transactionType, _txStatus: $t.status}'

# USD volume by direction over completed txs in a window.
bron tx list --transactionStatuses completed --createdAtFrom $FROM --createdAtTo $TO \
  --embed events --limit 500 --output json \
  | jq '[.transactions[]._embedded.events[]?
         | {eventType, usd: (.usdAmount // "0" | tonumber)}]
        | group_by(.eventType)
        | map({eventType: .[0].eventType,
               total_usd: (map(.usd) | add), count: length})'

# Net USD per swap/bridge/intent (in − out − fee).
bron tx list --transactionTypes swap-lifi,intents,bridge --transactionStatuses completed \
  --embed events --limit 50 --output json \
  | jq '[.transactions[]
         | {transactionId, transactionType,
            net_usd: ([._embedded.events[]?
                       | (.usdAmount // "0" | tonumber)
                       * (if .eventType == "in" then 1
                          elif .eventType == "out" or .eventType == "fee" then -1
                          else 0 end)] | add // 0)}]'
```

`(.usdAmount // "0" | tonumber)` is the safe coercion. Don't use postfix `tonumber?` — it silently drops the whole object literal when the input is null, so a workspace with mixed priced/unpriced events shrinks invisibly. Trailing `add // 0` covers the empty-events case (non-completed sagas).

When grouping by asset, key on `assetId` not `symbol` — USDC-on-ETH and USDC-on-BASE share a symbol but are different assets.

## What `params` *does* tell you

`params` carries the user's intent and saga-level identifiers that don't appear on events:

- `externalId`, `quoteId`, `intentId` — saga identifiers (joining to client systems / DeFi solver state).
- `toAddress`, `toAccountId`, `toWorkspaceTag`, `addressBookRecordId` — where the user *asked* to send. The actual settlement address is in `event.extra.out[].address` / `event.extra.in[].address`.
- `feeLevel`, `includeFee`, `slippage` — knobs dialed before broadcast.
- `assetId`, `amount`, `networkId` — what was *requested*. For deposits these match the event; for withdrawals/swaps/bridges they're the *quote*, not the *fill*.

Report `params` when explaining *what was asked for*, events when explaining *what happened*.

## Naming things in summaries

Label destinations by human-friendly names, not raw IDs or addresses. Pull the lookup once:

```bash
bron accounts list --limit 200 --output jsonl --columns accountId,accountName,isTestnet,status
```

Then map `event.accountId → accountName`. For external recipients, prefer `params.toWorkspaceTag` (when present) or the address-book name. `→ Mainnet 001 (0x7981FE…1c08)` reads better than `→ 0x7981FE…1c08`. Mask middle of external addresses unless the user wants the full hex.

## Discovery

For full filter / status / type / event-type enums, ask the CLI directly:

```bash
bron tx list --schema     # request schema with all filters and enums
bron tx events --schema   # response schema with EventType enum
bron tx --help            # every transactionType subcommand
```

If the user gives an asset by symbol ("USDC", "BTC"), resolve to `assetId` via `bron assets list --search <symbol>` — symbols map to multiple `assetId`s (one per network).

## What this skill does NOT do

- No transaction creation / approval / decline / cancel → `bron-tx-send`.
- No live streaming → `bron-tx-subscribe`.
- No balance reads → `bron-balances-read`.
- No address-book CRUD → `bron-address-book`.
