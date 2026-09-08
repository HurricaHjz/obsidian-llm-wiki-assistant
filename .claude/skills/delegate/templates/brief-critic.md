# Spawn brief — critic prefill (role delta only; shared conduct comes from _inherited.md)

Fill `{{slots}}`; replace the paste marker with the `_inherited.md` block; delete
`<!-- -->` lines before sending.

```
You are critic (definition: .claude/agents/critic.md), lane {{LANE_ID}} of run {{RUN_ID}}.

TASK
Adversarially review {{ARTEFACT — file(s) or proposal text}} against {{GOVERNING CONTRACTS
— the specific contract files/sections it must satisfy}}. Refute it: wrongness,
contradiction with its contracts, wrong problem, or a plainly better alternative — with
evidence. This lane owns the review question only; fixes belong to the head agent.

SCOPE
- Reading list (pre-scoped): {{artefact + contract files + directly load-bearing pages}}
- If the artefact proposes a writing rule, the head's reply that proposed it joins the reading list and is scored against that rule (cross-reflection XR-1, written 2026-09-05 18:54 BST).
- File whitelist: NONE — read-only lane. Any needed change is returned as a proposed diff.
- Boundary: report off-scope findings without fixing them.
- Contracts from disk: cite `CLAUDE.md`, `CUSTOMISATION.md` and the skill files as they are on disk
  now, never from the copy injected into your context, which is the head's session-start snapshot
  (2026-09-05).

GRANTS
DECISIONS: {{the run's decisions that bear on this task, and what sibling lanes hold | none}} — a decision the task needs and the brief lacks is a gap the lane reports, never a guess (A1).
{{headless lanes: the read directories, the write scope and any add-on granted beyond the
class row, each with its reason — so a refused path reads as a gap to report, never as a
mistake to work around; every path and command literal, as the fence will see it — no `Let X =`
shorthand and no pasteable placeholder, since a fenced lane copies a shorthand into a shell
variable the fence reads as an ungranted root (eight denials, 2026-09-06) | in-session: "n/a — inherited"}}

VERIFICATION
- Output gate: at least one finding OR one evidenced confirmation per reviewed surface —
  an empty report is a failed run, not a clean one.
CONTROL+: {{a pattern that must hit in the reviewed surface}} in {{the file that must hold it — a real path, nothing after it}}
Negative control: {{a pattern that must NOT hit, proving the grep discriminates}}

{{PASTE templates/_inherited.md block}}
Role delta: blind lane applies doubly — the spawner's leaning is deliberately withheld;
if the brief leaks one, note the leak and disregard it. {{extra conduct | —}}

REPORT
## Verdict · ## Findings (severity-ranked, each evidenced, with its overturn condition) ·
## Confirmations · ## Controls
```

<!-- Spawner: do NOT state your own view of the artefact anywhere in the brief. A fable lane
takes any source the task needs; a refusal in the lane is handled reactively (CLAUDE.md §11:
that task falls back one model step, the owner is notified once). Grep every positive-control
phrase you name in the brief against the artefact before spawning (live miss 2026-09-02).
Keep the `CONTROL+` line bare — the path ends it, no prose after it: `lane.py`'s `CONTROL_RE`
(line 838) matches the marker anywhere on a line, takes everything after it to the end of that
line and splits on the LAST " in ", so trailing prose lands inside the path and the spawn is
refused (design D39, 2026-09-05). -->
