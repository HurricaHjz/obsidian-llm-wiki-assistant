#!/usr/bin/env python3
"""Report source pages that admit conversion damage in prose while carrying no conversion flag.

Stdout-only by construction: reads pages, prints, writes nothing.

Why (known-issues 2026-09-08, ingest Step 0 conversions): fourteen source pages recorded a
damaged conversion — in a `depth:` comment, a sentence in the summary, a note that the verbatim
quotation is unavailable — and only five raised a `flagged:` line. deep-lint's Step 2 reads the
flag channel and nothing else, so a damage admission written as prose is invisible to it. This
probe keys on the observable, the damage vocabulary, never on a named file:
    collapsed · lost inter-word spaces · inter-word · space-restored · run-together ·
    run together · verbatim quotation is unavailable · lost every chart · lost every figure ·
    lost every table · charts lost · figures lost
A page under wiki/sources/ whose frontmatter (any line, comments included) or body matches one
of those, case-insensitively, while its frontmatter carries no CONVERSION flag, is a finding.
The negative is keyed on the flag's own text: a `flagged:` line counts only when its value
carries the word `conversion` (`source conversion suspect …`, `conversion damage …`); a flag
about something else (`flagged: 2026-09-01 stale pricing table`) does not mask an admission,
since deep-lint would resolve that flag without ever reading the conversion. Fenced code, code
spans and HTML comments are NOT stripped: a comment is exactly where such an admission hides,
and a quotation of the vocabulary inside a source page is worth a look too.

Terminal state (ingest Step 0, 3c): a conversion flag is resolved when a repaired conversion
scored `clean` joins the page's `sources:` and the page's `## Summary` ends with a dated
Provenance sentence naming the repair file and the quotation check. That sentence necessarily
admits the old damage (it says what was repaired), so an admission line that also carries the
words `repaired conversion` is RESOLVED: counted under its own line, listed, never a finding.

Controls, in memory, before the scan: the damage sentence with no flag must be caught; the same
page with a conversion `flagged:` must not be a finding; with a non-conversion `flagged:` it must
be caught again; and its admission line rewritten as a Provenance sentence naming a repaired
conversion must read resolved. Every result prints, and a control that fails is a PROBE FAILED
(exit 2). The scan totals print as the positive control on the count.

Usage (from the vault root):
  python3 .claude/skills/lint/check_flag_admissions.py [--vault ROOT] [ROOT]
  exit 0 = clean · 1 = findings · 2 = broken premise (not a vault root, no wiki/sources/, no
  page in it, a control that did not fire)
"""
import os
import re
import sys

USAGE = ("usage: check_flag_admissions.py [--vault ROOT] [ROOT]   "
         "(exit 0 clean · 1 findings · 2 broken premise)")

VOCABULARY = re.compile(
    r"\bcollapsed\b"
    r"|\blost inter-word spaces\b"
    r"|\binter-word\b"
    r"|\bspace-restored\b"
    r"|\brun-together\b"
    r"|\brun together\b"
    r"|\bverbatim quotation is unavailable\b"
    r"|\blost every chart\b"
    r"|\blost every figure\b"
    r"|\blost every table\b"
    r"|\bcharts lost\b"
    r"|\bfigures lost\b",
    re.I,
)
FM_RE = re.compile(r"\A---[ \t]*\n(.*?\n)---[ \t]*(?:\n|\Z)", re.S)
FLAGGED_LINE_RE = re.compile(r"^flagged:[ \t]*(.*?)[ \t]*$", re.M)
CONVERSION_FLAG_RE = re.compile(r"\bconversion\b", re.I)      # `conversion` or `source conversion`
RESOLVED_RE = re.compile(r"\brepaired conversion\b", re.I)

CONTROL_PAGE = (
    "---\ntitle: \"Control\"\ntype: source\nconfidence: medium\n"
    "depth: standard # the conversion is run-together in places\n---\n\n"
    "## Summary\nThe source conversion collapsed inter-word spaces, so the verbatim quotation is unavailable.\n"
)
CONTROL_FLAGGED = CONTROL_PAGE.replace("confidence: medium\n",
                                       "confidence: medium\nflagged: 2026-01-01 source conversion suspect\n")
CONTROL_OTHER_FLAG = CONTROL_PAGE.replace("confidence: medium\n",
                                          "confidence: medium\nflagged: 2026-01-01 stale pricing table, re-read\n")
CONTROL_RESOLVED = (
    "---\ntitle: \"Control\"\ntype: source\nconfidence: medium\n---\n\n"
    "## Summary\nProvenance (2026-01-02): compiled from a damaged conversion (run-together prose); "
    "repaired conversion `raw/2-papers/example-repair.md` (clean); quotation check: 3 confirmed, 1 corrected, 0 unverifiable.\n"
)


def probe_failed(message):
    print(f"PROBE FAILED: {message}", file=sys.stderr)
    raise SystemExit(2)


def parse_root(argv):
    """The sibling flag spelling or the historical positional form; an unknown flag is
    refused, never swallowed as a root (known-issues 2026-09-06)."""
    root, rest = None, list(argv)
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            print(USAGE)
            raise SystemExit(0)
        if arg == "--vault":
            if not rest:
                probe_failed("--vault needs a directory argument")
            arg = rest.pop(0)
        elif arg.startswith("--vault="):
            arg = arg.split("=", 1)[1]
        elif arg.startswith("-"):
            probe_failed(f"unknown option {arg} ({USAGE})")
        if root is not None:
            probe_failed(f"two roots given ({root} and {arg})")
        root = arg
    return root if root else "."


def read_text(path):
    """UTF-8 with a BOM dropped and CRLF normalised; bad bytes replaced, never fatal."""
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")


def scan_page(text):
    """(has_flag, has_conversion_flag, hits, resolved): hits and resolved are (line number,
    matched term, line) over the whole page, the `flagged:` lines themselves excluded from
    matching; a matching line that also names a repaired conversion goes to resolved."""
    fm = FM_RE.match(text)
    flags = FLAGGED_LINE_RE.findall(fm.group(1)) if fm else []
    has_flag = bool(flags)
    has_conversion_flag = any(CONVERSION_FLAG_RE.search(v) for v in flags)
    hits, resolved = [], []
    for n, line in enumerate(text.split("\n"), 1):
        if line.startswith("flagged:"):
            continue
        m = VOCABULARY.search(line)
        if not m:
            continue
        entry = (n, m.group(0), line.strip())
        (resolved if RESOLVED_RE.search(line) else hits).append(entry)
    return has_flag, has_conversion_flag, hits, resolved


def show(line):
    return line if len(line) <= 120 else line[:117] + "..."


def main():
    root = parse_root(sys.argv[1:])
    if not all(os.path.isdir(os.path.join(root, d)) for d in ("raw", "wiki")):
        probe_failed(f"{root} is not a vault root (no raw/ or wiki/)")
    sources = os.path.join(root, "wiki", "sources")
    if not os.path.isdir(sources):
        probe_failed(f"{sources} does not exist — nothing to scan")

    # Controls first: a probe whose regex cannot fire must never print a clean scan.
    flag_c, conv_c, hits_c, res_c = scan_page(CONTROL_PAGE)
    flag_f, conv_f, hits_f, res_f = scan_page(CONTROL_FLAGGED)
    flag_o, conv_o, hits_o, res_o = scan_page(CONTROL_OTHER_FLAG)
    flag_r, conv_r, hits_r, res_r = scan_page(CONTROL_RESOLVED)
    if flag_c or conv_c or not hits_c or res_c:
        probe_failed("the in-memory control page (damage prose, no flagged: key) was not caught")
    if not flag_f or not conv_f or not hits_f:
        probe_failed("the conversion-flagged control page was not read as flagged")
    if not flag_o or conv_o or not hits_o:
        probe_failed("the control page with a non-conversion flag was not read as an unmasked admission")
    if flag_r or hits_r or len(res_r) != 1:
        probe_failed("the control page naming a repaired conversion was not read as resolved")

    pages = []
    for dirpath, dirnames, filenames in os.walk(sources):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if name.endswith(".md"):
                pages.append(os.path.join(dirpath, name))
    if not pages:
        probe_failed(f"{sources} holds no .md page")

    flagged = conversion_flagged = matched = 0
    findings, resolved_pages = [], []
    for path in pages:
        try:
            text = read_text(path)
        except OSError as exc:
            probe_failed(f"cannot read {path}: {exc}")
        has_flag, has_conv, hits, resolved = scan_page(text)
        flagged += has_flag
        conversion_flagged += has_conv
        matched += bool(hits or resolved)
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        if resolved:
            resolved_pages.append((rel, resolved))
        if hits and not has_conv:
            findings.append((rel, hits))

    print(f"SCANNED: {len(pages)} pages under wiki/sources/ | {flagged} carry flagged: "
          f"({conversion_flagged} conversion) | {matched} match the damage vocabulary   "
          f"(nonzero page total = probe ran)")
    print(f"CONTROL: in-memory page admitting damage without flagged: -> caught "
          f"({len(hits_c)} term(s): {', '.join(sorted({h[1].lower() for h in hits_c}))}); "
          f"with a conversion flagged: -> not a finding; with a non-conversion flagged: -> caught; "
          f"its admission rewritten as a Provenance sentence naming a repaired conversion -> resolved")
    n_res = sum(len(r) for _, r in resolved_pages)
    print(f"RESOLVED: {n_res} line(s) on {len(resolved_pages)} page(s) — an admission that also names "
          f"a repaired conversion (the terminal state; never a finding)")
    for rel, entries in resolved_pages:
        for n, term, line in entries:
            print(f"  {rel}:{n} · {term} · {show(line)}")
    print(f"ADMISSIONS WITHOUT FLAG: {len(findings)}")
    for rel, hits in findings:
        for n, term, line in hits:
            print(f"  {rel}:{n} · {term} · {show(line)}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
