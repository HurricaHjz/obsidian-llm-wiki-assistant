---
name: lint
description: >
  Health-check the Obsidian wiki — the "static analysis" pass for a knowledge base. Use when the
  user runs /lint, /health, /scan, or asks to "check the wiki", "find broken links", "clean up the
  wiki", or "find gaps/orphans/conflicts". Read-only scan that reports dead links, dead media
  embeds, orphan pages, pages missing from index.md, unresolved knowledge conflicts, live links
  leaking into the attic, wikilinks from shipped skill or agent files into wiki pages that never ship, and the
  count of pending `flagged:` freshness flags (≥5 suggests a deep-lint). Also restores the graph colour
  palette on request (on-demand only, never on a routine scan). Proposes fixes but only applies them
  after the user confirms.
user-invocable: true
---

# lint — knowledge-graph health check

## Goal
Find the rot that accumulates as a knowledge base grows: **dead links, orphans, unindexed pages,
unresolved conflicts.**

## When to run (and when not)
**Don't lint routinely after a normal ingest** — ingest/query leave the graph integrity-clean by
construction (CLAUDE.md §6). Run lint for *drift* (manual edits/renames/deletes in Obsidian, external or
OneDrive/git sync changes) and periodic *discovery* (emerging gap pages, cross-corpus contradictions,
stale claims).

**Scope boundary:** confidence coverage, staleness scoring, and online-source freshness are **not**
lint's job — they live in the heavier, ~monthly **`deep-lint`**. Routine `/lint` stays cheap and never
reads pages for confidence or fetches anything.

## Triggers
`/lint` · `/health` · `/scan` · "check my wiki" · "find broken links / orphans / gaps".

## Pipeline (read-only until the user approves fixes)

### 1 — Index consistency (one scripted check)
Run `python3 .claude/skills/lint/check-index.py --vault .` (exit 0 = the probe ran, findings or none;
2 = broken premise). It compares `wiki/index.md` with the pages on disk and prints three lists with their
counts: **unindexed pages** (on disk, registered by no `- [[…]]` entry), **dangling index entries**
(registered, no page on disk) and **duplicate entries** (the same target registered twice). The rules are
deep-lint `audit-pools.py`'s, copied so a reader can check them against it: resolution on the basename with or without
`.md`, `index.md` and `log.md` excluded as pages, and a page's frontmatter `aliases:` counting as a
resolution on both sides (one deliberate departure from audit-pools, which aliases the dangling side only). It
prints `SCANNED: <pages> pages · <entries> index entries` as its own positive control (§11): a root it cannot
scan ends in `PROBE FAILED` and exit 2 before any list prints, so a clean result always carries non-zero counts.
Copy the three figures into the report — never re-derive them by hand. Shared stems are printed as information, not a finding.

### 2 — Link health (one shared script — the single source of truth for link rules)
Run `python3 .claude/skills/lint/check-links.py` (exit 0 = clean, 1 = findings; deep-lint's
structural pass uses the same script). It applies the codified rules so scans never re-derive them:
code spans / fenced blocks / HTML comments are not links; frontmatter `aliases` resolve; vault-path
and root-doc targets resolve; `wiki/log.md` is exempt as a source (append-only history); and **media
embeds `![[name.png|pdf|…]]` are checked against `assets/`** — a missing target is a **dead embed**,
reported separately (they are checked, not skipped). The script prints its scan totals as its own
positive control (§11): zero findings with zero links scanned is a broken probe, not a clean vault.
- The same script resolves each page's frontmatter `sources:` entries against disk and reports **dangling
  sources** separately from dead links: one line per page · path, with `SOURCES SCANNED:` as that arm's
  control. A URL, prose provenance (`email: …`, `session: …`) and an entry that declares its own deletion
  (`path (deleted YYYY-MM-DD)`) are counted, never flagged — provenance written as prose is legitimate. An entry the
  parser could not read prints as `(empty or unparsed sources)` inside the same block: read it, since it is the
  parser's own gap detector, not a dangler. A `~`- or `/`-led entry is provenance **outside the vault** (a run
  store, a home directory): resolved with `expanduser`, it prints under `OUT-OF-VAULT SOURCES: n present | m missing`
  — a missing one is a finding in that bucket, never a dangling vault path (register entry 2026-09-08: two false
  positives per run until then).
- Beside it, `python3 .claude/skills/lint/check_flag_admissions.py --vault .` (exit 0 = clean, 1 = findings, 2 =
  premise: not a vault root, or no `wiki/sources/`) lists every page under `wiki/sources/` whose prose or frontmatter
  comment **admits conversion damage** — the vocabulary `collapsed`, `lost inter-word spaces`, `inter-word`,
  `space-restored`, `run-together`, `run together`, `verbatim quotation is unavailable`, `lost every chart`, `lost
  every figure`, `lost every table`, `charts lost`, `figures lost` — while the page carries no **conversion** flag: a
  `flagged:` line counts only when its own text carries `conversion` (`source conversion suspect …`), so a flag about
  something else never masks an admission. A damage admission belongs in the flag channel (ingest Step 0 scores every
  file carrying `converted_by:` and records a `suspect` one in scope `pdf` as `flagged:`), which is the only channel deep-lint reads;
  the fix for a hit is a `flagged:` line on the page, never a rewrite of the prose — and the flag's end is ingest 3c's
  terminal state: a repaired conversion scored `clean` in `sources:` plus the dated Provenance sentence, which the
  probe counts under its `RESOLVED:` line (an admission that also names a `repaired conversion`), never as a finding.
  It prints its own in-memory controls (a page that must fire; its conversion-flagged twin that must not; a twin
  flagged for something else that must; a resolved twin) and the count scanned; an ordinary use of `collapsed` in
  prose is a false positive to read and dismiss in the report, not to silence in the script (register entry
  2026-09-08, ingest Step 0 conversions, and the folds of the same day).
- Every script in this directory refuses, in vault mode, a root that is not a vault (no `raw/` + `wiki/`): one `PROBE
  FAILED: <root> is not a vault root (no raw/ or wiki/)` line on stderr and exit 2, so a wrong root can
  never read as a clean vault scan (the 2026-08-26 standard; the register entry of 2026-09-06 that closed it
  here; the file-mode forms `anomaly-lister --pages` and `tier-cap-check --verdicts` keep their own checks). Every
  Python script and `check-qmd-registry.sh` take `--vault ROOT`; an unknown flag is refused with exit 2, never
  read as the root.
- Orphans are scripted too: `python3 .claude/skills/lint/check-orphans.py --vault .` reports a page with **no inbound links** from any other page as an **orphan**, exempting `index`, `log`, and `maps/` pages (Maps of Content are navigational entry points, not orphans). It applies this directory's link rules, prints its own inbound-link control (zero orphans with a zero control is a broken probe, §11), and additionally lists the pages `index.md` alone reaches — information, not a finding.
- Two further helpers in this directory serve deep-lint and the routing design's verify leg, not routine lint: `tier-cap-check.py` (§4.6 type caps and boundaries; a documented override on the `confidence:` line is reported separately, never as a violation) and `anomaly-lister.py` (page-visible anomalies: open conflict blocks, `flagged:` lines, thin-page notes, `unverified` markers). Suite for all three: `bash .claude/skills/lint/test_lint_phase2.sh`.
- **Routing (M0, 2026-09-02; residue closed 2026-09-07):** every lint check is a script; the agent reads reports and never re-derives a scripted count (orphans became `check-orphans.py`, Phase 2 of the routing design; Step 1's index-consistency comparison became `check-index.py`, the last hand comparison in this pipeline).

### 2b — Pending freshness flags (count only — reconciling them is deep-lint's job)
`grep -rl "^flagged:" wiki --include='*.md' | wc -l` — with the engine control
`grep -rl "^confidence:" wiki --include='*.md' | wc -l` (must be >0, proving the probe ran).
Report the count; at **≥5 flagged pages**, suggest running `/deep-lint` (the adaptive-cadence
signal from `wiki/developments/deeplint-scalable-maintenance-design.md`). Never read or resolve
the flagged pages here — lint counts, deep-lint reconciles.

### 2c — Attic-leak check (filenames only — attic contents are never opened)
Live pages must never link into the attic (CLAUDE.md §2.1): Obsidian resolves wikilinks vault-wide,
so a surviving `[[link]]` to an archived note silently reconnects retired material and can pull a
query in. List basenames only — `find attic -type f -name '*.md'`, skip `MANIFEST.md` (the check
reads names, never contents; attic absent or empty → report "attic-leak: n/a"). For each basename
`b`, grep live wiki (excluding `wiki/log.md`, append-only history) for the exact link forms
`"[[b]]" "[[b|" "[[b#" "/b]]" "/b|"` — plain-text mentions ("b (archived)") are the §2.1 sweep
style and are NOT findings. Any hit is a **leak finding**: report it; the fix (owner-confirmed) is
re-sweeping to plain text per §2.1, or `/attic restore` if the page should live again. Control
(§11): the same pipeline against one known live page name must return >0 before reporting "no leaks".

### 2d — qmd registry guard (one scripted check; skipped silently when qmd is dormant)
`wiki/log.md` must stay out of the semantic index (CLAUDE.md §10) — embeddings key on a file's
whole-content hash, so every append re-embeds the whole timeline, and a hit invites an ~80k-token
`qmd get`. The exclusion lives in `~/.config/qmd/index.yml`, **outside the vault and outside both
git repos**, so it can disappear silently. Run
`sh .claude/skills/lint/check-qmd-registry.sh .` and copy its one line into the report verbatim.
The script carries its own §11 control (`index.md`, deliberately kept, must be listed) and reports
`PROBE FAILED` rather than "clean" when its own premise breaks. Exit 1 = finding; the fix is to
restore `ignore: ["**/log.md"]` on the `wiki` collection and re-run `qmd update`.

### 2e — Injection guard (names only — no skill or definition contents are read)
Third-party installers write into the roots the harness auto-loads, and anything landing there reaches
**every** session (Agent Reach's documented SKILL.md auto-install; two register incidents prove the
class: `wiki/developments/known-issues.md` 2026-08-21/22). **Two roots, four arms.** Skills are
**directories** under `.claude/skills/`; agent definitions are **files** under `.claude/agents/`, and
each is auto-loaded — a definition names a lane's model, tools and write scope, so an unsanctioned one
is the same exposure as an unsanctioned skill. The asymmetry is real: `ls` yields names in one case and
filenames in the other, so the `comm` inputs differ. Both diff against the same baseline,
`.claude/skills/lint/sanctioned-skills.txt` (its `-skills` filename is kept for compatibility; it is the
registry for both).
```bash
b=".claude/skills/lint/sanctioned-skills.txt"    # ships: vault skill names + agent definition filenames
hs="$HOME/.claude/skills/.sanctioned.txt"        # machine-local baselines, never shipped
ha="$HOME/.claude/agents/.sanctioned.txt"
[ -s "$b" ] || echo "PROBE FAILED: vault baseline missing/empty"            # premise guard, never "clean"
# vault skills (directories)
comm -13 <(grep '^vault:' "$b" | cut -d: -f2 | sort) <(ls .claude/skills | sort)
# vault agent definitions (FILES — list everything, do not filter to *.md: a stray file here is the finding)
[ -d .claude/agents ] && comm -13 <(grep '^agent:' "$b" | cut -d: -f2 | sort) <(ls .claude/agents | sort) \
                      || echo "agents-guard: n/a (no .claude/agents in this vault)"
# user-level roots
[ -d ~/.claude/skills ] || echo "PROBE FAILED: ~/.claude/skills missing"    # premise guard, never "clean"
[ -s "$hs" ] && [ -d ~/.claude/skills ] && comm -13 <(sort "$hs") <(ls ~/.claude/skills | sort)
[ -s "$ha" ] && [ -d ~/.claude/agents ] && comm -13 <(sort "$ha") <(ls ~/.claude/agents | sort)
```
Any name printed = an **unsanctioned entry** (finding: report it; the fix — owner-confirmed — is removal,
or a conscious baseline addition in the same pass that sanctions it). **Premise failures never read as
clean, each in its own way:** a missing/empty vault baseline reports `PROBE FAILED`; an absent
`.claude/agents/` reports `n/a` (a vault may legitimately have none, so absence is not a finding and not
a pass either); an absent user-level root reports `PROBE FAILED`; no machine-local baseline yet (fresh
machine) → report that root's current listing as info and propose seeding it after the owner reviews,
never a finding, never auto-seeded. Baseline entries missing on disk are info (drift), not findings.
§11 control before trusting any empty result: re-run **each** arm's `comm` with a known-absent name
injected into the disk side (`printf 'zzz-ctrl\n'`) and confirm it prints — one arm's control does not
vouch for another's.
(Deep-lint inherits this via its structural pass.)
- **Throttle check (delegate skill §2, 2026-09-02):** `python3 .claude/skills/delegate/throttle.py check` — each `DRIFT` / `MISSING` / `UNROUTED` / `DESCRIPTION-TIER` line is a finding (the fix is `throttle.py set <active>` for drift, a definition or routing entry for the other two, the range wording for a description); `PROBE FAILED` (unreadable `routing.json`, unknown throttle name, absent `.claude/agents/`) never reads as clean. The script prints its own §11 control (a planted-drift comparator) on every run.

**Register arm (2026-09-05; names only, both directions).** `wiki/developments/capability-register.md` lists every
user-level skill as one row (`| \`name\` |`) under `## User-level skills`; the directory and the register must agree:
```bash
reg="wiki/developments/capability-register.md"
[ -s "$reg" ] || echo "register-arm: n/a (no register page yet — a fresh vault; /adopt seeds it)"
[ -s "$reg" ] && rows=$(awk '/^## User-level skills/{f=1} /^## Plugins/{f=0} f' "$reg" | grep -oE '^\| `[a-z0-9-]+`' | tr -d '|` ' | sort -u) \
  && { echo "installed, no row:"; comm -13 <(printf '%s\n' "$rows") <(ls ~/.claude/skills | sort); echo "row, not installed:"; comm -23 <(printf '%s\n' "$rows") <(ls ~/.claude/skills | sort); }
```
Either list non-empty = a finding (the fix, owner-confirmed, is a row or an install, never a silent delete). Control before
trusting two empty lists: re-run with one real row name filtered out of `rows` and see it appear under "installed, no row".


### 2f — Customisation pairing (cheap greps — no preference content is judged)
The preference layer is two files: always-on `CUSTOMISATION.md` (core: contracts + default style/role
blocks + `customised`) and on-demand `CUSTOMISATION-definitions.md` (the other definitions; read on
switch). Core absent (fresh vault) → report `customisation-pairing: n/a` and skip. Checks:
- The `style` and `role` values in core's `## Settings` each have a matching `^### <value>` heading
  **in core** (the block-move rule keeps the defaults there). §11 control: the same probe must find
  `### customised` in core (it never moves) before any missing-heading finding — or an all-present
  result — is trusted.
- No `### ` heading appears in both files:
  `comm -12 <(grep '^### ' CUSTOMISATION.md | sort) <(grep '^### ' CUSTOMISATION-definitions.md | sort)`
  must print nothing. A hit = a duplicated definition (finding: propose removing one copy; the owner
  says which — never auto-edit their preferences). Note `### ` lines inside HTML comments (e.g. the
  generalist example) can surface here; a hit inside a comment is reported as info, not a finding.
- Definitions file missing while core exists → **warning** (switches beyond the defaults will run
  without their definitions): propose recreating it from the private backup or the template seed
  (the `mk_custom_defs` function in the shipped `setup.sh`). Never fatal, never auto-created.

### 2g — Shipped-surface wikilinks (one scripted check — the publish gate's test suite calls the same script)
Every `.md` under `.claude/skills/` and `.claude/agents/` ships with the public framework; a `[[wikilink]]`
in one of them that resolves in this vault but not in the published copy is dead for every installer — the
class the 2026-08-30 delegate-skill finding proved. Run `python3 .claude/skills/lint/check-shipped-links.py .`
and copy its first line into the report verbatim. Scope is keyed on the export's auto-discovery contract
(`list_skills`/`list_agents`), minus vault-shaped content bundled inside a skill (any `wiki/` or `raw/`
segment, i.e. the shipped seed demo); names that ship are never findings (`index`, `log`, and the seed's own
pages); links inside code spans, fenced blocks and HTML comments are not links; targets resolve as Obsidian
does, frontmatter aliases included; root docs are out of scope (their `[[…]]` are naming examples by design —
CLAUDE.md §12's ship-safe-citation rule governs citations there). A link dead in both copies is counted on
the control line, never flagged: shipped skills use placeholders such as `[[topic]]`. The script carries its
own §11 control (a synthetic surface linking a synthetic page must be caught) and tells legitimate absence
from a broken premise: an empty `wiki/` (a fresh install, the published copy itself) reports `n/a`; a missing
`wiki/`, no surfaces, an unreadable surface or a silent self-control reports `PROBE FAILED`, never "clean".
Exit 1 = findings: the fix (owner-confirmed) is rewriting the citation in ship-safe wording — the page name
in code font, no link — never deleting the reference. The publish gate's test suite runs the same script
(its leg 14), so an edit-time miss here is caught there; regression fixtures live beside the script
(`bash .claude/skills/lint/test_check_shipped_links.sh`). Design record:
`wiki/developments/shipped-surface-wikilink-guard.md`.

### 3 — Conflict audit
Find pages containing `## Conflicts / Open Questions`. List each unresolved conflict (the two sides)
as cognitive tech-debt to resolve.

### 4 — Gap scan (optional, suggestive)
Note entities/concepts mentioned often but lacking their own page, and stale claims newer sources
supersede. Suggest sources or web searches to fill gaps.

## Graph colour restore (on-demand — NOT part of a routine lint)
The graph's per-type colours live in `.obsidian/graph.json` → `colorGroups`. That file is **volatile**:
Obsidian rewrites it from memory whenever a graph setting changes (or a sync clobbers it), and can wipe
the palette so the graph turns all-grey. A wiped palette is **immediately visible**, so handle it
**only on a real signal** — never scan for it on a routine lint.

**Trigger — do this only when:**
1. the user reports a grey/colourless graph or asks to check/fix/restore graph colours, **or**
2. it is a **fresh vault** at first-run — `ingest`'s bootstrap calls this once (see that skill).

Otherwise do nothing: a routine `/lint` never reads `graph.json` or the palette.

**Procedure (one shared script — the single source of truth for the palette):**
- **Detect:** `python3 .claude/skills/lint/apply-palette.py --check` → exit 0 = palette complete (stop);
  exit 1 = it prints the missing framework groups.
- **Confirm, then restore:** on the user's OK, `python3 .claude/skills/lint/apply-palette.py --apply` —
  it **merges** the canonical palette (`.claude/skills/lint/palette.json`) into `colorGroups`, adding
  only the missing framework groups and **preserving any custom groups**. Idempotent.
- **Reload:** tell the user to **close the graph view and reload Obsidian** (`Cmd/Ctrl+R`), so Obsidian
  does not overwrite the edit with stale in-memory state.

The palette data (`palette.json`) and logic (`apply-palette.py`) ship with this skill, so `setup.sh`,
`ingest`'s first-run, and this restore all use the **same** definition — read **only** on this path,
never on a routine lint.

## Report format
```markdown
## 🩺 Wiki Health Report — YYYY-MM-DD

### ✅ Healthy
- ...

### ⚠️ Warnings
- **N orphan pages**: [[..]] — suggest linking or categorizing
- **N unindexed pages**: [[..]] — on disk but missing from index.md

### ❌ Errors
- **N dead links**: [[Source]] → [[Missing Target]] · **N dead embeds**: [[Source]] → ![[missing.png]]
- **N unresolved conflicts**: [[Page]]

### ⏳ Flags
- **N pages carry `flagged:`** (engine control OK) — ≥5 → consider `/deep-lint`
- `<the qmd-registry line, verbatim from the script>` · `attic-leak: none / n/a / N leaks` · `skill-guard: clean / N unsanctioned (control OK)` · `customisation-pairing: ok / n/a / N findings` · `throttle-check: clean (N of M diffed, control OK) / N findings / PROBE FAILED` · `shipped-links: clean / n/a / N dead / PROBE FAILED`

### 🛠️ Proposed next steps
1. Auto-register unindexed pages? (y/n)
2. Re-derive / resolve the listed conflicts?
```

## Hard constraints
- **Read-only scan.** Do not modify, rename, or delete anything before the report.
- **No unverified "clean".** A check that returns zero findings must be validated with a positive
  control (the same probe matching something known to exist) before the report may say "clean"
  (CLAUDE.md §11).
- **Wait for confirmation** before applying any fix.
- **Graph colour restore is on-demand only** (see its section) — never scanned or read on a routine lint.
- After approved fixes, append to `wiki/log.md`:
  `## [YYYY-MM-DD] lint | fixed N issues (M dead links, K unindexed)`.
- **Refresh on write:** if approved fixes touched wiki pages, the `qmd-search` refresh applies — run it
  inline only where no turn-end refresh hook is installed (that skill owns the rule); a no-op when qmd is dormant.
- Report in **British/UK English**.
