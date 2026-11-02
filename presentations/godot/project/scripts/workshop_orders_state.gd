extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var pending_value: int=-1
var quantity_id: int=-1
var pending_quantity: int=-1
var row_ticket:=0
var row_generation:=0
var row_revision:=0
var rows: Dictionary={}
var row_total:=0
var row_offset:=0
var row_capacity:=1
var rows_available:=false

func _retire_rows() -> void:
	row_generation+=1
	var previous:=row_ticket;row_ticket=0
	if service!=null and previous!=0:service.detach(previous)
	rows={};row_revision=0;row_total=0;rows_available=false
func seek_rows(offset: int,capacity: int) -> void:
	row_capacity=maxi(0,capacity)
	row_offset=clampi(offset,0,maxi(0,row_total-row_capacity))
	_fill_rows();changed.emit()
func _fill_rows() -> void:
	if service==null or row_ticket!=0 or not rows_available:return
	for index in range(row_offset,mini(row_total,row_offset+row_capacity)):
		if not rows.has(index):_read_rows(index);return
func _read_rows(offset: int) -> void:
	if service==null:return
	var owner:=row_generation
	row_ticket=service.submit("work_orders",{"action":C.ManagementAction.WorkOrderList,"workshop_id":building_id,"cursor":offset,"expected_list_revision":row_revision},func(received,result,sent):
		if owner!=row_generation or received!=row_ticket:return
		row_ticket=0
		var value: Dictionary=result.get("work_order",{})
		var page: Array=value.get("orders",[])
		var revision: int=value.get("list_revision",0)
		var total: int=value.get("total",-1)
		var start: int=sent.cursor
		var next: int=value.get("next_cursor",0)
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderList or revision<=0 or (row_revision!=0 and row_revision!=revision) or total<0 or total>16384 or page.size()>16 or start+page.size()>total or (page.is_empty() and start<total) or next!=(start+page.size() if start+page.size()<total else 0):
			_retire_rows();changed.emit();return
		for row in page:
			if row.get("workshop_id",-1)!=building_id or row.get("id",-1)<0 or row.get("native_state",{}).get("phase",0) not in [C.WorkOrderPhase.Active,C.WorkOrderPhase.Waiting,C.WorkOrderPhase.Checking,C.WorkOrderPhase.Ready]:
				_retire_rows();changed.emit();return
		row_revision=revision;row_total=total;rows_available=true
		for index in page.size():rows[start+index]=page[index].duplicate(true)
		row_offset=clampi(row_offset,0,maxi(0,row_total-row_capacity))
		_fill_rows();changed.emit())
	if row_ticket==0:_retire_rows();changed.emit()


func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	_retire_rows();row_offset=0;quantity_id=-1;pending_quantity=-1
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;snapshot={};pending_value=-1;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	building_id=id;refresh()
func refresh() -> void:
	if building_id<0 or ticket!=0:return
	_retire_rows()
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"workshop_orders":true,"building_id":building_id})
func step(delta: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or delta not in [-1,1]:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"workshop_orders":true,"building_id":building_id,"expected_revision":snapshot.revision,"general_order_delta":delta})
func set_limit(value: int) -> void:
	if value<0 or value>99:return
	if phase==Phase.Applying:pending_value=value;return
	if phase!=Phase.Ready or ticket!=0:return
	pending_value=-1;phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"workshop_orders":true,"building_id":building_id,"expected_revision":snapshot.revision,"general_order_value":value})
func set_quantity(id: int,value: int) -> void:
	if value<0 or value>9999:return
	if phase==Phase.Applying:
		if quantity_id==id:pending_quantity=value
		return
	if phase!=Phase.Ready or ticket!=0 or service==null:return
	var row: Dictionary={}
	for candidate in rows.values():
		if candidate.id==id:row=candidate;break
	if row.is_empty():return
	# Retire list reads so an older observation cannot replace the edit receipt.
	row_generation+=1
	if row_ticket!=0:service.detach(row_ticket);row_ticket=0
	quantity_id=id;pending_quantity=-1;phase=Phase.Applying
	var owner:=generation
	ticket=service.submit("work_orders",{"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":id,"remaining":value,"expected_revision":row.revision},func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var page: Array=result.get("work_order",{}).get("orders",[])
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderUpdate or page.size()!=1 or page[0].get("id",-1)!=quantity_id or page[0].get("workshop_id",-1)!=building_id or page[0].get("remaining",-1)!=sent.remaining or page[0].get("total",-1)!=sent.remaining or page[0].get("revision",0)<=0 or page[0].get("native_state",{}).is_empty():
			quantity_id=-1;pending_quantity=-1;_retire_rows();_fail(Phase.Unknown);return
		for index in rows:
			if rows[index].id==quantity_id:rows[index]=page[0].duplicate(true);break
		var next:=pending_quantity;var target:=quantity_id
		quantity_id=-1;pending_quantity=-1;phase=Phase.Ready;changed.emit();applied.emit()
		if next>=0:set_quantity(target,next)
		else:_fill_rows())
	if ticket==0:quantity_id=-1;pending_quantity=-1;_retire_rows();_fail(Phase.Unavailable);return
	changed.emit()
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	snapshot={};pending_value=-1;phase=next;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var value: Dictionary=result.get("production",{}).get("workshop_orders",{})
	if result.get("outcome","")=="unknown" or value.get("outcome",0)==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Rejected);return
	if result.get("action",-1)!=sent.action or value.get("building_id",-1)!=building_id or value.get("revision",0)<=0 or not value.get("order_ids") is Array:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		var absolute: int=sent.get("general_order_value",-1)
		var delta: int=sent.get("general_order_delta",0)
		var expected: int=absolute if absolute>=0 else clampi(int(snapshot.general_order_limit)+delta,0,99)
		if value.get("outcome",0)!=C.FarmEditOutcome.Completed or value.get("delta",0)!=delta or value.get("value",-1)!=absolute or value.get("general_order_limit",-1)!=expected:
			_fail(Phase.Unknown);return
	elif value.get("outcome",-1)!=C.FarmEditOutcome.None:_fail(Phase.Rejected);return
	snapshot=value.duplicate(true);phase=Phase.Ready
	if not editing:_read_rows(0)
	elif row_revision!=0 and row_revision!=int(value.revision):_retire_rows();_read_rows(0)
	changed.emit()
	if editing:applied.emit()
	# A later local draft is a new intent, sent only after a confirmed receipt.
	# Failure clears it above; never retry a rejected or uncertain write.
	if pending_value>=0:
		var next:=pending_value;pending_value=-1;set_limit(next)
