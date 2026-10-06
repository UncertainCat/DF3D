"""No assets/process: typed manager adapter, zero-index DF vectors, pinned API mocks."""
from pathlib import Path
from lupa import LuaRuntime

# DFHack mock audit against external/dfhack/docs/dev/Lua API.rst:
# getTileFlags:2410 (LuaApi.cpp:2706-2712): designation,occupancy.
# getNoblePositions:1916: rows include entity,assignment,position.
# buildings.setOwner:2589: (civzone,unit or nil)->bool.
# canWalkBetween:2461 (LuaApi.cpp:2657): two coords -> bool.
# isSuitableItem/Material:1430/1435: filter,type,subtype / filter,mat,index,item_type -> bool.
# Remaining mocks audited: df2utf(string)->string; getTickCount():957 -> number;
# gui getCurViewscreen([bool])/getFocusStrings(screen):1071/1076 -> screen/string sequence;
# unit predicates:1497-1575,1979 -> bool; getReadableName(unit):1854 -> string;
# job getName/getManagerOrderName:1439/1443 -> string, removeJob:1345 -> bool,
# getWorker:1372 -> unit/nil; item subtype count/def:2129/2134 -> int/pointer;
# moveToGround(item,pos):2205 -> bool; matinfo.decode(mat,index):811->info/nil,
# info:toString():827->string. Error/false injection retains each API's return shape.
# Fixture producibility (bridge/plugin/work_orders.lua functions):
# step_builder: removed/garbage_collect exclusions; inspect: estimate count/text,
# native dependency satisfaction, details/inputs, positions, editability and jobs.
# handle / returned request closure: missing request, order/dependency cap refusals,
# move replies without orders, subtype/material resets and page caps/next_cursor.
# step_builder: WEAPON items_other_id bucket and IN_PLAY fallback.
# build_list: native adjective predicates; raw-only SYNTH/PRODUCT are not picker rows.
# task_key / generate_tasks: length-prefixed keys and standard group custom=-1.
# list_reply: progress phase/done/total without rows; completed candidate pages.
# handle: exact stale/neighbor/input/condition/detail refusal messages.
# Host/Godot codec fixture combines these field shapes from separate replies;
# its INT64_MAX revision is a transport boundary, not a claimed recorded hash.


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((Path(__file__).resolve().parent / "qa/lua_test_prelude.lua").read_text(encoding="utf-8"))
    lua.execute(r'''
    -- Native vectors throw on invalid numeric indexes. Keep this local to the adapter mock.
    local loose_vec=vec
    function vec(values)
     local v=loose_vec(values);local mt=getmetatable(v);local get=mt.__index
     mt.__index=function(self,key)
      if type(key)=='number' and (key<0 or key>=#self)then error('vector index out of bounds')end
      return get(self,key)
     end
     return v
    end
    df={job_type={ConstructBed=10,PrepareMeal=11,MakeCharcoal=12,CustomReaction=13},workshop_type={Carpenters=0,Kitchen=1,Still=2},furnace_type={WoodFurnace=0},building_type={Workshop=0,Furnace=1},
     item_type=enum({'BED','WOOD','BAR'}),logic_condition_type=enum({'AtLeast','AtMost','GreaterThan','LessThan','Exactly','Not'}),workquota_order_condition_type=enum({'Activated','Completed'}),
     workquota_frequency_type=enum({'OneTime','Daily','Monthly','Seasonally','Yearly'}),entity_position_responsibility={MANAGE_PRODUCTION=4},civzone_type={Office=4}}
    local function allocation(v)
     v.assign=function(self,data)for k,x in pairs(data)do self[k]=x end end
     v.delete=function(self)assert(not self.deleted,'double free');self.deleted=true end
     return v
    end
    function condition()
     return allocation{compare_type=0,compare_val=0,item_type=-1,item_subtype=-1,mat_type=-1,mat_index=-1,flags1=bits{},flags2=bits{},flags3=bits{},flags4=0,flags5=0,reaction_class='',has_material_reaction_product='',metal_ore=-1,min_dimension=-1,reaction_id=-1,has_tool_use=-1,dye_color=-1,contains=vec{}}
    end
    df.manager_order_condition_item={new=function()return condition()end}
    df.manager_order_condition_order={new=function()return allocation{order_id=-1,condition=1,flags=bits{'satisfied'}}end}
    df.manager_order={new=function()return allocation{id=-1,job_type=10,item_type=-1,item_subtype=-1,reaction_name='',mat_type=-1,mat_index=-1,amount_left=0,amount_total=0,status=bits{'validated','active'},material_category={whole=0},specflag={whole=0,encrust_flags={whole=0}},specdata={hist_figure_id=-1},art_spec={type=0,id=-1,subid=-1},frequency=0,finished_year=-1,finished_year_tick=-1,workshop_id=-1,max_workshops=0,item_conditions=vec{},order_conditions=vec{}}end}
    local orders=vec{}
    df.global={world={manager_orders={all=orders,manager_order_next_id=0},jobs={list={}},units={active=vec{}},buildings={all=vec{},other={ACTIVITY_ZONE=vec{}}},raws={reactions={reactions=vec{}}}},plotinfo={civ_id=0,group_id=0},game={main_interface={job_details={open=false},image_creator={ics={}},info={work_orders={conditions={open=false,condition_wq=vec{}},entering_number=false,b_entering_number=false}}}}}
    df.historical_entity={find=function()return nil end};df.building={find=function()return nil end}
    df.building_workshopst={is_instance=function()return false end};df.building_furnacest=df.building_workshopst
    dfhack={df2utf=function(s)return s end,job={getManagerOrderName=function(o)return 'Bed order '..o.id end},units={},buildings={},maps={}}
    package.preload['dfhack.workshops']=function()return {jobs_workshop={[0]={{name='make bed',job_fields={job_type=10}}},[1]={{name='meal',job_fields={job_type=11,mat_type=2}}}},jobs_furnace={[0]={{name='charcoal',job_fields={job_type=12}}}}}end
    seq=0
    function request(action,extra)
     local a={id=-1,expected_revision=0,recipe='',query='',cursor=0,remaining=-1,frequency=-1,workshop_id=-2,max_workshops=-1,condition_kind=0,condition_index=-1,remove_condition=false,compare=-1,threshold=-1,item_type=-1,target_order=-1,dependency=-1,candidate_kind=0}
     for k,v in pairs(extra or {})do a[k]=v end
     seq=seq+1;return {action=action,seq=seq,epoch=test_epoch or 0,work_order=a}
    end
    ''')
    helper = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/work_orders.lua").read_text())
    def call(action, **fields):
        capacity = fields.pop("retire_capacity", 0)
        req = lua.globals().request(action, lua.table_from(fields))
        req["retire_capacity"] = capacity
        while True:
            result = helper(req)
            assert 0 <= (result["steps"] or 0) <= 2048
            if not result["pending"]:
                return result
    def observed(order_id):
        result = call(21, id=order_id)
        assert result["ok"], result["message"]
        assert len(result["orders"]) == 1
        return result["orders"][1]
    def edit(action, order_id, **fields):
        return call(action, id=order_id, expected_revision=observed(order_id)["revision"], **fields)
    def built(action=27, **fields):
        result = call(action, **fields)
        for _ in range(10000):
            assert not result["pending"]
            if not result["build_phase"] or result["build_phase"] == 0:
                return result
            advanced = helper(lua.table_from({"step": 2048}))
            assert advanced["steps"] <= 2048
            result = call(action, **fields)
        raise AssertionError("builder did not finish")
    missing = helper(lua.table_from({"action":26,"seq":-1}))
    assert not missing["ok"] and missing["message"] == "Work order request missing"
    progress = call(27)
    assert progress["ok"] and progress["build_phase"] == 1 and progress["build_done"] == 0
    catalog = built()
    assert catalog["ok"] and len(catalog["tasks"]) == 5, catalog["message"]
    assert len(catalog["managers"]) == 0
    recipe = next(row["key"] for row in catalog["tasks"].values() if row["job_type"] == 10)
    assert recipe == "0:1:a0:0:0:1:/1:21:0"  # same produced key as the host/Godot fixture
    assert 0 < catalog["list_revision"] <= 2**63-1
    assert call(27, expected_list_revision=catalog["list_revision"] + 1)["message"] == "List changed; refresh"
    first = call(22, recipe=recipe, remaining=5)["orders"][1]
    assert first["id"] == 0 and first["total"] == 5 and not first["validated"] and not first["active"]
    stale = first["revision"]
    lua.execute("o=df.global.world.manager_orders.all[0];o.amount_left=3;o.status.validated=true;o.status.active=true")
    native = observed(0)
    assert native["validated"] and native["active"]
    rejected = call(23, id=0, expected_revision=stale, remaining=7)
    assert not rejected["ok"] and rejected["message"] == "Work order changed; inspect again before editing"
    assert edit(23, 0, remaining=6)["message"] == 'This batch has started; settings are read only to preserve completed work'
    assert edit(23, 0, frequency=1)["message"] == 'This batch has started; settings are read only to preserve completed work'
    assert not observed(0)["editable"] and observed(0)["remaining"] == 3
    assert "batch has started" in observed(0)["reason"]
    assert edit(23, 0, remaining=6)["message"] == observed(0)["reason"]
    lua.execute("df.global.world.manager_orders.all[0].amount_left=5")
    assert edit(23, 0, remaining=6)["orders"][1]["total"] == 6
    assert not observed(0)["validated"] and not observed(0)["active"]
    lua.execute("df.global.world.manager_orders.all[0].amount_left=3")
    assert edit(23, 0, remaining=0)["message"] == 'This batch has started; settings are read only to preserve completed work'
    lua.execute("df.global.world.manager_orders.all[0].amount_left=6")
    second = call(22, recipe=recipe, remaining=0)["orders"][1]["id"]
    assert observed(second)["total"] == 0
    lua.execute("df.global.world.manager_orders.all[1].status.validated=true;df.global.world.manager_orders.all[1].status.active=true")
    assert edit(25, second, compare=3, threshold=100, item_type=0)["ok"]
    assert not observed(second)["validated"] and not observed(second)["active"]
    condition = observed(second)["conditions"][1]
    assert condition["index"] == 0 and condition["editable"]
    assert condition["kind"] == 0 and condition["compare"] == 3 and condition["threshold"] == 100
    assert condition["item_type"] == 0 and condition["description"] == "BED LessThan 100"
    assert edit(25, second, condition_kind=1, target_order=0, dependency=1)["ok"]
    cycle = edit(25, 0, condition_kind=1, target_order=second, dependency=0)
    assert not cycle["ok"] and cycle["message"] == "Dependency target missing or would form a cycle"
    duplicate = edit(25, second, condition_kind=1, target_order=0, dependency=1)
    assert not duplicate["ok"] and duplicate["message"] == "Duplicate order dependency"
    self_target = edit(25, second, condition_kind=1, target_order=second, dependency=0)
    assert not self_target["ok"] and self_target["message"] == "Dependency target missing or would form a cycle"
    dep = observed(second)["conditions"][2]
    assert dep["kind"] == 1 and dep["target_order"] == 0 and dep["dependency"] == 1 and not dep["satisfied"]
    assert edit(24, 0)["message"] == 'Deleted-order capacity reached; restart DF'
    assert edit(25, second, condition_kind=1, condition_index=0, remove_condition=True)["message"] == 'Deleted-order capacity reached; restart DF'
    assert len(observed(second)["conditions"]) == 2  # never frees borrowed storage
    lua.execute("o=df.global.world.manager_orders.all[0];local f=condition();f.quantity=2;f.vector_id=0;f.reagent_index=-1;f.job_details_flags=bits{};f.job_details_item_flags2=bits{};f.job_details_mat_type=-1;f.job_details_mat_index=-1;o.items={elements=vec{f},delete=function(s)s.deleted=true end}")
    before = observed(0)["revision"]
    lua.execute("df.global.world.manager_orders.all[0].items.elements[0].contains:insert('#',3)")
    assert call(23, id=0, expected_revision=before, max_workshops=2)["message"] == 'Work order changed; inspect again before editing'
    assert edit(23, 0, max_workshops=2)["orders"][1]["max_workshops"] == 2
    assert lua.eval("df.global.world.manager_orders.all[0].items.elements[0].contains[0]") == 3
    lua.execute("df.global.world.jobs.list.next={item={id=7,order_id=0}}")
    assert not observed(0)["editable"]
    assert "outstanding jobs" in observed(0)["reason"]
    assert observed(0)["generated_jobs"][1] == 7
    assert edit(23, 0, remaining=4)["message"] == observed(0)["reason"]
    assert edit(23, 0, frequency=2)["message"] == 'Finish outstanding jobs before editing'
    assert edit(25, 0, condition_kind=0, item_type=0, compare=0, threshold=0)["message"] == 'Finish outstanding jobs before editing'
    assert edit(24, 0)["message"] == 'Deleted-order capacity reached; restart DF'
    assert edit(23, 0, remaining=4)["message"] == 'Finish outstanding jobs before editing'
    lua.execute("df.global.world.jobs.list.next=nil;df.global.game.main_interface=setmetatable({}, {__index=function()error('Native UI must not be read')end})")
    assert edit(23, 0, frequency=2)["ok"]  # in-place edits never consult panels
    assert edit(25, second, condition_index=0, item_type=0, compare=3, threshold=90)["ok"]
    assert edit(24, 0)["message"] == 'Deleted-order capacity reached; restart DF'
    assert edit(24, second)["message"] == 'Deleted-order capacity reached; restart DF'
    assert edit(25, second, condition_index=0, remove_condition=True)["message"] == 'Deleted-order capacity reached; restart DF'
    assert lua.eval("#df.global.world.manager_orders.all") == 2
    assert not lua.eval("df.global.world.manager_orders.all[0].deleted")
    assert len(observed(second)["conditions"]) == 2
    refusal = "Deleted-order capacity reached; restart DF"
    for result in [edit(24, 0), edit(25, second, condition_index=0, remove_condition=True)]:
        assert not result["ok"] and result["message"] == refusal
    for frequency in range(5):
        lua.execute("df.global.world.manager_orders.all[0].status.validated=true;df.global.world.manager_orders.all[0].status.active=true")
        row = edit(23, 0, frequency=frequency)["orders"][1]
        assert row["frequency"] == frequency and not row["validated"] and not row["active"]
    row = observed(second)["conditions"][1]
    assert row["threshold"] == 90 and row["compare"] == 3 and row["item_type"] == 0
    lua.execute("df.global.world.manager_orders.all[1].item_conditions[0].mat_type=2")
    custom = observed(second)["conditions"][1]
    assert custom["editable"] and custom["mat_type"] == 2
    result = edit(25, second, condition_index=0, item_type=0, compare=0, threshold=1)
    assert result["ok"] and result["orders"][1]["conditions"][1]["threshold"] == 1
    assert lua.eval("df.global.world.manager_orders.all[1].item_conditions[0].mat_type") == -1
    lua.execute(r'''
    df.workshop_type[0]='Carpenters';df.workshop_type[1]='Kitchen'
    local function shop(id,kind)
     return {id=id,type=kind,centerx=id,centery=0,z=0,workshop=true,
      getBuildStage=function()return 3 end,getMaxBuildStage=function()return 3 end}
    end
    df.global.world.buildings.all=vec{shop(4,0),shop(5,1),shop(6,0)}
    df.building.find=function(id)for _,b in ipairs(df.global.world.buildings.all)do if b.id==id then return b end end end
    df.building_workshopst={is_instance=function(_,b)return b.workshop end}
    df.building_furnacest={is_instance=function()return false end}
    dfhack.maps.getTileFlags=function(p)return {hidden=false},{building=0}end
    dfhack.buildings.getName=function(b)return b.type==0 and "Carpenter's Workshop" or "Kitchen" end
    ''')
    assert observed(0)["workshop_id"] == -1
    assert call(22, recipe=recipe, remaining=1, workshop_id=5)["message"] == 'Selected workshop cannot service this recipe'
    bound = call(22, recipe=recipe, remaining=7, frequency=3, workshop_id=4, max_workshops=2)["orders"][1]
    assert bound["workshop_id"] == 4 and bound["frequency"] == 3 and bound["max_workshops"] == 2
    assert bound["total"] == 7 and bound["remaining"] == 7 and not bound["validated"] and not bound["active"]
    assert edit(23, bound["id"], workshop_id=5)["message"] == 'Workshop restriction unsupported for this order'
    assert edit(23, bound["id"], workshop_id=6)["orders"][1]["workshop_id"] == 6
    assert edit(23, bound["id"], workshop_id=-1, max_workshops=0)["orders"][1]["workshop_id"] == -1
    assert observed(bound["id"])["max_workshops"] == 0
    shops = call(26, candidate_kind=1, query="carpenter", cursor=5)
    assert shops["ok"] and len(shops["choices"]) == 1 and shops["next_cursor"] == 0
    assert shops["choices"][1]["id"] == 6 and shops["choices"][1]["name"] == "Carpenter's Workshop #6"
    items = call(26, candidate_kind=2, query="bar", cursor=1)
    assert items["ok"] and len(items["choices"]) == 1 and items["next_cursor"] == 0
    assert items["choices"][1]["id"] == 2 and items["choices"][1]["name"] == "BAR #2"
    # Replace with distinct identities for deterministic paging across incremental scans.
    lua.execute("df.global.world.manager_orders.all=vec{}")
    lua.execute("for id=1100,1,-1 do local o=df.manager_order:new();o.id=id;o.amount_total=2;o.amount_left=2;df.global.world.manager_orders.all:insert('#',o)end")
    page = call(20)
    assert len(page["orders"]) == 16 and page["orders"][1]["id"] == 1100 and page["orders"][16]["id"] == 1085
    assert page["next_cursor"] == 16
    next_page = call(20, cursor=page["next_cursor"])
    assert len(next_page["orders"]) == 16 and next_page["orders"][1]["id"] == 1084 and next_page["next_cursor"] == 32
    page = call(20, query="1100")
    assert page["orders"][1]["id"] == 1100
    assert len(page["orders"]) == 1 and page["next_cursor"] == 0
    choices = call(26, candidate_kind=0)
    assert len(choices["choices"]) == 128 and choices["next_cursor"] == 129
    filtered = call(26, candidate_kind=0, query="1100", cursor=1000)
    assert len(filtered["choices"]) == 1 and filtered["choices"][1]["name"] == "Bed order 1100 #1100"
    assert filtered["next_cursor"] == 0
    page = call(26, cursor=1000)
    assert page["choices"][1]["id"] == 1000 and len(page["choices"]) == 101
    lua.execute("df.global.world.units.active=vec{{id=7,job={}}};dfhack.units.isCitizen=function()return true end;dfhack.units.isActive=function()return true end;dfhack.units.isDead=function()return false end;dfhack.units.getReadableName=function()return 'Manager' end;dfhack.units.getNoblePositions=function()return {{entity={id=0},assignment={id=0},position={name={[0]='Manager'},responsibilities={[4]=true}}}}end;df.global.world.buildings.other.ACTIVITY_ZONE=vec{{id=3,type=4,assigned_unit_id=7}}")
    manager = call(27)["managers"][1]
    assert manager["unit_id"] == 7 and manager["offices"][1] == 3
    assert manager["name"] == "Manager" and manager["position"] == "Manager" and manager["job"] == "No current job"
    lua.execute("df.global.world.units.active[0].job.current_job={};dfhack.job.getName=function()return 'Validate work orders' end")
    assert call(27)["managers"][1]["job"] == "Validate work orders"
    # Mutations use isolated semantic identities and explicit retirement capacity.
    lua.execute("df.global.world.manager_orders.all=vec{};df.global.world.manager_orders.manager_order_next_id=0;df.global.world.units.active=vec{}")
    ids = [call(22, recipe=recipe)["orders"][1]["id"] for _ in range(18)]
    page = call(20)
    assert page["total"] == 18 and [r["position"] for r in page["orders"].values()] == list(range(16))
    call(22, recipe=recipe)
    assert call(20, cursor=16, expected_list_revision=page["list_revision"])["message"] == "List changed; refresh"
    assert call(20, cursor=16)["orders"][1]["position"] == 16
    # Independently calculate the full unsigned FNV, including a high-bit fixture.
    def fnv(values):
        h = 0xcbf29ce484222325
        for value in values:
            for byte in value.to_bytes(8, "little"):
                h = ((h ^ byte) * 0x100000001b3) & (2**64 - 1)
        return h
    high_seen = False
    for count in range(1, 20):
        lua.execute("df.global.world.manager_orders.all=vec{};for i=0,...-1 do local o=df.manager_order:new();o.id=i;df.global.world.manager_orders.all:insert('#',o)end", count)
        raw = fnv([count] + list(range(count)))
        actual = call(20)["list_revision"]
        assert actual == ((raw & (2**63 - 1)) or 1) and 1 <= actual <= 2**63 - 1
        high_seen |= raw >= 2**63
    assert high_seen
    lua.execute("df.global.world.manager_orders.all:resize(3);df.global.world.manager_orders.all[0].status.validated=true;df.global.world.manager_orders.all[0].status.active=true;df.global.world.jobs.list.next={item={id=77,order_id=0}}")
    rev = observed(0)["revision"]
    listing = call(20)["list_revision"]
    for fields in ({}, {"expected_list_revision": listing + 1}):
        assert call(23, id=0, expected_revision=rev, move=1, expected_neighbor=1, **fields)["message"] == "List changed; refresh"
    assert call(23, id=0, expected_revision=rev, move=1, expected_neighbor=2, expected_list_revision=listing)["message"] == "Neighbor changed; inspect again"
    assert edit(23, 0, move=-1, expected_neighbor=1, expected_list_revision=listing)["message"] == "Neighbor changed; inspect again"
    assert edit(23, 2, move=1, expected_neighbor=1, expected_list_revision=listing)["message"] == "Neighbor changed; inspect again"
    move_reply = edit(23, 0, move=1, expected_neighbor=1, expected_list_revision=listing)
    assert move_reply["ok"] and move_reply["orders"] is None
    moved = observed(0)
    assert moved["position"] == 1 and moved["validated"] and moved["active"] and moved["revision"] == rev
    assert edit(23, 0, move=-1, expected_neighbor=1, expected_list_revision=call(20)["list_revision"])["ok"]
    assert observed(0)["position"] == 0 and observed(0)["generated_jobs"][1] == 77
    assert edit(25, 1, compare=0, threshold=1, item_type=-1)["ok"]
    assert observed(1)["frequency"] == 1
    assert edit(25, 1, condition_kind=1, target_order=0, dependency=1)["ok"]
    dep = observed(1)["conditions"][2]
    assert dep["satisfaction"] == 2 and not dep["estimated"]
    assert dep["description"] == "Order #0 Completed; Not satisfied for next check"
    lua.execute("df.global.world.manager_orders.all[1].order_conditions[0].flags.satisfied=true")
    assert observed(1)["conditions"][2]["description"] == "Order #0 Completed; Satisfied for next check"
    before = observed(1)["revision"]
    assert call(24, id=0, expected_revision=rev+100, retire_capacity=3)["message"] == "Work order changed; inspect again before editing"
    assert call(24, id=999, expected_revision=1, retire_capacity=3)["message"] == "Work order no longer exists"
    assert edit(24, 0, retire_capacity=1)["message"] == refusal
    assert observed(1)["revision"] == before and call(20)["total"] == 3
    deleted = edit(24, 0, retire_capacity=2)
    assert deleted["ok"] and len(deleted["retired"]) == 2
    assert all(not obj["deleted"] for obj in deleted["retired"].values())
    assert len(observed(1)["conditions"]) == 1 and observed(1)["conditions"][1]["kind"] == 0
    assert lua.eval("df.global.world.jobs.list.next.item.order_id") == 0
    lua.execute("df.global.world.jobs.list.next=nil")
    for kind in (0, 1):
        if kind == 1:
            assert edit(25, 1, condition_kind=1, target_order=2, dependency=0)["ok"]
        for index in (1, 65535):
            assert edit(25, 1, condition_kind=kind, condition_index=index, remove_condition=True, retire_capacity=1)["message"] == "Condition identity changed"
        rev = observed(1)["revision"]
        assert call(25, id=1, expected_revision=rev+100, condition_kind=kind, condition_index=0, remove_condition=True, retire_capacity=1)["message"] == 'Work order changed; inspect again before editing'
        assert observed(1)["revision"] == rev
        removed = edit(25, 1, condition_kind=kind, condition_index=0, remove_condition=True, retire_capacity=1)
        assert removed["ok"] and len(removed["retired"]) == 1 and not removed["retired"][1]["deleted"]
    assert len(observed(1)["conditions"]) == 0

    assert edit(23, 1, frequency=2)["ok"]  # Monthly survives its first item condition.
    assert edit(25, 1, compare=0, threshold=1, item_type=-1)["ok"]
    assert observed(1)["frequency"] == 2

    # Synthetic simulation raws, never native UI template tables. Numeric values
    # are deliberately different from live enums to catch hard-coded identities.
    lua.execute(r'''
    df.workshop_type=enum({'Carpenters','Farmers','Masons','Craftsdwarfs','Jewelers','MetalsmithsForge','MagmaForge','Bowyers','Mechanics','Siege','Butchers','Leatherworks','Tanners','Clothiers','Fishery','Still','Loom','Quern','Kennels','Kitchen','Ashery','Dyers','Millstone','Custom','Tool'})
    df.furnace_type=enum({'WoodFurnace','Smelter','GlassFurnace','Kiln'})
    df.job_type=enum({'ConstructBed','PrepareMeal','MakeCharcoal','CustomReaction','MakeWeapon','MakeArmor','MakeEarring','EncrustWithGems','EncrustWithGlass','EncrustWithStones','MakeTool','SmeltOre','ExtractMetalStrands','ConstructBag','SewImage','WeaveCloth'})
    df.item_type=enum({'BED','WOOD','BAR','WEAPON','ARMOR','TOOL'})
    df.builtin_mats={AMBER=1,SALT=14,GLASS_GREEN=3,GLASS_CLEAR=4,GLASS_CRYSTAL=5}
    df.global.world.manager_orders.all=vec{}
    df.global.world.units.active=vec{}
    local raws=df.global.world.raws
    local function inorganic(id,flags,ores,threads)
     return {id=id,material={flags=flags,reaction_class=vec{{value='SYNTH'}},reaction_product={id=vec{{value='PRODUCT'}}}},metal_ore={mat_index=vec(ores)},thread_metal={mat_index=vec(threads)}}
    end
    raws.inorganics={all=vec{inorganic('IRON',{IS_METAL=true,ITEMS_HARD=true,ITEMS_METAL=true,ITEMS_WEAPON=true,ITEMS_ARMOR=true}),
     inorganic('COPPER',{IS_METAL=true,ITEMS_HARD=true,ITEMS_METAL=true,ITEMS_WEAPON=true}),inorganic('GEM',{}),
     inorganic('ORE',{}, {0}),inorganic('THREAD_ORE',{}, {}, {0})}}
    raws.plants={all=vec{{material=vec{{flags={THREAD_PLANT=true},reaction_class=vec{},reaction_product={id=vec{}}},{flags={WOOD=true},reaction_class=vec{},reaction_product={id=vec{}}}}}}}
    raws.creatures={all=vec{{material=vec{{flags={LEATHER=true},reaction_class=vec{},reaction_product={id=vec{}}},{flags={BONE=true},reaction_class=vec{},reaction_product={id=vec{}}}}}}}
    raws.buildings={all=vec{{id=0,name="Soap Maker's Workshop",building_type=0,building_subtype=23},
     {id=1,name='Screw Press',building_type=0,building_subtype=23}}}
    defs={
     [df.item_type.WEAPON]=vec{{id='AXE',name='axe',flags={},skill_ranged=-1},
       {id='BOW',name='bow',flags={},skill_ranged=0},{id='TRAIN',name='training axe',flags={TRAINING=true},skill_ranged=-1}},
     [df.item_type.ARMOR]=vec{{id='MAIL',name='mail',props={flags={METAL=true}}},
       {id='ROBE',name='robe',props={flags={SOFT=true,LEATHER=true}}}},
     [df.item_type.TOOL]=vec{{id='JUG',name='jug',flags={HARD_MAT=true}},
       {id='REACT_ONLY',name='reaction tool',flags={HARD_MAT=true,NO_DEFAULT_JOB=true}}}}
    dfhack.items={getSubtypeCount=function(t)return #(defs[t] or {})end,
     getSubtypeDef=function(t,sub)return defs[t] and defs[t][sub]end}
    dfhack.matinfo={decode=function(mt,mi)return {toString=function()return 'material '..mt..':'..mi end}end}
    df.tool_uses=enum({'HAMMER'});raws.descriptors={colors=vec{}}
    entity={id=42,entity_raw={equipment={weapon_id=vec{0,1,2},digger_id=vec{0},armor_id=vec{0,1},tool_id=vec{0,1}},
     workshops={permitted_building_id=vec{0,1},permitted_reaction_id=vec{0,1}}}}
    entity.resources={weapon_type=vec{0,1},digger_type=vec{0},training_weapon_type=vec{2},armor_type=vec{0,1},tool_type=vec{0,1}}
    df.historical_entity.find=function()return entity end
    function reaction(code,custom,source)
     return {code=code,name=code,source_enid=source or -1,building={type=vec{0},subtype=vec{23},custom=vec{custom}},flags={}}
    end
    raws.reactions.reactions=vec{reaction('PRESS',1),reaction('SOAP',0),reaction('FORBIDDEN',0),reaction('CIV_GENERATED',1,42)}
    dfhack.job.getManagerOrderName=function(o)
     return string.format('%s/%d/%d/%d/%d/%d/%s',df.job_type[o.job_type],o.item_subtype,o.mat_type,o.mat_index,o.material_category.whole,o.specflag.encrust_flags.whole,o.reaction_name)
    end
    ''')
    source = (Path(__file__).resolve().parents[1] / "bridge/plugin/work_orders.lua").read_text()
    helper = lua.execute(source)
    # Numeric flag words model DF's bitfield whole assignment (the generic
    # prelude's named-bit helper intentionally does not implement this operation).
    lua.execute(r"""
    local old=condition
    function condition()
     local c=old();c.flags1={whole=0};c.flags2={whole=0};c.flags3={whole=0};return c
    end
    df.job_item={new=function()return condition()end}
    df.global.cur_year=7;df.global.cur_year_tick=403000
    df.items_other_id=enum({'IN_PLAY','ANY_ARTIFACT','WEAPON','BED','WOOD','BAR','TOOL','ARMOR'})
    df.global.world.items={all=vec{},other={[df.items_other_id.IN_PLAY]=vec{}}}
    function sample_item(flag,match,stack)
     return {flags=flag or {},getType=function()return match and 3 or 0 end,
      getSubtype=function()return 0 end,getMaterial=function()return 0 end,
      getMaterialIndex=function()return 0 end,getStackSize=function()return stack or 1 end}
    end
    dfhack.job.isSuitableItem=function(f,t,sub)return t==3 and f.item_subtype==sub end
    dfhack.job.isSuitableMaterial=function(f,t,i,item_type)return t==f.mat_type and i==f.mat_index end
    local o=df.manager_order:new();o.id=0;df.global.world.manager_orders.all=vec{o}
    df.global.world.raws.descriptors.colors=vec{{}}
    """)
    keys = [f"f{word}:31" for word in range(1,6)] + ["rc:SYNTH", "rp:PRODUCT", "ore:3", "tool:0", "dye:0"]
    changed = edit(25, 0, compare=0, threshold=2, item_type=3, item_subtype=0, mat_type=0, mat_index=0, traits=lua.table_from(keys))
    assert changed["ok"], changed["message"]
    row = observed(0)["conditions"][1]
    assert (row["item_subtype"], row["mat_type"], row["mat_index"]) == (0,0,0)
    assert set(row["traits"].values()) == set(keys)
    rev = observed(0)["revision"]
    assert edit(25, 0, condition_index=0, item_type=-1, compare=0, threshold=0, traits=lua.table_from(["unknown:x"]))["message"] == 'Unknown condition trait'
    assert observed(0)["revision"] == rev
    assert edit(25, 0, condition_index=0, item_type=-1, compare=0, threshold=0)["ok"]
    reset_row = observed(0)["conditions"][1]
    assert (reset_row["item_subtype"], reset_row["mat_type"], reset_row["mat_index"]) == (-1,-1,-1)
    assert set(reset_row["traits"].values()) == set(keys)
    assert edit(25, 0, condition_index=0, item_type=3, item_subtype=0, mat_type=0, mat_index=0, compare=0, threshold=2, traits=lua.table_from([]))["ok"]
    assert len(observed(0)["conditions"][1]["traits"]) == 0
    lua.execute("df.global.world.items.other[df.items_other_id.WEAPON]=vec{sample_item({},true,2),sample_item({forbid=true},true),sample_item({dump=true},true),sample_item({in_job=true},true),sample_item({owned=true},true),sample_item({},false),sample_item({removed=true},true,11),sample_item({garbage_collect=true},true,13)}")
    description_before_estimate = observed(0)["conditions"][1]["description"]
    advanced = helper(lua.table_from({"step":2048}))
    assert advanced["steps"] == 8 and advanced["active_kinds"] == 0
    row = observed(0)["conditions"][1]
    assert row["satisfaction"] == 2 and row["estimated"] and row["estimate_count"] == 2 and row["satisfied"]
    assert row["description"] == description_before_estimate
    assert "DF3D estimate" not in row["description"]
    # The same condition through IN_PLAY sees exactly the live subset.
    lua.execute("df.items_other_id.WEAPON=nil;df.global.world.items.other[df.items_other_id.IN_PLAY]=vec{sample_item({},true,2)}")
    assert edit(25, 0, condition_index=0, item_type=3, item_subtype=0, mat_type=0, mat_index=0, compare=0, threshold=2)["ok"]
    helper(lua.table_from({"step":2048}))
    assert observed(0)["conditions"][1]["estimate_count"] == 2
    lua.execute("df.items_other_id.WEAPON=2")
    lua.execute("df.global.cur_year=8;df.global.cur_year_tick=1000")
    assert observed(0)["conditions"][1]["satisfaction"] == 2  # exactly 1200, crossing a year
    lua.execute("df.global.cur_year_tick=1001")
    assert observed(0)["conditions"][1]["satisfaction"] == 1
    helper(lua.table_from({"step":2048}))
    assert edit(23, 0, frequency=2)["orders"][1]["conditions"][1]["satisfaction"] == 1
    # The enum values intentionally disagree: WEAPON item_type=3, other_id=2.
    # Generic and unmapped types both scan IN_PLAY, never items.all.
    lua.execute("df.global.world.items.other[df.items_other_id.IN_PLAY]=vec{sample_item({},true,7)};df.global.world.items.all=vec{sample_item({},true,99)}")
    for item_type in (-1, 3):
        if item_type == 3:
            lua.execute("df.items_other_id.WEAPON=nil")
        assert edit(25, 0, condition_index=0, item_type=item_type, item_subtype=0 if item_type>=0 else -1, mat_type=0, mat_index=0, compare=0, threshold=2)["ok"]
        lua.execute("saved_suitable=dfhack.job.isSuitableItem;dfhack.job.isSuitableItem=function()return true end")
        helper(lua.table_from({"step":2048,"builder_kind":2}))
        assert observed(0)["conditions"][1]["estimate_count"] == 7
        lua.execute("dfhack.job.isSuitableItem=saved_suitable")
    lua.execute("df.items_other_id.WEAPON=2")
    # A filter is allocated once, retained across updates, and freed on every exit.
    lua.execute(r"""
    filter_new,filter_deleted,revision_reads=0,0,0
    df.job_item.new=function()
     filter_new=filter_new+1;local f=condition();local delete=f.delete
     f.delete=function(self)filter_deleted=filter_deleted+1;delete(self)end;return f
    end
    local o=df.global.world.manager_orders.all[0];local reaction=o.reaction_name;o.reaction_name=nil
    setmetatable(o,{__index=function(_,key)if key=='reaction_name' then revision_reads=revision_reads+1;return reaction end end})
    df.global.world.items.other[df.items_other_id.WEAPON]=vec{sample_item({},true),sample_item({},true),sample_item({},true)}
    """)
    assert edit(25, 0, condition_index=0, item_type=3, item_subtype=0, mat_type=0, mat_index=0, compare=0, threshold=2)["ok"]
    lua.execute("revision_reads=0")
    assert helper(lua.table_from({"step":2,"builder_kind":2}))["steps"] == 2
    assert lua.eval("filter_new==1 and filter_deleted==0 and revision_reads==1")
    helper(lua.table_from({"step":2048,"builder_kind":2}))
    assert lua.eval("filter_new==1 and filter_deleted==1 and revision_reads==2")
    assert edit(23, 0, frequency=1)["ok"]
    helper(lua.table_from({"step":1,"builder_kind":2}))
    assert lua.eval("filter_new==2 and filter_deleted==1")
    assert edit(23, 0, frequency=2)["ok"]
    assert lua.eval("filter_deleted==2")
    helper(lua.table_from({"step":1,"builder_kind":2}))
    helper(lua.table_from({"cancel_builders":True}))
    assert lua.eval("filter_new==filter_deleted")
    # A throwing item drops its estimate and releases its filter; later entries finish.
    lua.execute("df.global.world.manager_orders.all=vec{};for id=0,1 do local o=df.manager_order:new();o.id=id;local c=condition();c.item_type=3;c.item_subtype=0;c.mat_type=0;c.mat_index=0;o.item_conditions:insert('#',c);df.global.world.manager_orders.all:insert('#',o)end")
    observed(0);observed(1)
    lua.execute("saved_suitable=dfhack.job.isSuitableItem;local first=true;dfhack.job.isSuitableItem=function(...)if first then first=false;error('bad item')end;return saved_suitable(...)end")
    advanced=helper(lua.table_from({"step":2048,"builder_kind":2}))
    assert advanced["active_kinds"] == 0
    assert observed(1)["conditions"][1]["satisfaction"] == 2
    assert observed(0)["conditions"][1]["satisfaction"] == 1
    assert lua.eval("filter_new==filter_deleted")
    lua.execute("dfhack.job.isSuitableItem=saved_suitable")
    # Oldest of 65 queued estimates is discarded; only 64 item scans run.
    lua.execute("df.global.world.items.other[df.items_other_id.IN_PLAY]=vec{sample_item({},false)};df.global.world.manager_orders.all=vec{};for i=0,64 do local o=df.manager_order:new();o.id=i;o.item_conditions:insert('#',condition());df.global.world.manager_orders.all:insert('#',o)end")
    helper = lua.execute(source)
    for oid in range(65):
        assert observed(oid)["conditions"][1]["satisfaction"] == 1
    advanced = helper(lua.table_from({"step":2048}))
    assert advanced["steps"] == 64 and advanced["active_kinds"] == 0
    assert observed(64)["conditions"][1]["satisfaction"] == 2
    assert observed(0)["conditions"][1]["satisfaction"] == 1
    # A scan that outlives its start-tick window cannot publish a known result.
    helper(lua.table_from({"step":1}))
    lua.execute("df.global.cur_year_tick=df.global.cur_year_tick+1201")
    helper(lua.table_from({"step":2048}))
    assert observed(0)["conditions"][1]["satisfaction"] == 1
    lua.execute("df.global.world.manager_orders.all=vec{};df.global.world.raws.descriptors.colors=vec{}")
    families = {"CustomReaction":1,"SmeltOre":1,"TanAHide":1,"MeltMetalObject":1,
                "ConstructBag":2,"ConstructDoor":2,"ConstructTable":2,"ConstructBed":2,
                "ProcessPlants":3,"MillPlants":3,"MakeArmor":4,"MakeHelm":4,"MakeGloves":4,
                "MakeShoes":4,"MakePants":4,"EncrustWithGems":5,"EncrustWithGlass":5,"EncrustWithStones":5,"Unknown":0}
    # Local enum additions are restored before the catalog fixture runs.
    lua.execute("saved_jobs=df.job_type;df.job_type={}")
    for oid, (name, kind) in enumerate(families.items()):
        lua.execute("local id,name=...;df.job_type[id]=name;df.job_type[name]=id;local o=df.manager_order:new();o.id=id;o.job_type=id;df.global.world.manager_orders.all:insert('#',o)",oid,name)
        row = observed(oid)
        assert row["detail_kind"] == kind and len(row["inputs"]) == 0
        assert edit(23, oid, input_index=0, mat_type=0, mat_index=0)["message"] == 'Order has no editable material input'
        lua.execute("local o=df.global.world.manager_orders.all[...];local f=condition();f.job_details_flags=bits{'have_set_job_details'};f.job_details_item_flags2=bits{};f.job_details_mat_type=-1;f.job_details_mat_index=-1;o.items={elements=vec{f}}",oid)
        for index in (1, 32767):
            assert edit(23, oid, input_index=index, mat_type=0, mat_index=0)["message"] == "Order has no editable material input"
        if kind in (0,1):
            assert edit(23, oid, input_index=0, mat_type=0, mat_index=0)["message"] == "Order has no editable material input"
        if kind in (2,3,5):
            for flags in ((1, 1093) if kind == 5 else (0, 4)):
                assert edit(23, oid, input_index=0, encrust_flags=flags)["message"] == "Invalid gem decoration flags"
            assert edit(23, oid, input_index=0, mat_type=0, mat_index=0, frequency=1)["message"] == 'Details must be an exclusive update'
            result = edit(23, oid, input_index=0, mat_type=0, mat_index=0, **({"encrust_flags":1092} if kind==5 else {}))
            assert result["ok"] and result["orders"][1]["inputs"][1]["mat_type"] == 0
        if kind == 4:
            assert edit(23, oid, input_index=0, mat_type=0, mat_index=0)["message"] == 'Order has no editable material input'
            lua.execute("local o=df.global.world.manager_orders.all[...];o.material_category.cloth=true;o.specdata.hist_figure_id=42",oid)
            assert observed(oid)["detail_kind"] == 6 and observed(oid)["size_raw"] == 42
            for flags in (0, 4):
                refused = edit(23, oid, input_index=0, encrust_flags=flags)
                assert not refused["ok"] and refused["message"] == "Invalid gem decoration flags"
            assert edit(23, oid, input_index=0, mat_type=0, mat_index=0)["ok"]
            assert observed(oid)["size_raw"] == 42
    lua.execute("df.job_type=saved_jobs;df.global.world.manager_orders.all=vec{}")
    helper = lua.execute(source)
    first_progress = call(27)
    assert first_progress["build_phase"] == 1 and first_progress["build_done"] == 0
    assert first_progress["build_total"] == 22
    one = helper(lua.table_from({"step": 1}))
    assert one["steps"] == 1 and one["active_kinds"] == 2
    catalog = built()
    assert catalog["ok"], catalog["message"]
    rows = list(catalog["tasks"].values())
    assert catalog["next_cursor"] == 0  # small synthetic fixture
    assert len(catalog["groups"]) == 29
    assert catalog["groups"][1]["name"] == "All tasks"
    assert catalog["groups"][1]["count"] == len(rows)
    assert sum(g["count"] for i, g in catalog["groups"].items() if i != 1) == len(rows)
    assert len({r["key"] for r in rows}) == len(rows)
    assert all(len(r["key"].encode()) <= 64 for r in rows)
    assert [r["name"] for r in rows] == sorted(r["name"] for r in rows)
    enum_job = lua.globals().df.job_type
    def family(name):
        return [r for r in rows if r["job_type"] == enum_job[name]]
    assert {r["reaction"] for r in family("CustomReaction")} == {"PRESS", "SOAP", "CIV_GENERATED"}
    assert {(r["item_subtype"], r["mat_index"]) for r in family("MakeWeapon") if r["mat_type"] == 0} == {(0, 0), (0, 1)}
    assert {(r["item_subtype"], r["mat_index"]) for r in family("MakeArmor") if r["mat_type"] == 0} == {(0, 0)}
    assert {(r["item_subtype"], r["material_category"]) for r in family("MakeArmor") if r["mat_type"] == -1} == {(1, 4), (1, 8), (1, 16), (1, 4096)}
    assert {r["encrust_flags"] for r in family("EncrustWithGems")} == {4, 64, 1024}
    assert {r["material_category"] for r in family("MakeEarring") if r["mat_type"] == -1} == {2, 4, 8, 16, 32, 64, 512, 1024, 2048, 4096}
    assert all(r["item_subtype"] == 0 for r in family("MakeTool"))
    assert {(r["mat_type"], r["mat_index"]) for r in family("SmeltOre")} == {(0, 3)}
    assert {(r["mat_type"], r["mat_index"]) for r in family("ExtractMetalStrands")} == {(0, 4)}
    press = built(group_type=0, group_subtype=23, group_custom=1)
    assert {r["reaction"] for r in press["tasks"].values()} == {"PRESS", "CIV_GENERATED"}
    # Shared applicability is one All-tasks row with membership in both groups.
    lua.execute("local r=df.global.world.raws.reactions.reactions[0];r.building.type:insert('#',0);r.building.subtype:insert('#',23);r.building.custom:insert('#',0)")
    helper = lua.execute(source)
    shared = built()
    assert shared["total"] == len(rows)
    assert sum(g["count"] for i, g in shared["groups"].items() if i != 1) == len(rows) + 1
    soap = built(group_type=0, group_subtype=23, group_custom=0)
    assert {r["reaction"] for r in soap["tasks"].values()} == {"PRESS", "SOAP"}
    lua.execute("local r=df.global.world.raws.reactions.reactions[0];r.building.type:erase(1);r.building.subtype:erase(1);r.building.custom:erase(1)")
    helper = lua.execute(source)
    built()
    # Native raw BUILDING membership: Farmer 7 jobs + 2 reactions, Still
    # extraction + 3 reactions; the two milling reactions also belong to Millstone.
    lua.execute(r"""
    group_saved_jobs=df.job_type;group_saved_reactions=df.global.world.raws.reactions.reactions
    df.job_type=enum({'CustomReaction','ProcessPlants','ProcessPlantsVial','ProcessPlantsBarrel',
      'MilkCreature','MakeCheese','ShearCreature','SpinThread','ExtractFromPlants','MillPlants'})
    local reactions={}
    for _,entry in ipairs{
      {'PROCESS_PLANT_TO_BAG','Farmers'},{'MAKE_SHEET_FROM_PLANT','Farmers'},
      {'BREW_DRINK_FROM_PLANT','Still'},{'BREW_DRINK_FROM_PLANT_GROWTH','Still'},
      {'MAKE_MEAD','Still'},{'MILL_SEEDS_NUTS_TO_PASTE','Quern'},{'MAKE_SLURRY_FROM_PLANT','Quern'}}do
     local r=reaction(entry[1],-1,42);r.building.subtype=vec{df.workshop_type[entry[2]]}
     if entry[2]=='Quern' then
      r.building.type:insert('#',0);r.building.subtype:insert('#',df.workshop_type.Millstone);r.building.custom:insert('#',-1)
     end
     reactions[#reactions+1]=r
    end
    df.global.world.raws.reactions.reactions=vec(reactions)
    """)
    helper = lua.execute(source)
    grouped = built()
    assert grouped["total"] == 16
    assert len({r["key"] for r in grouped["tasks"].values()}) == 16
    for name, count in (("Farmers", 9), ("Still", 4), ("Quern", 2), ("Millstone", 3)):
        page = built(group_type=0, group_subtype=lua.globals().df.workshop_type[name], group_custom=-1)
        assert page["total"] == count, (name, page["total"])
        jobs = {r["job_type"] for r in page["tasks"].values()}
        assert (lua.globals().df.job_type.ExtractFromPlants in jobs) == (name == "Still")
        assert (lua.globals().df.job_type.MillPlants in jobs) == (name == "Millstone")
    lua.execute("df.job_type=group_saved_jobs;df.global.world.raws.reactions.reactions=group_saved_reactions")
    helper = lua.execute(source)
    built()
    # Keys recreate every field, including collision-prone categories/encrust bits.
    selected = family("EncrustWithGems")[0]
    created = call(22, recipe=selected["key"])
    assert created["ok"], created["message"]
    order = created["orders"][1]
    assert order["remaining"] == order["total"] == 10 and order["frequency"] == 0
    assert not order["validated"] and not order["active"]
    assert order["encrust_flags"] == selected["encrust_flags"]
    assert call(22, recipe="absent")["message"] == "Recipe changed or is unavailable"
    for task in family("MakeEarring"):
        restored = call(22, recipe=task["key"])
        assert restored["ok"], restored["message"]
        result = restored["orders"][1]
        assert (result["material_category"], result["mat_type"], result["mat_index"]) == (task["material_category"], task["mat_type"], task["mat_index"])

    # Pass-2 native rule gaps: flags and civ permissions, never raw IDs/names.
    lua.execute(r"""
    saved_catalog={jobs=df.job_type,types=df.item_type,defs=defs,resources=entity.resources,
      inorganics=df.global.world.raws.inorganics.all,buildings=entity.entity_raw.workshops.permitted_building_id}
    local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
    df.job_type=copy(df.job_type);df.item_type=copy(df.item_type);defs=copy(defs)
    for _,name in ipairs{'ConstructDoor','ConstructMechanisms','StudWith','MakeScepter','MakeShield',
      'ConstructBallistaParts','ConstructCatapultParts','ConstructBoltThrowerParts'}do
     local id=df.job_type._last_item+1;df.job_type._last_item=id;df.job_type[name]=id;df.job_type[id]=name
    end
    df.item_type.SHIELD=6;defs[6]=vec{{id='SHIELD',name='shield'},{id='BUCKLER',name='buckler'}}
    defs[df.item_type.WEAPON]=vec{defs[df.item_type.WEAPON][0],defs[df.item_type.WEAPON][1],
      defs[df.item_type.WEAPON][2],{id='DIGGER',name='digger',flags={},skill_ranged=-1}}
    defs[df.item_type.ARMOR]=vec{defs[df.item_type.ARMOR][0],defs[df.item_type.ARMOR][1],
      {id='SCALES',props={flags={SCALED=true}}},{id='BARS',props={flags={BARRED=true}}}}
    defs[df.item_type.TOOL]=vec{defs[df.item_type.TOOL][0],defs[df.item_type.TOOL][1],
      {id='METAL_TOOL',flags={METAL_MAT=true}},{id='WEAPON_TOOL',flags={METAL_WEAPON_MAT=true}}}
    entity.resources=copy(entity.resources)
    entity.resources.digger_type=vec{0,3};entity.resources.armor_type=vec{0,1,2,3}
    entity.resources.shield_type=vec{0,1};entity.resources.tool_type=vec{0,1,2,3}
    local v=vec{};for _,raw in ipairs(saved_catalog.inorganics)do v:insert('#',raw)end
    v:insert('#',{id='STUD_ONLY',material={flags={IS_METAL=true}},metal_ore={mat_index=vec{}},thread_metal={mat_index=vec{}}})
    v:insert('#',{id='DIGGER_ONLY',material={flags={IS_METAL=true,ITEMS_DIGGER=true}},metal_ore={mat_index=vec{}},thread_metal={mat_index=vec{}}})
    df.global.world.raws.inorganics.all=v
    """)
    helper = lua.execute(source)
    variant = built()
    assert variant["ok"], variant["message"]
    variant_rows = list(variant["tasks"].values())
    for cursor in range(128, variant["total"], 128):
        variant_rows.extend(call(27, cursor=cursor)["tasks"].values())
    def tuples(job):
        jt = lua.globals().df.job_type[job]
        return {(r["item_subtype"], r["mat_type"], r["mat_index"], r["material_category"])
                for r in variant_rows if r["job_type"] == jt}
    assert tuples("ConstructDoor") == {(-1,-1,-1,2),(-1,0,-1,0),(-1,0,0,0),(-1,0,1,0),
                                         (-1,3,-1,0),(-1,4,-1,0),(-1,5,-1,0)}
    assert tuples("ConstructMechanisms") == {(-1,0,-1,0),(-1,0,0,0),(-1,0,1,0)}
    assert tuples("StudWith") == {(-1,0,i,0) for i in (0,1,5,6)}
    assert {t for t in tuples("MakeWeapon") if t[1] == 0} == {(0,0,0,0),(0,0,1,0),(0,0,6,0),(3,0,6,0)}
    assert {t for t in tuples("MakeTool") if t[1] == 0 and t[2]>=0} == {(sub,0,mi,0) for sub in (0,2,3) for mi in (0,1)}
    assert {t for t in tuples("MakeArmor") if t[3] in (32,64)} == {(2,-1,-1,64),(3,-1,-1,32)}
    assert {t for t in tuples("MakeShield") if t[1] == -1} == {(sub,-1,-1,cat) for sub in (0,1) for cat in (2,16)}
    assert {t[3] for t in tuples("MakeScepter") if t[1] == -1} == {2,32,512,1024}
    for job in ("ConstructBallistaParts", "ConstructCatapultParts", "ConstructBoltThrowerParts"):
        assert tuples(job) == {(-1,-1,-1,2)}
    assert not any(r["reaction"] == "FORBIDDEN" for r in variant_rows)
    # Civ reaction permission alone cannot bypass unavailable custom buildings.
    lua.execute("entity.entity_raw.workshops.permitted_building_id=vec{0}")
    helper = lua.execute(source)
    unavailable = built()
    unavailable_rows = list(unavailable["tasks"].values())
    for cursor in range(128, unavailable["total"], 128):
        unavailable_rows.extend(call(27, cursor=cursor)["tasks"].values())
    assert {r["reaction"] for r in unavailable_rows if r["reaction"]} == {"SOAP"}
    lua.execute("df.job_type=saved_catalog.jobs;df.item_type=saved_catalog.types;defs=saved_catalog.defs;entity.resources=saved_catalog.resources;df.global.world.raws.inorganics.all=saved_catalog.inorganics;entity.entity_raw.workshops.permitted_building_id=saved_catalog.buildings")

    # Rejected cross-product iterations consume the same single-step budget.
    lua.execute("iteration_reads=0;saved_subtype=dfhack.items.getSubtypeDef;dfhack.items.getSubtypeDef=function(...)iteration_reads=iteration_reads+1;return saved_subtype(...)end")
    helper = lua.execute(source)
    call(27)
    steps = 0
    while True:
        reads = lua.globals().iteration_reads
        advanced = helper(lua.table_from({"step": 1}))
        assert lua.globals().iteration_reads - reads <= 1
        assert advanced["steps"] <= 1
        steps += advanced["steps"]
        if advanced["active_kinds"] == 0:
            break
    lua.execute("dfhack.items.getSubtypeDef=saved_subtype")
    assert steps > len(rows) * 2
    assert built()["list_revision"] == catalog["list_revision"]
    lua.execute("df.global.world.raws.reactions.reactions:insert('#',reaction('PRESS',1,42))")
    helper = lua.execute(source)
    assert built()["message"] == "Duplicate task key"
    lua.execute("df.global.world.raws.reactions.reactions:erase(4)")
    # Compare single-step accounting with 2048-step updates, phase by phase.
    # Polling itself must neither advance work nor return Pending.
    for kind, total in ((3,7),(4,7),(5,5),(27,22)):
        counts = {}
        expected_rows = None
        for budget in (1,2048):
            helper = lua.execute(source)
            action = 27 if kind == 27 else 26
            fields = {} if kind == 27 else {"candidate_kind":kind}
            page = call(action, **fields)
            assert (page["build_phase"],page["build_done"],page["build_total"]) == (1,0,total)
            calls_by_phase = {}
            steps_by_phase = {}
            observed_steps = {1:0,2:0,3:0}
            while page["build_phase"]:
                phase = page["build_phase"]
                phase_steps = phase_calls = 0
                while True:
                    advanced = helper(lua.table_from({"step":budget}))
                    phase_calls += 1
                    phase_steps += advanced["steps"]
                    assert 0 <= advanced["steps"] <= budget
                    assert advanced["active_kinds"] in (0, {3:1, 4:1, 5:1, 27:2}[kind])
                    if budget == 1 and advanced["steps"]:
                        progress = call(action, **fields)
                        assert progress["ok"] and not progress["pending"]
                        assert progress["build_done"] <= progress["build_total"]
                        polled = call(action, **fields)
                        assert (polled["build_phase"], polled["build_done"], polled["build_total"]) == (progress["build_phase"], progress["build_done"], progress["build_total"])
                        observed_steps[progress["build_phase"]] += 1
                    if advanced["active_kinds"] == 0:
                        break
                # Read/sort and the separate filter retain their domain bit.
                calls_by_phase[phase] = phase_calls
                steps_by_phase[phase] = phase_steps
                page = call(action, **fields)
                assert page["ok"] and not page["pending"]
            if budget == 1:
                counts = steps_by_phase
                expected_rows = page["total"]
                assert observed_steps[3] == expected_rows
                assert observed_steps[2] == (expected_rows * (expected_rows-1).bit_length() if kind in (4,5,27) else 0)
                assert observed_steps[1] > 0
            else:
                assert steps_by_phase == counts and page["total"] == expected_rows
                assert all(calls_by_phase[p] == counts[p] // 2048 + 1 for p in counts)
            assert steps_by_phase[3] == page["total"]  # one test per filter row
            if kind == 4:
                materials = list(page["materials"].values())
                assert {(r["mat_type"],r["mat_index"]) for r in materials} == {(-1,-1),(0,0),(0,1),(0,2),(0,3),(0,4),(419,0),(420,0),(19,0),(20,0)}
                assert materials[0]["name"] == "None"
                assert [r["name"] for r in materials[1:]] == sorted(r["name"] for r in materials[1:])
                assert counts[1] == 17 + 10 * 4  # reads/materials plus four merge passes
            if kind == 5:
                trait_keys = {r["key"] for r in page["traits"].values()}
                for cursor in range(128, page["total"], 128):
                    trait_keys.update(r["key"] for r in call(26, candidate_kind=5, cursor=cursor)["traits"].values())
                assert page["total"] == 112  # 111 fixed native adjectives + one ore target
                assert {key for key in trait_keys if key.startswith("rc:")} == {
                    "rc:CALCIUM_CARBONATE", "rc:FAT", "rc:FLUX", "rc:CAN_GLAZE", "rc:GYPSUM",
                    "rc:PAPER_PLANT", "rc:PAPER_SLURRY", "rc:TALLOW", "rc:WAX"}
                assert {key for key in trait_keys if key.startswith("rp:")} == {
                    "rp:BAG_ITEM", "rp:FIRED_MAT", "rp:SOAP_MAT", "rp:DRINK_MAT", "rp:GLAZE_MAT",
                    "rp:HONEYCOMB_PRESS_MAT", "rp:PRESS_LIQUID_MAT", "rp:PRESS_PAPER_MAT",
                    "rp:PARCHMENT_MAT", "rp:RENDER_MAT", "rp:TAN_MAT"}
                assert "ore:0" in trait_keys and "ore:3" not in trait_keys
                assert not any(k.startswith(("f4:", "f5:")) for k in trait_keys)
                assert sum(k.startswith("f") for k in trait_keys) == 65
                assert sum(k.startswith("tool:") for k in trait_keys) == 26
                names = [r["name"] for r in page["traits"].values()]
                assert all(names) and names == sorted(names)
            if kind == 3:
                assert [(r["item_type"],r["item_subtype"]) for r in page["types"].values()] == [(-1,-1),(0,-1),(1,-1),(2,-1),(3,-1),(3,0),(3,1),(3,2),(4,-1),(4,0),(4,1),(5,-1),(5,0),(5,1)]
        helper = lua.execute(source)
        reset = call(action, **fields)
        assert (reset["build_phase"],reset["build_done"],reset["build_total"]) == (1,0,total)

    # Two distinct ores targeting one metal emit one sorted target trait.
    lua.execute("df.global.world.raws.inorganics.all[4].metal_ore.mat_index:insert('#',0)")
    helper = lua.execute(source)
    ores = built(26, candidate_kind=5)
    ore_rows = list(ores["traits"].values())
    assert ores["total"] == 112
    assert [(r["key"], r["name"]) for r in ore_rows if r["key"].startswith("ore:")] == [("ore:0", "Material 0:0-bearing items")]
    assert [r["name"] for r in ore_rows] == sorted(r["name"] for r in ore_rows)
    lua.execute("df.global.world.raws.inorganics.all[4].metal_ore.mat_index:erase(0)")

    # FOOD raw subtypes are recipe levels, absent from the native Type picker.
    lua.execute("df.item_type.FOOD=0")
    helper = lua.execute(source)
    assert built(26, candidate_kind=3)["total"] == 14  # BED has no subtypes in this mock
    lua.execute("df.item_type.FOOD=3")
    helper = lua.execute(source)
    assert built(26, candidate_kind=3)["total"] == 11  # all three FOOD subtypes excluded
    lua.execute("df.item_type.FOOD=nil")
    # Builtin generic/filth/placeholders are not condition materials (1..14 only).
    lua.execute("local v=vec{};for i=0,18 do v:insert('#',{})end;df.global.world.raws.mat_table={builtin=v}")
    helper = lua.execute(source)
    assert built(26, candidate_kind=4)["total"] == 24
    lua.execute("df.global.world.raws.mat_table=nil")

    # Each domain bit advances independently, including filters inheriting kind.
    helper = lua.execute(source)
    lua.execute("df.global.world.manager_orders.all=vec{};local o=df.manager_order:new();o.id=0;o.item_conditions:insert('#',condition());df.global.world.manager_orders.all:insert('#',o)")
    assert call(26, candidate_kind=4)["active_kinds"] == 1
    assert call(27)["active_kinds"] == 3
    assert observed(0)["conditions"][1]["satisfaction"] == 1
    assert call(27)["active_kinds"] == 7
    assert helper(lua.table_from({"step":2048,"builder_kind":2}))["active_kinds"] == 3
    assert call(26, candidate_kind=4)["build_done"] == 0
    assert call(27)["build_done"] == 0
    while helper(lua.table_from({"step":2048,"builder_kind":0}))["active_kinds"] & 1:
        pass
    assert call(26, candidate_kind=4)["build_phase"] == 3
    assert call(27)["build_done"] == 0
    assert helper(lua.table_from({"step":2048,"builder_kind":0}))["active_kinds"] == 2
    while helper(lua.table_from({"step":2048,"builder_kind":1}))["active_kinds"] & 2:
        pass
    assert call(27)["active_kinds"] == 2  # catalog's filter is also kind 1
    helper(lua.table_from({"step":2048,"builder_kind":1}))
    assert call(27)["active_kinds"] == 0

    # Inline scans share the allowance, and can interleave safely with builders.
    helper = lua.execute(source)
    call(27)
    lua.execute("df.global.world.manager_orders.all=vec{};for id=0,2199 do local o=df.manager_order:new();o.id=id;df.global.world.manager_orders.all:insert('#',o)end")
    req=lua.globals().request(20, lua.table_from({"query":"absent"}))
    req["step_budget"]=37
    total_steps=0
    for _ in range(3000):
        result=helper(req)
        assert 0 <= result["steps"] <= 37
        total_steps+=result["steps"]
        advanced=helper(lua.table_from({"step":2048-result["steps"],"builder_kind":1}))
        assert result["steps"]+advanced["steps"] <= 2048
        if not result["pending"]:
            break
    else:
        raise AssertionError("bounded inline scan did not complete")
    assert result["ok"] and len(result["orders"]) == 0 and total_steps > 2200

    # Atomic index rebuild, move hashing and deletion have explicit count caps.
    helper = lua.execute(source)
    lua.execute("df.global.world.manager_orders.all=vec{};for id=0,4095 do local o=df.manager_order:new();o.id=id;df.global.world.manager_orders.all:insert('#',o)end")
    rev = observed(0)["revision"]  # index rebuild accepts exactly 4096
    listing = call(20, query="absent")["list_revision"]
    assert call(23, id=0, expected_revision=rev, move=1, expected_neighbor=1, expected_list_revision=listing)["ok"]
    assert call(22, recipe=recipe)["message"] == "Work order count exceeds 4096-order cap"
    assert call(26, candidate_kind=4)["active_kinds"] == 1
    assert call(27)["active_kinds"] == 3
    cap_pending = lua.globals().request(20, lua.table_from({"query":"absent"}))
    cap_pending["step_budget"] = 1
    assert helper(cap_pending)["pending"]
    lua.execute("local o=df.manager_order:new();o.id=4096;df.global.world.manager_orders.all:insert('#',o)")
    refused = helper(cap_pending)
    assert refused["active_kinds"] == 0 and not refused["active"]
    assert not refused["ok"] and refused["message"] == "Work order count exceeds 4096-order cap"
    for action in (20,21,23,24):
        refused = call(action, id=0, expected_revision=rev, move=1, expected_neighbor=1, expected_list_revision=listing)
        assert not refused["ok"] and refused["message"] == "Work order count exceeds 4096-order cap"
    refused = helper(lua.table_from({"step":1,"builder_kind":2}))
    assert not refused["ok"] and refused["message"] == "Work order count exceeds 4096-order cap"
    lua.execute("df.global.world.manager_orders.all:erase(4096)")
    # Delete accepts the order-count boundary without inspecting every order.
    assert call(24, id=0, expected_revision=rev, retire_capacity=1)["ok"]
    cap_catalog = built()
    lua.execute("df.global.world.manager_orders.manager_order_next_id=5000")
    assert call(22, recipe=cap_catalog["tasks"][1]["key"])["ok"]  # create up to exactly 4096
    assert lua.eval("#df.global.world.manager_orders.all") == 4096
    for count in (4096,4097):
        helper = lua.execute(source)
        lua.execute("df.global.world.manager_orders.all=vec{};for id=0,1 do local o=df.manager_order:new();o.id=id;df.global.world.manager_orders.all:insert('#',o)end")
        rev = observed(0)["revision"]
        lua.execute(f"local o=df.global.world.manager_orders.all[1];for i=1,{count} do local c=df.manager_order_condition_order:new();c.order_id=99;o.order_conditions:insert('#',c)end")
        deleted = call(24, id=0, expected_revision=rev, retire_capacity=1)
        if count == 4096:
            assert deleted["ok"] and deleted["message"] == "Work order deleted; generated jobs retained"
        else:
            assert not deleted["ok"] and deleted["message"] == "Delete exceeds 4096-dependency sweep cap"
            assert lua.eval("#df.global.world.manager_orders.all") == 2
            assert lua.eval("#df.global.world.manager_orders.all[1].order_conditions") == 4097

    # Delete/move preflight uses the receipt independently of inspector limits.
    # Expose the existing receipt function only in this isolated test closure.
    helper = lua.execute(source.replace("local function inspect(o)", "test_revision=revision\nlocal function inspect(o)"))
    for overflow, message in (("conditions", "Order exceeds 64-condition inspector"),
                              ("jobs", "Order exceeds 1024-job inspector"),
                              ("traits", "Order exceeds trait page cap")):
        lua.execute("df.global.world.manager_orders.all=vec{};df.global.world.jobs.list.next=nil;for id=0,1 do local o=df.manager_order:new();o.id=id;df.global.world.manager_orders.all:insert('#',o)end")
        if overflow == "conditions":
            lua.execute("local o=df.global.world.manager_orders.all[0];for i=1,65 do o.item_conditions:insert('#',condition())end")
        elif overflow == "jobs":
            lua.execute("local link=df.global.world.jobs.list;for id=1,1025 do link.next={item={id=id,order_id=0}};link=link.next end")
        else:
            lua.execute("local o=df.global.world.manager_orders.all[0];for i=1,13 do local c=condition();c.flags1.whole=0xffffffff;c.flags2.whole=0xffffffff;c.flags3.whole=0xffffffff;c.flags4=0xffffffff;c.flags5=0xffffffff;o.item_conditions:insert('#',c)end")
        assert call(21, id=0)["message"] == message
        rev=lua.eval("test_revision(df.global.world.manager_orders.all[0])")
        # A nonmatching query obtains the list receipt without inspecting rows.
        listing=call(20, query="absent")["list_revision"]
        moved=call(23, id=0, expected_revision=rev, expected_list_revision=listing, expected_neighbor=1, move=1)
        assert moved["ok"] and moved["message"] == "Work order moved"
        assert lua.eval("df.global.world.manager_orders.all[1].id") == 0
        deleted=call(24, id=0, expected_revision=rev, retire_capacity=1)
        assert deleted["ok"] and deleted["message"] == "Work order deleted; generated jobs retained"
        assert lua.eval("#df.global.world.manager_orders.all") == 1
    lua.execute("df.global.world.manager_orders.all=vec{};df.global.world.jobs.list.next=nil")

    # Action 20 aggregate limits accept N and split before the N+1 row.
    for domain, cap in (("conditions",128),("jobs",2048),("traits",2048),("inputs",128)):
        for extra in (0,1):
            helper = lua.execute(source)
            lua.execute("df.global.world.manager_orders.all=vec{};df.global.world.jobs.list.next=nil")
            for oid, count in enumerate([cap//2, cap//2] + ([1] if extra else [])):
                lua.execute("local o=df.manager_order:new();o.id=...;df.global.world.manager_orders.all:insert('#',o)", oid)
                lua.execute(r"""
                local id,n,domain=...
                local o=df.global.world.manager_orders.all[id]
                if domain=='conditions' then
                 for i=1,n do o.order_conditions:insert('#',df.manager_order_condition_order:new())end
                elseif domain=='jobs' then
                 local link=df.global.world.jobs.list;while link.next do link=link.next end
                 for i=1,n do link.next={item={id=id*1024+i,order_id=id}};link=link.next end
                elseif domain=='traits' then
                 while n>0 do local c=condition();local bits=math.min(n,32);c.flags1.whole=(1<<bits)-1;o.item_conditions:insert('#',c);n=n-bits end
                else
                 o.items={elements=vec{}}
                 for i=1,n do local f=condition();f.job_details_flags=bits{};f.job_details_item_flags2=bits{};f.job_details_mat_type=-1;f.job_details_mat_index=-1;o.items.elements:insert('#',f)end
                end
                """, oid, count, domain)
            page=call(20)
            assert page["ok"], page["message"]
            assert len(page["orders"]) == 2 and page["next_cursor"] == (2 if extra else 0)
            def size(row):
                if domain == "traits":
                    return sum(len(c["traits"]) for c in row["conditions"].values())
                return len(row[{"conditions":"conditions","jobs":"generated_jobs","inputs":"inputs"}[domain]])
            assert sum(size(row) for row in page["orders"].values()) == cap
            if extra:
                tail=call(20, cursor=page["next_cursor"], expected_list_revision=page["list_revision"])
                assert tail["ok"] and tail["next_cursor"] == 0 and len(tail["orders"]) == 1
                assert tail["orders"][1]["position"] == 2 and size(tail["orders"][1]) == 1
    helper=lua.execute(source)
    lua.execute("df.global.world.jobs.list.next=nil;local o=df.manager_order:new();o.id=0;df.global.world.manager_orders.all=vec{o};for i=1,64 do local c=condition();c.flags1.whole=0xffffffff;o.item_conditions:insert('#',c)end")
    assert sum(len(c["traits"]) for c in observed(0)["conditions"].values()) == 2048
    lua.execute("df.global.world.manager_orders.all[0].item_conditions[0].flags2.whole=1")
    for action in (20,21):
        assert call(action, id=0)["message"] == "Order exceeds trait page cap"
    lua.execute("df.global.world.manager_orders.all=vec{}")

    # Task capacity is checked on insertion, including the exact limit.
    baseline = len(rows)
    lua.execute("saved_reactions=df.global.world.raws.reactions.reactions")
    def fill_tasks(total):
        lua.execute("df.global.world.raws.reactions.reactions=vec{}")
        lua.execute("for i=1,... do df.global.world.raws.reactions.reactions:insert('#',reaction('R'..i,1,42))end", total - baseline + 3)
    fill_tasks(8192)
    helper = lua.execute(source)
    cap_page = built()
    assert cap_page["ok"] and cap_page["total"] == 8192 and len(cap_page["tasks"]) == 128
    assert lua.eval("(function()collectgarbage('collect');return collectgarbage('count')end)()") < 30 * 1024
    next_page = built(cursor=128, expected_list_revision=cap_page["list_revision"])
    assert next_page["total"] == 8192 and len(next_page["tasks"]) == 128
    fill_tasks(8193)
    helper = lua.execute(source)
    assert built()["message"] == "list exceeds cap"
    lua.execute("df.global.world.raws.reactions.reactions=saved_reactions")
    # A new epoch's closure cannot serve or create from the preceding cache.
    helper = lua.execute(source)
    assert call(22, recipe=selected["key"])["message"] == "Task catalog is building; refresh"
    assert call(27)["build_done"] == 0
    lua.execute("test_epoch=1")
    helper = lua.execute(source)
    changed_epoch = built()
    assert changed_epoch["list_revision"] != catalog["list_revision"]
    assert call(27, expected_list_revision=catalog["list_revision"])["message"] == "List changed; refresh"
    lua.execute("test_epoch=0")
    # Cache string caps: accept exactly 128 bytes, reject 129 before publication.
    lua.execute("saved_name=dfhack.job.getManagerOrderName;dfhack.job.getManagerOrderName=function()return string.rep('n',128)end")
    helper = lua.execute(source)
    assert built()["ok"]
    lua.execute("dfhack.job.getManagerOrderName=function()return string.rep('n',129)end")
    helper = lua.execute(source)
    assert built()["message"] == "list row exceeds string cap"
    lua.execute("dfhack.job.getManagerOrderName=saved_name")
    # Key bytes at and just beyond the bound (length-prefix digit is stable here).
    sample = next(r for r in rows if r["reaction"] == "PRESS")
    extra = 64 - len(sample["key"])
    # Crossing a 1-digit length prefix consumes one additional byte.
    code_len = len("PRESS") + extra - 1
    lua.execute("df.global.world.raws.reactions.reactions=vec{reaction(string.rep('r',...),1,42)}", code_len)
    helper = lua.execute(source)
    at_key_cap = built()
    assert at_key_cap["ok"], at_key_cap["message"]
    assert any(len(r["key"].encode()) == 64 for r in at_key_cap["tasks"].values())
    lua.execute("df.global.world.raws.reactions.reactions=vec{reaction(string.rep('r',...),1,42)}", code_len + 1)
    helper = lua.execute(source)
    assert built()["message"] == "list row exceeds string cap"
    lua.execute("df.global.world.raws.reactions.reactions=saved_reactions")
    # Every published group counts toward the 128-row producer bound.
    lua.execute("saved_buildings=df.global.world.raws.buildings.all;saved_permitted=entity.entity_raw.workshops.permitted_building_id")
    for customs in (101, 102):
        lua.execute("df.global.world.raws.buildings.all=vec{};entity.entity_raw.workshops.permitted_building_id=vec{};for i=0,...-1 do df.global.world.raws.buildings.all:insert('#',{id=i,name='Custom '..i,building_type=0,building_subtype=23});entity.entity_raw.workshops.permitted_building_id:insert('#',i)end", customs)
        helper = lua.execute(source)
        page = built()
        if customs == 101:
            assert page["ok"] and len(page["groups"]) == 128
        else:
            assert page["message"] == "list exceeds cap"
    lua.execute("df.global.world.raws.buildings.all=saved_buildings;entity.entity_raw.workshops.permitted_building_id=saved_permitted")
    # Exact non-task cache caps use the same producer insertion guard.
    lua.execute("saved_count=dfhack.items.getSubtypeCount;saved_def=dfhack.items.getSubtypeDef;dfhack.items.getSubtypeDef=function()return {name='subtype'}end")
    for total in (1024, 1025):
        lua.execute("dfhack.items.getSubtypeCount=function(t)return t==0 and ... or 0 end".replace("...", str(total - 7)))
        helper = lua.execute(source)
        page = built(26, candidate_kind=3)
        if total == 1024:
            assert page["ok"] and page["total"] == total
            assert lua.eval("(function()collectgarbage('collect');return collectgarbage('count')end)()") < 30 * 1024
        else:
            assert page["message"] == "list exceeds cap"
    lua.execute("dfhack.items.getSubtypeCount=saved_count;dfhack.items.getSubtypeDef=saved_def")
    for total in (1024, 1025):
        lua.execute("df.global.world.raws.descriptors.colors=vec{};for i=1,... do df.global.world.raws.descriptors.colors:insert('#',{})end", total - 112)
        helper = lua.execute(source)
        page = built(26, candidate_kind=5)
        if total == 1024:
            assert page["ok"] and page["total"] == total
            assert lua.eval("(function()collectgarbage('collect');return collectgarbage('count')end)()") < 30 * 1024
        else:
            assert page["message"] == "list exceeds cap"
    lua.execute("df.global.world.raws.descriptors.colors=vec{}")
    for total in (65536, 65537):
        lua.execute("local v=vec{};local raw={material={},metal_ore={mat_index=vec{}}};for i=1,... do v:insert('#',raw)end;df.global.world.raws.inorganics.all=v", total - 5)
        helper = lua.execute(source)
        page = built(26, candidate_kind=4)
        if total == 65536:
            assert page["ok"] and page["total"] == total
            assert lua.eval("(function()collectgarbage('collect');return collectgarbage('count')end)()") < 30 * 1024
        else:
            assert page["message"] == "list exceeds cap"
    test_lane_waits()
    test_dispatch_fixture()
    print("WORK_ORDERS_ADAPTER PASS")


def test_lane_waits():
    """Execute the lane verifier with injected screen, popups, and clocks."""
    root = Path(__file__).resolve().parents[1]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((root / "tools/qa/lua_test_prelude.lua").read_text())
    lua.execute(r"""
    package.preload.json=function()return {
      decode=function()return request end,encode=function(value)response=value;return '' end}end
    io.open=function()return {read=function()return '' end,write=function()end,close=function()end}end
    print=function()end
    focus={'dwarfmode/Default'};wall=1000
    df={d_init_autosave={NONE=0},viewscreen_dwarfmodest={is_instance=function()return true end},global={
      pause_state=true,cur_year=0,cur_year_tick=10,d_init={feature={autosave=0}},
      world={status={popups=vec{}},manager_orders={all=vec{{id=7,status={validated=false}}}}}}}
    dfhack={df2utf=function(s)return s end,getTickCount=function()return wall end,
      gui={getCurViewscreen=function()return {} end,getFocusStrings=function()return focus end}}
    df3d_work_orders_acceptance={manager=1,prepare_dispatch=function()end,
      dispatch_diagnostics=function()return {workshop={jobs=0},worker={available=true,carpentry=true,reachable=true},
        material_count=10,required_materials=10,manager={available=true,reachable=true},office={active=true,owner=1}}end}
    """)
    source = (root / "tools/smoke/work-orders-acceptance-verify.lua").read_text()
    def verify(op):
        lua.globals().request = lua.table_from({"op":op,"kind":"validated","id":7})
        lua.execute(source, "memory", "1")
        return lua.globals().response
    lua.execute("df.global.world.status.popups=vec{{text='First popup'},{text='Second popup'}}")
    result = verify("wait_start")
    assert result["status"] == "incomplete" and result["reason"] == "wait requires no announcement popups (count=2, first=First popup)"
    assert lua.globals().df3d_work_orders_acceptance.wait is None
    lua.execute("df.global.world.status.popups=vec{};focus={'dwarfmode/Info'}")
    result = verify("wait_start")
    assert result["status"] == "incomplete" and result["reason"] == "wait requires default fortress screen; screen=dwarfmode/Info"
    lua.execute("focus={'dwarfmode/Default'}")
    assert verify("wait_start")["waiting"]
    lua.execute("df.global.pause_state=false;wall=1100;df.global.cur_year_tick=11")
    result = verify("wait_poll")
    assert result["status"] == "passed" and result["waiting"] and result["ticks"] == 1
    lua.execute("df.global.pause_state=true;df.global.world.status.popups=vec{{text='New popup'}}")
    result = verify("wait_poll")
    assert result["status"] == "incomplete" and not result["waiting"]
    assert result["reason"] == "game paused mid-wait; screen=dwarfmode/Default; popup count=1"
    lua.execute("df.global.world.status.popups=vec{};focus={'dwarfmode/Info'}")
    result = verify("wait_poll")
    assert result["reason"] == "game paused mid-wait; screen=dwarfmode/Info; popup count=0"
    lua.execute("df.global.pause_state=true;df.global.world.manager_orders.all[0].status.validated=true")
    completed = verify("wait_poll")
    assert completed["waiting"] is False and completed["status"] == "passed"
    # Fixture stages before setup; a missing manager must still permit restoration.
    lua.execute(r"""
    df.global.d_init.feature.autosave=3
    local function flags()
     local whole=0;local masks={DO_MEGA=1,PAUSE=2,RECENTER=4}
     return setmetatable({}, {__index=function(_,k)if k=='whole' then return whole end;return whole & masks[k] ~= 0 end,
       __newindex=function(_,k,v)if k=='whole' then whole=v elseif v then whole=whole | masks[k] else whole=whole & ~masks[k] end end})
    end
    df.global.d_init.announcements={flags=vec{flags(),flags()}}
    local flags=df.global.d_init.announcements.flags
    flags[0].DO_MEGA=true;flags[0].PAUSE=true;flags[0].RECENTER=true;flags[1].PAUSE=true
    original_flags={flags[0].whole,flags[1].whole}
    df.global.plotinfo={group_id=1};df.historical_entity={find=function()return nil end}
    """)
    fixture = (root / "tools/smoke/work-orders-acceptance-fixture.lua").read_text()
    lua.execute(fixture, "memory")
    assert lua.eval("df.global.d_init.feature.autosave") == 0
    assert lua.eval("df.global.d_init.announcements.flags[0].whole") == 4
    assert lua.eval("df.global.d_init.announcements.flags[1].whole") == 0
    lua.execute(fixture, "memory")  # repeated staging preserves original
    lua.execute("df.global.pause_state=false")
    try:
        lua.execute(source, "memory", "restore_prefs")
        raise AssertionError("unpaused restoration accepted")
    except Exception as error:
        assert str(error).splitlines()[0].split(": ", 1)[-1] == "DF must be paused before restoring fixture preferences"
    assert lua.eval("df.global.d_init.feature.autosave") == 0
    assert lua.eval("df.global.d_init.announcements.flags[0].whole") == 4
    lua.execute("df.global.pause_state=true")
    lua.execute(source, "memory", "restore_prefs")
    assert lua.eval("df.global.d_init.feature.autosave") == 3
    assert lua.eval("df.global.d_init.announcements.flags[0].whole == original_flags[1]")
    assert lua.eval("df.global.d_init.announcements.flags[1].whole == original_flags[2]")
    lua.execute(source, "memory", "restore_prefs")  # idempotent cleanup


def test_dispatch_fixture():
    """Run real fixture setup and diagnostics, then inject native ticks/dispatch."""
    root = Path(__file__).resolve().parents[1]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((root / "tools/qa/lua_test_prelude.lua").read_text())
    mock = r"""
    package.preload.json=function()return {decode=function()return request end,
      encode=function(v)response=v;return '' end}end
    package.preload['plugins.eventful']=function()return {eventType={JOB_COMPLETED=1},
      enableEvent=function()end,onJobCompleted={}}end
    io.open=function()return {read=function()return '' end,write=function()end,close=function()end}end
    print=function(s)last_print=s end
    local function unit(id)
      return {id=id,hist_figure_id=id,pos={x=1,y=1,z=0},job={},flags4={},status={labors={[0]=true,[1]=true}}}
    end
    manager=unit(1);worker=unit(2)
    chair={id=4,centerx=1,centery=1,z=0,getBuildStage=function()return 1 end,getMaxBuildStage=function()return 1 end}
    office={id=5,type=1,contained_buildings=vec{chair},spec_sub_flag={},assigned_unit_id=-1}
    shop={id=6,type=1,centerx=2,centery=2,z=0,flags={},jobs=vec{{id=90}},
      getBuildStage=function()return 3 end,getMaxBuildStage=function()return 3 end,
      profile={permitted_workers=vec{99},min_level=9,max_level=9,max_general_orders=2,
        flags={},blocked_labors={[0]=true},links={take_from_pile=vec{},take_from_workshop=vec{}}}}
    pile={links={give_to_workshop=vec{shop}}};source_shop={profile={links={give_to_workshop=vec{shop}}}}
    shop.profile.links.take_from_pile:insert('#',pile);shop.profile.links.take_from_workshop:insert('#',source_shop)
    local position={id=1,responsibilities={[1]=true}}
    local assignment={id=1,position_id=1,histfig=1}
    local entity={id=1,positions={own=vec{position},assignments=vec{assignment}},assignments_by_type={[1]=vec{}}}
    local hf={id=1,entity_links=vec{{entity_id=1,assignment_id=1}}}
    o={id=7,job_type=1,mat_type=-1,mat_index=-1,status=bits{'validated','active'},amount_left=10,
      frequency=1,workshop_id=-1,item_conditions=vec{},order_conditions=vec{},finished_year=-1,finished_year_tick=-1}
    logs=vec{}
    for id=1,10 do logs:insert('#',{id=id,pos={x=1,y=1,z=0},flags={on_ground=true,forbid=true}})end
    df={entity_position_responsibility={MANAGE_PRODUCTION=1},civzone_type={Office=1},workshop_type={Carpenters=1},
      unit_labor={CARPENTER=0},job_type={ConstructBed=1},d_init_autosave={NONE=0},
      viewscreen_dwarfmodest={is_instance=function()return true end},
      building_chairst={is_instance=function(_,b)return b==chair end},
      building_workshopst={is_instance=function(_,b)return b==shop end},
      historical_entity={find=function()return entity end},historical_figure={find=function()return hf end},
      histfig_entity_link_positionst={is_instance=function()return true end},world_site={find=function()return nil end},
      global={pause_state=true,cur_year=0,cur_year_tick=0,plotinfo={group_id=1,site_id=1,manager_timer=50,nobles={manager_cooldown=1008}},
        d_init={feature={autosave=0},announcements={flags=vec{}}},world={units={active=vec{manager,worker}},
          buildings={all=vec{shop},other={ACTIVITY_ZONE=vec{office}}},items={other={WOOD=logs}},
          status={popups=vec{}},manager_orders={all=vec{o}},jobs={list={}}}}}
    wall=1000;reachable=true
    dfhack={getTickCount=function()return wall end,df2utf=function(s)return s end,
      gui={getCurViewscreen=function()return {} end,getFocusStrings=function()return {'dwarfmode/Default'} end},
      units={isCitizen=function()return true end,isActive=function()return true end,isDead=function()return false end,
        isAdult=function()return true end,isSane=function()return true end,isJobAvailable=function(u)return u.job.current_job==nil end,
        getNoblePositions=function()return {{entity=entity,assignment=assignment,position=position}} end},
      buildings={setOwner=function(b,u)b.assigned_unit_id=u and u.id or -1;return true end},maps={canWalkBetween=function(a,b)assert(type(a)=='table' and type(b)=='table' and a.x and a.y and a.z and b.x and b.y and b.z);return reachable end},
      items={moveToGround=function(i,p)i.pos=p;return true end},
      job={removeJob=function(j)assert(j.id==90);shop.jobs:erase(0);return true end,getWorker=function()return nil end}}
    """
    lua.execute(mock)
    fixture = (root / "tools/smoke/work-orders-acceptance-fixture.lua").read_text()
    lua.execute(fixture, "memory")
    assert lua.globals().last_print == "FIXTURE_READY manager=1 office=5 workshop=6 worker=2 logs=10"
    lua.execute("s=df3d_work_orders_acceptance")
    assert lua.eval("#shop.jobs==0 and shop.profile.max_general_orders==0 and shop.profile.flags.block_general_orders")
    assert lua.eval("shop.profile.permitted_workers[0]==2 and worker.status.labors[0] and not worker.status.labors[1]")
    assert lua.eval("not manager.status.labors[0] and not manager.status.labors[1] and office.spec_sub_flag.active")
    assert lua.eval("not logs[0].flags.forbid and #s.materials==10")
    assert lua.eval("#pile.links.give_to_workshop==0 and #source_shop.profile.links.give_to_workshop==0")
    for change, reason in (
        ("o.mat_type=0", "dispatch fixture requires an unrestricted bed order"),
        ("o.mat_type=-1;o.item_conditions:insert('#',{})", "dispatch fixture requires no conditions"),
    ):
        lua.execute(change)
        ok, error = lua.eval("pcall(s.prepare_dispatch,o)")
        assert not ok and error.endswith(": " + reason)
    lua.execute("o.item_conditions:resize(0)")
    source = (root / "tools/smoke/work-orders-acceptance-verify.lua").read_text()

    def verify(op, kind="jobs"):
        lua.globals().request = lua.table_from({"op": op, "kind": kind, "id": 7})
        lua.execute(source, "memory", "1")
        return lua.globals().response

    start = verify("wait_start", "validated")
    assert start["waiting"] and start["dispatch"]["order"]["workshop_id"] == 6
    assert start["dispatch"]["order"]["status"] == 0  # routing never validates/activates
    assert start["dispatch"]["manager_cooldown"] == 1008
    lua.execute("o.status.validated=true;o.status.active=true")
    assert verify("wait_start")["dispatch"]["order"]["status"] == 3
    lua.execute("df.global.pause_state=false;df.global.cur_year_tick=3599;wall=1100")
    assert verify("wait_poll")["waiting"]
    for tick in (3600, 3601):
        lua.execute("df.global.cur_year_tick=...", tick)
        cap = verify("wait_poll")
        assert cap["reason"] == f"jobs wait cap hit ({tick} ticks, 100 ms)"
        assert cap["dispatch"]["material_count"] == 10
        # Real dispatch is accepted even on the cap boundary; no fake job injection by fixture.
        lua.execute("df.global.world.jobs.list.next={item={id=8,order_id=7}}")
        assert verify("wait_poll")["status"] == "passed"
        lua.execute("df.global.world.jobs.list.next=nil")
    lua.execute("logs[0].flags.in_job=true;logs[1].flags.forbid=true;worker.job.current_job={id=42,job_type=9};worker.status.labors[0]=false")
    cap = verify("wait_poll")["dispatch"]
    assert cap["material_count"] == 8 and cap["worker"]["job_id"] == 42
    assert "candidate worker unavailable" in list(cap["blockers"].values())
    assert "candidate carpentry disabled" in list(cap["blockers"].values())
    lua.execute("reachable=false;df.global.world.status.popups=vec{{text='blocked'}}")
    cap = verify("wait_poll")["dispatch"]
    assert cap["material_count"] == 0 and not cap["manager"]["reachable"] and cap["popup_count"] == 1
    lua.execute("df.global.pause_state=true;reachable=true;df.global.world.status.popups=vec{}")
    refused = verify("wait_start", "validated")
    assert refused["reason"] == "dispatch prerequisites unavailable; see dispatch diagnostics"
    assert not refused["dispatch"]["worker"]["available"]
    lua.execute("df.global.world.manager_orders.all:resize(0)")
    refused = verify("wait_start", "validated")
    assert refused["dispatch"]["order"]["missing"]
    assert refused["reason"].endswith(": dispatch order missing")
    # Setup must fail closed instead of spending a tick budget on missing resources.
    for edit, reason in (
        ("dfhack.units.isJobAvailable=function()return false end", "no free adult citizen with a histfig for manager"),
        ("office.contained_buildings:resize(0)", "no reachable Office with a built chair"),
        ("reachable=false", "no reachable Office with a built chair"),
        ("worker.job.current_job={id=42}", "no built untargeted Carpenter workshop with a free reachable worker"),
        ("o.workshop_id=shop.id", "no built untargeted Carpenter workshop with a free reachable worker"),
        ("dfhack.job.removeJob=function()return false end", "could not clear Carpenter workshop jobs"),
        ("logs:resize(9)", "need 10 free reachable logs; found 9"),
        ("logs:resize(0)", "need 10 free reachable logs; found 0"),
    ):
        lua.execute(mock)
        lua.execute(edit)
        lua.execute(fixture, "memory")
        assert lua.globals().last_print == "FIXTURE_INCOMPLETE " + reason
    lua.execute(mock)
    lua.execute("dfhack.items.moveToGround=function()return false end")
    lua.execute(fixture, "memory")
    assert lua.globals().last_print.startswith("FIXTURE_INCOMPLETE manager/office/event prerequisite: ")
    assert lua.globals().last_print.endswith(": could not stage reachable log")
    lua.execute(mock)
    lua.execute("logs:insert('#',{id=11,pos=worker.pos,flags={on_ground=true,forbid=true}})")
    lua.execute(fixture, "memory")
    assert lua.eval("#df3d_work_orders_acceptance.materials==10 and logs[10].flags.forbid")


if __name__ == "__main__":
    main()
