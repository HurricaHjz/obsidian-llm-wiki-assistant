#!/bin/sh
# test_parity.sh — the suite for parity.py.   Run:  sh .claude/skills/delegate/test_parity.sh
#
# Every leg runs a real subcommand against a fixture under one /tmp root and asserts the observable
# output and the exit code. Each guard is attacked as well as exercised: a planted case that must be
# caught, a clean case that must pass, and two closing legs proving the script wrote nothing outside
# its own --out root (a checksum manifest of the read-only fixture vault and of the two shipped
# skill directories, before and after, plus a source sweep for write patterns whose own positive
# control must hit). The fixture root is removed and recreated on every run, never cleared with a
# glob, so dot-entries cannot leak into the next run. Last line: PASS n/n, or FAIL k/n.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
PY="$HERE/parity.py"
SKILLS=$(dirname "$HERE")
# The lint scripts and the lane wrapper sit beside this skill. A staged copy of the suite (a lane's
# working copy under /tmp) is not beside them, so each may also be named by an environment
# variable; a missing lint directory is a broken premise, never a quiet skip.
LINT=${PARITY_LINT_DIR:-$SKILLS/lint}
LANE=${PARITY_LANE_PY:-$HERE/lane.py}
if [ ! -d "$LINT" ]; then
  printf 'PROBE FAILED: no lint script directory at %s (name it with PARITY_LINT_DIR)\n' "$LINT"
  exit 2
fi
O=/tmp/b6-parity-suite/out.txt
B=/tmp/b6-parity-suite/brief-lint.md

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

reset_dir() {
  python3 -B -c "
import os, shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
os.makedirs(sys.argv[1])
" "$1"
}

make_dir() {
  python3 -B -c "
import os, sys
os.makedirs(sys.argv[1], exist_ok=True)
" "$1"
}

manifest() {
  python3 -B -c "
import hashlib, os, sys
rows = []
for root in sys.argv[1:]:
    for dirpath, dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            try:
                digest = hashlib.sha256(open(p, 'rb').read()).hexdigest()
            except OSError:
                digest = 'unreadable'
            rows.append(digest + ' ' + os.path.relpath(p, root))
print(chr(10).join(sorted(rows)))
" "$@"
}

run() {
  want=$1; label=$2; shift 2
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$PY" "$@" > /tmp/b6-parity-suite/out.txt 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$label (exit $got)"; else no "$label (exit $got, wanted $want)"; fi
}

has() { if grep -q -- "$2" "$O"; then ok "$1"; else no "$1 — not in output: $2"; fi; }
infile() { if grep -q -- "$2" "$3"; then ok "$1"; else no "$1"; fi; }
hasnt() { if grep -q -- "$2" "$O"; then no "$1 — output carries: $2"; else ok "$1"; fi; }
notinfile() { if grep -q -- "$2" "$3"; then no "$1 — $3 carries: $2"; else ok "$1"; fi; }
skip() { printf 'skip %s — %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- fixture tree
reset_dir /tmp/b6-parity-suite
make_dir /tmp/b6-parity-suite/arm-one
make_dir /tmp/b6-parity-suite/arm-two
make_dir /tmp/b6-parity-suite/vault/wiki
make_dir /tmp/b6-parity-suite/vault/raw     # the lint root guard (2026-09-07) wants raw/ beside wiki/
make_dir /tmp/b6-parity-suite/vault/.claude/skills/demo
make_dir /tmp/b6-parity-suite/vault/.claude/agents
make_dir /tmp/b6-parity-suite/emptylint

cat > /tmp/b6-parity-suite/arm-one/lint.md <<'ARTEFACT_A1'
# Lint artefact A1
Produced by the head of run run-20260905-handsoff, session b62193b5-2fc4-4f2b-8b74-912c4ef8d7f8,
at 2026-09-05T04:12:00Z on vendor-opus-5. The head read the pages itself; no lane, no pack.
DEAD LINKS: 0 and DEAD EMBEDS: 0 by my own count.
ARTEFACT_A1

cat > /tmp/b6-parity-suite/arm-one/query.md <<'ARTEFACT_A2'
# Query artefact A2
Written 2026-09-05 04:20 by the same head. Costs by phase are cited from the run record.
ARTEFACT_A2

cat > /tmp/b6-parity-suite/arm-two/lint.md <<'ARTEFACT_B1'
# Lint artefact B1
Produced by a thin head in run run-20260905-handsoff at 04:31 with a lint lane and a hunter pack,
model fable-5-1, session 7a1b2c3d. Counts copied from the scripts.
ARTEFACT_B1

cat > /tmp/b6-parity-suite/arm-two/query.md <<'ARTEFACT_B2'
# Query artefact B2
The thin arm answered from a pack of pointers, 2026-09-05 04:35, no page read whole.
ARTEFACT_B2

cat > /tmp/b6-parity-suite/vault/wiki/index.md <<'VAULT_INDEX'
---
title: "Index"
type: index
confidence: high
---
The catalogue links [[page-one]] and [[page-two]].
VAULT_INDEX

cat > /tmp/b6-parity-suite/vault/wiki/page-one.md <<'VAULT_P1'
---
title: "Page one"
type: source
confidence: medium
---
Page one links to [[page-two]] and states that the run cost 55.02 dollars by phase.
The three waste classes were idle minutes, over-cap reports and denials.
VAULT_P1

cat > /tmp/b6-parity-suite/vault/wiki/page-two.md <<'VAULT_P2'
---
title: "Page two"
type: source
confidence: medium
---
Page two links back to [[page-one]] and records the phase costs in a table.
VAULT_P2

cat > /tmp/b6-parity-suite/vault/.claude/skills/demo/SKILL.md <<'VAULT_SKILL'
---
name: demo
description: a shipped surface so the shipped-links check has something to scan
---
This surface cites the page named page-one in code font, never as a link.
VAULT_SKILL

cat > /tmp/b6-parity-suite/vault/.claude/agents/demo-agent.md <<'VAULT_AGENT'
---
name: demo-agent
description: a shipped definition so the agents arm of the shipped-links check is not empty
---
Nothing here links anywhere.
VAULT_AGENT

cat > /tmp/b6-parity-suite/record.jsonl <<'RECORD'
{"ts": "2026-09-05T04:00+0100", "event": "run-open", "run": "run-x", "session": "arm-one"}
{"ts": "2026-09-05T04:05+0100", "event": "gate", "run": "run-x", "lane": "arm-one", "context": 100000}
{"ts": "2026-09-05T04:20+0100", "event": "gate", "run": "run-x", "lane": "arm-one", "context": 300000}
{"ts": "2026-09-05T04:35+0100", "event": "gate", "run": "run-x", "lane": "arm-one", "context": 500000}
{"ts": "2026-09-05T04:06+0100", "event": "gate", "run": "run-x", "lane": "arm-two", "context": 80000}
{"ts": "2026-09-05T04:21+0100", "event": "gate", "run": "run-x", "lane": "arm-two", "context": 140000}
{"ts": "2026-09-05T04:36+0100", "event": "gate", "run": "run-x", "lane": "arm-two", "context": 200000}
RECORD

# The meter fixtures copy the metering script's own line shape, whose separator is built here
# rather than written literally (a bare separator in this file reads as a path to the lane fence).
python3 -B -c "
s = ' ' + chr(47) + ' '
share = 'fable share: head %s out' + s + '%s flow' + s + '%s peak'
billed = 'billed (list, prices 2026-09-01): head \$%s . lanes %s . session \$%s . rewrites 0'
nl = chr(10)
open('/tmp/b6-parity-suite/meter-a.txt', 'w').write(
    share % ('120,000', '3,110,000', '412,000') + nl + billed % ('2.40', 'not scanned', '2.40') + nl)
open('/tmp/b6-parity-suite/meter-b.txt', 'w').write(
    share % ('90,000', '1,900,000', '210,000') + nl + billed % ('1.10', '\$0.40', '1.50') + nl)
open('/tmp/b6-parity-suite/meter-unmetered.txt', 'w').write(
    'fable share: unmetered (no transcript for this session)' + nl)
"

manifest /tmp/b6-parity-suite/vault "$LINT" "$HERE" > /tmp/b6-parity-suite/manifest-before.txt

# ---------------------------------------------------------------- 1 fixture, clean run
run 0 "fixture builds the blind fixture" fixture --run run-x --arm-a /tmp/b6-parity-suite/arm-one \
  --arm-b /tmp/b6-parity-suite/arm-two --out /tmp/b6-parity-suite/fx --seed 7
has "fixture reports four artefacts, two per arm" "fixture: 4 artefacts (2 per arm)"
has "fixture reports its redaction counts" "^redactions: "
has "fixture reports a leak sweep with a nonzero source control" "control: leak sweep 0 hits"
n=$(ls /tmp/b6-parity-suite/fx/fixture | grep -c '^art-')
if [ "$n" -eq 4 ]; then ok "four neutral artefacts written"; else no "four neutral artefacts written (saw $n)"; fi
if [ -f /tmp/b6-parity-suite/fx/mapping.json ]; then ok "the mapping sits outside the fixture directory"; else no "no mapping written"; fi
m=$(ls /tmp/b6-parity-suite/fx/fixture | grep -c 'mapping')
if [ "$m" -eq 0 ]; then ok "no mapping inside the granted fixture directory"; else no "a mapping leaked into the fixture directory"; fi

# ---------------------------------------------------------------- 2 blindness, planted markers
SWEEP='run-2026|b62193b5|7a1b2c3d|fable-5-1|vendor-opus|thin|pack|[0-9]{4}-[0-9]{2}-[0-9]{2}'
leaks=$(grep -R -l -E "$SWEEP" /tmp/b6-parity-suite/fx/fixture | wc -l | tr -d ' ')
src=$(grep -R -l -E "$SWEEP" /tmp/b6-parity-suite/arm-one /tmp/b6-parity-suite/arm-two | wc -l | tr -d ' ')
if [ "$leaks" -eq 0 ]; then ok "planted markers are gone from the fixture (negative control)"; else no "planted markers survive in $leaks fixture file(s)"; fi
if [ "$src" -gt 0 ]; then ok "the same sweep hits $src source file(s) (positive control)"; else no "the sweep hit nothing in the sources — the control did not fire"; fi
a1=$(grep -R -l 'A1' /tmp/b6-parity-suite/fx/fixture | wc -l | tr -d ' ')
if [ "$a1" -eq 0 ]; then ok "arm artefact ids are mapped away"; else no "an arm artefact id survives in the fixture"; fi

# ---------------------------------------------------------------- 3 fixture premise failures
run 2 "fixture refuses a missing arm directory" fixture --arm-a /tmp/b6-parity-suite/nope \
  --arm-b /tmp/b6-parity-suite/arm-two --out /tmp/b6-parity-suite/fx2
has "the missing arm is named" "PROBE FAILED: arm a directory not found"

make_dir /tmp/b6-parity-suite/arm-short
cat > /tmp/b6-parity-suite/arm-short/only.md <<'SHORT'
One artefact only, written 2026-09-05 by a lane.
SHORT
run 2 "fixture refuses unequal artefact counts" fixture --arm-a /tmp/b6-parity-suite/arm-one \
  --arm-b /tmp/b6-parity-suite/arm-short --out /tmp/b6-parity-suite/fx3
has "the unequal counts are named" "different artefact counts"

make_dir /tmp/b6-parity-suite/bland-a
make_dir /tmp/b6-parity-suite/bland-b
cat > /tmp/b6-parity-suite/bland-a/x.md <<'BLAND_A'
nothing worth redacting in me
BLAND_A
cat > /tmp/b6-parity-suite/bland-b/x.md <<'BLAND_B'
nor in me either
BLAND_B
run 2 "fixture refuses when its leak-sweep control cannot fire" fixture \
  --arm-a /tmp/b6-parity-suite/bland-a --arm-b /tmp/b6-parity-suite/bland-b \
  --out /tmp/b6-parity-suite/fx4
has "the silent control is named" "leak-sweep control did not fire"

run 2 "fixture refuses an empty arm directory" fixture --arm-a /tmp/b6-parity-suite/emptylint \
  --arm-b /tmp/b6-parity-suite/arm-two --out /tmp/b6-parity-suite/fx5
has "the empty arm is named" "holds no artefact matching"

# ---------------------------------------------------------------- 4 truth, clean run
run 0 "truth runs the five lint checks" truth --vault /tmp/b6-parity-suite/vault \
  --lint-dir "$LINT" --out /tmp/b6-parity-suite/tr
has "truth names its five checks" "truth: 5 checks"
has "truth prints a headline control per check" "^control: check-links"
for label in check-links check-orphans check-shipped-links check-qmd-registry tier-cap-check; do
  infile "the truth file carries $label" "## $label" /tmp/b6-parity-suite/tr/truth.md
done
infile "the truth file carries a headline count verbatim" 'DEAD LINKS:' /tmp/b6-parity-suite/tr/truth.md

# ---------------------------------------------------------------- 5 truth premise failures
run 2 "truth refuses a lint directory with no scripts" truth --vault /tmp/b6-parity-suite/vault \
  --lint-dir /tmp/b6-parity-suite/emptylint --out /tmp/b6-parity-suite/tr2
has "the missing script is named" "PROBE FAILED: lint script not found"
if [ -f /tmp/b6-parity-suite/tr2/truth.md ]; then no "an aborted truth run left a truth file"; else ok "an aborted truth run leaves no truth file"; fi

run 2 "truth refuses a vault with no wiki directory" truth --vault /tmp/b6-parity-suite/arm-one \
  --lint-dir "$LINT" --out /tmp/b6-parity-suite/tr3
has "the wrong root is named" "no wiki directory under"

# ---------------------------------------------------------------- 6 query truth
run 0 "truth builds the query truth" truth --vault /tmp/b6-parity-suite/vault --lint-dir "$LINT" \
  --out /tmp/b6-parity-suite/tr --query-pages wiki/page-one.md wiki/page-two.md \
  --query-grep 'phase' --query-grep 'waste classes'
has "the query truth counts its matched lines" "query-truth: 2 page(s)"
infile "the query truth carries the frontmatter title" 'title: Page one' /tmp/b6-parity-suite/tr/query-truth.md
infile "the query truth carries path and line locators" 'page-one.md:' /tmp/b6-parity-suite/tr/query-truth.md

run 2 "truth refuses a query pattern that matches nothing" truth --vault /tmp/b6-parity-suite/vault \
  --lint-dir "$LINT" --out /tmp/b6-parity-suite/tr4 --query-pages wiki/page-one.md \
  --query-grep 'zzz-no-such-phrase'
has "the empty pattern is named" "matched no line in any named page"

run 2 "truth refuses a query page that is not there" truth --vault /tmp/b6-parity-suite/vault \
  --lint-dir "$LINT" --out /tmp/b6-parity-suite/tr5 --query-pages wiki/absent.md --query-grep 'phase'
has "the absent page is named" "query page not found"

# ---------------------------------------------------------------- 7 judge brief
run 0 "judge-brief composes the lint brief" judge-brief --fixture /tmp/b6-parity-suite/fx/fixture \
  --truth /tmp/b6-parity-suite/tr --out /tmp/b6-parity-suite/brief-lint.md --rubric lint \
  --lane J1 --run run-x
has "judge-brief reports its controls" "blindness sweep 0 hits"
has "judge-brief reports every slot filled" "slots: 8 filled, no placeholder left"
for slot in TASK SCOPE REGISTRIES GRANTS DECISIONS VERIFICATION CONDUCT REPORT; do
  infile "the brief carries the $slot slot" "^$slot$" "$B"
done
infile "the brief states the score line format" 'SCORE ART-ID accuracy=N completeness=N citations=N' "$B"
infile "the brief carries a positive-control line" 'CONTROL+: ' "$B"
# D37 and D39: a bare rubric line the judge echoes, a bare control-plus line with nothing after the
# file path, and a separate negative-control line. The one-line `Controls: positive … negative …`
# form was refused twice on 2026-09-05 because the wrapper's parser read the prose after the path
# as part of the path.
infile "the brief carries the bare rubric line the score step groups on" '^RUBRIC: lint$' "$B"
infile "the control-plus line starts its own line" '^CONTROL+: ' "$B"
infile "the negative control is a separate line" '^Negative control: ' "$B"
infile "the brief tells the judge to echo the rubric line first" 'FIRST line of your report is the bare line' "$B"
has "judge-brief reports the two mechanical lines" "^lines: 1 bare"
ctl=$(python3 -B -c "
import re, sys
found = re.findall(r'(?m)^CONTROL[+]: (.+)\$', open(sys.argv[1]).read())
if len(found) != 1:
    print('control lines: %d' % len(found)); raise SystemExit
body = found[0]
cut = body.rfind(' in ')                      # the wrapper splits on the LAST ' in '
path = body[cut + 4:] if cut != -1 else ''
print('ok' if path and path == path.strip() and path.endswith('truth.md') else 'tail=%r' % path)
" "$B")
if [ "$ctl" = ok ]; then ok "the control line ends at the truth file with nothing after it"; else no "the control line is malformed ($ctl)"; fi
badctl=$(python3 -B -c "
import re
line = 'CONTROL+: a phrase in /tmp/x/truth.md  (report the line you found it on)'
body = re.match(r'^CONTROL[+]: (.+)\$', line).group(1)
path = body[body.rfind(' in ') + 4:]
print('caught' if not path.endswith('truth.md') else 'missed')
")
if [ "$badctl" = caught ]; then ok "the same check catches a planted trailing clause (positive control)"; else no "the control-line check passed a planted trailing clause"; fi
# The pin itself: the wrapper's own parser, run for real on the generated brief. A dry run spawns
# nothing and writes nothing (it prints what it would write). `--reason` is required at every spawn,
# dry runs included, and is checked before any record line, so an omitted one refuses with exit 2
# and this leg's parser is never reached (2026-09-07). The letter is (a) independence because the
# parity judge is a blind lane: it is the instrument rule this spawn is opened under, not a token
# added to satisfy the wrapper, and the leg's intent — the wrapper's own control parser run on the
# generated brief — is unchanged.
if [ -f "$LANE" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$LANE" spawn --dry-run --run run-x --lane J1 \
    --class critic --brief "$B" --grant /tmp/b6-parity-suite/fx/fixture \
    --grant /tmp/b6-parity-suite/tr --grants-only --delegation single --delegation-src head \
    --reason "(a) independence: the parity judge scores the fixture blind to its arm" \
    > /tmp/b6-parity-suite/dry.txt 2>&1
  dry=$?
  if [ "$dry" -eq 0 ]; then ok "the spawn wrapper accepts the brief on a dry run (exit 0)"; else no "the spawn wrapper refused the brief (exit $dry)"; fi
  infile "the wrapper's control parser lands on the truth file" 'truth.md", "matches"' /tmp/b6-parity-suite/dry.txt
  infile "the wrapper counted a nonzero match (positive control)" '"matches": [1-9]' /tmp/b6-parity-suite/dry.txt
  notinfile "the parsed control file carries no trailing prose" 'truth.md (report' /tmp/b6-parity-suite/dry.txt
else
  skip "the spawn wrapper's own control parser on this brief" "no lane.py at $LANE (name it with PARITY_LANE_PY); the regex legs above stand in"
fi
phrase=$(python3 -B -c "
import re, sys
m = re.search(r'CONTROL[+]: (.+?) in ', open(sys.argv[1]).read())
print(m.group(1) if m else '')
" "$B")
if [ -n "$phrase" ] && grep -qF "$phrase" /tmp/b6-parity-suite/tr/truth.md; then ok "the control phrase really occurs in the truth file"; else no "the control phrase is not in the truth file"; fi
if grep -q -E 'A[0-9]|B[0-9]|arm-a|arm-b|thin arm' "$B"; then no "the brief names an arm"; else ok "the brief names no arm (blind)"; fi

run 0 "judge-brief composes the query brief" judge-brief --fixture /tmp/b6-parity-suite/fx/fixture \
  --truth /tmp/b6-parity-suite/tr --out /tmp/b6-parity-suite/brief-query.md --rubric query
has "the query brief leaves the spawner its placeholders" "placeholders left for the spawner"
infile "the query brief carries its own bare rubric line" '^RUBRIC: query$' /tmp/b6-parity-suite/brief-query.md
notinfile "the query brief does not carry the other rubric's key" '^RUBRIC: lint$' /tmp/b6-parity-suite/brief-query.md

run 2 "judge-brief refuses a marker that would unblind the judge" judge-brief \
  --fixture /tmp/b6-parity-suite/fx/fixture --truth /tmp/b6-parity-suite/tr \
  --out /tmp/b6-parity-suite/brief-bad.md --rubric lint --arm-marker fixture
has "the leaking marker is named" "the judge would not be blind"

run 2 "judge-brief refuses a missing truth file" judge-brief --fixture /tmp/b6-parity-suite/fx/fixture \
  --truth /tmp/b6-parity-suite/emptylint --out /tmp/b6-parity-suite/brief-bad2.md --rubric lint
has "the missing truth file is named" "truth file for rubric lint not found"

run 2 "judge-brief refuses an empty fixture" judge-brief --fixture /tmp/b6-parity-suite/emptylint \
  --truth /tmp/b6-parity-suite/tr --out /tmp/b6-parity-suite/brief-bad3.md --rubric lint
has "the empty fixture is named" "holds no artefact named"

# ---------------------------------------------------------------- 7b id blindness: token, not path
# Planted input: the same fixture reached under two directory names carrying an arm-id-shaped pair,
# store-b6 (lowercase) and store-B6 (uppercase, inside a path component). Both briefs must compose.
# A sweep that folds case, or that reads a path as an id, refuses them, and the gate then stalls on
# a store path whose letters nobody chose for their meaning. Two controls keep the narrowing honest:
# a bare id in the identity line is still a refusal, and the fixture is untouched either way.
make_dir /tmp/b6-parity-suite/store-b6/fixture
make_dir /tmp/b6-parity-suite/store-B6/fixture
cp /tmp/b6-parity-suite/fx/fixture/art-1.md /tmp/b6-parity-suite/store-b6/fixture/art-1.md
cp /tmp/b6-parity-suite/fx/fixture/art-1.md /tmp/b6-parity-suite/store-B6/fixture/art-1.md
manifest /tmp/b6-parity-suite/store-B6 > /tmp/b6-parity-suite/blind-before.txt

run 0 "judge-brief accepts a fixture path whose directory carries a lowercase b6" judge-brief \
  --fixture /tmp/b6-parity-suite/store-b6/fixture --truth /tmp/b6-parity-suite/tr \
  --out /tmp/b6-parity-suite/brief-b6.md --rubric lint --lane J1 --run run-x
run 0 "judge-brief accepts a fixture path whose directory carries an uppercase B6" judge-brief \
  --fixture /tmp/b6-parity-suite/store-B6/fixture --truth /tmp/b6-parity-suite/tr \
  --out /tmp/b6-parity-suite/brief-B6.md --rubric lint --lane J1 --run run-x
has "the sweep still ran on the B6 brief" "blindness sweep 0 hits"
b6lines=$(grep -c 'B6' /tmp/b6-parity-suite/brief-B6.md)
loose=$(grep 'B6' /tmp/b6-parity-suite/brief-B6.md | grep -c -v '/')
if [ "$b6lines" -gt 0 ] && [ "$loose" -eq 0 ]; then ok "each of the $b6lines B6 line(s) in that brief is a path line, none a bare id (the nonzero count is the control)"; else no "the B6 brief carries $b6lines B6 line(s), $loose of them without a path"; fi
if grep -q -E 'arm-a|arm-b|thin arm' /tmp/b6-parity-suite/brief-B6.md; then no "the B6 brief names an arm"; else ok "the B6 brief still names no arm"; fi
manifest /tmp/b6-parity-suite/store-B6 > /tmp/b6-parity-suite/blind-after.txt
if cmp -s /tmp/b6-parity-suite/blind-before.txt /tmp/b6-parity-suite/blind-after.txt; then ok "the artefact under the B6 directory is byte-identical after the sweep (negative control)"; else no "the blindness sweep changed a file under the B6 directory"; fi
run 2 "judge-brief still refuses a bare arm id outside a path" judge-brief \
  --fixture /tmp/b6-parity-suite/store-B6/fixture --truth /tmp/b6-parity-suite/tr \
  --out /tmp/b6-parity-suite/brief-bad4.md --rubric lint --lane A1 --run run-x
has "the bare id is named as the leak (positive control for the narrowed marker)" "the judge would not be blind"

# ---------------------------------------------------------------- 8 score
python3 -B -c "
import json
mapping = json.load(open('/tmp/b6-parity-suite/fx/mapping.json'))
rows = sorted(mapping['neutral_to_arm'].items())
a = [k for k, v in rows if v['arm'] == 'a']
b = [k for k, v in rows if v['arm'] == 'b']
one, two = ['RUBRIC: lint'], ['RUBRIC: lint']
for art in a:
    one.append('SCORE %s accuracy=7 completeness=7 citations=7 note=fine' % art)
    two.append('SCORE %s accuracy=7 completeness=7 citations=7 note=fine' % art)
for i, art in enumerate(b):
    one.append('SCORE %s accuracy=%d completeness=8 citations=8 note=fine' % (art, 6 if i == 0 else 8))
    two.append('SCORE %s accuracy=8 completeness=8 citations=8 note=fine' % art)
nl = chr(10)
open('/tmp/b6-parity-suite/judge-one.md', 'w').write(nl.join(one) + nl)
open('/tmp/b6-parity-suite/judge-two.md', 'w').write(nl.join(two) + nl)
open('/tmp/b6-parity-suite/judge-bad.md', 'w').write('no score lines at all' + nl)
open('/tmp/b6-parity-suite/judge-unknown.md', 'w').write('RUBRIC: lint' + nl + 'SCORE art-99 accuracy=5 completeness=5 citations=5 note=x' + nl)
open('/tmp/b6-parity-suite/judge-range.md', 'w').write('RUBRIC: lint' + nl + 'SCORE %s accuracy=44 completeness=5 citations=5 note=x' % a[0] + nl)
"

run 0 "score compares the arms without a record" score --report /tmp/b6-parity-suite/judge-one.md \
  --report /tmp/b6-parity-suite/judge-two.md --mapping /tmp/b6-parity-suite/fx/mapping.json \
  --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt \
  --spend-a 2.40 --spend-b 1.50 --judge-spend 0.90 --judge-spend 0.95
has "score prints the table header" "^parity table: 2 judge(s)"
has "score prints an arm row with its peak and flow" "^arm-a · mean "
has "score marks the thin arm" "arm-b (thin)"
has "score prints the per-judge spend" "^judge spend: "
has "score flags the split dimension with its rubric" "^split: .* accuracy (lint) 6/8"
has "score recommends a third judge, naming the artefact and dimension" "^third-judge: recommended for .* accuracy (lint: 6 vs 8)"
has "score holds the lever while the context is unmeasured" "hold-lever — context per item unmeasured"

run 0 "score uses the gate events when a record is given" score \
  --report /tmp/b6-parity-suite/judge-one.md --report /tmp/b6-parity-suite/judge-two.md \
  --mapping /tmp/b6-parity-suite/fx/mapping.json --meter-a /tmp/b6-parity-suite/meter-a.txt \
  --meter-b /tmp/b6-parity-suite/meter-b.txt --record /tmp/b6-parity-suite/record.jsonl \
  --arm-a-key arm-one --arm-b-key arm-two
has "the deprecated shared record still gives the context per item" "context per item 200,000 (3 gate events, shared record)"
has "score passes when the thin arm is not lower and its context per item is" "^parity: pass"

run 2 "score refuses a report with no score lines" score --report /tmp/b6-parity-suite/judge-bad.md \
  --mapping /tmp/b6-parity-suite/fx/mapping.json --meter-a /tmp/b6-parity-suite/meter-a.txt \
  --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the empty report is named" "carries no SCORE line"

run 2 "score refuses an id the mapping does not carry" score \
  --report /tmp/b6-parity-suite/judge-unknown.md --mapping /tmp/b6-parity-suite/fx/mapping.json \
  --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the unknown id is named" "an id the mapping does not carry"

run 2 "score refuses a score outside the range" score --report /tmp/b6-parity-suite/judge-range.md \
  --mapping /tmp/b6-parity-suite/fx/mapping.json --meter-a /tmp/b6-parity-suite/meter-a.txt \
  --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the out-of-range score is named" "outside 0 to 10"

run 2 "score refuses an unmetered arm" score --report /tmp/b6-parity-suite/judge-one.md \
  --mapping /tmp/b6-parity-suite/fx/mapping.json --meter-a /tmp/b6-parity-suite/meter-unmetered.txt \
  --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the unmetered meter is named" "is unmetered"

run 2 "score refuses a record with too few gate events" score \
  --report /tmp/b6-parity-suite/judge-one.md --mapping /tmp/b6-parity-suite/fx/mapping.json \
  --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt \
  --record /tmp/b6-parity-suite/record.jsonl --arm-a-key no-such-arm --arm-b-key arm-two
has "the missing gate events are named" "a per-item context needs at"

# ---------------------------------------------------------------- 8b unknown id before coverage
# Planted input: a report scoring three of the four mapped artefacts plus art-99, an id the mapping
# does not carry. Both guards fire on it, and the unknown id must be the one named: a coverage
# message would send the caller hunting the judge that dropped an artefact, while the report which
# invented an id went unmentioned. The last leg is the coverage guard's own positive control.
python3 -B -c "
import json
mapping = json.load(open('/tmp/b6-parity-suite/fx/mapping.json'))
arts = sorted(mapping['neutral_to_arm'])
lines = ['RUBRIC: lint'] + ['SCORE %s accuracy=7 completeness=7 citations=7 note=fine' % a for a in arts[:-1]]
nl = chr(10)
open('/tmp/b6-parity-suite/judge-gap-only.md', 'w').write(nl.join(lines) + nl)
lines.append('SCORE art-99 accuracy=5 completeness=5 citations=5 note=planted unknown id')
open('/tmp/b6-parity-suite/judge-unknown-gap.md', 'w').write(nl.join(lines) + nl)
"
run 2 "score names the unknown id when an artefact is also unscored" score \
  --report /tmp/b6-parity-suite/judge-unknown-gap.md --mapping /tmp/b6-parity-suite/fx/mapping.json \
  --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the planted unknown id is the failure named" "does not carry: art-99"
hasnt "no coverage message masks the unknown id" "no judge scored"
run 2 "score still catches an artefact no judge scored" score \
  --report /tmp/b6-parity-suite/judge-gap-only.md --mapping /tmp/b6-parity-suite/fx/mapping.json \
  --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt
has "the unscored artefact is named (positive control for the coverage guard)" "no judge scored"

# ---------------------------------------------------------------- 8c rubric grouping (D37)
# Planted input: two lint judges and two query judges, each scoring the artefacts of its own rubric.
# The truth of the fixture, computed by hand from the numbers written below: per rubric, arm a lint
# 7.00 (all sevens) and query 8.00 (all eights); arm b lint 8.50 (accuracy 9, completeness 8,
# citations (9+8)/2) and query 8.00. Over the two rubrics: arm a 7.50, arm b 8.25 — the figures run
# 1 computed by hand while the script printed 4.17 and 5.08 from the mixed pool. Every per-rubric
# mean differs from its arm's mixed mean, so a grouping that silently pooled the judges again would
# print a different number in at least one row.
python3 -B -c "
import json
mapping = json.load(open('/tmp/b6-parity-suite/fx/mapping.json'))
rows = mapping['neutral_to_arm']
def pick(arm, stem):
    return [k for k, v in rows.items()
            if v['arm'] == arm and v['source'].endswith(stem + '.md')][0]
al, aq = pick('a', 'lint'), pick('a', 'query')
bl, bq = pick('b', 'lint'), pick('b', 'query')
nl = chr(10)
def line(art, acc, comp, cit):
    return 'SCORE %s accuracy=%d completeness=%d citations=%d note=fine' % (art, acc, comp, cit)
def write(name, lines):
    open('/tmp/b6-parity-suite/' + name, 'w').write(nl.join(lines) + nl)
write('jl-1.md', ['RUBRIC: lint', line(al, 7, 7, 7), line(bl, 9, 8, 9)])
write('jl-2.md', ['RUBRIC: lint', line(al, 7, 7, 7), line(bl, 9, 8, 8)])
write('jq-1.md', ['RUBRIC: query', line(aq, 8, 8, 8), line(bq, 8, 8, 8)])
write('jq-2.md', ['RUBRIC: query', line(aq, 8, 8, 8), line(bq, 8, 8, 8)])
# The reports that must never reach a mean: no rubric line, and a rubric no brief carries. Both
# score every artefact 1, so pooling either would move every printed figure.
ones = [line(a, 1, 1, 1) for a in (al, aq, bl, bq)]
write('jn-none.md', ['## Scores'] + ones)
write('jn-banana.md', ['RUBRIC: banana'] + ones)
write('jn-two.md', ['RUBRIC: lint', 'RUBRIC: query', line(al, 7, 7, 7), line(bl, 9, 8, 9)])
write('jn-repeat.md', ['RUBRIC: lint', line(al, 7, 7, 7), 'RUBRIC: lint', line(bl, 9, 8, 9)])
open('/tmp/b6-parity-suite/jn-empty.md', 'w').write('')
# The split fixture: two lint judges 2 points apart on one artefact's accuracy (must fire), and a
# lint pair and a query pair 3 points apart on another artefact's accuracy (must not fire: two
# rubrics are two tests, and a third judge would settle nothing).
write('js-lint-1.md', ['RUBRIC: lint', line(al, 7, 7, 7), line(bl, 8, 8, 8)])
write('js-lint-2.md', ['RUBRIC: lint', line(al, 9, 7, 7), line(bl, 8, 8, 8)])
write('js-query-1.md', ['RUBRIC: query', line(bl, 5, 8, 8), line(aq, 8, 8, 8), line(bq, 8, 8, 8)])
write('js-query-2.md', ['RUBRIC: query', line(bl, 5, 8, 8), line(aq, 8, 8, 8), line(bq, 8, 8, 8)])
open('/tmp/b6-parity-suite/ids.sh', 'w').write(
    nl.join(['A_LINT=' + al, 'A_QUERY=' + aq, 'B_LINT=' + bl, 'B_QUERY=' + bq]) + nl)
# One record per arm (D37): the same gate series as the shared record, split into its two files,
# plus a record whose events carry no gate at all.
src = [json.loads(l) for l in open('/tmp/b6-parity-suite/record.jsonl') if l.strip()]
for arm, lane in (('a', 'arm-one'), ('b', 'arm-two')):
    kept = [e for e in src if e.get('lane') == lane]
    open('/tmp/b6-parity-suite/record-' + arm + '.jsonl', 'w').write(
        nl.join(json.dumps(e) for e in kept) + nl)
open('/tmp/b6-parity-suite/record-nogates.jsonl', 'w').write(
    nl.join(json.dumps(e) for e in src if e.get('event') != 'gate') + nl)
print('grouping fixtures written')
"
. /tmp/b6-parity-suite/ids.sh

GROUP="--report /tmp/b6-parity-suite/jl-1.md --report /tmp/b6-parity-suite/jl-2.md --report /tmp/b6-parity-suite/jq-1.md --report /tmp/b6-parity-suite/jq-2.md"
MAPMET="--mapping /tmp/b6-parity-suite/fx/mapping.json --meter-a /tmp/b6-parity-suite/meter-a.txt --meter-b /tmp/b6-parity-suite/meter-b.txt"
RECORDS="--record-a /tmp/b6-parity-suite/record-a.jsonl --record-b /tmp/b6-parity-suite/record-b.jsonl"

# shellcheck disable=SC2086
run 0 "score groups four judges by their echoed rubric" score $GROUP $MAPMET $RECORDS
has "the header counts the judges per rubric" "^parity table: 4 judge(s) over 2 rubric(s) (lint 2 · query 2)"
has "arm a's lint mean is the planted 7.00" "^arm-a rubric lint · mean 7.00"
has "arm a's query mean is the planted 8.00" "^arm-a rubric query · mean 8.00"
has "arm b's lint mean is the planted 8.50" "^arm-b rubric lint · mean 8.50"
has "arm b's query mean is the planted 8.00" "^arm-b rubric query · mean 8.00"
has "arm a's mean over the rubrics is the planted 7.50" "^arm-a · mean 7.50 "
has "arm b's mean over the rubrics is the planted 8.25" "^arm-b (thin) · mean 8.25 "
hasnt "no mixed pool: arm a never scores its lint rubric's 7.00 overall" "^arm-a · mean 7.00 "
hasnt "no mixed pool: arm b never scores its lint rubric's 8.50 overall" "^arm-b (thin) · mean 8.50 "
has "each arm's context per item comes from its own record" "context per item 200,000 (3 gate events, own record)"
has "the other arm's context comes from the other record" "context per item 60,000 (3 gate events, own record)"
has "the verdict applies the rule per rubric and overall" "^parity: pass — arm-b is not lower on any rubric (lint 8.50 against 7.00 · query 8.00 against 8.00) nor overall (8.25 against 7.50)"
hasnt "no third judge is recommended on an unsplit fixture" "third-judge"

# shellcheck disable=SC2086
run 0 "score lists a report with no rubric line as unscored" score $GROUP \
  --report /tmp/b6-parity-suite/jn-none.md $MAPMET $RECORDS
has "the unscored report is named with its reason" "^unscored (no RUBRIC line): /tmp/b6-parity-suite/jn-none.md"
has "the unscored report's four score lines are counted" "its 4 score line(s) enter no mean"
has "the arm means are unmoved by it (it scored everything 1)" "^arm-a · mean 7.50 "
has "the other arm's mean is unmoved too" "^arm-b (thin) · mean 8.25 "
has "the judge count still names four scored judges" "^parity table: 4 judge(s) over 2 rubric(s)"

# shellcheck disable=SC2086
run 0 "score lists a rubric no brief carries as unscored" score $GROUP \
  --report /tmp/b6-parity-suite/jn-banana.md $MAPMET $RECORDS
has "the unknown rubric is named with the briefed ones" "^unscored (unknown rubric 'banana'; the briefed rubrics are lint, query)"
has "the unknown rubric moves no mean" "^arm-b (thin) · mean 8.25 "

run 2 "score refuses a report carrying two rubric lines" score \
  --report /tmp/b6-parity-suite/jn-two.md $MAPMET
has "the ambiguous grouping is named with both rubrics" "carries 2 RUBRIC lines naming lint, query"

# shellcheck disable=SC2086
run 0 "score accepts a report that repeats one rubric line" score $GROUP \
  --report /tmp/b6-parity-suite/jn-repeat.md $MAPMET $RECORDS
has "the repeat is reported as a note" "^note: /tmp/b6-parity-suite/jn-repeat.md repeats its RUBRIC line 2 times (all lint)"
has "the repeating judge is counted as a lint judge" "^parity table: 5 judge(s) over 2 rubric(s) (lint 3 · query 2)"

run 2 "score refuses an empty report" score --report /tmp/b6-parity-suite/jn-empty.md $MAPMET
has "the empty report is named" "carries no SCORE line"

run 2 "score refuses a report set with no groupable rubric at all" score \
  --report /tmp/b6-parity-suite/jn-none.md --report /tmp/b6-parity-suite/jn-banana.md $MAPMET
has "both reasons are listed" "every judge report is unscored"

run 0 "score splits within a rubric and not across" score \
  --report /tmp/b6-parity-suite/js-lint-1.md --report /tmp/b6-parity-suite/js-lint-2.md \
  --report /tmp/b6-parity-suite/js-query-1.md --report /tmp/b6-parity-suite/js-query-2.md \
  $MAPMET $RECORDS
has "the within-rubric split names artefact, dimension and rubric" "^third-judge: recommended for $A_LINT accuracy (lint: 7 vs 9)"
hasnt "the cross-rubric gap of 3 points recommends nothing" "third-judge: recommended for $B_LINT"
hasnt "and no split line is printed for it either" "^split: $B_LINT accuracy"

run 2 "score refuses both record forms at once" score $GROUP $MAPMET $RECORDS \
  --record /tmp/b6-parity-suite/record.jsonl
has "the two record forms are named as alternatives" "are alternatives"

run 2 "score refuses a per-arm record with no gate event in it" score $GROUP $MAPMET \
  --record-a /tmp/b6-parity-suite/record-nogates.jsonl
has "the empty record is named with its path and count" "record-nogates.jsonl carries 0 gate event(s) for arm a"

run 0 "score --help documents both record forms" score --help
has "the deprecated flag says so" "deprecated (design D37)"
has "the per-arm flags are documented" "arm a's own run record"
hasnt "the pre-D37 help string is gone (negative control)" "run record whose gate events carry the context figures"

# ---------------------------------------------------------------- 9 nothing written outside
manifest /tmp/b6-parity-suite/vault "$LINT" "$HERE" > /tmp/b6-parity-suite/manifest-after.txt
if cmp -s /tmp/b6-parity-suite/manifest-before.txt /tmp/b6-parity-suite/manifest-after.txt; then
  ok "the fixture vault and both shipped skill directories are byte-identical after the run"
else
  no "a file changed outside the --out roots"
fi
mb=$(wc -l < /tmp/b6-parity-suite/manifest-before.txt | tr -d ' ')
if [ "$mb" -gt 10 ]; then ok "the manifest control covers $mb files (nonzero, so the comparison means something)"; else no "the manifest covered $mb files — it proves nothing"; fi

writers=$(grep -c 'open(target, "w"' "$PY")
if [ "$writers" -eq 1 ]; then ok "parity.py has exactly one write site"; else no "parity.py has $writers write sites, wanted 1"; fi
WRITEPAT="open\([^)]*, *[\"']w|shutil|os\.remove|os\.rename|os\.unlink|rmtree"
strays=$(grep -c -E "$WRITEPAT" "$PY")
if [ "$strays" -eq 1 ]; then ok "no write pattern outside that one site"; else no "$strays write patterns in parity.py, wanted 1"; fi
selfctl=$(grep -c -E "$WRITEPAT" "$0")
if [ "$selfctl" -gt 0 ]; then ok "the write-pattern sweep hits $selfctl line(s) in this suite (positive control)"; else no "the write-pattern sweep found nothing anywhere — it is broken"; fi

# ---------------------------------------------------------------- result
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then printf 'PASS %s/%s\n' "$pass" "$total"; else printf 'FAIL %s/%s\n' "$fail" "$total"; fi
if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
