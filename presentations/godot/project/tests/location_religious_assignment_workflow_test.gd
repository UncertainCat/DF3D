extends SceneTree
const Model=preload("res://scripts/location_religious_assignment_workflow.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
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
		calls.append({"domain":domain,"request":request.duplicate(true)})
		return calls.size()
class Details:
	extends RefCounted
	signal changed
	enum Phase { Closed, Ready, Editing, Refreshing }
	var phase:=Phase.Ready
	var generation:=1
	var identity: Dictionary={"site_id":651,"id":0}
	var snapshot: Dictionary={"kind":2,"revision":11}
	var service
	var refreshes:=0
	func refresh():
		refreshes+=1;phase=Phase.Refreshing;changed.emit()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func reply(world,service,area: Dictionary,status:=C.ManagementStatus.Ok) -> void:
	var sent: Dictionary=world.calls[-1].request
	area.operation=sent.operation
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,"status":status,"area":area}
	service.poll()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world=World.new();var service=Service.new();service.configure(world)
	var details=Details.new();details.service=service
	var row={"source":1,"entity_id":383,"assignment_id":2,"histfig_id":-1}
	details.snapshot.staff={"rows":[row]}
	var workflow=Model.new();workflow.configure(details)
	var target={"site_id":651,"location_id":0,"entity_id":383,"assignment_id":2,"position_id":0,"holder_id":-1,"unit_id":-1,"revision":9007199254740993,"removable":false}
	var candidate={"unit_id":7123,"histfig_id":10379,"name":"Synthetic","base_name":"Synthetic","profession_name":"candidate","profession_color":7,"legendary":false,
		"score":1,"source_index":0,"profession_order":0,"status_order":0,"name_sort_key":PackedByteArray([97]),"profession_sort_key":PackedByteArray([112]),"skills":[]}
	var page={"target":target,"revision":99,"cursor":0,"next_cursor":0,"total":1,"rows":[candidate]}
	var receipt={"target":target,"unit_id":7123,"histfig_id":10379,"nemesis_id":7120,"revision":9007199254740995,"list_revision":99,"eligible":true}
	var applied=target.duplicate(true);applied.holder_id=10379;applied.unit_id=7123;applied.removable=true;applied.revision+=4
	workflow.open(row);workflow.open(row);service.poll()
	check(world.calls.size()==1 and world.calls[-1].request.operation==C.AreaOperation.LocationReligiousCandidates,"vacant gesture opens one native list")
	reply(world,service,{"location_religious_candidates":page})
	check(workflow.candidates.phase==workflow.candidates.Phase.Ready,"full list selectable")
	workflow.choose(999);service.poll();check(world.calls.size()==1,"absent candidate cannot request authority")
	workflow.choose(7123);workflow.choose(7123);service.poll()
	check(world.calls.size()==2 and details.phase==Details.Phase.Editing,"selection locks details and reads once")
	reply(world,service,{"location_religious_assignment":receipt});service.poll()
	check(world.calls.size()==3 and world.calls[-1].request.expected_revision==9007199254740995 and world.calls[-1].request.expected_list_revision==99,"both exact receipts bind assignment")
	reply(world,service,{"location_religious_staff":applied,"location_edit_outcome":C.LocationEditOutcome.Completed})
	check(details.refreshes==1 and workflow.mode==Model.Mode.Closed,"completed assignment refreshes once")
	for stage in ["queued read","sent read","queued assignment","sent assignment"]:
		details.phase=Details.Phase.Ready;details.snapshot.revision+=1;details.changed.emit();workflow.close();workflow.open(row);service.poll()
		reply(world,service,{"location_religious_candidates":page});workflow.choose(7123)
		if stage!="queued read":service.poll()
		if stage in ["queued assignment","sent assignment"]:reply(world,service,{"location_religious_assignment":receipt})
		if stage=="sent assignment":service.poll()
		var count: int=world.calls.size();workflow.close();service.poll()
		check(world.calls.size()==count and workflow.mode==Model.Mode.Closed and details.phase==Details.Phase.Ready,"close detaches "+stage)
		if stage=="sent read":reply(world,service,{"location_religious_assignment":receipt})
		if stage=="sent assignment":reply(world,service,{"location_religious_staff":applied,"location_edit_outcome":C.LocationEditOutcome.Completed})
		check(details.refreshes==1 and world.calls.size()==count,"late result cannot resume "+stage)
	for outcome in [C.LocationEditOutcome.Rejected,C.LocationEditOutcome.Stale,C.LocationEditOutcome.Unknown]:
		details.snapshot.revision+=1;details.changed.emit();workflow.close();workflow.open(row);service.poll()
		reply(world,service,{"location_religious_candidates":page});workflow.choose(7123);service.poll()
		reply(world,service,{"location_religious_assignment":receipt});service.poll()
		reply(world,service,{"location_edit_outcome":outcome},C.ManagementStatus.Rejected)
		var count: int=world.calls.size();workflow.close();workflow.open(row);service.poll()
		check(world.calls.size()==count and details.phase==Details.Phase.Ready,"failed assignment cannot replay at same details revision")
	details.snapshot.revision+=1;details.changed.emit();workflow.close();workflow.open(row);service.poll()
	reply(world,service,{"location_religious_candidates":page});workflow.choose(7123);service.poll()
	var mismatch=receipt.duplicate(true);mismatch.list_revision=100
	var count: int=world.calls.size();reply(world,service,{"location_religious_assignment":mismatch});service.poll()
	check(world.calls.size()==count and workflow.mode==Model.Mode.Stale,"selected receipt cannot adopt another list")
	details.snapshot.revision+=1;details.changed.emit();workflow.close();workflow.open(row);service.poll()
	reply(world,service,{"location_religious_candidates":page});workflow.choose(7123);service.poll()
	reply(world,service,{"location_religious_assignment":receipt});service.poll();count=world.calls.size()
	details.generation+=1;details.identity.id=7;details.changed.emit()
	reply(world,service,{"location_religious_staff":applied,"location_edit_outcome":C.LocationEditOutcome.Completed})
	check(details.refreshes==1 and details.identity.id==7,"replacement panel ignores late success")
	details.identity.id=0;details.generation+=1;details.phase=Details.Phase.Ready;details.changed.emit();workflow.close();workflow.open(row);service.poll()
	count=world.calls.size();world.state={"world_epoch":6,"revision":1,"status":0};service.poll();service.poll()
	check(world.calls.size()==count and workflow.mode==Model.Mode.Unavailable,"epoch loss retires list without replay")
	workflow.dispose()
	# A partial religious list never becomes selectable, and continuations must
	# retain the exact target receipt even when the list revision stays unchanged.
	world.state={"world_epoch":5,"revision":1,"status":0};service.poll()
	var pages=preload("res://scripts/location_staff_candidates_state.gd").new();pages.configure(service)
	for changed in [false,true]:
		pages.open_religious({"site_id":651,"location_id":0,"entity_id":383,"assignment_id":2,"holder_id":-1});service.poll()
		var first=page.duplicate(true);first.total=129;first.next_cursor=128;first.rows=[]
		for i in range(128):
			var item=candidate.duplicate(true);item.unit_id+=i;item.source_index=i;first.rows.append(item)
		reply(world,service,{"location_religious_candidates":first})
		check(pages.rows.is_empty() and pages.phase==pages.Phase.Reading,"partial religious list is not selectable")
		var last=page.duplicate(true);last.cursor=128;last.total=129;last.rows[0].unit_id+=128;last.rows[0].source_index=128
		if changed:last.target.revision+=1
		reply(world,service,{"location_religious_candidates":last})
		check(pages.phase==(pages.Phase.Rejected if changed else pages.Phase.Ready),"continuation validates religious target receipt")
		check(pages.rows.size()==(0 if changed else 129),"only complete consistent list is retained")
	pages.close();service.session_changed.disconnect(pages._session_changed);service.free()
	if failures==0:print("LOCATION_RELIGIOUS_ASSIGNMENT_WORKFLOW_PASS")
	quit(1 if failures else 0)
