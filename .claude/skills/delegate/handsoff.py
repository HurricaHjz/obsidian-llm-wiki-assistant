#!/usr/bin/env python3
"""handsoff.py — the hands-off run's head-side primitives (delegate skill, hands-off mode).

One script, one line per action; every write is a record event or a named hand-off section.
Run store: LLM_WIKI_STORE (default ~/.llm-wiki, resolved to its real path), file
spawn-records/<run>.jsonl; the hand-off document is the path the run's run-open event names.
Design: wiki/developments/hands-off-mode-design.md (D4, D5, D13, D21, the trace and boundary
schema, the context bands, the account plan) plus the critic amendments in the builder brief.

Subcommands
  run-open     record the run's opening: session, head, regime, hand-off path, envelope, pid,
               and --session-kind seed|head written as `session_kind` (default head; seed marks
               a launcher's placeholder session, which no reader counts as a head that ran);
               writes the grants file and the state directory's run-<sid> pointer (D34), and
               opens the console window unless --viewer none (the console window below)
  run-resume   a later head (a successor, or a pasted resume prompt) records itself likewise,
               and writes the same two files
  boundary     meter, compute the five waste fields, measure the head's context, append the
               phase-boundary event, add the trace row, refresh the morning report's figures,
               checkpoint-commit (--commit MSG)
  ledger       one row in the hand-off's findings ledger plus an observation event;
               `--observation "<what>"` instead appends the observation alone, with no ledger
               row, to any record that exists (the plain-lane-run shape below)
  gate         band and envelope check before an item: a gate event; exit 4 when armed at or
               above the second edge (stop-condition band); exit 5 with stop-condition
               `which: envelope` when the run's spend has reached run-open's envelope_usd
               (the envelope policy below); the unmetered policy below; the first gate
               of a session records the orientation cost (D41), null after a resume — a
               head-resumed event, or a run-resume naming the session of the head event before
               it WHEN that session already gated, either of which leaves the whole session in
               the transcript's first call (a successor's own first gate stays measured)
  handoff      rewrite named sections or morning-report bullets, atomically; --final records
               head-exit with --band and requires the next-task pack (D41), and prints the pid
               it wrote and why (pid discovery below). --inflight and
               --inflight-file stamp the pack with its age; --inflight-from-record re-derives
               `## In flight` from the run record (the pack-age guard below)
  successor    called BY the exiting head: sizes the cap from the envelope minus recorded spend
               when the record's last head-exit is a seed exit (`budget_src: envelope (seed)`,
               register entry 2026-09-07, since a seed session has no transcript to meter);
               records head-exit when missing, then starts a
               DETACHED starter that waits for the predecessor to die, starts the successor
               head (claude -p, the resume prompt on standard input) and stays as its
               supervisor (D30); returns at once
  supervise    attach the same supervisor to a head already running (the head calls it about
               itself); detaches at once and returns one line
  resume-head  after a limit the run stood down on (D42): resume the record's last head in
               place, armed, evented and supervised (the owner's command after the reset);
               detaches at once
  watch        the read-only console for a run: header, items, lanes, timeline, feed; `q` quits
               and `r` resumes a stopped head. Writes only the timeline report, at the close
  heartbeat    an attended head's idle-cache beat (D32): a background call that returns after
               --minutes with one line, so the harness's re-invocation refreshes the cache;
               never for a -p head, which has no idle state
  wait-reset   the supervisor's reset wait as a command, kept for --dry-run parser checks and
               for a hand-run wait; no longer a head-side blocking call (D28). It sleeps to the
               reset time the stop text names and sends no probe unless --probe is passed
  close        final meter, run-close, the heartbeat stop marker, commit and push on grant; on a
               plain record (below) the run-close is written from the lane events alone
  waste-table  Step 2b's usage-and-waste table rendered from the run record alone (D36)
  extract-transcript
               the head's own transcript extracted for a reflector lane (D36)
  reflect-inputs
               that reflector lane's whole input set in one directory: the extraction, the
               waste table and a filtered copy of the run record (D36)

The plain-lane-run shape. A record opened by the lane wrapper alone carries lane events and no
`run-open`: an attended session spawned lanes, so there is no hands-off run, no head session on
the record, no envelope and no hand-off document. Three primitives accept it, and the test is
always the record's own events, never the run's name. `ledger --observation "<what>"` appends one
observation and no ledger row; the plain `ledger` still refuses (no hand-off to write a row in)
and its refusal names `--observation`. `close` writes a `run-close` carrying `shape:
"plain-lane-run"`, the lanes counted by exit class and the spend summed from the `lane-closed`
events' own costs, with no head meter, no hand-off rewrite and no hand-off row; `--commit` and
`--push` are refused there (exit 2, nothing written), since neither has a head's grant behind it.
`watch --run` renders the lanes, the timeline and the feed with no items panel. Every other
primitive needs the head a `run-open` names and refuses as before.

The boundary reflection (D36). At a hands-off boundary the head reflects in a lane rather than
in its own context, and two primitives feed that lane. `waste-table --run R` renders the reflect
skill's Step 2b table from `<store>/spawn-records/<run>.jsonl` — no recalled figure, and the one
meter call is the whole-run rows' own (T6 of the token-efficiency findings, 2026-09-07: each head
metered over the RUN's window, run-open to run-close or to the record's last event, by the
meter's `--start`/`--end`, so a session shared with attended work is never counted whole against
one run; `--no-meter` renders from the record alone and `--meter-line SID=LINE` stands in for one
head). Where that meter gives no figure a head's row falls back to the LATER of its last boundary
billed line and its `head-exit.spent_usd`, so a head that exited without a boundary loses no
spend, and the envelope base is printed beside the total (register entry 2026-09-06). Head
sessions are counted by distinct session id, a session `run-open --session-kind seed` marks is
skipped as a launcher's placeholder and named once in the header's `seed (skipped)` line (T7),
and a recorded limit wait (stop-condition to head-resumed) takes a structural row of its own. The
rest is read from fields: one row per waste field per phase-boundary event (each naming its event
by from → to and timestamp) — the over-cap row carrying the CUT TAIL alone, the words above the
800-word cap at 1.3 tokens per word (judgement, unmeasured) and the lane's model's output rate
from prices.json, never the lane's whole cost (T8) — the billed line at every boundary, context
per item as the delta between consecutive gate events, the
orientation cost per head from the first gate's `orientation_tokens` (D41), and the lost-lane
cost of every lane-closed whose exit class is not `completed`. A field the event does not carry
is `field absent`, never 0; a field that is there and null is `unmeasured`; every figure carries
its derivation. Kinds are assigned mechanically and the legend line says how. When no row
carries a measured cost the table ends with a `no waste found` row naming what was searched,
which is the zero-findings control. A record with no phase-boundary events still renders the
gate, orientation and lane rows and says `no phase-boundary events`; no record at all is a
premise failure. Output goes to --out (default `<store>/spawn-records/<run>-waste-table.md`) and
one line to stdout; --dry-run prints the counts and writes nothing.
`extract-transcript --session SID` writes `turns.md` (the human turns, the assistant prose and
the assistant's tool CALLS, each headed `## turn N · role · timestamp`) and `counts.json` (the
`read k of N` figure the reflector verifies) under --out (default `/tmp/aimyth-extract-<sid>/`).
An assistant record holding only tool calls is a tool-call turn headed `assistant · tool calls`:
one line per call with the tool's name and the input field naming what it acted on (Bash
`command`, Read/Edit/Write `file_path`, Grep/Glob `pattern`, any other tool its name alone), each
cut at 300 characters; a record holding both prose and calls keeps its prose turn and the lines
go under it. Those records were dropped before (register entry 2026-09-07: the reflector saw the
head's progress prose and nothing of what it did); they are now counted under `tool_call_turns`,
so records = extracted + tool_call_turns + every exclusion. Tool RESULTS are never carried:
tool-result records and the two injected user-record classes the reflector template names are
excluded and counted;
`"type":"user"` alone does not mean a human turn. The transcript is found as the gate finds it
(--projects-root overrides the root), the block reader is lane.py's own, and an unparseable line
is counted under `excluded.unparseable` rather than being fatal. Two harness shapes are handled
where they would otherwise read as the head's own words: a resume replay — a whole prior
conversation re-sent as ONE user record, recognised by a turn marker at its opening and at least
two in all, never by its size — is trimmed to the text after its last `User:` marker and counted
under `excluded.replay`; an assistant record whose model field opens `<synthetic` is the
harness's own stop text and is skipped, counted under `excluded.synthetic`, as the watermark
hook's measure() skips it.
`reflect-inputs --run R --session SID --out DIR` writes that lane's whole input set into DIR and
nothing else: `turns.md` and `counts.json` (the extraction above, same options), `waste-table.md`
(the table above) and `record-filtered.jsonl`, the run record with every observation whose phase
starts `controls` dropped and the keys `controls_checked`, `brief_copy`, `brief` and `plant`
stripped from every event kept. The convention behind the drop is the spawner's control
pre-registration, `handsoff.py ledger --phase controls-<LANE> …`: the reflector is blind to what
the head expected of it, and the filtered copy is written before the `reflect-inputs` event that
records the run, the session, the directory and the counts, so the copy never carries its own
line. An --out inside the run store or the projects root is a premise failure (exit 2), since the
lane is granted DIR alone, and --dry-run prints the same counts, writes nothing and records
nothing. The orientation rows carry one row per session id — a head-successor and the run-resume
that follows it are two spans of one session — and a measured figure wins over an unmeasured one.

One account (D28–D32). The vault runs under one login, so a limit stops the head and every
lane at once and nothing can wait for the reset from inside the session. The supervisor is
the process that started the head (the starter) or one attached with `supervise`: it waits on
its own head's process without bound and with no API call (only the predecessor-pid wait keeps
STARTER_WAIT_S, and the reset wait keeps --max-wait-s), and on exit classifies the stop with
the lane wrapper's own classifier (`classify` and `limit_signal`, imported from lane.py beside
this script; the .out result's subtype and text, the transcript's synthetic zero-usage
record). `handed-over` (a head-exit follows this head's start AND a head-successor follows
that head-exit within the starter's wait: the head left by design and its own `successor`
call owns the next head) and `closed` (a run-close follows) end the supervisor with one line;
a head-exit with no head-successor after that wait means the head died between `handoff
--final` and `successor`, and the supervisor runs the successor path itself (idempotent: the
duplicate guard refuses when a head-successor appears meanwhile). Every head-exit records
`spent_usd`, the session's billed total metered once at exit, and the remainder any next head
is sized at is the envelope minus every head-exit's spent_usd minus the current session's
total — the envelope is never re-granted per head.
`limit` is decided by the run's limit gate — the grants file's `on_limit` (design D42, the
pre-flight's class L): `stop`, the default, stands the supervisor down at once (event
supervisor-stood-down reason limit-stop, exit 0, the hand-off the recovery — the designed
default, never an abort); `resume` (the pre-flight's limit-off) waits: the explicit --reset-at first, else the reset parsed from the stop text; the
sleep runs in SUPERVISE_TICK_S ticks so a run-close written meanwhile ends it, and --max-wait-s
bounds it (successor-aborted, reason reset-timeout). During that wait, and as the last act
before a resume or a successor start, the supervisor stands down when the head transcript
changed (someone continued the session by hand: reason resumed-by-hand) or the marker
<run>-supervisor.stop appeared (`supervise --stop`, or `close`; reason stopped) — design D43,
keyed on the observable, the baseline taken after the stop is classified. THE PROBE IS OPT-IN AND OFF BY DEFAULT
(owner ruling 2026-09-06, CLAUDE.md §11: no agent probes or adjusts to an account limit without
explicit approval): with --probe, and only then, a haiku probe under the same login every
PROBE_INTERVAL_S ends the wait on the first success; the supervisor never passes --probe on its
own, and forwards it to its detached half only when its own caller passed it. Without the flag
and with no reset time to parse there is no wait at all: a stop-condition `which:
limit-unparsed` is recorded and the hand-off is the recovery (the supervisor ends
successor-aborted, reason limit-unparsed; wait-reset exits 7). After the reset a head whose context (its transcript, else the last
gate event) is under the FIRST band edge is resumed in place (`claude -p --resume <sid>`, the
resume note on standard input, the same .out, the envelope's remainder as its cap; event
head-resumed) and supervised again; at or above the edge a head-exit with band `limit` is
written and the successor path runs from the hand-off. `budget` (the harness's cap) takes the
same fork with no wait when the remainder (the envelope minus the meter's session total) is
positive, else successor-aborted reason budget (the owner tops up). `error` and a `completed`
head that neither handed over nor closed get one successor from the hand-off under the loop
guards (repeat-exit, successor-cap, unmetered-loop); an error exit's head-exit carries band
`error`. A resume runs only after the process has exited, refuses (duplicate-resume) when a
head-resumed or head-successor already follows this head's start, and is capped at two per
session (RESUME_CAP: a third would-be resume takes the successor path); two consecutive
error or budget stops, in any mix, and two consecutive completed stops (a head that exits
completed with neither a head-exit nor a run-close, whose successor does the same) end in
successor-aborted reason repeat-stop, the successor cap being only the backstop. A head-exit
recording a session that left no transcript (`unmetered (transcript missing …)` with no metered
spend: a seeded record whose head never ran) is not a stop the guard counts (register
2026-09-06), and the waste table leaves that session out of its head count. Without lane.py the supervisor cannot classify: successor-aborted, reason
classifier-missing, and the hand-off is the recovery. The heartbeat is the attended head's
answer to the idle cache: one beat per --minutes of idleness, one-shot, re-armed by the head
in the reply the beat re-invokes; a pid file refuses a second arming while one is alive.

Blocking calls and the shell tool: wait-reset returns `still-running <seconds left>` (exit 8)
after --max-block-s (default 540 s, under the shell tool's 600 s cap) and a hand-run caller
re-issues it. Nothing the head calls blocks: successor and supervise hand their waits to a
detached process, heartbeat is a background call by design, and boundary only runs the meter.

The gate's unmetered policy (amendments N1, F4): no transcript or no usage record → the line
`gate: unmetered (<reason>)`, an observation, the item allowed (exit 0); the SECOND consecutive
unmetered gate — counted over gate events after the last run-open, run-resume or
head-successor, never record-wide — exits 7 with stop-condition `which: unmetered` when the
session is armed, so the head runs `handoff --final --band unmetered` then `successor`; the
starter refuses (successor-aborted, reason unmetered-loop) when the previous head-exit also
carried band unmetered, so an unmetered fault buys at most one restart. Unarmed, the second
miss is a warning line and exit 0 (soft bands never stop a run, D2); the observation stands.

The gate's envelope policy (register entry 2026-09-07: an envelope stated in the pre-flight and
measured nowhere cannot stop anything). Every gate computes the run's spend against run-open's
`envelope_usd` through `envelope_left` — every head-exit's spent_usd plus this session's billed
total, metered now or taken from `--meter-line` — and prints it on its line as `envelope: $<spent>
of $<envelope>, remainder $<r>`. A remainder at or below zero refuses the item, armed or not,
with a stop-condition event — `{"event": "stop-condition", "which": "envelope", "lane":
"head", "action": …, "note": <the figures>}` — and exit 5: the run stops there, and the owner
tops the envelope up before any successor (which refuses on the same figure). A record whose run-open carries no envelope prints `envelope: none` and allows; a
meter that gives no session total prints `envelope: unmeasured (<reason>)` and allows, never a
refusal. A warning threshold stays the head's rule: the gate writes no warning event.

Armed: AIMYTH_HANDSOFF=1 in the environment, or the marker file armed-<sid> in AIMYTH_STATE_DIR
(default ~/.aimyth/handoffs; the hooks' handsoff-gate.py convention). Bands: AIMYTH_BANDS
(two or three ascending edges; the second is the gate's threshold) and AIMYTH_CONTEXT_WINDOW,
read through the watermark hook's own bands() and window() so gate and prompt line agree. The
head's transcript is <sid>.jsonl under the vault's dashed project directory beneath
AIMYTH_PROJECTS_DIR (default ~/.claude/projects), the session id from the LAST run-open,
run-resume or head-successor event; the dashed form replaces every non-alphanumeric character
with a dash (the harness's encoding, checked against a live projects root). measure() is
imported from the hooks directory's context-watermark.py beside this script's tree, never
from the watermark log: a headless head's transcript may hold one prompt and no hook line.

pid discovery (N4): walk upward from the parent process with `ps -o pid=,ppid=,comm=` to the
nearest ancestor whose command is the harness binary → pid, pid_src parent-walk; none (an
attended head) → no pid, pid_src none, and the starter falls back to 120 s of transcript
silence; --pid N overrides with pid_src arg.

The seed pattern (register entry 2026-09-07). A launcher shell that opens a run for a head which
has not started yet passes ITS OWN pid, `--pid $$`, to `run-open --session-kind seed`, to
`handoff --final` and to `successor`: the launcher is not the head, so a parent walk from any of
those calls reaches the live attended session instead, and the first starter then waits on the
launcher itself (register entry 2026-09-07: one lost starter at a 01:00 BST launch, no head
cost). Where
`handoff --final` is called without --pid on a SEEDED record — the record's run-open marks
`session_kind: seed` — the seed's own recorded pid is taken from that run-open event and the
walk is not run; the command prints the pid and its source on one line (`handoff: pid <n>
(run-open, seed)`), and on a head record the line reads `(parent-walk)`, `(arg)` or `(none)` as
before. `successor` inherits the fix through a head-exit the record already holds, and from
2026-09-08 resolves the pid by that same rule — the same helper — for the first head-exit it
writes itself, printing `successor: pid <n> (run-open, seed)` on the same shape of line
(register entry 2026-09-08).

The grants file (D34): run-open and run-resume write <store>/spawn-records/<run>-grants.json
(--grants-file PATH overrides) with `grants` and `writes` as real paths — every path given is
expanded, made absolute and resolved, and kept in both spellings when the given and the real
path differ — plus the defaults that keep the head's own primitives inside the fence: grants
carry the vault root, the store root, the state directory, the projects root and /tmp; writes
carry the store root and the state directory. The same two commands write the pointer file
run-<sid> (one line, the run id) under the state directory, so the head fence finds the run
from a session id when AIMYTH_HANDSOFF_RUN is absent. gate and boundary print one warning
line when the session is armed and the grants file is missing: the head fence is fail-open.

The console window (IDEAS №139 A2, the window on the A1 console). The grants file carries a
second key beside `on_limit` and built the same way: `viewer`, either `terminal` (the default,
and what a file without the key reads) or `none`. `run-open --viewer terminal|none` sets it,
`grants --viewer` rewrites it, `grants --grant PATH` and a flag-less `run-resume` carry it
forward, and run-open records it on its event as `viewer` with `viewer_src` (arg, grants, or
default (key absent)). The grants file is the key's only home: no second file and no environment
fallback for the key itself. On `terminal`, `open_console(run)` writes
<store>/spawn-records/<run>-console.command (mode 0755, `exec <this interpreter> -B <this
script> watch --run R`, rewritten when stale) and opens it in a Terminal window — osascript
first (`do script` on the file path, passed as an argv item and never interpolated into the
script text, the window titled `aiMyth hands-off · <run>`), then `open -a Terminal <path>`,
which needs no Automation permission. AIMYTH_VIEWER_CMD, when set, REPLACES the whole opener:
it is split with shlex, the command file's path is appended as its last argument and it is run
in list form, never through a shell. A VIEWER FAILURE NEVER FAILS A LAUNCH: every failure — no
binary, a timeout, a non-zero exit — prints one line to standard error (`viewer: no Terminal
window (<why>); run by hand: python3 -B <this script> watch --run R`) and the calling primitive
still exits 0. run-open opens at once, since a run's first act can have no console yet;
`successor`, `resume-head` and the supervisor's own successor and in-place-resume starts open
one only when `console_alive(run)` finds none, so the owner's `q` gets a fresh window while a
running console is never doubled. That probe is `pgrep -f` on both spellings of the command —
`handsoff.py watch --run R` as it is launched and `watch.py --run R` as it runs, since `watch`
execs watch.py in place — the run id escaped and the pattern passed as an argv item, so it never
matches its own command line. Away runs are included: the key alone decides. Every --dry-run
prints the opener's command line, opens nothing and writes no command file.

Paths for a staged copy: AIMYTH_HOOKS_DIR names the hooks directory holding
context-watermark.py (default two levels up from this script, beside the skill tree) and
AIMYTH_LANE_PY names the lane wrapper (default lane.py beside this script), so a copy under
test can be pointed at the shipped modules the way CLAUDE_PROJECT_DIR points it at a vault.

The pack-age guard (D41's pack, the successor's brief). `handoff --inflight`/`--inflight-file`
writes the section under a first line `- pack written: <ISO timestamp>`, replacing any earlier
stamp, so the pack carries its own age. `run-resume` and every successor start (the starter,
and `supervise` where its loop starts a successor) compare that stamp with the timestamp of the
record's last `phase-boundary` or `head-exit` event: a pack older than that boundary is STALE —
the head moved on and the pack did not. The starter then rewrites `## In flight` from the record
before the successor starts (the last boundary's `next`, the lanes still open since it with
their spawn lines, the `decision` events since it, one line each, under `- pack re-derived from
the record at <ts> (the head's pack was stale)`) and records an observation `what: stale-pack`;
`run-resume` prints one warning line and records the same observation. No boundary in the record
means the pack is fresh by definition; a pack with no stamp at all (a hand-off written by hand,
or before this guard) is reported `unstamped` and left alone, since re-deriving over it would
overwrite the head's own judgement. `handoff --inflight-from-record` is the same derivation as a
command, for a head that wants it, and it keeps the three D41 labels so a re-derived pack passes
the same label check a head's own pack must pass.

Exit codes: 0 done · 2 premise failure (PROBE FAILED, nothing written) · 3 event written but
the hand-off not refreshed (a section is missing: fix the document) · 4 gate refused on the
band (armed) · 7 gate refused on the second unmetered miss (armed), or wait-reset gave up at
--max-wait-s, or wait-reset ended limit-unparsed (no reset time, no --probe: the hand-off is
the recovery) · 8 wait-reset still running (re-issue the call) · 1 from an internal supervisor
whose run ended in successor-aborted (a stand-down, supervisor-stood-down, exits 0: the
designed default, never an abort).

Numbers: report cap 800 words (delegate skill, lane core); starter wait 600 s and silence
proxy 120 s (design, context bands; set by judgement, unmeasured); --max-block-s 540 s (the
shell tool's 600 s cap minus a minute of slack, set by judgement); probe interval 900 s and
budget $0.05 (design, account plan); commit timeout 300 s (set by judgement, unmeasured — a
cloud-synced work tree); the reset wait's bound 8 h (the existing waiter's bound, design D30);
the supervisor's sleep tick 60 s (set by judgement, unmeasured: a run-close is seen within a
minute and the tick costs nothing); the resume edge is the first band edge, 60 % by default
(design D30: the first band, unmeasured as an optimum); heartbeat 50 min (the 1-hour cache
tier less 10 min for the re-invocation's latency, set by judgement, design D32) in 30 s ticks
(design D32); the stop-condition note is cut at 300 characters (the waiter's existing cut); the
viewer's timeout 10 s (the console page's osascript notification bound is 5 s, doubled because
`do script` starts a process rather than posting a banner: set by judgement, unmeasured).
Every --dry-run prints what would be written and writes nothing.
"""
import sys
sys.dont_write_bytecode = True   # the hook import must never leave bytecode in the vault
import argparse
import calendar
import glob as globmod
import importlib.util
import json
import math
import os
import re
import shlex
import subprocess
import time
import uuid

HEAD_EVENTS = ("run-open", "run-resume", "head-exit", "head-successor")
SESSION_EVENTS = ("run-open", "run-resume", "head-successor")   # each names the head's session
START_EVENTS = SESSION_EVENTS + ("head-resumed",)   # each starts a head process the supervisor owns
WRAPPER_EVENTS = ("lane-closed", "stall")   # written while the head waits, never by the head
SESSION_KINDS = ("seed", "head")   # run-open --session-kind: a launcher's placeholder, or a head
# The cut tail of an over-cap report, priced in the waste table (T8 of the token-efficiency
# findings of 2026-09-07): words above REPORT_CAP_WORDS, converted at this many tokens per word
# and charged at the lane's model's OUTPUT rate from prices.json. The ratio is set by judgement,
# unmeasured — no tokeniser is read here — and every row it prices says so.
WORDS_TO_TOKENS = 1.3
DEFAULT_EDGES = (60, 80, 90)                # fallback only; the watermark hook's bands() decides
DEFAULT_WINDOW = 1000000
REPORT_CAP_WORDS = 800
STARTER_WAIT_S = 600
SILENCE_PROXY_S = 120
MAX_BLOCK_S = 540
MAX_WAIT_S = 8 * 3600          # the reset wait's bound (design D30: the existing waiter's bound)
PROBE_INTERVAL_S = 900
PROBE_BUDGET_USD = 0.05
PROBE_TIMEOUT_S = 120
COMMIT_TIMEOUT_S = 300
METER_TIMEOUT_S = 600
SUPERVISE_TICK_S = 60          # the supervisor's sleep tick (set by judgement, unmeasured)
RESUME_CAP = 2                 # resumes per head session (critic C2 N6, set by judgement)
HEARTBEAT_MINUTES = 50.0       # the 1-hour cache tier less 10 min latency (design D32, judgement)
HEARTBEAT_TICK_S = 30          # design D32
ON_LIMIT_VALUES = ("stop", "resume")   # the limit gate (design D42): the pre-flight's class L
ON_LIMIT_DEFAULT = "stop"              # respect the limit; `resume` is the pre-flight's limit-off
VIEWER_VALUES = ("terminal", "none")   # the viewer key: a Terminal window on the run's console
VIEWER_DEFAULT = "terminal"            # a run the owner can see; `none` is the opt-out
VIEWER_TIMEOUT_S = 10          # the opener's bound (the console page's osascript 5 s, doubled
                               # because `do script` starts a process: set by judgement)
CONSOLE_TITLE = "aiMyth hands-off · %s"   # the console window's custom title, per run
CONSOLE_START_GRACE_S = 15     # a console opened this recently counts as alive before its process
                               # shows in the table: Terminal opens the window and starts the
                               # .command's shell a few seconds after the opener returns, and
                               # run-open then successor one second apart opened two windows
                               # (the №140 launch, 12:16 BST 2026-09-08). Bounds only: 15 s is
                               # an order of magnitude over that race and under any head's first
                               # turn; set by judgement, the race measured once
NOTE_CUT = 300                 # the stop-condition note's cut (the waiter's existing cut)
# The gate's envelope stop (register entry 2026-09-07): 5 is the lowest exit code no subcommand
# uses — 0 done, 1 a supervisor or starter failure, 2 a premise failure, 3 boundary's hand-off
# not refreshed, 4 the band stop, 7 unmetered or limit, 8 still-running, 124/127 the shell's.
EXIT_ENVELOPE = 5
PACK_LABELS = ("Next:", "Needs:", "Decided:")   # the next-task pack (design D41)
PACK_LINE_RE = re.compile(r"^\s*(?:[-*]\s+)?(Next|Needs|Decided):", re.M)
PACK_STAMP = "- pack written: "                 # the pack's age stamp (the pack-age guard)
PACK_DERIVED = "- pack re-derived from the record at %s (the head's pack was stale)"
PACK_STAMP_RE = re.compile(r"^\s*[-*]\s+pack (?:written:|re-derived from the record at)\s*"
                           r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?"
                           r"(?:Z|[+-]\d{2}:?\d{2})?)", re.M)
BOUNDARY_EVENTS = ("phase-boundary", "head-exit")   # the pack-age guard's anchor
HARNESS = "claude"
TOKEN_RE = re.compile(r"[A-Za-z0-9._-]{1,128}")
TS_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?"
                   r"(Z|[+-]\d{2}:?\d{2})?$")
BULLETS = {"shipped": "What shipped", "waits": "Waits for you", "register": "Register delta",
           "spend": "Spend against the envelope", "saving": "Measured head-load saving",
           "warnings": "Warnings raised and handling", "resume": "Resume prompt"}
SECTIONS = {"inflight": "In flight", "resume-prompt": "Resume prompt", "plan": "Plan of record",
            "pointers": "Pointers", "grants": "Grants"}
APPEND_ONLY = ("ledger", "findings-ledger", "trace")
HERE = os.path.dirname(os.path.abspath(__file__))


# ----------------------------------------------------------------- premise and paths -------

def die(reason):
    """A premise failure: say what broke, write nothing, exit 2."""
    sys.stderr.write("handsoff.py: PROBE FAILED: %s\n" % reason)
    sys.exit(2)


def note(msg):
    sys.stderr.write("handsoff.py: %s\n" % msg)


def say(line):
    print(line, flush=True)


def vault_root():
    """Three levels above this script; an explicit CLAUDE_PROJECT_DIR wins, so a copy can be
    pointed at a fixture vault."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return os.path.realpath(env)
    return os.path.realpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))


def store_root():
    """The machine-local run store, as its real path (the default is a symlink)."""
    return os.path.realpath(os.path.expanduser(
        os.environ.get("LLM_WIKI_STORE") or os.path.join("~", ".llm-wiki")))


def projects_root():
    return os.path.realpath(os.path.expanduser(
        os.environ.get("AIMYTH_PROJECTS_DIR") or os.path.join("~", ".claude", "projects")))


def state_dir():
    return os.path.expanduser(os.environ.get("AIMYTH_STATE_DIR")
                              or os.path.join("~", ".aimyth", "handoffs"))


def dashed(path):
    """The harness's project-directory encoding: every non-alphanumeric character becomes a
    dash (checked against a live projects root, 2026-09-05)."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(path))


def vault_given():
    """The vault root as the caller spelled it (symlinks unresolved), for the second spelling."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return os.path.abspath(os.path.expanduser(env))
    return os.path.abspath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))


def store_given():
    return os.path.abspath(os.path.expanduser(
        os.environ.get("LLM_WIKI_STORE") or os.path.join("~", ".llm-wiki")))


def projects_given():
    return os.path.abspath(os.path.expanduser(
        os.environ.get("AIMYTH_PROJECTS_DIR") or os.path.join("~", ".claude", "projects")))


def lane_home_given():
    """The lane-home root as lane.py spells it: LLM_WIKI_LANE_HOME, else lane-home under the
    store (critic C2 N8: a head reads its lanes' homes)."""
    return os.path.abspath(os.path.expanduser(
        os.environ.get("LLM_WIKI_LANE_HOME") or os.path.join(store_given(), "lane-home")))


def spellings(path):
    """The path expanded and made absolute, in its real spelling and — when the two differ,
    as under a symlinked store — the given one as well."""
    given = os.path.abspath(os.path.expanduser(path))
    real = os.path.realpath(given)
    return [real] if real == given else [real, given]


def grants_path(run, override=None):
    """The grants file the head fence loads (D34): beside the record, unless overridden."""
    if override:
        return os.path.realpath(os.path.expanduser(override))
    return os.path.join(store_root(), "spawn-records", token(run, "run id") + "-grants.json")


def grants_payload(run, source, grants, writes, on_limit=ON_LIMIT_DEFAULT,
                   viewer=VIEWER_DEFAULT):
    """The defaults first (critic C1 F2: the head's own primitives are never denied), then the
    paths given, every one in both spellings, de-duplicated in order; `on_limit` is the limit
    gate (D42) and `viewer` the console window's key, each carried by this file alone."""
    def merge(paths):
        out = []
        for p in paths:
            for s in spellings(p):
                if s not in out:
                    out.append(s)
        return out
    return {"run": run,
            "grants": merge([vault_given(), store_given(), state_dir(), projects_given(),
                             lane_home_given(), "/tmp"] + list(grants or [])),
            "writes": merge([store_given(), state_dir()] + list(writes or [])),
            "on_limit": on_limit, "viewer": viewer, "written": now(), "source": source}


def read_grants(path):
    """The grants file's payload, or {} when absent or unreadable (a missing file is the fence's
    fail-open case and the gate's default, never an error here)."""
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
        return payload if isinstance(payload, dict) else {}
    except (OSError, ValueError):
        return {}


def on_limit_of(payload):
    """(value, source) from a grants payload: the key when it holds a known value, else the
    default `stop` with the reason (D42: a file written before the gate existed reads stop)."""
    value = payload.get("on_limit") if isinstance(payload, dict) else None
    if value in ON_LIMIT_VALUES:
        return value, "grants"
    if not payload:
        return ON_LIMIT_DEFAULT, "default (no grants file)"
    if value is None:
        return ON_LIMIT_DEFAULT, "default (key absent)"
    return ON_LIMIT_DEFAULT, "default (unknown value %r)" % (value,)


def on_limit_choice(a, path):
    """(value, source) the next write of the grants file carries: --on-limit when given, else
    the file's own value carried forward (D42; critic C1 M5: a rebuild must not reset it), else
    the default."""
    chosen = getattr(a, "on_limit", None)
    if chosen in ON_LIMIT_VALUES:
        return chosen, "--on-limit"
    return on_limit_of(read_grants(path))


def viewer_of(payload):
    """(value, source) from a grants payload, as on_limit_of reads the limit gate: the key when
    it holds a known value, else the default `terminal` with the reason. A grants file written
    before the viewer existed reads `terminal`, so an old run still gets its window."""
    value = payload.get("viewer") if isinstance(payload, dict) else None
    if value in VIEWER_VALUES:
        return value, "grants"
    if not payload:
        return VIEWER_DEFAULT, "default (no grants file)"
    if value is None:
        return VIEWER_DEFAULT, "default (key absent)"
    return VIEWER_DEFAULT, "default (unknown value %r)" % (value,)


def viewer_choice(a, path):
    """(value, source) the next write of the grants file carries: --viewer when given, else the
    file's own value carried forward (a rebuild must not reset it, as for the limit gate), else
    the default. The grants file is this key's only home (D42's rule for on_limit): no second
    file and no environment fallback for the key itself."""
    chosen = getattr(a, "viewer", None)
    if chosen in VIEWER_VALUES:
        return chosen, "arg"
    return viewer_of(read_grants(path))


def write_grants(run, source, a):
    path = grants_path(run, a.grants_file)
    on_limit, _ = on_limit_choice(a, path)
    viewer, _ = viewer_choice(a, path)
    if on_limit == "resume" and path != grants_path(run):
        die("--on-limit resume needs the default grants path %s: the supervisor and the status "
            "hook read no other (D42), and --grants-file names %s" % (grants_path(run), path))
    try:
        write_atomic(path, json.dumps(grants_payload(run, source, a.grant, a.write, on_limit,
                                                     viewer),
                                      ensure_ascii=False, indent=1) + "\n")
    except OSError as exc:
        die("cannot write the grants file %s: %s" % (path, exc))
    return path


def write_pointer(run, sid):
    """The state directory's run-<sid> file: one line, the run id (D34)."""
    path = os.path.join(state_dir(), "run-" + sid)
    try:
        write_atomic(path, run + "\n")
    except OSError as exc:
        die("cannot write the run pointer %s: %s" % (path, exc))
    return path


def grants_warning(events, run, sid):
    """One line when the session is armed and the grants file is missing (D34: the head fence
    is fail-open); None otherwise."""
    is_armed, _ = armed(sid)
    if not is_armed:
        return None
    path = None
    for ev in reversed(events):
        if ev.get("event") in ("run-open", "run-resume") and ev.get("grants_file"):
            path = ev["grants_file"]
            break
    path = path or grants_path(run)
    if os.path.isfile(path):
        return None
    return "warn: armed with no grants file at %s: the head fence is fail-open" % path


def heartbeat_files(run):
    """(pid file, stop marker) beside the record (design D32)."""
    base = os.path.join(store_root(), "spawn-records", token(run, "run id") + "-heartbeat")
    return base + ".pid", base + ".stop"


def token(value, what):
    if not isinstance(value, str) or not TOKEN_RE.fullmatch(value):
        die("%s %r is not a plain token" % (what, value))
    return value


def record_path(run):
    return os.path.join(store_root(), "spawn-records", token(run, "run id") + ".jsonl")


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def hhmm():
    return time.strftime("%H:%M")


def fmt_ts(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(epoch))


def parse_ts(value):
    """Epoch seconds from a record timestamp (seconds optional, offset +0100, +01:00 or Z; a
    naive stamp reads as local time), else None."""
    m = TS_RE.match(str(value or "").strip())
    if not m:
        return None
    y, mo, d, hh, mm = (int(m.group(i)) for i in range(1, 6))
    ss = int(m.group(6) or 0)
    tz = m.group(7)
    try:
        if not tz:
            return time.mktime((y, mo, d, hh, mm, ss, 0, 0, -1))
        base = calendar.timegm((y, mo, d, hh, mm, ss, 0, 0, 0))
    except (OverflowError, ValueError):
        return None
    if tz == "Z":
        return float(base)
    digits = tz[1:].replace(":", "")
    offset = int(digits[:2]) * 3600 + int(digits[2:]) * 60
    return float(base - offset if tz[0] == "+" else base + offset)


def read_text(path, what):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError as exc:
        die("cannot read %s (%s): %s" % (what, path, exc))


def write_atomic(path, text):
    """Temp file in the same directory, then rename: a concurrent reader sees the old file or
    the new one, never a half-written one."""
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temp = os.path.join(directory, ".%s.%d.tmp" % (os.path.basename(path), os.getpid()))
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, path)


# ------------------------------------------------------------------------ the record -------

def read_record(path):
    """(events, unparseable lines): a torn last line — a wrapper writing concurrently — is
    counted, never guessed at."""
    events, bad = [], 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    bad += 1
                    continue
                if isinstance(rec, dict):
                    events.append(rec)
                else:
                    bad += 1
    except OSError as exc:
        die("cannot read the run record %s: %s" % (path, exc))
    return events, bad


PLAIN_SHAPE = "plain-lane-run"   # the `shape` a plain record's run-close carries (see close_plain)


def read_existing_record(path):
    """The record's events with NO `run-open` requirement: the file must exist and parse.

    A record `lane.py` opened holds lane events and no `run-open` — the plain-lane-run shape of
    the register entries of 2026-09-06 and 2026-09-07. The guard on `run-open` belongs to the
    caller that needs a head (a boundary, a gate, a hand-off rewrite), never to the reader."""
    if not os.path.isfile(path):
        die("no run record at %s — run-open first" % path)
    events, bad = read_record(path)
    if bad:
        note("%d unparseable line(s) in %s skipped" % (bad, path))
    return events


def is_plain_run(events):
    """True for the plain-lane-run shape: a record with no `run-open` event. The test is the
    record's own events, never the run's name or the store it sits in."""
    return last_index(events, ("run-open",)) < 0


def require_record(path, hint=""):
    """The events of a record that must carry a `run-open`; `hint` names the form that works on
    a record without one, for the commands that have such a form."""
    events = read_existing_record(path)
    if is_plain_run(events):
        die("no run-open event in %s%s" % (path, hint))
    return events


def append_record(path, payload):
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as exc:
        die("run record is not writable (%s): %s" % (path, exc))


def event(run, kind, **fields):
    payload = {"ts": now(), "run": run, "event": kind}
    payload.update(fields)
    return payload


def last_index(events, kinds):
    for i in range(len(events) - 1, -1, -1):
        if events[i].get("event") in kinds:
            return i
    return -1


def run_open(events):
    i = last_index(events, ("run-open",))
    if i < 0:
        die("no run-open event")
    return events[i]


def head_session(events):
    """(session id, the event naming it) from the LAST run-open, run-resume or head-successor
    event; (None, None) when the record names no session."""
    i = last_index(events, SESSION_EVENTS)
    if i < 0:
        return None, None
    ev = events[i]
    sid = ev.get("session_id") if ev.get("event") == "head-successor" else ev.get("session")
    return (sid if isinstance(sid, str) and TOKEN_RE.fullmatch(sid) else None), ev


def handoff_of(events, override=None):
    path = os.path.expanduser(override) if override else run_open(events).get("handoff")
    if not path:
        die("run-open carries no hand-off path; pass --handoff")
    if not os.path.isfile(path):
        die("hand-off document not found: %s" % path)
    return path


# ---------------------------------------------------------------- hand-off sections --------

def heading_index(lines, name):
    """The first level-two heading whose text starts with the name (the shipped documents
    suffix their headings)."""
    for i, line in enumerate(lines):
        if line.startswith("## ") and line[3:].strip().lower().startswith(name.lower()):
            return i
    return -1


def section_end(lines, start):
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## ") or lines[i].startswith("# "):
            return i
    return len(lines)


def section_text(lines, name):
    i = heading_index(lines, name)
    if i < 0:
        return None
    body = lines[i + 1:section_end(lines, i)]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return "\n".join(body)


def table_span(lines, name):
    """(first row, last row) of the first table under the heading, else None: the first
    contiguous block of pipe-led lines after the heading, header and separator included."""
    i = heading_index(lines, name)
    if i < 0:
        return None
    end = section_end(lines, i)
    j = i + 1
    while j < end and not lines[j].strip():
        j += 1
    if j >= end or not lines[j].lstrip().startswith("|"):
        return None
    k = j
    while k + 1 < end and lines[k + 1].lstrip().startswith("|"):
        k += 1
    if k - j < 1:
        return None
    return j, k


def table_rows(lines, name):
    span = table_span(lines, name)
    return 0 if span is None else max(0, span[1] - span[0] - 1)


def one_line(text):
    return re.sub(r"\s*\n\s*", " ", str(text)).strip()


def cell(text):
    return one_line(text).replace("|", "\\|")


def set_bullet(lines, key, value, number_only=False):
    """Rewrite one morning-report bullet (`- **Label:** text`), adding it when absent. With
    number_only, refresh only a `(N lines` figure inside the existing text."""
    label = BULLETS[key]
    i = heading_index(lines, "Morning report")
    if i < 0:
        return False
    end = section_end(lines, i)
    pat = re.compile(r"^(\s*[-*]\s+\*\*%s:?\*\*:?\s*)(.*)$" % re.escape(label))
    for j in range(i + 1, end):
        m = pat.match(lines[j])
        if not m:
            continue
        if number_only and re.search(r"\(\d+ lines?", m.group(2)):
            lines[j] = m.group(1) + re.sub(r"\((\d+) (lines?)", "(%s \\2" % value,
                                           m.group(2), count=1)
        elif number_only:
            lines[j] = m.group(1) + "see `## Findings ledger` (%s lines)" % value
        else:
            lines[j] = m.group(1) + one_line(value)
        return True
    insert = end
    while insert > i + 1 and not lines[insert - 1].strip():
        insert -= 1
    text = ("see `## Findings ledger` (%s lines)" % value) if number_only else one_line(value)
    lines.insert(insert, "- **%s:** %s" % (label, text))
    return True


def set_section(lines, key, value):
    i = heading_index(lines, SECTIONS[key])
    if i < 0:
        return False
    lines[i + 1:section_end(lines, i)] = value.rstrip("\n").split("\n") + [""]
    return True


# --------------------------------------------------------------- context and arming --------

_WATERMARK = None


def hooks_dir():
    """The hooks directory: AIMYTH_HOOKS_DIR wins (a staged copy), else beside the skill tree."""
    env = os.environ.get("AIMYTH_HOOKS_DIR")
    if env:
        return os.path.realpath(os.path.expanduser(env))
    return os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, "hooks"))


def watermark():
    """(module, path): the hook imported by file path; (None, path) when it is not there."""
    global _WATERMARK
    if _WATERMARK is not None:
        return _WATERMARK
    path = os.path.join(hooks_dir(), "context-watermark.py")
    if not os.path.isfile(path):
        _WATERMARK = (None, path)
        return _WATERMARK
    spec = importlib.util.spec_from_file_location("context_watermark", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _WATERMARK = (module, path)
    return _WATERMARK


_LANE = None


def lane_module():
    """(module, path, error): the lane wrapper imported by file path for its classifier, never
    copied; (None, path, reason) when it is missing or does not import (a torn write)."""
    global _LANE
    if _LANE is not None:
        return _LANE
    path = os.environ.get("AIMYTH_LANE_PY") or os.path.join(HERE, "lane.py")
    path = os.path.realpath(os.path.expanduser(path))
    if not os.path.isfile(path):
        _LANE = (None, path, "lane.py not found at %s" % path)
        return _LANE
    try:
        spec = importlib.util.spec_from_file_location("lane_wrapper", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    except Exception as exc:   # a torn or broken file: report it, never classify from a copy
        _LANE = (None, path, "lane.py at %s does not import: %s" % (path, exc))
        return _LANE
    for name in ("classify", "limit_signal", "parse_transcript"):
        if not callable(getattr(module, name, None)):
            _LANE = (None, path, "lane.py at %s has no %s()" % (path, name))
            return _LANE
    _LANE = (module, path, None)
    return _LANE


def window():
    module, _ = watermark()
    if module is not None and hasattr(module, "window"):
        return module.window()
    try:
        w = int(os.environ.get("AIMYTH_CONTEXT_WINDOW") or 0)
    except ValueError:
        w = 0
    return w if w > 0 else DEFAULT_WINDOW


def edges():
    module, _ = watermark()
    if module is not None and hasattr(module, "bands"):
        found = tuple(module.bands())
        if len(found) >= 2:
            return found
    raw = os.environ.get("AIMYTH_BANDS") or ""
    parts = [p.strip() for p in raw.split(",")] if raw else []
    if 2 <= len(parts) <= 3 and all(p.isdigit() for p in parts):
        found = tuple(int(p) for p in parts)
        if found[0] > 0 and found[-1] <= 100 and list(found) == sorted(found):
            return found
    return DEFAULT_EDGES


def band_edge(context, w, e):
    """The highest edge the figure has reached (lower edge inclusive), 0 below the first."""
    reached = [edge for edge in e if context * 100 >= edge * w]
    return reached[-1] if reached else 0


def transcript_for(sid, root=None):
    """The head's transcript: the vault's project directory first, then a unique hit across
    the projects root (a head started elsewhere); else the direct path, so the unmetered
    reason names where it was expected. `root` overrides the projects root for a caller that
    was given one (extract-transcript's --projects-root); everything else is unchanged."""
    root = root or projects_root()
    direct = os.path.join(root, dashed(vault_root()), "%s.jsonl" % sid)
    if os.path.isfile(direct):
        return direct
    hits = sorted(globmod.glob(os.path.join(root, "*", "%s.jsonl" % sid)))
    return hits[0] if len(hits) == 1 else direct


def measure_head(sid):
    """The watermark hook's measure() on the head's transcript, plus percent and band edge."""
    module, path = watermark()
    if not sid:
        return {"reason": "no head session in the record", "transcript": None}
    if module is None:
        return {"reason": "context-watermark.py not found at %s" % path, "transcript": None}
    tp = transcript_for(sid)
    m = dict(module.measure(tp))
    m["transcript"] = tp
    if m.get("context") is None:
        m["reason"] = "%s: %s" % (m.get("reason", "unknown"), tp)
        return m
    w, e = window(), edges()
    m["percent"] = m["context"] * 100 // w
    m["band"] = band_edge(m["context"], w, e)
    return m


def context_text(m):
    if m.get("context") is None:
        return "unmetered (%s)" % m.get("reason", "unknown")
    return "%s tokens (%d %%)" % (format(m["context"], ","), m["percent"])


def armed(sid):
    """(armed, how): the environment first, then the marker file the hooks also honour."""
    if os.environ.get("AIMYTH_HANDSOFF") == "1":
        return True, "env"
    if sid and TOKEN_RE.fullmatch(sid) and os.path.isfile(
            os.path.join(state_dir(), "armed-" + sid)):
        return True, "marker"
    return False, "none"


def ps_row(pid):
    try:
        out = subprocess.run(["ps", "-o", "pid=,ppid=,comm=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    parts = out.split(None, 2)
    if len(parts) < 3:
        return None
    try:
        return int(parts[0]), int(parts[1]), parts[2].strip()
    except ValueError:
        return None


def head_pid(arg):
    """(pid, pid_src): --pid wins; else the nearest ancestor whose command is the harness."""
    if arg is not None:
        return int(arg), "arg"
    pid = os.getppid()
    for _ in range(32):
        row = ps_row(pid)
        if row is None:
            break
        _, ppid, comm = row
        if comm == HARNESS or comm.endswith(os.sep + HARNESS):
            return pid, "parent-walk"
        if ppid <= 1 or ppid == pid:
            break
        pid = ppid
    return None, "none"


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


# ------------------------------------------------------------------ the console window -----

def console_command_path(run):
    """The run's opener script, beside its record in the run store (never a temp path, so a
    stale one is found and rewritten rather than accumulating)."""
    return os.path.join(store_root(), "spawn-records",
                        token(run, "run id") + "-console.command")


def console_command_text(run):
    """The opener script's whole content: this interpreter, this script, `watch --run R`. Every
    path is derived — sys.executable and this file's own absolute path — so the shipped source
    carries none of them as a literal."""
    return ("#!/bin/sh\nexec %s -B %s watch --run %s\n"
            % (shlex.quote(sys.executable), shlex.quote(os.path.abspath(__file__)),
               shlex.quote(token(run, "run id"))))


def write_console_command(run):
    """The opener script written 0755, rewritten when stale (the interpreter or this file moved,
    or the run store was rebuilt): the path, or None with a note when it cannot be written."""
    path = console_command_path(run)
    text = console_command_text(run)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        current = None
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as handle:
                current = handle.read()
        if current != text:
            write_atomic(path, text)
        os.chmod(path, 0o755)
    except OSError as exc:
        note("viewer: cannot write the console command %s: %s" % (path, exc))
        return None
    return path


def console_alive(run):
    """The pids of the processes already showing this run's console. Two spellings count: the
    command as it is launched (`handsoff.py watch --run R`) and the command as it RUNS, since
    `watch` execs watch.py in place and the live process reads `… /watch.py --run R` (checked
    against a live console on 2026-09-08). A pattern on the first spelling alone finds nothing.
    The run id is escaped and the pattern is passed as an argv item to `pgrep`, never through a
    shell, so this probe never matches its own command line."""
    rid = re.escape(token(run, "run id"))
    pattern = r"(handsoff\.py watch|watch\.py) --run %s([[:space:]]|$)" % rid
    try:
        proc = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True,
                              timeout=VIEWER_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError) as exc:
        note("viewer: cannot probe for a live console (%s: %s)" % (type(exc).__name__, exc))
        return []
    pids = []
    for field in proc.stdout.split():
        try:
            pid = int(field)
        except ValueError:
            continue
        if pid != os.getpid():
            pids.append(pid)
    return pids


def console_starting(run):
    """The age in seconds of a console opened within CONSOLE_START_GRACE_S, else None: the
    opener sets the command file's mtime at every open (mark_console_opening) and pushes it into
    the past on a failed open (mark_console_failed), so a fresh mtime means a window Terminal is
    still bringing up, whose process console_alive cannot see yet (the race of 2026-09-08). A
    missing file, an old file or an unreadable mtime is None: no claim."""
    path = console_command_path(run)
    try:
        age = time.time() - os.path.getmtime(path)
    except OSError:
        return None
    return age if 0 <= age < CONSOLE_START_GRACE_S else None


def mark_console_opening(path):
    """Stamp the command file with the clock just before the opener runs, whatever its content
    (write_console_command rewrites only stale content, so the stamp is explicit)."""
    try:
        os.utime(path, None)
    except OSError as exc:
        note("viewer: cannot stamp the console command %s: %s" % (path, exc))


def mark_console_failed(path):
    """Push the command file's mtime past the grace window after a failed open, so the failure
    never reads as a console still starting."""
    past = time.time() - 2 * CONSOLE_START_GRACE_S
    try:
        os.utime(path, (past, past))
    except OSError as exc:
        note("viewer: cannot unstamp the console command %s: %s" % (path, exc))


def viewer_argv(path, run):
    """(argv, fallback argv) for the opener. AIMYTH_VIEWER_CMD, when set, REPLACES the whole
    opener command: it is split with shlex, the command file's path is appended as the last
    argument, and it is run in list form — never a shell string, so no word of it is re-parsed
    by a shell. Otherwise the pair is osascript (a Terminal window with a custom title) and,
    on any failure, `open -a Terminal <path>`, which needs no Automation permission."""
    custom = os.environ.get("AIMYTH_VIEWER_CMD")
    if custom:
        return shlex.split(custom) + [path], None
    script = ["on run argv",
              "tell application \"Terminal\"",
              "activate",
              "do script (item 1 of argv)",
              "try",
              "set custom title of window 1 to (item 2 of argv)",
              "end try",
              "end tell",
              "end run"]
    argv = ["osascript"]
    for line in script:
        argv += ["-e", line]
    argv += [path, CONSOLE_TITLE % token(run, "run id")]
    return argv, ["open", "-a", "Terminal", path]


def run_viewer(argv):
    """(True, "") when the command exits 0, else (False, why). Never raises and never fails a
    caller: a missing binary, a timeout and a non-zero exit are all one class."""
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=VIEWER_TIMEOUT_S)
    except FileNotFoundError:
        return False, "%s not on PATH" % argv[0]
    except subprocess.TimeoutExpired:
        return False, "%s timed out after %d s" % (argv[0], VIEWER_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, "%s: %s" % (argv[0], exc)
    if proc.returncode == 0:
        return True, ""
    tail = (proc.stderr or proc.stdout or "").strip().replace("\n", " ")[:120]
    return False, "%s exit %d%s" % (argv[0], proc.returncode, ": " + tail if tail else "")


def run_viewer_key(run):
    """(value, source): the run's viewer key from the DEFAULT grants path — the one file the
    head fence and the status hook read too, and the key's only home (as `on_limit`, D42). A
    missing file or key is the default `terminal`, and the source says which."""
    return viewer_of(read_grants(grants_path(run)))


def by_hand_line(run):
    """The line the owner runs when no window could be opened; the same derived paths."""
    return "python3 -B %s watch --run %s" % (os.path.abspath(__file__), token(run, "run id"))


def open_console(run, viewer=None, dry_run=False, why=""):
    """Put a Terminal window on this run's console (`handsoff.py watch --run R`), the window
    part A2 of the console (IDEAS №139). Returns True when a window was opened.

    A VIEWER FAILURE NEVER FAILS A LAUNCH: every path here ends in one stderr line naming the
    reason and the by-hand command, and the calling primitive still exits 0. `viewer: none`
    opens nothing; --dry-run prints the command line, opens nothing and writes no file."""
    if viewer is None:
        viewer, _ = run_viewer_key(run)
    if viewer != "terminal":
        say("viewer: none (grants) · no window%s" % (" · " + why if why else ""))
        return False
    path = console_command_path(run)
    argv, fallback = viewer_argv(path, run)
    if dry_run:
        say("viewer: dry run · command file %s (not written) · would run: %s%s"
            % (path, " ".join(shlex.quote(w) for w in argv),
               " · fallback: " + " ".join(shlex.quote(w) for w in fallback)
               if fallback else " · fallback: none (AIMYTH_VIEWER_CMD)"))
        return False
    written = write_console_command(run)
    if written is None:
        note("viewer: no Terminal window (the console command could not be written); run by "
             "hand: %s" % by_hand_line(run))
        return False
    mark_console_opening(path)
    ok, first_why = run_viewer(argv)
    if not ok and fallback is not None:
        ok, second_why = run_viewer(fallback)
        first_why = "%s; %s" % (first_why, second_why) if not ok else first_why
    if not ok:
        mark_console_failed(path)
        note("viewer: no Terminal window (%s); run by hand: %s" % (first_why, by_hand_line(run)))
        return False
    say("viewer: Terminal window on %s%s" % (path, " · " + why if why else ""))
    return True


def open_console_if_dark(run, viewer=None, dry_run=False):
    """The opener for a primitive that starts a head into a run that may already be watched:
    one window per run, so the owner's `q` and a by-hand restart get a fresh one while a running
    console is never doubled. Away runs included — the key alone decides. Concurrent openers
    (N Agent lanes in one message run N spawn-guard hooks at once; two lane.py workers a second
    apart) settle on an atomic claim, `<command file>.opening`, created with O_EXCL: the claimant
    opens, every other caller inside CONSOLE_START_GRACE_S reads the claim and opens nothing, and
    a claim older than the grace window is stale (its console died or never started) and is taken
    over — the check-then-act gap the grace stamp alone left open (critic F2 of the 2026-09-08
    watcher review)."""
    if viewer is None:
        viewer, _ = run_viewer_key(run)
    if viewer != "terminal":
        return open_console(run, viewer=viewer, dry_run=dry_run)
    live = console_alive(run)
    if live and not dry_run:
        say("viewer: a console is already alive (pid %s) · no second window"
            % ", ".join(str(p) for p in live))
        return False
    if not live and not dry_run:
        age = console_starting(run)
        if age is not None:
            say("viewer: a console was opened %.0f s ago and may still be starting · no second "
                "window" % age)
            return False
        claim = console_command_path(run) + ".opening"
        try:
            os.close(os.open(claim, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
        except FileExistsError:
            try:
                age = time.time() - os.path.getmtime(claim)
            except OSError:
                age = 0.0
            if 0 <= age < CONSOLE_START_GRACE_S:
                say("viewer: another opener claimed this run %.0f s ago · no second window" % age)
                return False
            try:
                os.utime(claim, None)                 # a stale claim: taken over
            except OSError:
                pass
        except OSError as exc:
            note("viewer: cannot claim the console (%s); opening anyway" % exc)
    return open_console(run, viewer=viewer, dry_run=dry_run,
                        why="no console was alive" if not live else "")


# ------------------------------------------------------------------ meter and waste --------

def billed_field(line, pattern, cast):
    m = re.search(pattern, line or "")
    if not m:
        return None
    try:
        return cast(m.group(1))
    except ValueError:
        return None


def seed_sessions(events):
    """The session ids the record marks as a launcher's placeholder: `run-open --session-kind
    seed` (T7 of the token-efficiency findings, 2026-09-07). A seed session never ran, so it is
    no head: the table skips it and the meter is never asked to read a transcript it has none
    of. The marking is the record's own field, never the run's or the session's name."""
    found = []
    for ev in events:
        if ev.get("event") == "run-open" and ev.get("session_kind") == "seed":
            sid = ev.get("session")
            if isinstance(sid, str) and sid not in found:
                found.append(sid)
    return found


def run_window(events):
    """(start, end, source): the run's OWN window as the record spells it — the run-open
    timestamp to the run-close timestamp, or to the record's last event where the record holds
    no run-close (T6, 2026-09-07). Metering a head over this window rather than over its whole
    session stops a session shared with attended work from being counted whole against one run.
    (None, None, reason) where the record carries no usable timestamp."""
    stamps = [ev.get("ts") for ev in events if isinstance(ev.get("ts"), str) and ev.get("ts")]
    ro = run_open(events)
    start = ro.get("ts") if isinstance(ro.get("ts"), str) else (stamps[0] if stamps else None)
    close = next((ev for ev in reversed(events) if ev.get("event") == "run-close"), None)
    if close is not None and isinstance(close.get("ts"), str):
        end, how = close["ts"], "run-close"
    elif stamps:
        end, how = stamps[-1], "the record's last event (no run-close)"
    else:
        end, how = None, "no timestamped event"
    if not start or not end:
        return None, None, "the record carries no usable window (%s)" % how
    return start, end, "run-open %s → %s %s" % (start, how, end)


def meter_cmd(meter, run, sid, ro, lanes, start=None, end=None):
    """The meter's command line for one head session, over a window when one is given: the
    `--start`/`--end` pair the meter already takes (its own main), so the head is metered over
    the run's window rather than over its whole session (T6)."""
    vault, root = vault_root(), projects_root()
    cmd = [sys.executable, "-B", meter, "--session", sid, "--lanes", lanes,
           "--spawn-record", record_path(run), "--projects-root", root, "--vault", vault,
           "--project-dir", os.path.join(root, dashed(vault))]
    if ro.get("regime") in ("single", "multi") and ro.get("regime_src") in ("owner", "head"):
        cmd += ["--delegation", ro["regime"], "--delegation-src", ro["regime_src"]]
    if start:
        cmd += ["--start", start]
    if end:
        cmd += ["--end", end]
    return cmd


def meter_line(events, run, override=None, start=None, end=None, session=None):
    """The meter's billed line for the head session, or `failed: <reason>`. Lanes come from
    the record (--lanes auto); before any lane has a transcript the meter refuses and the head
    alone is metered (--lanes none), which the line itself says. `session` meters a named head
    rather than the record's last one, and `start`/`end` meter it over a window (T6): both are
    for the waste table's whole-run rows, and every other caller's behaviour is unchanged."""
    if override:
        return override
    sid = session or head_session(events)[0]
    if not sid:
        return "failed: no head session in the record"
    if sid in seed_sessions(events):
        return "seed (skipped): run-open marks session %s a seed, which never ran" % sid
    meter = os.path.join(HERE, "fable-share.py")
    if not os.path.isfile(meter):
        return "failed: fable-share.py not found beside handsoff.py"
    ro = run_open(events)
    base = meter_cmd(meter, run, sid, ro, "auto", start, end)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for lanes in ("auto", "none"):
        cmd = list(base)
        cmd[cmd.index("--lanes") + 1] = lanes
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=METER_TIMEOUT_S,
                                  env=env)
        except subprocess.TimeoutExpired:
            return "failed: the meter did not finish in %d s" % METER_TIMEOUT_S
        except OSError as exc:
            return "failed: %s" % exc
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                if line.startswith("billed ("):
                    return line.strip()
            return "failed: the meter printed no billed line"
        tail = (proc.stderr.strip().splitlines() or ["exit %d" % proc.returncode])[-1]
        if lanes == "auto" and "no readable lane transcript" in tail:
            continue
        return "failed: %s" % tail[:300]
    return "failed: the meter refused both lane modes"


def count_words(path):
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return len(handle.read().split())
    except OSError:
        return None


# A head gap counts as idle only above this many seconds: the brief's threshold for the head-idle
# measure (2026-09-06), set by judgement, unmeasured. A tool call that runs longer reads as idle,
# since a transcript's timestamps cannot tell a long tool run from a wait.
IDLE_GAP_S = 60
REWRITES_RE = r"rewrites (\d+) \("


def head_calls(path):
    """Epoch timestamps of the head's own calls: every assistant record of its transcript that
    is not a sidechain (a lane's context, never the head's) and carries a parseable timestamp,
    sorted. None when the transcript is missing, unreadable or holds no such record, so the
    caller falls back to the record and says so."""
    if not path or not os.path.isfile(path):
        return None
    stamps = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if '"assistant"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if (not isinstance(rec, dict) or rec.get("type") != "assistant"
                        or rec.get("isSidechain")):
                    continue
                t = parse_ts(rec.get("timestamp"))
                if t is not None:
                    stamps.append(t)
    except OSError:
        return None
    return sorted(stamps) or None


def merge_intervals(intervals):
    out = []
    for a, b in sorted(intervals):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def lane_intervals(events, t0, t1):
    """The lane running time inside [t0, t1], merged: from each lane-open or lane-resumed to
    that lane's next lane-closed (t1 when none has come). A lane-closed whose open the record
    does not place is taken as running from t0, the earliest the record can put it — the
    direction that hides idle time rather than inventing it."""
    starts, found = {}, []
    for ev in events:
        kind, lane = ev.get("event"), ev.get("lane")
        if lane is None or kind not in ("lane-open", "lane-resumed", "lane-closed"):
            continue
        t = parse_ts(ev.get("ts"))
        if kind != "lane-closed":
            if t is not None:
                starts[lane] = t
            continue
        start = starts.pop(lane, None)
        if t is not None:
            found.append((start if start is not None else t0, t))
    found += [(start, t1) for start in starts.values()]
    clipped = [(max(a, t0), min(b, t1)) for a, b in found if min(b, t1) > max(a, t0)]
    return merge_intervals(clipped)


def head_idle_s(calls, running, t0, t1):
    """Seconds of [t0, t1] inside a head gap above IDLE_GAP_S and outside every lane interval:
    the span's edges are the head's own acts (the previous boundary, this one)."""
    points = [t0] + [t for t in calls if t0 < t < t1] + [t1]
    idle = 0.0
    for a, b in zip(points, points[1:]):
        if b - a <= IDLE_GAP_S:
            continue
        busy = sum(max(0.0, min(b, y) - max(a, x)) for x, y in running)
        idle += (b - a) - busy
    return idle


def resumed_after(later, close):
    """The first lane-resumed for the same lane among the events after its close, else None;
    the lane session id is matched too when both events carry one."""
    for ev in later:
        if ev.get("event") != "lane-resumed" or ev.get("lane") != close.get("lane"):
            continue
        a, b = ev.get("session_id"), close.get("session_id")
        if a and b and a != b:
            continue
        return ev
    return None


def waste_fields(events, since, transcript=None, now_ts=None):
    """Four of the five waste classes over the events after index `since` (the previous
    boundary, else run-open), each with its derivation (register entries of 2026-09-05):
      - idle_min: head idleness — the time in the span (that event's timestamp to now) when
        no lane was running and the head made no call, a head gap counting only above
        IDLE_GAP_S. Lane running time comes from the record (lane-open or lane-resumed to the
        lane's next lane-closed); the head's calls from its transcript (`transcript`, the path
        measure_head found), labelled idle_src `transcript`. When the transcript is missing or
        carries no timestamped call, the record alone measures it as the rule before this one
        did — silence after each lane close until the head's next recorded act, summed per
        close — labelled idle_src `record`, which under parallel lanes overstates.
      - denials: summed from the wrappers' counts.
      - over_cap_reports: reports over the cap.
      - respawn_cost_usd: the cost of lanes that closed other than `completed` and were NOT
        resumed afterwards (a lane-resumed for the same lane later in the record): a lane
        resumed from intact staging lost nothing. `respawn_excluded` counts the resumed ones.
    Rewrites come from the billed line (rewrites_delta). Also returns how many reports could
    not be word-counted."""
    window_events = events[since + 1:]
    now_ts = time.time() if now_ts is None else now_ts
    silence, denials, over, respawn, unmeasured, excluded = 0.0, 0, 0, 0.0, 0, 0
    for k, ev in enumerate(window_events):
        if ev.get("event") != "lane-closed":
            continue
        t0 = parse_ts(ev.get("ts"))
        if t0 is not None:
            t1 = None
            for later in window_events[k + 1:]:
                if later.get("event") in WRAPPER_EVENTS:
                    continue
                t = parse_ts(later.get("ts"))
                if t is not None and t >= t0:
                    t1 = t
                    break
            silence += ((t1 if t1 is not None else now_ts) - t0) / 60.0
        d = ev.get("denials")
        if isinstance(d, dict):
            denials += int(d.get("tool") or 0)
        elif isinstance(d, int):
            denials += d
        else:
            denials += len(ev.get("permission_denials") or [])
        words = ev.get("report_words")
        if not isinstance(words, int):
            words = count_words(ev.get("report"))
        if words is None:
            unmeasured += 1
        elif words > REPORT_CAP_WORDS:
            over += 1
        if ev.get("exit_class") not in (None, "completed"):
            if resumed_after(window_events[k + 1:], ev) is not None:
                excluded += 1
                continue
            try:
                respawn += float(ev.get("total_cost_usd") or 0)
            except (TypeError, ValueError):
                pass
    span_start = parse_ts(events[since].get("ts")) if 0 <= since < len(events) else None
    calls = head_calls(transcript)
    if calls is not None and span_start is not None and now_ts > span_start:
        idle = head_idle_s(calls, lane_intervals(events, span_start, now_ts),
                           span_start, now_ts) / 60.0
        src = "transcript"
    else:
        idle, src = silence, "record"
    return {"idle_min": round(idle, 1), "idle_src": src, "denials": denials,
            "over_cap_reports": over, "respawn_cost_usd": round(respawn, 2),
            "respawn_excluded": excluded}, unmeasured


def rewrites_delta(events, sid, meter):
    """(rewrites, total, since): the billed line's rewrites figure is cumulative over the head
    session, so the field is its change since the same head's previous boundary that carried
    one — a head's first boundary keeps the figure, the change since the head started. None
    throughout when this line carries no figure; a record naming no head session cannot tell
    one head's boundaries from another's, so its figure is kept and the label says why."""
    total = billed_field(meter, REWRITES_RE, int)
    if total is None:
        return None, None, None
    if not sid:
        return total, total, "head start (no head session in the record)"
    for i in range(len(events) - 1, -1, -1):
        ev = events[i]
        if ev.get("event") != "phase-boundary" or session_at(events, i) != sid:
            continue
        prev = billed_field(ev.get("meter"), REWRITES_RE, int)
        if prev is not None:
            return total - prev, total, boundary_label(ev)
    return total, total, "head start"


# ------------------------------------------------------------------------------ git --------

def git(vault, args, timeout=COMMIT_TIMEOUT_S):
    try:
        proc = subprocess.run(["git"] + args, cwd=vault, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "", "timed out after %d s" % timeout
    except OSError as exc:
        return 127, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def ident(text):
    m = re.match(r"^(.*?)\s*<([^>]*)>", text.strip())
    return (m.group(1), m.group(2)) if m else (text.strip(), "")


def tail_of(out, err):
    lines = (err or out or "").strip().splitlines()
    return lines[-1][:160] if lines else ""


def checkpoint_commit(vault, msg):
    """git add -A and git commit as the owner: author must equal committer, no attribution
    line; the short sha on success, `none (nothing to commit)`, or `failed <reason>` — never
    retried, never reset."""
    for bad in ("Co-Authored", "Generated"):
        if bad in msg:
            return "failed the message carries '%s'" % bad
    rc, out, err = git(vault, ["rev-parse", "--is-inside-work-tree"])
    if rc != 0 or out.strip() != "true":
        return "failed %s is not a git work tree (%s)" % (vault, tail_of(out, err))
    rc, author, err = git(vault, ["var", "GIT_AUTHOR_IDENT"])
    rc2, committer, err2 = git(vault, ["var", "GIT_COMMITTER_IDENT"])
    if rc or rc2:
        return "failed identity unresolved (%s)" % tail_of("", err or err2)
    if ident(author) != ident(committer):
        return "failed author ident %s <%s> differs from committer ident %s <%s>" % (
            ident(author) + ident(committer))
    rc, out, err = git(vault, ["add", "-A"])
    if rc:
        return "failed git add (%s)" % tail_of(out, err)
    rc, out, err = git(vault, ["diff", "--cached", "--quiet"])
    if rc == 0:
        return "none (nothing to commit)"
    if rc != 1:
        return "failed git diff --cached (%s)" % tail_of(out, err)
    rc, out, err = git(vault, ["commit", "-q", "-m", msg])
    if rc:
        return "failed git commit exit %d (%s)" % (rc, tail_of(out, err))
    rc, out, err = git(vault, ["log", "-1", "--format=%H%x00%an%x00%ae%x00%cn%x00%ce%x00%B"])
    if rc:
        return "failed commit made but unreadable (%s)" % tail_of(out, err)
    sha, an, ae, cn, ce, body = (out.split("\x00", 5) + [""] * 6)[:6]
    if (an, ae) != (cn, ce):
        return "failed author %s <%s> != committer %s <%s> (%s)" % (an, ae, cn, ce, sha[:7])
    for bad in ("Co-Authored", "Generated"):
        if bad in body:
            return "failed the commit body carries '%s' (%s)" % (bad, sha[:7])
    return sha[:7]


def push(vault):
    rc, out, err = git(vault, ["push", "-q"], timeout=COMMIT_TIMEOUT_S)
    if rc == 0:
        return "ok"
    return "failed %s" % (tail_of(out, err) or "exit %d" % rc)


# ---------------------------------------------------------------------- reset times --------

AMPM_RE = re.compile(r"resets?\s*(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", re.I)
ISO_IN_TEXT_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?")


def next_clock(hour, minute, now_ts):
    lt = time.localtime(now_ts)
    candidate = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, hour, minute, 0, 0, 0, -1))
    if candidate <= now_ts:
        candidate += 86400
    return candidate


def parse_reset_text(text, now_ts):
    """(epoch, source) from a stop text: an ISO time, else `resets (at) h[:mm] [am|pm]`;
    (None, None) when neither is there — the caller falls back, never guesses."""
    m = ISO_IN_TEXT_RE.search(text)
    if m:
        t = parse_ts(m.group(0))
        if t is not None:
            return t, "stop text ISO %s" % m.group(0)
    m = AMPM_RE.search(text)
    if m:
        hour, minute = int(m.group(1)), int(m.group(2) or 0)
        meridian = (m.group(3) or "").lower()
        if meridian == "pm" and hour < 12:
            hour += 12
        if meridian == "am" and hour == 12:
            hour = 0
        if hour <= 23 and minute <= 59:
            return next_clock(hour, minute, now_ts), "stop text '%s'" % m.group(0).strip()
    return None, None


def parse_reset_at(value, now_ts):
    if re.fullmatch(r"\+\d+s", value):
        return now_ts + int(value[1:-1])
    m = re.fullmatch(r"(\d{1,2}):(\d{2})", value)
    if m and int(m.group(1)) <= 23 and int(m.group(2)) <= 59:
        return next_clock(int(m.group(1)), int(m.group(2)), now_ts)
    t = parse_ts(value)
    if t is not None:
        return t
    die("--reset-at %r is neither HH:MM, +Ns nor an ISO time" % value)


# ------------------------------------------------------------------ subcommands ------------

def band_value(arg, m):
    """A band edge, `unmetered`, `limit` (a head the account window stopped, D30) or `error`
    (a head the supervisor found stopped in error, C2 N6)."""
    band = arg if arg is not None else (str(m["band"]) if m.get("context") is not None
                                        else "unmetered")
    if band not in ("unmetered", "limit", "error") and not band.isdigit():
        die("--band must be a band edge, 'unmetered', 'limit' or 'error', got %r" % band)
    return int(band) if band.isdigit() else band


def session_spent(line):
    return billed_field(line, r"session \$([0-9.]+)", float)


def spent_sum(events, start):
    """(Σ spent_usd over every head-exit, this session's own head-exit if one follows its start
    index): critic C2 N5, the envelope is never re-granted per head."""
    total, own = 0.0, None
    for i, e in enumerate(events):
        if e.get("event") != "head-exit":
            continue
        if isinstance(e.get("spent_usd"), (int, float)):
            total += float(e["spent_usd"])
        if i > start:
            own = e
    return round(total, 2), own


def envelope_left(events, run, meter_override, start):
    """(remainder, source): the envelope minus every head-exit's spent_usd minus this session's
    billed total — taken from its own head-exit when that carries spent_usd, else metered now.
    (None, reason) when the envelope is absent or the meter gives no session total."""
    envelope = run_open(events).get("envelope_usd")
    if envelope is None:
        return None, "run-open carries no envelope_usd"
    spent, own = spent_sum(events, start)
    if own is not None and isinstance(own.get("spent_usd"), (int, float)):
        return round(float(envelope) - spent, 2), (
            "envelope $%s minus $%.2f spent over every head-exit" % (envelope, spent))
    total = session_spent(meter_line(events, run, meter_override))
    if total is None:
        return None, "the meter gave no session total"
    return round(float(envelope) - spent - total, 2), (
        "envelope $%s minus $%.2f spent by earlier heads minus session $%.2f"
        % (envelope, spent, total))


def cmd_run_open(a):
    path = record_path(a.run)
    events = read_record(path)[0] if os.path.isfile(path) else []
    if last_index(events, ("run-open",)) >= 0:
        die("run %s already has a run-open; a later head records run-resume" % a.run)
    token(a.session, "session id")
    handoff = os.path.realpath(os.path.expanduser(a.handoff))
    if not os.path.isfile(handoff):
        die("hand-off document not found: %s" % handoff)
    pid, src = head_pid(a.pid)
    ev = event(a.run, "run-open", session=a.session, head=a.head, regime=a.regime,
               regime_src=a.regime_src, handoff=handoff, detail=a.detail, pid_src=src,
               session_kind=a.session_kind)
    if pid is not None:
        ev["pid"] = pid
    if a.envelope_usd is not None:
        ev["envelope_usd"] = a.envelope_usd
    ev["grants_file"] = grants_path(a.run, a.grants_file)
    ev["on_limit"], ev["on_limit_src"] = on_limit_choice(a, ev["grants_file"])
    ev["viewer"], ev["viewer_src"] = viewer_choice(a, ev["grants_file"])
    if a.dry_run:
        say("run-open: dry run · %s" % json.dumps(ev, ensure_ascii=False))
        open_console(a.run, viewer=ev["viewer"], dry_run=True)
        return 0
    write_grants(a.run, "run-open", a)
    write_pointer(a.run, a.session)
    append_record(path, ev)
    say("run-open: %s · session %s (session_kind %s) · pid %s (%s) · hand-off %s · grants %s · "
        "on_limit %s (%s) · viewer %s (%s)"
        % (a.run, a.session[:8], ev["session_kind"], "none" if pid is None else pid, src,
           handoff, ev["grants_file"], ev["on_limit"], ev["on_limit_src"], ev["viewer"],
           ev["viewer_src"]))
    # The run's own window, at once and unguarded: a run-open is the run's first act, so no
    # console can be alive for it yet. A viewer failure never fails the launch.
    open_console(a.run, viewer=ev["viewer"])
    return 0


def cmd_run_resume(a):
    path = record_path(a.run)
    events = require_record(path)
    sid, how = a.session, "arg"
    if sid == "auto":
        i = last_index(events, ("head-successor",))
        if i < 0:
            die("--session auto needs a head-successor event; pass --session ID")
        sid, how = events[i].get("session_id"), "head-successor"
    token(sid, "session id")
    pid, src = head_pid(a.pid)
    ho = run_open(events).get("handoff")
    stale = None
    if ho and os.path.isfile(ho):
        state, why = pack_state(events, ho)
        if state == "stale":
            stale = why
            say("warn: the hand-off's in-flight pack is stale — %s; re-derive it with `handoff "
                "--inflight-from-record` or write a fresh pack before the next item" % why)
    ev = event(a.run, "run-resume", session=sid, head=a.head, detail=a.detail, pid_src=src)
    if pid is not None:
        ev["pid"] = pid
    ev["grants_file"] = grants_path(a.run, a.grants_file)
    # A resume with no --grant and no --write keeps the grants file it finds: the seed's file
    # carries the pre-flight's W list, and the successor's first act names no flags, so a
    # rewrite here narrowed every successor to the default writes (found live 2026-09-06, run 3:
    # the head fence denied the head's own install; register entry of that date). Explicit
    # flags still rewrite, as `grants` does.
    keep = (not a.grant and not a.write and getattr(a, "on_limit", None) is None
            and getattr(a, "viewer", None) is None
            and os.path.isfile(ev["grants_file"]))   # --on-limit or --viewer alone rewrites
    if keep:
        ev["grants"] = "kept"
    ev["on_limit"], ev["on_limit_src"] = on_limit_choice(a, ev["grants_file"])
    ev["viewer"], ev["viewer_src"] = viewer_choice(a, ev["grants_file"])
    if a.dry_run:
        say("run-resume: dry run · %s" % json.dumps(ev, ensure_ascii=False))
        return 0
    if not keep:
        write_grants(a.run, "run-resume", a)
    write_pointer(a.run, sid)
    append_record(path, ev)
    if stale is not None:
        append_record(path, event(a.run, "observation", phase="", what="stale-pack",
                                  note="run-resume: " + stale))
    say("run-resume: %s · session %s (%s) · pid %s (%s) · grants %s%s · on_limit %s · viewer %s"
        % (a.run, sid[:8], how, "none" if pid is None else pid, src, ev["grants_file"],
           " (kept)" if keep else "", ev["on_limit"], ev["viewer"]))
    return 0


LEDGER_HINT = (" — a record with no run-open is a plain lane run: `ledger --observation \"<what>\"`"
               " writes an observation there, with no hand-off row")


def ledger_observation(a, path):
    """`ledger --observation`: ONE observation event on any record that exists, and no hand-off
    row. On a plain record (no `run-open`) it is the only ledger form there is; on a record with
    a `run-open` it is the head's aside that is not a finding, so the findings ledger keeps only
    findings. `--phase` is optional and the phase is empty without it."""
    events = read_existing_record(path)
    shape = "plain lane run (no run-open)" if is_plain_run(events) else "run-open present"
    ev = event(a.run, "observation", phase=a.phase or "", what=a.observation)
    if a.dry_run:
        say("ledger --observation: dry run · %s · %s"
            % (shape, json.dumps(ev, ensure_ascii=False)))
        return 0
    append_record(path, ev)
    say("ledger: observation recorded (%s) · %s · no hand-off row"
        % (one_line(a.observation)[:70], shape))
    return 0


def cmd_ledger(a):
    path = record_path(a.run)
    if a.observation is not None:
        return ledger_observation(a, path)
    missing = [f for f in ("phase", "what", "evidence", "routing") if getattr(a, f) is None]
    if missing:
        die("ledger needs %s, or --observation \"<what>\" for an observation with no ledger row"
            % ", ".join("--" + m for m in missing))
    events = require_record(path, LEDGER_HINT)
    ho = handoff_of(events, a.handoff)
    lines = read_text(ho, "hand-off").split("\n")
    span = table_span(lines, "Findings ledger")
    if span is None:
        die("no table under a '## Findings ledger' heading in %s" % ho)
    row = "| %s | %s | %s | %s | %s |" % (hhmm(), cell(a.phase), cell(a.what),
                                         cell(a.evidence), cell(a.routing))
    ev = event(a.run, "observation", phase=a.phase, what=a.what,
               note="evidence: %s · routing: %s" % (one_line(a.evidence), one_line(a.routing)))
    n = span[1] - span[0]
    if a.dry_run:
        say("ledger: dry run · row %d would be %s" % (n, row))
        return 0
    lines.insert(span[1] + 1, row)
    write_atomic(ho, "\n".join(lines))
    append_record(path, ev)
    say("ledger: row %d appended (%s) · observation recorded" % (n, one_line(a.what)[:70]))
    return 0


def refresh_figures(lines, ro, meter, a=None):
    """The morning report's spend and warnings bullets, plus shipped, waits and saving when
    given. False when the section is missing."""
    spend = meter + (" · envelope $%s" % ro["envelope_usd"]
                     if ro.get("envelope_usd") is not None else "")
    if not set_bullet(lines, "spend", spend):
        return False
    set_bullet(lines, "warnings", str(table_rows(lines, "Findings ledger")), number_only=True)
    for key in ("shipped", "waits", "saving"):
        value = getattr(a, key, None)
        if value is not None:
            set_bullet(lines, key, value)
    return True


def cmd_boundary(a):
    path = record_path(a.run)
    events = require_record(path)
    ro = run_open(events)
    ho = handoff_of(events, a.handoff)
    prev = last_index(events, ("phase-boundary",))
    if prev < 0:
        prev = last_index(events, ("run-open",))
    meter = meter_line(events, a.run, a.meter_line)
    sid, _ = head_session(events)
    warning = grants_warning(events, a.run, sid)
    if warning:
        say(warning)
    m = measure_head(sid)
    fields, unmeasured = waste_fields(events, prev, transcript=m.get("transcript"))
    ev = event(a.run, "phase-boundary", **{"from": a.from_, "to": a.to})
    ev.update(disposition=a.disposition, meter=meter, waste=a.waste, context=context_text(m),
              next=a.next)
    ev.update(fields)
    ev["rewrites"], ev["rewrites_total"], ev["rewrites_since"] = rewrites_delta(events, sid, meter)
    lines = read_text(ho, "hand-off").split("\n")
    problems = []
    span = table_span(lines, "Trace")
    if span is None:
        problems.append("no table under a '## Trace' heading")
    else:
        lines.insert(span[1] + 1, "| %s | %s → %s | %s | %s | %s |" % (
            hhmm(), cell(a.from_), cell(a.to), cell(a.disposition), cell(meter), cell(a.waste)))
    if not refresh_figures(lines, ro, meter, a):
        problems.append("no '## Morning report' section")
    if a.dry_run:
        say("boundary: dry run · %s" % json.dumps(ev, ensure_ascii=False))
        if problems:
            say("hand-off: would NOT refresh — %s" % "; ".join(problems))
        return 0
    write_atomic(ho, "\n".join(lines))
    if a.commit is not None:
        ev["commit"] = checkpoint_commit(vault_root(), a.commit)
    append_record(path, ev)
    say("boundary: %s → %s · idle %s min · denials %d · over-cap %d · re-spawn $%.2f · "
        "rewrites %s · context %s%s%s · idle src %s · rewrites since %s%s" % (
            a.from_, a.to, fields["idle_min"], fields["denials"], fields["over_cap_reports"],
            fields["respawn_cost_usd"], "n/a" if ev["rewrites"] is None else ev["rewrites"],
            ev["context"], " · commit %s" % ev["commit"] if "commit" in ev else "",
            " · %d report(s) not word-counted" % unmeasured if unmeasured else "",
            fields["idle_src"], ev["rewrites_since"] or "n/a",
            " · %d resumed lane(s) excluded from re-spawn" % fields["respawn_excluded"]
            if fields["respawn_excluded"] else ""))
    say("meter: %s" % meter)
    if problems:
        say("hand-off: NOT refreshed — %s" % "; ".join(problems))
        return 3
    return 0


def first_usage(path):
    """The stock of the transcript's FIRST qualifying assistant usage record, read from the
    file start under the watermark's own rule (not sidechain, role assistant, model not
    synthetic, stock above zero); None when there is none or the file is unreadable."""
    module, _ = watermark()
    keys = getattr(module, "USAGE_KEYS", None) or (
        "input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
    to_int = getattr(module, "_int", None) or (lambda v: int(v) if isinstance(v, int) else 0)
    if not path:
        return None
    try:
        handle = open(path, "rb")
    except OSError:
        return None
    with handle:
        for line in handle:
            if b'"usage"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict) or rec.get("isSidechain"):
                continue
            msg = rec.get("message")
            if not isinstance(msg, dict) or msg.get("role") != "assistant":
                continue
            usage = msg.get("usage")
            if not isinstance(usage, dict) or str(msg.get("model", "")).startswith("<synthetic"):
                continue
            stock = sum(to_int(usage.get(k)) for k in keys)
            if stock > 0:
                return stock
    return None


def same_session_resume(events, scope):
    """True when the session event this gate's scope opens at is a run-resume that names the
    session the previous session-naming head event named AND that session already recorded a
    gate before the resume. The resumed process kept its context, so its transcript's first call
    after the resume carries the whole session rather than the head's orientation read (the
    register entry of 2026-09-05 records 337,762 tokens on such a gate; the figure varies with
    the session, and the gate is nulled whatever its size).
    The earlier gate is what makes the test sound: a head-successor and the run-resume its
    successor writes share a session id BY DESIGN, so the shared id alone would null every
    successor's first gate, which is a real orientation figure. A session that has already
    gated once has been measured once; a fresh one has not."""
    i = scope - 1
    if i < 0 or events[i].get("event") != "run-resume":
        return False
    sid = events[i].get("session")
    if not sid:
        return False
    start, prior = -1, None
    for j in range(i - 1, -1, -1):
        if events[j].get("event") in SESSION_EVENTS:
            start = j
            prior = (events[j].get("session_id")
                     if events[j].get("event") == "head-successor" else events[j].get("session"))
            break
    if prior != sid:
        return False
    return any(e.get("event") == "gate" for e in events[start + 1:i])


def orientation(events, scope, m):
    """(tokens, note) for a session's first gate (D41): the context now minus the transcript's
    first-call context; None with the reason when either is absent, and always None after a
    head-resumed event or a same-session run-resume, whose first call carries the whole
    session."""
    if any(e.get("event") == "head-resumed" for e in events[scope:]):
        return None, "unmeasured after a resume"
    if same_session_resume(events, scope):
        return None, "unmeasured after a same-session resume"
    if m.get("context") is None:
        return None, "unmetered gate: %s" % m.get("reason", "unknown")
    first = first_usage(m.get("transcript"))
    if first is None:
        return None, "no qualifying first usage record in %s" % m.get("transcript")
    return m["context"] - first, None


def usd(value):
    """A signed dollar figure with the sign before the symbol: `$80.38`, `-$9.62`."""
    return ("-$%.2f" % -value) if value < 0 else ("$%.2f" % value)


def envelope_status(events, run, meter_override, start):
    """(the gate line's envelope text, the remainder or None, the source): `envelope: none` when
    run-open carries no envelope_usd; `envelope: unmeasured (<reason>)` when `envelope_left`
    has no number (the meter gave no session total); else `envelope: $<spent> of $<envelope>,
    remainder $<r>`, spent being the envelope minus the remainder `envelope_left` computed."""
    envelope = run_open(events).get("envelope_usd")
    if envelope is None or isinstance(envelope, bool):
        return "envelope: none", None, "run-open carries no envelope_usd"
    left, why = envelope_left(events, run, meter_override, start)
    if left is None:
        return "envelope: unmeasured (%s)" % why, None, why
    spent = round(float(envelope) - left, 2)
    return ("envelope: %s of %s, remainder %s" % (usd(spent), usd(float(envelope)), usd(left)),
            left, why)


def envelope_stop(path, a, env_text, env_why, figure):
    """The envelope stop: the stop-condition event (which envelope, lane head, the figures in
    its note) and the gate's exit 5. The run ends here; a successor refuses on the same figure."""
    figures = env_text[len("envelope: "):]
    append_record(path, event(
        a.run, "stop-condition", which="envelope", lane="head",
        action="gate refused item %s: the envelope is spent" % a.to,
        note="%s (%s)" % (figures, env_why)))
    say("gate: %s · %s · %s · REFUSED (stop-condition envelope: the remainder is at or below "
        "zero) → the run stops here; the owner tops up the envelope before any successor"
        % (a.to, figure, env_text))
    return EXIT_ENVELOPE


def cmd_gate(a):
    path = record_path(a.run)
    events = require_record(path)
    sid, sev = head_session(events)
    scope = last_index(events, SESSION_EVENTS) + 1
    prior = [e for e in events[scope:] if e.get("event") == "gate"]
    m = measure_head(sid)
    is_armed, how = armed(sid)
    warning = grants_warning(events, a.run, sid)
    if warning:
        say(warning)
    w, e = window(), edges()
    threshold = e[1]
    orient = orientation(events, scope, m) if not prior else None
    # The envelope (register entry 2026-09-07): measured at every gate, on the same session
    # index the successor uses; a remainder at or below zero is the stop, armed or not.
    env_text, env_left, env_why = envelope_status(events, a.run, a.meter_line, scope - 1)
    spent_out = env_left is not None and env_left <= 0
    if m.get("context") is None:
        second = bool(prior) and prior[-1].get("metered") is False
        decision = "refuse" if ((second and is_armed) or spent_out) else "allow"
        ev = event(a.run, "gate", item=a.to, context=None, percent=None, band="unmetered",
                   armed=is_armed, decision=decision, metered=False)
        if orient is not None:
            ev["orientation_tokens"], ev["orientation_note"] = orient
        obs = event(a.run, "observation", phase=a.phase, what="gate unmetered",
                    note="item %s: %s%s" % (a.to, m["reason"],
                                            "; second consecutive" if second else ""))
        if a.dry_run:
            say("gate: dry run · unmetered (%s) · %s · %s" % (m["reason"], decision, env_text))
            return 0
        append_record(path, ev)
        append_record(path, obs)
        if spent_out:
            return envelope_stop(path, a, env_text, env_why, "unmetered (%s)" % m["reason"])
        if decision == "refuse":
            append_record(path, event(
                a.run, "stop-condition", which="unmetered", lane="head",
                action="gate refused item %s: second consecutive unmetered gate (armed by %s)"
                       % (a.to, how), note=m["reason"]))
            say("gate: unmetered (%s) · second consecutive · armed (%s) · REFUSED item %s → "
                "handoff --final --band unmetered, then successor · %s"
                % (m["reason"], how, a.to, env_text))
            return 7
        say("gate: unmetered (%s) · %s · item %s allowed%s · %s" % (
            m["reason"], "second consecutive" if second else "first miss", a.to,
            " · soft: fix the metering" if second else "", env_text))
        return 0
    over = m["context"] * 100 >= threshold * w
    decision = "refuse" if ((over and is_armed) or spent_out) else "allow"
    ev = event(a.run, "gate", item=a.to, context=m["context"], percent=m["percent"],
               band=m["band"], armed=is_armed, decision=decision, metered=True)
    figure = "context %s (%d %%) · band %d · armed %s" % (
        format(m["context"], ","), m["percent"], m["band"], how if is_armed else "no")
    if orient is not None:
        ev["orientation_tokens"] = orient[0]
        if orient[1]:
            ev["orientation_note"] = orient[1]
        else:
            figure += " · orientation %s" % format(orient[0], ",")
    if a.dry_run:
        say("gate: dry run · %s · %s · %s · %s" % (a.to, figure, decision, env_text))
        return 0
    append_record(path, ev)
    if spent_out:
        return envelope_stop(path, a, env_text, env_why, figure)
    if decision == "refuse":
        append_record(path, event(
            a.run, "stop-condition", which="band", lane="head",
            action="gate refused item %s at %d %% (edge %d, armed by %s)"
                   % (a.to, m["percent"], threshold, how),
            note="handoff --final --band %d, watch in-flight lanes, then successor" % threshold))
        say("gate: %s · %s · REFUSED (stop-condition band) → handoff --final --band %d, watch "
            "in-flight lanes, then successor · %s" % (a.to, figure, threshold, env_text))
        return 4
    warn = (" · warn: at or above the second edge (%d %%), soft — finish what is in flight, "
            "start nothing new" % threshold) if over else ""
    say("gate: %s · %s · allow%s · %s" % (a.to, figure, warn, env_text))
    return 0


def pack_missing(text):
    """The next-task pack's labels (D41) absent from the text: each must start a line, after
    an optional `- ` or `* ` bullet."""
    found = set(PACK_LINE_RE.findall(text or ""))
    return [label for label in PACK_LABELS if label[:-1] not in found]


def stamp_pack(text):
    """The in-flight pack under one `- pack written: <ISO>` first line: an earlier stamp, or a
    re-derivation header, is dropped first, so the section's age is the age of this write."""
    body = [line for line in str(text).rstrip("\n").split("\n") if not PACK_STAMP_RE.match(line)]
    while body and not body[0].strip():
        body.pop(0)
    return "\n".join([PACK_STAMP + now()] + body)


def pack_stamp(lines):
    """(epoch, the stamp as written) of the `## In flight` section's age stamp; (None, reason)
    when the section, the stamp or a parsable timestamp is missing."""
    text = section_text(lines, SECTIONS["inflight"])
    if text is None:
        return None, "the hand-off carries no '## In flight' section"
    m = PACK_STAMP_RE.search(text)
    if not m:
        return None, "the in-flight pack carries no `%s<timestamp>` stamp" % PACK_STAMP.strip()
    epoch = parse_ts(m.group(1))
    if epoch is None:
        return None, "the pack stamp %r is not a timestamp this script parses" % m.group(1)
    return epoch, m.group(1)


def boundary_index(events):
    """The index of the pack-age guard's anchor — the last phase-boundary or head-exit, a
    `pack: true` head-exit skipped (see boundary_stamp) — or -1. Both the age comparison and the
    re-derivation read it, so `since the boundary` means the same span in each."""
    for i in range(len(events) - 1, -1, -1):
        ev = events[i]
        if ev.get("event") not in BOUNDARY_EVENTS:
            continue
        if ev.get("event") == "head-exit" and ev.get("pack") is True:
            continue
        return i
    return -1


def boundary_stamp(events):
    """(epoch, event) of the record's last phase-boundary or head-exit — the pack-age guard's
    anchor — else (None, None). A head-exit carrying `pack: true` is skipped: `handoff --final`
    writes the pack and that head-exit in one call, so the pack cannot be older than it, and
    the literal rule would call every good hand-over pack stale on the second boundary."""
    i = boundary_index(events)
    if i < 0:
        return None, None
    return parse_ts(events[i].get("ts")), events[i]


def pack_state(events, ho):
    """(state, note) for the hand-off's in-flight pack against that anchor: `no-boundary` (the
    head has closed nothing yet, so the pack is fresh by definition), `fresh`, `stale` (older
    than the boundary: the head moved on and the pack did not), `unstamped` (a hand-off written
    before this guard, or by hand: left alone, since re-deriving over it would overwrite the
    head's judgement) or `unmeasured`. The note names both timestamps."""
    btime, bev = boundary_stamp(events)
    if bev is None:
        return "no-boundary", ("the record carries no phase-boundary or head-exit event: the "
                               "pack is fresh by definition")
    label = "%s at %s" % (bev.get("event"), bev.get("ts", "no ts"))
    ptime, detail = pack_stamp(read_text(ho, "hand-off").split("\n"))
    if ptime is None:
        return "unstamped", "%s; the anchor is the %s" % (detail, label)
    if btime is None:
        return "unmeasured", ("the %s carries no parsable timestamp, so the pack stamped %s "
                              "cannot be compared with it" % (bev.get("event"), detail))
    if ptime < btime:
        return "stale", "the pack was written %s, before the %s" % (detail, label)
    return "fresh", "the pack was written %s, at or after the %s" % (detail, label)


def spawn_line(ev):
    """A lane-open event as one line: the spawn fields the wrapper writes that are there."""
    parts = []
    for key in ("class", "model", "reason", "brief"):
        if ev.get(key):
            parts.append("%s %s" % (key, one_line(ev[key])))
    return " · ".join(parts) or "the lane-open event carries no class, model, reason or brief"


def derive_inflight(events):
    """`## In flight` derived from the run record: the last boundary's `next`, the lanes still
    open since that boundary with their spawn lines, and the decisions since it, one line each,
    under the header the guard writes. The D41 labels are kept, so a derived pack passes the
    same label check a head's own pack must pass; an empty class says so rather than going
    silent, since a missing line and nothing to report are different claims."""
    i = boundary_index(events)
    since = events[i + 1:] if i >= 0 else list(events)
    lines = [PACK_DERIVED % now()]
    j = last_index(events, ("phase-boundary",))
    if j >= 0 and events[j].get("next"):
        lines.append("- Next: %s (the `next` of the phase-boundary at %s)"
                     % (one_line(events[j]["next"]), events[j].get("ts", "no ts")))
    elif j >= 0:
        lines.append("- Next: unstated — the phase-boundary at %s carries no `next` field"
                     % events[j].get("ts", "no ts"))
    else:
        lines.append("- Next: unstated — the record carries no phase-boundary event")
    open_lanes = []
    for ev in since:
        if not ev.get("lane"):
            continue
        if ev.get("event") == "lane-open":
            open_lanes.append(ev)
        elif ev.get("event") == "lane-closed":
            open_lanes = [e for e in open_lanes if e.get("lane") != ev.get("lane")]
    for ev in open_lanes:
        lines.append("- Needs: lane %s open since %s · %s"
                     % (ev.get("lane"), ev.get("ts", "no ts"), spawn_line(ev)))
    if not open_lanes:
        lines.append("- Needs: no lane is open in the record since the boundary")
    decisions = [ev for ev in since if ev.get("event") == "decision"]
    for ev in decisions:
        lines.append("- Decided: %s (%s, at %s)"
                     % (one_line(ev.get("what") or "unstated"),
                        one_line(ev.get("grant") or "grant unstated"), ev.get("ts", "no ts")))
    if not decisions:
        lines.append("- Decided: no decision event since the boundary")
    return "\n".join(lines)


def guard_pack(a, path, ho):
    """The pack-age guard before a successor starts: a stale `## In flight` is rewritten from
    the record, so the successor is briefed by the record rather than by a pack the head wrote
    before its last boundary. Returns the state; the observation says which."""
    events, _ = read_record(path)
    state, why = pack_state(events, ho)
    if state != "stale":
        say("pack: %s — %s" % (state, why))
        return state
    lines = read_text(ho, "hand-off").split("\n")
    if not set_section(lines, "inflight", derive_inflight(events)):
        append_record(path, event(a.run, "observation", phase="", what="stale-pack",
                                  note="not re-derived (no '## In flight' section): " + why))
        say("pack: STALE — %s · the hand-off carries no '## In flight' section, so nothing was "
            "re-derived" % why)
        return "stale-unwritten"
    write_atomic(ho, "\n".join(lines))
    append_record(path, event(a.run, "observation", phase="", what="stale-pack",
                              note="'## In flight' re-derived from the record: " + why))
    say("pack: STALE — %s · '## In flight' re-derived from the record before the successor "
        "starts" % why)
    return "stale"


def apply_set(lines, key, value):
    if key in BULLETS:
        if not set_bullet(lines, key, value):
            die("no '## Morning report' section")
    elif key in SECTIONS:
        if not set_section(lines, key, value):
            die("no '## %s' section" % SECTIONS[key])
    elif key in APPEND_ONLY:
        die("the ledger and the trace are append-only: use `ledger` and `boundary`")
    else:
        die("unknown key %r; bullets: %s; sections: %s"
            % (key, ", ".join(sorted(BULLETS)), ", ".join(sorted(SECTIONS))))
    return key


def cmd_handoff(a):
    path = record_path(a.run)
    events = require_record(path)
    ho = handoff_of(events, a.handoff)
    lines = read_text(ho, "hand-off").split("\n")
    changes = []
    if a.inflight_file is not None:
        a.inflight = read_text(a.inflight_file, "--inflight-file")
    derived = False
    if a.inflight_from_record:
        if a.inflight is not None:
            die("--inflight-from-record and --inflight/--inflight-file are two sources for one "
                "section: pass one")
        a.inflight, derived = derive_inflight(events), True
        say("handoff: '## In flight' derived from the record · %d lines"
            % len(a.inflight.split("\n")))
        if a.dry_run:
            for line in a.inflight.split("\n"):
                say(line)
    if a.final and a.inflight is None:
        die("--final needs the next-task pack: --inflight-file PATH (or --inflight TEXT) "
            "carrying Next:, Needs: and Decided: (D41)")
    if a.inflight is not None:
        missing = pack_missing(a.inflight)
        if missing and a.final:
            die("the next-task pack lacks %s (each label at the start of a line; an optional "
                "'- ' bullet is allowed)" % ", ".join(missing))
        if missing:
            say("handoff: warn: the in-flight pack lacks %s (a --final pack would be refused)"
                % ", ".join(missing))
        changes.append(apply_set(lines, "inflight",
                                 a.inflight if derived else stamp_pack(a.inflight)))
    for spec in a.set or []:
        key, sep, value = spec.partition("=")
        if not sep:
            die("--set needs key=value, got %r" % spec)
        changes.append(apply_set(lines, key.strip(), value))
    for spec in a.set_file or []:
        key, sep, fpath = spec.partition("=")
        if not sep:
            die("--set-file needs key=path, got %r" % spec)
        changes.append(apply_set(lines, key.strip(), read_text(fpath, "--set-file " + key)))
    exit_ev = None
    if a.final:
        sid, _ = head_session(events)
        m = measure_head(sid)
        pid, psrc = final_pid(events, a.pid)
        say("handoff: pid %s (%s)" % ("none" if pid is None else pid, psrc))
        exit_ev = event(a.run, "head-exit", band=band_value(a.band, m),
                        context=context_text(m), handoff=ho, pack=True,
                        spent_usd=session_spent(meter_line(events, a.run, a.meter_line)))
        if pid is not None:
            exit_ev["pid"] = pid
    if not changes and exit_ev is None:
        say("handoff: nothing to do (no --inflight, --set, --set-file or --final)")
        return 0
    if a.dry_run:
        say("handoff: dry run · would rewrite %s%s" % (
            ", ".join(changes) or "nothing",
            " · head-exit %s" % json.dumps(exit_ev, ensure_ascii=False) if exit_ev else ""))
        return 0
    if changes:
        write_atomic(ho, "\n".join(lines))
    if exit_ev is not None:
        append_record(path, exit_ev)
    say("handoff: %s rewritten%s" % (
        ", ".join(changes) if changes else "nothing",
        " · head-exit recorded (band %s, %s)" % (exit_ev["band"], exit_ev["context"])
        if exit_ev else ""))
    return 0


def resume_prompt(ho):
    text = section_text(read_text(ho, "hand-off").split("\n"), "Resume prompt")
    if not text:
        die("the hand-off's '## Resume prompt' section is missing or empty: %s" % ho)
    return text


def next_out(run):
    n = 1
    while True:
        out = os.path.join(store_root(), "spawn-records", "%s-head-%d.out" % (run, n))
        if not os.path.exists(out):
            return out, n
        n += 1


def head_command(binary, sid, budget, model, effort=None, resume=False):
    """The head's command line: a fresh session (--session-id) or, with resume, the same
    session continued (--resume, D30); model and effort as given."""
    cmd = [binary, "-p", "--resume" if resume else "--session-id", sid, "--output-format",
           "json", "--permission-mode", "bypassPermissions", "--max-budget-usd", "%.2f" % budget]
    if model:
        cmd += ["--model", model]
    if effort:
        cmd += ["--effort", effort]   # the head runs at max (owner rule 2026-09-04); absent, the harness default applies
    return cmd


def cmd_successor(a):
    path = record_path(a.run)
    events = require_record(path)
    hi = last_index(events, HEAD_EVENTS)
    if hi >= 0 and events[hi].get("event") == "head-successor":
        die("a head-successor (session %s) already follows the last head-exit in %s: nothing "
            "started, since its own run-resume is the next head event"
            % (events[hi].get("session_id"), path))
    ro = run_open(events)
    ho = handoff_of(events, a.handoff)
    prompt = resume_prompt(ho)
    xi = last_index(events, ("head-exit",))
    envelope = ro.get("envelope_usd")
    if a.budget_usd is not None:
        budget, bsrc = float(a.budget_usd), "--budget-usd"
    elif xi >= 0 and seed_exit(events[xi]) and isinstance(envelope, (int, float)) \
            and not isinstance(envelope, bool):
        # A seed head-exit records a session that never ran: it left no transcript, so the
        # meter has nothing to read and the remainder is the envelope minus the spend the
        # record already holds — never a premise failure (register entry 2026-09-07).
        spent, _ = spent_sum(events, last_index(events, SESSION_EVENTS))
        budget = round(float(envelope) - spent, 2)
        bsrc = ("envelope (seed): the last head-exit is a seed exit, so envelope $%s minus "
                "$%.2f spent over every head-exit, unmetered" % (envelope, spent))
    else:
        budget, bsrc = envelope_left(events, a.run, a.meter_line,
                                     last_index(events, SESSION_EVENTS))
        if budget is None:
            die("%s; pass --budget-usd" % bsrc)
        if budget <= 0:
            if not a.dry_run:
                append_record(path, event(a.run, "successor-aborted", reason="budget",
                                          note="the envelope is spent (%s leaves $%.2f): the "
                                               "owner tops up" % (bsrc, budget)))
            die("the envelope is spent (%s leaves $%.2f); pass --budget-usd to extend it"
                % (bsrc, budget))
    have_exit = hi >= 0 and events[hi].get("event") == "head-exit"
    sid, sev = head_session(events)
    m = measure_head(sid)
    # The same rule `handoff --final` carries, through the same helper: on a SEEDED record with
    # no --pid the seed's own run-open pid is taken and the parent walk is not run. The walk
    # from here reaches the live attended session, so the head-exit written below — and the
    # predecessor pid the starter then waits on, which reads that event — named the caller
    # instead of the launcher shell the seed pattern exists for (register entries 2026-09-07
    # and 2026-09-08).
    own_pid, own_src = final_pid(events, a.pid)
    if have_exit:
        exit_ev = events[hi]
    else:
        exit_ev = event(a.run, "head-exit", band=band_value(a.band, m),
                        context=context_text(m), handoff=ho,
                        spent_usd=session_spent(meter_line(events, a.run, a.meter_line)))
        if own_pid is not None:
            exit_ev["pid"] = own_pid
        say("successor: pid %s (%s)" % ("none" if own_pid is None else own_pid, own_src))
    if a.predecessor_pid is not None:
        pred, psrc = int(a.predecessor_pid), "--predecessor-pid"
    elif exit_ev.get("pid") is not None:
        pred, psrc = int(exit_ev["pid"]), "head-exit"
    elif sev is not None and sev.get("pid") is not None:
        pred, psrc = int(sev["pid"]), sev["event"]
    else:
        pred, psrc = None, "none: %d s of transcript silence is the proxy" % SILENCE_PROXY_S
    if not have_exit:
        exit_ev["pack"] = False
    if a.reset_at:
        parse_reset_at(a.reset_at, time.time())   # refuse a malformed value now, not at 3 am
    out, _ = next_out(a.run)
    transcript = transcript_for(sid) if sid else ""
    plan = ("starter: wait ≤%d s for pid %s (%s); abort if a head-successor already follows "
            "the head-exit, if the previous head-exit was unmetered too, or on timeout; then "
            "from %s start the successor with the resume prompt (%d chars) on stdin, env "
            "AIMYTH_HANDSOFF=1 AIMYTH_HANDSOFF_RUN=%s%s, budget $%.2f (budget_src: %s), output %s, and "
            "supervise it (D30)" % (
                a.wait_s, "none" if pred is None else pred, psrc, vault_root(), len(prompt),
                a.run, " CLAUDE_CONFIG_DIR=%s" % a.config_dir if a.config_dir else "", budget,
                bsrc, out))
    cmd = head_command(a.harness_bin, "<fresh uuid4>", budget, a.model, a.effort)
    if a.dry_run:
        say("successor: dry run · %s" % plan)
        say("command: %s < resume prompt" % " ".join(cmd))
        open_console_if_dark(a.run, dry_run=True)
        return 0
    if not have_exit:
        append_record(path, exit_ev)
    starter = [sys.executable, "-B", os.path.abspath(__file__), "_starter", "--run", a.run,
               "--handoff", ho, "--budget", "%.2f" % budget, "--out", out, "--wait-s",
               str(a.wait_s), "--harness-bin", a.harness_bin, "--transcript", transcript,
               "--max-wait-s", str(a.max_wait_s), "--probe-interval-s",
               str(a.probe_interval_s), "--tick-s", str(a.tick_s)]
    if a.model:
        starter += ["--model", a.model]
    if a.effort:
        starter += ["--effort", a.effort]
    if a.config_dir:
        starter += ["--config-dir", a.config_dir]
    if pred is not None:
        starter += ["--predecessor-pid", str(pred)]
    if a.reset_at:
        starter += ["--reset-at", a.reset_at]
    if a.probe:
        starter += ["--probe"]   # forwarded only when this caller opted in (2026-09-06)
    if a.meter_line:
        starter += ["--meter-line", a.meter_line]
    log = out + ".starter.log"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(log, "ab") as handle:
        proc = subprocess.Popen(starter, stdin=subprocess.DEVNULL, stdout=handle, stderr=handle,
                                start_new_session=True, cwd=vault_root(),
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    say("successor: %s · starter pid %d detached (log %s) · %s" % (
        "head-exit already recorded" if have_exit
        else "head-exit recorded (band %s)" % exit_ev["band"], proc.pid, log, plan))
    # The successor's window: one per run, so the owner's `q` gets a fresh one and a console
    # still running is never doubled. A viewer failure never fails the launch.
    open_console_if_dark(a.run)
    return 0


def wait_dead(pid, limit):
    """True once the pid is gone; a limit of 0 or less waits without bound (a supervisor)."""
    end = time.time() + limit if limit > 0 else None
    while end is None or time.time() < end:
        if not pid_alive(pid):
            return True
        time.sleep(1)
    return not pid_alive(pid)


def wait_silent(transcript, quiet, limit):
    if not transcript or not os.path.isfile(transcript):
        return True
    end = time.time() + limit
    while time.time() < end:
        try:
            age = time.time() - os.path.getmtime(transcript)
        except OSError:
            return True
        if age >= quiet:
            return True
        time.sleep(5)
    return False


def start_guards(events, hi, gone=True, why=""):
    """The starter's loop guards over the record's last head-exit (index hi): (reason, detail)
    for a successor-aborted event, or (None, None) when the start may go ahead."""
    if hi < 0:
        return "no-head-exit", "the record carries no head-exit to succeed"
    if any(e.get("event") == "head-successor" for e in events[hi + 1:]):
        return "duplicate", "a head-successor already follows the head-exit"
    if not gone:
        return "timeout", why
    earlier = [e for e in events[:hi] if e.get("event") == "head-exit"]
    succ = [e for e in events if e.get("event") == "head-successor"]
    cap = int(os.environ.get("AIMYTH_MAX_SUCCESSORS", "6"))   # backstop, set by judgement:
    # a 20-hour run at ~3 h per head; the repeat-exit check below is the real guard

    def item_before(idx):
        """The item the head was on when it exited: the last gate before the exit, unless
        a head event sits between (then the head exited before any gate)."""
        for e in reversed(events[:idx]):
            if e.get("event") == "gate":
                return e.get("item")
            if e.get("event") in START_EVENTS:
                return None
        return None
    if events[hi].get("band") == "unmetered" and earlier and \
            earlier[-1].get("band") == "unmetered":
        return "unmetered-loop", ("the previous head-exit was unmetered too: an unmetered "
                                  "fault buys at most one restart")
    if len(succ) >= cap:
        return "successor-cap", ("%d successors already started for this run "
                                 "(AIMYTH_MAX_SUCCESSORS=%d)" % (len(succ), cap))
    if earlier and item_before(hi) is not None and \
            item_before(hi) == item_before(events.index(earlier[-1])) and \
            str(events[hi].get("band")) in ("80", "90") and \
            str(earlier[-1].get("band")) in ("80", "90"):
        return "repeat-exit", ("the last two head-exits followed a gate on the same item "
                               "(%s): the item does not fit the window; the hand-off is the "
                               "recovery — rehearsal R6, 2026-09-05, three restarts on one "
                               "item" % item_before(hi))
    return None, None


def abort(path, run, reason, detail):
    append_record(path, event(run, "successor-aborted", reason=reason, note=detail))
    say("supervisor: aborted — %s: %s (the hand-off is the recovery)" % (reason, detail))
    return 1


def head_env(run, config_dir):
    """Every head the starter starts is armed and knows its run (D34: the head fence reads
    AIMYTH_HANDSOFF_RUN before the state directory's pointer)."""
    env = dict(os.environ, AIMYTH_HANDSOFF="1", AIMYTH_HANDSOFF_RUN=run)
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    return env


def feed(proc, text):
    try:
        proc.stdin.write(text.encode("utf-8"))
        proc.stdin.close()
    except (BrokenPipeError, OSError) as exc:
        say("supervisor: the head closed stdin early: %s" % exc)


def out_size(out):
    if not out or out == "none" or not os.path.exists(out):
        return 0
    return os.path.getsize(out)


def start_head(a, path, budget, out, t0, watch=None):
    """A fresh head from the hand-off's resume prompt (the start path the starter has always
    used), then the head-successor and supervise events: (proc, sid, out, offset, start index)
    or None after successor-aborted, reason start-failed."""
    ho = handoff_of(read_record(path)[0], a.handoff)
    guard_pack(a, path, ho)          # a pack older than the last boundary is re-derived first
    prompt = resume_prompt(ho)
    sid = str(uuid.uuid4())
    cmd = head_command(a.harness_bin, sid, budget, a.model, a.effort)
    offset = out_size(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if watch is not None and watch.check():   # the last act before the start (D43; C2 H1: after
        return "stood-down"                     # the meter and the pack guard, nothing follows)
    with open(out, "ab") as handle:
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=handle, stderr=handle,
                                    cwd=vault_root(), env=head_env(a.run, a.config_dir),
                                    start_new_session=True)
        except OSError as exc:
            abort(path, a.run, "start-failed", "cannot start %s: %s" % (a.harness_bin, exc))
            return None
    feed(proc, prompt)
    append_record(path, event(a.run, "head-successor", session_id=sid, pid=proc.pid,
                              config_dir=a.config_dir, budget=budget,
                              started_after_s=round(time.time() - t0), out=out))
    events, _ = read_record(path)
    start = last_index(events, ("head-successor",))
    append_record(path, event(a.run, "supervise", mode="launched", pid=proc.pid, session_id=sid,
                              out=out, supervisor_pid=os.getpid()))
    say("supervisor: head-successor pid %d session %s after %d s → %s"
        % (proc.pid, sid, time.time() - t0, out))
    open_console_if_dark(a.run)   # the supervisor's own successor start after a head exit
    return proc, sid, out, offset, start


def out_result(out, offset):
    """(result, tail, note) from the .out written after `offset`: the LAST JSON object line is
    the harness's result; every other line is the tail text (a limit printed to stderr with no
    result), cut to its last 4,000 characters. A missing, empty or JSON-less file gives an
    empty result and a note naming the premise, never a guess."""
    if not out or out == "none":
        return {}, "", "no .out file: transcript-only classification"
    try:
        with open(out, "rb") as handle:
            handle.seek(offset)
            data = handle.read()
    except OSError as exc:
        return {}, "", "cannot read %s: %s" % (out, exc)
    text = data.decode("utf-8", "replace")
    if not text.strip():
        return {}, "", ("%s is empty" % out if offset == 0
                        else "nothing appended to %s since this head started" % out)
    lines = text.splitlines()
    result, where = {}, -1
    for i in range(len(lines) - 1, -1, -1):
        stripped = lines[i].strip()
        if not stripped.startswith("{"):
            continue
        try:
            rec = json.loads(stripped)
        except ValueError:
            continue
        if isinstance(rec, dict):
            result, where = rec, i
            break
    tail = "\n".join(line for i, line in enumerate(lines) if i != where)[-4000:]
    if not result:
        return {}, tail, "no JSON result line in %s" % out
    return result, tail, "result subtype %s" % result.get("subtype", "?")


def stop_class(events, start, out, offset, rc, transcript):
    """The head's stop, classified (D30): `closed` and `handed-over` from the record after this
    head's start event, the rest from the lane wrapper's own classifier over the .out result,
    the exit code and the transcript. (class, detail) with detail's `text` the stop text."""
    after = events[start + 1:]
    if any(e.get("event") == "run-close" for e in after):
        return "closed", {"note": "a run-close follows this head's start", "text": ""}
    hi = last_index(after, ("head-exit",))
    if hi >= 0:
        if any(e.get("event") == "head-successor" for e in after[hi + 1:]):
            return "handed-over", {"note": "a head-exit follows this head's start and a "
                                           "head-successor follows it: its own successor call "
                                           "owns the next head", "text": ""}
        return "unsucceeded", {"note": "a head-exit follows this head's start with no "
                                       "head-successor after it", "text": ""}
    result, tail, note = out_result(out, offset)
    lane, _, err = lane_module()
    if lane is None:
        return "classifier-missing", {"note": err, "text": ""}
    parsed = lane.parse_transcript(transcript)
    subtype = str(result.get("subtype") or "")
    cls, signal = lane.classify(False, False, parsed, result, subtype, 0 if rc is None else rc,
                                not result, tail)
    text = one_line(result.get("result") or "")
    if not text and tail.strip():
        text = one_line(tail.strip().splitlines()[-1])
    if cls in ("refusal", "max-turns"):
        note, cls = "%s (%s)" % (note, cls), "error"
    if signal:
        note = "%s · %s" % (note, signal)
    return cls, {"note": note, "text": text, "subtype": subtype}


def head_context(sid, events, start):
    """The head's context for the resume decision: its transcript through measure_head, else
    the last gate event of its session (the fallback D30 names), else unmetered."""
    m = measure_head(sid)
    if m.get("context") is not None:
        m["source"] = "transcript"
        return m
    session_start = last_index(events[:start + 1], SESSION_EVENTS)
    for e in reversed(events[session_start + 1:]):
        if e.get("event") == "gate" and isinstance(e.get("context"), int):
            w, ed = window(), edges()
            return {"context": e["context"], "percent": e["context"] * 100 // w,
                    "band": band_edge(e["context"], w, ed), "source": "last gate event",
                    "transcript": m.get("transcript")}
    m["source"] = "none"
    return m


def remainder(events, a, cls, start):
    """(budget, source) for the next head: the envelope minus every head-exit's spent_usd
    minus this session's total (G9, C2 N5); when the session total cannot be metered, the cap
    this supervisor holds (--budget), never above what the envelope has left — except after a
    budget stop, whose unknown remainder is never re-spent. (None, reason) means
    successor-aborted, reason budget: the owner tops up."""
    left, why = envelope_left(events, a.run, a.meter_line, start)
    if left is not None:
        if left <= 0:
            return None, "the envelope is spent: %s leaves $%.2f" % (why, left)
        return left, why
    known = a.budget
    if cls == "budget" or known is None:
        return None, "%s: the remainder is unknown%s" % (
            why, " and a budget stop never re-spends its cap" if known is not None else "")
    cap = float(known)
    envelope = run_open(events).get("envelope_usd")
    if envelope is not None:
        cap = min(cap, round(float(envelope) - spent_sum(events, start)[0], 2))
    if cap <= 0:
        return None, "%s: the cap in hand is spent against the envelope" % why
    return cap, "%s: the cap in hand $%.2f reused" % (why, cap)


def supervisor_stop_file(run):
    """The supervisor's stop marker (D43): `supervise --stop` and `close` write it; a sleeping
    supervisor stands down at its next tick, and a supervisor whose head exits with the marker
    on disk stands down before any successor decision (register entry 2026-09-07).

    It is cleared at exactly three sites, and a bare arming is not one of them: `resume-head`,
    a `successor` CALLED BY A HEAD (the detached `_starter`, which only cmd_successor spawns),
    and the run's own `close`, which writes it as the last thing it does."""
    return os.path.join(store_root(), "spawn-records", token(run, "run id") + "-supervisor.stop")


def clear_stop_marker(run):
    """A marker left by an earlier --stop or close is not this arming's (the heartbeat's rule).
    Called from the three sites supervisor_stop_file names, and nowhere else."""
    marker = supervisor_stop_file(run)
    if os.path.exists(marker):
        try:
            os.remove(marker)
            say("supervisor: a stale stop marker removed (%s)" % marker)
        except OSError as exc:
            note("stale stop marker not removed: %s" % exc)


def run_on_limit(events, run):
    """(value, source, grants file): the run's limit gate (D42) from the DEFAULT grants path —
    the one file the head fence and the status hook read too (C2 H2: a --grants-file override
    is outside the gate, and write_grants refuses `resume` there). A missing file or key is the
    default `stop`, and the source says which."""
    path = grants_path(run)
    value, src = on_limit_of(read_grants(path))
    return value, src, path


class StandDown(object):
    """The limit wait's stand-down watch (D43): the head transcript's byte size and mtime,
    baselined AFTER the stop is classified (so the harness's own stop record sits inside the
    baseline), plus the stop marker. check() records the reason and detail and returns True."""

    def __init__(self, run, transcript, on_limit, src):
        self.run, self.on_limit, self.src = run, on_limit, src
        self.path = transcript if transcript and os.path.isfile(transcript) else None
        self.size, self.mtime = self._stat()
        self.marker = supervisor_stop_file(run)
        self.reason = self.detail = None

    def _stat(self):
        if not self.path:
            return None, None
        try:
            st = os.stat(self.path)
            return st.st_size, st.st_mtime
        except OSError:
            return None, None

    def label(self):
        if self.path and self.size is not None:
            return "transcript %s (%d bytes)" % (self.path, self.size)
        return "unwatched (no transcript file)"

    def check(self):
        if os.path.exists(self.marker):
            self.reason, self.detail = "stopped", "the stop marker %s appeared" % self.marker
            return True
        if self.path:
            size, mtime = self._stat()
            if (size, mtime) != (self.size, self.mtime):
                self.reason = "resumed-by-hand"
                self.detail = ("the head transcript changed during the wait (someone continued "
                               "the session): %s → %s bytes, mtime %s → %s; %s"
                               % (self.size, "gone" if size is None else size,
                                  fmt_ts(self.mtime) if self.mtime else "?",
                                  fmt_ts(mtime) if mtime else "gone", self.path))
                return True
        return False


def stand_down(path, run, reason, detail, on_limit, src, waited):
    """The designed stop (D42, D43): a supervisor-stood-down event and exit 0 — never an abort."""
    append_record(path, event(run, "supervisor-stood-down", reason=reason, on_limit=on_limit,
                              on_limit_src=src, waited_s=round(waited), note=detail))
    say("supervisor: stood down (%s) — %s; the hand-off is the recovery" % (reason, detail))
    return 0


def wait_for_reset(a, path, start, text, stopped_at, watch=None):
    """The limit wait (D28, D30): --reset-at first, else the stop text's reset time, and — only
    when --probe was passed (opt-in, owner ruling 2026-09-06) — the haiku probe under the same
    login every --probe-interval-s; sleeps in --tick-s ticks so a run-close written meanwhile
    ends it; bounded by --max-wait-s. Returns (status, source, waited_s) with status ok, closed,
    reset-timeout or limit-unparsed (no reset time and no --probe: the hand-off is the
    recovery); the record says which."""
    now_ts = time.time()
    if a.reset_at:
        target, source = parse_reset_at(a.reset_at, now_ts), "--reset-at %s" % a.reset_at
    else:
        target, source = parse_reset_text(text, now_ts) if text else (None, None)
    if target is None and not a.probe:
        append_record(path, event(
            a.run, "stop-condition", which="limit-unparsed", lane="head",
            action="no reset time in the stop text, no --reset-at and no --probe (the probe is "
                   "opt-in, owner ruling 2026-09-06): the hand-off is the recovery",
            note=one_line(text or "")[:NOTE_CUT]))
        say("supervisor: limit — no reset time could be parsed and --probe was not passed: no "
            "probe is sent and the hand-off is the recovery")
        return "limit-unparsed", "none", time.time() - stopped_at
    if target is not None:
        plan = "wait until %s (%s)" % (fmt_ts(target), source)
    else:
        plan = "probe every %d s under %s" % (
            a.probe_interval_s,
            "CLAUDE_CONFIG_DIR=%s" % a.config_dir if a.config_dir else "the same login")
    extra = ({"watch": watch.label(), "on_limit": watch.on_limit, "on_limit_src": watch.src}
             if watch is not None else {"watch": "unwatched (hand-run wait)"})
    append_record(path, event(a.run, "stop-condition", which="limit", lane="head",
                              action=plan, note=one_line(text or "")[:NOTE_CUT], **extra))
    say("supervisor: limit — %s" % plan)

    def closed():
        events, _ = read_record(path)
        return any(e.get("event") == "run-close" for e in events[start + 1:])

    def ended(what):
        append_record(path, event(a.run, "observation", phase="", what="wait-reset ended",
                                  note=what))
        say("supervisor: " + what)

    def waited():
        return time.time() - stopped_at

    if target is not None:
        if target - now_ts > a.max_wait_s:
            abort(path, a.run, "reset-timeout", "the reset at %s is %d s away, past --max-wait-s "
                  "%d" % (fmt_ts(target), target - now_ts, a.max_wait_s))
            return "reset-timeout", source, waited()
        while time.time() < target:
            if closed():
                ended("closed during the wait: a run-close follows this head's start")
                return "closed", source, waited()
            if watch is not None and watch.check():
                return "stood-down", source, waited()
            time.sleep(max(0.0, min(a.tick_s, target - time.time())))
        ended("reset reached at %s after %d s" % (fmt_ts(target), waited()))
        return "ok", source, waited()
    last_probe = None
    while True:
        if time.time() - now_ts > a.max_wait_s:
            abort(path, a.run, "reset-timeout", "no probe succeeded in %d s (--max-wait-s %d)"
                  % (time.time() - now_ts, a.max_wait_s))
            return "reset-timeout", "probe", waited()
        due = (last_probe + a.probe_interval_s) if last_probe else time.time()
        while time.time() < due:
            if closed():
                ended("closed during the wait: a run-close follows this head's start")
                return "closed", "probe", waited()
            if watch is not None and watch.check():
                return "stood-down", "probe", waited()
            time.sleep(max(0.0, min(a.tick_s, due - time.time())))
        ok, what = probe(a.harness_bin, a.config_dir)
        last_probe = time.time()
        append_record(path, event(a.run, "observation", phase="", what="wait-reset probe",
                                  note=what))
        if ok:
            ended("probe succeeded after %d s: %s" % (waited(), what))
            return "ok", "probe (%s)" % what, waited()


RESUME_NOTE = (
    "Before anything else run tail -8 on the run record and git status --short; then continue "
    "the item in flight from your own context. The hand-off document may be older than your "
    "last action: trust the record and your context, and refresh the hand-off at the next "
    "boundary.\nLanes closed with exit class limit: resume each with lane.py resume before "
    "anything else in that item.\n")


def resume_head(a, path, sid, budget, bsrc, out, m, cls, waited, source, stopped_at):
    """`claude -p --resume <sid>` from the vault with the resume note on standard input, its
    output appended to the same .out (D30, D31): (proc, out, offset, start index) or None after
    successor-aborted, reason resume-failed."""
    if cls == "limit":
        opening = ("RESUMED after the account window reset. The limit stopped this head at %s; "
                   "the window reset at %s (%s).\n"
                   % (fmt_ts(stopped_at), fmt_ts(stopped_at + waited), source))
    else:
        opening = ("RESUMED after a budget stop. The harness's cap stopped this head at %s; the "
                   "new cap is $%.2f (%s).\n" % (fmt_ts(stopped_at), budget, bsrc))
    if out in (None, "none"):
        out, _ = next_out(a.run)
    cmd = head_command(a.harness_bin, sid, budget, a.model, a.effort, resume=True)
    offset = out_size(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "ab") as handle:
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=handle, stderr=handle,
                                    cwd=vault_root(), env=head_env(a.run, a.config_dir),
                                    start_new_session=True)
        except OSError as exc:
            abort(path, a.run, "resume-failed",
                  "cannot start %s --resume %s: %s" % (a.harness_bin, sid, exc))
            return None
    feed(proc, opening + RESUME_NOTE)
    events, _ = read_record(path)
    n = 1 + sum(1 for e in events
                if e.get("event") == "head-resumed" and e.get("session_id") == sid)
    append_record(path, event(a.run, "head-resumed", session_id=sid, pid=proc.pid,
                              context=m["context"], waited_s=round(waited),
                              reset_source=source, resume_n=n, out=out, budget=budget))
    events, _ = read_record(path)
    start = last_index(events, ("head-resumed",))
    append_record(path, event(a.run, "supervise", mode="launched", pid=proc.pid, session_id=sid,
                              out=out, supervisor_pid=os.getpid()))
    say("supervisor: head-resumed pid %d session %s (resume %d) at %s tokens (%s) after %d s "
        "→ %s" % (proc.pid, sid, n, format(m["context"], ","), m.get("source"), waited, out))
    open_console_if_dark(a.run)   # the in-place resume: `_resume-head`'s own start, and the
                                  # supervisor's resume after a limit reset
    return proc, out, offset, start


def successor_path(a, path, m, band, cls, budget, pid, t0, watch=None):
    """The head-exit the supervisor owes (the head wrote none), then one successor from the
    hand-off under the loop guards: (proc, sid, out, offset, start index) or None."""
    events, _ = read_record(path)
    exit_ev = event(a.run, "head-exit", band=band, context=context_text(m),
                    handoff=handoff_of(events, a.handoff), pack=False, exit_class=cls,
                    spent_usd=session_spent(meter_line(events, a.run, a.meter_line)))
    if pid is not None:
        exit_ev["pid"] = pid
    append_record(path, exit_ev)
    return succeed_exit(a, path, budget, t0, watch)


def succeed_exit(a, path, budget, t0, watch=None):
    """One successor after the record's last head-exit, under the loop guards (idempotent: a
    head-successor that appeared meanwhile is the duplicate guard's refusal)."""
    events, _ = read_record(path)
    reason, detail = start_guards(events, last_index(events, ("head-exit",)))
    if reason:
        abort(path, a.run, reason, detail)
        return None
    out, _ = next_out(a.run)
    return start_head(a, path, budget, out, t0, watch)


def seed_run_open(events):
    """The record's `run-open` event when it marks a seed session (`session_kind: seed`, T7),
    else None. The marking is the record's own field, never the run's or the session's name."""
    for ev in events:
        if ev.get("event") == "run-open" and ev.get("session_kind") == "seed":
            return ev
    return None


def final_pid(events, arg):
    """(pid, source) for the head-exit `handoff --final` writes. --pid wins, as everywhere.

    On a SEEDED record the seed's own recorded pid is taken and the parent walk is not run: the
    launcher shell calls `handoff --final` in its own process, so the walk reaches the LIVE
    attended session instead of the placeholder the run was opened for, and the first starter
    then waits on the launcher itself (register entry 2026-09-07: one launch lost a starter that
    way). A head record — no seed `run-open` — resolves as before. A seed `run-open` that
    recorded no pid falls through to the walk too, since there is nothing better to take."""
    if arg is not None:
        return int(arg), "arg"
    ro = seed_run_open(events)
    if ro is not None and ro.get("pid") is not None:
        try:
            return int(ro["pid"]), "run-open, seed"
        except (TypeError, ValueError):
            pass
    return head_pid(None)


def seed_exit(ev):
    """True when a head-exit records a session that left no transcript: its context reads
    `unmetered (transcript missing …)` and no spend was metered. That is a record opened for a
    head which never ran — a seeded record — and nothing about it is a stop. The test is the
    event's own observable fields; the run's or the session's name is never the key."""
    if ev.get("event") != "head-exit":
        return False
    context = str(ev.get("context") or "")
    return (context.startswith("unmetered") and "transcript missing" in context
            and ev.get("spent_usd") is None)


def previous_stop(events):
    """The exit class of the last head stop the record holds (the supervisor's own `head
    exited` observation), or None. A stop whose head-exit shows the session left no transcript
    is skipped: nothing ran, so it cannot be the first of two consecutive faults (register
    2026-09-06). The head-exit is looked for beside the observation, which the supervisor and
    `handoff --final` write in either order."""
    for i in range(len(events) - 1, -1, -1):
        ev = events[i]
        if ev.get("event") == "observation" and ev.get("what") == "head exited":
            if any(seed_exit(x) for x in events[max(0, i - 1):i + 2]):
                continue
            return ev.get("exit_class")
    return None


def supervise_loop(a, path, sid, proc, pid, out, offset, start, t0):
    """The supervisor (D30): wait for the head's process with no API call, classify its stop,
    act — end, wait and resume, or one successor — and supervise whatever it started, in a
    loop. Exit 0 when the run ended or was handed over, 1 after successor-aborted."""
    while True:
        if proc is not None:
            rc = proc.wait()
            pid = proc.pid
        else:
            wait_dead(pid, 0)
            rc = None
        stopped_at = time.time()
        events, _ = read_record(path)
        cls, d = stop_class(events, start, out, offset, rc, transcript_for(sid) if sid else None)
        if cls == "unsucceeded":
            # C2 N4: the head's own successor call may still be on its way (the starter's wait)
            deadline = stopped_at + a.wait_s
            while time.time() < deadline:
                time.sleep(max(0.0, min(a.tick_s, deadline - time.time())))
                events, _ = read_record(path)
                cls, d = stop_class(events, start, out, offset, rc, None)
                if cls != "unsucceeded":
                    break
        before = previous_stop(events)
        append_record(path, event(a.run, "observation", phase="", what="head exited",
                                  exit_class=cls,
                                  note="session %s exit %s after %d s → %s (%s); output %s"
                                       % (sid, "unknown" if rc is None else rc,
                                          stopped_at - t0, cls, d["note"], out)))
        say("supervisor: session %s exit %s → %s (%s)"
            % (sid, "unknown" if rc is None else rc, cls, d["note"]))
        if cls in ("handed-over", "closed"):
            append_record(path, event(a.run, "observation", phase="", what="supervisor ended",
                                      note="%s: %s" % (cls, d["note"])))
            say("supervisor: %s — ended" % cls)
            return 0
        # The owner's stop outranks every fork below (register entry 2026-09-07: a marker written
        # at 16:22 did not stop the successor started after a SIGTERM at 16:24). A marker on disk
        # when the head exits stands the supervisor down BEFORE any successor decision, whatever
        # the exit was classified as, a signalled head included. It sits under the two forks
        # above because neither decides anything: `closed` is this run's own close, which writes
        # this very marker, and `handed-over` already has its successor.
        marker = supervisor_stop_file(a.run)
        if os.path.exists(marker):
            on_limit, osrc, _ = run_on_limit(events, a.run)
            return stand_down(path, a.run, "stopped",
                              "a stop marker was on disk at the head's exit (%s): no successor "
                              "and no resume after a %s stop" % (marker, cls),
                              on_limit, osrc, time.time() - stopped_at)
        if cls == "classifier-missing":
            return abort(path, a.run, "classifier-missing", d["note"])
        # Two stops of the same fault end the loop, the successor cap being only the backstop:
        # `error` and `budget` in either order, and `completed` against itself — a head that
        # exits completed with neither a head-exit nor a run-close leaves nothing behind for
        # its successor to do differently, so the second such exit is a loop, not progress.
        if (cls in ("error", "budget") and before in ("error", "budget")) or \
                (cls == "completed" and before == "completed"):
            return abort(path, a.run, "repeat-stop", "two consecutive %s and %s stops: the "
                         "head does not get a third start on the same fault" % (before, cls))
        waited, source, watch = 0.0, "none: no wait after a %s stop" % cls, None
        if cls == "limit":
            on_limit, osrc, gpath = run_on_limit(events, a.run)
            if on_limit != "resume":   # the gate's default (D42): stand down, no wait
                append_record(path, event(a.run, "stop-condition", which="limit", lane="head",
                                          action="stand-down: on_limit stop", on_limit=on_limit,
                                          on_limit_src=osrc, grants_file=gpath,
                                          note=one_line(d["text"] or "")[:NOTE_CUT]))
                say("supervisor: limit — on_limit stop (%s): no wait, no resume" % osrc)
                return stand_down(path, a.run, "limit-stop",
                                  "on_limit stop (%s): the limit ends this run's supervision"
                                  % osrc, on_limit, osrc, 0.0)
            watch = StandDown(a.run, transcript_for(sid) if sid else None, on_limit, osrc)
            status, source, waited = wait_for_reset(a, path, start, d["text"], stopped_at,
                                                    watch)
            if status == "stood-down":
                return stand_down(path, a.run, watch.reason, watch.detail, on_limit, osrc,
                                  waited)
            if status == "closed":
                append_record(path, event(a.run, "observation", phase="", what="supervisor ended",
                                          note="closed during the reset wait"))
                say("supervisor: closed — ended")
                return 0
            if status == "limit-unparsed":
                return abort(path, a.run, "limit-unparsed",
                             "no reset time could be parsed from the stop text and --probe was "
                             "not passed (the probe is opt-in, owner ruling 2026-09-06)")
            if status != "ok":
                return 1
        events, _ = read_record(path)
        budget, bsrc = remainder(events, a, cls, start)
        if budget is None:
            return abort(path, a.run, "budget", bsrc)
        if cls == "unsucceeded":
            say("supervisor: the head-exit has no successor after %d s — starting one at $%.2f "
                "(%s)" % (a.wait_s, budget, bsrc))
            started = succeed_exit(a, path, budget, t0)
            if started is None:
                return 1
            proc, sid, out, offset, start = started
            continue
        m = head_context(sid, events, start)
        resumes = sum(1 for e in events
                      if e.get("event") == "head-resumed" and e.get("session_id") == sid)
        if cls in ("limit", "budget") and m.get("context") is not None and \
                m["context"] * 100 < edges()[0] * window() and resumes < RESUME_CAP:
            events, _ = read_record(path)
            if any(e.get("event") in ("head-resumed", "head-successor")
                   for e in events[start + 1:]):
                return abort(path, a.run, "duplicate-resume", "a head-resumed or head-successor "
                             "already follows this head's start: another supervisor got there "
                             "first")
            if watch is not None and watch.check():   # the last act before a start (D43)
                return stand_down(path, a.run, watch.reason, watch.detail, watch.on_limit,
                                  watch.src, waited)
            resumed = resume_head(a, path, sid, budget, bsrc, out, m, cls, waited, source,
                                  stopped_at)
            if resumed is not None:
                proc, out, offset, start = resumed
                continue
        band = {"limit": "limit", "error": "error"}.get(cls) or band_value(None, m)
        say("supervisor: successor path — context %s (%s), band %s, resumes %d, budget $%.2f "
            "(%s)" % (context_text(m), m.get("source"), band, resumes, budget, bsrc))
        started = successor_path(a, path, m, band, cls, budget, pid, t0, watch)
        if started == "stood-down":
            return stand_down(path, a.run, watch.reason, watch.detail, watch.on_limit,
                              watch.src, waited)
        if started is None:
            return 1
        proc, sid, out, offset, start = started


def cmd_starter(a):
    t0 = time.time()
    path = record_path(a.run)
    say("starter: %s pid %d waits for %s" % (
        now(), os.getpid(),
        "pid %d" % a.predecessor_pid if a.predecessor_pid else "transcript silence"))
    if a.predecessor_pid:
        gone = wait_dead(a.predecessor_pid, a.wait_s)
        why = "predecessor pid %d alive after %d s" % (a.predecessor_pid, a.wait_s)
    else:
        gone = wait_silent(a.transcript, SILENCE_PROXY_S, a.wait_s)
        why = "transcript %s still changing after %d s" % (a.transcript, a.wait_s)
    events, _ = read_record(path)
    reason, detail = start_guards(events, last_index(events, ("head-exit",)), gone, why)
    if reason:
        return abort(path, a.run, reason, detail)
    # One of the marker's three clearing sites: this starter is detached by cmd_successor and by
    # nothing else (the only `_starter` spawn in this file), so reaching here means a HEAD called
    # `successor`, and the head's own hand-over clears an earlier arming's marker. The supervisor's
    # own successor path does not come through here — it calls succeed_exit in process, under the
    # stand-down check at the head's exit.
    clear_stop_marker(a.run)
    started = start_head(a, path, a.budget, a.out, t0)
    if started is None:
        return 1
    proc, sid, out, offset, start = started
    return supervise_loop(a, path, sid, proc, None, out, offset, start, t0)


def cmd_supervise_internal(a):
    """The detached half of `supervise`: attach to a running head and run the loop."""
    t0 = time.time()
    path = record_path(a.run)
    events, _ = read_record(path)
    start = last_index(events, START_EVENTS)
    alive = pid_alive(a.pid)
    offset = out_size(a.out) if alive else 0   # a head already gone wrote its result before now
    a.budget = a.budget_usd
    say("supervisor: %s pid %d attached to head pid %d (%s) session %s · out %s" % (
        now(), os.getpid(), a.pid, "alive" if alive else "already gone", a.session, a.out))
    # No clear here: arming a supervisor is not one of the marker's three clearing sites
    # (resume-head, a successor called by a head, close). A run the owner stopped stays stopped
    # across a re-arming, and this supervisor stands down at the head's exit.
    return supervise_loop(a, path, a.session, None, a.pid, a.out, offset, start, t0)


def cmd_supervise(a):
    path = record_path(a.run)
    events = require_record(path)
    if a.stop:   # before any pid resolution: a stopped run has no live head (D43, C1 L8)
        marker = supervisor_stop_file(a.run)
        if a.dry_run:
            say("supervise: dry run · would write the stop marker %s" % marker)
            return 0
        write_atomic(marker, now() + "\n")
        append_record(path, event(a.run, "supervise", mode="stop-requested", marker=marker,
                                  pid=os.getpid()))
        say("supervise: stop marker written (%s) — a sleeping supervisor stands down at its "
            "next tick, at most %d s" % (marker, a.tick_s))
        return 0
    sid, sev = head_session(events)
    if not sid:
        die("no head session in the record: run-open first")
    pid, src = head_pid(a.pid)
    if pid is None:
        die("no harness ancestor to supervise (an attended head has no idle-exit); pass --pid N")
    if a.pid is not None and not pid_alive(pid):
        die("pid %d is not alive: a stopped run has no head to supervise; after a limit use "
            "resume-head or successor (D42; C2 L5)" % pid)
    if a.reset_at:
        parse_reset_at(a.reset_at, time.time())
    out, osrc = a.out, "--out"
    if not out and sev is not None and sev.get("event") == "head-successor" and sev.get("out"):
        out, osrc = sev["out"], "head-successor"
    if not out:
        hits = sorted(globmod.glob(os.path.join(store_root(), "spawn-records",
                                                "%s-head-*.out" % token(a.run, "run id"))),
                      key=os.path.getmtime)
        if hits:
            out, osrc = hits[-1], "newest .out"
    if not out:
        out, osrc = "none", "transcript-only"
    log = os.path.join(store_root(), "spawn-records", "%s-supervise.log" % a.run)
    cmd = [sys.executable, "-B", os.path.abspath(__file__), "_supervise", "--run", a.run,
           "--pid", str(pid), "--session", sid, "--out", out, "--harness-bin", a.harness_bin,
           "--max-wait-s", str(a.max_wait_s), "--probe-interval-s", str(a.probe_interval_s),
           "--tick-s", str(a.tick_s), "--wait-s", str(a.wait_s), "--effort", a.effort]
    if a.probe:
        cmd += ["--probe"]   # never on its own: only when this caller opted in (2026-09-06)
    for flag, value in (("--reset-at", a.reset_at), ("--model", a.model),
                        ("--config-dir", a.config_dir), ("--handoff", a.handoff),
                        ("--meter-line", a.meter_line)):
        if value:
            cmd += [flag, value]
    if a.budget_usd is not None:
        cmd += ["--budget-usd", "%.2f" % a.budget_usd]
    if a.dry_run:
        say("supervise: dry run · pid %d (%s) session %s · out %s (%s) · would detach %s"
            % (pid, src, sid, out, osrc, " ".join(cmd[3:])))
        return 0
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "ab") as handle:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=handle, stderr=handle,
                                start_new_session=True, cwd=vault_root(),
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    append_record(path, event(a.run, "supervise", mode="attached", pid=pid, session_id=sid,
                              out=out, supervisor_pid=proc.pid, log=log))
    say("supervise: pid %d session %s · out %s · detached pid %d" % (pid, sid, out, proc.pid))
    return 0


def cmd_watch(a):
    """`watch --run R` or `watch --session S`: hand the tty to watch.py beside this file (exec,
    so the keys work). `--session` is the attended-session view — one row per background job of
    that session, read from its transcript and the harness's job directory (A4)."""
    script = os.path.join(HERE, "watch.py")
    if not os.path.isfile(script):
        die("no watch.py beside handsoff.py at %s" % script)
    argv = ["--session", a.session] if a.session else ["--run", a.run]
    for flag, value in (("--refresh", a.refresh), ("--vault", a.vault)):
        if value is not None:
            argv += [flag, str(value)]
    for flag, on in (("--once", a.once), ("--plain", a.plain), ("--no-notify", a.no_notify)):
        if on:
            argv.append(flag)
    os.execv(sys.executable, [sys.executable, "-B", script] + argv)


def cmd_resume_head(a):
    """`resume-head` (D42's recovery; critic C2 M4): resume the record's last head session in
    place — armed, evented and supervised — the owner's command after a limit the run stood down
    on, instead of an unarmed hand-run `claude -p --resume`. Detaches at once, like `supervise`."""
    path = record_path(a.run)
    events = require_record(path)
    sid, sev = head_session(events)
    if not sid:
        die("no head session in the record: run-open first")
    out, osrc = a.out, "--out"
    if not out and sev is not None and sev.get("out"):
        out, osrc = sev["out"], sev.get("event")
    if not out:
        hits = sorted(globmod.glob(os.path.join(store_root(), "spawn-records",
                                                "%s-head-*.out" % token(a.run, "run id"))),
                      key=os.path.getmtime)
        if hits:
            out, osrc = hits[-1], "newest .out"
    if not out:
        out, osrc = next_out(a.run)[0], "fresh"
    log = os.path.join(store_root(), "spawn-records", "%s-supervise.log" % a.run)
    cmd = [sys.executable, "-B", os.path.abspath(__file__), "_resume-head", "--run", a.run,
           "--session", sid, "--out", out, "--harness-bin", a.harness_bin,
           "--max-wait-s", str(a.max_wait_s), "--probe-interval-s", str(a.probe_interval_s),
           "--tick-s", str(a.tick_s), "--wait-s", str(a.wait_s), "--effort", a.effort]
    if a.probe:
        cmd += ["--probe"]
    for flag, value in (("--reset-at", a.reset_at), ("--model", a.model),
                        ("--config-dir", a.config_dir), ("--handoff", a.handoff),
                        ("--meter-line", a.meter_line)):
        if value:
            cmd += [flag, value]
    if a.budget_usd is not None:
        cmd += ["--budget-usd", "%.2f" % a.budget_usd]
    if a.dry_run:
        say("resume-head: dry run · session %s · out %s (%s) · would detach %s"
            % (sid, out, osrc, " ".join(cmd[3:])))
        open_console_if_dark(a.run, dry_run=True)
        return 0
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "ab") as handle:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=handle, stderr=handle,
                                start_new_session=True, cwd=vault_root(),
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    append_record(path, event(a.run, "supervise", mode="resume-head", session_id=sid, out=out,
                              supervisor_pid=proc.pid, log=log))
    say("resume-head: session %s · out %s (%s) · detached pid %d" % (sid, out, osrc, proc.pid))
    # A by-hand resume-head is the owner at the desk: a window unless one is already alive.
    open_console_if_dark(a.run)
    return 0


def cmd_resume_head_internal(a):
    """The detached half of `resume-head`: size the head, resume it in place, supervise it."""
    t0 = time.time()
    path = record_path(a.run)
    events, _ = read_record(path)
    start = last_index(events, START_EVENTS)
    a.budget = a.budget_usd
    budget, bsrc = remainder(events, a, "limit", start)
    if budget is None:
        return abort(path, a.run, "budget", bsrc)
    m = head_context(a.session, events, start)
    if m.get("context") is None:
        return abort(path, a.run, "resume-unsized", "the head's context cannot be sized (no "
                     "transcript, no gate event): start the successor from the hand-off instead")
    clear_stop_marker(a.run)
    resumed = resume_head(a, path, a.session, budget, bsrc, a.out, m, "limit", 0.0,
                          "resume-head (by hand, after the reset)", time.time())
    if resumed is None:
        return 1
    proc, out, offset, start = resumed
    return supervise_loop(a, path, a.session, proc, None, out, offset, start, t0)


def cmd_grants(a):
    """Rewrite the run's grants file and run-<sid> pointer (C2 N7): for a head whose file is
    missing or wrong, since a second run-open is refused by design."""
    path = record_path(a.run)
    events = require_record(path)
    sid, _ = head_session(events)
    if not sid:
        die("no head session in the record: run-open first")
    gpath = grants_path(a.run, a.grants_file)
    on_limit, osrc = on_limit_choice(a, gpath)
    viewer, vsrc = viewer_choice(a, gpath)
    payload = grants_payload(a.run, "grants", a.grant, a.write, on_limit, viewer)
    ev = event(a.run, "grants", grants_file=gpath, grants=payload["grants"],
               writes=payload["writes"], session=sid, on_limit=on_limit, on_limit_src=osrc,
               viewer=viewer, viewer_src=vsrc)
    if a.dry_run:
        say("grants: dry run · %s" % json.dumps(ev, ensure_ascii=False))
        return 0
    write_grants(a.run, "grants", a)
    write_pointer(a.run, sid)
    append_record(path, ev)
    say("grants: %s · %d grants · %d writes · on_limit %s (%s) · viewer %s (%s) · pointer run-%s"
        % (ev["grants_file"], len(payload["grants"]), len(payload["writes"]), on_limit, osrc,
           viewer, vsrc, sid[:8]))
    return 0


def read_pidfile(path):
    """(pid, end epoch) from a heartbeat pid file, (None, None) when absent or unreadable."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            parts = handle.read().split()
        return int(parts[0]), float(parts[1])
    except (OSError, ValueError, IndexError):
        return None, None


def cmd_heartbeat(a):
    path = record_path(a.run)
    require_record(path)
    pid_file, stop_file = heartbeat_files(a.run)
    if a.stop:
        if a.dry_run:
            say("heartbeat: dry run · would write the stop marker %s" % stop_file)
            return 0
        write_atomic(stop_file, now() + "\n")
        append_record(path, event(a.run, "heartbeat", action="stopped", pid=os.getpid(),
                                  minutes=None, note="--stop"))
        say("heartbeat: %s · stop marker written (%s)" % (a.run, stop_file))
        return 0
    if a.minutes <= 0:
        die("--minutes must be positive, got %r" % a.minutes)
    armed_pid, armed_end = read_pidfile(pid_file)
    if armed_pid and pid_alive(armed_pid):
        left = max(0.0, ((armed_end or time.time()) - time.time()) / 60.0)
        if not a.dry_run:
            append_record(path, event(a.run, "heartbeat", action="already-armed", pid=armed_pid,
                                      minutes=round(left, 2)))
        say("heartbeat: already armed (pid %d, %d min left)" % (armed_pid, math.ceil(left)))
        return 0
    parent = a.parent_pid if a.parent_pid is not None else os.getppid()
    end = time.time() + a.minutes * 60
    if a.dry_run:
        say("heartbeat: dry run · would arm %g min (until %s), parent pid %d, pid file %s"
            % (a.minutes, fmt_ts(end), parent, pid_file))
        return 0
    if os.path.exists(stop_file):
        os.remove(stop_file)   # a marker left by an earlier --stop or close, not this arming's
    write_atomic(pid_file, "%d %d\n" % (os.getpid(), end))
    append_record(path, event(a.run, "heartbeat", action="armed", minutes=a.minutes,
                              pid=os.getpid(), parent_pid=parent))

    def end_quietly(action, note):
        if os.path.exists(pid_file):
            os.remove(pid_file)
        append_record(path, event(a.run, "heartbeat", action=action, minutes=a.minutes,
                                  pid=os.getpid(), note=note))
        return 0

    while time.time() < end:
        if os.path.exists(stop_file):
            return end_quietly("stopped", "the stop marker appeared")
        if not pid_alive(parent):
            return end_quietly("orphaned", "parent pid %d is gone" % parent)
        time.sleep(max(0.0, min(a.tick_s, end - time.time())))
    if os.path.exists(pid_file):
        os.remove(pid_file)
    append_record(path, event(a.run, "heartbeat", action="beat", minutes=a.minutes,
                              pid=os.getpid()))
    say("heartbeat: %s · %g min · the cache is refreshed by this re-invocation; re-arm if "
        "still idle" % (a.run, a.minutes))
    return 0


def open_wait(events):
    """Index of the open limit stop-condition (no observation ended it), else -1."""
    for i in range(len(events) - 1, -1, -1):
        ev = events[i]
        if ev.get("event") == "observation" and ev.get("what") == "wait-reset ended":
            return -1
        if ev.get("event") == "stop-condition" and ev.get("which") == "limit":
            return i
    return -1


def probe(binary, config_dir):
    """One haiku call under the same login (D28): (ok, what). A limited account answers with
    the limit text at no cost; a config directory is optional and unused by default."""
    cmd = [binary, "-p", "--model", "haiku", "--max-budget-usd", "%.2f" % PROBE_BUDGET_USD,
           "--output-format", "json"]
    env = dict(os.environ)
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    try:
        proc = subprocess.run(cmd, input="Reply with the single word OK.", capture_output=True,
                              text=True, timeout=PROBE_TIMEOUT_S, env=env)
    except subprocess.TimeoutExpired:
        return False, "probe timed out after %d s" % PROBE_TIMEOUT_S
    except OSError as exc:
        return False, "probe could not start: %s" % exc
    result = {}
    if proc.stdout.strip():
        try:
            result = json.loads(proc.stdout.strip().splitlines()[-1])
        except ValueError:
            result = {}
    if not isinstance(result, dict):
        result = {}
    ok = (proc.returncode == 0 and not result.get("is_error")
          and result.get("subtype", "success") == "success")
    return ok, "exit %d · subtype %s · cost $%s" % (
        proc.returncode, result.get("subtype", "?"), result.get("total_cost_usd", "?"))


def cmd_wait_reset(a):
    path = record_path(a.run)
    events = require_record(path)
    text = a.stop_text if a.stop_text is not None else (
        read_text(a.stop_file, "--stop-file") if a.stop_file else "")
    now_ts = time.time()
    target, source = parse_reset_text(text, now_ts) if text else (None, None)
    if target is None and a.reset_at:
        target, source = parse_reset_at(a.reset_at, now_ts), "--reset-at %s" % a.reset_at
    if target is None and not a.probe:
        # Opt-in probe (owner ruling 2026-09-06): with no reset time to sleep to there is no
        # wait to run, so the stop condition is recorded and the hand-off is the recovery.
        if a.dry_run:
            say("wait-reset: dry run · no reset time, no --reset-at and no --probe · would "
                "record stop-condition limit-unparsed and end with the hand-off as the recovery")
            return 0
        append_record(path, event(
            a.run, "stop-condition", which="limit-unparsed", lane=a.lane,
            action="no reset time in the stop text, no --reset-at and no --probe (the probe is "
                   "opt-in, owner ruling 2026-09-06): the hand-off is the recovery",
            note=one_line(text)[:NOTE_CUT]))
        say("wait-reset: no reset time could be parsed and --probe was not passed · "
            "stop-condition limit-unparsed recorded · the hand-off is the recovery")
        return 7
    oi = open_wait(events)
    started = parse_ts(events[oi]["ts"]) if oi >= 0 else None
    if started is None:
        started = now_ts
    plan = ("until %s (%s)" % (fmt_ts(target), source)) if target is not None else (
        "probe every %d s under %s" % (
            a.probe_interval_s,
            "CLAUDE_CONFIG_DIR=%s" % a.config_dir if a.config_dir else "the same login"))
    if a.dry_run:
        say("wait-reset: dry run · %s · %s" % (
            plan, "%d s to go" % (target - now_ts) if target is not None else "no target"))
        return 0
    if oi < 0:
        append_record(path, event(a.run, "stop-condition", which="limit", lane=a.lane,
                                  action="wait-reset " + plan, note=one_line(text)[:300]))
    block_end = now_ts + a.max_block_s
    say("wait-reset: %s · waited %d s so far · this call blocks at most %d s"
        % (plan, now_ts - started, a.max_block_s))

    def ended(what, code):
        append_record(path, event(a.run, "observation", phase="", what="wait-reset ended",
                                  note=what))
        say("wait-reset: " + what)
        return code

    if target is not None:
        if target - started > a.max_wait_s:
            return ended("gave up: reset at %s is %d s after the wait began, past --max-wait-s %d"
                         % (fmt_ts(target), target - started, a.max_wait_s), 7)
        if target > block_end:
            time.sleep(max(0.0, block_end - time.time()))
            say("still-running %d" % max(0, round(target - time.time())))
            return 8
        time.sleep(max(0.0, target - time.time()))
        return ended("reset reached at %s after %d s" % (fmt_ts(target), time.time() - started), 0)
    last_probe = None
    for ev in (events[oi + 1:] if oi >= 0 else []):
        if ev.get("event") == "observation" and ev.get("what") == "wait-reset probe":
            last_probe = parse_ts(ev.get("ts"))
    while True:
        elapsed = time.time() - started
        if elapsed > a.max_wait_s:
            return ended("gave up after %d s of probing (--max-wait-s %d)"
                         % (elapsed, a.max_wait_s), 7)
        due = (last_probe + a.probe_interval_s) if last_probe else time.time()
        if due > block_end:
            time.sleep(max(0.0, block_end - time.time()))
            say("still-running %d" % max(0, round(a.max_wait_s - (time.time() - started))))
            return 8
        time.sleep(max(0.0, due - time.time()))
        ok, what = probe(a.harness_bin, a.config_dir)
        last_probe = time.time()
        append_record(path, event(a.run, "observation", phase="", what="wait-reset probe",
                                  note=what))
        if ok:
            return ended("probe succeeded after %d s: %s" % (time.time() - started, what), 0)


def plain_totals(events):
    """(lane names, counts by exit class, spend, the spend's source) for a record with no
    `run-open`. Every figure is read from the lane events alone, since they are the whole
    record: the classes come from `lane-closed.exit_class`, the spend from those events'
    `total_cost_usd`, and a lane opened but never closed is counted under `open`. Costs are
    summed by reading each event, never by a pattern over the file."""
    names, closed_names = set(), set()
    by_exit, spend, priced, unpriced = {}, 0.0, 0, 0
    for e in events:
        kind, lane = e.get("event"), e.get("lane")
        if kind not in ("lane-open", "lane-resumed", "lane-closed") or lane is None:
            continue
        names.add(str(lane))
        if kind != "lane-closed":
            continue
        closed_names.add(str(lane))
        cls = str(e.get("exit_class") or "unstated")
        by_exit[cls] = by_exit.get(cls, 0) + 1
        cost = e.get("total_cost_usd")
        if isinstance(cost, (int, float)) and not isinstance(cost, bool):
            spend += float(cost)
            priced += 1
        else:
            unpriced += 1
    still_open = len(names - closed_names)
    if still_open:
        by_exit["open"] = by_exit.get("open", 0) + still_open
    src = "sum of %d lane-closed total_cost_usd" % priced
    if unpriced:
        src += "; %d lane-closed carried no cost and are unpriced" % unpriced
    return sorted(names), by_exit, round(spend, 2), src


def close_plain(a, path, events):
    """`close` on the plain-lane-run shape (the register entry of 2026-09-06, widened
    2026-09-07): the `run-close` is written from the lane events alone.

    No head meter — the record names no head session to meter; no hand-off rewrite — no
    `run-open` names a pack; no hand-off row anywhere; and no commit and no push, since those
    write the vault under a head's grant and this record carries no head. The event says its
    own shape, so the console and the waste table can tell it from a hands-off close. The
    heartbeat and supervisor markers are not written either: a plain lane run arms neither."""
    if a.commit is not None or a.push:
        die("a plain lane run's close never commits and never pushes (%s was given): the record "
            "has no run-open, so no head's grant stands behind a vault write; nothing written"
            % ("--commit" if a.commit is not None else "--push"))
    names, by_exit, spend, src = plain_totals(events)
    tally = " · ".join("%s %d" % (k, n) for k, n in sorted(by_exit.items())) or "none"
    decisions = sum(1 for e in events if e.get("event") == "decision")
    ev = event(a.run, "run-close", shape=PLAIN_SHAPE, lanes=len(names), lanes_by_exit=by_exit,
               spend_usd=spend, spend_src=src, decisions_on_owner_behalf=decisions,
               meter="none: a plain lane run names no head session to meter",
               items=a.items, register=a.register, log=a.log, lint=a.lint)
    if a.dry_run:
        say("close: dry run · plain lane run (no run-open) · %s"
            % json.dumps(ev, ensure_ascii=False))
        say("close: lanes %d (%s) · spend $%.2f (%s) · would write no hand-off row, no commit, "
            "no push" % (len(names), tally, spend, src))
        return 0
    append_record(path, ev)
    say("close: %s · plain lane run (no run-open) · lanes %d (%s) · spend $%.2f (%s) · "
        "decisions %d · no hand-off row, no commit, no push"
        % (a.run, len(names), tally, spend, src, decisions))
    return 0


def cmd_close(a):
    path = record_path(a.run)
    events = read_existing_record(path)
    if is_plain_run(events):
        return close_plain(a, path, events)
    ro = run_open(events)
    ho = handoff_of(events, a.handoff)
    meter = meter_line(events, a.run, a.meter_line)
    per_item, prev = [], None
    for g in events:
        if g.get("event") != "gate" or not g.get("metered"):
            continue
        item = {"item": g.get("item"), "context": g.get("context"), "percent": g.get("percent")}
        if isinstance(g.get("context"), int):
            if prev is not None:
                item["delta"] = g["context"] - prev
            prev = g["context"]
        per_item.append(item)
    lanes = sorted({str(e.get("lane")) for e in events
                    if e.get("event") == "lane-open" and e.get("lane") is not None})
    decisions = sum(1 for e in events if e.get("event") == "decision")
    tally = billed_field(meter, r"\(reasons: (.*?)\) · ", str) or "n/a"
    lines = read_text(ho, "hand-off").split("\n")
    ev = event(a.run, "run-close", items=a.items, lanes=len(lanes), reason_tally=tally,
               decisions_on_owner_behalf=decisions, register=a.register, log=a.log,
               trace="%d rows under '## Trace' in %s" % (table_rows(lines, "Trace"), ho),
               lint=a.lint, meter=meter)
    if a.parity is not None:
        ev["parity"] = a.parity
    if per_item:
        ev["head_context_per_item"] = per_item
    refreshed = refresh_figures(lines, ro, meter)
    if a.dry_run:
        say("close: dry run · %s" % json.dumps(ev, ensure_ascii=False))
        return 0
    if refreshed:
        write_atomic(ho, "\n".join(lines))
    if a.commit is not None:
        ev["commit"] = checkpoint_commit(vault_root(), a.commit)
    if a.push:
        ev["push"] = push(vault_root())
    append_record(path, ev)
    try:
        write_atomic(heartbeat_files(a.run)[1], now() + "\n")   # an armed heartbeat ends (D32)
        write_atomic(supervisor_stop_file(a.run), now() + "\n")  # a sleeping supervisor ends (D43)
    except OSError as exc:
        note("heartbeat stop marker not written: %s" % exc)
    say("close: %s · lanes %d · decisions %d · gates %d%s%s%s" % (
        a.run, len(lanes), decisions, len(per_item),
        " · commit %s" % ev["commit"] if "commit" in ev else "",
        " · push %s" % ev["push"] if "push" in ev else "",
        "" if refreshed else " · morning report NOT refreshed (section missing)"))
    say("meter: %s" % meter)
    return 0


# ----------------------------------------------------------------- the waste table ---------

MISSING = object()   # the field is not on the event at all: `field absent`, never 0

# Kind assignment is mechanical (design D36; the reflect skill's Step 2b): a lost output is
# real, an output bought too dearly is arguable, a cost of the chosen shape is structural.
BOUNDARY_FIELDS = (
    ("idle_min", "idle minutes", "real", "min"),
    ("over_cap_reports", "reports over the %d-word cap" % REPORT_CAP_WORDS, "arguable", "count"),
    ("denials", "tool denials", "arguable", "count"),
    ("respawn_cost_usd", "lost-lane cost re-spawned", "real", "usd"),
    ("rewrites", "rewrites after a lapsed cache", "structural", "count"),
)
TABLE_HEAD = ("| Item | ≈ $ or idle min | Kind | Fix and where it lands |", "|---|---|---|---|")
LEGEND = ("Kinds are mechanical, never judged here: idle minutes and lost lanes are real; "
          "over-cap reports and denials are arguable; rewrites and the orientation cost are "
          "structural. Rows marked `billed`, `context` and `control` are Step 2b's other "
          "requirements and carry no waste kind. Field meanings (2026-09-06): idle minutes are "
          "head idleness — the time in the boundary's span when no lane was running and the "
          "head made no call, a gap counting only above %d s — read from the head's transcript "
          "(idle_src transcript) or, when it is unavailable, from the record alone as silence "
          "after each lane close (idle_src record, an overstatement under parallel lanes); the "
          "lost-lane cost sums lanes closed other than `completed` and not resumed afterwards; "
          "rewrites are the change since the same head's previous boundary, a head's first "
          "boundary keeping the billed line's cumulative figure. A boundary written before "
          "these meanings is quoted as recorded and its source cell says so. Field meanings "
          "(2026-09-07): the over-cap row carries the CUT TAIL alone — the words above the "
          "%d-word cap, converted at %s tokens per word, set by judgement, unmeasured, and "
          "charged at the lane's model's output rate from prices.json — never the lane's whole "
          "cost, and a report at or under the cap contributes nothing; a lane whose model the "
          "record does not name is counted in words and left unpriced. The whole-run rows meter "
          "each head over the RUN's window (run-open to run-close, else the record's last "
          "event), so a session shared with attended work is not counted whole against this "
          "run; where that meter gives no figure the row falls back to the later of the head's "
          "last boundary billed line and its head-exit spend, and says which. A recorded limit "
          "wait (stop-condition to head-resumed) has a structural row of its own, and an idle "
          "row whose span covers one says how many of its minutes it holds. A `soft-cap` cell "
          "is a lane billed over its soft line (`lane-closed.soft_exceeded`; `soft_src` says "
          "whether the line was the class's completed maximum plus its headroom or the head's "
          "own --expect-usd): the line is logged, never a stop, and the head ledgers it at the "
          "lane's close." % (
              IDLE_GAP_S, REPORT_CAP_WORDS, WORDS_TO_TOKENS))
# What each of the three re-defined fields means on a given boundary, read off the marker
# fields the boundary command writes beside them; a boundary written before the rule has none
# and is labelled as recorded, never re-read under the new meaning.
FIELD_MEANINGS = {
    "idle_min": lambda ev: {
        "transcript": "head idle: no lane running and no head call, gaps above %d s, the "
                      "head's calls from its transcript (idle_src transcript)" % IDLE_GAP_S,
        "record": "record-only fallback: silence after each lane close until the head's next "
                  "recorded act, summed per close, an overstatement under parallel lanes "
                  "(idle_src record)"}.get(
        ev.get("idle_src"), "as recorded: per-lane silence after each close, a boundary written "
                            "before the head-idle rule (no idle_src)"),
    "respawn_cost_usd": lambda ev: (
        "lanes closed other than completed and not resumed afterwards (%d resumed lane(s) "
        "excluded)" % ev["respawn_excluded"] if isinstance(ev.get("respawn_excluded"), int)
        else "as recorded: every lane closed other than completed, a boundary written before "
             "the resume exclusion"),
    "rewrites": lambda ev: (
        "change since %s (this head's billed line cumulative: %d)"
        % (ev.get("rewrites_since") or "unstated", ev["rewrites_total"])
        if isinstance(ev.get("rewrites_total"), int) and not isinstance(ev.get("rewrites_total"), bool)
        else "as recorded: the billed line's session-cumulative figure, a boundary written "
             "before the delta rule"),
}
FIX_OPEN = ("unrouted: the reflector lane proposes one of a plan phase, a `known-issues` entry, "
            "an IDEAS todo or `accepted`; the owner approves")
FIX_NONE = "no fix: this row carries no measured cost"
FIX_NA = "n/a"


def figure(value, unit, source):
    """(cell, is a finding): a figure with its derivation beside it, `field absent` where the
    event has no such key, `unmeasured` where the key is there and null. A missing field and a
    measured zero are different claims (Step 2b), and a bare number is never written."""
    if value is MISSING:
        return "field absent", False
    if value is None:
        return "unmeasured (the field is null) · %s" % source, False
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return "%s (as recorded) · %s" % (cell(value), source), False
    if unit == "usd":
        text = "$%.2f" % float(value)
    elif unit == "min":
        text = "%s min" % value
    else:
        text = format(value, ",") if isinstance(value, int) else str(value)
    return "%s · %s" % (text, source), float(value) > 0


def boundary_label(ev):
    return "%s → %s at %s" % (ev.get("from", "?"), ev.get("to", "?"), ev.get("ts", "no ts"))


def session_at(events, index):
    """The head session in force at an event: the last run-open, run-resume or head-successor
    before it, since a phase-boundary names no session of its own."""
    i = last_index(events[:index], SESSION_EVENTS)
    if i < 0:
        return None
    ev = events[i]
    sid = ev.get("session_id") if ev.get("event") == "head-successor" else ev.get("session")
    return sid if isinstance(sid, str) else None


def output_rate(model):
    """(rate in $ per MTok, family) for a model id, read from prices.json beside this script by
    that file's own matching rule — the id lower-cased, the first family name it contains in the
    file's stated order winning. (None, reason) where the file, the id or the family is missing:
    the row then carries the words alone and says it is unpriced, never a guessed rate."""
    path = os.path.join(HERE, "prices.json")
    if not isinstance(model, str) or not model.strip():
        return None, "the record names no model for this lane"
    try:
        with open(path, "r", encoding="utf-8") as handle:
            table = json.load(handle)
    except (OSError, ValueError) as exc:
        return None, "prices.json unreadable (%s)" % exc
    order = table.get("family_order") or list(table.get("families") or {})
    for family in order:
        if family in model.lower():
            rate = (table.get("families") or {}).get(family, {}).get("output")
            if isinstance(rate, (int, float)) and not isinstance(rate, bool):
                return float(rate), family
            return None, "prices.json carries no output rate for %s" % family
    return None, "the model %s matches no price family" % one_line(model)[:60]


def lane_model(events, index, close):
    """The model of the lane a lane-closed event names: the last lane-open for the same lane
    before the close (the wrapper records the model there, not on the close), matched on the
    lane session id too when both events carry one. None when no lane-open names one."""
    for ev in reversed(events[:index]):
        if ev.get("event") != "lane-open" or ev.get("lane") != close.get("lane"):
            continue
        a, b = ev.get("session_id"), close.get("session_id")
        if a and b and a != b:
            continue
        return ev.get("model")
    return None


def cut_tail_rows(events, lo, hi):
    """[(lane, words over the cap, cost or None, note)] for every lane-closed between the event
    indices lo (exclusive) and hi (inclusive) whose report ran over the cap: the CUT TAIL alone
    — `report_words` minus REPORT_CAP_WORDS, at WORDS_TO_TOKENS tokens per word, charged at the
    lane's model's output rate — and never the lane's whole cost (T8, 2026-09-07). A report at
    or under the cap contributes nothing."""
    found = []
    for i in range(max(0, lo + 1), min(hi + 1, len(events))):
        ev = events[i]
        if ev.get("event") != "lane-closed":
            continue
        words = ev.get("report_words")
        if not isinstance(words, int) or isinstance(words, bool) or words <= REPORT_CAP_WORDS:
            continue
        over = words - REPORT_CAP_WORDS
        model = lane_model(events, i, ev)
        rate, why = output_rate(model)
        if rate is None:
            found.append((ev.get("lane") or "unnamed lane", over, None, "unpriced: %s" % why))
            continue
        cost = over * WORDS_TO_TOKENS / 1000000.0 * rate
        found.append((ev.get("lane") or "unnamed lane", over, cost,
                      "%s output $%.2f/MTok" % (why, rate)))
    return found


def cut_tail_text(found):
    """The over-cap row's cut-tail cell: the priced tail with its derivation, or the statement
    that nothing in the span ran over the cap."""
    if not found:
        return ("cut tail $0.00 · no report in this span ran over the %d-word cap"
                % REPORT_CAP_WORDS)
    priced = [c for _, _, c, _ in found if c is not None]
    total = ("$%.2f" % sum(priced)) if priced else "unpriced"
    parts = ["%s %d words over" % (lane, over) + (
        " = $%.4f (%s)" % (cost, note) if cost is not None else " (%s)" % note)
        for lane, over, cost, note in found]
    return ("cut tail %s%s · the tail alone (report_words − %d), never the lane's whole cost: "
            "%s · %s tokens per word, set by judgement, unmeasured" % (
                total, "" if len(priced) == len(found) else " over the priced tail(s)",
                REPORT_CAP_WORDS, "; ".join(parts), WORDS_TO_TOKENS))


def limit_waits(events):
    """[(stop-condition, head-resumed, minutes)] for every recorded limit stop the record shows
    a head resumed from: the span between the two events. The limits ruling makes that wait a
    cost of the chosen shape, so the table gives it a structural row of its own rather than
    leaving it inside idle_min's real class (register entry 2026-09-06)."""
    found = []
    for i, ev in enumerate(events):
        if ev.get("event") != "stop-condition":
            continue
        resumed = next((x for x in events[i + 1:] if x.get("event") == "head-resumed"), None)
        if resumed is None:
            continue
        t0, t1 = parse_ts(ev.get("ts")), parse_ts(resumed.get("ts"))
        if t0 is None or t1 is None or t1 < t0:
            continue
        found.append((ev, resumed, (t1 - t0) / 60.0))
    return found


def limit_wait_rows(events):
    """One structural row per recorded limit wait; none where the record holds no such pair."""
    rows = []
    for stop, resumed, minutes in limit_waits(events):
        rows.append(("limit wait · %s → head-resumed at %s"
                     % (stop.get("which", "stop-condition"), resumed.get("ts", "no ts")),
                     "%.1f min · stop-condition at %s to head-resumed at %s · a cost of the "
                     "chosen shape (the limits ruling), not head idleness: a boundary whose "
                     "span covers it counts the same minutes under idle_min"
                     % (minutes, stop.get("ts", "no ts"), resumed.get("ts", "no ts")),
                     "structural", FIX_NONE))
    return rows


def overlap_min(waits, t0, t1):
    """The recorded limit-wait minutes inside a boundary's span, 0.0 when none overlap."""
    if t0 is None or t1 is None:
        return 0.0
    total = 0.0
    for stop, resumed, _ in waits:
        a, b = parse_ts(stop.get("ts")), parse_ts(resumed.get("ts"))
        if a is None or b is None:
            continue
        total += max(0.0, min(b, t1) - max(a, t0))
    return total / 60.0


def field_rows(events):
    """One row per waste field per phase-boundary event, each naming its event and, for the
    three fields re-defined on 2026-09-06, what the figure means on that boundary. The over-cap
    row carries the cut tail's price (T8) and an idle row whose span covers a recorded limit
    wait says how many of its minutes that wait holds (register entry 2026-09-06)."""
    rows = []
    waits = limit_waits(events)
    previous = -1
    for i, ev in enumerate(events):
        if ev.get("event") != "phase-boundary":
            continue
        label = boundary_label(ev)
        t0 = parse_ts(events[previous].get("ts")) if 0 <= previous < len(events) else \
            parse_ts(run_open(events).get("ts"))
        waited = overlap_min(waits, t0, parse_ts(ev.get("ts")))
        for key, what, kind, unit in BOUNDARY_FIELDS:
            meaning = FIELD_MEANINGS[key](ev) if key in FIELD_MEANINGS else None
            source = "phase-boundary.%s · %s%s" % (key, "%s · " % meaning if meaning else "",
                                                   label)
            fig, finding = figure(ev.get(key, MISSING), unit, source)
            measured = ev.get(key, MISSING) is not MISSING and ev.get(key) is not None
            if key == "over_cap_reports" and measured:
                fig = "%s · %s" % (fig, cut_tail_text(cut_tail_rows(events, previous, i)))
            if key == "idle_min" and measured and waited > 0:
                fig = ("%s · of which %.1f min is a recorded limit wait (stop-condition → "
                       "head-resumed), structural rather than real" % (fig, waited))
            rows.append(("%s · %s" % (what, label), fig, kind,
                         FIX_OPEN if finding else FIX_NONE))
        previous = i
    return rows


def head_totals(events, metered=None):
    """[(sid, dollars or None, source)] — one entry per head session the table counts, in
    record order. Each head's figure is, in order of preference: the meter's own reading over
    the RUN's window when one was taken (T6, so a session shared with attended work is never
    counted whole against this run), else the LATER of that head's last boundary billed line
    and its head-exit's `spent_usd` — a head that exited without a boundary loses nothing
    (register entry 2026-09-06). None where the record and the meter both give no figure."""
    found = []
    for sid in head_ids(events):
        billed_i, billed, exit_i, spent = -1, None, -1, None
        for i, ev in enumerate(events):
            if session_at(events, i) != sid:
                continue
            if ev.get("event") == "phase-boundary" and isinstance(ev.get("meter"), str):
                value = session_spent(ev["meter"])
                if value is not None:
                    billed_i, billed = i, value
            elif ev.get("event") == "head-exit":
                value = ev.get("spent_usd")
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    exit_i, spent = i, float(value)
        if spent is not None and (billed is None or exit_i > billed_i):
            record, why = spent, "head-exit.spent_usd $%.2f%s" % (
                spent, ", later in the record than the last boundary billed line $%.2f" % billed
                if billed is not None else ", the head recorded no boundary billed line")
        elif billed is not None:
            record, why = billed, "the last boundary billed line's `session $` $%.2f%s" % (
                billed, ", later than head-exit.spent_usd $%.2f" % spent
                if spent is not None else "")
        else:
            record, why = None, "no boundary billed line and no head-exit.spent_usd"
        line = (metered or {}).get(sid)
        window = session_spent(line) if isinstance(line, str) else None
        if window is not None:
            found.append((sid, window, "metered over the run's window: $%.2f (the record gives "
                                       "%s)" % (window, why)))
        else:
            found.append((sid, record, "%s%s" % (why, "" if line is None else
                                                 " · the window meter gave no figure: %s"
                                                 % one_line(str(line))[:120])))
    return found


def billed_rows(events, metered=None):
    """The billed line at every boundary, quoted as the meter printed it, and the whole-run
    rows: a run total as a shown sum of the per-head figures head_totals derives, with the
    envelope base beside it. An unmetered or failed line is quoted, never zeroed."""
    rows, quoted = [], 0
    for i, ev in enumerate(events):
        if ev.get("event") != "phase-boundary":
            continue
        sid = session_at(events, i) or "unnamed head"
        line = ev.get("meter", MISSING)
        text = "field absent" if line is MISSING else cell(one_line(line))
        rows.append(("billed line · head %s · %s" % (sid, boundary_label(ev)), text, "billed",
                     FIX_NA))
        if not (isinstance(line, str) and session_spent(line) is not None):
            quoted += 1
    totals = [(sid, usd, why) for sid, usd, why in head_totals(events, metered)
              if usd is not None]
    if not rows and not totals:
        return rows
    envelope = run_open(events).get("envelope_usd")
    base = (" · envelope base $%.2f (run-open.envelope_usd)" % float(envelope)
            if isinstance(envelope, (int, float)) and not isinstance(envelope, bool)
            else " · no envelope base (run-open carries no envelope_usd)")
    seeds = seed_sessions(events)
    skipped = (" · seed (skipped): %s, marked seed by run-open and never a head"
               % ", ".join(seeds) if seeds else "")
    if totals:
        shown = " + ".join("$%.2f" % usd for _, usd, _ in totals)
        fig = "%s = $%.2f · per head: %s%s%s%s" % (
            shown, round(sum(usd for _, usd, _ in totals), 2),
            "; ".join("%s %s" % (sid, why) for sid, _, why in totals), base, skipped,
            "; %d boundary line(s) carried no session figure and are quoted above, never read "
            "as zero" % quoted if quoted else "")
    else:
        fig = ("unmeasured · no boundary billed line carried a `session $` figure and no "
               "head-exit recorded spend; the %d line(s) are quoted above, never read as "
               "zero%s%s" % (quoted, base, skipped))
    rows.append(("run total (shown sum)", fig, "billed", FIX_NA))
    return rows


def context_rows(events):
    """Context per item, read off the gate events as the delta between consecutive gates."""
    gates = [e for e in events if e.get("event") == "gate"]
    if not gates:
        return [("context per item", "no gate events in the record · Step 2b drops the context "
                 "column for this run", "context", FIX_NA)]
    rows, prev = [], None
    for g in gates:
        item = "context · item %s at %s" % (g.get("item", "?"), g.get("ts", "no ts"))
        value = g.get("context")
        if not isinstance(value, int):
            rows.append((item, "unmeasured · the gate is unmetered (band %s)"
                         % g.get("band", "?"), "context", FIX_NA))
            continue
        if prev is None:
            rows.append((item, "%s tokens · the first metered gate, no earlier gate to "
                         "difference%s" % (format(value, ","),
                                           " (one gate event only)" if len(gates) == 1 else ""),
                         "context", FIX_NA))
        else:
            delta = value - prev
            rows.append((item, "%s%s tokens · gate context %s → %s"
                         % ("+" if delta >= 0 else "-", format(abs(delta), ","),
                            format(prev, ","), format(value, ",")), "context", FIX_NA))
        prev = value
    return rows


def head_spans(events):
    """[(session id, start, end)] for the head sessions the table counts, in record order. A
    span holding a head-exit that records no transcript is a session that never ran (see
    seed_exit) and is left out: counting it would put an `unmeasured` head in the table beside
    the heads that did run. A session `run-open --session-kind seed` marks is left out for the
    same reason, on the record's own field rather than on the absence of a transcript (T7)."""
    starts = [i for i, e in enumerate(events) if e.get("event") in SESSION_EVENTS]
    seeds = seed_sessions(events)
    spans = []
    for k, i in enumerate(starts):
        end = starts[k + 1] if k + 1 < len(starts) else len(events)
        if any(seed_exit(e) for e in events[i:end]):
            continue
        sid = session_at(events, i + 1) or "unnamed head"
        if sid in seeds:
            continue
        spans.append((sid, i, end))
    return spans


def head_ids(events):
    """The distinct head session ids the table counts, in record order. One id however many
    spans it holds: a head-successor and the run-resume that follows it name ONE session, and
    counting spans read four heads for two ids (register entry 2026-09-06)."""
    ids = []
    for sid, _, _ in head_spans(events):
        if sid not in ids:
            ids.append(sid)
    return ids


def orientation_rows(events):
    """The orientation cost per head (D41): the first gate of each head's span carries
    `orientation_tokens`; anything else is `unmeasured` with the reason. One row per session
    id — a head-successor and the run-resume that follows it are two spans of ONE session — and
    a measured figure wins over an unmeasured one, so a resumed head's null does not hide the
    figure its own first gate recorded."""
    spans = head_spans(events)
    if not spans:
        return [("orientation cost", "unmeasured · the record names no head session that ran",
                 "structural", FIX_NONE)]
    found = []       # (session id, row, measured): one row per id survives, measured first
    for sid, i, end in spans:
        item = "orientation cost · head %s" % sid
        gate = next((e for e in events[i:end] if e.get("event") == "gate"), None)
        if gate is None:
            found.append((sid, (item, "unmeasured · no gate event in this head's span",
                                "structural", FIX_NONE), False))
            continue
        value = gate.get("orientation_tokens", MISSING)
        source = "gate.orientation_tokens · item %s at %s" % (gate.get("item", "?"),
                                                              gate.get("ts", "no ts"))
        if value is None:
            note = gate.get("orientation_note") or "the field is null"
            found.append((sid, (item, "unmeasured · %s · %s" % (note, source), "structural",
                                FIX_NONE), False))
            continue
        if value is MISSING:
            found.append((sid, (item, "field absent", "structural", FIX_NONE), False))
            continue
        fig, finding = figure(value, "count", source)
        found.append((sid, (item, fig.replace(" · ", " tokens · ", 1), "structural",
                            FIX_OPEN if finding else FIX_NONE), True))
    chosen = {}
    order = []
    for sid, row, measured in found:
        if sid not in chosen:
            order.append(sid)
        if sid not in chosen or (measured and not chosen[sid][1]):
            chosen[sid] = (row, measured)
    return [chosen[sid][0] for sid in order]


def soft_cap_note(ev):
    """` · soft-cap: $<billed> over $<soft>` for a close the wrapper flagged, else "". The
    soft threshold is logged at the close and never stops a lane (lane.py's two-tier caps),
    so the flag had no reader until this row (critic finding F4, 2026-09-07); the head ledgers
    the line at the lane's close. A flag with no dollar figure beside it says `unmeasured`
    rather than a number nobody recorded."""
    if ev.get("soft_exceeded") is not True:
        return ""
    def money(value):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return "unmeasured"
        return "$%.2f" % float(value)
    return " · soft-cap: %s over %s (%s)" % (money(ev.get("total_cost_usd")),
                                             money(ev.get("soft_usd")),
                                             ev.get("soft_src") or "class")


def lane_rows(events):
    """Lost-lane cost: every lane-closed whose exit class is not `completed`, with the cost
    field as recorded and `unmeasured` where the event carries none. A cut lane that a later
    lane-resumed picked up again lost nothing: its row says so and carries no fix, matching
    the boundary field's exclusion. A close flagged `soft_exceeded` carries its soft-cap note
    on the same row, and a COMPLETED lane so flagged — which has no row otherwise — gets one
    of its own, arguable in kind: the money bought a result, and whether it was waste is the
    reflector's call, not this table's."""
    rows = []
    for i, ev in enumerate(events):
        if ev.get("event") != "lane-closed":
            continue
        cls = ev.get("exit_class", MISSING)
        note = soft_cap_note(ev)
        if cls == "completed":
            if note:
                rows.append(("soft-cap lane · %s · exit class completed"
                             % (ev.get("lane") or "unnamed lane"),
                             "%s · lane-closed.soft_exceeded · logged at the close, never a "
                             "stop" % note.lstrip(" ·").strip(), "arguable", FIX_OPEN))
            continue
        lane = ev.get("lane") or "unnamed lane"
        stamped = "%s at %s" % (lane, ev.get("ts", "no ts"))
        if cls is MISSING:
            rows.append(("lost lane · %s · exit class" % lane, "field absent", "real", FIX_NONE))
            continue
        fig, finding = figure(ev.get("total_cost_usd", MISSING), "usd",
                              "lane-closed.total_cost_usd · %s%s" % (stamped, note))
        resumed = resumed_after(events[i + 1:], ev)
        if resumed is not None:
            rows.append(("cut lane · %s · exit class %s · resumed" % (lane, cls),
                         "%s · resumed at %s, so not lost (excluded from respawn_cost_usd)"
                         % (fig, resumed.get("ts", "no ts")), "real", FIX_NONE))
            continue
        rows.append(("lost lane · %s · exit class %s" % (lane, cls), fig, "real",
                     FIX_OPEN if finding else FIX_NONE))
    return rows


def waste_table(events, run, path, bad, metered=None):
    """(text, rows, counts): the whole document, rendered from the record and — for the
    whole-run rows alone — the meter's reading of each head over the run's own window, which
    the caller takes and passes in (T6). Every other figure is read from a field."""
    boundaries = [e for e in events if e.get("event") == "phase-boundary"]
    gates = [e for e in events if e.get("event") == "gate"]
    lanes = [e for e in events if e.get("event") == "lane-closed"]
    lost = [e for e in lanes if e.get("exit_class", MISSING) != "completed"]
    heads = head_ids(events)   # distinct ids: a session that never ran is not a head
    rows = []
    if not boundaries:
        rows.append(("phase-boundary events", "no phase-boundary events · the waste fields and "
                     "the billed lines are read from these events", "control", FIX_NA))
    rows += field_rows(events)
    rows += billed_rows(events, metered)
    rows += context_rows(events)
    rows += orientation_rows(events)
    rows += limit_wait_rows(events)
    rows += lane_rows(events)
    if not any(row[3] == FIX_OPEN for row in rows):
        rows.append(("no waste found", "searched: %d phase-boundary event(s) for %s; %d "
                     "lane-closed event(s) for an exit class other than `completed`; %d gate "
                     "event(s) for `orientation_tokens` and the context deltas"
                     % (len(boundaries), ", ".join(k for k, _, _, _ in BOUNDARY_FIELDS),
                        len(lanes), len(gates)),
                     "control", "n/a · the zero-findings control names what was searched"))
    _, _, window_src = run_window(events)
    seeds = seed_sessions(events)
    header = [
        "# Waste table · run %s" % run,
        "",
        "Step 2b of the reflect skill, rendered by `handsoff.py waste-table` from the run "
        "record: every figure but the whole-run rows is read from a field, none is recalled, "
        "and the only meter call is the one those rows name (hands-off design D36; T6 of the "
        "token-efficiency findings, 2026-09-07).",
        "Record: %s" % path,
        "Rendered: %s" % now(),
        "Events read: %d phase-boundary%s, %d gate, %d lane-closed (%d not completed), %d head "
        "session(s)%s." % (len(boundaries), " (no phase-boundary events)" if not boundaries
                           else "", len(gates), len(lanes), len(lost), len(heads),
                           "; %d unparseable line(s) skipped" % bad if bad else ""),
        "Head sessions are counted by DISTINCT session id (%s): a head-successor and the "
        "run-resume that follows it are one session, not two." % (", ".join(heads) or "none"),
        "Run window for the whole-run rows: %s." % window_src,
        "seed (skipped): %s." % ("%s — marked `session_kind: seed` by run-open, a launcher's "
                                 "placeholder that never ran, so it is neither metered nor "
                                 "counted as a head session" % ", ".join(seeds) if seeds else
                                 "none — no run-open in this record marks a seed session"),
        "Legend: %s" % LEGEND,
        "",
        "## Waste table",
        "",
    ]
    body = list(TABLE_HEAD) + ["| %s | %s | %s | %s |" % tuple(cell(x) for x in row)
                               for row in rows]
    counts = {"rows": len(rows), "boundaries": len(boundaries), "gates": len(gates),
              "lanes": len(lanes)}
    return "\n".join(header + body) + "\n", rows, counts


def meter_overrides(pairs):
    """{session id: billed line} from `--meter-line SID=LINE` (repeatable): a line already in
    hand for one head, so the whole-run rows can be rendered without running the meter."""
    found = {}
    for pair in pairs or []:
        sid, sep, line = pair.partition("=")
        if not sep or not sid.strip() or not line.strip():
            die("--meter-line takes SID=LINE; got %s" % one_line(pair)[:80])
        found[sid.strip()] = line.strip()
    return found


def metered_heads(events, run, no_meter=False, overrides=None):
    """{session id: billed line or its failure} for every head session the table counts, each
    metered over the RUN's own window (T6). `no_meter` renders from the record alone, which is
    what a caller with no transcripts to read passes; an override stands in for the meter."""
    overrides = overrides or {}
    if no_meter and not overrides:
        return {}
    start, end, _ = run_window(events)
    found = {}
    for sid in head_ids(events):
        if sid in overrides:
            found[sid] = overrides[sid]
        elif not no_meter:
            found[sid] = meter_line(events, run, None, start, end, sid)
    return found


def cmd_waste_table(a):
    path = record_path(a.run)
    events = require_record(path)
    bad = read_record(path)[1]
    out_path = (os.path.realpath(os.path.expanduser(a.out)) if a.out else
                os.path.join(store_root(), "spawn-records", "%s-waste-table.md" % a.run))
    metered = metered_heads(events, a.run, a.no_meter, meter_overrides(a.meter_line))
    text, _, counts = waste_table(events, a.run, path, bad, metered)
    summary = "%d rows from %d boundaries, %d gates, %d lanes" % (
        counts["rows"], counts["boundaries"], counts["gates"], counts["lanes"])
    if a.dry_run:
        say("waste-table: dry run · %s · would write %s" % (summary, out_path))
        return 0
    try:
        write_atomic(out_path, text)
    except OSError as exc:
        die("cannot write the waste table %s: %s" % (out_path, exc))
    say("waste-table: %s → %s" % (summary, out_path))
    return 0


# ------------------------------------------------------- the head's own transcript ----------

# The two injected user-record classes the reflector template names, plus the tool results:
# `"type":"user"` alone does not mean a human turn. A Skill-tool injection carries
# `isMeta: true` and opens "Base directory for this skill" (the reflect skill's Step 2). A
# harness injection is recognised by its opening, or by a record whose whole text is one or
# more system-reminder blocks. RESIDUE, stated rather than hidden: the harness's exact
# task-notification wrapper is unverified here, so a notification matching none of these
# markers is extracted as a human turn — an over-count the reflector can see, rather than a
# dropped human turn it cannot. `--notification-re` adds a marker without editing this list.
SKILL_INJECTION_RE = re.compile(r"^\s*Base directory for this skill")
REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
# A resume replay: the harness sends a whole prior conversation as ONE user record, opening
# with a turn marker and carrying at least two of them (observed 2026-09-04; the same predicate
# the anchor hook's `_owner_text` carries, copied rather than imported because that hook is
# machine-local). The markers are the property, never the size. The hook drops such a prompt
# whole; the extraction keeps its trailing owner message — the words the owner actually typed
# this turn — and counts the record under `excluded.replay`.
REPLAY_OPEN_RE = re.compile(r"\s*(?:User|Assistant|Human):")
TURN_MARK_RE = re.compile(r"(?m)^(?:User|Assistant|Human):")
HUMAN_MARK_RE = re.compile(r"(?m)^(?:User|Human):")
# The harness's own stop record: an assistant record whose model field opens with this and
# whose text is "No response requested." is the harness speaking, not the head. The watermark
# hook's measure() skips the same records (context-watermark.py, the `<synthetic` model test).
SYNTHETIC_MODEL = "<synthetic"
NOTIFICATION_RES = (
    re.compile(r"^\s*<task-notification\b"),
    re.compile(r"^\s*Caveat: The messages below were generated by the user while running local "
               r"commands"),
)


# An assistant record's tool calls carried into the extraction (register entry 2026-09-07): the
# call, never its result — the tool_result exclusion above stands, so the reflector reads what
# the head DID and not what came back. One line per call: the tool's name and the input field
# that says what it acted on, each line cut at TOOL_CALL_CHARS characters (set by the head as a
# bound on one line, unmeasured; a cut line ends with the marker so the cut is visible). A tool
# outside the table prints its name alone rather than a guessed field.
TOOL_CALL_CHARS = 300
TOOL_CALL_CUT = " …[cut]"
TOOL_ARG_KEYS = {"Bash": ("command",), "Read": ("file_path",), "Write": ("file_path",),
                 "Edit": ("file_path",), "Grep": ("pattern",), "Glob": ("pattern",)}


def tool_call_line(block):
    """`- <tool>: <what it acted on>` for one tool_use block, or `- <tool>` where the tool is
    not in the table above or its input carries none of that tool's fields. Cut at
    TOOL_CALL_CHARS characters, the cut marked."""
    name = str(block.get("name") or "tool")
    data = block.get("input") if isinstance(block.get("input"), dict) else {}
    value = ""
    for key in TOOL_ARG_KEYS.get(name, ()):
        if data.get(key) not in (None, ""):
            value = one_line(str(data[key]))
            break
    line = "- %s: %s" % (name, value) if value else "- %s" % name
    if len(line) > TOOL_CALL_CHARS:
        line = line[:TOOL_CALL_CHARS - len(TOOL_CALL_CUT)] + TOOL_CALL_CUT
    return line


def tool_call_lines(blocks):
    """The tool-call lines of one assistant record, in the order the record holds them."""
    return [tool_call_line(b) for b in blocks if b.get("type") == "tool_use"]


def blocks_of(message):
    content = message.get("content")
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return []


def turn_text(lane, blocks, kinds=("text",)):
    """The record's prose, joined by lane.py's own block reader (never a second parser)."""
    return " ".join(lane.block_text(b) for b in blocks if b.get("type") in kinds).strip()


def is_notification(text, extra):
    if not REMINDER_RE.sub("", text).strip():
        return True
    return any(pattern.match(text) for pattern in tuple(NOTIFICATION_RES) + tuple(extra))


def replay_tail(text):
    """(is_replay, kept text) for a resume replay the harness sent as one user record: everything
    after its LAST human turn marker, which in the observed shape is the message the owner typed
    this turn. The kept text is "" when the replay carries no human marker at all or nothing
    after it, and a record that is not a replay comes back unchanged. The tail is NOT cut at any
    later marker: where the last marker is not the owner's — a typed prompt that opens by quoting
    a conversation — cutting drops the owner's own words, and this file's residue note already
    prefers an over-inclusive turn the reflector can see to a dropped one it cannot."""
    if not (REPLAY_OPEN_RE.match(text) and len(TURN_MARK_RE.findall(text)) >= 2):
        return False, text
    marks = list(HUMAN_MARK_RE.finditer(text))
    return True, (text[marks[-1].end():].strip() if marks else "")


def extract_turns(lane, path, extra):
    """(turns, counts) from a transcript: human turns, assistant prose and the assistant's tool
    calls in file order, with the tool results and the two injected user-record classes counted
    out. An unparseable line is counted, never fatal. An assistant record carrying only tool
    calls is a tool-call turn — one line per call, the call and never its result — counted under
    `tool_call_turns` rather than excluded, so records = extracted + tool_call_turns + every
    exclusion (register entry 2026-09-07). A record carrying both prose and tool calls keeps its
    prose turn and the lines go under it, so the turn count still matches the head's messages. A
    resume replay keeps its trailing owner message alone and a synthetic assistant record is
    skipped: `replay` counts the records recognised (the trimmed ones are still human turns),
    `synthetic` the records dropped."""
    turns = []
    counts = {"records": 0, "human_turns": 0, "assistant_turns": 0, "tool_call_turns": 0,
              "excluded": {"tool_result": 0, "meta": 0, "notification": 0, "replay": 0,
                           "synthetic": 0, "unparseable": 0}}
    out = counts["excluded"]
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            counts["records"] += 1
            try:
                record = json.loads(line)
            except ValueError:
                out["unparseable"] += 1
                continue
            if not isinstance(record, dict):
                out["unparseable"] += 1
                continue
            kind = record.get("type")
            message = record.get("message") if isinstance(record.get("message"), dict) else {}
            blocks = blocks_of(message)
            stamp = record.get("timestamp") or record.get("ts") or "no timestamp"
            if kind == "user":
                if record.get("toolUseResult") is not None or \
                        any(b.get("type") == "tool_result" for b in blocks):
                    out["tool_result"] += 1
                    continue
                text = turn_text(lane, blocks)
                if record.get("isMeta") is True or SKILL_INJECTION_RE.match(text):
                    out["meta"] += 1
                    continue
                replayed, text = replay_tail(text)
                if replayed:
                    out["replay"] += 1
                    if not text:
                        continue          # a replay with no owner message left: nothing to keep
                if text and is_notification(text, extra):
                    out["notification"] += 1
                    continue
                counts["human_turns"] += 1
                turns.append(("human", stamp, text or "(this record carries no text content)"))
            elif kind == "assistant":
                if str(message.get("model") or "").startswith(SYNTHETIC_MODEL):
                    out["synthetic"] += 1   # the harness's stop record, never the head's prose
                    continue
                prose = turn_text(lane, blocks)
                calls = tool_call_lines(blocks)
                if prose:
                    counts["assistant_turns"] += 1
                    body = prose + ("\n\nTool calls:\n" + "\n".join(calls) if calls else "")
                    turns.append(("assistant", stamp, body))
                elif calls:
                    counts["tool_call_turns"] += 1
                    turns.append(("assistant · tool calls", stamp, "\n".join(calls)))
    counts["extracted"] = counts["human_turns"] + counts["assistant_turns"]
    return turns, counts


def extraction_text(sid, path, turns, counts):
    out = counts["excluded"]
    head = [
        "# Transcript extraction · session %s" % sid,
        "",
        "Source: %s" % path,
        "Extracted: %s by `handsoff.py extract-transcript` (hands-off design D36): the human "
        "turns and the assistant prose, in order." % now(),
        "Excluded: %d tool-result record(s), %d Skill-tool injection(s) marked `isMeta`, %d "
        "harness injection(s), %d synthetic assistant record(s), %d unparseable line(s)." % (
            out["tool_result"], out["meta"], out["notification"], out["synthetic"],
            out["unparseable"]),
        "Replays: %d record(s) in which the harness re-sent a whole prior conversation as one "
        "user record (a turn marker at the opening and at least two in all, whatever the size) "
        "were trimmed to the text after their last `User:` marker, which is the turn the owner "
        "typed; a replay with no owner message left is dropped and counted here too." %
        out["replay"],
        "An assistant record carrying only tool calls is a tool-call turn, headed `assistant · "
        "tool calls`: one line per call with the tool's name and the input field naming what it "
        "acted on, each line cut at %d characters. The calls are carried, never their results, "
        "so the tool-result exclusion above stands. A record carrying both prose and tool calls "
        "keeps its prose turn and its lines go under it." % TOOL_CALL_CHARS,
        "Read %d of %d records as turns (%d human, %d assistant), and %d record(s) of tool "
        "calls alone. Records = %d extracted + %d tool-call + %d excluded = %d." % (
            counts["extracted"], counts["records"], counts["human_turns"],
            counts["assistant_turns"], counts["tool_call_turns"], counts["extracted"],
            counts["tool_call_turns"], sum(out.values()),
            counts["extracted"] + counts["tool_call_turns"] + sum(out.values())),
        "",
    ]
    body = []
    for n, (role, stamp, text) in enumerate(turns, 1):
        body += ["## turn %d · %s · %s" % (n, role, stamp), "", text, ""]
    return "\n".join(head + body) + "\n"


def extraction_inputs(a):
    """(lane module, session id, transcript path, extra notification patterns) for the two
    commands that read the head's own transcript; every missing premise is a premise failure."""
    lane, _, err = lane_module()
    if lane is None:
        die("the transcript helpers are lane.py's, never a second parser of the same shape: %s"
            % err)
    sid = token(a.session, "session id")
    root = os.path.realpath(os.path.expanduser(a.projects_root)) if a.projects_root else None
    path = transcript_for(sid, root)
    if not os.path.isfile(path):
        die("no transcript for session %s at %s" % (sid, path))
    try:
        extra = [re.compile(pattern) for pattern in (a.notification_re or [])]
    except re.error as exc:
        die("--notification-re is not a regular expression: %s" % exc)
    return lane, sid, path, extra


def write_extraction(lane, sid, path, out_dir, extra):
    """turns.md and counts.json under out_dir, and the counts behind them — one writer for
    `extract-transcript` and `reflect-inputs`, so the two can never differ."""
    try:
        turns, counts = extract_turns(lane, path, extra)
    except OSError as exc:
        die("cannot read the transcript %s: %s" % (path, exc))
    counts["session"] = sid
    payload = {"session": sid, "records": counts["records"],
               "human_turns": counts["human_turns"],
               "assistant_turns": counts["assistant_turns"],
               "tool_call_turns": counts["tool_call_turns"], "excluded": counts["excluded"],
               "extracted": counts["extracted"]}
    try:
        write_atomic(os.path.join(out_dir, "turns.md"),
                     extraction_text(sid, path, turns, counts))
        write_atomic(os.path.join(out_dir, "counts.json"),
                     json.dumps(payload, ensure_ascii=False, indent=1) + "\n")
    except OSError as exc:
        die("cannot write the extraction under %s: %s" % (out_dir, exc))
    return counts


def excluded_text(out):
    return ("excluded tool_result %d, meta %d, notification %d, replay %d, synthetic %d, "
            "unparseable %d" % (out["tool_result"], out["meta"], out["notification"],
                                out["replay"], out["synthetic"], out["unparseable"]))


def cmd_extract_transcript(a):
    lane, sid, path, extra = extraction_inputs(a)
    out_dir = (os.path.realpath(os.path.expanduser(a.out)) if a.out
               else os.path.join("/tmp", "aimyth-extract-%s" % sid))
    counts = write_extraction(lane, sid, path, out_dir, extra)
    say("extract-transcript: %d turns (%d human, %d assistant) of %d records · %d tool-call "
        "turn(s) · %s → %s"
        % (counts["extracted"], counts["human_turns"], counts["assistant_turns"],
           counts["records"], counts["tool_call_turns"], excluded_text(counts["excluded"]),
           out_dir))
    return 0


# ------------------------------------------------- the blind reflector's whole input set -----

# A spawner pre-registers its controls in the record as an observation whose phase starts
# `controls` (the convention: `handsoff.py ledger --phase controls-<LANE> …`), and a lane event
# carries the brief it was given and the case planted for it. None of that is the P4
# reflector's to read: that lane is blind to what the head expected, so `reflect-inputs` drops
# those observations from the copy it writes and strips these keys from every event it keeps.
CONTROL_PHASE = "controls"
BLINDED_KEYS = ("controls_checked", "brief_copy", "brief", "plant")


def blinded_events(events):
    """(kept events, observations dropped, events stripped) for the blind reflector's copy of
    the run record: an observation whose phase starts `controls` goes whole, and every event
    kept loses the keys carrying a control, a brief or a planted case."""
    kept, dropped, stripped = [], 0, 0
    for ev in events:
        phase = ev.get("phase")
        if ev.get("event") == "observation" and isinstance(phase, str) \
                and phase.startswith(CONTROL_PHASE):
            dropped += 1
            continue
        copy = dict((k, v) for k, v in ev.items() if k not in BLINDED_KEYS)
        if len(copy) != len(ev):
            stripped += 1
        kept.append(copy)
    return kept, dropped, stripped


def refuse_out_inside(out_dir, what, root):
    """A premise failure when --out sits in a directory the blind lane is not granted: the
    reflector is granted its own directory alone, and an input set written into the store or
    the projects root either needs a grant it must not have or is read as the run's own."""
    real = os.path.realpath(os.path.expanduser(out_dir))
    for spelling in spellings(root):
        if real == spelling or real.startswith(spelling + os.sep):
            die("--out %s is inside the %s (%s): the reflector lane is granted its output "
                "directory alone, so the input set is written outside both" % (out_dir, what,
                                                                               spelling))


def cmd_reflect_inputs(a):
    """The P4 boundary reflection's whole input set in one directory (D36): the extraction, the
    waste table and a filtered copy of the run record, written before the event that records
    them so the copy never carries its own line."""
    path = record_path(a.run)
    events = require_record(path)
    bad = read_record(path)[1]
    out_dir = os.path.realpath(os.path.expanduser(a.out))
    refuse_out_inside(out_dir, "run store", store_root())
    refuse_out_inside(out_dir, "projects root", projects_root())
    lane, sid, tpath, extra = extraction_inputs(a)
    if a.dry_run:
        try:
            _, counts = extract_turns(lane, tpath, extra)
        except OSError as exc:
            die("cannot read the transcript %s: %s" % (tpath, exc))
        _, _, wcounts = waste_table(events, a.run, path, bad,
                                    metered_heads(events, a.run, a.no_meter,
                                                  meter_overrides(a.meter_line)))
        kept, dropped, stripped = blinded_events(events)
        say("reflect-inputs: dry run · %d turns (%d human, %d assistant) of %d records · %d "
            "tool-call turn(s) · %d waste row(s) · %d event(s) kept, %d controls observation(s) "
            "dropped, %d stripped of %s · would write turns.md, counts.json, waste-table.md and "
            "record-filtered.jsonl under %s and append one reflect-inputs event"
            % (counts["extracted"], counts["human_turns"], counts["assistant_turns"],
               counts["records"], counts["tool_call_turns"], wcounts["rows"], len(kept),
               dropped, stripped, "/".join(BLINDED_KEYS), out_dir))
        return 0
    counts = write_extraction(lane, sid, tpath, out_dir, extra)
    text, _, wcounts = waste_table(events, a.run, path, bad,
                                   metered_heads(events, a.run, a.no_meter,
                                                 meter_overrides(a.meter_line)))
    kept, dropped, stripped = blinded_events(events)
    try:
        write_atomic(os.path.join(out_dir, "waste-table.md"), text)
        write_atomic(os.path.join(out_dir, "record-filtered.jsonl"),
                     "".join(json.dumps(ev, ensure_ascii=False) + "\n" for ev in kept))
    except OSError as exc:
        die("cannot write the reflection inputs under %s: %s" % (out_dir, exc))
    summary = {"turns": counts["extracted"], "human_turns": counts["human_turns"],
               "assistant_turns": counts["assistant_turns"],
               "tool_call_turns": counts["tool_call_turns"], "records": counts["records"],
               "waste_rows": wcounts["rows"], "events_kept": len(kept),
               "controls_dropped": dropped, "events_stripped": stripped}
    append_record(path, event(a.run, "reflect-inputs", session=sid, out=out_dir,
                              counts=summary))
    say("reflect-inputs: %d turns (%d human, %d assistant) of %d records · %d tool-call turn(s) "
        "· %d waste row(s) · %d event(s) kept, %d controls observation(s) dropped, %d stripped "
        "of %s → %s"
        % (summary["turns"], summary["human_turns"], summary["assistant_turns"],
           summary["records"], summary["tool_call_turns"], summary["waste_rows"],
           summary["events_kept"], summary["controls_dropped"], summary["events_stripped"],
           "/".join(BLINDED_KEYS), out_dir))
    return 0


# ------------------------------------------------------------------------------ main -------

def main():
    ap = argparse.ArgumentParser(description="hands-off run primitives; see the module docstring")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p, handoff=True):
        p.add_argument("--run", required=True, help="run id (the record's file stem)")
        if handoff:
            p.add_argument("--handoff", default=None, help="hand-off path (default: run-open's)")
        p.add_argument("--dry-run", action="store_true", help="print what would be written")
        return p

    def grants(p):
        p.add_argument("--grants-file", nargs="?", const=None, default=None, metavar="PATH",
                       help="the grants file's path (default: <store>/spawn-records/<run>-grants.json)")
        p.add_argument("--grant", action="append", default=[], metavar="PATH",
                       help="a read grant (repeatable); the defaults are always present")
        p.add_argument("--write", action="append", default=[], metavar="PATH",
                       help="a write grant (repeatable); the store and the state directory are always present")
        p.add_argument("--on-limit", choices=ON_LIMIT_VALUES, default=None,
                       help="the limit gate (D42, the pre-flight's class L): stop (the default: "
                            "the supervisor stands down on a limit, the hand-off is the recovery) "
                            "or resume (the pre-flight's limit-off: sleep to the reset, then "
                            "resume); absent, the file's own value is carried forward")
        p.add_argument("--viewer", choices=VIEWER_VALUES, default=None,
                       help="the console window (the pre-flight's viewer key): terminal (the "
                            "default: run-open opens a Terminal window on `watch --run R`, and "
                            "successor and resume-head open one when none is alive) or none; "
                            "absent, the file's own value is carried forward")
        return p

    def supervision(p):
        p.add_argument("--reset-at", default=None, metavar="HH:MM|+Ns|ISO",
                       help="the reset time after a limit stop; wins over the stop text")
        p.add_argument("--max-wait-s", type=int, default=MAX_WAIT_S,
                       help="the reset wait's bound (successor-aborted reset-timeout past it)")
        p.add_argument("--probe", action="store_true",
                       help="opt in to the $0.05 haiku probe when no reset time can be parsed; "
                            "OFF by default (owner ruling 2026-09-06), and the supervisor never "
                            "passes it on its own — without it an unparsed limit records "
                            "stop-condition limit-unparsed and the hand-off is the recovery")
        p.add_argument("--probe-interval-s", type=int, default=PROBE_INTERVAL_S)
        p.add_argument("--tick-s", type=int, default=SUPERVISE_TICK_S,
                       help="the sleep tick, so a run-close ends a wait (a suite shortens it)")
        p.add_argument("--meter-line", default=None,
                       help="a billed line in hand for the remainder (skips the meter)")
        return p

    p = common(sub.add_parser("run-open", help="record the run's opening"), handoff=False)
    p.add_argument("--session", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--regime", required=True, choices=("single", "multi"))
    p.add_argument("--regime-src", required=True, choices=("owner", "head"))
    p.add_argument("--handoff", required=True)
    p.add_argument("--detail", required=True)
    p.add_argument("--pid", type=int, default=None, help="the head's pid (default: parent walk)")
    p.add_argument("--envelope-usd", type=float, default=None)
    p.add_argument("--session-kind", choices=SESSION_KINDS, default="head",
                   help="seed: a launcher's placeholder session that never runs, written as "
                        "session_kind on the run-open event; the waste table and the meter skip "
                        "it rather than reading it as a head that spent nothing (default: head)")
    grants(p)

    p = common(sub.add_parser("run-resume", help="a later head records itself"), handoff=False)
    p.add_argument("--session", default="auto", help="session id, or auto (the last head-successor's)")
    p.add_argument("--head", required=True)
    p.add_argument("--detail", required=True)
    p.add_argument("--pid", type=int, default=None)
    grants(p)

    p = common(sub.add_parser("boundary", help="meter, waste fields, event, trace row, figures, commit"))
    p.add_argument("--from", dest="from_", required=True)
    p.add_argument("--to", required=True)
    p.add_argument("--disposition", required=True)
    p.add_argument("--waste", required=True, help="the three classes, free text")
    p.add_argument("--next", required=True)
    p.add_argument("--commit", default=None, metavar="MSG", help="checkpoint commit in the vault")
    p.add_argument("--shipped", default=None)
    p.add_argument("--waits", default=None)
    p.add_argument("--saving", default=None)
    p.add_argument("--meter-line", default=None, help="a billed line already in hand (skips the meter)")

    p = common(sub.add_parser("ledger", help="one findings-ledger row plus an observation, or "
                                             "--observation alone on any record"))
    # The four are required together (cmd_ledger refuses a partial set by name); they are not
    # argparse-required, because --observation is a complete call on its own.
    p.add_argument("--phase", default=None)
    p.add_argument("--what", default=None)
    p.add_argument("--evidence", default=None)
    p.add_argument("--routing", default=None)
    p.add_argument("--observation", default=None, metavar="WHAT",
                   help="append one observation event and NO hand-off row, to any record that "
                        "exists: the form a record with no run-open (a plain lane run) takes, "
                        "and a head's aside on a record that has one. --phase is optional")

    p = common(sub.add_parser("gate", help="band and envelope check before an item: exit 4 on "
                                           "the band stop, 5 on the envelope stop (the run's "
                                           "spend has reached run-open's envelope_usd), 7 on "
                                           "the second consecutive unmetered gate"),
               handoff=False)
    p.add_argument("--to", required=True, metavar="ITEM")
    p.add_argument("--phase", default="", help="for the observation on an unmetered gate")
    p.add_argument("--meter-line", default=None,
                   help="a billed line in hand for the envelope remainder (skips the meter)")

    p = common(sub.add_parser("handoff", help="rewrite named sections or bullets; --final records head-exit"))
    p.add_argument("--inflight", default=None)
    p.add_argument("--inflight-file", default=None)
    p.add_argument("--inflight-from-record", action="store_true",
                   help="derive '## In flight' from the run record (the last boundary's next, "
                        "the lanes open since it, the decisions since it) instead of taking a "
                        "pack: the pack-age guard's own rewrite, as a command")
    p.add_argument("--set", action="append", metavar="KEY=VALUE",
                   help="bullets: %s; sections: %s" % (", ".join(sorted(BULLETS)), ", ".join(sorted(SECTIONS))))
    p.add_argument("--set-file", action="append", metavar="KEY=PATH")
    p.add_argument("--final", action="store_true", help="record head-exit; needs the next-task pack (D41)")
    p.add_argument("--band", default=None, help="the band edge crossed, unmetered, limit or error (default: measured)")
    p.add_argument("--pid", type=int, default=None)
    p.add_argument("--meter-line", default=None, help="a billed line in hand for head-exit's spent_usd (skips the meter)")

    def head_options(p):
        p.add_argument("--model", default=None)
        p.add_argument("--effort", default="max", help="effort for the head (default max; the owner's head rule)")
        p.add_argument("--config-dir", default=None, help="optional; unused by default (single account, D28)")
        p.add_argument("--harness-bin", default=HARNESS, help="the harness binary (a suite substitutes a stub)")
        return p

    p = common(sub.add_parser("successor", help="record head-exit, start the detached starter (which supervises); returns at once"))
    head_options(p)
    p.add_argument("--budget-usd", type=float, default=None, help="default: the envelope's remainder (N5)")
    p.add_argument("--predecessor-pid", type=int, default=None)
    p.add_argument("--band", default=None)
    p.add_argument("--pid", type=int, default=None)
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S, help="the predecessor-pid wait's bound")
    supervision(p)

    p = common(sub.add_parser("_starter", help="internal: the detached starter and supervisor"))
    head_options(p)
    p.add_argument("--budget", type=float, required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S)
    p.add_argument("--transcript", default="")
    p.add_argument("--predecessor-pid", type=int, default=None)
    supervision(p)

    p = common(sub.add_parser("supervise", help="attach the supervisor to a running head (the head calls it about itself); detaches at once"))
    head_options(p)
    p.add_argument("--pid", type=int, default=None, help="the head's pid (default: the nearest claude ancestor)")
    p.add_argument("--out", default=None, help="the head's .out (default: the record's, else the newest, else none)")
    p.add_argument("--budget-usd", type=float, default=None, help="the cap in hand when the meter cannot size the remainder")
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S, help="how long a head-exit may wait for its head-successor")
    p.add_argument("--stop", action="store_true",
                   help="write the supervisor's stop marker and exit: a sleeping supervisor stands down at its next tick (D43)")
    supervision(p)

    p = common(sub.add_parser("_supervise", help="internal: the detached supervisor"))
    head_options(p)
    p.add_argument("--pid", type=int, required=True)
    p.add_argument("--session", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--budget-usd", type=float, default=None)
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S)
    supervision(p)

    p = common(sub.add_parser("resume-head", help="after a limit the run stood down on (D42): resume the record's last head in place — armed, evented, supervised; detaches at once"))
    head_options(p)
    p.add_argument("--out", default=None, help="the head's .out (default: the record's, else the newest)")
    p.add_argument("--budget-usd", type=float, default=None, help="the cap in hand when the meter cannot size the remainder")
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S)
    supervision(p)

    p = common(sub.add_parser("_resume-head", help="internal: the detached resume-head"))
    head_options(p)
    p.add_argument("--session", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--budget-usd", type=float, default=None)
    p.add_argument("--wait-s", type=int, default=STARTER_WAIT_S)
    supervision(p)

    p = common(sub.add_parser("heartbeat", help="an attended head's idle-cache beat (D32): a background call"), handoff=False)
    p.add_argument("--minutes", type=float, default=HEARTBEAT_MINUTES)
    p.add_argument("--stop", action="store_true", help="write the stop marker and exit")
    p.add_argument("--parent-pid", type=int, default=None, help="end quietly when this pid is gone (default: the parent)")
    p.add_argument("--tick-s", type=float, default=HEARTBEAT_TICK_S, help="the sleep tick (a suite shortens it)")

    p = common(sub.add_parser("grants", help="rewrite the run's grants file and run-<sid> pointer (N7)"), handoff=False)
    grants(p)

    p = common(sub.add_parser("wait-reset", help="the reset wait as a command, for --dry-run checks and a hand-run "
                              "wait: blocks at most --max-block-s and re-issues on `still-running` (exit 8)"),
               handoff=False)
    p.add_argument("--stop-text", default=None)
    p.add_argument("--stop-file", default=None)
    p.add_argument("--reset-at", default=None, metavar="HH:MM|+Ns|ISO")
    p.add_argument("--probe", action="store_true", help="opt in to a $0.05 haiku probe every --probe-interval-s until one succeeds; OFF by default (owner ruling 2026-09-06): without it an unparsed reset records stop-condition limit-unparsed and ends (exit 7), the hand-off being the recovery")
    p.add_argument("--config-dir", default=None, help="optional; unused by default (single account, D28)")
    p.add_argument("--probe-interval-s", type=int, default=PROBE_INTERVAL_S)
    p.add_argument("--max-wait-s", type=int, default=8 * 3600, help="give up (exit 7) past this, from the wait's start")
    p.add_argument("--max-block-s", type=int, default=MAX_BLOCK_S, help="one call blocks at most this long")
    p.add_argument("--lane", default="", help="the lane the limit stopped, for the stop-condition event")
    p.add_argument("--harness-bin", default=HARNESS)

    def window_meter(p):
        p.add_argument("--no-meter", action="store_true",
                       help="render the whole-run rows from the record alone: no meter call "
                            "(the pre-2026-09-07 behaviour, for a caller with no transcripts)")
        p.add_argument("--meter-line", action="append", default=[], metavar="SID=LINE",
                       help="a billed line already in hand for one head session (repeatable), "
                            "used in place of metering that head over the run's window")
        return p

    p = common(sub.add_parser("waste-table", help="render Step 2b's waste table from the run "
                              "record, the whole-run rows metered over the run's window (D36)"),
               handoff=False)
    p.add_argument("--out", default=None, metavar="PATH",
                   help="default: <store>/spawn-records/<run>-waste-table.md")
    window_meter(p)

    p = sub.add_parser("extract-transcript", help="the head's own transcript extracted for a "
                       "reflector lane: human turns and assistant prose (D36)")
    p.add_argument("--session", required=True, metavar="SID")
    p.add_argument("--out", default=None, metavar="DIR",
                   help="default: /tmp/aimyth-extract-<sid>/")
    p.add_argument("--projects-root", default=None, metavar="P",
                   help="default: AIMYTH_PROJECTS_DIR, else ~/.claude/projects")
    p.add_argument("--notification-re", action="append", default=[], metavar="REGEX",
                   help="an extra injected-user-record marker, matched at the start (repeatable)")

    p = sub.add_parser("watch", help="the read-only console: --run for a hands-off run (header, "
                       "items, lanes, timeline, feed) or --session for an attended session's "
                       "background jobs; q quits, r resumes a stopped head (writes only the "
                       "timeline report at the close, and the per-suite totals cache)")
    what = p.add_mutually_exclusive_group(required=True)
    what.add_argument("--run")
    what.add_argument("--session", metavar="SID",
                      help="a transcript stem, or a unique prefix of one: the background-job view")
    p.add_argument("--once", action="store_true")
    p.add_argument("--plain", action="store_true")
    p.add_argument("--no-notify", action="store_true")
    p.add_argument("--refresh", type=float, default=None)
    p.add_argument("--vault", default=None)
    p = sub.add_parser("reflect-inputs", help="the P4 boundary reflection's whole input set in "
                       "one directory for a blind reflector lane (D36)")
    p.add_argument("--run", required=True, help="run id (the record's file stem)")
    p.add_argument("--session", required=True, metavar="SID")
    p.add_argument("--out", required=True, metavar="DIR",
                   help="the reflector lane's own directory: never inside the run store or the "
                        "projects root, which the lane is not granted")
    p.add_argument("--projects-root", default=None, metavar="P",
                   help="default: AIMYTH_PROJECTS_DIR, else ~/.claude/projects")
    p.add_argument("--notification-re", action="append", default=[], metavar="REGEX",
                   help="an extra injected-user-record marker, matched at the start (repeatable)")
    p.add_argument("--dry-run", action="store_true",
                   help="print the counts and what would be written; write and record nothing")
    window_meter(p)

    p = common(sub.add_parser("close", help="final meter, run-close, commit and push on grant"))
    p.add_argument("--commit", default=None, metavar="MSG")
    p.add_argument("--push", action="store_true")
    p.add_argument("--items", default="unstated")
    p.add_argument("--register", default="unstated")
    p.add_argument("--log", default="unstated")
    p.add_argument("--lint", default="unstated")
    p.add_argument("--parity", default=None)
    p.add_argument("--meter-line", default=None)

    a = ap.parse_args()
    handlers = {"run-open": cmd_run_open, "run-resume": cmd_run_resume, "boundary": cmd_boundary,
                "ledger": cmd_ledger, "gate": cmd_gate, "handoff": cmd_handoff,
                "successor": cmd_successor, "_starter": cmd_starter,
                "supervise": cmd_supervise, "_supervise": cmd_supervise_internal,
                "resume-head": cmd_resume_head, "_resume-head": cmd_resume_head_internal,
                "heartbeat": cmd_heartbeat, "grants": cmd_grants,
                "wait-reset": cmd_wait_reset, "close": cmd_close,
                "waste-table": cmd_waste_table,
                "extract-transcript": cmd_extract_transcript,
                "reflect-inputs": cmd_reflect_inputs, "watch": cmd_watch}
    sys.exit(handlers[a.cmd](a) or 0)


if __name__ == "__main__":
    main()
