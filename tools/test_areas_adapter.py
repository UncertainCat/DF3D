"""Fixed area helper regression using pinned Lua API names; no DF process/assets."""
from pathlib import Path
from lupa import LuaRuntime


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
    package.preload.utils=function() return {} end
    local lookup={[0]='Bedroom',[1]='MeetingHall',Bedroom=0,MeetingHall=1}
    df={civzone_type=setmetatable({_last_item=1},{__index=lookup}),global={world={buildings={all={},other={STOCKPILE={}}},units={active={}}}}}
    df.building_stockpilest={is_instance=function(_,b)return b and b.kind==0 end}
    df.building_civzonest={is_instance=function(_,b)return b and b.kind==1 end}
    dfhack={buildings={},units={},maps={},df2utf=function(s)return s end}
    dfhack.units.isCitizen=function(u)return u.citizen end
    dfhack.units.isActive=function(u)return u.active end
    dfhack.units.isDead=function(u)return u.dead end
    -- Deliberately omit nonexistent dfhack.TranslateName. Only the pinned
    -- public units namespace provides display-name translation here.
    dfhack.units.getReadableName=function(u)return u.label end
    dfhack.maps.isValidTilePos=function()return true end
    dfhack.maps.getTileFlags=function()return {hidden=false} end
    df.global.world.units.active={{id=100,label='Later citizen',citizen=true,active=true},{id=2,label='Early citizen',citizen=true,active=true},{id=3,label='Visitor',citizen=false,active=true}}
    df.unit={find=function(id)for _,u in ipairs(df.global.world.units.active)do if u.id==id then return u end end end}
    pile={id=5,kind=0,name='Custom pile',x1=0,x2=2,y1=0,y2=2,z=1,room={},settings={flags={wood=true,food=true},food={meat={true,false,true}},wood={mats={false,true}}},storage={max_bins=4,max_barrels=2,max_wheelbarrows=1},stockpile_flag={use_links_only=false},links={give_to_pile={},take_from_pile={}}}
    zone={id=6,kind=1,name='Bedroom',type=0,x1=0,x2=2,y1=0,y2=2,z=1,room={},spec_sub_flag={active=true},assigned_unit_id=100}
    df.building={find=function(id) if id==5 then return pile elseif id==6 then return zone end end}
    dfhack.buildings.setOwner=function(b,u)b.assigned_unit_id=u and u.id or -1;return true end
    dfhack.buildings.notifyCivzoneModified=function()end
    function request(action,extra)
     local a={kind=0,id=5,barrels=-1,bins=-1,wheelbarrows=-1,changed_categories=0,categories=0,active=-1,owner_id=-2,links_only=-1,cursor=0,query=''}
     for k,v in pairs(extra or {})do a[k]=v end
     return {action=action,area=a}
    end
    """)
    adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    call = lambda action, values=None: adapter(lua.globals().request(action, lua.table_from(values or {})))
    catalog = call(7)
    assert catalog["ok"] and len(catalog["choices"]) == 2
    candidates = call(14, {"kind": 1})
    assert [r["id"] for r in candidates["choices"].values()] == [2, 100]
    assert call(14, {"kind": 1, "cursor": 50})["choices"][1]["id"] == 100
    assert call(14, {"kind": 1, "query": "Later"})["choices"][1]["name"] == "Later citizen #100"
    observed = call(9, {"kind": 1, "id": 6})
    assert observed["ok"] and observed["areas"][1]["owner_name"] == "Later citizen"
    assert call(11, {"kind": 1, "id": 6, "owner_id": 3})["ok"] is False
    assert call(11, {"kind": 1, "id": 6, "owner_id": -1})["areas"][1]["owner_id"] == -1
    changed = call(11, {"bins": 5, "changed_categories": 8192, "categories": 0})
    assert changed["ok"] and changed["areas"][1]["bins"] == 5
    assert changed["areas"][1]["categories"] == 2
    assert lua.eval("pile.settings.food.meat[1] and not pile.settings.food.meat[2] and pile.settings.food.meat[3]")
    assert lua.eval("not pile.settings.wood.mats[1] and pile.settings.wood.mats[2]")
    rejected = call(11, {"bins": 10, "changed_categories": 2, "categories": 0})
    assert not rejected["ok"] and lua.eval("pile.settings.flags.food and pile.storage.max_bins==5")
    lua.execute("zone.room={x=1,y=1,width=2,height=2,extents={[0]=1,[1]=0,[2]=1,[3]=1}}")
    footprint = call(9, {"kind": 1, "id": 6})["areas"][1]["extents"]
    assert list(footprint.values()) == [0, 0, 0, 0, 1, 0, 0, 1, 1]
    lua.execute("df.global.world.units.active={};for id=260,1,-1 do table.insert(df.global.world.units.active,{id=id,label='Citizen',citizen=true,active=true}) end")
    page = call(14, {"kind": 1})
    assert len(page["choices"]) == 128 and page["next_cursor"] == 129
    later = call(14, {"kind": 1, "cursor": page["next_cursor"]})
    assert later["choices"][1]["id"] == 129 and later["next_cursor"] == 257
    last = call(14, {"kind": 1, "cursor": later["next_cursor"]})
    assert [r["id"] for r in last["choices"].values()] == [257, 258, 259, 260]
    assert last["next_cursor"] == 0
    print("AREAS_ADAPTER PASS")


if __name__ == "__main__":
    main()
