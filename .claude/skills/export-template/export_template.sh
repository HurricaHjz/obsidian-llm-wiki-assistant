#!/usr/bin/env bash
# export_template.sh — sync THIS LLM-Wiki framework with its public GitHub repo, ONE direction per run.
#
#   bash export_template.sh [OUT_DIR]               fresh build  (default OUT_DIR = <vault>/template-export)
#   bash export_template.sh --push <repo>           vault → repo : overlay framework + packaging into a clone
#   bash export_template.sh --pull <repo>           repo → vault : PREVIEW (git pull + diff; writes NOTHING)
#   bash export_template.sh --pull <repo> --apply   repo → vault : APPLY (CLAUDE/Manual/skills + README/LICENSE at root, screenshot in assets/, + payload)
#       add  --with-graph  to also pull .obsidian/graph.json (colour scheme); never app/appearance/core-plugins.
#   (--sync is kept as an alias for --push.)
#
# Exactly ONE direction per invocation — passing --pull AND --push together is an error.
# Read-only on the vault EXCEPT `--pull --apply`, which updates ONLY framework files + this skill's payload/,
# and NEVER your knowledge (wiki/ raw/ output/ + your own assets media) or your .obsidian runtime config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/../../.." && pwd)"                 # vault root = 3 levels up
[ -f "$SRC/CLAUDE.md" ] || { echo "ERROR: $SRC has no CLAUDE.md — not a vault root"; exit 1; }
KIT="$SCRIPT_DIR/payload"   # the publish payload (build machinery: setup.sh, git dotfiles, seed demo) lives in this skill
[ -d "$KIT/example" ] || { echo "ERROR: skill payload missing at $KIT"; exit 1; }

# Images under assets/ are shipped only when the README references them (force-tracked).
# Keep the `!` exceptions in payload/gitignore.txt in sync, or the file copies but stays uncommittable.
readme_images() { grep -oE 'assets/[A-Za-z0-9._-]+\.(png|jpg|jpeg|gif|webp)' "$1" 2>/dev/null | sort -u || true; }

strip_junk() {   # drop regenerable cache / OS junk so it never ships or pollutes a pull diff
  for d in "$@"; do
    [ -e "$d" ] && find "$d" \( -name __pycache__ -o -name '*.pyc' -o -name .DS_Store \) -exec rm -rf {} + 2>/dev/null
  done
  return 0
}
strip_junk "$KIT"   # keep the payload mirror clean

list_skills() {  # echo EVERY skill folder under $1/.claude/skills — auto-discovery, so new skills ship/sync with zero edits.
  [ -d "$1/.claude/skills" ] || return 0   # export-template is included (users need its --pull to update); see SKILL.md.
  for d in "$1/.claude/skills"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; d="${d##*/}"
    printf '%s\n' "$d"
  done
}

list_agents() {  # echo EVERY subagent definition FILE under $1/.claude/agents — same auto-discovery contract as
  [ -d "$1/.claude/agents" ] || return 0   # list_skills, so a new definition ships with zero edits. FILES only:
  for f in "$1/.claude/agents"/*.md; do    # a lane's `memory` directory is excluded by construction, never shipped.
    [ -f "$f" ] || continue
    f="${f##*/}"
    printf '%s\n' "$f"
  done
}

# ── vault-owned framework files: vault → $1  (build & push) ─────────────────────────────────
copy_framework() {
  local D="$1" s STRAY
  # cwd-shift guard (known-issues 2026-08-21→23): a wiki/raw/output tree nested in a skill dir means a
  # relative write landed inside shipped machinery — refuse to package knowledge. payload/example/ is the demo seed.
  STRAY="$(find "$SRC/.claude/skills" -mindepth 2 -type d \( -name wiki -o -name raw -o -name output \) ! -path '*/payload/example/*')"
  [ -n "$STRAY" ] && { echo "ERROR: knowledge-shaped dirs inside .claude/skills — fix before shipping:"; echo "$STRAY"; exit 1; }
  cp "$SRC/CLAUDE.md" "$SRC/MANUAL.md" "$D/"
  mkdir -p "$D/.claude/skills"
  for s in $(list_skills "$SRC"); do
    rm -rf "$D/.claude/skills/$s"; cp -R "$SRC/.claude/skills/$s" "$D/.claude/skills/"
  done
  if [ -n "$(list_agents "$SRC")" ]; then    # known-issues 2026-08-27: the delegate skill's routing table
    mkdir -p "$D/.claude/agents"             # named definitions the payload never shipped
    for a in $(list_agents "$SRC"); do
      rm -f "$D/.claude/agents/$a"; cp "$SRC/.claude/agents/$a" "$D/.claude/agents/"
    done
  fi
  mkdir -p "$D/.obsidian"
  for f in graph.json app.json core-plugins.json appearance.json; do
    [ -f "$SRC/.obsidian/$f" ] && cp "$SRC/.obsidian/$f" "$D/.obsidian/"
  done
  rm -rf "$D/examples/seed"; mkdir -p "$D/examples/seed"          # the demo (tracked, separate from wiki/raw)
  cp -R "$KIT/example/." "$D/examples/seed/"
  strip_junk "$D/.claude/skills" "$D/examples"                    # never ship __pycache__/*.pyc/.DS_Store
}

# ── publish-only packaging: vault root + payload → $1  (build & push) ────────────────────────
copy_packaging() {
  local D="$1" f
  for f in README.md LICENSE.md; do                                                 # canonical at the vault root
    [ -f "$SRC/$f" ] || { echo "ERROR: $SRC/$f missing — it is canonical at the vault root"; exit 1; }
    cp "$SRC/$f" "$D/$f"
  done
  rm -f "$D/LICENSE" "$D/CONTRIBUTING.md"; rm -rf "$D/docs"                         # drop legacy no-ext LICENSE, retired CONTRIBUTING + old docs/ folder
  mkdir -p "$D/assets"
  for img in $(readme_images "$SRC/README.md"); do
    if [ -f "$SRC/$img" ]; then cp "$SRC/$img" "$D/$img"; fi                        # README images (force-tracked)
  done
  cp "$KIT/gitignore.txt"      "$D/.gitignore"
  cp "$KIT/gitattributes.txt"  "$D/.gitattributes"
  cp "$KIT/setup.sh"           "$D/setup.sh"; chmod +x "$D/setup.sh"
}

# ── empty content skeleton (.gitkeep) — NO content, NO index/log (those are gitignored) ─────
make_skeleton() {
  local D="$1"
  for d in 1-articles 2-papers 3-notes 4-webinfo 5-blogs 6-social 7-reviews 8-transcripts 9-originals archives duplicates; do
    mkdir -p "$D/raw/$d"; touch "$D/raw/$d/.gitkeep"; done
  for d in concepts entities tools models benchmarks sources syntheses developments maps user; do
    mkdir -p "$D/wiki/$d"; touch "$D/wiki/$d/.gitkeep"; done
  mkdir -p "$D/assets" "$D/output" "$D/attic"; touch "$D/assets/.gitkeep" "$D/output/.gitkeep" "$D/attic/.gitkeep"
}

# ── tune the template's Obsidian config: keep the demo + build dirs out of the graph (idempotent) ──
apply_fixes() {
  local D="$1"
  python3 - "$D/.obsidian/app.json" <<'PY' || true
import json, sys
p = sys.argv[1]
try: d = json.load(open(p))
except Exception: sys.exit(0)
flt = d.get("userIgnoreFilters", [])
for x in ["examples/", "template-export/"]:
    if x not in flt: flt.append(x)
d["userIgnoreFilters"] = flt
json.dump(d, open(p, "w"), indent=2)
PY
  python3 - "$D/.obsidian/graph.json" <<'PY' || true
import json, sys
p = sys.argv[1]
try: g = json.load(open(p))
except Exception: sys.exit(0)
# drop volatile per-session view-state so the shipped graph.json stays deterministic (no push noise
# from zooming/searching/collapsing panels); keep colorGroups + the display/force config that matters.
for k in ("scale", "close", "search", "collapse-filter", "collapse-color-groups", "collapse-display", "collapse-forces"):
    g.pop(k, None)
json.dump(g, open(p, "w"), indent=2)
PY
  # drop vault-local snippet enablement from the shipped appearance.json — the snippets themselves
  # (.obsidian/snippets/) never ship, so the key would dangle in the template (added 2026-08-23).
  python3 - "$D/.obsidian/appearance.json" <<'PY2' || true
import json, sys
p = sys.argv[1]
a = json.load(open(p))
a.pop("enabledCssSnippets", None)
json.dump(a, open(p, "w"), indent=2)
PY2
  # Strip VAULT-LOCAL blocks from every shipped Markdown file — content the vault needs but the
  # template must never ship (owner-specific setup: tier-3 activation wiring, machine paths, burner).
  # Marker: <!-- vault-local:begin --> … <!-- vault-local:end -->. General conditional-compile, so any
  # future vault-specific block ships nothing by wrapping it (added 2026-08-26).
  find "$D" -name '*.md' -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
    python3 - "$f" <<'PY3' || true
import re, sys
p = sys.argv[1]
try: t = open(p, encoding="utf-8").read()
except Exception: sys.exit(0)
n = re.sub(r"[ \t]*<!-- *vault-local:begin *-->.*?<!-- *vault-local:end *-->[ \t]*\n?", "", t, flags=re.S)
if n != t: open(p, "w", encoding="utf-8").write(n)
PY3
  done
}

# ── pull publish files from the repo: README/LICENSE → vault root, screenshot → assets/, rest → payload ──
refresh_local() {
  local R="$1" f
  for f in README.md LICENSE.md; do                                                 # canonical at the vault root
    [ -f "$R/$f" ] && cp "$R/$f" "$SRC/$f"
  done
  mkdir -p "$SRC/assets"
  for img in $(readme_images "$R/README.md"); do
    if [ -f "$R/$img" ]; then cp "$R/$img" "$SRC/$img"; fi
  done
  for pair in ".gitignore:gitignore.txt" ".gitattributes:gitattributes.txt" "setup.sh:setup.sh"; do
    s="${pair%%:*}"; d="${pair##*:}"; [ -f "$R/$s" ] && cp "$R/$s" "$KIT/$d"
  done
  [ -d "$R/examples/seed" ] && { rm -rf "$KIT/example"; mkdir -p "$KIT/example"; cp -R "$R/examples/seed/." "$KIT/example/"; }
  strip_junk "$KIT"
}

# ── parse: pick exactly ONE direction ───────────────────────────────────────────────────────
WANT_PULL=0; WANT_PUSH=0; APPLY=0; WITH_GRAPH=0; REPO=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pull)        WANT_PULL=1; shift; REPO="${1:?--pull needs a path to your repo clone}"; shift;;
    --push|--sync) WANT_PUSH=1; shift; REPO="${1:?--push needs a path to your repo clone}"; shift;;
    --apply)       APPLY=1;      shift;;
    --with-graph)  WITH_GRAPH=1; shift;;
    *)             POS+=("$1");  shift;;
  esac
done
[ "$WANT_PULL" = 1 ] && [ "$WANT_PUSH" = 1 ] && { echo "ERROR: pick ONE direction — --pull OR --push, never both."; exit 1; }

# ── PULL mode (repo → vault) ────────────────────────────────────────────────────────────────
if [ "$WANT_PULL" = 1 ]; then
  REPO="$(cd "$REPO" && pwd)"
  [ -d "$REPO/.git" ]      || { echo "ERROR: $REPO is not a git clone — clone it first: git clone <repo-url> $REPO (RUNBOOK section D)"; exit 1; }
  [ -f "$REPO/CLAUDE.md" ] || { echo "ERROR: $REPO has no CLAUDE.md — not the framework repo"; exit 1; }
  echo "PULL ← $REPO   (your knowledge — wiki/ raw/ output/ + your assets media — and .obsidian config are never touched)"
  git -C "$REPO" pull --ff-only || { echo "ERROR: 'git pull' failed; resolve it in $REPO, then retry."; exit 1; }

  echo "--- framework changes pull would apply to your vault ---"
  CHG=0
  for f in CLAUDE.md MANUAL.md README.md LICENSE.md; do
    diff -q "$REPO/$f" "$SRC/$f" >/dev/null 2>&1 || { echo "  update  $f"; CHG=1; }
  done
  for img in $(readme_images "$REPO/README.md"); do
    if [ -f "$REPO/$img" ]; then
      diff -q "$REPO/$img" "$SRC/$img" >/dev/null 2>&1 || { echo "  update  $img"; CHG=1; }
    fi
  done
  for s in $(list_skills "$REPO"); do
    diff -rq -x __pycache__ -x '*.pyc' -x .DS_Store "$REPO/.claude/skills/$s" "$SRC/.claude/skills/$s" >/dev/null 2>&1 || { echo "  update  .claude/skills/$s"; CHG=1; }
  done
  for a in $(list_agents "$REPO"); do
    diff -q "$REPO/.claude/agents/$a" "$SRC/.claude/agents/$a" >/dev/null 2>&1 || { echo "  update  .claude/agents/$a"; CHG=1; }
  done
  if [ "$WITH_GRAPH" = 1 ] && [ -f "$REPO/.obsidian/graph.json" ]; then
    diff -q "$REPO/.obsidian/graph.json" "$SRC/.obsidian/graph.json" >/dev/null 2>&1 || { echo "  update  .obsidian/graph.json"; CHG=1; }
  fi
  [ "$CHG" = 0 ] && echo "  (vault framework already matches the repo)"
  echo "  + payload refresh (setup.sh, .gitignore/.gitattributes, seed demo)"

  if [ "$APPLY" != 1 ]; then
    G=""; [ "$WITH_GRAPH" = 1 ] && G=" --with-graph"
    echo
    echo "PREVIEW only — nothing written. To apply, re-run with --apply:"
    echo "  bash .claude/skills/export-template/export_template.sh --pull \"$REPO\" --apply$G"
    exit 0
  fi

  cp "$REPO/CLAUDE.md" "$SRC/CLAUDE.md"
  cp "$REPO/MANUAL.md" "$SRC/MANUAL.md"
  for s in $(list_skills "$REPO"); do                    # per-name copy, incl. export-template itself —
    rm -rf "$SRC/.claude/skills/$s"; cp -R "$REPO/.claude/skills/$s" "$SRC/.claude/skills/"   # replacing the running script is Unix-safe (old inode stays open; new version applies next run)
  done
  if [ -n "$(list_agents "$REPO")" ]; then
    mkdir -p "$SRC/.claude/agents"
    for a in $(list_agents "$REPO"); do cp "$REPO/.claude/agents/$a" "$SRC/.claude/agents/"; done
  fi
  [ "$WITH_GRAPH" = 1 ] && [ -f "$REPO/.obsidian/graph.json" ] && cp "$REPO/.obsidian/graph.json" "$SRC/.obsidian/graph.json"
  refresh_local "$REPO"
  echo "DONE — vault framework updated from $REPO. Re-read CLAUDE.md; reopen Obsidian if skills/graph changed."
  exit 0
fi

# ── PUSH mode (vault → repo) ────────────────────────────────────────────────────────────────
if [ "$WANT_PUSH" = 1 ]; then
  REPO="$(cd "$REPO" && pwd)"
  [ -d "$REPO/.git" ] || { echo "ERROR: $REPO is not a git clone — clone it first: git clone <repo-url> $REPO (RUNBOOK section D)"; exit 1; }
  echo "PUSH → overlaying framework + packaging into $REPO (knowledge never copied; .git untouched)"
  copy_framework "$REPO"
  for d in "$REPO/.claude/skills"/*/; do            # repo-side dirs the vault retired (known-issues 2026-08-22)
    s="$(basename "$d")"
    [ -d "$SRC/.claude/skills/$s" ] || echo "STALE repo-side skill '$s' (vault has none) — propose at the diff gate:  git -C \"$REPO\" rm -r .claude/skills/$s"
  done
  for a in $(list_agents "$REPO"); do               # same rule for a vault-retired agent definition
    [ -f "$SRC/.claude/agents/$a" ] || echo "STALE repo-side agent '$a' (vault has none) — propose at the diff gate:  git -C \"$REPO\" rm .claude/agents/$a"
  done
  copy_packaging "$REPO"     # publish files: README/LICENSE + screenshot from the vault; machinery from payload
  make_skeleton  "$REPO"     # idempotent (re-touches .gitkeep); creates the skeleton on a first publish
  apply_fixes    "$REPO"
  echo "DONE. Guided publish next: git -C \"$REPO\" pull --ff-only → add -A → diff → confirm → commit → push"
  exit 0
fi

# ── FRESH BUILD (standalone content-free copy) ──────────────────────────────────────────────
OUT="${POS[0]:-$SRC/template-export}"
echo "BUILD → $OUT"
rm -rf "$OUT"; mkdir -p "$OUT"
copy_framework "$OUT"
make_skeleton  "$OUT"
copy_packaging "$OUT"
apply_fixes    "$OUT"

# ── verify ───────────────────────────────────────────────────────────────────────────────
echo "--- shipped skills (auto-discovered, incl. export-template) ---"; ls "$OUT/.claude/skills" | tr '\n' ' '; echo
echo "--- shipped agent definitions (auto-discovered) ---"; ls "$OUT/.claude/agents" 2>/dev/null | tr '\n' ' '; echo
echo "--- wiki/raw ship empty (only .gitkeep)? ---"; find "$OUT/wiki" "$OUT/raw" -type f ! -name .gitkeep | sed 's/^/  STRAY: /' || true
echo "--- top-level ---"; ls -1A "$OUT"
echo "DONE → $OUT   (next: see .claude/skills/export-template/RUNBOOK.md → Publish)"
