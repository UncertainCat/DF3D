"""Asset-free adapter regression: DF enums are metatable-backed, not iterable maps.

Run with Python + lupa (test tooling only; no DF or presentation dependencies).
"""
from pathlib import Path

from lupa import LuaRuntime


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
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
            building_type=enum{'Chair','Workshop','Construction','Trap'},
            workshop_type=enum{'Carpenters'},
            construction_type=enum{'Wall','Floor'},
            trap_type=enum{'Lever'},
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
                          t==df.building_type.Workshop and 3 or 1
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
                            "Trap:Lever", "Construction:Stairs", "Construction:Track"}
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
            getTileType=function() return 0 end,getWalkableGroup=function() return 1 end}
        local function vector(v) v[0]=table.remove(v,1);return setmetatable(v,{__len=function() return 1 end}) end
        stock={}
        for i=1,3 do
            stock[i]={id=i,flags={on_ground=true},isAssignedToStockpile=function() return false end,
                getType=function() return i==3 and 1 or 0 end,getSubtype=function() return -1 end,
                getMaterial=function() return 0 end,getMaterialIndex=function() return i==2 and 1 or 0 end}
        end
        local all={[0]=stock[1],stock[2],stock[3]}
        setmetatable(all,{__len=function() return 3 end})
        df.global={cur_year=1,cur_year_tick=0,world={raws={buildings={all={}}},items={other={[0]=all}},units={active=vector{{}}}}}
        df.item={find=function(id) reads=reads+1;return stock[id] end}
        dfhack.items={getContainer=function() end,getPosition=function() return {x=0,y=0,z=0} end,
            getGeneralRef=function() end}
        dfhack.units={isDead=function() return false end,isActive=function() return true end,
            isCitizen=function() return true end,getPosition=function() return {} end}
        dfhack.job={isSuitableItem=function() return true end,isSuitableMaterial=function() return true end}
        dfhack.matinfo={decode=function() return {toString=function() return 'stone' end} end}
        dfhack.df2utf=function(v) return v end
        dfhack.with_finalize=function(clean,fn) local v=fn();clean();return v end
        df.delete=function() end
        dfhack.buildings.allocInstance=function() return {room={}} end
        dfhack.buildings.setSize=function() return true end
        dfhack.buildings.getFiltersByType=function() return {{item_type=0,quantity=2},{item_type=1,quantity=1}} end
        dfhack.buildings.constructBuilding=function(v) created=created+1;assert(#v.items==3);return {id=created} end
        created=0;reads=0
    """)
    place_adapter = lua.execute(source.read_text(encoding="utf-8"))
    def call(**fields):
        base = dict(action=63, definition="Chair", epoch=7, filter=0, cursor=0)
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
    lua.execute("df.building_type._last_item = -1")
    broken = lua.execute(source.read_text(encoding="utf-8"))
    result = broken(lua.table_from({"action": 0}))
    assert not result["ok"] and "catalog is incomplete" in result["message"]
    print("CONSTRUCTION_CATALOG PASS")


if __name__ == "__main__":
    main()
