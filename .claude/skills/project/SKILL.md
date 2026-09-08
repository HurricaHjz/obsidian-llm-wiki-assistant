---
name: project
description: >
  Manage the owner's OWN working repositories (Overleaf LaTeX projects, code repositories) from the
  vault, on an explicit instruction only: /project link | open | sync | brief | snapshot | status |
  unlink, or "open my research outline", "commit and push the outline", "link this Overleaf project",
  "snapshot the paper into the wiki". The clones live OUTSIDE the vault in the project store
  (~/.llm-wiki/projects/) or are registered where they already are; the wiki holds only a registry row
  (wiki/tools/Agent Project Store.md) and commit-pinned snapshots ingested through raw/. Never runs
  from passive context, IDEAS.md or another skill; never changes the working directory; commits as
  the owner on the word commit, pushes on the word push, never force. Design and rationale:
  wiki/developments/project-store-design.md.
user-invocable: true
---

# project — the owner's working repositories beside the vault

## Contract
`wiki/developments/project-store-design.md` is the governing text; this skill adds **procedure only**
and can never relax a permission. The load-bearing rules, restated for salience:
- **Explicit instruction only.** A passive mention of a repository (an `@`-mention, a selection,
  IDEAS.md) never triggers a verb. Every verb that clones, removes or writes into the wiki shows a
  preview first and waits for the owner's go.
- **Placement.** New clones go to the project store root `~/.llm-wiki/projects/<name>/` (on this
  machine `~/.llm-wiki/` aliases `~/.aimyth/`); an existing working copy outside the vault is
  registered in place (`link --path`). A path inside the vault is refused. The sibling store
  `~/.llm-wiki/repos/` (studied third-party repositories, `repo_pack.py clone`) is never used here.
- **Nothing in a clone is knowledge.** The wiki holds the registry row and, per repository, the
  source page compiled from a snapshot pack in `raw/`; no page describes a repository from its live
  tree, no page cites a clone path except the registry.
- **No `cd`.** Every command is `git -C <absolute path> …` or names an absolute file path
  (CUSTOMISATION.md shell rules: a persisted working directory has misplaced writes twice).
- **Credentials never in a URL.** Each clone carries a git credential helper that reads its token
  from the credential file (`~/.aimyth/credentials.env`, the Agent Credential Store page); the remote
  URL is clean (`https://git.overleaf.com/<id>`, `https://github.com/<owner>/<repo>`).
- **Commits and pushes.** Commit on the word *commit*, or under a standing per-repository policy the
  owner set on its registry row; the owner is sole author (git config identity, no AI trailer, an
  imperative one-line message); push on the word *push*; never a force push, never a rewrite of
  pushed history, never a branch the instruction did not name. The vault's destructive-git guard
  (`checkout`, `restore`, `clean`, `reset --hard`) covers `git -C` forms too.
- **Lanes.** A project path reaches a lane only by an explicit grant; `git` stays the head's
  instrument; an armed hands-off head needs a pre-flight grant for any project path.
- **Logging.** `link` and `brief` are logged by the `ingest` they run (the entry's Changed line names
  the registry row and the pointer); `open`, `sync`, commits, pushes, `status` and `unlink` change no
  knowledge and log nothing.

## Registry — `wiki/tools/Agent Project Store.md`
`type: tool`, the sibling of `Agent Repo Store`. It carries the rule of use (read or written only
under this skill on the owner's instruction; never cited; never read into a compile) and one row per
repository:

`| name | kind | remotes (role: url) | local path | purpose | project page | channel | commit policy | last sync (date · sha12) | state |`

- `kind`: `overleaf` (LaTeX on Overleaf) · `code` · `other`. `channel`: `overleaf-git` (the primary,
  `https://git.overleaf.com/<project-id>`) · `github-bridge` (the fallback, a clone of Overleaf's
  GitHub mirror; each push then needs the owner's "Pull GitHub changes into Overleaf" click) ·
  `github` (a plain code repository) · `in-place` (registered where it is).
- `commit policy`: `on the word commit` (default) or the owner's standing sentence for that row.
- `state`: `linked` · `unlinked` (the row stays as the recovery record).
- The row is the single home of the path and the sha; the research-project page in `wiki/user/` gets a
  `## Repository` section holding two links only, the registry row and the latest snapshot's source page.

## Verbs

### `link <url> [--name n] [--kind overleaf|code] [--overleaf <project-id>]` · `link --path <dir> [--name n] [--kind …]`
1. **Resolve.** Name = `--name`, else the repository's basename (an Overleaf project id alone is not a
   name: ask). Refuse a name already on the registry; refuse a `--path` under the vault root; refuse a
   URL whose user part carries a password (`user:secret@host`).
2. **Channel check (URL only).** `git ls-remote <clean url>` with the helper environment; record the
   branch list (Overleaf serves one branch: the documentation says `master`, the research outline
   showed `main` on 2026-09-07; take what `ls-remote` shows). A failure here is reported, never
   worked around (a missing Overleaf git integration means the `github-bridge` channel instead).
3. **Preview and wait.** One table: source · name · destination path (or the registered path) ·
   remotes with roles · channel · commit policy · the brief selection (files and bytes) · what the
   ingest will log. WAIT for the owner's go.
4. **Clone or register.** `git clone <clean url> <store>/<name>` (full history, the remote's default
   branch); `--path`: no clone, verify `git -C <dir> rev-parse --is-inside-work-tree`. Then the
   credential helper (below) and, for `overleaf`, a reminder that Overleaf's GitHub-sync feature
   should be off for that project once direct git is in use.
5. **Registry row** on the tool page (create the page from the sibling's shape on the first link) and
   the `## Repository` section on the research-project page.
6. **Brief** (below), then report: the row, the branch, the sha, the snapshot's source page.

### `open <name>`
1. `git -C <path> fetch --all --prune`.
2. **Report first:** branch, ahead/behind per remote, modified, staged and untracked files (names), and
   the porcelain line count (`git -C <path> status --porcelain | wc -l`) so a "clean" claim carries its
   number.
3. Pull `--ff-only` when the tree is clean, else wait for the owner's word; a non-fast-forward is
   reported with both sides and a merge proposed, never forced.
4. Record the absolute path for the rest of the instruction; every later command names it.

### `sync <name> [push]`
Fetch and pull as in `open`; report divergence; push only when the instruction says push, then prove
it: `git -C <path> ls-remote origin <branch>` equals `git -C <path> rev-parse HEAD`. For an
`overleaf` repository, compile first where a TeX engine exists (`tectonic <main.tex>` in a temporary
output directory) and report the result; with no engine, say the build is unchecked.

### `brief <name>`
`open` (a pull first), then `snapshot <name> --brief`: the file tree (depth 3), the main document's
head (the `.tex` that holds `\documentclass`, its first 200 lines), and a README, abstract or outline
skeleton where one exists — at most 8 files and 32 KiB (caps set by judgement, unmeasured). A single-file
document (one `main.tex` larger than the per-file cap) has no useful head: its brief is the document itself,
packed whole under `--allow-large '<why>'` with its bibliography, within the 300 KiB hard cap (2026-09-07,
the research outline: `main.tex` 127 KB).

### `snapshot <name> [paths…] [--brief]`
The only way repository content reaches the wiki.
1. The tree must be clean for the selection (`repo_pack.py` refuses a modified tracked file or a
   selected untracked one; the owner commits first).
2. Ledger, then pack, then ingest:
   `python3 .claude/skills/gather/run_ledger.py init --id <project>-<date> --budget 1`
   `python3 .claude/skills/gather/repo_pack.py pack-and-write --repo <absolute path> --paths <p1,p2,…>
   --slice <sha12> --title "<name> snapshot <date> <sha12>" --rationale "<why these files>"
   --ledger-id <project>-<date>`
   The pack lands in the `raw/` root; `/ingest` compiles it at `standard` depth or above. The ingest's
   de-dup pre-flight matches an existing source page for the same work (the research outline already
   has one) and updates it as the new version, never a second page; the sort table's authorship rule
   sends the pack to `raw/9-originals/`. Confidence `high` by default (the owner's own work), stamped
   `audited:`.
3. Update the registry row's last-sync sha and the project page's source-page link.

### `status`
One table for every row: branch · ahead/behind per remote · porcelain count · sha on disk vs the row's
sha · path present. Name every row whose path or sha disagrees with disk; propose the fix, apply on the
owner's word.

### `unlink <name>`
1. **Preview and wait:** every branch with unpushed commits (`git -C <path> log --branches --not
   --remotes --oneline`), the stash list, untracked files, ahead/behind per remote.
2. On the owner's explicit yes: a store clone is removed (`rm -rf <store>/<name>`, its own simple
   command); a registered-in-place copy is never removed, only unregistered.
3. The row's state becomes `unlinked`; the project page keeps its links.

## The credential helper
Set once per clone, never a token in the URL; the helper reads the key at use time by grep, never by
sourcing the file (a cookie value with a `;` would execute):
```
git -C <path> config --local credential.helper ''
git -C <path> config --local --add credential.helper '!f() { echo username=git; echo "password=$(grep "^OVERLEAF_GIT_TOKEN=" "$HOME/.aimyth/credentials.env" | cut -d= -f2-)"; }; f'
```
The empty first value resets the helper list for that clone, so the machine's keychain helper (Homebrew's
`osxkeychain`, set system-wide) is not consulted and never stores a second copy of the token; the
credential file stays the single home (the first link set both lines through `git clone -c …`, 2026-09-07).
GitHub remotes use the login `gh` already holds (`gh auth setup-git` once per machine if a push
prompts). A token that expires or is revoked fails the push with an authentication error: report,
stop, no retry loop; the owner renews it in Overleaf's Account Settings and updates the credential
file's `OVERLEAF_GIT_TOKEN` line.

## Overleaf specifics
- Endpoint `https://git.overleaf.com/<project-id>`; username `git`; the token as the password.
- One branch only, no force push, no branch creation: a branch request on an `overleaf` row is refused
  with the reason.
- The GitHub-sync feature and direct git both write the same history; keep one channel per project
  (the row names it). Under `overleaf-git`, leaving the sync on is harmless lag until the owner clicks.

## Controls (CLAUDE.md §11)
- A "clean tree" claim prints its porcelain count; a "pushed" claim prints the remote sha beside HEAD.
- `status` reads the registry with a parser over the table rows, never a substring count.
- A refused command (guard, fence, authentication) is reported as the gap it is, never worked around.

## Failure handling
| Failure | Handling |
|---|---|
| Authentication error on pull or push | report and stop; the owner renews the token |
| Non-fast-forward (edits on both sides) | report both sides, propose a merge, never force |
| Uncommitted changes at `open` | reported before any pull; the pull waits for the owner's word |
| Dirty tree at `snapshot` | `repo_pack.py` refuses with the list; commit first |
| A branch requested on an `overleaf` row | refused with the reason |
| Two rows with one name | `link` refuses without `--name` |
| `--path` inside the vault | refused |
| A clone missing on a fresh machine | `link` re-creates a store clone from its row; an in-place copy is reported absent |
| No TeX engine | the compile check is skipped and the reply says the build is unchecked |
| The registry drifts from disk | `status` names the rows; fixes on the owner's word |

## Report format
Compact: the verb · the repository (name, branch, sha12) · what changed (files, commit, push proof) ·
what was written into the wiki (row, source page) · every control with its number. UK English.
