import json
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path
from hitch_digest import summarize


class HitchDigestTest(unittest.TestCase):
    def test_bounded_ranking_ignores_history_and_partial_tail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hitches.jsonl"
            records = []
            for frame, duration in enumerate((60, 1800, 120)):
                current = {"frame": frame, "start_us": frame * 2000000,
                           "frame_ms": duration, "unattributed_ms": 1,
                           "coarse_stages_ms": {"world_poll": duration - 1},
                           "largest_component": "world_poll"}
                records.append(json.dumps({"frames": [{"frame_ms": 9999}, current],
                                           "hitches": frame + 1}))
            path.write_text("\n".join(records) + '\n{"frames":', encoding="utf-8")
            result = summarize(path, 2)
            self.assertEqual([row["frame_ms"] for row in result["worst"]], [1800, 120])
            self.assertEqual(result["largest_component_counts"], {"world_poll": 3})
            self.assertEqual(result["malformed_or_partial_lines"], 1)
            self.assertEqual(result["last_report_counters"]["hitches"], 3)

    def test_summary_is_not_malformed_or_a_hitch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hitches.jsonl"
            path.write_text(json.dumps({"kind": "presentation_hitch_summary", "frames": [],
                                        "hitches": 7, "peak_frame_us": 1890000}), encoding="utf-8")
            result = summarize(path)
            self.assertEqual(result["reports"], 0)
            self.assertEqual(result["malformed_or_partial_lines"], 0)
            self.assertEqual(result["final_summary"]["hitches"], 7)
            command = subprocess.run([sys.executable, str(Path(__file__).with_name("hitch_digest.py")),
                                      str(path), "--fail-over-ms", "1000"], capture_output=True)
            self.assertEqual(command.returncode, 2, "suppressed peak must fail the regression gate")

    @staticmethod
    def frame(number, duration, phase="viewer"):
        return {"frame": number, "start_us": number * 100000,
                "frame_ms": duration, "phase": phase, "unattributed_ms": 1,
                "coarse_stages_ms": {"items": duration - 1}, "largest_component": "items"}

    def test_pretty_worst_artifact_retains_peak_inside_cooldown(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "worst.json"
            frames = [self.frame(10, 70), self.frame(11, 195), self.frame(12, 95)]
            frames[1]["pre_draw_ms"] = 80
            frames[1]["cpu"] = {"main_cycles": 100, "thread_ms": 2}
            path.write_text(json.dumps({"kind": "presentation_worst_frames", "phase": "viewer",
                "frames": frames, "observed_frames": 1200, "peak_frame_us": 195000}, indent=2))
            result = summarize(path, 2)
            self.assertEqual([r["frame_ms"] for r in result["worst"]], [195, 95])
            self.assertEqual(result["peak_frame_ms"], 195)
            self.assertEqual(result["worst_artifacts"]["viewer"]["observed_frames"], 1200)
            self.assertEqual(result["worst"][0]["lifecycle_and_cpu"]["pre_draw_ms"], 80)
            self.assertEqual(result["worst"][0]["lifecycle_and_cpu"]["cpu"]["thread_ms"], 2)
            self.assertEqual(result["worst"][0]["after_late_ms"], -1)
            self.assertEqual(result["unique_selected_frames"], 3)

    def test_mixed_reports_do_not_count_history_or_duplicate_selected_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mixed.jsonl"
            a, b = self.frame(1, 70), self.frame(2, 195)
            artifact = {"kind": "presentation_worst_frames", "phase": "viewer",
                        "frames": [a, b], "observed_frames": 100, "peak_frame_us": 195000}
            path.write_text("\n".join(map(json.dumps, [
                {"frames": [self.frame(0, 9999), a]}, artifact, artifact])))
            result = summarize(path)
            self.assertEqual(result["unique_selected_frames"], 2)
            self.assertEqual(result["duplicate_frames_ignored"], 3)
            self.assertEqual(result["largest_component_counts"], {"items": 2})
            self.assertEqual(result["peak_frame_ms"], 195)
            self.assertEqual(result["worst_artifacts"]["viewer"]["observed_frames"], 100)

    def test_phase_filter_excludes_init_and_unscoped_global_peak(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mixed.jsonl"
            records = [{"kind": "presentation_worst_frames", "phase": "init",
                        "frames": [self.frame(1, 1800, "init")], "peak_frame_us": 1800000},
                       {"kind": "presentation_worst_frames", "phase": "viewer",
                        "frames": [self.frame(2, 19)], "peak_frame_us": 19000},
                       {"kind": "presentation_hitch_summary", "peak_frame_us": 1800000}]
            path.write_text("\n".join(map(json.dumps, records)))
            result = summarize(path, phase="viewer")
            self.assertEqual(result["peak_frame_ms"], 19)
            self.assertEqual(result["unique_selected_frames"], 1)
            self.assertIsNone(result["final_summary"])
            self.assertEqual(set(result["worst_artifacts"]), {"viewer"})
            command = subprocess.run([sys.executable, str(Path(__file__).with_name("hitch_digest.py")),
                str(path), "--phase", "viewer", "--fail-over-ms", "20"], capture_output=True)
            self.assertEqual(command.returncode, 0)

    def test_missing_lifecycle_is_unknown_not_summed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "worst.json"
            frame = self.frame(1, 30)
            frame["process_to_late_ms"] = 25
            frame["pre_draw_ms"] = 27
            path.write_text(json.dumps({"kind": "presentation_worst_frames", "frames": [frame]}))
            row = summarize(path)["worst"][0]
            self.assertEqual(row["frame_ms"], 30)
            self.assertEqual(row["after_late_ms"], -1)
            self.assertEqual(row["process_to_late_ms"], 25)
            self.assertEqual(row["lifecycle_and_cpu"]["pre_draw_ms"], 27)


if __name__ == "__main__":
    unittest.main()
