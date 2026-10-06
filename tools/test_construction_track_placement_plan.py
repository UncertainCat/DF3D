"""Native route/item assignment replay and rejection before Track mutation."""
import copy
import json
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

class TrackPlacementPlan(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.plan = self.lua.execute((ROOT / 'bridge/plugin/construction_track_placement_plan.lua').read_text())
        self.fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))

    def inputs(self, case):
        rows = copy.deepcopy(self.fixture['production_materials_capture']['materials'])
        retained = {'revision':42,'epoch':7,'plan_key':'fixture route','required':5,'rows':rows}
        fresh = copy.deepcopy(retained)
        fresh['pieces'] = [dict(x=b['x'],y=b['y'],z=b['z'],action=0,connections=12,ramp=False,building_id=-1) for b in case['route_assignments']]
        selections = []
        for row in reversed(rows):
            ids = [c['id'] for c in row['candidates'] if c['id'] in case['selected_ids']]
            if ids:
                selection = {k:row[k] for k in ['item_type','item_subtype','mat_type','mat_index']}
                selection.update(filter=0,count=len(ids),expected_list_revision=42,item_ids=list(reversed(ids)))
                selections.append(selection)
        return retained, fresh, selections

    def call(self, args):
        return self.plan(*(self.lua.table_from(v, recursive=True) for v in args))

    def test_native_assignment_both_route_directions(self):
        for case in self.fixture['assignment_capture']['cases']:
            args = self.inputs(case)
            result = self.call(args)
            self.assertIsNotNone(result)
            for i, b in enumerate(case['route_assignments'],1):
                self.assertEqual(result['pieces'][i]['item_id'],b['jobs'][0]['items'][0]['id'])
                self.assertEqual(result['pieces'][i]['x'],b['x'])
            self.assertEqual(args[2], self.inputs(case)[2], 'caller selections changed')

    def test_stale_and_malformed_intents_rejected(self):
        base = self.inputs(self.fixture['assignment_capture']['cases'][0])
        def remove_selected(a):
            chosen = a[2][0]['item_ids'][0]
            for row in a[1]['rows']:
                row['candidates'] = [c for c in row['candidates'] if c['id'] != chosen]
                row['count'] = len(row['candidates'])
        def swap_group(a):
            chosen = a[2][0]['item_ids'][0]
            for row in a[1]['rows']:
                if any(c['id']==chosen for c in row['candidates']): row['mat_index'] = 999999
        changes = [lambda a:a[1].update(epoch=8),lambda a:a[1].update(plan_key='changed geometry'),
            lambda a:a[1].update(required=4),lambda a:a[2][0].update(expected_list_revision=41),
            lambda a:a[2][0].update(filter=1),lambda a:a[2][0].update(count=0),
            lambda a:a[2][0].pop('item_ids'),lambda a:a[2][0].update(item_ids=[]),
            lambda a:a[2][0]['item_ids'].__setitem__(0,-1),remove_selected,swap_group,
            lambda a:a[2].append(copy.deepcopy(a[2][0])),lambda a:a[1]['pieces'].pop(),
            lambda a:a[1]['pieces'][0].update(x=-1),lambda a:a[1]['pieces'][0].update(action=3),
            lambda a:a[1]['pieces'][0].update(building_id=100),lambda a:a[1]['pieces'][0].update(item_id=42),
            lambda a:a[1]['pieces'][1].update(x=a[1]['pieces'][0]['x']),
            lambda a:a[1]['pieces'][0].update(borrowed={}),lambda a:a[0].pop('epoch')]
        for index, change in enumerate(changes):
            with self.subTest(case=index):
                args = copy.deepcopy(base);change(args)
                self.assertIsNone(self.call(args))

    def test_native_seventeen_distinct_groups(self):
        case = self.fixture['seventeen_group_capture']
        rows, selections = [], []
        for entry in case['selected']:
            row = dict(zip(('item_type','item_subtype','mat_type','mat_index'), map(int, entry['identity'].split(':'))))
            rows.append(dict(row, count=1, candidates=[dict(id=entry['id'])]))
            selections.append(dict(row, filter=0, count=1, expected_list_revision=42, item_ids=[entry['id']]))
        retained = dict(revision=42, epoch=7, plan_key='native17', required=17, rows=rows)
        fresh = copy.deepcopy(retained)
        first = case['start']
        fresh['pieces'] = [dict(x=first['x']+i,y=first['y'],z=first['z'],action=0,connections=12,ramp=False,building_id=-1) for i in range(17)]
        result = self.call((retained,fresh,selections))
        self.assertIsNotNone(result)
        self.assertEqual([result['pieces'][i+1]['item_id'] for i in range(17)], [e['item'] for e in case['effects']])

    def test_pending_updates_do_not_consume_items_and_result_is_owned(self):
        args = self.inputs(self.fixture['assignment_capture']['cases'][0])
        extra = dict(x=999,y=1,z=1,action=1,building_id=100,connections=15,ramp=False,expected_connections=3)
        args[1]['pieces'].insert(1,extra)
        args[1]['pieces'].insert(3,dict(extra,x=1000,action=2,building_id=101))
        lua_args = [self.lua.table_from(v, recursive=True) for v in args]
        result = self.plan(*lua_args)
        self.assertIsNotNone(result)
        self.assertIsNone(result['pieces'][2]['item_id'])
        self.assertIsNone(result['pieces'][4]['item_id'])
        result['pieces'][2]['connections'] = 1
        self.assertEqual(lua_args[1]['pieces'][2]['connections'],15)
        self.assertEqual(len(result['item_ids']),5)

if __name__ == '__main__':
    result = unittest.main(exit=False).result
    if result.wasSuccessful(): print('CONSTRUCTION_TRACK_PLACEMENT_PLAN_PASS')
    raise SystemExit(0 if result.wasSuccessful() else 1)
