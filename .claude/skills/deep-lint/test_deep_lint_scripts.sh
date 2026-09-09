#!/bin/bash
# test_deep_lint_scripts.sh — suite for the deep-lint report-only scripts
# (audit-pools.py, sweeps.py, prefix-budget.py).
#
# Fixture vaults are built under one mktemp -d, each isolating one thing. A PLANTED vault, where
# every behaviour has a case that must be caught and a trap that must not fire; a CLEAN vault, which
# must report zeros with their controls; and one vault per premise failure or malformed input —
# byte-order marks, CRLF, absent and unparseable frontmatter, non-ASCII and apostrophe file names, a
# fence marker inside an HTML comment, a page transclusion beside a media embed, two folders sharing
# one stem, a vault older than any fixed control date, a vault with no body date at all, a vault of
# maps and registries only, a young log, a log whose entry pattern matches nothing, an unopenable
# page, and the four states of the always-on prefix layers.
# The final legs are the stdout-only proof: read-only copies of two fixture vaults plus a checksum
# manifest before and after, and a source grep for write patterns whose own positive control is a
# synthetic file that does write.
#
# set -u, deliberately no set -e (a failing leg must be recorded, not abort the suite).
# Run from anywhere:  bash .claude/skills/deep-lint/test_deep_lint_scripts.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$HERE/audit-pools.py"
SWEEPS="$HERE/sweeps.py"
PREFIX="$HERE/prefix-budget.py"
PY=python3

TMP="$(mktemp -d)"
PV="$TMP/planted"       # every behaviour has a case that must be caught, plus traps that must not fire
CV="$TMP/clean"         # must report zeros, each with its control
EV="$TMP/edge"          # the malformed-input vault: BOM, CRLF, no frontmatter, unparseable date,
                        # non-ASCII and apostrophe file names, a fence inside an HTML comment,
                        # a page transclusion, a media embed, two folders sharing one stem
OV="$TMP/oldvault"      # every date predates the constant a fixed control would have used
DV="$TMP/datefree"      # no page body carries any date, so the control must fall back to synthetic
MV="$TMP/mapsonly"      # maps and registries only: nothing is audit-eligible
YV="$TMP/younglog"      # log.md present, no dated entry yet
BL="$TMP/brokenlog"     # log.md has headings but no entry the pattern matches
RO="$TMP/readonly"      # read-only copy of PV for the stdout-only proof
ROE="$TMP/readonly-edge"
NC="$TMP/nocust"        # CUSTOMISATION.md removed
NA="$TMP/noagents"      # .claude/agents removed — legitimate on a fresh machine
NCM="$TMP/noclaudemd"   # CLAUDE.md removed — a premise failure, never an n/a
PH="$TMP/phantomfm"     # an agents file with body `---` rules, and a directory named like one
OUT="$TMP/out"
mkdir -p "$OUT"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n        %s\n' "$1" "$2"; }
leg() { if [ -z "$2" ]; then ok "$1"; else bad "$1" "$2"; fi; }
want() { grep -qF -- "$2" "$1" || printf 'missing [%s]; ' "$2"; }
wantre() { grep -qE -- "$2" "$1" || printf 'no match [%s]; ' "$2"; }
notwant() { if grep -qF -- "$2" "$1"; then printf 'unexpected [%s]; ' "$2"; fi; }
wantrc() { [ "$1" = "$2" ] || printf 'exit %s, expected %s; ' "$1" "$2"; }

w() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
# CRLF and byte-order-mark writers: both are states a real editor produces and both used to make a
# page's whole frontmatter, or a page's whole tail, invisible to the scripts.
wcr() { mkdir -p "$(dirname "$1")"; awk '{printf "%s\r\n", $0}' > "$1"; }
wbom() { mkdir -p "$(dirname "$1")"; { printf '\xef\xbb\xbf'; cat; } > "$1"; }

# ---------------------------------------------------------------- planted fixture
w "$PV/CLAUDE.md" <<'FIXTURE_END'
# Fixture schema

A stand-in for the vault contract, present so the prefix probe has a layer to measure.
FIXTURE_END

w "$PV/CUSTOMISATION.md" <<'FIXTURE_END'
`CUSTOMISATION-LOADED-v1` — fixture preference layer.
FIXTURE_END

w "$PV/.mcp.json" <<'FIXTURE_END'
{"mcpServers": {"fixture-server": {"command": "true"}}}
FIXTURE_END

w "$PV/.claude/skills/alpha/SKILL.md" <<'FIXTURE_END'
---
name: alpha
---

# alpha

Body bytes that the prefix probe must not count.
FIXTURE_END

w "$PV/.claude/skills/beta/SKILL.md" <<'FIXTURE_END'
---
name: beta
description: Two frontmatter lines.
---

# beta

Body bytes that the prefix probe must not count.
FIXTURE_END

w "$PV/.claude/agents/gamma.md" <<'FIXTURE_END'
---
name: gamma
---

A fixture agent definition.
FIXTURE_END

w "$PV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2026-08-20
---

# Index — fixture catalogue

Catalogue reconciled 2026-08-20.

## Concepts
- [[Planted Concept]] — a page whose body outruns its updated field.
- [[Hard Wrap]] — a page carrying one wrapped paragraph.
- [[Raw Tag]] — a page carrying one raw angle-bracket token.
- [[No Confidence]] — a page with no confidence badge.
- [[No Updated]] — a page with no updated field.

## Sources
- [[comment-conf]] — a page whose confidence carries an inline comment.
- [[flagged-source]] — a flagged page.
- [[authoritative-source]] — an authoritative page.
- [[authoritative-two]] — a second authoritative page.
- [[mutable-source]] — a page with a mutable source URL.

## Developments
- [[narrative-doc]] — a development page carrying correction narrative.

## Maps
- [[topic-map]] — the fixture map.
- [[ghost-page]] — registered here but absent from disk.
FIXTURE_END

w "$PV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-30
---

## [2026-06-01] setup | Fixture seed entry
- **Changed**: created [[stale-ghost]]

## [2026-08-29] ingest | Fixture entry one
- **Changed**: created [[Planted Concept]]; updated [[index.md]]

## [2026-08-30] framework | Fixture entry two
- **Changed**: updated [[ghost-target]]
- **Structural**: prefix budget: CLAUDE.md 1000 B · skills 100 B (alpha 30 · zeta 70) · customisation 500 B · MCP 0 declared · total ≈400 tok/request
FIXTURE_END

w "$PV/wiki/maps/topic-map.md" <<'FIXTURE_END'
---
title: Topic Map
type: map
updated: 2026-08-20
---

# Topic Map

- [[Planted Concept]] — the hub link.
FIXTURE_END

w "$PV/wiki/concepts/Planted Concept.md" <<'FIXTURE_END'
---
title: Planted Concept
type: concept
confidence: high
audited: 2026-08-20
updated: 2026-08-20
created: 2026-08-01
---

## Definition
A fixture concept whose body carries a date later than the field claims.

## Key Points
- The rollout note is dated 2026-08-25, after the frontmatter claim.

## Related
- [[Unindexed Page]] — the page this one keeps out of orphan status.
FIXTURE_END

w "$PV/wiki/concepts/Orphan Page.md" <<'FIXTURE_END'
---
title: Orphan Page
type: concept
confidence: medium
updated: 2026-08-20
---

## Definition
A page nothing links to, so it is the planted orphan. It also says the old rule is no longer applied, which is correction narrative outside the developments folder and must not be reported.

## Related
- [[Planted Concept]] — an outbound link that does not save it.
FIXTURE_END

w "$PV/wiki/concepts/Unindexed Page.md" <<'FIXTURE_END'
---
title: Unindexed Page
type: concept
confidence: medium
updated: 2026-08-20
---

## Definition
A page linked from another page but never registered in the index.

## Related
- [[Planted Concept]] — its inbound source.
FIXTURE_END

w "$PV/wiki/concepts/Hard Wrap.md" <<'FIXTURE_END'
---
title: Hard Wrap
type: concept
confidence: high
audited: 2026-08-01
updated: 2026-06-01
---

## Definition
A page carrying one genuine wrapped paragraph and two traps that must not fire.

## a heading that ends in lowercase
continues in lowercase prose beneath a heading, which is not a wrap.

## Key Points
- a list item that ends in lowercase and
continues beneath the item, which is not a wrap either.

## Wrapped paragraph
this paragraph was wrapped at a fixed column and
continues here in lowercase, which is the genuine suspect.

## Related
- [[Planted Concept]] — a link so the page is not an orphan.
FIXTURE_END

w "$PV/wiki/concepts/Raw Tag.md" <<'FIXTURE_END'
---
title: Raw Tag
type: concept
confidence: high
updated: 2026-06-02
---

## Definition
A page with a raw <tag> in rendered prose, a safe `<code>` span, and a fenced example.

## Key Points
- The fenced block below must not count.

```
<div>a fenced tag</div>
```

<!-- a commented <span> must not count -->

## Related
- [[Planted Concept]] — a link so the page is not an orphan.
FIXTURE_END

w "$PV/wiki/concepts/No Confidence.md" <<'FIXTURE_END'
---
title: No Confidence
type: concept
updated: 2026-08-24
---

## Definition
A page with no confidence badge, so it lands in the invalid list.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/concepts/No Updated.md" <<'FIXTURE_END'
---
title: No Updated
type: concept
confidence: medium
---

## Definition
A page with no updated field, so it belongs to neither pool.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/sources/comment-conf.md" <<'FIXTURE_END'
---
title: Comment Conf
type: source
confidence: high   # note: graded from the abstract
depth: standard
updated: 2026-08-20
---

## Summary
A source page whose confidence value carries an inline comment.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/sources/flagged-source.md" <<'FIXTURE_END'
---
title: Flagged Source
type: source
confidence: high
flagged: freshness suspected at query time
updated: 2026-08-22
---

## Summary
A source page carrying a freshness flag, so Step 2 has already read it.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/sources/authoritative-source.md" <<'FIXTURE_END'
---
title: Authoritative Source
type: source
confidence: authoritative
updated: 2026-08-23
source_url: https://arxiv.org/abs/2501.00001
---

## Summary
A peer-reviewed source whose URL is immutable, so freshness must skip it.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/sources/authoritative-two.md" <<'FIXTURE_END'
---
title: Authoritative Two
type: source
confidence: authoritative
updated: 2026-08-23
---

## Summary
A second authoritative page, so the cap can overflow the always-include stratum.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/sources/mutable-source.md" <<'FIXTURE_END'
---
title: Mutable Source
type: source
confidence: medium
updated: 2026-06-03
source_url: https://example.com/fixture-post
---

## Summary
A source whose URL is mutable, so it is a freshness candidate.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END

w "$PV/wiki/developments/narrative-doc.md" <<'FIXTURE_END'
---
title: Narrative Doc
type: development
confidence: medium
updated: 2026-08-21
---

## Design
A development page carrying two correction-narrative phrases.

The rule is no longer applied to new lanes.

The clause was removed from the contract in an earlier pass.

## Sources Used
- [[Planted Concept]] — an outbound link.
FIXTURE_END

# ---------------------------------------------------------------- clean fixture
w "$CV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2026-08-20
---

# Index — clean fixture catalogue

Catalogue reconciled 2026-08-20.

## Concepts
- [[Alpha Page]] — the first clean page.
- [[Beta Page]] — the second clean page.

## Developments
- [[clean-doc]] — a forward-facing development page.

## Maps
- [[clean-map]] — the clean map.
FIXTURE_END

w "$CV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-21
---

## [2026-08-20] ingest | Clean entry one
- **Changed**: created [[Alpha Page]]; updated [[index.md]]

## [2026-08-21] framework | Clean entry two
- **Changed**: updated [[Beta Page]]
FIXTURE_END

w "$CV/wiki/concepts/Alpha Page.md" <<'FIXTURE_END'
---
title: Alpha Page
type: concept
confidence: high
audited: 2026-08-20
updated: 2026-08-20
---

## Definition
A clean page whose prose sits on one line per paragraph.
A second line that begins with a capital, so the pair is scanned and rejected.

## Related
- [[Beta Page]] — a sibling link.
- [[clean-doc]] — the development record.
FIXTURE_END

w "$CV/wiki/concepts/Beta Page.md" <<'FIXTURE_END'
---
title: Beta Page
type: concept
confidence: medium
audited: 2026-08-20
updated: 2026-08-20
---

## Definition
A second clean page, linked both ways.

## Related
- [[Alpha Page]] — a sibling link.
FIXTURE_END

w "$CV/wiki/developments/clean-doc.md" <<'FIXTURE_END'
---
title: Clean Doc
type: development
confidence: medium
audited: 2026-08-20
updated: 2026-08-20
---

## Design
A forward-facing development record with no correction narrative in it.

## Sources Used
- [[Alpha Page]] — the page it records.
FIXTURE_END

w "$CV/wiki/maps/clean-map.md" <<'FIXTURE_END'
---
title: Clean Map
type: map
updated: 2026-08-20
---

# Clean Map

- [[Alpha Page]] — the hub link.
FIXTURE_END

# ---------------------------------------------------------------- edge fixture (malformed inputs)
w "$EV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2026-08-20
---

# Index — edge fixture catalogue

Catalogue reconciled 2026-08-20.

## Concepts
- [[CR Page]] — a page written with CRLF line endings.
- [[BOM Page]] — a page behind a byte-order mark.
- [[No Frontmatter]] — a page with no frontmatter at all.
- [[Bad Date]] — a page whose updated value does not parse.
- [[Fence In Comment]] — a page with a fence marker inside an HTML comment.
- [[Unicode Pagé ✦]] — a page whose name carries non-ASCII characters.
- [[Owner's Note]] — a page whose name carries an apostrophe.
FIXTURE_END

w "$EV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-22
---

## [2026-08-21] ingest | Edge entry one
- **Changed**: created [[CR Page]]; embedded ![[missing-diagram.png]]

## [2026-08-22] framework | Edge entry two
- **Changed**: transcluded ![[Transcluded]]; touched [[ghost-entry]]
FIXTURE_END

wcr "$EV/wiki/concepts/CR Page.md" <<'FIXTURE_END'
---
title: CR Page
type: concept
confidence: high
audited: 2026-08-20
updated: 2026-08-20
---

## Definition
A page whose every line ends CRLF, so the frontmatter parser and the line classifier both meet carriage returns.

## Related
- [[BOM Page]] — a sibling link.
- ![[Transcluded]] — a page transclusion, which is a live inbound link.
- ![[cover.png]] — a media embed, which is not a page link.
FIXTURE_END

wbom "$EV/wiki/concepts/BOM Page.md" <<'FIXTURE_END'
---
title: BOM Page
type: concept
confidence: high
updated: 2026-08-21
---

## Definition
A page whose frontmatter sits behind a byte-order mark, which used to hide every field on it.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/concepts/No Frontmatter.md" <<'FIXTURE_END'
## Definition
A page with no frontmatter block at all, so it carries no confidence and no updated value.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/concepts/Bad Date.md" <<'FIXTURE_END'
---
title: Bad Date
type: concept
confidence: medium
updated: not-a-date
---

## Definition
A page whose updated value does not parse, so it belongs to neither pool.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

wcr "$EV/wiki/concepts/Fence In Comment.md" <<'FIXTURE_END'
---
title: Fence In Comment
type: concept
confidence: high
updated: 2026-08-22
---

## Definition
A page whose HTML comment contains a fence marker, followed by a genuine wrap and a genuine raw tag.

<!--
```
a fence marker inside a comment must not toggle the fence state
-->

this paragraph was wrapped at a fixed column and
continues here in lowercase, which is the genuine suspect.

a raw <tag> after the comment block, which is a genuine defect.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/concepts/Transcluded.md" <<'FIXTURE_END'
---
title: Transcluded
type: concept
confidence: medium
updated: 2026-08-22
---

## Definition
A page nothing links to except a transclusion, so it is an orphan unless an embed counts as a link.

## Related
- [[CR Page]] — an outbound link that does not save it.
FIXTURE_END

w "$EV/wiki/concepts/Unicode Pagé ✦.md" <<'FIXTURE_END'
---
title: Unicode Pagé ✦
type: concept
confidence: medium
updated: 2026-08-22
---

## Definition
A page whose file name carries non-ASCII characters.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/concepts/Owner's Note.md" <<'FIXTURE_END'
---
title: Owner's Note
type: concept
confidence: medium
updated: 2026-08-22
---

## Definition
A page whose file name carries an apostrophe, which every vault-wide sweep has to survive.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/benchmarks/BrowseComp-Plus.md" <<'FIXTURE_END'
---
title: BrowseComp-Plus
type: benchmark
confidence: medium
updated: 2026-08-22
source_url: https://example.com/a-living-page
---

## Definition
A benchmark page sharing its lowercased stem with a source page in another folder.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

w "$EV/wiki/sources/browsecomp-plus.md" <<'FIXTURE_END'
---
title: browsecomp-plus
type: source
confidence: medium
depth: standard
updated: 2026-08-22
source_url: https://www.semanticscholar.org/paper/fixture-identifier
---

## Summary
A source page sharing its lowercased stem with a benchmark page in another folder.

## Related
- [[CR Page]] — an outbound link.
FIXTURE_END

# ---------------------------------------------------------------- old-date fixture
w "$OV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2024-01-05
---

# Index — old-date fixture catalogue

Catalogue reconciled 2024-01-05.

## Concepts
- [[Old Page]] — the only page.
FIXTURE_END

w "$OV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2024-01-05
---

## [2024-01-05] setup | Old seed entry
- **Changed**: created [[Old Page]]
FIXTURE_END

w "$OV/wiki/concepts/Old Page.md" <<'FIXTURE_END'
---
title: Old Page
type: concept
confidence: high
audited: 2024-01-01
updated: 2024-01-01
---

## Definition
A page dated years before any constant a fixed control would have planted.

## Related
- [[Index]] — an outbound link.
FIXTURE_END

# ---------------------------------------------------------------- date-free fixture
w "$DV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2026-08-20
---

# Index — date-free fixture catalogue

## Concepts
- [[Undated Page]] — the only page, and no body anywhere carries a date.
FIXTURE_END

w "$DV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-20
---

## [2026-08-20] setup | Date-free seed entry
- **Changed**: created [[Undated Page]]
FIXTURE_END

w "$DV/wiki/concepts/Undated Page.md" <<'FIXTURE_END'
---
title: Undated Page
type: concept
confidence: high
updated: 2026-08-20
---

## Definition
A page whose body names no date at all, so the accuracy sweep has no real page to plant on.

## Related
- [[Index]] — an outbound link.
FIXTURE_END

# ---------------------------------------------------------------- maps-and-registries-only fixture
w "$MV/wiki/index.md" <<'FIXTURE_END'
---
title: Index
type: index
confidence: high
updated: 2026-08-20
---

## Maps
- [[Only Map]] — the only page besides the registries.
FIXTURE_END

w "$MV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-20
---

## [2026-08-20] maps | Only map created
- **Changed**: created [[Only Map]]
FIXTURE_END

w "$MV/wiki/maps/Only Map.md" <<'FIXTURE_END'
---
title: Only Map
type: map
updated: 2026-08-20
---

# Only Map

- [[Index]] — the hub link.
FIXTURE_END

# ================================================================= runs
run() { # run <outfile> <command...>
  local out="$1"; shift
  "$@" > "$OUT/$out" 2>&1
  echo $?
}

rc_a1=$(run a1.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02)
rc_a2=$(run a2.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02 --cap 3)
rc_a3=$(run a3.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02 --cap 1)
rc_a4=$(run a4.txt "$PY" "$AUDIT" --vault "$PV" --today 2026-09-02)
rc_a5=$(run a5.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02 --format json)
rc_a6=$(run a6.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02 --cap 4 --seed 0)
rc_a7=$(run a7.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02 --cap 4 --seed 0)
rc_c1=$(run c1.txt "$PY" "$AUDIT" --vault "$CV" --baseline 2026-08-15 --today 2026-09-02)
rc_s1=$(run s1.txt "$PY" "$SWEEPS" --vault "$PV")
rc_s2=$(run s2.txt "$PY" "$SWEEPS" --vault "$PV" --phrases "was removed")
rc_s3=$(run s3.txt "$PY" "$SWEEPS" --vault "$CV")
rc_p1=$(run p1.txt "$PY" "$PREFIX" --vault "$PV")
rc_p2=$(run p2.txt "$PY" "$PREFIX" --vault "$PV" --diff-log wiki/log.md)

# copy-then-break fixtures: each starts from a healthy vault so the broken state is the only variable
cp -R "$EV" "$YV"
w "$YV/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-22
---
FIXTURE_END
cp -R "$EV" "$BL"
w "$BL/wiki/log.md" <<'FIXTURE_END'
---
title: Log
type: log
confidence: high
updated: 2026-08-22
---

## Not a dated entry heading
- **Changed**: nothing the entry pattern can match
FIXTURE_END
cp -R "$PV" "$NA"; rm -rf "$NA/.claude/agents"
cp -R "$PV" "$NCM"; rm -f "$NCM/CLAUDE.md"
cp -R "$PV" "$PH"
w "$PH/.claude/agents/README.md" <<'FIXTURE_END'
A note in the agents folder that opens with prose, not a frontmatter block.

---

A horizontal rule.

---

Another one, so a scan that hunts any pair of markers finds a phantom block.
FIXTURE_END
mkdir -p "$PH/.claude/agents/notadefinition.md"

rc_e1=$(run e1.txt "$PY" "$AUDIT" --vault "$EV" --today 2026-09-02)
rc_e2=$(run e2.txt "$PY" "$SWEEPS" --vault "$EV")
rc_o1=$(run o1.txt "$PY" "$AUDIT" --vault "$OV" --baseline 2024-01-01 --today 2024-06-01)
rc_d1=$(run d1.txt "$PY" "$AUDIT" --vault "$DV" --today 2026-09-02)
rc_m1=$(run m1.txt "$PY" "$AUDIT" --vault "$MV" --today 2026-09-02)
rc_y1=$(run y1.txt "$PY" "$AUDIT" --vault "$YV" --today 2026-09-02)
rc_b1=$(run b1.txt "$PY" "$AUDIT" --vault "$BL" --today 2026-09-02)
rc_n1=$(run n1.txt "$PY" "$AUDIT" --vault "$PV" --today 2026-09-02 --cap -1)
rc_n2=$(run n2.txt "$PY" "$AUDIT" --vault "$PV" --today 2026-09-02 --tail -1)
rc_s4=$(run s4.txt "$PY" "$SWEEPS" --vault "$PV" --phrases "<retired>")
rc_p4=$(run p4.txt "$PY" "$PREFIX" --vault "$NA")
rc_p5=$(run p5.txt "$PY" "$PREFIX" --vault "$NCM")
rc_p6=$(run p6.txt "$PY" "$PREFIX" --vault "$PH")
rc_p7=$(run p7.txt "$PY" "$PREFIX" --vault "$PV" --diff-log wiki/absent-log.md)
rc_e3=$(run e3.txt "$PY" "$AUDIT" --vault "$EV" --today 2026-09-02 --format json)

A1="$OUT/a1.txt"; A2="$OUT/a2.txt"; A3="$OUT/a3.txt"; A4="$OUT/a4.txt"; A5="$OUT/a5.txt"
C1="$OUT/c1.txt"; S1="$OUT/s1.txt"; S2="$OUT/s2.txt"; S3="$OUT/s3.txt"
P1="$OUT/p1.txt"; P2="$OUT/p2.txt"
E1="$OUT/e1.txt"; E2="$OUT/e2.txt"

# ================================================================= legs
r=""
r="$r$(wantrc "$rc_a1" 0)"
r="$r$(want "$A1" 'pages scanned: 16 · audit-eligible: 13')"
r="$r$(want "$A1" 'audit-pools: vault=')"
r="$r$(want "$A1" 'cap=40 tail=20 seed=0')"
leg "1  eligible count and printed defaults" "$r"

r=""
r="$r$(want "$A1" 'invalid or missing: 1')"
r="$r$(want "$A1" 'inline comments stripped on 1 pages')"
r="$r$(want "$A1" 'wiki/concepts/No Confidence.md — (missing)')"
r="$r$(notwant "$A1" '  wiki/sources/comment-conf.md — high')"
r="$r$(want "$A1" 'distribution: authoritative 2 · high 5 · medium 5 · low 0 · very-low 0')"
leg "2  confidence coverage, comment-stripped" "$r"

r=""
r="$r$(want "$A1" 'pool A (changed, updated >= 2026-08-15): 9')"
r="$r$(want "$A1" 'pool B (unchanged): 3')"
r="$r$(want "$A1" 'unclassifiable (no parseable updated:): 1')"
r="$r$(want "$A1" '  wiki/concepts/No Updated.md')"
# The control baseline is DERIVED (one day before the oldest updated: in the vault), never a fixed
# year: the fixture's oldest page is 2026-06-01, so the control must read 2026-05-31.
r="$r$(want "$A1" 'pool-control: baseline 2026-05-31 returns 12 of 12 classifiable eligible pages')"
leg "3  pools A and B with the derived baseline control" "$r"

r=""
r="$r$(want "$A1" 'flagged: 1 of 1 (Step 2 — no cap cost)')"
r="$r$(want "$A1" 'authoritative: 2 of 2')"
r="$r$(want "$A1" 'compiled/derived-high: 1 of 1')"
r="$r$(want "$A1" 'other: 5 of 5')"
r="$r$(want "$A1" 'cap: audited 8 of 8 (under cap — no sampling)')"
leg "4  strata in fill order, under-cap branch" "$r"

r=""
r="$r$(want "$A1" 'tail pool: 3 unchanged · oldest third: 3 · sampled: 3 (cap 20)')"
r="$r$(want "$A1" 'key range: 2026-06-02 -> 2026-08-01')"
leg "5  tail pool keyed on audited: else updated:" "$r"

r=""
r="$r$(want "$A1" "$(printf 'FLAGGED\twiki/sources/flagged-source.md')")"
r="$r$(want "$A1" "$(printf 'AUTH\twiki/sources/authoritative-source.md')")"
r="$r$(want "$A1" "$(printf 'A-HIGH\twiki/concepts/Planted Concept.md')")"
r="$r$(want "$A1" "$(printf 'UNCLASS\twiki/concepts/No Updated.md')")"
r="$r$(want "$A1" "$(printf 'TAIL\twiki/concepts/Raw Tag.md')")"
r="$r$(wantre "$A1" 'A-HIGH.*· concept · high · upd=2026-08-20 · aud=2026-08-20 · in=[0-9]+ · [0-9]+ B')"
r="$r$(want "$A1" 'sample size: 13 pages')"
leg "6  sample listing in fill order with page metadata" "$r"

r=""
r="$r$(want "$A1" 'updated-accuracy: 1 pages carry a body date later than the field')"
r="$r$(want "$A1" '  wiki/concepts/Planted Concept.md 2026-08-20 -> 2026-08-25')"
# The planted date is derived from index.md's own oldest body date (2026-08-20), minus one day.
r="$r$(want "$A1" 'updated-control: planted 2026-08-19 on a copy of wiki/index.md -> caught')"
leg "7  planted later body date caught, with its derived control" "$r"

r=""
r="$r$(want "$A1" 'orphans: 1 (index, log and maps exempt)')"
r="$r$(want "$A1" '  wiki/concepts/Orphan Page.md')"
r="$r$(notwant "$A1" '  wiki/concepts/Unindexed Page.md')"
r="$r$(want "$A1" 'inbound-control: 13 pages carry >= 1 inbound link')"
r="$r$(want "$A1" 'orphans with index.md excluded as a source: 11')"
leg "8  planted orphan caught, aliases and exemptions honoured" "$r"

r=""
r="$r$(want "$A1" 'registered names: 13 · pages on disk: 14 · unindexed on disk: 2 · registered without a page or alias: 1')"
r="$r$(want "$A1" '  unindexed: wiki/concepts/Orphan Page.md')"
r="$r$(want "$A1" '  unindexed: wiki/concepts/Unindexed Page.md')"
r="$r$(want "$A1" '  registered but absent: ghost-page')"
leg "9  index consistency both ways" "$r"

r=""
r="$r$(want "$A1" 'entries >= 2026-08-15: 2 of 3 · links checked: 3 · unresolved: 1')"
r="$r$(want "$A1" '## [2026-08-30] framework | Fixture entry two -> unresolved: ghost-target')"
r="$r$(notwant "$A1" 'stale-ghost')"
leg "10 planted dangling log link caught, scoped to the baseline" "$r"

r=""
r="$r$(wantre "$A1" 'entries: 2 · median [0-9]+ B · mean [0-9]+ B · max [0-9]+ B · log.md total [0-9]+ B')"
leg "11 log entry sizes for entries at or after the baseline" "$r"

r=""
r="$r$(want "$A1" 'source_url pages: 2 · mutable 1 · immutable 1')"
r="$r$(wantre "$A1" 'score=[0-9]+ wiki/sources/mutable-source.md · medium')"
r="$r$(notwant "$A1" 'arxiv.org')"
leg "12 freshness candidates rank the mutable URL and skip the immutable one" "$r"

r=""
r="$r$(want "$A1" 'changed: audited 9 of 9 — flagged 1 (Step 2) · authoritative 2 of 2 · compiled/derived-high 1 of 1 · other 5 of 5 · not audited 0')"
r="$r$(want "$A1" 'tail: sampled 3 of 3 least-recently-audited (of 3 unchanged)')"
r="$r$(want "$A1" 'audited: coverage 2 of 13 eligible pages (15.4%)')"
leg "13 the three runbook report lines, verbatim shape" "$r"

r=""
r="$r$(wantrc "$rc_a2" 0)"
r="$r$(want "$A2" 'changed: audited 4 of 9 — flagged 1 (Step 2) · authoritative 2 of 2 · compiled/derived-high 1 of 1 · other 0 of 5 · not audited 5')"
r="$r$(want "$A2" 'cap: 3 · always-include first, then two-thirds compiled/derived-high')"
leg "14 cap rule: always-include first, then the two-thirds split" "$r"

r=""
r="$r$(wantrc "$rc_a3" 0)"
r="$r$(want "$A3" 'authoritative: 1 of 2 — cap reached, 1 not audited')"
r="$r$(want "$A3" 'compiled/derived-high: 0 of 1')"
leg "15 always-include overflow reported, never a silent stretch" "$r"

r=""
r="$r$(wantrc "$rc_a4" 0)"
r="$r$(want "$A4" 'NO-BASELINE MODE: no previous deep-lint date given')"
r="$r$(want "$A4" 'pool A (changed, updated >= n/a — whole vault): 12')"
r="$r$(want "$A4" 'pool B (unchanged): 0')"
r="$r$(want "$A4" 'tail: sampled 0 of 0 least-recently-audited (of 0 unchanged)')"
leg "16 no-baseline mode: one pool at the same cap" "$r"

r=""
r="$r$(wantrc "$rc_a5" 0)"
if ! "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["eligible"]==13, d["eligible"]; assert len(d["report_lines"])==3; assert d["pools"]["pool_a"]==9; assert len(d["sample"])==13' "$A5"; then
  r="$r json payload did not parse or did not match;"
fi
r="$r$(wantrc "$rc_a6" 0)"
if ! cmp -s "$OUT/a6.txt" "$OUT/a7.txt"; then r="$r same seed produced different output;"; fi
leg "17 json output parses; the seed makes the draw reproducible" "$r"

r=""
r="$r$(wantrc "$rc_s1" 0)"
r="$r$(want "$S1" 'hardwrap: 1 suspects on 1 pages')"
r="$r$(want "$S1" '  wiki/concepts/Hard Wrap.md (1)')"
r="$r$(wantre "$S1" '[1-9][0-9]* adjacent prose pairs scanned')"
r="$r$(want "$S1" 'hardwrap-control: fired')"
r="$r$(notwant "$S1" 'continues in lowercase prose beneath a heading')"
leg "18 hard wrap caught; heading and list traps did not fire" "$r"

r=""
r="$r$(want "$S1" 'raw tags in rendered prose: 1')"
r="$r$(want "$S1" 'wiki/concepts/Raw Tag.md:9 <tag>')"
r="$r$(want "$S1" 'tag-control: fired')"
r="$r$(notwant "$S1" '<div>')"
r="$r$(notwant "$S1" '<span>')"
leg "19 raw tag caught; backticked, fenced and commented tags did not" "$r"

r=""
r="$r$(want "$S1" 'narrative phrases: 2 hits over 1 development pages')"
r="$r$(want "$S1" 'wiki/developments/narrative-doc.md')"
r="$r$(notwant "$S1" 'wiki/concepts/Orphan Page.md:')"
r="$r$(want "$S1" 'narrative-control: fired')"
r="$r$(wantrc "$rc_s2" 0)"
r="$r$(want "$S2" 'narrative phrases: 1 hits over 1 development pages (phrases: was removed)')"
leg "20 correction narrative scoped to developments; --phrases overrides" "$r"

r=""
r="$r$(wantrc "$rc_c1" 0)"
r="$r$(want "$C1" 'invalid or missing: 0')"
r="$r$(want "$C1" 'orphans: 0 (index, log and maps exempt)')"
r="$r$(want "$C1" 'inbound-control: 4 pages carry >= 1 inbound link')"
r="$r$(want "$C1" 'orphans with index.md excluded as a source: 0')"
r="$r$(want "$C1" 'registered names: 4 · pages on disk: 4 · unindexed on disk: 0 · registered without a page or alias: 0')"
r="$r$(want "$C1" 'updated-accuracy: 0 pages carry a body date later than the field')"
r="$r$(want "$C1" 'updated-control: planted 2026-08-19 on a copy of wiki/index.md -> caught')"
r="$r$(want "$C1" 'pool-control: baseline 2026-08-19 returns 3 of 3 classifiable eligible pages')"
r="$r$(wantre "$C1" 'links checked: [1-9][0-9]* · unresolved: 0')"
r="$r$(want "$C1" 'audited: coverage 3 of 3 eligible pages (100.0%)')"
r="$r$(notwant "$C1" 'PROBE FAILED')"
leg "21 clean vault: audit-pools reports zeros with their controls" "$r"

r=""
r="$r$(wantrc "$rc_s3" 0)"
r="$r$(want "$S3" 'hardwrap: 0 suspects on 0 pages')"
r="$r$(wantre "$S3" '[1-9][0-9]* adjacent prose pairs scanned')"
r="$r$(want "$S3" 'hardwrap-control: fired')"
r="$r$(want "$S3" 'raw tags in rendered prose: 0')"
r="$r$(want "$S3" 'tag-control: fired')"
r="$r$(want "$S3" 'narrative phrases: 0 hits over 1 development pages')"
r="$r$(want "$S3" 'narrative-control: fired')"
r="$r$(notwant "$S3" 'PROBE FAILED')"
leg "22 clean vault: sweeps report zeros with their controls" "$r"

exp_alpha=$(awk '{n += length($0) + 1} $0 == "---" {c++; if (c == 2) {print n; exit}}' "$PV/.claude/skills/alpha/SKILL.md")
exp_beta=$(awk '{n += length($0) + 1} $0 == "---" {c++; if (c == 2) {print n; exit}}' "$PV/.claude/skills/beta/SKILL.md")
exp_gamma=$(awk '{n += length($0) + 1} $0 == "---" {c++; if (c == 2) {print n; exit}}' "$PV/.claude/agents/gamma.md")
exp_skills=$((exp_alpha + exp_beta))
exp_claude=$(wc -c < "$PV/CLAUDE.md" | tr -d ' ')
exp_cust=$(wc -c < "$PV/CUSTOMISATION.md" | tr -d ' ')
exp_total=$(( (exp_claude + exp_skills + exp_gamma + exp_cust) / 4 ))
r=""
r="$r$(wantrc "$rc_p1" 0)"
r="$r$(want "$P1" "prefix budget: CLAUDE.md $exp_claude B · skills $exp_skills B (alpha $exp_alpha · beta $exp_beta) · agents $exp_gamma B (gamma $exp_gamma) · customisation $exp_cust B · MCP 1 declared · total ≈$exp_total tok/request")"
r="$r$(want "$P1" 'mcp-probe: .mcp.json present (1)')"
r="$r$(want "$P1" 'skills measured=2 of 2 candidates agents measured=1 of 1 candidates')"
leg "23 prefix budget line, markers-included frontmatter arithmetic" "$r"

r=""
r="$r$(wantrc "$rc_p2" 0)"
r="$r$(want "$P2" "  CLAUDE.md: 1000 -> $exp_claude B")"
r="$r$(want "$P2" "    skill alpha: 30 -> $exp_alpha B")"
r="$r$(want "$P2" '    retired skill: zeta (was 70 B)')"
r="$r$(want "$P2" "    new skill: beta $exp_beta B")"
r="$r$(want "$P2" '  agents: no figure in the previous line — format baseline, cannot diff')"
r="$r$(want "$P2" '  MCP: 0 -> 1 declared (+1)')"
leg "24 --diff-log deltas: changed, new, retired, format baseline" "$r"

cp -R "$PV" "$NC"
rm -f "$NC/CUSTOMISATION.md"
rc_p3=$(run p3.txt "$PY" "$PREFIX" --vault "$NC")
r=""
r="$r$(wantrc "$rc_p3" 2)"
r="$r$(want "$OUT/p3.txt" 'PROBE FAILED: CUSTOMISATION.md is absent')"
r="$r$(wantre "$OUT/p3.txt" 'prefix budget: CLAUDE\.md [0-9]+ B')"
leg "25 a missing layer is a probe failure, not a zero (exit 2)" "$r"

rc_a8=$(run a8.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2027-01-01 --today 2026-09-02)
r=""
r="$r$(wantrc "$rc_a8" 0)"
# A baseline after every page empties pool A of changed pages; the one flagged page is still
# lifted into it (the stratum is defined by the flag, not the window — 2026-09-08), so the
# pool reads 1 with the lift printed, and the control still passes.
r="$r$(want "$OUT/a8.txt" 'pool A (changed, updated >= 2027-01-01): 1 · flagged lifted from below the baseline: 1')"
r="$r$(want "$OUT/a8.txt" 'pool B (unchanged): 11')"
r="$r$(want "$OUT/a8.txt" 'pool-control: baseline 2026-05-31 returns 12 of 12 classifiable eligible pages')"
r="$r$(want "$OUT/a8.txt" 'changed: audited 1 of 1 — flagged 1 (Step 2)')"
r="$r$(notwant "$OUT/a8.txt" 'PROBE FAILED')"
leg "26 zero changed pages is a finding, not a failure, once the control passes (the flagged page alone is lifted)" "$r"

# ---------------------------------------------------------------- the flagged lift (2026-09-08)
# The entry (wiki page writers): a flagged: write did not bump updated:, so a flagged page could
# sit in deep-lint's cold tail unread. Every flagged page now sits in pool A whatever its date.
# Fixture: the planted vault plus one flagged page dated before the baseline; it must appear
# under FLAGGED, leave pool B, and the counts must say so.
SV="$TMP/staleflag"; rm -rf "$SV"; cp -R "$PV" "$SV"
w "$SV/wiki/sources/stale-flagged.md" <<'FIXTURE_END'
---
title: Stale Flagged
type: source
confidence: high
flagged: 2026-06-15 source conversion suspect — run-together 12.3 %
updated: 2026-06-15
---

## Summary
A source page flagged long before the baseline, with no updated: bump.

## Related
- [[Planted Concept]] — an outbound link.
FIXTURE_END
rc_sf=$(run sf.txt "$PY" "$AUDIT" --vault "$SV" --baseline 2026-08-15 --today 2026-09-02)
r=""
r="$r$(wantrc "$rc_sf" 0)"
r="$r$(want "$OUT/sf.txt" 'pool A (changed, updated >= 2026-08-15): 10 · flagged lifted from below the baseline: 1')"
r="$r$(want "$OUT/sf.txt" 'pool B (unchanged): 3')"
r="$r$(want "$OUT/sf.txt" 'flagged: 2 of 2 (Step 2 — no cap cost)')"
r="$r$(want "$OUT/sf.txt" "$(printf 'FLAGGED\twiki/sources/stale-flagged.md · source · high · upd=2026-06-15')")"
r="$r$(want "$OUT/sf.txt" "$(printf 'FLAGGED\twiki/sources/flagged-source.md')")"
r="$r$(notwant "$OUT/sf.txt" "$(printf 'TAIL\twiki/sources/stale-flagged.md')")"
r="$r$(want "$OUT/sf.txt" 'changed: audited 10 of 10 — flagged 2 (Step 2)')"
leg "26b a flagged page older than the baseline is lifted into pool A under FLAGGED, never the tail, and the counts say so" "$r"
rc_sfj=$(run sfj.txt "$PY" "$AUDIT" --vault "$SV" --baseline 2026-08-15 --today 2026-09-02 --format json)
r=""
r="$r$(wantrc "$rc_sfj" 0)"
r="$r$(want "$OUT/sfj.txt" '"flagged_lifted": 1')"
r="$r$(want "$OUT/sfj.txt" '"pool_a": 10')"
leg "26c the JSON form carries the lifted count" "$r"
rc_a9=$(run a9.txt "$PY" "$AUDIT" --vault "$PV" --baseline 2026-08-15 --today 2026-09-02)
r=""
r="$r$(want "$OUT/a9.txt" 'pool A (changed, updated >= 2026-08-15): 9')"
r="$r$(notwant "$OUT/a9.txt" 'flagged lifted')"
leg "26d control: with every flagged page inside the window nothing is lifted and the line is unchanged" "$r"

# ---------------------------------------------------------------- malformed-input legs
r=""
r="$r$(wantrc "$rc_e1" 0)"
r="$r$(want "$E1" 'pages scanned: 12 · audit-eligible: 10')"
r="$r$(wantre "$E1" 'A-HIGH\twiki/concepts/BOM Page.md · concept · high · upd=2026-08-21')"
r="$r$(wantre "$E1" 'wiki/concepts/CR Page.md · concept · high · upd=2026-08-20 · aud=2026-08-20')"
r="$r$(want "$E1" 'invalid or missing: 1')"
r="$r$(want "$E1" 'wiki/concepts/No Frontmatter.md — (missing)')"
r="$r$(want "$E1" 'unclassifiable (no parseable updated:): 2')"
r="$r$(want "$E1" '  wiki/concepts/Bad Date.md')"
leg "27 BOM, CRLF, missing and unparseable frontmatter each land in the right pool" "$r"

r=""
r="$r$(want "$E1" "$(printf 'A-OTHER\twiki/concepts/Unicode Pagé ✦.md')")"
r="$r$(want "$E1" "$(printf "A-OTHER\twiki/concepts/Owner's Note.md")")"
r="$r$(want "$E1" 'pool-control: baseline 2026-08-19 returns 8 of 8 classifiable eligible pages')"
leg "28 non-ASCII and apostrophe file names survive every path that prints them" "$r"

r=""
r="$r$(want "$E1" 'orphans: 2 (index, log and maps exempt)')"
r="$r$(want "$E1" '  wiki/benchmarks/BrowseComp-Plus.md')"
r="$r$(notwant "$E1" '  wiki/concepts/Transcluded.md')"
r="$r$(want "$E1" 'links checked: 3 · unresolved: 1')"
r="$r$(want "$E1" 'unresolved: ghost-entry')"
r="$r$(notwant "$E1" 'missing-diagram')"
leg "29 a page transclusion is an inbound link, a media embed is not (check-links parity)" "$r"

r=""
r="$r$(want "$E1" 'registered names: 7 · pages on disk: 10 · unindexed on disk: 3')"
r="$r$(want "$E1" '  unindexed: wiki/benchmarks/BrowseComp-Plus.md')"
r="$r$(want "$E1" '  unindexed: wiki/sources/browsecomp-plus.md')"
r="$r$(want "$E1" '  note: browsecomp-plus is the stem of more than one page')"
leg "30 two folders sharing one stem: both are reported, neither masks the other" "$r"

r=""
r="$r$(wantrc "$rc_e2" 0)"
r="$r$(want "$E2" 'hardwrap: 1 suspects on 1 pages · 1 adjacent prose pairs scanned')"
r="$r$(want "$E2" '  wiki/concepts/Fence In Comment.md (1)')"
r="$r$(want "$E2" 'raw tags in rendered prose: 1')"
r="$r$(want "$E2" 'wiki/concepts/Fence In Comment.md:19 <tag>')"
r="$r$(want "$E2" 'hardwrap-control: fired')"
r="$r$(want "$E2" 'tag-control: fired')"
leg "31 a fence marker inside an HTML comment no longer swallows the rest of the page" "$r"

r=""
r="$r$(want "$E2" 'narrative phrases: 0 hits over 0 development pages')"
r="$r$(want "$E2" 'note: this vault holds no wiki/developments/ page')"
r="$r$(want "$E2" 'narrative-control: fired')"
leg "32 an empty developments scope prints its scope, never a bare zero" "$r"

r=""
r="$r$(wantrc "$rc_o1" 0)"
r="$r$(want "$OUT/o1.txt" 'pool-control: baseline 2023-12-31 returns 1 of 1 classifiable eligible pages')"
r="$r$(want "$OUT/o1.txt" 'updated-control: planted 2024-01-04 on a copy of wiki/index.md -> caught')"
r="$r$(notwant "$OUT/o1.txt" 'PROBE FAILED')"
leg "33 a vault older than any fixed control date still fires both derived controls" "$r"

r=""
r="$r$(wantrc "$rc_d1" 0)"
r="$r$(want "$OUT/d1.txt" 'updated-control: planted 2026-08-31 on a synthetic page (no vault page carries a body date) -> caught')"
r="$r$(want "$OUT/d1.txt" 'updated-accuracy: 0 pages carry a body date later than the field')"
r="$r$(notwant "$OUT/d1.txt" 'PROBE FAILED')"
leg "34 no body date anywhere: the control falls back to synthetic, never to a failure" "$r"

r=""
r="$r$(wantrc "$rc_m1" 2)"
r="$r$(want "$OUT/m1.txt" 'PROBE FAILED: no audit-eligible page')"
leg "35 a vault of maps and registries only is a premise failure, not a clean audit" "$r"

r=""
r="$r$(wantrc "$rc_y1" 0)"
r="$r$(want "$OUT/y1.txt" 'log link health: n/a')"
r="$r$(want "$OUT/y1.txt" 'entry sizes: n/a — no dated entry to measure')"
r="$r$(notwant "$OUT/y1.txt" 'unresolved: 0')"
r="$r$(notwant "$OUT/y1.txt" 'PROBE FAILED')"
r="$r$(wantrc "$rc_b1" 2)"
r="$r$(want "$OUT/b1.txt" 'PROBE FAILED: wiki/log.md has heading lines (1) but no dated entry matched')"
leg "36 a young log reports n/a; a log whose entry pattern matches nothing fails its premise" "$r"

r=""
r="$r$(wantrc "$rc_n1" 2)"
r="$r$(want "$OUT/n1.txt" 'PROBE FAILED: --cap and --tail must be zero or more')"
r="$r$(wantrc "$rc_n2" 2)"
r="$r$(want "$OUT/n2.txt" 'PROBE FAILED: --cap and --tail must be zero or more')"
leg "37 a negative cap or tail is refused, never silently truncated or crashed into" "$r"

r=""
r="$r$(wantrc "$rc_s4" 0)"
r="$r$(want "$OUT/s4.txt" 'tag-control: fired')"
r="$r$(want "$OUT/s4.txt" 'hardwrap-control: fired')"
r="$r$(want "$OUT/s4.txt" 'narrative-control: fired')"
r="$r$(notwant "$OUT/s4.txt" 'PROBE FAILED')"
leg "38 a caller phrase carrying an angle-bracket token cannot break the tag control" "$r"

r=""
r="$r$(wantrc "$rc_p4" 0)"
r="$r$(want "$OUT/p4.txt" 'agents n/a (no directory)')"
r="$r$(want "$OUT/p4.txt" 'agents n/a (no .claude/agents directory)')"
r="$r$(notwant "$OUT/p4.txt" 'PROBE FAILED')"
r="$r$(wantre "$OUT/p4.txt" 'prefix budget: CLAUDE\.md [0-9]+ B')"
r="$r$(wantrc "$rc_p5" 2)"
r="$r$(want "$OUT/p5.txt" 'PROBE FAILED: CLAUDE.md is absent')"
leg "39 an absent agents directory is n/a at exit 0; an absent CLAUDE.md still fails" "$r"

r=""
r="$r$(wantrc "$rc_p6" 2)"
r="$r$(want "$OUT/p6.txt" 'PROBE FAILED: README')"
r="$r$(want "$OUT/p6.txt" 'does not begin with a frontmatter block')"
r="$r$(want "$OUT/p6.txt" 'could not be read (IsADirectoryError)')"
r="$r$(notwant "$OUT/p6.txt" 'README 1')"
r="$r$(want "$OUT/p6.txt" 'agents measured=1 of 3 candidates')"
leg "40 body rules are never a phantom frontmatter layer; a directory named .md never crashes" "$r"

r=""
r="$r$(wantrc "$rc_p7" 2)"
r="$r$(want "$OUT/p7.txt" 'PROBE FAILED: --diff-log wiki/absent-log.md does not exist')"
r="$r$(want "$OUT/p7.txt" 'no delta computed')"
leg "41 --diff-log pointing at nothing is a premise failure, never a silent no-change" "$r"

r=""
r="$r$(wantrc "$rc_e3" 0)"
if ! "$PY" - "$OUT/e3.txt" <<'JSON_CHECK_END'
import json, sys
d = json.load(open(sys.argv[1]))
diag = d["orphans"]["diagnostic_only"]
assert "not a finding" in diag["note"], diag["note"]
assert isinstance(diag["orphans_excluding_index_as_source"], list)
assert "strict_orphans" not in d["orphans"], "the unlabelled key is still there"
assert d["orphans"]["orphans"] == ["wiki/benchmarks/BrowseComp-Plus.md",
                                   "wiki/sources/browsecomp-plus.md"], d["orphans"]["orphans"]
assert d["index"]["shared_stems"] == ["browsecomp-plus"], d["index"]["shared_stems"]
assert d["log"]["has_entries"] is True
JSON_CHECK_END
then
  r="$r json diagnostic labelling or payload did not match;"
fi
leg "42 the index-excluded orphan figure is labelled information in JSON, not a finding" "$r"

r=""
r="$r$(want "$E1" 'source_url pages: 2 · mutable 1 · immutable 1')"
r="$r$(want "$E1" 'https://example.com/a-living-page')"
r="$r$(notwant "$E1" 'semanticscholar')"
leg "43 a Semantic Scholar URL counts as immutable and never becomes a freshness probe" "$r"

rc_s5=$(run s5.txt "$PY" "$SWEEPS" --vault "$EV" --format json)
rc_p8=$(run p8.txt "$PY" "$PREFIX" --vault "$PV" --format json)
r=""
r="$r$(wantrc "$rc_s5" 0)"
r="$r$(wantrc "$rc_p8" 0)"
if ! "$PY" - "$OUT/s5.txt" "$OUT/p8.txt" <<'JSON_CHECK_END'
import json, sys
s = json.load(open(sys.argv[1]))
assert s["controls"]["hardwrap"] and s["controls"]["raw_tag"] and s["controls"]["narrative"], s["controls"]
assert s["pages_scanned"] == 11, s["pages_scanned"]      # 12 pages, log.md excluded by path
assert s["rendered_lines"] > 0, s["rendered_lines"]
assert s["hardwrap"]["hits"] == 1 and len(s["raw_tags"]["hits"]) == 1
assert s["probe_failures"] == []
p = json.load(open(sys.argv[2]))
assert p["agents"]["present"] is True and p["agents"]["candidates"] == 1, p["agents"]
assert p["skills"]["candidates"] == 2 and p["skills"]["count"] == 2, p["skills"]
assert p["mcp"]["declared"] == 1 and p["probe_failures"] == []
assert p["budget_line"].startswith("prefix budget: CLAUDE.md ")
JSON_CHECK_END
then
  r="$r a json payload did not parse or did not carry its controls and scope;"
fi
leg "44 every script's json payload parses and carries its controls and its scope counts" "$r"

# A page the scan cannot open must never be skipped in silence: it is a hole in every count. A
# dangling symlink reproduces that without depending on file permissions or on who runs the suite.
UR="$TMP/unreadable"
cp -R "$EV" "$UR"
ln -s does-not-exist.md "$UR/wiki/concepts/Dangling.md"
rc_u1=$(run u1.txt "$PY" "$AUDIT" --vault "$UR" --today 2026-09-02)
rc_u2=$(run u2.txt "$PY" "$SWEEPS" --vault "$UR")
r=""
r="$r$(wantrc "$rc_u1" 2)"
r="$r$(want "$OUT/u1.txt" 'PROBE FAILED: wiki/concepts/Dangling.md could not be read (FileNotFoundError)')"
r="$r$(want "$OUT/u1.txt" 'pages scanned: 12')"
r="$r$(wantrc "$rc_u2" 2)"
r="$r$(want "$OUT/u2.txt" 'PROBE FAILED: wiki/concepts/Dangling.md could not be read (FileNotFoundError)')"
leg "45 a page that cannot be opened is a reported premise failure, never a silent skip" "$r"

# ---------------------------------------------------------------- stdout-only proof
manifest() { # manifest <dir> <outfile>
  { find "$1" | sort; find "$1" -type f -print0 | xargs -0 shasum | sort; } > "$2" 2>&1
}
cp -R "$PV" "$RO"
cp -R "$EV" "$ROE"
chmod -R a-w "$RO" "$ROE"
manifest "$RO" "$OUT/ro_before.txt"
manifest "$ROE" "$OUT/roe_before.txt"
manifest "$HERE" "$OUT/home_before.txt"
"$PY" "$AUDIT" --vault "$RO" --baseline 2026-08-15 --today 2026-09-02 > "$OUT/ro1.txt" 2>&1
rc_ro1=$?
"$PY" "$AUDIT" --vault "$RO" --today 2026-09-02 --format json > "$OUT/ro2.txt" 2>&1
rc_ro2=$?
"$PY" "$SWEEPS" --vault "$RO" > "$OUT/ro3.txt" 2>&1
rc_ro3=$?
"$PY" "$PREFIX" --vault "$RO" --diff-log wiki/log.md > "$OUT/ro4.txt" 2>&1
rc_ro4=$?
"$PY" "$AUDIT" --vault "$ROE" --today 2026-09-02 > "$OUT/ro5.txt" 2>&1
rc_ro5=$?
"$PY" "$SWEEPS" --vault "$ROE" > "$OUT/ro6.txt" 2>&1
rc_ro6=$?
manifest "$RO" "$OUT/ro_after.txt"
manifest "$ROE" "$OUT/roe_after.txt"
manifest "$HERE" "$OUT/home_after.txt"

r=""
r="$r$(wantrc "$rc_ro1" 0)"
r="$r$(wantrc "$rc_ro2" 0)"
r="$r$(wantrc "$rc_ro3" 0)"
r="$r$(wantrc "$rc_ro4" 0)"
r="$r$(wantrc "$rc_ro5" 0)"
r="$r$(wantrc "$rc_ro6" 0)"
if ! cmp -s "$OUT/ro_before.txt" "$OUT/ro_after.txt"; then r="$r the read-only fixture changed;"; fi
if ! cmp -s "$OUT/roe_before.txt" "$OUT/roe_after.txt"; then r="$r the read-only edge fixture changed;"; fi
if ! cmp -s "$OUT/home_before.txt" "$OUT/home_after.txt"; then r="$r the script home changed;"; fi
leg "46 stdout-only: read-only vaults and script home byte-identical after every run" "$r"

WRITE_RE='open\([^)]*"[wax]|open\([^)]*'"'"'[wax]|\.write_text\(|\.writelines\(|os\.(remove|unlink|rename|mkdir|makedirs|rmdir)\(|shutil\.(move|copy|copy2|copytree|rmtree)\(|subprocess\.|tempfile\.'
cat > "$OUT/write_control.py" <<'FIXTURE_END'
import shutil
handle = open("/tmp/control-target", "w")
shutil.copy("/tmp/a", "/tmp/b")
FIXTURE_END
r=""
if ! grep -qE -- "$WRITE_RE" "$OUT/write_control.py"; then
  r="$r the write-pattern grep did not match its positive control;"
fi
for src in "$AUDIT" "$SWEEPS" "$PREFIX"; do
  if grep -qE -- "$WRITE_RE" "$src"; then
    r="$r write pattern in $(basename "$src");"
  fi
done
leg "47 stdout-only: no write pattern in any source (grep control-verified)" "$r"

# ---------------------------------------------------------------- spawn-record review (2026-09-06)
SRR="$HERE/spawn-record-review.py"
RD="$TMP/records"; RJ="$TMP/routing.json"; RL="$TMP/log.md"; mkdir -p "$RD"
cat > "$RJ" <<'RJEOF'
{"schema": 2, "order": {"model": ["haiku","sonnet","opus","fable"], "effort": ["low","medium","high","xhigh","max"]},
 "classes": {"verifier": {"model": {"options": ["sonnet","opus","fable"], "default": "opus"}, "effort": {"options": ["high","xhigh","max"], "default": "max"}},
             "memory-hunter": {"model": {"options": ["sonnet","opus"], "default": "sonnet"}, "effort": {"options": ["high","xhigh","max"], "default": "max"}}}}
RJEOF
printf '%s\n' '## [2026-09-01] deep-lint | fixture' > "$RL"
RF="2026-09-06T12:00+0100"
mk() { # mk <file> <lane> <ts> <model> <effort> <throttle> <reason> [row_default-json|-] [extra-json]
  f="$RD/$1.jsonl"; [ -f "$f" ] || printf '{"ts":"2026-09-06T13:00+0100","run":"%s","event":"run-open","session":"fx"}\n' "$1" > "$f"
  rd=""; [ "${8:-}" != "-" ] && [ -n "${8:-}" ] && rd=",\"row_default\":$8"
  printf '{"ts":"%s","run":"%s","event":"lane-open","lane":"%s","class":"verifier","model":"%s","effort":"%s","throttle":"%s","reason":"%s"%s%s}\n' "$3" "$1" "$2" "$4" "$5" "$6" "$7" "$rd" "${9:-}" >> "$f"; }
RDJ='{"model":"opus","effort":"max"}'
mk r-default  D1 2026-09-06T13:00+0100 sonnet high default "(a) verify leg" "$RDJ"
mk r-phrase   P1 2026-09-06T13:00+0100 sonnet high default "(a) sonnet because closed list; effort high because mechanical" "$RDJ"
mk r-cheap    C1 2026-09-06T13:00+0100 sonnet high cheap "(a) x" '{"model":"sonnet","effort":"high"}'
mk r-cheap    C2 2026-09-06T13:00+0100 opus max cheap "(a) x" '{"model":"sonnet","effort":"high"}'
mk r-fast     F1 2026-09-06T13:00+0100 opus max fast "(a) x" '{"model":"opus","effort":"high"}'
mk r-fast     F2 2026-09-06T13:00+0100 opus high fast "(a) x" '{"model":"opus","effort":"high"}'
mk r-cheapfast CF1 2026-09-06T13:00+0100 sonnet high cheap-fast "(a) x" '{"model":"sonnet","effort":"high"}'
mk r-cheapfast CF2 2026-09-06T13:00+0100 opus xhigh cheap-fast "(a) x" '{"model":"sonnet","effort":"high"}'
mk r-top      T1 2026-09-06T13:00+0100 opus xhigh top "(a) x" '{"model":"fable","effort":"max"}'
mk r-rereso   R1 2026-09-06T13:00+0100 opus max default "(a) x" -
mk r-cut      B1 2026-09-06T11:59+0100 sonnet high default "(a) x" "$RDJ"
mk r-cut      A1 2026-09-06T12:01+0100 sonnet high default "(a) x" "$RDJ"
mk r-letter   L0 2026-09-03T23:00+0100 opus max default "no letter here" "$RDJ"
mk r-letter   L1 2026-09-04T01:00+0100 opus max default "no letter here" "$RDJ"
mk r-ts       Z1 garbage opus max default "(a) x" "$RDJ"
mk r-close    U1 2026-09-06T13:00+0100 opus max default "(a) x" "$RDJ"
mk r-close    N1 2026-09-06T13:00+0100 opus max default "(a) x" "$RDJ"
printf '{"ts":"2026-09-06T13:10+0100","run":"r-close","event":"lane-closed","lane":"N1","effort_applied":null}\n' >> "$RD/r-close.jsonl"
mk r-close    M1 2026-09-06T13:00+0100 opus max default "(a) x" "$RDJ"
printf '{"ts":"2026-09-06T13:10+0100","run":"r-close","event":"lane-closed","lane":"M1","effort_applied":["high"]}\n' >> "$RD/r-close.jsonl"
# The `auto` pick guard (2026-09-08; owner ruling 2026-09-07 17:0x): the anchor opus·xhigh, and a
# departure either way carries its reason in <axis>_src (`auto: …`) or choice_reason.
RDA='{"model":"opus","effort":"xhigh"}'
mk r-auto AR1 2026-09-06T13:00+0100 opus max auto "(a) x" "$RDA" ',"model_src":"anchor","effort_src":"auto: design-heavy","choice_reason":"design-heavy"'
mk r-auto AU1 2026-09-06T13:00+0100 opus max auto "(a) x" "$RDA" ',"model_src":"anchor","effort_src":"anchor","choice_reason":null'
mk r-auto AA1 2026-09-06T13:00+0100 opus xhigh auto "(a) x" "$RDA" ',"model_src":"anchor","effort_src":"anchor","choice_reason":null'
mk r-auto AD1 2026-09-06T13:00+0100 sonnet high auto "(a) x" "$RDA" ',"model_src":"auto: closed one-leg task","effort_src":"auto: closed one-leg task","choice_reason":"closed one-leg task"'
mk r-auto AB1 2026-09-06T13:00+0100 fable max auto "(a) x" "$RDA" ',"model_src":"anchor","effort_src":"anchor","choice_reason":null'
mk r-auto AP1 2026-09-06T13:00+0100 sonnet high auto "(a) x" "$RDA"
printf '%s\n' '{"ts":"2026-09-06T13:00+0100","event":"spawn","lane":"old"}' 'not json' > "$RD/r-norunopen.jsonl"
srr() { $PY "$SRR" --records "$RD" --routing "$RJ" --log "$RL" --rule-from "$RF" "$@" > "$TMP/srr.out" 2>&1; echo $? > "$TMP/srr.rc"; }
srr
leg "srr: default below-default sonnet·high without phrases is caught twice" "$(want "$TMP/srr.out" 'D1: model sonnet below the row default opus')$(want "$TMP/srr.out" 'D1: effort high below the row default max')"
leg "srr: the phrase-present lane passes (the phrase check discriminates)" "$(notwant "$TMP/srr.out" 'FINDING P1')"
leg "srr: cheap at the floor is skipped; above the floor is caught" "$(notwant "$TMP/srr.out" 'FINDING C1')$(want "$TMP/srr.out" "C2: pick above the owner's floor")"
leg "srr: fast above the effort floor is caught; at the floor skipped" "$(want "$TMP/srr.out" "F1: effort above the owner's floor")$(notwant "$TMP/srr.out" 'FINDING F2')"
leg "srr: cheap-fast skips both axes at the floors, catches both above" "$(notwant "$TMP/srr.out" 'FINDING CF1')$(want "$TMP/srr.out" "CF2: pick above the owner's floor")$(want "$TMP/srr.out" "CF2: effort above the owner's floor")"
leg "srr: top flags a pick below the ceiling" "$(want "$TMP/srr.out" 'T1: model opus below the ceiling under top')$(want "$TMP/srr.out" 'T1: effort xhigh below the ceiling under top')"
leg "srr: a line without row_default is re-resolved and labelled" "$(want "$TMP/srr.out" 'R1: re-resolved (no row_default)')$(notwant "$TMP/srr.out" 'FINDING R1')"
leg "srr: the cut: a minute before RULE_FROM is baseline, a minute after is checked" "$(notwant "$TMP/srr.out" 'FINDING B1')$(want "$TMP/srr.out" 'A1: model sonnet below the row default')"
leg "srr: the letter check starts at LETTER_FROM" "$(notwant "$TMP/srr.out" 'FINDING L0')$(want "$TMP/srr.out" 'L1: no instrument-rule letter')"
leg "srr: an unparseable ts is listed" "$(want "$TMP/srr.out" 'Z1: unparsed ts')"
leg "srr: unclosed, unread applied effort and a recorded/applied mismatch are told apart" "$(want "$TMP/srr.out" 'U1: unclosed')$(want "$TMP/srr.out" 'N1: applied effort unread')$(want "$TMP/srr.out" 'M1: effort max recorded, high applied')"
leg "srr: a file without run-open is skipped and its bad lines counted" "$(want "$TMP/srr.out" 'r-norunopen.jsonl: skipped (no run-open, 1 bad lines)')"
leg "srr: auto, a reasoned departure above the anchor (effort_src auto: …) is clean" "$(notwant "$TMP/srr.out" 'FINDING AR1')"
leg "srr: auto, an unreasoned departure is the finding, naming the axis and the anchor" "$(want "$TMP/srr.out" 'FINDING AU1: auto pick without --choice-reason (effort max departs from the anchor xhigh)')"
leg "srr: auto, an anchor pick is clean" "$(notwant "$TMP/srr.out" 'FINDING AA1')"
leg "srr: auto, a reasoned pick BELOW the anchor is clean (the hand-set phrase check does not apply)" "$(notwant "$TMP/srr.out" 'FINDING AD1')"
leg "srr: auto, both axes unreasoned are two findings" "$(want "$TMP/srr.out" 'FINDING AB1: auto pick without --choice-reason (model fable departs from the anchor opus)')$(want "$TMP/srr.out" 'FINDING AB1: auto pick without --choice-reason (effort max departs from the anchor xhigh)')"
leg "srr: a pre-fields auto line (no model_src) keeps the phrase check" "$(want "$TMP/srr.out" 'AP1: model sonnet below the row default opus without')$(notwant "$TMP/srr.out" 'AP1: auto pick')"
srr --since 2099-01-01T00:00+0100
leg "srr: an empty window says so with the file count" "$(want "$TMP/srr.out" 'no lanes this window (control:')"
$PY "$SRR" --records "$TMP/absent-zz" --routing "$RJ" --log "$RL" > "$TMP/srr.out" 2>&1; rc=$?
leg "srr: a missing records directory is PROBE FAILED, exit 2" "$(want "$TMP/srr.out" 'PROBE FAILED')$([ "$rc" -eq 2 ] || printf 'exit %s; ' "$rc")"
$PY "$SRR" --records "$RD" --routing "$TMP/no-routing.json" --log "$RL" > "$TMP/srr.out" 2>&1; rc=$?
leg "srr: an unreadable routing record is PROBE FAILED, exit 2" "$(want "$TMP/srr.out" 'PROBE FAILED')$([ "$rc" -eq 2 ] || printf 'exit %s; ' "$rc")"
RF_SCRIPT=$(grep -o 'RULE_FROM = "[^"]*"' "$SRR" | head -1 | sed 's/.*"\(.*\)"/\1/')
RF_LOG=$(grep -o 'per-call model and effort rule shipped 2026-09-06 [0-9][0-9]:[0-9][0-9]' "$HERE/../../../wiki/log.md" | head -1 | grep -o '[0-9][0-9]:[0-9][0-9]$')
leg "srr: RULE_FROM equals the ship entry's title time in wiki/log.md" "$([ -n "$RF_LOG" ] && [ "${RF_SCRIPT:11:5}" = "$RF_LOG" ] || printf 'script %s vs log %s; ' "$RF_SCRIPT" "$RF_LOG")"

# ---------------------------------------------------------------- teardown
chmod -R u+w "$TMP"
rm -rf "$TMP"

total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  printf 'PASS %d/%d\n' "$pass" "$total"
  exit 0
fi
printf 'FAIL %d/%d\n' "$fail" "$total"
exit 1
