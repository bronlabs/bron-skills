# Security & Trust Model

`bron-skills` packages instructions that get loaded into an AI coding agent's context. Treat it like any other dependency that influences automated decisions in your treasury workflow.

## Threat model

A malicious or buggy skill can:

1. Tell the agent to run a destructive `bron` command (e.g. `bron tx approve` on a transaction the user didn't intend).
2. Encourage the agent to disclose secrets (JWK contents, addresses) in chat.
3. Inject prompts to disable safety guardrails further down the conversation.
4. Direct the agent toward unintended endpoints or external services.

These risks are real — see the [OWASP Agentic Skills Top 10](https://owasp.org/www-project-agentic-skills-top-10/) and the [ClawHub registry-poisoning incident](https://www.practical-devsecops.com/mcp-security-vulnerabilities/) (Q1 2026) for documented attacks against the skill ecosystem.

## What this repo does to mitigate

- **`allowed-tools` allowlist on every `SKILL.md`.** Skills declare exactly which tool calls they require (e.g. `Bash(bron tx:*) Bash(bron policies:*) Read`), and Claude Code enforces them. No skill in this repo asks for unrestricted `Bash` or `Write` access.
- **Human-in-the-loop on state-changing ops.** `bron-tx-send` instructs the agent to surface every approve/decline/cancel/sign action to the user and wait for explicit OK. The skill body itself prompts that behaviour; do not weaken it in forks.
- **No embedded secrets.** Skills never ask the agent to paste, log, or transmit JWK file contents, API tokens, or `kid` values. Credentials live in `~/.config/bron/keys/*.jwk` or env vars and stay there.
- **No outbound network calls beyond `bron`.** The skills only invoke the local `bron` binary, which talks exclusively to the Bron API host configured in the active profile. No third-party telemetry, no fetch from arbitrary URLs.
- **Stable error codes over freeform text.** Skills branch on the CLI's stable exit codes and `code:` envelope field — not on parsed `--help` output or human messages — to avoid prompt-injection vectors that could rewrite a "success" message.

## What you should do as a consumer

1. **Pin to a tag**, not `master`:
   ```bash
   git clone --depth 1 --branch v0.1.0 https://github.com/bronlabs/bron-skills
   ```
   Reviewing a tagged release is feasible; reviewing a moving branch is not.

2. **Read every `SKILL.md` you install.** All four skills in this bundle fit on a screen — review them before symlinking. Look for `allowed-tools` declarations and the human-in-the-loop language.

3. **Use a reduced-scope API key for agent-driven workflows.** Bron API keys inherit the workspace member's permissions; create a dedicated member for agent automation with the smallest set of permissions you can get away with (e.g. read-only + dry-run access, no `tx send` permission).

4. **Run agent-driven flows on a non-production workspace first.** Bron supports separate workspaces; point an agent at a sandbox workspace until the flow is stable.

5. **Watch the trace IDs.** Every API call produces a correlation ID. If something unexpected happens, the `trace:` value in the error envelope joins your call across every Bron service log.

## Supply-chain pinning policy

We pin everything we don't own:

- `bron-cli` floor declared per skill in `metadata.bron-cli-min` (`v0.3.6` at time of writing). Bumps are noted in `CHANGELOG.md`.
- The Phase 2 MCP server pins `bron-sdk-go` to a specific tag.
- No external skill packages are imported. Cross-references go to public docs (developer.bron.org, agents.md, agentskills.io), not into other people's skill repos.

We do **not** auto-update third-party skill content into this bundle. Any third-party skill we list in our own AGENTS.md as "compatible" is a documentation pointer, not an import.

## Reporting

Found a security issue in a skill? Don't open a public issue — email `security@bron.org` with the skill name, the problematic content, and (if possible) a reproduction. We acknowledge within one business day and patch within seven.

Generic CLI / API security issues belong on [bron.org's bug bounty](https://developer.bron.org/bug-bounty/about) page, not here.

## Future

- **AAIF skill-signing** — Linux Foundation's Agentic AI Foundation flagged supply-chain integrity as a 2026 priority. When a signing spec lands, every release of this bundle will ship signed; pin to signed tags only.
- **Reproducible builds** — once we add a build step (Phase 2's MCP server), releases will include a deterministic build manifest.
