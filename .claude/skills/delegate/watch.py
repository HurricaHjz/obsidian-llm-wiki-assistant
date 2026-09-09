#!/usr/bin/env python3
"""watch.py — a read-only console for a hands-off run.

Panels: header (run, head session, head turns, context %, spend once metered, elapsed, supervisor,
clock) · items (one bar per pack item, its state and its lanes as running/completed/other, plus an
overall bar) · lanes now (state, class, model and effort, elapsed, live turns from the lane's own
transcript, its last tool call, cost at the close or the cap while it runs) · timeline (a time axis,
the head row coloured by item with gate, boundary, limit-wait, stop, resume and close marks, the close
in the close's tone: bold green when every item is done, bold yellow when one was skipped; one row
per lane coloured by class) · feed (the record's events and the head's prose and tool calls, alerts
in red).

Reads the run record, the hand-off pack the record's `run-open` names, the head's transcript and the
lanes' transcripts.  It writes exactly one file, and only when the run closes: the plain-text
timeline report `<store>/spawn-records/<run>-timeline.txt`.  No tokens, no API calls.

The plain-lane-run shape. A record with lane events and no `run-open` — an attended session's
lanes, with no hands-off run behind them — renders the header line `plain lane run · no run-open`
with the lanes and the spend summed from the lanes' own costs, the lanes panel, the timeline's
lane rows without a head row, and the feed: no items panel, because no pack names any. Its close
draws the same boxed notice and writes the same timeline report. A record that HAS a run-open and
no items is still the broken premise it always was.

A lane with no close event is not taken on trust. Every open lane's recorded processes — the
`pid` and `wrapper_pid` its `lane-spawned` or `lane-resumed` carries — are probed with
`os.kill(pid, 0)` on every frame, and one whose processes have all gone is drawn `✗ dead` in
the lanes panel and counted as `dead` in the close banner, never `● running`: a lane killed by
hand writes no `lane-closed`, and the console used to show it running for ever. Only
`ProcessLookupError` counts as gone; a `PermissionError` (alive, another user's process) and
any unanswered probe leave the lane running, and an open lane whose record carries no pid at
all stays running too — an absence is never read as a death. `lane.py kill` is the deliberate
stop that writes the close this probe stands in for.

At the close the run has the last word on the items: every item that ever started ends with the
run and reads done, one that never started reads skipped, the overall line carries the verdict,
and a boxed RUN CLOSED notice with the run's totals follows the final board, the report's path
on a bare line beneath it so it is never cut.

Every path is derived: the vault is `--vault`, else `CLAUDE_PROJECT_DIR`, else three directory
levels above this script; the run store and the record path come from `handsoff.py`
(`store_root`, `record_path`); the head's transcript is `handsoff.py`'s `transcript_for`; a lane's
transcript follows `lane.py`'s `find_transcript` rule over the lane's own `lane-open` event.

Usage: watch.py --run RUN [--once] [--plain] [--no-notify] [--refresh S] [--vault DIR]
Keys while it runs: `q` quits · `r` resumes a stopped head (`handsoff.py resume-head`).
Design and derivations: DESIGN.md beside this file; suite: test_watch.sh.
"""
import argparse
import glob as globmod
import json
import os
import re
import select
import shlex
import shutil
import subprocess
import sys
import time
from collections import deque
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------ derived roots ----------
# The shipped primitives are the source of truth for every root.  When they cannot be imported
# (a copy of this file on its own) the replicas below repeat their rule exactly, and each names
# the function it mirrors.

_HANDSOFF = None
_HANDSOFF_TRIED = False


def handsoff():
    """The sibling `handsoff.py` as a module, or None. Imported lazily: a console that starts in
    a directory without it still runs on the replicas."""
    global _HANDSOFF, _HANDSOFF_TRIED
    if not _HANDSOFF_TRIED:
        _HANDSOFF_TRIED = True
        try:
            import importlib.util
            path = os.path.join(HERE, "handsoff.py")
            spec = importlib.util.spec_from_file_location("handsoff_for_watch", path)
            if spec and spec.loader:
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                _HANDSOFF = module
        except Exception:                                     # a broken sibling is not fatal here
            _HANDSOFF = None
    return _HANDSOFF


def vault_root(given=None):
    """`--vault`, else CLAUDE_PROJECT_DIR, else three levels above this script — handsoff.py's
    `vault_root` rule, with the flag added so a copy can be pointed at another tree."""
    if given:
        return os.path.realpath(os.path.expanduser(given))
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return os.path.realpath(os.path.expanduser(env))
    return os.path.realpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))


def store_root():
    """handsoff.py `store_root`: LLM_WIKI_STORE, else ~/.llm-wiki, as its real path."""
    module = handsoff()
    if module is not None and hasattr(module, "store_root"):
        return module.store_root()
    return os.path.realpath(os.path.expanduser(
        os.environ.get("LLM_WIKI_STORE") or os.path.join("~", ".llm-wiki")))


def record_path(run):
    """handsoff.py `record_path`: <store>/spawn-records/<run>.jsonl."""
    module = handsoff()
    if module is not None and hasattr(module, "record_path"):
        return module.record_path(run)
    return os.path.join(store_root(), "spawn-records", run + ".jsonl")


def report_path(run):
    """The one file this console writes, beside the record it read."""
    return os.path.join(store_root(), "spawn-records", "%s-timeline.txt" % run)


def projects_root(config_dir=None):
    """lane.py `projects_root_for`: <config dir or CLAUDE_CONFIG_DIR or ~/.claude>/projects,
    with handsoff.py's AIMYTH_PROJECTS_DIR override honoured first."""
    env = os.environ.get("AIMYTH_PROJECTS_DIR")
    if env:
        return os.path.realpath(os.path.expanduser(env))
    base = config_dir or os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude")
    return os.path.join(base, "projects")


def dashed(path):
    """handsoff.py / lane.py `dashed`: the harness's project-directory encoding — every
    non-alphanumeric character of the real path becomes a dash."""
    module = handsoff()
    if module is not None and hasattr(module, "dashed"):
        return module.dashed(path)
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(path))


def head_transcript_for(sid, vault):
    """handsoff.py `transcript_for`, run against the vault this console was given: the vault's
    project directory first, then a unique hit across the projects root, else the direct path."""
    if not sid:
        return ""
    module = handsoff()
    if module is not None and hasattr(module, "transcript_for"):
        keep = os.environ.get("CLAUDE_PROJECT_DIR")
        os.environ["CLAUDE_PROJECT_DIR"] = vault             # its vault_root() reads this first
        try:
            return module.transcript_for(sid)
        finally:
            if keep is None:
                os.environ.pop("CLAUDE_PROJECT_DIR", None)
            else:
                os.environ["CLAUDE_PROJECT_DIR"] = keep
    root = projects_root()
    direct = os.path.join(root, dashed(vault), "%s.jsonl" % sid)
    if os.path.isfile(direct):
        return direct
    hits = sorted(globmod.glob(os.path.join(root, "*", "%s.jsonl" % sid)))
    return hits[0] if len(hits) == 1 else direct


def lane_transcript_for(home, sid, config_dir=None, root=None):
    """lane.py `find_transcript`: <projects root>/<dashed home>/<session>.jsonl, else the first
    hit for the session id anywhere under the projects root, else nothing."""
    if not sid:
        return ""
    root = root or projects_root(config_dir)
    direct = os.path.join(root, dashed(home), "%s.jsonl" % sid) if home else ""
    if direct and os.path.isfile(direct):
        return direct
    hits = sorted(globmod.glob(os.path.join(root, "*", "%s.jsonl" % sid)))
    return hits[0] if hits else direct


# ------------------------------------------------------------------ presentation ------------

CLASS_COLOUR = {"builder": 33, "critic": 170, "verifier": 37, "reflector": 34,
                "memory-hunter": 178, "gate-judge": 208, "planner": 99, "wiki-compile": 30}
ITEM_COLOURS = [39, 45, 51, 87, 123, 159, 195, 75]            # eight blues, cycled by item order
GREY, DIM, WHITE, RED, GREEN, YELLOW, CYAN = 244, 240, 255, 196, 40, 220, 37

ALERT_EVENTS = ("stop-condition", "supervisor-stood-down", "successor-aborted", "head-exit",
                "run-close")
ALERT_WORDS = re.compile(r"warning|refus|parked|held|reverted|PROBE FAILED|FAIL ", re.I)

# The header line of the plain-lane-run shape: a record with lane events and no `run-open`
# (handsoff.py's PLAIN_SHAPE, written on that record's own run-close). One string, so the console,
# the suite and a reader's grep all name it the same way.
PLAIN_HEADER = "plain lane run · no run-open"

FEED_MAX = 400          # lines kept in memory: ~5 screens of scrollback, bounded by judgement
REPORT_WIDTH = 140      # the close report is a file, so its width is fixed, not the terminal's
REPORT_HEIGHT = 60      # only bounds the feed, which the report omits
MAX_WIDTH = 200         # beyond this the timeline's one-character slices stop being readable
LANE_NAME_W = 15        # the longest lane name over the 52 records of a live store, 2026-09-07
ITEM_NAME_W = 20        # the widest name the accepted grammar makes: `<TODO> · verify+close` (19)
TIMELINE_MIN_W = 20     # fewer than 20 slices cannot separate two marks; the panel says so instead
NOTIFY_CHARS = 180      # osascript's notification body is truncated by the notification centre

USE_COLOUR = True


def c(text, colour=None, bold=False, dim=False):
    if not USE_COLOUR or (colour is None and not bold and not dim):
        return text
    seq = ""
    if bold:
        seq += "\x1b[1m"
    if dim:
        seq += "\x1b[2m"
    if colour is not None:
        seq += "\x1b[38;5;%dm" % colour
    return seq + text + "\x1b[0m"


def visible_len(s):
    return len(re.sub(r"\x1b\[[0-9;]*m", "", s))


def fit(s, width):
    """Cut a plain string to width (never cut inside an escape: callers colour after fitting)."""
    if width <= 0:
        return ""
    return s if len(s) <= width else s[:max(0, width - 1)] + "…"


def parse_ts(ts):
    """Any stamp the record or a transcript carries, as local time: the record writes an offset,
    a transcript writes UTC with a Z."""
    t = str(ts or "").replace("Z", "+00:00")
    if re.search(r"[+-]\d{4}$", t):
        t = t[:-2] + ":" + t[-2:]
    try:
        return datetime.fromisoformat(t).astimezone()
    except ValueError:
        return None


def hms(ts):
    d = parse_ts(ts)
    return d.strftime("%H:%M:%S") if d else str(ts)[11:19]


def epoch(ts):
    d = parse_ts(ts)
    return d.timestamp() if d else 0.0


def span(seconds):
    seconds = int(max(0, seconds))
    h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
    return "%d:%02d:%02d" % (h, m, s) if h else "%d:%02d" % (m, s)


def read_events(path):
    out = []
    try:
        handle = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return out
    with handle:
        for line in handle:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass                                       # a torn tail line: skipped, not fatal
    return out


# ------------------------------------------------------------------ the pack's items --------

ITEM_LINE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}item(\d+)\*{0,2}\s+(.+?)\s+—")


def clean_name(text):
    return re.sub(r"\s+", " ", re.sub(r"[`*_]", "", text)).strip()


def parse_items(text):
    """Item names from a pack's Resume prompt lines. Both shapes are one grammar:
    `item<k> <name> —`, the name free text — `N137 · build`, `N137 · verify+close`, `close-out`
    (the phase shape) or `N137-INSTALL` (the older bare-name shape). The Resume prompt section is
    read first; a pack that names its items elsewhere is read whole."""
    lines = text.splitlines()
    sections, current = {}, None
    for line in lines:
        if line.startswith("## "):
            current = line[3:].strip().lower()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    resume = []
    for name, body in sections.items():
        if name.startswith("resume prompt"):
            resume = body
            break

    def scan(body):
        found = {}
        for line in body:
            m = ITEM_LINE.match(line)
            if m:
                found.setdefault("item" + m.group(1), clean_name(m.group(2)))
        return found

    return scan(resume) or scan(lines)


def pack_items(events):
    """(items, pack path). The pack is the `handoff` the last run-open names."""
    path = ""
    for e in events:
        if e.get("event") in ("run-open", "run-resume") and e.get("handoff"):
            path = os.path.expanduser(str(e["handoff"]))
    if not path or not os.path.isfile(path):
        return {}, path
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return parse_items(fh.read()), path
    except OSError:
        return {}, path


# ------------------------------------------------------------------ the run model -----------

class Lane:
    def __init__(self, e, projects=None):
        self.name = e.get("lane") or "?"
        self.cls = e.get("class") or "?"
        self.model = e.get("model") or "?"
        self.effort = e.get("effort") or "?"
        self.budget = e.get("budget_usd")
        self.reason = str(e.get("reason") or "")
        self.opened = parse_ts(e.get("ts"))
        self.closed = None
        self.exit = "running"
        self.cost = None
        self.turns_final = None
        self.item = None
        self.resumes = 0
        self.notes = ""                                        # a stall or an unwatched transcript
        self.pids = []                                         # what the spawn recorded (see probe_liveness)
        self.home = e.get("cwd") or ""
        self.config_dir = e.get("config_dir")
        self.projects = e.get("projects_root") or projects
        self.session = e.get("session_id")
        self.transcript = self._transcript()
        self.pos = 0
        self.turns = 0
        self.last_call = ""

    def _transcript(self):
        return lane_transcript_for(self.home, self.session, self.config_dir, self.projects)

    def spawned(self, e):
        """`lane-spawned` carries the session the wrapper really started under."""
        if e.get("session_id") and e["session_id"] != self.session:
            self.session, self.pos = e["session_id"], 0
            self.transcript = self._transcript()
        self.note_pids(e)

    def note_pids(self, e):
        """The processes a spawn or a resume names: the lane's own `pid` and the wrapper's
        `wrapper_pid`, which `lane.py` writes on both `lane-spawned` and `lane-resumed`. A later
        spawn or resume of the same lane name replaces them, so the pids in hand are always the
        latest run's."""
        pids = []
        for key in ("pid", "wrapper_pid"):
            value = e.get(key)
            if isinstance(value, int) and not isinstance(value, bool) and value > 0:
                pids.append(value)
        self.pids = pids

    def probe_liveness(self):
        """An open lane whose recorded processes have ALL gone is drawn `✗ dead`, never `● running`.

        A lane killed by hand writes no `lane-closed`, and until this probe the console drew it
        as running for ever. The observable is `os.kill(pid, 0)`: `ProcessLookupError` is the
        one answer that means gone, `PermissionError` means the process is there and owned by
        another user, and any other `OSError` means the question was not answered — so only a
        lane every one of whose pids raised `ProcessLookupError` is called dead. A lane with a
        live pid, and an open lane whose record carries NO pid at all (a record written before
        the spawn line, or one from another host), stay `running`: the console never invents a
        death from an absence. The mark is not sticky against the record — a `lane-closed`
        arriving later rebuilds the lane and its own exit class wins."""
        if self.exit != "running" or not self.pids:
            return
        for pid in self.pids:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue                                       # this one has gone; check the rest
            except PermissionError:
                return                                         # alive, owned by another user
            except OSError:
                return                                         # unanswered: never a death on a maybe
            else:
                return                                         # alive
        self.exit = "dead"
        self.notes = self.notes or "no close event"

    def close(self, e):
        self.closed = parse_ts(e.get("ts"))
        self.exit = e.get("exit_class") or "closed"
        self.cost = e.get("total_cost_usd")
        self.turns_final = e.get("num_turns")

    def resume(self, e):
        """`lane-resumed`: the lane runs again, under a new session (the console miss of
        2026-09-07 was leaving it drawn as closed)."""
        self.closed, self.exit, self.cost, self.turns_final = None, "running", None, None
        self.resumes += 1
        self.note_pids(e)
        if e.get("budget_usd") is not None:
            self.budget = e["budget_usd"]
        if e.get("session_id"):
            self.session, self.pos, self.turns = e["session_id"], 0, 0
            self.transcript = self._transcript()

    def poll(self):
        """Read the lane's transcript forward for its live turn count and last tool call."""
        if not self.transcript or not os.path.isfile(self.transcript):
            return
        try:
            with open(self.transcript, encoding="utf-8", errors="replace") as fh:
                fh.seek(self.pos)
                data = fh.read()
                self.pos = fh.tell()
        except OSError:
            return
        for line in data.splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("type") != "assistant":
                continue
            self.turns += 1
            for blk in (r.get("message") or {}).get("content") or []:
                if isinstance(blk, dict) and blk.get("type") == "tool_use":
                    self.last_call = "%s %s" % (blk.get("name", "tool"), tool_target(blk))


def tool_target(blk):
    inp = blk.get("input") or {}
    if not isinstance(inp, dict):
        return ""
    what = inp.get("command") or inp.get("file_path") or inp.get("pattern") or inp.get("path") or ""
    return str(what).replace("\n", " ")


# The event vocabulary: every kind the writers (handsoff.py, lane.py) and the trace schema of the
# design page can put in a record, and what this console does with it. TREATMENT is the table
# DESIGN.md carries in prose; the suite asserts that no kind in a record is missing from it, so a
# new writer's kind is a suite failure rather than a silent omission. Marks are drawn on the head
# row only, so a lane's own events move the lane row and the items panel instead.
MARKS = {"gate": "gate", "phase-boundary": "boundary", "head-exit": "boundary",
         "stop-condition": "stop", "supervisor-stood-down": "stop", "successor-aborted": "stop",
         "head-resumed": "resume", "head-successor": "resume", "run-resume": "resume",
         "run-close": "close"}
MARK_GLYPH = {"gate": "│", "boundary": "▲", "stop": "✖", "resume": "↻", "close": "■"}
TREATMENT = {
    "run-open": "the run's start, its pack and its head session; feed",
    "run-resume": "a head start: the followed transcript and a ↻ mark; feed",
    "run-close": "the run's end: the ■ mark, the final board and the timeline report; feed, alert",
    "gate": "the item's start and the header's context percent; the │ mark; feed",
    "phase-boundary": "the item's end and the header's spend; the ▲ mark; feed",
    "head-exit": "the followed transcript switches; the ▲ mark; feed, alert",
    "head-successor": "the followed transcript switches; the ↻ mark; feed",
    "head-resumed": "closes an open limit wait; the ↻ mark; feed",
    "stop-condition": "the ✖ mark, and with which=limit it opens the hatched wait; feed, alert",
    "supervisor-stood-down": "the header's supervisor state; the ✖ mark; feed, alert",
    "successor-aborted": "the header's supervisor state; the ✖ mark; feed, alert",
    "supervise": "the header's supervisor state; feed",
    "lane-open": "opens the lane's row, its class, model, effort, cap and transcript; feed",
    "lane-spawned": "the session the wrapper really started under; feed",
    "lane-closed": "closes the lane's row with its cost, turns and exit; feed, alert when the "
                   "exit class is not completed",
    "lane-resumed": "the lane runs again under its new session: ● on the items panel and a bar "
                    "growing again on its timeline row; feed",
    "stall": "a note on the lane's row; feed",
    "unwatched": "a note on the lane's row; feed",
    "observation": "feed, alert when the what matches the alert words",
    "heartbeat": "feed only (deliberately undrawn: a beat every few minutes says nothing new)",
    "grants": "feed only (deliberately undrawn: the grants belong to the fence, not the board)",
    "reflect-inputs": "feed only (deliberately undrawn: a reflection input count)",
    "decision": "feed only (a schema kind no writer emits today)",
    "correction": "feed only (a schema kind no writer emits today)",
    "hold": "feed only (a schema kind no writer emits today)",
}


class Run:
    def __init__(self, run, record, vault):
        self.run = run
        self.record = record
        self.vault = vault
        self.names = {}
        self.pack = ""
        self.events = []
        self.lanes = {}
        self.rebuild(read_events(record))

    def rebuild(self, events):
        self.events = events
        # The plain-lane-run shape: a record the lane wrapper opened, with lane events and no
        # `run-open` (handsoff.py's is_plain_run, the same test on the record's own events).
        # There is no head session, no pack and no items panel; the lanes, the timeline's lane
        # rows and the feed are the whole board.
        self.plain = not any(e.get("event") == "run-open" for e in events)
        if not self.names:
            self.names, self.pack = pack_items(events)
        self.t0 = parse_ts(events[0].get("ts")) if events else None
        self.item_order = sorted(self.names, key=lambda k: int(k[4:]))
        self.item_start, self.item_end, self.gates, self.waits, self.marks = {}, {}, [], [], []
        self.heads, self.meters, self.closed_at = [], [], None
        self.supervisor, self.stopped_note = "-", ""
        self.head_model = None
        current, wait_open = None, None
        for e in events:
            ev, ts = e.get("event"), parse_ts(e.get("ts"))
            lane = self.lanes.get(e.get("lane"))
            if ev == "gate" and e.get("item"):
                current = e["item"]
                if current not in self.item_order:
                    self.item_order.append(current)
                self.item_start.setdefault(current, ts)
                self.gates.append((ts, current, e.get("percent")))
            elif ev == "phase-boundary":
                if e.get("from"):
                    self.item_end[e["from"]] = ts
                if e.get("meter"):
                    self.meters.append(e["meter"])
                current = e.get("to") or current
                if current:
                    self.item_start.setdefault(current, ts)
                    if current not in self.item_order:
                        self.item_order.append(current)
            elif ev == "lane-open" and e.get("lane"):
                new = Lane(e, projects=None)
                new.item = current
                self.lanes[new.name] = new
            elif ev == "lane-spawned" and lane:
                lane.spawned(e)
            elif ev == "lane-closed" and lane:
                lane.close(e)
            elif ev == "lane-resumed":
                if lane:
                    lane.resume(e)
                elif e.get("lane"):                            # a resume without its open in view
                    new = Lane(e, projects=None)
                    new.item = current
                    self.lanes[new.name] = new
            elif ev in ("stall", "unwatched") and lane:
                lane.notes = "%s %s" % (ev, e.get("action") or e.get("silent_s") or "")
            elif ev in ("run-open", "run-resume", "head-successor", "head-resumed"):
                self.heads.append(e)
                # any head start ends an open limit wait: an in-place resume, or the successor the
                # supervisor starts above the 60 % band (run-20260908-n148n147 drew the wait to the
                # close because only head-resumed closed it; register entry 2026-09-09)
                if ev in ("head-resumed", "head-successor", "run-resume") and wait_open:
                    self.waits.append((wait_open, ts))
                    wait_open = None
                model = head_model(e)
                if model:
                    self.head_model = model
            elif ev == "stop-condition" and e.get("which") == "limit":
                wait_open = ts
            elif ev == "run-close":
                self.closed_at = ts
                if e.get("meter"):
                    self.meters.append(e["meter"])
            if ev == "supervise":
                self.supervisor = "supervise %s" % (e.get("mode") or "")
            elif ev == "supervisor-stood-down":
                self.supervisor = "stood down (%s)" % (e.get("reason") or "")
            elif ev == "successor-aborted":
                self.supervisor = "successor aborted (%s)" % (e.get("reason") or "")
            if ev in MARKS and ts:
                self.marks.append((ts, MARKS[ev]))
            if ev in ("stop-condition", "supervisor-stood-down"):
                self.stopped_note = str(e.get("note") or e.get("action") or ev)[:70]
        for lane_obj in self.lanes.values():
            # After every rebuild, so no panel and no count can draw an open lane as running
            # while its recorded processes have gone; the live loop re-probes each frame.
            lane_obj.probe_liveness()
        if wait_open:
            self.waits.append((wait_open, None))               # a wait still open ends at "now"
        if self.closed_at and current:
            self.item_end.setdefault(current, self.closed_at)  # the close ends the item in hand
        if self.closed_at:
            # the close ends every item that ever started (a gate, a boundary or a lane of its
            # own); an item with none of those reads skipped, never pending, once the run is over
            for it in self.item_order:
                if it in self.item_start or any(l.item == it for l in self.lanes.values()):
                    self.item_end.setdefault(it, self.closed_at)
        self.current = current

    # -- state ------------------------------------------------------------------------------

    def now(self):
        return self.closed_at or datetime.now(self.t0.tzinfo if self.t0 else None)

    def state(self, item):
        if item in self.item_end:
            return "done"
        if self.closed_at:
            return "skipped"                                  # the run closed before it started
        return "running" if item == self.current else "pending"

    def head_session(self):
        for e in reversed(self.heads):
            sid = e.get("session_id") or e.get("session")
            if sid:
                return sid
        return None

    def head_transcript(self):
        return head_transcript_for(self.head_session(), self.vault)

    def head_stopped(self):
        """True when the record's last head event is a stop: a `stop-condition` or a
        `supervisor-stood-down` after the last `head-successor` / `head-resumed` (the brief's
        rule for the `r` key). `run-open` and `run-resume` also start a head."""
        starts = ("head-successor", "head-resumed", "run-open", "run-resume")
        stops = ("stop-condition", "supervisor-stood-down")
        last_start = last_stop = -1
        for i, e in enumerate(self.events):
            if e.get("event") in starts:
                last_start = i
            elif e.get("event") in stops:
                last_stop = i
        return last_stop > last_start

    def spend(self):
        if self.plain:
            # A plain record names no head session, so no meter line exists to read: the lanes'
            # own recorded costs are the whole spend, and the count says how many carried one.
            costs = [l.cost for l in self.lanes.values()
                     if isinstance(l.cost, (int, float)) and not isinstance(l.cost, bool)]
            return "lanes $%.2f (%d of %d priced)" % (sum(costs), len(costs), len(self.lanes))
        if not self.meters:
            return "spend not yet metered"
        m = re.search(r"(head \$[\d.]+ · lanes \$[\d.]+ · session \$[\d.]+)", str(self.meters[-1]))
        return m.group(1) if m else str(self.meters[-1])[:48]

    def context_pct(self):
        return self.gates[-1][2] if self.gates else None


def head_model(e):
    """The head's model as the record carries it: a `model` field when a writer adds one, else a
    `model <name>` phrase in the event's own free text (`mechanism`, `head`, `detail`, `out`).
    No such field exists in today's head events, so the caller's fallback is what usually runs."""
    if e.get("model"):
        return str(e["model"])
    for key in ("mechanism", "head", "detail", "note"):
        m = re.search(r"model ([A-Za-z][A-Za-z0-9._-]*)", str(e.get(key) or ""))
        if m:
            return m.group(1)
    return None


# ------------------------------------------------------------------ rendering ---------------

def bar(frac, width):
    n = int(round(max(0.0, min(1.0, frac)) * width))
    return "█" * n + "░" * max(0, width - n)


def item_colour(run, item):
    try:
        return ITEM_COLOURS[run.item_order.index(item) % len(ITEM_COLOURS)]
    except ValueError:
        return WHITE


def row(coloured, width):
    """One boxed line: the caller has already fitted the content to width - 4."""
    pad = max(0, width - 4 - visible_len(coloured))
    return "│ " + coloured + " " * pad + " │"


def section(title, width):
    t = " %s " % title
    return "├" + c(t, GREY, bold=True) + "─" * max(0, width - 2 - len(t)) + "┤"


def items_summary(run):
    """`k/n items done · all done`, or `· m skipped`: the close's one-line verdict on the items.
    A plain record has no items to verdict, and says so rather than reading `0/0 done`."""
    if run.plain:
        return PLAIN_HEADER
    n = len(run.item_order)
    done_n = sum(1 for it in run.item_order if run.state(it) == "done")
    return "%d/%d items done · %s" % (done_n, n, "all done" if done_n == n else "%d skipped" % (n - done_n))


def close_tone(run):
    """The close's colour, one rule for the timeline mark, the header's RUN CLOSED, the overall line
    and the banner: green when every item is done (a plain record has no items to verdict and reads
    green), yellow when the close skipped an item, so a close that skipped an item never reads green
    anywhere. Owner request 2026-09-08: the white close mark did not show a finished run at one look."""
    if run.plain:
        return GREEN
    return GREEN if all(run.state(it) == "done" for it in run.item_order) else YELLOW


def render_close_banner(run, head_turns, report, width):
    """The closing notice printed after the final board: the run's totals in one box. `report`
    is the written timeline report's path, or None under --once, which writes nothing."""
    now = run.now()
    by_exit = {}
    for l in run.lanes.values():
        by_exit[l.exit] = by_exit.get(l.exit, 0) + 1
    lanes = " · ".join("%d %s" % (k_n, k) for k, k_n in sorted(by_exit.items(), key=lambda kv: (-kv[1], kv[0])))
    elapsed = span((now - run.t0).total_seconds()) if run.t0 else "-"
    body = ["closed %s · elapsed %s · %s" % (now.strftime("%H:%M:%S"), elapsed, items_summary(run)),
            "lanes %d: %s" % (len(run.lanes), lanes or "none"),
            "%s · head turns %s" % (run.spend(), head_turns),
            "timeline report: written (its path follows the box)" if report
            else "timeline report: not written (--once)"]
    title = fit(" ■ RUN CLOSED · %s " % run.run, max(0, width - 2))
    lines = ["┌" + c(title, close_tone(run), bold=True) + "─" * max(0, width - 2 - len(title)) + "┐"]
    for i, b in enumerate(body):
        lines.append(row(c(fit(b, max(0, width - 4)), WHITE, bold=(i == 0)), width))
    lines.append("└" + "─" * max(0, width - 2) + "┘")
    if report:
        lines.append("timeline report written to %s" % report)   # never fitted: the path is for copying
    return lines


def render_header(run, width, head_turns):
    now = run.now()
    pct = run.context_pct()
    sid = (run.head_session() or "-")[:8]
    elapsed = span((now - run.t0).total_seconds()) if run.t0 else "-"
    clock = " %s " % now.strftime("%H:%M:%S")
    title = fit(" %s · %s " % ("run console" if run.plain else "hands-off console", run.run),
                max(0, width - 2 - len(clock)))   # a plain lane run is not a hands-off run
    fill = max(0, width - 2 - len(title) - len(clock))
    top = "┌" + c(title, WHITE, bold=True) + "─" * fill + c(clock, GREY) + "┐"
    closed = "  ■ RUN CLOSED" if run.closed_at else ""
    if run.plain:
        # No head session, no context gate and no supervisor on a plain record: the line says the
        # shape rather than printing dashes where a head's figures would sit.
        line = "%s · lanes %d · %s · elapsed %s" % (
            PLAIN_HEADER, len(run.lanes), run.spend(), elapsed)
    else:
        line = "head %s · turn %s · context %s · %s · elapsed %s · supervisor %s" % (
            sid, head_turns, ("%s %%" % pct) if pct is not None else "-", run.spend(), elapsed,
            run.supervisor)
    line = fit(line, max(0, width - 4 - len(closed)))              # the close is never truncated away
    return [top, row(c(line, WHITE) + c(closed, close_tone(run), bold=True), width)]


def render_items(run, width):
    lines, now = [], run.now()
    bw = max(6, min(24, width - 60))
    done_n, frac_sum = 0, 0.0
    for it in run.item_order:
        st = run.state(it)
        lanes = [l for l in run.lanes.values() if l.item == it]
        if st == "done":
            f, done_n = 1.0, done_n + 1
        elif st == "running":
            # a running item's bar is its closed lanes over its lanes, held between 0.05 and 0.9
            # so that no item reads as full before its boundary event says so
            f = min(0.9, max(0.05, sum(1 for l in lanes if l.exit != "running") / len(lanes))) \
                if lanes else 0.1
        else:
            f = 0.0
        frac_sum += f
        start, end = run.item_start.get(it), run.item_end.get(it)
        # a pending item shows no clock: a record that skipped a boundary can leave a start behind
        dur = span(((end or now) - start).total_seconds()) if start and st != "pending" else ""
        marks = " ".join(("●" if l.exit == "running" else "✓" if l.exit == "completed" else "✗")
                         + l.name for l in sorted(lanes, key=lambda x: x.opened or now))
        colour = item_colour(run, it) if st not in ("pending", "skipped") else DIM
        used = 6 + 1 + ITEM_NAME_W + 1 + bw + 1 + 9 + 1 + 7 + 2
        coloured = "%s %s %s %s %s  %s" % (
            c("%-6s" % it, colour, bold=st == "running"),
            c("%-*s" % (ITEM_NAME_W, fit(run.names.get(it, ""), ITEM_NAME_W)), colour),
            c(bar(f, bw), colour), c("%-9s" % st, GREEN if st == "done" else
                                     YELLOW if st == "running" else DIM),
            c("%7s" % dur, GREY), c(fit(marks, max(0, width - 4 - used)), WHITE))
        lines.append(row(coloured, width))
    total = len(run.item_order) or 1
    summary, tone = " %d/%d items done" % (done_n, total), GREY
    if run.closed_at:
        # the close has the last word: every item is done or was never started, and the line says
        # which, in green when nothing was skipped
        summary, tone = " " + items_summary(run) + " ■ RUN CLOSED", close_tone(run)
    # the overall label spans the item and name columns, so its bar starts under the item bars
    lines.append(row(c("%-*s" % (6 + 1 + ITEM_NAME_W, "overall"), WHITE, bold=True) + " "
                     + c(bar(frac_sum / total, bw), tone if run.closed_at else WHITE)
                     + c(summary, tone, bold=bool(run.closed_at)), width))
    return lines


def render_lanes(run, width):
    now = run.now()
    lanes = [l for l in run.lanes.values() if l.item == run.current] or \
        sorted(run.lanes.values(), key=lambda x: x.opened or now)[-4:]
    if not lanes:
        return [row(c("no lanes yet", DIM), width)]
    lines = []
    for l in sorted(lanes, key=lambda x: x.opened or now):
        col = CLASS_COLOUR.get(l.cls, WHITE)
        if l.exit == "running":
            mark, state = c("●", YELLOW, bold=True), "running"
        elif l.exit == "completed":
            mark, state = c("✓", GREEN, bold=True), "completed"
        else:
            mark, state = c("✗", RED, bold=True), l.exit
        elapsed = span(((l.closed or now) - l.opened).total_seconds()) if l.opened else "-"
        turns = l.turns_final if l.turns_final is not None else l.turns
        cost = ("$%.2f" % l.cost) if isinstance(l.cost, (int, float)) else (
            "cap $%s" % l.budget if l.budget is not None else "")
        name, model = fit(l.name, LANE_NAME_W), fit(l.model + "·" + l.effort, 11)
        stem = "%s %-*s %-9s %-11s %7s %4s turns %8s " % (
            "•", LANE_NAME_W, name, fit(l.cls, 9), model, elapsed, turns, cost)
        left = "%s %s %s %s %s %s %s " % (
            mark, c("%-*s" % (LANE_NAME_W, name), col, bold=l.exit == "running"),
            c("%-9s" % fit(l.cls, 9), col), c("%-11s" % model, GREY),
            c("%7s" % elapsed, GREY), c("%4s turns" % turns, GREY), c("%8s" % cost, GREY))
        if l.exit == "running":
            tail = l.last_call or l.notes
        elif l.exit == "dead":
            # No lane-closed will ever arrive for this one: the row says why it stopped moving
            # rather than the reason it was opened for.
            tail = "dead · %s" % (l.notes or "no close event")
        else:
            tail = "%s%s" % (state, (" · " + l.reason) if l.reason else "")
        tail = fit(tail, max(0, width - 4 - len(stem)))
        lines.append(row(left + c(tail, WHITE if l.exit == "running" else DIM), width))
    return lines


def render_timeline(run, width, for_report=False):
    """A chart: a label column, then one character per time slice from the run's opening to now."""
    tw = width - 4 - LANE_NAME_W - 1
    if tw < TIMELINE_MIN_W or not run.t0:
        return [row(c("timeline needs a wider terminal", DIM), width)]
    end, lines = run.now(), []
    total = max(60.0, (end - run.t0).total_seconds())

    def col_of(ts):
        if ts is None:
            return tw - 1
        return int(min(tw - 1, max(0, (ts - run.t0).total_seconds() / total * (tw - 1))))

    axis = [" "] * tw
    # One tick per quarter hour under three hours, per half hour under eight, else hourly: at
    # ~100 slices that keeps ticks ~8 columns apart, wide enough for the five-character label.
    step = 900 if total <= 3 * 3600 else 1800 if total <= 8 * 3600 else 3600
    t = run.t0.replace(minute=(run.t0.minute // 15) * 15, second=0, microsecond=0)
    while (t - run.t0).total_seconds() < total:
        if (t.minute * 60) % step == 0 and t >= run.t0:
            k, label = col_of(t), t.strftime("%H:%M")
            if k + len(label) <= tw and all(axis[k + i] == " " for i in range(len(label))):
                for i, ch in enumerate(label):
                    axis[k + i] = ch
        t = t + timedelta(minutes=15)
    lines.append(row(c("%-*s" % (LANE_NAME_W, ""), DIM) + " " + c("".join(axis), GREY), width))

    cells = [(" ", DIM)] * tw
    for it in run.item_order:
        s, e = run.item_start.get(it), run.item_end.get(it)
        if not s or (not e and run.state(it) != "running" and not run.closed_at):
            continue
        for k in range(col_of(s), col_of(e) + 1):
            cells[k] = ("█", item_colour(run, it))
    for s, e in run.waits:                                     # a limit wait hatches over the item
        for k in range(col_of(s), col_of(e) + 1):
            cells[k] = ("░", GREY)
    for ts, kind in run.marks:
        cells[col_of(ts)] = (MARK_GLYPH[kind], RED if kind == "stop" else
                             GREEN if kind == "resume" else
                             close_tone(run) if kind == "close" else WHITE)
    if not run.plain:      # no head ran on a plain record: the lane rows are the whole chart
        lines.append(row(c("%-*s" % (LANE_NAME_W, "head"), WHITE, bold=True) + " "
                         + "".join(c(ch, col, bold=ch == MARK_GLYPH["close"]) for ch, col in cells),
                         width))
    for l in sorted(run.lanes.values(), key=lambda x: x.opened or end):
        col = CLASS_COLOUR.get(l.cls, WHITE)
        k0, k1 = col_of(l.opened), col_of(l.closed)
        body = [" "] * tw
        for k in range(k0, k1 + 1):
            body[k] = "█" if l.exit in ("running", "completed") else "▒"
        if l.closed:
            body[k1] = "✓" if l.exit == "completed" else "✗"
        elif not run.closed_at:
            body[k1] = "▶"
        body_colour = col if l.exit in ("running", "completed") else RED
        lines.append(row(c("%-*s" % (LANE_NAME_W, fit(l.name, LANE_NAME_W)), col,
                           bold=l.exit == "running") + " "
                         + c("".join(body), body_colour,
                             dim=not for_report and l.exit != "running"), width))
    legend = fit("legend: █ item or lane · │ gate · ▲ boundary · ░ limit wait · ✖ stop · ↻ resume"
                 " · ■ close · ▶ running · ✓ completed · ✗ other", width - 4)
    lines.append(row(c(legend, GREY), width))
    return lines


def fmt_event(e):
    lane = (" " + e["lane"]) if e.get("lane") else ""
    extra = ""
    for k in ("item", "to", "from", "what", "reason", "exit_class", "total_cost_usd",
              "disposition", "which", "action", "mode", "note", "class", "target", "phase"):
        if e.get(k) is not None:
            v = e[k]
            if isinstance(v, float):
                v = "%.2f" % v
            extra += " %s=%s" % (k, str(v).replace("\n", " ")[:160])
    return "%s  %-7s %s%s%s" % (hms(e.get("ts")), "RECORD", e.get("event"), lane, extra)


def is_alert(e):
    ev = e.get("event", "")
    if ev in ALERT_EVENTS:
        return True
    if ev == "lane-closed" and (e.get("exit_class") or "completed") != "completed":
        return True
    return ev == "observation" and bool(ALERT_WORDS.search(str(e.get("what", ""))))


def transcript_rows(line):
    """The head's own prose and tool calls, from one transcript line."""
    try:
        r = json.loads(line)
    except ValueError:
        return []
    if r.get("type") != "assistant":
        return []
    ts, out = r.get("timestamp"), []
    for blk in (r.get("message") or {}).get("content") or []:
        if not isinstance(blk, dict):
            continue
        if blk.get("type") == "text" and blk.get("text", "").strip():
            out.append((epoch(ts), "head",
                        "%s  %-7s %s" % (hms(ts), "HEAD", blk["text"].strip().replace("\n", " "))))
        elif blk.get("type") == "tool_use":
            out.append((epoch(ts), "tool", "%s  %-7s %s" % (hms(ts), str(blk.get("name", "tool"))[:7],
                                                            tool_target(blk))))
    return out


def colour_feed(kind, text, width):
    text = fit(text, width - 4)
    if kind == "alert":
        return c(text, RED, bold=True)
    if kind == "head":
        return c(text[:18], GREY) + c(text[18:], WHITE)
    if kind == "tool":
        return c(text[:18], GREY) + c(text[18:], CYAN)
    return c(text, GREY)


def render(run, feed, head_turns, width, height, for_report=False):
    if width < 40:                                             # too narrow for the box: plain rows
        out = ["%s %s" % (run.run, run.now().strftime("%H:%M:%S"))]
        for it in run.item_order:
            out.append(fit("%s %s" % (it, run.state(it)), width))
        return [fit(line, width) for line in out]
    lines = render_header(run, width, head_turns)
    if not run.plain:      # a plain record has no pack and no gates: no items panel at all
        lines.append(section("items", width))
        lines += render_items(run, width)
    lines.append(section("lanes now", width))
    lines += render_lanes(run, width)
    lines.append(section("timeline", width))
    lines += render_timeline(run, width, for_report)
    if not for_report:
        lines.append(section("feed", width))
        room = max(3, height - len(lines) - 2)
        for _, kind, text in list(feed)[-room:]:
            lines.append(row(colour_feed(kind, text, width), width))
    lines.append("└" + "─" * (width - 2) + "┘")
    return lines


# ------------------------------------------------------------------ following ---------------

def follow(path, pos):
    """New text since pos, and the new position. A file that shrank is read from its start."""
    if not path or not os.path.isfile(path):
        return [], pos
    try:
        if os.path.getsize(path) < pos:
            pos = 0
        with open(path, encoding="utf-8", errors="replace") as fh:
            fh.seek(pos)
            data = fh.read()
            return data.splitlines(), fh.tell()
    except OSError:
        return [], pos


def notify(title, text, enabled):
    """A macOS notification for an alert. Off under --no-notify, off under AIMYTH_WATCH_NOTIFY=0
    (which every suite leg sets), and absent on any other platform."""
    if not enabled or sys.platform != "darwin" or os.environ.get("AIMYTH_WATCH_NOTIFY") == "0":
        return False
    try:
        subprocess.run(["osascript", "-e", 'display notification "%s" with title "%s"'
                        % (text.replace('"', "'")[:NOTIFY_CHARS], title.replace('"', "'"))],
                       timeout=5, capture_output=True)
        return True
    except Exception:
        return False


# ------------------------------------------------------------------ keys --------------------

def resume_command(run, model):
    """`handsoff.py resume-head` for the head this record last ran, overridable so a suite can
    stub it. The interpreter is this one (handsoff.py re-invokes itself the same way)."""
    override = os.environ.get("AIMYTH_WATCH_RESUME_CMD")
    base = shlex.split(override) if override else [
        sys.executable, "-B", os.path.join(HERE, "handsoff.py"), "resume-head"]
    return base + ["--run", run, "--model", model, "--effort", "max"]


def handle_key(key, run, fallback_model="fable"):
    """(quit, feed lines). `q` quits; `r` resumes only a stopped head."""
    if key in ("q", "Q"):
        return True, ["quit"]
    if key not in ("r", "R"):
        return False, []
    if not run.head_stopped():
        return False, ["head is running — `r` does nothing (the last head event is not a stop)"]
    cmd = resume_command(run.run, run.head_model or fallback_model)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        out = (p.stdout or p.stderr or "").strip().splitlines()
        return False, ["resume-head: exit %d" % p.returncode] + out[:3]
    except Exception as exc:
        return False, ["resume-head failed: %s" % exc]


def read_key(timeout):
    """A keystroke if one is waiting, else None. Only a tty is polled; otherwise this is a sleep."""
    if not sys.stdin.isatty():
        time.sleep(timeout)
        return None
    try:
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
    except (OSError, ValueError):
        time.sleep(timeout)
        return None
    if not ready:
        return None
    try:
        return sys.stdin.read(1)
    except (OSError, ValueError):
        return None


# ------------------------------------------------------------------ the close report --------

def write_report(run, head_turns):
    """The console's one write: the board, the timeline and a per-lane table, in plain text."""
    global USE_COLOUR
    keep, USE_COLOUR = USE_COLOUR, False
    path = report_path(run.run)
    try:
        lines = render(run, deque(), head_turns, REPORT_WIDTH, REPORT_HEIGHT, for_report=True)
        lines.append("")
        lines.append("lane · class · model·effort · opened · closed · duration · turns · cost · exit")
        for l in sorted(run.lanes.values(), key=lambda x: x.opened or run.now()):
            turns = l.turns_final if l.turns_final is not None else l.turns
            lines.append("%s · %s · %s·%s · %s · %s · %s · %s · %s · %s" % (
                l.name, l.cls, l.model, l.effort,
                l.opened.strftime("%H:%M:%S") if l.opened else "-",
                l.closed.strftime("%H:%M:%S") if l.closed else "-",
                span(((l.closed or run.now()) - l.opened).total_seconds()) if l.opened else "-",
                turns, ("$%.2f" % l.cost) if isinstance(l.cost, (int, float)) else "-", l.exit))
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    finally:
        USE_COLOUR = keep
    return path


# ------------------------------------------------------------------ the session's jobs ------
# The attended-session view (A4): one row per background job of an attended harness session, read
# from two observables only — the session's transcript and the harness's per-session job directory.
# Shape A: everything below is observed. Nothing here asks the head to declare a job, and no new
# event is written; where an observable cannot carry a denominator the row says so rather than
# guessing one.

TASKS_ROOT_ENV = "AIMYTH_TASKS_ROOT"    # the suite's override; unset, the root is composed below
TASKS_DIR = "tasks"                     # <root>/<dashed cwd>/<session>/tasks/<job id>.output
OUTPUT_SUFFIX = ".output"
SUITE_TOTALS_FILE = "watch-suite-totals.json"   # the per-suite denominator cache, under state_dir()

JOB_TAIL_BYTES = 65536  # bytes of a job's output read for its last non-empty line and its `ok`
                        # count; a bound on a job's OUTPUT file, distinct from the status hook's
                        # transcript-tail bound (JOBS_TAIL_BYTES, 512 KB, role-style-anchor.py,
                        # re-derived 2026-09-08 by lane B-JOBS). A suite's 48 `ok` lines are
                        # ~5 KB, so the count is exact for every suite in this skill; a job whose
                        # output is larger has its earlier `ok` lines outside the window and its
                        # bar reads low rather than wrong — stated in the header when it bites.
JOB_LAST_LINE_W = 48    # the last-line column: the widest that leaves the bar column whole at the
                        # 120-column default terminal (kind 8 + id 11 + started 17 + state 9 + bar 20)
JOB_ID_W = 18           # the longest job id observed is 17 characters (an agent id); a Bash id is 9
JOB_BAR_W = 14          # the bar itself, matching the run console's lane bars

# The four start shapes an attended session writes, each measured on a live transcript
# (2026-09-08).  A job reaches the job directory by any of them, and only the first carries
# `run_in_background` on the tool call — a foreground Bash command that outruns its timeout is
# *moved* to the background and is a job like any other, with no flag anywhere on the tool_use.
#
# Each pattern is ANCHORED at the start of the tool_result's text, because the harness writes its
# start sentence first and nothing else does: the same sentence inside a tool's output, in
# assistant prose or in a quoted brief is somebody talking ABOUT a job, never a start. Measured on
# 469 live transcripts, 2026-09-08: unanchored, `Monitor started (task …)` matched 10 texts, every
# one of them another tool's output (a grep, a file read, a probe's own summary) and not one a
# start; a grep over a second session's transcript put a phantom row on the operator's own board.
# Route 4's leading sentence is the launch line and the id sits on a line of its own inside the
# same text (231 live occurrences), so it takes an id pattern beside its anchor.
JOB_START_RES = (
    # (the anchor at the text's start, the id pattern within it or None for the anchor's group 1)
    (re.compile(r"^Command running in background with ID: ([A-Za-z0-9]+)"), None),
    (re.compile(r"^Command did not complete within its \S+ timeout and was moved to the "
                r"background \(ID: ([A-Za-z0-9]+)\)"), None),
    (re.compile(r"^Monitor started \(task ([A-Za-z0-9]+)"), None),
    (re.compile(r"^Async agent launched successfully\."),
     re.compile(r"^agentId: ([0-9a-f]{8,})", re.M)),
)
JOB_NOTIF_OPEN = "<task-notification>"
JOB_NOTIF_ID = re.compile(r"<task-id>([^<]*)</task-id>")
JOB_NOTIF_STATUS = re.compile(r"<status>([^<]*)</status>")

# Kind by the command, in this precedence.  The tool decides first where the tool is the whole
# fact (Monitor is a waiter whatever it waits on; the Agent tool is an agent), then the command's
# own words.  `suite` before `lane` because a lane's spawn command never names a suite file while
# a suite's command may name lane.py; `waiter` last of the command rules because a suite that
# sleeps between legs is still a suite.
#
# Each script name may be followed by a closing quote: an operator's command quotes the script's
# path (`python3 -B "…/lane.py" watch --run …`), and without the optional quote every real lane
# watch of one live operator session read `other` (7 of 7 measured, 2026-09-08). The
# same three strings are shared verbatim with the status-line hook's `_jobs_kind`.
JOB_SUITE_RE = re.compile(r"\btest_[A-Za-z0-9_]+\.sh\b")
JOB_LANE_RE = re.compile(r"""lane\.py["']?\s+(?:\S+\s+)*?(?:watch|spawn|resume)\b""")
JOB_WAITER_RE = re.compile(r"""\bsleep\b|\bwait-reset\b|handsoff\.py["']?\s+watch\b|"""
                           r"""watch\.py["']?\s+--(?:run|session)\b""")
JOB_KINDS = ("suite", "lane", "waiter", "agent", "other")   # the fixed order every count prints in
JOB_RUN_RE = re.compile(r"--run\s+(\S+)")
JOB_LANE_NAME_RE = re.compile(r"--lane\s+(\S+)")
SUITE_FINAL_RE = re.compile(r"^\s*(?:PASS|FAIL)\s+(\d+)\s*/\s*(\d+)\s*$")
SUITE_OK_RE = re.compile(r"^\s*ok\b")


def tasks_root():
    """The harness's job root: `<TASKS_ROOT_ENV>`, else `/tmp/claude-<uid>` composed from this
    process's own uid — the shape a live root was read at on 2026-09-08 (`/tmp` is the symlink
    macOS resolves to `/private/tmp`, so both spellings reach the same directory). The uid is
    never a literal: a copy of this console run by another account finds that account's root."""
    env = os.environ.get(TASKS_ROOT_ENV)
    if env:
        return os.path.realpath(os.path.expanduser(env))
    return os.path.join("/tmp", "claude-%d" % os.getuid())


def session_tasks_dir(cwd, sid):
    """`<root>/<dashed working directory>/<session>/tasks`. The working directory is the
    transcript's own `cwd` field, never this console's: the view is of the session being watched,
    which is normally not the one this console runs in."""
    if not cwd or not sid:
        return ""
    return os.path.join(tasks_root(), dashed(cwd), sid, TASKS_DIR)


def resolve_session(sid, vault):
    """A full transcript stem, or a unique prefix of one, to (path, stem).

    fable-share.py `resolve_short_session`: the vault's own project directory first, then every
    project directory under the projects root. Exactly one hit resolves; zero or several is a
    broken premise named with its count, never a guess between transcripts."""
    root = projects_root()
    direct = os.path.join(root, dashed(vault), "%s.jsonl" % sid)
    if os.path.isfile(direct):
        return direct, sid
    for pattern in (os.path.join(root, dashed(vault), sid + "*.jsonl"),
                    os.path.join(root, "*", sid + "*.jsonl")):
        hits = sorted(globmod.glob(pattern))
        if len(hits) == 1:
            return hits[0], os.path.basename(hits[0])[:-len(".jsonl")]
        if hits:
            die("%d sessions match %s" % (len(hits), sid))
    die("no transcript for %s" % sid)


def notif_texts(rec):
    """Every string of a record that can carry a `<task-notification>`.

    Measured on a live transcript (2026-09-08): the eleven notifications of one session sat in
    three carriers — a `user` record's `message.content`, a `queue-operation` record's top-level
    `content`, and an `attachment` record's `attachment.prompt`. Reading the user records alone
    saw one of the four notified jobs, so all three are read and the ids de-duplicated."""
    out = []
    if isinstance(rec.get("content"), str):
        out.append(rec["content"])
    body = (rec.get("message") or {}).get("content")
    if isinstance(body, str):
        out.append(body)
    elif isinstance(body, list):
        out.extend(b["text"] for b in body
                   if isinstance(b, dict) and isinstance(b.get("text"), str))
    att = rec.get("attachment")
    if isinstance(att, dict):
        out.extend(v for v in att.values() if isinstance(v, str))
    return out


def result_texts(blk):
    """A tool_result's text, whichever of the two shapes it carries (a string, or the list of
    content blocks the Agent tool answers with)."""
    body = blk.get("content")
    if isinstance(body, str):
        return [body]
    if isinstance(body, list):
        return [b["text"] for b in body if isinstance(b, dict) and isinstance(b.get("text"), str)]
    return []


def start_id(text):
    """The job id a tool_result's text starts a job with, or "".

    The text must BEGIN with one of the harness's start sentences (leading whitespace aside).
    The sentence anywhere else in a text — inside another tool's output, inside assistant prose
    quoted back, inside a brief — is a mention, not a start, and mentions have put phantom rows
    on the board with ids read out of somebody else's transcript."""
    if not isinstance(text, str):
        return ""
    head = text.lstrip()
    for anchor, id_re in JOB_START_RES:
        hit = anchor.match(head)
        if not hit:
            continue
        if id_re is None:
            return hit.group(1)
        within = id_re.search(head)
        return within.group(1) if within else ""
    return ""


def job_kind(tool, command, linked=False):
    """The kind of one job. `tool` is the tool that started it, `command` its command (empty for
    an Agent), `linked` whether its output file is a symbolic link into a subagent transcript."""
    if tool == "Agent" or linked:
        return "agent"
    if tool == "Monitor":
        return "waiter"
    text = command or ""
    if JOB_SUITE_RE.search(text):
        return "suite"
    if JOB_LANE_RE.search(text):
        return "lane"
    if JOB_WAITER_RE.search(text):
        return "waiter"
    return "other"


def scan_session(path):
    """One pass over a session's transcript for everything the view needs.

    Returns (jobs, notified, cwd, last_ts, trusted). `jobs` maps job id to its start; `notified`
    maps job id to the status its notification carried; `trusted` is False when a line failed to
    parse after the first start record was seen — a torn or truncated record in the region the
    notifications live in means the absence of one is not evidence that the job still runs, and
    the caller falls back to the output files' mtimes rather than reporting a finished job as
    running."""
    jobs, notified, cwd, last_ts = {}, {}, "", ""
    torn_after_start = False
    uses = {}
    try:
        handle = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return jobs, notified, cwd, last_ts, True
    with handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                if jobs:
                    torn_after_start = True
                continue
            if rec.get("cwd") and not cwd:
                cwd = rec["cwd"]
            if rec.get("timestamp"):
                last_ts = rec["timestamp"]
            for text in notif_texts(rec):
                if JOB_NOTIF_OPEN not in text:
                    continue
                ident, status = JOB_NOTIF_ID.search(text), JOB_NOTIF_STATUS.search(text)
                if ident:
                    notified[ident.group(1)] = (status.group(1) if status else "unknown")
            body = (rec.get("message") or {}).get("content")
            if not isinstance(body, list):
                continue
            for blk in body:
                if not isinstance(blk, dict):
                    continue
                if blk.get("type") == "tool_use":
                    uses[blk.get("id")] = (blk.get("name") or "?",
                                           (blk.get("input") or {}).get("command") or "",
                                           rec.get("timestamp") or "")
                elif blk.get("type") == "tool_result":
                    # A start is a tool_result of a tool_use THIS transcript holds: the id comes
                    # from the leading sentence, and the tool call it answers gives the kind. A
                    # result whose tool_use_id resolves to nothing is not this session's job.
                    if blk.get("tool_use_id") not in uses:
                        continue
                    tool, command, started = uses[blk["tool_use_id"]]
                    for text in result_texts(blk):
                        ident = start_id(text)
                        if ident:
                            jobs[ident] = {"tool": tool, "command": command,
                                           "started": started or rec.get("timestamp") or ""}
                            break
    return jobs, notified, cwd, last_ts, not torn_after_start


def suite_totals_path():
    """The one file this view writes: the per-suite denominator cache, beside the hand-off state
    the rest of the skill keeps (handsoff.py `state_dir()`)."""
    module = handsoff()
    if module is not None and hasattr(module, "state_dir"):
        base = module.state_dir()
    else:
        base = os.path.expanduser(os.environ.get("AIMYTH_STATE_DIR")
                                  or os.path.join("~", ".aimyth", "handoffs"))
    return os.path.join(base, SUITE_TOTALS_FILE)


def load_suite_totals():
    try:
        with open(suite_totals_path(), encoding="utf-8") as fh:
            data = json.load(fh)
        return {k: int(v) for k, v in data.items() if isinstance(v, int)}
    except (OSError, ValueError, AttributeError):
        return {}


def save_suite_totals(totals):
    """Remember each suite's last announced total, so the next run of that suite draws a bar from
    its first leg. A cache that cannot be written costs a bar and nothing else."""
    path = suite_totals_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(totals, fh, indent=1, sort_keys=True)
    except OSError:
        pass


def job_output(path):
    """(last non-empty line, ok count, announced total or None) from a job's output file, read
    from its last JOB_TAIL_BYTES only. A file that vanished between the listing and this read is
    not an error: the harness deletes a foreground capture seconds after it is written."""
    try:
        size = os.path.getsize(path)
        with open(path, encoding="utf-8", errors="replace") as fh:
            if size > JOB_TAIL_BYTES:
                fh.seek(size - JOB_TAIL_BYTES)
            text = fh.read()
    except OSError:
        return "", 0, None
    last, oks, total = "", 0, None
    for line in text.splitlines():
        if line.strip():
            last = line.strip()
        if SUITE_OK_RE.match(line):
            oks += 1
        final = SUITE_FINAL_RE.match(line)
        if final:
            total = int(final.group(2))
    return last, oks, total


def lane_cap(command, vault):
    """(turns, cap) for a `lane.py` job: the lane's live turns as the run console counts them,
    against the cap its `lane-open` recorded. (None, None) where the command names no run, the
    record is absent, or the record carries no `max_turns` — on this store 30 of 215 `lane-open`
    events carried one (2026-09-08), so the honest answer is usually no denominator."""
    run = JOB_RUN_RE.search(command or "")
    want = JOB_LANE_NAME_RE.search(command or "")
    if not run:
        return None, None
    events = read_events(record_path(run.group(1)))
    lane = None
    for e in events:
        if e.get("event") != "lane-open":
            continue
        if want and e.get("lane") != want.group(1):
            continue
        lane = e
    if lane is None or lane.get("max_turns") in (None, 0):
        return None, None
    obj = Lane(lane, lane.get("projects_root"))
    for e in events:
        if e.get("lane") == obj.name and e.get("event") == "lane-spawned":
            obj.spawned(e)
    obj.poll()
    return obj.turns, int(lane["max_turns"])


class SessionJobs:
    """The session's jobs, rebuilt from the transcript and the job directory on every tick."""

    def __init__(self, sid, transcript, vault):
        self.sid, self.transcript, self.vault = sid, transcript, vault
        self.rows, self.counts, self.source = [], {}, "notifications"
        self.tasks, self.tasks_readable, self.no_record = "", True, 0
        self.totals = load_suite_totals()

    def poll(self):
        jobs, notified, cwd, last_ts, trusted = scan_session(self.transcript)
        self.tasks = session_tasks_dir(cwd, self.sid)
        listing, self.tasks_readable = {}, True
        if self.tasks:
            try:
                for name in os.listdir(self.tasks):
                    if name.endswith(OUTPUT_SUFFIX):
                        listing[name[:-len(OUTPUT_SUFFIX)]] = os.path.join(self.tasks, name)
            except OSError:
                self.tasks_readable = False
        self.no_record = sum(1 for ident in listing if ident not in jobs)
        self.source = "notifications" if (trusted or not jobs) else "by mtime"
        cut = epoch(last_ts)
        rows, counts, learnt = [], {}, dict(self.totals)
        for ident in sorted(jobs, key=lambda i: (jobs[i]["started"], i)):
            job = jobs[ident]
            path = listing.get(ident, "")
            linked = bool(path) and os.path.islink(path)
            kind = job_kind(job["tool"], job["command"], linked)
            last, oks, total = job_output(path) if path else ("", 0, None)
            if not self.tasks_readable:
                last = "output: unreadable"
            state = self.state(ident, notified, path, cut)
            bar_text = self.denominator(kind, job, oks, total, learnt)
            counts[kind] = counts.get(kind, 0) + 1
            rows.append({"kind": kind, "id": ident, "started": job["started"], "state": state,
                         "last": last, "bar": bar_text})
        if learnt != self.totals:
            self.totals = learnt
            save_suite_totals(learnt)
        self.rows, self.counts = rows, counts

    def state(self, ident, notified, path, cut):
        """`done` on a completed notification, `stopped` on any other notified status, else
        `running` while the output file is there and `lost` when it is not. Under the by-mtime
        fallback the notifications are not trusted, so the file's own mtime against the
        transcript's last record decides: written since, the job is still writing."""
        if self.source == "notifications":
            if ident in notified:
                return "done" if notified[ident] == "completed" else "stopped"
            return "running" if path else "lost"
        if not path:
            return "lost"
        try:
            return "running" if os.path.getmtime(path) > cut else "done"
        except OSError:
            return "lost"

    def denominator(self, kind, job, oks, total, learnt):
        """The bar column. A suite counts its `ok` lines against the total it last announced,
        cached by suite file name; a lane counts turns against the cap its `lane-open` recorded;
        every other kind has no observable denominator and says so."""
        if kind == "suite":
            name = JOB_SUITE_RE.search(job["command"] or "")
            name = name.group(0) if name else ""
            if total:
                learnt[name] = total
            cap = learnt.get(name)
            if not cap:
                return "no denominator"
            return "%s %d/%d" % (bar(float(oks) / cap, JOB_BAR_W), oks, cap)
        if kind == "lane":
            turns, cap = lane_cap(job["command"], self.vault)
            if not cap:
                return "no denominator"
            return "%s %d/%d turns" % (bar(float(turns) / cap, JOB_BAR_W), turns, cap)
        return "no denominator"


def render_jobs(view, width):
    """The session view's board: a header naming the session, the vault, the counts by kind and
    where the state came from, then one row per job."""
    out = ["┌" + "─" * max(0, width - 2) + "┐"]
    counts = " · ".join("%s %d" % (k, view.counts[k]) for k in JOB_KINDS if view.counts.get(k))
    head = "session %s · jobs %d%s" % (view.sid, len(view.rows), " · " + counts if counts else "")
    out.append(row(c(fit(head, width - 4), WHITE, bold=True), width))
    tail = "vault %s" % view.vault
    if view.no_record:
        tail += " · %d no record" % view.no_record
    if not view.tasks_readable:
        tail += " · output: unreadable"
    out.append(row(c(fit(tail, width - 4), GREY), width))
    out.append(row(c("state: %s" % view.source, YELLOW if view.source != "notifications" else GREY),
                   width))
    out.append(section("jobs", width))
    if not view.rows:
        out.append(row(c("no background jobs", GREY), width))
    for r in view.rows:
        started = hms(r["started"]) if r["started"] else "--:--:--"
        began = epoch(r["started"])
        if began and r["state"] == "running":
            started = "%s +%s" % (started, span(time.time() - began))
        colour = {"done": GREEN, "running": CYAN, "stopped": YELLOW}.get(r["state"], RED)
        line = "%-7s %-*s %-17s %s  %s" % (
            r["kind"], JOB_ID_W, fit(r["id"], JOB_ID_W), started,
            c("%-8s" % r["state"], colour), fit(r["last"], JOB_LAST_LINE_W))
        out.append(row(fit_row(line, r["bar"], width), width))
    out.append("└" + "─" * max(0, width - 2) + "┘")
    return out


def fit_row(line, bar_text, width):
    """The row's fixed columns, then the bar column pushed to the right margin."""
    pad = max(1, width - 4 - visible_len(line) - len(bar_text))
    return line + " " * pad + c(bar_text, GREY if bar_text == "no denominator" else WHITE)


def main_session(a):
    """`--session`: the attended-session view. One snapshot under `--once`, else the same live
    loop and the same key handling as the run console (`q` quits, no other key acts)."""
    vault = vault_root(a.vault)
    transcript, sid = resolve_session(a.session, vault)
    if not os.path.isfile(transcript):
        die("no transcript for %s" % a.session)
    view = SessionJobs(sid, transcript, vault)
    view.poll()
    if not view.rows:
        print("no background jobs")
        return 0

    def frame():
        size = shutil.get_terminal_size((120, 40))
        return render_jobs(view, min(max(1, size.columns), MAX_WIDTH))

    if a.once:
        print("\n".join(frame()))
        return 0
    raw = None
    if sys.stdin.isatty():
        try:
            import termios
            import tty
            raw = (termios, sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno()))
            tty.setcbreak(raw[1])
        except Exception:
            raw = None
    if not a.plain:
        sys.stdout.write("\x1b[?1049h\x1b[?25l")
    try:
        while True:
            sys.stdout.write(("\x1b[2J\x1b[H" if not a.plain else "") + "\n".join(frame()) + "\n")
            sys.stdout.flush()
            key = read_key(a.refresh)
            if key in ("q", "Q"):
                break
            view.poll()
    except KeyboardInterrupt:
        pass
    finally:
        if raw is not None:
            raw[0].tcsetattr(raw[1], raw[0].TCSADRAIN, raw[2])
        if not a.plain:
            sys.stdout.write("\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()
    print("\n".join(frame()))
    return 0


# ------------------------------------------------------------------ main --------------------

def die(reason):
    sys.stderr.write("watch.py: PROBE FAILED: %s\n" % reason)
    sys.exit(2)


def build_feed(run):
    feed = deque(maxlen=FEED_MAX)
    for e in run.events:
        feed.append((epoch(e.get("ts")), "alert" if is_alert(e) else "record", fmt_event(e)))
    return feed


def main(argv=None):
    global USE_COLOUR
    ap = argparse.ArgumentParser(description="a read-only console for a hands-off run")
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("--run", help="a hands-off run: the run console")
    what.add_argument("--session", help="an attended session's transcript stem, or a unique "
                                        "prefix of one: the background-job view")
    ap.add_argument("--once", action="store_true", help="print one snapshot and exit")
    ap.add_argument("--plain", action="store_true", help="no colour, no screen switching")
    ap.add_argument("--no-notify", action="store_true", help="no macOS notification on an alert")
    ap.add_argument("--refresh", type=float, default=2.0,
                    help="seconds between reads (default 2: the record appends minutes apart, "
                         "the clock and the lane bars move every tick)")
    ap.add_argument("--vault", default=None,
                    help="the vault root (default: CLAUDE_PROJECT_DIR, else three levels up)")
    a = ap.parse_args(argv)

    USE_COLOUR = not a.plain and (sys.stdout.isatty()
                                  or os.environ.get("AIMYTH_WATCH_COLOUR") == "1")
    if a.session:
        return main_session(a)

    vault = vault_root(a.vault)
    record = record_path(a.run)
    if not os.path.isfile(record):
        die("no run record at %s" % record)
    run = Run(a.run, record, vault)
    # The items premise belongs to a record that HAS a run-open: only such a record names a pack
    # to take items from. A plain record (no run-open) is watched on its lane events, and its own
    # premise is that it holds some — an empty file is still a broken premise.
    if run.plain:
        if not run.lanes:
            die("no run-open, no lane-open and no lane-closed event in %s: a plain lane run is "
                "watched on its lane events and this record holds none" % record)
    elif not run.item_order:
        die("no items in %s and no gate events in %s" % (run.pack or "(no pack in run-open)", record))

    USE_COLOUR = not a.plain and (sys.stdout.isatty()
                                  or os.environ.get("AIMYTH_WATCH_COLOUR") == "1")
    notify_on = not a.no_notify

    feed = build_feed(run)
    transcript = run.head_transcript()
    rows, tpos = follow(transcript, 0)
    head_turns = 0
    for line in rows:
        for item in transcript_rows(line):
            feed.append(item)
        if '"type":"assistant"' in line or '"type": "assistant"' in line:
            head_turns += 1
    feed = deque(sorted(feed, key=lambda r: r[0]), maxlen=FEED_MAX)
    for l in run.lanes.values():
        l.poll()
    rpos = os.path.getsize(record)

    def frame():
        size = shutil.get_terminal_size((120, 40))
        return render(run, feed, head_turns, min(max(1, size.columns), MAX_WIDTH), size.lines)

    if a.once:
        print("\n".join(frame()))
        if run.closed_at:
            width = min(max(1, shutil.get_terminal_size((120, 40)).columns), MAX_WIDTH)
            print("\n".join(render_close_banner(run, head_turns, None, width)))
        return 0

    raw = None
    if sys.stdin.isatty():
        try:
            import termios
            import tty
            raw = (termios, sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno()))
            tty.setcbreak(raw[1])
        except Exception:
            raw = None
    if not a.plain:
        sys.stdout.write("\x1b[?1049h\x1b[?25l")
    try:
        sys.stdout.write(("\x1b[2J\x1b[H" if not a.plain else "") + "\n".join(frame()) + "\n")
        sys.stdout.flush()
        while not run.closed_at:
            key = read_key(a.refresh)
            if key:
                quit_now, said = handle_key(key, run)
                for line in said:
                    feed.append((time.time(), "record", "%s  %-7s %s"
                                 % (time.strftime("%H:%M:%S"), "KEY", line)))
                if quit_now:
                    break
            new, rpos = follow(record, rpos)
            if new:
                run.rebuild(read_events(record))
                for line in new:
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    alert = is_alert(e)
                    feed.append((epoch(e.get("ts")), "alert" if alert else "record", fmt_event(e)))
                    if alert:
                        text = fmt_event(e)[10:]
                        if e.get("event") == "run-close":       # the close says how it ended
                            text = "run closed · %s · %s" % (items_summary(run), run.spend())
                        notify("hands-off %s" % a.run, text, notify_on)
                    if e.get("event") in ("head-successor", "head-resumed", "head-exit",
                                          "run-resume"):
                        transcript, tpos = run.head_transcript(), 0
                        head_turns = 0
            new, tpos = follow(transcript, tpos)
            for line in new:
                for item in transcript_rows(line):
                    feed.append(item)
                if '"type":"assistant"' in line or '"type": "assistant"' in line:
                    head_turns += 1
            for l in run.lanes.values():
                if l.exit == "running":
                    l.poll()
                    l.probe_liveness()             # a lane can die between two frames
            sys.stdout.write(("\x1b[2J\x1b[H" if not a.plain else "") + "\n".join(frame()) + "\n")
            sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    finally:
        if raw is not None:
            raw[0].tcsetattr(raw[1], raw[0].TCSADRAIN, raw[2])
        if not a.plain:
            sys.stdout.write("\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()
    print("\n".join(frame()))                                  # the final board stays in scrollback
    if run.closed_at:
        report = write_report(run, head_turns)
        width = min(max(1, shutil.get_terminal_size((120, 40)).columns), MAX_WIDTH)
        print("\n".join(render_close_banner(run, head_turns, report, width)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
