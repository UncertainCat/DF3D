extends RefCounted
# Owns the guard roster; DF supplies membership, order, labels and appearance.
signal changed
signal inspect_ready(tile: Vector3i,unit_id: int)
const C=preload("res://scripts/management_contract.gd")
const NameColor=preload("res://scripts/native_name_color.gd")
enum Phase {Closed,Reading,Ready,Navigating,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var rows: Array=[]
var caption:=""
var color:=0
var query:=""
var first:=0
var cursor_id:=-1
var priorities: Array[int]=[C.JusticeCandidateColumn.Category]
var directions: Array[bool]=[false,false,false,false]
var generation:=0
var ticket:=0
var revision:=0
var last_result: Dictionary={}
var _pending: Array=[]
var _seen: Dictionary={}
var _total:=0
var _caption:=""
var _color:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1;var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
func close() -> void:
	_retire();phase=Phase.Closed;rows=[];caption="";color=0;query="";first=0;cursor_id=-1;revision=0
	_pending=[];_seen={};_total=0;last_result={}
	priorities=[C.JusticeCandidateColumn.Category];directions=[false,false,false,false];changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();phase=Phase.Reading;search("")
func search(value: String) -> void:
	var bytes:=value.to_utf8_buffer()
	if phase in [Phase.Closed,Phase.Navigating,Phase.Unavailable] or bytes.size()>512 or bytes.has(0):return
	_retire();query=value;rows=[];caption="";first=0;cursor_id=-1;revision=0;_pending=[];_seen={};_total=0
	last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func select_sort(column: int,retain:=false,remove:=false) -> void:
	if column<0 or column>3 or phase not in [Phase.Ready,Phase.Reading,Phase.Rejected]:return
	if remove:
		while priorities.has(column):priorities.erase(column)
		if priorities.is_empty():priorities.append(C.JusticeCandidateColumn.Category)
	else:
		if retain and priorities.size()>=65536:return
		if priorities.has(column):directions[column]=not directions[column]
		if not retain:priorities.clear()
		priorities.append(column)
	search(query)
func _fail(result: Dictionary) -> void:
	_pending=[];_seen={};last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _valid(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("tab")!=3 or typeof(value.get("list_revision"))!=TYPE_INT or value.list_revision<=0 or typeof(value.get("total"))!=TYPE_INT or value.total<0 or value.total>1048576:return false
	if value.get("offset")!=intent.offset or typeof(value.get("guard"))!=TYPE_DICTIONARY:return false
	var page: Dictionary=value.guard
	if typeof(page.get("caption"))!=TYPE_STRING or page.caption.to_utf8_buffer().size()>16384 or typeof(page.get("color"))!=TYPE_INT or page.color<0 or page.color>15 or typeof(page.get("rows"))!=TYPE_ARRAY:return false
	if page.rows.size()>intent.limit or intent.offset+page.rows.size()>value.total or (intent.offset<value.total and page.rows.is_empty()):return false
	if revision!=0 and (value.list_revision!=revision or value.total!=_total or page.caption!=_caption or page.color!=_color):return false
	for row in page.rows:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("unit_id"))!=TYPE_INT or row.unit_id<0 or row.unit_id>2147483647 or _seen.has(row.unit_id):return false
		if typeof(row.get("rank"))!=TYPE_INT or row.rank< -2147483648 or row.rank>2147483647:return false
		for key in ["first_line","second_line"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
		if typeof(row.get("name_color"))!=TYPE_DICTIONARY or NameColor.choose(row.name_color,0,0).is_empty():return false
		if row.has("position") and typeof(row.position)!=TYPE_VECTOR3I:return false
		_seen[row.unit_id]=true
	return true
func _page() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var sorts: Array=[]
	for column in priorities:sorts.append({"column":column,"reverse":directions[column]})
	var intent:={"action":C.ManagementAction.JusticeGuardRead,"tab":3,"offset":_pending.size(),"limit":32,"expected_list_revision":revision,"query":query,"sorts":sorts}
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or not _valid(value,intent):_fail(result);return
		revision=value.list_revision;_total=value.total;_caption=value.guard.caption;_color=value.guard.color;_pending.append_array(value.guard.rows.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};caption=_caption;color=_color;cursor_id=rows[0].unit_id if not rows.is_empty() else -1;phase=Phase.Ready;changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func inspect(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or service==null or not rows.any(func(row):return row.unit_id==id):return
	var owner:=generation;phase=Phase.Navigating
	ticket=service.submit("creature_sheet_location",{"action":C.ManagementAction.CreatureSheetLocate,"unit_id":id},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;phase=Phase.Ready;changed.emit()
		var value: Dictionary=result.get("creature_position",{})
		if result.get("outcome","")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=C.ManagementAction.CreatureSheetLocate:return
		if value.get("unit_id")!=id or typeof(value.get("position"))!=TYPE_VECTOR3I:return
		inspect_ready.emit(value.position,id))
	if ticket==0:phase=Phase.Ready
	changed.emit()
