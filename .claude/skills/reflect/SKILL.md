---
name: reflect
description: >
  Sweep the current conversation for things worth keeping — knowledge and insight, working context
  (decisions, directions, preferences), method lessons, framework defects — and propose where each
  should be recorded, then write only what the owner approves. The test is future performance across
  ALL the owner's work (research, writing, funding, life), never framework development alone; an
  intuition the owner states counts. Defaults to the unrecorded essentials — the top few, load-bearing items, with the rest
  listed one line each; `--all` lifts the cap. Use ONLY on an explicit instruction: /reflect, "capture what we learned", "reflect on
  this session", "store the lessons from this". NEVER runs automatically and never fires from
  passive context. It is a SECOND lane beside the agent's ordinary in-flight filing, which is
  unchanged: this is the owner's own trigger for what that lane missed. Preview-and-approve every
  run; opt-in `--yes` writes only inside wiki/ under a create-and-append rule. `--cross
  <transcript>` runs the same bar over ANOTHER session's transcript via a read-only reflector
  lane (cross-reflection; see its section below).
user-invocable: true
---

# reflect — capture what a session learned, on the owner's word

The agent already files findings as it works — the in-flight lane is real and measured (see
`wiki/developments/reflect-skill-design.md`). **That lane is unchanged and ungated.** This skill is the *second* lane: an explicit trigger the owner owns, for the
times the first one did not fire. It removes model-dependence from the **trigger**, not from the quality
of the harvest — a weaker model still finds less; it just no longer has to think of looking.

**The test is always future performance, across everything the owner does** — research, writing, funding,
work and life as much as framework development. A hunch about a research direction, a preference learned
from how a draft was received, a decision and the reason behind it: each can be worth more to a future
session than any number of process notes. Do not read "essential" as "technical".

## Trigger — explicit only
`/reflect`, or an imperative addressed to the agent: "capture what we learned", "reflect on this
session", "store the lessons from this". **Passive context never fires it** — not an `<editor_selection>`,
not an `@`-mention, not a line in `IDEAS.md`. If a phrase like "we should remember that" appears in
passing, surface it and ask; do not start a run.

**Non-interactive runs** (headless, scheduled) propose and write nothing, unless `--yes` is set, in which
case the path rules below still bind.

## Pipeline

### Step 1 — Read the register's open entries
`wiki/developments/known-issues.md`, `## Open` only. Two reasons, both intrinsic: a candidate defect must
not duplicate an entry already there, and a lesson from this session sometimes **closes** one. Surface an
entry to the owner **only when a candidate touches it** — do not print the list every run.

### Step 2 — Sweep the visible conversation, and say how far it reaches
Collect candidates of four kinds. The first two matter most often; the last is the narrowest.
- **Knowledge & insight** — something established, corrected or discovered here that the wiki does not
  hold: a correction the owner made, a finding from a probe run in the conversation, a conclusion drawn
  across pages that sits on none of them, or **a stated intuition worth testing later**.
- **Working context** — how the owner works and where they are going: a decision and its reason, a
  direction taken or abandoned, a priority, a standing preference, a constraint that will recur. Usually
  `wiki/user/`, and usually invisible to any source-driven route.
- **Method / process lesson** — something about how to work that would change a future session.
- **Defect** — a fault in a framework surface (the schema, a skill, a script).

**Horizon, measured every run.** Earlier turns may have been compacted out of context, so measure the
boundary against the on-disk session transcript instead of asserting it: `echo` a fresh nonce in shell,
then grep for it **in a later call** under the harness transcript directory (the transcript records a
call's result only after that call returns, so the same call cannot find its own nonce — the first
probe of 2026-09-07 printed 0 for that reason and was re-run) (Claude Code: `~/.claude/projects/<vault path,
separators as dashes>/*.jsonl`). The single file containing the nonce IS this session's record — the
transcript logs the probe itself, which is the positive control (CLAUDE.md §11). A **negative** control here needs a needle the transcript has not already recorded: assemble it at runtime rather than typing the literal (a typed literal matches because the command logging it is part of the medium), or state the baseline count of self-hits. A control that fires against its own stated expectation is repaired, never narrated past (2026-09-03: one printed `exit=0` where it declared `1 = correctly none`, and the run continued). Count its human turns
with a filter **verified against the visible span** (every visible human turn must be matched; beware:
tool results, harness task-notifications AND Skill-tool injections (`isMeta: true`, opening "Base directory for
this skill") all carry `"type":"user"` and must all be excluded — the notification miss overcounted 9 turns as
27, №103 cross-reflection P1, 2026-08-28; the injection miss counted 4 turns for 3, cross-reflection R1 of session
`80de6d8b`, 2026-09-05), and report
`visible k of N recorded turns`. **Fallback** — no transcript, no unique nonce match, or a filter that fails its own check →
the unmeasured form: name the earliest visible turn and state that the boundary carries no control
this run. **Never report "nothing to capture this session"** — only "nothing in the visible span".
On `--full` (explicit request only), read the compacted-out remainder from the transcript file itself,
declaring the token cost before reading.

### Step 2b — Usage and waste (development runs only; owner-added 2026-09-05)
Runs when the session ran a development item: the visible conversation shows the owner invoking an
IDEAS todo or naming a `wiki/developments/` page as the plan of record, or a spawn record names this
session (`grep -l <sid> ~/.llm-wiki/spawn-records/run-*.jsonl`, printed with the store's file count and
a grep for another record's known session id as its §11 controls; no store or no session id → say so and
use the conversation test alone). Otherwise print `usage: n/a (not a development run — <the test that
failed>)` and skip.
- **The billed line at each boundary.** From the run's boundary records — the spawn record's
  `phase-boundary` and `decision` events and the hand-off document's trace rows (delegate skill §4) —
  list the billed line at every item or phase boundary, per session as the meter printed it
  (`fable-share.py --session <sid> --lanes auto`, §2a), then the run total as a shown sum of those
  session figures. Records with no boundary figure → meter the session once now and say the boundaries
  carried none; an `unmetered` or `unbilled` exit is quoted as printed, never read as zero or estimated.
- **One waste table, three classes** (the owner's, from the 2026-09-04 live case,
  `wiki/developments/hands-off-live-case-2026-09-04.md`): `| Item | ≈ $ or idle min | Kind | Fix and
  where it lands |`, keyed on what the spend produced — **real** = its output was lost or unused (a lost
  lane, a wrong probe, a stall); **arguable** = its output was used, but a better brief, order or spec
  would have bought it cheaper; **structural** = a cost of the chosen shape (the contract prefix, a
  rewrite after a long hold). Each row names its event (Step 3 clause 1) and carries its figure with its
  derivation — a meter total or per-agent row, a lane's `lane-closed` cost, or `≈` with the arithmetic
  beside it — else `unmeasured`, never a bare number. Its fix lands in exactly one of: a phase of a named
  plan of record, a `known-issues` entry (§12 format), an IDEAS todo (a proposal — nothing enters
  IDEAS.md unless the owner says "queue it", Step 8), or `accepted` (a cost of the shape, or a fix
  already shipped, named). No waste found → one row saying so and naming what was searched (the billed
  line's `rewrites` and reason tally, the trace's idle minutes and denials), since a zero-findings claim
  needs its control (§11).
- **The waste fields are read, not recalled (2026-09-05).** Each `phase-boundary` event carries
  `idle_min`, `over_cap_reports`, `denials`, `respawn_cost_usd` and `rewrites`; list each as its own
  row with the figure the field holds and the event it came from — the field is the source, never a
  memory of the run — and where an event omits one, write `field absent` rather than `0`, since a
  missing field and a measured zero are different claims. The run's `gate` events carry the head's
  context at each item, so context per item is read off them as the delta between consecutive gates
  rather than estimated; a run with no `gate` events says so and drops that column.
- **A candidate like any other.** The table takes Step 3's bar, the 5b critique and the Step 6 preview,
  and its destination is the run's record page in `wiki/developments/` (Step 4). The `--yes` rules below
  apply unchanged: that page is never written under `--yes`, so an auto-approved run reports the table
  and says it waits for the owner.

### Step 3 — Apply the bar, then keep only what matters
**The default is deliberately narrow: the unrecorded essentials, not everything noticed.** A long
session generates dozens of small observations; proposing them all buys the owner a review chore and
buries the two things that mattered.

A candidate survives only if all three hold:
1. **Evidenced** — it points at something that actually happened here: a command and its output, a
   correction, a file read, a review, **or the owner stating a judgement, hunch or preference**. The
   owner voicing an intuition *is* the event, and it is recordable — marked as a hypothesis and graded
   honestly by §4.6, not discarded for lacking proof. What fails this clause is *the agent's* own
   generality with no event behind it.
2. **Not already recorded** — check *everywhere* it could already live before proposing it: the
   destination page, `known-issues.md`, the relevant `developments/` doc, and a `grep` of `wiki/` for
   the claim. **Open every hit.** A `grep -l` answers "does this string occur", never "is this idea
   recorded", and the filename it returns often looks unrelated to the candidate — on 2026-09-03 a dedup
   hit was the one page already carrying the candidate's entire argument, and it went unopened, so the
   candidate was proposed as novel. A hit that is not opened leaves the candidate *unresolved*, not clear. **Stamp each dedup probe with the time it ran (2026-09-06):** a reflect run over a session that
   edited the vault is checking a moving surface, and a candidate can be fixed by the same run that
   raised it — in the N128 run two of four were, and the Step 5b critic spent its budget refuting
   defects that no longer existed. The stamp is what lets a later reader tell a stale candidate from a
   wrong one. This is also what stops repeat runs re-proposing the same thing; there is no session
   cursor, and none can be built (the log carries no clock). Check against the files on disk, never the copy of
   `CLAUDE.md` or `CUSTOMISATION.md` injected into your context: a helper agent's injected copy is the
   head's session-start snapshot, and on 2026-09-05 a reflector's copy lacked four edits made that day.
3. **Load-bearing** — one decidable question: *would a future session do the work worse without it?*
   That covers both halves — repeating a mistake, redoing work or answering wrongly, **and** missing a
   better approach, a known preference, or a direction already decided. If the honest answer is no, it
   is an observation, not a lesson. "Interesting" is not the bar; "would change what a future session
   does" is.

**Then rank and cut.** Order the survivors by that third test and **propose the top 5 at most**. List
every remaining survivor as a **one-line "seen, not proposed"** with its reason, so nothing is dropped
silently and the owner can pull one up. Where several candidates are variations of one underlying point,
merge them and propose the general form once — three symptoms of one fault are one lesson.

**Widening is explicit.** `--all`, or an instruction like "capture everything" / "don't filter", lifts
the cap and proposes every survivor. The bar itself never relaxes: an unevidenced or already-recorded
candidate is still not proposed, whatever the flag.

**Self-conduct.** A lesson about the agent's own behaviour is a candidate only if it **names the external
mechanism that caught it** — a printed control, a failing test, an owner correction, a reviewer. An
unwitnessed self-assessment has no witness and does not survive step 3.

**Probe discipline (2026-08-27).** A dedup grep never carries an exclusion filter — one filtered out the
very record that made a candidate redundant, manufacturing false novelty. And a probe's control is never
the claim under test: pair every 0-hit with a positive control that hits on the same surface (§11),
phrased in the subject's own vocabulary — a path or name as the checked text spells it, never as the
checker would spell it: a control in the checker's spelling read 0 of 4 on a live dual-name path
(VER-130A, 2026-09-07) while the subject's spelling hit 4 of 4.

### Step 4 — Route it
In priority order. Say which rule sent it there.

| Destination | When | Note |
|---|---|---|
| A **rule** — `CLAUDE.md` or a skill | The lesson generalises, **and** it can tighten or replace an existing line | Contracts and skills are the surfaces actually read. But a rule that only *adds* a line feeds the always-on ratchet: report the byte delta and prefer a tightening |
| A **wiki page** (`concepts/`, `entities/`, `tools/`, `models/`, `benchmarks/`, `user/`) | Domain or research knowledge | New page or an addition to an existing one. `user/` is the owner's to curate — propose, never auto-write |
| A **`notes-*` synthesis** | A reusable procedure or a cross-page conclusion | `type: synthesis`, kebab-case, `notes-` prefix, `## Sources Used`, and `sources:` in frontmatter |
| `known-issues.md` | A framework defect out of scope to fix now | Entry format per §12 |
| The run's record page in `developments/` | The Step 2b usage-and-waste table of a development run | An append to the page holding the run's trace or design; owner-approved, never under `--yes` |
| **Discard** | Fails the bar, or is already recorded | Report it as discarded and why — a silent drop reads as "nothing found" |

**Contradictions.** A candidate that conflicts with something a page already claims never silently
overwrites it. Add a `## Conflicts / Open Questions` block keeping both statements and contrasting them
(CLAUDE.md §4.4), and say so at the preview. This is the common shape for an owner correction that
disagrees with a sourced claim.

**Sources.** A conversation here almost always rests on wiki pages, so cite them: `## Sources Used` plus
`sources:` in frontmatter. Where a finding is genuinely original with nothing prior to cite, that is a
legitimate page — say so plainly and let §4.6 grade it.

### Step 5 — Grade and attribute
**No confidence rule of its own.** Apply CLAUDE.md §4.6 to the evidence, not to who said it: the owner's
own work is `high` by default and drops if they state uncertainty; an inference from an `authoritative`
page inherits that standing; an extrapolation beyond the evidence is `very-low`. Record **provenance** in
the page — what the claim rests on — so a later reader can tell.

### Step 5b — Independent critique (default-on)
Before the preview, brief a subagent to **refute** the candidate table: per candidate — is the evidence
a real event in the recorded span, is it genuinely unrecorded (re-run the Step 3 destination checks),
is it load-bearing, and does a self-conduct item name a true external witness? A refuted candidate
moves to "seen, not proposed" with the refutation as its reason; an arguable refutation stays proposed
with the objection attached. **A refuted candidate's defensible residue is a NEW candidate**: it
re-enters at Step 3 and waits for the Step 6 preview like any other — never a direct write, however
broad the standing go (the missing salvage path let two refuted items ship pre-preview, №103 session,
recorded 2026-08-28). This is the bounded per-run witness self-reflection lacks (the
cross-session form is `## Cross-reflection` below). `--no-critic` skips it and the preview says "critic: skipped"; where the
harness offers no subagent mechanism, say "critic: unavailable". **The critic filters proposals; it
never approves writes — approval still terminates at the owner.**

### Step 6 — Preview, and get approval
One table, always, before any write:

```
Reflect — visible from turn N ("<first few words>"); earlier turns may have been compacted.
| # | Candidate | Evidence | → Destination | Tier | Edit |
Seen, not proposed (3): <one line each, with why it did not make the cut>
Discarded: 2 (already recorded ×1, no event behind it ×1)
Proposed rules: 1 · always-on cost +180 bytes
```

**The preview leads with the head's recommendation** (owner instruction 2026-09-06): one line per
item — approve · strike · defer, each with its one-clause reason — printed before the approval
question, so the owner can accept in a word; the recommendation is the head's, never the critic's,
and it changes nothing about who approves. **The line is style-invariant** (owner ruling 2026-09-07:
a style chooses the form of an obligation, never its presence): under `brief` and `shortest` it
compresses to one clause per item (`1 approve — repeat`, `2 strike — already recorded`), never to a
bare verdict in a column and never absent; a style's `Test:` bounds content, never an obligation's
presence (CUSTOMISATION `## Output styles`). The Stop-hook check that logs its absence, warn-only,
is recorded on `wiki/developments/per-reply-contract-enforcement.md` (`reflect-preview`).
The owner approves per item ("1 and 3", "all but 2"). **Nothing is written without approval**, except
under `--yes` below. One exception is a duty, not a licence: a defect the run itself finds is registered
under CLAUDE.md §12 with the pass whatever else is approved, listed in the preview as `register (§12)` so
the owner can strike it (owner-approved, cross-reflection XR-2, written 2026-09-05 20:27 BST).

### Step 7 — Write, log, report
- Write only the approved items. Every new page gets `## Related` and an `index.md` entry (§4.4, §5).
- **Log by what changed, never by which command ran**: `synthesis` for knowledge written into the wiki,
  `framework` for a contract or `developments/` change, nothing for a register append (§12 exempts it).
  A run that changes nothing logs nothing.
- Report what was written, where, at what tier, and what was discarded.
- **Every write carries its clock time** (owner instruction 2026-09-05): beside the date, the local time of the
  write and the run or lane id — on a register entry's `Where observed` line, in a rule addition's dated note,
  in an appended block's heading — so a parallel session's earlier fix or later edit can be ordered against it;
  an agent that finds the item already fixed reads the two stamps and keeps the later state.
- **A fix handed to another session** is recorded on its register entry with the taking run and that
  run's gate state, clock-stamped; if that gate later refuses, the entry reverts to open with the refusal
  dated, so a claimed-but-gated fix never reads as done (cross-reflection XR-2, written 2026-09-05 20:27 BST).

### Step 8 — Recommend, don't queue (owner-added 2026-08-27)
Close the report with next-action recommendations derived ONLY from what this run shipped, corrected or
left undecided — an open decision surfaced, a stale premise fixed, a watch worth setting. A short ranked
list: action · whose decision it is · when it becomes urgent. Where a written page ships, mirror it as a
`## Next` section **worded as recommendations with their reasons** — findings, never instructions to
future agents (§2.2 discipline applies to pages as to reports). Nothing self-executes; nothing enters
IDEAS.md unless the owner says "queue it" (normal IDEAS rules then apply). A run with nothing genuinely
open recommends nothing — no forced next.

## Cross-reflection (`--cross`) — one agent reflects on another's session

**Trigger, explicit only:** `/reflect --cross <transcript-path | session-id>`, or the owner accepting
a workflow-end proposal (the delegate skill §5 owns that policy: the head may propose once, cost
declared first, never auto-run; the run's log entry records whether one was proposed — `proposed`
or `not eligible`, 2026-08-30 — an accepted proposal being traced by the cross run's own entry). **Target:** a finished session's transcript, or the current
session's transcript as of spawn — the live-write race is declared in the report; for the current
session (a self-cross run) the head freezes a `/tmp` copy of the transcript BEFORE it writes the run
record's controls line and grants the copy alone, because the live file logs that very write and a
live-file grant voids the instrument check (2026-09-06, lane XR-PUB2, known-issues); the pilot tested
the finished case only (dated caveat: `wiki/developments/cross-reflection-pilot.md`).

**Mechanism.** The head agent spawns a READ-ONLY reflector lane (delegate skill,
`templates/brief-reflector.md`) that applies Steps 1–5, except 2b (head-only), to the target transcript. The lane extracts
the transcript's human turns and assistant prose (tool-result records excluded) to /tmp and reads
that extraction in full, reporting "read k of N turns". **Horizon control** (replaces Step 2's
nonce, which only proves one's *own* session): target file exists and is non-zero; human-turn count
verified against the extraction; coverage declared, never claimed complete.

**Witness ruling.** Proposer ≠ behaving agent, so a transcript-grounded observation (file + line)
IS the external witness Step 3's self-conduct rule demands — cross mode is where unwitnessed
conduct faults become recordable.

**Scope v1:** the head transcript only; lane-internal events appear only as the lane reports
embedded in it. **Output:** findings, never writes — the FULL named candidate table including every
discard with the page that killed it (an aggregate count hides the dedup evidence). Step 5b is not
re-run on cross output — duplicative cost, since the head's re-verify widens instead: dedup checks
AND a re-read of each cited transcript span before the preview. Owner approval stays line-by-line;
the head writes approved items under Step 7, each write clock-stamped. **`--yes` never applies to cross runs.** **Qualified 2026-09-06 (owner ruling):** it does apply to the hands-off boundary form, where a reflector lane reads the head's OWN session at the head's request — the lane proposes, the head re-verifies each proposal (dedup, evidence) and writes only within the `--yes` path bounds (design D36).

**Hands-off boundaries (2026-09-05, hands-off design D36; `--yes` admitted for this form by owner
ruling 2026-09-06).** At every phase boundary of a hands-off run the head does not run this skill in
its own context. It builds the lane's inputs with `handsoff.py reflect-inputs --run R --session SID
--out DIR` (a directory outside the store): the extraction of its own transcript (the human turns and
the assistant prose, a count file beside them), Step 2b's table rendered from the run record alone
(every figure read from a field, none recalled, so Step 2b's head-only rule is satisfied by the
primitive rather than by the head's memory), and a filtered copy of the record that carries no
control the lane is meant to be blind to (the spawner pre-registers controls with `ledger --phase
controls-LANE`, which the copy drops). It then spawns a reflector lane (headless, `lane.py`, fenced
Bash, the routing's model) granted DIR alone beside the wiki and this skill, and it receives the full
named candidate table including every discard. Before applying any item the head re-verifies it
exactly as this section prescribes: the dedup checks and a re-read of the cited transcript span. With
`--yes` the head then writes the items that pass, inside the `--yes` path bounds below and nowhere
else (create-and-append inside `wiki/`; never `developments/`, `known-issues.md` or any file outside
the wiki), logging each write as `synthesis`; every item the bounds exclude, and every item that
fails re-verification, goes to the run's morning report with the full named table for the owner's
line-by-line approval. Without `--yes` the head applies nothing and the whole table goes to the
morning report. A cross run over another session's transcript stays outside `--yes` whatever the run.

## `--yes` — opt-in auto-approval (off by default)
Set per run (`/reflect --yes`) or as a standing owner setting. It means **writing without waiting, never
writing without telling**: the step 6 table and the step 7 report still appear.

Bounded **by path, not by judgement**:
- **May**: create pages in `wiki/concepts/`, `wiki/entities/`, `wiki/tools/`, `wiki/models/`,
  `wiki/benchmarks/`, `wiki/syntheses/`; **append** to an existing wiki page or to `index.md`.
- **Never**: `wiki/user/` (the owner curates it, CLAUDE.md §1) · `wiki/developments/` and
  `known-issues.md` (a framework surface, and a register append logs nothing, so an unapproved one would
  leave no trace at all) · `CLAUDE.md`, `.claude/**`, `CUSTOMISATION.md`, `MANUAL.md`, `README.md` ·
  anything outside `wiki/` · **rewriting** any existing page — appends only.
- Every auto-approved write **is logged**, so it is always traceable.

> **One stated judgement call.** `wiki/syntheses/` also carries `query` Step 5's ask. The owner's standing
> opt-in *is* the consent that ask exists to collect, given in advance, and it binds **only reflect's own
> writes** — `query` keeps asking when `query` runs. This is stated here in plain sight rather than
> applied silently.

## Hard constraints
- **Explicit trigger only.** Never automatic; passive context never fires it.
- **Never claim a complete sweep.** Only a bounded one, with the boundary named.
- **Never invent a lesson.** Every candidate carries the event it came from.
- **Default narrow.** The unrecorded essentials only, at most five, the rest named in one line. Widen
  only on an explicit instruction; never widen the bar itself.
- **The in-flight lane is not weakened.** This is not a place to defer to: if something is worth filing
  while working, file it then, exactly as now.
- **Approval terminates at the owner.** A subagent may propose; it may never approve.
- Write in British/UK English.
