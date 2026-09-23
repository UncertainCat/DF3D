"""Compact comparison of control and explicit rendering-barrier experiments.

CPU accounting is coarse; compare phase averages, not individual frame samples.
Render CPU covers whole checkpoint intervals, not only time inside the barrier.
"""
import argparse
import json
from pathlib import Path


def compare(control, experiment):
    old = {p['mode']: p for p in control}
    rows = []
    for phase in experiment:
        mode = phase['mode']
        sync = phase['lifecycle_delta']['sync_probe']
        if sync['calls'] <= 0:
            raise ValueError('Experiment contains no explicit sync calls')
        def average(total, count):
            return sync[total] / sync[count] if sync[count] > 0 else None
        before = old[mode]['stages']['engine.late_node_to_pre_draw']['mean']
        after = phase['stages']['engine.late_node_to_pre_draw']['mean']
        wall = average('wall_ms', 'calls')
        rows.append({'mode': mode, 'control_late_ms': before, 'probe_late_ms': after,
                     'sync_wall_ms': wall, 'late_minus_sync_ms': after - wall,
                     'sync_main_cpu_ms': average('main_cpu_ms', 'main_cpu_samples'),
                     'render_interval_cpu_ms': average('render_cpu_ms', 'render_cpu_samples'),
                     'distinct_render_thread_samples': sync['distinct_render_thread_samples'],
                     'calls': sync['calls']})
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('control', type=Path)
    parser.add_argument('experiment', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    rows = compare(json.loads(args.control.read_text()), json.loads(args.experiment.read_text()))
    if args.output:
        args.output.write_text(json.dumps(rows, indent=2))
    print('Phase averages (ms). Render CPU is per checkpoint interval, not barrier-only.')
    for row in rows:
        print(row['mode'] + ': ' + ', '.join(
            f'{key}={value:.3f}' if isinstance(value, float) else f'{key}={value}'
            for key, value in row.items() if key != 'mode'))
