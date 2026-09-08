# Manual: using your LLM second brain

> **What is this.** Your AI-built **second brain**: drop in your sources and the agent compiles them into a structured, self-maintaining knowledge base that answers questions, creates deliverables, and acts as a cited reference. 
>
> **What this manual covers.** How to use it day to day: the capture → compile → ask → maintain loop, the everyday commands (`/ingest`, `/query`, `/output`), and the advanced options. You rarely edit the wiki by hand; you work through the agent.

## What's in here

| Folder | What it holds |
|--------|---------------|
| `raw/` | **Your sources** (the inbox). Drop files, clips, or links here in almost any format: PDF, Word, PowerPoint, Excel, Markdown and plain text, CSV, HTML and web pages (articles, blogs, GitHub repos and gists), images (PNG/JPG), audio (MP3/WAV), EPUB, and YouTube links. Once processed, the agent files each into a numbered subfolder (`1-articles` … `9-originals`, `archives`, `duplicates`). |
| `wiki/` | **The compiled brain:** `concepts/ entities/ tools/ models/ benchmarks/ sources/ syntheses/ developments/ maps/ user/`, plus `index.md` (the catalogue) and `log.md` (history). |
| `wiki/user/` | **About you** — profile, research, works. The agent reads this for personal context; you curate it. |
| `output/` | **Deliverables** the agent writes on request — reports, briefs, decks. Kept separate from the brain. The root holds one-off pieces; subfolders (`user-notes/`, `fundings/`, `conference/`) hold standing documents the agent keeps up to date as the underlying knowledge changes. |
| `assets/` | Images and reference attachments — diagrams, screenshots, and *special* PDFs you want to link to. Source PDFs to **ingest** go in `raw/`, not here. |
| `IDEAS.md` | **Your scratchpad** — a copy-ready **TODO prompt queue** plus ideas and a monitor lane of standing cautions, jotted freely. The agent ignores it unless you explicitly point it there: *"maintain IDEAS.md"* tidies and reconciles it, *"run TODO 2"* executes a queued prompt and updates its status. |
| `attic/` | **Your cold storage** — retired files kept "just in case", each listed in `attic/MANIFEST.md`. The agent never opens it unless you explicitly ask; archived notes show **grey** in the graph. |
| `CUSTOMISATION.md` | **How your agent behaves** (vault root, seeded on first setup) — its name, output styles, task roles, and any standing preferences you add. Edit it, or just ask the agent. Definitions of the non-default styles and roles live next door in `CUSTOMISATION-definitions.md`, which the agent reads only when you switch to one — keeping every session's always-on context lean. |
| `CLAUDE.md` | The rule-book the agent follows (you don't normally touch it). |
| `.claude/skills/` | The commands: `ingest`, `gather`, `query`, `output`, `reflect`, `lint`, `deep-lint`, `attic`, `adopt`, `project`, and `qmd-search` (plus `export-template` for framework updates, and `delegate`, which the agent reads itself rather than you calling it). |
| `.claude/agents/` | The subagent definitions `delegate` routes to: a critic that argues against a plan, a verifier that checks claims against files, a compile lane, a memory lane, a planner and a cross-session reflector. Each one is a small Markdown file naming what that lane may read and write. |

Every note in `wiki/` (except the navigational maps) also carries a **confidence level**, so you can see at a glance how far to trust it:

| Level           | What it means                                                                              |
| --------------- | ------------------------------------------------------------------------------------------ |
| `authoritative` | Peer-reviewed or published work, expert reviews, and verified sources — the highest trust. |
| `high`          | Faithful summaries, preprints, and official documentation, or your own work by default.    |
| `medium`        | Reputable secondary sources, or a page grounded only in sources primary for something adjacent — the default. |
| `low`           | A single promotional, social, or auto-transcribed source; treat with care.                 |
| `very-low`      | Speculative or unverified material, flagged for caution.                                   |

## The loop

**Capture** (drop a file, clip, or URL into `raw/`) → **Compile** (`/ingest`) → **Ask** (`/query`) →
**Maintain** (`/lint`). Good answers get filed back, so the wiki compounds over time.

## Everyday commands

Type these to the agent, in the Claudian panel or Claude Code.

**`/ingest` — turn sources into wiki notes**
- `/ingest` — process everything new in `raw/`.
- `/ingest <file or https://…>` — a single file or web link; PDFs, documents, web pages, and YouTube are all handled. A platform link the capture chain cannot reach (an X post, a Reddit thread, a XiaoHongShu note) is reported with a ready, owner-gated option rather than improvised or silently skipped.
- `ingest this at research depth` — pin the thorough, academic treatment for an important paper: exact figures, verbatim quotes, methods, and limitations. Left unpinned, the agent decides per source after reading and shows you what it chose.
- Plain language works too: *"add this to my wiki."*
- After each ingest, the agent lists the new notes with their **confidence level**, so you can check the trust ratings and ask to re-grade any.

**`/query` — ask your knowledge base**
- `/query <question>` — for example, *"/query what do my notes say about calibration?"*
- Answers come **from your wiki**, with clickable `[[links]]` to the pages used, and can be filed back when worth keeping.

**`/reflect` — keep what a session taught you**
- `/reflect` — at the end of a working session, the agent sweeps the conversation for research insight, method lessons and any faults it found, then shows you a table of what it proposes to record and where. Nothing is written until you approve it. A critic subagent tries to knock down each proposal before you see it (`--no-critic` skips), and the report names how much of the session's record it could still see. After a development run (an IDEAS todo, a framework change or a delegated job) the proposal table also carries the run's cost at each boundary and a short waste list, each entry naming where its fix should go.
- `/reflect --cross <session>` — the same sweep run over another, usually finished, session's transcript by a separate read-only agent. That agent is an independent witness: it can catch what the original session never noticed about itself. It only proposes; you still approve every write line by line. After a large multi-agent job the agent may offer one such pass itself, once, with the cost stated; it runs only on your yes.
- It only ever runs when you ask. The agent already files findings as it works, and that carries on unchanged; this is your own trigger for the times it didn't.
- It tells you how far back it can still see, since a long session may have dropped its earliest turns, and it never claims to have swept the whole thing.
- Add `--yes` to let it write without waiting. It still shows you everything it wrote, and it may only add new pages or append to existing ones inside `wiki/` — never your own pages in `wiki/user/`, and never the rule-book.

**`/output` — produce a polished deliverable**
- `/output <what you want>` — for example, *"/output a one-page brief on X for a non-expert."*
- Writes a grounded, **cited** document into `output/`; it cites what it draws on and does not invent facts.

## Rules of thumb

- **You curate and ask; the agent writes the wiki.** Change notes through the agent rather than by hand.
- Keep anything **about you** — bio, research, works — in `wiki/user/`, starting with `About Me`.
- `raw/` is your source of truth: the agent files and sorts your sources but never rewrites them.
- Keep Obsidian open, and explore through the **graph view** and **backlinks**.
- The agent runs on API credits, so it is worth being deliberate about very large jobs.

---

## Skills, tools and plugins: three use levels

Everything the agent can reach for beyond its own workflows sits in one register, `wiki/developments/capability-register.md`, with a use level per entry. An `auto` add-on is used whenever a task fits, such as the chart and figure skills inside a deliverable. A `propose-first` add-on is offered once, in a line, and runs only when you say yes; typing its slash command, naming it, or granting it in a hands-off pre-flight counts as yes. A `by-name` add-on never appears in any listing and runs only when you invoke it. The academic writing suite (ARS) and the experiment agent are propose-first; reflect and the attic are by-name.

To add something new, say "adopt <url>" or type `/adopt <url>`; `/adopt --assess-only <url>` stops after the report, and `/adopt --retire <name>` reverses an adoption. The agent fingerprints the repository, recommends a level and says what the add-on would mean for the system, then waits for your approval before installing, recording and routing it. To change a level, say so, and the register row and the wrapper change together.

## Advanced

**Deeper `/ingest` options**
- `/ingest --verbatim <url>` — save the **exact** page rather than a cleaned version, for precise quoting.
- `/ingest --no-dedup` — skip the automatic "already ingested?" check when loading material you know is new.
- `/ingest --agent-convert <file>` — the agent itself transcribes a PDF or image to Markdown instead of the automatic converter, for precision on complex layouts (heavier on tokens, so opt-in). If an automatic conversion comes back empty or garbled, the agent offers this route with a cost estimate before anything else.
- `/ingest --depth concise,standard` — narrow the depths the agent may choose from for this run. It may use all three unless you narrow or pin.
- Capture is automatic by type: web pages via `defuddle`, Markdown and text via `curl`, audio/video/binary via MarkItDown, with **Jina Reader** as a fallback for awkward or JavaScript-heavy pages.

**`/gather` — capture from the web: links, or a whole topic**
- `/gather <url> [url2 …]` — fetches the page(s) **and the relevant sources they cite** (papers, repos, docs) into `raw/`, then hands off to `/ingest`. It **previews what it will fetch and asks first**, and caps how much it pulls. On documentation sites it also checks the site's sitemap, so the preview shows the host's whole inventory rather than just the pages the seed happens to link.
- `/gather --search "<topic>"` — no links needed: the agent web-searches the topic, triages the hits, and shows you a **dated shortlist to approve** before anything is fetched. If the topic is too vague to plan from, it asks up to three sharp questions first; each approval screen also shows which sub-questions of your topic are covered and which are still open. Add `--rounds 2` to let it search again for whatever the first haul left uncovered — later rounds never re-run earlier queries or re-present rows you already passed over as new. This is the vault's own deep-research route — after `/ingest`, ask `/query` or `/output` for the cited report. When a topic needs Chinese or community coverage, search mode can also query the enabled platform channels (Bilibili, V2EX, known RSS feeds) alongside web search, declared at the approval screen.
- With a bigger budget (say `--max-pages 40`) the menu stays small but every further ranked candidate is listed one per line, and you capture by **rule** — *"top 30 by relevance"*, with row-level tweaks if you like. A bare "approve" always means just the menu, and the search funnel (queries, pool, date checks) scales with the budget and is printed at the gate.
- Conservative by default (search mode captures just the approved results; link mode follows one citation hop; up to ten pages). Override with `--expand 2` (citation hops), `--focus "X"` (only material relevant to X), `--max-pages 50`, `--shortlist 10` (detailed rows at the gate), `--queries 8` (searches per round), `--same-domain`, `--include a,b` / `--exclude c,d`, `--yes` (skip the preview), or `--ingest` (compile afterwards) — or simply describe it: *"gather these, two hops, only the papers."*
- Runs keep themselves honest (v3.1): every capture goes through one script that enforces the caps, raw immutability and provenance; a per-run ledger tracks captures and your drops across rounds on bigger runs; and the gate adds the agent's advice ("~N worth capturing") — rows beyond your budget are marked, and capturing them just means raising the cap ("raise to 15, take top 15").
- The agent may also **suggest** a gather when a `/query` or `/output` run hits a real knowledge gap: a short brief (why · what · the exact command · cost) after its answer. It only ever runs on your explicit yes — say nothing and it reminds you once, then drops it; say no and it stays dropped for the session.

**`/lint` — health-check the wiki**
- Finds broken links, orphans, unindexed pages, and conflicts, checks that no third-party installer has slipped an unsanctioned skill into the agent's skill folders, and checks that no shipped skill or agent file links to a wiki page that never ships (such a link would be dead in the published framework). A normal `/ingest` self-cleans, so run this after hand-editing, after syncing between machines, or for a periodic review.

**`/deep-lint` — periodic deep maintenance**
- A heavier pass (roughly monthly, or when flags pile up) that does everything `/lint` does and also reconciles the staleness flags queries leave behind, audits **confidence** on changed and sampled pages rather than re-reading the whole vault, re-checks a capped, priority-ordered set of sources against their **live online versions**, keeps the external capture tools current — a trustworthy newer release (tagged, past a cooling-off, same publisher, acceptance-tested) upgrades automatically with each bump reported to you, while anything failing that bar is only reported — and reviews the IDEAS Monitor lane, updating the wiki where things changed. Token-bounded by design, and every cap it applies is stated in its report.

**The attic — retire files without deleting them**
- Say *"archive [[X]] to the attic"* (or `/attic archive X`) and the agent runs the full routine: it first folds anything still useful from the file into your live notes, shows you the list for approval, then moves the file into `attic/`, records what, where from and why in `attic/MANIFEST.md`, unindexes it, tidies every link, and verifies nothing still points in; *"restore X from the attic"* (`/attic restore X`) reverses it; *"what's in my attic?"* reads the manifest back to you.
- Archived notes stay in the graph in **grey**, so retired material remains visible without cluttering your live knowledge. The agent never opens the attic on its own — only when you ask. The monthly `/deep-lint` may *suggest* archive candidates (stale or superseded notes) as ready-to-run `/attic` commands but never moves anything itself, and the routine `/lint` guards the boundary by flagging any live note that still links into the attic.

**Your working repositories — Overleaf and code, managed from the vault**
- Say *"link this Overleaf project"* (or `/project link <url>`) and the agent clones it into its own store outside the vault, shows you what it will do first, and puts one registry row in `wiki/tools/Agent Project Store.md` plus a commit-pinned snapshot of the document into `raw/`, ingested like any source, so the wiki knows the project without holding its files. From then on *"open my research outline"*, *"rewrite section 3, commit, push"* work in that clone; commits are yours, pushes happen only when you say push, and an Overleaf push lands in the project at once.
- A repository you already keep elsewhere (your code) is registered where it is (`/project link --path <dir>`), never copied. The clone's files are not visible in Obsidian, which is the point: nothing in a repository can enter the second brain except the snapshots you ask for.
- The other direction, running Claude Code inside a code repository with the vault mounted as read-only context, is a standing note at `output/user-notes/vault-as-external-context.md` (the mount, the deny rule, the clause for the repository's own `CLAUDE.md`). Say *"act as tutor, walk me through the project store and the external-context note"* in a fresh session for a guided tour of both shapes; the tutor reads that note, the `project` skill and `wiki/tools/Agent Project Store.md`.

**qmd — optional local semantic search (for large or fast-growing vaults)**
> Worth adding when your wiki is **already large enough that `index.md` is hard to scan**, *or* when you **expect it to grow very large**. In that case adopt it **early**: the index then builds up incrementally (one quick re-embed per note as you go) instead of as one slow bulk embed later, and you get search-by-meaning the whole way up.
- Once enabled, the agent **searches by meaning** (not just exact keywords) — but **only when it's actually needed**: when the normal `index.md` + keyword search comes up short for a question. It is **not** run on every search, and you don't have to ask for it — the agent decides when it genuinely helps (you *can* force it with `/qmd-search <query>`). Whenever qmd is off or absent, search silently falls back to the normal path.
- It stays **dormant and cost-free** until you install and enable it, runs **only as quick one-shot calls** (nothing is ever left running in the background), and the agent keeps its index fresh automatically as you add or change notes. Ask the agent to set it up when you're ready.

**Back up your vault — private repo**
- Your *entire* vault — notes and all — can back up to a **private** Git remote, giving you version history and sync across machines. Ask the agent to set it up once; after that it backs up automatically after every framework publish, and any time you say "back up my vault".
- This is **separate from sharing the framework**: the backup keeps *everything in a private repo*; the framework is published *stripped of your notes to a public repo*. Keep the two remotes distinct.
- The **Obsidian Git** plugin is an optional extra if you want continuous, timed auto-backups without asking the agent.

**`/export-template` — sync the framework with its repo**
> Most users need this only to **update**: `--pull` brings a newer framework version into your vault. `--push` publishes framework changes and is the maintainer's path. You never need either to capture sources or use your wiki.
- It packages the framework with **none** of your notes and syncs it with the public GitHub repo, one direction at a time. It always previews and asks before writing anything.
- A plain `git push` only syncs a single repository with its own remote. This skill instead carries framework changes between two separate repositories, your private vault and the public framework repo, and assembles the shareable demo. Your knowledge therefore stays in its own private, independently backed-up vault, while the framework itself stays shareable through the public repo.

**Modes and pacing**
- **Depth**: `concise` · `standard` · `research`. When ingesting, the agent picks a depth for each source **after reading it** and tells you which it chose and why, in the same report that lists confidence — so you can re-grade either with one word. Narrow what it may use with `/ingest --depth concise,standard`, or pin one for the whole run with `--research`, `--standard` or `--concise`. Asking a question is different: there `research` is opt-in or the agent asks first. All modes stay token-efficient.
- **Pacing** (how many at once): `auto` (default) · one at a time · in batches.

**Customisation — make the agent yours**
- Your agent's **name**, default **output style**, and **interaction preferences** live in `CUSTOMISATION.md`, seeded on first setup. Edit it — or just ask the agent — to change how it addresses you and how it writes. The styles and roles you are *not* currently using sit in `CUSTOMISATION-definitions.md`; the agent reads that file when you switch, and "set default style/role to X" moves the definition into the always-on file for you.
- Those are only starter examples: the file is **open-ended**. Add any standing preference you want every session to honour — citation habits, formatting rules, tutoring style, anything — as new bullets or sections.
- **Deliverable defaults** (optional): a `## Deliverable defaults` section sets standing formats for `/output` documents — citation style, deck format, and so on. Leave it empty and the agent chooses per deliverable; whatever you write in the instruction always wins.
- **Roles**: say *"act as tutor"* (or any role you define under `## Roles`) to switch the agent's task context for the conversation; every reply carries the active `role · style` status line (opening its first text or its final answer), a claim the reply has to satisfy rather than a decoration. Roles shape how the agent works on your task and add to your global preferences; they never change your output style — how much you read stays your choice alone.
- **Throttle**: subagent model and effort tiers follow one knob, `throttle` in `CUSTOMISATION.md` (`auto · top · default · cheap · fast · cheap-fast`). Say *"set throttle to fast"* and the agent runs `throttle.py set fast`, which rewrites the Settings line and every subagent definition; the change registers at your next message and, on a machine with the anchor hook installed, the status anchor shows it. `auto`, the default from 2026-09-08, picks model and effort per task within the class range. The row anchor in `routing.json` is the reference, `xhigh` for the closed-task classes and `max` for the critic and reflector, and every departure is recorded with its reason on the lane-open event. `default`, `top`, `cheap`, `fast` and `cheap-fast` are overrides you set by hand and they are never re-resolved: `default` pins the anchors with no reason required, `top` the ceilings, and `cheap`, `fast` and `cheap-fast` name a budget or time constraint. Which steps a skill may route to lanes is fixed by its parity gates and applies under the `multi` regime; in `single` the agent does the step itself unless it has a named reason for a lane (`wiki/developments/fable-minimising-routing.md`).
- **Long sessions**: every turn the agent sees its own context size. Past 60 % of the window it writes a hand-off document (`~/.llm-wiki/handoffs/`) at each item boundary and may recommend a fresh session with a ready prompt; past 80 % it finishes what is in flight and starts nothing new; and if the harness compacts the conversation, a checkpoint written just before is re-read afterwards. These are vault-local hooks in `.claude/hooks/`, not part of the published framework.
- **Output styles** shape conversation only, one ladder from most to least: `detailed` (everything the prompt makes relevant) · `balanced` (the default — the natural answer) · `brief` (the answer plus what you need to act on it, in flowing prose) · `shortest` (the answer and nothing around it). Say *"switch to brief"* for one session, or *"make shortest my default"* to keep it. You can add your own styles too. A scoped wish such as *"more concise for the next 3 replies"* shows as `customised` in the status line while it lasts, then the style reverts on its own.
- Choosing a style **never** changes the wiki itself — your notes, their confidence ratings, and the agent's status reports stay exactly the same.

**Subagent lanes — the helpers the agent spawns**
- The agent does the work itself by default. It calls a helper agent, a *lane*, only when there is a named reason: a check that has to be independent of whoever did the work, breadth it cannot hold in one context, isolation from a long conversation, or a job longer than it can afford. The reason is recorded before the lane starts, so you can see afterwards why each one was called.
- A lane is a separate, short-lived session that knows nothing about your vault. It runs from a **lane home**, a small folder outside the vault (`~/.llm-wiki/lane-home/`) holding the lane's own settings, a shell guard and a few extracts of the rules. `setup.sh` builds it for you by running `python3 .claude/skills/delegate/lane.py init`, and re-running setup refreshes it. Nothing in it is your knowledge, and it is never published with the framework.
- Each lane sees only its brief and the folders granted for that one call. Anything else it reaches for is refused, and the agent treats the refusal as a sign to brief it again rather than as a result.
- **`delegation`** in `CUSTOMISATION.md` sets how much of this you get. `auto`, the default, leaves the choice to the agent: for each run it decides between `single` (the work stays with the main agent) and `multi` (a skill may also route its own steps to lanes), weighing the size of the run, how full its context is, the throttle and breadth settings and whether you are present, and it records the reason. A run it chose to run `multi` shows as `auto→multi` in the fourth entry of the status line each reply opens with, and the first lane of such a run waits for your go. Take the choice away by setting `single` or `multi` yourself: say *"switch to multi"* for one conversation, *"do this multi"* for one run, or *"set default delegation to multi"* to keep it.
- Lane reports and the record of every spawn are written outside the vault as well, under `~/.llm-wiki/`, so your notes stay only your notes.
- Runs that touch the wiki now log a cost line beside their entry: what the session billed at list prices, split between the main agent and its lanes, with the number of lanes and the reasons they were called. It is arithmetic over the transcripts rather than a charge from your plan, so read it as a comparison between runs.

**More `/query` examples**
- `Compare [[A]] and [[B]] and save a table to syntheses.`
- `Where are the gaps in what I know about <X>? What should I read next?`
- `Turn [[topic]] into a Marp slide deck.`
- `Do a research-mode synthesis of <X> with exact ƒfigures and citations.`

---

### Hands-off long runs

When you want a long task done while you are away, say so. The agent first shows a short table: the permissions it needs and might need, the conditions under which it will stop on its own, the expected spend, and what happens if its context window fills. One confirming message starts the run. It ends with a reflection and a hand-off document you can resume from in a fresh session. A hands-off run relies on three context hooks that live only in your vault's `.claude/hooks/` and are not part of the published template; without them the run is refused at its second gate and stops after one hand-off, so on a fresh copy of the framework this feature waits for the hooks kit planned for the next release.

Starting one is a single exchange. Say what you want done and that you will be away; the agent replies with the pre-flight table — the permissions it holds and the ones it may need, the gates it will decide on your behalf with the default it will apply to each, the conditions under which it will stop by itself, the expected spend phase by phase, the reset time of your usage window against the expected finish, and what it will do as its own context fills. Read it once; one confirming message is the whole authorisation, and it covers exactly those grants. Anything outside them stops the run and waits for you with a report.

What happens as the agent's context window fills depends on whether you are there. In an attended session the thresholds only warn: at 60 % of the window it writes a hand-off document at every item boundary, and at 80 % it finishes what is in flight, starts nothing new and recommends a fresh session. On a hands-off run — from the first one after 2026-09-05 — they are hard: at 80 % it refuses to open a new item, waits for the helpers still running, writes the hand-off, ends its own session and starts a successor that picks the work up from the hand-off's resume prompt, so the conversation is never compacted mid-task and the cost of the change-over is one reload of the standing context. At 90 % a hook stops everything except the close-out: writing the hand-off, starting that successor, and the two bookkeeping records (the boundary and the findings ledger). That is the emergency exit, and it costs at most the item in flight.

Two more things run under the hood on a hands-off run. The agent's shell is fenced: every command is checked against the grants you confirmed in the pre-flight, a command outside them is refused and logged rather than worked around, and the status line at the top of each reply carries a fifth entry, `· hands-off`, while the fence is armed. And the hand-off is written as a pack for the next step, never as a history: what the next item needs, the decisions it rests on and the gate it must pass, so a successor orients from it in a few thousand tokens. The run also has a live console, a read-only board of its items, helpers and timeline (`handsoff.py watch --run <run>`): at a launch, a successor or a resume the run opens a Terminal window on it unless one is already open, or unless the pre-flight says `viewer: none`. If you are working alongside the agent yourself, `handsoff.py watch --session <id>` shows that session's background jobs, such as test suites and helpers, with their progress, and the status line carries a `· jobs` entry for as long as any of them run. The console window a hands-off launch opens also opens for any attended run that spawns helper agents, whenever none is open for that run, so every multi-agent run is watched; `--viewer none` on the spawn or `AIMYTH_VIEWER=none` keeps it closed.

What you read in the morning is that hand-off document, in `~/.llm-wiki/handoffs/` outside the vault, one file per session. It opens with a morning report — what shipped, what waits on a decision of yours, what changed in the registers, what it spent, what the run saved, every warning it raised, and the prompt to paste into a fresh session to carry on — and the sections below it hold the detail: the item in flight, the grants the run held, a ledger of every finding and warning with what was done about it, the trace of each phase boundary, and the plan of record. It is rewritten at every boundary, so it is current even if the run stopped in the night.

The agent runs under one account, so a usage limit stops it and its helpers together. That is expected, not avoided. The process that started a hands-off agent stays beside it as a supervisor. By default (since 6 September 2026) a limit ends the run there: the supervisor records the stop and stands down, the hand-off is the recovery, and once the window resets you resume it yourself with `handsoff.py resume-head --run <run>` (the same session, where it left off) or `handsoff.py successor --run <run>` (a fresh agent from the hand-off). If you would rather the run carried on across the reset without you, write `limit-off` in the pre-flight: the run then opens with `--on-limit resume`, the supervisor reads the reset time from the stop message, sleeps until then, and resumes the same session, provided its context is still under 60 % of the window; above that it starts a successor from the hand-off. A helper stopped by the limit is resumed from its own transcript in the same way, and you lose one cold re-read of the context and nothing else. In that mode the status line reads `hands-off-limit-off`, and the supervisor stands down of its own accord if you continue the session by hand in the meantime, or if you run `handsoff.py supervise --stop --run <run>`. If the stop message names no reset time, the run ends there and the hand-off is the recovery. The agent never probes your account to learn when a limit lifts, never tries a second login, and never adjusts to a limit beyond waiting for the reset. If you are working with the agent yourself when a limit stops it, say "continue" once the window resets and it carries on. A machine sleep or restart ends the supervisor too. The hand-off is then the recovery, as before.

Two rules govern what happens when something goes wrong while you are away. Nearly every trigger — spend past the envelope, a band crossing, a helper that fails, stalls or is refused a path, a red test suite, a reviewer's "not ready", a helper's usage limit — is warn-and-continue: the agent records it in the ledger with what it did about it and keeps going, and you read the list in the morning. The rest are holds: a component still failing after three attempts, a design still unready after two revisions, a phase running away with the budget, and any finding that would reverse a decision you made yourself are parked with their state on disk for you to rule on, while a refusal or a limit on the main agent itself, or any write or fetch outside the grants you confirmed, stops the run outright.

## Graph view (colours)

The graph is **colour-coded by node type**, so the shape of your knowledge reads at a glance. Reopen the graph view after any setup change to load new colours. **A fresh vault's graph is empty** until you `/ingest` your first source (or load the demo with `bash setup.sh --with-example`). The colours appear as soon as there are notes to colour, and `setup.sh` or your first ingest applies the palette automatically. If the colours ever disappear later (Obsidian can rewrite its graph config), just ask the agent to restore your graph colours.

| Colour         | Node type       | What it is                                     |
| -------------- | --------------- | ---------------------------------------------- |
| ⚪ White        | `index` · `log` | the registry hubs that anchor the graph        |
| 🟡 Gold        | Maps            | navigational hubs (Maps of Content)            |
| 🔵 Blue        | Concepts        | abstractions — methods, theories, principles   |
| 🟢 Green       | Entities        | people & organisations                         |
| 🟠 Orange      | Tools           | software, apps, plugins, skills, services      |
| 🟦 Oxford blue | User            | **about you** — profile, research, works       |
| 🔴 Red         | Models          | LLMs (Qwen, GPT, …)                            |
| 🟣 Purple      | Benchmarks      | evaluation datasets (AIME, GSM8K, …)           |
| ⚫ Charcoal     | Sources         | one summary per raw source (the bulk of nodes) |
| 🩷 Pink        | Syntheses       | knowledge the agent wrote itself, from a query, a reflect run, or its own reading |
| 🟤 Brown       | Developments    | this vault's own self-upgrade docs (design · plans · rollouts) |
| 🩶 Grey        | Attic           | retired files kept "just in case" (cold storage) |

New nodes colour themselves: each colour keys off the **type folder** (`wiki/models/`, …), so anything the agent files there is coloured automatically, with no manual tagging.

---
*This manual is stable. It changes only when the system's setup changes, not on every ingest or query.*
