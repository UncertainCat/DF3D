extends "res://tests/creature_knowledge_state_test.gd"
const Labor=preload("res://scripts/creature_labor_state.gd")
func setup_labor() -> void:
 if model!=null:model.dispose()
 if service!=null:service.free()
 world=LinkWorld.new();service=Service.new();service.configure(world);service.poll()
 model=Labor.new();model.configure(service)
func labor_reply(value: Dictionary,overrides: Dictionary={}) -> void:
 var action: int=world.calls.back().request.action
 world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":action,"status":C.ManagementStatus.Ok,"citizen":value}
 world.state.merge(overrides,true);service.poll()
func list_value() -> Dictionary:
 return {"detail_list_revision":42,"next_cursor":0,"details":[{"index":0,"revision":43,"editable":true,"assigned_units":[]}]}
func citizen_value() -> Dictionary:
 return {"detail_list_revision":42,"citizens":[{"id":86,"revision":44,"eligible":true,"only_assigned_jobs":false}]}
func ready() -> void:
 model.open(86);service.poll();labor_reply(list_value());service.poll();labor_reply(citizen_value())
 check(model.phase==Labor.Phase.Ready,"list and citizen receipts publish together")
func run() -> void:
 setup_labor();ready()
 model.set_member(0,true);model.set_member(0,true);service.poll()
 check(world.calls.size()==3 and world.calls.back().request.expected_revision==43,"membership uses displayed receipt and ignores duplicate pending click")
 labor_reply({});service.poll();labor_reply(list_value());service.poll();labor_reply(citizen_value())
 check(model.phase==Labor.Phase.Ready,"confirmed mutation refreshes all membership rows")
 model.set_scope(true);service.poll()
 check(world.calls.back().request.expected_revision==44,"scope uses citizen receipt")
 model.close();labor_reply({});service.poll()
 check(model.phase==Labor.Phase.Closed and model.rows.is_empty() and world.calls.size()==6,"late mutation completion cannot reopen or refresh closed panel")
 setup_labor();ready();model.set_member(0,true);service.poll()
 labor_reply({}, {"status":C.ManagementStatus.Rejected})
 check(model.phase==Labor.Phase.Rejected,"rejected edit disables further writes")
 model.set_scope(true);service.poll();check(world.calls.size()==3,"rejection never replays")
 setup_labor();ready();model.set_member(0,true);service.poll();world.live=false;service.poll()
 check(model.phase==Labor.Phase.Unavailable and model.rows.is_empty(),"disconnect retires selection and uncertain edit")
 world.live=true;service.poll();service.poll()
 check(world.calls.filter(func(call):return call.domain=="citizens").size()==3,"reconnect never replays labor mutation")
 setup_labor();model.open(86);service.poll();labor_reply(list_value());service.poll()
 var changed:=citizen_value();changed.detail_list_revision=45;labor_reply(changed)
 check(model.phase==Labor.Phase.Rejected and model.rows.is_empty(),"changed list cannot mix with citizen snapshot")
 model.dispose();model=null;service.free();service=null
 if failures==0:print("CREATURE_LABOR_STATE_PASS")
 quit(1 if failures else 0)
