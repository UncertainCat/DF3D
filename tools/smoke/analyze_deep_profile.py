"""Correlate the latest capture phase's frame intervals and native spans.

Usage: python tools/smoke/analyze_deep_profile.py TRACE --frames 360
Durations are elapsed time, not CPU samples. Nested native totals overlap.
"""
import argparse
import collections
import json
from pathlib import Path


def analyze(path, count):
    trace = json.loads(path.read_text(encoding="utf-8"))
    events = trace["traceEvents"]
    # Script and native rings retain different windows. A later mode export can
    # retain earlier mode intervals; select only the latest phase explicitly.
    frames = sorted((e for e in events if e["name"] == "frame.interval"),
                    key=lambda e: e["ts"])[-count:]
    coarse = {"session_and_controls", "world_poll", "view_state",
              "hd2d_prepare", "unit_upload", "item_upload", "remaining_main"}
    results = []
    for frame in frames:
        lo, hi = frame["ts"], frame["ts"] + frame["dur"]
        spans = collections.defaultdict(list)
        coverage = []
        for event in events:
            if event.get("tid") != frame["tid"]:
                continue
            start, end = event["ts"], event["ts"] + event.get("dur", 0)
            if end <= lo or start >= hi:
                continue
            if event["name"] in coarse:
                coverage.append((max(lo, start), min(hi, end)))
            if event.get("cat") == "native":
                spans[event["name"]].append((min(hi, end) - max(lo, start)) / 1000)
        # Union rather than summing possibly overlapping measured intervals.
        covered, edge = 0, lo
        for start, end in sorted(coverage):
            covered += max(0, end - max(edge, start))
            edge = max(edge, end)
        results.append({"timestamp_us": lo, "frame_ms": frame["dur"] / 1000,
                        "native_retention_complete": (lo > trace["native_evicted_through_us"]
                            if "native_evicted_through_us" in trace else None),
                        "script_retention_complete": (lo > trace["script_evicted_through_us"]
                            if "script_evicted_through_us" in trace else None),
                        "outside_coarse_stages_ms": (frame["dur"] - covered) / 1000,
                        "native_nested_spans": {
                            name: {"count": len(values), "total_ms": sum(values),
                                   "max_ms": max(values)}
                            for name, values in spans.items()}})
    return sorted(results, key=lambda frame: frame["frame_ms"], reverse=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--frames", type=int, default=360)
    args = parser.parse_args()
    if args.frames <= 0:
        parser.error("--frames must be positive")
    print(json.dumps(analyze(args.trace, args.frames), indent=2))
