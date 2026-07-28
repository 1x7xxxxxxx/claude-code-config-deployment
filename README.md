# claude_code_config_deployment

Opinionated bootstrap for new Claude Code projects. Ships:

- **`setup-claude-code.sh`** — one-shot installer that drops a curated `.claude/` tree (hooks, agents, skills, rules, slash commands) plus a starter `CLAUDE.md` into any project directory.
- **`setup-payload-generic.tar.gz.b64`** — the embedded base64-encoded payload the script unpacks. Keeping it inline lets the installer run from a single `wget`/`curl` without needing network access to GitHub at install time.
- **`setup-payload-ml.tar.gz.b64`** — optional `--preset ml` overlay: the ML/data-science skills, agents and rules, kept out of the generic payload so a C++ or workflow project does not pay for them.
- **`ARCHITECTURE.md`** — **read this before changing a project's `.claude/` tree.** The target architecture: what makes a component actually fire, the component budget, the orchestration patterns, the error-class lifecycle, and an adoption checklist. Every rule carries either a book citation or a measurement; anything unmeasured says so.
- **`NEXT.md`** — **read this before starting a work session on a project's config.** The actionable backlog: what is still open, per project, each item with its cost, its risk and the command that proves it done.
- **`REX.md`** — **read this before writing an installer, a guard or a metric.** Twenty cross-project lessons, each one a mistake this fleet actually paid for. Most of them are the same error wearing different masks: mistaking a thing's *presence* for its *working*. Tool-specific lessons stay colocated in the tool's own frontmatter (`.claude/rules/rex-format.md`); this file holds only what no single tool owns.
- **`bench/`** — **the only thing here that measures a configuration's *effect* rather than its conformance.** A generated fixture project carrying defects lifted from classes this fleet actually paid for, six tasks with deterministic oracles, five configurations, and a headless runner that reads what really happened out of the `stream-json` trace: which agents were spawned, which skills fired, what the pre-prompt context cost. Start at `bench/PROTOCOL.md` — counting rules and separation thresholds, fixed before the first run. Its three self-tests are blocking and consume no quota.
- **`tools/dev/audit_fleet.py`** — scores a project's `.claude/` against that architecture (conformance, not quality — see the caveat in `ARCHITECTURE.md`). `--markdown` for the human report, `--fail-under N` as a CI ratchet.
- **`tools/dev/validate_payload.py`** — gates a rebuilt payload on the invariants the audit scores, so a defect can never ship to every project at once.
- **`checklists_ml/`** — a 13-section ML + MLOps + SoftEng checklist (markdown source + per-section HTML renders) anchored in a real industrial predictive-maintenance project's REX. Generalized for reuse across personal and professional ML projects.

Four files, four questions: `ARCHITECTURE.md` = *why*, `ROADMAP.md` = *what was done*, `NEXT.md` = *what to do next*, `REX.md` = *what we learned the hard way*. `bench/` answers a fifth that none of them can: *does any of it help?* Every project's `CLAUDE.md` carries a generated pointer block naming all four — installed by `tools/dev/install_conformance_ratchet.py`, sourced from `tools/dev/claude-md-pointer.md`, and enforced by a test in each repo so it cannot silently go stale.

## The eight measured facts the architecture rests on

Full detail and sources in `ARCHITECTURE.md` §0. In short:

1. **Naming a component is not wiring it.** Agents named in an imperative CLAUDE.md rule got 33 spawns; 23 agents named in a roster table got 0. A playbook injected 99 times produced 0 spawns of the agents it names.
2. **A misplaced component is inert, not degraded.** Claude Code loads only `.claude/skills/<name>/SKILL.md` — 2 of 124 declared skills were loadable across 8 projects before this was fixed.
3. **A hook cannot run a workflow, and cannot spawn a subagent either.** It emits a directive (`hookSpecificOutput.additionalContext`) or runs a shell command — that is the whole channel list. Amended 2026-07-28 morning to add `type: "prompt"` / `type: "agent"` on a book's authority, then reverted the same evening against the installed binary: `agentHooks`, `subagentHooks` and `runInBackground` occur **zero** times in `claude 2.1.220`. Longer work is detached by the hook itself (`Popen(start_new_session=True)`) and reported by `SessionStart`. See REX **R19**.
4. **The filesystem dominates hook cost, not the hook count.** `git status`: 4 ms native vs 2045 ms on `/mnt/c` (511×).
5. **A producer with no reader produces nothing.** One probe wrote 735 rows over 9 days that no code ever opened.
6. **An unpruned directory walk costs more than everything else.** 97.6 s vs 0.36 s pruned (270×).
7. **Hooks are scoped to the session, not the target repo.** Driving repo A from a session opened on repo B fires none of A's hooks.
8. **A loadable component with no description is worse than an inert one.** It can never fire, yet counts as loadable in every audit. `disable-model-invocation: true` is the honest third state.

## Quick start

```bash
# Bootstrap a fresh project
bash setup-claude-code.sh --project-name my-new-project --framework fastapi

# Dry-run (prints the 11 planned steps without touching the filesystem)
bash setup-claude-code.sh --project-name my-new-project --dry-run

# Print version + payload SHA256
bash setup-claude-code.sh --version
```

## What the `.claude/` tree contains after bootstrap

| Directory | Purpose |
|---|---|
| `.claude/agents/` | Sub-agent definitions invoked via the Agent tool. Strategic planner, code critic, security reviewer, ML evaluator, test quality reviewer, silent-failure hunter, web research specialist, build error resolver, etc. |
| `.claude/hooks/` | Python event handlers: session start/stop, pre-tool guard against destructive commands, post-edit ruff syntax check, pre-compact snapshot, REX draft on session end, observation logger. |
| `.claude/skills/` | Skills in spec layout — one directory per skill, each containing `SKILL.md` with `name` + a four-part `description`. Claude Code discovers them by that description and loads the body only when it fires; a flat `<name>.md` at this level is **never loaded**. See `ARCHITECTURE.md` §3. |
| `.claude/rules/` | One-page conventions. The generic payload ships **two**: `python.md` and `rex-format.md`. This line listed seven until 2026-07-28 — API, database, tests, time-sync, OS/arch parity were named here and carried by nothing, found when a bench variant asked the payload for `tests.md` and was told it does not exist. A doc that describes more than the channel transports is R17 seen from the reader's end. |
| `.claude/commands/` | User-invocable slash command definitions. |
| `.claude/dev-docs/` | Living architecture index — bricks, ROADMAP, REX archive. |

## Repackaging

When you modify the `.claude/` tree and want to roll a new payload:

```bash
bash repack-claude-payloads.sh
# Regenerates setup-payload-generic.tar.gz.b64 from the working tree.
```

## Checklists

The ML checklists in `checklists_ml/` cover:

| § | Topic |
|---|---|
| 1 | Architecture & Use Case Matrix |
| 2 | Data Preparation & EDA |
| 3 | Feature Engineering & Preprocessing |
| 4 | Modeling & Optimization |
| 5 | Evaluation & Interpretation (XAI) |
| 6 | Dimensionality Reduction & Clustering |
| 7 | Time Series & Deep Learning |
| 8 | Reinforcement Learning (Predictive Maintenance) |
| 9 | Deployment & MLOps (ETL, registry, drift, retraining, monitoring, IPC industrial, Locust, rollback, DR, K8s) |
| 10 | Security (app, ML fairness, adversarial) |
| 11 | SoftEng — Architecture |
| 12 | SoftEng — Data & Tests |
| 13 | Development Environment & Tooling |

`unified_ml_checklist.md` is the canonical source; the HTML files are pre-rendered for offline viewing.

## License

[Apache License 2.0](./LICENSE). See `LICENSE` for the full text.

The checklist references generic patterns from a private industrial ML project, anonymized for redistribution. No third-party trade secrets or proprietary credentials are included.
