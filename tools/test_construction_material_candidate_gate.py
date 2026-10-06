"""Replay native Track bin/secondary-flag evidence through the partial Lua gate."""
import json
from pathlib import Path
import unittest

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class CandidateGateTests(unittest.TestCase):
    def test_workshop_input_native_copy(self):
        evidence=json.loads((ROOT/'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={BAR=0,SMALLGEM=1,BOULDER=4,BLOCKS=2,WOOD=5,BARREL=17,BUCKET=18,ANVIL=45,TRAPPARTS=67,MILLSTONE=81,CHAIN=10,TRAPCOMP=68,PIPE_SECTION=77,BALLISTAPARTS=64,CATAPULTPARTS=63,BOLT_THROWER_PARTS=92,BIN=32,WEAPON=24},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return improved end,
                    getType=function()return sample.item_type end,getSubtype=function()return sample.item_subtype end,
                    getMaterial=function()return sample.mat_type end,getMaterialIndex=function()return sample.mat_index end}
            end}}
            dfhack={df2utf=function(s)return s end,items={getDescription=function(item,mode,decorated)
                return mode==0 and sample.description or mode==1 and sample.singular or sample.plural end}}
        ''')
        for section in ('workshop_reference','workshop_special_reference','utility_reference','utility_special_reference','machine_reference','machine_special_reference','final_workshop_reference','final_workshop_special_reference','weapon_reference','weapon_special_reference'):
            for case in evidence[section]['cases']:
                for f in case['filters']:
                    for native in f['groups']:
                        sample=next(c for c in f['candidates'] if c['id']==native['ids'][0])
                        self.lua.globals().sample=self.lua.table_from(sample)
                        special=native['kind']=='Specific'
                        self.lua.globals().improved=special
                        group={k:sample[k] for k in ('item_type','item_subtype','mat_type','mat_index')}
                        group.update(individual=special,ids=native['ids'])
                        self.assertEqual(describe(self.lua.table_from(group,recursive=True)),native['name'],(case['definition'],f['index']))

    def test_native_improved_last_name_is_a_generic_material_class(self):
        fixture=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))
        cases=fixture['single_item_special_last_reference']['cases']+[fixture['artifact_last_reference']['case']]
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={},item={find=function(id)
                return {flags={artifact=artifact},isImproved=function()return true end,
                    getType=function()return sample.item_type end,getSubtype=function()return sample.item_subtype end,
                    getMaterial=function()return sample.mat_type end,getMaterialIndex=function()return sample.mat_index end}
            end}}
            dfhack={df2utf=function(s)return s end,
                matinfo={decode=function()return {toString=function()return material end}end},
                items={getDescription=function(item,mode,decorated)
                    assert(mode==2 and not decorated);return plural end}}
        ''')
        kinds={'TractionBench':'TRACTION_BENCH','Bookcase':'TOOL','DisplayFurniture':'TOOL','OfferingPlace':'TOOL','Instrument':'INSTRUMENT','Door':'DOOR','Hatch':'HATCH_COVER','Cage':'CAGE','Chain':'CHAIN','Armorstand':'ARMORSTAND','Weaponrack':'WEAPONRACK','GrateWall':'GRATE','GrateFloor':'GRATE','Floodgate':'FLOODGATE'}
        for case in cases:
            with self.subTest(kind=case['definition']):
                sample=case['history'];expected=case['native_last_name'].lower()
                self.lua.globals().sample=self.lua.table_from(sample)
                self.lua.globals().artifact=case.get('artifact',False)
                self.lua.globals().df.item_type[kinds.get(case['definition'],case['definition'].upper())]=sample['item_type']
                self.lua.globals().plural=next(d['text'] for d in case['descriptions'] if d['mode']==2 and not d['decorated'])
                self.lua.globals().material=expected.removesuffix(' statues')
                group={k:sample[k] for k in ('item_type','item_subtype','mat_type','mat_index')}
                group.update(individual=True,ids=[case['expected_item']])
                self.assertEqual(describe(self.lua.table_from(group,recursive=True),None,True),expected)

    def test_remaining_single_item_native_copy(self):
        fixture=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return improved end,
                    getType=function()return sample.item_type end,getSubtype=function()return sample.item_subtype end,
                    getMaterial=function()return sample.mat_type end,getMaterialIndex=function()return sample.mat_index end}
            end}}
            dfhack={df2utf=function(s)return s end,items={getDescription=function(item,mode,decorated)
                return mode==0 and sample.description or mode==1 and sample.singular or sample.plural end}}
        ''')
        kinds={'NestBox':'TOOL','Hive':'TOOL','Workshop:Quern':'QUERN','AnimalTrap':'ANIMALTRAP','WindowGlass':'WINDOW','Trap:PressurePlate':'TRAPPARTS'}
        for improved, section in [(False,'remaining_single_item_reference'),(True,'remaining_single_item_improved_reference')]:
            self.lua.globals().improved=improved
            for case in fixture[section]['cases']:
                for native in case['groups']:
                    sample=next(c for c in case['candidates'] if c['id']==native['ids'][0])
                    self.lua.globals().sample=self.lua.table_from(sample)
                    self.lua.globals().df.item_type[kinds[case['definition']]]=sample['item_type']
                    group={k:sample[k] for k in ('item_type','item_subtype','mat_type','mat_index')}
                    group.update(individual=improved,ids=native['ids'])
                    row=self.lua.table_from(group,recursive=True)
                    self.assertEqual(describe(row),native['name'],case['definition'])
                    self.assertEqual(describe(row,None,True),case['native_last_name'].lower(),case['definition'])

    def test_additional_single_item_group_copy(self):
        cases=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))['additional_single_item_reference']['capture']['cases']
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return sample.item_type end,getSubtype=function()return sample.item_subtype end,
                    getMaterial=function()return sample.mat_type end,getMaterialIndex=function()return sample.mat_index end}
            end}}
            dfhack={df2utf=function(s)return s end,items={getDescription=function(item,mode,decorated)
                assert(mode==2 and not decorated);return sample.plural end}}
        ''')
        kinds={'TractionBench':'TRACTION_BENCH','Bookcase':'TOOL','DisplayFurniture':'TOOL','OfferingPlace':'TOOL','Instrument':'INSTRUMENT','Door':'DOOR','Hatch':'HATCH_COVER','Cage':'CAGE','Chain':'CHAIN','Armorstand':'ARMORSTAND','Weaponrack':'WEAPONRACK','GrateWall':'GRATE','GrateFloor':'GRATE','Floodgate':'FLOODGATE'}
        for case in cases:
            for native in case['groups']:
                item=next(v for v in case['candidates'] if v['id']==native['ids'][0])
                self.lua.globals().sample=self.lua.table_from(item)
                self.lua.globals().df.item_type[kinds[case['definition']]]=item['item_type']
                group={k:item[k] for k in ('item_type','item_subtype','mat_type','mat_index')}
                group.update(individual=False,ids=native['ids'])
                self.assertEqual(describe(self.lua.table_from(group,recursive=True)),native['name'])

    def test_artifact_uses_its_native_name_not_readable_or_material_description(self):
        self.lua.execute('''
            df={item_type={COFFIN=21},general_ref_type={IS_ARTIFACT=7},item={find=function(id)
                if id~=13105 then return nil end
                return {flags={artifact=true},getType=function()return 21 end,getSubtype=function()return -1 end,
                    getMaterial=function()return 422 end,getMaterialIndex=function()return 157 end}
            end}}
            named=true
            dfhack={df2utf=function(s)return s end,items={getGeneralRef=function(item,kind)
                assert(kind==7);return {getArtifact=function()return {name={has_name=named}}end}end},
                translation={translateName=function(name,english)assert(not english);return 'Gongithosal'end}}
        ''')
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        row=self.lua.table_from(dict(item_type=21,item_subtype=-1,mat_type=422,mat_index=157,individual=True,ids=[13105]),recursive=True)
        fixture=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))['artifact_reference']
        native=next(g for c in fixture['cases'] for g in c['groups'] if g['ids']==[13105])
        self.assertEqual(describe(row),native['name'])
        self.assertEqual(describe(row,13105),native['name'])
        self.lua.globals().named=False
        self.assertIsNone(describe(row))

    def test_native_improved_furniture_standalone_copy(self):
        fixture=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))
        cases=fixture['special_item_reference']['cases']+fixture['additional_single_item_improved_reference']['capture']['cases']
        kinds={'TractionBench':'TRACTION_BENCH','Bookcase':'TOOL','DisplayFurniture':'TOOL','OfferingPlace':'TOOL','Instrument':'INSTRUMENT','Door':'DOOR','Hatch':'HATCH_COVER','Cage':'CAGE','Chain':'CHAIN','Armorstand':'ARMORSTAND','Weaponrack':'WEAPONRACK','GrateWall':'GRATE','GrateFloor':'GRATE','Floodgate':'FLOODGATE'}
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={},item={find=function(id)
                if id~=recorded.id then return nil end
                return {flags={artifact=false},isImproved=function()return true end,
                    getType=function()return recorded.item_type end,getSubtype=function()return recorded.item_subtype end,
                    getMaterial=function()return recorded.mat_type end,getMaterialIndex=function()return recorded.mat_index end}
            end}}
            dfhack={df2utf=function(s)return s end,items={getDescription=function(item,mode,decorate)
                assert(mode==0 and decorate);return decorated end}}
        ''')
        count=0
        for case in cases:
            names={g['ids'][0]:g['name'] for g in case['groups'] if g['kind']=='Specific'}
            for item in case['candidates']:
                if not item['improved'] or item['id'] not in names:continue
                self.lua.globals().recorded=self.lua.table_from(item,recursive=True)
                self.lua.globals().df.item_type[case['kind'] if 'kind' in case else kinds[case['definition']]]=item['item_type']
                self.lua.globals().decorated=next(d['text'] for d in item['descriptions'] if d['mode']==0 and d['decorated']) if 'descriptions' in item else item['description']
                group={k:item[k] for k in ('item_type','item_subtype','mat_type','mat_index')}
                group.update(individual=True,ids=[item['id']])
                row=self.lua.table_from(group,recursive=True)
                self.assertEqual(describe(row),names[item['id']])
                self.assertEqual(describe(row,item['id']),names[item['id']])
                self.assertIsNone(describe(row,item['id']+1))
                count+=1
        self.assertEqual(count,48)

    def test_native_furniture_group_copy(self):
        fixture = json.loads((ROOT / 'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))
        describe = self.lua.execute((ROOT / 'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={BED='BED',CHAIR='CHAIR',TABLE='TABLE'},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return kind end,getSubtype=function()return -1 end,
                    getMaterial=function()return 420 end,getMaterialIndex=function()return 140 end}
            end}}
            dfhack={df2utf=function(text)return text end,items={getDescription=function(item,mode,decorate)
                assert(not decorate);assert(mode==1 or mode==2)
                return mode==1 and singular or plural
            end}}
        ''')
        for case in fixture['cases']:
            for native in case['groups']:
                self.lua.globals().kind = case['kind']
                self.lua.globals().singular = native['singular']
                self.lua.globals().plural = native['plural']
                group = dict(item_type=case['kind'], item_subtype=-1, mat_type=420,
                             mat_index=140, individual=False, ids=native['ids'])
                self.assertEqual(describe(self.lua.table_from(group, recursive=True)), native['text'])

    def test_native_common_furniture_group_copy(self):
        fixture = json.loads((ROOT / 'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))['common_furniture_copy']
        describe = self.lua.execute((ROOT / 'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute("""
            df={item_type={COFFIN='COFFIN',CABINET='CABINET',BOX='BOX',SLAB='SLAB'},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return kind end,getSubtype=function()return -1 end,
                    getMaterial=function()return 420 end,getMaterialIndex=function()return 140 end}
            end}}
            dfhack={df2utf=function(text)return text end,items={getDescription=function(item,mode,decorate)
                assert(not decorate);assert(mode==1 or mode==2)
                return mode==1 and singular or plural
            end}}
        """)
        for case in fixture['cases']:
            if case['kind'] == 'STATUE':
                continue  # Native group description is not the full statue description.
            for native in case['groups']:
                self.lua.globals().kind = case['kind']
                self.lua.globals().singular = native['singular']
                self.lua.globals().plural = native['plural']
                group = dict(item_type=case['kind'], item_subtype=-1, mat_type=420,
                             mat_index=140, individual=False, ids=native['ids'])
                self.assertEqual(describe(self.lua.table_from(group, recursive=True)), native['text'])

    def test_native_statue_group_copy_omits_depicted_subject(self):
        fixture=json.loads((ROOT/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))['statue_copy']
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute("""
            df={item_type={STATUE='STATUE'},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return 'STATUE' end,getSubtype=function()return -1 end,
                    getMaterial=function()return 0 end,getMaterialIndex=function()return 1 end}
            end}}
            dfhack={df2utf=function(text)return text end,
                matinfo={decode=function()return {toString=function()return material end}end},
                items={getDescription=function()return depicted_description end}}
        """)
        for case in fixture['cases']:
            for native in case['groups']:
                self.lua.globals().material=native['material']
                self.lua.globals().depicted_description=native['plural']
                group=dict(item_type='STATUE',item_subtype=-1,mat_type=0,mat_index=1,individual=False,ids=native['ids'])
                self.assertEqual(describe(self.lua.table_from(group,recursive=True)),native['text'])

    def test_native_anvil_group_copy(self):
        fixture = json.loads((ROOT / 'fixtures/construction/magma_placement.json').read_text(encoding='utf-8'))
        describe = self.lua.execute((ROOT / 'bridge/plugin/construction_material_group_name.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            df={item_type={ANVIL='ANVIL'},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return kind end,getSubtype=function()return -1 end,
                    getMaterial=function()return 420 end,getMaterialIndex=function()return 140 end}
            end}}
            dfhack={df2utf=function(text)return text end,items={getDescription=function(item,mode,decorate)
                assert(not decorate);assert(mode==1 or mode==2)
                return mode==1 and singular or plural
            end}}
        ''')
        for case in fixture['anvil_copy']['cases']:
            for native in case['groups']:
                self.lua.globals().kind = 'ANVIL'
                self.lua.globals().singular = native['descriptions'][0]['singular']
                self.lua.globals().plural = native['descriptions'][0]['plural']
                group = dict(item_type='ANVIL', item_subtype=-1, mat_type=420,
                             mat_index=140, individual=False, ids=native['ids'])
                self.assertEqual(describe(self.lua.table_from(group, recursive=True)), native['name'])

    def test_native_decorated_anvil_individuals(self):
        fixture=json.loads((ROOT/'fixtures/construction/magma_placement.json').read_text())['native_picker']['expanded']
        describe=self.lua.execute((ROOT/'bridge/plugin/construction_material_group_name.lua').read_text())
        self.lua.execute("""
            df={item_type={ANVIL=45},item={find=function(id)
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return 45 end,getSubtype=function()return -1 end,
                    getMaterial=function()return 0 end,getMaterialIndex=function()return 1 end}
            end}}
            dfhack={df2utf=function(text)return text end,items={getDescription=function(item,mode,decorate)
                assert(mode==0);return decorate and decorated or plain
            end}}
        """)
        names={r['id']:r['name'] for r in fixture['choices'] if r['kind']=='Specific'}
        for row in fixture['items']:
            self.lua.globals().decorated=row['decorated'];self.lua.globals().plain=row['description']
            group=dict(item_type=45,item_subtype=-1,mat_type=0,mat_index=1,individual=False,ids=[row['id']])
            self.assertEqual(describe(self.lua.table_from(group,recursive=True),row['id']),names[row['id']])

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.gate = self.lua.execute((ROOT / 'bridge/plugin/construction_material_candidate_gate.lua').read_text())
        self.enabled = self.lua.execute((ROOT / 'bridge/plugin/construction_material_candidate_enabled.lua').read_text())
        self.groups = self.lua.execute((ROOT / 'bridge/plugin/construction_track_material_groups.lua').read_text())
        self.recipe = self.lua.execute((ROOT / 'bridge/plugin/construction_track_material_recipe.lua').read_text())
        factory = self.lua.execute((ROOT / 'bridge/plugin/construction_track_material_candidates.lua').read_text())
        self.partition = self.lua.execute((ROOT / 'bridge/plugin/construction_material_partition.lua').read_text())
        self.scan = factory(self.gate, self.recipe, self.enabled, self.groups, self.partition, self.lua.eval('function()return nil end'))

    def test_native_initial_group_membership(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        total = 0
        for case in fixture['initial_group_capture']['cases']:
            rows = [dict(zip(('id', 'item_type', 'item_subtype', 'mat_type', 'mat_index', 'individual'), row),
                         enabled=True) for row in case['candidates']]
            actual = self.partition(self.lua.table_from(rows, recursive=True))
            self.assertIsNotNone(actual)
            groups = list(actual.values())
            # This capture has no artifacts/improved items. Compare complete
            # native membership; native distance sorting is not tested here.
            expected = sorted(case['groups'], key=lambda g: g['ids'][0])
            self.assertEqual(len(groups), 33)
            for group, native in zip(groups, expected):
                self.assertEqual(native['kind'], 'General')
                self.assertFalse(group['individual'])
                self.assertEqual(':'.join(str(group[k]) for k in
                    ('item_type', 'item_subtype', 'mat_type', 'mat_index')), native['identity'])
                self.assertEqual(list(group['ids'].values()), native['ids'])
            total += len(rows)
        self.assertEqual(total, 6599)

    def test_partition_missing_facts_and_duplicate_ids(self):
        row = dict(id=1, item_type=2, item_subtype=-1, mat_type=0, mat_index=3,
                   enabled=True, individual=False)
        for missing in ('individual', 'mat_index', 'enabled'):
            partial = dict(row)
            del partial[missing]
            self.assertIsNone(self.partition(self.lua.table_from([partial], recursive=True)))
        self.assertIsNone(self.partition(self.lua.table_from([row, row], recursive=True)))
        # Disabled rows need no grouping facts; malformed snapshots still fail.
        self.assertEqual(len(self.partition(self.lua.table_from([dict(id=1, enabled=False)], recursive=True))), 0)

    def test_partition_preserves_individual_identity(self):
        # Synthetic invariant for the traced special-item branch; the native
        # group capture currently contains only ordinary materials.
        rows = [dict(id=i, item_type=2, item_subtype=-1, mat_type=0, mat_index=3,
                     enabled=True, individual=i in (1, 3)) for i in range(1, 5)]
        actual = self.partition(self.lua.table_from(rows, recursive=True))
        self.assertEqual([list(g['ids'].values()) for g in actual.values()], [[2, 4], [1], [3]])
        self.assertEqual([g['individual'] for g in actual.values()], [False, True, True])

    def test_native_group_copy_modes(self):
        describe = self.lua.execute((ROOT / 'bridge/plugin/construction_material_group_name.lua').read_text())
        self.lua.execute('''
            df={item_type={BAR=0,BLOCKS=2,BOULDER=4,WOOD=5},item={find=function(id)
                if id~=sample_id then return nil end
                return {flags={artifact=false},isImproved=function()return false end,
                    getType=function()return sample_identity[1] end,
                    getSubtype=function()return sample_identity[2] end,
                    getMaterial=function()return sample_identity[3] end,
                    getMaterialIndex=function()return sample_identity[4] end}
            end}}
            dfhack={df2utf=function(text)return text end,items={getDescription=function(item,mode,decorate)
                assert(decorate==(mode==0));return sample_descriptions[mode+1].text
            end}}
        ''')
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        count = 0
        for case in fixture['group_copy_capture']['cases']:
            for row in case['groups']:
                self.lua.globals().sample_id = row['representative_id']
                self.lua.globals().sample_identity = self.lua.table_from(row['identity'])
                self.lua.globals().sample_descriptions = self.lua.table_from(row['descriptions'], recursive=True)
                group = dict(zip(('item_type', 'item_subtype', 'mat_type', 'mat_index'), row['identity']),
                             individual=False, ids=[row['representative_id']] * row['candidate_count'])
                self.assertEqual(describe(self.lua.table_from(group, recursive=True)), row['native_copy'])
                self.assertEqual(describe(self.lua.table_from(group, recursive=True), row['representative_id']),
                                 row['descriptions'][0]['text'])
                group['individual'] = True
                self.assertIsNone(describe(self.lua.table_from(group, recursive=True)))
                group['individual'] = False
                group['mat_index'] += 1
                self.assertIsNone(describe(self.lua.table_from(group, recursive=True)))
                count += 1
        self.assertEqual(count, 132)

    def test_native_initial_distance_order(self):
        order = self.lua.execute((ROOT / 'bridge/plugin/construction_material_order.lua').read_text())
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        for case in fixture['installed_order_capture']['cases'] + fixture['installed_terrain_order_capture']['cases']:
            snapshot = case['snapshot']
            recorded = [{'reachable': True, 'distance': case['candidate_distances'][str(row['id'])]}
                        for row in snapshot['candidates'] if row['enabled']]
            self.lua.globals().recorded = self.lua.table_from(recorded, recursive=True)
            search = self.lua.eval('function()return {status=0,distances=recorded}end')
            result = order(self.lua.table_from(snapshot, recursive=True),
                           self.lua.table_from(case['destination']), self.lua.eval('function()end'), search, None, 10000)
            self.assertEqual(result['status'], 0)
            self.assertEqual({r['id']: r['distance'] for r in result['candidate_distances'].values()},
                             {int(k): v for k, v in case['candidate_distances'].items()})
            for actual, native in zip(result['groups'].values(), case['native']):
                self.assertEqual(list(actual['ids'].values()), native['ids'])
                self.assertEqual(actual['distance'], native['distance'])
                self.assertEqual(actual['name'], native['name'])
            self.assertEqual(len(result['groups']), 33)
            # Unknown, capped and unreachable searches must not publish a
            # seemingly valid partial or fallback order.
            for expression, status in [('return {status=3}', 3),
                    ('recorded[1]={reachable=false};return {status=0,distances=recorded}', 2)]:
                failed = order(self.lua.table_from(snapshot, recursive=True), None,
                    self.lua.eval('function()end'), self.lua.eval('function()' + expression + ' end'), None, 10000)
                self.assertEqual(failed['status'], status)
                self.assertIsNone(failed['groups'])
                self.assertIsNone(failed['candidate_distances'])

    def test_native_selection_kernel(self):
        select = self.lua.execute((ROOT / 'bridge/plugin/construction_material_selection.lua').read_text())
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        steps = 0
        for case in fixture['selection_kernel_capture']['cases']:
            distances = self.lua.table_from({int(k): v for k, v in case['candidate_distances'].items()})
            for group in case['groups']:
                ids = self.lua.table_from(group['ids'])
                selected = self.lua.table_from([])
                for native in group['steps']:
                    result = select(ids, distances, selected, native['action'])
                    self.assertIsNotNone(result)
                    self.assertEqual(list(result['selected'].values()), native['selected'])
                    self.assertEqual(result['distance'], native['distance'])
                    self.assertEqual(result['used'], native['used'])
                    self.assertEqual(result['used'], native['provided'])
                    if native['action'] == 'select':
                        self.assertEqual(result['changed_id'], native['returned_id'])
                    else:
                        self.assertEqual(result['changed_id'] >= 0, native['changed'])
                    selected = result['selected']
                    steps += 1
        self.assertEqual(steps, 558)
        self.assertIsNone(select(self.lua.table_from([1]), self.lua.table_from({1: 0}),
                                 self.lua.table_from([2]), 'select'))
        self.assertIsNone(select(self.lua.table_from([1]), self.lua.table_from({}),
                                 self.lua.table_from([]), 'select'))

    def test_native_picker_click_selection_and_final_cap(self):
        select = self.lua.execute((ROOT / 'bridge/plugin/construction_material_selection.lua').read_text())
        evidence = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())['picker_interaction_capture']
        frames = evidence['frames']
        initial = frames['picker-initial']
        distances = self.lua.table_from({r['id']: r['distance'] for r in initial['candidates']})
        group = next(g for g in initial['choices'] if g['name'] == 'chert blocks')
        selected = self.lua.table_from([])
        for label in ('picker-one', 'picker-all'):
            result = select(self.lua.table_from(group['ids']), distances, selected, 'select')
            self.assertEqual(list(result['selected'].values()),
                             [r['id'] for r in frames[label]['candidates'] if r['selected']])
            expected = next(g for g in frames[label]['choices'] if g['ids'] == group['ids'])
            self.assertEqual(result['distance'], expected['distance'])
            selected = result['selected']
        for _ in range(2):
            selected = select(self.lua.table_from(group['ids']), distances, selected, 'deselect')['selected']
        self.assertEqual(len(selected), frames['picker-none']['provided'])
        # Actual All click on a two-item row with only one required selected
        # exactly the nearest item, then native placement reserved all five.
        partial = frames['picker-four']
        self.assertEqual(partial['required'] - partial['provided'], 1)
        group = next(g for g in partial['choices'] if g['name'] == 'platinum bars')
        result = select(self.lua.table_from(group['ids']), distances, self.lua.table_from([]), 'select')
        expected = {r['id'] for r in partial['candidates'] if r['selected']} | set(result['selected'].values())
        self.assertEqual(expected, set(evidence['placement_effects']['reserved']))

    def test_native_individual_click_preserves_exact_item(self):
        select = self.lua.execute((ROOT / 'bridge/plugin/construction_material_selection.lua').read_text())
        evidence = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())['individual_picker_capture']
        frames = evidence['frames']
        initial = frames['expanded-Iron bars']
        group = next(g for g in initial['choices'] if g['kind'] == 'General' and g['name'] == 'iron bars')
        distances = self.lua.table_from({r['id']: r['distance'] for r in initial['candidates']})
        selected = [r['id'] for r in frames['specific-selected']['candidates'] if r['selected']]
        self.assertEqual(len(selected), 1)
        ids = self.lua.table_from(group['ids'])
        result = select(ids, distances, self.lua.table_from([]), 'select', selected[0])
        self.assertEqual(list(result['selected'].values()), selected)
        self.assertEqual(result['changed_id'], selected[0])
        again = select(ids, distances, result['selected'], 'select', selected[0])
        self.assertEqual(again['changed_id'], -1)
        for label in ('specific-collapsed', 'specific-reopened', 'specific-clicked-again'):
            self.assertEqual(list(again['selected'].values()),
                             [r['id'] for r in frames[label]['candidates'] if r['selected']])
        self.assertIsNone(select(ids, distances, result['selected'], 'select', -1))

    def test_native_expanded_display_order(self):
        order = self.lua.execute((ROOT / 'bridge/plugin/construction_material_order.lua').read_text())
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        for case in fixture['expanded_order_capture']['cases']:
            snapshot = {'status': 0, 'candidates': [{'id': id, 'enabled': True, 'position': {}}
                         for id in case['ids']], 'initial_groups': [{'ids': case['ids']}]}
            recorded = [{'reachable': True, 'distance': case['candidate_distances'][str(id)]} for id in case['ids']]
            self.lua.globals().recorded = self.lua.table_from(recorded, recursive=True)
            result = order(self.lua.table_from(snapshot, recursive=True), None, self.lua.eval('function()end'),
                self.lua.eval('function()return {status=0,distances=recorded}end'), None, 10000)
            self.assertEqual(result['status'], 0)
            group = result['groups'][1]
            self.assertEqual(list(group['expanded_ids'].values()), [r['id'] for r in case['native_children']])
            self.assertEqual(list(group['ids'].values()), case['ids'])

    def test_composed_snapshot_order_limits_and_failure(self):
        self.lua.execute('''
            local block={walkable={}}
            for x=0,15 do block.walkable[x]={};for y=0,15 do block.walkable[x][y]=1000047 end end
            function make_item(id,forbidden,assigned)
                return {id=id,flags={whole=forbidden and 0x80001 or 1,in_inventory=false},flags2={whole=0},
                    getType=function()return 0 end,getSubtype=function()return -1 end,
                    getMaterial=function()return 0 end,getMaterialIndex=function()return 3 end,
                    isImproved=function()return false end,isBuildMat=function()return true end,isAssignedToStockpile=function()return assigned end}
            end
            df={item_type={[0]='BAR'},global={world={items={other={IN_PLAY={}}}},plotinfo={economic_stone={}}}}
            dfhack={maps={isValidTilePos=function(p)return p.x>=0 and p.y>=0 and p.z>=0 end,
                         getTileBlock=function()return block end},
                    items={getPosition=function(item)return item.id,2,1 end}}
            df.global.world.items.other.IN_PLAY={make_item(9,false,false),make_item(2,false,false),
                make_item(5,true,false),make_item(6,false,true)}
            test_path={{x=1,y=1,z=1},{x=2,y=1,z=1}}
        ''')
        path = self.lua.globals().test_path
        result = self.scan(path, 8)
        self.assertEqual(result['status'], 0)
        self.assertEqual([r['id'] for r in result['candidates'].values()], [2, 9])
        self.assertTrue(all(r['enabled'] for r in result['candidates'].values()))
        self.assertEqual(self.scan(path, 1)['status'], 3)
        self.assertIsNone(self.scan(path, 1)['candidates'])
        self.lua.execute('dfhack.items.getPosition=function()error("unavailable position")end')
        self.assertEqual(self.scan(path, 8)['status'], 2)
        self.assertIsNone(self.scan(path, 8)['candidates'])
        self.assertEqual(self.scan(path, 0)['status'], 1)

    def test_native_recipe_capture(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        count = 0
        for case in fixture['recipe_capture']['cases'] + fixture['bar_capture']['cases']:
            for probe in case['probes']:
                with self.subTest(case=case['label'], kind=probe['kind']):
                    self.assertEqual(self.recipe(self.lua.table_from(probe)), probe['present'])
                    count += 1
        self.assertEqual(count, 54)

    def test_missing_recipe_policy_is_unknown(self):
        self.assertIsNone(self.recipe(self.lua.table_from({})))
        self.assertIsNone(self.recipe(self.lua.table_from({'is_build_mat': True, 'type': 'BOULDER',
                                                          'material_type': 0, 'material_index': 196})))

    def test_native_melt_exclusion(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        melt = next(row for row in fixture['melt_capture']['cases'] if row['flag']=='melt')
        # The captured primary flag is sufficient to reject, without inventing
        # the uncaptured secondary flags or containment facts.
        self.assertFalse(melt['present'])
        self.assertFalse(self.gate(self.lua.table_from({'flags': melt['item_flags']})))

    def test_native_track_site_groups(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        rows = fixture['site_group_capture']['cases'] + fixture['elevated_site_group_capture']['cases']
        self.assertEqual(len(rows), 72)
        for row in rows:
            with self.subTest(case=row['flag']):
                self.lua.globals().samples = self.lua.table_from(row['samples'], recursive=True)
                reader = self.lua.eval('''function(p)
                    for _,s in ipairs(samples)do
                        if s.pos.x==p.x and s.pos.y==p.y and s.pos.z==p.z then return s.group end
                    end
                    error('unexpected group sample')
                end''')
                groups = self.groups(self.lua.table_from(row['path'], recursive=True), reader)
                self.assertIsNotNone(groups)
                self.assertEqual(self.enabled(row['actual_item_group'], groups), row['enabled'])

    def test_site_group_collection_fails_closed(self):
        path = self.lua.table_from([{'x': 0, 'y': 0, 'z': 0}, {'x': 4, 'y': 0, 'z': 0}], recursive=True)
        for reader in ['function()return nil end', 'function()error("missing block")end',
                       'function()return -1 end', 'function()return 1.5 end']:
            self.assertIsNone(self.groups(path, self.lua.eval(reader)))
        groups = self.groups(path, self.lua.eval('function()return 1000047 end'))
        self.assertEqual(list(groups.values()), [1000047, 1000047])
        self.assertIsNone(self.groups(self.lua.table_from([]), self.lua.eval('function()return 0 end')))
        self.assertIsNone(self.groups(self.lua.table_from([{'x': 0, 'y': 0, 'z': 0}], recursive=True),
                                      self.lua.eval('function()return 47 end')))

    def test_native_site_group_capture(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        rows = fixture['reach_capture']['cases']
        self.assertEqual(len(rows), 12)
        for row in rows:
            with self.subTest(case=row['flag']):
                self.assertEqual(self.enabled(row['actual_item_group'],
                    self.lua.table_from([row['actual_site_group']])), row['enabled'])

    def test_site_group_unknown_and_no_narrowing(self):
        self.assertIsNone(self.enabled(None, self.lua.table_from([1])))
        self.assertIsNone(self.enabled(1, self.lua.table_from({2: 1})))
        self.assertIsNone(self.enabled(1, self.lua.table_from([1, -1])))
        self.assertFalse(self.enabled(17007, self.lua.table_from([1000047])))
        self.assertFalse(self.enabled(0, self.lua.table_from([0])))
        self.assertFalse(self.enabled(1, self.lua.table_from([])))
        self.assertTrue(self.enabled(1000047, self.lua.table_from([47, 1000047])))

    def test_native_container_capture(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        rows = fixture['container_capture']['cases']
        self.assertEqual(len(rows), 29)
        for row in rows:
            with self.subTest(case=row['flag']):
                facts = {'flags': row['item_flags'], 'flags2': row['item_flags2'],
                         'container_kind': 'BIN', 'container_flags': row['bin_flags'],
                         'container_flags2': row['bin_flags2']}
                self.assertEqual(self.gate(self.lua.table_from(facts)), row['present'])

    def test_native_containment_capture(self):
        fixture = json.loads((ROOT / 'fixtures/construction/material_candidates.json').read_text())
        rows = fixture['containment_capture']['cases']
        self.assertEqual(len(rows), 8)
        for row in rows:
            with self.subTest(case=row['flag']):
                container = row['containment']
                facts = {'flags': row['item_flags'], 'flags2': row['item_flags2'],
                         'container_kind': container['kind']}
                if 'flags' in container:
                    facts.update(container_flags=container['flags'], container_flags2=container['flags2'])
                self.assertEqual(self.gate(self.lua.table_from(facts)), row['present'])

    def test_incomplete_facts_are_unknown(self):
        for facts in [{}, {'flags': 1}, {'flags': 1, 'flags2': -1},
                      {'flags': 1.5, 'flags2': 0}, {'flags': 1 << 32, 'flags2': 0},
                      {'flags': 8, 'flags2': 0},
                      {'flags': 8, 'flags2': 0, 'container_kind': ''},
                      {'flags': 8, 'flags2': 0, 'container_kind': 'BIN', 'container_flags': 1}]:
            with self.subTest(facts=facts):
                self.assertIsNone(self.gate(self.lua.table_from(facts)))


if __name__ == '__main__':
    result = unittest.main(exit=False).result
    if not result.wasSuccessful():
        raise SystemExit(1)
    print('CONSTRUCTION_MATERIAL_CANDIDATE_GATE_PASS')
