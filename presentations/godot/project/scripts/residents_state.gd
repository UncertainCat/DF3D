extends RefCounted
# Native roster ordering and row content; no local eligibility, search or sorting.
signal changed
signal inspect_ready(tile: Vector3i,unit_id: int)
signal item_inspect_ready(item_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Rejected, Unavailable, Applying, Navigating, ActivityReading, ActivityReady, ActivityRejected }
var service
var phase:=Phase.Closed
var generation:=0
var ticket:=0
var sort:=C.ResidentsSort.Category
var tab:=0
var directions: Array[bool]=[false,false,false,false,false]
var query:=PackedByteArray()
var ids:=PackedInt32Array()
var rows: Dictionary={}
var first:=0
var cursor:=0
var capacity:=13
var columns:=30
var show_gender:=false
var roster_ready:=false
var activity_selection: Dictionary={}
var activity_page: Dictionary={}
var activity_columns:=0
var activity_first:=0
var activity_capacity:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	activity_selection={};activity_page={};activity_columns=0;activity_first=0
	retire();ids=PackedInt32Array();rows={};first=0;cursor=0;roster_ready=false;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();tab=0;sort=C.ResidentsSort.Category;directions=[false,false,false,false,false];query=PackedByteArray();refresh()
func select_tab(value: int) -> void:
	if value<0 or value>3 or value==tab or phase in [Phase.Closed,Phase.Applying,Phase.Navigating]:return
	retire();activity_selection={};activity_page={};activity_first=0
	tab=value;sort=C.ResidentsSort.Category;directions=[false,false,false,false,false,false]
	query=PackedByteArray();first=0;cursor=0;phase=Phase.Reading;refresh()
# Native IDs are nonnegative int32. Negative local keys encode item identities
# without collisions, including unit/item rows with the same native ID.
static func row_key(row: Dictionary) -> int:
	return int(row.id) if int(row.get("kind",0))==0 else -int(row.id)-1
func identity(key: int) -> Dictionary:
	return {"kind":0,"id":key} if key>=0 else {"kind":1,"id":-key-1}
func select_sort(value: int) -> void:
	if activity_open():return
	if value<0 or value>=directions.size() or phase in [Phase.Closed,Phase.Applying]:return
	if (tab==0 and value==5) or (tab!=0 and value==3) or (tab!=1 and value==5):return
	if phase==Phase.Navigating:return
	if sort==value:directions[value]=not directions[value]
	sort=value;first=0;refresh()
func set_query(value: PackedByteArray) -> void:
	if activity_open():return
	if value.size()>128 or value.has(0) or value==query or phase in [Phase.Closed,Phase.Applying]:return
	if phase==Phase.Navigating:return
	query=value.duplicate();first=0;refresh()
func refresh() -> void:
	if activity_open():return
	if phase in [Phase.Applying,Phase.Navigating]:return
	retire();rows={};ids=PackedInt32Array();roster_ready=false
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading
	var owner:=generation
	var action: int=C.ManagementAction.ResidentsQuery if tab==0 else C.ManagementAction.CreatureListQuery
	var domain: String="residents" if tab==0 else "creature_list"
	var intent: Dictionary={"action":action,"sort":sort,"descending":directions[sort],"query_bytes":query}
	if tab!=0:intent.tab=tab
	ticket=service.submit(domain,intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=action or not result.has(domain):
			_reject();return
		if tab==0:ids=result.residents.unit_ids.duplicate()
		else:
			if result.creature_list.get("tab",-1)!=tab:_reject();return
			for entry: Dictionary in result.creature_list.entries:ids.append(row_key(entry))
		cursor=clampi(cursor,0,maxi(0,ids.size()-1))
		roster_ready=true
		first=clampi(first,0,maxi(0,ids.size()-capacity));_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func activity_open() -> bool:return not activity_selection.is_empty()
func show_activity(id: int,width: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or service==null or width<1 or width>1024:return
	var target: Dictionary=rows.get(id,{}).get("activity_target",{})
	if target.is_empty():return
	activity_selection={"unit_id":id,"activity_id":int(target.activity_id),"event_id":int(target.event_id)}
	activity_first=0;_read_activity(width)
func resize_activity(width: int) -> void:
	if activity_open() and width!=activity_columns and width>=1 and width<=1024:_read_activity(width)
func _read_activity(width: int) -> void:
	retire();activity_columns=width;activity_page={};phase=Phase.ActivityReading
	var intent:=activity_selection.duplicate();intent.action=C.ManagementAction.ResidentsActivityRead;intent.columns=width
	var owner:=generation
	ticket=service.submit("residents_activity",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;activity_page={};phase=Phase.ActivityRejected
		var page: Dictionary=result.get("residents_activity",{})
		if result.get("status",-1)==C.ManagementStatus.Ok and result.get("action",-1)==C.ManagementAction.ResidentsActivityRead and page.get("unit_id")==intent.unit_id and page.get("activity_id")==intent.activity_id and page.get("event_id")==intent.event_id and page.get("columns")==width:
			activity_page=page.duplicate(true);phase=Phase.ActivityReady
			activity_first=clampi(activity_first,0,maxi(0,int(page.max_y)+1-activity_capacity))
		changed.emit())
	if ticket==0:phase=Phase.ActivityRejected
	changed.emit()
func scroll_activity(offset: int,count: int) -> void:
	activity_capacity=maxi(0,count)
	activity_first=clampi(offset,0,maxi(0,int(activity_page.get("max_y",-1))+1-activity_capacity));changed.emit()
func close_activity() -> void:
	if not activity_open():return
	retire();activity_selection={};activity_page={};activity_first=0;activity_columns=0;phase=Phase.Ready
	_fill();changed.emit()
func inspect(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or service==null or not rows.has(id):return
	if not rows[id].get("can_inspect",true):return
	if id<0:
		item_inspect_ready.emit(-id-1);return
	var owner:=generation;phase=Phase.Navigating
	ticket=service.submit("creature_sheet_location",{"action":C.ManagementAction.CreatureSheetLocate,"unit_id":id},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;phase=Phase.Ready;changed.emit()
		var value: Dictionary=result.get("creature_position",{})
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.CreatureSheetLocate:return
		if value.get("unit_id",-1)!=id or typeof(value.get("position"))!=TYPE_VECTOR3I:return
		inspect_ready.emit(value.position,id))
	if ticket==0:phase=Phase.Ready
	changed.emit()
func specialize(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or service==null:return
	var receipt: Dictionary=rows.get(id,{}).get("specialization",{})
	if receipt.is_empty() or int(receipt.get("revision",0))<=0:return
	var desired: bool=not receipt.only_assigned
	var owner:=generation
	phase=Phase.Applying
	ticket=service.submit("residents_specialization",{"action":C.ManagementAction.ResidentsSpecialize,"unit_id":id,"expected_revision":receipt.revision,"only_assigned":desired},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("residents_specialization",{})
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.ResidentsSpecialize or value.get("unit_id",-1)!=id or value.get("outcome",-1)!=C.ResidentsSpecializationOutcome.Applied or value.get("only_assigned")!=desired:
			_reject();return
		phase=Phase.Ready;refresh())
	if ticket==0:_reject()
	else:changed.emit()
func pet_action(key: int,action: int) -> void:
	if tab!=1 or phase!=Phase.Ready or ticket!=0 or service==null or action==C.PetAction.Trainer:return
	var pet: Dictionary=rows.get(key,{}).get("pet",{})
	var choices: Array=pet.get("controls",[]).filter(func(control):return int(control.action)==action)
	if choices.size()!=1 or int(pet.get("revision",0))<=0:return
	var target:=identity(key);var desired: bool=not choices[0].value;var owner:=generation
	phase=Phase.Applying
	ticket=service.submit("pet_action",{"action":C.ManagementAction.PetActionApply,"target":target,"expected_revision":pet.revision,"pet_action":action,"desired":desired},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("pet_edit",{})
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.PetActionApply or value.get("target",{})!=target or value.get("outcome",-1)!=C.PetOutcome.Applied:
			_reject();return
		phase=Phase.Ready;refresh())
	if ticket==0:_reject()
	else:changed.emit()
func move_cursor(step: int) -> void:
	if tab==0 or phase!=Phase.Ready or ids.is_empty() or capacity<=0:return
	cursor=clampi(cursor+step,0,ids.size()-1)
	var offset:=first
	if cursor<first:offset=cursor
	elif cursor>=first+capacity:offset=cursor-capacity+1
	seek(offset,capacity)
func seek(offset: int,count: int) -> void:
	capacity=clampi(count,0,64);first=clampi(offset,0,maxi(0,ids.size()-capacity))
	_fill();changed.emit()
func row_at(index: int) -> Dictionary:
	return rows.get(ids[index],{}) if index>=0 and index<ids.size() else {}
func _reject() -> void:
	rows={};ids=PackedInt32Array();roster_ready=false;first=0;phase=Phase.Rejected;changed.emit()
func _fill() -> void:
	if phase not in [Phase.Reading,Phase.Ready] or not roster_ready or ticket!=0:return
	var wanted:=PackedInt32Array()
	for index in range(first,mini(ids.size(),first+capacity)):
		if not rows.has(ids[index]):wanted.append(ids[index])
	if wanted.is_empty():phase=Phase.Ready;return
	phase=Phase.Reading
	var owner:=generation
	var action: int=C.ManagementAction.ResidentsRowsRead if tab==0 else C.ManagementAction.CreatureListRowsRead
	var domain: String="residents_rows" if tab==0 else "creature_list_rows"
	var intent: Dictionary={"action":action,"columns":columns}
	if tab==0:intent.unit_ids=wanted;intent.show_gender=show_gender
	else:
		intent.tab=tab;intent.targets=[]
		for key in wanted:intent.targets.append(identity(key))
	ticket=service.submit(domain,intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var page: Array=result.get(domain,{}).get("rows",[])
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=action or page.size()!=wanted.size() or (tab!=0 and result.get(domain,{}).get("tab",-1)!=tab):
			_reject();return
		for index in page.size():
			if not page[index].has("id") or row_key(page[index])!=wanted[index]:_reject();return
		# Keep only the active viewport and this receipt, rather than retaining
		# an unbounded history of native text while scrolling a large fortress.
		var kept: Dictionary={}
		for index in range(first,mini(ids.size(),first+capacity)):
			if rows.has(ids[index]):kept[ids[index]]=rows[ids[index]]
		for row: Dictionary in page:
			var value:=row.duplicate(true)
			if tab!=0:
				if value.has("portrait"):value.sheet_icon=value.portrait
				value.activity={"caption":row.activity.text,"fg":row.activity.foreground,"bg":row.activity.background,"bright":row.activity.bright}
			kept[row_key(row)]=value
		rows=kept;_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
