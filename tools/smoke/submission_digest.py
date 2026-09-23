"""Bounded summary of engine-input counters from a deep live capture."""
import argparse
import json
from pathlib import Path


def summarize(phases, details=False):
    lines = ["Engine inputs: logical API bytes, not GPU traffic. Allocation requests are separate."]
    for phase in phases[:3]:
        probe = phase.get("engine_submissions", {})
        frames = probe.get("frames", 0)
        if not frames:
            lines.append(f"{phase.get('mode')}: no submission counters")
            continue
        totals = probe["totals"]
        lines.append(f"{phase['mode']}: {frames} frames; retained={probe['retained_frames']}; resets={probe['counter_resets']}")
        for key in ("instance_transform_calls", "instance_custom_calls", "instance_color_calls",
                    "instance_payload_bytes", "instance_allocation_calls", "instance_allocation_requested_bytes",
                    "mesh_surface_calls", "mesh_payload_bytes", "texture_create_calls", "texture_payload_bytes"):
            stats = probe["per_frame"].get(key, {})
            lines.append(f"  {key}: total={totals.get(key, 0)}, mean/frame={totals.get(key, 0) / frames:.1f}, max/frame={stats.get('max', 0)}")
        sources = sorted(((key, value) for key, value in totals.items()
                          if key.endswith("_mesh_payload_bytes")), key=lambda item: item[1], reverse=True)[:3]
        lines.append("  mesh source bytes/frame: " + ", ".join(f"{key.removesuffix('_mesh_payload_bytes')}={value / frames:.1f}" for key, value in sources))
        for row in probe.get("largest_payload_frames", [])[:2]:
            counts = row["counts"]
            size = sum(counts.get(key, 0) for key in ("instance_payload_bytes", "mesh_payload_bytes", "texture_payload_bytes"))
            lines.append(f"  burst draw-frame {row['frame']}: {size} logical bytes")
        if details:
            memory = phase.get("render_memory_endpoint", {})
            lines.append("  Godot allocation MiB: " + ", ".join(f"{key}={memory.get(key, 0) / 1048576:.1f}" for key in ("video_bytes", "texture_bytes", "buffer_bytes")))
            lines.append("  detail drops: " + json.dumps(probe.get("detail_drops", {}), sort_keys=True))
            reason_counts = {key: value for key, value in totals.items() if key.startswith("detail_") and value}
            # A dedicated compact row: fields are scalar counters, not raw events.
            lines.append("  causes: " + json.dumps(reason_counts, sort_keys=True))
            for row in probe.get("largest_payload_frames", [])[:1] + probe.get("slowest_frames", [])[:1]:
                packet = row.get("details", {})
                lines.append(f"  frame {row['frame']}: {row.get('frame_ms', 0):.3f}ms; poll={packet.get('poll')}")
                for entry in packet.get("buildings", [])[:2]:
                    lines.append("    building: " + json.dumps({key: entry.get(key) for key in ("id", "kind", "reason_mask", "payload_bytes", "stream_relation", "elapsed_ms")}, sort_keys=True))
                for entry in packet.get("batches", [])[:2]:
                    lines.append("    batch: " + json.dumps({key: entry.get(key) for key in ("batch_kind", "stage", "source_count", "unchanged_sources", "copied_bytes", "api_payload_bytes", "cancelled")}, sort_keys=True))
    return "\n".join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--details", action="store_true")
    parser.add_argument("--mode", choices=("free", "billboard", "hd2d", "df"))
    args = parser.parse_args()
    phases = json.loads(args.capture.read_text(encoding="utf-8-sig"))
    if args.mode:
        phases = [phase for phase in phases if phase.get("mode") == args.mode]
    print(summarize(phases, args.details))
