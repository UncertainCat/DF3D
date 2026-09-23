import json
from pathlib import Path
import tempfile
import unittest
from analyze_deep_profile import analyze


class TraceAnalysisTests(unittest.TestCase):
    def test_overlap_and_retention_are_explicit(self):
        trace = {"native_evicted_through_us": 200, "script_evicted_through_us": 0,
                 "traceEvents": [
                     {"name": "frame.interval", "ts": 100, "dur": 1000, "tid": 1},
                     {"name": "world_poll", "ts": 100, "dur": 700, "tid": 1},
                     {"name": "unit_upload", "ts": 500, "dur": 400, "tid": 1},
                     {"name": "worker.ingest", "ts": 100, "dur": 1000, "tid": 2, "cat": "native"}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "trace.json"
            path.write_text(json.dumps(trace))
            row = analyze(path, 1)[0]
        self.assertAlmostEqual(row["outside_coarse_stages_ms"], 0.2)
        self.assertFalse(row["native_retention_complete"])
        self.assertTrue(row["script_retention_complete"])
        self.assertEqual(row["native_nested_spans"], {})


if __name__ == "__main__":
    unittest.main()
