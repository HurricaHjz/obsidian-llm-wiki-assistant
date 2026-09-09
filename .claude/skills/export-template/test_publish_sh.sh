#!/usr/bin/env bash
# test_publish_sh.sh — isolated tests for publish.sh, the export-template publish chain.
# Builds a throwaway vault, a bare remote and a clone under $TMPDIR and runs the whole chain
# against them. NEVER touches the real vault, and never pushes anywhere but the fixture's own bare
# repo (asserted before every publish run). Run:  bash test_publish_sh.sh
#
# Premise guard: this suite needs process substitution. Invoked as `sh <file>` it dies mid-run with
# a raw syntax error and exit 2, and a caller grepping the output for "FAIL" then reads zero and
# calls it green (the rule test_export_template.sh states at its head; the capability is probed,
# never the shell name).
if ! (eval 'cat < <(echo probe)') >/dev/null 2>&1; then
  echo "ERROR: process substitution unavailable (POSIX mode?) — run: bash $0"; exit 2
fi

set -uo pipefail

# `pwd -P`, never `pwd`: the fixture copies this directory into a throwaway vault and then writes
# inside that copy (an allowlist entry, a renamed gate script). Reached through a symbolic link the
# logical path would copy the LINK, and every one of those writes would land in the real skill
# directory instead — observed 2026-09-08, when a sibling suite's pull-apply leg wrote through such
# a link. The physical path cannot do that, and the premise below refuses to run if it ever could.
SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"  # the export-template skill under test
PUB="$SKILL/publish.sh"
# A staged copy names the vault it borrows two things from: the delegate skill's throttle.py (the
# throttle gate is the real one, never a stand-in) and the routed agent definitions that gate
# compares. Default: the vault this skill sits in — the same three-up derivation publish_guard.py
# uses, and the escape test_handsoff.sh's HOOKS_DIR is.
VAULT_DIR=${VAULT_DIR:-$(cd "$SKILL/../../.." && pwd)}

[ -f "$PUB" ] || { echo "PROBE FAILED: no publish.sh beside this test ($SKILL)"; exit 2; }
[ -f "$VAULT_DIR/.claude/skills/delegate/throttle.py" ] \
  || { echo "PROBE FAILED: no .claude/skills/delegate/throttle.py under $VAULT_DIR (set VAULT_DIR)"; exit 2; }
[ -f "$VAULT_DIR/.claude/skills/delegate/routing.json" ] \
  || { echo "PROBE FAILED: no routing.json under $VAULT_DIR/.claude/skills/delegate (set VAULT_DIR)"; exit 2; }
[ -d "$VAULT_DIR/.claude/agents" ] \
  || { echo "PROBE FAILED: no .claude/agents under $VAULT_DIR (set VAULT_DIR)"; exit 2; }

# This suite SHIPS inside `.claude/skills/**`, so the payload gate it drives scans this very file.
# Every fixture string that becomes a needle — the vault directory's own name, the account name, the
# home basename — is therefore assembled at run time from the pid: written as a literal it would
# make the gate fire on this file, and each leg's "clean" would be this suite's own defect
# (the rule test_publish_guard.sh states at its head, for the same reason).
ID="$$"
ROOT="${TMPDIR:-/tmp}/pubshtest.$ID"
V="$ROOT/vlt$ID"
REMOTE="$ROOT/remote.git"
CLONE="$ROOT/clone"
FXH="$ROOT/h$ID"
FXU="acct$ID"
PUBV="$V/.claude/skills/export-template/publish.sh"       # the installed copy the legs run
GUARDV="$V/.claude/skills/export-template/publish_guard.py"
RECAP="$V/output/publish-recap.txt"                       # publish.sh's default recap path
VER="v0.9.0"
GIT="git -c user.email=t@t -c user.name=test -c commit.gpgsign=false -c init.defaultBranch=main"
# A home-directory path, assembled: probe 1's class, planted in a shipped vault file.
U="/U""sers"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }
chk(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1"; fi; }

# ── fixture ──────────────────────────────────────────────────────────────────────────────────
# build_fake_vault is test_export_template.sh's, copied rather than sourced (sourcing that file
# runs its whole suite) and trimmed to what this chain needs, plus three additions the gates read:
# a CUSTOMISATION `## Settings` block (agent name + throttle), the delegate skill's throttle.py and
# routing.json, and the routed agent definitions. A vault-local block and a root .gitignore are
# planted deliberately: they are the drift check's by-design differences.
build_fake_vault(){
  rm -rf "$ROOT"
  mkdir -p "$V/.claude/skills" "$V/.claude/agents" "$V/.claude/skills/delegate" "$V/.obsidian" \
           "$V/wiki/sources" "$V/raw" "$V/assets" "$V/output" "$V/attic" "$FXH"
  printf '# CLAUDE (test contract)\n\nA line every copy carries.\n' > "$V/CLAUDE.md"
  printf '# Manual (test)\n' > "$V/MANUAL.md"
  printf '# README (test)\n\n![graph](assets/framework_demo.png)\n\nSee the [Manual](MANUAL.md).\n' > "$V/README.md"
  printf 'FAKE-PNG-BYTES\n' > "$V/assets/framework_demo.png"
  printf 'MIT License (test)\n' > "$V/LICENSE.md"
  printf '# the fixture vault ignores its own scratch\n/output/**\n' > "$V/.gitignore"
  for f in app core-plugins appearance; do printf '{\n  "x": 1\n}\n' > "$V/.obsidian/$f.json"; done
  printf '{ "colorGroups": [ {"query":"path:wiki/models/","color":1} ], "scale": 0.5, "close": true }\n' \
    > "$V/.obsidian/graph.json"
  for s in ingest query lint; do
    mkdir -p "$V/.claude/skills/$s"; printf '# %s skill\n' "$s" > "$V/.claude/skills/$s/SKILL.md"
  done
  cp -R "$SKILL" "$V/.claude/skills/export-template"
  [ ! -L "$V/.claude/skills/export-template" ] \
    || { echo "PROBE FAILED: the fixture's skill copy is a symbolic link — the fixture's writes would leave the fixture"; rm -rf "$ROOT"; exit 2; }
  cp "$VAULT_DIR/.claude/skills/delegate/throttle.py" "$VAULT_DIR/.claude/skills/delegate/routing.json" \
     "$V/.claude/skills/delegate/"
  printf '# delegate skill (throttle.py + routing.json are the real ones)\n' > "$V/.claude/skills/delegate/SKILL.md"
  cp "$VAULT_DIR"/.claude/agents/*.md "$V/.claude/agents/"
  printf '# secret note\npersonal data here\n' > "$V/wiki/sources/secret.md"
  printf 'raw source\n' > "$V/raw/source1.md"
  set_throttle auto
}

# The preference layer the gates read: publish_guard.py needs an `agent_name` line, throttle.py the
# `throttle` line. Both live in `## Settings`, which is where throttle.py rewrites it.
set_throttle(){
  printf 'marker\n\n## Settings\n- **agent_name**: Zeph%s — what the agent calls itself\n- **throttle**: %s — routing throttle\n' \
    "$ID" "$1" > "$V/CUSTOMISATION.md"
}

# A vault-local block: its content is stripped from the shipped copy, so the staged CLAUDE.md
# differs from the vault's BY DESIGN and the drift check must name it exempt, never as drift.
# The argument varies the line OUTSIDE the block, so the shipped copy changes too and the path
# reaches the staged diff the drift check reads.
add_vault_local(){
  printf '# CLAUDE (test contract)\n\nA line every copy carries — %s.\n<!-- vault-local:begin -->\nowner-only wiring\n<!-- vault-local:end -->\n' \
    "$1" > "$V/CLAUDE.md"
}

# The .obsidian file apply_fixes() rewrites: changing it in the vault puts the transformed path in
# the staged diff, which is where the transform exemption has to hold.
bump_graph(){
  printf '{ "colorGroups": [ {"query":"path:wiki/models/","color":%s} ], "scale": 0.5, "close": true }\n' \
    "$1" > "$V/.obsidian/graph.json"
}

# The gate derives a needle from every component of the vault's own absolute path. A throwaway
# vault under the temp root contributes ordinary words — on macOS /tmp resolves through /private,
# so `private` is one — and they occur legitimately in the framework text this fixture ships.
# They are adjudicated in the FIXTURE's copy of the allowlist, under the placeholder the gate
# provides for exactly this class, scoped file by file from a run-time grep of the built payload
# rather than a hand list. It cannot mask the planted leak: that is a machine PATH, probe 1, which
# no allowlist entry covers.
adjudicate_path_components(){
  local comps files f n=0
  comps="$(python3 -c 'import os, sys
v = sys.argv[1]
out = set()
for form in {os.path.abspath(v), os.path.realpath(v)}:
    for c in form.split("/"):
        if len(c.encode("utf-8")) >= 4:
            out.add(c)
print("\n".join(sorted(out)))' "$V")"
  files=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    while IFS= read -r f; do
      case ", $files" in *", \`${f#"$CLONE"/}\`"*) continue ;; esac
      files="$files, \`${f#"$CLONE"/}\`"; n=$((n + 1))
    done < <(grep -rl --exclude-dir=.git -- "$c" "$CLONE" | sort)
  done <<< "$comps"
  if [ -n "$files" ]; then
    printf -- '- <vault path component> :: %s :: fixture: this throwaway vault sits under the temp root, whose components are ordinary words that the shipped text uses in its own sense\n' \
      "${files#, }" >> "$V/.claude/skills/export-template/publish-allowlist.md"
  fi
  echo "$n"
}

setup_published(){
  build_fake_vault
  add_vault_local zero
  $GIT init -q --bare "$REMOTE"
  $GIT clone -q "$REMOTE" "$CLONE" 2>/dev/null
  bash "$V/.claude/skills/export-template/export_template.sh" --push "$CLONE" >/dev/null 2>&1
  ( cd "$CLONE" && $GIT add -A && $GIT commit -qm init && $GIT push -qu origin main ) >/dev/null 2>&1
  # The repo's .gitignore edited on the repo side: the next overlay restores it from the skill
  # payload, so it lands in the staged diff — the packaged-file exemption's live case.
  printf '\n# edited on the repo side\n' >> "$CLONE/.gitignore"
  ( cd "$CLONE" && $GIT add -A && $GIT commit -qm "repo-side edit" && $GIT push -q ) >/dev/null 2>&1
  ADJUDICATED="$(adjudicate_path_components)"
}

bump_vault(){ printf '# Manual (test) — %s\n' "$1" > "$V/MANUAL.md"; }

count_bare(){ $GIT -C "$REMOTE" rev-list --count main; }
count_clone(){ $GIT -C "$CLONE" rev-list --count HEAD; }

# every run: the fixture's own account, home and git identity, so the gate derives fixture needles
# and never this machine's. Identity travels in the environment, never in the repo's config, which
# is what probe 3 reads.
run_publish(){
  OUT="$(env USER="$FXU" LOGNAME="$FXU" HOME="$FXH" \
             GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
             GIT_AUTHOR_NAME="A$ID" GIT_AUTHOR_EMAIL="a$ID@example.invalid" \
             GIT_COMMITTER_NAME="A$ID" GIT_COMMITTER_EMAIL="a$ID@example.invalid" \
             bash "$PUBV" "$@" 2>&1)"; RC=$?
}

# the only remote this suite may push to
assert_fixture_remote(){
  local url; url="$($GIT -C "$CLONE" config --get remote.origin.url)"
  case "$url" in
    "$ROOT"/*) ok "the push target is the fixture's own bare repo ($1)" ;;
    *) echo "PROBE FAILED: the push target is not the fixture's bare repo ($1): $url"; rm -rf "$ROOT"; exit 2 ;;
  esac
}

# a checksum manifest of the vault, output/ excluded (the recap's home) and .git excluded
manifest(){ find "$V" -type f -not -path "*/output/*" -not -path "*/.git/*" -print0 \
              | xargs -0 shasum -a 256 | sort; }

hasline(){ printf '%s' "$OUT" | grep -q -- "$1"; }

echo "== fixture: a throwaway vault, a bare remote and a published clone =="
setup_published
chk "fixture: the clone holds a published framework" '[ -f "$CLONE/CLAUDE.md" ] && [ -d "$CLONE/.claude/skills/export-template" ]'
chk "fixture: publish.sh is installed in the fixture vault" '[ -f "$PUBV" ]'
B0="$(count_bare)"; C0="$(count_clone)"
chk "fixture: the bare repo has commits to count" '[ "$(count_bare)" -ge 2 ]'
chk "fixture: the vault's own path components are adjudicated in the fixture allowlist" '[ "$ADJUDICATED" -ge 1 ]'

echo "== group 1: the clean run stops at the recap with nothing committed =="
bump_vault one
add_vault_local one
bump_graph 2
rm -f "$RECAP"
M_BEFORE="$(manifest)"
run_publish --release "$VER" "$CLONE"
G1OUT="$OUT"                                   # the recap-only run's whole stdout: its LAST line is the digest
chk "clean: exit 0"                            '[ "$RC" = 0 ]'
chk "clean: the stop line names the recap"     'hasline "STOP: recap written to $RECAP"'
chk "clean: the bare repo gained no commit"    '[ "$(count_bare)" = "$B0" ]'
chk "clean: the clone gained no commit"        '[ "$(count_clone)" = "$C0" ]'
chk "clean: the recap file is non-empty"       '[ -s "$RECAP" ]'
chk "clean: the recap carries this run's completion marker" 'grep -q "^recap-complete " "$RECAP"'
chk "clean: the recap names the candidate version" 'grep -q "candidate   $VER" "$RECAP"'
chk "clean: the recap quotes the payload gate's check line" 'grep -q "^check: clean" "$RECAP"'
chk "clean: the recap quotes the personal-strings line" 'grep -q "^personal-strings:" "$RECAP"'
chk "clean: the recap carries the staged stat"     'grep -q "files* changed" "$RECAP"'
chk "clean: the recap carries git log --oneline -5" 'grep -q -- "-- git log --oneline -5 --" "$RECAP"'
chk "clean: the recap carries the throttle gate line" 'grep -q "match throttle .auto." "$RECAP"'
chk "drift: a transformed path is exempt, not drift"    'grep -q "exempt  .obsidian/graph.json  (transformed by apply_fixes())" "$RECAP"'
chk "drift: a vault-local block is exempt, not drift"   'grep -q "exempt  CLAUDE.md  (a vault-local:begin block was stripped" "$RECAP"'
chk "drift: a payload-packaged file is exempt, not drift" 'grep -q "exempt  .gitignore  (packaged from the skill payload" "$RECAP"'
chk "drift: the run reports no drift"                   'grep -q "  drift: none" "$RECAP"'
chk "digest: the recap carries a 12-character recap-digest line" 'grep -q "^recap-digest [0-9a-f]\{12\}$" "$RECAP"'
chk "digest: the recap names the staged index tree hash" 'grep -q "^tree        [0-9a-f]\{40\}$" "$RECAP"'
chk "digest: the recap's tree line IS the clone's staged tree" \
    '[ "$(sed -n "s/^tree        //p" "$RECAP" | head -1)" = "$($GIT -C "$CLONE" write-tree)" ]'
chk "digest: recap-digest is the run's last stdout line" \
    '[ "$(printf "%s\n" "$G1OUT" | tail -1)" = "recap-digest $(sed -n "s/^recap-digest //p" "$RECAP")" ]'
chk "digest: the stop line tells the owner which digest to pass" \
    'printf "%s" "$G1OUT" | grep -q -- "--approved [0-9a-f]\{12\}"'
M_AFTER="$(manifest)"
chk "write scope: the vault is byte-identical after the run (output/ excluded)" '[ "$M_BEFORE" = "$M_AFTER" ]'
printf 'x\n' >> "$V/MANUAL.md"
chk "control: the same manifest DOES see a planted vault change" '[ "$M_BEFORE" != "$(manifest)" ]'
chk "write scope: the recap is the only file the run left under output/" '[ "$(ls "$V/output" | tr -d " \n")" = "publish-recap.txt" ]'

echo "== group 2: the owner's word is bound to the recap by its digest =="
# The word authorises ONE recap. These legs are the ways that binding can be broken; the publish in
# group 2c is their positive control — the same command, with the digest of the recap on disk.
bump_vault one                                 # undo the manifest control's plant: these legs re-gate this tree
D1="$(sed -n 's/^recap-digest //p' "$RECAP")"
chk "digest: the recap-only run left a digest to approve" '[ "${#D1}" = 12 ]'
run_publish --release "$VER" --publish "yes, publish it" --message "publish: $VER (fixture)" "$CLONE"
chk "--publish without --approved: exit 2"     '[ "$RC" = 2 ]'
chk "--publish without --approved: the three flags are named as one set" 'hasline "STOP premise — --publish, --message and --approved come as a set"'
chk "--publish without --approved: nothing committed" '[ "$(count_bare)" = "$B0" ]'
run_publish --release "$VER" --approved "$D1" "$CLONE"
chk "--approved without --publish: exit 2"     '[ "$RC" = 2 ]'
chk "--approved without --publish: nothing committed" '[ "$(count_bare)" = "$B0" ]'
run_publish --release "$VER" --publish "yes, publish it" --message "m" --approved 000000000000 "$CLONE"
chk "a digest naming no recap: exit 1"         '[ "$RC" = 1 ]'
chk "a digest naming no recap: the recap-digest section is the named difference" 'hasline "STOP approval — section recap-digest"'
chk "a digest naming no recap: nothing committed" '[ "$(count_bare)" = "$B0" ]'
chk "a digest naming no recap: the approved recap was NOT truncated" 'grep -q "^recap-digest $D1$" "$RECAP"'
chk "a digest naming no recap: the run neither pulled nor overlaid" '! hasline "^-- overlay" && ! hasline "^-- pull"'
printf 'one more staged file\n' > "$CLONE/EXTRA.md"
$GIT -C "$CLONE" add EXTRA.md >/dev/null 2>&1
run_publish --release "$VER" --publish "yes, publish it" --message "m" --approved "$D1" "$CLONE"
chk "the index mutated by one more staged file: exit 1" '[ "$RC" = 1 ]'
chk "the index mutated: the tree section is the named difference" 'hasline "STOP approval — section tree differs"'
chk "the index mutated: nothing committed"     '[ "$(count_bare)" = "$B0" ]'
$GIT -C "$CLONE" rm -q --cached EXTRA.md >/dev/null 2>&1; rm -f "$CLONE/EXTRA.md"
chk "control: unstaging it restores the tree the recap named" \
    '[ "$($GIT -C "$CLONE" write-tree)" = "$(sed -n "s/^tree        //p" "$RECAP" | head -1)" ]'

echo "== group 2b: a regenerated recap retires the digest the word was given on =="
bump_vault two                                 # the vault moves, so the fresh recap covers a different tree
run_publish --release "$VER" "$CLONE"
D2="$(sed -n 's/^recap-digest //p' "$RECAP")"
chk "regenerated: the second recap digests differently" '[ "${#D2}" = 12 ] && [ "$D2" != "$D1" ]'
run_publish --release "$VER" --publish "yes, publish it" --message "publish: $VER (fixture)" --approved "$D1" "$CLONE"
chk "regenerated: the earlier digest exits 1"  '[ "$RC" = 1 ]'
chk "regenerated: the recap-digest section is the named difference" 'hasline "STOP approval — section recap-digest"'
chk "regenerated: the run says the recap on disk is a different one" 'hasline "The recap was regenerated after the word was given"'
chk "regenerated: nothing committed"           '[ "$(count_bare)" = "$B0" ]'
chk "regenerated: the recap on disk is still the fresh one, intact" 'grep -q "^recap-digest $D2$" "$RECAP"'

echo "== group 2c: with that recap's digest the word commits and pushes =="
assert_fixture_remote "publish leg"
run_publish --release "$VER" --publish "yes, publish it" --message "publish: $VER (fixture)" --approved "$D2" "$CLONE"
chk "publish: exit 0"                          '[ "$RC" = 0 ]'
chk "publish: the approval check names the recap and tree it approved" 'hasline "approved: recap $D2" && hasline "tree $($GIT -C "$CLONE" write-tree)"'
chk "publish: the run reports the push"        'hasline "PUBLISHED:"'
chk "publish: the run did not pull again"      '! hasline "^-- pull"'
chk "publish: the run did not overlay again"   '! hasline "^-- overlay"'
chk "publish: all four gates ran again on the staged index" \
    'hasline "^-- drift check" && hasline "^-- payload gate" && hasline "^-- release gate" && hasline "^-- throttle gate"'
chk "publish: the bare repo gained exactly one commit" '[ "$(count_bare)" = "$((B0 + 1))" ]'
chk "publish: the clone gained exactly one commit"     '[ "$(count_clone)" = "$((C0 + 1))" ]'
chk "publish: the commit carries the given message"    '$GIT -C "$REMOTE" log -1 --pretty=%s main | grep -q "publish: $VER (fixture)"'
chk "publish: the committed tree IS the tree the recap named" \
    '[ "$($GIT -C "$REMOTE" rev-parse "main^{tree}")" = "$(sed -n "s/^tree        //p" "$RECAP" | head -1)" ]'
chk "publish: the recap records the owner word"        'grep -q "owner word   yes, publish it" "$RECAP"'
B1="$(count_bare)"; C1="$(count_clone)"

echo "== group 2d: a vault that moved after the recap is drift, never a publish =="
bump_vault vaultmoved
run_publish --release "$VER" "$CLONE"
D3="$(sed -n 's/^recap-digest //p' "$RECAP")"
chk "fixture: a fresh recap after the publish" '[ "$RC" = 0 ] && [ "${#D3}" = 12 ]'
bump_vault vaultmovedagain                     # a concurrent session edits a shipped file after the word
run_publish --release "$VER" --publish "yes, publish it" --message "publish: moved" --approved "$D3" "$CLONE"
chk "vault moved: exit 1"                      '[ "$RC" = 1 ]'
chk "vault moved: the approval check passed (the index is untouched)" 'hasline "approved: recap $D3"'
chk "vault moved: the drift check is the named stop"  'hasline "STOP drift"'
chk "vault moved: the STOP says what it leaves in the clone" 'hasline "reset -q"'
chk "vault moved: nothing committed"           '[ "$(count_bare)" = "$B1" ]'
chk "vault moved: the approved recap is intact" 'grep -q "^recap-digest $D3$" "$RECAP"'
bump_vault vaultmoved                          # control: the vault back where the recap saw it
run_publish --release "$VER" --publish "yes, publish it" --message "publish: moved" --approved "$D3" "$CLONE"
chk "control: with the vault back the same digest publishes" '[ "$RC" = 0 ] && hasline "PUBLISHED:"'
chk "control: the bare repo gained exactly one commit" '[ "$(count_bare)" = "$((B1 + 1))" ]'
B1="$(count_bare)"; C1="$(count_clone)"

echo "== group 2e: the release gate is a step of its own =="
# The shipped allowlist carries a provisional entry expiring at v1.0: a candidate that has reached
# it is a finding the payload gate alone never sees, which is why --release is required.
bump_vault twob
run_publish --release v1.0 "$CLONE"
chk "release gate: a candidate at a provisional entry's expiry stops the chain" '[ "$RC" = 1 ]'
chk "release gate: the release gate is the named stop"      'hasline "STOP release-gate"'
chk "release gate: the payload gate passed on the same tree" 'hasline "^check: clean"'
chk "release gate: nothing committed"                        '[ "$(count_bare)" = "$B1" ]'

echo "== group 3: a planted payload leak stops the chain at the gate =="
bump_vault three
printf '# CLAUDE (test contract)\n\nsee %s/%s/notes.md for the wiring\n' "$U" "$FXU" > "$V/CLAUDE.md"
rm -f "$RECAP"
run_publish --release "$VER" "$CLONE"
chk "leak: exit 1"                             '[ "$RC" = 1 ]'
chk "leak: the payload gate is the named stop" 'hasline "STOP payload-gate — the gate reported a finding (exit 1)"'
chk "leak: the guard's finding names the file" 'hasline "CLAUDE.md"'
chk "leak: nothing committed in the bare repo" '[ "$(count_bare)" = "$B1" ]'
chk "leak: nothing committed in the clone"     '[ "$(count_clone)" = "$C1" ]'
chk "leak: no completed recap was left behind" '! grep -q "^recap-complete " "$RECAP"'
assert_fixture_remote "leak + --publish leg"
# The gate stopped that run before it wrote a recap, so there is no recap to approve and the digest
# the owner holds from an earlier run names none of it: the publish is refused on the premise, not
# on the gate — the tree the failed run would have shipped was never presented to anybody.
run_publish --release "$VER" --publish "yes, publish it" --message "publish: leaked" --approved "$D3" "$CLONE"
chk "leak + --publish: exit 2 (the failed run left no completed recap)" '[ "$RC" = 2 ]'
chk "leak + --publish: the missing completion marker is named" 'hasline "STOP approval — .* carries no completion marker"'
chk "leak + --publish: nothing committed"      '[ "$(count_bare)" = "$B1" ] && [ "$(count_clone)" = "$C1" ]'
chk "leak + --publish: nothing pushed"         '! hasline "PUBLISHED:"'
add_vault_local three                          # negative control: the same tree, plant removed
run_publish --release "$VER" "$CLONE"
chk "control: with the plant removed the same tree reaches the recap" '[ "$RC" = 0 ] && hasline "STOP: recap written"'

echo "== group 4: a broken premise stops before any write =="
mv "$GUARDV" "$GUARDV.away"
rm -f "$RECAP"
run_publish --release "$VER" "$CLONE"
chk "no guard: exit 2"                         '[ "$RC" = 2 ]'
chk "no guard: the missing gate is named"      'hasline "STOP premise — no publish_guard.py"'
chk "no guard: the chain never started"        '! hasline "^-- pull"'
chk "no guard: nothing committed"              '[ "$(count_bare)" = "$B1" ]'
mv "$GUARDV.away" "$GUARDV"
run_publish --release "$VER" "$ROOT/no-such-clone"
chk "bad repo: exit 2"                         '[ "$RC" = 2 ]'
chk "bad repo: the path is named"              'hasline "is not a directory"'
chk "bad repo: no recap was written"           '[ ! -e "$RECAP" ]'
chk "bad repo: nothing committed"              '[ "$(count_bare)" = "$B1" ]'
mkdir -p "$ROOT/plain"
run_publish --release "$VER" "$ROOT/plain"
chk "not a clone: exit 2 and says so"          '[ "$RC" = 2 ] && hasline "is not a git clone"'
run_publish --release "$VER" --publish "yes" "$CLONE"
chk "--publish without --message: exit 2"      '[ "$RC" = 2 ] && hasline "STOP premise — --publish needs --message"'
run_publish --release "$VER" --message "m" "$CLONE"
chk "--message without --publish: exit 2"      '[ "$RC" = 2 ] && hasline "the owner'\''s word is what authorises"'
run_publish "$CLONE"
chk "no --release: exit 2 (the release gate is never skipped)" '[ "$RC" = 2 ] && hasline "release <ver> is required"'
run_publish --release "$VER" --sneak x "$CLONE"
chk "an unknown option: exit 2"                '[ "$RC" = 2 ] && hasline "unknown option --sneak"'
printf 'stale\n' > "$RECAP"; chmod 444 "$RECAP"
run_publish --release "$VER" "$CLONE"
chk "unwritable recap: exit 2"                 '[ "$RC" = 2 ]'
chk "unwritable recap: the recap is the named stop" 'hasline "STOP recap — cannot write"'
chk "unwritable recap: the chain never started" '! hasline "^-- pull"'
chk "unwritable recap: nothing committed"      '[ "$(count_bare)" = "$B1" ]'
chmod 644 "$RECAP"; rm -f "$RECAP"
# A first invocation that goes straight to --publish: there is no recap on disk, so there is nothing
# the owner can have read, and the run stops on the premise before it touches the clone.
run_publish --release "$VER" --publish "yes, publish it" --message "m" --approved "$D3" "$CLONE"
chk "--publish with no recap on disk: exit 2"  '[ "$RC" = 2 ]'
chk "--publish with no recap on disk: the missing recap is the named stop" 'hasline "STOP recap — no recap at"'
chk "--publish with no recap on disk: no recap was created either" '[ ! -e "$RECAP" ]'
chk "--publish with no recap on disk: no gate ran" '! hasline "^-- drift check"'
chk "--publish with no recap on disk: nothing committed" '[ "$(count_bare)" = "$B1" ]'

echo "== group 4b: the repo argument may not be this vault (two repos, never crossed) =="
# The vault is itself a git clone with a private remote, so it passes every other repo premise:
# directory, .git, work tree. Mistyped as the repo it would have the overlay written onto it.
$GIT init -q "$V" >/dev/null 2>&1              # give the fixture vault the property the real one has
chk "fixture: the vault now looks like a clone (the premise the guard must catch)" '[ -d "$V/.git" ]'
MV_BEFORE="$(manifest)"
run_publish --release "$VER" "$V"
chk "repo = vault: exit 2"                     '[ "$RC" = 2 ]'
chk "repo = vault: the two-repos premise is the named stop" 'hasline "STOP premise — the repo clone is this vault itself"'
chk "repo = vault: the chain never started"    '! hasline "^-- pull"'
chk "repo = vault: nothing was written in the vault" '[ "$MV_BEFORE" = "$(manifest)" ]'
chk "repo = vault: nothing was staged in the vault" '[ -z "$($GIT -C "$V" diff --cached --name-only)" ]'
chk "repo = vault: nothing committed in the bare repo" '[ "$(count_bare)" = "$B1" ]'
run_publish --release "$VER" --vault "$V" "$CLONE"
chk "control: the same vault named as --vault, with the clone as the repo, runs" '[ "$RC" = 0 ] && hasline "STOP: recap written"'
rm -rf "$V/.git"

echo "== group 5: the throttle gate =="
bump_vault five
set_throttle default
run_publish --release "$VER" "$CLONE"
chk "throttle default: exit 1"                 '[ "$RC" = 1 ]'
chk "throttle default: the throttle gate is the named stop" 'hasline "STOP throttle-gate"'
chk "throttle default: the gate's own finding is shown"  'hasline "REQUIRE auto: the active throttle is default"'
chk "throttle default: nothing committed"      '[ "$(count_bare)" = "$B1" ]'
set_throttle auto
run_publish --release "$VER" "$CLONE"
chk "control: back at auto the same tree reaches the recap" '[ "$RC" = 0 ] && hasline "STOP: recap written"'

echo "== group 6: drift between the staged tree and the vault =="
bump_vault six
printf 'repo side\n' > "$CLONE/NOTICE.md"
printf 'vault side\n' > "$V/NOTICE.md"
run_publish --release "$VER" "$CLONE"
chk "drift: exit 1"                            '[ "$RC" = 1 ]'
chk "drift: the drift check is the named stop" 'hasline "STOP drift"'
chk "drift: the differing path is listed"      'hasline "DRIFT   NOTICE.md"'
chk "drift: nothing committed"                 '[ "$(count_bare)" = "$B1" ]'
rm -f "$CLONE/NOTICE.md" "$V/NOTICE.md"
$GIT -C "$CLONE" reset -q >/dev/null 2>&1
run_publish --release "$VER" "$CLONE"
chk "control: with the drift removed the same tree reaches the recap" '[ "$RC" = 0 ] && hasline "STOP: recap written"'

echo "== group 7: the chain's shape is the one the skill describes =="
chk "publish.sh runs the payload gate script"   'grep -q "publish_guard.py" "$PUB"'
chk "publish.sh runs the overlay script"        'grep -q "export_template.sh" "$PUB"'
chk "publish.sh runs the throttle gate"         'grep -q "throttle.py" "$PUB"'
chk "the chain is one && list of steps"         '[ "$(grep -c "&& step_" "$PUB")" -ge 7 ]'
chk "control: the same grep misses a step the chain does not carry" '! grep -q "&& step_backup" "$PUB"'
chk "the publish chain carries an approval step" 'grep -q "&& step_drift" "$PUB" && grep -q "^  step_verify_approval" "$PUB"'
# What the script SAYS about itself, checked against what the legs above measured it doing.
chk "header: the write scope is stated, not summed as two things" \
    'grep -q "^# WHAT IT WRITES" "$PUB" && ! grep -q "writes exactly two things" "$PUB"'
chk "header: it says what a STOP leaves in the clone"   'grep -q "reset -q" "$PUB"'
chk "header: the recap doc drops the false gitignore claim" '! grep -q "output/. is gitignored, so it never ships" "$PUB"'
chk "header: the recap doc says the vault backup may commit the recap" 'grep -q "private backup commits every recap" "$PUB"'
chk "control: the same greps still find text the header does carry" \
    'grep -q "^# WHAT IT DOES NOT DO" "$PUB" && grep -q "output/publish-recap.txt" "$PUB"'
chk "the throttle preset literal carries its derivation beside it" \
    '[ "$(grep -c "require auto" "$PUB")" -ge 2 ] && grep -q "grep -n .require auto. SKILL.md" "$PUB"'

echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then echo "PASS $PASS/$TOTAL"; else echo "FAIL $FAIL/$TOTAL"; fi
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
