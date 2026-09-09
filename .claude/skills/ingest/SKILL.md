---
name: ingest
description: >
  Compile inbox files in raw/ into the wiki (source + entity/concept/model/benchmark pages), update
  index + log, then sort the raw file into its category subfolder. Use on /ingest, when files are
  dropped into raw/, or "add this to my wiki / ingest this / file this source / process my inbox".
  Non-.md sources (PDF, PPTX, DOCX, XLSX, image, audio, HTML, CSV, EPUB, YouTube/web URL) are
  converted to Markdown first; runs a cheap de-dup check; picks each source's depth
  (concise/standard/research) after reading it, within the run's authorised range, and records the
  choice with its evidence in the report and log. Scans the raw/ ROOT only (or one given path);
  never edits raw file contents — only relocates them.
user-invocable: true
---

# ingest — compile raw sources into the wiki

You maintain a **persistent, compounding wiki** (see `CLAUDE.md`). `raw/` root is the **inbox**;
`wiki/` is the **compiled layer**. Work in **British/UK English**.

## Trigger logic
1. **`/ingest`** (no arg) → list every file in the **`raw/` root only** (exclude all subfolders;
   they are already processed), then process them at the pacing chosen in **Pacing** below.
2. **`/ingest <path>`** → process just that file (or a YouTube/web URL the user gives you).
3. **Implicit** → user says "add this to my wiki" / "ingest this" / "file this source".

## Pacing: auto (default), one-by-one, batch, or parallel
Read the **pacing** from the user's words; **if they don't specify, default to `auto` and decide yourself.**
Do not ask which *pacing* to use unless the choice is genuinely risky. (This is pacing only — **depth**
is a separate axis with its own rules; see Depth. `auto` names a default on both, so never read a
pacing sentence as licence on depth, or a depth rule as licence on pacing.)

- **`auto` (DEFAULT)** — pick the cheapest path that preserves quality:
  - **Batch** in a single pass when the inbox is small (≲5 files), the sources overlap the existing
    wiki, or conflict risk is low.
  - **One-by-one** when there are many diverse/unfamiliar sources, conflict risk is high, or the
    source is long and dense.
  - Either way, **pause immediately** if a genuine knowledge conflict surfaces.
- **`one-by-one`** — user says "one at a time" / "let me review each", or names a single file.
- **`batch`** — user says "all at once" / "batch them" / "do them all".
- **`parallel [N]`** — user says `--parallel` (optionally a lane count), or `auto` proposes it when the
  inbox holds **≥6 independent sources** (threshold set by judgement, unmeasured — recalibrate on batch
  metering; ≤5 stays the small-batch boundary above). **Owner-go gate, knob-invariant:** parallel compile lanes
  are never spawned without the owner's explicit go on the echoed spawn record — the `pre-report` knob
  switches reporting only, never this consent (delegate skill §3 slot 0); a routed single-source lane's
  go is the `/ingest` invocation itself (Routing note, Step 3; 2026-09-03); under the `light` breadth tier
  a fan-out needs an explicit owner ask. Parallel mode is available under **both** delegation modes:
  a batch the head cannot hold in one context is the instrument rule's reason (b), and the verify legs
  of the lanes it spawns are reason (a) (delegate skill §1). Mechanics: **Parallel mode** below.

### Token-efficiency rules (especially in batch — avoid redundant repetition)
- Read each source **once**; never re-read the whole wiki per file.
- Collect entities/concepts across **all** batched sources first, **dedupe**, then create/update each
  shared page **once** — not once per source.
- Update `index.md` and `log.md` **once** at the end of the batch (a single batch `log` entry is fine).
- Skip irrelevant/off-topic source material instead of compiling noise. Don't re-read pages you just wrote.

## Depth (chosen per source AFTER the read, recorded always)
Depth sets how deep/academic the output is (orthogonal to Pacing). **Decide each source's depth once you
have read it — never from its filename, folder, length or markers**, none of which separate a
research-worthy source from an ordinary one in practice.

### The authorised range (consent)
Every run has a range of depths you may use. **Default: all three.** The user narrows it
(`--depth concise,standard`, "no research this time") or pins one (`--research` / `--standard` /
`--concise` — unchanged, each forces that depth for the whole run). **Never choose outside the range.**
If a source genuinely needs a depth the range excludes, **stop and ask** — that is the one surviving
pause, and it should fire rarely. Echo the resolved range in words before compiling when the user gave
anything other than the default, and resolve an ambiguous phrase to the **narrower** reading.

### The decision (three triggers, judged on the source you just read)
- **T1 · Reuse** — does it carry original figures, a reimplementable method, or wording where a
  paraphrase would falsify the claim?
- **T2 · Proximity** — does it bear on a topic named in `wiki/user/`, or on an open question already in
  the wiki (a `## Conflicts / Open Questions` block, a `flagged:` page)? *Fallback*: if
  `wiki/user/` is absent, empty, **or outside the reader's scoped reading list** (a delegated compile
  lane — two №103 lanes resolved this opposite ways, one probing off-scope, one forced down to
  `standard`; cross-reflection P3, 2026-08-28), read T2 as "a topic with ≥3 source pages in `index.md`"; if the wiki
  is too small for even that, say so once and work in concise/standard only.
- **T3 · Novelty** — does it add anything not already on an existing page?

**`research` = T1 ∧ T2 · `concise` = ¬T3 · `standard` = everything else.**

**Overrides (fire regardless of the triggers):**
- A source in `raw/9-originals/` (the owner's own work) is **never below standard**.
- A source that **corrects an existing wiki page is always research** — a correction has to be exact.
- A source whose Step 0 check found **collapsed word boundaries can never be research** (verbatim
  quoting is impossible on it): compile at standard and say so in the report. The same holds for a
  conversion the Step 0 scorer reads `suspect` in scope `pdf` (3c): the `flagged:` line it puts on the source
  page is the record, and the depth line names that verdict as the reason. 3b and 3c never contradict —
  either one raising the flag is enough, and a 3c `clean` never clears a 3b `COLLAPSED`.

**Name the evidence, or drop a rung.** Every depth you record carries a locator — `research — T1 (Table 3
ablation) · T2 (calibration, About Me)`, `concise — ¬T3 (link post, all three tools already have pages)`.
A trigger letter with empty parentheses is a defect, not a record. **If you cannot name the evidence,
take the lower rung** (the §4.6 tie-goes-lower principle, applied to depth).

- **standard (the usual outcome)** — articles, blogs, posts, docs. Run Steps 2–4 as written.
- **concise** — thin or fully-redundant sources (brief tweet, link dump, thin page): 1–3-sentence
  summary, create pages only for genuinely new entities/concepts, minimal bullets.
- **research** — primary material the owner will need to reuse exactly. At research depth:
  - Preserve exact figures (no rounding); quote critical claims verbatim with §/page refs; mark
    anything not directly stated as `unverified`; never infer numbers.
  - **Quote discipline, all depths:** short critical quotes as above stay mandatory; *long-form
    block quotes* stay in the raw file — link, never transplant — so compiled pages stay quotable
    from their source (a refusal while reading is handled reactively, CLAUDE.md §11).
  - Replace the Step 3 source page with the **literature-note template** below.
  - Add academic frontmatter (`authors`, `year`, `venue`, `doi`, `depth: research`).
  - Cross-check findings against existing pages and flag confirmations/contradictions explicitly.

**Record it, always.** Every source page carries `depth: concise|standard|research` (Step 3); every run
reports each source's depth + locator (Step 8) and logs the tally (Step 5). *Never silent* is now
**never unrecorded**: consent lives in the range, notice lives in the record. Do **not** backfill `depth:`
onto pages compiled before this contract — an absent value means "unknown", and inventing one would be
fabrication.

### Research-depth source page (replaces the Step 3 template)
```markdown
---
title: "Paper: <Title>"
type: source
depth: research
confidence: high   # authoritative if peer-reviewed/published; see CLAUDE.md §4.6
audited: <YYYY-MM-DD>   # today — assignment with the source in context is the check (§4.6)
tags: [paper, <field>]
authors: [<First Author>, <…>]
year: <YYYY>
venue: "<journal / conference>"
doi: "<DOI or stable URL>"
sources: [raw/2-papers/<file>.pdf, raw/2-papers/<file>.md]   # original + converted
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

## Citation
<full reference string>

## Research Question
## Methodology
## Key Findings
- <finding with exact figures, e.g. "+12.3 BLEU, p<0.01">
## Data / Setup
## Contributions
## Limitations & Threats to Validity
## Relation to Wiki
- Confirms [[…]]; contradicts [[…]] → flag a `## Conflicts / Open Questions` block on that page
## Key Quotes
> "<verbatim>" (§/p.)
## Open Questions / Follow-ups
## Related
- [[…]]
```

**Genre note — research depth is not paper-only.** T1 ∧ T2 fire on any primary source whose exact
wording matters (regulations, institutional handbooks, contracts, policy documents). For those, keep
the frontmatter fields that exist (no DOI → omit it; `venue:` takes the issuing body + version) and
replace the paper-shaped middle sections (Research Question … Limitations) with genre-fitting
equivalents (e.g. Scope & Applicability · Requirements & Thresholds · Deadlines & Milestones ·
Governance). The obligations never flex — exact figures, verbatim quotes with §/page refs,
`## Relation to Wiki`, `## Related` — and the substitution is declared on the page and in the run
report. First exercised 2026-08-26 on an institutional research-degree handbook, where the exact
thresholds and term-relative deadlines are precisely what a paraphrase would falsify.

## Run ledger (persistence — every run, serial or parallel)

Every ingest run appends an event log under the agent home `~/.llm-wiki/`:
`~/.llm-wiki/ingest-runs/run-<YYYYMMDD-HHMM-id>.jsonl` — one JSON
event per line via shell append (`printf '%s\n' '<json>' >> <ledger>`), the same primitive that makes
`log.md` race-safe. **Never read-modify-write it**; resume state is a fold over events.
No helper script — primitives first (§12), until a real run shows hand-rolled appends failing. *(Status 2026-09-02: that condition has fired twice — five fabricated clocks in run 20260901-batch112107, then a hard-coded stamp in run 20260901-mp2i despite a brief mandate — so a helper or a mechanical ledger check is now the owner's call, recorded in known-issues.)*
(Design record: `wiki/developments/ingest-persistence-parallelism-design.md`.)

**Fold with a parser; a key-pattern grep is a locator, never a verdict.** Writers disagree on key
spacing (`json.dumps` writes `"lane": "LB"`, a `printf` event `"lane":"LB"`), so every count, census
or resume fold reads the lines through `python3 -c` or `jq`. A grep locates a line to look at; it
never settles a question. Evidence: a head grep of `"lane":"LB"` reported two lanes' claim objects
missing and that false negative reached a verify brief (2026-09-04), and `grep -c '"lane":"L4"'`
returned 5 of 8 on the same shape (2026-09-01) — both in `known-issues`.

**Every event's `ts` is the shell clock at write time** — `$(date +%FT%R%z)`, one offset format,
head-written events included — never typed, remembered or derived from context. Five lanes stamped
~6.5–7 h fast on one run (2026-09-01), and the resume pre-flight below reads a future-dated stamp as
perpetually live, so a fabricated clock disables the liveness check it feeds.

**Events** (extra fields are free): `run_open` (run id · pacing · authorised depth range · inbox
listing as `inbox: [{file, sha256 prefix}]`) · `lane_open` / `lane_close` (lane id · definition ·
model · effort) · per-source `checkpoint` (`source` + `stage` + stage fields) · `conflict` (page ·
both statements' locators · disposition) · `merge_open` (plan artefact named, parallel mode) · `merged` (per merge target, parallel
mode) · `verify` (Verify step: lane · definition · model · effort · `scores:` line · verdict · fixes) ·
`run_close` (tallies mirroring the Step 5 log entry). **Serial runs use lane id `head`** — one schema serves both.

**Checkpoint stages, mapped to the pipeline** (append as each source passes the step):
`deduped` (pre-flight) → `converted` (Step 0; skipped for native `.md`) → `read` (Step 1) →
`compiled` (Steps 2–4: pages created/updated · depth + locator · confidence tiers) →
`claims_emitted` (parallel lanes only) → `registered` (Step 5) → `sorted` (Step 6).

**The ledger is evidence, never authority — disk is truth.** Resume re-verifies every ledger claim
against disk before acting — content, not existence (torn-write check: frontmatter closes,
`## Related` present). A 0-hit disk probe shortly after a crash gets one retry before it is believed
(phantom-zero rule). Ledger-vs-disk mismatch → reconcile from disk and append a correction event;
ledger missing mid-run → fall back to the raw-root convention (root = unprocessed) and say so. A
malformed line never blocks a fold: skip it and report it.

**Resume pre-flight (start of every run, before the inbox scan):** one cheap check —
`grep -L run_close ~/.llm-wiki/ingest-runs/run-*.jsonl 2>&1` (dir absent / no files → proceed fresh,
silently). Any open run → report it (each source's last checkpoint, plus the **age of the last
event**) and offer resume before scanning the inbox fresh. Last event under **~60 minutes** old →
flag "possibly live in another session" and let the owner decide (concurrent sessions are routine
against this vault; resuming a live run would create a dual-writer race). The 60-minute line is
judgement, loosely anchored to a once-observed ~30-minute cloud-sync materialisation lag.

**A `ts` later than the shell clock is invalid — never "live".** Five lanes stamped ~6.5–7 h fast on
2026-09-01, and a future stamp sits under the 60-minute line for ever, disabling the check it feeds. So
age the latest event against the wall clock, comparing stamps as parsed instants (a string `max` ranks
`+0100` above `+0000` for the same clock reading), and where the latest `ts` is later than now, or any
stamp is unparseable or carries no UTC offset, fall back to the ledger file's mtime and name the source of
the age in the report:
```bash
python3 -c "
import datetime as dt, json, os, sys
p=sys.argv[1]; now=dt.datetime.now(dt.timezone.utc); t=None; ts=''; bad_ts=''; skipped=0
for line in open(p):
    try: s=json.loads(line).get('ts','') or ''
    except Exception: skipped += line.strip() != ''; continue
    try: c=dt.datetime.fromisoformat(s)
    except ValueError: c=None
    if c is None or c.tzinfo is None: bad_ts = bad_ts or (s or 'absent'); continue
    if t is None or c > t: t, ts = c, s
bad = t is None or t > now or bad_ts != ''
age=now.timestamp() - (os.path.getmtime(p) if bad else t.timestamp())
print(('mtime (ts invalid: ' + (bad_ts or ts or 'absent') + ')') if bad else ('ts ' + ts),
      round(age/60), 'min old ·', skipped, 'malformed line(s) skipped')" ~/.llm-wiki/ingest-runs/<run>.jsonl
```
The mtime is a fallback, not a clock: a ledger synced in from another machine can carry a preserved
older stamp, so the age it yields may overstate how long the run has been quiet. Report a rejected
stamp as "ledger clock rejected, mtime age <n> min" and let the owner decide, exactly as with a run
inside the 60-minute window.

**Completion gating (ungated mid-pipeline duties measure at 4% compliance here — so gate, don't
trust habit):** the Step 8 report carries one mandatory line — `Run: <id> · <n> ledger events ·
closed` — and the Step 5 log entry names the run id. A silent zero surfaces in the reply the
completion gate already requires; the warn-only Stop hook (`.claude/hooks/ingest-ledger-check.sh`)
additionally flags stale open runs at turn end.

## Parallel mode (compile lanes + entity merge)

The serial pipeline is unchanged; parallel adds lanes and a merge stage. Run it through the delegate
skill (routing, spawn slots, `brief-compile` template). Full rationale:
`wiki/developments/ingest-persistence-parallelism-design.md`.

1. **Partition (head agent; planner lane where used — its output is a proposal, §2.2).** Disjoint
   source sets, balanced by size/likely depth; related sources deliberately co-assigned to one lane so
   shared-entity claims cluster. **Verified, never assumed:** before any spawn, a mechanical
   disjointness assert — every inbox source in exactly one lane; pairwise-empty file whitelists — plus
   a head review of every brief.
2. **Owner go on the echoed spawn record** — this skill's own approval gate, whatever `pre-report`
   says (a reporting knob, never a consent switch).
3. **Lane shape.** `wiki-compile` under `brief-compile` + two added duties: **ledger appends**
   (`lane_open` · per-source checkpoints · `lane_close`) and **claims instead of shared-page writes**.
   Per-lane whitelist: its raw pairs (conversion writes — disjoint files), its source pages (sole
   writer), the run ledger (append-only), and, under the §2.2 ingest exception, its own
   `index.md` source-heading lines by **anchored per-heading `Edit`** and its own `log.md`
   entry by **shell append** (`cat >>`) — never an `Edit` on the log, which the harness
   would make the lane read whole (600 kB+). Grep-verify both back and show the grep.
   Everything else: propose-don't-write.
4. **Lanes never write shared-type pages** (entity/concept/model/benchmark — the true race surface).
   Each lane emits **claims** in its report AND **in full inside the `claims_emitted` checkpoint** —
   the event carries the claim objects themselves, never just their names: lane reports die with
   their sessions, so a name-only mirror leaves the run unresumable if the head dies before merge
   (gate evidence 2026-08-28: lanes mirrored inconsistently; the head's plan artefact had to carry
   the load). Claim schema:
   `{name · type · kind: create|update · target (canonicalised against index.md/existing pages —
   GPT-4o arrives as an update to the GPT page, §4.5) · facts[] with per-fact source locators · links[] ·
   appears_in[] · confidence (lane-assigned, §4.6) · from: source-page}`; shaky facts marked
   `unverified`. The claims consumer is the head LLM — report framing is tolerated; no parser exists.
5. **Lanes do NOT sort — they end at `registered`.** Sorting before merge would mark sources processed
   while their entity claims were still unapplied, silently breaking root-state truth (the §2
   fallback invariant). The head sorts at merge-close.
6. **Merge stage (head agent, after all lanes close). Open it by persisting the plan:** write the
   deduped merge plan (targets · kinds · fact sources · tiers · close-out steps) to a scratch file
   and append a `merge_open` event naming it BEFORE the first page write — with the full claims in
   the ledger this is belt-and-braces, and together they are what makes a mid-merge crash honestly
   resumable (the leg-2 gate drill resumed from exactly these two artefacts). Then: dedupe claims cross-lane by canonical target
   (two lanes' names for one new entity → one page + aliases) · merge facts · write each shared page
   **once** (create per schema, or anchored incremental merge — never clobber), appending a per-target
   `merged` event as it goes · **reconcile lane-page links** (apply the canonical-name map back to
   lane source pages whose `## Related` named a losing variant — safe, all lanes are closed) · index
   each merged page · sort each fully-merged source's raw pair (`sorted` checkpoints) · append the
   head's batch `log.md` entry naming lanes and models (§5 attribution). Run log composition: N lane
   entries + 1 head batch entry.
7. **Confidence at merge (§4.6):** the lane that read the source assigns the tier; merge *combines* —
   corroboration across claims may lift a compiled page toward its `high` cap, never above — and never
   re-grades a reading lane's tier without reading the source. The head's §4.6 spot-check rides the
   merge pass; `audited:` stamps at merge write.
8. **Step 7 splits.** A claims-mode lane checks: every link resolves to a real page **or to a target
   in my emitted claims**. The head runs the Verify step (below) over each lane's pages and claims
   BEFORE merge, then the full Step 7 over the batch post-merge — the final gate before `run_close`.
   **Quarantine is per claim, not per lane.** A claim's facts carry their own locators, so the verify
   leg's `claims` dimension counts the claim objects whose facts the flagged sentence, paragraph or
   table feeds and names them; the head quarantines exactly those and merges the lane's remaining
   claims. Two cases still take the whole set: a **plant** hit (the lane failed the fidelity gate, not
   one sentence) and a leg that could not run the dimension (`claims -`) — fail closed. Derivation:
   on run `run-20260904-0230-thin` the per-lane rule discarded 93 usable claim objects over one
   fabricated sentence each on three lanes and the merge re-derived them, ≈$16.7 against ≈$10 list
   (`known-issues`, 2026-09-04).
9. **Conflicts under parallelism.** A lane never pauses the batch: it keeps both statements in its
   claim (§4.4) and appends a `conflict` event; the head surfaces every conflict in the batch report,
   and high-stakes ones pause the **merge** — the single point where a pause still has leverage.

## Verify step (every compile a lane did — the routed single-source path and each parallel lane's pages)

Runs head-side after the lane closes and before the head accepts the run (Step 7 and the close-out).
Design: `wiki/developments/fable-minimising-routing.md`, protocol items 3, 4, 5, 6 and 9 (item 4's
single-source form and item 3's mechanism delta are dated status facts there). **Routing (shipped
2026-09-03, critic C15 folded; mode-gated 2026-09-04):** the scripts run in the head's shell (M0), the
scoring runs in a `verifier` lane on opus (the class's default from 2026-09-06; before that a per-call escalation inside its option set, since
tier verdicts are judgement claims — delegate skill §2), the verdict stays with the head (M2). The lane
is the default under the `multi` regime; under `single` the head scores in-session **unless** an
instrument-rule reason holds — and one always does when the compile itself was routed, since a verify
leg on a routed step is reason (a) (delegate skill §1). So a lane-compiled source never loses its
independent leg, in either mode, and a head-compiled source gets one only where the head proposes it.

1. **Output set by manifest, never by report.** Before the run's first spawn, `touch` a marker file
   beside the run ledger (`~/.llm-wiki/ingest-runs/<run>.marker`) — once per run, never re-touched on a
   resume; after the lane closes, `find <vault>/wiki -name '*.md' -newer <marker>` (absolute path) is the
   candidate set, **intersected with the lane's file whitelist from its brief**: a candidate off the
   whitelist is reported as an "unexpected writer" (a concurrent session, a sync, a lane off its
   contract) and is never scored or rewritten. Controls: the source page the lane reports must be in
   the set — an empty set against a reported page is a broken probe, not a clean one; where the lane's
   durable transcript exists, its Write/Edit/redirect paths (the parity store's scope parser lists
   them) must equal the set. Parallel mode takes the set per lane, before merge.
2. **M0 pre-checks, head shell, stdout only — persisted, then named in the brief.** Run `python3
   .claude/skills/lint/tier-cap-check.py --format json` (vault-wide — a clean vault implies a clean
   set); `python3 .claude/skills/lint/anomaly-lister.py --pages <set>` (the page-visible list the
   lane's `## Anomalies` is checked against); `python3 .claude/skills/lint/check-links.py` (dead
   links). Write all three, each under a heading naming its script, to
   `~/.llm-wiki/ingest-runs/<run>-m0-<lane>.txt` beside the run ledger, and let the brief name that
   path instead of pasting the lines: a lane cannot treat brief text as evidence, and two verify lanes
   scored the pasted `tier-cap-check.py` line UNVERIFIABLE for exactly that reason (`known-issues`,
   2026-09-04). The path joins the lane's read grants. A breach here is a miss before the verifier runs.
3. **Verifier lane** from `.claude/skills/delegate/templates/brief-ingest-verify.md`, which also
   receives the compile brief's CONTEXT NOTES verbatim, the plant, the M0 file's path, and (parallel
   mode) the lane's emitted claims: claim list and warranted set from the raw first, then the counts —
   fabrication · plant · coverage · tier · structure · integration · language · anomalies, plus
   `claims` in parallel mode (the claim objects whose facts a flagged sentence feeds, the quarantine
   unit of step 8 above) — evidence per non-zero, both controls, the plant grep's own positive
   control, and the last line `scores: …` (`plant -` when its control could not run; `claims` is
   appended to that line in parallel mode only, so a serial line keeps the eight names the parity
   gate's verdict script parses). One lane per compile; a second only where the head disputes a call, and the lane's evidence,
   never its verdict, decides.
4. **Verdict (head, M2).** Fabrication 0 and plant 0 are required; `plant -` (no plant, a placeholder,
   or a plant that hits in the raw) means the leg did not run — re-plant and re-run it, or the compile
   reverts. A fabrication or plant hit reverts that compile to the head for the run: the head corrects
   or rewrites the pages itself, appends a `known-issues` entry, and the step's next use needs a brief
   or rubric change first (protocol item 1's retry rule); in parallel mode the `claims` count says
   which of that lane's claim objects the merge must drop (step 8) rather than the whole set. Every
   other non-zero item the head settles from the cited evidence: a coverage, structure or language miss is fixed on the page; an integration
   miss on both pages; a tier dispute — and every tier the lane raised above an existing page's badge —
   is read in full by the head (§4.6: delegation never raises a tier unread); an anomaly the lane
   omitted is judged and, where real, written as a §4.4 block. **Head slice (protocol item 4):**
   whatever the scores, the head reads the source page and up to two more set pages in full against
   the raw (the larger of three items or ten per cent); the per-run empirical re-compile is withdrawn
   for single-source compiles (design page, dated status) — every fifth routed run the head also
   compiles the source in a fixture and diffs. The head never edits a lane's page on a verdict alone —
   it reads the cited line first.
5. **Record.** One `verify` ledger event (lane id · definition · model · effort · the `scores:` line ·
   verdict · fixes applied), appended with a shell clock; the spawn record carries the plant and the
   full meter; **a routed-run register row on the design page every run** (misses, reverts, fable
   share). Then Step 7 runs head-side over the set (its controls are the head's, not the lane's); the
   lane's `audited:` stamps stand, with the mechanism (lane check · verify leg · head slice) named in
   the head's close-out log entry (protocol item 9) — always written for a routed run beside the lane's
   own entry, carrying the verdict line, the `fable share:` meter line (protocol item 8;
   `fable-share.py`) and wikilinks to the network pages the head accepted (the lane's entry names them
   in code font); the Step 8 report carries the `scores:` line and the verdict beside the depth and
   confidence lines.

## Pipeline (per source)

### Pre-flight — De-dup: have I ingested this already? (one cheap shell call)
Step 6 (move-to-subfolder) is the **primary** guard: a root file is unprocessed by construction and
archived files are never re-scanned. The pre-flight only catches a doc that was **re-added**
(re-clipped, copied, or renamed). **Keep it minimal-token**: run it as ONE combined command that prints
*only* a match — so it costs ~nothing when there's no duplicate, and **its output does not grow with
wiki size** (grep for *this* file's hash, never dump all hashes; never read page contents):

```bash
f="<filename>"; u="<source: URL, or empty>"
{ find raw -mindepth 2 -name "$f"
  h=$(shasum -a 256 "raw/$f" | cut -c1-16); [ -n "$h" ] && grep -rlF "$h" wiki/sources/
  [ -n "$u" ] && grep -rlF -- "$u" wiki/sources/ raw/*/
} | sort -u      # any path printed = possible duplicate
grep -rlF "source_hash" wiki/sources/ | head -1   # §11 control: MUST print a page — silence = the probe searched nothing, so "NEW" is unproven
```
An empty candidate list means NEW **only when the control line printed**; stderr stays visible by
design (a missing file or unreadable dir must surface, never read as "no duplicate").

**On a match, decide (don't blindly skip):**
- **Process it as an UPDATE** when there's something new to extract — the user gave extra instructions,
  a deeper **depth** is requested (e.g. `--research`), it's a newer/extended version, or it plausibly
  carries **new content** (e.g. an **OpenReview / peer-review page** with reviews, rebuttals, scores,
  decisions). Read it and **merge new findings into the EXISTING wiki pages** (don't create a redundant
  second source page). A genuinely different artifact — notably a **review** — gets its own page and is
  filed to `raw/7-reviews/` (Step 6).
  - **Depth upgrade (merge vs replace).** When the update is a *deeper depth* for an already-compiled
    source, **replace that one source page** with the deeper template (research → the literature-note
    template) and update its `depth:`; **merge** everywhere else — entity/concept/model/benchmark pages
    take the new detail incrementally, never a rewrite. Never downgrade: a re-ingest at a shallower
    depth leaves an existing deeper source page alone unless the user explicitly pins the shallower one.
- **Quarantine** to `raw/duplicates/` when it's **not useful** (truly redundant) OR the user says
  **"ignore duplicates"**. Move the file there — never leave dups in the inbox or delete them.
- No match (genuinely new) → proceed to Step 0. Record `source_url`/`source_hash` (Step 3) for next time.

> The shell check only catches *exact/near-exact* dups (name · byte-hash · URL). A **content duplicate
> in a different file** (same paper, different PDF/version; an OpenReview page) won't match — spot it
> while reading, then apply the same decision (update vs `duplicates`).

- **Opt-out**: `--no-dedup` (or "skip dedup") skips this pre-flight for bulk all-new loads. On by default (cheap).

### Step 0 — Normalize to Markdown (MarkItDown) — conversion for non-`.md` sources; the score (3c) for every file carrying `converted_by:`
**If the source is already `.md`, SKIP the conversion (1–3b) — do NOT invoke MarkItDown — but still run 3c on it when its frontmatter carries `converted_by:`.** A gather, Jina or defuddle capture is a conversion whatever its extension, and the score keys on that observable, never on the extension (two of the three damage admissions the 2026-09-08 lint probe found sat on Jina captures no check had scored). A `.md` with no `converted_by:` takes no Step 0 at all.

Otherwise (`.pdf`, `.pptx`, `.docx`, `.xlsx`, `.png`/`.jpg`, `.mp3`/`.wav`, `.html`, `.csv`, `.epub`,
… or a YouTube/web URL):

1. **Preflight the engine** (install once if missing — the console script is NOT on PATH here, so
   check *importability*, not `command -v`):
   `python3 -c "import markitdown" 2>/dev/null || pip3 install 'markitdown[all]'`
   `pdftotext` is **optional** and serves 3c's recovery measure only: `command -v pdftotext || brew install poppler`
   (macOS; the `poppler-utils` package elsewhere). Absent, or failing on a PDF, the scorer prints
   `recovery n/a (pdftotext absent)` or `recovery n/a (pdftotext failed: <reason>)` and decides on its other
   three measures — it never stalls a conversion on the binary.
2. **Convert** (always use the module form — `python3 -m markitdown` — since the bare `markitdown`
   script isn't on PATH):
   - **Local file** → `python3 -m markitdown "<absolute path>" -o "raw/<stem>.md"`
   - **URL — capture the *original*, never a summary.** Route by type:
     - **Raw `.md` / text / code URL** (`raw.githubusercontent.com`, gist raw, `.txt`) → `curl -sL "<url>"` and save the bytes **verbatim**. **Do NOT use WebFetch** — it returns a model *summary*, not the source.
     - **Web page (article / repo / docs)** → `defuddle` (extracts the real main content as clean Markdown, not a summary). Use WebFetch *only* for a throwaway lookup where exact text is irrelevant — never for ingest.
     - **arXiv HTML / LaTeXML page** (`arxiv.org/html/…`, ar5iv) → do **not** defuddle it (defuddle's Markdown converter crashes on LaTeXML and silently emits raw HTML): `curl -sL` the page to a temp file, then convert with `python3 -m markitdown`.
     - **GitHub repo** → `curl -sL` the raw README/files (`raw.githubusercontent.com/<owner>/<repo>/<branch>/README.md`), or `gh api` / `gh repo view` if authenticated.
     - **YouTube / binary URL** → MarkItDown's Python API (its CLI only accepts file paths):
       `python3 -c "from markitdown import MarkItDown; open('raw/<stem>.md','w').write(MarkItDown().convert('<url>').text_content)"`
     - **Fallback — a web page none of the above can capture** (JS-heavy / anti-bot / empty or garbled result) → `curl -sL "https://r.jina.ai/<url>"` (Jina Reader renders server-side → clean Markdown). **Last resort only**; it routes the URL through a third party, so skip it for sensitive or login-walled pages.
     - **Public X/Twitter post URL** → capture via the tier-1 Jina channel: `curl -sL "https://r.jina.ai/<post-url>"` (route live-verified 2026-08-23; declare the routing in the ingest report, as with any Jina capture). Single public posts only — X search, timelines and protected content take the platform-gap path below.
     - **Platform URL the whole chain cannot capture** (a Reddit thread, XiaoHongShu note, X search/timeline/protected content, Bilibili search page, or other login-walled/bot-blocked platform page) → do NOT improvise a scraper and never WebFetch it: report the gap and point at the ready, owner-gated platform-reach option (`wiki/developments/agent-reach-adoption-design.md` — nothing installs or routes without the owner's word). YouTube stays on the markitdown route above.
     - **Opt-in `--verbatim` (byte-exact original).** When the user wants the *unaltered* source (research-grade provenance / exact quoting), `curl -sL "<url>" > raw/<stem>.md` (or `gh`) and keep the bytes **unmodified** — skip the step-3 defang/clean (raw/ is graph-excluded anyway). For an HTML page, `curl` it then `python3 -m markitdown` to convert deterministically (full content, no summary). Heavier on tokens → opt-in, not the default.
3. **Save** the Markdown into `raw/` as `<original-stem>.md` (use `<original-stem>.converted.md` if
   that name is taken). **This is the only time you may add a file to `raw/`.** Prepend provenance:
   ```yaml
   ---
   converted_from: <original filename or source URL>
   converted_by: markitdown
   converted_on: <YYYY-MM-DD>
   conversion_score: <from 3c, e.g. short-lines 4.0 % · run-together 1.7 % · long-run 0.3 /1k · recovery 0.96 · clean · scope pdf>
   ---
   ```
   Then **sanitize the saved body** so it can never pollute the Obsidian graph (MarkItDown emits stray
   `[text](bareword)` links from math/citations, and sometimes control/binary bytes):
   ```bash
   perl -i -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g; s{\[([^\]\n]*)\]\(([^)\n]*)\)}{my($t,$u)=($1,$2); $u =~ m{://|^#|^mailto} ? "[$t]($u)" : "$t ($u)"}ge; s/\[\[/[ [/g; s/\]\]/] ]/g' "raw/<stem>.md"
   ```
   (Strips control bytes; defangs `[a,b](z)`→`a,b (z)` and `[[x]]`→`[ [x] ]`; keeps real `https://` links. `raw/` is also graph-excluded — see CLAUDE.md §12.)
   **Post-sanitise check (same pass, cheap):** keep a pre-image first (`cp "raw/<stem>.md" /tmp/` — perl edits in place), then compare `wc -c` and `grep -c ']('` before/after: bytes may fall only by the stripped control bytes, and the `](` count only by the intended bareword defangs — any other delta (a falling kept-link count above all) is a sanitiser defect: STOP, restore the pre-image, inspect. No pre-image (premise failure) → recompute the before-counts from the fetched source and say so. `--verbatim` captures skip sanitising, and this check with it. (Instantiates `wiki/developments/verification-discipline.md`; the 2026-08-23 capture-group clobber shipped `[]()` mangles for two months before an ad-hoc size check caught it — `wiki/developments/known-issues.md` §Closed.)
3b. **Conversion-quality check (converted files only).** *3b and 3c never contradict: a `COLLAPSED` here is
   authoritative on its own, a `suspect` from 3c (scope `pdf`) is authoritative on its own, and either one
   raises the `flagged:` line on the source page — 3c's line records the four measures and names `3b COLLAPSED`
   beside them when 3b fired, so the line says which check spoke; a 3c `clean` never clears a 3b `COLLAPSED`.
   Probe (b) locates the damage.* Some PDFs convert with the inter-word spaces
   stripped, so the body reads `ProximalPolicyOptimizationAlgorithms…`. The text is still readable but
   has **no word boundaries to quote**, which silently defeats research depth's verbatim-quote contract
   and makes every word-count metric wrong. One arithmetic check, no LLM read:
   ```bash
   python3 -c "
   t=open('raw/<stem>.md',encoding='utf-8',errors='replace').read()
   w=len(t.split()) or 1; c=len(t); cjk=sum(1 for ch in t if '一'<=ch<='鿿')
   print(('COLLAPSED' if c/w>50 and cjk/max(c,1)<0.10 else 'ok'), round(c/w), 'chars/word')"
   ```
   **The whole-file mean clears a partially collapsed file.** MarkItDown's table padding, reference lists
   and prompt blocks restore enough whitespace to pull the ratio back under 50 while the running prose
   stays space-stripped (2026-09-04, ten arXiv PDFs: `ok` at 8–17 chars/word, prose-only ratios 13–21).
   So every converted file also takes probe (a) below, which decides; where the mean or (a) fires, run probe (b)
   for the locators:
   ```bash
   # (a) run-word probe: letter runs of 25+ with no space in them, per 1,000 words.
   python3 -c "
   import re,sys
   t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
   r=len(re.findall(r'[A-Za-z]{25,}',t)); w=len(t.split()) or 1
   print(('COLLAPSED' if r>=10 and r*1000.0/w>5 else 'ok'), r, 'runs', round(r*1000.0/w,1), 'per 1k words')" "raw/<stem>.md"
   # positive control on the same run — the register's own probe against a known-clean capture (defuddle
   # or curl). `-c` counts matching LINES, not runs: 4 on a clean arXiv-HTML capture against 758 on the
   # collapsed file measured 2026-09-07, so the control must sit far below the file under test.
   grep -coE '[A-Za-z]{25,}' "raw/<a clean capture>.md"
   # (b) per-line ratio over PROSE lines only — fences, |-rows, quotes, embeds and numbered
   #     reference entries dropped, since their markup is what dilutes the whole-file mean.
   #     (Both counts sit in their own variables: a `/` straight after `)` reads as a path to the lane
   #     shell fence, which denies the whole command — verified 2026-09-07.)
   python3 -c "
   import re,sys
   fence=False; bt=chr(96)*3
   for n,l in enumerate(open(sys.argv[1],encoding='utf-8',errors='replace'),1):
       s=l.strip()
       if s.startswith(bt) or s.startswith('~~~'): fence = not fence; continue
       if fence or len(s)<60 or s[:1] in '|>' or s.startswith('![') or re.match(r'^\[\d+\]',s): continue
       c=len(s); w=len(s.split()) or 1
       if c/w>50: print(n, round(c/w), s[:60])" "raw/<stem>.md"
   ```
   `COLLAPSED` from **either** the mean or probe (a) → the source **cannot be research** (Depth override):
   compile at standard, say so in the Step 8 report, and offer `--agent-convert` or a different capture
   route if the owner wants it quotable.
   A high ratio with ≥10% CJK is **not** a collapse — Chinese and Japanese have no inter-word spaces, so
   word counts are meaningless there while quoting works fine. (Threshold calibrated on this vault: real
   collapses sit near 300–400 chars/word, ordinary English clips with long URLs reach 25. The run rate is
   calibrated on the same corpus, the 96 Markdown captures under `raw/2-papers/` on 2026-09-07: 76 sit
   below 2 runs per 1,000 words and three at 2.2–2.5, the next value up is 10.6, and every file from
   there up is a MarkItDown PDF conversion with space-stripped prose — 5 lies in the empty band between
   the two populations, and the 10-run floor keeps a short clean capture off the gate, a clean defuddle
   capture of an arXiv HTML page measuring 11 runs in 9,513 words. Probe (b) is read, never counted: on
   the same corpus a clean capture carried up to 8 flagged lines, all glyph padding or data-URI blobs,
   and a collapsed one as few as 8, so only (a) separates the two populations.)
3c. **Conversion score — the scripted check (every file carrying `converted_by:`; register entry 2026-09-08).**
   Its thresholds are derived from the vault's own 96-file distribution, never set by eye. Run it on every
   conversion after the sanitiser and its post-check, and on every `.md` capture whose frontmatter carries
   `converted_by:` — a gather or Jina capture included; the conversion steps are what a `.md` source skips,
   never this score:
   ```bash
   python3 -B .claude/skills/ingest/conversion_score.py "raw/<stem>.md"
   ```
   One verdict line per file — `clean` or `suspect` — with four measures, the threshold each was judged
   against, and a `scope`. **Short-line share:** non-blank body lines of one character or less over all
   non-blank body lines (the structural collapse reads 94.4 % against a clean maximum of 20.7 %; threshold
   > 57.57 %; the cut rests on one positive, PPO.md — the other collapsed file reads 0.0 % here and is caught
   by the other three). **Run-together share:** Latin word tokens carrying an internal lower-to-upper case
   join or more than 18 letters, over all Latin word tokens, with fenced code, angle-bracket tags (attributes
   and their blobs included) and base64-shaped blobs excluded from both sides (the space-stripped conversions
   read 5.3–52.6 % against a clean maximum of 3.50 % — a defuddle capture of an arXiv HTML page whose hits are
   product names; next-worst clean 2.95 %; threshold > 4.41 %; `n/a` on a non-Latin-majority file, which has
   no inter-word spaces to lose). Before the exclusions the worst clean file read 8.68 % on one
   `<latexit sha1_base64="…">` line, and the 9.15 % cut that floor forced missed the SoK survey conversion at
   5.3 %. **Long-run rate:** probe (a) above, as a measure — runs of 25+ Latin letters per 1,000 words, firing
   at ten runs or more (the damaged conversions read 10.6–5,224 per 1,000 against a clean maximum of 2.48;
   threshold > 6.56), so 3b's probe and 3c count the same thing and differ only in the cut (3b's 5 per 1,000 set by judgement, 3c's 6.56 derived); a file between the two cuts is 3b's `COLLAPSED`, and that stands. **Sentence
   recovery** against `pdftotext` where a sibling PDF exists: the share of pdftotext sentences of six words or
   more found in the conversion after whitespace normalisation (damaged conversions read 0.00–0.01 against a
   clean minimum of 0.29; threshold < 0.15; `n/a` with no PDF, with `pdftotext` absent, or when it fails — the
   reason prints and the verdict rests on the other three). Each threshold is the midpoint of the gap between
   the worst known-clean file and the nearest known-damaged one beyond it — derived 2026-09-08 on
   `raw/2-papers/`, 17 known-damaged files against 79 clean, 17 caught at zero false positives; the token
   rule and the derivation are in the script's docstring, and `--derive DIR --positives FILE` reprints them.
   Exit 0 = clean, 3 = suspect, 2 = a premise failure (an empty or unreadable file, a directory with no
   `.md`): a premise failure is not a verdict — fix the premise and re-run.
   - **Scope — where the thresholds hold.** They were derived on PDF conversions of papers, and every verdict
     line says whether the file is inside that population: `scope: pdf` when `converted_from:` names a `.pdf`,
     a `.pdf` sibling exists, or `converted_by:` is one of this skill's document-conversion routes
     (`markitdown`, `agent`); `scope: other` for a defuddle, Jina, curl or gh capture of a web page. A
     `suspect` in scope `other` goes into the Step 8 `Suspect conversions:` block with its scope and measures
     and raises **no `flagged:` line by itself**: read the verdict line — API-docs captures fire the long-run
     rate on `BetaMessageParam`-shaped identifiers, READMEs the share on product names — and flag it only
     where the damage is real (on 2026-09-08, 9 of 301 non-paper captures read `suspect`, none of them damaged).
   - Copy the four measures, the verdict and the scope into the provenance block's `conversion_score:` line
     (the template in step 3), e.g.
     `conversion_score: short-lines 4.0 % · run-together 1.7 % · long-run 0.3 /1k · recovery 0.96 · clean · scope pdf`. A source that arrived as `.md` (a gather capture) has no step-3 template of its own: its score stays in the run report and on the source page's `flagged:` line when suspect, and the raw file is never written back (raw immutability).
   - **`suspect` in scope `pdf`, and 3b's `COLLAPSED`, are recorded in the flag channel, and only there.** The
     source page (Step 3) carries one line,
     `flagged: <YYYY-MM-DD> source conversion suspect — raw/<path>.md · short-lines N % · run-together N % · long-run N /1k · recovery N[ · 3b COLLAPSED]; verify quotations against the original`
     — the 3c measures always, `3b COLLAPSED` appended when 3b fired, so the line says which check spoke;
     never a prose note in the summary and never a `depth:` comment: deep-lint reads `flagged:` and nothing
     else, and lint's `check_flag_admissions.py` reports a source page that admits damage in prose without a
     conversion flag. The source **cannot be research** (the Depth override); a quotation from it is
     paraphrase, or is checked against the original; and the Step 8 report lists it under `Suspect
     conversions:` with its measures. Offer `--agent-convert` or another capture route if the owner wants it
     quotable (`pdftotext` read 0.0 % run-together where MarkItDown read 10.4 % on the same PDF, 2026-09-08).
   - **Terminal state — how a conversion flag ends.** The flag is removed when a repaired conversion — a
     `raw/<path>-repair.md` beside the original, or a re-fetched conversion — scores `clean` here and joins the
     page's `sources:`, and the page's `## Summary` ends with one dated Provenance sentence naming the repair
     file and the quotation check:
     `Provenance (YYYY-MM-DD): compiled from a damaged conversion (<what the scorer read>); repaired conversion raw/<path>-repair.md (<its verdict>); quotation check: n confirmed, m corrected, u unverifiable.`
     That sentence admits the old damage by design, and `check_flag_admissions.py` counts an admission that
     also names a `repaired conversion` under its `RESOLVED:` line, never as a finding. Removing the flag
     without the repair, or rewriting the admission away, is not a resolution.
   - `--thresholds SHORT,RUN,RECOVERY,LONGRUN` overrides the four for a scratch run (`-` keeps one, `off`
     disables one) and is printed on the summary line; it is never the way to make a conversion pass.
4. **Keep the original untouched.** The original and the converted `.md` are now a **pair**. For a
   URL source there is no local original — the converted `.md` is the only file; keep the URL in
   `converted_from`.
5. **Agent conversion — opt-in `--agent-convert`, and the offered fallback.** On `--agent-convert` (or
   "transcribe it yourself"), skip the engine: read the original directly (PDF pages / images via the
   Read tool) and transcribe it to `raw/<stem>.md` yourself — a faithful transcription, never a summary;
   mark illegible spots `unverified`; set provenance `converted_by: agent`. Reserve it for sources where
   layout or precision defeats MarkItDown — it costs real tokens, so it is never the default. **Fallback:**
   when a conversion returns empty/garbled text (e.g. a scanned, image-only PDF), FIRST rule out a
   truncated download — an empty converter error on a binary source may mean a partial file, so compare
   byte size against the source and re-fetch once (precedent 2026-08-25: an arXiv PDF at 2.6 of 5.4 MB
   failed markitdown silently; the re-download converted cleanly). Only then OFFER this route with a
   page/token estimate and proceed only on explicit confirmation; otherwise ask the user to OCR
   externally. Never fabricate content.

> From here on, "the source" means the **converted `.md`** (for converted sources) or the original
> `.md` (for native-Markdown sources).

### Step 1 — Read the source
- Read the source Markdown in full.
- If it references images worth keeping, download them into `assets/` and read them separately
  (LLMs can't read inline-image Markdown in one pass).
- If the clip is mainly a **pointer to a richer primary source** (a docs page, repo, or article URL),
  **follow that link** and fetch the real source with the Step 0 capture chain (`defuddle` for a page,
  `curl` for a raw `.md`/text URL, MarkItDown for a YouTube/binary URL — never WebFetch) — compile
  from the source, not the stub.

### Step 2 — Extract & (if needed) translate
Pull out: **core thesis** (1–2 sentences), **entities** (people/companies), **tools** (software/apps/plugins/skills/services),
**concepts** (frameworks/methods/theories). Translate non-English content into British/UK English.

### Step 3 — Create the source summary → `wiki/sources/<slug>.md` (kebab-case)
```markdown
---
title: "Source: <Human Title>"
type: source
depth: concise | standard | research   # the depth you chose (Depth) — required on every source page
confidence: medium   # per CLAUDE.md §4.6 — reflects the source: peer-reviewed/expert→authoritative · preprint/official-doc/owner-work/faithful-summary(default)→high · secondary or adjacent-only grounding→medium · promo/social/transcript→low (grounding strength, not source count; a user instruction can override the tier)
audited: <YYYY-MM-DD>   # today — assignment with the source in context is the check (§4.6); on updating an existing page, re-check its badge and re-stamp
tags: [topic]
sources: [raw/2-papers/report.md, raw/2-papers/report.pdf]   # converted .md AND original; one entry if native .md or URL
source_url: "<original web URL if a clip — else omit>"        # de-dup
source_hash: "<first 16 hex chars of the raw file's sha256>"   # de-dup — the length the pre-flight greps
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

## Summary
[3–5 sentence core summary.]

## Key Takeaways
- ...

## Related
- [[EntityName]] — why related
- [[Concept Name]] — why related
```
**Dual provenance:** for a converted source, `sources:` must list **both** the converted `.md` and
the original (file path, or the URL for web/YouTube). Predict the post-sort paths (Step 6) so the
links don't break after the move.

**Routing (parity gates G3 and G4, 2026-09-02 — `wiki/developments/fable-minimising-routing.md`).** Gate evidence: G4 passed with both lane arms cleaner than the head arm (the lanes kept the paper's internal contradictions the head had restated) and carries the flag "passed against a head arm the record cannot certify as strong"; G3 passed on its second attempt, after two brief clauses, without that flag. The routed step is in force — its carriers shipped 2026-09-03: (a) `.claude/skills/delegate/templates/brief-compile.md` carries the two gate-added clauses (the source page states the source's own provenance — publisher, date, URL; any sentence about a linked page uses only that page's or the raw's words), the CONTEXT NOTES fidelity-plant slot and the `## Anomalies` report section; (b) the Verify step above scores every lane compile against the raw — fabrication · plant · coverage · tier · structure · integration · language · anomalies, plus `claims` in parallel mode — before the head accepts it. **Mode gate (2026-09-04):** this routed default applies under the `multi` regime (owner-set, or head-resolved for the run under delegation `auto`, 2026-09-04). Under `single` the head compiles in-session unless an instrument-rule reason holds for that source — a batch it cannot hold (reason (b), which is Parallel mode below), or context isolation its watermark bands demand (reasons (c)/(d)) — and it may propose ONE verify lane for a high-stakes in-head compile, once (delegate skill §1). Default executor for a single-source compile in `multi`: a `wiki-compile` lane on opus (the definition's default since 2026-09-02) at the run's authorised depth range — standard and research are gated (G3, G4); concise is ungated (a lane that chooses it is covered by the verify leg and the plant; the design page records the residual); every compile clears the design's ≈30k leave-the-head threshold by construction, since a compile loads `wiki/index.md` (≈32k tokens at 127 kB, 2026-09-06; ≈27k when this line was written) before the source and its network pages, and the fresh-session head arm of 2026-09-03 spent 44k Fable output tokens on a 3.8 kB source — the derivation the cost rule requires; a 2–5 source `auto` batch routes one lane at a time (two routed lanes writing network pages concurrently is Parallel mode's race surface, and that shape takes Parallel mode's claims); the head keeps the resume pre-flight, the spawn record with its plant (echoed per `pre-report`; under `auto` the owner's `/ingest` invocation is the go for this single lane, whose whitelist is the ingest's own output — delegate skill §3 slot 0, dated clause), the Verify step and the close-out. When routed: the lane runs with the shape the gates tested — it writes the source page and the warranted network pages, its own index line and log entry under the §2.2 ingest exception, and sorts the raw; the head's post-lane check is the verify step plus Step 7's controls plus a full read of every page whose tier the lane raised (§4.6: delegation never raises a tier unread); §4.4 conflict settlement and the research-depth key-claim spot-check stay head-side; the head's close-out log entry, always written for a routed run beside the lane's, carries the verify verdict, the stamp mechanism and the `fable share` meter line; the spawn record keeps the plant and the full meter. **Re-gate runbook (rule 7; the G4 flag):** the second routed use at each depth re-runs the paired fixture form — the parity store's `g34v2` fixture builder, scope parser, verify-dir stager and verdict script — with a fresh-session head arm (`claude -p --model <fable id> --effort max` in a snapshot-equal fixture, its transcript effort confirmed) against two routed lanes on the current carriers; the routed-run register on the design page is the use counter. Standard depth's re-gate **passed 2026-09-03** (G3r, second attempt, after FIDELITY clause 3 was added; detail on the design page), so the routed default stands at standard depth; research depth's re-gate, carrying G4's flag, is the next research-depth compile.

### Step 4 — Network the knowledge (entities · tools · concepts · models · benchmarks)

**Index read modes for a whole ingest run (CLAUDE.md §5).** Read `section` for the five types this step
matches against, and `name` for the three it only checks membership in. Never `route`: an ingest knows
its types, so the whole file is waste — but a section list that is *wrong* loses recall silently, so
these eight rows are the whole list; a step that needs a section outside them says so in its report and takes `route` for that step alone.

| `## ` section | Mode | Why | Write |
|---|---|---|---|
| Entities · Tools · Concepts · Models · Benchmarks | `section` (46.6 kB, 37 % of the file) | the only types a source shares with existing pages, so the only place duplication is the risk (§4.5) | free |
| Sources | `name` (10.3 kB) | sibling-source links in the new page's `## Related` and name canonicalisation (291 of 348 source pages link another source); de-dup is the pre-flight's grep over `wiki/sources/` frontmatter, never this read; a source never merges into another, so the 53 kB of descriptions is not needed | free |
| Syntheses | `section` (4.2 kB; the names alone are 0.6 kB and carry no claim to contradict) | a new source can contradict an answer already filed; surface it as a §4.4 conflict | **ask** |
| Maps | `name` (0.1 kB) | a source in a mapped cluster usually belongs on that map | **ask** |
| Developments · User | `name` (2.3 kB + 0.05 kB) | framework records and the owner's profile: 34 of 348 source pages link a Developments page and 17 a User page from `## Related`, so the names are needed to link and to propose; the descriptions are not | **ask** |

**"Ask" means propose, never write.** Those four are the owner's or a past decision's, so this step
reports the proposed line and waits; `wiki/user/` already carries that rule in CLAUDE.md §1. A lane
writes only what its brief whitelists, whatever this table says.

For each entity → `wiki/entities/`, **tool** (software/app/plugin/skill/library/service) →
`wiki/tools/`, concept → `wiki/concepts/`, **model** (any LLM named — e.g. Qwen,
GPT, Llama) → `wiki/models/`, **benchmark** (any eval dataset named — e.g. AIME, GSM8K, GPQA) →
`wiki/benchmarks/` (Title Case filenames; a tool keeps its canonical lowercase where applicable):
1. **Page missing** → create it per the `CLAUDE.md` frontmatter + required sections (`## Definition /
   ## Key Points / ## Related`; model & benchmark pages also carry `## Appears in`); set its
   `confidence` per §4.6 (compiled pages **cap at `high`**). Judge by **grounding strength, not source count** (the rubric's settled reading, 2026-09-02): one strong source that is *primary for the page's own claims* grounds `high` on its own; a strong source primary only for something adjacent, or reputable-secondary grounding, is `medium`; conflicting corroboration stays `medium` by the tie rule; "thin" (one paragraph in one witness) is `low`. The cap is a ceiling, never a demotion (G3r evidence 2026-09-03: five blind scorings, every arm including the head tiered a single-source entity page `medium` citing source count).
2. **Page exists** → read it, then **incrementally merge** new info (don't clobber).
3. **Conflict found** → **pause**, report the conflict to the user, ask how to handle it
   (keep both under `## Conflicts / Open Questions`, overwrite, or skip), then continue.
   **Time-sensitive conflict → suspect the page first.** When the contradicted fact is
   time-sensitive (releases, versions, prices, dates, roles) and the wiki page predates the
   source, never default to grading the incoming claim down — an earlier compile date is
   evidence of age, not of correctness. Either run ONE bounded verification probe (a single
   search or authoritative lookup) to settle which side is current, or set
   `flagged: YYYY-MM-DD <one-phrase reason>` on the page and keep both statements per §4.4.
   In batch pacing this needs no pause — report the outcome in Step 8. (Precedent: the
   2026-08-23 Opus-5 staleness reversal, log entry same date.)

**Models & benchmarks link bidirectionally** (CLAUDE.md §4.5): add this paper under the model/benchmark
page's `## Appears in`, and list the models/benchmarks the paper uses in the source page's `## Related`
(Obsidian backlinks then close the loop automatically). **Reuse** an existing model/benchmark page —
never duplicate one (fold `GPT-4`/`GPT-4o` into `GPT`, `MATH500` into `MATH`, `Qwen2.5` into `Qwen`).

A single source typically touches **10–15 wiki pages** via cross-links. No orphans — every page
gets a `## Related` section.

### Step 5 — Update the registries
- **First-run bootstrap**: if `wiki/index.md` or `wiki/log.md` is missing (a fresh clone), create it first
  — an empty `index.md` with the standard `## Sources / Entities / Tools / Models / Benchmarks / Concepts
  / Syntheses / Developments / Maps / User` headers, and a `log.md` seeded with one `setup` entry. On this
  same fresh-vault branch, **once**, ensure the graph colour palette: run
  `python3 .claude/skills/lint/apply-palette.py --apply` (idempotent — a no-op if the shipped palette is
  intact; restores it if a fresh clone had `colorGroups` wiped by Obsidian). If it prints `APPLIED…`, tell
  the user to reload Obsidian with the graph view closed. This runs **only** here (registries missing),
  never on a normal ingest. Then proceed.
- **`wiki/index.md`** → add each new page under its type heading (Sources / Entities / Tools / Models /
  Benchmarks / Concepts / Syntheses / …) with a one-line desc; sections are **thematically clustered,
  not alphabetical** — place the new line beside its nearest relations, not at the section tail.
  **Mechanism: anchored `Edit` (or append)
  per heading — NEVER a whole-file read-modify-write** (a rewrite writes back a stale snapshot and
  silently drops entries a concurrent session added; CLAUDE.md §5, incident 2026-08-23).
- **`wiki/log.md`** → append **via shell** (`cat >> wiki/log.md …`; never Read the whole file — it grows unbounded):
  ```markdown
  ## [YYYY-MM-DD] ingest | <short title>
  - **Changed**: created [[..]], [[..]]; updated [[index.md]]
  - **Converted**: <original> → <stem>.md via markitdown   (omit if source was native .md)
  - **Depth**: <tally, e.g. research 2 · standard 9 · concise 1>   (note the range if it was narrowed or pinned)
  - **Confidence**: <level(s) assigned, e.g. high>   (note any override of the §4.6 default)
  - **Conflicts**: none (or: conflict [[Page]], flagged/paused)
  - **Run**: <ledger run id>   (parallel runs also name lanes + models — §5 attribution)
  ```

### Step 6 — Sort the raw source (this vault's archive design)
Only after Steps 3–5 are confirmed done, **move** the source out of the `raw/` root into the
matching category subfolder (use `obsidian-cli` or a shell `mv`; **never edit file contents**, though you MAY
rename an unwieldy auto-generated clip filename to a clean kebab-case slug as part of the move):

| Signal | → destination |
|--------|---------------|
| arxiv / PDF / formal paper / report | `raw/2-papers/` |
| tweet / X status / LinkedIn / Reddit / thread | `raw/6-social/` |
| Substack / personal blog / newsletter | `raw/5-blogs/` |
| docs / reference / GitHub repo / gist / tool manual | `raw/4-webinfo/` |
| news / magazine / long-form web article | `raw/1-articles/` |
| meeting / personal notes | `raw/3-notes/` |
| video / podcast / audio / lecture transcript | `raw/8-transcripts/` |
| peer review / OpenReview page / rebuttal / meta-review | `raw/7-reviews/` |
| owner-authored original work (research outline / draft / paper / thesis) | `raw/9-originals/` |
| a repo pack (`repo-pack` engine) of the owner's OWN repository — a project-store snapshot; authorship outranks form, so never `4-webinfo/` (tie rule, 2026-09-07) | `raw/9-originals/` |
| none of the above / deprecated | `raw/archives/` |
| confirmed duplicate (ignored / not useful) | `raw/duplicates/` |

**If the source was converted in Step 0, move the original AND its converted `.md` together** into
the same subfolder, so they stay paired and the `sources:` links remain valid. After moving, the
`raw/` root should contain only still-unprocessed files.

### Step 7 — Self-check (leave the wiki lint-clean)
Before reporting done, verify your own output so a later `/lint` would find nothing to fix:
1. Every page you created/updated is registered in `index.md`.
2. Every `[[wikilink]]` you wrote resolves to a real page — or you created that page.
3. Every page you created has a `## Related` section and ≥1 inbound link from another page (no orphans).
4. Each `sources:` path points to the file's **post-sort** location.
5. Every page you created carries a valid `confidence` (except `map`), assigned per §4.6, and every page you created **or updated** carries today's `audited:` stamp (§4.6 write-time self-audit — an update re-checks the badge, not just the content).

Fix any gap immediately. Scope this to the pages you touched — don't re-scan the whole wiki (efficiency).

### Step 8 — Report the new pages + depth + confidence (for the user to check)
After the self-check, surface a short summary so the human can review the agent's two judgement calls —
**how deep** each source was compiled and **how far** each page is to be trusted. List each page **created
or updated** with its `confidence` (add a word of basis for any non-obvious one — an `authoritative`, or a
`low`/`very-low`), and give every **source** its depth with the locator that justified it (Depth). Invite
the user to re-grade either; both are one-line changes. Example:

```
Ingested 3 sources → 11 pages (range: all three)
Depth:
- [[some-paper-slug]]    — research  T1 (Table 3 ablations) · T2 (calibration, About Me)
- [[some-docs-slug]]     — standard  T1 no (no original results)
- [[some-tweet-slug]]    — concise   ¬T3 (both tools already have pages)
Confidence:
- [[some-paper-slug]] — authoritative  (peer-reviewed)
- [[Some Concept]] — medium
- [[Some Entity]] — low  (single promo source)
Suspect conversions:
- raw/2-papers/some-paper.md — scope pdf · run-together 12.3 % · long-run 31.8 /1k · short-lines 1.0 % · recovery n/a → flagged: on its source page; standard depth
- raw/4-webinfo/some-api-docs.md — scope other · long-run 8.7 /1k (identifiers in the prose) → read, not flagged
Run: run-20260827-2330-a1 · 14 ledger events · closed
Re-grade a depth or a confidence and I'll fix it.
```

`Suspect conversions:` lists every conversion the Step 0 scorer (3c) read `suspect`, with its scope and the
measures from its verdict line, and says whether it was flagged (scope `pdf`, or a 3b `COLLAPSED`) or read and
left unflagged (scope `other`); a run with none writes `Suspect conversions: none`, so the absence is a
statement rather than a silence. A depth cell with an empty locator is a defect — go back and name the evidence, or drop a rung. To
**re-grade a depth upward** later, re-run `/ingest --research <sorted path>`: the de-dup pre-flight
recognises it as a deeper-depth request and takes the UPDATE path.

**Completion gate:** an ingest is not done until this report — the depth lines, the confidence lines
**and the `Run:` ledger line** — has appeared in the reply. Deliver it in
the same reply that declares the run complete — never deferred to a later turn, and never displaced by
the self-check or other verification running long. A batch run reports every page of the batch in one
table; an interrupted run reports the pages compiled so far at the point it stops. If zero pages were
created, one line saying so satisfies the gate.

## Hard constraints
- **Pace via the Pacing section** (default = `auto`). Keep the human in the loop for conflicts and
  large/uncertain batches; don't ask permission for small, low-risk, on-topic batches.
- **Every run keeps a ledger** (Run ledger): `run_open` → checkpoints → `run_close`, evidence-only,
  disk is truth. The Step 8 `Run:` line is part of the completion gate.
- **Parallel mode never spawns without the owner's go** on the echoed spawn record; lanes emit claims
  for shared-type pages and never sort — the head merges, sorts and closes the run.
- **Never** modify or delete the text inside an existing raw file. The only permitted `raw/` writes
  are *relocating* a file (Step 6) and *adding* a MarkItDown-converted `.md` beside its original (Step 0).
- Convert every non-`.md` source with `markitdown` before reading it; never guess a binary file's contents.
- Every wiki page must have a `## Related` section (no orphans).
- Every wiki page (except `map`) carries a `confidence` — assign it per CLAUDE.md §4.6 (free, since you've already read the source).
- **Every source page carries a `depth`** — decided *after* the read, inside the run's authorised range, never from filename/folder/length/markers (Depth). Never backfill it onto older pages.
- After ingesting, **report the created/updated pages with their depth + locator and their `confidence`** so the user can review and re-grade — a completion gate: no done-declaration without it (Step 8).
- **Refresh on write:** the pages you created/updated refresh per the `qmd-search` contract — a turn-end hook where installed, inline only where not; a no-op when qmd is dormant.
- Entities/Concepts = Title Case filenames; Sources/Syntheses = kebab-case.
- Write everything in **British/UK English** (US spelling only inside verbatim quotes, proper nouns, or code).
- Don't fabricate. Mark uncertain claims `unverified` and cite the source.

> **Standing derivative**: `output/user-notes/gather-ingest-quick-reference.md` — a change to this skill's user-facing workflow (commands, flags, gates, report shape) updates that note in the same pass (§2 output contract).
