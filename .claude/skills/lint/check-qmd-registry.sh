#!/bin/sh
# Guard: wiki/log.md must never enter the qmd semantic index.
#
# Why: qmd keys embeddings on a file's whole-content hash, so every append re-embeds the entire
# timeline, and a hit on it invites an ~80k-token whole-file read via `qmd get`. The exclusion lives
# in ~/.config/qmd/index.yml — OUTSIDE the vault and outside both git repos — so it can vanish
# silently (it did once, 2026-07-21, when a folder rename left 0 files indexed). This asserts it.
#
# Dormant-safe: silent no-op wording when qmd is absent or disabled (CLAUDE.md §10).
# Never reports clean on a broken probe: an empty listing or a missing positive control is a FAILURE,
# not a pass (CLAUDE.md §11).
#
# Usage: sh .claude/skills/lint/check-qmd-registry.sh [--vault ROOT] [vault-root] [collection]
#   exit 0 = clean or n/a · exit 1 = finding or broken probe · exit 2 = the root is not a vault
#
# Root guard (the 2026-08-26 standard, swept across this directory 2026-09-07): the root must
# hold raw/ AND wiki/, or the run refuses on stderr with exit 2 rather than reporting on a tree
# it was never pointed at (the .qmd-off opt-out is read from this root, so a wrong root silently
# ignores a disabled collection). Exit 2 is the cross-script guard code; the script's own
# premise failures keep their exit 1. --vault is accepted for parity with the sibling scripts;
# an unknown option is refused rather than read as the root.
USAGE="usage: check-qmd-registry.sh [--vault ROOT] [vault-root] [collection]"
ROOT=""
COLL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      shift
      [ $# -gt 0 ] || { echo "PROBE FAILED: --vault needs a directory argument" >&2; exit 2; }
      ROOT="$1" ;;
    --vault=*) ROOT="${1#--vault=}" ;;
    -*) echo "PROBE FAILED: unknown option $1 ($USAGE)" >&2; exit 2 ;;
    *)
      if [ -z "$ROOT" ]; then ROOT="$1"
      elif [ -z "$COLL" ]; then COLL="$1"
      else echo "PROBE FAILED: too many arguments ($USAGE)" >&2; exit 2; fi ;;
  esac
  shift
done
ROOT="${ROOT:-.}"
COLL="${COLL:-wiki}"

if [ ! -d "$ROOT/raw" ] || [ ! -d "$ROOT/wiki" ]; then
  echo "PROBE FAILED: $ROOT is not a vault root (no raw/ or wiki/)" >&2
  exit 2
fi

command -v qmd >/dev/null 2>&1 || { echo "qmd-registry: n/a (qmd not installed)"; exit 0; }
[ -e "$ROOT/.qmd-off" ] && { echo "qmd-registry: n/a (qmd disabled by .qmd-off)"; exit 0; }

LIST=$(qmd ls "$COLL" 2>&1)
N=$(printf '%s\n' "$LIST" | grep -c "qmd://$COLL/")
if [ "$N" -eq 0 ]; then
  echo "qmd-registry: PROBE FAILED — 'qmd ls $COLL' listed no files (collection missing, renamed, or index empty)"
  exit 1
fi

# Positive control: index.md is deliberately KEPT in the index, so its absence means the probe
# or the config is broken, not that the vault is clean.
if ! printf '%s\n' "$LIST" | grep -q "qmd://$COLL/index\.md$"; then
  echo "qmd-registry: PROBE FAILED — control missing (index.md is not indexed; $N files listed)"
  exit 1
fi

if printf '%s\n' "$LIST" | grep -q "qmd://$COLL/log\.md$"; then
  echo "qmd-registry: FAIL — log.md is in the qmd index; restore 'ignore: [\"**/log.md\"]' on the $COLL collection in ~/.config/qmd/index.yml"
  exit 1
fi

echo "qmd-registry: ok — log.md excluded ($N files indexed; control: index.md present)"
exit 0
