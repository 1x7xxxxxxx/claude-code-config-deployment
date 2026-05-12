# claude_code_config_deployment

Opinionated bootstrap for new Claude Code projects. Ships:

- **`setup-claude-code.sh`** — one-shot installer that drops a curated `.claude/` tree (hooks, agents, skills, rules, slash commands) plus a starter `CLAUDE.md` into any project directory.
- **`setup-payload-generic.tar.gz.b64`** — the embedded base64-encoded payload the script unpacks. Keeping it inline lets the installer run from a single `wget`/`curl` without needing network access to GitHub at install time.
- **`checklists_ml/`** — a 13-section ML + MLOps + SoftEng checklist (markdown source + per-section HTML renders) anchored in a real industrial predictive-maintenance project's REX. Generalized for reuse across personal and professional ML projects.

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
| `.claude/skills/` | Domain-specific slash commands (`/resume`, `/sprint`, `/retro`, `/rex-promote`, …) loaded on demand by keyword triggers in `inject_context.py`. |
| `.claude/rules/` | One-page conventions: API, database, Python style, tests, time-sync, OS/arch parity, REX format. |
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
