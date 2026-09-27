"""Asset-free adapter regression: DF enums are metatable-backed, not iterable maps.

Run with Python + lupa (test tooling only; no DF or presentation dependencies).
"""
from pathlib import Path

from lupa import LuaRuntime


# Pinned API audit: external/dfhack/docs/dev/Lua API.rst (line numbers below).
# Position tuples: 1736,2179 / LuaApi.cpp:2264-2265,2583-2584.
# Walkability takes coord, not XYZ: 2448 / LuaApi.cpp:2656.
# Map coordinate overloads: 2390-2415; getTileFlags returns designation,occupancy.
# Building sizes return five values: 2613,2665 / LuaApi.cpp:2976-3017.
# Recipes/construct: 2720-2808; getFiltersByType(argtable,type,subtype,custom).
# Item container/ref and suitability: 2156,2139,1430-1437; pointer/nil and bool.
# matinfo.decode/toString: 811,827; df2utf:973 string -> string.
# allocInstance/checkFreeTiles/deconstruct/markedForRemoval:2660,2619,2700,2710;
# (coord,type,subtype,custom)->building/nil, (coord,size,...)->bool, (building)->bool.
# unit predicates:1497-1540 (unit[,include_insane])->bool; item subtype count:2129.
# xyz2pos mirrors library/lua/dfhack.lua:448-454, including invalid-position sentinel.
# with_finalize: 710-713 preserves all returns and cleans up on errors too.
API_MOCKS = r"""
function xyz2pos(x,y,z)
 if x then return {x=x,y=y,z=z} end
 return {x=-30000,y=-30000,z=-30000}
end
function position(object)
 assert(type(object)=='table')
 local p=object.pos
 if not p or p.x==-30000 then return nil end
 return p.x,p.y,p.z
end
walk_groups={}
function walkable_group(p)
 assert(type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number', 'expected coord table')
 if p.x==-30000 or p.y==-30000 or p.z==-30000 then return 0 end
 return walk_groups[p.x..':'..p.y..':'..p.z] or 1
end
function finalize(clean,fn,...)
 local result=table.pack(pcall(fn,...));clean()
 if not result[1] then error(result[2],0) end
 return table.unpack(result,2,result.n)
end
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(API_MOCKS)
    lua.execute(
        """
        local function enum(names)
            local lookup = {}
            for i, name in ipairs(names) do
                lookup[i-1] = name
                lookup[name] = i-1
            end
            return setmetatable({_last_item=#names-1}, {__index=lookup})
        end
        df = {
            building_type=enum{'Chair','Workshop','Construction','Trap','SiegeEngine','Weapon','Bridge'},
            siegeengine_type=enum{'Ballista','Catapult'},
            tool_uses={NONE=-1},
            workshop_type=enum{'Carpenters'},
            construction_type=enum{'Wall','Floor','UpStair','DownStair','UpDownStair'},
            trap_type=enum{'Lever','WeaponTrap'},
        }
        df.job_item = {
            new=function()
                return {
                    quantity=1,
                    assign=function(self, values)
                        for key, value in pairs(values) do self[key]=value end
                    end,
                    delete=function() end,
                }
            end,
        }
        dfhack = {buildings={}}
        dfhack.buildings.getCorrectSize=function(w,h,t)
            return false, t==df.building_type.Workshop and 3 or 1,
                          t==df.building_type.Workshop and 3 or 1,
                          t==df.building_type.Workshop and 1 or 0,
                          t==df.building_type.Workshop and 1 or 0
        end
        dfhack.buildings.getFiltersByType=function(_,t,st)
            -- Missing quantity must preserve job_item's native default of one.
            -- Explicit quantities are retained by the multi-input catalog.
            if t==df.building_type.Construction and st==df.construction_type.Floor then
                return {{quantity=2}}
            end
            return {{new=true}}
        end
        """
    )
    source = Path(__file__).resolve().parents[1] / "bridge/plugin/construction.lua"
    adapter = lua.execute(source.read_text(encoding="utf-8"))
    result = adapter(lua.table_from({"action": 0}))
    assert result["ok"], result["message"]
    catalog = {entry["key"]: entry for entry in result["catalog"].values()}
    assert set(catalog) == {"Chair", "Workshop:Carpenters", "Construction:Wall", "Construction:Floor",
                            "Trap:Lever", "Trap:WeaponTrap", "Construction:Stairs", "Construction:Track",
                            "Construction:UpStair", "Construction:DownStair", "Construction:UpDownStair",
                            "SiegeEngine:Ballista", "SiegeEngine:Catapult", "Weapon", "Bridge"}
    for key in ("Chair", "Workshop:Carpenters", "Construction:Wall"):
        assert catalog[key]["supported"], key
    assert catalog["Workshop:Carpenters"]["width"] == 3
    assert catalog["Construction:Floor"]["supported"]
    # Item 10: real builder revisions feed a multi-filter Place, without native DF.
    lua.execute("""
        df.job_item.new=function()
            return {quantity=1,item_type=-1,item_subtype=-1,has_tool_use=-1,metal_ore=-1,
                vector_id=0,flags1={whole=0},flags2={whole=0},flags3={whole=0},
                assign=function(self,v) for k,x in pairs(v) do self[k]=x end end,
                delete=function() end}
        end
        df.job_item_vector_id={IN_PLAY=0,attrs={[0]={other=0}}}
        df.tool_uses={NONE=-1};df.item_type={TOOL=99,BAR=98};df.general_ref_type={CONTAINS_ITEM=0}
        df.tiletype_shape={[0]='FLOOR'};df.tiletype={attrs={[0]={shape=0}}}
        dfhack.maps={isValidTilePos=function() return true end,
            getTileFlags=function() return {flow_size=0},{building=0} end,
            getTileType=function() return 0 end,getWalkableGroup=walkable_group}
        local function vector(v) v[0]=table.remove(v,1);return setmetatable(v,{__len=function() return 1 end}) end
        stock={}
        for i=1,3 do
            stock[i]={id=i,pos={x=0,y=0,z=0},flags={on_ground=true},isAssignedToStockpile=function() return false end,
                getType=function() return i==3 and 1 or 0 end,getSubtype=function() return -1 end,
                getMaterial=function() return 0 end,getMaterialIndex=function() return i==2 and 1 or 0 end}
        end
        local all={[0]=stock[1],stock[2],stock[3]}
        setmetatable(all,{__len=function() return 3 end})
        df.global={cur_year=1,cur_year_tick=0,world={raws={buildings={all={}}},items={other={[0]=all}},units={active=vector{{pos={x=0,y=0,z=0}}}}}}
        df.item={find=function(id) reads=reads+1;return stock[id] end}
        dfhack.items={getContainer=function() end,getPosition=position,
            getGeneralRef=function() end}
        dfhack.units={isDead=function() return false end,isActive=function() return true end,
            isCitizen=function() return true end,getPosition=position}
        dfhack.job={isSuitableItem=function() return true end,isSuitableMaterial=function() return true end}
        dfhack.matinfo={decode=function() return {toString=function() return 'stone' end} end}
        dfhack.df2utf=function(v) return v end
        dfhack.with_finalize=finalize
        df.delete=function() end
        dfhack.buildings.allocInstance=function() return {room={}} end
        dfhack.buildings.setSize=function(b,w,h,d) return true,w,h,w*h,w*h end
        dfhack.buildings.getFiltersByType=function() return {{item_type=0,quantity=2},{item_type=1,quantity=1}} end
        dfhack.buildings.constructBuilding=function(v) created=created+1;assert(#v.items==3);return {id=created} end
        created=0;reads=0
    """)
    place_adapter = lua.execute(source.read_text(encoding="utf-8"))
    def call(**fields):
        base = dict(action=63, definition="Chair", epoch=7, filter=0, cursor=0, x=0, y=0, z=0)
        base.update(fields)
        return place_adapter(lua.table_from(base, recursive=True))
    revisions = []
    for f in range(2):
        call(filter=f)
        call(step=2048)
        page = call(filter=f)
        assert page['ok'] and page['build_phase'] == 0, page['message']
        revisions.append(page['list_revision'])
    assert revisions[0] != revisions[1]
    selections = [dict(filter=f, item_type=f, item_subtype=-1, mat_type=0,
                       mat_index=m, count=1, expected_list_revision=revisions[f])
                  for f, m in ((0, 0), (0, 1), (1, 0))]
    seq = 0
    def place(rows, budget=1536):
        nonlocal seq
        seq += 1
        args = dict(action=2, seq=seq, selections=rows, x=0, y=0, z=0,
                    width=1, height=1, depth=1, direction=0, step_budget=budget,
                    expected_revision=987, expected_list_revision=123)
        result = call(**args)
        while result['pending']:
            result = call(**args)
        return result
    # Every entry is checked, including a second group in the same filter.
    for index in (2, 1):
        for stale in (-1, 0, revisions[selections[index]['filter']] + 1, None):
            rows = [dict(v) for v in selections]
            if stale is None:
                del rows[index]['expected_list_revision']
            else:
                rows[index]['expected_list_revision'] = stale
            result = place(rows)
            assert not result['ok'] and result['message'] == 'List changed; refresh'
            assert result['filter'] == rows[index]['filter']
            assert lua.globals().reads == 0 and lua.globals().created == 0
            # A refused preflight must not dirty any cache (which would queue a rebuild).
            assert call(filter=0)['build_phase'] == 0
            assert call(filter=1)['build_phase'] == 0
    # A late short group releases earlier reservations; unchanged revisions can retry.
    lua.execute('stock[3].flags.forbid=true')
    result = place(selections)
    assert not result['ok'] and result['message'] == 'Selected material no longer available; refresh materials'
    assert lua.globals().created == 0
    lua.execute('stock[3].flags.forbid=false')
    result = place(selections, budget=6)
    assert result['ok'] and result['message'] == 'Native construction job queued'
    assert result['placed'] == 1 and lua.globals().created == 1
    # Native e4 behavior and review-B-1 regressions. Broad site/cap coverage is commit C.
    lua.execute("""
        df.building_bridgest={T_direction={Up=0,Down=1,Left=2,Right=3}}
        df.tiletype_material={CONSTRUCTION=99};df.tile_liquid={Magma=1}
        df.construction={find=function() end}
        dfhack.buildings.checkFreeTiles=function() return true end
        dfhack.buildings.getCorrectSize=function(w,h,t)
            if t==df.building_type.Bridge then return false,w,h,0,0 end
            return false,1,1,0,0
        end
        dfhack.buildings.getFiltersByType=function(_,t,st)
            if t==df.building_type.Trap and st==df.trap_type.WeaponTrap then
                return {{item_type=1,quantity=1},{item_type=0,quantity=1}}
            end
            return {{item_type=0,quantity=-1}}
        end
        stock={};local all={}
        for i=1,14 do
            local ty=i==14 and 1 or 0
            stock[i]={id=i,flags={on_ground=true},pos={x=i,y=0,z=0},
                isAssignedToStockpile=function() return false end,
                getType=function() return ty end,getSubtype=function() return -1 end,
                getMaterial=function() return 0 end,getMaterialIndex=function() return 0 end}
            all[i-1]=stock[i]
        end
        setmetatable(all,{__len=function() return 14 end})
        df.global.world.items.other[0]=all
        dfhack.items.getPosition=position
        dfhack.items.getContainer=function(item) return item.container end
        dfhack.maps.getWalkableGroup=walkable_group
        dfhack.buildings.constructBuilding=function(v)
            created=created+1;last_build=v;return {id=created}
        end
        created=0
    """)
    place_adapter = lua.execute(source.read_text(encoding="utf-8"))
    def finish(**args):
        nonlocal seq
        seq += 1
        args['seq'] = seq
        result = call(**args)
        while result['pending']:
            result = call(**args)
        return result
    def page(**args):
        result = call(**args)
        for _ in range(100):
            if not result['ok'] or result['build_phase'] == 0:
                return result
            call(step=2048)
            result = call(**args)
        raise AssertionError('builder failed to finish')
    def selection(rev, count=1, f=0, ty=0, mat=0):
        return dict(filter=f, item_type=ty, item_subtype=-1, mat_type=0,
                    mat_index=mat, count=count, expected_list_revision=rev)
    # One-level stairs refuse even on existing stairs; endpoints are up/down.
    result = finish(action=1, definition='Construction:Stairs', depth=1)
    assert not result['ok'] and result['message'] == 'Must span multiple elevations'
    for depth, expected in ((2, [1, 2]), (3, [1, 3, 2])):
        result = finish(action=1, definition='Construction:Stairs', depth=depth)
        assert result['ok'] and list(result['pieces'].values()) == expected
        assert result['required'] == depth
    rev = page()['list_revision']
    result = finish(action=2, definition='Construction:Stairs', depth=2,
                    selections=[selection(rev, 2)])
    assert result['ok'] and result['message'] == 'Painted 2 of 2'
    assert lua.globals().last_build['subtype'] == lua.globals().df.construction_type.DownStair
    # Eight siege footprints/facings reach constructBuilding unchanged.
    cat = {r['key']: r for r in call(action=0)['catalog'].values()}
    assert cat['SiegeEngine:Ballista']['orientations'] == 255
    assert len(cat['SiegeEngine:Ballista']['footprints']) == 8
    for direction in range(8):
        rev = page()['list_revision']
        result = finish(action=2, definition='SiegeEngine:Ballista', direction=direction,
                        selections=[selection(rev)])
        assert result['ok'], result['message']
        assert lua.globals().last_build['fields']['facing'] == direction
        assert lua.globals().last_build['fields']['resting_orientation'] == direction
    result = finish(action=1, definition='SiegeEngine:Ballista', direction=8)
    assert not result['ok'] and result['message'] == 'Orientation not available for this building'
    result = finish(action=1, definition='Bridge', direction=4)
    assert not result['ok'] and result['message'] == 'Orientation not available for this building'
    result = finish(action=1, definition='SiegeEngine:Ballista', retracting=True)
    assert not result['ok'] and result['message'] == 'Orientation not available for this building'
    # Both count-selecting recipes default to one and accept 1..10 whole items.
    for definition, f in (('Weapon', 0), ('Trap:WeaponTrap', 1)):
        preview = finish(action=1, definition=definition)
        assert preview['filters'][f + 1]['quantity'] == 1
        for count in (-1, 0, 1, 10, 11):
            weapons = page(definition=definition, filter=f)['list_revision']
            rows = [selection(weapons, count, f)]
            if f:
                mech = page(definition=definition, filter=0)['list_revision']
                rows.insert(0, selection(mech, 1, 0, 1))
            result = finish(action=2, definition=definition, selections=rows)
            if count < 1:
                assert not result['ok'] and result['message'] == 'Selections do not cover the recipe'
            elif count == 11:
                assert not result['ok'] and result['message'] == 'Weapon count must be between 1 and 10'
            else:
                assert result['ok'], result['message']
                assert len(lua.globals().last_build['items']) == count + f
        rows = [selection(page(definition=definition, filter=f)['list_revision'], f=f)]
        del rows[0]['count']
        if f:
            rows.insert(0, selection(page(definition=definition, filter=0)['list_revision'], f=0, ty=1))
        assert finish(action=2, definition=definition, selections=rows)['ok']
    # Fail after reservation, so the initial site check succeeds.
    for definition in ('Chair', 'Bridge'):
        rev = page()['list_revision']
        args = dict(action=2, definition=definition, seq=seq + 1,
                    selections=[selection(rev)], step_budget=1)
        seq += 1
        result = call(**args)
        # First slice checks tile, second performs native footprint and prepares recipe,
        # third reserves the item. No creation fits in a one-step slice.
        for _ in range(2):
            result = call(**args)
        lua.execute('dfhack.maps.getTileFlags=function() return {flow_size=0},{building=1} end')
        args['step_budget'] = 1536
        result = call(**args)
        assert not result['ok'] and result['message'] == 'Native construction rejected'
        assert result['placed'] == 0 and result['skipped'] == 1
        lua.execute('dfhack.maps.getTileFlags=function() return {flow_size=0},{building=0} end')
        lua.execute('dfhack.buildings.constructBuilding=function(info) return nil,"cannot place at this position" end')
        rev = page()['list_revision']
        result = finish(action=2, definition=definition, selections=[selection(rev)])
        assert not result['ok'] and result['message'] == 'Native construction rejected'
        assert result['placed'] == 0 and result['skipped'] == 1
    # Per-tile -1 recipe uses area 1, then multiplies by valid tile count.
    lua.execute("""
        dfhack.maps.getTileFlags=function(p) return {flow_size=0},{building=p.x==1 and 1 or 0} end
        dfhack.buildings.constructBuilding=function(v) return {id=1} end
    """)
    rev = page()['list_revision']
    preview = finish(action=1, definition='Construction:Wall', width=4, height=2)
    assert preview['required'] == 6
    result = finish(action=2, definition='Construction:Wall', width=4, height=2,
                    selections=[selection(rev, 6)])
    assert result['ok'] and result['message'] == 'Painted 6 of 8'
    assert result['placed'] == 6 and result['skipped'] == 2
    lua.execute('dfhack.buildings.constructBuilding=function(info) return nil,"cannot place at this position" end')
    rev = page()['list_revision']
    result = finish(action=2, definition='Construction:Wall', selections=[selection(rev)])
    assert not result['ok'] and result['message'] == 'Native construction rejected'
    assert result['placed'] == 0 and result['skipped'] == 1
    # Nearest-member squared 3D distance; ties use numeric material identities.
    # A grounded bin supplies one eligible item; another item is unreachable.
    lua.execute("""
        dfhack.maps.getTileFlags=function() return {flow_size=0},{building=0} end
        for i=1,13 do stock[i].flags.forbid=true end
        for i=1,4 do stock[i].flags.forbid=false end
        stock[1].pos={x=9,y=0,z=0};stock[1].getMaterialIndex=function() return 10 end
        stock[2].pos={x=1,y=0,z=0};stock[2].getMaterialIndex=function() return 2 end
        stock[3].pos={x=0,y=1,z=0};stock[3].getMaterialIndex=function() return 1 end
        stock[3].flags.on_ground=false
        stock[3].container={flags={on_ground=true},getType=function() return 97 end}
        stock[4].pos={x=0,y=0,z=1};walk_groups['0:0:1']=2;stock[4].getMaterialIndex=function() return 99 end
        df.global.cur_year_tick=2000
    """)
    material_page = page()
    assert [r['mat_index'] for r in material_page['materials'].values()] == [1, 2, 10]
    assert [r['count'] for r in material_page['materials'].values()] == [1, 1, 1]
    moved = page(x=10)
    assert [r['mat_index'] for r in moved['materials'].values()] == [10, 2, 1]
    assert moved['list_revision'] != material_page['list_revision']
    result = finish(action=2, x=10, selections=[selection(material_page['list_revision'], mat=1)])
    assert not result['ok'] and result['message'] == 'List changed; refresh'
    # A failed coroutine remains stopped until reported, then explicitly retried.
    call(cancel_builders=True)
    lua.execute('saved_decode=dfhack.matinfo.decode;dfhack.matinfo.decode=function() error("injected",0) end')
    call()
    call(step=2048)
    lua.execute('dfhack.matinfo.decode=saved_decode')
    assert not call(step=2048)['active']
    failed = call()
    assert not failed['ok'] and failed['build_phase'] == 3
    assert failed['message'] == 'Materials list unavailable: injected'
    assert not call(step=2048)['active']
    retry = call()
    assert retry['ok'] and retry['build_phase'] == 1
    assert page()['build_phase'] == 0
    # Distinct footprint failure, and UTF-8 custom names clipped at 128 bytes.
    lua.execute("""
        dfhack.buildings.getCorrectSize=function(w,h,t)
            return false,t==df.building_type.SiegeEngine and 0 or 1,1,0,0
        end
        df.building_def_furnacest={is_instance=function() return false end}
        df.global.plotinfo={civ_id=1}
        df.historical_entity={find=function() return {entity_raw={workshops={permitted_building_id={1}}}} end}
        df.global.world.raws.buildings.all={{id=1,code='LONG',name=string.rep('é',65)}}
    """)
    named_adapter = lua.execute(source.read_text(encoding='utf-8'))
    cat = {r['key']: r for r in named_adapter(lua.table_from(dict(action=0)))['catalog'].values()}
    assert cat['SiegeEngine:Ballista']['reason'] == 'Native placement check rejected this site'
    assert len(cat['Workshop:Custom:LONG']['native_name'].encode('utf-8')) == 128
    lua.execute("df.building_type._last_item = -1")
    broken = lua.execute(source.read_text(encoding="utf-8"))
    result = broken(lua.table_from({"action": 0}))
    assert not result["ok"] and result["message"] == "Native construction catalog is incomplete: Chair"
    print("CONSTRUCTION_CATALOG PASS")


# Fixture producibility | construction.lua function (committed B).
# Catalog labels/modes/limits/reasons/footprints | definitions:59-122.
# Missing self-check key | catalog initialization:116-119.
# Filter identities, quantities and requirement tokens | filter_row:41-51.
# Stale page message and integer revision | returned request closure:506-510.
# Inline tables are synthetic DF API inputs, never recorded raws or native text.
def catalog_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(API_MOCKS)
    lua.execute((Path(__file__).parent / 'qa/lua_test_prelude.lua').read_text())
    lua.execute(r"""
    df={building_type=enum{'Chair','Workshop','Furnace','Construction','Trap','SiegeEngine',
      'Nest','Wagon','Shop','Bed','Door','Hatch','GrateFloor','BarsFloor','Support','Well',
      'ScrewPump','WaterWheel','GearAssembly','AxleHorizontal','AxleVertical','Rollers','Bridge',
      'FarmPlot','RoadDirt','RoadPaved','Windmill','Stockpile','Civzone','Weapon',
      'AnimalTrap','Chain','Cage','ArcheryTarget','TractionBench','Slab','NestBox','Hive',
      'Instrument','Bookcase','DisplayFurniture','OfferingPlace','WindowGem','Kennels','TradeDepot','GrateWall','BarsVertical','Floodgate'},
      workshop_type=enum{'Carpenters','Tool','Custom'},furnace_type=enum{'WoodFurnace','MagmaSmelter','Custom'},
      trap_type=enum{'Lever','CageTrap','StoneFallTrap','WeaponTrap','PressurePlate','TrackStop'},
      siegeengine_type=enum{'Ballista','Catapult'},
      construction_type=enum{'Wall','Floor','Ramp','UpStair','DownStair','UpDownStair','Fortification'},
      tool_uses=enum{'NONE','SCREW'},job_item_vector_id=enum{'IN_PLAY','BLOCKS'}}
    df.tool_uses.NONE=-1
    for i=1,30 do local e=df.construction_type;e._last_item=e._last_item+1
      local name=i==30 and 'TrackNSEW' or 'Track'..i;e[e._last_item]=name;e[name]=e._last_item end
    customs={{id=11,code='PRESS',name='Press',class='workshop'},
      {id=12,code='KILN',name='Kiln',class='furnace'},
      {id=13,code='LOCKED',name='',class='workshop'},
      {id=14,code='HOT',name='',class='furnace',needs_magma=true}}
    permitted_ids={11,12,14}
    df.global={cur_year=1,cur_year_tick=0,plotinfo={civ_id=1},world={raws={buildings={all=customs}}}}
    df.building_def_furnacest={is_instance=function(_,v)return v.class=='furnace'end}
    df.building_def_workshopst={is_instance=function(_,v)return v.class=='workshop'end}
    df.building_def={find=function(id)for _,v in ipairs(customs)do if v.id==id then return v end end end}
    df.historical_entity={find=function()return {entity_raw={workshops={permitted_building_id=permitted_ids}}}end}
    df.job_item={new=function()return {quantity=1,item_type=-1,item_subtype=-1,
      mat_type=-1,mat_index=-1,vector_id=0,has_tool_use=-1,metal_ore=-1,
      flags1={whole=0},flags2={whole=0},flags3={whole=0},
      assign=function(self,v)for k,x in pairs(v)do self[k]=x end end,delete=function()end}end}
    dfhack={df2utf=function(s)return s end,buildings={}}
    dfhack.buildings.getCorrectSize=function(w,h,t,st,custom,dir)
      if t==df.building_type.Workshop or t==df.building_type.SiegeEngine then return false,3,3,1,1 end
      return false,w,h,0,0
    end
    recipes={}
    dfhack.buildings.getFiltersByType=function(_,t,st)
      if recipes[t] then return recipes[t] end
      if t==df.building_type.Workshop and st==df.workshop_type.Tool then return nil end
      if t==df.building_type.FarmPlot or t==df.building_type.RoadDirt then return {} end
      return {{item_type=0,quantity=1}}
    end
    """)
    return lua


def extended_catalog():
    lua = catalog_runtime()
    source = (Path(__file__).resolve().parents[1] / 'bridge/plugin/construction.lua').read_text()
    def load(): return lua.execute(source)
    def page(helper, **kw): return helper(lua.table_from(dict(action=0, epoch=7, **kw)))
    helper = load()
    first = page(helper)
    assert first['ok'] and first['message'] == 'Construction catalog ready'
    rows = {r['key']: r for r in first['catalog'].values()}
    for parent in ('Workshop','Furnace','Trap','SiegeEngine','Construction','Nest','Wagon','Shop',
                   'Workshop:Custom','Furnace:Custom'):
        assert parent not in rows
    assert not any(k.startswith('Construction:Track') and k != 'Construction:Track' for k in rows)
    for key in ('Chair','Workshop:Carpenters','Trap:Lever','Construction:Stairs',
                'Furnace:WoodFurnace','Trap:CageTrap','SiegeEngine:Catapult'):
        assert rows[key]['supported'], key
    reasons = {'Workshop:Tool':'Building has no recipe',
        'Workshop:Custom:LOCKED':'Not permitted for this civilization',
        'Furnace:Custom:HOT':'Magma placement rule not captured',
        'Furnace:MagmaSmelter':'Magma placement rule not captured',
        'Construction:Track':'Track piece selection not captured',
        'Windmill':'Windmill placement rule not captured',
        'Trap:PressurePlate':'Pressure plate options not captured',
        'Trap:TrackStop':'Track stop options not captured',
        'Stockpile':'Placed from the stockpile and zone menus',
        'Civzone':'Placed from the stockpile and zone menus'}
    for key, reason in reasons.items():
        assert not rows[key]['supported'] and rows[key]['reason'] == reason
    for key, family, code, name in [('Workshop:Custom:PRESS','Workshop','PRESS','Press'),
                                   ('Furnace:Custom:KILN','Furnace','KILN','Kiln')]:
        row=rows[key]
        assert row['supported'] and (row['family'],row['subtype_key'],row['custom_code'],row['native_name']) == (family,'Custom',code,name)
    for key, mode, orient, depth in [('Chair',1,1,1),('Bridge',2,31,1),
                                   ('Construction:Wall',3,1,1),('Construction:Stairs',4,1,256),
                                   ('SiegeEngine:Ballista',1,255,1),('ScrewPump',1,15,1)]:
        row=rows[key]
        assert (row['area_mode'],row['orientations'],row['max_depth']) == (mode,orient,depth)
        assert row['native_name'] == '' and row['custom_code'] == ''
        assert (row['max_width'],row['max_height']) == ((row['width'],row['height']) if mode==1 else (31,31))
        assert (row['family'],row['subtype_key']) == tuple((key.split(':')+[''])[:2])
        assert [f['direction'] for f in row['footprints'].values()] == [i for i in range(8) if orient & (1<<i)]
    for n in (8,9):
        lua.execute('recipes[df.building_type.Chair]={};for i=1,... do table.insert(recipes[df.building_type.Chair],{quantity=1})end',n)
        # Chair is a required self-check key, so use a generic family for overflow.
        lua.execute('recipes[df.building_type.Chain]=recipes[df.building_type.Chair];recipes[df.building_type.Chair]=nil')
        row=next(r for r in page(load())['catalog'].values() if r['key']=='Chain')
        assert row['supported'] == (n==8)
        assert row['reason'] == ('' if n==8 else 'Recipe has more than 8 inputs')
    lua.execute('recipes={};for i=1,150 do customs[#customs+1]={id=100+i,code="C"..i,name="",class="workshop"};permitted_ids[#permitted_ids+1]=100+i end')
    helper=load();first=page(helper);second=page(helper,cursor=128,expected_list_revision=first['list_revision'])
    assert len(first['catalog'])==128 and first['next_cursor']==128
    assert second['next_cursor']==0 and len(second['catalog'])+128==first['total']==second['total']
    assert page(helper,cursor=128,expected_list_revision=first['list_revision']+1)['message']=='List changed; refresh'
    lua.execute('customs[#customs+1]=customs[1]')
    try: load()
    except Exception as error:
        assert str(error).splitlines()[0].split(': ',1)[1] == 'Duplicate construction catalog key: Workshop:Custom:PRESS'
    else: raise AssertionError('duplicate key accepted')


if __name__ == "__main__":
    extended_catalog()
    main()
