"""Deterministic construction contract tests; inline synthetic DF objects only."""
from pathlib import Path
import json
import unittest
from test_construction_catalog import catalog_runtime, synthetic_native_recipe, synthetic_native_candidates

# DFHack signatures/return shapes: see test_construction_catalog.API_MOCKS audit.
# designateRemove: Lua API.rst:2821 returns true,was_only_planned (or false).
# Fixture producibility | construction.lua emitting functions (line numbers are historical).
# Catalog names/modes/flags/reasons | definitions:65-98; filter_row:50.
# Site refusals and masks | tile_rule:139-177; placement:392-394.
# Materials/estimate/phases | item_row:224-226; queue:261,302,322; materials:348.
# Placement counts/refusals | placement:383-386,411-446,477,491-493.
# Stale selection refusal | construction.lua placement (standard list wording).
# Removal identities/messages | building_key:356-365; returned closure:515-538.
# Native decisions | stair_piece:134-135; placement:371,420,482,492;
# distance sorting incl. bins | screen:196-204; queue:288-307.
# Retired input refusal | returned closure:504; management_util.h:235.
# Builder accounting/caps | stats:247-248; queue:281; entry:328.
# Catalog revision high bit | revision:30; returned closure:506-510.
SOURCE = (Path(__file__).resolve().parents[1] / 'bridge/plugin/construction.lua').read_text()


class Adapter(unittest.TestCase):
    def test_native_reinforced_completed_and_queued_replacement(self):
        self.lua.execute("local e=df.construction_type;e._last_item=e._last_item+1;e[e._last_item]='ReinforcedWall';e.ReinforcedWall=e._last_item")
        self.reset()
        for shape,accepted in [('FLOOR',True),('RAMP',True),('STAIR_UPDOWN',False),('WALL',False)]:
            self.lua.execute("shape=df.tiletype_shape[...];df.tiletype.attrs[shape].material=df.tiletype_material.CONSTRUCTION;existing={}",shape)
            for width in (1,3):
                result=self.finish(action=1,definition='Construction:ReinforcedWall',width=width,height=width)
                self.assertEqual(bool(result['ok']),accepted,(shape,width))
        self.lua.execute("""
            shape=df.tiletype_shape.FLOOR;df.tiletype.attrs[shape].material=df.tiletype_material.SOIL
            occupied={['0:0:0']=true}
            queued={id=88,type=df.construction_type.Floor,jobs={{original_item=77}},
                getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end}
            dfhack.buildings.findAtTile=function()return queued end
            dfhack.buildings.markedForRemoval=function()return false end
        """)
        preview=self.finish(action=1,definition='Construction:ReinforcedWall')
        self.assertTrue(preview['ok']);self.assertEqual(preview['required'],0)
        self.assertEqual(len(preview['filters']),0)
        placed=self.finish(action=2,definition='Construction:ReinforcedWall')
        self.assertTrue(placed['ok'],placed['message']);self.assertEqual(placed['placed'],1)
        self.assertEqual(placed['first_building'],88);self.assertEqual(len(self.lua.globals().created),0)
        self.assertEqual(self.lua.globals().queued.type,self.lua.globals().df.construction_type.ReinforcedWall)
        self.assertEqual(self.lua.globals().queued.jobs[1].original_item,77)

    def test_native_ordinary_queued_replacement(self):
        for target in ('Floor','Wall','Ramp','Fortification'):
            for original in ('Floor','Wall','Ramp','Fortification'):
                self.reset()
                self.lua.execute("""
                    occupied={['0:0:0']=true}
                    queued={id=88,type=df.construction_type[...],jobs={{original_item=77}},
                        getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end}
                    dfhack.buildings.findAtTile=function()return queued end
                    dfhack.buildings.markedForRemoval=function()return false end
                """,original)
                preview=self.finish(action=1,definition='Construction:'+target)
                self.assertTrue(preview['ok'],(target,original,preview['message']))
                self.assertEqual(preview['required'],0)
                self.assertEqual(len(preview['filters']),0)
                placed=self.finish(action=2,definition='Construction:'+target)
                self.assertTrue(placed['ok'],placed['message'])
                self.assertEqual(placed['placed'],1)
                self.assertEqual(placed['first_building'],88)
                self.assertEqual(len(self.lua.globals().created),0)
                self.assertEqual(self.lua.globals().queued.type,self.lua.globals().df.construction_type[target])
                self.assertEqual(self.lua.globals().queued.jobs[1].original_item,77)

    def test_native_queued_mixed_material_accounting_and_stale_site(self):
        self.lua.execute("""
            occupied={['0:0:0']=true}
            queued={id=88,type=df.construction_type.Floor,jobs={{original_item=77}},
                getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end}
            dfhack.buildings.findAtTile=function(p)if p.x==0 then return queued end end
            dfhack.buildings.markedForRemoval=function()return false end
        """)
        request=dict(definition='Construction:Wall',width=2)
        preview=self.finish(action=1,**request)
        self.assertTrue(preview['ok']);self.assertEqual(preview['required'],1)
        selection=self.selection(**request)
        placed=self.finish(action=2,selections=[selection],**request)
        self.assertTrue(placed['ok'],placed['message']);self.assertEqual(placed['placed'],2)
        self.assertEqual(len(self.lua.globals().created),1)
        self.assertEqual(self.lua.globals().queued.jobs[1].original_item,77)
        self.lua.execute("queued.type=df.construction_type.Floor;flags.flow_size=2")
        refused=self.finish(action=2,definition='Construction:Wall')
        self.assertFalse(refused['ok'])
        self.assertEqual(self.lua.globals().queued.type,self.lua.globals().df.construction_type.Floor)

    def test_native_mixed_queued_cancel_and_commit(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/construction_paint_area.json.gz').read_bytes()))
        for row in data['queued_mixed']['rows']:
            self.setUp()
            before=row['before']
            self.lua.execute("""
                local original,id,job,item=...
                occupied={['0:0:0']=true}
                queued={id=id,type=df.construction_type[original],jobs={{id=job,original_item=item}},
                    getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end}
                dfhack.buildings.findAtTile=function(p)if p.x==0 then return queued end end
                dfhack.buildings.markedForRemoval=function()return false end
            """,row['existing'],before['id'],before['jobs'][0],before['items'][0])
            request=dict(definition='Construction:'+row['target'],width=2)
            preview=self.finish(action=1,**request)
            self.assertTrue(preview['ok']);self.assertEqual(preview['required'],1)
            if row['mode']=='manual_cancel':
                self.reset()
            else:
                selection=self.selection(**request)
                placed=self.finish(action=2,selections=[selection],**request)
                self.assertTrue(placed['ok']);self.assertEqual(placed['placed'],2)
            queued=self.lua.globals().queued
            self.assertEqual(queued.id,row['after']['id'])
            self.assertEqual(queued.type,self.lua.globals().df.construction_type[row['after']['subtype']])
            self.assertEqual(queued.jobs[1].id,row['after']['jobs'][0])
            self.assertEqual(queued.jobs[1].original_item,row['after']['items'][0])
            self.assertEqual(len(self.lua.globals().created),len(row['created']))

    def test_native_mixed_queued_stairs_cancel_and_commit(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/construction_paint_area.json.gz').read_bytes()))
        for row in data['queued_stairs']['rows']:
            self.setUp()
            before=row['before']
            self.lua.execute("""
                local original,z,id,job,item=...
                occupied={['0:0:'..z]=true}
                queued={id=id,type=df.construction_type[original],jobs={{id=job,original_item=item}},
                    getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end}
                dfhack.buildings.findAtTile=function(p)if p.z==z then return queued end end
                dfhack.buildings.markedForRemoval=function()return false end
            """,row['existing'],row['affected'],before['id'],before['jobs'][0],before['items'][0])
            request=dict(definition='Construction:Stairs',depth=3,
                         material_anchor=dict(x=0,y=0,z=0 if row['reverse'] else 2))
            preview=self.finish(action=1,**request)
            self.assertTrue(preview['ok'],row);self.assertEqual(preview['required'],2)
            if row['mode']=='manual_cancel':
                self.reset()
            else:
                selection=self.selection(count=2,**request)
                placed=self.finish(action=2,selections=[selection],**request)
                self.assertTrue(placed['ok'],placed['message']);self.assertEqual(placed['placed'],3)
            queued=self.lua.globals().queued
            self.assertEqual(queued.id,row['after']['id'])
            self.assertEqual(queued.type,self.lua.globals().df.construction_type[row['after']['subtype']],row)
            self.assertEqual(queued.jobs[1].id,row['after']['jobs'][0])
            self.assertEqual(queued.jobs[1].original_item,row['after']['items'][0])
            created=list(self.lua.globals().created.values())
            self.assertEqual(len(created),len(row['created']))
            expected={v['position']['z']-165:v['subtype'] for v in row['created']}
            for building in created:
                self.assertEqual(building['subtype'],self.lua.globals().df.construction_type[expected[building['pos']['z']]])

    def test_native_queued_stair_endpoint_connections(self):
        cases=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))['queued_replacement']['cases']
        for case in cases:
            self.reset()
            self.lua.execute("""
                local original,opposite=...
                occupied={['0:0:0']=true,['0:0:1']=true,['0:0:2']=true};queued={}
                for z=0,2 do queued[z]={id=88+z,type=df.construction_type[original],jobs={{original_item=77+z}},
                    getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end} end
                dfhack.buildings.findAtTile=function(p)return queued[p.z]end
                dfhack.buildings.markedForRemoval=function()return false end
                dfhack.maps.getTileType=function(p)return opposite and df.tiletype_shape[({'STAIR_DOWN','STAIR_UPDOWN','STAIR_UP'})[p.z+1]] or df.tiletype_shape.FLOOR end
            """,case['existing'],case['terrain']=='opposite_stairs')
            request=dict(definition='Construction:Stairs',depth=3,material_anchor=dict(x=0,y=0,z=0 if case['reverse'] else 2))
            preview=self.finish(action=1,**request)
            self.assertTrue(preview['ok'],preview['message']);self.assertEqual(preview['required'],0)
            placed=self.finish(action=2,**request)
            self.assertTrue(placed['ok'],placed['message']);self.assertEqual(placed['placed'],3)
            self.assertEqual(len(self.lua.globals().created),0)
            for z,piece in enumerate(case['after']):
                queued=self.lua.globals().queued[z]
                self.assertEqual(queued.type,self.lua.globals().df.construction_type[piece['subtype']],(case,z))
                self.assertEqual(queued.jobs[1].original_item,77+z)

    def test_queued_stairs_recheck_connection_after_incremental_scan(self):
        self.lua.execute("""
            occupied={['0:0:0']=true,['0:0:1']=true,['0:0:2']=true};queued={}
            for z=0,2 do queued[z]={id=88+z,type=df.construction_type.Floor,
                getType=function()return df.building_type.Construction end,getBuildStage=function()return 0 end} end
            dfhack.buildings.findAtTile=function(p)return queued[p.z]end
            dfhack.buildings.markedForRemoval=function()return false end
        """)
        self.seq+=1
        request=dict(action=2,definition='Construction:Stairs',depth=3)
        pending=self.call(step_budget=3,**request)
        self.assertTrue(pending['pending']);self.assertEqual(pending['placed'],0)
        self.lua.execute('queued[0].type=df.construction_type.DownStair;queued[2].type=df.construction_type.UpStair')
        for _ in range(10):
            result=self.call(step_budget=3,**request)
            if not result['pending']:break
        self.assertTrue(result['ok']);self.assertFalse(result['pending'])
        for z in range(3):self.assertEqual(self.lua.globals().queued[z].type,self.lua.globals().df.construction_type.UpDownStair)

    def test_native_reinforced_material_admission(self):
        evidence=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))['reinforced_admission_reference']
        self.lua.execute("local e=df.construction_type;e._last_item=e._last_item+1;e[e._last_item]='ReinforcedWall';e.ReinforcedWall=e._last_item")
        for case in evidence['cases']:
            self.reset()
            v=case['variant']; origin=case['origin']
            self.lua.globals().tag_x=v.get('x',-999)-origin['x']
            self.lua.globals().tag_y=v.get('y',-999)-origin['y']
            self.lua.globals().item_tag=v['item_group']
            self.lua.execute("""
                fill(1);stock[1].pos={x=10,y=10,z=0}
                dfhack.maps.getWalkableGroup=function()return 4464 end
                dfhack.maps.getTileBlock=function(p)
                    local g=p.x==10 and p.y==10 and item_tag or (p.x==tag_x and p.y==tag_y and 70000 or 80000)
                    return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return g end})end})}
                end
            """)
            anchor={k:case['anchor'][k]-origin[k] for k in ('x','y','z')}
            page=self.page(definition=case['definition'],width=case['width'],height=case['height'],material_anchor=anchor)
            self.assertTrue(page['ok'],page['message'])
            self.assertEqual(sum(r['count'] for r in page['materials'].values()),int(case['enabled']),(case['filter'],case['width'],anchor,v['name']))
        self.lua.execute('fill(1);stock[1].flags.on_ground=false')
        self.reset()
        self.lua.execute("dfhack.maps.getTileBlock=function(p)return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return 70000 end})end})}end")
        page=self.page(definition='Construction:ReinforcedWall')
        self.assertEqual(sum(r['count'] for r in page['materials'].values()),1)

    def test_native_paved_road_hidden_ground_materials(self):
        # Native road_placement: soil_all_hidden reserves the hidden patch stock.
        self.lua.execute('fill(3);flags.hidden=true')
        page=self.page(definition='RoadPaved',width=3,height=3)
        self.assertTrue(page['ok'],page['message'])
        self.assertEqual(sum(row['count'] for row in page['materials'].values()),3)

    def test_native_machine_full_width_admission(self):
        evidence=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))
        self.lua.execute("df.building_type=enum{'Chair','Workshop','Construction','Trap','SiegeEngine','Weapon','Bridge','Well','ScrewPump','WaterWheel','Windmill','RoadPaved','AxleHorizontal','Rollers'};df.siegeengine_type=enum{'Ballista','Catapult','BoltThrower'}")
        for case in evidence['machine_admission_reference']['cases']+evidence['variable_admission_reference']['cases']:
            self.reset()
            variant=dict(case['variant']);origin=case['origin']
            for axis in ('x','y','z'):variant[axis]=variant.get(axis,-999)-origin[axis]
            self.lua.globals().variant=self.lua.table_from(variant)
            self.lua.execute('''
                fill(1);stock[1].pos={x=10,y=10,z=0}
                dfhack.maps.getWalkableGroup=function()return 4464 end
                dfhack.maps.getTileBlock=function(p)
                    local g=p.x==10 and p.y==10 and variant.item_group or
                        ((variant.all or (p.x==variant.x and p.y==variant.y and p.z==variant.z)) and variant.group or 80000)
                    return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return g end})end})}
                end
            ''')
            page=self.page(definition=case['definition'],width=case['width'],height=case['height'],direction=case['direction'])
            self.assertTrue(page['ok'],page['message'])
            self.assertEqual(sum(r['count'] for r in page['materials'].values()),int(case['enabled']),(case['definition'],case['direction'],variant['name']))

    def test_native_pump_pointer_anchors_and_bolt_thrower_recipe(self):
        reference=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/machinery_directions.json').read_text(encoding='utf-8'))
        self.lua.execute('''
            df.building_type=enum{'Chair','Workshop','Construction','Trap','SiegeEngine','Weapon','Bridge','ScrewPump','WaterWheel'}
            df.siegeengine_type=enum{'Ballista','Catapult','BoltThrower'}
            local old=dfhack.buildings.getCorrectSize
            dfhack.buildings.getCorrectSize=function(w,h,t,st,c,dir)
                if t==df.building_type.ScrewPump then return false,dir%2==0 and 1 or 2,dir%2==0 and 2 or 1,dir==1 and 1 or 0,dir==2 and 1 or 0 end
                return old(w,h,t,st,c,dir)
            end
            local filters=dfhack.buildings.getFiltersByType
            dfhack.buildings.getFiltersByType=function(a,t,st,c)
                if t==df.building_type.SiegeEngine and st==df.siegeengine_type.BoltThrower then
                    return {{item_type=11},{item_type=22},{item_type=33},{item_type=44}}
                end
                return filters(a,t,st,c)
            end
        ''')
        self.reset()
        catalog={r['key']:r for r in self.call(action=0)['catalog'].values()}
        footprints={r['direction']:r for r in catalog['ScrewPump']['footprints'].values()}
        for case in reference['cases']:
            if case['definition']!='ScrewPump': continue
            shape,site=case['shape'],case['site'];f=footprints[case['direction']]
            self.assertEqual((f['center_x'],f['center_y']),(site['x']-shape['x1'],site['y']-shape['y1']))
            self.assertEqual((f['width'],f['height']),(shape['x2']-shape['x1']+1,shape['y2']-shape['y1']+1))
        self.assertEqual([f['item_type'] for f in catalog['SiegeEngine:BoltThrower']['filters'].values()],[11,33,44,22])

    def test_standard_workshop_native_admission(self):
        evidence=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))
        cases=evidence['workshop_admission_reference']['cases']
        cases+=evidence['utility_admission_reference']['cases']
        cases+=evidence['final_workshop_admission_reference']['cases']
        cases+=evidence['weapon_admission_reference']['cases']
        names=list(dict.fromkeys(['Chair','Workshop','Furnace','Construction','Trap','SiegeEngine','Weapon','Bridge']+[c['definition'] for c in cases if ':' not in c['definition']]))
        self.lua.globals().building_names=self.lua.table_from(names)
        self.lua.execute('df.building_type=enum(building_names)')
        self.lua.execute("df.trap_type=enum{'Lever','WeaponTrap','StoneFallTrap','CageTrap','TrackStop'}")
        self.lua.execute("customs[#customs+1]={id=91,code='SCREW_PRESS',name='Screw Press',class='workshop'};customs[#customs+1]={id=92,code='SOAP_MAKER',name='Soap Maker',class='workshop'};permitted_ids[#permitted_ids+1]=91;permitted_ids[#permitted_ids+1]=92")
        for family in ('Workshop','Furnace'):
            names=list(dict.fromkeys(c['definition'].split(':')[1] for c in cases if c['definition'].startswith(family+':')))
            self.lua.globals().names=self.lua.table_from(names)
            self.lua.execute('df.'+('workshop_type' if family=='Workshop' else 'furnace_type')+'=enum(names)')
        for case in cases[1:]: # First cold native query is a separately retained anomaly.
            self.reset()
            v=case['variant']; origin=case['origin']
            self.lua.globals().tag_x=v.get('x',-999)-origin['x']
            self.lua.globals().tag_y=v.get('y',-999)-origin['y']
            self.lua.globals().item_tag=v['item_group']
            self.lua.execute('''
                fill(1);stock[1].pos={x=10,y=10,z=0}
                dfhack.maps.getWalkableGroup=function()return 4464 end
                dfhack.maps.getTileBlock=function(p)
                    local g=p.x==10 and p.y==10 and item_tag or (p.x==tag_x and p.y==tag_y and 70000 or 80000)
                    return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return g end})end})}
                end
            ''')
            page=self.page(definition=case['definition'])
            self.assertTrue(page['ok'],(case['definition'],page['message']))
            self.assertEqual(sum(r['count'] for r in page['materials'].values()),int(case['enabled']),(case['definition'],v['name']))

    def test_additional_single_item_native_admission(self):
        reference=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))
        fixture={'cases':reference['additional_single_item_admission']['cases']+reference['remaining_single_item_admission']['cases']}
        names=list(dict.fromkeys(c['definition'] for c in fixture['cases'] if ':' not in c['definition']))
        self.lua.globals().extra=self.lua.table_from(names)
        self.lua.execute("local names={'Chair','Workshop','Construction','Trap','SiegeEngine','Weapon','Bridge'};for _,name in ipairs(extra)do names[#names+1]=name end;df.building_type=enum(names)")
        self.lua.execute("df.workshop_type=enum{'Carpenters','Quern'};df.trap_type=enum{'Lever','WeaponTrap','PressurePlate'}")
        for case in fixture['cases']:
            self.reset()
            self.lua.globals().variant=self.lua.table_from(case['variant'])
            self.lua.execute('''
                fill(1);stock[1].pos={x=10,y=0,z=0}
                dfhack.maps.getWalkableGroup=function()return 4464 end
                dfhack.maps.getTileBlock=function(p)
                    local group=variant.item
                    if p.x==0 and p.y==0 then group=p.z==-1 and variant.below or p.z==1 and variant.above or variant.center
                    elseif math.abs(p.x)+math.abs(p.y)==1 then group=variant.neighbor end
                    return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return group end})end})}
                end
            ''')
            page=self.page(definition=case['definition'])
            self.assertTrue(page['ok'],(case['definition'],page['message']))
            self.assertEqual(sum(row['count'] for row in page['materials'].values()),int(case['enabled']),(case['definition'],case['variant']['name']))

    def test_improved_furniture_rows_keep_exact_identity(self):
        for malformed in (False, True):
            self.reset()
            self.lua.execute('''
                fill(3);df.item_type.CHAIR=0
                for i=1,3 do stock[i].pos.x=2;stock[i].isImproved=function()return i>1 end end
            ''')
            page=self.page()
            self.assertTrue(page['ok'],page['message'])
            rows=list(page['materials'].values())
            self.assertEqual([r['individual_id'] for r in rows],[-1,2,3])
            self.assertEqual([r['count'] for r in rows],[1,1,1])
            selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                count=1,individual_id=2,item_ids=[3 if malformed else 2],expected_list_revision=page['list_revision'])
            result=self.finish(action=2,selections=[selection])
            self.assertEqual(result['ok'],not malformed,result['message'])
            if not malformed:self.assertEqual(self.lua.globals().created[1]['items'][1]['id'],2)

    def setUp(self):
        self.lua = catalog_runtime()
        self.lua.execute(r'''
        df.item_type={TOOL=99,BAR=98};df.general_ref_type={CONTAINS_ITEM=0,CONTAINS_UNIT=1}
        df.job_item_vector_id.attrs={[0]={other=0},[1]={other=0}}
        df.tiletype_shape=enum{'FLOOR','WALL','EMPTY','RAMP','RAMP_TOP','STAIR_UP','STAIR_DOWN','STAIR_UPDOWN','FORTIFICATION','BOULDER','PEBBLES','TWIG','SAPLING','SHRUB','BROOK_TOP'}
        df.tiletype_shape_basic={Floor=0};df.tiletype_shape.attrs={}
        df.tiletype_material=enum{'STONE','SOIL','CONSTRUCTION','GRASS_LIGHT','GRASS_DARK','GRASS_DRY','GRASS_DEAD','PLANT'}
        df.tiletype={attrs={}};for i=0,df.tiletype_shape._last_item do
          df.tiletype_shape.attrs[i]={basic_shape=i==0 and 0 or 1}
          df.tiletype.attrs[i]={shape=i,material=0} end
        df.tile_liquid={Magma=1};df.building_bridgest={T_direction={Left=0,Right=1,Up=2,Down=3}}
        df.block_square_event_type={material_spatter=0};df.builtin_mats={MUD=0};df.matter_state={Solid=0}
        shape=0;adjacent_shape=0;flags={flow_size=0};occupied={};valid=true;free=true
        dfhack.maps={isValidTilePos=function()return valid end,
          getTileFlags=function(p)return flags,{building=occupied[p.x..':'..p.y..':'..p.z] and 1 or 0}end,
          getTileType=function(p)return (p.x<0 or p.y<0) and adjacent_shape or shape end,
          getWalkableGroup=walkable_group,
          getTileBlock=function()return {block_events={},walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return 1 end})end})}end}
        df.construction={find=function()return existing end}
        dfhack.with_finalize=finalize
        df.machine_tile_set={new=function()
          local function coords()return {resize=function()end}end
          return {tiles={x=coords(),y=coords(),z=coords()},
            can_connect={resize=function(t,n)for i=0,n-1 do t[i]={whole=0}end end},
            delete=function()end}
        end}
        dfhack.buildings.findAtTile=function()end
        df.delete=function()end
        dfhack.buildings.allocInstance=function()return {room={}}end
        dfhack.buildings.setSize=function(b,w,h,d)if not free then return false end;return true,w,h,w*h,w*h end
        dfhack.buildings.checkFreeTiles=function()return free end
        created={};dfhack.buildings.constructBuilding=function(v)
          created[#created+1]=v;for _,item in ipairs(v.items)do item.flags.in_job=true end
          return {id=100+#created} end
        dfhack.items={getContainer=function(i)return i.container end,getPosition=position,
          getGeneralRef=function()end,getSubtypeDef=function()end}
        dfhack.units={isDead=function()return false end,isActive=function()return true end,
          isCitizen=function()return true end,getPosition=position}
        dfhack.job={isSuitableItem=function()return true end,isSuitableMaterial=function()return true end}
        dfhack.matinfo={decode=function(i)if type(i)=='table' and i.nameless then return end
          return {getToken=function()return 'INORGANIC:GRANITE'end,
            toString=function()return type(i)=='table' and i.name or 'stone'end}end}
        df.global.world.raws.descriptors={colors={}}
        df.global.world.units={active=vec{{pos={x=0,y=0,z=0}}}}
        stock={};df.item={find=function(id)return stock[id]end}
        function fill(n,groups)
          stock={};local all={};for i=1,n do
            local item={id=i,flags={on_ground=true},pos={x=i%8,y=0,z=0},mat=groups and i-1 or 0,
              isAssignedToStockpile=function()return false end,getType=function()return 0 end,
              getSubtype=function()return -1 end,getMaterial=function()return 0 end,
              getColorWhetherDyedOrNot=function()return -1 end,getStackSize=function()return 1 end,
              getMaterialIndex=function(s)return s.mat end,isBuildMat=function()return true end}
            stock[i]=item;all[i]=item end
          df.global.world.items={other={[0]=vec(all)}}
        end
        fill(1024)
        ''')
        evidence=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/windmill.json').read_text())
        hooks=evidence['native_hookup_service']['cases'][0]['native_closed']['hooks']
        self.lua.execute("""
            local captured=...
            df.global.world.buildings={all=setmetatable({[0]={canConnectToMachine=function(_,info)
                return fixture_connect and fixture_connect(info) or false
            end}},{__len=function()return 1 end})}
            df.global.world.buildings.get_machine_hookup_list=function(_,info,kind,subtype,x1,y1,x2,y2,z,direction)
                if kind~=df.building_type.Windmill then
                    -- Synthetic native service result; live fixtures establish geometry.
                    hook_calls=(hook_calls or 0)+1
                    if fixture_hook then fixture_hook(info,kind,subtype,x1,y1,x2,y2,z,direction) end
                    return
                end
                assert(kind==df.building_type.Windmill and subtype==-1 and not direction)
                assert(x2-x1==2 and y2-y1==2)
                hook_calls=(hook_calls or 0)+1
                for i,h in ipairs(captured)do
                    info.tiles.x[i-1]=x1+1+h.x;info.tiles.y[i-1]=y1+1+h.y;info.tiles.z[i-1]=z+h.z
                    info.can_connect[i-1]={whole=h.bits}
                end
            end
        """,self.lua.table_from(hooks,recursive=True))
        self.seq=0
        self.reset()

    def reset(self):
        self.lua.execute('''
            dfhack.maps.getTileSize=function()return 192,192,193 end
            fixture_search=function(seeds,targets)
                local distances={}
                for _,p in ipairs(targets)do distances[#distances+1]={reachable=true,distance=p.x}end
                return {status=0,distances=distances}
            end
        ''')
        order=self.lua.execute((Path(__file__).resolve().parents[1]/'bridge/plugin/construction_material_order.lua').read_text())
        names=self.lua.eval("function(group,id)if id then return 'fixture item '..id end end")
        self.helper=self.lua.execute(SOURCE,None,None,order,None,None,names,self.lua.eval("function(p,family,width,height,subtype,x1,y1) if family=='BridgeTile' then if native_bridge then return native_bridge(p,subtype) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if subtype then if native_floor then ok,reason=native_floor(p) else ok=({FLOOR=true,BOULDER=true,PEBBLES=true,TWIG=true,SAPLING=true,SHRUB=true})[sh]==true;reason='Blocked at this location' end;if not ok then return false,reason=='' and '' or 'Needs to be anchored on edge',reason~='' end end;return true,'',true end;if family:match('SpecialTile$') then family=family:sub(1,-12);if native_special then return native_special(p,family,subtype) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if subtype then if native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end else floor_calls=(floor_calls or 0)+1;if native_floor then ok,reason=native_floor(p) elseif sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;return true,'',true end;if family:match('OpeningTile$') then family=family:sub(1,-12);if native_opening then return native_opening(p,family) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if family=='Support' then floor_calls=(floor_calls or 0)+1;if native_floor then ok,reason=native_floor(p) elseif sh~='FLOOR' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end elseif native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if family=='Well' or family=='Hatch' or family=='GrateFloor' or family=='BarsFloor' then support_calls=(support_calls or 0)+1;return not support_allowed or support_allowed[family]~=false,'fixture native support refusal',true end;return true,'',true end;if family=='PressurePlateTrigger' then if native_trigger then return native_trigger(subtype) end;return subtype.units or subtype.water or subtype.magma or subtype.track,'Need trigger type',true end;if family:match('FurnitureTile$') or family:match('OrdinaryTile$') then local ordinary=family:match('OrdinaryTile$')~=nil;family=family:sub(1,ordinary and -13 or -14);if ordinary and native_ordinary then return native_ordinary(p,family) end;if not ordinary and native_furniture then return native_furniture(p,family) end;floor_calls=(floor_calls or 0)+1;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if native_floor then ok,reason=native_floor(p) elseif sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if (family=='Bed' or family=='Chair' or family=='Table' or family=='Coffin' or family=='TractionBench') and f.outside then return false,'Must be inside',true end;if family=='Door' then door_calls=(door_calls or 0)+1;return door_allowed~=false,'fixture native Door refusal',true end;return true,'',true end;if family=='FarmPlotTile' or family=='RoadDirtTile' or family=='RoadPavedTile' then terrain_calls=(terrain_calls or 0)+1;family=family:sub(1,-5);if native_extent_tile then return native_extent_tile(p,family) end;local raw,reason=true,'';if native_terrain then raw,reason=native_terrain(p,family) end;if not raw then return false,reason,reason~='',false end;local f,occ=dfhack.maps.getTileFlags(p);local depth=f.flow_size or 0;local magma=f.liquid_type==true or f.liquid_type==1;if depth>1 and not magma then return false,'Water at this location',true,true end;if depth>0 and magma then return false,'Lava/Magma at this location',true,true end;if occ.building~=0 then return false,'Building present',true,true end;return true,'',true,true end;if family=='FarmPlotWarning' then if native_warning then return native_warning(p,width,height,subtype) end;return false,'',true end;if family:match('Connectivity$') then if native_connectivity then return native_connectivity() end;return true,'' end;if family=='ConstructionTerrain' then if native_construction then return native_construction(p,width,height,subtype,x1,y1) end;local a=df.tiletype.attrs[dfhack.maps.getTileType(p)];local sh=df.tiletype_shape[a.shape];local f=dfhack.maps.getTileFlags(p);local ct=a.material==df.tiletype_material.CONSTRUCTION;if sh=='WALL' or sh=='FORTIFICATION' then return false,ct and 'Must remove construction' or 'Blocked at this location' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location' end;if f.flow_size>1 then return false,'Water at this location' end;if ct and (sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN') and subtype~=df.construction_type.UpDownStair then return false,'Must remove construction' end;return true,'' end;if family=='BridgePerimeter' then if native_perimeter then local ok,reason,verified=native_perimeter(p,width,height);return ok,reason,verified~=false end;return true,'',true end;if family=='OpenTerrain' then if native_open then return native_open(p) end;return df.tiletype.attrs[dfhack.maps.getTileType(p)].shape~=df.tiletype_shape.WALL and df.tiletype.attrs[dfhack.maps.getTileType(p)].shape~=df.tiletype_shape.FORTIFICATION,'Blocked at this location' end;if family=='SinglePerimeter' then if native_single_perimeter then return native_single_perimeter() end;return perimeter_allowed~=false,'Needs walkable perimeter',true end;if family=='FloorTerrain' then floor_calls=(floor_calls or 0)+1;if native_floor then return native_floor(p) end;local f=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];return not (sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1))),'Blocked at this location' end;if family=='FarmPlot' or family=='RoadDirt' or family=='RoadPaved' then terrain_calls=(terrain_calls or 0)+1;if native_terrain then return native_terrain(p,family) end;return true,'' end; if family=='Door' then door_calls=(door_calls or 0)+1;return door_allowed~=false,'fixture native Door refusal' end;support_calls=(support_calls or 0)+1;return not support_allowed or support_allowed[family]~=false,'fixture native support refusal' end"))

    def test_furniture_eligibility_uses_site_not_citizen_group(self):
        # Native furniture_material_copy evidence: citizens group47, site and
        # eligible furniture group2690. A citizen's absence cannot hide beds.
        self.lua.execute('''
            fill(2);df.item_type.CHAIR=0
            df.global.world.units.active[0].pos={x=100,y=0,z=0}
            dfhack.maps.getWalkableGroup=function(p)return p.x==100 and 47 or 2690 end
            dfhack.maps.getTileBlock=function(p)
                return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return p.x==100 and 47 or 2690 end})end})}
            end
        ''')
        self.reset()
        page=self.page()
        self.assertTrue(page['ok'])
        self.assertEqual(page['materials'][1]['count'],2)

    def test_common_furniture_site_group_eligibility(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/furniture_material_copy.json').read_text(encoding='utf-8'))['common_furniture_site_groups']
        for case in fixture['cases']:
            # The capture created IDs48809..48818; older items have separate flag/containment facts.
            candidates=[v for v in case['candidates'] if v['id']>=48809]
            self.reset()
            self.lua.globals().site_group=case['site_group']
            self.lua.globals().neighbor_groups=self.lua.table_from(case['cardinal_groups'])
            self.lua.globals().candidate_group=candidates[0]['raw_group']
            self.lua.globals().fixture_kind=case['kind']
            self.lua.execute("""
                fill(2);for _,kind in ipairs{'CHAIR','COFFIN','CABINET','BOX','SLAB','STATUE'}do df.item_type[kind]=nil end;df.item_type[fixture_kind]=0
                for _,item in pairs(stock)do item.pos={x=10+item.id,y=0,z=0}end
                df.global.world.units.active[0].pos={x=100,y=0,z=0}
                dfhack.maps.getWalkableGroup=function()return 47 end
                dfhack.maps.getTileBlock=function(p)
                    local group=candidate_group
                    if p.x==0 and p.y==0 then group=site_group
                    elseif p.x==0 and p.y==-1 then group=neighbor_groups[1]
                    elseif p.x==0 and p.y==1 then group=neighbor_groups[2]
                    elseif p.x==-1 and p.y==0 then group=neighbor_groups[3]
                    elseif p.x==1 and p.y==0 then group=neighbor_groups[4] end
                    return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return group end})end})}
                end
            """)
            page=self.page()
            self.assertTrue(page['ok'],page['message'])
            count=sum(r['count'] for r in page['materials'].values())
            self.assertEqual(count,sum(v['enabled']!=0 for v in candidates),(case['kind'],case['variant']))

    def test_furniture_walkable_groups_preserve_high_bits(self):
        self.lua.execute('''
            fill(2);df.item_type.CHAIR=0
            -- Both groups alias under the uint16 convenience API.
            dfhack.maps.getWalkableGroup=function()return 47 end
            dfhack.maps.getTileBlock=function(p)
                return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return p.x==0 and 65583 or 47 end})end})}
            end
        ''')
        self.reset()
        page=self.page()
        self.assertTrue(page['ok'])
        self.assertEqual(len(page['materials']),0)

    def test_native_stairs_preserve_endpoint_connections(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))
        shapes={'StoneFloorSmooth':'FLOOR','StoneStairU':'STAIR_UP','StoneStairD':'STAIR_DOWN','StoneStairUD':'STAIR_UPDOWN','OpenSpace':'EMPTY'}
        pieces={'UpStair':1,'DownStair':2,'UpDownStair':3}
        for capture in fixture['cases']:
            case=capture['case'];self.reset()
            self.lua.globals().bottom=shapes[case['bottom']]
            self.lua.globals().top=shapes[case['top']]
            self.lua.globals().height=case['depth']
            self.lua.execute("""
                fill(8);created={}
                dfhack.maps.getTileType=function(p)
                    if p.z==0 then return df.tiletype_shape[bottom] end
                    if p.z==height-1 then return df.tiletype_shape[top] end
                    return df.tiletype_shape.FLOOR
                end
            """)
            preview=self.finish(action=1,definition='Construction:Stairs',depth=case['depth'])
            expected=[v.get('subtype') for v in capture['pieces']]
            if case['depth']==1:
                self.assertFalse(preview['ok']);self.assertEqual(expected,[None]);continue
            self.assertTrue(preview['ok'],preview['message'])
            self.assertEqual(list(preview['pieces'].values()),[pieces[v] for v in expected])
            page=self.page(definition='Construction:Stairs',depth=case['depth'])
            selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=3,expected_list_revision=page['list_revision'])
            placed=self.finish(action=2,definition='Construction:Stairs',depth=case['depth'],selections=[selection])
            self.assertTrue(placed['ok'],placed['message'])
            actual=[self.lua.globals().df.construction_type[v['subtype']] for v in self.lua.globals().created.values()]
            self.assertEqual(actual,expected)

    def test_native_stairs_area_and_completed_rebuild(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))['rebuild_area_reference']
        shapes={'UpStair':'STAIR_UP','DownStair':'STAIR_DOWN','UpDownStair':'STAIR_UPDOWN','Floor':'FLOOR'}
        for capture in fixture['cases']:
            case=capture['case'];self.reset()
            completed=case.get('completed',[])
            self.lua.globals().shape_names=self.lua.table_from([shapes[v] for v in completed] if completed else ['FLOOR']*3)
            self.lua.globals().rebuilding=bool(completed)
            self.lua.execute("""
                fill(20);created={};existing=rebuilding and {} or nil
                for z=0,2 do df.tiletype.attrs[100+z]={shape=df.tiletype_shape[shape_names[z+1]],material=rebuilding and df.tiletype_material.CONSTRUCTION or 0}end
                dfhack.maps.getTileType=function(p)return 100+p.z end
            """)
            request=dict(definition='Construction:Stairs',width=case['width'],height=case['height'],depth=3)
            preview=self.finish(action=1,**request)
            self.assertTrue(preview['ok'],preview['message'])
            expected=[v['subtype'] for v in capture['pieces']]
            self.assertEqual(list(preview['valid_mask'].values()),[1]*len(expected))
            page=self.page(definition='Construction:Stairs',width=case['width'],height=case['height'],depth=3)
            selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=len(expected),expected_list_revision=page['list_revision'])
            placed=self.finish(action=2,selections=[selection],**request)
            self.assertTrue(placed['ok'],placed['message'])
            actual=[self.lua.globals().df.construction_type[v['subtype']] for v in self.lua.globals().created.values()]
            self.assertEqual(actual,expected,case['name'])

    def test_terrain_material_admission_uses_volume_and_last_corner(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))['material_admission_reference']
        names={'WALL':'Wall','FLOOR':'Floor','RAMP':'Ramp','FORTIFICATION':'Fortification','STAIR_UPDOWN':'Stairs'}
        for direction in ['forward','reverse']:
            for case in fixture[direction]['cases']:
                self.reset()
                self.lua.globals().levels=self.lua.table_from([self.lua.table_from({'center':r['center'],'neighbors':self.lua.table_from(r['neighbors'])}) for r in case['level_groups']])
                self.lua.globals().candidate_group=case['candidates'][0]['raw_group']
                self.lua.execute("""
                    fill(12)
                    for _,item in pairs(stock)do item.pos={x=10,y=0,z=0}end
                    dfhack.maps.getTileBlock=function(p)
                        local value=candidate_group
                        if p.x<10 then
                            value=0;local row=levels[p.z+1]
                            if row then
                                if p.x==0 and p.y==0 then value=row.center
                                elseif p.x==0 and p.y==-1 then value=row.neighbors[1]
                                elseif p.x==0 and p.y==1 then value=row.neighbors[2]
                                elseif p.x==-1 and p.y==0 then value=row.neighbors[3]
                                elseif p.x==1 and p.y==0 then value=row.neighbors[4] end
                            end
                        end
                        return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return value end})end})}
                    end
                """)
                depth=3 if case['kind']=='STAIR_UPDOWN' else 1
                anchor=dict(x=0,y=0,z=depth-1 if direction=='forward' else 0)
                page=self.page(definition='Construction:'+names[case['kind']],depth=depth,material_anchor=anchor)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual(sum(v['count'] for v in page['materials'].values()),sum(v['enabled']!=0 for v in case['candidates']),(direction,case['kind'],case['variant']))

    def test_stair_material_snapshot_rejects_other_endpoint_before_reserving(self):
        self.lua.execute('fill(6)')
        row=self.selection(3,definition='Construction:Stairs',depth=3,material_anchor=dict(x=0,y=0,z=2))
        refused=self.finish(action=2,definition='Construction:Stairs',depth=3,material_anchor=dict(x=0,y=0,z=0),selections=[row])
        self.assertFalse(refused['ok']);self.assertEqual(refused['message'],'List changed; refresh')
        self.assertEqual(len(self.lua.globals().created),0)
        placed=self.finish(action=2,definition='Construction:Stairs',depth=3,material_anchor=dict(x=0,y=0,z=2),selections=[row])
        self.assertTrue(placed['ok'],placed['message']);self.assertEqual(placed['placed'],3)

    def test_stair_preview_refreshes_volume_anchor_snapshot_while_paused(self):
        self.lua.execute("""
            fill(6);site_group=1
            for _,item in pairs(stock)do item.pos={x=10,y=0,z=0}end
            dfhack.maps.getTileBlock=function(p)
                local value=p.x>=10 and 1 or site_group
                return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return value end})end})}
            end
        """)
        request=dict(definition='Construction:Stairs',width=2,depth=3,material_anchor=dict(x=1,y=0,z=2))
        initial=self.page(**request);self.assertEqual(initial['materials'][1]['count'],6)
        self.lua.execute('site_group=2')
        self.assertTrue(self.finish(action=1,**request)['ok'])
        refreshed=self.page(**request)
        self.assertTrue(refreshed['ok'],refreshed['message'])
        self.assertEqual(len(refreshed['materials']),0)
        self.assertNotEqual(initial['list_revision'],refreshed['list_revision'])

    def test_native_terrain_navigation_seeds_and_exact_selection(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))['terrain_picker_reference']
        names={'WALL':'Wall','FLOOR':'Floor','RAMP':'Ramp','FORTIFICATION':'Fortification','STAIR_UPDOWN':'Stairs'}
        for capture in fixture['cases']:
            self.reset();case=capture['definition'];site=capture['site']
            rows=[dict(id=v['id'],x=v['position']['x']-site['x'],y=v['position']['y']-site['y'],z=v['position']['z']-site['z'],distance=v['native_distance']) for v in capture['candidates']]
            self.lua.globals().native=self.lua.table_from(rows,recursive=True)
            self.lua.globals().first_z=case['depth']-1 if case.get('reverse') else 0
            self.lua.globals().seed_count=case['width']*case['height']
            self.lua.execute("""
                fill(#native);created={};local remapped={};costs={}
                for i,row in ipairs(native)do
                    local item=stock[i];item.id=row.id;item.pos={x=row.x,y=row.y,z=row.z};remapped[item.id]=item
                    costs[row.x..':'..row.y..':'..row.z]=row.distance
                end
                stock=remapped
                fixture_search=function(seeds,targets)
                    assert(#seeds==seed_count)
                    for _,seed in ipairs(seeds)do assert(seed.z==first_z,'wrong gesture elevation seed')end
                    local result={};for _,p in ipairs(targets)do result[#result+1]={reachable=true,distance=assert(costs[p.x..':'..p.y..':'..p.z])}end
                    return {status=0,distances=result}
                end
            """)
            request=dict(definition='Construction:'+names[case['kind']],width=case['width'],height=case['height'],depth=case['depth'],material_anchor={axis:capture['anchor'][axis]-site[axis] for axis in ['x','y','z']})
            page=self.page(**request);self.assertTrue(page['ok'],page['message']);row=page['materials'][1]
            actual=[(v['id'],v['distance']) for v in row['candidates'].values()]
            expected=[(v['id'],v['distance']) for v in capture['expanded']['choices'] if v['kind']=='Specific']
            self.assertEqual(actual,expected,case['name'])
            quantity=case['width']*case['height']*case['depth']
            ids=[v[0] for v in reversed(expected)][:quantity]
            selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=quantity,item_ids=ids,expected_list_revision=page['list_revision'])
            placed=self.finish(action=2,selections=[selection],**request)
            self.assertTrue(placed['ok'],placed['message'])
            self.assertEqual([b['items'][1]['id'] for b in self.lua.globals().created.values()],sorted(ids))

    def test_native_terrain_mixed_assignment_matches_each_tile(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/stairs_placement.json').read_text(encoding='utf-8'))
        names={'WALL':'Wall','FLOOR':'Floor','RAMP':'Ramp','FORTIFICATION':'Fortification','STAIR_UPDOWN':'Stairs'}
        for capture in fixture['terrain_options_reference']['cases']+fixture['terrain_area_options_reference']['cases']:
            for mode in ['closest_effects','mixed_effects']:
                self.reset();case=capture['definition'];site=capture['site'];effects=capture[mode]
                self.lua.globals().native=self.lua.table_from(effects,recursive=True)
                self.lua.execute("""
                    fill(#native);created={};local remapped={}
                    for i,row in ipairs(native)do
                        local item=stock[i];item.id=row.item_id;item.mat=row.mat_index;remapped[item.id]=item
                    end
                    stock=remapped
                """)
                request=dict(definition='Construction:'+names[case['kind']],width=case['width'],height=case['height'],depth=case['depth'])
                if case.get('name')=='reverse':request['material_anchor']={'x':0,'y':0,'z':0}
                else:request['material_anchor']={'x':case['width']-1,'y':case['height']-1,'z':case['depth']-1}
                page=self.page(**request);self.assertTrue(page['ok'],page['message'])
                selections=[]
                for row in page['materials'].values():
                    ids=[e['item_id'] for e in effects if e['mat_index']==row['mat_index']]
                    selections.append(dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=row['mat_index'],count=len(ids),item_ids=sorted(ids,reverse=True),expected_list_revision=page['list_revision']))
                selections.sort(key=lambda row:min(row['item_ids']),reverse=True)
                placed=self.finish(action=2,selections=selections,**request)
                self.assertTrue(placed['ok'],placed['message'])
                actual={(b['pos']['x'],b['pos']['y'],b['pos']['z']):b['items'][1]['id'] for b in self.lua.globals().created.values()}
                expected={tuple(e['position'][axis]-site[axis] for axis in ['x','y','z']):e['item_id'] for e in effects}
                self.assertEqual(actual,expected,(case,mode))

    def test_bridge_mixed_assignment_uses_native_sorted_item_set(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/bridge_placement.json').read_text(encoding='utf-8'))['native_last_material']
        for native in fixture['cases']:
            self.reset();self.lua.globals().native=self.lua.table_from(native['items'])
            self.lua.execute("""
                fill(#native);created={};local remapped={};recipes[df.building_type.Bridge]={{quantity=-1,vector_id=1}}
                for i,id in ipairs(native)do local item=stock[i];item.id=id;item.mat=id<48841 and 172 or 167;remapped[id]=item end
                stock=remapped
            """)
            request=dict(definition='Bridge',width=3,height=3)
            page=self.page(**request);self.assertTrue(page['ok'],page['message']);selections=[]
            for row in page['materials'].values():
                ids=[v['id'] for v in row['candidates'].values()]
                selections.append(dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=row['mat_index'],count=len(ids),item_ids=sorted(ids,reverse=True),expected_list_revision=page['list_revision']))
            selections.sort(key=lambda row:min(row['item_ids']),reverse=True)
            result=self.finish(action=2,selections=selections,**request);self.assertTrue(result['ok'],result['message'])
            actual=[v['id'] for v in self.lua.globals().created[1]['items'].values()]
            self.assertEqual(actual,native['items'])

    def test_native_candidate_admission_and_fresh_reservation(self):
        for family in ('Bed','Chair','Table','Coffin','Cabinet','Box','Statue','Slab','Cage','Chain','Door','Hatch','GrateWall','GrateFloor','Floodgate','Armorstand','Weaponrack','TractionBench','Bookcase','DisplayFurniture','OfferingPlace','Instrument','NestBox','Hive','AnimalTrap','WindowGlass','BarsVertical','BarsFloor','WindowGem','Support','ArcheryTarget','TradeDepot','Weapon','Bridge','RoadPaved','Workshop:Carpenters','Furnace:WoodFurnace'):
            for stale in (False,True):
                self.setUp()
                self.lua.execute("fill(2);local definition=...;local name,sub=definition:match('^([^:]+):(.+)$');name=name or definition;local e=df.building_type;if e[name]==nil then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end;native_request_type=e[name];if sub then local st=name=='Workshop' and df.workshop_type or df.furnace_type;if st[sub]==nil then st._last_item=st._last_item+1;st[st._last_item]=sub;st[sub]=st._last_item end end;recipes[native_request_type]={{item_type=0,quantity=1}};stock[1].flags.hostile=true;stock[1].flags.on_ground=false;allow_native=true",family)
                self.reset()
                query=self.lua.eval("function(t)assert(t==native_request_type);return {status=0,candidates={allow_native and {1} or {}}}end")
                request=dict(definition=family,native_material_candidates=query)
                if family.startswith('Workshop:'):request.update(width=3,height=3)
                page=self.page(**request)
                self.assertTrue(page['ok'],(family,page['message']))
                self.assertEqual([x['id'] for x in page['materials'][1]['candidates'].values()],[1],family)
                if stale:self.lua.execute('allow_native=false')
                selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=1,item_ids=[1],expected_list_revision=page['list_revision'])
                placed=self.finish(action=2,selections=[selection],**request)
                self.assertEqual(bool(placed['ok']),not stale,(family,placed['message']))
                self.assertEqual(len(self.lua.globals().created),0 if stale else 1)
                if not stale:self.assertEqual(self.lua.globals().created[1]['items'][1]['id'],1)

    def test_native_custom_recipe_identity_and_stale_admission(self):
        self.lua.execute("""
            fill(3);customs[1].code='SCREW_PRESS';customs[2].code='SOAP_MAKER';customs[2].class='workshop'
            native_id1=customs[1].id;native_id2=customs[2].id
            dfhack.buildings.getFiltersByType=function()return {{item_type=0,quantity=1}}end
            stock[1].flags.hostile=true;stock[2].flags.hostile=true;allow_native=true
        """)
        self.reset()
        query=self.lua.eval("""function(t,st,custom_id)
            assert(t==df.building_type.Workshop and st==df.workshop_type.Custom)
            assert(custom_id==native_id1 or custom_id==native_id2)
            return {status=0,candidates={allow_native and {custom_id==native_id1 and 1 or 2} or {}}}
        end""")
        requests=[]
        for name,item_id in [('SCREW_PRESS',1),('SOAP_MAKER',2)]:
            request=dict(definition='Workshop:Custom:'+name,width=3,height=3,native_material_candidates=query)
            page=self.page(**request)
            self.assertTrue(page['ok'],page['message'])
            self.assertEqual([row['id'] for row in page['materials'][1]['candidates'].values()],[item_id])
            selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=1,
                           item_ids=[item_id],expected_list_revision=page['list_revision'])
            requests.append((request,selection))
        request,selection=requests[0]
        placed=self.finish(action=2,selections=[selection],**request)
        self.assertTrue(placed['ok'],placed['message'])
        self.assertEqual(self.lua.globals().created[1]['custom'],self.lua.globals().native_id1)
        self.lua.execute('allow_native=false')
        request,selection=requests[1]
        refused=self.finish(action=2,selections=[selection],**request)
        self.assertFalse(refused['ok'])
        self.assertEqual(len(self.lua.globals().created),1)

    def test_native_candidate_requirements_remain_separate(self):
        for stale in (False, True):
            self.setUp()
            self.lua.execute("""
                fill(4);recipes[df.building_type.ScrewPump]={
                    {item_type=0,quantity=1},{item_type=0,quantity=1},{item_type=0,quantity=1}}
                for _,item in ipairs(stock)do item.flags.hostile=true end
                allow_last=true
            """)
            query=self.lua.eval("function()return {status=0,candidates={{3},{1},allow_last and {2} or {}}}end")
            request=dict(definition='ScrewPump',native_material_candidates=query)
            selections=[]
            for index,item_id in enumerate((3,1,2)):
                page=self.page(filter=index,**request)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual([x['id'] for x in page['materials'][1]['candidates'].values()],[item_id])
                selections.append(dict(filter=index,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                                       count=1,item_ids=[item_id],expected_list_revision=page['list_revision']))
            if stale:self.lua.execute('allow_last=false')
            placed=self.finish(action=2,selections=selections,**request)
            self.assertEqual(bool(placed['ok']),not stale,placed['message'])
            self.assertEqual(len(self.lua.globals().created),0 if stale else 1)
            if not stale:
                self.assertEqual([v['id'] for v in self.lua.globals().created[1]['items'].values()],[3,1,2])

    def test_native_bolt_thrower_requirements_remain_separate(self):
        for stale in (False, True):
            self.setUp()
            self.lua.execute("""
                fill(5);df.siegeengine_type=enum{'Ballista','Catapult','BoltThrower'};recipes[df.building_type.SiegeEngine]={
                    {item_type=0,quantity=1},{item_type=0,quantity=1},{item_type=0,quantity=1},{item_type=0,quantity=1}}
                for _,item in ipairs(stock)do item.flags.hostile=true end
                dfhack.buildings.getCorrectSize=function()return false,1,1,0,0 end
                allow_last=true
            """)
            self.reset()
            query=self.lua.eval("function()return {status=0,candidates={{4},{2},{1},allow_last and {3} or {}}}end")
            request=dict(definition='SiegeEngine:BoltThrower',native_material_candidates=query)
            selections=[]
            for index,item_id in enumerate((4,2,1,3)):
                page=self.page(filter=index,**request)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual([x['id'] for x in page['materials'][1]['candidates'].values()],[item_id])
                selections.append(dict(filter=index,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                                       count=1,item_ids=[item_id],expected_list_revision=page['list_revision']))
            if stale:self.lua.execute('allow_last=false')
            placed=self.finish(action=2,selections=selections,**request)
            self.assertEqual(bool(placed['ok']),not stale,placed['message'])
            self.assertEqual(len(self.lua.globals().created),0 if stale else 1)
            if not stale:
                self.assertEqual([v['id'] for v in self.lua.globals().created[1]['items'].values()],[4,2,1,3])

    def test_native_weapon_trap_variable_inputs_and_stale_admission(self):
        for stale in (False, True):
            self.setUp()
            self.lua.execute("""
                fill(5);recipes[df.building_type.Trap]={
                    {item_type=0,quantity=1},{item_type=0,quantity=1}}
                for _,item in ipairs(stock)do item.flags.hostile=true end
                allow_weapon=true
            """)
            query=self.lua.eval("""function(t,st)
                assert(t==df.building_type.Trap and st==df.trap_type.WeaponTrap)
                return {status=0,candidates={{4},allow_weapon and {1,2,3} or {1,3}}}
            end""")
            request=dict(definition='Trap:WeaponTrap',native_material_candidates=query)
            selections=[]
            for index,ids in enumerate(([4],[1,2,3])):
                page=self.page(filter=index,**request)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual([x['id'] for x in page['materials'][1]['candidates'].values()],ids)
                selections.append(dict(filter=index,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                                       count=len(ids),item_ids=ids,expected_list_revision=page['list_revision']))
            if stale:self.lua.execute('allow_weapon=false')
            placed=self.finish(action=2,selections=selections,**request)
            self.assertEqual(bool(placed['ok']),not stale,placed['message'])
            self.assertEqual(len(self.lua.globals().created),0 if stale else 1)
            if not stale:
                self.assertEqual([v['id'] for v in self.lua.globals().created[1]['items'].values()],[4,1,2,3])

    def test_native_fixed_quantity_overrides_legacy_recipe_and_fails_closed(self):
        self.lua.execute('fill(6);recipes[df.building_type.Windmill]={{item_type=0,quantity=1}};recipe_calls=0')
        query=self.lua.eval("function(t,st,c)assert(t==df.building_type.Windmill and st==-1 and c==-1);recipe_calls=recipe_calls+1;return {status=0,recipes={{count_required=4}}}end")
        request=dict(definition='Windmill',width=3,height=3,native_material_recipe=query)
        preview=self.finish(action=1,**request)
        self.assertTrue(preview['ok'],preview['message']);self.assertEqual(preview['required'],4)
        self.assertEqual(self.lua.globals().recipe_calls,1)
        selection=self.selection(count=1,definition='Windmill',width=3,height=3)
        refused=self.finish(action=2,selections=[selection],**request)
        self.assertFalse(refused['ok']);self.assertEqual(len(self.lua.globals().created),0)
        selection=self.selection(count=4,definition='Windmill',width=3,height=3)
        placed=self.finish(action=2,selections=[selection],**request)
        self.assertTrue(placed['ok'],placed['message'])
        self.assertEqual(len(self.lua.globals().created[1]['items']),4)
        self.assertEqual(self.lua.globals().recipe_calls,3)
        for value in ('nil','{status=1}','{status=0,recipes={}}','{status=0,recipes={{count_required=0}}}','{status=0,recipes={{count_required=32768}}}'):
            request['native_material_recipe']=self.lua.eval('function()return '+value+' end')
            failed=self.finish(action=1,**request);self.assertFalse(failed['ok'])

    def test_missing_native_fixed_quantity_callback_rejects_preview_and_place(self):
        for callback in (None, False, 1, 'not a callback'):
            for action in (1, 2):
                with self.subTest(callback=callback, action=action):
                    self.reset()
                    result=self.finish(action=action, native_material_recipe=callback)
                    self.assertFalse(result['ok'])
                    self.assertEqual(result['message'], '')
                    self.assertEqual(len(self.lua.globals().created), 0)

    def test_native_road_quantity_uses_mask_rechecks_and_fails_closed(self):
        self.lua.execute("df.new=function()return {}end;df.reinterpret_cast=function(_,p)return p end;fill(12);recipes[df.building_type.RoadPaved]={{quantity=-1,vector_id=1}};road_count=0;road_calls=0;native_terrain=function(p)return p.x~=0,'Blocked at this location' end")
        query=self.lua.eval("function(t,s,c,n)assert(t==df.building_type.RoadPaved and s==-1 and c==-1);road_count=n;road_calls=road_calls+1;return {status=0,recipes={{count_required=7}}}end")
        request=dict(definition='RoadPaved',width=3,height=3,native_material_recipe=query)
        preview=self.finish(action=1,**request)
        self.assertTrue(preview['ok'],preview['message']);self.assertEqual(preview['required'],7)
        self.assertEqual(self.lua.globals().road_count,6);self.assertEqual(self.lua.globals().road_calls,1)
        self.lua.execute("native_terrain=function()return true,'' end")
        refused=self.finish(action=2,selections=[],**request)
        self.assertFalse(refused['ok']);self.assertEqual(self.lua.globals().road_count,9)
        self.assertEqual(self.lua.globals().road_calls,2);self.assertEqual(len(self.lua.globals().created),0)
        for value in ('nil','{status=1}','{status=0,recipes={}}','{status=0,recipes={{count_required=0}}}','{status=0,recipes={{count_required=1.5}}}'):
            request['native_material_recipe']=self.lua.eval('function()return '+value+' end')
            self.assertFalse(self.finish(action=1,**request)['ok'])
        request['native_material_recipe']=False
        self.assertFalse(self.finish(action=1,**request)['ok'])

    def test_native_initial_quantity_does_not_replace_later_area_stage(self):
        self.lua.execute('recipes[df.building_type.Bridge]={{quantity=-1,vector_id=1}}')
        query=self.lua.eval("function()error('Initial recipe is not final area quantity')end")
        result=self.finish(action=1,definition='Bridge',width=3,height=3,native_material_recipe=query)
        self.assertTrue(result['ok'],result['message']);self.assertEqual(result['required'],3)

    def test_native_candidate_rechecked_after_reservation_yields(self):
        self.lua.execute("fill(1);recipes[df.building_type.Bed]={{item_type=0,quantity=1}};allow_native=true")
        query=self.lua.eval("function()return {status=0,candidates={allow_native and {1} or {}}}end")
        request=dict(definition='Bed',native_material_candidates=query)
        page=self.page(**request);self.assertTrue(page['ok'])
        selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=1,item_ids=[1],expected_list_revision=page['list_revision'])
        self.seq+=1
        pending=self.call(action=2,selections=[selection],step_budget=2,**request)
        self.assertTrue(pending['pending'])
        self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute('allow_native=false')
        result=self.call(action=2,selections=[selection],**request)
        self.assertFalse(result['ok'])
        self.assertEqual(len(self.lua.globals().created),0)

    def test_missing_native_candidate_callback_has_no_fallback(self):
        for callback in (None, False, 1, 'not a callback'):
            for action in (63, 2):
                with self.subTest(callback=callback, action=action):
                    self.reset()
                    result=self.finish(action=action, native_material_candidates=callback)
                    self.assertFalse(result['ok'])
                    self.assertEqual(result['message'], '')
                    self.assertEqual(len(self.lua.globals().created), 0)

    def test_native_candidate_result_is_not_refiltered_by_old_item_flags(self):
        # These deliberately contradictory synthetic flags verify delegation,
        # not which flags DF accepts. Recorded native collectors own that proof.
        flags=['dump','forbid','garbage_collect','hostile','on_fire','rotten','trader',
               'in_building','construction','in_job','owned','removed','encased','spider_web']
        query=self.lua.eval('function()return {status=0,candidates={{1}}}end')
        for flag in flags:
            with self.subTest(flag=flag):
                self.lua.execute('fill(2);stock[1].flags[...]=true',flag)
                self.reset()
                page=self.page(native_material_candidates=query)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual([v['id'] for v in page['materials'][1]['candidates'].values()],[1])

    def test_native_candidate_failure_has_no_legacy_fallback(self):
        self.lua.execute("fill(2);recipes[df.building_type.Bed]={{item_type=0,quantity=1}}")
        query=self.lua.eval("function()return {status=1}end")
        page=self.page(definition='Bed',native_material_candidates=query)
        self.assertFalse(page['ok'])
        self.assertEqual(page['message'],'')
        self.assertEqual(page['build_phase'],3)

    def test_exact_furniture_placement_preserves_farther_item(self):
        self.lua.execute('fill(2);df.item_type.CHAIR=0')
        page=self.page()
        self.assertTrue(page['ok'],page['message'])
        row=page['materials'][1]
        self.assertEqual([v['id'] for v in row['candidates'].values()],[1,2])
        selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                       count=1,item_ids=[2],expected_list_revision=page['list_revision'])
        for invalid in [[],[1,2],[9999]]:
            refused=self.finish(action=2,selections=[dict(selection,item_ids=invalid)])
            self.assertFalse(refused['ok'])
            self.assertEqual(len(self.lua.globals().created),0)
        placed=self.finish(action=2,selections=[selection])
        self.assertTrue(placed['ok'],placed['message'])
        self.assertEqual(self.lua.globals().created[1]['items'][1]['id'],2)

    def test_material_group_name_helper_reaches_generic_rows(self):
        self.lua.execute('fill(2)')
        names=self.lua.eval("function(row,id)if id then return 'fixture chair '..id end;assert(#row.ids==2);return 'native fixture chairs' end")
        order=self.lua.execute((Path(__file__).resolve().parents[1]/'bridge/plugin/construction_material_order.lua').read_text())
        self.helper=self.lua.execute(SOURCE,None,None,order,None,None,names)
        page=self.page()
        self.assertTrue(page['ok'])
        self.assertEqual(page['materials'][1]['name'],'native fixture chairs')

    def test_native_furniture_navigation_order_and_reserved_item(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/furniture_material_copy.json').read_text())
        for case in fixture['native_order_selection']['cases']:
            for expected in case['groups']:
                self.reset()
                self.lua.globals().recorded=self.lua.table_from(case['candidates'],recursive=True)
                self.lua.execute('''
                    fill(6);df.item_type.CHAIR=0;local all={};local costs={};stock={};created={}
                    for i,row in ipairs(recorded)do
                        local it=df.global.world.items.other[0][i-1]
                        it.id=row.id;it.pos=row.position;it.mat=row.mat_index
                        stock[it.id]=it;all[i]=it
                        costs[it.pos.x..':'..it.pos.y..':'..it.pos.z]=row.native_distance
                    end
                    df.global.world.items.other[0]=vec(all)
                    dfhack.maps.getTileBlock=function(p)
                        return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return 1 end})end})}
                    end
                    fixture_search=function(seeds,targets)
                        local distances={}
                        for _,p in ipairs(targets)do distances[#distances+1]={reachable=true,distance=costs[p.x..':'..p.y..':'..p.z]}end
                        return {status=0,distances=distances}
                    end
                ''')
                page=self.page()
                self.assertTrue(page['ok'],page['message'])
                by_id={r['id']:r for r in case['candidates']}
                self.assertEqual([r['mat_index'] for r in page['materials'].values()],
                                 [by_id[g['ids'][0]]['mat_index'] for g in case['groups']])
                selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,
                               mat_index=by_id[expected['ids'][0]]['mat_index'],count=1,
                               expected_list_revision=page['list_revision'])
                result=self.finish(action=2,selections=[selection])
                self.assertTrue(result['ok'],result['message'])
                self.assertEqual(self.lua.globals().created[1]['items'][1]['id'],expected['selection'][0])

    def test_furniture_navigation_failure_has_no_geometric_fallback(self):
        self.lua.execute('''
            fill(2);df.item_type.CHAIR=0
            dfhack.maps.getTileBlock=function(p)
                return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return 1 end})end})}
            end
            fixture_search=function()return {status=3}end
        ''')
        page=self.page()
        self.assertFalse(page['ok'])
        self.assertEqual(page['build_phase'],3)
        self.assertIsNone(page['materials'])

    def test_new_preview_refreshes_materials_while_paused(self):
        # Native furniture singleton/restored captures change membership on
        # reopening with no simulation tick advance.
        self.lua.execute('fill(2)')
        self.reset()
        before=self.page()
        self.assertEqual(before['materials'][1]['count'],2)
        self.lua.execute('stock[2].flags.forbid=true')
        preview=self.finish(action=1)
        self.assertTrue(preview['ok'])
        after=self.page()
        self.assertEqual(after['materials'][1]['count'],1)
        self.assertNotEqual(before['list_revision'],after['list_revision'])
        self.lua.execute('stock[2].flags.forbid=false')
        self.assertTrue(self.finish(action=1)['ok'])
        self.assertEqual(self.page()['materials'][1]['count'],2)

    def test_unmigrated_exact_ids_never_fall_back_to_aggregate_reservation(self):
        helper = self.lua.execute(SOURCE)
        for ids in [[], [3225]]:
            request = self.lua.table_from({'action': 2, 'definition': 'Workshop:Custom:PRESS', 'epoch': 7,
                'selections': self.lua.table_from([self.lua.table_from({'filter': 0, 'count': 1,
                    'expected_list_revision': 42, 'item_ids': self.lua.table_from(ids)})])})
            result = helper(request)
            self.assertFalse(result['ok'])
            self.assertEqual(result['message'], '')
            self.assertEqual(result['active_kinds'], 0)

    def test_track_material_snapshot_paging_revision_and_reset(self):
        self.lua.execute('''
        df.global.world.raws.descriptors={colors=vec{{id='IRON_GRAY'}}}
        dfhack.items.getSubtypeDef=function()end
        dfhack.matinfo.decode=function(_,index)return {getToken=function()return 'INORGANIC:FIXTURE_'..index end}end
        for _,item in pairs(stock)do
          item.getStackSize=function(s)return s.stack or 1 end
          item.getColorWhetherDyedOrNot=function(s)return s.color or -1 end
        end
        dfhack.maps.getTileSize=function()return 192,192,193 end
        native_reader=function()end
        calls=0;generation=0;unverified=false
        scan=function(path,limit)
          calls=calls+1;local rows={}
          for i=1,130 do rows[i]={id=i,name='fixture item '..i..':'..generation,position={x=i,y=2,z=3}}end
          return {status=0,candidates=rows}
        end
        ordering=function(snapshot,seed,search)
          if unverified then return {status=2}end
          local groups,costs={},{}
          for i=1,130 do
            groups[i]={item_type=0,item_subtype=-1,mat_type=0,mat_index=i,
              name='fixture group '..i,ids={i},expanded_ids={i},individual=false}
            costs[i]={id=i,distance=i}
          end
          return {status=0,groups=groups,candidate_distances=costs}
        end
        request={action=63,epoch=7,definition='Construction:Track',filter=0,x=1,y=2,z=3,
          connected_track_destination={x=4,y=2,z=3},
          route_track=function(reader,a,b,max)return {status=0,path={a,b}}end,
          plan_track=function()
            local pieces={}
            for i=1,2 do pieces[i]={x=i,y=2,z=3,action=0,building_id=-1,connections=12,
              expected_connections=0,expected_terrain_connections=0,expected_terrain_kind=0,
              ramp=false,expected_job_ramp=false,expected_terrain_ramp=false}end
            if changed_field then pieces[1][changed_field]=changed_value end
            return {verified=true,new_count=2,pieces=pieces}
          end,
          material_distances=function()end}
        ''')
        g = self.lua.globals()
        preflight = self.lua.execute((Path(__file__).resolve().parents[1] / 'bridge/plugin/construction_track_placement_plan.lua').read_text())
        helper = self.lua.execute(SOURCE, g.native_reader, g.scan, g.ordering, preflight)
        request = g.request
        first = helper(request)
        self.assertTrue(first['ok'])
        self.assertFalse(first['estimated'])
        self.assertEqual(first['total'], 130)
        self.assertEqual(len(first['materials']), 128)
        self.assertEqual(first['materials'][1]['candidates'][1]['id'], 1)
        appearance=first['materials'][1]['candidates'][1]['appearance']
        self.assertEqual(appearance['material_token'], 'INORGANIC:FIXTURE_0')
        self.assertEqual((appearance['stack'],appearance['flags'],appearance['color_token']),(1,0,''))
        revision = first['list_revision']
        request['cursor'] = first['next_cursor']
        request['expected_list_revision'] = revision
        second = helper(request)
        self.assertTrue(second['ok'])
        self.assertEqual(len(second['materials']), 2)
        self.assertEqual(second['next_cursor'], 0)
        self.assertEqual(g.calls, 1)
        placement = self.lua.table_from({k:v for k,v in request.items()})
        placement['action'] = 2
        placement['cursor'] = 0
        placement['selections'] = self.lua.table_from([
            self.lua.table_from({'filter':0,'item_type':0,'item_subtype':-1,'mat_type':0,
                'mat_index':i,'count':1,'expected_list_revision':revision,
                'item_ids':self.lua.table_from([i])}) for i in [2,1]])
        prepared = helper(placement)
        self.assertFalse(prepared['ok'])  # This fixture omits the commit executor.
        self.assertTrue(prepared['placement_valid'])
        self.assertEqual(g.calls, 2)  # Place acquired fresh semantic facts.
        g.changed_field, g.changed_value = 'connections', 15
        self.assertFalse(helper(placement)['placement_valid'])
        g.changed_field = None
        self.assertEqual(helper(request)['list_revision'], revision)  # Refusal kept retained page.
        self.assertEqual(g.calls, 3)  # Retained paging did not rescan.
        self.assertTrue(helper(placement)['placement_valid'])
        self.assertEqual(len(g.created), 0)
        request['expected_list_revision'] = revision + 1
        self.assertFalse(helper(request)['ok'])
        request['cursor'] = 0
        request['expected_list_revision'] = 0
        g.generation = 1
        refreshed = helper(request)
        self.assertNotEqual(refreshed['list_revision'], revision)
        baseline_revision = refreshed['list_revision']
        self.lua.execute('stock[1].stack=7;stock[1].color=0;stock[1].flags.artifact=true')
        changed_appearance=helper(request)
        self.assertNotEqual(changed_appearance['list_revision'],baseline_revision)
        changed=changed_appearance['materials'][1]['candidates'][1]['appearance']
        self.assertEqual((changed['stack'],changed['flags'],changed['color_token']),(7,32,'IRON_GRAY'))
        self.assertEqual((appearance['stack'],appearance['flags'],appearance['color_token']),(1,0,''))
        self.lua.execute('stock[1].stack=nil;stock[1].color=nil;stock[1].flags.artifact=false')
        self.assertEqual(helper(request)['list_revision'],baseline_revision)
        self.lua.execute("df.item_type.INSTRUMENT=0;df.job_skill={PLAY_KEYBOARD_INSTRUMENT=100,PLAY_STRINGED_INSTRUMENT=101,PLAY_WIND_INSTRUMENT=102,PLAY_PERCUSSION_INSTRUMENT=103};instrument_raw={id='FIXTURE_INSTRUMENT',music_skill=103,flags={PLACED_AS_BUILDING=true}};dfhack.items.getSubtypeDef=function()return instrument_raw end")
        instrument_page=helper(request)
        instrument=instrument_page['materials'][1]['candidates'][1]['appearance']
        self.assertEqual((instrument['instrument_family'],instrument['instrument_placed']),(3,1))
        self.lua.execute('instrument_raw.music_skill=100;instrument_raw.flags.PLACED_AS_BUILDING=false')
        portable=helper(request)
        self.assertNotEqual(portable['list_revision'],instrument_page['list_revision'])
        facts=portable['materials'][1]['candidates'][1]['appearance']
        self.assertEqual((facts['instrument_family'],facts['instrument_placed']),(0,0))
        self.assertEqual((instrument['instrument_family'],instrument['instrument_placed']),(3,1))
        self.lua.execute('df.item_type.INSTRUMENT=nil;dfhack.items.getSubtypeDef=function()end')
        self.assertEqual(helper(request)['list_revision'],baseline_revision)
        self.lua.execute('df.item_type.SLAB=0;stock[1].engraving_type=-1')
        slab_page=helper(request)
        self.assertEqual(slab_page['materials'][1]['candidates'][1]['appearance']['slab_engraving'],-1)
        self.lua.execute('stock[1].engraving_type=6')
        engraved=helper(request)
        self.assertNotEqual(engraved['list_revision'],slab_page['list_revision'])
        self.assertEqual(engraved['materials'][1]['candidates'][1]['appearance']['slab_engraving'],6)
        self.assertEqual(slab_page['materials'][1]['candidates'][1]['appearance']['slab_engraving'],-1)
        self.lua.execute('df.item_type.SLAB=nil;stock[1].engraving_type=nil')
        self.lua.execute("df.item_type.SMALLGEM=0;for _,item in ipairs(stock)do item.shape=-1 end;stock[1].shape=0;df.global.world.raws.descriptors.shapes={[0]={id='BAGUETTE_CUT_GEM'},{id='ROUND_BRILLIANT_CUT_GEM'},{id='sentinel'}}")
        gem_page=helper(request)
        self.assertEqual(gem_page['materials'][1]['candidates'][1]['appearance']['gem_shape_raw'],'BAGUETTE_CUT_GEM')
        self.lua.execute('stock[1].shape=1')
        changed_gem=helper(request)
        self.assertNotEqual(changed_gem['list_revision'],gem_page['list_revision'])
        self.assertEqual(gem_page['materials'][1]['candidates'][1]['appearance']['gem_shape_raw'],'BAGUETTE_CUT_GEM')
        self.lua.execute('df.item_type.SMALLGEM=nil;stock[1].shape=nil')

        self.assertEqual(helper(request)['list_revision'],baseline_revision)
        for field, value in [('x', 9), ('y', 9), ('z', 9), ('action', 1),
                             ('building_id', 123), ('connections', 15),
                             ('expected_connections', 4), ('expected_subtype', 9), ('expected_terrain_connections', 4),
                             ('expected_terrain_kind', 1), ('ramp', True),
                             ('expected_job_ramp', True), ('expected_terrain_ramp', True)]:
            with self.subTest(field=field):
                g.changed_field, g.changed_value = field, value
                changed = helper(request)
                self.assertTrue(changed['ok'])
                self.assertNotEqual(changed['list_revision'], baseline_revision)
        g.changed_field = None
        restored = helper(request)
        self.assertEqual(restored['list_revision'], baseline_revision)
        g.unverified = True
        self.assertFalse(helper(request)['ok'])
        helper(self.lua.table_from({'cancel_builders': True}))
        request['expected_list_revision'] = refreshed['list_revision']
        self.assertFalse(helper(request)['ok'])

        # Same production closure, now with the real commit executor injected.
        commit = self.lua.execute((Path(__file__).resolve().parents[1] / 'bridge/plugin/construction_track_commit.lua').read_text())
        self.lua.execute("""
        df.construction_type.TrackEW=99
        commit_calls={};fail_kind='';
        dfhack.buildings.constructBuilding=function(v)
          commit_calls[#commit_calls+1]=v
          if #commit_calls==2 and fail_kind=='reject' then return nil end
          if #commit_calls==2 and fail_kind=='throw' then error('fixture native exception')end
          return {id=100+#commit_calls}
        end
        """)
        g.unverified=False
        request['expected_list_revision']=0
        request['cursor']=0
        for failure, outcome, placed in [('',1,2),('reject',3,1),('throw',4,1)]:
            with self.subTest(commit=failure):
                g.commit_calls=self.lua.table();g.fail_kind=failure
                writer=self.lua.execute(SOURCE,g.native_reader,g.scan,g.ordering,preflight,commit)
                snap=writer(request)
                for selection in placement['selections'].values(): selection['expected_list_revision']=snap['list_revision']
                result=writer(placement)
                self.assertEqual(result['construction_outcome'],outcome)
                self.assertEqual(result['placed'],placed)
                self.assertEqual(result['ok'],outcome==1)
                self.assertEqual(g.commit_calls[1]['items'][1]['id'],1)
                self.assertEqual(g.commit_calls[2]['items'][1]['id'],2)
                self.assertEqual(g.commit_calls[1]['subtype'],99)
                self.assertEqual(result['failed_index'],-1 if outcome==1 else 2)
                self.assertEqual(writer(placement)['construction_outcome'],2)  # consumed cache forbids replay
                self.assertEqual(len(g.commit_calls),2)

        self.lua.execute("""
        df.construction_type.TrackE=98;df.job_type={ConstructBuilding=77}
        pending={id=200,type=98,x1=1,y1=2,z=3,stage=0,removing=false,jobs=vec{{id=300,job_type=77}},
          getType=function()return df.building_type.Construction end,
          getSubtype=function(b)return b.type end,getBuildStage=function(b)return b.stage end}
        df.building={find=function(id)if id==200 then return pending end end}
        dfhack.buildings.markedForRemoval=function(b)return b.removing end
        original_plan=request.plan_track
        request.plan_track=function(...)
          local plan=original_plan(...);plan.new_count=1
          local p=plan.pieces[1];p.action=1;p.building_id=200;p.expected_connections=4
          return plan
        end
        """)
        placement['plan_track']=g.request['plan_track']
        placement['selections']=self.lua.table_from([placement['selections'][1]])
        for defect in ['', 'stage', 'removing', 'position', 'job', 'subtype']:
            with self.subTest(pending=defect):
                g.fail_kind='';g.commit_calls=self.lua.table()
                g.pending['stage']=0;g.pending['removing']=False;g.pending['x1']=1
                g.pending['type']=98;g.pending['jobs'][0]['job_type']=77
                writer=self.lua.execute(SOURCE,g.native_reader,g.scan,g.ordering,preflight,commit)
                snapshot=writer(request)
                placement['selections'][1]['expected_list_revision']=snapshot['list_revision']
                if defect=='stage':g.pending['stage']=1
                if defect=='removing':g.pending['removing']=True
                if defect=='position':g.pending['x1']=9
                if defect=='job':g.pending['jobs'][0]['job_type']=88
                if defect=='subtype':g.pending['type']=99
                result=writer(placement)
                self.assertEqual(result['ok'],not defect)
                self.assertEqual(len(g.commit_calls),0 if defect else 1)
                if not defect:
                    self.assertEqual(result['placed'],1);self.assertEqual(result['updated'],1)
                    self.assertEqual(g.pending['type'],99);self.assertEqual(g.pending['jobs'][0]['id'],300)

        # All-reused routes need neither a prior material snapshot nor stock reads.
        self.lua.execute("""
        queued_jobs={}
        for i=1,2 do queued_jobs[200+i]={id=200+i,type=df.construction_type.Floor,x1=i,y1=2,z=3,stage=0,removing=false,jobs=vec{{id=300+i,job_type=77}},
          getType=function()return df.building_type.Construction end,getSubtype=function(b)return b.type end,getBuildStage=function(b)return b.stage end}end
        df.building.find=function(id)return queued_jobs[id]end
        no_materials=function()error('zero-input conversion read materials')end
        request.plan_track=function(...)
          local plan=original_plan(...);plan.new_count=0
          for i,p in ipairs(plan.pieces)do p.action=1;p.building_id=200+i;p.expected_connections=0;p.expected_subtype=df.construction_type.Floor end
          return plan
        end
        """)
        placement['plan_track']=g.request['plan_track'];placement['selections']=self.lua.table()
        for defect in ('','subtype','stage','removing'):
            for building in g.queued_jobs.values():
                building['type']=g.df.construction_type.Floor;building['stage']=0;building['removing']=False
            if defect=='subtype':g.queued_jobs[201]['type']=g.df.construction_type.Wall
            if defect=='stage':g.queued_jobs[201]['stage']=1
            if defect=='removing':g.queued_jobs[201]['removing']=True
            writer=self.lua.execute(SOURCE,g.native_reader,g.no_materials,g.no_materials,preflight,commit)
            result=writer(placement)
            self.assertEqual(result['ok'],not defect)
            if not defect:
                self.assertEqual(result['updated'],2);self.assertEqual(result['placed'],0)
                self.assertEqual(g.queued_jobs[201]['jobs'][0]['id'],301)
                self.assertEqual(g.queued_jobs[201]['type'],99)

    def test_connected_track_preview_preserves_order_and_payload_outcome(self):
        self.lua.execute('''
        dfhack.maps.getTileSize=function()return 192,192,193 end
        track_reader=function()return {loaded=false}end
        function preview_request(large)
          return {action=1,seq=99,epoch=7,definition='Construction:Track',x=9,y=2,z=3,
            connected_track_destination={x=0,y=2,z=3},
            route_track=function(reader,a,b,max)
              assert(reader==track_reader and a.x==9 and b.x==0 and max.x==191 and max.z==192)
              local path={a,b}
              if large then path={};for i=1,16385 do path[i]={x=i,y=2,z=3}end end
              return {status=0,path=path}
            end,
            plan_track=function(reader,path)
              assert(reader==track_reader and path[1].x==9 and path[2].x==0)
              return {verified=true,new_count=2}
            end}
        end
        ''')
        helper=self.lua.execute(SOURCE,self.lua.globals().track_reader)
        result=helper(self.lua.globals().preview_request(False))
        self.assertTrue(result['ok'])
        self.assertEqual(result['message'],'')
        self.assertTrue(result['placement_valid'])
        self.assertEqual(result['required'],2)
        self.assertEqual(result['track_preview']['path'][1]['x'],9)
        self.assertEqual(result['track_preview']['path'][2]['x'],0)
        result=helper(self.lua.globals().preview_request(True))
        self.assertEqual(result['track_preview']['status'],5)
        self.assertEqual(len(result['track_preview']['path']),0)
        self.assertFalse(result['placement_valid'])
        request=self.lua.globals().preview_request(False)
        request['plan_track']=self.lua.eval('function()return {verified=false}end')
        result=helper(request)
        self.assertEqual(result['track_preview']['status'],4)
        self.assertEqual(result['required'],0)
        request['plan_track']=self.lua.eval('function()return {verified=true,new_count=0}end')
        result=helper(request)
        self.assertTrue(result['placement_valid'])
        self.assertEqual(result['required'],0)
        self.assertEqual(len(result['filters']),0)

    def test_pressure_creature_examples_use_raw_facts_and_context(self):
        self.lua.execute('''
        df.game_mode={DWARF=0,ADVENTURE=1};df.global.gamemode=0
        df.global.plotinfo={race_id=-1}
        df.global.buildreq=setmetatable({}, {__index=function()error('native widget read')end})
        function pressure_raw(size,frequency,name,flags)
          return {adultsize=size,frequency=frequency,name={[0]=name},flags=flags or {},
                  caste=vec{{misc={adult_size=999999999}}}}
        end
        df.global.world.raws.creatures={all=vec{
          pressure_raw(1000,100,'first',{}),
          pressure_raw(1500,50,'second',{HAS_ANY_INTELLIGENT_LEARNS=true,HAS_ANY_INTELLIGENT_SPEAKS=true}),
          pressure_raw(1000,50,'third',{HAS_ANY_COMMON_DOMESTIC=true})}}
        ''')
        def first():
            result = self.helper(self.lua.table_from({'pressure_creatures': True}))
            self.assertTrue(result['ok'])
            self.assertEqual(len(result['pressure_creatures']), 200)
            return result['pressure_creatures'][1]
        self.assertEqual((first()['race_id'], first()['name']), (1, 'second'))
        self.lua.execute('df.global.plotinfo.race_id=2')
        self.assertEqual(first()['race_id'], 2)
        self.lua.execute('df.global.gamemode=1')
        self.assertEqual(first()['race_id'], 1)
        self.lua.execute('df.global.world.raws.creatures.all[1].frequency=49')
        self.assertEqual(first()['race_id'], 2)
        self.lua.execute('df.global.world.raws.creatures.all[2].flags.GENERATED=true')
        self.assertEqual(first()['race_id'], 1)
        self.lua.execute('df.global.world.raws.creatures.all[1].flags.EQUIPMENT=true')
        self.assertEqual(first()['race_id'], 0)
        self.lua.execute('df.global.world.raws.creatures.all[0].flags.DOES_NOT_EXIST=true')
        self.assertEqual((first()['race_id'], first()['name']), (-1, ''))

    def test_pressure_examples_are_captured_on_first_catalog_page_only(self):
        self.lua.execute("df.global.buildreq=setmetatable({}, {__index=function()error('native widget read')end})")
        result=self.call(action=0,cursor=0)
        self.assertTrue(result['ok'])
        self.assertEqual(len(result['pressure_creatures']),200)
        for i in range(1,201):
            row=result['pressure_creatures'][i]
            self.assertEqual((row['size'],row['race_id'],row['name']),(i*1000,-1,''))
        later=self.call(action=0,cursor=128,expected_list_revision=result['list_revision'])
        self.assertTrue(later['ok'])
        self.assertIsNone(later['pressure_creatures'])
        self.assertIsNone(self.finish(action=1)['pressure_creatures'])

    def test_pressure_creature_size_bands_and_final_native_ceiling(self):
        self.lua.execute('''
        df.game_mode={DWARF=0};df.global.gamemode=0;df.global.plotinfo={race_id=-1}
        function pressure_raw(size,frequency)
          return {adultsize=size,frequency=frequency,name={[0]='fixture'},flags={}}
        end
        df.global.world.raws.creatures={all=vec{
          pressure_raw(999,100),pressure_raw(1000,100),pressure_raw(1999,101),
          pressure_raw(2000,100),pressure_raw(200000999,100),pressure_raw(200001000,200),
          pressure_raw(3000,-300)}}
        ''')
        rows = self.helper(self.lua.table_from({'pressure_creatures': True}))['pressure_creatures']
        self.assertEqual(rows[1]['race_id'], 2)
        self.assertEqual(rows[2]['race_id'], 3)
        self.assertEqual(rows[3]['race_id'], -1)
        self.assertEqual(rows[200]['race_id'], 4)
        self.assertEqual(rows[200]['size'], 200000)

    def call(self, **kw):
        args=dict(action=63,epoch=7,definition='Chair',filter=0,cursor=0,x=0,y=0,z=0,seq=self.seq,
                  material_distances=self.lua.globals().fixture_search)
        args['native_material_candidates']=synthetic_native_candidates(self.lua)
        args.update(kw)
        if args['definition']=='RoadPaved' and 'native_material_recipe' not in args:
            # Synthetic native boundary; real quantity parity is captured live.
            args['native_material_recipe']=self.lua.eval("function(t,s,c,n)assert(n~=nil);return {status=0,recipes={{count_required=n//4+1}}}end")
        if 'native_material_recipe' not in args:
            args['native_material_recipe']=synthetic_native_recipe(self.lua)
        return self.helper(self.lua.table_from(args,recursive=True))

    def finish(self, **kw):
        self.seq+=1
        for _ in range(10000):
            result=self.call(**kw)
            if not result['pending']: return result
        self.fail('operation did not finish within deterministic step bound')

    def page(self, **kw):
        for _ in range(10000):
            result=self.call(**kw)
            self.assertFalse(result['pending'])
            if not result['ok'] or result['build_phase']==0: return result
            step=self.call(step=2048)
            self.assertLessEqual(step['steps'],2048)
        self.fail('materials builder did not finish')

    def selection(self, count=1, **kw):
        page=self.page(**kw)
        self.assertTrue(page['ok'],page['message'])
        return dict(filter=kw.get('filter',0),item_type=0,item_subtype=-1,mat_type=0,mat_index=0,
                    count=count,expected_list_revision=page['list_revision'])

    def refusal(self, message, **kw):
        result=self.finish(**kw)
        self.assertFalse(result['ok'])
        self.assertEqual(result['message'],message)
        return result

    def test_native_windmill_footprint_order_and_four_log_reservation(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/windmill.json').read_text())
        capture=fixture['native_material_distance_probe']['capture']
        self.lua.globals().recorded=self.lua.table_from(capture,recursive=True)
        self.lua.execute('''
            recipes[df.building_type.Windmill]={{item_type=0,quantity=4}}
            fill(#recorded.candidates);local all={};local costs={};stock={};created={}
            local groups={}
            for index,g in ipairs(recorded.groups)do for _,id in ipairs(g.ids)do groups[id]=index end end
            for i,row in ipairs(recorded.candidates)do
                local it=df.global.world.items.other[0][i-1]
                it.id=row.id;it.pos=row.position;it.mat=groups[it.id] or -1;it.flags.forbid=not row.enabled
                stock[it.id]=it;all[i]=it
                costs[it.pos.x..':'..it.pos.y..':'..it.pos.z]=row.native_distance
            end
            df.global.world.items.other[0]=vec(all)
            fixture_search=function(seeds,targets)
                assert(#seeds==9,'Windmill needs all footprint seeds')
                local seen={}
                for _,p in ipairs(seeds)do
                    assert(p.x>=0 and p.x<=2 and p.y>=0 and p.y<=2 and p.z==0)
                    seen[p.x..':'..p.y]=true
                end
                local n=0;for _ in pairs(seen)do n=n+1 end;assert(n==9)
                local distances={}
                for _,p in ipairs(targets)do distances[#distances+1]={reachable=true,distance=costs[p.x..':'..p.y..':'..p.z]}end
                return {status=0,distances=distances}
            end
        ''')
        page=self.page(definition='Windmill',width=3,height=3)
        self.assertTrue(page['ok'],page['message'])
        self.assertEqual([r['mat_index'] for r in page['materials'].values()],list(range(1,len(capture['groups'])+1)))
        selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=1,
                       count=4,expected_list_revision=page['list_revision'])
        placed=self.finish(action=2,definition='Windmill',width=3,height=3,selections=[selection])
        self.assertTrue(placed['ok'],placed['message'])
        # machine_reference records native job ordering separately from picker
        # click ordering: fixed recipes reserve their selected set in ID order.
        self.assertEqual([i['id'] for i in self.lua.globals().created[1]['items'].values()],sorted(capture['groups'][0]['selection']))

    def test_native_magma_footprint_order_and_reserved_block(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/magma_placement.json').read_text())
        capture=fixture['material_order']['cases'][1]
        self.lua.globals().recorded=self.lua.table_from(capture,recursive=True)
        self.lua.execute('''
            recipes[df.building_type.Furnace]={{item_type=0,quantity=1}}
            fill(#recorded.candidates);local all={};local costs={};stock={};created={}
            local groups={}
            for index,g in ipairs(recorded.groups)do for _,id in ipairs(g.ids)do groups[id]=index end end
            for i,row in ipairs(recorded.candidates)do
                local it=df.global.world.items.other[0][i-1]
                it.id=row.id;it.pos=row.position;it.mat=groups[it.id] or -1;it.flags.forbid=not row.enabled
                stock[it.id]=it;all[i]=it
                costs[it.pos.x..':'..it.pos.y..':'..it.pos.z]=row.native_distance
            end
            df.global.world.items.other[0]=vec(all)
            fixture_search=function(seeds,targets)
                assert(#seeds==9,'Magma furnace needs all footprint seeds')
                local seen={}
                for _,p in ipairs(seeds)do
                    assert(p.x>=0 and p.x<=2 and p.y>=0 and p.y<=2 and p.z==0)
                    seen[p.x..':'..p.y]=true
                end
                local n=0;for _ in pairs(seen)do n=n+1 end;assert(n==9)
                local distances={}
                for _,p in ipairs(targets)do distances[#distances+1]={reachable=true,distance=costs[p.x..':'..p.y..':'..p.z]}end
                return {status=0,distances=distances}
            end
        ''')
        page=self.page(definition='Furnace:MagmaSmelter',width=3,height=3)
        self.assertTrue(page['ok'],page['message'])
        self.assertEqual([r['mat_index'] for r in page['materials'].values()],list(range(1,len(capture['groups'])+1)))
        selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=1,
                       count=1,expected_list_revision=page['list_revision'])
        placed=self.finish(action=2,definition='Furnace:MagmaSmelter',width=3,height=3,selections=[selection])
        self.assertTrue(placed['ok'],placed['message'])
        self.assertEqual([i['id'] for i in self.lua.globals().created[1]['items'].values()],capture['groups'][0]['selection'][:1])

    def test_windmill_exact_selection_never_substitutes_another_log(self):
        for change in ['', 'stock[5].flags.forbid=true', 'stock[5].mat=3']:
            with self.subTest(change=change):
                self.reset()
                self.lua.execute('fill(6);created={};recipes[df.building_type.Windmill]={{item_type=0,quantity=4}}')
                selection=self.selection(4,definition='Windmill',width=3,height=3)
                selection['item_ids']=[1,2,5,6]
                self.lua.execute(change)
                result=self.finish(action=2,definition='Windmill',width=3,height=3,selections=[selection])
                self.assertEqual(bool(result['ok']),not change)
                if change:
                    self.assertEqual(len(self.lua.globals().created),0)
                else:
                    self.assertEqual([i['id'] for i in self.lua.globals().created[1]['items'].values()],[1,2,5,6])
        for ids in [[1,1,2,3],[1,2,3,999],[1,2,3]]:
            self.reset()
            self.lua.execute('fill(6);created={};recipes[df.building_type.Windmill]={{item_type=0,quantity=4}}')
            selection=self.selection(4,definition='Windmill',width=3,height=3)
            selection['item_ids']=ids
            self.assertFalse(self.finish(action=2,definition='Windmill',width=3,height=3,selections=[selection])['ok'])
            self.assertEqual(len(self.lua.globals().created),0)

    def test_windmill_candidate_payload_pages_complete_groups(self):
        self.lua.execute('fill(2048);for i,it in pairs(stock)do it.mat=(i-1)//512 end')
        # Long sourced descriptions force the byte budget before the row cap.
        names=self.lua.eval("function(group,id)if id then return string.rep('x',128)end end")
        order=self.lua.execute((Path(__file__).resolve().parents[1]/'bridge/plugin/construction_material_order.lua').read_text())
        self.helper=self.lua.execute(SOURCE,None,None,order,None,None,names,self.lua.eval("function(p,family,width,height,subtype,x1,y1) if family=='BridgeTile' then if native_bridge then return native_bridge(p,subtype) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if subtype then if native_floor then ok,reason=native_floor(p) else ok=({FLOOR=true,BOULDER=true,PEBBLES=true,TWIG=true,SAPLING=true,SHRUB=true})[sh]==true;reason='Blocked at this location' end;if not ok then return false,reason=='' and '' or 'Needs to be anchored on edge',reason~='' end end;return true,'',true end;if family:match('SpecialTile$') then family=family:sub(1,-12);if native_special then return native_special(p,family,subtype) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if subtype then if native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end else floor_calls=(floor_calls or 0)+1;if native_floor then ok,reason=native_floor(p) elseif sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;return true,'',true end;if family:match('OpeningTile$') then family=family:sub(1,-12);if native_opening then return native_opening(p,family) end;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if family=='Support' then floor_calls=(floor_calls or 0)+1;if native_floor then ok,reason=native_floor(p) elseif sh~='FLOOR' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end elseif native_open then ok,reason=native_open(p) elseif sh=='WALL' or sh=='FORTIFICATION' then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location',true end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if family=='Well' or family=='Hatch' or family=='GrateFloor' or family=='BarsFloor' then support_calls=(support_calls or 0)+1;return not support_allowed or support_allowed[family]~=false,'fixture native support refusal',true end;return true,'',true end;if family=='PressurePlateTrigger' then if native_trigger then return native_trigger(subtype) end;return subtype.units or subtype.water or subtype.magma or subtype.track,'Need trigger type',true end;if family:match('FurnitureTile$') or family:match('OrdinaryTile$') then local ordinary=family:match('OrdinaryTile$')~=nil;family=family:sub(1,ordinary and -13 or -14);if ordinary and native_ordinary then return native_ordinary(p,family) end;if not ordinary and native_furniture then return native_furniture(p,family) end;floor_calls=(floor_calls or 0)+1;local f,occ=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];local ok,reason=true,'';if native_floor then ok,reason=native_floor(p) elseif sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1)) then ok,reason=false,'Blocked at this location' end;if not ok then return false,reason,reason~='' end;if f.flow_size>1 then return false,'Water at this location',true end;if occ.building~=0 then return false,'Building present',true end;if (family=='Bed' or family=='Chair' or family=='Table' or family=='Coffin' or family=='TractionBench') and f.outside then return false,'Must be inside',true end;if family=='Door' then door_calls=(door_calls or 0)+1;return door_allowed~=false,'fixture native Door refusal',true end;return true,'',true end;if family=='ConstructionTerrain' then if native_construction then return native_construction(p,width,height,subtype,x1,y1) end;local a=df.tiletype.attrs[dfhack.maps.getTileType(p)];local sh=df.tiletype_shape[a.shape];local f=dfhack.maps.getTileFlags(p);local ct=a.material==df.tiletype_material.CONSTRUCTION;if sh=='WALL' or sh=='FORTIFICATION' then return false,ct and 'Must remove construction' or 'Blocked at this location' end;if f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1) then return false,'Lava/Magma at this location' end;if f.flow_size>1 then return false,'Water at this location' end;if ct and (sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN') and subtype~=df.construction_type.UpDownStair then return false,'Must remove construction' end;return true,'' end;if family=='BridgePerimeter' then if native_perimeter then local ok,reason,verified=native_perimeter(p,width,height);return ok,reason,verified~=false end;return true,'',true end;if family=='OpenTerrain' then if native_open then return native_open(p) end;return df.tiletype.attrs[dfhack.maps.getTileType(p)].shape~=df.tiletype_shape.WALL and df.tiletype.attrs[dfhack.maps.getTileType(p)].shape~=df.tiletype_shape.FORTIFICATION,'Blocked at this location' end;if family=='SinglePerimeter' then if native_single_perimeter then return native_single_perimeter() end;return perimeter_allowed~=false,'Needs walkable perimeter',true end;if family=='FloorTerrain' then floor_calls=(floor_calls or 0)+1;if native_floor then return native_floor(p) end;local f=dfhack.maps.getTileFlags(p);local sh=df.tiletype_shape[df.tiletype.attrs[dfhack.maps.getTileType(p)].shape];return not (sh=='WALL' or sh=='FORTIFICATION' or sh=='EMPTY' or sh=='RAMP' or sh=='RAMP_TOP' or sh=='STAIR_UP' or sh=='STAIR_DOWN' or sh=='STAIR_UPDOWN' or f.flow_size==7 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==1))),'Blocked at this location' end;if family=='FarmPlot' or family=='RoadDirt' or family=='RoadPaved' then terrain_calls=(terrain_calls or 0)+1;if native_terrain then return native_terrain(p,family) end;return true,'' end; if family=='Door' then door_calls=(door_calls or 0)+1;return door_allowed~=false,'fixture native Door refusal' end;support_calls=(support_calls or 0)+1;return not support_allowed or support_allowed[family]~=false,'fixture native support refusal' end"))
        seen=[];cursor=0;revision=0
        while True:
            page=self.page(definition='Windmill',width=3,height=3,cursor=cursor,expected_list_revision=revision)
            self.assertTrue(page['ok'],page['message'])
            revision=page['list_revision']
            for row in page['materials'].values():
                self.assertEqual(len(row['candidates']),512)
                seen.extend(item['id'] for item in row['candidates'].values())
            self.assertLessEqual(len(page['materials']),2)
            cursor=page['next_cursor']
            if not cursor:break
        self.assertEqual(sorted(seen),list(range(1,2049)))

    def test_native_windmill_shapes_and_machine_hookups(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/windmill.json').read_text())
        for section,supported in [('ground_shapes',False),('machine_supported_shapes',True)]:
            for case in fixture[section]['cases']:
                with self.subTest(section=section,shape=case['variant']):
                    self.lua.execute('''
                        local name,supported=...
                        dfhack.maps.getTileType=function(p)
                            return p.x==1 and p.y==1 and df.tiletype_shape[name] or df.tiletype_shape.FLOOR
                        end
                        fixture_connect=function()return supported end
                    ''',case['variant'],supported)
                    result=self.finish(action=1,definition='Windmill',width=3,height=3)
                    self.assertEqual(bool(result['ok']),case['clicked_stage']=='STAGES')
        for case in fixture['native_hookup_service']['cases']:
            with self.subTest(hookup=case['variant']):
                self.lua.execute('''
                    local c=...
                    dfhack.maps.getTileType=function(p)
                        if c.variant=='gear_corner_wall' and p.x==0 and p.y==0 then return df.tiletype_shape.WALL end
                        if c.variant=='gear_center_floor' and p.x==1 and p.y==1 then return df.tiletype_shape.FLOOR end
                        return df.tiletype_shape.EMPTY
                    end
                    fixture_connect=function(info)
                        for i=0,8 do for _,h in ipairs(c.hookups)do
                            if info.tiles.x[i]==h.x+1 and info.tiles.y[i]==h.y+1 and
                               info.tiles.z[i]==h.z and (info.can_connect[i].whole & (1<<h.bit))~=0 then return true end
                        end end
                        return false
                    end
                ''',self.lua.table_from(case,recursive=True))
                result=self.finish(action=1,definition='Windmill',width=3,height=3)
                self.assertEqual(bool(result['ok']),case['clicked_stage']=='STAGES')

    def test_magma_unmarked_candidates_and_stale_inventory(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/magma_placement.json').read_text())
        native=fixture['unmarked_candidates']['candidates']
        self.assertEqual(len(native),304)
        self.assertTrue(all(c['enabled'] and c['raw_flags']==0 and not c['in_inventory'] for c in native))
        self.lua.execute('fill(1);stock[1].flags.on_ground=false')
        page=self.page(definition='Furnace:MagmaSmelter',width=3,height=3)
        self.assertEqual(page['materials'][1]['count'],1)
        selection=self.selection(definition='Furnace:MagmaSmelter',width=3,height=3)
        self.lua.execute('stock[1].flags.in_inventory=true')
        result=self.finish(action=2,definition='Furnace:MagmaSmelter',width=3,height=3,selections=[selection])
        self.assertFalse(result['ok'])
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_farm_gestures_and_irregular_extents(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/farm_placement.json').read_text())
        self.check_native_extent_gestures(fixture,'FarmPlot')

    def test_native_road_gestures_and_irregular_extents(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/road_placement.json').read_text())
        for family,cases in fixture['families'].items():
            self.reset()
            if family=='RoadPaved':self.lua.execute('recipes[df.building_type.RoadPaved]={{quantity=-1,vector_id=1}}')
            self.check_native_extent_gestures(cases,family)

    def check_native_extent_gestures(self, fixture, family):
        # Replay captured native mask decisions through the adapter contract.
        # Terrain classification itself is tested against the real DF routines.
        self.lua.execute("df.new=function(kind,count)assert(kind=='uint8_t');return {}end;df.reinterpret_cast=function(_,ptr)return ptr end")
        for case in fixture['cases']:
            with self.subTest(variant=case['variant']):
                self.lua.execute("created={}")
                accepted_anchor=case['first_selection']['x']!=-30000
                self.lua.execute("local ok=...;native_terrain=function()return ok,'fixture terrain refusal' end",accepted_anchor)
                x,y=(case['first_selection']['x']-fixture['origin']['x'],case['first_selection']['y']-fixture['origin']['y']) if accepted_anchor else (0,0)
                anchor=self.finish(action=1,definition=family,x=x,y=y,width=1,height=1)
                self.assertEqual(bool(anchor['ok']),accepted_anchor)
                if not case['buildings']:
                    self.lua.execute("native_terrain=function()return false,'fixture terrain refusal' end")
                    self.assertFalse(self.finish(action=1,definition=family,width=3,height=3)['ok'])
                    self.assertEqual(len(self.lua.globals().created),0)
                    continue
                building=case['buildings'][0]
                x=building['x1']-fixture['origin']['x'];y=building['y1']-fixture['origin']['y']
                w=building['x2']-building['x1']+1;h=building['y2']-building['y1']+1
                expected=[1 if v==-1 else v for v in building['extents']]
                self.lua.execute("""local x,y,w,mask=...;native_terrain=function(p)
                    return mask[(p.y-y)*w+p.x-x+1]==1,'fixture terrain refusal' end""",
                    x,y,w,self.lua.table_from(expected))
                preview=self.finish(action=1,definition=family,x=x,y=y,width=w,height=h)
                self.assertTrue(preview['ok'],preview['message'])
                self.assertEqual(list(preview['valid_mask'].values()),expected)
                if family=='RoadPaved':
                    self.assertEqual(preview['required'],sum(expected)//4+1)
                    continue
                placed=self.finish(action=2,definition=family,x=x,y=y,width=w,height=h)
                self.assertTrue(placed['ok'],placed['message'])
                fields=self.lua.globals().created[1]['fields']
                if 0 in expected:self.assertEqual([fields['room']['extents'][i] for i in range(w*h)],expected)
                else:self.assertIsNone(fields['room'])

    def test_native_reinforced_geometry(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/material_candidates.json').read_text(encoding='utf-8'))['reinforced_geometry_reference']['evidence']
        family="Construction:ReinforcedWall"
        self.lua.execute("local e=df.construction_type;e._last_item=e._last_item+1;e[e._last_item]='ReinforcedWall';e.ReinforcedWall=e._last_item")
        self.reset()
        self.lua.execute("""
            df.new=function(kind,count)assert(kind=='uint8_t');return {}end
            df.reinterpret_cast=function(_,ptr)return ptr end
            df.tiletype.attrs[100]={shape=0,material=df.tiletype_material.SOIL}
            df.tiletype.attrs[101]={shape=0,material=df.tiletype_material.STONE}
            df.tiletype.attrs[102]={shape=0,material=df.tiletype_material.GRASS_DARK}
            df.tiletype_shape.attrs[df.tiletype_shape.BOULDER].basic_shape=0
            df.tiletype_shape.attrs[df.tiletype_shape.PEBBLES].basic_shape=0
        """)
        for case in fixture['cases']:
            name=case['variant']
            with self.subTest(variant=name):
                self.lua.execute("""
                    local name=...;created={}
                    local stone=name:find('stone',1,true)==1 or name=='rough_stone_center_mud'
                    local base=stone and 101 or name=='soil_grass' and 102 or name=='boulder_all_mud' and df.tiletype_shape.BOULDER or name=='pebbles_all_mud' and df.tiletype_shape.PEBBLES or 100
                    dfhack.maps.getTileType=function(p)
                        if name=='stone_first_soil' and p.x==0 and p.y==0 or (name=='stone_last_soil' or name=='stone_last_soil_reverse') and p.x==2 and p.y==2 then return 100 end
                        if p.x==1 and p.y==1 then
                            local center={soil_center_stone=101,soil_center_wall=df.tiletype_shape.WALL,soil_center_empty=df.tiletype_shape.EMPTY,soil_center_ramp=df.tiletype_shape.RAMP,soil_center_stair=df.tiletype_shape.STAIR_UPDOWN}
                            return center[name] or base
                        end
                        return base
                    end
                    dfhack.maps.getTileFlags=function(p)
                        local at_center=p.x==1 and p.y==1
                        local flow=at_center and ({soil_water_one=1,soil_water_two=2,soil_magma_one=1,soil_magma_two=2})[name] or 0
                        if name=='soil_water_two_corner' and p.x==0 and p.y==0 then flow=2 end
                        return {flow_size=flow,hidden=name=='soil_all_hidden' or name=='soil_hidden_center' and at_center or name=='soil_hidden_first' and p.x==0 and p.y==0 or name=='soil_hidden_last' and p.x==2 and p.y==2,
                            liquid_type=name:find('magma',1,true)~=nil},{building=0}
                    end
                    dfhack.maps.getTileBlock=function(p)
                        local amount=0
                        if name:find('mud',1,true)then
                            local x,y=1,1
                            if name:find('elsewhere',1,true)then x,y=3,3 elseif name=='stone_first_mud' then x,y=0,0 elseif name=='stone_last_mud' then x,y=2,2 end
                            if name:find('all_mud',1,true) or p.x==x and p.y==y then amount=10 end
                        end
                        return {block_events={{getType=function()return 0 end,mat_type=0,mat_state=0,
                            amount=setmetatable({},{__index=function()return setmetatable({},{__index=function()return amount end})end})}}}
                    end
                """,name)
                accepted_anchor=case['first_selection']['x']!=-30000
                x,y=(case['first_selection']['x']-fixture['origin']['x'],case['first_selection']['y']-fixture['origin']['y']) if accepted_anchor else (0,0)
                anchor=self.finish(action=1,definition=family,x=x,y=y,width=1,height=1)
                self.assertEqual(bool(anchor['ok']),accepted_anchor)
                if not case['buildings']:
                    if accepted_anchor:
                        self.assertFalse(self.finish(action=1,definition=family,width=3,height=3)['ok'])
                    continue
                buildings=case['buildings']
                x=min(b['x1'] for b in buildings)-fixture['origin']['x'];y=min(b['y1'] for b in buildings)-fixture['origin']['y']
                w=max(b['x1'] for b in buildings)-fixture['origin']['x']-x+1;h=max(b['y1'] for b in buildings)-fixture['origin']['y']-y+1
                preview=self.finish(action=1,definition=family,x=x,y=y,width=w,height=h)
                self.assertTrue(preview['ok'],preview['message'])
                self.assertEqual(list(preview['valid_mask'].values()),[1]*len(buildings))

    def test_native_bridge_material_perimeter_groups(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/bridge_placement.json').read_text())
        for case in fixture['material_groups']['capture']['cases']:
            with self.subTest(variant=case['variant']):
                self.reset()
                self.lua.execute("""
                    local c=...;fill(1);stock[1].pos={x=1,y=4,z=0}
                    local groups={}
                    for y=0,2 do for x=0,2 do groups[x..':'..y]=c.footprint_groups[y*3+x+1]end end
                    local index=1
                    for i=0,2 do for _,p in ipairs{{-1,i},{3,i},{i,-1},{i,3}}do groups[p[1]..':'..p[2]]=c.perimeter_groups[index];index=index+1 end end
                    groups['1:4']=c.candidates[1].raw_group
                    dfhack.maps.getTileBlock=function(p)
                        local g=groups[p.x..':'..p.y]or 0
                        return {block_events={},walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return g end})end})}
                    end
                """,self.lua.table_from(case,recursive=True))
                page=self.page(definition='Bridge',width=3,height=3)
                self.assertTrue(page['ok'],page['message'])
                self.assertEqual(len(page['materials'])>0,case['candidates'][0]['enabled'])

    def test_native_navigation_failure_copy_is_not_rewritten(self):
        self.lua.execute("""
            fill(2);df.item_type.CHAIR=0
            dfhack.maps.getTileBlock=function(p)
                return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return 1 end})end})}
            end
            fixture_search=function()return {status=3,native_message='Synthetic native failure',reason='internal debug reason'}end
        """)
        page=self.page()
        self.assertFalse(page['ok'])
        self.assertEqual(page['message'],'Synthetic native failure')

    def test_native_stair_navigation_receives_construction_subtype(self):
        self.lua.execute("""
            fill(1)
            fixture_search=function(seeds,targets,subtype)
                assert(subtype==df.construction_type.UpDownStair,'native stair subtype missing')
                native_stair_called=true
                local result={status=0,distances={}}
                for _,p in ipairs(targets)do result.distances[#result.distances+1]={reachable=true,distance=0}end
                return result
            end
        """)
        page=self.page(definition='Construction:Stairs',depth=3)
        self.assertTrue(page['ok'],page['message'])
        self.assertTrue(self.lua.globals().native_stair_called)

    def test_bridge_material_footprint_identity_and_exact_reservation(self):
        self.lua.execute("""
            fill(2);stock[1].pos={x=3,y=1,z=0};stock[2].pos={x=0,y=3,z=0}
            stock[1].flags.on_ground=false;stock[2].flags.on_ground=false
            fixture_search=function(seeds,targets)
                local result={status=0,distances={}}
                for _,p in ipairs(targets)do
                    local best=math.huge
                    for _,s in ipairs(seeds)do best=math.min(best,math.abs(s.x-p.x)+math.abs(s.y-p.y))end
                    result.distances[#result.distances+1]={reachable=true,distance=best}
                end
                return result
            end
        """)
        a=self.page(definition='Bridge',width=3,height=1)
        b=self.page(definition='Bridge',width=1,height=3)
        self.assertTrue(a['ok'],a['message']);self.assertTrue(b['ok'],b['message'])
        self.assertEqual(a['materials'][1]['candidates'][1]['id'],1)
        self.assertEqual(b['materials'][1]['candidates'][1]['id'],2)
        self.assertNotEqual(a['list_revision'],b['list_revision'])
        selection=dict(filter=0,item_type=0,item_subtype=-1,mat_type=0,mat_index=0,count=1,item_ids=[1],expected_list_revision=a['list_revision'])
        refused=self.finish(action=2,definition='Bridge',width=1,height=3,selections=[selection])
        self.assertFalse(refused['ok'])
        self.assertEqual(len(self.lua.globals().created),0)
        selection.update(item_ids=[2],expected_list_revision=b['list_revision'])
        placed=self.finish(action=2,definition='Bridge',width=1,height=3,selections=[selection])
        self.assertTrue(placed['ok'],placed['message'])
        self.assertEqual(self.lua.globals().created[1]['items'][1]['id'],2)

    def test_native_bridge_placement_matrix(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/bridge_placement.json').read_text())
        for case in fixture['cases']:
            with self.subTest(variant=case['variant'],orientation=case['orientation']):
                self.lua.execute("""
                    local name,dir=...;local shape_names={OpenSpace='EMPTY',StoneWall='WALL',StoneRamp='RAMP',RampTop='RAMP_TOP',StoneStairU='STAIR_UP',StoneStairD='STAIR_DOWN',StoneStairUD='STAIR_UPDOWN',StoneBoulder='BOULDER',StonePebbles1='PEBBLES'}
                    local function edge(p,d)
                        return p.x>=0 and p.x<=2 and p.y>=0 and p.y<=2 and
                            ((d=='W' and p.x==0)or(d=='E' and p.x==2)or(d=='N' and p.y==0)or(d=='S' and p.y==2)or(d=='Retracting' and p.x==p.y))
                    end
                    dfhack.maps.getTileType=function(p)
                        local base=name=='all_open' or name:find('floor_edge_',1,true)==1
                        local shape=base and 'EMPTY' or name=='all_ramp' and 'RAMP' or 'FLOOR'
                        local outer=p.x<0 or p.x>2 or p.y<0 or p.y>2
                        local outside=name:match('^outside_(.+)')
                        if outer and outside then shape=shape_names[outside] end
                        if outer and name:find('perimeter_',1,true)==1 then
                            shape='EMPTY'
                            local dx,dy=name:match('^perimeter_floor_([%-0-9]+)_([%-0-9]+)')
                            local x,y=dx and tonumber(dx)+1 or 3,dy and tonumber(dy)+1 or 1
                            if p.x==x and p.y==y then shape='FLOOR' end
                        end
                        local e=name:match('_edge_(.+)')
                        if e and edge(p,e)then shape=name:find('floor_',1,true)==1 and 'FLOOR' or name:find('ramp_',1,true)==1 and 'RAMP' or 'STAIR_UPDOWN' end
                        local a=name:match('^anchor_(.+)')
                        if a and edge(p,dir)then shape=shape_names[a]end
                        if p.x==1 and p.y==1 then
                            shape=({center_open='EMPTY',center_ramp='RAMP',center_wall='WALL',center_upstairs='STAIR_UP',center_downstairs='STAIR_DOWN',center_updownstairs='STAIR_UPDOWN'})[name]or shape
                        end
                        local dx,dy=name:match('^open_([%-0-9]+)_([%-0-9]+)')
                        if dx and p.x==tonumber(dx)+1 and p.y==tonumber(dy)+1 then shape='EMPTY'end
                        return assert(df.tiletype_shape[shape])
                    end
                    dfhack.maps.getTileFlags=function(p)
                        local center=p.x==1 and p.y==1
                        local f={flow_size=center and ({water_one=1,water_two=2,magma_one=1})[name]or 0,
                            liquid_type=name=='magma_one',hidden=(name=='hidden_first' and p.x==0 and p.y==0)or(name=='center_hidden' and center)}
                        local occupancy=0
                        if p.x==3 and p.y==1 then
                            local flag=name:match('^perimeter_flag_(.+)')
                            if flag then
                                f.flow_size=tonumber(flag:sub(-1))or 0;f.liquid_type=flag:find('magma',1,true)~=nil
                                f.hidden=flag=='hidden'
                                occupancy=({Planned=1,Passable=2,Obstacle=3,Well=4,Floored=5,Impassable=6,Dynamic=7})[flag]or 0
                            end
                        end
                        return f,{building=occupancy}
                    end
                """,case['variant'],case['orientation'])
                self.lua.execute("""
                    local accepted,anchor=...
                    native_perimeter=function(p,w,h)
                        return (w==3 and h==3 and accepted) or (w==1 and h==1 and anchor),'Needs walkable perimeter'
                    end
                """,'Needs walkable perimeter' not in case['errors'],
                    case['first_selection']['x']!=-30000)
                request=dict(action=1,definition='Bridge',direction=max(0,case['direction']),retracting=case['direction']==-1)
                anchor=self.finish(**request)
                accepted=case['first_selection']['x']!=-30000
                self.assertEqual(bool(anchor['ok']),accepted,anchor['message'])
                if accepted:
                    result=self.finish(width=3,height=3,**request)
                    self.assertEqual(bool(result['ok']),case['stage']=='STAGES',result['message'])

    def test_construction_native_refusal_precedes_occupancy(self):
        self.lua.execute("occupied={['0:0:0']=true}")
        for family in ['Construction:Wall','Construction:Floor']:
            for message in ['Water at this location','Lava/Magma at this location','Blocked at this location','Cannot build at highest level','Too close to edge']:
                self.lua.execute("local message=...;native_construction=function()return false,message end",message)
                self.refusal(message,action=1,definition=family)
                self.assertFalse(self.finish(action=2,definition=family)['ok'])
                self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute("flags.hidden=true;native_construction=function()error('Hidden site should stop before native terrain')end")
        self.refusal('Hidden, cannot build at this location',action=1,definition='Construction:Wall')

    def test_construction_native_bounds_subtype_and_recheck(self):
        for family in ['Wall','Floor','Ramp','Fortification','Stairs']:
            with self.subTest(family=family):
                self.setUp()
                depth=3 if family=='Stairs' else 1
                self.lua.execute("expected=df.construction_type[...];native_construction=function(p,w,h,st,x,y)assert(w==2 and h==2 and x==0 and y==0 and st==expected);return true,'' end",'UpDownStair' if family=='Stairs' else family)
                request=dict(definition='Construction:'+family,width=2,height=2,depth=depth)
                self.assertTrue(self.finish(action=1,**request)['placement_valid'])
                self.lua.execute("native_construction=function()return false,'Must remove construction' end")
                self.refusal('Must remove construction',action=1,**request)
                self.assertFalse(self.finish(action=2,**request)['ok'])
                self.assertEqual(len(self.lua.globals().created),0)
                self.lua.execute("native_construction=function()return false,'' end")
                self.refusal('',action=1,**request)

    def test_magma_native_center_outer_and_commit_recheck(self):
        for family in ['Workshop:MagmaForge','Furnace:MagmaSmelter','Furnace:MagmaGlassFurnace','Furnace:MagmaKiln']:
            with self.subTest(family=family):
                self.setUp()
                self.lua.execute("native_floor=function(p)assert(p.x==1 and p.y==1);return true,'' end;native_open=function(p)assert(p.x~=1 or p.y~=1);return true,'' end")
                self.assertTrue(self.finish(action=1,definition=family,width=3,height=3)['placement_valid'])
                self.lua.execute("native_floor=function()return false,'Must remove construction' end")
                self.refusal('Must remove construction',action=1,definition=family,width=3,height=3)
                self.assertFalse(self.finish(action=2,definition=family,width=3,height=3)['ok'])
                self.assertEqual(len(self.lua.globals().created),0)
                self.lua.execute("native_open=function()return false,'' end")
                self.refusal('',action=1,definition=family,width=3,height=3)

    def test_native_magma_placement_matrix(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/magma_placement.json').read_text())
        shapes={'OpenSpace':'EMPTY','StoneRamp':'RAMP','RampTop':'RAMP_TOP',
                'StoneStairU':'STAIR_UP','StoneStairD':'STAIR_DOWN','StoneStairUD':'STAIR_UPDOWN',
                'StoneWall':'WALL','StoneFortification':'FORTIFICATION'}
        for case in fixture['cases']:
            name=case['variant'];x=y=1;shape='FLOOR'
            if name.startswith('hole_'):
                _,dx,dy=name.split('_');x=int(dx)+1;y=int(dy)+1;shape='EMPTY'
            elif name.startswith('center_hole_'):shape='EMPTY'
            elif name in ('center_ramp','center_wall','center_stair_up'):
                shape={'center_ramp':'RAMP','center_wall':'WALL','center_stair_up':'STAIR_UP'}[name]
            elif name.split('_')[0] in shapes:
                raw,dx,dy=name.split('_');shape=shapes[raw];x=int(dx)+1;y=int(dy)+1
            with self.subTest(definition=case['definition'],variant=name):
                self.lua.execute("""
                    local name,x,y,shape=...
                    dfhack.maps.getTileType=function(p)
                        if name=='all_empty' then return df.tiletype_shape.EMPTY end
                        if name=='center_floor_only' then return p.x==1 and p.y==1 and df.tiletype_shape.FLOOR or df.tiletype_shape.EMPTY end
                        return p.x==x and p.y==y and df.tiletype_shape[shape] or df.tiletype_shape.FLOOR
                    end
                    dfhack.maps.getTileFlags=function(p)
                        return {hidden=name=='hidden_corner' and p.x==0 and p.y==0,
                            flow_size=p.x==1 and p.y==1 and (name=='water_two' and 2 or (name=='water_one' or name=='magma_one') and 1 or 0) or 0,
                            liquid_type=name=='magma_one'}, {building=0}
                    end
                """,name,x,y,shape)
                result=self.finish(action=1,definition=case['definition'],width=3,height=3)
                self.assertEqual(bool(result['ok']),case['clicked_stage']=='STAGES',str(result['message']))

    def test_machinery_native_terrain_and_support_recheck(self):
        for family in ['GearAssembly','AxleHorizontal','AxleVertical','Rollers','Workshop:Millstone']:
            with self.subTest(family=family):
                self.setUp()
                if family=='Workshop:Millstone':
                    self.lua.execute("df.workshop_type=enum{'Carpenters','Tool','MagmaForge','Custom','Millstone'}")
                    self.reset()
                size=3 if family=='Workshop:Millstone' else 1
                self.lua.execute("fixture_connect=function()return true end;native_open=function()return true,'' end;native_floor=function()return false,'Blocked at this location' end")
                self.assertTrue(self.finish(action=1,definition=family,width=size,height=size)['placement_valid'])
                self.lua.execute("fixture_connect=function()return false end")
                self.refusal('Blocked at this location',action=1,definition=family,width=size,height=size)
                self.assertFalse(self.finish(action=2,definition=family,width=size,height=size)['ok'])
                self.assertEqual(len(self.lua.globals().created),0)
        self.setUp()
        self.lua.execute("native_floor=function()return false,'' end")
        self.refusal('',action=1,definition='Support')

    def test_windmill_native_terrain_selection_and_unknown(self):
        self.lua.execute("shape=df.tiletype_shape.EMPTY;fixture_connect=function()return true end;native_open=function()return true,'' end;native_floor=function()error('wrong terrain mode')end")
        self.assertTrue(self.finish(action=1,definition='Windmill',width=3,height=3)['placement_valid'])
        self.lua.execute("native_open=function()return false,'Must remove construction' end")
        self.refusal('Must remove construction\nNeeds ground or near machine',action=1,definition='Windmill',width=3,height=3)
        self.lua.execute("native_open=function()return false,'' end")
        self.refusal('',action=1,definition='Windmill',width=3,height=3)
        self.lua.execute("fixture_connect=function()return false end;native_floor=function()return false,'Blocked at this location' end")
        self.refusal('Blocked at this location\nNeeds ground or near machine',action=1,definition='Windmill',width=3,height=3)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_farm_warning_independent_of_preview_acceptance(self):
        for accepted in [True,False]:
            self.setUp()
            self.lua.execute("native_warning=function()return true,'No mud/soil for farm\\nMud is left by water',true end")
            if not accepted:
                self.lua.execute("native_connectivity=function()return false,'Disconnected' end")
            result=self.finish(action=1,definition='FarmPlot',width=3,height=3)
            self.assertEqual(result['ok'],accepted)
            self.assertEqual(result['warnings'],'No mud/soil for farm\nMud is left by water')
            self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute("native_warning=function()return true,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='FarmPlot')['warnings'],'')

    def test_farm_water_refusal_finishes_warning_scan_without_jobs(self):
        self.lua.execute("""
        dfhack.maps.getTileFlags=function(p)return {hidden=false,flow_size=p.x==0 and 2 or 0,liquid_type=0},{building=0} end
        native_warning=function(p,w,h,mask)
          assert(table.concat(mask,',')=='0,0,1,1,1,1')
          return true,'No mud/soil for farm\\nMud is left by water',true
        end
        """)
        for action in [1,2]:
            result=self.finish(action=action,definition='FarmPlot',width=3,height=2,step_budget=1)
            self.assertFalse(result['ok'])
            self.assertEqual(result['message'],'Water at this location')
            self.assertEqual(result['warnings'],'No mud/soil for farm\nMud is left by water')
        self.assertEqual(len(self.lua.globals().created),0)

    def test_farm_warning_transposes_completed_mask(self):
        self.lua.execute("""
        df.new=function(kind,count)assert(kind=='uint8_t');return {}end
        df.reinterpret_cast=function(_,ptr)return ptr end
        native_terrain=function(p)return p.x==0 or p.y==0,'Need soil or mud at location' end
        native_warning=function(p,w,h,mask)
          assert(w==3 and h==2)
          assert(table.concat(mask,',')=='1,1,1,0,1,0')
          warning_calls=(warning_calls or 0)+1
          return false,'',true
        end
        """)
        self.seq+=1
        for _ in range(5):
            result=self.call(action=1,definition='FarmPlot',width=3,height=2,step_budget=1)
            self.assertTrue(result['pending'])
            self.assertEqual(result['warnings'],'')
        result=self.call(action=1,definition='FarmPlot',width=3,height=2)
        self.assertTrue(result['ok'])
        self.assertEqual(result['warnings'],'')
        self.assertEqual(self.lua.globals().warning_calls,1)

    def test_native_bridge_full_tiles_and_perimeter_order(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/bridge_tile_native.json.gz').read_bytes()))
        messages={5:'Needs to be anchored on edge',6:'Blocked at this location',7:'Hidden, cannot build at this location',10:'Water at this location',11:'Lava/Magma at this location',12:'Building present',19:'Must remove construction'}
        for dataset in data['datasets'].values():
            for row in dataset['rows']:
                codes={str(t['dx'])+','+str(t['dy']):t['code'] for t in row['tiles']}
                self.lua.execute("""
                  local codes,messages,direction,w,h,perimeter=...
                  native_bridge=function(p,anchor)
                    assert(anchor==((direction==0 and p.x==0) or (direction==1 and p.x==w-1) or (direction==2 and p.y==0) or (direction==3 and p.y==h-1)))
                    local code=assert(codes[p.x..','..p.y]);return code==0,messages[code] or '',true
                  end
                  native_perimeter=function()return perimeter,'Needs walkable perimeter',true end
                """,self.lua.table_from(codes),self.lua.table_from(messages),row['direction'],row['width'],row['height'],'Needs walkable perimeter' not in row['errors'])
                result=self.finish(action=1,definition='Bridge',width=row['width'],height=row['height'],direction=max(0,row['direction']),retracting=row['direction']==-1)
                self.assertEqual(result['ok'],not row['errors'],row)
                if row['errors']:self.assertEqual(result['message'],'\n'.join(row['errors']),row)
        self.lua.execute("native_bridge=function()return false,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='Bridge',width=3,height=3)['message'],'')
        self.lua.execute("native_bridge=function()return true,'',true end;native_perimeter=function()return false,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='Bridge',width=3,height=3)['message'],'')
        self.lua.execute("bridge_calls=0;native_bridge=function()bridge_calls=bridge_calls+1;return bridge_calls<=9,'Water at this location',true end;native_perimeter=function()return true,'',true end;dfhack.buildings.getFiltersByType=function()return {}end")
        self.assertFalse(self.finish(action=2,definition='Bridge',width=3,height=3)['ok'])
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_special_tiles_drive_preview_and_commit(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/special_tile_native.json.gz').read_bytes()))
        names={'building_type':['ScrewPump','WaterWheel','GearAssembly','AxleHorizontal','AxleVertical','Rollers','Workshop','Windmill','Furnace'],'workshop_type':['Millstone','MagmaForge'],'furnace_type':['MagmaSmelter','MagmaGlassFurnace','MagmaKiln']}
        for enum,values in names.items():
            self.lua.execute("local e,names=df[(...)],select(2,...);for _,name in ipairs(names)do if not e[name] then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end end",enum,self.lua.table_from(values))
        dimensions={row['key']:[row['width'],row['height']] for row in data['datasets']['edge']['rows']}
        self.lua.execute("""
          local dimensions=...
          dfhack.buildings.getCorrectSize=function(w,h,kind,subtype)
            local key=df.building_type[kind]
            if key=='Workshop' then key=key..':'..df.workshop_type[subtype] elseif key=='Furnace' then key=key..':'..df.furnace_type[subtype] end
            local size=dimensions[key];if size then return true,size[1],size[2],0,0 end
            return true,w,h,0,0
          end
        """,self.lua.table_from(dimensions,recursive=True))
        self.reset()
        messages={6:'Blocked at this location',7:'Hidden, cannot build at this location',10:'Water at this location',11:'Lava/Magma at this location',12:'Building present',14:'Too close to edge',19:'Must remove construction'}
        for row in data['datasets']['edge']['rows']:
            codes={str(t['dx'])+','+str(t['dy']):t['code'] for t in row['tiles']}
            self.lua.execute("""
                local codes,messages,hookup=...
                df.global.world.buildings.get_machine_hookup_list=function(_,info)if hookup then info.tiles.x[1]=0 end end
                fixture_connect=function()return false end
                native_special=function(p,key,open)
                  assert(open==(key:find('Magma')~=nil and not (p.x==1 and p.y==1)))
                  local code=assert(codes[p.x..','..p.y]);return code<=3,messages[code] or '',true
                end
            """,self.lua.table_from(codes),self.lua.table_from(messages),'Needs ground or near machine' in row['errors'])
            result=self.finish(action=1,definition=row['key'],width=row['width'],height=row['height'],direction=0)
            self.assertEqual(result['ok'],not row['errors'],row)
            if row['errors']:self.assertEqual(result['message'],'\n'.join(row['errors']),row)
        self.lua.execute("native_special=function()return false,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='Windmill',width=3,height=3)['message'],'')
        self.lua.execute("special_calls=0;native_special=function()special_calls=special_calls+1;return special_calls<=9,'Water at this location',true end;dfhack.buildings.getFiltersByType=function()return {}end")
        result=self.finish(action=2,definition='Windmill',width=3,height=3)
        self.assertFalse(result['ok']);self.assertEqual(len(self.lua.globals().created),0)

    def test_native_opening_results_drive_preview_and_commit(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/opening_tile_native.json.gz').read_bytes()))
        self.lua.execute("local e=df.building_type;for _,name in ipairs{'Support','Well','Hatch','GrateFloor','BarsFloor','AnimalTrap'}do if not e[name] then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end end")
        self.reset()
        for dataset in data['datasets'].values():
            for row in dataset['rows']:
                family=row.get('family',row.get('key'));code=row.get('code',row.get('first_tile'))
                errors=row['errors'];reason=errors[0] if errors and code not in (0,1) else ''
                self.lua.execute("local ok,reason,perimeter=...;native_opening=function()return ok,reason,true end;perimeter_allowed=perimeter",code in (0,1),reason,'Needs walkable perimeter' not in errors)
                result=self.finish(action=1,definition=family)
                self.assertEqual(result['ok'],not errors,(family,row))
                if errors:self.assertEqual(result['message'],'\n'.join(errors),(family,row))
        self.lua.execute("native_opening=function()return false,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='Hatch')['message'],'')
        self.lua.execute("native_opening=function()return true,'',true end;native_single_perimeter=function()return false,'unverified',false end")
        self.assertEqual(self.finish(action=1,definition='AnimalTrap')['message'],'')
        self.lua.execute("native_single_perimeter=nil;opening_calls=0;native_opening=function()opening_calls=opening_calls+1;return opening_calls==1,'Water at this location',true end;dfhack.buildings.getFiltersByType=function()return {}end")
        result=self.finish(action=2,definition='Hatch')
        self.assertFalse(result['ok']);self.assertEqual(len(self.lua.globals().created),0)

    def test_animal_perimeter_preserves_tiles_and_rechecks_commit(self):
        self.lua.execute("native_opening=function()return true,'',true end;native_single_perimeter=function()return false,'Needs walkable perimeter',true end")
        result=self.finish(action=1,definition='AnimalTrap')
        self.assertFalse(result['ok']);self.assertEqual(result['message'],'Needs walkable perimeter')
        self.assertEqual(list(result['valid_mask'].values()),[1])
        self.lua.execute("perimeter_calls=0;native_single_perimeter=function()perimeter_calls=perimeter_calls+1;return perimeter_calls==1,'Needs walkable perimeter',true end;dfhack.buildings.getFiltersByType=function()return {}end")
        result=self.finish(action=2,definition='AnimalTrap')
        self.assertFalse(result['ok']);self.assertEqual(result['message'],'Needs walkable perimeter')
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_ordinary_results_drive_preview_and_commit(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/ordinary_tile_native.json.gz').read_bytes()))
        names={}
        for row in data['datasets']['priority']['rows']:
            parts=row['key'].split(':');names.setdefault('building_type',set()).add(parts[0])
            if len(parts)>1:
                names.setdefault({'Workshop':'workshop_type','Furnace':'furnace_type','Trap':'trap_type','SiegeEngine':'siegeengine_type'}[parts[0]],set()).add(parts[1])
        for enum, values in names.items():
            self.lua.execute("local key,names=...;local e=df[key];for _,name in ipairs(names)do if e[name]==nil then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end end",enum,self.lua.table_from(sorted(values)))
        # Add the two admitted custom workshop raws.
        self.lua.execute("customs[#customs+1]={id=91,code='SCREW_PRESS',name='Screw Press',class='workshop'};customs[#customs+1]={id=92,code='SOAP_MAKER',name='Soap Maker',class='workshop'};permitted_ids[#permitted_ids+1]=91;permitted_ids[#permitted_ids+1]=92")
        self.reset()
        catalog={r['key']:r for r in self.call(action=0)['catalog'].values()}
        plate=json.loads((root/'fixtures/construction/pressure_plate.json').read_text())['default']
        options={**plate['flags'],**{k:plate[k] for k in ('unit_min','unit_max','water_min','water_max','magma_min','magma_max','track_min','track_max')},'units':True}
        for dataset in data['datasets'].values():
            for row in dataset['rows']:
                code=row['first_tile'];reason=row['errors'][0] if row['errors'] else ''
                self.lua.execute("local ok,reason=...;native_ordinary=function()return ok,reason,true end",code in (0,1),reason)
                args=dict(action=1,definition=row['key'],width=catalog[row['key']]['width'],height=catalog[row['key']]['height'])
                if row['key']=='Trap:PressurePlate':args['pressure_plate']=options
                if row['key']=='Trap:TrackStop':args['track_stop']={'friction':50000,'dump_direction':0}
                result=self.finish(**args)
                self.assertEqual(result['ok'],code in (0,1),row['key'])
                if code not in (0,1):self.assertEqual(result['message'],reason,row['key'])
        self.lua.execute("native_ordinary=function()return false,'unverified',false end")
        for action in (1,2):
            result=self.finish(action=action,definition='Workshop:Carpenters',width=3,height=3)
            self.assertFalse(result['ok']);self.assertEqual(result['message'],'')
        self.lua.execute("""
            dfhack.buildings.getFiltersByType=function()return {}end
            ordinary_calls=0
            native_ordinary=function()
                ordinary_calls=ordinary_calls+1
                return ordinary_calls<=9,'Water at this location',true
            end
        """)
        result=self.finish(action=2,definition='Workshop:Carpenters',width=3,height=3)
        self.assertFalse(result['ok']);self.assertEqual(len(self.lua.globals().created),0)
        self.assertGreater(self.lua.globals().ordinary_calls,9)

    def test_native_furniture_results_drive_preview_and_place(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/furniture_tile_native.json.gz').read_bytes()))
        self.lua.execute("local e=df.building_type;for _,name in ipairs{'Bed','Chair','Door','Statue','Cage','Weaponrack','Table','Box','Cabinet','Coffin','Slab','TractionBench','Bookcase','DisplayFurniture','OfferingPlace','Instrument','GrateWall','BarsVertical','WindowGlass','WindowGem'}do if not e[name] then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end end")
        self.reset()
        for dataset in data['datasets'].values():
            for row in dataset['rows']:
                code=row['code'];reason=row['errors'][0] if row['errors'] else ''
                self.lua.execute("local ok,reason=...;native_furniture=function()return ok,reason,true end",code in (0,1),reason)
                result=self.finish(action=1,definition=row['family'])
                self.assertEqual(result['ok'],code in (0,1),row)
                if code not in (0,1):self.assertEqual(result['message'],reason,row)
        self.lua.execute("native_furniture=function()return false,'unverified',false end")
        for action in (1,2):
            result=self.finish(action=action,definition='Chair')
            self.assertFalse(result['ok']);self.assertEqual(result['message'],'')
        self.lua.execute("""
            dfhack.buildings.getFiltersByType=function()return {}end
            furniture_calls=0
            native_furniture=function()
                furniture_calls=furniture_calls+1
                return furniture_calls==1,'Must be inside',true
            end
        """)
        result=self.finish(action=2,definition='Chair')
        self.assertFalse(result['ok']);self.assertEqual(len(self.lua.globals().created),0)
        self.assertEqual(self.lua.globals().furniture_calls,2)

    def test_native_extent_tile_results_drive_preview(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/extent_tile_native.json.gz').read_bytes()))
        for dataset in data['datasets'].values():
            for row in dataset['cases']:
                code=row['code'];reason=row['errors'][0] if row['errors'] else ''
                self.lua.execute("local ok,reason,raw=...;native_extent_tile=function()return ok,reason,true,raw end",code==0,reason,row['raw']==0)
                result=self.finish(action=1,definition=row['family'])
                self.assertEqual(result['ok'],code==0,row)
                if code!=0:self.assertEqual(result['message'],reason,row)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_extent_unknown_or_missing_raw_fails_closed(self):
        for value in ["true,'',false,true", "true,'',true,nil"]:
            self.lua.execute("native_extent_tile=function()return "+value+" end")
            for action in [1,2]:
                result=self.finish(action=action,definition='FarmPlot')
                self.assertFalse(result['ok'])
                self.assertEqual(result['message'],'')
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_construction_mixed_rectangles_refuse_entire_area(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/construction_paint_area.json.gz').read_bytes()))
        self.lua.execute("local e=df.construction_type;for _,name in ipairs{'ReinforcedWall','UpStair','DownStair','UpDownStair'}do if e[name]==nil then e._last_item=e._last_item+1;e[e._last_item]=name;e[name]=e._last_item end end")
        self.reset()
        reasons={6:'Blocked at this location',7:'Hidden, cannot build at this location',10:'Water at this location',11:'Lava/Magma at this location',12:'Building present'}
        for row in data['native_evaluation']['rows']:
            # Native single stair subtypes are construction effects; the menu exposes Stairs.
            if row['subtype'] in ('UpStair','DownStair','UpDownStair'):
                continue
            family='Stairs' if row['subtype']=='UpDownStair' else row['subtype']
            self.lua.execute("local codes,reasons=...;native_construction=function(p) local c=codes[p.x+1];return c<4,reasons[c] or '' end",self.lua.table_from(row['tiles']),self.lua.table_from(reasons))
            result=self.finish(action=1,definition='Construction:'+family,width=3,step_budget=2)
            self.assertEqual(result['ok'],not row['errors'],row)
            self.assertEqual(result['message'],'\n'.join(row['errors']),row)
            if row['errors']:
                result=self.finish(action=2,definition='Construction:'+family,width=3,step_budget=2)
                self.assertFalse(result['ok']);self.assertEqual(result['message'],'\n'.join(row['errors']))
        self.assertEqual(len(self.lua.globals().created),0)

    def test_unknown_family_has_no_local_terrain_fallback(self):
        self.lua.execute("local e=df.building_type;e._last_item=e._last_item+1;e[e._last_item]='UnverifiedFamily';e.UnverifiedFamily=e._last_item")
        self.reset()
        for action in (1,2):
            result=self.finish(action=action,definition='UnverifiedFamily')
            self.assertFalse(result['ok']);self.assertEqual(result['message'],'')
        for key,size in [('Workshop:Custom:PRESS',3),('Furnace:Custom:KILN',1)]:
            for action in (1,2):
                result=self.finish(action=action,definition=key,width=size,height=size)
                self.assertFalse(result['ok']);self.assertEqual(result['message'],'')
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_stairs_click_time_volume_refusals(self):
        import gzip
        root=Path(__file__).resolve().parents[1]
        data=json.loads(gzip.decompress((root/'fixtures/construction/construction_paint_area.json.gz').read_bytes()))
        reasons={'wall':'Blocked at this location','water':'Water at this location','magma':'Lava/Magma at this location','hidden':'Hidden, cannot build at this location','occupied':'Building present'}
        for row in data['stairs_mixed']['rows']:
            if row['reverse'] or row['selection']['z']==-30000:continue
            reason=reasons.get(row['variant'],'')
            self.lua.execute("local level,reason=...;native_construction=function(p)if p.z==level and reason~='' then return false,reason end;return true,'' end",row['affected'],reason)
            result=self.finish(action=1,definition='Construction:Stairs',depth=3,step_budget=1)
            self.assertEqual(result['ok'],row['stage']=='STAGES',row)
            self.assertEqual(result['message'],'\n'.join(row['after_errors']),row)
        # The renderer overwrites reverse errors; use native click-time validation.
        for row in data['stairs_refusal_events']['rows']:
            self.lua.execute("""
                local variant=...
                native_construction=function(p)
                    if p.z==0 and p.x==1 and variant~='middle_pair' then return false,'Water at this location' end
                    if p.z==1 and p.x==0 then return false,'Building present' end
                    if p.z==1 and p.x==1 and variant=='middle_pair' then return false,'Water at this location' end
                    if p.z==2 and p.x==0 and variant=='three_levels' then return false,'Hidden, cannot build at this location' end
                    return true,''
                end
            """,row['variant'])
            for action in (1,2):
                result=self.finish(action=action,definition='Construction:Stairs',width=2,depth=4,step_budget=1,material_anchor=dict(x=0 if row['reverse'] else 1,y=0,z=0 if row['reverse'] else 3))
                self.assertFalse(result['ok']);self.assertEqual(result['message'],'\n'.join(row['click_trace']['after_input']['errors']),row)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_extent_errors_order_and_raw_terrain_skip(self):
        for family in ['FarmPlot','RoadDirt','RoadPaved']:
            self.setUp()
            self.lua.execute("""
            native_terrain=function(p)return p.x~=1,'Blocked at this location' end
            native_connectivity=function()return false,'Disconnected' end
            dfhack.maps.getTileFlags=function(p)return {hidden=false,flow_size=p.x==0 and 2 or 0,liquid_type=0},{building=0} end
            """)
            for action in [1,2]:
                result=self.finish(action=action,definition=family,width=3,height=3,step_budget=1)
                self.assertFalse(result['ok'])
                self.assertEqual(result['message'],'Disconnected\nWater at this location')
            self.assertEqual(len(self.lua.globals().created),0)

    def test_native_extent_partial_occupancy_refuses_entire_area(self):
        for family in ['FarmPlot','RoadDirt','RoadPaved']:
            self.setUp()
            self.lua.execute("dfhack.maps.getTileFlags=function(p)return {hidden=false,flow_size=0,liquid_type=0},{building=p.x==0 and 1 or 0} end")
            for action in [1,2]:
                result=self.finish(action=action,definition=family,width=3,height=3,step_budget=1)
                self.assertFalse(result['ok'])
                self.assertEqual(result['message'],'Building present')
            self.assertEqual(len(self.lua.globals().created),0)

    def test_native_extent_raw_terrain_precedes_occupancy_and_water(self):
        for family in ['FarmPlot','RoadDirt']:
            self.setUp()
            reason='Need soil or mud at location' if family=='FarmPlot' else 'Need soil at location'
            self.lua.execute("""local reason=...
            native_terrain=function(p)return false,p.x==1 and 'Blocked at this location' or reason end
            dfhack.maps.getTileFlags=function(p)return {hidden=false,flow_size=p.x==0 and 2 or 0,liquid_type=0},{building=p.x==2 and 1 or 0} end
            """,reason)
            result=self.finish(action=1,definition=family,width=3,height=3,step_budget=1)
            self.assertFalse(result['ok'])
            self.assertEqual(result['message'],reason+'\nBlocked at this location')

    def test_native_extent_skipped_terrain_becomes_occupied_before_creation(self):
        self.lua.execute("""
        df.new=function()return {}end;df.reinterpret_cast=function(_,p)return p end
        dfhack.buildings.getFiltersByType=function()return {} end
        native_calls=0
        native_terrain=function(p)native_calls=native_calls+1;return p.x~=0 or native_calls>9,'Blocked at this location' end
        dfhack.maps.getTileFlags=function(p)return {hidden=false,flow_size=0,liquid_type=0},{building=p.x==0 and native_calls>=9 and 1 or 0} end
        """)
        result=self.finish(action=2,definition='FarmPlot',width=3,height=3)
        self.assertFalse(result['ok'])
        self.assertEqual(len(self.lua.globals().created),0)

    def test_area_connectivity_refuses_before_reserving_materials(self):
        for family in ['FarmPlot','RoadDirt','RoadPaved']:
            with self.subTest(family=family):
                self.setUp()
                self.lua.execute("native_connectivity=function()return false,'Disconnected' end")
                for action in [1,2]:
                    self.refusal('Disconnected',action=action,definition=family,width=3,height=3)
                self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute("native_connectivity=function()return false,'' end")
        self.refusal('',action=1,definition='FarmPlot',width=3,height=3)

    def test_area_connectivity_changes_before_creation(self):
        self.lua.execute("""
        dfhack.buildings.getFiltersByType=function()return {} end
        connectivity_calls=0
        native_connectivity=function()
          connectivity_calls=connectivity_calls+1
          return connectivity_calls==1,'Disconnected'
        end
        """)
        result=self.finish(action=2,definition='FarmPlot',width=3,height=3)
        self.assertFalse(result['ok'])
        self.assertEqual(self.lua.globals().connectivity_calls,2)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_native_refusal_order_and_dedup_across_incremental_scan(self):
        self.lua.execute("""
        native_floor=function(p)
          if p.x==0 and p.y==1 then return false,'Water at this location' end
          if p.x==1 or p.x==2 then return false,'Blocked at this location' end
          return true,''
        end
        """)
        for action in [1,2]:
            result=self.finish(action=action,definition='Windmill',width=3,height=3,step_budget=1)
            self.assertFalse(result['ok'])
            self.assertEqual(result['message'],'Water at this location\nBlocked at this location\nNeeds ground or near machine')
            self.assertEqual(len(self.lua.globals().created),0)

    def test_windmill_support_removed_before_creation(self):
        self.lua.execute('''
            shape=df.tiletype_shape.EMPTY;support_present=true
            fixture_connect=function()return support_present end
        ''')
        request=dict(definition='Windmill',width=3,height=3)
        selection=self.selection(**request)
        self.seq+=1
        result=self.call(action=2,selections=[selection],step_budget=20,**request)
        self.assertTrue(result['pending'])
        self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute('support_present=false')
        for _ in range(20):
            result=self.call(action=2,selections=[selection],step_budget=20,**request)
            if not result['pending']:break
        self.assertFalse(result['pending'])
        self.assertFalse(result['ok'])
        self.assertEqual(len(self.lua.globals().created),0)

    def test_site_rules(self):
        groups=[(['Chair','Chain','Cage','ArcheryTarget','TractionBench','Slab','NestBox',
                  'Hive','Instrument','Bookcase','DisplayFurniture','OfferingPlace','WindowGem',
                  'Furnace:WoodFurnace','Trap:Lever','Workshop:Carpenters',
                  'SiegeEngine:Ballista','SiegeEngine:Catapult','Trap:CageTrap','Trap:StoneFallTrap',
                  'Trap:WeaponTrap','Weapon','TradeDepot','GrateWall','BarsVertical','Floodgate'], 'FLOOR','EMPTY','Site needs a floor'),
                (['Hatch','GrateFloor','BarsFloor'],'EMPTY','WALL','Blocked at this location'),
                (['Support'],'FLOOR','WALL','Blocked at this location'),
                (['ScrewPump','WaterWheel','GearAssembly','AxleHorizontal','AxleVertical','Rollers','Bridge'],
                 'FLOOR','WALL','Blocked at this location')]
        for names,good,bad,message in groups:
            for name in names:
                with self.subTest(name=name):
                    self.lua.execute('shape=df.tiletype_shape[...]',good)
                    size=3 if name.startswith(('Workshop:','SiegeEngine:')) else 1
                    self.assertTrue(self.finish(action=1,definition=name,width=size,height=size)['ok'])
                    self.lua.execute('shape=df.tiletype_shape[...]',bad)
                    self.refusal('Blocked at this location' if name in ['Chain', 'Cage', 'ArcheryTarget', 'NestBox', 'Hive', 'Furnace:WoodFurnace', 'Trap:Lever', 'Workshop:Carpenters', 'SiegeEngine:Ballista', 'SiegeEngine:Catapult', 'Trap:CageTrap', 'Trap:StoneFallTrap', 'Trap:WeaponTrap', 'Weapon', 'TradeDepot', 'Floodgate','Chair','TractionBench','Slab','Instrument','Bookcase','DisplayFurniture','OfferingPlace','WindowGem','GrateWall','BarsVertical'] else message,action=1,definition=name,width=size,height=size)
        self.lua.execute('shape=0;flags.outside=false')
        self.assertTrue(self.finish(action=1,definition='Bed')['ok'])
        self.lua.execute('flags.outside=true')
        self.refusal('Must be inside',action=1,definition='Bed')
        self.lua.execute('flags.outside=false;adjacent_shape=0;door_allowed=true;door_calls=0')
        self.assertTrue(self.finish(action=1,definition='Door')['ok'])
        self.assertGreater(self.lua.globals().door_calls,0)
        self.lua.execute('door_allowed=false;adjacent_shape=df.tiletype_shape.WALL')
        self.refusal('fixture native Door refusal',action=1,definition='Door')
        self.lua.execute('shape=df.tiletype_shape.EMPTY;adjacent_shape=0')
        self.assertTrue(self.finish(action=1,definition='Well')['ok'])
        self.lua.execute('support_allowed={Well=false};adjacent_shape=df.tiletype_shape.FLOOR')
        self.refusal('fixture native support refusal',action=1,definition='Well')
        self.lua.execute('support_allowed={}')
        self.lua.execute('shape=0')
        for setup,message in [('valid=false','Site is unloaded or outside the map'),
            ('flags.hidden=true','Hidden, cannot build at this location'),
            ("occupied['0:0:0']=true",'Building present'),
            ('flags.flow_size=2','Water at this location'),
            ('flags.flow_size=1;flags.liquid_type=1','Blocked at this location'),
            ('free=false','Native placement check rejected this site')]:
            self.lua.execute('valid=true;flags={flow_size=0};occupied={};free=true;'+setup)
            self.refusal(message,action=1)

    def test_natural_wall_refusal(self):
        for family in ['Bed', 'Door', 'Well', 'Hatch', 'Workshop:Carpenters', 'FarmPlot', 'RoadDirt', 'RoadPaved', 'Windmill', 'Construction:Wall']:
            with self.subTest(family=family):
                self.setUp()
                self.lua.execute("shape=df.tiletype_shape.WALL;native_terrain=function()return false,'Blocked at this location' end")
                size = 3 if family in ['Workshop:Carpenters', 'Windmill'] else 1
                for liquid in ['flags.flow_size=0', 'flags.flow_size=2', 'flags.flow_size=7', 'flags.flow_size=1;flags.liquid_type=true']:
                    self.lua.execute(liquid)
                    for action in [1, 2]:
                        self.refusal('Blocked at this location'+('\nNeeds ground or near machine' if family=='Windmill' else ''), action=action, definition=family, width=size, height=size)
                        self.assertEqual(len(self.lua.globals().created), 0)

    def test_terrain_empty_mask_preserves_refusal(self):
        for family in ['Construction:Wall', 'Construction:Floor', 'Construction:Ramp', 'Construction:Fortification']:
            for setup, reason in [('flags.hidden=true', 'Hidden, cannot build at this location'),
                                  ('flags.flow_size=2', 'Water at this location')]:
                with self.subTest(family=family, setup=setup):
                    self.setUp()
                    self.lua.execute(setup)
                    result = self.finish(action=1, definition=family, width=2, height=2, step_budget=1)
                    self.assertFalse(result['ok'])
                    self.assertFalse(result['placement_valid'])
                    self.assertEqual(result['message'], reason)
                    self.assertEqual(list(result['valid_mask'].values()), [0, 0, 0, 0])
                    self.assertEqual(len(self.lua.globals().created), 0)
                    placed = self.finish(action=2, definition=family, width=2, height=2, step_budget=1)
                    self.assertFalse(placed['ok'])
                    self.assertEqual(placed['message'], reason)
                    self.assertEqual(len(self.lua.globals().created), 0)
        self.setUp()
        self.lua.execute("dfhack.maps.getTileFlags=function(p)return {flow_size=0,hidden=p.x==0 and p.y==0},{building=0}end")
        result = self.finish(action=1, definition='Construction:Wall', width=2, height=2, step_budget=1)
        self.assertFalse(result['ok'])
        self.assertFalse(result['placement_valid'])
        self.assertEqual(sum(result['valid_mask'].values()), 3)
        self.assertEqual(result['message'], 'Hidden, cannot build at this location')
        self.assertEqual(result['required'], 0)

    def test_hidden_refusal_distinguishes_missing_map_data(self):
        original_flags = self.lua.globals().dfhack.maps.getTileFlags
        for missing in ('nil,nil', '{hidden=true},nil', 'nil,{building=0}'):
            self.reset()
            self.lua.execute('dfhack.maps.getTileFlags=function()return '+missing+' end')
            self.refusal('Site is unloaded or outside the map', action=1)
        self.lua.globals().dfhack.maps.getTileFlags = original_flags
        self.reset()
        self.assertTrue(self.finish(action=1)['ok'])
        self.lua.execute('flags.hidden=true')
        self.refusal('Hidden, cannot build at this location', action=2)
        self.assertEqual(len(self.lua.globals().created), 0)

    def test_native_extent_terrain_rechecked_and_unknown_fails_closed(self):
        for family in ['FarmPlot','RoadDirt','RoadPaved']:
            with self.subTest(family=family):
                self.setUp()
                self.lua.execute("native_terrain=function()return true,'' end;terrain_calls=0")
                self.assertTrue(self.finish(action=1,definition=family)['ok'])
                before=self.lua.globals().terrain_calls
                self.lua.execute("native_terrain=function()return false,'fixture native terrain refusal' end")
                self.refusal('fixture native terrain refusal',action=2,definition=family)
                self.assertGreater(self.lua.globals().terrain_calls,before)
                self.assertEqual(len(self.lua.globals().created),0)
                # One unknown native answer must abort, not become a skipped cell.
                self.lua.execute("native_terrain=function(p)if p.x==1 then return false,'' end;return true,'' end")
                self.refusal('',action=1,definition=family,width=2,height=1)
                self.assertEqual(len(self.lua.globals().created),0)
                self.helper=self.lua.execute(SOURCE)
                self.refusal('',action=1,definition=family)
                self.assertEqual(len(self.lua.globals().created),0)

    def test_native_extent_liquid_stage_preserves_fatal_and_skipped_cells(self):
        for family in ['FarmPlot','RoadDirt','RoadPaved']:
            for depth in range(2,7):
                with self.subTest(family=family,depth=depth):
                    self.setUp()
                    self.lua.execute("""local depth=...;native_terrain=function()return true,'' end
                        dfhack.maps.getTileFlags=function(p)return {flow_size=p.x==1 and depth or 0},{building=0}end""",depth)
                    for action in [1,2]:
                        self.refusal('Water at this location',action=action,definition=family,width=2,height=1)
                        self.assertEqual(len(self.lua.globals().created),0)
            for magma,depth in [(False,7),(True,1),(True,7)]:
                with self.subTest(family=family,magma=magma,depth=depth):
                    self.setUp()
                    self.lua.execute("df.new=function(kind,count)assert(kind=='uint8_t');return {}end;df.reinterpret_cast=function(_,ptr)return ptr end")
                    self.lua.execute("""local magma,depth=...;native_terrain=function(p)
                        return p.x~=1,'Blocked at this location' end
                        dfhack.maps.getTileFlags=function(p)return {flow_size=p.x==1 and depth or 0,liquid_type=magma},{building=0}end""",magma,depth)
                    preview=self.finish(action=1,definition=family,width=2,height=1)
                    self.assertTrue(preview['placement_valid'])
                    self.assertEqual(list(preview['valid_mask'].values()),[1,0])

    def test_opening_native_terrain_replaces_shape_filter(self):
        for family in ['Well','Hatch','GrateFloor','BarsFloor']:
            with self.subTest(family=family):
                self.setUp()
                self.lua.execute("shape=df.tiletype_shape.RAMP;native_open=function()return true,'' end")
                self.assertTrue(self.finish(action=1,definition=family)['placement_valid'])
                self.lua.execute("native_open=function()return false,'Must remove construction' end")
                self.refusal('Must remove construction',action=2,definition=family)
                self.assertEqual(len(self.lua.globals().created),0)

    def test_bridge_native_terrain_and_anchor_recheck(self):
        self.lua.execute("native_open=function()return true,'' end;native_floor=function()return false,'Blocked at this location' end")
        self.refusal('Needs to be anchored on edge',action=1,definition='Bridge')
        self.assertTrue(self.finish(action=1,definition='Bridge',retracting=True)['placement_valid'])
        self.lua.execute("native_floor=function()return true,'' end")
        self.assertTrue(self.finish(action=1,definition='Bridge')['placement_valid'])
        self.lua.execute("native_floor=function()return false,'' end")
        self.refusal('',action=1,definition='Bridge')
        self.assertFalse(self.finish(action=2,definition='Bridge')['ok'])
        self.lua.execute("native_open=function()return false,'Must remove construction' end")
        self.refusal('Must remove construction',action=1,definition='Bridge',retracting=True)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_bridge_native_perimeter_dimensions_and_commit_recheck(self):
        self.lua.execute("""
            native_perimeter=function(p,w,h)
                assert(p.x==0 and p.y==0 and w==3 and h==2)
                return perimeter_allowed~=false,perimeter_reason or 'Needs walkable perimeter'
            end
        """)
        self.assertTrue(self.finish(action=1,definition='Bridge',width=3,height=2)['placement_valid'])
        self.lua.execute('perimeter_allowed=false')
        self.refusal('Needs walkable perimeter',action=1,definition='Bridge',width=3,height=2)
        self.assertFalse(self.finish(action=2,definition='Bridge',width=3,height=2)['ok'])
        self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute("perimeter_reason=''")
        self.refusal('',action=1,definition='Bridge',width=3,height=2)

    def test_animal_trap_native_terrain_and_perimeter_recheck(self):
        for shape in ['RAMP','STAIR_UP','EMPTY']:
            with self.subTest(shape=shape):
                self.setUp()
                self.lua.execute("shape=df.tiletype_shape[...];perimeter_allowed=true",shape)
                self.assertTrue(self.finish(action=1,definition='AnimalTrap')['placement_valid'])
                self.lua.execute('perimeter_allowed=false')
                self.refusal('Needs walkable perimeter',action=2,definition='AnimalTrap')
                self.assertEqual(len(self.lua.globals().created),0)
        self.setUp()
        self.lua.execute("native_open=function()return false,'' end")
        self.refusal('',action=1,definition='AnimalTrap')

    def test_workshop_native_terrain_checks_entire_footprint(self):
        for reason in ['Blocked at this location','Must remove construction','']:
            with self.subTest(reason=reason):
                self.setUp()
                self.lua.execute("local reason=...;native_floor=function(p)if p.x==1 and p.y==1 then return false,reason end;return true,'' end",reason)
                for action in [1,2]:
                    self.refusal(reason,action=action,definition='Workshop:Carpenters',width=3,height=3)
                    self.assertEqual(len(self.lua.globals().created),0)

    def test_furniture_native_terrain_rechecked_and_unknown_fails_closed(self):
        for family in ['Bed','Door','Chair','WindowGem']:
            for reason in ['Must remove construction','Blocked at this location','']:
                with self.subTest(family=family,reason=reason):
                    self.setUp()
                    self.lua.execute("native_floor=function()return true,'' end")
                    self.assertTrue(self.finish(action=1,definition=family)['placement_valid'])
                    self.lua.execute("local reason=...;native_floor=function()return false,reason end",reason)
                    self.refusal(reason,action=2,definition=family)
                    self.assertEqual(len(self.lua.globals().created),0)

    def test_opening_liquid_refusals_precede_support(self):
        for family in ['Well','Hatch','GrateFloor','BarsFloor']:
            for magma,depth in [(False,n) for n in range(2,8)]+[(True,n) for n in range(1,8)]:
                with self.subTest(family=family,magma=magma,depth=depth):
                    self.setUp()
                    self.lua.execute("shape=df.tiletype_shape.EMPTY;flags.flow_size=...",depth)
                    self.lua.execute("flags.liquid_type=...",magma)
                    self.lua.execute("support_allowed={};support_allowed[...]=false",family)
                    for action in [1,2]:
                        self.refusal('Lava/Magma at this location' if magma else 'Water at this location',action=action,definition=family)
                        self.assertEqual(len(self.lua.globals().created),0)

    def test_floor_opening_native_support_rechecked(self):
        for family in ['Well','Hatch','GrateFloor','BarsFloor']:
            with self.subTest(family=family):
                self.lua.execute('support_allowed={};support_calls=0;shape=df.tiletype_shape.EMPTY')
                self.assertTrue(self.finish(action=1,definition=family)['ok'])
                before=self.lua.globals().support_calls
                self.lua.execute('support_allowed[...]=false',family)
                self.refusal('fixture native support refusal',action=2,definition=family)
                self.assertGreater(self.lua.globals().support_calls,before)
                self.assertEqual(len(self.lua.globals().created),0)

    def test_door_support_rechecked_after_preview(self):
        self.lua.execute('door_allowed=true;door_calls=0')
        self.assertTrue(self.finish(action=1,definition='Door')['ok'])
        before=self.lua.globals().door_calls
        self.lua.execute('door_allowed=false')
        self.refusal('fixture native Door refusal',action=2,definition='Door')
        self.assertGreater(self.lua.globals().door_calls,before)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_site_rule_edges_and_direction_limits(self):
        for direction in range(4):
            self.lua.execute('shape=df.tiletype_shape.RAMP')
            self.refusal('Needs to be anchored on edge',action=1,definition='Bridge',direction=direction)
            self.assertTrue(self.finish(action=1,definition='Bridge',direction=direction,retracting=True)['ok'])
            self.lua.execute('shape=df.tiletype_shape.EMPTY')
            self.refusal('Needs to be anchored on edge',action=1,definition='Bridge',direction=direction)
        self.lua.execute('shape=0')
        for family,directions in [('AxleHorizontal',range(2)),('Rollers',range(4))]:
            for direction in directions:
                vertical=direction==1 if family=='AxleHorizontal' else direction%2==0
                w,h=(1,31) if vertical else (31,1)
                self.assertTrue(self.finish(action=1,definition=family,direction=direction,width=w,height=h)['ok'])
                for width,height in ((w+1,h),(w,h+1)):
                    self.refusal("Size exceeds this building's limits",action=1,definition=family,direction=direction,width=width,height=height)

    def test_retired_strings_absent(self):
        for text in ('Not yet supported: special placement or input workflow','Dry floor required',
                     'Site has no terrain support','Select one construction input'):
            self.assertNotIn(text,SOURCE)

    def test_roller_speed_reaches_native_constructor(self):
        for speed in (0,10000,20000,30000,40000,50000):
            row=self.selection(definition='Rollers')
            result=self.finish(action=2,definition='Rollers',roller_speed=speed,selections=[row])
            self.assertTrue(result['ok'],result['message'])
            created=self.lua.globals().created
            self.assertEqual(created[len(created)]['fields']['speed'],speed or 50000)
        for speed in (-10000,1,15000,60000):
            self.refusal('Invalid roller speed intent',action=1,definition='Rollers',roller_speed=speed)
        self.refusal('Invalid roller speed intent',action=1,definition='Chair',roller_speed=10000)

    def test_track_stop_profile_reaches_native_constructor(self):
        vectors=[(0,0),(0,-1),(1,0),(0,1),(-1,0)]
        for friction in (10,50,500,10000,50000):
            for direction,(dx,dy) in enumerate(vectors):
                row=self.selection(definition='Trap:TrackStop')
                result=self.finish(action=2,definition='Trap:TrackStop',track_stop={'friction':friction,'dump_direction':direction},selections=[row])
                self.assertTrue(result['ok'],result['message'])
                created=self.lua.globals().created
                profile=created[len(created)]['fields']['track_stop_info']
                self.assertEqual((profile['friction'],profile['dump_x_shift'],profile['dump_y_shift']),(friction,dx,dy))
                self.assertEqual(profile['track_flags']['use_dump'],direction!=0)
        for options in ({},{'friction':0,'dump_direction':0},{'friction':50000,'dump_direction':5}):
            self.refusal('Invalid track stop intent',action=1,definition='Trap:TrackStop',track_stop=options)
        self.refusal('Unexpected track stop intent',action=1,definition='Chair',track_stop={'friction':50000,'dump_direction':0})

    def test_pressure_plate_recorded_profiles_reach_native_constructor(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/pressure_plate.json').read_text())
        quantities={r['bits']:r['native'] for r in fixture['native_quantity']['capture']['cases']}
        self.assertEqual(set(quantities.values()),{1})
        for row in fixture['native_quantity']['capture']['cases']:
            self.assertEqual(row['bits'],row['configured_flags']);self.assertEqual(row['bits'],row['picker_flags'])
        state=fixture['default']
        default={**state['flags'],**{k:state[k] for k in ('unit_min','unit_max','water_min','water_max','magma_min','magma_max','track_min','track_max')}}
        profiles=[default]
        for r in fixture['controls']['fluid_ranges']:
            profiles.append({**default,r['kind']:True,r['kind']+'_min':r['expected_min'],r['kind']+'_max':r['expected_max']})
        for r in fixture['controls']['cart_boundaries']:
            profiles.append({**default,'track':True,'track_min':r['track_min'],'track_max':r['track_max']})
        for r in fixture['scroll']['bottom_choices']:
            profiles.append({**default,'units':True,'unit_min':r['unit_min'],'unit_max':r['unit_max']})
        for bits in range(64):
            profiles.append({**default,**{key:bool(bits & (1<<i)) for i,key in enumerate(('units','water','magma','citizens','resets','track'))}})
        self.lua.execute("df.global.buildreq=setmetatable({}, {__index=function()error('native widget read')end})")
        native_recipe=self.lua.eval("function(t,s,c,...)assert(t==df.building_type.Trap and s==df.trap_type.PressurePlate and c==-1 and select('#',...)==0);return {status=0,recipes={{count_required=1}}}end")
        accepted={r['bits']:r['errors']!=['Need trigger type'] for r in fixture['native_trigger']['cases'] if r['case']=='dry'}
        for options in profiles:
            row=self.selection(definition='Trap:PressurePlate')
            result=self.finish(action=2,definition='Trap:PressurePlate',pressure_plate=options,selections=[row],native_material_recipe=native_recipe)
            bits=sum((1<<i) for i,key in enumerate(('units','water','magma','citizens','resets','track')) if options[key])
            self.assertEqual(result['ok'],accepted[bits],options)
            if not accepted[bits]:
                self.assertEqual(result['message'],'Need trigger type');continue
            created=self.lua.globals().created
            self.assertEqual(len(created[len(created)]['items']),quantities[bits])
            actual=created[len(created)]['fields']['plate_info']
            for key,value in options.items():
                self.assertEqual(actual['flags'][key] if key in default and isinstance(value,bool) else actual[key],value)

    def test_pressure_trigger_native_order_unknown_and_commit_recheck(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'fixtures/construction/pressure_plate.json').read_text())
        d=fixture['default'];default={**d['flags'],**{k:d[k] for k in ('unit_min','unit_max','water_min','water_max','magma_min','magma_max','track_min','track_max')}}
        for row in fixture['native_trigger']['cases']:
            options={**default,**{key:bool(row['bits']&(1<<i)) for i,key in enumerate(('units','water','magma','citizens','resets','track'))}}
            reason={0:'',7:'Hidden, cannot build at this location',10:'Water at this location'}[row['code']]
            self.lua.execute("local reason=...;native_ordinary=function()return reason=='',reason,true end",reason)
            result=self.finish(action=1,definition='Trap:PressurePlate',pressure_plate=options)
            self.assertEqual(result['ok'],not row['errors'],row)
            self.assertEqual(result['message'],'\n'.join(row['errors']),row)
        self.lua.execute("native_ordinary=function()return true,'',true end;native_trigger=function()return false,'unverified',false end")
        for action in (1,2):
            result=self.finish(action=action,definition='Trap:PressurePlate',pressure_plate={**default,'units':True})
            self.assertFalse(result['ok']);self.assertEqual(result['message'],'')
        self.lua.execute("dfhack.buildings.getFiltersByType=function()return {}end;trigger_calls=0;native_trigger=function()trigger_calls=trigger_calls+1;return trigger_calls==1,'Need trigger type',true end")
        result=self.finish(action=2,definition='Trap:PressurePlate',pressure_plate={**default,'units':True})
        self.assertFalse(result['ok']);self.assertEqual(result['message'],'Need trigger type')
        self.assertEqual(len(self.lua.globals().created),0)

    def test_pressure_plate_rejects_malformed_profiles_before_creation(self):
        default=dict(units=False,water=False,magma=False,citizens=False,resets=True,track=False,
                     unit_min=5000,unit_max=200000,water_min=1,water_max=7,magma_min=1,magma_max=7,track_min=1,track_max=2000)
        for key,value in [('units',1),('resets','true'),('unit_min',0),('unit_min',1500),('unit_max',200000999),
                          ('unit_max',4000),('unit_max',6500),('water_min',-1),('water_max',8),('magma_min',8),
                          ('track_min',2),('track_max',0),('track_max',2050),('water_min',1.5)]:
            self.refusal('Invalid pressure plate intent',action=1,definition='Trap:PressurePlate',pressure_plate={**default,key:value})
        self.refusal('Invalid pressure plate intent',action=1,definition='Trap:PressurePlate')
        self.refusal('Invalid pressure plate intent',action=1,definition='Trap:PressurePlate',pressure_plate={})
        self.refusal('Unexpected pressure plate intent',action=1,definition='Chair',pressure_plate=default)
        self.assertEqual(len(self.lua.globals().created),0)

    def test_piece_rule_exact_messages_and_requirement_tokens(self):
        # As in the work-order exemplar's receipt test, expose a private pure
        # rule in this isolated closure to assert reasons that Preview reduces
        # to mask bytes. No product source or runtime exports are changed.
        self.lua.execute(SOURCE.replace('local function native_site(', 'test_tile_rule=tile_rule\nlocal function native_site('))
        rule=self.lua.globals().test_tile_rule
        request=self.lua.table_from(dict(x=0,y=0,z=0,width=1,height=1,depth=1,direction=0))
        definition=self.lua.table_from(dict(family='Construction',subtype_key='Wall'))
        pos=self.lua.table_from(dict(x=0,y=0,z=0))
        # Missing native service must fail closed, even on plausible floor.
        self.assertEqual(rule(request,definition,pos),(False,'',True))
        for raw,expected in [("{quantity=1,has_tool_use=1}",'SCREW'),
                             ("{quantity=1,flags2={whole=0,building_material=true}}",'building_material')]:
            self.lua.execute('recipes[df.building_type.Chair]={'+raw+'}')
            self.reset()
            self.assertEqual(self.finish(action=1)['filters'][1]['requirement'],expected)
    def test_preview_and_custom_resolution(self):
        self.refusal('Depth applies to stairs only',action=1,depth=2)
        self.refusal("Size exceeds this building's limits",action=1,width=32)
        self.refusal('This building has a fixed size',action=1,definition='Workshop:Carpenters')
        self.refusal('Orientation not available for this building',action=1,direction=1)
        self.refusal('Must span multiple elevations',action=1,definition='Construction:Stairs')
        self.lua.execute('recipes[df.building_type.Bridge]={{quantity=-1,vector_id=1}}')
        self.reset()
        preview=self.finish(action=1,definition='Bridge',width=4,height=3)
        self.assertTrue(preview['placement_valid'], 'completed Preview must enable the presentation draft')
        self.assertEqual(preview['required'],4)
        self.assertEqual(preview['filters'][1]['requirement'],'BLOCKS')
        self.assertEqual(list(preview['valid_mask'].values()),[1]*12)
        self.assertEqual((preview['footprint']['width'],preview['footprint']['height']),(4,3))
        for name,w,h,d in [('Chair',1,1,1),('Bridge',2,2,1),('Construction:Wall',2,2,1),('Construction:Stairs',2,2,3)]:
            p=self.finish(action=1,definition=name,width=w,height=h,depth=d)
            self.assertTrue(p['placement_valid'], name)
            self.assertEqual(list(p['valid_mask'].values()),[1]*(w*h*d))
            if d==3:self.assertEqual(list(p['pieces'].values()),[1]*4+[3]*4+[2]*4)
        self.lua.execute("customs[1].code='SCREW_PRESS';customs[2].code='SOAP_MAKER';customs[2].class='workshop'")
        self.reset()
        for key,index,size in [('Workshop:Custom:SCREW_PRESS',1,3),('Workshop:Custom:SOAP_MAKER',2,3)]:
            row=self.selection(definition=key)
            self.lua.execute('customs[...].id=77',index)
            result=self.finish(action=2,definition=key,width=size,height=size,selections=[row])
            self.assertTrue(result['ok'],result['message'])
            self.assertEqual(self.lua.globals().created[len(self.lua.globals().created)]['custom'],77)

    def test_placed_custom_workshop_find_by_id(self):
        # constructBuilding(info) returns the linked building, with an ID assigned
        # by Buildings.cpp:1040. df.building.find(id) takes one numeric ID and
        # returns that building or nil, never an index or a coordinate.
        self.lua.execute(r"""
        linked={}
        local construct=dfhack.buildings.constructBuilding
        dfhack.buildings.constructBuilding=function(info)
          local b=construct(info)
          b.x1=info.pos.x;b.y1=info.pos.y;b.z=info.pos.z
          b.x2=b.x1+2;b.y2=b.y1+2
          b.centerx=b.x1+2;b.centery=b.y1+1 -- raw work location, not midpoint
          b.custom_type=info.custom;b.jobs={}
          b.getType=function()return info.type end
          b.getSubtype=function()return info.subtype end
          b.getCustomType=function()return b.custom_type end
          b.getBuildStage=function()return 0 end;b.getMaxBuildStage=function()return 3 end
          linked[b.id]=b;return b
        end
        df.building={find=function(id,...)
          assert(type(id)=='number' and select('#',...)==0)
          return linked[id]
        end}
        dfhack.buildings.markedForRemoval=function()return false end
        dfhack.buildings.getName=function()return 'screw press' end
        dfhack.maps.isValidTilePos=function(p)
          return p and p.x>=0 and p.y>=0 and p.z==0
        end
        """)
        self.lua.execute("customs[1].code='SCREW_PRESS'")
        self.reset()
        key='Workshop:Custom:SCREW_PRESS'
        row=self.selection(definition=key)
        placed=self.finish(action=2,definition=key,width=3,height=3,selections=[row])
        self.assertTrue(placed['ok'],placed['message'])
        bid=placed['first_building']
        self.assertGreater(bid,0)
        found=self.finish(action=3,building_id=bid)
        self.assertTrue(found['ok'],found['message'])
        self.assertEqual(found['building_id'],bid)
        self.assertEqual(found['building_key'],key)
        self.assertEqual(found['message'],'screw press')
        self.refusal('Building is no longer available',action=3,building_id=bid+1)
        self.lua.execute('flags.hidden=true')
        self.refusal('Building is no longer available',action=3,building_id=bid)
        self.lua.execute('flags.hidden=false;linked[...] = nil',bid)
        self.refusal('Building is no longer available',action=3,building_id=bid)

    def test_chunked_place_and_dirty_cache(self):
        row=self.selection(1024,definition='Construction:Stairs',width=16,height=16,depth=4)
        self.seq+=1
        args=dict(action=2,definition='Construction:Stairs',width=16,height=16,depth=4,selections=[row])
        chunks=[]
        for _ in range(20):
            result=self.call(**args)
            self.assertLessEqual(result['chunk_placed'],128)
            if result['chunk_placed']:chunks.append(result['chunk_placed'])
            if not result['pending']:break
        self.assertTrue(result['ok'],result['message'])
        self.assertEqual(chunks,[128]*8)
        self.assertEqual((result['placed'],result['skipped'],result['first_building']),(1024,0,101))
        dirty=self.call(definition='Construction:Stairs',width=16,height=16,depth=4)
        self.assertEqual(dirty['build_phase'],1)
        self.assertEqual(dirty['list_revision'],row['expected_list_revision'])
        self.assertEqual(dirty['cache_entries'],2)  # retained snapshot plus replacement

    def test_short_group_release_and_retired_items(self):
        row=self.selection(2,definition='Construction:Wall',width=2)
        self.lua.execute('for i=2,1024 do stock[i].flags.forbid=true end')
        self.refusal('Selected material no longer available; refresh materials',action=2,
                     definition='Construction:Wall',width=2,selections=[row])
        self.assertEqual(len(self.lua.globals().created),0)
        self.lua.execute('stock[2].flags.forbid=false')
        result=self.finish(action=2,definition='Construction:Wall',width=2,selections=[row])
        self.assertTrue(result['ok'],result['message'])
        self.refusal('selected inputs are retired; use selections',action=2,items=[1])
        self.refusal('Selections do not cover the recipe',action=2,selections=[])

    def test_spec_stale_material_refusal(self):
        row=self.selection();row['expected_list_revision']+=1
        self.refusal('List changed; refresh',action=2,selections=[row])

    def test_mid_place_taken_skip_and_reset(self):
        for mode in ('taken','occupied','reset'):
            with self.subTest(mode=mode):
                self.lua.execute('fill(1024);created={};occupied={};for _,item in pairs(stock)do item.pos.x=item.id end')
                self.reset();row=self.selection(600,definition='Construction:Wall',width=30,height=20)
                self.seq+=1
                args=dict(action=2,definition='Construction:Wall',width=30,height=20,selections=[row],step_budget=1200)
                result=self.call(**args)
                while result['pending'] and result['placed']<256: result=self.call(**args)
                self.assertEqual(result['placed'],256)
                if mode=='taken':
                    self.lua.execute('stock[257].flags.in_job=true')
                    result=self.call(**args)
                    self.assertFalse(result['ok'])
                    self.assertEqual(result['message'],'Painted 256 of 600; Selected material was taken during placement')
                    self.assertEqual((result['placed'],result['chunk_placed']),(256,0))
                elif mode=='occupied':
                    self.lua.execute("occupied['16:8:0']=true")
                    while result['pending']:result=self.call(**args)
                    self.assertFalse(result['ok'])
                    self.assertEqual((result['placed'],result['skipped']),(256,0))
                    self.assertEqual(result['message'],'Painted 256 of 600; Building present')
                    self.assertEqual(len(self.lua.globals().created),256)
                else:
                    self.reset()
                    result=self.call(**args)
                    while result['pending']:result=self.call(**args)
                    self.assertEqual(result['message'],'List changed; refresh')
                    self.assertEqual(result['placed'],0)
                    self.assertEqual(len(self.lua.globals().created),256)

    def test_builder_phases_ticks_caps_lru(self):
        self.lua.execute('fill(129,true)');self.reset()
        first=self.call()
        self.assertEqual((first['build_phase'],first['build_done'],first['build_total']),(1,0,130))
        counts={1:0,2:0}
        while True:
            p=self.call()
            if p['build_phase']==0:break
            phase=p['build_phase'];step=self.call(step=1)
            self.assertLessEqual(step['steps'],1);counts[phase]+=step['steps']
        self.assertEqual(counts[1],131)  # resume after the last read enters the first merge move
        signature='|'.join(['0','-1','-1','-1','0','-1','-1']+['nil']*5+['0']*3)+'|0:0:0'
        # Native sorting is one safe-point query; no local merge-sort moves remain.
        self.assertGreater(counts[2],0)
        self.assertLessEqual(sum(counts.values()),130+len('7|'+signature)+129*4)
        self.assertEqual(len(p['materials']),128);self.assertEqual(p['next_cursor'],128)
        tail=self.call(cursor=128,expected_list_revision=p['list_revision'])
        self.assertEqual(len(tail['materials']),1)
        self.assertEqual(tail['next_cursor'],0)
        self.reset();self.call();calls=0
        while self.call()['build_phase']:
            self.call(step=2048);calls+=1
        self.assertEqual(calls,(sum(counts.values())//2048)+1)
        self.lua.execute('df.global.cur_year_tick=1200')
        self.assertEqual(self.call()['build_phase'],0)
        self.lua.execute('df.global.cur_year_tick=1201')
        self.assertEqual(self.call()['build_phase'],1)
        self.page()
        self.lua.execute('df.global.cur_year=2;df.global.cur_year_tick=0')
        self.assertEqual(self.call()['build_phase'],1)
        self.reset();reset=self.call()
        self.assertEqual((reset['build_phase'],reset['build_done'],reset['build_total']),(1,0,130))
        self.page()
        for x in range(1,4):self.page(x=x)
        self.page(x=0)  # refresh LRU use
        self.assertEqual(self.page(x=4)['cache_entries'],4)
        self.assertEqual(self.call(x=0)['build_phase'],0)
        self.assertEqual(self.call(x=1)['build_phase'],1)
        for n in (1000,65537):
            self.lua.execute('fill(...)',n);self.reset()
            if n==1000:
                result=self.page();self.assertTrue(result['ok'],result['message'])
                self.assertEqual(result['materials'][1]['count'],1000)
                for x in range(1,4):self.page(x=x)
                stats=self.call(x=3)
                self.assertEqual((stats['cache_entries'],stats['cache_ids']),(4,4*1000))
                self.assertLess(self.lua.eval("(function()collectgarbage('collect');return collectgarbage('count')end)()"),100*1024)
            else:
                self.call()
                while True:
                    step=self.call(step=2048)
                    if not step['active']:break
                self.assertEqual(step['cache_ids'],0)
                self.assertFalse(self.call(step=2048)['active'])
                result=self.call()
                self.assertFalse(result['ok'])
                self.assertEqual(result['build_phase'],3)
                self.assertEqual(result['message'],'Materials list unavailable: list exceeds cap')
                self.assertFalse(self.call(step=2048)['active'])
                for _ in range(3):
                    repeat=self.call()
                    self.assertFalse(repeat['ok'])
                    self.assertEqual(repeat['message'],'Materials list unavailable: list exceeds cap')
                    self.assertEqual(repeat['build_phase'],3)
                    self.assertEqual(repeat['build_done'],result['build_done'])
                    self.assertFalse(self.call(step=2048)['active'])
                self.call(action=0,cursor=128)  # Paging is not an explicit refresh.
                self.assertEqual(self.call()['build_phase'],3)
                catalog=self.call(action=0,cursor=128)
                self.call(action=0,cursor=0,expected_list_revision=catalog['list_revision'])
                self.assertEqual(self.call()['message'],'Materials list unavailable: list exceeds cap')
                self.call(action=0,cursor=0,expected_list_revision=0)
                retry=self.call()
                self.assertTrue(retry['ok'])
                self.assertEqual((retry['build_phase'],retry['build_done']),(1,0))

    def test_diagnostic_collection_can_be_disabled_during_a_build(self):
        self.lua.execute("""fill(6);profile_rows={};dfhack.df3d_construction_profile=profile_rows
          local clock=0;dfhack.getTickCount=function()clock=clock+1;return clock end""")
        self.reset()
        first=self.call()
        self.assertNotEqual(first['build_phase'],0)
        self.lua.execute('dfhack.df3d_construction_profile=nil')
        result=self.page()
        self.assertTrue(result['ok'])
        profile=self.lua.globals().profile_rows[1]
        self.assertGreater(profile['slices'],0)
        self.assertGreaterEqual(profile['elapsed_ms'],0)

    def test_material_rows(self):
        self.lua.execute('''fill(6);stock[1].mat=2;stock[1].pos.x=7;stock[2].mat=1;stock[2].pos.x=1
          stock[3].mat=1;stock[3].flags.on_ground=false;stock[3].container={flags={on_ground=true},getType=function()return 97 end}
          stock[4].nameless=true;stock[5].flags.forbid=true;stock[6].pos.z=1;walk_groups[stock[6].pos.x..':0:1']=2
          stock[1].name=string.rep('n',129)''')
        self.lua.execute("dfhack.maps.getTileBlock=function(p)return {walkable=setmetatable({},{__index=function()return setmetatable({},{__index=function()return walk_groups[p.x..':'..p.y..':'..p.z] or 1 end})end})}end")
        self.reset();p=self.page()
        self.assertEqual([(r['mat_index'],r['count']) for r in p['materials'].values()],[(1,2),(2,1)])
        self.assertTrue(p['estimated']);self.assertEqual(p['message'],'')
        self.assertEqual(len(p['materials'][2]['name'].encode()),128)
        self.lua.execute('stock[3].container.flags.in_job=true;df.global.cur_year_tick=1201')
        self.assertEqual(self.page()['materials'][1]['count'],1)
        self.assertGreater(p['list_revision'],0);self.assertLessEqual(p['list_revision'],2**63-1)

    def test_stairs_rebuild_and_orientation_arguments(self):
        for existing in ('STAIR_UP','STAIR_DOWN','STAIR_UPDOWN'):
            self.lua.execute('shape=df.tiletype_shape[...]',existing)
            self.refusal('Must span multiple elevations',action=1,definition='Construction:Stairs',depth=1)
            p=self.finish(action=1,definition='Construction:Stairs',depth=3)
            self.assertEqual(list(p['pieces'].values()),{'STAIR_UP':[1,3,3],'STAIR_DOWN':[3,3,2],'STAIR_UPDOWN':[3,3,3]}[existing])
            self.assertEqual(list(p['valid_mask'].values()),[1,1,1])
        self.lua.execute('shape=0;df.tiletype.attrs[0].material=df.tiletype_material.CONSTRUCTION;existing={}')
        p=self.finish(action=1,definition='Construction:Wall')
        self.assertEqual(list(p['valid_mask'].values()),[1])
        p=self.finish(action=1,definition='Construction:Wall',width=2)
        self.assertEqual(list(p['valid_mask'].values()),[1,1])
        p=self.finish(action=1,definition='Construction:Floor')
        self.assertEqual(list(p['valid_mask'].values()),[1])
        self.lua.execute('df.tiletype.attrs[0].material=0;existing=nil')
        for name,directions in [('ScrewPump',range(4)),('Rollers',range(4)),
                                ('WaterWheel',range(2)),('AxleHorizontal',range(2)),('Bridge',range(5))]:
            for direction in directions:
                row=self.selection(definition=name,direction=direction if direction<4 else 0)
                r=self.finish(action=2,definition=name,direction=direction if direction<4 else 0,
                              retracting=direction==4,selections=[row])
                self.assertTrue(r['ok'],r['message'])
                build=self.lua.globals().created[len(self.lua.globals().created)]
                self.assertEqual(build['direction'],direction if direction<4 else -1)
                self.assertEqual(build['type'],self.lua.globals().df.building_type[name])
        # DFHack applies these direction parameters to native fields; that write
        # belongs to the MSVC/live check, not this synthetic constructBuilding.

    def test_native_candidate_rows_clip_names_and_omit_empty_names(self):
        for size in (128,129):
            self.lua.execute("fill(1);stock[1].name=string.rep('n',...)",size);self.reset()
            self.assertEqual(len(self.page()['materials'][1]['name']),128)
        self.lua.execute("fill(1);stock[1].name=''");self.reset()
        self.assertEqual(len(self.page()['materials']),0)

    def test_unknown_custom_recipe_has_no_copied_material_gate(self):
        result=self.page(definition='Workshop:Custom:PRESS')
        self.assertFalse(result['ok'])
        self.assertEqual(result['message'], '')
        self.assertEqual(result['cache_entries'], 0)
        self.assertNotIn('local function screen(', SOURCE)

    def test_shared_budget_two_real_closures(self):
        # Both real domain closures progress, with the request's inline work
        # deducted first. The production C++ scheduler is reviewed separately.
        self.lua.execute("""df.global.world.manager_orders={all=vec{}}
          local names={};for i=1,900 do names[i]='TYPE'..i end
          df.item_type=enum(names);df.item_type.TOOL=9999;df.item_type.BAR=9998
          dfhack.items.getSubtypeCount=function()return 0 end""")
        work=self.lua.execute((Path(__file__).resolve().parents[1] / 'bridge/plugin/work_orders.lua').read_text())
        request=self.lua.table_from(dict(action=26,epoch=7,seq=1,
            work_order=dict(candidate_kind=3,query='',cursor=0)),recursive=True)
        self.call()
        self.assertTrue(work(request)['ok'])
        self.seq+=1
        before=0
        for _ in range(2):
            self.assertTrue(work(request)['ok'])
            inline=self.call(action=1,definition='Construction:Wall',width=31,height=31,step_budget=64)
            self.assertEqual(inline['steps'],64)
            left=2048-inline['steps']
            construction=self.call(step=left//2)
            orders=work(self.lua.table_from(dict(step=left-left//2,builder_kind=0)))
            self.assertGreater(construction['steps'],0)
            self.assertGreater(orders['steps'],0)
            self.assertLessEqual(inline['steps']+construction['steps']+orders['steps'],2048)
            progress=self.call()
            self.assertGreater(progress['build_done'],before)
            before=progress['build_done']

    def test_masked_fnv_high_bit(self):
        for epoch in range(64):
            page=self.call(action=0,epoch=epoch)
            h=0xcbf29ce484222325
            for byte in f"{epoch}|1|{page['total']}".encode():
                h=((h^byte)*0x100000001b3)&((1<<64)-1)
            self.assertEqual(page['list_revision'],(h&((1<<63)-1)) or 1)
            if h >= 1<<63:break
        else:self.fail('fixture failed to exercise the unmasked high bit')

    def test_stair_effects_remain_inspectable_without_legacy_catalog_entries(self):
        catalog=self.call(action=0)
        keys={v['key'] for v in catalog['catalog'].values()}
        self.assertIn('Construction:Stairs',keys)
        self.lua.execute("""building={id=1,centerx=0,centery=0,z=0,jobs={},
            getType=function()return df.building_type.Construction end,
            getSubtype=function()return stair_subtype end,
            getBuildStage=function()return 0 end,getMaxBuildStage=function()return 1 end}
            df.building={find=function()return building end}
            dfhack.buildings.markedForRemoval=function()return false end
            dfhack.buildings.getName=function()return '' end
            cancelled=0;dfhack.buildings.deconstruct=function()cancelled=cancelled+1;return true end""")
        for subtype in ('UpStair','DownStair','UpDownStair'):
            key='Construction:'+subtype
            self.assertNotIn(key,keys)
            self.lua.globals().stair_subtype=self.lua.globals().df.construction_type[subtype]
            inspected=self.finish(action=3,building_id=1)
            self.assertTrue(inspected['ok']);self.assertEqual(inspected['building_key'],key)
            cancelled=self.finish(action=4,building_id=1,definition=key)
            self.assertTrue(cancelled['ok']);self.assertTrue(cancelled['removing'])
        self.assertEqual(self.lua.globals().cancelled,3)

    def test_removal(self):
        self.lua.execute('''building={id=1,centerx=0,centery=0,z=0,jobs={},getType=function()return df.building_type.Chair end,
          getSubtype=function()return -1 end,getBuildStage=function()return 0 end,getMaxBuildStage=function()return 1 end}
          df.building={find=function()return building end};marked=false;cancel=true
          dfhack.buildings.markedForRemoval=function()return marked end
          dfhack.buildings.deconstruct=function()return cancel end
          dfhack.buildings.getName=function()return ''end
          dfhack.constructions={findAtTile=function()return terrain end,designateRemove=function(p)return true,false end}''')
        self.refusal('Building changed; inspect again',action=4,definition='Bed',building_id=1)
        self.lua.execute('marked=true')
        self.refusal('Already marked for removal',action=4,building_id=1)
        self.lua.execute('marked=false')
        self.lua.execute('''df.job_type=df.job_type or {};df.job_type.DestroyBuilding=999
          building.jobs={{job_type=999},{job_type=1}};marked=true;removed_jobs=0
          dfhack.job={removeJob=function(j)assert(j.job_type==999);removed_jobs=removed_jobs+1;table.remove(building.jobs,1);marked=false end}''')
        self.assertFalse(self.finish(action=4,building_id=1,cancel_removal=True)['removing'])
        self.assertEqual(self.lua.globals().removed_jobs,1)
        self.finish(action=4,building_id=1,cancel_removal=True)
        self.assertEqual(self.lua.globals().removed_jobs,1)
        self.assertEqual(self.finish(action=4,building_id=1)['message'],'Unbuilt construction cancelled')
        catalog=self.call(action=0)['catalog']
        for row in catalog.values():
            if row['family'] in ('Stockpile','Civzone') or row['key'] in ('Construction:Track','Construction:Stairs'):
                continue
            if row['custom_code'] and row['key']!='Workshop:Custom:PRESS':
                continue
            self.lua.execute('building.getCustomType=function()return 11 end')
            self.lua.execute("""local ty,st=...;building.getType=function()return ty end
              building.getSubtype=function()return st end""",row['type'],row['subtype'])
            self.assertEqual(self.finish(action=4,definition=row['key'],building_id=1)['message'],
                             'Unbuilt construction cancelled')
        self.lua.execute('building.getType=function()return df.building_type.Chair end')
        for family in ('Stockpile','Civzone'):
            self.lua.execute('local family=...;building.getType=function()return df.building_type[family] end',family)
            self.refusal('Placed from the stockpile and zone menus',action=4,definition=family,building_id=1)
        self.lua.execute('building.getType=function()return df.building_type.Chair end;cancel=false')
        self.assertEqual(self.finish(action=4,building_id=1)['message'],'Native deconstruction queued')
        self.refusal('No removable completed construction at this tile',action=6)
        self.lua.execute('terrain={flags={}}')
        self.assertEqual(self.finish(action=6)['message'],'Native construction removal designated')
        self.lua.execute('valid=false')
        self.refusal('Construction tile is hidden or outside the map',action=6)


class Lane(unittest.TestCase):
    def test_fixture_machine_parts(self):
        lua=catalog_runtime()
        lua.execute(r"""
        df.item_type={WOOD=5,BALLISTAPARTS=62,CATAPULTPARTS=63,TRAPCOMP=68,[5]="WOOD"}
        state={stock={},incomplete={},unavailable_types={}};unit={pos={x=1,y=2,z=3}}
        function missing(k,reason)state.incomplete[k]=reason end
        local wood={getType=function()return 5 end,getSubtype=function()return -1 end,
          getMaterial=function()return 419 end,getMaterialIndex=function()return 7 end}
        df.global.world.items={all=vec{wood}}
        df.global.world.raws.itemdefs={trapcomps=vec{{flags={}},{flags={IS_SCREW=true}}}}
        created={};dfhack.items={createItem=function(u,t,st,mt,mi,...)
          assert(u==unit and mt==419 and mi==7 and select('#',...)==0)
          if t==63 and unavailable then return {} end
          if t==68 then assert(st==1) elseif t==62 or t==63 then assert(st==-1) end
          created[t]=(created[t] or 0)+1;return {{id=created[t],flags={}}}
        end,moveToGround=function(item,pos)assert(pos==unit.pos);return true end}
        """)
        source=(Path(__file__).parent/'smoke/construction-acceptance-fixture.lua').read_text()
        seeds=source[source.index('local kinds='):source.index('local bin=')]
        lua.execute(seeds)
        self.assertEqual(lua.eval('#state.stock.TRAPCOMP'),24)
        self.assertEqual(lua.eval('#state.stock.CATAPULTPARTS'),24)
        self.assertIsNone(lua.eval("state.unavailable_types['68']"))
        lua.execute('unavailable=true;df.global.world.raws.itemdefs.trapcomps=vec{}')
        lua.execute(seeds)
        self.assertEqual(lua.eval("state.unavailable_types['63']"),'no items created')
        self.assertEqual(lua.eval("state.unavailable_types['68']"),'no material/subtype seed for item creation')

    def test_native_exists_evidence(self):
        lua=catalog_runtime()
        lua.execute(r"""
        package.preload.json=function()return {decode=function()return request end,
          encode=function(v)response=v;return '' end}end
        io.open=function()return {read=function()return '' end,write=function()end,close=function()end}end
        print=function()end;df3d_construction_acceptance={}
        building={id=1503,x1=121,y1=54,x2=123,y2=56,z=165,centerx=123,centery=55,
          getCustomType=function()return 7 end}
        df.global.world.buildings={all=vec{building}}
        df.building={find=function(id,...)assert(id==1503 and select('#',...)==0);return lookup and building or nil end}
        dfhack.buildings.findAtTile=function(p)return tile and building or nil end
        dfhack.maps={getTileFlags=function(p)assert(p.x==123 and p.y==55);return {hidden=hidden} end}
        request={op='exists',id=1503,origin={x=121,y=54,z=165},phase='before step 6'}
        """)
        source=(Path(__file__).parent/'smoke/construction-acceptance-verify.lua').read_text()
        for setup,found,world,tile,hidden in [
            ('lookup=true;tile=true;hidden=false',True,True,1503,False),
            ('lookup=false',False,True,1503,False),
            ('lookup=true;hidden=true',True,True,1503,True),
            ('lookup=false;tile=false;df.global.world.buildings.all=vec{}',False,False,-1,None)]:
            lua.execute(setup);lua.execute(source,'memory','1');r=lua.globals().response
            self.assertEqual(r['status'],'passed')
            self.assertEqual((r['found_by_id'],r['found_in_world'],r['tile_id'],r['center_hidden']),
                             (found,world,tile,hidden))

    def test_api_position_contract(self):
        lua = catalog_runtime()
        # These mocks must fail on the exact tuple-to-coord bug from review D-2.
        self.assertEqual(lua.eval("position({pos={x=1,y=2,z=3}})"), (1, 2, 3))
        self.assertIsNone(lua.eval("position({})"))
        self.assertFalse(lua.eval("pcall(walkable_group,1,2,3)")[0])
        self.assertEqual(lua.eval("walkable_group(xyz2pos(position({pos={x=1,y=2,z=3}})))"), 1)
        self.assertEqual(lua.eval("select('#',finalize(function()end,function()return 1,nil,3 end))"), 3)
        lua.execute("cleaned=false;pcall(finalize,function()cleaned=true end,function()error('injected')end)")
        self.assertTrue(lua.globals().cleaned)

    def test_wait_preconditions_and_restore(self):
        lua = catalog_runtime()
        lua.execute(r"""
        package.preload.json=function()return {decode=function()return request end,
          encode=function(v)response=v;return '' end}end
        io.open=function()return {read=function()return '' end,write=function()end,close=function()end}end
        print=function()end
        focus={'dwarfmode/Default'};top={};wall=1000
        df.d_init_autosave={NONE=0};df.viewscreen_dwarfmodest={is_instance=function(_,s)return s==top end}
        df.global.pause_state=true;df.global.cur_year=0;df.global.cur_year_tick=10
        df.global.d_init={feature={autosave=0},announcements={flags=vec{{whole=0}}}}
        df.global.world.status={popups=vec{}}
        dfhack.getTickCount=function()return wall end
        dfhack.gui={getCurViewscreen=function(skip)return top end,getFocusStrings=function(s)assert(s==top);return focus end}
        dfhack.constructions={findAtTile=function(p)return completed end}
        df3d_construction_acceptance={prefs={autosave=3,announcements={[0]=7}}}
        """)
        source = (Path(__file__).parent / 'smoke/construction-acceptance-verify.lua').read_text()
        def verify(op):
            lua.globals().request = lua.table_from(dict(op=op, origin=dict(x=0,y=0,z=0)), recursive=True)
            lua.execute(source, 'memory', '1')
            return lua.globals().response
        # Independently exercise the lane's citizen tuple conversion (review #1).
        lua.execute(r"""
        df.global.world.units={active=vec{{pos={x=0,y=0,z=0}}}}
        df.global.world.items={all=vec{}}
        dfhack.units={getPosition=position,isActive=function(u)return true end,
          isDead=function(u)return false end,isCitizen=function(u)return true end}
        dfhack.maps={getWalkableGroup=walkable_group}
        df3d_construction_acceptance.incomplete={};df3d_construction_acceptance.binned={}
        request={op='materials',definition='Chair',filter=0,origin={x=0,y=0,z=0},rows={}}
        """)
        lua.execute(source, 'memory', '1')
        self.assertEqual(lua.globals().response['status'], 'incomplete')
        self.assertEqual(lua.globals().response['reason'], 'binned items unavailable')
        lua.execute("df.global.world.status.popups=vec{{text='First popup'},{text='Second popup'}}")
        result = verify('wait_start')
        self.assertEqual(result['status'], 'incomplete')
        self.assertEqual(result['reason'], 'wait requires no announcement popups (count=2, first=First popup)')
        self.assertIsNone(lua.globals().df3d_construction_acceptance.wait)
        lua.execute("df.global.world.status.popups=vec{};focus={'dwarfmode/Info'}")
        self.assertEqual(verify('wait_start')['reason'], 'wait requires default fortress screen; screen=dwarfmode/Info')
        lua.execute("focus={'dwarfmode/Default'}")
        self.assertTrue(verify('wait_start')['waiting'])
        lua.execute('df.global.pause_state=false;wall=1100;df.global.cur_year_tick=11')
        self.assertTrue(verify('wait_poll')['waiting'])
        lua.execute("df.global.pause_state=true;df.global.world.status.popups=vec{{text='New popup'}}")
        self.assertEqual(verify('wait_poll')['reason'], 'game paused mid-wait; screen=dwarfmode/Default; popup count=1')
        lua.execute('df.global.pause_state=false')
        with self.assertRaisesRegex(Exception, 'DF must be paused before restoring fixture preferences'):
            lua.execute(source, 'memory', 'restore_prefs')
        self.assertEqual(lua.eval('df.global.d_init.feature.autosave'), 0)
        self.assertEqual(lua.eval('df.global.d_init.announcements.flags[0].whole'), 0)
        lua.execute(source, 'memory', 'pause')
        lua.execute(source, 'memory', 'final')
        lua.execute(source, 'memory', 'restore_prefs')
        self.assertEqual(lua.eval('df.global.d_init.feature.autosave'), 3)
        self.assertEqual(lua.eval('df.global.d_init.announcements.flags[0].whole'), 7)


class TrackSiteReader(unittest.TestCase):
    def setUp(self):
        self.lua=catalog_runtime()
        self.lua.execute('''
        df.tiletype_shape={[0]='FLOOR'}
        df.tiletype_material={CONSTRUCTION=1}
        df.tiletype={[43]='StoneFloorSmooth',OpenSpace=32,Chasm=19,EeriePit=21,
          attrs={[43]={shape=0,material=0}}}
        df.construction_type={[21]='TrackNSEW'}
        df.building_type={[0]='Construction',[1]='Hatch'}
        block={tiletype={[0]={[0]=43}},designation={[0]={[0]={hidden=false,flow_size=0,liquid_type=false}}},
          occupancy={[0]={[0]={building=1}}},walkable={[0]={[0]=1}}}
        building={id=20,stage=0,kind=0,removing=false,
          getType=function(s)return s.kind end,getSubtype=function()return 21 end,
          getBuildStage=function(s)return s.stage end,getMaxBuildStage=function()return 1 end,
          isSettingOccupancy=function()return true end}
        dfhack.maps={getTileBlock=function(p)assert(p.extra==nil);return block end}
        dfhack.buildings.findAtTile=function()return building end
        dfhack.buildings.markedForRemoval=function(b)return b.removing end
        ''')
        path=Path(__file__).resolve().parents[1]/'bridge/plugin/construction_track.lua'
        self.reader=self.lua.execute(path.read_text(), self.lua.eval("function()return true, '', true end"))
        self.pos=self.lua.table_from({'x':0,'y':0,'z':0,'extra':'caller metadata'})

    def test_pending_identity_requires_current_stage_and_no_removal(self):
        result=self.reader(self.pos)
        self.assertEqual((result['occupancy'],result['pending']['id'],result['pending']['connections']),('PendingConstruction',20,15))
        self.lua.execute('building.removing=true')
        result=self.reader(self.pos)
        self.assertEqual(result['occupancy'],'Unknown')
        self.assertIsNone(result['pending'])
        self.lua.execute('building.removing=false;building.stage=1')
        self.assertEqual(self.reader(self.pos)['occupancy'],'Unknown')

    def test_absent_or_unresolved_facts_do_not_invent_clearance(self):
        self.lua.execute('block.occupancy[0][0].building=7;building=nil')
        result=self.reader(self.pos)
        self.assertEqual(result['occupancy'],'Unknown')
        self.assertIsNone(result['clearance_blocked'])
        self.lua.execute('block=nil')
        self.assertFalse(self.reader(self.pos)['loaded'])

    def test_ramp_replacement_preserves_job_and_terrain_from_native_capture(self):
        root=Path(__file__).resolve().parents[1]
        fixture=json.loads((root/'fixtures/construction/connected_track.json').read_text())
        expected=fixture['semantic_reader']['ramp_replacement']['replacement']['facts']
        self.lua.execute('''
        df.tiletype_shape[1]='RAMP'
        df.tiletype[689]='ConstructedRampTrackEW'
        df.tiletype.attrs[689]={shape=1,material=1}
        block.tiletype[0][0]=689
        building.id=1496;df.construction_type[21]='TrackRampNSEW'
        ''')
        actual=self.reader(self.pos)
        self.assertEqual(actual['occupancy'],'PendingConstruction')
        self.assertEqual(expected['occupancy'],'PendingTrack')  # retained capture used the older internal name
        self.assertTrue(actual['pending']['track']);self.assertEqual(actual['pending']['subtype'],21)
        for field in ('pending','terrain'):
            self.assertEqual({k:actual[field][k] for k in expected[field]},expected[field])

    def test_hatch_clearance_tracks_live_flags_and_completion(self):
        self.lua.execute('block.occupancy[0][0].building=7;building.kind=1;building.stage=1;building.door_flags={forbidden=true,closed=true}')
        self.assertTrue(self.reader(self.pos)['clearance_blocked'])
        self.lua.execute('building.door_flags.closed=false')
        self.assertFalse(self.reader(self.pos)['clearance_blocked'])


if __name__ == '__main__':
    result = unittest.main(exit=False)
    if result.result.wasSuccessful(): print("CONSTRUCTION_ADAPTER_PASS")
    raise SystemExit(not result.result.wasSuccessful())
