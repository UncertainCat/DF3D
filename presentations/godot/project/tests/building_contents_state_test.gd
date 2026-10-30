extends SceneTree
const Model=preload("res://scripts/building_contents_state.gd")
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
func page(cursor:=0,revision:=9007199254740993,id:=968,total:=70) -> Dictionary:
	var rows: Array=[]
	for index in range(cursor,mini(cursor+64,total)):
		rows.append({"id":1000+index,"role":2,"name":"native caption","forbid":false,"dump":false,"melt":false,"hidden":false,"can_dump":true,"can_melt":false,"in_job":false,"in_building":true,"item_type":53,"material_token":"PLANT:POD_SWEET:SEED","subtype_raw":""})
	return {"building_id":id,"revision":revision,"cursor":cursor,"next_cursor":cursor+rows.size() if cursor+rows.size()<total else 0,"total":total,"completed":true,"removing":false,"rows":rows}
func reply(value: Dictionary,outcome:=0,receipt: Dictionary={}) -> void:
	var sent: Dictionary=world.calls[-1].request
	var production: Dictionary={"farm_edit_outcome":outcome}
	if not value.is_empty():production.contents=value
	if not receipt.is_empty():production.contents_edit=receipt
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Rejected if outcome>1 else C.ManagementStatus.Ok,"production":production}
	service.poll()
func ready() -> void:
	setup();model.open(968);service.poll();reply(page())
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var appearance_page:=page(0,12,278,1);appearance_page.rows[0].item_type=13
	check(not Model.valid_page(appearance_page,278),"Instrument row requires appearance")
	var row: Dictionary=appearance_page.rows[0]
	row.appearance={"material_token":row.material_token,"subtype_raw":row.subtype_raw,"color_token":"","stack":1,"flags":0,"instrument":{"family":3,"placed":0}}
	check(Model.valid_page(appearance_page,278),"Instrument row appearance accepted")
	row.appearance.instrument.family=-1
	check(not Model.valid_page(appearance_page,278),"Invalid instrument row family rejected")
	ready();check(model.phase==Model.Phase.Ready and model.rows().size()==64,"initial bounded page ready")
	var copy: Array=model.rows();copy[0].name="mutated"
	check(model.rows()[0].name=="native caption","view rows cannot mutate authority")
	model.seek(64);service.poll()
	check(world.calls[-1].request.expected_revision==9007199254740993 and world.calls[-1].request.cursor==64,"seek carries exact complete-list revision")
	reply(page(64));check(model.snapshot.rows.size()==6 and model.snapshot.cursor==64,"seek replaces rather than accumulates pages")
	model.seek(5);model.seek(10);service.poll()
	check(world.calls[-1].request.cursor==10,"queued scroll requests coalesce by retirement")
	model.seek(20);reply(page(10))
	check(model.phase==Model.Phase.Reading and model.snapshot.cursor==64,"late sent scroll page cannot replace current authority")
	reply(page(20));check(model.snapshot.cursor==20,"latest scroll owns receipt")
	model.seek(0);service.poll();reply(page(0,9007199254740994))
	check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"pages from another revision cannot mix")
	model.refresh();service.poll();reply(page());check(model.phase==Model.Phase.Ready,"explicit refresh starts a new revision")
	for fault in 13:
		setup();model.open(968);service.poll();var malformed:=page()
		match fault:
			0:malformed.rows[1].id=malformed.rows[0].id
			1:malformed.next_cursor=63
			2:malformed.total=2
			3:malformed.rows[0].can_dump=1
			4:malformed.rows[0].name="x".repeat(131073)
			5:malformed.revision=0
			6:malformed.cursor=1
			7:malformed.building_id=969
			8:malformed.rows[0].erase("item_type")
			9:malformed.rows[0].item_type=93
			10:malformed.rows[0].material_token="x".repeat(257)
			11:malformed.rows[0].subtype_raw="x".repeat(129)
			12:malformed.rows[0].material_token=123
		reply(malformed);check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"malformed page has no authority: "+str(fault))
	ready();var count: int=world.calls.size()
	model.set_flag(1000,C.FarmOperation.ItemMelt,true);model.set_flag(999,C.FarmOperation.ItemHidden,true);service.poll()
	check(world.calls.size()==count,"missing/ineligible rows cannot send")
	model.set_flag(1001,C.FarmOperation.ItemHidden,true);model.set_flag(1000,C.FarmOperation.ItemForbid,true);service.poll()
	check(world.calls.size()==count+1 and not world.calls[-1].request.has("season") and world.calls[-1].request.item_id==1001,"one explicit contents intent owns exact fields")
	check(not model.rows()[1].hidden,"pending edit does not optimistically change flags")
	var changed:=page(1,9007199254740994);changed.rows[0].hidden=true
	reply(changed,1,{"item_id":1001,"farm_operation":C.FarmOperation.ItemHidden,"value":1})
	check(applied==1 and model.phase==Model.Phase.Reading and model.snapshot.is_empty(),"later-row completion retires old pages and requests viewport read")
	check(world.calls[-1].request.action==C.ManagementAction.ProductionInspect and world.calls[-1].request.expected_revision==changed.revision and world.calls[-1].request.cursor==0,"viewport recovery is read-only at new revision")
	var full:=page(0,changed.revision);full.rows[1].hidden=true;reply(full)
	check(model.phase==Model.Phase.Ready and model.snapshot.rows[1].hidden,"fresh viewport restored after edit")
	for outcome in [2,3,4]:
		ready();model.set_flag(1000,C.FarmOperation.ItemHidden,true);service.poll();count=world.calls.size()
		reply({},outcome);model.set_flag(1000,C.FarmOperation.ItemHidden,true);service.poll()
		check(model.phase==(Model.Phase.Unknown if outcome==4 else Model.Phase.Stale if outcome==3 else Model.Phase.Rejected) and model.snapshot.is_empty() and world.calls.size()==count,"failed edits clear authority and never replay")
	ready();model.set_flag(1000,C.FarmOperation.ItemHidden,true);service.poll();reply(page(),1,{"item_id":1000,"farm_operation":C.FarmOperation.ItemHidden,"value":1})
	check(model.phase==Model.Phase.Unknown and applied==0,"wrong observed flag cannot confirm an edit")
	ready();model.set_flag(1000,C.FarmOperation.ItemHidden,true);var queued: int=model.ticket;count=world.calls.size();model.close();service.poll()
	check(world.calls.size()==count and service.result(queued).outcome=="not_sent","closing cancels queued edit")
	ready();model.set_flag(1000,C.FarmOperation.ItemHidden,true);service.poll();model.open(969)
	changed=page(0,9007199254740994);changed.rows[0].hidden=true
	reply(changed,1,{"item_id":1000,"farm_operation":C.FarmOperation.ItemHidden,"value":1})
	check(applied==0 and model.building_id==969 and model.snapshot.is_empty(),"late completion cannot revive prior building")
	reply(page(0,9007199254740993,969));check(model.phase==Model.Phase.Ready,"replacement building owns fresh page")
	for sent in [false,true]:
		ready();model.set_flag(1000,C.FarmOperation.ItemHidden,true);var pending: int=model.ticket
		if sent:service.poll()
		count=world.calls.size();world.state.world_epoch=6;service.poll()
		check(model.phase==Model.Phase.Unavailable and model.building_id==-1 and model.ticket==0 and model.snapshot.is_empty(),"epoch change retires contents")
		check(service.result(pending).outcome==("unknown" if sent else "not_sent") and world.calls.size()==count,"epoch change never replays item intent")
	for enabled in [false,true]:
		setup();model.edit_removing=enabled;model.open(968);service.poll()
		var removing:=page();removing.removing=true;reply(removing)
		model.set_flag(1000,C.FarmOperation.ItemHidden,true)
		check((model.ticket>0)==enabled,"Removal edits require chest opt-in")
		if enabled:
			service.poll();removing.rows[0].hidden=true;removing.revision+=1
			reply(removing,1,{"item_id":1000,"farm_operation":C.FarmOperation.ItemHidden,"value":1})
			check(model.phase==Model.Phase.Ready and model.snapshot.removing and model.snapshot.rows[0].hidden,"Removing chest receipt accepted")
	model.dispose();service.free()
	if failures==0:print("BUILDING_CONTENTS_STATE_PASS")
	quit(0 if failures==0 else 1)
