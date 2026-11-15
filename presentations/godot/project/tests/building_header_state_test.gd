extends SceneTree
const Model=preload("res://scripts/building_header_state.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const C=preload("res://scripts/management_contract.gd")
var failures:=0
var world
var service
var model
var applied:=0
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
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func setup() -> void:
	if model!=null:model.dispose();service.free()
	world=World.new();service=Service.new();service.configure(world);model=Model.new();model.configure(service)
	applied=0;model.applied.connect(func():applied+=1)
func snapshot(id:=278,revision:=9007199254740993) -> Dictionary:
	return {"id":id,"type":10,"revision":revision,"stage":1,"max_stage":1,"custom_name":"","native_name":"native chest","header_name":"Native chest","removing":false,"suspended":false,"has_worker":false,"forbidden":false}
func reply(value: Dictionary,outcome:=0,operation:=0,missing_id: int=-1) -> void:
	var sent: Dictionary=world.calls[-1].request
	var state={"outcome":outcome,"operation":operation}
	if not value.is_empty():state.snapshot=value
	if missing_id!=-1:state.missing_building_id=missing_id
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,"production":{"building_header":state}}
	service.poll()
func ready() -> void:
	setup();model.open(278);service.poll();reply(snapshot())
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for wrong_receipt in [false,true]:
		setup();model.open(278);service.poll()
		var pump:=snapshot();pump.type=33
		pump.machinery={"machine_id":-1,"produced":0,"required":0,"status":0,"stable_foundation":true,"disengaged":false,"pump_manual":0,"pump_direction":0}
		reply(pump);model.set_pump_manual(true);service.poll()
		var count: int=world.calls.size();model.set_pump_manual(false);service.poll()
		check(world.calls.size()==count and world.calls[-1].request.item_value==1,"pending pump input cannot change submitted intent")
		pump.revision+=1;pump.machinery.pump_manual=0 if wrong_receipt else 1
		reply(pump,C.FarmEditOutcome.Completed,C.FarmOperation.PumpManual)
		check(model.phase==(Model.Phase.Unknown if wrong_receipt else Model.Phase.Ready),"pump receipt must confirm explicit setting")
	for kind in [33,40,41,42,43,44,50]:
		var machine:=snapshot();machine.type=kind
		check(not Model.valid_snapshot(machine,278),"machinery requires body")
		machine.machinery={"machine_id":-1,"produced":0,"required":0,"status":C.MachineryStatus.NoNetwork,
			"stable_foundation":true,"disengaged":false,"pump_manual":0 if kind==33 else -1,"pump_direction":0 if kind==33 else -1}
		check(Model.valid_snapshot(machine,278),"valid machinery body")
		machine.machinery.status=C.MachineryStatus.Active
		check(not Model.valid_snapshot(machine,278),"active network needs identity")
		machine.machinery.machine_id=1;machine.machinery.produced=100;machine.machinery.required=20
		check(Model.valid_snapshot(machine,278),"valid active network")
		machine.machinery.stable_foundation=1
		check(not Model.valid_snapshot(machine,278),"foundation flag must be boolean")
	setup();model.open(278);service.poll();reply({},0,0,278)
	check(model.phase==Model.Phase.Closed and model.building_id==-1,"confirmed absent initial target closes header")
	ready();model.poll_refresh(0.5);service.poll();reply({},0,0,278)
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty() and applied==0,"confirmed deletion retires open header without claiming edit")
	for missing_fault in [279,-2]:
		ready();model.poll_refresh(0.5);service.poll();reply({},0,0,missing_fault)
		check(model.phase==Model.Phase.Rejected and model.building_id==278,"invalid missing identity does not close target")
	ready();model.poll_refresh(0.5);service.poll();reply(snapshot(),0,0,278)
	check(model.phase==Model.Phase.Rejected and model.building_id==278,"snapshot mixed with absence rejected")
	ready();model.request_removal();service.poll();reply({},1,C.FarmOperation.Remove,278)
	check(model.phase==Model.Phase.Unknown and model.building_id==278 and applied==0,"missing identity cannot claim mutation completion")
	ready();model.poll_refresh(0.49);service.poll()
	check(world.calls.size()==1,"background reads are rate limited")
	model.poll_refresh(0.01);service.poll()
	check(world.calls.size()==2 and model.ticket==0 and model.phase==Model.Phase.Ready and not model.snapshot.is_empty(),"background read preserves visible interactive authority")
	model.poll_refresh(2.0);service.poll()
	check(world.calls.size()==2,"only one background read outstanding")
	var external:=snapshot();external.removing=true;external.has_worker=true;external.revision+=1
	reply(external)
	check(model.snapshot.has_worker and model.snapshot.removing and applied==0,"external changes update header without claiming an edit")
	ready();model.poll_refresh(0.5);service.poll();reply({},C.FarmEditOutcome.Rejected)
	model.poll_refresh(2.0);service.poll()
	check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty() and world.calls.size()==2,"failed background read retires authority without a retry loop")
	ready();model.poll_refresh(0.5);service.poll();world.state.world_epoch=6;service.poll()
	check(model.phase==Model.Phase.Unavailable and model.refresh_ticket==0 and model.snapshot.is_empty(),"epoch retires pending background authority")
	ready();model.poll_refresh(0.5);service.poll();model.request_removal()
	reply(snapshot())
	check(model.phase==Model.Phase.Applying and model.ticket!=0,"retired background reply cannot overwrite pending edit")
	check(world.calls[-1].request.action==C.ManagementAction.FarmEdit and world.calls[-1].request.expected_revision==9007199254740993,"edit uses displayed authority during background read")
	ready();model.poll_refresh(0.5);check(model.begin_name_entry(),"background read does not block rename")
	model.poll_refresh(2.0);service.poll()
	check(world.calls.size()==1 and model.refresh_ticket==0,"rename retires queued background read and prevents polling")
	model.finish_name_entry()
	ready();model.poll_refresh(0.5);service.poll();model.close();reply(snapshot())
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"late refresh cannot reopen closed panel")
	var memorial:=snapshot();memorial.type=46
	check(not Model.valid_snapshot(memorial,278),"specialized header requires body")
	memorial.funerary={"unit_id":-1,"historical_figure_id":12,"room_id":-1,"room_type":-1,"introduction":"native introduction","name":"native name","room_introduction":"","room_name":"","deceased":"","notices":[]}
	check(Model.valid_snapshot(memorial,278),"memorial body accepted")
	for fault in 8:
		var bad_body: Dictionary=memorial.duplicate(true)
		match fault:
			0:bad_body.type=10
			1:bad_body.funerary.historical_figure_id=-1
			2:bad_body.funerary.name=""
			3:bad_body.funerary.unit_id=1
			4:bad_body.funerary.room_id=1
			5:bad_body.funerary.notices=[""]
			6:bad_body.funerary.deceased="unexpected"
			7:bad_body.funerary.owner_appearance={}
		check(not Model.valid_snapshot(bad_body,278),"malformed memorial body rejected "+str(fault))
	var coffin: Dictionary=memorial.duplicate(true);coffin.type=3
	coffin.funerary.historical_figure_id=-1;coffin.funerary.introduction="";coffin.funerary.name=""
	coffin.funerary.notices=["native roomless notice"]
	check(Model.valid_snapshot(coffin,278),"roomless coffin accepted")
	coffin.funerary.room_id=2;coffin.funerary.room_type=97;coffin.funerary.room_name="native tomb";coffin.funerary.room_introduction="native membership"
	check(not Model.valid_snapshot(coffin,278),"roomless notice cannot accompany membership")
	coffin.funerary.notices=[]
	check(Model.valid_snapshot(coffin,278),"unassigned tomb membership accepted")
	for kind in [0,1,2,5,8,10,11,12,13,14,15,23,51,52,54]:
		var supported:=snapshot();supported.type=kind
		check(Model.valid_snapshot(supported,278),"native header type "+str(kind))
	ready();check(model.phase==Model.Phase.Ready and world.calls[0].request.building_header and not world.calls[0].request.has("season"),"independent header read")
	model.rename("new");service.poll();var sent: Dictionary=world.calls[-1].request
	check(sent.expected_revision==9007199254740993 and sent.farm_name=="new" and not sent.has("season"),"rename preserves exact revision without farm data")
	check(model.snapshot.custom_name=="","rename is not optimistic")
	var renamed:=snapshot(278,9007199254740994);renamed.custom_name="new";renamed.native_name="new";renamed.header_name="New"
	reply(renamed,1,C.FarmOperation.Rename);check(applied==1 and model.phase==Model.Phase.Ready,"confirmed rename accepted")
	renamed.custom_name="external";check(model.snapshot.custom_name=="new","snapshot authority copied")
	model.request_removal();service.poll();var removed: Dictionary=model.snapshot.duplicate(true);removed.removing=true;removed.revision+=1
	reply(removed,1,C.FarmOperation.Remove);check(model.snapshot.removing,"remove receipt accepted")
	var count: int=world.calls.size();model.rename("wrong");model.request_removal();service.poll();check(world.calls.size()==count,"removing blocks rename and second removal")
	model.cancel_removal();service.poll();reply(snapshot(),1,C.FarmOperation.CancelRemoval);check(applied==3 and not model.snapshot.removing,"cancellation receipt accepted")
	for fault in 14:
		setup();model.open(278);service.poll();var bad:=snapshot()
		match fault:
			0:bad.id=279
			1:bad.type=4
			2:bad.revision=0
			3:bad.stage=-1
			4:bad.max_stage=0
			5:bad.header_name=""
			6:bad.custom_name="x".repeat(1537)
			7:bad.has_worker=true
			8:bad.suspended=true
			9:bad.removing=1
			10:bad.revision=1.0
			11:bad.erase("forbidden")
			12:bad.forbidden=1
			13:bad.appearance={}
		reply(bad);check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"malformed header refused "+str(fault))
	for fault in 4:
		ready();model.rename("new");service.poll();var bad:=snapshot();bad.custom_name="new"
		if fault==0:bad.custom_name="wrong"
		if fault==1:bad.removing=true
		if fault==2:bad.stage=0
		reply(bad,1,C.FarmOperation.Remove if fault==3 else C.FarmOperation.Rename)
		check(model.phase==Model.Phase.Unknown and applied==0 and model.snapshot.is_empty(),"mismatched completion has no authority")
	for outcome in [2,3,4]:
		ready();model.rename("new");service.poll();count=world.calls.size();reply({},outcome)
		model.rename("new");service.poll()
		check(model.phase==(Model.Phase.Unknown if outcome==4 else Model.Phase.Stale if outcome==3 else Model.Phase.Rejected) and model.snapshot.is_empty() and world.calls.size()==count,"failed edit is never replayed")
	ready();model.rename("new");var queued: int=model.ticket;count=world.calls.size();model.close();service.poll()
	check(world.calls.size()==count and service.result(queued).outcome=="not_sent","close cancels queued edit")
	ready();model.rename("new");service.poll();model.open(279)
	var late:=snapshot();late.custom_name="new";reply(late,1,C.FarmOperation.Rename)
	check(applied==0 and model.building_id==279 and model.snapshot.is_empty(),"late completion cannot revive old target")
	reply(snapshot(279));check(model.phase==Model.Phase.Ready,"replacement target accepts own read")
	for sent_edit in [false,true]:
		ready();model.rename("new");var pending: int=model.ticket
		if sent_edit:service.poll()
		count=world.calls.size();world.state.world_epoch=6;service.poll()
		check(model.phase==Model.Phase.Unavailable and model.building_id==-1 and model.snapshot.is_empty() and model.ticket==0,"epoch retires header")
		check(service.result(pending).outcome==("unknown" if sent_edit else "not_sent") and world.calls.size()==count,"epoch does not replay edit")
	ready();model.request_removal();service.poll();var detached: int=model.ticket;model.close();reply({},C.FarmEditOutcome.Unknown)
	check(service.result(detached).get("outcome")=="unknown" and service.last_detached_mutation("production").get("result",{}).get("outcome")=="unknown","detached header unknown is retained by service")
	ready();model.request_removal();service.poll();world.state.transport_alive=false;service.poll()
	check(model.phase==Model.Phase.Unavailable and model.snapshot.is_empty(),"disconnect retires header authority")
	ready();check(model.begin_name_entry(),"chest name entry begins")
	model.edit_name_entry("A");model.edit_name_entry("AB");model.edit_name_entry("ABC")
	model.finish_name_entry();service.poll()
	check(world.calls[-1].request.farm_name=="A" and world.calls[-1].request.building_header and not world.calls[-1].request.has("season"),"typed header uses independent intent")
	var typed:=snapshot(278,9007199254740994);typed.custom_name="A";typed.native_name="A";typed.header_name="A"
	reply(typed,1,C.FarmOperation.Rename)
	check(model.phase==Model.Phase.Applying and model.snapshot.custom_name=="A" and world.calls[-1].request.farm_name=="ABC","typing coalesces on confirmed authority")
	typed=typed.duplicate(true);typed.custom_name="ABC";typed.native_name="ABC";typed.header_name="ABC";typed.revision+=1
	reply(typed,1,C.FarmOperation.Rename);check(model.phase==Model.Phase.Ready and model.name_session==null and model.snapshot.custom_name=="ABC","Enter drains final typed text")
	await process_frame
	ready();check(model.begin_name_entry(),"second name entry begins")
	model.edit_name_entry("A");model.edit_name_entry("AB");model.close()
	service.submit("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":279},Callable())
	service.poll();check(world.calls[-1].request.farm_name=="A","closing keeps explicitly typed intent")
	typed=snapshot(278,9007199254740994);typed.custom_name="A";typed.native_name="A";typed.header_name="A"
	reply(typed,1,C.FarmOperation.Rename)
	check(world.calls[-1].request.farm_name=="AB" and world.calls[-1].request.expected_revision==typed.revision,"closing preserves latest text before later interactions")
	typed=typed.duplicate(true);typed.custom_name="AB";typed.native_name="AB";typed.header_name="AB";typed.revision+=1
	reply(typed,1,C.FarmOperation.Rename)
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty() and applied==0 and world.calls[-1].request.building_id==279,"retired panel cannot revive from name continuation")
	await process_frame
	for outcome in [2,3,4]:
		ready();model.begin_name_entry();model.edit_name_entry("A");service.poll();model.edit_name_entry("AB");model.finish_name_entry();reply({},outcome)
		check(model.name_session==null and model.snapshot.is_empty() and world.calls.size()==2,"failed typed session retires buffered text")
		service.poll();check(world.calls.size()==2,"failed typed session never replays")
		await process_frame
	for sent_name in [false,true]:
		ready();model.begin_name_entry();model.edit_name_entry("A")
		if sent_name:service.poll()
		model.edit_name_entry("AB");world.state.world_epoch=6;service.poll()
		check(model.phase==Model.Phase.Unavailable and model.name_session==null and world.calls.size()==1+int(sent_name),"epoch retires typed name session")
		await process_frame
	for kind in [5,13]:
		setup();model.open(278);service.poll();var production:=snapshot();production.type=kind;reply(production)
		check(model.begin_name_entry(),"production name entry begins "+str(kind));model.finish_name_entry()
		model.request_removal();service.poll()
		check(world.calls[-1].request.get("farm_operation",-1)==C.FarmOperation.Remove,"production removal dispatched "+str(kind))
		var removal: Dictionary=production.duplicate(true);removal.removing=true;removal.revision+=1;reply(removal,1,C.FarmOperation.Remove)
		model.cancel_removal();service.poll();reply(production,1,C.FarmOperation.CancelRemoval)
		check(model.phase==Model.Phase.Ready and not model.snapshot.removing,"production cancellation accepted "+str(kind))
		await process_frame
	model.dispose();service.free()
	if failures==0:print("BUILDING_HEADER_STATE_PASS")
	quit(0 if failures==0 else 1)
