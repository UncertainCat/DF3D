extends RefCounted
# One owned item snapshot. Native inspection supplies text, eligibility and revision.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Contents=preload("res://scripts/building_contents_state.gd")
const FIELDS=Contents.FIELDS
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var item_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0

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
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;item_id=-1;snapshot={};phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(building: int, item: int) -> void:
	close()
	if building<0 or building>2147483647 or item<0 or item>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=building;item_id=item;_read()

func refresh() -> void:
	if building_id<0 or item_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func view_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func set_flag(operation: int, desired: bool) -> void:
	if phase!=Phase.Ready or ticket!=0 or not FIELDS.has(operation) or snapshot.is_empty():return
	if not snapshot.completed or snapshot.removing:return
	if operation==C.FarmOperation.ItemDump and not snapshot.can_dump:return
	if operation==C.FarmOperation.ItemMelt and not snapshot.can_melt:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"building_id":building_id,"item_id":item_id,
		"farm_operation":operation,"item_value":int(desired),"expected_revision":snapshot.revision})

func _read() -> void:
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_id":building_id,"item_id":item_id})

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

func _valid(value: Dictionary) -> bool:
	for key in ["id","building_id","role","item_type","revision"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.id!=item_id or value.building_id!=building_id or value.role<0 or value.role>2147483647 or value.item_type<0 or value.item_type>92 or value.revision<=0:return false
	for key in ["completed","removing","forbid","dump","melt","hidden","can_dump","can_melt","in_job","in_building"]:
		if typeof(value.get(key))!=TYPE_BOOL:return false
	for key in ["name","weight","description","material_token","subtype_raw"]:
		var limit: int={"name":131072,"weight":128,"description":32768,"material_token":256,"subtype_raw":128}[key]
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>limit:return false
	if value.has("holder"):
		if typeof(value.holder)!=TYPE_DICTIONARY:return false
		for key in ["id","type"]:
			if typeof(value.holder.get(key))!=TYPE_INT or value.holder[key]<0 or value.holder[key]>2147483647:return false
		if typeof(value.holder.get("name"))!=TYPE_STRING or value.holder.name.to_utf8_buffer().size()>512:return false
	return true

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0
	var owner:=generation
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var production: Dictionary=result.get("production",{})
	var outcome: int=production.get("farm_edit_outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	if result.get("action",-1)!=sent.action or production.get("selected_building",-1)!=building_id or production.has("farm"):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if not editing:
		var value: Dictionary=production.get("item",{})
		if outcome!=C.FarmEditOutcome.None or production.has("contents") or production.has("contents_edit") or not _valid(value):_fail(Phase.Rejected);return
		snapshot=value.duplicate(true);phase=Phase.Ready;changed.emit();return
	var page: Dictionary=production.get("contents",{})
	var receipt: Dictionary=production.get("contents_edit",{})
	if production.has("item") or outcome!=C.FarmEditOutcome.Completed or not Contents.valid_page(page,building_id):_fail(Phase.Unknown);return
	if not page.completed or page.removing or receipt!={"item_id":item_id,"farm_operation":sent.farm_operation,"value":sent.item_value}:_fail(Phase.Unknown);return
	var target: Dictionary={}
	for row in page.rows:
		if row.id==item_id:target=row;break
	if target.is_empty() or target[FIELDS[sent.farm_operation]]!=bool(sent.item_value):_fail(Phase.Unknown);return
	# A contents receipt confirms the edit, not the item's new description/holder.
	# Read those facts afresh; never splice new flags into an old snapshot.
	_read()
	if owner==generation:applied.emit()
