# claude-code-config-deployment

Opinionated bootstrap for new Claude Code projects. One script drops a curated
`.claude/` tree — hooks, agents, skills, rules, slash commands — plus a starter
`CLAUDE.md` into any project directory.

**The installer writes into `$(pwd)`, not into its own directory.** Stand in the
target project and call the script by path — `cd`-ing into this clone and running
it there installs the configuration into *this repo*, which is the first thing
people do after `git clone`. Since 2026-08-31 the script refuses that case
instead of silently doing it.

```bash
# 1. Get the distribution (once), somewhere OUTSIDE your project
git clone https://github.com/<owner>/claude-code-config-deployment ~/tools/ccd

# 2. Bootstrap a project — from the TARGET repo root
cd /path/to/my-new-project
bash ~/tools/ccd/setup-claude-code.sh --project-name my-new-project

# Everything the payload actually carries — hooks, rules, workflows, skills:
bash ~/tools/ccd/setup-claude-code.sh --project-name my-new-project \
     --preset extended --with-skills

# Print the plan without touching the filesystem
bash ~/tools/ccd/setup-claude-code.sh --project-name my-new-project --dry-run

# Print version + payload SHA256
bash ~/tools/ccd/setup-claude-code.sh --version
```

Prerequisites: Bash, Python 3.10+ (with PyYAML), and a git repo to install into.
The payloads are embedded base64, so the installer needs no network access at
install time.

Two caveats the script does not enforce for you: the **git repo is a convention,
not a check** — the installer runs happily in a plain directory and only the
hooks that shell out to `git` will misbehave; and on Windows you must read the
next section before cloning.

Counts and behaviour on this page were verified on 2026-08-19 against Claude Code
2.1.235; the tables and the fixes below were re-verified on 2026-08-31 by
installing each variant into a fresh repository.

## Windows: the CRLF trap

Git for Windows ships `core.autocrlf=true`, so a plain `git clone` on Windows
rewrites every tracked text file to CRLF. That breaks both deliverables here, and
the second failure is silent until you have fixed the first:

```
setup-claude-code.sh: line 58: $'\r': command not found
: invalid option name line 59: set: pipefail
```

`bash` has read `set -euo pipefail\r`. Repairing only the script is not enough —
`setup-payload-*.tar.gz.b64` is corrupted the same way, and `base64 -d` rejects
the stray `\r`, so extraction fails *after* directories have been created.

This repo now carries a `.gitattributes` pinning `eol=lf` (and marking the
payloads binary), so fresh clones are correct. **An existing bad clone is not
retroactively fixed by it** — repair it:

```bash
git config core.autocrlf false && git config core.eol lf
git rm --cached -r . >/dev/null && git reset --hard
file setup-claude-code.sh          # must NOT say "with CRLF line terminators"
```

Both failure modes are now caught before anything is written: the script
self-checks its own line endings on its first executable line (it has to be a
single line ending in a comment — under CRLF every `if … then` is already a
syntax error), and the pre-flight checks the payloads before decoding.

## What ships here

| File | Role |
|---|---|
| `setup-claude-code.sh` | The installer. `--help` lists every flag. |
| `.gitattributes` | Pins `eol=lf` and marks the payloads binary. Not cosmetic — without it a Windows clone cannot run the installer at all. |
| `setup-payload-generic.tar.gz.b64` | The base payload it unpacks: 3 agents, 1 command, 3 scripts, and the `CLAUDE.md` / `DEVLOG.md` / dev-docs templates. No hooks, no rules, no skills — see the table below. |
| `setup-payload-ml.tar.gz.b64` | `--preset ml` overlay — ML/data-science skills, agents and rules, kept out of the base so a C++ or workflow project does not pay for them. |
| `setup-payload-extended.tar.gz.b64` | `--preset extended` overlay — the larger command and skill set. |

Presets are discovered by glob: `ls setup-payload-*.tar.gz.b64` lists what this
copy can install.

## What lands in `.claude/`, per preset

Counted by running each variant into a fresh git repo **with `--with-skills`**,
re-measured 2026-08-31. Not what the payload is meant to contain — what it puts
on disk. The two right-hand columns did not exist before 2026-08-31, because the
installer never copied them (see the fix log).

| | agents | commands | hooks | rules | skills | scripts | workflows | tools/ |
|---|---|---|---|---|---|---|---|---|
| *(no preset)* | 3 | 1 | 0 | 0 | 0 | 3 | 0 | 0 |
| `--preset ml` | 7 | 1 | 0 | 5 | 8 | 3 | 0 | 0 |
| `--preset extended` | 11 | 14 | 13 | 2 | 14 | 11 | 5 | 1 |

Without `--with-skills` the skills column is **0 on every row** — that is the
point of the opt-in, and as of 2026-08-31 it finally holds for presets too.
`tools/` lands at the repo root, not under `.claude/`.

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
| `workflows/` | Multi-step engineering loops (`engineering-loop.js`, bug-resolution, architecture-change…). **`extended` only**, and never installed at all before 2026-08-31. |
| `tools/` | Repo-root, not under `.claude/`: `generate-dev-docs.py`. Same blind spot, same fix. |

### `--with-skills` gates the preset overlays (fixed 2026-08-31)

Skills are opt-in since 2026-08-03, on the measurement that they fired once in
222 cells and cost +9 432 tokens of context per session. The gate used to wrap
only the **base** payload's skills — a tree that is empty — so the flag was inert
where it mattered: `--preset extended` installed its skills either way. The
opt-in that measurement paid for did not exist for the only payloads that have
skills to opt out of.

Now measured both ways on `extended`: **0 skills without the flag, 14 with.**

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

## Fix log — 2026-08-31

Six defects, found by installing this distribution onto a Windows machine and
then auditing what actually landed. Each is listed with the symptom you would
have seen, because five of the six were silent.

| # | Defect | Symptom | Fix |
|---|---|---|---|
| 1 | No `.gitattributes`; Git for Windows checks out CRLF | `line 58: $'\r': command not found`, then `set: pipefail` — installer will not start | `.gitattributes` pins `eol=lf`, payloads marked binary |
| 2 | CRLF also corrupts `setup-payload-*.b64` | **Silent until #1 is fixed**, then `base64 -d` fails mid-extraction, after directories exist | Pre-flight rejects CRLF payloads before writing anything |
| 3 | Installer targets `$(pwd)` with no guard | Running it from this clone installs `.claude/` into the distribution itself | Refuses when `$(pwd)` is the script's own directory, and prints the correct invocation |
| 4 | `--with-skills` did not gate preset skills | **Silent.** Flag accepted, ignored; the documented opt-in never applied to any payload that has skills | Preset skills gated by the same condition as generic |
| 5 | Preset `workflows/` and `tools/` never copied | **Silent.** 5 workflows + `generate-dev-docs.py` (37 KB) unpacked to staging, then discarded; no count reported them | Both trees copied for presets; both now have a column in the table above |
| 6 | `validate_rex.py` frontmatter regex unanchored | `2 without rex key` on every install — one of them **falsely**: the block was there and hidden | Regex anchored to whole lines; `select_tests.py` given the block it genuinely lacked |

Defect 6 is the instructive one. `_DOCSTRING_FM_RE` was `r"---\n(.*?)\n---"`,
unanchored — so it also matched the last three dashes of an RST section
underline (`Pourquoi cet outil existe` / `-------------------------`). The two
scripts it flagged are the only two in the payload that use RST underlines. For
`check_ci_waste.py` the parser captured prose, `yaml.safe_load` raised, and the
file was reported as carrying no lesson while it carried **two** — a validator
that hides the very knowledge it exists to protect. Adding a `rex:` block would
not have helped; the parser had to be fixed first.

After the fix, on a fresh `extended` install: `55 tool(s) OK, 0 without rex key,
0 entry error(s)` — against `49 tool(s), 2 without` before. The corpus grew by
the six components defect 5 had been discarding.

Payloads `generic` and `extended` were repacked (`ml` is untouched). Verified:
member lists identical to the originals, and exactly two files differ —
`scripts/select_tests.py` and `scripts/validate_rex.py`.

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
