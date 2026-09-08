#!/usr/bin/env python3
"""fable-share.py — post-run metering and attribution for a delegated run.

The delegate skill's section 2a ("Metering and attribution") makes the metered figure the
close-out truth: lane-reported numbers are estimates. This script produces that figure from
the harness transcripts, reporting three head quantities and every lane's usage:

  - output — the head session's output tokens over the run's turns (the quantity the
    fable-minimising objective targets);
  - flow   — input + cache creation + cache read + output, the whole token flow;
  - peak   — the largest single call's context (input + cache creation + cache read).

Method (section 2a, transcript form): parse JSON records, never substring greps; dedupe
assistant records by message id keeping the FINAL usage record per id, because a step's
earlier records carry a placeholder output count; sum the four usage fields per model. The
model and effort mixes are counted over the same de-duplicated calls, so both sum to the
call count.

It then prices that usage. After the unchanged `fable share:` line it prints

    billed (list, prices <date>): head $X · lanes $Y · session $Z · rewrites k ($w) ·
    rewrite causes switch i lapse j limit k unknown l ·
    tool uses/call head <a> lanes <b> · delegation <single|multi> (<head|owner>)|unstated ·
    baseline <label|none> ·
    lanes n (reasons: (a)×i (b)×j (c)×k (d)×l, none×m) ·
    picks: <class> m a<i> r<j> l<k> · e a<i> r<j> l<k>; …; unrecorded <n> · metered n of m recorded

and one line per model carrying that model's token quantities beside its dollars. The
quantities are printed beside the dollars, never replaced by them: list prices are a proxy
for the plan accounting the owner is actually billed under, which is opaque, so the tokens
are the durable measurement and the dollars are the comparison aid. `--per-agent` adds one
row per agent (the head and every lane): label, model(s), calls, first-call prefix, peak
context, output, tool uses and list dollars.

Billing definitions, each with its derivation:

  - list dollars — per de-duplicated call: input, cache read, 5-minute cache write, 1-hour
    cache write and output tokens, each at its family's rate from `prices.json` beside this
    script (the one price home; its own header carries the rates, their source and the
    substring matching rule). Cache tiers come from `usage.cache_creation`'s two
    `ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` fields; a record carrying no
    such sub-object falls back to `cache_creation_input_tokens` counted at the 5-minute
    rate, and the number of records that fell back is printed on the control line, since
    the fallback is a guess about a tier and must be visible.
  - rewrite — a non-first call of an agent whose cache write is at least 0.9 x BOTH that
    agent's previous call's context and its own (input + cache read + cache write, each). The
    class it names is the full-context rewrite: a model or effort switch, or an expired cache
    entry, rewrites the whole context at the write rate instead of reading it, so the call
    writes back what the previous call held AND reads next to none of its own context. The
    own-context half is what separates a rewrite from a long turn that reads its prefix from
    the cache and appends a large tool result: without it — the rule shipped until 2026-09-05,
    which tested the previous context alone — 37 of the 174 calls flagged in a sweep of one
    harness projects directory (444 transcripts, 13,148 calls, 2026-09-05) had read most of
    their own context back rather than rewriting it (written fraction 0.48 to 0.90), while the
    same rule's `previous_context and` guard silently dropped 43 true rewrites, every one of
    them following a call whose usage record carried four zeros. The 0.9 itself is set by
    judgement: in that sweep 98% of the 12,565 non-first calls wrote under half their own
    context and 129 wrote essentially all of it, but the tail between is continuous (nearest
    calls either side of the line: 0.8995 and 0.9009), so the tenth of slack is a choice about
    how much of a turn's own growth to absorb, not a gap the data draws. No token floor is
    applied: the smallest write the rule flagged in that sweep was 45,318 tokens, so the
    20,000-token floor of the head-side probe that opened the question would have cut nothing.
    `rewrites k ($w)` counts those calls and prices their cache writes alone (the part of the
    call the rewrite added).
  - rewrite cause — every counted rewrite carries exactly one of `switch`, `lapse`, `limit` or
    `unknown`, so the four counts partition the rewrites total and change no figure. `switch`:
    the model or the effort differs from that agent's previous call (effort as the transcript
    records it; where neither call records one, the models alone are compared). `lapse`: the
    gap from the previous call's first record to this one's exceeds the agent's cache tier —
    5 minutes, or 1 hour where the run's spawn record says the lane ran at the 1-hour tier
    (`lane-open`'s `cache_tier_expected`, or `lane-closed`'s `cache_write_tier`, naming `1h`);
    an agent the record does not name is at 5 minutes unless its own transcript carries
    1-hour cache writes, which is the same field the billed line prices as `write_1h`. Both
    TTLs are the harness's documented cache tiers, the pair this script has always priced
    apart (see the two `ephemeral_*_input_tokens` fields above and `prices.json`'s
    `write_5m_mult` / `write_1h_mult`); neither is a threshold this script chose. `limit`: a
    limit stop recorded in the run's spawn record (`stop-condition` with `which: limit`, or
    `lane-closed` with `exit_class: limit`) falls inside the metered window AND inside this
    call's own gap — the stop is paired with the call that followed it, never spread over
    every rewrite of a run that hit a limit, which would leave the other three causes
    unobservable. `unknown` is the residue and is a real answer: it says the transcript and
    the record hold no cause, not that the call is unclassified. Precedence where more than
    one holds: `limit`, then `switch`, then `lapse`. The causes are reported on the billed
    line, in the per-agent table and under `rewrite_causes` in JSON (per agent and in the
    totals); the rewrites total and its dollars are unchanged by any of it.
  - tool uses per call — distinct `tool_use` content blocks divided by de-duplicated calls,
    per agent kind (head, lanes). Counting is by block id across every record of a message,
    because the harness writes one transcript line per content block and the final record
    carries only its own block; block ids are distinct, so no block is counted twice. The
    ratio matches the harness's own per-lane `tool_uses` figure where a spawn record holds
    one (checked against one lane of run 2026-09-04: 22 of 22).
  - reason tally — the letters (a) to (d) read out of each `lane-open` event's `reason`
    field in the run's spawn record (`--spawn-record`): the bracketed form anywhere in the
    text, or a leading bare letter with a colon or a spaced dash (`a:`, `a —`, `a -`), the
    letter's case ignored. A reason may name more than one
    letter, and each letter it names is counted, so the tally can exceed the lane count; a
    lane whose reason names none is counted under `none`. Without a spawn record the tally
    and the recorded-lane count both read `n/a`.
  - picks — per class, how the model and effort each `lane-open` of the metered partition
    recorded relate to the anchor the SAME event recorded (`row_default`), placed on the
    routing order (`order.model`, `order.effort` of `routing.json` beside this script, or
    `--routing PATH`): `a` anchor (equal), `r` raised (above it), `l` lowered (below it); `m`
    is the model axis, `e` the effort axis; one clause per class in name order, a class with
    no lane omitted. `unrecorded n` counts the lane-open events carrying no `model_src` /
    `effort_src` — every lane opened before 2026-09-08, when lane.py began recording the
    per-call pick under the owner's ruling of 2026-09-07 — and they count nowhere else; it is
    never an error. `unplaced n` (printed only when non-zero) counts the axis values of
    recorded events that the order or the event's own anchor cannot place. The direction is
    computed from the event's own `row_default`, never re-resolved, so a later anchor move
    rewrites no history. With no readable routing record the segment reads `picks:
    unavailable (no routing record at <path>)` and every other figure prints as before;
    without a spawn record it reads `picks: n/a`. JSON carries the same counts under `picks`
    (`{"<class>": {"model": {anchor, raised, lowered}, "effort": {…}}, "unrecorded": n,
    "unplaced": n}`, or null with `picks_unavailable` saying why).

Lane discovery by id (`--spawn-record <path>`): an in-session lane is matched by its
`agent_id` to `<project-dir>/<session>/subagents/<agent-id>.jsonl` — the session of its own
partition, which is the metered one unless the paragraph below says otherwise — a headless lane by its
`session_id` to `<projects-root>/*/<session-id>.jsonl` — any project directory under
`--projects-root`, never a guessed one. Record-resolved lanes are metered alongside whatever
`--lanes` finds, de-duplicated by content identity as usual, and `metered n of m recorded`
states how many `lane-open` events were matched to a metered transcript. A mismatch is a
flag on the line, not a premise failure: the figures printed are still real, and the exit
code stays 0, because an unmetered lane understates the bill rather than corrupting it.

A run outlives one head session, so the record is partitioned before any of that is counted.
`run-open` and `run-resume` each name the session that wrote the events after it; every lane
event belongs to the partition its most recent marker opened, and metering one session
expects that session's partition alone — `metered n of m recorded under run-resume <first
eight characters of the session id>` names which. Lanes of another partition are neither
expected nor called missing, a metered transcript recorded under one of them is reported as
from another session of this run rather than as unrecorded, and the reason tally covers the
metered partition only. A record with no marker at all is one partition and it is this
session's, the shape every record had before markers were read. A marker that named no
session claims nothing: its partition is counted on the mismatch flag, never guessed at.

A lane can run under two heads: opened under one and resumed under another through the
wrapper's `lane-resumed` event (the same lane name and session id, a second `lane-closed`
after it). Such a lane belongs to each partition it ran under, and its usage records are
split at the resume's timestamp: the opener bills the records before it, the resumer those
from it on, so each head's line carries the lane cost its own partition incurred and the run
total stays the sum over the heads. The split is by timestamp rather than by the wrapper's
recorded per-close cost because every figure on the billed line is metered from a transcript
and priced from the dated table, while a recorded cost is the harness's own figure on its own
basis; a lanes figure summing the two would be a sum of unlike quantities. `metered n of m`
counts, for the metered partition, the lanes that ran under it (opened or resumed there), and
the reason tally counts each of them. A lane that ran under one session only is metered as it
always was, by the head's window alone. A shared lane whose open or resume carries no
parseable timestamp cannot be split and is left unmetered for every session, flagged on the
line as unsplittable, since a guessed boundary would bill one head for the other's work.

Read-only by construction: it opens files for reading, prints to stdout, and creates,
moves or deletes nothing anywhere. Diagnostics go to stderr.

Premise discipline: a figure is only ever printed when the probe demonstrably ran. Any
broken premise prints, exactly,

    fable share: unmetered (<reason>)

and exits 2 — in text and JSON mode alike, so a consumer checks the exit code before
parsing. One case is a skip rather than a failure: where `--spawn-record` names a record whose
`run-open` marks the metered session as a launcher's placeholder (`session_kind: seed`, the
wrapper's field and its two values `seed` and `head`), the session ran no turns and wrote no
transcript, so the meter prints exactly `seed (skipped)` and exits 0 — JSON carries
`skipped: "seed"` — and the caller counts it under skipped instead of recording a failed meter
call. A record with `session_kind: head`, or with no such field, meters as it always has.
Broken premises: the project directory or the session transcript is missing or
unreadable; a marker does not match; the window holds no assistant record; the window is
inverted; lane scanning finds no readable transcript at all; lane discovery finds a number
of lanes other than --expect-lanes; a flag cannot yield a meaningful figure (a negative
baseline, an expectation that cannot be checked); a spawn record that is missing, unreadable
or holds no lane event. An unforeseen error is reported the same way, with its traceback on
stderr, so a crash can never masquerade as a metered run.

Billing has the same discipline, one step later and with its own line. When the metering
succeeded but the pricing premise fails, the `fable share:` line still prints (it needs no
prices) and the billed line is replaced, exactly, by

    billed: unbilled (<reason>)

with exit 2, in text and JSON mode alike — never a zero, never a partial payload. Broken
billing premises: `prices.json` missing, unreadable or not JSON; a table missing a field,
carrying a non-numeric or non-positive rate; every model id matching no price family (one stray
id beside a priced family is priced-with-an-unpriced-list instead, 2026-09-04); the
known-positive control failing. That control runs on every invocation before any billed
figure is printed: the script prices one built-in fixture call (1,000,000 input, 400,000
cache read, 200,000 5-minute write, 100,000 1-hour write, 50,000 output tokens on a Fable
id) and asserts the table returns $17.10 — 10.00 + 0.10 + 2.50 + 2.00 + 2.50, hand-computed
against the rates the shipped table carries at its date. The anchor is keyed to that date:
when the table is re-priced and its `prices_date` moves, the anchor no longer binds and the
control degrades to its table invariants (every family present and positively priced, the
fixture priced above zero and strictly increasing in each of the five quantities), saying so
on the control line rather than failing a legitimate re-pricing or passing silently.

A malformed record never crashes the run and is never guessed at: a record whose message is
not an object, whose id is unusable, or whose usage carries a non-numeric value is counted
and reported rather than summed. A transcript torn by a write in progress reports its
unparseable line count, saying so when the final line is the torn one.

One threshold classifies and none decides: the 0.9 of the rewrite definition above labels a
call, changes no figure and blocks nothing, and it is stated with its derivation where it is
defined. The two cache TTLs the causes compare a gap against (5 minutes and 1 hour) are the
harness's documented tiers, not a choice made here, and they too only label an already counted
rewrite. Every other number printed is measured from a transcript or priced from the dated
table; the presentation constants are the single decimal place on the share percentage, the
two on dollars and tool uses per call. Every default the script chooses (project directory,
temporary root, lane mode, window bounds, matching fallbacks, price table, delegation
source) is printed in the header or on the control line, so a wrong derivation is visible.

Usage (from anywhere; nothing is assumed about the working directory):

  python3 fable-share.py --session <id> [--vault <root>] [--project-dir <path>]
      [--start <iso|marker>] [--end <iso|marker>] [--lanes auto|none|<glob>...]
      [--expect-lanes <n>] [--baseline-output <n>] [--tmp-root <path>]
      [--format text|json] [--per-agent] [--spawn-record <path>]
      [--projects-root <path>] [--delegation single|multi --delegation-src head|owner]
      [--state-dir <path>] [--baseline <label>] [--prices <path>] [--routing <path>]

  --session takes a full transcript stem or a prefix of one (the eight characters a status
  line shows are what an owner has to hand). A stem that names a file in the project directory
  is used as it always was; otherwise the value is resolved as a prefix, first against
  <project-dir>/<prefix>*.jsonl, then against <projects-root>/*/<prefix>*.jsonl — the same
  order handsoff.py's transcript_for uses for a head started elsewhere. Exactly one match
  resolves, and the resolved full id is what every line and the JSON payload then carry; zero
  or several is a broken premise (the unmetered line on stdout, `PROBE FAILED: --session
  <prefix> matches <k> transcripts under <root>` on stderr naming the count and, where there
  are several, their stems) rather than a guess between transcripts.
  --project-dir defaults to the harness's mapping of the vault's absolute path: every
  character outside A-Za-z0-9- becomes a hyphen, under ~/.claude/projects/. The mapping was
  checked against every project directory of a harness home, comparing each transcript's own
  cwd field with the directory holding it (6 of 6 matched, one path containing an @). Paths
  carrying spaces or non-ASCII characters were not among them, and a decomposed accent maps
  to two hyphens where a composed one maps to one, so a mismatch is possible there: when the
  derived directory or the session file inside it is missing, the failure names the sibling
  directory that does hold the session, and --project-dir overrides the derivation.
  --start and --end each take either an ISO timestamp or a text marker; a marker is
  matched against user-message text for --start (the invoking prompt) and assistant-message
  text for --end (the close-out reply), falling back to any record type and saying so. A
  marker matching more than once takes the first match and reports the others.
  --lanes auto searches both known homes for in-session lane transcripts, the durable
  <project-dir>/<session>/subagents/agent-*.jsonl and the volatile
  <tmp-root>/claude-*/<project-basename>/<session>/tasks/*.output (observed 2026-09-02),
  de-duplicated by content identity: the volatile entries are frequently symlinks to the
  durable files, and some are not transcripts at all. --lanes none meters the head alone and
  asserts no share. Scanning that reaches no readable transcript is a broken premise, since
  a zero lane total would otherwise be a claim with no control behind it; --expect-lanes 0
  is how a run with genuinely no lanes asserts that on purpose.
  --spawn-record adds discovery by id from a run's spawn record (see above) and turns on the
  reason tally and the recorded-lane count; --projects-root (default ~/.claude/projects) is
  where a headless lane's own session file is looked for, across every project directory
  under it. --per-agent adds the per-agent table to text output; the JSON payload always
  carries the same rows under per_agent, so a consumer never needs the flag.
  --delegation with --delegation-src records which delegation regime the run used and who
  chose it. Without the flags the regime is read from the head session's state file,
  <state-dir>/<session>.json as role-style-anchor.py keeps it (its `delegation` and
  `delegation_src` keys, when the regime is single or multi: the head's resolution under
  `auto`, or the owner's word), so the meter runs BEFORE the run's `set-delegation clear`;
  then from the `- **delegation**:` line of <vault>/CUSTOMISATION.md (the pre-rename
  `- **mode**:` line as a fallback) with source `owner`; then `unstated`. --state-dir
  defaults to ~/.cache/aimyth/role-style. --baseline is free text naming what this run is
  being compared against, `none` by default. All are printed and never interpreted: they
  exist so two runs are only ever compared on the same work, and the billed line's
  `(head|owner)` says whose choice the regime was. --prices overrides the price table path,
  whose default is prices.json in this script's own directory. --routing overrides the routing
  record the picks tally takes its order from, whose default is routing.json in the same
  directory; the path used is printed on the control line.
"""
import argparse
import glob
import json
import os
import re
import sys
import traceback
from datetime import datetime, timezone

USAGE_FIELDS = ("input_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "output_tokens")
TIER_5M = "ephemeral_5m_input_tokens"
TIER_1H = "ephemeral_1h_input_tokens"
ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[T ]")
REASON_RE = re.compile(r"\(([a-dA-D])\)")
# A leading bare letter followed by a colon or a spaced dash (`a:`, `a —`, `a -`): the forms two
# heads wrote live, which the bracketed pattern alone read as `none` (register, 2026-09-06).
# lane.py's REASON_LEAD_RE is the twin that refuses a reason carrying none of the forms.
REASON_LEAD_RE = re.compile(r"^\s*([a-dA-D])\s*(?::|[\u2014-](?=\s|$))")
DELEGATION_RE = re.compile(r"^\s*[-*]\s+\*\*delegation\*\*:\s*([A-Za-z][\w-]*)")
LEGACY_MODE_RE = re.compile(r"^\s*[-*]\s+\*\*mode\*\*:\s*([A-Za-z][\w-]*)")   # the pre-rename line
REGIMES = ("single", "multi")     # what a run actually runs under; `auto` is resolved to one per run
# A classifier, not a decision threshold: a call is a full-context rewrite when its cache
# write is at least this fraction of BOTH the previous call's context and its own (input +
# cache read + cache write) — it wrote back what the previous call held and read next to none
# of it. The own-context half is what separates a rewrite from a long turn that reads its
# prefix from the cache and appends a large tool result: on the previous-context test alone,
# 37 of 174 flagged calls in a sweep of one harness projects directory (444 transcripts,
# 13,148 calls, 2026-09-05) were ordinary writes. The fraction itself is set by judgement: in
# that sweep 98% of non-first calls wrote under half their own context and 129 wrote
# essentially all of it, but the tail between is continuous (0.8995 below the line, 0.9009
# above), so the tenth of slack absorbs the turn's own growth by choice rather than by a gap
# in the data. No token floor accompanies it: the smallest write the rule flagged in that
# sweep was 45,318 tokens. It labels calls; it decides nothing.
REWRITE_FRACTION = 0.9
# The two cache tiers the harness documents and this script has always priced apart (the
# `ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` fields of a usage record, and the
# `write_5m_mult` / `write_1h_mult` rates of prices.json): 5 minutes and 1 hour. They are read
# here as the TTL a gap is compared against when a rewrite is given its cause. Neither number
# is chosen by this script, and neither decides anything: they label a rewrite already counted.
CACHE_TIER_5M_S = 300
CACHE_TIER_1H_S = 3600
# The causes a counted rewrite can carry, in the precedence they are tested in. They partition
# the rewrites total: every counted rewrite takes exactly one, so the four counts sum to it.
REWRITE_CAUSES = ("limit", "switch", "lapse", "unknown")
CAUSE_ORDER = ("switch", "lapse", "limit", "unknown")   # the order they are reported in
# The known-positive price control, run on every invocation. One call on a Fable id:
#   1,000,000 input   -> 1.000 * 10.000            = 10.00
#     400,000 read    -> 0.400 * 10.000 * 0.025    =  0.10
#     200,000 write5m -> 0.200 * 10.000 * 1.25     =  2.50
#     100,000 write1h -> 0.100 * 10.000 * 2.00     =  2.00
#      50,000 output  -> 0.050 * 50.000            =  2.50   total $17.10
# The expectation is anchored to the table date it was hand-computed against; when the table
# is re-priced the anchor stops binding and the invariant checks below carry the control.
CONTROL_MODEL = "claude-fable-5-1"
CONTROL_USAGE = (1000000, 400000, 200000, 100000, 50000)   # input, read, write5m, write1h, out
CONTROL_DATE = "2026-09-03"
CONTROL_USD = 17.10
CONTROL_TOLERANCE = 0.005          # half a cent: the line prints dollars to two places
PRICE_FIELDS = ("input", "output", "read_mult", "write_5m_mult", "write_1h_mult")
# A bound with headroom, not a decision threshold: the diagnostic scan of sibling project
# directories stops here. The harness home this was written against held 6 project
# directories (2026-09-02), so the cap leaves about two orders of magnitude of room.
SIBLING_SCAN_CAP = 500


def die(reason):
    """Print the broken-premise line and exit 2. Never a number on a broken premise."""
    print("fable share: unmetered (%s)" % reason)
    sys.exit(2)


def note(msg):
    print(msg, file=sys.stderr)


def derive_project_dir(vault):
    """The harness's project-directory mapping: non [A-Za-z0-9-] -> hyphen, under ~/.claude/projects."""
    slug = re.sub(r"[^A-Za-z0-9-]", "-", os.path.abspath(os.path.expanduser(vault)))
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", slug)


def sibling_hint(project_dir, session):
    """Diagnose a wrong derivation: name the sibling directory that does hold the session."""
    parent = os.path.dirname(os.path.abspath(project_dir))
    try:
        entries = sorted(os.listdir(parent))[:SIBLING_SCAN_CAP]
    except OSError:
        return ""
    hits = [os.path.join(parent, name) for name in entries
            if os.path.isfile(os.path.join(parent, name, session + ".jsonl"))]
    if len(hits) == 1:
        return " — %s holds that session; pass it as --project-dir" % hits[0]
    if len(hits) > 1:
        return " — %d sibling directories hold that session; pass one as --project-dir" % len(hits)
    return " — no sibling directory holds it either; check --session and --vault"


def parse_ts(value):
    if not value:
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        stamp = datetime.fromisoformat(text)
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp


def message_text(rec):
    """Flatten a record's message content to plain text for marker matching."""
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return ""
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parts.append(block["text"])
        return " ".join(parts)
    return ""


def label(value):
    """A hashable, printable form of a record field that should be a string but may not be."""
    if value is None or isinstance(value, str):
        return value
    return repr(value)


def compact(rec, start_marker, end_marker):
    """Retain only what the meter needs, so a very large transcript stays bounded in memory."""
    kind = rec.get("type")
    row = {"type": kind, "ts": rec.get("ts_parsed"), "sm": False, "em": False,
           "sm_any": False, "em_any": False}
    if kind in ("user", "assistant"):
        text = message_text(rec)
        if start_marker and start_marker in text:
            row["sm_any"] = True
            row["sm"] = (kind == "user")
        if end_marker and end_marker in text:
            row["em_any"] = True
            row["em"] = (kind == "assistant")
    if kind == "assistant":
        msg = rec.get("message")
        if not isinstance(msg, dict):
            msg = {}                       # a message that is not an object carries no usage
        usage = msg.get("usage")
        row["mid"] = label(msg.get("id"))
        row["model"] = label(msg.get("model"))
        row["effort"] = label(rec.get("effort"))
        row["usage"] = None
        row["usage_bad"] = False
        row["usage_partial"] = False
        row["tiers"] = (0, 0)
        row["untiered"] = False
        row["tools"] = tool_ids(msg)
        if isinstance(usage, dict):
            try:
                row["usage"] = tuple(int(usage.get(field) or 0) for field in USAGE_FIELDS)
            except (TypeError, ValueError):
                row["usage_bad"] = True    # a non-numeric usage field: count it, never guess it
            else:
                row["usage_partial"] = not all(field in usage for field in USAGE_FIELDS)
                row["tiers"], row["untiered"] = cache_tiers(usage, row["usage"][1])
                if row["tiers"] is None:
                    row["usage_bad"], row["usage"] = True, None
    return row


def tool_ids(msg):
    """The tool_use blocks of one transcript record, by block id.

    The harness writes one line per content block, so a message's blocks are spread over its
    records and the final record carries only its own. Counting is therefore over every
    record of a message id, and by block id so a repeated block could never count twice.
    """
    content = msg.get("content")
    if not isinstance(content, list):
        return ()
    found = []
    for index, block in enumerate(content):
        if isinstance(block, dict) and block.get("type") == "tool_use":
            ident = block.get("id")
            found.append(ident if isinstance(ident, str) else "position-%d" % index)
    return tuple(found)


def cache_tiers(usage, cache_write_total):
    """(5-minute, 1-hour) cache-write tokens, and whether the tier had to be assumed.

    Returns (None, False) when a tier field is present but not a number — an unusable usage
    record, handled exactly like any other, counted and never guessed at.
    """
    block = usage.get("cache_creation")
    if isinstance(block, dict) and (TIER_5M in block or TIER_1H in block):
        try:
            return (int(block.get(TIER_5M) or 0), int(block.get(TIER_1H) or 0)), False
        except (TypeError, ValueError):
            return None, False
    # No sub-object: the whole cache write is counted at the 5-minute rate and the fallback
    # is reported, because assuming a tier is a guess about a 1.25x-versus-2x price.
    return (cache_write_total, 0), bool(cache_write_total)


def read_transcript(path, start_marker=None, end_marker=None):
    """Stream a JSONL transcript into compact rows. Returns (rows, stats)."""
    rows = []
    stats = {"unparseable": 0, "tail_truncated": False}
    last_parsed = True
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            rec = None
            try:
                rec = json.loads(line)
            except ValueError:
                rec = None
            if not isinstance(rec, dict):
                stats["unparseable"] += 1
                last_parsed = False
                continue
            last_parsed = True
            rec["ts_parsed"] = parse_ts(rec.get("timestamp"))
            rows.append(compact(rec, start_marker, end_marker))
    # A torn final line is the signature of a transcript read while it was being written.
    stats["tail_truncated"] = bool(stats["unparseable"]) and not last_parsed
    return rows, stats


def rewrite_cause(model, effort, stamp, previous, tier_s, limit_stamps):
    """Why this counted rewrite rewrote its context. Exactly one cause, so the causes partition
    the rewrites total; the call is already counted and no figure moves either way.

    `previous` is (model, effort, timestamp) of the same agent's previous call. Precedence:
      limit  — a limit stop from the run's spawn record falls in this call's own gap. Paired
               with the call that followed the stop rather than with every rewrite of the run,
               so a run that hit a limit still shows its switches and lapses.
      switch — the model differs, or the effort does where either call records one. A pair
               that records no effort at all is compared on models alone, since an absent
               field is not evidence of a change.
      lapse  — the start-to-start gap exceeds the agent's cache tier (CACHE_TIER_*_S), so the
               entry the next call would have read had expired.
      unknown— the residue: the transcript and the record hold no cause. A real answer.
    A cause needing a timestamp this transcript does not carry is not claimed: it falls
    through to the next test rather than being guessed at.
    """
    prev_model, prev_effort, prev_stamp = previous
    if stamp is not None and prev_stamp is not None:
        if any(prev_stamp < stop <= stamp for stop in limit_stamps):
            return "limit"
    if model != prev_model:
        return "switch"
    if (effort is not None or prev_effort is not None) and effort != prev_effort:
        return "switch"
    if (stamp is not None and prev_stamp is not None
            and (stamp - prev_stamp).total_seconds() > tier_s):
        return "lapse"
    return "unknown"


def aggregate(rows, tier_s=None, limit_stamps=()):
    """Dedupe assistant rows by message id, keeping the final usage record per id, then sum.

    Tool-use blocks are the exception to "final record wins": they are collected over every
    record of a message id (see tool_ids), because each record carries one block.

    `tier_s` is the agent's cache tier in seconds where the run's spawn record names it, and
    None where nothing does — then the transcript decides: an agent with any 1-hour cache
    write ran at the 1-hour tier, else the 5-minute one. `limit_stamps` are the run's limit
    stops inside the metered window. Both feed rewrite_cause and nothing else: no token, no
    dollar and no call count depends on either.
    """
    final = {}
    order = []
    tools = {}
    starts = {}
    raw = 0
    bad_usage = 0
    for index, row in enumerate(rows):
        if row.get("type") != "assistant":
            continue
        key = row.get("mid") or "position-%d" % index   # no id: it can only count as its own call
        if row.get("usage_bad"):
            bad_usage += 1
            continue
        if not row.get("usage"):
            continue
        raw += 1
        if key not in final:
            order.append(key)
        final[key] = row
        # The call's start, for the gap a lapse is measured over: the FIRST record the harness
        # wrote for this message id, not the final one dedup keeps, since a long turn's final
        # record lands well after the call began.
        if key not in starts and row.get("ts") is not None:
            starts[key] = row["ts"]
        if row.get("tools"):
            tools.setdefault(key, set()).update(row["tools"])
    tier_src = "spawn record"
    if tier_s is None:
        one_hour = any(row.get("tiers") and row["tiers"][1] for row in final.values())
        tier_s = CACHE_TIER_1H_S if one_hour else CACHE_TIER_5M_S
        tier_src = ("transcript 1-hour cache writes" if one_hour
                    else "no record entry and no 1-hour write: the 5-minute tier")
    totals = {"calls": len(final), "records": raw, "output": 0, "flow": 0, "peak": 0,
              "models": {}, "efforts": {}, "bad_usage": bad_usage, "partial_usage": 0,
              "per_model": {}, "tool_uses": 0, "untiered": 0, "first_prefix": 0,
              "rewrites": 0, "rewrite_tiers": {},
              "rewrite_causes": {cause: 0 for cause in CAUSE_ORDER},
              "cache_tier_s": tier_s, "cache_tier_src": tier_src}
    previous_context = None
    previous_call = (None, None, None)
    for position, key in enumerate(order):
        row = final[key]
        inp, cache_write, cache_read, out = row["usage"]
        w5, w1 = row["tiers"]
        used = len(tools.get(key, ()))
        totals["output"] += out
        totals["flow"] += inp + cache_write + cache_read + out
        totals["peak"] = max(totals["peak"], inp + cache_write + cache_read)
        totals["tool_uses"] += used
        if row.get("untiered"):
            totals["untiered"] += 1
        model = row.get("model") or "unknown"
        totals["models"][model] = totals["models"].get(model, 0) + 1
        per = totals["per_model"].setdefault(model, {"calls": 0, "input": 0, "cache_read": 0,
                                                     "write_5m": 0, "write_1h": 0,
                                                     "output": 0, "tool_uses": 0})
        per["calls"] += 1
        per["input"] += inp
        per["cache_read"] += cache_read
        per["write_5m"] += w5
        per["write_1h"] += w1
        per["output"] += out
        per["tool_uses"] += used
        effort = row.get("effort")
        if effort is not None:
            totals["efforts"][effort] = totals["efforts"].get(effort, 0) + 1
        if row.get("usage_partial"):
            totals["partial_usage"] += 1
        context = inp + cache_read + cache_write
        if position == 0:
            totals["first_prefix"] = inp + cache_write
        # A full-context rewrite writes back what the previous call held (the second test)
        # AND reads next to none of its own context from the cache (the first). A call whose
        # usage records no context at all rewrote nothing, so it is never one; testing the
        # previous context alone counted long turns that appended a large tool result, and
        # guarding on a truthy previous context dropped the rewrites that followed a call
        # recording four zeros (both measured 2026-09-05, see REWRITE_FRACTION).
        elif (context and cache_write >= REWRITE_FRACTION * context
              and cache_write >= REWRITE_FRACTION * previous_context):
            totals["rewrites"] += 1
            tier = totals["rewrite_tiers"].setdefault(model, {"write_5m": 0, "write_1h": 0})
            tier["write_5m"] += w5
            tier["write_1h"] += w1
            # One cause per counted rewrite, so the four counts sum to the total above.
            cause = rewrite_cause(model, row.get("effort"), starts.get(key), previous_call,
                                  tier_s, limit_stamps)
            totals["rewrite_causes"][cause] += 1
        previous_context = context
        previous_call = (model, row.get("effort"), starts.get(key))
    return totals


def fmt_models(models):
    if not models:
        return "none"
    return ", ".join("%s:%d" % (name, count) for name, count in sorted(models.items()))


def plural(count, word):
    return "%d %s%s" % (count, word, "" if count == 1 else "s")


def data_clause(totals):
    """The malformed-record clause, printed only when there is something to report."""
    parts = []
    if totals["bad_usage"]:
        parts.append("%s with unusable usage skipped" % plural(totals["bad_usage"], "assistant record"))
    if totals["partial_usage"]:
        parts.append("%s missing a usage field (counted as 0)" % plural(totals["partial_usage"], "call"))
    return " · ".join(parts)


def resolve_window(rows, start, end):
    """Locate the run's records. Returns (start_index, end_index, notes)."""
    notes = {}
    last = len(rows) - 1
    if start is None:
        si, notes["start"] = 0, "first record (no --start given)"
        notes["start_matches"] = 0
    elif ISO_RE.match(start):
        bound = parse_ts(start)
        if bound is None:
            die("start reads as a timestamp but will not parse (a marker beginning with a date "
                "is read as a timestamp): %s" % start)
        si = next((i for i, r in enumerate(rows) if r["ts"] and r["ts"] >= bound), None)
        if si is None:
            die("no record at or after the start timestamp: %s" % start)
        notes["start"] = "first record at or after %s" % start
        notes["start_matches"] = 0
    else:
        hits = [i for i, r in enumerate(rows) if r["sm"]]
        if hits:
            si = hits[0]
            notes["start"] = 'marker "%s" in a user message' % start
        else:
            hits = [i for i, r in enumerate(rows) if r["sm_any"]]
            if not hits:
                die("start marker not found: %s" % start)
            si = hits[0]
            notes["start"] = 'marker "%s" (matched on any record type, not a user message)' % start
        notes["start_matches"] = len(hits)
        if len(hits) > 1:
            # An over-broad marker silently shifting the window is the failure this names.
            notes["start"] += " · %s later, first taken" % plural(len(hits) - 1, "further match")

    if end is None:
        ei, notes["end"] = last, "last record (no --end given)"
        notes["end_matches"] = 0
    elif ISO_RE.match(end):
        bound = parse_ts(end)
        if bound is None:
            die("end reads as a timestamp but will not parse (a marker beginning with a date "
                "is read as a timestamp): %s" % end)
        ei = next((i for i in range(last, -1, -1) if rows[i]["ts"] and rows[i]["ts"] <= bound), None)
        if ei is None:
            die("no record at or before the end timestamp: %s" % end)
        notes["end"] = "last record at or before %s" % end
        notes["end_matches"] = 0
    else:
        hits = [i for i in range(si + 1, len(rows)) if rows[i]["em"]]
        kind = "in an assistant reply"
        if not hits:
            hits = [i for i in range(si + 1, len(rows)) if rows[i]["em_any"]]
            kind = "(matched on any record type, not an assistant reply)"
        if not hits:
            earlier = sum(1 for i in range(0, si + 1) if rows[i]["em_any"])
            if earlier:
                die('end marker matches only at or before the start bound (%s): %s'
                    % (plural(earlier, "earlier match"), end))
            die("end marker not found: %s" % end)
        ei = hits[0]
        notes["end"] = 'marker "%s" %s' % (end, kind)
        notes["end_matches"] = len(hits)
        if len(hits) > 1:
            notes["end"] += " · %s later, first taken" % plural(len(hits) - 1, "further match")

    if ei < si:
        die("the end bound precedes the start bound")
    return si, ei, notes


def window_bounds(rows, si, ei):
    """The window's wall-clock edges, used to select each lane's own records."""
    first = next((rows[i]["ts"] for i in range(si, ei + 1) if rows[i]["ts"]), None)
    lastc = next((rows[i]["ts"] for i in range(ei, si - 1, -1) if rows[i]["ts"]), None)
    return first, lastc


def lane_patterns(mode, patterns, project_dir, session, tmp_root):
    """The globs a lane scan will search — printed in a failure so the probe stays auditable."""
    if mode == "auto":
        return [os.path.join(project_dir, session, "subagents", "agent-*.jsonl"),
                os.path.join(tmp_root, "claude-*", os.path.basename(project_dir),
                             session, "tasks", "*.output")]
    return [os.path.expanduser(pattern) for pattern in patterns]


def discover_lanes(mode, patterns, project_dir, session, tmp_root, recorded=()):
    """Both known lane homes plus any path resolved from the spawn record, de-duplicated by
    content identity. Returns (paths, scan_counts)."""
    durable, volatile = [], []
    if mode == "auto":
        durable = sorted(glob.glob(os.path.join(project_dir, session, "subagents", "agent-*.jsonl")))
        volatile = sorted(glob.glob(os.path.join(
            tmp_root, "claude-*", os.path.basename(project_dir), session, "tasks", "*.output")))
        candidates = durable + volatile
    else:
        candidates = []
        for pattern in patterns:
            candidates.extend(sorted(glob.glob(os.path.expanduser(pattern))))
    candidates = candidates + [path for path in recorded if path not in candidates]
    unique, seen, skipped = [], set(), 0
    for path in candidates:
        # isfile() is False for a directory, a dangling link and a symlink loop alike, and
        # raises for none of them; each is a candidate that cannot be a transcript.
        if not os.path.isfile(path):
            skipped += 1
            continue
        try:
            key = os.path.realpath(path)
        except OSError:
            skipped += 1
            continue
        if key in seen:
            continue
        seen.add(key)
        unique.append(path)
    return unique, {"durable": len(durable), "volatile": len(volatile),
                    "recorded": len(recorded),
                    "candidates": len(candidates), "unique": len(unique),
                    "skipped": skipped, "identity_duplicates": 0, "no_window_records": 0}


def lane_identity(path):
    """A lane's content id: its own agent id where the transcript carries one, else the file stem."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict) and rec.get("agentId"):
                    return str(rec["agentId"])
    except OSError:
        return None
    stem = os.path.basename(path)
    for suffix in (".jsonl", ".output"):
        if stem.endswith(suffix):
            stem = stem[:-len(suffix)]
    if stem.startswith("agent-"):
        stem = stem[len("agent-"):]
    return stem


def scan_clause(scan):
    """The lane-scan control, with each silently-dropped candidate class named."""
    text = ("control: %s scanned (%d durable, %d volatile, %d unique after de-duplication)"
            % (plural(scan["candidates"], "candidate transcript"),
               scan["durable"], scan["volatile"], scan["unique"]))
    if scan.get("recorded"):
        text += " · %d resolved from the spawn record" % scan["recorded"]
    if scan["skipped"]:
        text += " · %d skipped (not a regular file)" % scan["skipped"]
    if scan["identity_duplicates"]:
        text += " · %d dropped as a duplicate identity" % scan["identity_duplicates"]
    if scan["no_window_records"]:
        text += " · %d with no records in the window" % scan["no_window_records"]
    if scan.get("unsplittable"):
        text += " · %d shared lane(s) unsplittable, left unmetered" % scan["unsplittable"]
    return text


def default_prices_path():
    """prices.json in this script's own directory — derived, never a hard-coded location."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "prices.json")


def load_prices(path):
    """Load and validate the price table. Returns (table, reason): one of them is always None."""
    try:
        with open(path, encoding="utf-8") as handle:
            table = json.load(handle)
    except OSError as exc:
        return None, "price table unreadable: %s (%s)" % (path, exc)
    except ValueError as exc:
        return None, "price table is not valid JSON: %s (%s)" % (path, exc)
    if not isinstance(table, dict):
        return None, "price table is not an object: %s" % path
    families = table.get("families")
    order = table.get("family_order")
    if not isinstance(families, dict) or not families:
        return None, "price table carries no families: %s" % path
    if not isinstance(order, list) or not order:
        return None, "price table carries no family_order: %s" % path
    if not isinstance(table.get("prices_date"), str):
        return None, "price table carries no prices_date: %s" % path
    for name in order:
        rates = families.get(name)
        if not isinstance(rates, dict):
            return None, "price table lists family %r in family_order but carries no rates for it" % name
        for field in PRICE_FIELDS:
            value = rates.get(field)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value <= 0:
                # A zero or missing rate would price real tokens at nothing, which is the one
                # thing the billed line must never do.
                return None, "price table field %s of family %s is not a positive number: %r" % (
                    field, name, value)
    return table, None


def family_for(model, table):
    """The price family of a model id, by substring in the table's stated order."""
    text = (model or "").lower()
    for name in table["family_order"]:
        if name.lower() in text:
            return name
    return None


def price_tokens(rates, inp, read, w5, w1, out):
    """List dollars for one call's five token quantities, at one family's rates."""
    return (inp * rates["input"]
            + read * rates["input"] * rates["read_mult"]
            + w5 * rates["input"] * rates["write_5m_mult"]
            + w1 * rates["input"] * rates["write_1h_mult"]
            + out * rates["output"]) / 1e6


def price_control(table):
    """The known-positive control: price the built-in fixture and check it before any figure.

    Returns (ok, note). Anchored to the table date the expectation was hand-computed against;
    when the table has been re-priced since, the anchor cannot bind and the invariants below
    carry the control instead — stated on the control line, never silently dropped.
    """
    family = family_for(CONTROL_MODEL, table)
    if family is None:
        return False, "control fixture model %s matches no family in the table" % CONTROL_MODEL
    rates = table["families"][family]
    got = price_tokens(rates, *CONTROL_USAGE)
    if got <= 0:
        return False, "control fixture priced at $%.2f, which cannot be right" % got
    for position in range(len(CONTROL_USAGE)):
        more = list(CONTROL_USAGE)
        more[position] += 1000
        if price_tokens(rates, *more) <= got:
            # Every quantity must cost something: a table that prices one of them at nothing
            # would silently zero a whole column of the bill.
            return False, "control fixture price does not rise with quantity %d" % position
    if table["prices_date"] != CONTROL_DATE:
        return True, ("fixture $%.2f, anchor $%.2f not applicable (table dated %s, "
                      "anchor %s); invariants checked"
                      % (got, CONTROL_USD, table["prices_date"], CONTROL_DATE))
    if abs(got - CONTROL_USD) > CONTROL_TOLERANCE:
        return False, ("control fixture priced at $%.4f against the hand-computed $%.2f for the "
                       "table dated %s" % (got, CONTROL_USD, CONTROL_DATE))
    return True, "fixture $%.2f matches the hand-computed anchor for %s" % (got, CONTROL_DATE)


def read_settings_delegation(vault):
    """The delegation regime from <vault>/CUSTOMISATION.md's `- **delegation**:` line (the
    pre-rename `- **mode**:` line as a fallback), source `owner`. Returns (regime, source,
    where): `unstated` with source None when the file or the line is absent, or the line
    reads anything but single/multi — `auto` is no regime; a run's resolution under it lives
    in the session state file, which is read before this."""
    path = os.path.join(os.path.abspath(os.path.expanduser(vault)), "CUSTOMISATION.md")
    if not os.path.isfile(path):
        return "unstated", None, "no CUSTOMISATION.md at %s" % path
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as exc:
        return "unstated", None, "CUSTOMISATION.md unreadable (%s)" % exc
    for pattern, name in ((DELEGATION_RE, "delegation line"), (LEGACY_MODE_RE, "pre-rename mode line")):
        for line in lines:
            found = pattern.match(line)
            if found:
                value = found.group(1)
                if value in REGIMES:
                    return value, "owner", "the %s of %s" % (name, path)
                return "unstated", None, ('the %s of %s reads "%s", which is neither single nor '
                                          'multi' % (name, path, value))
    return "unstated", None, "no delegation line in %s" % path


def read_state_delegation(state_dir, session):
    """The run's resolved regime from the head session's state file, the one
    role-style-anchor.py keeps at <state-dir>/<session>.json: its `delegation` and
    `delegation_src` keys, when the regime is single or multi (an owner-set `auto` there is
    no regime; an empty slot means the run was closed and cleared, or never resolved).
    Returns (regime, source, where), or (None, None, why) when the file yields nothing
    usable, so the control line can say what was tried before the Settings line."""
    safe = re.sub(r"[^A-Za-z0-9._-]", "-", session) or "unknown"
    path = os.path.join(os.path.abspath(os.path.expanduser(state_dir)), safe + ".json")
    if not os.path.isfile(path):
        return None, None, "no session state file at %s" % path
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError) as exc:
        return None, None, "session state file unreadable (%s)" % exc
    if not isinstance(state, dict):
        return None, None, "session state file is not an object: %s" % path
    regime, source = state.get("delegation"), state.get("delegation_src")
    if regime in REGIMES and source in ("head", "owner"):
        return regime, source, "the session state file %s" % path
    return None, None, ("session state file %s carries no resolved regime (delegation %r, "
                        "source %r)" % (path, regime, source))


def read_spawn_record(path):
    """The run's lanes as its spawn record has them, partitioned by head session.

    Reads three lane event shapes, all observed in real records: `lane-open` (the lane's name
    and its reason), `lane-spawned` (one lane's `agent_id`) and `lanes-spawned` (a `lanes` map
    of name to agent id, written when several lanes go out together). A lane's transcript is
    found by `agent_id` in the session's subagents directory, or by `session_id` — a headless
    lane's own top-level transcript — under the projects root.

    A run outlives one head session: `run-open` and `run-resume` each name the session that
    wrote the events after it, so every lane event belongs to the partition its most recent
    such marker opened. Metering one session therefore expects that session's partition and
    no other, which is what keeps a resumed run from reporting an earlier session's lanes as
    missing. A `lane-resumed` event (the wrapper resuming a lane, the same name and session
    id) adds a span to the lane it names — the lane then belongs to the resume's partition
    too, from the resume's timestamp on — so a lane resumed by a later head is billed to that
    head for the resume and to its opener for the first run. Returns (lanes, unparseable,
    partitions, has_markers, unopened_resumes): each lane carries the index of the partition
    that opened it and its `spans` (partition and timestamp of the open and of every resume,
    in record order); a partition whose marker named no session carries None, never a guess;
    a resume naming a lane the record never opened is counted, never invented. A record with
    no marker at all is one partition, matched against whatever session is being metered —
    the shape every record had before run markers were read.

    Two more fields are read, for the rewrite causes and nothing else: a lane's cache tier
    (`lane-open`'s `cache_tier_expected`, or `lane-closed`'s `cache_write_tier`, naming `1h`),
    and the run's limit stops (`stop-condition` with `which: limit`, and `lane-closed` with
    `exit_class: limit`) as a list of timestamps. A limit stop with no parseable timestamp
    cannot be paired with a call and is dropped rather than placed by guess. From 2026-09-08
    each lane also carries `pick`, the lane-open's per-call pick fields for the picks tally
    (see pick_fields); nothing else reads them.
    """
    lanes = []
    index = {}
    by_name = {}
    limit_stops = []
    unparseable = 0
    unopened_resumes = 0
    partitions = [{"kind": "none", "session": None}]
    current = 0
    has_markers = False
    with open(os.path.expanduser(path), encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                unparseable += 1
                continue
            if not isinstance(rec, dict):
                unparseable += 1
                continue
            event = rec.get("event")
            name = rec.get("lane")
            if event in ("run-open", "run-resume"):
                has_markers = True
                session = rec.get("session")
                partitions.append({"kind": event,
                                   "session": session if isinstance(session, str) else None})
                current = len(partitions) - 1
            elif event == "lane-open" and name is not None:
                name = str(name)
                reason = rec.get("reason")
                tier = rec.get("cache_tier_expected")
                lane = {"name": name, "reason": reason if isinstance(reason, str) else "",
                        "agent_id": None, "session_id": None, "partition": current,
                        "cache_tier": tier if isinstance(tier, str) else None,
                        "pick": pick_fields(rec),
                        "spans": [{"partition": current, "ts": parse_ts(rec.get("ts")),
                                   "event": "lane-open"}]}
                lanes.append(lane)
                index[(current, name)] = lane         # a re-opened lane keeps one entry
                by_name[name] = lane                  # ...and a resume names the latest open
            elif event == "lane-spawned" and name is not None:
                lane = index.get((current, str(name)))
                if lane is not None:
                    if isinstance(rec.get("agent_id"), str):
                        lane["agent_id"] = rec["agent_id"]
                    if isinstance(rec.get("session_id"), str):
                        lane["session_id"] = rec["session_id"]
            elif event == "lane-resumed" and name is not None:
                lane = by_name.get(str(name))
                if lane is None:
                    unopened_resumes += 1             # a resume of a lane never opened here
                    continue
                lane["spans"].append({"partition": current, "ts": parse_ts(rec.get("ts")),
                                      "event": "lane-resumed"})
                if lane["session_id"] is None and isinstance(rec.get("session_id"), str):
                    lane["session_id"] = rec["session_id"]
            elif event == "lane-closed":
                lane = by_name.get(str(name)) if name is not None else None
                written = rec.get("cache_write_tier")
                if lane is not None and isinstance(written, str) and "1h" in written:
                    lane["cache_tier"] = written
                if rec.get("exit_class") == "limit":
                    stamp = parse_ts(rec.get("ts"))
                    if stamp is not None:
                        limit_stops.append(stamp)
            elif event == "stop-condition" and rec.get("which") == "limit":
                stamp = parse_ts(rec.get("ts"))
                if stamp is not None:
                    limit_stops.append(stamp)
            elif event == "lanes-spawned" and isinstance(rec.get("lanes"), dict):
                for key, value in rec["lanes"].items():
                    lane = index.get((current, str(key)))
                    if lane is None or not isinstance(value, str):
                        continue
                    if lane["agent_id"] is None:
                        lane["agent_id"] = value
    return lanes, unparseable, partitions, has_markers, unopened_resumes, sorted(limit_stops)


def seed_sessions(path):
    """The sessions a spawn record marks as a launcher's placeholder: `session_kind: seed` on a
    `run-open` event (the wrapper's field, values `seed` and `head`).

    A seed session starts the run and ends; it runs no turns and no transcript is ever written
    for it, so metering it is a category error rather than a failure. Unreadable or malformed
    here is not the place to fail — the record's own premises are checked below, in the order
    they always were — so this returns what it could read and nothing else.
    """
    found = set()
    try:
        handle = open(os.path.expanduser(path), encoding="utf-8", errors="replace")
    except OSError:
        return found
    with handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict) or rec.get("event") != "run-open":
                continue
            if rec.get("session_kind") == "seed" and isinstance(rec.get("session"), str):
                found.add(rec["session"])
    return found


def seeded(seeds, session):
    """Whether this session is one the record marks seed: equal, or the eight-character prefix
    relation session_matches already governs the run markers by."""
    return any(recorded == session or session_matches(recorded, session) for recorded in seeds)


def probe_failed(what):
    """The lane-facing diagnostic on stderr. The meter's own unmetered line still goes to
    stdout, so a consumer parsing stdout sees the shape it always has."""
    note("PROBE FAILED: %s" % what)


def resolve_short_session(project_dir, session, projects_root):
    """Resolve a short --session (a prefix) to the one transcript it names.

    Reached only when no <project-dir>/<session>.jsonl exists, so a full stem behaves exactly
    as it always has. The search order mirrors handsoff.py's transcript_for: the project
    directory being metered first, then every project directory under the projects root, for a
    head started elsewhere. Exactly one hit resolves and its stem is returned; zero or several
    is a broken premise, never a guess between transcripts — the stems are named so the caller
    can pass a longer prefix.
    """
    for root, pattern in ((project_dir, os.path.join(project_dir, session + "*.jsonl")),
                          (projects_root, os.path.join(projects_root, "*", session + "*.jsonl"))):
        hits = sorted(glob.glob(pattern))
        if len(hits) == 1:
            return hits[0], os.path.basename(hits[0])[:-len(".jsonl")]
        if hits:
            stems = ", ".join(sorted(os.path.basename(hit)[:-len(".jsonl")] for hit in hits))
            probe_failed("--session %s matches %d transcripts under %s: %s"
                         % (session, len(hits), root, stems))
            die("session prefix matches %d transcripts under %s: %s"
                % (len(hits), root, stems))
    probe_failed("--session %s matches 0 transcripts under %s" % (session, projects_root))
    die("session transcript not found: %s%s"
        % (os.path.join(project_dir, session + ".jsonl"), sibling_hint(project_dir, session)))


def span_clip(spans, mine):
    """The wall-clock intervals of a shared lane's spans that belong to the metered session:
    each runs from its own timestamp to the next span's (any partition), the last open-ended.
    None when a needed timestamp is missing — the lane cannot be split without a guess."""
    clip = []
    for i, span in enumerate(spans):
        if span["partition"] not in mine:
            continue
        end = spans[i + 1]["ts"] if i + 1 < len(spans) else None
        if span["ts"] is None or (i + 1 < len(spans) and end is None):
            return None
        clip.append((span["ts"], end))
    return clip


def in_clip(stamp, clip):
    return any(start <= stamp and (end is None or stamp < end) for start, end in clip)


def resolve_recorded_lanes(lanes, project_dir, session, projects_root):
    """Find each recorded lane's transcript by id. Returns {path: lane} and a note dict.

    Every partition's lanes are resolved, so a transcript recorded under another session of
    the same run can be named as such rather than counted as unrecorded; the note counters
    describe the partition being metered (the lanes flagged `selected`).
    """
    paths = {}
    notes = {"in_session": 0, "headless": 0, "no_id": 0, "not_found": 0, "ambiguous": 0}
    for lane in lanes:
        mine = lane.get("selected")
        agent_id = lane.get("agent_id")
        session_id = lane.get("session_id")
        # An in-session lane sits under the session that spawned it, which is its partition's
        # own session and not necessarily the one being metered. A partition that named no
        # session can place none of its lanes, so none of them is claimed here.
        owner = lane.get("session") or (session if not lane.get("partitioned") else None)
        if not owner:
            continue
        if agent_id:
            stem = agent_id if agent_id.startswith("agent-") else "agent-" + agent_id
            candidate = os.path.join(project_dir, owner, "subagents", stem + ".jsonl")
            if os.path.isfile(candidate):
                paths.setdefault(candidate, lane)
                lane["path"] = candidate
                notes["in_session"] += mine
            else:
                notes["not_found"] += mine
        elif session_id:
            # A headless lane writes its own top-level transcript, in whichever project
            # directory the wrapper ran under: searched, never guessed.
            hits = sorted(glob.glob(os.path.join(projects_root, "*", session_id + ".jsonl")))
            if len(hits) == 1:
                paths.setdefault(hits[0], lane)
                lane["path"] = hits[0]
                notes["headless"] += mine
            elif hits:
                notes["ambiguous"] += mine
            else:
                notes["not_found"] += mine
        else:
            notes["no_id"] += mine
    return paths, notes


def partition_label(partitions, indices, session):
    """How the billed line names the partition whose lanes were expected."""
    if not indices:
        return "recorded under no partition for %s" % session[:8]
    if len(indices) == 1:
        return "recorded under %s %s" % (partitions[indices[0]]["kind"], session[:8])
    return "recorded under %d partitions of %s" % (len(indices), session[:8])


def session_matches(recorded, session):
    """A run marker's session id matches the metered session when equal, or when one is a
    prefix (at least eight characters) of the other: the head writes run-open with the
    eight-character prefix the status hook shows, the wrapper the full id (2026-09-06)."""
    if not recorded or not session: return False
    if recorded == session: return True
    short, long_ = sorted((recorded, session), key=len)
    return len(short) >= 8 and long_.startswith(short)


def reason_tally(lanes):
    """The (a)-(d) letters of each lane's reason; a lane naming none counts under `none`."""
    tally = {"a": 0, "b": 0, "c": 0, "d": 0, "none": 0}
    for lane in lanes:
        reason = lane.get("reason") or ""
        letters = {letter.lower() for letter in REASON_RE.findall(reason)}
        lead = REASON_LEAD_RE.match(reason)
        if lead:
            letters.add(lead.group(1).lower())
        if not letters:
            tally["none"] += 1
        for letter in letters:
            tally[letter] += 1
    return tally


def fmt_tally(tally):
    if tally is None:
        return "n/a"
    return "%s, none×%d" % (" ".join("(%s)×%d" % (letter, tally[letter])
                                          for letter in ("a", "b", "c", "d")), tally["none"])


def pick_fields(rec):
    """The per-call pick a `lane-open` recorded, as the picks tally reads it: the class, the two
    values, the anchor the event itself recorded (`row_default`) and whether the event carries
    the source fields lane.py writes from 2026-09-08 (`model_src`, `effort_src`). An event
    without both is `unrecorded`, whatever else it holds."""
    row_default = rec.get("row_default")

    def text(key):
        return rec[key] if isinstance(rec.get(key), str) else None
    return {"class": text("class"), "model": text("model"), "effort": text("effort"),
            "row_default": row_default if isinstance(row_default, dict) else None,
            "recorded": isinstance(rec.get("model_src"), str)
            and isinstance(rec.get("effort_src"), str)}


def load_routing_order(path):
    """(order, None): the routing record's `order.model` and `order.effort` lists, the strength
    ranking the picks tally places each value on — or (None, why) when the record is missing,
    unreadable, not JSON or without those lists. Never a premise failure of the meter: the
    picks segment reads `unavailable (<why>)` and every other figure prints as before."""
    if not os.path.isfile(path):
        return None, "no routing record at %s" % path
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        return None, "routing record at %s unreadable: %s" % (path, exc)
    order = data.get("order") if isinstance(data, dict) else None
    if not isinstance(order, dict):
        return None, "routing record at %s has no order" % path
    for axis in ("model", "effort"):
        values = order.get(axis)
        if not isinstance(values, list) or not values \
                or not all(isinstance(value, str) for value in values):
            return None, "routing record at %s has no order.%s list" % (path, axis)
    return {"model": list(order["model"]), "effort": list(order["effort"])}, None


def pick_tally(lanes, order):
    """(classes, counts). Per class, how each recorded lane-open's model and effort relate to
    the anchor the same event recorded: `anchor` (equal), `raised` (above it in the routing
    order), `lowered` (below it). The direction is read from the event's own `row_default`,
    never re-resolved, so a later anchor move rewrites no history. `counts["unrecorded"]` is
    the lane-open events carrying no source fields (every lane opened before 2026-09-08),
    `counts["unplaced"]` the axis values of recorded events that the order or the event's own
    anchor cannot place; neither is an error."""
    classes = {}
    counts = {"unrecorded": 0, "unplaced": 0}
    for lane in lanes:
        pick = lane.get("pick") or {}
        if not pick.get("recorded"):
            counts["unrecorded"] += 1
            continue
        per = classes.setdefault(pick.get("class") or "unknown",
                                 {axis: {"anchor": 0, "raised": 0, "lowered": 0}
                                  for axis in ("model", "effort")})
        anchors = pick.get("row_default") or {}
        for axis in ("model", "effort"):
            value, anchor = pick.get(axis), anchors.get(axis)
            if value not in order[axis] or anchor not in order[axis]:
                counts["unplaced"] += 1
                continue
            delta = order[axis].index(value) - order[axis].index(anchor)
            per[axis]["anchor" if delta == 0 else "raised" if delta > 0 else "lowered"] += 1
    return classes, counts


def fmt_picks(picks, unavailable):
    """The picks segment of the billed line: `m` the model axis, `e` the effort axis, `a`/`r`/`l`
    anchor/raised/lowered, one clause per class in name order, then `unrecorded n` and, only
    when non-zero, `unplaced n`."""
    if unavailable:
        return "unavailable (%s)" % unavailable
    if picks is None:
        return "n/a"
    classes, counts = picks
    parts = []
    for cls in sorted(classes):
        per = classes[cls]
        parts.append("%s m a%d r%d l%d · e a%d r%d l%d"
                     % (cls, per["model"]["anchor"], per["model"]["raised"], per["model"]["lowered"],
                        per["effort"]["anchor"], per["effort"]["raised"], per["effort"]["lowered"]))
    parts.append("unrecorded %d" % counts["unrecorded"])
    if counts["unplaced"]:
        parts.append("unplaced %d" % counts["unplaced"])
    return "; ".join(parts)


def picks_payload(picks):
    """The JSON form of the picks tally: the per-class objects beside `unrecorded` and `unplaced`."""
    if picks is None:
        return None
    classes, counts = picks
    payload = {cls: classes[cls] for cls in sorted(classes)}
    payload.update(counts)
    return payload


def fmt_causes(causes):
    """The four cause counts, always all four and always in the same order: they partition the
    rewrites total, and a suppressed zero would hide which cause the run did not have."""
    return " ".join("%s %d" % (cause, causes.get(cause, 0)) for cause in CAUSE_ORDER)


def merge_causes(into, causes):
    for cause, count in causes.items():
        into[cause] = into.get(cause, 0) + count


def fmt_ratio(tool_uses, calls):
    return "n/a" if not calls else "%.2f" % (tool_uses / calls)


def price_agent(totals, table):
    """List dollars for one agent's calls, plus the dollars its rewrites' cache writes cost.

    Returns (usd, rewrite_usd, unknown_models). An unknown model id is returned, never
    priced: the caller turns it into the unbilled premise failure.
    """
    usd = 0.0
    rewrite_usd = 0.0
    unknown = set()
    for model, per in totals["per_model"].items():
        family = family_for(model, table)
        if family is None:
            unknown.add(model)
            continue
        rates = table["families"][family]
        usd += price_tokens(rates, per["input"], per["cache_read"],
                            per["write_5m"], per["write_1h"], per["output"])
    for model, tier in totals["rewrite_tiers"].items():
        family = family_for(model, table)
        if family is None:
            unknown.add(model)
            continue
        rates = table["families"][family]
        rewrite_usd += price_tokens(rates, 0, 0, tier["write_5m"], tier["write_1h"], 0)
    return usd, rewrite_usd, unknown


def merge_per_model(into, totals):
    for model, per in totals["per_model"].items():
        row = into.setdefault(model, {"calls": 0, "input": 0, "cache_read": 0, "write_5m": 0,
                                      "write_1h": 0, "output": 0, "tool_uses": 0})
        for field, value in per.items():
            row[field] += value


def skip_seed(session, args):
    """The launcher placeholder: one line, exit 0, and no figure anywhere. Not a premise
    failure — nothing is broken — so a caller counting failed meter calls counts a skip."""
    if args.format == "json":
        print(json.dumps({"session": session, "skipped": "seed",
                          "spawn_record": args.spawn_record, "line": "seed (skipped)"},
                         indent=2, sort_keys=True))
    else:
        print("seed (skipped)")
    return 0


def main():
    ap = argparse.ArgumentParser(add_help=True, description="Meter a delegated run's head and lane usage.")
    ap.add_argument("--session", required=True,
                    help="head session id: the transcript stem, or a unique prefix of one")
    ap.add_argument("--vault", default=".", help="vault root; the project directory is derived from it")
    ap.add_argument("--project-dir", default=None, help="override the derived project directory")
    ap.add_argument("--start", default=None, help="ISO timestamp or a text marker in the invoking user message")
    ap.add_argument("--end", default=None, help="ISO timestamp or a text marker in the close-out reply")
    ap.add_argument("--lanes", nargs="+", default=["auto"], help="auto | none | one or more transcript globs")
    ap.add_argument("--expect-lanes", type=int, default=None, help="fail the premise unless exactly this many lanes are found")
    ap.add_argument("--baseline-output", type=int, default=None, help="prior head output, for the delta line")
    # The volatile lane home lives under the system temporary directory; resolving /tmp keeps
    # the default right on a platform that symlinks it, without a platform literal in source.
    ap.add_argument("--tmp-root", default=os.path.realpath("/tmp"), help="root of the volatile lane home")
    ap.add_argument("--format", choices=("text", "json"), default="text", help="output format")
    ap.add_argument("--per-agent", action="store_true", help="add the per-agent table to text output")
    ap.add_argument("--spawn-record", default=None, help="the run's spawn record: lane discovery by id, reason tally")
    ap.add_argument("--projects-root", default=os.path.join(os.path.expanduser("~"), ".claude", "projects"),
                    help="where a headless lane's own session transcript is searched for")
    ap.add_argument("--delegation", choices=REGIMES, default=None,
                    help="the run's delegation regime; with --delegation-src it overrides the session "
                         "state file and the Settings line")
    ap.add_argument("--delegation-src", choices=("head", "owner"), default=None,
                    help="who chose the regime: head (resolved under auto) or owner")
    ap.add_argument("--state-dir", default=os.path.join(os.path.expanduser("~"), ".cache", "aimyth", "role-style"),
                    help="where the head session's state file is read from (the anchor hook's directory)")
    ap.add_argument("--baseline", default=None, help="free text naming what this run is compared against")
    ap.add_argument("--prices", default=None, help="price table path (default: prices.json beside this script)")
    ap.add_argument("--routing", default=None,
                    help="routing record the picks tally takes its order from (default: routing.json beside this script)")
    args = ap.parse_args()

    if args.expect_lanes is not None and args.expect_lanes < 0:
        die("--expect-lanes cannot be negative: %d" % args.expect_lanes)
    if args.baseline_output is not None and args.baseline_output < 0:
        die("--baseline-output cannot be negative: %d" % args.baseline_output)
    if bool(args.delegation) != bool(args.delegation_src):
        die("--delegation and --delegation-src go together: --delegation single|multi "
            "--delegation-src head|owner")

    session = args.session.strip()
    if session.endswith(".jsonl"):
        session = session[:-len(".jsonl")]          # the transcript's file name is a fair thing to paste
    separators = [sep for sep in (os.sep, os.altsep) if sep]
    if not session or session in (".", "..") or any(sep in session for sep in separators):
        die("session must be a bare session id, not a path: %s" % args.session)

    # A launcher's placeholder session is skipped, not failed: it wrote no transcript, so the
    # check comes before the project directory and the transcript are looked for at all.
    seeds = seed_sessions(args.spawn_record) if args.spawn_record else set()
    if seeded(seeds, session):
        return skip_seed(session, args)

    project_dir = args.project_dir or derive_project_dir(args.vault)
    derivation = "given" if args.project_dir else "derived from vault %s" % os.path.abspath(os.path.expanduser(args.vault))
    if not os.path.isdir(project_dir):
        die("project directory not found (%s): %s%s"
            % (derivation, project_dir, sibling_hint(project_dir, session)))
    session_path = os.path.join(project_dir, session + ".jsonl")
    if not os.path.isfile(session_path):
        # Not a stem in this project directory: resolve it as a prefix, or fail naming what it
        # matched. Every line below then carries the resolved full id, never the prefix.
        session_path, session = resolve_short_session(
            project_dir, session, os.path.expanduser(args.projects_root))
        if seeded(seeds, session):
            return skip_seed(session, args)
    try:
        rows, stats = read_transcript(session_path, args.start, args.end)
    except OSError as exc:
        die("session transcript unreadable: %s" % exc)
    if not rows:
        die("session transcript holds no parseable records: %s (%d unparseable line(s))"
            % (session_path, stats["unparseable"]))

    si, ei, notes = resolve_window(rows, args.start, args.end)
    head = aggregate(rows[si:ei + 1])
    if head["calls"] == 0:
        die("no assistant records with usage in the window (records %d..%d%s)"
            % (si, ei, "" if not head["bad_usage"]
               else "; %s had unusable usage" % plural(head["bad_usage"], "record")))
    win_start, win_end = window_bounds(rows, si, ei)

    mode = "auto"
    patterns = []
    if len(args.lanes) == 1 and args.lanes[0] in ("auto", "none"):
        mode = args.lanes[0]
    else:
        mode, patterns = "globs", args.lanes

    record_lanes, record_paths, record_notes, tally = None, {}, None, None
    picks, picks_unavailable = None, None
    routing_path = args.routing or os.path.join(os.path.dirname(os.path.abspath(__file__)), "routing.json")
    record_selected, record_label, sessionless = None, None, 0
    unsplittable, unopened_resumes = 0, 0
    limit_stops, limit_stamps = [], []
    if args.spawn_record is not None:
        record_path = os.path.expanduser(args.spawn_record)
        if not os.path.isfile(record_path):
            die("spawn record not found: %s" % record_path)
        try:
            (record_lanes, record_unparseable, partitions, has_markers,
             unopened_resumes, limit_stops) = read_spawn_record(record_path)
        except OSError as exc:
            die("spawn record unreadable: %s (%s)" % (record_path, exc))
        if not record_lanes:
            # A record with no lane-open event cannot support the tally it was passed for.
            die("spawn record holds no lane-open event: %s" % record_path)
        # Only this session's partitions are expected here: a lane belongs to every partition
        # it ran under (its open and each resume), and a lane that ran under more than one
        # session is clipped to this session's spans below. Without a run marker the record
        # has one partition and it is this session's, which is how every record read before
        # run markers were understood.
        chosen = set()
        mine = set(i for i, part in enumerate(partitions) if session_matches(part["session"], session))
        for lane in record_lanes:
            part = partitions[lane["partition"]]
            here = [span for span in lane["spans"] if span["partition"] in mine]
            lane["selected"] = (not has_markers) or bool(here)
            lane["session"] = part["session"]
            lane["partitioned"] = has_markers
            lane["clip"] = None
            lane["unsplittable"] = False
            if not lane["selected"]:
                continue
            if has_markers:
                chosen.update(span["partition"] for span in here)
            else:
                chosen.add(lane["partition"])
            sessions = set(partitions[span["partition"]]["session"] for span in lane["spans"])
            if has_markers and len(sessions) > 1:
                lane["clip"] = span_clip(lane["spans"], mine)
                lane["unsplittable"] = lane["clip"] is None
        record_selected = [lane for lane in record_lanes if lane["selected"]]
        unsplittable = len([lane for lane in record_selected if lane["unsplittable"]])
        if has_markers:
            record_label = partition_label(partitions, sorted(chosen), session)
            # A marker that named no session cannot be assigned to anyone: its lanes are
            # neither claimed nor disowned, and the count says so on the line.
            sessionless = len(set(lane["partition"] for lane in record_lanes
                                  if partitions[lane["partition"]]["session"] is None))
        record_paths, record_notes = resolve_recorded_lanes(
            record_lanes, project_dir, session, os.path.expanduser(args.projects_root))
        record_notes["unparseable"] = record_unparseable
        record_notes["partitions"] = len(set(lane["partition"] for lane in record_lanes))
        record_notes["partitions_without_session"] = sessionless
        record_notes["unopened_resumes"] = unopened_resumes
        record_notes["shared_lanes"] = len([lane for lane in record_selected if lane["clip"]])
        record_notes["unsplittable_lanes"] = unsplittable
        record_notes["limit_stops"] = len(limit_stops)
        tally = reason_tally(record_selected)
        # The picks tally needs the routing order to place a value against its anchor; a record
        # it cannot read leaves the segment `unavailable` and nothing else on the line changes.
        order, picks_unavailable = load_routing_order(routing_path)
        if order is not None:
            picks = pick_tally(record_selected, order)
        # A limit stop can only have caused a rewrite of the session being metered when it fell
        # inside that session's window; one outside is another session's and is dropped here.
        limit_stamps = [stamp for stamp in limit_stops
                        if win_start is not None and win_end is not None
                        and win_start <= stamp <= win_end]
        record_notes["limit_stops_in_window"] = len(limit_stamps)
        if limit_stamps:
            # The head is re-aggregated now the record's limit stops are known. The first pass
            # above gates the empty-window premise, so the order premise failures print in is
            # unchanged; only the rewrite causes differ between the two passes.
            head = aggregate(rows[si:ei + 1], limit_stamps=limit_stamps)

    lanes = []
    scan = {"durable": 0, "volatile": 0, "recorded": 0, "candidates": 0, "unique": 0,
            "skipped": 0, "identity_duplicates": 0, "no_window_records": 0, "unsplittable": 0}
    lane_totals = {"output": 0, "flow": 0, "calls": 0, "models": {}}
    if mode == "none":
        if args.expect_lanes is not None:
            die("--expect-lanes %d cannot be checked with --lanes none" % args.expect_lanes)
    else:
        if win_start is None or win_end is None:
            die("the window carries no timestamps, so lane records cannot be selected")
        searched = lane_patterns(mode, patterns, project_dir, session, args.tmp_root)
        paths, scan = discover_lanes(mode, patterns, project_dir, session, args.tmp_root,
                                     sorted(path for path, lane in record_paths.items()
                                            if lane["selected"]))
        scan["unsplittable"] = 0
        if scan["unique"] == 0 and args.expect_lanes != 0:
            # A zero lane total off a scan that reached nothing would be a claim with no
            # control behind it, so it is a broken premise rather than a share of 100%.
            die("no readable lane transcript found (%d candidate(s), %d skipped) under: %s "
                "— use --lanes none to meter the head alone, or --expect-lanes 0 to assert there were none"
                % (scan["candidates"], scan["skipped"], " ".join(searched)))
        seen_ids = set()
        for path in paths:
            ident = lane_identity(path)
            if ident and ident in seen_ids:
                scan["identity_duplicates"] += 1
                continue
            if ident:
                seen_ids.add(ident)
            try:
                lane_rows, lane_stats = read_transcript(path)
            except OSError as exc:
                note("skipped unreadable lane transcript %s (%s)" % (path, exc))
                scan["skipped"] += 1
                continue
            in_window = [r for r in lane_rows if r["ts"] and win_start <= r["ts"] <= win_end]
            # A lane the spawn record named is labelled with that name; otherwise its own
            # transcript identity carries the label, exactly as before. A lane that ran under
            # another session too is clipped to this session's spans (split at the resume);
            # one that cannot be split is left unmetered here and flagged, never guessed.
            found = record_paths.get(path)
            outside = 0
            if found and found.get("selected") and found.get("unsplittable"):
                scan["unsplittable"] += 1
                continue
            if found and found.get("selected") and found.get("clip"):
                kept = [r for r in in_window if in_clip(r["ts"], found["clip"])]
                outside = len(in_window) - len(kept)
                in_window = kept
            # The lane's cache tier as the record has it (`1h` anywhere in the recorded value is
            # the 1-hour tier), else None so the lane's own transcript decides.
            recorded_tier = found.get("cache_tier") if found else None
            lane_tier = None
            if isinstance(recorded_tier, str) and recorded_tier:
                lane_tier = CACHE_TIER_1H_S if "1h" in recorded_tier else CACHE_TIER_5M_S
            totals = aggregate(in_window, tier_s=lane_tier, limit_stamps=limit_stamps)
            if totals["calls"] == 0:
                scan["no_window_records"] += 1
                continue
            totals["recorded_name"] = found["name"] if found else None
            totals["recorded_here"] = bool(found and found["selected"])
            totals["split"] = bool(found and found.get("clip"))
            totals["records_other_session"] = outside
            totals["name"] = totals["recorded_name"] or ident or os.path.basename(path)
            totals["path"] = path
            totals["unparseable"] = lane_stats["unparseable"]
            totals["tail_truncated"] = lane_stats["tail_truncated"]
            lanes.append(totals)
            lane_totals["output"] += totals["output"]
            lane_totals["flow"] += totals["flow"]
            lane_totals["calls"] += totals["calls"]
            for model, count in totals["models"].items():
                lane_totals["models"][model] = lane_totals["models"].get(model, 0) + count
        if args.expect_lanes is not None and len(lanes) != args.expect_lanes:
            die("expected %d lane transcripts in the window, found %d" % (args.expect_lanes, len(lanes)))

    share = None
    if mode != "none":
        denominator = head["output"] + lane_totals["output"]
        share = (head["output"] / denominator) if denominator else None
    share_text = "n/a" if share is None else "%.1f%%" % (share * 100)
    lanes_clause = ("not scanned" if mode == "none"
                    else "%s out (%s)" % (format(lane_totals["output"], ","), fmt_models(lane_totals["models"])))
    main_line = ("fable share: head %s out / %s flow / %s peak · lanes %s · share %s"
                 % (format(head["output"], ","), format(head["flow"], ","),
                    format(head["peak"], ","), lanes_clause, share_text))
    delta = None if args.baseline_output is None else head["output"] - args.baseline_output
    basis = ("not asserted: lanes not scanned (--lanes none)" if mode == "none"
             else "head output / (head + lane output)")

    # ---- billing -----------------------------------------------------------------------
    # Everything below is computed before anything is printed, so a billing premise failure
    # takes the same shape in both formats: the share line, the unbilled line, exit 2.
    if args.delegation:
        run_delegation, delegation_src, delegation_from = (args.delegation, args.delegation_src,
                                                           "--delegation")
    else:
        run_delegation, delegation_src, delegation_from = read_state_delegation(args.state_dir, session)
        if run_delegation is None:
            # The state file yielded nothing: fall through to the Settings line, and say so,
            # since an unstated regime after a cleared run is the likeliest wrong derivation.
            state_note = delegation_from
            run_delegation, delegation_src, delegation_from = read_settings_delegation(args.vault)
            delegation_from = "%s (%s)" % (delegation_from, state_note)
    delegation_clause = ("%s (%s)" % (run_delegation, delegation_src) if delegation_src
                         else "unstated")
    baseline_label = args.baseline if args.baseline else "none"
    prices_path = args.prices or default_prices_path()
    table, unbilled = load_prices(prices_path)
    control_note = None
    if table is not None:
        control_ok, control_note = price_control(table)
        if not control_ok:
            unbilled = control_note

    agents, unknown_models, unpriced = [], set(), {}
    head_usd = lane_usd = rewrite_usd = 0.0
    rewrites = 0
    causes = {cause: 0 for cause in CAUSE_ORDER}
    per_model = {}
    untiered = head["untiered"]
    if table is not None and unbilled is None:
        for kind, name, totals in ([("head", "head", head)]
                                   + [("lane", lane["name"], lane) for lane in lanes]):
            usd, rew_usd, unknown = price_agent(totals, table)
            unknown_models |= unknown
            rewrites += totals["rewrites"]
            merge_causes(causes, totals["rewrite_causes"])
            rewrite_usd += rew_usd
            merge_per_model(per_model, totals)
            if kind == "lane":
                lane_usd += usd
                untiered += totals["untiered"]
            else:
                head_usd += usd
            agents.append({"label": name, "kind": kind, "models": totals["models"],
                           "calls": totals["calls"], "first_call_prefix": totals["first_prefix"],
                           "peak": totals["peak"], "output": totals["output"],
                           "tool_uses": totals["tool_uses"], "rewrites": totals["rewrites"],
                           "rewrite_causes": dict(totals["rewrite_causes"]),
                           "cache_tier_seconds": totals["cache_tier_s"],
                           "cache_tier_source": totals["cache_tier_src"],
                           "usd": usd})
        if unknown_models:
            # 2026-09-04: price what matches and NAME the rest. A session whose every model is
            # unknown stays unbilled (never a silent zero); a session with one priced family and
            # one stray id (a `<synthetic>` record from a denied tool call, 2026-09-04) is priced
            # with the stray ids and their call counts on the billed and control lines.
            if any(m not in unknown_models for m in per_model):
                unpriced = {m: per_model[m]["calls"] for m in sorted(unknown_models) if m in per_model}
                unpriced.update({m: 0 for m in sorted(unknown_models) if m not in per_model})
            else:
                unbilled = ("model id matches no price family in %s: %s"
                            % (prices_path, ", ".join(sorted(unknown_models))))

    lane_calls = sum(lane["calls"] for lane in lanes)
    lane_tools = sum(lane["tool_uses"] for lane in lanes)
    recorded_total = None if record_lanes is None else len(record_selected)
    matched_names = set(lane.get("recorded_name") for lane in lanes
                        if lane.get("recorded_here")) - {None}
    metered_recorded = None if record_lanes is None else len(matched_names)
    other_session_metered = (0 if record_lanes is None else
                             len([lane for lane in lanes
                                  if lane.get("recorded_name") and not lane.get("recorded_here")]))
    unrecorded_metered = (0 if record_lanes is None
                          else len([lane for lane in lanes if not lane.get("recorded_name")]))
    if mode == "none":
        metered_clause = "metered n/a of %s %s" % (
            "n/a" if recorded_total is None else recorded_total,
            record_label or "recorded")
        mismatch = None
    else:
        metered_clause = "metered %s of %s %s" % (
            len(lanes) if recorded_total is None else metered_recorded,
            "n/a" if recorded_total is None else recorded_total,
            record_label or "recorded")
        mismatch = None if recorded_total is None else (metered_recorded != recorded_total
                                                        or bool(unrecorded_metered)
                                                        or bool(other_session_metered)
                                                        or bool(sessionless)
                                                        or bool(unsplittable)
                                                        or bool(unopened_resumes))
        if mismatch:
            flags = []
            if metered_recorded != recorded_total:
                flags.append("%d recorded lane(s) unmatched" % (recorded_total - metered_recorded))
            if other_session_metered:
                flags.append("%d metered lane(s) from another session of this run"
                             % other_session_metered)
            if sessionless:
                flags.append("%d partition(s) with no session field" % sessionless)
            if unsplittable:
                flags.append("%d shared lane(s) unsplittable (no timestamp on a lane-open or "
                             "lane-resumed), left unmetered" % unsplittable)
            if unopened_resumes:
                flags.append("%d lane-resumed event(s) naming a lane the record never opened"
                             % unopened_resumes)
            if unrecorded_metered:
                flags.append("%d metered lane(s) not in the record" % unrecorded_metered)
            # A flag, never a premise failure: the figures printed are real and the exit code
            # stays 0; an unmetered lane understates the bill rather than corrupting it.
            metered_clause += " [MISMATCH: %s]" % "; ".join(flags)

    billed_line = None
    model_lines = []
    if unbilled is None:
        session_usd = head_usd + (lane_usd if mode != "none" else 0.0)
        billed_line = ("billed (list, prices %s): head $%.2f · lanes %s · session $%.2f · "
                       "rewrites %d ($%.2f) · rewrite causes %s · "
                       "tool uses/call head %s lanes %s · delegation %s · "
                       "baseline %s · lanes %s (reasons: %s) · picks: %s · %s"
                       % (table["prices_date"], head_usd,
                          "not scanned" if mode == "none" else "$%.2f" % lane_usd,
                          session_usd, rewrites, rewrite_usd, fmt_causes(causes),
                          fmt_ratio(head["tool_uses"], head["calls"]),
                          "n/a" if mode == "none" else fmt_ratio(lane_tools, lane_calls),
                          delegation_clause, baseline_label,
                          "not scanned" if mode == "none" else len(lanes),
                          fmt_tally(tally), fmt_picks(picks, picks_unavailable), metered_clause))
        if unpriced:
            billed_line += " · unpriced %s" % ", ".join(
                "%s (%d call%s)" % (m, n, "" if n == 1 else "s") for m, n in unpriced.items())
        for model in sorted(per_model):
            row = per_model[model]
            family = family_for(model, table)
            if family is None:
                model_lines.append("  %s: unpriced (%d calls; no price family)" % (model, row["calls"]))
                continue
            usd = price_tokens(table["families"][family], row["input"], row["cache_read"],
                               row["write_5m"], row["write_1h"], row["output"])
            model_lines.append(
                "  %s (%s): %s · in %s · read %s · write 5m %s / 1h %s · out %s · tools %d · $%.2f"
                % (model, family, plural(row["calls"], "call"), format(row["input"], ","),
                   format(row["cache_read"], ","), format(row["write_5m"], ","),
                   format(row["write_1h"], ","), format(row["output"], ","),
                   row["tool_uses"], usd))

    if args.format == "json":
        if unbilled is not None:
            # The metered figures are sound and the billing premise is not: print the share
            # line the prices were never needed for, then the unbilled line, and exit 2. No
            # payload, so a consumer that checks the exit code can never parse a half-priced
            # object.
            print(main_line)
            print("billed: unbilled (%s)" % unbilled)
            return 2
        payload = {
            "session": session,
            "session_given": args.session.strip(),      # the prefix, where one was passed
            "project_dir": project_dir,
            "project_dir_source": derivation,
            "window": {"start_index": si, "end_index": ei,
                       "start": win_start.isoformat() if win_start else None,
                       "end": win_end.isoformat() if win_end else None,
                       "start_match": notes["start"], "end_match": notes["end"],
                       "start_marker_matches": notes["start_matches"],
                       "end_marker_matches": notes["end_matches"]},
            "head": {"calls": head["calls"], "records": head["records"], "output": head["output"],
                     "flow": head["flow"], "peak": head["peak"], "models": head["models"],
                     "efforts": head["efforts"], "unusable_usage_records": head["bad_usage"],
                     "partial_usage_calls": head["partial_usage"]},
            "lanes_mode": mode,
            "lane_scan": scan,
            "lanes": [{"name": l["name"], "path": l["path"], "models": l["models"],
                       "calls": l["calls"], "records": l["records"], "output": l["output"],
                       "flow": l["flow"], "peak": l["peak"],
                       "efforts": l["efforts"], "distinct_efforts": len(l["efforts"]),
                       "unusable_usage_records": l["bad_usage"],
                       "unparseable_lines": l["unparseable"],
                       "tail_truncated": l["tail_truncated"],
                       "split_at_resume": l.get("split", False),
                       "records_of_another_session": l.get("records_other_session", 0)}
                      for l in lanes],
            "lane_totals": {"lanes": len(lanes), "output": lane_totals["output"],
                            "flow": lane_totals["flow"], "calls": lane_totals["calls"],
                            "models": lane_totals["models"]},
            "share": share,
            "share_basis": basis,
            "baseline_output": args.baseline_output,
            "baseline_delta": delta,
            "unparseable_session_lines": stats["unparseable"],
            "session_tail_truncated": stats["tail_truncated"],
            "line": main_line,
            "billed": {
                "unpriced": [{"model": m, "calls": n} for m, n in unpriced.items()],
                "prices_date": table["prices_date"],
                "prices_path": prices_path,
                "prices_source": table.get("source"),
                "head_usd": round(head_usd, 6),
                "lanes_usd": None if mode == "none" else round(lane_usd, 6),
                "session_usd": round(head_usd + (0.0 if mode == "none" else lane_usd), 6),
                "rewrites": rewrites,
                "rewrites_usd": round(rewrite_usd, 6),
                "rewrite_fraction": REWRITE_FRACTION,
                "rewrite_causes": causes,
                "cache_tier_5m_seconds": CACHE_TIER_5M_S,
                "cache_tier_1h_seconds": CACHE_TIER_1H_S,
                "limit_stops_in_window": len(limit_stamps),
                "tool_uses_head": head["tool_uses"],
                "tool_uses_lanes": lane_tools,
                "tool_uses_per_call_head": (None if not head["calls"]
                                            else head["tool_uses"] / head["calls"]),
                "tool_uses_per_call_lanes": (None if mode == "none" or not lane_calls
                                             else lane_tools / lane_calls),
                "delegation": run_delegation,
                "delegation_src": delegation_src,
                "delegation_from": delegation_from,
                "baseline": baseline_label,
                "lanes_metered": None if mode == "none" else len(lanes),
                "lanes_recorded": recorded_total,
                "recorded_lanes_metered": metered_recorded,
                "recorded_partition": record_label,
                "recorded_lanes_split_at_resume": len([l for l in lanes if l.get("split")]),
                "recorded_lanes_unsplittable": unsplittable,
                "metered_lanes_other_session": other_session_metered,
                "metered_lanes_unrecorded": unrecorded_metered,
                "lane_count_mismatch": mismatch,
                "reason_tally": tally,
                "picks": picks_payload(picks),
                "picks_unavailable": picks_unavailable,
                "picks_routing": routing_path,
                "spawn_record": args.spawn_record,
                "spawn_record_resolution": record_notes,
                "untiered_write_records": untiered,
                "per_model": {model: dict(row, usd=(None if family_for(model, table) is None else round(price_tokens(
                table["families"][family_for(model, table)], row["input"], row["cache_read"],
                row["write_5m"], row["write_1h"], row["output"]), 6)))
                          for model, row in per_model.items()},
                "control": control_note,
                "line": billed_line,
            },
            "per_agent": [dict(agent, usd=round(agent["usd"], 6)) for agent in agents],
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    print("fable-share: session %s · project-dir %s (%s) · tmp-root %s · lanes %s · format %s"
          % (session, project_dir, derivation, args.tmp_root,
             mode if mode != "globs" else " ".join(patterns), args.format))
    torn = "" if not stats["unparseable"] else (
        " · %s unparseable%s" % (plural(stats["unparseable"], "session line"),
                                 " (the final one: a transcript read mid-write looks like this)"
                                 if stats["tail_truncated"] else ""))
    print("window: records %d..%d of %d · %s -> %s · start = %s · end = %s%s"
          % (si, ei, len(rows),
             win_start.isoformat() if win_start else "no timestamp",
             win_end.isoformat() if win_end else "no timestamp",
             notes["start"], notes["end"], torn))
    print("head: %s (%s) · models %s · efforts %s   (nonzero counts = probe ran)"
          % (plural(head["calls"], "call"), plural(head["records"], "assistant record"),
             fmt_models(head["models"]), fmt_models(head["efforts"])))
    if data_clause(head):
        print("head data: %s" % data_clause(head))
    if mode == "none":
        print("lanes: not scanned (--lanes none), so the share is not asserted")
    else:
        expected = ("" if args.expect_lanes is None
                    else " (matches --expect-lanes %d)" % args.expect_lanes)
        print("lanes: %d in window%s · %s" % (len(lanes), expected, scan_clause(scan)))
        for lane in lanes:
            extra = data_clause(lane)
            if lane["unparseable"]:
                extra = " · ".join(filter(None, [
                    extra, "%s unparseable%s" % (plural(lane["unparseable"], "line"),
                                                 " (the final one)" if lane["tail_truncated"] else "")]))
            if lane.get("split"):
                extra = " · ".join(filter(None, [
                    extra, "split at the resume: %s of another head's span excluded"
                    % plural(lane["records_other_session"], "record")]))
            print("  lane %s: models %s · %s (%s) · %s out · efforts %d (%s)%s"
                  % (lane["name"], fmt_models(lane["models"]), plural(lane["calls"], "call"),
                     plural(lane["records"], "record"),
                     format(lane["output"], ","), len(lane["efforts"]), fmt_models(lane["efforts"]),
                     "" if not extra else " · " + extra))
    print(main_line)
    if unbilled is not None:
        print("billed: unbilled (%s)" % unbilled)
        return 2
    print(billed_line)
    for text in model_lines:
        print(text)
    print("billed control: prices from %s · %s · delegation from %s · %s · picks order from %s"
          % (prices_path, control_note, delegation_from,
             "every cache write tiered from the transcript" if not untiered
             else "%s with no cache_creation tier, counted at the 5-minute rate"
                  % plural(untiered, "call"), routing_path))
    if args.per_agent:
        width = max([len(agent["label"]) for agent in agents] + [5])
        print("per-agent (label · model(s) · calls · first-call prefix · peak context · "
              "output · tool uses · rewrites by cause · list $):")
        for agent in agents:
            print("  %-*s · %s · %s · prefix %s · peak %s · out %s · tools %d · "
                  "rewrites %d (%s) · $%.2f"
                  % (width, agent["label"], fmt_models(agent["models"]),
                     plural(agent["calls"], "call"),
                     format(agent["first_call_prefix"], ","), format(agent["peak"], ","),
                     format(agent["output"], ","), agent["tool_uses"], agent["rewrites"],
                     fmt_causes(agent["rewrite_causes"]), agent["usd"]))
    if delta is not None:
        print("head output delta vs baseline: %s" % format(delta, "+,"))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:                        # a belt: no traceback may pass for a metered run
        traceback.print_exc(file=sys.stderr)
        die("unexpected error, see stderr: %s: %s" % (type(exc).__name__, exc))
