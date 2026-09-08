---
name: gather
description: >
  Web capture into raw/, two modes, one pipeline. SEED mode: given URL(s), fetch them and (optionally)
  the relevant links they cite. SEARCH mode: given a topic and no URL, web-search it, triage the hits,
  and present a dated shortlist for approval before anything is fetched — the vault's native
  deep-research entry (topic → sources → wiki; the cited report then comes from ingest + query/output).
  Use on /gather, "gather sources on <topic>", "search the web for X and save the sources",
  "deep-capture these links", "grab this article AND the repos/papers it cites". Preview-and-approve
  gates by default; conservative caps + a hard 100-page ceiling; expert flags (--search/--seed,
  --expand, --focus, --rounds, --max-pages, --include/--exclude, --same-domain, --yes, --ingest).
  Big budgets flow through a ranked policy gate (--shortlist, --queries tune the funnel); a
  per-run ledger plus a scripted sole write path harden caps, raw immutability and provenance.
  Opt-in; does nothing until invoked. It only CAPTURES into raw/ — /ingest compiles. Writes only new
  raw files, their asset images and its own log entry (never edits existing raw content).
user-invocable: true
---

# gather — web capture into raw/ (seed mode + search mode)

## Goal
Turn either a set of links (seed mode) or a bare topic (search mode) into a high-quality set of
captured sources in `raw/`, without fan-out blow-ups, off-topic noise, or silent writes. `/ingest`
then compiles. Capture is document-granular — whole pages, verbatim; salience is ingest's job.

**The whole logic in three lines** (single-letter symbols live in the scripts):
- **Two inputs**: the owner's page budget, and the topic's uncovered sub-questions (round 1: the
  brief's facets; later rounds: the open gaps — same thing, next moment).
- **One funnel**: search wide → rank a pool → show a menu → the owner approves → capture.
- **Three principles**: numbers bound, never oblige (every cap is a cap, not a quota); nothing is
  written without the owner's yes, and noes outlive yeses (drops persist, rules don't); judgement
  declares itself, arithmetic is scripted (the agent states sub-questions/relevance/advice, the
  scripts derive and print every number).

**How to read this skill.** The CONTROL ENVELOPE is rigid — a smarter model obeys it identically.
Procedure (how to phrase queries, rank, scope) is stated as goal + reason under JUDGEMENT &
RATIONALE and applied with judgement — better models make better choices there. Judgement governs
HOW a rationale entry is satisfied, never WHETHER: the imperative duties inside those entries
(SAY SO · EVERY · STOP · never) bind exactly like the envelope. The CAPABILITY CATALOG lists
every lever; a lever you don't know exists is one you can't reach for.

## Modes & routing (deterministic — any agent, any model, same result)
- ≥1 URL among the arguments → **seed mode**. Free text alongside = scope + focus.
- No URL, a topic/question present → **search mode**. The text is the **brief**: goal, any
  include/exclude criteria, recency expectations.
- Explicit `--seed` / `--search "<brief>"` overrides inference. Neither URL nor topic — or `--seed`
  with no URL — → **ask**. Out-of-range flag values are clamped to their bounds, the clamp reported
  at the gate. NL intent maps to flags (*"two hops, only papers"* → `--expand 2 --include
  arxiv,doi,/paper`; *"only the parts about X"* → `--focus "X"`; *"show me 10"* → `--shortlist
  10`); unstated → the defaults in Flags.
- **Thin-brief clarify (search mode)**: a brief too thin to plan from — fewer than two derivable
  sub-questions, or scope/recency/depth genuinely ambiguous — gets up to THREE pointed questions
  ONCE, before any discovery spend; otherwise unstated choices become assumptions stated in the
  run-spec echo, and the gate stays the correction point. Never re-interrogate a brief that already
  answers them; the clarify OUTRANKS the survey probe (owner answers first, the probe serves
  residual unfamiliarity, never an unanswered clarify).

## Flags
`--search "<brief>"` · `--seed` · `--expand N` — citation hops beyond the fetched base (default:
seed 1 · search 0; no fixed clamp — the page caps bound it; `--max-depth` accepted as a legacy
alias; link **hops**, unrelated to ingest's compile depth) · `--focus "<topic>"` — semantic
relevance filter (implied by the brief in search mode) · `--rounds N` — search-mode iterative
deepening (default 1, max 3) · `--max-pages N` (default 10; hard ceiling 100) · `--shortlist N` —
full-detail rows at the Discover gate (search mode; default min(12, remaining budget); clamp ≤20) ·
`--queries N` — search queries per round (search mode; default 2 per brief facet within 3–12;
clamp ≤12) · `--same-domain` · `--include a,b` / `--exclude c,d` (seed mode: URL substring
patterns for the classifier · search mode: domain names for the search engine, non-domain patterns
applied as substring post-filters) · `--yes` (skip the Step-4 previews and the seed `--expand 0`
batch preview — the Discover gate always waits) · `--ingest` (compile after capturing) ·
`--no-ledger` (bookkeeping continues in full — write path, gates, rounds, so anti-repeat keeps its
data; only cross-round AUTHORITY is off, numbers quoted from the transcript instead; authority is
otherwise auto-on when `--rounds > 1` or budget ≥ 30).

## Capability catalog (complete — every lever, none prescribed)
**Scripts** (`.claude/skills/gather/`; arithmetic and enforcement live here, never re-derived in
prose):
- `funnel_knobs.py --max-pages N --facets F [--shortlist N] [--queries N] [--pages-captured N |
  --ledger-id ID] [--advice N] [--date-window] [--json]` — derives and prints every funnel number
  for a round: queries band, menu, pool, date-check policy, clamps, budget warnings.
- `gather_links.py <seed.md> --seed-url "<url>" --max-pages N [--same-domain] [--include a,b]
  [--exclude c,d] --json` — the link classifier: returns `expand` / `maybe` / `skip` with the page
  caps pre-applied. Heuristics live in the script (docs/papers/repos/READMEs expand; nav/ads/
  login/social skip; a skip-path hit on the seed's OWN documentation-shaped host demotes to
  `maybe`, so a docs login *guide* reaches the owner while a commercial login *wall* stays out).
- `capture_write.py` — three verbs. `write --url U --engine E --ledger-id ID [--title T]
  < fetched.md`: the SOLE write path (budget + ceiling enforced against the ledger, refuses
  existing paths, sanitises, stamps provenance frontmatter, appends to the ledger, runs the
  capture quality gate; `--allow-degraded '<why>'` for a declared acceptance). `check`: the
  quality gate alone on stdin — pre-write probe, no write, no
  ledger. `dedup --urls u1,u2 --control <known-present URL>`: vault de-dup over
  `source_url`/`converted_from` across `raw/` + `wiki/` (candidates comma- or
  whitespace-separated; the control URL must hit or the scan aborts — proof the probe ran,
  CLAUDE.md §11; `--allow-no-control` only for a provably fresh vault, declared).
- `run_ledger.py` — `init --id <run-id> --budget N` · `add-gate` · `add-drop` · `add-round` ·
  `raise-budget --id ID --to N --reason '<why>'` (the audited budget-raise path; `init --force`
  is for genuine restarts only and refuses once the ledger records any state).
- `repo_pack.py` — repo study: `clone` a shallow sha-pinned working copy into
  `~/.llm-wiki/repos/` (outside the vault, disposable), select paths AFTER reading, then
  `pack-and-write` one immutable commit-pinned pack through capture_write (exit-verified,
  never a pipe; caps + fence escalation in the script; contract:
  `wiki/developments/repo-pack-design.md`; since 2026-09-07 also the project store's snapshot path:
  `--repo` takes an absolute working-copy path, a dirty tree or a credential-bearing remote is refused,
  `--allow-large` lifts the per-file cut, see `wiki/developments/project-store-design.md` D4). The resolved file list with byte totals is the
  consent gate for a pack, and its cost line uses actual pack bytes/4, not the per-page default.

**Capture chain** (type-routed, then fallback — same as ingest Step 0, carve-out included): `defuddle`
for web pages · **arXiv HTML / LaTeXML pages** (`arxiv.org/html/…`, ar5iv) never through defuddle —
`curl -sL` the page to a temp file, then convert with `python3 -m markitdown`, exactly as ingest Step 0
routes them, because defuddle's Markdown converter crashes on LaTeXML and silently emits raw HTML ·
`curl` for raw/`.md` URLs · `markitdown` for binaries (PDF, Office, …) · repo study →
`repo_pack.py` (see Scripts) · **Jina Reader** as the
fallback when the routed engine fails (third-party routing — consented via the preflight, see the
envelope).

**Discovery engines & probes** (discovery informs the gate; only capture writes):
- **WebSearch** per derived query, `--include`/`--exclude` mapped to allowed/blocked domains.
  Results are US-region — say so when the topic suggests non-US sources (those may need direct
  URLs or the platform engines below).
- **Platform tier** (only when `.agent-reach-on` enables it; venv-only binaries — invoke via
  `~/.agent-reach-venv/bin/<cmd>`, incl. `yt-dlp`, never a guessed path; declare the tier with
  `doctor --json`, venv on PATH): `bili search "<q>" --type video -n 5` (Bilibili) · the V2EX public API · RSS/Atom feeds
  via the tier-1 feedparser channel (`~/.agent-reach-venv/bin/python3 -c "import feedparser; …"`;
  blog/newsletter coverage). Hits are triaged identically, metadata-only.
  Default X/Reddit posture (tier 3 inactive): login-walled — locate posts via WebSearch, read via
  the tier-1 Jina channel. A 0-result or auth failure on ANY platform engine is an engine failure:
  report it, never a blank capture. Tier-3 governance:
  `wiki/developments/agent-reach-adoption-design.md`.
- **Bounded pre-consent probes**, each declared at the gate it feeds: ≤6 throwaway WebFetch date
  checks per round on unclear finalists (never a capture path; unknown → mark "date unverified") ·
  ≤2 locate probes per round (a `gh` search, an arXiv listing lookup — when search returns only
  secondary coverage of a known primary artefact; discovery only) · ≤1 survey probe per run (one
  overview-shaped query whose result structure informs the sub-question list itself — perspective
  discovery for weak topic familiarity) · the seed host inventory probe (see rationale; one
  `curl` of `sitemap.xml`, falling back to `/llms.txt`).

## Control envelope (rigid — never relaxes, whatever the model)
**Consent.** Nothing is written before the owner's yes. Preview-and-confirm is the default; only
`--yes` skips the Step-4 previews and the seed `--expand 0` batch preview — the search Discover
gate ALWAYS waits, even with `--yes`: discovered pages are unknowns and always get human curation.
An agent gap proposal (CLAUDE.md §6 — propose-only) becomes a run ONLY on the owner's explicit
yes; the consent covers the echoed run-spec alone; the agent never self-adds `--yes`. Under
delegation the same flow binds every agent, with three admission conditions — novelty verified
against the vault, essentiality for the live or a named future task, strong-agent judgement
(delegate skill §5, owner ruling 2026-08-29). The engine
preflight verifies the capture chain and declares any substitution UP FRONT ("defuddle absent →
Jina fallback") — third-party routing is consented before capture, never reported after.
**Approval semantics (pinned).** A bare "approve" captures the MENU ONLY (the gate's prompt line
says so; if an explicit `--shortlist` made the menu exceed the remaining budget, it captures the
menu's top rows up to the budget, clamp reported). More takes a rule ("top N by relevance" — N
beyond the remaining budget is clamped and reported), a rule plus curation ("top 25, drop 9, add
31"), or row-by-row choices. An ambiguous rule is asked back, never guessed. Before capturing,
echo the RESOLVED set in one line (rows · count · cost) and record it in the ledger. A rule NEVER
carries across rounds — each round's gate is fresh ("same rule" must be said); an explicit DROP
persists — out of every later menu and rule resolution this run, re-listed only among the drops
("dropped at round 1") if re-surfaced, re-entering only when named explicitly.
**Caps.** `--max-pages` (default 10) and the non-overridable **100-page ceiling**, cumulative
across rounds and hops — each repeat classifier invocation gets the REMAINING budget. Caps bound,
never oblige. **No silent caps**: every cap hit, clamp, drop, demotion, dedup and pool underfill
is reported at a gate with its reason. A budget raise is a mid-run constraint change — full
run-spec re-echo — and runs `run_ledger.py raise-budget` (ledger-audited; next round's funnel
reads the raised budget), NEVER `init --force`.
**Ledger.** Every run inits one; the write path requires it — a capture with a missing ledger is
STOP-and-ask, the declared repair a fresh `init` carrying the known state. Cross-round AUTHORITY
(feeding `funnel_knobs.py --ledger-id`, the mismatch rule, resume) engages when `--rounds > 1` or
budget ≥ 30, unless `--no-ledger`. The ledger is evidence, never authority over the owner: any
ledger-versus-memory mismatch → STOP and ask; if the file goes missing mid-run, fall back to model
memory for DISCOVERY accounting only and DECLARE the fallback at the next gate.
**Writes.** `capture_write.py` is the sole write path — raw immutability is mechanical (it refuses
existing paths; never edit or delete existing raw bytes; only *add* new captures, CLAUDE.md §3.1's
"converted `.md`" provision). If the script is missing or broken, STOP and ask — never hand-write
a capture around it. Every capture carries full provenance frontmatter
(`converted_from`/`converted_by`/`converted_on` + `source_url`, keeping ingest's de-dup working).
Download body images to `assets/` with relative paths. The **capture quality gate** (mechanical,
in the script) refuses unwritten: engine error stubs, Page-Not-Found shells, HTML-dominant bodies
(a crashed converter emitting markup), near-empty pages. Platform captures (tier-3 CLIs) pipe the
CLI's output VERBATIM inside a closed fenced block under a one-line header — the gate honours the
fence (fenced payloads sit outside the HTML heuristic; the sanitiser leaves them byte-exact) but
refuses a dominant fence that is a JSON error/empty payload or a served HTML page (a login wall),
and bare unfenced whole-body JSON. Treat any refusal as that engine failing and retry with the
next engine in the chain. A body you deliberately accept needs `--allow-degraded '<why>'` —
stamped into frontmatter + ledger and declared in the run report.
**Reporting duties (gate content = informed consent — exact duties, never paraphrased away).**
Every run echoes its parsed **run-spec** at the first gate (mode · seeds/brief · focus · expand ·
rounds · caps; search mode adds the brief's facet list, the declared provenance ranking frame,
every declared probe/engine/assumption, and the `funnel_knobs.py` block echoed VERBATIM, clamps
included — re-run with `--advice N` once triage has the count). A mid-run constraint change (caps,
date window, focus, mode — at an open gate or between rounds) re-echoes the FULL updated run-spec,
never just the changed value. The Discover gate prints the LITERAL queries run. Menu rows are NUMBERED (rules and curation
address rows by number) and carry: title · provenance class (·×k multiplicity where >1) · date (✓ = page-verified) · one-line
relevance · likely raw/ subfolder (informational — capture writes to the raw/ root; ingest
sorts). A **coverage table** (per sub-question: covered by which rows · still open) appears at
every gate and again at hand-off — approval is informed by what it buys AND what it leaves open.
The **advice line** states the judged worth-capturing count ("of the <pool> ranked, ~N look
genuinely worth capturing", echoed via `--advice`); advice widens what is SHOWN, never what a rule
may buy. The **ranked remainder** (one-liners: rank · title · provenance · date · relevance)
appears when the remaining budget OR the advice count exceeds the menu, rows beyond the remaining
budget carrying the block's raise marker (rules always cap at the remaining budget; capturing a
marked row needs an explicit budget raise); otherwise below-cutoff candidates are summarised in one
line ("+K ranked below — say 'show all'"), never silently dropped. Every dropped or deduped
candidate is listed with its reason. Every gate/preview shows the page count and a **cost
estimate** (assume ≈4k tokens per captured page + ≈2× that to compile, and state the assumption;
when the remainder is shown, price a full-budget rule too) and ends with ONE short
**recommendation** line — at a gate, the option the agent judges best and the trim it would make
("Recommend: approve all 20; drop rows 4/7 if trimming"); at hand-off, the next step. Advisory
only — it never self-executes.
**Capture discipline.** Capture, don't summarise: the chain captures verbatim; WebFetch is
triage-only (throwaway date checks) — NEVER a capture path. Never fill gaps with invented
content; mark anything uncertain `unverified`. A page whose whole chain fails (Jina included) is
reported — URL, engines tried — and its slot is never auto-backfilled from the remainder; offer a
follow-up rule or round instead (the date-window discard rule, mirrored). WebSearch unavailable →
say so and ask for seed URLs — never substitute model memory. Zero hits → print the queries run
(proof the probe ran) and offer reformulations.
**Privacy & language.** Skip anything behind a login or obviously private.
The Jina fallback routes URLs through a third party — don't use it for sensitive links. UK
English at COMPILE time, not capture time: non-English pages are captured VERBATIM in their
source language (raw/ is immutable evidence — CLAUDE.md §3.1); `/ingest` translates. Note the
source language in the gate row when known. Don't compile here — that's `/ingest`'s job.
**Logging.** After a completed capture run, append ONE `gather` entry to `wiki/log.md` via shell
(`cat >>`): mode, seed URL(s) or the brief + the queries run (and rounds), any policy rule
approved at the gate, pages captured, where they landed in `raw/`, and that the batch awaits
`/ingest`. A preview-only or aborted run (nothing captured) is not logged. The run ledger
(`/tmp/gather-run-<id>.json`) may then be deleted — run-scoped scratch, never knowledge.

## Judgement & rationale (procedure as goal + reason — judgement chooses the HOW, never the
WHETHER; every entry was bought by a live run)
- **Query craft.** Goal: cover every sub-question, wide before narrow — unguided agents
  over-narrow. Derive per sub-question one WIDE and one NARROW phrasing by default; across the
  set cover the applicable expansion axes: terminology shift · entity-anchored (named
  systems/people/orgs) · temporal (recency terms where freshness matters) · provenance-targeted
  (phrasing that surfaces the source class sought). Add native-language queries when the topic's
  primary literature is non-English (capture stays verbatim; ingest translates, §3.1). When the
  scripted band overrides two-per-facet (floor 3 · cap 12), the band wins: keep every
  sub-question represented first, then trim narrow variants. Round ≥2 queries narrow onto the
  open gaps. The pool holds the top candidates by triage score up to the scripted pool value — a
  cap, not a quota; underfill is reported with `--queries`/`--rounds` suggested.
- **Triage & ranking.** Metadata-only — no capture fetches at discovery; capture is what the
  owner consents to. Dedupe by URL, recording ×k multiplicity (a URL surfaced by k>1 distinct
  queries) as a declared centrality signal, not a verdict. Source trust is objective-relative, so
  declare the **provenance ranking frame** chosen for THIS brief ("operational how-to → official
  docs first"; "landscape scan → engineering blogs first") and rank under it — the frame is
  declared, never implicit. Classify provenance (official docs / paper / repo / engineering blog
  / news / aggregator); score relevance against the brief. Drop junk (listicles, undated
  marketing, off-topic) — every drop with its reason, per the envelope.
- **Date windows & liveness.** A **hard date window** is an explicit user-stated cutoff
  ("2026-04 onwards", "last three months") — a mere freshness preference ("recent work") is NOT
  one. Under a hard window, EVERY menu row is date-verified pre-gate (the overrun past the ≤6
  baseline declared at the gate) and rule-selected below-menu rows are date-checked at capture;
  out-of-window pages are discarded unwritten, the spent fetch reported, the shortfall never
  auto-backfilled — offer a follow-up rule or round. An UNDATED living surface (an active repo's
  files, a vendor docs page) may pass the window on liveness evidence named in its row —
  host/repo activity (e.g. `pushed_at`) inside the window — while dated artefacts (posts,
  announcements) pass only on publication date (precedent: the 2026-08-25 harness run).
  **Backend-pain warn**: when a hard window forces ≥8 in-window verifications in one run, or the
  run's own row/drop reasons record region- or language-skew for the topic, SAY SO at the gate
  and note that an opt-in agent-grade search backend (API-side date/domain filters:
  Exa/Tavily/Brave) is the designed, deliberately deferred remedy — surfacing the option is the
  duty; adopting it is the owner's call, never the run's. This warn is the deferred backend upgrade's live trigger (an IDEAS queue item) and
  must never rot out of the gate.
- **Seed inventory.** Extraction strips site navigation, so a documentation host's structure
  never reaches the classifier through body links alone. When the seed host serves
  `sitemap.xml`, fetch it as a declared discovery-only probe (one `curl`, never a capture path)
  and put BOTH counts in the run-spec echo ("13 linked from the seed body · 97 on the host
  sitemap"); a missing, redirected, index-style or HTML-serving sitemap falls back to ONE
  further declared probe of `/llms.txt` (docs hosts increasingly serve it; precedent:
  developers.openai.com, 2026-08-25); only when both are absent or empty does the probe degrade
  to link-only discovery, the degradation STATED at the preview — it never aborts the run and
  never fabricates an inventory. The sitemap's focus-relevant pages reach the preview as
  `maybe`s, owner-curated; promotions count against the caps.
- **Rounds & gaps.** From the round's captured material, list the brief's open gaps — derived
  from what was already read, no re-reads. No gaps → stop early and say so. The gap list IS the
  next round's facet list (printed at its gate) and gap-derived queries follow the same craft
  (2 per gap, within the band). **Anti-repeat, ledgered**: previously-issued queries are
  excluded from the new derivation ("excluded k repeat queries" reported at the gate), and a
  candidate already shown at an earlier gate this run returns annotated ("shown round n — not
  selected"), never presented as new — the dropped-row rule's softer sibling: drops stay OUT,
  passed-over rows return labelled. Every knob recomputes from the REMAINING budget, so later
  rounds shrink naturally; every round gets the same gate under the same semantics.
- **Engine health.** When a formerly-working engine fails on ordinary pages (rot, not a
  one-off), the run report says so; after the run, the engine's class-rule upgrade may apply
  automatically under the trusted-release criteria
  (`wiki/developments/agent-reach-adoption-design.md`), reported from → to — never mid-run, and
  never for a release failing the criteria (those are reported for the owner).

## Pipeline (the funnel — order and gates; duties above)
### 0 — Scope (both modes)
Parse args + natural language into the run-spec (defaults from Flags). Run the **engine
preflight** and declare substitutions and the platform tier (per the envelope). Init the **run
ledger**: `python3 .claude/skills/gather/run_ledger.py init --id <run-id> --budget <N>`.
### 1 — Discover (search mode only)
1.1 State the brief's facets; run `funnel_knobs.py` (block echoed verbatim at the gate; re-run
    with `--advice` after triage); one declared survey probe if familiarity is weak (the
    thin-brief clarify outranks it); declare the provenance frame; derive queries per the craft
    rationale; run WebSearch — plus any enabled platform engines, each named in the run-spec
    echo — into the pool.
1.2 Triage on result metadata (multiplicity, provenance, relevance, dates — the hard-window
    policy and the backend-pain warn live in the rationale); state the advice count.
    **Routing (parity gate G5, 2026-09-02 — `wiki/developments/fable-minimising-routing.md`):** *(applies under the `multi` regime, owner-set or head-resolved for the run under delegation `auto`; in `single` the head runs the step itself unless an instrument-rule reason holds — thin-lanes phase 4, 2026-09-04; delegation `auto` 2026-09-04)* the metadata triage runs in a read-only `verifier`-shaped lane on opus, blind to any expected shortlist, handed the pool WITH each hit's title, snippet, date and URL (a bare-URL pool loses exactly the signal-less rows, the gate's one caveat), the brief's facets, the declared provenance frame and the budget; it returns keep (ranked, one-line ground each), drop (ground each), anomalies (pool contamination, unverifiable rows, disclosed model priors) and its controls. The head reviews the lists, runs 1.3 and presents the Discover gate itself (1.4): the owner-facing step never routes. Gate evidence: two blind lanes kept every must-keep and no decoy.
1.3 Vault de-dup pre-check: `capture_write.py dedup --urls … --control <known-present URL>`;
    matches shown as "already in vault", never proposed.
1.4 Present the **Discover gate** (contents per the envelope's reporting duties; never skipped,
    even with `--yes`). Approval per the pinned semantics; record it in the ledger (`add-gate`;
    every explicit drop → `add-drop`; the round's literal queries + shown rows → `add-round`,
    "shown" = every row printed at this gate, menu and displayed remainder alike — feeding
    Step 6's anti-repeat). With `--expand 0` (the search default) this approval IS the capture
    approval → approved rows go straight to Step 5. With `--expand ≥ 1`, approved rows enter
    Steps 2–4 as seeds AND are captured at Step 5.
### 2 — Fetch the seed(s)
Capture each seed with the type-routed chain; save the seed Markdown to a temp file OUTSIDE the
vault (e.g. `/tmp` — not a vault write) for Step 3. Run the **host inventory probe** (per the
rationale). Base pages (seeds, or search-mode approved rows) are themselves captures: written at
Step 5, counted against the caps. Seed `--expand 0` skips Steps 3–4 — the given URLs are the
whole capture set (batch-capture shorthand), previewed ONCE with the cost estimate BEFORE
anything is fetched (unless `--yes`); the inventory probe STILL RUNS under `--expand 0` (a
discovery read, not a capture) and its counts join that one batch preview, its sitemap pages
promotable like any `maybe`.
### 3 — Plan (deterministic)
Run `gather_links.py` so every gather applies the SAME rules. The script's output is never
altered; nothing is silently dropped. With `--focus`, a labelled semantic pass runs AFTER the
classifier: each `expand`/`maybe` link annotated for topical fit, demotions proposed — both
verdicts shown side by side at the preview.
### 4 — Preview & confirm (expansion hops — skip only with `--yes`; the `--expand 0` paths carry
their own approval)
Show the plan + cost estimate, headed by the run-spec. The owner approves / prunes / adjusts
caps / reclassifies the `maybe`s and any focus demotions; promotions count against `--max-pages`
— the run never exceeds it. Under `--yes`: the conservative disposition — `maybe`s skipped,
demotions applied.
### 5 — Capture (into raw/)
Fetch each APPROVED link (routed chain → Jina fallback; whole-chain failures and engine rot per
the envelope and rationale). Write every page through `capture_write.py write` — the sole write
path. For `--expand > 1`, repeat Steps 3–5 on the newly captured pages, re-previewing each hop
(unless `--yes`).
### 6 — Rounds (search mode, `--rounds > 1`)
Per the rounds rationale: open gaps → the new facet list → re-enter Step 1, re-running
`funnel_knobs.py` with `--ledger-id <run-id>` (the ledger supplies pages-captured; mismatch →
STOP and ask; authority off → the `--pages-captured` flag, stated). Same gate, same semantics,
cumulative caps; no rule carries over; explicit drops persist.
### 7 — Hand off to ingest
The captures sit in the `raw/` inbox. Offer `/ingest` (or chain with `--ingest`). Report what
was captured, skipped, the running page/cost total, and — search mode — the final coverage table
(sub-questions covered · still open); a facetless seed run reports plan-versus-captured instead.
For a synthesised report, follow with `/query` (filed into the wiki) or `/output` (a
deliverable) — discovery + capture here, reporting there. Then log per the envelope.

## Relationship to the other skills
- **`gather`** → builds the *Raw layer* (search-driven or seed-driven multi-link capture into `raw/`).
- **`ingest`** → *compiles* `raw/` into linked `wiki/` pages (run it after gather).
- **`query` / `output`** → the reporting half of deep research: cited answers/deliverables from
  the compiled pages. gather + ingest + query/output together replace external deep-research tools.

> **Standing derivative**: `output/user-notes/gather-ingest-quick-reference.md` — a change to this skill's user-facing workflow (commands, flags, gates, report shape) updates that note in the same pass (§2 output contract).
