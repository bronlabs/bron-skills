---
name: bron-tx-subscribe
description: |
  Stream live transaction updates from the Bron treasury platform over WebSocket.
  Use when the user wants to "watch" transactions, react to status changes, build
  a live dashboard, or wait for a specific transaction to complete. Same filters as
  `bron tx list`; emits JSONL on stdout. Read-only, transparent auto-reconnect, no
  state changes.
license: MIT
compatibility: |
  Requires bron-cli >= 0.3.6 in PATH and an active profile with API key
  authentication. The CLI's WebSocket transport handles auto-reconnect via the
  bron-sdk-go realtime package — no extra setup needed.
allowed-tools: Bash(bron tx subscribe:*) Bash(bron tx:*) Bash(bron --schema:*) Read
metadata:
  vendor: bronlabs
  version: "0.1.0"
  bron-cli-min: "0.3.6"
---

# Bron live transaction stream

`bron tx subscribe` opens a long-lived WebSocket and prints transaction updates as JSONL on stdout. Same filters as `bron tx list`. Read-only — no state changes. Auto-reconnect on idle/network drops is built in; you don't have to wrap it in a retry loop.

## Mental model: GET extended

A subscription is "GET extended": same query as `bron tx list`, the server replays the historical match as the **first frame**, then keeps the connection open and pushes each subsequent change as another frame. Output is always JSONL — pipe to `jq`.

```bash
bron tx subscribe --transactionStatuses signing-required,waiting-approval
```

You'll see:
1. A snapshot frame for every currently-matching transaction (could be 0, could be 100s).
2. One frame per state transition after that, indefinitely.

For long-running watchers, the snapshot is usually noise — pass `--no-history` to skip it.

## Skipping the snapshot

```bash
bron tx subscribe --no-history --transactionStatuses signing-required
```

This sends `limit=0` to the server: snapshot is empty, live stream starts fresh.

## Filters

| Flag | Use |
|---|---|
| `--transactionStatuses <list>` | comma-separated statuses (`signing-required,signed,broadcasted,…`) |
| `--transactionTypes <list>` | comma-separated types (`withdrawal,bridge,allowance,…`) |
| `--accountId <id>` | scope to one source account |
| `--no-history` | skip the initial snapshot |

Filters apply to **both** the snapshot and the live stream — once subscribed, the server only pushes updates that match.

## Recipes

### Tail every signed transaction

```bash
bron tx subscribe --no-history \
  | jq -r 'select(.status == "signed") | "\(.transactionId) \(.transactionType) \(.params.amount)"'
```

### Auto-approve incoming withdrawals matching a rule

This is the "agent flow" pattern — but **only run after explicit user confirmation of the rule**. Don't write something that auto-approves without human-in-the-loop unless the user has explicitly authorised it.

```bash
bron tx subscribe --no-history \
  --transactionStatuses signing-required \
  --transactionTypes withdrawal \
  | jq -rc '.' \
  | while read -r tx; do
      ID=$(echo "$tx" | jq -r '.transactionId')
      AMOUNT=$(echo "$tx" | jq -r '.params.amount')
      # ... apply your rule, ask user, then:
      bron tx approve "$ID"
    done
```

### Wait for a specific tx to complete

```bash
TX=<transactionId>
bron tx subscribe --no-history \
  | jq --arg id "$TX" -r 'select(.transactionId == $id) | .status' \
  | while read -r status; do
      echo "$TX: $status"
      [ "$status" = "completed" ] && exit 0
      [ "$status" = "failed" ]    && exit 1
      [ "$status" = "expired" ]   && exit 1
      [ "$status" = "cancelled" ] && exit 1
    done
```

For a one-off "wait for this tx", `bron tx get <id>` polled is also fine. Subscribe is the right pattern when an agent watches dozens of in-flight transactions concurrently.

### Tee to a log file while consuming

```bash
bron tx subscribe --no-history --transactionStatuses completed \
  | tee /tmp/completed-tx.log \
  | jq -rc '{id: .transactionId, amount: .params.amount, status: .status}'
```

## Auto-reconnect contract

The CLI's transport handles reconnects transparently:

| Trigger | Behaviour |
|---|---|
| Server idle timeout (~60s without traffic) | Re-dials immediately, sends `SUBSCRIBE` again with the same `Correlation-Id` |
| Abnormal closure (1006), TCP drop | Linear backoff 1s → 2s → … → 10s, capped |
| Server-initiated logout (close 4000) | Stream ends; non-zero exit |
| Token-refresh (close 4001) | Re-dials with a fixed 1s delay |
| Stable connection (≥30s) before disconnect | Backoff resets to 0 — first reconnect is instant |
| Flapping connection (drops within 30s) | Backoff escalates per attempt |

**You don't see the reconnects** — frames keep flowing on stdout. The CLI only writes to stderr if the transport is actually flapping.

For verbose tracing during development, add `--debug`:

```bash
bron --debug tx subscribe --no-history --accountId <accountId>
```

Stderr gets each ping, dial, frame received (with byte counts), reconnect attempts. Authorization tokens never appear in logs.

## Server-side replay on reconnect

Important: when the connection drops and reconnects, the server **replays the snapshot frame again** (matching the original `--no-history` setting). With `--no-history`, the snapshot is empty so duplicates aren't an issue. Without `--no-history`, you'll see every currently-matching transaction again on each reconnect — dedupe by `transactionId` if it matters.

## What this skill does NOT do

- No state changes. To approve / decline / cancel a transaction surfaced by the stream, use the `bron-tx-send` skill (and confirm with the user first).
- No balance stream. Balances change as a side-effect of transactions; subscribe to transactions and recompute if you need a live balance view.
- No long-term storage. The subscribe channel is a stream — to query past transactions, use `bron tx list`.

## Discovery

```bash
bron tx subscribe --help
bron tx subscribe --schema    # falls back to the `tx list` schema with streaming: websocket tag
```
