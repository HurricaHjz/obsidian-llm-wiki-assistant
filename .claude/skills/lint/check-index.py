#!/usr/bin/env python3
"""Index-consistency census: wiki/index.md against the pages on disk.

Lint Step 1 used to be an agent Read of the index plus a glob and a hand comparison — the
"re-derive a count by hand" the lint Routing note forbids. This is that comparison as a
script, so the agent reads a report instead of counting.

The rules are deep-lint's, not new ones: `.claude/skills/deep-lint/audit-pools.py` already
computes index consistency, and this script reuses its definitions so the two cannot drift.
  - the index is `wiki/index.md`; the pages are every `wiki/**/*.md` except `wiki/index.md`
    and `wiki/log.md` (matched on the relative path, so a nested page called index.md
    elsewhere under wiki/ is still a page — audit-pools.py's INDEX_REL / LOG_REL rule);
  - an index ENTRY is a list line whose first item is a wikilink, then an em-dashed line of
    description — the format the index's own header states; fenced blocks, inline code spans
    and HTML comments are stripped first, so the example in that header, which is written
    inside a code span, is not read as an entry;
  - a target resolves the way Obsidian resolves it: on the basename, with or without the
    `.md` extension, case-folded (audit-pools.py's link_key);
  - a page's frontmatter `aliases:` count as resolutions on BOTH sides — an entry naming an
    alias is not dangling, and a page registered under an alias is not unindexed. (Deliberate
    departure: audit-pools.py applies aliases to the dangling side only, which reports a page
    registered under its alias as unindexed. The banner says the alias rule is on.)

Three lists, each with its count:
  UNINDEXED   pages on disk that no index entry registers;
  DANGLING    index entries whose target is no page on disk (nor any alias);
  DUPLICATE   the same target registered by more than one entry.

`SCANNED: <pages> pages · <entries> index entries` is the run's own positive control (§11):
zero findings with a zero scanned count is a broken probe, never a clean index.

A broken premise prints one plain `PROBE FAILED: …` line and exits 2 — a root that is not a
vault (no raw/ + wiki/, on stderr, the 2026-08-26 standard), a missing wiki/index.md, an
index that registers nothing, no pages on disk, an unreadable page. An unknown option is
refused with exit 2 rather than ignored.

Stdout only: this script never creates, modifies, moves or deletes a file.

Usage:
  python3 check-index.py [--vault ROOT]
  exit 0 = the probe ran (findings or none) · exit 2 = broken premise
"""
import argparse
import glob
import os
import re
import sys

INDEX_REL = "wiki/index.md"
LOG_REL = "wiki/log.md"
ENTRY_RE = re.compile(r"^[ \t]*[-*][ \t]*!?\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]", re.M)


def stdout_utf8():
    """Make stdout encode any page name this script prints.

    Without it an ascii stdout (PYTHONIOENCODING, a bare C locale on some builds) turns a
    unicode page name into a traceback and exit 1, which reads as neither a finding nor a
    probe failure.
    """
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass


def assert_vault_root(root):
    """A root must hold raw/ AND wiki/ or the census refuses to run.

    The 2026-08-26 standard, closed for the capture layer and swept across this directory on
    2026-09-07: fail loud on stderr, never a wrong-tree scan reported as a clean index.
    """
    if not all(os.path.isdir(os.path.join(root, d)) for d in ("raw", "wiki")):
        print(f"PROBE FAILED: {root} is not a vault root (no raw/ or wiki/)", file=sys.stderr)
        raise SystemExit(2)
    return root


def read_text(path):
    """Read a file as UTF-8, dropping a BOM and normalising CRLF; bad bytes are replaced.

    A BOM or a CRLF line ending would otherwise defeat the frontmatter match and drop that
    page's aliases, which would report a registered page as dangling.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")


def strip_noise(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)     # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                  # inline code spans
    return text


def link_key(target):
    """Obsidian resolves on the basename, with or without the extension (audit-pools.py)."""
    key = os.path.basename(target.strip().rstrip("\\").split("#", 1)[0].strip()).casefold()
    return key[:-3] if key.endswith(".md") else key


def page_aliases(text):
    """Frontmatter aliases, inline list first then block list — check-links.py's reader."""
    fm = re.match(r"\A---\n(.*?)\n---", text, re.S)
    if not fm:
        return []
    block = fm.group(1)
    m = re.search(r"^aliases:\s*\[([^\]]*)\]", block, re.M)
    if m:
        vals = m.group(1).split(",")
    else:
        m2 = re.search(r"^aliases:\s*\n((?:\s*-\s*.+\n?)+)", block, re.M)
        vals = re.findall(r"-\s*(.+)", m2.group(1)) if m2 else []
    return [a.strip().strip("\"'") for a in vals if a.strip().strip("\"'")]


def main():
    stdout_utf8()
    ap = argparse.ArgumentParser(
        description="Index-consistency census: wiki/index.md against the pages on disk.")
    ap.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    args = ap.parse_args()

    root = assert_vault_root(os.path.abspath(os.path.expanduser(args.vault)))
    index_path = os.path.join(root, "wiki", "index.md")
    if not os.path.isfile(index_path):
        print(f"PROBE FAILED: no {INDEX_REL} under {root}")
        return 2

    paths = sorted(os.path.normpath(p) for p in
                   glob.glob(os.path.join(root, "wiki", "**", "*.md"), recursive=True))
    try:
        texts = {p: read_text(p) for p in paths}
    except OSError as exc:
        print(f"PROBE FAILED: cannot read a wiki page: {exc}")
        return 2

    # stem -> every page carrying it. Two folders may hold the same stem (a benchmark page and
    # its source page, say); a stem -> one-path map drops all but one, and an unindexed sibling
    # then disappears from the finding instead of being reported (audit-pools.py's note).
    on_disk, names, aliased = {}, {}, {}
    for p in paths:
        rel = os.path.relpath(p, root).replace(os.sep, "/")
        if rel in (INDEX_REL, LOG_REL):
            continue
        stem = link_key(rel)
        on_disk.setdefault(stem, []).append(rel)
        names.setdefault(stem, []).append(rel)
        for alias in page_aliases(texts[p]):
            key = link_key(alias)
            names.setdefault(key, []).append(rel)
            aliased.setdefault(rel, []).append(key)
    pages_on_disk = sum(len(rels) for rels in on_disk.values())
    if not pages_on_disk:
        print("PROBE FAILED: wiki directory holds no pages besides the two registries")
        return 2

    entries = [link_key(t) for t in ENTRY_RE.findall(strip_noise(texts[index_path]))]
    if not entries:
        print(f"PROBE FAILED: {INDEX_REL} registers no page — the index probe is broken")
        return 2
    registered = set(entries)

    unindexed = sorted(rel for stem, rels in on_disk.items() for rel in rels
                       if stem not in registered
                       and not any(a in registered for a in aliased.get(rel, [])))
    dangling = sorted(name for name in registered if name not in names)
    duplicates = sorted({name for name in entries if entries.count(name) > 1})
    shared = sorted(stem for stem, rels in on_disk.items() if len(rels) > 1)

    print(f"SCANNED: {pages_on_disk} pages · {len(entries)} index entries "
          f"({len(registered)} distinct targets; frontmatter aliases count as a resolution "
          "on both sides)   (nonzero totals = probe ran)")
    print(f"UNINDEXED PAGES: {len(unindexed)}")
    for rel in unindexed:
        print("  " + rel)
    print(f"DANGLING INDEX ENTRIES: {len(dangling)}")
    for name in dangling:
        print("  " + name)
    print(f"DUPLICATE INDEX ENTRIES: {len(duplicates)}")
    for name in duplicates:
        print(f"  {name} · {entries.count(name)} entries")
    # Information, not a finding: one entry registers every page sharing that stem, so a shared
    # stem is where "registered" covers more than one file.
    print(f"shared stems (information, not a finding): {len(shared)}")
    for stem in shared:
        print(f"  {stem} · {', '.join(on_disk[stem])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
