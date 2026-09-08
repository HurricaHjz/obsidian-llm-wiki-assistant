#!/usr/bin/env bash
# test_setup_customisation.sh — unit tests for setup.sh seeding the customisation layer.
# Runs the shipped payload/setup.sh in an isolated temp dir; NEVER touches the real vault.
# Run:  bash test_setup_customisation.sh
# Premise guard: this suite needs process substitution. Invoked as `sh <file>` it dies mid-run
# with a raw syntax error and exit 2, and a caller grepping the output for "FAIL" then reads zero
# and calls it green (observed 2026-08-28). Probe the CAPABILITY, not the shell name: on macOS
# /bin/sh IS bash, so $BASH_VERSION is set while POSIX mode still disables the feature.
if ! (eval 'cat < <(echo probe)') >/dev/null 2>&1; then
  echo "ERROR: process substitution unavailable (POSIX mode?) — run: bash $0"; exit 2
fi

set -uo pipefail
PAY="$(cd "$(dirname "${BASH_SOURCE[0]}")/payload" && pwd)/setup.sh"
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${TMPDIR:-/tmp}/setuptest.$$"
CUST="CUSTOMISATION.md"
DEFS="CUSTOMISATION-definitions.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }
hash_of(){ md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
fresh(){ rm -rf "$ROOT"; mkdir -p "$ROOT"; cp "$PAY" "$ROOT/setup.sh"; }   # isolated: setup.sh cd's to its own dir

[ -f "$PAY" ] || { echo "cannot find payload/setup.sh"; exit 2; }

echo "== 1) setup.sh parses =="
if bash -n "$PAY"; then ok "valid bash syntax"; else no "syntax error"; fi

echo "== 2) plain init seeds a valid Customisation =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "init creates $CUST"                  || no "init did not create $CUST"
grep -q '^- \*\*style\*\*: balanced' "$ROOT/$CUST" 2>/dev/null && ok "style knob seeded in ## Settings" || no "style knob missing from ## Settings"
grep -q '^## Settings' "$ROOT/$CUST" 2>/dev/null && ok "## Settings block present" || no "## Settings block missing"
sed -n '/^---$/,/^---$/p' "$ROOT/$CUST" | grep -qE '^(style|role|agent_name|language):' && no "knob still in frontmatter (import strips YAML)" || ok "no knob left in frontmatter"
grep -q '^### balanced'       "$ROOT/$CUST" 2>/dev/null && ok "default style defined in CORE" || no "default style has no ### section in core"
[ -f "$ROOT/$DEFS" ]                          && ok "init creates $DEFS (on-demand half)"  || no "init did not create $DEFS"
grep -q '^### detailed'       "$ROOT/$DEFS" 2>/dev/null && ok "detailed style in definitions file" || no "detailed style missing from $DEFS"
grep -q '^### shortest'       "$ROOT/$DEFS" 2>/dev/null && ok "shortest style in definitions file" || no "shortest style missing from $DEFS"
grep -q '^### brief'          "$ROOT/$DEFS" 2>/dev/null && ok "brief style in definitions file"    || no "brief style missing from $DEFS"
grep -q '^### detailed'       "$ROOT/$CUST" 2>/dev/null && no "detailed leaked into core (split broken)" || ok "core carries no non-default style (split holds)"
grep -q 'Definitions split'   "$ROOT/$CUST" 2>/dev/null && ok "Definitions-split rule seeded in core" || no "Definitions-split rule missing from core"
grep -q 'one canonical home per definition' "$ROOT/$CUST" 2>/dev/null && ok "block-move rule seeded" || no "block-move rule missing"
DUP=$(comm -12 <(grep '^### ' "$ROOT/$CUST" 2>/dev/null | sort) <(grep '^### ' "$ROOT/$DEFS" 2>/dev/null | sort))
[ -z "$DUP" ]                                 && ok "no ### heading duplicated across the pair" || no "duplicated heading(s): $DUP"
grep -q '\[\[About Me\]\]'    "$ROOT/$CUST" 2>/dev/null && ok "Related links [[About Me]] (no orphan)" || no "missing ## Related backlink"
grep -q '^- \*\*role\*\*: generalist' "$ROOT/$CUST" 2>/dev/null && ok "role knob seeded in ## Settings" || no "role knob missing from ## Settings"
grep -q '^- \*\*throttle\*\*: auto' "$ROOT/$CUST" 2>/dev/null && ok "throttle knob seeded in ## Settings (auto, the default preset from 2026-09-08)" || no "throttle knob missing from ## Settings"
grep -q '^- \*\*breadth\*\*: standard' "$ROOT/$CUST" 2>/dev/null && ok "breadth knob seeded in ## Settings" || no "breadth knob missing from ## Settings"
grep -q '^- \*\*delegation\*\*: auto' "$ROOT/$CUST" 2>/dev/null && ok "delegation knob seeded in ## Settings (auto is the default)" || no "delegation knob missing from ## Settings"
grep -q '^## Roles'           "$ROOT/$CUST" 2>/dev/null && ok "Roles section present"                  || no "Roles section missing"
grep -q "^### generalist" "$ROOT/$CUST" 2>/dev/null && ok "role seeded in core: generalist (default)" || no "role missing from core: generalist"
for r in researcher engineer tutor examiner; do
  grep -q "^### $r" "$ROOT/$DEFS" 2>/dev/null && ok "role seeded in definitions: $r" || no "role missing from definitions: $r"
done
grep -q "^### researcher" "$ROOT/$CUST" 2>/dev/null && no "researcher leaked into core (split broken)" || ok "core carries no non-default role (split holds)"
grep -Eq '^- overrides[ :]' "$ROOT/$CUST" && no "retired override syntax still seeded" || ok "no marked-override lines (mechanism retired 2026-08-17)"
grep -q 'no role may change the active style' "$ROOT/$CUST" 2>/dev/null && ok "roles-never-change-style clause seeded" || no "clause missing"
grep -q 'offer the full report' "$ROOT/$DEFS" 2>/dev/null && ok "examiner compression-notice line seeded" || no "notice line missing"
grep -q 'status line'         "$ROOT/$CUST" 2>/dev/null && ok "status-line rule shipped"               || no "status-line rule missing"
grep -q "never the agent's internal reasoning" "$ROOT/$CUST" 2>/dev/null && ok "reasoning-invariance clause shipped" || no "reasoning-invariance clause missing"
grep -q 'plainness and fluency hold on every style' "$ROOT/$CUST" 2>/dev/null && ok "plainness holds on every rung (one-dimension ladder, 2026-09-04)" || no "plainness preamble missing"
grep -q 'two dimensions that move together' "$ROOT/$CUST" 2>/dev/null && no "retired two-dimension sentence still seeded" || ok "control: the retired two-dimension sentence is absent"
grep -q '| depth | per request; ingest picks per source' "$ROOT/$CUST" 2>/dev/null && ok "depth axis row seeded (v0.8.8 vocabulary)" || no "depth axis row missing/stale"
grep -q '^### customised' "$ROOT/$CUST" 2>/dev/null && ok "customised span seeded (№56)" || no "customised span missing"
grep -q 'a claim, never a label' "$ROOT/$CUST" 2>/dev/null && ok "status-line claim rule seeded (№56)" || no "status-line claim rule missing"
# Parity legs (2026-09-06, step 4): three always-on paragraphs of the seeded core must be byte-identical to the live vault's
# line, so an edit to the live file that misses the seed fails here (the Roles line drifted from 2026-09-04 to 2026-09-06
# unnoticed: its `mode` clause never reached the seed; critic CRIT-S4). Each leg first proves its live anchor hits.
for anchor in 'The active role is the `role` value' '- **Plain and fluent in every reply to the owner' 'The four styles are one ladder along'; do
  LIVE_LINE=$(grep -F -m1 -e "$anchor" "$VAULT/$CUST" 2>/dev/null); SEED_LINE=$(grep -F -m1 -e "$anchor" "$ROOT/$CUST" 2>/dev/null)   # -e: an anchor may start with "-"
  if [ -z "$LIVE_LINE" ]; then no "parity premise: live anchor not found ($anchor)"; elif [ "$LIVE_LINE" = "$SEED_LINE" ]; then ok "seed parity: '${anchor}…' byte-identical to the live vault"; else no "seed parity: '${anchor}…' drifts from the live vault (seed v live)"; fi
done
T=$(( $(grep -c 'Test:' "$ROOT/$CUST" 2>/dev/null || echo 0) + $(grep -c 'Test:' "$ROOT/$DEFS" 2>/dev/null || echo 0) ))
[ "$T" -ge 6 ] && ok "per-style Test clauses seeded across the pair ($T lines)" || no "Test clauses missing ($T lines across pair, need >=6)"
RAW=$(python3 -c "
import re,sys
s=open('$ROOT/$CUST').read()
b=re.sub(r'\A---\n.*?\n---\n','',s,flags=re.S); b=re.sub(r'<!--.*?-->','',b,flags=re.S); b=re.sub(r'\`[^\`]*\`','',b)
print(len(re.findall(r'<[a-zA-Z][\w-]*>',b)))" 2>/dev/null || echo 99)
[ "$RAW" = 0 ]                                && ok "no raw HTML-parsed tokens in rendered prose"      || no "$RAW raw <tag> token(s) leak into rendered prose"
grep -q 'CUSTOMISATION-LOADED-v1'     "$ROOT/$CUST" 2>/dev/null && ok "load marker seeded"                  || no "load marker missing"
grep -q '^@CUSTOMISATION\.md' "$VAULT/CLAUDE.md" && ok "shipped CLAUDE.md imports the preference layer" || no "CLAUDE.md import line missing"
L=$(wc -l < "$ROOT/$CUST" | tr -d ' '); B=$(wc -c < "$ROOT/$CUST" | tr -d ' ')
# leanness guard only — the old ~10 KB bound encoded the hook-transport limit retired in v0.7.6; raised 2026-07-31 for the shipped Human-expert register default; raised 2026-08-14 for the four-style delivery ladder; raised 2026-08-22 for the №56 style-ceiling enforcement layer (claim + Test clauses + customised spans)
# raised 2026-08-23 for the fourth invariant (filed work is never restated) — vault↔template parity
if grep -q "Four invariants hold across the ladder" "$ROOT/CUSTOMISATION.md" && grep -q "filed work is never restated" "$ROOT/CUSTOMISATION.md"; then ok "fourth invariant (no-restatement) seeded"; else no "fourth invariant missing from seeded CUSTOMISATION"; fi
[ "$B" -le 16384 ]                            && ok "seeded core stays lean (${B} B / $L lines)"      || no "seeded core too heavy (${B} B / $L lines)"
DB=$(wc -c < "$ROOT/$DEFS" | tr -d ' ')
# defs bound: seed measures ~7.6 kB at the 2026-08-25 split; 12288 gives ~60% headroom
[ "$DB" -le 12288 ]                           && ok "seeded definitions file stays lean (${DB} B)"    || no "seeded definitions file too heavy (${DB} B)"

echo "== 2b) definitions half is idempotent too =="
printf '\nMY DEFS EDIT\n' >> "$ROOT/$DEFS"
B2=$(hash_of "$ROOT/$DEFS"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A2=$(hash_of "$ROOT/$DEFS")
[ "$A2" = "$B2" ]                             && ok "re-run preserves definitions edits"   || no "re-run overwrote definitions file"

echo "== 3) re-run is idempotent (never overwrites user edits) =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); printf '\nMY EDIT\n' >> "$ROOT/$CUST"
B=$(hash_of "$ROOT/$CUST"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A=$(hash_of "$ROOT/$CUST")
[ "$A" = "$B" ]                               && ok "re-run preserves user edits"          || no "re-run overwrote user edits"

echo "== 4) --reset preserves Customisation (user config) but blanks registries =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); printf '\nMY EDIT\n' >> "$ROOT/$CUST"
B=$(hash_of "$ROOT/$CUST"); ( cd "$ROOT" && bash setup.sh --reset >/dev/null 2>&1 ); A=$(hash_of "$ROOT/$CUST")
[ "$A" = "$B" ]                               && ok "--reset keeps Customisation"          || no "--reset clobbered Customisation"
[ -f "$ROOT/wiki/index.md" ] && [ -f "$ROOT/wiki/log.md" ] && ok "--reset re-creates registries" || no "--reset missing registries"

echo "== 5) --reset seeds Customisation when absent =="
fresh; ( cd "$ROOT" && bash setup.sh --reset >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "--reset seeds if missing"             || no "--reset did not seed"
[ -f "$ROOT/$DEFS" ]                          && ok "--reset seeds definitions half too"   || no "--reset did not seed $DEFS"

echo "== 6) --with-example seeds Customisation =="
fresh; ( cd "$ROOT" && bash setup.sh --with-example >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "--with-example seeds Customisation"   || no "--with-example did not seed"
[ -f "$ROOT/$DEFS" ]                          && ok "--with-example seeds definitions half" || no "--with-example did not seed $DEFS"

echo "== 7) mk_log seeds the full action list incl. deep-lint =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 )
grep -q 'deep-lint' "$ROOT/wiki/log.md"       && ok "log.md action list includes deep-lint" || no "log.md missing deep-lint"

echo "== 8) IDEAS.md scratchpad seeded =="
[ -f "$ROOT/IDEAS.md" ]                                    && ok "init seeds IDEAS.md at vault root"      || no "IDEAS.md not seeded"
grep -q '^## 📋 Overview' "$ROOT/IDEAS.md" 2>/dev/null     && ok "Overview table section present"         || no "Overview section missing"
grep -q 'ignores this file in normal runs' "$ROOT/IDEAS.md" 2>/dev/null && ok "ignore-by-default rule stated" || no "ignore rule missing"
printf '\n- my idea\n' >> "$ROOT/IDEAS.md"
B=$(hash_of "$ROOT/IDEAS.md"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A=$(hash_of "$ROOT/IDEAS.md")
[ "$A" = "$B" ]                                            && ok "re-run preserves owner's IDEAS edits"   || no "re-run overwrote IDEAS.md"

echo "== 9) setup.sh builds the lane home headless lanes run from =="
# The lane home is machine-local state outside the vault, so setup builds it rather than the payload
# shipping one. Three cases, because a step that runs a wrapper has three outcomes: no wrapper (a vault
# on an older framework), the wrapper succeeding, the wrapper failing its own premise (a brand-new vault
# has no confidence-rubric page to slice). In all three setup must finish and say what happened, since
# a bootstrap that aborts on an optional extra leaves the user with no registries at all.
LW=".claude/skills/delegate/lane.py"
fresh; OUT9="$( cd "$ROOT" && bash setup.sh 2>&1 )"; RC9=$?
[ "$RC9" = 0 ]                                 && ok "no wrapper: setup still succeeds"            || no "no wrapper: setup exited $RC9"
echo "$OUT9" | grep -qi 'lane home skipped'    && ok "no wrapper: says the lane home was skipped"  || no "no wrapper: silent about the lane home"
[ -f "$ROOT/wiki/index.md" ]                   && ok "no wrapper: the registries were still seeded" || no "no wrapper: registries missing"

fresh; mkdir -p "$ROOT/.claude/skills/delegate"
printf '#!/usr/bin/env python3\nimport sys\nprint("lane home: /tmp/fixture-lane-home")\nprint("  created      lane-fence.py")\nsys.exit(0)\n' > "$ROOT/$LW"
OUT9B="$( cd "$ROOT" && bash setup.sh 2>&1 )"; RC9B=$?
[ "$RC9B" = 0 ]                                && ok "wrapper ok: setup succeeds"                   || no "wrapper ok: setup exited $RC9B"
echo "$OUT9B" | grep -q 'lane home ready'      && ok "wrapper ok: setup reports the lane home ready" || no "wrapper ok: no lane-home line in output"
echo "$OUT9B" | grep -q 'fixture-lane-home'    && ok "wrapper ok: setup shows where it was built"    || no "wrapper ok: location not shown"

fresh; mkdir -p "$ROOT/.claude/skills/delegate"
printf '#!/usr/bin/env python3\nimport sys\nsys.stderr.write("lane.py: PROBE FAILED: cannot read the confidence rubric page\\n")\nsys.exit(2)\n' > "$ROOT/$LW"
OUT9C="$( cd "$ROOT" && bash setup.sh 2>&1 )"; RC9C=$?
[ "$RC9C" = 0 ]                                && ok "wrapper fails: setup still succeeds (exit 0)"  || no "wrapper fails: setup exited $RC9C"
echo "$OUT9C" | grep -q 'lane home not created' && ok "wrapper fails: setup says so plainly"         || no "wrapper fails: failure swallowed"
echo "$OUT9C" | grep -q 'PROBE FAILED'         && ok "wrapper fails: the wrapper's own reason is shown" || no "wrapper fails: reason hidden"
echo "$OUT9C" | grep -q "python3 $LW init"     && ok "wrapper fails: the recovery command is printed" || no "wrapper fails: no recovery command"
[ -f "$ROOT/wiki/index.md" ]                   && ok "wrapper fails: the registries were still seeded" || no "wrapper fails: registries missing"
# §11 control: these greps must be able to miss — a line setup.sh never prints must not match.
echo "$OUT9C" | grep -q 'lane home ready'      && no "control failed: 'ready' matched a failing run" || ok "control: the success line does not match a failing run"

echo
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
