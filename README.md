# Bron Skills

Agent skill bundle for the [Bron CLI](https://github.com/bronlabs/bron-cli) — teaches AI coding agents (Claude Code, Codex, Cursor, Aider, GitHub Copilot, etc.) how to drive `bron` safely and productively.

Bron is a non-custodial treasury management platform for digital assets. The CLI is a Go binary that exposes every API endpoint 1:1; this repo packages **what an agent needs to know** to use it well: when to dry-run vs send, idempotency contracts, error handling, output projection, and the `bron tx subscribe` live-event flow.

## What's in here

| Path | What it is | Who reads it |
|---|---|---|
| [`skills/`](skills/) | Canonical [`SKILL.md`](https://agentskills.io/specification) packages, one per workflow | Claude Code, Codex, Gemini CLI, JetBrains Junie, and any other tool implementing the SKILL.md open standard |
| [`AGENTS.md`](AGENTS.md) | Cross-agent project memory ([`agents.md`](https://agents.md/) standard) | Codex, Cursor, Copilot, Claude Code, Aider, Junie, Zed, Warp, Gemini CLI, Devin, Windsurf, OpenHands, OpenCode |
| [`SECURITY.md`](SECURITY.md) | Trust model, allowed-tools rationale, supply-chain pinning policy | You, before installing |
| [`install/`](install/) | One installer per agent — symlinks the right files into the right paths | You |

## Install

### Claude Code

```bash
git clone https://github.com/bronlabs/bron-skills ~/src/bron-skills
~/src/bron-skills/install/install-claude.sh
```

This symlinks every skill in `skills/` into `~/.claude/skills/`. Restart Claude Code (or run `/skills reload`) and the skills appear under `bron-*`.

### Codex

```bash
git clone https://github.com/bronlabs/bron-skills ~/src/bron-skills
~/src/bron-skills/install/install-codex.sh
```

Symlinks every skill into `~/.codex/skills/` and `AGENTS.md` into `~/.codex/AGENTS.md`. Restart Codex to pick them up. Override the install root with `CODEX_HOME=...`.

### Anthropic plugin marketplace (coming soon)

```
/plugin install bron@bronlabs/bron-skills
```

### Other agents

Cursor (MDC), GitHub Copilot, and Aider mirrors are on the roadmap; a typed [MCP server](https://modelcontextprotocol.io) wrapping `bron-sdk-go` ships today as `bron mcp` — see the [CLI MCP docs](https://developer.bron.org/sdk/cli/mcp).

For now, agents that read [`AGENTS.md`](AGENTS.md) natively (Codex, Cursor, Copilot, Aider, …) get a usable subset by dropping a copy of this repo's `AGENTS.md` into a project that uses `bron`.

## What the skills cover

| Skill | When to use it |
|---|---|
| [`bron-tx-send`](skills/bron-tx-send/) | Create / approve / decline / cancel transactions. Includes idempotency contract, dry-run pre-flight, and human-in-the-loop guardrails for state-changing ops. |
| [`bron-tx-read`](skills/bron-tx-read/) | List, get, and analyse transactions. Teaches the saga-vs-events mental model, `--embed events` for real money movement, and ready-made `jq` aggregations. |
| [`bron-balances-read`](skills/bron-balances-read/) | List account balances, project to specific columns, fold USD totals in via `--embed prices`. |
| [`bron-address-book`](skills/bron-address-book/) | Manage saved addresses; route withdrawals via `toAddressBookRecordId` instead of raw addresses. |
| [`bron-tx-subscribe`](skills/bron-tx-subscribe/) | Stream live transaction updates over WebSocket. JSONL pipelines, wait-for-completion patterns, auto-reconnect contract. |

Each skill is a folder with `SKILL.md` (the loaded brief), `references/` (longer material the agent loads on demand), and `assets/examples/` where helpful.

## Try it in 60 seconds

After running `install/install-claude.sh`, fire up Claude Code in a workspace that has `bron` configured (see [the CLI's quickstart](https://developer.bron.org/sdk/cli)) and ask it:

> List every withdrawal awaiting approval in this workspace, then dry-run approving the smallest one.

The agent will pick up the `bron-tx-send` skill, run `bron tx list --transactionStatuses waiting-approval --transactionTypes withdrawal --output jsonl`, sort by `params.amount`, and offer to approve the smallest — without you having to tell it the flag names.

## Trust model

Skills can pull instructions into an agent's context. Treat this repo like any other dependency:

- Pin to a tag (`git checkout v0.1.0`), not `master`, when integrating into production agent setups.
- Read [`SECURITY.md`](SECURITY.md) before granting an agent access to a production workspace.
- Every `SKILL.md` declares `allowed-tools` (e.g. `Bash(bron tx:*)`) — review them before installing.

State-changing operations (approve / decline / cancel / sign / send) require human-in-the-loop confirmation in every skill that exposes them. The skill prompts the agent to surface the action and wait for explicit OK before proceeding.

## Compatibility

| Skill | Min `bron-cli` |
|---|---|
| `bron-tx-send` | `v0.3.7` |
| `bron-tx-read` | `v0.3.7` |
| `bron-balances-read` | `v0.3.7` |
| `bron-address-book` | `v0.3.7` |
| `bron-tx-subscribe` | `v0.3.7` |

Skills declare their floor in `metadata.bron-cli-min`. Bumps to that floor are noted in [`CHANGELOG.md`](CHANGELOG.md).

## Versioning

Semver on the repo. New skills bump minor; backwards-incompatible content changes inside an existing skill bump major. Tag every release; the canonical install paths above all support pinning.

## Related

- [`bron-cli`](https://github.com/bronlabs/bron-cli) — the CLI these skills wrap.
- [`bron-sdk-go`](https://github.com/bronlabs/bron-sdk-go) — Go SDK; powers the `bron mcp` MCP server (`bron-cli ≥ 0.3.7`).
- [Bron developer docs](https://developer.bron.org) — API + CLI + SDK reference.

## Contributing

Issues and PRs welcome. New skills should follow the [`skills/bron-tx-send/`](skills/bron-tx-send/) layout as a template — frontmatter, ≤ 500 lines in `SKILL.md`, longer reference material under `references/`.

## License

[MIT](LICENSE) — same as `bron-cli`.
