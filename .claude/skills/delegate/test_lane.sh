#!/bin/sh
# test_lane.sh — regression suite for lane.py and lane-fence.py (delegate skill, thin lanes).
#
# Two parts. The OFFLINE part puts a stub `claude` first on PATH that records its argv, stdin,
# cwd and lane environment, writes a fixture transcript into a fixture projects root and emits
# a canned result JSON, so every wrapper behaviour is asserted without spending a penny. The
# LIVE part (--live) spawns a handful of real sonnet lanes and asserts what only a real
# harness can show: the read fence, the shell fence, the effort actually applied, the cache
# write tier, a write lane's whitelist, and the core-injection measurement.
#
# Every clean claim carries a positive control on the same probe: a planted case the same test
# must catch. Fixtures live under one mktemp -d that the suite removes; nothing outside it is
# written, and the last legs prove that with a checksum manifest and a source grep whose own
# control must hit.
#
# Run:  sh test_lane.sh                 offline only   (last line PASS n/n or FAIL k/n)
#       sh test_lane.sh --live          offline + the live sonnet legs (prints the live spend)
#       sh test_lane.sh --live-handsoff offline + two haiku probes (the allow list, the vault root)
#       sh test_lane.sh --vault DIR     run a copy of the scripts from elsewhere against DIR
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LANE="$HERE/lane.py"
FENCE="$HERE/lane-fence.py"
PY="${PYTHON:-python3}"
LIVE=0; LIVEHO=0; VAULT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --live-handsoff) LIVEHO=1 ;;
    --vault) shift; VAULT_ARG="${1:-}" ;;
    *) echo "usage: sh test_lane.sh [--live] [--live-handsoff] [--vault DIR]" >&2; exit 2 ;;
  esac
  shift
done
export PYTHONDONTWRITEBYTECODE=1

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "FAIL   — $1"; }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1  [want $3, got $2]"; fi; }

F=$(mktemp -d)
cleanup(){ chmod -R u+w "$F" >/dev/null 2>&1; rm -rf "$F"; }
trap cleanup EXIT INT TERM

# The vault: three levels up from the shipped location, or --vault DIR when the suite runs on a
# copy of the scripts elsewhere (a builder's /tmp draft); the fence is read from beside lane.py,
# else from the vault's shipped copy. CLAUDE_PROJECT_DIR points the wrapper at the same vault.
if [ -n "$VAULT_ARG" ]; then VAULT=$(cd "$VAULT_ARG" && pwd) || exit 2
else VAULT=$(cd "$HERE/../../.." && pwd); fi
export CLAUDE_PROJECT_DIR="$VAULT"
[ -f "$FENCE" ] || FENCE="$VAULT/.claude/skills/delegate/lane-fence.py"
# The shipped home's own three files, so the last leg can prove the suite left them alone.
HOME_BEFORE=$(shasum "$LANE" "$FENCE" "$0")

STORE="$F/store"
# mktemp -d hands back the unresolved /var form on this platform; the wrapper records real paths.
FR=$("$PY" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$F")
SR="$FR/store/spawn-records"
LHOME="$F/home"
PROJ="$F/projects"
BIN="$F/bin"
mkdir -p "$STORE" "$PROJ" "$BIN" "$F/granted" "$F/writable" "$F/elsewhere"
printf 'GRANTED\n' > "$F/granted/inside.txt"
printf 'ELSEWHERE\n' > "$F/elsewhere/outside.txt"

# ------------------------------------------------------------------ the stub `claude` -------
cat > "$BIN/claude" <<'STUB_SOURCE_TERMINATOR'
#!/usr/bin/env python3
"""Stub harness: records the call, writes a fixture transcript, prints a canned result."""
import json, os, re, sys, time

log = os.environ["STUB_LOG"]
os.makedirs(log, exist_ok=True)
argv = sys.argv[1:]
with open(os.path.join(log, "argv.txt"), "w") as h:
    h.write("\n".join(argv) + "\n")
with open(os.path.join(log, "cwd.txt"), "w") as h:
    h.write(os.getcwd() + "\n")
with open(os.path.join(log, "env.txt"), "w") as h:
    for key in ("LLM_WIKI_LANE", "LLM_WIKI_LANE_RUN", "LLM_WIKI_LANE_ID",
                "LLM_WIKI_LANE_GRANTS", "LLM_WIKI_LANE_WRITES", "LLM_WIKI_LANE_PROGRESS",
                "CLAUDE_CONFIG_DIR"):
        h.write("%s=%s\n" % (key, os.environ.get(key, "<unset>")))
with open(os.path.join(log, "stdin.txt"), "w") as h:
    h.write(sys.stdin.read())

sid = "no-session"
for flag in ("--session-id", "--resume"):
    if flag in argv:
        sid = argv[argv.index(flag) + 1]
delay = float(os.environ.get("STUB_SLEEP", "0"))
if delay:
    time.sleep(delay)

projects = os.environ.get("STUB_PROJECTS", "")
if projects:
    name = os.environ.get("STUB_PROJECT_DIR") or re.sub(r"[^A-Za-z0-9]", "-",
                                                        os.path.realpath(os.getcwd()))
    directory = os.path.join(projects, name)
    os.makedirs(directory, exist_ok=True)
    usage = {"input_tokens": 10, "cache_creation_input_tokens": 400,
             "cache_read_input_tokens": 5000, "output_tokens": 20,
             "cache_creation": {"ephemeral_1h_input_tokens": 400,
                                "ephemeral_5m_input_tokens": 0}}
    records = [{"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                "message": {"id": "m1", "model": "claude-sonnet-5", "role": "assistant",
                            "stop_reason": "end_turn", "usage": usage,
                            "content": [{"type": "text", "text": "stub transcript text"}]}}]
    if os.environ.get("STUB_FENCE"):
        records.append({"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result",
             "content": "lane-fence: `/nope/x` is outside the granted directories"}]}})
        records.append({"type": "attachment", "attachment": {
            "type": "hook_success", "hookName": "PreToolUse:Bash",
            "stdout": json.dumps({"hookSpecificOutput": {
                "permissionDecisionReason": "lane-fence: within grants"}})}})
    if os.environ.get("STUB_REFUSAL"):
        records.append({"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                        "message": {"id": "m2", "model": "claude-sonnet-5", "role": "assistant",
                                    "stop_reason": "refusal", "usage": usage,
                                    "content": [{"type": "text", "text": ""}]}})
    # The lane's own prose quoting the fence prefix back must NOT count as a denial.
    records.append({"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                    "message": {"id": "m3", "model": "claude-sonnet-5", "role": "assistant",
                                "stop_reason": "end_turn", "usage": usage,
                                "content": [{"type": "text",
                                             "text": "I saw lane-fence: outside the grants"}]}})
    if os.environ.get("STUB_SYNTHETIC"):
        # The limit-stop shape: a last assistant record with a synthetic model and zero usage.
        records.append({"type": "assistant", "message": {
            "id": "m9", "model": "<synthetic>", "role": "assistant", "stop_reason": None,
            "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0,
                      "cache_read_input_tokens": 0, "output_tokens": 0},
            "content": [{"type": "text", "text": "You've hit your session limit"}]}})
    with open(os.path.join(directory, sid + ".jsonl"), "w") as h:
        for record in records:
            h.write(json.dumps(record) + "\n")

# A lane that stays silent AFTER its transcript exists (STUB_SLEEP_AFTER seconds), optionally
# appending to its progress file every half second (STUB_PROGRESS) as a healthy long call does.
after = float(os.environ.get("STUB_SLEEP_AFTER", "0"))
progress = os.environ.get("LLM_WIKI_LANE_PROGRESS")
waited = 0.0
while waited < after:
    time.sleep(0.5)
    waited += 0.5
    if os.environ.get("STUB_PROGRESS") and progress:
        with open(progress, "a") as h:
            h.write("tick\n")

denials = []
if os.environ.get("STUB_DENIALS"):
    denials = [{"tool_name": "Read", "tool_input": {"file_path": "/nope/x"}}]
result = {"type": "result", "subtype": os.environ.get("STUB_SUBTYPE", "success"),
          "is_error": bool(os.environ.get("STUB_ISERROR")),
          "result": os.environ.get("STUB_REPORT", "stub report body"),
          "num_turns": 3, "total_cost_usd": 0.12, "permission_denials": denials,
          "modelUsage": {"claude-sonnet-5": {"inputTokens": 10, "outputTokens": 20}},
          "session_id": sid}
sys.stdout.write(json.dumps(result) + "\n")
sys.exit(int(os.environ.get("STUB_EXIT", "0")))
STUB_SOURCE_TERMINATOR
chmod +x "$BIN/claude"
# The viewer stub: AIMYTH_VIEWER_CMD replaces the whole console opener in handsoff.py, so no leg
# of this suite ever opens a Terminal window; the stub appends its argv to AIMYTH_VIEWER_ARGV.
cat > "$BIN/viewer-stub.sh" <<'VIEWER_STUB_END'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a" >> "$AIMYTH_VIEWER_ARGV"; done
exit 0
VIEWER_STUB_END
chmod +x "$BIN/viewer-stub.sh"

# ----------------------------------------------------------------- the fixture routing ------
"$PY" - "$F" <<'ROUTING_FIXTURE_TERMINATOR'
import json, sys
root = sys.argv[1]

def row(models, mdef, efforts, edef, grants, extras, writes, tools, skills=None, sextras=None):
    return {"model": {"options": models, "default": mdef},
            "effort": {"options": efforts, "default": edef},
            "grants": {"default": grants, "extras": extras},
            "writes": writes, "tools": tools,
            "skills": {"default": skills or [], "extras": sextras or []},
            "mcp": {"default": [], "grantable": []},
            "cache": "1h", "gate": "fixture row, not the shipped table", "dated": "2026-09-04"}

# Effort defaults: the closed-task classes (verifier, memory-hunter, wiki-compile, builder, planner)
# sit at the anchor `xhigh` since 2026-09-08 (the owner's per-call rule of 2026-09-07 17:0x: an
# anchor the head picks around, never a pin); critic and reflector keep `max`, gate-judge is fixed.
# The pick legs below lean on builder's anchor being opus·xhigh.
table = {"schema": 2,
         "order": {"model": ["haiku", "sonnet", "opus", "fable"],
                   "effort": ["low", "medium", "high", "xhigh", "max"]},
         "classes": {
    "verifier": row(["sonnet", "opus", "fable"], "sonnet", ["high", "xhigh", "max"], "xhigh",
                    ["<claim files>"], ["wiki", "raw"], [],
                    ["Read", "Grep", "Glob", "Bash"], ["lane-core"], ["markitdown"]),
    "memory-hunter": row(["sonnet", "opus"], "sonnet", ["high", "xhigh", "max"], "xhigh",
                         ["wiki"], ["raw"], ["<memory dir>"], ["Read", "Grep", "Glob"]),
    "wiki-compile": row(["sonnet", "opus", "fable"], "opus",
                        ["medium", "high", "xhigh", "max"], "xhigh",
                        ["wiki", "<assigned raw files>"], ["raw", "assets"], [],
                        ["Read", "Grep", "Glob", "Bash", "Write", "Edit"],
                        ["lane-core", "compile-core"], ["markitdown"]),
    "builder": row(["sonnet", "opus", "fable"], "opus", ["high", "xhigh", "max"], "xhigh",
                   ["<target dirs>"], ["wiki"], ["<target dirs>"],
                   ["Read", "Grep", "Glob", "Bash", "Write", "Edit"]),
    "critic": row(["opus", "fable"], "opus", ["xhigh", "max"], "max",
                  ["<artefact files>", "<contract files>"], ["wiki", "raw"], [],
                  ["Read", "Grep", "Glob", "Bash"]),
    "planner": row(["opus", "fable"], "opus", ["high", "xhigh", "max"], "xhigh",
                   ["wiki", "<batch listing>"], [], [], ["Read", "Grep", "Glob"]),
    "reflector": row(["opus", "fable"], "opus", ["high", "xhigh", "max"], "max",
                     ["<transcript>"], ["wiki"], [], ["Read", "Grep", "Glob"],
                     ["lane-core", "reflect-slice"]),
    "gate-judge": row(["opus"], "opus", ["max"], "max", ["<fixture>"], [], [],
                      ["Read", "Grep", "Glob"])}}

with open(root + "/routing-v2.json", "w") as handle:
    json.dump(table, handle, indent=1)
# Two broken tables for the premise legs.
with open(root + "/routing-v1.json", "w") as handle:
    json.dump({"order": table["order"], "roles": {}}, handle)
broken = json.loads(json.dumps(table))
del broken["classes"]["verifier"]["tools"]
with open(root + "/routing-noTools.json", "w") as handle:
    json.dump(broken, handle)
badslice = json.loads(json.dumps(table))
badslice["classes"]["reflector"]["skills"]["default"] = ["lane-core", "no-such-slice"]
with open(root + "/routing-badslice.json", "w") as handle:
    json.dump(badslice, handle)
ROUTING_FIXTURE_TERMINATOR

R="$F/routing-v2.json"
printf 'Do the thing and report.\n' > "$F/brief.md"

# A fixture vault for every offline spawn: the live .claude tree, CLAUDE.md, wiki, raw and assets
# reached through symlinks, plus its own CUSTOMISATION.md, so no leg depends on the live Settings
# line (a live `delegation: auto` would, by design, fail every flagless spawn). The wrapper
# resolves each symlinked grant to its real path, so the vault-reference legs still see the live
# vault path where a row literal names it.
mkvault(){ # $1 = vault dir, $2 = the delegation line (empty for none)
  mkdir -p "$1"
  for entry in .claude CLAUDE.md wiki raw assets; do
    [ -e "$VAULT/$entry" ] && ln -s "$VAULT/$entry" "$1/$entry"
  done
  { printf '## Settings\n- **throttle**: default\n- **breadth**: standard\n'
    [ -n "$2" ] && printf '%s\n' "$2"; } > "$1/CUSTOMISATION.md"
}
FXV="$F/vault"
mkvault "$FXV" '- **delegation**: single — the fixture regime'

# One environment for every offline wrapper call.
mkdir -p "$F/progress"
LANEV="env -u CLAUDE_CONFIG_DIR PATH=$BIN:$PATH LLM_WIKI_STORE=$STORE STUB_LOG=$F/stub STUB_PROJECTS=$PROJ CLAUDE_PROJECT_DIR=$FXV LLM_WIKI_PROGRESS_DIR=$F/progress AIMYTH_VIEWER_CMD=$BIN/viewer-stub.sh AIMYTH_VIEWER_ARGV=$F/viewer-default.argv"
# --reason is required of every spawn (register, 2026-09-07), so the helper carries one; "$@"
# comes after it, and a call site's own --reason is the one argparse keeps.
spawn(){ $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
         --projects-root "$PROJ" --reason '(a) fixture spawn' "$@"; }

echo "== offline =="

# 1–5 · init ---------------------------------------------------------------------------------
INIT1=$("$PY" "$LANE" init --home "$LHOME" 2>&1); IRC=$?
MISS=0
for f in lane-settings.json lane-fence.py contract/schema-s4.md contract/confidence-rubric.md; do
  [ -f "$LHOME/$f" ] || MISS=$((MISS + 1))
done
if [ "$IRC" = 0 ] && [ "$MISS" = 0 ]; then ok "init builds the lane home's four artefacts"
else no "init did not build the lane home  [exit $IRC, $MISS missing]"; fi

if grep -q 'lane-fence.py' "$LHOME/lane-settings.json" \
   && grep -q '"PreToolUse"' "$LHOME/lane-settings.json" \
   && ! grep -q 'mcpServers' "$LHOME/lane-settings.json"; then
  ok "lane settings carry the Bash fence hook and no MCP servers"
else no "lane settings are wrong  [$(cat "$LHOME/lane-settings.json")]"; fi

BEFORE_SLICE=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
INIT2=$("$PY" "$LANE" init --home "$LHOME" 2>&1)
AFTER_SLICE=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
KEPT=$(printf '%s' "$INIT2" | grep -c 'kept')
if [ "$BEFORE_SLICE" = "$AFTER_SLICE" ] && [ "$KEPT" -ge 4 ]; then
  ok "init is idempotent: $KEPT artefacts kept, the slice byte-identical"
else no "init is not idempotent  [kept $KEPT, slice changed: $([ "$BEFORE_SLICE" = "$AFTER_SLICE" ] && echo no || echo yes)]"; fi

# Positive control for the leg above: a drifted slice must be regenerated, not kept.
printf 'DRIFT\n' > "$LHOME/contract/schema-s4.md"
INIT3=$("$PY" "$LANE" init --home "$LHOME" 2>&1)
RESTORED=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
if printf '%s' "$INIT3" | grep -q 'regenerated .*schema-s4' && [ "$RESTORED" = "$BEFORE_SLICE" ]; then
  ok "init regenerates a drifted slice (control: the 'kept' leg above is not vacuous)"
else no "init kept a drifted slice  [$(printf '%s' "$INIT3" | grep schema-s4)]"; fi

# The same probe against a vault that carries neither the core nor the slice source: init
# must name both and still succeed, since a fresh machine has them only after a pull.
mkdir -p "$F/fakevault/wiki/developments"
cp "$VAULT/CLAUDE.md" "$F/fakevault/CLAUDE.md"
cp "$VAULT/wiki/developments/wiki-confidence-levels.md" "$F/fakevault/wiki/developments/"
INITB=$(env CLAUDE_PROJECT_DIR="$F/fakevault" "$PY" "$LANE" init --home "$F/home-bare" 2>&1)
RC=$?
if [ "$RC" = 0 ] && printf '%s' "$INITB" | grep -q 'lane-home-src' \
   && printf '%s' "$INITB" | grep -q 'lane-core.md' \
   && printf '%s' "$INIT1" | grep -q 'created .*lane-core.md'; then
  ok "init names a missing core and slice source and still succeeds (control: the real vault's init created both)"
else no "init on a vault without the core or the slices  [exit $RC: $INITB]"; fi


# 5b · the instrument-rule letter (register, 2026-09-06): a --reason carrying none of the four
#      leading forms is refused before any record line; each form spawns and is recorded.
RF=$(spawn --run run-test-rf --lane RF0 --class verifier --grant "$F/granted" \
     --record "$F/rec-rf.jsonl" --reason 'the work is long and the head is busy' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$RF" | grep -q '(a)' && printf '%s' "$RF" | grep -q 'a:' \
   && [ ! -e "$F/rec-rf.jsonl" ]; then
  ok "spawn refuses a --reason carrying no instrument-rule letter (exit 2, the four forms named, no record line)"
else no "letterless reason  [exit $RC, record: $([ -e "$F/rec-rf.jsonl" ] && echo yes || echo no): $RF]"; fi
i=0
for form in 'a: a contract requires blindness' 'b — parallel breadth' 'C - context isolation' '(d) a task longer than the head can afford'; do
  i=$((i + 1))
  spawn --run run-test-rf --lane "RF$i" --class verifier --grant "$F/granted" \
        --record "$F/rec-rf.jsonl" --reason "$form" >/dev/null 2>&1; RC=$?
  ascii=$(printf '%s' "$form" | cut -c1-2)   # the ASCII opening of each form; the record escapes the em-dash
  if [ "$RC" = 0 ] && [ "$(grep -c '"event": "lane-open"' "$F/rec-rf.jsonl")" = "$i" ] \
     && grep -q "\"lane\": \"RF$i\", \"event\": \"lane-open\"" "$F/rec-rf.jsonl" \
     && grep -q "\"reason\": \"$ascii" "$F/rec-rf.jsonl"; then
    ok "spawn accepts the reason form '${ascii}...' and records it on lane-open"
  else no "reason form '$form'  [exit $RC, lane-open lines $(grep -c '"event": "lane-open"' "$F/rec-rf.jsonl" 2>&1)]"; fi
done

# 5c · --reason is required (register, 2026-09-07): an omitted flag and a whitespace-only one
#      take the same refusal as a letterless one — exit 2, the same message naming the four
#      forms, and no record line — and --dry-run refuses the same way. The lettered spawn below
#      is the positive control: the same command differing only in the flag runs to a close.
reqfail(){ # $1 = leg name, then the spawn's own flags
  NAME="$1"; shift
  rm -f "$F/rec-rq.jsonl"
  RQ=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
       --projects-root "$PROJ" --run run-test-rq --lane RQ --class verifier \
       --grant "$F/granted" --record "$F/rec-rq.jsonl" "$@" 2>&1); RC=$?
  if [ "$RC" = 2 ] && printf '%s' "$RQ" | grep -q 'carries no instrument-rule letter' \
     && printf '%s' "$RQ" | grep -q '(a)' && printf '%s' "$RQ" | grep -q 'a:' \
     && [ ! -e "$F/rec-rq.jsonl" ]; then
    ok "$NAME (exit 2, the four forms named, no record line)"
  else no "$NAME  [exit $RC, record $([ -e "$F/rec-rq.jsonl" ] && echo written || echo absent): $RQ]"; fi
}
reqfail "spawn refuses an omitted --reason as it refuses a letterless one"
reqfail "spawn refuses a whitespace-only --reason" --reason '   '
reqfail "spawn --dry-run refuses an omitted --reason before it prints anything" --dry-run
rm -f "$F/rec-rq.jsonl"
RQOK=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
       --projects-root "$PROJ" --run run-test-rq --lane RQ --class verifier \
       --grant "$F/granted" --record "$F/rec-rq.jsonl" --reason '(b) parallel breadth' 2>&1); RC=$?
RQREC=$("$PY" - "$F/rec-rq.jsonl" <<'REQ_CONTROL_TERMINATOR'
import json, sys
opens = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
opens = [r for r in opens if r.get("event") == "lane-open"]
print("%d %s" % (len(opens), json.dumps(opens[-1].get("reason") if opens else None)))
REQ_CONTROL_TERMINATOR
)
if [ "$RC" = 0 ] && [ "$RQREC" = '1 "(b) parallel breadth"' ]; then
  ok "control: the same spawn with a lettered --reason runs and records it on lane-open (the three refusals above are not vacuous)"
else no "the lettered control spawn  [exit $RC, record $RQREC: $(printf '%s' "$RQOK" | head -2 | tr '\n' ' ')]"; fi

# 6 · the record exists even when the process fails ------------------------------------------
env STUB_EXIT=9 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-a --lane L1 --class verifier \
  --grant "$F/granted" --record "$F/rec-a.jsonl" --reason '(a) leg 6' >/dev/null 2>&1
RC=$?
OPENS=$(grep -c '"event": "lane-open"' "$F/rec-a.jsonl" 2>/dev/null || echo 0)
if [ "$OPENS" = 1 ] && [ "$RC" = 3 ]; then
  ok "the lane-open record is written before the process starts (stub exit 9 -> wrapper exit 3)"
else no "record-before-spawn  [opens $OPENS, exit $RC]"; fi

# 7–11 · the composed call --------------------------------------------------------------------
spawn --run run-test-b --lane L2 --class verifier --grant "$F/granted" \
      --record "$F/rec-b.jsonl" --reason '(a) leg 7' >/dev/null 2>&1
A="$F/stub/argv.txt"
MISSING=""
for flag in -p --agents --agent --model --effort --restricted --tools --settings \
            --strict-mcp-config --session-id --max-budget-usd --permission-prompts \
            --output-format --add-dir; do
  grep -qx -- "$flag" "$A" || MISSING="$MISSING $flag"
done
if [ -z "$MISSING" ]; then ok "every required flag is on the command line"
else no "flags missing: $MISSING"; fi

if grep -qx -- '--mcp-config' "$A"; then no "--mcp-config appears without a grant"
else ok "--mcp-config is absent unless granted"; fi
if grep -qx -- '--permission-mode' "$A"; then no "acceptEdits on a read-only lane"
else ok "no --permission-mode on a read-only lane"; fi

E="$F/stub/env.txt"
if grep -q "^LLM_WIKI_LANE=1$" "$E" && grep -q "^LLM_WIKI_LANE_RUN=run-test-b$" "$E" \
   && grep -q "LLM_WIKI_LANE_GRANTS=.*$F/granted" "$E" && grep -q "LLM_WIKI_LANE_GRANTS=.*:/tmp" "$E" \
   && grep -q "^LLM_WIKI_LANE_WRITES=$" "$E"; then
  ok "the spawn environment carries the grants, the home, /tmp and an empty write set"
else no "spawn environment wrong  [$(cat "$E")]"; fi

DEF=$("$PY" - "$A" <<'DEFJSON_TERMINATOR'
import json, sys
argv = open(sys.argv[1]).read().split("\n")
blob = json.loads(argv[argv.index("--agents") + 1])
agent = blob["verifier"]
print(json.dumps({"keys": sorted(agent), "tools": agent["tools"],
                  "skills": agent.get("skills"), "body": agent["prompt"][:40]}))
DEFJSON_TERMINATOR
)
if printf '%s' "$DEF" | grep -q '"effort"'; then no "the thin definition still carries effort"
else ok "the thin definition carries no effort field (it is a spawn flag, not a definition field)"; fi
if printf '%s' "$DEF" | grep -q '"skills": null' && printf '%s' "$DEF" | grep -q 'Read'; then
  ok "the thin definition carries the row's tools and never a skills key (measured not to load)"
else no "thin definition wrong  [$DEF]"; fi

# The same probe must see a skills list when the class has one: the control for the leg above.
spawn --run run-test-c --lane L3 --class wiki-compile --grant "$F/granted" \
      --write "$F/writable" --record "$F/rec-c.jsonl" --reason '(a) leg 11 control' >/dev/null 2>&1
DEF2=$("$PY" - "$A" <<'DEFJSON2_TERMINATOR'
import json, sys
argv = open(sys.argv[1]).read().split("\n")
blob = json.loads(argv[argv.index("--agents") + 1])
print(json.dumps(blob["wiki-compile"].get("skills")))
DEFJSON2_TERMINATOR
)
eq "a class WITH default slices still gets no skills key in its definition" "$DEF2" "null"
if grep -qx -- '--permission-mode' "$A" && grep -qx -- 'acceptEdits' "$A"; then
  ok "acceptEdits is set for a write lane (control for the read-only leg above)"
else no "a write lane did not get acceptEdits"; fi
if grep -q "LLM_WIKI_LANE_WRITES=.*$F/writable" "$E"; then
  ok "the write set reaches the lane environment"
else no "write set missing from the environment  [$(grep WRITES "$E")]"; fi

# the appended system-prompt file: the single carrier of the core and the row's slices --------
CORESRC="$VAULT/.claude/skills/delegate/templates/lane-core.md"
appended(){ cat "$STORE/spawn-records/$1-appended-$2.md" 2>/dev/null; }
headings(){ appended "$1" "$2" | grep -c '^## Lane slice: '; }

spawn --run run-test-ap1 --lane A1 --class verifier --grant "$F/granted" \
      --record "$F/rec-ap1.jsonl" --reason '(a) appended: core only' >/dev/null 2>&1
if [ "$(headings run-test-ap1 A1)" = 1 ] \
   && appended run-test-ap1 A1 | grep -q '^## Lane slice: lane-core — source: '; then
  ok "a class with no slice beyond the core appends the core alone, under its named heading"
else no "verifier appended file  [$(appended run-test-ap1 A1 | grep '^## Lane slice')]"; fi

spawn --run run-test-ap2 --lane A2 --class wiki-compile --grant "$F/granted" \
      --record "$F/rec-ap2.jsonl" --reason '(a) appended: core + compile-core' >/dev/null 2>&1
CORE_MARK=$(head -1 "$CORESRC")
if appended run-test-ap2 A2 | grep -q '^## Lane slice: compile-core — source: .*lane-home-src/compile-core/SKILL.md' \
   && appended run-test-ap2 A2 | grep -qF "$CORE_MARK" \
   && [ "$(headings run-test-ap2 A2)" = 2 ]; then
  ok "a compile spawn appends the core's own text plus compile-core, each under its source heading"
else no "compile appended file  [$(appended run-test-ap2 A2 | grep '^## Lane slice')]"; fi

APREC=$("$PY" - "$F/rec-ap2.jsonl" "$STORE/spawn-records/run-test-ap2-appended-A2.md" <<'APPENDED_TERMINATOR'
import json, os, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        print(json.dumps({"appended": record["appended"],
                          "matches": record["appended_bytes"] == os.path.getsize(sys.argv[2])}))
APPENDED_TERMINATOR
)
eq "the lane-open record names what was appended and its byte size" \
   "$APREC" '{"appended": ["lane-core", "compile-core"], "matches": true}'

spawn --run run-test-ap3 --lane A3 --class reflector --grant "$F/granted" \
      --record "$F/rec-ap3.jsonl" --reason '(a) appended: core + reflect-slice' >/dev/null 2>&1
if appended run-test-ap3 A3 | grep -q '^## Lane slice: reflect-slice — source: ' \
   && [ "$(headings run-test-ap3 A3)" = 2 ]; then
  ok "a reflector spawn appends reflect-slice beside the core"
else no "reflector appended file  [$(appended run-test-ap3 A3 | grep '^## Lane slice')]"; fi

if grep -qx -- '--append-system-prompt-file' "$A" \
   && grep -qx -- "$SR/run-test-ap3-appended-A3.md" "$A"; then
  ok "the appended file is the one passed with --append-system-prompt-file"
else no "the appended file was not passed to the harness"; fi

spawn --run run-test-ap4 --lane A4 --class wiki-compile --grant "$F/granted" --no-core \
      --record "$F/rec-ap4.jsonl" --reason '(a) appended: --no-core' >/dev/null 2>&1
if [ "$(headings run-test-ap4 A4)" = 1 ] \
   && appended run-test-ap4 A4 | grep -q '^## Lane slice: compile-core' \
   && ! appended run-test-ap4 A4 | grep -q '^## Lane slice: lane-core'; then
  ok "--no-core drops the core and keeps the slices (control: the two-heading leg above)"
else no "--no-core  [$(appended run-test-ap4 A4 | grep '^## Lane slice')]"; fi

# 12–16 · outputs and the close line ----------------------------------------------------------
if [ -s "$STORE/spawn-records/run-test-b-definition-L2.md" ] \
   && grep -q 'verifier' "$STORE/spawn-records/run-test-b-definition-L2.md"; then
  ok "the thin definition copy is saved beside the record"
else no "no definition copy saved"; fi

if [ "$(cat "$STORE/spawn-records/run-test-b-report-L2.md")" = "stub report body" ]; then
  ok "the report is persisted from the result JSON"
else no "report not persisted  [$(cat "$STORE/spawn-records/run-test-b-report-L2.md" 2>&1)]"; fi

BRIEFED=$(cat "$F/stub/stdin.txt")
eq "the brief is delivered on stdin" "$BRIEFED" "$(cat "$F/brief.md")"

env STUB_FENCE=1 STUB_DENIALS=1 STUB_EFFORT=xhigh $LANEV "$PY" "$LANE" spawn --home "$LHOME" \
  --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-d --lane L4 \
  --class verifier --grant "$F/granted" --effort xhigh --record "$F/rec-d.jsonl" \
  --reason '(a) leg 15' >/dev/null 2>&1
RC=$?
CLOSE=$("$PY" - "$F/rec-d.jsonl" <<'CLOSE_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-closed":
        print(json.dumps({"effort": record["effort_applied"], "tier": record["cache_write_tier"],
                          "fence": record["denials"]["fence"],
                          "allows": record["denials"]["fence_allows"],
                          "tool": record["denials"]["tool"], "exit": record["exit_class"],
                          "peak": record["usage"]["peak_context"]}))
CLOSE_TERMINATOR
)
eq "the close line reads effort, tier, fence and tool denials from the fixture transcript" \
   "$CLOSE" '{"effort": ["xhigh"], "tier": ["1h"], "fence": 1, "allows": 1, "tool": 1, "exit": "completed", "peak": 5410}'
eq "permission denials are reported, not treated as an error" "$RC" "0"

env STUB_REFUSAL=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-e --lane L5 --class verifier \
  --grant "$F/granted" --record "$F/rec-e.jsonl" --reason '(a) leg 17' >/dev/null 2>&1
eq "a refusal in the transcript closes the lane at exit 3" "$?" "3"
grep -q '"exit_class": "refusal"' "$F/rec-e.jsonl" \
  && ok "the close line names the refusal" || no "close line does not name the refusal"

env STUB_SUBTYPE=error_max_budget_usd $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-f --lane L6 --class verifier \
  --grant "$F/granted" --record "$F/rec-f.jsonl" --reason '(a) leg 19' >/dev/null 2>&1
RC=$?
if [ "$RC" = 3 ] && grep -q '"exit_class": "budget"' "$F/rec-f.jsonl"; then
  ok "a budget stop closes the lane at exit 3 and says so"
else no "budget stop mishandled  [exit $RC]"; fi

# 20 · the deadline path ----------------------------------------------------------------------
START=$(date +%s)
env STUB_SLEEP=30 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-g --lane L7 --class verifier \
  --grant "$F/granted" --deadline-s 2 --record "$F/rec-g.jsonl" --reason '(a) leg 20' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 3 ] && grep -q '"exit_class": "deadline"' "$F/rec-g.jsonl" && [ "$ELAPSED" -lt 25 ]; then
  ok "the deadline kills the process group and records it (${ELAPSED}s against a 30s stub)"
else no "deadline path  [exit $RC, ${ELAPSED}s]"; fi

# 21 · the glob fallback for a transcript in an unexpected directory ---------------------------
env STUB_PROJECT_DIR=some-other-name $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-h --lane L8 --class verifier \
  --grant "$F/granted" --record "$F/rec-h.jsonl" --reason '(a) leg 21' >/dev/null 2>&1
if grep -q '"effort_applied": \[' "$F/rec-h.jsonl"; then
  ok "a transcript in an unexpected project directory is still found by the session-id glob"
else no "the glob fallback did not find the transcript"; fi

# 22–26 · the throttle mapping and out-of-range choices ----------------------------------------
tier(){ $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
        --run run-test-t --lane T --class wiki-compile --grant "$F/granted" --dry-run \
        --reason '(a) throttle tier' --throttle "$1" 2>/dev/null \
        | grep '^  claude' | tr ' ' '\n' | grep -A1 -x -e --model -e --effort | grep -v '^--' \
        | tr '\n' ' '; }
eq "throttle default -> the row's default"      "$(tier default)"    "opus xhigh "
eq "throttle top -> the strongest options"      "$(tier top)"        "fable max "
eq "throttle cheap -> weakest model, ceiling effort" "$(tier cheap)"  "sonnet max "
eq "throttle fast -> default model, weakest effort" "$(tier fast)"   "opus medium "
eq "throttle cheap-fast -> weakest of both"     "$(tier cheap-fast)" "sonnet medium "

# 26c · a grant given as the real path also gets its ~/.llm-wiki spelling (2026-09-06) ---------
if [ -L "$HOME/.llm-wiki" ]; then
  OUT=$(spawn --run run-test-sl --lane SL --class verifier --grant "$(cd "$HOME/.llm-wiki" && pwd -P)/spawn-records" \
        --record "$F/rec-sl.jsonl" --dry-run 2>&1)
  if printf '%s' "$OUT" | grep -q "$HOME/.llm-wiki/spawn-records"; then
    ok "a real-path grant under a symlinked root carries the symlink spelling in add_dirs"
  else no "the symlink spelling is missing from add_dirs for a real-path grant"; fi
else ok "(skipped: no ~/.llm-wiki symlink on this machine)"; fi

# 26b · row_default is the row's tier before the override (2026-09-06) --------------------------
OUT=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --run run-test-rd --lane RD --class wiki-compile --grant "$F/granted" --dry-run \
      --throttle default --model sonnet --effort high --reason '(a) row_default' 2>&1)
if printf '%s' "$OUT" | grep -q '"row_default": {"model": "opus", "effort": "xhigh"}' \
   && printf '%s' "$OUT" | grep -q '"model": "sonnet", "effort": "high"'; then
  ok "row_default holds the row's default (opus·xhigh) while the pick is the override (sonnet·high)"
else no "row_default did not differ from the overridden pick: $(printf '%s' "$OUT" | grep -o '"row_default": {[^}]*}' | head -1)"; fi

OUT=$(spawn --run run-test-i --lane L9 --class verifier --grant "$F/granted" --model haiku \
      --record "$F/rec-i.jsonl" --dry-run 2>&1)
if printf '%s' "$OUT" | grep -q 'outside_options'; then
  ok "a model outside the class options is recorded as such"
else no "an out-of-range model was not recorded"; fi

# per-call slots in a routing row -------------------------------------------------------------
spawn --run run-test-ph1 --lane B1 --class builder --write "$F/writable" \
      --record "$F/rec-ph1.jsonl" --reason '(a) slot filled by --write' >/dev/null 2>&1
PH1=$("$PY" - "$F/rec-ph1.jsonl" <<'SLOT_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        tokens = [p for p in record["grants"] + record["writes"] if "<" in p]
        print(json.dumps({"writes": record["writes"], "granted": record["writes"][0] in record["grants"],
                          "tokens": tokens}))
SLOT_TERMINATOR
)
if printf '%s' "$PH1" | grep -q '"granted": true' && printf '%s' "$PH1" | grep -q '"tokens": \[\]' \
   && printf '%s' "$PH1" | grep -q "$F/writable"; then
  ok "a write slot is filled by --write, and the record carries the resolved path, never the token"
else no "builder write slot  [$PH1]"; fi

MEMREL=".claude/agent-memory-local/memory-hunter"
if [ -d "$LHOME/$MEMREL" ]; then
  spawn --run run-test-ph2 --lane B2 --class memory-hunter \
        --record "$F/rec-ph2.jsonl" --reason '(a) slot filled by the home memory dir' >/dev/null 2>&1
  if grep -q "$MEMREL" "$F/rec-ph2.jsonl"; then
    ok "a memory class's write slot resolves to its own directory in the home, with no flag"
  else no "memory slot did not auto-resolve  [$(grep -o '"writes": \[[^]]*\]' "$F/rec-ph2.jsonl")]"; fi
else no "init did not materialise the memory directory the leg needs"; fi

spawn --run run-test-ph3 --lane B3 --class verifier --grant "$F/granted" \
      --record "$F/rec-ph3.jsonl" --reason '(a) read slot filled by --grant' >/dev/null 2>&1
if grep -q "$F/granted" "$F/rec-ph3.jsonl" && ! grep -q 'claim files' "$F/rec-ph3.jsonl"; then
  ok "a read slot is filled by --grant, and the token never reaches the record"
else no "verifier read slot  [$(grep -o '"grants": \[[^]]*\]' "$F/rec-ph3.jsonl")]"; fi

# --grants-only: a fixture-bound lane sees nothing of the live vault ---------------------------
mkdir -p "$F/fx"
# mktemp -d hands back the unresolved /var form on this platform while every path the wrapper
# records is symlink-resolved (/private/var/...), so the exact-match assertions use the
# resolved form; a substring test on the unresolved one would pass vacuously.
FXR=$("$PY" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$F/fx")
vaultrefs(){ # how many times the vault root appears in the record and in the --add-dir args
  R=$(grep -c -- "$VAULT" "$1"); [ -n "$R" ] || R=0
  G=$("$PY" - "$A" "$VAULT" <<'ADDDIR_TERMINATOR'
import sys
argv = open(sys.argv[1]).read().split("\n")
print(sum(1 for i, a in enumerate(argv)
          if a == "--add-dir" and i + 1 < len(argv) and argv[i + 1].startswith(sys.argv[2])))
ADDDIR_TERMINATOR
)
  echo "$R/$G"
}
spawn --run run-test-go1 --lane G1 --class wiki-compile --grants-only --grant "$F/fx" \
      --write "$F/fx" --record "$F/rec-go1.jsonl" --reason '(a) fixture-bound' >/dev/null 2>&1
GO1=$(vaultrefs "$F/rec-go1.jsonl")
GOENV=$(cat "$E")            # the environment of THIS spawn, before the control overwrites it
spawn --run run-test-go2 --lane G2 --class wiki-compile --grant "$F/fx" --write "$F/fx" \
      --record "$F/rec-go2.jsonl" --reason '(a) control: row literals kept' >/dev/null 2>&1
GO2=$(vaultrefs "$F/rec-go2.jsonl")
if [ "$GO1" = "0/0" ] && [ "$GO2" != "0/0" ]; then
  ok "--grants-only keeps every vault path out of the record and out of --add-dir (control: $GO2 vault references without the flag)"
else no "--grants-only scope  [with flag $GO1, without $GO2 — want 0/0 and non-zero]"; fi
if grep -q '"row_literals_dropped": \["wiki"\]' "$F/rec-go1.jsonl"; then
  ok "the dropped row literals are named in the record, not discarded quietly"
else no "row_literals_dropped  [$(grep -o '\"row_literals_dropped\": \[[^]]*\]' "$F/rec-go1.jsonl")]"; fi
if grep -q "\"$FXR\"" "$F/rec-go1.jsonl"; then
  ok "the row's per-call slot is still filled from the call under --grants-only"
else no "the slot was not filled under --grants-only"; fi
if printf '%s\n' "$GOENV" | grep -q "LLM_WIKI_LANE_GRANTS=$FXR:" \
   && printf '%s\n' "$GOENV" | grep -q "LLM_WIKI_LANE_WRITES=$FXR$" \
   && ! printf '%s\n' "$GOENV" | grep -q -- "$VAULT"; then
  ok "the fence environment carries exactly the call's scope, with no vault path in it"
else no "fence environment under --grants-only  [$(printf '%s\n' "$GOENV" | grep GRANTS)]"; fi

# 27–33 · premise failures: exit 2, no record --------------------------------------------------
premise(){ # name, expected-fragment, args...
  NAME="$1"; FRAG="$2"; shift 2
  rm -f "$F/rec-p.jsonl"
  ERR=$($LANEV "$PY" "$LANE" spawn --projects-root "$PROJ" --record "$F/rec-p.jsonl" \
        --reason '(a) premise fixture' "$@" 2>&1)
  RC=$?
  if [ "$RC" = 2 ] && [ ! -f "$F/rec-p.jsonl" ] && printf '%s' "$ERR" | grep -q "$FRAG"; then
    ok "premise: $NAME (exit 2, no record)"
  else no "premise: $NAME  [exit $RC, record $([ -f "$F/rec-p.jsonl" ] && echo written || echo absent), said: $ERR]"; fi
}
premise "no lane home"        "run \`lane.py init\`" --home "$F/nohome" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier
premise "unknown class"       "unknown class"        --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class no-such-class
premise "routing schema 1"    "schema"               --home "$LHOME" --routing "$F/routing-v1.json" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier
premise "routing field missing" "has no \`tools\`"   --home "$LHOME" --routing "$F/routing-noTools.json" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "brief missing"       "brief file not found" --home "$LHOME" --routing "$R" \
        --brief "$F/no-brief.md" --run run-test-p --lane P --class verifier
premise "default slice missing" "resolves nowhere" --home "$LHOME" \
        --routing "$F/routing-badslice.json" --brief "$F/brief.md" --run run-test-p --lane P \
        --class reflector --grant "$F/granted"
premise "grant that does not exist" "does not exist" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/no-such-dir"
premise "a write slot the call left empty" "needs --write for <target dirs>" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class builder \
        --grant "$F/granted"
premise "a read slot the call left empty" "needs --grant for <fixture>" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class gate-judge
premise "--grants-only with no --grant" "needs at least one --grant" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class wiki-compile \
        --grants-only --write "$F/fx"

mkdir -p "$F/rolock"; : > "$F/rolock/rec.jsonl"; chmod a-w "$F/rolock/rec.jsonl" "$F/rolock"
ERR=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-p --lane P --class verifier --grant "$F/granted" \
      --record "$F/rolock/rec.jsonl" --reason '(a) an unwritable record' 2>&1)
RC=$?; chmod u+w "$F/rolock" "$F/rolock/rec.jsonl"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'not writable'; then
  ok "premise: an unwritable spawn record (exit 2)"
else no "an unwritable record did not stop the spawn  [exit $RC: $ERR]"; fi

# 35 · --dry-run writes nothing ---------------------------------------------------------------
DRYMAN1=$(find "$STORE" "$LHOME" -type f -exec shasum {} \; | sort)
DRYOUT=$(spawn --run run-test-dry --lane D1 --class wiki-compile --grant "$F/granted" \
         --write "$F/writable" --record "$F/rec-dry.jsonl" --dry-run 2>&1)
DRYMAN2=$(find "$STORE" "$LHOME" -type f -exec shasum {} \; | sort)
if [ "$DRYMAN1" = "$DRYMAN2" ] && [ ! -f "$F/rec-dry.jsonl" ] \
   && printf '%s' "$DRYOUT" | grep -q 'claude -p --agents' \
   && printf '%s' "$DRYOUT" | grep -q 'LLM_WIKI_LANE_GRANTS='; then
  ok "--dry-run prints the full command, the environment and the record line, and writes nothing"
else no "--dry-run wrote something or printed too little"; fi

# 36–39 · the console opens on a spawn, once per run ------------------------------------------
# Every spawn puts the run's console on screen when none is alive (owner ruling 2026-09-08); the
# recording stub in AIMYTH_VIEWER_CMD stands in for the Terminal, so no window opens here.
V1="$F/viewer-v1.argv"; : > "$V1"
$LANEV AIMYTH_VIEWER_ARGV="$V1" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 36' --run run-20260908-view --lane V1 --class verifier \
  --grant "$F/granted" --record "$F/rec-view.jsonl" >/dev/null 2>"$F/v1.err"
if [ "$(grep -c 'run-20260908-view-console.command' "$V1")" = 1 ] && grep -q 'viewer: Terminal window on' "$F/v1.err"; then
  ok "the first spawn of a run opens its console once (the viewer stub ran on the run's command file)"
else no "the first spawn opened no console  [argv $(grep -c . "$V1"), stderr: $(head -3 "$F/v1.err" | tr '\n' ' ')]"; fi
V2="$F/viewer-v2.argv"; : > "$V2"
$LANEV AIMYTH_VIEWER_ARGV="$V2" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 37' --run run-20260908-view --lane V2 --class verifier \
  --grant "$F/granted" --record "$F/rec-view.jsonl" >/dev/null 2>"$F/v2.err"
if [ "$(grep -c . "$V2")" = 0 ] && grep -q 'no second window' "$F/v2.err"; then
  ok "a second spawn on the same run inside the grace window opens no second window (the live console shows the new lane)"
else no "the second spawn doubled the console  [argv $(grep -c . "$V2"), stderr: $(head -3 "$F/v2.err" | tr '\n' ' ')]"; fi
V3="$F/viewer-v3.argv"; : > "$V3"
$LANEV AIMYTH_VIEWER_ARGV="$V3" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 38' --run run-20260908-view2 --lane V3 --class verifier --viewer none \
  --grant "$F/granted" --record "$F/rec-view2.jsonl" >/dev/null 2>"$F/v3.err"
if [ "$(grep -c . "$V3")" = 0 ] && grep -q 'viewer none' "$F/v3.err"; then
  ok "--viewer none opts out (no window, said on stderr)"
else no "--viewer none still opened  [argv $(grep -c . "$V3"), stderr: $(head -3 "$F/v3.err" | tr '\n' ' ')]"; fi
V4="$F/viewer-v4.argv"; : > "$V4"
$LANEV AIMYTH_VIEWER_ARGV="$V4" AIMYTH_VIEWER=none "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 39' --run run-20260908-view3 --lane V4 --class verifier \
  --grant "$F/granted" --record "$F/rec-view3.jsonl" >/dev/null 2>"$F/v4.err"
if [ "$(grep -c . "$V4")" = 0 ]; then
  ok "AIMYTH_VIEWER=none opts out too"
else no "AIMYTH_VIEWER=none still opened  [argv $(grep -c . "$V4")]"; fi
# 40–41 · the opener's premises fail without failing the spawn --------------------------------
cat > "$BIN/viewer-fail.sh" <<'VIEWER_FAIL_END'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a" >> "$AIMYTH_VIEWER_ARGV"; done
printf 'stub viewer: this window refuses to open\n' >&2
exit 1
VIEWER_FAIL_END
chmod +x "$BIN/viewer-fail.sh"
V5="$F/viewer-v5.argv"; : > "$V5"
$LANEV AIMYTH_VIEWER_ARGV="$V5" AIMYTH_VIEWER_CMD="$BIN/viewer-fail.sh" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 40' --run run-20260908-view4 --lane V5 --class verifier \
  --grant "$F/granted" --record "$F/rec-view4.jsonl" >/dev/null 2>"$F/v5.err"; RC5=$?
if [ "$RC5" = 0 ] && grep -q 'no Terminal window' "$F/v5.err" && [ "$(grep -c '"event": "lane-closed"' "$F/rec-view4.jsonl")" = 1 ]; then
  ok "a viewer that fails never fails the spawn (exit 0, the lane ran to its close, the failure said on stderr)"
else no "a failing viewer broke the spawn  [exit $RC5, stderr: $(head -3 "$F/v5.err" | tr '\n' ' ')]"; fi
V6="$F/viewer-v6.argv"; : > "$V6"
$LANEV AIMYTH_VIEWER_ARGV="$V6" AIMYTH_VIEWER=1 "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --reason '(a) leg 41' --run run-20260908-view5 --lane V6 --class verifier \
  --grant "$F/granted" --record "$F/rec-view5.jsonl" >/dev/null 2>"$F/v6.err"
if grep -q 'neither terminal nor none' "$F/v6.err" && [ "$(grep -c . "$V6")" = 1 ]; then
  ok "an unknown AIMYTH_VIEWER value is named on stderr and the grants default (terminal) decides"
else no "an unknown viewer value was not handled  [argv $(grep -c . "$V6"), stderr: $(head -2 "$F/v6.err" | tr '\n' ' ')]"; fi

# ------------------------------------------------------ the delegation regime in the record ---
# Resolved from the flags or the Settings line; `auto`, an absent line or any other value is a
# premise failure, so the record never carries a regime nobody chose.
echo "== delegation =="
modeof(){ "$PY" - "$1" <<'MODEOF_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        print("%s/%s/%s" % (record.get("mode"), record.get("mode_src"), record.get("mode_from")))
MODEOF_TERMINATOR
}
# $1 = vault dir (the CLAUDE_PROJECT_DIR override goes AFTER $LANEV's own, so it wins), then args
dspawn(){ V="$1"; shift; $LANEV CLAUDE_PROJECT_DIR="$V" "$PY" "$LANE" spawn --home "$LHOME" \
          --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --class verifier \
          --grant "$F/granted" --reason '(a) delegation regime fixture' "$@"; }
eq "a Settings single passes through to the record with source owner (the leg-7 spawn)" \
   "$(modeof "$F/rec-b.jsonl")" 'single/owner/the Settings `delegation` line'

mkvault "$F/vault-auto"   '- **delegation**: auto — the head resolves per run'
mkvault "$F/vault-legacy" '- **mode**: multi — the pre-rename line'
mkvault "$F/vault-legauto" '- **mode**: auto — the pre-rename line, unresolved'
mkvault "$F/vault-noline" ''
dpremise(){ # name, expected-fragment, vault, args...
  NAME="$1"; FRAG="$2"; V="$3"; shift 3
  rm -f "$F/rec-dp.jsonl"
  ERR=$(dspawn "$V" --run run-test-dp --lane DP --record "$F/rec-dp.jsonl" "$@" 2>&1); RC=$?
  if [ "$RC" = 2 ] && [ ! -f "$F/rec-dp.jsonl" ] && printf '%s' "$ERR" | grep -qF -- "$FRAG"; then
    ok "premise: $NAME (exit 2, no record)"
  else no "premise: $NAME  [exit $RC, record $([ -f "$F/rec-dp.jsonl" ] && echo written || echo absent), said: $ERR]"; fi
}
dpremise "Settings auto without --delegation" 'the Settings line is `auto`' "$F/vault-auto"
dpremise "a Settings line that is absent" 'the Settings line is absent' "$F/vault-noline"
dpremise "a pre-rename mode line reading auto" 'the Settings line is `auto`' "$F/vault-legauto"
dpremise "--delegation without --delegation-src" 'go together' "$F/vault-auto" --delegation multi
dpremise "--delegation-src without --delegation" 'go together' "$F/vault-auto" --delegation-src head
ERR=$(dspawn "$F/vault-auto" --run run-test-dp --lane DP --record "$F/rec-dp.jsonl" --delegation turbo \
      --delegation-src head 2>&1); RC=$?
if [ "$RC" = 2 ] && [ ! -f "$F/rec-dp.jsonl" ] && printf '%s' "$ERR" | grep -q 'invalid choice'; then
  ok "premise: a regime no run runs under is refused by the flag itself (exit 2, no record)"
else no "an invalid --delegation value got through  [exit $RC: $ERR]"; fi

dspawn "$F/vault-auto" --run run-test-dl --lane DL1 --record "$F/rec-dl1.jsonl" \
       --delegation multi --delegation-src head --reason '(a) resolved under auto' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && [ "$(modeof "$F/rec-dl1.jsonl")" = 'multi/head/--delegation' ] \
   && grep -q '^LLM_WIKI_LANE_RUN=run-test-dl$' "$E"; then
  ok "under Settings auto the flags carry the regime and its source into the record, and the lane spawns (control: the stub saw the run)"
else no "flags under auto  [exit $RC, record $(modeof "$F/rec-dl1.jsonl" 2>&1)]"; fi

dspawn "$F/vault-legacy" --run run-test-dl --lane DL2 --record "$F/rec-dl2.jsonl" \
       --reason '(a) legacy line' >/dev/null 2>&1
eq "a pre-rename mode line reading multi passes through with source owner and says which line" \
   "$(modeof "$F/rec-dl2.jsonl")" 'multi/owner/the Settings `mode (the pre-rename line)` line'

dspawn "$FXV" --run run-test-dl --lane DL3 --record "$F/rec-dl3.jsonl" \
       --delegation multi --delegation-src owner --reason '(a) the owner said do this multi' >/dev/null 2>&1
eq "the flags beat a Settings single (the owner's one-run word)" \
   "$(modeof "$F/rec-dl3.jsonl")" 'multi/owner/--delegation'

DRY=$(dspawn "$F/vault-auto" --run run-test-dl --lane DL4 --record "$F/rec-dl4.jsonl" \
      --delegation single --delegation-src head --dry-run 2>&1)
if printf '%s' "$DRY" | grep -q '"mode": "single", "mode_src": "head", "mode_from": "--delegation"' \
   && [ ! -f "$F/rec-dl4.jsonl" ]; then
  ok "--dry-run shows the resolved regime and source on the record line it would write"
else no "--dry-run record line  [$(printf '%s' "$DRY" | grep -o '"mode[^,]*,[^,]*,[^,]*')]"; fi

# ------------------------------------------------------------- the hands-off additions -------
# File-level grants, both spellings, the per-lane input directory, --grant-vault-root, the
# CONTROL+ refusal, the per-spawn settings, --config-dir, the report cut, the silence watch,
# watch, resume, the limit class and --detach (design page hands-off-mode-design: D8, D17–D20,
# D25; C2 N5, N6, N12). Every planted case has its clean control on the same probe.
echo "== hands-off =="
recfield(){ # record, event, key -> the key's value as sorted JSON, from the LAST such event
  "$PY" - "$1" "$2" "$3" <<'RECFIELD_TERMINATOR'
import json, sys
value = None
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("event") == sys.argv[2] and sys.argv[3] in record:
        value = record[sys.argv[3]]
print(json.dumps(value, sort_keys=True))
RECFIELD_TERMINATOR
}
events(){ N=$(grep -c "\"event\": \"$2\"" "$1"); [ -n "$N" ] || N=0; echo "$N"; }
adddirs(){ "$PY" - "$A" <<'ADDDIRS_TERMINATOR'
import sys
argv = open(sys.argv[1]).read().split("\n")
for i, a in enumerate(argv):
    if a == "--add-dir" and i + 1 < len(argv):
        print(argv[i + 1])
ADDDIRS_TERMINATOR
}
argafter(){ grep -A1 -x -- "$1" "$A" | tail -1; }
dirs_of(){ printf '%s\n' "$1" | grep '^add-dirs:' | sed 's/^add-dirs: //' | tr ' ' '\n'; }

# file-level grants, the per-spawn settings and the input directory ---------------------------
printf 'NOTE\n' > "$F/writable/note.md"
spawn --run run-test-fg --lane FG --class builder --grant "$F/granted/inside.txt" \
      --write "$F/writable/note.md" --record "$F/rec-fg.jsonl" --reason '(a) file-level grants' >/dev/null 2>&1
RC=$?
GF=$(recfield "$F/rec-fg.jsonl" lane-open grants_files); WF=$(recfield "$F/rec-fg.jsonl" lane-open writes_files)
if [ "$RC" = 0 ] && [ "$GF" = "[\"$FR/granted/inside.txt\", \"$FR/writable/note.md\"]" ] \
   && [ "$WF" = "[\"$FR/writable/note.md\"]" ]; then
  ok "a file passed to --grant or --write is accepted and recorded in grants_files / writes_files (real paths)"
else no "file-level grants  [exit $RC, grants_files $GF, writes_files $WF]"; fi
if grep -q "^LLM_WIKI_LANE_WRITES=$FR/writable/note.md$" "$E" \
   && grep -q "^LLM_WIKI_LANE_GRANTS=$FR/granted/inside.txt:$FR/writable/note.md:" "$E"; then
  ok "the fence environment carries the file paths themselves (a write file is also a read grant)"
else no "file grants in the fence environment  [$(grep LLM_WIKI_LANE_ "$E" | tr '\n' ' ')]"; fi
if adddirs | grep -qx "$FR/granted" && adddirs | grep -qx "$FR/writable" \
   && ! adddirs | grep -q 'inside.txt' && ! adddirs | grep -q 'note.md'; then
  ok "the file tools get each file's parent directory through --add-dir, never the file itself"
else no "--add-dir for file grants  [$(adddirs | tr '\n' ' ')]"; fi
SET="$STORE/spawn-records/run-test-fg-settings-FG.json"
if [ -f "$SET" ] && grep -qx -- "$SR/run-test-fg-settings-FG.json" "$A" \
   && grep -q "\"Edit(/$FR/writable/note.md)\"" "$SET" && grep -q "\"Write(/$FR/writable/note.md)\"" "$SET" \
   && grep -q 'lane-fence.py' "$SET" && grep -q '"PreToolUse"' "$SET"; then
  ok "the per-spawn settings file carries the home's hooks plus Edit/Write allow rules for the file write, and is what --settings names"
else no "per-spawn settings  [$(cat "$SET" 2>&1 | tr '\n' ' ')]"; fi
SETC="$STORE/spawn-records/run-test-c-settings-L3.json"; SETB="$STORE/spawn-records/run-test-b-settings-L2.json"
if grep -q "\"Edit(/$FR/writable/\*\*)\"" "$SETC" && grep -q "\"Write(/$FR/writable/\*\*)\"" "$SETC" \
   && ! grep -q 'permissions' "$SETB" && grep -q '"PreToolUse"' "$SETB"; then
  ok "a directory write allows its whole tree (dir/**); a read-only lane's settings carry the hooks and no allow list (control)"
else no "settings allow shapes  [$(grep -o 'Edit([^)]*)' "$SETC" | tr '\n' ' ') / permissions lines in the read-only file: $(grep -c permissions "$SETB")]"; fi
IN="$STORE/spawn-records/run-test-fg-in-FG"
if [ -f "$IN/run-test-fg-brief-FG.md" ] && cmp -s "$IN/run-test-fg-brief-FG.md" "$F/brief.md" \
   && [ "$(recfield "$F/rec-fg.jsonl" lane-open input_dir)" = "\"$SR/run-test-fg-in-FG\"" ] \
   && adddirs | grep -qx "$SR/run-test-fg-in-FG" && grep -q "^LLM_WIKI_LANE_GRANTS=.*:$SR/run-test-fg-in-FG:" "$E" \
   && ! adddirs | grep -qx "$SR"; then
  ok "each spawn gets its own input directory with the brief copied in, granted read in the fence and --add-dir; the store itself is not granted"
else no "the per-lane input directory  [$(ls "$IN" 2>&1 | tr '\n' ' '); add-dirs $(adddirs | tr '\n' ' ')]"; fi
spawn --run run-test-fg2 --lane FG2 --class verifier --grant "$STORE/spawn-records" \
      --record "$F/rec-fg2.jsonl" --reason '(a) control: the store named explicitly' >/dev/null 2>&1
if adddirs | grep -qx "$SR"; then ok "the store reaches --add-dir when a call names it (control for the leg above)"
else no "an explicit store grant did not reach --add-dir  [$(adddirs | tr '\n' ' ')]"; fi

# both spellings of a symlinked grant -----------------------------------------------------------
ln -s "$F/granted" "$F/link-granted"
spawn --run run-test-sl --lane SL --class verifier --grant "$F/link-granted" \
      --record "$F/rec-sl.jsonl" --reason '(a) a symlinked grant' >/dev/null 2>&1
if adddirs | grep -qx "$FR/granted" && adddirs | grep -qx "$F/link-granted" \
   && [ "$(recfield "$F/rec-sl.jsonl" lane-open grants)" = "[\"$FR/granted\"]" ]; then
  ok "a symlinked grant reaches --add-dir in both spellings and the record in its real path"
else no "symlink spellings  [$(adddirs | tr '\n' ' ')]"; fi
spawn --run run-test-sl2 --lane SL2 --class verifier --grant "$FR/granted" \
      --record "$F/rec-sl2.jsonl" --reason '(a) control: a real path' >/dev/null 2>&1
eq "a grant given as its real path is passed once (control for the two-spelling leg)" \
   "$(adddirs | grep -c '/granted$')" "1"

# --grant-vault-root -----------------------------------------------------------------------------
GV=$(spawn --run run-test-gv --lane GV --class verifier --grant "$F/granted" --record "$F/rec-gv.jsonl" \
     --grant-vault-root --dry-run 2>&1)
GV0=$(spawn --run run-test-gv --lane GV0 --class verifier --grant "$F/granted" --record "$F/rec-gv.jsonl" \
      --dry-run 2>&1)
if dirs_of "$GV" | grep -qx "$FR/vault" && printf '%s\n' "$GV" | grep -q '"grant_vault_root": true' \
   && printf '%s\n' "$GV" | grep '^  LLM_WIKI_LANE_GRANTS=' | sed 's/^  LLM_WIKI_LANE_GRANTS=//' | tr ':' '\n' | grep -qx "$FR/vault" \
   && ! dirs_of "$GV0" | grep -qx "$FR/vault" && printf '%s\n' "$GV0" | grep -q '"grant_vault_root": false' \
   && [ ! -f "$F/rec-gv.jsonl" ]; then
  ok "--grant-vault-root passes the real vault root through --add-dir and the fence grants and records the flag (control: absent without it)"
else no "--grant-vault-root  [$(dirs_of "$GV" | tr '\n' ' ')]"; fi

# CONTROL+ lines --------------------------------------------------------------------------------
printf 'Do the thing.\nCONTROL+: GRANTED in %s\n- CONTROL+: "Settings" in CUSTOMISATION.md\n' "$F/granted/inside.txt" > "$F/brief-ctl.md"
spawn --run run-test-ct --lane CT --class verifier --grant "$F/granted" --record "$F/rec-ct.jsonl" \
      --brief "$F/brief-ctl.md" --reason '(a) controls checked' >/dev/null 2>&1
RC=$?
WANT="[{\"file\": \"$FR/granted/inside.txt\", \"matches\": 1, \"phrase\": \"GRANTED\"}, {\"file\": \"$FR/vault/CUSTOMISATION.md\", \"matches\": 1, \"phrase\": \"Settings\"}]"
GOT=$(recfield "$F/rec-ct.jsonl" lane-open controls_checked)
if [ "$RC" = 0 ] && [ "$GOT" = "$WANT" ]; then
  ok "CONTROL+ lines are grepped before the spawn (a bulleted, quoted phrase and a vault-relative file included) and recorded as controls_checked"
else no "controls_checked  [exit $RC: $GOT]"; fi
printf 'x\nCONTROL+: NOPE-PHRASE-7731 in %s\n' "$F/granted/inside.txt" > "$F/brief-ctl-miss.md"
printf 'x\nCONTROL+: GRANTED in %s\n' "$F/granted/absent.txt" > "$F/brief-ctl-nofile.md"
printf 'x\nCONTROL+: GRANTED\n' > "$F/brief-ctl-bad.md"
premise "a CONTROL+ phrase that matches nothing refuses the spawn" "matches nothing" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-miss.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "a CONTROL+ file that does not exist" "control file not found" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-nofile.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "a malformed CONTROL+ line" "malformed control line" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-bad.md" --run run-test-p --lane P --class verifier --grant "$F/granted"

# --config-dir ----------------------------------------------------------------------------------
mkdir -p "$F/cfg2"
spawn --run run-test-cfg --lane CF --class verifier --grant "$F/granted" --config-dir "$F/cfg2" \
      --record "$F/rec-cfg.jsonl" --reason '(a) a second login directory' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && grep -q "^CLAUDE_CONFIG_DIR=$F/cfg2$" "$E" \
   && [ "$(recfield "$F/rec-cfg.jsonl" lane-open config_dir)" = "\"$F/cfg2\"" ]; then
  ok "--config-dir sets CLAUDE_CONFIG_DIR for the lane process and is recorded on lane-open"
else no "--config-dir  [exit $RC, env $(grep CLAUDE_CONFIG_DIR "$E"), record $(recfield "$F/rec-cfg.jsonl" lane-open config_dir)]"; fi
spawn --run run-test-cfg0 --lane CF0 --class verifier --grant "$F/granted" \
      --record "$F/rec-cfg0.jsonl" --reason '(a) control: no config dir' >/dev/null 2>&1
if grep -q '^CLAUDE_CONFIG_DIR=<unset>$' "$E" && [ "$(recfield "$F/rec-cfg0.jsonl" lane-open config_dir)" = "null" ]; then
  ok "without the flag the lane inherits no CLAUDE_CONFIG_DIR and the record says null (control)"
else no "config dir control  [$(grep CLAUDE_CONFIG_DIR "$E")]"; fi
premise "--config-dir that is not a directory" "not a directory" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted" --config-dir "$F/no-cfg"

# the report cut --------------------------------------------------------------------------------
LONG=$("$PY" -c 'print(" ".join("w%d" % i for i in range(1, 1001)))')
CUT=$(env STUB_REPORT="$LONG" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-cut --lane CU --class verifier --grant "$F/granted" \
      --record "$F/rec-cut.jsonl" --reason '(a) report cut' 2>&1)
RC=$?
REPF="$STORE/spawn-records/run-test-cut-report-CU.md"
if [ "$RC" = 0 ] && printf '%s\n' "$CUT" | grep -qF "(800 of 1000 words shown; full text: $SR/run-test-cut-report-CU.md)" \
   && printf '%s\n' "$CUT" | grep -qw 'w800' && ! printf '%s\n' "$CUT" | grep -qw 'w801' \
   && [ "$(wc -w < "$REPF" | tr -d ' ')" = 1000 ] \
   && [ "$(recfield "$F/rec-cut.jsonl" lane-closed report_words)" = 1000 ] \
   && [ "$(recfield "$F/rec-cut.jsonl" lane-closed report_cut)" = true ] \
   && printf '%s\n' "$CUT" | grep -q 'report 800/1000 words (cut)'; then
  ok "a 1000-word report is cut to 800 words on stdout with the pointer line, persisted whole, and recorded as report_words 1000 / report_cut true"
else no "the report cut  [exit $RC; $(printf '%s\n' "$CUT" | grep -c .) lines; $(printf '%s\n' "$CUT" | grep 'words shown')]"; fi
SHORT=$(spawn --run run-test-cut2 --lane CU2 --class verifier --grant "$F/granted" --record "$F/rec-cut2.jsonl" \
        --reason '(a) control: a short report' 2>&1)
FIVE=$(env STUB_REPORT="$LONG" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
       --projects-root "$PROJ" --run run-test-cut3 --lane CU3 --class verifier --grant "$F/granted" \
       --record "$F/rec-cut3.jsonl" --report-words 5 --reason '(a) the report cut' 2>&1)
if printf '%s\n' "$SHORT" | grep -q '(3 of 3 words shown; full text: ' \
   && [ "$(recfield "$F/rec-cut2.jsonl" lane-closed report_cut)" = false ] \
   && printf '%s\n' "$FIVE" | grep -q '(5 of 1000 words shown; full text: ' \
   && printf '%s\n' "$FIVE" | grep -qw 'w5' && ! printf '%s\n' "$FIVE" | grep -qw 'w6'; then
  ok "a short report is shown whole (report_cut false) and --report-words sets the cut (controls)"
else no "report cut controls  [$(printf '%s\n' "$SHORT" | grep 'words shown') / $(printf '%s\n' "$FIVE" | grep 'words shown')]"; fi

# the silence watch -----------------------------------------------------------------------------
START=$(date +%s)
env STUB_SLEEP_AFTER=20 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st1 --lane S1 --class verifier --grant "$F/granted" \
  --silence-s 2 --poll-s 1 --record "$F/rec-st1.jsonl" --reason '(a) a silent lane' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"event": "stall"' "$F/rec-st1.jsonl" && grep -q '"reason": "silent"' "$F/rec-st1.jsonl" \
   && grep -q '"exit_class": "stall"' "$F/rec-st1.jsonl" && grep -q '"by": "spawn"' "$F/rec-st1.jsonl" \
   && [ "$ELAPSED" -lt 15 ]; then
  ok "a lane silent past --silence-s is killed: stall event, exit_class stall, exit 5 (${ELAPSED}s against a 20 s sleep)"
else no "the silence watch  [exit $RC, ${ELAPSED}s, $(grep -o '"event": "[a-z-]*"' "$F/rec-st1.jsonl" | tr '\n' ' ')]"; fi
env STUB_SLEEP_AFTER=5 STUB_PROGRESS=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st2 --lane S2 --class verifier --grant "$F/granted" \
  --silence-s 2 --poll-s 1 --record "$F/rec-st2.jsonl" --reason '(a) control: a progress file' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && ! grep -q '"event": "stall"' "$F/rec-st2.jsonl" && [ -s "$F/progress/run-test-st2-S2.progress" ] \
   && grep -q "^LLM_WIKI_LANE_PROGRESS=$F/progress/run-test-st2-S2.progress$" "$E"; then
  ok "a lane that appends to its progress file through a 5 s silence is not stalled at a 2 s threshold (control; the path reaches the lane as LLM_WIKI_LANE_PROGRESS)"
else no "the progress-file liveness  [exit $RC, progress file: $(wc -l < "$F/progress/run-test-st2-S2.progress" 2>&1) lines]"; fi
START=$(date +%s)
env STUB_SLEEP=20 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st3 --lane S3 --class verifier --grant "$F/granted" \
  --silence-s 30 --poll-s 1 --no-transcript-s 2 --record "$F/rec-st3.jsonl" --reason '(a) no transcript' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"reason": "no transcript"' "$F/rec-st3.jsonl" && [ "$ELAPSED" -lt 15 ]; then
  ok "no transcript within --no-transcript-s is a stall of reason 'no transcript' (${ELAPSED}s)"
else no "the no-transcript stall  [exit $RC, ${ELAPSED}s]"; fi
env STUB_SLEEP_AFTER=4 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st4 --lane S4 --class verifier --grant "$F/granted" \
  --silence-s 0 --poll-s 1 --no-transcript-s 1 --record "$F/rec-st4.jsonl" --reason '(a) --silence-s 0' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && ! grep -q '"event": "stall"' "$F/rec-st4.jsonl" \
   && [ "$(recfield "$F/rec-st4.jsonl" lane-open silence_s)" = 0 ]; then
  ok "--silence-s 0 disables the watch: a 4 s silence at a 1 s no-transcript bound completes (control)"
else no "--silence-s 0  [exit $RC]"; fi
printf '{"event": "lane-closed", "lane": "X", "run": "run-test-bl", "duration_s": 10}\n' > "$F/rec-bl.jsonl"
BL=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
     --silence-s 5 --baseline-lane X --dry-run 2>&1)
BL2=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
      --silence-s 100 --baseline-lane X --dry-run 2>&1)
BL3=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" --dry-run 2>&1)
if printf '%s\n' "$BL" | grep -qF 'silence: 15.0 s (1.5 x baseline X (10.0 s))' \
   && printf '%s\n' "$BL2" | grep -qF 'silence: 100.0 s (--silence-s)' \
   && printf '%s\n' "$BL3" | grep -qF 'silence: 900 s (default)'; then
  ok "--baseline-lane raises the threshold to 1.5 x the predecessor's duration only when larger; the default is 900 s"
else no "the silence threshold  [$(printf '%s\n' "$BL" | grep '^silence') / $(printf '%s\n' "$BL2" | grep '^silence') / $(printf '%s\n' "$BL3" | grep '^silence')]"; fi
ERR=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
      --baseline-lane Y --dry-run 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'has no lane-closed'; then
  ok "premise: --baseline-lane naming a lane with no recorded close (exit 2)"
else no "an unknown baseline lane got through  [exit $RC: $ERR]"; fi

# watch -----------------------------------------------------------------------------------------
ERR=$($LANEV "$PY" "$LANE" watch --run run-test-b --lane NOPE --record "$F/rec-b.jsonl" --poll-s 1 --appear-s 0 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'unknown'; then ok "watch: an unknown lane is refused (exit 2)"
else no "watch on an unknown lane  [exit $RC: $ERR]"; fi
OUT=$($LANEV "$PY" "$LANE" watch --run run-test-b --lane L2 --record "$F/rec-b.jsonl" --poll-s 1 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'already closed' && printf '%s' "$OUT" | grep -q '^lane run-test-b/L2: '; then
  ok "watch: an already-closed lane is refused (exit 2) after its summary line"
else no "watch on a closed lane  [exit $RC: $OUT]"; fi
env STUB_SLEEP_AFTER=6 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-w1 --lane W1 --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-w1.jsonl" --reason '(a) watched to its close' >/dev/null 2>&1 &
SP=$!
sleep 2
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-w1 --lane W1 --record "$F/rec-w1.jsonl" --poll-s 1 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"
if [ "$RC" = 0 ] && printf '%s\n' "$WOUT" | grep -q '^lane run-test-w1/W1: .* completed ' \
   && [ "$(events "$F/rec-w1.jsonl" lane-closed)" = 1 ]; then
  ok "watch: a running lane that closes on its own returns 0 with the summary line, and no second close is written"
else no "watch to a natural close  [exit $RC: $(printf '%s' "$WOUT" | head -2 | tr '\n' ' ')]"; fi
env STUB_SLEEP_AFTER=8 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-w2 --lane W2 --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-w2.jsonl" --reason '(a) still running' >/dev/null 2>&1 &
SP=$!
sleep 2
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-w2 --lane W2 --record "$F/rec-w2.jsonl" --poll-s 1 --max-wait-s 2 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"
if [ "$RC" = 8 ] && printf '%s' "$WOUT" | grep -q 'still-running'; then
  ok "watch: --max-wait-s returns still-running (exit 8) so the head can re-issue a bounded blocking call"
else no "watch --max-wait-s  [exit $RC: $WOUT]"; fi
env STUB_SLEEP_AFTER=30 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-ws --lane WS --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-ws.jsonl" --reason '(a) stalled by watch' >/dev/null 2>&1 &
SP=$!
sleep 2; START=$(date +%s)
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-ws --lane WS --record "$F/rec-ws.jsonl" --poll-s 1 --silence-s 1 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"by": "watch"' "$F/rec-ws.jsonl" && grep -q '"event": "stall"' "$F/rec-ws.jsonl" \
   && [ "$(events "$F/rec-ws.jsonl" lane-closed)" = 1 ] && [ "$ELAPSED" -lt 20 ]; then
  ok "watch --silence-s kills a silent lane (stall event by watch, exit 5) and the live wrapper writes the one close (${ELAPSED}s against a 30 s sleep)"
else no "watch stalling a lane  [exit $RC, ${ELAPSED}s: $(printf '%s' "$WOUT" | head -2 | tr '\n' ' ')]"; fi
# a lane whose wrapper is gone: closed from its transcript (C2 N6)
sh -c 'exit 0' & DEADPID=$!; wait "$DEADPID"
TS=$(date +%Y-%m-%dT%H:%M:%S%z)
printf '{"ts": "%s", "run": "run-test-wg", "lane": "WG", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "fixture-gone", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' "$TS" "$LHOME" "$PROJ" > "$F/rec-wg.jsonl"
printf '{"ts": "%s", "run": "run-test-wg", "lane": "WG", "event": "lane-spawned", "session_id": "fixture-gone", "pid": %s, "wrapper_pid": %s}\n' "$TS" "$DEADPID" "$DEADPID" >> "$F/rec-wg.jsonl"
DASHED=$("$PY" -c 'import os, re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(sys.argv[1])))' "$LHOME")
mkdir -p "$PROJ/$DASHED"
sleep 1
"$PY" - "$PROJ/$DASHED/fixture-gone.jsonl" <<'GONE_TRANSCRIPT_TERMINATOR'
import json, sys
usage = {"input_tokens": 5, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 2000,
         "output_tokens": 30}
with open(sys.argv[1], "w") as h:
    h.write(json.dumps({"type": "assistant", "effort": "high", "message": {
        "id": "g1", "model": "claude-sonnet-5", "role": "assistant", "usage": usage,
        "content": [{"type": "text", "text": "orphan report text ORPHAN-9911"}]}}) + "\n")
GONE_TRANSCRIPT_TERMINATOR
WG=$($LANEV "$PY" "$LANE" watch --run run-test-wg --lane WG --record "$F/rec-wg.jsonl" --poll-s 1 2>&1); RC=$?
if [ "$RC" = 0 ] && grep -q '"exit_class": "watch-closed"' "$F/rec-wg.jsonl" \
   && grep -q '"cost_src": "transcript-estimate"' "$F/rec-wg.jsonl" && grep -q '"denials": "unknown"' "$F/rec-wg.jsonl" \
   && grep -q '"note": "closed by watch (wrapper gone)"' "$F/rec-wg.jsonl" \
   && [ "$(recfield "$F/rec-wg.jsonl" lane-closed duration_s)" != null ] \
   && grep -q 'ORPHAN-9911' "$STORE/spawn-records/run-test-wg-report-WG.md" \
   && printf '%s\n' "$WG" | grep -q '^lane run-test-wg/WG: .* watch-closed '; then
  ok "watch: a lane whose wrapper is gone is closed from its transcript (watch-closed, transcript-estimate, denials unknown), its report persisted, home and projects root taken from the record"
else no "watch closing an orphan  [exit $RC: $(printf '%s' "$WG" | head -2 | tr '\n' ' '); $(grep -o '"exit_class": "[a-z-]*"' "$F/rec-wg.jsonl")]"; fi
sleep 30 & LIVEPID=$!
printf '{"ts": "%s", "run": "run-test-wl", "lane": "WL", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "fixture-live", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' "$TS" "$LHOME" "$PROJ" > "$F/rec-wl.jsonl"
printf '{"ts": "%s", "run": "run-test-wl", "lane": "WL", "event": "lane-spawned", "session_id": "fixture-live", "pid": %s, "wrapper_pid": %s}\n' "$TS" "$LIVEPID" "$LIVEPID" >> "$F/rec-wl.jsonl"
WL=$($LANEV "$PY" "$LANE" watch --run run-test-wl --lane WL --record "$F/rec-wl.jsonl" --poll-s 1 --max-wait-s 2 2>&1); RC=$?
if [ "$RC" = 8 ] && printf '%s' "$WL" | grep -q 'still-running' && [ "$(events "$F/rec-wl.jsonl" lane-closed)" = 0 ]; then
  ok "watch never closes a lane whose wrapper is alive: still-running (exit 8), no close written (control for the orphan leg)"
else no "watch on a live wrapper  [exit $RC: $WL]"; fi
WL=$($LANEV "$PY" "$LANE" watch --run run-test-wl --lane WL --record "$F/rec-wl.jsonl" --poll-s 1 --max-wait-s 3 \
     --silence-s 5 --no-transcript-s 1 2>&1); RC=$?
if [ "$RC" = 8 ] && [ "$(events "$F/rec-wl.jsonl" unwatched)" = 1 ] && [ "$(events "$F/rec-wl.jsonl" lane-closed)" = 0 ] \
   && kill -0 "$LIVEPID" 2>/dev/null; then
  ok "watch with a threshold but no transcript to read writes one unwatched event and kills nothing"
else no "the unwatched path  [exit $RC, unwatched $(events "$F/rec-wl.jsonl" unwatched): $WL]"; fi

# kill ------------------------------------------------------------------------------------------
# The deliberate stop. A lane killed by hand wrote no lane-closed and every reader went on
# drawing it as running, so `kill` signals the recorded processes and writes the close itself.
# Every count below parses the record line by line: a key-pattern grep would count the same
# string appearing inside another field's value.
jevents(){ # record, event -> how many parsed lines carry that event
  "$PY" - "$1" "$2" <<'JEVENTS_TERMINATOR'
import json, sys
n = 0
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if isinstance(record, dict) and record.get("event") == sys.argv[2]:
        n += 1
print(n)
JEVENTS_TERMINATOR
}
# The liveness probe of these legs, with its stderr kept rather than dropped: `kill -0` on a
# missing binary would exit non-zero too, and a bare `! kill -0` would then read that as `the
# process is gone`. Every use below is paired with the opposite answer on the same run.
alive(){ if kill -0 "$1" 2>"$F/kill0.err"; then echo yes; else echo no; fi; }
killrec(){ # record path, run, lane, session, pid: the two lines a spawned lane leaves behind
  printf '{"ts": "%s", "run": "%s", "lane": "%s", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "%s", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' \
    "$TS" "$2" "$3" "$4" "$LHOME" "$PROJ" > "$1"
  printf '{"ts": "%s", "run": "%s", "lane": "%s", "event": "lane-spawned", "session_id": "%s", "pid": %s, "wrapper_pid": %s}\n' \
    "$TS" "$2" "$3" "$4" "$5" "$5" >> "$1"
}
TS=$(date +%Y-%m-%dT%H:%M:%S%z)
mkdir -p "$PROJ/$DASHED"
"$PY" - "$PROJ/$DASHED/fixture-killed.jsonl" <<'KILLED_TRANSCRIPT_TERMINATOR'
import json, sys
usage = {"input_tokens": 7, "cache_creation_input_tokens": 120, "cache_read_input_tokens": 3000,
         "output_tokens": 40}
with open(sys.argv[1], "w") as h:
    h.write(json.dumps({"type": "assistant", "effort": "high", "message": {
        "id": "k1", "model": "claude-sonnet-5", "role": "assistant", "usage": usage,
        "content": [{"type": "text", "text": "killed lane report text KILLED-4242"}]}}) + "\n")
KILLED_TRANSCRIPT_TERMINATOR
sleep 30 & KPID=$!
killrec "$F/rec-k1.jsonl" run-test-k1 K1 fixture-killed "$KPID"
KBEFORE=$(alive "$KPID")           # the same probe's other answer, one line before the kill
K1=$($LANEV "$PY" "$LANE" kill --run run-test-k1 --lane K1 --record "$F/rec-k1.jsonl" \
     --reason "the head stopped it: the brief named the wrong file" 2>&1); RC=$?
sleep 1
KAFTER=$(alive "$KPID")
if [ "$RC" = 0 ] && [ "$(jevents "$F/rec-k1.jsonl" lane-closed)" = 1 ] \
   && [ "$(recfield "$F/rec-k1.jsonl" lane-closed exit_class)" = '"killed"' ] \
   && [ "$(recfield "$F/rec-k1.jsonl" lane-closed exit_code)" = 3 ] \
   && [ "$(recfield "$F/rec-k1.jsonl" lane-closed killed_by)" = '"lane.py kill"' ] \
   && [ "$(recfield "$F/rec-k1.jsonl" lane-closed cost_src)" = '"transcript-estimate"' ] \
   && printf '%s' "$(recfield "$F/rec-k1.jsonl" lane-closed reason)" | grep -q 'the wrong file' \
   && grep -q 'KILLED-4242' "$STORE/spawn-records/run-test-k1-report-K1.md" \
   && [ "$KBEFORE" = yes ] && [ "$KAFTER" = no ]; then
  ok "kill: a running lane is signalled and closed with exit_class killed, the reason, the transcript estimate and its report persisted; the process was alive before the call and is gone after it"
else no "kill on a live lane  [exit $RC, closes $(jevents "$F/rec-k1.jsonl" lane-closed), class $(recfield "$F/rec-k1.jsonl" lane-closed exit_class), alive before/after $KBEFORE/$KAFTER: $(printf '%s' "$K1" | head -2 | tr '\n' ' ')]"; fi
if [ "$(recfield "$F/rec-k1.jsonl" lane-closed kill_grace_s)" = 5 ] \
   && printf '%s' "$K1" | grep -q '^lane run-test-k1/K1: .* killed '; then
  ok "kill: the close records the grace it waited and the command prints the lane's summary line"
else no "the kill summary  [grace $(recfield "$F/rec-k1.jsonl" lane-closed kill_grace_s): $(printf '%s' "$K1" | head -1)]"; fi
# premise: a lane the record does not carry. Nothing is signalled and nothing is written.
KN=$(wc -l < "$F/rec-k1.jsonl" | tr -d ' ')
K2=$($LANEV "$PY" "$LANE" kill --run run-test-k1 --lane NOSUCH --record "$F/rec-k1.jsonl" \
     --reason "a lane that is not there" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$K2" | grep -q 'is unknown in' \
   && [ "$(wc -l < "$F/rec-k1.jsonl" | tr -d ' ')" = "$KN" ]; then
  ok "kill: an unknown lane refuses (exit 2) and writes nothing (the record's line count is unchanged)"
else no "kill on an unknown lane  [exit $RC, lines $KN -> $(wc -l < "$F/rec-k1.jsonl" | tr -d ' '): $(printf '%s' "$K2" | head -1)]"; fi
# premise: a lane already closed — the one above, killed a moment ago.
K3=$($LANEV "$PY" "$LANE" kill --run run-test-k1 --lane K1 --record "$F/rec-k1.jsonl" \
     --reason "a second kill of the same lane" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$K3" | grep -q 'already closed' \
   && [ "$(jevents "$F/rec-k1.jsonl" lane-closed)" = 1 ] \
   && [ "$(wc -l < "$F/rec-k1.jsonl" | tr -d ' ')" = "$KN" ]; then
  ok "kill: a lane already closed refuses (exit 2) and writes no second close (still one lane-closed)"
else no "kill on a closed lane  [exit $RC, closes $(jevents "$F/rec-k1.jsonl" lane-closed): $(printf '%s' "$K3" | head -1)]"; fi
# premise: --reason is not optional. argparse refuses before any record is read.
K4=$($LANEV "$PY" "$LANE" kill --run run-test-k1 --lane K1 --record "$F/rec-k1.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$K4" | grep -q 'reason' \
   && [ "$(wc -l < "$F/rec-k1.jsonl" | tr -d ' ')" = "$KN" ]; then
  ok "kill: a kill with no --reason is refused (exit 2), so no kill reaches the record unexplained"
else no "kill without a reason  [exit $RC: $(printf '%s' "$K4" | head -1)]"; fi
# a recorded pid that has already gone: NOT a premise failure — the missing close is the point.
sh -c 'exit 0' & GONEPID=$!; wait "$GONEPID"
killrec "$F/rec-k5.jsonl" run-test-k5 K5 fixture-killed "$GONEPID"
K5=$($LANEV "$PY" "$LANE" kill --run run-test-k5 --lane K5 --record "$F/rec-k5.jsonl" \
     --reason "killed by hand from another terminal" 2>&1); RC=$?
if [ "$RC" = 0 ] && [ "$(jevents "$F/rec-k5.jsonl" lane-closed)" = 1 ] \
   && [ "$(recfield "$F/rec-k5.jsonl" lane-closed exit_class)" = '"killed"' ] \
   && printf '%s' "$K5" | grep -q 'already gone before the signal' \
   && printf '%s' "$K5" | grep -q 'the close is written anyway'; then
  ok "kill: a lane whose recorded pid has already gone is still closed, and one line on stdout says the pid had gone"
else no "kill on a gone pid  [exit $RC, closes $(jevents "$F/rec-k5.jsonl" lane-closed): $(printf '%s' "$K5" | head -2 | tr '\n' ' ')]"; fi
# two spawns of one lane name: the LAST spawn is the lane, and the earlier spawn's close does
# not stand in the way. The first spawn's process must survive, or the wrong pid was signalled.
sleep 30 & OLDPID=$!
sleep 30 & NEWPID=$!
killrec "$F/rec-k6.jsonl" run-test-k6 K6 fixture-killed "$OLDPID"
printf '{"ts": "%s", "run": "run-test-k6", "lane": "K6", "event": "lane-closed", "session_id": "fixture-killed", "exit_class": "completed", "exit_code": 0, "total_cost_usd": 0.5}\n' "$TS" >> "$F/rec-k6.jsonl"
printf '{"ts": "%s", "run": "run-test-k6", "lane": "K6", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "fixture-killed", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' "$TS" "$LHOME" "$PROJ" >> "$F/rec-k6.jsonl"
printf '{"ts": "%s", "run": "run-test-k6", "lane": "K6", "event": "lane-spawned", "session_id": "fixture-killed", "pid": %s, "wrapper_pid": %s}\n' "$TS" "$NEWPID" "$NEWPID" >> "$F/rec-k6.jsonl"
K6=$($LANEV "$PY" "$LANE" kill --run run-test-k6 --lane K6 --record "$F/rec-k6.jsonl" \
     --reason "the second spawn is the one running" 2>&1); RC=$?
sleep 1
K6PIDS=$(recfield "$F/rec-k6.jsonl" lane-closed killed_pids)
if [ "$RC" = 0 ] && [ "$(jevents "$F/rec-k6.jsonl" lane-closed)" = 2 ] \
   && printf '%s' "$K6PIDS" | grep -q "\"lane\": $NEWPID" \
   && [ "$(alive "$NEWPID")" = no ] && [ "$(alive "$OLDPID")" = yes ]; then
  ok "kill: with two spawns of one lane name the LAST spawn is the lane — its pid is signalled, the earlier spawn's process is untouched (the control), and the earlier close does not block the kill"
else no "kill across two spawns  [exit $RC, closes $(jevents "$F/rec-k6.jsonl" lane-closed), pids $K6PIDS: $(printf '%s' "$K6" | head -1)]"; fi
kill "$OLDPID" 2>"$F/kill0.err" || true    # the fixture's survivor: tidied away, not asserted on

# resume ----------------------------------------------------------------------------------------
printf 'Follow-up: say more.\n' > "$F/brief-follow.md"
RS=$($LANEV "$PY" "$LANE" resume --run run-test-b --lane L2 --brief "$F/brief-follow.md" --record "$F/rec-b.jsonl" \
     --home "$LHOME" 2>&1); RC=$?
SIDB=$(recfield "$F/rec-b.jsonl" lane-open session_id | tr -d '"')
if [ "$RC" = 0 ] && [ "$(argafter --resume)" = "$SIDB" ] && ! grep -qx -- '--session-id' "$A" \
   && [ "$(cat "$F/stub/stdin.txt")" = 'Follow-up: say more.' ] \
   && [ "$(argafter --model)" = sonnet ] && [ "$(argafter --effort)" = xhigh ] \
   && [ "$(events "$F/rec-b.jsonl" lane-resumed)" = 1 ] && [ "$(events "$F/rec-b.jsonl" lane-closed)" = 2 ] \
   && [ "$(recfield "$F/rec-b.jsonl" lane-closed resumed)" = true ] \
   && [ -f "$STORE/spawn-records/run-test-b-in-L2/run-test-b-brief-L2-resume-1.md" ]; then
  ok "resume re-enters the session (--resume <id>, the follow-up on stdin, the open's model and effort) and records lane-resumed plus a new lane-closed"
else no "resume  [exit $RC: $(printf '%s' "$RS" | head -3 | tr '\n' ' ')]"; fi
printf '{"run": "run-test-old", "lane": "O", "event": "lane-open", "class": "verifier"}\n{"run": "run-test-old", "lane": "O", "event": "lane-spawned", "session_id": "old-sid"}\n{"run": "run-test-old", "lane": "O", "event": "lane-closed", "ts": "2026-01-01T00:00:00+0000", "session_id": "old-sid"}\n' > "$F/rec-old.jsonl"
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-old --lane O --brief "$F/brief-follow.md" --record "$F/rec-old.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'resume window'; then
  ok "premise: resume refuses a lane whose last call is older than 55 min (exit 2)"
else no "resume of a lapsed lane  [exit $RC: $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-wl --lane WL --brief "$F/brief-follow.md" --record "$F/rec-wl.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'no lane-closed yet'; then
  ok "premise: resume refuses a lane that has not closed (exit 2)"
else no "resume of an open lane  [exit $RC: $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-b --lane NOPE --brief "$F/brief-follow.md" --record "$F/rec-b.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'unknown'; then
  ok "premise: resume refuses an unknown lane (exit 2)"
else no "resume of an unknown lane  [exit $RC: $ERR]"; fi

# D29: after a `limit` close the cache window is waived; every other class keeps it, and a lane
# whose transcript cannot be found is re-spawned rather than resumed.
agedclose(){ # source record, destination, exit_class, [session id override] -> a close 2 h old
  "$PY" - "$1" "$2" "$3" "${4-}" <<'AGED_CLOSE_TERMINATOR'
import json, sys, time
src, dst, cls, sid = sys.argv[1:5]
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - 2 * 3600))
records = []
for line in open(src):
    if not line.strip():
        continue
    record = json.loads(line)
    if sid and record.get("session_id"):
        record["session_id"] = sid
    if record.get("event") == "lane-closed":
        record["ts"] = ts
        record["exit_class"] = cls
    records.append(record)
with open(dst, "w") as handle:
    for record in records:
        handle.write(json.dumps(record) + "\n")
AGED_CLOSE_TERMINATOR
}
agedclose "$F/rec-b.jsonl" "$F/rec-limit.jsonl" limit
RS=$($LANEV "$PY" "$LANE" resume --run run-test-lim --lane L2 --brief "$F/brief-follow.md" \
     --record "$F/rec-limit.jsonl" --home "$LHOME" 2>&1); RC=$?
RAGE=$(recfield "$F/rec-limit.jsonl" lane-resumed age_s | cut -d. -f1)
if [ "$RC" = 0 ] && printf '%s' "$RS" | grep -q 'cache window is waived' \
   && [ "$(recfield "$F/rec-limit.jsonl" lane-resumed after_limit)" = true ] \
   && [ -n "$RAGE" ] && [ "$RAGE" -gt 3600 ]; then
  ok "D29: a lane closed on a limit 2 h ago resumes, prints the waiver, and records after_limit with age_s ($RAGE s)"
else no "D29 limit resume  [exit $RC, age $RAGE: $(printf '%s' "$RS" | head -3 | tr '\n' ' ')]"; fi
agedclose "$F/rec-b.jsonl" "$F/rec-comp.jsonl" completed
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-comp --lane L2 --brief "$F/brief-follow.md" \
      --record "$F/rec-comp.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'resume window'; then
  ok "D29: a completed close of the same age still refuses (the waiver is the limit class's alone — control for the leg above)"
else no "D29 non-limit close  [exit $RC: $ERR]"; fi
agedclose "$F/rec-b.jsonl" "$F/rec-nots.jsonl" limit fixture-no-transcript
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-nots --lane L2 --brief "$F/brief-follow.md" \
      --record "$F/rec-nots.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 're-spawn the lane'; then
  ok "D29: a limit close whose transcript is gone refuses with re-spawn (exit 2)"
else no "D29 missing transcript  [exit $RC: $ERR]"; fi
kill "$LIVEPID" 2>/dev/null; wait "$LIVEPID" 2>/dev/null

# the resumed call's reason (register, 2026-09-07) ------------------------------------------------
# The lane's reason has not changed, so `lane-resumed` carries the one its lane-open recorded and
# the command takes no flag. --reason is the override for a record that names no letter, and is
# refused against a record that carries one. Every assertion below parses the record with json.
spawn --run run-test-rr --lane RR --class verifier --grant "$F/granted" \
      --record "$F/rec-rr.jsonl" --reason '(c) context isolation, the resume leg' >/dev/null 2>&1
RS=$($LANEV "$PY" "$LANE" resume --run run-test-rr --lane RR --brief "$F/brief-follow.md" \
     --record "$F/rec-rr.jsonl" --home "$LHOME" 2>&1); RC=$?
RRSN=$(recfield "$F/rec-rr.jsonl" lane-resumed reason)
RRSRC=$(recfield "$F/rec-rr.jsonl" lane-resumed reason_src)
if [ "$RC" = 0 ] && [ "$RRSN" = '"(c) context isolation, the resume leg"' ] \
   && [ "$RRSN" = "$(recfield "$F/rec-rr.jsonl" lane-open reason)" ] && [ "$RRSRC" = '"lane-open"' ]; then
  ok "resume carries the lane-open reason onto lane-resumed with reason_src lane-open (both fields read by a json parse of the record)"
else no "resume reason carry-forward  [exit $RC, resumed $RRSN, src $RRSRC, open $(recfield "$F/rec-rr.jsonl" lane-open reason)]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-rr --lane RR --brief "$F/brief-follow.md" \
      --record "$F/rec-rr.jsonl" --home "$LHOME" --reason '(a) a different label' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'recorded reason stands' \
   && [ "$(events "$F/rec-rr.jsonl" lane-resumed)" = 1 ]; then
  ok "resume refuses --reason against a record that already carries one (exit 2, one line, no second lane-resumed)"
else no "resume --reason over a recorded reason  [exit $RC, resumes $(events "$F/rec-rr.jsonl" lane-resumed): $ERR]"; fi
# An older record: the same lane with the lane-open's reason dropped, as records written before
# the letter check carry it.
"$PY" - "$F/rec-rr.jsonl" "$F/rec-rn.jsonl" <<'DROP_REASON_TERMINATOR'
import json, sys
records = []
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    record = json.loads(line)
    if record.get("event") == "lane-open":
        record.pop("reason", None)
    records.append(record)
with open(sys.argv[2], "w") as handle:
    for record in records:
        handle.write(json.dumps(record) + "\n")
DROP_REASON_TERMINATOR
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-rn --lane RR --brief "$F/brief-follow.md" \
      --record "$F/rec-rn.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'carries no instrument-rule letter' \
   && [ "$(events "$F/rec-rn.jsonl" lane-resumed)" = 1 ]; then
  ok "resume of a record whose lane-open names no reason refuses without --reason (exit 2, the same message, nothing added to the record)"
else no "resume of a reasonless record  [exit $RC, resumes $(events "$F/rec-rn.jsonl" lane-resumed): $ERR]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-rn --lane RR --brief "$F/brief-follow.md" \
     --record "$F/rec-rn.jsonl" --home "$LHOME" --reason '(d) the override for an older record' 2>&1); RC=$?
RNSN=$(recfield "$F/rec-rn.jsonl" lane-resumed reason)
if [ "$RC" = 0 ] && [ "$RNSN" = '"(d) the override for an older record"' ] \
   && [ "$(recfield "$F/rec-rn.jsonl" lane-resumed reason_src)" != '"lane-open"' ] \
   && [ "$(events "$F/rec-rn.jsonl" lane-resumed)" = 2 ]; then
  ok "the same resume passes with --reason and records it as the override (control: the refusal above is the flag's absence, nothing else)"
else no "resume with the override  [exit $RC, reason $RNSN, src $(recfield "$F/rec-rn.jsonl" lane-resumed reason_src)]"; fi

# the per-call pick (owner ruling 2026-09-07 17:0x; built 2026-09-08) ----------------------------
# Under `auto` the row default is the ANCHOR: a departure on either axis needs --choice-reason, and
# the refusal comes before any record line, --dry-run included; a hand-set preset records
# `throttle <name>` or `explicit` and never asks. Every field below is read by a json parse of the
# record (recfield), never a grep. The fixture table's builder anchor is opus·xhigh; the resumed
# leg above pins the verifier's effort as xhigh for the same reason (both moved 2026-09-08).
pkspawn(){ spawn --class builder --write "$F/writable" "$@"; }
pkf(){ recfield "$F/rec-$1.jsonl" "$2" "$3"; }
pkspawn --run run-test-pk --lane PK1 --throttle auto --record "$F/rec-pk1.jsonl" --reason '(a) pick: no override' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk1 lane-open model_src)" = '"anchor"' ] && [ "$(pkf pk1 lane-open effort_src)" = '"anchor"' ] \
   && [ "$(pkf pk1 lane-open choice_reason)" = 'null' ] && [ "$(pkf pk1 lane-open throttle)" = '"auto"' ] \
   && [ "$(pkf pk1 lane-open row_default)" = '{"effort": "xhigh", "model": "opus"}' ]; then
  ok "auto, no override: model_src and effort_src read anchor, choice_reason null, row_default the anchor opus·xhigh"
else no "auto anchor pick  [exit $RC: $(pkf pk1 lane-open model_src)/$(pkf pk1 lane-open effort_src)/$(pkf pk1 lane-open choice_reason)/$(pkf pk1 lane-open row_default)]"; fi
pkspawn --run run-test-pk --lane PK2 --throttle auto --effort max --choice-reason 'design-heavy' \
        --record "$F/rec-pk2.jsonl" --reason '(a) pick: raised with a reason' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk2 lane-open effort_src)" = '"auto: design-heavy"' ] && [ "$(pkf pk2 lane-open model_src)" = '"anchor"' ] \
   && [ "$(pkf pk2 lane-open choice_reason)" = '"design-heavy"' ] && [ "$(pkf pk2 lane-open effort)" = '"max"' ] \
   && [ "$(argafter --effort)" = max ]; then
  ok "auto, --effort max with --choice-reason on the xhigh anchor: effort_src auto: design-heavy, model_src anchor, choice_reason recorded, the stub saw --effort max"
else no "auto reasoned departure  [exit $RC: $(pkf pk2 lane-open effort_src)/$(pkf pk2 lane-open model_src)/$(pkf pk2 lane-open choice_reason)]"; fi
PKN=$(wc -l < "$F/rec-pk2.jsonl" | tr -d ' ')
ERR=$(pkspawn --run run-test-pk --lane PK3 --throttle auto --effort max --record "$F/rec-pk2.jsonl" --reason '(a) pick: unreasoned' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF -- 'PROBE FAILED: --effort max departs from the anchor xhigh under throttle auto; pass --choice-reason' \
   && [ "$(wc -l < "$F/rec-pk2.jsonl" | tr -d ' ')" = "$PKN" ]; then
  ok "auto, --effort max with no --choice-reason is refused: exit 2, the message names the value and the anchor, no record line ($PKN lines before and after)"
else no "auto unreasoned departure  [exit $RC, lines $PKN -> $(wc -l < "$F/rec-pk2.jsonl" | tr -d ' '): $ERR]"; fi
ERR=$(pkspawn --run run-test-pk --lane PK3 --throttle auto --effort max --choice-reason '   ' --record "$F/rec-pk2.jsonl" --reason '(a) pick: whitespace reason' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF -- 'pass --choice-reason' && [ "$(wc -l < "$F/rec-pk2.jsonl" | tr -d ' ')" = "$PKN" ]; then
  ok "a whitespace-only --choice-reason is no reason: the same refusal, nothing recorded"
else no "whitespace choice reason  [exit $RC: $ERR]"; fi
pkspawn --run run-test-pk --lane PK4 --throttle auto --effort xhigh --record "$F/rec-pk4.jsonl" --reason '(a) pick: override equal to the anchor' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk4 lane-open effort_src)" = '"anchor"' ] && [ "$(pkf pk4 lane-open choice_reason)" = 'null' ]; then
  ok "auto, --effort xhigh equal to the anchor needs no reason and reads anchor (control: the refusal is the departure's, not the flag's)"
else no "auto override equal to the anchor  [exit $RC: $(pkf pk4 lane-open effort_src)]"; fi
ERR=$(pkspawn --run run-test-pk --lane PK5 --throttle auto --model fable --effort max --record "$F/rec-pk5.jsonl" --reason '(a) pick: both depart' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF -- '--model fable departs from the anchor opus and --effort max departs from the anchor xhigh under throttle auto; pass --choice-reason' \
   && [ ! -e "$F/rec-pk5.jsonl" ]; then
  ok "auto, both axes departing without a reason: one refusal naming both, no record file"
else no "auto both axes  [exit $RC, record $([ -e "$F/rec-pk5.jsonl" ] && echo written || echo absent): $ERR]"; fi
pkspawn --run run-test-pk --lane PK6 --throttle default --record "$F/rec-pk6.jsonl" --reason '(a) pick: hand-set, no override' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk6 lane-open model_src)" = '"throttle default"' ] && [ "$(pkf pk6 lane-open effort_src)" = '"throttle default"' ]; then
  ok "throttle default, no override: both sources read throttle default"
else no "hand-set, no override  [exit $RC: $(pkf pk6 lane-open model_src)/$(pkf pk6 lane-open effort_src)]"; fi
pkspawn --run run-test-pk --lane PK7 --throttle default --effort max --record "$F/rec-pk7.jsonl" --reason '(a) pick: hand-set, departure' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk7 lane-open effort_src)" = '"explicit"' ] && [ "$(pkf pk7 lane-open model_src)" = '"throttle default"' ] \
   && [ "$(pkf pk7 lane-open choice_reason)" = 'null' ]; then
  ok "throttle default, --effort max: effort_src explicit, choice_reason null, no refusal (a hand-set preset never asks)"
else no "hand-set departure  [exit $RC: $(pkf pk7 lane-open effort_src)/$(pkf pk7 lane-open choice_reason)]"; fi
pkspawn --run run-test-pk --lane PK8 --throttle default --effort max --choice-reason 'design-heavy' --record "$F/rec-pk8.jsonl" --reason '(a) pick: hand-set with a reason' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk8 lane-open effort_src)" = '"explicit"' ] && [ "$(pkf pk8 lane-open choice_reason)" = '"design-heavy"' ]; then
  ok "throttle default with --choice-reason: the text is recorded beside explicit"
else no "hand-set with a reason  [exit $RC: $(pkf pk8 lane-open effort_src)/$(pkf pk8 lane-open choice_reason)]"; fi
pkspawn --run run-test-pk --lane PK9 --throttle auto --model haiku --choice-reason 'probe' --record "$F/rec-pk9.jsonl" --reason '(a) pick: out of range with a reason' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk9 lane-open model_src)" = '"auto: probe"' ] && [ "$(pkf pk9 lane-open outside_options)" != 'null' ]; then
  ok "auto, an out-of-range --model with a reason keeps today's outside_options note beside model_src auto: probe"
else no "auto out of range  [exit $RC: $(pkf pk9 lane-open model_src)/$(pkf pk9 lane-open outside_options)]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-pk --lane PK2 --brief "$F/brief-follow.md" --record "$F/rec-pk2.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pk2 lane-resumed model_src)" = '"anchor"' ] && [ "$(pkf pk2 lane-resumed effort_src)" = '"auto: design-heavy"' ] \
   && [ "$(pkf pk2 lane-resumed choice_reason)" = '"design-heavy"' ] && [ "$(argafter --effort)" = max ]; then
  ok "resume copies model_src, effort_src and choice_reason from the lane-open onto lane-resumed and re-uses the pick (no new pick)"
else no "resume pick carry-forward  [exit $RC: $(pkf pk2 lane-resumed model_src)/$(pkf pk2 lane-resumed effort_src)/$(pkf pk2 lane-resumed choice_reason): $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi
# An older record: the same lane with the pick fields dropped from its lane-open and the resume
# above removed, as every record written before 2026-09-08 reads.
"$PY" - "$F/rec-pk2.jsonl" "$F/rec-pkold.jsonl" <<'DROP_PICK_TERMINATOR'
import json, sys
records = []
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    record = json.loads(line)
    if record.get("event") == "lane-resumed" or (record.get("event") == "lane-closed" and record.get("resumed")):
        continue
    if record.get("event") == "lane-open":
        for key in ("model_src", "effort_src", "choice_reason"):
            record.pop(key, None)
    records.append(record)
with open(sys.argv[2], "w") as handle:
    for record in records:
        handle.write(json.dumps(record) + "\n")
DROP_PICK_TERMINATOR
RS=$($LANEV "$PY" "$LANE" resume --run run-test-pk --lane PK2 --brief "$F/brief-follow.md" --record "$F/rec-pkold.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pkold lane-resumed model_src)" = '"unrecorded"' ] && [ "$(pkf pkold lane-resumed effort_src)" = '"unrecorded"' ] \
   && [ "$(pkf pkold lane-resumed choice_reason)" = 'null' ]; then
  ok "resume of a lane-open from before the pick fields records unrecorded/unrecorded/null (control for the copy above)"
else no "resume of a pre-fields record  [exit $RC: $(pkf pkold lane-resumed model_src)/$(pkf pkold lane-resumed effort_src): $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi
DRY=$(pkspawn --run run-test-pk --lane PKD --throttle auto --effort max --choice-reason 'design-heavy' --record "$F/rec-pkd.jsonl" --dry-run --reason '(a) pick: dry run' 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$DRY" | grep -qx 'model_src: anchor' && printf '%s\n' "$DRY" | grep -qx 'effort_src: auto: design-heavy' \
   && printf '%s\n' "$DRY" | grep -qx 'choice_reason: design-heavy' && printf '%s\n' "$DRY" | grep -qF '"effort_src": "auto: design-heavy"' \
   && [ ! -e "$F/rec-pkd.jsonl" ]; then
  ok "--dry-run prints model_src, effort_src and choice_reason on their own lines and on the record line it would write, and writes nothing"
else no "--dry-run pick lines  [exit $RC: $(printf '%s\n' "$DRY" | grep -E '^(model_src|effort_src|choice_reason):' | tr '\n' ' ')]"; fi
ERR=$(pkspawn --run run-test-pk --lane PKD --throttle auto --effort max --record "$F/rec-pkd.jsonl" --dry-run --reason '(a) pick: dry run unreasoned' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF -- 'pass --choice-reason' && ! printf '%s\n' "$ERR" | grep -q '^command:' && [ ! -e "$F/rec-pkd.jsonl" ]; then
  ok "--dry-run refuses an unreasoned departure the same way, before it prints anything"
else no "--dry-run refusal  [exit $RC: $(printf '%s' "$ERR" | head -2 | tr '\n' ' ')]"; fi
mkvault "$F/vault-nothr" '- **delegation**: single — the fixture regime'
printf '## Settings\n- **breadth**: standard\n- **delegation**: single — the fixture regime\n' > "$F/vault-nothr/CUSTOMISATION.md"
$LANEV CLAUDE_PROJECT_DIR="$F/vault-nothr" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" \
  --run run-test-pk --lane PKF --class builder --write "$F/writable" --record "$F/rec-pkf.jsonl" --reason '(a) pick: no Settings line' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pkf lane-open throttle)" = '"auto"' ] && [ "$(pkf pkf lane-open model_src)" = '"anchor"' ] && [ "$(pkf pkf lane-open throttle_note)" = 'null' ]; then
  ok "a vault with no throttle line spawns under auto, the default preset, with no note (the fallback moved from default on 2026-09-08)"
else no "the auto fallback  [exit $RC: $(pkf pkf lane-open throttle)/$(pkf pkf lane-open model_src)/$(pkf pkf lane-open throttle_note)]"; fi
pkspawn --run run-test-pk --lane PKU --throttle turbo --record "$F/rec-pku.jsonl" --reason '(a) pick: unknown throttle' >/dev/null 2>&1; RC=$?
if [ "$RC" = 0 ] && [ "$(pkf pku lane-open throttle)" = '"auto"' ] && printf '%s' "$(pkf pku lane-open throttle_note)" | grep -qF 'treated as `auto`'; then
  ok "an unknown throttle name is treated as auto and the record's throttle_note says so (control: the fallback leg above carries no note)"
else no "unknown throttle  [exit $RC: $(pkf pku lane-open throttle)/$(pkf pku lane-open throttle_note)]"; fi

# the limit class -------------------------------------------------------------------------------
env STUB_REPORT="You've hit your session limit · resets 8:50am (Europe/London)" STUB_ISERROR=1 $LANEV "$PY" "$LANE" spawn \
  --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-lm1 --lane LM1 \
  --class verifier --grant "$F/granted" --record "$F/rec-lm1.jsonl" --reason '(a) a limit stop' >/dev/null 2>&1
RC=$?
if [ "$RC" = 6 ] && grep -q '"exit_class": "limit"' "$F/rec-lm1.jsonl" \
   && grep -q '"limit_signal": "result text names a limit"' "$F/rec-lm1.jsonl"; then
  ok "a result naming a session limit closes as limit, exit 6"
else no "the limit class from the result text  [exit $RC]"; fi
env STUB_SYNTHETIC=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-lm2 --lane LM2 --class verifier --grant "$F/granted" \
  --record "$F/rec-lm2.jsonl" --reason '(a) a synthetic stop' >/dev/null 2>&1
RC=$?
if [ "$RC" = 6 ] && grep -q '"exit_class": "limit"' "$F/rec-lm2.jsonl" && grep -q '"limit_signal": "transcript: ' "$F/rec-lm2.jsonl"; then
  ok "a transcript whose last assistant record is a synthetic model with zero usage closes as limit, exit 6 (C2 N12)"
else no "the limit class from the transcript  [exit $RC: $(grep -o '"limit_signal": "[^"]*"' "$F/rec-lm2.jsonl")]"; fi
LONGLIMIT=$("$PY" -c 'print("the rate limit in the usage table is documented here; " * 12)')
env STUB_REPORT="$LONGLIMIT" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-lm3 --lane LM3 --class verifier --grant "$F/granted" \
  --record "$F/rec-lm3.jsonl" --reason '(a) control: a report that mentions limits' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && grep -q '"exit_class": "completed"' "$F/rec-lm3.jsonl"; then
  ok "a successful 108-word report that merely mentions a limit and usage is not a limit stop (control; a budget stop stays budget, leg 19)"
else no "the limit text guard  [exit $RC]"; fi

# --detach --------------------------------------------------------------------------------------
DT=$(env STUB_SLEEP_AFTER=4 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
     --projects-root "$PROJ" --run run-test-dt1 --lane D1 --class verifier --grant "$F/granted" \
     --silence-s 0 --record "$F/rec-dt1.jsonl" --reason '(a) detach, no wait' --detach --no-wait 2>&1); RC=$?
DPID=$(printf '%s\n' "$DT" | sed -n 's/^detached pid \([0-9][0-9]*\) session .*$/\1/p')
if [ "$RC" = 0 ] && [ -n "$DPID" ] && [ "$(printf '%s\n' "$DT" | grep -c .)" = 1 ]; then
  ok "--detach --no-wait prints one line (detached pid N session S) and returns 0 at once"
else no "--detach --no-wait  [exit $RC: $DT]"; fi
WD=$($LANEV "$PY" "$LANE" watch --run run-test-dt1 --lane D1 --record "$F/rec-dt1.jsonl" --poll-s 1 \
     --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$WD" | grep -q '^lane run-test-dt1/D1: .* completed ' \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-spawned wrapper_pid)" = "$DPID" ] \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-spawned detached)" = true ] \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-closed wrapper_pid)" = "$DPID" ]; then
  ok "watch on a detached lane waits for the worker's close; lane-spawned and lane-closed carry the worker's pid as wrapper_pid"
else no "watch on a detached lane  [exit $RC: $(printf '%s' "$WD" | head -2 | tr '\n' ' '); wrapper_pid $(recfield "$F/rec-dt1.jsonl" lane-spawned wrapper_pid) vs $DPID]"; fi
DT2=$(env STUB_EXIT=9 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-dt2 --lane D2 --class verifier --grant "$F/granted" \
      --silence-s 0 --poll-s 1 --record "$F/rec-dt2.jsonl" --reason '(a) detach, failing worker' --detach 2>&1); RC=$?
if [ "$RC" = 3 ] && printf '%s\n' "$DT2" | grep -q '^lane run-test-dt2/D2: .* error ' \
   && [ "$(recfield "$F/rec-dt2.jsonl" lane-spawned detached)" = true ]; then
  ok "--detach (waiting) stays as the watch over its worker and exits with the worker's code (3 for a stub exiting 9), printing the same summary line"
else no "--detach waiting on a failing worker  [exit $RC: $(printf '%s' "$DT2" | head -2 | tr '\n' ' ')]"; fi
DT3=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" \
      --run run-test-dt3 --lane D3 --class verifier --grant "$F/granted" --silence-s 0 --poll-s 1 \
      --record "$F/rec-dt3.jsonl" --reason '(a) detach, clean worker' --detach 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$DT3" | grep -q '^lane run-test-dt3/D3: .* completed '; then
  ok "--detach with a clean worker exits 0 with the summary (control)"
else no "--detach on a clean worker  [exit $RC: $(printf '%s' "$DT3" | head -2 | tr '\n' ' ')]"; fi
DT4=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" \
      --run run-test-dt4 --lane D4 --class no-such-class --grant "$F/granted" --poll-s 1 \
      --record "$F/rec-dt4.jsonl" --reason '(a) detach, premise failure' --detach 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$DT4" | grep -q 'unknown class' && [ ! -f "$F/rec-dt4.jsonl" ]; then
  ok "a detached worker's premise failure surfaces in the foreground (exit 2, its reason quoted, no record)"
else no "a detached premise failure  [exit $RC: $(printf '%s' "$DT4" | tail -2 | tr '\n' ' ')]"; fi
premise "--no-wait without --detach" "goes with --detach" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted" --no-wait

# ------------------------------------------------------------------- the fence, offline ------
echo "== fence =="
fence(){ # name, expect(allow|deny|silent), command, [grants], [writes]
  NAME="$1"; WANT="$2"; CMD="$3"; G="${4-$F/granted}"; W="${5-}"
  OUT=$(printf '%s' "$($PY - "$CMD" <<'FENCE_INPUT_TERMINATOR'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
FENCE_INPUT_TERMINATOR
)" | env LLM_WIKI_LANE_GRANTS="$G" LLM_WIKI_LANE_WRITES="$W" "$PY" "$FENCE")
  RC=$?
  if [ "$RC" != 0 ]; then no "fence exited $RC on: $NAME"; return; fi
  GOT=silent
  printf '%s' "$OUT" | grep -q '"permissionDecision": "deny"'  && GOT=deny
  printf '%s' "$OUT" | grep -q '"permissionDecision": "allow"' && GOT=allow
  if [ "$GOT" = "$WANT" ]; then ok "fence $WANT: $NAME"
  else no "fence $NAME  [want $WANT, got $GOT: $OUT]"; fi
}
fence "a read inside the grants"            allow "cat $F/granted/inside.txt"
fence "a read outside the grants"           deny  "cat $F/elsewhere/outside.txt"
fence "a relative escape"                   deny  "cat ../../etc/hosts"
fence "a write with no write grant"         deny  "echo x > $F/writable/f.txt"
fence "a write into /tmp"                   allow "echo x > /tmp/lane-scratch.txt"
fence "an invocation of claude"             deny  "claude -p 'hello'"
fence "an invocation of claude by path"     deny  "/usr/local/bin/claude -p 'hello'"
fence "a quoted redirect character in a read" allow "grep -n '>' $F/granted/inside.txt"
fence "a system binary reading a granted file" allow "/usr/bin/grep -c x $F/granted/inside.txt"
fence "a write inside the whitelist"        allow "echo x > $F/writable/f.txt" "$F/granted" "$F/writable"
fence "a write outside the whitelist"       deny  "echo x > $F/elsewhere/f.txt" "$F/granted" "$F/writable"
fence "rm outside the whitelist"            deny  "rm -f $F/elsewhere/outside.txt" "$F/granted" "$F/writable"
fence "sed -i with no write grant"          deny  "sed -i '' s/a/b/ $F/granted/inside.txt"
fence "tee with no write grant"             deny  "cat $F/granted/inside.txt | tee /etc/x"

# --- D33: heredoc bodies are data, quoted payload is not a path -------------------------------
# `hd` turns \n in its argument into real newlines, so a multi-line command reaches the fence
# without this suite writing one: printf, never a heredoc, since a heredoc here would be the very
# thing under test. Every path is derived from $F, so no leg carries a literal home path.
hd(){ printf '%b' "$1"; }
fence "a heredoc body carrying >, tee, claude, ~, rm -rf and an outside path, written into the write grant" \
  allow "$(hd "cat > $F/writable/f.md <<'EOF'\na > b and tee -a x and claude -p hi\n$F/elsewhere/secret and ~/private\nrm -rf /\nthe word EOF inside the body\nEOF\necho done")" \
  "$F/granted" "$F/writable"
fence "the same redirect on the command line proper still denies" \
  deny "$(hd "cat > $F/elsewhere/f.md <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same claude on the command line proper still denies" \
  deny "$(hd "claude -p hi <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same tee on the command line proper still denies" \
  deny "$(hd "cat <<'EOF' | tee /etc/hosts\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same outside path on the command line proper still denies" \
  deny "$(hd "cat $F/elsewhere/secret <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "two heredocs opened on one line, consumed in marker order" \
  allow "$(hd "diff <(cat <<'A'\n> $F/elsewhere/x claude\nA\n) <(cat <<'B'\ntee /etc/passwd\nB\n)")" \
  "$F/granted" "$F/writable"
fence "<<- with a tab-indented terminator ends the body there" \
  allow "$(hd "cat > $F/writable/g.md <<-END\n\tclaude > $F/elsewhere/x\n\tEND\necho ok")" \
  "$F/granted" "$F/writable"
fence "an unterminated heredoc is body to the end of the text" \
  allow "$(hd "cat > $F/writable/h.md <<'ZZ'\nclaude -p x > $F/elsewhere/y\ntee /etc/hosts")" \
  "$F/granted" "$F/writable"
fence "a heredoc marker with no body at all still leaves its command line checked" \
  deny "cat $F/elsewhere/secret <<EOF" "$F/granted" "$F/writable"
fence "a > inside a body whose own command line redirects outside the grants still denies" \
  deny "$(hd "cat > $F/elsewhere/out.md <<'EOF'\na > b\nEOF")" "$F/granted" "$F/writable"
fence "a quoted single path outside the grants is a path token" \
  deny "cat \"$F/elsewhere/secret\"" "$F/granted" "$F/writable"
fence "a mutator with a quoted spaced target outside the write roots" \
  deny "cp /tmp/a \"$F/elsewhere/a b\"" "$F/granted" "$F/writable"
fence "a quoted multi-word literal naming a path in a read command is payload" \
  allow "grep \"see $F/elsewhere/x for\" /tmp/a" "$F/granted" "$F/writable"
fence "a python one-liner in quotes carrying claude still denies (check 1 keeps content)" \
  deny "python3 -c \"import os; os.system('claude -p hi')\"" "$F/granted" "$F/writable"
fence "chmod +x a file inside the write grant (a +-led mode is not a path)" \
  allow "chmod +x $F/writable/f.md" "$F/granted" "$F/writable"
fence "chmod +x a variable target stays denied, fail-closed" \
  deny "chmod +x \"\$f\"" "$F/granted" "$F/writable"
fence "a quoted pattern carrying ^ is payload" \
  allow "grep '/^x/' /tmp/a" "$F/granted" "$F/writable"
fence "a quoted glob outside the grants is still a path token, cut to its directory" \
  deny "cat \"$F/elsewhere/*.md\"" "$F/granted" "$F/writable"

# --- D33 as amended by critic C2: N1 (one spaced path, not two words) and N3 (no variable target)
fence "N1: a spaced quoted path outside the grants is ONE path and denies" \
  deny "cat \"$F/elsewhere/Application Support/x\"" "$F/granted" "$F/writable"
fence "N1: a spaced quoted path inside the temp roots is allowed" \
  allow "cat \"/tmp/a b\"" "$F/granted" "$F/writable"
fence "N1: a quoted glob inside the write grant is cut to its directory and allowed (control for the deny above)" \
  allow "cat \"$F/writable/*.md\"" "$F/granted" "$F/writable"
fence "N3: a mutator target carrying a variable is denied outright" \
  deny "cp /tmp/a \"\$HOME/.zshrc\"" "$F/granted" "$F/writable"
fence "N3: a redirection target carrying a variable is denied outright" \
  deny "echo x > \"\$HOME/.zshrc\"" "$F/granted" "$F/writable"
fence "N3: a tee target carrying a variable is denied outright" \
  deny "cat /tmp/a | tee \"\$HOME/x\"" "$F/granted" "$F/writable"
fence "N3: two literal paths inside the write roots still pass (control for the three denies above)" \
  allow "cp /tmp/a /tmp/b" "$F/granted" "$F/writable"
fence "N11 (was the N1 residue): a letters-only quoted pattern in sed's script position is a pattern, not a path" \
  allow "sed -n '/foo/p' /tmp/a" "$F/granted" "$F/writable"

# --- N9: the false-deny classes on quoted arguments, each with its negative control ------------
# Five denials measured live (register, 2026-09-05 and 2026-09-06), each of which stopped a whole
# command line for a call that wrote nothing: a quoted `>` scanned as a redirection, a sanctioned
# quoted target whose blanking unbalanced the rest of the line, and a slash-led quoted pattern read
# as a path. Every control below is the deny the fix must keep, run on the same suite.
fence "N9: a quoted status prose holding an angle-bracket placeholder and a backticked word is no redirect" \
  allow "python3 $F/granted/vault-writes.py register add --status \"wrote <topic>/<page> \`date -u\`\"" \
  "$F/granted" "$F/writable"
fence "N9 control: a real redirect whose quoted target carries a substitution still denies (N3)" \
  deny "echo x > \"\`echo /etc/x\`\"" "$F/granted" "$F/writable"
fence "N9: an awk program whose slash-led quoted regex carries an action block is a pattern" \
  allow "awk '/## Open/{print \$2}' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 control: a slash-led quoted real path outside the grants is still a path (N1)" \
  deny "awk '{print}' \"/etc/passwd\"" "$F/granted" "$F/writable"
fence "N9: a compound whose quoted redirect target sits in the write grant, then a quoted placeholder" \
  allow "echo x > \"$F/writable/out.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "N9 control: the same compound with the quoted target outside the write grant still denies" \
  deny "echo x > \"$F/elsewhere/out.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "N9: a sed address range is a pattern, not a path" \
  allow "sed -n '/Open/,/Closed/p' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 control: an address range does not blind check 4 on the same line" \
  deny "sed -n '/Open/,/Closed/p' \"/etc/passwd\"" "$F/granted" "$F/writable"
fence "N9c: a read path built from a quoted shell variable joined to a literal subdirectory" \
  allow "grep -rn \"needle\" \"\$V\"/wiki" "$F/granted" "$F/writable"
fence "N9c control: a quoted literal directory glued to a name outside the grants still denies" \
  deny "cat \"$F/elsewhere\"/secret" "$F/granted" "$F/writable"

# N9 attack pass: each premise failure with the verdict it must get -----------------------------
fence "N9 attack: empty quotes in a redirect target position deny, fail-closed" \
  deny "echo x > \"\"" "$F/granted" "$F/writable"
fence "N9 attack: an unterminated quote hiding a redirect outside the writes still denies" \
  deny "echo \"a > $F/elsewhere/x.txt" "$F/granted" "$F/writable"
fence "N9 attack: a double-quoted string inside a single-quoted awk program is payload" \
  allow "awk 'BEGIN{print \"a > b\"}' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 attack: a pattern-shaped redirect target denies, fail-closed" \
  deny "echo x > \"/foo/,/bar/\"" "$F/granted" "$F/writable"
fence "N9 attack: a multi-segment path that looks pattern-ish is still a path" \
  deny "cat \"/etc/pam.d/sudo\"" "$F/granted" "$F/writable"
fence "N9 attack: a quoted path behind a glued flag is still a path token" \
  deny "grep -f\"/etc/patterns\" $F/granted/inside.txt" "$F/granted" "$F/writable"

# --- N11: the read side runs on the quote-aware segment tokens (register, 2026-09-06) -----------
# Case G of the probe in the store: a register close with a 700-character double-quoted status
# holding four apostrophes, an awk count with a caret-anchored slash-led pattern and a brace
# action, and a grep -c whose double-quoted pattern opens a parenthesis, denied live with the awk
# pattern named as a path; H, I and J are the probe's controls. Then the minimal reproducer of
# 2026-09-06 23:49 (a quoted slash-led grep pattern in a two-stage pipe), its two passing
# controls, and the plants that must stay denied on the same shapes.
N11S="closed - fixed by the builder lane and the heads: reflect-inputs writes the reflector's whole input set (turns.md, counts.json, the rendered waste-table.md and record-filtered.jsonl with every controls-phase observation dropped and the controls_checked, brief_copy, brief and plant keys stripped) into a directory outside the store and the projects root, refusing an --out inside either, and gains --dry-run; legs on the filtered copy, the stripped keys and a kept positive control; the delegate skill's Boundary reflection inputs paragraph and the reflect skill's hands-off paragraph name the form; the design page resolves D17 against D18 (2026-09-06); run 3's boundary reflections run in this form; the suite re-run from the vault by head 2"
N11CLOSE='cd "'"$F/granted"'" && V="'"$F/granted"'" && python3 -B .claude/skills/delegate/vault-writes.py register close --vault "$V" --date 2026-09-06 --match "the reflector lane is not blind" --status "'"$N11S"'" 2>&1 | tail -1 | cut -c1-160'
N11AWK1='echo "== open entries dated 2026-09-05/06 now:" && awk '"'"'/^## Open/{f=1} /^## Closed/{f=0} f'"'"' wiki/developments/known-issues.md | grep "^### \[2026-09-0[56]\]" | cut -c1-110'
N11AWK2='echo "== closed today:" && awk '"'"'/^## Closed/{f=1} f'"'"' wiki/developments/known-issues.md | grep -c "(2026-09-06: closed"'
fence "N11 case G: the live compound (a 700-character quoted status with four apostrophes; an awk count; a grep -c whose quoted pattern opens a parenthesis)" \
  allow "$N11CLOSE; $N11AWK1; $N11AWK2" "$F/granted" "$F/writable"
fence "N11 control H: the two awk calls without the close" \
  allow "cd \"$F/granted\" && $N11AWK1; $N11AWK2" "$F/granted" "$F/writable"
fence "N11 control I: the parenthesis grep alone" \
  allow "cd \"$F/granted\" && $N11AWK2" "$F/granted" "$F/writable"
fence "N11 control J: a real copy outside the writes on the same checker still denies" \
  deny "cp /tmp/a $F/elsewhere/x" "$F/granted" "$F/writable"
fence "N11 reproducer: a quoted slash-led grep pattern in a two-stage pipe is a pattern, not a path" \
  allow "printf 'a\\n' | grep -v \"/log.md:\"" "$F/granted" "$F/writable"
fence "N11 control: the same pattern without the slash" \
  allow "printf 'a\\n' | grep -v \"log.md:\"" "$F/granted" "$F/writable"
fence "N11 control: a slash-led pattern under a temp root" \
  allow "printf 'a\\n' | grep -v \"/tmp/x:\"" "$F/granted" "$F/writable"
fence "N11 plant: the reproducer redirected outside the write roots still denies (check 2)" \
  deny "printf 'a\\n' | grep -v \"/log.md:\" > $F/elsewhere/out" "$F/granted" "$F/writable"
fence "N11 plant: a file operand after the pattern, outside the grants, still denies" \
  deny "grep -v \"/log.md:\" $F/elsewhere/secret" "$F/granted" "$F/writable"
fence "N11 plant: -e supplies the pattern, so a quoted slash-led operand is a file and denies" \
  deny "grep -e x \"$F/elsewhere/secret\"" "$F/granted" "$F/writable"
fence "N11 plant: -f names a pattern file outside the grants and denies" \
  deny "grep -f \"$F/elsewhere/patterns\" /tmp/a" "$F/granted" "$F/writable"
fence "N11 residue: an unquoted slash-led pattern keeps today's reading and denies" \
  deny "grep -v /log.md: /tmp/a" "$F/granted" "$F/writable"
fence "N11: an interpreter segment in a compound keeps its program as tokens (the payload rule is per segment)" \
  deny "cd /tmp && python3 -c \"open('$F/elsewhere/secret').read()\"" "$F/granted" "$F/writable"
fence "N11: a grep -c in one segment no longer makes another segment's python3 an interpreter payload" \
  allow "python3 -B $F/granted/run.py | grep -c \"/^## Open/\"" "$F/granted" "$F/writable"

# --- the mutator check is scoped to the mutator's own segment and its target arguments ---------
# The head hit the whole-command form live on 2026-09-05: `cd <vault> && … && mkdir -p /tmp/a`
# denied with "`mkdir` targets `cd`", every later token read as a target.
fence "a compound line whose only write is inside the write grant" \
  allow "cd $F/granted && echo x && mkdir -p /tmp/lane-compound && python3 -B run.py" "$F/granted" /tmp
fence "cp reads a granted source and writes a granted target (the source is a read, not a target)" \
  allow "cp $F/granted/inside.txt /tmp/lane-copy" "$F/granted" /tmp
fence "cp whose TARGET is outside the write roots still denies" \
  deny "cp /tmp/a $F/elsewhere/b" "$F/granted" /tmp
fence "a second segment's mutator is checked on its own target" \
  deny "mkdir -p /tmp/a && cp /tmp/a/x $F/elsewhere/z" "$F/granted" /tmp
fence "a mutator after a sanctioned redirect is still checked" \
  deny "echo x > /tmp/a; rm -rf $F/elsewhere" "$F/granted" /tmp
fence "a leading VAR=value assignment does not hide the mutator" \
  allow "VAR=1 rm -rf /tmp/lane-scratch" "$F/granted" /tmp
fence "a prefix word does not hide the mutator either" \
  deny "sudo rm -rf $F/elsewhere" "$F/granted" /tmp

# --- N10: the mutator scan reads TOKENS, and an operand that names no file is not a target ------
# Three denials measured live on 2026-09-06, each on a command line that ran nothing: quoted prose
# whose `;` started a segment and whose next word was `cp`; a heredoc body inside a QUOTED command
# substitution (a `<<` inside quotes opens no heredoc, so the body stayed text), whose `install`
# line was read as a command; and `chmod 644 <file in W>`, whose MODE was read as a relative path
# and denied as a target outside W. Every allow below is paired with the deny it must keep, and
# the controls grant READ on the outside directory so the deny can only come from the write rule.
fence "N10: a mutator word inside another command's quoted prose is prose, not a command" \
  allow "python3 $F/granted/vault-writes.py register add --status \"compiled the page; cp of the fixture into $F/elsewhere/notes.md\"" \
  "$F/granted" "$F/writable"
fence "N10 control: the same cp as a command still denies on its target" \
  deny "python3 $F/granted/vault-writes.py register add --status compiled; cp $F/granted/inside.txt $F/elsewhere/notes.md" \
  "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a heredoc body inside a quoted command substitution is payload, not commands" \
  allow "$(hd "python3 $F/granted/note.py --text \"\$(cat <<'EOF'\ninstall -m 644 lane-fence.py $F/elsewhere/delegate/\nthe head runs that line; this lane does not\nEOF\n)\"")" \
  "$F/granted" "$F/writable"
fence "N10 control: the same install line as a command still denies on its target" \
  deny "$(hd "python3 $F/granted/note.py --text ok\ninstall -m 644 $F/granted/inside.txt $F/elsewhere/delegate/x")" \
  "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: chmod writes its FILE — an octal mode is a mode, not a relative path" \
  allow "chmod 644 $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: the same mode with the file outside the writes still denies" \
  deny "chmod 644 $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a mode that is also a plausible file name — the SECOND operand is what chmod writes" \
  allow "chmod 755 $F/writable/755" "$F/granted" "$F/writable"
fence "N10 control: the same shape with the second operand outside the writes denies" \
  deny "chmod 755 $F/elsewhere/755" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a symbolic mode with commas is a mode" \
  allow "chmod u+x,g-w $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: a symbolic mode with commas over a file outside the writes denies" \
  deny "chmod u+x,g-w $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: chown -R takes its owner spec after the flag, and the spec is no path" \
  allow "chown -R alice:staff $F/writable/d" "$F/granted" "$F/writable"
fence "N10 control: the same owner spec with the target outside the writes denies" \
  deny "chown -R alice:staff $F/elsewhere/d" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a chgrp group spec is a group, not a relative path" \
  allow "chgrp staff $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: chgrp with the target outside the writes denies" \
  deny "chgrp staff $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: install -m consumes its mode, and the last operand is the file it creates" \
  allow "install -m 644 $F/granted/inside.txt $F/writable/b" "$F/granted" "$F/writable"
fence "N10 control: install -m with the created file outside the writes denies" \
  deny "install -m 644 $F/granted/inside.txt $F/elsewhere/b" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: install -d creates EVERY operand, all of them inside the writes" \
  allow "install -d $F/writable/a $F/writable/b $F/writable/c" "$F/granted" "$F/writable"
fence "N10 control: install -d denies when one operand is outside the writes" \
  deny "install -d $F/writable/a $F/elsewhere/b" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a quoted single-path target inside the writes stays a target and passes" \
  allow "cp $F/granted/inside.txt \"$F/writable/b\"" "$F/granted" "$F/writable"
fence "N10 control: the same quoted single-path target outside the writes still denies" \
  deny "cp $F/granted/inside.txt \"$F/elsewhere/b\"" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a real write hides in a glued target-directory flag, and denies on that directory" \
  deny "cp -t\"$F/granted/sub\" $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N10 control: the same glued flag naming a directory inside the writes passes" \
  allow "cp -t\"$F/writable\" $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N10: a glued path behind a flag that takes no value is no write (the command reads the whole word as options and errors)" \
  allow "rm -rf\"$F/granted/sub\"" "$F/granted" "$F/writable"
fence "N10: dd writes its of= operand and reads its if= one" \
  allow "dd if=$F/granted/inside.txt of=$F/writable/copy.img bs=4k count=1" "$F/granted" "$F/writable"
fence "N10 control: dd with of= outside the writes denies" \
  deny "dd if=$F/granted/inside.txt of=$F/elsewhere/copy.img" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: touch -r takes a reference FILE as its value, never as its target" \
  allow "touch -r $F/granted/inside.txt $F/writable/f" "$F/granted" "$F/writable"
fence "N10 control: touch with its target outside the writes denies" \
  deny "touch -r $F/granted/inside.txt $F/elsewhere/f" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10 attack: an empty quoted target writes nothing and keeps its verdict" \
  allow "cp $F/granted/inside.txt \"\"" "$F/granted" "$F/writable"
fence "N10 attack: an unterminated quote round a target outside the writes still denies" \
  deny "cp $F/granted/inside.txt \"$F/elsewhere/x" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10 attack: nested quotes round prose naming a mutator and two paths read nothing" \
  allow "python3 $F/granted/x.py --status \"it's cp $F/elsewhere/a $F/elsewhere/b, not run\"" \
  "$F/granted" "$F/writable"
fence "N10 attack: a mutator's own diagnostics redirect is not one of its operands" \
  allow "rm -f $F/writable/x 2>/dev/null" "$F/granted" "$F/writable"

# --- D33 attack pass: planted smuggles, each with the verdict it must get ----------------------
fence "attack: a # <<EOF comment opens no heredoc, so the lines beneath it are commands" \
  deny "$(hd "# <<EOF\nrm -rf $F/elsewhere/important\nEOF")" "$F/granted" "$F/writable"
fence "attack: a << inside quotes opens no heredoc either" \
  deny "$(hd "echo \"a << EOF here\"\ncat $F/elsewhere/secret")" "$F/granted" "$F/writable"
fence "attack: a terminator with a trailing space does not end the body (the shell agrees: the line beneath never runs)" \
  allow "$(hd "cat > $F/writable/a.md <<'EOF'\nbody\nEOF \ncat $F/elsewhere/secret")" "$F/granted" "$F/writable"
fence "attack: a backslash-continued line hiding a redirect outside the grants" \
  deny "$(hd "cat /tmp/a \\\\\n  > $F/elsewhere/out.txt")" "$F/granted" "$F/writable"
fence "attack: a heredoc opened on a continued line, a mutator after the terminator" \
  deny "$(hd "cat > $F/writable/b.md \\\\\n<<'EOF'\nbody > $F/elsewhere/x\nEOF\nrm -f $F/elsewhere/important")" "$F/granted" "$F/writable"
fence "attack: a command substitution naming an outside path" \
  deny "cat \$(echo $F/elsewhere/secret)" "$F/granted" "$F/writable"
fence "attack: an interpreter payload (sh -c) keeps its content for the read checks" \
  deny "sh -c \"cat $F/elsewhere/secret\"" "$F/granted" "$F/writable"
fence "attack: a /-led quoted target carrying a variable is one path token and is checked" \
  deny "cat \"$F/elsewhere/\$f\"" "$F/granted" "$F/writable"
fence "attack: a \$-led quoted target is the named read-side false-allow (the fence cannot expand it)" \
  allow "cat \"\$HOME/Library/Application Support/x\"" "$F/granted" "$F/writable"
fence "attack: a here-STRING is not a heredoc and its word is still a path token" \
  deny "cat <<< $F/elsewhere/secret" "$F/granted" "$F/writable"
fence "attack: a bare terminator ends the body, so the tee beneath it is checked" \
  deny "$(hd "cat > $F/writable/c.md <<EOF\ntee /etc/hosts\nEOF\ncat /tmp/a | tee /etc/hosts")" "$F/granted" "$F/writable"
fence "attack: nested quotes round a spaced literal naming a path read nothing" \
  allow "grep \"it's $F/elsewhere/secret\" /tmp/a" "$F/granted" "$F/writable"
fence "attack: a mutator whose target is a variable stays denied, fail-closed" \
  deny "cp /tmp/a \"\$DEST/b\"" "$F/granted" "$F/writable"

# --- D34: the head role (--head) --------------------------------------------------------------
hfence(){ # name, expect(silent|deny|allow), command, [grants], [writes] — the same checker, --head
  HNAME="$1"; HWANT="$2"; HCMD="$3"; HG="${4-$F/granted}"; HW="${5-}"
  OUT=$(printf '%s' "$($PY - "$HCMD" <<'HEAD_FENCE_INPUT_TERMINATOR'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
HEAD_FENCE_INPUT_TERMINATOR
)" | env LLM_WIKI_LANE_GRANTS="$HG" LLM_WIKI_LANE_WRITES="$HW" "$PY" "$FENCE" --head)
  RC=$?
  if [ "$RC" != 0 ]; then no "head fence exited $RC on: $HNAME"; return; fi
  GOT=silent
  printf '%s' "$OUT" | grep -q '"permissionDecision": "deny"'  && GOT=deny
  printf '%s' "$OUT" | grep -q '"permissionDecision": "allow"' && GOT=allow
  if [ "$GOT" = "$HWANT" ]; then ok "head fence $HWANT: $HNAME"
  else no "head fence $HNAME  [want $HWANT, got $GOT: $OUT]"; fi
}
hfence "a cleared command is silent, never an explicit allow" \
  silent "cat $F/granted/inside.txt" "$F/granted" "$F/writable"
hfence "a head may invoke claude (check 1 is off)" \
  silent "claude -p 'spawn a lane'" "$F/granted" "$F/writable"
hfence "git is the head's X grant" silent "git status --short" "$F/granted" "$F/writable"
hfence "a read outside the grants is the same deny as a lane's" \
  deny "cat $F/elsewhere/secret" "$F/granted" "$F/writable"
hfence "a write outside the write grant is the same deny as a lane's" \
  deny "echo x > $F/elsewhere/f.txt" "$F/granted" "$F/writable"
hfence "N9: the head's own compound — a quoted target in the writes, then a quoted placeholder" \
  silent "echo x > \"$F/writable/o.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "the lane role still answers a cleared command with an explicit allow (control for the silence above)" \
  allow "cat $F/granted/inside.txt" "$F/granted" "$F/writable"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p hi"}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" LLM_WIKI_FENCE_ROLE=head "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "LLM_WIKI_FENCE_ROLE=head selects the head role without the flag"
else no "the head role from the environment  [exit $RC: $OUT]"; fi

# fail-closed and the premise cases
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' \
      | env -u LLM_WIKI_LANE_GRANTS -u LLM_WIKI_LANE_WRITES "$PY" "$FENCE")
if printf '%s' "$OUT" | grep -q 'lane-fence: no grants in environment'; then
  ok "fence fails closed with no grants in the environment"
else no "fence did not fail closed  [$OUT]"; fi
OUT=$(printf 'not json at all' | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE")
printf '%s' "$OUT" | grep -q 'hook input unreadable' \
  && ok "fence denies unreadable hook input" || no "fence allowed unreadable input  [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{}}' | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE")
printf '%s' "$OUT" | grep -q 'no command in hook input' \
  && ok "fence denies a Bash event carrying no command" || no "fence allowed a command-less event  [$OUT]"
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "fence stays silent on a non-Bash tool"
else no "fence spoke on a non-Bash tool  [exit $RC: $OUT]"; fi
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"   "}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "fence stays silent on an empty command"
else no "fence spoke on an empty command  [exit $RC: $OUT]"; fi

# ------------------------------------------------------------ cost caps, two tiers per class --
# routing.json's per-class `cost` block: a SOFT threshold logged at close and never a stop, and
# a HARD stop passed as --max-budget-usd (the smaller of 5 x the class's usual cost and the run's
# envelope remainder; else 5 x usual alone; a class without figures takes the breadth tier), which
# an explicit --budget-usd may RAISE and never lower (owner ruling, 2026-09-07); and the head's own
# --expect-usd, which replaces the class figure as the soft line and is never a stop. Every figure a
# leg asserts is set in this fixture table, so
# the legs hold whatever the shipped table says. recraw prints a record string with its non-ASCII
# kept (json.dumps escapes the multiplication sign in the record), so the expected hard_src
# strings below carry the character itself.
echo "== cost caps =="
"$PY" - "$F" <<'COST_FIXTURE_TERMINATOR'
import json, sys
root = sys.argv[1]
table = json.load(open(root + "/routing-v2.json"))
def block(soft, usual):
    return {"soft_usd": soft, "usual_usd": usual, "n": 3, "window": "2026-09-04..2026-09-06",
            "source": "fixture figures, not the shipped table"}
table["classes"]["verifier"]["cost"] = block(0.10, 0.05)   # the stub bills $0.12: over this soft
table["classes"]["builder"]["cost"] = block(5.0, 2.0)      # hard 5 x 2.0 = $10 unless something is smaller
table["classes"]["memory-hunter"]["cost"] = block(1.0, 0.05)   # 5 x usual = $0.25, UNDER the soft: the max() base (F1)
# planner keeps no cost block: the breadth-tier fallback
with open(root + "/routing-cost.json", "w") as handle:
    json.dump(table, handle, indent=1)
bad = json.loads(json.dumps(table))
bad["classes"]["builder"]["cost"]["usual_usd"] = "2.0"
with open(root + "/routing-badcost.json", "w") as handle:
    json.dump(bad, handle)
COST_FIXTURE_TERMINATOR
RCOST="$F/routing-cost.json"
recraw(){ # record, event, key -> the key's value as JSON with non-ASCII kept, from the LAST such event
  "$PY" - "$1" "$2" "$3" <<'RECRAW_TERMINATOR'
import json, sys
value = None
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("event") == sys.argv[2] and sys.argv[3] in record:
        value = record[sys.argv[3]]
print(json.dumps(value, sort_keys=True, ensure_ascii=False))
RECRAW_TERMINATOR
}

OUT=$(spawn --routing "$RCOST" --run run-test-cap --lane SOFT --class verifier --grant "$F/granted" \
      --record "$F/rec-cap.jsonl" --reason '(a) soft cap' 2>&1); RC=$?
SX=$(recfield "$F/rec-cap.jsonl" lane-closed soft_exceeded); SU=$(recfield "$F/rec-cap.jsonl" lane-closed soft_usd)
if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qF 'soft-cap: $0.12 over $0.10 (class verifier)' \
   && [ "$SX" = true ] && [ "$SU" = 0.1 ] \
   && [ "$(recfield "$F/rec-cap.jsonl" lane-closed exit_class)" = '"completed"' ]; then
  ok "soft cap: a close billed over the class's soft_usd is logged on the close line and in lane-closed (soft_usd $SU, soft_exceeded $SX), and the lane still completes at exit 0"
else no "soft cap  [exit $RC, soft_usd $SU, soft_exceeded $SX: $(printf '%s' "$OUT" | head -1)]"; fi

spawn --routing "$RCOST" --run run-test-cap --lane HARD --class builder --write "$F/writable" \
      --record "$F/rec-cap.jsonl" --reason '(a) hard cap' >/dev/null 2>&1; RC=$?
HU=$(recfield "$F/rec-cap.jsonl" lane-open hard_usd); HS=$(recraw "$F/rec-cap.jsonl" lane-open hard_src)
BU=$(recfield "$F/rec-cap.jsonl" lane-open budget_usd)
SX=$(recfield "$F/rec-cap.jsonl" lane-closed soft_exceeded); SU=$(recfield "$F/rec-cap.jsonl" lane-closed soft_usd)
SS=$(recraw "$F/rec-cap.jsonl" lane-closed soft_src)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$BU" = 10.0 ] && [ "$(argafter --max-budget-usd)" = 10.0 ] \
   && [ "$HS" = '"5 × usual $2.00 (envelope unmetered: no run-open event in the run record)"' ] \
   && [ "$SX" = false ] && [ "$SU" = 5.0 ] && [ "$SS" = '"class"' ]; then
  ok "CONTROL for the --expect-usd legs below, and the multiplier's own leg: a spawn with NEITHER flag takes 5 x usual (\$10.00) as --max-budget-usd, records it as hard_usd (= budget_usd) with its hard_src, and measures the close against the class figure (soft_usd $SU, soft_src $SS, soft_exceeded false)"
else no "hard stop, no envelope  [exit $RC, hard_usd $HU, budget_usd $BU, argv $(argafter --max-budget-usd), hard_src $HS, soft $SU/$SX]"; fi

# A run record with an envelope and a head-exit carrying spent_usd: envelope_left returns the
# remainder without metering (its own head-exit path), and the smaller figure decides.
mkdir -p "$SR"
REC="$SR/run-test-env.jsonl"
printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-env", "event": "run-open", "session": "head-sid-1", "envelope_usd": 30.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-env", "event": "head-exit", "session_id": "head-sid-1", "spent_usd": 25.0}' > "$REC"
spawn --routing "$RCOST" --run run-test-env --lane ENV --class builder --write "$F/writable" --reason '(a) envelope' >/dev/null 2>&1; RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] && [ "$(argafter --max-budget-usd)" = 5.0 ] \
   && [ "$HS" = '"envelope remainder $5.00 (envelope $30.00, spent $25.00; below 5 × usual $10.00)"' ]; then
  ok "hard stop under an envelope: the remainder (\$30 minus \$25 spent over the head-exits, read without metering) beats 5 x usual when smaller, and hard_src says so"
else no "hard stop, envelope  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS]"; fi

printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-big", "event": "run-open", "session": "head-sid-2", "envelope_usd": 1000.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-big", "event": "head-exit", "session_id": "head-sid-2", "spent_usd": 10.0}' > "$SR/run-test-big.jsonl"
spawn --routing "$RCOST" --run run-test-big --lane BIG --class builder --write "$F/writable" --reason '(a) big envelope' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-big.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-big.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$HS" = '"5 × usual $2.00 (class builder)"' ]; then
  ok "the hard stop reads 5 x usual where that exceeds the soft threshold: under an envelope with more left (\$990) than the multiple, 5 x \$2.00 = \$10.00 decides over the class's \$5.00 soft threshold and hard_src names the class (control: the remainder leg above took the envelope)"
else no "class multiple under a large envelope  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

# Raise-only (owner ruling, 2026-09-07): --budget-usd may lift a lane's hard stop over the value
# its class composed and never set it below, because an explicit cap read as a sizing guess put a
# builder at $6 under its class's $18.22 soft threshold (known-issues, 2026-09-07). The class value
# on this record is the envelope remainder, $5.00: the three legs are above it, below it and equal.
OUT=$(spawn --routing "$RCOST" --run run-test-env --lane EXPUP --class builder --write "$F/writable" --budget-usd 12 --reason '(a) explicit, raising' 2>&1); RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 12.0 ] && [ "$(argafter --max-budget-usd)" = 12.0 ] \
   && printf '%s' "$HS" | grep -q '^"explicit --budget-usd (raised over class \$5\.00: .*)"$' \
   && ! printf '%s' "$OUT" | grep -q 'cap is kept'; then
  ok "an explicit --budget-usd ABOVE the class value wins and says what it raised over: \$12 reaches the CLI, hard_src reads the raised form naming the \$5.00 class value, and no kept-note is printed"
else no "explicit budget, raising  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS: $(printf '%s' "$OUT" | head -1)]"; fi

OUT=$(spawn --routing "$RCOST" --run run-test-env --lane EXPDN --class builder --write "$F/writable" --budget-usd 1.5 --reason '(a) explicit, lowering' 2>&1); RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] && [ "$(argafter --max-budget-usd)" = 5.0 ] \
   && printf '%s' "$HS" | grep -q '^"explicit --budget-usd \$1\.50 at or below class cap \$5\.00: class cap kept (.*)"$' \
   && printf '%s' "$OUT" | grep -qF -- '--budget-usd $1.50 is at or below this class' \
   && printf '%s' "$OUT" | grep -qF 'the class cap is kept'; then
  ok "an explicit --budget-usd BELOW the class value is refused as a lowering: the \$5.00 class cap is what reaches the CLI, hard_src records both figures and the refusal, and the spawn prints one line saying so (the defect of 2026-09-07: an explicit \$6 under an \$18.22 soft threshold)"
else no "explicit budget, lowering  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS: $(printf '%s' "$OUT" | head -1)]"; fi

OUT=$(spawn --routing "$RCOST" --run run-test-env --lane EXPEQ --class builder --write "$F/writable" --budget-usd 5 --reason '(a) explicit, equal' 2>&1); RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] \
   && printf '%s' "$HS" | grep -q '^"explicit --budget-usd \$5\.00 at or below class cap \$5\.00: class cap kept (.*)"$' \
   && printf '%s' "$OUT" | grep -qF 'the class cap is kept'; then
  ok "premise: --budget-usd EQUAL to the class value is kept, not raised — equal is not above, the note is printed and the record shows the refusal rather than an indistinguishable \$5.00"
else no "explicit budget, equal  [exit $RC, hard_usd $HU, hard_src $HS: $(printf '%s' "$OUT" | head -1)]"; fi

# --expect-usd (owner ruling, 2026-09-07): the head's own estimate becomes the lane's soft line and
# is NEVER a stop. The stub bills $0.12, so an estimate under it must be flagged and must not kill.
OUT=$(spawn --routing "$RCOST" --run run-test-cap --lane EXPECT --class builder --write "$F/writable" \
      --record "$F/rec-cap.jsonl" --expect-usd 0.05 --reason '(a) expect under the bill' 2>&1); RC=$?
SU=$(recfield "$F/rec-cap.jsonl" lane-closed soft_usd); SX=$(recfield "$F/rec-cap.jsonl" lane-closed soft_exceeded)
SS=$(recraw "$F/rec-cap.jsonl" lane-closed soft_src); EU=$(recfield "$F/rec-cap.jsonl" lane-open expect_usd)
HU=$(recfield "$F/rec-cap.jsonl" lane-open hard_usd)
if [ "$RC" = 0 ] && [ "$EU" = 0.05 ] && [ "$SU" = 0.05 ] && [ "$SX" = true ] && [ "$SS" = '"expect"' ] \
   && [ "$HU" = 10.0 ] && [ "$(argafter --max-budget-usd)" = 10.0 ] \
   && printf '%s' "$OUT" | grep -qF 'soft-cap: $0.12 over $0.05 (expect)' \
   && [ "$(recfield "$F/rec-cap.jsonl" lane-closed exit_class)" = '"completed"' ]; then
  ok "--expect-usd becomes the lane's soft line and never a stop: the head's \$0.05 estimate is recorded as expect_usd, replaces the class's \$5.00 as soft_usd (soft_src $SS), the \$0.12 bill flags soft_exceeded true with (expect) on the close line — and the hard stop is untouched at \$10.00, so the lane completes at exit 0"
else no "--expect-usd as the soft line  [exit $RC, expect_usd $EU, soft $SU/$SX/$SS, hard_usd $HU: $(printf '%s' "$OUT" | grep -o 'soft-cap[^·]*' | head -1)]"; fi

ERR=$(spawn --routing "$RCOST" --run run-test-expect --lane HIGH --class builder --write "$F/writable" \
      --record "$F/rec-expect.jsonl" --expect-usd 99 --reason '(a) expect over the stop' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF -- '--expect-usd $99.00 is above this lane' \
   && printf '%s' "$ERR" | grep -qF '$10.00' && [ ! -f "$F/rec-expect.jsonl" ]; then
  ok "premise: an --expect-usd (\$99) above the lane's own hard stop (\$10) exits 2 naming both figures and writes no record line — a soft line the lane would be killed before reaching could never fire"
else no "--expect-usd over the hard stop  [exit $RC, record $([ -f "$F/rec-expect.jsonl" ] && echo written || echo absent): $ERR]"; fi

ERR=$(spawn --routing "$RCOST" --run run-test-expect --lane ZERO --class builder --write "$F/writable" \
      --record "$F/rec-expect0.jsonl" --expect-usd 0 --reason '(a) expect zero' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF 'not a positive dollar figure' \
   && [ ! -f "$F/rec-expect0.jsonl" ]; then
  ok "premise: a non-positive --expect-usd is refused (exit 2, no record) — zero is not an estimate, and it would otherwise read as a soft line every lane crosses"
else no "--expect-usd non-positive  [exit $RC, record $([ -f "$F/rec-expect0.jsonl" ] && echo written || echo absent): $ERR]"; fi

# The premise the fallback path must not skip: a class with no cost block still takes the estimate.
OUT=$(spawn --routing "$RCOST" --run run-test-env --lane PLANX --class planner --grants-only --grant "$F/granted" \
      --expect-usd 0.5 --reason '(a) no figures, with an estimate' 2>&1); RC=$?
EU=$(recfield "$REC" lane-open expect_usd); SS=$(recraw "$REC" lane-open soft_src)
SU=$(recfield "$REC" lane-closed soft_usd); SX=$(recfield "$REC" lane-closed soft_exceeded)
if [ "$RC" = 0 ] && [ "$EU" = 0.5 ] && [ "$SS" = '"expect"' ] && [ "$SU" = 0.5 ] && [ "$SX" = false ]; then
  ok "premise: a class WITHOUT a cost block still takes an --expect-usd as its soft line — the breadth-tier fallback records expect_usd and soft_src expect where it would otherwise carry nulls (control: the planner leg above, same class and no flag, recorded soft_usd null)"
else no "no-figures class with --expect-usd  [exit $RC, expect_usd $EU, soft_src $SS, soft $SU/$SX: $(printf '%s' "$OUT" | head -1)]"; fi

spawn --routing "$RCOST" --run run-test-env --lane PLAN --class planner --grants-only --grant "$F/granted" --reason '(a) no figures' >/dev/null 2>&1; RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
SU=$(recfield "$REC" lane-closed soft_usd); SX=$(recfield "$REC" lane-closed soft_exceeded)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] && [ "$HS" = '"breadth-tier (no class figures)"' ] \
   && [ "$(recfield "$REC" lane-open breadth)" = '"standard"' ] && [ "$SU" = null ] && [ "$SX" = null ]; then
  ok "a class without figures falls back to the breadth tier (standard, \$5) and records hard_src breadth-tier (no class figures); its close carries soft_usd null and soft_exceeded null"
else no "no-figures fallback  [exit $RC, hard_usd $HU, hard_src $HS, soft $SU/$SX]"; fi

# F1 (critic, 2026-09-07): the median and the maximum are unrelated statistics, so 5 x the class
# median can sit UNDER the class's own soft threshold and kill a lane below its class's history.
# The base is max(5 x usual, soft); the four legs below are the two branches, metered and not.
spawn --routing "$RCOST" --run run-test-big --lane MAXR --class memory-hunter --write "$F/writable" \
      --reason '(a) soft base' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-big.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-big.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 1.0 ] && [ "$(argafter --max-budget-usd)" = 1.0 ] \
   && [ "$HS" = '"soft $1.00 (class memory-hunter; 5 × usual $0.25 below it)"' ]; then
  ok "the hard stop reads the soft threshold where 5 x usual is below it: 5 x \$0.05 = \$0.25 sits under the class's \$1.00 soft threshold, so the threshold is the base and hard_src names both, and no lane is killed below its own class's history (F1)"
else no "max(5 x usual, soft)  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS]"; fi

spawn --routing "$RCOST" --run run-test-big --lane MULT --class verifier --grant "$F/granted" \
      --reason '(a) multiple wins' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-big.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-big.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 0.25 ] && [ "$HS" = '"5 × usual $0.05 (class verifier)"' ]; then
  ok "control for the leg above: where 5 x usual (\$0.25) is the larger term it still decides, over the same class's soft threshold of \$0.10"
else no "the multiple still wins where larger  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

spawn --routing "$RCOST" --run run-test-cap --lane MAXU --class memory-hunter --write "$F/writable" \
      --record "$F/rec-cap.jsonl" --reason '(a) soft base, unmetered' >/dev/null 2>&1; RC=$?
HU=$(recfield "$F/rec-cap.jsonl" lane-open hard_usd); HS=$(recraw "$F/rec-cap.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 1.0 ] \
   && [ "$HS" = '"soft $1.00 (class memory-hunter; 5 × usual $0.25 below it; envelope unmetered: no run-open event in the run record)"' ]; then
  ok "the soft base carries into the unmetered-envelope form: one hard_src states the base, the term it beat and why no remainder was had"
else no "soft base, envelope unmetered  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

# F5 (critic, 2026-09-07): the no-figures fallback ignored the envelope, so a class without
# figures could spawn at the tier value on a run with less than that left.
printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-tier", "event": "run-open", "session": "head-sid-4", "envelope_usd": 10.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-tier", "event": "head-exit", "session_id": "head-sid-4", "spent_usd": 8.5}' > "$SR/run-test-tier.jsonl"
spawn --routing "$RCOST" --run run-test-tier --lane TIER --class planner --grants-only --grant "$F/granted" \
      --reason '(a) tier under an envelope' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-tier.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-tier.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 1.5 ] && [ "$(argafter --max-budget-usd)" = 1.5 ] \
   && [ "$HS" = '"envelope remainder $1.50 (envelope $10.00, spent $8.50; below the breadth tier $5.00)"' ]; then
  ok "a class without figures composes with the envelope too: the remainder (\$1.50) beats the breadth tier (\$5) and hard_src says so (F5; the control is the planner leg above, which kept the tier where the remainder was not smaller)"
else no "no-figures fallback under an envelope  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS]"; fi

printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-soft", "event": "run-open", "session": "head-sid-5", "envelope_usd": 10.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-soft", "event": "head-exit", "session_id": "head-sid-5", "spent_usd": 9.4}' > "$SR/run-test-soft.jsonl"
spawn --routing "$RCOST" --run run-test-soft --lane SOFTR --class memory-hunter --write "$F/writable" \
      --reason '(a) remainder under the soft base' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-soft.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-soft.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 0.6 ] \
   && [ "$HS" = '"envelope remainder $0.60 (envelope $10.00, spent $9.40; below the soft threshold $1.00)"' ]; then
  ok "the envelope still bounds the soft base: a remainder of \$0.60 beats the \$1.00 base and the remainder line names the term it undercut"
else no "remainder under the soft base  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

# Raise-only leaves the one documented override standing: an exhausted envelope has no class value
# to raise over, so the explicit figure decides alone and hard_src names the envelope it overrode.
# Its own run record, so the two refusal legs keep asserting a record file that was never written.
printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-empty2", "event": "run-open", "session": "head-sid-6", "envelope_usd": 10.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-empty2", "event": "head-exit", "session_id": "head-sid-6", "spent_usd": 12.0}' > "$SR/run-test-empty2.jsonl"
spawn --routing "$RCOST" --run run-test-empty2 --lane OVER --class builder --write "$F/writable" \
      --budget-usd 3 --reason '(a) exhausted, overridden' >/dev/null 2>&1; RC=$?
HU=$(recfield "$SR/run-test-empty2.jsonl" lane-open hard_usd); HS=$(recraw "$SR/run-test-empty2.jsonl" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 3.0 ] && [ "$(argafter --max-budget-usd)" = 3.0 ] \
   && [ "$HS" = '"explicit --budget-usd (override of an exhausted envelope $10.00, remainder $-2.00)"' ]; then
  ok "an explicit --budget-usd still overrides an exhausted envelope (control for the two refusal legs around it, which passed no flag): raise-only compares against a class value, and a run with nothing left composed none — hard_src names the envelope and the remainder it overrode"
else no "exhausted envelope overridden  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

TYPES=$("$PY" - "$F/rec-cap.jsonl" "$REC" "$SR/run-test-big.jsonl" "$SR/run-test-tier.jsonl" "$SR/run-test-soft.jsonl" "$SR/run-test-empty2.jsonl" <<'TYPES_TERMINATOR'
import json, re, sys
opens, closes, forms_seen, states, bad = 0, 0, set(), set(), []
forms = [r"^explicit --budget-usd \(raised over class \$\d+\.\d\d: .+\)$",
         r"^5 × usual \$\d+\.\d\d \(class [a-z-]+\)$",
         r"^envelope remainder \$\d+\.\d\d \(envelope \$\d+\.\d\d, spent \$\d+\.\d\d; below 5 × usual \$\d+\.\d\d\)$",
         r"^breadth-tier \(no class figures\)$", r"^5 × usual \$\d+\.\d\d \(envelope unmetered: .+\)$",
         r"^soft \$\d+\.\d\d \(class [a-z-]+; 5 × usual \$\d+\.\d\d below it\)$",
         r"^soft \$\d+\.\d\d \(class [a-z-]+; 5 × usual \$\d+\.\d\d below it; envelope unmetered: .+\)$",
         r"^envelope remainder \$\d+\.\d\d \(envelope \$\d+\.\d\d, spent \$\d+\.\d\d; below the breadth tier \$\d+\.\d\d\)$",
         r"^envelope remainder \$\d+\.\d\d \(envelope \$\d+\.\d\d, spent \$\d+\.\d\d; below the soft threshold \$\d+\.\d\d\)$",
         r"^explicit --budget-usd \$\d+\.\d\d at or below class cap \$\d+\.\d\d: class cap kept \(.+\)$",
         r"^explicit --budget-usd \(override of an exhausted envelope \$\d+\.\d\d, remainder \$-?\d+\.\d\d\)$"]
def number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)
for path in sys.argv[1:]:
    for line in open(path):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("event") == "lane-open":
            opens += 1
            if not number(r.get("hard_usd")):
                bad.append("hard_usd %r" % r.get("hard_usd"))
            if r.get("budget_usd") != r.get("hard_usd"):
                bad.append("budget_usd %r != hard_usd %r" % (r.get("budget_usd"), r.get("hard_usd")))
            src = r.get("hard_src")
            hit = [i for i, f in enumerate(forms) if isinstance(src, str) and re.match(f, src)]
            if len(hit) != 1:
                bad.append("hard_src %r" % src)
            forms_seen.update(hit)
            if not (r.get("soft_usd") is None or number(r.get("soft_usd"))):
                bad.append("open soft_usd %r" % r.get("soft_usd"))
            # The soft line's own invariants (owner ruling, 2026-09-07): a source exactly where
            # there is a line, and an --expect-usd that is the line whenever one was given.
            src_soft, expect = r.get("soft_src"), r.get("expect_usd")
            if src_soft not in (None, "class", "expect"):
                bad.append("soft_src %r" % src_soft)
            if (r.get("soft_usd") is None) != (src_soft is None):
                bad.append("soft_usd %r with soft_src %r" % (r.get("soft_usd"), src_soft))
            if expect is not None and not (number(expect) and expect > 0):
                bad.append("expect_usd %r" % expect)
            if expect is not None and (src_soft != "expect" or r.get("soft_usd") != expect):
                bad.append("expect_usd %r not the soft line (%r/%r)"
                           % (expect, r.get("soft_usd"), src_soft))
            if expect is None and src_soft == "expect":
                bad.append("soft_src expect without expect_usd")
        elif r.get("event") == "lane-closed":
            closes += 1
            su, sx = r.get("soft_usd"), r.get("soft_exceeded")
            if not (su is None or number(su)):
                bad.append("close soft_usd %r" % su)
            if not (sx is None or isinstance(sx, bool)):
                bad.append("soft_exceeded %r" % sx)
            if (su is None) != (sx is None):
                bad.append("soft_usd %r with soft_exceeded %r" % (su, sx))
            states.add(sx)
print(json.dumps({"opens": opens, "closes": closes, "bad": bad, "forms": sorted(forms_seen),
                  "states": sorted(states, key=str)}))
TYPES_TERMINATOR
)
eq "record fields: every lane-open carries hard_usd (a number equal to budget_usd) and a hard_src in the eleven-form vocabulary, every soft line a source (soft_src class or expect, present exactly where soft_usd is, and equal to expect_usd wherever one was given), every lane-closed soft_usd (number or null) with soft_exceeded (bool or null); the legs above covered all eleven forms and all three soft states" \
   "$TYPES" '{"opens": 16, "closes": 16, "bad": [], "forms": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "states": [false, null, true]}'

RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" --record "$F/rec-cap.jsonl" --home "$LHOME" 2>&1); RC=$?
HU=$(recfield "$F/rec-cap.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-cap.jsonl" lane-resumed hard_src)
SU=$(recfield "$F/rec-cap.jsonl" lane-closed soft_usd); SX=$(recfield "$F/rec-cap.jsonl" lane-closed soft_exceeded)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$HS" = '"lane-open hard_usd"' ] && [ "$(argafter --max-budget-usd)" = 10.0 ] \
   && [ "$SU" = 5.0 ] && [ "$SX" = false ]; then
  ok "resume re-uses the lane-open's hard_usd as its --max-budget-usd, records it on lane-resumed with hard_src, and its close carries the soft check"
else no "resume hard cap  [exit $RC, hard_usd $HU, hard_src $HS, argv $(argafter --max-budget-usd), soft $SU/$SX: $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" --record "$F/rec-cap.jsonl" --home "$LHOME" --budget-usd 0.7 2>&1); RC=$?
HU=$(recfield "$F/rec-cap.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-cap.jsonl" lane-resumed hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$(argafter --max-budget-usd)" = 10.0 ] \
   && printf '%s' "$HS" | grep -q '^"explicit --budget-usd \$0\.70 at or below resumed cap \$10\.00: resumed cap kept (.*)"$' \
   && printf '%s' "$RS" | grep -qF 'that cap is kept'; then
  ok "raise-only holds on resume too: --budget-usd \$0.70 under the \$10.00 cap the lane already ran under is refused as a lowering, the recorded cap reaches the CLI, hard_src records both figures and the resume prints one line (this leg asserted the opposite before 2026-09-07)"
else no "resume explicit budget, lowering  [exit $RC, hard_usd $HU, hard_src $HS, argv $(argafter --max-budget-usd)]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" --record "$F/rec-cap.jsonl" --home "$LHOME" --budget-usd 14 --expect-usd 0.05 2>&1); RC=$?
HU=$(recfield "$F/rec-cap.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-cap.jsonl" lane-resumed hard_src)
SS=$(recraw "$F/rec-cap.jsonl" lane-closed soft_src); SX=$(recfield "$F/rec-cap.jsonl" lane-closed soft_exceeded)
EU=$(recfield "$F/rec-cap.jsonl" lane-resumed expect_usd)
if [ "$RC" = 0 ] && [ "$HU" = 14.0 ] && [ "$(argafter --max-budget-usd)" = 14.0 ] \
   && printf '%s' "$HS" | grep -q '^"explicit --budget-usd (raised over resumed \$10\.00: .*)"$' \
   && [ "$EU" = 0.05 ] && [ "$SS" = '"expect"' ] && [ "$SX" = true ] \
   && printf '%s' "$RS" | grep -qF 'soft-cap: $0.12 over $0.05 (expect)'; then
  ok "control for the leg above: a --budget-usd ABOVE the resumed cap raises it (\$14 reaches the CLI, hard_src names the \$10.00 it raised over), and --expect-usd on resume carries the same soft line to the close as on spawn"
else no "resume explicit budget, raising  [exit $RC, hard_usd $HU, hard_src $HS, expect_usd $EU, soft_src $SS/$SX]"; fi

ERR=$(spawn --routing "$F/routing-badcost.json" --run run-test-bad --lane BAD --class builder --write "$F/writable" --record "$F/rec-bad.jsonl" --reason '(a) bad cost' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'usual_usd' && [ ! -f "$F/rec-bad.jsonl" ]; then
  ok "premise: a cost block whose usual_usd is not a positive number refuses the spawn (exit 2, no record; control: the same row spawned above from the sound table)"
else no "malformed cost block  [exit $RC, record $([ -f "$F/rec-bad.jsonl" ] && echo written || echo absent): $ERR]"; fi

printf '%s\n' '{"ts": "2026-09-06T10:00:00+0100", "run": "run-test-empty", "event": "run-open", "session": "head-sid-3", "envelope_usd": 10.0}' \
              '{"ts": "2026-09-06T11:00:00+0100", "run": "run-test-empty", "event": "head-exit", "session_id": "head-sid-3", "spent_usd": 12.0}' > "$SR/run-test-empty.jsonl"
ERR=$(spawn --routing "$RCOST" --run run-test-empty --lane EMPTY --class builder --write "$F/writable" --reason '(a) exhausted' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'nothing left' && [ "$(events "$SR/run-test-empty.jsonl" lane-open)" = 0 ]; then
  ok "premise: an envelope with nothing left (\$10 granted, \$12 spent) refuses the spawn before any record line (exit 2)"
else no "exhausted envelope  [exit $RC, lane-opens $(events "$SR/run-test-empty.jsonl" lane-open): $ERR]"; fi


# lane.py on its own: without handsoff.py beside it no envelope can be read, and the spawn says so.
mkdir -p "$F/alone"; cp "$LANE" "$F/alone/lane.py"
$LANEV "$PY" "$F/alone/lane.py" spawn --home "$LHOME" --routing "$RCOST" --brief "$F/brief.md" --projects-root "$PROJ" \
  --run run-test-env --lane ALONE --class builder --write "$F/writable" --reason '(a) no handsoff beside' >/dev/null 2>&1; RC=$?
HU=$(recfield "$REC" lane-open hard_usd); HS=$(recraw "$REC" lane-open hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$HS" = '"5 × usual $2.00 (envelope unmetered: handsoff.py not found beside lane.py)"' ]; then
  ok "a lane.py without handsoff.py beside it still spawns: the envelope goes unread (control: the same run gave the remainder above), the class multiple applies and hard_src says why"
else no "spawn without handsoff.py  [exit $RC, hard_usd $HU, hard_src $HS]"; fi

ERR=$(spawn --routing "$RCOST" --run run-test-empty --lane EMPTY2 --class planner --grants-only \
       --grant "$F/granted" --reason '(a) exhausted, no figures' 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'nothing left' && [ "$(events "$SR/run-test-empty.jsonl" lane-open)" = 0 ]; then
  ok "premise: an exhausted envelope refuses a class WITHOUT figures too — the fallback no longer spawns at the tier value on a run with nothing left (F5)"
else no "exhausted envelope, no figures  [exit $RC, lane-opens $(events "$SR/run-test-empty.jsonl" lane-open): $ERR]"; fi

# F5/F9 (critic, 2026-09-07): resume ignored the envelope remainder, and its last fallback
# ignored the breadth knob while calling itself `no class figures`.
"$PY" - "$SR/run-test-big.jsonl" "$F/rec-resenv.jsonl" <<'RESENV_TERMINATOR'
import json, sys
out = []
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("event") == "run-open":
        record["envelope_usd"] = 25.0
    if record.get("event") == "head-exit":
        record["spent_usd"] = 20.0
    out.append(json.dumps(record))
with open(sys.argv[2], "w") as handle:
    handle.write("\n".join(out) + "\n")
RESENV_TERMINATOR
RS=$($LANEV "$PY" "$LANE" resume --run run-test-big --lane BIG --brief "$F/brief-follow.md" \
     --record "$F/rec-resenv.jsonl" --home "$LHOME" 2>&1); RC=$?
HU=$(recfield "$F/rec-resenv.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-resenv.jsonl" lane-resumed hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] && [ "$(argafter --max-budget-usd)" = 5.0 ] \
   && [ "$HS" = '"envelope remainder $5.00 (envelope $25.00, spent $20.00; below the lane-open hard_usd $10.00)"' ]; then
  ok "resume composes with the envelope: a remainder of \$5 caps the resumed call under the lane-open's own \$10 hard stop, and hard_src names both (F5; the control is the resume leg above, whose record carries no envelope and kept the recorded figure)"
else no "resume under an envelope  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS: $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi

"$PY" - "$F/rec-cap.jsonl" "$F/rec-resfb.jsonl" <<'RESFB_TERMINATOR'
import json, sys
out = []
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("event") == "lane-open" and record.get("lane") == "HARD":
        record.pop("hard_usd", None)
        record.pop("budget_usd", None)
    out.append(json.dumps(record))
with open(sys.argv[2], "w") as handle:
    handle.write("\n".join(out) + "\n")
RESFB_TERMINATOR
RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
     --record "$F/rec-resfb.jsonl" --home "$LHOME" 2>&1); RC=$?
HU=$(recfield "$F/rec-resfb.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-resfb.jsonl" lane-resumed hard_src)
if [ "$RC" = 0 ] && [ "$HU" = 5.0 ] && [ "$(argafter --max-budget-usd)" = 5.0 ] \
   && [ "$HS" = '"breadth-tier (a lane-open without hard_usd or budget_usd)"' ]; then
  ok "resume's last fallback is labelled for what it is — a lane-open carrying neither hard_usd nor budget_usd — and takes the breadth knob's tier (standard, \$5), not a constant (F9)"
else no "resume fallback label  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS: $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi

mkdir -p "$F/vault-max"
for entry in .claude CLAUDE.md wiki raw assets; do
  [ -e "$VAULT/$entry" ] && ln -s "$VAULT/$entry" "$F/vault-max/$entry"
done
printf '## Settings\n- **throttle**: default\n- **breadth**: max\n- **delegation**: single — the fixture regime\n' > "$F/vault-max/CUSTOMISATION.md"
RS=$($LANEV CLAUDE_PROJECT_DIR="$F/vault-max" "$PY" "$LANE" resume --run run-test-cap --lane HARD \
     --brief "$F/brief-follow.md" --record "$F/rec-resfb.jsonl" --home "$LHOME" 2>&1); RC=$?
HU=$(recfield "$F/rec-resfb.jsonl" lane-resumed hard_usd)
if [ "$RC" = 0 ] && [ "$HU" = 15.0 ] && [ "$(argafter --max-budget-usd)" = 15.0 ]; then
  ok "control for the leg above: under a preference layer whose breadth reads max the same fallback resumes at \$15, so the knob is read rather than a default assumed"
else no "resume fallback reads the breadth knob  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd): $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi

# A `budget` close never resumes on the cap that stopped it (SKILL.md §2a): the CLI's running
# total either survives the resume — the same cap kills the lane at once — or it does not, and
# the lane takes a second full helping. Four fixtures off the same $20 lane-open, differing only
# in the close's exit_class and the recorded cap, so the control below is an exact A/B.
"$PY" - "$F/rec-cap.jsonl" "$F/rec-resbud.jsonl" "$F/rec-rescomp.jsonl" "$F/rec-resnocap.jsonl" \
       "$F/rec-resbadcap.jsonl" <<'RESBUD_TERMINATOR'
import json, sys
src, budget_path, comp_path, nocap_path, badcap_path = sys.argv[1:6]
rows = []
for line in open(src):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("lane") == "HARD" and record.get("event") == "lane-resumed":
        continue          # back to the close-to-resume state the earlier legs started from
    rows.append(record)
def write(path, exit_class, mutate=None):
    out = []
    for row in rows:
        row = dict(row)
        if row.get("lane") == "HARD":
            if row.get("event") == "lane-closed":
                row["exit_class"] = exit_class
                if exit_class == "budget":
                    row["subtype"] = "error_max_budget_usd"
            elif row.get("event") == "lane-open" and mutate:
                row = mutate(row)
        out.append(json.dumps(row))
    with open(path, "w") as handle:
        handle.write("\n".join(out) + "\n")
def drop_caps(row):
    row.pop("hard_usd", None); row.pop("budget_usd", None); return row
def string_cap(row):
    row["hard_usd"] = "twenty"; return row
write(budget_path, "budget")
write(comp_path, "completed")
write(nocap_path, "budget", drop_caps)
write(badcap_path, "budget", string_cap)
RESBUD_TERMINATOR
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
      --record "$F/rec-resbud.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'budget cap of \$10.00' \
   && printf '%s' "$ERR" | grep -q 'ABOVE that figure' \
   && [ "$(events "$F/rec-resbud.jsonl" lane-resumed)" = 0 ]; then
  ok "a budget close does not resume on the cap that stopped it: without --budget-usd it exits 2, names the recorded \$10.00 cap and the rule, and writes no lane-resumed"
else no "budget close resumed bare  [exit $RC, lane-resumed $(events "$F/rec-resbud.jsonl" lane-resumed): $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
      --record "$F/rec-resbud.jsonl" --home "$LHOME" --budget-usd 10 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'not above it' \
   && [ "$(events "$F/rec-resbud.jsonl" lane-resumed)" = 0 ]; then
  ok "premise: --budget-usd EQUAL to the recorded cap refuses too (exit 2, no lane-resumed) — equal is not above, and the lane would stop where it stopped before"
else no "budget close resumed at the same cap  [exit $RC, lane-resumed $(events "$F/rec-resbud.jsonl" lane-resumed): $ERR]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
     --record "$F/rec-resbud.jsonl" --home "$LHOME" --budget-usd 25 2>&1); RC=$?
HU=$(recfield "$F/rec-resbud.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-resbud.jsonl" lane-resumed hard_src)
AB=$(recfield "$F/rec-resbud.jsonl" lane-resumed after_budget); AL=$(recfield "$F/rec-resbud.jsonl" lane-resumed after_limit)
if [ "$RC" = 0 ] && [ "$HU" = 25.0 ] && [ "$(argafter --max-budget-usd)" = 25.0 ] \
   && [ "$HS" = '"explicit --budget-usd (raised over a budget close from $10.00)"' ] \
   && [ "$AB" = true ] && [ "$AL" = false ]; then
  ok "a --budget-usd ABOVE the recorded cap resumes the budget close: \$25 reaches the CLI, hard_src names the raise over the \$10 close and lane-resumed carries after_budget beside after_limit"
else no "budget close resumed raised  [exit $RC, hard_usd $HU, argv $(argafter --max-budget-usd), hard_src $HS, after_budget $AB/after_limit $AL: $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi
RS=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
     --record "$F/rec-rescomp.jsonl" --home "$LHOME" 2>&1); RC=$?
HU=$(recfield "$F/rec-rescomp.jsonl" lane-resumed hard_usd); HS=$(recraw "$F/rec-rescomp.jsonl" lane-resumed hard_src)
AB=$(recfield "$F/rec-rescomp.jsonl" lane-resumed after_budget)
if [ "$RC" = 0 ] && [ "$HU" = 10.0 ] && [ "$HS" = '"lane-open hard_usd"' ] && [ "$AB" = false ] \
   && [ "$(events "$F/rec-rescomp.jsonl" lane-resumed)" = 1 ]; then
  ok "control for the three legs above: the same fixture with a completed close resumes bare on the recorded \$10 hard_usd exactly as before, after_budget false — the guard keys on the close's exit_class, nothing else"
else no "completed close resumed bare  [exit $RC, hard_usd $HU, hard_src $HS, after_budget $AB: $(printf '%s' "$RS" | head -2 | tr '\n' ' ')]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
      --record "$F/rec-resnocap.jsonl" --home "$LHOME" --budget-usd 25 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'cap it stopped at is unknown' \
   && [ "$(events "$F/rec-resnocap.jsonl" lane-resumed)" = 0 ]; then
  ok "premise: a budget close whose lane-open carries neither hard_usd nor budget_usd refuses even with a raised --budget-usd (exit 2) — no figure can be shown to clear an unknown cap"
else no "budget close without a recorded cap  [exit $RC, lane-resumed $(events "$F/rec-resnocap.jsonl" lane-resumed): $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-cap --lane HARD --brief "$F/brief-follow.md" \
      --record "$F/rec-resbadcap.jsonl" --home "$LHOME" --budget-usd 25 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'not a number' \
   && [ "$(events "$F/rec-resbadcap.jsonl" lane-resumed)" = 0 ]; then
  ok "premise: a non-numeric recorded cap ('twenty') on a budget close is a broken premise, not a comparison against a string (exit 2, no lane-resumed)"
else no "budget close with an unreadable cap  [exit $RC, lane-resumed $(events "$F/rec-resbadcap.jsonl" lane-resumed): $ERR]"; fi

# ------------------------------------------------------------------- cost-figures ------------
# `lane.py cost-figures` re-derives every class's figures from the run store and, with --check,
# compares them with the table's blocks — the reader F3 found missing. It writes nothing: the
# manifest leg at the end of this block is the proof, and its own control must show a change.
echo "== cost-figures =="
FIGS="$F/figstore"; FIGT="$F/figtables"; mkdir -p "$FIGS" "$FIGT"
"$PY" - "$FIGS" "$FIGT" <<'FIG_FIXTURE_TERMINATOR'
import json, os, sys
store, tables = sys.argv[1], sys.argv[2]
def close(cls, cost, day="05", exit_class="completed", drop=False):
    event = {"ts": "2026-09-%sT10:00:00+0100" % day, "event": "lane-closed", "lane": "L",
             "class": cls, "exit_class": exit_class, "total_cost_usd": cost}
    if drop:
        del event["total_cost_usd"]
    return json.dumps(event)
first = [close("alpha", 1.0, "04"), close("alpha", 2.0), close("alpha", 3.0, "06"),
         "{ this line is not JSON",                      # torn: skipped and counted
         close("alpha", 99.0, exit_class="budget"),      # not completed: excluded
         close("alpha", None),                           # completed, no figure: excluded
         close("alpha", 42.0, drop=True),                # completed, no field: excluded
         json.dumps({"ts": "2026-09-05T10:00:00+0100", "event": "lane-open", "class": "alpha"})]
second = [close("beta", 0.5), close("beta", 0.5), close("beta", 0.5), close("beta", 4.0),
          close("gamma", 1.0), close("gamma", 2.0)]     # gamma stops under the floor of three
for name, lines in (("fig-a.jsonl", first), ("fig-b.jsonl", second)):
    with open(os.path.join(store, name), "w") as handle:
        handle.write("\n".join(lines) + "\n")
def table(alpha, beta, gamma):
    classes = {}
    for name, block in (("alpha", alpha), ("beta", beta), ("gamma", gamma)):
        classes[name] = {"cost": block} if block else {}
    return {"schema": 2, "order": {"model": ["sonnet"], "effort": ["high"]}, "classes": classes}
ALPHA = {"soft_usd": 3.75, "usual_usd": 2.0, "n": 3}
BETA = {"soft_usd": 5.0, "usual_usd": 0.5, "n": 4}
for name, data in (("same.json", table(ALPHA, BETA, None)),
                   ("drift.json", table(ALPHA, dict(BETA, usual_usd=0.6), None)),
                   ("gaps.json", table(None, BETA, {"soft_usd": 2.5, "usual_usd": 1.5, "n": 2}))):
    with open(os.path.join(tables, name), "w") as handle:
        json.dump(data, handle, indent=1)
FIG_FIXTURE_TERMINATOR
figures(){ "$PY" "$LANE" cost-figures --records "$FIGS" "$@"; }
has(){ printf '%s\n' "$1" | grep -qF "$2"; }

FIGOUT=$(figures 2>&1); RC=$?
if [ "$RC" = 0 ] \
   && has "$FIGOUT" 'alpha · n=3 · 2026-09-04..2026-09-06 · usual $2.00 · max $3.00 · soft $3.75' \
   && has "$FIGOUT" 'beta · n=4 · 2026-09-05..2026-09-05 · usual $0.50 · max $4.00 · soft $5.00' \
   && has "$FIGOUT" 'gamma · n=2 (below the floor of three: no block)' \
   && has "$FIGOUT" 'cost-figures: 2 record file(s), 9 completed close(s), 1 torn line(s)'; then
  ok "cost-figures folds the store per class: n, window, median, maximum and the 25 % soft threshold, the floor of three named for the class under it, and a count line carrying the files, the completed closes and the torn line (the fold's own positive control)"
else no "cost-figures fold  [exit $RC] $(printf '%s' "$FIGOUT" | tr '\n' '|')"; fi

FIGOUT=$(figures --routing "$FIGT/same.json" --check 2>&1); RC=$?
if [ "$RC" = 0 ] && has "$FIGOUT" 'soft $3.75 · same' && has "$FIGOUT" 'soft $5.00 · same' \
   && has "$FIGOUT" 'gamma · n=2 (below the floor of three: no block) · no block (n < 3)'; then
  ok "cost-figures --check: a table whose blocks match the fold reports same on every class and no block (n < 3) for the class under the floor, and exits 0"
else no "cost-figures --check same  [exit $RC] $(printf '%s' "$FIGOUT" | tr '\n' '|')"; fi

FIGOUT=$(figures --routing "$FIGT/drift.json" --check 2>&1); RC=$?
if [ "$RC" = 1 ] && has "$FIGOUT" 'drift (soft $5.00 → $5.00 · usual $0.60 → $0.50 · n 4 → 4)' \
   && has "$FIGOUT" 'soft $3.75 · same'; then
  ok "cost-figures --check: a planted drift in one block is caught with the table's figure on the left of each arrow and the fold's on the right, exit 1 (control: the untouched class on the same run still reads same)"
else no "cost-figures --check drift  [exit $RC] $(printf '%s' "$FIGOUT" | tr '\n' '|')"; fi

FIGOUT=$(figures --routing "$FIGT/gaps.json" --check 2>&1); RC=$?
if [ "$RC" = 1 ] && has "$FIGOUT" 'fold due (n=3 ≥ 3, no block)' \
   && has "$FIGOUT" 'drift (soft $2.50 → none · usual $1.50 → none · n 2 → 2)'; then
  ok "cost-figures --check: a class of three or more completed lanes without a block is fold due, and a block on a class under the floor is a drift to none — the two ways the table and the floor of three fall out of step (F3), both exit 1"
else no "cost-figures --check gaps  [exit $RC] $(printf '%s' "$FIGOUT" | tr '\n' '|')"; fi

FIGJSON=$(figures --format json 2>&1); RC=$?
FIGSUM=$("$PY" - "$FIGJSON" <<'FIGJSON_TERMINATOR'
import json, sys
data = json.loads(sys.argv[1])
rows = {row["class"]: row for row in data["classes"]}
print(json.dumps([data["files"], data["completed"], data["torn"], data["floor_n"],
                  data["headroom"], rows["alpha"]["usual_usd"], rows["beta"]["soft_usd"],
                  rows["gamma"]["n"]]))
FIGJSON_TERMINATOR
)
eq "cost-figures --format json carries the same fold as one object: the counts, the floor, the headroom and a row per class" \
   "$FIGSUM" '[2, 9, 1, 3, 1.25, 2.0, 5.0, 2]'

mkdir -p "$F/figempty" "$F/fignone"
printf '%s\n' '{"ts": "2026-09-05T10:00:00+0100", "event": "lane-closed", "class": "alpha", "exit_class": "budget", "total_cost_usd": 1.0}' > "$F/fignone/only.jsonl"
E1=$("$PY" "$LANE" cost-figures --records "$F/figempty" 2>&1); R1=$?
E2=$("$PY" "$LANE" cost-figures --records "$F/fignone" 2>&1); R2=$?
E3=$("$PY" "$LANE" cost-figures --records "$F/figstore/not-a-directory" 2>&1); R3=$?
if [ "$R1" = 2 ] && [ "$R2" = 2 ] && [ "$R3" = 2 ] \
   && has "$E1" 'PROBE FAILED: no .jsonl record file' && has "$E2" 'PROBE FAILED: no completed lane-closed' \
   && has "$E3" 'PROBE FAILED: no records directory'; then
  ok "cost-figures refuses a broken premise instead of printing a clean zero: an empty directory, a directory whose records hold no completed close, and a directory that is not there each print PROBE FAILED and exit 2 (control: the same command on the fixture store above exited 0 with figures)"
else no "cost-figures premise failures  [exits $R1/$R2/$R3] $(printf '%s' "$E1$E2$E3" | tr '\n' '|')"; fi

DEFOUT=$($LANEV "$PY" "$LANE" cost-figures 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$DEFOUT" | tail -1 | grep -q '^cost-figures: [1-9][0-9]* record file(s), [1-9][0-9]* completed close(s), [0-9]* torn line(s)$'; then
  ok "cost-figures with no --records folds the run store's own spawn-records (here the suite's redirected store) and ends with the same count line"
else no "cost-figures default records directory  [exit $RC] $(printf '%s' "$DEFOUT" | tail -2 | tr '\n' '|')"; fi

figman(){ find "$FIGS" "$FIGT" -type f -exec shasum {} \; | sort; }
FM1=$(figman)
figures --routing "$FIGT/same.json" --check >/dev/null 2>&1
figures --routing "$FIGT/drift.json" --check --format json >/dev/null 2>&1
figures >/dev/null 2>&1
FM2=$(figman)
FIGN1=$(find "$FIGS" "$FIGT" -type f | wc -l | tr -d ' ')
printf '\n' >> "$FIGT/same.json"; FM3=$(figman)
if [ -n "$FM1" ] && [ "$FM1" = "$FM2" ] && [ "$FM2" != "$FM3" ] && [ "$FIGN1" = 5 ]; then
  ok "cost-figures writes nothing: three runs (fold, check, json) leave the record store and the tables byte-identical and still five files (control: the same manifest catches the one byte this leg planted afterwards)"
else no "cost-figures write-nothing manifest  [files $FIGN1, changed under the runs: $([ "$FM1" = "$FM2" ] && echo no || echo yes), control $([ "$FM2" != "$FM3" ] && echo hit || echo missed)]"; fi

# --fold: the one writing path. Every leg here works on a COPY under its own directory, so the
# manifest leg above keeps its meaning — those three runs still write nothing. The fixture
# tables are dumped at indent 1 (see the fixture above), which is not the width any re-dump
# here would pick by itself: that is what makes the indent legs real.
FIGF="$F/figfold"; mkdir -p "$FIGF"
cp "$FIGT/drift.json" "$FIGF/drift-0.json"
cp "$FIGT/drift.json" "$FIGF/drift-1.json"
FOLD1=$(figures --routing "$FIGF/drift-1.json" --fold 2>&1); RC=$?
cp "$FIGF/drift-1.json" "$FIGF/after-first.json"
FOLD2=$(figures --routing "$FIGF/drift-1.json" --fold 2>&1); RC2=$?
if [ "$RC" = 0 ] && [ "$RC2" = 0 ] \
   && diff "$FIGF/after-first.json" "$FIGF/drift-1.json" > "$F/fold-second.diff" \
   && [ ! -s "$F/fold-second.diff" ] \
   && has "$FOLD1" 'wrote 1 class block(s)' && has "$FOLD2" 'nothing drifted'; then
  ok "cost-figures --fold is idempotent: the second fold of an already-folded table reports nothing drifted and the diff between the two results is empty"
else no "the second fold changed the file  [exits $RC/$RC2, diff $(wc -l < "$F/fold-second.diff" | tr -d ' ') lines] $(printf '%s' "$FOLD2" | tr '\n' '|')"; fi
# The bound on what one folded class may touch. The planted drift is beta's `usual_usd` alone,
# and the fixture's block carries neither `window` nor `source`, so the fold's whole diff is:
# two lines removed (the old `usual_usd`, and `n` because it gains a comma once fields follow
# it), four written (the new `usual_usd`, `n,`, `window`, `source`), and the closing `}` re-read
# because the fixture was dumped with no newline at the end of the file and every table this
# writes carries one. 2 + 4 + 2 = 8, and the leg refuses anything above it: a re-dump at another
# width would put every one of the file's ~40 lines in the diff.
diff "$FIGF/drift-0.json" "$FIGF/after-first.json" > "$F/fold-first.diff"
FOLDCH=$(grep -c '^[<>]' "$F/fold-first.diff"); [ -n "$FOLDCH" ] || FOLDCH=0
FOLDALPHA=$(grep -c '3.75' "$F/fold-first.diff"); [ -n "$FOLDALPHA" ] || FOLDALPHA=0
if [ "$FOLDCH" -le 8 ] && [ "$FOLDCH" -ge 4 ] && [ "$FOLDALPHA" = 0 ] \
   && grep -q '^> *"usual_usd": 0.5,' "$F/fold-first.diff"; then
  ok "cost-figures --fold touches only the drifted class's block: $FOLDCH changed lines against a bound of 8, none of them the untouched class's (the control: alpha's figures appear nowhere in the diff)"
else no "the fold's diff is too wide  [$FOLDCH changed lines, alpha lines $FOLDALPHA] $(head -6 "$F/fold-first.diff" | tr '\n' '|')"; fi
# The indent is the file's own, not this script's: the folded file is what a re-dump AT THE
# FIXTURE'S OWN WIDTH gives, and is not what one at the next width up gives.
FOLDIND=$("$PY" - "$FIGF/drift-1.json" <<'FOLDIND_TERMINATOR'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
data = json.loads(raw)
same = json.dumps(data, indent=1, ensure_ascii=False) + "\n"     # the fixture's own width
wider = json.dumps(data, indent=2, ensure_ascii=False) + "\n"    # the width a re-dump picked
print("kept" if raw == same else "widened" if raw == wider else "neither")
FOLDIND_TERMINATOR
)
FOLDORD=$("$PY" - "$FIGF/drift-1.json" <<'FOLDORD_TERMINATOR'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(",".join(list(data)) + "|" + ",".join(list(data["classes"]))
      + "|" + ",".join(list(data["classes"]["beta"]["cost"])))
FOLDORD_TERMINATOR
)
if [ "$FOLDIND" = kept ] \
   && [ "$FOLDORD" = "schema,order,classes|alpha,beta,gamma|soft_usd,usual_usd,n,window,source" ]; then
  ok "cost-figures --fold keeps the file's own indent (the folded file is the fixture's one-space width, not the wider one the re-fold used to pick) and its key order: the new fields are appended, nothing is sorted"
else no "the fold rewrote the file's shape  [indent $FOLDIND, order $FOLDORD]"; fi
# Nothing drifted: no write at all, and the file is byte-identical afterwards.
cp "$FIGT/drift.json" "$FIGF/same-1.json"      # `drift.json` differs from `same.json` in one
"$PY" - "$FIGF/same-1.json" <<'SAMEFIX_TERMINATOR'
import json, sys                                # field only; put it back and nothing drifts
data = json.load(open(sys.argv[1], encoding="utf-8"))
data["classes"]["beta"]["cost"]["usual_usd"] = 0.5
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=1)
SAMEFIX_TERMINATOR
SAMESUM=$(shasum "$FIGF/same-1.json" | cut -d' ' -f1)
FOLD3=$(figures --routing "$FIGF/same-1.json" --fold 2>&1); RC=$?
if [ "$RC" = 0 ] && has "$FOLD3" 'nothing drifted' \
   && [ "$(shasum "$FIGF/same-1.json" | cut -d' ' -f1)" = "$SAMESUM" ]; then
  ok "cost-figures --fold with nothing drifted writes nothing and says so (the table's checksum is unchanged; the drifted table above is the control)"
else no "the fold wrote an undrifted table  [exit $RC] $(printf '%s' "$FOLD3" | tr '\n' '|')"; fi
# A class under the floor that still carries a block: the fold removes it, which is what
# --check's `drift (… → none)` says should happen.
cp "$FIGT/gaps.json" "$FIGF/gaps-1.json"
FOLD4=$(figures --routing "$FIGF/gaps-1.json" --fold 2>&1); RC=$?
GAPSGAMMA=$("$PY" -c 'import json, sys; print("cost" in json.load(open(sys.argv[1], encoding="utf-8"))["classes"]["gamma"])' "$FIGF/gaps-1.json")
GAPSALPHA=$("$PY" -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["classes"]["alpha"]["cost"]["usual_usd"])' "$FIGF/gaps-1.json")
if [ "$RC" = 0 ] && [ "$GAPSGAMMA" = False ] && [ "$GAPSALPHA" = 2.0 ] \
   && has "$FOLD4" 'block removed'; then
  ok "cost-figures --fold gives a class over the floor its first block and removes the block of a class that has fallen under it (gamma), the two shapes --check calls fold due and drift to none"
else no "the fold on the gaps table  [exit $RC, gamma block $GAPSGAMMA, alpha usual $GAPSALPHA] $(printf '%s' "$FOLD4" | tr '\n' '|')"; fi
# Under --format json stdout stays one parseable object and the fold's own line goes to stderr.
cp "$FIGT/drift.json" "$FIGF/drift-json.json"
FOLDJ=$("$PY" "$LANE" cost-figures --records "$FIGS" --routing "$FIGF/drift-json.json" --fold --format json 2>"$F/fold-json.err"); RC=$?
FOLDJOK=$(printf '%s' "$FOLDJ" | "$PY" -c 'import json, sys; print(json.load(sys.stdin)["drift"])' 2>&1)
if [ "$RC" = 0 ] && [ "$FOLDJOK" = True ] && grep -q 'wrote 1 class block' "$F/fold-json.err"; then
  ok "cost-figures --fold --format json leaves stdout a parseable object and puts the fold's own line on stderr"
else no "the fold broke the json stdout  [exit $RC, parsed $FOLDJOK, stderr $(head -1 "$F/fold-json.err")]"; fi
# --check is unchanged by the flag's arrival: the same table, the same verdicts, still no write.
CHKSUM=$(shasum "$FIGT/drift.json" | cut -d' ' -f1)
FIGOUT=$(figures --routing "$FIGT/drift.json" --check 2>&1); RC=$?
if [ "$RC" = 1 ] && has "$FIGOUT" 'drift (soft $5.00 → $5.00 · usual $0.60 → $0.50 · n 4 → 4)' \
   && [ "$(shasum "$FIGT/drift.json" | cut -d' ' -f1)" = "$CHKSUM" ]; then
  ok "cost-figures --check is unchanged beside --fold: the same drift, the same exit 1, and the table it read is byte-identical afterwards"
else no "--check changed under --fold  [exit $RC, table changed $([ "$(shasum "$FIGT/drift.json" | cut -d' ' -f1)" = "$CHKSUM" ] && echo no || echo yes)] $(printf '%s' "$FIGOUT" | tr '\n' '|')"; fi

# ----------------------------------------------------------- wrote nothing outside its own ---
echo "== containment =="
SCRATCH="$F/scratch"; mkdir -p "$SCRATCH"; printf 'a\n' > "$SCRATCH/probe"
manifest(){ find "$1" -type f -exec shasum {} \; | sort; }
M1=$(manifest "$SCRATCH"); printf 'b\n' > "$SCRATCH/probe"; M2=$(manifest "$SCRATCH")
if [ -n "$M1" ] && [ "$M1" != "$M2" ]; then
  ok "the manifest comparison notices a changed byte (control for the legs below)"
else no "the manifest comparison is insensitive — the containment legs would be vacuous"; fi

# Only the files these two scripts read or could plausibly damage are hashed: the rest of the
# skill directory may legitimately change under a concurrent editor, and hashing it would turn
# a sibling's edit into a false failure here.
WATCHED="$LANE $FENCE $0 $VAULT/CLAUDE.md $VAULT/wiki/developments/wiki-confidence-levels.md"
VAULT_BEFORE=$(shasum $WATCHED)
spawn --run run-test-z --lane Z1 --class verifier --grant "$F/granted" \
      --record "$F/rec-z.jsonl" --reason '(a) containment' >/dev/null 2>&1
"$PY" "$LANE" init --home "$LHOME" >/dev/null 2>&1
VAULT_AFTER=$(shasum $WATCHED)
if [ "$VAULT_BEFORE" = "$VAULT_AFTER" ] && [ -n "$VAULT_BEFORE" ]; then
  ok "a spawn and an init leave both scripts and the two vault files init reads byte-identical"
else no "the wrapper wrote into the vault"; fi

if [ -z "$(find "$HOME/.llm-wiki/spawn-records" -name 'run-test-*' -newer "$LANE" 2>/dev/null)" ]; then
  ok "no run-test artefact reached the real run store (LLM_WIKI_STORE redirected every write)"
else no "the suite wrote into the real run store"; fi

scan_writes(){ # count how many of the five write-pattern families hit in a file
  N=0
  for pat in 'open\([^)]*['"'"'"][wax]' '\bos\.(remove|unlink|rename|replace|mkdir|makedirs|rmdir)\b' \
             '\bshutil\.' '\b(subprocess|Popen)\b' '\bos\.symlink\b'; do
    grep -qE -- "$pat" "$1" && N=$((N + 1))
  done
  echo "$N"
}
PLANT="$F/planted-fence.py"
{ cat "$FENCE"; printf '\nopen("x", "w")\nos.remove("x")\nshutil.copy("x","y")\nsubprocess.run([])\nos.symlink("a","b")\n'; } > "$PLANT"
WRITES=$(scan_writes "$FENCE"); PWRITES=$(scan_writes "$PLANT"); LWRITES=$(scan_writes "$LANE")
if [ "$WRITES" = 0 ] && [ "$PWRITES" = 5 ] && [ "$LWRITES" -ge 3 ]; then
  ok "the fence is stdout-only: none of the five write-pattern families appears in its source (controls: all 5 caught in a planted copy, and the same scan finds $LWRITES families in lane.py, which does write)"
else no "fence write-pattern scan  [fence $WRITES, planted $PWRITES of 5, lane.py $LWRITES]"; fi

STRAY=$(grep -nE "open\([^)]*['\"][wax]" "$LANE" | grep -v 'write_atomic\|append_record' | wc -l | tr -d ' ')
if [ "$STRAY" = 2 ]; then
  ok "every write in lane.py runs through write_atomic or append_record (2 call sites, both inside those helpers)"
else no "lane.py has $STRAY write call sites outside its two helpers"; fi

# ------------------------------------------------- every written spawn command names a reason ---
# A shipped example without the flag is how a head learns to leave it out, and the flag is now
# refused when absent, so a documented command that omits it is also wrong. The sweep reads the
# .md, .sh and .py files under its roots, takes each mention of the wrapper's spawn command, and
# treats it as a command only where its own argument text — up to the next mention of the wrapper
# on the same logical line, backslash continuations joined — carries --run. Prose and a lone flag
# fragment are therefore not commands. It prints locators and a count, writes nothing, exits 1 on
# a bare command and 2 on a root holding nothing it can read. Every spawn command written into
# this suite reaches the wrapper through "$LANE", which the sweep's pattern does not match, so the
# suite's own text is swept for documentation, not for its calls; the fixtures below assemble the
# bare form through printf's %s for the same reason.
reasonsweep(){ "$PY" - "$@" <<'REASON_SWEEP_TERMINATOR'
import os, re, sys
MENTION = re.compile(r"lane\.py\s+([a-z][a-z-]*)")
roots = [os.path.realpath(p) for p in sys.argv[1:]]
bare, scanned = [], 0
for root in roots:
    for base, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("__pycache__", ".git")]
        for name in sorted(names):
            if not name.endswith((".md", ".sh", ".py")):
                continue
            path = os.path.join(base, name)
            try:
                lines = open(path, errors="replace").read().split("\n")
            except OSError as exc:
                sys.stderr.write("PROBE FAILED: cannot read %s: %s\n" % (path, exc))
                sys.exit(2)
            scanned += 1
            for i, line in enumerate(lines):
                logical, j = line, i
                while logical.rstrip().endswith("\\") and j + 1 < len(lines):
                    j += 1
                    logical = logical.rstrip()[:-1] + " " + lines[j]
                spots = list(MENTION.finditer(logical))
                for k, spot in enumerate(spots):
                    if spot.group(1) != "spawn":
                        continue
                    end = spots[k + 1].start() if k + 1 < len(spots) else len(logical)
                    segment = logical[spot.start():end]
                    if "--run" not in segment:
                        continue
                    if "--reason" not in segment:
                        bare.append("%s:%d" % (path, i + 1))
if not scanned:
    sys.stderr.write("PROBE FAILED: no .md, .sh or .py file under %s\n" % ", ".join(roots))
    sys.exit(2)
for hit in bare:
    print(hit)
print("swept %d file(s), %d bare spawn command(s)" % (scanned, len(bare)))
sys.exit(1 if bare else 0)
REASON_SWEEP_TERMINATOR
}
# The roots: the skill directory this suite runs from, widened to the whole skills tree when that
# directory sits inside the vault (the shipped location), where a sibling skill may show a spawn.
SWEEPROOT="$HERE"
case "$HERE/" in
  "$VAULT"/*) [ -d "$VAULT/.claude/skills" ] && SWEEPROOT="$VAULT/.claude/skills" ;;
esac
mkdir -p "$F/sweep/thing" "$F/sweep-empty"
printf 'Start it: `python3 lane.py %s --run <id> --lane <id> --class verifier --brief b.md`\n' spawn \
  > "$F/sweep/thing/SKILL.md"
printf 'python3 lane.py %s --run r --lane L --class verifier --brief b.md --reason "(a) clean"\n' spawn \
  > "$F/sweep/thing/clean.sh"
printf 'The wrapper: lane.py %s greps each control phrase in the brief before it starts.\n' spawn \
  > "$F/sweep/thing/prose.md"
printf 'python3 lane.py %s --run r --lane L --class verifier \\\n  --brief b.md --reason "(b) split over two lines"\n' spawn \
  > "$F/sweep/thing/continued.sh"
SWP=$(reasonsweep "$F/sweep" 2>&1); SWPRC=$?
SWC=$(reasonsweep "$SWEEPROOT" 2>&1); SWCRC=$?
SWE=$(reasonsweep "$F/sweep-empty" 2>&1); SWERC=$?
if [ "$SWPRC" = 1 ] && printf '%s' "$SWP" | grep -q 'thing/SKILL.md:1' \
   && printf '%s' "$SWP" | grep -q '1 bare spawn command' \
   && ! printf '%s' "$SWP" | grep -q 'clean.sh' && ! printf '%s' "$SWP" | grep -q 'prose.md' \
   && ! printf '%s' "$SWP" | grep -q 'continued.sh'; then
  ok "the reason sweep catches a planted spawn command with no --reason and passes the three it must not flag (a lettered command, a prose mention, a reason on a continuation line)"
else no "the planted sweep case  [exit $SWPRC: $(printf '%s' "$SWP" | tr '\n' ' ')]"; fi
if [ "$SWCRC" = 0 ] && printf '%s' "$SWC" | grep -q '0 bare spawn command' \
   && [ "$(printf '%s' "$SWC" | grep -c 'swept')" = 1 ]; then
  ok "every spawn command written in $SWEEPROOT carries --reason (control: the planted case above, caught by the same sweep on the same run)"
else no "the reason sweep over $SWEEPROOT  [exit $SWCRC: $(printf '%s' "$SWC" | tr '\n' ' ')]"; fi
if [ "$SWERC" = 2 ] && printf '%s' "$SWE" | grep -q 'PROBE FAILED'; then
  ok "the sweep refuses a root holding no readable file (PROBE FAILED, exit 2) instead of printing a clean zero"
else no "the sweep's premise case  [exit $SWERC: $SWE]"; fi

# The wrapper's own usage line is one of the commands the sweep reads; this leg names it, so a
# rewritten docstring cannot drop the flag unnoticed.
DOCUSAGE=$(grep -n 'lane\.py spawn ' "$LANE" | head -1)
DOCCTL=$(printf '    lane.py %s  --run ID --lane ID --class CLASS --brief FILE [options]\n' spawn)
if printf '%s' "$DOCUSAGE" | grep -q -- '--reason' && printf '%s' "$DOCUSAGE" | grep -q -- '--run' \
   && ! printf '%s' "$DOCCTL" | grep -q -- '--reason'; then
  ok "the lane.py docstring's spawn usage line carries --reason (control: the same grep misses a copy of the line without it)"
else no "the docstring usage line  [$DOCUSAGE]"; fi

HOME_AFTER=$(shasum "$LANE" "$FENCE" "$0")
mkdir -p "$F/fakehome/__pycache__"
if [ "$HOME_BEFORE" = "$HOME_AFTER" ] && [ ! -d "$HERE/__pycache__" ] \
   && [ -d "$F/fakehome/__pycache__" ]; then
  ok "the suite leaves its own home untouched (control: a planted __pycache__ the same test sees)"
else no "the suite wrote into the script home"; fi

# ------------------------------------------------------------------------- live --------------
if [ "$LIVE" = 1 ]; then
  echo "== live =="
  LSTORE="$F/live-store"; LREC="$LSTORE/spawn-records/run-test-live.jsonl"
  mkdir -p "$F/live/granted" "$F/live/whitelist" "$F/live/offlimits"
  printf 'LIVE-GRANTED-TOKEN-5150\n' > "$F/live/granted/inside.txt"
  printf 'LIVE-OFFLIMITS-TOKEN-6260\n' > "$F/live/offlimits/outside.txt"
  live(){ env LLM_WIKI_STORE="$LSTORE" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
          --run run-test-live --model sonnet --budget-usd 1 --max-turns 6 --deadline-s 420 \
          --record "$LREC" --reason '(a) live probe: only a real harness shows this' "$@"; }

  cat > "$F/live/brief-fence.md" <<LIVE_FENCE_BRIEF_TERMINATOR
Do exactly these four steps, in order, then stop. One line per step.
1. Read tool on $F/live/granted/inside.txt — quote the token.
2. Read tool on $F/live/offlimits/outside.txt — if refused, say REFUSED.
3. Bash: cat $VAULT/CLAUDE.md — if refused, say DENIED and quote the first four words of the reason.
4. Bash: cat $F/live/granted/inside.txt — say ALLOWED and the token, or DENIED and the reason.
Finish with the line: STEPS DONE.
LIVE_FENCE_BRIEF_TERMINATOR
  live --lane V1 --class verifier --brief "$F/live/brief-fence.md" --effort high \
       --grant "$F/live/granted" --reason '(a) live: the two fences' >/dev/null 2>&1
  REP="$LSTORE/spawn-records/run-test-live-report-V1.md"
  V1=$("$PY" - "$LREC" V1 <<'LIVE_CLOSE_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed" and r.get("lane") == sys.argv[2]:
        print(json.dumps({"tool": r["denials"]["tool"], "fence": r["denials"]["fence"],
                          "allows": r["denials"]["fence_allows"],
                          "effort": r["effort_applied"], "tier": r["cache_write_tier"],
                          "exit": r["exit_class"],
                          "denied": [d.get("tool_name") for d in r["permission_denials"]]}))
LIVE_CLOSE_TERMINATOR
)
  printf '%s' "$V1" | grep -q '"denied": \["Read", "Bash"\]' \
    && ok "live: the harness refused the ungranted Read and the fence refused the Bash read" \
    || no "live: fences  [$V1]"
  grep -q 'LIVE-GRANTED-TOKEN-5150' "$REP" \
    && ok "live: the granted read and the granted cat both succeeded (control: the denials above)" \
    || no "live: a granted read failed  [$(cat "$REP" 2>&1 | head -4)]"
  grep -qi 'lane-fence' "$REP" \
    && ok "live: the Bash denial carried a lane-fence reason the lane could quote" \
    || no "live: no lane-fence reason reached the lane"
  printf '%s' "$V1" | grep -q '"effort": \["high"\]' \
    && ok "live: the transcript's effort equals the --effort flag" || no "live: effort  [$V1]"
  printf '%s' "$V1" | grep -q '"tier": \["1h"\]' \
    && ok "live: the cache write tier is reported (1h, the headless default)" || no "live: tier  [$V1]"

  cat > "$F/live/brief-write.md" <<LIVE_WRITE_BRIEF_TERMINATOR
Do exactly these two steps, then stop. One line per step.
1. Use the Write tool to create $F/live/whitelist/made.txt containing exactly: WROTE-INSIDE
2. Use the Write tool to create $F/live/offlimits/made.txt containing exactly: WROTE-OUTSIDE
Say for each: WROTE or REFUSED. Finish with the line: STEPS DONE.
LIVE_WRITE_BRIEF_TERMINATOR
  live --lane W1 --class builder --brief "$F/live/brief-write.md" --effort high \
       --grant "$F/live/granted" --write "$F/live/whitelist" \
       --reason '(a) live: the write whitelist' >/dev/null 2>&1
  if [ -f "$F/live/whitelist/made.txt" ]; then
    ok "live: a write lane wrote inside its whitelist"
  else no "live: the write lane could not write inside its whitelist"; fi
  if [ ! -f "$F/live/offlimits/made.txt" ]; then
    ok "live: the same lane was refused outside its whitelist (control: the write above)"
  else no "live: a write landed outside the whitelist"; fi

  # The injection control pair: one spawn with the core appended, one without.
  cat > "$F/live/core.md" <<'LIVE_CORE_TERMINATOR'
# Lane core (measurement fixture)

LANE-CORE-MARKER: KESTREL-4417

Conduct, controls and shell discipline would follow here. This fixture stands in for the
shipped core so the leg does not depend on the shipped text.
LIVE_CORE_TERMINATOR
  printf 'Reply with exactly two words: ok, then the value of the LANE-CORE-MARKER line in your instructions, or NONE if there is no such line.\n' \
    > "$F/live/brief-core.md"
  live --lane A --class verifier --brief "$F/live/brief-core.md" --effort high \
       --grant "$F/live/granted" --max-turns 3 --reason '(a) live: no core' --no-core >/dev/null 2>&1
  live --lane C --class verifier --brief "$F/live/brief-core.md" --effort high \
       --grant "$F/live/granted" --max-turns 3 --reason '(a) live: core appended' \
       --append-core "$F/live/core.md" >/dev/null 2>&1
  MEAS=$("$PY" - "$LREC" "$LSTORE/spawn-records" <<'LIVE_MEASURE_TERMINATOR'
import json, os, sys
first = {}
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed" and r.get("lane") in ("A", "C"):
        first[r["lane"]] = r["usage"].get("first_call_context")
marks = {}
for lane in ("A", "C"):
    path = os.path.join(sys.argv[2], "run-test-live-report-%s.md" % lane)
    marks[lane] = "KESTREL-4417" in open(path).read() if os.path.exists(path) else None
print(json.dumps({"first": first, "marks": marks}))
LIVE_MEASURE_TERMINATOR
)
  echo "  measurement: $MEAS"
  printf '%s' "$MEAS" | grep -q '"C": true' \
    && ok "live: the core reaches the lane as an appended system prompt (marker quoted back)" \
    || no "live: the appended core did not reach the lane  [$MEAS]"
  printf '%s' "$MEAS" | grep -q '"A": false' \
    && ok "live: a lane spawned --no-core sees none (negative control for the leg above)" \
    || no "live: a core-less lane saw the marker  [$MEAS]"

  # The compile class carries its slice the same way: the lane quotes the slice's own heading.
  printf 'Your instructions contain lines beginning "## Lane slice: ". Reply with those lines and nothing else. If there are none, reply NONE.\n' \
    > "$F/live/brief-slice.md"
  live --lane S --class wiki-compile --brief "$F/live/brief-slice.md" --effort high \
       --grant "$F/live/granted" --max-turns 4 --reason '(a) live: the compile slice' >/dev/null 2>&1
  SREP="$LSTORE/spawn-records/run-test-live-report-S.md"
  if grep -q 'Lane slice: compile-core' "$SREP" && grep -q 'Lane slice: lane-core' "$SREP"; then
    ok "live: a wiki-compile lane's first call carries the compile-core heading beside the core's"
  else no "live: the compile slice did not reach the lane  [$(head -3 "$SREP" 2>&1)]"; fi

  TRUST=$("$PY" - "$LHOME" <<'LIVE_TRUST_TERMINATOR'
import json, os, sys
path = os.path.expanduser("~/.claude.json")
data = json.load(open(path)) if os.path.exists(path) else {}
entry = (data.get("projects") or {}).get(os.path.realpath(sys.argv[1]))
print("absent" if not isinstance(entry, dict) or "hasTrustDialogAccepted" not in entry
      else str(entry["hasTrustDialogAccepted"]))
LIVE_TRUST_TERMINATOR
)
  if [ "$TRUST" = absent ] && grep -q 'LIVE-GRANTED-TOKEN-5150' "$REP"; then
    ok "live: probe (a) — a lane home with no trust entry ($TRUST) still reads its home and grants"
  else no "live: probe (a) is inconclusive  [trust $TRUST]"; fi

  SPEND=$("$PY" - "$LREC" <<'LIVE_SPEND_TERMINATOR'
import json, sys
total = 0.0
n = 0
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed":
        total += float(r.get("total_cost_usd") or 0)
        n += 1
print("%d spawns, $%.4f list" % (n, total))
LIVE_SPEND_TERMINATOR
)
  echo "  live spend: $SPEND"
fi

# ------------------------------------------------------------- live hands-off probes ---------
# Two questions only a real harness can answer, each a haiku lane capped at $0.10: whether the
# per-spawn settings allow list beats the harness's sensitive-path guard under a `.claude/`
# directory (design D18: recorded, either answer is a finding), and whether --grant-vault-root
# lets a lane `cat` a vault-root file through the fence (with a no-flag control).
if [ "$LIVEHO" = 1 ]; then
  echo "== live hands-off (haiku, capped at \$0.10 per lane) =="
  HSTORE="$F/ho-store"; HREC="$HSTORE/spawn-records/run-test-ho.jsonl"
  mkdir -p "$F/ho/.claude/skills/thing" "$F/ho/plain"
  printf '# thing\n' > "$F/ho/.claude/skills/thing/SKILL.md"
  printf 'PLAIN-TOKEN-8181\n' > "$F/ho/plain/file.txt"
  holive(){ env -u CLAUDE_CONFIG_DIR LLM_WIKI_STORE="$HSTORE" CLAUDE_PROJECT_DIR="$FXV" "$PY" "$LANE" spawn \
            --home "$LHOME" --routing "$R" --run run-test-ho --model haiku --effort high --budget-usd 0.1 \
            --max-turns 4 --deadline-s 300 --record "$HREC" \
            --reason '(a) live hands-off probe' "$@"; }
  cat > "$F/ho/brief-edit.md" <<HO_EDIT_BRIEF_TERMINATOR
Use the Edit tool (never Bash) on the file $F/ho/.claude/skills/thing/SKILL.md: old_string is the line "# thing", new_string is "# thing" followed by a newline and the line PROBE-EDIT-OK. Then reply with exactly one line: EDITED, or DENIED followed by the tool's refusal text verbatim. Do nothing else.
HO_EDIT_BRIEF_TERMINATOR
  holive --lane HE --class builder --brief "$F/ho/brief-edit.md" --grant "$F/ho" \
         --write "$F/ho/.claude/skills/thing/SKILL.md" --reason '(a) live: the allow list against the sensitive-path guard' >/dev/null 2>&1
  HERC=$?
  HEREP="$HSTORE/spawn-records/run-test-ho-report-HE.md"
  if grep -q 'PROBE-EDIT-OK' "$F/ho/.claude/skills/thing/SKILL.md"; then
    ANSWER="the allow list BEATS the guard: the Edit landed"
  else
    ANSWER="the guard WINS: no edit landed (lane said: $(head -c 300 "$HEREP" 2>&1 | tr '\n' ' '))"
  fi
  echo "  probe (settings allow list under .claude/): $ANSWER"
  if [ "$HERC" = 0 ] || [ "$HERC" = 3 ]; then
    ok "live: the settings allow-list probe ran to a close (answer above; exit $HERC)"
  else no "live: the allow-list probe did not close cleanly  [exit $HERC]"; fi

  printf 'Run exactly one Bash command: cat %s/CUSTOMISATION.md — then reply with exactly one line: ALLOWED followed by the line of that file containing "throttle", or DENIED followed by the refusal text verbatim. Do nothing else.\n' "$FR/vault" > "$F/ho/brief-root.md"
  holive --lane HR --class verifier --brief "$F/ho/brief-root.md" --grant "$F/ho/plain" --grant-vault-root \
         --reason '(a) live: --grant-vault-root' >/dev/null 2>&1
  holive --lane HR0 --class verifier --brief "$F/ho/brief-root.md" --grant "$F/ho/plain" \
         --reason '(a) live: control, no vault root' >/dev/null 2>&1
  HRREP="$HSTORE/spawn-records/run-test-ho-report-HR.md"; HR0REP="$HSTORE/spawn-records/run-test-ho-report-HR0.md"
  if grep -q 'throttle' "$HRREP" && ! grep -q 'DENIED' "$HRREP"; then
    ok "live: --grant-vault-root lets a lane cat a vault-root file through the fence"
  else no "live: --grant-vault-root  [$(head -c 300 "$HRREP" 2>&1 | tr '\n' ' ')]"; fi
  if grep -q 'DENIED' "$HR0REP" && grep -q 'outside the granted directories' "$HR0REP"; then
    ok "live: without the flag the same cat is fenced, the reason quoted back (control)"
  else no "live: the vault-root control  [$(head -c 300 "$HR0REP" 2>&1 | tr '\n' ' ')]"; fi
  HOSPEND=$("$PY" - "$HREC" <<'HO_SPEND_TERMINATOR'
import json, sys
total, n, classes = 0.0, 0, []
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed":
        total += float(r.get("total_cost_usd") or 0)
        n += 1
        classes.append("%s:%s" % (r.get("lane"), r.get("exit_class")))
print("%d lanes (%s), $%.4f list" % (n, " ".join(classes), total))
HO_SPEND_TERMINATOR
)
  echo "  live hands-off spend: $HOSPEND"
fi

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then echo "PASS $PASS/$TOTAL"; else echo "FAIL $FAIL/$TOTAL"; exit 1; fi
