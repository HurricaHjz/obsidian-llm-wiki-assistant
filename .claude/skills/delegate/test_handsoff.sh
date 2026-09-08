#!/bin/sh
# test_handsoff.sh — the suite for handsoff.py (delegate skill, hands-off mode).
#
# Run:  sh test_handsoff.sh                       (from beside handsoff.py)
#       HANDSOFF=<path to handsoff.py> sh test_handsoff.sh
#
# Every fixture lives in a fresh directory under /tmp — never TMPDIR, which on this platform
# points at a per-user root outside the temp directory a lane is granted — and is removed on
# exit; HANDSOFF_KEEP=1 keeps it for a post-mortem. The suite writes nothing anywhere else,
# and the last three legs are the proof: a checksum manifest of the shipped skill directory
# and of the hooks directory taken before the legs and again after, that manifest's own
# positive control (a modified copy must show a difference), and a scan of this file for a
# write verb aimed at an absolute path outside /tmp, with a planted control that must hit.
#
# Every leg that reports a clean result carries its positive control on the same run: each
# refusal leg plants the case that must be caught (a second run-open, an append-only key, a
# missing table, an armed band crossing, a second unmetered gate, a duplicate successor).
#
# The last line is PASS n/n or FAIL k/n; the exit code is 0 only when every leg passed.
set -u

PY=${PYTHON:-python3}
SRC=$0
H=${HANDSOFF:-$(dirname "$SRC")/handsoff.py}

die() { printf 'PROBE FAILED: %s\n' "$1" >&2; exit 2; }

command -v "$PY" >/dev/null || die "no python3 on PATH"
command -v git >/dev/null || die "no git on PATH: the checkpoint-commit legs cannot run"
[ -f "$H" ] || die "no handsoff.py at $H (pass HANDSOFF=<path>)"
SKILL_DIR=$(cd "$(dirname "$H")" && pwd) || die "cannot resolve the directory of $H"
# A staged copy names the shipped modules: HOOKS_DIR (context-watermark.py) and LANE_PY (the
# lane wrapper, imported for its classifier); beside the vault's script tree both default.
HOOKS_DIR=${HOOKS_DIR:-$(cd "$SKILL_DIR/../../hooks" 2>&1 && pwd)}
LANE_PY=${LANE_PY:-$SKILL_DIR/lane.py}
[ -f "$HOOKS_DIR/context-watermark.py" ] || die "no context-watermark.py under $HOOKS_DIR (set HOOKS_DIR)"
[ -f "$LANE_PY" ] || die "no lane.py at $LANE_PY (set LANE_PY)"
export AIMYTH_HOOKS_DIR="$HOOKS_DIR"
export AIMYTH_LANE_PY="$LANE_PY"

WORK=$(mktemp -d /tmp/handsoff-suite.XXXXXX) || die "cannot make a temp directory under /tmp"
case $WORK in
  /tmp/*|/private/tmp/*) : ;;
  *) die "the temp directory $WORK is not under /tmp" ;;
esac
cleanup() { [ "${HANDSOFF_KEEP:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# The target must import before anything else is claimed about it; the byte-code file goes to
# the temp directory, because py_compile ignores -B and the vault takes no __pycache__.
"$PY" -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
      "$H" "$WORK/handsoff.pyc" || die "handsoff.py does not compile"

STORE="$WORK/store"
PROJECTS="$WORK/projects"
STATE="$WORK/state"
VAULT="$WORK/vault"
REMOTE="$WORK/remote.git"
MK="$WORK/mk.py"
mkdir -p "$STORE/spawn-records" "$PROJECTS" "$STATE" "$VAULT" "$WORK/handoffs" "$WORK/starter" \
         "$WORK/psclaude" "$WORK/psnone" "$WORK/bin"

# One environment for every call: the run store, the projects root, the arming marker root and
# the vault are all fixtures, so no call can reach the real store, transcripts or work tree.
export LLM_WIKI_STORE="$STORE"
export AIMYTH_PROJECTS_DIR="$PROJECTS"
export AIMYTH_STATE_DIR="$STATE"
export CLAUDE_PROJECT_DIR="$VAULT"
export AIMYTH_BANDS="60,80,90"
export AIMYTH_CONTEXT_WINDOW="1000000"
export PYTHONDONTWRITEBYTECODE=1
export LLM_WIKI_LANE_HOME="$WORK/lane-home"
unset AIMYTH_HANDSOFF
unset AIMYTH_WATERMARK_LOG
unset AIMYTH_HANDSOFF_RUN
# The stub head reads these: it is started by the supervisor with the suite's environment.
SUITE_WORK="$WORK"; SUITE_PY="$PY"; SUITE_MK="$MK"; SUITE_STORE="$STORE"
export SUITE_WORK SUITE_PY SUITE_MK SUITE_STORE

# The billed line every metered leg passes in place of running the meter: its shape is the one
# the run's own hand-off carries (head/lanes/session/rewrites/reasons), so the field parsers
# are tested against a real line rather than a convenient one.
METER='billed (list 2026-09-03) · head $14.49 · lanes $5.12 · session $19.62 · rewrites 3 ($0.12) · tool uses/call head 2.05 lanes 5.80 · delegation multi (owner) · lanes 1 (reasons: (a)×1 (b)×0 (c)×0 (d)×0, none×0) · metered 1 of 1'

# ------------------------------------------------------------------ the fixture toolkit ----
cat > "$MK" <<'MKPY'
#!/usr/bin/env python3
"""Fixtures and an independent oracle for test_handsoff.sh.

Writes only under the suite's temp directory (every path it is given comes from there); every
query command prints to standard output and writes nothing. The document and record parsers
here are written from the schema, not imported from handsoff.py, so a leg that passes agrees
with an independent reading rather than with the code under test.
"""
import hashlib
import json
import os
import re
import sys
import time

BLOCKS = [
    ("morning", "## Morning report (rewritten at every boundary)", [
        "- **What shipped:** nothing yet.",
        "- **Waits for you:** nothing yet.",
        "- **Register delta:** none.",
        "- **Spend against the envelope:** unmetered.",
        "- **Measured head-load saving:** n/a until the parity run.",
        "- **Warnings raised and handling:** see `## Findings ledger` (9 lines; a wrong figure "
        "on purpose, so a refresh is observable).",
        "- **Resume prompt:** below.",
    ]),
    ("resume", "## Resume prompt (paste into a new conversation if this session is gone)", [
        "Resume the fixture run: read this hand-off in full, then continue at the next item.",
    ]),
    ("inflight", "## In flight", ["- nothing in flight."]),
    ("grants", "## Grants", ["- fixture grants."]),
    ("ledger", "## Findings ledger (one line per warning · issue · finding · lesson)", [
        "| Time | Phase | What | Evidence | Routing |",
        "|---|---|---|---|---|",
        "| 01:00 | 0 | fixture finding one | fixture evidence | no action |",
        "| 01:01 | 0 | fixture finding two | fixture evidence | no action |",
    ]),
    ("trace", "## Trace (one row per decision and boundary)", [
        "| Time | Item | Decision and its rule | Billed line | Waste so far |",
        "|---|---|---|---|---|",
        "| 01:02 | open → 1 | fixture decision | fixture billed line | fixture waste |",
    ]),
    ("decoy", "## Trace archive (a decoy: the row must land in the FIRST trace table)", [
        "| Time | Item | Decision and its rule | Billed line | Waste so far |",
        "|---|---|---|---|---|",
        "| 00:01 | archived | decoy row | decoy | decoy |",
    ]),
    ("plan", "## Plan of record", ["- fixture plan."]),
    ("pointers", "## Pointers", ["- fixture pointers."]),
]


def out(text):
    sys.stdout.write(str(text) + "\n")


def stamp(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(epoch))


def dashed(path):
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(path))


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def read_lines(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().split("\n")


def events_of(path):
    found = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                found.append(json.loads(line))
    return found


def heading_index(lines, name):
    for i, line in enumerate(lines):
        if line.startswith("## ") and line[3:].strip().lower().startswith(name.lower()):
            return i
    return -1


def section_end(lines, start):
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## ") or lines[i].startswith("# "):
            return i
    return len(lines)


def table(lines, name):
    i = heading_index(lines, name)
    if i < 0:
        return []
    end = section_end(lines, i)
    rows = []
    started = False
    for j in range(i + 1, end):
        if lines[j].lstrip().startswith("|"):
            started = True
            rows.append(lines[j])
        elif started:
            break
    return rows[2:] if len(rows) > 2 else []


def cmd_handoff(argv):
    path = argv[0]
    drop = [x for x in (argv[1] if len(argv) > 1 else "").split(",") if x]
    body = ["# Fixture hand-off (a suite fixture, not a vault page)", ""]
    for key, heading, lines in BLOCKS:
        if key in drop:
            continue
        body.append(heading)
        body.extend(lines)
        body.append("")
    write(path, "\n".join(body))
    out(path)


def cmd_record(argv):
    path, run, session, handoff, envelope = argv[:5]
    base = time.time() - 7200
    ev = {"ts": stamp(base), "run": run, "event": "run-open", "session": session,
          "head": "fixture head", "regime": "multi", "regime_src": "owner",
          "handoff": os.path.realpath(handoff), "detail": "fixture run", "pid_src": "none"}
    if envelope != "none":
        ev["envelope_usd"] = float(envelope)
    write(path, json.dumps(ev, ensure_ascii=False) + "\n")
    out(path)


def append(path, ev):
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(ev, ensure_ascii=False) + "\n")


def cmd_append(argv):
    path, payload = argv[0], argv[1]
    ev = json.loads(payload)
    first = events_of(path)[0]
    ev.setdefault("run", first.get("run"))
    ev.setdefault("ts", stamp(time.time()))
    append(path, ev)
    out(ev["event"])


def cmd_waste(argv):
    """The planted close-outs behind the five waste fields.

    Offsets from a base two hours old, so every figure is fixed whatever the wall clock says:
    closes at +60 s, +120 s and +150 s, and the head's next act (an observation) at +300 s.
    Idle = (300-60 + 300-120 + 300-150) / 60 = 9.5 min; denials 2 (a wrapper count) + 1 (a
    denial list) = 3; one report over the 800-word cap (971 words, the figure this run's own
    record carries); re-spawn cost $5.00 from the one close that did not complete; one report
    that cannot be word-counted (the path does not exist).
    """
    path, run, missing = argv[0], argv[1], argv[2]
    base = time.time() - 7200
    append(path, {"ts": stamp(base + 60), "run": run, "event": "lane-closed", "lane": "L1",
                  "exit_class": "budget", "total_cost_usd": 5.0,
                  "denials": {"tool": 2, "fence": 1}, "permission_denials": [],
                  "report_words": 971})
    append(path, {"ts": stamp(base + 120), "run": run, "event": "lane-closed", "lane": "L2",
                  "exit_class": "completed", "total_cost_usd": 1.25,
                  "permission_denials": [{"tool": "Edit"}], "report_words": 12})
    append(path, {"ts": stamp(base + 150), "run": run, "event": "lane-closed", "lane": "L3",
                  "exit_class": "watch-closed", "total_cost_usd": 0.0, "report": missing})
    append(path, {"ts": stamp(base + 300), "run": run, "event": "observation", "phase": "2",
                  "what": "the head's next act", "note": "closes the idle windows"})
    out("waste fixtures planted")


def cmd_transcript(argv):
    """A transcript the watermark hook's measure() will meter: one assistant usage record
    whose three stock keys sum to the tokens asked for."""
    sid, tokens = argv[0], int(argv[1])
    first = int(argv[2]) if len(argv) > 2 else None   # an optional earlier record (orientation)
    path = os.path.join(os.environ["AIMYTH_PROJECTS_DIR"],
                        dashed(os.environ["CLAUDE_PROJECT_DIR"]), "%s.jsonl" % sid)

    def rec(n):
        return {"type": "assistant", "isSidechain": False,
                "message": {"role": "assistant", "model": "claude-fixture-1",
                            "usage": {"input_tokens": n - 2, "cache_read_input_tokens": 1,
                                      "cache_creation_input_tokens": 1}}}
    recs = ([rec(first)] if first is not None else []) + [rec(tokens)]
    write(path, "".join(json.dumps(r) + "\n" for r in recs))
    out(path)


def cmd_untranscript(argv):
    path = os.path.join(os.environ["AIMYTH_PROJECTS_DIR"],
                        dashed(os.environ["CLAUDE_PROJECT_DIR"]), "%s.jsonl" % argv[0])
    if os.path.isfile(path):
        os.remove(path)
    out("removed" if not os.path.exists(path) else "still there")


def transcript_path(sid, root=None):
    return os.path.join(root or os.environ["AIMYTH_PROJECTS_DIR"],
                        dashed(os.environ["CLAUDE_PROJECT_DIR"]), "%s.jsonl" % sid)


def cmd_xscript(argv):
    """One transcript record of every class the extractor must tell apart: a human turn, an
    assistant turn carrying prose and a tool call, a tool-result record, a Skill-tool
    injection (isMeta), a harness injection (a record that is nothing but a system reminder),
    an assistant record of tool calls only, and a torn line."""
    sid = argv[0]
    root = argv[1] if len(argv) > 1 else None
    recs = [
        {"type": "user", "timestamp": "2026-09-05T20:00:00Z",
         "message": {"role": "user",
                     "content": [{"type": "text", "text": "the human turn asks"}]}},
        {"type": "assistant", "timestamp": "2026-09-05T20:00:10Z",
         "message": {"role": "assistant", "model": "claude-fixture-1",
                     "content": [{"type": "text", "text": "the assistant answers in prose"},
                                 {"type": "tool_use", "name": "Bash", "input": {}}]}},
        {"type": "user", "timestamp": "2026-09-05T20:00:20Z",
         "message": {"role": "user", "content": [{"type": "tool_result",
                                                  "content": "tool output text"}]}},
        {"type": "user", "isMeta": True, "timestamp": "2026-09-05T20:00:30Z",
         "message": {"role": "user",
                     "content": [{"type": "text",
                                  "text": "Base directory for this skill: fixture"}]}},
        {"type": "user", "timestamp": "2026-09-05T20:00:40Z",
         "message": {"role": "user",
                     "content": [{"type": "text",
                                  "text": "<system-reminder>injected</system-reminder>"}]}},
        {"type": "assistant", "timestamp": "2026-09-05T20:00:50Z",
         "message": {"role": "assistant",
                     "content": [{"type": "tool_use", "name": "Read", "input": {}}]}},
    ]
    path = transcript_path(sid, root)
    write(path, "".join(json.dumps(r) + "\n" for r in recs) + "{a torn line\n")
    out(path)


def cmd_toolscript(argv):
    """A transcript for the tool-call extraction (register entry 2026-09-07): an assistant
    record of tool calls alone, one carrying prose AND a call, one whose command runs past the
    300-character cut, a tool result that must stay out, and a harness injection. Six records:
    2 extracted + 2 tool-call + 2 excluded, so a leg can check the arithmetic."""
    recs = [
        {"type": "user", "timestamp": "2026-09-07T10:00:00Z",
         "message": {"role": "user",
                     "content": [{"type": "text", "text": "the human turn asks"}]}},
        {"type": "assistant", "timestamp": "2026-09-07T10:00:10Z",
         "message": {"role": "assistant", "model": "claude-fixture-1", "content": [
             {"type": "tool_use", "name": "Bash",
              "input": {"command": "git status --porcelain", "description": "status"}},
             {"type": "tool_use", "name": "Read", "input": {"file_path": "/fixture/page.md"}},
             {"type": "tool_use", "name": "Grep",
              "input": {"pattern": "needle", "output_mode": "content"}},
             {"type": "tool_use", "name": "TodoWrite", "input": {"todos": []}}]}},
        {"type": "assistant", "timestamp": "2026-09-07T10:00:20Z",
         "message": {"role": "assistant", "model": "claude-fixture-1", "content": [
             {"type": "text", "text": "the assistant answers in prose and edits"},
             {"type": "tool_use", "name": "Edit",
              "input": {"file_path": "/fixture/other.md", "old_string": "a", "new_string": "b"}}]}},
        {"type": "user", "timestamp": "2026-09-07T10:00:30Z",
         "message": {"role": "user", "content": [
             {"type": "tool_result",
              "content": "the tool result never reaches the extraction"}]}},
        {"type": "assistant", "timestamp": "2026-09-07T10:00:40Z",
         "message": {"role": "assistant", "model": "claude-fixture-1", "content": [
             {"type": "tool_use", "name": "Bash", "input": {"command": "y" * 400}}]}},
        {"type": "user", "timestamp": "2026-09-07T10:00:50Z",
         "message": {"role": "user",
                     "content": [{"type": "text",
                                  "text": "<system-reminder>injected</system-reminder>"}]}},
    ]
    path = transcript_path(argv[0])
    write(path, "".join(json.dumps(r) + "\n" for r in recs))
    out(path)


def cmd_metascript(argv):
    """A transcript of injected user records only: nothing to extract, and not a failure."""
    recs = [
        {"type": "user", "isMeta": True, "timestamp": "2026-09-05T20:00:00Z",
         "message": {"role": "user", "content": [{"type": "text", "text": "skill injection"}]}},
        {"type": "user", "isMeta": True, "timestamp": "2026-09-05T20:00:10Z",
         "message": {"role": "user",
                     "content": [{"type": "text",
                                  "text": "Base directory for this skill: fixture"}]}},
        {"type": "user", "timestamp": "2026-09-05T20:00:20Z",
         "message": {"role": "user",
                     "content": [{"type": "text",
                                  "text": "<system-reminder>injected</system-reminder>"}]}},
    ]
    path = transcript_path(argv[0])
    write(path, "".join(json.dumps(r) + "\n" for r in recs))
    out(path)


def cmd_replayscript(argv):
    """The two harness shapes that read as the head's own words unless they are handled: a
    resume replay (a whole prior conversation re-sent as ONE user record, ending with the
    message the owner typed), a replay carrying no human marker at all, a synthetic assistant
    record (the harness's stop text), and — as the control for that skip — an ordinary
    assistant record whose text is the same stop words. Two ordinary turns open the file."""
    recs = [
        {"type": "user", "timestamp": "2026-09-06T09:00:00Z",
         "message": {"role": "user",
                     "content": [{"type": "text", "text": "the plain human turn"}]}},
        {"type": "assistant", "timestamp": "2026-09-06T09:00:10Z",
         "message": {"role": "assistant", "model": "claude-fixture-1",
                     "content": [{"type": "text",
                                  "text": "the assistant answers in prose"}]}},
        {"type": "user", "timestamp": "2026-09-06T09:00:20Z",
         "message": {"role": "user", "content": [{"type": "text", "text":
                     "User: an earlier replayed turn\n"
                     "Assistant: an earlier replayed answer\n"
                     "User: the owner's real message"}]}},
        {"type": "assistant", "timestamp": "2026-09-06T09:00:30Z",
         "message": {"role": "assistant", "model": "<synthetic>",
                     "content": [{"type": "text", "text": "No response requested."}]}},
        {"type": "user", "timestamp": "2026-09-06T09:00:40Z",
         "message": {"role": "user", "content": [{"type": "text", "text":
                     "Assistant: a replay with no human marker\n"
                     "Assistant: and a second replayed answer"}]}},
        {"type": "assistant", "timestamp": "2026-09-06T09:00:50Z",
         "message": {"role": "assistant", "model": "claude-fixture-1",
                     "content": [{"type": "text", "text": "No response requested."}]}},
        # The residue: a prompt the owner typed that OPENS by quoting a conversation reads as a
        # replay. Trimming keeps everything after its last human marker, so the owner's own
        # trailing question survives (over-inclusive and visible, never dropped).
        {"type": "user", "timestamp": "2026-09-06T09:01:00Z",
         "message": {"role": "user", "content": [{"type": "text", "text":
                     "User: what did I say here\n"
                     "Assistant: you said that\n"
                     "what do you make of it"}]}},
    ]
    path = transcript_path(argv[0])
    write(path, "".join(json.dumps(r) + "\n" for r in recs))
    out(path)


def cmd_json(argv):
    """One dotted key from a JSON file, so a leg compares a value rather than a substring."""
    with open(argv[0], "r", encoding="utf-8") as handle:
        data = json.load(handle)
    for key in argv[1].split("."):
        if not isinstance(data, dict) or key not in data:
            out("<no key %s>" % argv[1])
            return
        data = data[key]
    out(data if isinstance(data, str) else json.dumps(data))


def cmd_field(argv):
    path, kind, key = argv[0], argv[1], argv[2]
    found = [e for e in events_of(path) if e.get("event") == kind]
    if not found:
        out("<no %s event>" % kind)
        return
    value = found[-1].get(key, "<no key %s>" % key)
    out(value if isinstance(value, str) else json.dumps(value, ensure_ascii=False))


def cmd_count(argv):
    path, kind = argv[0], argv[1]
    out(sum(1 for e in events_of(path) if e.get("event") == kind))


def cmd_lines(argv):
    out(len(events_of(argv[0])) if os.path.isfile(argv[0]) else 0)


def cmd_rows(argv):
    out(len(table(read_lines(argv[0]), argv[1])))


def cmd_row(argv):
    rows = table(read_lines(argv[0]), argv[1])
    idx = int(argv[2])
    out(rows[idx] if -len(rows) <= idx < len(rows) else "<no row %s>" % idx)


def cmd_section(argv):
    lines = read_lines(argv[0])
    i = heading_index(lines, argv[1])
    if i < 0:
        out("<no section %s>" % argv[1])
        return
    out(" ".join(x.strip() for x in lines[i + 1:section_end(lines, i)] if x.strip()))


def cmd_bullet(argv):
    lines = read_lines(argv[0])
    i = heading_index(lines, "Morning report")
    if i < 0:
        out("<no morning report>")
        return
    pat = re.compile(r"^\s*[-*]\s+\*\*%s:?\*\*:?\s*(.*)$" % re.escape(argv[1]))
    for j in range(i + 1, section_end(lines, i)):
        m = pat.match(lines[j])
        if m:
            out(m.group(1))
            return
    out("<no bullet %s>" % argv[1])


def cmd_manifest(argv):
    """sha256, size and path for every file under the directories given: the write-proof's
    before-and-after comparison, and the only thing that can show a stray __pycache__."""
    for root in argv:
        for base, dirs, files in os.walk(root):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(base, name)
                try:
                    with open(full, "rb") as handle:
                        digest = hashlib.sha256(handle.read()).hexdigest()
                    size = os.path.getsize(full)
                except OSError as exc:
                    digest, size = "unreadable", str(exc)
                out("%s %s %s" % (digest, size, full))


ALLOWED = ("/tmp", "/private/tmp", "/dev/null", "/dev/stdout", "/dev/stderr")
VERB = re.compile(r"(?:(?<![0-9&])>>?|\b(?:cp|mv|rm|tee|touch|mkdir|install|truncate|dd|ln)\b"
                  r"|sed\s+-i)")
ABS = re.compile(r"(?:^|[\s\"'=(:,])(/[A-Za-z0-9_.@%+-][^\s\"';|)]*)")


def cmd_srcscan(argv):
    """Every line carrying a write verb is checked for an absolute path outside the temp root:
    the suite's own source must score zero, and the planted control file must not."""
    hits = 0
    with open(argv[0], "r", encoding="utf-8", errors="replace") as handle:
        for i, line in enumerate(handle, 1):
            text = line.rstrip("\n")
            if not VERB.search(text):
                continue
            for m in ABS.finditer(text):
                token = m.group(1)
                if token.startswith(ALLOWED):
                    continue
                hits += 1
                out("hit line %d: %s" % (i, text.strip()[:110]))
    out("hits %d" % hits)


COMMANDS = {"handoff": cmd_handoff, "record": cmd_record, "append": cmd_append,
            "waste": cmd_waste, "transcript": cmd_transcript, "untranscript": cmd_untranscript,
            "field": cmd_field, "count": cmd_count, "lines": cmd_lines, "rows": cmd_rows,
            "row": cmd_row, "section": cmd_section, "bullet": cmd_bullet,
            "manifest": cmd_manifest, "srcscan": cmd_srcscan, "xscript": cmd_xscript,
            "metascript": cmd_metascript, "replayscript": cmd_replayscript,
            "toolscript": cmd_toolscript, "json": cmd_json}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.stderr.write("mk.py: unknown command %r\n" % (sys.argv[1:2],))
        sys.exit(2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
MKPY

# The parent-walk stub: every ps row answers `claude`, so the walk stops at the first parent.
cat > "$WORK/psclaude/ps" <<'PSC'
#!/bin/sh
# ps -o pid=,ppid=,comm= -p PID  →  "<pid> 1 claude"
printf '%s 1 claude\n' "$4"
PSC
# The no-ancestor stub: no row at all, so the walk gives up and the pid source is `none`.
cat > "$WORK/psnone/ps" <<'PSN'
#!/bin/sh
exit 1
PSN
# The harness stub: reads the resume prompt from standard input, as the real starter feeds it.
cat > "$WORK/bin/harness" <<STUB
#!/bin/sh
cat > "$WORK/harness-stdin.txt"
printf 'stub harness: args %s\n' "\$*"
STUB
# The stub head for the supervisor legs, driven by its environment: STUB_MODE (limit, nolimit,
# budget, error, complete, nojson, handonly) applies to the first STUB_N invocations; every
# later one hands over as a real head does (head-exit, then its own head-successor) and prints
# a success result. STUB_TOKENS makes it write the transcript the harness would for a fresh
# --session-id. A probe call (--model haiku) fails once, then succeeds. Every invocation
# appends its argv, keeps its stdin and records AIMYTH_HANDSOFF_RUN, keyed by the run.
cat > "$WORK/bin/stubhead" <<'STUBHEAD'
#!/bin/sh
RUN=${AIMYTH_HANDSOFF_RUN:-none}
REC="$SUITE_STORE/spawn-records/$RUN.jsonl"
case " $* " in
  *" --model haiku "*)
    PC="$SUITE_WORK/stub-probe.count"; n=0; [ -f "$PC" ] && n=$(cat "$PC"); n=$((n + 1)); echo "$n" > "$PC"
    if [ "$n" -le 1 ]; then
      printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"You have hit your session limit"}'; exit 1
    fi
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"OK","total_cost_usd":0.01}'; exit 0 ;;
esac
CF="$SUITE_WORK/stub-$RUN.count"; n=0; [ -f "$CF" ] && n=$(cat "$CF"); n=$((n + 1)); echo "$n" > "$CF"
printf '%s\n' "$*" >> "$SUITE_WORK/stub-$RUN.args"
printf '%s\n' "${AIMYTH_HANDSOFF_RUN:-unset}" > "$SUITE_WORK/stub-$RUN.env"
cat > "$SUITE_WORK/stub-$RUN.stdin.$n"
sid=""; prev=""
for arg in "$@"; do [ "$prev" = "--session-id" ] && sid=$arg; prev=$arg; done
[ -n "$sid" ] && [ -n "${STUB_TOKENS:-}" ] && "$SUITE_PY" "$SUITE_MK" transcript "$sid" "$STUB_TOKENS" >/dev/null
if [ "$n" -le "${STUB_N:-1}" ]; then
  case ${STUB_MODE:-complete} in
    limit) printf '%s\n' "{\"type\":\"result\",\"subtype\":\"error_during_execution\",\"is_error\":true,\"result\":\"You've hit your session limit · resets 8:50am (Europe/London)\"}"; exit 1 ;;
    nolimit) printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Usage limit reached for this session"}'; exit 1 ;;
    budget) printf '%s\n' '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"result":"the budget cap was reached"}'; exit 1 ;;
    error) printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"the stub failed"}'; exit 1 ;;
    complete) printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"done without a hand-off"}'; exit 0 ;;
    nojson) printf 'stub: no result line at all\n'; exit 0 ;;
    handonly) "$SUITE_PY" "$SUITE_MK" append "$REC" '{"event":"head-exit","band":60,"context":"stub","spent_usd":1.0,"pack":true}' >/dev/null
      printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"handed off, died before successor"}'; exit 0 ;;
  esac
fi
"$SUITE_PY" "$SUITE_MK" append "$REC" '{"event":"head-exit","band":60,"context":"stub","spent_usd":1.0,"pack":true}' >/dev/null
"$SUITE_PY" "$SUITE_MK" append "$REC" '{"event":"head-successor","session_id":"sid-by-the-head","pid":1,"budget":1.0}' >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"handed over"}'
exit 0
STUBHEAD
cat > "$WORK/bin/harness2" <<STUB2
#!/bin/sh
cat > "$WORK/harness2-stdin.txt"
printf 'stub harness 2 started\n'
STUB2

# The viewer stubs (the console window, IDEAS №139 A2). AIMYTH_VIEWER_CMD replaces the whole
# opener command, so with it set NO LEG OF THIS SUITE EVER REACHES osascript OR open AND NO
# REAL TERMINAL WINDOW IS EVER OPENED. It is exported for every call below, and the legs that
# test a failure point it at the failing stub or unset it with an empty PATH instead.
# The recording stub appends its whole argv, one argument per line, to the file the current leg
# named in AIMYTH_VIEWER_ARGV: a per-leg file, so a detached starter that opens late can never
# land in a later leg's count.
cat > "$WORK/bin/viewer-stub.sh" <<'VSTUB'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a" >> "$AIMYTH_VIEWER_ARGV"; done
exit 0
VSTUB
cat > "$WORK/bin/viewer-fail.sh" <<'VFAIL'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a" >> "$AIMYTH_VIEWER_ARGV"; done
printf 'stub viewer: this window refuses to open\n' >&2
exit 1
VFAIL
mkdir -p "$WORK/nopath"          # an empty directory: PATH with neither osascript nor open
chmod +x "$WORK/psclaude/ps" "$WORK/psnone/ps" "$WORK/bin/harness" "$WORK/bin/harness2" \
         "$WORK/bin/stubhead" "$WORK/bin/viewer-stub.sh" "$WORK/bin/viewer-fail.sh"
export AIMYTH_VIEWER_CMD="$WORK/bin/viewer-stub.sh"
export AIMYTH_VIEWER_ARGV="$WORK/viewer-default.argv"

# The planted control for the source scan: two write lines aimed outside the temp root, which
# the scan must catch. The target is assembled here rather than written out, so that this
# file's own source carries no absolute write target for the scan to trip over.
CTRL_DIR="/Users""/example/vault/wiki"
{ printf 'cp "$f" %s/index.md\n' "$CTRL_DIR"
  printf 'printf x > %s/log.md\n' "$CTRL_DIR"; } > "$WORK/planted-writer.sh"

# The fixture work tree and its bare remote: every commit leg runs here, never in the vault.
git -c init.defaultBranch=main init -q "$VAULT" || die "cannot init the fixture work tree"
git -C "$VAULT" config user.name "Fixture Owner" || die "cannot set the fixture author name"
git -C "$VAULT" config user.email "owner@example.invalid" || die "cannot set the fixture email"
git -C "$VAULT" config commit.gpgsign false || die "cannot disable signing in the fixture"
git -c init.defaultBranch=main init -q --bare "$REMOTE" || die "cannot init the bare remote"
git -C "$VAULT" remote add origin "$REMOTE" || die "cannot add the fixture remote"
printf 'fixture work tree\n' > "$VAULT/README.md"
git -C "$VAULT" add -A || die "cannot stage the fixture tree"
git -C "$VAULT" commit -q -m "fixture: initial" || die "cannot make the fixture commit"
git -C "$VAULT" push -q -u origin HEAD || die "cannot set the fixture upstream"

# ------------------------------------------------------------------------ leg plumbing -----
N=0; PASSED=0; FAILED=0; why=""; RUNENV=""

run() {
  RC=0
  env $RUNENV "$PY" -B "$H" "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
  cat "$WORK/out" "$WORK/err" >"$WORK/both"
  RUNENV=""
}

mk() { "$PY" "$MK" "$@"; }
real() { "$PY" -c 'import os, sys; sys.stdout.write(os.path.realpath(sys.argv[1]))' "$1"; }
# handsoff.py resolves the store to its real path (a symlinked /tmp on this platform), so the
# paths it prints and records are compared against this spelling.
REALSTORE=$(real "$STORE")

need_rc() { [ "$RC" = "$1" ] || why="$why; exit $RC, wanted $1"; }
need_out() { grep -q -- "$1" "$WORK/both" || why="$why; output lacks '$1'"; }
need_absent() { if grep -q -- "$1" "$WORK/both"; then why="$why; output carries '$1'"; fi; }
need_eq() { [ "$1" = "$2" ] || why="$why; $3: '$1' != '$2'"; }
need_file() { [ -f "$1" ] || why="$why; no file $1"; }
need_nofile() { [ ! -e "$1" ] || why="$why; file $1 exists"; }
need_lines() { # one line only, for a refusal
  n=$(grep -c 'PROBE FAILED' "$WORK/err")
  [ "$n" = "1" ] || why="$why; $n PROBE FAILED lines, wanted 1"
}
wait_field() { # $1 record, $2 kind, $3 key, $4 value, $5 tries of 0.5 s: a detached process
  i=0
  while [ "$i" -lt "$5" ]; do
    [ "$(mk field "$1" "$2" "$3")" = "$4" ] && return 0
    sleep 0.5; i=$((i + 1))
  done
  why="$why; no $2.$3 = '$4' within $5 half-seconds"; return 1
}
starter() { # a foreground starter run: the stubs exit at once, so the loop ends by itself
  RC=0
  env $RUNENV "$PY" -B "$H" _starter "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
  cat "$WORK/out" "$WORK/err" >"$WORK/both"
  RUNENV=""
}
verdict() {
  N=$((N + 1))
  if [ -z "$why" ]; then
    PASSED=$((PASSED + 1)); printf 'ok   %2d  %s\n' "$N" "$1"
  else
    FAILED=$((FAILED + 1)); printf 'FAIL %2d  %s —%s\n' "$N" "$1" "$why"
  fi
  why=""
}

fixture() { # $1 tag, $2 envelope, $3 optional dropped section
  HO="$WORK/handoffs/$1-handoff.md"
  REC="$STORE/spawn-records/$1.jsonl"
  rm -f "$REC"
  mk handoff "$HO" "${3:-}" >/dev/null
  mk record "$REC" "$1" "sid-$1" "$HO" "$2" >/dev/null
}
plain_fixture() { # $1 tag: the plain-lane-run shape — lane events, NO run-open, no hand-off
  REC="$STORE/spawn-records/$1.jsonl"
  rm -f "$REC"
  "$PY" - "$REC" "$1" <<'PLAINREC'
import json, os, sys, time

path, run = sys.argv[1], sys.argv[2]
base = time.time() - 3600


def stamp(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(t))


rows = [
    {"event": "lane-open", "lane": "L1", "class": "builder", "model": "fable", "effort": "max"},
    {"event": "lane-spawned", "lane": "L1", "session_id": "sid-plain-l1", "pid": 3001},
    {"event": "lane-closed", "lane": "L1", "exit_class": "completed", "total_cost_usd": 2.50},
    {"event": "lane-open", "lane": "L2", "class": "critic", "model": "opus", "effort": "max"},
    {"event": "lane-closed", "lane": "L2", "exit_class": "error", "total_cost_usd": 1.25},
    {"event": "lane-open", "lane": "L3", "class": "verifier", "model": "fable", "effort": "high"},
]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    for i, row in enumerate(rows):
        row.update(ts=stamp(base + i * 60), run=run)
        fh.write(json.dumps(row) + "\n")
PLAINREC
}
arm_resume() { # $1 run: the pre-flight's limit-off (D42) — the grants file carries on_limit resume
  run grants --run "$1" --on-limit resume
  [ "$RC" = 0 ] || die "cannot arm on_limit resume for $1: $(cat "$WORK/both")"
}
gval() { "$PY" -c 'import json, sys; print(json.load(open(sys.argv[1])).get("on_limit"))' "$1"; }
vval() { "$PY" -c 'import json, sys; print(json.load(open(sys.argv[1])).get("viewer"))' "$1"; }
# The viewer stub's recording file, one per leg (see the stub above).
VIEWER_ARGV="$WORK/viewer-default.argv"
viewer_use() { VIEWER_ARGV="$WORK/viewer-$1.argv"; rm -f "$VIEWER_ARGV"
               export AIMYTH_VIEWER_ARGV="$VIEWER_ARGV"; }
viewer_calls() { if [ -f "$VIEWER_ARGV" ]; then grep -c . "$VIEWER_ARGV"; else echo 0; fi; }
viewer_has() { [ -f "$VIEWER_ARGV" ] || return 1; grep -q -F -- "$1" "$VIEWER_ARGV"; }
need_viewer_arg() { viewer_has "$1" || why="$why; the viewer stub was not called with '$1'"; }
need_no_viewer() { n=$(viewer_calls)
                   [ "$n" = "0" ] || why="$why; the viewer stub was called ($n arguments)"; }
console_cmd() { printf '%s/spawn-records/%s-console.command\n' "$REALSTORE" "$1"; }
# A live console to plant: a process whose command line carries the marker in one of the two
# spellings, so console_alive() finds it exactly as it finds a real console.
PLANTED=""
plant_console() { # $1 run, $2 spelling (watch.py | handsoff.py)
  case $2 in
    handsoff.py) "$PY" -c 'import time; time.sleep(90)' handsoff.py watch --run "$1" & ;;
    *)           "$PY" -c 'import time; time.sleep(90)' watch.py --run "$1" & ;;
  esac
  PLANTED=$!
  sleep 1   # the process must be in the table before any probe reads it
  kill -0 "$PLANTED" || die "the planted console for $1 died before the leg could probe it"
}
kill_console() {
  if [ -n "$PLANTED" ]; then kill "$PLANTED"; wait "$PLANTED" || :; PLANTED=""; fi
  return 0
}

printf 'handsoff.py suite · target %s\n' "$H"
printf 'fixtures %s · vault fixture %s\n\n' "$WORK" "$VAULT"

MANIFEST_BEFORE="$WORK/manifest-before.txt"
mk manifest "$SKILL_DIR" "$HOOKS_DIR" > "$MANIFEST_BEFORE"

# ------------------------------------------------------------------------- run-open --------
HO="$WORK/handoffs/open-handoff.md"; mk handoff "$HO" >/dev/null
REC="$STORE/spawn-records/ropen.jsonl"; rm -f "$REC"
run run-open --run ropen --session sid-open --head "fixture head" --regime multi \
    --regime-src owner --handoff "$HO" --detail "opening leg" --pid 4242 --envelope-usd 200
need_rc 0
need_out "pid 4242 (arg)"
need_eq "$(mk field "$REC" run-open pid_src)" "arg" "pid_src"
need_eq "$(mk field "$REC" run-open pid)" "4242" "pid"
need_eq "$(mk lines "$REC")" "1" "record lines"
verdict "run-open: --pid N recorded with pid_src arg"

REC2="$STORE/spawn-records/ropen2.jsonl"; rm -f "$REC2"
RUNENV="PATH=$WORK/psclaude:$PATH"
run run-open --run ropen2 --session sid-open2 --head "fixture head" --regime single \
    --regime-src head --handoff "$HO" --detail "parent walk"
need_rc 0
need_out "(parent-walk)"
need_eq "$(mk field "$REC2" run-open pid_src)" "parent-walk" "pid_src"
case $(mk field "$REC2" run-open pid) in
  ''|*[!0-9]*) why="$why; the parent-walk pid is not a number" ;;
esac
verdict "run-open: the parent walk finds the harness ancestor (pid_src parent-walk)"

REC3="$STORE/spawn-records/ropen3.jsonl"; rm -f "$REC3"
RUNENV="PATH=$WORK/psnone:$PATH"
run run-open --run ropen3 --session sid-open3 --head "fixture head" --regime multi \
    --regime-src owner --handoff "$HO" --detail "no ancestor"
need_rc 0
need_out "pid none (none)"
need_eq "$(mk field "$REC3" run-open pid_src)" "none" "pid_src"
need_eq "$(mk field "$REC3" run-open pid)" "<no key pid>" "pid absent"
verdict "run-open: no harness ancestor gives pid_src none and no pid key"

run run-open --run ropen --session sid-again --head "fixture head" --regime multi \
    --regime-src owner --handoff "$HO" --detail "a second opening"
need_rc 2
need_out "already has a run-open"
need_lines
need_eq "$(mk lines "$REC")" "1" "record lines after the refusal"
verdict "run-open: a second run-open is refused (exit 2, one line, nothing appended)"

REC4="$STORE/spawn-records/ropen4.jsonl"; rm -f "$REC4"
run run-open --run ropen4 --session sid-open4 --head "h" --regime multi --regime-src owner \
    --handoff "$WORK/handoffs/not-there.md" --detail "missing document"
need_rc 2
need_out "hand-off document not found"
need_lines
need_nofile "$REC4"
verdict "run-open: a missing hand-off document is refused (exit 2, no record written)"

REC5="$STORE/spawn-records/ropen5.jsonl"; rm -f "$REC5"
run run-open --run ropen5 --session sid-open5 --head "h" --regime multi --regime-src owner \
    --handoff "$HO" --detail "dry run" --dry-run
need_rc 0
need_out "dry run"
need_nofile "$REC5"
verdict "run-open: --dry-run prints the event and writes no record"

# ------------------------------------------------------------------------ run-resume -------
fixture rres 200
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rres --session sid-second --head "successor head" --detail "resumed" \
    --pid 5150
need_rc 0
need_out "session sid-seco (arg)"
need_eq "$(mk field "$REC" run-resume session)" "sid-second" "session"
need_eq "$(mk field "$REC" run-resume pid)" "5150" "pid"
verdict "run-resume: an explicit session and --pid are recorded"

fixture rres2 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"800,000 tokens (80 %)"}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-fromstarter","pid":9001,"budget":3.5}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rres2 --session auto --head "successor head" --detail "auto session"
need_rc 0
need_out "(head-successor)"
need_eq "$(mk field "$REC" run-resume session)" "sid-fromstarter" "session from the starter"
verdict "run-resume: --session auto takes the last head-successor's session id"

fixture rres3 200
run run-resume --run rres3 --session auto --head "h" --detail "no successor to read"
need_rc 2
need_out "needs a head-successor event"
need_lines
need_eq "$(mk count "$REC" run-resume)" "0" "run-resume events"
verdict "run-resume: --session auto without a head-successor is refused (exit 2)"

# -------------------------------------------------------------------------- boundary -------
fixture rbnd 200
mk waste "$REC" rbnd "$WORK/handoffs/no-such-report.md" >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd --from 2 --to 3 --disposition "phase 2 closed" \
    --waste "real \$0 · arguable \$0.3 · structural \$1.5" --next "phase 3" \
    --meter-line "$METER" --shipped "the suite" --waits "nothing" --saving "n/a"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary idle_min)" "9.5" "idle_min"
need_eq "$(mk field "$REC" phase-boundary denials)" "3" "denials"
need_eq "$(mk field "$REC" phase-boundary over_cap_reports)" "1" "over_cap_reports"
need_eq "$(mk field "$REC" phase-boundary respawn_cost_usd)" "5.0" "respawn_cost_usd"
need_eq "$(mk field "$REC" phase-boundary rewrites)" "3" "rewrites"
need_out "idle 9.5 min · denials 3 · over-cap 1 · re-spawn \$5.00 · rewrites 3"
need_out "1 report(s) not word-counted"
verdict "boundary: the five waste fields come from the planted close-outs"

need_eq "$(mk rows "$HO" "Trace")" "2" "rows in the first trace table"
need_eq "$(mk rows "$HO" "Trace archive")" "1" "rows in the decoy table"
case $(mk row "$HO" "Trace" -1) in
  *"2 → 3"*"phase 2 closed"*) : ;;
  *) why="$why; the new trace row is not the last row of the first table" ;;
esac
verdict "boundary: the trace row lands in the FIRST trace table, the decoy untouched"

need_eq "$(mk bullet "$HO" "Warnings raised and handling")" \
        "see \`## Findings ledger\` (2 lines; a wrong figure on purpose, so a refresh is observable)." \
        "warnings bullet"
case $(mk bullet "$HO" "Spend against the envelope") in
  *"session \$19.62"*"envelope \$200.0"*) : ;;
  *) why="$why; the spend bullet does not carry the billed line and the envelope" ;;
esac
need_eq "$(mk bullet "$HO" "What shipped")" "the suite" "shipped bullet"
verdict "boundary: the morning report's figures are refreshed from the meter and the ledger"

printf 'a checkpoint change %s\n' "$N" > "$VAULT/notes.txt"
RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd --from 3 --to 4 --disposition "checkpoint" --waste "none" \
    --next "phase 4" --meter-line "$METER" --commit "fixture: a checkpoint commit"
need_rc 0
SHA=$(mk field "$REC" phase-boundary commit)
case $SHA in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
  *) why="$why; the commit field is '$SHA', not a short sha" ;;
esac
IDENTS=$(git -C "$VAULT" log -1 --format='%an|%ae|%cn|%ce')
need_eq "$IDENTS" "Fixture Owner|owner@example.invalid|Fixture Owner|owner@example.invalid" \
        "author and committer"
if git -C "$VAULT" log -1 --format='%B' | grep -q -E 'Co-Authored|Generated'; then
  why="$why; the commit body carries an attribution line"
fi
verdict "boundary --commit: a real commit, author equal to committer, no attribution"

RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd --from 4 --to 5 --disposition "nothing changed" --waste "none" \
    --next "phase 5" --meter-line "$METER" --commit "fixture: nothing to commit"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary commit)" "none (nothing to commit)" "commit field"
need_out "commit none (nothing to commit)"
verdict "boundary --commit: a clean tree gives 'none (nothing to commit)'"

printf 'another change %s\n' "$N" > "$VAULT/notes.txt"
BEFORE_COMMITS=$(git -C "$VAULT" rev-list --count HEAD)
RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd --from 5 --to 6 --disposition "attributed message" --waste "none" \
    --next "phase 6" --meter-line "$METER" \
    --commit "fixture: a message with Co-Authored-By in it"
need_rc 0
case $(mk field "$REC" phase-boundary commit) in
  failed*Co-Authored*) : ;;
  *) why="$why; the attributed message was not refused" ;;
esac
need_eq "$(git -C "$VAULT" rev-list --count HEAD)" "$BEFORE_COMMITS" "commit count"
verdict "boundary --commit: a message carrying an attribution line is refused (failed <reason>)"

RUNENV="PATH=$WORK/psnone:$PATH GIT_COMMITTER_NAME=Someone GIT_COMMITTER_EMAIL=someone@example.invalid"
run boundary --run rbnd --from 6 --to 7 --disposition "split identity" --waste "none" \
    --next "phase 7" --meter-line "$METER" --commit "fixture: split identity"
need_rc 0
case $(mk field "$REC" phase-boundary commit) in
  failed*"differs from committer ident"*) : ;;
  *) why="$why; a committer differing from the author was not refused" ;;
esac
need_eq "$(git -C "$VAULT" rev-list --count HEAD)" "$BEFORE_COMMITS" "commit count"
verdict "boundary --commit: author unequal to committer is refused, nothing committed"

fixture rbnd2 200 "trace,decoy"
RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd2 --from 1 --to 2 --disposition "no trace table" --waste "none" \
    --next "next" --meter-line "$METER"
need_rc 3
need_out "NOT refreshed"
need_out "no table under a '## Trace' heading"
need_eq "$(mk count "$REC" phase-boundary)" "1" "phase-boundary events"
verdict "boundary: a hand-off without a trace table exits 3 with the event still written"

fixture rbnd3 200
SUM_BEFORE=$(mk manifest "$WORK/handoffs" | grep rbnd3)
RUNENV="PATH=$WORK/psnone:$PATH"
run boundary --run rbnd3 --from 1 --to 2 --disposition "dry" --waste "none" --next "n" \
    --meter-line "$METER" --dry-run
need_rc 0
need_out "boundary: dry run"
need_eq "$(mk count "$REC" phase-boundary)" "0" "phase-boundary events"
need_eq "$(mk manifest "$WORK/handoffs" | grep rbnd3)" "$SUM_BEFORE" "hand-off checksum"
verdict "boundary --dry-run: no event, no hand-off change"

# ---------------------------------------------------------------------------- ledger -------
fixture rled 200
run ledger --run rled --phase 2 --what "a planted finding" \
    --evidence "the suite's own fixture" --routing "no action"
need_rc 0
need_out "row 3 appended"
need_eq "$(mk rows "$HO" "Findings ledger")" "3" "ledger rows"
case $(mk row "$HO" "Findings ledger" -1) in
  *"a planted finding"*"no action"*) : ;;
  *) why="$why; the ledger row is not the last row" ;;
esac
need_eq "$(mk field "$REC" observation what)" "a planted finding" "observation"
verdict "ledger: the row is appended and an observation recorded"

fixture rled2 200 ledger
run ledger --run rled2 --phase 2 --what "no table to take it" --evidence "e" --routing "r"
need_rc 2
need_out "no table under a '## Findings ledger' heading"
need_lines
need_eq "$(mk count "$REC" observation)" "0" "observation events"
verdict "ledger: a hand-off without the ledger table is refused (exit 2)"

fixture rled3 200
SUM_BEFORE=$(mk manifest "$WORK/handoffs" | grep rled3)
run ledger --run rled3 --phase 2 --what "dry" --evidence "e" --routing "r" --dry-run
need_rc 0
need_out "ledger: dry run"
need_eq "$(mk rows "$HO" "Findings ledger")" "2" "ledger rows"
need_eq "$(mk manifest "$WORK/handoffs" | grep rled3)" "$SUM_BEFORE" "hand-off checksum"
verdict "ledger --dry-run: no row, no observation, no file change"

# ------------------------------------------------- ledger --observation and the plain shape --
# The plain-lane-run shape: a record lane.py opened, with lane events and no run-open. The legs
# above are the control throughout — the same commands on a record that HAS a run-open.
plain_fixture pled
LINES_BEFORE=$(mk lines "$REC")
HO_SUM_BEFORE=$(mk manifest "$WORK/handoffs")
run ledger --run pled --observation "the head's peer name for this run"
need_rc 0
need_out "observation recorded"
need_out "plain lane run (no run-open)"
need_out "no hand-off row"
need_eq "$(mk count "$REC" observation)" "1" "observation events"
need_eq "$(mk field "$REC" observation what)" "the head's peer name for this run" "what"
need_eq "$(mk field "$REC" observation phase)" "" "phase (empty without --phase)"
need_eq "$(mk lines "$REC")" "$((LINES_BEFORE + 1))" "record lines"
need_eq "$(mk manifest "$WORK/handoffs")" "$HO_SUM_BEFORE" "the hand-off directory's checksums"
verdict "ledger --observation: one observation on a record with no run-open, phase empty, no hand-off row, exit 0"

run ledger --run pled --observation "an observation with a phase" --phase 3
need_rc 0
need_eq "$(mk field "$REC" observation phase)" "3" "phase (given)"
need_eq "$(mk count "$REC" observation)" "2" "observation events"
verdict "ledger --observation --phase: the phase is carried when it is given"

LINES_BEFORE=$(mk lines "$REC")
run ledger --run pled --observation "a dry observation" --dry-run
need_rc 0
need_out "ledger --observation: dry run"
need_out "plain lane run (no run-open)"
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines (dry run appends nothing)"
need_eq "$(mk count "$REC" observation)" "2" "observation events after the dry run"
verdict "ledger --observation --dry-run: the event is printed and nothing is appended"

LINES_BEFORE=$(mk lines "$REC")
run ledger --run pled --phase 2 --what "a finding with nowhere to go" --evidence "e" --routing "r"
need_rc 2
need_out "no run-open event"
need_out "--observation"
need_lines
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines (nothing appended)"
verdict "ledger (the row form) on a plain record: refused as before, exit 2, and the message names --observation as the form that works there"

run ledger --run pled --phase 2 --what "no evidence given"
need_rc 2
need_out "--evidence"
need_out "--observation"
verdict "ledger: a partial row form names the flags it lacks and the observation form (exit 2)"

# the clean control: the same --observation on a record that HAS a run-open appends the
# observation and NO ledger row (the head's aside that is not a finding)
fixture rledobs 200
ROWS_BEFORE=$(mk rows "$HO" "Findings ledger")
run ledger --run rledobs --observation "an aside that is not a finding"
need_rc 0
need_out "run-open present"
need_eq "$(mk count "$REC" observation)" "1" "observation events"
need_eq "$(mk rows "$HO" "Findings ledger")" "$ROWS_BEFORE" "ledger rows (unchanged)"
verdict "ledger --observation on a run-open record: the observation alone, the findings ledger untouched (the control for the plain leg)"


# ------------------------------------------------------------------------------ gate -------
fixture rgate 200
SID=sid-rgate
mk transcript "$SID" 100000 >/dev/null
run gate --run rgate --to "item one"
need_rc 0
need_out "band 0 · armed no"
need_out "allow"
need_eq "$(mk field "$REC" gate decision)" "allow" "decision"
need_eq "$(mk field "$REC" gate metered)" "true" "metered"
verdict "gate: unarmed below the first edge allows (band 0)"

mk transcript "$SID" 850000 >/dev/null
run gate --run rgate --to "item two"
need_rc 0
need_out "band 80"
need_out "warn: at or above the second edge"
need_eq "$(mk field "$REC" gate decision)" "allow" "decision"
verdict "gate: unarmed at 85 % warns and allows (soft band, D2)"

RUNENV="AIMYTH_HANDSOFF=1"
run gate --run rgate --to "item three"
need_rc 4
need_out "REFUSED (stop-condition band)"
need_eq "$(mk field "$REC" stop-condition which)" "band" "stop-condition"
need_eq "$(mk field "$REC" gate decision)" "refuse" "decision"
verdict "gate: armed above the second edge exits 4 with stop-condition band"

mk transcript "$SID" 800000 >/dev/null
touch "$STATE/armed-$SID"
run gate --run rgate --to "item four"
need_rc 4
need_out "armed marker"
need_out "band 80"
verdict "gate: armed by the marker file, exactly at the edge, exits 4 (lower edge inclusive)"

mk transcript "$SID" 100000 >/dev/null
run gate --run rgate --to "item five"
need_rc 0
need_out "allow"
need_absent "REFUSED"
verdict "gate: armed below the edge allows"

rm -f "$STATE/armed-$SID"
mk untranscript "$SID" >/dev/null
run gate --run rgate --to "item six"
need_rc 0
need_out "gate: unmetered"
need_out "first miss"
need_eq "$(mk field "$REC" gate metered)" "false" "metered"
need_eq "$(mk field "$REC" observation what)" "gate unmetered" "observation"
verdict "gate: the first unmetered gate allows with an observation (N1)"

RUNENV="AIMYTH_HANDSOFF=1"
run gate --run rgate --to "item seven"
need_rc 7
need_out "second consecutive"
need_out "REFUSED"
need_eq "$(mk field "$REC" stop-condition which)" "unmetered" "stop-condition"
verdict "gate: the second consecutive unmetered gate, armed, exits 7 (never 4)"

run gate --run rgate --to "item eight"
need_rc 0
need_out "second consecutive"
need_out "allowed"
need_out "soft: fix the metering"
verdict "gate: the second consecutive unmetered gate, unarmed, warns and allows (D2)"

RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rgate --session "$SID" --head "successor" --detail "scope reset"
need_rc 0
RUNENV="AIMYTH_HANDSOFF=1"
run gate --run rgate --to "item nine"
need_rc 0
need_out "first miss"
need_absent "second consecutive"
verdict "gate: the unmetered count is scoped to the last session event (a run-resume resets it)"

# ------------------------------------------------------------------ gate: the envelope -------
# Register entry 2026-09-07: an envelope the pre-flight states is measured at every gate, or its
# stop condition cannot fire. Fixture envelope $100; the billed line's session total is $19.62.
fixture renv 100
SID=sid-renv
mk transcript "$SID" 100000 >/dev/null
run gate --run renv --to "item one" --meter-line "$METER"
need_rc 0
need_out 'envelope: $19.62 of $100.00, remainder $80.38'
need_eq "$(mk field "$REC" gate decision)" "allow" "decision"
verdict "gate: the line carries spent, envelope and remainder (100.00 - 19.62 = 80.38) and allows"

# Two earlier heads spent $50.00 and $40.00 (head-exit spent_usd); with this session's $19.62
# the remainder is 100 - 90 - 19.62 = -9.62, at or below zero: the gate refuses with exit 5,
# unarmed, and the record gains the gate event and the stop-condition, nothing else.
mk append "$REC" '{"event":"head-exit","band":80,"spent_usd":50.0}' >/dev/null
mk append "$REC" '{"event":"head-exit","band":80,"spent_usd":40.0}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run renv --session "$SID" --head "successor" --detail "after two exits"
need_rc 0
LINES_BEFORE=$(mk lines "$REC")
run gate --run renv --to "item two" --meter-line "$METER"
need_rc 5
need_out 'envelope: $109.62 of $100.00, remainder -$9.62'
need_out "REFUSED (stop-condition envelope"
need_eq "$(mk field "$REC" stop-condition which)" "envelope" "stop-condition which"
need_eq "$(mk field "$REC" stop-condition lane)" "head" "stop-condition lane"
need_eq "$(mk field "$REC" gate decision)" "refuse" "decision"
need_eq "$(mk lines "$REC")" "$((LINES_BEFORE + 2))" "record lines (the gate and the stop-condition)"
verdict "gate: a spent envelope (remainder at or below zero) records stop-condition envelope, lane head, and exits 5"

fixture rnoenv none
SID=sid-rnoenv
mk transcript "$SID" 100000 >/dev/null
run gate --run rnoenv --to "item one" --meter-line "$METER"
need_rc 0
need_out "envelope: none"
need_absent "REFUSED"
need_eq "$(mk lines "$REC")" "2" "record lines (run-open and the gate)"
verdict "gate: a record whose run-open carries no envelope_usd prints envelope: none and allows"

fixture runm 100
SID=sid-runm
mk transcript "$SID" 100000 >/dev/null
run gate --run runm --to "item one" --meter-line "failed: the fixture meter gave nothing"
need_rc 0
need_out "envelope: unmeasured (the meter gave no session total)"
need_absent "REFUSED"
need_eq "$(mk lines "$REC")" "2" "record lines (run-open and the gate)"
verdict "gate: an envelope the meter cannot measure prints unmeasured and allows, never a refusal"

# --------------------------------------------------------------------------- handoff -------
fixture rho 200
run handoff --run rho --inflight "- lane B2b: the suite, running."
need_rc 0
need_out "inflight rewritten"
case $(mk section "$HO" "In flight") in
  *"lane B2b: the suite, running."*) : ;;
  *) why="$why; the in-flight section was not rewritten" ;;
esac
verdict "handoff --inflight: the in-flight section is rewritten"

run handoff --run rho --set "shipped=the suite and its controls" \
    --set "waits=one confirmation"
need_rc 0
need_eq "$(mk bullet "$HO" "What shipped")" "the suite and its controls" "shipped bullet"
need_eq "$(mk bullet "$HO" "Waits for you")" "one confirmation" "waits bullet"
verdict "handoff --set: named morning-report bullets are rewritten"

SUM_BEFORE=$(mk manifest "$WORK/handoffs" | grep rho)
run handoff --run rho --set "ledger=a row by the back door"
need_rc 2
need_out "append-only"
need_lines
need_eq "$(mk manifest "$WORK/handoffs" | grep rho)" "$SUM_BEFORE" "hand-off checksum"
verdict "handoff --set ledger: refused as append-only (exit 2, file untouched)"

run handoff --run rho --set "trace=a row by the back door"
need_rc 2
need_out "append-only"
need_lines
verdict "handoff --set trace: refused as append-only (exit 2)"

run handoff --run rho --set "nonesuch=x"
need_rc 2
need_out "unknown key"
need_lines
verdict "handoff --set: an unknown key is refused (exit 2)"

printf -- '- Next: item 4 (gate: 4)\n- Needs: wiki/a.md:1-9\n- Decided: D1 because x\n' > "$WORK/pack-rho.md"
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rho --final --band 80 --meter-line "$METER" --inflight-file "$WORK/pack-rho.md"
need_rc 0
need_out "head-exit recorded (band 80"
need_eq "$(mk field "$REC" head-exit band)" "80" "head-exit band"
REALHO=$("$PY" -c 'import os, sys; sys.stdout.write(os.path.realpath(sys.argv[1]))' "$HO")
need_eq "$(mk field "$REC" head-exit handoff)" "$REALHO" "head-exit hand-off path"
verdict "handoff --final --band: a head-exit event with the band and the hand-off path"

# ------------------------------------------------------------------------- successor -------
fixture rsuc 200
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rsuc --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "budget \$180.38"
need_out "minus session \$19.62"
need_eq "$(mk count "$REC" head-exit)" "0" "head-exit events"
need_eq "$(mk lines "$REC")" "1" "record lines"
verdict "successor --dry-run: the budget is the envelope minus the session total, nothing written"

fixture rsuc2 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"800,000 tokens (80 %)"}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-running","pid":9002,"budget":3.5}' >/dev/null
LINES_BEFORE=$(mk lines "$REC")
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rsuc2 --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 2
need_out "head-successor"
need_lines
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines"
verdict "successor: refused when a head-successor already follows the last head-exit (exit 2)"

fixture rsuc3 10
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rsuc3 --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 2
need_out "the envelope is spent"
need_lines
verdict "successor: a spent envelope is refused rather than a negative budget (exit 2)"

# --------------------------------------------------------------------------- _starter ------
# The pid path: a real process the starter must outlive. The suite reaps it as soon as it
# exits, so pid_alive() sees the process gone rather than a zombie of this shell.
fixture rst 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"800,000 tokens (80 %)"}' >/dev/null
sleep 2 &
PRED=$!
(
  RCF=0
  env STUB_MODE=complete STUB_N=1 "$PY" -B "$H" _starter --run rst --handoff "$HO" --budget 3.50 \
        --out "$WORK/starter/rst-head-1.out" --wait-s 20 --harness-bin "$WORK/bin/stubhead" \
        --meter-line "$METER" --predecessor-pid "$PRED" >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait "$PRED"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_out "head-successor pid"
need_eq "$(mk field "$REC" head-successor budget)" "1.0" "the last head-successor is the stub's own hand-over"
need_file "$WORK/starter/rst-head-1.out"
if ! grep -q "Resume the fixture run" "$WORK/stub-rst.stdin.1"; then
  why="$why; the resume prompt did not reach the head on standard input"
fi
need_eq "$(cat "$WORK/stub-rst.env")" "rst" "AIMYTH_HANDSOFF_RUN seen by the head"
need_eq "$(mk field "$REC" supervise mode)" "launched" "supervise event"
verdict "_starter: waits for the predecessor pid, starts the head on stdin under AIMYTH_HANDSOFF_RUN, supervises it"

# The chain the record must show: head 1 completed without a hand-off → the supervisor's own
# head-exit (band unmetered: no transcript, exit_class completed, pack false, spent from the
# meter line) → one successor at the remainder → head 2 hands over → handed-over, ended.
need_eq "$(mk count "$REC" head-successor)" "3" "head-successors (starter, supervisor, the stub's own)"
need_eq "$(cat "$WORK/stub-rst.count")" "2" "stub invocations"
need_eq "$(mk count "$REC" successor-aborted)" "0" "successor-aborted events"
case $(mk field "$REC" observation note) in
  handed-over*) : ;;
  *) why="$why; the supervisor did not end handed-over: $(mk field "$REC" observation note)" ;;
esac
"$PY" - "$REC" <<'CHAIN' > "$WORK/chain.txt"
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ex = [e for e in evs if e.get("event") == "head-exit" and e.get("exit_class")]
print("%s %s %s %s" % (ex[0]["band"], ex[0]["exit_class"], ex[0]["pack"], ex[0].get("spent_usd")) if ex else "none")
CHAIN
need_eq "$(cat "$WORK/chain.txt")" "unmetered completed False 19.62" "the supervisor's head-exit"
verdict "supervisor: a completed head with no hand-off gets one successor, then the hand-over ends the loop"

fixture rst2 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"800,000 tokens (80 %)"}' >/dev/null
rm -f "$WORK/harness2-stdin.txt"
TR=$(mk transcript sid-rst2 500000)
touch "$TR"
# --wait-s 2 against the 120 s silence proxy: the transcript cannot be quiet long enough, so
# the bound must expire and the starter must abort rather than start a second head.
run _starter --run rst2 --handoff "$HO" --budget 1.00 --out "$WORK/starter/rst2-head-1.out" \
    --wait-s 2 --harness-bin "$WORK/bin/harness2" --transcript "$TR"
need_rc 1
need_out "aborted"
need_eq "$(mk field "$REC" successor-aborted reason)" "timeout" "abort reason"
need_nofile "$WORK/harness2-stdin.txt"
verdict "_starter: the silence proxy times out and aborts (successor-aborted timeout)"

fixture rst3 200
mk append "$REC" '{"event":"head-exit","band":"unmetered","context":"unmetered (no transcript)"}' >/dev/null
mk append "$REC" '{"event":"observation","phase":"2","what":"a restart happened","note":"n"}' >/dev/null
mk append "$REC" '{"event":"head-exit","band":"unmetered","context":"unmetered (no transcript)"}' >/dev/null
rm -f "$WORK/harness2-stdin.txt"
run _starter --run rst3 --handoff "$HO" --budget 1.00 --out "$WORK/starter/rst3-head-1.out" \
    --wait-s 5 --harness-bin "$WORK/bin/harness2" --transcript ""
need_rc 1
need_eq "$(mk field "$REC" successor-aborted reason)" "unmetered-loop" "abort reason"
need_nofile "$WORK/harness2-stdin.txt"
verdict "_starter: two unmetered head-exits abort the restart (unmetered-loop, at most one)"

fixture rst4 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"800,000 tokens (80 %)"}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-already","pid":9003,"budget":2.0}' >/dev/null
rm -f "$WORK/harness2-stdin.txt"
run _starter --run rst4 --handoff "$HO" --budget 1.00 --out "$WORK/starter/rst4-head-1.out" \
    --wait-s 5 --harness-bin "$WORK/bin/harness2" --transcript ""
need_rc 1
need_eq "$(mk field "$REC" successor-aborted reason)" "duplicate" "abort reason"
need_nofile "$WORK/harness2-stdin.txt"
verdict "_starter: a head-successor already following the head-exit aborts (duplicate)"

# ------------------------------------------------------------------------- wait-reset ------
fixture rwait 200
# +5 s against a 2 s block bound: the call must give the window back, not the reset.
T0=$(date +%s)
run wait-reset --run rwait --reset-at "+5s" --max-block-s 2 --lane B9
T1=$(date +%s)
need_rc 8
need_out "still-running"
need_eq "$(mk field "$REC" stop-condition which)" "limit" "stop-condition"
if [ "$((T1 - T0))" -gt 4 ]; then why="$why; the call blocked $((T1 - T0)) s past its 2 s bound"; fi
verdict "wait-reset: --reset-at +5s under a 2 s block bound returns still-running (exit 8)"

fixture rwait2 200
run wait-reset --run rwait2 --stop-text "You've hit your session limit · resets 3:50am (Europe/London)" \
    --dry-run
need_rc 0
need_out "stop text 'resets 3:50am'"
need_out "wait-reset: dry run"
need_eq "$(mk count "$REC" stop-condition)" "0" "stop-condition events"
verdict "wait-reset: the am/pm reset time is parsed out of the stop text"

fixture rwait3 200
run wait-reset --run rwait3 --stop-text "limit reached; the window resets at 2030-01-02T03:04:05+0100" \
    --dry-run
need_rc 0
need_out "stop text ISO 2030-01-02T03:04:05+0100"
verdict "wait-reset: an ISO reset time in the stop text is parsed"

# The probe is opt-in and off by default (owner ruling 2026-09-06): with no reset time to sleep
# to and no --probe, the wait is not entered at all — the stop condition is recorded and the
# hand-off is the recovery. The planted input is a stop text naming no time.
fixture rwait4 200
run wait-reset --run rwait4 --stop-text "the window is closed, and no time is given"
need_rc 7
need_out "no reset time could be parsed and --probe was not passed"
need_out "the hand-off is the recovery"
need_absent "PROBE FAILED"
need_eq "$(mk count "$REC" stop-condition)" "1" "stop-condition events"
need_eq "$(mk field "$REC" stop-condition which)" "limit-unparsed" "which"
need_eq "$(mk field "$REC" stop-condition note)" "the window is closed, and no time is given" "the stop text"
verdict "wait-reset: no reset time and no --probe records stop-condition limit-unparsed and ends with the hand-off as the recovery (exit 7)"

fixture rwait5 200
run wait-reset --run rwait5 --probe --dry-run
need_rc 0
need_out "probe every 900 s under the same login"
need_absent "PROBE FAILED"
verdict "wait-reset: --probe without --config-dir is accepted under the single account (D28)"

# The help text says the probe is opt-in, and the phrase the owner ruling forbids is absent.
run wait-reset --help
need_rc 0
need_out "OFF by default"
need_absent "auto-probe"
OPTIN=$(grep -c 'opt in to' "$WORK/both")
[ "$OPTIN" -ge 1 ] || why="$why; the help text never says the probe is opted in to ($OPTIN)"
verdict "wait-reset --help: the probe is named as opt-in and off by default (control: the count of 'opt in to' is $OPTIN)"

# ------------------------------------------------------------------------------ close ------
fixture rclose 200
mk append "$REC" '{"event":"lane-open","lane":"L1"}' >/dev/null
mk append "$REC" '{"event":"lane-open","lane":"L2"}' >/dev/null
mk append "$REC" '{"event":"decision","phase":"2","what":"one","grant":"owner"}' >/dev/null
mk append "$REC" '{"event":"decision","phase":"2","what":"two","grant":"owner"}' >/dev/null
mk append "$REC" '{"event":"gate","item":"a","context":100000,"percent":10,"band":0,"armed":false,"decision":"allow","metered":true}' >/dev/null
mk append "$REC" '{"event":"gate","item":"b","context":300000,"percent":30,"band":0,"armed":false,"decision":"allow","metered":true}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run close --run rclose --meter-line "$METER" --items "9 of 9" --register "one entry" \
    --log "one line" --lint "clean" --parity "not yet"
need_rc 0
need_out "lanes 2 · decisions 2 · gates 2"
need_eq "$(mk field "$REC" run-close lanes)" "2" "lanes"
need_eq "$(mk field "$REC" run-close decisions_on_owner_behalf)" "2" "decisions"
need_eq "$(mk field "$REC" run-close reason_tally)" "(a)×1 (b)×0 (c)×0 (d)×0, none×0" "tally"
case $(mk field "$REC" run-close head_context_per_item) in
  *'"delta": 200000'*) : ;;
  *) why="$why; the per-item context deltas are missing" ;;
esac
case $(mk field "$REC" run-close trace) in
  "1 rows under '## Trace'"*) : ;;
  *) why="$why; the trace count is not the first table's row count" ;;
esac
need_eq "$(mk bullet "$HO" "Spend against the envelope")" \
        "$METER · envelope \$200.0" "spend bullet"
need_file "$STORE/spawn-records/rclose-heartbeat.stop"
verdict "close: run-close carries lanes, decisions, the tally, per-item context, the trace; the heartbeat stop marker is written"

# ---------------------------------------------------------- close on the plain-lane-run shape
plain_fixture pclose
COMMITS_BEFORE=$(git -C "$VAULT" rev-list --count HEAD)
run close --run pclose --items "not applicable"
need_rc 0
need_out "plain lane run (no run-open)"
need_out "lanes 3 (completed 1 · error 1 · open 1)"
need_out "spend \$3.75"
need_out "no hand-off row, no commit, no push"
need_eq "$(mk field "$REC" run-close shape)" "plain-lane-run" "the shape field"
need_eq "$(mk field "$REC" run-close lanes)" "3" "lanes"
need_eq "$(mk field "$REC" run-close lanes_by_exit)" '{"completed": 1, "error": 1, "open": 1}' "lanes by exit class"
need_eq "$(mk field "$REC" run-close spend_usd)" "3.75" "spend summed from the lane-closed costs"
need_eq "$(mk field "$REC" run-close spend_src)" "sum of 2 lane-closed total_cost_usd" "the spend's source"
need_eq "$(mk field "$REC" run-close trace)" "<no key trace>" "no trace field (there is no hand-off)"
need_eq "$(mk field "$REC" run-close commit)" "<no key commit>" "no commit field"
need_eq "$(git -C "$VAULT" rev-list --count HEAD)" "$COMMITS_BEFORE" "commit count"
need_nofile "$STORE/spawn-records/pclose-heartbeat.stop"
need_nofile "$STORE/spawn-records/pclose-supervisor.stop"
verdict "close on a plain record: run-close carries shape plain-lane-run, the lanes by exit class and the lane-summed spend; no hand-off row, no commit, no meter, no markers (exit 0)"

# the clean control: a run-open record still closes as today, and its run-close carries NO shape
need_eq "$(mk field "$STORE/spawn-records/rclose.jsonl" run-close shape)" "<no key shape>" "the hands-off close carries no shape field"
need_eq "$(mk field "$STORE/spawn-records/rclose.jsonl" run-close lanes)" "2" "the hands-off close's lanes"
verdict "close: the hands-off close of the rclose leg is unchanged and carries no shape field, so the two shapes are told apart by the record"

plain_fixture pclose2
LINES_BEFORE=$(mk lines "$REC")
COMMITS_BEFORE=$(git -C "$VAULT" rev-list --count HEAD)
run close --run pclose2 --commit "fixture: a commit a plain run may not make"
need_rc 2
need_out "never commits and never pushes"
need_lines
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines (nothing written)"
need_eq "$(mk count "$REC" run-close)" "0" "run-close events"
need_eq "$(git -C "$VAULT" rev-list --count HEAD)" "$COMMITS_BEFORE" "commit count"
run close --run pclose2 --push
need_rc 2
need_out "never commits and never pushes"
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines after --push"
need_eq "$(mk count "$REC" run-close)" "0" "run-close events after --push"
verdict "close --commit and --push on a plain record: refused with the reason (exit 2), nothing written and nothing committed"

plain_fixture pclose3
LINES_BEFORE=$(mk lines "$REC")
run close --run pclose3 --dry-run
need_rc 0
need_out "close: dry run · plain lane run"
need_out '"shape": "plain-lane-run"'
need_eq "$(mk lines "$REC")" "$LINES_BEFORE" "record lines (dry run writes nothing)"
verdict "close --dry-run on a plain record: the run-close it would write is printed and the record is untouched"

# ------------------------------------------------------------- grants file and pointer ----
mkdir -p "$WORK/real-grant"
ln -s "$WORK/real-grant" "$WORK/link-grant"
HO="$WORK/handoffs/rgrant-handoff.md"; mk handoff "$HO" >/dev/null
REC="$STORE/spawn-records/rgrant.jsonl"; rm -f "$REC"
GF="$REALSTORE/spawn-records/rgrant-grants.json"
run run-open --run rgrant --session sid-rgrant --head "h" --regime multi --regime-src owner \
    --handoff "$HO" --detail "grants" --pid 1 --envelope-usd 100 --grant "$WORK/link-grant" \
    --write "$WORK/link-grant/out"
need_rc 0
need_file "$GF"
need_eq "$(mk field "$REC" run-open grants_file)" "$GF" "grants_file on the event"
need_eq "$(cat "$STATE/run-sid-rgrant")" "rgrant" "the run-<sid> pointer"
REAL_GRANT=$("$PY" -c 'import os, sys; sys.stdout.write(os.path.realpath(sys.argv[1]))' "$WORK/link-grant")
"$PY" - "$GF" "$WORK/link-grant" "$REAL_GRANT" "$VAULT" "$STORE" "$STATE" "$PROJECTS" "$WORK/lane-home" <<'GRANTS' > "$WORK/grants-check.txt"
import json, os, sys
g = json.load(open(sys.argv[1]))
link, real, vault, store, state, projects, lane_home = sys.argv[2:9]
want = [link, real, os.path.realpath(vault), os.path.realpath(store), os.path.realpath(state),
        os.path.realpath(projects), os.path.realpath(lane_home), "/tmp"]
missing = [p for p in want if p not in g["grants"]]
wmissing = [p for p in (os.path.realpath(store), os.path.realpath(state), real + "/out", link + "/out") if p not in g["writes"]]
print("grants-missing %d writes-missing %d source %s run %s" % (len(missing), len(wmissing), g.get("source"), g.get("run")))
for p in missing + wmissing: print("missing " + p)
GRANTS
need_eq "$(head -1 "$WORK/grants-check.txt")" "grants-missing 0 writes-missing 0 source run-open run rgrant" "grants file content"
verdict "run-open: the grants file holds the given path in both spellings, the defaults (vault, store, state, projects, lane-home, /tmp), the writes; the pointer names the run"

rm -f "$GF"
run grants --run rgrant --write "$WORK/real-grant/more"
need_rc 0
need_file "$GF"
need_out "grants: $GF"
need_eq "$(mk field "$REC" grants grants_file)" "$GF" "grants event"
need_eq "$(cat "$STATE/run-sid-rgrant")" "rgrant" "the pointer after grants"
if ! grep -q "real-grant/more" "$GF"; then why="$why; the new write is not in the rewritten file"; fi
verdict "grants: a missing grants file is rewritten with the pointer (N7)"

fixture rgrant2 200
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rgrant2 --session sid-second --head "h" --detail "d" --grants-file "$WORK/custom-grants.json"
need_rc 0
need_file "$WORK/custom-grants.json"
need_eq "$(mk field "$REC" run-resume grants_file)" "$(real "$WORK/custom-grants.json")" "overridden path"
need_eq "$(cat "$STATE/run-sid-second")" "rgrant2" "the pointer for the resumed session"
if ! grep -q '"source": "run-resume"' "$WORK/custom-grants.json"; then why="$why; source is not run-resume"; fi
verdict "run-resume: --grants-file PATH overrides the path; source run-resume; the pointer is written"

fixture rkeep 200
GFK="$REALSTORE/spawn-records/rkeep-grants.json"
RUNENV="PATH=$WORK/psnone:$PATH"
run grants --run rkeep --write "$WORK/real-grant/keepme"
need_rc 0
need_file "$GFK"
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rkeep --session sid-keep --head "h" --detail "no flags"
need_rc 0
need_out "grants $GFK (kept)"
need_eq "$(mk field "$REC" run-resume grants)" "kept" "grants kept on the event"
if ! grep -q "real-grant/keepme" "$GFK"; then why="$why; the seeded write was lost"; fi
if grep -q '"source": "run-resume"' "$GFK"; then why="$why; the file was rewritten"; fi
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rkeep --session sid-keep2 --head "h" --detail "explicit write" --write "$WORK/real-grant/other"
need_rc 0
need_absent "(kept)"
if grep -q "real-grant/keepme" "$GFK"; then why="$why; an explicit --write did not replace the file"; fi
if ! grep -q "real-grant/other" "$GFK"; then why="$why; the explicit write is absent"; fi
verdict "run-resume: with no --grant or --write an existing grants file is kept (register 2026-09-06); an explicit --write rewrites it (control)"

fixture rwarn 200
mk transcript sid-rwarn 100000 >/dev/null
RUNENV="AIMYTH_HANDSOFF=1"
run gate --run rwarn --to "item"
need_rc 0
need_out "warn: armed with no grants file at $REALSTORE/spawn-records/rwarn-grants.json: the head fence is fail-open"
RUNENV="AIMYTH_HANDSOFF=1 PATH=$WORK/psnone:$PATH"
run boundary --run rwarn --from 1 --to 2 --disposition d --waste w --next n --meter-line "$METER"
need_rc 0
need_out "warn: armed with no grants file"
run grants --run rwarn
RUNENV="AIMYTH_HANDSOFF=1"
run gate --run rwarn --to "item two"
need_rc 0
need_absent "warn: armed"
verdict "gate and boundary: armed with no grants file warns (exit unchanged); the control after grants is silent"

# ---------------------------------------------------------------- the next-task pack ------
fixture rpack 200
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rpack --final --band 80 --meter-line "$METER"
need_rc 2
need_out "needs the next-task pack"
need_lines
need_eq "$(mk count "$REC" head-exit)" "0" "head-exit events"
verdict "handoff --final without the pack is refused (exit 2, nothing written)"

for MISSING in Next Needs Decided; do
  printf -- '- Next: item 4 (gate: 4)\n- Needs: wiki/a.md:1-9\n- Decided: D1 because x\n' | grep -v "$MISSING" > "$WORK/pack-$MISSING.md"
  RUNENV="PATH=$WORK/psnone:$PATH"
  run handoff --run rpack --final --band 80 --meter-line "$METER" --inflight-file "$WORK/pack-$MISSING.md"
  need_rc 2
  need_out "lacks $MISSING:"
  need_lines
done
need_eq "$(mk count "$REC" head-exit)" "0" "head-exit events after three refusals"
verdict "handoff --final: a pack lacking Next:, Needs: or Decided: is refused naming the label"

run handoff --run rpack --inflight "- Next: item 4
- Needs: wiki/a.md:1-9"
need_rc 0
need_out "warn: the in-flight pack lacks Decided:"
need_out "inflight rewritten"
verdict "handoff --inflight (not final): a missing label warns and writes"

printf -- '- Next: item 4 (gate: 4)\n- Needs: wiki/a.md:1-9\n- Decided: D1 because x\n' > "$WORK/pack-full.md"
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rpack --final --band 80 --meter-line "$METER" --inflight-file "$WORK/pack-full.md"
need_rc 0
need_eq "$(mk field "$REC" head-exit pack)" "true" "pack"
need_eq "$(mk field "$REC" head-exit spent_usd)" "19.62" "spent_usd from the meter line (N5)"
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rpack --final --band limit --meter-line "$METER" --inflight-file "$WORK/pack-full.md"
need_rc 0
need_eq "$(mk field "$REC" head-exit band)" "limit" "band limit accepted"
verdict "handoff --final: the full pack writes head-exit with pack true and spent_usd; band limit is accepted"

# ----------------------------------------------------------------- the pack-age guard -----
# The stamp handoff --inflight writes, and the guard that compares it with the record's last
# phase-boundary or head-exit. A head-exit carrying pack true is not the anchor: handoff --final
# writes the pack and that exit in one call, so the pack cannot be older than it.
fixture rage 200
mk append "$REC" '{"event":"phase-boundary","ts":"2020-01-02T03:04:05+0100","from":"1","to":"2","next":"item 5: older than the pack"}' >/dev/null
run handoff --run rage --inflight "- Next: item 5 (gate: 5)
- Needs: wiki/b.md:1-4
- Decided: D2 because y"
need_rc 0
case $(mk section "$HO" "In flight") in
  "- pack written: 20"*) : ;;
  *) why="$why; no pack-written stamp on the section: $(mk section "$HO" "In flight")" ;;
esac
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5,"pack":true}' >/dev/null
RUNENV="STUB_MODE=complete STUB_N=0"
starter --run rage --handoff "$HO" --budget 3.50 --out "$WORK/starter/rage-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "pack: fresh"
need_absent "re-derived"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations"
case $(mk section "$HO" "In flight") in
  *"item 5 (gate: 5)"*) : ;;
  *) why="$why; the fresh pack was rewritten: $(mk section "$HO" "In flight")" ;;
esac
verdict "the pack-age guard: handoff --inflight stamps the pack, and a pack newer than the last boundary is accepted unchanged by the starter"

# The planted stale case: a phase-boundary, a decision and a lane opened AFTER the pack was
# written, so the record knows more than the pack does.
fixture rage2 200
mk append "$REC" '{"event":"lane-open","lane":"B7","class":"builder","model":"opus","reason":"opened before the boundary"}' >/dev/null
run handoff --run rage2 --inflight "- Next: the stale item
- Needs: wiki/c.md:1-2
- Decided: D3 because z"
need_rc 0
mk append "$REC" '{"event":"phase-boundary","ts":"2030-01-02T03:04:05+0100","from":"2","to":"3","next":"item 9: the record knows better"}' >/dev/null
mk append "$REC" '{"event":"decision","ts":"2030-01-02T04:00:00+0100","phase":"3","what":"ship the guard","grant":"owner"}' >/dev/null
mk append "$REC" '{"event":"lane-open","ts":"2030-01-02T04:05:00+0100","lane":"B8","class":"verifier","model":"sonnet","reason":"open since the boundary"}' >/dev/null
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T04:10:00+0100","band":80,"context":"c","spent_usd":5,"pack":true}' >/dev/null
RUNENV="STUB_MODE=complete STUB_N=0"
starter --run rage2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rage2-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "pack: STALE"
need_out "re-derived from the record"
G=$(grep -c 'stale-pack' "$REC"); [ "$G" -ge 1 ] || why="$why; no stale-pack observation ($G)"
SEC=$(mk section "$HO" "In flight")
case $SEC in *"pack re-derived from the record at "*) : ;; *) why="$why; no re-derivation header: $SEC" ;; esac
case $SEC in *"item 9: the record knows better"*) : ;; *) why="$why; the boundary's next is missing" ;; esac
case $SEC in *"lane B8 open since"*) : ;; *) why="$why; the lane open since the boundary is missing" ;; esac
case $SEC in *"ship the guard"*) : ;; *) why="$why; the decision since the boundary is missing" ;; esac
case $SEC in *"the stale item"*) why="$why; the stale pack survived the re-derivation" ;; *) : ;; esac
case $SEC in *"lane B7"*) why="$why; a lane opened before the boundary is in the re-derived pack" ;; *) : ;; esac
verdict "the pack-age guard: a pack older than the last phase-boundary is STALE, and the starter re-derives the in-flight section from the record before the successor starts (observation stale-pack)"

# No boundary at all: nothing for the pack to be older than.
fixture rage3 200
run handoff --run rage3 --inflight "- Next: the first item
- Needs: wiki/d.md:1
- Decided: D4 because w"
need_rc 0
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage3 --session sid-noboundary --head "h" --detail "no boundary yet"
need_rc 0
need_absent "stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations"
verdict "the pack-age guard: a record with no phase-boundary and no head-exit leaves the pack fresh by definition (run-resume is silent)"

# The same command over a pack older than a head-exit: one warning line, nothing rewritten.
fixture rage4 200
run handoff --run rage4 --inflight "- Next: written before the exit
- Needs: wiki/e.md:2
- Decided: D5 because v"
need_rc 0
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T03:04:05+0100","band":80,"context":"c","spent_usd":5,"pack":false}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage4 --session sid-stalepack --head "h" --detail "resumed onto a stale pack"
need_rc 0
need_out "in-flight pack is stale"
need_eq "$(grep -c 'in-flight pack is stale' "$WORK/both")" "1" "warning lines"
need_eq "$(mk field "$REC" observation what)" "stale-pack" "the observation"
case $(mk section "$HO" "In flight") in
  *"written before the exit"*) : ;;
  *) why="$why; run-resume rewrote the pack, which is the starter's job" ;;
esac
verdict "run-resume: a pack older than the last head-exit warns once and records observation stale-pack, rewriting nothing (control: the no-boundary leg above is silent)"

# The derivation as a command, and its shape: header, next, open lanes, decisions.
fixture rage5 200
mk append "$REC" '{"event":"phase-boundary","ts":"2026-01-02T03:04:05+0100","from":"3","to":"4","next":"item 7: the derived next"}' >/dev/null
mk append "$REC" '{"event":"lane-open","ts":"2026-01-02T04:00:00+0100","lane":"B9","class":"builder","model":"opus","reason":"still open"}' >/dev/null
mk append "$REC" '{"event":"lane-open","ts":"2026-01-02T04:01:00+0100","lane":"B10","class":"verifier","model":"sonnet","reason":"closed again"}' >/dev/null
mk append "$REC" '{"event":"lane-closed","ts":"2026-01-02T04:02:00+0100","lane":"B10","exit_class":"completed"}' >/dev/null
mk append "$REC" '{"event":"decision","ts":"2026-01-02T04:03:00+0100","phase":"4","what":"the derived decision","grant":"owner"}' >/dev/null
run handoff --run rage5 --inflight-from-record --dry-run
need_rc 0
need_out "pack re-derived from the record at"
need_out "Next: item 7: the derived next"
need_out "Needs: lane B9 open since"
need_out "class builder"
need_out "Decided: the derived decision"
need_absent "lane B10"
need_eq "$(mk section "$HO" "In flight")" "- nothing in flight." "the dry run wrote nothing"
verdict "handoff --inflight-from-record --dry-run: the header, the boundary's next, the open lane with its spawn line and the decision are printed; the lane closed again is absent and nothing is written"

run handoff --run rage5 --inflight-from-record
need_rc 0
need_out "inflight rewritten"
case $(mk section "$HO" "In flight") in
  "- pack re-derived from the record at "*) : ;;
  *) why="$why; the written section does not open with the re-derivation header" ;;
esac
need_eq "$(mk count "$REC" observation)" "0" "observations recorded by the subcommand"
run handoff --run rage5 --inflight-from-record --inflight "a second source"
need_rc 2
need_out "two sources for one section"
need_lines
verdict "handoff --inflight-from-record: writes the derived pack and records nothing; with --inflight as well it is refused (exit 2)"

# The pack handed in as a file, and the stamp's replacement: an earlier stamp is dropped, so the
# section carries exactly one age and it is the age of this write.
fixture rage6 200
cat > "$WORK/pack6.md" <<'PACK6'
- pack written: 2020-01-02T03:04:05+0100
- Next: item 6 handed in by file
- Needs: wiki/f.md:1
- Decided: D6 because u
PACK6
run handoff --run rage6 --inflight-file "$WORK/pack6.md"
need_rc 0
SEC=$(mk section "$HO" "In flight")
case $SEC in "- pack written: 20"*) : ;; *) why="$why; the pack from the file was not stamped: $SEC" ;; esac
need_eq "$(printf '%s\n' "$SEC" | grep -c 'pack written:')" "1" "stamp lines on the section"
case $SEC in *"2020-01-02T03:04:05"*) why="$why; the file's earlier stamp survived the write" ;; *) : ;; esac
case $SEC in *"item 6 handed in by file"*) : ;; *) why="$why; the file's pack body is missing: $SEC" ;; esac
verdict "handoff --inflight-file: the pack is stamped with the time of this write, and the earlier stamp planted in the file is replaced rather than doubled"

# The head writing its own pack over a re-derived one: the guard's header carries the age, so it
# is dropped by the same rule, and one fresh stamp replaces it.
run handoff --run rage6 --inflight "- pack re-derived from the record at 2020-03-04T05:06:07+0100 (the head's pack was stale)
- Next: the head's own pack over a derived one
- Needs: wiki/g.md:2
- Decided: D7 because t"
need_rc 0
SEC=$(mk section "$HO" "In flight")
case $SEC in "- pack written: 20"*) : ;; *) why="$why; the head's own pack was not stamped: $SEC" ;; esac
need_eq "$(printf '%s\n' "$SEC" | grep -c 'pack re-derived from the record')" "0" "re-derivation headers left"
need_eq "$(printf '%s\n' "$SEC" | grep -c 'pack written:')" "1" "stamp lines on the section"
case $SEC in *"the head's own pack over a derived one"*) : ;; *) why="$why; the pack body is missing: $SEC" ;; esac
verdict "handoff --inflight over a re-derived pack: the planted 2020 re-derivation header is dropped and one fresh stamp replaces it"

# A pack written before this guard existed, or by hand: no stamp, so no age. The guard leaves it
# alone rather than re-deriving over the head's own judgement, and says which.
fixture rage7 200
run handoff --run rage7 --set "inflight=- Next: the hand-written pack
- Needs: wiki/h.md:3
- Decided: D8 because s"
need_rc 0
mk append "$REC" '{"event":"phase-boundary","ts":"2030-01-02T03:04:05+0100","from":"4","to":"5","next":"item 11: later than any stamp"}' >/dev/null
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T03:05:00+0100","band":80,"context":"c","spent_usd":5,"pack":true}' >/dev/null
RUNENV="STUB_MODE=complete STUB_N=0"
starter --run rage7 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rage7-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "pack: unstamped"
need_out "carries no"
need_absent "re-derived"
need_out "head-successor"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations"
case $(mk section "$HO" "In flight") in
  *"the hand-written pack"*) : ;;
  *) why="$why; the unstamped pack was rewritten" ;;
esac
verdict "the pack-age guard: an unstamped pack (planted with --set, against a 2030 boundary) is left alone and the successor still starts (control: the same 2030 boundary re-derived a stamped pack two legs above)"

# The comparison's edge, both sides planted with --set, which writes no stamp of its own.
fixture rage8 200
mk append "$REC" '{"event":"phase-boundary","ts":"2030-01-02T03:04:05+0100","from":"5","to":"6","next":"item 12: the edge"}' >/dev/null
run handoff --run rage8 --set "inflight=- pack written: 2030-01-02T03:04:05+0100
- Next: stamped at the boundary
- Needs: wiki/i.md:4
- Decided: D9 because r"
need_rc 0
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage8 --session sid-edge-equal --head "h" --detail "stamped at the boundary"
need_rc 0
need_absent "in-flight pack is stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations at the edge"
run handoff --run rage8 --set "inflight=- pack written: 2030-01-02T03:04:04+0100
- Next: stamped one second before the boundary
- Needs: wiki/i.md:4
- Decided: D9 because r"
need_rc 0
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage8 --session sid-edge-before --head "h" --detail "stamped a second early"
need_rc 0
need_out "in-flight pack is stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "1" "stale-pack observations one second earlier"
verdict "the pack-age guard's edge: a pack stamped at the boundary's own timestamp is fresh, and the same pack stamped one second earlier is stale (the control on the same fixture)"

# The head-exit `handoff --final` writes carries the pack, so it is not the anchor; the exit the
# supervisor writes for a head that wrote none is.
fixture rage9 200
run handoff --run rage9 --inflight "- Next: written with the final hand-off
- Needs: wiki/j.md:5
- Decided: D10 because q"
need_rc 0
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T03:04:05+0100","band":80,"context":"c","spent_usd":5,"pack":true}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage9 --session sid-packtrue --head "h" --detail "after a final hand-off"
need_rc 0
need_absent "in-flight pack is stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations after a pack-true exit"
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T03:04:06+0100","band":80,"context":"c","spent_usd":5,"pack":false}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rage9 --session sid-packfalse --head "h" --detail "after an exit with no pack"
need_rc 0
need_out "in-flight pack is stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "1" "stale-pack observations after a pack-false exit"
verdict "the pack-age guard: a head-exit carrying pack true is skipped as the anchor (a 2030 exit leaves a 2026 pack fresh), and the same exit with pack false one second later makes it stale (the control on the same fixture)"

# An anchor whose timestamp this script cannot parse: unmeasured, not stale — a comparison that
# cannot be made is not evidence of age.
fixture rageA 200
run handoff --run rageA --inflight "- Next: against an unparsable boundary
- Needs: wiki/k.md:6
- Decided: D11 because p"
need_rc 0
mk append "$REC" '{"event":"phase-boundary","ts":"the third of never","from":"6","to":"7","next":"item 13: unparsable"}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rageA --session sid-unmeasured --head "h" --detail "an unparsable boundary"
need_rc 0
need_absent "in-flight pack is stale"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations against an unparsable anchor"
mk append "$REC" '{"event":"phase-boundary","ts":"2030-01-02T03:04:05+0100","from":"7","to":"8","next":"item 14: parsable again"}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rageA --session sid-measured --head "h" --detail "a parsable boundary"
need_rc 0
need_out "in-flight pack is stale"
verdict "the pack-age guard: a boundary whose timestamp does not parse leaves the pack unmeasured rather than stale, and a parsable later boundary on the same fixture is the control"

# A hand-off with no '## In flight' section at all: nothing to age, nothing re-derived, and the
# start is not blocked by the guard.
fixture rageB 200 inflight
mk append "$REC" '{"event":"phase-boundary","ts":"2030-01-02T03:04:05+0100","from":"8","to":"9","next":"item 15: no section to compare"}' >/dev/null
mk append "$REC" '{"event":"head-exit","ts":"2030-01-02T03:05:00+0100","band":80,"context":"c","spent_usd":5,"pack":true}' >/dev/null
RUNENV="STUB_MODE=complete STUB_N=0"
starter --run rageB --handoff "$HO" --budget 3.50 --out "$WORK/starter/rageB-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "no '## In flight' section"
need_absent "re-derived"
need_out "head-successor"
need_eq "$(grep -c 'stale-pack' "$REC")" "0" "stale-pack observations with no section"
verdict "the pack-age guard: a hand-off with no '## In flight' section (the section dropped from the fixture) is reported and left alone, and the successor still starts"

# The derived pack against the D41 label gate: what the guard writes must pass the check a head's
# own pack must pass, or a re-derivation would leave a hand-off --final would refuse.
fixture rageC 200
mk append "$REC" '{"event":"phase-boundary","ts":"2026-01-02T03:04:05+0100","from":"9","to":"10","next":"item 16: the final derived next"}' >/dev/null
mk append "$REC" '{"event":"lane-open","ts":"2026-01-02T04:00:00+0100","lane":"B11","class":"builder","model":"opus","reason":"open at the final"}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rageC --inflight-from-record --final --band 80 --meter-line "$METER"
need_rc 0
need_out "head-exit recorded"
need_eq "$(mk field "$REC" head-exit pack)" "true" "the head-exit's pack flag"
case $(mk section "$HO" "In flight") in
  "- pack re-derived from the record at "*) : ;;
  *) why="$why; the final hand-off does not carry the derived pack" ;;
esac
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rageC --final --band 80 --meter-line "$METER" --inflight "- Next: one label only"
need_rc 2
need_out "the next-task pack lacks"
need_lines
verdict "handoff --inflight-from-record --final: the derived pack passes the same D41 label gate a head's own pack must pass, and a one-label pack on the same fixture is still refused (exit 2)"

# The supervisor's own successor start, not the starter's: the head it launched stops at a limit
# above the first edge, the supervisor writes the head-exit the head owed (pack false) and starts
# a successor — and that pack, fresh when the run began, is older than the exit just written.
fixture rageD 200
arm_resume rageD
mk append "$REC" '{"event":"head-exit","ts":"2020-01-02T03:04:05+0100","band":80,"context":"c","spent_usd":5,"pack":false}' >/dev/null
run handoff --run rageD --inflight "- Next: fresh when the first head started
- Needs: wiki/l.md:7
- Decided: D12 because o"
need_rc 0
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=150000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rageD --handoff "$HO" --budget 3.50 --out "$WORK/starter/rageD-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_out "pack: fresh"
need_out "pack: STALE"
need_out "re-derived from the record"
S=$(mk count "$REC" head-successor); [ "$S" -ge 2 ] || why="$why; head-successor events $S, wanted 2 or more"
G=$(grep -c 'stale-pack' "$REC"); [ "$G" -ge 1 ] || why="$why; no stale-pack observation from the supervisor's successor start ($G)"
SEC=$(mk section "$HO" "In flight")
case $SEC in "- pack re-derived from the record at "*) : ;; *) why="$why; no re-derivation header after the supervisor's start: $SEC" ;; esac
case $SEC in *"fresh when the first head started"*) why="$why; the stale pack survived into the successor's brief" ;; *) : ;; esac
case $SEC in *"the record carries no phase-boundary event"*) : ;; *) why="$why; the derivation does not say the record holds no boundary: $SEC" ;; esac
verdict "the pack-age guard on the supervisor's own successor path: the first start reports the pack fresh, the head-exit the supervisor writes for a limit stop makes it stale, and the second start re-derives the section before briefing the successor"

# ------------------------------------------------------------------ orientation (D41) -----
fixture rorient 200
mk transcript sid-rorient 100000 60000 >/dev/null
run gate --run rorient --to "item one"
need_rc 0
need_out "orientation 40,000"
need_eq "$(mk field "$REC" gate orientation_tokens)" "40000" "orientation_tokens"
run gate --run rorient --to "item two"
need_rc 0
need_absent "orientation"
need_eq "$(mk field "$REC" gate orientation_tokens)" "<no key orientation_tokens>" "no orientation on a later gate"
verdict "gate: the first gate of a session records orientation_tokens = context minus the first-call context; later gates do not"

fixture rorient2 200
mk transcript sid-rorient2 100000 60000 >/dev/null
mk append "$REC" '{"event":"head-resumed","session_id":"sid-rorient2","pid":1,"context":90000,"waited_s":1,"reset_source":"x","resume_n":1}' >/dev/null
run gate --run rorient2 --to "item one"
need_rc 0
need_eq "$(mk field "$REC" gate orientation_tokens)" "null" "null after a resume"
need_eq "$(mk field "$REC" gate orientation_note)" "unmeasured after a resume" "the note"
fixture rorient3 200
run gate --run rorient3 --to "item one"
need_eq "$(mk field "$REC" gate orientation_tokens)" "null" "null when unmetered"
case $(mk field "$REC" gate orientation_note) in
  "unmetered gate"*) : ;;
  *) why="$why; the unmetered note is wrong: $(mk field "$REC" gate orientation_note)" ;;
esac
verdict "gate: orientation is null with its reason after a head-resumed event and on an unmetered gate"

# A run-resume naming the session the head event before it named: the process kept its context,
# so its first call after the resume carries the whole session (337,762 tokens seen, 2026-09-05)
# and the difference is not an orientation cost.
fixture rorient6 200
mk transcript sid-rorient6b 100000 60000 >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-rorient6b","pid":1,"budget":1.0}' >/dev/null
mk append "$REC" '{"event":"gate","item":"an earlier item","context":61000,"percent":6,"band":0,"armed":false,"decision":"allow","metered":true,"orientation_tokens":1240}' >/dev/null
mk append "$REC" '{"event":"run-resume","session":"sid-rorient6b","head":"fixture head","detail":"resumed in place","pid_src":"none"}' >/dev/null
run gate --run rorient6 --to "item one"
need_rc 0
need_eq "$(mk field "$REC" gate orientation_tokens)" "null" "null after a same-session resume"
need_eq "$(mk field "$REC" gate orientation_note)" "unmeasured after a same-session resume" "the note"
need_absent "orientation 40,000"
verdict "gate: the first gate after a run-resume naming the previous head event's own session records orientation_tokens null with the same-session note"

fixture rorient7 200
mk transcript sid-rorient7b 100000 60000 >/dev/null
mk append "$REC" '{"event":"run-resume","session":"sid-rorient7b","head":"fixture head","detail":"a fresh session","pid_src":"none"}' >/dev/null
run gate --run rorient7 --to "item one"
need_rc 0
need_out "orientation 40,000"
need_eq "$(mk field "$REC" gate orientation_tokens)" "40000" "orientation still measured"
need_eq "$(mk field "$REC" gate orientation_note)" "<no key orientation_note>" "no note when it is measured"
verdict "gate: a run-resume naming a session the record has not seen still measures orientation (the control for the leg above)"

# A head-successor and the run-resume its successor writes share a session id BY DESIGN, so the
# shared id alone must not null the successor's own first gate. The shape is the run record of
# 2026-09-06 (a seeded head-exit with no transcript, a head-successor, then the run-resume, with
# no gate of that session in between): HANDSOFF_REAL_RECORD points the legs at that record — its
# session ids rewritten to this suite's own — and without it the same eight events are built here.
REALREC=${HANDSOFF_REAL_RECORD:-}
shape_record() { # $1 destination record, $2 the session id to give the resumed head
  if [ -f "$REALREC" ]; then
    "$PY" - "$REALREC" "$1" "$2" <<'SHAPE'
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()][:8]
last = [e.get("session") or e.get("session_id") for e in evs
        if e.get("event") in ("run-open", "run-resume", "head-successor")][-1]
for e in evs:
    for key in ("session", "session_id"):
        if e.get(key):
            e[key] = sys.argv[3] if e[key] == last else "sid-seeded-head"
open(sys.argv[2], "w", encoding="utf-8").write("".join(json.dumps(e) + "\n" for e in evs))
SHAPE
    SHAPE_SRC="the run record of 2026-09-06"
  else
    mk append "$1" '{"event":"observation","phase":"","what":"head exited","exit_class":"error","note":"the seeded head never ran"}' >/dev/null
    mk append "$1" '{"event":"head-exit","band":"unmetered","context":"unmetered (transcript missing: a path that is not there)","exit_class":"error","pack":false}' >/dev/null
    mk append "$1" "{\"event\":\"head-successor\",\"session_id\":\"$2\",\"pid\":1,\"budget\":1.0}" >/dev/null
    mk append "$1" "{\"event\":\"run-resume\",\"session\":\"$2\",\"head\":\"fixture head\",\"detail\":\"the successor records itself\",\"pid_src\":\"none\"}" >/dev/null
    SHAPE_SRC="the same eight events built here"
  fi
}

fixture rorient8 200
shape_record "$REC" sid-rorient8b
mk transcript sid-rorient8b 72167 59763 >/dev/null
run gate --run rorient8 --to "item one"
need_rc 0
need_eq "$(mk field "$REC" gate orientation_tokens)" "12404" "the successor's own first gate stays measured"
need_eq "$(mk field "$REC" gate orientation_note)" "<no key orientation_note>" "no note on a measured gate"
need_out "orientation 12,404"
verdict "gate: a run-resume naming the head-successor's own session, with no gate of that session before it, still measures orientation ($SHAPE_SRC)"

fixture rorient9 200
shape_record "$REC" sid-rorient9b
mk transcript sid-rorient9b 72167 59763 >/dev/null
"$PY" - "$REC" <<'INSERT'
import json, sys
path = sys.argv[1]
evs = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
cut = max(i for i, e in enumerate(evs) if e.get("event") == "run-resume")
gate = {"ts": evs[cut]["ts"], "run": evs[cut].get("run"), "event": "gate", "item": "an earlier item",
        "context": 61000, "percent": 6, "band": 0, "armed": False, "decision": "allow",
        "metered": True, "orientation_tokens": 1240}
evs.insert(cut, gate)
open(path, "w", encoding="utf-8").write("".join(json.dumps(e) + "\n" for e in evs))
INSERT
run gate --run rorient9 --to "item one"
need_rc 0
need_eq "$(mk field "$REC" gate orientation_tokens)" "null" "null once that session has gated before the resume"
need_eq "$(mk field "$REC" gate orientation_note)" "unmeasured after a same-session resume" "the note"
verdict "gate: the same shape with one gate of that session BEFORE the run-resume nulls the first gate after it (the control for the leg above)"

# ----------------------------------------------------------- N5: the envelope remainder ----
fixture rspent 100
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":50}' >/dev/null
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":40}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rspent --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "budget \$10.00"
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":10}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rspent --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 2
need_out "the envelope is spent"
need_lines
need_eq "$(mk field "$REC" successor-aborted reason)" "budget" "successor-aborted budget"
verdict "successor: the remainder is the envelope minus every head-exit's spent_usd (10 of 100); spent → successor-aborted budget"

# ------------------------------------------------- the limit gate (D42): the grants file's key ---
HO="$WORK/handoffs/onl-handoff.md"; mk handoff "$HO" >/dev/null
REC="$STORE/spawn-records/ronl.jsonl"; rm -f "$REC"
GF="$STORE/spawn-records/ronl-grants.json"; rm -f "$GF"
run run-open --run ronl --session sid-onl --head "fixture head" --regime single --regime-src owner \
    --handoff "$HO" --detail "gate" --pid 1
need_rc 0
need_eq "$(gval "$GF")" "stop" "run-open default"
need_eq "$(mk field "$REC" run-open on_limit)" "stop" "the run-open event"
need_eq "$(mk field "$REC" run-open on_limit_src)" "default (no grants file)" "the source"
need_out "on_limit stop (default (no grants file))"
run grants --run ronl --on-limit resume
need_rc 0
need_eq "$(gval "$GF")" "resume" "grants --on-limit resume"
need_out "on_limit resume (--on-limit)"
run grants --run ronl --grant "$WORK/handoffs"
need_rc 0
need_eq "$(gval "$GF")" "resume" "a rebuild with --grant carries resume forward"
need_eq "$(mk field "$REC" grants on_limit_src)" "grants" "carried from the file"
run run-resume --run ronl --session sid-onl2 --head "fixture head" --detail "flag-less" --pid 1
need_rc 0
need_eq "$(gval "$GF")" "resume" "a flag-less run-resume keeps the file"
need_eq "$(mk field "$REC" run-resume on_limit)" "resume" "the run-resume event"
run run-resume --run ronl --session sid-onl3 --head "fixture head" --detail "rebuild" --pid 1 --grant "$WORK/handoffs"
need_rc 0
need_eq "$(gval "$GF")" "resume" "a run-resume rebuild with --grant carries resume forward"
run run-resume --run ronl --session sid-onl4 --head "fixture head" --detail "set stop" --pid 1 --on-limit stop
need_rc 0
need_eq "$(gval "$GF")" "stop" "run-resume --on-limit stop rewrites"
need_eq "$(mk field "$REC" run-resume on_limit_src)" "--on-limit" "the source"
REC2="$STORE/spawn-records/ronl2.jsonl"; rm -f "$REC2"
run run-open --run ronl2 --session sid-onl5 --head "fixture head" --regime single --regime-src owner \
    --handoff "$HO" --detail "gate" --pid 1 --on-limit resume
need_rc 0
need_eq "$(gval "$STORE/spawn-records/ronl2-grants.json")" "resume" "run-open --on-limit resume"
verdict "limit gate (D42): run-open writes on_limit stop by default and resume under the flag; grants --on-limit sets it; every rebuild (grants --grant, run-resume --grant) and a flag-less run-resume carry it forward; --on-limit stop rewrites"

run grants --run ronl --grants-file "$WORK/elsewhere-grants.json" --on-limit resume
need_rc 2
need_out "needs the default grants path"
need_nofile "$WORK/elsewhere-grants.json"
verdict "limit gate (D42): --on-limit resume with --grants-file is refused — the supervisor and the status hook read the default path only (C2 H2)"

# --------------------------------------------------------- the supervisor: limit, resume ---
fixture rlim 200
arm_resume rlim
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
OUT="$WORK/starter/rlim-head-1.out"
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rlim --handoff "$HO" --budget 3.50 --out "$OUT" --wait-s 5 --harness-bin "$WORK/bin/stubhead" \
        --meter-line "$METER" --reset-at +2s --tick-s 1
need_rc 0
need_eq "$(mk field "$REC" stop-condition which)" "limit" "stop-condition"
case $(mk field "$REC" stop-condition action) in
  "wait until "*"(--reset-at +2s)") : ;;
  *) why="$why; --reset-at did not win over the stop text: $(mk field "$REC" stop-condition action)" ;;
esac
need_eq "$(mk field "$REC" stop-condition note)" "You've hit your session limit · resets 8:50am (Europe/London)" "the stop text"
need_eq "$(mk field "$REC" stop-condition on_limit_src)" "grants" "the gate read from the grants file"
case $(mk field "$REC" stop-condition watch) in "transcript "*) : ;; *) why="$why; the stop-condition names no watched transcript: $(mk field "$REC" stop-condition watch)" ;; esac
need_eq "$(mk field "$REC" head-resumed context)" "50000" "head-resumed context"
need_eq "$(mk field "$REC" head-resumed resume_n)" "1" "resume_n"
need_eq "$(mk field "$REC" head-resumed reset_source)" "--reset-at +2s" "reset_source"
need_eq "$(mk field "$REC" head-resumed out)" "$OUT" "out"
W=$(mk field "$REC" head-resumed waited_s); [ "$W" -ge 2 ] || why="$why; waited_s $W under 2"
case $(sed -n 2p "$WORK/stub-rlim.args") in
  *"--resume "*) : ;;
  *) why="$why; the second invocation is not a --resume: $(sed -n 2p "$WORK/stub-rlim.args")" ;;
esac
case $(sed -n 2p "$WORK/stub-rlim.args") in *"--session-id"*) why="$why; the resume carries --session-id" ;; esac
grep -q "RESUMED after the account window reset" "$WORK/stub-rlim.stdin.2" || why="$why; the resume note is missing"
grep -q "Lanes closed with exit class limit: resume each with lane.py resume" "$WORK/stub-rlim.stdin.2" || why="$why; the note's last sentence is missing"
need_eq "$(grep -c '"type":"result"' "$OUT")" "2" "both results appended to the same .out"
case $(mk field "$REC" observation note) in handed-over*) : ;; *) why="$why; not ended handed-over" ;; esac
verdict "supervisor: a limit stop waits (--reset-at wins over the text), resumes under the edge with the note on stdin, then the hand-over ends it"

fixture rlim2 200
arm_resume rlim2
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=150000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rlim2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rlim2-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume at 75 %"
"$PY" - "$REC" <<'CHAIN' > "$WORK/chain.txt"
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ex = [e for e in evs if e.get("event") == "head-exit" and e.get("exit_class")]
print("%s %s %s" % (ex[0]["band"], ex[0]["exit_class"], ex[0].get("spent_usd")) if ex else "none")
CHAIN
need_eq "$(cat "$WORK/chain.txt")" "limit limit 19.62" "head-exit band limit with spent_usd"
need_eq "$(mk count "$REC" head-successor)" "3" "the successor path ran"
case $(sed -n 2p "$WORK/stub-rlim2.args") in *"--session-id"*) : ;; *) why="$why; the successor is not a fresh session" ;; esac
verdict "supervisor: a limit stop at or above the first edge writes head-exit band limit and starts the successor"

# ------------------------------------------- the limit gate (D42, D43): stop and stand down ---
# t2: the default. No grants file at all → on_limit stop, source "default (no grants file)": the
# supervisor writes the stop-condition and stands down at once — no wait, no resume, exit 0.
fixture rstop 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rstop --handoff "$HO" --budget 3.50 --out "$WORK/starter/rstop-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_out "stood down (limit-stop)"
need_eq "$(mk field "$REC" stop-condition which)" "limit" "stop-condition"
need_eq "$(mk field "$REC" stop-condition action)" "stand-down: on_limit stop" "the action"
need_eq "$(mk field "$REC" stop-condition on_limit_src)" "default (no grants file)" "the source"
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "limit-stop" "stood-down reason"
need_eq "$(mk field "$REC" supervisor-stood-down on_limit)" "stop" "on_limit"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume"
need_eq "$(mk count "$REC" successor-aborted)" "0" "not an abort"
need_eq "$(cat "$WORK/stub-rstop.count")" "1" "one start, no second"
verdict "limit gate (D42): with no grants file the default on_limit stop stands the supervisor down at once — stop-condition, supervisor-stood-down limit-stop, exit 0, no wait, no resume"

# resume-head (D42's recovery, C2 M4): after the stand-down above, the owner's command resumes the
# head in place — armed (AIMYTH_HANDSOFF_RUN), with the head-resumed event, supervised to its hand-over.
RSID=$(mk field "$REC" head-successor session_id)
run resume-head --run rstop --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --dry-run
need_rc 0
need_out "would detach"
need_out "_resume-head --run rstop --session $RSID"
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
run _resume-head --run rstop --session "$RSID" --out "$WORK/starter/rstop-head-1.out" \
    --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --wait-s 5 --tick-s 1
need_rc 0
need_eq "$(mk count "$REC" head-resumed)" "1" "head-resumed"
need_eq "$(mk field "$REC" head-resumed reset_source)" "resume-head (by hand, after the reset)" "the source"
case $(sed -n 2p "$WORK/stub-rstop.args") in *"--resume $RSID"*) : ;; *) why="$why; the second invocation is not a --resume of the session: $(sed -n 2p "$WORK/stub-rstop.args")" ;; esac
need_eq "$(cat "$WORK/stub-rstop.env")" "rstop" "AIMYTH_HANDSOFF_RUN seen by the resumed head (armed)"
case $(mk field "$REC" observation note) in handed-over*) : ;; *) why="$why; not ended handed-over: $(mk field "$REC" observation note)" ;; esac
verdict "resume-head (D42, C2 M4): after a stand-down the owner's command resumes the last head in place — armed, head-resumed recorded, supervised to the hand-over"

# t7: a grants file written before the gate existed (no on_limit key) reads stop, source "default (key absent)".
fixture rstop2 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
printf '{"run":"rstop2","grants":[],"writes":[]}\n' > "$STORE/spawn-records/rstop2-grants.json"
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rstop2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rstop2-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_eq "$(mk field "$REC" stop-condition on_limit_src)" "default (key absent)" "the source"
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "limit-stop" "stood-down"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume"
verdict "limit gate (D42): a grants file without the key reads stop, source default (key absent)"

# t3: under resume, the transcript changes during the wait (the owner continued the session by
# hand) → supervisor-stood-down resumed-by-hand, no resume call. The starter runs in the
# background with a 6 s reset; the leg appends one record to the head's transcript once the
# stop-condition is written. The rlim leg above is the control: unchanged → head-resumed.
fixture rhand 200
arm_resume rhand
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rhand --handoff "$HO" --budget 3.50 --out "$WORK/starter/rhand-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +6s --tick-s 1 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
HSID=$(mk field "$REC" head-successor session_id)
HTR=$(find "$PROJECTS" -name "$HSID.jsonl" | head -1)
[ -n "$HTR" ] || why="$why; no transcript for the head session $HSID under $PROJECTS"
printf '{"type":"user","message":{"role":"user","content":"continue"}}\n' >> "$HTR"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_out "stood down (resumed-by-hand)"
case $(mk field "$REC" stop-condition watch) in "transcript "*) : ;; *) why="$why; the stop-condition names no watched transcript: $(mk field "$REC" stop-condition watch)" ;; esac
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "resumed-by-hand" "stood-down reason"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume"
need_eq "$(mk count "$REC" successor-aborted)" "0" "not an abort"
need_eq "$(cat "$WORK/stub-rhand.count")" "1" "one start, no second"
verdict "limit gate (D43): under resume, a transcript that changes during the wait stands the supervisor down (resumed-by-hand) with no resume call — the rlim leg is its control (unchanged transcript → head-resumed)"

# t4: supervise --stop needs no harness ancestor (it precedes pid resolution), writes the marker,
# and the sleeping supervisor stands down (stopped) at its next tick.
fixture rmark 200
arm_resume rmark
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rmark --handoff "$HO" --budget 3.50 --out "$WORK/starter/rmark-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +6s --tick-s 1 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
RUNENV="PATH=$WORK/psnone:$PATH"
run supervise --run rmark --stop
need_rc 0
need_out "stop marker written"
need_file "$STORE/spawn-records/rmark-supervisor.stop"
need_eq "$(mk field "$REC" supervise mode)" "stop-requested" "the supervise event"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "stopped" "stood-down reason"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume"
verdict "limit gate (D43): supervise --stop under the no-ancestor stub writes the marker, and the sleeping supervisor stands down (stopped) at its next tick"

# a fresh arming removes a stale marker: the rmark marker is still on disk; a new starter for the
# same run must not stand down on it.
fixture rmark2 200
arm_resume rmark2
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
printf 'stale\n' > "$STORE/spawn-records/rmark2-supervisor.stop"
RUNENV="STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rmark2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rmark2-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_out "stale stop marker removed"
need_eq "$(mk count "$REC" supervisor-stood-down)" "0" "no stand-down on a stale marker"
need_eq "$(mk count "$REC" head-resumed)" "1" "the resume ran"
verdict "limit gate (D43): a fresh arming removes a stale stop marker and the wait proceeds to the resume"

# t4c: a stop marker present AT THE HEAD'S EXIT stands the supervisor down before any successor
# decision, on the successor fork of a head that did not stop on a limit — the shape of the
# 2026-09-07 register entry, where a marker written at 16:22 did not stop the successor started
# after a SIGTERM at 16:24. The supervisor is attached to a pid that is already gone, so the
# classification runs at once off the head's own .out; t4d below is the same fixture with no
# marker, and it starts the successor.
fixture rexit 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"terminated by a signal"}' > "$WORK/rexit.out"
printf 'stopped by the owner\n' > "$STORE/spawn-records/rexit-supervisor.stop"
RC=0
env "$PY" -B "$H" _supervise --run rexit --pid 999999 --session sid-rexit \
    --out "$WORK/rexit.out" --harness-bin "$WORK/bin/stubhead" --handoff "$HO" \
    --meter-line "$METER" --tick-s 1 --wait-s 2 >"$WORK/out" 2>"$WORK/err" || RC=$?
cat "$WORK/out" "$WORK/err" >"$WORK/both"
need_rc 0
need_out "stood down (stopped)"
need_out "a stop marker was on disk at the head's exit"
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "stopped" "stood-down reason"
need_eq "$(mk count "$REC" head-successor)" "0" "no successor start"
need_eq "$(mk count "$REC" successor-aborted)" "0" "not an abort"
[ -f "$WORK/stub-rexit.count" ] && why="$why; the stub head was started"
need_file "$STORE/spawn-records/rexit-supervisor.stop"
verdict "stop marker (2026-09-07): a marker on disk at a head's exit stands the supervisor down (stopped) before the successor decision, on a non-limit exit class; the marker is left for the record"

# t4c2: the other fork — a head that left NO head-exit, classified from its own .out (the shape a
# signalled head takes). The marker stands the supervisor down there too.
fixture rexit4 200
printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"terminated by a signal"}' > "$WORK/rexit4.out"
printf 'stopped by the owner\n' > "$STORE/spawn-records/rexit4-supervisor.stop"
RC=0
env "$PY" -B "$H" _supervise --run rexit4 --pid 999999 --session sid-rexit4 \
    --out "$WORK/rexit4.out" --harness-bin "$WORK/bin/stubhead" --handoff "$HO" \
    --meter-line "$METER" --tick-s 1 --wait-s 2 >"$WORK/out" 2>"$WORK/err" || RC=$?
cat "$WORK/out" "$WORK/err" >"$WORK/both"
need_rc 0
need_out "stood down (stopped)"
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "stopped" "stood-down reason"
need_eq "$(mk count "$REC" head-exit)" "0" "no head-exit written by the supervisor"
need_eq "$(mk count "$REC" head-successor)" "0" "no successor start"
[ -f "$WORK/stub-rexit4.count" ] && why="$why; the stub head was started"
verdict "stop marker: on the classifier's own fork too (a head that left no head-exit, the signalled shape) the marker stands the supervisor down before the successor decision"

# t4d: the control — the same fixture and the same exit, with no marker: the successor starts.
fixture rexit2 200
printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"terminated by a signal"}' > "$WORK/rexit2.out"
need_nofile "$STORE/spawn-records/rexit2-supervisor.stop"
RC=0
env STUB_MODE=complete STUB_N=0 "$PY" -B "$H" _supervise --run rexit2 --pid 999999 \
    --session sid-rexit2 --out "$WORK/rexit2.out" --harness-bin "$WORK/bin/stubhead" \
    --handoff "$HO" --meter-line "$METER" --tick-s 1 --wait-s 2 >"$WORK/out" 2>"$WORK/err" || RC=$?
cat "$WORK/out" "$WORK/err" >"$WORK/both"
need_eq "$(mk count "$REC" supervisor-stood-down)" "0" "no stand-down without a marker"
need_eq "$(cat "$WORK/stub-rexit2.count")" "1" "the stub head was started once (the successor)"
need_out "successor path"
verdict "stop marker: the control — the same exit with no marker takes the successor path and starts one head"

# t4e: arming a supervisor does not clear the marker (the three clearing sites are resume-head, a
# successor called by a head, and close). The marker planted here survives the attach, so the
# supervisor stands down at the head's exit rather than succeeding it.
fixture rexit3 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"terminated by a signal"}' > "$WORK/rexit3.out"
printf 'stopped by the owner\n' > "$STORE/spawn-records/rexit3-supervisor.stop"
RC=0
env "$PY" -B "$H" _supervise --run rexit3 --pid 999999 --session sid-rexit3 \
    --out "$WORK/rexit3.out" --harness-bin "$WORK/bin/stubhead" --handoff "$HO" \
    --meter-line "$METER" --tick-s 1 --wait-s 2 >"$WORK/out" 2>"$WORK/err" || RC=$?
cat "$WORK/out" "$WORK/err" >"$WORK/both"
need_absent "stale stop marker removed"
need_file "$STORE/spawn-records/rexit3-supervisor.stop"
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "stopped" "stood-down reason"
verdict "stop marker: attaching a supervisor never clears the marker (no 'stale stop marker removed' line), so a stopped run stays stopped across a re-arming"

# t8: the ≥60 % fork under resume with the transcript changed during the wait → stood down, no
# successor start (the last-act check before successor_path is the same check the tick runs).
fixture rhand2 200
arm_resume rhand2
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=150000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rhand2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rhand2-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +6s --tick-s 1 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
HSID=$(mk field "$REC" head-successor session_id)
HTR=$(find "$PROJECTS" -name "$HSID.jsonl" | head -1)
[ -n "$HTR" ] || why="$why; no transcript for the head session $HSID under $PROJECTS"
printf '{"type":"user","message":{"role":"user","content":"continue"}}\n' >> "$HTR"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "resumed-by-hand" "stood-down reason"
need_eq "$(mk count "$REC" head-successor)" "1" "no successor start after the stand-down (the starter's own only)"
need_eq "$(cat "$WORK/stub-rhand2.count")" "1" "one start, no second"
verdict "limit gate (D43): at 75 % (the successor fork) a transcript that changes during the wait stands the supervisor down before any successor start"

# t6: no transcript file (no STUB_TOKENS) → the wait is unwatched, recorded as such, and proceeds.
fixture runw 200
arm_resume runw
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=limit STUB_N=1 AIMYTH_CONTEXT_WINDOW=200000"
starter --run runw --handoff "$HO" --budget 3.50 --out "$WORK/starter/runw-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_eq "$(mk field "$REC" stop-condition watch)" "unwatched (no transcript file)" "the watch label"
need_eq "$(mk count "$REC" supervisor-stood-down)" "0" "no stand-down"
verdict "limit gate (D43): with no transcript file the wait is recorded unwatched and proceeds"

# t3d / t8b (C2 M3): the LAST-ACT check. The change lands after the wait's last tick and before
# the start: --reset-at +8s with --tick-s 5 checks at 0 s and 5 s, then sleeps to 8 s; the leg
# appends at ≈6.5 s. A per-tick-only implementation resumes; the last-act check stands down.
# Timing-dependent by construction (margins ≈1.5 s each side on this machine).
fixture rlast 200
arm_resume rlast
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rlast --handoff "$HO" --budget 3.50 --out "$WORK/starter/rlast-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +8s --tick-s 5 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
sleep 6
HSID=$(mk field "$REC" head-successor session_id)
HTR=$(find "$PROJECTS" -name "$HSID.jsonl" | head -1)
printf '{"type":"user","message":{"role":"user","content":"continue"}}\n' >> "$HTR"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "resumed-by-hand" "stood-down reason"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume"
verdict "limit gate (D43, C2 M3): the resume fork's last-act check catches a change after the wait's last tick (timing leg)"

fixture rlast2 200
arm_resume rlast2
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=150000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rlast2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rlast2-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +8s --tick-s 5 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
sleep 6
HSID=$(mk field "$REC" head-successor session_id)
HTR=$(find "$PROJECTS" -name "$HSID.jsonl" | head -1)
printf '{"type":"user","message":{"role":"user","content":"continue"}}\n' >> "$HTR"
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 0
need_eq "$(mk field "$REC" supervisor-stood-down reason)" "resumed-by-hand" "stood-down reason"
need_eq "$(mk count "$REC" head-successor)" "1" "no successor start (the starter's own only)"
need_eq "$(cat "$WORK/stub-rlast2.count")" "1" "one start, no second"
verdict "limit gate (D43, C2 H1): the successor fork's last-act check, inside start_head after the meter, catches a change after the wait's last tick (timing leg)"

fixture rbud 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=budget STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rbud --handoff "$HO" --budget 3.50 --out "$WORK/starter/rbud-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_eq "$(mk count "$REC" stop-condition)" "0" "no wait after a budget stop"
need_eq "$(mk field "$REC" head-resumed budget)" "175.38" "the resume's cap is the remainder (200 - 5 - 19.62)"
case $(sed -n 2p "$WORK/stub-rbud.args") in *"--resume "*"--max-budget-usd 175.38"*) : ;; *) why="$why; the resume's argv lacks the remainder cap" ;; esac
grep -q "RESUMED after a budget stop" "$WORK/stub-rbud.stdin.2" || why="$why; the budget note is missing"
fixture rbud2 20
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=budget STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rbud2 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rbud2-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 1
need_eq "$(mk field "$REC" successor-aborted reason)" "budget" "successor-aborted budget"
need_eq "$(mk count "$REC" head-resumed)" "0" "no resume on a spent envelope"
verdict "supervisor: a budget stop resumes at once at the remainder; a spent envelope aborts (budget)"

fixture rn4 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=handonly STUB_N=1"
starter --run rn4 --handoff "$HO" --budget 3.50 --out "$WORK/starter/rn4-head-1.out" --wait-s 2 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "has no successor after 2 s"
need_eq "$(mk count "$REC" head-successor)" "3" "starter, the N4 start, the stub's own"
need_eq "$(mk count "$REC" successor-aborted)" "0" "no abort"
need_eq "$(cat "$WORK/stub-rn4.count")" "2" "stub invocations"
case $(mk field "$REC" observation note) in handed-over*) : ;; *) why="$why; the control did not end handed-over" ;; esac
verdict "supervisor (N4): a head-exit with no head-successor after the wait gets the successor path; with one present, handed-over ends it"

fixture rcap 200
arm_resume rcap
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=limit STUB_N=3 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rcap --handoff "$HO" --budget 3.50 --out "$WORK/starter/rcap-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +1s --tick-s 1
need_rc 0
need_eq "$(mk count "$REC" head-resumed)" "2" "resumes capped at 2 (N6)"
need_eq "$(mk field "$REC" head-resumed resume_n)" "2" "resume_n"
need_eq "$(mk count "$REC" head-successor)" "3" "the third limit took the successor path"
verdict "supervisor (N6): resume_n is capped at 2 per session; the third limit takes the successor path"

fixture rrep 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=error STUB_N=2"
starter --run rrep --handoff "$HO" --budget 3.50 --out "$WORK/starter/rrep-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 1
need_eq "$(mk field "$REC" head-exit band)" "error" "an error exit's band (N6)"
need_eq "$(mk field "$REC" successor-aborted reason)" "repeat-stop" "repeat-stop"
need_eq "$(cat "$WORK/stub-rrep.count")" "2" "two starts, no third"
verdict "supervisor (N6): an error exit writes band error; two consecutive error stops abort (repeat-stop)"

# The completed-without-close loop: a head that exits completed with neither a head-exit nor a
# run-close gets its one successor, and a successor doing the same is a loop rather than
# progress. The first stop's successor is this leg's own positive control: the abort is on the
# second stop, not the first, and the head really started twice.
fixture rcomp 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=complete STUB_N=2"
starter --run rcomp --handoff "$HO" --budget 3.50 --out "$WORK/starter/rcomp-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 1
need_eq "$(mk field "$REC" successor-aborted reason)" "repeat-stop" "repeat-stop"
need_eq "$(cat "$WORK/stub-rcomp.count")" "2" "two starts, no third"
need_eq "$(mk count "$REC" head-successor)" "2" "the starter's start and the one successor (the control: the first completed stop was succeeded)"
verdict "supervisor: two consecutive completed-without-close exits abort (repeat-stop) after the first has had its successor"

# The seed guard (register 2026-09-06): a head-exit recording a session that left no transcript
# is not a stop, so it can never be the first of two. The same record's head count leaves that
# session out and the orientation rows carry one row per session id.
fixture rseed 200
shape_record "$REC" sid-rseedb
"$PY" - "$H" "$REC" <<'PREV' > "$WORK/prev.txt"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
evs = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
print(mod.previous_stop(evs))
PREV
need_eq "$(cat "$WORK/prev.txt")" "None" "a seeded head-exit is not a previous stop"
mk append "$REC" '{"event":"observation","phase":"","what":"head exited","exit_class":"error","note":"a head that really ran"}' >/dev/null
mk append "$REC" '{"event":"head-exit","band":"error","context":"500,000 tokens (50 %)","exit_class":"error","spent_usd":3.0,"pack":false}' >/dev/null
"$PY" - "$H" "$REC" <<'PREV2' > "$WORK/prev2.txt"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
evs = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
print(mod.previous_stop(evs))
PREV2
need_eq "$(cat "$WORK/prev2.txt")" "error" "positive control: a metered error head-exit is still a stop"
verdict "supervisor: a head-exit whose session left no transcript is skipped by the repeat-stop guard, while a metered error exit still counts ($SHAPE_SRC)"

WTS="$WORK/rseed-waste.md"
run waste-table --run rseed --out "$WTS" --no-meter
need_rc 0
# One id, not two spans: the head-successor and the run-resume that follows it name the SAME
# session, and counting spans read four heads for two ids (register entry 2026-09-06, fixed
# 2026-09-07). The distinct-id count is asserted in its own leg further down with a control.
need_eq "$(grep -c '1 head session(s)' "$WTS")" "1" "the head count leaves the session with no transcript out"
need_eq "$(grep -c '^| orientation cost · head sid-rseedb' "$WTS")" "1" "one row per session id"
need_eq "$(grep -c 'orientation cost · head sid-seeded-head' "$WTS")" "0" "the session that left no transcript is not a head"
need_eq "$(grep -c '^| orientation cost' "$WTS")" "1" "orientation rows in all"
verdict "waste-table: a session that left no transcript is out of the head count, and the head-successor and run-resume of one session render a single orientation row"

fixture rnojson 200
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
RUNENV="STUB_MODE=nojson STUB_N=1"
starter --run rnojson --handoff "$HO" --budget 3.50 --out "$WORK/starter/rnojson-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --tick-s 1
need_rc 0
need_out "no JSON result line"
need_eq "$(mk field "$REC" head-exit band)" "60" "the last head-exit is the stub's hand-over"
need_eq "$(mk count "$REC" head-successor)" "3" "an error class start, then the hand-over"
verdict "supervisor: a .out with no JSON result line classifies as error (one successor), never as a limit"

fixture rdup 200
arm_resume rdup
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
(
  RCF=0
  env STUB_MODE=limit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000 "$PY" -B "$H" _starter \
      --run rdup --handoff "$HO" --budget 3.50 --out "$WORK/starter/rdup-head-1.out" --wait-s 5 \
      --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --reset-at +3s --tick-s 1 \
      >"$WORK/starter-out" 2>&1 || RCF=$?
  printf '%s\n' "$RCF" > "$WORK/starter-rc"
) &
STARTER=$!
wait_field "$REC" stop-condition which limit 20
mk append "$REC" '{"event":"head-resumed","session_id":"sid-other-supervisor","pid":1,"context":1,"waited_s":1,"reset_source":"x","resume_n":1}' >/dev/null
wait "$STARTER"
RC=$(cat "$WORK/starter-rc")
cp "$WORK/starter-out" "$WORK/both"
need_rc 1
need_eq "$(mk field "$REC" successor-aborted reason)" "duplicate-resume" "duplicate-resume"
need_eq "$(cat "$WORK/stub-rdup.count")" "1" "no second start"
verdict "supervisor: a head-resumed written by another supervisor during the wait refuses the resume (duplicate-resume)"

# The planted input for both legs below is STUB_MODE=nolimit: a limit result whose text names
# no reset time. Without --probe the supervisor sends nothing and hands off; with it, it probes.
fixture rnoprobe 200
arm_resume rnoprobe
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
rm -f "$WORK/stub-probe.count"
RUNENV="STUB_MODE=nolimit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rnoprobe --handoff "$HO" --budget 3.50 --out "$WORK/starter/rnoprobe-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --probe-interval-s 1 --tick-s 1
need_rc 1
need_out "no reset time could be parsed and --probe was not passed"
need_eq "$(mk field "$REC" stop-condition which)" "limit-unparsed" "the unparsed stop-condition"
need_eq "$(mk field "$REC" successor-aborted reason)" "limit-unparsed" "successor-aborted"
need_eq "$(mk count "$REC" head-resumed)" "0" "resumes without a probe"
need_eq "$(cat "$WORK/stub-rnoprobe.count")" "1" "one start, no second"
PROBES=0; [ -f "$WORK/stub-probe.count" ] && PROBES=$(cat "$WORK/stub-probe.count")
need_eq "$PROBES" "0" "probe calls without --probe"
verdict "supervisor: without --probe an unparsed limit sends no probe (0 calls to the stub) and ends limit-unparsed with the hand-off as the recovery"

fixture rprobe 200
arm_resume rprobe
mk append "$REC" '{"event":"head-exit","band":80,"context":"c","spent_usd":5}' >/dev/null
rm -f "$WORK/stub-probe.count"
RUNENV="STUB_MODE=nolimit STUB_N=1 STUB_TOKENS=50000 AIMYTH_CONTEXT_WINDOW=200000"
starter --run rprobe --handoff "$HO" --budget 3.50 --out "$WORK/starter/rprobe-head-1.out" --wait-s 5 \
        --harness-bin "$WORK/bin/stubhead" --meter-line "$METER" --probe-interval-s 1 --tick-s 1 --probe
need_rc 0
need_eq "$(mk field "$REC" stop-condition action)" "probe every 1 s under the same login" "the probe plan"
need_eq "$(cat "$WORK/stub-probe.count")" "2" "one failed probe, one success"
[ "$(cat "$WORK/stub-probe.count")" -ge 1 ] || why="$why; --probe sent no probe at all"
case $(mk field "$REC" head-resumed reset_source) in probe*) : ;; *) why="$why; reset_source is not the probe" ;; esac
verdict "supervisor: with --probe and no reset time it probes under the same login until one succeeds, then resumes (2 calls ≥ 1: the positive control for the zero above)"

# ------------------------------------------------------------------------ supervise -------
fixture rsup 200
run supervise --run rsup --pid 999999 --dry-run
need_rc 2
need_out "is not alive"
verdict "supervise: an explicit --pid that is not alive is refused — a stopped run has no head to attach to (C2 L5)"
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"done"}' > "$WORK/rsup.out"
sleep 3 &
SPID=$!
# The head calls supervise about itself early; its hand-off (head-exit, then its own successor
# call's head-successor) lands later, before its process ends.
run supervise --run rsup --pid "$SPID" --out "$WORK/rsup.out" --harness-bin "$WORK/bin/stubhead" --tick-s 1
need_rc 0
need_out "supervise: pid $SPID session sid-rsup · out $WORK/rsup.out · detached pid"
need_eq "$(mk field "$REC" supervise mode)" "attached" "supervise mode"
need_eq "$(mk field "$REC" supervise pid)" "$SPID" "supervised pid"
mk append "$REC" '{"event":"head-exit","band":60,"context":"c","spent_usd":5}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-next","pid":1,"budget":1.0}' >/dev/null
wait "$SPID"
wait_field "$REC" observation what "supervisor ended" 20
case $(mk field "$REC" observation note) in handed-over*) : ;; *) why="$why; not handed-over: $(mk field "$REC" observation note)" ;; esac
verdict "supervise: attaches to a running pid, detaches at once, and its loop ends handed-over when the pid dies"

RUNENV="PATH=$WORK/psnone:$PATH"
run supervise --run rsup --out "$WORK/rsup.out"
need_rc 2
need_out "no harness ancestor to supervise"
need_lines
verdict "supervise: no claude ancestor and no --pid is refused (exit 2)"

fixture rsup2 200
mk append "$REC" '{"event":"head-exit","band":60,"context":"c"}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-s2","pid":1,"budget":1.0,"out":"/tmp/from-record.out"}' >/dev/null
run supervise --run rsup2 --pid 1 --dry-run
need_rc 0
need_out "out /tmp/from-record.out (head-successor)"
fixture rsup3 200
printf 'x\n' > "$STORE/spawn-records/rsup3-head-1.out"; sleep 1
printf 'x\n' > "$STORE/spawn-records/rsup3-head-2.out"
run supervise --run rsup3 --pid 1 --dry-run
need_out "out $REALSTORE/spawn-records/rsup3-head-2.out (newest .out)"
fixture rsup4 200
run supervise --run rsup4 --pid 1 --dry-run
need_out "out none (transcript-only)"
verdict "supervise: the .out comes from the record's head-successor, else the newest <run>-head-*.out, else none"

# The supervisor never opts into the probe on its own: the detached command carries --probe
# only when this caller passed it (owner ruling 2026-09-06).
fixture rsupprobe 200
run supervise --run rsupprobe --pid 1 --dry-run
need_rc 0
need_out "would detach"
if grep -qE -- '--probe( |$)' "$WORK/both"; then why="$why; the detached command carries --probe with no flag given"; fi
run supervise --run rsupprobe --pid 1 --probe --dry-run
need_rc 0
grep -qE -- '--probe( |$)' "$WORK/both" || why="$why; --probe was not forwarded to the detached supervisor"
verdict "supervise: --probe reaches the detached supervisor only when the caller passes it (control: the same command without the flag carries none)"

# ------------------------------------------------------------------------ heartbeat -------
fixture rhb 200
run heartbeat --run rhb --minutes 0.02
need_rc 0
need_out "heartbeat: rhb · 0.02 min · the cache is refreshed by this re-invocation; re-arm if still idle"
need_eq "$(mk count "$REC" heartbeat)" "2" "armed then beat"
need_eq "$(mk field "$REC" heartbeat action)" "beat" "the last action"
need_nofile "$STORE/spawn-records/rhb-heartbeat.pid"
verdict "heartbeat: arms, sleeps --minutes (a float), prints the beat line and records armed then beat"

fixture rhb2 200
( "$PY" -B "$H" heartbeat --run rhb2 --minutes 1 --tick-s 0.2 >"$WORK/hb-bg.out" 2>&1 ) &
HBW=$!
sleep 1
run heartbeat --run rhb2 --minutes 1
need_rc 0
need_out "heartbeat: already armed (pid "
need_out " min left)"
need_eq "$(mk field "$REC" heartbeat action)" "already-armed" "already-armed"
run heartbeat --run rhb2 --stop
need_rc 0
need_file "$STORE/spawn-records/rhb2-heartbeat.stop"
wait "$HBW"
need_eq "$(cat "$WORK/hb-bg.out")" "" "the stopped timer prints nothing"
need_eq "$(mk field "$REC" heartbeat action)" "stopped" "the timer's stopped event"
need_nofile "$STORE/spawn-records/rhb2-heartbeat.pid"
verdict "heartbeat: a second arming is refused while one is alive; --stop ends the timer quietly"

fixture rhb3 200
sleep 1 &
SP=$!
run heartbeat --run rhb3 --minutes 1 --parent-pid "$SP" --tick-s 0.2
need_rc 0
need_eq "$(cat "$WORK/out")" "" "an orphaned timer prints nothing"
need_eq "$(mk field "$REC" heartbeat action)" "orphaned" "orphaned"
wait "$SP"
verdict "heartbeat: the timer ends quietly (action orphaned) when its parent is gone"

# ------------------------------------------------------------------ waste-table (D36) ------
# Two boundaries (the second without `rewrites`), three gates (the first carrying the
# orientation figure), one lane closed `limit` and one closed `completed`. The expected row
# count is arithmetic, not a memory: 5 waste fields × 2 boundaries + 2 billed lines + 1 run
# total + 3 context rows + 1 orientation row + 1 lost-lane row = 18.
fixture rwaste 200
mk append "$REC" '{"event":"gate","item":"one","context":100000,"percent":10,"band":0,"metered":true,"orientation_tokens":40000}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"L1","exit_class":"limit","total_cost_usd":2.5}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"L2","exit_class":"completed","total_cost_usd":1.0}' >/dev/null
# The billed line is substituted by printf: inside double quotes its `$14.49` would expand to
# nothing and the payload would be written wrong without an error (the shell rule).
B1=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":9.5,"denials":3,"over_cap_reports":1,"respawn_cost_usd":5.0,"rewrites":3}' "$METER")
mk append "$REC" "$B1" >/dev/null
mk append "$REC" '{"event":"gate","item":"two","context":140000,"percent":14,"band":0,"metered":true}' >/dev/null
B2=$(printf '{"event":"phase-boundary","from":"2","to":"3","meter":"%s","idle_min":0.0,"denials":0,"over_cap_reports":0,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$B2" >/dev/null
mk append "$REC" '{"event":"gate","item":"three","context":300000,"percent":30,"band":0,"metered":true}' >/dev/null
WT="$WORK/rwaste-table.md"
run waste-table --run rwaste --out "$WT"
need_rc 0
need_out "waste-table: 18 rows from 2 boundaries, 3 gates, 2 lanes"
need_eq "$(grep -c . "$WORK/out")" "1" "stdout lines"
need_file "$WT"
need_eq "$(mk rows "$WT" "Waste table")" "18" "rendered rows"
need_eq "$(grep -c 'rewrites after a lapsed cache · 2 → 3.*| field absent |' "$WT")" "1" "the absent rewrites field"
need_eq "$(grep -c 'orientation cost · head sid-rwaste | 40,000 tokens · gate.orientation_tokens' "$WT")" "1" "the orientation row"
need_eq "$(grep -c 'Kinds are mechanical' "$WT")" "1" "the legend"
need_eq "$(grep -c 'lost lane · L1 · exit class limit | \$2.50 · lane-closed.total_cost_usd' "$WT")" "1" "the lost lane"
need_eq "$(grep -c 'lost lane · L2' "$WT")" "0" "a completed lane is not a lost lane"
need_eq "$(grep -c 'no waste found' "$WT")" "0" "no zero-findings row when a figure is positive"
need_eq "$(grep -c 'run total (shown sum) | \$19.62 = \$19.62' "$WT")" "1" "the run total as a shown sum"
need_eq "$(grep -c 'context · item two at .* | +40,000 tokens · gate context 100,000 → 140,000' "$WT")" "1" "context per item as a gate delta"
verdict "waste-table: 18 rows from the record alone — a row per waste field per boundary, the billed lines with the run total, the gate deltas, the orientation figure and the lost lane"

run waste-table --run rwaste
need_rc 0
need_file "$REALSTORE/spawn-records/rwaste-waste-table.md"
WTD="$WORK/rwaste-dry.md"
run waste-table --run rwaste --out "$WTD" --dry-run
need_rc 0
need_out "dry run"
need_out "18 rows from 2 boundaries"
need_nofile "$WTD"
verdict "waste-table: the default path is <store>/spawn-records/<run>-waste-table.md; --dry-run prints the counts and writes nothing"

# The zero-findings control, and a gate series with one gate (no consecutive pair to difference).
fixture rwaste2 200
mk append "$REC" '{"event":"gate","item":"one","context":100000,"percent":10,"band":0,"metered":true}' >/dev/null
WT2="$WORK/rwaste2-table.md"
run waste-table --run rwaste2 --out "$WT2"
need_rc 0
need_out "0 boundaries, 1 gates, 0 lanes"
need_eq "$(mk rows "$WT2" "Waste table")" "4" "rendered rows"
need_eq "$(grep -c 'no waste found' "$WT2")" "1" "the zero-findings row"
need_eq "$(grep -c 'no phase-boundary events' "$WT2")" "2" "the header line and the row"
need_eq "$(grep -c 'one gate event only' "$WT2")" "1" "one gate: no pair to difference"
need_eq "$(grep -c 'field absent' "$WT2")" "1" "the orientation field is absent, not zero"
verdict "waste-table: no boundary events still renders the gate, orientation and lane rows, says 'no phase-boundary events' and ends with the zero-findings row naming what was searched"

# A boundary carrying no waste field at all: five `field absent` rows, never five zeroes.
fixture rwaste3 200
mk append "$REC" '{"event":"phase-boundary","from":"1","to":"2"}' >/dev/null
WT3="$WORK/rwaste3-table.md"
run waste-table --run rwaste3 --out "$WT3"
need_rc 0
need_eq "$(grep -c '| field absent |' "$WT3")" "6" "five waste fields and the billed line"
need_eq "$(grep -c '0 min' "$WT3")" "0" "a missing field never reads as a measured zero"
need_eq "$(grep -c 'no waste found' "$WT3")" "1" "zero findings when every field is absent"
need_eq "$(grep -c 'no boundary billed line carried a .session' "$WT3")" "1" "the total says so rather than summing to zero"
rm -f "$STORE/spawn-records/rwaste9.jsonl"
run waste-table --run rwaste9
need_rc 2
need_out "PROBE FAILED"
need_lines
need_nofile "$REALSTORE/spawn-records/rwaste9-waste-table.md"
verdict "waste-table: a boundary lacking every field renders 'field absent' and no zero; no record is a premise failure (exit 2) that writes nothing"

# ----------------------------------------------------------- extract-transcript (D36) ------
mk xscript sid-extract >/dev/null
EX="$WORK/extract"
run extract-transcript --session sid-extract --out "$EX"
need_rc 0
need_eq "$(grep -c . "$WORK/out")" "1" "stdout lines"
need_out "2 turns (1 human, 1 assistant) of 7 records"
need_eq "$(mk json "$EX/counts.json" session)" "sid-extract" "session"
need_eq "$(mk json "$EX/counts.json" records)" "7" "records"
need_eq "$(mk json "$EX/counts.json" human_turns)" "1" "human turns"
need_eq "$(mk json "$EX/counts.json" assistant_turns)" "1" "assistant turns"
need_eq "$(mk json "$EX/counts.json" extracted)" "2" "extracted"
need_eq "$(mk json "$EX/counts.json" excluded.tool_result)" "1" "tool results excluded"
need_eq "$(mk json "$EX/counts.json" excluded.meta)" "1" "isMeta injections excluded"
need_eq "$(mk json "$EX/counts.json" excluded.notification)" "1" "harness injections excluded"
need_eq "$(mk json "$EX/counts.json" excluded.unparseable)" "1" "the torn line is counted, not fatal"
need_eq "$(grep -c '^## turn 1 · human · 2026-09-05T20:00:00Z' "$EX/turns.md")" "1" "turn 1"
need_eq "$(grep -c '^## turn 2 · assistant · 2026-09-05T20:00:10Z' "$EX/turns.md")" "1" "turn 2"
need_eq "$(grep -c 'the assistant answers in prose' "$EX/turns.md")" "1" "positive control: the assistant prose is there"
need_eq "$(grep -c 'tool output text' "$EX/turns.md")" "0" "the tool result is out"
need_eq "$(grep -c 'Base directory for this skill' "$EX/turns.md")" "0" "the Skill-tool injection is out"
need_eq "$(grep -c 'system-reminder' "$EX/turns.md")" "0" "the harness injection is out"
verdict "extract-transcript: the human turn and the assistant prose are extracted in order; the tool result, the isMeta injection and the harness injection are counted out and a torn line is not fatal"

ALT="$WORK/altprojects"
mk xscript sid-alt "$ALT" >/dev/null
run extract-transcript --session sid-alt --out "$WORK/alt" --projects-root "$ALT"
need_rc 0
need_out "2 turns (1 human, 1 assistant)"
run extract-transcript --session sid-nothere --out "$WORK/none"
need_rc 2
need_out "PROBE FAILED"
need_lines
need_nofile "$WORK/none/turns.md"
mk metascript sid-onlymeta >/dev/null
run extract-transcript --session sid-onlymeta --out "$WORK/onlymeta"
need_rc 0
need_out "0 turns (0 human, 0 assistant) of 3 records"
need_eq "$(mk json "$WORK/onlymeta/counts.json" excluded.meta)" "2" "two isMeta records"
need_eq "$(mk json "$WORK/onlymeta/counts.json" excluded.notification)" "1" "one harness injection"
need_eq "$(mk json "$WORK/onlymeta/counts.json" extracted)" "0" "nothing to extract"
verdict "extract-transcript: --projects-root finds a transcript elsewhere; a missing transcript is a premise failure (exit 2); a transcript of injections only extracts nothing and still exits 0"

# The two harness shapes: a resume replay sent as one user record, and the synthetic stop
# record. Both legs run against the same extraction, so each carries the other's counts.
mk replayscript sid-replay >/dev/null
RP="$WORK/replay"
run extract-transcript --session sid-replay --out "$RP"
need_rc 0
need_eq "$(grep -c . "$WORK/out")" "1" "stdout lines"
need_out "5 turns (3 human, 2 assistant) of 7 records"
need_out "replay 3"
need_eq "$(mk json "$RP/counts.json" excluded.replay)" "3" "replays counted"
need_eq "$(mk json "$RP/counts.json" human_turns)" "3" "the plain turn, the replay's own message and the quoted prompt"
need_eq "$(grep -c 'what do you make of it' "$RP/turns.md")" "1" "residue: a typed prompt opening with a quoted conversation keeps the owner's trailing words"
need_eq "$(grep -c "the owner's real message" "$RP/turns.md")" "1" "the trailing owner message is kept"
need_eq "$(grep -c 'an earlier replayed turn' "$RP/turns.md")" "0" "the replayed turns are out"
need_eq "$(grep -c 'an earlier replayed answer' "$RP/turns.md")" "0" "the replayed answers are out"
need_eq "$(grep -c 'a replay with no human marker' "$RP/turns.md")" "0" "a replay with no owner message is dropped whole"
need_eq "$(grep -c 'the plain human turn' "$RP/turns.md")" "1" "positive control: an ordinary human turn is untouched"
need_eq "$(grep -c 'were trimmed to the text after their last' "$RP/turns.md")" "1" "the header states the trimming"
verdict "extract-transcript: a resume replay keeps only its trailing owner message, one carrying no owner message is dropped, and both are counted under excluded.replay"

need_eq "$(mk json "$RP/counts.json" excluded.synthetic)" "1" "the synthetic record is counted out"
need_eq "$(mk json "$RP/counts.json" assistant_turns)" "2" "the prose turn and the control record"
need_eq "$(grep -c 'No response requested.' "$RP/turns.md")" "1" "positive control: the same words from a real model are still a turn"
need_eq "$(grep -c 'the assistant answers in prose' "$RP/turns.md")" "1" "positive control: the assistant prose is there"
need_out "synthetic 1"
verdict "extract-transcript: an assistant record whose model opens '<synthetic' is skipped and counted, while the same stop words from a real model stay a turn (the skip keys on the model field)"

# ------------------------------------------------- the reflect skill's proposed amendment ---
# The diff is a build-time artefact: while it is staged the leg dry-runs it against a copy of
# the skill file (never the file itself), and once the head has applied it the same leg reads
# the paragraph in the installed file. Point REFLECT_DIFF at the staged diff until then.
# The reflect skill's directory: beside the target's own skill directory by default, and
# REFLECT_DIR when the target is a staged copy outside the skill tree.
REFLECT_DIR=${REFLECT_DIR:-$SKILL_DIR/../reflect}
REFLECT_SKILL=${REFLECT_SKILL:-$REFLECT_DIR/SKILL.md}
RDIFF=${REFLECT_DIFF:-$SKILL_DIR/reflect-skill.diff}
[ -f "$RDIFF" ] || RDIFF=$(dirname "$SRC")/reflect-skill.diff
PROOT="$WORK/patchroot"
rm -rf "$PROOT"
mkdir -p "$PROOT/.claude/skills/reflect"
if [ -f "$RDIFF" ] && [ -f "$REFLECT_SKILL" ]; then
  command -v patch >/dev/null || why="$why; no patch on PATH: the dry-run legs cannot run"
  cp "$REFLECT_SKILL" "$PROOT/.claude/skills/reflect/SKILL.md"
  RC=0; (cd "$PROOT" && patch -p0 --dry-run < "$RDIFF") >"$WORK/both" 2>&1 || RC=$?
  need_rc 0
  need_out "SKILL.md"
  D1=$(grep -c 'waste-table' "$RDIFF")
  [ "$D1" -ge 1 ] || why="$why; the diff never names waste-table ($D1)"
  D2=$(grep -c 'Hands-off boundaries' "$RDIFF")
  [ "$D2" -ge 1 ] || why="$why; the diff never names the paragraph ($D2)"
  verdict "reflect skill: the staged diff applies to the installed file with patch -p0 --dry-run"
  # The control: the anchored span is cut out of the copy, so the hunk has nothing to match.
  # A one-word edit is not the control, since patch applies with fuzz and would still land it.
  "$PY" -c 'import sys; p = sys.argv[1]; lines = open(p, encoding="utf-8").read().split("\n"); open(p, "w", encoding="utf-8").write("\n".join(lines[:100]) + "\n")' \
        "$PROOT/.claude/skills/reflect/SKILL.md"
  RC=0; (cd "$PROOT" && patch -p0 --dry-run < "$RDIFF") >"$WORK/both" 2>&1 || RC=$?
  [ "$RC" = "0" ] && why="$why; the diff applied to a skill file whose anchored span had gone"
  need_out "hunks failed"
  verdict "reflect skill: the same diff is refused when the span it anchors on has gone from the file (the control for the leg above)"
elif [ -f "$REFLECT_SKILL" ]; then
  P1=0; grep -q 'Hands-off boundaries' "$REFLECT_SKILL" && P1=1
  [ "$P1" = "1" ] || why="$why; no staged diff at $RDIFF and no applied paragraph in $REFLECT_SKILL (pass REFLECT_DIFF=<path>)"
  verdict "reflect skill: the hands-off boundaries paragraph is in the installed file (no staged diff to dry-run)"
  P2=0; grep -q 'never applies to cross runs' "$REFLECT_SKILL" && P2=1
  [ "$P2" = "1" ] || why="$why; positive control: the cross-run sentence is missing from $REFLECT_SKILL"
  verdict "reflect skill: the cross-reflection section is readable (the control for the leg above)"
else
  why="$why; no reflect SKILL.md at $REFLECT_SKILL and no staged diff at $RDIFF"
  verdict "reflect skill: the diff's target is readable"
  why="$why; the control cannot run without the skill file"
  verdict "reflect skill: the control for the leg above"
fi

# ------------------------------------------------------- reflect-inputs (D36, the P4 lane) --
# The blind reflector's whole input set in one directory: the extraction, the waste table and a
# copy of the run record with the spawner's control pre-registration (an observation whose phase
# starts `controls`) dropped and the brief-and-plant keys stripped. The source record carries
# both, which is this leg's positive control.
fixture rrefl 200
mk xscript sid-rrefl >/dev/null
mk waste "$REC" rrefl "$WORK/no-such-report.md" >/dev/null
mk append "$REC" '{"event":"observation","phase":"controls-B1","what":"pre-registered control","note":"the case planted for the lane"}' >/dev/null
mk append "$REC" '{"event":"observation","phase":"reflection-b1","what":"a phase the copy keeps"}' >/dev/null
mk append "$REC" '{"event":"lane-open","lane":"B1","class":"builder","brief":"the brief text","brief_copy":"/tmp/brief-copy.md","controls_checked":true,"plant":"the case planted for the lane"}' >/dev/null
RD="$WORK/reflect-in"
run reflect-inputs --run rrefl --session sid-rrefl --out "$RD"
need_rc 0
need_eq "$(grep -c . "$WORK/out")" "1" "stdout lines"
need_out "reflect-inputs: 2 turns (1 human, 1 assistant) of 7 records"
need_out "1 controls observation(s) dropped"
need_file "$RD/turns.md"
need_file "$RD/counts.json"
need_file "$RD/waste-table.md"
need_file "$RD/record-filtered.jsonl"
need_eq "$(grep -c '^# Waste table · run rrefl' "$RD/waste-table.md")" "1" "the waste table's own title"
need_eq "$(mk json "$RD/counts.json" extracted)" "2" "the extraction's own counts"
need_eq "$(grep -c 'controls_checked' "$RD/record-filtered.jsonl")" "0" "controls_checked keys in the copy"
need_eq "$(grep -c 'controls-B1' "$RD/record-filtered.jsonl")" "0" "controls-phase observations in the copy"
need_eq "$(grep -c 'controls_checked' "$REC")" "1" "positive control: the source record carries the key"
need_eq "$(grep -c 'controls-B1' "$REC")" "1" "positive control: the source record carries the observation"
need_eq "$(grep -c 'reflection-b1' "$RD/record-filtered.jsonl")" "1" "an observation of another phase is kept"
need_eq "$(grep -c 'the brief text' "$RD/record-filtered.jsonl")" "0" "the brief is stripped"
need_eq "$(grep -c 'brief-copy.md' "$RD/record-filtered.jsonl")" "0" "the brief copy is stripped"
need_eq "$(grep -c 'the case planted for the lane' "$RD/record-filtered.jsonl")" "0" "the plant is stripped"
need_eq "$(grep -c 'the case planted for the lane' "$REC")" "2" "positive control: the source record carries both"
need_eq "$(grep -c '"lane": "B1"' "$RD/record-filtered.jsonl")" "1" "positive control: the stripped event itself is kept"
need_eq "$(mk lines "$RD/record-filtered.jsonl")" "7" "events kept (8 in the record, one controls observation dropped)"
need_eq "$(mk lines "$REC")" "9" "the record after its reflect-inputs event"
need_eq "$(grep -c 'reflect-inputs' "$RD/record-filtered.jsonl")" "0" "the copy is written before the event that records it"
need_eq "$(mk field "$REC" reflect-inputs out)" "$(real "$RD")" "the event names the directory"
need_eq "$(mk field "$REC" reflect-inputs session)" "sid-rrefl" "the event names the session"
verdict "reflect-inputs: the four files land in the granted directory, the filtered copy holds no controls-phase observation and no controls_checked, brief or plant key, and every other event survives"

run reflect-inputs --run rrefl --session sid-rrefl --out "$STORE/spawn-records/blind"
need_rc 2
need_out "is inside the run store"
need_lines
need_nofile "$REALSTORE/spawn-records/blind/turns.md"
run reflect-inputs --run rrefl --session sid-rrefl --out "$PROJECTS/blind"
need_rc 2
need_out "is inside the projects root"
need_lines
need_nofile "$PROJECTS/blind/turns.md"
need_eq "$(mk count "$REC" reflect-inputs)" "1" "no event from either refusal (the control: the granted directory above recorded one)"
verdict "reflect-inputs: an --out inside the run store or the projects root is a premise failure (exit 2) that writes nothing and records nothing"

DRD="$WORK/reflect-dry"
run reflect-inputs --run rrefl --session sid-rrefl --out "$DRD" --dry-run
need_rc 0
need_out "reflect-inputs: dry run"
need_out "would write turns.md, counts.json, waste-table.md and record-filtered.jsonl"
need_out "2 turns (1 human, 1 assistant) of 7 records"
need_nofile "$DRD/turns.md"
need_nofile "$DRD/record-filtered.jsonl"
need_eq "$(mk count "$REC" reflect-inputs)" "1" "no second event from the dry run (the control: the write above recorded one)"
verdict "reflect-inputs --dry-run: the same counts, no file written and no event recorded"

# ------------------------------------------- the console window (IDEAS №139 A2) ------------
# The viewer key in the grants file, the opener, who opens it, and the failure modes. Every leg
# runs through the recording stub set up above (AIMYTH_VIEWER_CMD), so no window is ever opened
# and the assertions are on the stub's argv, the command file and the primitive's own lines.
PYEXE=$("$PY" -c 'import sys; sys.stdout.write(sys.executable)')
pmode() { "$PY" -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[-3:])' "$1"; }
viewer_last() { tail -1 "$VIEWER_ARGV"; }

VHO="$WORK/handoffs/vw-handoff.md"; mk handoff "$VHO" >/dev/null
REC="$STORE/spawn-records/rvw.jsonl"; rm -f "$REC"
GF="$STORE/spawn-records/rvw-grants.json"; rm -f "$GF"
viewer_use vkey
run run-open --run rvw --session sid-vw --head "fixture head" --regime single --regime-src owner \
    --handoff "$VHO" --detail "the viewer key" --pid 1
need_rc 0
need_eq "$(vval "$GF")" "terminal" "run-open's default with no file at all"
need_eq "$(mk field "$REC" run-open viewer)" "terminal" "the run-open event"
need_eq "$(mk field "$REC" run-open viewer_src)" "default (no grants file)" "the source"
need_out "viewer terminal (default (no grants file))"
run grants --run rvw --viewer none
need_rc 0
need_eq "$(vval "$GF")" "none" "grants --viewer none rewrites the key"
need_eq "$(mk field "$REC" grants viewer_src)" "arg" "the flag is the source"
run grants --run rvw
need_rc 0
need_eq "$(vval "$GF")" "none" "positive control: a file WITH the key carries it forward"
need_eq "$(mk field "$REC" grants viewer_src)" "grants" "positive control: the source reads grants"
"$PY" -c 'import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8")); d.pop("viewer", None)
json.dump(d, open(p, "w", encoding="utf-8"))' "$GF"
need_eq "$(vval "$GF")" "None" "the planted case: the key is gone from the file"
run grants --run rvw
need_rc 0
need_eq "$(vval "$GF")" "terminal" "a file without the key reads terminal"
need_eq "$(mk field "$REC" grants viewer_src)" "default (key absent)" "the source names the absent key"
verdict "the viewer key: a grants file WITHOUT it reads terminal, source 'default (key absent)', and no file at all reads 'default (no grants file)' (control: a file with the key reads 'grants')"

REC="$STORE/spawn-records/rvwn.jsonl"; rm -f "$REC"
GF="$STORE/spawn-records/rvwn-grants.json"; rm -f "$GF"
viewer_use vflag
run run-open --run rvwn --session sid-vwn --head "fixture head" --regime single --regime-src owner \
    --handoff "$VHO" --detail "the flag" --pid 1 --viewer none
need_rc 0
need_eq "$(vval "$GF")" "none" "run-open --viewer none"
need_eq "$(mk field "$REC" run-open viewer)" "none" "the run-open event"
need_eq "$(mk field "$REC" run-open viewer_src)" "arg" "the source"
need_out "viewer: none (grants) · no window"
need_no_viewer
need_nofile "$(console_cmd rvwn)"
verdict "the viewer key: run-open --viewer none writes none, records viewer_src arg, opens nothing and writes no command file"

run grants --run rvwn --grant "$WORK/handoffs"
need_rc 0
need_eq "$(vval "$GF")" "none" "a rebuild with --grant carries none forward"
need_eq "$(mk field "$REC" grants viewer_src)" "grants" "carried from the file"
GRANTED=$("$PY" -c 'import json, sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))["grants"]))' "$GF")
run run-resume --run rvwn --session sid-vwn2 --head "fixture head" --detail "flag-less" --pid 1
need_rc 0
need_eq "$(vval "$GF")" "none" "a flag-less run-resume keeps the file"
need_eq "$(mk field "$REC" run-resume viewer)" "none" "the run-resume event"
need_eq "$("$PY" -c 'import json, sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))["grants"]))' "$GF")" \
        "$GRANTED" "the kept file's paths are unchanged (both spellings kept)"
run run-resume --run rvwn --session sid-vwn3 --head "fixture head" --detail "the flag alone" --pid 1 --viewer terminal
need_rc 0
need_eq "$(vval "$GF")" "terminal" "--viewer alone rewrites, as --on-limit does"
need_eq "$(mk field "$REC" run-resume viewer_src)" "arg" "the source"
verdict "the viewer key: grants --grant and a flag-less run-resume carry it forward untouched, while --viewer alone rewrites it"

REC="$STORE/spawn-records/rvwo.jsonl"; rm -f "$REC"
CF=$(console_cmd rvwo); rm -f "$CF"
viewer_use vopen
run run-open --run rvwo --session sid-vwo --head "fixture head" --regime single --regime-src owner \
    --handoff "$VHO" --detail "the window" --pid 1
need_rc 0
need_eq "$(viewer_calls)" "1" "the opener was called with one argument"
need_eq "$(viewer_last)" "$CF" "the command file is the LAST argument"
need_out "viewer: Terminal window on $CF"
need_file "$CF"
need_eq "$(pmode "$CF")" "755" "the command file's mode"
need_eq "$(sed -n 1p "$CF")" "#!/bin/sh" "the command file's first line"
LINE2=$(sed -n 2p "$CF")
case $LINE2 in
  "exec "*" -B "*"handsoff.py watch --run rvwo") : ;;
  *) why="$why; the exec line reads '$LINE2'" ;;
esac
case $LINE2 in *"$PYEXE"*) : ;; *) why="$why; the exec line does not name this interpreter" ;; esac
verdict "the opener: run-open writes <run>-console.command (0755, exec <this interpreter> -B <this script> watch --run R) and calls the opener with that path as its last argument"

CF=$(console_cmd rvwst)
# The stale content is assembled from parts so that this file's own source carries no absolute
# path beside a write verb (the source scan below), and no owner path anywhere.
STALE_EXE="/nowhere""/python"
STALE_SRC="/nowhere""/handsoff.py"
printf '#!/bin/sh\nexec %s -B %s watch --run rvwst\n' "$STALE_EXE" "$STALE_SRC" > "$CF"
chmod 600 "$CF"
grep -q 'nowhere' "$CF" || why="$why; positive control: the planted stale line is not in the file"
REC="$STORE/spawn-records/rvwst.jsonl"; rm -f "$REC"
viewer_use vstale
run run-open --run rvwst --session sid-vwst --head "fixture head" --regime single --regime-src owner \
    --handoff "$VHO" --detail "a stale command file" --pid 1
need_rc 0
if grep -q 'nowhere' "$CF"; then why="$why; the stale command file was not rewritten"; fi
need_eq "$(pmode "$CF")" "755" "the rewritten file's mode"
need_eq "$(sed -n 2p "$CF" | sed 's/.* watch --run //')" "rvwst" "the rewritten exec line"
verdict "the opener: a stale <run>-console.command is rewritten and re-moded 0755 (control: the planted stale line is there before the run)"

fixture rvwsuc 200
viewer_use vsuc
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwsuc --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: Terminal window on"
need_viewer_arg "$(console_cmd rvwsuc)"
need_file "$(console_cmd rvwsuc)"
sleep 2   # the detached starter aborts on the missing harness; let it go before the next leg
verdict "successor: with no console alive for the run, one window is opened on it and the primitive still exits 0"

# The grace window (2026-09-08, the run-20260908-n140 launch): run-open and successor a second
# apart opened two windows, since Terminal had not yet started the first console's process when
# successor probed the table. A console opened within CONSOLE_START_GRACE_S counts as alive,
# keyed on the command file's mtime: the opener stamps it at every open and pushes it into the
# past on a failed open. Legs: a fresh stamp blocks the second window; an old stamp does not; a
# failed open leaves no fresh stamp; the helper itself on a fresh, an old and a missing file.
fixture rvwg1 200
CF=$(console_cmd rvwg1)
printf '#!/bin/sh\n' > "$CF"; chmod 755 "$CF"    # a command file stamped now: a console starting
viewer_use vg1
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwg1 --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "may still be starting · no second window"
need_no_viewer
sleep 2
verdict "successor: a console opened within the grace window (a fresh command-file stamp, no process yet) is not doubled — no opener call, the primitive still exits 0"

fixture rvwg2 200
CF=$(console_cmd rvwg2)
printf '#!/bin/sh\n' > "$CF"; chmod 755 "$CF"
"$PY" -c 'import os, sys, time; t = time.time() - 120; os.utime(sys.argv[1], (t, t))' "$CF"
viewer_use vg2
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwg2 --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: Terminal window on"
need_viewer_arg "$CF"
AGE=$("$PY" -c 'import os, sys, time; print(int(time.time() - os.path.getmtime(sys.argv[1])))' "$CF")
[ "$AGE" -lt 15 ] || why="$why; the opener did not re-stamp the command file (age ${AGE}s)"
sleep 2
verdict "successor: a command file stamped two minutes ago does not count as a starting console — the window is opened and the file is stamped afresh (the control for the grace leg)"

fixture rvwg3 200
CF=$(console_cmd rvwg3); rm -f "$CF"
viewer_use vg3
RUNENV="PATH=$WORK/psnone:$PATH AIMYTH_VIEWER_CMD=$WORK/bin/viewer-fail.sh"
run successor --run rvwg3 --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: no Terminal window"
need_eq "$(viewer_calls)" "1" "positive control: the failing stub was reached"
AGE=$("$PY" -c 'import os, sys, time; print(int(time.time() - os.path.getmtime(sys.argv[1])))' "$CF")
[ "$AGE" -ge 15 ] || why="$why; a failed open left a fresh stamp (age ${AGE}s), so it would read as a console starting"
sleep 2
verdict "a failed open pushes the command file's stamp past the grace window, so the failure never reads as a console still starting"

CF=$(console_cmd rvwg4)
printf '#!/bin/sh\n' > "$CF"
env LLM_WIKI_STORE="$STORE" "$PY" - "$H" rvwg4 "$CF" <<'CSTART' > "$WORK/cs.txt"
import importlib.util, os, sys, time
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
run, path = sys.argv[2], sys.argv[3]
fresh = mod.console_starting(run)
t = time.time() - 120; os.utime(path, (t, t))
old = mod.console_starting(run)
os.remove(path)
gone = mod.console_starting(run)
print("fresh" if fresh is not None and 0 <= fresh < mod.CONSOLE_START_GRACE_S else "fresh=%r" % fresh,
      old, gone)
CSTART
need_eq "$(cat "$WORK/cs.txt")" "fresh None None" "console_starting: a fresh stamp is an age under the grace window; an old stamp and a missing file are None"
verdict "console_starting: keyed on the command file's stamp alone — fresh counts, old and missing make no claim"

fixture rvwsuc2 200
plant_console rvwsuc2 watch.py
viewer_use vsuc2
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwsuc2 --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "a console is already alive (pid $PLANTED)"
need_no_viewer
need_nofile "$(console_cmd rvwsuc2)"
sleep 2
kill_console
verdict "successor: a console already alive for the run is never doubled — the pid is named, nothing is opened, no command file is written"

fixture rvwrh 200
mk append "$REC" '{"event":"head-successor","session_id":"sid-rvwrh","pid":1,"budget":5.0}' >/dev/null
viewer_use vrh
run resume-head --run rvwrh --harness-bin "$WORK/bin/no-such-harness" --budget-usd 5 --tick-s 1
need_rc 0
need_out "viewer: Terminal window on"
need_viewer_arg "$(console_cmd rvwrh)"
sleep 2   # the detached half aborts: the fixture session has no transcript to size
verdict "resume-head: with no console alive for the run, one window is opened on it and the primitive still exits 0"

fixture rvwrh2 200
mk append "$REC" '{"event":"head-successor","session_id":"sid-rvwrh2","pid":1,"budget":5.0}' >/dev/null
plant_console rvwrh2 handsoff.py
viewer_use vrh2
run resume-head --run rvwrh2 --harness-bin "$WORK/bin/no-such-harness" --budget-usd 5 --tick-s 1
need_rc 0
need_out "a console is already alive (pid $PLANTED)"
need_no_viewer
sleep 2
kill_console
verdict "resume-head: a console already alive for the run is never doubled (the handsoff.py spelling of the marker)"

viewer_use vspell
plant_console rvwsp watch.py
"$PY" - "$H" rvwsp <<'CALIVE' > "$WORK/ca-watch.txt"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print(len(mod.console_alive(sys.argv[2])), len(mod.console_alive("rvwsp-nobody")))
CALIVE
need_eq "$(cat "$WORK/ca-watch.txt")" "1 0" "the watch.py spelling, with the negative control"
kill_console
plant_console rvwsp handsoff.py
"$PY" - "$H" rvwsp <<'CALIVE2' > "$WORK/ca-handsoff.txt"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print(len(mod.console_alive(sys.argv[2])), len(mod.console_alive("rvwsp-nobody")))
CALIVE2
need_eq "$(cat "$WORK/ca-handsoff.txt")" "1 0" "the handsoff.py spelling, with the negative control"
kill_console
sleep 1
"$PY" - "$H" rvwsp <<'CALIVE3' > "$WORK/ca-none.txt"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print(len(mod.console_alive(sys.argv[2])))
CALIVE3
need_eq "$(cat "$WORK/ca-none.txt")" "0" "nothing alive once the planted console is gone"
verdict "console_alive: both spellings of the marker are found — 'watch.py --run R' as the console RUNS and 'handsoff.py watch --run R' as it is launched — and a run with no console reads 0 (the negative control on each run)"

fixture rvwnone 200
run grants --run rvwnone --viewer none
need_rc 0
viewer_use vnone
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwnone --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: none (grants)"
need_no_viewer
mk append "$REC" '{"event":"head-successor","session_id":"sid-rvwnone","pid":1,"budget":5.0}' >/dev/null
run resume-head --run rvwnone --harness-bin "$WORK/bin/no-such-harness" --budget-usd 5 --tick-s 1
need_rc 0
need_out "viewer: none (grants)"
need_no_viewer
need_nofile "$(console_cmd rvwnone)"
sleep 2
verdict "viewer none: run-open (above), successor and resume-head each open nothing and write no command file, and each still exits 0"

fixture rvwfail 200
viewer_use vfail
RUNENV="PATH=$WORK/psnone:$PATH AIMYTH_VIEWER_CMD=$WORK/bin/viewer-fail.sh"
run successor --run rvwfail --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: no Terminal window"
need_out "exit 1"
need_out "run by hand: python3 -B"
need_out "watch --run rvwfail"
need_eq "$(viewer_calls)" "1" "positive control: the failing stub was reached"
sleep 2
verdict "the failing opener: a stub that exits 1 gives one stderr line naming the reason and the by-hand command, and the primitive still exits 0"

fixture rvwpath 200
viewer_use vpath
RC=0
env PATH="$WORK/nopath" AIMYTH_VIEWER_CMD= AIMYTH_VIEWER_ARGV="$VIEWER_ARGV" \
    LLM_WIKI_STORE="$STORE" AIMYTH_PROJECTS_DIR="$PROJECTS" AIMYTH_STATE_DIR="$STATE" \
    CLAUDE_PROJECT_DIR="$VAULT" "$PYEXE" -B "$H" successor --run rvwpath --meter-line "$METER" \
    --harness-bin "$WORK/bin/no-such-harness" --wait-s 1 --max-wait-s 5 --tick-s 1 \
    >"$WORK/out" 2>"$WORK/err" || RC=$?
cat "$WORK/out" "$WORK/err" >"$WORK/both"
need_rc 0
need_out "viewer: no Terminal window"
need_out "osascript not on PATH"
need_out "open not on PATH"
need_out "run by hand: python3 -B"
need_no_viewer
sleep 2
# the positive control on the same premise: with the stub back, the same command opens one
fixture rvwpath2 200
viewer_use vpath2
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwpath2 --meter-line "$METER" --harness-bin "$WORK/bin/no-such-harness" \
    --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "viewer: Terminal window on"
sleep 2
verdict "no osascript and no open on PATH: both are named in one stderr line with the by-hand command and the primitive exits 0 (control: the same call with the opener in place opens one)"

fixture rvwdry 200
CF=$(console_cmd rvwdry); rm -f "$CF"
viewer_use vdry
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rvwdry --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "viewer: dry run"
need_out "would run:"
need_out "$CF"
need_nofile "$CF"
need_no_viewer
run resume-head --run rvwdry --dry-run --harness-bin "$WORK/bin/stubhead" --meter-line "$METER"
need_rc 0
need_out "viewer: dry run"
need_nofile "$CF"
need_no_viewer
REC="$STORE/spawn-records/rvwdry2.jsonl"; rm -f "$REC"
run run-open --run rvwdry2 --dry-run --session sid-vwdry2 --head "fixture head" --regime single \
    --regime-src owner --handoff "$VHO" --detail "dry" --pid 1
need_rc 0
need_out "viewer: dry run"
need_out "$(console_cmd rvwdry2)"
need_nofile "$(console_cmd rvwdry2)"
need_nofile "$REC"
need_no_viewer
verdict "--dry-run on run-open, successor and resume-head: the opener's command line is printed, nothing is called and no command file is written"

# ------------------------------------------ the seed pid (register entry 2026-09-07) -------
SHO="$WORK/handoffs/vseed-handoff.md"; mk handoff "$SHO" >/dev/null
PACK=$(printf 'Next: the next item\nNeeds: nothing\nDecided: the pid')
REC="$STORE/spawn-records/rseedpid.jsonl"; rm -f "$REC"
viewer_use vseed
run run-open --run rseedpid --session sid-seedpid --head "the launcher" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a seeded record" --pid 93910 \
    --session-kind seed --envelope-usd 200
need_rc 0
need_eq "$(mk field "$REC" run-open pid)" "93910" "the seed's recorded pid"
# No --pid, and every ps row answers `claude`: the parent walk would take THIS shell's pid,
# which is the fault the register entry names. The seed's own recorded pid must win.
RUNENV="PATH=$WORK/psclaude:$PATH"
run handoff --run rseedpid --final --band 80 --inflight "$PACK"
need_rc 0
need_out "handoff: pid 93910 (run-open, seed)"
need_eq "$(mk field "$REC" head-exit pid)" "93910" "the head-exit takes the seed's pid"
need_absent "(parent-walk)"
verdict "handoff --final on a SEEDED record without --pid takes the seed run-open's pid and says so ('pid 93910 (run-open, seed)'), never the parent walk to the calling session"

REC="$STORE/spawn-records/rheadpid.jsonl"; rm -f "$REC"
run run-open --run rheadpid --session sid-headpid --head "a head" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a head record" --pid 55555 --envelope-usd 200
need_rc 0
need_eq "$(mk field "$REC" run-open session_kind)" "head" "not a seed"
RUNENV="PATH=$WORK/psclaude:$PATH"
run handoff --run rheadpid --final --band 80 --inflight "$PACK"
need_rc 0
need_out "(parent-walk)"
need_absent "(run-open, seed)"
if [ "$(mk field "$REC" head-exit pid)" = "55555" ]; then
  why="$why; the head record's head-exit took the run-open pid instead of the walk"
fi
REC="$STORE/spawn-records/rheadpid2.jsonl"; rm -f "$REC"
run run-open --run rheadpid2 --session sid-headpid2 --head "a head" --regime multi \
    --regime-src head --handoff "$SHO" --detail "no ancestor" --pid 55555 --envelope-usd 200
RUNENV="PATH=$WORK/psnone:$PATH"
run handoff --run rheadpid2 --final --band 80 --inflight "$PACK"
need_rc 0
need_out "handoff: pid none (none)"
need_eq "$(mk field "$REC" head-exit pid)" "<no key pid>" "no pid on the head-exit"
verdict "handoff --final on a HEAD record is unchanged: the parent walk still decides (parent-walk under the claude ps stub, none under the empty one), and the run-open pid is never taken"

# The same rule where `successor` writes the FIRST head-exit itself (register entry 2026-09-08):
# the head never wrote one, so the pid on it — and the predecessor pid the starter then waits
# on, which reads that event — came from the parent walk. Under the psclaude stub every ps row
# answers `claude`, so the walk would take THIS shell's pid and the starter would wait on the
# suite instead of the launcher shell: the fault the seed pid closes.
REC="$STORE/spawn-records/rsucseed.jsonl"; rm -f "$REC"
run run-open --run rsucseed --session sid-sucseed --head "the launcher" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a seeded record" --pid 93911 \
    --session-kind seed --envelope-usd 200
need_rc 0
need_eq "$(mk field "$REC" run-open pid)" "93911" "the seed's recorded pid"
RUNENV="PATH=$WORK/psclaude:$PATH"
run successor --run rsucseed --dry-run --budget-usd 5 --meter-line "$METER" \
    --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "successor: pid 93911 (run-open, seed)"
need_absent "(parent-walk)"
need_eq "$(mk field "$REC" head-exit pid)" "<no head-exit event>" "the dry run wrote no head-exit"
# The real run, which appends the head-exit before it detaches its starter. --budget-usd is any
# cap at all (it only keeps the meter out of the leg, as the seed skip already would); the
# harness name does not exist and the three waits are 1/5/1 s, so the detached starter finds
# nothing to start and gives up at once — the pattern the viewer successor legs above use.
RUNENV="PATH=$WORK/psclaude:$PATH"
run successor --run rsucseed --budget-usd 5 --meter-line "$METER" \
    --harness-bin "$WORK/bin/no-such-harness" --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "successor: pid 93911 (run-open, seed)"
need_eq "$(mk field "$REC" head-exit pid)" "$(mk field "$REC" run-open pid)" "the head-exit's pid is the run-open's"
verdict "successor on a SEEDED record without --pid takes the seed run-open's pid for the first head-exit it writes ('successor: pid 93911 (run-open, seed)'), never the parent walk to the calling session"

REC="$STORE/spawn-records/rsuchead.jsonl"; rm -f "$REC"
run run-open --run rsuchead --session sid-suchead --head "a head" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a head record" --pid 55556 --envelope-usd 200
need_rc 0
need_eq "$(mk field "$REC" run-open session_kind)" "head" "not a seed"
RUNENV="PATH=$WORK/psclaude:$PATH"
run successor --run rsuchead --budget-usd 5 --meter-line "$METER" \
    --harness-bin "$WORK/bin/no-such-harness" --wait-s 1 --max-wait-s 5 --tick-s 1
need_rc 0
need_out "(parent-walk)"
need_absent "(run-open, seed)"
XPID=$(mk field "$REC" head-exit pid)
if [ "$XPID" = "$(mk field "$REC" run-open pid)" ]; then
  why="$why; the head record's head-exit took the run-open pid (55556) instead of the walk"
fi
case $XPID in
  ''|*[!0-9]*) why="$why; positive control: the walk recorded no pid on the head-exit ('$XPID')" ;;
esac
verdict "successor on a HEAD record is unchanged: the parent walk decides the first head-exit's pid (a live pid under the claude ps stub, never the run-open's 55556)"

REC="$STORE/spawn-records/rsucarg.jsonl"; rm -f "$REC"
run run-open --run rsucarg --session sid-sucarg --head "the launcher" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a seeded record" --pid 93911 \
    --session-kind seed --envelope-usd 200
need_rc 0
RUNENV="PATH=$WORK/psclaude:$PATH"
run successor --run rsucarg --dry-run --pid 41414 --budget-usd 5 --meter-line "$METER" \
    --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "successor: pid 41414 (arg)"
need_absent "(run-open, seed)"
# A seed run-open that recorded no pid has nothing better to take, so the walk answers as before.
REC="$STORE/spawn-records/rsucnopid.jsonl"; rm -f "$REC"
RUNENV="PATH=$WORK/psnone:$PATH"
run run-open --run rsucnopid --session sid-sucnopid --head "the launcher" --regime multi \
    --regime-src head --handoff "$SHO" --detail "a seed with no pid" --session-kind seed \
    --envelope-usd 200
need_rc 0
need_eq "$(mk field "$REC" run-open session_kind)" "seed" "a seeded record"
need_eq "$(mk field "$REC" run-open pid)" "<no key pid>" "with no pid of its own"
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rsucnopid --dry-run --budget-usd 5 --meter-line "$METER" \
    --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "successor: pid none (none)"
need_absent "(run-open, seed)"
verdict "successor: --pid wins on a seeded record ('pid 41414 (arg)'), and a seed run-open that recorded no pid falls through to the walk ('pid none (none)')"

# --------------------------------------------------------------------- controls ------------
"$PY" - "$H" > "$WORK/shipsafe.txt" <<'SHIPSAFE'
import re, sys
PATTERNS = (("owner path", r"/(?:Users|home)/[A-Za-z0-9._-]+"),
            ("user or store name", r"(?i)\b" + "|\\b".join(w[::-1] for w in ("gnarej", "yrrej", "evirdeno", "563suxen")) + r"\b"),
            ("session id", r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"),
            ("uid", r"\buid=\d+\b"),
            ("run id", r"\brun-20\d{6}[A-Za-z0-9-]*"))
src = open(sys.argv[1], encoding="utf-8").read()
total = 0
for name, pattern in PATTERNS:
    hits = re.findall(pattern, src)
    total += len(hits)
    if hits:
        print("%s: %s" % (name, ", ".join(sorted(set(hits))[:4])))
print("hits %d" % total)
SHIPSAFE
SHIP=$(tail -1 "$WORK/shipsafe.txt")
need_eq "$SHIP" "hits 0" "ship-safe sweep of handsoff.py"
# Assembled from parts, so this file's own source carries no owner path, session id or run id.
{ printf 'HOME_DIR = "%s%s"\n' "/Users" "/example-owner/vault"
  printf 'SESSION = "%s-1111-2222-3333-444455556666"\n' "7c77ff5b"
  printf 'RUN = "%s%s"\n' "run-2026" "0101-example"; } > "$WORK/planted-owner.py"
SHIPCTRL=$("$PY" - "$WORK/planted-owner.py" <<'SHIPSAFE2' | tail -1
import re, sys
PATTERNS = (("owner path", r"/(?:Users|home)/[A-Za-z0-9._-]+"),
            ("user or store name", r"(?i)\b" + "|\\b".join(w[::-1] for w in ("gnarej", "yrrej", "evirdeno", "563suxen")) + r"\b"),
            ("session id", r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"),
            ("uid", r"\buid=\d+\b"),
            ("run id", r"\brun-20\d{6}[A-Za-z0-9-]*"))
src = open(sys.argv[1], encoding="utf-8").read()
total = sum(len(re.findall(p, src)) for _, p in PATTERNS)
print("hits %d" % total)
SHIPSAFE2
)
need_eq "$SHIPCTRL" "hits 3" "positive control: the planted file's three literals"
verdict "ship-safe: no owner path, user or store name, session id, uid or run id is a literal in handsoff.py ($SHIP; control: 3 planted hits)"

NEG=$(grep -c 'tests the wrong' "$H")
need_eq "$NEG" "0" "negative control: the lifted refusal's phrase"
POS=$(grep -c 'unmetered-loop' "$H")
[ "$POS" -ge 1 ] || why="$why; positive control: 'unmetered-loop' count $POS"
verdict "controls: 'tests the wrong' absent from handsoff.py ($NEG); 'unmetered-loop' present ($POS)"

fixture rclose2 200
printf 'a change to close over %s\n' "$N" > "$VAULT/notes.txt"
RUNENV="PATH=$WORK/psnone:$PATH"
run close --run rclose2 --meter-line "$METER" --commit "fixture: the closing commit" --push
need_rc 0
need_out "push ok"
need_eq "$(mk field "$REC" run-close push)" "ok" "push"
need_eq "$(git -C "$VAULT" rev-parse HEAD)" "$(git -C "$REMOTE" rev-parse HEAD)" "remote head"
verdict "close --commit --push: the commit is made and pushed to the fixture remote"

# ------------------------------------------------------------------------ write proof ------
MANIFEST_AFTER="$WORK/manifest-after.txt"
mk manifest "$SKILL_DIR" "$HOOKS_DIR" > "$MANIFEST_AFTER"
# A difference here is either a write by the suite (the fault this leg looks for) or a sibling
# process writing to the same directory while the suite ran; the reason line names the paths,
# so the two can be told apart rather than guessed at.
DIFF=$(diff "$MANIFEST_BEFORE" "$MANIFEST_AFTER" | grep '^[<>]' | cut -c1-90)
need_eq "$DIFF" "" "manifest difference"
need_eq "$(grep -c . "$MANIFEST_BEFORE")" "$(grep -c . "$MANIFEST_AFTER")" "manifest length"
NEWCACHE=$(grep '__pycache__' "$MANIFEST_AFTER" | grep -c -v -F -f "$MANIFEST_BEFORE")
need_eq "$NEWCACHE" "0" "byte-code files created under the shipped directories"
verdict "write proof: the shipped skill and hooks directories are byte-identical after the run"

COPY="$WORK/manifest-control"
rm -rf "$COPY"
mkdir -p "$COPY"
cp "$H" "$COPY/handsoff.py"
mk manifest "$COPY" > "$WORK/control-before.txt"
printf '# a planted change\n' >> "$COPY/handsoff.py"
mk manifest "$COPY" > "$WORK/control-after.txt"
if diff "$WORK/control-before.txt" "$WORK/control-after.txt" >/dev/null; then
  why="$why; the manifest did not notice a planted one-line change"
fi
verdict "write proof control: the manifest detects a planted change in a copy"

SCAN=$(mk srcscan "$SRC" | tail -1)
need_eq "$SCAN" "hits 0" "source scan of the suite"
PLANTED=$(mk srcscan "$WORK/planted-writer.sh" | tail -1)
need_eq "$PLANTED" "hits 2" "source scan of the planted control"
verdict "write proof: no write verb in this suite aims outside /tmp (control: 2 planted hits)"

# ------------------------------------------ waste fields (register, 2026-09-05) ------------
# The three boundary fields whose labels said more than they measured: idle_min is head
# idleness (time in the span when no lane was running and the head made no call, a head gap
# counting only above 60 s) read from the head's transcript, with the record-only measure
# kept as a labelled fallback; respawn_cost_usd leaves out a cut lane that a later
# lane-resumed picked up; rewrites is the change since the same head's previous boundary.
# Every timestamp is placed relative to N, the clock at fixture time, so each figure is
# arithmetic. Span: a planted boundary at N-1000 to the boundary under test (about N). Lane
# L1 runs N-900..N-600; the head calls at N-1000, N-900, N-870, N-300 and N. Gaps above 60 s:
# N-1000..N-900 = 100 s (no lane); N-870..N-300 = 570 s, of which N-870..N-600 = 270 s under
# L1, so 300 s; N-300..N = 300 s; the last gap, to the boundary itself, is seconds. Idle =
# 700 s = 11.7 min. The record-only measure on the same events is L1's close (N-600) to the
# head's next recorded act (the observation at N-300) = 5.0 min, which the transcript-less
# control reads and labels idle_src record.
cat > "$WORK/idle-fixture.py" <<'BH2_IDLE_FIXTURE_END'
import json, os, re, sys, time
rec, sid, mode = sys.argv[1], sys.argv[2], sys.argv[3]
now = time.time()
stamp = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(t))
zulu = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".000Z"
with open(rec, encoding="utf-8") as fh:
    run = json.loads(fh.readline())["run"]
events = [
    {"event": "phase-boundary", "from": "0", "to": "1", "ts": stamp(now - 1000),
     "next": "the planted span start"},
    {"event": "lane-open", "lane": "L1", "ts": stamp(now - 900), "class": "builder"},
    {"event": "lane-closed", "lane": "L1", "ts": stamp(now - 600), "exit_class": "completed",
     "total_cost_usd": 1.0, "report_words": 10},
    {"event": "observation", "ts": stamp(now - 300), "what": "the head's next recorded act"},
]
with open(rec, "a", encoding="utf-8") as fh:
    for ev in events:
        ev["run"] = run
        fh.write(json.dumps(ev) + "\n")
if mode == "transcript":
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(os.environ["CLAUDE_PROJECT_DIR"]))
    path = os.path.join(os.environ["AIMYTH_PROJECTS_DIR"], slug, sid + ".jsonl")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for t in (now - 1000, now - 900, now - 870, now - 300, now):
            fh.write(json.dumps({"type": "assistant", "isSidechain": False, "timestamp": zulu(t),
                                 "message": {"role": "assistant", "model": "claude-fixture-1",
                                             "usage": {"input_tokens": 100,
                                                       "cache_read_input_tokens": 1,
                                                       "cache_creation_input_tokens": 1}}}) + "\n")
print("planted")
BH2_IDLE_FIXTURE_END

fixture ridle 200
"$PY" "$WORK/idle-fixture.py" "$REC" sid-ridle transcript >/dev/null
run boundary --run ridle --from 1 --to 2 --disposition "head idle" --waste "none" --next "n" \
    --meter-line "$METER"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary idle_min)" "11.7" "idle_min from the transcript"
need_eq "$(mk field "$REC" phase-boundary idle_src)" "transcript" "idle_src"
need_out "idle 11.7 min"
need_out "idle src transcript"
verdict "waste fields: idle_min is head idleness from the head's transcript — 700 s of gaps above 60 s outside the lane's running time = 11.7 min, labelled idle_src transcript"

fixture ridle2 200
"$PY" "$WORK/idle-fixture.py" "$REC" sid-ridle2 none >/dev/null
run boundary --run ridle2 --from 1 --to 2 --disposition "no transcript" --waste "none" --next "n" \
    --meter-line "$METER"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary idle_min)" "5.0" "idle_min from the record"
need_eq "$(mk field "$REC" phase-boundary idle_src)" "record" "idle_src"
need_out "idle src record"
verdict "waste fields: the same events without a head transcript fall back to the record-only measure (5.0 min, each close to the head's next act) and say so with idle_src record (the control: the two figures differ)"

fixture rresp 200
mk append "$REC" '{"event":"lane-open","lane":"C1","class":"builder"}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"C1","session_id":"lane-c1","exit_class":"limit","total_cost_usd":4.0,"report_words":5}' >/dev/null
mk append "$REC" '{"event":"lane-resumed","lane":"C1","session_id":"lane-c1","resume_n":1}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"C1","session_id":"lane-c1","exit_class":"completed","total_cost_usd":1.0,"report_words":5,"resumed":true}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"C2","exit_class":"budget","total_cost_usd":2.5,"report_words":5}' >/dev/null
run boundary --run rresp --from 1 --to 2 --disposition "a resumed cut" --waste "none" --next "n" \
    --meter-line "$METER"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary respawn_cost_usd)" "2.5" "respawn_cost_usd"
need_eq "$(mk field "$REC" phase-boundary respawn_excluded)" "1" "respawn_excluded"
need_out "re-spawn \$2.50"
need_out "1 resumed lane(s) excluded from re-spawn"
verdict "waste fields: respawn_cost_usd leaves out the cut lane a later lane-resumed picked up (C1, \$4.00) and keeps the one nobody resumed (C2, \$2.50)"

fixture rresp2 200
mk append "$REC" '{"event":"lane-closed","lane":"C1","exit_class":"limit","total_cost_usd":4.0,"report_words":5}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"C2","exit_class":"budget","total_cost_usd":2.5,"report_words":5}' >/dev/null
run boundary --run rresp2 --from 1 --to 2 --disposition "no resume" --waste "none" --next "n" \
    --meter-line "$METER"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary respawn_cost_usd)" "6.5" "respawn_cost_usd"
need_eq "$(mk field "$REC" phase-boundary respawn_excluded)" "0" "respawn_excluded"
need_out "re-spawn \$6.50"
need_absent "excluded from re-spawn"
verdict "waste fields: the same two cuts with no lane-resumed both count (\$6.50, none excluded) — the control for the leg above"

fixture rrew 200
run boundary --run rrew --from 1 --to 2 --disposition "first" --waste "none" --next "n" \
    --meter-line "$METER"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary rewrites)" "3" "the first boundary keeps the billed figure"
need_eq "$(mk field "$REC" phase-boundary rewrites_total)" "3" "rewrites_total"
need_eq "$(mk field "$REC" phase-boundary rewrites_since)" "head start" "rewrites_since"
METER5=$(printf '%s' "$METER" | sed 's/rewrites 3 (/rewrites 5 (/')
run boundary --run rrew --from 2 --to 3 --disposition "second" --waste "none" --next "n" \
    --meter-line "$METER5"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary rewrites)" "2" "the change since the previous boundary"
need_eq "$(mk field "$REC" phase-boundary rewrites_total)" "5" "rewrites_total"
case $(mk field "$REC" phase-boundary rewrites_since) in
  "1 → 2 at "*) : ;;
  *) why="$why; rewrites_since does not name the previous boundary: $(mk field "$REC" phase-boundary rewrites_since)" ;;
esac
need_out "rewrites 2 "
verdict "waste fields: rewrites is the change since this head's previous boundary (billed 3 then 5: fields 3, then 2), the first boundary keeping the figure and the second naming its base"

RUNENV="PATH=$WORK/psnone:$PATH"
run run-resume --run rrew --session sid-rrew-2 --head "successor" --detail "a second head"
need_rc 0
METER7=$(printf '%s' "$METER" | sed 's/rewrites 3 (/rewrites 7 (/')
run boundary --run rrew --from 3 --to 4 --disposition "the successor's first" --waste "none" \
    --next "n" --meter-line "$METER7"
need_rc 0
need_eq "$(mk field "$REC" phase-boundary rewrites)" "7" "a new head's first boundary keeps its figure"
need_eq "$(mk field "$REC" phase-boundary rewrites_since)" "head start" "rewrites_since"
verdict "waste fields: a successor head's first boundary keeps its own billed figure (7, not 7 - 5): the change never crosses heads (the control for the leg above)"

WTR="$WORK/rresp-table.md"
run waste-table --run rresp --out "$WTR"
need_rc 0
need_eq "$(grep -c 'cut lane · C1 · exit class limit · resumed | \$4.00 · lane-closed.total_cost_usd · C1 at .* · resumed at .*, so not lost (excluded from respawn_cost_usd) | real | no fix' "$WTR")" "1" "the resumed cut lane's row"
need_eq "$(grep -c 'lost lane · C2 · exit class budget | \$2.50' "$WTR")" "1" "the lost lane's row"
need_eq "$(grep -c '(1 resumed lane(s) excluded)' "$WTR")" "1" "the respawn field's source"
need_eq "$(grep -c '(idle_src record)' "$WTR")" "1" "the idle field's source (the record fallback)"
need_eq "$(grep -c 'change since head start (this head' "$WTR")" "1" "the rewrites field's source"
need_eq "$(grep -c 'Field meanings (2026-09-06)' "$WTR")" "1" "the legend"
WTI="$WORK/ridle-table.md"
run waste-table --run ridle --out "$WTI"
need_rc 0
need_eq "$(grep -c '| 11.7 min · phase-boundary.idle_min · head idle: no lane running and no head call, gaps above 60 s, the head.s calls from its transcript (idle_src transcript)' "$WTI")" "1" "the transcript-sourced idle row"
verdict "waste-table: the rows say the new meanings and their source — the resumed cut lane is not lost, the lost-lane cost names its exclusion, idle names transcript or record, rewrites names its base — and the legend carries them"

# The soft cap the wrapper logs at every close had no reader until this table (critic finding
# F4, 2026-09-07): a completed lane over its class's soft threshold gets a row of its own, a
# lost one carries the note on the row it already had, and a close without the flag gets none.
fixture rsoft 200
mk append "$REC" '{"event":"lane-closed","lane":"S1","exit_class":"completed","total_cost_usd":12.0,"soft_usd":9.67,"soft_exceeded":true,"report_words":5}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"S2","exit_class":"completed","total_cost_usd":1.0,"soft_usd":9.67,"soft_exceeded":false,"report_words":5}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"S3","exit_class":"budget","total_cost_usd":3.0,"soft_usd":2.14,"soft_exceeded":true,"report_words":5}' >/dev/null
WSC="$WORK/rsoft-table.md"
run waste-table --run rsoft --out "$WSC" --no-meter
need_rc 0
need_eq "$(grep -c 'soft-cap lane · S1 · exit class completed | soft-cap: \$12.00 over \$9.67 (class) · lane-closed.soft_exceeded · logged at the close, never a stop | arguable | unrouted' "$WSC")" "1" "the completed lane's soft-cap row"
need_eq "$(grep -c 'S2' "$WSC")" "0" "a close whose soft_exceeded is false gets no row (the control)"
verdict "waste-table (F4): a completed lane billed over its class's soft threshold gets a row of its own, arguable in kind and routed like any other finding, while a close carrying soft_exceeded false gets none"

need_eq "$(grep -c 'lost lane · S3 · exit class budget | \$3.00 · lane-closed.total_cost_usd · S3 at .* · soft-cap: \$3.00 over \$2.14 (class) | real | unrouted' "$WSC")" "1" "the lost lane's row carries the note"
need_eq "$(grep -c 'soft-cap' "$WSC")" "3" "the two rows and the legend sentence, and nothing else"
need_eq "$(grep -c 'the line is logged, never a stop, and the head ledgers it at the lane.s close' "$WSC")" "1" "the legend sentence"
verdict "waste-table (F4): a lost lane that also crossed its soft threshold carries the note on the row it already had, and the legend says the threshold is logged rather than enforced and where the head puts it"

fixture rold 200
B0=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":2.0,"denials":0,"over_cap_reports":0,"respawn_cost_usd":1.0,"rewrites":3}' "$METER")
mk append "$REC" "$B0" >/dev/null
WTO="$WORK/rold-table.md"
run waste-table --run rold --out "$WTO"
need_rc 0
need_eq "$(grep -c 'a boundary written before the head-idle rule (no idle_src)' "$WTO")" "1" "the old idle row"
need_eq "$(grep -c 'a boundary written before the resume exclusion' "$WTO")" "1" "the old respawn row"
need_eq "$(grep -c 'a boundary written before the delta rule' "$WTO")" "1" "the old rewrites row"
need_eq "$(grep -c 'idle_src transcript' "$WTO")" "1" "the transcript source named by the legend only"
verdict "waste-table: a boundary written before the 2026-09-06 meanings is quoted as recorded, each of the three rows naming the rule it predates (the control: the new-meaning strings appear in the legend alone)"

# ------------------------------- the five fixes of 2026-09-07 (T6, T7, T8 and two entries) --
# (a) T7: run-open --session-kind, written as session_kind, and the seed session skipped by the
# waste table's head rows and named once in its legend line.
HO="$WORK/handoffs/rskind-handoff.md"; mk handoff "$HO" >/dev/null
REC="$STORE/spawn-records/rskind.jsonl"; rm -f "$REC"
run run-open --run rskind --session sid-seedplace --head "launcher" --regime multi \
    --regime-src owner --handoff "$HO" --detail "a seeded launch" --pid 4242 \
    --envelope-usd 400 --session-kind seed
need_rc 0
need_out "session_kind seed"
need_eq "$(mk field "$REC" run-open session_kind)" "seed" "session_kind on the run-open event"
HO2="$WORK/handoffs/rhkind-handoff.md"; mk handoff "$HO2" >/dev/null
rm -f "$STORE/spawn-records/rhkind.jsonl"
run run-open --run rhkind --session sid-realhead --head "head" --regime multi \
    --regime-src owner --handoff "$HO2" --detail "an ordinary launch" --pid 4242
need_rc 0
need_eq "$(mk field "$STORE/spawn-records/rhkind.jsonl" run-open session_kind)" "head" \
        "positive control: the default is head, never absent"
verdict "run-open: --session-kind seed is written as session_kind on the run-open event and named on the line, and the flag defaults to head (T7)"

mk append "$REC" '{"event":"head-exit","band":"unmetered","context":"unmetered (transcript missing: a path that is not there)","exit_class":"error","pack":false}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-realsucc","pid":1,"budget":1.0}' >/dev/null
mk append "$REC" '{"event":"run-resume","session":"sid-realsucc","head":"h","detail":"the successor records itself","pid_src":"none"}' >/dev/null
mk append "$REC" '{"event":"gate","item":"one","context":100000,"percent":10,"band":0,"metered":true,"orientation_tokens":4000}' >/dev/null
WSK="$WORK/rskind-table.md"
run waste-table --run rskind --out "$WSK" --no-meter
need_rc 0
need_eq "$(grep -c '1 head session(s)' "$WSK")" "1" "the seed session is not a head session"
need_eq "$(grep -c 'seed (skipped): sid-seedplace' "$WSK")" "1" "one seed line in the legend"
need_eq "$(grep -c '^| orientation cost · head sid-realsucc' "$WSK")" "1" "positive control: the real head still has its row"
need_eq "$(grep -c '^| orientation cost · head sid-seedplace' "$WSK")" "0" "the seed session renders no head row"
need_eq "$(grep -c 'Head sessions are counted by DISTINCT session id (sid-realsucc)' "$WSK")" "1" "the head named is the real one"
WSK2="$WORK/rwaste-noseed.md"
run waste-table --run rwaste --out "$WSK2" --no-meter
need_eq "$(grep -c 'seed (skipped): none' "$WSK2")" "1" "control: a record marking no seed says so rather than dropping the line"
verdict "waste-table: a session run-open marks seed is skipped by the head rows and named once as 'seed (skipped)', while a record with no seed says none (T7)"

# (b) T6: the run's own window, and the --start/--end pair passed to the meter.
fixture rwin 200
mk append "$REC" '{"event":"phase-boundary","from":"1","to":"2","idle_min":0.0}' >/dev/null
mk append "$REC" '{"event":"run-close","items":"1","register":"none"}' >/dev/null
"$PY" - "$H" "$REC" <<'WINDOW' > "$WORK/window.txt"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
evs = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
start, end, src = mod.run_window(evs)
cmd = mod.meter_cmd("/nowhere/fable-share.py", "rwin", "sid-rwin", mod.run_open(evs), "auto",
                    start, end)
print(start)
print(end)
print(src)
print(" ".join(cmd))
WINDOW
need_eq "$(sed -n 1p "$WORK/window.txt")" "$(mk field "$REC" run-open ts)" "the window opens at run-open"
need_eq "$(sed -n 2p "$WORK/window.txt")" "$(mk field "$REC" run-close ts)" "the window closes at run-close"
case $(sed -n 4p "$WORK/window.txt") in
  *"--start $(mk field "$REC" run-open ts) --end $(mk field "$REC" run-close ts)"*) : ;;
  *) why="$why; the meter command carries no --start/--end pair: $(sed -n 4p "$WORK/window.txt")" ;;
esac
fixture rwin2 200
mk append "$REC" '{"event":"phase-boundary","from":"1","to":"2","idle_min":0.0}' >/dev/null
"$PY" - "$H" "$REC" <<'WINDOW2' > "$WORK/window2.txt"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("target", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
evs = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
start, end, src = mod.run_window(evs)
print(end)
print(src)
WINDOW2
need_eq "$(sed -n 1p "$WORK/window2.txt")" "$(mk field "$REC" phase-boundary ts)" "control: no run-close ends the window at the record's last event"
case $(sed -n 2p "$WORK/window2.txt") in
  *"no run-close"*) : ;;
  *) why="$why; the window source does not say the run-close is missing: $(sed -n 2p "$WORK/window2.txt")" ;;
esac
verdict "waste-table (T6): the run's own window is run-open to run-close, else the record's last event, and the meter command carries it as --start/--end"

fixture rwinrow 200
BW=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":0.0,"denials":0,"over_cap_reports":0,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$BW" >/dev/null
WWR="$WORK/rwinrow-table.md"
WINLINE='billed (list 2026-09-03) · head $5.00 · lanes $2.00 · session $7.00 · rewrites 0 ($0.00) · metered 1 of 1'
run waste-table --run rwinrow --out "$WWR" --meter-line "sid-rwinrow=$WINLINE"
need_rc 0
need_eq "$(grep -c 'run total (shown sum) | \$7.00 = \$7.00' "$WWR")" "1" "the window figure wins over the session-wide billed line"
need_eq "$(grep -c "metered over the run's window: \$7.00 (the record gives the last boundary billed line" "$WWR")" "1" "the row says which figure it took and what the record gave"
need_eq "$(grep -c 'envelope base \$200.00 (run-open.envelope_usd)' "$WWR")" "1" "the envelope base beside the total"
WWR2="$WORK/rwinrow-norow.md"
run waste-table --run rwinrow --out "$WWR2" --no-meter
need_eq "$(grep -c 'run total (shown sum) | \$19.62 = \$19.62' "$WWR2")" "1" "control: without a window figure the row falls back to the record's own"
verdict "waste-table (T6): the whole-run row takes the head's window meter figure over the session-wide billed line, names both and prints the envelope base"

# (b) the register entry of 2026-09-06: the under-read, the head count and the limit wait.
fixture rlater 100
BL=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":0.0,"denials":0,"over_cap_reports":0,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$BL" >/dev/null
mk append "$REC" '{"event":"head-exit","band":0,"context":"362,843 tokens (36 %)","spent_usd":56.26,"pack":true}' >/dev/null
WLA="$WORK/rlater-table.md"
run waste-table --run rlater --out "$WLA" --no-meter
need_rc 0
need_eq "$(grep -c 'run total (shown sum) | \$56.26 = \$56.26' "$WLA")" "1" "the later head-exit spend, not the earlier billed line"
need_eq "$(grep -c 'head-exit.spent_usd \$56.26, later in the record than the last boundary billed line \$19.62' "$WLA")" "1" "the row names both figures and which is later"
fixture rearlier 100
mk append "$REC" '{"event":"head-exit","band":0,"context":"c","spent_usd":5.0,"pack":true}' >/dev/null
mk append "$REC" "$BL" >/dev/null
WEA="$WORK/rearlier-table.md"
run waste-table --run rearlier --out "$WEA" --no-meter
need_eq "$(grep -c 'run total (shown sum) | \$19.62 = \$19.62' "$WEA")" "1" "control: a boundary later than the head-exit keeps the billed line"
verdict "waste-table (register 2026-09-06): per head the run total takes the LATER of the last boundary billed line and head-exit.spent_usd, so a head that exits without a boundary loses no spend"

fixture rids 100
mk append "$REC" '{"event":"head-successor","session_id":"sid-two","pid":1,"budget":1.0}' >/dev/null
mk append "$REC" '{"event":"run-resume","session":"sid-two","head":"h","detail":"the successor records itself","pid_src":"none"}' >/dev/null
mk append "$REC" '{"event":"head-successor","session_id":"sid-two","pid":1,"budget":1.0}' >/dev/null
WID="$WORK/rids-table.md"
run waste-table --run rids --out "$WID" --no-meter
need_rc 0
need_eq "$(grep -c '2 head session(s)' "$WID")" "1" "four spans over two distinct ids read as two heads"
need_eq "$(grep -c 'Head sessions are counted by DISTINCT session id (sid-rids, sid-two)' "$WID")" "1" "the ids are named"
mk append "$REC" '{"event":"head-successor","session_id":"sid-three","pid":1,"budget":1.0}' >/dev/null
WID2="$WORK/rids2-table.md"
run waste-table --run rids --out "$WID2" --no-meter
need_eq "$(grep -c '3 head session(s)' "$WID2")" "1" "positive control: a third id moves the count to three"
verdict "waste-table (register 2026-09-06): head sessions are counted by distinct session id, four spans of two ids reading as two heads"

# The record's own run-open sits two hours back, so the planted wait is stamped inside that
# span (a stop 60 minutes back, its resume 30 minutes back) rather than on a fixed date.
fixture rlimit 100
STOP_TS=$("$PY" -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - 3600)))')
RES_TS=$("$PY" -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - 1800)))')
mk append "$REC" "{\"event\":\"stop-condition\",\"which\":\"limit\",\"lane\":\"head\",\"action\":\"wait until the reset\",\"ts\":\"$STOP_TS\"}" >/dev/null
mk append "$REC" "{\"event\":\"head-resumed\",\"session_id\":\"sid-rlimit\",\"pid\":1,\"context\":136346,\"waited_s\":1800,\"ts\":\"$RES_TS\"}" >/dev/null
BLIM=$(printf '{"event":"phase-boundary","from":"2","to":"3","meter":"%s","idle_min":40.0,"idle_src":"transcript","denials":0,"over_cap_reports":0,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$BLIM" >/dev/null
WLI="$WORK/rlimit-table.md"
run waste-table --run rlimit --out "$WLI" --no-meter
need_rc 0
need_eq "$(grep -c "^| limit wait · limit → head-resumed at $RES_TS | 30.0 min" "$WLI")" "1" "the structural row for the recorded limit wait"
need_eq "$(grep -c 'not head idleness: a boundary whose span covers it counts the same minutes under idle_min | structural' "$WLI")" "1" "the row's kind and its reason"
need_eq "$(grep -c 'of which 30.0 min is a recorded limit wait' "$WLI")" "1" "the idle row says how much of it is the wait"
need_eq "$(grep -c '^| limit wait' "$WTR")" "0" "control: a record with no stop-condition renders no limit-wait row"
verdict "waste-table (register 2026-09-06): a stop-condition and its head-resumed take a structural row of their own and the idle row that covers them says how many of its minutes they hold"

# (c) T8: the over-cap row carries the cut tail's price, never the lane's whole cost.
fixture rtail 200
mk append "$REC" '{"event":"lane-open","lane":"L9","class":"builder","model":"claude-opus-5","budget_usd":15.0}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"L9","exit_class":"completed","total_cost_usd":14.57,"report_words":1000,"report_cut":true}' >/dev/null
mk append "$REC" '{"event":"lane-open","lane":"L8","class":"verifier","model":"claude-sonnet-5","budget_usd":2.0}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"L8","exit_class":"completed","total_cost_usd":0.39,"report_words":800,"report_cut":false}' >/dev/null
BT=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":0.0,"denials":0,"over_cap_reports":1,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$BT" >/dev/null
WTT="$WORK/rtail-table.md"
run waste-table --run rtail --out "$WTT" --no-meter
need_rc 0
need_eq "$(grep -c 'cut tail \$0.01 · the tail alone (report_words − 800), never the lane.s whole cost: L9 200 words over = \$0.0065 (opus output \$25.00/MTok)' "$WTT")" "1" "the cut tail priced at the lane's model's output rate"
need_eq "$(grep -c '1.3 tokens per word, set by judgement, unmeasured' "$WTT")" "2" "the ratio and its standing, in the row and in the legend"
need_eq "$(grep -c 'L8' "$WTT")" "0" "a lane at the cap contributes nothing to the row"
need_eq "$(grep -c '14.57' "$WTT")" "0" "the lane's whole cost is not the figure"
verdict "waste-table (T8): the over-cap row carries the cut tail (report_words − 800 at the model's output rate), a lane at the cap contributing nothing and the lane's whole cost nowhere in it"

fixture rtail2 200
mk append "$REC" '{"event":"lane-closed","lane":"L7","exit_class":"completed","total_cost_usd":1.0,"report_words":900}' >/dev/null
mk append "$REC" '{"event":"lane-open","lane":"L6","class":"builder","model":"fable-1","budget_usd":15.0}' >/dev/null
mk append "$REC" '{"event":"lane-closed","lane":"L6","exit_class":"completed","total_cost_usd":1.0,"report_words":900}' >/dev/null
BT2=$(printf '{"event":"phase-boundary","from":"1","to":"2","meter":"%s","idle_min":0.0,"denials":0,"over_cap_reports":2,"respawn_cost_usd":0.0}' "$METER")
mk append "$REC" "$BT2" >/dev/null
WT7="$WORK/rtail2-table.md"
run waste-table --run rtail2 --out "$WT7" --no-meter
need_rc 0
need_eq "$(grep -c 'L7 100 words over (unpriced: the record names no model for this lane)' "$WT7")" "1" "a lane whose model the record does not name is counted in words and left unpriced"
need_eq "$(grep -c 'L6 100 words over = \$0.0065 (fable output \$50.00/MTok)' "$WT7")" "1" "positive control: the priced lane in the same span"
need_eq "$(grep -c 'over the priced tail(s)' "$WT7")" "1" "the total says it covers the priced tails alone"
verdict "waste-table (T8): a lane whose model the record does not name is counted in words and never guessed at a price, beside a priced lane in the same span"

# (d) the extraction carries an assistant record's tool calls, never their results.
mk toolscript sid-tools >/dev/null
TX="$WORK/tools"
run extract-transcript --session sid-tools --out "$TX"
need_rc 0
need_out "2 turns (1 human, 1 assistant) of 6 records"
need_out "2 tool-call turn(s)"
need_eq "$(grep -c '^## turn 2 · assistant · tool calls · 2026-09-07T10:00:10Z' "$TX/turns.md")" "1" "the tool-call turn's heading"
need_eq "$(grep -c '^- Bash: git status --porcelain' "$TX/turns.md")" "1" "the Bash call carries its command"
need_eq "$(grep -c '^- Read: /fixture/page.md' "$TX/turns.md")" "1" "the Read call carries its file path"
need_eq "$(grep -c '^- Grep: needle' "$TX/turns.md")" "1" "the Grep call carries its pattern"
need_eq "$(grep -c '^- TodoWrite$' "$TX/turns.md")" "1" "a tool outside the table prints its name alone"
need_eq "$(grep -c 'the tool result never reaches the extraction' "$TX/turns.md")" "0" "the tool result is out, as before"
# A repetition count above 255 is outside POSIX grep, so the long line is matched by its head
# and its cut marker and measured in Python.
need_eq "$(grep -c ' …\[cut\]$' "$TX/turns.md")" "1" "one line carries the cut marker"
need_eq "$(grep -c '^- Bash: yyyyyyyyyy' "$TX/turns.md")" "1" "the long command's own line"
CUTLEN=$("$PY" -c 'import sys; print(max(len(x.rstrip(chr(10))) for x in open(sys.argv[1], encoding="utf-8") if x.startswith("- Bash: y")))' "$TX/turns.md")
need_eq "$CUTLEN" "300" "the cut line is exactly 300 characters"
verdict "extract-transcript: an assistant record of tool calls alone is a tool-call turn, one line per call with the tool's name and its command, path or pattern, cut at 300 characters (register 2026-09-07)"

need_eq "$(mk json "$TX/counts.json" tool_call_turns)" "2" "tool_call_turns in counts.json"
need_eq "$(mk json "$TX/counts.json" extracted)" "2" "extracted counts the prose turns alone"
"$PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c["records"], c["extracted"] + c["tool_call_turns"] + sum(c["excluded"].values()))' \
      "$TX/counts.json" > "$WORK/sum.txt"
need_eq "$(cut -d" " -f1 "$WORK/sum.txt")" "$(cut -d" " -f2 "$WORK/sum.txt")" "records = extracted + tool_call_turns + excluded"
need_eq "$(grep -c 'Records = 2 extracted + 2 tool-call + 2 excluded = 6' "$TX/turns.md")" "1" "the extraction states the arithmetic"
need_eq "$(grep -c '^## turn 3 · assistant · 2026-09-07T10:00:20Z' "$TX/turns.md")" "1" "a record with prose AND calls keeps its prose turn"
need_eq "$(grep -c '^- Edit: /fixture/other.md' "$TX/turns.md")" "1" "and its tool calls go under that turn"
need_eq "$(mk json "$EX/counts.json" tool_call_turns)" "1" "positive control: the first extraction's own tool-call record"
verdict "extract-transcript: counts.json carries tool_call_turns and records = extracted + tool_call_turns + excluded holds, a record with prose and calls keeping one turn"

RTD="$WORK/rrefl-tools"
run reflect-inputs --run rrefl --session sid-tools --out "$RTD" --no-meter
need_rc 0
need_out "2 tool-call turn(s)"
need_eq "$(mk field "$STORE/spawn-records/rrefl.jsonl" reflect-inputs counts | grep -c 'tool_call_turns')" "1" "the event's counts carry the figure"
verdict "reflect-inputs: the tool-call turns reach the reflector's input set and the count is on the event"

# (e) the successor sizes its cap from the envelope when the last head-exit is a seed exit.
fixture rseedsucc 400
mk append "$REC" '{"event":"head-exit","band":"unmetered","context":"unmetered (transcript missing: a path that is not there)","exit_class":"error","pack":false}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rseedsucc --dry-run --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "budget_src: envelope (seed)"
need_out "budget \$400.00"
need_absent "pass --budget-usd"
fixture rmetsucc 400
mk append "$REC" '{"event":"head-exit","band":0,"context":"500,000 tokens (50 %)","spent_usd":40.0,"pack":true}' >/dev/null
RUNENV="PATH=$WORK/psnone:$PATH"
run successor --run rmetsucc --dry-run --meter-line "$METER" --harness-bin "$WORK/bin/harness"
need_rc 0
need_out "budget \$360.00"
need_absent "envelope (seed)"
verdict "successor: a seed head-exit sizes the cap at the envelope minus recorded spend (budget_src: envelope (seed)), while a metered head-exit takes the ordinary remainder (register 2026-09-07)"

# ----------------------------------------------------------------------------- summary -----
printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'PASS %d/%d\n' "$PASSED" "$N"
  exit 0
fi
printf 'FAIL %d/%d\n' "$FAILED" "$N"
exit 1
