#!/usr/bin/env python3
"""Score a Markdown conversion for source damage — ingest Step 0's guard.

Stdout-only: this script reads conversions and their PDFs, calls `pdftotext` with its output
on stdout, and writes no file anywhere. It never modifies, creates, moves or deletes anything.

Why it exists (known-issues 2026-09-08, ingest Step 0 conversions): 17 of 96 conversions under
the vault's paper directory carried source damage in two shapes — two files whose line
structure had collapsed to one-character lines, and fifteen whose lines were sound but had
lost the space between words — and only five of the pages compiled from them raised a
`flagged:` line. No probe scored a conversion. This one does, and its `suspect` verdict is the
observable Step 0 records as `flagged:` on the source page (never a prose note).

THE FOUR MEASURES (per file; the body is every line below the YAML frontmatter, or the whole
file when there is no frontmatter)
  short-lines %   the share of NON-BLANK body lines whose stripped content is one character
                  or less, over all non-blank body lines. A blank line is a paragraph break in
                  every Markdown conversion and is counted on neither side; a line of one
                  character is what the structural collapse produces (a word or glyph per line).
  run-together %  the share of Latin word tokens that carry an internal lower-to-upper case
                  join or are longer than LONG_TOKEN letters, over all Latin word tokens, after
                  the exclusions below. Token rule, exactly: a token is a maximal run of Latin
                  letters (a letter is Latin when its Unicode name starts with `LATIN`, so the
                  ligature glyphs a PDF leaves count; a digit, an underscore, a hyphen, an
                  apostrophe, punctuation or a letter of another script ends a token — a CJK run
                  is never a token and never a hit). A token counts as run-together when (a) any
                  lower-case character is immediately followed by an upper-case one, or (b) it
                  has more than LONG_TOKEN letters. Rule (a) catches `algorithmsWe propose`,
                  rule (b) catches `thepolicygradientmethod`; a legitimate CamelCase identifier
                  or a 19-letter word is a false hit, and the derived threshold absorbs that
                  floor. Excluded from numerator and denominator alike, because they are not
                  prose and their tokens are not evidence about the prose: (1) fenced code
                  blocks (a line opening with three or more backticks or tildes to the matching
                  closer, or to the end of the file when unclosed, as CommonMark reads it);
                  (2) angle-bracket tags with everything inside the brackets (`<` up to the next
                  `>`, tag name, attributes and attribute values — the `<latexit sha1_base64="…">`
                  blobs a LaTeXML page leaves live there); (3) base64-shaped blobs — a maximal run
                  of 40 or more characters from the base64 and URL-safe alphabet
                  (`A–Z a–z 0–9 + / = _ -`) that carries at least one letter, at least one digit
                  and a run of six or more consecutive characters none of which is a vowel
                  (`a e i o u y`, either case). Space-stripped prose with a year or a table
                  number inside it keeps a vowel every few letters and so survives the blob rule;
                  base64, hex digests and data-URI payloads do not. The 40 and the six are set by
                  judgement, unmeasured (an English word runs six consonants only in rarities
                  such as `rhythms`, which the `y` clause absorbs). `n/a` on a non-Latin-majority
                  body: when most letters after the exclusions are outside the Latin script there
                  are no inter-word spaces to lose, and the verdict rests on the other measures.
                  `n/a` too when the body holds no word token at all (see exit 2).
  long-run /1k    runs of 25 or more ASCII Latin letters (`[A-Za-z]{25,}`) per 1,000
                  whitespace-separated words of the body — the ingest skill's own Step 0 probe
                  (a), the same rule with none of the exclusions above, so the two agree on what
                  they count (the skill reads the whole file, this reads the body: on the
                  derivation corpus the two agree on every verdict, and the rates differ by
                  under 0.5 per 1,000 except on the two collapsed files whose bodies hold 49 and
                  153 words). Fires when the rate crosses its threshold AND the body holds
                  at least LONG_RUN_FLOOR runs — the skill's own floor, set by judgement,
                  unmeasured, which keeps a very short capture off the gate. `n/a` on a
                  non-Latin-majority body for the reason given above (the skill's 3b makes the
                  same CJK carve-out for its chars-per-word mean).
  recovery        sentence recovery against `pdftotext` (flow order, no `-layout`) when a
                  sibling PDF exists: the fraction of pdftotext sentences of MIN_SENTENCE_WORDS
                  words or more that are found verbatim in the conversion after whitespace
                  normalisation (every run of whitespace on either side collapsed to one space,
                  the text lower-cased and NFKC-normalised so a ligature glyph and its letters
                  compare equal). A sentence is a maximal run of text ended by `.`, `!` or `?`
                  followed by whitespace, and counts when it has MIN_SENTENCE_WORDS or more
                  whitespace-separated words. The PDF is the file `converted_from:` names when
                  that value is a local `.pdf` name beside the conversion, else `<stem>.pdf`
                  beside it; with neither the measure is `n/a (no sibling PDF)`. `pdftotext` is
                  optional and serves this measure only: when the binary is absent the measure
                  reads `n/a (pdftotext absent)`, when it exits non-zero or times out it reads
                  `n/a (pdftotext failed: <first stderr line>)`, and in every `n/a` case the
                  verdict rests on the other three measures and the exit code is 0 or 3, never 2.

SCOPE (printed per file as `scope: pdf` or `scope: other`, with the evidence in brackets)
  The thresholds are derived on PDF conversions of papers, so `pdf` is the scope they were
  measured in. A file is `pdf` when any of three facts holds: `converted_from:` names a `.pdf`
  (a local file name or a URL whose path ends in `.pdf`); a `.pdf` sibling with the file's own
  stem exists; or `converted_by:` names one of the ingest skill's two document-conversion
  routes (`markitdown`, `agent`), the routes a PDF can reach `raw/` by. Everything else — a
  defuddle, Jina, curl or gh capture of a web page — is `other`. The scope never changes the
  verdict: a `suspect` outside the derivation scope is still printed and still exits 3, and
  the ingest skill decides what to do with it (its Step 0 text: a `suspect` on `other` is
  reported in the run report and raises no `flagged:` line by itself). Why not
  `converted_from:` alone: on the derivation corpus 12 of the 17 damaged files record the
  paper's abstract URL there, not the PDF the agent downloaded and converted, and the engine
  is the one remaining observable that says a converter ran. The engine names are the skill's
  own routes, listed in one tuple (DOCUMENT_CONVERTERS); a route the skill adds later is added
  there, and until it is, a conversion by an unlisted engine reads `other` — reported, never
  silent.

VERDICT  `suspect` when any measure crosses its threshold, else `clean`. Every output line
prints the four measured values, the threshold each was judged against, and the scope.

THRESHOLDS — derived, never set by eye. Rule: for each measure, the threshold is the midpoint
of the gap between the worst-scoring known-clean file (the negatives' maximum for the three
rates, their minimum for recovery) and the nearest known-damaged file beyond it — the loosest
cut that admits no known-clean file, with half the gap as headroom on each side. A measure
with no damaged file beyond the worst clean one gets no threshold (`n/a`: it does not
separate) and the verdict rests on the others. Run `--derive DIR --positives FILE` to print
the derivation, and `--distribution DIR` for the percentiles behind it.

Derived 2026-09-08 on the vault's `raw/2-papers/` (96 Markdown conversions; 17 listed as
damaged by the 2026-09-08 deep-lint, the other 79 taken as clean; 57 files had a sibling PDF):
  short-lines %   negatives 0.00–20.69 · positives 0.00–94.44 · one positive beyond the worst
                  negative (the structurally collapsed PPO.md at 94.44) · gap 20.69 → 94.44
                  · threshold > 57.57. This threshold rests on one positive; the second
                  collapsed file (LLM_Probe.md) reads 0.0 % here and is caught by the other
                  measures.
  run-together %  negatives 0.29–3.50 · positives 5.32–52.64 · 17 positives beyond the worst
                  negative · gap 3.50 → 5.32 · threshold > 4.41. Worst clean file
                  arxiv-org-html-2604-21284v1.md (3.50 %, a defuddle capture of an arXiv HTML
                  page); next-worst clean GRPO.md (2.95 %); nearest damaged the SoK survey
                  conversion at 5.32 %. Before the exclusions the worst clean file read 8.68 %
                  (DrGRPO.md: 686 of its 879 hits sat on one `<latexit sha1_base64="…">` line
                  of 8,689 characters) and the threshold, 9.15 %, missed that same 5.32 % file.
  long-run /1k    negatives 0.00–2.48 · positives 10.64–5224.49 · 17 positives beyond the
                  worst negative · gap 2.48 → 10.64 · threshold > 6.56. Worst clean SWIFT.md
                  (2.48), next-worst DrGRPO.md (2.27); nearest damaged the SoK conversion
                  (10.64, 284 runs in 26,688 words), the file the share alone missed under the
                  old token rule — the skill's probe (a) caught it at a 4× margin, so it is a
                  measure here.
  recovery        negatives 0.29–0.94 (53 with a PDF) · positives 0.00–0.01 (4 with a PDF)
                  · all 4 beyond the worst negative · gap 0.29 → 0.01 · threshold < 0.15
  combined verdict at these thresholds: suspect 17 · clean 79 · true positives 17 · false
  positives 0 · false negatives 0 · precision 1.000 · recall 1.000. Every positive reads
  `scope: pdf`; 15 of the 79 clean files are web captures and read `scope: other`.
The numbers above are the ones baked in below; re-run `--derive` after the corpus changes and
update both places together. A `--thresholds` override is printed on the summary line.

USAGE
  python3 -B conversion_score.py FILE [FILE …]             score files (or every .md in a DIR)
  python3 -B conversion_score.py --distribution DIR        percentiles of each measure over DIR
  python3 -B conversion_score.py --derive DIR --positives FILE
                                                           threshold derivation (FILE lists the
                                                           known-damaged conversions, one path
                                                           per line; matched on the basename)
  --thresholds SHORT,RUN,RECOVERY,LONGRUN   override the four thresholds (a bare `-` keeps
                                    one, `off` disables one); recorded on the summary line
  CONVERSION_SCORE_PDFTOTEXT        environment: the pdftotext binary to use (default: PATH,
                                    then the usual Homebrew locations); tests point it away

EXIT  0 every file clean · 3 any file suspect · 2 premise failure (an unreadable or empty
file, a body with no word token, a directory with no `.md`, a positives entry not found in
DIR, a malformed option). A missing or failing `pdftotext` is not a premise failure.
"""
import os
import re
import sys
import unicodedata
import subprocess
from functools import lru_cache

# --- derived thresholds (see the docstring for the derivation) ---------------------------
THRESHOLD_SHORT = 57.57    # short-lines %  : suspect when ABOVE (rests on one positive, PPO.md)
THRESHOLD_RUN = 4.41       # run-together % : suspect when ABOVE
THRESHOLD_RECOVERY = 0.15  # recovery       : suspect when BELOW
THRESHOLD_LONG_RUN = 6.56  # long-run /1k   : suspect when ABOVE (and LONG_RUN_FLOOR runs or more)
DERIVED_ON = "2026-09-08 on raw/2-papers (96 files, 17 positives)"

LONG_TOKEN = 18            # rule (b): more than this many letters — set by judgement, unmeasured
LONG_RUN_FLOOR = 10        # long-run fires only with this many runs — the skill's floor, set by judgement, unmeasured
MIN_SENTENCE_WORDS = 6     # a pdftotext sentence counts from this many words — set by judgement, unmeasured
PDFTOTEXT_TIMEOUT_S = 120  # bound on one pdftotext call — a timeout, set by judgement, unmeasured; a hit reads n/a
BLOB_MIN_CHARS = 40        # base64-shaped blob: at least this long — set by judgement, unmeasured
BLOB_NO_VOWEL_RUN = 6      # …and a run of this many non-vowels — set by judgement, unmeasured
DOCUMENT_CONVERTERS = ("markitdown", "agent")   # the ingest skill's document-conversion routes (scope pdf)

LETTER_RUN_RE = re.compile(r"[^\W\d_]+")
LONG_RUN_RE = re.compile(r"[A-Za-z]{25,}")       # the ingest skill's Step 0 probe (a), verbatim
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+")
WS_RE = re.compile(r"\s+")
FM_RE = re.compile(r"\A---[ \t]*\r?\n(.*?\r?\n)---[ \t]*\r?\n", re.S)
CONVERTED_FROM_RE = re.compile(r"^converted_from:[ \t]*(.+?)[ \t]*$", re.M)
CONVERTED_BY_RE = re.compile(r"^converted_by:[ \t]*(.+?)[ \t]*$", re.M)
URL_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*://")
TAG_RE = re.compile(r"<[A-Za-z!/?][^<>]*>")
BLOB_RE = re.compile(r"[A-Za-z0-9+/=_\-]{%d,}" % BLOB_MIN_CHARS)
NO_VOWEL_RUN_RE = re.compile(r"[^aeiouyAEIOUY]{%d}" % BLOB_NO_VOWEL_RUN)
DIGIT_RE = re.compile(r"\d")
LETTER_RE = re.compile(r"[A-Za-z]")

USAGE = ("usage: conversion_score.py [--thresholds S,R,C,L] FILE|DIR … | --distribution DIR | "
         "--derive DIR --positives FILE   (exit 0 clean · 3 suspect · 2 premise failure)")


def probe_failed(message):
    print(f"PROBE FAILED: {message}", file=sys.stderr)
    raise SystemExit(2)


# --- reading ----------------------------------------------------------------------------
def read_text(path):
    """UTF-8 with a BOM dropped and CRLF normalised; bad bytes replaced, never fatal."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        probe_failed(f"cannot read {path}: {exc}")
    return raw.decode("utf-8-sig", "replace").replace("\r\n", "\n")


def split_frontmatter(text):
    """(frontmatter or '', body)."""
    m = FM_RE.match(text)
    if not m:
        return "", text
    return m.group(1), text[m.end():]


@lru_cache(maxsize=None)
def is_latin(ch):
    return unicodedata.name(ch, "").startswith("LATIN")


# --- exclusions (run-together only) -----------------------------------------------------
def strip_fences(body):
    """Drop fenced code blocks: from a line opening with ``` or ~~~ to the matching closer,
    or to the end of the file when the fence is never closed (CommonMark's reading)."""
    out, fence = [], None
    for line in body.split("\n"):
        s = line.lstrip()
        if fence is None:
            if s.startswith("```") or s.startswith("~~~"):
                fence = s[:3]
                continue
            out.append(line)
        elif s.startswith(fence):
            fence = None
    return "\n".join(out)


def is_blob(chunk):
    return (bool(DIGIT_RE.search(chunk)) and bool(LETTER_RE.search(chunk))
            and bool(NO_VOWEL_RUN_RE.search(chunk)))


def strip_blobs(text):
    return BLOB_RE.sub(lambda m: " " if is_blob(m.group(0)) else m.group(0), text)


def prose_text(body):
    """The body with fenced code, angle-bracket tags and base64-shaped blobs excluded."""
    return strip_blobs(TAG_RE.sub(" ", strip_fences(body)))


# --- measures ---------------------------------------------------------------------------
def short_line_share(body):
    """(share %, short, non-blank) over non-blank body lines."""
    lines = [ln.strip() for ln in body.split("\n")]
    nonblank = [ln for ln in lines if ln]
    short = sum(1 for ln in nonblank if len(ln) <= 1)
    return (100.0 * short / len(nonblank) if nonblank else 0.0), short, len(nonblank)


def latin_tokens(text):
    """(tokens, letters, latin_letters): maximal runs of Latin letters, and the letter census
    the Latin-majority test rests on."""
    tokens = []
    letters = latin = 0
    for run in LETTER_RUN_RE.findall(text):
        letters += len(run)
        if run.isascii():
            latin += len(run)
            tokens.append(run)
            continue
        cur = []
        for ch in run:
            if is_latin(ch):
                latin += 1
                cur.append(ch)
            elif cur:
                tokens.append("".join(cur))
                cur = []
        if cur:
            tokens.append("".join(cur))
    return tokens, letters, latin


def is_run_together(tok):
    if len(tok) > LONG_TOKEN:
        return True
    if tok.islower() or tok.isupper() or tok.istitle():
        return False            # no lower-to-upper join is possible in these shapes
    return any(a.islower() and b.isupper() for a, b in zip(tok, tok[1:]))


def run_together_share(body):
    """(share % or None, hits, tokens, latin_majority, any_token, note) over the prose text;
    the note says why the share is n/a."""
    tokens, letters, latin = latin_tokens(prose_text(body))
    any_token = bool(LETTER_RUN_RE.search(body))
    latin_majority = letters > 0 and latin * 2 >= letters
    if not latin_majority:
        return None, 0, len(tokens), False, any_token, "non-Latin-majority text: no inter-word spaces to lose"
    if not tokens:
        return None, 0, 0, True, any_token, "no prose token outside the exclusions"
    hits = sum(1 for tok in tokens if is_run_together(tok))
    return 100.0 * hits / len(tokens), hits, len(tokens), True, any_token, None


def long_run_rate(body, latin_majority):
    """(rate per 1,000 words or None, runs, words) — the skill's probe (a) on the body."""
    runs = len(LONG_RUN_RE.findall(body))
    words = len(body.split()) or 1
    if not latin_majority:
        return None, runs, words
    return runs * 1000.0 / words, runs, words


def normalise(text):
    return WS_RE.sub(" ", unicodedata.normalize("NFKC", text)).strip().lower()


def find_pdftotext():
    override = os.environ.get("CONVERSION_SCORE_PDFTOTEXT")
    if override:
        return override if os.path.isfile(override) and os.access(override, os.X_OK) else None
    for d in os.environ.get("PATH", "").split(os.pathsep) + ["/opt/homebrew/bin", "/usr/local/bin"]:
        cand = os.path.join(d, "pdftotext")
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def converted_from(frontmatter):
    m = CONVERTED_FROM_RE.search(frontmatter)
    return m.group(1).strip().strip("\"'") if m else ""


def names_pdf(value):
    """True when a converted_from: value names a .pdf — a local name, or a URL whose path
    (query and fragment dropped) ends in .pdf."""
    if not value:
        return False
    path = value.split("?", 1)[0].split("#", 1)[0] if URL_RE.match(value) else value
    return path.lower().endswith(".pdf")


def sibling_pdf(path, frontmatter):
    """The PDF `converted_from:` names when it is a local .pdf beside the conversion, else
    <stem>.pdf beside it, else None."""
    here = os.path.dirname(os.path.abspath(path))
    named = converted_from(frontmatter)
    if named.lower().endswith(".pdf") and not URL_RE.match(named):
        cand = named if os.path.isabs(named) else os.path.join(here, named)
        if os.path.isfile(cand):
            return cand
    stem = os.path.splitext(os.path.basename(path))[0]
    cand = os.path.join(here, stem + ".pdf")
    return cand if os.path.isfile(cand) else None


def scope_of(frontmatter, pdf):
    """('pdf' | 'other', evidence)."""
    if names_pdf(converted_from(frontmatter)):
        return "pdf", "converted_from names a PDF"
    if pdf:
        return "pdf", "sibling PDF"
    m = CONVERTED_BY_RE.search(frontmatter)
    engine = m.group(1).strip().strip("\"'") if m else ""
    first = re.match(r"[A-Za-z][A-Za-z0-9_\-]*", engine)
    first = first.group(0).lower() if first else ""
    if first in DOCUMENT_CONVERTERS:
        return "pdf", f"converted_by {first}"
    if engine:
        return "other", f"web capture, converted_by {engine[:24]}"
    return "other", "no converted_by and no PDF evidence"


def pdf_sentences(pdf, exe):
    """(sentences or None, reason): pdftotext sentences of MIN_SENTENCE_WORDS words or more,
    normalised; None with the reason when pdftotext fails or times out."""
    try:
        proc = subprocess.run([exe, "-enc", "UTF-8", pdf, "-"], capture_output=True, timeout=PDFTOTEXT_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return None, f"pdftotext failed: timed out after {PDFTOTEXT_TIMEOUT_S} s"
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"pdftotext failed: {str(exc).splitlines()[0][:120] if str(exc) else type(exc).__name__}"
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip().splitlines()
        first = err[0][:120] if err else f"exit {proc.returncode}, no stderr"
        return None, f"pdftotext failed: {first}"
    text = normalise(proc.stdout.decode("utf-8", "replace"))
    out = []
    for sent in SENTENCE_END_RE.split(text):
        sent = sent.strip()
        if len(sent.split(" ")) >= MIN_SENTENCE_WORDS:
            out.append(sent)
    return out, None


def recovery_fraction(body, pdf, exe):
    """(fraction or None, found, total, reason) — None with a reason when pdftotext fails or
    yields no sentence to look for."""
    sentences, reason = pdf_sentences(pdf, exe)
    if sentences is None:
        return None, 0, 0, reason
    if not sentences:
        return None, 0, 0, f"pdftotext yielded no sentence of {MIN_SENTENCE_WORDS} words"
    conv = normalise(body)
    found = sum(1 for s in sentences if s in conv)
    return found / len(sentences), found, len(sentences), None


def score_file(path, exe_cache):
    """Every measure for one file; premise failures exit 2 here."""
    text = read_text(path)
    if not text.strip():
        probe_failed(f"{path} is empty")
    fm, body = split_frontmatter(text)
    if not body.strip():
        probe_failed(f"{path} has no body below its frontmatter")
    short, n_short, n_lines = short_line_share(body)
    run, n_hits, n_tokens, latin, any_token, run_note = run_together_share(body)
    if not any_token:
        probe_failed(f"{path} holds no word token")
    long_run, n_runs, n_words = long_run_rate(body, latin)
    pdf = sibling_pdf(path, fm)
    scope, evidence = scope_of(fm, pdf)
    rec = None
    found = total = 0
    if pdf is None:
        rec_note = "no sibling PDF"
    else:
        if "exe" not in exe_cache:
            exe_cache["exe"] = find_pdftotext()
        if not exe_cache["exe"]:
            rec_note = "pdftotext absent"
        else:
            rec, found, total, rec_note = recovery_fraction(body, pdf, exe_cache["exe"])
    return {
        "path": path, "short": short, "n_short": n_short, "n_lines": n_lines,
        "run": run, "n_hits": n_hits, "n_tokens": n_tokens, "latin": latin, "run_note": run_note,
        "long_run": long_run, "n_runs": n_runs, "n_words": n_words,
        "pdf": pdf, "recovery": rec, "found": found, "total": total, "rec_note": rec_note,
        "scope": scope, "scope_evidence": evidence,
    }


def verdict(m, t_short, t_run, t_rec, t_long):
    reasons = []
    if t_short is not None and m["short"] > t_short:
        reasons.append("short-lines")
    if t_run is not None and m["run"] is not None and m["run"] > t_run:
        reasons.append("run-together")
    if t_long is not None and m["long_run"] is not None and m["long_run"] > t_long and m["n_runs"] >= LONG_RUN_FLOOR:
        reasons.append("long-run")
    if t_rec is not None and m["recovery"] is not None and m["recovery"] < t_rec:
        reasons.append("recovery")
    return ("suspect" if reasons else "clean"), reasons


def fmt_threshold(value, unit=""):
    return "n/a" if value is None else f"{value:g}{unit}"


def render(m, t_short, t_run, t_rec, t_long):
    v, reasons = verdict(m, t_short, t_run, t_rec, t_long)
    ts = fmt_threshold(t_short, " %")
    tr = fmt_threshold(t_run, " %")
    tc = fmt_threshold(t_rec)
    tl = fmt_threshold(t_long, " /1k")
    short = f"short-lines {m['short']:.1f} % ({'>' if 'short-lines' in reasons else '<='} {ts}; {m['n_short']}/{m['n_lines']} lines)"
    if m["run"] is None:
        run = f"run-together n/a ({m['run_note']})"
    else:
        run = f"run-together {m['run']:.1f} % ({'>' if 'run-together' in reasons else '<='} {tr}; {m['n_hits']}/{m['n_tokens']} tokens)"
    if m["long_run"] is None:
        long_run = "long-run n/a (non-Latin-majority text)"
    else:
        long_run = f"long-run {m['long_run']:.1f} /1k ({'>' if 'long-run' in reasons else '<='} {tl}; {m['n_runs']} runs/{m['n_words']} words)"
    if m["recovery"] is None:
        rec = f"recovery n/a ({m['rec_note']})"
    else:
        rec = f"recovery {m['recovery']:.2f} ({'<' if 'recovery' in reasons else '>='} {tc}; {m['found']}/{m['total']} sentences)"
    return f"{v:7s} {m['path']} · {short} · {run} · {long_run} · {rec} · scope: {m['scope']} ({m['scope_evidence']})"


# --- corpus helpers --------------------------------------------------------------------
def md_files(directory):
    if not os.path.isdir(directory):
        probe_failed(f"{directory} is not a directory")
    files = sorted(os.path.join(directory, n) for n in os.listdir(directory)
                   if n.lower().endswith(".md") and os.path.isfile(os.path.join(directory, n)))
    if not files:
        probe_failed(f"{directory} holds no .md file")
    return files


def percentile(values, p):
    """Linear interpolation between the two nearest ranks (the NumPy default)."""
    s = sorted(values)
    if not s:
        return None
    k = (len(s) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


MEASURES = (("short-lines %", "short", True, 1),
            ("run-together %", "run", True, 1),
            ("long-run /1k", "long_run", True, 1),
            ("recovery", "recovery", False, 2))


def distribution(directory):
    files = md_files(directory)
    cache = {}
    rows = [score_file(f, cache) for f in files]
    scopes = sum(1 for r in rows if r["scope"] == "pdf")
    print(f"DISTRIBUTION over {directory}: {len(rows)} files ({scopes} scope pdf, {len(rows) - scopes} other)   "
          f"(percentiles by linear interpolation)")
    print(f"{'measure':16s} {'n':>10s} {'min':>7s} {'p10':>7s} {'p25':>7s} {'p50':>7s} {'p75':>7s} {'p90':>7s} {'max':>7s}")
    for label, key, _, digits in MEASURES:
        vals = [r[key] for r in rows if r[key] is not None]
        na = len(rows) - len(vals)
        n = f"{len(vals)}" + (f" ({na} n/a)" if na else "")
        cells = [percentile(vals, p) for p in (0, 10, 25, 50, 75, 90, 100)]
        print(f"{label:16s} {n:>10s} " + " ".join(f"{c:7.{digits}f}" if c is not None else f"{'n/a':>7s}" for c in cells))
    return 0


def separate(neg, pos, higher_is_worse):
    """(threshold, caught, worst_negative, nearest_positive): the midpoint of the gap between
    the worst negative and the nearest positive beyond it; threshold None when nothing lies
    beyond. neg and pos are (value, path) pairs."""
    if not neg or not pos:
        return None, 0, None, None
    if higher_is_worse:
        worst = max(neg)
        beyond = [p for p in pos if p[0] > worst[0]]
        nearest = min(beyond) if beyond else None
    else:
        worst = min(neg)
        beyond = [p for p in pos if p[0] < worst[0]]
        nearest = max(beyond) if beyond else None
    if nearest is None:
        return None, 0, worst, None
    return (worst[0] + nearest[0]) / 2.0, len(beyond), worst, nearest


def derive(directory, positives_file):
    files = md_files(directory)
    try:
        with open(positives_file, encoding="utf-8") as fh:
            listed = [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]
    except OSError as exc:
        probe_failed(f"cannot read positives {positives_file}: {exc}")
    if not listed:
        probe_failed(f"{positives_file} lists no positive")
    by_base = {os.path.basename(f): f for f in files}
    missing = [p for p in listed if os.path.basename(p) not in by_base]
    if missing:
        probe_failed(f"{len(missing)} positive(s) not found in {directory}: {', '.join(missing[:5])}")
    pos_set = {os.path.basename(p) for p in listed}
    cache = {}
    rows = [score_file(f, cache) for f in files]
    pos_rows = [r for r in rows if os.path.basename(r["path"]) in pos_set]
    neg_rows = [r for r in rows if os.path.basename(r["path"]) not in pos_set]
    print(f"DERIVATION over {directory}: {len(rows)} files · positives {len(pos_rows)} (from {positives_file}) "
          f"· negatives {len(neg_rows)} · scope pdf {sum(1 for r in rows if r['scope'] == 'pdf')} "
          f"(positives {sum(1 for r in pos_rows if r['scope'] == 'pdf')})")
    print("rule: threshold = midpoint of the gap between the worst known-clean value and the nearest "
          "known-damaged value beyond it (the loosest cut admitting no known-clean file); no positive "
          "beyond the worst negative = the measure does not separate (n/a)")
    thresholds = {}
    base = os.path.basename
    for label, key, worse_high, _ in MEASURES:
        digits = 2
        pos = [(r[key], base(r["path"])) for r in pos_rows if r[key] is not None]
        neg = [(r[key], base(r["path"])) for r in neg_rows if r[key] is not None]
        na_pos, na_neg = len(pos_rows) - len(pos), len(neg_rows) - len(neg)
        t, caught, worst, nearest = separate(neg, pos, worse_high)
        thresholds[key] = t
        rng = lambda v: f"{min(v)[0]:.{digits}f}–{max(v)[0]:.{digits}f}" if v else "n/a"
        sign = ">" if worse_high else "<"
        if t is None:
            cut = "n/a — does not separate at zero false positives"
        else:
            cut = f"{sign} {t:.{digits}f} (midpoint of the gap {worst[0]:.{digits}f} → {nearest[0]:.{digits}f})"
        print(f"  {label:15s} positives {rng(pos)} ({len(pos)}" + (f", {na_pos} n/a" if na_pos else "") +
              f") · negatives {rng(neg)} ({len(neg)}" + (f", {na_neg} n/a" if na_neg else "") +
              f") · caught {caught}/{len(pos)} · threshold {cut}")
        if worst is not None:
            others = sorted((v for v in neg if v[1] != worst[1]), reverse=worse_high)
            next_worst = others[0] if others else None
            print(f"  {'':15s} worst clean {worst[1]} ({worst[0]:.{digits}f})"
                  + (f" · next-worst clean {next_worst[1]} ({next_worst[0]:.{digits}f})" if next_worst else "")
                  + (f" · nearest damaged {nearest[1]} ({nearest[0]:.{digits}f})" if nearest else ""))
    tp = fp = fn = tn = 0
    wrong = []
    for r in rows:
        v, _ = verdict(r, thresholds["short"], thresholds["run"], thresholds["recovery"], thresholds["long_run"])
        is_pos = base(r["path"]) in pos_set
        if v == "suspect" and is_pos:
            tp += 1
        elif v == "suspect":
            fp += 1
            wrong.append(f"false positive: {r['path']}")
        elif is_pos:
            fn += 1
            wrong.append(f"false negative: {r['path']}")
        else:
            tn += 1
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    print(f"combined verdict at these thresholds: suspect {tp + fp} · clean {tn + fn} · true positives {tp} "
          f"· false positives {fp} · false negatives {fn} · precision {prec:.3f} · recall {rec:.3f}")
    print("misclassified: " + ("(none)" if not wrong else "; ".join(wrong)))
    baked = (THRESHOLD_SHORT, THRESHOLD_RUN, THRESHOLD_RECOVERY, THRESHOLD_LONG_RUN)
    derived = tuple(None if t is None else round(t, 2)
                    for t in (thresholds["short"], thresholds["run"], thresholds["recovery"], thresholds["long_run"]))
    same = baked == derived
    print(f"baked-in thresholds {tuple(fmt_threshold(b) for b in baked)} "
          f"{'match' if same else 'DIFFER FROM'} the derived {tuple(fmt_threshold(d) for d in derived)}"
          + (" (rounded to two decimals)" if same else " — update the constants and the docstring together"))
    return 0


# --- entry ------------------------------------------------------------------------------
def parse_thresholds(spec):
    parts = spec.split(",")
    if len(parts) != 4:
        probe_failed(f"--thresholds wants SHORT,RUN,RECOVERY,LONGRUN, got {spec!r}")
    out = []
    for part, default in zip(parts, (THRESHOLD_SHORT, THRESHOLD_RUN, THRESHOLD_RECOVERY, THRESHOLD_LONG_RUN)):
        part = part.strip()
        if part in ("", "-"):
            out.append(default)
        elif part.lower() in ("n/a", "none", "off"):
            out.append(None)
        else:
            try:
                out.append(float(part))
            except ValueError:
                probe_failed(f"--thresholds value {part!r} is not a number")
    return tuple(out)


def main(argv):
    args = list(argv)
    if not args or args[0] in ("-h", "--help"):
        print(USAGE)
        return 0
    if args[0] == "--distribution":
        if len(args) != 2:
            probe_failed("--distribution takes exactly one directory")
        return distribution(args[1])
    if args[0] == "--derive":
        if len(args) != 4 or args[2] != "--positives":
            probe_failed("--derive DIR --positives FILE")
        return derive(args[1], args[3])
    thresholds = (THRESHOLD_SHORT, THRESHOLD_RUN, THRESHOLD_RECOVERY, THRESHOLD_LONG_RUN)
    override = None
    if args[0] == "--thresholds":
        if len(args) < 3:
            probe_failed("--thresholds needs a value and at least one file")
        override = args[1]
        thresholds = parse_thresholds(override)
        args = args[2:]
    if any(a.startswith("-") for a in args):
        probe_failed(f"unknown option in {args} ({USAGE})")
    targets = []
    for a in args:
        if os.path.isdir(a):
            targets.extend(md_files(a))
        else:
            targets.append(a)
    t_short, t_run, t_rec, t_long = thresholds
    cache = {}
    suspect = 0
    scopes = {"pdf": 0, "other": 0}
    for path in targets:
        m = score_file(path, cache)
        line = render(m, t_short, t_run, t_rec, t_long)
        if line.startswith("suspect"):
            suspect += 1
        scopes[m["scope"]] += 1
        print(line)
    source = f"override {override!r}" if override else f"derived {DERIVED_ON}"
    print(f"SCORED: {len(targets)} file(s) · clean {len(targets) - suspect} · suspect {suspect} · "
          f"scope pdf {scopes['pdf']} | other {scopes['other']} · "
          f"thresholds short-lines > {fmt_threshold(t_short, ' %')} | run-together > {fmt_threshold(t_run, ' %')} "
          f"| long-run > {fmt_threshold(t_long, ' /1k')} | recovery < {fmt_threshold(t_rec)} ({source})")
    return 3 if suspect else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
