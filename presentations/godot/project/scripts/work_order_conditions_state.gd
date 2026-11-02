extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var order_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
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
	building_id=-1;order_id=-1;snapshot={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(building: int,order: int) -> void:
	close()
	if building<0 or order<0:return
	building_id=building;order_id=order;_read()
func _read() -> void:
	phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id})
func cycle_frequency() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"frequency":(int(snapshot.frequency)+1)%5})
func add_suggestion(index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.suggested_conditions.size():return
	if not snapshot.suggested_conditions[index].get("editable",false):return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"suggestion_index":index})
func _fail(next: Phase) -> void:
	snapshot={};phase=next;changed.emit()
func remove_condition(row: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or not snapshot.conditions.has(row):return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_kind":row.kind,"condition_index":row.index,"remove_condition":true})
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("work_orders",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var writing: bool=sent.action in [C.ManagementAction.WorkOrderUpdate,C.ManagementAction.WorkOrderCondition]
	if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action or result.get("outcome","")=="unknown":
		_fail(Phase.Unknown if writing else Phase.Rejected);return
	var rows: Array=result.get("work_order",{}).get("orders",[])
	if rows.size()!=1 or rows[0].get("id",-1)!=order_id or rows[0].get("workshop_id",-1)!=building_id or rows[0].get("revision",0)<=0:
		_fail(Phase.Unknown if writing else Phase.Rejected);return
	if writing:
		if sent.action==C.ManagementAction.WorkOrderUpdate:
			if rows[0].get("frequency",-1)!=sent.frequency:_fail(Phase.Unknown);return
		elif sent.get("remove_condition",false):
			if rows[0].get("conditions",[]).size()!=snapshot.conditions.size()-1 or rows[0].get("frequency",-1)!=snapshot.frequency:_fail(Phase.Unknown);return
		elif rows[0].get("conditions",[]).size()!=snapshot.conditions.size()+1 or rows[0].get("frequency",-1)!=(1 if snapshot.frequency==0 else snapshot.frequency):
			_fail(Phase.Unknown);return
		applied.emit();_read();return
	if not rows[0].get("suggested_conditions") is Array or rows[0].get("frequency",-1) not in [0,1,2,3,4]:_fail(Phase.Rejected);return
	snapshot=rows[0].duplicate(true);phase=Phase.Ready;changed.emit()
