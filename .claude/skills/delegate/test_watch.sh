#!/bin/sh
# test_watch.sh — the suite for watch.py.   Run:  sh <this skill directory>/test_watch.sh
#
# Every leg runs the real console against fixtures under one mktemp root: a synthetic run record
# carrying every event kind the record can hold, a synthetic hand-off pack naming its items in both
# accepted shapes, a synthetic head transcript and a synthetic lane transcript. Each guard is
# attacked as well as exercised — a planted case that must be caught beside a clean case that must
# not be — and the closing legs prove the console wrote nothing: a checksum manifest of the fixture
# record, pack and transcripts before and after every run (including one run against a read-only
# copy), plus a source sweep for write patterns and for owner paths whose own positive controls hit
# a planted fixture file. No notification is ever raised: AIMYTH_WATCH_NOTIFY=0 is exported below.
# The fixture root is removed at the end. Last line: PASS n/n, or FAIL k/n.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
WATCH="$HERE/watch.py"
if [ ! -f "$WATCH" ]; then
  printf 'PROBE FAILED: no watch.py beside this suite at %s\n' "$WATCH"
  exit 2
fi

# The locale. A bracket expression carrying a multibyte glyph — `[✓✗●]` — is a set of single
# BYTES outside a UTF-8 locale, so under `LANG` and `LC_ALL` unset every such leg read 0 rows
# and the suite was red through no fault of the console. The suite therefore fixes its own
# locale rather than the caller's shell: the first UTF-8 locale this host lists wins, and a
# host that lists none is still covered, because every multibyte class in a leg below is
# written as an alternation of whole glyphs (`(✓|✗|●)`), which matches the same byte sequences
# under any locale. Leg LC01 is the must-still-pass case: the console run with the locale
# emptied.
for _loc in C.UTF-8 en_GB.UTF-8 en_US.UTF-8; do
  if locale -a | grep -qx "$_loc"; then
    LC_ALL="$_loc"
    export LC_ALL
    break
  fi
done
unset _loc

AIMYTH_WATCH_NOTIFY=0
export AIMYTH_WATCH_NOTIFY
T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT INT TERM

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# Every leg runs the console with the store, the projects root and the vault given as fixture
# paths: nothing in watch.py may point at a real machine for these to resolve. COLUMNS and LINES
# are fixed so the rendering the assertions read is the same on every terminal.
run_watch() {
  env LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_WATCH_NOTIFY=0 \
      COLUMNS=150 LINES=60 python3 -B "$WATCH" --vault "$T/vault" "$@"
}

SYNTH_VAULT_NAME=synthetic-vault-name-for-the-grep

# ---------------------------------------------------------------- fixtures
mkdir -p "$T/store/spawn-records" "$T/handoffs" "$T/vault" "$T/projects" "$T/planted" "$T/bin"

# The planted control file: the owner-path, session-id and write-pattern sweeps must each hit it.
cat > "$T/planted/planted-strays.py" <<'PLANTED'
# A planted fixture: every sweep the ship-safety legs run must hit this file, or the sweep is
# broken and its clean result over watch.py means nothing.
VAULT = "/" + "Users/example-owner/Vaults/synthetic-vault-name-for-the-grep"   # assembled: no home-path literal in a shipped file
ALSO = "/" + "home/example-owner/synthetic-vault-name-for-the-grep/notes"
SESSION = "c4292553-3d9f-4541-80b8-acf317bfda86"


def stray_writes(path):
    with open(path, "w") as fh:
        fh.write("a write outside any report function")
    os.remove(path)
PLANTED

# The stub the `r` key runs instead of handsoff.py resume-head: it records its arguments only.
cat > "$T/bin/stub-resume.sh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_ARGS"
printf 'stub resume-head: %s\n' "$*"
STUB
chmod +x "$T/bin/stub-resume.sh"

# The pack. Both item-name shapes sit under ## Resume prompt; three decoys must not be parsed:
# one outside that section, one with no em dash, one whose index is not a number.
cat > "$T/handoffs/pack.md" <<'PACK'
# hand-off pack (synthetic fixture)

## Morning report

nothing to report: this pack is a fixture.

## Resume prompt

Continue the run in this order.
item1 N137 · build — the phase shape, a TODO and a phase
item2 N137 · verify+close — the phase shape, second
item3 N137-INSTALL — the older bare-name shape
item4 close-out — the phase shape without a TODO
item8 no-em-dash-here so this line is not an item
itemX NOT-A-NUMBER — the index is not a number

## Trace

item9 DECOY-OUTSIDE-RESUME — named outside the Resume prompt section
PACK

printf '# an empty pack (no item lines at all)\n\n## Resume prompt\n\nnothing here.\n' \
  > "$T/handoffs/empty-pack.md"

# Two pids the liveness legs need, and the fixture record needs with them, since the console
# now probes the pid of every open lane. LIVE_PID is this suite's own shell: certainly alive
# for as long as the suite runs, so a lane carrying it must still read `running`. REAPED_PID is
# a child started, exited and reaped here: certainly gone, and reaped, so nothing is waiting on
# it. Its one risk is pid recycling, and the premise guard below is the answer to it — the
# probe must already read the pid as gone before any fixture is written.
LIVE_PID=$$
sh -c 'exit 0' &
REAPED_PID=$!
wait "$REAPED_PID"
if kill -0 "$REAPED_PID" 2>"$T/reaped-probe.err"; then
  printf 'PROBE FAILED: the reaped pid %s still answers kill -0 (recycled?)\n' "$REAPED_PID"
  exit 2
fi
if ! kill -0 "$LIVE_PID" 2>"$T/live-probe.err"; then
  printf 'PROBE FAILED: this shell (pid %s) does not answer its own kill -0\n' "$LIVE_PID"
  exit 2
fi

python3 -B - "$T" "$WATCH" "$LIVE_PID" "$REAPED_PID" <<'PY_FIX'
"""Write the fixture record, the head transcript and the lane transcript.

The record carries every event kind handsoff.py and lane.py write, plus the schema kinds no
writer emits today (decision, correction, hold), with the field names copied from real records and
their values replaced by synthetic ones. Stamps are relative to now so the elapsed times, the
timeline and the states are the same on every run; the record's stamps carry the local offset (as
handsoff.py writes them) and the transcripts' stamps are UTC with a Z (as the harness writes them),
so the console's conversion is exercised.
"""
import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

T, WATCH = sys.argv[1], sys.argv[2]
# The console probes the recorded pid of every open lane, so an open fixture lane must carry a
# pid that is really alive or it renders `✗ dead`: LIVE_PID is the suite shell's own, REAPED_PID
# a child of it that has exited and been reaped.
LIVE_PID, REAPED_PID = int(sys.argv[3]), int(sys.argv[4])
spec = importlib.util.spec_from_file_location("watch_under_test", WATCH)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

t0 = time.time() - 120 * 60
PACK = os.path.join(T, "handoffs", "pack.md")
HOMES = {"B-ONE": os.path.join(T, "lane-home", "B-ONE"),
         "C-TWO": os.path.join(T, "lane-home", "C-TWO"),
         "V-THREE": os.path.join(T, "lane-home", "V-THREE")}
for home in HOMES.values():
    os.makedirs(home, exist_ok=True)
PROJECTS = os.path.join(T, "projects")
METER = ("billed (list, prices 0000-00-00): head $1.00 · lanes $2.00 · session $3.00 · "
         "rewrites 0 ($0.00)")


def ts(mins):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(t0 + mins * 60))


def utc(mins):
    return datetime.fromtimestamp(t0 + mins * 60, timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S.000Z")


def ev(mins, kind, **fields):
    payload = {"ts": ts(mins), "run": "run-vocab", "event": kind}
    payload.update(fields)
    return payload


events = [
    ev(0, "run-open", session="head-sid-1", head="seed: the fixture launcher", regime="multi",
       regime_src="head", handoff=PACK, detail="a synthetic run for the console suite",
       envelope_usd=40.0, pid=1001, pid_src="arg", on_limit="stop", on_limit_src="--on-limit",
       grants_file=os.path.join(T, "store", "spawn-records", "run-vocab-grants.json")),
    ev(1, "grants", session="head-sid-1", grants=2, writes=1, on_limit="stop",
       on_limit_src="--on-limit"),
    ev(2, "heartbeat", minutes=30, pid=1001, action="armed"),
    ev(3, "gate", item="item1", context=70000, percent=7, band=0, armed=True, decision="allow",
       metered=True, orientation_tokens=6000),
    ev(4, "lane-open", lane="B-ONE", **{"class": "builder"}, model="fable", effort="max",
       cwd=HOMES["B-ONE"], session_id="lane-sid-1", budget_usd=8.0, projects_root=PROJECTS,
       reason="(a) independence: a synthetic builder", mode="multi", deadline_s=3600,
       silence_s=900.0, silence_src="--silence-s"),
    ev(4, "lane-spawned", lane="B-ONE", session_id="lane-sid-1", pid=2001, wrapper_pid=2000,
       **{"class": "builder"}),
    ev(5, "observation", phase="build", what="a plain note that carries no alerting word",
       note="evidence: the fixture"),
    ev(6, "observation", phase="build", what="warning: the planted alert word",
       note="evidence: the fixture"),
    ev(7, "decision", phase="build", what="a schema kind no writer emits today",
       grant="none needed"),
    ev(20, "lane-closed", lane="B-ONE", exit_class="completed", total_cost_usd=1.23, num_turns=17,
       **{"class": "builder"}, duration_s=960, exit_code=0, is_error=False,
       cost_src="transcript-estimate", report_words=700, session_id="lane-sid-1"),
    ev(21, "phase-boundary", **{"from": "item1", "to": "item2"},
       disposition="the synthetic builder closed green", meter=METER,
       context="100,000 tokens (10 %)", next="item2", idle_min=1.0, denials=0,
       over_cap_reports=0, respawn_cost_usd=0.0, rewrites=0, commit="0000000",
       waste="real: none · arguable: none · avoided: none"),
    ev(22, "gate", item="item2", context=110000, percent=18, band=0, armed=True,
       decision="allow", metered=True),
    ev(23, "lane-open", lane="C-TWO", **{"class": "critic"}, model="opus", effort="max",
       cwd=HOMES["C-TWO"], session_id="lane-sid-2", budget_usd=8.0, projects_root=PROJECTS,
       reason="(a) independence: a synthetic critic"),
    ev(23, "lane-spawned", lane="C-TWO", session_id="lane-sid-2", pid=2002, wrapper_pid=2003,
       **{"class": "critic"}),
    ev(30, "stall", lane="C-TWO", silent_s=901, threshold_s=900,
       action="SIGTERM the process group"),
    ev(31, "lane-closed", lane="C-TWO", exit_class="stall", total_cost_usd=0.50, num_turns=5,
       **{"class": "critic"}, stall=True, session_id="lane-sid-2"),
    # The resumed lane is left running to the end of the fixture, so its pid must be alive or
    # the console's liveness probe would rightly draw it dead: the suite's own shell it is.
    ev(35, "lane-resumed", lane="C-TWO", session_id="lane-sid-2r", pid=LIVE_PID,
       wrapper_pid=LIVE_PID,
       **{"class": "critic"}, resume_n=1, after_limit=True, age_s=240.0, budget_usd=8.0,
       mechanism="lane.py headless, model opus, effort max"),
    ev(40, "stop-condition", which="limit", lane="head", action="wait until the reset",
       note="synthetic limit text · resets at the fixture hour", on_limit="stop",
       on_limit_src="grants"),
    ev(41, "supervisor-stood-down", reason="limit-stop", on_limit="stop", on_limit_src="grants",
       waited_s=60, note="the fixture supervisor stood down"),
    ev(42, "head-exit", band="limit", context="unmetered (fixture)", handoff=PACK, pack=True,
       spent_usd=None, pid=1001),
    ev(43, "successor-aborted", reason="resume-unsized"),
    ev(44, "head-successor", session_id="head-sid-2", pid=1002, config_dir=None, budget=30.0,
       started_after_s=0, out=os.path.join(T, "store", "spawn-records", "run-vocab-head-1.out")),
    # the wait runs from the limit stop at 40 to the resume at 75: the marks of 41-44 sit inside
    # it, and the free columns between them and the resume are the hatching the suite looks for
    ev(75, "head-resumed", session_id="head-sid-2", pid=1002, context=120000, waited_s=0,
       reset_source="resume-head (by hand, after the reset)", resume_n=1, budget=30.0),
    ev(76, "run-resume", session="head-sid-2", head="the resumed fixture head", on_limit="stop",
       on_limit_src="grants", pid=1002, pid_src="arg"),
    ev(76, "supervise", mode="launched", pid=1002, session_id="head-sid-2", supervisor_pid=1003),
    ev(77, "correction", target="a fixture claim", change="corrected", reason="the fixture"),
    ev(77, "hold", **{"class": "fixture"}, what="a held item", route="no action"),
    ev(78, "unwatched", lane="C-TWO", note="the watcher could not find the transcript"),
    ev(78, "reflect-inputs", session="head-sid-2", counts="0 rows", out="none"),
    ev(79, "phase-boundary", **{"from": "item2", "to": "item3"},
       disposition="the synthetic critic was resumed and left running", meter=METER,
       context="130,000 tokens (13 %)", next="item3", idle_min=2.0, denials=0,
       over_cap_reports=0, respawn_cost_usd=0.0, rewrites=0, commit="0000000",
       waste="real: none · arguable: none · avoided: none"),
    ev(80, "gate", item="item3", context=130000, percent=30, band=0, armed=True,
       decision="allow", metered=True),
    ev(81, "lane-open", lane="V-THREE", **{"class": "verifier"}, model="fable", effort="high",
       cwd=HOMES["V-THREE"], session_id="lane-sid-3", budget_usd=6.0, projects_root=PROJECTS,
       reason="(b) breadth: a synthetic verifier"),
    # V-THREE never closes in this fixture: the same reason as C-TWO's resume above.
    ev(81, "lane-spawned", lane="V-THREE", session_id="lane-sid-3", pid=LIVE_PID,
       wrapper_pid=LIVE_PID, **{"class": "verifier"}),
    ev(85, "observation", phase="verify", what="PROBE FAILED: a planted premise failure",
       note="evidence: the fixture"),
    ev(86, "observation", phase="verify", what="a late plain note with no alerting word in it",
       note="evidence: the fixture"),
]

records = os.path.join(T, "store", "spawn-records")


def write_jsonl(name, rows):
    with open(os.path.join(records, name), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


write_jsonl("run-vocab.jsonl", events)
# the same run, closed: the close ends the item in hand and triggers the timeline report
write_jsonl("run-vocab-closed.jsonl", [dict(e, run="run-vocab-closed") for e in events] + [
    dict(ev(90, "run-close", items="3", lanes="3", meter=METER, reason_tally="(a)x2 (b)x1",
            trace="3 rows", commit="0000000", push="ok"), run="run-vocab-closed")])
# the same run closed with every item done: item4 starts at a boundary just before the close, so
# the close ends it and the verdict reads 4/4 · all done (the green case for the close's tone)
write_jsonl("run-vocab-alldone.jsonl", [dict(e, run="run-vocab-alldone") for e in events] + [
    dict(ev(89, "phase-boundary", **{"from": "item3", "to": "item4"},
            disposition="the synthetic verifier closed green", meter=METER), run="run-vocab-alldone"),
    dict(ev(90, "run-close", items="4", lanes="3", meter=METER, reason_tally="(a)x2 (b)x1",
            trace="4 rows", commit="0000000", push="ok"), run="run-vocab-alldone")])
# the head stopped: one more stop after the last head start, so the `r` key may fire
write_jsonl("run-stopped.jsonl", [dict(e, run="run-stopped") for e in events] + [
    dict(ev(88, "stop-condition", which="limit", lane="head", action="wait until the reset",
            note="synthetic limit text"), run="run-stopped")])
# no limit wait anywhere: the negative for the hatched wait
write_jsonl("run-nowait.jsonl", [dict(e, run="run-nowait") for e in events
                                 if e["event"] not in ("stop-condition", "head-resumed")])
# a limit wait ended by a successor head with no head-resumed (2026-09-09): the wait must close
# at the successor, never run to the end of the record
write_jsonl("run-succwait.jsonl", [dict(e, run="run-succwait") for e in events
                                   if e["event"] != "head-resumed"])
# a record whose pack yields no items and which carries no gate event
write_jsonl("run-noitems.jsonl", [
    dict(ev(0, "run-open", session="head-sid-1", handoff=os.path.join(T, "handoffs",
                                                                     "empty-pack.md"),
            head="the fixture", regime="multi"), run="run-noitems"),
    dict(ev(1, "observation", phase="none", what="no gate here"), run="run-noitems")])
# The plain-lane-run shape: lane events and NO run-open, as the lane wrapper alone writes a record
# when an attended session spawns lanes. Two lanes, one completed and one error, and a third left
# open, so the close's counts by exit class have something to count.
plain_events = [
    ev(0, "lane-open", lane="P-ONE", **{"class": "builder"}, model="fable", effort="max",
       cwd=HOMES["B-ONE"], session_id="plain-sid-1", budget_usd=8.0, projects_root=PROJECTS,
       reason="(a) independence: a synthetic plain-run builder"),
    ev(0, "lane-spawned", lane="P-ONE", session_id="plain-sid-1", pid=3001, wrapper_pid=3000,
       **{"class": "builder"}),
    ev(18, "lane-closed", lane="P-ONE", exit_class="completed", total_cost_usd=2.50, num_turns=11,
       **{"class": "builder"}, duration_s=1080, exit_code=0, is_error=False,
       session_id="plain-sid-1"),
    ev(20, "lane-open", lane="P-TWO", **{"class": "critic"}, model="opus", effort="max",
       cwd=HOMES["C-TWO"], session_id="plain-sid-2", budget_usd=6.0, projects_root=PROJECTS,
       reason="(b) breadth: a synthetic plain-run critic"),
    ev(30, "lane-closed", lane="P-TWO", exit_class="error", total_cost_usd=1.25, num_turns=4,
       **{"class": "critic"}, duration_s=600, exit_code=1, is_error=True,
       session_id="plain-sid-2"),
    ev(31, "lane-open", lane="P-THREE", **{"class": "verifier"}, model="fable", effort="high",
       cwd=HOMES["V-THREE"], session_id="plain-sid-3", budget_usd=4.0, projects_root=PROJECTS,
       reason="(c) load: a synthetic plain-run verifier, still running"),
]
write_jsonl("run-plain.jsonl", [dict(e, run="run-plain") for e in plain_events])
write_jsonl("run-plain-closed.jsonl", [dict(e, run="run-plain-closed") for e in plain_events] + [
    dict(ev(40, "run-close", shape="plain-lane-run", lanes=3,
            lanes_by_exit={"completed": 1, "error": 1, "open": 1}, spend_usd=3.75,
            spend_src="sum of 2 lane-closed total_cost_usd",
            meter="none: a plain lane run names no head session to meter"),
         run="run-plain-closed")])
# The liveness shape: four open lanes, no close event on any of them, differing only in the pids
# their spawn recorded. L-DEAD carries a pid that has exited and been reaped — the lane killed by
# hand, which writes no lane-closed and which the console drew as running for ever. L-LIVE carries
# this suite's own shell. L-MIXED carries one gone pid and one live one: a wrapper that died with
# its lane still working is NOT dead. L-NOPID's spawn names no pid at all, which is an absence and
# never a death. The closed variant adds a run-close so the banner's counts by exit class can be
# read.
liveness_events = [
    ev(0, "lane-open", lane="L-DEAD", **{"class": "builder"}, model="fable", effort="max",
       cwd=HOMES["B-ONE"], session_id="live-sid-1", budget_usd=8.0, projects_root=PROJECTS,
       reason="(a) independence: the lane killed by hand"),
    ev(0, "lane-spawned", lane="L-DEAD", session_id="live-sid-1", pid=REAPED_PID,
       wrapper_pid=REAPED_PID, **{"class": "builder"}),
    ev(1, "lane-open", lane="L-LIVE", **{"class": "critic"}, model="opus", effort="max",
       cwd=HOMES["C-TWO"], session_id="live-sid-2", budget_usd=6.0, projects_root=PROJECTS,
       reason="(b) breadth: the lane still working"),
    ev(1, "lane-spawned", lane="L-LIVE", session_id="live-sid-2", pid=LIVE_PID,
       wrapper_pid=LIVE_PID, **{"class": "critic"}),
    ev(2, "lane-open", lane="L-MIXED", **{"class": "verifier"}, model="fable", effort="high",
       cwd=HOMES["V-THREE"], session_id="live-sid-3", budget_usd=4.0, projects_root=PROJECTS,
       reason="(c) load: the wrapper gone, the lane working"),
    ev(2, "lane-spawned", lane="L-MIXED", session_id="live-sid-3", pid=LIVE_PID,
       wrapper_pid=REAPED_PID, **{"class": "verifier"}),
    ev(3, "lane-open", lane="L-NOPID", **{"class": "builder"}, model="sonnet", effort="medium",
       cwd=HOMES["B-ONE"], session_id="live-sid-4", budget_usd=2.0, projects_root=PROJECTS,
       reason="(a) independence: a spawn line with no pid in it"),
    ev(3, "lane-spawned", lane="L-NOPID", session_id="live-sid-4", **{"class": "builder"}),
]
write_jsonl("run-liveness.jsonl", [dict(e, run="run-liveness") for e in liveness_events])
write_jsonl("run-liveness-closed.jsonl",
            [dict(e, run="run-liveness-closed") for e in liveness_events]
            + [dict(ev(9, "run-close", shape="plain-lane-run", lanes=4,
                       meter="none: a plain lane run names no head session to meter"),
                    run="run-liveness-closed")])
# the plain record's own broken premise: no run-open AND no lane event
write_jsonl("run-plain-empty.jsonl", [
    dict(ev(0, "observation", phase="", what="a record with neither a run-open nor a lane"),
         run="run-plain-empty")])
# gate events but no pack items: the gate item ids are the item list
write_jsonl("run-gateonly.jsonl", [
    dict(ev(0, "run-open", session="head-sid-1", handoff=os.path.join(T, "handoffs",
                                                                     "empty-pack.md"),
            head="the fixture", regime="multi"), run="run-gateonly"),
    dict(ev(3, "gate", item="item1", percent=7, decision="allow", metered=True),
         run="run-gateonly"),
    dict(ev(9, "gate", item="item2", percent=9, decision="allow", metered=True),
         run="run-gateonly")])


def assistant(mins, text=None, tool=None, target=None, model="claude-fixture"):
    content = []
    if text:
        content.append({"type": "text", "text": text})
    if tool:
        content.append({"type": "tool_use", "name": tool, "id": "toolu_fixture",
                        "input": {"command": target} if tool == "Bash" else {"file_path": target}})
    return {"type": "assistant", "timestamp": utc(mins), "sessionId": "fixture",
            "message": {"role": "assistant", "model": model, "content": content}}


def write_transcript(directory, name, rows):
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, name), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


vault_dir = os.path.join(PROJECTS, watch.dashed(os.path.join(T, "vault")))
write_transcript(vault_dir, "head-sid-1.jsonl", [
    assistant(2, text="the first head speaks"),
    assistant(3, tool="Bash", target="a fixture command from head one")])
write_transcript(vault_dir, "head-sid-2.jsonl", [
    assistant(76, text="the resumed head speaks in its own prose"),
    assistant(77, tool="Bash", target="a fixture command from the resumed head",
              model="<synthetic-model-record>"),
    assistant(78, text="the resumed head speaks again")])
write_transcript(os.path.join(PROJECTS, watch.dashed(HOMES["V-THREE"])), "lane-sid-3.jsonl", [
    assistant(82, text="the verifier lane speaks"),
    assistant(83, tool="Bash", target="the last tool call of the lane")])
print("fixtures written")
PY_FIX
[ $? -eq 0 ] || { printf 'PROBE FAILED: the fixture generator did not run\n'; exit 2; }

# The manifest of every file the console reads: it must be byte-identical at the end.
# ---------------------------------------------------------------- fixtures: the session view (A4)
# A fixture job root (AIMYTH_TASKS_ROOT) and four fixture transcripts under the fixture projects
# root. The session view reads those two observables and nothing else, so every leg below runs
# against a machine that has no harness on it. The job directory is keyed by the DASHED working
# directory the transcript itself records, so the suite computes it with the same rule the console
# does rather than spelling one.
SESS_CWD="$T/vault"
DASHED_CWD=$(python3 -B - "$SESS_CWD" <<'DASH_END'
import os, re, sys
print(re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(sys.argv[1])))
DASH_END
)
TASKS="$T/tasks-root/$DASHED_CWD"
mkdir -p "$T/projects/session-project" "$T/projects/session-project/subagents" "$T/state" \
         "$TASKS/jobs-one-aaa/tasks" "$TASKS/mtime-three-ccc/tasks"

python3 -B - "$T" "$SESS_CWD" "$T/projects/session-project" "$TASKS" <<'JOBFIX_END'
"""Build the session-view fixtures: four transcripts and their job directories.

Every job shape the harness writes is planted here, each one measured on a live transcript on
2026-09-08: a Bash call flagged `run_in_background`, a foreground Bash call that outran its
timeout and was MOVED to the background (no flag anywhere on the tool call), the Monitor tool,
and the Agent tool. The three notification carriers are planted too — a `user` record's
`message.content`, a `queue-operation` record's top-level `content`, and an `attachment`
record's `attachment.prompt` — because a live session's eleven notifications sat in all three
and reading only the user records saw one of its four notified jobs.
"""
import json, os, sys

T, CWD, PROJ, TASKS = sys.argv[1:5]
TS = "2026-09-08T01:%02d:%02d.000Z"


def rec(**kw):
    kw.setdefault("cwd", CWD)
    return json.dumps(kw)


def assistant(i, blocks):
    return rec(type="assistant", timestamp=TS % (i, 0), message={"role": "assistant", "content": blocks})


def result(i, use_id, text):
    return rec(type="user", timestamp=TS % (i, 30),
               message={"role": "user", "content": [{"type": "tool_result",
                                                     "tool_use_id": use_id, "content": text}]})


def use(use_id, name, inp):
    return {"type": "tool_use", "id": use_id, "name": name, "input": inp}


def notif(i, carrier, task_id, status):
    body = ("<task-notification>\n<task-id>%s</task-id>\n<tool-use-id>tu-x</tool-use-id>\n"
            "<status>%s</status>\n<summary>a fixture summary</summary>\n</task-notification>"
            % (task_id, status))
    if carrier == "user":
        return rec(type="user", timestamp=TS % (i, 40), message={"role": "user", "content": body})
    if carrier == "queue":
        return rec(type="queue-operation", timestamp=TS % (i, 40), content=body)
    return rec(type="attachment", timestamp=TS % (i, 40), attachment={"prompt": body})


# ---- session one: every kind, every state, every notification carrier
lines = []
jobs = [
    # (use id, tool, input, result text, job id)
    ("tu-1", "Bash", {"command": "sh /fixture/test_beta.sh", "run_in_background": True},
     "Command running in background with ID: jsuiteb. Output is being written to: /x/jsuiteb.output.",
     "jsuiteb"),
    ("tu-2", "Bash", {"command": "sh /fixture/test_alpha.sh", "run_in_background": True},
     "Command running in background with ID: jsuitea. Output is being written to: /x/jsuitea.output.",
     "jsuitea"),
    # a lane job started by the MOVED shape: no run_in_background anywhere on the tool call
    ("tu-3", "Bash", {"command": "python3 -B lane.py watch --run run-jobs --lane L1"},
     "Command did not complete within its 120s timeout and was moved to the background "
     "(ID: jlane). Output is being written to: /x/jlane.output.", "jlane"),
    ("tu-4", "Monitor", {"command": "until test -f /x/done; do sleep 5; done", "persistent": True},
     "Monitor started (task jwaiter, persistent — runs until TaskStop or session end).", "jwaiter"),
    ("tu-5", "Agent", {"description": "a fixture agent", "subagent_type": "critic",
                       "run_in_background": True, "prompt": "a fixture prompt"},
     [{"type": "text", "text": "Async agent launched successfully.\nagentId: abcdef0123456789a\n"
                               "The agent is working in the background."}], "abcdef0123456789a"),
    # an `other` command whose output file is a symlink into a subagent transcript: the file
    # decides the kind, not the command
    ("tu-6", "Bash", {"command": "python3 -c 'print(1)'", "run_in_background": True},
     "Command running in background with ID: jlink. Output is being written to: /x/jlink.output.",
     "jlink"),
    ("tu-7", "Bash", {"command": "python3 -c 'print(2)'", "run_in_background": True},
     "Command running in background with ID: jother. Output is being written to: /x/jother.output.",
     "jother"),
    ("tu-8", "Bash", {"command": "echo hi", "run_in_background": True},
     "Command running in background with ID: jlost. Output is being written to: /x/jlost.output.",
     "jlost"),
]
for i, (uid, tool, inp, text, _ident) in enumerate(jobs, start=1):
    lines.append(assistant(i, [use(uid, tool, inp)]))
    lines.append(result(i, uid, text))
# the three carriers, one each
lines.append(notif(20, "queue", "jsuiteb", "completed"))
lines.append(notif(21, "attachment", "jsuitea", "completed"))
lines.append(notif(22, "user", "jother", "failed"))
open(os.path.join(PROJ, "jobs-one-aaa.jsonl"), "w", encoding="utf-8").write("\n".join(lines) + "\n")

# ---- session two: a prefix rival for `jobs-`, and no background record at all
open(os.path.join(PROJ, "jobs-two-bbb.jsonl"), "w", encoding="utf-8").write(
    assistant(1, [{"type": "text", "text": "a turn with no tool call"}]) + "\n")

# ---- session three: a torn record after the start records — the by-mtime fallback
three = [assistant(1, [use("tu-a", "Bash", {"command": "echo one", "run_in_background": True})]),
         result(1, "tu-a", "Command running in background with ID: mrun. Output is being "
                           "written to: /x/mrun.output."),
         assistant(2, [use("tu-b", "Bash", {"command": "echo two", "run_in_background": True})]),
         result(2, "tu-b", "Command running in background with ID: mdone. Output is being "
                           "written to: /x/mdone.output."),
         '{"type":"user","timestamp":"2026-09-08T01:30:00.000Z", TORN']
open(os.path.join(PROJ, "mtime-three-ccc.jsonl"), "w", encoding="utf-8").write("\n".join(three) + "\n")

# ---- session four: the start sentence where it is NOT a start, and quoted script paths
# Every decoy here was seen live on 2026-09-08: a grep over another session's transcript put a
# phantom row on the operator's own board, and every real lane watch read `other` because the
# command quotes the script's path. The true start is the control on the same session.
four = [
    assistant(1, [use("tu-d1", "Bash", {"command": "python3 -c 'print(1)'",
                                        "run_in_background": True})]),
    result(1, "tu-d1", "Command running in background with ID: dtrue. Output is being written "
                       "to: /x/dtrue.output."),
    # a decoy in assistant prose: the sentence quoted back inside a turn
    assistant(2, [{"type": "text", "text": "The harness answered: Command running in background "
                                           "with ID: dphantom1. That was another session."}]),
    # a decoy inside another tool's output: a grep whose hits carry the sentence
    assistant(3, [use("tu-d2", "Bash", {"command": "grep -n background /x/other-session.jsonl"})]),
    result(3, "tu-d2", "---transcripts with background records---\n/x/other-session.jsonl:12: "
                       "Command running in background with ID: dphantom2. Output is being "
                       "written to: /x/dphantom2.output."),
    # a decoy with no tool_use of its own: a result whose tool_use_id resolves to nothing
    result(4, "tu-missing", "Command running in background with ID: dorphan. Output is being "
                            "written to: /x/dorphan.output."),
    # the three quoted commands: a lane watch, the run console, the console through handsoff.py
    assistant(5, [use("tu-d3", "Bash",
                      {"command": "cd /tmp && python3 -B \"/fixture/delegate/lane.py\" watch "
                                  "--run run-jobs --lane L1 --max-wait-s 570",
                       "run_in_background": True})]),
    result(5, "tu-d3", "Command running in background with ID: dqlane. Output is being written "
                       "to: /x/dqlane.output."),
    assistant(6, [use("tu-d4", "Bash",
                      {"command": "python3 -B \"/fixture/delegate/watch.py\" --run r --once",
                       "run_in_background": True})]),
    result(6, "tu-d4", "Command running in background with ID: dqwatch. Output is being written "
                       "to: /x/dqwatch.output."),
    assistant(7, [use("tu-d5", "Bash",
                      {"command": "python3 -B \"/fixture/delegate/handsoff.py\" watch --run r",
                       "run_in_background": True})]),
    result(7, "tu-d5", "Command running in background with ID: dqhandsoff. Output is being "
                       "written to: /x/dqhandsoff.output."),
]
open(os.path.join(PROJ, "decoy-four-ddd.jsonl"), "w", encoding="utf-8").write("\n".join(four) + "\n")

# ---- the lane the `jlane` job watches, and its run record
lane_lines = [assistant(i, [use("tu-l%d" % i, "Read", {"file_path": "/x/a"})]) for i in range(1, 5)]
open(os.path.join(PROJ, "lane-sess-1.jsonl"), "w", encoding="utf-8").write("\n".join(lane_lines) + "\n")
open(os.path.join(T, "store", "spawn-records", "run-jobs.jsonl"), "w", encoding="utf-8").write(
    json.dumps({"ts": "2026-09-08T01:00:00+0100", "run": "run-jobs", "event": "run-open"}) + "\n" +
    json.dumps({"ts": "2026-09-08T01:01:00+0100", "run": "run-jobs", "event": "lane-open",
                "lane": "L1", "class": "builder", "model": "fable", "effort": "max",
                "max_turns": 10, "hard_usd": 8.0, "cwd": CWD, "session_id": "lane-sess-1"}) + "\n")

# ---- the job directories
one = os.path.join(TASKS, "jobs-one-aaa", "tasks")


def out(ident, text):
    open(os.path.join(one, ident + ".output"), "w", encoding="utf-8").write(text)


out("jsuiteb", "\n".join("ok   leg %d" % i for i in range(1, 13)) + "\nPASS 12/12\n")
out("jsuitea", "ok   leg 1\nok   leg 2\nok   leg 3\n")
out("jlane", "lane watch running\n")
out("jwaiter", "waiting\n")
out("jother", "a failure line\n")
# the agent's output is a symbolic link into a subagent transcript, as the harness writes it
sub = os.path.join(PROJ, "subagents", "agent-abcdef0123456789a.jsonl")
open(sub, "w", encoding="utf-8").write('{"type":"assistant"}\n')
os.symlink(sub, os.path.join(one, "abcdef0123456789a.output"))
sub2 = os.path.join(PROJ, "subagents", "agent-jlink.jsonl")
open(sub2, "w", encoding="utf-8").write('{"type":"assistant"}\n')
os.symlink(sub2, os.path.join(one, "jlink.output"))
# the decoy: an output file with no start record anywhere in the transcript. Not a job.
out("norecord1", "a persisted capture with no start record\n")
# `jlost` deliberately has NO output file

four_dir = os.path.join(TASKS, "decoy-four-ddd", "tasks")
os.makedirs(four_dir, exist_ok=True)
for ident in ("dtrue", "dqlane", "dqwatch", "dqhandsoff"):
    open(os.path.join(four_dir, ident + ".output"), "w", encoding="utf-8").write("still writing\n")

three_dir = os.path.join(TASKS, "mtime-three-ccc", "tasks")
open(os.path.join(three_dir, "mrun.output"), "w", encoding="utf-8").write("still writing\n")
open(os.path.join(three_dir, "mdone.output"), "w", encoding="utf-8").write("finished\n")
# Both mtimes are set RELATIVE to the transcript's last parsed record, never to the clock: the
# fallback compares those two numbers, so a fixture pinned to `now` would decide differently
# depending on the hour the suite ran (it read `done` for both when the fixture stamps sat an hour
# ahead of the wall clock, 2026-09-08).
from datetime import datetime
cut = datetime.fromisoformat((TS % (2, 30)).replace("Z", "+00:00")).timestamp()
os.utime(os.path.join(three_dir, "mrun.output"), (cut + 3600, cut + 3600))
os.utime(os.path.join(three_dir, "mdone.output"), (cut - 3600, cut - 3600))
JOBFIX_END

# The session view is run with every root pointed at the fixture tree, and its state directory
# separate from $T/handoffs so the manifest legs below measure the console, not the cache.
run_jobs() {
  env LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_TASKS_ROOT="$T/tasks-root" \
      AIMYTH_STATE_DIR="$T/state" AIMYTH_WATCH_NOTIFY=0 COLUMNS=150 LINES=60 \
      python3 -B "$WATCH" --vault "$T/vault" "$@"
}

manifest() {
  find "$T/store" "$T/handoffs" "$T/projects" "$T/tasks-root" -type f -print0 | sort -z |
    xargs -0 shasum | sort
}
manifest > "$T/manifest-before.txt"

# ---------------------------------------------------------------- leg 1: item shapes
run_watch --run run-vocab --once --plain > "$T/vocab.txt" 2>"$T/vocab.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -s "$T/vocab.txt" ]; then
  ok "the console renders a snapshot of the vocabulary record (exit 0)"
else
  no "the vocabulary snapshot exited $rc: $(head -2 "$T/vocab.err")"
fi

if grep -q 'item1  *N137 · build' "$T/vocab.txt" && grep -q 'item2  *N137 · verify+close' "$T/vocab.txt" &&
   grep -q 'item4  *close-out' "$T/vocab.txt"; then
  ok "the phase shape parses (item1 N137 · build, item2 N137 · verify+close, item4 close-out)"
else
  no "the phase shape did not parse: $(grep -c 'item' "$T/vocab.txt") item lines seen"
fi

if grep -q 'item3  *N137-INSTALL' "$T/vocab.txt"; then
  ok "the older bare-name shape parses (item3 N137-INSTALL)"
else
  no "the bare-name shape did not parse"
fi

if grep -q 'DECOY-OUTSIDE-RESUME' "$T/vocab.txt" || grep -q 'NOT-A-NUMBER' "$T/vocab.txt" ||
   grep -q 'no-em-dash-here' "$T/vocab.txt"; then
  no "a planted decoy line was parsed as an item"
else
  ok "the three planted decoys (outside the section, no em dash, a non-numeric index) are refused"
fi

# ---------------------------------------------------------------- leg 2: the no-items premise
out=$(run_watch --run run-noitems --once --plain 2>&1)
rc=$?
case $out in
  *"PROBE FAILED: no items in "*"empty-pack.md and no gate events in "*"run-noitems.jsonl"*) hit=1 ;;
  *) hit=0 ;;
esac
if [ "$hit" -eq 1 ] && [ "$rc" -eq 2 ]; then
  ok "a pack with no items and a record with no gate is a premise failure (PROBE FAILED, exit 2)"
else
  no "the no-items premise gave exit $rc and: $(printf '%s' "$out" | head -1)"
fi

out=$(run_watch --run run-gateonly --once --plain 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'item1' && printf '%s' "$out" | grep -q 'item2'; then
  ok "gate events without pack items give the gate item ids (the clean case, exit 0)"
else
  no "the gate-only record gave exit $rc"
fi

# ---------------------------------------------------------------- leg 3: rows and states
if grep -qE '^\│ item1 .*done' "$T/vocab.txt" && grep -qE '^\│ item3 .*running' "$T/vocab.txt" &&
   grep -qE '^\│ item4 .*pending' "$T/vocab.txt"; then
  ok "--once --plain shows item1 done, item3 running and item4 pending"
else
  no "the item states are wrong: $(grep -E '^\│ item' "$T/vocab.txt" | tr '\n' '|')"
fi

if grep -q 'turn 3' "$T/vocab.txt"; then
  ok "the header counts the head's turns from the followed transcript (3 assistant records)"
else
  no "the head turn count is wrong: $(grep -m1 'head head-sid' "$T/vocab.txt")"
fi

if grep -q 'context 30 %' "$T/vocab.txt" && grep -q 'session \$3.00' "$T/vocab.txt"; then
  ok "the header carries the last gate's context percent and the metered spend"
else
  no "the header lacks the gate percent or the meter"
fi

if grep -qE '● V-THREE .*2 turns' "$T/vocab.txt" &&
   grep -qE '● V-THREE .*the last tool call of the lane' "$T/vocab.txt"; then
  ok "lanes now shows the running lane's live turn count and last tool call from its transcript"
else
  no "the lanes panel misses the live turns or the last call: $(grep -m1 'V-THREE' "$T/vocab.txt")"
fi

# ---------------------------------------------------------------- leg 4: a resumed lane
item2row=$(grep -E '^\│ item2 ' "$T/vocab.txt")
case $item2row in
  *"●C-TWO"*) resumed=1 ;;
  *) resumed=0 ;;
esac
case $item2row in
  *"✗C-TWO"*) stale=1 ;;
  *) stale=0 ;;
esac
if [ "$resumed" -eq 1 ] && [ "$stale" -eq 0 ]; then
  ok "a lane-resumed lane is drawn running (●), not closed (✗)"
else
  no "the resumed lane is drawn wrong: $item2row"
fi

if grep -qE '^\│ B-ONE .*✓' "$T/vocab.txt" || grep -q '✓B-ONE' "$T/vocab.txt"; then
  ok "a completed lane keeps its ✓ (the clean case beside the resumed one)"
else
  no "the completed lane lost its mark"
fi

# ---------------------------------------------------------------- leg 5: the limit wait
headrow=$(grep -E '^\│ head {3,}' "$T/vocab.txt")
case $headrow in *"░"*) wait_hit=1 ;; *) wait_hit=0 ;; esac
case $headrow in *"↻"*) res_hit=1 ;; *) res_hit=0 ;; esac
case $headrow in *"✖"*) stop_hit=1 ;; *) stop_hit=0 ;; esac
case $headrow in *"│"*) gate_hit=1 ;; *) gate_hit=0 ;; esac
case $headrow in *"▲"*) bnd_hit=1 ;; *) bnd_hit=0 ;; esac
if [ "$wait_hit" -eq 1 ] && [ "$res_hit" -eq 1 ] && [ "$stop_hit" -eq 1 ]; then
  ok "the head row draws the limit wait (░), the stop (✖) and the resume that closes it (↻)"
else
  no "the head row lacks a mark (wait=$wait_hit stop=$stop_hit resume=$res_hit): $headrow"
fi
if [ "$gate_hit" -eq 1 ] && [ "$bnd_hit" -eq 1 ]; then
  ok "the head row draws the gate (│) and the boundary (▲) marks"
else
  no "the head row lacks the gate or the boundary mark: $headrow"
fi

run_watch --run run-nowait --once --plain > "$T/nowait.txt" 2>&1
nowaitrow=$(grep -E '^\│ head {3,}' "$T/nowait.txt")
case $nowaitrow in
  *"░"*) no "a record with no limit stop still drew a wait: $nowaitrow" ;;
  *) ok "a record with no limit stop draws no wait (the negative control)" ;;
esac

# ---------------------------------------------------------------- leg 5b: a wait ended by a successor (2026-09-09)
run_watch --run run-succwait --once --plain > "$T/succwait.txt" 2>&1
succrow=$(grep -E '^\│ head {3,}' "$T/succwait.txt")
case $succrow in *"░"*) sw_wait=1 ;; *) sw_wait=0 ;; esac
case $succrow in *"↻"*) sw_res=1 ;; *) sw_res=0 ;; esac
case ${succrow##*↻} in *"░"*) sw_tail=1 ;; *) sw_tail=0 ;; esac
if [ "$sw_wait" -eq 1 ] && [ "$sw_res" -eq 1 ] && [ "$sw_tail" -eq 0 ]; then
  ok "a limit wait that ends with a successor head closes at the successor: no hatching after the last ↻"
else
  no "the wait ended by a successor runs to the end (wait=$sw_wait resume=$sw_res tail-hatch=$sw_tail): $succrow"
fi

# ---------------------------------------------------------------- leg 6: alerts
python3 -B - "$WATCH" > "$T/alerts.txt" 2>&1 <<'PY_ALERT'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("watch_under_test", sys.argv[1])
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

positives = [
    {"event": "stop-condition", "which": "limit"},
    {"event": "supervisor-stood-down", "reason": "limit-stop"},
    {"event": "successor-aborted", "reason": "resume-unsized"},
    {"event": "head-exit", "band": "limit"},
    {"event": "run-close", "lanes": "3"},
    {"event": "lane-closed", "lane": "C-TWO", "exit_class": "stall"},
    {"event": "lane-closed", "lane": "C-TWO", "exit_class": "limit"},
]
for word in ("warning: x", "a refusal here", "parked for later", "held back", "reverted the edit",
             "PROBE FAILED: x", "FAIL 3/10"):
    positives.append({"event": "observation", "what": word})
negatives = [
    {"event": "lane-closed", "lane": "B-ONE", "exit_class": "completed"},
    {"event": "observation", "what": "a plain note that carries no alerting word"},
    {"event": "gate", "item": "item1"},
    {"event": "heartbeat", "action": "beat"},
    {"event": "phase-boundary", "from": "item1", "to": "item2"},
]
missed = [e for e in positives if not watch.is_alert(e)]
wrong = [e for e in negatives if watch.is_alert(e)]
print("positives %d missed %d" % (len(positives), len(missed)))
print("negatives %d wrong %d" % (len(negatives), len(wrong)))
# the notification guard, both ways: the suite's environment refuses, and so does --no-notify
print("notify with the environment refusing: %s" % watch.notify("t", "x", True))
print("notify with --no-notify: %s" % watch.notify("t", "x", False))
if missed:
    print("MISSED", missed)
if wrong:
    print("WRONG", wrong)
PY_ALERT
if grep -q 'positives 14 missed 0' "$T/alerts.txt" && grep -q 'negatives 5 wrong 0' "$T/alerts.txt"; then
  ok "every alert kind classifies (14 positives, 0 missed) and 5 non-alerts do not (0 wrong)"
else
  no "the alert classifier is wrong: $(cat "$T/alerts.txt" | tr '\n' '|')"
fi

env LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_WATCH_COLOUR=1 \
    AIMYTH_WATCH_NOTIFY=0 COLUMNS=150 LINES=60 python3 -B "$WATCH" --vault "$T/vault" \
    --run run-vocab --once > "$T/colour.txt" 2>&1
red=$(printf '\033[38;5;196m')
if grep -F "$red" "$T/colour.txt" | grep -q 'a planted premise failure' &&
   ! grep -F "$red" "$T/colour.txt" | grep -q 'no alerting word in it'; then
  ok "the alerting observation is red in the feed and the plain one beside it is not"
else
  no "the feed colouring is wrong: $(grep -c . "$T/colour.txt") lines rendered"
fi

if grep -q 'osascript' "$T/vocab.txt" "$T/colour.txt"; then
  no "an osascript call leaked into a suite run"
else
  ok "no notification path ran in the suite (AIMYTH_WATCH_NOTIFY=0 on every leg)"
fi

if grep -q 'notify with the environment refusing: False' "$T/alerts.txt" &&
   grep -q 'notify with --no-notify: False' "$T/alerts.txt"; then
  ok "the notification is refused by AIMYTH_WATCH_NOTIFY=0 and by --no-notify (no osascript ran)"
else
  no "the notification guard did not hold: $(grep -c notify "$T/alerts.txt") lines"
fi

# ---------------------------------------------------------------- the event vocabulary
python3 -B - "$WATCH" "$T/store/spawn-records/run-vocab-closed.jsonl" > "$T/kinds.txt" 2>&1 <<'PY_VOCAB'
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("watch_under_test", sys.argv[1])
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

kinds = sorted({json.loads(line)["event"] for line in open(sys.argv[2], encoding="utf-8")
                if line.strip()})
missing = [k for k in kinds if k not in watch.TREATMENT]
print("kinds %d missing %d %s" % (len(kinds), len(missing), missing))
print("an invented kind is missing: %s" % ("not-a-real-event" not in watch.TREATMENT))
print("marked %d of them, every mark has a glyph: %s" % (
    len([k for k in kinds if k in watch.MARKS]),
    all(v in watch.MARK_GLYPH for v in watch.MARKS.values())))
PY_VOCAB
kinds=$(sed -n 's/^kinds \([0-9]*\) .*/\1/p' "$T/kinds.txt")
if grep -q ' missing 0 \[\]' "$T/kinds.txt" && [ "${kinds:-0}" -ge 20 ] &&
   grep -q 'an invented kind is missing: True' "$T/kinds.txt"; then
  ok "all $kinds event kinds in the record have a treatment; an invented kind does not (control)"
else
  no "the vocabulary table misses a kind: $(cat "$T/kinds.txt" | tr '\n' '|')"
fi
if grep -qE '^marked [0-9]+ of them, every mark has a glyph: True' "$T/kinds.txt" &&
   ! grep -q '^marked 0 ' "$T/kinds.txt"; then
  ok "$(sed -n 's/^marked \([0-9]*\) .*/\1/p' "$T/kinds.txt") kinds mark the head row and each mark has a glyph"
else
  no "the mark table is inconsistent"
fi

# ---------------------------------------------------------------- terminal size
for w in 90 200; do
  env LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_WATCH_NOTIFY=0 \
      COLUMNS=$w LINES=45 python3 -B "$WATCH" --vault "$T/vault" --run run-vocab --once --plain \
      > "$T/w$w.txt" 2>&1
done
python3 -B -c "
import sys
w90 = max(len(l.rstrip(chr(10))) for l in open(sys.argv[1], encoding='utf-8'))
w200 = max(len(l.rstrip(chr(10))) for l in open(sys.argv[2], encoding='utf-8'))
print('widest at 90: %d · widest at 200: %d' % (w90, w200))
print('within bounds: %s · adaptive: %s' % (w90 <= 90 and w200 <= 200, w90 < w200))
" "$T/w90.txt" "$T/w200.txt" > "$T/widths.txt" 2>&1
if grep -q 'within bounds: True · adaptive: True' "$T/widths.txt"; then
  ok "no line is wider than the terminal and the board follows its width ($(head -1 "$T/widths.txt"))"
else
  no "the width discipline broke: $(cat "$T/widths.txt" | tr '\n' '|')"
fi

run_watch --run run-vocab --once > "$T/notty.txt" 2>&1
if ! grep -q "$(printf '\033')" "$T/notty.txt" && grep -q 'item1' "$T/notty.txt"; then
  ok "--once with a piped stdout prints plain (no escape sequences) without --plain"
else
  no "colour leaked into a piped snapshot"
fi

# ---------------------------------------------------------------- leg 7: the keys
STUB_ARGS="$T/stub-args.txt"
: > "$STUB_ARGS"
env LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_WATCH_NOTIFY=0 \
    STUB_ARGS="$STUB_ARGS" AIMYTH_WATCH_RESUME_CMD="sh $T/bin/stub-resume.sh" \
    python3 -B - "$WATCH" "$T" > "$T/keys.txt" 2>&1 <<'PY_KEYS'
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("watch_under_test", sys.argv[1])
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)
T = sys.argv[2]
vault = os.path.join(T, "vault")
records = os.path.join(T, "store", "spawn-records")

running = watch.Run("run-vocab", os.path.join(records, "run-vocab.jsonl"), vault)
stopped = watch.Run("run-stopped", os.path.join(records, "run-stopped.jsonl"), vault)
print("running head_stopped=%s" % running.head_stopped())
print("stopped head_stopped=%s" % stopped.head_stopped())
quit_r, said = watch.handle_key("r", running)
print("refused quit=%s msg=%s" % (quit_r, " ".join(said)))
quit_r, said = watch.handle_key("r", stopped)
print("fired quit=%s msg=%s" % (quit_r, " ".join(said)))
quit_q, said = watch.handle_key("q", running)
print("quit quit=%s msg=%s" % (quit_q, " ".join(said)))
print("model from a field: %s" % watch.head_model({"event": "head-successor", "model": "fable-x"}))
os.environ.pop("AIMYTH_WATCH_RESUME_CMD", None)          # the unstubbed default, for the next line
print("command: %s" % " ".join(watch.resume_command("run-stopped", "fable")))
PY_KEYS
if grep -q 'refused quit=False msg=head is running' "$T/keys.txt" &&
   grep -q 'running head_stopped=False' "$T/keys.txt"; then
  ok "\`r\` is refused while a head runs and says so"
else
  no "\`r\` was not refused while a head runs: $(grep -m1 refused "$T/keys.txt")"
fi
if grep -q 'fired quit=False msg=resume-head: exit 0' "$T/keys.txt"; then
  ok "\`r\` runs the resume command once the last head event is a stop"
else
  no "\`r\` did not fire after a stop: $(grep -m1 fired "$T/keys.txt")"
fi
if grep -q -- '--run run-stopped --model fable --effort max' "$STUB_ARGS"; then
  ok "the stub was invoked with --run, the model and --effort max (AIMYTH_WATCH_RESUME_CMD)"
else
  no "the stub arguments are wrong: $(cat "$STUB_ARGS")"
fi
if [ "$(wc -l < "$STUB_ARGS" | tr -d ' ')" -eq 1 ]; then
  ok "the refused key ran no command (the stub was invoked exactly once)"
else
  no "the stub ran $(wc -l < "$STUB_ARGS") times, wanted 1"
fi
if grep -q 'quit quit=True' "$T/keys.txt" && grep -q 'model from a field: fable-x' "$T/keys.txt"; then
  ok "\`q\` quits and the head model comes from the record when a head event names one"
else
  no "the q key or the model rule is wrong"
fi
if grep -q 'command: .*handsoff.py resume-head --run run-stopped --model fable --effort max' "$T/keys.txt"; then
  ok "the unstubbed command line is handsoff.py resume-head beside this script"
else
  no "the default resume command is wrong: $(grep -m1 command: "$T/keys.txt")"
fi

# ---------------------------------------------------------------- leg 8: the close report
REPORT="$T/store/spawn-records/run-vocab-closed-timeline.txt"
run_watch --run run-vocab-closed --plain --refresh 0.2 < /dev/null > "$T/closed.txt" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q '■ RUN CLOSED' "$T/closed.txt"; then
  ok "a closed run prints its final board with RUN CLOSED and exits 0"
else
  no "the closed run exited $rc without a RUN CLOSED header"
fi
# the printed path is the store's real path, which under a symlinked temporary root is spelled
# differently from $T: the file name is what the assertion can compare
if grep -q 'timeline report written to .*run-vocab-closed-timeline.txt' "$T/closed.txt" &&
   [ -f "$REPORT" ]; then
  ok "the timeline report is written to the store and its path is printed"
else
  no "no timeline report at $REPORT"
fi
if [ -f "$REPORT" ] &&
   grep -q 'lane · class · model·effort · opened · closed · duration · turns · cost · exit' "$REPORT" &&
   grep -q '^B-ONE · builder · fable·max · ' "$REPORT" && grep -q '^V-THREE · verifier · fable·high · ' "$REPORT"; then
  ok "the report carries the per-lane table with a row per lane"
else
  no "the per-lane table is missing or malformed"
fi
if [ -f "$REPORT" ] && grep -q 'legend: █ item or lane' "$REPORT" && grep -q 'item1' "$REPORT" &&
   ! grep -q "$(printf '\033')" "$REPORT"; then
  ok "the report holds the board and the timeline as plain text (no escape sequences)"
else
  no "the report is not plain text or lacks the board"
fi
if [ -f "$T/store/spawn-records/run-vocab-timeline.txt" ]; then
  no "a snapshot of an open run wrote a report (it must not)"
else
  ok "an open run writes no report (the negative case)"
fi

# ---------------------------------------------------------------- leg 8b: the close's item states and notice
# the close ends every item that started and reads a never-started item as skipped, the overall
# line carries the verdict, and a boxed notice follows the final board; the open run keeps item4
# pending (the control), so the rule fires only at a close
run_watch --run run-vocab-closed --once --plain < /dev/null > "$T/closed-once.txt" 2>&1
if grep -qE '^│ item3 .*done' "$T/closed-once.txt" && grep -qE '^│ item4 .*skipped' "$T/closed-once.txt" &&
   ! grep -qE '^│ item[0-9]+ .*pending' "$T/closed-once.txt"; then
  ok "at the close the item in hand reads done and the item never started reads skipped, none pending"
else
  no "the closed run's item states are wrong: $(grep -E '^│ item' "$T/closed-once.txt" | tr '\n' ' ')"
fi
if grep -q '3/4 items done · 1 skipped ■ RUN CLOSED' "$T/closed-once.txt"; then
  ok "the overall line of a closed run counts done and skipped and carries the close mark"
else
  no "the overall line is wrong: $(grep -m1 overall "$T/closed-once.txt")"
fi
if grep -q '■ RUN CLOSED · run-vocab-closed' "$T/closed-once.txt" && grep -q 'lanes 3: ' "$T/closed-once.txt" &&
   grep -q 'timeline report: not written (--once)' "$T/closed-once.txt"; then
  ok "a closed snapshot ends with the boxed RUN CLOSED notice, its lane count and no report claim"
else
  no "the closing notice is missing from the snapshot"
fi
if grep -q '■ RUN CLOSED · run-vocab-closed' "$T/closed.txt" && grep -q 'lanes 3: ' "$T/closed.txt" &&
   ! grep -q "$(printf '\033')" "$T/closed.txt"; then
  ok "the live close prints the boxed notice after the final board, plain under --plain"
else
  no "the live close lacks the boxed notice or carries escapes"
fi
if grep -qE '^│ item4 .*pending' "$T/vocab.txt" && ! grep -q 'RUN CLOSED' "$T/vocab.txt"; then
  ok "the open run still reads item4 pending and shows no close notice (the negative case)"
else
  no "the open run reads a close it never had"
fi

# ---------------------------------------------------------------- PL: the plain-lane-run shape
# A record with lane events and no run-open (the shape lane.py alone writes). Every leg here has
# run-vocab as its control: the same console, the same fixtures, a record that HAS a run-open.
run_watch --run run-plain --once --plain > "$T/plain.txt" 2>"$T/plain.err"
plrc=$?
if [ "$plrc" -eq 0 ] && ! grep -q 'PROBE FAILED' "$T/plain.err"; then
  ok "PL01 a record with no run-open renders (exit 0, no PROBE FAILED); run-vocab is the control"
else
  no "PL01 the plain record exited $plrc: $(head -2 "$T/plain.err")"
fi
if grep -q 'plain lane run · no run-open' "$T/plain.txt"; then
  ok "PL02 the header names the shape: plain lane run · no run-open"
else
  no "PL02 the header reads: $(sed -n 2p "$T/plain.txt")"
fi
if grep -q 'plain lane run · no run-open · lanes 3 · lanes \$3.75 (2 of 3 priced)' "$T/plain.txt"; then
  ok "PL03 the header counts the lanes and sums the spend from the lanes' own costs (2 of 3 priced)"
else
  no "PL03 the header's lanes and spend read: $(sed -n 2p "$T/plain.txt")"
fi
# The mark is matched as an alternation of whole glyphs, never a bracket class: see the locale
# note at the top of this file.
if [ "$(grep -cE '^│ (✓|✗|●) P-(ONE|TWO|THREE) ' "$T/plain.txt")" = "3" ]; then
  ok "PL04 the lanes panel draws one row per lane of the plain record"
else
  no "PL04 the lanes panel drew $(grep -cE '^│ (✓|✗|●) P-' "$T/plain.txt") of 3 rows"
fi
if ! grep -q '├ items ' "$T/plain.txt" && ! grep -qE '^│ item[0-9]' "$T/plain.txt" &&
   grep -q '├ items ' "$T/vocab.txt"; then
  ok "PL05 no items panel on a plain record (the control run-vocab still draws one)"
else
  no "PL05 the plain record drew an items panel or the control drew none"
fi
if grep -q '├ timeline ' "$T/plain.txt" && grep -qE '^│ P-ONE +(█|✓)' "$T/plain.txt" &&
   ! grep -qE '^│ head +' "$T/plain.txt" && grep -qE '^│ head +' "$T/vocab.txt"; then
  ok "PL06 the timeline has the lane rows and no head row (the control has one)"
else
  no "PL06 the plain timeline is wrong: $(grep -cE '^│ head ' "$T/plain.txt") head rows"
fi
if grep -q '├ feed ' "$T/plain.txt" && grep -q 'RECORD  lane-closed P-TWO' "$T/plain.txt"; then
  ok "PL07 the feed carries the record's lane events"
else
  no "PL07 the feed is missing the plain record's lane events"
fi

# ------------------------------------------------- LV: an open lane whose processes have gone
# The console probes the recorded pid of every open lane, so a lane killed by hand — which
# writes no lane-closed at all — is drawn dead instead of running for ever. Each leg's control
# is another lane of the SAME record, rendered by the same run of the same console: only the
# pids differ between them, so a wrong verdict cannot be blamed on the fixture's shape.
run_watch --run run-liveness --once --plain > "$T/liveness.txt" 2>"$T/liveness.err"
lvrc=$?
if [ "$lvrc" -eq 0 ] && ! grep -q 'PROBE FAILED' "$T/liveness.err"; then
  ok "LV00 the liveness record renders (exit 0, no PROBE FAILED)"
else
  no "LV00 the liveness record exited $lvrc: $(head -2 "$T/liveness.err")"
fi
if [ "$(grep -cE '^│ ✗ L-DEAD .* dead · no close event' "$T/liveness.txt")" = "1" ]; then
  ok "LV01 an open lane whose recorded processes have gone is drawn ✗ dead · no close event"
else
  no "LV01 the killed lane's row reads: $(grep -E '^│ . L-DEAD ' "$T/liveness.txt" | head -1)"
fi
if [ "$(grep -cE '^│ ● L-DEAD ' "$T/liveness.txt")" = "0" ]; then
  ok "LV02 and it is not drawn ● running (the state the defect showed for ever)"
else
  no "LV02 the killed lane is still drawn running"
fi
if [ "$(grep -cE '^│ ● L-LIVE ' "$T/liveness.txt")" = "1" ]; then
  ok "LV03 the clean case: a lane whose recorded pid is this suite's own shell still reads ● running"
else
  no "LV03 the live lane's row reads: $(grep -E '^│ . L-LIVE ' "$T/liveness.txt" | head -1)"
fi
if [ "$(grep -cE '^│ ● L-MIXED ' "$T/liveness.txt")" = "1" ]; then
  ok "LV04 a lane with one gone pid and one live one still reads running (only all-gone is dead)"
else
  no "LV04 the mixed lane's row reads: $(grep -E '^│ . L-MIXED ' "$T/liveness.txt" | head -1)"
fi
if [ "$(grep -cE '^│ ● L-NOPID ' "$T/liveness.txt")" = "1" ]; then
  ok "LV05 an open lane whose spawn recorded no pid stays running (an absence is not a death)"
else
  no "LV05 the pid-less lane's row reads: $(grep -E '^│ . L-NOPID ' "$T/liveness.txt" | head -1)"
fi
run_watch --run run-liveness-closed --once --plain > "$T/liveness-closed.txt" 2>&1
if grep -q 'lanes 4: ' "$T/liveness-closed.txt" && grep -q '1 dead' "$T/liveness-closed.txt" &&
   grep -q '3 running' "$T/liveness-closed.txt"; then
  ok "LV06 the close banner counts the dead lane as dead: lanes 4, 3 running, 1 dead"
else
  no "LV06 the banner's counts read: $(grep -o 'lanes 4: .*' "$T/liveness-closed.txt" | head -1)"
fi

# LC01: the same snapshot with the locale emptied — LANG, LC_ALL and LC_CTYPE all unset, the
# shell the defect was found from. The console must render the same three lane rows, and the
# probe must still read them: both halves of the locale fix are under test here, the exported
# LC_ALL above (which `env -u` removes for this leg) and the glyph alternation in the pattern.
# The control is PL04 above: the same assertion on the same fixture under the suite's locale.
env -u LANG -u LC_ALL -u LC_CTYPE LLM_WIKI_STORE="$T/store" AIMYTH_PROJECTS_DIR="$T/projects" \
    AIMYTH_WATCH_NOTIFY=0 COLUMNS=150 LINES=60 \
    python3 -B "$WATCH" --vault "$T/vault" --run run-plain --once --plain \
    > "$T/plain-nolocale.txt" 2>"$T/plain-nolocale.err"
lcrc=$?
lcrows=$(grep -cE '^│ (✓|✗|●) P-(ONE|TWO|THREE) ' "$T/plain-nolocale.txt")
if [ "$lcrc" -eq 0 ] && [ "$lcrows" = "3" ] && ! grep -q 'PROBE FAILED' "$T/plain-nolocale.err"; then
  ok "LC01 the console renders its three lane rows with LANG, LC_ALL and LC_CTYPE unset (PL04 is the control)"
else
  no "LC01 under an emptied locale the console exited $lcrc and drew $lcrows of 3 lane rows"
fi
# LC02: the negative control for LC01's probe — the pattern is not matching everything. The
# same grep over the same file with a lane name that is not in the record must read 0.
if [ "$(grep -cE '^│ (✓|✗|●) P-(FOUR|FIVE) ' "$T/plain-nolocale.txt")" = "0" ]; then
  ok "LC02 the same glyph-alternation probe reads 0 for a lane the record does not carry"
else
  no "LC02 the glyph-alternation probe matched a lane that is not in the record"
fi
PLREPORT="$T/store/spawn-records/run-plain-closed-timeline.txt"
run_watch --run run-plain-closed --plain --refresh 0.2 < /dev/null > "$T/plain-closed.txt" 2>&1
plcrc=$?
if [ "$plcrc" -eq 0 ] && grep -q '■ RUN CLOSED · run-plain-closed' "$T/plain-closed.txt" &&
   grep -q 'lanes 3: ' "$T/plain-closed.txt"; then
  ok "PL08 a closed plain record prints the boxed notice with its lane counts and exits 0"
else
  no "PL08 the closed plain run exited $plcrc without its boxed notice"
fi
if [ -f "$PLREPORT" ] && grep -q 'timeline report written to .*run-plain-closed-timeline.txt' "$T/plain-closed.txt" &&
   grep -q '^P-ONE · builder · fable·max · ' "$PLREPORT"; then
  ok "PL09 the close writes the timeline report for a plain record too, with its per-lane table"
else
  no "PL09 no timeline report at $PLREPORT"
fi
if grep -q 'plain lane run · no run-open' "$T/plain-closed.txt" &&
   ! grep -q '0/0 items done' "$T/plain-closed.txt"; then
  ok "PL10 the close's notice says the shape rather than claiming 0/0 items done"
else
  no "PL10 the closing notice reads: $(grep -m1 'closed ' "$T/plain-closed.txt")"
fi
run_watch --run run-plain-empty --once --plain > "$T/plain-empty.txt" 2>&1
plerc=$?
if [ "$plerc" -eq 2 ] && grep -q 'PROBE FAILED' "$T/plain-empty.txt" &&
   grep -q 'no run-open, no lane-open and no lane-closed event' "$T/plain-empty.txt"; then
  ok "PL11 a record with neither a run-open nor a lane event is still a premise failure (exit 2)"
else
  no "PL11 the empty plain record exited $plerc: $(head -1 "$T/plain-empty.txt")"
fi
# PL12 would repeat leg 2 (the no-items premise on a record that HAS a run-open): that leg is the
# narrowing's own control and runs above, unchanged.

# ---------------------------------------------------------------- JB: the session view (A4)
# One row per background job of an attended session, from the transcript and the job directory.
# Each kind, each state, each notification carrier and each premise failure is a separate plant of
# the same probe, so a view that emitted one constant could not pass them all.
JB="$T/jobs-one.txt"
run_jobs --session jobs-one-aaa --once --plain > "$JB" 2>"$T/jobs-one.err"
jbrc=$?
jbrow() { grep -E "^│ $1 +$2 " "$JB"; }   # the row for kind $1 and job id $2

if [ "$jbrc" -eq 0 ] && [ -s "$JB" ]; then
  ok "JB01a the session view renders a snapshot from the transcript and the job directory (exit 0)"
else
  no "JB01a the session snapshot exited $jbrc: $(head -3 "$T/jobs-one.err")"
fi
if grep -q '^│ session jobs-one-aaa · jobs 8 ' "$JB"; then
  ok "JB01b the header names the session and counts its eight jobs"
else
  no "JB01b the header reads: $(grep -m1 '│ session' "$JB")"
fi
if grep -qE '^│ session .* · suite 2 · lane 1 · waiter 1 · agent 2 · other 2' "$JB"; then
  ok "JB01c the header counts by kind, in the fixed kind order"
else
  no "JB01c the kind counts read: $(grep -m1 '│ session' "$JB")"
fi
if grep -q '^│ state: notifications' "$JB"; then
  ok "JB01d the header names notifications as the source of the state"
else
  no "JB01d the state source reads: $(grep -m1 'state:' "$JB")"
fi

# JB02 the kinds. Each is decided by a different observable: the command for the suites, the lane
# and the waiter-by-sleep, the tool for the Monitor and Agent jobs, the file for the symlink.
if [ -n "$(jbrow suite jsuiteb)" ] && [ -n "$(jbrow suite jsuitea)" ]; then
  ok "JB02a a command naming a test_*.sh file is kind suite"
else
  no "JB02a the suite rows are missing: $(grep -c '^│ suite' "$JB") found"
fi
if [ -n "$(jbrow lane jlane)" ]; then
  ok "JB02b a lane.py watch command is kind lane — and it was started by the MOVED shape, with no run_in_background on the tool call"
else
  no "JB02b the lane row is missing (the moved-to-background start was not read)"
fi
if [ -n "$(jbrow waiter jwaiter)" ]; then
  ok "JB02c the Monitor tool is kind waiter, decided by the tool and not by its command"
else
  no "JB02c the waiter row is missing"
fi
if [ -n "$(jbrow agent abcdef0123456789a)" ]; then
  ok "JB02d the Agent tool is kind agent, its id read from the agentId line"
else
  no "JB02d the agent row is missing"
fi
if [ -n "$(jbrow agent jlink)" ]; then
  ok "JB02e a symlinked .output makes a job kind agent whatever its command said (the file decides)"
else
  no "JB02e the symlinked job did not read as an agent: $(jbrow other jlink)"
fi
if [ -n "$(jbrow other jother)" ] && [ -n "$(jbrow other jlost)" ]; then
  ok "JB02f a command matching no rule is kind other"
else
  no "JB02f the other rows are missing"
fi

# JB03 the states, one per notification carrier and one per absence
if jbrow suite jsuiteb | grep -q ' done '; then
  ok "JB03a a completed notification in a queue-operation record reads done"
else
  no "JB03a jsuiteb reads: $(jbrow suite jsuiteb)"
fi
if jbrow suite jsuitea | grep -q ' done '; then
  ok "JB03b a completed notification in an attachment record reads done (the carrier a user-record scan misses)"
else
  no "JB03b jsuitea reads: $(jbrow suite jsuitea)"
fi
if jbrow other jother | grep -q ' stopped '; then
  ok "JB03c a notified status that is not completed reads stopped (carried by a user record)"
else
  no "JB03c jother reads: $(jbrow other jother)"
fi
if jbrow waiter jwaiter | grep -q ' running '; then
  ok "JB03d no notification and an output file reads running"
else
  no "JB03d jwaiter reads: $(jbrow waiter jwaiter)"
fi
if jbrow other jlost | grep -q ' lost '; then
  ok "JB03e no notification and no output file reads lost"
else
  no "JB03e jlost reads: $(jbrow other jlost)"
fi

# JB04 the decoy: an output file with no start record is not a job
if ! grep -q 'norecord1' "$JB"; then
  ok "JB04a the .output with no start record is not a row (the no-record decoy)"
else
  no "JB04a the decoy was drawn as a job: $(grep norecord1 "$JB")"
fi
if grep -q '· 1 no record' "$JB"; then
  ok "JB04b the header counts that file as one no record, so it is reported rather than hidden"
else
  no "JB04b the no-record count is missing from the header"
fi

# JB05 the denominators
if jbrow suite jsuiteb | grep -qE '█+.* 12/12'; then
  ok "JB05a a suite whose output announced PASS 12/12 draws a bar against that total"
else
  no "JB05a jsuiteb's bar reads: $(jbrow suite jsuiteb)"
fi
if jbrow suite jsuitea | grep -q 'no denominator'; then
  ok "JB05b a suite with no announced total and nothing cached says no denominator"
else
  no "JB05b jsuitea's bar reads: $(jbrow suite jsuitea)"
fi
if jbrow lane jlane | grep -qE '█+.* 4/10 turns'; then
  ok "JB05c a lane job counts its lane's live turns against the max_turns its lane-open recorded"
else
  no "JB05c the lane bar reads: $(jbrow lane jlane)"
fi
for k in waiter:jwaiter agent:abcdef0123456789a other:jother; do
  kk=${k%%:*}; ii=${k##*:}
  if jbrow "$kk" "$ii" | grep -q 'no denominator'; then
    ok "JB05d a $kk has no observable denominator and says so"
  else
    no "JB05d the $kk row claims a denominator: $(jbrow "$kk" "$ii")"
  fi
done

# JB06 the cache: the view's one write, and the bar it buys on the next run
if [ -f "$T/state/watch-suite-totals.json" ] &&
   grep -q '"test_beta.sh": 12' "$T/state/watch-suite-totals.json"; then
  ok "JB06a the run cached test_beta.sh's total under the state directory (the view's only write)"
else
  no "JB06a the totals cache reads: $(cat "$T/state/watch-suite-totals.json" 2>&1 | tr '\n' ' ')"
fi
python3 -B - "$T/state/watch-suite-totals.json" <<'SEED_END'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["test_alpha.sh"] = 9
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), indent=1, sort_keys=True)
SEED_END
run_jobs --session jobs-one-aaa --once --plain > "$T/jobs-cached.txt" 2>&1
if grep -E '^│ suite +jsuitea ' "$T/jobs-cached.txt" | grep -qE '█+.* 3/9'; then
  ok "JB06b with a cached total the same suite draws 3/9 from its ok lines (the cache is the denominator)"
else
  no "JB06b the cached suite row reads: $(grep -E '^│ suite +jsuitea ' "$T/jobs-cached.txt")"
fi

# JB07 the by-mtime fallback: a torn record after the start records
run_jobs --session mtime-three-ccc --once --plain > "$T/jobs-mtime.txt" 2>&1
if grep -q '^│ state: by mtime' "$T/jobs-mtime.txt"; then
  ok "JB07a a record that will not parse after a start record moves the state source to by mtime"
else
  no "JB07a the state source reads: $(grep -m1 'state:' "$T/jobs-mtime.txt")"
fi
if grep -E '^│ other +mrun ' "$T/jobs-mtime.txt" | grep -q ' running ' &&
   grep -E '^│ other +mdone ' "$T/jobs-mtime.txt" | grep -q ' done '; then
  ok "JB07b under the fallback the file written since the transcript's last record reads running, the older one done"
else
  no "JB07b the by-mtime states read: $(grep -E '^│ other ' "$T/jobs-mtime.txt" | tr '\n' '|')"
fi

# JB08 the prefix resolution, exactly as fable-share.py resolves one
run_jobs --session jobs-one --once --plain > "$T/jobs-prefix.txt" 2>&1
if grep -q '^│ session jobs-one-aaa ' "$T/jobs-prefix.txt"; then
  ok "JB08a a prefix naming exactly one transcript resolves to its full stem"
else
  no "JB08a the prefix resolved to: $(grep -m1 'session' "$T/jobs-prefix.txt")"
fi
run_jobs --session jobs- --once --plain > "$T/jobs-two.txt" 2>&1
if [ $? -eq 2 ] && grep -q 'PROBE FAILED: 2 sessions match jobs-' "$T/jobs-two.txt"; then
  ok "JB08b a prefix matching two transcripts fails with the count, never a guess between them"
else
  no "JB08b the ambiguous prefix said: $(head -1 "$T/jobs-two.txt")"
fi
run_jobs --session zzznosuch --once --plain > "$T/jobs-zero.txt" 2>&1
if [ $? -eq 2 ] && grep -q 'PROBE FAILED: no transcript for zzznosuch' "$T/jobs-zero.txt"; then
  ok "JB08c a prefix matching no transcript is a premise failure with exit 2"
else
  no "JB08c the missing prefix said: $(head -1 "$T/jobs-zero.txt")"
fi

# JB09 the premise cases
run_jobs --session jobs-two-bbb --once --plain > "$T/jobs-none.txt" 2>&1
if [ $? -eq 0 ] && grep -q '^no background jobs$' "$T/jobs-none.txt"; then
  ok "JB09a a transcript with no background record is a legitimate state: no background jobs, exit 0"
else
  no "JB09a the empty session said: $(head -2 "$T/jobs-none.txt")"
fi
chmod 000 "$TASKS/jobs-one-aaa/tasks"
run_jobs --session jobs-one-aaa --once --plain > "$T/jobs-noroot.txt" 2>&1
noroot=$?
chmod 755 "$TASKS/jobs-one-aaa/tasks"
if [ "$noroot" -eq 0 ] && grep -q 'output: unreadable' "$T/jobs-noroot.txt" &&
   [ "$(grep -c 'output: unreadable' "$T/jobs-noroot.txt")" -ge 8 ]; then
  ok "JB09b an unreadable job root still draws every row from the transcript, each marked output: unreadable (exit 0)"
else
  no "JB09b the unreadable root gave exit $noroot and $(grep -c 'output: unreadable' "$T/jobs-noroot.txt") marked rows"
fi
if run_jobs --once --plain > "$T/jobs-neither.txt" 2>&1; then
  no "JB09c the console ran with neither --run nor --session"
else
  ok "JB09c --run and --session are mutually exclusive and one is required"
fi
if run_jobs --run run-vocab --session jobs-one-aaa --once --plain > "$T/jobs-both.txt" 2>&1; then
  no "JB09d the console accepted --run and --session together"
else
  ok "JB09d passing both --run and --session is refused"
fi

# JB10 the run console is untouched by the session view: an existing snapshot re-asserted after
# every session run above. The header carries a wall clock, so the assertion is leg 8b's own —
# the item rows and the absence of a close — rather than a byte comparison that time would break.
run_watch --run run-vocab --once --plain > "$T/vocab-again.txt" 2>&1
jb10rc=$?
if [ "$jb10rc" -eq 0 ] && grep -qE '^│ item4 .*pending' "$T/vocab-again.txt" &&
   ! grep -q 'RUN CLOSED' "$T/vocab-again.txt" &&
   [ "$(grep -cE '^│ item[0-9]' "$T/vocab-again.txt")" = "$(grep -cE '^│ item[0-9]' "$T/vocab.txt")" ]; then
  ok "JB10 the --run path still renders leg 8b's snapshot after every session run (same item rows, still open)"
else
  no "JB10 the run console changed: exit $jb10rc, $(grep -cE '^│ item[0-9]' "$T/vocab-again.txt") item rows"
fi

# JB11 the start rule and the quoted script paths (session four). A start is a tool_result whose
# text BEGINS with a start sentence and whose tool_use_id resolves to a tool_use of this
# transcript; the same sentence anywhere else is a mention. `dtrue` is the control on the same
# session: if the reader stopped seeing starts altogether, it would fail with the decoys.
JB4="$T/jobs-four.txt"
run_jobs --session decoy-four-ddd --once --plain > "$JB4" 2>&1
jb4rc=$?
jb4row() { grep -E "^│ $1 +$2 " "$JB4"; }
if [ "$jb4rc" -eq 0 ] && jb4row other dtrue > /dev/null; then
  ok "JB11a the control: a true start on this session is a row (exit 0)"
else
  no "JB11a the control start is missing: exit $jb4rc, $(grep -c '^│' "$JB4") rows"
fi
if ! grep -q 'dphantom1' "$JB4"; then
  ok "JB11b the start sentence inside assistant prose is not a start (no row)"
else
  no "JB11b prose put a phantom row on the board: $(grep dphantom1 "$JB4")"
fi
if ! grep -q 'dphantom2' "$JB4"; then
  ok "JB11c the start sentence inside another tool's output is not a start (the live phantom's shape)"
else
  no "JB11c another tool's output put a phantom row on the board: $(grep dphantom2 "$JB4")"
fi
if ! grep -q 'dorphan' "$JB4"; then
  ok "JB11d a result whose tool_use_id resolves to no tool_use is not a start"
else
  no "JB11d an unresolved tool_result became a row: $(grep dorphan "$JB4")"
fi
if [ "$(grep -cE '^│ (suite|lane|waiter|agent|other) +d' "$JB4")" = "4" ]; then
  ok "JB11e session four has exactly its four true starts, the three decoys counted out"
else
  no "JB11e session four drew $(grep -cE '^│ (suite|lane|waiter|agent|other) +d' "$JB4") rows, wanted 4"
fi
if jb4row lane dqlane > /dev/null; then
  ok "JB11f a lane.py command whose script path is QUOTED is kind lane"
else
  no "JB11f the quoted lane command reads: $(grep dqlane "$JB4")"
fi
if jb4row waiter dqwatch > /dev/null; then
  ok "JB11g a quoted watch.py --run command is kind waiter"
else
  no "JB11g the quoted run console reads: $(grep dqwatch "$JB4")"
fi
if jb4row waiter dqhandsoff > /dev/null; then
  ok "JB11h a quoted handsoff.py watch command is kind waiter"
else
  no "JB11h the quoted handsoff console reads: $(grep dqhandsoff "$JB4")"
fi

# ---------------------------------------------------------------- leg 8c: the close's tone
# under colour the close mark on the head row, the header's RUN CLOSED, the overall line and the
# banner take the close's tone: bold green when every item is done, bold yellow when the close
# skipped an item (the planted contrast: run-vocab-closed's item4); leg 8 holds the plain control.
# The contrast negates only the close's own spans (a mark, a RUN CLOSED), since a completed lane's
# ✓ in the lanes panel is bold green by right. Fixed-string greps: the sequences carry `[`, which a
# regex would read as a bracket expression.
G=$(printf '\033[1m\033[38;5;40m')
Y=$(printf '\033[1m\033[38;5;220m')
R0=$(printf '\033[0m')
( export AIMYTH_WATCH_COLOUR=1; run_watch --run run-vocab-alldone --once < /dev/null > "$T/alldone-colour.txt" 2>&1 )
( export AIMYTH_WATCH_COLOUR=1; run_watch --run run-vocab-closed --once < /dev/null > "$T/skipped-colour.txt" 2>&1 )
if grep -q '4/4 items done · all done' "$T/alldone-colour.txt" && grep -qF "${G}  ■ RUN CLOSED${R0}" "$T/alldone-colour.txt" &&
   grep head "$T/alldone-colour.txt" | grep -qF "${G}■${R0}" && grep -qF "${G} ■ RUN CLOSED · run-vocab-alldone" "$T/alldone-colour.txt" &&
   grep -qF "${G} 4/4 items done · all done ■ RUN CLOSED${R0}" "$T/alldone-colour.txt"; then
  ok "an all-done close paints the head row's mark, the header, the overall line and the banner bold green"
else
  no "the all-done close is not bold green throughout: $(grep -cF "$G" "$T/alldone-colour.txt") bold-green spans"
fi
if grep -qF "${Y}  ■ RUN CLOSED${R0}" "$T/skipped-colour.txt" && grep head "$T/skipped-colour.txt" | grep -qF "${Y}■${R0}" &&
   grep -qF "${Y} ■ RUN CLOSED · run-vocab-closed" "$T/skipped-colour.txt" &&
   ! grep -F "$G" "$T/skipped-colour.txt" | grep -q '■'; then
  ok "a close that skipped an item paints them bold yellow and no close span bold green (the contrast)"
else
  no "the skipped close's tone is wrong: bold green $(grep -cF "$G" "$T/skipped-colour.txt") · bold yellow $(grep -cF "$Y" "$T/skipped-colour.txt")"
fi

# ---------------------------------------------------------------- leg 8d: the title names the run's shape
if grep -q 'run console · run-plain-closed' "$T/plain-closed.txt" && grep -q 'hands-off console · run-vocab-closed' "$T/closed.txt" &&
   ! grep -q 'hands-off console · run-plain-closed' "$T/plain-closed.txt"; then
  ok "a plain lane run is titled run console, a hands-off run hands-off console (the contrast)"
else
  no "the console title does not follow the run's shape: $(grep -o '[a-z-]* console · run-[a-z-]*' "$T/plain-closed.txt" "$T/closed.txt" | sort -u | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- leg 9: derived paths
strays=$(grep -c -E '/Us''ers/|/ho''me/|/Vol''umes/|Cloud''Storage|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-' "$WATCH")
control=$(grep -c -E '/Us''ers/|/ho''me/|/Vol''umes/|Cloud''Storage|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-' "$T/planted/planted-strays.py")
if [ "$strays" -eq 0 ] && [ "$control" -gt 0 ]; then
  ok "no owner path or session id in watch.py (0 hits; the same sweep hits the planted file $control times)"
else
  no "the owner-path sweep found $strays hits in watch.py and $control in the planted control"
fi

vname=$(grep -c "$SYNTH_VAULT_NAME" "$WATCH")
vcontrol=$(grep -c "$SYNTH_VAULT_NAME" "$T/planted/planted-strays.py")
if [ "$vname" -eq 0 ] && [ "$vcontrol" -gt 0 ]; then
  ok "no vault name in watch.py (the name sweep hits the planted file $vcontrol times)"
else
  no "the vault-name sweep found $vname hits in watch.py"
fi

python3 -B - "$WATCH" "$T/planted/planted-strays.py" > "$T/literals.txt" 2>&1 <<'PY_LIT'
"""Every string literal in the file that looks like a path, minus the ones a derivation needs.
An owner path can only enter the source as such a literal, so a clean list is the ship-safe claim;
the planted file must show strays or the check proves nothing."""
import ast
import sys

ALLOWED = {"~/.llm-wiki", "~/.claude", "handsoff.py", "%s.jsonl", "spawn-records",
           "%s-timeline.txt", "watch.py",
           # the harness's job root, composed with this process's own uid in tasks_root(): a
           # system directory every account shares, never an owner path (A4, 2026-09-08)
           "/tmp"}


def path_shaped(v):
    """A literal that could be a path: it starts at a root or a home, or it is one unbroken
    token holding a separator. Prose and format strings hold spaces and are not paths."""
    if v in ALLOWED or len(v) <= 3:
        return False
    return v.startswith(("/", "~/", "./")) or ("/" in v and " " not in v and "\n" not in v)


def patterns(tree):
    """Every string literal that is an argument of `re.compile`. A regular expression holding a
    `/` (`.../tasks/...`, an alternation) is a pattern, not a path, and counting it as a stray
    would either fail this leg on correct source or push the sweep towards an allow-list long
    enough to hide a real owner path."""
    out = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if isinstance(fn, ast.Attribute) and fn.attr == "compile" and \
                isinstance(fn.value, ast.Name) and fn.value.id == "re":
            for arg in node.args:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    out.add(arg.value)
    return out


def strays(path):
    tree = ast.parse(open(path, encoding="utf-8").read())
    skip = patterns(tree)
    out = [node.value for node in ast.walk(tree)
           if isinstance(node, ast.Constant) and isinstance(node.value, str)
           and node.value not in skip and path_shaped(node.value)]
    return sorted(set(out))


for arg in sys.argv[1:]:
    found = strays(arg)
    print("%s: %d %s" % (arg.rsplit("/", 1)[-1], len(found), found[:4]))
PY_LIT
if grep -q '^watch.py: 0 ' "$T/literals.txt" &&
   grep -qE '^planted-strays.py: [1-9]' "$T/literals.txt"; then
  ok "watch.py holds no path-shaped string literal outside its derivation allow-list (control hits)"
else
  no "path literals in watch.py: $(cat "$T/literals.txt" | tr '\n' '|')"
fi

if grep -q "$T/store/spawn-records/run-vocab.jsonl" "$T/vocab.err" 2>/dev/null; then
  no "the console printed the record path as an error"
else
  ok "the store, the projects root and the vault were taken from the environment and --vault"
fi

# ---------------------------------------------------------------- leg 10: the write proof
cp -R "$T/store" "$T/ro-store"
chmod -R a-w "$T/ro-store"
robefore=$(find "$T/ro-store" -type f | wc -l | tr -d ' ')
env LLM_WIKI_STORE="$T/ro-store" AIMYTH_PROJECTS_DIR="$T/projects" AIMYTH_WATCH_NOTIFY=0 \
    COLUMNS=150 LINES=60 python3 -B "$WATCH" --vault "$T/vault" --run run-vocab --once --plain \
    > "$T/ro.txt" 2>&1
rc=$?
roafter=$(find "$T/ro-store" -type f | wc -l | tr -d ' ')
chmod -R u+w "$T/ro-store"
if [ "$rc" -eq 0 ] && [ "$robefore" -eq "$roafter" ] && [ "$robefore" -gt 0 ]; then
  ok "a snapshot against a read-only store runs (exit 0) and adds no file ($robefore before and after)"
else
  no "the read-only run exited $rc and left $roafter files, wanted $robefore"
fi

manifest > "$T/manifest-after.txt"
grep -v -- '-timeline.txt' "$T/manifest-after.txt" > "$T/manifest-after-inputs.txt"
if cmp -s "$T/manifest-before.txt" "$T/manifest-after-inputs.txt"; then
  ok "the record, the pack and both transcripts are byte-identical after every run"
else
  ok_diff=$(diff "$T/manifest-before.txt" "$T/manifest-after-inputs.txt" | head -3 | tr '\n' '|')
  no "a file the console read changed: $ok_diff"
fi
mb=$(wc -l < "$T/manifest-before.txt" | tr -d ' ')
if [ "$mb" -ge 8 ]; then
  ok "the manifest control covers $mb files (nonzero, so the comparison means something)"
else
  no "the manifest covered $mb files — it proves nothing"
fi
added=$(comm -13 "$T/manifest-before.txt" "$T/manifest-after.txt" | wc -l | tr -d ' ')
# Two closes ran: the hands-off run's and the plain lane run's, one sanctioned report each.
if [ "$added" -eq 2 ] && grep -q -- 'run-vocab-closed-timeline.txt' "$T/manifest-after.txt" &&
   grep -q -- 'run-plain-closed-timeline.txt' "$T/manifest-after.txt"; then
  ok "exactly two files appeared in the fixture store: the two closes' sanctioned timeline reports"
else
  no "$added files appeared in the store, wanted 2 (the two timeline reports)"
fi

python3 -B - "$WATCH" "$T/planted/planted-strays.py" > "$T/writes.txt" 2>&1 <<'PY_WRITE'
"""Every file-mutating call in the file, and whether it sits inside one of the console's two
sanctioned write sites: `write_report` (the close's timeline report) and `save_suite_totals` (the
session view's per-suite denominator cache). A stray is any such call anywhere else."""
import ast
import re
import sys

SANCTIONED = ("write_report", "save_suite_totals")
PATTERN = re.compile(r"""open\([^)]*["'][wax]|os\.(remove|unlink|rename|replace|mkdir|makedirs|"""
                     r"""truncate)|shutil\.(rmtree|move|copy)""")


def scan(path):
    text = open(path, encoding="utf-8").read()
    spans = []
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, ast.FunctionDef) and node.name in SANCTIONED:
            spans.append((node.lineno, node.end_lineno))
    inside = stray = 0
    for i, line in enumerate(text.splitlines(), 1):
        if PATTERN.search(line):
            if any(lo <= i <= hi for lo, hi in spans):
                inside += 1
            else:
                stray += 1
    return inside, stray


for arg in sys.argv[1:]:
    inside, stray = scan(arg)
    print("%s: inside=%d stray=%d" % (arg.rsplit("/", 1)[-1], inside, stray))
PY_WRITE
if grep -q '^watch.py: inside=4 stray=0' "$T/writes.txt" &&
   grep -qE '^planted-strays.py: inside=0 stray=[1-9]' "$T/writes.txt"; then
  ok "watch.py's only write calls are the report's two and the totals cache's two; the sweep hits the control"
else
  no "the write sweep says: $(cat "$T/writes.txt" | tr '\n' '|')"
fi

# ---------------------------------------------------------------- result
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then printf 'PASS %s/%s\n' "$pass" "$total"; else printf 'FAIL %s/%s\n' "$fail" "$total"; fi
if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
