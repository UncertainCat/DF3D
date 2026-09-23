"""Compact causal summary of bounded deep item-probe rows within a sample.

Rows are the retained worst updates, not an unbiased frame distribution.
Input reasons may overlap: a slot can change position and thickness together.
"""
import argparse
import json
from pathlib import Path


def summarize(capture, limit=5, profile=None):
    start, end = capture["start_us"], capture["end_us"]
    rows = sorted((row for row in capture.get("item_probe", [])
                   if start <= row["timestamp_us"] <= end),
                  key=lambda row: row["total_us"], reverse=True)
    fields = ("schema_version", "timestamp_us", "total_us", "work", "input_reasons", "selection_reasons",
              "groups", "changed_groups", "prepared_transforms", "prepared_custom", "prepared_colors",
              "resized_groups", "resized_instances", "largest_changed_group",
              "full_manifest", "context_reset", "dependencies", "group_examples", "input_examples")
    selected = []
    for row in rows[:max(1, min(limit, 32))]:
        result = {key: row.get(key) for key in fields}
        result["timings_ms"] = {key: value / 1000 for key, value in row.items()
                                if key.endswith("_us") and key not in ("timestamp_us", "total_us")}
        selected.append(result)
    result = {"phase": capture["phase"], "retained_rows_in_sample": len(rows),
            "meaning": "Worst retained updates only; intrusive deep timings. Reasons overlap.",
            "worst": selected}
    if profile is not None:
        layout = profile.get("native", {}).get("layout_causal_probe", [])
        result["largest_layout_updates"] = sorted(
            (row for row in layout if start <= row["timestamp_us"] <= end),
            key=lambda row: row["changed_items"], reverse=True)[:max(1, min(limit, 32))]
        gaps = profile.get("frame_lifecycle", {}).get("cpu_boundary_gaps", {})
        result["cpu_boundary_gaps"] = {
            name: [row for row in values if start <= row["start_us"] and row["end_us"] <= end][:max(1, min(limit, 32))]
            for name, values in gaps.items()}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture")
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument("--output")
    parser.add_argument("--profile", help="Matching .profile.json for native layout causes and CPU gaps")
    args = parser.parse_args()
    profile = json.loads(Path(args.profile).read_text(encoding="utf-8-sig")) if args.profile else None
    result = summarize(json.loads(Path(args.capture).read_text(encoding="utf-8-sig")), args.top, profile)
    encoded = json.dumps(result, indent=2)
    if args.output:
        Path(args.output).write_text(encoded, encoding="utf-8")
    print(encoded)
