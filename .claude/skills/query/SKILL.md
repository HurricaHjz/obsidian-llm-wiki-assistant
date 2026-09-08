---
name: query
description: >
  Answer questions against the local Obsidian wiki — not from model memory. Use when the user runs
  /query, or asks in natural language about "my notes / my wiki / what I've researched / my past
  decisions / what do I know about X". Always read wiki/index.md FIRST and WHOLE to locate pages, then read
  them in full, then answer with [[wikilink]] citations. If the wiki has nothing relevant, say so
  explicitly before giving any general-knowledge answer. Offers to file high-value answers back
  into wiki/syntheses/ so explorations compound.
user-invocable: true
---

# query — answer from the wiki, with citations

## Goal
Turn a question into a **deep read of the compiled wiki** and a synthesized, **cited** answer.
When the answer is valuable, **file it back** into the wiki so knowledge compounds.

## Triggers
- `/query <question>`
- Natural language: "what do my notes say about X", "what was my past decision on Y", "search my wiki for Z"
- Mentions of: my wiki / my notes / my knowledge base / what I've researched.

## Depth (see CLAUDE.md → Processing depth)
Match answer depth to the question (auto standard/concise; `research` is **opt-in or ask-first, never
silent** — this is query's rule and it is unchanged. `ingest` differs deliberately: it picks each
source's depth after reading and records it, because a batch of forty sources cannot carry forty asks.
One question can.)
**All depths stay token-efficient — `research` permits more depth, never filler.**
- **standard (DEFAULT)** — balanced, cited synthesis.
- **concise** — a tight, direct answer citing only the few key pages.
- **research** — rigorous and exhaustive: exact figures, verbatim quotes with refs, explicit treatment
  of agreements/contradictions across sources, and a short "limitations / gaps" note. Higher accuracy
  bar, still no filler. A filed synthesis uses academic structure + `depth: research`.

## Pipeline

### Step 1 — Read the global index (always first)
Read `wiki/index.md` **whole** — `route` mode, CLAUDE.md §5 — and locate candidate pages across **every**
`## ` section. Do not scope the read to a few sections: the four this step once named (Sources, Entities,
Concepts, Syntheses) hold 79 of the 111 pages real syntheses turned out to cite, so the other six carried
29 % of the answer (wiki/developments/registry-read-policy.md, 2026-09-06). Grepping the index instead of reading it finds
49 % of them.

### Step 2 — Deep-read the targets (triage by confidence)
Open the most relevant pages in full with the read tool (or `obsidian-cli`). Follow `## Related`
links one hop out when it helps. **When candidates are many, first check their `confidence` cheaply
(one `grep "^confidence:" <candidate files>`, frontmatter only) and deep-read `authoritative`/`high`
first; pull in `medium` as needed; consult `low`/`very-low` only to fill gaps.**
**If the catalogue under-covers the question and
qmd is active** (the `qmd-search` skill — dormant unless qmd is installed + enabled), use it as the
semantic fallback (`qmd query "<q>" --json --files`), confidence-rank the hits, then deep-read; otherwise
`grep` as usual.

### Step 3 — Synthesize with citations (weighted by confidence)
- Cite every page you draw from inline as `[[Page Name]]`.
- For a verbatim claim, use a `> blockquote`.
- Don't over-cite: one citation at the start and end of a passage from the same page is enough.
- **Weight by `confidence`:** resolve conflicts toward the higher tier (and, if tied, the newer
  `updated`); state `authoritative`/`high` plainly, but attribute and hedge `low`/`very-low`
  ("a promotional listing claims…", "an unverified transcript suggests…"); never let a `very-low` or
  `unverified` claim harden into an asserted fact. Optionally flag a weak citation inline, e.g.
  `[[X]] *(low-confidence)*` (only for `low`/`very-low`).

### Step 3b — Freshness duty (Tier-2 flags; costs no extra reads)
Judge only the pages you have ALREADY read for this answer — never read extra pages for this duty:
- **Contradiction** (page vs page, or page vs clearly newer evidence just read) → surface it in the
  reply and add/extend the page's `## Conflicts / Open Questions` block (CLAUDE.md §4.4).
- **Staleness suspicion** (old `updated` against newer in-wiki evidence; a superseded claim) → one
  line in the reply + offer the fix now; if not fixed on the spot, record it on the page as
  frontmatter `flagged: YYYY-MM-DD <one-phrase reason>` so `/deep-lint` reconciles it later.
- Flags are annotations, not logged ops — the reconciling `deep-lint` run logs their resolution.
  (Design: `wiki/developments/deeplint-scalable-maintenance-design.md`.)
- **The freshness line — a completion gate.** Every reply that read wiki pages ends with one line,
  whatever the active style:
  `Freshness: <N> pages read · oldest [[page]] (updated YYYY-MM-DD) · <k> flagged`
  (`k` = flags placed or staleness fixes made this run; usually 0). The answer is **not done** until
  the line has appeared — duties fire when they gate the done-declaration (measured 88% gated vs 4%
  ungated: `wiki/developments/ingest-auto-mode-design.md`). Naming the oldest page is the locator —
  the line cannot be written without looking at the `updated:` dates already in hand. A reply that
  read no wiki pages (general-knowledge fallback) skips the line and says so.

### Step 4 — Degrade gracefully (two cases, never a bare refusal)
- **No coverage** — if `index.md` has nothing relevant and the question is general knowledge, say so first:
  > Nothing in the local wiki covers this — answering from general knowledge:
  …then answer. Never silently pretend the wiki had the answer.
- **Only low-confidence coverage** — if the wiki *does* cover it but only at `low`/`very-low`, **still
  give the substantive answer from those pages**, opening with an explicit warning, e.g.:
  > ⚠ Low-confidence: the only sources here are a promo listing and an auto-transcript — treat as provisional.
  Never refuse with a bare "I don't know".

### Step 4b — Gap proposal (propose-only; CLAUDE.md §6)
When Step 4 declared missing or weak coverage, a gather proposal MAY follow the answer — never
replace it — if ALL four hold: the gap is **evidenced** by the search just run (the brief cites what
was searched — a zero-findings claim carries its probe, CLAUDE.md §11); **load-bearing** for the core
of the task (answerable-but-`low` coverage stays a warning, not a proposal); plausibly **fixable by
public web sources** (not owner-only knowledge); and **not explicitly declined** this session. At
most ONE proposal per reply, surfaced whatever the active style, formatted why (gap + evidence) ·
what (source kinds, rough count) · how (the literal `/gather` command with its page budget — never
`--yes`) · cost. Only the owner's explicit yes runs it — that run-spec only; gather's own gates
unchanged. Consent ledger: explicit **no** → dead this session (a one-line gap note at most) ·
**unaddressed** → one compact reminder while the task is live, then quiet (a later re-fire on a new
task references the earlier brief in one line, never a full re-brief) · **"later"** → one re-offer at
the natural point. Non-interactive runs never propose — state the gap in the report.
(Design: `wiki/developments/agent-initiated-gather-design.md`.)

### Step 5 — File high-value answers back
If the answer is more than ~2 paragraphs or is comparative/analytical, ask:
> This looks worth keeping — save it to `wiki/syntheses/`?

On yes, create `wiki/syntheses/<slug>.md` (kebab-case) with synthesis frontmatter, a
`## Sources Used` section listing every cited `[[page]]`, and register it under **Syntheses** in `index.md`.
Give it a **conservative inherited `confidence`** (a synthesis *defaults* to `medium` as agent-derived and *caps* at `high`, per §4.6; drop to
`low` if it rests mainly on `low` sources); never crystallise a `low`/`unverified` claim as asserted fact.
**Report the filed page and its `confidence`** to the user — every newly added wiki file states its level
(as `ingest` Step 8 does), so you can review and re-grade it. **Refresh on write:** the new page's qmd
embedding refreshes per the `qmd-search` contract — a turn-end hook where installed, inline only where not;
a no-op when qmd is dormant.

### Step 6 — Log it (only if you filed a synthesis)
**A pure inline answer is NOT logged** — logging is for brain-updating ops only (see CLAUDE.md §5).
**Only if Step 5 actually filed a synthesis**, append:
```markdown
## [YYYY-MM-DD] synthesis | <short question>
- **Output**: filed [[synthesis-slug]]; updated [[index.md]]
```
Log a no-synthesis (inline-only) query **only if the user explicitly asks**.

## Hard constraints
- **Never answer substantive questions from memory** — read the wiki first.
- **Never** silently answer when the wiki lacks coverage — declare it.
- **Use `confidence`** to triage, weight and hedge; on only-`low` coverage, answer *with a warning*, never a bare refusal.
- **The freshness line is a completion gate** (Step 3b) — every reply that read wiki pages carries it; no done-declaration without it.
- Output in **British/UK English** with real `[[wikilink]]` citations.
