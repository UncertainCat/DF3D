extends RefCounted
# Native order and assessments are authority; paging and scroll belong here.
signal changed
const C=preload("res://scripts/management_contract.gd")
const MAX_RETAINED_BYTES=64*1024*1024
enum Phase {Closed,Reading,Ready,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _pending: Array=[]
var _seen: Dictionary={}
var _revision:=0
var _total:=0
var _bytes:=0
var _restarts:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	rows=[];_pending=[];_seen={};_revision=0;_total=0;_bytes=0
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();_clear();first=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();phase=Phase.Rejected;refresh()
func refresh() -> void:
	if phase not in [Phase.Ready,Phase.Rejected]:return
	_retire();_clear();_restarts=0;last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,65536) or value.get("offset")!=intent.offset or typeof(value.get("rows"))!=TYPE_ARRAY:return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision and (value.list_revision!=_revision or value.total!=_total):return false
	var bytes:=0
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for key in ["entity_id","position_id","assignment_id","unit_id","nemesis_id"]:
			if not _integer(row.get(key),0 if key in ["entity_id","position_id"] else -1,2147483647):return false
		var identity:=Vector3i(row.entity_id,row.position_id,row.assignment_id)
		if _seen.has(identity):return false
		_seen[identity]=true;bytes+=192
		for key in ["title","squad_caption","holder_caption"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
			bytes+=row[key].to_utf8_buffer().size()
		if not _integer(row.get("priority"),-2147483648,2147483647) or typeof(row.get("can_appoint"))!=TYPE_BOOL or typeof(row.get("has_room_assessment"))!=TYPE_BOOL:return false
		if row.has_room_assessment!=(row.unit_id>=0):return false
		for key in ["required_rooms","actual_rooms","required_furniture","actual_furniture"]:
			if typeof(row.get(key))!=TYPE_ARRAY or row[key].size()!=4:return false
			for number in row[key]:
				if not _integer(number,-2147483648,2147483647) or (not row.has_room_assessment and number!=0):return false
		for key in ["demand_status","mandate_status"]:
			if not _integer(row.get(key),-1,3) or (not row.has_room_assessment and row[key]!=-1):return false
		if row.has("appearance"):
			if row.unit_id<0 or not preload("res://scripts/item_sheet_state.gd")._valid_recipe(row.appearance):return false
			bytes+=12+row.appearance.layers.size()*16
			for key in ["tile_pages","palettes"]:
				for name in row.appearance[key]:bytes+=4+name.to_utf8_buffer().size()
	if bytes>384*1024 or _bytes+bytes>MAX_RETAINED_BYTES:return false
	_bytes+=bytes;return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _page() -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var intent: Dictionary={"action":C.ManagementAction.NoblesRead,"offset":_pending.size(),"limit":32,"expected_list_revision":_revision}
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("nobles",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result);return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.NoblesOutcome.Stale and _restarts==0:
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.NoblesOutcome.None or not _valid_page(value,intent):_reject(result);return
		_revision=value.list_revision;_total=value.total;_pending.append_array(value.rows.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};phase=Phase.Ready;last_result={};first=mini(first,maxi(0,rows.size()-1));changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
