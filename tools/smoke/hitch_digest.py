"""Compact digest of hitch JSONL or bounded presentation_worst_frames JSON."""
import argparse
import collections
import json
import itertools
from pathlib import Path


def records(path):
    """Stream JSONL; bounded pretty-printed artifacts are a single document."""
    with Path(path).open(encoding="utf-8-sig") as stream:
        first = stream.readline()
        if first.strip() == "{":
            try:
                yield json.loads(first + stream.read())
            except (ValueError, TypeError):
                yield None
            return
        for line in itertools.chain([first], stream):
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except (ValueError, TypeError):
                yield None


def compact_frame(frame, phase):
    row = {key: frame.get(key) for key in
           ("frame", "start_us", "frame_ms", "unattributed_ms")}
    row["largest_component"] = frame.get("largest_component", "unknown")
    row["phase"] = phase
    # Missing lifecycle evidence is unknown, never a zero-duration measurement.
    row["process_to_late_ms"] = frame.get("process_to_late_ms", -1)
    row["after_late_ms"] = frame.get("after_late_ms", -1)
    row["instance_work"] = {key: frame.get(key) for key in
                            ("instance_allocations", "transform_writes", "custom_writes",
                             "item_allocations", "item_transform_writes", "item_custom_writes")}
    stages = frame.get("coarse_stages_ms", {})
    row["top_stages_ms"] = dict(sorted(stages.items(), key=lambda pair: pair[1], reverse=True)[:4])
    timing = {}
    for key, value in frame.items():
        if key in row or key in ("end_us", "coarse_stages_ms"):
            continue
        if key in ("lifecycle", "lifecycle_ms", "cpu", "cpu_boundaries") and isinstance(value, dict):
            timing[key] = dict(list(value.items())[:24])
        elif isinstance(value, (int, float)) and (key.endswith(("_ms", "_us", "_cycles")) or "cpu" in key):
            timing[key] = value
    if timing:
        row["lifecycle_and_cpu"] = dict(list(timing.items())[:24])
    return row


def summarize(path, limit=10, phase=None):
    worst = []
    counts = collections.Counter()
    reports = malformed = duplicates = selected = 0
    latest = {}
    final_summary = None
    artifacts = {}
    seen = set()
    for report in records(path):
        if not isinstance(report, dict):
            malformed += 1
            continue
        kind = report.get("kind")
        report_phase = report.get("phase", "unlabeled")
        if kind == "presentation_hitch_summary":
            if phase is None or phase == report_phase:
                final_summary = report
            continue
        frames = report.get("frames")
        if not isinstance(frames, list) or (not frames and kind != "presentation_worst_frames"):
            malformed += 1
            continue
        is_worst = kind == "presentation_worst_frames"
        if is_worst and (phase is None or phase == report_phase):
            metadata = artifacts.setdefault(report_phase, {"observed_frames": 0, "peak_frame_us": 0})
            for key in metadata:
                metadata[key] = max(metadata[key], report.get(key, 0))
        candidates = frames if is_worst else frames[-1:]
        accepted = False
        for frame in candidates:
            if not isinstance(frame, dict) or not isinstance(frame.get("frame_ms"), (int, float)):
                malformed += 1
                continue
            frame_phase = frame.get("phase", report_phase)
            if phase is not None and phase != frame_phase:
                continue
            accepted = True
            # History is ignored for rate-limited reports. Repeated selected frames
            # are counted once if a worst artifact and a report share a JSONL file.
            identity = (frame_phase, frame.get("frame"), frame.get("start_us"))
            if identity[1:] != (None, None):
                if identity in seen:
                    duplicates += 1
                    continue
                seen.add(identity)
            selected += 1
            component = frame.get("largest_component", "unknown")
            counts[component] += 1
            worst.append(compact_frame(frame, frame_phase))
            worst.sort(key=lambda value: value["frame_ms"], reverse=True)
            del worst[limit:]
        if accepted or (is_worst and (phase is None or phase == report_phase)):
            reports += 1
            if not is_worst:
                latest = {key: report.get(key, 0) for key in
                          ("hitches", "suppressed", "dropped_reports", "invalid_intervals")}
    peak = max((row["frame_ms"] for row in worst), default=0)
    for metadata in artifacts.values():
        peak = max(peak, metadata["peak_frame_us"] / 1000)
    if final_summary:
        peak = max(peak, final_summary.get("peak_frame_us", 0) / 1000)
    return {"reports": reports, "unique_selected_frames": selected,
            "duplicate_frames_ignored": duplicates, "phase_filter": phase,
            "malformed_or_partial_lines": malformed, "last_report_counters": latest,
            "largest_component_counts": dict(counts), "final_summary": final_summary,
            "worst_artifacts": artifacts, "peak_frame_ms": peak, "worst": worst,
            "meaning": "Selected worst frames or rate-limited hitch triggers, not all-frame percentiles. Lifecycle fields may overlap and are not summed. Missing boundaries are unknown; unattributed is not GPU time."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--phase", help="Exact phase name; excludes unscoped summary peaks")
    parser.add_argument("--output")
    parser.add_argument("--fail-over-ms", type=float, default=0,
                        help="Opt-in regression gate on selected phase peak; exit 2 when exceeded")
    args = parser.parse_args()
    result = summarize(args.path, max(1, min(args.top, 100)), args.phase)
    encoded = json.dumps(result, indent=2)
    if args.output:
        Path(args.output).write_text(encoded, encoding="utf-8")
    print(encoded)
    if args.fail_over_ms and result["peak_frame_ms"] > args.fail_over_ms:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
