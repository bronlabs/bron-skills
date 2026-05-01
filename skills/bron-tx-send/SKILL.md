---
name: bron-tx-send
description: |
  Create, approve, decline, or cancel transactions on the Bron treasury platform.
  Use whenever the user wants to send funds, broadcast a withdrawal, allowance,
  bridge, stake/unstake operation, or move money between accounts. Drives the
  Bron transaction state machine (signing-required → signing → signed →
  broadcasted → completed) end-to-end. Mandatory human-in-the-loop on every
  state-changing call. Live state visibility via the long-poll
  `bron_tx_wait_for_state` MCP tool (universal) or `bron tx subscribe`
  + Monitor (CLI; preferred for multi-tx fan-out).
license: MIT
compatibility: |
  Works in three environments — pure-CLI, MCP-only, or CLI+MCP. At least one of:
  (a) bron-cli >= 0.3.7 in PATH with an active profile + API key, OR (b) a
  registered MCP server named `bron` (either `bron mcp` from bron-cli or the
  Bron Desktop bundled MCP). The skill detects which surfaces are available
  and pins its commands to one of them — see "Pick your surface" below.
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
  mcp__bron__bron_tx_create_signing_request
  mcp__bron__bron_tx_accept_deposit_offer mcp__bron__bron_tx_reject_outgoing_offer
  mcp__bron__bron_accounts_list mcp__bron__bron_accounts_get
  mcp__bron__bron_balances_list mcp__bron__bron_address_book_list
metadata:
  vendor: bronlabs
  version: "0.2.1"
  bron-cli-min: "0.3.7"
---

# Bron transactions: create, approve, send

This skill drives `bron tx` safely. Bron is a non-custodial treasury management platform; every transaction goes through a state machine with explicit human approval steps. Don't try to short-circuit it.

## Pick your surface — once, on the first turn

The same operations are reachable through two surfaces: **MCP** (typed tools `mcp__bron__bron_*`) and **CLI** (bash `bron tx <verb>`). They wrap the same backend; behaviour matches end-to-end including ISO 8601 ↔ epoch-millis date coercion. **Pick one and stay there for the whole session** — switching mid-flow is the most common cause of agents getting confused and accidentally double-driving a transaction.

Detect the available surfaces at the start, then commit:

| Signal | Mode | Use for |
|---|---|---|
| `mcp__bron__bron_tx_*` tools listed in this session | **MCP available** | All read + write + state-change calls. |
| `bash: which bron` returns a path AND `bron --version` works | **CLI available** | Same set — and the streaming primitive (`bron tx subscribe`). |

Three concrete modes:

**Mode M — MCP only** (e.g. only Bron Desktop MCP installed, no CLI):
- Use `mcp__bron__bron_*` for everything. Never call `bash bron …` — `bron` won't be in PATH.
- Live state visibility: `mcp__bron__bron_tx_wait_for_state` — long-poll tool that subscribes via WebSocket scoped to one transaction and returns when it enters one of `expectedStates` (or on timeout, with a continuation hint to call again). One round trip per ~30s wait, no `ScheduleWakeup` loop.

**Mode C — CLI only** (no MCP server registered):
- Use `bash bron …` for everything.
- Single-tx wait: there's no MCP, so use `bron tx subscribe --no-history` + `Monitor` on the bash process — see the `bron-tx-subscribe` skill.

**Mode H — hybrid CLI + MCP** (both available):
- Use `mcp__bron__bron_*` for all data operations (typed inputs, structured errors, no shell quoting).
- **Single-tx wait**: prefer `mcp__bron__bron_tx_wait_for_state` — one tool call, no bash process, works the same way the user's other MCP servers do.
- **Multi-tx fan-out / dashboard / "watch the whole workspace for the next N minutes"**: drop to bash for `bron tx subscribe …` → `Monitor`. The subscribe stream wakes the agent on every workspace transition, ideal for batch operations or operator-style sessions.
- Don't randomly mix — if you started a flow with MCP for one tx, finish with MCP. CLI is reserved for the workspace-wide subscribe lane.

If you can't tell which mode you're in, run a one-shot probe: try `mcp__bron__bron_workspace_info {}`. If it succeeds you have MCP. Then `bash which bron` to see if CLI is also there. Cache the result for the rest of the session — don't re-probe before every call.

## Step 0 — pick the live-state primitive that fits the workflow

Bron transactions move through up to 7 statuses over ~30–60 seconds (longer for bridges and on-chain withdrawals). The user wants to see the transitions, not just the final result. Two primitives, pick by workflow shape:

### Single-tx flow ("submit one tx, watch it through to completion") — `bron_tx_wait_for_state`

Default for any "send X to Y" / "approve this tx" request. Available in **all modes** (M, C, H). After submit, call:

```text
mcp__bron__bron_tx_wait_for_state {
  transactionId: "<id>",
  expectedStates: ["completed","canceled","expired","error","failed-on-blockchain","removed-from-blockchain"],
  timeoutSec: 30
}
```

The tool subscribes via WebSocket scoped to that one transaction and returns the moment the status enters `expectedStates`. On timeout it returns the current status with `retryHint: "Call bron_tx_wait_for_state again …"` — call it again to keep waiting. One round trip per ~30s wait, no `ScheduleWakeup` loop, works in every MCP client.

If you also want to surface intermediate transitions to the user, narrow `expectedStates` step-by-step:

```text
# Wake on the next milestone, then again on the next, then on terminal.
expectedStates: ["signed","broadcasted","completed","failed-on-blockchain","error","canceled","expired"]
# … then on next call:
expectedStates: ["broadcasted","completed","failed-on-blockchain","error","canceled","expired"]
# … then:
expectedStates: ["completed","failed-on-blockchain","error","canceled","expired"]
```

Each call returns a typed `transaction` object with the live status — surface the transition to the user before issuing the next wait.

In Mode C (no MCP), the equivalent is `bron tx subscribe --no-history --transactionId <id>` + `Monitor`. See the `bron-tx-subscribe` skill.

### Multi-tx fan-out / dashboard / operator session — `bron tx subscribe` (CLI only)

When the workflow is "approve a batch of 30 pending tx and watch them all complete", "spend the next ten minutes watching the whole workspace", or "every deposit triggers a follow-up trade" — open a workspace-wide subscription instead of one wait-for-state per tx.

Only Mode H or C (CLI in PATH) supports this primitive today. In Mode M, fall back to running multiple `bron_tx_wait_for_state` calls (sequentially or in parallel via separate Agent invocations).

```text
1. Bash run_in_background
   command: bron tx subscribe --no-history --output jsonl > /tmp/bron-tx-stream.log 2>&1
   description: "Workspace-wide tx subscription for live state visibility"
   → capture bash_id

2. Monitor { bash_id: <captured> }
   → wakes you on every state transition for the rest of the session
```

See the **`bron-tx-subscribe`** skill for reconnect semantics, filter options, and Monitor patterns.

### Decision rule

| Workflow | Use |
|---|---|
| One tx, await terminal | `bron_tx_wait_for_state` (every mode) |
| One tx, surface every milestone | `bron_tx_wait_for_state` chained with narrowing `expectedStates` |
| Many tx in parallel, batch monitoring | `bron tx subscribe` + `Monitor` (Mode H/C) |
| Operator dashboard / workspace-wide | `bron tx subscribe` + `Monitor` (Mode H/C) |
| MCP-only + many tx | One `bron_tx_wait_for_state` per tx, in parallel via Agent |

## Decision flow

1. **What does the user actually want?**
   - "send X", "withdraw Y", "pay this invoice", "move from A to B" → **create** flow.
   - "approve / decline / cancel that tx" → **action** flow on an existing transactionId.
   - "what's the status of …" → if subscription is already running, the answer is in the stream; otherwise `mcp__bron__bron_tx_get` or see `bron-tx-subscribe`.
2. **Verify pre-conditions** before creating: account exists (`mcp__bron__bron_accounts_list`), asset/network is supported, recipient resolves (address-book record id, internal account id, or raw address).
3. **Always dry-run first** for any first-time pattern. Dry-run returns expected fees, blockchain ETA, balance impact, and validation errors without submitting.
4. **Always pass `externalId`** on transaction-creation calls. Generate it from a stable identifier — task ID, hash of (intent + timestamp), `tx-$(date +%s)-$(openssl rand -hex 4)`. Bron de-duplicates by `(workspaceId, externalId)`.
5. **Surface every state-changing action to the human and wait for explicit OK** before invoking any create / approve / decline / cancel call. No silent execution.

## Two ways to drive the same flow

The `bron mcp` subcommand exposes typed MCP tools that mirror every CLI verb. **Prefer MCP when available** — the agent gets typed inputs, structured error envelopes (`{code, status, trace, message}`), and one less context switch into bash. Fall back to CLI when running under an agent that doesn't speak MCP.

Same call, two surfaces:

| Action | MCP tool | CLI equivalent |
|---|---|---|
| Dry-run a withdrawal | `mcp__bron__bron_tx_dry_run` | `bron tx dry-run --transactionType withdrawal …` |
| Submit a withdrawal | `mcp__bron__bron_tx_withdrawal` | `bron tx withdrawal …` |
| Approve | `mcp__bron__bron_tx_approve` | `bron tx approve <id>` |
| Decline | `mcp__bron__bron_tx_decline` | `bron tx decline <id>` |
| Cancel | `mcp__bron__bron_tx_cancel` | `bron tx cancel <id>` |
| Get one tx | `mcp__bron__bron_tx_get` | `bron tx get <id>` |
| Wait for terminal status | `mcp__bron__bron_tx_wait_for_state` | `bron tx subscribe --transactionId <id>` (CLI streams; no built-in early exit) |
| Create signing request | `mcp__bron__bron_tx_create_signing_request` | `bron tx create-signing-request <id>` |

The full table is auto-generated from the OpenAPI spec; every `bron <resource> <verb>` has a matching `mcp__bron__bron_<resource>_<verb>` tool. Date fields (createdAt, expiresAt, terminatedAtFrom, …) accept ISO 8601 *and* epoch millis on both surfaces — coercion happens client-side.

## Creating a transaction — MCP-first walkthrough

End-to-end withdrawal with subscription, dry-run, submit, and live state observation.

### 1. (already chosen in Step 0) Live-state primitive picked — `wait_for_state` for single-tx, subscribe + Monitor for multi-tx.

### 2. Compose payload via the typed shortcut

The `bron_tx_<type>` shortcuts mirror `bron tx <type>` and take flat inputs — no `/tmp/tx.json` needed. For a withdrawal between two internal accounts:

```text
mcp__bron__bron_tx_dry_run {
  transactionType: "withdrawal",
  accountId: "<sourceAccountId>",
  externalId: "agent-task-2026-05-01-1430-a4b5",
  description: "Quarterly vendor payout",
  body: {
    params: {
      amount:    "100",
      assetId:   "<assetId>",
      networkId: "ETH",
      toAddressBookRecordId: "<recordId>",
      feeLevel:  "medium"
    }
  }
}
```

`body` is the typed body baseline; the SDK merges it with the flat top-level fields you pass alongside. You can also use `bron_tx_withdrawal` directly with flat `accountId / amount / assetId / networkId / toAddressBookRecordId / feeLevel` fields — same wire payload, less indentation.

The dry-run response contains `estimations[]` (one entry per leg + one per fee), `extra.fromAddress / toAddress` (resolved on-chain addresses for context), and any validation errors as a structured envelope.

### 3. Show the dry-run summary to the user, wait for OK

What to surface:
- transactionType + amount + asset + symbol
- source account name (resolve via `mcp__bron__bron_accounts_get` if you only have the id) and its on-chain address from `extra.fromAddress`
- recipient — for `toAccountId` say "Account X (<accountName>) — internal transfer"; for `toAddressBookRecordId` say "Address Book entry: <name>"; for raw `toAddress` say the address verbatim
- estimated fee (sum of `eventType=fee` rows in `estimations`)
- estimated USD value of the transfer + fee

Wait for explicit OK. Never proceed on ambiguous yes-flavoured language ("ok cool" without "send", "go ahead" without scope).

### 4. Submit via the same shortcut

```text
mcp__bron__bron_tx_withdrawal {
  accountId: "<sourceAccountId>",
  externalId: "agent-task-2026-05-01-1430-a4b5",
  description: "Quarterly vendor payout",
  amount: "100",
  assetId: "<assetId>",
  networkId: "ETH",
  toAddressBookRecordId: "<recordId>",
  feeLevel: "medium"
}
```

Returns the full transaction. Pluck `.transactionId` and `.status` (initially `signing-required`).

### 5. Wait for the next milestone — `bron_tx_wait_for_state`

After submit, immediately follow up with one or more wait calls. The simplest pattern is "wake on terminal":

```text
mcp__bron__bron_tx_wait_for_state {
  transactionId: "<id>",
  expectedStates: ["completed","canceled","expired","error","failed-on-blockchain","removed-from-blockchain"],
  timeoutSec: 30
}
```

If `matched: true` — surface terminal state to the user. If `matched: false` (timeout), `currentState` is the latest status — surface intermediate progress, then call again with the same args to keep waiting.

If you want to surface every milestone, chain narrowing waits:

| After submit, status is | Call wait_for_state with expectedStates |
|---|---|
| `signing-required` | `["signing","signed","broadcasted","completed","error","failed-on-blockchain","canceled","expired"]` — wakes on the next forward step or terminal |
| `signing` | `["signed","broadcasted","completed","error","failed-on-blockchain","canceled","expired"]` |
| `signed` | `["broadcasted","completed","error","failed-on-blockchain","canceled","expired"]` |
| `broadcasted` | `["completed","error","failed-on-blockchain","canceled","expired"]` |

State narrative to surface to the user:

- `signing-required` → "submitted, awaiting signers"
- `waiting-approval` → "approval queued"
- `signing` → "signers in progress"
- `signed` → "signature set assembled, broadcasting"
- `broadcasted` → "on-chain, awaiting confirmations"
- `completed` → "confirmed — done" (or `failed | expired | cancelled` for non-happy paths)

When you reach a terminal state, summarise: tx id, on-chain hash (from `extra.blockchainDetails[0].blockchainTxId`), final balance impact.

For multi-tx batch flows (Mode H/C), use the workspace-wide subscribe + Monitor pattern instead — see Step 0 and the `bron-tx-subscribe` skill.

### 6. CLI fallback (when MCP isn't registered)

```bash
EXTID="agent-task-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"

bron tx dry-run --transactionType withdrawal \
  --accountId <sourceAccountId> \
  --externalId "$EXTID" \
  --params.amount=100 \
  --params.assetId=<assetId> \
  --params.networkId=ETH \
  --params.toAddressBookRecordId=<recordId> \
  --params.feeLevel=medium \
  --output yaml

# After OK:
bron tx withdrawal \
  --accountId <sourceAccountId> \
  --externalId "$EXTID" \
  --params.amount=100 \
  --params.assetId=<assetId> \
  --params.networkId=ETH \
  --params.toAddressBookRecordId=<recordId> \
  --params.feeLevel=medium \
  --output json
```

Same flow, no `/tmp/tx.json` heredoc needed — every shortcut takes flat `--params.*` flags. Use `--file ./tx.json --params.amount=...` only when you have a baseline JSON you want to overlay.

## Choosing a recipient field

Pick exactly one of:

| Field | When to use |
|---|---|
| `toAddressBookRecordId` | Recipient is a saved address-book entry — preferred, validated by Bron. |
| `toAccountId` | Internal transfer between Bron accounts — instant, no on-chain cost (well, on-chain when the accounts are different vault accounts; check the dry-run). |
| `toBronTag` | Route to another Bron workspace by tag. |
| `toAddress` | Raw on-chain address. Only if it's on the workspace's allowlist; else use `toAddressBookRecordId`. |

If the user gives you a raw address, prefer to look it up in the address book first (`mcp__bron__bron_address_book_list { networkIds: "ETH" }` — see the `bron-address-book` skill).

## Acting on existing transactions

```text
mcp__bron__bron_tx_approve  { transactionId: "<id>" }
mcp__bron__bron_tx_decline  { transactionId: "<id>", reason: "<reason>" }
mcp__bron__bron_tx_cancel   { transactionId: "<id>", reason: "<reason>" }
mcp__bron__bron_tx_create_signing_request { transactionId: "<id>" }
```

Plus offer-related verbs: `bron_tx_accept_deposit_offer`, `bron_tx_reject_outgoing_offer`. See `bron tx --help` for the full list.

**These are state-changing.** Show the user what's about to happen (transaction summary: id, type, amount, asset, recipient, current status), get explicit OK, then run.

```text
# Pattern: bulk approval with explicit confirmation step.
mcp__bron__bron_tx_list {
  transactionStatuses: "waiting-approval",
  transactionTypes:    "withdrawal"
}
# → render a table of (transactionId, amount, asset, recipient, description),
#   show to the user, wait for confirmation
# → for each row the user OKs:
mcp__bron__bron_tx_approve { transactionId: "<id>" }
```

If the user says "approve all the small ones", surface the full list of transactions that match before approving any, **then** approve them one by one.

## State machine cheat-sheet

```
[create] → signing-required → waiting-approval → signing → signed → broadcasted → completed
                                             ↓                                       ↑
                                          declined / cancelled                  pending-confirmation
```

Terminal states: `completed`, `failed`, `expired`, `cancelled`, `declined`, `rejected`. Once a tx is in a terminal state, no action will move it.

For monitoring transitions live, prefer `bron_tx_wait_for_state` (single-tx) or `bron tx subscribe` + Monitor (multi-tx). Don't poll `bron_tx_get` in a loop — it costs tokens and burns the cache for no reason.

## Errors

MCP error envelope (returned as `isError: true` with structured payload):

```json
{
  "error": "<human-readable message>",
  "status": <http-status>,
  "code":  "<STABLE_CODE>",
  "trace": "<correlation-id>"
}
```

CLI fallback exit codes (stable across `0.x`):

| Exit | Meaning |
|---|---|
| `0` | success |
| `3` | unauthorized (401/403) |
| `4` | not found (404) |
| `5` | bad request (400/422) |
| `6` | conflict (409) — typically `EXTERNAL_ID_CONFLICT` |
| `7` | rate limited (429) |
| `8` | server error (5xx) |
| `1` | other / network / file I/O |

Branch on `code`, not the human message. Common codes: `INSUFFICIENT_BALANCE`, `AMOUNT_BELOW_MIN`, `EXTERNAL_ID_CONFLICT`, `INVALID_ADDRESS`, `ADDRESS_NOT_WHITELISTED`. See [`references/error-codes.md`](references/error-codes.md).

If retrying, **reuse the same `externalId`** — the same call returns the existing transaction, no duplicate spend.

## Hard guardrails

- Never invoke any create / approve / decline / cancel tool without surfacing the action and waiting for explicit user OK.
- Never proceed past a non-zero exit / `isError: true` from a dry-run — fix the validation error first.
- Never reuse an `externalId` with a different body — it's a 409.
- Never embed JWK contents, API tokens, or `kid` values in command lines or logs.
- Never bulk-approve without showing the user the full target list first.
- Never poll `bron_tx_get` in a wait loop. Use `bron_tx_wait_for_state` (single-tx) or `bron tx subscribe` + Monitor (multi-tx) instead — the former blocks server-side until the state matches, the latter pushes every transition.

## Reference material

- [`references/tx-types.md`](references/tx-types.md) — body shape per `transactionType`.
- [`references/error-codes.md`](references/error-codes.md) — stable error code → cause → recovery.
- [`bron-tx-subscribe`](../bron-tx-subscribe/SKILL.md) — full subscription + Monitor reference.
- [Bron CLI docs](https://developer.bron.org/api-reference/cli) — full CLI reference.
- [Idempotency contract](https://developer.bron.org/api-reference/cli/errors#idempotency-contract).
