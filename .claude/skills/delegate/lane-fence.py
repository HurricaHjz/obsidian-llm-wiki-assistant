#!/usr/bin/env python3
"""lane-fence.py — the lane-side PreToolUse(Bash) fence for a headless thin lane.

`--restricted` confines the FILE tools (Read, Grep, Glob, Write, Edit) to the working
directory plus the `--add-dir` grants, and removes Bash unless `--tools` names it. It does
not fence the shell channel: a lane holding Bash can `cat` anything the user can read. This
hook is that missing fence. It is installed only in the lane home's own settings file, which
the wrapper passes with `--settings`, and must never be installed into the vault's settings —
it denies far more than a head session should ever have denied.

It keys on PATHS taken from the spawn environment, never on an agent key: an in-session
PreToolUse event carries `agent_type`, a headless one does not (probed 2026-09-04), so the
vault's own `deny-lane-shell-writes.sh` cannot serve a headless lane. The two variables are
written by the wrapper at spawn:

    LLM_WIKI_LANE_GRANTS   os.pathsep-joined absolute directories the lane may READ
    LLM_WIKI_LANE_WRITES   os.pathsep-joined absolute directories the lane may WRITE (may be empty)

Implicitly granted for reads and writes, whatever the variables say: /tmp (and its resolved
form) and /dev — not $TMPDIR. Lane scratch is sanctioned, and a benign /tmp
write was the only shell-write incident the vault has recorded (2026-08-27). Implicitly
granted for reads only: the lane home (the working directory) and executables that already
exist under the system bin directories, so a lane may invoke /usr/bin/grep without the fence
reading that path as data access.

What it denies, in this order, so the reason names the real cause:
  1. an invocation of `claude` (a lane may not spawn lanes, nor escape its own fence);
  2. a write channel — redirection, tee, `sed -i` / `perl -i`, or a mutating command word
     (mv, cp, rm, mkdir, rmdir, touch, ln, install, truncate, dd, chmod, chown) — whose
     target is outside the write set, or ANY such channel when the write set is empty
     (temporary roots and /dev excepted). A mutator is judged on ITS OWN segment and on its
     target arguments alone (`mutator_targets`): a compound line's other commands are not its
     targets, and for cp/mv/install/ln the sources are reads, tested by checks 3 and 4. That
     segment and its words are read QUOTE-AWARE (`shell_segments`, N10), so a separator inside a
     quoted argument starts no segment and a mutator word inside another command's quoted prose
     is prose; and an operand that names no file — a chmod mode, a chown or chgrp owner spec, a
     flag's value, a redirection target — is dropped by the SHAPE of the token, never by a list
     of known values, so `chmod 644 644` still reads its second operand as the file it writes;
  3. a relative path token that escapes the working directory (a `..` component);
  4. an absolute path token outside the read grants.

Before any of those four run, the HEREDOC BODIES are removed (`strip_heredocs`, design D33):
`<<` and `<<-`, quoted (`'EOF'`, `"EOF"`) and bare terminators, several heredocs opened on one
command line consumed in marker order, a line equal to the terminator (after `<<-` strips leading
tabs) ending that body there, and an unterminated body running to the end of the text — each as
the shell reads it, so what the fence calls data is what the shell calls data. The command line
carrying the `<<` STAYS: its own redirect targets and command words are checked as before, and a
`>` on that line still denies when its target is outside the write set. A `<<` inside quotes, and
anything after an unquoted `#`, opens no heredoc, so neither can hide a command from the checks.
Checks 3 and 4 — the read side — take their path tokens from `read_tokens`, which reads a quoted
string in this order (`quoted_kind`, D33 as amended by critic C2, N1): content holding a newline or
an OPERATOR character (`|`, `;`, `&`, `<`, `>`, `(`, `)`, a backtick, `^`, a backslash) is payload —
a pattern, a pipeline, a script; content starting with `/`, `~` or `$` is ONE path however many
spaces it holds, tested whole with any glob part cut (`"/x/*.md"` → `/x/`), so a spaced path is
checked rather than split into words that each pass; a `/`-led string in the slash-delimited
PATTERN shape carrying a metacharacter no path or glob has (`'/^## Open/'`, `'/x/{print $2}'`) or
in the address-range shape (`'/a/,/b/p'`) is payload, not a path (N9, `slash_pattern`); any other
whitespace-bearing content is prose and is payload; a bare word is a token like any other. A
`$`-led quoted string takes whatever is GLUED to it as part of the same token (`"$V"/wiki`), the
spelling `"$V/wiki"` and the bare `$V/wiki` both already having passed (N9c). Check 1 keeps the
whole (heredoc-stripped) text and its quoted content, so `python3 -c "... claude ..."` still
denies. Check 2 runs on the QUOTED-STRIPPED text (N9): a `>` inside quotes is not a redirection in
any shell, and scanning it as one denied three live command lines that wrote nothing. A quoted
single-path target survives the strip as a target (`> "/x/y"`), so on the WRITE side (N3, measured
by C2) a redirection, `tee` or mutator target whose text carries `$` or a backtick is still denied
outright: the fence cannot expand it, and a variable joined to the working directory passed every
other test for a head whose cwd sat inside its W.

`--head` (or LLM_WIKI_FENCE_ROLE=head) is the HEAD role, used by .claude/hooks/head-fence.py
(design D34), which imports this module and calls `check()` rather than spawning it (N8): check 1
is off (a head spawns lanes) and a CLEARED command is answered with SILENCE — exit 0, no stdout —
never an explicit `allow`, which the harness reads as auto-approval and which, armed in an attended
session, would bypass every shell prompt the owner still wants (the same rule handsoff-gate.py's
docstring states). `git` gets no rule of its own in either role: it is not a mutator token, so
nothing denies it, and its paths are checked like any other command's. A deny is the same JSON deny
in both roles, and the grants and writes come from the same two variables.

Premise cases, each made to behave rather than to guess:
  - stdin is not JSON, or carries no `tool_input.command` for a Bash call → DENY
    (`lane-fence: hook input unreadable` / `no command in hook input`). Fail-closed: a fence
    that cannot see the command cannot clear it.
  - LLM_WIKI_LANE_GRANTS absent, empty, or all-whitespace → DENY every Bash command
    (`lane-fence: no grants in environment`). This is the case that fires when the hook is
    reached from a session the wrapper did not start, which is exactly when it should.
  - `tool_name` is not Bash → no output, exit 0 (the harness decides). The settings matcher
    already scopes the hook to Bash; this is the belt.
  - an empty or whitespace-only command → allowed with no output: it writes nothing and
    reads nothing.
  - LLM_WIKI_LANE_WRITES absent or empty → a read-only lane: every write channel outside the
    temporary roots denies. Absent is not "unfenced", it is "no writes".
The process exits 0 in every case; a non-zero exit from a PreToolUse hook is a harness error,
not a denial, so it is never used to express one.

A cleared command gets an explicit `allow` decision rather than silence IN THE LANE ROLE. Silence
leaves the command to the ordinary permission flow, and a lane spawned with `--permission-prompts
none` has every would-be prompt turned into a denial, so silence would fence the shell to nothing.
The explicit allow is therefore what makes a granted `cat` run, and it makes this hook the
sole arbiter of the lane's shell — which is why its deny rules are conservative. In the head role
the opposite holds and a cleared command is silent (see `--head` above): the head's session keeps
its ordinary prompts, and an allow there would switch them off.

Every reason begins `lane-fence:` so the wrapper can count fence denials in the lane
transcript apart from the harness's own tool denials.

Residual false-deny class, narrowed by D33 and N9 and stated in what it still is (a retry tax, not
a hole). On the READ side a quoted string is payload or path by its content, so `grep 'see
/etc/hosts' f` is allowed, and a `/`-led PATTERN is payload wherever it carries a regex
metacharacter or is an address range; a pattern made only of letters and slashes (`'/foo/'`,
`'/foo/p'`) carries neither and is therefore still read as a path, so it false-denies outside the
grants — write it with an anchor, a class or a range (`'/^foo/'`, `'/a/,/b/'`) and it is payload.
A quoted glob (`"/x/*.md"`) is a path token, and `* ? [ ]` are for that reason not pattern
metacharacters: reading them as pattern markers would clear `cat "/etc/*"`. What that costs is
the other way round and is accepted: a two-segment path whose file name carries a brace, a bar or
a plus (`"/etc/{a}"`) is read as a pattern and passes unchecked, a file name no vault holds. On
the READ side a LITERAL quoted directory glued to a name (`cat "/x"/y`) is still split into two
tokens, so the tail (`/y`) is tested as a path of its own and false-denies; N9c glues only a
`$`-led string, and the write side reads the same word whole (N10, measured 2026-09-06).
Fail-closed residues that stay: a mutator whose
target is a variable (`chmod +x "$f"`, `cp a "$D/b"`) is denied, because the fence sees no literal
path to test — a lane writes the literal path; an interpreter's program argument (`sh -c '…'`,
`python3 -c '…'`) keeps its content for the read checks, so a path inside it is tested and an
outside one denies as before D33, while a program passed with no `-c`/`-e` flag (an awk or sed
script) is payload the fence cannot decide; `sh -c '...'` still hides its payload from the
command-word tests; a relative symlink pointing out of the grants is not resolved. Each of these
fails towards denial; a lane that hits one reports the gap and the head re-spawns it with the grant
(the re-spawn rule), which is the designed recovery. The one direction that is NOT fail-closed is
named, and it is a READ: a quoted target whose variable the fence cannot expand — `cat
"$HOME/Library/Application Support/x"`, `cat "$D/secret"` — is one path token that is not absolute,
so checks 3 and 4 have nothing to test and it passes. Unquoted it always passed too (`tokens_of`
splits on `$`), and the WRITE side of the same shape denies outright (N3), so what remains is a
lane reading through a variable it set itself; the grants, not this fence, are what bound that.
"""

import json
import os
import re
import sys

FENCE = "lane-fence:"

# Command words that mutate the filesystem. Keyed on the basename of a command word, so
# /bin/rm and rm are the same case and a token like /x/rm-notes is not.
MUTATORS = {"mv", "cp", "rm", "rmdir", "mkdir", "touch", "ln", "install",
            "truncate", "dd", "chmod", "chown", "chgrp", "shred", "unlink"}
# Prefix words that stand in front of the real command word.
PREFIXES = {"env", "nohup", "time", "sudo", "doas", "command", "builtin", "exec",
            "xargs", "nice", "ionice", "stdbuf", "then", "do", "else", "elif", "if", "while"}
SYSTEM_BIN = ("/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/",
              "/usr/local/bin/", "/opt/homebrew/bin/", "/opt/local/bin/")


def decide(action, reason):
    """Print one PreToolUse decision and exit 0. `action` is 'allow' or 'deny'."""
    sys.stdout.write(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": action,
        "permissionDecisionReason": reason}}) + "\n")
    sys.exit(0)


def deny(reason):
    decide("deny", "%s %s" % (FENCE, reason))


def norm(path):
    """Absolute, symlink-resolved, trailing-slash-free — both sides of every comparison."""
    return os.path.realpath(os.path.abspath(os.path.expanduser(path)))


def roots_from(varname):
    raw = os.environ.get(varname) or ""
    out = []
    for part in raw.split(os.pathsep):
        part = part.strip()
        if part:
            out.append(norm(part))
    return out


def within(path, roots):
    path = norm(path)
    for root in roots:
        if path == root or path.startswith(root.rstrip(os.sep) + os.sep):
            return True
    return False


def temp_roots():
    """The sanctioned scratch roots: /dev, /tmp and whatever /tmp resolves to (on this
    platform /private/tmp). $TMPDIR is deliberately NOT among them: on macOS it points at a
    per-user directory under /var/folders that a lane has no standing reason to touch, and
    sanctioning it would silently widen the fence far past the two paths the design names."""
    out = ["/dev", os.path.abspath("/tmp"), norm("/tmp")]
    return sorted(set(r for r in out if r))


def strip_quoted(text):
    """Remove quoted string CONTENT (the proven form from the vault's shell hook, 2026-08-28:
    the unstripped version false-denied ~10% of read-only commands on a quoted '>')."""
    return re.sub(r"'[^']*'", " ", re.sub(r'"[^"]*"', " ", text))


# A redirect or `tee` TARGET position: what stands immediately before a quoted string, with every
# earlier quoted content already removed, ends in a redirection operator or a `tee` word.
TARGET_POSITION = re.compile(r"(?:>>?|(?:^|[\s;|&(])tee(?:\s+-a)?)\s*$")


def strip_quoted_for_writes(text):
    """Quoted CONTENT removed BEFORE the write-channel scan (N9), with one exception: a quoted
    string standing in a redirect or `tee` target position whose content `quoted_kind` calls a
    path is kept, unquoted, so `> "/x/y"` is still a target the scan tests and N3 still sees a
    `$` or a backtick in it.

    The order this replaces ran the scan on the unstripped text and stripped afterwards, which
    cost three false-deny classes measured live (2026-09-05, 2026-09-06), each of which stopped a
    whole command line: a `>` inside quoted PROSE matched the redirect pattern, so a backtick or a
    `$` in the following word tripped N3 (a `--status` prose holding a placeholder in angle
    brackets and then a backticked word); and blanking a SANCTIONED quoted target consumed its
    opening quote, leaving the rest of the line with
    unbalanced quotes, a quoted `<placeholder>` half-stripped and a bare `>` for the redirect test
    to deny. Stripping first removes both, because a quoted `>` is not a redirection in any shell.
    Every real redirect stays visible: it is written outside quotes, and a quoted target survives
    by the exception above."""
    out, last = [], 0
    for match in re.finditer(r"'[^']*'|\"[^\"]*\"", text):
        out.append(text[last:match.start()])
        content = match.group(0)[1:-1]
        # A target carrying `$` or a backtick is kept whatever `quoted_kind` calls it, so N3 keeps
        # its own reason for `tee "`sub`"` rather than falling through to the bare-`tee` deny.
        keep = quoted_kind(content) == "path" or "$" in content or "`" in content
        if content and keep and TARGET_POSITION.search("".join(out)):
            out.append(" %s " % content)
        else:
            out.append(" ")
        last = match.end()
    out.append(text[last:])
    return "".join(out)


def unquote(text):
    """Remove quote CHARACTERS but keep their content, so a quoted path is still a path."""
    return text.replace('"', " ").replace("'", " ")


# The OPERATOR characters that make a quoted string payload whatever else it holds (D33 as
# amended by critic C2, N1). `^` and the backslash are here so a quoted regex (`'/^x/'`, `'\d+/x'`)
# is payload; `*` and `?` are NOT, so a quoted glob is a path with its glob part cut; `$` is NOT,
# so a quoted `"$HOME/x"` is one path token rather than a hole.
PAYLOAD_OPERATORS = "|;&<>()`^\\\n"
# A quoted string whose content starts with one of these is ONE path however many spaces it holds:
# `"/opt/x/Application Support/y"` is a single argument to the command, not prose.
PATH_STARTS = ("/", "~", "$")
GLOB_CHARS = "*?["
# N9: a slash-led quoted string that is a slash-delimited PATTERN, not a path — a sed address, an
# awk program, a grep expression. Two tests, both required, because `/etc/passwd` fits the shape:
#   SHAPE  one `/…/` part, or a comma-joined pair (`/a/,/b/`), followed by pattern flags and
#          actions only — never a second path separator, which is why a real multi-segment path
#          (`/x/y/z`) cannot match at all.
#   METACHARACTER  something no path and no glob carries. Between the delimiters that is
#          `^ $ { } | + ( ) \`; in the TRAILING part `$` does not count, so `"/etc/$f"` stays the
#          path token it is today and only an awk action (`{print $2}`) is read as a pattern.
# The glob characters `* ? [ ]` are deliberately absent from both sets: a quoted glob is a PATH
# whose glob part is cut (D33), and reading `*` as a pattern marker would clear `cat "/etc/*"`.
PATTERN_PART = r"(?:\\.|[^/\\])*"
PATTERN_TAIL = r"[A-Za-z0-9,;:{}!+=$._ \t-]*"
PATTERN_SHAPE = re.compile(r"/(%s)/(?:\s*,\s*/(%s)/)?(%s)"
                           % (PATTERN_PART, PATTERN_PART, PATTERN_TAIL))
PATTERN_META = "^${}|+()\\"
TAIL_META = "{}|+()"
# Interpreters whose program text arrives as a quoted argument behind -c / -e / -E. Their payload
# is a command line, not prose, so the read checks keep its content: `sh -c "cat /etc/shadow"`
# must deny exactly as the bare `cat` does. Without this the payload rule would open a read hole
# that the fence did not have before D33.
INTERPRETERS = {"sh", "bash", "zsh", "ksh", "dash", "python", "python2", "python3",
                "perl", "ruby", "node", "php", "osascript", "env"}
INTERPRETER_FLAG = re.compile(r"(^|\s)-[A-Za-z]*[ceE]([\s'\"]|$)")
# A quoted string plus whatever is GLUED to its right within the same shell word (N9c). The tail
# stops at whitespace, at a quote and at every shell operator, so it never swallows a command.
QUOTED_WORD = re.compile(r"('[^']*'|\"[^\"]*\")([^\s'\";|&<>()`]*)")


def heredoc_markers(line):
    """Every heredoc terminator opened on one command line, in the order the shell reads their
    bodies: `<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`. A `<<` inside quotes opens nothing, a
    here-STRING (`<<<`) is not a heredoc, a backslash-escaped `<` is literal, and an unquoted `#`
    starts a comment — the shell opens no heredoc from a comment, so neither does this, or a
    `# <<EOF` line would let the text beneath it pass unchecked as a body."""
    markers = []
    index, end, quote = 0, len(line), None
    while index < end:
        ch = line[index]
        if quote:
            if ch == quote:
                quote = None
            index += 1
            continue
        if ch in "'\"":
            quote = ch
            index += 1
            continue
        if ch == "\\":
            index += 2
            continue
        if ch == "#" and (index == 0 or line[index - 1] in " \t;|&("):
            break
        if not line.startswith("<<", index) or line.startswith("<<<", index):
            index += 1 if not line.startswith("<<<", index) else 3
            continue
        cursor = index + 2
        dash = cursor < end and line[cursor] == "-"
        cursor += 1 if dash else 0
        while cursor < end and line[cursor] in " \t":
            cursor += 1
        if cursor < end and line[cursor] in "'\"":
            closing = line.find(line[cursor], cursor + 1)
            word = line[cursor + 1:] if closing < 0 else line[cursor + 1:closing]
            cursor = end if closing < 0 else closing + 1
        else:
            chars = []
            while cursor < end and line[cursor] not in " \t;|&<>()":
                if line[cursor] == "\\" and cursor + 1 < end:
                    chars.append(line[cursor + 1])
                    cursor += 2
                    continue
                chars.append(line[cursor])
                cursor += 1
            word = "".join(chars)
        if word:
            markers.append((word, dash))
        index = cursor
    return markers


def strip_heredocs(text):
    """Remove every heredoc BODY, keeping the command lines that open them (design D33). The
    body ends at a line equal to the terminator (leading tabs stripped first for `<<-`), and an
    unterminated body runs to the end of the text — both as the shell reads them, so a body the
    shell never executes is never scanned here, and a line the shell would execute always is."""
    lines = text.split("\n")
    out = []
    index = 0
    while index < len(lines):
        line = lines[index]
        out.append(line)
        index += 1
        for word, dash in heredoc_markers(line):
            while index < len(lines):
                body = lines[index]
                index += 1
                if (body.lstrip("\t") if dash else body) == word:
                    break
    return "\n".join(out)


def slash_pattern(content):
    """True when a `/`-led quoted string is a sed/awk/grep PATTERN rather than a path (N9): the
    slash-delimited shape AND a metacharacter no path or glob carries, or the address-range shape
    `/a/,/b/`, which is a sed range in every script and no one's file name. The whole of the
    content must be the pattern: a trailing path separator, or anything but flags and an action
    after the closing delimiter, and it is a path again."""
    match = PATTERN_SHAPE.fullmatch(content)
    if not match:
        return False
    if match.group(2) is not None:
        return True                       # an address range
    return (any(ch in PATTERN_META for ch in match.group(1))
            or any(ch in TAIL_META for ch in match.group(3)))


def quoted_kind(content):
    """What a quoted string is for the READ checks (D33 as amended, N1 and N9), in this order:
      payload  — its content holds a newline or an operator character: a pattern, a script, a
                 pipeline. It names nothing the command reads.
      payload  — it is `/`-led and `slash_pattern` calls it a pattern: `'/^## Open/'`,
                 `'/x/{print $2}'`, `'/a/,/b/p'`. Denying these stopped whole command lines for
                 no read (2026-09-05, twice on the head).
      path     — its content starts with `/`, `~` or `$`: ONE path however many spaces it holds.
      payload  — anything else that holds whitespace: prose, a message, a search string.
      path     — a bare word: `"notes.md"`, checked like any unquoted token."""
    if any(ch in PAYLOAD_OPERATORS for ch in content):
        return "payload"
    if content.startswith("/") and slash_pattern(content):
        return "payload"
    if content.startswith(PATH_STARTS):
        return "path"
    return "payload" if any(ch.isspace() for ch in content) else "path"


def cut_glob(path):
    """A glob is tested by the deepest directory it cannot escape: `/x/*.md` → `/x/`. Cutting at
    the last separator before the first glob character keeps the test honest — the glob may match
    anything under that directory, and nothing above it."""
    hits = [path.find(ch) for ch in GLOB_CHARS if path.find(ch) >= 0]
    if not hits:
        return path
    slash = path.rfind("/", 0, min(hits))
    return path[:slash + 1] if slash >= 0 else path


# N11 (register, 2026-09-06): the PATTERN position of a pattern-taking command. A quoted string
# standing there is what the command searches for, never a file it reads, whatever its content
# looks like: `grep -v "/log.md:"` was denied live as a read of `/log.md:`, and `slash_pattern`
# cannot help, since a bare `/x` has no closing delimiter. Keyed on the token's position in the
# command's own grammar — the first operand after the flags, unless a flag already supplied the
# pattern or the program (`-e`, `-f` and their long forms), in which case every operand is a file.
# Only a QUOTED token is exempted: an unquoted pattern keeps today's reading, so the change is
# confined to the false-deny class measured.
PATTERN_COMMANDS = {"grep": "grep", "egrep": "grep", "fgrep": "grep", "zgrep": "grep",
                    "awk": "awk", "gawk": "awk", "mawk": "awk", "nawk": "awk", "sed": "sed"}
# Per family: the short letters that take a value (the glued tail or the next token is then no
# operand), the letters that SUPPLY the pattern or program (no positional pattern remains), and
# the long options of each kind. `-E` is a value flag for gawk (--exec) and a plain switch for
# grep and sed, which is why the tables are per family rather than shared.
PATTERN_FLAGS = {
    "grep": {"value": set("efmABCdD"), "supply": set("ef"),
             "value_long": {"--regexp", "--file", "--max-count", "--after-context",
                            "--before-context", "--context", "--directories", "--devices",
                            "--include", "--exclude", "--exclude-dir", "--exclude-from",
                            "--label", "--binary-files", "--group-separator"},
             "supply_long": {"--regexp", "--file"}},
    "awk":  {"value": set("fFvWeiIlE"), "supply": set("feE"),
             "value_long": {"--file", "--field-separator", "--assign", "--source", "--include",
                            "--load", "--exec"},
             "supply_long": {"--file", "--source", "--exec"}},
    "sed":  {"value": set("efl"), "supply": set("ef"),
             "value_long": {"--expression", "--file", "--line-length"},
             "supply_long": {"--expression", "--file"}},
}
# An interpreter's program flag as ONE shell word: `-c`, `-Bc`, `-e`, or the flag glued to its
# quoted program (`-c"..."`). The same shape INTERPRETER_FLAG reads out of running text.
INTERPRETER_TOKEN = re.compile(r"^-[A-Za-z]*[ceE](['\"]|$)")


def segment_command(words):
    """(index, basename) of a segment's command word, past leading assignments and prefix words;
    (None, None) for a segment made of those alone."""
    index = 0
    while index < len(words):
        word = unquote_token(words[index]).strip()
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", word) or word in PREFIXES:
            index += 1
            continue
        return index, os.path.basename(word.rstrip(os.sep))
    return None, None


def interpreter_segment(words):
    """True when THIS segment invokes an interpreter with a program flag (`sh -c`, `python3 -c`,
    `perl -e`): its quoted argument is a command line, so the read checks keep its content and
    the pre-D33 behaviour — a denial — stands for it. Decided per segment (N11): the whole-line
    form read `grep -c` in one segment against `python3` in another as an interpreter payload,
    tokenised every quoted string of the line and denied an awk pattern as a path (register,
    2026-09-06, case G). A program passed WITHOUT such a flag (an awk or sed script) is payload
    like any other quoted string: the fence cannot decide it, and that residue is named in the
    docstring."""
    index, base = segment_command(words)
    if base not in INTERPRETERS:
        return False
    return any(INTERPRETER_TOKEN.match(word) for word in words[index + 1:])


def carries_interpreter_payload(text):
    """True when any segment of the text is an interpreter segment (kept for callers of the
    whole-text form; the read checks decide per segment)."""
    return any(interpreter_segment(words) for words in shell_segments(text))


def pattern_operand(words):
    """The index of the quoted token standing in the PATTERN position of a pattern-taking command
    (N11), else None: the first operand after the flags, read as the command reads them (a
    value-taking letter consumes its glued tail or the next token; `--` ends the flags; a
    redirection and its target belong to check 2). None as soon as a flag supplied the pattern or
    the program, since every operand is then a file the command reads. Only a quoted token
    qualifies: `grep -v "/log.md:"` is the case; `grep -v /log.md:` keeps today's reading."""
    index, base = segment_command(words)
    family = PATTERN_COMMANDS.get(base)
    if family is None:
        return None
    flags = PATTERN_FLAGS[family]
    i, end_of_flags = index + 1, False
    while i < len(words):
        raw = words[i]
        i += 1
        if raw[:1] in "<>":
            if "&" not in raw and i < len(words):
                i += 1                        # the redirection's target
            continue
        word = unquote_token(raw).strip()
        if not word:
            continue
        if not end_of_flags and word == "--":
            end_of_flags = True
            continue
        if not end_of_flags and word.startswith("-") and word != "-":
            if word.startswith("--"):
                name, sep, _ = word.partition("=")
                if name in flags["supply_long"]:
                    return None
                if not sep and name in flags["value_long"]:
                    i += 1
                continue
            for position in range(1, len(word)):
                letter = word[position]
                if letter in flags["supply"]:
                    return None
                if letter in flags["value"]:
                    if position + 1 >= len(word):
                        i += 1                # the value is the next token
                    break
            continue
        return i - 1 if raw[:1] in "'\"" else None
    return None


def quoted_tokens(word):
    """The read-side reading of ONE shell word (D33, N1, N9, N9c): each quoted span that
    `quoted_kind` calls a path, whole and with its glob part cut; a `$`-led span with the text
    GLUED to it dropped as one token the fence cannot expand — `"$V"/wiki` is the same argument
    as `"$V/wiki"` and as the bare `$V/wiki`, both of which pass, and emitting the tail alone
    made `/wiki` an absolute token of its own and denied a lane's read-only grep (N9c); and
    `tokens_of` over what is left when the quoted spans are removed."""
    paths = []

    def replace(match):
        content, glued = match.group(1)[1:-1], match.group(2)
        kind = quoted_kind(content)
        if kind == "path" and content.startswith("$"):
            return " "
        if kind == "path":
            paths.append(cut_glob(content))
        return " %s " % glued if glued else " "
    rest = QUOTED_WORD.sub(replace, word)
    return paths + tokens_of(rest)


def read_tokens(text):
    """Every path token the read checks (3 and 4) test, read segment by segment from the same
    quote-aware tokens the mutator scan uses (`shell_segments`, N11), so a quote is paired within
    its own word and never across another segment's prose. An interpreter segment's program
    argument (`sh -c '…'`) is a command line, not quoted payload, so that segment's content is
    tokenised as though it were one; in every other segment the quoted token in a pattern-taking
    command's pattern position is payload, and each remaining word is read by `quoted_tokens`."""
    tokens = []
    for words in shell_segments(text):
        if interpreter_segment(words):
            tokens += tokens_of(" ".join(words))
            continue
        skip = pattern_operand(words)
        for index, word in enumerate(words):
            if index != skip:
                tokens += quoted_tokens(word)
    return tokens


def tokens_of(command):
    """Path-ish tokens: quote characters dropped, shell metacharacters and `=` turned into
    separators, so `--file=/etc/x` and `"/etc/x"` both yield /etc/x."""
    text = re.sub(r"[|;&<>()`$*?\[\]{}=,]", " ", unquote(command))
    return [t for t in text.split() if t]


def command_words(command):
    """The first real word of each shell segment, plus every token whose basename could name
    a binary — enough to catch `xargs claude` and `find . -exec rm {} ;`."""
    words = []
    for segment in re.split(r"[;&|\n()]+", strip_quoted(command)):
        parts = segment.split()
        index = 0
        while index < len(parts):
            token = parts[index]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token) or token in PREFIXES:
                index += 1
                continue
            break
        if index < len(parts):
            words.append(parts[index])
    return words


def head_role(argv=None):
    """The head role: `--head` on the command line, or LLM_WIKI_FENCE_ROLE=head for a caller
    that cannot pass arguments. Anything else is the lane role."""
    argv = sys.argv[1:] if argv is None else argv
    return "--head" in argv or (os.environ.get("LLM_WIKI_FENCE_ROLE") or "").strip() == "head"


def check(event, grants, writes, head=False):
    """The whole decision as a pair — ("deny", reason), ("allow", reason) or ("silent", "") —
    computed, never printed and never exited, so head-fence.py can IMPORT this module and call
    this one function instead of paying a second interpreter start (D34 as amended, N8).
    `grants` and `writes` are lists of real paths; `head` selects the head role."""
    def denial(reason):
        return "deny", "%s %s" % (FENCE, reason)

    if (event.get("tool_name") or "Bash") != "Bash":
        return "silent", ""               # not our channel; the harness decides
    if not grants:
        return denial("no grants in environment (LLM_WIKI_LANE_GRANTS unset or empty) "
                      "— fail-closed")

    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict) or "command" not in tool_input:
        return denial("no command in hook input — fail-closed")
    command = tool_input.get("command") or ""
    if not command.strip():
        return "silent", ""               # writes nothing, reads nothing

    temps = temp_roots()
    read_roots = grants + writes + temps
    write_roots = writes + temps

    # Heredoc bodies are data, whoever wrote them: removed once, before every check (D33). The
    # command lines that opened them stay, so their own redirects and command words are checked.
    body = strip_heredocs(command)

    # 1 — a lane never spawns a lane. Off in the head role: a head spawns lanes for a living.
    if not head:
        for token in tokens_of(body):
            if os.path.basename(token.rstrip(os.sep)) == "claude":
                return denial("a lane may not invoke `claude` (no nested spawns)")

    # 2 — write channels. Strip fd duplications, then quoted content (keeping a quoted single-path
    #     target), then redirect/tee targets already inside the write set; deny on what survives.
    stripped = re.sub(r"[0-9]*>&[0-9-]+", " ", body)
    # N9: the quoted content goes FIRST, before any target is looked for, keeping a quoted
    # single-path target as a target. A `>` inside quotes is not a redirection in any shell, and
    # scanning it as one denied three live command lines that wrote nothing.
    stripped = strip_quoted_for_writes(stripped)
    # Sanctioned write channels are removed by TESTING each target with the same path
    # comparison the read side uses, never by matching the root as a literal string: on this
    # platform a temporary root reaches the command unresolved (/var/folders/...) while the
    # environment carries it resolved (/private/var/folders/...), and a literal match would
    # deny a lane writing inside its own whitelist.
    for pattern in (r"(>>?)\s*[\"']?([^\s\"';|&<>]+)",
                    r"(tee)(?:\s+-a)?\s+[\"']?([^\s\"';|&<>]+)"):
        # N3, measured by critic C2: a target carrying a variable or a substitution is denied
        # outright. Joined to the working directory it can land anywhere — for a head whose cwd
        # is the vault root and whose W holds it, `echo x > "$HOME/.zshrc"` passed every test
        # below. The fence cannot expand it, so it refuses it: write the literal path.
        for match in re.finditer(pattern, stripped):
            if "$" in match.group(2) or "`" in match.group(2):
                return denial("the %s target `%s` carries a variable or a substitution, which "
                              "this fence cannot resolve — write the literal path"
                              % ("redirection" if match.group(1) != "tee" else "`tee`",
                                 match.group(2)))
        while True:
            for match in re.finditer(pattern, stripped):
                target = match.group(2)
                if not os.path.isabs(os.path.expanduser(target)):
                    target = os.path.join(os.getcwd(), target)
                if within(target, write_roots):
                    stripped = (stripped[:match.start()] + " " * (match.end() - match.start())
                                + stripped[match.end():])
                    break
            else:
                break
    scope = "outside the write whitelist" if writes else "on a lane with no write grant"
    if ">" in stripped:
        return denial("shell redirection %s is denied (writes go to the granted directories, or "
                      "the change comes back as a proposed diff)" % scope)
    if re.search(r"(^|[^A-Za-z0-9_])tee([^A-Za-z0-9_]|$)", stripped):
        return denial("`tee` %s is denied" % scope)
    if re.search(r"(^|[^A-Za-z0-9_])(sed|perl)[^|;&]{0,60}\s-[A-Za-z]*i", stripped):
        return denial("an in-place editor (sed -i / perl -i) %s is denied" % scope)
    for mutator, raw in mutator_targets(body):
        # N3 on the TARGET alone: a variable or a substitution the fence cannot resolve. A source
        # carrying one is a read, and the read side owns it.
        if "$" in raw or "`" in raw:
            return denial("`%s` takes the target `%s`, which carries a variable or a substitution "
                          "this fence cannot resolve — write the literal path (N3)" % (mutator, raw))
        target = cut_glob(unquote(raw).strip())
        if not target:
            continue
        if not within(target if os.path.isabs(os.path.expanduser(target))
                      else os.path.join(os.getcwd(), target), write_roots):
            return denial("`%s` targets `%s`, which is %s" % (mutator, target, scope))

    # 3 and 4 read PATHS: `read_tokens` decides what is a path and what is payload (D33, N1).
    tokens = read_tokens(body)

    # 3 — a relative token may not climb out of the working directory.
    for token in tokens:
        if os.path.isabs(os.path.expanduser(token)):
            continue
        if ".." in token.split(os.sep):
            return denial("relative path `%s` escapes the working directory" % token)

    # 4 — an absolute token must sit inside the grants. `git` needs no rule of its own in either
    # role: it is not a mutator token, and its own paths are checked like any other (N8).
    cwd = norm(os.getcwd())
    for token in tokens:
        expanded = os.path.expanduser(token)
        if not os.path.isabs(expanded):
            continue
        if any(expanded.startswith(prefix) for prefix in SYSTEM_BIN) and os.path.exists(expanded):
            continue                      # invoking a system binary is not data access
        if within(expanded, read_roots + [cwd]):
            continue
        return denial("`%s` is outside the granted directories — report the gap "
                      "(`needs: <path> because <reason>`) instead of working around it" % token)

    # Cleared. A lane gets the explicit allow its permission flow needs; a head gets silence, an
    # explicit allow there being read by the harness as auto-approval (C1 F1).
    return ("silent", "") if head else ("allow", "%s within grants" % FENCE)


# Commands whose LAST non-flag operand is the thing they create; every earlier one is a source,
# which is a READ and is tested by checks 3 and 4, never by the write rule.
SOURCE_AND_TARGET = {"cp", "mv", "install", "ln"}
# The characters that end a segment OUTSIDE quotes, the same set `command_words` splits on.
SEGMENT_SEPARATORS = ";&|\n()"
# Flags that take a VALUE, per command, because the same letter reads differently: `-t` is a
# target DIRECTORY for cp/mv/ln/install and a TIMESTAMP for touch, `-s` a size for truncate and
# "symbolic" for ln. A value is not an operand — `install -m 644 a b` writes b, never a file
# called 644 — and reading it as one denied `chmod 644 <file inside W>` live (2026-09-06, N10).
VALUE_FLAGS = {
    "cp":       {"-t", "--target-directory", "-S", "--suffix"},
    "mv":       {"-t", "--target-directory", "-S", "--suffix"},
    "ln":       {"-t", "--target-directory", "-S", "--suffix"},
    "install":  {"-t", "--target-directory", "-m", "--mode", "-o", "--owner", "-g", "--group",
                 "-S", "--suffix", "--strip-program"},
    "mkdir":    {"-m", "--mode"},
    "touch":    {"-r", "--reference", "-t", "-d", "--date", "--time"},
    "truncate": {"-s", "--size", "-r", "--reference"},
    "chmod":    {"--reference"},
    "chown":    {"--reference", "--from"},
    "chgrp":    {"--reference"},
    "shred":    {"-n", "--iterations", "-s", "--size", "--random-source"},
}
# The one value that is itself a WRITE: the directory cp/mv/ln/install copy INTO.
TARGET_DIR_FLAGS = {"-t", "--target-directory"}
# A chmod MODE: octal (one to four digits — three permission triples plus the optional setuid
# digit) or symbolic, comma-joined. Keyed on the token's shape, never on a list of known modes,
# so `chmod 644 644` still reads its SECOND operand as the file it writes.
MODE_SHAPE = re.compile(r"^[0-7]{1,4}$"
                        r"|^[ugoa]*[-+=][rwxXstugo]*(,[ugoa]*[-+=][rwxXstugo]*)*$")


def shell_segments(text):
    """The command's segments, each a list of RAW tokens (quotes still on), split the way the
    shell splits — on `; & | newline ( )` OUTSIDE quotes only, so a separator inside quoted prose
    starts no segment. A quoted span glues to whatever touches it, as the shell joins them into
    one word (`"/x"/y` is one operand); a backslash escapes the next character, so a continued
    line stays one segment; an unterminated quote runs to the end of the text, which keeps the
    write side fail-closed on it. A redirection operator becomes its own token (`>`, `>>`, `2>`,
    `2>&1`) so the operand grammar can drop it together with its target: a redirect target belongs
    to check 2, not to a mutator's operands.

    Heredoc bodies are NOT handled here: `check` strips them once before any check runs, and a
    second strip would let a stripped body's opening line swallow the commands beneath it."""
    segments, tokens, current = [], [], []
    index, end = 0, len(text)

    def close_token():
        if current:
            tokens.append("".join(current))
            del current[:]

    def close_segment():
        close_token()
        if tokens:
            segments.append(list(tokens))
        del tokens[:]

    while index < end:
        char = text[index]
        if char in "'\"":
            closing = text.find(char, index + 1)
            if closing < 0:                   # unterminated: the rest of the text is one word
                current.append(text[index:])
                index = end
                continue
            current.append(text[index:closing + 1])
            index = closing + 1
            continue
        if char == "\\" and index + 1 < end:
            current.append(text[index:index + 2])
            index += 2
            continue
        if char in SEGMENT_SEPARATORS:
            close_segment()
            index += 1
            continue
        if char in "<>":
            if current and "".join(current).isdigit():
                del current[:]                # a file-descriptor number belongs to the operator
            close_token()
            start = index
            while index < end and text[index] in "<>&0123456789-":
                index += 1
            tokens.append(text[start:index])
            continue
        if char.isspace():
            close_token()
            index += 1
            continue
        current.append(char)
        index += 1
    close_segment()
    return segments


def unquote_token(token):
    """One shell WORD with its quoting resolved: quote characters removed rather than blanked
    (`"/x"/y` → `/x/y`, the single path the shell passes) and a backslash escape reduced to what
    it escapes. `unquote` cannot serve here — it blanks a quote into a SPACE, which splits exactly
    the glued word this has to keep whole. A backslash inside single quotes is literal to the
    shell and is unescaped here anyway: the difference is a file name carrying a backslash."""
    return re.sub(r"\\(.)", r"\1", token.replace('"', "").replace("'", ""), flags=re.S)


def flag_reading(command, word):
    """How a dash-led word is read by `command`: (glued value or None, consumes the next token,
    the value is a write TARGET). A short cluster is read as getopt reads it — in `-rft/dir` the
    tail of the first value-taking letter is that letter's argument — and a long option takes its
    value glued behind `=` or from the next token.

    Leftward glue: the shell hands the command ONE word, so a write can hide in the glued
    spelling of a flag whose value is a directory (`cp -t"/dir" src`, `install -t/dir src`), and
    that is the case this returns as a target. Every other glued value is a mode, a size, an
    owner, a suffix or a timestamp, which names no file the command creates, and a glued path
    behind a flag that takes NO value (`rm -rf"/dir"`) is not a write at all: the command reads
    the whole word as options and errors out."""
    takes = VALUE_FLAGS.get(command, set())
    if word.startswith("--"):
        name, sep, glued = word.partition("=")
        if name not in takes:
            return None, False, False
        target = command in SOURCE_AND_TARGET and name in TARGET_DIR_FLAGS
        return (glued, False, target) if sep else (None, True, target)
    for position in range(1, len(word)):
        flag = "-" + word[position]
        if flag in takes:
            target = command in SOURCE_AND_TARGET and flag in TARGET_DIR_FLAGS
            tail = word[position + 1:]
            return (tail, False, target) if tail else (None, True, target)
    return None, False, False


def mutator_operands(command, tokens):
    """(operands, flag-named targets, flags seen) for one mutator's token list — what the command
    reads as its arguments once redirections, flags and their values are taken out. Operands are
    unquoted; an operand that is genuinely empty (`""`) is kept, so a command whose target is an
    empty string keeps today's verdict, while the residue of a backslash-escaped newline is not."""
    operands, flag_targets, flags = [], [], set()
    index, end_of_flags = 0, False
    while index < len(tokens):
        token = tokens[index]
        index += 1
        if token[:1] in "<>":
            # A redirection and its target: check 2 owns both. An operator carrying `&` is a file
            # descriptor duplication (`2>&1`) and takes no following word.
            if "&" not in token and index < len(tokens):
                index += 1
            continue
        word = unquote_token(token).strip()
        if not word:
            if token.strip("'\"") == "":      # a real empty operand, not escape residue
                operands.append("")
            continue
        if not end_of_flags and word == "--":
            end_of_flags = True
            continue
        if not end_of_flags and word.startswith("-") and word != "-":
            glued, consumes, is_target = flag_reading(command, word)
            flags.update(["-" + ch for ch in word[1:]] if not word.startswith("--")
                         else [word.partition("=")[0]])
            if glued and is_target:
                flag_targets.append(glued)
            if consumes and index < len(tokens):
                value = unquote_token(tokens[index]).strip()
                index += 1
                if is_target:
                    flag_targets.append(value)
            continue
        if not end_of_flags and word.startswith("+"):
            continue                          # a `+`-led symbolic mode (`chmod +x`) is no path
        operands.append(word)
    return operands, flag_targets, flags


def mutator_targets(text):
    """(mutator word, target) for every write a mutator command actually makes, scoped to its OWN
    segment and read from the segment's TOKENS. The whole-command form this replaces read every
    token of a compound line as a target (`cd /vault && mkdir -p /tmp/a` denied with "`mkdir`
    targets `cd`", live 2026-09-05); the text-scanning form that replaced THAT still read the raw
    segment text, and three more live command lines that ran nothing were denied by it on
    2026-09-06 (N10): quoted prose naming `cp` and a path, where the `;` inside the quotes started
    a segment; a heredoc body inside a quoted command substitution, whose `install` line was read
    as a command; and `chmod 644 <file inside W>`, whose MODE was read as a relative path.

    So: segments and words come from `shell_segments`, which is quote-aware, and a mutator word
    inside another command's quoted argument is prose, never a command. A quoted whole token that
    IS an operand stays a target (`cp a "/outside/b"` still denies). A leading `VAR=value`
    assignment and the prefix words (`sudo`, `env`, `xargs`) are stepped over. Operands that name
    no file are dropped by the shape of the token, never by a magic value: a chmod MODE, a
    chown/chgrp owner or group spec, a flag's value, a redirection target. For cp/mv/ln/install
    only the last operand is written, unless `-t` named the target directory (then every operand
    is a source) or `install -d` created all of them; for `dd` only the `of=` operand is a write,
    `if=` being a read that checks 3 and 4 own.

    The target comes back with its quotes already resolved, so the caller's `unquote` is a no-op
    on it while its `$` and backtick test (N3) still sees what the shell would expand."""
    out = []
    for words in shell_segments(text):
        index = 0
        while index < len(words):
            word = unquote_token(words[index]).strip()
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", word) or word in PREFIXES:
                index += 1
                continue
            break
        if index >= len(words):
            continue
        mutator = unquote_token(words[index]).strip()
        base = os.path.basename(mutator.rstrip(os.sep))
        if base not in MUTATORS:
            continue
        operands, targets, flags = mutator_operands(base, words[index + 1:])
        if base == "dd":
            # dd's operands are `key=value`: `of=` names the file it writes, `if=` a file it
            # reads, and `bs=`, `count=`, `seek=` name no file at all.
            operands = [operand.partition("=")[2] for operand in operands
                        if operand.partition("=")[0] == "of"]
        else:
            if base == "chmod" and operands and MODE_SHAPE.match(operands[0]):
                operands = operands[1:]       # the first operand is a mode, not a path
            if base in ("chown", "chgrp") and operands and os.sep not in operands[0]:
                # The first operand is the owner or group spec. Keyed on shape: a spec carries no
                # path separator, so `chown --reference=/ref /outside/x` keeps its target.
                operands = operands[1:]
            if base in SOURCE_AND_TARGET:
                if targets:
                    operands = []             # `-t` named the target; every operand is a source
                elif not (base == "install" and flags & {"-d", "--directory"}):
                    operands = operands[-1:]  # only the last is created; the rest are reads
        for target in targets + operands:
            out.append((mutator, target))
    return out


def main():
    raw = sys.stdin.read()
    try:
        event = json.loads(raw) if raw.strip() else None
    except ValueError:
        event = None
    if not isinstance(event, dict):
        deny("hook input unreadable (no JSON on stdin) — fail-closed")
    action, reason = check(event, roots_from("LLM_WIKI_LANE_GRANTS"),
                           roots_from("LLM_WIKI_LANE_WRITES"), head_role())
    if action == "silent":
        sys.exit(0)
    decide(action, reason)


if __name__ == "__main__":
    main()
