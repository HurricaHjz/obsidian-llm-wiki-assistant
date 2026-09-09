#!/bin/sh
# test_vault_writes.sh — regression suite for vault-writes.py (delegate skill, the vault
# writes a head composes by hand).
#
# Every fixture is a throwaway vault under one `mktemp -d`: a short log, a register with an
# Open and a Closed section, and an IDEAS file. The live vault is never named here and never
# touched: every path below hangs off $W (the temporary directory) or $HERE (this file own
# directory, read only). A leg that asserts a clean or empty result carries the planted case
# that proves the same probe fires, and the last group proves the script wrote nothing but
# the file it was pointed at.
#
# Run:  sh test_vault_writes.sh      (last line: PASS n/n or FAIL k/n; exit 0 only when clean)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/vault-writes.py"
PY="${PYTHON:-python3}"
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL   — $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }

W=$(mktemp -d)
OUT="$W/out.txt"
cleanup() { chmod -R u+w "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT

[ -f "$S" ] || { echo "PROBE FAILED: no vault-writes.py at $S"; echo "FAIL 1/1"; exit 2; }
command -v "$PY" >/dev/null 2>&1 || { echo "PROBE FAILED: no $PY on PATH"; echo "FAIL 1/1"; exit 2; }

run() { "$@" >"$OUT" 2>&1; RC=$?; }
vw() { run "$PY" -B "$S" "$@"; }
has() { if grep -qF -- "$2" "$OUT"; then ok "$1"; else no "$1 (stdout lacks '$2')"; fi; }
hasnot() { if grep -qF -- "$2" "$OUT"; then no "$1 (stdout still holds '$2')"; else ok "$1"; fi; }
fhas() { if grep -qF -- "$3" "$2"; then ok "$1"; else no "$1 ($2 lacks '$3')"; fi; }
fhasnot() { if grep -qF -- "$3" "$2"; then no "$1 ($2 holds '$3')"; else ok "$1"; fi; }
nlines() { awk 'END { print NR }' "$1"; }
count() { grep -cF -- "$2" "$1" || true; }
fmatch() { if grep -Eq -- "$3" "$2"; then ok "$1"; else no "$1 ($2 holds no line matching /$3/)"; fi; }
fnomatch() { if grep -Eq -- "$3" "$2"; then no "$1 ($2 holds a line matching /$3/)"; else ok "$1"; fi; }

# The clock legs. Every stamp below is read from the same clock the script under test reads,
# so a leg that asserts an exact stamp reads the clock either side of the call and accepts
# both: the minute may tick between the two processes, and a leg that failed one time in
# sixty would be read as a defect. `eq2` is that pair.
eq2() {
	if [ "$2" = "$3" ] || [ "$2" = "$4" ]; then ok "$1"
	else no "$1 (got '$2', want '$3' or '$4')"; fi
}
now_hm() { "$PY" -B -c 'import time; print(time.strftime("%H:%M"))'; }
now_min() { "$PY" -B -c 'import time; print(time.localtime().tm_min)'; }
now_zone() { "$PY" -B -c 'import time; print(time.strftime("%Z") or time.strftime("%z"))'; }
# An hour that is neither the clock's own nor the hour before it, at any hour of the day:
# the planted token of every mismatch leg, computed at run time so the suite is stable at
# 23:5x as at 00:0x.
plant_hour() { "$PY" -B -c 'import time; print("%02d" % ((time.localtime().tm_hour + 3) % 24))'; }
prev_hour() { "$PY" -B -c 'import time; print("%02d" % ((time.localtime().tm_hour - 1) % 24))'; }
# A SECOND offending hour, distinct from plant_hour's, for the leg that needs two tokens at
# once. The primitive's tolerance is one hour wide and one-sided: `GRACE_MINUTES = 10`
# (vault-writes.py:127) with `if clock_minute < GRACE_MINUTES and token_hour == (clock_hour -
# 1) % HOURS: return False` (vault-writes.py:195), so only the offset -1 (i.e. +23) is ever
# forgiven, and only while the clock's minute is under ten. The arithmetic: an offset k is
# safe at every minute of the hour when k mod 24 is neither 0 (the clock's own hour) nor 23
# (the hour the grace forgives). plant_hour takes k=+3 and this takes k=+5: both are outside
# the tolerance at every minute, and the two differ, so the two tokens are distinct hours and
# the leg's two warning lines do not depend on the clock. (`$(prev_hour):45` was k=-1 here
# until 2026-09-08 and went silent whenever the run began at a minute under ten.)
other_hour() { "$PY" -B -c 'import time; print("%02d" % ((time.localtime().tm_hour + 5) % 24))'; }
# Streams kept apart: the warning is specified as a stderr line, and stdout stays the one
# line a head reads. $SOUT and $SERR hold them.
SOUT="$W/stdout.txt"
SERR="$W/stderr.txt"
vws() { "$PY" -B "$S" "$@" >"$SOUT" 2>"$SERR"; RC=$?; }

# The fixture: a vault root at $1/vault, an IDEAS file at $1/IDEAS.md.
fixture() {
	d="$1"
	rm -rf "$d"
	mkdir -p "$d/vault/wiki/developments"
	cat > "$d/vault/wiki/log.md" <<'LOG_END'
# Log

## [2026-09-01] lint | an older entry
- **Changed**: nothing at all
- **Conflicts**: none

LOG_END
	cat > "$d/vault/wiki/developments/known-issues.md" <<'REG_END'
# Known Issues

**Entry format** (append under `## Open`, newest first):

## Open

### [2026-09-05] alpha surface — the first one (minor)
- **Where observed**: run A · one path
- **Symptom**: it broke observably
- **Suspected cause**: inference, marked as such
- **Status**: open — fix shape: alpha

### [2026-09-04] beta surface — the middle one (medium)
- **Where observed**: run B · another path
- **Symptom**: it slipped
- **Severity**: medium (a false alarm only). **Status**: open — fix shape: beta

### [2026-09-03] gamma surface — no status bullet at all (minor)
- **Where observed**: run C
- **Symptom**: it stalled

### [2026-09-02] epsilon surface — the last open one (major)
- **Where observed**: run E
- **Symptom**: it doubled
- **Suspected cause**: confirmed: a doubled span
- **Status**: open — fix shape: epsilon

## Closed

### [2026-09-01] delta surface — closed long ago (minor)
- **Status**: closed 2026-09-01 — done

## Related

- nothing here
REG_END
	cat > "$d/IDEAS.md" <<'IDEAS_END'
# IDEAS

<!-- live items only (todo · idea · monitor); archived rows leave this table -->

- **№11** a short item
- **№119** the big one (D-0.9) *(agent 2026-09-03: numbered at maintenance)*
- **№1190** a decoy with a longer number
- **№7** the first twin
- **№7** the second twin
IDEAS_END
}

VAULT="$W/fix/vault"
LOG="$VAULT/wiki/log.md"
REG="$VAULT/wiki/developments/known-issues.md"
IDEAS="$W/fix/IDEAS.md"

fixture "$W/fix"
# Premise checks: a mangled fixture must not read as a clean run.
[ "$(count "$IDEAS" '- **№119**')" = "1" ] || { echo "PROBE FAILED: the fixture IDEAS file has no single №119 bullet (encoding?)"; echo "FAIL 1/1"; exit 2; }
[ "$(count "$REG" '## Open')" = "2" ] || { echo "PROBE FAILED: the fixture register does not carry its Open heading twice (heading + prose)"; echo "FAIL 1/1"; exit 2; }

echo "== log-append =="

cp "$LOG" "$W/log.before"
vw log-append --vault "$VAULT" --action framework --title "a title" --changed "one file" --conflicts "none" --date 2026-09-05
eq "L1 exit 0" "$RC" "0"
eq "L2 one line of output" "$(nlines "$OUT")" "1"
eq "L3 the ok line names the heading line" "$(cat "$OUT")" "ok log-append $LOG:7"
eq "L4 the heading landed on line 7" "$(awk 'NR==7' "$LOG")" "## [2026-09-05] framework | a title"
eq "L5 the Changed bullet follows it" "$(awk 'NR==8' "$LOG")" "- **Changed**: one file"
# Updated 2026-09-08: the Clock bullet the primitive stamps now sits between the two, so the
# Conflicts bullet moved from line 9 to line 10. Its own legs are the K group below.
fmatch "L6 the Clock bullet follows that" "$LOG" '^- \*\*Clock\*\*: [0-9]{2}:[0-9]{2} .+$'
eq "L6b the Conflicts bullet is last" "$(awk 'NR==10' "$LOG")" "- **Conflicts**: none"
eq "L7 exactly one blank line above the heading" "$(awk 'NR==6' "$LOG")" ""
head -c "$(wc -c < "$W/log.before" | awk '{print $1}')" "$LOG" > "$W/log.head"
if cmp -s "$W/log.before" "$W/log.head"; then ok "L8 every byte before the append is unchanged"; else no "L8 the append rewrote earlier bytes"; fi
printf 'x' >> "$W/log.head"
if cmp -s "$W/log.before" "$W/log.head"; then no "L8c the byte comparison cannot see a change"; else ok "L8c control: the same comparison catches a planted byte"; fi

fixture "$W/fix"
vw log-append --vault "$VAULT" --action synthesis --title "extras" --changed "c" --conflicts "none" --extra "Delegation: lane B3 (fable)" --extra "Meter: billed 1.00" --date 2026-09-05
eq "L9 exit 0 with two extras" "$RC" "0"
# Updated 2026-09-08: the Clock bullet leads the extras, so the caller's two moved down one
# line each and the entry is one line longer (was 9, 10, 11 and 12).
eq "L10 the first extra sits under the Clock bullet" "$(awk 'NR==10' "$LOG")" "- **Delegation**: lane B3 (fable)"
eq "L11 the second extra follows it" "$(awk 'NR==11' "$LOG")" "- **Meter**: billed 1.00"
eq "L12 Conflicts stays last" "$(awk 'NR==12' "$LOG")" "- **Conflicts**: none"
eq "L13 a blank line closes the entry" "$(awk 'END { print NR }' "$LOG")" "13"

fixture "$W/fix"
vw log-append --vault "$VAULT" --action reflect --title "t" --changed "c" --conflicts "none"
eq "L14 an unknown action is refused" "$RC" "2"
eq "L15 one error line only" "$(nlines "$OUT")" "1"
has "L16 it names the allowed set" "is none of: ingest gather synthesis"
vw log-append --vault "$VAULT" --action lint --title "$(printf 'two\nlines')" --changed "c" --conflicts "none"
eq "L17 a line break in a title is refused" "$RC" "2"
has "L18 it says why" "carries a line break"
vw log-append --vault "$VAULT" --action lint --title "t" --changed "   " --conflicts "none"
eq "L19 an empty --changed is refused" "$RC" "2"
has "L20 it names the argument" "--changed is empty"
vw log-append --vault "$VAULT" --action lint --title "t" --changed "c" --conflicts "none" --extra "no colon here"
eq "L21 an --extra without a colon is refused" "$RC" "2"
has "L22 it says what it wanted" "is not 'Key: value'"
vw log-append --vault "$VAULT" --action lint --title "t" --changed "c" --conflicts "none" --date 2026-13-40
eq "L23 an impossible date is refused" "$RC" "2"
has "L24 it names the date" "2026-13-40"
vw log-append --vault "$W/nowhere" --action lint --title "t" --changed "c" --conflicts "none"
eq "L25 a missing log file is refused" "$RC" "2"
has "L26 it names the path it wanted" "no file at $W/nowhere/wiki/log.md"

echo "== log-append: the blank-line separator =="

fixture "$W/fix"
printf '%s' "$(cat "$LOG")" > "$W/log.nonl"
cp "$W/log.nonl" "$LOG"
vw log-append --vault "$VAULT" --action lint --title "after a bare line" --changed "c" --conflicts "none" --date 2026-09-05
eq "L27 a log with no trailing newline still appends" "$RC" "0"
eq "L28 the reported line is the heading" "$(cat "$OUT")" "ok log-append $LOG:7"
eq "L29 the last old line is intact" "$(awk 'NR==5' "$LOG")" "- **Conflicts**: none"
eq "L30 exactly one blank line separates them" "$(awk 'NR==6' "$LOG")" ""
eq "L31 the heading is on the reported line" "$(awk 'NR==7' "$LOG")" "## [2026-09-05] lint | after a bare line"

fixture "$W/fix"
printf '%s\n' "$(cat "$LOG")" > "$W/log.onenl"
cp "$W/log.onenl" "$LOG"
vw log-append --vault "$VAULT" --action lint --title "after one newline" --changed "c" --conflicts "none" --date 2026-09-05
eq "L32 a log ending in a single newline appends" "$RC" "0"
eq "L33 one blank line is inserted, not two" "$(awk 'NR==6' "$LOG")" ""
eq "L34 the heading follows immediately" "$(awk 'NR==7' "$LOG")" "## [2026-09-05] lint | after one newline"

fixture "$W/fix"
cp "$LOG" "$W/log.dry"
vw log-append --vault "$VAULT" --action lint --title "dry" --changed "c" --conflicts "none" --date 2026-09-05 --dry-run
eq "L35 a dry run exits 0" "$RC" "0"
has "L36 it says dry-run and where the entry would land" "dry-run log-append $LOG:7"
has "L37 it shows the heading it would write" "| ## [2026-09-05] lint | dry"
if cmp -s "$W/log.dry" "$LOG"; then ok "L38 the dry run wrote nothing"; else no "L38 the dry run changed the log"; fi

echo "== register add =="

fixture "$W/fix"
cp "$REG" "$W/reg.before"
T0=$(now_hm)
vw register add --vault "$VAULT" --date 2026-09-05 --surface "zeta surface — a new one" --symptom "it refused" --cause "inference: a guess" --severity minor --status "open — fix shape: zeta" --where "run Z · one path"
T1=$(now_hm)
eq "R1 exit 0" "$RC" "0"
eq "R2 one line of output" "$(nlines "$OUT")" "1"
eq "R3 the ok line names the heading line" "$(cat "$OUT")" "ok register-add $REG:7"
# Updated 2026-09-08: the heading carries the clock's time beside the caller's date.
eq2 "R4 the heading carries date, time, surface and severity" "$(awk 'NR==7' "$REG")" "### [2026-09-05 $T0] zeta surface — a new one (minor)" "### [2026-09-05 $T1] zeta surface — a new one (minor)"
eq "R5 Where observed" "$(awk 'NR==8' "$REG")" "- **Where observed**: run Z · one path"
eq "R6 Symptom" "$(awk 'NR==9' "$REG")" "- **Symptom**: it refused"
eq "R7 Suspected cause" "$(awk 'NR==10' "$REG")" "- **Suspected cause**: inference: a guess"
eq "R8 Status verbatim" "$(awk 'NR==11' "$REG")" "- **Status**: open — fix shape: zeta"
eq "R9 one blank line under the new entry" "$(awk 'NR==12' "$REG")" ""
eq "R10 the old first entry follows it" "$(awk 'NR==13' "$REG")" "### [2026-09-05] alpha surface — the first one (minor)"
eq "R11 the Open heading still has its blank line" "$(awk 'NR==6' "$REG")" ""
awk 'NR<7 || NR>12' "$REG" > "$W/reg.rest"
if cmp -s "$W/reg.before" "$W/reg.rest"; then ok "R12 every other byte of the register is unchanged"; else no "R12 the insert disturbed the rest of the file"; fi
awk 'NR!=13' "$W/reg.before" > "$W/reg.mangled"
if cmp -s "$W/reg.mangled" "$W/reg.rest"; then no "R12c the comparison cannot see a dropped line"; else ok "R12c control: the same comparison catches a dropped line"; fi
eq "R13 no temp file is left beside the target" "$(ls -a "$VAULT/wiki/developments" | grep -c 'vault-writes' || true)" "0"

fixture "$W/fix"
T0=$(now_hm)
vw register add --vault "$VAULT" --date 2026-09-05 --surface "eta surface — no where" --symptom "s" --cause "c" --severity blocking --status "open — fix shape: eta"
T1=$(now_hm)
eq "R14 blocking is accepted as a severity" "$RC" "0"
eq "R15 the Where bullet is omitted, not invented" "$(awk 'NR==8' "$REG")" "- **Symptom**: s"
# Updated 2026-09-08: the stamped heading shape.
eq2 "R16 the heading carries blocking" "$(awk 'NR==7' "$REG")" "### [2026-09-05 $T0] eta surface — no where (blocking)" "### [2026-09-05 $T1] eta surface — no where (blocking)"

fixture "$W/fix"
vw register add --vault "$VAULT" --date 2026-09-05 --surface "s" --symptom "s" --cause "c" --severity critical --status "open"
eq "R17 an unknown severity is refused" "$RC" "2"
has "R18 it names the allowed set" "is none of: blocking major medium minor"
vw register add --vault "$VAULT" --date 2026-09-05 --surface "$(printf 'two\nlines')" --symptom "s" --cause "c" --severity minor --status "open"
eq "R19 a line break in the surface is refused" "$RC" "2"
has "R20 it says why" "carries a line break"

fixture "$W/fix"
cp "$REG" "$W/reg.dry"
T0=$(now_hm)
vw register add --vault "$VAULT" --date 2026-09-05 --surface "theta" --symptom "s" --cause "c" --severity minor --status "open" --dry-run
T1=$(now_hm)
eq "R21 a dry run exits 0" "$RC" "0"
# Updated 2026-09-08: a dry run shows the stamp the write would carry, not a bare date.
if grep -qF -- "| ### [2026-09-05 $T0] theta (minor)" "$OUT" || grep -qF -- "| ### [2026-09-05 $T1] theta (minor)" "$OUT"
then ok "R22 it shows the stamped heading it would write"
else no "R22 it shows the stamped heading it would write (got '$(cat "$OUT")')"; fi
if cmp -s "$W/reg.dry" "$REG"; then ok "R23 the dry run wrote nothing"; else no "R23 the dry run changed the register"; fi

echo "== register: the section anchors =="

fixture "$W/fix"
printf '\n## Open\n' >> "$REG"
vw register add --vault "$VAULT" --date 2026-09-05 --surface "s" --symptom "s" --cause "c" --severity minor --status "open"
eq "R24 a second Open heading is refused" "$RC" "2"
has "R25 it names the count it found" "'## Open' is 2 lines of the register, not 1"

fixture "$W/fix"
awk '$0 != "## Closed"' "$REG" > "$W/reg.noclosed"
cp "$W/reg.noclosed" "$REG"
vw register add --vault "$VAULT" --date 2026-09-05 --surface "s" --symptom "s" --cause "c" --severity minor --status "open"
eq "R26 a missing Closed heading is refused" "$RC" "2"
has "R27 it names the count it found" "'## Closed' is 0 lines of the register, not 1"

fixture "$W/fix"
printf '# Inverted\n\n## Closed\n\n### [2026-09-01] delta surface — closed (minor)\n- **Status**: closed\n\n## Open\n\n### [2026-09-05] alpha surface — first (minor)\n- **Status**: open\n' > "$REG"
vw register add --vault "$VAULT" --date 2026-09-05 --surface "s" --symptom "s" --cause "c" --severity minor --status "open"
eq "R28 Closed above Open is refused" "$RC" "2"
has "R29 it names both lines" "'## Closed' (line 3) sits above '## Open' (line 8)"

echo "== register close =="

fixture "$W/fix"
BEFORE_LINES=$(nlines "$REG")
T0=$(now_hm)
vw register close --vault "$VAULT" --match "beta surface" --date 2026-09-05 --status "closed by the suite"
T1=$(now_hm)
eq "C1 exit 0" "$RC" "0"
eq "C2 one line of output" "$(nlines "$OUT")" "1"
eq "C3 the ok line names the new position" "$(cat "$OUT")" "ok register-close $REG:25"
eq "C4 the entry now heads the Closed section" "$(awk 'NR==25' "$REG")" "### [2026-09-04] beta surface — the middle one (medium)"
eq "C5 its bullets moved with it, byte for byte" "$(awk 'NR==26' "$REG")" "- **Where observed**: run B · another path"
# Updated 2026-09-08: the status fact inside the dated suffix now opens with the clock stamp
# `closed DATE HH:MM — ` (the caller's text carried no date of its own).
eq2 "C6 the combined Severity and Status line is dated and stamped in place" "$(awk 'NR==28' "$REG")" "- **Severity**: medium (a false alarm only). **Status**: open — fix shape: beta *(2026-09-05: closed 2026-09-05 $T0 — closed by the suite)*" "- **Severity**: medium (a false alarm only). **Status**: open — fix shape: beta *(2026-09-05: closed 2026-09-05 $T1 — closed by the suite)*"
eq "C7 the old Closed entry follows it" "$(awk 'NR==30' "$REG")" "### [2026-09-01] delta surface — closed long ago (minor)"
eq "C8 the heading exists exactly once in the file" "$(count "$REG" 'beta surface — the middle one')" "1"
eq "C9 the entry is gone from the Open section" "$(awk 'NR>=5 && NR<23' "$REG" | grep -cF 'beta surface' || true)" "0"
eq "C10 the file neither grew nor shrank" "$(nlines "$REG")" "$BEFORE_LINES"
eq "C11 gamma still sits under Open" "$(awk 'NR==13' "$REG")" "### [2026-09-03] gamma surface — no status bullet at all (minor)"
eq "C12 the Related section is untouched" "$(awk 'NR==35' "$REG")" "- nothing here"

fixture "$W/fix"
T0=$(now_hm)
vw register close --vault "$VAULT" --match "epsilon surface" --date 2026-09-05 --status "closed last"
T1=$(now_hm)
eq "C13 the last Open entry closes too" "$RC" "0"
eq "C14 it lands at the top of Closed" "$(cat "$OUT")" "ok register-close $REG:24"
eq "C15 the Closed heading is intact above it" "$(awk 'NR==22' "$REG")" "## Closed"
# Updated 2026-09-08: the stamped status fact inside the dated suffix.
eq2 "C16 its Status bullet carries the dated, stamped suffix" "$(awk 'NR==28' "$REG")" "- **Status**: open — fix shape: epsilon *(2026-09-05: closed 2026-09-05 $T0 — closed last)*" "- **Status**: open — fix shape: epsilon *(2026-09-05: closed 2026-09-05 $T1 — closed last)*"
eq "C17 the file neither grew nor shrank" "$(nlines "$REG")" "35"

fixture "$W/fix"
vw register close --vault "$VAULT" --match "no such entry" --date 2026-09-05 --status "x"
eq "C18 no match is refused" "$RC" "2"
has "C19 it names the count" "matches 0 entry headings under '## Open', not 1"
vw register close --vault "$VAULT" --match "surface" --date 2026-09-05 --status "x"
eq "C20 an ambiguous match is refused" "$RC" "2"
has "C21 it names the count" "matches 4 entry headings under '## Open', not 1"
vw register close --vault "$VAULT" --match "delta surface" --date 2026-09-05 --status "x"
eq "C22 an entry that is already closed is not found under Open" "$RC" "2"
has "C23 it names the count" "matches 0 entry headings"
vw register close --vault "$VAULT" --match "gamma surface" --date 2026-09-05 --status "x"
eq "C24 an entry with no Status bullet is refused" "$RC" "2"
has "C25 it names what it could not find" "carries 0 '**Status**' lines, not 1"

fixture "$W/fix"
cp "$REG" "$W/reg.dryclose"
vw register close --vault "$VAULT" --match "beta surface" --date 2026-09-05 --status "x" --dry-run
eq "C26 a dry run exits 0" "$RC" "0"
has "C27 it shows the entry it would move" "dry-run register-close $REG:25"
has "C28 it says how much moves" "| moved 4 lines to the top of '## Closed'"
if cmp -s "$W/reg.dryclose" "$REG"; then ok "C29 the dry run wrote nothing"; else no "C29 the dry run changed the register"; fi

echo "== ideas annotate =="

fixture "$W/fix"
cp "$IDEAS" "$W/ideas.before"
T0=$(now_hm)
vw ideas annotate --file "$IDEAS" --item 119 --note "hands-off primitives shipped" --date 2026-09-05
T1=$(now_hm)
eq "I1 exit 0" "$RC" "0"
eq "I2 one line of output" "$(nlines "$OUT")" "1"
eq "I3 the ok line names the bullet line" "$(cat "$OUT")" "ok ideas-annotate $IDEAS:6"
# Updated 2026-09-08: the note prefix is `*(agent DATE HH:MM: …)*`; every other rule of the
# shape (appended after the existing note, italic parentheses, one line) is unchanged, and
# the older note already on the bullet keeps its own dateless form.
eq2 "I4 the stamped note is appended after the existing one" "$(awk 'NR==6' "$IDEAS")" "- **№119** the big one (D-0.9) *(agent 2026-09-03: numbered at maintenance)* *(agent 2026-09-05 $T0: hands-off primitives shipped)*" "- **№119** the big one (D-0.9) *(agent 2026-09-03: numbered at maintenance)* *(agent 2026-09-05 $T1: hands-off primitives shipped)*"
awk 'NR!=6' "$IDEAS" > "$W/ideas.rest"
awk 'NR!=6' "$W/ideas.before" > "$W/ideas.restbefore"
if cmp -s "$W/ideas.restbefore" "$W/ideas.rest"; then ok "I5 no other line changed"; else no "I5 another line changed"; fi
eq "I6 the shorter neighbour is untouched" "$(awk 'NR==5' "$IDEAS")" "- **№11** a short item"
eq "I7 the longer neighbour is untouched" "$(awk 'NR==7' "$IDEAS")" "- **№1190** a decoy with a longer number"
# Updated 2026-09-08: the marker counted is the stamped prefix, so the leg still counts one
# note and would now miss an unstamped one.
eq "I8 exactly one stamped agent note was added" "$(count "$IDEAS" '(agent 2026-09-05 ')" "1"
eq "I8b and no unstamped one" "$(count "$IDEAS" '(agent 2026-09-05:')" "0"
eq "I8c control: the same probe counts the fixture's own dateless note" "$(count "$IDEAS" '(agent 2026-09-03:')" "1"

fixture "$W/fix"
vw ideas annotate --file "$IDEAS" --item 999 --note "n" --date 2026-09-05
eq "I9 an item that is not there is refused" "$RC" "2"
has "I10 it names the marker and the count" "begins 0 lines of"
vw ideas annotate --file "$IDEAS" --item 7 --note "n" --date 2026-09-05
eq "I11 a doubled item is refused" "$RC" "2"
has "I12 it names the count" "begins 2 lines of"
vw ideas annotate --file "$IDEAS" --item 11a --note "n"
eq "I13 an item that is not a number is refused" "$RC" "2"
has "I14 it says so" "is not a number"
vw ideas annotate --file "$W/no-such-ideas.md" --item 119 --note "n"
eq "I15 a missing file is refused" "$RC" "2"
has "I16 it names the path" "no file at $W/no-such-ideas.md"
vw ideas annotate --file "$IDEAS" --item 119 --note "$(printf 'two\nlines')"
eq "I17 a line break in the note is refused" "$RC" "2"
has "I18 it says why" "carries a line break"

fixture "$W/fix"
cp "$IDEAS" "$W/ideas.dry"
vw ideas annotate --file "$IDEAS" --item 119 --note "n" --date 2026-09-05 --dry-run
eq "I19 a dry run exits 0" "$RC" "0"
has "I20 it shows the line it would write" "dry-run ideas-annotate $IDEAS:6"
if cmp -s "$W/ideas.dry" "$IDEAS"; then ok "I21 the dry run wrote nothing"; else no "I21 the dry run changed the file"; fi

echo "== the clock: log-append =="

fixture "$W/fix"
Z=$(now_zone)
T0=$(now_hm)
vws log-append --vault "$VAULT" --action framework --title "clocked" --changed "c" --conflicts "none" --date 2026-09-05
T1=$(now_hm)
eq "K1 exit 0" "$RC" "0"
fmatch "K2 the heading keeps its schema shape, with no time inside it" "$LOG" '^## \[2026-09-05\] framework \| clocked$'
eq2 "K3 the Clock bullet carries the clock's time and its own zone" "$(awk 'NR==9' "$LOG")" "- **Clock**: $T0 $Z" "- **Clock**: $T1 $Z"
eq "K4 it sits between Changed and Conflicts" "$(awk 'NR==8 || NR==10' "$LOG" | tr '\n' '|')" "- **Changed**: c|- **Conflicts**: none|"
eq "K5 exactly one Clock bullet in the entry" "$(count "$LOG" '- **Clock**: ')" "1"
eq "K6 a text naming no time warns about nothing" "$(nlines "$SERR")" "0"

fixture "$W/fix"
PLANT="$(plant_hour):3x"
T0=$(now_hm)
vws log-append --vault "$VAULT" --action framework --title "written at $PLANT" --changed "c" --conflicts "none" --date 2026-09-05
T1=$(now_hm)
eq "K7 control: the same stderr probe catches a planted mismatch" "$(nlines "$SERR")" "1"
eq2 "K8 the warning names the token and the clock's reading" "$(cat "$SERR")" "clock: the note names $PLANT, the clock reads $T0" "clock: the note names $PLANT, the clock reads $T1"
eq "K9 a warning is not a refusal" "$RC" "0"
eq "K10 stdout still carries the one line a head reads" "$(nlines "$SOUT")" "1"
fhas "K11 and it is the ok line" "$SOUT" "ok log-append $LOG:7"
eq "K12 the write proceeded" "$(count "$LOG" "| written at $PLANT")" "1"

fixture "$W/fix"
PLANT="$(plant_hour):3x"
vws log-append --vault "$VAULT" --action framework --title "t" --changed "again at $PLANT" --conflicts "and at $PLANT" --extra "Meter: $PLANT" --date 2026-09-05
eq "K13 one token in three arguments earns one line, not three" "$(nlines "$SERR")" "1"
PLANT2="$(other_hour):45"
vws log-append --vault "$VAULT" --action framework --title "t" --changed "at $PLANT" --conflicts "c" --extra "Meter: $PLANT2" --date 2026-09-05
eq "K14 two distinct offending tokens earn two lines" "$(nlines "$SERR")" "2"
# K14's own premise: the two planted tokens really are two distinct hours, so a leg reading
# two lines is reading one line each and not one token twice. K13 above is the control for
# the other direction — one token in three arguments reads one line.
if [ "${PLANT%%:*}" != "${PLANT2%%:*}" ]; then
	ok "K14b the two planted tokens name different hours ($PLANT and $PLANT2)"
else
	no "K14b the two planted tokens name the same hour ($PLANT and $PLANT2)"
fi

fixture "$W/fix"
cp "$LOG" "$W/log.clockdry"
PLANT="$(plant_hour):3x"
T0=$(now_hm)
vws log-append --vault "$VAULT" --action framework --title "dry at $PLANT" --changed "c" --conflicts "none" --date 2026-09-05 --dry-run
T1=$(now_hm)
eq "K15 a dry run warns the same way" "$(nlines "$SERR")" "1"
if grep -qF -- "| - **Clock**: $T0 $Z" "$SOUT" || grep -qF -- "| - **Clock**: $T1 $Z" "$SOUT"
then ok "K16 and shows the stamp the write would carry"
else no "K16 and shows the stamp the write would carry (got '$(cat "$SOUT")')"; fi
if cmp -s "$W/log.clockdry" "$LOG"; then ok "K17 the warned dry run wrote nothing"; else no "K17 the warned dry run changed the log"; fi

echo "== the clock: register add =="

fixture "$W/fix"
PLANT="$(plant_hour):3x"
T0=$(now_hm)
vws register add --vault "$VAULT" --date 2026-09-05 --surface "kappa surface — a timed one" --symptom "seen at $PLANT" --cause "c" --severity minor --status "open — since $PLANT" --where "run K"
T1=$(now_hm)
eq "K18 exit 0" "$RC" "0"
fmatch "K19 the heading carries the date and a clock time" "$REG" '^### \[2026-09-05 [0-9]{2}:[0-9]{2}\] kappa surface — a timed one \(minor\)$'
eq2 "K20 the time is the clock's own" "$(awk 'NR==7' "$REG")" "### [2026-09-05 $T0] kappa surface — a timed one (minor)" "### [2026-09-05 $T1] kappa surface — a timed one (minor)"
eq "K21 the token repeated in two arguments earns one warning" "$(nlines "$SERR")" "1"
eq "K22 stdout is still one line" "$(nlines "$SOUT")" "1"

fixture "$W/fix"
NOW=$(now_hm)
vws register add --vault "$VAULT" --date 2026-09-05 --surface "lambda surface" --symptom "seen at $NOW" --cause "c" --severity minor --status "open — x" --where "and again at $NOW"
eq "K23 a token at the clock's own reading is silent" "$(nlines "$SERR")" "0"
eq "K24 the entry was still written" "$RC" "0"
PLANT="$(plant_hour):3x"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "mu surface" --symptom "seen at $PLANT" --cause "c" --severity minor --status "open — x"
eq "K25 control: the same silence probe fires on a planted hour" "$(nlines "$SERR")" "1"

fixture "$W/fix"
cp "$REG" "$W/reg.clockdry"
PLANT="$(plant_hour):3x"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "nu surface" --symptom "at $PLANT" --cause "c" --severity minor --status "open — x" --dry-run
eq "K26 a dry run warns" "$(nlines "$SERR")" "1"
fmatch "K27 and shows the stamped heading" "$SOUT" '^\| ### \[2026-09-05 [0-9]{2}:[0-9]{2}\] nu surface \(minor\)$'
if cmp -s "$W/reg.clockdry" "$REG"; then ok "K28 the warned dry run wrote nothing"; else no "K28 the warned dry run changed the register"; fi

echo "== the clock: register close =="

fixture "$W/fix"
T0=$(now_hm)
vws register close --vault "$VAULT" --match "alpha surface" --date 2026-09-05 --status "the fix shipped"
T1=$(now_hm)
eq "K29 an old-shape heading still closes by --match" "$RC" "0"
eq2 "K30 a status with no date of its own takes the whole stamp" "$(grep -F -- 'fix shape: alpha' "$REG")" "- **Status**: open — fix shape: alpha *(2026-09-05: closed 2026-09-05 $T0 — the fix shipped)*" "- **Status**: open — fix shape: alpha *(2026-09-05: closed 2026-09-05 $T1 — the fix shipped)*"
eq "K31 no second 'closed' was introduced" "$(count "$REG" 'closed closed')" "0"
eq "K31c control: the same probe sees a planted doubling" "$(printf 'closed closed 2026-09-05\n' | grep -cF 'closed closed')" "1"

fixture "$W/fix"
T0=$(now_hm)
vws register close --vault "$VAULT" --match "alpha surface" --date 2026-09-05 --status "closed 2026-09-05 — the fix shipped"
T1=$(now_hm)
eq2 "K32 a status already opening 'closed DATE' takes the time after that date" "$(grep -F -- 'fix shape: alpha' "$REG")" "- **Status**: open — fix shape: alpha *(2026-09-05: closed 2026-09-05 $T0 — the fix shipped)*" "- **Status**: open — fix shape: alpha *(2026-09-05: closed 2026-09-05 $T1 — the fix shipped)*"
eq "K33 the caller's own 'closed' is not repeated" "$(count "$REG" 'closed 2026-09-05')" "1"

fixture "$W/fix"
PLANT="$(plant_hour):3x"
vws register close --vault "$VAULT" --match "alpha surface" --date 2026-09-05 --status "closed 2026-09-05 $PLANT — the fix shipped"
eq "K34 a status already carrying a time keeps it, byte for byte" "$(count "$REG" "closed 2026-09-05 $PLANT — the fix shipped")" "1"
eq "K35 and the disagreeing hour is what the warning says" "$(nlines "$SERR")" "1"
fhas "K36 the warning names that token" "$SERR" "clock: the note names $PLANT,"

fixture "$W/fix"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "xi surface — added timed" --symptom "s" --cause "c" --severity minor --status "open — x"
eq "K37 the entry to close is written with the new heading shape" "$RC" "0"
fmatch "K37b its heading carries a time" "$REG" '^### \[2026-09-05 [0-9]{2}:[0-9]{2}\] xi surface — added timed \(minor\)$'
vws register close --vault "$VAULT" --match "xi surface" --date 2026-09-05 --status "done"
eq "K38 --match finds a heading of the new shape too" "$RC" "0"
fhas "K39 the closed entry sits under the Closed heading" "$SOUT" "ok register-close $REG:"
eq "K40 it left the Open section" "$(awk '/^## Open/, /^## Closed/' "$REG" | grep -cF 'xi surface' || true)" "0"
eq "K40c control: the same window probe still sees an entry that stayed open" "$(awk '/^## Open/, /^## Closed/' "$REG" | grep -cF 'gamma surface' || true)" "1"

fixture "$W/fix"
cp "$REG" "$W/reg.closedry"
PLANT="$(plant_hour):3x"
vws register close --vault "$VAULT" --match "alpha surface" --date 2026-09-05 --status "closed at $PLANT" --dry-run
eq "K41 a dry run warns" "$(nlines "$SERR")" "1"
fmatch "K42 and shows the stamped status fact" "$SOUT" '^\| - \*\*Status\*\*: open — fix shape: alpha \*\(2026-09-05: closed 2026-09-05 [0-9]{2}:[0-9]{2} — closed at '"$PLANT"'\)\*$'
if cmp -s "$W/reg.closedry" "$REG"; then ok "K43 the warned dry run wrote nothing"; else no "K43 the warned dry run changed the register"; fi

echo "== the clock: ideas annotate =="

fixture "$W/fix"
T0=$(now_hm)
vws ideas annotate --file "$IDEAS" --item 11 --note "a plain note" --date 2026-09-05
T1=$(now_hm)
eq "K44 exit 0" "$RC" "0"
fmatch "K45 the note prefix carries the date and the clock's time" "$IDEAS" '^- \*\*№11\*\* a short item \*\(agent 2026-09-05 [0-9]{2}:[0-9]{2}: a plain note\)\*$'
eq2 "K46 the time is the clock's own" "$(awk 'NR==5' "$IDEAS")" "- **№11** a short item *(agent 2026-09-05 $T0: a plain note)*" "- **№11** a short item *(agent 2026-09-05 $T1: a plain note)*"
eq "K47 the note names no time of its own, so nothing is warned" "$(nlines "$SERR")" "0"
PLANT="$(plant_hour):3x"
vws ideas annotate --file "$IDEAS" --item 119 --note "a note about $PLANT" --date 2026-09-05
eq "K48 control: the same silence probe fires on a planted hour" "$(nlines "$SERR")" "1"
eq "K49 the note was written all the same" "$(count "$IDEAS" "a note about $PLANT")" "1"
eq "K50 stdout is still one line" "$(nlines "$SOUT")" "1"

fixture "$W/fix"
cp "$IDEAS" "$W/ideas.clockdry"
PLANT="$(plant_hour):3x"
vws ideas annotate --file "$IDEAS" --item 11 --note "dry at $PLANT" --date 2026-09-05 --dry-run
eq "K51 a dry run warns" "$(nlines "$SERR")" "1"
fmatch "K52 and shows the stamped line" "$SOUT" '\| - \*\*№11\*\* a short item \*\(agent 2026-09-05 [0-9]{2}:[0-9]{2}: dry at '"$PLANT"'\)\*'
if cmp -s "$W/ideas.clockdry" "$IDEAS"; then ok "K53 the warned dry run wrote nothing"; else no "K53 the warned dry run changed the file"; fi

echo "== the clock: the token and the grace =="

# The wall clock cannot be moved, so the two rules that depend on it are exercised through
# the module's own functions with the clock passed in. Each string below carries its own
# positive control: the same probe that returns 0 for a case it must pass returns 1 for one
# it must catch, in the same run.
TOKENS=$("$PY" -B -c '
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("vwmod", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
now = time.struct_time((2026, 9, 8, 9, 30, 0, 0, 0, -1))   # 09:30, mid-hour
print(",".join(mod.clock_tokens(now, [
    "twice at 21:3x and again 21:3x",   # caught once: the rounded Mx form, deduplicated
    "at 19:52:29 exactly",              # caught once: 19:52, and 52:29 is not a second token
    "at 8:07 this morning",             # caught: a one-digit hour
    "at 9:30 now", "at 9:05 too",       # silent: the clock own hour
    "PASS 139/139", "1300 hours",       # silent: no token at all
    "at 25:00", "x9:30x",               # silent: not an hour, and not a token in a word
])))
' "$S")
eq "K54 the token regex catches what it must and skips what it must not" "$TOKENS" "21:3x,19:52,8:07"

GRACE=$("$PY" -B -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vwmod", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
cases = [(9, 9, 30), (8, 9, 5), (8, 9, 9), (8, 9, 10), (8, 9, 30),
         (23, 0, 5), (23, 0, 30), (12, 9, 5)]
print("".join("1" if mod.hour_disagrees(t, h, m) else "0" for t, h, m in cases))
' "$S")
# clock hour · previous hour at minute 5 and 9 · previous hour at minute 10 and 30 · the
# midnight wrap either side of the grace · an unrelated hour inside the grace.
eq "K55 the ten-minute grace, hour by hour" "$GRACE" "00011011"
eq "K56 the grace bound is the constant the file documents" "$("$PY" -B -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vwmod", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.GRACE_MINUTES)
' "$S")" "10"

fixture "$W/fix"
# The live clock against the grace: under minute ten the previous hour passes, at or past it
# the same token is warned. Reading the minute either side of the call keeps the leg honest
# when the minute turns during it.
M0=$(now_min)
PREV="$(prev_hour):45"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "omicron surface" --symptom "an event at $PREV" --cause "c" --severity minor --status "open — x"
M1=$(now_min)
GOT=$(nlines "$SERR")
if [ "$M0" -lt 10 ] && [ "$M1" -lt 10 ]; then
	eq "K57 the previous hour is silent inside the grace (clock minute $M0)" "$GOT" "0"
elif [ "$M0" -ge 10 ] && [ "$M1" -ge 10 ]; then
	eq "K57 the previous hour is warned outside the grace (clock minute $M0)" "$GOT" "1"
else
	eq2 "K57 the grace boundary turned during the call (minute $M0 to $M1)" "$GOT" "0" "1"
fi

echo "== what the primitives may touch =="

# A sha256 manifest of every file under a tree, one line each: the proof that a run changed
# the file it named and nothing else.
manifest() {
	"$PY" -B -c 'import hashlib, os, sys
root = sys.argv[1]
for base, dirs, files in os.walk(root):
    for name in sorted(files):
        path = os.path.join(base, name)
        with open(path, "rb") as handle:
            print(hashlib.sha256(handle.read()).hexdigest(), os.path.relpath(path, root))
' "$1" | sort
}
changed_paths() { diff "$1" "$2" | awk '$1 == "<" || $1 == ">" { print $NF }' | sort -u | tr '\n' ' '; }

fixture "$W/fix"
manifest "$W/fix" > "$W/man.before"
vw log-append --vault "$VAULT" --action framework --title "sweep" --changed "c" --conflicts "none" --date 2026-09-05
vw register add --vault "$VAULT" --date 2026-09-05 --surface "iota — swept" --symptom "s" --cause "c" --severity minor --status "open"
vw register close --vault "$VAULT" --match "alpha surface" --date 2026-09-05 --status "swept"
vw ideas annotate --file "$IDEAS" --item 119 --note "swept" --date 2026-09-05
manifest "$W/fix" > "$W/man.after"
eq "E1 the four verbs changed the three files they were pointed at, and no other" "$(changed_paths "$W/man.before" "$W/man.after")" "IDEAS.md vault/wiki/developments/known-issues.md vault/wiki/log.md "
touch "$W/fix/planted-by-the-suite.txt"
manifest "$W/fix" > "$W/man.planted"
eq "E1c control: the same manifest catches a file the suite planted" "$(changed_paths "$W/man.after" "$W/man.planted")" "planted-by-the-suite.txt "
eq "E2 no atomic-write temp file survives the run" "$(find "$W/fix" -name '.vault-writes-*' | wc -l | tr -d ' ')" "0"
touch "$W/fix/.vault-writes-planted.tmp"
eq "E2c control: the same probe sees a planted temp file" "$(find "$W/fix" -name '.vault-writes-*' | wc -l | tr -d ' ')" "1"

# A warning is not a write: the manifest around a warned run, and around a warned dry run.
fixture "$W/fix"
manifest "$W/fix" > "$W/man.warned.before"
PLANT="$(plant_hour):3x"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "pi — warned" --symptom "at $PLANT" --cause "c" --severity minor --status "open"
manifest "$W/fix" > "$W/man.warned.after"
eq "E2d a warned write still touches only the file it was pointed at" "$(changed_paths "$W/man.warned.before" "$W/man.warned.after")" "vault/wiki/developments/known-issues.md "
eq "E2e control: the warning did fire on that run" "$(nlines "$SERR")" "1"

fixture "$W/fix"
manifest "$W/fix" > "$W/man.dry.before"
vws register add --vault "$VAULT" --date 2026-09-05 --surface "rho — warned dry" --symptom "at $PLANT" --cause "c" --severity minor --status "open" --dry-run
manifest "$W/fix" > "$W/man.dry.after"
eq "E2f a warned dry run touches nothing at all" "$(changed_paths "$W/man.dry.before" "$W/man.dry.after")" ""
eq "E2g control: that dry run warned too" "$(nlines "$SERR")" "1"

# The two shipped files travel with the public framework: no owner path, no wikilink. Both
# patterns are built at run time so that this file does not fail its own probe.
SELF="$HERE/$(basename "$0")"
SLASH=$(printf '\057')
OWNER_PAT="${SLASH}Users${SLASH}"
LINK_PAT=$(printf '%s%s' '[' '[')
eq "E3 the script names no absolute owner path" "$(grep -c "$OWNER_PAT" "$S" || true)" "0"
eq "E4 the suite names no absolute owner path" "$(grep -c "$OWNER_PAT" "$SELF" || true)" "0"
eq "E5 the script carries no wikilink" "$(grep -cF "$LINK_PAT" "$S" || true)" "0"
eq "E6 the suite carries no wikilink" "$(grep -cF "$LINK_PAT" "$SELF" || true)" "0"
printf '%ssomebody%svault %sa-page]]\n' "$OWNER_PAT" "$SLASH" "$LINK_PAT" > "$W/hygiene-control.txt"
eq "E6c control: the same two greps hit a planted line" "$(grep -c "$OWNER_PAT" "$W/hygiene-control.txt")$(grep -cF "$LINK_PAT" "$W/hygiene-control.txt")" "11"

eq "E7 the script under test leaves no bytecode of its own" "$(find "$HERE" -name 'vault_writes*.pyc' | wc -l | tr -d ' ')" "0"
mkdir -p "$W/fix/__pycache__"
touch "$W/fix/__pycache__/vault_writes.cpython-planted.pyc"
eq "E7c control: the same probe sees a planted bytecode file" "$(find "$W/fix" -name 'vault_writes*.pyc' | wc -l | tr -d ' ')" "1"

fixture "$W/fix"
if [ "$(id -u)" = "0" ]; then
	echo "  --   E8 skipped: running as root, a read-only directory would not refuse"
else
	chmod 500 "$VAULT/wiki/developments"
	vw register add --vault "$VAULT" --date 2026-09-05 --surface "s" --symptom "s" --cause "c" --severity minor --status "open"
	eq "E8 a read-only target directory is refused, not a traceback" "$RC" "2"
	eq "E9 one error line only" "$(nlines "$OUT")" "1"
	has "E10 it names the failure" "error vault-writes:"
	chmod 700 "$VAULT/wiki/developments"
	eq "E11 the register is unchanged after the refusal" "$(count "$REG" '### [')" "5"
fi

vw log-append --help
eq "E12 log-append has help" "$RC" "0"
has "E13 the help names the vault argument" "--vault"
vw register close --help
eq "E14 the nested verb has help too" "$RC" "0"
vw
eq "E15 no verb at all is refused" "$RC" "2"
vw register
eq "E16 a bare register is refused" "$RC" "2"

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "PASS $PASS/$TOTAL"
	exit 0
fi
echo "FAIL $FAIL/$TOTAL"
exit 1
