import unittest

from profile_digest import analyze, render


def event(name, start, duration, tid=1, category="script", pid=1):
    return {"name": name, "ts": start, "dur": duration, "tid": tid,
            "pid": pid, "cat": category, "ph": "X"}


class ProfileDigestTests(unittest.TestCase):
    def test_clips_nested_coarse_and_excludes_workers(self):
        result = analyze({"traceEvents": [
            event("frame.interval", 100, 1000),
            event("world_poll", 0, 600), event("unit_upload", 400, 500),
            event("items.update", 900, 500, category="native"),
            event("worker.ingest", 100, 1000, tid=2, category="native"),
            event("other.process", 100, 1000, pid=2, category="native")]})
        row = result["frames"][0]
        self.assertAlmostEqual(row["coarse_union_ms"], .8)
        self.assertAlmostEqual(row["outside_coarse_stages_ms"], .2)
        self.assertAlmostEqual(row["native_nested_spans"]["items.update"]["total_ms"], .2)
        self.assertEqual(len(row["native_nested_spans"]), 1)

    def test_lifecycle_separate_from_coarse_and_nested_native(self):
        row = analyze({"traceEvents": [
            event("frame.interval", 100, 1000),
            event("world_poll", 100, 200),
            event("world.poll", 100, 200, category="native"),
            event("items.update", 150, 100, category="native"),
            event("engine.process_to_pre_draw", 100, 700),
            event("engine.pre_to_post_draw", 800, 200),
            event("engine.post_to_process", 1000, 200)]})["frames"][0]
        self.assertAlmostEqual(row["outside_coarse_stages_ms"], .8)
        self.assertEqual(row["lifecycle_ms"], {"engine.process_to_pre_draw": .7,
                         "engine.pre_to_post_draw": .2, "engine.post_to_process": .1})
        self.assertEqual(len(row["native_nested_spans"]), 2)

    def test_retention_missing_and_incomplete_are_not_complete(self):
        frames = [event("frame.interval", 100, 100), event("frame.interval", 200, 100)]
        unknown = analyze({"traceEvents": frames})["frames"][0]
        self.assertIsNone(unknown["native_retention_complete"])
        rows = analyze({"traceEvents": frames, "native_evicted_through_us": 150,
                        "script_evicted_through_us": 0})["frames"]
        self.assertEqual([row["native_retention_complete"] for row in rows], [False, True])
        self.assertTrue(all(row["script_retention_complete"] for row in rows))
        self.assertIn("Lifecycle ms (nested): unavailable", render({"frames": rows, "requested_frames": 2}))

    def test_latest_phase_actual_median_and_bounded_output(self):
        frames = [event("frame.interval", index * 10000 + 1, index + 1) for index in range(1000)]
        result = analyze({"traceEvents": frames}, 360)
        self.assertEqual(result["selected_frames"], 360)
        self.assertEqual(result["frames"][0]["frame_ms"], .641)
        text = render(result, 100000)
        self.assertLessEqual(len(text.splitlines()), 80)
        self.assertIn("Actual median representative: 0.820 ms", text)
        self.assertNotIn("traceEvents", text)
        self.assertNotIn("Worst 9", text)

    def test_spans_can_cross_multiple_and_overlapping_frame_windows(self):
        rows = analyze({"traceEvents": [event("frame.interval", 100, 300),
                       event("frame.interval", 200, 100), event("frame.interval", 400, 100),
                       event("world_poll", 250, 200)]})["frames"]
        self.assertEqual([row["coarse_union_ms"] for row in rows], [.15, .05, .05])

    def test_empty_and_invalid_frame_selection(self):
        self.assertIn("No frame.interval", render(analyze({"traceEvents": []})))
        with self.assertRaises(ValueError):
            analyze({}, 0)


if __name__ == "__main__":
    unittest.main()
