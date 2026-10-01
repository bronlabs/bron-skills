# Bron

Claude plugin and agent skill bundle for [Bron](https://bron.org), a non-custodial treasury management platform for digital assets.

- **The Bron plugin** (`.claude-plugin/`, `.mcp.json`, `skills/`) — connects Claude to the MCP server built into Bron Desktop, so you can ask about your treasury in plain language: balances, transactions, deposit addresses, address book, stakes. Authorization is OAuth plus Touch ID in the app; you choose the workspace, the access level and the accounts. Its skill teaches the agent to read settlements instead of quotes, page before totalling, and confirm every state change.
- **Bron CLI skills** (`cli-skills/`) — `SKILL.md` packages for agents that drive the [Bron CLI](https://github.com/bronlabs/bron-cli) with an API key. They are not part of the plugin; install them with the scripts in `install/`.

## What's in here

| Path | What it is | Who reads it |
|---|---|---|
| [`skills/`](skills/) | The plugin's skill for the Bron Desktop MCP server | Claude, through the plugin |
| [`cli-skills/`](cli-skills/) | Canonical [`SKILL.md`](https://agentskills.io/specification) packages for the Bron CLI, one per workflow | Claude Code, Codex, Gemini CLI, JetBrains Junie, and any other tool implementing the SKILL.md open standard |
| [`AGENTS.md`](AGENTS.md) | Cross-agent project memory ([`agents.md`](https://agents.md/) standard) | Codex, Cursor, Copilot, Claude Code, Aider, Junie, Zed, Warp, Gemini CLI, Devin, Windsurf, OpenHands, OpenCode |
| [`SECURITY.md`](SECURITY.md) | Trust model, allowed-tools rationale, supply-chain pinning policy | You, before installing |
| [`install/`](install/) | One installer per agent — symlinks the right files into the right paths | You |

## Install

### Bron CLI skills — Claude Code

```bash
git clone https://github.com/bronlabs/bron-skills ~/src/bron-skills
~/src/bron-skills/install/install-claude.sh
```

This symlinks every skill in `cli-skills/` into `~/.claude/skills/`. Restart Claude Code (or run `/skills reload`) and the skills appear under `bron-*`.

### Bron CLI skills — Codex

```bash
git clone https://github.com/bronlabs/bron-skills ~/src/bron-skills
~/src/bron-skills/install/install-codex.sh
```

Symlinks every skill into `~/.codex/skills/` and `AGENTS.md` into `~/.codex/AGENTS.md`. Restart Codex to pick them up. Override the install root with `CODEX_HOME=...`.

### Claude plugin

Install **Bron** from the plugin directory in Claude (**Customize → Plugins**). A plugin added there also appears in your Claude Code sessions. To try a local checkout in Claude Code for one session:

```bash
claude --plugin-dir ~/src/bron-skills
```

### Other agents

Cursor (MDC), GitHub Copilot, and Aider mirrors are on the roadmap; a typed [MCP server](https://modelcontextprotocol.io) wrapping `bron-sdk-go` ships today as `bron mcp` — see the [CLI MCP docs](https://developer.bron.org/sdk/cli/mcp).

For now, agents that read [`AGENTS.md`](AGENTS.md) natively (Codex, Cursor, Copilot, Aider, …) get a usable subset by dropping a copy of this repo's `AGENTS.md` into a project that uses `bron`.

## Bron Desktop MCP server

The plugin registers one MCP server, `bron`, started as:

```
/Applications/Bron.app/Contents/MacOS/Bron --mcp-bridge
```

**Requirements:** macOS, Bron Desktop installed in `/Applications`, open and signed in. The server runs in Claude Code and in Cowork sessions on your computer. Regular claude.ai chats run connectors in the cloud and can't reach an app on your Mac, so there the plugin loads its skills only.

**Connecting:** on the first Bron question the app shows a consent screen. Pick the workspace, the access level and the accounts, then confirm with Touch ID. See [Connect an AI agent to Bron](https://support.bron.org/en/articles/17104034-connect-an-ai-agent-to-bron) for screenshots and other AI apps.

**Access levels:**

- **Read only** — accounts, balances, portfolio, transactions and their events, limits, address book, deposit addresses, assets, prices, networks, stakes. No actions.
- **Manage** — Read only plus dry-running, creating and cancelling transactions and intents, and managing the address book.

Neither level can approve, decline or sign. A transaction the agent prepares waits for your signature in Bron, and your workspace approval rules still apply. Keys never leave your devices.

**Staying in control:** **Settings → AI agents** in Bron Desktop lists connected agents. **Pause all agents** blocks every call until you resume; **Revoke** on an agent card removes its access immediately.

## Data and privacy

- The plugin itself runs no code, collects nothing and sends nothing anywhere. It ships one Markdown skill and one MCP server entry that starts the Bron Desktop app you already have installed.
- The bridge talks only to Bron Desktop's local endpoint on `127.0.0.1`, which is not reachable from outside your computer. Bron Desktop then calls the Bron API with your signed-in session, exactly as the app does for you.
- Whatever the agent reads becomes part of your conversation with Claude and is handled under [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). Grant the narrowest access level and accounts that do the job.
- Bron's own handling of your data: [Bron privacy policy](https://bron.org/policy).

## What the skills cover

| Skill | When to use it |
|---|---|
| [`bron-desktop-mcp`](skills/bron-desktop-mcp/) | Bron Desktop MCP: first-call order, what each access level allows, settlement-vs-quote, confirm-before-write, connection troubleshooting. |
| [`bron-tx-send`](cli-skills/bron-tx-send/) | Create / approve / decline / cancel transactions. Includes idempotency contract, dry-run pre-flight, and human-in-the-loop guardrails for state-changing ops. |
| [`bron-tx-read`](cli-skills/bron-tx-read/) | List, get, and analyse transactions. Teaches the saga-vs-events mental model, `--embed events` for real money movement, and ready-made `jq` aggregations. |
| [`bron-balances-read`](cli-skills/bron-balances-read/) | List account balances, project to specific columns, fold USD totals in via `--embed prices`. |
| [`bron-address-book`](cli-skills/bron-address-book/) | Manage saved addresses; route withdrawals via `toAddressBookRecordId` instead of raw addresses. |
| [`bron-tx-subscribe`](cli-skills/bron-tx-subscribe/) | Stream live transaction updates over WebSocket. JSONL pipelines, wait-for-completion patterns, auto-reconnect contract. |

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

Issues and PRs welcome. New skills should follow the [`cli-skills/bron-tx-send/`](cli-skills/bron-tx-send/) layout as a template — frontmatter, ≤ 500 lines in `SKILL.md`, longer reference material under `references/`.

## License

[MIT](LICENSE) — same as `bron-cli`.
