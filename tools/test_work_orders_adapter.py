"""No assets/process: typed manager adapter, zero-index DF vectors, pinned API mocks."""
from pathlib import Path
from lupa import LuaRuntime


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((Path(__file__).resolve().parent / "qa/lua_test_prelude.lua").read_text(encoding="utf-8"))
    lua.execute(r'''
    df={job_type={ConstructBed=10,PrepareMeal=11,MakeCharcoal=12,CustomReaction=13},workshop_type={Carpenters=0,Kitchen=1,Still=2},furnace_type={WoodFurnace=0},building_type={Workshop=0},
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
    df.manager_order={new=function()return allocation{id=-1,job_type=10,item_type=-1,item_subtype=-1,reaction_name='',mat_type=-1,mat_index=-1,amount_left=0,amount_total=0,status=bits{'validated','active'},material_category=bits{'wood'},specflag={whole=0},specdata={hist_figure_id=-1},art_spec={type=0,id=-1,subid=-1},frequency=0,finished_year=-1,finished_year_tick=-1,workshop_id=-1,max_workshops=0,item_conditions=vec{},order_conditions=vec{}}end}
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
     seq=seq+1;return {action=action,seq=seq,work_order=a}
    end
    ''')
    helper = lua.execute((Path(__file__).resolve().parents[1] / "bridge/plugin/work_orders.lua").read_text())
    def call(action, **fields):
        req = lua.globals().request(action, lua.table_from(fields))
        while True:
            result = helper(req)
            if not result["pending"]:
                return result
    def observed(order_id):
        result = call(21, id=order_id)
        assert result["ok"], result["message"]
        assert len(result["orders"]) == 1
        return result["orders"][1]
    def edit(action, order_id, **fields):
        return call(action, id=order_id, expected_revision=observed(order_id)["revision"], **fields)
    catalog = call(27)
    assert catalog["ok"] and len(catalog["recipes"]) == 3
    assert len(catalog["managers"]) == 0
    assert catalog["recipes"][1]["key"] == "Carpenters:10:-1"
    assert catalog["recipes"][1]["name"] == "make bed"
    first = call(22, recipe="Carpenters:10:-1", remaining=5)["orders"][1]
    assert first["id"] == 0 and first["total"] == 5 and not first["validated"] and not first["active"]
    stale = first["revision"]
    lua.execute("o=df.global.world.manager_orders.all[0];o.amount_left=3;o.status.validated=true;o.status.active=true")
    native = observed(0)
    assert native["validated"] and native["active"]
    rejected = call(23, id=0, expected_revision=stale, remaining=7)
    assert not rejected["ok"] and rejected["message"] == "Work order changed; inspect again before editing"
    assert not edit(23, 0, remaining=6)["ok"]  # native reapproval of partial batches is unverified
    assert not edit(23, 0, frequency=1)["ok"]
    assert not observed(0)["editable"] and observed(0)["remaining"] == 3
    assert "batch has started" in observed(0)["reason"]
    assert edit(23, 0, remaining=6)["message"] == observed(0)["reason"]
    lua.execute("df.global.world.manager_orders.all[0].amount_left=5")
    assert edit(23, 0, remaining=6)["orders"][1]["total"] == 6
    assert not observed(0)["validated"] and not observed(0)["active"]
    lua.execute("df.global.world.manager_orders.all[0].amount_left=3")
    assert not edit(23, 0, remaining=0)["ok"]  # cannot erase completed history
    lua.execute("df.global.world.manager_orders.all[0].amount_left=6")
    second = call(22, recipe="Carpenters:10:-1", remaining=0)["orders"][1]["id"]
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
    assert not edit(24, 0)["ok"]  # dependent order exists
    assert not edit(25, second, condition_kind=1, condition_index=0, remove_condition=True)["ok"]
    assert len(observed(second)["conditions"]) == 2  # never frees borrowed storage
    lua.execute("o=df.global.world.manager_orders.all[0];local f=condition();f.quantity=2;f.vector_id=0;f.reagent_index=-1;f.job_details_flags=bits{};f.job_details_item_flags2=bits{};f.job_details_mat_type=-1;f.job_details_mat_index=-1;o.items={elements=vec{f},delete=function(s)s.deleted=true end}")
    before = observed(0)["revision"]
    lua.execute("df.global.world.manager_orders.all[0].items.elements[0].contains:insert('#',3)")
    assert not call(23, id=0, expected_revision=before, max_workshops=2)["ok"]
    assert edit(23, 0, max_workshops=2)["orders"][1]["max_workshops"] == 2
    assert lua.eval("df.global.world.manager_orders.all[0].items.elements[0].contains[0]") == 3
    lua.execute("df.global.world.jobs.list.next={item={id=7,order_id=0}}")
    assert not observed(0)["editable"]
    assert "outstanding jobs" in observed(0)["reason"]
    assert observed(0)["generated_jobs"][1] == 7
    assert edit(23, 0, remaining=4)["message"] == observed(0)["reason"]
    assert not edit(23, 0, frequency=2)["ok"]
    assert not edit(25, 0, condition_kind=0, item_type=0, compare=0, threshold=0)["ok"]
    assert not edit(24, 0)["ok"] and not edit(23, 0, remaining=4)["ok"]
    lua.execute("df.global.world.jobs.list.next=nil;df.global.game.main_interface=setmetatable({}, {__index=function()error('Native UI must not be read')end})")
    assert edit(23, 0, frequency=2)["ok"]  # in-place edits never consult panels
    assert edit(25, second, condition_index=0, item_type=0, compare=3, threshold=90)["ok"]
    assert not edit(24, 0)["ok"] and not edit(24, second)["ok"]
    assert not edit(25, second, condition_index=0, remove_condition=True)["ok"]
    assert lua.eval("#df.global.world.manager_orders.all") == 2
    assert not lua.eval("df.global.world.manager_orders.all[0].deleted")
    assert len(observed(second)["conditions"]) == 2
    refusal = "Removal is unavailable until safe work-order retirement is supported"
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
    assert not custom["editable"] and "custom filters preserved; read only" in custom["description"]
    result = edit(25, second, condition_index=0, item_type=0, compare=0, threshold=1)
    assert not result["ok"] and result["message"] == "Unsupported custom condition is read only"
    assert lua.eval("df.global.world.manager_orders.all[1].item_conditions[0].mat_type") == 2
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
    dfhack.maps.getTileFlags=function()return {hidden=false}end
    dfhack.buildings.getName=function(b)return b.type==0 and "Carpenter's Workshop" or "Kitchen" end
    ''')
    assert observed(0)["workshop_id"] == -1
    assert not call(22, recipe="Carpenters:10:-1", remaining=1, workshop_id=5)["ok"]
    bound = call(22, recipe="Carpenters:10:-1", remaining=7, frequency=3, workshop_id=4, max_workshops=2)["orders"][1]
    assert bound["workshop_id"] == 4 and bound["frequency"] == 3 and bound["max_workshops"] == 2
    assert bound["total"] == 7 and bound["remaining"] == 7 and not bound["validated"] and not bound["active"]
    assert not edit(23, bound["id"], workshop_id=5)["ok"]
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
    assert len(page["orders"]) == 16 and page["orders"][1]["id"] == 1 and page["orders"][16]["id"] == 16
    assert page["next_cursor"] == 17
    next_page = call(20, cursor=page["next_cursor"])
    assert len(next_page["orders"]) == 16 and next_page["orders"][1]["id"] == 17 and next_page["next_cursor"] == 33
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
    lua.execute("df.global.world.units.active=vec{{id=7,job={}}};dfhack.units.isCitizen=function()return true end;dfhack.units.isActive=function()return true end;dfhack.units.isDead=function()return false end;dfhack.units.getReadableName=function()return 'Manager' end;dfhack.units.getNoblePositions=function()return {{entity={id=0},position={name={[0]='Manager'},responsibilities={[4]=true}}}}end;df.global.world.buildings.other.ACTIVITY_ZONE=vec{{id=3,type=4,assigned_unit_id=7}}")
    manager = call(27)["managers"][1]
    assert manager["unit_id"] == 7 and manager["offices"][1] == 3
    assert manager["name"] == "Manager" and manager["position"] == "Manager" and manager["job"] == "No current job"
    lua.execute("df.global.world.units.active[0].job.current_job={};dfhack.job.getName=function()return 'Validate work orders' end")
    assert call(27)["managers"][1]["job"] == "Validate work orders"
    print("WORK_ORDERS_ADAPTER PASS")


if __name__ == "__main__":
    main()
