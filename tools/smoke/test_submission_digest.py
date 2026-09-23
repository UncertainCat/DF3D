import unittest
from submission_digest import summarize


class SubmissionDigestTests(unittest.TestCase):
    def test_missing_and_bounded(self):
        self.assertIn("no submission counters", summarize([{"mode": "old"}]))
        probe = {"frames": 2, "retained_frames": 2, "counter_resets": 0,
                 "totals": {"mesh_payload_bytes": 100},
                 "per_frame": {"mesh_payload_bytes": {"max": 100}},
                 "largest_payload_frames": [{"frame": 10, "counts": {
                     "mesh_payload_bytes": 100, "terrain_mesh_payload_bytes": 100}}] * 8}
        output = summarize([{"mode": "free", "engine_submissions": probe}] * 16)
        self.assertIn("total=100, mean/frame=50.0, max/frame=100", output)
        self.assertIn("100 logical bytes", output)
        self.assertEqual(output.count("burst draw-frame"), 6)
        self.assertLess(len(output.splitlines()), 45)

    def test_detail_view_bounds_events(self):
        row = {"frame": 7, "frame_ms": 12.5, "counts": {}, "details": {
            "poll": 55, "buildings": [{"id": 123}] * 16, "batches": [{"source_count": 77}] * 8}}
        probe = {"frames": 1, "retained_frames": 1, "counter_resets": 0, "totals": {},
                 "per_frame": {}, "largest_payload_frames": [row], "slowest_frames": [row]}
        result = summarize([{"mode": "free", "engine_submissions": probe}], details=True)
        self.assertEqual(result.count('"id": 123'), 4)
        self.assertEqual(result.count('"source_count": 77'), 4)
        self.assertIn("poll=55", result)
        self.assertLess(len(result.splitlines()), 30)


if __name__ == "__main__":
    unittest.main()
