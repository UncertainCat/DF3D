"""Bounded deep-trace digest; elapsed spans are not CPU samples.

Only the latest requested frame intervals belong to the selected capture phase.
Events are indexed against frame windows once; nested spans are never added to
their parents. Optional JSON contains aggregated frame rows, not raw events.
"""
import argparse
from bisect import bisect_right
from collections import defaultdict
import json
from pathlib import Path

COARSE = ("frame_housekeeping", "session_and_controls", "session_attach", "session_detach",
          "not_ready", "world_poll", "view_state", "hd2d_prepare",
          "unit_upload", "projectile_upload", "item_upload", "remaining_main")
LIFECYCLE = ("engine.process_to_pre_draw", "engine.pre_draw_to_process",
             "engine.process_to_late_node", "engine.late_node_to_pre_draw",
             "engine.pre_to_post_draw", "engine.post_to_process")


def union_duration(intervals):
    total, edge = 0.0, float("-inf")
    for start, end in sorted(intervals):
        total += max(0.0, end - max(edge, start))
        edge = max(edge, end)
    return total


def analyze(trace, count=360):
    if count <= 0:
        raise ValueError("frame count must be positive")
    events = trace.get("traceEvents", [])
    frames = sorted((event for event in events
                     if event.get("name") == "frame.interval" and event.get("dur", 0) > 0),
                    key=lambda event: event["ts"])[-count:]
    rows, windows = [], defaultdict(list)
    for frame in frames:
        lo, hi = frame["ts"], frame["ts"] + frame["dur"]
        row = {"timestamp_us": lo, "frame_ms": frame["dur"] / 1000,
               "main_thread": {"pid": frame.get("pid", 1), "tid": frame.get("tid")},
               "native_retention_complete": None, "script_retention_complete": None}
        for category in ("native", "script"):
            watermark = trace.get(category + "_evicted_through_us")
            if watermark is not None:
                row[category + "_retention_complete"] = lo > watermark
        rows.append(row)
        windows[(frame.get("pid", 1), frame.get("tid"))].append((lo, hi, len(rows) - 1))
    # Prefix maximum ends make the index correct even for overlapping windows.
    indexes = {}
    for thread, entries in windows.items():
        ends, edge = [], float("-inf")
        for _, hi, _ in entries:
            edge = max(edge, hi)
            ends.append(edge)
        indexes[thread] = (entries, ends)
    buckets = [defaultdict(list) for _ in rows]
    native = [defaultdict(list) for _ in rows]
    for event in events:
        name = event.get("name", "")
        is_native = event.get("cat") == "native"
        if name not in COARSE and name not in LIFECYCLE and not is_native:
            continue
        if event.get("dur", 0) <= 0 or "ts" not in event:
            continue
        index = indexes.get((event.get("pid", 1), event.get("tid")))
        if index is None:
            continue  # Worker durations cannot explain main-thread CPU work.
        lo, hi = event["ts"], event["ts"] + event["dur"]
        entries, ends = index
        cursor = bisect_right(ends, lo)
        while cursor < len(entries) and entries[cursor][0] < hi:
            start, end, target = entries[cursor]
            overlap = (max(start, lo), min(end, hi))
            if overlap[1] > overlap[0]:
                if name in COARSE or name in LIFECYCLE:
                    buckets[target][name].append(overlap)
                if is_native:
                    native[target][name].append((overlap[1] - overlap[0]) / 1000)
            cursor += 1
    for index, row in enumerate(rows):
        spans = buckets[index]
        row["coarse_ms"] = {name: union_duration(spans[name]) / 1000 for name in COARSE}
        covered = union_duration([interval for name in COARSE for interval in spans[name]]) / 1000
        row["coarse_union_ms"] = covered
        row["outside_coarse_stages_ms"] = max(0.0, row["frame_ms"] - covered)
        row["lifecycle_ms"] = {name: union_duration(spans[name]) / 1000
                               for name in LIFECYCLE if spans[name]}
        row["native_nested_spans"] = {
            name: {"count": len(values), "total_ms": sum(values), "max_ms": max(values)}
            for name, values in native[index].items()}
    return {"schema": 1, "requested_frames": count, "selected_frames": len(rows),
            "retention_metadata": {key: trace[key] for key in (
                "native_evicted_through_us", "script_evicted_through_us", "dropped_events",
                "script_dropped_events", "frame_lifecycle") if key in trace}, "frames": rows}


def retention(value):
    return "unknown" if value is None else ("complete" if value else "incomplete")


def render(result, worst=3):
    rows = result["frames"]
    lines = [f"Deep profile: {len(rows)}/{result['requested_frames']} latest frames.",
             "Elapsed spans, not CPU samples. Outside = frame minus coarse UNION.",
             "Lifecycle and native spans nest/overlap coarse work; do not add them."]
    if not rows:
        return "\n".join(lines + ["No frame.interval events; no frame attribution possible."])
    for category in ("native", "script"):
        states = [retention(row[category + "_retention_complete"]) for row in rows]
        lines.append(f"{category} retention: " + ", ".join(
            f"{state}={states.count(state)}" for state in ("complete", "incomplete", "unknown")))
    lifecycle = result.get("retention_metadata", {}).get("frame_lifecycle")
    if lifecycle:
        lines.append("Lifecycle validation: " + ", ".join(
            f"{name}={lifecycle.get(name, 'unknown')}" for name in
            ("unexpected_boundaries", "foreign_thread_boundaries")))
    # Select a real observed frame, using the lower middle for even counts.
    actual = sorted(rows, key=lambda row: row["frame_ms"])[(len(rows) - 1) // 2]
    selected = [("Actual median representative", actual)]
    ranked = sorted(rows, key=lambda row: row["frame_ms"], reverse=True)
    selected.extend((f"Worst {index + 1}", row) for index, row in enumerate(ranked[:max(0, min(worst, 8))]))
    for label, row in selected:
        lines.extend(["", f"{label}: {row['frame_ms']:.3f} ms at {row['timestamp_us']:.1f} us",
                      f"  Coarse union {row['coarse_union_ms']:.3f}; outside {row['outside_coarse_stages_ms']:.3f} ms; "
                      f"retention native={retention(row['native_retention_complete'])}, script={retention(row['script_retention_complete'])}",
                      "  Coarse ms: " + ", ".join(f"{name}={value:.3f}" for name, value in row["coarse_ms"].items()),
                      "  Lifecycle ms (nested): " + (", ".join(
                          f"{name.removeprefix('engine.')}={value:.3f}" for name, value in row["lifecycle_ms"].items()) or "unavailable")])
        spans = sorted(row["native_nested_spans"].items(), key=lambda item: item[1]["total_ms"], reverse=True)[:3]
        lines.append("  Top native (nested): " + (", ".join(
            f"{name[:72]}={value['total_ms']:.3f} ms/{value['count']} spans" for name, value in spans) or "none retained"))
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--frames", type=int, default=360)
    parser.add_argument("--worst", type=int, default=3, help="worst frames to print (0-8)")
    parser.add_argument("--output", type=Path, help="write all aggregate frame rows as JSON")
    args = parser.parse_args()
    if args.frames <= 0 or not 0 <= args.worst <= 8:
        parser.error("--frames must be positive; --worst must be between 0 and 8")
    with args.trace.open(encoding="utf-8") as stream:
        result = analyze(json.load(stream), args.frames)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(render(result, args.worst))


if __name__ == "__main__":
    main()
