#!/usr/bin/env python3
"""spawn-record-review.py — deep-lint Step 2's spawn-record review (2026-09-06).

Carries two guards from one read of the spawn records, and never calls the meter:
  the instrument rule's over-calling guard — every lane-open line carries its reason letter
  (a)–(d), and a run's lane count never exceeds its reason tally; and the per-call model and
  effort rule's pick guard — a pick below the lane's recorded row default carries its reason
  (`<model> because …`, `effort <x> because …`) unless the active throttle floored that axis; and,
  from 2026-09-08, the `auto` pick guard — under the `auto` throttle (the owner's ruling of
  2026-09-07 17:0x: the row default is an anchor and the head picks per call) a departure from
  `row_default` on either axis in either direction carries its reason, `model_src`/`effort_src`
  reading `auto: <text>` or a non-empty `choice_reason`; a departure with neither is the finding
  `auto pick without --choice-reason`. A line without `model_src` (every record before 2026-09-08)
  keeps the phrase check whatever its throttle; a hand-set preset keeps it too.

Inputs: the records directory (`~/.llm-wiki/spawn-records/*.jsonl`), `routing.json`, and the
log (for the window: records whose run-open is on or after the last `deep-lint |` entry's date;
no such entry → every record, said once). Baselines come from each line's `row_default` field
(written by lane.py and by the head from 2026-09-06); an older line is re-resolved from today's
routing.json and labelled "re-resolved". The phrase checks apply from RULE_FROM, the ship instant
carried by the ship's `framework` log entry title; the letter check from LETTER_FROM, the
instrument rule's date. Premise failures print one `PROBE FAILED: …` line and exit 2, never a
clean report. Report-only: this script writes nothing.
"""
import argparse, glob, io, json, os, re, sys
from datetime import datetime, timezone, timedelta

RULE_FROM = "2026-09-06T18:22+0100"    # the ship instant; the suite asserts it equals the ship entry's title time
LETTER_FROM = "2026-09-04T00:00+0100"  # the instrument rule's date (delegate §1, 2026-09-04)
FLOOR_MODEL = {"cheap", "cheap-fast"}
FLOOR_EFFORT = {"fast", "cheap-fast"}
LETTER_RE = re.compile(r"\(([a-d])\)")

def die(msg):
    print("PROBE FAILED: " + msg); sys.exit(2)

def parse_ts(s):
    if not s or not isinstance(s, str): return None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            d = datetime.strptime(s, fmt)
            if d.tzinfo is None: d = d.replace(tzinfo=timezone(timedelta(hours=1)))
            return d
        except ValueError: pass
    return None

def tier_word(v, order):
    if isinstance(v, list): v = v[0] if v else None
    if not isinstance(v, str): return None
    w = v.strip().split(" ")[0].strip("(,;:")
    return w if w in order else None

def window_start(log_path):
    if not os.path.isfile(log_path): return None, "log absent: the whole history is the window"
    last = None
    for line in io.open(log_path, encoding="utf-8", errors="replace"):
        m = re.match(r"## \[(\d{4}-\d{2}-\d{2})\] deep-lint \|", line)
        if m: last = m.group(1)
    if last is None: return None, "no deep-lint entry in the log: the whole history is the window"
    return parse_ts(last + "T00:00+0100"), None

def resolve(routing, cls, throttle, headless):
    """Re-resolve a row's tier under a throttle, as throttle.py's table and (from 2026-09-06)
    lane.py both do; `headless` is kept for the label only. `auto` (2026-09-08) and `default`
    both resolve to the row defaults — under `auto` they are the anchors the head picks around."""
    order = routing["order"]; row = routing["classes"][cls]
    def strongest(axis): return max(row[axis]["options"], key=lambda o: order[axis].index(o))
    def weakest(axis): return min(row[axis]["options"], key=lambda o: order[axis].index(o))
    m, e = row["model"]["default"], row["effort"]["default"]
    if throttle in ("auto", "default"): pass   # the row defaults, explicitly: the anchors under `auto`
    elif throttle == "top": m, e = strongest("model"), strongest("effort")
    elif throttle == "cheap": m, e = weakest("model"), strongest("effort")   # both paths since the lane.py fix of 2026-09-06
    elif throttle == "fast": e = weakest("effort")
    elif throttle == "cheap-fast": m, e = weakest("model"), weakest("effort")
    return {"model": m, "effort": e}

def main():
    ap = argparse.ArgumentParser(description="deep-lint Step 2: spawn-record review (report-only)")
    ap.add_argument("--records", default=os.path.expanduser("~/.llm-wiki/spawn-records"))
    ap.add_argument("--routing", default=os.path.join(os.getcwd(), ".claude/skills/delegate/routing.json"))
    ap.add_argument("--log", default=os.path.join(os.getcwd(), "wiki/log.md"))
    ap.add_argument("--since", help="ISO instant overriding the log-derived window start")
    ap.add_argument("--rule-from", default=RULE_FROM); ap.add_argument("--letter-from", default=LETTER_FROM)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.records): die("records directory %s is missing" % a.records)
    try: routing = json.load(io.open(a.routing, encoding="utf-8")); order = routing["order"]; classes = routing["classes"]
    except Exception as e: die("routing record unreadable: %s" % e)
    rule_from = parse_ts(a.rule_from); letter_from = parse_ts(a.letter_from)
    if rule_from is None or letter_from is None: die("RULE_FROM or LETTER_FROM does not parse")
    since, note = (parse_ts(a.since), None) if a.since else window_start(a.log)
    if a.since and since is None: die("--since does not parse")
    files = sorted(glob.glob(os.path.join(a.records, "*.jsonl")))
    out = {"files": len(files), "window_start": since.isoformat() if since else None, "note": note,
           "runs": [], "totals": {"runs": 0, "lanes": 0, "findings": 0, "no_run_open": 0, "bad_lines": 0}}
    for f in files:
        evs, bad = [], 0
        for line in io.open(f, encoding="utf-8", errors="replace"):
            line = line.strip()
            if not line: continue
            try: evs.append(json.loads(line))
            except ValueError: bad += 1
        out["totals"]["bad_lines"] += bad
        ro = next((e for e in evs if e.get("event") == "run-open"), None)
        if ro is None:
            out["totals"]["no_run_open"] += 1; out["runs"].append({"file": os.path.basename(f), "skipped": "no run-open", "bad_lines": bad}); continue
        ro_ts = parse_ts(ro.get("ts")); last_ts = max([parse_ts(e.get("ts")) for e in evs if parse_ts(e.get("ts"))] or [None], default=None)
        if since and ro_ts and ro_ts < since and not (last_ts and last_ts >= since): continue
        run = {"run": ro.get("run") or os.path.basename(f), "resumed": bool(since and ro_ts and ro_ts < since), "bad_lines": bad,
               "lanes": 0, "letters": {}, "findings": [], "notes": [], "throttle_unrecorded": 0}
        opens = [e for e in evs if e.get("event") == "lane-open"]
        closes = {}
        for e in evs:
            if e.get("event") == "lane-closed": closes[e.get("lane")] = e   # the last close wins
        for e in opens:
            run["lanes"] += 1; lane = e.get("lane", "?"); reason = e.get("reason") or ""
            opened = parse_ts(e.get("ts"))
            if opened is None: run["findings"].append("%s: unparsed ts %r" % (lane, e.get("ts"))); continue
            m = LETTER_RE.search(reason)
            if m: run["letters"][m.group(1)] = run["letters"].get(m.group(1), 0) + 1
            elif opened >= letter_from: run["findings"].append("%s: no instrument-rule letter in reason" % lane)
            cls = e.get("class") or e.get("agent")
            if cls not in classes: run["notes"].append("%s: unknown class %r" % (lane, cls)); continue
            thr = e.get("throttle")
            if thr is None: run["throttle_unrecorded"] += 1; thr = "default"
            headless = "definition_sha256" in e
            rd = e.get("row_default")
            if not isinstance(rd, dict): rd = resolve(routing, cls, thr, headless); run["notes"].append("%s: re-resolved (no row_default)" % lane)
            model = tier_word(e.get("model"), order["model"]); effort = tier_word(e.get("effort"), order["effort"])
            if model is None: run["notes"].append("%s: unparsed model %r" % (lane, e.get("model")))
            if effort is None: run["notes"].append("%s: unparsed effort %r" % (lane, e.get("effort")))
            if e.get("outside_options") or (model and model not in classes[cls]["model"]["options"]): run["notes"].append("%s: outside the set" % lane)
            row = classes[cls]; rk = lambda axis, v: order[axis].index(v)
            # The `auto` pick guard (2026-09-08) applies to a line that carries the pick fields lane.py
            # writes from that date; an older line, whatever its throttle, keeps the phrase check below.
            recorded_pick = isinstance(e.get("model_src"), str)
            if thr == "auto" and recorded_pick and opened >= rule_from:
                choice = e.get("choice_reason"); choice = choice.strip() if isinstance(choice, str) else ""
                for axis, value in (("model", model), ("effort", effort)):
                    anchor = rd.get(axis) if isinstance(rd, dict) else None
                    if not value or value not in order[axis] or anchor not in order[axis] or value == anchor: continue
                    src = e.get("%s_src" % axis)
                    if not ((isinstance(src, str) and src.startswith("auto:")) or choice):
                        run["findings"].append("%s: auto pick without --choice-reason (%s %s departs from the anchor %s)" % (lane, axis, value, anchor))
            if opened >= rule_from and model and not (thr == "auto" and recorded_pick):
                if thr in FLOOR_MODEL:
                    floor = min(row["model"]["options"], key=lambda o: rk("model", o))
                    if rk("model", model) > rk("model", floor): run["findings"].append("%s: pick above the owner's floor (model %s under %s)" % (lane, model, thr))
                elif thr == "top":
                    ceil = max(row["model"]["options"], key=lambda o: rk("model", o))
                    if rk("model", model) < rk("model", ceil): run["findings"].append("%s: model %s below the ceiling under top" % (lane, model))
                elif rk("model", model) < rk("model", rd["model"]) and ("%s because" % model) not in reason:
                    run["findings"].append("%s: model %s below the row default %s without '%s because'" % (lane, model, rd["model"], model))
            if opened >= rule_from and effort and not (thr == "auto" and recorded_pick):
                if thr in FLOOR_EFFORT:
                    floor = min(row["effort"]["options"], key=lambda o: rk("effort", o))
                    if rk("effort", effort) > rk("effort", floor): run["findings"].append("%s: effort above the owner's floor (%s under %s)" % (lane, effort, thr))
                elif thr == "top":
                    ceil = max(row["effort"]["options"], key=lambda o: rk("effort", o))
                    if rk("effort", effort) < rk("effort", ceil): run["findings"].append("%s: effort %s below the ceiling under top" % (lane, effort))
                elif rk("effort", effort) < rk("effort", rd["effort"]) and ("effort %s because" % effort) not in reason:
                    run["findings"].append("%s: effort %s below the row default %s without 'effort %s because'" % (lane, effort, rd["effort"], effort))
            c = closes.get(lane)
            if c is None: run["notes"].append("%s: unclosed" % lane)
            else:
                applied = tier_word(c.get("effort_applied"), order["effort"])
                if c.get("effort_applied") in (None, []): run["notes"].append("%s: applied effort unread" % lane)
                elif effort and applied and applied != effort: run["findings"].append("%s: effort %s recorded, %s applied" % (lane, effort, applied))
        tally = sum(run["letters"].values())
        if run["lanes"] > tally and opens: run["notes"].append("lane count %d exceeds reason tally %d" % (run["lanes"], tally))
        out["totals"]["runs"] += 1; out["totals"]["lanes"] += run["lanes"]; out["totals"]["findings"] += len(run["findings"])
        out["runs"].append(run)
    if a.json: print(json.dumps(out, ensure_ascii=False, indent=1)); return
    t = out["totals"]
    print("spawn-record review: %d files · window from %s%s · %d runs · %d lanes · %d findings · %d files without run-open · %d bad lines"
          % (out["files"], out["window_start"] or "the start", (" (%s)" % note) if note else "", t["runs"], t["lanes"], t["findings"], t["no_run_open"], t["bad_lines"]))
    if t["lanes"] == 0: print("no lanes this window (control: %d record files read)" % out["files"])
    for r in out["runs"]:
        if r.get("skipped"): print("  %s: skipped (%s, %d bad lines)" % (r["file"], r["skipped"], r["bad_lines"])); continue
        print("  %s%s: %d lanes · letters %s%s" % (r["run"], " (resumed, re-reviewed)" if r["resumed"] else "", r["lanes"],
              json.dumps(r["letters"], sort_keys=True), (" · throttle unrecorded on %d" % r["throttle_unrecorded"]) if r["throttle_unrecorded"] else ""))
        for x in r["findings"]: print("    FINDING " + x)
        for x in r["notes"]: print("    note " + x)

if __name__ == "__main__":
    main()
