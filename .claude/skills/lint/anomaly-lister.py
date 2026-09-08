#!/usr/bin/env python3
"""anomaly-lister.py — the page-visible anomaly census a verify leg checks a report against.

A compile lane's report ends with an Anomalies section. Verifying it by hand means
re-reading every page the lane touched; this script instead lists what the PAGES
themselves say, so the verify leg is a comparison rather than a re-read.

Four kinds, all read straight off the page
  open-conflict  a Conflicts / Open Questions block (CLAUDE.md 4.4) whose text carries
                 no settled marker. An empty block records nothing, so it counts as an
                 empty block rather than an open one.
  flagged        a `flagged:` frontmatter line (the query/output staleness flag), with
                 its text, so the reason travels with the count.
  thin-page      prose saying the page rests on too little — single witness, single-source
                 stub, uncorroborated.
  unverified     inline `unverified` markers (CLAUDE.md 11), counted per page.

What is stripped before matching: fenced code blocks and HTML comments, neither of which
is page-visible prose. Inline code spans are KEPT, because the inline marker is habitually
written inside backticks and stripping spans would silently zero the commonest kind.

Counting the marker, two ways (`--unverified-form`, printed in the header)
  any        every occurrence of the word in visible prose. The default, and the honest
             census: it is a floor on nothing and a ceiling on nothing.
  backtick   only occurrences inside an inline code span, i.e. the MARKER form CLAUDE.md
             prescribes. Prose that discusses the marker rather than applying it — a
             design page explaining when to write it — drops out, so a verify leg that
             must compare like with like has a form to ask for.

Self-control (CLAUDE.md 11): every run analyses one synthetic page held in memory that
carries all four kinds (the marker in both forms, so the control vouches for whichever
`--unverified-form` is active) plus one empty conflict block, and prints
`anomaly-control: 4/4 … empty-conflict control: 1/1`. A miss prints PROBE FAILED and
exits 2 — an analyser that cannot find a planted anomaly cannot report a page clean.

A broken premise prints one plain `PROBE FAILED: …` line on stdout and exits 2 whatever
`--format` says, so a JSON consumer keys on the exit code, never on parsing that line.

Stdout only: this script never creates, modifies, moves or deletes a file.

Usage:
  python3 anomaly-lister.py [--vault ROOT] [--format text|json]
  python3 anomaly-lister.py --pages PATH [PATH ...] [--format text|json]
  optional: --settled-markers 'a|b|c'   --thin-regex 'x|y'   --unverified-form any|backtick
  exit 0 = the probe ran (findings or none) · exit 2 = broken premise
"""
import argparse
import glob
import json
import os
import re
import sys

KINDS = ("open-conflict", "flagged", "thin-page", "unverified")
UNVERIFIED_FORMS = ("any", "backtick")

# A conflict block is settled when its own text says so. Defaults chosen to match the
# vocabulary the vault's conflict blocks already use when they record an outcome.
DEFAULT_SETTLED = "settled|resolved|closed|adjudicated|superseded|reconciled|provenance|confirmed"
DEFAULT_THIN = "thin page|single witness|single-witness|single-source stub|only witness|uncorroborated"

CONFLICT_HEAD = re.compile(r"^(#{1,6})[ \t]*Conflicts\b.*$", re.M)
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---", re.S)
SPAN_RE = re.compile(r"`[^`\n]+`")
UNVERIFIED_RE = re.compile(r"unverified", re.I)
EXCERPT_CHARS = 140     # one terminal line minus the indent; set by judgement, unmeasured


def stdout_utf8():
    """Make stdout encode any page name, excerpt or separator this script prints.

    Without it an ascii stdout (PYTHONIOENCODING, a bare C locale on some builds) turns a
    unicode page name — or the run's own separator glyph — into a traceback and exit 1,
    which reads as neither a finding nor a probe failure.
    """
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass


def read_text(path):
    """Read a file as UTF-8, dropping a BOM and normalising CRLF; bad bytes are replaced.

    A BOM or a CRLF line ending would otherwise defeat the frontmatter match and hide a
    `flagged:` line inside a block this census would then read as prose.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")


def visible(text):
    """Drop what a reader never sees: fenced code blocks and HTML comments. Spans stay."""
    text = re.sub(r"```.*?```", "\n", text, flags=re.S)
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    return text


def excerpt(s):
    s = " ".join(s.split())
    return s if len(s) <= EXCERPT_CHARS else s[:EXCERPT_CHARS - 1] + "…"


def line_at(prose, pos):
    """The whole source line containing an offset, trimmed."""
    start = prose.rfind("\n", 0, pos) + 1
    end = prose.find("\n", pos)
    return prose[start:end if end != -1 else len(prose)].strip()


def unverified_hits(prose, form):
    """Offsets of each marker occurrence the ACTIVE form counts."""
    if form == "backtick":
        for span in SPAN_RE.finditer(prose):
            for m in UNVERIFIED_RE.finditer(span.group(0)):
                yield span.start() + m.start()
        return
    for m in UNVERIFIED_RE.finditer(prose):
        yield m.start()


def unclosed_frontmatter(text):
    """True when a page opens a frontmatter fence it never closes.

    Every key below such a fence is read as prose, so a `flagged:` line there is invisible
    to this census: the run reports the page rather than letting its count pass as zero.
    """
    return text.startswith("---\n") and not FRONTMATTER.match(text)


def analyse(text, settled_re, thin_re, form="any"):
    """Return {kind: [excerpt, ...]} plus an `empty-conflict` counter for one page's text.

    Pure text in, findings out — the vault pass and the self-control call the same function.
    """
    found = {k: [] for k in KINDS}
    empty_conflicts = 0

    fm = FRONTMATTER.match(text)
    if fm:
        for line in fm.group(1).split("\n"):
            if re.match(r"^flagged:", line):
                found["flagged"].append(excerpt(line.strip()))

    body = visible(text)
    lines = body.split("\n")
    for m in CONFLICT_HEAD.finditer(body):
        level = len(m.group(1))
        start = body[:m.start()].count("\n") + 1
        end = len(lines)
        for i in range(start, len(lines)):
            h = re.match(r"^(#{1,6})[ \t]", lines[i])
            if h and len(h.group(1)) <= level:
                end = i
                break
        block = "\n".join(lines[start:end]).strip()
        if not block:
            empty_conflicts += 1
        elif settled_re.search(block):
            continue                     # the block records its own settlement
        else:
            first = next((ln.strip() for ln in block.split("\n") if ln.strip()), "")
            found["open-conflict"].append(excerpt(first))

    # Re-match the frontmatter on the STRIPPED text: offsets into `body` are the only ones
    # valid here, and a match against the raw text would cut the prose at the wrong place
    # whenever stripping shortened anything above it.
    fm_body = FRONTMATTER.match(body)
    prose = body[fm_body.end():] if fm_body else body
    for m in thin_re.finditer(prose):
        found["thin-page"].append(excerpt(line_at(prose, m.start())))
    for pos in unverified_hits(prose, form):
        found["unverified"].append(excerpt(line_at(prose, pos)))

    return found, empty_conflicts


# A synthetic page carrying all four kinds, the marker in both forms, and one empty
# conflict block. In memory only; it never touches disk.
SELF_CONTROL_PAGE = (
    "---\n"
    "title: \"Self-control page\"\n"
    "type: concept\n"
    "flagged: 2026-01-01 mechanism may have changed since capture\n"
    "---\n\n"
    "## Definition\n"
    "A thin page resting on a single witness, so its claim stays `unverified` here, and it\n"
    "reads unverified in plain prose as well.\n\n"
    "## Conflicts / Open Questions\n"
    "- Two captures disagree on the figure and nothing decides between them.\n\n"
    "## Conflicts / Open Questions\n\n"
    "## Related\n"
    "- Another page.\n"
)


def run_self_control(settled_re, thin_re, form):
    """Prove the analyser finds all four kinds, then ask whether the ACTIVE markers hide one.

    The control runs on the DEFAULT marker set, because what it tests is the analyser, not
    the caller's configuration: an override wide enough to settle the synthetic block would
    otherwise fail the run for a reason that has nothing to do with the analyser working.
    It runs on the ACTIVE `--unverified-form`, because that one is a counting mode rather
    than a filter, and a control has to vouch for the counting the run actually does.
    The override is still attacked — a second pass under the active markers reports which
    kinds it swallows, as a warning, so a marker set that quietly zeroes a kind is visible.
    """
    default, empties = analyse(SELF_CONTROL_PAGE, re.compile(DEFAULT_SETTLED, re.I),
                               re.compile(DEFAULT_THIN, re.I), form)
    caught = [k for k in KINDS if default[k]]
    active = analyse(SELF_CONTROL_PAGE, settled_re, thin_re, form)[0]
    swallowed = [k for k in KINDS if default[k] and not active[k]]
    return caught, swallowed, empties


def assert_vault_root(root):
    """A root must hold raw/ AND wiki/ or the census refuses to run.

    The 2026-08-26 standard, closed for the capture layer and swept here on 2026-09-07: fail
    loud on stderr, never a wrong-tree scan that reports a clean vault on a scan of nothing.
    """
    if not all(os.path.isdir(os.path.join(root, d)) for d in ("raw", "wiki")):
        print(f"PROBE FAILED: {root} is not a vault root (no raw/ or wiki/)", file=sys.stderr)
        raise SystemExit(2)
    return root


def main():
    stdout_utf8()
    ap = argparse.ArgumentParser(description="Page-visible anomaly census for wiki pages.")
    ap.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    ap.add_argument("--pages", nargs="+", help="check exactly these pages instead of the vault")
    ap.add_argument("--settled-markers", default=DEFAULT_SETTLED,
                    help="regex alternation marking a conflict block settled")
    ap.add_argument("--thin-regex", default=DEFAULT_THIN,
                    help="regex matching a thin-page note")
    ap.add_argument("--unverified-form", choices=UNVERIFIED_FORMS, default="any",
                    help="count every occurrence of the word (any, the default) or only the "
                         "backticked marker form (backtick)")
    ap.add_argument("--format", choices=("text", "json"), default="text",
                    help="output format (default: text)")
    args = ap.parse_args()

    try:
        settled_re = re.compile(args.settled_markers, re.I)
        thin_re = re.compile(args.thin_regex, re.I)
    except re.error as exc:
        print(f"PROBE FAILED: bad regex: {exc}")
        return 2

    form = args.unverified_form
    caught, swallowed, control_empties = run_self_control(settled_re, thin_re, form)
    if len(caught) != len(KINDS):
        missed = [k for k in KINDS if k not in caught]
        print(f"PROBE FAILED: anomaly-control {len(caught)}/{len(KINDS)} — "
              f"analyser missed {', '.join(missed)}")
        return 2
    if control_empties != 1:
        print(f"PROBE FAILED: empty-conflict control {control_empties}/1 — the planted empty "
              f"block was not counted, so an empty-block total of zero would prove nothing")
        return 2

    root = os.path.abspath(os.path.expanduser(args.vault))
    if args.pages:
        mode = "pages"
        pages = [os.path.abspath(os.path.expanduser(p)) for p in args.pages]
        missing = [p for p in pages if not os.path.isfile(p)]
        if missing:
            print(f"PROBE FAILED: {len(missing)} named page(s) not on disk: "
                  f"{', '.join(os.path.basename(m) for m in missing)}")
            return 2
    else:
        mode = "vault"
        root = assert_vault_root(root)     # vault mode only: --pages names its own files
        wiki = os.path.join(root, "wiki")
        if not os.path.isdir(wiki):        # unreachable while the root guard runs first
            print(f"PROBE FAILED: no wiki directory under {args.vault}")
            return 2
        # log.md is append-only history, not a page whose anomalies anyone reconciles.
        pages = [p for p in sorted(glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True))
                 if os.path.basename(p) != "log.md"]
        if not pages:
            print("PROBE FAILED: wiki directory holds no Markdown pages")
            return 2

    results, empty_total, malformed = {}, 0, []
    for p in pages:
        try:
            rel = os.path.relpath(p, root)
        except ValueError:
            rel = p
        try:
            text = read_text(p)
        except OSError as exc:
            print(f"PROBE FAILED: cannot read {rel}: {exc}")
            return 2
        if unclosed_frontmatter(text):
            malformed.append(rel)
        found, empties = analyse(text, settled_re, thin_re, form)
        empty_total += empties
        if any(found[k] for k in KINDS):
            results[rel] = {k: found[k] for k in KINDS if found[k]}

    summary = {k: sum(len(v.get(k, [])) for v in results.values()) for k in KINDS}
    control = f"{len(caught)}/{len(KINDS)}"

    if args.format == "json":
        print(json.dumps({
            "mode": mode, "root": args.vault, "pages": len(pages),
            "settled_markers": args.settled_markers, "thin_regex": args.thin_regex,
            "unverified_form": form,
            "findings": results, "pages_with_findings": len(results),
            "summary": summary, "empty_conflict_blocks": empty_total,
            "anomaly_control": control, "empty_conflict_control": control_empties,
            "markers_swallow": swallowed, "malformed_frontmatter": malformed,
        }, indent=2, sort_keys=True))
        return 0

    print(f"anomaly-lister: mode={mode} · root={args.vault} · kinds={','.join(KINDS)} · "
          f"unverified-form={form} · excerpt={EXCERPT_CHARS} chars · format=text")
    print(f"settled-markers={args.settled_markers}")
    print(f"thin-regex={args.thin_regex}")
    print(f"scanned: {len(pages)} pages (log.md excluded in vault mode)")
    for rel in sorted(results):
        print(rel)
        for kind in KINDS:
            items = results[rel].get(kind)
            if items:
                print(f"  {kind} ({len(items)}) — {items[0]}")
    print("summary: " + " · ".join(f"{k} {summary[k]}" for k in KINDS) +
          f"   (across {len(results)} pages; {empty_total} empty conflict blocks)")
    print(f"anomaly-control: {control} (on the default markers — the analyser's own capability) "
          f"· empty-conflict control: {control_empties}/1")
    if swallowed:
        print(f"marker-override warning: the active markers also hide {', '.join(swallowed)} "
              f"on the control page, so that kind's count here is a floor, not a census")
    if malformed:
        print(f"frontmatter warning: {len(malformed)} page(s) open a --- fence they never close, "
              f"so any frontmatter key there reads as prose and their flagged count is a floor")
        for rel in malformed:
            print("  " + rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
