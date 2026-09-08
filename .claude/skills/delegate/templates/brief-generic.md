# Spawn brief — generic skeleton

Fill EVERY `{{slot}}`; an empty slot is a spawn blocker. Replace the paste marker with the
block from `_inherited.md`, verbatim. Lines starting `<!--` are spawner guidance — delete
before sending. Send the fenced body as the Agent prompt.

```
You are {{AGENT_NAME}} (definition: .claude/agents/{{DEF}}.md), lane {{LANE_ID}} of run
{{RUN_ID}}.

TASK
{{One paragraph. State the partition explicitly: which question THIS lane answers, and
which adjacent questions belong to other lanes even where files overlap.}}

SCOPE
- Reading list (pre-scoped): {{per slice: `page — why — ~size` (SKILL.md §2b); keep tight —
  open discovery multiplies cost}}
- File whitelist (may create/edit): {{paths | NONE — read-only lane}}
- Link whitelist (may link to): {{pages | n/a}}
- Boundary: anything outside the whitelists is out of scope — return a proposed diff
  instead of an edit, and report off-scope findings without fixing them.

REGISTRIES
wiki/index.md and wiki/log.md are propose-don't-write: return entries as ready-to-apply
diffs. {{Ingest lanes only, under an explicit ingest contract — replace this sentence with
the granted-exception wording in brief-compile.md; never grant to any other lane.}}

GRANTS
{{headless lanes: the read directories, the write scope and any add-on granted beyond the
class row, each with its reason — so a refused path reads as a gap to report, never as a
mistake to work around; every path and command literal, as the fence will see it — no `Let X =`
shorthand and no pasteable placeholder, since a fenced lane copies a shorthand into a shell
variable the fence reads as an ungranted root (eight denials, 2026-09-06) | in-session: "n/a — inherited"}}

DECISIONS
{{the run decisions that bear on this task, and what sibling lanes hold; "none" is a
statement, not an omission. A decision this lane needs and cannot find here is a gap to
report, never one to invent.}}

VERIFICATION
- Output gate: {{the assert-nonzero / expected-shape assertion for EVERY stage of the
  lane's work, e.g. "≥N pages, each with §4.1 frontmatter"}} — report each assertion's
  result.
CONTROL+: {{a probe that must hit}} in {{the file that must hold it — a real path, nothing after it}}
Negative control: {{a planted pattern that must NOT hit / must be caught}}
- {{Write lanes with a link whitelist: name the link-whitelist sweep and its planted-fake
  negative control | read-only lanes: "—"}}
- Folds must parse: a count over a run ledger, a spawn record or any JSONL more than one
  writer appends to reads every line with `json.loads` or `jq` before it counts; a key-pattern grep
  is a locator, never a verdict (two writers spell one key two ways; a substring count read
  5 of 8, 2026-09-01).

{{PASTE templates/_inherited.md block}}
{{extra role conduct | —}}

REPORT
{{shape — the definition's report shape unless the task needs more}}
```

<!-- Spawner checks before sending: spawn-record line written (SKILL.md §3 slot 0); all
eight slots present (GRANTS belongs to slot 2's scope, DECISIONS to slot 8 — neither adds a
ninth); no expected answer leaked anywhere; reading list scoped. Control
strings for greps over the CURRENT session's transcript must be generated at probe time
by the lane, never written in the brief — a brief-supplied string matches its own spawn
prompt inside the transcript (observed live 2026-08-27: a briefed negative control
returned 1, hitting its own brief), so use a fresh nonce or scope the grep to pre-brief
lines. -->
