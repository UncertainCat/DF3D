extends SceneTree
const Model=preload("res://scripts/farm_state.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
var world
var service
var model
class World:
	extends RefCounted
	var state: Dictionary={"world_epoch":5,"revision":1,"status":0}
	var calls: Array=[]
	func reconnect_management():pass
	func session_generation():return 1
	func is_live():return true
	func last_error():return ""
	func poll_management():return state.duplicate(true)
	func management_request(domain,request):
		calls.append({"domain":domain,"request":request.duplicate(true)});return calls.size()
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func facts(id:=227,season:=1) -> Dictionary:
	return {"building_id":id,"selected_season":season,"current_season":1,"revision":9007199254740993,
		"seasonal_crops":[173,175,-1,173],"choices":[
			{"id":175,"name":"Cave wheat","raw_id":"GRASS_WHEAT_CAVE","seeds_available":false,"current_season_warning":false},
			{"id":173,"name":"Plump helmets","raw_id":"MUSHROOM_HELMET_PLUMP","seeds_available":true,"current_season_warning":false}],
		"custom_name":"","header_name":"Farm Plot","removing":false,"removal_suspended":false,"removal_has_worker":false,
		"current_fertilization":0,"max_fertilization":29,"pending_fertilization":0,"seasonal_fertilization":true}
func reply(value: Dictionary, outcome:=0) -> void:
	var sent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,
		"production":{"farm":value,"farm_edit_outcome":outcome}}
	service.poll()
func ready() -> void:
	model.open(227,1);service.poll();reply(facts())
func _initialize() -> void:call_deferred("run")
func run() -> void:
	world=World.new();service=Service.new();service.configure(world);model=Model.new();model.configure(service)
	var applied: Array=[];model.applied.connect(func():applied.append(true))
	model.open(227);service.poll();reply(facts(227,0))
	check(model.phase==Model.Phase.Reading and model.snapshot.is_empty() and world.calls[-1].request.season==1,"initial open follows native current season without exposing wrong tab")
	reply(facts());check(model.phase==Model.Phase.Ready,"current season read ready")
	var before: int=world.calls.size()
	model.choose_crop(999);service.poll();check(world.calls.size()==before,"absent choice cannot submit")
	model.choose_crop(173);model.toggle_fertilization();model.set_seasonal_fertilization(false);service.poll()
	check(world.calls.size()==before+1 and world.calls[-1].request.expected_revision==9007199254740993,"one pending edit uses exact displayed revision")
	check(model.snapshot.seasonal_crops[1]==175,"pending choice does not change native facts")
	var changed:=facts();changed.revision+=1;changed.seasonal_crops[1]=173;changed.choices.reverse()
	reply(changed,C.FarmEditOutcome.Completed)
	check(model.row_order==[175,173] and model.snapshot.choices[0].id==173 and model.choices()[0].id==175,"display order stays frozen while authority preserves fresh order")
	var isolated: Array=model.choices();isolated[0].name="changed"
	check(model.choices()[0].name=="Cave wheat","display rows cannot mutate authority")
	model.set_seasonal_fertilization(false);service.poll()
	check(world.calls[-1].request.farm_operation==2 and world.calls[-1].request.seasonal_fertilization==0 and not world.calls[-1].request.has("crop_id") and world.calls[-1].request.expected_revision==changed.revision,"seasonal command owns only its fields")
	changed.seasonal_fertilization=false;changed.revision+=1;reply(changed,1)
	model.toggle_fertilization();service.poll()
	check(world.calls[-1].request.farm_operation==1 and not world.calls[-1].request.has("seasonal_fertilization"),"immediate fertilizer preserves native toggle intent")
	changed.pending_fertilization=29;changed.revision+=1;reply(changed,1)
	model.select_season(2);service.poll();var tab:=changed.duplicate(true);tab.selected_season=2;reply(tab)
	check(model.row_order==[173,175],"tab change rebuilds native order")
	for outcome in [C.FarmEditOutcome.Rejected,C.FarmEditOutcome.Stale,C.FarmEditOutcome.Unknown]:
		ready();model.toggle_fertilization();service.poll();before=world.calls.size()
		var pending_ticket: int=model.ticket
		reply({},outcome)
		if outcome==C.FarmEditOutcome.Unknown:check(service.result(pending_ticket).get("outcome")=="unknown" and not service.last_detached_mutation("production").is_empty(),"farm Unknown is retained as detached uncertainty by service")
		model.choose_crop(-1);model.toggle_fertilization();service.poll()
		var expected=Model.Phase.Unknown if outcome==4 else Model.Phase.Stale if outcome==3 else Model.Phase.Rejected
		check(model.phase==expected and model.snapshot.is_empty() and model.row_order.is_empty() and world.calls.size()==before,"failure retires authority without replay")
		model.refresh();service.poll();check(world.calls[-1].request.action==C.ManagementAction.ProductionInspect,"explicit recovery only reads")
		reply(facts())
	ready();before=world.calls.size();model.choose_crop(-1);model.close();service.poll()
	check(world.calls.size()==before and model.phase==Model.Phase.Closed,"closing cancels queued unsent edit")
	ready();model.toggle_fertilization();service.poll();before=applied.size();model.open(228,3)
	reply(changed,1);check(model.phase==Model.Phase.Reading and model.snapshot.is_empty() and applied.size()==before,"late sent success cannot revive old farm")
	reply(facts(228,3));check(model.snapshot.building_id==228,"new farm owns its own receipt")
	for invalid in [null,"","A".repeat(129),42]:
		model.open(227,1);service.poll()
		var malformed:=facts();malformed.choices[0].raw_id=invalid
		reply(malformed)
		check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"invalid raw identity cannot grant farm authority")
	for field in ["custom_name","header_name","removing","removal_suspended","removal_has_worker"]:
		model.open(227,1);service.poll()
		var malformed:=facts();malformed.erase(field);reply(malformed)
		check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"missing header cannot grant farm authority")
	for field in ["custom_name","header_name"]:
		model.open(227,1);service.poll()
		var malformed:=facts();malformed[field]="X".repeat(1537);reply(malformed)
		check(model.phase==Model.Phase.Rejected,"oversized header rejected")
	await rename_cases()
	ready()
	model.toggle_fertilization();service.poll();before=world.calls.size()
	world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
	check(model.phase==Model.Phase.Unavailable and model.building_id==-1 and model.snapshot.is_empty(),"epoch retires pending farm")
	model.toggle_fertilization();service.poll();check(world.calls.size()==before,"epoch does not replay edit")
	model.dispose();service.free()
	if failures==0:print("FARM_STATE_PASS")
	quit(1 if failures else 0)

func rename_cases() -> void:
	ready();var before: int=world.calls.size()
	model.rename("x".repeat(91));service.poll()
	check(world.calls.size()==before,"oversized rename remains local")
	model.rename("new farm");model.rename("later");model.choose_crop(-1);service.poll()
	var request: Dictionary=world.calls[-1].request
	check(world.calls.size()==before+1 and request=={"action":C.ManagementAction.FarmEdit,"building_id":227,"season":1,"expected_revision":9007199254740993,"farm_operation":C.FarmOperation.Rename,"farm_name":"new farm"},"rename owns exact intent and one pending slot")
	check(model.snapshot.custom_name=="","pending rename does not fabricate name facts")
	var renamed:=facts();renamed.custom_name="new farm";renamed.header_name="New farm";renamed.revision+=1
	reply(renamed,1);check(model.phase==Model.Phase.Ready and model.snapshot.custom_name=="new farm","rename completion grants fresh authority")
	model.rename("");service.poll();check(world.calls[-1].request.farm_name=="" and world.calls[-1].request.expected_revision==renamed.revision,"clearing submits explicit empty name with latest revision")
	reply(facts(),1)
	for outcome in [2,3,4]:
		ready();model.rename("new farm");service.poll();before=world.calls.size();reply({},outcome)
		model.rename("retry");service.poll()
		check(world.calls.size()==before and model.snapshot.is_empty(),"failed rename cannot replay or retain authority")
		model.refresh();service.poll();check(world.calls[-1].request.action==C.ManagementAction.ProductionInspect,"rename recovery is read-only");reply(facts())
	ready();model.rename("expected");service.poll();reply(renamed,1)
	check(model.phase==Model.Phase.Unknown and model.snapshot.is_empty(),"wrong-name completion cannot grant authority")
	ready();before=world.calls.size();model.rename("queued");model.close();service.poll()
	check(world.calls.size()==before,"retired unsent rename has no effect")
	ready();model.rename("sent");service.poll();model.open(228,2)
	var old:=facts();old.custom_name="sent";old.header_name="Sent";old.revision+=1;reply(old,1)
	check(model.phase==Model.Phase.Reading and model.snapshot.is_empty(),"late rename cannot revive old selection")
	reply(facts(228,2));check(model.snapshot.building_id==228,"new selection owns rename reply lifecycle")
	model.open(227,1);service.poll();var removing:=facts();removing.removing=true;reply(removing)
	before=world.calls.size();model.rename("hidden");model.choose_crop(-1);model.toggle_fertilization();model.set_seasonal_fertilization(false);service.poll()
	check(world.calls.size()==before and model.phase==Model.Phase.Ready,"removal context blocks every hidden farm edit")
