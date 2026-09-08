#!/usr/bin/env python3
"""Deterministic wikilink + embed checker for the wiki/ layer.

Shared by `lint` (routine scan) and `deep-lint` (structural pass) so every run applies
identical rules instead of re-deriving an ad-hoc scanner. Rules encoded here:
  - scans wiki/**/*.md; wiki/log.md is EXCLUDED as a link source (append-only history);
  - fenced code blocks, inline code spans and HTML comments are stripped before extraction
    (documentation examples like `[[wikilink]]` are not links);
  - page links resolve the way Obsidian does: wiki page stems -> frontmatter aliases ->
    vault-relative paths (with or without .md) -> any visible file's basename, with or
    without the extension. Obsidian keys its own lookup on the basename *including* the
    extension over every non-dot path in the vault, so a narrower rule reports live links
    as dead ([[index.md]], [[Claude Code.md]], [[choices-quick-reference]] in output/, and
    every attic target all resolve in the app);
  - media embeds ![[name.ext]] resolve against assets/ (the attachment folder) and are
    reported separately as dead embeds when missing — they are checked, not skipped;
  - frontmatter `sources:` entries that name a vault path are resolved against disk and
    reported separately as DANGLING SOURCES (provenance is a reference, not only prose);
  - prints scan totals as its own positive control (a zero-findings run with zero links
    scanned is a broken probe, per CLAUDE.md §11);
  - refuses a root that is not a vault (no raw/ + wiki/): PROBE FAILED on stderr, exit 2.

Usage (from the vault root):
  python3 .claude/skills/lint/check-links.py [--vault ROOT] [ROOT]
  exit 0 = clean · 1 = findings · 2 = broken premise
"""
import os
import re
import sys
import glob

USAGE = "usage: check-links.py [--vault ROOT] [ROOT]   (exit 0 clean · 1 findings · 2 broken premise)"


def probe_failed(message):
    """One line on stderr, exit 2 — the fail-loud premise convention, so no caller reads a
    refused run as a clean one."""
    print(f"PROBE FAILED: {message}", file=sys.stderr)
    raise SystemExit(2)


def parse_root(argv):
    """Take the root from the sibling flag spelling or the historical positional form.

    An unrecognised flag is refused, never swallowed as a root: `--vault X` used to set the
    root to the literal string "--vault", so the scan opened nothing and still printed a
    clean bill of health (known-issues 2026-09-06).
    """
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


def assert_vault_root(candidate):
    """A root must hold raw/ AND wiki/ or the scan refuses to run.

    The 2026-08-26 standard closed for gather/capture_write.py: fail loud, never a wrong-tree
    scan that reports a clean vault on a scan of nothing.
    """
    if not all(os.path.isdir(os.path.join(candidate, d)) for d in ("raw", "wiki")):
        probe_failed(f"{candidate} is not a vault root (no raw/ or wiki/)")
    return candidate


root = assert_vault_root(parse_root(sys.argv[1:]))
wiki = os.path.join(root, "wiki")

MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf", ".mp3", ".wav", ".mp4", ".mov"}

files = sorted(glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True))
stems = {os.path.splitext(os.path.basename(p))[0] for p in files}


def read_text(path):
    """UTF-8 with a BOM dropped and CRLF normalised; bad bytes replaced, never fatal.
    A BOM or a CRLF line ending defeats the frontmatter match, so the page's aliases go
    uncollected and every link through them reads as dead."""
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")

# Obsidian's resolver (uniqueFileLookup) is keyed on each visible file's basename INCLUDING the
# extension, across the whole vault; dot-folders are invisible to it. Model the same surface or
# valid links read as dead. Ambiguous basenames are treated as resolving: for a dead-link checker,
# erring permissive avoids false alarms, and Obsidian falls back to path resolution there anyway.
vault_basenames = set()
for _dir, _subdirs, _names in os.walk(root):
    _subdirs[:] = [d for d in _subdirs if not d.startswith(".")]
    for _n in _names:
        if not _n.startswith("."):
            vault_basenames.add(_n.lower())

# --- sources: provenance resolution -------------------------------------------------------
# Classification of one `sources:` entry, in this order (the order matters: an email address
# ends in a dot-extension, so the prose test has to run before the path test). The counts
# beside each rule are what the live vault held when the rule was derived (1,256 entries on
# 686 pages, measured 2026-09-07 with this same parser):
#   url        a scheme form — never resolved against disk                              (54)
#   annotated  the entry itself declares the file gone: "path (deleted 2026-08-13)"      (2)
#   prose      provenance written as prose: "email: …", "session: …", "20 Aug 2026"     (10)
#   path       contains "/" (1,177) or ends in a file extension, e.g. CLAUDE.md          (18)
# Only `path` entries are resolved; everything else is counted so a zero is auditable.
URL_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*://")
PROSE_KEY_RE = re.compile(r"^[A-Za-z][A-Za-z ]{0,20}:\s")
EXT_RE = re.compile(r"\.[A-Za-z0-9]{1,8}$")
ANNOTATED_RE = re.compile(r"\((?:deleted|removed|archived|superseded)\b[^)]*\)\s*$", re.I)
SOURCES_KEY_RE = re.compile(r"^sources:", re.M)


def split_flow_list(text):
    """Split a YAML flow list's body on commas OUTSIDE quotes.

    A quoted path may carry commas — quoting is exactly the fix a page took for that on
    2026-09-03 — and a naive split turns one live path into two or three fragments that then
    read as dangling. Quote state is tracked so the fix is not punished.
    """
    out, buf, quote = [], "", ""
    for ch in text:
        if quote:
            if ch == quote:
                quote = ""
            buf += ch
        elif ch in "\"'":
            quote = ch
            buf += ch
        elif ch == ",":
            out.append(buf)
            buf = ""
        else:
            buf += ch
    out.append(buf)
    return [v.strip() for v in out if v.strip()]


def frontmatter_sources(block):
    """Every `sources:` entry in one frontmatter block, in any of the three shapes the vault
    writes: an inline flow list (possibly wrapped), a block list of `-` items, or a bare
    scalar. Returns (entries, key_present)."""
    if not SOURCES_KEY_RE.search(block):
        return [], False
    flow = re.search(r"^sources:[ \t]*\[(.*?)\]", block, re.M | re.S)
    if flow:
        return split_flow_list(flow.group(1)), True
    listed = re.search(r"^sources:[ \t]*(?:#[^\n]*)?\n((?:[ \t]*-[ \t]*[^\n]+\n?)+)", block, re.M)
    if listed:
        return [v.strip() for v in re.findall(r"^[ \t]*-[ \t]*(.+?)[ \t]*$", listed.group(1), re.M)
                if v.strip()], True
    scalar = re.search(r"^sources:[ \t]+([^\[\n#][^\n]*)$", block, re.M)
    if scalar and scalar.group(1).strip():
        return [scalar.group(1).strip()], True
    return [], True                    # `sources:` with an empty or `[]` value: parsed, no entries


def classify_source(entry):
    """Return (kind, cleaned) for one entry; kind is url · annotated · prose · path."""
    text = entry.strip()
    if len(text) > 1 and text[0] == text[-1] and text[0] in "\"'":
        text = text[1:-1].strip()
    else:
        text = text.strip("\"'").strip()
    if not text:
        return "prose", text
    if URL_RE.match(text):
        return "url", text
    if ANNOTATED_RE.search(text):
        return "annotated", text
    if PROSE_KEY_RE.match(text):
        return "prose", text
    if "/" in text or EXT_RE.search(text):
        return "path", text
    return "prose", text


source_pages = source_entries = 0
source_paths = source_urls = source_prose = 0
dangling_sources, annotated_sources, unparsed_sources = [], [], []

aliases = {}
for p in files:
    head = read_text(p)   # full read — a byte-capped head can silently drop aliases past the cap (§12: a bound needs stated headroom; the link pass re-reads every file in full anyway)
    fm = re.match(r"\A---\n(.*?)\n---", head, re.S)
    if not fm:
        continue
    block = fm.group(1)
    entries, key_present = frontmatter_sources(block)
    if key_present:
        source_pages += 1
        rel_page = os.path.relpath(p, root)
        if not entries:
            unparsed_sources.append(rel_page)
        for entry in entries:
            source_entries += 1
            kind, value = classify_source(entry)
            if kind == "url":
                source_urls += 1
            elif kind == "prose":
                source_prose += 1
            elif kind == "annotated":
                annotated_sources.append(f"{rel_page} · {value}")
            else:
                source_paths += 1
                if not os.path.exists(os.path.join(root, value)):
                    dangling_sources.append(f"{rel_page} · {value}")
    m = re.search(r"^aliases:\s*\[([^\]]*)\]", block, re.M)
    vals = []
    if m:
        vals = m.group(1).split(",")
    else:
        m2 = re.search(r"^aliases:\s*\n((?:\s*-\s*.+\n?)+)", block, re.M)
        if m2:
            vals = re.findall(r"-\s*(.+)", m2.group(1))
    for a in vals:
        a = a.strip().strip("\"'")
        if a:
            aliases[a] = p


def strip_noise(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)     # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                   # inline code spans
    return text


def resolves(target):
    t = target.strip()
    if not t or t.startswith("#"):
        return True                                          # self-heading link
    t = t.split("#", 1)[0].strip()                           # drop heading part
    if t in stems or t in aliases:
        return True
    if "/" in t or t.endswith(".md"):                        # vault-relative path form
        for cand in (t, t + ".md"):
            if os.path.exists(os.path.join(root, cand)):
                return True
    if os.path.exists(os.path.join(root, t + ".md")):        # root doc, e.g. [[CLAUDE]]
        return True
    base = os.path.basename(t).lower()                        # Obsidian basename lookup
    if base in vault_basenames or (base + ".md") in vault_basenames:
        return True
    return False


dead_links, dead_embeds = [], []
links_checked = embeds_checked = 0
for p in files:
    if os.path.basename(p) == "log.md":
        continue
    body = strip_noise(read_text(p))
    for is_embed, target in re.findall(r"(!?)\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]", body):
        target = target.strip().rstrip("\\")   # [[page\|alias]] table-escaped pipes leave a trailing backslash
        ext = os.path.splitext(target.split("#", 1)[0])[1].lower()
        rel = os.path.relpath(p, root)
        if is_embed and ext in MEDIA_EXT:
            embeds_checked += 1
            cands = [os.path.join(root, "assets", target), os.path.join(root, target)]
            if not any(os.path.exists(c) for c in cands):
                dead_embeds.append(f"{rel} -> ![[{target}]]")
        else:
            links_checked += 1
            if not resolves(target):
                dead_links.append(f"{rel} -> [[{target}]]")

print(f"SCANNED: {len(files)} pages | {links_checked} page links | {embeds_checked} media embeds "
      f"| {len(stems)} stems | {len(aliases)} aliases   (nonzero totals = probe ran)")
print(f"DEAD LINKS: {len(dead_links)}")
for d in dead_links:
    print("  " + d)
print(f"DEAD EMBEDS: {len(dead_embeds)}")
for d in dead_embeds:
    print("  " + d)
print(f"SOURCES SCANNED: {source_pages} pages carry sources: | {source_entries} entries "
      f"| {source_paths} vault paths resolved | {source_urls} URLs | {source_prose} prose "
      f"| {len(annotated_sources)} annotated absences | {len(unparsed_sources)} empty or unparsed"
      "   (nonzero totals = the sources arm ran)")
print(f"DANGLING SOURCES: {len(dangling_sources)}")
for d in dangling_sources:
    print("  " + d)
# Neither list is a finding: an annotated entry declares its own absence, and an empty
# `sources:` carries nothing to resolve. Both are printed so nothing is silently skipped.
for label, items in (("annotated absence", annotated_sources), ("empty or unparsed sources", unparsed_sources)):
    for d in items:
        print(f"  ({label}) {d}")
sys.exit(1 if (dead_links or dead_embeds or dangling_sources) else 0)
