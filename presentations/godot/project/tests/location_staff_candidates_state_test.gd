extends SceneTree
const Model = preload("res://scripts/location_staff_candidates_state.gd")
const Service = preload("res://scripts/semantic_action_service.gd")
const C = preload("res://scripts/management_contract.gd")
const TARGET = {"site_id":651,"location_id":2,"occupation_id":87,"role":8}
var failures := 0
class World:
	extends RefCounted
	var state := {"world_epoch":5,"revision":1,"status":0}
	var calls: Array = []
	func reconnect_management(): pass
	func session_generation(): return 1
	func is_live(): return true
	func last_error(): return ""
	func poll_management(): return state.duplicate(true)
	func management_request(domain,request):
		calls.append({"domain":domain,"request":request.duplicate(true)})
		return calls.size()
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func page(cursor: int, total: int) -> Dictionary:
	var result: Dictionary=TARGET.duplicate()
	result.merge({"revision":9007199254740993,"cursor":cursor,"total":total,
		"next_cursor":cursor+128 if total>cursor+128 else 0,"rows":[]})
	for index in range(cursor,mini(cursor+128,total)):
		result.rows.append({"unit_id":100+index,"histfig_id":900+index,"name":"Synthetic candidate %d"%index,
			"source_index":index,"profession_order":809,"status_order":0,"name_sort_key":PackedByteArray([97]),"profession_sort_key":PackedByteArray([112]),
			"base_name":"Synthetic","profession_name":"candidate","profession_color":7,"legendary":true,"score":1000-index,"skills":[{"id":58,"rating":1000-index,"experience":2000000,"weight":1}]})
	return result
func reply(world,service,facts: Dictionary, status := C.ManagementStatus.Ok) -> void:
	var intent: Dictionary=world.calls[-1].request
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
		"action":intent.action,"status":status,"area":{"operation":intent.operation,"location_staff_candidates":facts}}
	service.poll()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=World.new();var service=Service.new();service.configure(world)
	var model=Model.new();model.configure(service)
	model.open(TARGET);service.poll()
	check(world.calls.size()==1 and world.calls[-1].request=={
		"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationStaffCandidates,"kind":1,
		"location_site_id":651,"location_id":2,"occupation_id":87,"cursor":0,"expected_list_revision":0},"opening sends one read with semantic identities")
	reply(world,service,page(0,260))
	check(model.phase==Model.Phase.Reading and model.rows.is_empty() and world.calls.size()==2,"partial page is not a selectable list")
	check(world.calls[-1].request.cursor==128 and world.calls[-1].request.expected_list_revision==9007199254740993,"continuation keeps exact64-bit receipt")
	reply(world,service,page(128,260));reply(world,service,page(256,260))
	check(model.phase==Model.Phase.Ready and model.rows.size()==260 and model.rows[259].unit_id==359,"complete native order is published after all pages")
	check(model.revision==9007199254740993,"completed list retains receipt")
	var count: int=world.calls.size();model.refresh();model.refresh();service.poll()
	check(world.calls.size()==count+1 and model.phase==Model.Phase.Refreshing and model.rows.size()==260,"refresh keeps confirmed rows but cannot duplicate a request")
	var replacement:=page(0,1);reply(world,service,replacement)
	replacement.rows[0].skills[0].rating=-1
	check(model.rows.size()==1 and model.rows[0].skills[0].rating==1000,"published rows own nested facts")
	# Even individually valid wire pages can disagree across a receipt boundary.
	for variant in 21:
		model.open(TARGET);service.poll()
		var first_page:=page(0,260)
		if variant==20:first_page.rows[-1].source_index=259
		reply(world,service,first_page)
		var invalid:=page(128,260)
		if variant==0:invalid.revision+=1
		if variant==1:invalid.total=261
		if variant==2:invalid.occupation_id+=1
		if variant==3:invalid.role=9
		if variant==4:invalid.rows[0].unit_id=100
		if variant==5:invalid.rows[0].score=999
		if variant==6:invalid.cursor=0
		if variant==7:invalid.next_cursor=128
		if variant==8:invalid.rows.pop_back()
		if variant==9:invalid.rows[0].erase("base_name")
		if variant==10:invalid.rows[0].profession_name=null
		if variant==11:invalid.rows[0].profession_color=16
		if variant==12:invalid.rows[0].legendary=1
		if variant==13:invalid.rows[0].source_index=0
		if variant==14:invalid.rows[0].source_index=260
		if variant==15:invalid.rows[0].profession_order=-1
		if variant==16:invalid.rows[0].status_order=-1
		if variant==17:invalid.rows[0].erase("name_sort_key")
		if variant==18:invalid.rows[0].profession_sort_key=[]
		if variant==19:invalid.rows[0].name_sort_key=PackedByteArray();invalid.rows[0].name_sort_key.resize(2049)
		if variant==20:invalid.rows[0].score=first_page.rows[-1].score;invalid.rows[0].skills[0].rating=first_page.rows[-1].score
		count=world.calls.size();reply(world,service,invalid);model.refresh();service.poll()
		check(model.phase==Model.Phase.Rejected and model.rows.is_empty() and world.calls.size()==count,"mixed or invalid pages must clear pending rows without replay: %d"%variant)
	model.open(TARGET);service.poll();reply(world,service,page(0,0))
	check(model.phase==Model.Phase.Ready and model.rows.is_empty() and model.revision>0,"observed empty list is ready, not unknown")
	model.open(TARGET);service.poll();reply(world,service,{},C.ManagementStatus.Rejected)
	count=world.calls.size();model.refresh();service.poll()
	check(model.phase==Model.Phase.Rejected and world.calls.size()==count,"native refusal does not automatically retry")
	model.open(TARGET);model.close();service.poll()
	check(world.calls.size()==count,"close cancels an unsent read")
	model.open(TARGET);service.poll();model.close();model.open(TARGET)
	reply(world,service,page(0,1))
	check(model.phase==Model.Phase.Reading and model.rows.is_empty(),"late reply cannot populate reopened selector")
	reply(world,service,page(0,1))
	check(model.phase==Model.Phase.Ready,"reopened selector uses its own receipt")
	# Close from a signal before the queued continuation can reach DF.
	var cancel_continuation=func():
		if model.phase==Model.Phase.Reading and model._pending_rows.size()==128:model.close()
	model.changed.connect(cancel_continuation)
	model.open(TARGET);service.poll();count=world.calls.size();reply(world,service,page(0,260))
	check(model.phase==Model.Phase.Closed and world.calls.size()==count,"close cancels a queued continuation")
	model.changed.disconnect(cancel_continuation)
	model.open(TARGET);service.poll();service.poll(16.0)
	check(model.phase==Model.Phase.Unavailable and model.rows.is_empty(),"lost read receipt cannot become a ready list")
	model.close();reply(world,service,page(0,1))
	check(model.phase==Model.Phase.Closed,"late timed-out receipt cannot reopen selector")
	model.open(TARGET);service.poll();world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
	check(model.phase==Model.Phase.Unavailable and model.identity.is_empty(),"epoch change retires selector identity")
	count=world.calls.size()
	for key in TARGET:
		var invalid: Dictionary=TARGET.duplicate();invalid[key]=float(invalid[key]);model.open(invalid);service.poll()
		check(model.phase==Model.Phase.Rejected and world.calls.size()==count,"noninteger selector identity cannot reach transport")
	model.close();service.free()
	print("LOCATION_STAFF_CANDIDATES_STATE_PASS" if failures==0 else "LOCATION_STAFF_CANDIDATES_STATE_FAIL")
	quit(failures)
