# AGENTS.md — Bron CLI for AI coding agents

Project memory for any AI coding agent working in a repo that uses the Bron CLI. This file follows the [`agents.md`](https://agents.md/) open standard — drop it into any project (or symlink from this bundle's installer) and the agent picks it up automatically.

Bron is a non-custodial treasury management platform. The CLI is `bron`. It's a single Go binary, regenerated from the OpenAPI spec on every API release; every endpoint and every request/response field is reachable from the shell, 1:1 with the spec.

## Two surfaces — pick one per session

- **`bron mcp` (MCP server)** — typed tool calls (`bron_tx_list`, `bron_tx_create`, `bron_tx_withdrawal`, `bron_tx_wait_for_state`, …) without shell quoting. Same auth, same data path, structured errors. Right when the agent host speaks MCP (Claude Code, Cursor, Cline, Claude Desktop, ChatGPT, …). Register once: `claude mcp add bron -- bron mcp`. The default tool set is curated (generic `bron_tx_create` replaces the per-type creators; `--tools all` registers everything). Call `bron_help` first for the data model and tool discovery.
- **`bash bron <verb>` (CLI)** — pipeable, JSONL output, stable exit codes. Right when there's no MCP host, when you need `--columns` projection, or when the workflow uses shell tooling (`jq`, `xargs`, etc.).

Pick once on the first turn and stay there for the session. Mixing surfaces mid-flow is a common source of confusion (the same backend operation reached two different ways tracks badly in conversation context).

## General rules (both surfaces)

- **Always prefer `bron` over raw `curl`/JWT signing** for any Bron API call. The CLI handles signing, retries, error envelope parsing, output formatting, and the WebSocket subscribe transport. Going around it is brittle.
- **Use the bron-sdk-go / sdk-js / sdk-python in code** if you're writing a long-lived service, not invoking commands ad-hoc. The CLI is for one-shots, scripts, and agent-driven workflows.
- **Do not** invoke private/internal endpoints. The public surface is what `bron --schema` (or MCP `tools/list`) reflects.

## Discovery

```bash
bron --help                         # human-readable: examples + flags + every resource
bron <resource> <verb> --help       # per-command flags + body shape + responses
bron --schema                       # full CLI as one OpenAPI 3.1 document — agent's preferred entry point
bron <resource> <verb> --schema     # single-command fragment
bron help <topic>                   # signing | profiles | output | body | errors | idempotency | agents | mcp
```

`--schema` is the contract you can rely on across `0.x`. Branch on it for tool discovery, not on `--help` text.

On the MCP surface there's a cheaper orientation step: a single `bron_help` call returns the data model, any tool's response shape (resolved from the spec, with wire-correct field paths), and worked `jq` recipes. Call it once before composing analytical queries.

## Common patterns

### Listing transactions

```bash
bron tx list --transactionStatuses waiting-approval,signing
bron tx list --transactionTypes withdrawal --createdAtFrom 2026-01-01 --embed assets
bron tx list --output table --columns transactionId,status,transactionType,createdAt
```

JSONL is the easiest format for agent-side parsing:

```bash
bron tx list --output jsonl --columns transactionId,status,params.amount
```

**Intent vs settlement.** `params.amount` is what was *requested* (the quote); `_embedded.events[].amount` is what *actually settled on-chain*. For any financial total — volume, net flow, P&L — pass `--includeEvents` (CLI) / `includeEvents: true` (MCP) and aggregate `_embedded.events[]`, never `params.amount` (it diverges for swaps, bridges, intents, fiat and fee-bearing transfers). `params.amount` is right only when you genuinely want the requested amount, e.g. filtering withdrawals under a threshold.

### Creating a transaction

**Always** pass `--externalId` so retries are idempotent:

```bash
bron tx withdrawal \
  --externalId  "agent-task-$(date +%s)-$(openssl rand -hex 4)" \
  --accountId   <accountId> \
  --params.amount=100 \
  --params.assetId=5000 \
  --params.networkId=ETH \
  --params.toAddressBookRecordId=<recordId>
```

The `--externalId` is the idempotency key. Bron de-duplicates by `(workspaceId, externalId)` — retrying the same call returns the existing transaction; reusing the key with a different body is a 409 conflict.

For a first-time pattern, **dry-run first**:

```bash
bron tx dry-run --transactionType withdrawal --file /tmp/tx.json
```

Returns expected fees, blockchain ETA, and validation errors without submitting.

### Approve / decline / cancel

```bash
bron tx approve <transactionId>
bron tx decline <transactionId>
bron tx cancel  <transactionId>
```

These are state-changing and often irreversible. **Never** invoke them silently in agent code — surface the affected transactions to the human, wait for explicit OK.

### Live updates

```bash
bron tx subscribe --transactionStatuses signing-required,waiting-approval
```

Streams JSONL frames forever, transparent auto-reconnect on idle/network drops. Live-only by default — pass `--with-history` if you also want a one-time replay of every currently-matching transaction on connect (useful for snapshot+tail scripts; rare for agent flows).

## Error handling

Stable exit codes:

| Exit | HTTP | Meaning |
|---|---|---|
| `0` | 2xx | success |
| `3` | 401/403 | unauthorized |
| `4` | 404 | not found |
| `5` | 400 | bad request |
| `6` | 409 | conflict (e.g. `externalId` reuse) |
| `7` | 429 | rate limited |
| `8` | 5xx | server error |
| `1` | other | network, file I/O, malformed flag |

On non-zero exit the CLI prints the API error envelope to **stderr**:

```
error: <message>
  status: <http-status>
  code:   <STABLE_CODE>
  id:     <correlation-id>
```

Branch on `code` (stable), not on the human message. Quote `id` in any user-facing error report — same value the SDKs expose under longer programmatic names (Go `APIError.RequestID`, MCP error payload `requestId`), so logs join cleanly across surfaces.

## Output formats

| Format | When to use |
|---|---|
| `--output json` (default) | Single-resource reads, pretty-printed for humans on TTY |
| `--output jsonl` | Lists, agent-side parsing, shell pipelines, line-by-line consumption |
| `--output yaml` | Hand-editing config, rare for agent flows |
| `--output table` | Human review only — never grep table output |

Combine with `--columns` to project just what you need (works for json/yaml/jsonl/table). Cuts agent context cost significantly. A dot-path crossing an array applies to every element (`--columns transactionId,_embedded.events.usdAmount`).

On the MCP surface there's no shell to pipe through, so the equivalent shaping is built into every read tool as arguments: `fields` (the `--columns` analogue) and `jq` (a sandboxed gojq program run server-side for `select` / `group_by` / arithmetic). Both trim the reply before it reaches the agent's context — e.g. `{ "tool": "bron_tx_list", "arguments": { "includeEvents": true, "jq": "[.transactions[]._embedded.events[]? | (.usdAmount // \"0\" | tonumber)] | add" } }` returns just the total.

## Authentication

The active profile (`bron config show`) holds the JWK key file path, workspace ID, and base URL. For CI / one-off agent runs, prefer env vars:

- `BRON_PROFILE` — pick a different named profile from the config
- `BRON_WORKSPACE_ID` — workspace ID
- `BRON_API_KEY` — raw JWK bytes (preferred for secret stores: `BRON_API_KEY=$(op read 'op://Personal/Bron/private-jwk') bron tx list`); the CLI strips the var from its environment after reading, so child processes don't inherit it
- `BRON_API_KEY_FILE` — path to the JWK private key (use when you want a managed file on disk)
- `BRON_BASE_URL` — override the default API host (rarely needed)
- `BRON_PROXY` — `http://[user:pass@]host:port` for outbound HTTP/HTTPS through a corporate proxy
- `BRON_CONFIG` — path to a different `config.yaml` (default: `~/.config/bron/config.yaml`)

Never log the contents of the JWK file. Never paste it into the agent's chat history.

## Safety guardrails (apply these in your system prompt)

- **Always** pass `--externalId` on any `tx <type>` or `tx create` call.
- **Confirm before approve / decline / cancel / sign** — these are state-changing and often irreversible.
- **Use `tx dry-run`** before any first-time withdrawal pattern, to surface fees and validation errors.
- **Bound query windows** — `--createdAtFrom` / `--createdAtTo` on list queries to keep response sizes manageable.
- **Treat exit codes as truth** — `bron tx approve $tx || stop_and_report` instead of grepping success messages.
- **Never** embed secrets (JWK contents, API tokens) in code or logs.

## See also

- The full [Bron CLI documentation](https://developer.bron.org/sdk/cli) on the dev portal.
- [`bron help agents`](https://developer.bron.org/sdk/cli/agents) — same content as this file, baked into the CLI itself.
- [`SECURITY.md`](SECURITY.md) for the trust model and allowed-tools rationale.
