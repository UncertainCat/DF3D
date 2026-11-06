extends RefCounted
# Native roster ordering and row content; no local eligibility, search or sorting.
signal changed
signal inspect_ready(tile: Vector3i,unit_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Rejected, Unavailable, Applying, Navigating }
var service
var phase:=Phase.Closed
var generation:=0
var ticket:=0
var sort:=C.ResidentsSort.Category
var directions: Array[bool]=[false,false,false,false,false]
var query:=PackedByteArray()
var ids:=PackedInt32Array()
var rows: Dictionary={}
var first:=0
var capacity:=13
var columns:=30
var show_gender:=false
var roster_ready:=false

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
	retire();ids=PackedInt32Array();rows={};first=0;roster_ready=false;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();sort=C.ResidentsSort.Category;directions=[false,false,false,false,false];query=PackedByteArray();refresh()
func select_sort(value: int) -> void:
	if value<0 or value>=directions.size() or phase in [Phase.Closed,Phase.Applying]:return
	if phase==Phase.Navigating:return
	if sort==value:directions[value]=not directions[value]
	sort=value;first=0;refresh()
func set_query(value: PackedByteArray) -> void:
	if value.size()>128 or value.has(0) or value==query or phase in [Phase.Closed,Phase.Applying]:return
	if phase==Phase.Navigating:return
	query=value.duplicate();first=0;refresh()
func refresh() -> void:
	if phase in [Phase.Applying,Phase.Navigating]:return
	retire();rows={};ids=PackedInt32Array();roster_ready=false
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("residents",{"action":C.ManagementAction.ResidentsQuery,"sort":sort,"descending":directions[sort],"query_bytes":query},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.ResidentsQuery or not result.has("residents"):
			_reject();return
		ids=result.residents.unit_ids.duplicate();roster_ready=true
		first=clampi(first,0,maxi(0,ids.size()-capacity));_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func inspect(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or service==null or not rows.has(id):return
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
	ticket=service.submit("residents_rows",{"action":C.ManagementAction.ResidentsRowsRead,"unit_ids":wanted,"columns":columns,"show_gender":show_gender},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var page: Array=result.get("residents_rows",{}).get("rows",[])
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.ResidentsRowsRead or page.size()!=wanted.size():
			_reject();return
		for index in page.size():
			if int(page[index].get("id",-1))!=wanted[index]:_reject();return
		# Keep only the active viewport and this receipt, rather than retaining
		# an unbounded history of native text while scrolling a large fortress.
		var kept: Dictionary={}
		for index in range(first,mini(ids.size(),first+capacity)):
			if rows.has(ids[index]):kept[ids[index]]=rows[ids[index]]
		for row: Dictionary in page:kept[int(row.id)]=row.duplicate(true)
		rows=kept;_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
