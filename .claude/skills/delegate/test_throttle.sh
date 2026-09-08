#!/bin/sh
# test_throttle.sh — regression suite for throttle.py (delegate skill, the routing throttle).
#
# Every fixture is a throwaway vault under one `mktemp -d`: a routing record, a synthetic
# CUSTOMISATION.md, and one definition per routed role (the live `.claude/agents/` copy where the
# vault has one, a generated stand-in where it does not, so the suite also runs on a fresh clone
# that ships no definitions). `set` is never run outside those fixtures.
#
# Three records, and which legs use which — the installed record moves under the suite (a v1→v2
# install, and later a gate moving a carried default down), so no leg may assume its shape:
#   * the v1 record, EMBEDDED below — every schema-1 leg. It is a fixture, not a snapshot to keep
#     in step with anything: the v1 rules it exercises are frozen.
#   * the v2 record, the suite's own hand-written copy of the design table (or ROUTING_V2=<file>)
#     — every schema-2 resolution leg, pinned against the design's TARGET defaults.
#   * the installed `routing.json` — only legs that hold by construction whatever it currently
#     says: its option sets (pinned; a gate never moves those), its defaults against the
#     definitions on disk (read, never pinned), and the rule that a carried default sits at or
#     above the target its `dated` names.
#
# Controls (CLAUDE.md 11): every leg that asserts a clean or empty result is paired with a leg that
# plants the fault and proves the same probe fires. The expected model/effort values are pinned as
# literals below, hand-derived from the design page's routing record, so the suite does not grade
# the code against the same file the code reads.
#
# Run:  sh test_throttle.sh          (last line: PASS n/n or FAIL k/n; exit 0 only when clean)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/throttle.py"
R="$HERE/routing.json"
VAULT=$(cd "$HERE/../../.." && pwd)      # .claude/skills/delegate -> vault root
PY="${PYTHON:-python3}"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL   — $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }

W=$(mktemp -d)
OUT="$W/out.txt"
cleanup() { chmod -R u+w "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
[ -f "$S" ] || { echo "PROBE FAILED: no throttle.py at $S"; echo "FAIL 1/1"; exit 2; }
[ -f "$R" ] || { echo "PROBE FAILED: no routing.json at $R"; echo "FAIL 1/1"; exit 2; }

run() { "$@" >"$OUT" 2>&1; RC=$?; }
has() { grep -qF -- "$2" "$OUT" && ok "$1" || no "$1 (stdout lacks '$2')"; }
hasnot() { grep -qF -- "$2" "$OUT" && no "$1 (stdout still holds '$2')" || ok "$1"; }

# The value of one frontmatter field, read by an awk parser of its own so a definition is never
# graded by the parser under test.
fmval() {
	awk -v k="$2" '
	  NR==1 { if ($0 != "---") exit }
	  NR>1  { if ($0 == "---") exit
	          if (index($0, k ":") == 1) { v = substr($0, length(k)+2)
	                                       gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$1"
}
# Everything below the frontmatter, hashed — the proof `set` touched no body byte.
bodyhash() { "$PY" "$W/bodyhash.py" "$1"; }
# One checksum manifest of a whole fixture, for the "wrote nothing" legs.
manifest() { (cd "$1" && find . -type f -print0 | xargs -0 shasum) | LC_ALL=C sort; }

# ------------------------------------------------------------------ helper scripts ----------
cat >"$W/bodyhash.py" <<'BODYHASH_SCRIPT_END'
import hashlib, sys
raw = open(sys.argv[1], "rb").read()
lines = raw.splitlines(keepends=True)
close = None
for i in range(1, len(lines)):
    if lines[i].rstrip(b"\r\n") == b"---":
        close = i
        break
body = b"".join(lines[close + 1:]) if close is not None else raw
print(hashlib.sha256(body).hexdigest())
BODYHASH_SCRIPT_END

cat >"$W/mkfix.py" <<'MKFIX_SCRIPT_END'
"""Build one throwaway vault: synthetic CUSTOMISATION.md + one definition per routed role."""
import json, os, shutil, sys

dest, vault = sys.argv[1], sys.argv[2]
rec = json.load(open(os.path.join(dest, ".claude", "skills", "delegate", "routing.json")))
# Both schemas build the same fixture: `roles` (v1 triples/pairs) and `classes` (v2 option
# sets) name one row per definition stem, and a stand-in carries that row's default pair.
rows = rec.get("classes") or rec["roles"]


def defaults(spec):
    if isinstance(spec["model"], dict):
        return spec["model"]["default"], spec["effort"]["default"]
    return spec["model"][1], spec["effort"][1]
custom = """`CUSTOMISATION-LOADED-v1` — load marker.

## Settings
The live knobs.

- **agent_name**: testbot — what the agent calls itself (blank = none)
- **style**: balanced — any style defined in `## Output styles`
- **role**: generalist — any role defined in `## Roles`
- **language**: English (UK) — conversation language
- **effort**: standard — delegation compute tier: light · standard · max
- **pre-report**: auto — spawn-record echo before delegated runs: on · auto · off

## Identity
- a synthetic fixture, not a vault.
"""
with open(os.path.join(dest, "CUSTOMISATION.md"), "w", encoding="utf-8") as fh:
    fh.write(custom)

# A copied definition's real description may name a current tier, which `check` reports.
# The fixture's baseline has to be clean for the drift legs to mean anything, so every
# copied description is replaced by the durable range wording, which the stand-ins carry
# too; the description legs below plant the tier form back and prove the finding fires.
DURABLE = ("description: Routing range (admitted 2026-09-02): model sonnet–fable, "
           "effort high–max; the active throttle sets the current values.\n")
STAND_IN = """---
name: %s
""" + DURABLE + """model: %s
effort: %s
disallowedTools: Agent, SendMessage
---

Body text the throttle must never touch.
"""
live = os.path.join(vault, ".claude", "agents")
for role, spec in rows.items():
    dst = os.path.join(dest, ".claude", "agents", role + ".md")
    src = os.path.join(live, role + ".md")
    if os.path.isfile(src):
        lines = open(src, encoding="utf-8").read().splitlines(keepends=True)
        in_fm = bool(lines) and lines[0].rstrip("\r\n") == "---"
        out = []
        for i, line in enumerate(lines):
            if in_fm and i > 0 and line.rstrip("\r\n") == "---":
                in_fm = False
            elif in_fm and i > 0 and line.startswith("description:"):
                line = DURABLE
            out.append(line)
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write("".join(out))
    else:
        model, effort = defaults(spec)
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(STAND_IN % (role, model, effort))
MKFIX_SCRIPT_END

# The schema-1 record every v1 leg runs against. Embedded, never read from the installed file:
# the installed record moved to schema 2 on 2026-09-04, and a v1 leg pointed at it grades the v1
# rules against a record that no longer has them (12 legs failed exactly that way).
V1="$W/routing.v1.json"
cat >"$V1" <<'V1_RECORD_PAYLOAD_END'
{"order": {"model": ["haiku", "sonnet", "opus", "fable"], "effort": ["low", "medium", "high", "xhigh", "max"]},
 "roles": {
  "critic":        {"model": ["opus", "opus", "fable"],     "effort": ["xhigh", "max"]},
  "planner":       {"model": ["opus", "opus", "fable"],     "effort": ["high", "max"]},
  "reflector":     {"model": ["opus", "opus", "fable"],     "effort": ["high", "max"]},
  "verifier":      {"model": ["sonnet", "sonnet", "fable"], "effort": ["high", "max"]},
  "gate-judge":    {"model": ["opus", "opus", "opus"],      "effort": ["max", "max"]},
  "wiki-compile":  {"model": ["sonnet", "opus", "fable"],   "effort": ["medium", "max"]},
  "builder":       {"model": ["sonnet", "opus", "fable"],   "effort": ["high", "max"]},
  "memory-hunter": {"model": ["sonnet", "sonnet", "fable"], "effort": ["high", "max"]}}}
V1_RECORD_PAYLOAD_END

# $1 fixture name · $2 the record to install (default: the embedded v1 record)
mkfix() {
	d="$W/$1"
	rm -rf "$d"
	mkdir -p "$d/.claude/agents" "$d/.claude/skills/delegate"
	cp "${2:-$V1}" "$d/.claude/skills/delegate/routing.json"
	"$PY" "$W/mkfix.py" "$d" "$VAULT" || { echo "PROBE FAILED: fixture build for $1"; exit 2; }
}

# The expected values, hand-derived from the routing record in the design page:
#   order model haiku < sonnet < opus < fable ; order effort low < medium < high < xhigh < max
#   critic opus/opus/fable + xhigh/max · gate-judge opus/opus/opus + max/max
#   wiki-compile sonnet/opus/fable + medium/max · builder sonnet/opus/fable + high/max
#   memory-hunter sonnet/sonnet/fable + high/max
# top = ceiling/ceiling · default = default/ceiling · cheap = floor/ceiling
# fast = default/floor · cheap-fast = floor/floor · auto = as default (frozen legacy on a v1 record;
# 2026-09-08)
pins() { # $1 throttle -> "role model effort" triples, one per line
	case "$1" in
	auto) pins default ;;
	top) printf 'critic fable max\ngate-judge opus max\nwiki-compile fable max\nbuilder fable max\n' ;;
	default) printf 'critic opus max\ngate-judge opus max\nwiki-compile opus max\nbuilder opus max\n' ;;
	cheap) printf 'critic opus max\ngate-judge opus max\nwiki-compile sonnet max\nbuilder sonnet max\n' ;;
	fast) printf 'critic opus xhigh\ngate-judge opus max\nwiki-compile opus medium\nbuilder opus high\n' ;;
	cheap-fast) printf 'critic opus xhigh\ngate-judge opus max\nwiki-compile sonnet medium\nbuilder sonnet high\n' ;;
	esac
}
headline() {
	case "$1" in
	auto | top | default) echo "head: fable · max" ;;
	cheap | cheap-fast) echo "head: opus · max recommended" ;;
	fast) echo "head: fable · high recommended" ;;
	esac
}

ROLES=$("$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["roles"]))' "$V1")
NROLES=$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["roles"]))' "$V1")

echo "throttle.py suite — $NROLES routed roles, fixtures under $W"

# ================================================================== 1 · show ==========
mkfix show1
run "$PY" "$S" show --root "$W/show1"
eq "L01a show exits 0" "$RC" "0"
has "L01b show reports the absent Settings line as auto (the default preset from 2026-09-08)" "throttle: auto (no throttle line: treated as auto)"
eq "L01c show prints the pinned default row for wiki-compile" \
	"$(awk '$1=="wiki-compile"{print $2, $3}' "$OUT")" "opus max"
has "L01d show prints the head recommendation" "head: fable · max"
seen=0
for r in $ROLES; do
	awk -v r="$r" '$1==r{f=1} END{exit !f}' "$OUT" && seen=$((seen + 1))
done
eq "L01e show prints one table row per routed role" "$seen" "$NROLES"

# ================================================================== 2 · set + check ===
for T in auto top default cheap fast cheap-fast; do
	mkfix "s_$T"
	d="$W/s_$T"
	run "$PY" "$S" set "$T" --root "$d"
	eq "L02.$T set exits 0" "$RC" "0"
	run "$PY" "$S" check --root "$d"
	eq "L03.$T check clean after set" "$RC" "0"
	has "L04.$T check reports clean against '$T'" "match throttle '$T'"
	has "L05.$T check carries its comparator control" "control: comparator caught 2/2 planted drifts"
	bad=0
	pins "$T" | while read -r role m e; do
		[ "$(fmval "$d/.claude/agents/$role.md" model)" = "$m" ] || echo "$role model" >>"$W/pinfail"
		[ "$(fmval "$d/.claude/agents/$role.md" effort)" = "$e" ] || echo "$role effort" >>"$W/pinfail"
	done
	if [ -s "$W/pinfail" ]; then
		no "L06.$T pinned values on disk ($(tr '\n' ',' <"$W/pinfail"))"
		rm -f "$W/pinfail"
	else
		ok "L06.$T pinned values on disk"
	fi
	run "$PY" "$S" show --root "$d"
	eq "L07.$T show's head recommendation" "$(grep -F 'head: ' "$OUT")" "$(headline "$T")"
	bad=$bad
done

# ================================================================== 3 · idempotency ===
d="$W/s_default"
BEFORE=$(manifest "$d")
run "$PY" "$S" set default --root "$d"
eq "L08a second set exits 0" "$RC" "0"
has "L08b second set says there is nothing to do" "nothing to do (already at 'default')"
eq "L08c second set left every byte identical" "$(manifest "$d")" "$BEFORE"

# ================================================================== 4 · planted drift =
# Control pair for L03.default: the same check on the same fixture, one field moved.
d="$W/drift"
mkfix drift
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L09a control — check is clean before the plant" "$RC" "0"
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_DRIFT_END'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read().replace("\neffort: max\n", "\neffort: low\n", 1)
open(p, "w", encoding="utf-8").write(t)
PLANT_DRIFT_END
run "$PY" "$S" check --root "$d"
eq "L09b planted drift exits 1" "$RC" "1"
has "L09c planted drift names the file and the field" "DRIFT .claude/agents/critic.md: effort low ≠ max"

# ================================================================== 5 · Settings line =
d="$W/absent"
mkfix absent
run "$PY" "$S" set default --root "$d"
n=$(grep -n -F -- '- **pre-report**:' "$d/CUSTOMISATION.md" | head -1 | cut -d: -f1)
nxt=$(sed -n "$((n + 1))p" "$d/CUSTOMISATION.md")
case "$nxt" in
'- **throttle**: default — subagent routing throttle: auto (the default: model and effort picked per call within the class ranges, the row anchor the reference, each departure recorded with its reason) · top · default · cheap · fast · cheap-fast (hand-set overrides, never re-resolved); semantics in the delegate skill §2 (say "set throttle to X"; the head runs throttle.py set)')
	ok "L10a set inserts the exact Settings line directly after pre-report" ;;
*) no "L10a set inserts the exact Settings line directly after pre-report (got '$nxt')" ;;
esac
"$PY" - "$d/CUSTOMISATION.md" <<'DROP_LINE_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?mi)^-\s*\*\*throttle\*\*:.*\n", "", open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
DROP_LINE_END
run "$PY" "$S" check --root "$d"
eq "L10b a missing Settings line is not a failure" "$RC" "0"
has "L10c the missing line is reported once, as auto" "throttle: auto (no throttle line: treated as auto)"

# ================================================================== 6 · broken premises
d="$W/premise"
mkfix premise
run "$PY" "$S" check --root "$d"
# The intact fixture may be clean (stand-in definitions) or hold a drift (a live definition
# already off the routing default); either is a run. Only exit 2 would mean the probe never ran.
eq "L11a control — the premise fixture checks without a probe failure" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
hasnot "L11b control — no PROBE FAILED on the intact fixture" "PROBE FAILED"

sed -i.bak 's/^- \*\*pre-report\*\*: auto/- **throttle**: turbo — bogus\
- **pre-report**: auto/' "$d/CUSTOMISATION.md"
run "$PY" "$S" check --root "$d"
eq "L12a unknown throttle name exits 2" "$RC" "2"
has "L12b unknown throttle name names it" "PROBE FAILED: unknown throttle 'turbo'"
mv "$d/CUSTOMISATION.md.bak" "$d/CUSTOMISATION.md"

RJ="$d/.claude/skills/delegate/routing.json"
mv "$RJ" "$W/rj.keep"
run "$PY" "$S" check --root "$d"
eq "L13a a missing routing record exits 2 (never a silent fallback to another copy)" "$RC" "2"
has "L13b the missing record names its path" "PROBE FAILED: no routing record at"
mv "$W/rj.keep" "$RJ"

printf '{"order": {"model": [' >"$RJ.broken"
cp "$RJ" "$W/rj.keep"
cp "$RJ.broken" "$RJ"
run "$PY" "$S" check --root "$d"
eq "L14a invalid JSON exits 2" "$RC" "2"
has "L14b invalid JSON says so" "is not valid JSON"
cp "$W/rj.keep" "$RJ"

chmod 000 "$RJ"
if [ -r "$RJ" ]; then
	no "L15 unreadable-record leg (chmod 000 left the file readable — leg cannot run)"
else
	run "$PY" "$S" check --root "$d"
	if [ "$RC" = "2" ] && grep -qF -- "unreadable" "$OUT"; then
		ok "L15 an unreadable routing record exits 2"
	else
		no "L15 an unreadable routing record exits 2 (rc=$RC)"
	fi
fi
chmod 644 "$RJ"

"$PY" - "$RJ" <<'NONMONOTONE_END'
import json, sys
p = sys.argv[1]
rec = json.load(open(p))
rec["roles"]["critic"]["model"] = ["fable", "opus", "sonnet"]   # ceiling below the floor
json.dump(rec, open(p, "w"))
NONMONOTONE_END
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d"
eq "L16a a non-monotone record refuses set, exit 2" "$RC" "2"
has "L16b the refusal names the role and axis" "role \`critic\` model range is not floor"
eq "L16c the refused set wrote nothing" "$(manifest "$d")" "$BEFORE"
cp "$W/rj.keep" "$RJ"
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d"
eq "L16d control — with the record repaired the same set does write" \
	"$(if [ "$(manifest "$d")" = "$BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"

d="$W/badfm"
mkfix badfm
"$PY" - "$d/.claude/agents/verifier.md" <<'BREAK_FM_END'
import sys
p = sys.argv[1]
open(p, "w", encoding="utf-8").write("no frontmatter here\nmodel: opus\n")
BREAK_FM_END
run "$PY" "$S" check --root "$d"
eq "L17a an unparseable definition exits 2" "$RC" "2"
has "L17b it names the file and the reason" "verifier.md: no frontmatter"

run "$PY" "$S" set nitro --root "$W/badfm"
eq "L18a an unknown NAME on set exits 2" "$RC" "2"
has "L18b it lists the known names" "PROBE FAILED: unknown throttle 'nitro'"

# ================================================================== 7 · roster findings
d="$W/roster"
mkfix roster
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L19a control — the roster fixture is clean before the plant" "$RC" "0"
printf -- '---\nname: stranger\nmodel: opus\neffort: max\n---\n\nbody\n' >"$d/.claude/agents/stranger.md"
run "$PY" "$S" check --root "$d"
eq "L19b an unrouted definition is a finding" "$RC" "1"
has "L19c it is named as UNROUTED" "UNROUTED .claude/agents/stranger.md"
rm -f "$d/.claude/agents/stranger.md"
rm -f "$d/.claude/agents/reflector.md"
run "$PY" "$S" check --root "$d"
eq "L20a a routed role with no definition is a finding" "$RC" "1"
has "L20b it is named as MISSING" "MISSING .claude/agents/reflector.md"

# ================================================================== 8 · --require =====
d="$W/require"
mkfix require
run "$PY" "$S" set cheap --root "$d"
run "$PY" "$S" check --root "$d" --require cheap
eq "L21a control — --require matching the active throttle is clean" "$RC" "0"
run "$PY" "$S" check --root "$d" --require default
eq "L21b --require default against a cheap vault exits 1" "$RC" "1"
has "L21c the require finding names both" "REQUIRE default: the active throttle is cheap"

# ================================================================== 9 · --dry-run =====
d="$W/dry"
mkfix dry
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d" --dry-run
eq "L22a --dry-run exits 0" "$RC" "0"
has "L22b --dry-run says nothing was written" "(dry run — nothing written)"
eq "L22c --dry-run left every byte identical" "$(manifest "$d")" "$BEFORE"
run "$PY" "$S" set top --root "$d"
eq "L22d control — the same set without --dry-run does write" \
	"$(if [ "$(manifest "$d")" = "$BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"

# ================================================================== 10 · body bytes ===
d="$W/body"
mkfix body
for role in $ROLES; do
	bodyhash "$d/.claude/agents/$role.md" >>"$W/body.before"
done
run "$PY" "$S" set cheap-fast --root "$d"
for role in $ROLES; do
	bodyhash "$d/.claude/agents/$role.md" >>"$W/body.after"
done
eq "L23a set changed no body byte in any definition" \
	"$(cat "$W/body.before")" "$(cat "$W/body.after")"
eq "L23b control — the frontmatter did move" \
	"$(fmval "$d/.claude/agents/wiki-compile.md" effort)" "medium"

# ================================================================== 11 · other fields =
d="$W/fields"
mkfix fields
cat >"$d/.claude/agents/gate-judge.md" <<'GATE_FIXTURE_END'
---
name: gate-judge
description: A fixture definition carrying every extra frontmatter shape the vault uses.
model: haiku
effort: low
tools: Read, Grep, Glob
memory: local
skills:
  - ingest
---

Body text the throttle must never touch.
GATE_FIXTURE_END
run "$PY" "$S" set top --root "$d"
eq "L24a set rewrote the two routed fields" \
	"$(fmval "$d/.claude/agents/gate-judge.md" model)/$(fmval "$d/.claude/agents/gate-judge.md" effort)" \
	"opus/max"
eq "L24b every other frontmatter line survived byte-identical" \
	"$(sed -n '2,$p' "$d/.claude/agents/gate-judge.md" | sed -n '/^---$/q;p' | grep -v '^model:\|^effort:')" \
	"$(printf 'name: gate-judge\ndescription: A fixture definition carrying every extra frontmatter shape the vault uses.\ntools: Read, Grep, Glob\nmemory: local\nskills:\n  - ingest')"

# ================================================================== 12 · absent fields
d="$W/nofields"
mkfix nofields
cat >"$d/.claude/agents/planner.md" <<'NOFIELDS_FIXTURE_END'
---
name: planner
description: A fixture definition with neither routed field.
disallowedTools: Agent, SendMessage
---

Body text the throttle must never touch.
NOFIELDS_FIXTURE_END
run "$PY" "$S" check --root "$d"
eq "L25a an absent field is a finding" "$RC" "1"
has "L25b the finding says the field is absent" "DRIFT .claude/agents/planner.md: model absent ≠ opus"
run "$PY" "$S" set default --root "$d"
eq "L25c set adds both fields, exit 0" "$RC" "0"
eq "L25d the added fields hold the resolved values" \
	"$(fmval "$d/.claude/agents/planner.md" model)/$(fmval "$d/.claude/agents/planner.md" effort)" \
	"opus/max"
run "$PY" "$S" check --root "$d"
eq "L25e check is clean once the fields exist" "$RC" "0"

# ================================================================== 13 · stdout only ==
# `show` and `check` must need no write permission at all, and must leave every byte alone.
d="$W/ro"
mkfix ro
run "$PY" "$S" set default --root "$d"
BEFORE=$(manifest "$d")
chmod -R a-w "$d"
run "$PY" "$S" show --root "$d"
RC1=$RC
run "$PY" "$S" check --root "$d"
RC2=$RC
run "$PY" "$S" check --root "$d" --require default
RC3=$RC
run "$PY" "$S" set top --root "$d" --dry-run
RC4=$RC
chmod -R u+w "$d"
eq "L26a show/check/--require/--dry-run all ran on a read-only copy" "$RC1$RC2$RC3$RC4" "0000"
eq "L26b the read-only copy is byte-identical afterwards" "$(manifest "$d")" "$BEFORE"

# Source grep: one write call site, reached only from cmd_set. Its own positive control is that
# the pattern must hit at all — a zero-hit grep would "prove" the script never writes.
WRITES=$(grep -c -E 'open\([^)]*"w"|os\.remove|os\.replace|os\.rename|shutil\.|\.unlink\(' "$S")
eq "L27a exactly one write call site in the source (control: the pattern hits)" "$WRITES" "1"
eq "L27b that call site sits inside write_text" \
	"$(grep -n -E 'open\([^)]*"w"' "$S" | cut -d: -f1)" \
	"$(awk '/^def write_text/{d=NR} /open\([^)]*"w"/{if (NR>d && d) {print NR; exit}}' "$S")"
eq "L27c write_text is called from exactly one place" "$(grep -c '^ *write_text(' "$S")" "1"
eq "L27d and that place is cmd_set" \
	"$(awk '/^def cmd_set/{s=NR} /^def main/{m=NR} /^ *write_text\(/{c=NR} END{print (c>s && c<m) ? "yes" : "no"}' "$S")" \
	"yes"

# ================================================================== 14 · description ==
# A description naming a CURRENT tier goes stale the moment a throttle moves it. `set` never
# rewrites prose, so `check` reports it for a human to reword.
d="$W/desc"
mkfix desc
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L28a control — the durable range wording is clean" "$RC" "0"
hasnot "L28b no DESCRIPTION-TIER line on the durable wording" "DESCRIPTION-TIER"
DESC_BEFORE=$(grep -c -F 'the active throttle sets the current values' "$d/.claude/agents/critic.md")
eq "L28c set left the description line in place" "$DESC_BEFORE" "1"
for tier in low medium high xhigh max; do
	"$PY" - "$d/.claude/agents/critic.md" "$tier" <<'PLANT_DESC_END'
import re, sys
p, tier = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · %s effort; per-call override." % tier,
           t, count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_DESC_END
	run "$PY" "$S" check --root "$d"
	if [ "$RC" = "1" ] && grep -qF -- "DESCRIPTION-TIER .claude/agents/critic.md" "$OUT"; then
		ok "L29.$tier a description naming '$tier' is a finding"
	else
		no "L29.$tier a description naming '$tier' is a finding (rc=$RC)"
	fi
done
# A word after the separator that is not a tier must not fire: the probe keys on the tier list.
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_NONTIER_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · sonnet effort; per-call override.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_NONTIER_END
run "$PY" "$S" check --root "$d"
eq "L30a a non-tier word after the separator does not fire" "$RC" "0"
hasnot "L30b and no DESCRIPTION-TIER line is printed" "DESCRIPTION-TIER"
# Live miss 2026-09-02: the reflector wording names a tier without the word "effort".
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_REFL_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Read-only lane. Routing (owner-admitted 2026-08-28) opus · max; fable escalation discouraged.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_REFL_END
run "$PY" "$S" check --root "$d"
if [ "$RC" = "1" ] && grep -qF -- "DESCRIPTION-TIER .claude/agents/critic.md" "$OUT"; then
	ok "L29r a tier after a middle dot without the word effort is a finding"
else
	no "L29r a tier after a middle dot without the word effort is a finding (rc=$RC)"
fi
# `set` must not rewrite prose, tier-naming or not.
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_STALE_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · max effort; per-call override.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_STALE_END
DESC_BEFORE=$(grep -F 'description:' "$d/.claude/agents/critic.md")
run "$PY" "$S" set cheap --root "$d"
eq "L31 set never rewrites a description, stale tier and all" \
	"$(grep -F 'description:' "$d/.claude/agents/critic.md")" "$DESC_BEFORE"

# ================================================================== 15 · N of M =======
d="$W/count"
mkfix count
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
has "L32a the summary names how many of the routed roles were diffed" "$NROLES of $NROLES diffed"
rm -f "$d/.claude/agents/verifier.md"
run "$PY" "$S" check --root "$d"
has "L32b control — one definition short, the count drops" "$((NROLES - 1)) of $NROLES diffed"

# ================================================================== 16 · no agents ====
d="$W/noagents"
mkfix noagents
run "$PY" "$S" check --root "$d"
eq "L33a control — the fixture checks while the directory is there" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
rm -rf "$d/.claude/agents"
run "$PY" "$S" check --root "$d"
eq "L33b an absent .claude/agents directory is a broken premise, exit 2" "$RC" "2"
has "L33c it says which directory is missing" "PROBE FAILED: no definitions directory at .claude/agents"
run "$PY" "$S" set default --root "$d"
eq "L33d set refuses the same way" "$RC" "2"

# ============================================================ L34 Skill unavailable ======
# Levers L1 (2026-09-04): every definition must leave the Skill tool unavailable to its lane --
# either a `tools:` allowlist that omits Skill, or `disallowedTools:` that names it. Keyed on the
# property, never on a definition's name (critic F9). Controls: planted definitions that fail it.
skill_off() {  # $1 = definition path; prints yes|no
    if grep -q '^tools:' "$1"; then
        if grep '^tools:' "$1" | grep -q 'Skill'; then echo no; else echo yes; fi
    elif grep '^disallowedTools:' "$1" | grep -q 'Skill'; then echo yes
    else echo no; fi
}
BADDEF=""; NDEF=0
for f in "$VAULT"/.claude/agents/*.md; do
    [ -f "$f" ] || continue; NDEF=$((NDEF + 1))
    [ "$(skill_off "$f")" = "yes" ] || BADDEF="$BADDEF $(basename "$f")"
done
eq "L34a every live definition leaves Skill unavailable ($NDEF checked)" "$BADDEF" ""
if [ "$NDEF" -gt 0 ]; then ok "L34b the live definitions directory was non-empty ($NDEF)"; else no "L34b no definitions found at $VAULT/.claude/agents"; fi
d="$W/l34"; mkdir -p "$d"
printf -- '---\nname: planted\nmodel: opus\neffort: max\ndisallowedTools: Agent, SendMessage\n---\nbody\n' > "$d/planted.md"
eq "L34c control: a definition with neither an allowlist nor Skill in disallowedTools is caught" "$(skill_off "$d/planted.md")" "no"
printf -- '---\nname: planted2\ntools: Read, Grep, Skill\n---\nbody\n' > "$d/planted2.md"
eq "L34d control: an allowlist that names Skill is caught" "$(skill_off "$d/planted2.md")" "no"

# ======================================================= 17 · schema 2: the record ===
# The v2 record under test is the suite's own hand-written copy of the design page's class
# table (thin-lanes-design.md, "The class table"), so the code is never graded against the
# same file it reads. `ROUTING_V2=<path> sh test_throttle.sh` swaps in a candidate record —
# how a proposed or freshly installed routing.json is graded against the same hand-derived
# pins before it goes live. 2026-09-08: the record pins the design's TARGET effort defaults,
# and the owner's per-call rule of 2026-09-07 17:0x moved those targets to the anchor `xhigh`
# for the closed-task classes; of the three rows here that moves verifier (high → xhigh) —
# wiki-compile already read xhigh and gate-judge is fixed — so the row and its pins move too.
V2="${ROUTING_V2:-$W/routing.v2.json}"
if [ -n "${ROUTING_V2:-}" ]; then
	[ -f "$V2" ] || { echo "PROBE FAILED: ROUTING_V2 names no file ($V2)"; echo "FAIL 1/1"; exit 2; }
	SCH=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("schema", 1))' "$V2" 2>&1)
	[ "$SCH" = "2" ] || { echo "PROBE FAILED: ROUTING_V2 record is schema $SCH, not 2"; echo "FAIL 1/1"; exit 2; }
	echo "v2 record under test: $V2 (ROUTING_V2)"
else
	cat >"$V2" <<'V2_RECORD_PAYLOAD_END'
{"schema": 2,
 "order": {"model": ["haiku", "sonnet", "opus", "fable"],
           "effort": ["low", "medium", "high", "xhigh", "max"]},
 "classes": {
  "verifier": {
    "model": {"options": ["sonnet", "opus", "fable"], "default": "sonnet"},
    "effort": {"options": ["high", "xhigh", "max"], "default": "xhigh"},
    "grants": {"default": ["<claim files>"], "extras": ["wiki", "raw"]},
    "writes": [], "tools": ["Read", "Grep", "Glob", "Bash"],
    "skills": {"default": ["lane-core"], "extras": ["markitdown"]},
    "mcp": {"default": [], "grantable": []},
    "cache": "1h", "gate": "G6a; re-gate at high", "dated": "fixture row"},
  "wiki-compile": {
    "model": {"options": ["sonnet", "opus", "fable"], "default": "opus"},
    "effort": {"options": ["medium", "high", "xhigh", "max"], "default": "xhigh"},
    "grants": {"default": ["wiki", "<assigned raw files>"], "extras": ["assets"]},
    "writes": ["wiki"], "tools": ["Read", "Grep", "Glob", "Bash", "Write", "Edit"],
    "skills": {"default": ["lane-core", "compile-core"], "extras": ["markitdown"]},
    "mcp": {"default": [], "grantable": []},
    "cache": "1h", "gate": "G3/G4; re-gate thin at opus xhigh", "dated": "fixture row"},
  "gate-judge": {
    "model": {"options": ["opus"], "default": "opus"},
    "effort": {"options": ["max"], "default": "max"},
    "grants": {"default": ["<fixture>"], "extras": []},
    "writes": [], "tools": ["Read", "Grep", "Glob"],
    "skills": {"default": ["lane-core"], "extras": []},
    "mcp": {"default": [], "grantable": []},
    "cache": "1h", "gate": "it is the gate", "dated": "fixture row"}}}
V2_RECORD_PAYLOAD_END
	echo "v2 record under test: the suite's own hand-written class table"
fi

# Pinned as literals, hand-derived from the design page's class table (the default in bold
# there, the weakest and strongest options its floor and ceiling by construction):
#   verifier      models sonnet* opus fable   · efforts high xhigh* max   (effort default moved
#                 high → xhigh on 2026-09-08: the anchor under the per-call rule of 2026-09-07 17:0x)
#   wiki-compile  models sonnet opus* fable   · efforts medium high xhigh* max
#   gate-judge    models opus (single)        · efforts max (single)
# top = strongest/strongest · default = default/default · cheap = weakest/strongest
# fast = default/weakest · cheap-fast = weakest/weakest · auto = default/default (the anchors)
rpins() { # $1 class · $2 throttle -> "model effort"
	case "$1/$2" in
	verifier/auto) echo "sonnet xhigh" ;;
	verifier/top) echo "fable max" ;;
	verifier/default) echo "sonnet xhigh" ;;
	verifier/cheap) echo "sonnet max" ;;
	verifier/fast) echo "sonnet high" ;;
	verifier/cheap-fast) echo "sonnet high" ;;
	wiki-compile/auto) echo "opus xhigh" ;;
	wiki-compile/top) echo "fable max" ;;
	wiki-compile/default) echo "opus xhigh" ;;
	wiki-compile/cheap) echo "sonnet max" ;;
	wiki-compile/fast) echo "opus medium" ;;
	wiki-compile/cheap-fast) echo "sonnet medium" ;;
	gate-judge/top) echo "opus max" ;;
	gate-judge/cheap-fast) echo "opus max" ;;
	*) echo "NO-PIN" ;;
	esac
}
rgot() { awk '/^model: /{m=$2} /^effort: /{e=$2} END{print m, e}' "$OUT"; }

D2="$W/v2"
mkfix v2 "$V2"
for T in auto top default cheap fast cheap-fast; do
	run "$PY" "$S" resolve --class wiki-compile --throttle "$T" --root "$D2"
	eq "L35.$T resolve wiki-compile under '$T'" "$(rgot)" "$(rpins wiki-compile "$T")"
	run "$PY" "$S" resolve --class verifier --throttle "$T" --root "$D2"
	eq "L36.$T resolve verifier under '$T'" "$(rgot)" "$(rpins verifier "$T")"
done
# A single-option row: every throttle resolves to the same pair, so min and max over a
# one-element set are exercised rather than assumed.
run "$PY" "$S" resolve --class gate-judge --throttle top --root "$D2"
eq "L37a resolve gate-judge under 'top'" "$(rgot)" "$(rpins gate-judge top)"
run "$PY" "$S" resolve --class gate-judge --throttle cheap-fast --root "$D2"
eq "L37b resolve gate-judge under 'cheap-fast' (single-option row)" "$(rgot)" "$(rpins gate-judge cheap-fast)"

# ======================================================= 18 · resolve's whole row =====
run "$PY" "$S" resolve --class wiki-compile --throttle default --root "$D2"
eq "L38a resolve exits 0" "$RC" "0"
eq "L38b the tools line is the row's tool grant" \
	"$(awk -F': ' '/^tools: /{print $2}' "$OUT")" "Read, Grep, Glob, Bash, Write, Edit"
eq "L38c the grants line names the row's default reads" \
	"$(awk -F': ' '/^grants: /{print $2}' "$OUT")" "wiki, <assigned raw files>"
eq "L38d the skills line names the lane core and the compile slice" \
	"$(awk -F': ' '/^skills: /{print $2}' "$OUT")" "lane-core, compile-core"
eq "L38e an empty list prints as (none), never as a blank" \
	"$(awk -F': ' '/^mcp: /{print $2}' "$OUT")" "(none)"
eq "L38f the cache line is the headless 1-hour tier" \
	"$(awk -F': ' '/^cache: /{print $2}' "$OUT")" "1h"
run "$PY" "$S" resolve --class wiki-compile --throttle top --root "$D2" --json
eq "L38g --json exits 0" "$RC" "0"
eq "L38h --json is one parseable object carrying the same fields" \
	"$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["class"], d["model"], d["effort"], len(d["tools"]), d["cache"])' "$OUT" 2>&1)" \
	"wiki-compile fable max 6 1h"
run "$PY" "$S" resolve --root "$D2"
eq "L38i resolve without --class exits 2 rather than guessing one" "$RC" "2"

# ======================================================= 19 · v1 and v2, one script ===
mkfix v1read
run "$PY" "$S" show --root "$W/v1read"
eq "L39a the v1 record still resolves by its triple/pair rule" \
	"$(awk '$1=="wiki-compile"{print $2, $3}' "$OUT")" "opus max"
hasnot "L39b a v1 run claims no schema-2 control it did not run" "Skill and tools probes"
run "$PY" "$S" set default --root "$D2"
run "$PY" "$S" check --root "$D2"
eq "L39c the v2 fixture checks clean after set" "$RC" "0"
has "L39d and its control line names the schema-2 probes too" \
	"Skill and tools probes caught 2/2 planted definitions"
# `set` first, so the fixture's definitions hold the v1 record's own values: without it this leg
# would be reading whatever the installed record last wrote to the live definitions it copied,
# and it failed exactly that way in a simulated post-gate vault.
run "$PY" "$S" set default --root "$W/v1read"
"$PY" - "$W/v1read/.claude/skills/delegate/routing.json" <<'SCHEMA_ONE_END'
import json, sys
p = sys.argv[1]
rec = json.load(open(p))
rec["schema"] = 1          # the explicit form of what an absent key already means
json.dump(rec, open(p, "w"))
SCHEMA_ONE_END
run "$PY" "$S" check --root "$W/v1read"
eq "L39e an explicit \`schema: 1\` reads as the v1 record" "$RC" "0"
hasnot "L39f and it took the v1 path — no schema-2 control claimed" "Skill and tools probes"

# ======================================================= 20 · v2 broken premises ======
d="$W/v2prem"
mkfix v2prem "$V2"
RJ2="$d/.claude/skills/delegate/routing.json"
cp "$RJ2" "$W/rj2.keep"
run "$PY" "$S" check --root "$d"
eq "L41a control — the intact v2 fixture checks without a probe failure" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
mutate() { # $1 = which premise to break, from the pristine copy each time
	"$PY" - "$RJ2" "$W/rj2.keep" "$1" <<'MUTATE_V2_END'
import json, sys
path, keep, case = sys.argv[1], sys.argv[2], sys.argv[3]
rec = json.load(open(keep))
cls = sorted(rec["classes"])[0]
if case == "baddefault":
    rec["classes"][cls]["model"]["default"] = "haiku"      # in `order`, not in the options
elif case == "badoption":
    rec["classes"][cls]["effort"]["options"] = ["max", "turbo"]   # not in `order`
elif case == "missingfield":
    del rec["classes"][cls]["tools"]
elif case == "emptyoptions":
    rec["classes"][cls]["model"]["options"] = []
elif case == "badschema":
    rec["schema"] = 3
else:
    raise SystemExit("no such mutation: %s" % case)
json.dump(rec, open(path, "w"))
MUTATE_V2_END
}
mutate baddefault
run "$PY" "$S" check --root "$d"
eq "L41b a default outside its own options exits 2" "$RC" "2"
has "L41c it names the default and the options" "is not one of its options"
mutate badoption
run "$PY" "$S" check --root "$d"
eq "L41d an option outside \`order\` exits 2" "$RC" "2"
has "L41e it names the axis" "is not in \`order.effort\`"
mutate missingfield
run "$PY" "$S" check --root "$d"
eq "L41f a row missing a required field exits 2" "$RC" "2"
has "L41g it names the field" "is missing \`tools\`"
mutate emptyoptions
run "$PY" "$S" check --root "$d"
eq "L41h an empty options list exits 2" "$RC" "2"
has "L41i it says the list is empty" "is not a non-empty list"
mutate badschema
run "$PY" "$S" check --root "$d"
eq "L41j a schema value other than 1 or 2 exits 2" "$RC" "2"
has "L41k it names the value it will not read" "\`schema\` is 3"
cp "$W/rj2.keep" "$RJ2"
run "$PY" "$S" check --root "$d"
eq "L41l control — with the record restored the same check runs again" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
run "$PY" "$S" resolve --class no-such-class --throttle top --root "$d"
eq "L42a an unknown class exits 2" "$RC" "2"
has "L42b it lists the classes the record does hold" "PROBE FAILED: unknown class 'no-such-class'"
run "$PY" "$S" resolve --class gate-judge --throttle turbo --root "$d"
eq "L42c an unknown --throttle exits 2" "$RC" "2"
has "L42d it lists the known throttles" "unknown throttle 'turbo' passed to --throttle"

# ======================================== 21 · definitions checked against their row ==
# Two properties the record can only check under schema 2: the Skill tool stays off (a lane
# that can load a whole skill is no longer thin — levers L1, 2026-09-04), and a definition
# never claims a tool its class row does not grant. Keyed on the property, never on a
# definition's name, so the next class added is checked by the same rule.
d="$W/v2defs"
mkfix v2defs "$V2"
run "$PY" "$S" set default --root "$d"
CLS=$("$PY" -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["classes"])[0])' "$V2")
mkdef() { # $1 = the frontmatter tool line (empty for none) — written at the row's defaults
	"$PY" - "$d/.claude/agents/$CLS.md" "$V2" "$CLS" "$1" <<'MKDEF_END'
import json, sys
path, rec_path, cls, toolline = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
row = json.load(open(rec_path))["classes"][cls]
open(path, "w", encoding="utf-8").write(
    "---\nname: %s\ndescription: Routing range (admitted 2026-09-04); the active throttle "
    "sets the current values.\nmodel: %s\neffort: %s\n%s---\n\nBody text.\n"
    % (cls, row["model"]["default"], row["effort"]["default"],
       toolline + "\n" if toolline else ""))
MKDEF_END
}
mkdef "tools: Read"
run "$PY" "$S" check --root "$d"
eq "L43a control — a definition narrower than its row is clean" "$RC" "0"
hasnot "L43b no TOOLS-WIDER on the narrower definition" "TOOLS-WIDER"
mkdef "tools: Read, WebFetch"
run "$PY" "$S" check --root "$d"
eq "L43c a definition allowlisting a tool the row lacks exits 1" "$RC" "1"
has "L43d it names the file and the tool" "TOOLS-WIDER .claude/agents/$CLS.md: WebFetch"
hasnot "L43e and it does not fire the Skill finding on that plant" "SKILL-AVAILABLE"
mkdef "disallowedTools: Agent, SendMessage"
run "$PY" "$S" check --root "$d"
eq "L44a a definition leaving Skill available exits 1" "$RC" "1"
has "L44b it is named as SKILL-AVAILABLE" "SKILL-AVAILABLE .claude/agents/$CLS.md"
hasnot "L44c a denylist definition is never TOOLS-WIDER (the spawn's --tools bounds it)" "TOOLS-WIDER"
mkdef "tools: Read, Grep, Skill"
run "$PY" "$S" check --root "$d"
has "L44d an allowlist naming Skill is caught too" "SKILL-AVAILABLE .claude/agents/$CLS.md"
mkdef "disallowedTools: Agent, SendMessage, Skill"
run "$PY" "$S" check --root "$d"
eq "L44e control — the denylist form that names Skill is clean" "$RC" "0"
# The same two properties are silent under schema 1, which carries no tool list to compare.
mkfix v1defs
printf -- '---\nname: verifier\ndescription: Routing range (admitted 2026-09-04); the active throttle sets the current values.\nmodel: sonnet\neffort: max\ntools: Read, WebFetch, Skill\n---\n\nBody text.\n' >"$W/v1defs/.claude/agents/verifier.md"
run "$PY" "$S" check --root "$W/v1defs"
hasnot "L45a a schema-1 run reports no TOOLS-WIDER (no tool list in the record)" "TOOLS-WIDER"
hasnot "L45b and no SKILL-AVAILABLE" "SKILL-AVAILABLE"

# ======================================================= 22 · resolve is stdout-only ==
d="$W/v2ro"
mkfix v2ro "$V2"
run "$PY" "$S" set default --root "$d"
BEFORE=$(manifest "$d")
chmod -R a-w "$d"
run "$PY" "$S" resolve --class gate-judge --root "$d"
RC1=$RC
run "$PY" "$S" resolve --class gate-judge --root "$d" --json
RC2=$RC
chmod -R u+w "$d"
eq "L46a resolve ran on a read-only copy, plain and --json" "$RC1$RC2" "00"
eq "L46b the read-only copy is byte-identical afterwards" "$(manifest "$d")" "$BEFORE"

# ============================================ 23 · the installed record, by construction ==
# What this section may assume: nothing about the installed record's current defaults. A class
# default moves down when its gate passes, so every leg here is either pinned to something a gate
# never moves (the option sets), or read from the record and compared with disk.
LIVE_SCHEMA=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("schema", 1))' "$R")
echo "installed record: schema $LIVE_SCHEMA"
if [ "$LIVE_SCHEMA" = "1" ]; then
	run "$PY" "$S" resolve --class critic --throttle top --root "$VAULT"
	eq "L47a a schema-1 installed record refuses resolve, exit 2" "$RC" "2"
	has "L47b it says what the record cannot give it" "needs a schema-2 record"
	run "$PY" "$S" check --root "$VAULT"
	eq "L47c control — check still runs against it" \
		"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
else
	# Option sets, pinned as literals hand-derived from the design page's class table. A gate
	# moves a DEFAULT within its set; it never edits the set, so these hold across the phase-3
	# moves. An install that quietly narrowed a class is exactly what this catches.
	opts() { # $1 class -> "models|efforts"
		case "$1" in
		verifier) echo "sonnet,opus,fable|high,xhigh,max" ;;
		memory-hunter) echo "sonnet,opus|high,xhigh,max" ;;
		wiki-compile) echo "sonnet,opus,fable|medium,high,xhigh,max" ;;
		builder) echo "sonnet,opus,fable|high,xhigh,max" ;;
		critic) echo "opus,fable|xhigh,max" ;;
		planner) echo "opus,fable|high,xhigh,max" ;;
		reflector) echo "opus,fable|high,xhigh,max" ;;
		gate-judge) echo "opus|max" ;;
		*) echo "NO-PIN" ;;
		esac
	}
	cat >"$W/rowopts.py" <<'ROWOPTS_END'
import json, sys
row = json.load(open(sys.argv[1]))["classes"][sys.argv[2]]
print(",".join(row["model"]["options"]) + "|" + ",".join(row["effort"]["options"]))
ROWOPTS_END
	CLASSES=$("$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["classes"]))' "$R")
	NCLASSES=$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["classes"]))' "$R")
	optbad=""
	for c in $CLASSES; do
		got=$("$PY" "$W/rowopts.py" "$R" "$c")
		[ "$got" = "$(opts "$c")" ] || optbad="$optbad $c[$got]"
	done
	eq "L47a every installed class carries the design table's option sets ($NCLASSES classes)" "$optbad" ""
	eq "L47b control — the pin table covers every installed class" \
		"$(for c in $CLASSES; do opts "$c"; done | grep -c NO-PIN)" "0"
	run "$PY" "$S" check --root "$VAULT"
	# A red here names the drifting classes and the command that closes the drift: after an anchor
	# move in the installed record the definitions hold the old values until the owner runs
	# `throttle.py set <active throttle>` (2026-09-08). The legs' semantics are unchanged.
	ACTIVE=$(sed -n "s/.*throttle '\([a-z-]*\)'.*/\1/p" "$OUT" | head -1)
	DRIFTING=$(sed -n 's|^DRIFT \.claude/agents/\([^.]*\)\.md: .*|\1|p' "$OUT" | sort -u | tr '\n' ' ')
	CLOSE="close the drift with: python3 throttle.py set ${ACTIVE:-<active throttle>} --root <vault>"
	if [ "$RC" = "0" ]; then ok "L47c check against the installed record exits 0"
	else no "L47c check against the installed record exits 0 (rc=$RC; drifting: ${DRIFTING:-none named}; $CLOSE)"; fi
	if grep -qF -- "check: clean — $NCLASSES of $NCLASSES diffed" "$OUT"; then
		ok "L47d it reports clean, with the count it diffed"
	else
		no "L47d it reports clean, with the count it diffed (stdout lacks 'check: clean — $NCLASSES of $NCLASSES diffed'; drifting: ${DRIFTING:-none named}; $CLOSE)"
	fi
	has "L47e and its control line names the schema-2 probes it ran" \
		"Skill and tools probes caught 2/2 planted definitions"
	# Extremes: `top` and `cheap-fast` read the ends of the option sets, which no gate moves.
	run "$PY" "$S" resolve --class wiki-compile --throttle top --root "$VAULT"
	eq "L47f the installed record resolves wiki-compile under 'top'" "$(rgot)" "fable max"
	run "$PY" "$S" resolve --class wiki-compile --throttle cheap-fast --root "$VAULT"
	eq "L47g and under 'cheap-fast'" "$(rgot)" "sonnet medium"
	# Consistency: what the wrapper would spawn under the vault's own throttle is what the
	# definitions hold. Expected values are read from disk, never pinned, so a gate-driven move
	# of a carried default keeps this green once `set` has run.
	defbad=""
	for c in $CLASSES; do
		run "$PY" "$S" resolve --class "$c" --root "$VAULT"
		want="$(fmval "$VAULT/.claude/agents/$c.md" model) $(fmval "$VAULT/.claude/agents/$c.md" effort)"
		[ "$(rgot)" = "$want" ] || defbad="$defbad $c(resolved '$(rgot)' vs definition '$want')"
	done
	if [ -z "$defbad" ]; then ok "L48a resolve under the active throttle matches every definition on disk"
	else no "L48a resolve under the active throttle matches every definition on disk (drifting:$defbad; $CLOSE)"; fi
	# The gate rule: a default whose `dated` names a target is CARRIED — it sits at or above that
	# target until the gate passes, never below it, and the target is one of its own options.
	cat >"$W/carried.py" <<'CARRIED_END'
"""Carried defaults: every `target <value>` a row's `dated` names, checked against that row.
Its own positive control runs first on a synthetic line, so `carried=0` can never read as clean
when the parser has simply stopped matching."""
import json, re, sys

rec = json.load(open(sys.argv[1]))
order = rec["order"]


def targets(text):
    out = []
    for token in re.findall(r"target ([A-Za-z0-9_-]+)", text or ""):
        for axis in ("model", "effort"):
            if token in order[axis]:
                out.append((axis, token))
    return out


probe = order["effort"][0]
if targets("carried as today's value until the gate — target %s per the table" % probe) \
        != [("effort", probe)]:
    print("carried=- control=FAILED verdict=parser did not match its own control")
    raise SystemExit(2)

bad, n = [], 0
for cls, row in rec["classes"].items():
    for axis, want in targets(row.get("dated", "")):
        n += 1
        have = row[axis]["default"]
        if order[axis].index(have) < order[axis].index(want):
            bad.append("%s %s default %s below target %s" % (cls, axis, have, want))
        if want not in row[axis]["options"]:
            bad.append("%s %s target %s is not one of its options" % (cls, axis, want))
print("carried=%d control=ok verdict=%s" % (n, "; ".join(bad) if bad else "ok"))
CARRIED_END
	CARRIED=$("$PY" "$W/carried.py" "$R")
	CN=$(echo "$CARRIED" | sed -n 's/.*carried=\([0-9-]*\).*/\1/p')
	eq "L48b every carried default sits at or above the target its \`dated\` names ($CN carried)" \
		"$(echo "$CARRIED" | sed -n 's/.*verdict=//p')" "ok"
	eq "L48c control — the carried-default parser matched its own synthetic target first" \
		"$(echo "$CARRIED" | grep -c 'control=ok')" "1"
	# Control for the clean check above: the same comparison on a fixture copy of the installed
	# record and the live definitions, one field moved. The live vault is never written to.
	d="$W/livecopy"
	mkfix livecopy "$R"
	run "$PY" "$S" check --root "$d"
	eq "L49a control — a fixture copy of the installed record checks clean" "$RC" "0"
	cat >"$W/plantpick.py" <<'PLANTPICK_END'
import json, sys
rec = json.load(open(sys.argv[1]))
for cls in sorted(rec["classes"]):
    if len(rec["classes"][cls]["model"]["options"]) > 1:
        print(cls)
        break
PLANTPICK_END
	PCLS=$("$PY" "$W/plantpick.py" "$R")
	[ -n "$PCLS" ] || { echo "PROBE FAILED: no installed class has a second model option to plant"; exit 2; }
	"$PY" - "$d/.claude/agents/$PCLS.md" "$R" "$PCLS" <<'PLANT_LIVE_END'
import json, re, sys
path, rec_path, cls = sys.argv[1], sys.argv[2], sys.argv[3]
axis = json.load(open(rec_path))["classes"][cls]["model"]
other = [m for m in axis["options"] if m != axis["default"]][0]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"(?m)^model: .*$", "model: %s" % other, text, count=1))
PLANT_LIVE_END
	run "$PY" "$S" check --root "$d"
	eq "L49b a planted drift against the installed record is a finding" "$RC" "1"
	has "L49c it names the file and the field" "DRIFT .claude/agents/$PCLS.md: model"
fi

# ================================== 24 · the `auto` preset (owner ruling 2026-09-07 17:0x; 2026-09-08) ==
# Under `auto` the row defaults are ANCHORS the head picks around per call: `resolve` returns them
# labelled `anchor` beside the option lists, a hand-set preset labels its values `throttle <name>`,
# `show` says so on its header, `set auto` writes exactly what `set default` writes, a missing
# Settings line reads as `auto`, and a definition off the anchor is a drift like any other. Every
# clean claim here has its planted control on the same probe.
d="$W/auto"
mkfix auto "$V2"
run "$PY" "$S" resolve --class verifier --throttle auto --root "$d" --json
eq "L50a resolve --throttle auto --json exits 0" "$RC" "0"
eq "L50b it returns the anchors (the v2 fixture's verifier defaults) labelled anchor, with the option lists" \
	"$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["throttle"], d["model"], d["effort"], d["model_src"], d["effort_src"], ",".join(d["model_options"]), ",".join(d["effort_options"]))' "$OUT" 2>&1)" \
	"auto sonnet xhigh anchor anchor sonnet,opus,fable high,xhigh,max"
run "$PY" "$S" resolve --class verifier --throttle top --root "$d" --json
eq "L50c control — under a hand-set preset the same keys read throttle <name>" \
	"$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["model"], d["effort"], d["model_src"], d["effort_src"], len(d["model_options"]))' "$OUT" 2>&1)" \
	"fable max throttle top throttle top 3"
run "$PY" "$S" resolve --class verifier --throttle auto --root "$d"
has "L50d the text form prints model-src" "model-src: anchor"
has "L50e and effort-src" "effort-src: anchor"
has "L50f and the option lists the head picks within" "effort-options: high, xhigh, max"
run "$PY" "$S" resolve --class verifier --throttle cheap --root "$d"
has "L50g control — the text form under a hand-set preset labels the source throttle cheap" "effort-src: throttle cheap"

run "$PY" "$S" set auto --root "$d"
eq "L51a set auto exits 0" "$RC" "0"
run "$PY" "$S" show --root "$d"
eq "L51b show's first line is exactly throttle: auto (no fallback note once the line is set)" "$(head -1 "$OUT")" "throttle: auto"
eq "L51c the table header carries the anchors annotation, on one line" \
	"$(grep -c 'role .*model .*effort  (anchors: the head picks per call within the options)$' "$OUT")" "1"
eq "L51d the head line under auto" "$(grep -F 'head: ' "$OUT")" "head: fable · max"
has "L51e the check summary names the throttle auto" "match throttle 'auto'"
run "$PY" "$S" show --root "$D2"
hasnot "L51f control — under default the header carries no anchors annotation" "(anchors:"
run "$PY" "$S" set auto --root "$d"
has "L51g a second set auto has nothing to do" "nothing to do (already at 'auto')"

mkfix auto_a "$V2"
mkfix auto_b "$V2"
fmall() { for f in "$1"/.claude/agents/*.md; do printf '%s %s %s\n' "$(basename "$f")" "$(fmval "$f" model)" "$(fmval "$f" effort)"; done; }
run "$PY" "$S" set auto --root "$W/auto_a"
run "$PY" "$S" set default --root "$W/auto_b"
eq "L52a set auto writes the same model and effort values as set default (the anchors ARE the row defaults)" \
	"$(fmall "$W/auto_a")" "$(fmall "$W/auto_b")"
eq "L52b control — those values are the fixture's pinned defaults, so the equality is not vacuous" \
	"$(fmval "$W/auto_a/.claude/agents/verifier.md" model)/$(fmval "$W/auto_a/.claude/agents/verifier.md" effort)" "sonnet/xhigh"
n=$(grep -n -F -- '- **pre-report**:' "$W/auto_a/CUSTOMISATION.md" | head -1 | cut -d: -f1)
nxt=$(sed -n "$((n + 1))p" "$W/auto_a/CUSTOMISATION.md")
case "$nxt" in
'- **throttle**: auto — subagent routing throttle: auto (the default: model and effort picked per call within the class ranges, the row anchor the reference, each departure recorded with its reason) · top · default · cheap · fast · cheap-fast (hand-set overrides, never re-resolved); semantics in the delegate skill §2 (say "set throttle to X"; the head runs throttle.py set)')
	ok "L52c set auto writes the exact Settings line (auto named as the default, the others as hand-set overrides)" ;;
*) no "L52c set auto writes the exact Settings line (got '$nxt')" ;;
esac
eq "L52d the two fixtures' Settings lines differ in the name alone" \
	"$(sed -n "$((n + 1))p" "$W/auto_b/CUSTOMISATION.md" | sed 's/: default —/: auto —/')" "$nxt"
eq "L52e control — the line is under the always-on length it replaces plus the auto gloss (chars)" \
	"$(if [ "${#nxt}" -le 420 ]; then echo within; else echo "${#nxt}"; fi)" "within"

mkfix noline "$V2"
run "$PY" "$S" show --root "$W/noline"
has "L53a a fixture with no Settings line resolves as auto and says so (show)" "throttle: auto (no throttle line: treated as auto)"
run "$PY" "$S" check --root "$W/noline"
has "L53b the same note from check" "throttle: auto (no throttle line: treated as auto)"
has "L53c and check compares against the anchors" "throttle 'auto'"
run "$PY" "$S" resolve --class verifier --root "$W/noline" --json
eq "L53d resolve with neither flag nor line resolves under auto and says the line is absent" \
	"$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["throttle"], d["throttle_source"], d["model_src"])' "$OUT" 2>&1)" \
	"auto line absent anchor"
run "$PY" "$S" check --root "$W/noline" --require auto
hasnot "L53e control — --require auto against the fallback adds no REQUIRE finding" "REQUIRE"
run "$PY" "$S" check --root "$W/noline" --require default
has "L53f and --require default against it does" "REQUIRE default: the active throttle is auto"

d="$W/autodrift"
mkfix autodrift "$V2"
run "$PY" "$S" set auto --root "$d"
run "$PY" "$S" check --root "$d"
eq "L54a control — check is clean after set auto" "$RC" "0"
"$PY" - "$d/.claude/agents/verifier.md" <<'PLANT_AUTO_DRIFT_END'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read().replace("\neffort: xhigh\n", "\neffort: max\n", 1)
open(p, "w", encoding="utf-8").write(t)
PLANT_AUTO_DRIFT_END
run "$PY" "$S" check --root "$d"
eq "L54b a definition departing from the anchor under auto is a drift (planted upward: a pick the head may make per call is not a value the definition may hold)" "$RC" "1"
has "L54c it names the file, the field and the anchor" "DRIFT .claude/agents/verifier.md: effort max ≠ xhigh"

mkfix wn_target "$V2"
mkfix wn_sibling "$V2"
TGT_BEFORE=$(manifest "$W/wn_target")
SIB_BEFORE=$(manifest "$W/wn_sibling")
run "$PY" "$S" set auto --root "$W/wn_target"
eq "L55a set auto against one fixture changes nothing in a sibling fixture" "$(manifest "$W/wn_sibling")" "$SIB_BEFORE"
eq "L55b control — the target fixture did change" \
	"$(if [ "$(manifest "$W/wn_target")" = "$TGT_BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"
printf 'planted\n' >>"$W/wn_sibling/CUSTOMISATION.md"
eq "L55c control — a planted write into the sibling makes the same probe fire" \
	"$(if [ "$(manifest "$W/wn_sibling")" = "$SIB_BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"

# ================================================================== tally =============
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "PASS $PASS/$TOTAL"
	exit 0
fi
echo "FAIL $FAIL/$TOTAL"
exit 1
