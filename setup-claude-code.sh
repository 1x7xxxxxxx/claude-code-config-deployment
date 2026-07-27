#!/usr/bin/env bash
# =============================================================================
# setup-claude-code.sh — Bootstrap Claude Code configuration for a new project
# =============================================================================
# Usage:
#   bash /path/to/setup-claude-code.sh --project-name "my-project"
#   bash /path/to/setup-claude-code.sh --project-name "my-project" --preset <name>
#   bash /path/to/setup-claude-code.sh --project-name "my-project" --update
#   bash /path/to/setup-claude-code.sh --dry-run --project-name "test"
#   bash /path/to/setup-claude-code.sh --version
#
# Prerequisites: Python 3.10+, run from repo root (git repo).
#
# Modes:
#   (default)  — fresh bootstrap. Creates .claude/, settings.json, settings.local.json,
#                CLAUDE.md, DEVLOG.md, dev-docs/. Skips files that already exist.
#   --update   — re-extract payload. Updates skills/agents/hooks/commands/rules/scripts/dev-docs.
#                ⚠️  It also OVERWRITES CLAUDE.md, DEVLOG.md and settings*.json with the generic
#                templates. This block used to say "PRESERVES … settings*.json (backed up to *.bak)":
#                a .bak is a rollback you must remember to perform, not preservation. Verified on a
#                real deployment whose settings.json registered 15 hooks, 5 project-specific — all
#                would have been replaced. To add tools WITHOUT losing local config: copy the files
#                and MERGE the hook registrations by hand.
#   --dry-run  — print the plan without touching the filesystem.
#   --version  — print SETUP_VERSION + sha256 of this script.
#
# Flags:
#   --project-name NAME    (required unless --version)
#   --preset NAME          ships extra payload setup-payload-${NAME}.tar.gz.b64 if present.
#                          Discovered by glob — list with: ls setup-payload-*.tar.gz.b64
#   --tests-dir PATH       used by session_summary hook (default "tests").
#   --pytest-cwd PATH      run pytest from a subdirectory.
#   --has-ml               toggle ML-specific dev-docs templates.
#   --has-docker           toggle Docker-aware sections in macro_architecture.md.
#   --has-timeseries       scaffold tools/stack_tables_catalog.md (time-series stub).
#   --has-relational       scaffold tools/stack_tables_catalog.md (PG stub).
#   --with-graphify        write tools/graphify_setup.md and try `pip install graphifyy`.
#   --with-mcp             write .mcp.json wiring graphify.serve to graphify-out/graph.json.
#   --force                allow downgrade of SETUP_VERSION (skip the warning).
#   --only LIST            comma-separated subtrees to copy, e.g. --only skills,agents.
#                          Default: all. Use it when the payload is older than the
#                          project for some files — check audit_fleet.py provenance first.
#
# Distribution:
#   This script depends on TWO sibling files: setup-payload-generic.tar.gz.b64
#   and (optionally) setup-payload-${preset}.tar.gz.b64. Distribute all three
#   together. To regenerate the payloads from the source-of-truth project, run
#   tools/dev/repack-claude-payloads.sh.
# =============================================================================

set -euo pipefail

# 2026.07.17 — RE-GENERICISED. The payload tagged 2026.07.07 shipped msdr's PROJECT-SPECIFIC
# inject_context.py (294 lines: stm32, fanuc, questdb, drilling_sessions) under the label "generic":
# it had been re-packed from a working tree without re-genericizing, so `--update` would have
# injected drilling-machine keywords into any repo. Fixed, and the class now ships as a signature
# (`foreign-repo-path-in-config` in templates/dev-docs/error-classes.md) so it cannot come back
# unseen. Also added: error-classes.md itself — scripts/audit_runner.py shipped WITHOUT the
# catalogue it reads, so a fresh install got a runner that exits 2. Orphan-by-construction, in the
# payload whose job is to catch that.
SETUP_VERSION="2026.07.27"

# ── Args ──────────────────────────────────────────────────────────────────────

PROJECT_NAME=""
TESTS_DIR="tests"
PYTEST_CWD=""
PRESET=""
HAS_ML=0
HAS_DOCKER=0
HAS_TIMESERIES=0
HAS_RELATIONAL=0
WITH_GRAPHIFY=0
WITH_MCP=0
DRY_RUN=0
UPDATE=0
FORCE=0
ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-name)    PROJECT_NAME="$2";    shift 2 ;;
        --tests-dir)       TESTS_DIR="$2";       shift 2 ;;
        --pytest-cwd)      PYTEST_CWD="$2";      shift 2 ;;
        --preset)          PRESET="$2";          shift 2 ;;
        --has-ml)          HAS_ML=1;             shift ;;
        --has-docker)      HAS_DOCKER=1;         shift ;;
        --has-timeseries)  HAS_TIMESERIES=1;     shift ;;
        --has-relational)  HAS_RELATIONAL=1;     shift ;;
        --with-graphify)   WITH_GRAPHIFY=1;      shift ;;
        --with-mcp)        WITH_MCP=1;           shift ;;
        --dry-run)         DRY_RUN=1;            shift ;;
        --update)          UPDATE=1;             shift ;;
        --force)           FORCE=1;              shift ;;
        --only)            ONLY="$2";            shift 2 ;;
        --version)
            hash="$(sha256sum "$0" 2>/dev/null | awk '{print $1}')"
            printf 'setup-claude-code.sh v%s\nsha256: %s\n' "$SETUP_VERSION" "${hash:-unknown}"
            exit 0 ;;
        --help|-h)
            sed -n '2,40p' "$0"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: --project-name is required" >&2
    echo "Usage: bash $0 --project-name \"my-project\" [--preset NAME] [--update] [--dry-run]" >&2
    exit 1
fi

SAFE_NAME="${PROJECT_NAME// /-}"
REPO_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_GENERIC="$SCRIPT_DIR/setup-payload-generic.tar.gz.b64"
PAYLOAD_PRESET=""
if [[ -n "$PRESET" ]]; then
    PAYLOAD_PRESET="$SCRIPT_DIR/setup-payload-${PRESET}.tar.gz.b64"
fi

# ── Pre-flight checks ─────────────────────────────────────────────────────────

if [[ ! -f "$PAYLOAD_GENERIC" ]]; then
    echo "Error: payload file not found: $PAYLOAD_GENERIC" >&2
    echo "       Distribute setup-claude-code.sh alongside setup-payload-generic.tar.gz.b64" >&2
    echo "       Regenerate via: bash tools/dev/repack-claude-payloads.sh" >&2
    exit 1
fi

if [[ -n "$PRESET" && ! -f "$PAYLOAD_PRESET" ]]; then
    echo "Error: preset payload not found: $PAYLOAD_PRESET" >&2
    echo "       Available presets: $(ls "$SCRIPT_DIR"/setup-payload-*.tar.gz.b64 2>/dev/null | xargs -n1 basename | sed -E 's/setup-payload-(.*)\.tar\.gz\.b64/\1/' | tr '\n' ' ')" >&2
    exit 1
fi

# Anti-downgrade guard.
if [[ -f .claude/.setup-version && "$FORCE" == "0" ]]; then
    INSTALLED_VERSION="$(cat .claude/.setup-version)"
    # Lexicographic compare works for YYYY.MM.DD format.
    if [[ "$INSTALLED_VERSION" > "$SETUP_VERSION" ]]; then
        echo "Error: refusing to downgrade." >&2
        echo "       Installed: $INSTALLED_VERSION" >&2
        echo "       This script: $SETUP_VERSION" >&2
        echo "       Pass --force to override." >&2
        exit 1
    fi
fi

# ── Dry-run helpers ───────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == "1" ]]; then
    DRY_PREFIX="[dry-run]"
    run() { echo "$DRY_PREFIX $*"; }
    run_pipe() { echo "$DRY_PREFIX $*"; }
else
    DRY_PREFIX=""
    run() { "$@"; }
    run_pipe() { eval "$*"; }
fi

run_mkdir()  { run mkdir -p "$@"; }
run_rm()     { run rm -f "$@"; }
run_chmod()  { run chmod "$@"; }
run_cp()     { run cp "$@"; }
run_write()  {
    local dest="$1"; shift
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "$DRY_PREFIX write $dest"
    else
        cat > "$dest"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────

echo ""
if [[ "$DRY_RUN" == "1" ]]; then
    echo "=== Claude Code Bootstrap — DRY RUN — $PROJECT_NAME ==="
elif [[ "$UPDATE" == "1" ]]; then
    echo "=== Claude Code Update — $PROJECT_NAME ==="
else
    echo "=== Claude Code Bootstrap — $PROJECT_NAME ==="
fi
echo "    Script version : $SETUP_VERSION"
echo "    Repo root      : $REPO_ROOT"
echo "    Tests dir      : $TESTS_DIR"
echo "    Preset         : ${PRESET:-<none>}"
# This said "UPDATE (preserves CLAUDE.md, DEVLOG.md, settings*.json via .bak)". It does NOT preserve
# them — `install_template` copies to .bak and then OVERWRITES with the generic template. A .bak is
# not preservation; it is a rollback you have to know to perform. Measured 2026-07-17 on a real
# deployment: `--update --dry-run` printed "preserves … settings*.json" one line above
# "install template → .claude/settings.json", on a repo whose settings.json registers 15 hooks, 5 of
# them project-specific. A declaration the code contradicts — the dominant bug of every project using
# this config, living in the installer that deploys the config.
[[ "$UPDATE" == "1" ]] && cat <<'WARN'
    Mode           : UPDATE
    ⚠️  --update OVERWRITES CLAUDE.md, DEVLOG.md and settings*.json with the generic
        templates (a .bak is written first — that is a rollback, not preservation).
        Any project-specific hook you registered will be GONE from settings.json.
        To add payload tools WITHOUT losing local config: copy the files by hand and
        MERGE the hook registrations into your existing settings.json.
WARN
echo ""

# ── [1/8] Directory structure ─────────────────────────────────────────────────

echo "[1/8] Creating directory structure..."

run_mkdir \
    .claude/hooks \
    .claude/skills \
    .claude/agents \
    .claude/sessions \
    .claude/rules \
    .claude/commands \
    .claude/scripts \
    ".claude/homunculus/${SAFE_NAME}" \
    .claude/dev-docs/work-in-progress \
    .claude/dev-docs/archives \
    .claude/dev-docs/research \
    .claude/dev-docs/reference \
    .claude/dev-docs/reports

# ── [2/8] Extract payload(s) ──────────────────────────────────────────────────

echo "[2/8] Extracting payload(s)..."

PAYLOAD_TMP="$(mktemp -d)"
trap 'rm -rf "$PAYLOAD_TMP"' EXIT

extract_payload() {
    local label="$1"
    local b64_path="$2"
    local stage="$PAYLOAD_TMP/$label"
    # Staging extraction always runs — it only touches /tmp, not the project. This
    # lets downstream copy_payload_subtree / install_template print accurate dry-run
    # plans (otherwise the staging dir would be empty and they'd silently no-op).
    mkdir -p "$stage"
    base64 -d "$b64_path" | tar xzf - -C "$stage"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "$DRY_PREFIX extract $label payload from $(basename "$b64_path") → $stage"
    fi
}

extract_payload generic "$PAYLOAD_GENERIC"
[[ -n "$PRESET" ]] && extract_payload "$PRESET" "$PAYLOAD_PRESET"

# Helper: copy payload subtree into a destination, with optional overwrite control.
# In --update mode, copies always overwrite (refresh). In default mode, never
# overwrites a CLAUDE.md or DEVLOG.md that already exists at the project root.
# --only restricts which subtrees are copied.
#
# Needed because the payload is not uniformly newer than the projects. Measured
# on this fleet: the payload's usage_report.py is 7.5K while trading_bot's is
# 15.2K and plugin_vst's is 8.5K, and session_summary.py / draft_rex.py /
# observe.py are likewise older in the payload. A blanket copy silently
# downgrades local work — including the telemetry readers the fleet audit
# depends on. Run `audit_fleet.py` and read the provenance section before
# choosing what to push.
subtree_selected() {
    [[ -z "$ONLY" ]] && return 0
    local want="$1"
    local IFS=','
    local item
    for item in $ONLY; do
        [[ "$item" == "$want" ]] && return 0
    done
    return 1
}

copy_payload_subtree() {
    local label="$1"   # "generic" or preset name
    local subdir="$2"  # e.g. "skills"
    local dest="$3"    # e.g. ".claude/skills"
    local stage="$PAYLOAD_TMP/$label/$subdir"
    if ! subtree_selected "$subdir"; then
        echo "    [skip] $subdir (not in --only)"
        return 0
    fi
    [[ -d "$stage" ]] || return 0
    run_mkdir "$dest"
    if [[ "$DRY_RUN" == "1" ]]; then
        local n
        n=$(find "$stage" -mindepth 1 -maxdepth 1 | wc -l)
        echo "$DRY_PREFIX copy $n entries from $label/$subdir → $dest"
        return
    fi
    # cp -rf preserves dirs and forces overwrite of existing files (needed for
    # --update mode, where target read-only files from the prior extraction would
    # otherwise block the re-copy).
    if compgen -G "$stage/*" > /dev/null; then
        cp -rf "$stage"/* "$dest/"
    fi
}

# Skills: generic first, then preset overlays (preset wins on collision).
copy_payload_subtree generic skills    .claude/skills

# Retire flat skill files superseded by a spec-layout directory.
#
# Claude Code only loads .claude/skills/<name>/SKILL.md; the payload used to
# ship flat .md files, which were never loaded. copy_payload_subtree uses
# `cp -rf` and never deletes, so after this migration a project would hold BOTH
# `foo.md` (inert) and `foo/SKILL.md` (live). The flat one is harmless but
# confusing, and it poisons the flat-vs-SKILL.md signal the fleet audit reads.
#
# Moved, never deleted: `.migrated/` is a dotdir, so the skill loader ignores it
# and the move is reversible with a single mv.
retire_flat_skills() {
    local sdir=".claude/skills"
    [[ -d "$sdir" ]] || return 0
    local moved=0 dest="$sdir/.migrated"
    local d name flat
    for d in "$sdir"/*/; do
        [[ -f "$d/SKILL.md" ]] || continue
        name="$(basename "$d")"
        flat="$sdir/$name.md"
        [[ -f "$flat" ]] || continue
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "$DRY_PREFIX retire flat skill $flat → $dest/$name.md"
        else
            mkdir -p "$dest"
            mv "$flat" "$dest/$name.md"
        fi
        moved=$((moved + 1))
    done
    [[ "$moved" -gt 0 ]] && echo "    ✓ $moved flat skill file(s) retired to $dest (reversible)"
    return 0
}
retire_flat_skills
copy_payload_subtree generic agents    .claude/agents
copy_payload_subtree generic hooks     .claude/hooks
copy_payload_subtree generic commands  .claude/commands
copy_payload_subtree generic rules     .claude/rules
copy_payload_subtree generic scripts   .claude/scripts
copy_payload_subtree generic tools     tools

if [[ -n "$PRESET" ]]; then
    copy_payload_subtree "$PRESET" skills   .claude/skills
    copy_payload_subtree "$PRESET" agents   .claude/agents
    copy_payload_subtree "$PRESET" hooks    .claude/hooks
    copy_payload_subtree "$PRESET" commands .claude/commands
    copy_payload_subtree "$PRESET" rules    .claude/rules
    copy_payload_subtree "$PRESET" scripts  .claude/scripts
fi

# Templates (CLAUDE.md, DEVLOG.md, settings.json, dev-docs/*, etc.) live under
# templates/ in the payload — they need TARGET-aware placement.
install_template() {
    local label="$1"
    local rel_in_template="$2"  # path relative to templates/ root
    local dest="$3"             # absolute path (or relative to REPO_ROOT)
    local src="$PAYLOAD_TMP/$label/templates/$rel_in_template"
    # --only gates templates too. It did not, and that was a real defect: a
    # `--only skills` run still installed GANTT.md, REX.md, api/ and
    # architecture/ into repos that had never asked for them, and one of those
    # templates carries a mermaid block that does not render — so a surgical
    # deployment turned an `audit_runner --static` from clean to two hits.
    # Templates are "documents", so they answer to the pseudo-subtree name
    # `templates`; pass `--only skills,templates` to get the old behaviour.
    subtree_selected "templates" || return 0
    [[ -f "$src" ]] || return 0
    if [[ -f "$dest" && "$UPDATE" == "0" ]]; then
        echo "    [skip] $dest already exists (use --update to refresh, with .bak backup)"
        return
    fi
    if [[ -f "$dest" && "$UPDATE" == "1" ]]; then
        run_cp "$dest" "$dest.bak"
    fi
    run_mkdir "$(dirname "$dest")"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "$DRY_PREFIX install template $rel_in_template → $dest"
    else
        # Substitute {{PROJECT_NAME}} and {{REPO_ROOT}} placeholders.
        sed -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
            -e "s|{{REPO_ROOT}}|${REPO_ROOT}|g" \
            "$src" > "$dest"
    fi
}

# ── [3/8] Settings (settings.json, settings.local.json) ───────────────────────

echo "[3/8] Writing settings files..."

# settings.json: preset overrides generic if a preset variant exists.
if [[ -n "$PRESET" && -f "$PAYLOAD_TMP/$PRESET/templates/.claude/settings.json" ]]; then
    install_template "$PRESET" .claude/settings.json .claude/settings.json
else
    install_template generic .claude/settings.json .claude/settings.json
fi

# settings.local.json: preset overrides generic.
if [[ -n "$PRESET" && -f "$PAYLOAD_TMP/$PRESET/templates/.claude/settings.local.json" ]]; then
    install_template "$PRESET" .claude/settings.local.json .claude/settings.local.json
else
    install_template generic .claude/settings.local.json .claude/settings.local.json
fi

# ── [4/8] CLAUDE.md + DEVLOG.md ───────────────────────────────────────────────

echo "[4/8] Writing CLAUDE.md + DEVLOG.md..."

install_template generic CLAUDE.md CLAUDE.md
install_template generic DEVLOG.md DEVLOG.md

# ── [5/8] dev-docs templates ──────────────────────────────────────────────────

echo "[5/8] Installing dev-docs templates..."

install_dev_docs() {
    local label="$1"
    local stage="$PAYLOAD_TMP/$label/templates/dev-docs"
    subtree_selected "templates" || return 0     # see install_template
    [[ -d "$stage" ]] || return 0
    while IFS= read -r -d '' src; do
        local rel="${src#"$stage"/}"
        local dest=".claude/dev-docs/$rel"
        # Skip ML-conditional templates if --has-ml not set.
        if [[ "$HAS_ML" == "0" && ( "$rel" == mlops/* || "$rel" == features/* || "$rel" == reference/ml-unified/* ) ]]; then
            continue
        fi
        if [[ -f "$dest" && "$UPDATE" == "0" ]]; then
            continue
        fi
        if [[ -f "$dest" && "$UPDATE" == "1" ]]; then
            run_cp "$dest" "$dest.bak"
        fi
        run_mkdir "$(dirname "$dest")"
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "$DRY_PREFIX install dev-doc $rel → $dest"
        else
            sed -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
                -e "s|{{REPO_ROOT}}|${REPO_ROOT}|g" \
                "$src" > "$dest"
        fi
    done < <(find "$stage" -type f -print0)
}

install_dev_docs generic
[[ -n "$PRESET" ]] && install_dev_docs "$PRESET"

# docs/adr template (if present in payload).
install_template generic docs/adr/ADR-TEMPLATE.md docs/adr/ADR-TEMPLATE.md

# ── [6/8] Optional scaffolds ──────────────────────────────────────────────────

if [[ "$HAS_TIMESERIES" -eq 1 || "$HAS_RELATIONAL" -eq 1 ]]; then
    install_template generic tools/stack_tables_catalog.md tools/stack_tables_catalog.md
fi

if [[ "$WITH_GRAPHIFY" -eq 1 ]]; then
    install_template generic tools/graphify_setup.md tools/graphify_setup.md

    if [[ "$DRY_RUN" == "0" ]] && command -v pip3 &>/dev/null; then
        echo "  Attempting: pip3 install graphifyy ..."
        if pip3 install graphifyy --quiet; then
            echo "  ✓ graphifyy installed"
        else
            echo "  ⚠ graphifyy install failed — install manually with: pip install graphifyy"
        fi
    fi
fi

if [[ "$WITH_MCP" -eq 1 ]]; then
    MCP_JSON=".mcp.json"
    if [[ -f "$MCP_JSON" && "$UPDATE" == "0" ]]; then
        echo "  [skip] .mcp.json — already exists"
    else
        PYTHON3_BIN="$(command -v python3 || echo /usr/bin/python3)"
        GRAPH_JSON="$REPO_ROOT/graphify-out/graph.json"
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "$DRY_PREFIX write $MCP_JSON"
        else
            cat > "$MCP_JSON" <<MCP_EOF
{
  "mcpServers": {
    "graphify": {
      "command": "${PYTHON3_BIN}",
      "args": ["-m", "graphify.serve", "${GRAPH_JSON}"]
    }
  }
}
MCP_EOF
            echo "  ✓ Created .mcp.json (graphify MCP server → ${GRAPH_JSON})"
            echo "  ⚠ Add .mcp.json to .gitignore — contains absolute paths."
        fi
    fi
fi

# ── [7/8] REX inject + version stamp ──────────────────────────────────────────

echo "[7/8] Finalizing REX blocks + stamping version..."

if [[ "$DRY_RUN" == "0" ]]; then
    python3 - <<'INJECT_REX_EOF'
import ast, re
from pathlib import Path

_FM_RE = re.compile(r"\A(---\n)(.*?)(\n---\s*\n)", re.DOTALL)

md_targets = []
# skills/ is deliberately excluded. Since skills moved to the spec layout
# (skills/<name>/SKILL.md), an rglob here would (a) stamp `rex: []` — a key
# outside the SKILL.md spec — into every skill on every install, and (b) worse,
# add frontmatter to auxiliary files inside skill folders (references/, assets/,
# STYLE_PRESETS.md, html-template.md), which must not carry any. The REX
# convention stays on agents, commands, rules, hooks and scripts.
for sub in ("agents", "commands", "rules"):
    d = Path(f".claude/{sub}")
    if d.exists():
        md_targets.extend(d.rglob("*.md"))

py_targets = []
for sub in ("hooks", "scripts"):
    d = Path(f".claude/{sub}")
    if d.exists():
        py_targets.extend(d.glob("*.py"))

modified = 0
for p in md_targets:
    text = p.read_text(encoding="utf-8")
    m = _FM_RE.match(text)
    if m:
        if re.search(r"^rex\s*:", m.group(2), re.MULTILINE):
            continue
        new_fm = m.group(1) + m.group(2).rstrip() + "\nrex: []" + m.group(3)
        p.write_text(new_fm + text[m.end():], encoding="utf-8")
    else:
        p.write_text("---\nrex: []\n---\n\n" + text, encoding="utf-8")
    modified += 1

for p in py_targets:
    src = p.read_text(encoding="utf-8")
    try:
        tree = ast.parse(src)
    except SyntaxError:
        continue
    doc = ast.get_docstring(tree) or ""
    if re.search(r"^rex\s*:", doc, re.MULTILINE):
        continue
    if (not tree.body
        or not isinstance(tree.body[0], ast.Expr)
        or not isinstance(tree.body[0].value, ast.Constant)
        or not isinstance(tree.body[0].value.value, str)):
        continue
    end_line = tree.body[0].end_lineno
    lines = src.splitlines(keepends=True)
    idx = end_line - 1
    closing = lines[idx].rstrip("\n").rstrip()
    triple = '"""' if closing.endswith('"""') else ("'''" if closing.endswith("'''") else None)
    if triple is None:
        continue
    prefix = closing[:-3]
    lines[idx] = prefix + "\n---\nrex: []\n---\n" + triple + lines[idx][len(closing):]
    p.write_text("".join(lines), encoding="utf-8")
    modified += 1

print(f"  ✓ REX blocks finalized ({modified} tool(s) received rex: [])")
INJECT_REX_EOF
fi

if [[ "$DRY_RUN" == "0" ]]; then
    run_mkdir .claude
    echo "$SETUP_VERSION" > .claude/.setup-version
    echo "  ✓ Stamped .claude/.setup-version = $SETUP_VERSION"
else
    echo "$DRY_PREFIX stamp .claude/.setup-version = $SETUP_VERSION"
fi

# ── [8/8] Post-bootstrap validation ───────────────────────────────────────────

echo "[8/8] Validating installation..."

if [[ "$DRY_RUN" == "1" ]]; then
    echo "$DRY_PREFIX skip validation (dry-run)"
else
    HOOK_ERRORS=0

    # 1. Syntax-check all hooks.
    for hook in .claude/hooks/*.py .claude/scripts/*.py; do
        [[ -f "$hook" ]] || continue
        if ! python3 -c "import ast; ast.parse(open('${hook}').read())" 2>/dev/null; then
            echo "    ✗ SYNTAX ERROR in ${hook}"
            HOOK_ERRORS=$((HOOK_ERRORS + 1))
        fi
    done

    # 2. Validate settings.json structure.
    if ! python3 -c "import json; json.load(open('.claude/settings.json'))" 2>/dev/null; then
        echo "    ✗ INVALID JSON in .claude/settings.json"
        HOOK_ERRORS=$((HOOK_ERRORS + 1))
    fi

    # 3. Verify every hook referenced in settings.json points to an existing file.
    python3 - <<'WIRING_EOF' || HOOK_ERRORS=$((HOOK_ERRORS + 1))
import json, re, sys
from pathlib import Path

cfg = json.load(open(".claude/settings.json"))
missing = []
for event, items in cfg.get("hooks", {}).items():
    for item in items:
        for hook in item.get("hooks", []):
            cmd = hook.get("command", "")
            for m in re.finditer(r"\.claude/hooks/[A-Za-z_]+\.py", cmd):
                rel = m.group(0)
                if not Path(rel).exists():
                    missing.append((event, rel))
if missing:
    for ev, p in missing:
        print(f"    ✗ {ev} hook references missing file: {p}")
    sys.exit(1)
WIRING_EOF

    # 4. Run validate_rex.py if present (non-fatal).
    if [[ -x .claude/scripts/validate_rex.py ]]; then
        if python3 .claude/scripts/validate_rex.py 2>/dev/null; then
            echo "    ✓ validate_rex.py passed"
        else
            echo "    ⚠ validate_rex.py reported issues (non-fatal)"
        fi
    fi

    if [[ "$HOOK_ERRORS" -gt 0 ]]; then
        echo "    ✗ $HOOK_ERRORS validation error(s)"
        exit 2
    fi
    echo "    ✓ All validation checks passed"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

count_dir() {
    local dir="$1"
    local pattern="$2"
    [[ -d "$dir" ]] || { echo 0; return; }
    # -mindepth 1 excludes the dir itself; -name '*' would otherwise match it.
    find "$dir" -mindepth 1 -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Claude Code bootstrap complete — $PROJECT_NAME"
echo "════════════════════════════════════════════════════════════"
echo "  .claude/skills/   → $(count_dir .claude/skills '*') entries"
echo "  .claude/agents/   → $(count_dir .claude/agents '*.md') entries"
echo "  .claude/hooks/    → $(count_dir .claude/hooks '*.py') entries"
echo "  .claude/commands/ → $(count_dir .claude/commands '*.md') entries"
echo "  .claude/rules/    → $(count_dir .claude/rules '*.md') entries"
echo "  .claude/scripts/  → $(count_dir .claude/scripts '*.py') entries"
echo "════════════════════════════════════════════════════════════"

if [[ "$UPDATE" == "0" && "$DRY_RUN" == "0" ]]; then
    echo ""
    # This line used to be load-bearing: DOMAINS shipped empty, inject_context.py is the ONLY
    # injector of rules/ + skills/, and filling it was delegated to this echo. Measured 2026-07-17
    # across 6 deployments: 4 left it empty. A 33% hit rate is not inattention — it is a manual step
    # at the end of a script nobody reads. `_discover_domains()` now makes it non-fatal: a skill or
    # rule that declares `keywords: a, b, c` in its frontmatter SELF-WIRES. So this is advice now,
    # and the signature `context-injector-is-a-no-op` (error-classes.md) is what enforces it.
    echo "Next: fill in CLAUDE.md placeholders."
    echo ""
    echo "  Context injection is SELF-WIRING: add \`keywords: a, b, c\` to a skill/rule frontmatter"
    echo "  and it registers itself — no hook edit. Check what is live with:"
    echo "      python3 -c \"import sys;sys.path.insert(0,'.claude/hooks');import inject_context as i;print(sorted(i.DOMAINS))\""
    echo ""
    echo "  Then seed .claude/dev-docs/error-classes.md as you find bugs, and sweep with:"
    echo "      python3 .claude/scripts/audit_runner.py --coverage    # no class may be un-swept"
    echo "      See .claude/dev-docs/reference/claude_code_deployment_guide.md"
fi
