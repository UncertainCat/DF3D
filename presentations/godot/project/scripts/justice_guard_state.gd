extends RefCounted
# Owns the guard roster; DF supplies membership, order, labels and appearance.
signal changed
signal inspect_ready(tile: Vector3i,unit_id: int)
const C=preload("res://scripts/management_contract.gd")
const NameColor=preload("res://scripts/native_name_color.gd")
enum Phase {Closed,Reading,Ready,Navigating,Rejected,Unavailable,DetailReading}
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
var _resume_cursor:=0
var _resume_first:=0
func _tab() -> int:return 3
func _roster_action() -> int:return C.ManagementAction.JusticeGuardRead
func _roster_key() -> String:return "guard"
func _max_sort() -> int:return 3
func _has_caption() -> bool:return true
func _loaded() -> void:pass
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
	_resume_cursor=0;_resume_first=0
	priorities=[C.JusticeCandidateColumn.Category];directions=[false,false,false,false];changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func draft() -> Dictionary:
	return {"query":query,"priorities":priorities.duplicate(),"directions":directions.duplicate(),"cursor":maxi(0,rows.find_custom(func(row):return row.unit_id==cursor_id)) if not rows.is_empty() else _resume_cursor,"first":first if not rows.is_empty() else _resume_first}
func open(retained: Dictionary={}) -> void:
	close();query=retained.get("query","")
	priorities.assign(retained.get("priorities",[C.JusticeCandidateColumn.Category]));directions.assign(retained.get("directions",[false,false,false,false]))
	_resume_cursor=retained.get("cursor",0);_resume_first=retained.get("first",0)
	phase=Phase.Reading;_page()
func search(value: String) -> void:
	var bytes:=value.to_utf8_buffer()
	if phase in [Phase.Closed,Phase.Navigating,Phase.Unavailable] or bytes.size()>512 or bytes.has(0):return
	_retire();query=value;rows=[];caption="";first=0;cursor_id=-1;revision=0;_pending=[];_seen={};_total=0
	_resume_cursor=0;_resume_first=0
	last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading]:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func select_unit(id: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading] or cursor_id==id or not rows.any(func(row):return row.unit_id==id):return
	cursor_id=id;changed.emit()
func move_cursor(step: int,capacity: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading] or rows.is_empty():return
	# Native142cc00 keeps the cursor in view; Convicts activates its detail
	# callback on selection, supplied by the select_unit override.
	var previous_cursor:=cursor_id;var previous_first:=first
	var index:=rows.find_custom(func(row):return row.unit_id==cursor_id)
	index=clampi(maxi(0,index)+step,0,rows.size()-1)
	if capacity<=0:first=0
	elif index<first:first=index
	elif index>=first+capacity:first=index-capacity+1
	select_unit(rows[index].unit_id)
	if cursor_id==previous_cursor and first!=previous_first:changed.emit()
func select_sort(column: int,retain:=false,remove:=false) -> void:
	if column<0 or column>_max_sort() or phase not in [Phase.Ready,Phase.Reading,Phase.Rejected,Phase.DetailReading]:return
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
	if value.get("tab")!=_tab() or typeof(value.get("list_revision"))!=TYPE_INT or value.list_revision<=0 or typeof(value.get("total"))!=TYPE_INT or value.total<0 or value.total>1048576:return false
	if value.get("offset")!=intent.offset or typeof(value.get(_roster_key()))!=TYPE_DICTIONARY:return false
	var page: Dictionary=value[_roster_key()]
	if typeof(page.get("rows"))!=TYPE_ARRAY:return false
	if _has_caption() and (typeof(page.get("caption"))!=TYPE_STRING or page.caption.to_utf8_buffer().size()>16384 or typeof(page.get("color"))!=TYPE_INT or page.color<0 or page.color>15):return false
	if page.rows.size()>intent.limit or intent.offset+page.rows.size()>value.total or (intent.offset<value.total and page.rows.is_empty()):return false
	if revision!=0 and (value.list_revision!=revision or value.total!=_total or (_has_caption() and (page.caption!=_caption or page.color!=_color))):return false
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
	var intent:={"action":_roster_action(),"tab":_tab(),"offset":_pending.size(),"limit":32,"expected_list_revision":revision,"query":query,"sorts":sorts}
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or not _valid(value,intent):_fail(result);return
		revision=value.list_revision;_total=value.total;_caption=value[_roster_key()].get("caption","");_color=value[_roster_key()].get("color",0);_pending.append_array(value[_roster_key()].rows.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};caption=_caption;color=_color
		cursor_id=rows[clampi(_resume_cursor,0,rows.size()-1)].unit_id if not rows.is_empty() else -1
		first=clampi(_resume_first,0,maxi(0,rows.size()-1));phase=Phase.Ready;_loaded();changed.emit())
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
