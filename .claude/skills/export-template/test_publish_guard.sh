#!/usr/bin/env bash
# test_publish_guard.sh — isolated tests for publish_guard.py (the publish gate's payload
# probe, item 121). Builds throwaway payloads under $TMPDIR, git and non-git. NEVER touches
# the real vault or any real repo. Run:  bash test_publish_guard.sh
#
# Covers, per case group: both probes fire on their own class; both stay quiet on the
# legitimate shapes the live payload actually contains; every premise failure exits 2 rather
# than reporting clean; the index — not the working tree — is what the guard reads.
#
# From 2026-09-08 the suite reads the same from any working directory: group 7's gitlink blob
# is hashed inside the fixture repository rather than wherever the caller stood, and group 7d
# runs that build from a directory inside no repository at all (register entry 2026-09-08
# 06:35 — from outside a repo the hash failed and took the submodule case with it).

set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SKILL/publish_guard.py"
ROOT="${TMPDIR:-/tmp}/pgtest.$$"
GIT="git -c user.email=t@t -c user.name=test -c commit.gpgsign=false -c init.defaultBranch=main"

# This suite SHIPS inside `.claude/skills/**`, so it sits inside the scope of the guard it
# tests — by design: the guard exempts no file. Every example home path is therefore
# assembled from parts at run time and never written as a literal, or this suite would halt
# the publish on itself (found by prototyping on the live payload, 2026-09-06).
U="/U""sers"; H="/h""ome"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }

# run the guard on $1, capture output in $OUT and exit code in $RC. GUARD_EXTRA adds flags
# for one case; the empty-array form keeps it safe under `set -u` on bash 3.2.
GUARD_EXTRA=()
guard(){ OUT="$(env USER=fxaccount LOGNAME=fxaccount HOME="$FXH" \
                    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                    python3 "$GUARD" --vault "$FXV" --allowlist "$FXA" \
                    ${GUARD_EXTRA[@]+"${GUARD_EXTRA[@]}"} "$1" 2>&1)"; RC=$?; }

# expect exit code $2 (and, when given, substring $3 in the output) from a run on $1
expect(){ local dir="$1" want="$2" needle="${3:-}" label="$4"
  guard "$dir"
  if [ "$RC" != "$want" ]; then no "$label (exit $RC, wanted $want): $(echo "$OUT" | head -2)"; return; fi
  if [ -n "$needle" ] && ! printf '%s' "$OUT" | grep -q -- "$needle"; then
    no "$label (exit ok, but output lacks '$needle'): $(echo "$OUT" | head -2)"; return; fi
  ok "$label"
}

# a minimal but shape-valid framework payload at $1
make_payload(){ local D="$1"
  mkdir -p "$D/.claude/skills/ingest" "$D/.claude/agents" "$D/assets" "$D/examples/seed/wiki" \
           "$D/wiki/sources" "$D/raw/2-papers" "$D/.obsidian"
  printf '# CLAUDE (test contract)\n' > "$D/CLAUDE.md"
  printf '# Manual (test)\n'          > "$D/MANUAL.md"
  printf '# ingest skill\n'           > "$D/.claude/skills/ingest/SKILL.md"
  printf '# critic\n'                 > "$D/.claude/agents/critic.md"
  printf '{ "colorGroups": [] }\n'    > "$D/.obsidian/graph.json"
  printf '# seed page\n'              > "$D/examples/seed/wiki/index.md"
  : > "$D/wiki/sources/.gitkeep"; : > "$D/raw/2-papers/.gitkeep"; : > "$D/assets/.gitkeep"
}

rm -rf "$ROOT"; mkdir -p "$ROOT"
# Probe 3 derives the owner's strings from a vault, so every case here runs against a FIXTURE
# vault and a fixture allowlist, with the account name, home and git config isolated too.
# Without that the suite would scan its throwaway payloads with the real machine's needles and
# pass or fail differently on every machine — and mutating the shipped allowlist to test a
# malformed one would leave a shipped file broken if a case ever aborted.
FXV="$ROOT/fxv"; FXH="$ROOT/fxhome"; FXA="$ROOT/fx-allowlist.md"
mkdir -p "$FXV" "$FXH"
printf '# fixture contract\n' > "$FXV/CLAUDE.md"
printf 'marker\n\n## Settings\n- **agent_name**: Zephyrine — what the agent calls itself\n' > "$FXV/CUSTOMISATION.md"
$GIT -C "$FXV" init -q
$GIT -C "$FXV" config user.name "Quillsworth Vaneska"
$GIT -C "$FXV" config user.email "qz9917+ZephyrineQ@example.invalid"
$GIT -C "$FXV" config remote.origin.url "https://example.com/ZephyrineQ/fx.git"
cp "$SKILL/publish-allowlist.md" "$FXA"
# The same invocation as an array, for the two cases that must call the guard with a bad
# argument or none at all. An array, never a string: a flag and its value in one word is the
# 2026-09-04 wrapper defect.
GUARD_CMD=(env USER=fxaccount LOGNAME=fxaccount HOME="$FXH"
           GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
           python3 "$GUARD" --vault "$FXV" --allowlist "$FXA")


echo "── group 1: the clean payload passes, and says what it scanned ──"
P="$ROOT/clean"; make_payload "$P"
expect "$P" 0 "check: clean" "a clean payload passes"
expect "$P" 0 "control: 7/7 path probes, 3/3 class probes" "the clean line carries its self-control tally"
expect "$P" 0 "no git index" "a non-git payload says its file set came from disk"

echo "── group 2: probe 1 — machine paths ──"
P="$ROOT/p1a"; make_payload "$P"; printf 'OUT=%s/someone/vault/x\n' "$U" > "$P/.claude/skills/ingest/run.sh"
expect "$P" 1 "FINDING machine-path" "an absolute macOS home path in a shipped file halts"
P="$ROOT/p1b"; make_payload "$P"; printf 'HOME_DIR=%s/someone/notes\n' "$H" > "$P/MANUAL.md"
expect "$P" 1 "FINDING machine-path" "an absolute Linux home path halts too"
P="$ROOT/p1c"; make_payload "$P"
printf 'the fixture stamp is "$W%s/.llm-wiki/last-run.txt"\n' "$H" > "$P/.claude/skills/ingest/t.sh"
expect "$P" 0 "check: clean" "a fixture-relative \$W-prefixed home path does NOT halt (the live deep-lint case)"
P="$ROOT/p1d"; make_payload "$P"; printf 'the agent home is ~/.llm-wiki/ under $HOME\n' > "$P/README.md"
expect "$P" 0 "check: clean" "a tilde or \$HOME form does NOT halt"
P="$ROOT/p1e"; make_payload "$P"; printf 'see file://%s/someone/vault/CLAUDE.md\n' "$U" > "$P/README.md"
expect "$P" 1 "FINDING machine-path" "a file:// URL into a home directory halts"
P="$ROOT/p1f"; make_payload "$P"; printf 'see https://example.com%s/guide\n' "$U" > "$P/README.md"
expect "$P" 0 "check: clean" "a URL segment of the same spelling does NOT halt"
# The real incident's bytes: CPython writes the source path behind a marshal LENGTH byte, so
# the character before the path is arbitrary data. A text-style lookbehind swallows it — which
# is why the machine-path rule follows the content class.
P="$ROOT/p1g"; make_payload "$P"
printf 'x\000o%s/someone/vault/repo_pack.py\000' "$U" > "$P/.claude/skills/ingest/repo_pack.pyc"
guard "$P"
if [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q "FINDING machine-path" \
   && printf '%s' "$OUT" | grep -q "FINDING non-text"; then
  ok "the 2026-09-03 incident shape (a path behind a marshal length byte) halts on BOTH probes"
else no "the 2026-09-03 incident shape halts on both probes (exit $RC): $(echo "$OUT" | head -3)"; fi
P="$ROOT/p1h"; make_payload "$P"; printf 'the vendor path fragment is repo%s/guide\n' "$U" > "$P/MANUAL.md"
expect "$P" 0 "check: clean" "the SAME preceding byte in a TEXT file stays a fragment, not a halt"

echo "── group 3: probe 2 — non-text files ──"
P="$ROOT/p2a"; make_payload "$P"; printf 'ELF\000\000\000' > "$P/.claude/skills/ingest/helper.so"
expect "$P" 1 "FINDING non-text" "a non-text file under .claude/ halts (no filename list needed)"
P="$ROOT/p2b"; make_payload "$P"; printf 'junk\000\000' > "$P/examples/seed/wiki/thumb.ico"
expect "$P" 1 "FINDING non-text" "a non-text file under examples/ halts too — the scope is not .claude-only"
P="$ROOT/p2c"; make_payload "$P"
printf '\211PNG\r\n\032\n\000\000IHDR' > "$P/assets/framework_demo.png"
printf '\211PNG\r\n\032\n\000\000IHDR' > "$P/assets/hero.png"
expect "$P" 0 "check: clean" "the two intentional assets/*.png screenshots do NOT halt"
P="$ROOT/p2d"; make_payload "$P"; printf '\211PNG\r\n\032\n\000\000' > "$P/.claude/skills/ingest/hero.png"
expect "$P" 1 "FINDING non-text" "the SAME png halts once it sits under .claude/ (scope, not name)"
P="$ROOT/p2e"; make_payload "$P"
expect "$P" 0 "check: clean" "empty .gitkeep placeholders are text, not findings"
P="$ROOT/p2f"; make_payload "$P"
printf 'a page — with an em dash, a curly quote and an emoji 🧹\n' > "$P/.claude/skills/ingest/SKILL.md"
expect "$P" 0 "check: clean" "high UTF-8 bytes are text, not findings"
P="$ROOT/p2g"; make_payload "$P"
python3 -c 'open("'"$P"'/.claude/skills/ingest/big.md","wb").write(b"# doc\n"*3000 + b"\x00tail")'
expect "$P" 0 "check: clean" "a NUL past byte 8000 is text, matching git's own window"

echo "── group 4: premise failures exit 2, never clean ──"
expect "$ROOT/does-not-exist" 2 "PROBE FAILED" "a missing path is a broken premise"
mkdir -p "$ROOT/empty"
expect "$ROOT/empty" 2 "payload holds no files" "an EMPTY payload is a broken premise, not a clean scan"
mkdir -p "$ROOT/partial"; printf '# CLAUDE\n' > "$ROOT/partial/CLAUDE.md"
expect "$ROOT/partial" 2 "not a framework payload" "a payload with no skills is a broken premise"
mkdir -p "$ROOT/noclaude/.claude/skills/x"; printf '# s\n' > "$ROOT/noclaude/.claude/skills/x/SKILL.md"
expect "$ROOT/noclaude" 2 "not a framework payload" "a payload with no CLAUDE.md is a broken premise"
OUT="$("${GUARD_CMD[@]}" "$ROOT/clean/CLAUDE.md" 2>&1)"; RC=$?
if [ "$RC" = 2 ]; then ok "a file rather than a directory is a broken premise"
else no "a file rather than a directory is a broken premise (exit $RC)"; fi
OUT="$("${GUARD_CMD[@]}" 2>&1)"; RC=$?
if [ "$RC" = 2 ]; then ok "a missing argument is a broken premise"
else no "a missing argument is a broken premise (exit $RC)"; fi

echo "── group 5: with a git index, the INDEX is what ships ──"
R="$ROOT/repo"; make_payload "$R"
( cd "$R" && $GIT init -q . && printf '__pycache__/\n*.pyc\n.DS_Store\n' > .gitignore && $GIT add -A ) >/dev/null
expect "$R" 0 "from the index of" "a staged clean payload passes, read from the index"
printf 'OUT=%s/someone/leak\n' "$U" > "$R/.claude/skills/ingest/unstaged.sh"
expect "$R" 2 "stage the payload first" "an UNTRACKED file is refused: the gate would otherwise read the last publish"
( cd "$R" && $GIT add -A ) >/dev/null
expect "$R" 1 "FINDING machine-path" "the same file halts once staged"
( cd "$R" && $GIT rm -q --cached .claude/skills/ingest/unstaged.sh && rm -f .claude/skills/ingest/unstaged.sh ) >/dev/null
printf 'x\000%s/someone/vault/mod.py\000' "$U" > "$R/.claude/skills/ingest/mod.pyc"
expect "$R" 0 "check: clean" "a gitignored .pyc does not ship, so it does not halt"
( cd "$R" && $GIT add -f .claude/skills/ingest/mod.pyc ) >/dev/null
expect "$R" 1 "FINDING non-text" "the incident's real shape — a TRACKED .pyc that .gitignore no longer covers — halts"
( cd "$R" && $GIT rm -q --cached .claude/skills/ingest/mod.pyc && rm -f .claude/skills/ingest/mod.pyc ) >/dev/null
printf 'clean line\n' > "$R/.claude/skills/ingest/edited.sh"
( cd "$R" && $GIT add -A ) >/dev/null
printf 'OUT=%s/someone/after-staging\n' "$U" > "$R/.claude/skills/ingest/edited.sh"
expect "$R" 2 "stage them first" "an edit made AFTER staging is refused — the commit would write the index, not those bytes"
( cd "$R" && $GIT add -A ) >/dev/null
expect "$R" 1 "FINDING machine-path" "…and it halts as soon as it is staged"
( cd "$R" && $GIT rm -q --cached .claude/skills/ingest/edited.sh && rm -f .claude/skills/ingest/edited.sh ) >/dev/null

echo "── group 6: git's own classification cannot be gamed into a false halt ──"
printf '*.md -text -diff\n' > "$R/.gitattributes"
( cd "$R" && $GIT add -A ) >/dev/null
expect "$R" 0 "check: clean" "a .gitattributes '-text' line does NOT make Markdown files halt (shape B's failure mode)"
if ( cd "$R" && $GIT grep -I -e 'CLAUDE' --cached -- 'CLAUDE.md' ) >/dev/null 2>&1; then
  no "control: git itself still greps CLAUDE.md as text under '*.md -text' (the premise this case tests is absent)"
else ok "control: git itself now treats CLAUDE.md as binary — the guard's independence is what kept it clean"; fi
rm -f "$R/.gitattributes"; ( cd "$R" && $GIT add -A ) >/dev/null

echo "── group 7: shapes git can hide ──"
( cd "$R" && ln -sf "$U/someone/vault/CLAUDE.md" .claude/skills/ingest/link.md && $GIT add -A ) >/dev/null
expect "$R" 1 "FINDING machine-path" "a symlink into a home directory halts (its blob is the target path)"
( cd "$R" && $GIT rm -q --cached .claude/skills/ingest/link.md && rm -f .claude/skills/ingest/link.md ) >/dev/null
# The gitlink's blob is written INSIDE the fixture repo: `git hash-object -w` writes to
# whichever repository the caller's working directory is in, so from outside any repo the hash
# failed and the submodule case never ran, while from a repo it left a loose object in the
# caller's own store (2026-09-08). stderr is left visible: with the directory dependence gone,
# a failure here is a real one and its reason belongs beside the premise leg below.
gitlink_blob(){ ( cd "$R" && $GIT hash-object -w "$ROOT/clean/CLAUDE.md" ) || echo ""; }
SUB="$(gitlink_blob)"
if [ -n "$SUB" ]; then
  ( cd "$R" && $GIT update-index --add --cacheinfo "160000,$SUB,vendor/thing" ) >/dev/null 2>&1
  expect "$R" 1 "FINDING unscannable" "a gitlink (submodule) is REPORTED, never silently unscanned"
  ( cd "$R" && $GIT update-index --force-remove vendor/thing ) >/dev/null 2>&1
else no "could not build the gitlink fixture (premise for the submodule case)"; fi
expect "$R" 0 "check: clean" "the repo is clean again once the fixtures are removed"

echo "── group 7d: the gitlink premise does not depend on the caller's directory ──"
# The same build, run from a directory that is inside no repository: what the caller's cwd was
# is exactly what used to decide whether group 7 could run at all.
OUTSIDE="$ROOT/outside"; mkdir -p "$OUTSIDE"
if ( cd "$OUTSIDE" && $GIT rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
  # Four legs either way, so the total does not move with the premise.
  no "premise: the fixture root is inside no repository (it is inside one — this group cannot test what it claims)"
  no "…so the outside-repo build could not run"
  no "…nor the submodule case from outside a repository"
  no "…nor its clean-again leg"
else
  ok "premise: the fixture root sits inside no repository, so a caller standing there has none"
  SUB="$( cd "$OUTSIDE" && gitlink_blob )"
  if [ -n "$SUB" ]; then
    ok "the gitlink blob is built from a directory inside no repository"
    ( cd "$R" && $GIT update-index --add --cacheinfo "160000,$SUB,vendor/thing" ) >/dev/null 2>&1
    expect "$R" 1 "FINDING unscannable" "…and the submodule case reaches its finding from there too"
    ( cd "$R" && $GIT update-index --force-remove vendor/thing ) >/dev/null 2>&1
    expect "$R" 0 "check: clean" "…and the repo is clean again once that fixture is removed"
  else
    no "the gitlink blob is built from a directory inside no repository (the premise this group tests)"
    no "…so the submodule case from outside a repository could not run"
    no "…nor its clean-again leg"
  fi
fi

# Findings folded from the critic lane of 2026-09-06 (run-20260906-n121, C1).
echo "── group 7c: the folded critic findings ──"
P="$ROOT/c1"; make_payload "$P"; printf 'OUT = "D:\\Users\\someone\\vault"\n' > "$P/MANUAL.md"
expect "$P" 1 "FINDING machine-path" "a WINDOWS home path halts too — three roots, not the two this machine uses"
P="$ROOT/c2"; make_payload "$P"; mkdir -p "$P/.claude/skills/ingest/assets"
printf 'ELF\000\000' > "$P/.claude/skills/ingest/assets/evil.so"
expect "$P" 1 "FINDING non-text" "a NESTED assets/ directory does NOT inherit the media exemption"
P="$ROOT/c3"; make_payload "$P"; printf -- '---\nrole: generalist\n---\n' > "$P/CUSTOMISATION.md"
expect "$P" 2 "this is a vault" "the VAULT root is refused: it passes the shape key but is not a payload"
S="$ROOT/c4"; make_payload "$S"; ( cd "$S" && $GIT init -q . ) >/dev/null
expect "$S" 2 "stage the payload first" "an unstaged payload is a broken premise, not a clean scan of the last publish"
( cd "$S" && $GIT add -A ) >/dev/null
expect "$S" 0 "check: clean" "…and it passes once staged"
printf '# edited after staging\n' > "$S/MANUAL.md"
expect "$S" 2 "stage them first" "a tracked file edited after staging is a broken premise"
( cd "$S" && $GIT add -A ) >/dev/null
expect "$S" 0 "check: clean" "…and it passes once restaged"

echo "── group 7b: the file set comes from the right place ──"
# The DEFAULT build directory sits inside the vault's own repo. Keyed on `rev-parse
# --is-inside-work-tree` the guard would ask the OUTER repo for its index and find the build
# untracked, i.e. call a real payload empty. Keyed on a .git entry at the root, it scans the tree.
B="$R/inner-build"; make_payload "$B"
expect "$B" 0 "no git index" "a build directory INSIDE a repo is scanned as a tree, not via the outer index"
PY3="$(command -v python3)"
if [ -n "$PY3" ]; then
  OUT="$(env PATH="" "$PY3" "$GUARD" "$R" 2>&1)"; RC=$?
  if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q "PROBE FAILED"; then
    ok "a repo whose git cannot run is a broken premise, never a silent disk fallback"
  else no "a repo whose git cannot run is a broken premise (exit $RC): $(echo "$OUT" | head -2)"; fi
  # A payload far larger than a pipe buffer must not deadlock: the sha list is written in
  # chunks and each chunk's blobs are drained before the next is sent.
  BIG="$ROOT/big"; make_payload "$BIG"
  "$PY3" -c 'import sys,os
d = sys.argv[1] + "/.claude/skills/ingest/many"
os.makedirs(d, exist_ok=True)
for i in range(1500): open("%s/f%04d.md" % (d, i), "w").write("# page %d\n" % i)' "$BIG"
  ( cd "$BIG" && $GIT init -q . && $GIT add -A ) >/dev/null 2>&1
  OUT="$("$PY3" -c 'import subprocess,sys
try:
    p = subprocess.run([sys.executable, sys.argv[1], sys.argv[2]], timeout=90,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sys.stdout.write(p.stdout.decode()); sys.exit(p.returncode)
except subprocess.TimeoutExpired:
    print("TIMED OUT"); sys.exit(9)' "$GUARD" "$BIG" 2>&1)"; RC=$?
  if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "check: clean"; then
    ok "a 1500-file staged payload scans without deadlocking on cat-file's pipes"
  else no "a 1500-file staged payload scans without deadlocking (exit $RC): $(echo "$OUT" | head -2)"; fi
else no "could not locate python3 for the PATH and scale cases"; fi

echo "── group 9: probe 3 — personal strings ──"
ALL_DEFAULT="$FXA"
# One fixture adjudication set: a permanent entry scoped to one file, a provisional entry
# with a per-file occurrence cap and an expiry.
cat > "$ROOT/al9.md" <<'AL9'
# fixture allowlist
- <licence holder's legal name> :: `LICENSE.md` — the fixture copyright line :: fixture
- <agent name> :: PROVISIONAL, expires at v1.0 — `.claude/skills/ingest/SKILL.md` (2) :: fixture
AL9
FXA="$ROOT/al9.md"
P="$ROOT/p3a"; make_payload "$P"; printf 'contact Vaneska for access\n' > "$P/MANUAL.md"
expect "$P" 1 "FINDING personal-str" "a derived personal string in a file's content halts"
P="$ROOT/p3a2"; make_payload "$P"; printf 'run as fxaccount on the build host\n' > "$P/MANUAL.md"
expect "$P" 1 "no allowlist entry" "a string no entry mentions at all says exactly that"
P="$ROOT/p3b"; make_payload "$P"; printf 'x\n' > "$P/notes-by-vaneska.md"
expect "$P" 1 "hit(s) in name" "a personal string in a file NAME halts, with the branch named"
P="$ROOT/p3c"; make_payload "$P"
printf '\211PNG\r\n\032\n\000\000 Vaneska \000' > "$P/assets/hero.png"
expect "$P" 1 "FINDING personal-str  assets/hero.png" "a personal string in BINARY bytes halts, media directory or not"
P="$ROOT/p3d"; make_payload "$P"; printf 'contact VANESKA and vaneska\n' > "$P/MANUAL.md"
expect "$P" 1 "2 hit(s)" "matching is case-insensitive, and occurrences are counted"
P="$ROOT/p3e"; make_payload "$P"; printf 'no owner strings here at all\n' > "$P/MANUAL.md"
expect "$P" 0 "check: clean" "a payload with no personal string passes"
P="$ROOT/p3f"; make_payload "$P"; printf 'Copyright (c) Quillsworth Vaneska\n' > "$P/LICENSE.md"
expect "$P" 0 "check: clean" "an allowlisted string passes IN the file its entry names"
P="$ROOT/p3g"; make_payload "$P"; printf 'Copyright (c) Quillsworth Vaneska\n' > "$P/MANUAL.md"
expect "$P" 1 "but not in this file" "the SAME string halts in a file the entry does not name"
P="$ROOT/p3h"; make_payload "$P"; printf 'Zephyrine and Zephyrine\n' > "$P/.claude/skills/ingest/SKILL.md"
expect "$P" 0 "check: clean" "a provisional entry passes AT its per-file count"
P="$ROOT/p3i"; make_payload "$P"; printf 'Zephyrine and Zephyrine and Zephyrine\n' > "$P/.claude/skills/ingest/SKILL.md"
expect "$P" 1 "over the cap of 2" "one occurrence over the count halts, naming the cap"
P="$ROOT/p3j"; make_payload "$P"
GUARD_EXTRA=(--release v0.9.9); expect "$P" 0 "check: clean" "a release below a provisional expiry passes"
GUARD_EXTRA=(--release v1.0); expect "$P" 1 "FINDING allowlist-exp" "the release that reaches the expiry halts"
GUARD_EXTRA=(--release v1); expect "$P" 1 "FINDING allowlist-exp" "v1 and v1.0 compare equal, so the grammar cannot be dodged"
GUARD_EXTRA=(--release 2.0.0); expect "$P" 1 "FINDING allowlist-exp" "a later release still halts, with or without the v"
GUARD_EXTRA=(--release nonsense); expect "$P" 2 "does not parse as a version" "an unparseable release is a broken premise"
GUARD_EXTRA=()
expect "$P" 0 "provisional: <agent name> expires at v1.0" "every run reports the pending expiry for the recap"
expect "$P" 0 "corpus control" "the clean line carries the corpus control's hit count"
expect "$P" 0 "string probes" "and the string-probe tally beside the other two"
# The floor, and the owner-local extras file that is exempt from it.
P="$ROOT/p3k"; make_payload "$P"; printf 'the fxv directory and the fxvault\n' > "$P/MANUAL.md"
expect "$P" 0 "check: clean" "a path component below the byte floor is not a needle"
mkdir -p "$FXV/output"; printf '# extras\n\nfxv\n' > "$FXV/output/publish-gate-strings.txt"
expect "$P" 1 "from extra" "a line in the gate-strings file IS a needle, floor or not"
expect "$P" 1 "extra strings: 1 line" "and the run says how many extra lines it read"
rm "$FXV/output/publish-gate-strings.txt"; rmdir "$FXV/output"
expect "$P" 0 "extra strings: none" "with the file gone the run says so, rather than staying silent"
# Inspection, and the negative control for the whole probe.
guard "$P"
if printf '%s' "$OUT" | grep -q "inert:"; then ok "an entry that matched no needle is reported inert"
else no "an entry that matched no needle is reported inert: $(echo "$OUT" | tail -1)"; fi
GUARD_EXTRA=(--print-needles); guard "$P"; GUARD_EXTRA=()
if printf '%s' "$OUT" | grep -q "^needle  Zephyrine .*agent-name"; then ok "--print-needles shows each needle with the class it came from"
else no "--print-needles shows each needle with its class"; fi
if printf '%s' "$OUT" | grep -q "^needle  .*fxaccount"; then ok "the machine account name is derived even though it is not in the vault path"
else no "the machine account name is derived"; fi
if printf '%s' "$OUT" | grep -q "^check: clean" && ! printf '%s' "$OUT" | grep -q "Zephyrine\b.*FINDING"; then
  ok "control: a needle list this long still reports clean on a payload that carries none"
else no "control: a clean payload with many needles"; fi

echo "── group 10: the allowlist is parsed, and every malformed shape exits 2 ──"
printf '# fixture allowlist\n\n- <mystery class> :: `README.md` :: planted\n' > "$ROOT/al10a.md"
FXA="$ROOT/al10a.md"; expect "$P" 2 "unknown placeholder" "an unknown placeholder is a broken premise"
printf '# fixture allowlist\n\n- SomeString :: nowhere in particular :: planted\n' > "$ROOT/al10b.md"
FXA="$ROOT/al10b.md"; expect "$P" 2 "names no file" "an entry naming no file is a broken premise"
printf '# fixture allowlist\n\n- SomeString :: `README.md` (3) :: planted\n' > "$ROOT/al10c.md"
FXA="$ROOT/al10c.md"; expect "$P" 2 "must not carry a per-file count" "a count on a permanent entry is a broken premise"
printf '# fixture allowlist\n\n- S :: PROVISIONAL, expires at v1.0 — `README.md` :: planted\n' > "$ROOT/al10d.md"
FXA="$ROOT/al10d.md"; expect "$P" 2 "needs a per-file count" "a provisional path with no count is a broken premise"
printf '# fixture allowlist\n\n- <agent name> :: PROVISIONAL, expires at v1.0 — `SKILL.md` (1), `ingest/SKILL.md` (3) :: planted\n' > "$ROOT/al10e.md"
P="$ROOT/p3l"; make_payload "$P"; printf 'Zephyrine Zephyrine\n' > "$P/.claude/skills/ingest/SKILL.md"
FXA="$ROOT/al10e.md"
expect "$P" 0 "check: clean" "where two entry paths both cover a file, the LONGEST binds (its cap, not the short one's)"
P="$ROOT/p3k"
printf '# nothing parseable\n' > "$ROOT/al10f.md"
FXA="$ROOT/al10f.md"; expect "$P" 2 "parsed to 0 entries" "an allowlist that parses to nothing is a broken premise"
FXA="$ROOT/al10g.md"; expect "$P" 2 "is missing" "a missing allowlist is a broken premise, not an empty one"
FXA="$ALL_DEFAULT"
# The shipped pair must parse: the fixture must not be hiding a defect in the real files.
OUT="$(env USER=fxaccount LOGNAME=fxaccount HOME="$FXH" GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_SYSTEM=/dev/null python3 "$GUARD" --vault "$FXV" --print-needles \
        "$ROOT/p3e" 2>&1)"; RC=$?
if [ "$RC" = 0 ]; then ok "control: the SHIPPED allowlist parses and adjudicates a real run"
else no "control: the shipped allowlist parses (exit $RC): $(echo "$OUT" | head -2)"; fi
printf '# fixture contract\n' > "$ROOT/novault/CLAUDE.md" 2>/dev/null || mkdir -p "$ROOT/novault"
printf '# fixture contract\n' > "$ROOT/novault/CLAUDE.md"
FXV_SAVE="$FXV"; FXV="$ROOT/novault"
expect "$P" 2 "cannot derive the owner's strings" "a vault with no preference layer is a broken premise, never a skipped probe"
mkdir -p "$ROOT/noname"; printf '# c\n' > "$ROOT/noname/CLAUDE.md"; printf 'marker\n\n## Settings\n- **style**: brief\n' > "$ROOT/noname/CUSTOMISATION.md"
FXV="$ROOT/noname"; expect "$P" 2 "no \`agent_name\` line" "a preference layer that lost its agent_name line is a broken premise"
mkdir -p "$ROOT/blankname"; printf '# c\n' > "$ROOT/blankname/CLAUDE.md"; printf 'marker\n\n## Settings\n- **agent_name**:  — blank means none\n' > "$ROOT/blankname/CUSTOMISATION.md"
FXV="$ROOT/blankname"; expect "$P" 0 "check: clean" "a BLANK agent_name is legitimate (setup.sh seeds it blank) and yields no needle"
FXV="$FXV_SAVE"

echo "── group 8: the gate is wired into the publish flow ──"
if grep -q "publish_guard.py" "$SKILL/SKILL.md"; then ok "SKILL.md's publish flow invokes the guard"
else no "SKILL.md's publish flow invokes the guard"; fi
if grep -q "publish_guard.py" "$SKILL/RUNBOOK.md"; then ok "RUNBOOK.md's verify list invokes the guard"
else no "RUNBOOK.md's verify list invokes the guard"; fi
if grep -q "publish_guard_v99.py" "$SKILL/SKILL.md"; then
  no "control: the same grep should MISS a name the skill does not carry"
else ok "control: the same grep misses a name the skill does not carry"; fi

echo
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
