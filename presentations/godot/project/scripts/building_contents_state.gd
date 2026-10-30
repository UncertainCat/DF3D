extends RefCounted
# One bounded viewport page. DF owns ordering, captions, eligibility and effects.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
const FIELDS={C.FarmOperation.ItemForbid:"forbid",C.FarmOperation.ItemDump:"dump",C.FarmOperation.ItemMelt:"melt",C.FarmOperation.ItemHidden:"hidden"}
var service
var edit_removing:=false
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var _wanted_cursor:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)

func close() -> void:
	_retire();building_id=-1;snapshot={};_wanted_cursor=0;phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=id;_read(0,0)

func refresh() -> void:
	if building_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	snapshot={};_read(0,0)

func seek(cursor: int) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or snapshot.is_empty() or cursor<0 or cursor>=snapshot.total:return
	if cursor==snapshot.cursor:
		if ticket!=0:_retire();phase=Phase.Ready;changed.emit()
		return
	var revision: int=snapshot.revision
	_retire();_read(cursor,revision)

func rows() -> Array:
	return snapshot.get("rows",[]).duplicate(true)

func set_flag(item_id: int, operation: int, desired: bool) -> void:
	if phase!=Phase.Ready or ticket!=0 or not FIELDS.has(operation) or snapshot.is_empty():return
	if not snapshot.completed or (snapshot.removing and not edit_removing):return
	var selected: Dictionary={}
	for row in snapshot.rows:
		if row.id==item_id:selected=row;break
	if selected.is_empty():return
	if operation==C.FarmOperation.ItemDump and not selected.can_dump:return
	if operation==C.FarmOperation.ItemMelt and not selected.can_melt:return
	_wanted_cursor=snapshot.cursor;phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"building_id":building_id,"farm_operation":operation,
		"item_id":item_id,"item_value":int(desired),"expected_revision":snapshot.revision})

func _read(cursor: int, revision: int) -> void:
	_wanted_cursor=cursor;phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_id":building_id,"contents":true,
		"cursor":cursor,"expected_revision":revision})

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

static func valid_page(page: Dictionary, expected_building: int) -> bool:
	for key in ["building_id","revision","cursor","next_cursor","total"]:
		if typeof(page.get(key))!=TYPE_INT:return false
	if page.building_id!=expected_building or page.revision<=0 or page.total<0 or page.total>4294967295 or page.cursor<0 or page.cursor>page.total:return false
	if typeof(page.get("completed"))!=TYPE_BOOL or typeof(page.get("removing"))!=TYPE_BOOL or typeof(page.get("rows"))!=TYPE_ARRAY:return false
	if page.rows.size()>64 or page.rows.size()>page.total-page.cursor:return false
	var end: int=page.cursor+page.rows.size()
	if end<page.total:
		if page.rows.is_empty() or page.next_cursor!=end:return false
	elif page.next_cursor!=0:return false
	if page.total>0 and page.cursor==page.total:return false
	var ids: Dictionary={};var bytes:=0
	for row in page.rows:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for key in ["id","role"]:
			if typeof(row.get(key))!=TYPE_INT or row[key]<0 or row[key]>2147483647:return false
		if ids.has(row.id) or typeof(row.get("name"))!=TYPE_STRING:return false
		if typeof(row.get("item_type"))!=TYPE_INT or row.item_type<0 or row.item_type>92:return false
		for key in ["material_token","subtype_raw"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>(256 if key=="material_token" else 128):return false
		if row.item_type in [13,30] and not row.has("appearance"):return false
		if row.has("appearance"):
			if not preload("res://scripts/item_sheet_state.gd")._valid_appearance(row.appearance,row.item_type):return false
			if row.appearance.material_token!=row.material_token or row.appearance.subtype_raw!=row.subtype_raw:return false
		ids[row.id]=true;bytes+=row.name.to_utf8_buffer().size()
		if bytes>128*1024:return false
		for key in ["forbid","dump","melt","hidden","can_dump","can_melt","in_job","in_building"]:
			if typeof(row.get(key))!=TYPE_BOOL:return false
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
	var page: Dictionary=production.get("contents",{})
	if result.get("action",-1)!=sent.action or production.has("farm") or not valid_page(page,building_id):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if not editing:
		if outcome!=C.FarmEditOutcome.None or production.has("contents_edit") or page.cursor!=sent.cursor or (sent.expected_revision>0 and page.revision!=sent.expected_revision):_fail(Phase.Rejected);return
		if not snapshot.is_empty() and sent.expected_revision>0 and (page.total!=snapshot.total or page.completed!=snapshot.completed or page.removing!=snapshot.removing):_fail(Phase.Rejected);return
		snapshot=page.duplicate(true);phase=Phase.Ready;changed.emit();return
	var receipt: Dictionary=production.get("contents_edit",{})
	if outcome!=C.FarmEditOutcome.Completed or not page.completed or (page.removing and not edit_removing) or page.removing!=snapshot.removing or receipt!={"item_id":sent.item_id,"farm_operation":sent.farm_operation,"value":sent.item_value}:
		_fail(Phase.Unknown);return
	var target: Dictionary={}
	for row in page.rows:
		if row.id==sent.item_id:target=row;break
	if target.is_empty() or target[FIELDS[sent.farm_operation]]!=bool(sent.item_value):_fail(Phase.Unknown);return
	# Never combine old pages with the new revision. A receipt may start at the
	# clicked row; recover the old viewport offset with a read, never another edit.
	snapshot={}
	var cursor:=mini(_wanted_cursor,maxi(0,page.total-1))
	if page.cursor==cursor:
		snapshot=page.duplicate(true);phase=Phase.Ready;changed.emit()
	else:_read(cursor,page.revision)
	if owner==generation:applied.emit()
