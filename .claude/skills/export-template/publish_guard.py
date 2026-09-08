#!/usr/bin/env python3
"""publish_guard.py — the publish gate's payload probe (items 121 and 132, 2026-09-06).

Scans the payload that will ACTUALLY ship for three leak classes, and halts the publish like
any other gate failure:

  probe 1  machine paths      an absolute path into a per-machine home root (macOS, Linux or
                              Windows) anywhere in any file, binary content included.
  probe 2  non-text files     a file that is not source text, anywhere outside the payload's
                              declared media directory (assets/).
  probe 3  personal strings   any string identifying THIS owner, in a file's name or its
                              bytes, unless publish-allowlist.md adjudicates that string in
                              that file. The needles are derived at run time and never
                              stored, since storing them would ship them: the agent name from
                              the vault's CUSTOMISATION.md, the git identity (name tokens,
                              email local-part tokens, the origin URL's owner segment) of the
                              vault and of the scanned repo, every component of the vault's
                              absolute path, the machine account name, and any extra line in
                              the owner-local output/publish-gate-strings.txt.

Why both, and why here: the public payload ships `.claude/skills/**` wholesale, so anything
that lands in a skill directory ships by default. On 2026-09-03 six tracked `.pyc` files
(five under `.claude/skills/`) each carried the owner's absolute vault path in their
bytecode; `.gitignore` cannot help once a file is tracked, and `strip_junk()` in
export_template.sh keys on three file NAMES (__pycache__, *.pyc, .DS_Store), so the next
artefact class slips past it. This gate keys on the observable property instead — what the
bytes are, and where in the payload they sit — so it needs no list to maintain.

Ship-truth: with a git work tree the file set and the file CONTENTS both come from the
INDEX (`ls-files -s` + `cat-file --batch`), which is exactly what a commit writes; an
unstaged edit between overlay and gate therefore cannot make the guard scan a tree that
differs from the publish. A symlink's blob holds its target, so a symlink into a home
directory is caught by probe 1. Without a git work tree (a fresh build directory) the tree
is walked on disk and the output says so.

Probe 3 replaces the hand-run personal-strings gate of the export-template SKILL.md, which
depended on the operator recalling every derivation source; on 2026-09-06 one run omitted the
punctuation-led components of the vault path and missed a fixture hit. Its rules follow
publish-allowlist.md, which is parsed rather than read: an entry names the files it covers, a
permanent entry is uncapped inside them, a provisional entry carries a per-file OCCURRENCE
count and an expiry release, and a placeholder key covers a derivation class so the shipped
allowlist never has to quote personal data.

Usage:
  python3 publish_guard.py [--vault <vault>] [--allowlist <file>] [--release <ver>]
                           [--print-needles] <repo-clone-or-build-dir>

  --vault        the vault probe 3 derives from; default is three directories above this
                 script. --allowlist likewise defaults to the file beside it, and an override
                 of either is named on the gate's own output line.
  --release      the candidate version: a provisional allowlist entry whose expiry it has
                 reached becomes a finding. Without it every run still reports the pending
                 expiries, for the recap to check against the version it derives.
  --print-needles  print the derived needles and their sources to the terminal, for
                 inspection during an adjudication. Never part of the gate's own output.

Exit codes follow throttle.py's gate convention:
  0  clean  — one line naming what was scanned AND the self-control tally
  1  findings — the publish halts; every finding printed with its evidence
  2  broken premise — one `PROBE FAILED:` line, never a clean report

Premise failures (all exit 2, never a silent pass): the path is missing or not a directory;
the file set is empty; the set is not a framework payload (no CLAUDE.md, or no file under
.claude/skills/); any git command fails or a blob reads short; any self-control fails; no
vault is found and none is given; CUSTOMISATION.md has lost its agent_name line; the
allowlist is missing, unreadable, parses to zero entries, or holds an entry that names no
file, an unknown placeholder, a count on a permanent entry, a missing count on a provisional
one, or two paths covering one payload file; the corpus control matches nothing.

Suite: test_publish_guard.sh beside this file. Design: wiki/developments/publish-payload-guard-design.md
"""

import getpass
import os
import re
import subprocess
import sys

MEDIA_ROOT = "assets/"      # the payload's declared media directory (SPEC.md): the README
                            # images live here and the shipped .gitignore force-tracks them.
NUL_WINDOW = 8000           # git's own text/binary window, so both classifiers agree
MAX_SHOWN = 40              # per probe, so a broken payload cannot flood the gate output
BATCH = 200                 # shas per `cat-file --batch` write (see read_index)

# An absolute path into a per-machine home root, matched two ways because context differs
# with content class — the property the guard already computes for probe 2.
#   TEXT: the negative lookbehind is load-bearing. A path preceded by a path character is a
#   fragment, not an absolute path: "$W" + the Linux home root is a fixture path in
#   deep-lint/style-rerun/test_style_rerun.sh, and a URL segment of the same spelling is a
#   URL. `/` stays OUT of the exclusion class, so a `file://` URL into a home root still fires.
#   BYTES: no lookbehind. In a non-text file the preceding byte is data, not context — the
#   2026-09-03 bytecode carried its path behind a marshal length byte ('o'), which the text
#   lookbehind silently swallowed. Found by prototyping on the live payload, 2026-09-06:
#   before this split the guard MISSED the exact artefact it was built for.
#   ROOTS: all three a home directory can have — the macOS, Linux and Windows ones. Keying
#   on the two this machine happens to use is the "instance constant" failure §12 warns
#   about; a contributor's fixture is as public as ours (critic finding, 2026-09-06).
_POSIX = rb"/(?:Users|home)/[A-Za-z0-9._-]+"
_WIN = rb"[A-Za-z]:\\Users\\[A-Za-z0-9._-]+"
HOME_TEXT_RE = re.compile(rb"(?<![A-Za-z0-9._$~-])" + _POSIX + rb"|" + _WIN)
HOME_BYTES_RE = re.compile(_POSIX + rb"|" + _WIN)

# This file SHIPS inside `.claude/skills/**`, so it is inside its own scan scope — by design:
# the guard exempts nothing, because an exemption is the hole the next artefact walks through.
# Every example home path below is therefore ASSEMBLED at import time, never written as a
# literal, so the invariant stays absolute: no shipped file contains an absolute home path.
# (Found by prototyping the guard on the live payload before review, 2026-09-06: written as
# literals, this file and its suite halted the publish on themselves.)
_U = "/U" + "sers"
_H = "/h" + "ome"

# Self-controls: every run proves both probes can still fire and still stay quiet.
# Each row is (buffer, treat-as-text, must-match).
PATH_CONTROLS = (
    (('OUT = "%s/example/vault/wiki"' % _U).encode(), True, True),    # a machine path fires
    (('cat "$W%s/.llm-wiki/last-run.txt"' % _H).encode(), True, False),  # a fragment does not
    (b'the agent home is ~/.llm-wiki/ and $HOME/notes', True, False),  # tilde/var forms do not
    (('see https://example.com%s/guide' % _U).encode(), True, False),  # a URL segment does not
    (('\x6f%s/example/vault/mod.py' % _U).encode("latin-1"), False, True),  # bytes behind a
    (('\x6f%s/example/vault/mod.py' % _U).encode("latin-1"), True, False),  # length byte: the
    (b'OUT = "D:' + b'\\Users\\example\\vault"', True, True),   # the Windows home root fires
)                                              # binary rule fires, the text rule rightly does not
CLASS_CONTROLS = (
    (b"\x89PNG\r\n\x1a\n\x00\x00", False),   # NUL-bearing bytes are not text
    (b"", True),                             # an empty file (.gitkeep) IS text
    (b"# a plain source line\n", True),      # ordinary source is text
)

# ── probe 3: personal strings ────────────────────────────────────────────────
# The strings that identify THIS owner are derived at run time from the vault beside this
# script, never stored, because storing them would ship them. Deriving them also puts the
# derivation under test, which is the half the hand-run gate kept losing: the 2026-09-06 run
# that omitted the punctuation-led components of the vault path missed a fixture hit.
MIN_NEEDLE = 4              # bytes. Set by judgement against the live needle set, whose
                            # shortest member is 5 bytes. The floor drops the generic short
                            # components a system or temp root contributes (var, tmp, usr,
                            # opt, lib, a single-letter mount) and keeps every owner string
                            # this vault derives. A deliberately short string belongs in the
                            # gate-strings file, which is exempt from the floor.
ALLOWLIST_NAME = "publish-allowlist.md"                  # adjudications, beside this script
GATE_STRINGS_REL = "output/publish-gate-strings.txt"     # owner-local extras, never shipped
CONTROL_NEEDLE = b"CLAUDE.md"   # check_payload_shape asserts this path is in the payload, so
                                # any pass that iterated the corpus at all matches it once.
# The home-root markers are probe 1's own grammar (_POSIX's alternation), so this is one
# source of truth, not a second instance constant. They are the OS's word rather than the
# owner's and identify nobody outside path context, which probe 1 owns. The account name that
# FOLLOWS the marker stays a needle, and a vault outside a home root loses nothing.
HOME_MARKERS = ("Users", "home")
TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)   # tokens of a person name or an email local part
DRIVE_RE = re.compile(r"^[A-Za-z]:$")
ORIGIN_RE = re.compile(r"(?:://[^/]+/|:)([^/]+)/[^/]+?(?:\.git)?/?$")
AGENT_NAME_RE = re.compile(r"^[ \t]*-[ \t]*\*\*agent_name\*\*[ \t]*:(.*)$", re.M)

# An allowlist key is a literal string or a placeholder standing for a derivation class,
# because the allowlist SHIPS and may not quote personal data. Every class is expressible, so
# an adjudication never has to fall back to writing the string out.
PLACEHOLDERS = {
    "<agent name>": "agent-name",
    "<repo owner handle>": "origin-owner",
    "<licence holder's legal name>": "name-token",
    "<owner email token>": "email-token",
    "<machine account name>": "account",
    "<vault path component>": "path-component",
    "<extra gate string>": "extra",
}
ENTRY_RE = re.compile(r"^-[ \t]+(.+?)[ \t]+::[ \t]+(.+?)[ \t]+::[ \t]+(.+)$", re.M)
ALLOW_PATH_RE = re.compile(r"`([^`]+)`(?:[ \t]*\((\d+)\))?")
EXPIRY_RE = re.compile(r"PROVISIONAL.{0,40}?expires at (v?[0-9][0-9.]*)", re.I | re.S)
VERSION_RE = re.compile(r"^v?([0-9]+(?:\.[0-9]+)*)$")


class Premise(Exception):
    """A broken premise: one PROBE FAILED line and exit 2, never a clean report."""


def is_text(blob):
    """git's own rule, applied to our bytes: a NUL in the first NUL_WINDOW bytes."""
    return b"\x00" not in blob[:NUL_WINDOW]


def first_nul(blob):
    return blob[:NUL_WINDOW].find(b"\x00")


def run_git(root, args):
    """Run one git command under `root`; any non-zero exit is a broken premise."""
    cmd = ["git", "-C", root] + args
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as err:
        raise Premise("cannot run git (%s)" % err)
    if p.returncode != 0:
        raise Premise("`%s` exited %d: %s"
                      % (" ".join(cmd), p.returncode,
                         p.stderr.decode("utf-8", "replace").strip()[:200]))
    return p.stdout


def has_index(root):
    """Is THIS directory a repository whose index will be committed?

    Keyed on a `.git` entry at the root itself (a directory, or a file for a linked work
    tree), never on `rev-parse --is-inside-work-tree`: the default build directory sits
    INSIDE the vault repo, where rev-parse says yes and `ls-files` then returns the vault's
    tracked paths under that prefix — none, since the build is gitignored — so the guard
    would call a real payload empty. A build tree has no `.git` of its own; a publish clone
    does. When one exists, git must work: falling back to the disk here would silently
    change what the gate scanned.
    """
    if not os.path.exists(os.path.join(root, ".git")):
        return False
    try:
        p = subprocess.run(["git", "-C", root, "rev-parse", "--git-dir"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as err:
        raise Premise("%s has a .git entry but git will not run (%s)" % (root, err))
    if p.returncode != 0:
        raise Premise("%s has a .git entry but `git rev-parse` exited %d"
                      % (root, p.returncode))
    return True


def read_index(root):
    """Yield (path, mode, blob) for every staged entry — the bytes a commit would write."""
    out = run_git(root, ["ls-files", "-s", "-z"])
    entries = []
    for rec in out.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        bits = meta.split()
        if len(bits) < 3 or not path:
            raise Premise("unparseable `git ls-files -s` record: %r" % rec[:80])
        entries.append((path.decode("utf-8", "surrogateescape"),
                        bits[0].decode(), bits[1].decode()))
    if not entries:
        return []
    # gitlinks (submodules) have no blob to read — reported, never silently skipped.
    blobs = [e for e in entries if e[1] != "160000"]
    proc = subprocess.Popen(["git", "-C", root, "cat-file", "--batch"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    result = []
    # Chunked on purpose: writing every sha at once deadlocks a large payload — git stops
    # reading stdin while its own stdout pipe is full of blob bytes nobody is draining yet.
    # A chunk of shas is a few KB, always smaller than the pipe buffer, and its responses are
    # read before the next chunk is written, so neither side can block.
    for i in range(0, len(blobs), BATCH):
        chunk = blobs[i:i + BATCH]
        try:
            proc.stdin.write(("\n".join(sha for _, _, sha in chunk) + "\n").encode())
            proc.stdin.flush()
        except (BrokenPipeError, OSError) as err:
            raise Premise("`git cat-file --batch` closed its input early (%s)" % err)
        for path, mode, sha in chunk:
            header = proc.stdout.readline()
            if not header:
                raise Premise("`git cat-file --batch` ended early at %s" % path)
            parts = header.split()
            if len(parts) != 3 or parts[1] != b"blob":
                raise Premise("`git cat-file --batch` answered %r for %s" % (header[:80], path))
            size = int(parts[2])
            blob = proc.stdout.read(size)
            if len(blob) != size:
                raise Premise("short read for %s (%d of %d bytes)" % (path, len(blob), size))
            proc.stdout.read(1)          # the trailing newline cat-file adds
            result.append((path, mode, blob))
    proc.stdin.close()
    proc.stdout.close()
    proc.wait()
    if proc.returncode != 0:
        raise Premise("`git cat-file --batch` exited %d" % proc.returncode)
    for path, mode, _sha in entries:
        if mode == "160000":
            result.append((path, mode, None))   # unreadable by construction
    return result


def read_tree(root):
    """No index: walk the directory. Used for a fresh build dir, which is not a repo."""
    result = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in sorted(files):
            full = os.path.join(base, name)
            if os.path.islink(full):
                target = os.readlink(full)
                result.append((os.path.relpath(full, root), "120000", target.encode()))
                continue
            try:
                with open(full, "rb") as fh:
                    result.append((os.path.relpath(full, root), "100644", fh.read()))
            except OSError as err:
                raise Premise("cannot read %s (%s)" % (full, err))
    return result


def home_hits(blob, text):
    """Machine-path matches in one file. The rule follows the content class (see the regexes)."""
    return (HOME_TEXT_RE if text else HOME_BYTES_RE).finditer(blob)


# ── probe 3, derivation ──────────────────────────────────────────────────────

def path_components(path):
    """The owner's own components of an absolute path, in order.

    A leading drive letter and a leading home-root marker are the machine's, not the owner's
    (see HOME_MARKERS); everything from the account name onward is the owner's. Components
    are kept VERBATIM and never split: splitting a punctuation-led component into its word
    would fire on ordinary prose (114 hits of one such word across 24 files of the live
    payload, measured 2026-09-06) while adding no personal string, because the personal shape
    IS the component and probe 1 already owns the full-path form.
    """
    comps = [c for c in re.split(r"[\\/]+", path) if c]
    if comps and DRIVE_RE.match(comps[0]):
        comps = comps[1:]
    if comps and comps[0] in HOME_MARKERS:
        comps = comps[1:]
    return comps


def name_tokens(text):
    """Word tokens of a person name or an email local part.

    Tokenised where a path component is not, because the whole string is useless as a needle
    and one of its tokens is the string that leaks: a legal name carries titles and brackets,
    an email local part joins an id to a handle. A whitespace split would keep the brackets
    and never match the bare given name — the case DERIVATION_CONTROLS pins.
    """
    return TOKEN_RE.findall(text)


def origin_owners(urls):
    """The owner segment of each remote URL, both the https and the ssh spelling."""
    out = []
    for url in urls:
        m = ORIGIN_RE.search(url.strip())
        if m:
            out.append(m.group(1))
    return out


def read_agent_name(vault):
    """The `agent_name` value from the vault's CUSTOMISATION.md Settings list.

    A missing line is a broken premise (the file's shape changed under us); a present and
    blank one is legitimate — the shipped setup.sh seeds it blank — and yields no needle.
    """
    path = os.path.join(vault, "CUSTOMISATION.md")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as err:
        raise Premise("cannot read CUSTOMISATION.md (%s)" % err)
    m = AGENT_NAME_RE.search(text)
    if not m:
        raise Premise("CUSTOMISATION.md has no `agent_name` line in its Settings list — "
                      "the preference layer's shape changed, so the agent name cannot be derived")
    value = re.split(r"\s[—-]\s", m.group(1).strip(), maxsplit=1)[0].strip()
    return value


def git_identity(root):
    """(name tokens, email local-part tokens, origin owners) from one repository's config.

    Read from the vault AND from the scanned repo: the clone is what commits the payload, so
    its identity is as publishable as the vault's. A directory with no git config contributes
    nothing rather than failing — an unset identity is legitimate.
    """
    def cfg(key):
        try:
            p = subprocess.run(["git", "-C", root, "config", "--get", key],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError:
            return ""
        return p.stdout.decode("utf-8", "replace").strip() if p.returncode == 0 else ""
    names = name_tokens(cfg("user.name"))
    email = cfg("user.email")
    local = name_tokens(email.split("@", 1)[0]) if email else []
    urls = [u for u in (cfg("remote.origin.url"), cfg("remote.origin.pushurl")) if u]
    return names, local, origin_owners(urls)


def account_names():
    """The machine account name, which a vault outside a home root would not otherwise yield."""
    out = []
    try:
        out.append(getpass.getuser())
    except Exception:
        pass
    home = os.path.basename(os.path.expanduser("~").rstrip("/\\"))
    if home:
        out.append(home)
    return out


def read_gate_strings(vault):
    """Extra needles the owner keeps outside the vault's derivable surfaces.

    Affiliation, a second handle, an ORCID: strings only the owner can name. The file is
    owner-local and never shipped; absent is normal and reported, unreadable is a premise
    failure, and its lines are exempt from MIN_NEEDLE because the owner wrote them on purpose.
    """
    path = os.path.join(vault, GATE_STRINGS_REL)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as err:
        raise Premise("cannot read %s (%s)" % (GATE_STRINGS_REL, err))
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def derive_needles(vault, repos):
    """{needle.lower(): (text, {source classes})} — every owner string, with where it came from.

    A needle can arise from two sources (the agent name that is also the vault directory; the
    handle that is also an email token), so sources are a SET and an allowlist placeholder
    matches when its class is anywhere in that set. Anything else would make a clean payload
    halt on a needle whose entry named the other source.
    """
    found = {}
    dropped = []

    def add(text, source):
        text = (text or "").strip()
        if not text:
            return
        if source != "extra" and len(text.encode("utf-8")) < MIN_NEEDLE:
            dropped.append(text)
            return
        key = text.lower()
        if key not in found:
            found[key] = [text, set()]
        found[key][1].add(source)

    add(read_agent_name(vault), "agent-name")
    for root in repos:
        names, local, owners = git_identity(root)
        for t in names:
            add(t, "name-token")
        for t in local:
            add(t, "email-token")
        for t in owners:
            add(t, "origin-owner")
    for form in {os.path.abspath(vault), os.path.realpath(vault)}:
        for c in path_components(form):
            add(c, "path-component")
    for a in account_names():
        add(a, "account")
    extra = read_gate_strings(vault)
    for s in (extra or []):
        add(s, "extra")
    return ({k: (v[0], frozenset(v[1])) for k, v in found.items()},
            sorted(set(dropped)), extra)


# ── probe 3, matching ────────────────────────────────────────────────────────

def needle_pattern(needles):
    """One alternation, longest first, every needle escaped.

    Longest first because per-file caps are per needle: with a short needle ahead of a longer
    one that contains it, every hit is attributed to the short needle and the long one's cap
    is never tested.
    """
    if not needles:
        return None
    parts = sorted(needles, key=len, reverse=True)
    return re.compile(b"|".join(re.escape(p.encode("utf-8")) for p in parts), re.IGNORECASE)


def scan_needles(entries, pattern):
    """{(needle.lower(), path): [count, first offset, sample, in name, in content]}.

    Both branches matter: a personal string leaks as readily through a file NAME as through
    its bytes, and through a compiled artefact's bytes as readily as through source text.
    """
    hits = {}
    if pattern is None:
        return hits

    def record(path, blob, in_name):
        for m in pattern.finditer(blob):
            key = (m.group().decode("utf-8", "replace").lower(), path)
            row = hits.get(key)
            if row is None:
                hits[key] = [1, m.start(), m.group().decode("utf-8", "replace"),
                             in_name, not in_name]
            else:
                row[0] += 1
                if in_name:
                    row[3] = True
                else:
                    row[4] = True

    for path, _mode, blob in entries:
        record(path, path.encode("utf-8", "surrogateescape"), True)
        if blob is not None:
            record(path, blob, False)
    return hits


# ── probe 3, the allowlist ───────────────────────────────────────────────────

def parse_version(text):
    m = VERSION_RE.match(text.strip())
    if not m:
        return None
    return tuple(int(x) for x in m.group(1).split("."))


def version_at_least(candidate, expiry):
    """True when the candidate release has reached the expiry, v1.0 and v1.0.0 comparing equal."""
    n = max(len(candidate), len(expiry))
    return candidate + (0,) * (n - len(candidate)) >= expiry + (0,) * (n - len(expiry))


def read_allowlist(path):
    """Parse the adjudications. Every rule the file states about itself is enforced here.

    Each entry names the FILES it covers, permanent entries included: a permanent allowance
    that floated free of its files would let the owner's name spread from the LICENSE line it
    was adjudicated for into any file that later quoted it, and still report clean.
    """
    if not os.path.exists(path):
        raise Premise("%s is missing — a publish cannot be adjudicated without it" % ALLOWLIST_NAME)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as err:
        raise Premise("cannot read %s (%s)" % (ALLOWLIST_NAME, err))
    entries = []
    for key, where, why in ENTRY_RE.findall(text):
        key = key.strip()
        if key.startswith("<") and key.endswith(">") and key not in PLACEHOLDERS:
            raise Premise("%s entry `%s` names an unknown placeholder — the known ones are %s"
                          % (ALLOWLIST_NAME, key, ", ".join(sorted(PLACEHOLDERS))))
        paths = {}
        for p, count in ALLOW_PATH_RE.findall(where):
            paths[p.strip("/")] = int(count) if count else None
        if not paths:
            raise Premise("%s entry `%s` names no file in backticks — an allowance with no "
                          "file cannot be scoped" % (ALLOWLIST_NAME, key))
        m = EXPIRY_RE.search(where)
        expiry = parse_version(m.group(1)) if m else None
        provisional = m is not None
        if provisional and expiry is None:
            raise Premise("%s entry `%s` is provisional but its expiry release does not parse"
                          % (ALLOWLIST_NAME, key))
        missing = [p for p, c in paths.items() if (c is None) == provisional]
        if missing:
            raise Premise("%s entry `%s`: %s %s a per-file count"
                          % (ALLOWLIST_NAME, key, ", ".join(sorted(missing)),
                             "needs" if provisional else "must not carry"))
        entries.append({"key": key, "placeholder": PLACEHOLDERS.get(key),
                        "provisional": provisional, "expiry": expiry,
                        "expiry_text": m.group(1) if m else "", "paths": paths, "why": why})
    if not entries:
        raise Premise("%s parsed to 0 entries — its format changed and every adjudication "
                      "would silently stop applying" % ALLOWLIST_NAME)
    return entries


def entry_cap(entry, path):
    """The cap this entry sets for one payload file, or None when it does not cover it.

    Suffix matching is anchored on a path component, so an entry naming a file never covers a
    different file whose name merely ends with those characters.
    """
    # A literal key writes its own string into this file, so the entry covers its key inside
    # the file that declares it. Not an exemption: it is scoped to the one string the entry
    # already adjudicates, and any OTHER personal string reaching the allowlist still halts.
    # Found by prototyping on the live payload, 2026-09-06 — the first entry with a literal
    # key halted the publish on the allowlist itself.
    if not entry["placeholder"] and (path == ALLOWLIST_NAME or path.endswith("/" + ALLOWLIST_NAME)):
        return -1
    # Longest suffix wins, and the binding is unambiguous by construction: two DISTINCT
    # entry paths of equal length cannot both be component-anchored suffixes of one payload
    # path, so a tie needs no rule. (An ambiguity check was written here and removed the same
    # day once that was proved: a branch that can never run is worse than none, because it
    # reads as a hazard someone handled.)
    best = None
    for p, count in entry["paths"].items():
        if path == p or path.endswith("/" + p):
            if best is None or len(p) > len(best[0]):
                best = (p, count)
    if best is None:
        return None
    return (best[1] if entry["provisional"] else -1)     # -1 = covered, uncapped


def adjudicate(hits, needles, entries):
    """Split probe 3's hits into allowed and unallowed, and count each entry's use."""
    unallowed, used = [], {i: 0 for i in range(len(entries))}
    allowed_total = 0
    for (needle, path), row in sorted(hits.items()):
        count, off, sample, in_name, in_content = row
        sources = needles.get(needle, ("", frozenset()))[1]
        verdict = None
        for i, entry in enumerate(entries):
            if entry["placeholder"]:
                if entry["placeholder"] not in sources:
                    continue
            elif entry["key"].lower() != needle:
                continue
            cap = entry_cap(entry, path)
            if cap is None:
                verdict = verdict or ("scope", entry)
                continue
            if cap == -1 or count <= cap:
                used[i] += count
                verdict = ("allowed", entry)
                break
            verdict = ("cap", entry, cap)
        if verdict and verdict[0] == "allowed":
            allowed_total += count
            continue
        where = "name" if in_name and not in_content else \
                ("content" if in_content and not in_name else "name+content")
        if verdict and verdict[0] == "cap":
            why = "over the cap of %d in `%s`" % (verdict[2], verdict[1]["key"])
        elif verdict and verdict[0] == "scope":
            why = "`%s` allows this string, but not in this file" % verdict[1]["key"]
        else:
            why = "no allowlist entry"
        unallowed.append((path, off, sample, count, where,
                          ",".join(sorted(sources)) or "?", why))
    return unallowed, used, allowed_total


# Probe 3's controls come in two halves, because its incident class was a DERIVATION
# omission, not a matching failure: the first half pins what the derivation returns for
# fixture inputs, the second pins the matcher. Every home path below is assembled, never
# written as a literal, for the reason given above PATH_CONTROLS.
_EX = _U + "/exampleacct/Cloud-Store99/@Lab/@work/MyVault"
DERIVATION_CONTROLS = (
    ("path components", lambda: path_components(_EX),
     ["exampleacct", "Cloud-Store99", "@Lab", "@work", "MyVault"]),
    ("path components, no home root", lambda: path_components("/srv/data/@Lab/MyVault"),
     ["srv", "data", "@Lab", "MyVault"]),
    ("name tokens", lambda: name_tokens("Ada (Byron) Lovelace"), ["Ada", "Byron", "Lovelace"]),
    ("email local tokens", lambda: name_tokens("12345678+SomeHandle"), ["12345678", "SomeHandle"]),
    ("origin owners", lambda: origin_owners(["https://example.com/SomeHandle/a-repo.git",
                                             "git@example.com:Other-Handle/b.git"]),
     ["SomeHandle", "Other-Handle"]),
)
# (needles, buffer, expected match count) — the matcher itself.
STRING_CONTROLS = (
    (["Lovelace"], b"see Lovelace and lovelace", 2),      # fires, case-insensitively
    (["Lovelace"], b"see Babbage", 0),                    # stays quiet on an absent needle
    (["a.c"], b"abc and a.c", 1),                         # a needle is a literal, not a regex
    (["Ada", "Ada-Lovelace"], b"Ada-Lovelace", 1),        # longest first: one hit, the long one
)


def self_controls():
    """Prove all three probes still fire and still stay quiet. A failure is a broken premise."""
    path_ok = 0
    for buf, text, should_match in PATH_CONTROLS:
        if bool(list(home_hits(buf, text))) == should_match:
            path_ok += 1
        else:
            raise Premise("machine-path control failed on %r (text=%s, expected match=%s)"
                          % (buf[:60], text, should_match))
    class_ok = 0
    for buf, should_be_text in CLASS_CONTROLS:
        if is_text(buf) == should_be_text:
            class_ok += 1
        else:
            raise Premise("text-class control failed on %r (expected text=%s)"
                          % (buf[:20], should_be_text))
    string_ok = 0
    for label, fn, expected in DERIVATION_CONTROLS:
        got = fn()
        if got == expected:
            string_ok += 1
        else:
            raise Premise("derivation control `%s` returned %r, expected %r" % (label, got, expected))
    for needles, buf, expected in STRING_CONTROLS:
        got = sum(1 for _ in needle_pattern(needles).finditer(buf))
        if got == expected:
            string_ok += 1
        else:
            raise Premise("string-match control failed on %r (%d matches, expected %d)"
                          % (buf[:40], got, expected))
    # Both branches of the corpus scan, on a synthetic corpus: the needle in a file NAME, and
    # the needle in a file's BYTES behind a NUL so the entry is binary. A scan that lost
    # either branch would still match the real payload's guaranteed path hit and look fine.
    probe = scan_needles([("dir/name-" + CONTROL_NEEDLE.decode(), "100644", b"nothing here"),
                          ("dir/blob.bin", "100644", b"\x00\x00" + CONTROL_NEEDLE)],
                         needle_pattern([CONTROL_NEEDLE.decode()]))
    branches = {p: row for (_n, p), row in probe.items()}
    name_row = branches.get("dir/name-" + CONTROL_NEEDLE.decode())
    blob_row = branches.get("dir/blob.bin")
    if not (name_row and name_row[3]) or not (blob_row and blob_row[4]):
        raise Premise("corpus-branch control failed: the scan matched %s, so one of its two "
                      "branches (file name, file bytes) did not run" % sorted(branches))
    string_ok += 2
    return path_ok, class_ok, string_ok


def check_staged(root):
    """The index must already hold the payload, or the gate scans the LAST publish.

    Run before `git add -A`, the guard would read a stale index and report clean on a tree
    nobody staged. Both halves are needed: `--others` catches a payload never added, `diff`
    catches a tracked file edited after the overlay.
    """
    others = run_git(root, ["ls-files", "--others", "--exclude-standard", "-z"])
    if others.strip(b"\0"):
        n = len([x for x in others.split(b"\0") if x])
        raise Premise("%d file(s) in %s are untracked — stage the payload first "
                      "(`git add -A`), or the gate reads the previous publish" % (n, root))
    try:
        # Submodules are excluded: a gitlink's worktree state is not part of the bytes this
        # payload ships, and the scan reports the entry as unscannable either way.
        p = subprocess.run(["git", "-C", root, "diff", "--quiet", "--ignore-submodules=all"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as err:
        raise Premise("cannot run git diff (%s)" % err)
    if p.returncode == 1:
        raise Premise("tracked files in %s differ from the index — stage them first "
                      "(`git add -A`), or the gate scans bytes that will not ship" % root)
    if p.returncode != 0:
        raise Premise("`git diff --quiet` exited %d in %s" % (p.returncode, root))


def check_payload_shape(paths):
    """Keyed on the payload's observable shape, so an empty or partial tree cannot pass."""
    if not paths:
        raise Premise("payload holds no files — nothing was scanned")
    if "CLAUDE.md" not in paths:
        raise Premise("no CLAUDE.md at the payload root — not a framework payload")
    if not any(p.startswith(".claude/skills/") for p in paths):
        raise Premise("no file under .claude/skills/ — not a framework payload")
    # The vault itself also has CLAUDE.md and .claude/skills/, so the two checks above pass
    # on it. A payload never carries the owner's preference layer (SPEC.md, STRIP list), so
    # its presence says this tree is a vault, not something about to be published.
    if "CUSTOMISATION.md" in paths:
        raise Premise("CUSTOMISATION.md is present — this is a vault, not a publish payload")


def scan(entries):
    machine, nontext, unreadable = [], [], []
    for path, mode, blob in entries:
        if blob is None:
            unreadable.append(path)
            continue
        text = is_text(blob)
        for m in home_hits(blob, text):
            machine.append((path, m.start(), m.group().decode("utf-8", "replace")))
        if path.startswith(MEDIA_ROOT):
            continue                      # the declared media directory: images belong here
        if not text:
            nontext.append((path, len(blob), first_nul(blob)))
    return machine, nontext, unreadable


def find_vault(override):
    """The vault whose owner strings probe 3 derives: three directories up, or --vault.

    Probes 1 and 2 need only a payload; probe 3 needs the owner's preference layer and path.
    A vault that cannot be found is a broken premise rather than a skipped probe, because a
    skip would print `check: clean` over a scan that never searched for a personal string.
    """
    cand = override or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                    "..", "..", ".."))
    missing = [f for f in ("CLAUDE.md", "CUSTOMISATION.md")
               if not os.path.exists(os.path.join(cand, f))]
    if missing:
        raise Premise("cannot derive the owner's strings: %s has no %s. Pass --vault <path> "
                      "to point at the vault this payload was built from."
                      % (cand, " or ".join(missing)))
    return cand


def parse_args(argv):
    root = vault = release = allowlist = None
    show_needles = False
    rest = argv[1:]
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--print-needles":
            show_needles = True
        elif a in ("--vault", "--release", "--allowlist"):
            if i + 1 >= len(rest):
                raise Premise("%s needs a value" % a)
            i += 1
            if a == "--vault":
                vault = rest[i]
            elif a == "--release":
                release = rest[i]
            else:
                allowlist = rest[i]
        elif a.startswith("--"):
            raise Premise("unknown option %s" % a)
        elif root is None:
            root = a
        else:
            raise Premise("more than one directory given (%s and %s)" % (root, a))
        i += 1
    if root is None:
        raise Premise("usage: publish_guard.py [--vault <vault>] [--allowlist <file>] "
                      "[--release <ver>] [--print-needles] <repo-clone-or-build-dir>")
    if release is not None and parse_version(release) is None:
        raise Premise("--release %s does not parse as a version" % release)
    return root, vault, release, allowlist, show_needles


def main(argv):
    root, vault_arg, release, allow_arg, show_needles = parse_args(argv)
    if not os.path.isdir(root):
        raise Premise("%s is not a directory" % root)
    root = os.path.abspath(root)

    vault = find_vault(vault_arg)
    # --allowlist exists so the suite can exercise a malformed adjudication file without
    # mutating the shipped one; an override is named on the gate's own output line, because a
    # publish run that quietly used a different adjudication set would be invisible in the recap.
    allow_path = allow_arg or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                           ALLOWLIST_NAME)
    entries_allow = read_allowlist(allow_path)
    needles, dropped, extra = derive_needles(vault, [vault, root])
    path_ok, class_ok, string_ok = self_controls()
    if show_needles:
        for key in sorted(needles):
            print("needle  %-28s  %s" % (needles[key][0], ",".join(sorted(needles[key][1]))))

    indexed = has_index(root)
    if indexed:
        check_staged(root)
    entries = read_index(root) if indexed else read_tree(root)
    check_payload_shape({p for p, _m, _b in entries})
    machine, nontext, unreadable = scan(entries)

    control = sum(row[0] for row in scan_needles(entries, needle_pattern([CONTROL_NEEDLE.decode()])).values())
    if control == 0:
        raise Premise("the corpus control matched nothing across %d files — the scan searched "
                      "nothing, so a clean result would be a claim about an empty set" % len(entries))
    unallowed, used, allowed_total = adjudicate(
        scan_needles(entries, needle_pattern([n[0] for n in needles.values()])), needles, entries_allow)

    expired = []
    for i, entry in enumerate(entries_allow):
        if entry["provisional"] and release is not None \
                and version_at_least(parse_version(release), entry["expiry"]):
            expired.append((entry["key"], entry["expiry_text"]))

    scanned = len(entries)
    total = sum(len(b) for _p, _m, b in entries if b is not None)
    source = ("the index of %s" % root) if indexed \
             else ("the on-disk tree at %s (no git index)" % root)
    by_source = {}
    for _text, sources in needles.values():
        for s in sources:
            by_source[s] = by_source.get(s, 0) + 1
    # Public-safe by construction: counts and class names only, never a needle and never the
    # vault path — this line is quoted in the publish recap.
    strings_line = ("personal-strings: %d needle(s) from %d class(es) [%s]%s; %d allowlisted "
                    "hit(s), %d entr(ies) of %d used%s; extra strings: %s"
                    % (len(needles), len(by_source),
                       ", ".join("%s %d" % (k, v) for k, v in sorted(by_source.items())),
                       (", %d below the %d-byte floor" % (len(dropped), MIN_NEEDLE)) if dropped else "",
                       allowed_total, sum(1 for v in used.values() if v), len(entries_allow),
                       "" if all(used.values()) else
                       " (inert: %s)" % ", ".join(entries_allow[i]["key"]
                                                  for i, v in sorted(used.items()) if not v),
                       "none" if extra is None else "%d line(s)" % len(extra)))
    if allow_arg:
        strings_line += "; allowlist: NON-DEFAULT (%s)" % os.path.basename(allow_path)
    pending = ["%s expires at %s" % (e["key"], e["expiry_text"])
               for e in entries_allow if e["provisional"]]
    if pending:
        strings_line += "; provisional: " + "; ".join(pending)

    if machine or nontext or unreadable or unallowed or expired:
        for path, off, hit in machine[:MAX_SHOWN]:
            print("FINDING machine-path  %s  byte %d: %s" % (path, off, hit))
        if len(machine) > MAX_SHOWN:
            print("FINDING machine-path  … and %d more" % (len(machine) - MAX_SHOWN))
        for path, size, nul in nontext[:MAX_SHOWN]:
            print("FINDING non-text      %s  %d bytes, first NUL at byte %d" % (path, size, nul))
        if len(nontext) > MAX_SHOWN:
            print("FINDING non-text      … and %d more" % (len(nontext) - MAX_SHOWN))
        for path in unreadable[:MAX_SHOWN]:
            print("FINDING unscannable   %s  gitlink (submodule): no blob to read" % path)
        for path, off, sample, count, where, sources, why in unallowed[:MAX_SHOWN]:
            print("FINDING personal-str  %s  %d hit(s) in %s, first at byte %d: %s "
                  "[from %s] — %s" % (path, count, where, off, sample, sources, why))
        if len(unallowed) > MAX_SHOWN:
            print("FINDING personal-str  … and %d more" % (len(unallowed) - MAX_SHOWN))
        for key, ver in expired:
            print("FINDING allowlist-exp %s  provisional entry `%s` expires at %s and this "
                  "publish is %s — remove it or re-adjudicate"
                  % (ALLOWLIST_NAME, key, ver, release))
        print("gate FAILED: %d machine path(s), %d non-text file(s) outside %s, %d unscannable, "
              "%d unallowlisted personal string(s), %d expired allowlist entr(ies) — scanned %d "
              "files (%d bytes) from %s. The publish halts."
              % (len(machine), len(nontext), MEDIA_ROOT, len(unreadable), len(unallowed),
                 len(expired), scanned, total, source))
        print(strings_line)
        return 1

    print("check: clean — scanned %d files (%d bytes) from %s; 0 machine paths, "
          "0 non-text files outside %s, 0 unallowlisted personal strings "
          "(control: %d/%d path probes, %d/%d class probes, %d/%d string probes, "
          "corpus control %d hits)"
          % (scanned, total, source, MEDIA_ROOT, path_ok, len(PATH_CONTROLS),
             class_ok, len(CLASS_CONTROLS), string_ok,
             len(DERIVATION_CONTROLS) + len(STRING_CONTROLS) + 2, control))
    print(strings_line)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Premise as err:
        print("PROBE FAILED: %s" % err)
        sys.exit(2)
