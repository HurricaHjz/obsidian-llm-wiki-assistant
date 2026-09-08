# RUNBOOK — publish & maintain the second-yourself framework

Turns the private vault into the public framework repo **github.com/HurricaHjz/second-yourself** (renamed 2026-09-08 from `obsidian-llm-wiki-assistant`; GitHub redirects the old URL), with
your knowledge kept local. Read top to bottom.

## A. Build the template
```bash
bash .claude/skills/export-template/export_template.sh template-export
```
Produces `template-export/` per `SPEC.md`.

## B. Verify (script prints most of this — confirm)
- Skills = **every directory under `.claude/skills/`** (auto-discovered by `list_skills()`; check with `ls .claude/skills` — never a hand-kept list, which has gone stale twice: v0.7.6 and the 2026-08-23 `attic` omission). export-template ships too — users need its `--pull` to update.
- **Suites — run every one the tree holds (discovered, never hand-kept: a hand list went stale a third time, 8 named of 21, 2026-09-06), then the build-side re-run; green = `0 failed` printed by each suite itself** (never compare against a historical count — assertion totals grow):
  ```bash
  n=0; L=$(mktemp -d); while IFS= read -r t; do n=$((n+1)); d=$(dirname "$t"); f=$(basename "$t")
    case "$f" in *.py) (cd "$d" && python3 "$f") ;; *) (cd "$d" && bash "$f") ;; esac > "$L/$n.log" 2>&1 || echo "SUITE FAILED: $t"
    echo "$t :: $(grep -E -o 'PASS [0-9]+/[0-9]+|FAIL [0-9]+/[0-9]+|[0-9]+ passed, [0-9]+ failed|[0-9]+/[0-9]+ passed|Ran [0-9]+ tests|^OK$' "$L/$n.log" | tail -1)"
  done < <(find .claude -type f \( -name 'test_*.sh' -o -name 'test_*.py' \) -not -path '*/__pycache__/*' | sort)
  echo "suites run: $n"; [ "$n" -gt 0 ] || echo "PROBE FAILED: no suites found"
  ```
  Quote the `suite :: verdict` lines in the recap and sum them there, visibly; an empty verdict is a suite whose
  result line the parser did not recognise, to be read by hand, never a pass. A total carried from an earlier run
  is not a verification (2026-09-06: a recap stated the previous session's total after its own probe printed another figure).
  ```bash
  (cd template-export/.claude/skills/export-template && bash test_export_template.sh) || echo "SUITE FAILED: export suite INSIDE the build"
  ```
  The build-side re-run exists because the copy's premises differ from the vault's (`wiki/` is empty by
  construction): a guard can pass here and fail there — the 2026-08-30 empty-wiki regression is the class
  it catches, found only because that run was done ad hoc; this line makes it repeat.
- `template-export/wiki` & `/raw` hold only `.gitkeep` (no seed, no `index.md`/`log.md`); the demo is in
  `template-export/examples/seed/`.
- No personal leak: the payload gate below covers this, deriving your strings from the vault rather
  than asking you to recall them. Strings it cannot derive — an affiliation, a second handle, an ORCID
  — go one per line in `output/publish-gate-strings.txt` (owner-local, never shipped). Check by eye only
  that `template-export/wiki/user/` is empty.
- **Git-policy test** (the important one):
  ```bash
  cd template-export && git init -q && git add -A
  git check-ignore -q wiki/log.md raw/x.md output/y.md wiki/sources/z.md && echo "content ignored ✓"
  git ls-files | grep -qE 'CLAUDE.md|MANUAL.md|\.claude/skills/|examples/seed' && echo "framework tracked ✓"
  cd ..
  ```
- **Payload gate** (run it AFTER the git-policy test above, so it reads the index rather than the
  disk): `python3 .claude/skills/export-template/publish_guard.py template-export` → expect
  `check: clean` with a non-zero file count and its control tally, plus the `personal-strings:` line.
  Exit 1 lists the offending files: an absolute path into a machine home directory in any file, a
  non-text file outside `assets/`, or a personal string in a file's name or bytes that
  `publish-allowlist.md` does not adjudicate for that file. Exit 2 is a broken premise (unstaged tree,
  empty or partial build, git unusable, a vault or allowlist it cannot read) and is never a pass.
- **setup.sh test**: in a copy, `bash setup.sh` creates `index.md`/`log.md`; `--with-example` loads the demo.
- **`audited:` policy (decided 2026-08-27)**: the `setup.sh` seeders stamp `audited:` at seed time (creation-with-assignment is the check, §4.6); the shipped example pages deliberately carry **none** — stamping them would backfill a badge nobody checked, and "absent = pre-rule" is their honest state. A future §4.1 field change must sweep both surfaces (CLAUDE.md §12, the emitting-surfaces rule).

## C. Publish (first time)
1. **github.com → New repository** → name `second-yourself` → **Public** → do **not** add a README or
   licence (we ship them) → **Create repository**.
2. In Terminal:
   ```bash
   cd template-export
   git init -b main
   git add -A
   git commit -m "second-yourself: framework v0.1"
   git remote add origin https://github.com/HurricaHjz/second-yourself.git
   git push -u origin main
   ```
3. On GitHub → **Settings → tick "Template repository"**; add a description + topics
   (`obsidian`, `claude`, `second-brain`, `llm`, `knowledge-management`, `ai-research`).
4. The README images already ship (`assets/framework_demo.png`, `assets/hero.png` — tracked, referenced
   by `README.md`). To refresh one later, replace it under `assets/` at your vault root (where the README
   lives), then `--push` again.

> No `gh` CLI needed. Prefer a GUI? **GitHub Desktop**: File → Add local repo → `template-export` →
> Publish repository (untick "keep private").

## D. Maintain — push and pull (ONE direction at a time)
The framework round-trips with the repo (README.md, LICENSE.md + `assets/` at the vault root; the
build machinery in the skill's `payload/`). Keep your clone **outside the vault**; never sync both ways at
once. **Easiest:**
ask the agent to publish or update via the
`export-template` skill — it automates the steps and **pauses for your confirmation** before anything is
written publicly or back into your vault (see the skill's "Publish (push)" / "Update (pull)" flows). Manual
equivalents:

**No clone on this machine.** The repo exists on GitHub and this machine has never cloned it — the
ordinary state of a new or reimaged machine, and what the script reports as
`ERROR: <path> is not a git clone`. Clone it once, outside the vault, then proceed as this section:
`git clone https://github.com/<owner>/<repo>.git /path/to/<repo>`. §C is only for creating a repo that
does not exist yet.

**Push (vault → repo)** — you improved the framework locally and want to publish it:
```bash
git -C /path/to/second-yourself pull --ff-only                              # never clobber remote edits
bash .claude/skills/export-template/export_template.sh --push /path/to/second-yourself
cd /path/to/second-yourself && git add -A && git diff       # review → commit → push
```
`--push` overlays vault-owned files (CLAUDE.md, MANUAL.md, `README.md`/`LICENSE.md` + `assets/`,
`.claude/skills/**`, `.obsidian` config, `examples/seed`) **and** the build machinery from the skill's
`payload/` (setup.sh, .gitignore, .gitattributes), leaving `.git/` untouched. (`--sync` is an alias.)

**Pull (repo → vault)** — the repo has a newer framework (another machine, a merged PR) and you want it:
```bash
bash .claude/skills/export-template/export_template.sh --pull /path/to/second-yourself            # preview — writes nothing
bash .claude/skills/export-template/export_template.sh --pull /path/to/second-yourself --apply    # apply (+ --with-graph for colours)
```
`--pull` previews which framework files differ, then (with `--apply`) copies CLAUDE.md, MANUAL.md,
`README.md`/`LICENSE.md` + `assets/` and the skills into your vault and refreshes the `payload/`
machinery — **never** touching your knowledge (`wiki/ raw/ output/` and your own `assets/` media) or `.obsidian` config. It copies
skills per-name — including `export-template` itself; replacing the running script mid-pull is Unix-safe (the old inode stays open).

### If the GitHub repo gets renamed
GitHub redirects the old URL so pushes keep working, but fix the name promptly — a redirect dies if the
old name is ever re-registered. Three steps, in order:
1. **Detect:** the push output prints a `remote:` moved notice, or
   `gh repo view <owner>/<old-name> --json nameWithOwner` resolves to the new name.
2. **Re-point the clone:** `git -C /path/to/<clone> remote set-url origin
   https://github.com/<owner>/<new-name>.git`, then verify with `git fetch --dry-run`.
3. **Sweep the live framework files** for the old name (README.md, this RUNBOOK, SKILL.md, SPEC.md,
   `payload/setup.sh` — enumerate with `grep -r` first; after replacing, verify zero standalone old-name
   hits remain plus a positive new-name control). Log the sweep as `framework`; it ships on the next
   publish. Historical layers (wiki pages, log entries, archived quotes) keep the old name — history
   stays as written.

## Golden rules
- Edit the framework in the **vault**, not in the repo (else `--push` can't carry your change across).
- **Pull before you push** — keeps `payload/` current and avoids clobbering remote edits (merged PRs).
- **One direction per run:** `--pull` and `--push` never happen together.
- Never `git add` knowledge (`wiki/**`, `index.md`, `log.md`, `raw/**`, `output/**`); the `.gitignore`
  blocks it — don't force past it.
- Never ship personal data; keep the demo clearly deletable (`setup.sh --reset`).
