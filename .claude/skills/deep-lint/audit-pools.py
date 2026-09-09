#!/usr/bin/env python3
"""Audit pools and frontmatter-dependent sweeps for deep-lint Steps 1 and 3.

Report-only by construction: this script prints to stdout and stderr and writes nothing —
no vault file, no cache, no temporary file. Every deep-lint decision it feeds stays with the
agent; the script only measures.

What it produces, in the runbook's own line formats so a run copies them verbatim:
  - the audit-eligible count (all of wiki/ except `type: map`, index.md and log.md);
  - confidence coverage over comment-stripped values (`high   # note` parses as `high`),
    with the invalid/missing list;
  - pool A (`updated:` >= baseline) and pool B, each with the baseline control;
  - pool A's strata in fill order (flagged, authoritative, compiled/derived-high, other),
    the cap rule applied, and the sample listing;
  - the least-recently-audited tail pool and its sample;
  - unclassifiable pages (no parseable `updated:`);
  - the `updated:` accuracy sweep with an in-memory planted control;
  - orphans, index consistency, log link health and log entry sizes;
  - `source_url` freshness candidates ranked confidence x age x inbound degree;
  - the three Step 3 report lines.

Rules encoded here (so a run never re-derives them by hand):
  - the split is on the `updated:` FRONTMATTER date, never filesystem mtime and never git
    (cloud sync rewrites mtimes; backups are batched) — deep-lint Step 3;
  - `flagged:` pages are always audited and cost nothing against the cap (Step 2 read them),
    and every one of them sits in pool A whatever its `updated:` date — the stratum is defined
    by the flag, not by the window, so a flag written without an `updated:` bump can no longer
    hide in the cold tail (known-issues 2026-09-08, wiki page writers); the lifted count prints;
  - `confidence: authoritative` pages are always audited and do consume the cap;
  - wikilinks inside fenced code blocks, inline code spans and HTML comments are not links;
    aliases resolve; log.md is history, so it never acts as a link source for the graph; an embed
    of a page is a page link, an embed of a media file is not — the shared link checker's rule.

Every control here is derived from the data it guards, never from a fixed date or count: a
constant stops being "older than every page" the moment a vault carries an older one, and the
guard then fails a healthy run instead of catching a broken one.

Premise failures (exit 2) versus legitimate empty states (exit 0, reported as such): a missing
wiki directory, a wiki with no pages, no audit-eligible page, a missing index.md or log.md, an
unreadable page, a negative cap and a log whose entry pattern matches nothing despite headings are
premise failures. A log with no headings at all, an empty tail pool and zero findings anywhere are
legitimate and print their own scope so no zero reads as an unverified "clean".

Usage (from the vault root):
  python3 .claude/skills/deep-lint/audit-pools.py --baseline 2026-08-28
  python3 .claude/skills/deep-lint/audit-pools.py --vault <root> --format json

Exit codes: 0 = the probe ran (findings or none); 2 = a probe premise failed.
"""

import argparse
import datetime
import json
import os
import re
import statistics
import sys
from random import Random

VALID_CONFIDENCE = ("authoritative", "high", "medium", "low", "very-low")
# The compiled/derived types that sit on the CLAUDE.md 4.6 `high` ceiling — deep-lint Step 3.
COMPILED_TYPES = ("concept", "entity", "tool", "model", "benchmark", "synthesis", "development")
# Freshness ranking weights: confidence x age x inbound degree (deep-lint Step 5, "bound and prioritise").
CONF_WEIGHT = {"authoritative": 5, "high": 4, "medium": 3, "low": 2, "very-low": 1}
# Hosts whose artefacts are published once and effectively immutable — Step 5 skips re-fetching them.
IMMUTABLE_HOST = re.compile(
    r"arxiv\.org|doi\.org|openreview\.net|semanticscholar|\.pdf($|[?#])|aclanthology|ieee|springer"
    r"|neurips\.cc|proceedings\.mlr",
    re.I,
)
# Extensions an Obsidian embed treats as media rather than as a page transclusion — the same set
# the shared link checker uses, so both agree on what counts as a page link.
MEDIA_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf", ".mp3", ".wav", ".mp4", ".mov")
# The two registries, addressed by PATH: keying them on the file stem alone would also silently drop
# any other page under wiki/ that happens to be called index.md or log.md.
INDEX_REL = "wiki/index.md"
LOG_REL = "wiki/log.md"
# A byte-order mark, written as an escape so the character never sits invisibly in shipped source.
BOM = "\ufeff"
# Top-N freshness candidates printed: enough for Step 5's capped probe budget to choose from.
# Set by judgement, unmeasured.
FRESHNESS_TOP = 14
# The tail is drawn from its oldest third unless the tail is small, where the whole tail is the
# pool: 60 = three times the 20-page tail cap, so the "oldest third" rule cannot under-fill it
# (deep-lint Step 3, pool B).
TAIL_WHOLE_POOL_BELOW = 60

FM_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n?", re.S)
FM_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$")
LINK_RE = re.compile(r"(!?)\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]")
DATE_RE = re.compile(r"(?<![\d-])(20\d\d-\d\d-\d\d)(?![\d-])")
LOG_HEAD_RE = re.compile(r"(?m)^## \[(\d{4}-\d{2}-\d{2})\].*$")


def parse_date(value):
    """Parse a YYYY-MM-DD frontmatter value; return None when it does not parse."""
    if value is None:
        return None
    text = value.strip().strip("\"'")
    try:
        return datetime.date.fromisoformat(text[:10])
    except ValueError:
        return None


def strip_comment(value):
    """Drop a trailing YAML comment and surrounding quotes: `high   # note` -> `high`."""
    return value.split("#", 1)[0].strip().strip("\"'")


def strip_url_comment(value):
    """A URL may legitimately carry a `#` fragment, so only a spaced ` #` starts a comment."""
    return re.split(r"\s#", value, maxsplit=1)[0].strip().strip("\"'")


def strip_noise(text):
    """Remove the spans where a wikilink is documentation, not a link."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)     # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                  # inline code spans
    return text


def link_targets(text):
    """Wikilink targets in rendered prose, heading part dropped.

    An embed of a MEDIA file is not a page link; an embed of a page is one, because a transclusion
    is a live reference to that page. This is the rule the shared link checker applies,
    and the two must agree or a page transcluded but never linked reads as an orphan here and as
    linked there.
    """
    out = []
    for bang, target in LINK_RE.findall(strip_noise(text)):
        target = target.strip().rstrip("\\")                # table-escaped pipes leave a backslash
        target = target.split("#", 1)[0].strip()
        if not target:
            continue
        if bang and os.path.splitext(target)[1].lower() in MEDIA_EXT:
            continue
        out.append(target)
    return out


def link_key(target):
    """Obsidian resolves on the basename, with or without the extension."""
    key = os.path.basename(target).lower()
    return key[:-3] if key.endswith(".md") else key


def read_page(path, rel):
    text = open(path, encoding="utf-8", errors="replace").read()
    if text.startswith(BOM):
        # A byte-order mark sits in front of the opening `---`, so the frontmatter pattern misses and
        # every field on the page — confidence, updated, type — silently reads as body text.
        text = text[1:]
    fm_raw, body, fields = "", text, {}
    match = FM_RE.match(text)
    if match:
        fm_raw = match.group(1)
        body = text[match.end():]
        for line in fm_raw.split("\n"):
            keyed = FM_KEY_RE.match(line)
            if keyed:
                fields[keyed.group(1)] = keyed.group(2).strip()
    aliases = []
    alias_inline = re.search(r"^aliases:\s*\[(.*?)\]", fm_raw, re.M)
    if alias_inline:
        aliases = [a.strip().strip("\"'") for a in alias_inline.group(1).split(",") if a.strip()]
    else:
        alias_block = re.search(r"^aliases:\s*\n((?:\s*-\s*.+\n?)+)", fm_raw, re.M)
        if alias_block:
            aliases = [a.strip().strip("\"'") for a in re.findall(r"-\s*(.+)", alias_block.group(1))]
    stem = os.path.basename(path)[:-3]
    return {
        "path": path,
        "rel": rel,
        "stem": stem,
        "type": strip_comment(fields.get("type", "")),
        "conf": strip_comment(fields.get("confidence", "")),
        "conf_raw": fields.get("confidence", ""),
        "has_conf": "confidence" in fields,
        "updated": parse_date(fields.get("updated")),
        "audited": parse_date(fields.get("audited")),
        "flagged": "flagged" in fields,
        "source_url": strip_url_comment(fields.get("source_url", "")),
        "aliases": aliases,
        "body": body,
        "links": link_targets(body),   # extracted once: the graph is built from it twice
        "bytes": len(text.encode("utf-8")),
    }


def collect_pages(wiki_dir, root):
    """Read every wiki page. Returns (pages, unreadable) — an unreadable file is never skipped
    silently, because a page the scan could not open is a hole in every count below it."""
    pages, unreadable = {}, []
    for dirpath, dirnames, filenames in os.walk(wiki_dir):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            try:
                pages[rel] = read_page(path, rel)
            except OSError as exc:
                unreadable.append(f"{rel} could not be read ({exc.__class__.__name__})")
    return pages, unreadable


def build_name_index(pages):
    by_name = {}
    for rel, page in pages.items():
        by_name.setdefault(page["stem"].lower(), set()).add(rel)
        for alias in page["aliases"]:
            by_name.setdefault(alias.lower(), set()).add(rel)
    return by_name


def build_vault_resolver(root, by_name):
    """Resolve a log link the way Obsidian does: stems and aliases, then vault paths and basenames."""
    basenames = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if not name.startswith("."):
                basenames.add(name.lower())

    def resolves(target):
        candidate = target.strip().rstrip("\\")
        if not candidate:
            return True
        if candidate.lower() in by_name:
            return True
        for form in (candidate, candidate + ".md"):
            if os.path.exists(os.path.join(root, form)):
                return True
        base = os.path.basename(candidate).lower()
        return base in basenames or (base + ".md") in basenames

    return resolves, len(basenames)


def inbound_degrees(pages, by_name, exclude_sources=()):
    """Distinct inbound source pages per page. log.md is history, never a link source."""
    inbound = {rel: set() for rel in pages}
    for rel, page in pages.items():
        if rel == LOG_REL or rel in exclude_sources:
            continue
        for target in page["links"]:
            for hit in by_name.get(link_key(target), ()):
                if hit != rel:
                    inbound[hit].add(rel)
    return {rel: len(sources) for rel, sources in inbound.items()}


def body_dates(page, today):
    """Every parseable date in the page body that is not in the future, oldest first."""
    found = []
    for raw in DATE_RE.findall(page["body"]):
        seen = parse_date(raw)
        if seen and seen <= today:
            found.append(seen)
    return sorted(found)


def later_body_date(page, today):
    """The latest body date that postdates `updated:` without being in the future, else None."""
    if page["updated"] is None:
        return None
    found = [seen for seen in body_dates(page, today) if seen > page["updated"]]
    return max(found) if found else None


def log_entries(body):
    heads = list(LOG_HEAD_RE.finditer(body))
    entries = []
    for i, head in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(body)
        text = body[head.start():end].rstrip("\n")
        entries.append({
            "date": parse_date(head.group(1)),
            "heading": head.group(0).strip(),
            "text": text,
            "bytes": len(text.encode("utf-8")),
        })
    return entries


def draw(rng, pool, count):
    """Deterministic sample: sort by path first so filesystem order never leaks in."""
    ordered = sorted(pool, key=lambda page: page["rel"])
    if count >= len(ordered):
        return ordered
    return sorted(rng.sample(ordered, count), key=lambda page: page["rel"])


def sample_row(tag, page):
    return (f"{tag}\t{page['rel']} · {page['type'] or '(no type)'} · {page['conf'] or '(none)'} · "
            f"upd={page['updated']} · aud={page['audited']} · in={page['inbound']} · {page['bytes']} B")


def main():
    parser = argparse.ArgumentParser(
        description="Deep-lint audit pools and frontmatter sweeps (read-only; prints, never writes).")
    parser.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    parser.add_argument("--baseline", default=None,
                        help="previous deep-lint date YYYY-MM-DD; absent = no-baseline mode")
    parser.add_argument("--today", default=None, help="override today's date (default: the system date)")
    # Cap 40 and tail 20 come from the deep-lint skill's Step 3 derivation: an audit read is
    # frontmatter plus the opening section (median 2.5 kB, p90 4.4 kB over 623 pages), so 40 reads
    # are ~100 kB ~ 25k tokens, and 40 changed + <=20 tail is a 60-page ceiling a real run has
    # already carried. Absolute, never a fraction of the changed set.
    parser.add_argument("--cap", type=int, default=40, help="pool A read cap (default 40)")
    parser.add_argument("--tail", type=int, default=20, help="pool B sample cap (default 20)")
    parser.add_argument("--seed", type=int, default=0, help="sampling seed (default 0; printed)")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()

    # A file name that is not valid UTF-8 arrives here as a surrogate; without this the first print
    # touching it aborts the whole report. Mangled beats missing, and it changes nothing otherwise.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")

    root = os.path.abspath(args.vault)
    wiki_dir = os.path.join(root, "wiki")
    failures = []

    if args.cap < 0 or args.tail < 0:
        # A negative cap silently truncates the always-include stratum through the slice that
        # applies it, and a negative tail crashes the sampler; neither may reach the pools.
        print(f"PROBE FAILED: --cap and --tail must be zero or more "
              f"(got cap={args.cap}, tail={args.tail})", file=sys.stderr)
        return 2

    today = parse_date(args.today) if args.today else datetime.date.today()
    if today is None:
        print(f"PROBE FAILED: --today {args.today!r} is not a YYYY-MM-DD date", file=sys.stderr)
        return 2
    baseline = None
    if args.baseline:
        baseline = parse_date(args.baseline)
        if baseline is None:
            print(f"PROBE FAILED: --baseline {args.baseline!r} is not a YYYY-MM-DD date", file=sys.stderr)
            return 2

    if not os.path.isdir(wiki_dir):
        print(f"PROBE FAILED: no wiki directory under {root}", file=sys.stderr)
        return 2

    pages, unreadable = collect_pages(wiki_dir, root)
    if not pages:
        print(f"PROBE FAILED: wiki directory holds no Markdown pages ({wiki_dir})", file=sys.stderr)
        return 2
    for note in unreadable:
        failures.append(note)

    by_name = build_name_index(pages)
    degrees = inbound_degrees(pages, by_name)
    for rel, page in pages.items():
        page["inbound"] = degrees[rel]

    eligible = sorted(
        (p for p in pages.values() if p["type"] != "map" and p["rel"] not in (INDEX_REL, LOG_REL)),
        key=lambda page: page["rel"])
    if not eligible:
        print(f"PROBE FAILED: no audit-eligible page under {wiki_dir} — every page found is a map "
              f"or a registry, so there is nothing for the audit to sample", file=sys.stderr)
        return 2

    result = {
        "vault": root,
        "today": str(today),
        "baseline": str(baseline) if baseline else None,
        "no_baseline_mode": baseline is None,
        "cap": args.cap,
        "tail_cap": args.tail,
        "seed": args.seed,
        "pages_scanned": len(pages),
        "eligible": len(eligible),
    }

    # --- confidence coverage -------------------------------------------------------------
    invalid = [{"path": p["rel"],
                "value": ((p["conf_raw"][:60] or "(empty)") if p["has_conf"] else "(missing)")}
               for p in eligible if p["conf"] not in VALID_CONFIDENCE]
    commented = sum(1 for p in eligible if "#" in p["conf_raw"])
    result["confidence"] = {
        "valid": len(eligible) - len(invalid),
        "invalid": invalid,
        "comment_stripped": commented,
        "distribution": {tier: sum(1 for p in eligible if p["conf"] == tier) for tier in VALID_CONFIDENCE},
    }

    # --- pools ----------------------------------------------------------------------------
    classifiable = [p for p in eligible if p["updated"] is not None]
    unclassifiable = [p for p in eligible if p["updated"] is None]
    # The date split's positive control, per the runbook: a baseline older than every page must
    # return every classifiable page. DERIVED as one day before the oldest `updated:` in the vault,
    # never a fixed year — a constant stops being "older than every page" as soon as one page
    # predates it, and the guard then fails a healthy run instead of catching a broken probe.
    control_date = (min(p["updated"] for p in classifiable) - datetime.timedelta(days=1)
                    if classifiable else None)
    control_hits = sum(1 for p in classifiable if p["updated"] >= control_date) if control_date else 0
    if classifiable and control_hits != len(classifiable):
        failures.append("baseline control did not return every classifiable eligible page")
    if not classifiable:
        failures.append("no eligible page carries a parseable updated: date, so the pool split "
                        "could not run and its control has nothing to return")

    if baseline is None:
        pool_a = list(classifiable)
        pool_b = []
    else:
        pool_a = [p for p in classifiable if p["updated"] >= baseline]
        pool_b = [p for p in classifiable if p["updated"] < baseline]
    # A flagged page belongs to pool A whatever its date: the flagged stratum below is filled
    # from pool A, and a page flagged without an `updated:` bump otherwise waits in the tail.
    lifted = [p for p in pool_b if p["flagged"]]
    pool_a = pool_a + lifted
    pool_b = [p for p in pool_b if not p["flagged"]]

    result["pools"] = {
        "pool_a": len(pool_a),
        "pool_b": len(pool_b),
        "flagged_lifted": len(lifted),
        "classifiable": len(classifiable),
        "unclassifiable": [p["rel"] for p in unclassifiable],
        "control_date": str(control_date) if control_date else None,
        "control_hits": control_hits,
    }

    # --- strata and the cap ---------------------------------------------------------------
    rng = Random(args.seed)
    flagged = sorted((p for p in pool_a if p["flagged"]), key=lambda page: page["rel"])
    rest = [p for p in pool_a if not p["flagged"]]
    auth = sorted((p for p in rest if p["conf"] == "authoritative"), key=lambda page: page["rel"])
    auth_rels = {p["rel"] for p in auth}
    chigh = sorted((p for p in rest if p["rel"] not in auth_rels and p["conf"] == "high"
                    and p["type"] in COMPILED_TYPES), key=lambda page: page["rel"])
    chigh_rels = {p["rel"] for p in chigh}
    other = sorted((p for p in rest if p["rel"] not in auth_rels and p["rel"] not in chigh_rels),
                   key=lambda page: page["rel"])

    overflow = 0
    under_cap = len(rest) <= args.cap
    if under_cap:
        take_auth, take_high, take_other = list(auth), list(chigh), list(other)
    elif len(auth) >= args.cap:
        take_auth = auth[:args.cap]
        take_high, take_other = [], []
        overflow = len(auth) - args.cap
    else:
        take_auth = list(auth)
        remaining = args.cap - len(auth)
        # Two-thirds compiled/derived-high, one-third everything else changed; either pool short
        # of its share hands the slack to the other. The two-thirds split is set by judgement,
        # unmeasured (deep-lint Step 3 says so, and the per-stratum re-tier counts will settle it).
        want_high = round(remaining * 2 / 3)
        want_other = remaining - want_high
        n_high = min(len(chigh), want_high)
        n_other = min(len(other), want_other + (want_high - n_high))
        n_high = min(len(chigh), remaining - n_other)
        take_high = draw(rng, chigh, n_high)
        take_other = draw(rng, other, n_other)

    # --- tail -----------------------------------------------------------------------------
    def tail_key(page):
        return (page["audited"] or page["updated"], page["rel"])

    pool_b_sorted = sorted(pool_b, key=tail_key)
    if not pool_b_sorted:
        third = []
    elif len(pool_b_sorted) < TAIL_WHOLE_POOL_BELOW:
        third = list(pool_b_sorted)
    else:
        third = pool_b_sorted[:len(pool_b_sorted) // 3]
    tail_sample = sorted(draw(rng, third, min(args.tail, len(third))), key=tail_key)
    key_range = None
    if third:
        key_range = (str(tail_key(third[0])[0]), str(tail_key(third[-1])[0]))

    audited_now = len(flagged) + len(take_auth) + len(take_high) + len(take_other)
    result["strata"] = {
        "flagged": {"taken": len(flagged), "of": len(flagged)},
        "authoritative": {"taken": len(take_auth), "of": len(auth), "overflow": overflow},
        "compiled_high": {"taken": len(take_high), "of": len(chigh)},
        "other": {"taken": len(take_other), "of": len(other)},
        "under_cap": under_cap,
        "audited": audited_now,
    }
    result["tail"] = {
        "pool": len(pool_b),
        "oldest_third": len(third),
        "sampled": len(tail_sample),
        "key_range": key_range,
    }
    result["sample"] = (
        [{"stratum": "FLAGGED", "path": p["rel"]} for p in flagged]
        + [{"stratum": "AUTH", "path": p["rel"]} for p in take_auth]
        + [{"stratum": "A-HIGH", "path": p["rel"]} for p in take_high]
        + [{"stratum": "A-OTHER", "path": p["rel"]} for p in take_other]
        + [{"stratum": "UNCLASS", "path": p["rel"]} for p in unclassifiable]
        + [{"stratum": "TAIL", "path": p["rel"]} for p in tail_sample]
    )

    # --- updated: accuracy sweep ----------------------------------------------------------
    accuracy = []
    for page in sorted(pages.values(), key=lambda page: page["rel"]):
        if page["rel"] == LOG_REL:
            continue
        latest = later_body_date(page, today)
        if latest:
            accuracy.append({"path": page["rel"], "field": str(page["updated"]), "latest": str(latest)})
    # In-memory control: a copy of a real page whose `updated:` is planted one day BEFORE the oldest
    # body date that page itself carries must be caught by the same sweep. The planted date is
    # derived from the page, never fixed: a constant silently stops firing on any vault whose pages
    # predate it, turning a working sweep into a probe failure (a fixed 2026-01-01 did exactly that
    # against a 2024-dated fixture). index.md is preferred because it carries the most dates.
    control_base, control_dates = None, []
    preferred = pages.get(INDEX_REL)
    if preferred is not None and body_dates(preferred, today):
        control_base, control_dates = preferred, body_dates(preferred, today)
    else:
        for candidate in sorted(pages.values(), key=lambda page: page["rel"]):
            if candidate["rel"] == LOG_REL:
                continue
            dates = body_dates(candidate, today)
            if len(dates) > len(control_dates):
                control_base, control_dates = candidate, dates
    if control_base is None:
        # No page carries a usable body date. That is a legitimate young vault, not a broken probe,
        # so the control falls back to a synthetic page through the SAME function and says so.
        planted_date = today - datetime.timedelta(days=2)
        synthetic = {"updated": planted_date,
                     "body": f"a synthetic control body dated {today - datetime.timedelta(days=1)}."}
        caught = later_body_date(synthetic, today)
        label = "a synthetic page (no vault page carries a body date)"
    else:
        planted_date = control_dates[0] - datetime.timedelta(days=1)
        planted = dict(control_base)
        planted["updated"] = planted_date
        caught = later_body_date(planted, today)
        label = f"a copy of {control_base['rel']}"
    accuracy_control = {"base": label, "planted": str(planted_date), "caught": bool(caught)}
    if not caught:
        failures.append(f"updated: control planted on {label} was not caught")
    result["updated_accuracy"] = {"hits": accuracy, "control": accuracy_control}

    # --- orphans ---------------------------------------------------------------------------
    def orphan_candidates(degree_map):
        return [p["rel"] for p in sorted(pages.values(), key=lambda page: page["rel"])
                if p["rel"] not in (INDEX_REL, LOG_REL)
                and not p["rel"].startswith("wiki/maps/")
                and degree_map[p["rel"]] == 0]

    orphans = orphan_candidates(degrees)
    linked = sum(1 for p in pages.values() if p["inbound"] > 0)
    if linked == 0:
        failures.append("no page carries an inbound link — the link graph probe is broken")
    strict_degrees = inbound_degrees(pages, by_name, exclude_sources={INDEX_REL})
    strict_orphans = orphan_candidates(strict_degrees)
    result["orphans"] = {
        "orphans": orphans,
        "linked_control": linked,
        # Information, never a finding: the index registers every page, so it masks graph isolation.
        # These pages are correctly indexed and are NOT orphans; the figure only tells the agent how
        # much of the graph's connectivity rests on the index alone. Nested and named so a consumer
        # cannot mistake it for the findings list above.
        "diagnostic_only": {
            "note": "information, not a finding: pages whose only inbound link is wiki/index.md",
            "orphans_excluding_index_as_source": strict_orphans,
        },
    }

    # --- index consistency -----------------------------------------------------------------
    index_page = pages.get(INDEX_REL)
    if index_page is None:
        failures.append("wiki/index.md is absent, so index consistency did not run")
        result["index"] = None
    else:
        registered = {link_key(t) for t in index_page["links"]}
        # stem -> EVERY page carrying it. Two folders may hold the same stem (a benchmark page and
        # its source page, say); a stem->one-path map drops all but one of them, and an unindexed
        # sibling then disappears from the finding instead of being reported.
        on_disk = {}
        for page in pages.values():
            if page["rel"] in (INDEX_REL, LOG_REL):
                continue
            on_disk.setdefault(page["stem"].lower(), []).append(page["rel"])
        unindexed = sorted(rel for stem, rels in on_disk.items() if stem not in registered
                           for rel in rels)
        dangling = sorted(name for name in registered if name not in on_disk and name not in by_name)
        if not registered:
            failures.append("wiki/index.md registers no page — the index probe is broken")
        result["index"] = {"registered": len(registered), "pages_on_disk": sum(
            len(rels) for rels in on_disk.values()), "shared_stems": sorted(
            stem for stem, rels in on_disk.items() if len(rels) > 1),
            "unindexed": unindexed, "dangling": dangling}

    # --- log link health and entry sizes ----------------------------------------------------
    log_page = pages.get(LOG_REL)
    if log_page is None:
        failures.append("wiki/log.md is absent, so log link health and entry sizes did not run")
        result["log"] = None
    else:
        resolves, basename_count = build_vault_resolver(root, by_name)
        entries = log_entries(log_page["body"])
        scoped = [e for e in entries if baseline is None or (e["date"] and e["date"] >= baseline)]
        unresolved, checked = [], 0
        for entry in scoped:
            for target in link_targets(entry["text"]):
                checked += 1
                if not resolves(target):
                    unresolved.append({"heading": entry["heading"], "target": target})
        sizes = [e["bytes"] for e in scoped]
        # Distinguish a young log from a broken entry pattern, or a zero here is unreadable. A log
        # with no `## ` heading at all has nothing to check and says so; a log that HAS headings yet
        # yields no dated entry means the entry pattern no longer matches the format, which is a
        # premise failure and must never print as "unresolved: 0".
        headings = len(re.findall(r"(?m)^## ", log_page["body"]))
        if not entries and headings:
            failures.append(f"wiki/log.md has heading lines ({headings}) but no dated entry "
                            f"matched — the log entry pattern is broken")
        result["log"] = {
            "entries_total": len(entries),
            "entries_scoped": len(scoped),
            "headings": headings,
            "has_entries": bool(entries),
            "links_checked": checked,
            "unresolved": unresolved,
            "vault_basenames": basename_count,
            "sizes": {
                "count": len(sizes),
                "median": round(statistics.median(sizes)) if sizes else None,
                "mean": round(statistics.mean(sizes)) if sizes else None,
                "max": max(sizes) if sizes else None,
                "log_total": os.path.getsize(log_page["path"]),
            },
        }

    # --- source_url freshness candidates ------------------------------------------------------
    with_url = [p for p in pages.values() if p["source_url"].startswith("http")]
    mutable = [p for p in with_url if not IMMUTABLE_HOST.search(p["source_url"])]

    def freshness_score(page):
        age = (today - page["updated"]).days if page["updated"] else 0
        return CONF_WEIGHT.get(page["conf"], 1) * max(age, 0) * (1 + page["inbound"])

    ranked = sorted(mutable, key=lambda page: (-freshness_score(page), page["rel"]))[:FRESHNESS_TOP]
    result["freshness"] = {
        "with_url": len(with_url),
        "mutable": len(mutable),
        "immutable": len(with_url) - len(mutable),
        "candidates": [{"path": p["rel"], "confidence": p["conf"], "updated": str(p["updated"]),
                        "inbound": p["inbound"], "score": freshness_score(p), "url": p["source_url"]}
                       for p in ranked],
    }

    # --- the three Step 3 report lines ----------------------------------------------------------
    coverage = sum(1 for p in eligible if p["audited"] is not None)
    percent = (100.0 * coverage / len(eligible)) if eligible else 0.0
    report_lines = [
        (f"changed: audited {audited_now} of {len(pool_a)} — flagged {len(flagged)} (Step 2) · "
         f"authoritative {len(take_auth)} of {len(auth)} · "
         f"compiled/derived-high {len(take_high)} of {len(chigh)} · "
         f"other {len(take_other)} of {len(other)} · not audited {len(pool_a) - audited_now}"),
        (f"tail: sampled {len(tail_sample)} of {len(third)} least-recently-audited "
         f"(of {len(pool_b)} unchanged)"),
        f"audited: coverage {coverage} of {len(eligible)} eligible pages ({percent:.1f}%)",
    ]
    result["report_lines"] = report_lines
    result["probe_failures"] = failures

    if args.format == "json":
        json.dump(result, sys.stdout, indent=1, sort_keys=True)
        sys.stdout.write("\n")
        for note in failures:
            print(f"PROBE FAILED: {note}", file=sys.stderr)
        return 2 if failures else 0

    # --- text rendering -------------------------------------------------------------------------
    mode = f"baseline={baseline}" if baseline else "baseline=none"
    print(f"audit-pools: vault={root} today={today} {mode} cap={args.cap} tail={args.tail} "
          f"seed={args.seed} format=text")
    if baseline is None:
        print("NO-BASELINE MODE: no previous deep-lint date given — the whole vault is one pool, "
              "drawn at the same cap; the tail pool is empty by construction.")

    print("--- ELIGIBLE ---")
    print(f"pages scanned: {len(pages)} · audit-eligible: {len(eligible)} "
          f"(excludes type: map, index.md, log.md)   (nonzero totals = probe ran)")

    print("--- CONFIDENCE COVERAGE ---")
    print(f"valid: {result['confidence']['valid']} of {len(eligible)} · "
          f"inline comments stripped on {commented} pages · invalid or missing: {len(invalid)}")
    for row in invalid:
        print(f"  {row['path']} — {row['value']}")
    print("  distribution: " + " · ".join(
        f"{tier} {result['confidence']['distribution'][tier]}" for tier in VALID_CONFIDENCE))

    print("--- POOLS ---")
    print(f"pool A (changed, updated >= {baseline if baseline else 'n/a — whole vault'}): {len(pool_a)}"
          + (f" · flagged lifted from below the baseline: {len(lifted)}" if lifted else ""))
    print(f"pool B (unchanged): {len(pool_b)}")
    print(f"unclassifiable (no parseable updated:): {len(unclassifiable)}")
    for page in unclassifiable:
        print(f"  {page['rel']}")
    if control_date is None:
        print("pool-control: n/a — no eligible page carries a parseable updated: date, so the "
              "split could not run (reported as a probe failure below)")
    else:
        print(f"pool-control: baseline {control_date} returns {control_hits} of {len(classifiable)} "
              f"classifiable eligible pages   (control date = one day before the oldest updated:)")

    print("--- STRATA (fill order) ---")
    print(f"flagged: {len(flagged)} of {len(flagged)} (Step 2 — no cap cost)")
    if overflow:
        print(f"authoritative: {len(take_auth)} of {len(auth)} — cap reached, {overflow} not audited")
    else:
        print(f"authoritative: {len(take_auth)} of {len(auth)}")
    print(f"compiled/derived-high: {len(take_high)} of {len(chigh)}")
    print(f"other: {len(take_other)} of {len(other)}")
    if under_cap:
        print(f"cap: audited {len(rest)} of {len(rest)} (under cap — no sampling)")
    else:
        print(f"cap: {args.cap} · always-include first, then two-thirds compiled/derived-high, "
              f"one-third other, slack flowing between (split set by judgement, unmeasured)")

    print("--- TAIL ---")
    print(f"tail pool: {len(pool_b)} unchanged · oldest third: {len(third)} · "
          f"sampled: {len(tail_sample)} (cap {args.tail})")
    if key_range:
        print(f"key range: {key_range[0]} -> {key_range[1]}   (key = audited: else updated:)")
    else:
        print("key range: n/a — the tail pool is empty")

    print("--- SAMPLE (fill order) ---")
    for page in flagged:
        print(sample_row("FLAGGED", page))
    for page in take_auth:
        print(sample_row("AUTH", page))
    for page in take_high:
        print(sample_row("A-HIGH", page))
    for page in take_other:
        print(sample_row("A-OTHER", page))
    for page in unclassifiable:
        print(sample_row("UNCLASS", page))
    for page in tail_sample:
        print(sample_row("TAIL", page))
    print(f"sample size: {len(result['sample'])} pages")

    print("--- UPDATED ACCURACY ---")
    print(f"updated-accuracy: {len(accuracy)} pages carry a body date later than the field")
    for row in accuracy:
        print(f"  {row['path']} {row['field']} -> {row['latest']}")
    state = "caught" if accuracy_control["caught"] else "NOT CAUGHT"
    print(f"updated-control: planted {accuracy_control['planted']} on {accuracy_control['base']} "
          f"-> {state}")

    print("--- ORPHANS ---")
    print(f"orphans: {len(orphans)} (index, log and maps exempt)")
    for rel in orphans:
        print(f"  {rel}")
    print(f"inbound-control: {linked} pages carry >= 1 inbound link")
    print(f"orphans with index.md excluded as a source: {len(strict_orphans)}   "
          f"[DIAGNOSTIC, NOT A FINDING: these pages are indexed and are not orphans; the figure "
          f"only shows how much connectivity rests on the index alone]")
    for rel in strict_orphans[:10]:
        print(f"  diagnostic: {rel}")
    if len(strict_orphans) > 10:
        print(f"  diagnostic: … and {len(strict_orphans) - 10} more")

    print("--- INDEX CONSISTENCY ---")
    if result["index"] is None:
        print("PROBE FAILED: wiki/index.md is absent")
    else:
        print(f"registered names: {result['index']['registered']} · "
              f"pages on disk: {result['index']['pages_on_disk']} · "
              f"unindexed on disk: {len(result['index']['unindexed'])} · "
              f"registered without a page or alias: {len(result['index']['dangling'])}")
        for rel in result["index"]["unindexed"]:
            print(f"  unindexed: {rel}")
        for name in result["index"]["dangling"]:
            print(f"  registered but absent: {name}")
        for stem in result["index"]["shared_stems"]:
            print(f"  note: {stem} is the stem of more than one page — every one of them is "
                  f"checked against the index, and Obsidian resolves such a link ambiguously")

    print("--- LOG LINK HEALTH ---")
    if result["log"] is None:
        print("PROBE FAILED: wiki/log.md is absent")
    elif not result["log"]["has_entries"]:
        print(f"log link health: n/a — wiki/log.md was read ({result['log']['sizes']['log_total']} B) "
              f"and carries no dated entry, so no link was checked. A young log, not a clean bill.")
        print("--- LOG ENTRY SIZES ---")
        print("entry sizes: n/a — no dated entry to measure")
    else:
        scope = f"entries >= {baseline}" if baseline else "all entries (no baseline)"
        print(f"{scope}: {result['log']['entries_scoped']} of {result['log']['entries_total']} · "
              f"links checked: {result['log']['links_checked']} · "
              f"unresolved: {len(result['log']['unresolved'])} "
              f"(resolved vault-wide against {result['log']['vault_basenames']} file names)")
        for row in result["log"]["unresolved"]:
            print(f"  {row['heading']} -> unresolved: {row['target']}")
        sizes = result["log"]["sizes"]
        print("--- LOG ENTRY SIZES ---")
        if sizes["count"]:
            print(f"entries: {sizes['count']} · median {sizes['median']} B · mean {sizes['mean']} B · "
                  f"max {sizes['max']} B · log.md total {sizes['log_total']} B")
        else:
            print(f"entries: 0 in scope — no entry at or after {baseline}, so no size was measured "
                  f"(the log holds {result['log']['entries_total']} entries in all) · "
                  f"log.md total {sizes['log_total']} B")

    print("--- FRESHNESS CANDIDATES ---")
    print(f"source_url pages: {result['freshness']['with_url']} · mutable {result['freshness']['mutable']} "
          f"· immutable {result['freshness']['immutable']} (top {FRESHNESS_TOP} by "
          f"confidence x age x inbound degree)")
    for row in result["freshness"]["candidates"]:
        print(f"  score={row['score']} {row['path']} · {row['confidence']} · upd={row['updated']} · "
              f"in={row['inbound']} · {row['url'][:100]}")

    print("--- REPORT LINES ---")
    for line in report_lines:
        print(line)

    for note in failures:
        print(f"PROBE FAILED: {note}")
    return 2 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
