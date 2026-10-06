"""Fixed area helper regression using pinned Lua API names; no DF process/assets."""
from pathlib import Path
import re
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
    -- Native owner names omit getReadableName's English/profession suffix.
    -- Use pinned public translation/visible-name APIs, never dfhack.TranslateName.
    dfhack.units.getReadableName=function(u)return u.readable_label or u.label end
    dfhack.units.getVisibleName=function(u)return u.visible_name or u.label end
    dfhack.translation={translateName=function(n)return n end}
    dfhack.units.getProfessionName=function(u)return u.profession or 'Worker' end
    dfhack.maps.isValidTilePos=function()return true end
    dfhack.maps.getTileFlags=function()return {hidden=false} end
    df.global.world.units.active={{id=100,label='Later citizen',citizen=true,active=true},{id=2,label='Early citizen',citizen=true,active=true},{id=3,label='Visitor',citizen=false,active=true}}
    df.unit_relationship_type={Spouse=0}
    for _,unit in ipairs(df.global.world.units.active)do unit.relationship_ids={[0]=-1};unit.owned_buildings={};unit.sex=1 end
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
    # Native closure stand-ins exercise Lua dispatch/accounting, not native
    # snapshot or paint effects. Native callback/live coverage remains separate.
    lua.execute(r"""
    pile.settings.misc={allow_organic=true,allow_inorganic=true}
    dfhack.buildings.getName=function(b) return b.name~='' and b.name or 'Native default area' end
    dfhack.utf2df=function(s)return s:gsub('\226\152\131','?') end
    snapshot_calls=0;paint_calls=0;notification_calls=0
    df.global.world.buildings.other.IN_PLAY={}
    zone.contained_buildings={}
    dfhack.buildings.notifyCivzoneModified=function()
     notification_calls=notification_calls+1
     if force_notification_error then error('fixture notification failure') end
    end
    function area_snapshot(b,want_visibility,budget)
     budget=budget or math.huge
     snapshot_calls=snapshot_calls+1
     local cost=want_visibility and 3 or 2
     if budget<cost then return {ok=false,message='snapshot budget',steps=0} end
     local extents={};local tiles=0
     for y=b.y1,b.y2 do for x=b.x1,b.x2 do
      local raw=1
      if b.room.extents then
       local rx,ry=x-b.room.x,y-b.room.y
       raw=(rx>=0 and ry>=0 and rx<b.room.width and ry<b.room.height) and b.room.extents[ry*b.room.width+rx] or 0
      end
      extents[#extents+1]=raw~=0 and 1 or 0;tiles=tiles+(raw~=0 and 1 or 0)
     end end
     local revision=1000+b.id
     if b.kind==1 then revision=revision+b.assigned_unit_id*73+(b.spec_sub_flag.active and 500000 or 0) end
     if b.kind==1 and b.squad_room_info then
      for _,room in ipairs(b.squad_room_info)do revision=revision+room.squad_id*83+room.mode.whole*97 end
     end
     if b.kind==1 and b.assigned_units then for _,id in ipairs(b.assigned_units)do revision=revision+id*101 end end
     for i=1,#b.name do revision=revision+b.name:byte(i)*i end
     if b.kind==0 then revision=revision+(b.settings.misc.allow_organic and 100000 or 0)+(b.settings.misc.allow_inorganic and 200000 or 0) end
     if b.kind==0 then
      revision=revision+b.storage.max_bins*17+b.storage.max_barrels*31+b.storage.max_wheelbarrows*53+
       (b.stockpile_flag.use_links_only and 400000 or 0)
      for i,key in ipairs{'animals','food','furniture','corpses','refuse','stone','ammo','coins',
       'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'} do
       if b.settings.flags[key] then revision=revision+(1 << (i-1))*16 end
      end
     end
     if b.kind==0 then
      for group,key in ipairs{'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'} do
       local links=b.links[key] or {}
       if #links>1024 then return {ok=false,message='Link limit reached; no endpoints changed',steps=cost} end
       revision=revision+#links*13
       for i,target in ipairs(links)do revision=revision+target.id*(i+group*1024) end
      end
     end
     if b.kind==1 and b.zone_settings then
      local z=b.zone_settings
      revision=revision+(z.pond.flag.keep_filled and 10000 or 0)+100*z.archery.dir_x+1000*z.archery.dir_y+
       (z.tomb.flags.no_citizens and 20000 or 0)+(z.tomb.flags.no_pets and 40000 or 0)+
       (z.gather.flags.pick_trees and 80000 or 0)+(z.gather.flags.pick_shrubs and 160000 or 0)
     end
     return {ok=true,steps=cost,revision=revision,visible=not force_hidden and not b.hidden,
      x=b.x1,y=b.y1,z=b.z,width=b.x2-b.x1+1,height=b.y2-b.y1+1,extents=extents,
      tile_count=tiles,gives={},takes={},assigned_units=b.assigned_units or {}}
    end
    function repaint(b,spans,mode,budget)
     budget=budget or math.huge
     paint_calls=paint_calls+1
     if budget<4 then return {ok=false,message='paint budget',steps=0} end
     if force_paint_refusal then return {ok=false,message='site refused',steps=4} end
     b.name='Painted fixture'
     if b.kind==1 then
      if force_notification_error then return {ok=false,message='Native zone notification failed; inspect before retrying',steps=4,work_unknown=true} end
      return {ok=true,steps=4,tile_count=9,work_unknown=true}
     end
     return {ok=true,steps=4,tile_count=9}
    end
    workshop={id=7,canLinkToStockpile=function()return not force_unlinkable end}
    local old_find=df.building.find
    df.building.find=function(id)if id==7 then return workshop end;return old_find(id) end
    workshop_link_calls=0
    settings_layout_calls=0;settings_raw_count=0
    function settings_layout(b,budget)
     budget=budget or math.huge
     settings_layout_calls=settings_layout_calls+1
     if budget<108 then return {ok=false,message='Settings layout exceeds remaining step budget',steps=0} end
     if settings_raw_count>65536 then return {ok=false,message='Stockpile settings exceed 65,536 entries',steps=108} end
     return {ok=true,steps=108,raw_count=settings_raw_count,fields={}}
    end
    function workshop_link(w,p,give,unlink,budget)
     workshop_link_calls=workshop_link_calls+1
     assert(w==workshop and p==pile)
     if budget<31 then return {ok=false,message='link budget',steps=1} end
     if force_link_refusal then return {ok=false,message='endpoint cap',steps=31} end
     last_link_give=give;last_link_unlink=unlink
     p.name='Linked fixture'
     return {ok=true,steps=31}
    end
    local old_request=request
    function request(action,extra)
     local r=old_request(action,extra)
     r.step_budget=1536;r.epoch=1;r.area_retire_capacity=1024;r.area_snapshot=area_snapshot;r.repaint=repaint
     r.link_areas=workshop_link
     r.settings_layout=settings_layout
     r.settings_preset=settings_preset
     r.set_location=set_location
     r.create_location=create_location
     r.create_area=create_area
     r.remove_area=remove_area
     r.synchronous_read=action==9 and r.area.operation==1
     r.synchronous_write=action==10 or action==12 or action==11 and (r.area.operation==nil or r.area.operation==0 or r.area.operation==3 or r.area.operation==5 or r.area.operation==7 or r.area.operation==8 or r.area.operation==9)
     return r
    end
    """)
    adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    # Exercise the actual private validation closure without native mutations.
    # Dispatch/effect tests below still call the public adapter; this matrix
    # isolates selector acceptance from unrelated world prerequisites.
    upvalue = lua.eval("""function(fn,wanted)
     for i=1,100 do local name,value=debug.getupvalue(fn,i)
      if not name then break end;if name==wanted then return value end
     end
     error('missing validator upvalue: '..wanted)
    end""")
    validator = upvalue(upvalue(adapter, "native_operation"), "validate_operation")
    action_for = {1: 9, 2: 11, 3: 11, 4: 11, 6: 9, 7: 11, 8: 11, 9: 11, 10: 9, 11: 11, 12: 11, 13: 11, 14: 14, 15: 13}
    for action in range(7, 15):
        for operation in range(16):
            values = {"operation": operation, "id": 7, "expected_revision": 1,
                      "kind": 2 if operation == 15 else 1 if operation in (6, 7, 8, 9, 11, 12, 14) else 0}
            if operation == 0:
                values.update(x=0, y=0, z=0)
                if action == 13:
                    values["link_id"] = 8
            if operation == 2:
                values.update(scope=1, value=1, row_key="row")
            if operation == 3:
                values["preset"] = 1
            if operation == 5:
                values.update(paint_mode=1, paint_z=1, spans=lua.table_from([lua.table_from({"x": 1, "y": 1, "length": 1})]))
            if operation == 7:
                values["location_id"] = -1
            if operation == 8:
                values.update(location_kind=4, profession=0)
            if operation == 9:
                values["zone_settings"] = lua.table_from({"pond_mode": 1})
            if operation == 11:
                values.update(unit_id=0, assign=0)
            if operation == 12:
                values.update(squad_id=0, squad_use=0)
            if operation == 13:
                values["organic"] = 0
            if operation == 14:
                values["candidate_kind"] = 1
            if operation == 15:
                values["link_id"] = 8
            request = lua.globals().request(action, lua.table_from(values))
            allowed = operation == 0 or (action in (10, 11) if operation == 5 else action == action_for[operation])
            assert validator(request, request["area"]) == (None if allowed else "Area operation is not valid for this action"), (action, operation)
            if allowed:
                request["area"]["kind"] = 0 if operation == 15 else 2
                assert validator(request, request["area"]) == "Workshop kind is only valid for workshop links"
    foreign_fields = {"expected_list_revision": 1, "list_key": "x", "row_key": "x", "scope": 1, "value": 1,
        "preset": 1, "name": "x", "spans": lua.table_from([lua.table_from({"x": 1, "y": 1, "length": 1})]),
        "paint_mode": 1, "paint_z": 0, "location_id": -1, "location_kind": 1, "profession": 0,
        "deity_kind": 1, "deity_id": 0, "zone_settings": lua.table_from({"pond_mode": 1}),
        "unit_id": 0, "assign": 0, "squad_id": 0, "squad_use": 0, "organic": 0, "inorganic": 0,
        "candidate_kind": 1, "sort": 1, "sort_descending": True}
    for field, value in foreign_fields.items():
        request = lua.globals().request(9, lua.table_from({field: value}))
        assert validator(request, request["area"]) == f"Field {field} does not belong to this operation"
    request = lua.globals().request(9, lua.table_from({"list_key": "", "row_key": "", "name": "",
        "spans": lua.table_from([]), "zone_settings": lua.table_from({})}))
    assert validator(request, request["area"]) is None
    legacy_fields = {"x": 0, "y": 0, "z": 0, "width": 2, "height": 2, "zone_type": 0,
        "categories": 1, "changed_categories": 1, "barrels": 0, "bins": 0, "wheelbarrows": 0,
        "links_only": 0, "active": 0, "owner_id": -1, "link_id": 8, "give": False, "unlink": True}
    for field, value in legacy_fields.items():
        request = lua.globals().request(11, lua.table_from({"operation": 4, "id": 7, "expected_revision": 1, field: value}))
        assert validator(request, request["area"]) == "Legacy area fields cannot be combined with an operation", field
    required_cases = [(11, {"unit_id": 0, "assign": 0}, "unit_id", "invalid area unit assignment"),
        (11, {"unit_id": 0, "assign": 0}, "assign", "invalid area unit assignment"),
        (12, {"squad_id": 0, "squad_use": 0}, "squad_id", "invalid area squad use"),
        (12, {"squad_id": 0, "squad_use": 0}, "squad_use", "invalid area squad use"),
        (8, {"location_kind": 4, "profession": 0}, "profession", "invalid area location creation"),
        (8, {"location_kind": 2, "deity_kind": 2, "deity_id": 0}, "deity_id", "invalid area location creation")]
    for operation, values, field, message in required_cases:
        request = lua.globals().request(11, lua.table_from({"operation": operation, "id": 7, "kind": 1, "expected_revision": 1, **values}))
        assert validator(request, request["area"]) is None
        request["area"][field] = -1
        assert validator(request, request["area"]) == message
        request["area"][field] = None
        assert validator(request, request["area"]) == message
    for deity_kind in (-1, 0, 1, 2, 3, 4):
        request = lua.globals().request(11, lua.table_from({"operation": 8, "id": 7, "kind": 1,
            "location_kind": 2, "deity_kind": deity_kind, "deity_id": 0 if deity_kind >= 2 else -1}))
        assert validator(request, request["area"]) == (None if 1 <= deity_kind <= 3 else "invalid area location creation")
    stages = [(11, {"operation": 16}, "Unsupported area operation"),
        (9, {}, "Area operation is not valid for this action"),
        (11, {"kind": 2}, "Workshop kind is only valid for workshop links"),
        (11, {"operation": 3, "kind": 1, "preset": 1}, "Area kind is not valid for this operation"),
        (11, {"width": 2}, "Legacy area fields cannot be combined with an operation"),
        (11, {"organic": 0}, "Field organic does not belong to this operation"),
        (11, {"id": -1}, "area id required"),
        (11, {"name": "x"*513}, "area name too long"),
        (11, {"expected_revision": -1}, "invalid area revision")]
    for action, extra, message in stages:
        request = lua.globals().request(action, lua.table_from({"operation": 4, "id": 7, "expected_revision": 1, **extra}))
        assert validator(request, request["area"]) == message
    raw_call = lambda action, values=None: adapter(lua.globals().request(action, lua.table_from(values or {})))
    def call(action, values=None):
        result = raw_call(action, values)
        for _ in range(10000):
            if not result["ok"] or not result["build_phase"]:
                return result
            stepped = adapter(lua.table_from({"step": 64, "builder_kind": 7, "epoch": 1}))
            assert 0 <= stepped["steps"] <= 64 and stepped["active_kinds"] in (0, 128)
            result = raw_call(action, values)
        raise AssertionError("candidate builder did not finish")
    catalog = call(7)
    assert catalog["ok"] and len(catalog["choices"]) == 2
    candidates = call(14, {"kind": 1})
    assert [r["id"] for r in candidates["choices"].values()] == [2, 100]
    assert call(14, {"kind": 1, "cursor": 50})["choices"][1]["id"] == 100
    assert call(14, {"kind": 1, "query": "Later"})["choices"][1]["name"] == "Later citizen #100"
    lua.execute("df.global.world.units.active[1].readable_label='Later citizen \"English\", Worker'")
    observed = call(9, {"kind": 1, "id": 6})
    assert observed["ok"] and observed["areas"][1]["owner_name"] == "Later citizen"
    assert observed["areas"][1]["owner_profession"] == "Worker" and observed["areas"][1]["owner_sex"] == 1
    assert observed["areas"][1]["location_kind"] == 0
    lua.execute("zone.name=''")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["name"] == "Unnamed bedroom"
    lua.execute("zone.type=1")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["name"] == "Unnamed memorial hall"
    lua.execute("zone.type=0;zone.name='Bedroom'")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["name"] == "Bedroom"
    assert call(11, {"kind": 1, "id": 6, "owner_id": 3,
                     "expected_revision": observed["areas"][1]["revision"]})["ok"] is False
    assert call(11, {"kind": 1, "id": 6, "owner_id": -1,
                     "expected_revision": observed["areas"][1]["revision"]})["areas"][1]["owner_id"] == -1
    changed = call(11, {"bins": 5, "changed_categories": 8192, "categories": 0,
                        "expected_revision": call(9)["areas"][1]["revision"]})
    assert changed["ok"] and changed["areas"][1]["bins"] == 5
    assert changed["areas"][1]["categories"] == 2
    assert lua.eval("pile.settings.food.meat[1] and not pile.settings.food.meat[2] and pile.settings.food.meat[3]")
    assert lua.eval("not pile.settings.wood.mats[1] and pile.settings.wood.mats[2]")
    rejected = call(11, {"bins": 10, "changed_categories": 2, "categories": 0,
                         "expected_revision": call(9)["areas"][1]["revision"]})
    assert not rejected["ok"] and lua.eval("pile.settings.flags.food and pile.storage.max_bins==5")
    current_revision = call(9)["areas"][1]["revision"]
    # Raw preflight is independent of stored lengths. This minimal inventory
    # stand-in does not provide the descriptors needed by the summary builder.
    for action, operation in [(9, 1), (11, 2)]:
        values = {"operation": operation, "expected_revision": current_revision}
        if operation == 2:
            values.update(scope=4, value=2)
        elif operation == 3:
            values["preset"] = 1
        lua.execute("settings_raw_count=65537")
        result = raw_call(action, values)
        assert result["message"] == "Stockpile settings exceed 65,536 entries"
        assert result["steps"] == 121
        lua.execute("settings_raw_count=65536")
        result = raw_call(action, values)
        assert result["message"] == ("Stockpile settings layout changed" if operation in (1, 2) else "Area operation producer is not yet available")
        assert result["steps"] == (228 if operation == 2 else 121)
        before_calls = lua.globals().settings_layout_calls
        result = raw_call(action, {**values, "expected_revision": 1})
        assert result["message"] == "Area changed; inspect again"
        assert lua.globals().settings_layout_calls == before_calls
        request = lua.globals().request(action, lua.table_from(values))
        request["step_budget"] = 120
        result = adapter(request)
        if operation == 1:
            assert result["message"] == "Stockpile settings layout changed" and result["steps"] == 121
        else:
            assert result["message"] == "Settings layout exceeds remaining step budget" and result["steps"] == 13
    lua.execute("settings_raw_count=0")
    assert call(9)["areas"][1]["revision"] == current_revision
    before_calls = lua.globals().settings_layout_calls
    for values in [{"scope": 0, "value": 2}, {"scope": 5, "value": 2},
                   {"scope": 1, "value": 2}, {"scope": 2, "value": 0},
                   {"scope": 2, "value": 3}, {"scope": 2, "value": 2, "row_key": "food/meat/0"}]:
        assert raw_call(11, {"operation": 2, "expected_revision": current_revision, **values})["message"] == "invalid area settings edit"
    for preset in [0, 20, 1.5]:
        assert raw_call(11, {"operation": 3, "preset": preset, "expected_revision": current_revision})["message"] == "invalid area preset"
    assert raw_call(11, {"operation": 3, "expected_revision": current_revision})["message"] == "invalid area preset"
    assert lua.globals().settings_layout_calls == before_calls
    for values in [{"bins": 0}, {"bins": 0, "expected_revision": 1},
                   {"bins": 0, "active": 1, "expected_revision": current_revision},
                   {"bins": 0, "owner_id": -1, "expected_revision": current_revision},
                   {"bins": -2, "expected_revision": current_revision},
                   {"links_only": 2, "expected_revision": current_revision},
                   {"categories": 131072, "expected_revision": current_revision},
                   {"changed_categories": 1.5, "expected_revision": current_revision}]:
        assert not call(11, values)["ok"]
        assert lua.eval("pile.storage.max_bins") == 5
    lua.execute("pile.room={x=0,y=0,width=3,height=3,extents={[0]=1,[1]=0,[2]=1,[3]=0,[4]=1,[5]=0,[6]=0,[7]=0,[8]=0}}")
    current_revision = call(9)["areas"][1]["revision"]
    assert call(11, {"bins": 4, "expected_revision": current_revision})["message"] == "Container limits exceed usable stockpile tiles"
    assert not call(11, {"wheelbarrows": 3, "expected_revision": current_revision})["ok"]
    containers = {"bins": 3, "barrels": 3, "wheelbarrows": 2, "links_only": 1,
                  "expected_revision": current_revision}
    scarce_update = lua.globals().request(11, lua.table_from(containers))
    scarce_update["step_budget"] = 0
    updated = adapter(scarce_update)
    assert updated["ok"] and updated["steps"] == 36 and updated["areas"][1]["bins"] == 3
    assert updated["areas"][1]["barrels"] == 3 and updated["areas"][1]["wheelbarrows"] == 2
    assert updated["areas"][1]["links_only"] and updated["areas"][1]["revision"] != current_revision
    assert not call(11, {"bins": 2, "expected_revision": current_revision})["ok"]
    assert lua.eval("pile.settings.food.meat[1] and not pile.settings.food.meat[2] and pile.settings.food.meat[3]")
    assert lua.eval("not pile.settings.wood.mats[1] and pile.settings.wood.mats[2]")
    lua.execute("pile.room={}")
    lua.execute("zone.room={x=1,y=1,width=2,height=2,extents={[0]=1,[1]=0,[2]=1,[3]=1}}")
    footprint = call(9, {"kind": 1, "id": 6})["areas"][1]["extents"]
    assert list(footprint.values()) == [0, 0, 0, 0, 1, 0, 0, 1, 1]
    lua.execute("df.global.cur_year_tick=2401;df.global.world.units.active={};for id=260,1,-1 do table.insert(df.global.world.units.active,{id=id,label='Citizen',citizen=true,active=true}) end")
    page = call(14, {"kind": 1})
    assert len(page["choices"]) == 128 and page["next_cursor"] == 129
    later = call(14, {"kind": 1, "cursor": page["next_cursor"]})
    assert later["choices"][1]["id"] == 129 and later["next_cursor"] == 257
    last = call(14, {"kind": 1, "cursor": later["next_cursor"]})
    assert [r["id"] for r in last["choices"].values()] == [257, 258, 259, 260]
    assert last["next_cursor"] == 0
    def revision():
        return call(9)["areas"][1]["revision"]

    renamed = call(11, {"operation": 4, "name": "New pile", "expected_revision": revision()})
    assert renamed["ok"] and renamed["areas"][1]["name"] == "New pile"
    assert renamed["steps"] == 16 and renamed["active_kinds"] == 0 and renamed["operation"] == 4
    assert not call(11, {"operation": 4, "name": "stale", "expected_revision": 1})["ok"]
    assert lua.eval("pile.name") == "New pile"
    assert not call(11, {"operation": 4, "name": "missing revision"})["ok"]
    assert not call(11, {"operation": 4, "name": "x" * 129, "expected_revision": revision()})["ok"]
    assert not call(11, {"operation": 4, "name": "\u2603", "expected_revision": revision()})["ok"]
    cleared = call(11, {"operation": 4, "name": "", "expected_revision": revision()})
    assert cleared["ok"] and cleared["areas"][1]["name"] == "Native default area"
    toggled = call(11, {"operation": 13, "organic": 0, "expected_revision": revision()})
    assert toggled["ok"] and toggled["areas"][1]["organic"] == 0 and toggled["areas"][1]["inorganic"] == 1
    assert not call(11, {"operation": 13, "organic": 2, "expected_revision": revision()})["ok"]
    assert not call(11, {"operation": 13, "organic": 0, "kind": 1, "id": 6})["ok"]
    assert not call(9, {"operation": 4, "name": "wrong action"})["ok"]
    assert not call(11, {"operation": 4, "name": "foreign", "organic": 1})["ok"]
    assert not call(11, {"operation": 4, "name": "legacy", "x": 0})["ok"]
    lua.execute("force_hidden=true")
    assert not call(9)["ok"]
    lua.execute("force_hidden=false")
    draft = {"operation": 5, "paint_mode": 1, "expected_revision": revision(),
             "spans": lua.table_from([lua.table_from({"x": 0, "y": 0, "length": 1})])}
    painted = call(11, draft)
    assert painted["ok"] and painted["steps"] == 19 and lua.eval("paint_calls") == 1
    draft["expected_revision"] = revision()
    draft["paint_z"] = 2
    assert not call(11, draft)["ok"] and lua.eval("paint_calls") == 1
    draft["paint_z"] = -1
    request = lua.globals().request(11, lua.table_from(draft))
    request["area_retire_capacity"] = 0
    assert not adapter(request)["ok"] and lua.eval("paint_calls") == 1
    request["area_retire_capacity"] = 1
    request["step_budget"] = 0
    lua.execute("force_paint_refusal=true")
    refused = adapter(request)
    assert not refused["ok"] and refused["message"] == "site refused" and refused["steps"] == 17
    assert adapter(lua.table_from({"step": 2048, "builder_kind": 5, "epoch": 1}))["steps"] == 0
    assert catalog["choices"][1]["label"] == "Bedroom" and catalog["choices"][2]["label"] == "Meeting Area"
    assert not adapter(lua.table_from({"step": 2049, "builder_kind": 5, "epoch": 1}))["ok"]
    assert not adapter(lua.table_from({"step": 1, "builder_kind": 4, "epoch": 1}))["ok"]
    for zone_type, key, expected in [(2, "pond_mode", 2), (3, "facing", 3),
                                     (4, "tomb_pets", 0), (5, "gather_trees", 1)]:
        lua.execute("""
        local names={[2]='Pond',[3]='ArcheryRange',[4]='Tomb',[5]='PlantGathering'}
        for id,label in pairs(names)do df.civzone_type[id]=label end
        zone.zone_settings={pond={flag={keep_filled=true}},archery={dir_x=0,dir_y=-1},
         tomb={flags={no_pets=true,no_citizens=false}},gather={flags={pick_trees=true,pick_shrubs=false}}}
        """)
        lua.globals().zone["type"] = zone_type
        row = call(9, {"kind": 1, "id": 6})["areas"][1]
        assert row["zone_settings"][key] == expected
    # Op 9 exercises the real Lua mutations; native notification is a stand-in.
    def zone_edit(settings, expected=None):
        if expected is None:
            expected = call(9, {"kind": 1, "id": 6})["areas"][1]["revision"]
        return {"operation": 9, "kind": 1, "id": 6, "expected_revision": expected,
                "zone_settings": lua.table_from(settings)}

    for zone_type, key, values in [(2, "pond_mode", [1, 2]), (3, "facing", [1, 2, 3, 4]),
                                    (4, "tomb_citizens", [0, 1]), (4, "tomb_pets", [1, 0]),
                                    (5, "gather_trees", [0, 1]), (5, "gather_shrubs", [1, 0])]:
        lua.globals().zone["type"] = zone_type
        for value in values:
            before = lua.eval("notification_calls")
            edited = call(11, zone_edit({key: value}))
            assert edited["ok"] and edited["steps"] == 16
            assert edited["areas"][1]["zone_settings"][key] == value
            assert lua.eval("notification_calls") == before + 1
        for other in [0, 2, 3, 4, 5]:
            if other == zone_type:
                continue
            lua.globals().zone["type"] = other
            before = lua.eval("notification_calls")
            rejected = call(11, zone_edit({key: values[0]}))
            assert not rejected["ok"] and rejected["message"] == f"Setting {key} does not apply to this zone type"
            assert lua.eval("notification_calls") == before
    lua.globals().zone["type"] = 2
    for settings in [{}, {"pond_mode": 3}, {"pond_mode": 1.5}, {"pond_mode": True},
                     {"facing": -1}, {"tomb_pets": -2}, {"gather_trees": 2}]:
        assert call(11, zone_edit(settings))["message"] == "invalid area zone settings"
    before = lua.eval("notification_calls")
    assert not call(11, zone_edit({"pond_mode": 1}, 1))["ok"]
    assert not call(11, zone_edit({"pond_mode": 1}, 0))["ok"]
    # A valid field combined with an inapplicable field must leave both untouched.
    old_mode = call(9, {"kind": 1, "id": 6})["areas"][1]["zone_settings"]["pond_mode"]
    assert not call(11, zone_edit({"pond_mode": 3 - old_mode, "tomb_pets": 0}))["ok"]
    assert lua.eval("notification_calls") == before
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["zone_settings"]["pond_mode"] == old_mode
    lua.execute("df.global.world.buildings.other.IN_PLAY={{relations={}},{relations={}}}")
    budgeted = lua.globals().request(11, lua.table_from(zone_edit({"pond_mode": 3 - old_mode})))
    budgeted["step_budget"] = 0
    edited = adapter(budgeted)
    assert edited["ok"] and edited["steps"] == 16 and edited["work_unknown"]
    assert lua.eval("notification_calls") == before + 1
    lua.execute("df.global.world.buildings.other.IN_PLAY={};for i=1,5000 do table.insert(df.global.world.buildings.other.IN_PLAY,{relations={}}) end")
    large_world = call(11, zone_edit({"pond_mode": old_mode}))
    assert large_world["ok"] and large_world["work_unknown"]
    lua.execute("df.global.world.buildings.other.IN_PLAY={};force_notification_error=true")
    uncertain = call(11, zone_edit({"pond_mode": old_mode}))
    assert not uncertain["ok"] and uncertain["steps"] == 14 and uncertain["work_unknown"]
    assert uncertain["message"] == "Native zone notification failed; inspect before retrying"
    lua.execute("force_notification_error=false;force_paint_refusal=false")
    # Native repaint notification failure can follow the extent commit. Preserve
    # known work, report uncertainty, and do not replay or claim successful paint.
    zone_paint = dict(draft, kind=1, id=6, expected_revision=call(9, {"kind": 1, "id": 6})["areas"][1]["revision"])
    paint_request = lua.globals().request(11, lua.table_from(zone_paint))
    paint_request["step_budget"] = 0
    result = adapter(paint_request)
    assert result["ok"] and result["work_unknown"] and result["steps"] == 19
    paint_request["area"]["expected_revision"] = call(9, {"kind": 1, "id": 6})["areas"][1]["revision"]
    lua.execute("force_notification_error=true")
    before_paints = lua.eval("paint_calls")
    result = adapter(paint_request)
    assert not result["ok"] and result["work_unknown"] and result["steps"] == 17
    assert result["message"] == "Native zone notification failed; inspect before retrying"
    assert lua.eval("paint_calls") == before_paints+1
    lua.execute("force_notification_error=false")
    link = {"operation": 15, "kind": 2, "id": 7, "link_id": 5, "expected_revision": revision()}
    for give, unlink in [(True, False), (False, False), (True, True), (False, True)]:
        link.update(give=give, unlink=unlink, expected_revision=revision())
        linked = call(13, link)
        assert linked["ok"] and linked["steps"] == 46
        assert linked["areas"][1]["id"] == 5 and linked["areas"][1]["kind"] == 0
        assert linked["area_id"] == 7 and linked["building_id"] == 5
        assert lua.eval("last_link_give") == give and lua.eval("last_link_unlink") == unlink
    before = lua.eval("workshop_link_calls")
    for bad in [{"expected_revision": 1}, {"expected_revision": 0}, {"link_id": 7},
                {"link_id": 999}, {"id": 999}, {"link_id": 6}, {"give": 1}]:
        assert not call(13, dict(link, **bad))["ok"]
    assert lua.eval("workshop_link_calls") == before
    lua.execute("force_unlinkable=true")
    assert call(13, link)["message"] == "This workshop cannot link to stockpiles"
    lua.execute("force_unlinkable=false;force_link_refusal=true")
    link["expected_revision"] = revision()
    assert call(13, link)["message"] == "endpoint cap"
    lua.execute("force_link_refusal=false")
    low_budget = lua.globals().request(13, lua.table_from(link))
    low_budget["step_budget"] = 197  # 13 snapshot + 31 link + 154 reserved reply.
    assert not adapter(low_budget)["ok"]
    low_budget["step_budget"] = 198
    assert adapter(low_budget)["ok"]
    lua.execute("""
    local function clone(value)
     if type(value)~='table' then return value end
     local out={};for key,v in pairs(value)do out[key]=clone(v) end;return out
    end
    other_pile=clone(pile);other_pile.id=8
    local old_find=df.building.find
    df.building.find=function(id)if id==8 then return other_pile end;return old_find(id) end
    local prior_request=request;local prior_link=workshop_link
    legacy_link_calls=0
    function request(action,extra)
     local r=prior_request(action,extra)
     r.link_areas=function(first,second,give,unlink,budget)
      if first.kind~=0 then return prior_link(first,second,give,unlink,budget) end
      assert(first==pile and second==other_pile)
      if budget<31 then return {ok=false,message='link budget',steps=1} end
      legacy_link_calls=legacy_link_calls+1;last_link_give=give;last_link_unlink=unlink
      first.name='Linked pile fixture'
      return {ok=true,steps=31}
     end
     return r
    end
    """)
    legacy_link = {"link_id": 8, "expected_revision": revision()}
    for give, unlink in [(True, False), (False, False), (True, True), (False, True)]:
        legacy_link.update(give=give, unlink=unlink, expected_revision=revision())
        linked = call(13, legacy_link)
        assert linked["ok"] and linked["steps"] == 49 and linked["operation"] == 0
        assert linked["area_id"] == 5 and linked["areas"][1]["id"] == 5 and linked["building_id"] == 5
        assert lua.eval("last_link_give") == give and lua.eval("last_link_unlink") == unlink
    before = lua.eval("legacy_link_calls")
    for bad in [{"expected_revision": 0}, {"expected_revision": 1}, {"link_id": 5},
                {"link_id": 6}, {"link_id": 999}, {"give": 0}, {"unlink": 1}]:
        assert not call(13, dict(legacy_link, **bad))["ok"]
    lua.execute("other_pile.hidden=true")
    assert call(13, legacy_link)["message"] == "Area is not visible"
    lua.execute("other_pile.hidden=false")
    assert lua.eval("legacy_link_calls") == before
    scarce = lua.globals().request(13, lua.table_from(legacy_link))
    scarce["step_budget"] = 200
    assert not adapter(scarce)["ok"] and lua.eval("legacy_link_calls") == before
    scarce["step_budget"] = 201
    assert adapter(scarce)["ok"] and lua.eval("legacy_link_calls") == before + 1
    lua.execute("""
    zone.type=0;zone.assigned_units={2};zone.squad_room_info={}
    df.global.cur_year_tick=2000
    df.global.plotinfo={group_id=7}
    df.global.world.squads={all={}}
    dfhack.units.getProfessionName=function(u)return u.profession or 'Worker' end
    dfhack.units.getStressCategory=function(u)return u.stress or 0 end
    dfhack.units.isGrazer=function(u)return u.grazer or false end
    dfhack.units.isTame=function(u)return u.tame or false end
    dfhack.translation={translateName=function(n)return n end}
    for _,u in ipairs(df.global.world.units.active)do u.sex=1;u.flags1={caged=false};u.profession='Worker';u.stress=u.id%7 end
    """)
    selector = {"operation": 14, "kind": 1, "id": 6, "candidate_kind": 1, "sort": 1}
    pending = raw_call(14, selector)
    assert pending["ok"] and pending["build_phase"] == 1 and pending["build_done"] == 0
    assert pending["candidates"] is None and pending["active_kinds"] == 128
    owners = call(14, selector)
    assert owners["ok"] and len(owners["candidates"]) == 128 and owners["next_cursor"] == 128
    assert owners["steps"] <= 1536 and owners["list_revision"] > 0
    next_selector = dict(selector, cursor=128, expected_list_revision=owners["list_revision"])
    owner_page = call(14, next_selector)
    assert owner_page["candidates"][1]["id"] == 129 and owner_page["next_cursor"] == 256
    assert not call(14, dict(selector, expected_list_revision=owners["list_revision"] + 1))["ok"]
    descending = call(14, dict(selector, sort=0, sort_descending=True))
    assert descending["candidates"][1]["id"] == 1  # source vector is descending IDs
    searched = call(14, dict(selector, query="260"))
    assert len(searched["candidates"]) == 1 and searched["candidates"][1]["id"] == 260
    category = call(14, dict(selector, sort=2))
    assert category["candidates"][1]["mood"] == 1
    lua.execute("df.global.cur_year_tick=4400")
    assert raw_call(14, dict(selector, expected_list_revision=owners["list_revision"]))["ok"]
    lua.execute("df.global.cur_year_tick=4401")
    assert not raw_call(14, dict(selector, expected_list_revision=owners["list_revision"]))["ok"]
    refreshed = call(14, selector)
    assert refreshed["ok"]
    assert not call(11, {"operation": 4, "name": "x" * 129, "expected_revision": revision()})["ok"]
    assert raw_call(14, dict(selector, expected_list_revision=refreshed["list_revision"]))["ok"]
    # An unrelated successful area edit invalidates cached area lists too.
    assert call(11, {"operation": 13, "organic": 1, "expected_revision": revision()})["ok"]
    assert not raw_call(14, dict(selector, expected_list_revision=refreshed["list_revision"]))["ok"]
    lua.execute("""
    df.global.cur_year_tick=4000;zone.type=2;df.civzone_type[2]='Pond'
    df.global.world.units.active={
     {id=10,label='Yak',active=true,tame=true,grazer=true,sex=1,flags1={caged=false}},
     {id=11,label='Caged visitor',active=true,sex=0,flags1={caged=true}},
     {id=12,label='Wild visitor',active=true,sex=0,flags1={caged=false}}}
    zone.assigned_units={10}
    """)
    animals = call(14, {"operation": 14, "kind": 1, "id": 6, "candidate_kind": 2})
    assert [v["id"] for v in animals["candidates"].values()] == [10, 11]
    assert animals["candidates"][1]["grazer"] and animals["candidates"][1]["assigned"]
    lua.execute("""
    df.global.cur_year_tick=5000;zone.type=6;df.civzone_type[6]='Barracks'
    df.global.world.squads.all={{id=20,entity_id=7,alias='Guard',name='A'},
     {id=21,entity_id=8,alias='Foreign',name='B'},{id=22,entity_id=7,alias='',name='Translated'}}
    zone.squad_room_info={{squad_id=20,mode={whole=3}}}
    """)
    squads = call(14, {"operation": 14, "kind": 1, "id": 6, "candidate_kind": 3})
    assert [v["id"] for v in squads["candidates"].values()] == [20, 22]
    assert squads["candidates"][1]["squad_use"] == 3 and squads["candidates"][2]["name"] == "Translated"
    # Jobs from an old epoch cannot continue after an epoch transition.
    adapter(lua.table_from({"step": 1, "builder_kind": 7, "epoch": 2}))
    assert raw_call(14, dict(selector, expected_list_revision=refreshed["list_revision"]))["ok"] is False
    # Cache insertion is bounded to eight selector lists. The ninth evicts LRU;
    # old revision receipts then demand an explicit refresh instead of reuse.
    lua.execute("zone.type=0;df.global.cur_year_tick=6000")
    cache_receipts = []
    for number in range(9):
        selected = dict(selector, query="cache-" + str(number))
        cached = call(14, selected)
        assert cached["ok"]
        cache_receipts.append((selected, cached["list_revision"]))
    first_selector, first_revision = cache_receipts[0]
    assert not raw_call(14, dict(first_selector, expected_list_revision=first_revision))["ok"]
    lua.execute("""
    df.global.cur_year_tick=7000;df.global.world.units.active={}
    for id=1,4097 do df.global.world.units.active[id]={id=id,label='Citizen',citizen=true,active=true,
     sex=1,flags1={caged=false},profession='Worker',stress=0} end
    """)
    over_cap = call(14, selector)
    assert not over_cap["ok"] and over_cap["message"] == "Candidate list exceeds 4,096 entries"
    lua.execute("table.remove(df.global.world.units.active)")
    maximum = call(14, selector)
    assert maximum["ok"] and len(maximum["candidates"]) == 128
    last_page = call(14, dict(selector, cursor=3968, expected_list_revision=maximum["list_revision"]))
    assert last_page["next_cursor"] == 0 and last_page["candidates"][128]["id"] == 4096
    # Build source changes reject and can subsequently be refreshed.
    changed_selector = dict(selector, query="source-change")
    assert raw_call(14, changed_selector)["build_phase"] == 1
    lua.execute("table.remove(df.global.world.units.active)")
    changed = call(14, changed_selector)
    assert not changed["ok"] and changed["message"] == "List changed; refresh"
    assert call(14, changed_selector)["ok"]
    # Legacy stockpile visibility scanning is incremental too.
    lua.execute("df.global.world.buildings.other.STOCKPILE={pile};df.global.cur_year_tick=8000")
    stockpiles = call(14, {"kind": 0, "query": ""})
    assert stockpiles["ok"] and stockpiles["choices"][1]["id"] == 5
    lua.execute("""
    df.global.cur_year_tick=9000
    linked_pile={id=30,kind=0,name='Supply pile'}
    linked_workshop={id=40,name='Carpenter'}
    link_targets={[30]=linked_pile,[40]=linked_workshop}
    local prior_find=df.building.find
    df.building.find=function(id)return link_targets[id] or prior_find(id) end
    pile.links={give_to_pile={linked_pile},take_from_pile={linked_pile},
     give_to_workshop={linked_workshop},take_from_workshop={linked_workshop}}
    """)
    link_selector = {"operation": 10, "kind": 0, "id": 5}
    pending = raw_call(9, link_selector)
    assert pending["ok"] and pending["build_phase"] == 1 and pending["build_done"] == 0
    assert pending["build_total"] == 4 and pending["active_kinds"] == 128 and pending["links"] is None
    links = call(9, link_selector)
    assert links["ok"] and links["list_revision"] > 0 and links["next_cursor"] == 0
    assert [(v["id"], v["kind"], v["direction"], v["name"]) for v in links["links"].values()] == [
        (30, 0, 1, "Supply pile"), (30, 0, 2, "Supply pile"),
        (40, 2, 1, "Carpenter"), (40, 2, 2, "Carpenter")]
    assert links["candidates"] is None and links["choices"] is None
    exhausted = lua.globals().request(9, lua.table_from(link_selector))
    exhausted["step_budget"] = 13
    assert adapter(exhausted)["message"] == "Area page exceeds remaining step budget"
    exhausted["step_budget"] = 14
    one_row = adapter(exhausted)
    assert one_row["ok"] and one_row["steps"] == 14 and len(one_row["links"]) == 1
    assert one_row["next_cursor"] == 1 and one_row["truncated"]
    assert len(call(9, dict(link_selector, query="carp"))["links"]) == 2
    assert len(call(9, dict(link_selector, query="30"))["links"]) == 2
    assert not call(9, dict(link_selector, expected_list_revision=links["list_revision"] + 1))["ok"]
    # Same target in a different direction is legal; duplicate within one is not.
    lua.execute("table.insert(pile.links.give_to_pile,linked_pile)")
    assert call(9, link_selector)["message"] == "Duplicate link identity"
    lua.execute("table.remove(pile.links.give_to_pile);df.global.cur_year_tick=11401")
    assert raw_call(9, link_selector)["build_phase"] == 1
    lua.execute("pile.links.take_from_pile={}")
    # Refreshing with the old receipt cannot silently reuse the changed list.
    assert not raw_call(9, dict(link_selector, expected_list_revision=links["list_revision"]))["ok"]
    fresh_links = call(9, link_selector)
    assert fresh_links["ok"] and len(fresh_links["links"]) == 3
    # Build the full 4096-entry link set across scheduler slices and page it.
    lua.execute("""
    pile.links={give_to_pile={},take_from_pile={},give_to_workshop={},take_from_workshop={}}
    for i=1,1024 do
     local p={id=100+i,kind=0,name='Pile '..i};local w={id=2000+i,name='Workshop '..i}
     link_targets[p.id]=p;link_targets[w.id]=w
     table.insert(pile.links.give_to_pile,p);table.insert(pile.links.take_from_pile,p)
     table.insert(pile.links.give_to_workshop,w);table.insert(pile.links.take_from_workshop,w)
    end
    """)
    maximum_links = call(9, link_selector)
    assert maximum_links["ok"] and len(maximum_links["links"]) == 128 and maximum_links["next_cursor"] == 128
    end_links = call(9, dict(link_selector, cursor=3968, expected_list_revision=maximum_links["list_revision"]))
    assert len(end_links["links"]) == 128 and end_links["links"][128]["id"] == 3024
    assert end_links["next_cursor"] == 0 and end_links["links"][128]["direction"] == 2
    assert len(call(9, dict(link_selector, cursor=4096))["links"]) == 0
    lua.execute("table.insert(pile.links.give_to_pile,linked_pile)")
    assert not call(9, link_selector)["ok"]
    lua.execute("table.remove(pile.links.give_to_pile)")
    assert call(11, {"operation": 13, "organic": 0, "expected_revision": revision()})["ok"]
    assert not raw_call(9, dict(link_selector, expected_list_revision=maximum_links["list_revision"]))["ok"]
    lua.execute("""
    df.global.cur_year_tick=12000
    location_site={id=90,buildings={}}
    dfhack.world={getCurrentSite=function()return location_site end}
    df.abstract_building_type={[8]='INN_TAVERN',[2]='TEMPLE',[9]='LIBRARY',[11]='GUILDHALL',[13]='HOSPITAL',[1]='KEEP'}
    df.religious_practice_type={WORSHIP_HFID=0,RELIGION_ENID=1}
    df.historical_figure={find=function(id)if id==17 then return {name='The Deity'} end end}
    df.historical_entity={find=function(id)if id==18 then return {name='The Faith'} end end}
    function location(id,kind,label,practice,practice_id)
     return {id=id,name=label,getType=function()return kind end,deity_type=practice or -1,
      deity_data={practice_id=practice_id or -1},contents={profession=41,location_tier=0}}
    end
    location_site.buildings={location(1,8,'The Tavern'),location(2,2,'Temple A',0,17),
     location(3,9,'Library'),location(4,11,'Guildhall'),location(5,13,'Hospital'),
     location(6,2,'Temple B',1,18),location(7,2,'Temple C',1,-1),location(8,1,'Keep'),
     location(9,2,'Temple D',0,999)}
    """)
    locations_selector = {"operation": 6, "kind": 1, "id": 6}
    pending = raw_call(9, locations_selector)
    assert pending["ok"] and pending["build_phase"] == 1 and pending["build_total"] == 9
    locations = call(9, locations_selector)
    assert locations["ok"] and len(locations["locations"]) == 8
    assert [v["location_kind"] for v in locations["locations"].values()] == [1, 2, 3, 4, 5, 2, 2, 2]
    assert locations["locations"][2]["religion"] == "The Deity"
    assert locations["locations"][6]["religion"] == "The Faith"
    assert locations["locations"][4]["guild_profession"] == 41
    assert locations["locations"][4]["location_tier"] == 0
    assert all(v["site_id"] == 90 for v in locations["locations"].values())
    lua.execute("location_site.buildings[4].contents.location_tier=2")
    changed_tier = call(9, locations_selector)
    assert changed_tier["locations"][4]["location_tier"] == 2
    assert changed_tier["list_revision"] != locations["list_revision"]
    lua.execute("location_site.buildings[4].contents.location_tier=0")
    assert locations["locations"][7]["religion"] == "" and locations["locations"][8]["religion"] == ""
    assert len(call(9, dict(locations_selector, query="temple"))["locations"]) == 4
    assert call(9, dict(locations_selector, query="5"))["locations"][1]["name"] == "Hospital"
    assert not call(9, dict(locations_selector, expected_list_revision=locations["list_revision"] + 1))["ok"]
    lua.execute("location_site.id=91")
    assert not call(9, dict(locations_selector, expected_list_revision=locations["list_revision"]))["ok"]
    assert call(9, locations_selector)["list_revision"] != locations["list_revision"]
    lua.execute("saved_site=location_site;location_site=nil")
    assert call(9, locations_selector)["message"] == "Location site no longer exists"
    lua.execute("location_site=saved_site;df.global.cur_year_tick=14401")
    assert raw_call(9, locations_selector)["build_phase"] == 1
    lua.execute("table.remove(location_site.buildings)")
    assert call(9, locations_selector)["message"] == "List changed; refresh"
    assert call(9, locations_selector)["ok"]
    lua.execute("location_site.buildings={location(1,8,'A'),location(1,8,'B')};df.global.cur_year_tick=16802")
    assert not call(9, locations_selector)["ok"]
    lua.execute("location_site.buildings={location(1,8,string.rep('X',513))};df.global.cur_year_tick=19203")
    assert not call(9, locations_selector)["ok"]
    # Location cache cap is the general 65536 limit, not the candidate cap.
    lua.execute("location_site.buildings={};for i=1,65537 do location_site.buildings[i]=location(i,8,'Tavern '..i) end;df.global.cur_year_tick=21604")
    def location_page(values):
        result = raw_call(9, values)
        for _ in range(2000):
            if not result["ok"] or not result["build_phase"]:
                return result
            step = adapter(lua.table_from({"step": 2048, "builder_kind": 7, "epoch": 1}))
            assert 0 <= step["steps"] <= 2048
            result = raw_call(9, values)
        raise AssertionError("location list did not finish")
    assert location_page(locations_selector)["message"] == "List exceeds 65,536 entries"
    lua.execute("table.remove(location_site.buildings)")
    maximum_locations = location_page(locations_selector)
    assert maximum_locations["ok"] and len(maximum_locations["locations"]) == 128
    final_locations = raw_call(9, dict(locations_selector, cursor=65408, expected_list_revision=maximum_locations["list_revision"]))
    assert final_locations["locations"][128]["id"] == 65536 and final_locations["next_cursor"] == 0
    lua.execute("""
    zone.site_id=91;zone.location_id=6
    observed_site={id=91,buildings={location(6,2,'Assigned temple',1,18)}}
    df.world_site={find=function(id)if id==91 then return observed_site end end}
    location_site={id=92,buildings={location(6,8,'Wrong current-site location')}}
    """)
    observed = call(9, {"kind": 1, "id": 6})
    assert observed["ok"] and observed["areas"][1]["location_name"] == "Assigned temple"
    assert observed["areas"][1]["location_kind"] == 2
    assert observed["areas"][1]["location_site_id"] == 91
    assert observed["areas"][1]["religion"] == "The Faith" and observed["areas"][1]["location_id"] == 6
    edited = call(11, {"operation": 4, "kind": 1, "id": 6, "name": "Renamed zone",
                       "expected_revision": observed["areas"][1]["revision"]})
    assert edited["ok"] and edited["areas"][1]["location_name"] == "Assigned temple"
    no_budget = lua.globals().request(9, lua.table_from({"kind": 1, "id": 6}))
    no_budget["step_budget"] = 15
    assert not adapter(no_budget)["ok"]
    no_budget["step_budget"] = 16
    assert adapter(no_budget)["ok"]
    lua.execute("observed_site.buildings[1].name=string.rep('X',513)")
    rejected_label = call(11, {"operation": 4, "kind": 1, "id": 6, "name": "Must not change",
                              "expected_revision": edited["areas"][1]["revision"]})
    assert not rejected_label["ok"] and rejected_label["message"] == "Area location label exceeds 512 bytes"
    assert lua.eval("zone.name") == "Renamed zone"
    lua.execute("observed_site.buildings={location(5,8,'Before'),location(7,8,'After')}")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_name"] == ""
    lua.execute("zone.site_id=999")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["religion"] == ""
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_site_id"] == 999
    lua.execute("zone.location_id=-1")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_id"] == -1
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_site_id"] == -1
    lua.execute("""
    zone.type=0;zone.assigned_unit_id=20;zone.spec_sub_flag.active=true
    df.global.world.buildings.other.IN_PLAY={}
    df.global.world.units.active={}
    for i=20,23 do
     local u={id=i,label='Owner '..i,citizen=true,active=true,relationship_ids={[0]=-1},owned_buildings={zone}}
     table.insert(df.global.world.units.active,u)
    end
    df.unit.find(20).relationship_ids[0]=21;df.unit.find(22).relationship_ids[0]=23
    owner_calls=0
    dfhack.buildings.setOwner=function(b,u)
     owner_calls=owner_calls+1
     if refuse_owner then return false end
     b.assigned_unit_id=u and u.id or -1
     if fail_owner then error('owner fixture exception') end
     return true
    end
    """)
    def zone_revision():
        return call(9, {"kind": 1, "id": 6})["areas"][1]["revision"]
    owner_request = {"kind": 1, "id": 6, "owner_id": 22, "active": 0, "expected_revision": zone_revision()}
    for bad in [{"expected_revision": 0}, {"expected_revision": 1}, {"owner_id": 99},
                {"owner_id": -3}, {"active": 2}, {"bins": 1}, {"links_only": 0}]:
        assert not call(11, dict(owner_request, **bad))["ok"]
    assert lua.eval("owner_calls") == 0 and lua.eval("zone.spec_sub_flag.active")
    lua.execute("zone.type=2")
    assert call(11, dict(owner_request, expected_revision=zone_revision()))["message"] == "This zone type has no single owner"
    lua.execute("zone.type=0")
    owner_budget = lua.globals().request(11, lua.table_from(owner_request))
    owner_budget["step_budget"] = 0
    owned = adapter(owner_budget)
    assert owned["ok"] and owned["steps"] == 17 and owned["work_unknown"] and owned["areas"][1]["owner_id"] == 22
    assert not owned["areas"][1]["active"] and lua.eval("owner_calls") == 1
    assert not call(11, owner_request)["ok"]
    # Large owner/spouse vectors do not cause timing-only refusals.
    lua.execute("local v=df.unit.find(23).owned_buildings;for i=1,200000 do v[i]=zone end")
    large_owner = call(11, {"kind": 1, "id": 6, "owner_id": 20, "active": 0, "expected_revision": zone_revision()})
    assert large_owner["ok"] and large_owner["work_unknown"]
    assert lua.eval("owner_calls") == 2 and not lua.eval("zone.spec_sub_flag.active")
    lua.execute("df.unit.find(23).owned_buildings={};refuse_owner=true")
    assert call(11, {"kind": 1, "id": 6, "owner_id": -1, "active": 1,
                     "expected_revision": zone_revision()})["message"] == "Native owner assignment failed"
    assert not lua.eval("zone.spec_sub_flag.active")
    lua.execute("refuse_owner=false;fail_owner=true")
    uncertain = call(11, {"kind": 1, "id": 6, "owner_id": -1, "active": 1, "expected_revision": zone_revision()})
    assert not uncertain["ok"] and uncertain["steps"] == 15 and uncertain["work_unknown"]
    assert uncertain["message"] == "Native owner assignment failed; inspect before retrying"
    lua.execute("fail_owner=false")
    active_only = call(11, {"kind": 1, "id": 6, "active": 1, "expected_revision": zone_revision()})
    assert active_only["ok"] and active_only["steps"] == 16 and active_only["areas"][1]["active"]
    lua.execute("""
    local function clone(value)
     if type(value)~='table' then return value end
     local out={};for key,v in pairs(value)do out[key]=clone(v) end;return out
    end
    overlaps={};df.global.world.buildings.all={}
    local prior_find=df.building.find
    df.building.find=function(id)return overlaps[id] or prior_find(id) end
    for i=65,1,-1 do
     local b=clone(zone);b.id=1000+i;b.room={};b.assigned_unit_id=-1;b.location_id=-1
     overlaps[b.id]=b;table.insert(df.global.world.buildings.all,b)
    end
    local hole=clone(zone);hole.id=2001;hole.room={x=0,y=0,width=1,height=1,extents={[0]=0}}
    local other_z=clone(zone);other_z.id=2002;other_z.z=2
    table.insert(df.global.world.buildings.all,hole);table.insert(df.global.world.buildings.all,other_z)
    table.insert(df.global.world.buildings.all,{id=2003,kind=2})
    """)
    tile = {"x": 0, "y": 0, "z": 1}
    overlaps = call(8, tile)
    assert overlaps["ok"] and len(overlaps["areas"]) == 64 and overlaps["next_cursor"] == 1065
    assert [v["id"] for v in overlaps["areas"].values()] == list(range(1001, 1065))
    assert all(v["revision"] == 0 for v in overlaps["areas"].values())
    last_overlap = call(8, dict(tile, cursor=1065))
    assert len(last_overlap["areas"]) == 1 and last_overlap["areas"][1]["id"] == 1065
    assert last_overlap["next_cursor"] == 0 and not last_overlap["truncated"]
    # Every building visit counts, including unrelated objects and cursor skips.
    lua.execute("df.global.world.buildings.all={};for i=1,1526 do table.insert(df.global.world.buildings.all,{id=i,kind=2}) end")
    exact_visits = call(8, dict(tile, cursor=9999))
    assert exact_visits["ok"] and exact_visits["steps"] == 1536 and len(exact_visits["areas"]) == 0
    lua.execute("table.insert(df.global.world.buildings.all,{id=1527,kind=2})")
    too_many = call(8, tile)
    assert not too_many["ok"] and too_many["message"] == "Too many areas at this tile for one inspection"
    assert too_many["steps"] == 1536 and too_many["areas"] is None
    lua.execute("df.global.world.buildings.all={overlaps[1002],overlaps[1001]}")
    no_sort_budget = lua.globals().request(8, lua.table_from(tile))
    no_sort_budget["step_budget"] = 12
    assert adapter(no_sort_budget)["message"] == "Too many areas at this tile for one inspection"
    # Extent-less zones remain matches; page at the aggregate extent cap.
    lua.execute("""
    overlaps[1001].x2=127;overlaps[1001].y2=255
    df.global.world.buildings.all={overlaps[1002],overlaps[1001]}
    """)
    full_extent = call(8, tile)
    assert full_extent["ok"] and len(full_extent["areas"]) == 1
    assert len(full_extent["areas"][1]["extents"]) == 32768 and full_extent["next_cursor"] == 1002
    lua.execute("dfhack.maps.getTileFlags=function()return {hidden=true} end")
    assert call(8, tile)["message"] == "Tile is hidden or outside the map"
    lua.execute("""
    dfhack.maps.getTileFlags=function()return {hidden=false} end
    zone.type=6;df.civzone_type[6]='Barracks';zone.squad_room_info={}
    squad_fixture={id=20,entity_id=7,rooms={}}
    df.squad={find=function(id)if id==20 then return squad_fixture end end}
    squad_calls=0
    local previous_request=request
    function request(action,extra)
     local r=previous_request(action,extra)
     r.squad_use=function(b,s,use,budget)
      squad_calls=squad_calls+1;assert(b==zone and s==squad_fixture)
      if budget<13 then return {ok=false,message='squad budget',steps=1} end
      if refuse_squad then return {ok=false,message='native squad refusal',steps=13} end
      if use==0 then
       local retired={};if #b.squad_room_info>0 then retired={b.squad_room_info[1],s.rooms[1]} end
       b.squad_room_info={};s.rooms={};return {ok=true,steps=13,retired=retired}
      end
      b.squad_room_info={{squad_id=s.id,mode={whole=use}}};s.rooms={{building_id=b.id,mode={whole=use}}}
      if fail_squad then error('squad fixture exception') end
      return {ok=true,steps=13}
     end
     return r
    end
    """)
    squad_request = {"operation": 12, "kind": 1, "id": 6, "squad_id": 20, "squad_use": 15,
                     "expected_revision": zone_revision()}
    for use in [1, 2, 4, 8, 15]:
        squad_request.update(squad_use=use, expected_revision=zone_revision())
        changed = call(11, squad_request)
        assert changed["ok"] and changed["steps"] == 28 and changed["building_id"] == 6
        assert lua.eval("zone.squad_room_info[1].mode.whole") == use
        assert lua.eval("squad_fixture.rooms[1].mode.whole") == use
    calls = lua.eval("squad_calls")
    for bad in [{"expected_revision": 0}, {"expected_revision": 1}, {"squad_id": 999},
                {"squad_use": -1}, {"squad_use": 16}, {"squad_use": 1.5}]:
        assert not call(11, dict(squad_request, **bad))["ok"]
    assert lua.eval("squad_calls") == calls
    lua.execute("zone.type=3")
    squad_request["expected_revision"] = zone_revision()
    assert call(11, squad_request)["message"] == "This operation does not apply to this zone type"
    squad_request["squad_use"] = 2
    assert call(11, squad_request)["ok"]
    squad_request.update(squad_use=0, expected_revision=zone_revision())
    no_retire = lua.globals().request(11, lua.table_from(squad_request))
    no_retire["area_retire_capacity"] = 1
    assert adapter(no_retire)["message"] == "Area retire capacity reached; restart DF3D bridge"
    assert lua.eval("#zone.squad_room_info") == 1
    no_retire["area_retire_capacity"] = 2
    no_retire["step_budget"] = 179
    assert not adapter(no_retire)["ok"] and lua.eval("#zone.squad_room_info") == 1
    no_retire["step_budget"] = 180
    removed = adapter(no_retire)
    assert removed["ok"] and len(removed["retired"]) == 2
    assert removed["retired"][1]["squad_id"] == 20 and removed["retired"][2]["building_id"] == 6
    assert lua.eval("#zone.squad_room_info") == 0 and lua.eval("#squad_fixture.rooms") == 0
    lua.execute("zone.type=2")
    assert not call(11, dict(squad_request, expected_revision=zone_revision()))["ok"]
    lua.execute("zone.type=6;squad_fixture.entity_id=99")
    assert call(11, dict(squad_request, expected_revision=zone_revision()))["message"] == "Squad no longer exists"
    lua.execute("squad_fixture.entity_id=7;refuse_squad=true")
    assert call(11, dict(squad_request, expected_revision=zone_revision()))["message"] == "native squad refusal"
    lua.execute("refuse_squad=false;fail_squad=true")
    uncertain = call(11, dict(squad_request, squad_use=2, expected_revision=zone_revision()))
    assert not uncertain["ok"] and uncertain["steps"] == 1536 and "inspect before retrying" in uncertain["message"]
    lua.execute("""
    zone.type=2;zone.assigned_units={};assign_calls=0
    local previous_request=request
    function request(action,extra)
     local r=previous_request(action,extra)
     r.assign_unit=function(b,u,assign,budget)
      assign_calls=assign_calls+1;assert(b==zone and u.id==20)
      if budget<17 then return {ok=false,message='assignment budget',steps=1} end
      if refuse_assign then return {ok=false,message='cage limit',steps=17} end
      b.assigned_units=assign==1 and {u.id} or {}
      if fail_assign then error('assignment fixture exception') end
      return {ok=true,steps=17,retired={{building_id=6}}}
     end
     return r
    end
    """)
    animal_request = {"operation": 11, "kind": 1, "id": 6, "unit_id": 20, "assign": 1,
                      "expected_revision": zone_revision()}
    no_capacity = lua.globals().request(11, lua.table_from(animal_request))
    no_capacity["area_retire_capacity"] = 0
    assert adapter(no_capacity)["message"] == "Area retire capacity reached; restart DF3D bridge"
    assert lua.eval("assign_calls") == 0
    for bad in [{"expected_revision": 0}, {"expected_revision": 1}, {"unit_id": 999},
                {"unit_id": -1}, {"assign": -1}, {"assign": 2}, {"assign": 0.5}]:
        assert not call(11, dict(animal_request, **bad))["ok"]
    assert lua.eval("assign_calls") == 0
    no_capacity["area_retire_capacity"] = 1
    no_capacity["step_budget"] = 183
    assert not adapter(no_capacity)["ok"] and lua.eval("#zone.assigned_units") == 0
    no_capacity["step_budget"] = 184
    assigned = adapter(no_capacity)
    assert assigned["ok"] and assigned["steps"] == 32 and assigned["areas"][1]["assigned_count"] == 1
    assert assigned["retired"][1]["building_id"] == 6
    assert not call(11, animal_request)["ok"]
    unassigned = call(11, dict(animal_request, assign=0, expected_revision=zone_revision()))
    assert unassigned["ok"] and unassigned["areas"][1]["assigned_count"] == 0
    lua.execute("zone.type=6")
    assert call(11, dict(animal_request, expected_revision=zone_revision()))["message"] == "This operation does not apply to this zone type"
    lua.execute("zone.type=7;df.civzone_type[7]='Pen'")
    assert call(11, dict(animal_request, expected_revision=zone_revision()))["ok"]
    lua.execute("refuse_assign=true")
    assert call(11, dict(animal_request, assign=0, expected_revision=zone_revision()))["message"] == "cage limit"
    assert lua.eval("#zone.assigned_units") == 1
    lua.execute("refuse_assign=false;fail_assign=true")
    unknown = call(11, dict(animal_request, assign=0, expected_revision=zone_revision()))
    assert not unknown["ok"] and unknown["steps"] == 1536 and "inspect before retrying" in unknown["message"]
    # Settings label jobs use kind5 and share the cache/scheduler with kind7.
    # Raw objects below are synthetic; native caption/effect acceptance is D.
    lua.execute(r"""
    df.global.world.raws={plants={all={}},creatures={all={}},itemdefs={},
      descriptors={colors={}},inorganics={all={}},mat_table={organic_types={},organic_indexes={},builtin={}}}
    settings_fields={};settings_raw_count=0
    function settings_layout(b,budget)
     budget=budget or math.huge
     if budget<108 then return {ok=false,message='Settings layout exceeds remaining step budget',steps=0} end
     if settings_raw_count>65536 then return {ok=false,message='Stockpile settings exceed 65,536 entries',steps=108} end
     return {ok=true,steps=108,raw_count=settings_raw_count,fields=settings_fields}
    end
    for i=1,5000 do df.global.world.raws.plants.all[i]={name_plural=('Tree %05d'):format(5001-i),flags={TREE=true}} end
    settings_fields['wood.mats']={count=5000,stored_count=5000,fixed=false}
    pile.settings.wood.mats={};for i=1,5000 do pile.settings.wood.mats[i]=0 end
    pile.settings.wood.mats[5000]=1
    """)
    settings_adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    def setting_request(key="wood", **extra):
        return lua.globals().request(9, lua.table_from({"operation": 1, "list_key": key, **extra}))
    def setting_page(key="wood", **extra):
        result = settings_adapter(setting_request(key, **extra))
        phases = set()
        for _ in range(30000):
            if not result["ok"] or not result["build_phase"]:
                return result, phases
            phases.add(result["build_phase"])
            step = settings_adapter(lua.table_from({"step": 64, "builder_kind": 5, "epoch": 1}))
            assert 0 <= step["steps"] <= 64 and step["active_kinds"] in (0, 32)
            result = settings_adapter(setting_request(key, **extra))
        raise AssertionError("settings builder did not finish")
    queued = settings_adapter(setting_request())
    assert queued["ok"] and queued["build_phase"] == 1 and queued["build_done"] == 0 and queued["build_total"] == 5000
    assert queued["active_kinds"] == 32 and queued["steps"] == 121 and len(queued["settings"]) == 0
    for builder in [6, 7]:
        step = settings_adapter(lua.table_from({"step": 2048, "builder_kind": builder, "epoch": 1}))
        assert step["steps"] == 0 and step["active_kinds"] == 32
    first, phases = setting_page()
    assert first["ok"] and phases == {1, 2, 3} and len(first["settings"]) == 128
    assert first["settings"][1]["label"] == "Tree 00001" and first["settings"][1]["index"] == 4999
    assert first["settings"][1]["key"] == "wood/4999" and first["settings"][1]["state"] == 2
    assert not first["settings"][1]["estimated"] and first["next_cursor"] == 128
    receipt = first["list_revision"]
    assert isinstance(receipt, int) and 0 < receipt <= 2**63-1
    second, _ = setting_page(cursor=128, expected_list_revision=receipt)
    assert second["settings"][1]["index"] == 4871 and second["next_cursor"] == 256
    assert not setting_page(expected_list_revision=receipt ^ 1)[0]["ok"]
    lua.execute("pile.settings.wood.mats[5000]=0")
    refreshed, _ = setting_page(expected_list_revision=receipt)
    assert refreshed["settings"][1]["state"] == 1 and refreshed["list_revision"] == receipt
    matched, _ = setting_page(query="TREE 00001")
    assert len(matched["settings"]) == 1 and matched["settings"][1]["index"] == 4999
    assert matched["query"] == "TREE 00001" and matched["list_revision"] == receipt
    small_budget = setting_request(expected_list_revision=receipt)
    small_budget["step_budget"] = 0
    page = settings_adapter(small_budget)
    assert page["ok"] and len(page["settings"]) == 128 and page["next_cursor"] == 128
    assert len(setting_page(cursor=5000, expected_list_revision=receipt)[0]["settings"]) == 0
    assert setting_page(cursor=-1)[0]["message"] == "invalid area cursor"
    # Raw count changes invalidate receipts; a queued source changing length
    # fails and is evicted, permitting an explicit fresh request.
    lua.execute("settings_fields['wood.mats'].count=5001")
    assert setting_page(expected_list_revision=receipt)[0]["message"] == "List changed; refresh"
    result, _ = setting_page()
    assert result["message"] == "List changed; refresh"
    lua.execute("settings_fields['wood.mats'].count=5000")
    assert setting_page()[0]["ok"]
    # Duplicate captions retain independent indices; blank captions are omitted
    # while ineligible plant raws do not count as missing captions.
    lua.execute(r"""
    df.global.world.raws.plants.all={{name_plural='Same',flags={TREE=true}},
      {name_plural='Same',flags={TREE=true}},{name_plural='',flags={TREE=true}},
      {name_plural='Shrub',flags={TREE=false}}}
    settings_fields['wood.mats'].count=4
    """)
    duplicates, _ = setting_page()
    assert duplicates["ok"] and duplicates["omitted"] == 1 and len(duplicates["settings"]) == 2
    assert [r["index"] for r in duplicates["settings"].values()] == [0, 1]
    assert [r["key"] for r in duplicates["settings"].values()] == ["wood/0", "wood/1"]
    # Reset the helper cache, as helpers.reset() does, for malformed caption.
    lua.execute("df.global.world.raws.plants.all[1].name_plural=string.rep('x',513)")
    settings_adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    assert setting_page()[0]["message"] == "Area setting label exceeds 512 bytes"
    lua.execute("df.global.world.raws.plants.all[1].name_plural='Repaired'")
    assert setting_page()[0]["ok"]
    lua.execute(r"""
    local raws=df.global.world.raws
    df.item_quality={[0]='Ordinary',[1]='WellCrafted',[2]='FinelyCrafted',[3]='Superior',[4]='Exceptional',[5]='Masterful',[6]='Artifact'}
    df.organic_mat_category={Meat=0,Fish=1,Eggs=3,Silk=4,Paper=5}
    df.item_type={_last_item=3,[0]='BAR',[1]='CHAIN',[2]='BOOK',[3]='BOULDER',attrs={
      [0]={caption='bars'},[1]={caption='chains'},[2]={caption='books'},[3]={caption='boulders'}}}
    df.furniture_type={_last_item=1,[0]='ANVIL',[1]='UNCAPTURED_TOOL'}
    df.builtin_mats={[0]='INORGANIC',[1]='OTHER',[2]='OTHER',[3]='GLASS_GREEN',[4]='GLASS_CLEAR',[5]='GLASS_CRYSTAL'}
    raws.mat_table.builtin=setmetatable({}, {__len=function()return 6 end}) -- null slots must not crash glass filtering
    dfhack.matinfo={decode=function(t,i)
      return {toString=function()return t==0 and ('Inorganic '..i) or i==-1 and ('Glass '..t) or ('Organic '..i) end}
    end}
    function make_setting(field,count,values)
     local cat,key=field:match('^([^%.]+)%.(.+)$')
     pile.settings[cat]=pile.settings[cat] or {};pile.settings[cat][key]=values or {}
     settings_fields[field]={count=count,stored_count=values and #values or 0,fixed=false}
    end
    raws.inorganics.all={
      {flags={},material={gem_name2='native irregular plural',flags={IS_GEM=true,IS_METAL=true,IS_STONE=true}}},
      {flags={},material={flags={IS_METAL=true,IS_STONE=true}}},
      {flags={},material={flags={IS_STONE=true}}},
      {flags={},material={flags={}}}}
    make_setting('finished_goods.mats',4,{1,0,1,0})
    make_setting('coins.mats',4,{0,1,0,1})
    make_setting('gems.cut_mats',4,{1,1,1,1})
    make_setting('gems.rough_mats',4,{1,0,0,0})
    make_setting('gems.rough_other_mats',6,{0,0,0,1,0,1})
    make_setting('armor.quality_core',7,{false,true,false,true,false,true,false})
    make_setting('armor.color',2,{1,0});raws.descriptors.colors={{name='Red'},{name='Blue'}}
    make_setting('armor.body',2,{0,1});raws.itemdefs.armor={{name_plural='coats',adjective='bulky'},{name_plural='coats',adjective=''}}
    make_setting('ammo.other_mats',2,{1,0})
    make_setting('finished_goods.type',4,{1,0,1,1})
    make_setting('refuse.type',4,{1,1,1,1})
    make_setting('furniture.type',2,{1,1})
    raws.creatures.all={{creature_id='BIRD',name={[0]='bird',[1]='birds'},flags={},caste={{caste_name={[0]='bird hen'}}}},
      {creature_id='GENERATED',name={[0]='generated',[1]='generated'},flags={GENERATED=true}},
      {creature_id='EQUIPMENT_WAGON',name={[0]='wagon',[1]='wagons'},flags={}}}
    make_setting('corpses.corpses',3,{1,1,1})
    raws.mat_table.organic_types[0]={9,9};raws.mat_table.organic_indexes[0]={6,7}
    raws.mat_table.organic_types[1]={0};raws.mat_table.organic_indexes[1]={0}
    make_setting('food.meat',2,{1,0});make_setting('food.fish',1,{1})
    raws.mat_table.organic_types[4]={9};raws.mat_table.organic_indexes[4]={6}
    raws.mat_table.organic_types[5]={9};raws.mat_table.organic_indexes[5]={7}
    make_setting('cloth.thread_silk',1,{1});make_setting('sheet.paper',1,{0})
    """)
    def setting_indices(key):
        result, _ = setting_page(key)
        assert result["ok"], result["message"]
        return [r["index"] for r in result["settings"].values()]
    assert setting_indices("finished_goods/gem") == [0]
    assert setting_indices("finished_goods/metal") == [1]
    assert setting_indices("finished_goods/stone") == [2]
    assert setting_indices("coins") == [0, 1, 2, 3]
    assert setting_indices("gems/cut_gem") == [0] and setting_indices("gems/cut_stone") == [1, 2]
    assert setting_page("gems/rough_gem")[0]["settings"][1]["label"] == "native irregular plural"
    lua.execute("df.global.world.raws.inorganics.all[1].material.gem_name1='alexandrite';df.global.world.raws.inorganics.all[1].material.gem_name2='STP'")
    regular_gem, _ = setting_page("gems/rough_gem", query="alexandrite")
    assert regular_gem["settings"][1]["label"] == "alexandrites"
    assert setting_page("cloth/thread_silk")[0]["settings"][1]["label"] == "Organic 6 thread"
    assert setting_page("sheet/paper")[0]["settings"][1]["label"] == "Organic 7 sheet"
    assert setting_indices("gems/rough_glass") == [3, 4, 5]
    qualities, _ = setting_page("armor/quality_core")
    assert len(qualities["settings"]) == 7
    assert [r["label"] for r in qualities["settings"].values()] == ["Standard", "Well-crafted", "Finely-crafted", "Superior quality", "Exceptional", "Masterwork", "Artifact"]
    assert [r["index"] for r in qualities["settings"].values()] == list(range(7))
    assert {r["index"]: r["state"] for r in qualities["settings"].values()} == {i: 2 if i % 2 else 1 for i in range(7)}
    assert setting_indices("armor/color") == [1, 0]
    assert [r["label"] for r in setting_page("armor/body")[0]["settings"].values()] == ["bulky coats", "coats"]
    assert setting_indices("ammo/other_materials") == [1, 0]
    assert [r["label"] for r in setting_page("ammo/other_materials")[0]["settings"].values()] == ["Bone", "Wood"]
    assert setting_indices("finished_goods/type") == [1, 2]
    refuse_page, _ = setting_page("refuse/type")
    assert [r["label"] for r in refuse_page["settings"].values()] == ["chains", "codices", "Fresh raw hide", "Rotten raw hide"]
    assert [r["label"] for r in setting_page("finished_goods/type")[0]["settings"].values()] == ["chains", "codices"]
    furniture, _ = setting_page("furniture/type")
    assert furniture["omitted"] == 0 and furniture["settings"][1]["label"] == "Anvils"
    assert furniture["settings"][2]["label"] == "UNCAPTURED_TOOL"  # unknown future enum fallback
    lua.execute("df.item_type[2]='INSTRUMENT';df.furniture_type[1]='CHAIR'")
    settings_adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    assert [r["label"] for r in setting_page("finished_goods/type")[0]["settings"].values()] == ["chains", "musical instruments"]
    assert [r["label"] for r in setting_page("furniture/type")[0]["settings"].values()] == ["Anvils", "Thrones"]
    lua.execute("df.item_type[2]='BOOK';df.furniture_type[1]='UNCAPTURED_TOOL'")
    settings_adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    assert setting_indices("corpses") == [0]
    assert [r["label"] for r in setting_page("food/meat")[0]["settings"].values()] == ["Organic 6", "Organic 7"]
    assert setting_page("food/fish")[0]["settings"][1]["label"] == "bird hen"
    lua.execute(r"""
    local values=df.global.world.raws.inorganics.all
    for i=1,6 do values[i]={flags={},material={flags={IS_STONE=true}},metal_ore={mat_index={}},economic_uses={}} end
    values[1].metal_ore.mat_index={1};values[1].economic_uses={1};values[1].flags.SOIL=true
    values[2].economic_uses={1};values[2].flags.SOIL=true
    values[3].flags.SOIL=true
    values[5].material.flags.NO_STONE_STOCKPILE=true
    values[6].material.flags.IS_STONE=false;values[6].flags.SOIL=true;values[6].flags.AQUIFER=true
    make_setting('stone.mats',6,{1,1,1,1,1,1})
    """)
    assert setting_indices("stone/metal_ores") == [0]
    assert setting_indices("stone/economic") == [1]
    assert setting_indices("stone/clay") == [2]
    assert setting_indices("stone/other_stone") == [3]
    # Epoch replacement drops label jobs, as do successful DF3D mutations.
    settings_adapter(lua.table_from({"step": 0, "builder_kind": 5, "epoch": 2}))
    assert not setting_page("wood", expected_list_revision=receipt)[0]["ok"]
    observed, _ = setting_page("wood")
    current = settings_adapter(lua.globals().request(9, lua.table_from({})))
    changed = settings_adapter(lua.globals().request(11, lua.table_from({"operation": 13, "organic": 0,
                               "expected_revision": current["areas"][1]["revision"]})))
    assert changed["ok"] and not setting_page("wood", expected_list_revision=observed["list_revision"])[0]["ok"]
    queued = settings_adapter(setting_request("wood", query="unique pending query"))
    assert queued["active_kinds"] == 32
    candidates = settings_adapter(lua.globals().request(14, lua.table_from({"kind": 1})))
    assert candidates["active_kinds"] == 160
    step = settings_adapter(lua.table_from({"step": 1, "builder_kind": 5, "epoch": 1}))
    assert step["steps"] == 1 and step["active_kinds"] == 160
    # Give the summary fixture the complete private native field inventory.
    # Counts and raw data remain synthetic and independent of stored settings.
    management_source = (Path(__file__).resolve().parents[1] / "bridge/plugin/management.cpp").read_text()
    vector_source = management_source.split("auto areaSettingVectors(", 1)[1].split("struct AreaFixedSetting", 1)[0]
    fixed_source = management_source.split("auto areaFixedSettings(", 1)[1].split("// Counts refer", 1)[0]
    vector_keys = re.findall(r'\{"([^"]+)",&pile->settings', vector_source)
    fixed_keys = re.findall(r'\{"([^"]+)",', fixed_source)
    assert len(vector_keys) == 78 and len(fixed_keys) == 29
    # Swapping old buffers out is equivalent to native SET only because the
    # pinned serializer clears every active vector before importing. Guard that
    # assumption against dependency drift; food uses its category map to clear.
    serializer = (Path(__file__).resolve().parents[1] / "external/dfhack/plugins/stockpiles/StockpileSerializer.cpp").read_text()
    aliases = dict(re.findall(r'auto\s*&\s*(\w+)\s*=\s*mSettings->(\w+)', serializer))
    cleared = {f"{aliases[alias]}.{field}" for alias, field in re.findall(r'(\w+)\.(\w+)\.clear\(\)', serializer) if alias in aliases}
    cleared.update(re.findall(r'&mSettings->(food\.\w+)', serializer))
    assert cleared == set(vector_keys) - {"ore.mats"}
    lua.globals().fixture_vector_keys = lua.table_from(vector_keys)
    lua.globals().fixture_fixed_keys = lua.table_from(fixed_keys)
    lua.execute(r"""
    df.global.cur_year=0;df.global.cur_year_tick=100
    local raws={plants={all={}},creatures={all={}},itemdefs={},descriptors={colors={}},inorganics={all={}},
      mat_table={organic_types={},organic_indexes={},builtin=setmetatable({}, {__len=function()return 6 end})}}
    df.global.world.raws=raws
    for _,name in ipairs{'ammo','armor','helms','shoes','gloves','pants','shields','weapons','trapcomps'} do raws.itemdefs[name]={} end
    for index,name in ipairs{'Meat','Fish','UnpreparedFish','Eggs','Plants','PlantDrink','CreatureDrink','PlantCheese',
      'CreatureCheese','Seed','PlantGrowth','PlantPowder','CreaturePowder','Glob','Paste','Pressed','PlantLiquid',
      'CreatureLiquid','MiscLiquid','Silk','PlantFiber','Yarn','MetalThread','Leather','Paper','Parchment'} do
      df.organic_mat_category[name]=index;raws.mat_table.organic_types[index]={};raws.mat_table.organic_indexes[index]={}
    end
    settings_fields={};settings_raw_count=0;fixture_raw_revision=300
    local sizes={['ammo.other_mats']=2,['armor.other_mats']=10,['weapons.other_mats']=10,
      ['bars_blocks.bars_other_mats']=5,['bars_blocks.blocks_other_mats']=4,
      ['furniture.other_mats']=15,['finished_goods.other_mats']=16,
      ['gems.rough_other_mats']=6,['gems.cut_other_mats']=6,['finished_goods.type']=4,['refuse.type']=4,['furniture.type']=2}
    for _,key in ipairs(fixture_vector_keys) do
      local count=sizes[key] or 0;local values={};for i=1,count do values[i]=0 end
      make_setting(key,count,values)
    end
    for _,key in ipairs(fixture_fixed_keys) do
      local cat,field=key:match('^([^%.]+)%.(.+)$')
      if field:find('quality',1,true) then
       make_setting(key,7,{false,false,false,false,false,false,false});settings_fields[key].fixed=true
      else pile.settings[cat][field]=false;settings_fields[key]={count=1,stored_count=1,fixed=true} end
    end
    for _,cat in ipairs{'animals','food','furniture','corpses','refuse','stone','ammo','coins',
      'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}do pile.settings.flags[cat]=true end
    pile.settings.misc.allow_organic=true
    raws.plants.all={{name_plural='Oak trees',flags={TREE=true}},{name_plural='Pine trees',flags={TREE=true}},
      {name_plural='Shrubs',flags={TREE=false}}};make_setting('wood.mats',3,{1,0,1})
    local meat=df.organic_mat_category.Meat
    raws.mat_table.organic_types[meat]={9,9};raws.mat_table.organic_indexes[meat]={1,2};make_setting('food.meat',2,{1,0})
    local previous_layout=settings_layout
    function settings_layout(b,budget)
     budget=budget or math.huge
      local result=previous_layout(b,budget);result.raw_revision=fixture_raw_revision;return result
    end
    """)
    settings_adapter = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/areas.lua").read_text())
    summary_step_counts = []
    def summary_page(key="", **extra):
        result = settings_adapter(setting_request(key, **extra))
        phases = set()
        for _ in range(3000):
            if not result["ok"] or not result["build_phase"]:
                return result, phases
            phases.add(result["build_phase"])
            step = settings_adapter(lua.table_from({"step": 64, "builder_kind": 6, "epoch": 1}))
            summary_step_counts.append(step["steps"])
            assert 0 <= step["steps"] <= 64 and step["active_kinds"] in (0, 64)
            result = settings_adapter(setting_request(key, **extra))
        raise AssertionError("summary builder did not finish")
    initial = settings_adapter(setting_request(""))
    assert initial["ok"] and initial["active_kinds"] == 0 and initial["build_phase"] == 0
    root, phases = summary_page()
    assert root["ok"] and phases == set() and len(root["settings"]) == 19
    assert initial["steps"] > 244  # Includes the complete native summary scan.
    assert [r["key"] for r in root["settings"].values()] == ["ammo", "animals", "armor", "bars_blocks", "cloth",
        "coins", "finished_goods", "food", "furniture", "gems", "leather", "corpses", "refuse", "sheet", "stone", "weapons", "wood", "organic", "inorganic"]
    root_rows = {r["key"]: r for r in root["settings"].values()}
    assert root_rows["wood"]["state"] == 3 and root_rows["food"]["state"] == 3
    assert root_rows["armor"]["state"] == 1  # enabled flag with every leaf off
    assert root_rows["organic"]["state"] == 2 and not root_rows["organic"]["estimated"]
    assert all(not r["estimated"] and "DF3D estimate" not in r["label"] for r in root["settings"].values())
    food, _ = summary_page("food", query="unmatched search")
    assert [r["key"] for r in food["settings"].values()] == ["food/prepared_meals", "food/meat"]
    assert food["settings"][2]["state"] == 3 and food["settings"][1]["kind"] == 3
    assert food["query"] == "unmatched search" and food["captured_tick"] == root["captured_tick"]
    assert [r["label"] for r in summary_page("ammo")[0]["settings"].values()] == ["Type", "Metal", "Other materials", "Core quality", "Total quality"]
    stone, _ = summary_page("stone")
    assert [r["key"] for r in stone["settings"].values()] == ["stone/metal_ores", "stone/economic", "stone/other_stone", "stone/clay"]
    # One summary backs every column; each page has its own receipt.
    assert food["list_revision"] != root["list_revision"]
    assert not summary_page("food", expected_list_revision=root["list_revision"])[0]["ok"]
    # Native leaf edits while paused must invalidate the old receipt immediately.
    # No simulation tick or DF3D mutation is needed to discover the changed state.
    paused_tick = lua.eval("df.global.cur_year_tick")
    lua.execute("pile.settings.wood.mats[2]=1")
    assert lua.eval("df.global.cur_year_tick") == paused_tick
    assert summary_page(expected_list_revision=root["list_revision"])[0]["message"] == "List changed; refresh"
    refreshed, _ = summary_page()
    assert {r["key"]: r["state"] for r in refreshed["settings"].values()}["wood"] == 2
    lua.execute("pile.settings.flags.wood=false")
    assert not summary_page(expected_list_revision=refreshed["list_revision"])[0]["ok"]
    disabled, _ = summary_page()
    assert {r["key"]: r["state"] for r in disabled["settings"].values()}["wood"] == 1
    lua.execute("fixture_raw_revision=301")
    assert not summary_page(expected_list_revision=disabled["list_revision"])[0]["ok"]
    assert summary_page("not-a-list")[0]["message"] == "Unknown stockpile settings list"
    # PM-approved serializer names cover uncaptured middle-column captions.
    lua.execute(r"""
    local cat=df.organic_mat_category.PlantCheese
    df.global.world.raws.mat_table.organic_types[cat]={9};df.global.world.raws.mat_table.organic_indexes[cat]={9}
    make_setting('food.cheese_plant',1,{1});fixture_raw_revision=302
    """)
    missing_caption, _ = summary_page("food")
    assert missing_caption["ok"] and missing_caption["omitted"] == 0
    assert {r["key"]: r["label"] for r in missing_caption["settings"].values()}["food/cheese_plant"] == "cheese/plant"
    # A shared backing raw belongs to exactly its first matching partition.
    lua.execute(r"""
    df.global.world.raws.inorganics.all={{flags={},material={flags={IS_GEM=true,IS_METAL=true,IS_STONE=true}},
      metal_ore={mat_index={1}},economic_uses={1}}}
    for _,field in ipairs{'ammo.mats','armor.mats','bars_blocks.bars_mats','bars_blocks.blocks_mats','coins.mats',
      'finished_goods.mats','furniture.mats','gems.rough_mats','gems.cut_mats','stone.mats','weapons.mats'} do make_setting(field,1,{1}) end
    fixture_raw_revision=303
    """)
    partitioned, _ = summary_page("finished_goods")
    states = {r["key"]: r["state"] for r in partitioned["settings"].values()}
    assert states["finished_goods/gem"] == 2 and states["finished_goods/metal"] == 1 and states["finished_goods/stone"] == 1
    # Inconsistent native layout fails; the next repaired read is independent.
    lua.execute("fixture_raw_revision=304;settings_fields['ammo.mats'].count=2")
    assert summary_page()[0]["message"] == "List changed; refresh"
    lua.execute("settings_fields['ammo.mats'].count=1")
    repaired, _ = summary_page()
    assert repaired["ok"]
    lua.execute("df.global.cur_year_tick=1")
    assert summary_page(expected_list_revision=repaired["list_revision"])[0]["ok"]
    # Fixed SettingsSet writes do not depend on a warmed list cache. Exercise
    # real producer validation/dispatch with a stand-in for the native fill;
    # native fixed-array and scalar memory semantics are covered by core tests.
    lua.execute(r"""
    fixed_fill_calls=0
    function settings_fill(b,field,members,allowed,enabled,budget)
     fixed_fill_calls=fixed_fill_calls+1
     assert(#members==#allowed and (#members==1 or #members==7))
     if budget<2 then return {ok=false,message='fill budget',steps=1} end
     if refuse_fill then return {ok=false,message='fill refused',steps=1} end
     if invalid_fill_accounting then return {ok=true,steps=budget+1} end
     local cat,key=field:match('^([^%.]+)%.(.+)$')
     for i=1,#members do
      if members:byte(i)~=0 and allowed:byte(i)~=0 then
       if #members==1 then b.settings[cat][key]=enabled
       else b.settings[cat][key][i]=enabled end
      end
     end
     if fail_after_fill then error('fixture lost native reply') end
     return {ok=true,steps=2}
    end
    pile.settings.armor.quality_core={false,true,false,true,false,true,false}
    pile.settings.armor.quality_total={true,true,true,true,true,true,true}
    pile.settings.flags.armor=false
    """)
    def fixed_edit(list_key, row_key=None, value=2, **extra):
        values = {"operation": 2, "list_key": list_key, "scope": 1 if row_key is not None else 2,
                  "value": value, "expected_revision": call(9)["areas"][1]["revision"], **extra}
        if row_key is not None:
            values["row_key"] = row_key
        request = lua.globals().request(11, lua.table_from(values))
        request["settings_fill"] = lua.globals().settings_fill
        return request
    def fill_count():
        return lua.globals().fixed_fill_calls
    # Exact reserve includes the maximum reply snapshot, even though this
    # fixture's snapshot is cheaper. Refusal happens before helper invocation.
    edit = fixed_edit("armor/quality_core", "armor/quality_core/2")
    edit["step_budget"] = 278
    assert not settings_adapter(edit)["ok"] and fill_count() == 0
    assert lua.eval("not pile.settings.armor.quality_core[3]")
    edit["step_budget"] = 279
    changed = settings_adapter(edit)
    assert changed["ok"] and changed["steps"] == 127 and fill_count() == 1, dict(changed)
    assert lua.eval("pile.settings.armor.quality_core[3] and not pile.settings.armor.quality_core[1] and pile.settings.armor.quality_core[2]")
    assert lua.eval("not pile.settings.flags.armor and pile.settings.armor.quality_total[1]")
    for row in ["armor/quality_core/-1", "armor/quality_core/7", "armor/quality_core/02",
                "armor/quality_core/2.0", "armor/quality_total/2", "armor/quality_core/2/0"]:
        before = fill_count()
        rejected = settings_adapter(fixed_edit("armor/quality_core", row))
        assert rejected["message"] == "Unknown stockpile settings row" and fill_count() == before
    assert settings_adapter(fixed_edit("armor/quality_core", value=1))["ok"]
    assert lua.eval("not pile.settings.armor.quality_core[1] and not pile.settings.armor.quality_core[3] and not pile.settings.armor.quality_core[7]")
    assert settings_adapter(fixed_edit("armor/quality_core", value=2))["ok"]
    assert lua.eval("pile.settings.armor.quality_core[1] and pile.settings.armor.quality_core[7] and not pile.settings.flags.armor")
    assert settings_adapter(fixed_edit("armor", "armor/quality_core", value=1))["ok"]
    assert lua.eval("not pile.settings.armor.quality_core[1] and not pile.settings.armor.quality_core[7] and pile.settings.armor.quality_total[1]")
    for category in ["ammo", "armor", "finished_goods", "furniture", "weapons"]:
        for quality in ["quality_core", "quality_total"]:
            assert settings_adapter(fixed_edit(f"{category}/{quality}", value=2))["ok"]
            assert lua.eval(f"pile.settings.{category}.{quality}[1] and pile.settings.{category}.{quality}[7]")
    assert settings_adapter(fixed_edit("food", "food/prepared_meals", value=1))["ok"]
    assert lua.eval("not pile.settings.food.prepared_meals")
    assert settings_adapter(fixed_edit("", "organic", value=1))["ok"]
    assert lua.eval("not pile.settings.misc.allow_organic")
    # Native Ammo middle-column actions reach the corresponding quality vector.
    assert settings_adapter(fixed_edit("ammo", "ammo/quality_core", value=1))["ok"]
    assert lua.eval("not pile.settings.ammo.quality_core[1] and not pile.settings.ammo.quality_core[7] and pile.settings.ammo.quality_total[1]")
    # Filtered All/None selects native caption matches, independent of paging.
    assert settings_adapter(fixed_edit("ammo/quality_core", value=1, query="CRAFTED"))["ok"]
    assert lua.eval("pile.settings.ammo.quality_core[1] == false and not pile.settings.ammo.quality_core[2] and not pile.settings.ammo.quality_core[3]")
    assert settings_adapter(fixed_edit("ammo/quality_core", value=2, query="CRAFTED"))["ok"]
    assert lua.eval("not pile.settings.ammo.quality_core[1] and pile.settings.ammo.quality_core[2] and pile.settings.ammo.quality_core[3] and not pile.settings.ammo.quality_core[4]")
    assert settings_adapter(fixed_edit("ammo/quality_core", value=1, query="no such grade"))["ok"]
    assert lua.eval("pile.settings.ammo.quality_core[2] and pile.settings.ammo.quality_core[3]")
    # A producer's larger post-write snapshot must be reserved before mutation.
    lua.execute(r"""
    snapshot_without_reserve=area_snapshot
    function area_snapshot(...)
     local result=snapshot_without_reserve(...);result.reply_steps=700;return result
    end
    """)
    reserved = fixed_edit("ammo/quality_core", value=1)
    reserved["step_budget"] = 800
    before = fill_count()
    assert settings_adapter(reserved)["message"] == "Area request exceeds remaining step budget"
    assert fill_count() == before and lua.eval("pile.settings.ammo.quality_core[2]")
    reserved["step_budget"] = 1000
    assert settings_adapter(reserved)["ok"] and fill_count() == before + 1
    lua.execute("area_snapshot=snapshot_without_reserve")
    # No cross-parent aliases or unknown list rows.
    before = fill_count()
    for key, row, scope in [("food", "armor/usable", 1), ("food/unknown", None, 3)]:
        result = settings_adapter(fixed_edit(key, row, scope=scope))
        assert result["message"] == "Unknown stockpile settings list or row"
    assert fill_count() == before
    before = fill_count()
    assert settings_adapter(fixed_edit("food", "food/prepared_meals", expected_revision=0))["message"] == "Area revision required; inspect again"
    assert settings_adapter(fixed_edit("food", "food/prepared_meals", expected_revision=1))["message"] == "Area changed; inspect again"
    assert fill_count() == before
    lua.execute("settings_fields['armor.quality_core'].count=6")
    assert settings_adapter(fixed_edit("armor/quality_core"))["message"] == "Stockpile settings layout changed"
    assert fill_count() == before
    lua.execute("settings_fields['armor.quality_core'].count=7;refuse_fill=true")
    rejected = settings_adapter(fixed_edit("food", "food/prepared_meals"))
    assert rejected["message"] == "fill refused" and lua.eval("not pile.settings.food.prepared_meals")
    lua.execute("refuse_fill=false;invalid_fill_accounting=true")
    rejected = settings_adapter(fixed_edit("food", "food/prepared_meals"))
    assert rejected["message"] == "Native area helper returned invalid work accounting" and rejected["steps"] == 1536
    lua.execute("invalid_fill_accounting=false;fail_after_fill=true")
    unknown = settings_adapter(fixed_edit("food", "food/prepared_meals"))
    assert not unknown["ok"] and unknown["steps"] == 1536 and "inspect before retrying" in unknown["message"]
    assert lua.eval("pile.settings.food.prepared_meals")
    lua.execute("fail_after_fill=false")
    observed, _ = summary_page("food")
    assert observed["build_phase"] == 0
    assert next(r for r in observed["settings"].values() if r["key"] == "food/prepared_meals")["state"] == 2
    # Classified masks carry bounded semantic selectors, not raw pointers or
    # cached captions. This stand-in checks dispatch and whole-operation budget;
    # native classification parity is a separate producer/live acceptance item.
    lua.execute(r"""
    local fixed_fill=settings_fill
    all_fill_calls={};fixture_partitions={['wood.mats']={1,1,0}}
    function settings_fill(b,field,members,allowed,enabled,budget)
     all_fill_calls[#all_fill_calls+1]=field
     if fail_fill_at and #all_fill_calls==fail_fill_at then return {ok=false,message='fixture later refusal',steps=1} end
     if type(members)=='string' and not settings_fields[field].fixed then
      local cat,key=field:match('^([^%.]+)%.(.+)$');local values=b.settings[cat][key]
      local resize=#values<#members
      for i=1,#members do
       if resize and allowed:byte(i)==0 then values[i]=1
       elseif members:byte(i)~=0 then values[i]=enabled and 1 or 0
       elseif values[i]==nil then values[i]=0 end
      end
      return {ok=true,steps=1+((#members+255)//256)}
     end
     if type(members)~='table' then return fixed_fill(b,field,members,allowed,enabled,budget) end
     assert(allowed=='' and settings_fields[field].fixed==false)
     assert(members.count==settings_fields[field].count)
     local count,selection,row=members.count,members.selection,members.row
     local cost=1+2*((count+255)//256)
     if budget<cost then return {ok=false,message='fill budget',steps=1} end
     local cat,key=field:match('^([^%.]+)%.(.+)$');local values=b.settings[cat][key]
     local parts=fixture_partitions[field] or {}
     local function member(i)
      local part=parts[i] or 1
      return part~=0 and (selection==0 or (part & selection)~=0) and (row<0 or row==i-1),part~=0
     end
     if row>=0 and (row>=count or not member(row+1)) then return {ok=false,message='Unknown stockpile settings row',steps=1+((count+255)//256)} end
     local resize=#values<count
     if resize then for i=#values+1,count do values[i]=0 end end
     for i=1,count do
      local selected,eligible=member(i)
      if resize and not eligible then values[i]=1
      elseif selected then values[i]=enabled and 1 or 0 end
     end
     return {ok=true,steps=cost,resized=resize}
    end
    pile.settings.wood.mats={0}
    """)
    rejected = settings_adapter(fixed_edit("wood", "wood/2"))
    assert rejected["message"] == "Unknown stockpile settings row"
    assert lua.eval("#pile.settings.wood.mats==1 and pile.settings.wood.mats[1]==0")
    assert settings_adapter(fixed_edit("wood", "wood/1"))["ok"]
    assert lua.eval("#pile.settings.wood.mats==3 and pile.settings.wood.mats[1]==0 and pile.settings.wood.mats[2]==1 and pile.settings.wood.mats[3]==1")
    lua.execute("pile.settings.wood.mats={1,1,0,9}")
    assert settings_adapter(fixed_edit("wood", value=1))["ok"]
    assert lua.eval("#pile.settings.wood.mats==4 and pile.settings.wood.mats[1]==0 and pile.settings.wood.mats[2]==0 and pile.settings.wood.mats[3]==0 and pile.settings.wood.mats[4]==9")
    lua.execute("make_setting('finished_goods.mats',3,{0,0,0,9});fixture_partitions['finished_goods.mats']={8,2,4}")
    assert settings_adapter(fixed_edit("finished_goods/metal"))["ok"]
    assert lua.eval("pile.settings.finished_goods.mats[1]==0 and pile.settings.finished_goods.mats[2]==1 and pile.settings.finished_goods.mats[3]==0 and pile.settings.finished_goods.mats[4]==9")
    assert settings_adapter(fixed_edit("finished_goods/gem", "finished_goods/gem/1"))["message"] == "Unknown stockpile settings row"
    assert settings_adapter(fixed_edit("finished_goods", "finished_goods/gem"))["ok"]
    assert lua.eval("pile.settings.finished_goods.mats[1]==1 and pile.settings.finished_goods.mats[3]==0")
    # A whole middle page merges partitions of the same backing vector into
    # one helper call, and does not implicitly enable its category flag.
    lua.execute("all_fill_calls={};pile.settings.flags.finished_goods=false")
    assert settings_adapter(fixed_edit("finished_goods"))["ok"]
    fields = list(lua.globals().all_fill_calls.values())
    assert len(fields) == len(set(fields)) and fields.count("finished_goods.mats") == 1
    assert lua.eval("pile.settings.finished_goods.mats[3]==1 and not pile.settings.flags.finished_goods")
    lua.execute("pile.settings.refuse.fresh_raw_hide=false;pile.settings.refuse.rotten_raw_hide=false")
    assert settings_adapter(fixed_edit("refuse"))["ok"]
    assert lua.eval("not pile.settings.refuse.fresh_raw_hide and not pile.settings.refuse.rotten_raw_hide")
    assert settings_adapter(fixed_edit("refuse", scope=3))["ok"]
    assert lua.eval("pile.settings.refuse.fresh_raw_hide and pile.settings.refuse.rotten_raw_hide and pile.settings.flags.refuse")
    assert settings_adapter(fixed_edit("", "refuse", value=1))["ok"]
    assert lua.eval("not pile.settings.refuse.fresh_raw_hide and not pile.settings.refuse.rotten_raw_hide and not pile.settings.flags.refuse")
    lua.execute("make_setting('animals.enabled',1,{0});fixture_partitions['animals.enabled']={1}")
    assert settings_adapter(fixed_edit("animals"))["ok"]
    assert lua.eval("pile.settings.animals.enabled[1]==0 and pile.settings.animals.empty_cages")
    assert settings_adapter(fixed_edit("animals", scope=3))["ok"]
    assert lua.eval("pile.settings.animals.enabled[1]==1 and pile.settings.flags.animals")
    # Middle-column All/None ignores the leaf search.
    assert settings_adapter(fixed_edit("ammo", scope=3, value=1, query="CRAFTED"))["ok"]
    assert lua.eval("not pile.settings.ammo.quality_core[2] and not pile.settings.ammo.quality_total[1]")
    # Refuse's two raw-hide leaf rows address independent native booleans.
    lua.execute("pile.settings.refuse.fresh_raw_hide=true;pile.settings.refuse.rotten_raw_hide=true")
    assert settings_adapter(fixed_edit("refuse/type", "refuse/type/fresh_raw_hide", value=1))["ok"]
    assert lua.eval("not pile.settings.refuse.fresh_raw_hide and pile.settings.refuse.rotten_raw_hide")
    assert settings_adapter(fixed_edit("refuse/type", "refuse/type/1", value=1))["ok"]
    assert lua.eval("not pile.settings.refuse.fresh_raw_hide and pile.settings.refuse.rotten_raw_hide")
    assert settings_adapter(fixed_edit("refuse/type", value=2, query="fresh raw"))["ok"]
    assert lua.eval("pile.settings.refuse.fresh_raw_hide and pile.settings.refuse.rotten_raw_hide")
    assert settings_adapter(fixed_edit("refuse/type", value=1, query="raw hide"))["ok"]
    assert lua.eval("not pile.settings.refuse.fresh_raw_hide and not pile.settings.refuse.rotten_raw_hide")
    assert settings_adapter(fixed_edit("refuse/type", value=2))["ok"]
    assert lua.eval("pile.settings.refuse.fresh_raw_hide and pile.settings.refuse.rotten_raw_hide")
    assert not settings_adapter(fixed_edit("refuse", "refuse/type/fresh_raw_hide"))["ok"]
    # Metadata for every target is checked before any field is written.
    # Filtered shared vectors keep other eligible partitions zero on expansion;
    # only truly ineligible slots receive the native filler value of one.
    lua.execute(r"""
    unfiltered_fill=settings_fill
    df.global.world.raws.inorganics.all={
     {flags={},material={flags={IS_GEM=true}}},
     {flags={},material={flags={IS_METAL=true}}},
     {flags={},material={flags={}}}}
    make_setting('finished_goods.mats',3,{})
    function settings_fill(b,field,members,allowed,enabled,budget)
     if field~='finished_goods.mats' or type(members)~='string' then return unfiltered_fill(b,field,members,allowed,enabled,budget) end
     assert(members=='\0\1\0' and allowed=='\1\1\0')
     local values=b.settings.finished_goods.mats
     local resize=#values<#members
     for i=1,#members do
      if resize and allowed:byte(i)==0 then values[i]=1
      elseif members:byte(i)~=0 then values[i]=enabled and 1 or 0
      elseif values[i]==nil then values[i]=0 end
     end
     return {ok=true,steps=2}
    end
    """)
    assert settings_adapter(fixed_edit("finished_goods/metal", value=2, query="inorganic 1"))["ok"]
    assert lua.eval("pile.settings.finished_goods.mats[1]==0 and pile.settings.finished_goods.mats[2]==1 and pile.settings.finished_goods.mats[3]==1")
    lua.execute("settings_fill=unfiltered_fill")
    lua.execute("all_fill_calls={};settings_fields['wood.mats'].count=-1")
    assert settings_adapter(fixed_edit("", scope=4))["message"] == "Stockpile settings layout changed"
    assert len(lua.globals().all_fill_calls) == 0
    lua.execute("settings_fields['wood.mats'].count=3;settings_raw_count=65537")
    assert settings_adapter(fixed_edit("", scope=4))["message"] == "Stockpile settings exceed 65,536 entries"
    assert len(lua.globals().all_fill_calls) == 0
    lua.execute("settings_raw_count=0;fail_fill_at=2;pile.settings.ammo.other_mats={0,0}")
    partial = settings_adapter(fixed_edit("ammo", scope=3))
    assert not partial["ok"] and "earlier filters changed; inspect before retrying" in partial["message"]
    assert len(lua.globals().all_fill_calls) == 2  # no automatic replay or later writes
    lua.execute("fail_fill_at=nil;all_fill_calls={};pile.settings.flags.refuse=true;pile.settings.flags.corpses=false;pile.settings.refuse.type={1,0};pile.settings.corpses.corpses={0,1};pile.settings.refuse.fresh_raw_hide=true;pile.settings.refuse.rotten_raw_hide=false")
    assert settings_adapter(fixed_edit("", scope=4))["ok"]
    fields = list(lua.globals().all_fill_calls.values())
    assert len(fields) == 94 and len(set(fields)) == 94 and "ore.mats" not in fields
    assert not any(field.startswith(("refuse.", "corpses.")) for field in fields)
    assert lua.eval("pile.settings.flags.refuse and not pile.settings.flags.corpses and pile.settings.refuse.type[1]==1 and pile.settings.refuse.type[2]==0 and pile.settings.corpses.corpses[1]==0 and pile.settings.corpses.corpses[2]==1 and pile.settings.refuse.fresh_raw_hide and not pile.settings.refuse.rotten_raw_hide")
    assert lua.eval("pile.settings.misc.allow_organic and pile.settings.misc.allow_inorganic and pile.settings.flags.ammo and pile.settings.flags.wood")
    lua.execute("pile.settings.flags.food=false;pile.settings.flags.refuse=false;pile.settings.misc.allow_inorganic=false")
    # Maximum sum of per-vector rounding: 76 one-entry vectors and the final
    # vector with65460 entries. All-field plan/fill/flags and maximum reply fit
    # the producer budget even when the native pre-snapshot is282 steps.
    lua.execute(r"""
    local active={};for _,field in ipairs(fixture_vector_keys)do if field~='ore.mats' then active[#active+1]=field end end
    assert(#active==77);fixture_partitions={};settings_raw_count=65536
    for i,field in ipairs(active)do make_setting(field,i==77 and 65460 or 1,{}) end
    all_fill_calls={}
    """)
    maximum = fixed_edit("", scope=4, value=1)
    maximum["step_budget"] = 1193
    assert settings_adapter(maximum)["message"] == "Area request exceeds remaining step budget"
    assert len(lua.globals().all_fill_calls) == 0
    maximum["step_budget"] = 1194
    completed = settings_adapter(maximum)
    assert completed["ok"] and completed["steps"] == 1042, dict(completed)
    assert len(lua.globals().all_fill_calls) == 104
    assert lua.eval("#pile.settings.wood.mats==65460 and pile.settings.wood.mats[65460]==0 and pile.settings.flags.wood and pile.settings.misc.allow_organic and not pile.settings.misc.allow_inorganic")
    assert lua.eval("pile.settings.flags.ammo and not pile.settings.flags.food and not pile.settings.flags.refuse and not pile.settings.ammo.quality_core[1] and not pile.settings.refuse.fresh_raw_hide")
    # Presets use the amended synchronous write policy. The native transaction
    # stand-in models effect/rollback boundaries; buffer identity is tested in
    # DF-free C++, and the actual importer/native guard still require C/D.
    lua.execute(r"""
    settings_raw_count=0;import_calls=0;preset_calls=0
    local cats={'animals','food','furniture','corpses','refuse','stone','ammo','coins',
      'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
    for _,field in ipairs(fixture_vector_keys)do
     local cat,key=field:match('^([^%.]+)%.(.+)$');pile.settings[cat][key]={1,0,1,7}
    end
    function copy_state(value)
     if type(value)~='table' then return value end
     local result={};for k,v in pairs(value)do result[k]=copy_state(v) end;return result
    end
    local function encode(value)
     if type(value)~='table' then return tostring(value) end
     local entries={};for k,v in pairs(value)do entries[#entries+1]=tostring(k)..'='..encode(v) end
     table.sort(entries);return '{'..table.concat(entries,',')..'}'
    end
    function preset_state()return encode{pile.settings,pile.storage,pile.stockpile_flag} end
    function fixture_import(path,id,mode,filter)
     import_calls=import_calls+1;last_import_path=path
     assert(id==5 and mode=='set' and filter=='')
     local cat=path:match('/cat_([^/]+)%.dfstock$');if cat=='sheets' then cat='sheet' end
     for _,name in ipairs(cats)do pile.settings.flags[name]=cat and name==cat or not cat and name~='corpses' and name~='refuse' end
     for _,field in ipairs(fixture_vector_keys)do
      if field~='ore.mats' then
       local category,key=field:match('^([^%.]+)%.(.+)$')
       pile.settings[category][key]=pile.settings.flags[category] and {1,1,1} or {}
      end
     end
     for _,field in ipairs(fixture_fixed_keys)do
      local category,key=field:match('^([^%.]+)%.(.+)$');local enabled=pile.settings.flags[category] or category=='misc'
      pile.settings[category][key]=key:find('quality',1,true) and {enabled,enabled,enabled,enabled,enabled,enabled,enabled} or enabled
     end
     pile.storage.max_bins=0;pile.storage.max_barrels=0;pile.storage.max_wheelbarrows=0;pile.stockpile_flag.use_links_only=false
     if import_mode=='error' then error('fixture import failed after mutation') end
     if import_mode=='false' then return false end
     if import_mode=='malformed' then return 'true' end
     return true
    end
    package.preload['plugins.stockpiles']=function()
     if plugin_missing then error('plugin unavailable') end
     return {stockpiles_import=fixture_import}
    end
    dfhack.getHackPath=function()return 'C:/Pinned DFHack' end
    function settings_preset(b,preset,importer,path,budget)
     preset_calls=preset_calls+1
     assert(budget==nil)
     if helper_lost then error('fixture transaction helper lost') end
     if settings_raw_count>65536 then return {ok=false,message='Stockpile settings exceed 65,536 entries',steps=79} end
     local saved=copy_state(b.settings);local storage=copy_state(b.storage);local flags=copy_state(b.stockpile_flag)
     local ok=true
     if preset==19 then
      b.settings.flags={}
      for _,field in ipairs(fixture_vector_keys)do
       if field~='ore.mats' then local cat,key=field:match('^([^%.]+)%.(.+)$');b.settings[cat][key]={} end
      end
      for _,field in ipairs(fixture_fixed_keys)do
       local cat,key=field:match('^([^%.]+)%.(.+)$')
       b.settings[cat][key]=key:find('quality',1,true) and {false,false,false,false,false,false,false} or false
      end
     else local worked,result=pcall(importer,path,b.id,'set','');ok=worked and result==true end
     b.storage=storage;b.stockpile_flag=flags
     if not ok then b.settings=saved end
     return {ok=ok,message=ok and '' or 'Native stockpile preset failed; previous settings restored',steps=reported_preset_steps or 79,work_unknown=true}
    end
    """)
    def preset_request(preset=1, **extra):
        return lua.globals().request(11, lua.table_from({"operation": 3, "preset": preset,
            "expected_revision": call(9)["areas"][1]["revision"], **extra}))
    categories = ["animals", "food", "furniture", "corpses", "refuse", "stone", "ammo", "coins",
                  "bars_blocks", "gems", "finished_goods", "leather", "cloth", "wood", "weapons", "armor", "sheet"]
    for preset in range(1, 19):
        lua.execute("pile.storage.max_bins=3;pile.storage.max_barrels=2;pile.storage.max_wheelbarrows=1;pile.stockpile_flag.use_links_only=true")
        request = preset_request(preset);request["step_budget"] = 0
        result = settings_adapter(request)
        assert result["ok"] and result["work_unknown"] and result["steps"] == 94, dict(result)
        stem = "all" if preset == 1 else "cat_" + ("sheets" if preset == 18 else categories[preset-2])
        assert lua.globals().last_import_path == f"C:/Pinned DFHack/data/stockpiles/{stem}.dfstock"
        assert lua.eval("pile.storage.max_bins==3 and pile.storage.max_barrels==2 and pile.storage.max_wheelbarrows==1 and pile.stockpile_flag.use_links_only")
        assert lua.eval("#pile.settings.ore.mats==4 and pile.settings.ore.mats[4]==7")
        if preset == 1:
            assert lua.eval("not pile.settings.flags.refuse and not pile.settings.flags.corpses and pile.settings.misc.allow_organic and pile.settings.misc.allow_inorganic")
        else:
            assert [cat for cat in categories if lua.globals().pile.settings.flags[cat]] == [categories[preset-2]]
    # False, Lua exception, and malformed importer success all roll back exact
    # vector lengths/values, fixed fields, category flags and container settings.
    for mode in ["false", "error", "malformed"]:
        lua.globals().import_mode = mode
        saved = lua.globals().preset_state()
        before = lua.globals().import_calls
        result = settings_adapter(preset_request())
        assert not result["ok"] and result["work_unknown"] and "previous settings restored" in result["message"]
        assert lua.globals().preset_state() == saved and lua.globals().import_calls == before + 1
    lua.execute("import_mode=nil;settings_raw_count=65537")
    saved = lua.globals().preset_state();before = lua.globals().import_calls
    assert settings_adapter(preset_request())["message"] == "Stockpile settings exceed 65,536 entries"
    assert lua.globals().preset_state() == saved and lua.globals().import_calls == before
    lua.execute("settings_raw_count=65536")
    assert settings_adapter(preset_request(expected_revision=0))["message"] == "Area revision required; inspect again"
    assert settings_adapter(preset_request(expected_revision=1))["message"] == "Area changed; inspect again"
    assert lua.globals().import_calls == before
    # A long write is accepted with an exhausted read budget and honest work
    # accounting; the result contract/scheduler have independent native tests.
    lua.execute("reported_preset_steps=9000")
    request = preset_request();request["step_budget"] = 0
    result = settings_adapter(request)
    assert result["ok"] and result["steps"] == 9015 and result["work_unknown"]
    lua.execute("reported_preset_steps=nil;package.loaded['plugins.stockpiles']=nil;plugin_missing=true")
    assert settings_adapter(preset_request())["message"] == "Native stockpile preset plugin unavailable"
    before = lua.globals().import_calls
    result = settings_adapter(preset_request(19))
    assert result["ok"] and lua.globals().import_calls == before  # None requires no importer
    assert lua.eval("not next(pile.settings.flags) and #pile.settings.wood.mats==0 and not pile.settings.misc.allow_organic and not pile.settings.armor.quality_core[1]")
    assert lua.eval("#pile.settings.ore.mats==4 and pile.settings.ore.mats[4]==7 and pile.storage.max_bins==3 and pile.stockpile_flag.use_links_only")
    lua.execute("helper_lost=true")
    unknown = settings_adapter(preset_request(19))
    assert not unknown["ok"] and unknown["steps"] == 13 and unknown["work_unknown"] and "inspect before retrying" in unknown["message"]
    lua.execute("helper_lost=false")
    # A read cannot opt out of bounded work by supplying the private write flag.
    ordinary = setting_request("wood");ordinary["step_budget"] = 0;ordinary["synchronous_write"] = True;ordinary["synchronous_read"] = False
    assert settings_adapter(ordinary)["message"] == "Area request exceeds remaining step budget"
    # Location IDs belong to sites. Moving/repairing/removing a relationship
    # updates both sorted ID lists before native recategorization. The stand-in
    # verifies Lua integration; the actual native helper needs C/D acceptance.
    lua.execute(r"""
    location_site={id=90,buildings={location(1,8,'Destination tavern'),location(2,2,'Destination temple',1,18),location(8,1,'Keep')}}
    old_location_site={id=91,buildings={location(1,8,'Previous tavern')}}
    for _,site in ipairs{location_site,old_location_site}do for _,loc in ipairs(site.buildings)do loc.contents={building_ids={}} end end
    old_location_site.buildings[1].contents.building_ids={3,6,6,8}
    location_site.buildings[1].contents.building_ids={2,4,10}
    df.world_site.find=function(id)if id==90 then return location_site elseif id==91 then return old_location_site end end
    dfhack.world.getCurrentSite=function()return no_location_site and nil or location_site end
    zone.site_id=91;zone.location_id=1;zone.type=0
    location_set_calls=0;recategorize_calls=0
    -- Include identity in the fixture revision just as the native snapshot does.
    local snapshot_before_location=area_snapshot
    function area_snapshot(b,visible,budget)
     local value=snapshot_before_location(b,visible,budget)
     if value.ok and b.kind==1 then value.revision=value.revision+(b.site_id or -1)*113+(b.location_id or -1)*131 end
     return value
    end
    function set_location(b,site,id,budget)
     assert(budget==nil);location_set_calls=location_set_calls+1
     local function find(owner,key)
      if owner then for _,loc in ipairs(owner.buildings)do if loc.id==key then return loc end end end
     end
     local target=find(site,id)
     if id>=0 and (not target or target:getType()==1) then return {ok=false,message='Location no longer exists',steps=0,work_unknown=true} end
     local previous=find(df.world_site.find(b.site_id),b.location_id)
     local function without(values)
      local result={};for _,v in ipairs(values)do if v~=b.id then result[#result+1]=v end end
      table.sort(result);return result
     end
     local old_values=previous and without(previous.contents.building_ids)
     local new_values=target and without(target.contents.building_ids)
     if new_values then new_values[#new_values+1]=b.id;table.sort(new_values) end
     if previous and previous~=target then previous.contents.building_ids=old_values end
     if target then target.contents.building_ids=new_values;b.site_id=site.id end
     b.location_id=id;recategorize_calls=recategorize_calls+1
     if fail_recategorize then return {ok=false,message='Native location recategorization failed; inspect before retrying',steps=0,work_unknown=true} end
     return {ok=true,steps=0,work_unknown=true}
    end
    """)
    def location_edit(location_id, **extra):
        return lua.globals().request(11, lua.table_from({"operation": 7, "kind": 1, "id": 6,
            "location_id": location_id, "expected_revision": call(9, {"kind": 1, "id": 6})["areas"][1]["revision"], **extra}))
    request = location_edit(1);request["step_budget"] = 0
    result = settings_adapter(request)
    assert result["ok"] and result["work_unknown"] and result["areas"][1]["location_name"] == "Destination tavern"
    assert list(lua.globals().old_location_site.buildings[1].contents.building_ids.values()) == [3, 8]
    assert list(lua.globals().location_site.buildings[1].contents.building_ids.values()) == [2, 4, 6, 10]
    assert lua.eval("zone.site_id==90 and zone.location_id==1 and recategorize_calls==1")
    before = lua.globals().location_set_calls
    assert settings_adapter(request)["message"] == "Area changed; inspect again"  # prior-site revision cannot replay
    assert lua.globals().location_set_calls == before
    assert settings_adapter(location_edit(1))["ok"]
    assert list(lua.globals().location_site.buildings[1].contents.building_ids.values()) == [2, 4, 6, 10]
    # Repair a missing back-reference on an otherwise identical assignment.
    lua.execute("location_site.buildings[1].contents.building_ids={2,10}")
    assert settings_adapter(location_edit(1))["ok"]
    assert list(lua.globals().location_site.buildings[1].contents.building_ids.values()) == [2, 6, 10]
    result = settings_adapter(location_edit(2))
    assert result["ok"] and result["areas"][1]["location_name"] == "Destination temple" and result["areas"][1]["religion"] == "The Faith"
    assert list(lua.globals().location_site.buildings[1].contents.building_ids.values()) == [2, 10]
    assert list(lua.globals().location_site.buildings[2].contents.building_ids.values()) == [6]
    for missing in [999, 8]:
        assert settings_adapter(location_edit(missing))["message"] == "Location no longer exists"
        assert lua.eval("zone.location_id==2")
    before = lua.globals().location_set_calls
    for invalid in [None, -2, 1.5, 2147483648]:
        assert settings_adapter(location_edit(invalid))["message"] == "invalid area location"
    assert settings_adapter(location_edit(-1, expected_revision=0))["message"] == "Area revision required; inspect again"
    assert lua.globals().location_set_calls == before
    removed = settings_adapter(location_edit(-1))
    assert removed["ok"] and removed["areas"][1]["location_id"] == -1
    assert removed["areas"][1]["location_name"] == "" and removed["areas"][1]["religion"] == ""
    assert lua.eval("zone.site_id==90 and #location_site.buildings[2].contents.building_ids==0")
    # Orphaned old IDs and repeated removal are recoverable. Membership work
    # does not add a timing-derived limit at the old1536/2048 boundaries.
    lua.execute("zone.site_id=999;zone.location_id=999")
    assert settings_adapter(location_edit(-1))["ok"]
    assert settings_adapter(location_edit(-1))["ok"]
    lua.execute("location_site.buildings[1].contents.building_ids={};for i=100,5100 do table.insert(location_site.buildings[1].contents.building_ids,i) end")
    assert settings_adapter(location_edit(1))["ok"]
    assert len(lua.globals().location_site.buildings[1].contents.building_ids) == 5002
    # Native recategorization can fail after relationships changed: one call,
    # no optimistic success and no replay; a later explicit inspect sees facts.
    lua.execute("fail_recategorize=true")
    before = lua.globals().location_set_calls
    failed = settings_adapter(location_edit(2))
    assert not failed["ok"] and failed["work_unknown"] and "inspect before retrying" in failed["message"]
    assert lua.globals().location_set_calls == before+1 and lua.eval("zone.location_id==2")
    lua.execute("fail_recategorize=false")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_name"] == "Destination temple"
    lua.execute(r"""
    location_site.next_building_id=20;location_create_calls=0
    function create_location(b,site,kind,profession,deity_kind,deity_id,adjective,noun,budget)
     location_create_calls=location_create_calls+1;assert(budget==nil)
     if site.next_building_id<0 or site.next_building_id==2147483647 then return {ok=false,message='Location IDs exhausted',steps=0,work_unknown=true} end
     for _,existing in ipairs(site.buildings)do if existing.id==site.next_building_id then return {ok=false,message='Location registry changed; inspect again',steps=0,work_unknown=true} end end
     if kind==4 and profession>20 then return {ok=false,message='Profession no longer exists',steps=0,work_unknown=true} end
     if kind==2 and deity_kind==2 and not df.historical_figure.find(deity_id) then return {ok=false,message='Deity no longer exists',steps=0,work_unknown=true} end
     if kind==2 and deity_kind==3 and not df.historical_entity.find(deity_id) then return {ok=false,message='Religion no longer exists',steps=0,work_unknown=true} end
     if refuse_creation then return {ok=false,message='Native location preparation failed; no location created',steps=0,work_unknown=true} end
     local id=site.next_building_id
     local created=location(id,({8,2,9,11,13})[kind],'Created '..kind,deity_kind==3 and 1 or 0,deity_id)
     created.contents={building_ids={b.id},profession=profession};created.adjective=adjective;created.noun=noun
     -- Stand-in only: actual C++ constructor/default/native-effect validation
     -- remains distinct from this Lua command-dispatch fixture.
     for _,owner in ipairs{location_site,old_location_site}do
      if owner.id==b.site_id then for _,old in ipairs(owner.buildings)do
       if old.id==b.location_id then for i=#old.contents.building_ids,1,-1 do if old.contents.building_ids[i]==b.id then table.remove(old.contents.building_ids,i) end end end
      end end
     end
     table.insert(site.buildings,created);table.sort(site.buildings,function(a,b)return a.id<b.id end)
     site.next_building_id=id+1;b.site_id=site.id;b.location_id=id
     if fail_creation_recategory then return {ok=false,message='Native location created but recategorization failed; inspect before retrying',steps=0,work_unknown=true} end
     return {ok=true,steps=0,work_unknown=true}
    end
    """)
    def location_create(kind=1, **extra):
        return lua.globals().request(11, lua.table_from({"operation": 8, "kind": 1, "id": 6,
            "location_kind": kind, "expected_revision": call(9, {"kind": 1, "id": 6})["areas"][1]["revision"], **extra}))
    invalid_creates = [dict(location_kind=0), dict(location_kind=6), dict(location_kind=4),
                       dict(location_kind=4, profession=-1), dict(location_kind=4, profession=32768),
                       dict(location_kind=1, profession=3), dict(location_kind=2),
                       dict(location_kind=2, deity_kind=0), dict(location_kind=2, deity_kind=4),
                       dict(location_kind=2, deity_kind=1, deity_id=17),
                       dict(location_kind=2, deity_kind=2), dict(location_kind=2, deity_kind=3),
                       dict(location_kind=1, deity_kind=1), dict(location_kind=1, deity_id=17)]
    before = lua.globals().location_create_calls
    for values in invalid_creates:
        assert settings_adapter(location_create(**values))["message"] == "invalid area location creation"
    assert lua.globals().location_create_calls == before
    assert settings_adapter(location_create(expected_revision=0))["message"] == "Area revision required; inspect again"
    assert settings_adapter(location_create(expected_revision=1))["message"] == "Area changed; inspect again"
    assert settings_adapter(location_create())["message"] == "Location name words unavailable"
    lua.execute("df.global.world.raws.language={word_table={[0]={[35]={words={Adjectives={},TheX={8}}}}}}")
    assert settings_adapter(location_create())["message"] == "Location name words unavailable"
    assert lua.globals().location_create_calls == before
    lua.execute("df.global.world.raws.language.word_table[0][35].words.Adjectives={2,3};math.randomseed(7)")
    for kind in range(1, 6):
        extra = {"profession": 10} if kind == 4 else {"deity_kind": 1} if kind == 2 else {}
        request = location_create(kind, **extra);request["step_budget"] = 0
        before_id = lua.globals().location_site.next_building_id
        before_count = len(lua.globals().location_site.buildings)
        result = settings_adapter(request)
        assert result["ok"] and result["work_unknown"] and result["areas"][1]["location_id"] == before_id, dict(result)
        assert result["areas"][1]["location_name"] == f"Created {kind}" and result["areas"][1]["religion"] == ""
        created = lua.globals().location_site.buildings[before_count + 1]
        assert created.adjective in (2, 3) and created.noun == 8
        assert list(created.contents.building_ids.values()) == [6]
        assert lua.globals().location_site.next_building_id == before_id + 1
        before = lua.globals().location_create_calls
        assert settings_adapter(request)["message"] == "Area changed; inspect again"
        assert lua.globals().location_create_calls == before  # no duplicate creation on stale replay
    for deity_kind, deity_id, expected in [(2, 17, "The Deity"), (3, 18, "The Faith")]:
        created = settings_adapter(location_create(2, deity_kind=deity_kind, deity_id=deity_id))
        assert created["ok"] and created["areas"][1]["religion"] == expected
    before_count = len(lua.globals().location_site.buildings)
    before_id = lua.globals().location_site.next_building_id
    before_zone = lua.globals().zone.location_id
    for kind, extra, expected in [(4, dict(profession=21), "Profession no longer exists"),
                                  (2, dict(deity_kind=2, deity_id=999), "Deity no longer exists"),
                                  (2, dict(deity_kind=3, deity_id=999), "Religion no longer exists")]:
        assert settings_adapter(location_create(kind, **extra))["message"] == expected
        assert len(lua.globals().location_site.buildings) == before_count
        assert lua.globals().location_site.next_building_id == before_id and lua.globals().zone.location_id == before_zone
    lua.execute("location_site.next_building_id=1")
    assert settings_adapter(location_create())["message"] == "Location registry changed; inspect again"
    lua.execute("location_site.next_building_id=2147483647")
    assert settings_adapter(location_create())["message"] == "Location IDs exhausted"
    lua.globals().location_site.next_building_id = before_id
    lua.execute("refuse_creation=true")
    rejected = settings_adapter(location_create())
    assert not rejected["ok"] and "no location created" in rejected["message"]
    assert lua.globals().location_site.next_building_id == before_id and lua.globals().zone.location_id == before_zone
    assert len(lua.globals().location_site.buildings) == before_count
    lua.execute("refuse_creation=false;df.global.world.raws.language.word_table[0][35].words={Adjectives={5},TheX={9}};fail_creation_recategory=true")
    before = lua.globals().location_create_calls
    uncertain = settings_adapter(location_create())
    assert not uncertain["ok"] and "inspect before retrying" in uncertain["message"] and uncertain["work_unknown"]
    assert lua.globals().location_create_calls == before + 1 and len(lua.globals().location_site.buildings) == before_count + 1
    created = lua.globals().location_site.buildings[before_count + 1]
    assert created.adjective == 5 and created.noun == 9  # raw name source was reacquired
    assert lua.globals().zone.location_id == before_id and lua.globals().location_site.next_building_id == before_id + 1
    lua.execute("fail_creation_recategory=false")
    assert call(9, {"kind": 1, "id": 6})["areas"][1]["location_name"] == "Created 1"
    # Deconstruction invalidates the native object immediately. Poison every
    # field to catch any response construction or re-observation after removal.
    lua.execute(r"""
    removed_ids={};remove_calls=0
    local prior_find=df.building.find
    df.building.find=function(id)if not removed_ids[id] then return prior_find(id) end end
    function remove_area(b,budget)
     assert(budget==nil);remove_calls=remove_calls+1
     if remove_mode=='reject' then return {ok=false,message='Native area removal rejected',steps=0,work_unknown=true} end
     if remove_mode=='throw' then error('native removal interrupted') end
     removed_ids[b.id]=true
     for key in pairs(b)do b[key]=nil end
     setmetatable(b,{__index=function()error('read after destruction')end})
     return {ok=true,steps=0,work_unknown=true}
    end
    """)
    for area_kind, area_id in [(0, 5), (1, 6)]:
        snapshot = call(9, {"kind": area_kind, "id": area_id})["areas"][1]
        def deletion(**extra):
            req = lua.globals().request(12, lua.table_from({"kind": area_kind, "id": area_id,
                "expected_revision": snapshot["revision"], **extra}))
            req["step_budget"] = 0
            return settings_adapter(req)
        before = lua.globals().remove_calls
        assert deletion(expected_revision=0)["message"] == "Area revision required; inspect again"
        assert deletion(expected_revision=1)["message"] == "Area changed; inspect again"
        assert deletion(kind=1-area_kind)["message"] == "Area kind changed; inspect again"
        lua.execute("force_hidden=true")
        assert deletion()["message"] == "Area is not visible"
        lua.execute("force_hidden=false")
        assert lua.globals().remove_calls == before
        lua.execute("remove_mode='reject'")
        result = deletion()
        assert not result["ok"] and result["work_unknown"]
        lua.execute("remove_mode='throw'")
        result = deletion()
        assert not result["ok"] and result["work_unknown"] and "inspect before retrying" in result["message"]
        lua.execute("remove_mode=nil")
        result = deletion()
        assert result["ok"] and result["work_unknown"] and result["building_id"] == area_id
        for field in ("x", "y", "z", "width", "height"):
            assert result["hint_"+field] == snapshot[field]
        assert result["areas"] is None
        assert lua.globals().remove_calls == before + 3
        assert deletion()["message"] == "Area no longer exists"
        assert lua.globals().remove_calls == before + 3
    # Creation dispatch uses native construction stand-ins; native allocation,
    # occupancy/default fields and deconstruction are separate C/D obligations.
    lua.execute(r"""
    created_areas={};create_calls=0;next_area_id=30;import_calls={}
    local prior_find=df.building.find
    df.building.find=function(id)if not removed_ids[id] then return created_areas[id] or prior_find(id) end end
    df.civzone_type[6]='Pen';df.civzone_type[7]='Barracks';df.civzone_type[8]='Office'
    function create_area(a,budget)
     assert(budget==nil);create_calls=create_calls+1
     if refuse_area_creation then return {ok=false,message='Every selected tile must be visible and loaded',steps=1} end
     if a.kind==0 and a.categories~=0 and settings_raw_count>65536 then
      return {ok=false,message='Stockpile settings exceed 65,536 entries',steps=79}
     end
     local x,y,z,w,h=a.x,a.y,a.z,a.width or 1,a.height or 1
     local room={}
     if a.operation==5 then
      local right,bottom=-1,-1;x,y,z=32768,32768,a.paint_z
      for _,span in ipairs(a.spans)do x=math.min(x,span.x);y=math.min(y,span.y);right=math.max(right,span.x+span.length-1);bottom=math.max(bottom,span.y) end
      w,h=right-x+1,bottom-y+1
      if w>256 or h>256 or w*h>32768 then return {ok=false,message='Painted area would exceed 256 per side or 32,768 tiles',steps=1} end
      room={x=x,y=y,width=w,height=h,extents={}}
      for i=0,w*h-1 do room.extents[i]=0 end
      for _,span in ipairs(a.spans)do for tx=span.x,span.x+span.length-1 do room.extents[(span.y-y)*w+tx-x]=1 end end
     end
     local id=next_area_id;next_area_id=id+1
     created_areas[id]={id=id,kind=a.kind,name='',x1=x,y1=y,z=z,x2=x+w-1,y2=y+h-1,room=room,
      type=a.zone_type or -1,settings={flags={},misc={allow_organic=false,allow_inorganic=false}},
      storage={max_barrels=0,max_bins=0,max_wheelbarrows=0},stockpile_flag={use_links_only=false},
      links={give_to_pile={},take_from_pile={}},spec_sub_flag={active=false},assigned_unit_id=-1,
      zone_settings={pen={flags={}},pond={flag={keep_filled=true}},archery={dir_x=0,dir_y=0},
       tomb={flags={no_pets=false,no_citizens=false}},gather={flags={}}}}
     return {ok=true,building_id=id,steps=7,work_unknown=true}
    end
    package.loaded['plugins.stockpiles']=nil
    package.preload['plugins.stockpiles']=function()error('fixture plugin unavailable')end
    """)
    def create_request(**values):
        data = {"id": -1, "kind": 0, "x": 10, "y": 11, "z": 1, "width": 2, "height": 2, **values}
        req = lua.globals().request(10, lua.table_from(data));req["step_budget"] = 0
        return req
    before = lua.globals().create_calls
    for values, message in [({"x": -1}, "invalid area rectangle"), ({"width": 32}, "invalid area rectangle"),
                            ({"width": 0}, "invalid area rectangle"), ({"x": 32767, "width": 2}, "invalid area rectangle"),
                            ({"categories": 131072}, "invalid stockpile categories"),
                            ({"barrels": 5}, "Container limits exceed usable stockpile tiles"),
                            ({"wheelbarrows": 4}, "Container limits exceed usable stockpile tiles"),
                            ({"active": 1}, "Zone-only fields on stockpile"),
                            ({"categories": 1}, "Native stockpile preset plugin unavailable"),
                            ({"kind": 1, "zone_type": 255}, "Unsupported zone type"),
                            ({"kind": 1, "zone_type": 0, "bins": 1}, "Stockpile-only fields on zone"),
                            ({"kind": 1, "zone_type": 2, "owner_id": -1}, "This zone type has no single owner"),
                            ({"kind": 1, "zone_type": 0, "owner_id": 999}, "Owner must be an active living citizen of this fortress")]:
        result = settings_adapter(create_request(**values))
        assert not result["ok"] and result["message"] == message, dict(result)
    assert lua.globals().create_calls == before
    assert settings_adapter(create_request(width=31, height=31))["ok"]
    assert settings_adapter(create_request(x=32767, y=32767, width=1, height=1))["ok"]
    none = settings_adapter(create_request(barrels=4, bins=4, wheelbarrows=3, links_only=1))
    assert none["ok"] and none["work_unknown"] and none["message"] == "Native area created"
    created = none["areas"][1]
    assert created["revision"] > 0 and created["categories"] == 0 and len(created["extents"]) == 4
    assert created["barrels"] == 4 and created["bins"] == 4 and created["wheelbarrows"] == 3 and created["links_only"]
    assert none["hint_x"] == 10 and none["hint_y"] == 11 and none["hint_z"] == 1
    lua.execute(r"""
    package.loaded['plugins.stockpiles']={stockpiles_import=function(path,id,mode,filter)
     table.insert(import_calls,{path=path,id=id,mode=mode,filter=filter})
     assert(mode=='enable' and filter=='')
     local b=df.building.find(id)
     b.storage.max_bins=123;b.stockpile_flag.use_links_only=true
     local cat=path:match('/cat_(.+)%.dfstock$');if cat=='sheets' then cat='sheet' end
     b.settings.flags[cat]=true
     if import_mode=='throw' then error('fixture failed import') end
     if import_mode=='false' then return false end
     if import_mode=='malformed' then return 1 end
     return true
    end}
    """)
    all_categories = settings_adapter(create_request(categories=131071, barrels=1))
    assert all_categories["ok"] and all_categories["areas"][1]["categories"] == 131071
    assert all_categories["areas"][1]["barrels"] == 1 and all_categories["areas"][1]["bins"] == 0
    assert not all_categories["areas"][1]["links_only"] and len(lua.globals().import_calls) == 17
    assert lua.globals().import_calls[17]["path"].endswith("/cat_sheets.dfstock")
    lua.execute("settings_raw_count=65537")
    assert settings_adapter(create_request(categories=1))["message"] == "Stockpile settings exceed 65,536 entries"
    assert settings_adapter(create_request())["ok"]  # None allocates no raw filters
    lua.execute("settings_raw_count=65536")
    assert settings_adapter(create_request(categories=1))["ok"]
    lua.execute("settings_raw_count=0")
    for failure in ("false", "throw", "malformed"):
        lua.globals().import_mode = failure
        expected_id = lua.globals().next_area_id
        before_removes = lua.globals().remove_calls
        result = settings_adapter(create_request(categories=1))
        assert result["message"].startswith("New pile preset failed; new area removed: ") and result["work_unknown"]
        assert lua.globals().df.building.find(expected_id) is None and lua.globals().remove_calls == before_removes+1
    lua.execute("import_mode='false';remove_mode='reject'")
    uncertain_id = lua.globals().next_area_id
    uncertain = settings_adapter(create_request(categories=1))
    assert not uncertain["ok"] and uncertain["message"] == "New area initialization failed; cleanup uncertain; inspect before retrying"
    assert lua.globals().df.building.find(uncertain_id) is not None
    lua.execute("import_mode=nil;remove_mode=nil;refuse_area_creation=true")
    before_id = lua.globals().next_area_id
    assert settings_adapter(create_request())["message"] == "Every selected tile must be visible and loaded"
    assert lua.globals().next_area_id == before_id
    lua.execute("refuse_area_creation=false")
    for zone_type in (0, 2, 3, 4, 5, 6, 7, 8):
        result = settings_adapter(create_request(kind=1, zone_type=zone_type))
        assert result["ok"] and result["areas"][1]["active"] and result["areas"][1]["owner_id"] == -1, dict(result)
        settings = result["areas"][1]["zone_settings"]
        if zone_type == 2:
            assert settings["pond_mode"] == 1
        if zone_type == 3:
            assert settings["facing"] == 2
        if zone_type == 4:
            assert settings["tomb_pets"] == 0
        if zone_type == 5:
            assert settings["gather_trees"] == 1 and settings["gather_shrubs"] == 1
    owner = settings_adapter(create_request(kind=1, zone_type=0, owner_id=20, active=0))
    assert owner["ok"] and owner["areas"][1]["owner_id"] == 20 and not owner["areas"][1]["active"]
    lua.execute("force_notification_error=true")
    expected_id = lua.globals().next_area_id
    failed_settings = settings_adapter(create_request(kind=1, zone_type=0))
    assert failed_settings["message"].startswith("Invalid new area settings; new area removed: ")
    assert failed_settings["message"].endswith("fixture notification failure")
    assert lua.globals().df.building.find(expected_id) is None
    lua.execute("force_notification_error=false")
    def create_paint(spans, **extra):
        data = {"operation": 5, "id": -1, "paint_mode": 1, "paint_z": 1,
                "spans": lua.table_from([lua.table_from(span) for span in spans]), **extra}
        req = lua.globals().request(10, lua.table_from(data));req["step_budget"] = 0
        return settings_adapter(req)
    paint = create_paint([{"x": 10, "y": 10, "length": 2}, {"x": 10, "y": 11, "length": 1}])
    assert paint["ok"] and list(paint["areas"][1]["extents"].values()) == [1, 1, 1, 0]
    created = paint["areas"][1]
    chained = settings_adapter(lua.globals().request(11, lua.table_from({"id": created["id"], "operation": 5,
        "paint_mode": 1, "expected_revision": created["revision"],
        "spans": lua.table_from([lua.table_from({"x": 11, "y": 11, "length": 1})])})))
    assert chained["ok"] and chained["areas"][1]["revision"] != created["revision"]
    assert create_paint([{"x": 0, "y": 0, "length": 256}, {"x": 0, "y": 1, "length": 128}])["ok"]
    full_footprint = [{"x": 0, "y": y, "length": 256} for y in range(128)]
    maximum_paint = create_paint(full_footprint)
    assert maximum_paint["ok"] and len(maximum_paint["areas"][1]["extents"]) == 32768
    assert create_paint(full_footprint + [{"x": 0, "y": 128, "length": 1}])["message"] == "too many painted area tiles"
    individual_tiles = [{"x": x, "y": y, "length": 1} for y in range(128) for x in range(256)]
    maximum_spans = create_paint(individual_tiles, kind=1, zone_type=2)
    assert maximum_spans["ok"] and len(maximum_spans["areas"][1]["extents"]) == 32768
    assert create_paint(individual_tiles + [{"x": 0, "y": 128, "length": 1}])["message"] == "too many area spans"
    assert create_paint([{"x": 0, "y": 0, "length": 1}], paint_z=-1)["message"] == "area paint z required"
    assert create_paint([{"x": 0, "y": 0, "length": 1}], paint_mode=2)["message"] == "invalid area paint"
    assert create_paint([{"x": 0, "y": 0, "length": 1}], categories=1)["message"] == "Legacy area fields cannot be combined with an operation"
    assert create_paint([{"x": 0, "y": 0, "length": 1}, {"x": 255, "y": 127, "length": 1}], kind=1, zone_type=0)["ok"]
    assert create_paint([{"x": 0, "y": 0, "length": 1}, {"x": 255, "y": 128, "length": 1}], kind=1, zone_type=0)["message"] == "Painted area would exceed 256 per side or 32,768 tiles"
    print("AREAS_ADAPTER PASS")


if __name__ == "__main__":
    main()
