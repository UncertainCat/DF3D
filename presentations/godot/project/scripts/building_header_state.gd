extends RefCounted
# One building's independently revisioned header authority; DF owns all effects.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var name_session
var refresh_ticket:=0
var refresh_age:=0.0

func _retire_refresh() -> void:
	var previous:=refresh_ticket;refresh_ticket=0;refresh_age=0.0
	if service!=null and previous!=0:service.detach(previous)

# Reads retain the displayed authority and never reserve the input controls.
# An edit retires the read and still uses the displayed revision as its guard.
func poll_refresh(delta: float) -> void:
	if phase!=Phase.Ready or ticket!=0 or name_session!=null:return
	refresh_age+=maxf(0.0,delta)
	if refresh_ticket!=0 or refresh_age<0.5:return
	refresh_age=0.0
	var owner:=generation
	refresh_ticket=service.submit("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":building_id},func(received,result,sent):
		if owner!=generation or received!=refresh_ticket:return
		refresh_ticket=0;refresh_age=0.0
		_receive(result,sent))
	if refresh_ticket==0:_fail(Phase.Unavailable)

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	_retire_refresh()
	generation+=1
	var previous_name=name_session;name_session=null
	if previous_name!=null:previous_name.finish()
	var previous:=ticket;ticket=0;building_id=-1;snapshot={};phase=Phase.Closed
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=id;_read()

func refresh() -> void:
	if building_id<0 or ticket!=0 or name_session!=null or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func _read() -> void:
	_retire_refresh()
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":building_id})

func begin_name_entry() -> bool:
	if phase!=Phase.Ready or ticket!=0 or name_session!=null or snapshot.get("type",-1) not in [0,1,2,3,5,8,9,10,11,12,13,14,15,18,23,33,35,36,37,38,39,40,41,42,43,44,46,50,51,52,54] or snapshot.get("removing",true) or snapshot.stage!=snapshot.max_stage:return false
	_retire_refresh()
	var owner:=generation
	var owned=load("res://scripts/farm_rename_session.gd").new()
	service.add_child(owned);owned.configure(service,snapshot,true)
	if owned.stopped:return false
	name_session=owned;phase=Phase.Applying
	owned.changed.connect(func(observed):
		if owner!=generation or name_session!=owned:return
		snapshot=observed.duplicate(true);phase=Phase.Applying;changed.emit();applied.emit())
	owned.finished.connect(func():
		if owner!=generation or name_session!=owned:return
		name_session=null;phase=Phase.Ready;changed.emit())
	owned.failed.connect(func(result):
		if owner!=generation or name_session!=owned:return
		name_session=null
		var outcome: int=result.get("production",{}).get("building_header",{}).get("outcome",C.FarmEditOutcome.None)
		_fail(Phase.Unknown if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown else Phase.Stale if outcome==C.FarmEditOutcome.Stale else Phase.Rejected))
	changed.emit();return true

func edit_name_entry(value: String) -> void:
	if name_session!=null:name_session.edit(value)

func finish_name_entry() -> void:
	if name_session!=null:name_session.finish()

func rename(value: String) -> void:
	var bytes:=value.to_utf8_buffer()
	if bytes.size()>90 or bytes.has(0):return
	_edit(C.FarmOperation.Rename,{"farm_name":value})

func request_removal() -> void:_edit(C.FarmOperation.Remove,{})
func cancel_removal() -> void:_edit(C.FarmOperation.CancelRemoval,{})
func set_pump_manual(desired: bool) -> void:
	if snapshot.get("type",-1)!=33 or not snapshot.has("machinery"):return
	_edit(C.FarmOperation.PumpManual,{"item_value":int(desired)})

func _edit(operation: int,fields: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.is_empty() or snapshot.get("type",-1) not in [0,1,2,3,5,8,9,10,11,12,13,14,15,18,23,33,35,36,37,38,39,40,41,42,43,44,46,50,51,52,54] or snapshot.stage!=snapshot.max_stage:return
	if snapshot.removing!=(operation==C.FarmOperation.CancelRemoval):return
	_retire_refresh()
	var intent={"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":building_id,
		"expected_revision":snapshot.revision,"farm_operation":operation}
	intent.merge(fields);phase=Phase.Applying;_send(intent)

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

static func valid_snapshot(value: Dictionary,id: int) -> bool:
	for field in ["id","type","revision","stage","max_stage"]:
		if typeof(value.get(field))!=TYPE_INT:return false
	if value.id!=id or id<0 or id>2147483647 or value.type not in [0,1,2,3,5,8,9,10,11,12,13,14,15,18,23,33,35,36,37,38,39,40,41,42,43,44,46,50,51,52,54] or value.revision<=0 or value.stage<0 or value.max_stage<value.stage or value.max_stage>2147483647:return false
	for field in ["custom_name","native_name","header_name"]:
		if typeof(value.get(field))!=TYPE_STRING:return false
		var bytes: PackedByteArray=value[field].to_utf8_buffer()
		if bytes.size()>1536 or bytes.has(0) or (field!="custom_name" and bytes.is_empty()):return false
	for field in ["removing","suspended","has_worker","forbidden"]:
		if typeof(value.get(field))!=TYPE_BOOL:return false
	if value.has("appearance") and not preload("res://scripts/item_sheet_state.gd")._valid_recipe(value.appearance):return false
	if not valid_funerary(value) or not valid_machinery(value) or not valid_well(value):return false
	return value.removing or (not value.suspended and not value.has_worker)

static func valid_well(value: Dictionary) -> bool:
	if value.type!=18:return not value.has("well")
	return typeof(value.get("well"))==TYPE_DICTIONARY and value.well.size()==1 and typeof(value.well.get("status"))==TYPE_INT and value.well.status in [0,1,2,3]

static func valid_machinery(value: Dictionary) -> bool:
	if value.type not in [33,40,41,42,43,44,50]:return not value.has("machinery")
	if typeof(value.get("machinery"))!=TYPE_DICTIONARY:return false
	var body: Dictionary=value.machinery
	if body.size()!=8:return false
	for field in ["machine_id","produced","required","status","pump_manual","pump_direction"]:
		if typeof(body.get(field))!=TYPE_INT or body[field]<-2147483648 or body[field]>2147483647:return false
	for field in ["stable_foundation","disengaged"]:
		if typeof(body.get(field))!=TYPE_BOOL:return false
	if body.status<0 or body.status>4 or body.machine_id<-1 or (body.status!=0)!=(body.machine_id>=0):return false
	if body.status==0 and (body.produced!=0 or body.required!=0):return false
	if body.disengaged and value.type!=40:return false
	return (body.pump_manual in [0,1] and body.pump_direction in [0,1,2,3]) if value.type==33 else (body.pump_manual==-1 and body.pump_direction==-1)

static func valid_funerary(value: Dictionary) -> bool:
	if value.type not in [3,46]:return not value.has("funerary")
	if typeof(value.get("funerary"))!=TYPE_DICTIONARY:return false
	var body: Dictionary=value.funerary
	for field in ["unit_id","historical_figure_id","room_id","room_type"]:
		if typeof(body.get(field))!=TYPE_INT or body[field]<-1 or body[field]>2147483647:return false
	for field in ["introduction","name","room_introduction","room_name","deceased"]:
		if typeof(body.get(field))!=TYPE_STRING:return false
		var bytes: PackedByteArray=body[field].to_utf8_buffer()
		if bytes.size()>1536 or bytes.has(0):return false
	if typeof(body.get("notices"))!=TYPE_ARRAY or body.notices.size()>3:return false
	for notice in body.notices:
		if typeof(notice)!=TYPE_STRING or notice.is_empty():return false
		var bytes: PackedByteArray=notice.to_utf8_buffer()
		if bytes.size()>1536 or bytes.has(0):return false
	var named: bool=not body.name.is_empty()
	var owner: bool=body.unit_id>=0
	var room: bool=body.room_id>=0
	if named!=not body.introduction.is_empty():return false
	if room!=(body.room_type==97) or (not room and body.room_type!=-1):return false
	if room!=not body.room_name.is_empty() or room!=not body.room_introduction.is_empty():return false
	if owner!=body.has("owner_appearance") or (not owner and not body.deceased.is_empty()):return false
	if owner and not preload("res://scripts/item_sheet_state.gd")._valid_recipe(body.owner_appearance):return false
	if value.type==3:
		return body.historical_figure_id==-1 and named==owner and (not owner or room) and (body.notices.is_empty() or (not named and not room))
	return not owner and not room and body.notices.is_empty() and named==(body.historical_figure_id>=0)

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var state: Dictionary=result.get("production",{}).get("building_header",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	var observed: Dictionary=state.get("snapshot",{})
	var operation: int=state.get("operation",-1)
	var missing=state.get("missing_building_id",-1)
	if typeof(missing)!=TYPE_INT or missing< -1:_fail(Phase.Unknown if editing else Phase.Rejected);return
	if missing>=0:
		if editing or missing!=building_id or result.get("action",-1)!=sent.action or state.has("snapshot") or outcome!=C.FarmEditOutcome.None or operation!=C.FarmOperation.Crop:
			_fail(Phase.Unknown if editing else Phase.Rejected);return
		close();return
	if result.get("action",-1)!=sent.action or not valid_snapshot(observed,building_id) or \
		outcome!=(C.FarmEditOutcome.Completed if editing else C.FarmEditOutcome.None) or \
		operation!=(sent.farm_operation if editing else C.FarmOperation.Crop):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		if observed.stage!=observed.max_stage or observed.removing!=(operation==C.FarmOperation.Remove) or \
			(operation==C.FarmOperation.Rename and observed.custom_name!=sent.farm_name) or \
			(operation==C.FarmOperation.PumpManual and (observed.type!=33 or observed.machinery.pump_manual!=sent.item_value)):
			_fail(Phase.Unknown);return
	var different: bool=phase!=Phase.Ready or snapshot!=observed
	snapshot=observed.duplicate(true);phase=Phase.Ready
	if different:changed.emit()
	if editing:applied.emit()
