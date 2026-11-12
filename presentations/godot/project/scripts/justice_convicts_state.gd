extends "res://scripts/justice_guard_state.gd"
# Shared roster ownership with a separately receipted native sentence read.
var detail: Dictionary={}
var _detail_pending: Dictionary={}
var _detail_seen: Dictionary={}
func _tab() -> int:return 4
func _roster_action() -> int:return C.ManagementAction.JusticeConvictsRead
func _roster_key() -> String:return "convicts"
func _max_sort() -> int:return 2
func _has_caption() -> bool:return false
func _retire() -> void:
	detail={};_detail_pending={};_detail_seen={};super._retire()
func _loaded() -> void:
	if not rows.is_empty():select_unit(cursor_id)
func select_unit(id: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading] or not rows.any(func(row):return row.unit_id==id):return
	if cursor_id==id and (not detail.is_empty() or phase==Phase.DetailReading):return
	_retire();cursor_id=id;phase=Phase.DetailReading;last_result={};_detail_page()
func _detail_fail(result: Dictionary) -> void:
	detail={};_detail_pending={};_detail_seen={};last_result=result.duplicate(true);phase=Phase.Ready;changed.emit()
func _valid_detail(page: Dictionary,intent: Dictionary) -> bool:
	if page.get("unit_id")!=cursor_id or typeof(page.get("revision"))!=TYPE_INT or page.revision<=0 or typeof(page.get("total"))!=TYPE_INT or page.total<0 or page.total>1048576 or page.get("offset")!=intent.offset:return false
	if typeof(page.get("sentence"))!=TYPE_ARRAY or page.sentence.size()>3 or typeof(page.get("crimes"))!=TYPE_ARRAY:return false
	for line in page.sentence:
		if typeof(line)!=TYPE_STRING or line.to_utf8_buffer().size()>16384:return false
	if page.has("officer") and (typeof(page.officer)!=TYPE_STRING or page.officer.to_utf8_buffer().size()>16384):return false
	if page.crimes.size()>intent.limit or intent.offset+page.crimes.size()>page.total or (intent.offset<page.total and page.crimes.is_empty()):return false
	if not _detail_pending.is_empty():
		for key in ["revision","total","sentence","officer"]:
			if page.get(key)!=_detail_pending.get(key):return false
	for crime in page.crimes:
		if typeof(crime)!=TYPE_DICTIONARY or typeof(crime.get("crime_id"))!=TYPE_INT or crime.crime_id<0 or crime.crime_id>2147483647 or _detail_seen.has(crime.crime_id):return false
		for key in ["caption","injured_party"]:
			if key=="injured_party" and not crime.has(key):continue
			if typeof(crime.get(key))!=TYPE_STRING or crime[key].to_utf8_buffer().size()>16384:return false
		_detail_seen[crime.crime_id]=true
	return true
func _detail_page() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var sorts: Array=[]
	for column in priorities:sorts.append({"column":column,"reverse":directions[column]})
	var intent:={"action":C.ManagementAction.JusticeConvictDetailRead,"tab":4,"offset":_detail_pending.get("crimes",[]).size(),"limit":32,"expected_list_revision":revision,"query":query,"sorts":sorts,"unit_id":cursor_id,"expected_case_revision":_detail_pending.get("revision",0)}
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_detail_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or value.get("tab")!=4 or value.get("list_revision")!=revision or typeof(value.get("convict_detail"))!=TYPE_DICTIONARY:_detail_fail(result);return
		var page: Dictionary=value.convict_detail
		if not _valid_detail(page,intent):_detail_fail(result);return
		if _detail_pending.is_empty():_detail_pending=page.duplicate(true)
		else:_detail_pending.crimes.append_array(page.crimes.duplicate(true))
		if _detail_pending.crimes.size()<_detail_pending.total:_detail_page();return
		detail=_detail_pending;_detail_pending={};_detail_seen={};phase=Phase.Ready;changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
