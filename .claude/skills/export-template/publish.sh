#!/usr/bin/env bash
# publish.sh — the export-template publish flow as ONE chain, so no step can be skipped by hand.
#
# The flow this owns is SKILL.md's publish steps 1–4 and the RUNBOOK's maintain section:
#   pull → overlay → stage → drift check → payload gate → release gate → throttle gate → recap
# and it STOPS there with nothing committed. Only `--publish "<word>" --message "<msg>"` — the
# owner's go on the presented recap, passed verbatim by the caller — continues to commit and push.
# It exists because a hand-chained publish committed past a failed gate: a `;` between two steps,
# or an exit code eaten by a command substitution, is enough. Here every step is an explicit `&&`
# link whose failure ends the run with a named `publish.sh: STOP <step> — …` line on stderr and a
# non-zero code; `set -euo pipefail` is the belt, never the argument.
#
# USAGE
#   bash publish.sh --release <ver> [--vault <dir>] [--recap <file>] <repo-clone>
#   bash publish.sh --release <ver> --publish "<the owner's word>" --message "<msg>" \
#                   --approved <recap-digest> <repo-clone>
#
# FLAGS
#   --release <ver>   REQUIRED — the candidate version, derived by the caller per SKILL.md's recap
#                     rule (the repo's `git log` AND the vault log's `export |` entries, at recap
#                     time). Required rather than optional because an absent version would silently
#                     skip the release gate, which is the only probe that turns a provisional
#                     allowlist entry the candidate has reached into a finding.
#   --publish <word>  the owner's go on the recap, verbatim; needs --message AND --approved. Absent,
#                     the chain stops at the recap. The script never asks: consent reaches it as an
#                     argument.
#   --message <msg>   the commit message the owner gave or confirmed; needs --publish.
#   --approved <dig>  the `recap-digest` the recap-only run printed as its last line. It is what
#                     binds the owner's word to the recap the owner actually saw: without it a
#                     --publish run would re-pull, re-overlay and push a tree nobody presented. The
#                     three publish flags come as a set — all of them, or none.
#   --recap <file>    where the recap is written (default: <vault>/output/publish-recap.txt, beside
#                     the gate's other owner-local file). The export never ships `output/` — the
#                     overlay copies the framework files it knows by name, and the shipped
#                     template's own .gitignore excludes the directory as well. That says nothing
#                     about THIS vault's git repository: unless its .gitignore excludes `output/`,
#                     the vault's own private backup commits every recap, owner word included.
#   --vault <dir>     the vault whose strings the payload gate derives and whose throttle is read.
#                     Default: three directories above this script, the same derivation
#                     publish_guard.py's --vault overrides. This copy's own export_template.sh
#                     reads its source vault from its own location, so an override that names a
#                     different tree is refused rather than silently overlaying the wrong vault.
#
# EXIT CODES
#   0  the chain reached the recap and stopped, nothing committed — or, with --publish, committed
#      and pushed.
#   1  a gate refused the publish: drift, a payload-gate finding, a release-gate finding, a
#      throttle finding — or the approval check found the approved recap or its tree no longer on
#      disk as approved. Nothing is committed.
#   2  a broken premise: usage, a missing script, a repo that is not a git clone, the vault passed
#      as the repo, a vault it cannot read, a recap it cannot write or (under --publish) cannot
#      find, a gate that exited 2. Nothing is committed.
#   3  a step of the chain failed: pull, overlay, stage, commit or push.
#
# WHAT IT WRITES — the whole of it:
#   · the recap file (default <vault>/output/publish-recap.txt): the only file it writes in the
#     vault, and only on a recap-only run. Under --publish the approved recap is never truncated;
#     it gains the publish result appended, and only after the push succeeds.
#   · the repo clone, on a recap-only run: the overlay export_template.sh copies in, and the git
#     index `git add -A` stages. Both are written BEFORE the gates run, so a gate STOP leaves the
#     clone with the overlay in its working tree and everything staged, uncommitted —
#     `git -C <repo> reset -q` clears the index, and the next run overlays and stages again.
#   · under --publish: the commit and the push, and nothing else. That run does not pull, does not
#     overlay and does not stage: it re-gates the index as it stands, which is the index the
#     approved recap named by its tree hash, so the committed tree is the one the recap described.
#
# WHAT IT DOES NOT DO — by the two-repos rule and SKILL.md's own division:
#   · the private vault backup (SKILL.md step 7) is a separate command outside this chain;
#   · the `export |` entry in the vault log (step 5) and the build-directory cleanup (step 6) stay
#     with the caller, which is what reports the result.

set -euo pipefail

STAMP="$$-$(date -u +%Y%m%dT%H%M%SZ)"          # this invocation, for the recap's completion marker
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {                                        # $1 exit code, rest the named line
  local code="$1"; shift
  printf 'publish.sh: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  printf 'usage: bash publish.sh --release <ver> [--vault <dir>] [--recap <file>] '
  printf '[--publish "<word>" --message "<msg>" --approved <recap-digest>] <repo-clone>\n'
}

# ── arguments ────────────────────────────────────────────────────────────────────────────────
REPO=""; VAULT=""; RECAP=""; RELEASE=""; OWNER_WORD=""; MESSAGE=""; APPROVED=""
need_value() { [ "$2" -lt "$3" ] || die 2 "STOP premise — $1 needs a value"; }
[ "$#" -gt 0 ] || { usage >&2; die 2 "STOP premise — no arguments"; }   # bash 3.2: an empty array under set -u
ARGS=("$@")
i=0
while [ "$i" -lt "${#ARGS[@]}" ]; do
  a="${ARGS[$i]}"
  case "$a" in
    --release|--vault|--recap|--publish|--message|--approved)
      need_value "$a" "$((i + 1))" "${#ARGS[@]}"
      v="${ARGS[$((i + 1))]}"
      case "$v" in --*) die 2 "STOP premise — $a was given the flag '$v' as its value" ;; esac
      case "$a" in
        --release)  RELEASE="$v" ;;
        --vault)    VAULT="$v" ;;
        --recap)    RECAP="$v" ;;
        --publish)  OWNER_WORD="$v" ;;
        --message)  MESSAGE="$v" ;;
        --approved) APPROVED="$v" ;;
      esac
      i=$((i + 2)) ;;
    -h|--help) usage; exit 0 ;;
    --*) die 2 "STOP premise — unknown option $a" ;;
    *)
      [ -z "$REPO" ] || die 2 "STOP premise — more than one repo given ($REPO and $a)"
      REPO="$a"; i=$((i + 1)) ;;
  esac
done

[ -n "$REPO" ]    || { usage >&2; die 2 "STOP premise — no repo clone given"; }
[ -n "$RELEASE" ] || die 2 "STOP premise — --release <ver> is required (the release gate runs on it)"
if [ -n "$OWNER_WORD" ] && [ -z "$MESSAGE" ]; then
  die 2 "STOP premise — --publish needs --message: a commit with no owner-given message is not the owner's"
fi
if [ -n "$MESSAGE" ] && [ -z "$OWNER_WORD" ]; then
  die 2 "STOP premise — --message without --publish: the owner's word is what authorises the commit"
fi
# The three publish flags are one authorisation, so they arrive together or not at all: the word,
# the message it authorised, and the digest of the recap the word was given on. --approved alone is
# refused too — a digest with no word authorises nothing, and accepting it silently would make the
# recap-only run look like a publish that did not happen.
if [ -n "$OWNER_WORD$MESSAGE$APPROVED" ] && { [ -z "$OWNER_WORD" ] || [ -z "$MESSAGE" ] || [ -z "$APPROVED" ]; }; then
  die 2 "STOP premise — --publish, --message and --approved come as a set: the owner's word, the message it authorised, and the recap-digest the recap-only run printed as its last line. Run without them first, read the recap, then pass all three"
fi

# ── premises: the repo, the vault, the three scripts, the recap file ─────────────────────────
[ -d "$REPO" ]      || die 2 "STOP premise — $REPO is not a directory"
REPO="$(cd "$REPO" && pwd)"
[ -d "$REPO/.git" ] || die 2 "STOP premise — $REPO is not a git clone (clone the repo first; RUNBOOK section D)"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null \
  || die 2 "STOP premise — git cannot read $REPO as a work tree"

DERIVED_VAULT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -n "$VAULT" ]; then
  [ -d "$VAULT" ] || die 2 "STOP premise — --vault $VAULT is not a directory"
  VAULT="$(cd "$VAULT" && pwd)"
  [ "$VAULT" = "$DERIVED_VAULT" ] || die 2 \
    "STOP premise — --vault $VAULT is not the vault this script sits in ($DERIVED_VAULT); the overlay reads its source from its own location, so run that vault's own copy of publish.sh"
else
  VAULT="$DERIVED_VAULT"
fi
# Two repos, never crossed. The vault is itself a git clone with a private remote, so it passes
# every premise above: mistyped as the repo argument it would have the overlay written onto it,
# `git add -A` staging the result, and the packaging step replacing its .gitignore. Compared on
# physical paths, because either side may be reached through a symbolic link.
[ "$(cd "$REPO" && pwd -P)" != "$(cd "$VAULT" && pwd -P)" ] \
  || die 2 "STOP premise — the repo clone is this vault itself (two repos, never crossed): pass the public repo's clone, which lives outside the vault"
for f in CLAUDE.md CUSTOMISATION.md; do
  [ -f "$VAULT/$f" ] || die 2 "STOP premise — $VAULT has no $f, so it is not a vault root (pass --vault)"
done

EXPORT="$SCRIPT_DIR/export_template.sh"
GUARD="$SCRIPT_DIR/publish_guard.py"
THROTTLE="$VAULT/.claude/skills/delegate/throttle.py"
[ -f "$EXPORT" ]   || die 2 "STOP premise — no export_template.sh beside this script ($SCRIPT_DIR)"
[ -f "$GUARD" ]    || die 2 "STOP premise — no publish_guard.py beside this script ($SCRIPT_DIR): the payload gate cannot run, and a skipped gate is never a pass"
[ -f "$THROTTLE" ] || die 2 "STOP premise — no throttle.py at $THROTTLE: the throttle gate cannot run"
[ -d "$SCRIPT_DIR/payload" ] || die 2 "STOP premise — no payload/ beside this script ($SCRIPT_DIR)"

[ -n "$RECAP" ] || RECAP="$VAULT/output/publish-recap.txt"
if [ -n "$OWNER_WORD" ]; then
  # A --publish run NEVER truncates the recap: that file is the evidence the owner's word was given
  # on, and the approval check below reads it. The INCOMPLETE placeholder belongs to the recap-only
  # path alone — written there it would destroy the approved recap before the gates had run, and a
  # refused publish would leave the owner nothing to re-read.
  { [ -f "$RECAP" ] && [ -s "$RECAP" ]; } \
    || die 2 "STOP recap — no recap at $RECAP: --publish approves a recap that already exists. Run without --publish first, read the recap it writes, then pass its recap-digest as --approved"
  RECAP="$(cd "$(dirname "$RECAP")" && pwd)/$(basename "$RECAP")"
else
  mkdir -p "$(dirname "$RECAP")" || true
  [ -d "$(dirname "$RECAP")" ] || die 2 "STOP recap — cannot write $RECAP: $(dirname "$RECAP") is not a directory"
  printf 'publish.sh recap — stamp %s — INCOMPLETE\n' "$STAMP" > "$RECAP" \
    || die 2 "STOP recap — cannot write $RECAP"
  RECAP="$(cd "$(dirname "$RECAP")" && pwd)/$(basename "$RECAP")"
fi

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/publish.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

REMOTE_URL="(no origin)"
if u="$(git -C "$REPO" config --get remote.origin.url)"; then REMOTE_URL="$u"; fi
printf '== publish.sh — repo %s\n' "$REPO"
printf '== vault %s · candidate %s · stamp %s\n' "$VAULT" "$RELEASE" "$STAMP"

# What a STOP leaves behind, said in the STOP itself rather than left for the reader to discover:
# the overlay and the staging happen before the gates, so a refused publish leaves the clone dirty.
LEFT_BEHIND="the clone keeps the overlay in its working tree with everything staged, uncommitted ('git -C $REPO reset -q' clears the index; the next run overlays and stages again)"

# ── the drift check's exemptions, keyed on what export_template.sh itself holds ───────────────
# Two classes of staged file differ from their vault twin BY DESIGN, and both are read out of the
# export script rather than listed here by name, so a new transform or a new marked block needs no
# edit in this file:
#   1. the paths apply_fixes() rewrites — parsed out of that function's body;
#   2. any Markdown file carrying the conditional-compile marker, whose block the export strips —
#      the marker string itself is read out of the same script.
# A third class is packaged rather than copied: the machinery under the skill's payload/ (the git
# dotfiles, setup.sh, the seed demo), which lands at a repo path whose vault twin is a different
# file. It is recognised by content — a staged file whose bytes are some payload file's bytes.
derive_transform_paths() {
  awk 'index($0, "apply_fixes()") == 1 { f = 1 } f && $0 == "}" { f = 0 } f' "$EXPORT" \
    | grep -o '\$D/[A-Za-z0-9_./-]*' | sed 's|^\$D/||' | sort -u
}
if command -v shasum >/dev/null; then SUM=(shasum -a 256)
elif command -v sha256sum >/dev/null; then SUM=(sha256sum)
else die 2 "STOP premise — neither shasum nor sha256sum is on PATH: the packaged-file exemption cannot be computed"
fi
sum_of() { "${SUM[@]}" "$1" | awk '{ print $1 }'; }

# ── the recap digest: what binds the owner's word to the recap the owner read ────────────────
# The recap-only run prints `recap-digest <d>` as its last line; --publish carries that d back and
# the run refuses to commit unless the recap on disk, and the index it named, still digest to it.
# 12 hex characters of the sha-256 (48 bits): the digest is copied by hand from one command into
# the next, so it is kept short enough to retype and long enough that no two recaps of a run collide
# — the width is set by judgement, unmeasured.
DIGEST_WIDTH=12
# The body the digest covers is everything the owner read EXCEPT what differs between two runs that
# presented the same thing: the stamp lines (pid and clock of that invocation) and the digest line
# itself. The staged index enters it as the `tree` line — git's own hash of the index, so a single
# extra staged byte changes the digest. $2 is the tree hash to weigh: the recap's own on the run
# that writes it, the clone's current one on the run that checks it, which is how a mutated index
# is caught.
recap_digest_body() {                          # $1 recap file, $2 tree hash
  awk -v tree="$2" '
    index($0, "publish.sh recap") == 1 { next }
    index($0, "recap-complete ")   == 1 { next }
    index($0, "recap-digest ")     == 1 { next }
    index($0, "tree ")             == 1 { print "tree        " tree; next }
    { print }' "$1"
}
recap_digest_of() {                            # $1 recap file, $2 tree hash
  recap_digest_body "$1" "$2" | "${SUM[@]}" | cut -c "1-$DIGEST_WIDTH"
}
recap_field() {                                # $1 key — the value of the first `<key> …` line
  awk -v k="$1" 'index($0, k " ") == 1 { sub("^" k " +", ""); print; exit }' "$RECAP"
}

TRANSFORMS="$(derive_transform_paths || true)"
[ -n "$TRANSFORMS" ] || die 2 "PROBE FAILED: no transformed paths parsed out of apply_fixes() in $EXPORT — the drift check's exemption derivation is broken, and every transformed file would read as drift"
MARKER="$(grep -o 'vault-local:[a-z]*' "$EXPORT" | head -1 || true)"
[ -n "$MARKER" ] || die 2 "PROBE FAILED: no conditional-compile marker found in $EXPORT — the drift check cannot tell a stripped block from drift"
find "$SCRIPT_DIR/payload" -type f -print0 | xargs -0 "${SUM[@]}" | awk '{ print $1 }' | sort -u > "$TMPD/payload.sums"
[ -s "$TMPD/payload.sums" ] || die 2 "PROBE FAILED: no files under $SCRIPT_DIR/payload — the packaged-file exemption would match nothing"

# ── the steps ────────────────────────────────────────────────────────────────────────────────
step_pull() {
  printf -- '-- pull\n'
  git -C "$REPO" pull --ff-only || die 3 "STOP pull — 'git pull --ff-only' failed in $REPO; resolve it there and re-run"
}

step_overlay() {
  printf -- '-- overlay\n'
  bash "$EXPORT" --push "$REPO" || die 3 "STOP overlay — export_template.sh --push failed"
}

step_stage() {
  printf -- '-- stage\n'
  git -C "$REPO" add -A || die 3 "STOP stage — 'git add -A' failed in $REPO"
  git -C "$REPO" --no-pager diff --cached --stat > "$TMPD/stat.txt" \
    || die 3 "STOP stage — 'git diff --cached --stat' failed in $REPO"
  # git's own hash of the staged index, which the recap prints and the digest covers: it is the
  # name of the exact tree a commit would write, so the --publish run can prove the index it is
  # about to commit is the one the recap described.
  TREE="$(git -C "$REPO" write-tree)" || die 3 "STOP stage — 'git write-tree' failed in $REPO"
  cat "$TMPD/stat.txt"
}

step_drift() {
  printf -- '-- drift check (exemptions derived from export_template.sh)\n'
  if git -C "$REPO" rev-parse --verify -q HEAD >/dev/null; then
    git -C "$REPO" diff --cached --name-only -z > "$TMPD/staged.z" \
      || die 3 "STOP stage — 'git diff --cached --name-only' failed in $REPO"
  else
    git -C "$REPO" ls-files --cached -z > "$TMPD/staged.z" \
      || die 3 "STOP stage — 'git ls-files --cached' failed in $REPO"
  fi
  : > "$TMPD/drift.txt"; : > "$TMPD/exempt.txt"
  local p reason
  while IFS= read -r -d '' p; do
    [ -f "$REPO/$p" ]  || continue            # staged deletion: no bytes to compare
    [ -f "$VAULT/$p" ] || continue            # no vault twin: packaging or skeleton, not a vault file
    if cmp -s "$REPO/$p" "$VAULT/$p"; then continue; fi   # `cmp … && continue` would trip set -e
    reason=""
    if printf '%s\n' "$TRANSFORMS" | grep -qxF -- "$p"; then
      reason="transformed by apply_fixes()"
    elif grep -q -- "$MARKER" "$VAULT/$p"; then
      reason="a $MARKER block was stripped on export"
    elif grep -qxF -- "$(sum_of "$REPO/$p")" "$TMPD/payload.sums"; then
      reason="packaged from the skill payload, not copied from the vault"
    fi
    if [ -n "$reason" ]; then
      printf '  exempt  %s  (%s)\n' "$p" "$reason" >> "$TMPD/exempt.txt"
    else
      printf '  DRIFT   %s  (vault %s · repo %s)\n' "$p" \
        "$(date -u -r "$VAULT/$p" +%Y-%m-%dT%H:%M:%SZ)" "$(date -u -r "$REPO/$p" +%Y-%m-%dT%H:%M:%SZ)" \
        >> "$TMPD/drift.txt"
    fi
  done < "$TMPD/staged.z"
  cat "$TMPD/exempt.txt"
  if [ -s "$TMPD/drift.txt" ]; then
    cat "$TMPD/drift.txt" >&2
    die 1 "STOP drift — $(grep -c . "$TMPD/drift.txt") staged file(s) differ from the vault and no export rule explains it: the vault changed after the overlay, so re-overlay and re-gate. Nothing committed; $LEFT_BEHIND"
  fi
  printf '  drift: none (%s exempt, %s transform path(s) and the %s marker derived from export_template.sh)\n' \
    "$(grep -c . "$TMPD/exempt.txt" || true)" "$(printf '%s\n' "$TRANSFORMS" | grep -c . || true)" "$MARKER"
}

run_gate() {                                   # $1 label, $2 out-file, rest the command
  local label="$1" out="$2"; shift 2
  local rc=0
  "$@" > "$out" 2>&1 || rc=$?
  cat "$out"
  case "$rc" in
    0) return 0 ;;
    1) die 1 "STOP $label — the gate reported a finding (exit 1); nothing committed; $LEFT_BEHIND" ;;
    *) die 2 "STOP $label — exit $rc (a broken premise is never a pass); nothing committed; $LEFT_BEHIND" ;;
  esac
}

step_payload_gate() {
  printf -- '-- payload gate\n'
  run_gate "payload-gate" "$TMPD/gate.txt" python3 "$GUARD" --vault "$VAULT" "$REPO"
}

step_release_gate() {
  printf -- '-- release gate (--release %s)\n' "$RELEASE"
  run_gate "release-gate" "$TMPD/release.txt" python3 "$GUARD" --vault "$VAULT" --release "$RELEASE" "$REPO"
}

step_throttle_gate() {
  printf -- '-- throttle gate\n'
  # `auto` is written here as a literal, and stays one. It is not this instance's setting but the
  # gate's own wording: the export SKILL.md states the throttle gate as `throttle.py check --require
  # auto` in prose (`grep -n "require auto" SKILL.md` finds that line), and this call is that
  # sentence executed. throttle.py holds the shipped default's name in a comment rather than as a
  # queryable value, so deriving the preset instead of naming it means changing throttle.py — a
  # different item, outside this script. A preset rename therefore sweeps two surfaces, and the
  # grep above is the probe that finds both.
  run_gate "throttle-gate" "$TMPD/throttle.txt" python3 "$THROTTLE" check --root "$VAULT" --require auto
}

step_recap() {
  printf -- '-- recap\n'
  git -C "$REPO" --no-pager log --oneline -5 > "$TMPD/log.txt" \
    || die 3 "STOP recap — 'git log' failed in $REPO"
  {
    printf 'publish.sh recap — stamp %s\n' "$STAMP"
    printf 'repo        %s\n' "$REPO"
    printf 'remote      %s\n' "$REMOTE_URL"
    printf 'vault       %s\n' "$VAULT"
    printf 'candidate   %s\n' "$RELEASE"
    printf 'tree        %s\n' "$TREE"
    printf '\n-- staged (git diff --cached --stat) --\n'
    cat "$TMPD/stat.txt"
    printf '\n-- drift check --\n'
    cat "$TMPD/exempt.txt"
    printf '  drift: none\n'
    printf '\n-- payload gate --\n'
    grep -E '^(check|personal-strings):' "$TMPD/gate.txt" || cat "$TMPD/gate.txt"
    printf '\n-- release gate (--release %s) --\n' "$RELEASE"
    grep -E '^(check|personal-strings):' "$TMPD/release.txt" || cat "$TMPD/release.txt"
    printf '\n-- throttle gate --\n'
    cat "$TMPD/throttle.txt"
    printf '\n-- git log --oneline -5 --\n'
    cat "$TMPD/log.txt"
    printf '\nrecap-complete %s\n' "$STAMP"
  } > "$RECAP" || die 2 "STOP recap — cannot write $RECAP"
  [ -s "$RECAP" ] || die 2 "STOP recap — $RECAP was written empty"
  # The digest of what was just written, appended to the recap and printed as this run's last line.
  # It is computed over the file on disk, so what the owner reads and what --approved names are the
  # same bytes. A publish that succeeds appends its result below this line, which changes the body:
  # a second --publish on the same digest is therefore refused, and one word publishes once.
  DIGEST="$(recap_digest_of "$RECAP" "$TREE")" \
    || die 2 "STOP recap — could not digest $RECAP (no sha-256 output)"
  [ -n "$DIGEST" ] || die 2 "PROBE FAILED: the recap digest came out empty — the approval check would compare nothing"
  printf 'recap-digest %s\n' "$DIGEST" >> "$RECAP" \
    || die 2 "STOP recap — cannot append the digest to $RECAP"
  cat "$RECAP"
}

# ── the approval check: the --publish run's first step, and the only one that can refuse a word ──
# It answers one question — is the tree about to be committed the tree whose recap the owner read?
# Each section is compared in the recap's own order and the first difference is the one named, so
# the message says which premise moved: the clone, the remote, the vault, the candidate version,
# the staged index, or the recap body itself.
step_verify_approval() {
  printf -- '-- approval check (--approved %s)\n' "$APPROVED"
  local recorded now_tree derived
  grep -q '^recap-complete ' "$RECAP" \
    || die 2 "STOP approval — $RECAP carries no completion marker: the run that wrote it did not finish, so there is no recap to approve. Re-run without --publish"
  recorded="$(recap_field recap-digest)"
  [ -n "$recorded" ] || die 2 "STOP approval — $RECAP carries no recap-digest line: it was not written by this version of publish.sh. Re-run without --publish to produce a recap with one"
  [ "$recorded" = "$APPROVED" ] || die 1 \
    "STOP approval — section recap-digest: the recap on disk digests to $recorded, --approved names $APPROVED. The recap was regenerated after the word was given, so the word is not on this recap. Read the recap now on disk and pass ITS digest; nothing committed"
  verify_section() {                           # $1 section, $2 recap's value, $3 the value now
    [ "$2" = "$3" ] || die 1 \
      "STOP approval — section $1 differs: the recap says '$2', it is now '$3'. The tree the owner approved is not the tree on disk; re-run without --publish for a fresh recap and digest. Nothing committed"
  }
  verify_section repo      "$(recap_field repo)"      "$REPO"
  verify_section remote    "$(recap_field remote)"    "$REMOTE_URL"
  verify_section vault     "$(recap_field vault)"     "$VAULT"
  verify_section candidate "$(recap_field candidate)" "$RELEASE"
  # write-tree on the index AS IT STANDS: this run has not pulled, overlaid or staged anything, so
  # this hash is the index the last recap-only run left — unless something else touched it.
  now_tree="$(git -C "$REPO" write-tree)" || die 3 "STOP approval — 'git write-tree' failed in $REPO"
  verify_section tree "$(recap_field tree)" "$now_tree"
  # Everything else the owner read: the staged stat, the exemptions, both gate reports, the log.
  # The tree matched above, so a difference here is the recap body having changed under the digest.
  derived="$(recap_digest_of "$RECAP" "$now_tree")"
  [ "$derived" = "$recorded" ] || die 1 \
    "STOP approval — section recap body: $RECAP no longer digests to $recorded (now $derived); it was edited after the word was given. Nothing committed"
  printf '  approved: recap %s · tree %s · %s\n' "$recorded" "$now_tree" "$RECAP"
}

step_finish() {
  [ -s "$RECAP" ] || die 2 "STOP recap — $RECAP is missing or empty; a recap not produced is a stop"
  if [ -z "$OWNER_WORD" ]; then
    # This invocation's own marker, checked against a torn or truncated write rather than against
    # an earlier run: it cannot fail on a run that reached here, which is why it is NOT what
    # authorises a publish. The binding to the owner's word is step_verify_approval's digest.
    grep -qF -- "recap-complete $STAMP" "$RECAP" \
      || die 2 "STOP recap — $RECAP carries no completion marker from this invocation ($STAMP)"
    printf 'STOP: recap written to %s — nothing committed.\n' "$RECAP"
    printf 'To publish, re-run with --publish "<the owner'"'"'s word>" --message "<commit message>" --approved %s.\n' "$DIGEST"
    printf 'recap-digest %s\n' "$DIGEST"
    return 0
  fi
  printf -- '-- publish (owner word: %s)\n' "$OWNER_WORD"
  git -C "$REPO" commit -m "$MESSAGE" || die 3 "STOP commit — 'git commit' failed in $REPO"
  git -C "$REPO" push               || die 3 "STOP push — 'git push' failed in $REPO (auth? set up a token or key and re-run)"
  local head
  head="$(git -C "$REPO" rev-parse --short HEAD)"
  {
    printf '\npublished    %s\n' "$head"
    printf 'message      %s\n' "$MESSAGE"
    printf 'owner word   %s\n' "$OWNER_WORD"
  } >> "$RECAP" || die 2 "STOP recap — cannot append the publish result to $RECAP"
  printf 'PUBLISHED: %s pushed to %s\n' "$head" "$REMOTE_URL"
}

# One chain per mode. Each step also exits on its own failure with its own code, so the `&&` links
# are the second lock rather than the only one — the defect this script replaces was a hand-typed
# chain where one link was a `;`.
#
# The two chains differ in one way that matters: the recap-only chain BUILDS the tree it reports on
# (pull, overlay, stage), the publish chain does not touch it. A second pull or overlay under
# --publish would move the tree out from under the recap the owner read — the whole point of the
# digest — so the publish chain proves the index is still the approved one, re-runs the four gates
# on it read-only (they are the same gates, on the same index, and a vault that moved since is drift
# here just as it was there), and only then commits and pushes.
if [ -z "$OWNER_WORD" ]; then
  step_pull \
    && step_overlay \
    && step_stage \
    && step_drift \
    && step_payload_gate \
    && step_release_gate \
    && step_throttle_gate \
    && step_recap \
    && step_finish
else
  step_verify_approval \
    && step_drift \
    && step_payload_gate \
    && step_release_gate \
    && step_throttle_gate \
    && step_finish
fi
