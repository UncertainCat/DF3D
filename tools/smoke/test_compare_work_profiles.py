import unittest
from compare_work_profiles import compare, normalize


class WorkProfileTests(unittest.TestCase):
    def test_normalizes_actual_frame_counts(self):
        a = {"mode": "free", "frames": 100, "native_delta": {"item_records_updated": 20}}
        b = {"mode": "free", "frames": 200, "native_delta": {"item_records_updated": 40}}
        self.assertEqual(normalize(a), normalize(b))
        self.assertIn("| free | item owners | 200.0 | 200.0 |", compare([a], [b]))

    def test_missing_is_not_zero_and_invalid_counts_fail(self):
        phase = {"mode": "free", "frames": 100, "native_delta": {"item_records_updated": 0}}
        self.assertIn("unavailable | 0.0", compare([], [phase]))
        for phase in ({"frames": 0}, {}, {"frames": 1, "native_delta": {"item_records_updated": -1}}):
            with self.assertRaises(ValueError):
                normalize(phase)
        self.assertEqual(normalize({}, 360), {})
        with self.assertRaises(ValueError):
            compare([{"mode": "free", "frames": 1}] * 2, [])


if __name__ == "__main__":
    unittest.main()
