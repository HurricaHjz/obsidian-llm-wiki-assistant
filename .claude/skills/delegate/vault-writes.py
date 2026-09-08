#!/usr/bin/env python3
"""vault-writes.py — the vault writes a head composes by hand, as primitives that cannot slip.

Four writes recur in every run — a log entry, a defect-register entry, a register entry
closed, an IDEAS bullet annotated — and each has been mis-composed by hand: a misplaced
anchor, a doubled span, an entry inserted under the wrong heading. Each verb below makes
one of them against an asserted anchor, prints one line, and refuses rather than guesses.

  log-append        append one entry to `wiki/log.md` under the vault root given.
  register add      insert one entry at the top of `## Open` in
                    `wiki/developments/known-issues.md`.
  register close    move one `## Open` entry to the top of `## Closed`, dating its Status.
  ideas annotate    append ` *(agent DATE TIME: NOTE)*` to one numbered IDEAS bullet.

The clock, and why it is not an argument

  A time of day written by hand is written from a sense of elapsed time, and seven such
  stamps reached five surfaces in one session before anything compared one to a clock. So
  every stamp below is read from the clock at the moment of the write and from nowhere
  else — no `--time` argument exists to be guessed into:

    register add     `### [DATE HH:MM] SURFACE — TITLE (SEVERITY)`, the date from `--date`.
    register close   the status fact as `closed DATE HH:MM — …`: the time is inserted after
                     the date the caller's `--status` already opens with (`closed DATE …`),
                     and otherwise the whole stamp is prefixed to the caller's text.
    ideas annotate   `*(agent DATE HH:MM: NOTE)*`.
    log-append       one further bullet, `- **Clock**: HH:MM ZONE`, written through the
                     `--extra` path between Changed and Conflicts. The `## [DATE] ACTION |
                     TITLE` heading is a schema surface and is not touched.

  The zone is the clock's own (`%Z`), never a literal. And because a caller's free text may
  still name a time, every text argument is scanned for an `H:MM`, `HH:MM` or `HH:Mx` token
  whose hour disagrees with the clock's: each such token prints one line on stderr,
  `clock: the note names TOKEN, the clock reads HH:MM`. It is a warning and never a
  refusal — a note may legitimately cite a past event — so the write proceeds either way,
  and `--dry-run` prints the same warnings.

The contract every verb keeps

  * One line of output. `ok <verb> <path>:<line>` names where the change landed, or
    `error <verb>: <reason>` names what stopped it and the process exits 2. A head pays
    a few tokens for a write and never reads a dump.
  * `--dry-run` prints `dry-run <verb> <path>:<line>` and the would-be block as `| `
    lines (at most PREVIEW_MAX, then a count), and writes nothing at all. It is the control
    run, and the way to see a change before making it.
  * Every write except the log append is atomic: a temp file beside the target, fsync,
    `os.replace`. An interruption leaves the old file or the new one, never half of one.
  * The log is append-only by contract, so `log-append` opens it in append mode and never
    rewrites it. Two bounded read-only probes support that append and neither holds the
    file in memory: its last two bytes (which decide the blank-line separator) and a
    chunked newline count (the line number the `ok` line reports). Neither alters a byte.
  * Every text argument carrying a line break is refused. Wiki prose is one line per
    paragraph or bullet (the schema line discipline), and a line break is also how a
    caller text would forge a heading inside somebody else entry.
  * Refusal beats repair. A structural heading that does not appear exactly once, a match
    count that is not one, a missing file, an entry with no Status bullet: `error`, exit 2,
    naming the count it actually found. Nothing is written on a refusal.

Formats, and where they come from

  The log entry is `## [DATE] ACTION | TITLE`, then `- **Changed**: …`, then the `Clock`
  bullet and any `--extra` bullets in the order given, then `- **Conflicts**: …`, then a
  blank line — the shape the file own recent entries carry, Changed first and Conflicts last.
  The register entry is the format the register documents above its own `## Open` heading:
  severity in the heading, then `- **Where observed**`, `- **Symptom**`,
  `- **Suspected cause**`, `- **Status**`. `--status` is the caller's own words, prefixed on
  a close by the clock stamp above and otherwise untouched (`open — fix shape: …`);
  `--where` is optional and its bullet is omitted when it is absent rather than filled with
  invented text.
  `register close` finds the Status line of the entry by the `**Status**` marker, so it dates both
  forms in live use: a `- **Status**: …` bullet, and a `- **Severity**: … **Status**: …`
  line.

Run

  vault-writes.py log-append --vault V --action ACTION --title T --changed C --conflicts X
                             [--extra "Key: value"]... [--date D] [--dry-run]
  vault-writes.py register add --vault V --date D --surface S --symptom Y --cause C
                               --severity minor --status T [--where W] [--dry-run]
  vault-writes.py register close --vault V --match TEXT --date D --status TEXT [--dry-run]
  vault-writes.py ideas annotate --file IDEAS.md --item N --note TEXT [--date D] [--dry-run]

Suite: `test_vault_writes.sh` beside this file (last line PASS n/n or FAIL k/n).
"""

import argparse
import datetime
import os
import re
import stat
import sys
import tempfile
import time

# The vocabulary the log itself uses of entry kinds; anything else is a typo, never a new kind.
ACTIONS = ("ingest", "gather", "synthesis", "lint", "deep-lint", "framework",
           "setup", "maps", "attic", "export")
# The severities the register documents. Its format block offers "blocking · major · minor"
# and its live entries also carry "medium", so all four are accepted and none is invented.
SEVERITIES = ("blocking", "major", "medium", "minor")

# Paths are derived from the vault root the caller passes: no absolute path is written here.
LOG_REL = os.path.join("wiki", "log.md")
REGISTER_REL = os.path.join("wiki", "developments", "known-issues.md")

OPEN_HEAD = "## Open"
CLOSED_HEAD = "## Closed"
NUMERO = "№"                  # the IDEAS bullet marker, spelled as an escape
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ITEM_RE = re.compile(r"^[0-9]+$")
ENTRY_END_RE = re.compile(r"^#{1,6} ")  # any ATX heading ends the entry above it
CHUNK = 65536                           # the log newline count reads this much at a time
PREVIEW_MAX = 6                         # `--dry-run` prints at most this many `| ` lines
SHORT = 70                              # an error line quotes at most this much of a line

# A clock token as the register and the notes actually write one: a one- or two-digit hour,
# a colon, then two digits or the rounded `Mx` form the register uses ("filed 21:3x BST").
# The lookarounds keep the seconds of `19:52:29` from reading as a second token (`52:29`)
# and keep a token out of a longer word; an hour above 23 is not a time and is skipped.
CLOCK_TOKEN_RE = re.compile(r"(?<![0-9A-Za-z:])([0-9]{1,2}):([0-9][0-9x])(?![0-9A-Za-z])")
HOUR_MAX = 23
HOURS = 24
# The grace: the previous hour passes while the clock's minute is under ten — a note written
# just after the turn of the hour about the minute before it. Ten is set by judgement,
# unmeasured; the failure it forgives (a stamp one minute stale) is smaller than the one it
# would otherwise report, and no count of real notes was taken to choose it.
GRACE_MINUTES = 10
# The status fact `register close` writes, and the two shapes a caller's own `--status` may
# already carry: `closed DATE …` takes the time after its date, `closed DATE HH:MM …` is
# already stamped and is left exactly as it came.
# The already-stamped shape admits the rounded `HH:Mx` minute as well as `HH:MM`, so a
# caller who wrote one keeps it verbatim rather than collecting a second time beside it;
# whether that time agrees with the clock is the token check's business, not this one's.
CLOSED_DATED_RE = re.compile(r"^closed\s+\d{4}-\d{2}-\d{2}")
CLOSED_TIMED_RE = re.compile(r"^closed\s+\d{4}-\d{2}-\d{2}\s+\d{1,2}:[0-9][0-9x]")


def die(verb, reason):
    """One error line on stdout — where the head reads it — then exit 2. Never a traceback."""
    print("error %s: %s" % (verb, reason))
    sys.exit(2)


def short(text):
    """A line quoted inside an error message stays inside one line."""
    text = " ".join(text.split())
    return text if len(text) <= SHORT else text[:SHORT - 1] + "…"


def check_text(verb, name, value, allow_empty=False):
    """A wiki line is one line: refuse any argument carrying a break, and refuse the blank."""
    if value is None:
        return None
    if "\n" in value or "\r" in value:
        die(verb, "%s carries a line break; a wiki bullet is one line" % name)
    if not allow_empty and not value.strip():
        die(verb, "%s is empty" % name)
    return value


def check_date(verb, value):
    """A date is YYYY-MM-DD and a real calendar day; absent, it is today."""
    if value is None:
        return datetime.date.today().isoformat()
    if not DATE_RE.match(value):
        die(verb, "--date '%s' is not YYYY-MM-DD" % value)
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        die(verb, "--date %s is not a real date" % value)
    return value


# ----------------------------------------------------------------------- clock ---------

def clock_now():
    """The wall clock, read once per run so every stamp of one write agrees with the rest."""
    return time.localtime()


def clock_hm(now):
    """The stamp itself: `HH:MM`, zero-padded, local time — the only source of a time here."""
    return time.strftime("%H:%M", now)


def clock_zone(now):
    """The clock's own zone name. `%z` (+0100) stands in where a host reports no name."""
    return time.strftime("%Z", now) or time.strftime("%z", now)


def hour_disagrees(token_hour, clock_hour, clock_minute):
    """Whether a token hour is neither the clock's own nor the previous one under the grace."""
    if token_hour == clock_hour:
        return False
    if clock_minute < GRACE_MINUTES and token_hour == (clock_hour - 1) % HOURS:
        return False
    return True


def clock_tokens(now, values):
    """Every distinct clock token in the caller's text whose hour disagrees, in reading order.

    Distinct, because one token repeated across two arguments is one mistake and earns one
    line; the order is the order the arguments are listed by the verb that collected them."""
    offenders = []
    for value in values:
        if not value:
            continue
        for found in CLOCK_TOKEN_RE.finditer(value):
            hour = int(found.group(1))
            if hour > HOUR_MAX:
                continue                # 52 of `19:52:29` is not an hour; nor is 99
            if not hour_disagrees(hour, now.tm_hour, now.tm_min):
                continue
            if found.group(0) not in offenders:
                offenders.append(found.group(0))
    return offenders


def warn_clock(now, values):
    """One stderr line per offending token. A warning: a note may cite a past event, so the
    write goes ahead, and stdout keeps the one line a head reads."""
    reading = clock_hm(now)
    for token in clock_tokens(now, values):
        sys.stderr.write("clock: the note names %s, the clock reads %s\n" % (token, reading))


def stamped_status(status, date, hm):
    """The `register close` status fact, stamped: `closed DATE HH:MM — …`.

    A caller who already opened with `closed DATE` gets the time inserted after that date
    rather than a second `closed`; one who already carries a time keeps it (the token check
    is what says whether that time agrees with the clock); anything else is prefixed whole."""
    if CLOSED_TIMED_RE.match(status):
        return status
    dated = CLOSED_DATED_RE.match(status)
    if dated:
        return "%s %s%s" % (status[:dated.end()], hm, status[dated.end():])
    return "closed %s %s — %s" % (date, hm, status)


def read_text(verb, path):
    """The register and IDEAS are read whole; the log never is (see log_tail below)."""
    if not os.path.isfile(path):
        die(verb, "no file at %s" % path)
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            return handle.read()
    except UnicodeDecodeError:
        die(verb, "%s is not UTF-8" % path)


def atomic_write(verb, path, text):
    """Write beside the target, fsync, rename: the file is whole or untouched, never half."""
    directory = os.path.dirname(os.path.abspath(path))
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError:
        mode = None
    handle_fd, tmp = tempfile.mkstemp(prefix=".vault-writes-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(handle_fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)          # a failed write leaves no debris beside the target
        except OSError:
            pass
        raise
    try:                            # the rename is durable only once the directory is
        dir_fd = os.open(directory, os.O_RDONLY)    # synced; best effort, never fatal
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass


def report(verb, path, line, preview, dry_run):
    """The whole of the output of a verb: one line, or the bounded block of a dry run."""
    if not dry_run:
        print("ok %s %s:%d" % (verb, path, line))
        return
    print("dry-run %s %s:%d" % (verb, path, line))
    for item in preview[:PREVIEW_MAX]:
        print("| %s" % item)
    if PREVIEW_MAX < len(preview):
        print("| + %d more lines" % (len(preview) - PREVIEW_MAX))


def line_terminator(line):
    """A file that arrived with CRLF keeps its CR on the line this run edits."""
    return "\r" if line.endswith("\r") else ""


# ------------------------------------------------------------------ log-append ---------

def log_tail(path, count=2):
    """The last bytes, by seek. The log is append-only and is never held in memory."""
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        handle.seek(max(0, size - count))
        return handle.read()


def log_line_count(path):
    """Newlines, counted in bounded chunks — again, never the whole file in memory."""
    total = 0
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(CHUNK)
            if not chunk:
                break
            total += chunk.count(b"\n")
    return total


def log_separator(tail):
    """Whatever it takes for exactly one blank line to sit above the new heading.

    An entry is written ending in a blank line, so a file whose tail is already a blank
    line needs nothing; one ending mid-line needs that line finished first."""
    if not tail:
        return ""                       # an empty log: the heading is line 1
    if tail.endswith(b"\n\n"):
        return ""
    if tail.endswith(b"\n"):
        return "\n"
    return "\n\n"


def cmd_log_append(args):
    verb = "log-append"
    path = os.path.join(args.vault, LOG_REL)
    if args.action not in ACTIONS:
        die(verb, "--action '%s' is none of: %s" % (args.action, " ".join(ACTIONS)))
    date = check_date(verb, args.date)
    title = check_text(verb, "--title", args.title)
    changed = check_text(verb, "--changed", args.changed)
    conflicts = check_text(verb, "--conflicts", args.conflicts)
    extras = []
    for raw in args.extra or []:
        check_text(verb, "--extra", raw)
        if ":" not in raw:
            die(verb, "--extra '%s' is not 'Key: value'" % short(raw))
        key, value = raw.split(":", 1)
        key, value = key.strip(), value.strip()
        if not key or not value:
            die(verb, "--extra '%s' needs a key and a value" % short(raw))
        extras.append((key, value))
    if not os.path.isfile(path):
        die(verb, "no file at %s" % path)

    now = clock_now()
    warn_clock(now, [title, changed, conflicts] + [raw for raw in args.extra or []])
    # The heading shape is a schema surface and stays `## [DATE] ACTION | TITLE`, so the time
    # rides in a bullet instead — first among the extras, where it sits under the heading's
    # own date and does not move when the caller passes more of them.
    extras.insert(0, ("Clock", "%s %s" % (clock_hm(now), clock_zone(now))))

    block = ["## [%s] %s | %s" % (date, args.action, title),
             "- **Changed**: %s" % changed]
    for key, value in extras:
        block.append("- **%s**: %s" % (key, value))
    block.append("- **Conflicts**: %s" % conflicts)

    separator = log_separator(log_tail(path))
    payload = separator + "\n".join(block) + "\n\n"
    heading_line = log_line_count(path) + separator.count("\n") + 1

    if args.dry_run:
        report(verb, path, heading_line, block, True)
        return
    with open(path, "a", encoding="utf-8") as handle:   # append only, never a rewrite
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    report(verb, path, heading_line, block, False)


# -------------------------------------------------------------------- register ---------

def register_lines(verb, path):
    """The register as a line list whose join restores the file byte for byte."""
    return read_text(verb, path).split("\n")


def heading_index(verb, lines, heading):
    """The one line that IS the heading. Not one, not the register this code knows: refuse."""
    hits = [i for i, line in enumerate(lines) if line == heading]
    if len(hits) != 1:
        die(verb, "'%s' is %d lines of the register, not 1" % (heading, len(hits)))
    return hits[0]


def register_anchors(verb, lines):
    """Both section headings, asserted once each and in the order the register keeps them."""
    open_at = heading_index(verb, lines, OPEN_HEAD)
    closed_at = heading_index(verb, lines, CLOSED_HEAD)
    if closed_at < open_at:
        die(verb, "'%s' (line %d) sits above '%s' (line %d)"
            % (CLOSED_HEAD, closed_at + 1, OPEN_HEAD, open_at + 1))
    return open_at, closed_at


def first_body_index(lines, head_at):
    """Where the first entry of a section starts: the blank line under the heading is kept."""
    index = head_at + 1
    while index < len(lines) and not lines[index].strip():
        index += 1
    return index


def entry_end(lines, start, stop):
    """One entry runs from its own heading to the line before the next heading."""
    index = start + 1
    while index < stop and not ENTRY_END_RE.match(lines[index]):
        index += 1
    return index


def cmd_register_add(args):
    verb = "register-add"
    path = os.path.join(args.vault, REGISTER_REL)
    date = check_date(verb, args.date)
    surface = check_text(verb, "--surface", args.surface)
    symptom = check_text(verb, "--symptom", args.symptom)
    cause = check_text(verb, "--cause", args.cause)
    status = check_text(verb, "--status", args.status)
    where = check_text(verb, "--where", args.where)
    if args.severity not in SEVERITIES:
        die(verb, "--severity '%s' is none of: %s" % (args.severity, " ".join(SEVERITIES)))

    now = clock_now()
    warn_clock(now, [surface, symptom, cause, status, where])

    lines = register_lines(verb, path)
    open_at, _ = register_anchors(verb, lines)

    block = ["### [%s %s] %s (%s)" % (date, clock_hm(now), surface, args.severity)]
    if where:
        block.append("- **Where observed**: %s" % where)
    block.append("- **Symptom**: %s" % symptom)
    block.append("- **Suspected cause**: %s" % cause)
    block.append("- **Status**: %s" % status)

    at = first_body_index(lines, open_at)
    if args.dry_run:
        report(verb, path, at + 1, block, True)
        return
    atomic_write(verb, path, "\n".join(lines[:at] + block + [""] + lines[at:]))
    report(verb, path, at + 1, block, False)


def cmd_register_close(args):
    verb = "register-close"
    path = os.path.join(args.vault, REGISTER_REL)
    date = check_date(verb, args.date)
    match = check_text(verb, "--match", args.match)
    status = check_text(verb, "--status", args.status)

    now = clock_now()
    # `--match` is a locator, not text this write lands: an entry already headed with a time
    # is addressed by that time, and warning about it would be warning about the register.
    warn_clock(now, [status])
    status = stamped_status(status, date, clock_hm(now))

    lines = register_lines(verb, path)
    open_at, closed_at = register_anchors(verb, lines)

    hits = [i for i in range(open_at + 1, closed_at)
            if lines[i].startswith("### ") and match in lines[i]]
    if len(hits) != 1:
        die(verb, "'%s' matches %d entry headings under '%s', not 1"
            % (short(match), len(hits), OPEN_HEAD))
    start = hits[0]
    end = entry_end(lines, start, closed_at)
    block = lines[start:end]
    while block and not block[-1].strip():
        block.pop()

    status_lines = [i for i, line in enumerate(block) if "**Status**" in line]
    if len(status_lines) != 1:
        die(verb, "the entry '%s' carries %d '**Status**' lines, not 1"
            % (short(lines[start]), len(status_lines)))
    at_status = status_lines[0]
    tail = line_terminator(block[at_status])
    block[at_status] = "%s *(%s: %s)*%s" % (block[at_status].rstrip(), date, status, tail)

    remainder = lines[:start] + lines[end:]
    # The anchors move once the span is gone, so they are asserted again on the remainder.
    _, closed_after = register_anchors(verb, remainder)
    at = first_body_index(remainder, closed_after)
    preview = [block[0], block[at_status],
               "moved %d lines to the top of '%s'" % (len(block), CLOSED_HEAD)]
    if args.dry_run:
        report(verb, path, at + 1, preview, True)
        return
    atomic_write(verb, path, "\n".join(remainder[:at] + block + [""] + remainder[at:]))
    report(verb, path, at + 1, preview, False)


# ----------------------------------------------------------------------- ideas ---------

def cmd_ideas_annotate(args):
    verb = "ideas-annotate"
    path = args.file
    if not ITEM_RE.match(args.item):
        die(verb, "--item '%s' is not a number" % short(args.item))
    note = check_text(verb, "--note", args.note)
    date = check_date(verb, args.date)

    now = clock_now()
    warn_clock(now, [note])

    lines = read_text(verb, path).split("\n")
    marker = "- **%s%s**" % (NUMERO, args.item)
    hits = [i for i, line in enumerate(lines) if line.startswith(marker)]
    if len(hits) != 1:
        die(verb, "'%s' begins %d lines of %s, not 1" % (marker, len(hits), path))
    at = hits[0]
    tail = line_terminator(lines[at])
    # The note shape IDEAS.md's own HOW TO USE comment prescribes — a one-line `(agent)`
    # annotation appended to the bullet — with the clock's time beside the date.
    lines[at] = "%s *(agent %s %s: %s)*%s" % (lines[at].rstrip(), date, clock_hm(now), note, tail)

    preview = [short(lines[at])]
    if args.dry_run:
        report(verb, path, at + 1, preview, True)
        return
    atomic_write(verb, path, "\n".join(lines))
    report(verb, path, at + 1, preview, False)


# ----------------------------------------------------------------------- entry ---------

def build_parser():
    parser = argparse.ArgumentParser(
        prog="vault-writes.py",
        description="The hand-composed writes of the vault, one asserted anchor at a time.")
    verbs = parser.add_subparsers(dest="verb", required=True)

    log = verbs.add_parser("log-append", help="append one entry to the wiki log")
    log.add_argument("--vault", required=True, help="the vault root; the path is derived")
    log.add_argument("--action", required=True, help="one of: %s" % " ".join(ACTIONS))
    log.add_argument("--title", required=True)
    log.add_argument("--changed", required=True)
    log.add_argument("--conflicts", required=True)
    log.add_argument("--extra", action="append", metavar="KEY: VALUE",
                     help="a further bullet, between Changed and Conflicts; repeatable")
    log.add_argument("--date", help="YYYY-MM-DD; today when absent")
    log.add_argument("--dry-run", action="store_true", help="print the block, write nothing")

    register = verbs.add_parser("register", help="the framework defect register")
    register_verbs = register.add_subparsers(dest="register_verb", required=True)

    add = register_verbs.add_parser("add", help="a new entry at the top of the Open section")
    add.add_argument("--vault", required=True)
    add.add_argument("--date", required=True)
    add.add_argument("--surface", required=True, help="surface — short title")
    add.add_argument("--symptom", required=True)
    add.add_argument("--cause", required=True)
    add.add_argument("--severity", required=True, help="one of: %s" % " ".join(SEVERITIES))
    add.add_argument("--status", required=True, help="verbatim, the leading 'open — ' too")
    add.add_argument("--where", help="omitted entirely when absent")
    add.add_argument("--dry-run", action="store_true", help="print the block, write nothing")

    close = register_verbs.add_parser("close", help="move one entry to the Closed section")
    close.add_argument("--vault", required=True)
    close.add_argument("--match", required=True, help="text of exactly one Open heading")
    close.add_argument("--date", required=True)
    close.add_argument("--status", required=True,
                       help="the text of the dated line; the clock stamps its time")
    close.add_argument("--dry-run", action="store_true", help="print the change, write nothing")

    ideas = verbs.add_parser("ideas", help="the scratchpad of the owner")
    ideas_verbs = ideas.add_subparsers(dest="ideas_verb", required=True)
    annotate = ideas_verbs.add_parser("annotate", help="append one agent note to one bullet")
    annotate.add_argument("--file", required=True)
    annotate.add_argument("--item", required=True, metavar="N")
    annotate.add_argument("--note", required=True)
    annotate.add_argument("--date", help="YYYY-MM-DD; today when absent")
    annotate.add_argument("--dry-run", action="store_true",
                          help="print the line, write nothing")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.verb == "log-append":
        cmd_log_append(args)
    elif args.verb == "register":
        (cmd_register_add if args.register_verb == "add" else cmd_register_close)(args)
    else:
        cmd_ideas_annotate(args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except OSError as exc:          # a read-only target, a full disk: one line, exit 2
        print("error vault-writes: %s" % exc)
        sys.exit(2)
