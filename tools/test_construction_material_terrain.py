"""Native binary-table destination checks; not full material movement acceptance."""
import json
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
FIXTURE=json.loads((ROOT/'fixtures/construction/material_destination.json').read_text())


class MaterialDestination(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        df={tiletype={attrs={}},tiletype_shape={},building_type={}}
        block={tiletype={[0]={[0]=0}},designation={[0]={[0]={flow_forbid=false}}},
            occupancy={[0]={[0]={building=0}}}}
        dfhack={maps={getTileBlock=function()return block end},
            buildings={findAtTile=function()return building end}}
        function probe(tile,occupancy,forbid,kind,closed)
            block.tiletype[0][0]=tile
            block.designation[0][0].flow_forbid=forbid
            block.occupancy[0][0].building=occupancy
            df.building_type[0]=kind
            building=kind and {getType=function()return 0 end,
                getBuildStage=function()return building_stage or 1 end,
                getMaxBuildStage=function()return 1 end,
                isSettingOccupancy=function()return setting_occupancy~=false end,
                door_flags={closed=closed,forbidden=forbidden or false},gate_flags={closed=closed}} or nil
            return reader({x=0,y=0,z=0})
        end
        ''')
        df=self.lua.globals().df
        for row in FIXTURE['tiles']:
            df.tiletype[row['id']]=row['name']
            df.tiletype.attrs[row['id']]=self.lua.table_from({'shape':row['shape']})
            df.tiletype_shape[row['shape']]=row['shape']
        self.lua.globals().reader=self.lua.execute((ROOT/'bridge/plugin/construction_material_terrain.lua').read_text())
        self.probe=self.lua.globals().probe

    def use_opening(self,movement):
        self.lua.globals().opening=self.lua.execute((ROOT/'bridge/plugin/construction_material_opening.lua').read_text())
        self.lua.globals().movement=movement
        self.lua.execute("reader=function(p)return opening(p,movement and 'stairs' or 'liquid')end")

    def test_native_opening_tiles_and_static_occupancies(self):
        for movement in (False,True):
            self.use_opening(movement)
            field='native_movement_opening' if movement else 'native_liquid_opening'
            for row in FIXTURE['tiles']:
                for occupancy in range(7):
                    expected=row[field] and occupancy not in (3,5,6)
                    self.assertEqual(self.probe(row['id'],occupancy,False,None,False),expected,
                                     (row['name'],occupancy,movement))

    def test_opening_hatch_modes_and_dynamic_floor_covers(self):
        for movement in (False,True):
            self.use_opening(movement)
            for closed in (False,True):
                for forbidden in (False,True):
                    for stage in (0,1):
                        for setting in (False,True):
                            self.lua.globals().forbidden=forbidden
                            self.lua.globals().building_stage=stage
                            self.lua.globals().setting_occupancy=setting
                            blocked=closed and (not movement or (forbidden and stage==1 and setting))
                            self.assertEqual(self.probe(32,7,False,'Hatch',closed),not blocked)
            for kind in ('GrateFloor','BarsFloor','GrateWall','BarsVertical','Door'):
                for closed in (False,True):
                    blocked=closed and kind in ('GrateFloor','BarsFloor')
                    self.assertEqual(self.probe(32,7,False,kind,closed),not blocked)
            self.assertIsNone(self.probe(32,7,False,None,False))
        self.lua.execute('reader=function(p)return opening(p,nil)end')
        self.assertIsNone(self.probe(32,0,False,None,False))

    def test_ramp_clearance_separates_stair_tiles_from_hatch_behavior(self):
        self.use_opening(True)
        self.lua.execute("reader=function(p)return opening(p,'ramp')end")
        for row in FIXTURE['tiles']:
            self.assertEqual(self.probe(row['id'],0,False,None,False),row['native_liquid_opening'],row['name'])
        # Closed but unforbidden hatch: movement permits passage; liquid does not.
        self.lua.globals().forbidden=False
        self.assertTrue(self.probe(32,7,False,'Hatch',True))
        self.lua.globals().forbidden=True
        self.assertFalse(self.probe(32,7,False,'Hatch',True))

    def test_all_native_tiles_static_occupancies_and_flow_forbid(self):
        for row in FIXTURE['tiles']:
            for occupancy in range(7):
                for forbid in (False,True):
                    expected=not forbid and occupancy not in (3,4,6) and (
                        row['native_base_walkable'] or occupancy==5 and row['native_open_exception'])
                    self.assertEqual(self.probe(row['id'],occupancy,forbid,None,False),expected,
                                     (row['name'],occupancy,forbid))

    def test_native_ramp_and_support_classifications(self):
        classify=self.lua.execute((ROOT/'bridge/plugin/construction_material_shapes.lua').read_text())
        for row in FIXTURE['tiles']:
            actual=classify(row['id'])
            self.assertEqual(row['native_general_surface'],row['native_base_walkable'],row['name'])
            self.assertEqual(actual['ramp'],row['native_movement_ramp'],row['name'])
            self.assertEqual(actual['support'],row['native_ramp_support'],row['name'])
        self.assertIsNone(classify(9999))

    def test_track_reader_preserves_native_movement_classifications(self):
        self.lua.execute('''
        df.construction_type={};df.tiletype_material={CONSTRUCTION=1}
        dfhack.buildings.markedForRemoval=function()return false end
        block.walkable={[0]={[0]=1}}
        block.designation[0][0].hidden=false
        block.designation[0][0].flow_size=0
        block.designation[0][0].liquid_type=false
        ''')
        reader=self.lua.execute((ROOT/'bridge/plugin/construction_track.lua').read_text())
        point=self.lua.table_from({'x':0,'y':0,'z':0})
        for row in FIXTURE['tiles']:
            self.lua.globals().block.tiletype[0][0]=row['id']
            result=reader(point)
            self.assertEqual(result['movement_ramp'],row['native_movement_ramp'],row['name'])
            self.assertEqual(result['support'],row['native_ramp_support'],row['name'])
        for group in (0,1,12345):
            self.lua.globals().block.walkable[0][0]=group
            self.assertEqual(reader(point)['walkable'],group!=0)

    def test_composed_facts_preserve_missing_lower_and_dynamic_observations(self):
        opening=self.lua.execute((ROOT/'bridge/plugin/construction_material_opening.lua').read_text())
        shapes=self.lua.execute((ROOT/'bridge/plugin/construction_material_shapes.lua').read_text())
        factory=self.lua.execute((ROOT/'bridge/plugin/construction_material_facts.lua').read_text())
        reader=factory(self.lua.globals().reader,opening,shapes)
        self.lua.execute('''
        block.temperature_1={[0]={[0]=10199}}
        block.designation[0][0].flow_size=1
        block.designation[0][0].liquid_type=false
        lower={designation={[0]={[0]={flow_size=7}}}}
        dfhack.maps.getTileBlock=function(p)if p.z==1 then return block else return lower end end
        ''')
        point=self.lua.table_from({'x':0,'y':0,'z':1})
        ids={r['name']:r['id'] for r in FIXTURE['tiles']}
        self.lua.globals().block.tiletype[0][0]=ids['StoneFloorSmooth']
        result=reader(point)
        self.assertTrue(result['loaded'])
        self.assertEqual(result['temperature'],10199)
        self.assertEqual(result['liquid_depth'],1)
        self.assertFalse(result['magma'])
        self.assertFalse(result['open_below'])
        self.assertIsNone(result['below_liquid_depth'])
        self.lua.globals().block.tiletype[0][0]=ids['OpenSpace']
        result=reader(point)
        self.assertTrue(result['open_below'])
        self.assertEqual(result['below_liquid_depth'],7)
        self.assertFalse(result['destination_allowed'])
        self.lua.execute('lower=nil')
        self.assertIsNone(reader(point)['below_liquid_depth'])
        self.lua.globals().block.occupancy[0][0].building=7
        result=reader(point)
        for field in ('destination_allowed','stair_opening','ramp_opening','open_below'):
            self.assertIsNone(result[field],field)
        self.assertTrue(result['open'])
        self.lua.execute('block=nil')
        self.assertFalse(reader(point)['loaded'])

    def test_composed_read_reuses_tile_without_retaining_dynamic_facts(self):
        opening=self.lua.execute((ROOT/'bridge/plugin/construction_material_opening.lua').read_text())
        shapes=self.lua.execute((ROOT/'bridge/plugin/construction_material_shapes.lua').read_text())
        factory=self.lua.execute((ROOT/'bridge/plugin/construction_material_facts.lua').read_text())
        destination=self.lua.globals().reader
        reader=factory(destination,opening,shapes)
        self.lua.execute("""
        block_reads=0
        block.temperature_1={[0]={[0]=10015}}
        block.designation[0][0].flow_size=0
        block.designation[0][0].liquid_type=false
        dfhack.maps.getTileBlock=function()block_reads=block_reads+1;return block end
        """)
        point=self.lua.table_from({'x':0,'y':0,'z':1})
        # Every recorded tile and occupancy, including dynamic building changes.
        for tile in FIXTURE['tiles']:
            for occupancy in range(8):
                for kind in (None,'Hatch','GrateFloor','BarsVertical'):
                    for closed in (False,True):
                        self.probe(tile['id'],occupancy,False,kind,closed)
                        expected=(destination(point),opening(point,'stairs'),opening(point,'ramp'))
                        self.lua.globals().block_reads=0
                        actual=reader(point)
                        self.assertEqual(self.lua.globals().block_reads,1)
                        self.assertEqual(tuple(actual[k] for k in
                            ('destination_allowed','stair_opening','ramp_opening')),expected)

    def test_native_dynamic_floor_and_wall_branches(self):
        for row in FIXTURE['tiles']:
            for kind in ('Hatch','GrateFloor','BarsFloor','GrateWall','BarsVertical','Door'):
                for closed in (False,True):
                    expected=row['native_base_walkable']
                    if closed and kind in ('Hatch','GrateFloor','BarsFloor'):
                        expected=expected or row['native_open_exception']
                    if closed and kind in ('GrateWall','BarsVertical'):
                        expected=False
                    self.assertEqual(self.probe(row['id'],7,False,kind,closed),expected,
                                     (row['name'],kind,closed))

    def test_missing_facts_remain_unknown(self):
        self.assertIsNone(self.probe(43,7,False,None,False))
        self.assertIsNone(self.probe(9999,0,False,None,False))
        self.assertIsNone(self.probe(43,0,None,None,False))
        self.lua.execute('block=nil')
        self.assertIsNone(self.lua.globals().reader(self.lua.table_from({'x':0,'y':0,'z':0})))


if __name__=='__main__':
    result=unittest.main(exit=False).result
    if not result.wasSuccessful():
        raise SystemExit(1)
    print('CONSTRUCTION_MATERIAL_TERRAIN_PASS')
