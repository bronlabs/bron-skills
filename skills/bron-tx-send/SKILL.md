---
name: bron-tx-send
description: |
  Create, approve, decline, or cancel transactions on the Bron treasury platform via
  the bron CLI. Use this skill whenever the user wants to send funds, broadcast a
  withdrawal, allowance, bridge, stake/unstake operation, or move money between
  accounts. Handles idempotency, dry-runs, confirmation prompts, and the state
  machine of a Bron transaction (signing-required → signing → signed → broadcasted →
  completed). Mandatory human-in-the-loop on every state-changing call.
license: MIT
compatibility: |
  Requires bron-cli >= 0.3.6 in PATH and an active profile with API key
  authentication (~/.config/bron/keys/*.jwk + workspace ID). See
  https://developer.bron.org/api-reference/cli/auth for setup.
allowed-tools: Bash(bron tx:*) Bash(bron config show:*) Bash(bron --help:*) Bash(bron --schema:*) Read
metadata:
  vendor: bronlabs
  version: "0.1.0"
  bron-cli-min: "0.3.6"
---

# Bron transactions: create, approve, send

This skill teaches you to drive `bron tx` safely. Bron is a non-custodial treasury management platform; every transaction goes through a state machine with explicit human approval steps. Don't try to short-circuit it.

## Decision flow

1. **What does the user actually want?** Is this a new outgoing transaction, an action on an existing one, or just a query?
   - "send X", "withdraw Y", "pay this invoice" → **create** flow.
   - "approve / decline / cancel that tx" → **action** flow on an existing transactionId.
   - "what's the status of …" → use `bron tx get <id>` or `bron tx subscribe` (see the `bron-tx-subscribe` skill).
2. **Verify pre-conditions** before creating: account exists, asset/network is supported, recipient resolves (address-book record id, internal account id, or raw address with allowlist).
3. **Always dry-run first** for any first-time pattern. `bron tx dry-run` returns expected fees, blockchain ETA, and validation errors without submitting.
4. **Always pass `--externalId`** on transaction-creation calls. Generate it from a stable identifier — task ID, hash of (intent + timestamp), `tx-$(date +%s)-$(openssl rand -hex 4)`. Bron de-duplicates by `(workspaceId, externalId)`.
5. **Surface every state-changing action to the human and wait for explicit OK** before invoking `bron tx approve / decline / cancel / sign / withdrawal / allowance / etc.`. No silent execution.

## Creating a transaction

### Discovery

```bash
bron tx --help                                # list all transaction-type subcommands
bron tx withdrawal --help                     # per-type flags & body shape
bron tx withdrawal --schema                   # machine-readable: full request + response schema
```

The CLI generates a `bron tx <type>` shortcut for every `transactionType` in the spec — `withdrawal`, `allowance`, `bridge`, `defi`, `stake-delegation`, `stake-undelegation`, `stake-claim`, `stake-withdrawal`, `address-creation`, `address-activation`, `fiat-in`, `fiat-out`, `intents`, `deposit`, `defi-message`. Each one is a thin wrapper around `bron tx create --transactionType <type>` with the type-specific body fields exposed as `--params.<field>`.

### A withdrawal, end-to-end

```bash
# 1. Generate an idempotency key. Stable across retries.
EXTID="agent-task-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"

# 2. Compose the body. Either inline flags or a JSON file (--file ./tx.json) with per-field overrides.
cat > /tmp/tx.json <<EOF
{
  "accountId":  "<accountId>",
  "externalId": "$EXTID",
  "description": "<short reason — shows up in audit log>",
  "params": {
    "amount":    "<decimal-string>",
    "assetId":   "<assetId>",
    "networkId": "<networkId>",
    "toAddressBookRecordId": "<addressBookRecordId>"
  }
}
EOF

# 3. Dry-run. Validates fees, balances, signing-policy. No state change.
bron tx dry-run --transactionType withdrawal --file /tmp/tx.json --output yaml

# 4. Show the dry-run output to the user, ask for explicit approval.
#    Wait for "yes" / "approved" / explicit OK before continuing.

# 5. Submit. Returns the transactionId; status is signing-required initially.
bron tx withdrawal --file /tmp/tx.json --output json | jq '.transactionId'
```

### Choosing a recipient field

Pick exactly one of:

| Field | When to use |
|---|---|
| `--params.toAddressBookRecordId=<id>` | Recipient is a saved address-book entry — preferred, validated by Bron. |
| `--params.toAccountId=<accountId>` | Internal transfer between Bron accounts — instant, no on-chain cost. |
| `--params.toBronTag=<tag>` | Route to another Bron workspace by tag. |
| `--params.toAddress=<rawAddress>` | Raw on-chain address. Only if it's on the workspace's allowlist; else use `toAddressBookRecordId`. |

If the user gives you a raw address, prefer to look it up in the address book first (`bron address-book list --networkIds <networkId>` — see the `bron-address-book` skill).

## Acting on existing transactions

```bash
bron tx approve  <transactionId>     # advance from waiting-approval → signing-required
bron tx decline  <transactionId>     # reject — terminal
bron tx cancel   <transactionId>     # abort — terminal (only if not yet signed)
bron tx create-signing-request <transactionId>   # request signature from the configured signers
```

Plus offer-related verbs: `accept-deposit-offer`, `reject-outgoing-offer`. See `bron tx --help` for the full list.

**These are state-changing.** Show the user what's about to happen (transaction summary: id, type, amount, asset, recipient, current status), get explicit OK, then run. If the user says "approve all the small ones", surface the full list of transactions that match before approving any.

```bash
# Pattern: bulk approval with explicit confirmation step.
bron tx list \
  --transactionStatuses waiting-approval \
  --transactionTypes withdrawal \
  --output table \
  --columns transactionId,params.amount,params.assetId,params.toAddress,description
# → show this to the user, wait for confirmation
# → for each row the user OKs:
bron tx approve <transactionId>
```

## State machine cheat-sheet

```
[create] → signing-required → waiting-approval → signing → signed → broadcasted → completed
                                             ↓                                       ↑
                                          declined / cancelled                  pending-confirmation
```

Terminal states: `completed`, `failed`, `expired`, `cancelled`, `declined`, `rejected`. Once a tx is in a terminal state, no action will move it.

For monitoring transitions, use the `bron-tx-subscribe` skill — `bron tx subscribe --no-history` streams JSONL frames as transactions move.

## Errors

CLI exit codes (stable across `0.x`):

| Exit | Meaning |
|---|---|
| `0` | success |
| `3` | unauthorized (401/403) |
| `4` | not found (404) |
| `5` | bad request (400) |
| `6` | conflict (409) — typically `EXTERNAL_ID_CONFLICT` |
| `7` | rate limited (429) |
| `8` | server error (5xx) |
| `1` | other / network / file I/O |

Error envelope (stderr):

```
Error: <message>
  code:    <STABLE_CODE>
  trace:   <correlation-id>
  details: <JSON>
```

Branch on `code`, not the human message. Common codes: `INSUFFICIENT_BALANCE`, `AMOUNT_BELOW_MIN`, `EXTERNAL_ID_CONFLICT`, `INVALID_ADDRESS`, `ADDRESS_NOT_WHITELISTED`. See [`references/error-codes.md`](references/error-codes.md).

If retrying, **reuse the same `--externalId`** — the same call returns the existing transaction, no duplicate spend.

## Hard guardrails

- Never invoke `bron tx <create|withdrawal|allowance|...|approve|decline|cancel|sign>` without surfacing the action and waiting for explicit user OK.
- Never proceed past a non-zero exit from `bron tx dry-run` — fix the validation error first.
- Never reuse an `--externalId` with a different body — it's a 409.
- Never embed JWK contents, API tokens, or `kid` values in command lines or logs.
- Never bulk-approve without showing the user the full target list first.

## Reference material

- [`references/tx-types.md`](references/tx-types.md) — body shape per `transactionType`.
- [`references/error-codes.md`](references/error-codes.md) — stable error code → cause → recovery.
- [Bron CLI docs](https://developer.bron.org/api-reference/cli) — full CLI reference.
- [Idempotency contract](https://developer.bron.org/api-reference/cli/errors#idempotency-contract).
