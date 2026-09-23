import unittest
from compare_sync_profiles import compare


class SyncComparisonTests(unittest.TestCase):
    def test_separates_barrier_wall_from_cpu_and_preserves_unknown(self):
        before = [{'mode': 'free', 'stages': {'engine.late_node_to_pre_draw': {'mean': 7}}}]
        after = [{'mode': 'free', 'stages': {'engine.late_node_to_pre_draw': {'mean': 8}},
                  'lifecycle_delta': {'sync_probe': {'calls': 10, 'wall_ms': 70,
                      'main_cpu_ms': 1, 'main_cpu_samples': 10, 'render_cpu_ms': 0,
                      'render_cpu_samples': 0, 'distinct_render_thread_samples': 10}}}]
        row = compare(before, after)[0]
        self.assertEqual(row['sync_wall_ms'], 7)
        self.assertEqual(row['late_minus_sync_ms'], 1)
        self.assertEqual(row['sync_main_cpu_ms'], .1)
        self.assertIsNone(row['render_interval_cpu_ms'])
        after[0]['lifecycle_delta']['sync_probe']['calls'] = 0
        with self.assertRaises(ValueError): compare(before, after)


if __name__ == '__main__': unittest.main()
