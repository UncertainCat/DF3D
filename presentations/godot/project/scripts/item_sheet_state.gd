extends RefCounted
# One owned item snapshot. Native inspection supplies text, eligibility and revision.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Contents=preload("res://scripts/building_contents_state.gd")
const FIELDS=Contents.FIELDS
const REFRESH_INTERVAL:=0.25
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var item_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var background_refresh:=false
var refresh_remaining:=0.0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	background_refresh=false;refresh_remaining=0
	if service!=null and previous!=0:service.detach(previous)
	item_id=-1;snapshot={};phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(item: int) -> void:
	close()
	if item<0 or item>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	item_id=item;_read()

func refresh() -> void:
	if item_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func poll(delta: float) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	refresh_remaining-=maxf(0,delta)
	if refresh_remaining<=0:_read(true)

func view_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func set_flag(operation: int, desired: bool) -> void:
	if phase!=Phase.Ready or (ticket!=0 and not background_refresh) or not FIELDS.has(operation) or snapshot.is_empty():return
	if operation==C.FarmOperation.ItemDump and not snapshot.can_dump:return
	if operation==C.FarmOperation.ItemMelt and not snapshot.can_melt:return
	# A read has no effects to replay. Explicit edits retire its observer and use
	# the last complete revision; DF still validates that revision before writing.
	if background_refresh:
		generation+=1
		var previous:=ticket;ticket=0;background_refresh=false
		service.detach(previous)
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"independent_item":true,"item_id":item_id,
		"farm_operation":operation,"item_value":int(desired),"expected_revision":snapshot.revision})

func _read(background:=false) -> void:
	background_refresh=background
	if not background:snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":item_id})

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	if not background_refresh:changed.emit()

func _fail(next: Phase) -> void:
	if background_refresh:close();return
	phase=next;snapshot={};changed.emit()

func _valid(value: Dictionary) -> bool:
	for key in ["id","item_type","revision","stockpile_categories"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.id!=item_id or value.item_type<0 or value.item_type>92 or value.revision<=0:return false
	for key in ["forbid","dump","melt","hidden","can_dump","can_melt","in_job","in_building"]:
		if typeof(value.get(key))!=TYPE_BOOL:return false
	for key in ["name","weight","description","material_token","subtype_raw"]:
		var limit: int={"name":131072,"weight":128,"description":32768,"material_token":256,"subtype_raw":128}[key]
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>limit:return false
	if value.has("stockpile"):
		if value.stockpile_categories<0 or value.stockpile_categories>0x1ffff:return false
	elif value.stockpile_categories!=-1:return false
	if value.has("carrier"):
		var carrier=value.carrier
		if value.has("holder") or typeof(carrier)!=TYPE_DICTIONARY:return false
		for key in ["kind","id","item_type"]:
			if typeof(carrier.get(key))!=TYPE_INT:return false
		if carrier.id<0 or carrier.id>2147483647 or carrier.kind not in [1,2]:return false
		if carrier.kind==1 and (carrier.item_type<0 or carrier.item_type>92):return false
		if carrier.kind==2 and carrier.item_type!=-1:return false
		if typeof(carrier.get("name"))!=TYPE_STRING or carrier.name.to_utf8_buffer().size()>512:return false
	for forbidden in ["building_id","role","completed","removing"]:
		if value.has(forbidden):return false
	for field in ["holder","stockpile"]:
		if not value.has(field):continue
		var link=value[field]
		if typeof(link)!=TYPE_DICTIONARY:return false
		for key in ["id","type"]:
			if typeof(link.get(key))!=TYPE_INT or link[key]<0 or link[key]>2147483647:return false
		if typeof(link.get("name"))!=TYPE_STRING or link.name.to_utf8_buffer().size()>512:return false
		if field=="stockpile" and link.type!=29:return false
	return true

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0;refresh_remaining=REFRESH_INTERVAL
	var owner:=generation
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var production: Dictionary=result.get("production",{})
	var state: Dictionary=production.get("independent_item",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	if result.get("action",-1)!=sent.action or production.get("selected_building",-1)!=-1:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	for field in ["farm","contents","contents_edit","item","item_position"]:
		if production.has(field):_fail(Phase.Unknown if editing else Phase.Rejected);return
	var value: Dictionary=state.get("snapshot",{})
	if not _valid(value):_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		if outcome!=C.FarmEditOutcome.Completed or state.get("edit",{})!={"item_id":item_id,"farm_operation":sent.farm_operation,"value":sent.item_value} or value[FIELDS[sent.farm_operation]]!=bool(sent.item_value):
			_fail(Phase.Unknown);return
	elif outcome!=C.FarmEditOutcome.None or state.has("edit"):_fail(Phase.Rejected);return
	# A confirmed independent receipt already contains a coherent fresh observation.
	var different: bool=not background_refresh or snapshot!=value
	background_refresh=false;snapshot=value.duplicate(true);phase=Phase.Ready
	if different:changed.emit()
	if editing and owner==generation:applied.emit()
