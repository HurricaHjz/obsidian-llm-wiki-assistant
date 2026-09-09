#!/bin/sh
# test_conversion_score.sh — suite for conversion_score.py, ingest Step 0's conversion scorer.
# Every fixture is built under one mktemp -d in /tmp and removed at exit; the vault is never
# touched. The final legs are the stdout-only proof: a read-only copy of the fixture set with a
# checksum manifest before and after every flag the script takes, the script home compared with
# its pre-run baseline, and a source grep for write patterns whose own control must hit.
#
# Run:  sh .claude/skills/ingest/test_conversion_score.sh      (exit 0 = every leg passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCORE="$HERE/conversion_score.py"
PY=python3

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '    ok   — %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL   — %s\n' "$1"; }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1  [want '$2', got '$3']"; fi; }
has(){ printf '%s\n' "$2" | grep -c -- "$1"; }   # has <pattern> <text>: matching lines

T="$(mktemp -d /tmp/convscore.XXXXXX)"
trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
F="$T/fixture"; mkdir -p "$F" "$T/nomd" "$T/withpdf"
ERR="$T/stderr.txt"
printf 'not markdown\n' > "$T/nomd/readme.txt"

manifest(){ find "$1" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum | LC_ALL=C sort; }
hashes(){ printf '%s\n' "$1" | grep -c '^[0-9a-f]\{40\}  '; }
START_H="$(manifest "$HERE")"

# The four derived thresholds the script bakes in (asserted verbatim below, so a silent edit of
# one constant fails the suite until the docstring and this file are updated together).
TS='57\.57 %'; TR='4\.41 %'; TL='6\.56 /1k'; TC='0\.15'

# ---------------------------------------------------------------- fixtures
PROSE='The policy gradient method estimates the direction of improvement from sampled trajectories and applies a clipped update so that the new policy stays close to the old one. Each iteration collects a batch of episodes, computes advantages with a learned value function, and runs several epochs of minibatch optimisation on the surrogate objective. The clipping range bounds the ratio between the new and the old policy, which keeps the update conservative without a separate constraint. Empirically this simple recipe matches or exceeds the trust region method on continuous control tasks while being far easier to implement and tune. The authors also report results on discrete action benchmarks where the same objective works without modification.'

# clean: ordinary prose, a URL source converted by markitdown (scope pdf by engine), no PDF beside it
printf -- '---\nconverted_from: https://example.org/paper\nconverted_by: markitdown\nconverted_on: 2026-01-01\n---\n\n# A clean conversion\n\n%s\n\n%s\n' "$PROSE" "$PROSE" > "$F/clean.md"

# collapsed: the structural collapse — one character per line for most of the body
{ printf -- '---\nconverted_by: markitdown\n---\n\n# Collapsed\n\n'
  i=0; while [ $i -lt 45 ]; do printf 'a\n'; i=$((i+1)); done
  printf 'One ordinary line survives in the middle.\n\n'
  i=0; while [ $i -lt 15 ]; do printf 'b\n'; i=$((i+1)); done
  printf 'A second ordinary line survives at the end.\n'; } > "$F/collapsed.md"

# joined: sound lines, inter-word spaces lost on a share of the words (a lower-to-upper join
# or a run of more than 18 letters), well above the derived threshold
"$PY" - "$F/joined.md" "$PROSE" <<'PYFIX'
import sys
path, prose = sys.argv[1], sys.argv[2]
words = prose.split()
out, i = [], 0
while i < len(words):
    if i % 4 == 0 and i + 1 < len(words):          # join every fourth pair: "methodEstimates"
        out.append(words[i] + words[i + 1][0].upper() + words[i + 1][1:]); i += 2
    else:
        out.append(words[i]); i += 1
body = " ".join(out)
open(path, "w", encoding="utf-8").write("---\nconverted_by: markitdown\n---\n\n# Joined\n\n" + body + "\n\n" + body + "\n")
PYFIX

# runs: the SoK shape — a run-together share well under its threshold, but twelve runs of 25+
# letters in 1,100 words (the skill's probe (a) rate above its threshold). runs-few: the same
# rate from two runs in 110 words — under the skill's ten-run floor, so it must not fire.
"$PY" - "$F/runs.md" "$F/runs-few.md" "$PROSE" <<'PYFIX'
import re, sys
runs_path, few_path, prose = sys.argv[1], sys.argv[2], sys.argv[3]
def build(copies, joins):
    words = (prose.split() * copies)
    out, i, made = [], 0, 0
    while i < len(words):
        if made < joins and i % 90 == 0:
            run, k = "", 0
            while len(run) < 25 and i + k < len(words):
                run += re.sub(r"[^A-Za-z]", "", words[i + k]).lower(); k += 1
            out.append(run); i += k; made += 1
        else:
            out.append(words[i]); i += 1
    assert made == joins, made
    return " ".join(out)
open(runs_path, "w", encoding="utf-8").write("---\nconverted_from: https://example.org/abs/1\nconverted_by: markitdown\n---\n\n# Runs\n\n" + build(10, 12) + "\n")
open(few_path, "w", encoding="utf-8").write("---\nconverted_from: https://example.org/abs/2\nconverted_by: markitdown\n---\n\n# Few runs\n\n" + build(1, 2) + "\n")
PYFIX

# exclusions: the same 100 CamelCase identifiers inside a fence (must not count) and outside
# one (the positive control: they would fire); a tag carrying a base64 attribute; a bare blob;
# and space-stripped prose that carries digits, which the blob rule must keep as evidence
"$PY" - "$F" "$PROSE" <<'PYFIX'
import sys
d, prose = sys.argv[1], sys.argv[2]
idents = " ".join(f"BetaMessageParam{i} ContentBlockDeltaEvent{i}" for i in range(50))
# the same three-token heading as clean.md, so the token counts compare exactly
head = "---\nconverted_from: https://example.org/docs\nconverted_by: markitdown\n---\n\n# A clean conversion\n\n"
open(f"{d}/excl-fence.md", "w", encoding="utf-8").write(head + prose + "\n\n```python\n" + idents + "\n```\n\n" + prose + "\n")
open(f"{d}/excl-fence-control.md", "w", encoding="utf-8").write(head + prose + "\n\n" + idents + "\n\n" + prose + "\n")
blob = "Zx9Qw7Kp2Lm4Rt8Vn3Bc6Fd1Hg5Jk0Pq7Sz2Wx4Tn3Mr8Vb5Ng2Kl7Xz1Qw9" * 3
open(f"{d}/excl-tag.md", "w", encoding="utf-8").write(head + prose + '\n\n<latexit sha1_base64="' + blob + '">someInlineMath</latexit> <div class="someCamelCaseClass anotherCamelCaseName">\n\n' + prose + "\n")
open(f"{d}/excl-blob.md", "w", encoding="utf-8").write(head + prose + "\n\n" + blob + " " + blob + "\n\n" + prose + "\n")
damaged = " ".join(f"Table{i}showsthattheproposedmethodoutperformsthebaseline" for i in range(1, 21))
open(f"{d}/digits-prose.md", "w", encoding="utf-8").write(head + prose + "\n\n" + damaged + "\n\n" + prose + "\n")
PYFIX

# cjk: a non-Latin-majority body (no inter-word spaces to lose); cjk-mixed: English prose with
# CJK sentences making some 40 % of the letters — Latin-majority, scored on the Latin tokens
CJK='策略梯度方法从采样的轨迹中估计改进方向，并施加裁剪更新，使新策略与旧策略保持接近。每次迭代收集一批回合，用学习到的价值函数计算优势，并在替代目标上运行若干轮小批量优化。裁剪范围限制了新旧策略之间的比率，从而在没有单独约束的情况下保持更新的保守性。实验表明这一简单方法在连续控制任务上与信赖域方法相当或更好，同时更容易实现和调参。'
printf -- '---\nconverted_by: markitdown\n---\n\n# 中文转换\n\n%s\n\n%s\n' "$CJK" "$CJK" > "$F/cjk.md"
printf -- '---\nconverted_by: markitdown\n---\n\n# Mixed\n\n%s\n\n%s\n\n%s\n\n%s\n' "$PROSE" "$CJK" "$PROSE" "$CJK" > "$F/cjk-mixed.md"

# scope fixtures: a URL ending in .pdf under a web engine, a web capture, and no provenance at all
printf -- '---\nconverted_from: https://example.org/files/paper.pdf?download=1\nconverted_by: jina\n---\n\n# URL PDF\n\n%s\n' "$PROSE" > "$F/scope-url-pdf.md"
printf -- '---\nconverted_from: https://example.org/page\nconverted_by: defuddle\n---\n\n# Web\n\n%s\n' "$PROSE" > "$F/scope-web.md"
printf -- '# No provenance\n\n%s\n' "$PROSE" > "$F/scope-none.md"

# the PDF pair: a minimal one-page PDF carrying three sentences of six words or more, one
# conversion that holds them (recovery 1.00) and one that holds other prose (recovery 0.00),
# a conversion whose converted_from: names a PDF under a different stem, and a clean .md beside
# a garbage .pdf (pdftotext must fail on it, and the verdict must rest on the other measures)
"$PY" - "$T/withpdf" <<'PYFIX'
import os, sys
d = sys.argv[1]
lines = ["The quick brown fox jumps over the lazy dog today.",
         "A second sentence with more than six words sits here.",
         "The third sentence also carries more than six words in total."]
def esc(s): return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
content = "BT /F1 12 Tf 72 720 Td 16 TL " + " ".join("(%s) Tj T*" % esc(l) for l in lines) + " ET"
objs = ["<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        "<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out = "%PDF-1.4\n"; offsets = []
for i, o in enumerate(objs, 1):
    offsets.append(len(out)); out += "%d 0 obj\n%s\nendobj\n" % (i, o)
xref = len(out)
out += "xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for off in offsets: out += "%010d 00000 n \n" % off
out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
for name in ("good.pdf", "bad.pdf", "other-name.pdf"):
    open(os.path.join(d, name), "wb").write(out.encode("latin-1"))
open(os.path.join(d, "garbage.pdf"), "wb").write(b"%PDF-1.4\ngarbage that is not a pdf body\n")
prose = " ".join(lines)
open(os.path.join(d, "good.md"), "w").write("---\nconverted_by: markitdown\n---\n\n# Good\n\n" + prose + "\n")
open(os.path.join(d, "bad.md"), "w").write("---\nconverted_by: markitdown\n---\n\n# Bad\n\nEntirely different prose that shares no sentence with the document it claims to convert, written at some length so that the body is not empty.\n")
open(os.path.join(d, "named.md"), "w").write("---\nconverted_from: other-name.pdf\nconverted_by: markitdown\n---\n\n# Named\n\n" + prose + "\n")
open(os.path.join(d, "garbage.md"), "w").write("---\nconverted_by: markitdown\n---\n\n# Garbage PDF beside a clean conversion\n\n" + prose + "\n")
PYFIX

: > "$F/empty.md"
printf -- '---\nconverted_by: markitdown\n---\n' > "$F/fm-only.md"
mkdir -p "$F/only-good"; cp "$F/clean.md" "$F/only-good/clean.md"; cp "$F/cjk.md" "$F/only-good/cjk.md"
mkdir -p "$F/mixed"; cp "$F/clean.md" "$F/collapsed.md" "$F/joined.md" "$F/cjk.md" "$F/mixed/"
cp "$T/withpdf/good.md" "$T/withpdf/good.pdf" "$T/withpdf/bad.md" "$T/withpdf/bad.pdf" "$F/mixed/"

score(){ "$PY" -B "$SCORE" "$@" 2>"$ERR"; }
tokens(){ printf '%s\n' "$1" | sed -n 's/.*run-together [0-9.]* % ([<>=]* [0-9.]* %; [0-9]*\/\([0-9]*\) tokens).*/\1/p'; }

echo '--- verdicts ---'
OUT="$(score "$F/collapsed.md")"; rc=$?
eq "a collapsed conversion (one-character lines) is suspect, exit 3" "3" "$rc"
eq "  the short-line share is the reason, printed with its threshold" "1" "$(has "^suspect .*short-lines [89][0-9]\.[0-9] % (> $TS" "$OUT")"
eq "  its run-together share is below threshold (single letters are not joins)" "1" "$(has "run-together 0\.0 % (<= $TR" "$OUT")"
eq "  its long-run rate is zero" "1" "$(has "long-run 0\.0 /1k (<= $TL; 0 runs/" "$OUT")"
eq "  recovery is n/a with no sibling PDF" "1" "$(has 'recovery n/a (no sibling PDF)' "$OUT")"

OUT="$(score "$F/joined.md")"; rc=$?
eq "a run-together conversion (joined words) is suspect, exit 3" "3" "$rc"
eq "  the run-together share is the reason, printed with its threshold" "1" "$(has "^suspect .*run-together [1-9][0-9]\.[0-9] % (> $TR" "$OUT")"
eq "  its short-line share is below threshold" "1" "$(has "short-lines 0\.0 % (<= $TS" "$OUT")"

OUT="$(score "$F/clean.md")"; rc=$?
eq "a clean conversion reads clean, exit 0" "0" "$rc"
eq "  the verdict line carries all four measures and the scope" "1" "$(has "^clean .*short-lines 0\.0 % (<= $TS.*run-together 0\.0 % (<= $TR.*long-run 0\.0 /1k (<= $TL.*recovery n/a (no sibling PDF) · scope: pdf (converted_by markitdown)" "$OUT")"
eq "  the summary line names the four derived thresholds and their date" "1" "$(has "^SCORED: 1 file(s) · clean 1 · suspect 0 · scope pdf 1 | other 0 · thresholds short-lines > $TS | run-together > $TR | long-run > $TL | recovery < $TC (derived 2026-09-08" "$OUT")"
CLEAN_TOKENS="$(tokens "$OUT")"
eq "  (arm) the clean file's token count is read for the exclusion legs" "1" "$(printf '%s\n' "$CLEAN_TOKENS" | grep -c '^[1-9][0-9]*$')"

OUT="$(score "$F/cjk.md")"; rc=$?
eq "a non-Latin-majority conversion takes n/a on run-together and says why" "1" "$(has 'run-together n/a (non-Latin-majority text: no inter-word spaces to lose)' "$OUT")"
eq "  and n/a on long-run" "1" "$(has 'long-run n/a (non-Latin-majority text)' "$OUT")"
eq "  and its verdict rests on the other measures (clean, exit 0)" "0-1" "$rc-$(has '^clean ' "$OUT")"

echo '--- the long-run measure (the skill probe (a), register entry H1) ---'
OUT="$(score "$F/runs.md")"; rc=$?
eq "twelve 25-letter runs in 1,100 words: suspect on long-run alone, exit 3" "3-1" "$rc-$(has "^suspect .*long-run 1[0-9]\.[0-9] /1k (> $TL; 12 runs/" "$OUT")"
eq "  while its run-together share stays under threshold (the share alone would miss it)" "1" "$(has "run-together [0-3]\.[0-9] % (<= $TR" "$OUT")"
OUT="$(score "$F/runs-few.md")"; rc=$?
eq "two runs in 110 words: the rate is over threshold but under the ten-run floor, so clean" "0-1" "$rc-$(has "^clean .*long-run [1-9][0-9]\.[0-9] /1k (<= $TL; 2 runs/" "$OUT")"

echo '--- exclusions from the run-together measure (register entry M3) ---'
OUT="$(score "$F/excl-fence-control.md")"; rc=$?
eq "control: 100 CamelCase identifiers in the open fire the run-together share (exit 3)" "3-1" "$rc-$(has "^suspect .*run-together [1-9][0-9]\.[0-9] % (> $TR; 100/" "$OUT")"
OUT="$(score "$F/excl-fence.md")"; rc=$?
eq "the same identifiers inside a fenced code block are excluded: clean, 0 hits" "0-1" "$rc-$(has "^clean .*run-together 0\.0 % (<= $TR; 0/" "$OUT")"
eq "  and excluded from the denominator too (the token count equals the clean file's)" "$CLEAN_TOKENS" "$(tokens "$OUT")"
OUT="$(score "$F/excl-tag.md")"; rc=$?
eq "an angle-bracket tag with a base64 attribute and CamelCase class names is excluded whole; the element's text content is prose and stays (one token, one hit)" "0-$((CLEAN_TOKENS + 1))-1" "$rc-$(tokens "$OUT")-$(has "run-together 0\.[0-9] % (<= $TR; 1/" "$OUT")"
OUT="$(score "$F/excl-blob.md")"; rc=$?
eq "a bare base64-shaped blob is excluded from both sides" "0-$CLEAN_TOKENS" "$rc-$(tokens "$OUT")"
OUT="$(score "$F/digits-prose.md")"; rc=$?
eq "space-stripped prose carrying digits is NOT a blob (it keeps its vowels): still suspect" "3-1" "$rc-$(has "^suspect .*run-together [4-9]\.[0-9] % (> $TR; 20/" "$OUT")"
OUT="$(score "$F/cjk-mixed.md")"; rc=$?
eq "English prose with some 40 % CJK letters is scored on its Latin tokens only: 0.0 %, clean" "0-1" "$rc-$(has "^clean .*run-together 0\.0 % (<= $TR" "$OUT")"

echo '--- scope (derived on PDF conversions of papers) ---'
OUT="$(score "$F/scope-url-pdf.md")"; rc=$?
eq "converted_from: a URL whose path ends in .pdf (query dropped) reads scope: pdf" "1" "$(has 'scope: pdf (converted_from names a PDF)' "$OUT")"
OUT="$(score "$F/scope-web.md")"; rc=$?
eq "a defuddle capture of a web page reads scope: other" "1" "$(has 'scope: other (web capture, converted_by defuddle)' "$OUT")"
OUT="$(score "$F/scope-none.md")"; rc=$?
eq "no provenance and no PDF evidence reads scope: other, and is still scored" "0-1" "$rc-$(has '^clean .*scope: other (no converted_by and no PDF evidence)' "$OUT")"
OUT="$(score "$T/withpdf/good.md")"; rc=$?
eq "a sibling PDF reads scope: pdf" "1" "$(has 'scope: pdf (sibling PDF)' "$OUT")"
OUT="$(score "$F/scope-web.md" "$F/clean.md")"; rc=$?
eq "the summary line tallies the scopes" "1" "$(has '^SCORED: 2 file(s) · clean 2 · suspect 0 · scope pdf 1 | other 1' "$OUT")"

echo '--- recovery against pdftotext ---'
OUT="$(score "$T/withpdf/good.md")"; rc=$?
eq "a conversion holding every pdftotext sentence recovers 1.00 and reads clean" "0-1" "$rc-$(has "^clean .*recovery 1\.00 (>= $TC; 3/3 sentences)" "$OUT")"
OUT="$(score "$T/withpdf/bad.md")"; rc=$?
eq "a conversion holding none of them recovers 0.00 and is suspect on recovery alone" "3-1" "$rc-$(has "^suspect .*run-together 0\.0 % (<= $TR.*recovery 0\.00 (< $TC; 0/3 sentences)" "$OUT")"
OUT="$(score "$T/withpdf/named.md")"; rc=$?
eq "the PDF converted_from: names is used when it exists beside the conversion" "0-1" "$rc-$(has "^clean .*recovery 1\.00 (>= $TC; 3/3 sentences)" "$OUT")"

echo '--- pdftotext optional: absent or failing is n/a, never a premise failure (register entry M6) ---'
OUT="$(env CONVERSION_SCORE_PDFTOTEXT="$T/no-such-binary" "$PY" -B "$SCORE" "$T/withpdf/good.md" 2>"$ERR")"; rc=$?
eq "pdftotext missing while a sibling PDF exists: recovery n/a with the reason, clean, exit 0" "0-1" "$rc-$(has '^clean .*recovery n/a (pdftotext absent)' "$OUT")"
OUT="$(env CONVERSION_SCORE_PDFTOTEXT="$T/no-such-binary" "$PY" -B "$SCORE" "$T/withpdf/bad.md" 2>"$ERR")"; rc=$?
eq "  the verdict then rests on the other three measures (the bad conversion reads clean without recovery)" "0-1" "$rc-$(has '^clean .*recovery n/a (pdftotext absent)' "$OUT")"
eq "  nothing on stderr" "0" "$(wc -c < "$ERR" | tr -d ' ')"
OUT="$(score "$T/withpdf/garbage.md")"; rc=$?
eq "a garbage PDF beside a clean .md: pdftotext fails, recovery n/a with its first stderr line, exit 0" "0-1" "$rc-$(has '^clean .*recovery n/a (pdftotext failed: [A-Za-z][^)]*)' "$OUT")"
OUT="$(score "$T/withpdf")"; rc=$?
eq "  control: the directory run still exits 3 on the bad conversion, with four files scored" "3-1" "$rc-$(has '^SCORED: 4 file(s) · clean 3 · suspect 1' "$OUT")"

echo '--- premise failures ---'
OUT="$(score "$F/empty.md")"; rc=$?
eq "an empty file is a premise failure (exit 2, no stdout, PROBE FAILED on stderr)" "2--1" "$rc-$OUT-$(grep -c 'PROBE FAILED: .*is empty' "$ERR")"
OUT="$(score "$F/fm-only.md")"; rc=$?
eq "a file with frontmatter and no body is a premise failure" "2-1" "$rc-$(grep -c 'PROBE FAILED: .*no body' "$ERR")"
OUT="$(score "$T/nomd")"; rc=$?
eq "a directory with no .md is a premise failure" "2-1" "$rc-$(grep -c 'PROBE FAILED: .*holds no .md file' "$ERR")"
OUT="$(score "$T/absent/none.md")"; rc=$?
eq "an unreadable file is a premise failure" "2-1" "$rc-$(grep -c 'PROBE FAILED: cannot read' "$ERR")"
OUT="$(score --deep "$F/clean.md")"; rc=$?
eq "an unknown flag is refused (exit 2), never read as a file" "2-1" "$rc-$(grep -c 'PROBE FAILED: unknown option' "$ERR")"
OUT="$(score --thresholds 1,2,3 "$F/clean.md")"; rc=$?
eq "a --thresholds with three values is refused (four measures now)" "2-1" "$rc-$(grep -c 'PROBE FAILED: --thresholds wants SHORT,RUN,RECOVERY,LONGRUN' "$ERR")"

echo '--- exit codes over a directory ---'
OUT="$(score "$F/only-good")"; rc=$?
eq "every file clean: exit 0 with the tally" "0-1" "$rc-$(has '^SCORED: 2 file(s) · clean 2 · suspect 0 · scope pdf 2 | other 0' "$OUT")"
OUT="$(score "$F/mixed")"; rc=$?
eq "any file suspect: exit 3 with the tally (6 files, 3 suspect)" "3-1" "$rc-$(has '^SCORED: 6 file(s) · clean 3 · suspect 3' "$OUT")"
eq "  one verdict line per file" "6" "$(has '^\(clean\|suspect\) ' "$OUT")"

echo '--- negative controls: overrides that hide a measure ---'
OUT="$(score --thresholds 100,-,-,- "$F/collapsed.md")"; rc=$?
eq "with the short-line threshold set to 100 % the collapsed fixture reads clean (the measure is what decides)" "0-1" "$rc-$(has '^clean .*short-lines [89][0-9]\.[0-9] % (<= 100 %' "$OUT")"
eq "  the override is recorded on the summary line" "1" "$(has "^SCORED: .*thresholds short-lines > 100 % .*(override '100,-,-,-')" "$OUT")"
OUT="$(score "$F/collapsed.md")"; rc=$?
eq "  restored: the derived thresholds catch it again (exit 3)" "3-1" "$rc-$(has '^suspect ' "$OUT")"
OUT="$(score --thresholds -,-,-,off "$F/runs.md")"; rc=$?
eq "with the long-run measure switched off the SoK-shaped fixture reads clean (the brief's negative control)" "0-1" "$rc-$(has '^clean .*long-run 1[0-9]\.[0-9] /1k (<= n/a' "$OUT")"
OUT="$(score "$F/runs.md")"; rc=$?
eq "  restored: suspect again (exit 3)" "3-1" "$rc-$(has '^suspect ' "$OUT")"
OUT="$(score --thresholds -,-,off,- "$T/withpdf/bad.md")"; rc=$?
eq "a measure switched off ('off') prints n/a as its threshold and no longer decides" "0-1" "$rc-$(has '^clean .*recovery 0\.00 (>= n/a' "$OUT")"

echo '--- distribution and derivation ---'
OUT="$(score --distribution "$F/mixed")"; rc=$?
eq "--distribution prints the percentile table over every .md in the directory, with the scope tally" "0-1" "$rc-$(has '^DISTRIBUTION over .*: 6 files (6 scope pdf, 0 other)' "$OUT")"
eq "  one row per measure with min p10 p25 p50 p75 p90 max" "4" "$(has '^\(short-lines %\|run-together %\|long-run /1k\|recovery\) ' "$OUT")"
eq "  the recovery row states its n/a count" "1" "$(has '^recovery  *2 (4 n/a)' "$OUT")"
printf 'raw/2-papers/collapsed.md\nraw/2-papers/joined.md\nraw/2-papers/bad.md\n' > "$T/positives.txt"
OUT="$(score --derive "$F/mixed" --positives "$T/positives.txt")"; rc=$?
eq "--derive prints ranges, thresholds and the combined precision and recall" "0-1" "$rc-$(has '^combined verdict at these thresholds: suspect 3 · clean 3 · true positives 3 · false positives 0 · false negatives 0 · precision 1\.000 · recall 1\.000' "$OUT")"
eq "  the positives are matched on the basename of a vault-relative path" "1" "$(has '^DERIVATION over .*: 6 files · positives 3 (from ' "$OUT")"
eq "  each of the four measures states the gap its threshold is the midpoint of, or that it does not separate" "4" "$(has '^  \(short-lines %\|run-together %\|long-run /1k\|recovery\) .*\(midpoint of the gap\|does not separate\)' "$OUT")"
eq "  the worst and next-worst clean files are named for every measure with a negative" "4" "$(has '^ *worst clean [^ ]*\.md (' "$OUT")"
eq "  a fixture-derived cut is compared with the baked-in one and the difference is said" "1" "$(has '^baked-in thresholds .*DIFFER FROM the derived' "$OUT")"
printf 'raw/2-papers/no-such-file.md\n' > "$T/positives-bad.txt"
OUT="$(score --derive "$F/mixed" --positives "$T/positives-bad.txt")"; rc=$?
eq "a positive not found in the directory is a premise failure" "2-1" "$rc-$(grep -c 'PROBE FAILED: 1 positive(s) not found' "$ERR")"

echo '--- deciding numbers carry their derivation or the words set by judgement ---'
eq "every judgement constant is labelled (LONG_TOKEN, floor, sentence words, timeout, blob length, blob run)" "6" "$(grep -c '^[A-Z_]* = .*set by judgement, unmeasured' "$SCORE")"
eq "the four thresholds are labelled derived, and the docstring names the derivation corpus and date" "4-1" "$(grep -c '^THRESHOLD_[A-Z_]* = ' "$SCORE")-$(grep -c '^Derived 2026-09-08 on the vault' "$SCORE")"

echo '--- stdout-only proof (must run last) ---'
RO="$T/readonly"; cp -R "$F/mixed" "$RO"; cp "$T/withpdf/garbage.md" "$T/withpdf/garbage.pdf" "$RO/"
BEFORE="$(manifest "$RO")"
chmod -R a-w "$RO"
score "$RO" > /dev/null; r1=$?
score "$RO/good.md" > /dev/null; r2=$?
score --distribution "$RO" > /dev/null; r3=$?
score --derive "$RO" --positives "$T/positives.txt" > /dev/null; r4=$?
score --thresholds 100,-,-,- "$RO/collapsed.md" > /dev/null; r5=$?
env CONVERSION_SCORE_PDFTOTEXT="$T/no-such-binary" "$PY" -B "$SCORE" "$RO/good.md" > /dev/null 2>"$ERR"; r6=$?
chmod -R u+w "$RO"
AFTER="$(manifest "$RO")"
eq "every mode runs against a chmod -R a-w copy (exits 3 0 0 0 0 0)" "3 0 0 0 0 0" "$r1 $r2 $r3 $r4 $r5 $r6"
if [ "$(hashes "$BEFORE")" -ge 10 ] && [ "$BEFORE" = "$AFTER" ]; then ok "the read-only copy's checksum manifest is unchanged after every mode ($(hashes "$BEFORE") files)"
else no "the read-only copy's checksum manifest is unchanged  [$(hashes "$BEFORE") before, $(hashes "$AFTER") after]"; fi
END_H="$(manifest "$HERE")"
if [ "$(hashes "$END_H")" -ge 2 ] && [ "$START_H" = "$END_H" ]; then ok "the script home is byte-identical to its pre-run baseline"
else no "the script home is byte-identical to its pre-run baseline"; fi
# Source grep: every write pattern, each matched on its own control line so a dead pattern
# cannot vouch for the list. The scorer's one subprocess is pdftotext with `-` (stdout) as
# its output argument, asserted separately.
npat(){ pat="$1"; shift; grep -oE -- "$pat" "$@" | wc -l | tr -d ' '; }
CTL="$(printf '%s\n' 'open("x", "w")' 'p.write_text(s)' 'q.write_bytes(b)' 'os.remove(p)' 'os.unlink(p)' \
  'os.rename(a, b)' 'os.replace(a, b)' 'os.mkdir(d)' 'os.rmdir(d)' 'os.makedirs(d)' 'shutil.copy(a, b)' \
  'tempfile.mkdtemp()' 'os.system(c)' 'os.popen(c)' 'print(x, file=open("f", "w"))')"
hits=0; dead=""
for pat in 'open\([^)]*["'"'"'][wax]' 'write_text' 'write_bytes' 'os\.remove' 'os\.unlink' 'os\.rename' \
           'os\.replace' 'os\.mkdir' 'os\.rmdir' 'makedirs' 'shutil\.' 'tempfile' 'os\.system' 'os\.popen' \
           'print\(.*file=open'; do
  hits=$((hits + $(npat "$pat" "$SCORE")))
  if [ "$(printf '%s\n' "$CTL" | npat "$pat" -)" -eq 0 ]; then dead="$dead $pat"; fi
done
if [ -n "$dead" ]; then no "every write pattern matches its own control line  [dead:$dead]"
elif [ "$hits" -eq 0 ]; then ok "no write pattern appears in the scorer's source (15 patterns, each matched on its own control line)"
else no "no write pattern appears in the scorer's source  [$hits hit(s)]"; fi
SUB="$(grep -c 'subprocess\.run(' "$SCORE")"; SUBOUT="$(grep -c 'subprocess\.run(\[exe, "-enc", "UTF-8", pdf, "-"\]' "$SCORE")"
eq "the only subprocess call is pdftotext with stdout as its output" "1-1" "$SUB-$SUBOUT"

N=$((PASS + FAIL))
printf '\n'
if [ "$FAIL" -eq 0 ]; then printf 'PASS %d/%d\n' "$PASS" "$N"; else printf 'FAIL %d/%d\n' "$FAIL" "$N"; fi
[ "$FAIL" -eq 0 ]
