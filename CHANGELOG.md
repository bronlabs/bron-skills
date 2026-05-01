# Changelog

## v0.2.1 — 2026-05-01

Three improvements driven by the first round of MCP usage feedback:

1. **`bron_tx_wait_for_state`** — long-poll MCP tool that subscribes via
   WebSocket to a single transaction and returns the moment its status
   enters `expectedStates`. Universal across MCP clients — no bash, no
   `Monitor`. Replaces the `ScheduleWakeup`-driven polling fallback for
   Mode M (MCP-only) and is the recommended path for single-tx waits in
   every mode.
2. **MCP schema types fixed** — `nonEmpty` is now `boolean`, `limit`/`offset`
   are `integer`. Auto-derived from the OpenAPI spec via cligen — every
   future endpoint inherits the right types without skill or MCP changes.
3. **`embed=prices` works on MCP** — `bron_balances_list { embed: "prices" }`
   now attaches `_embedded.usdPrice` / `usdValue` per balance, parity with
   `bron balances list --embed prices` on the CLI.

### `bron-tx-send`

- Step 0 reframed: **not** a mandatory subscription preamble. Single-tx flows
  use `bron_tx_wait_for_state` (every mode); multi-tx fan-out / dashboards
  still use `bron tx subscribe` + `Monitor` (CLI-only).
- Mode M no longer needs `ScheduleWakeup` polling — `wait_for_state` works
  natively without periodic re-firing.
- Walkthrough Step 5 rewritten around `wait_for_state` with a state-narrowing
  pattern table for surfacing each milestone.
- New row in "Two ways to drive the same flow" mapping table:
  `wait_for_state` ↔ `bron tx subscribe --transactionId`.
- `allowed-tools` extended with `mcp__bron__bron_tx_wait_for_state`.
- Bumped `bron-cli-min` to 0.3.7 (the version that ships the new MCP tool).

### `bron-tx-subscribe`

- Reframed as "multi-tx fan-out / dashboard / operator" primitive — no longer
  the universal first step of every tx-related session.
- New decision table at the top: when to pick `wait_for_state` vs subscribe.
- "Wait for a specific tx to terminate" recipe now points at
  `bron_tx_wait_for_state` first; bash subscribe is the fallback only when
  you've already launched a workspace stream for other reasons.
- "Why not an MCP subscribe tool?" rewritten to cover both workarounds —
  long-poll (universal) and bash + Monitor (Claude Code only).
- Bumped `bron-cli-min` to 0.3.7.

### `bron-balances-read`

- Default flow rewritten to use the new MCP `embed: "prices"` argument
  instead of the CLI-only fallback. The MCP server does the same join the
  CLI orchestrator does — one tool call, no bash needed.
- Schema-driven typing: `nonEmpty` accepts a real `true` / `false`, `limit`
  takes a real number — no more string-quoting integers in tool calls.
- Bumped `bron-cli-min` to 0.3.7.

## v0.2.0 — 2026-05-01

MCP-aware overhaul. Skills now drive both `bron-cli` (bash) and the new `bron`
MCP server (`bron mcp` from bron-cli, or the upcoming Bron Desktop bundled
MCP). All four skills detect available surfaces on the first turn and pin to
one — no more accidental drift between MCP and bash mid-flow. New explicit
"Pick your surface" preamble in `bron-tx-send` covers three modes: MCP-only
(Mode M, e.g. Desktop), CLI-only (Mode C), and hybrid (Mode H).

### `bron-tx-send`

- Mandatory **Step 0 — start a live subscription before doing anything else**.
  Mode H/C: `bron tx subscribe --no-history` in a `run_in_background` Bash plus
  the `Monitor` tool — every JSONL frame wakes the agent. Mode M: a
  `ScheduleWakeup`-driven `mcp__bron__bron_tx_get` polling loop until terminal.
- All examples rewritten to MCP-first: typed `bron_tx_dry_run`,
  `bron_tx_withdrawal`, `bron_tx_approve` etc. CLI shown as fallback only.
- New "Two ways to drive the same flow" mapping table — MCP tool ↔ CLI verb.
- New guardrail: never poll `bron_tx_get` in a wait loop when a Monitor-driven
  subscription does the same job for free.
- `allowed-tools` expanded to include every relevant `mcp__bron__*` tool plus
  the `Monitor` primitive.

### `bron-tx-subscribe`

- New "Mode prerequisite" section: requires CLI, with the mode-M polling fallback
  cross-referenced.
- New top-of-file pattern: **subscribe-first, send-second**. Workspace-wide
  subscription on the first turn of any tx work, before any payload is composed.
- New "Monitor primitive" section explaining how `Monitor { bash_id }` turns the
  WebSocket into a pseudo-push channel — each stdout line is a notification that
  wakes the agent; the agent can still call other tools while Monitor is active.
- New "Why not just an MCP `subscribe` tool?" section explaining that MCP server-
  initiated notifications exist in the spec but Claude Code doesn't currently
  surface them to the LLM session — bash + Monitor is the working primitive
  today.

### `bron-balances-read`

- New "Pick your surface" section — MCP tools listed alongside CLI fallback.
- Default flow rewritten in MCP form first; CLI fallback retained for
  `--embed prices` (the CLI-side join, not yet exposed as an MCP flag).
- `allowed-tools` extended with `mcp__bron__bron_balances_*`,
  `mcp__bron__bron_accounts_*`, `mcp__bron__bron_assets_*`.

### `bron-address-book`

- New "Pick your surface" section pointing at the canonical mode picker in
  `bron-tx-send`.
- All MCP examples added side-by-side with CLI: list, create, delete, recipient
  resolution before withdrawal.
- `allowed-tools` extended with `mcp__bron__bron_address_book_*`.

### Why the "Pick your surface" pattern

Multi-surface drift was the #1 friction in 0.1.x: agents would read via MCP,
then for follow-up "drop to bash" out of habit, then back to MCP for the next
call. The session became hard to reproduce and tools double-wrapped each other.
0.2.x makes the agent commit to one surface up front — based on what's actually
registered in the session — and stay there.

## v0.1.0 — 2026-04-30

Initial public release. Claude Code only; cross-agent mirrors and the typed MCP server land in subsequent phases (see `BRO-519`, `BRO-520`, `BRO-521`).

### Skills

- `bron-tx-send` — create / approve / decline / cancel transactions; idempotency contract; dry-run pre-flight; human-in-the-loop on state-changing ops.
- `bron-balances-read` — list balances, project to columns, USD totals via `--embed prices`.
- `bron-address-book` — list / create / delete saved addresses, route via `toAddressBookRecordId`.
- `bron-tx-subscribe` — live updates over WebSocket, JSONL pipelines, wait-for-completion patterns.

All skills require `bron-cli ≥ v0.3.6`.

### Repo

- `AGENTS.md` cross-agent project memory (any tool reading the [`agents.md`](https://agents.md/) standard).
- `SECURITY.md` trust model and supply-chain pinning policy.
- `install/install-claude.sh` — symlinks `skills/*` into `~/.claude/skills/`.
- `.claude-plugin/plugin.json` for the Anthropic plugin marketplace (submission deferred).
