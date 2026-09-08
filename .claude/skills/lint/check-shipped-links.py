#!/usr/bin/env python3
"""check-shipped-links.py — shipped-surface wikilink guard (CLAUDE.md §11 / §12).

Question it answers: does any Markdown file that ships with the public framework carry a [[wikilink]]
that resolves in THIS vault but not in the published copy? Such a link is dead for every installer. It
does not judge links that are dead everywhere (typos, renamed pages): shipped skills use placeholders
such as [[topic]] on purpose, so those are counted on the control line, never flagged.

Surfaces (keyed on the export's own auto-discovery contract, its list_skills / list_agents functions):
every *.md under .claude/skills/ and .claude/agents/, minus vault-shaped content bundled inside a skill
(any path with a wiki/ or raw/ segment below .claude/skills/, i.e. the shipped seed demo, which ships as
vault content and resolves among itself). Root docs (CLAUDE.md, MANUAL.md, README.md) are out of scope:
their [[…]] are naming examples by design, and §12's ship-safe-citation rule governs their citations.
Generator output (what setup.sh writes into a fresh vault) is the installed vault's content, not a
shipped surface.

Names that ship, and are therefore never findings: `index` and `log` (setup.sh creates wiki/index.md and
wiki/log.md in every install) and every page of a bundled example tree (.claude/skills/**/example/**/*.md,
installed by `setup.sh --with-example`).

Links: fenced blocks, inline code spans and HTML comments are not links (the strip_noise rule of
check-links.py); targets resolve the way Obsidian does (alias/heading stripped, a table-escaped pipe's
trailing backslash dropped, path-style by last segment, an explicit .md dropped, case-insensitive),
against page basenames AND frontmatter `aliases:` — an alias resolves here and dies in the published copy
just the same. Known limitation, shared with check-links.py: only three-backtick fences are recognised
(no ~~~, no four-backtick nesting); zero such fences in any shipped surface at the time of writing.

Call sites — one implementation, two callers, so they cannot drift:
  lint SKILL.md Step 2g (routine, edit time) · the publish gate's test suite, leg 14 (publish).
Regression fixtures: test_check_shipped_links.sh beside this file (run with bash).

Usage: python3 check-shipped-links.py [--vault ROOT] [VAULT_ROOT]  (default: three levels above this file)
Prints ONE summary line for the lint report, then one "  <file> → [[target]]" line per finding:
  shipped-links: clean (control OK: N surfaces, M wikilinks seen, P wiki pages + aliases = Q names,
                        S shipping names excluded, U targets resolving nowhere here, self-control fired)
  shipped-links: n/a (wiki/ present but empty — no vault-only page can be linked)
  shipped-links: K dead in the published copy (control OK: …)
  shipped-links: PROBE FAILED — <reason>
Exit 0 clean or n/a · 1 findings · 2 PROBE FAILED. Premise failures never read as clean: a root
that is not a vault, i.e. no raw/ + wiki/ (the 2026-08-26 standard, on stderr) → 2; an unknown
option → 2; no shipped surfaces → 2; an unreadable or undecodable surface → 2; the
matcher's self-control (a synthetic surface linking a synthetic page must be caught) silent → 2. An EMPTY
wiki/ is legitimate absence (a fresh install, the published copy itself) → n/a, exit 0.
Design record: wiki/developments/shipped-surface-wikilink-guard.md
"""
import glob
import os
import re
import sys

LINK = re.compile(r"\[\[([^\]]+)\]\]")
PROBE = "zzz-shipped-links-self-control"          # synthetic: keys the control on the matcher, not on a vault name


def strip_noise(text):                                     # mirrors check-links.py strip_noise
    text = re.sub(r"```.*?```", " ", text, flags=re.S)     # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)    # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                  # inline code spans
    return text


def norm(target):
    """Resolve the way Obsidian does: alias and heading stripped, a table-escaped pipe's trailing
    backslash dropped, path-style links by their last segment, an explicit .md dropped, case-insensitive."""
    t = target.split("|")[0].split("#")[0].strip().rstrip("\\").rsplit("/", 1)[-1]
    if t.lower().endswith(".md"):
        t = t[:-3]
    return t.casefold()


def targets(text):                                         # (raw link text, normalised target)
    return [(m, norm(m)) for m in LINK.findall(strip_noise(text))]


def read(path, strict):
    """A shipped surface must decode (strict); a wiki page only feeds the alias set (replace)."""
    try:
        with open(path, encoding="utf-8", errors="strict" if strict else "replace") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError) as err:
        print(f"shipped-links: PROBE FAILED — cannot read {path}: {err}")
        raise SystemExit(2)


def frontmatter_aliases(text):                             # mirrors check-links.py: inline list or block list
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


def stem(path):
    return os.path.splitext(os.path.basename(path))[0].casefold()


def parse_root(argv):
    """The sibling flag spelling or the historical positional form; anything else is refused.

    A swallowed flag is how a wrong root goes unnoticed: `--vault X` taken as the root scans a
    directory that does not exist and the run reads as a premise failure at best, clean at worst.
    """
    given = None
    rest = list(argv[1:])
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            print("usage: check-shipped-links.py [--vault ROOT] [ROOT]")
            raise SystemExit(0)
        if arg == "--vault":
            if not rest:
                print("PROBE FAILED: --vault needs a directory argument", file=sys.stderr)
                raise SystemExit(2)
            arg = rest.pop(0)
        elif arg.startswith("--vault="):
            arg = arg.split("=", 1)[1]
        elif arg.startswith("-"):
            print(f"PROBE FAILED: unknown option {arg} (usage: [--vault ROOT] [ROOT])", file=sys.stderr)
            raise SystemExit(2)
        if given is not None:
            print(f"PROBE FAILED: two roots given ({given} and {arg})", file=sys.stderr)
            raise SystemExit(2)
        given = arg
    return given


def assert_vault_root(root):
    """A root must hold raw/ AND wiki/ or the check refuses to run (2026-08-26 standard):
    fail loud on stderr, never a wrong-tree scan reported as clean."""
    if not all(os.path.isdir(os.path.join(root, d)) for d in ("raw", "wiki")):
        print(f"PROBE FAILED: {root} is not a vault root (no raw/ or wiki/)", file=sys.stderr)
        raise SystemExit(2)
    return root


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    given = parse_root(argv)
    root = os.path.abspath(given) if given else os.path.abspath(os.path.join(here, "..", "..", ".."))
    assert_vault_root(root)
    wiki = os.path.join(root, "wiki")
    if not os.path.isdir(wiki):    # unreachable while the root guard runs first; kept as depth
        print(f"shipped-links: PROBE FAILED — no wiki/ under {root} (wrong vault root?)")
        return 2
    skills = os.path.join(root, ".claude", "skills")

    def bundled_vault_content(f):                          # seed demo pages: vault-shaped dirs inside a skill
        parts = os.path.relpath(f, skills).split(os.sep)[:-1]
        return "wiki" in parts or "raw" in parts

    surfaces = sorted(f for f in glob.glob(os.path.join(skills, "**", "*.md"), recursive=True)
                      if not bundled_vault_content(f))
    surfaces += sorted(glob.glob(os.path.join(root, ".claude", "agents", "*.md")))
    if not surfaces:
        print("shipped-links: PROBE FAILED — no shipped Markdown surfaces under .claude/skills or .claude/agents")
        return 2
    files = glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True)
    if not files:                                          # legitimate absence: a fresh install, the published copy
        print("shipped-links: n/a (wiki/ present but empty — no vault-only page can be linked)")
        return 0
    pages = {stem(f) for f in files}
    for f in files:
        pages.update(a.casefold() for a in frontmatter_aliases(read(f, strict=False)))
    ships = {"index", "log"}                               # setup.sh creates both in every install
    ships |= {stem(f) for f in glob.glob(os.path.join(skills, "**", "example", "**", "*.md"), recursive=True)}
    if [t for _, t in targets(f"control [[{PROBE}|alias]] text") if t in pages | {PROBE}] != [PROBE]:
        print("shipped-links: PROBE FAILED — matcher self-control did not fire")
        return 2
    seen, unresolved, findings = 0, 0, []
    for f in surfaces:
        ts = targets(read(f, strict=True))
        seen += len(ts)
        for raw, t in ts:
            if t in ships:
                continue
            if t in pages:
                findings.append((os.path.relpath(f, root), raw))
            else:
                unresolved += 1
    ctl = (f"control OK: {len(surfaces)} surfaces, {seen} wikilinks seen, {len(files)} wiki pages + aliases = "
           f"{len(pages)} names, {len(ships)} shipping names excluded, {unresolved} targets resolving nowhere here, "
           f"self-control fired")
    if findings:
        print(f"shipped-links: {len(findings)} dead in the published copy ({ctl})")
        for f, raw in findings:
            print(f"  {f} → [[{raw}]]")
        return 1
    print(f"shipped-links: clean ({ctl})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
