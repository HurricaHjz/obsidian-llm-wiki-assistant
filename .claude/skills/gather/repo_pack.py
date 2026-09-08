#!/usr/bin/env python3
"""repo_pack — pinned repo evidence for the raw layer (design: wiki/developments/repo-pack-design.md).

Verbs:
  clone          --url U [--sha S] [--sparse a,b]          → ~/.llm-wiki/repos/<owner>-<repo>/ (shallow, blob-filtered, sha-pinned)
  pack-and-write --repo <slug | absolute path> --paths p1,p2,… [--globs g1,g2,…] [--tree-depth N] --ledger-id ID
                 [--slice NAME] [--allow-large '<why>'] [--allow-degraded '<why>'] [--capture-write PATH]
                 Emits the pack to a temp file, self-checks it (footer marker · header count == section count),
                 then invokes capture_write.py IN-PROCESS on exit-0, propagating failure. Never a pipe.
                 `--repo` names a clone in the store by slug, or any git working copy by absolute path
                 (the project store's snapshots, wiki/developments/project-store-design.md D4, 2026-09-07).
  clean          --repo <slug>                              → removes the clone; refuses any path outside the store
                 (an absolute path elsewhere, the project store included, is refused by the same guard).

Snapshot guards (project-store design D4, 2026-09-07; they bind every pack, the study store's included):
  (a) a dirty tree is refused — a modified tracked file (staged or unstaged), or a SELECTED path that is
      untracked; an unselected untracked file (.DS_Store) never blocks — so the header sha describes the bytes packed;
  (b) the remote URL is written without any user part; a URL carrying a password part (user:secret@host) is refused
      before anything is emitted, since the pack lands in raw/, source_url and the index;
  (c) a non-GitHub remote's provenance carries the slice, defaulting to the short sha, so two packs of one remote at
      different commits get distinct raw filenames (capture_write derives the filename from the provenance URL and
      refuses an existing one — the immutability rule).

Caps (derivations in the design): --max-files 40 · per-file truncate 65536 B (judgement-set, marker emitted)
· soft-warn 122880 B (≈30k tokens: the ≈100k lane anchor minus the ≈65–70k inherited prefix)
· hard refuse 307200 B without --allow-large (2.5× the warn, stated headroom); --allow-large '<why>' lifts the hard cap AND
  the per-file truncation (2026-09-07: a single-file document is packed whole, the reason recorded in the header).
Skips, each noted in the header: binaries (NUL sniff) · git-LFS pointers · control-byte-bearing files (packed, noted).
Fence rule: per-file fence length = longest interior backtick run + 1, minimum 3 (capture_write exact-closer semantics).
"""
import argparse, datetime, os, re, subprocess, sys, tempfile

STORE = os.path.expanduser("~/.llm-wiki/repos")
FOOTER = "<!-- repo-pack:end -->"
MAX_FILES = 40
TRUNCATE_AT = 65536          # bytes/file — set by judgement, unmeasured (design §Caps)
SOFT_WARN = 122880           # 120 KiB ≈ 30k tokens
HARD_CAP = 307200            # 300 KiB = 2.5× soft-warn
LFS_HEAD = b"version https://git-lfs"
CONTROL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
USERINFO = re.compile(r"^([a-z][a-z0-9+.-]*://)([^/@]+)@")   # scheme://userinfo@… (a password part holds a colon)

def die(msg, code=2):
    print(f"repo_pack: {msg}", file=sys.stderr); sys.exit(code)

def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"command failed ({' '.join(cmd[:3])}…): {r.stderr.strip()[:300]}")
    return r.stdout.strip()

def slug_of(url):
    m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$", url)
    if not m: die(f"cannot derive owner/repo slug from URL: {url}")
    return f"{m.group(1)}-{m.group(2)}", m.group(1), m.group(2)

def clean_remote_url(url):
    """Guard (b): the URL as it may be written. A bare user part (git@host) is dropped; a password part refuses."""
    m = USERINFO.match(url)
    if not m:
        return url
    if ":" in m.group(2):
        die("remote URL carries a credential part (user:secret@host) — refused: a pack lands in raw/, source_url and the index. "
            "Put the secret in a git credential helper and set a clean remote URL")
    return m.group(1) + url[m.end():]

def dirty_paths(repo_dir, rels):
    """Guard (a): modified tracked files, plus any selected path that is untracked. Empty list = clean for this pack."""
    out = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=repo_dir, capture_output=True, text=True)
    if out.returncode != 0:
        die(f"git status failed in {repo_dir}: {out.stderr.strip()[:200]}")
    selected = set(rels)
    bad = []
    for line in out.stdout.splitlines():
        if len(line) < 4:
            continue
        code, path = line[:2], line[3:]
        if " -> " in path:                       # a rename: the new path is what the tree holds
            path = path.split(" -> ", 1)[1]
        if code == "??":
            if path in selected:
                bad.append(f"{path} (untracked, selected)")
        else:
            bad.append(f"{path} (modified {code.strip() or 'M'})")
    return bad

def provenance(url, sha, slice_name):
    """The provenance URL the pack is written under. GitHub: tree/<sha>[/<slice>]; elsewhere: url#<slice or sha12>."""
    gh = "github.com" in url
    if gh:
        base = f"{url.rstrip('/').removesuffix('.git')}/tree/{sha}"
        return base + (f"/{slice_name}" if slice_name else "")
    return f"{url}#{slice_name or sha[:12]}"

def resolve_repo(arg):
    """`--repo` as a store slug or an absolute path to any git working copy (project-store snapshots)."""
    return arg if os.path.isabs(arg) else os.path.join(STORE, arg)

def cmd_clone(a):
    os.makedirs(STORE, exist_ok=True)
    slug, _, _ = slug_of(a.url)
    dest = os.path.join(STORE, slug)
    if os.path.isdir(dest):
        have = run(["git", "rev-parse", "HEAD"], cwd=dest)
        if a.sha and have != a.sha and not a.force_refresh:
            die(f"{slug} exists at {have[:12]}, requested {a.sha[:12]} — pass --force-refresh to replace")
        print(f"reuse {dest} @ {have}"); return
    cmd = ["git", "clone", "--depth", "1", "--filter=blob:none"]
    if a.sparse: cmd += ["--sparse"]
    cmd += [a.url, dest]
    run(cmd)
    if a.sparse:
        run(["git", "sparse-checkout", "set"] + a.sparse.split(","), cwd=dest)
    if a.sha:
        run(["git", "fetch", "--depth", "1", "origin", a.sha], cwd=dest)
        run(["git", "checkout", a.sha], cwd=dest)
    sha = run(["git", "rev-parse", "HEAD"], cwd=dest)
    print(f"cloned {dest} @ {sha}")

def fence_for(text):
    runs = re.findall(r"`{3,}", text)
    return "`" * max([3] + [len(r) + 1 for r in runs])

def build_pack(repo_dir, rel_paths, url, sha, slice_name, tree_depth, rationale, truncate_at=TRUNCATE_AT):
    url = clean_remote_url(url)
    owner_repo = re.sub(r"^.*[:/]([^/:]+/[^/]+?)(?:\.git)?$", r"\1", url.rstrip("/"))
    lines, skipped, noted, sections = [], [], [], 0
    date = datetime.date.today().isoformat()
    tree = run(["find", ".", "-maxdepth", str(tree_depth), "-not", "-path", "./.git*", "-print"], cwd=repo_dir)
    bodies = []
    for rel in rel_paths:
        p = os.path.join(repo_dir, rel)
        if not os.path.isfile(p):
            die(f"selected path missing in clone: {rel}")
        raw = open(p, "rb").read()
        if raw.startswith(LFS_HEAD):
            skipped.append(f"{rel} (git-LFS pointer)"); continue
        if b"\x00" in raw[:8192]:
            skipped.append(f"{rel} (binary)"); continue
        if CONTROL.search(raw):
            noted.append(f"{rel} (control bytes present — sanitiser strip applies)")
        trunc = ""
        if truncate_at and len(raw) > truncate_at:
            raw = raw[:truncate_at]; trunc = f"\n[TRUNCATED at {truncate_at} bytes]"
        text = raw.decode("utf-8", errors="replace")
        f = fence_for(text)
        bodies.append(f"## {rel}\n\n{f}\n{text}{trunc}\n{f}\n")
        sections += 1
    if sections == 0:
        die("empty selection after skips — a pack of nothing is refused (§11)")
    slice_part = f"/{slice_name}" if slice_name and slice_name != sha[:12] else ""   # a slice equal to the sha12 is already in the title
    header = (f"# Repo pack: {owner_repo} @ {sha[:12]}{slice_part}\n\n"
              f"- repo: {url}\n- sha: {sha}\n- date: {date}\n- files: {sections}\n"
              f"- selection: {rationale}\n"
              + (f"- skipped: {'; '.join(skipped)}\n" if skipped else "")
              + (f"- noted: {'; '.join(noted)}\n" if noted else ""))
    tf = fence_for(tree)
    body = header + f"\n## Tree (depth-capped)\n\n{tf}\n{tree}\n{tf}\n\n" + "\n".join(bodies) + f"\n{FOOTER}\n"
    return body, sections

FENCED = re.compile(r"^(?P<f>`{3,})[^\n]*\n.*?^(?P=f)[ \t]*$", re.M | re.S)

def self_check(text):
    if not text.rstrip().endswith(FOOTER):
        return "footer marker missing (truncated emission?)"
    m = re.search(r"^- files: (\d+)$", text, re.M)
    prose = FENCED.sub("", text)   # packed file bodies live inside fences; count sections outside them only
    n = len(re.findall(r"^## (?!Tree)", prose, re.M))
    if not m or int(m.group(1)) != n:
        return f"header file-count {m.group(1) if m else '?'} != emitted sections {n}"
    return None

def cmd_pack(a):
    repo_dir = resolve_repo(a.repo)
    if not os.path.isdir(repo_dir): die(f"no clone at {repo_dir} — run clone first")
    url = clean_remote_url(run(["git", "remote", "get-url", "origin"], cwd=repo_dir))   # guard (b), before any emission
    sha = run(["git", "rev-parse", "HEAD"], cwd=repo_dir)
    rels = [p for p in (a.paths.split(",") if a.paths else []) if p]
    if a.globs:
        import glob as g
        for pat in a.globs.split(","):
            rels += [os.path.relpath(x, repo_dir) for x in g.glob(os.path.join(repo_dir, pat), recursive=True) if os.path.isfile(x)]
    rels = sorted(dict.fromkeys(rels))
    if not rels: die("empty selection — name --paths or --globs")
    if len(rels) > a.max_files: die(f"{len(rels)} files exceeds --max-files {a.max_files}")
    dirty = dirty_paths(repo_dir, rels)                                                  # guard (a)
    if dirty:
        die("dirty tree — the header sha would misdescribe the bytes packed; commit first. Offending: " + "; ".join(dirty[:20]))
    rationale = a.rationale or f"{len(rels)} paths named after in-clone study"
    # --allow-large lifts the per-file truncation too (2026-09-07): a single-file document (a 127 KB main.tex)
    # is packed whole under the stated reason; the hard cap below is lifted by the same flag.
    body, n = build_pack(repo_dir, rels, url, sha, a.slice, a.tree_depth,
                         rationale + (f" · allow-large: {a.allow_large}" if a.allow_large else ""),
                         truncate_at=None if a.allow_large else TRUNCATE_AT)
    size = len(body.encode())
    if size > HARD_CAP and not a.allow_large:
        die(f"pack {size} B exceeds hard cap {HARD_CAP} — split the slice or pass --allow-large '<why>'")
    if size > SOFT_WARN:
        print(f"repo_pack: WARN pack {size} B exceeds soft-warn {SOFT_WARN} (lane-budget derivation in the design)", file=sys.stderr)
    err = self_check(body)
    if err: die(f"self-check failed: {err}")
    fd, tmp = tempfile.mkstemp(suffix=".md", prefix="repo-pack-")
    with os.fdopen(fd, "w") as fh: fh.write(body)
    print(f"pack ok: {n} files · {size} B · sha {sha[:12]} · tmp {tmp}")
    if a.no_write:
        return
    prov = provenance(url, sha, a.slice)                                                # guard (c)
    cw = a.capture_write or os.path.join(os.path.dirname(os.path.abspath(__file__)), "capture_write.py")
    if not os.path.isfile(cw): die("capture_write.py not found — sole-write rule, STOP")
    cmd = [sys.executable, cw, "write", "--url", prov, "--engine", "repo-pack", "--ledger-id", a.ledger_id]
    if a.title: cmd += ["--title", a.title]
    if a.allow_degraded: cmd += ["--allow-degraded", a.allow_degraded]
    r = subprocess.run(cmd, stdin=open(tmp), )
    sys.exit(r.returncode)

def cmd_clean(a):
    target = os.path.realpath(os.path.join(STORE, a.repo))
    store = os.path.realpath(STORE)
    if not (target.startswith(store + os.sep) and len(target) > len(store) + 1):
        die(f"refusing to clean outside the store: {target}")
    if not os.path.isdir(target): die(f"no clone at {target}")
    subprocess.run(["rm", "-rf", target], check=True)
    print(f"cleaned {target}")

def main():
    ap = argparse.ArgumentParser(prog="repo_pack")
    sub = ap.add_subparsers(dest="verb", required=True)
    c = sub.add_parser("clone"); c.add_argument("--url", required=True); c.add_argument("--sha"); c.add_argument("--sparse"); c.add_argument("--force-refresh", action="store_true")
    p = sub.add_parser("pack-and-write")
    p.add_argument("--repo", required=True, help="a store slug, or an absolute path to any git working copy"); p.add_argument("--paths"); p.add_argument("--globs")
    p.add_argument("--tree-depth", type=int, default=3); p.add_argument("--ledger-id", required=True)
    p.add_argument("--slice"); p.add_argument("--title"); p.add_argument("--rationale")
    p.add_argument("--max-files", type=int, default=MAX_FILES)
    p.add_argument("--allow-large"); p.add_argument("--allow-degraded")
    p.add_argument("--capture-write"); p.add_argument("--no-write", action="store_true")
    x = sub.add_parser("clean"); x.add_argument("--repo", required=True)
    a = ap.parse_args()
    {"clone": cmd_clone, "pack-and-write": cmd_pack, "clean": cmd_clean}[a.verb](a)

if __name__ == "__main__":
    main()
