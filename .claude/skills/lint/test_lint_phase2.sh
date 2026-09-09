#!/usr/bin/env bash
# test_lint_phase2.sh — regression fixtures for the stdout-only lint scripts: check-orphans.py,
# tier-cap-check.py, anomaly-lister.py, check-links.py's sources arm and check-index.py, plus
# the root guard every script in this directory carries. Every fixture is built under
# a fresh mktemp -d and removed at exit; the vault is never touched. The final leg is the
# stdout-only proof: a read-only copy, checksum manifests of the fixture AND of the script
# home before and after, plus a source grep for write patterns.
#
# Three register entries settled here (2026-09-07): the wrong-root guard (2026-09-06), the
# unresolved `sources:` paths (2026-09-03) and index consistency as a script (2026-09-02).
# Every fixture root therefore carries raw/ as well as wiki/ — a root without both is refused
# by design, and the root-guard section below is where that refusal is asserted.
#
# Three fixtures. `planted` carries one page per rule the scripts enforce, `clean` the same
# shapes with nothing wrong, and `edge` the malformed and awkward inputs a real vault throws
# at a parser: CRLF, a BOM, an unterminated frontmatter, a quoted tier, block-form lists,
# unicode and apostrophe page names, embeds, self-links, and a documented override beside
# its undocumented twin.
#
# Run:  bash test_lint_phase2.sh      (exit 0 = every leg passed)
set -uo pipefail

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORPH="$HOME_DIR/check-orphans.py"
TIER="$HOME_DIR/tier-cap-check.py"
ANOM="$HOME_DIR/anomaly-lister.py"
LINKS="$HOME_DIR/check-links.py"      # the link rules check-orphans.py replicates
INDEX="$HOME_DIR/check-index.py"      # index consistency, formerly a hand comparison
PAL="$HOME_DIR/apply-palette.py"      # the one script here that writes, on request
SHIP="$HOME_DIR/check-shipped-links.py"
QMD="$HOME_DIR/check-qmd-registry.sh"
FLAGS="$HOME_DIR/check_flag_admissions.py"   # a damage admission in prose with no flagged: key

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '    ok   — %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL   — %s\n' "$1"; }
# eq <name> <expected> <actual>
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1  [want '$2', got '$3']"; fi; }

W="$(mktemp -d)"
ERR="$W/stderr.txt"
cleanup(){ chmod -R u+rwX "$W" 2>>"$ERR"; rm -rf "$W"; }
trap cleanup EXIT

# Pull one dotted key out of a JSON document on stdin.
jget(){ python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d[int(k)] if k.lstrip("-").isdigit() else d[k]
print(json.dumps(d, sort_keys=True) if isinstance(d, (dict, list)) else d)
' "$1"; }

# Count entries of one tier-cap list whose page matches a substring.
# count_in <list-key> <page-substring> [<rule>]   — reads a tier-cap JSON document on stdin.
count_in(){ python3 -c '
import json, sys
d = json.load(sys.stdin)
key, frag = sys.argv[1], sys.argv[2]
rule = sys.argv[3] if len(sys.argv) > 3 else None
print(sum(1 for v in d[key]
          if frag in v["page"] and (rule is None or v.get("rule", v.get("kind")) == rule)))
' "$@"; }

# ---------------------------------------------------------------- fixture builders
# rawbase <dir>  — the raw/ layer. Two jobs: a fixture root must hold raw/ AND wiki/ or every
# script refuses it (the root guard), and every raw file a fixture page names in `sources:`
# has to exist or the clean fixture would report dangling sources of its own.
rawbase(){ local d="$1" f
  mkdir -p "$d/raw/1-articles" "$d/raw/2-papers" "$d/raw/4-webinfo" "$d/raw/6-social"
  for f in 1-articles/a 1-articles/b 2-papers/paper 2-papers/only 4-webinfo/a 4-webinfo/b \
           6-social/a 6-social/b 6-social/c 6-social/post 6-social/mirror; do
    printf -- '# raw capture\nfixture provenance file.\n' > "$d/raw/$f.md"
  done
}

# base <dir>  — the registries, a map and a hub every non-planted page hangs off.
base(){ local d="$1"
  rawbase "$d"
  mkdir -p "$d/wiki/concepts" "$d/wiki/tools" "$d/wiki/sources" "$d/wiki/maps"
  cat > "$d/wiki/index.md" <<'MDFIX'
---
title: "Index"
type: index
confidence: high
---
## Concepts
- [[Hub]] — the fixture hub.
MDFIX
  cat > "$d/wiki/log.md" <<'MDFIX'
---
title: "Log"
type: log
confidence: high
---
## [2026-01-01] ingest | fixture
- **Changed**: created [[LogLinked]]
MDFIX
  cat > "$d/wiki/maps/topic-map.md" <<'MDFIX'
---
title: "Topic Map"
type: map
---
## Map
- [[Hub]] — nothing links back here, and a map is exempt.
MDFIX
}

# hub <dir> <link...>  — writes the hub page carrying the given link targets.
hub(){ local d="$1"; shift
  { printf -- '---\ntitle: "Hub"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nThe fixture hub.\n\n## Related\n'
    local t; for t in "$@"; do printf -- '- [[%s]]\n' "$t"; done
    printf -- '```\n[[NotALink]]\n```\n`[[AlsoNotALink]]` <!-- [[NorThis]] -->\n'
  } > "$d/wiki/concepts/Hub.md"
}

# The planted fixture: every case the brief names.
planted(){ local d="$W/planted"; rm -rf "$d"; base "$d"
  hub "$d" "AliasName" "BadTier" "GoodTier" "social-post" "SinglePrimary" "Commented" "OpenConflict" \
      "SettledConflict" "Flagged" "Thin" "OddTier" "MapWithTier" "social-override"
  printf -- '---\ntitle: "Orphan"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nNothing links here.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/Orphan.md"
  printf -- '---\ntitle: "LogLinked"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nOnly the append-only log links here.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/LogLinked.md"
  printf -- '---\ntitle: "Aliased"\ntype: concept\nconfidence: medium\naliases: [AliasName]\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nReachable only through its alias.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/Aliased.md"
  printf -- '---\ntitle: "BadTier"\ntype: tool\nconfidence: authoritative\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nA compiled tool page over its cap.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/tools/BadTier.md"
  printf -- '---\ntitle: "GoodTier"\ntype: tool\nconfidence: high\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nA compiled tool page at its cap.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/tools/GoodTier.md"
  printf -- '---\ntitle: "Social post"\ntype: source\nconfidence: high\nsources: [raw/6-social/post.md]\nsource_url: "https://x.com/someone/status/1"\n---\n\n## Summary\nA single social capture badged above its boundary.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/sources/social-post.md"
  printf -- '---\ntitle: "Social override"\ntype: source\nconfidence: medium   # override of the social boundary, recorded by the owner: a first-party post mirrored by the official documentation\nsources: [raw/6-social/mirror.md]\n---\n\n## Summary\nThe same shape, with the judgement recorded on the tier line.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/sources/social-override.md"
  printf -- '---\ntitle: "SinglePrimary"\ntype: concept\nconfidence: high\nsources: [raw/2-papers/paper.md]\n---\n\n## Definition\nOne primary source, compiled at the cap.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/SinglePrimary.md"
  printf -- '---\ntitle: "Commented"\ntype: tool\nconfidence: high   # corroborated across two official sources\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nAn inline comment on the tier value.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/tools/Commented.md"
  printf -- '---\ntitle: "OddTier"\ntype: concept\nconfidence: pretty-sure\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA tier outside the five.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/OddTier.md"
  printf -- '---\ntitle: "MapWithTier"\ntype: map\nconfidence: high\n---\n\n## Map\n- [[Hub]] — a map is meant to omit confidence.\n' > "$d/wiki/maps/MapWithTier.md"
  cat > "$d/wiki/concepts/OpenConflict.md" <<'MDFIX'
---
title: "OpenConflict"
type: concept
confidence: medium
sources: [raw/1-articles/a.md, raw/1-articles/b.md]
---

## Definition
A page holding an unsettled disagreement.

## Conflicts / Open Questions
- Two captures give different figures for the same quantity and nothing decides between them.

## Related
- [[Hub]]
MDFIX
  cat > "$d/wiki/concepts/SettledConflict.md" <<'MDFIX'
---
title: "SettledConflict"
type: concept
confidence: medium
sources: [raw/1-articles/a.md, raw/1-articles/b.md]
---

## Definition
A page whose disagreement was settled.

## Conflicts / Open Questions
- The two figures disagreed; resolved 2026-01-02 in favour of the later capture.

## Related
- [[Hub]]
MDFIX
  printf -- '---\ntitle: "Flagged"\ntype: concept\nconfidence: medium\nflagged: 2026-01-01 the mechanism may have changed since capture\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA page carrying a freshness flag.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/Flagged.md"
  printf -- '---\ntitle: "Thin"\ntype: concept\nconfidence: low\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA thin page resting on a single witness, and the claim stays unverified.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/Thin.md"
  printf -- '[{"page": "wiki/tools/GoodTier.md", "tier": "authoritative"}, {"page": "wiki/tools/Commented.md", "tier": "high"}]\n' > "$W/verdicts.json"
  printf -- '%s' "$d"
}

# The clean fixture: the same shapes, none of them anomalous.
clean(){ local d="$W/clean"; rm -rf "$d"; base "$d"
  hub "$d" "AliasName" "GoodTier"
  printf -- '---\ntitle: "Aliased"\ntype: concept\nconfidence: medium\naliases: [AliasName]\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA clean page.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/concepts/Aliased.md"
  printf -- '---\ntitle: "GoodTier"\ntype: tool\nconfidence: high\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nA clean tool page.\n\n## Related\n- [[Hub]]\n' > "$d/wiki/tools/GoodTier.md"
  printf -- '%s' "$d"
}

# The edge fixture: malformed and awkward inputs, one page per failure mode.
edge(){ local d="$W/edge"; rm -rf "$d"; rawbase "$d"
  mkdir -p "$d/wiki/concepts" "$d/wiki/tools" "$d/wiki/sources" "$d/wiki/maps" "$d/assets"
  printf 'not a real image\n' > "$d/assets/diagram.png"
  printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n\n- [[EdgeHub]]\n- [[CatalogueOnly]]\n' > "$d/wiki/index.md"
  printf -- '---\ntitle: "CatalogueOnly"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nNothing but the catalogue points here.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/CatalogueOnly.md"
  { printf -- '---\ntitle: "EdgeHub"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Related\n'
    printf -- '- [[CrlfAlias]]\n- [[SectionLink#Definition]]\n- [[PipeLink|a different label]]\n'
    printf -- '- [[EmptyConflict]]\n- [[TailConflict]]\n- [[SpanMarker]]\n- [[Unclosed]]\n- [[BomPage]]\n'
    printf -- '- [[QuotedTier]]\n- [[CrlfSingle]]\n- [[OverrideUsed]]\n- [[OverrideUnused]]\n'
    printf -- '- [[social-undocumented]]\n- [[social-documented]]\n- [[social-verylow]]\n'
    printf -- '- [[OddTierOverride]]\n- [[NullTier]]\n- [[MapOverride]]\n- [[Media]]\n'
  } > "$d/wiki/concepts/EdgeHub.md"
  # CRLF frontmatter, block-form aliases, a flagged: line — all must still parse.
  printf -- '---\r\ntitle: "CrlfAliased"\r\ntype: concept\r\nconfidence: medium\r\nflagged: 2026-02-02 a CRLF page still carries its flag\r\naliases:\r\n  - CrlfAlias\r\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\r\n---\r\n\r\n## Definition\r\nReachable only through a block-form alias in a CRLF frontmatter.\r\n\r\n## Related\r\n- [[EdgeHub]]\r\n' > "$d/wiki/concepts/CrlfAliased.md"
  # A byte-order mark ahead of the frontmatter fence.
  printf -- '\xef\xbb\xbf---\ntitle: "BomPage"\ntype: concept\nconfidence: medium\nflagged: 2026-02-03 a BOM must not hide this line\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA page whose bytes open with a BOM.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/BomPage.md"
  printf -- '# NoFrontmatter\nA page with no frontmatter block at all, and nothing links to it, whose claim stays unverified.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/NoFrontmatter.md"
  printf -- '---\ntitle: "Unclosed"\ntype: concept\nconfidence: medium\nflagged: 2026-02-04 this line sits below a fence that never closes\n\n## Definition\nThe frontmatter fence is never closed. [[EdgeHub]]\n' > "$d/wiki/concepts/Unclosed.md"
  printf -- '---\ntitle: "Unicode"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA page whose name is not ASCII, and nothing links to it. It rests on a single witness.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/Ünïcødé Påge.md"
  printf -- '---\ntitle: "Apostrophe"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA page name carrying an apostrophe, linked by nobody.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/Ada's Note.md"
  printf -- '---\ntitle: "SectionLink"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nCredited only through a section link.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/SectionLink.md"
  printf -- '---\ntitle: "PipeLink"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nCredited only through an alias-piped link.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/PipeLink.md"
  printf -- '---\ntitle: "SelfOnly"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nThis page links to [[SelfOnly]] and nothing else links to it.\n\n## Related\n- [[SelfOnly]]\n' > "$d/wiki/concepts/SelfOnly.md"
  printf -- '---\ntitle: "Media"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nAn embed, not a page link: ![[diagram.png]]\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/Media.md"
  printf -- '---\ntitle: "EmptyConflict"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nAn empty conflict block records nothing.\n\n## Conflicts / Open Questions\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/EmptyConflict.md"
  # No trailing newline after the last conflict line, and the block ends the file.
  printf -- '---\ntitle: "TailConflict"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nSee [[EdgeHub]].\n\n## Conflicts / Open Questions\n- The last line of the file, with no newline after it, and nothing decides between the two.' > "$d/wiki/concepts/TailConflict.md"
  printf -- '---\ntitle: "SpanMarker"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nThe marker `unverified` sits inside a code span here, while the word unverified also appears in plain prose.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/SpanMarker.md"
  printf -- '---\ntitle: "QuotedTier"\ntype: tool\nconfidence: "authoritative"\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nA quoted tier value over its cap.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/tools/QuotedTier.md"
  printf -- '---\r\ntitle: "CrlfSingle"\r\ntype: tool\r\nconfidence: authoritative\r\nsources:\r\n  - "raw/2-papers/only.md"\r\n---\r\n\r\n## Definition\r\nCRLF, block-form and quoted: one source document.\r\n\r\n## Related\r\n- [[EdgeHub]]\r\n' > "$d/wiki/tools/CrlfSingle.md"
  printf -- '---\ntitle: "OverrideUsed"\ntype: tool\nconfidence: authoritative   # override recorded by the owner on 2026-02-05: the vendor specification is the primary document\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nOver the type cap, with the judgement recorded.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/tools/OverrideUsed.md"
  printf -- '---\ntitle: "OverrideUnused"\ntype: tool\nconfidence: high   # override recorded by the owner, though no rule fires here any more\nsources: [raw/4-webinfo/a.md, raw/4-webinfo/b.md]\n---\n\n## Definition\nAn override comment with nothing left to override.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/tools/OverrideUnused.md"
  printf -- '---\ntitle: "social-undocumented"\ntype: source\nconfidence: medium\nsources: [raw/6-social/a.md]\n---\n\n## Summary\nA social capture above its cap with nothing recorded.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/sources/social-undocumented.md"
  printf -- '---\ntitle: "social-documented"\ntype: source\nconfidence: medium   # override of the social boundary, recorded by the owner: first-party and corroborated\nsources: [raw/6-social/b.md]\n---\n\n## Summary\nThe same tier, with the judgement recorded beside it.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/sources/social-documented.md"
  printf -- '---\ntitle: "social-verylow"\ntype: source\nconfidence: very-low\nsources: [raw/6-social/c.md]\n---\n\n## Summary\nBelow the social cap, which is the tie rule working.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/sources/social-verylow.md"
  printf -- '---\ntitle: "OddTierOverride"\ntype: concept\nconfidence: pretty-sure   # override recorded by the owner\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nA value outside the five tiers, with an override comment.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/OddTierOverride.md"
  printf -- '---\ntitle: "NullTier"\ntype: concept\nconfidence:   # still to be decided\nsources: [raw/1-articles/a.md, raw/1-articles/b.md]\n---\n\n## Definition\nThe tier line carries only a comment.\n\n## Related\n- [[EdgeHub]]\n' > "$d/wiki/concepts/NullTier.md"
  printf -- '---\ntitle: "MapOverride"\ntype: map\nconfidence: high   # override recorded by the owner\n---\n\n## Map\n- [[EdgeHub]] — a map omits confidence whatever the comment says.\n' > "$d/wiki/maps/MapOverride.md"
  printf -- '%s' "$d"
}

P="$(planted)"; C="$(clean)"; E="$(edge)"

# Checksum manifests taken BEFORE the first script runs. The read-only leg at the end
# compares its own copy across six invocations; these compare the writable fixtures and the
# script home across EVERY invocation in the file. Taking them late would fold a file the
# first leg created into the baseline, and the comparison would then find nothing.
manifest(){ find "$1" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum | LC_ALL=C sort; }
START_P="$(manifest "$P")"; START_C="$(manifest "$C")"; START_E="$(manifest "$E")"
START_H="$(manifest "$HOME_DIR")"
# hashes <manifest> — how many hashed files a manifest actually holds.
hashes(){ printf '%s\n' "$1" | grep -c '^[0-9a-f]\{40\}  '; }

printf '\n--- baselines ---\n'
# Two empty strings compare equal, so a manifest that quietly produced nothing would turn
# the whole stdout-only proof into a no-op that reports "unchanged".
BH="$(hashes "$START_H")"; BP="$(hashes "$START_P$START_E")"
if [ "$BH" -ge 3 ] && [ "$BP" -ge 10 ]; then ok "the checksum manifest tool is live ($BH files in the script home, $BP in two fixtures)"
else no "the checksum manifest tool is live  [$BH in the script home, $BP in two fixtures]"; fi

printf '\n--- check-orphans.py ---\n'
OJ="$(python3 "$ORPH" --vault "$P" --format json)"
eq "a page nothing links to is an orphan" \
   '["wiki/concepts/LogLinked.md", "wiki/concepts/Orphan.md"]' \
   "$(printf '%s' "$OJ" | jget orphans)"
eq "a page linked only from log.md is still an orphan (log is not a link source)" \
   "1" "$(printf '%s' "$OJ" | jget orphans | grep -c 'LogLinked')"
eq "a page reachable only through a frontmatter alias is not an orphan" \
   "0" "$(printf '%s' "$OJ" | jget orphans | grep -c 'Aliased')"
eq "a map with no inbound link is exempt, never an orphan" \
   "0" "$(printf '%s' "$OJ" | jget orphans | grep -c 'maps/')"
eq "links inside fences, code spans and HTML comments are not links" \
   "0" "$(printf '%s' "$OJ" | jget orphans | grep -c 'NotALink')"
CJ="$(python3 "$ORPH" --vault "$C" --format json)"
CO="$(printf '%s' "$CJ" | jget orphan_count)"; CC="$(printf '%s' "$CJ" | jget inbound_control)"
if [ "$CO" = "0" ] && [ "$CC" -gt 0 ]; then ok "a clean fixture reports 0 orphans with a non-zero inbound control ($CC pages)"
else no "a clean fixture reports 0 orphans with a non-zero inbound control  [orphans $CO, control $CC]"; fi
# The root guard now intercepts this case: a directory with neither raw/ nor wiki/ is refused
# before the census reads anything. Same scenario as the pre-2026-09-07 leg (a root that is not
# a vault), asserted against the guard's contract — one line on stderr, exit 2, no stdout.
GERR="$W/guard-stderr.txt"
out="$(python3 "$ORPH" --vault "$W" 2>"$GERR")"; rc=$?
if [ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'is not a vault root' "$GERR"; then ok "no wiki directory is a broken premise, never clean"
else no "no wiki directory is a broken premise  [exit $rc: $out]"; fi

printf '\n--- check-orphans.py · edge inputs ---\n'
EO="$(python3 "$ORPH" --vault "$E" --format json)"
eorph(){ printf '%s' "$EO" | jget orphans | grep -c -- "$1"; }
eq "a CRLF page's block-form alias still resolves, so it is not an orphan" "0" "$(eorph 'CrlfAliased')"
eq "a page whose bytes open with a BOM is parsed, not orphaned" "0" "$(eorph 'BomPage')"
eq "a section link [[name#heading]] credits the page" "0" "$(eorph 'SectionLink')"
eq "an alias-piped link [[name|label]] credits the page" "0" "$(eorph 'PipeLink')"
eq "a page linking only to itself is still an orphan" "1" "$(eorph 'SelfOnly')"
eq "a page with no frontmatter at all is censused, not skipped" "1" "$(eorph 'NoFrontmatter')"
# The JSON path escapes non-ASCII, so the unicode leg reads the text path — which is also
# the one an ascii stdout would break.
eq "a unicode page name is censused and printed" "1" \
   "$(python3 "$ORPH" --vault "$E" | grep -c 'Ünïcødé')"
eq "an apostrophe in a page name is censused and printed" "1" "$(eorph 'Ada')"
eq "a media embed is not counted as a page link" "1" "$(printf '%s' "$EO" | jget embeds_skipped)"
eq "a page the catalogue alone reaches is reported as index-only, not as a finding" "1" \
   "$(printf '%s' "$EO" | jget index_only | grep -c 'CatalogueOnly')"
# The replica's own control: the shared rules must count the same links as check-links.py.
if [ ! -f "$LINKS" ]; then no "check-links.py is present to check the replica against"
else
  LOUT="$(python3 "$LINKS" "$E")"
  LN="$(printf '%s' "$LOUT" | sed -n 's/^SCANNED: .* | \([0-9]*\) page links .*/\1/p')"
  LE="$(printf '%s' "$LOUT" | sed -n 's/^SCANNED: .* | \([0-9]*\) media embeds .*/\1/p')"
  ON="$(printf '%s' "$EO" | jget links_scanned)"
  if [ -n "$LN" ] && [ "$LN" -gt 0 ] && [ "$LE" -gt 0 ]; then
    eq "the replica counts the same page links as check-links.py (control: $LN links, $LE embed)" "$LN" "$ON"
  else no "the replica's link-count agreement leg ran  [check-links reported '$LOUT']"; fi
fi
out="$(python3 "$ORPH" --vault "$E" --format json 2>"$ERR" | jget orphan_count)"
eq "the edge fixture's orphan count is the four unlinked pages" "4" "$out"
mkdir -p "$W/nolinks/wiki/concepts" "$W/nolinks/raw"
printf -- '---\ntitle: "Alone"\ntype: concept\nconfidence: medium\n---\n\n## Definition\nNo links anywhere.\n' > "$W/nolinks/wiki/concepts/Alone.md"
out="$(python3 "$ORPH" --vault "$W/nolinks" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'zero page links scanned'; then ok "a wiki with no links at all is a broken premise, never 'no orphans'"
else no "a wiki with no links at all is a broken premise  [exit $rc: $out]"; fi
mkdir -p "$W/emptywiki/wiki" "$W/emptywiki/raw"
out="$(python3 "$ORPH" --vault "$W/emptywiki" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "an empty wiki directory is a broken premise for the orphan census"
else no "an empty wiki directory is a broken premise for the orphan census  [exit $rc: $out]"; fi
out="$(python3 "$ORPH" --vault "$W/emptywiki" --format json 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "--format json still prints the plain PROBE FAILED line and exits 2"
else no "--format json still prints the plain PROBE FAILED line  [exit $rc: $out]"; fi
if [ -s "$ERR" ]; then no "a broken premise says it once, on stdout  [stderr: $(head -1 "$ERR")]"
else ok "a broken premise says it once, on stdout (stderr stayed empty)"; fi

printf '\n--- tier-cap-check.py ---\n'
TJ="$(python3 "$TIER" --vault "$P" --format json)"
vio(){ printf '%s' "$TJ" | count_in violations "$1" "$2"; }
eq "a compiled tool page badged authoritative breaks the type cap" "1" "$(vio BadTier type-cap)"
eq "a single social source above low breaks boundary 1" "1" "$(vio social-post social-low)"
eq "a single-primary-source concept at high is a note, not a violation" "0" "$(vio SinglePrimary boundary-2)"
eq "that same page is still reported as sitting on the boundary" "1" \
   "$(printf '%s' "$TJ" | count_in notes SinglePrimary boundary-2)"
eq "an inline # comment on the tier parses as the bare tier" "0" "$(vio Commented type-cap)"
eq "a value outside the five tiers is invalid" "1" "$(vio OddTier type-cap)"
eq "a map carrying a confidence value is a finding (maps omit it entirely)" "1" "$(vio MapWithTier type-cap)"
eq "the run prints its own rule-engine control" "3/3" "$(printf '%s' "$TJ" | jget cap_control)"
eq "a documented override beside it is not counted as a violation" "0" "$(vio social-override social-low)"
eq "that override is reported under its own heading instead" "1" \
   "$(printf '%s' "$TJ" | count_in overrides social-override social-low)"
TT="$(python3 "$TIER" --vault "$P")"
eq "the text run prints the overrides heading with a count" "1" \
   "$(printf '%s' "$TT" | grep -c '^overrides (documented): 1')"
eq "the override line carries the recorded reason" "1" \
   "$(printf '%s' "$TT" | grep -c 'override of the social boundary, recorded by the owner')"
VJ="$(python3 "$TIER" --vault "$P" --verdicts "$W/verdicts.json" --format json)"
eq "a verdict proposing authoritative on a tool page is caught" "1" \
   "$(printf '%s' "$VJ" | count_in violations GoodTier type-cap)"
eq "a legal verdict on the same run is not caught" "1" "$(printf '%s' "$VJ" | jget violation_count)"
KJ="$(python3 "$TIER" --vault "$C" --format json)"
KV="$(printf '%s' "$KJ" | jget violation_count)"; KC="$(printf '%s' "$KJ" | jget cap_control)"
if [ "$KV" = "0" ] && [ "$KC" = "3/3" ]; then ok "a clean fixture reports 0 violations with cap-control 3/3"
else no "a clean fixture reports 0 violations with cap-control 3/3  [violations $KV, control $KC]"; fi
eq "a zero override count carries its own control on the same run" "notes 2/2 · overrides 2/2" \
   "$(printf '%s' "$KJ" | jget extra_control)"
out="$(python3 "$TIER" --vault "$W" 2>"$GERR")"; rc=$?
if [ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'is not a vault root' "$GERR"; then ok "no wiki directory is a broken premise for the tier check too"
else no "no wiki directory is a broken premise for the tier check  [exit $rc: $out]"; fi

printf '\n--- tier-cap-check.py · edge inputs ---\n'
ET="$(python3 "$TIER" --vault "$E" --format json)"
evio(){ printf '%s' "$ET" | count_in violations "$1" "$2"; }
enote(){ printf '%s' "$ET" | count_in notes "$1" "$2"; }
eovr(){ printf '%s' "$ET" | count_in overrides "$1" "$2"; }
eq "a quoted tier value parses as the bare tier" "1" "$(evio QuotedTier type-cap)"
eq "a CRLF page's block-form quoted sources still collapse to one document" "1" "$(evio CrlfSingle boundary-2)"
eq "a documented override over the type cap is an override, not a violation" "0" "$(evio OverrideUsed type-cap)"
eq "and it is listed as one" "1" "$(eovr OverrideUsed type-cap)"
eq "an undocumented social page beside a documented one stays a violation" "1" "$(evio social-undocumented social-low)"
eq "the documented one does not" "0" "$(evio social-documented social-low)"
eq "a social source BELOW the cap is not a violation (the tie rule, obeyed)" "0" "$(evio social-verylow social-low)"
eq "an override comment that suppresses nothing is a note" "1" "$(enote OverrideUnused override-unused)"
eq "an override comment does not excuse a map carrying confidence" "1" "$(evio MapOverride type-cap)"
eq "an override comment does not excuse a tier outside the five" "1" "$(evio OddTierOverride type-cap)"
eq "a page with no frontmatter is named as such, not read as unbadged" "1" "$(enote NoFrontmatter no-frontmatter)"
eq "a frontmatter fence that never closes is named as such" "1" "$(enote Unclosed malformed-frontmatter)"
eq "a tier line carrying only a comment is a no-confidence note" "1" "$(enote NullTier no-confidence)"
eq "a BOM does not hide a page's tier" "0" "$(enote BomPage no-frontmatter)"
# Nothing silently skipped: unicode, apostrophe and malformed names all reach the record list.
EDGE_MD="$(find "$E/wiki" -type f -name '*.md' -print0 | tr -dc '\0' | wc -c | tr -d ' ')"
eq "every page in the fixture reaches the tier check, odd file names included" "$EDGE_MD" \
   "$(printf '%s' "$ET" | jget records)"
printf -- '[{"tier": "high"}]\n' > "$W/verdicts-nopage.json"
out="$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-nopage.json" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "a verdict entry with no page path is a broken premise, never a traceback"
else no "a verdict entry with no page path is a broken premise  [exit $rc: $out]"; fi
printf -- '["wiki/index.md"]\n' > "$W/verdicts-strings.json"
out="$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-strings.json" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "a verdicts array of non-objects is a broken premise, never a traceback"
else no "a verdicts array of non-objects is a broken premise  [exit $rc: $out]"; fi
printf -- '[{"page": "wiki/sources/social-documented.md", "tier": "high"}]\n' > "$W/verdicts-lift.json"
eq "an override recorded for the page's own tier does not excuse a DIFFERENT proposed tier" "1" \
   "$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-lift.json" --format json | jget violation_count)"
printf -- '[{"page": "wiki/sources/social-documented.md", "tier": "medium"}]\n' > "$W/verdicts-same.json"
eq "re-proposing the tier the page already records is still an override, not a violation" "0" \
   "$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-same.json" --format json | jget violation_count)"
printf -- '[{"page": "wiki/sources/social-undocumented.md", "tier": "medium", "comment": "override recorded with this proposal"}]\n' > "$W/verdicts-own.json"
eq "a proposal may record its own override in its own comment field" "1" \
   "$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-own.json" --format json | jget override_count)"
printf -- '[{"page": "wiki/concepts/NoFrontmatter.md", "tier": "authoritative"}]\n' > "$W/verdicts-bare.json"
# Two notes: the page has no frontmatter AND the rules still ran over the proposed tier.
eq "a verdict on a page with no frontmatter is still checked, not silently skipped" "2" \
   "$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-bare.json" --format json | count_in notes NoFrontmatter)"
printf -- '[{"page": "wiki/tools/QuotedTier.md", "tier": 3}, {"page": "wiki/tools/QuotedTier.md", "tier": "high"}]\n' > "$W/verdicts-odd.json"
VO="$(python3 "$TIER" --vault "$E" --verdicts "$W/verdicts-odd.json" --format json 2>"$ERR")"; rc=$?
if [ "$rc" = 0 ] && [ "$(printf '%s' "$VO" | jget violation_count)" = "1" ]; then ok "a non-string proposed tier is reported as invalid, not crashed on"
else no "a non-string proposed tier is reported as invalid  [exit $rc]"; fi
out="$(python3 "$TIER" --vault "$W/emptywiki" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "an empty wiki directory is a broken premise for the tier check"
else no "an empty wiki directory is a broken premise for the tier check  [exit $rc: $out]"; fi

printf '\n--- anomaly-lister.py ---\n'
AJ="$(python3 "$ANOM" --vault "$P" --format json)"
kind(){ printf '%s' "$AJ" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(sum(1 for p, ks in d["findings"].items() if sys.argv[1] in p and sys.argv[2] in ks))
' "$1" "$2"; }
eq "an unsettled Conflicts block is listed as open" "1" "$(kind OpenConflict open-conflict)"
eq "a Conflicts block carrying a settled marker is not listed" "0" "$(kind SettledConflict open-conflict)"
eq "a flagged: frontmatter line is listed" "1" "$(kind Flagged flagged)"
eq "the flagged text travels with the finding" "1" \
   "$(printf '%s' "$AJ" | grep -c 'the mechanism may have changed since capture')"
eq "a thin-page note is listed" "1" "$(kind Thin thin-page)"
eq "an inline unverified marker is counted" "1" "$(kind Thin unverified)"
eq "a custom --settled-markers value suppresses the open block" "0" \
   "$(python3 "$ANOM" --vault "$P" --settled-markers 'nothing decides' --format json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for p,k in d["findings"].items() if "OpenConflict" in p and "open-conflict" in k))')"
eq "--pages mode checks exactly the named page" "1" \
   "$(python3 "$ANOM" --vault "$P" --pages "$P/wiki/concepts/OpenConflict.md" --format json | jget pages_with_findings)"
NJ="$(python3 "$ANOM" --vault "$C" --format json)"
NF="$(printf '%s' "$NJ" | jget pages_with_findings)"; NC="$(printf '%s' "$NJ" | jget anomaly_control)"
if [ "$NF" = "0" ] && [ "$NC" = "4/4" ]; then ok "a clean fixture lists no anomalies with anomaly-control 4/4"
else no "a clean fixture lists no anomalies with anomaly-control 4/4  [pages $NF, control $NC]"; fi
out="$(python3 "$ANOM" --vault "$P" --thin-regex '*bad(' 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "an unusable regex is a broken premise, never clean"
else no "an unusable regex is a broken premise  [exit $rc: $out]"; fi

printf '\n--- anomaly-lister.py · edge inputs ---\n'
EA="$(python3 "$ANOM" --vault "$E" --format json)"
ekind(){ printf '%s' "$EA" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(sum(len(ks.get(sys.argv[2], [])) for p, ks in d["findings"].items() if sys.argv[1] in p))
' "$1" "$2"; }
eq "a conflict block ending the file with no trailing newline is caught" "1" "$(ekind TailConflict open-conflict)"
eq "an empty conflict block is counted as empty, not open" "0" "$(ekind EmptyConflict open-conflict)"
eq "and the empty block is counted" "1" "$(printf '%s' "$EA" | jget empty_conflict_blocks)"
eq "a zero empty-block total would carry its own control" "1" "$(printf '%s' "$EA" | jget empty_conflict_control)"
eq "a CRLF page's flagged: line is still found" "1" "$(ekind CrlfAliased flagged)"
eq "a page with no frontmatter still has its prose scanned" "1" "$(ekind NoFrontmatter unverified)"
eq "every page in the fixture reaches the anomaly census too" "$EDGE_MD" \
   "$(printf '%s' "$EA" | jget pages)"
eq "a BOM does not hide a flagged: line" "1" "$(ekind BomPage flagged)"
eq "the default form counts the marker in a span and the word in prose" "2" "$(ekind SpanMarker unverified)"
EB="$(python3 "$ANOM" --vault "$E" --unverified-form backtick --format json)"
eq "--unverified-form backtick counts only the marker form" "1" \
   "$(printf '%s' "$EB" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(sum(len(ks.get("unverified", [])) for p, ks in d["findings"].items() if "SpanMarker" in p))')"
eq "the active form is reported so a comparison knows what it compares" "backtick" \
   "$(printf '%s' "$EB" | jget unverified_form)"
eq "the text header names the form too" "1" \
   "$(python3 "$ANOM" --vault "$E" --unverified-form backtick | grep -c 'unverified-form=backtick')"
eq "the control still passes under the backtick form" "4/4" "$(printf '%s' "$EB" | jget anomaly_control)"
eq "an unterminated frontmatter is reported, so its flagged count reads as a floor" "1" \
   "$(printf '%s' "$EA" | jget malformed_frontmatter | grep -c 'Unclosed')"
eq "the text run warns about it" "1" \
   "$(python3 "$ANOM" --vault "$E" | grep -c '^frontmatter warning:')"
eq "a unicode page name is listed among the findings" "1" \
   "$(printf '%s' "$EA" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(sum(1 for p in d["findings"] if "single witness" in json.dumps(d["findings"][p])))')"
out="$(python3 "$ANOM" --vault "$P" --settled-markers '*bad(' 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "an unusable --settled-markers regex is a broken premise too"
else no "an unusable --settled-markers regex is a broken premise  [exit $rc: $out]"; fi
out="$(python3 "$ANOM" --vault "$E" --thin-regex 'zzz-matches-nothing' 2>"$ERR")"
if printf '%s' "$out" | grep -q '^marker-override warning:'; then ok "an override that zeroes a kind warns that the count is a floor"
else no "an override that zeroes a kind warns that the count is a floor  [$out]"; fi
out="$(python3 "$ANOM" --vault "$W/emptywiki" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "an empty wiki directory is a broken premise for the anomaly census"
else no "an empty wiki directory is a broken premise for the anomaly census  [exit $rc: $out]"; fi

printf '\n--- shared premises ---\n'
mkdir -p "$W/broken/wiki/concepts" "$W/broken/raw"
printf -- '---\ntitle: "Live"\ntype: concept\nconfidence: medium\n---\n\n## Related\n- [[Dangling]]\n' > "$W/broken/wiki/concepts/Live.md"
ln -s "$W/broken/wiki/concepts/no-such-target" "$W/broken/wiki/concepts/Dangling.md"
for pair in "orphans:$ORPH" "tier:$TIER" "anomaly:$ANOM"; do
  nm="${pair%%:*}"; scr="${pair#*:}"
  out="$(python3 "$scr" --vault "$W/broken" 2>"$ERR")"; rc=$?
  if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED'; then ok "$nm: an unreadable page is a broken premise, never a clean scan"
  else no "$nm: an unreadable page is a broken premise  [exit $rc: $out]"; fi
done
r1=0; r2=0; r3=0
env PYTHONIOENCODING=ascii python3 "$ORPH" --vault "$E" > "$W/ascii-orph.txt" 2>"$ERR" || r1=$?
env PYTHONIOENCODING=ascii python3 "$TIER" --vault "$E" > "$W/ascii-tier.txt" 2>"$ERR" || r2=$?
env PYTHONIOENCODING=ascii python3 "$ANOM" --vault "$E" > "$W/ascii-anom.txt" 2>"$ERR" || r3=$?
if [ "$r1$r2$r3" = "000" ] && grep -q 'Ada' "$W/ascii-orph.txt"; then ok "an ascii stdout does not turn a unicode page name into a traceback"
else no "an ascii stdout does not turn a unicode page name into a traceback  [exits $r1 $r2 $r3]"; fi

printf '\n--- root guard: a root that is not a vault (register entry 2026-09-06) ---\n'
# The entry: check-links.py printed "SCANNED: 0 pages … DEAD LINKS: 0" and exited 0 on a root
# holding no vault, so a caller reading the exit code got a clean bill of health from a probe
# that opened no file. Every script here now applies the 2026-08-26 standard (raw/ + wiki/ or
# refuse). Each leg asserts all three parts: exit 2, the message on stderr, nothing on stdout.
NOVAULT="$W/notavault"; rm -rf "$NOVAULT"; mkdir -p "$NOVAULT/docs"
printf 'a directory that is not a vault\n' > "$NOVAULT/docs/readme.md"
guard(){ local nm="$1"; shift; local gout grc
  gout="$("$@" 2>"$GERR")"; grc=$?
  if [ "$grc" = 2 ] && [ -z "$gout" ] && grep -q 'is not a vault root (no raw/ or wiki/)' "$GERR"
  then ok "$nm refuses a root that is not a vault (exit 2, one line on stderr, no stdout)"
  else no "$nm refuses a root that is not a vault  [exit $grc, stdout '$gout', stderr '$(head -1 "$GERR")']"; fi; }
guard "check-links.py"         python3 "$LINKS" --vault "$NOVAULT"
guard "check-orphans.py"       python3 "$ORPH"  --vault "$NOVAULT"
guard "tier-cap-check.py"      python3 "$TIER"  --vault "$NOVAULT"
guard "anomaly-lister.py"      python3 "$ANOM"  --vault "$NOVAULT"
guard "check-index.py"         python3 "$INDEX" --vault "$NOVAULT"
guard "check-shipped-links.py" python3 "$SHIP"  "$NOVAULT"
guard "apply-palette.py"       python3 "$PAL"   --apply --vault "$NOVAULT"
guard "check-qmd-registry.sh"  sh "$QMD" "$NOVAULT"
guard "check-qmd-registry.sh (--vault form)" sh "$QMD" --vault "$NOVAULT"
guard "check_flag_admissions.py" python3 "$FLAGS" --vault "$NOVAULT"
# The positive control for the eight refusals above: the same scripts, on a real fixture vault,
# on this same run. A guard that refused everything would pass the legs above and fail here.
scans(){ local nm="$1" want="$2"; shift 2; local sout src
  sout="$("$@" 2>"$GERR")"; src=$?
  if [ "$src" = "$want" ] && [ -n "$sout" ]
  then ok "control: $nm still scans a fixture vault on the same run (exit $src)"
  else no "control: $nm still scans a fixture vault  [exit $src, want $want; $(head -1 "$GERR")]"; fi; }
scans "check-links.py"   0 python3 "$LINKS" --vault "$C"
scans "check-orphans.py" 0 python3 "$ORPH"  --vault "$C"
scans "check-index.py"   0 python3 "$INDEX" --vault "$C"
scans "check_flag_admissions.py" 0 python3 "$FLAGS" --vault "$P"
# apply-palette.py reads its palette from the root it is given, so its control needs a fixture
# vault carrying one: --check then reports the missing groups and exits 1, which is the script
# running, not refusing. Built apart from the three shared fixtures, whose manifests are frozen.
PALV="$W/palette-vault"; rm -rf "$PALV"; mkdir -p "$PALV/raw" "$PALV/wiki" "$PALV/.claude/skills/lint"
cp "$HOME_DIR/palette.json" "$PALV/.claude/skills/lint/palette.json"
scans "apply-palette.py" 1 python3 "$PAL"   --check --vault "$PALV"
badflag(){ local nm="$1"; shift; local brc
  "$@" > /dev/null 2>"$GERR"; brc=$?
  if [ "$brc" = 2 ]; then ok "$nm refuses an unknown flag instead of reading it as a root"
  else no "$nm refuses an unknown flag  [exit $brc]"; fi; }
badflag "check-links.py"         python3 "$LINKS" --vault "$C" --deep
badflag "check-orphans.py"       python3 "$ORPH"  --vault "$C" --deep
badflag "check-index.py"         python3 "$INDEX" --vault "$C" --deep
badflag "apply-palette.py"       python3 "$PAL"   --check --vault "$C" --deep
badflag "check-shipped-links.py" python3 "$SHIP"  "$C" --deep
badflag "check-qmd-registry.sh"  sh "$QMD" "$C" wiki --deep
badflag "check_flag_admissions.py" python3 "$FLAGS" --vault "$C" --deep
LV="$(python3 "$LINKS" --vault "$C" 2>"$GERR")"; rc=$?
LP="$(python3 "$LINKS" "$C" 2>>"$GERR")"
if [ "$rc" = 0 ] && [ -n "$LV" ] && [ "$LV" = "$LP" ]
then ok "check-links.py reads --vault, the sibling spelling, exactly as the positional form"
else no "check-links.py reads --vault as the positional form  [exit $rc]"; fi
rm -rf "$W/palette-target"; mkdir -p "$W/palette-target/docs"
out="$(python3 "$PAL" --apply "$W/palette-target" 2>"$GERR")"; rc=$?
if [ "$rc" = 2 ] && [ ! -e "$W/palette-target/.obsidian" ]
then ok "apply-palette.py refuses a non-vault root BEFORE it writes anything"
else no "apply-palette.py refuses a non-vault root before writing  [exit $rc]"; fi

printf '\n--- check-links.py · sources: arm (register entry 2026-09-03) ---\n'
# The entry: 1,044 `sources:` paths across the vault and no probe resolved one of them; three
# were dead. The arm resolves every entry classified as a vault path and leaves URLs, prose
# provenance and entries that declare their own deletion alone — each counted, so a zero is
# auditable rather than a silence.
SFIX="$W/sourcefix"; rm -rf "$SFIX"; rawbase "$SFIX"; mkdir -p "$SFIX/wiki/concepts" "$SFIX/assets"
printf -- '# Framework Doc\nA root document a page may cite as its source.\n' > "$SFIX/CLAUDE.md"
printf -- 'a raw capture whose file name carries commas\n' > "$SFIX/raw/1-articles/one, two, three.md"
printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n## Concepts\n- [[GoodSource]] — the clean case.\n' > "$SFIX/wiki/index.md"
printf -- '---\ntitle: "GoodSource"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md, "raw/2-papers/paper.md"]\n---\n\n## Definition\nEvery source resolves.\n' > "$SFIX/wiki/concepts/GoodSource.md"
printf -- '---\ntitle: "MissingSource"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/gone.md]\n---\n\n## Definition\nOne source path names no file.\n' > "$SFIX/wiki/concepts/MissingSource.md"
printf -- '---\ntitle: "UrlSource"\ntype: concept\nconfidence: medium\nsources: ["https://example.org/paper", raw/1-articles/b.md]\n---\n\n## Definition\nA URL is provenance, not a path on disk.\n' > "$SFIX/wiki/concepts/UrlSource.md"
printf -- '---\ntitle: "ProseSource"\ntype: concept\nconfidence: medium\nsources: ["email: someone@example.org (a person, and a comma)", usage, 20 Aug 2026]\n---\n\n## Definition\nProse provenance is legitimate and must not be flagged.\n' > "$SFIX/wiki/concepts/ProseSource.md"
printf -- '---\ntitle: "AnnotatedSource"\ntype: concept\nconfidence: medium\nsources: ["assets/gone.md (deleted 2026-01-01)"]\n---\n\n## Definition\nThe entry declares its own absence.\n' > "$SFIX/wiki/concepts/AnnotatedSource.md"
printf -- '---\ntitle: "RootDoc"\ntype: concept\nconfidence: medium\nsources: [CLAUDE.md]\n---\n\n## Definition\nA root document, named without a folder.\n' > "$SFIX/wiki/concepts/RootDoc.md"
printf -- '---\ntitle: "CommaPath"\ntype: concept\nconfidence: medium\nsources: ["raw/1-articles/one, two, three.md"]\n---\n\n## Definition\nOne quoted path carrying commas.\n' > "$SFIX/wiki/concepts/CommaPath.md"
printf -- '---\ntitle: "BlockSource"\ntype: concept\nconfidence: medium\nsources:\n  - raw/4-webinfo/a.md\n  - "raw/4-webinfo/gone.md"\n---\n\n## Definition\nBlock-form list, one entry missing.\n' > "$SFIX/wiki/concepts/BlockSource.md"
printf -- '---\ntitle: "EmptyList"\ntype: concept\nconfidence: medium\nsources: []\n---\n\n## Definition\nThe key is present and carries nothing.\n' > "$SFIX/wiki/concepts/EmptyList.md"
SRCOUT="$(python3 "$LINKS" --vault "$SFIX" 2>"$ERR")"; rc=$?
srcline(){ printf '%s\n' "$SRCOUT" | grep -c -- "$1"; }
srcnum(){ printf '%s\n' "$SRCOUT" | sed -n "s/^SOURCES SCANNED: .*| \([0-9]*\) $1.*/\1/p"; }
eq "a sources: path that names no file on disk is a dangling source" "1" \
   "$(srcline 'DANGLING SOURCES: 2')"
eq "the dangling entry names the page and the path" "1" \
   "$(srcline '  wiki/concepts/MissingSource.md · raw/1-articles/gone.md')"
eq "a block-form sources: list is read too" "1" \
   "$(srcline '  wiki/concepts/BlockSource.md · raw/4-webinfo/gone.md')"
eq "a URL entry is counted, never resolved against disk" "1" "$(srcnum 'URLs')"
eq "prose provenance is skipped and counted, never flagged" "3" "$(srcnum 'prose')"
eq "no prose entry reaches the dangling list" "0" "$(srcline 'ProseSource')"
eq "an entry that declares its own deletion is reported apart, not as a finding" "1" \
   "$(srcline '(annotated absence) wiki/concepts/AnnotatedSource.md')"
eq "a root document named without a folder resolves" "0" "$(srcline 'RootDoc')"
eq "a quoted path carrying commas is one entry, not three fragments" "0" "$(srcline 'CommaPath')"
eq "an empty sources: list is counted as such, never as a missing path" "1" \
   "$(srcline '(empty or unparsed sources) wiki/concepts/EmptyList.md')"
if [ "$rc" = 1 ]; then ok "a dangling source alone sets the findings exit code (1), as a dead link does"
else no "a dangling source sets the findings exit code  [exit $rc]"; fi
CSRC="$(python3 "$LINKS" --vault "$C" 2>"$ERR")"; rc=$?
CD="$(printf '%s\n' "$CSRC" | grep -c 'DANGLING SOURCES: 0')"
CP="$(printf '%s\n' "$CSRC" | sed -n 's/^SOURCES SCANNED: .*| \([0-9]*\) vault paths resolved.*/\1/p')"
if [ "$CD" = "1" ] && [ "$CP" -gt 0 ] && [ "$rc" = 0 ]
then ok "a clean fixture reports 0 dangling sources with $CP paths resolved as its control"
else no "a clean fixture reports 0 dangling sources with a non-zero path count  [$CD, paths $CP, exit $rc]"; fi

printf '\n--- check-links.py · out-of-vault sources (register entry 2026-09-08) ---\n'
# The entry: a sources: entry under ~ was reported dangling although the file existed — two
# false positives per run, growing with every hands-off run report. A ~- or /-led entry is
# provenance outside the vault: resolved with expanduser under a HOME the leg redirects into
# the fixture, reported present or missing in its own bucket, never dangling.
OFIX="$W/outside"; rm -rf "$OFIX"; rawbase "$OFIX"; mkdir -p "$OFIX/wiki/concepts" "$W/home/store/run-1" "$W/abs"
printf -- 'a run report kept outside the vault\n' > "$W/home/store/run-1/report.md"
printf -- 'an absolute-path provenance file\n' > "$W/abs/note.md"
printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n## Concepts\n- [[TildePresent]] — a page.\n' > "$OFIX/wiki/index.md"
printf -- '---\ntitle: "TildePresent"\ntype: concept\nconfidence: medium\nsources: ["~/store/run-1/report.md", raw/1-articles/a.md]\n---\n\n## Definition\nA tilde-led entry whose file exists under HOME.\n' > "$OFIX/wiki/concepts/TildePresent.md"
printf -- '---\ntitle: "TildeMissing"\ntype: concept\nconfidence: medium\nsources: ["~/store/run-9/report.md"]\n---\n\n## Definition\nA tilde-led entry whose file does not exist.\n' > "$OFIX/wiki/concepts/TildeMissing.md"
printf -- '---\ntitle: "AbsolutePresent"\ntype: concept\nconfidence: medium\nsources:\n  - "%s/abs/note.md"\n---\n\n## Definition\nAn absolute path outside the vault, block form.\n' "$W" > "$OFIX/wiki/concepts/AbsolutePresent.md"
OOUT="$(env HOME="$W/home" python3 "$LINKS" --vault "$OFIX" 2>"$ERR")"; rc=$?
oline(){ printf '%s\n' "$OOUT" | grep -c -- "$1"; }
eq "a ~-led entry whose file exists is present, never dangling (the 2026-09-08 false positive)" "1" "$(oline 'DANGLING SOURCES: 0')"
eq "present and missing out-of-vault entries are counted in their own bucket" "1" "$(oline '^OUT-OF-VAULT SOURCES: 2 present | 1 missing')"
eq "the missing one names the page and the path under its own label" "1" "$(oline '^  (out-of-vault missing) wiki/concepts/TildeMissing.md · ~/store/run-9/report.md')"
eq "no out-of-vault entry is counted as a vault path" "1" "$(printf '%s\n' "$OOUT" | sed -n 's/^SOURCES SCANNED: .*| \([0-9]*\) vault paths resolved.*/\1/p')"
eq "the scan line carries the out-of-vault total" "1" "$(oline '| 3 out-of-vault ')"
if [ "$rc" = 1 ]; then ok "a genuinely missing out-of-vault source is a finding (exit 1)"
else no "a genuinely missing out-of-vault source is a finding  [exit $rc]"; fi
rm "$OFIX/wiki/concepts/TildeMissing.md"
OOUT="$(env HOME="$W/home" python3 "$LINKS" --vault "$OFIX" 2>"$ERR")"; rc=$?
eq "control: with the missing entry gone the same fixture is clean (exit 0, 2 present)" "0-1" "$rc-$(oline '^OUT-OF-VAULT SOURCES: 2 present | 0 missing')"
OOUT="$(env HOME="$W/no-such-home" python3 "$LINKS" --vault "$OFIX" 2>"$ERR")"; rc=$?
eq "negative control: under another HOME the ~ entry is missing, still never dangling" "1-1-1" "$rc-$(oline '^OUT-OF-VAULT SOURCES: 1 present | 1 missing')-$(oline 'DANGLING SOURCES: 0')"

printf '\n--- check_flag_admissions.py (register entry 2026-09-08, ingest Step 0 conversions) ---\n'
# The entry: 14 source pages recorded a damaged conversion in prose or a frontmatter comment
# and only 5 raised a flagged: line, so deep-lint's flag channel never saw the other 9. The
# probe keys on the damage vocabulary, never on a named file, and only under wiki/sources/.
AFIX="$W/admissions"; rm -rf "$AFIX"; rawbase "$AFIX"; mkdir -p "$AFIX/wiki/sources" "$AFIX/wiki/concepts"
printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n## Sources\n- [[admits]] — a page.\n' > "$AFIX/wiki/index.md"
printf -- '---\ntitle: "admits"\ntype: source\nconfidence: medium\nsources: [raw/2-papers/paper.md]\n---\n\n## Summary\nThe markitdown conversion collapsed inter-word spaces in the running prose, so quotations are paraphrased.\n' > "$AFIX/wiki/sources/admits.md"
printf -- '---\ntitle: "admits-in-comment"\ntype: source\nconfidence: medium\ndepth: standard # run-together conversion, verbatim quoting impossible\nsources: [raw/2-papers/paper.md]\n---\n\n## Summary\nThe body says nothing about the conversion.\n' > "$AFIX/wiki/sources/admits-in-comment.md"
printf -- '---\ntitle: "admits-unavailable"\ntype: source\nconfidence: medium\nsources: [raw/2-papers/paper.md]\n---\n\n## Summary\nA verbatim quotation is unavailable for this source.\n' > "$AFIX/wiki/sources/admits-unavailable.md"
printf -- '---\ntitle: "flagged-admits"\ntype: source\nconfidence: medium\nflagged: 2026-09-08 source conversion suspect — raw/2-papers/paper.md · run-together 12.3 %%\nsources: [raw/2-papers/paper.md]\n---\n\n## Summary\nThe conversion collapsed inter-word spaces; the flag above carries it.\n' > "$AFIX/wiki/sources/flagged-admits.md"
printf -- '---\ntitle: "clean-source"\ntype: source\nconfidence: medium\nsources: [raw/2-papers/only.md]\n---\n\n## Summary\nNothing about the conversion is admitted here.\n' > "$AFIX/wiki/sources/clean-source.md"
printf -- '---\ntitle: "OutsideScope"\ntype: concept\nconfidence: medium\nsources: [raw/1-articles/a.md]\n---\n\n## Definition\nA concept page whose prose says the columns collapsed — not a source page, not scanned.\n' > "$AFIX/wiki/concepts/OutsideScope.md"
# the fold of 2026-09-08 (critic L10, M5): a flag about something else no longer masks an admission;
# the new vocabulary catches a lost chart; a Provenance sentence naming a repaired conversion is the
# terminal state, counted as resolved and never a finding
printf -- '---\ntitle: "other-flag"\ntype: source\nconfidence: medium\nflagged: 2026-09-01 stale pricing table, re-read\nsources: [raw/2-papers/paper.md]\n---\n\n## Summary\nThe two-column layout collapsed in conversion, so the table is paraphrased.\n' > "$AFIX/wiki/sources/other-flag.md"
printf -- '---\ntitle: "charts"\ntype: source\nconfidence: medium\nsources: [raw/1-articles/a.md]\n---\n\n## Summary\nThe capture lost every chart on the page; the numbers below come from the prose.\n' > "$AFIX/wiki/sources/charts.md"
printf -- '---\ntitle: "resolved"\ntype: source\nconfidence: medium\nsources: [raw/2-papers/paper.md, raw/2-papers/only.md]\n---\n\n## Summary\nA page whose conversion was repaired.\nProvenance (2026-09-08): compiled from a damaged conversion (run-together prose); repaired conversion `raw/2-papers/only.md` (clean); quotation check: 3 confirmed, 1 corrected, 0 unverifiable.\n' > "$AFIX/wiki/sources/resolved.md"
FOUT="$(python3 "$FLAGS" --vault "$AFIX" 2>"$ERR")"; rc=$?
fline(){ printf '%s\n' "$FOUT" | grep -c -- "$1"; }
eq "a source page admitting damage in prose with no flagged: key is a finding (exit 1)" "1" "$rc"
eq "  the prose admission is listed with its line and term" "1" "$(fline '^  wiki/sources/admits.md:9 · collapsed · The markitdown conversion collapsed inter-word spaces')"
eq "  an admission inside a frontmatter comment is caught too" "1" "$(fline '^  wiki/sources/admits-in-comment.md:5 · run-together · depth: standard # run-together conversion')"
eq "  the unavailable-quotation phrase is caught" "1" "$(fline '^  wiki/sources/admits-unavailable.md:9 · verbatim quotation is unavailable ·')"
eq "  the same admission on a page carrying a conversion flagged: is not a finding (the negative)" "0" "$(fline 'flagged-admits')"
eq "  a flagged: line about something else does NOT mask the admission (keyed on the flag's own text)" "1" "$(fline '^  wiki/sources/other-flag.md:10 · collapsed · The two-column layout collapsed in conversion')"
eq "  the vocabulary catches a lost chart" "1" "$(fline '^  wiki/sources/charts.md:9 · lost every chart · ')"
eq "  a Provenance sentence naming a repaired conversion is resolved, listed under its own line, not a finding" "1-1-0" "$(fline '^RESOLVED: 1 line(s) on 1 page(s) — an admission that also names a repaired conversion')-$(fline '^  wiki/sources/resolved.md:10 · run-together · Provenance (2026-09-08): compiled from a damaged conversion')-$(printf '%s\n' "$FOUT" | sed -n '/^ADMISSIONS WITHOUT FLAG/,$p' | grep -c 'resolved.md')"
eq "  a concept page is outside the scan (wiki/sources/ only)" "0" "$(fline 'OutsideScope')"
eq "  the count line: 8 pages scanned, 2 flagged (1 conversion), 7 matching the vocabulary" "1" "$(fline '^SCANNED: 8 pages under wiki/sources/ | 2 carry flagged: (1 conversion) | 7 match the damage vocabulary')"
eq "  the findings total" "1" "$(fline '^ADMISSIONS WITHOUT FLAG: 5$')"
eq "  the in-memory controls print: caught, conversion flag not a finding, other flag caught, repaired conversion resolved" "1" "$(fline '^CONTROL: in-memory page admitting damage without flagged: -> caught (2 term(s): collapsed, run-together); with a conversion flagged: -> not a finding; with a non-conversion flagged: -> caught; its admission rewritten as a Provenance sentence naming a repaired conversion -> resolved')"
rm "$AFIX/wiki/sources/admits.md" "$AFIX/wiki/sources/admits-in-comment.md" "$AFIX/wiki/sources/admits-unavailable.md" "$AFIX/wiki/sources/other-flag.md" "$AFIX/wiki/sources/charts.md"
FOUT="$(python3 "$FLAGS" --vault "$AFIX" 2>"$ERR")"; rc=$?
eq "control: the flagged, clean and resolved pages alone report zero findings, exit 0, control still caught" "0-1-1" "$rc-$(fline '^ADMISSIONS WITHOUT FLAG: 0$')-$(fline '^CONTROL: .*-> caught')"
eq "  with the scan total as its control, the resolved page still counted" "1-1" "$(fline '^SCANNED: 3 pages under wiki/sources/ | 1 carry flagged: (1 conversion) | 2 match the damage vocabulary')-$(fline '^RESOLVED: 1 line(s) on 1 page(s)')"
rm -rf "$AFIX/wiki/sources"
FOUT="$(python3 "$FLAGS" --vault "$AFIX" 2>"$ERR")"; rc=$?
eq "no wiki/sources/ is a premise failure (exit 2, PROBE FAILED on stderr, no stdout)" "2--1" "$rc-$FOUT-$(grep -c 'PROBE FAILED: .*wiki/sources does not exist' "$ERR")"

printf '\n--- check-index.py (register entry 2026-09-02) ---\n'
# The entry: every other lint check is a script and Step 1 was still a Read plus a glob plus a
# hand comparison. The rules are deep-lint audit-pools.py's, so the two cannot drift.
IXP="$W/index-planted"; rm -rf "$IXP"; rawbase "$IXP"; mkdir -p "$IXP/wiki/concepts"
{ printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n\n'
  printf -- '> Format: `- [[Page Name]] — one-line description.`\n\n## Concepts\n'
  printf -- '- [[Registered]] — a page on disk.\n'
  printf -- '- [[Registered]] — the same target, a second time.\n'
  printf -- '- [[NoSuchPage]] — nothing on disk answers to this.\n'
  printf -- '- [[AliasName]] — registered under the page own alias.\n'
  printf -- '<!-- - [[CommentedOut]] — a commented entry is not an entry. -->\n'
} > "$IXP/wiki/index.md"
printf -- '---\ntitle: "Log"\ntype: log\nconfidence: high\n---\n## [2026-01-01] ingest | fixture\n- **Changed**: nothing\n' > "$IXP/wiki/log.md"
printf -- '---\ntitle: "Registered"\ntype: concept\nconfidence: medium\n---\n\n## Definition\nRegistered once, listed twice.\n' > "$IXP/wiki/concepts/Registered.md"
printf -- '---\ntitle: "Aliased"\ntype: concept\nconfidence: medium\naliases: [AliasName]\n---\n\n## Definition\nRegistered under an alias.\n' > "$IXP/wiki/concepts/Aliased.md"
printf -- '---\ntitle: "Unindexed"\ntype: concept\nconfidence: medium\n---\n\n## Definition\nOn disk, in no index entry.\n' > "$IXP/wiki/concepts/Unindexed.md"
IXOUT="$(python3 "$INDEX" --vault "$IXP" 2>"$ERR")"; rc=$?
ixline(){ printf '%s\n' "$IXOUT" | grep -c -- "$1"; }
eq "a page no index entry registers is reported as unindexed" "1" "$(ixline 'UNINDEXED PAGES: 1')"
eq "the unindexed page is named by its vault path" "1" "$(ixline '  wiki/concepts/Unindexed.md')"
eq "an index entry naming no page on disk is dangling" "1" "$(ixline 'DANGLING INDEX ENTRIES: 1')"
eq "the dangling entry is named" "1" "$(ixline '  nosuchpage')"
eq "the same target registered twice is a duplicate, with its count" "1" \
   "$(ixline '  registered · 2 entries')"
eq "a page registered under its frontmatter alias is not unindexed" "0" "$(ixline 'Aliased.md')"
eq "an entry inside an HTML comment is not an entry" "0" "$(ixline 'commentedout')"
eq "the format example in the index header is not read as an entry" "0" "$(ixline 'page name')"
eq "index.md and log.md are not counted as pages against themselves" "1" \
   "$(ixline 'SCANNED: 3 pages · 4 index entries')"
if [ "$rc" = 0 ]; then ok "a census with findings still exits 0 (the sibling census convention)"
else no "a census with findings exits 0  [exit $rc]"; fi
IXC="$W/index-clean"; rm -rf "$IXC"; rawbase "$IXC"; mkdir -p "$IXC/wiki/concepts"
{ printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n\n## Concepts\n'
  printf -- '- [[Registered]] — a page on disk.\n- [[AliasName]] — the alias of the other page.\n'
} > "$IXC/wiki/index.md"
printf -- '---\ntitle: "Log"\ntype: log\nconfidence: high\n---\n## [2026-01-01] ingest | fixture\n- **Changed**: nothing\n' > "$IXC/wiki/log.md"
printf -- '---\ntitle: "Registered"\ntype: concept\nconfidence: medium\n---\n\n## Definition\nRegistered.\n' > "$IXC/wiki/concepts/Registered.md"
printf -- '---\ntitle: "Aliased"\ntype: concept\nconfidence: medium\naliases: [AliasName]\n---\n\n## Definition\nRegistered under an alias.\n' > "$IXC/wiki/concepts/Aliased.md"
IXCOUT="$(python3 "$INDEX" --vault "$IXC" 2>"$ERR")"; rc=$?
IXZ="$(printf '%s\n' "$IXCOUT" | grep -c -E '^(UNINDEXED PAGES|DANGLING INDEX ENTRIES|DUPLICATE INDEX ENTRIES): 0$')"
IXS="$(printf '%s\n' "$IXCOUT" | sed -n 's/^SCANNED: \([0-9]*\) pages · \([0-9]*\) index entries.*/\1 \2/p')"
if [ "$IXZ" = "3" ] && [ "$IXS" = "2 2" ] && [ "$rc" = 0 ]
then ok "a clean index reports three zeros with SCANNED $IXS as its control"
else no "a clean index reports three zeros with a non-zero control  [zeros $IXZ, scanned '$IXS', exit $rc]"; fi
rm -f "$IXC/wiki/index.md"
out="$(python3 "$INDEX" --vault "$IXC" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'PROBE FAILED: no wiki/index.md'
then ok "a missing wiki/index.md is a broken premise, never an empty comparison"
else no "a missing wiki/index.md is a broken premise  [exit $rc: $out]"; fi
printf -- '---\ntitle: "Index"\ntype: index\nconfidence: high\n---\n\nNo entries at all.\n' > "$IXC/wiki/index.md"
out="$(python3 "$INDEX" --vault "$IXC" 2>"$ERR")"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'registers no page'
then ok "an index that registers nothing is a broken probe, not a vault of unindexed pages"
else no "an index that registers nothing is a broken probe  [exit $rc: $out]"; fi

printf '\n--- stdout-only proof (must run last) ---\n'
RO="$W/readonly"; rm -rf "$RO"; cp -R "$P" "$RO"
RE_="$W/readonly-edge"; rm -rf "$RE_"; cp -R "$E" "$RE_"
cp "$W/verdicts.json" "$W/verdicts-ro.json"
python3 - "$W/verdicts-ro.json" <<'PYFIX'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
json.dump(d, open(p, "w"))
PYFIX
BEFORE_F="$(manifest "$RO")$(manifest "$RE_")"
chmod -R a-w "$RO" "$RE_"
python3 "$ORPH" --vault "$RO" > /dev/null; r1=$?
python3 "$ORPH" --vault "$RO" --format json > /dev/null; r2=$?
python3 "$TIER" --vault "$RO" > /dev/null; r3=$?
python3 "$TIER" --vault "$RO" --verdicts "$W/verdicts-ro.json" --format json > /dev/null; r4=$?
python3 "$ANOM" --vault "$RO" > /dev/null; r5=$?
python3 "$ANOM" --vault "$RO" --format json > /dev/null; r6=$?
python3 "$ORPH" --vault "$RE_" --format json > /dev/null; r7=$?
python3 "$TIER" --vault "$RE_" > /dev/null; r8=$?
python3 "$ANOM" --vault "$RE_" --unverified-form backtick > /dev/null; r9=$?
python3 "$ANOM" --vault "$RE_" --pages "$RE_/wiki/concepts/TailConflict.md" > /dev/null; r10=$?
python3 "$INDEX" --vault "$RO" > /dev/null; r11=$?
python3 "$INDEX" --vault "$RE_" > /dev/null; r12=$?
# check-links.py reports findings with exit 1, so its own leg reads "the probe ran" as 0 or 1.
python3 "$LINKS" --vault "$RO" > /dev/null; rl1=$?
python3 "$LINKS" --vault "$RE_" > /dev/null; rl2=$?
python3 "$FLAGS" --vault "$RO" > /dev/null; r13=$?
python3 "$FLAGS" --vault "$RE_" > /dev/null; r14=$?
chmod -R u+w "$RO" "$RE_"
AFTER_F="$(manifest "$RO")$(manifest "$RE_")"
END_H="$(manifest "$HOME_DIR")"; END_FIX="$(manifest "$P")$(manifest "$C")$(manifest "$E")"
if [ "$r1$r2$r3$r4$r5$r6$r7$r8$r9$r10$r11$r12$r13$r14" = "00000000000000" ] && [ "$rl1" -le 1 ] && [ "$rl2" -le 1 ]
then ok "every script and flag runs clean against a chmod -R a-w vault copy"
else no "every script and flag runs clean against a read-only copy  [exits $r1 $r2 $r3 $r4 $r5 $r6 $r7 $r8 $r9 $r10 $r11 $r12 $r13 $r14, links $rl1 $rl2]"; fi
if [ "$(hashes "$AFTER_F")" -ge 10 ] && [ "$BEFORE_F" = "$AFTER_F" ]; then ok "the read-only fixtures' checksum manifest is unchanged after every run"
else no "the read-only fixtures' checksum manifest is unchanged  [$(hashes "$BEFORE_F") before, $(hashes "$AFTER_F") after]"; fi
# The whole-run comparison: these baselines predate the first invocation in this file.
if [ "$(hashes "$END_H")" -ge 3 ] && [ "$START_H" = "$END_H" ]; then ok "the script home is byte-identical to its pre-run baseline"
else no "the script home is byte-identical to its pre-run baseline  [a run left a trace beside the scripts, or the manifest came back empty]"; fi
if [ "$(hashes "$END_FIX")" -ge 10 ] && [ "$START_P$START_C$START_E" = "$END_FIX" ]; then
  ok "the three WRITABLE fixtures are byte-identical to their pre-run baselines"
else no "the three writable fixtures are byte-identical to their pre-run baselines"; fi
# grep -c drops the filename prefix on a single file, so count matches with -o | wc -l instead.
npat(){ local pat="$1"; shift; grep -oE -- "$pat" "$@" | wc -l | tr -d ' '; }
# One control line per pattern, fed on stdin so the control writes nothing. A single
# pattern's control cannot vouch for the others: an io.open() write once slipped through a
# list whose only control was the plain open() form.
CTL_LINES="$(printf '%s\n' \
  'open("x", "w")' 'p.write_text(s)' 'os.remove(p)' 'os.unlink(p)' 'os.rename(a, b)' \
  'os.mkdir(d)' 'os.makedirs(d)' 'shutil.copy(a, b)' 'subprocess.run(c)' 'tempfile.mkdtemp()' \
  'print(x, file=open("f", "w"))' 'io.open(p, "w")' 'pathlib.Path(p)' 'q.write_bytes(b)' \
  'os.open(p, flags)' 'os.fdopen(fd)' 'os.system(c)' 'os.popen(c)' 'os.replace(a, b)' 'os.rmdir(d)')"
hits=0; dead=""
for pat in 'open\([^)]*["'"'"'][wax]' 'write_text' 'write_bytes' 'os\.remove' 'os\.unlink' \
           'os\.rename' 'os\.replace' 'os\.mkdir' 'os\.rmdir' 'makedirs' 'shutil\.' \
           'subprocess' 'tempfile' 'pathlib' 'io\.open' 'os\.open' 'os\.fdopen' \
           'os\.system' 'os\.popen' 'print\(.*file=open'; do
  hits=$((hits + $(npat "$pat" "$ORPH" "$TIER" "$ANOM" "$INDEX" "$LINKS" "$FLAGS")))
  if [ "$(printf '%s\n' "$CTL_LINES" | npat "$pat" -)" -eq 0 ]; then dead="$dead $pat"; fi
done
if [ -n "$dead" ]; then no "every write pattern matches its own control line  [dead:$dead]"
elif [ "$hits" -eq 0 ]; then ok "no write pattern appears in any script source (20 patterns over six scripts, each matched on its own control line)"
else no "no write pattern appears in any script source  [$hits hit(s)]"; fi
# apply-palette.py is the one script here that writes, and only on request: it is excluded from
# the grep above by design, so this leg keys on the property that still has to hold — a REFUSED
# run leaves no trace. The manifest of a non-vault directory is unchanged across --apply.
PMAN="$W/palette-target"; rm -rf "$PMAN"; mkdir -p "$PMAN/docs"; printf 'x\n' > "$PMAN/docs/readme.md"
PBEFORE="$(manifest "$PMAN")"
python3 "$PAL" --apply "$PMAN" > /dev/null 2>&1
python3 "$PAL" --apply --vault "$PMAN" > /dev/null 2>&1
PAFTER="$(manifest "$PMAN")"
if [ "$(hashes "$PBEFORE")" -ge 1 ] && [ "$PBEFORE" = "$PAFTER" ]
then ok "a refused apply-palette.py run leaves the non-vault directory byte-identical"
else no "a refused apply-palette.py run leaves the directory unchanged  [$(hashes "$PBEFORE") before, $(hashes "$PAFTER") after]"; fi

N=$((PASS + FAIL))
printf '\n'
if [ "$FAIL" -eq 0 ]; then printf 'PASS %d/%d\n' "$PASS" "$N"; else printf 'FAIL %d/%d\n' "$FAIL" "$N"; fi
[ "$FAIL" -eq 0 ]
