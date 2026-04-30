# Changelog

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
