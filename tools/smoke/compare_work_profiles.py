"""Compare deep_profile_live work counts, normalized per 1000 displayed frames.

Counters reveal amplification; elapsed timings alone cannot identify CPU work.
This reports evidence, not a noisy performance pass/fail gate. Deterministic
fixture tests enforce work bounds. Older files require --legacy-frame-count.
"""
import argparse
import json
from pathlib import Path

METRICS = {
    "item delta records": "sprite_delta.item_delta_groups",
    "item full manifest recoveries": "sprite_delta.item_delta_fulls",
    "item sparse input checks": "sprite_delta.item_sparse_checks",
    "item full group input checks": "sprite_delta.item_full_checks",
    "item groups rejected before setup": "sprite_delta.item_group_early_hits",
    "item groups reaching setup": "sprite_delta.item_group_early_misses",
    "unit partition rebuilds": "sprite_delta.unit_partition_rebuilds",
    "unit partition hits": "sprite_delta.unit_partition_hits",
    "unit partition keys built": "sprite_delta.unit_partition_keys_built",
    "item owners": "native_delta.item_records_updated",
    "building builds": "native_delta.building_geometry_builds",
    "duplicate building builds": "native_delta.building_duplicate_builds",
    "visibility blocks observed": "native_delta.visibility_blocks_observed",
    "visibility blocks unchanged": "native_delta.visibility_blocks_unchanged",
    "layout contributors": "native_delta.tile_layout_contributors",
    "building batch completions": "batch_delta.buildings.builds",
    "building batch cancellations": "batch_delta.buildings.cancellations",
    "building source restore checks": "batch_delta.buildings.restore_checks",
    "building sources gathered": "batch_delta.buildings.gathered_sources",
    "building vertices gathered": "batch_delta.buildings.gathered_vertices",
    "building surfaces uploaded": "batch_delta.buildings.uploaded_surfaces",
    "building deferrals": "batch_delta.buildings.deferrals",
    "building rejoins": "batch_delta.buildings.rejoins",
}


def read_metric(phase, path):
    value = phase
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def normalize(phase, legacy_frames=None):
    frames = phase.get("frames", legacy_frames)
    if not isinstance(frames, int) or frames <= 0:
        raise ValueError("positive frame count required (legacy files: --legacy-frame-count)")
    result = {}
    for label, path in METRICS.items():
        value = read_metric(phase, path)
        if value is not None:
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
                raise ValueError(f"invalid cumulative counter delta: {path}")
            result[label] = value * 1000 / frames
    return result


def compare(before, after, legacy_frames=None):
    # A mode identifies one phase in this runner. Never silently overwrite phases.
    def index(phases):
        result = {}
        for phase in phases:
            mode = phase["mode"]
            if mode in result:
                raise ValueError(f"duplicate phase mode: {mode}")
            result[mode] = normalize(phase, legacy_frames)
        return result
    old, new = index(before), index(after)
    lines = ["Work per 1000 displayed frames; separate evolving runs, not identical simulation ticks.",
             "", "| Mode | Work | Before | After |", "| --- | --- | ---: | ---: |"]
    for mode in sorted(old.keys() | new.keys()):
        for metric in METRICS:
            values = [data.get(mode, {}).get(metric) for data in (old, new)]
            if all(value is None for value in values):
                continue
            formatted = ["unavailable" if value is None else f"{value:,.1f}" for value in values]
            lines.append(f"| {mode} | {metric} | {formatted[0]} | {formatted[1]} |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--legacy-frame-count", type=int)
    args = parser.parse_args()
    print(compare(json.loads(args.before.read_text()), json.loads(args.after.read_text()),
                  args.legacy_frame_count), end="")
