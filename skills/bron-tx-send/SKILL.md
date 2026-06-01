---
name: bron-tx-send
description: |
  Create, approve, decline, or cancel transactions on the Bron treasury platform.
  Use whenever the user wants to send funds, broadcast a withdrawal, allowance,
  bridge, stake/unstake operation, or move money between accounts. Drives the
  Bron transaction state machine (signing-required → signing → signed →
  broadcasted → completed) end-to-end. Mandatory human-in-the-loop on every
  state-changing call. Live state via the long-poll
  `bron_tx_wait_for_state` MCP tool (universal) or `bron tx subscribe`
  + Monitor (CLI; preferred for multi-tx fan-out).
license: MIT
allowed-tools: |
  Bash(bron tx:*) Bash(bron config show:*) Bash(bron --help:*) Bash(bron --schema:*)
  Read Monitor
  mcp__bron__bron_tx_list mcp__bron__bron_tx_get mcp__bron__bron_tx_events
  mcp__bron__bron_tx_wait_for_state
  mcp__bron__bron_tx_create mcp__bron__bron_tx_dry_run mcp__bron__bron_tx_bulk_create
  mcp__bron__bron_tx_withdrawal mcp__bron__bron_tx_allowance mcp__bron__bron_tx_bridge
  mcp__bron__bron_tx_deposit mcp__bron__bron_tx_defi mcp__bron__bron_tx_defi_message
  mcp__bron__bron_tx_intents mcp__bron__bron_tx_fiat_in mcp__bron__bron_tx_fiat_out
  mcp__bron__bron_tx_stake_delegation mcp__bron__bron_tx_stake_undelegation
  mcp__bron__bron_tx_stake_claim mcp__bron__bron_tx_stake_withdrawal
  mcp__bron__bron_tx_address_creation mcp__bron__bron_tx_address_activation
  mcp__bron__bron_tx_approve mcp__bron__bron_tx_decline mcp__bron__bron_tx_cancel
  mcp__bron__bron_tx_accept_deposit_offer mcp__bron__bron_tx_reject_outgoing_offer
  mcp__bron__bron_accounts_list mcp__bron__bron_accounts_get
  mcp__bron__bron_balances_list mcp__bron__bron_address_book_list
metadata:
  vendor: bronlabs
  version: "0.3.0"
  bron-cli-min: "0.3.7"
---

# Bron transactions: create, approve, send

Bron is a non-custodial treasury platform; every transaction is a saga that walks `signing-required → signing → signed → broadcasted → completed` (with optional `waiting-approval` and various failure terminals). State changes require explicit human OK every time — don't try to short-circuit the loop.

## Pick your surface — once, on the first turn

Two surfaces wrap the same backend: **MCP** (typed `mcp__bron__bron_*`) and **CLI** (`bash bron …`). Pick one and stay there for the whole session — switching mid-flow is the most common cause of double-driving a transaction.

| Probe | Mode |
|---|---|
| `mcp__bron__bron_workspace_info {}` succeeds | MCP available |
| `bash which bron` returns a path | CLI available |
| Both | **Hybrid** — use MCP for everything except multi-tx subscribe (CLI only) |

`bron` is the public Homebrew CLI. Don't run repo-bundled binaries from `libs/sdk/bron-cli/bin/`.

For **every command** — the canonical body, flags, and enums come from `bron <verb> --help` / `bron <verb> --schema` (or the typed MCP descriptor). Trust those over anything written here.

## Live state — pick the right primitive

| Workflow | Primitive |
|---|---|
| One tx, await terminal | `mcp__bron__bron_tx_wait_for_state` (every mode) |
| One tx, surface every milestone | `wait_for_state` chained with narrowing `expectedStates` |
| Many tx in parallel / batch / "watch the workspace" | `bron tx subscribe` + `Monitor` (CLI required) |

`wait_for_state` is a long-poll: it subscribes via WebSocket scoped to one tx and returns the moment status enters `expectedStates`, or returns `matched: false` with a `retryHint` on timeout (~30s). One round trip per wait, no `ScheduleWakeup` loop. See the **`bron-tx-subscribe`** skill for the multi-tx subscribe pattern.

**Never poll `bron_tx_get` in a loop** — it costs tokens and burns cache for no reason. The wait/subscribe primitives exist exactly to avoid this.

## Walkthrough — withdrawal

```text
# 1. Dry-run.
mcp__bron__bron_tx_dry_run {
  transactionType: "withdrawal",
  accountId: "<sourceAccountId>",
  externalId: "agent-task-2026-05-01-1430-a4b5",
  description: "Quarterly vendor payout",
  body: { params: {
    amount:    "100",
    assetId:   "<assetId>",
    networkId: "ETH",
    toAddressBookRecordId: "<recordId>",
    feeLevel:  "medium"
  } }
}

# 2. Surface to user → wait for explicit OK.
#    Show: type, amount, asset, source account name, recipient label,
#    estimated fee, total USD impact.

# 3. Submit with the SAME externalId.
mcp__bron__bron_tx_withdrawal {
  accountId: "<sourceAccountId>",
  externalId: "agent-task-2026-05-01-1430-a4b5",
  amount: "100", assetId: "<assetId>", networkId: "ETH",
  toAddressBookRecordId: "<recordId>",
  feeLevel: "medium"
}

# 4. Wait for terminal (or chain narrowing waits to surface every step).
mcp__bron__bron_tx_wait_for_state {
  transactionId: "<id>",
  expectedStates: ["completed","canceled","expired","error",
                   "failed-on-blockchain","removed-from-blockchain"],
  timeoutSec: 30
}
```

CLI fallback. Both `bron tx <type>` and `bron tx dry-run <type>` accept flat `--params.<field>=<value>` flags — symmetric pair, same flag set, same body shape. Use them with the same `externalId` so the dry-run pre-flight and the real submit are idempotent retries of the same logical operation.

```bash
EXT="agent-task-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
bron tx dry-run withdrawal --externalId "$EXT" --accountId "…" --params.amount=100 --params.assetId=… --params.networkId=ETH --params.toAddressBookRecordId=… --output yaml
# → surface to user, wait for OK
bron tx withdrawal --externalId "$EXT" --accountId "…" --params.amount=100 --params.assetId=… --params.networkId=ETH --params.toAddressBookRecordId=…
```

For a custom body, `--file <path>` and `--json '<json>'` work on both as baseline overlays (you can mix: pass a baseline JSON and override individual fields with `--params.*`). The legacy `bron tx dry-run --transactionType <type> --json '...'` form (no subcommand) still works for arbitrary bodies.

Live state in CLI-only mode: `bron tx subscribe --transactionId <id>` follows one tx; for batches drop the filter and consume the workspace-wide stream. Filters mirror `bron tx list`.

`bron tx <type> --help` and `bron tx dry-run <type> --help` list the per-type `--params.*` flags. `--schema` returns the typed body.

## Hard rules

- **Always `externalId`** on creation — Bron de-duplicates by `(workspaceId, externalId)`. Generate from a stable identifier (task id, hash of intent + timestamp, `tx-$(date +%s)-$(openssl rand -hex 4)`). Reuse the *same* id when retrying after a transient failure — same body returns the same tx, no double-spend. Different body with same id → 409 `already-exists`.
- **Always dry-run first** for any first-time pattern. Returns expected fees, ETA, balance impact, validation errors without submitting.
- **Always surface before state changes.** Create / approve / decline / cancel — show the user what's about to happen, wait for explicit OK. No silent execution. No bulk approval without showing the full target list first.
- **Never call `create-signing-request`** (CLI: `bron tx create-signing-request`, MCP: `bron_tx_create_signing_request`). Even if the tx sits in `signing-required`. See the dedicated section below — signing is owned by frontend / hot-wallet signer, not by CLI/SDK consumers.
- **Never embed JWK / API tokens / `kid` values** in command lines or logs.

## Choosing a recipient field

Pick exactly one:

| Field | When |
|---|---|
| `toAddressBookRecordId` | Saved address-book entry — preferred, validated by Bron. |
| `toAccountId` | Internal transfer between two Bron accounts in the same workspace. |
| `toWorkspaceTag` | Route to another Bron workspace by tag. |
| `toAddress` | Raw on-chain address — only if the workspace allowlist permits. |

If the user gives a raw address, look it up in the address book first (`bron-address-book` skill).

## Acting on existing transactions

```text
mcp__bron__bron_tx_approve  { transactionId: "<id>" }
mcp__bron__bron_tx_decline  { transactionId: "<id>", reason: "<reason>" }
mcp__bron__bron_tx_cancel   { transactionId: "<id>", reason: "<reason>" }
```

Plus offer-related verbs: `bron_tx_accept_deposit_offer`, `bron_tx_reject_outgoing_offer`. Full list: `bron tx --help`.

## Signing happens by itself — never trigger it

Once you've created a transaction and the user has approved it (when approval is required), **don't do anything else**. Don't poll, don't "kick" it, and in particular **never call `bron_tx_create_signing_request` / `bron tx create-signing-request`** — even if `bron tx --help` lists it and even if the tx sits in `signing-required` for a while.

Signing happens through one of two channels, neither of which goes through CLI/MCP/SDK:

1. **User-driven (the common case).** The user taps "Sign" in the Bron mobile or desktop app. That action creates the signing request, opens the MPC signing session, and the app broadcasts the signed tx to the chain. CLI/SDK consumers never hold the signing material — the user's device does.
2. **Hot Wallet Signer (rare, opt-in).** A workspace can run a dedicated Docker container with the MPC signer; it subscribes via WebSocket to every `signing-required` tx for accounts it has access to and signs them automatically.

After your `tx_<type>` call returns, just wait — `bron_tx_wait_for_state` (or `bron tx subscribe` for batches). The state machine drives itself: `signing-required → signing → signed → broadcasted → completed` happens without your help. A tx stuck in `signing-required` is **not yours to fix** — either the user hasn't tapped Sign yet, or no Hot Wallet Signer is configured for that account. Surface the situation to the user, don't poke the API.

Calling `create-signing-request` from an agent context either fails with `signing-request-conflict` (the real signer already created it) or creates an orphan request nothing can fulfil.

Same rule for incoming offers: don't auto-accept — surface and confirm.

## Errors

Errors carry a stable kebab-case `error` field on the response envelope (e.g. `already-exists`, `invalid-address`, `no-funds`, `invalid-new-status`, `missing-permission`, `key-not-found`, `signing-request-conflict`, `only-address-book-withdrawals-enabled`). **Pattern-match on this code, not the human message.** There is no centralised enum — codes are inline at the throw sites in service handlers, and the surface evolves; treat the response as the source of truth and read `details` for machine-readable context (`min`, `max`, `provided`).

CLI fallback exit codes (stable across `0.x`): `0` ok, `3` 401/403, `4` 404, `5` 400/422, `6` 409 (typically `already-exists` from externalId reuse), `7` 429, `8` 5xx, `1` other (network / file I/O).

For transient codes (5xx, 429): retry with the same `externalId`. For business-logic codes (`no-funds`, `only-address-book-withdrawals-enabled`): surface the situation to the user with `details`, don't silently fix-and-retry.

Quote `requestId` (MCP) / `id:` (CLI) when escalating — it joins your call across every backend service log.

## Discovery

```bash
bron tx --help              # every transactionType subcommand
bron tx <type> --help       # type-specific --params.* flags
bron tx <type> --schema     # typed body + response schema (OpenAPI fragment)
bron --schema               # whole CLI as one OpenAPI 3.1 doc
```

## Related skills

- **`bron-tx-read`** — read-only analysis (saga vs events, jq aggregations).
- **`bron-tx-subscribe`** — workspace-wide live stream + Monitor patterns.
- **`bron-balances-read`** — pre-flight balance checks.
- **`bron-address-book`** — saved addresses, `toAddressBookRecordId`.
