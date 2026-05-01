---
name: bron-tx-subscribe
description: |
  Stream live transaction updates from the Bron treasury platform in real time
  via the bron CLI's WebSocket transport. Use when the user wants to "watch"
  many transactions in parallel, react to status changes across the workspace,
  build a live dashboard, or run an operator-style session over several
  minutes. For single-tx wait-for-completion, prefer the
  `bron_tx_wait_for_state` MCP tool from `bron-tx-send` — it's universal across
  MCP clients and doesn't need a bash background process. Same filters as
  `bron tx list`. Read-only, transparent auto-reconnect, no state changes.
  Pair with the `Monitor` tool so each pushed frame wakes the agent immediately
  — no polling, no manual `tail`.
license: MIT
compatibility: |
  Requires bron-cli >= 0.3.7 in PATH and an active profile with API key
  authentication. The CLI's WebSocket transport handles auto-reconnect via the
  bron-sdk-go realtime package — no extra setup needed.
allowed-tools: Bash(bron tx subscribe:*) Bash(bron tx:*) Bash(bron --schema:*) Read Monitor
metadata:
  vendor: bronlabs
  version: "0.2.1"
  bron-cli-min: "0.3.7"
---

# Bron live transaction stream

`bron tx subscribe` opens a long-lived WebSocket and prints transaction updates as JSONL on stdout — same filters as `bron tx list`, one frame per state transition. Read-only, no state changes. Auto-reconnect on idle/network drops is built in.

## When to reach for this skill (vs `bron_tx_wait_for_state`)

`bron_tx_wait_for_state` (MCP tool, see `bron-tx-send`) and `bron tx subscribe` (this skill) cover overlapping but different shapes of "watch tx state":

| Workflow | Pick |
|---|---|
| Submit one tx, await terminal | `bron_tx_wait_for_state` (every mode, no bash needed) |
| Surface every milestone for one tx | `bron_tx_wait_for_state` chained with narrowing `expectedStates` |
| Watch a batch of N tx in parallel | **this skill** — one subscribe, Monitor wakes on any frame |
| Operator dashboard / "watch the whole workspace for the next N minutes" | **this skill** |
| Auto-approve incoming withdrawals matching a rule | **this skill** |
| Multi-tx fan-out where you don't know the tx IDs up front (e.g. waiting on follow-up deposits) | **this skill** |

**Single-tx wait → prefer `bron_tx_wait_for_state`.** It's a long-poll MCP tool — universal, no bash process, returns instantly on first match. Use this skill when you need a workspace-wide stream that wakes the agent on every transition across many transactions.

## Mode prerequisite

This skill requires `bron-cli` in PATH. If you only have an MCP server and no CLI ("Mode M" in the `bron-tx-send` skill), use one or more parallel `bron_tx_wait_for_state` calls (sequential per-tx waits, or fanned out via Agent invocations) — there's no workspace-wide stream primitive on MCP-only today.

In the hybrid mode (CLI + MCP both available), use this skill's bash subscribe + `Monitor` for the multi-tx streaming lane and reach for `mcp__bron__bron_*` for everything else (read, create, approve, single-tx wait). The streaming primitive is the one place where bash beats MCP for batch monitoring, because Claude Code doesn't currently surface MCP server-initiated notifications to the LLM session.

## When to use this skill — proactively (multi-tx flows)

**At the start of any session that touches multiple transactions in parallel.** Examples:

- "approve all the small withdrawals waiting for me"
- "I'm going to fund three accounts and then run trades — watch all of it"
- "every incoming deposit on this account, send a follow-up bridge"

Launch a workspace-wide subscription first; every subsequent state change shows up as a stream frame.

The bad pattern (don't do this):
```
1. Approve 30 pending tx in a loop with `bron_tx_approve`.
2. After each one, poll `bron_tx_get` to confirm.
3. Burn tokens; lose intermediate states.
```

The good pattern:
```
1. Bash run_in_background: bron tx subscribe --no-history > /tmp/bron-tx-stream.log 2>&1
2. Capture the bash_id.
3. Use the Monitor tool with that bash_id — every new stdout line wakes you.
4. Approve the batch via `bron_tx_approve`. Monitor wakes you for each transition,
   you surface progress to the user without re-querying.
```

For a **single** tx, skip the subscription entirely and use `bron_tx_wait_for_state` after submit — fewer moving parts.

## The Monitor primitive — how the agent sees frames in real time

`bron tx subscribe` is a long-running bash process. Standard Claude Code agents have a built-in `Monitor` tool that streams stdout from a background process: **each stdout line is a notification that wakes the agent.** Since `bron tx subscribe` emits one JSON line per state change, Monitor turns the WebSocket into a pseudo-push channel into the session — you don't need server-initiated MCP notifications (which Claude Code doesn't surface to the LLM today).

```text
Step 1 — launch in background:
  Bash {
    command: "bron tx subscribe --no-history --output jsonl > /tmp/bron-tx-stream.log 2>&1",
    run_in_background: true,
    description: "Start workspace-wide tx subscription"
  }
  → returns a bash_id like "bg-abc123"

Step 2 — start watching:
  Monitor {
    bash_id: "bg-abc123",
    until: "<empty for indefinite>"
  }
  → wakes the agent on every new line

Step 3 — agent processes each frame as a Monitor notification.
  Each notification is a JSONL line: {transactionId, status, transactionType, params, ...}.
  React: tell the user, take the next action, update state, etc.
```

`Monitor` does not block other work — it's a notification subscription. While Monitor is active, you can still call other tools (`bron_tx_get`, `bron_tx_approve`, etc.) in response to what arrives.

If the Claude Code installation doesn't expose `Monitor`, fall back to a polling re-read of the log file via `Bash`-with-Read on a `ScheduleWakeup` cycle. Don't manually `tail -f` and freeze — that wastes the entire turn waiting on a single process.

## Subscribe-first, send-second

The clean pattern in any tx-related session:

```
1. Launch the workspace-wide subscribe (background bash, Monitor on it).
2. ONLY THEN: start composing / submitting transactions via MCP or CLI.
3. As Monitor wakes you on each frame, surface the state transition to the user.
4. When you see `completed | failed | expired | cancelled` for the tx the user
   cared about, tell them and stop watching that ID (Monitor stays running for
   future tx in the same session).
```

Why this order matters: `--no-history` on subscribe means the snapshot is empty. If you submit a tx and *then* subscribe, you may miss the `signing-required` frame that the server emitted between submission and subscription start. Subscribing first guarantees you see every frame.

## Mental model: GET extended

A subscription is "GET extended": same query as `bron tx list`, the server replays the historical match as the **first frame**, then keeps the connection open and pushes each subsequent change as another frame. Output is always JSONL — pipe to `jq` or read line-by-line.

```bash
bron tx subscribe --transactionStatuses signing-required,waiting-approval
```

You'll see:
1. A snapshot frame for every currently-matching transaction (could be 0, could be 100s).
2. One frame per state transition after that, indefinitely.

For agent / Monitor flows, `--no-history` is almost always right — the snapshot is replay noise that Monitor would still wake the agent on.

## Skipping the snapshot — the agent default

```bash
bron tx subscribe --no-history --output jsonl > /tmp/bron-tx-stream.log 2>&1
```

`--no-history` sends `limit=0` to the server: snapshot is empty, live stream starts fresh. **This is the default for any agent-driven session** — saves token budget and lets the user / Monitor see only meaningful transitions.

If you also want a one-time snapshot of pending work for context, do it as a separate read call (`bron_tx_list` MCP tool, or `bron tx list --transactionStatuses signing-required,waiting-approval`) and *then* start the subscribe — never rely on the subscribe's history frame in agent flows.

## Filters

| Flag | Use |
|---|---|
| `--transactionStatuses <list>` | comma-separated statuses (`signing-required,signed,broadcasted,…`) |
| `--transactionTypes <list>` | comma-separated types (`withdrawal,bridge,allowance,…`) |
| `--accountId <id>` | scope to one source account |
| `--no-history` | skip the initial snapshot — **agent default** |

Filters apply to **both** the snapshot and the live stream — once subscribed, the server only pushes updates that match.

For workspace-wide visibility (recommended for proactive sessions), pass *no* filters except `--no-history`. You'll see every status change for every tx in the workspace — usually a low volume (0–10/min in a normal treasury).

## Recipes

### Proactive workspace-wide subscription (start of every tx session)

```bash
# Background, output in JSONL, no snapshot.
bron tx subscribe --no-history --output jsonl \
  > /tmp/bron-tx-stream.log 2>&1
```

→ Then `Monitor { bash_id: <id> }` to react to each frame.

### Wait for a specific tx to terminate

**Prefer `bron_tx_wait_for_state` over this skill for single-tx waits** — see the `bron-tx-send` skill. Universal MCP, no bash process needed.

This skill is right when you've already started a workspace-wide subscription for *other* reasons (batch operation, dashboard, fan-out) and want to ride that stream for one more tx without spinning up a separate wait_for_state call:

```bash
# Already running: workspace-wide subscribe in background, Monitor active.
# As frames arrive on Monitor, parse JSON; on each frame:
#   if .transactionId == "<TX>" and .status in {completed,failed,expired,cancelled,declined,rejected}:
#     terminal — surface to user, stop tracking <TX>.
```

Don't poll `bron_tx_get` in a loop — it's strictly worse than either of the above options.

### Auto-approve incoming withdrawals matching a rule

The "agent flow" — but **only run after explicit user confirmation of the rule**. Don't write something that auto-approves without human-in-the-loop unless the user has explicitly authorised it.

The agent reads each Monitor frame, applies the rule, surfaces the proposed action, waits for OK, then calls the matching MCP tool:

```text
On Monitor frame F where F.status == "signing-required" and F.transactionType == "withdrawal":
  if rule_matches(F):
    show user: "About to approve <id> (<amount> <asset>) — OK?"
    on user OK:
      mcp__bron__bron_tx_approve { transactionId: F.transactionId }
```

### Tee to a log file while consuming live

For session debugging — keep both Monitor + a tail-able log:

```bash
bron tx subscribe --no-history --output jsonl \
  | tee /tmp/bron-tx-stream.log
```

The `tee` keeps the file for postmortem; Monitor on the *bash process* still wakes the agent on each line.

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

**You don't see the reconnects** — frames keep flowing on stdout, Monitor keeps waking. The CLI only writes to stderr if the transport is actually flapping.

For verbose tracing during development, add `--debug`:

```bash
bron --debug tx subscribe --no-history --accountId <accountId>
```

Stderr gets each ping, dial, frame received (with byte counts), reconnect attempts. Authorization tokens never appear in logs.

## Server-side replay on reconnect

When the connection drops and reconnects, the server **replays the snapshot frame again** (matching the original `--no-history` setting). With `--no-history`, the snapshot is empty so duplicates aren't an issue. Without `--no-history`, you'll see every currently-matching transaction again on each reconnect — dedupe by `transactionId` if it matters.

## Why not just an MCP "subscribe" tool?

The MCP spec defines server-initiated notifications (`notifications/resources/updated`) and resource subscriptions (`resources/subscribe`), but **no major MCP client surfaces those notifications to the LLM session today** — Claude Desktop, Cursor, Cline, ChatGPT all consume them at the transport layer but never wake the agent. Until that changes, push-style state-change delivery to a live session needs one of two workarounds:

1. **Long-poll `tools/call`** — block the request until match-or-timeout. We expose this as `mcp__bron__bron_tx_wait_for_state` (single-tx) — see the `bron-tx-send` skill. Works in every MCP client; right for "submit one tx, watch through to completion".
2. **WebSocket-via-bash + Monitor** — for *multi-tx batch* monitoring where one stream feeds many decisions. This skill. Works only in clients that have a `Monitor` primitive (Claude Code today).

The `mcp__bron__bron_tx_*` tools cover everything else (read, create, approve). Bash subscribe is reserved for the workspace-wide-stream lane; everything else lives in MCP.

## What this skill does NOT do

- No state changes. To approve / decline / cancel a transaction surfaced by the stream, use the `bron-tx-send` skill (and confirm with the user first).
- No balance stream. Balances change as a side-effect of transactions; subscribe to transactions and recompute if you need a live balance view.
- No long-term storage. The subscribe channel is a stream — to query past transactions, use `bron tx list` or `mcp__bron__bron_tx_list`.

## Discovery

```bash
bron tx subscribe --help
bron tx subscribe --schema    # falls back to the `tx list` schema with streaming: websocket tag
```
