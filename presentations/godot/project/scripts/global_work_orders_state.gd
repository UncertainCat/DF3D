extends RefCounted
# Own the global list independently of workshop selection and native menu state.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var generation:=0
var ticket:=0
var revision:=0
var total:=0
var first:=0
var capacity:=15
var rows: Dictionary={}
var pending: Dictionary={}
var editing_id: int=-1
var editing_field:=""

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
	revision=0;total=0;first=0;rows={};pending={};editing_id=-1;editing_field="";phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();refresh()
func refresh() -> void:
	# A refresh retires requests, not the visible panel or its scroll position.
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	revision=0;rows={};pending={};editing_id=-1;editing_field=""
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading;_read(0);changed.emit()
func seek(offset: int,count: int) -> void:
	capacity=maxi(0,count);first=clampi(offset,0,maxi(0,total-capacity))
	_fill();changed.emit()
func _fill() -> void:
	if phase not in [Phase.Reading,Phase.Ready] or ticket!=0 or revision==0:return
	# Adjacent identities are needed by priority arrows at viewport boundaries.
	for index in range(maxi(0,first-1),mini(total,first+capacity+1)):
		if not rows.has(index):_read(index);return
	phase=Phase.Ready
func _reject() -> void:
	rows={};revision=0;total=0;phase=Phase.Rejected;changed.emit()
func find_order(id: int) -> Dictionary:
	for row in rows.values():
		if row.id==id:return row
	return {}
func set_quantity(id: int,value: int) -> void:
	if value>=0 and value<=9999:_edit(id,"remaining",value)
func remove_order(id: int) -> void:
	if phase!=Phase.Ready or service==null:return
	var row:=find_order(id)
	if row.is_empty():return
	generation+=1
	if ticket!=0:service.detach(ticket);ticket=0
	var owner:=generation
	phase=Phase.Applying
	ticket=service.submit("work_orders",{"action":C.ManagementAction.WorkOrderDelete,"workshop_id":-2,"id":id,"expected_revision":row.revision},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderDelete or result.get("work_order",{}).get("list_revision",0)<=0:
			phase=Phase.Unknown;changed.emit();return
		refresh())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func set_limit(id: int,value: int) -> void:
	if value>=0 and value<=999:_edit(id,"max_workshops",value)
func move_order(id: int,direction: int) -> void:
	if direction in [-1,1]:_edit(id,"move",direction)
func _edit(id: int,field: String,value: int) -> void:
	if phase==Phase.Applying:
		if id==editing_id and field==editing_field and field!="move":pending={"value":value}
		return
	if phase!=Phase.Ready or service==null:return
	var row:=find_order(id)
	if row.is_empty():return
	var request: Dictionary={"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":-2,"id":id,"expected_revision":row.revision,field:value}
	if field=="move":
		var neighbor: Dictionary=rows.get(row.position+value,{})
		if neighbor.is_empty():return
		request.expected_neighbor=neighbor.id;request.expected_list_revision=revision
	# Retire reads before sending a write; no late page may replace its receipt.
	generation+=1
	if ticket!=0:service.detach(ticket);ticket=0
	var owner:=generation
	phase=Phase.Applying;editing_id=id;editing_field=field;pending={}
	ticket=service.submit("work_orders",request,func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var page: Array=result.get("work_order",{}).get("orders",[])
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderUpdate or page.size()!=1 or page[0].get("id",-1)!=id or page[0].get("revision",0)<=0:
			pending={};phase=Phase.Unknown;changed.emit();return
		var after: Dictionary=page[0]
		if (field=="remaining" and (after.remaining!=sent.remaining or after.total!=sent.remaining)) or (field=="max_workshops" and after.max_workshops!=sent.max_workshops) or (field=="move" and after.position!=row.position+sent.move):
			pending={};phase=Phase.Unknown;changed.emit();return
		var queued:=pending.duplicate();pending={};editing_id=-1;editing_field=""
		if field=="move":refresh();return
		rows[after.position]=after.duplicate(true);phase=Phase.Ready;changed.emit()
		if queued.has("value"):_edit(id,field,queued.value)
		else:_fill())
	if ticket==0:phase=Phase.Unavailable;pending={}
	changed.emit()
func _read(offset: int) -> void:
	var owner:=generation
	ticket=service.submit("work_orders",{"action":C.ManagementAction.WorkOrderList,"workshop_id":-2,"cursor":offset,"expected_list_revision":revision},func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("work_order",{})
		var page: Array=value.get("orders",[])
		var observed: int=value.get("list_revision",0)
		var count: int=value.get("total",-1)
		var start: int=sent.cursor
		var next: int=value.get("next_cursor",0)
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderList or observed<=0 or (revision!=0 and revision!=observed) or count<0 or count>16384 or page.size()>16 or start+page.size()>count or (page.is_empty() and start<count) or next!=(start+page.size() if start+page.size()<count else 0):
			_reject();return
		var identities: Dictionary={}
		for index in page.size():
			var row: Dictionary=page[index]
			var id: int=row.get("id",-1)
			if id<0 or identities.has(id) or row.get("position",-1)!=start+index or row.get("revision",0)<=0 or row.get("native_state",{}).get("phase",0) not in [C.WorkOrderPhase.Active,C.WorkOrderPhase.Waiting,C.WorkOrderPhase.Checking,C.WorkOrderPhase.Ready]:
				_reject();return
			identities[id]=true
		revision=observed;total=count;first=clampi(first,0,maxi(0,total-capacity))
		for index in page.size():rows[start+index]=page[index].duplicate(true)
		_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
