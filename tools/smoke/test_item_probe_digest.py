import unittest
from item_probe_digest import summarize


class ItemProbeDigestTests(unittest.TestCase):
    def test_sample_bounds_and_ranking(self):
        capture = {"phase": "orbit", "start_us": 100, "end_us": 200, "item_probe": [
            {"timestamp_us": 99, "total_us": 10000},
            {"timestamp_us": 150, "total_us": 20, "bounds_us": 10},
            {"timestamp_us": 170, "total_us": 40, "input_reasons": {"thickness": 5}},
            {"timestamp_us": 201, "total_us": 20000}]}
        result = summarize(capture, 1)
        self.assertEqual(result["retained_rows_in_sample"], 2)
        self.assertEqual(result["worst"][0]["timestamp_us"], 170)
        self.assertEqual(result["worst"][0]["input_reasons"], {"thickness": 5})
        self.assertIsNone(result["worst"][0]["selection_reasons"])

    def test_profile_filters_loading_and_export(self):
        capture = {"phase": "orbit", "start_us": 100, "end_us": 200}
        profile = {"native": {"layout_causal_probe": [
            {"timestamp_us": 50, "changed_items": 5000},
            {"timestamp_us": 150, "changed_items": 1400}]},
            "frame_lifecycle": {"cpu_boundary_gaps": {"late_to_pre_draw": [
                {"start_us": 190, "end_us": 210, "wall_ms": 20},
                {"start_us": 150, "end_us": 180, "wall_ms": 30}]}}}
        result = summarize(capture, 2, profile)
        self.assertEqual(result["largest_layout_updates"], [{"timestamp_us": 150, "changed_items": 1400}])
        self.assertEqual(len(result["cpu_boundary_gaps"]["late_to_pre_draw"]), 1)


if __name__ == "__main__":
    unittest.main()
