#!/usr/bin/env python3
"""check-orphans.py — inbound-link (orphan) census for the wiki layer.

Mechanises the one link check the lint skill still leaves to the agent
("Orphans are agent-checked", lint SKILL.md Step 2). A page is an ORPHAN when no
OTHER page carries a resolving page link to it. Exempt from being reported:
`index.md`, `log.md`, and every page under `maps/` — Maps of Content are
navigational entry points by design, not orphans.

Link rules are the ones in this directory's check-links.py, applied identically:
  - fenced code blocks, inline code spans and HTML comments are stripped first,
    so documentation examples are not links;
  - `log.md` is excluded as a link SOURCE (append-only history), so a page linked
    only from the log is still an orphan;
  - media embeds are classified by the same extension set, so an embedded image
    is never counted as a page link;
  - targets resolve as Obsidian does: page stems -> frontmatter aliases ->
    vault-relative paths (with or without .md) -> basename, case-insensitively;
  - the alias form and the section form both credit the same page;
  - a page linking to itself does not make itself non-orphan.
check-links.py is a top-level script — it reads argv and calls sys.exit while
being imported — so those rules are REPLICATED here rather than imported. The
suite beside this file runs both scripts over one fixture and fails if their link
counts diverge, which is what keeps the replica honest; exposing those rules as
functions there would retire the replica altogether.

Two deliberate differences from that replica, both narrower than they look:
  - RESOLUTION stops at the wiki layer. check-links.py asks only "does this
    target exist anywhere in the vault", because a link into assets/ or output/
    is live; an inbound-link census instead has to credit a wiki PAGE, so a
    target outside the wiki credits nothing. Link COUNTING is identical, which
    is what the suite's agreement leg asserts against check-links.py.
  - Bytes are decoded permissively, a BOM is dropped and CRLF is normalised, so a
    CRLF page's frontmatter aliases are still read. check-links.py reads strict
    UTF-8 without normalising, so those aliases are invisible to it and an aliased
    CRLF page reads as dead there; giving it the same reader removes the difference.

`index.md` counts as a link source, because the rule this implements is the graph
rule (no isolated nodes) and the catalogue is a node like any other. That makes
the bare orphan count weak on its own, so the run also reports how many pages the
catalogue alone reaches: an "index-only" page is one nothing but the catalogue
points at. That is information, not a finding.

A broken premise prints one plain `PROBE FAILED: …` line on stdout and exits 2
whatever `--format` says, so a JSON consumer keys on the exit code, never on
parsing that line.

Stdout only: this script never creates, modifies, moves or deletes a file.

Usage:
  python3 check-orphans.py [--vault ROOT] [--format text|json]
  exit 0 = the probe ran (findings or none) · exit 2 = broken premise
"""
import argparse
import glob
import json
import os
import re
import sys

# Obsidian treats these embed targets as media rather than page transclusions; kept
# byte-identical to check-links.py so both scripts classify a link the same way.
MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf",
             ".mp3", ".wav", ".mp4", ".mov"}

LINK_RE = re.compile(r"(!?)\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]")


def stdout_utf8():
    """Make stdout encode any page name or separator this script prints.

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

    A BOM or a CRLF line ending would otherwise defeat the `\\A---\\n` frontmatter match and
    silently drop that page's aliases, which would report an aliased page as an orphan.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")


def strip_noise(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)     # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                  # inline code spans
    return text


def frontmatter_block(text):
    m = re.match(r"\A---\n(.*?)\n---", text, re.S)
    return m.group(1) if m else ""


def collect_aliases(pages, texts):
    """alias -> page path, following check-links.py: inline list first, then block list."""
    aliases = {}
    for p in pages:
        block = frontmatter_block(texts[p])
        if not block:
            continue
        m = re.search(r"^aliases:\s*\[([^\]]*)\]", block, re.M)
        if m:
            vals = m.group(1).split(",")
        else:
            m2 = re.search(r"^aliases:\s*\n((?:\s*-\s*.+\n?)+)", block, re.M)
            vals = re.findall(r"-\s*(.+)", m2.group(1)) if m2 else []
        for a in vals:
            a = a.strip().strip("\"'")
            if a:
                aliases[a] = p
    return aliases


def build_indexes(pages):
    stems, lower_stems = {}, {}
    for p in pages:
        s = os.path.splitext(os.path.basename(p))[0]
        stems.setdefault(s, []).append(p)
        lower_stems.setdefault(s.lower(), []).append(p)
    return stems, lower_stems


def resolve(target, root, stems, lower_stems, aliases, page_set):
    """Return the wiki pages a link target credits (empty when it leaves the wiki layer).

    Resolution order mirrors check-links.py exactly: stem, alias, vault-relative path,
    root doc, then case-folded basename. A stem shared by several pages credits all of
    them — the permissive reading check-links.py already takes for ambiguous basenames.
    """
    t = target.strip().rstrip("\\")     # a table-escaped pipe leaves a trailing backslash
    if not t or t.startswith("#"):
        return []                        # self-heading link
    t = t.split("#", 1)[0].strip()
    if not t:
        return []
    if t in stems:
        return stems[t]
    if t in aliases:
        return [aliases[t]]
    if "/" in t or t.endswith(".md"):
        for cand in (t, t + ".md"):
            full = os.path.normpath(os.path.join(root, cand))
            if full in page_set:
                return [full]
            if os.path.exists(full):
                return []                # resolves, but outside the wiki layer
    full = os.path.normpath(os.path.join(root, t + ".md"))
    if full in page_set:
        return [full]
    if os.path.exists(full):
        return []
    base = os.path.basename(t).lower()
    for key in (base, os.path.splitext(base)[0]):
        if key in lower_stems:
            return lower_stems[key]
    return []


def is_exempt(rel):
    """index.md, log.md and every maps/ page are never reported as orphans."""
    parts = rel.split(os.sep)
    return parts[-1] in ("index.md", "log.md") or (len(parts) > 1 and parts[1] == "maps")


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
    ap = argparse.ArgumentParser(description="Orphan (no-inbound-link) census for the wiki layer.")
    ap.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    ap.add_argument("--format", choices=("text", "json"), default="text",
                    help="output format (default: text)")
    args = ap.parse_args()

    root = assert_vault_root(os.path.abspath(os.path.expanduser(args.vault)))
    wiki = os.path.join(root, "wiki")
    if not os.path.isdir(wiki):   # unreachable while the root guard runs first; kept as depth
        print(f"PROBE FAILED: no wiki directory under {args.vault} (wrong root?)")
        return 2

    pages = sorted(os.path.normpath(p) for p in
                   glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True))
    if not pages:
        print("PROBE FAILED: wiki directory holds no Markdown pages")
        return 2

    try:
        texts = {p: read_text(p) for p in pages}
    except OSError as exc:
        print(f"PROBE FAILED: cannot read a wiki page: {exc}")
        return 2
    page_set = set(pages)
    stems, lower_stems = build_indexes(pages)
    aliases = collect_aliases(pages, texts)

    index_path = os.path.normpath(os.path.join(wiki, "index.md"))
    inbound = {p: set() for p in pages}
    links_scanned = embeds_skipped = 0
    for src in pages:
        if os.path.basename(src) == "log.md":
            continue                      # append-only history is not a link source
        body = strip_noise(texts[src])
        for is_embed, target in LINK_RE.findall(body):
            head = target.split("#", 1)[0].strip().rstrip("\\")
            if is_embed and os.path.splitext(head)[1].lower() in MEDIA_EXT:
                embeds_skipped += 1
                continue                  # media embed, not a page link
            links_scanned += 1
            for tgt in resolve(target, root, stems, lower_stems, aliases, page_set):
                if tgt != src:            # a self-link is not an inbound link
                    inbound[tgt].add(src)

    if links_scanned == 0:
        print("PROBE FAILED: zero page links scanned (nothing to census)")
        return 2

    candidates = [p for p in pages if not is_exempt(os.path.relpath(p, root))]
    orphans = sorted(os.path.relpath(p, root) for p in candidates if not inbound[p])
    with_inbound = sum(1 for p in pages if inbound[p])
    index_only = sorted(os.path.relpath(p, root) for p in candidates
                        if inbound[p] == {index_path})

    if args.format == "json":
        print(json.dumps({
            "root": args.vault,
            "pages": len(pages),
            "candidates": len(candidates),
            "exempt": len(pages) - len(candidates),
            "links_scanned": links_scanned,
            "embeds_skipped": embeds_skipped,
            "orphans": orphans,
            "orphan_count": len(orphans),
            "inbound_control": with_inbound,
            "index_only": index_only,
        }, indent=2, sort_keys=True))
        return 0

    print(f"check-orphans: root={args.vault} · exempt=index.md,log.md,maps/ · "
          f"log.md excluded as a link source · format=text")
    print(f"scanned: {len(pages)} pages · {links_scanned} page links · "
          f"{len(stems)} stems · {len(aliases)} aliases   (nonzero totals = the probe ran)")
    print(f"orphans: {len(orphans)} (of {len(candidates)} pages; exempt index/log/maps) · "
          f"inbound-control: {with_inbound} pages carry >=1 inbound link")
    for o in orphans:
        print("  " + o)
    print(f"index-only inbound: {len(index_only)} pages reached by the catalogue alone (information, not a finding)")
    for p in index_only:
        print("  " + p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
