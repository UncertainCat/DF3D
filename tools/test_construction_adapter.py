"""Deterministic construction contract tests; inline synthetic DF objects only."""
from pathlib import Path
import unittest
from test_construction_catalog import catalog_runtime

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
        df.tile_liquid={Magma=1};df.building_bridgest={T_direction={Up=0,Down=1,Left=2,Right=3}}
        df.block_square_event_type={material_spatter=0};df.builtin_mats={MUD=0};df.matter_state={Solid=0}
        shape=0;adjacent_shape=0;flags={flow_size=0};occupied={};valid=true;free=true
        dfhack.maps={isValidTilePos=function()return valid end,
          getTileFlags=function(p)return flags,{building=occupied[p.x..':'..p.y..':'..p.z] and 1 or 0}end,
          getTileType=function(p)return (p.x<0 or p.y<0) and adjacent_shape or shape end,
          getWalkableGroup=walkable_group,
          getTileBlock=function()return {block_events={}}end}
        df.construction={find=function()return existing end}
        dfhack.with_finalize=finalize
        df.delete=function()end
        dfhack.buildings.allocInstance=function()return {room={}}end
        dfhack.buildings.setSize=function(b,w,h,d)if not free then return false end;return true,w,h,w*h,w*h end
        dfhack.buildings.checkFreeTiles=function()return free end
        created={};dfhack.buildings.constructBuilding=function(v)
          created[#created+1]=v;for _,item in ipairs(v.items)do item.flags.in_job=true end
          return {id=100+#created} end
        dfhack.items={getContainer=function(i)return i.container end,getPosition=position,
          getGeneralRef=function()end}
        dfhack.units={isDead=function()return false end,isActive=function()return true end,
          isCitizen=function()return true end,getPosition=position}
        dfhack.job={isSuitableItem=function()return true end,isSuitableMaterial=function()return true end}
        dfhack.matinfo={decode=function(i)if i.nameless then return end
          return {toString=function()return i.name or 'stone'end}end}
        df.global.world.units={active=vec{{pos={x=0,y=0,z=0}}}}
        stock={};df.item={find=function(id)return stock[id]end}
        function fill(n,groups)
          stock={};local all={};for i=1,n do
            local item={id=i,flags={on_ground=true},pos={x=i%8,y=0,z=0},mat=groups and i-1 or 0,
              isAssignedToStockpile=function()return false end,getType=function()return 0 end,
              getSubtype=function()return -1 end,getMaterial=function()return 0 end,
              getMaterialIndex=function(s)return s.mat end,isBuildMat=function()return true end}
            stock[i]=item;all[i]=item end
          df.global.world.items={other={[0]=vec(all)}}
        end
        fill(1024)
        ''')
        self.seq=0
        self.reset()

    def reset(self): self.helper=self.lua.execute(SOURCE)

    def call(self, **kw):
        args=dict(action=63,epoch=7,definition='Chair',filter=0,cursor=0,x=0,y=0,z=0,seq=self.seq)
        args.update(kw)
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

    def test_site_rules(self):
        groups=[(['Chair','AnimalTrap','Chain','Cage','ArcheryTarget','TractionBench','Slab','NestBox',
                  'Hive','Instrument','Bookcase','DisplayFurniture','OfferingPlace','WindowGem','Kennels',
                  'Furnace:WoodFurnace','Trap:Lever','RoadPaved','Workshop:Carpenters',
                  'SiegeEngine:Ballista','SiegeEngine:Catapult','Trap:CageTrap','Trap:StoneFallTrap',
                  'Trap:WeaponTrap','Weapon','TradeDepot','GrateWall','BarsVertical','Floodgate'], 'FLOOR','EMPTY','Site needs a floor'),
                (['Hatch','GrateFloor','BarsFloor'],'EMPTY','WALL','Site needs a floor, open space, a ramp top or stairs'),
                (['Support'],'EMPTY','WALL','Site needs open space'),
                (['ScrewPump','WaterWheel','GearAssembly','AxleHorizontal','AxleVertical','Rollers','Bridge'],
                 'FLOOR','WALL','Site needs open space, a ramp or stairs')]
        for names,good,bad,message in groups:
            for name in names:
                with self.subTest(name=name):
                    self.lua.execute('shape=df.tiletype_shape[...]',good)
                    size=3 if name.startswith(('Workshop:','SiegeEngine:')) else 1
                    self.assertTrue(self.finish(action=1,definition=name,width=size,height=size)['ok'])
                    self.lua.execute('shape=df.tiletype_shape[...]',bad)
                    self.refusal(message,action=1,definition=name,width=size,height=size)
        self.lua.execute('shape=0;flags.outside=false')
        self.assertTrue(self.finish(action=1,definition='Bed')['ok'])
        self.lua.execute('flags.outside=true')
        self.refusal('Bed requires an indoor site',action=1,definition='Bed')
        self.lua.execute('flags.outside=false;adjacent_shape=df.tiletype_shape.WALL')
        self.assertTrue(self.finish(action=1,definition='Door')['ok'])
        self.lua.execute('adjacent_shape=0')
        self.refusal('Door requires an adjacent wall',action=1,definition='Door')
        self.lua.execute('shape=df.tiletype_shape.EMPTY')
        self.assertTrue(self.finish(action=1,definition='Well')['ok'])
        self.lua.execute('adjacent_shape=df.tiletype_shape.WALL')
        self.refusal('Well needs open space with an adjacent floor',action=1,definition='Well')
        for name in ('FarmPlot','RoadDirt'):
            self.lua.execute('shape=0;df.tiletype.attrs[0].material=df.tiletype_material.SOIL')
            self.assertTrue(self.finish(action=1,definition=name)['ok'])
            self.lua.execute('df.tiletype.attrs[0].material=0')
            self.refusal('Site needs soil',action=1,definition=name)
        for setup,message in [('valid=false','Site is hidden, unloaded or outside the map'),
            ('flags.hidden=true','Site is hidden, unloaded or outside the map'),
            ("occupied['0:0:0']=true",'Building present'),
            ('flags.flow_size=2','Site has magma or deep water'),
            ('flags.flow_size=1;flags.liquid_type=1','Site has magma or deep water'),
            ('free=false','Native placement check rejected this site')]:
            self.lua.execute('valid=true;flags={flow_size=0};occupied={};free=true;'+setup)
            self.refusal(message,action=1)

    def test_site_rule_edges_and_direction_limits(self):
        for family in ('FarmPlot','RoadDirt'):
            for material in ('SOIL','GRASS_LIGHT','GRASS_DARK','GRASS_DRY','GRASS_DEAD','PLANT'):
                for shape in ('FLOOR','TWIG','SAPLING','SHRUB','BOULDER','PEBBLES'):
                    self.lua.execute('shape=df.tiletype_shape[...];df.tiletype.attrs[shape].material=df.tiletype_material[select(2,...)]',shape,material)
                    if shape in ('BOULDER','PEBBLES'):
                        self.refusal('Site needs soil',action=1,definition=family)
                    else:self.assertTrue(self.finish(action=1,definition=family)['ok'])
        for direction in range(4):
            self.lua.execute('shape=df.tiletype_shape.RAMP')
            self.refusal('Site needs open space, a ramp or stairs',action=1,definition='Bridge',direction=direction)
            self.assertTrue(self.finish(action=1,definition='Bridge',direction=direction,retracting=True)['ok'])
            self.lua.execute('shape=df.tiletype_shape.EMPTY')
            self.assertTrue(self.finish(action=1,definition='Bridge',direction=direction)['ok'])
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

    def test_piece_rule_exact_messages_and_requirement_tokens(self):
        # As in the work-order exemplar's receipt test, expose a private pure
        # rule in this isolated closure to assert reasons that Preview reduces
        # to mask bytes. No product source or runtime exports are changed.
        self.lua.execute(SOURCE.replace('local function native_site(', 'test_tile_rule=tile_rule\nlocal function native_site('))
        rule=self.lua.globals().test_tile_rule
        request=self.lua.table_from(dict(x=0,y=0,z=0,width=1,height=1,depth=1,direction=0))
        definition=self.lua.table_from(dict(family='Construction',subtype_key='Wall'))
        pos=self.lua.table_from(dict(x=0,y=0,z=0))
        self.assertTrue(rule(request,definition,pos))
        self.lua.execute('shape=df.tiletype_shape.WALL')
        self.assertEqual(rule(request,definition,pos),(False,'Site needs open space or a ramp'))
        self.lua.execute('df.tiletype.attrs[shape].material=df.tiletype_material.CONSTRUCTION')
        self.assertEqual(rule(request,definition,pos),(False,'Construction already present'))
        definition['subtype_key']='Stairs'
        self.lua.execute('df.tiletype.attrs[shape].material=0')
        self.assertEqual(rule(request,definition,pos,1),(False,'Site needs open space or a ramp'))
        self.lua.execute('shape=0;free=false')
        self.assertEqual(rule(request,definition,pos),(False,'Native placement check rejected this site'))
        self.lua.execute('free=true')
        for raw,expected in [("{quantity=1,has_tool_use=1}",'SCREW'),
                             ("{quantity=1,flags2={whole=0,building_material=true}}",'building_material')]:
            self.lua.execute('recipes[df.building_type.Chair]={'+raw+'}')
            self.reset()
            self.assertEqual(self.finish(action=1)['filters'][1]['requirement'],expected)
        # Mud-on-stone is a separate FarmPlot acceptance path.
        self.lua.execute("""dfhack.maps.getTileBlock=function()return {block_events={{
          getType=function()return 0 end,mat_type=0,mat_state=0}}}end""")
        self.assertTrue(self.finish(action=1,definition='FarmPlot')['ok'])
        self.refusal('Site needs soil',action=1,definition='RoadDirt')

    def test_preview_and_custom_resolution(self):
        self.refusal('Depth applies to stairs only',action=1,depth=2)
        self.refusal("Size exceeds this building's limits",action=1,width=32)
        self.refusal('This building has a fixed size',action=1,definition='Workshop:Carpenters')
        self.refusal('Orientation not available for this building',action=1,direction=1)
        self.refusal('Must span multiple elevations',action=1,definition='Construction:Stairs')
        self.lua.execute('recipes[df.building_type.Bridge]={{quantity=-1,vector_id=1}}')
        self.reset()
        preview=self.finish(action=1,definition='Bridge',width=4,height=3)
        self.assertEqual(preview['required'],4)
        self.assertEqual(preview['filters'][1]['requirement'],'BLOCKS')
        self.assertEqual(list(preview['valid_mask'].values()),[1]*12)
        self.assertEqual((preview['footprint']['width'],preview['footprint']['height']),(4,3))
        for name,w,h,d in [('Chair',1,1,1),('Bridge',2,2,1),('Construction:Wall',2,2,1),('Construction:Stairs',2,2,3)]:
            p=self.finish(action=1,definition=name,width=w,height=h,depth=d)
            self.assertEqual(list(p['valid_mask'].values()),[1]*(w*h*d))
            if d==3:self.assertEqual(list(p['pieces'].values()),[1]*4+[3]*4+[2]*4)
        for key,index,size in [('Workshop:Custom:PRESS',1,3),('Furnace:Custom:KILN',2,1)]:
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
        key='Workshop:Custom:PRESS'
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
        row=self.selection(1024,definition='Construction:Stairs')
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
        dirty=self.call()
        self.assertEqual(dirty['build_phase'],1)
        self.assertEqual(dirty['list_revision'],row['expected_list_revision'])
        self.assertEqual(dirty['cache_entries'],2)  # retained snapshot plus replacement

    def test_short_group_release_and_retired_items(self):
        row=self.selection(2,definition='Construction:Wall')
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
                self.lua.execute('fill(1024);created={};occupied={}')
                self.reset();row=self.selection(600,definition='Construction:Wall')
                self.seq+=1
                args=dict(action=2,definition='Construction:Wall',width=30,height=20,selections=[row],step_budget=1200)
                result=self.call(**args)
                while result['placed']<256: result=self.call(**args)
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
                    self.assertEqual((result['placed'],result['skipped']),(599,1))
                    self.assertEqual(self.lua.globals().created[257]['items'][1]['id'],257)
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
        expected=130+129*8+len('7|'+signature)+129*2
        self.assertEqual(sum(counts.values()),expected)  # reads, merge moves, signature bytes, rows and ids
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
        for n in (65536,65537):
            self.lua.execute('fill(...)',n);self.reset()
            if n==65536:
                result=self.page();self.assertTrue(result['ok'],result['message'])
                self.assertEqual(result['materials'][1]['count'],65536)
                for x in range(1,4):self.page(x=x)
                stats=self.call(x=3)
                self.assertEqual((stats['cache_entries'],stats['cache_ids']),(4,4*65536))
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

    def test_material_rows(self):
        self.lua.execute('''fill(6);stock[1].mat=2;stock[1].pos.x=7;stock[2].mat=1;stock[2].pos.x=1
          stock[3].mat=1;stock[3].flags.on_ground=false;stock[3].container={flags={on_ground=true},getType=function()return 97 end}
          stock[4].nameless=true;stock[5].flags.forbid=true;stock[6].pos.z=1;walk_groups[stock[6].pos.x..':0:1']=2
          stock[1].name=string.rep('n',129)''')
        self.reset();p=self.page()
        self.assertEqual([(r['mat_index'],r['count']) for r in p['materials'].values()],[(1,2),(2,1)])
        self.assertTrue(p['estimated']);self.assertEqual(p['message'],'DF3D estimate: 3 accessible')
        self.assertEqual(len(p['materials'][2]['name'].encode()),128)
        self.lua.execute('stock[3].container.flags.in_job=true;df.global.cur_year_tick=1201')
        self.assertEqual(self.page()['materials'][1]['count'],1)
        self.assertGreater(p['list_revision'],0);self.assertLessEqual(p['list_revision'],2**63-1)

    def test_stairs_rebuild_and_orientation_arguments(self):
        for existing in ('STAIR_UP','STAIR_DOWN','STAIR_UPDOWN'):
            self.lua.execute('shape=df.tiletype_shape[...]',existing)
            self.refusal('Must span multiple elevations',action=1,definition='Construction:Stairs',depth=1)
            p=self.finish(action=1,definition='Construction:Stairs',depth=3)
            self.assertEqual(list(p['pieces'].values()),[1,3,2])
            self.assertEqual(list(p['valid_mask'].values()),[1,1,1])
        self.lua.execute('shape=0;df.tiletype.attrs[0].material=df.tiletype_material.CONSTRUCTION;existing={}')
        p=self.finish(action=1,definition='Construction:Wall')
        self.assertEqual(list(p['valid_mask'].values()),[1])
        p=self.finish(action=1,definition='Construction:Wall',width=2)
        self.assertEqual(list(p['valid_mask'].values()),[0,0])
        p=self.finish(action=1,definition='Construction:Floor')
        self.assertEqual(list(p['valid_mask'].values()),[0])
        self.lua.execute('df.tiletype.attrs[0].material=0;existing=nil')
        for name,directions in [('ScrewPump',range(4)),('Rollers',range(4)),
                                ('WaterWheel',range(2)),('AxleHorizontal',range(2)),('Bridge',range(5))]:
            for direction in directions:
                row=self.selection(definition=name)
                r=self.finish(action=2,definition=name,direction=direction if direction<4 else 0,
                              retracting=direction==4,selections=[row])
                self.assertTrue(r['ok'],r['message'])
                build=self.lua.globals().created[len(self.lua.globals().created)]
                self.assertEqual(build['direction'],direction if direction<4 else -1)
                self.assertEqual(build['type'],self.lua.globals().df.building_type[name])
        # DFHack applies these direction parameters to native fields; that write
        # belongs to the MSVC/live check, not this synthetic constructBuilding.

    def test_screen_flags_containers_and_clipping_boundaries(self):
        flags=['dump','forbid','garbage_collect','hostile','on_fire','rotten','trader',
               'in_building','construction','in_job','owned','removed','encased','spider_web']
        for flag in flags:
            with self.subTest(flag=flag):
                self.lua.execute('fill(1);stock[1].flags[...]=true',flag);self.reset()
                self.assertEqual(len(self.page()['materials']),0)
                self.lua.execute('stock[1].flags[...]=false',flag);self.reset()
                self.assertEqual(self.page()['materials'][1]['count'],1)
        for size in (128,129):
            self.lua.execute("fill(1);stock[1].name=string.rep('n',...)",size);self.reset()
            self.assertEqual(len(self.page()['materials'][1]['name']),128)
        for depth in (16,17):
            self.lua.execute("""fill(1);local item=stock[1];item.flags.on_ground=false
              for i=1,... do item.container={flags={on_ground=true},getType=function()return 97 end};item=item.container end""",depth)
            self.reset();p=self.page()
            self.assertEqual(len(p['materials']),1 if depth==16 else 0)
        self.lua.execute("fill(1);stock[1].name=''");self.reset()
        self.assertEqual(len(self.page()['materials']),0)

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


if __name__ == '__main__':
    result = unittest.main(exit=False)
    if result.result.wasSuccessful(): print("CONSTRUCTION_ADAPTER_PASS")
    raise SystemExit(not result.result.wasSuccessful())
