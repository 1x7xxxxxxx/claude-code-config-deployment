# claude-code-config-deployment

Opinionated bootstrap for new Claude Code projects. One script drops a curated
`.claude/` tree — hooks, agents, skills, rules, slash commands — plus a starter
`CLAUDE.md` into any project directory.

```bash
# Bootstrap a fresh project (run from the repo root of a git repo)
bash setup-claude-code.sh --project-name my-new-project

# Print the 11 planned steps without touching the filesystem
bash setup-claude-code.sh --project-name my-new-project --dry-run

# Print version + payload SHA256
bash setup-claude-code.sh --version
```

Prerequisites: Bash, Python 3.10+, and a git repo to install into. The payloads
are embedded base64, so the installer needs no network access at install time.
Every count and behaviour on this page was verified on 2026-08-19 against
Claude Code 2.1.235, by installing into fresh repositories.

## What ships here

| File | Role |
|---|---|
| `setup-claude-code.sh` | The installer. `--help` lists every flag. |
| `setup-payload-generic.tar.gz.b64` | The base payload it unpacks: 3 agents, 1 command, 3 scripts, and the `CLAUDE.md` / `DEVLOG.md` / dev-docs templates. No hooks, no rules, no skills — see the table below. |
| `setup-payload-ml.tar.gz.b64` | `--preset ml` overlay — ML/data-science skills, agents and rules, kept out of the base so a C++ or workflow project does not pay for them. |
| `setup-payload-extended.tar.gz.b64` | `--preset extended` overlay — the larger command and skill set. |

Presets are discovered by glob: `ls setup-payload-*.tar.gz.b64` lists what this
copy can install.

## What lands in `.claude/`, per preset

Counted by running each variant into a fresh git repo, 2026-08-19. Not what the
payload is meant to contain — what it puts on disk.

| | agents | commands | hooks | rules | skills | scripts |
|---|---|---|---|---|---|---|
| *(no preset)* | 3 | 1 | 0 | 0 | 0 | 3 |
| `--preset ml` | 7 | 1 | 0 | 5 | 9 | 3 |
| `--preset extended` | 11 | 14 | 13 | 2 | 24 | 11 |

**Read that first row before choosing.** The base payload installs three agents,
one command and three scripts — it creates `hooks/`, `rules/` and `skills/`, and
leaves all three empty. If you want the configuration the measured facts below
describe, you want `--preset extended`:

```bash
bash setup-claude-code.sh --project-name my-project --preset extended
```

| Directory | Purpose |
|---|---|
| `agents/` | Sub-agent definitions invoked via the Agent tool. Base: build error resolver, roadmap keeper, sibling sweeper. Presets add reviewers and evaluators. |
| `hooks/` | Python event handlers: session start/stop, a pre-tool guard against destructive commands, post-edit syntax check, pre-compact snapshot, observation logger. **`extended` only.** |
| `skills/` | Skills in spec layout — one directory per skill, each with a `SKILL.md` carrying `name` + a four-part `description`. A flat `<name>.md` at this level is never loaded. |
| `rules/` | One-page conventions. `extended` ships two, `ml` ships five, the base ships none. |
| `commands/` | User-invocable slash command definitions. |
| `scripts/` | Test selector, audit runner, usage report. |
| `dev-docs/` | Living architecture index — ROADMAP and error-class catalog. |

### Known gap: `--with-skills` does not gate the preset overlays

The installer documents skills as opt-in since 2026-08-03, on the measurement
that they fired once in 222 cells and cost +9 432 tokens of context per session.
The gate only wraps the **base** payload's skills — which is empty — so
`--preset extended` installs its 24 skills whether or not you pass the flag.
Verified 2026-08-19: 24 skills with `--with-skills`, 24 without. Until that is
fixed, budget the context cost when you pick `extended`.

### If the repo already has a `CLAUDE.md`

The installer never overwrites it — but then the agents, commands and scripts it
just installed are named by nothing, and a component no rule names never fires
(fact 1). In a baseline clone the rules are retrofitted automatically; **this
distribution does not carry that tool**, so the installer prints:

```
⚠️  NOT retrofitted: …/tools/dev/install_measured_rules.py is absent
    The repo now carries commands/agents/scripts that NO rule names —
    every one of them is inert.
```

The install still completes (verified: 11 agents, 24 skills on `extended`) and
your `CLAUDE.md` is untouched. You then have to name the pieces yourself: add
imperative rules to `CLAUDE.md` that call the agents and commands by name. A
roster table will not do it — that is fact 1, measured at 33 spawns versus 0.

## The eight measured facts it rests on

Every rule in the shipped configuration traces back to one of these. They are
measurements, not preferences — which is why some of them contradict advice you
will find elsewhere.

1. **Naming a component is not wiring it.** Agents named in an imperative
   `CLAUDE.md` rule got 33 spawns; 23 agents named in a roster table got 0. A
   playbook injected 99 times produced 0 spawns of the agents it names.
2. **A misplaced component is inert, not degraded.** Claude Code loads only
   `.claude/skills/<name>/SKILL.md`. Across 8 repositories, 2 of 124 declared
   skills were actually loadable before this was fixed.
3. **A hook cannot run a workflow, and cannot spawn a subagent either.** It
   emits a directive (`hookSpecificOutput.additionalContext`) or runs a shell
   command — that is the whole channel list. `agentHooks`, `subagentHooks` and
   `runInBackground` occur **zero** times in the installed binary. Longer work
   is detached by the hook itself (`Popen(start_new_session=True)`) and reported
   by `SessionStart`.
4. **The filesystem dominates hook cost, not the hook count.** `git status`:
   4 ms native vs 2045 ms on `/mnt/c` — 511×. On WSL, put the repo on the Linux
   side before tuning anything else.
5. **A producer with no reader produces nothing.** One probe wrote 735 rows over
   9 days that no code ever opened.
6. **An unpruned directory walk costs more than everything else.** 97.6 s vs
   0.36 s pruned — 270×.
7. **Hooks are scoped to the session, not the target repo.** Driving repo A from
   a session opened on repo B fires none of A's hooks.
8. **A loadable component with no description is worse than an inert one.** It
   can never fire, yet counts as loadable in every audit.
   `disable-model-invocation: true` is the honest third state.

## Updating an already-equipped project

```bash
bash setup-claude-code.sh --project-name my-project --update
```

⚠️ `--update` re-extracts the payload **and overwrites `CLAUDE.md`, `DEVLOG.md`
and `settings*.json`** with the generic templates. A `.bak` is a rollback you
have to remember to perform, not preservation — this was verified against a real
deployment whose `settings.json` registered 15 hooks, 5 of them project-specific.
To add tools without losing local config: copy the files and merge the hook
registrations by hand.

## License

[Apache License 2.0](./LICENSE).
