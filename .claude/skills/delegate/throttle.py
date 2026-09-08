#!/usr/bin/env python3
"""throttle.py — the subagent routing throttle: one record, four verbs.

The throttle is the owner's constraint knob for delegated work. It is vault-global,
never per session, because the definitions it rewrites are shared by every session and
outlive any one of them. Its record is the `throttle:` line in CUSTOMISATION `## Settings`;
its ranges live in `routing.json` beside this file; its effect is the `model:` and
`effort:` lines of the per-role definitions in `.claude/agents/`.

  show   the active throttle, what it resolves to per role, the drift status, and the
         head's own recommended tier (a recommendation only — the head's model and
         effort are the owner's own client settings, not this knob).
  check  regenerate the expected `model:`/`effort:` values and diff them against disk;
         also flag any definition whose `description:` prose names a current tier rather
         than its admitted range, since `set` never rewrites prose and a stale tier in a
         description misroutes whoever reads it. A lint leg and the publish gate run this;
         `--require NAME` adds a finding unless NAME is the active throttle (a gate pinned
         to `default` before 2026-09-08 pins `auto`, the default preset, from then on).
  set    write the Settings line and every routed definition in one pass.
  resolve  (schema 2 only) print one class's whole resolved row — model, effort, tools,
         grants, writes, skills, mcp, cache — under a throttle. This is the spawn
         wrapper's entry point: the wrapper composes `--model`, `--effort`, `--tools`,
         `--add-dir` and the lane home's skill slices from this output, so the record
         stays the one home for what a lane may use.

Two record schemas, both read (the vault never breaks between a delivery and its install)

  schema 1 (no `schema` key, or `schema: 1`) — `roles`, each a model triple
  (floor · default · ceiling) and an effort pair (floor · ceiling).
  schema 2 (`schema: 2`) — `classes`, each an option SET with a marked default per axis,
  plus grants, writes, tools, skills, mcp, cache, gate and dated (design:
  wiki/developments/thin-lanes-design.md, "The class table"). Strength on both axes is
  read from `order` by index, never from a list's position, so an unsorted options list
  still resolves correctly.

Resolution rule (design: wiki/developments/throttle-routing-design.md, "The selection rule";
the `auto` row: the owner's ruling of 2026-09-07 17:0x, built 2026-09-08)

  throttle      model (v1 · v2)               effort (v1 · v2)
  auto          role default · row default    ceiling · row default    (the anchors)
  top           ceiling · strongest option    ceiling · strongest option
  default       role default · row default    ceiling · row default
  cheap         floor · weakest option        ceiling · strongest option
  fast          role default · row default    floor · weakest option
  cheap-fast    floor · weakest option        floor · weakest option

  `auto` is the default preset: the Settings default from 2026-09-08 once the owner runs
  `set auto`, and what a missing Settings line reads as. Under it the head picks model and
  effort PER CALL within the row's options (`resolve` prints the options beside the anchors,
  and lane.py records every departure with its `--choice-reason`); the row default is the
  anchor and strong reference, never a pin, and `set auto` writes the anchors into the
  definitions so that an in-session spawn, which reads its definition, starts from them. The
  other five presets are hand-set overrides: `set <name>` writes their resolution once and
  nothing re-resolves it. On a schema-1 record `auto` resolves exactly as `default` does
  (frozen legacy).

  Effort is the ceiling unless the owner names a constraint (the written default; from
  2026-09-06 the head may pick a lower in-range effort per call with a recorded reason, the
  delegate skill §2 rule), and setting a below-default
  throttle IS the owner naming one. Under `default` and `fast` the head may still choose
  a different in-range model per call; the definition holds the default so that
  `set default` can restore it after `top` has written the ceilings.

  One axis moves between the schemas: under `default`, v1 writes the effort CEILING (no
  discretion, C5 F1, 2026-09-02) while v2 writes the row's marked default. The class table
  of 2026-09-04 marks an effort default per class and amends the owner's "max on every
  lane" ruling for closed-task classes, each downgrade gated once and metered every run
  (a dated fact: the ruling of 2026-09-07 17:0x supersedes "class default, gated once" for
  the closed-task classes — builder, verifier, wiki-compile, memory-hunter, planner — whose
  effort default is the anchor `xhigh`, a reference and not a pin, so a per-call pick either
  way, `max` for design- or reasoning-heavy work or `high` for a closed one-leg task, is
  recorded on the lane-open event with its reason and never gated; critic and reflector keep
  `max`, the effort being the product, and the gate-judge stays fixed); `cheap` keeps the
  ceiling effort because the constraint the owner named there is spend, which the model
  axis carries.

Where the ranges come from (a deciding number carries its derivation)

  The critic, planner, verifier, wiki-compile and memory-hunter ranges carry over from
  the delegate skill's section 2 routing table, set by judgement at its adoption on
  2026-08-27 and unmeasured. The reflector and builder ranges are set by judgement on
  2026-09-02 under the owner's routing mandate of that date. `gate-judge` is a single
  value on both axes: a parity gate measures the routed step's executor at its default
  tier, so a gate run at any other tier measures nothing the gate exists to measure.
  Every model ceiling except `gate-judge`'s is fable, per the owner's ruling of
  2026-09-02.

Guards, each keyed on a premise that can fail

  A missing, unreadable or invalid `routing.json`, a v1 routing record that is not monotone
  under its own order lists, a v2 row whose default is outside its own options or whose
  option is outside `order`, a v2 row missing a required field, a `schema` value other than
  1 or 2, an unknown class passed to `resolve`, `resolve` against a v1 record, an unknown
  throttle name, a definition whose frontmatter cannot be parsed, or a missing
  `.claude/agents/` directory all print one
  `PROBE FAILED: <reason>` line and exit 2 — never "clean". The record is read from
  `<root>` and from nowhere else: an earlier draft fell back to this script's own sibling
  copy when the root had none, and a fixture whose record had been deleted then reported
  "clean" against a foreign record (measured 2026-09-02). A MISSING Settings line is not
  a failure: it resolves to `auto` (the default preset from 2026-09-08; `default` until
  then) and says so once, because a fresh or pulled template vault has never run `set` and
  CUSTOMISATION is never published. `set` validates the
  whole record and builds every new file in memory before it writes anything, so a bad
  record changes no file.

  What this script cannot check: whether a model or effort name the record admits is one
  the harness will actually honour. Headless spawns ignore the DEFINITION's effort and apply --effort (probe 2026-09-04), and the available
  levels depend on the model, so the first in-session spawn after a switch is that check,
  read from the lane transcript. The record's own order lists are therefore the enum, and
  no model name is hard-coded here: a hard-coded list would silently exclude the next
  model released.

  `check` carries its own positive control: every run re-runs the comparator over two
  synthetic definitions, one correct and one carrying two planted drifts, and a miss is a
  PROBE FAILED rather than a clean report. A zero-findings run is a claim; this is its
  evidence.

  Two findings exist only under schema 2, where the record carries a tool list to compare
  against. SKILL-AVAILABLE: a definition whose `tools:` allowlist names `Skill`, or which
  has no allowlist and no `Skill` in `disallowedTools`, leaves a lane able to load whole
  skills into a thin context (levers L1, 2026-09-04) — keyed on that property, never on a
  definition's name. TOOLS-WIDER: a definition whose `tools:` allowlist names a tool the
  class row does not grant. A definition carrying only `disallowedTools:` is never
  TOOLS-WIDER: the spawn's `--tools` flag is the outer bound, so a denylist can only
  narrow what the row grants, and a narrower definition is fine — the head grants the
  extras per call.

`show`, `check` and `resolve` are stdout-only: they never create, modify, move or delete a
file. `set` writes, and only to `CUSTOMISATION.md` and the routed definitions under
`.claude/agents/`, through the single write helper below.

Usage
  python3 throttle.py show  [--root DIR]
  python3 throttle.py check [--root DIR] [--require NAME]
  python3 throttle.py set NAME [--root DIR] [--dry-run]
  python3 throttle.py resolve --class CLASS [--throttle NAME] [--json] [--root DIR]
  exit 0 = clean · exit 1 = findings (a drift, an unrouted or missing definition, a
  description naming a current tier, a failed --require) · exit 2 = broken premise
"""
import argparse
import json
import os
import re
import sys

THROTTLES = ("auto", "top", "default", "cheap", "fast", "cheap-fast")   # `auto` first: the default preset (2026-09-08)
# schema 1 · throttle -> (index into the model triple, index into the effort pair)
#   model triple reads floor · default · ceiling ; effort pair reads floor · ceiling
#   `auto` is frozen legacy on a v1 record: it resolves exactly as `default` does.
SELECT = {"auto": (1, 1), "top": (2, 1), "default": (1, 1), "cheap": (0, 1),
          "fast": (1, 0), "cheap-fast": (0, 0)}
# schema 2 · throttle -> (model picker, effort picker) over the row's option set. The
# pickers are names, not indices: an option set has no fixed width, and strength comes
# from `order` (see pick_option below). Under `auto` both pickers read the row default:
# the ANCHOR the head picks around per call (owner ruling 2026-09-07 17:0x).
SELECT_V2 = {"auto": ("default", "default"),
             "top": ("strongest", "strongest"), "default": ("default", "default"),
             "cheap": ("weakest", "strongest"), "fast": ("default", "weakest"),
             "cheap-fast": ("weakest", "weakest")}
# The fields every schema-2 row must carry. Absence is a broken premise, not a default:
# a row silently missing `tools` would spawn a lane with whatever the harness offers.
V2_FIELDS = ("model", "effort", "grants", "writes", "tools", "skills", "mcp", "cache",
             "gate", "dated")
# The head's own tier under each throttle. A recommendation the head carries in its
# hand-off line; the head's real model and effort are the owner's client settings.
HEAD_LINE = {"auto": "head: fable · max",
             "top": "head: fable · max",
             "default": "head: fable · max",
             "cheap": "head: opus · max recommended",
             "cheap-fast": "head: opus · max recommended",
             "fast": "head: fable · high recommended"}

# The Settings-line regex is the anchor hook's `_defaults()` family, unchanged: one
# bullet, a bold key, the value token. Trailing prose after the value is ignored, so the
# line can carry its own gloss.
SETTINGS_RE = re.compile(r"(?mi)^-\s*\*\*throttle\*\*:\s*([A-Za-z0-9_-]+)")
SETTINGS_LINE_RE = re.compile(r"(?mi)^-\s*\*\*throttle\*\*:.*$")
PREREPORT_RE = re.compile(r"(?mi)^-\s*\*\*pre-report\*\*:.*$")
SETTINGS_HEAD_RE = re.compile(r"(?m)^##\s+Settings\s*$")
NEXT_HEAD_RE = re.compile(r"(?m)^##\s+")
BULLET_RE = re.compile(r"(?m)^-\s")
SETTINGS_LINE = ('- **throttle**: %s — subagent routing throttle: auto (the default: model and effort '
                 'picked per call within the class ranges, the row anchor the reference, each '
                 'departure recorded with its reason) · top · default · cheap · fast · cheap-fast '
                 '(hand-set overrides, never re-resolved); semantics in the delegate skill §2 (say '
                 '"set throttle to X"; the head runs throttle.py set)')

CUSTOM_REL = "CUSTOMISATION.md"
AGENTS_REL = os.path.join(".claude", "agents")
ROUTING_REL = os.path.join(".claude", "skills", "delegate", "routing.json")
ROLE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
# A description that names a CURRENT tier goes stale the moment a throttle moves it, and a
# lane brief quoting it would carry the wrong routing. `set` never edits prose, so this is a
# finding for a human to reword — the durable form states the admitted RANGE and says the
# active throttle sets the current values. Pinned form (design v1.4, 2026-09-02).
DESC_TIER_RE = re.compile(r"·\s*(low|medium|high|xhigh|max)\b")  # any tier after a middle dot: "opus · max effort", "opus · max;" (reflector wording, live miss 2026-09-02)
FIELD_RE = {k: re.compile(r"^(?P<key>%s:)(?P<sp>[ \t]*)(?P<val>[^\r\n]*?)(?P<eol>\r?\n?)$" % k)
            for k in ("model", "effort")}


class Probe(Exception):
    """A broken premise: print one PROBE FAILED line and exit 2, never a clean report."""


def _fail(reason):
    raise Probe(reason)


# --------------------------------------------------------------- the record ----------

def load_routing(root):
    """The routing record under `root`, validated before it is returned. One path only:
    a fallback to another copy would let a fixture be checked against a foreign record
    and report clean (measured 2026-09-02)."""
    path = os.path.join(root, ROUTING_REL)
    if not os.path.exists(path):
        _fail("no routing record at %s (wrong --root?)" % ROUTING_REL)
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        _fail("%s unreadable (%s)" % (ROUTING_REL, exc.strerror or exc.__class__.__name__))
    try:
        rec = json.loads(raw)
    except ValueError as exc:
        _fail("%s is not valid JSON (%s)" % (ROUTING_REL, exc))
    validate_routing(rec, ROUTING_REL)
    return rec


def schema_of(rec, rel):
    """1 or 2. An absent key is 1: the shipped v1 record carries none, and a template
    vault pulled before the v2 install must keep working."""
    val = rec.get("schema", 1)
    if val not in (1, 2) or isinstance(val, bool):
        _fail("%s: `schema` is %r — this script reads 1 (roles) and 2 (classes) only"
              % (rel, val))
    return val


def validate_routing(rec, rel):
    """Shape, membership and monotonicity. Anything off here is a broken premise: a
    record whose floor sits above its ceiling would silently route outside its range."""
    if not isinstance(rec, dict):
        _fail("%s: top level is not an object" % rel)
    order = rec.get("order")
    if not isinstance(order, dict):
        _fail("%s: no `order` object" % rel)
    for axis in ("model", "effort"):
        vals = order.get(axis)
        if not isinstance(vals, list) or not vals:
            _fail("%s: `order.%s` is not a non-empty list" % (rel, axis))
        if not all(isinstance(v, str) and v for v in vals):
            _fail("%s: `order.%s` holds a non-string value" % (rel, axis))
        if len(set(vals)) != len(vals):
            _fail("%s: `order.%s` repeats a value" % (rel, axis))
    if schema_of(rec, rel) == 2:
        return validate_v2(rec, rel)
    roles = rec.get("roles")
    if not isinstance(roles, dict) or not roles:
        _fail("%s: no `roles` object, or it is empty" % rel)
    for role, spec in roles.items():
        if not ROLE_NAME_RE.match(role or ""):
            _fail("%s: role name %r is not a plain definition stem" % (rel, role))
        if not isinstance(spec, dict):
            _fail("%s: role `%s` is not an object" % (rel, role))
        for axis, width in (("model", 3), ("effort", 2)):
            vals = spec.get(axis)
            if not isinstance(vals, list) or len(vals) != width:
                _fail("%s: role `%s` needs a %d-value `%s` list" % (rel, role, width, axis))
            for v in vals:
                if v not in order[axis]:
                    _fail("%s: role `%s` %s value %r is not in `order.%s`"
                          % (rel, role, axis, v, axis))
            idx = [order[axis].index(v) for v in vals]
            if idx != sorted(idx):
                _fail("%s: role `%s` %s range is not floor%sceiling under `order.%s` (%s)"
                      % (rel, role, axis, " ≤ default ≤ " if width == 3 else " ≤ ",
                         axis, " ".join(vals)))


def validate_v2(rec, rel):
    """One class row per lane class: option sets with a marked default, plus the grant,
    tool, skill, mcp, cache and provenance fields the wrapper spawns from."""
    order = rec["order"]
    classes = rec.get("classes")
    if not isinstance(classes, dict) or not classes:
        _fail("%s: no `classes` object, or it is empty" % rel)
    for cls, spec in classes.items():
        if not ROLE_NAME_RE.match(cls or ""):
            _fail("%s: class name %r is not a plain definition stem" % (rel, cls))
        if not isinstance(spec, dict):
            _fail("%s: class `%s` is not an object" % (rel, cls))
        for field in V2_FIELDS:
            if field not in spec:
                _fail("%s: class `%s` is missing `%s`" % (rel, cls, field))
        for axis in ("model", "effort"):
            ax = spec[axis]
            if not isinstance(ax, dict) or "options" not in ax or "default" not in ax:
                _fail("%s: class `%s` `%s` needs an `options` list and a `default`"
                      % (rel, cls, axis))
            opts = ax["options"]
            if not isinstance(opts, list) or not opts:
                _fail("%s: class `%s` `%s.options` is not a non-empty list"
                      % (rel, cls, axis))
            for v in opts:
                if v not in order[axis]:
                    _fail("%s: class `%s` %s option %r is not in `order.%s`"
                          % (rel, cls, axis, v, axis))
            if ax["default"] not in opts:
                _fail("%s: class `%s` %s default %r is not one of its options (%s)"
                      % (rel, cls, axis, ax["default"], " ".join(map(str, opts))))
        for field, keys in (("grants", ("default", "extras")),
                            ("skills", ("default", "extras")),
                            ("mcp", ("default", "grantable"))):
            val = spec[field]
            if not isinstance(val, dict) or any(k not in val for k in keys):
                _fail("%s: class `%s` `%s` needs %s"
                      % (rel, cls, field, " and ".join("`%s`" % k for k in keys)))
            for k in keys:
                if not isinstance(val[k], list):
                    _fail("%s: class `%s` `%s.%s` is not a list" % (rel, cls, field, k))
        for field in ("writes", "tools"):
            if not isinstance(spec[field], list):
                _fail("%s: class `%s` `%s` is not a list" % (rel, cls, field))
        if not spec["tools"]:
            _fail("%s: class `%s` `tools` is empty — a lane with no tools cannot work"
                  % (rel, cls))
        for field in ("cache", "gate", "dated"):
            if not isinstance(spec[field], str) or not spec[field].strip():
                _fail("%s: class `%s` `%s` is not a non-empty string" % (rel, cls, field))


def rows(rec):
    """The per-lane rows, whichever schema wrote them. `roles` and `classes` name the same
    thing: one row per definition stem."""
    return rec["classes"] if rec.get("schema") == 2 else rec["roles"]


def pick_option(order_list, opts, default, how):
    """One option out of a set. Strength is the `order` index, never the list position, so
    a row whose options are written out of order still resolves to the same values."""
    if how == "default":
        return default
    ranked = sorted(opts, key=order_list.index)
    return ranked[-1] if how == "strongest" else ranked[0]


def resolve(rec, name):
    """role/class -> (model, effort) under one throttle."""
    if name not in SELECT:
        _fail("unknown throttle %r (known: %s)" % (name, ", ".join(THROTTLES)))
    if rec.get("schema") == 2:
        mh, eh = SELECT_V2[name]
        out = {}
        for cls, spec in rec["classes"].items():
            out[cls] = tuple(
                pick_option(rec["order"][axis], spec[axis]["options"], spec[axis]["default"], how)
                for axis, how in (("model", mh), ("effort", eh)))
        return out
    mi, ei = SELECT[name]
    return {role: (spec["model"][mi], spec["effort"][ei])
            for role, spec in rec["roles"].items()}


def resolve_row(rec, cls, name):
    """One class's whole resolved row under one throttle — the wrapper's spawn inputs.
    Schema 2 only: a v1 record carries no grants, tools, skills or cache, so resolving one
    from it would mean inventing the fence."""
    if rec.get("schema") != 2:
        _fail("`resolve` needs a schema-2 record; this one is schema %d, which carries no "
              "grants, tools, skills or cache" % rec.get("schema", 1))
    if name not in SELECT:
        _fail("unknown throttle %r (known: %s)" % (name, ", ".join(THROTTLES)))
    spec = rec["classes"].get(cls)
    if spec is None:
        _fail("unknown class %r (known: %s)" % (cls, ", ".join(sorted(rec["classes"]))))
    model, effort = resolve(rec, name)[cls]
    # Where the two values come from, in the words lane.py records on the lane-open line: under
    # `auto` they are the row's ANCHORS, which the head picks around per call within the option
    # lists returned beside them; under a hand-set preset they are that preset's own resolution.
    source = "anchor" if name == "auto" else "throttle %s" % name
    return {"class": cls, "throttle": name, "model": model, "effort": effort,
            "model_src": source, "effort_src": source,
            "model_options": list(spec["model"]["options"]),
            "effort_options": list(spec["effort"]["options"]),
            "tools": list(spec["tools"]),
            "grants": list(spec["grants"]["default"]),
            "grants_extras": list(spec["grants"]["extras"]),
            "writes": list(spec["writes"]),
            "skills": list(spec["skills"]["default"]),
            "skills_extras": list(spec["skills"]["extras"]),
            "mcp": list(spec["mcp"]["default"]),
            "mcp_grantable": list(spec["mcp"]["grantable"]),
            "cache": spec["cache"], "gate": spec["gate"], "dated": spec["dated"]}


# ------------------------------------------------------- the Settings record ----------

def active_throttle(root):
    """(name, reason) — reason is None when the line was read, else why it was not.
    A missing line or file is never a failure: it resolves to `auto`, the default preset
    (2026-09-08; `default` before that), because a fresh or pulled template vault has never
    run `set`. lane.py's fallback for a missing line is the same `auto`."""
    try:
        with open(os.path.join(root, CUSTOM_REL), encoding="utf-8") as fh:
            txt = fh.read()
    except OSError:
        return "auto", "unreadable"
    match = SETTINGS_RE.search(txt)
    if not match:
        return "auto", "line absent"
    name = match.group(1).lower()
    if name not in THROTTLES:
        _fail("unknown throttle '%s' in the CUSTOMISATION Settings line (known: %s)"
              % (name, ", ".join(THROTTLES)))
    return name, None


def settings_text(txt, name):
    """CUSTOMISATION.md with the throttle line set to `name`. Rewrite in place if the
    line is there; otherwise insert it directly after `- **pre-report**:`, and failing
    that at the end of the `## Settings` block."""
    line = SETTINGS_LINE % name
    if SETTINGS_LINE_RE.search(txt):
        return SETTINGS_LINE_RE.sub(lambda _m: line, txt, count=1), "rewritten"
    head = SETTINGS_HEAD_RE.search(txt)
    if not head:
        _fail("%s has no `## Settings` block to record the throttle in" % CUSTOM_REL)
    nxt = NEXT_HEAD_RE.search(txt, head.end())
    end = nxt.start() if nxt else len(txt)
    block = txt[head.end():end]
    anchor = PREREPORT_RE.search(block)
    where = "after pre-report"
    if not anchor:
        bullets = list(BULLET_RE.finditer(block))
        if not bullets:
            _fail("%s `## Settings` block holds no `- **knob**:` line to insert after"
                  % CUSTOM_REL)
        last = bullets[-1]
        nl = block.find("\n", last.start())
        anchor_end = len(block) if nl < 0 else nl
        where = "at the end of the Settings block"
    else:
        anchor_end = anchor.end()
    cut = head.end() + anchor_end
    return txt[:cut] + "\n" + line + txt[cut:], where


# ------------------------------------------------------ the definition files ----------

def definition_paths(root):
    """Every definition on disk, by stem. The stem is the routing key: the head spawns a
    lane by definition name and the file name is what the registry lists."""
    adir = os.path.join(root, AGENTS_REL)
    if not os.path.isdir(adir):
        _fail("no definitions directory at %s (wrong --root?)" % AGENTS_REL)
    found = {}
    for entry in sorted(os.listdir(adir)):
        if entry.endswith(".md") and not entry.startswith("."):
            found[entry[:-3]] = os.path.join(adir, entry)
    return found


def read_definition(path, rel):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        _fail("%s unreadable (%s)" % (rel, exc.strerror or exc.__class__.__name__))


def frontmatter_bounds(text, rel):
    """(lines with their terminators, index of the closing `---`)."""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        _fail("%s: no frontmatter (the first line is not `---`)" % rel)
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") == "---":
            return lines, i
    _fail("%s: unterminated frontmatter (no closing `---`)" % rel)


def field_index(lines, close, key):
    for i in range(1, close):
        if FIELD_RE[key].match(lines[i]):
            return i
    return None


def field_value(lines, close, key):
    i = field_index(lines, close, key)
    if i is None:
        return None
    val = FIELD_RE[key].match(lines[i]).group("val")
    return val.split("#", 1)[0].strip()


def set_field(lines, close, key, value):
    """Rewrite the field in place, or add it: after `model:` where that line exists, else
    at the end of the frontmatter. A trailing `#` comment on the line survives. Returns
    (lines, close, old_value)."""
    i = field_index(lines, close, key)
    if i is None:
        anchor = field_index(lines, close, "model")
        at = close if anchor is None else anchor + 1
        return lines[:at] + ["%s: %s\n" % (key, value)] + lines[at:], close + 1, None
    match = FIELD_RE[key].match(lines[i])
    raw = match.group("val")
    comment = raw.split("#", 1)[1] if "#" in raw else None
    old = raw.split("#", 1)[0].strip()
    new = "%s %s" % (match.group("key"), value)
    if comment is not None:
        new += "  #" + comment
    out = list(lines)
    out[i] = new + (match.group("eol") or "\n")
    return out, close, old


LIST_FIELD_RE = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_-]*):(?P<val>[^\r\n]*)$")
LIST_ITEM_RE = re.compile(r"^\s*-\s+(.+?)\s*$")


def list_field(lines, close, key):
    """A frontmatter field read as a list of names, or None where the key is absent. Two
    YAML shapes are live in the definitions and both are read: an inline comma list
    (`tools: Read, Grep, Glob`) and a block list (`skills:` then `  - ingest`)."""
    for i in range(1, close):
        match = LIST_FIELD_RE.match(lines[i].rstrip("\r\n"))
        if not match or match.group("key") != key:
            continue
        inline = match.group("val").split("#", 1)[0].strip()
        if inline:
            return [part.strip() for part in inline.split(",") if part.strip()]
        items = []
        for j in range(i + 1, close):
            item = LIST_ITEM_RE.match(lines[j].rstrip("\r\n"))
            if not item:
                break
            items.append(item.group(1).strip())
        return items
    return None


def skill_available(lines, close):
    """True where the definition leaves the `Skill` tool usable. Keyed on the property the
    harness applies — an allowlist wins over a denylist — never on a definition's name, so
    the next definition added is checked by the same rule."""
    allowed = list_field(lines, close, "tools")
    if allowed is not None:
        return "Skill" in allowed
    return "Skill" not in (list_field(lines, close, "disallowedTools") or [])


def wider_tools(lines, close, row_tools):
    """The tools a definition's allowlist names that its class row does not grant. A
    definition with no `tools:` allowlist returns none: the spawn's `--tools` flag bounds
    it to the row, so a denylist can only narrow."""
    allowed = list_field(lines, close, "tools")
    if allowed is None:
        return []
    return [t for t in allowed if t not in row_tools]


def description_text(text):
    """The frontmatter `description:` value, or None where there is no readable
    frontmatter. Deliberately tolerant: an arbitrary file dropped into `.claude/agents/`
    is already reported as UNROUTED, and parsing it strictly here would let it break the
    whole run. Single-line values only, which is the shape every definition uses."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        if line.startswith("description:"):
            return line[len("description:"):].strip()
    return None


def diff_definition(rel, text, want_model, want_effort):
    """The DRIFT lines for one definition. The comparator the self-control exercises."""
    lines, close = frontmatter_bounds(text, rel)
    findings = []
    for key, want in (("model", want_model), ("effort", want_effort)):
        have = field_value(lines, close, key)
        if have != want:
            findings.append("DRIFT %s: %s %s ≠ %s" % (rel, key, have or "absent", want))
    return findings


SYNTH_OK = "---\nname: synthetic\nmodel: opus\neffort: max\n---\n\nbody\n"
SYNTH_BAD = "---\nname: synthetic\nmodel: haiku\neffort: low\n---\n\nbody\n"
# Schema-2 controls: one definition that fails each new probe, one that passes it.
SYNTH_SKILL_ON = "---\nname: synthetic\ntools: Read, Grep, Skill\n---\n\nbody\n"
SYNTH_SKILL_OFF = "---\nname: synthetic\ndisallowedTools: Agent, Skill\n---\n\nbody\n"
SYNTH_ROW_TOOLS = ["Read", "Grep"]


def self_control(schema=1):
    """Positive control on the same run: every probe that can report clean must first
    catch its own planted fault. A miss makes every clean report worthless."""
    caught = len(diff_definition("<synthetic>", SYNTH_BAD, "opus", "max"))
    quiet = len(diff_definition("<synthetic>", SYNTH_OK, "opus", "max"))
    if caught != 2 or quiet != 0:
        _fail("comparator self-control failed (%d/2 planted drifts caught, %d false on a "
              "matching record)" % (caught, quiet))
    note = "control: comparator caught 2/2 planted drifts"
    if schema != 2:
        return note
    on_lines, on_close = frontmatter_bounds(SYNTH_SKILL_ON, "<synthetic-skill-on>")
    off_lines, off_close = frontmatter_bounds(SYNTH_SKILL_OFF, "<synthetic-skill-off>")
    hits = 0
    hits += 1 if skill_available(on_lines, on_close) else 0
    hits += 1 if wider_tools(on_lines, on_close, SYNTH_ROW_TOOLS) == ["Skill"] else 0
    false_hits = 0
    false_hits += 1 if skill_available(off_lines, off_close) else 0
    false_hits += 1 if wider_tools(off_lines, off_close, SYNTH_ROW_TOOLS) else 0
    if hits != 2 or false_hits != 0:
        _fail("schema-2 self-control failed (%d/2 planted definitions caught, %d false on "
              "a compliant one)" % (hits, false_hits))
    return note + "; Skill and tools probes caught 2/2 planted definitions"


# ------------------------------------------------------------------ the write ---------

def write_text(path, text):
    """The one write path in this script. Callers build the whole new text first, so a
    rejected record or an unparseable file changes nothing."""
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


# --------------------------------------------------------------- subcommands ----------

def throttle_note(reason):
    """How the active throttle was arrived at, or None when the Settings line was read
    normally. One wording for every verb since 2026-09-08 (`show` and `check` spelt the
    absent line differently before): the fallback is named, so a reader of either sees
    that `auto` was assumed rather than set."""
    if reason == "line absent":
        return "no throttle line: treated as auto"
    if reason == "unreadable":
        return "CUSTOMISATION unreadable: treated as auto"
    return None


def collect_findings(root, rec, name):
    """(findings, definitions diffed, fields compared, roles routed) for one throttle."""
    wanted = resolve(rec, name)
    on_disk = definition_paths(root)
    schema = rec.get("schema", 1)
    findings, read, fields = [], 0, 0
    texts = {}
    for role, (model, effort) in wanted.items():
        rel = os.path.join(AGENTS_REL, role + ".md")
        path = on_disk.get(role)
        if path is None:
            findings.append("MISSING %s" % rel)
            continue
        texts[role] = read_definition(path, rel)
        findings.extend(diff_definition(rel, texts[role], model, effort))
        read += 1
        fields += 2
        if schema != 2:
            continue
        # Schema 2 carries the class row's tool grant, so two more properties are
        # checkable here: the Skill tool must stay off (a thin lane that can load a whole
        # skill is no longer thin), and a definition must not claim a tool its row does
        # not grant. The wrapper's `--tools` is the fence; this is the declaration check,
        # and it is what an in-session spawn of the same definition actually gets.
        lines, close = frontmatter_bounds(texts[role], rel)
        if skill_available(lines, close):
            findings.append("SKILL-AVAILABLE %s" % rel)
        extra = wider_tools(lines, close, rows(rec)[role]["tools"])
        if extra:
            findings.append("TOOLS-WIDER %s: %s beyond the `%s` row's tools"
                            % (rel, ", ".join(extra), role))
    for stem in sorted(on_disk):
        if stem not in wanted:
            findings.append("UNROUTED %s" % os.path.join(AGENTS_REL, stem + ".md"))
    for stem in sorted(on_disk):
        text = texts.get(stem)
        if text is None:
            text = read_definition(on_disk[stem], os.path.join(AGENTS_REL, stem + ".md"))
        desc = description_text(text)
        if desc and DESC_TIER_RE.search(desc):
            findings.append("DESCRIPTION-TIER %s" % os.path.join(AGENTS_REL, stem + ".md"))
    return findings, read, fields, len(wanted)


def summary_line(findings, read, fields, total, name, control):
    """The drift status. `show` prints the same line as `check`, so the two verbs can
    never disagree about what the vault looks like. `N of M diffed` names how many of the
    routed roles were actually compared: a run that read fewer files than it routes has
    findings to explain the gap, and a reader can see the shortfall in the summary."""
    if findings:
        return ("check: %d finding(s) against throttle '%s' — %d of %d diffed, %d fields (%s)"
                % (len(findings), name, read, total, fields, control))
    return ("check: clean — %d of %d diffed, %d fields match throttle '%s' (%s)"
            % (read, total, fields, name, control))


def cmd_check(args):
    root = args.root
    rec = load_routing(root)
    name, reason = active_throttle(root)
    control = self_control(rec.get("schema", 1))
    note = throttle_note(reason)
    if note:
        print("throttle: %s (%s)" % (name, note))
    findings, read, fields, total = collect_findings(root, rec, name)
    if args.require:
        if args.require not in THROTTLES:
            _fail("unknown throttle %r passed to --require (known: %s)"
                  % (args.require, ", ".join(THROTTLES)))
        if args.require != name:
            findings.append("REQUIRE %s: the active throttle is %s" % (args.require, name))
    for line in findings:
        print(line)
    print(summary_line(findings, read, fields, total, name, control))
    return 1 if findings else 0


def cmd_show(args):
    root = args.root
    rec = load_routing(root)
    name, reason = active_throttle(root)
    note = throttle_note(reason)
    print("throttle: %s%s" % (name, " (%s)" % note if note else ""))
    wanted = resolve(rec, name)
    width = max([len(r) for r in wanted] + [len("role")])
    header = "%-*s  %-6s  %s" % (width, "role", "model", "effort")
    if name == "auto":
        # Under `auto` the table shows anchors, not pins: say so once, on the header line.
        header += "  (anchors: the head picks per call within the options)"
    print(header)
    for role, (model, effort) in wanted.items():
        print("%-*s  %-6s  %s" % (width, role, model, effort))
    findings, read, fields, total = collect_findings(root, rec, name)
    control = self_control(rec.get("schema", 1))
    for line in findings:
        print(line)
    print(summary_line(findings, read, fields, total, name, control))
    print(HEAD_LINE[name])
    print("(a recommendation for the head's own tier — the head's model and effort stay "
          "the owner's client settings, never this knob)")
    return 0


def cmd_resolve(args):
    """One class's spawn inputs, on stdout, for the wrapper to compose flags from. Text
    form for a human reading a spawn record; `--json` for the wrapper. The throttle comes
    from the flag, else the Settings line, else `auto` — the same order every verb uses,
    so a spawn can never resolve against a throttle the vault does not hold. Both forms
    carry `model_src`/`effort_src` (`anchor` under `auto`, `throttle <name>` otherwise)
    and the row's option lists, the range the head picks within (2026-09-08)."""
    rec = load_routing(args.root)
    if args.throttle:
        name, source = args.throttle, "flag"
        if name not in THROTTLES:
            _fail("unknown throttle %r passed to --throttle (known: %s)"
                  % (name, ", ".join(THROTTLES)))
    else:
        name, reason = active_throttle(args.root)
        source = reason or "settings"
    row = resolve_row(rec, args.cls, name)
    if args.json:
        row["throttle_source"] = source
        print(json.dumps(row, ensure_ascii=False, sort_keys=True))
        return 0
    note = throttle_note(None if source in ("settings", "flag") else source)
    print("class: %s" % row["class"])
    print("throttle: %s%s" % (name, " (%s)" % note if note else ""))
    print("model: %s" % row["model"])
    print("effort: %s" % row["effort"])
    print("model-src: %s" % row["model_src"])
    print("effort-src: %s" % row["effort_src"])
    print("model-options: %s" % ", ".join(row["model_options"]))
    print("effort-options: %s" % ", ".join(row["effort_options"]))
    for label, key in (("tools", "tools"), ("grants", "grants"),
                       ("grants-extras", "grants_extras"), ("writes", "writes"),
                       ("skills", "skills"), ("skills-extras", "skills_extras"),
                       ("mcp", "mcp"), ("mcp-grantable", "mcp_grantable")):
        print("%s: %s" % (label, ", ".join(row[key]) if row[key] else "(none)"))
    print("cache: %s" % row["cache"])
    return 0


def cmd_set(args):
    root, name = args.root, args.name
    if name not in THROTTLES:
        _fail("unknown throttle %r (known: %s)" % (name, ", ".join(THROTTLES)))
    rec = load_routing(root)           # validates the whole record before any write
    wanted = resolve(rec, name)
    on_disk = definition_paths(root)
    plan, notes, missing = [], [], []

    custom_path = os.path.join(root, CUSTOM_REL)
    try:
        with open(custom_path, encoding="utf-8") as fh:
            custom = fh.read()
    except OSError as exc:
        _fail("%s unreadable (%s) — the throttle has nowhere to be recorded"
              % (CUSTOM_REL, exc.strerror or exc.__class__.__name__))
    was, _ = active_throttle(root)
    had_line = SETTINGS_LINE_RE.search(custom) is not None
    new_custom, where = settings_text(custom, name)
    if new_custom != custom:
        plan.append((custom_path, new_custom))
        notes.append("changed %s: throttle %s"
                     % (CUSTOM_REL, ("%s → %s" % (was, name)) if had_line
                        else "line inserted %s → %s" % (where, name)))

    for role, (model, effort) in wanted.items():
        rel = os.path.join(AGENTS_REL, role + ".md")
        path = on_disk.get(role)
        if path is None:
            missing.append("MISSING %s" % rel)
            continue
        text = read_definition(path, rel)
        lines, close = frontmatter_bounds(text, rel)   # unparseable -> PROBE FAILED
        lines, close, old_model = set_field(lines, close, "model", model)
        lines, close, old_effort = set_field(lines, close, "effort", effort)
        new_text = "".join(lines)
        if new_text == text:
            continue
        # Report only the halves that really moved: a note claiming `effort max → max`
        # would be a false change claim on an otherwise honest report.
        moved = []
        if old_model != model:
            moved.append("model %s → %s" % (old_model or "absent", model))
        if old_effort != effort:
            moved.append("effort %s → %s" % (old_effort or "absent", effort))
        plan.append((path, new_text))
        notes.append("changed %s: %s" % (rel, " · ".join(moved) or "frontmatter normalised"))

    if not args.dry_run:
        for path, text in plan:
            write_text(path, text)
    for line in notes:
        print(line)
    for line in missing:
        print(line)
    total = len(wanted) + 1 - len(missing)
    same = total - len(plan)
    tail = "" if plan else " — nothing to do (already at '%s')" % name
    print("set '%s': %d file(s) changed, %d already correct, %d routed definition(s) "
          "missing%s" % (name, len(plan), same, len(missing), tail))
    if args.dry_run:
        print("(dry run — nothing written)")
    return 1 if missing else 0


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="throttle.py",
        description="the subagent routing throttle: show, check, set, resolve")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for verb, fn in (("show", cmd_show), ("check", cmd_check), ("set", cmd_set),
                     ("resolve", cmd_resolve)):
        p = sub.add_parser(verb)
        p.add_argument("--root", default=".", help="vault root (default: the current directory)")
        p.set_defaults(fn=fn)
        if verb == "resolve":
            p.add_argument("--class", dest="cls", required=True, metavar="CLASS",
                           help="the lane class to resolve (a row of the schema-2 record)")
            p.add_argument("--throttle", metavar="NAME",
                           help="resolve under NAME instead of the vault's active throttle")
            p.add_argument("--json", action="store_true",
                           help="one JSON object on stdout, for the spawn wrapper")
        if verb == "check":
            p.add_argument("--require", metavar="NAME",
                           help="add a finding unless the active throttle is NAME")
        if verb == "set":
            p.add_argument("name", metavar="NAME", help=" · ".join(THROTTLES))
            p.add_argument("--dry-run", action="store_true", help="print the plan, write nothing")
    args = ap.parse_args(argv)
    args.root = os.path.abspath(args.root)
    return args.fn(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Probe as err:
        print("PROBE FAILED: %s" % err)
        sys.exit(2)
