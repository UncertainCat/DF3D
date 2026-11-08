extends RefCounted
# Staged Work Details owner. DF supplies definitions and complete worker order;
# this object owns navigation and request retirement, never worker eligibility.
signal changed
const C=preload("res://scripts/management_contract.gd")
const A=C.ManagementAction
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unavailable, Unknown }
var service
var phase:=Phase.Closed
var generation:=0
var ticket:=0
var details: Array=[]
var list_revision:=0
var selected: Dictionary={}
var ids:=PackedInt32Array()
var rows: Dictionary={}
var roster_ready:=false
var editing_settings:=false
var settings: Dictionary={}
var settings_first:=0
var columns:=30
var show_gender:=false
var sort:=C.WorkDetailWorkerSort.Skills
var directions: Array[bool]=[false,false,false,false]
var query:=PackedByteArray()
var first:=0
var capacity:=10
var external_controller:=false
var last_result: Dictionary={}
var _collecting: Array=[]

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
	editing_settings=false;settings={};settings_first=0
	_retire();details=[];_collecting=[];list_revision=0;selected={};ids=PackedInt32Array();rows={};roster_ready=false;first=0
	last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();sort=C.WorkDetailWorkerSort.Skills;directions=[false,false,false,false];query=PackedByteArray()
	_reload(0)
func refresh() -> void:
	if phase in [Phase.Closed,Phase.Applying]:return
	_reload(int(selected.get("index",0)))
func _reject(result: Dictionary={}) -> void:
	settings={}
	selected={};ids=PackedInt32Array();rows={};roster_ready=false;last_result=result.duplicate(true)
	phase=Phase.Unknown if result.get("outcome","")=="unknown" else Phase.Rejected
	changed.emit()
func _submit(domain: String,intent: Dictionary,accept: Callable) -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit(domain,intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action:
			_reject(result);return
		accept.call(result))
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func _reload(preferred: int) -> void:
	settings={}
	_retire();details=[];_collecting=[];list_revision=0;selected={};ids=PackedInt32Array();rows={};roster_ready=false;phase=Phase.Reading
	_read_list(0,preferred)
func _read_list(cursor: int,preferred: int) -> void:
	_submit("citizens",{"action":A.WorkDetailList,"cursor":cursor,"expected_list_revision":list_revision},func(result):
		var page: Dictionary=result.get("citizen",{})
		var revision:=int(page.get("detail_list_revision",0))
		if revision<=0 or (cursor>0 and revision!=list_revision):_reject();return
		list_revision=revision;external_controller=bool(page.get("external_controller",false))
		for row: Dictionary in page.get("details",[]):
			if int(row.get("index",-1))!=_collecting.size() or int(row.get("revision",0))<=0:_reject();return
			_collecting.append(row.duplicate(true))
		var next:=int(page.get("next_cursor",0))
		if _collecting.size()>128 or (next!=0 and (next<=cursor or next!=_collecting.size())):_reject();return
		if next!=0:_read_list(next,preferred);return
		details=_collecting;_collecting=[]
		if details.is_empty():editing_settings=false;phase=Phase.Ready;changed.emit();return
		_select(clampi(preferred,0,details.size()-1)))
func select_detail(index: int) -> void:
	if phase==Phase.Applying or phase==Phase.Closed or index<0 or index>=details.size():return
	if int(selected.get("index",-1))==index:return
	editing_settings=false;settings={};settings_first=0
	_select(index)
func _select(index: int) -> void:
	_retire();selected=details[index].duplicate(true);first=0;ids=PackedInt32Array();phase=Phase.Reading
	if editing_settings:_read_settings()
	else:_read_workers()
func select_sort(value: int) -> void:
	if editing_settings or selected.is_empty() or phase in [Phase.Closed,Phase.Applying] or value<0 or value>=4:return
	if sort==value:directions[value]=not directions[value]
	sort=value;first=0;_read_workers()
func set_query(value: PackedByteArray) -> void:
	if editing_settings or selected.is_empty() or phase in [Phase.Closed,Phase.Applying] or value==query or value.size()>128 or value.has(0):return
	query=value.duplicate();first=0;_read_workers()
func seek(offset: int,count: int) -> void:
	capacity=clampi(count,0,64);first=clampi(offset,0,maxi(0,ids.size()-capacity));_fill();changed.emit()
func _read_workers() -> void:
	_retire();ids=PackedInt32Array();rows={};roster_ready=false;phase=Phase.Reading
	_submit("work_detail_workers",{"action":A.WorkDetailWorkersQuery,"detail_index":int(selected.index),"expected_revision":int(selected.revision),"sort":sort,"descending":directions[sort],"query_bytes":query},func(result):
		if not result.has("residents"):_reject();return
		ids=result.residents.unit_ids.duplicate();roster_ready=true;first=clampi(first,0,maxi(0,ids.size()-capacity));_fill();changed.emit())
func row_at(index: int) -> Dictionary:
	return rows.get(ids[index],{}) if index>=0 and index<ids.size() else {}
func _fill() -> void:
	if editing_settings or phase not in [Phase.Reading,Phase.Ready] or not roster_ready or ticket!=0:return
	var wanted:=PackedInt32Array()
	for index in range(first,mini(ids.size(),first+capacity)):
		if not rows.has(ids[index]):wanted.append(ids[index])
	if wanted.is_empty():phase=Phase.Ready;return
	phase=Phase.Reading
	_submit("work_detail_rows",{"action":A.WorkDetailRowsRead,"detail_index":int(selected.index),"expected_revision":int(selected.revision),"unit_ids":wanted,"columns":columns,"show_gender":show_gender},func(result):
		var page: Array=result.get("residents_rows",{}).get("rows",[])
		if page.size()!=wanted.size():_reject();return
		for index in page.size():
			if int(page[index].get("id",-1))!=wanted[index] or not page[index].has("skills") or not page[index].has("member"):_reject();return
		var retained: Dictionary={}
		for index in range(first,mini(ids.size(),first+capacity)):
			if rows.has(ids[index]):retained[ids[index]]=rows[ids[index]]
		for row: Dictionary in page:retained[int(row.id)]=row.duplicate(true)
		rows=retained;_fill();changed.emit())
func can_edit() -> bool:
	return not editing_settings and phase==Phase.Ready and ticket==0 and not external_controller and not selected.is_empty() and bool(selected.get("editable",false)) and str(selected.get("row_error","")).is_empty()
func create_detail() -> void:
	if phase!=Phase.Ready or ticket!=0 or external_controller or list_revision<=0 or details.size()>=128:return
	editing_settings=false;settings={};settings_first=0
	_apply({"action":A.WorkDetailCreate,"expected_revision":list_revision})
func set_mode(value: int) -> void:
	if not can_edit() or not selected.get("mode_editable",false) or value<1 or value>3 or value==int(selected.mode):return
	if value==1 and selected.get("cannot_be_everybody",false):return
	_apply({"action":A.WorkDetailMode,"detail_index":int(selected.index),"expected_revision":int(selected.revision),"mode":value})
func set_member(id: int,value: bool) -> void:
	if not can_edit() or not ids.has(id):return
	if selected.get("assigned_units",[]).has(id)==value:return
	_apply({"action":A.WorkDetailMembership,"detail_index":int(selected.index),"expected_revision":int(selected.revision),"unit_id":id,"member":int(value)})
func specialize(id: int) -> void:
	if not can_edit() or not rows.has(id):return
	var receipt: Dictionary=rows[id].get("specialization",{})
	if receipt.is_empty() or int(receipt.get("revision",0))<=0:return
	var index:=int(selected.index);var desired: bool=not receipt.only_assigned
	_retire();phase=Phase.Applying
	_submit("residents_specialization",{"action":A.ResidentsSpecialize,"unit_id":id,"expected_revision":receipt.revision,"only_assigned":desired},func(result):
		var value: Dictionary=result.get("residents_specialization",{})
		if value.get("unit_id",-1)!=id or value.get("outcome",-1)!=C.ResidentsSpecializationOutcome.Applied or value.get("only_assigned")!=desired:_reject(result);return
		_reload(index))
func _apply(intent: Dictionary) -> void:
	_retire();phase=Phase.Applying;last_result={}
	_submit("citizens",intent,func(result):
		var value: Dictionary=result.get("citizen",{})
		var index:=int(value.get("selected_detail",-1))
		if index<0 or index>=128:_reject(result);return
		# A change can alter other definitions' receipts, assignment modes and
		# native ordering. Read the authoritative list; never replay the mutation.
		_reload(index))

func open_settings() -> void:
	if phase!=Phase.Ready or ticket!=0 or selected.is_empty():return
	editing_settings=true;settings_first=0;_read_settings()
func close_settings() -> void:
	if not editing_settings or phase==Phase.Applying:return
	editing_settings=false;settings={};settings_first=0
	_reload(int(selected.get("index",0)))
func _accept_settings(result: Dictionary,index: int,revision: int,mutated: bool=false) -> bool:
	var value: Dictionary=result.get("work_detail_settings",{})
	if int(value.get("detail_index",-1))!=index or int(value.get("revision",0))<=0 or value.get("catalog",[]).size()!=91:
		_reject(result);return false
	if (not mutated and int(value.revision)!=revision) or (mutated and int(value.revision)==revision):
		_reject(result);return false
	settings=value.duplicate(true);return true
func _read_settings() -> void:
	_retire();settings={};ids=PackedInt32Array();rows={};roster_ready=false;phase=Phase.Reading
	var index:=int(selected.index);var revision:=int(selected.revision)
	_submit("work_detail_settings",{"action":A.WorkDetailSettingsRead,"detail_index":index,"expected_revision":revision},func(result):
		if not _accept_settings(result,index,revision):return
		phase=Phase.Ready;changed.emit())
func toggle_setting(id: int) -> void:
	if not editing_settings or phase!=Phase.Ready or ticket!=0 or not settings.get("editable",false):return
	var present:=false
	for entry: Dictionary in settings.get("catalog",[]):
		if int(entry.id)==id:present=true;break
	if not present:return
	var index:=int(settings.detail_index);var revision:=int(settings.revision)
	_retire();phase=Phase.Applying;last_result={}
	_submit("work_detail_settings",{"action":A.WorkDetailSettingsToggle,"detail_index":index,"expected_revision":revision,"setting_id":id},func(result):
		if not _accept_settings(result,index,revision,true):return
		# Definition changes affect every header receipt and the settings row's
		# detail icons. Refresh those observations; no worker recalc is requested.
		_reload(index))
func seek_settings(offset: int,count: int) -> void:
	settings_first=clampi(offset,0,maxi(0,settings.get("catalog",[]).size()-maxi(0,count)));changed.emit()

func reset_settings() -> void:
	if not editing_settings or phase!=Phase.Ready or ticket!=0 or not settings.get("editable",false) or not settings.get("no_modify",false):return
	_apply({"action":A.WorkDetailEdit,"detail_index":int(settings.detail_index),"expected_revision":int(settings.revision),"edit":3})

func delete_detail() -> void:
	if not editing_settings or phase!=Phase.Ready or ticket!=0 or not settings.get("editable",false) or settings.get("no_modify",true):return
	var intent: Dictionary={"action":A.WorkDetailDelete,"detail_index":int(settings.detail_index),"expected_revision":int(settings.revision)}
	editing_settings=false;settings={};settings_first=0
	_apply(intent)
