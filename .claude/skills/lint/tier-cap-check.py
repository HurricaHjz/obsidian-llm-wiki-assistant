#!/usr/bin/env python3
"""tier-cap-check.py — the mechanical half of confidence verification (CLAUDE.md 4.6).

The rubric has a judgement half (is this source really authoritative?) that only a
reader can settle, and a mechanical half that a script settles better than a lane:
the type cap and the two boundaries. This script owns the mechanical half.

Rules applied
  (a) type cap    concept, entity, tool, model, benchmark, synthesis and development
                  cap at `high`; `map` omits confidence entirely; `source` and `user`
                  may reach `authoritative`. Any value outside the five tiers is invalid.
  (b) boundary 1  a `source` page whose every raw entry sits under the social lane, or
                  whose source URL points at a social platform, CAPS at `low`. A page
                  below that cap is not a finding: the rubric's tie rule is to pick the
                  lower tier, so a social capture at `very-low` is obeying it.
  (c) boundary 2  a compiled page citing exactly ONE source document is at most `high`.
                  That equals the type cap, so it is reported as the boundary it is: a
                  proposed `authoritative` on such a page fails on both grounds, and the
                  note is what lets a report name the second one.

Documented overrides (the line 4.6 ends on: an explicit user instruction overrides a tier)
  A page records that instruction in the inline comment on its own `confidence:` line.
  A comment carrying the word "override" moves that page's tier findings out of
  `violations:` and under `overrides (documented):`, with the page and the comment
  excerpt, so a mechanical check tells a recorded judgement from a slip — the same tier
  with no comment stays a violation. Only the three JUDGEMENT rules are overridable:
  they are about how high a tier sits. A `map` carrying confidence, and a value outside
  the five tiers, stay violations whatever the comment says — they are schema breaches,
  with no trust judgement for an instruction to override. An override comment that
  suppresses nothing is reported as an `override-unused` note (usually a judgement whose
  page has since changed).

Two input modes
  --vault ROOT        check every wiki page's own frontmatter (the audit pass).
  --verdicts FILE     check a lane's PROPOSED tiers: a JSON array of
                      {"page": <path>, "tier": <tier>} objects, each optionally carrying
                      its own "comment" (where the proposal records its own override).
                      Each page's type and sources still come from its frontmatter on
                      disk, so a proposal is checked against the real page, never against
                      itself.

Self-control (CLAUDE.md 11): every run builds synthetic records in memory and re-runs the
same rule functions over them — one violating record per rule (`cap-control: 3/3`), one
record per zero-able note family and one documented/undocumented override pair
(`extra-control: notes 2/2 · overrides 2/2`). A miss prints PROBE FAILED and exits 2,
because a rule engine that cannot catch a planted violation cannot report a clean vault.

A broken premise prints one plain `PROBE FAILED: …` line on stdout and exits 2 whatever
`--format` says, so a JSON consumer keys on the exit code, never on parsing that line.

Stdout only: this script never creates, modifies, moves or deletes a file.

Usage:
  python3 tier-cap-check.py [--vault ROOT] [--format text|json]
  python3 tier-cap-check.py --verdicts proposed.json [--vault ROOT] [--format text|json]
  exit 0 = the probe ran (findings or none) · exit 2 = broken premise
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.parse

TIERS = ["very-low", "low", "medium", "high", "authoritative"]
RANK = {t: i for i, t in enumerate(TIERS)}

# CLAUDE.md 4.6: compiled pages cap at high; agent-derived pages cap at high too.
CAPPED_TYPES = {"concept", "entity", "tool", "model", "benchmark", "synthesis", "development"}
# The subset 4.6 calls "compiled" — the pages built by folding sources together. Boundary 2
# is about them: one primary source's authority never transfers to the page compiled from it.
COMPILED_TYPES = {"concept", "entity", "tool", "model", "benchmark"}
UNCAPPED_TYPES = {"source", "user", "index", "log"}
EXEMPT_TYPES = {"map"}

SOCIAL_DIR = "raw/6-social/"
# Hosts whose captures are the single social-platform capture 4.6 pins at `low`.
SOCIAL_HOSTS = {"x.com", "twitter.com", "reddit.com", "linkedin.com",
                "bilibili.com", "weibo.com", "threads.net"}

# The word an owner writes when a tier records an instruction rather than a default. The
# inflections are listed rather than a prefix match, so "overridable" (a description of the
# rule, not a record of one) never counts.
OVERRIDE_RE = re.compile(r"\boverrid(?:e|es|ing|den)\b", re.I)
# Rules that judge how HIGH a tier sits; the two schema breaches are deliberately absent.
OVERRIDABLE = {"social-low", "boundary-2", "over-cap"}

COMMENT_CHARS = 110   # one terminal line minus the page/rule prefix; set by judgement, unmeasured


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
    silently turn a badged page into an unbadged one.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    text = raw.decode("utf-8-sig", "replace")
    return text.replace("\r\n", "\n")


def field(block, key):
    """Frontmatter scalar as (value_or_None, inline_comment).

    YAML's own two rules decide the split: a `#` starts a comment only when whitespace
    precedes it, and a quoted scalar swallows every `#` inside the quotes.
    """
    m = re.search(r"^%s:[ \t]*(.*)$" % re.escape(key), block, re.M)
    if not m:
        return None, ""
    s = m.group(1).strip()
    if s.startswith("#"):                       # `key:` with only a comment = a null value
        return None, s.lstrip("#").strip()
    if s[:1] in ("\"", "'"):
        quote = s[0]
        end = s.find(quote, 1)
        if end != -1:
            rest = s[end + 1:]
            comment = rest.split("#", 1)[1].strip() if "#" in rest else ""
            return (s[1:end].strip() or None), comment
    parts = re.split(r"\s+#", s, maxsplit=1)
    value = parts[0].strip().strip("\"'")
    return (value or None), (parts[1].strip() if len(parts) > 1 else "")


def scalar(block, key):
    return field(block, key)[0]


def seq(block, key):
    """Frontmatter sequence in either YAML form: inline `[a, b]` or a block list."""
    m = re.search(r"^%s:[ \t]*\[([^\]]*)\]" % re.escape(key), block, re.M)
    if m:
        vals = m.group(1).split(",")
    else:
        m2 = re.search(r"^%s:[ \t]*\n((?:[ \t]*-[ \t]*.+\n?)+)" % re.escape(key), block, re.M)
        if not m2:
            return []
        vals = re.findall(r"-[ \t]*(.+)", m2.group(1))
    out = []
    for v in vals:
        v = re.split(r"\s+#", v, maxsplit=1)[0].strip().strip("\"'")
        if v:
            out.append(v)
    return out


def excerpt(s, limit=COMMENT_CHARS):
    s = " ".join(s.split())
    return s if len(s) <= limit else s[:limit - 1] + "…"


def record_from_page(path, root):
    text = read_text(path)
    m = re.match(r"\A---\n(.*?)\n---", text, re.S)
    block = m.group(1) if m else ""
    tier, comment = field(block, "confidence")
    return {
        "path": os.path.relpath(path, root),
        "type": scalar(block, "type"),
        "tier": tier,
        "comment": comment,
        "sources": seq(block, "sources"),
        "source_url": scalar(block, "source_url"),
        "has_frontmatter": bool(m),
        # Opens with a frontmatter fence that never closes: every key below it is read as
        # prose, so the page would otherwise pass as "carries no confidence value".
        "malformed_frontmatter": bool(not m and text.startswith("---\n")),
    }


def document_count(sources):
    """Distinct source DOCUMENTS behind a `sources:` list.

    Dual provenance (CLAUDE.md 3.1) lists a converted source twice — the original and its
    Markdown conversion — and a clip often lists its raw file plus the URL it came from.
    Both are one document, so raw entries collapse on their stem and the count falls back
    to the raw entry count where any raw entry exists. Set by judgement, unmeasured: it is
    the reading that makes boundary 2 fire on the case it names (a page resting on one
    document) rather than on a bookkeeping artefact.
    """
    raw = [s for s in sources if s.startswith("raw/")]
    if raw:
        return len({os.path.splitext(os.path.basename(s))[0] for s in raw})
    return len(sources)


def is_social(rec):
    raw = [s for s in rec["sources"] if s.startswith("raw/")]
    if raw and all(s.startswith(SOCIAL_DIR) for s in raw):
        return "every raw source under " + SOCIAL_DIR
    url = rec.get("source_url")
    if url:
        host = urllib.parse.urlparse(url if "//" in url else "//" + url).hostname or ""
        host = host.lower().lstrip(".")
        for h in SOCIAL_HOSTS:
            if host == h or host.endswith("." + h):
                return "source URL host " + host
    return None


def check(rec):
    """Return (violations, notes, overrides) for one record.

    Pure: the self-control runs it too. A violation is (rule, detail); the internal
    `over-cap` tag distinguishes the overridable half of `type-cap` (a valid tier sitting
    too high) from its schema half (a map carrying confidence, or a value outside the five)
    before both are reported under the same rule name.
    """
    notes = []
    ptype, tier = rec.get("type"), rec.get("tier")
    comment = rec.get("comment") or ""
    documented = bool(OVERRIDE_RE.search(comment))

    def done(vios):
        """Split the findings a documented override covers away from the rest."""
        keep = [(rule, detail) for rule, tag, detail in vios if not (documented and tag in OVERRIDABLE)]
        moved = [(rule, detail) for rule, tag, detail in vios if documented and tag in OVERRIDABLE]
        if documented and not moved:
            notes.append(("override-unused", "confidence comment records an override, but no "
                                             "OVERRIDABLE rule fires on this page (a schema "
                                             "finding is not one): " + excerpt(comment)))
        return keep, notes, moved

    if ptype in EXEMPT_TYPES:
        if tier:
            return done([("type-cap", "schema",
                          f"type {ptype} omits confidence entirely, found `{tier}`")])
        return done([])

    if not rec.get("has_frontmatter", True):
        kind = "malformed-frontmatter" if rec.get("malformed_frontmatter") else "no-frontmatter"
        detail = ("frontmatter opens with --- and never closes, so its keys read as prose"
                  if rec.get("malformed_frontmatter") else "page carries no frontmatter block")
        notes.append((kind, detail))
        if tier is None:
            return done([])
        # A verdict names a tier even where the page carries none, and that tier is the whole
        # point of the run — so the note is recorded and the rules still run over it.

    if tier is None:
        notes.append(("no-confidence", f"type {ptype or '?'} carries no confidence value"))
        return done([])

    if tier not in RANK:
        return done([("type-cap", "schema", f"`{tier}` is not one of {'|'.join(TIERS)}")])

    vios = []
    if ptype in CAPPED_TYPES and RANK[tier] > RANK["high"]:
        vios.append(("type-cap", "over-cap", f"type {ptype} caps at high, found `{tier}`"))
    elif ptype not in CAPPED_TYPES and ptype not in UNCAPPED_TYPES:
        notes.append(("unknown-type",
                      f"type `{ptype or '(absent)'}` is not a schema type; capped rules not applied"))

    if ptype == "source":
        why = is_social(rec)
        # A cap, not an equality: below it the rubric's tie rule is being obeyed, not broken.
        if why and RANK[tier] > RANK["low"]:
            vios.append(("social-low", "social-low", f"{why} caps at low, found `{tier}`"))

    if ptype in COMPILED_TYPES and document_count(rec["sources"]) == 1:
        if RANK[tier] > RANK["high"]:
            vios.append(("boundary-2", "boundary-2",
                         f"single source document caps at high, found `{tier}`"))
        elif tier == "high":
            notes.append(("boundary-2", "single source document — sitting ON the boundary-2 cap"))
        else:
            notes.append(("boundary-2-slack", f"single source document, at `{tier}` — below the cap"))

    return done(vios)


# Synthetic records, in memory only, that never touch disk. The first three are one
# violating record per rule; the rest control the zero-able note and override families.
SELF_CONTROL = [
    ("type-cap", {"path": "<synthetic>/capped-type.md", "type": "tool", "tier": "authoritative",
                  "sources": ["raw/4-webinfo/a.md", "raw/4-webinfo/b.md"], "source_url": None}),
    ("social-low", {"path": "<synthetic>/social-source.md", "type": "source", "tier": "high",
                    "sources": ["raw/6-social/a.md"], "source_url": None}),
    ("boundary-2", {"path": "<synthetic>/single-source.md", "type": "concept", "tier": "authoritative",
                    "sources": ["raw/2-papers/a.md"], "source_url": None}),
]
NOTE_CONTROL = [
    ("boundary-2", {"path": "<synthetic>/on-cap.md", "type": "concept", "tier": "high",
                    "sources": ["raw/2-papers/a.md"], "source_url": None}),
    ("no-confidence", {"path": "<synthetic>/unbadged.md", "type": "concept", "tier": None,
                       "sources": [], "source_url": None}),
]
# A documented override and its undocumented twin: the comment is the only difference.
OVERRIDE_CONTROL = [
    ("documented", {"path": "<synthetic>/documented.md", "type": "source", "tier": "medium",
                    "comment": "override of the social boundary, recorded by the owner",
                    "sources": ["raw/6-social/a.md"], "source_url": None}),
    ("undocumented", {"path": "<synthetic>/undocumented.md", "type": "source", "tier": "medium",
                      "comment": "corroborated elsewhere",
                      "sources": ["raw/6-social/a.md"], "source_url": None}),
]


def run_self_control():
    """Return (rules caught, notes raised, override pair verdicts) — each a positive control."""
    caught = []
    for rule, rec in SELF_CONTROL:
        vios, _, _ = check(dict(rec))
        if any(v[0] == rule for v in vios):
            caught.append(rule)
    notes_ok = []
    for kind, rec in NOTE_CONTROL:
        _, nts, _ = check(dict(rec))
        if any(n[0] == kind for n in nts):
            notes_ok.append(kind)
    overrides_ok = []
    for label, rec in OVERRIDE_CONTROL:
        vios, _, ovr = check(dict(rec))
        if label == "documented" and ovr and not vios:
            overrides_ok.append(label)
        if label == "undocumented" and vios and not ovr:
            overrides_ok.append(label)
    return caught, notes_ok, overrides_ok


def load_verdicts(path, root):
    with open(path, "rb") as fh:
        data = json.loads(fh.read().decode("utf-8"))
    if not isinstance(data, list):
        raise ValueError("verdicts file must hold a JSON array")
    records, unresolved = [], []
    for i, item in enumerate(data):
        if not isinstance(item, dict):
            unresolved.append(f"<entry {i} is not an object>")
            continue
        page, tier = item.get("page"), item.get("tier")
        if not isinstance(page, str) or not page.strip():
            unresolved.append(f"<entry {i} carries no page path>")
            continue
        cand = page if os.path.isabs(page) else os.path.join(root, page)
        if not os.path.isfile(cand):
            unresolved.append(page)
            continue
        rec = record_from_page(cand, root)
        on_disk = rec["tier"]
        rec["tier"] = tier if (tier is None or isinstance(tier, str)) else str(tier)
        # An override recorded on the page justifies the tier the page CARRIES. It does not
        # travel to a different proposed tier, or the check would excuse a lane's new verdict
        # on the strength of a judgement made about another one. A proposal that means to
        # record its own override says so in its own `comment` field.
        note = item.get("comment")
        if isinstance(note, str):
            rec["comment"] = note
        elif rec["tier"] != on_disk:
            rec["comment"] = ""
        rec["proposed"] = True
        records.append(rec)
    return records, unresolved


def assert_vault_root(root):
    """A root must hold raw/ AND wiki/ or the audit refuses to run.

    The 2026-08-26 standard, closed for the capture layer and swept here on 2026-09-07: fail
    loud on stderr, never a wrong-tree scan that reports a clean vault on a scan of nothing.
    """
    if not all(os.path.isdir(os.path.join(root, d)) for d in ("raw", "wiki")):
        print(f"PROBE FAILED: {root} is not a vault root (no raw/ or wiki/)", file=sys.stderr)
        raise SystemExit(2)
    return root


def main():
    stdout_utf8()
    ap = argparse.ArgumentParser(description="Confidence type-cap and boundary checker.")
    ap.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    ap.add_argument("--verdicts", help="JSON array of {page, tier} proposals to check instead")
    ap.add_argument("--format", choices=("text", "json"), default="text",
                    help="output format (default: text)")
    args = ap.parse_args()

    root = os.path.abspath(os.path.expanduser(args.vault))
    caught, notes_ok, overrides_ok = run_self_control()
    if len(caught) != len(SELF_CONTROL):
        missed = [r for r, _ in SELF_CONTROL if r not in caught]
        print(f"PROBE FAILED: cap-control {len(caught)}/{len(SELF_CONTROL)} — "
              f"rule engine missed {', '.join(missed)}")
        return 2
    if len(notes_ok) != len(NOTE_CONTROL) or len(overrides_ok) != len(OVERRIDE_CONTROL):
        print(f"PROBE FAILED: extra-control notes {len(notes_ok)}/{len(NOTE_CONTROL)} · "
              f"overrides {len(overrides_ok)}/{len(OVERRIDE_CONTROL)} — the note or override "
              f"path did not fire on its own planted record")
        return 2

    unresolved = []
    if args.verdicts:
        mode = "verdicts"
        verdicts_path = os.path.expanduser(args.verdicts)
        if not os.path.isfile(verdicts_path):
            print(f"PROBE FAILED: verdicts file not found: {args.verdicts}")
            return 2
        try:
            records, unresolved = load_verdicts(verdicts_path, root)
        except (ValueError, OSError) as exc:
            print(f"PROBE FAILED: cannot read verdicts: {exc}")
            return 2
        if not records:
            print("PROBE FAILED: no verdict resolved to a page on disk "
                  f"({len(unresolved)} unresolved)")
            return 2
    else:
        mode = "vault"
        root = assert_vault_root(root)     # vault mode only: --verdicts names its own pages
        wiki = os.path.join(root, "wiki")
        if not os.path.isdir(wiki):        # unreachable while the root guard runs first
            print(f"PROBE FAILED: no wiki directory under {args.vault}")
            return 2
        pages = sorted(glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True))
        if not pages:
            print("PROBE FAILED: wiki directory holds no Markdown pages")
            return 2
        try:
            records = [record_from_page(p, root) for p in pages]
        except OSError as exc:
            print(f"PROBE FAILED: cannot read a wiki page: {exc}")
            return 2
        if not any(r["tier"] for r in records):
            print("PROBE FAILED: no page carries a confidence value (nothing to check)")
            return 2

    violations, notes, overrides = [], [], []
    for rec in records:
        vios, nts, ovr = check(rec)
        for rule, detail in vios:
            violations.append({"page": rec["path"], "type": rec["type"],
                               "tier": rec["tier"], "rule": rule, "detail": detail})
        for kind, detail in nts:
            notes.append({"page": rec["path"], "type": rec["type"],
                          "tier": rec["tier"], "kind": kind, "detail": detail})
        for rule, detail in ovr:
            overrides.append({"page": rec["path"], "type": rec["type"], "tier": rec["tier"],
                              "rule": rule, "detail": detail,
                              "comment": excerpt(rec.get("comment") or "")})

    per_rule = {r: sum(1 for v in violations if v["rule"] == r) for r in
                ("type-cap", "social-low", "boundary-2")}
    per_note = {}
    for n in notes:
        per_note[n["kind"]] = per_note.get(n["kind"], 0) + 1
    control = f"{len(caught)}/{len(SELF_CONTROL)}"
    extra = f"notes {len(notes_ok)}/{len(NOTE_CONTROL)} · overrides {len(overrides_ok)}/{len(OVERRIDE_CONTROL)}"

    if args.format == "json":
        print(json.dumps({
            "mode": mode, "root": args.vault, "records": len(records),
            "violations": violations, "violation_count": len(violations),
            "per_rule": per_rule, "notes": notes, "note_counts": per_note,
            "overrides": overrides, "override_count": len(overrides),
            "unresolved": unresolved, "cap_control": control, "extra_control": extra,
        }, indent=2, sort_keys=True))
        return 0

    print(f"tier-cap-check: mode={mode} · root={args.vault} · "
          f"tiers={'|'.join(TIERS)} · compiled-cap=high · "
          f"override-marker=\"override\" in the confidence comment · format=text")
    print(f"checked: {len(records)} records · "
          f"{sum(1 for r in records if r['tier'])} carry a tier · "
          f"{sum(1 for r in records if r.get('type') in EXEMPT_TYPES)} exempt (map)")
    print(f"violations: {len(violations)}  (type-cap {per_rule['type-cap']} · "
          f"social-low {per_rule['social-low']} · boundary-2 {per_rule['boundary-2']})")
    for v in violations:
        print(f"  {v['page']} · {v['type']} · {v['tier']} · {v['rule']} — {v['detail']}")
    print(f"overrides (documented): {len(overrides)}  (tier findings a `confidence:` comment "
          f"records as a judgement — not violations)")
    for o in overrides:
        print(f"  {o['page']} · {o['type']} · {o['tier']} · {o['rule']} — {o['comment']}")
    b2 = [n for n in notes if n["kind"] == "boundary-2"]
    slack = per_note.get("boundary-2-slack", 0)
    print(f"boundary-2 notes: {len(b2)} single-document compiled pages ON the high cap "
          f"(+{slack} single-document pages below it, not listed)")
    for n in b2:
        print(f"  {n['page']} · {n['type']} · {n['tier']} — {n['detail']}")
    skip = ("boundary-2", "boundary-2-slack")
    other = [n for n in notes if n["kind"] not in skip]
    print(f"other notes: {len(other)}  (" +
          " · ".join(f"{k} {v}" for k, v in sorted(per_note.items()) if k not in skip) + ")")
    for n in other:
        print(f"  {n['page']} · {n['kind']} — {n['detail']}")
    if unresolved:
        print(f"unresolved verdict pages: {len(unresolved)}")
        for u in unresolved:
            print("  " + u)
    print(f"cap-control: {control} synthetic violations caught")
    print(f"extra-control: {extra} (planted note records raised; a documented override "
          f"recognised and its undocumented twin still a violation)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
