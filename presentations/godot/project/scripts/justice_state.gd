extends RefCounted
# Read-only staged controller. Native case membership/order/text remain authority.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,DetailReading,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var tab:=0
var rows: Array=[]
var detail: Dictionary={}
var selected_id: int=-1
var first:=0
var witness_first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _scroll: Array[int]=[0,0,0]
var _pending: Array=[]
var _pending_detail: Dictionary={}
var _seen: Dictionary={}
var _revision:=0
var _total:=0
var _restarts:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func _clear() -> void:
	rows=[];detail={};selected_id=-1;witness_first=0;_pending=[];_pending_detail={};_seen={};_revision=0;_total=0
func close() -> void:
	_retire();_clear();phase=Phase.Closed;tab=0;first=0;_scroll=[0,0,0];last_result={};changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(selected_tab:=0) -> void:
	if selected_tab<0 or selected_tab>2:return
	close();tab=selected_tab;refresh()
func select_tab(value: int) -> void:
	if phase in [Phase.Closed,Phase.Unavailable] or value<0 or value>2 or value==tab:return
	_scroll[tab]=first;_retire();_clear();tab=value;first=_scroll[tab];phase=Phase.Ready;refresh()
func refresh() -> void:
	_retire();_clear();_restarts=0;last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading]:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));_scroll[tab]=first;changed.emit()
func seek_witness(value: int,capacity: int) -> void:
	if phase!=Phase.Ready or detail.is_empty():return
	witness_first=clampi(value,0,maxi(0,detail.witnesses.size()-maxi(1,capacity)));changed.emit()
func select_case(id: int) -> void:
	if phase not in [Phase.Ready,Phase.DetailReading] or not rows.any(func(row):return row.crime_id==id):return
	if selected_id==id and (phase==Phase.DetailReading or not detail.is_empty()):return
	_retire();selected_id=id;detail={};_pending_detail={};witness_first=0;last_result={};phase=Phase.DetailReading;_case_page()
func _page() -> void:
	_submit({"action":C.ManagementAction.JusticeRead,"tab":tab,"offset":_pending.size(),"limit":32,"expected_list_revision":_revision})
func _case_page() -> void:
	_submit({"action":C.ManagementAction.JusticeCaseRead,"tab":tab,"crime_id":selected_id,"offset":_pending_detail.get("witnesses",[]).size(),"limit":32,"expected_list_revision":_revision,"expected_case_revision":_pending_detail.get("revision",0)})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _text(value: Variant) -> bool:return typeof(value)==TYPE_STRING and value.to_utf8_buffer().size()<=16384
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("tab")!=tab or not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,1048576) or value.get("offset")!=intent.offset or typeof(value.get("rows"))!=TYPE_ARRAY or value.has("detail"):return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision!=0 and (value.list_revision!=_revision or value.total!=_total):return false
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("crime_id"),0,2147483647) or _seen.has(row.crime_id) or not _text(row.get("caption")):return false
		_seen[row.crime_id]=true
	return true
func _valid_detail(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("tab")!=tab or value.get("list_revision")!=_revision or typeof(value.get("detail"))!=TYPE_DICTIONARY:return false
	var d: Dictionary=value.detail
	if d.get("crime_id")!=selected_id or not _integer(d.get("revision"),1,9223372036854775807) or not _integer(d.get("total"),0,1048576) or d.get("offset")!=intent.offset or typeof(d.get("witnesses"))!=TYPE_ARRAY:return false
	if not _integer(d.get("resolution"),C.JusticeCaseResolution.Unsolved,C.JusticeCaseResolution.UnknownConvict):return false
	if not _text(d.get("caption")) or not _text(d.get("status")) or (d.has("injured_party") and not _text(d.injured_party)):return false
	if d.witnesses.size()>intent.limit or intent.offset+d.witnesses.size()>d.total or (intent.offset<d.total and d.witnesses.is_empty()):return false
	if not _pending_detail.is_empty():
		for key in ["revision","total","caption","status","injured_party","resolution"]:
			if d.get(key)!=_pending_detail.get(key):return false
	for witness in d.witnesses:
		if typeof(witness)!=TYPE_DICTIONARY:return false
		for key in ["witness","description","date","reported"]:
			if not _text(witness.get(key)):return false
	return true
func _reject(result: Dictionary,selected: bool) -> void:
	last_result=result.duplicate(true);_pending=[];_pending_detail={};detail={}
	if selected:phase=Phase.Ready
	else:_clear();phase=Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{});var selected: bool=intent.action==C.ManagementAction.JusticeCaseRead
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result,selected);return
		if value.get("tab")!=intent.tab:_reject(result,selected);return
		if not selected and result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.JusticeOutcome.Stale and _restarts==0:
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.JusticeOutcome.None:_reject(result,selected);return
		if selected:
			if not _valid_detail(value,intent):_reject(result,true);return
			var d: Dictionary=value.detail
			if _pending_detail.is_empty():_pending_detail=d.duplicate(true)
			else:_pending_detail.witnesses.append_array(d.witnesses.duplicate(true))
			if _pending_detail.witnesses.size()<_pending_detail.total:_case_page();return
			detail=_pending_detail;_pending_detail={};phase=Phase.Ready;last_result={};changed.emit();return
		if not _valid_page(value,intent):_reject(result,false);return
		_revision=value.list_revision;_total=value.total;_pending.append_array(value.rows.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};first=mini(first,maxi(0,rows.size()-1));_scroll[tab]=first;phase=Phase.Ready;last_result={}
		if not rows.is_empty():select_case(rows[0].crime_id)
		else:changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
