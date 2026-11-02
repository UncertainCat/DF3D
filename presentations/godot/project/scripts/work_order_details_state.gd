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
var first:=0
var rows: Array=[]
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(close)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(close):service.session_changed.disconnect(close)
	service=null
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;order_id=-1;snapshot={};rows=[];first=0;phase=Phase.Closed;changed.emit()
func open(building: int,order: int) -> void:
	close()
	if (building<0 and building!=-2) or order<0:return
	building_id=building;order_id=order;read_root()
func read_root() -> void:
	if ticket!=0:return
	first=0;rows=[];phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"details":{}})
func select_option(index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.get("options",[]).size():return
	first=0;rows=[];phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":index}})
func seek(value: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.get("selected_option",-1)<0:return
	first=clampi(value,0,maxi(0,rows.size()-1));changed.emit()
func choose(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for row in rows:
		if row.id==id:found=true;break
	if not found:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"choice":id,"expected_choices_revision":snapshot.choices_revision}})
func _fail(next: Phase) -> void:
	snapshot={};rows=[];phase=next;changed.emit()
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("work_orders",intent,func(received,result,sent):
		if generation==owner and ticket==received:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var writing: bool=sent.action==C.ManagementAction.WorkOrderUpdate
	var failure:=Phase.Unknown if writing else Phase.Rejected
	if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action or result.get("outcome","")=="unknown":_fail(failure);return
	var value: Dictionary=result.get("work_order",{}).get("details",{})
	var selected: int=-1 if writing else sent.details.get("option",-1)
	if value.get("id",-1)!=order_id or value.get("revision",0)<=0 or value.get("selected_option",-2)!=selected or not value.get("options") is Array:_fail(failure);return
	if selected>=0:
		var cursor: int=sent.details.get("cursor",0)
		if not value.get("choices") is Array or value.get("choices_revision",0)<=0 or cursor!=rows.size():_fail(failure);return
		if cursor>0 and (value.revision!=snapshot.revision or value.choices_revision!=snapshot.choices_revision):_fail(failure);return
		rows.append_array(value.choices.duplicate(true))
		if rows.size()>value.get("total",-1):_fail(failure);return
		snapshot=value.duplicate(true)
		var next: int=value.get("next_cursor",0)
		if next>0:
			if next!=rows.size() or value.choices.is_empty():_fail(failure);return
			_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":value.revision,"details":{"option":selected,"cursor":next,"expected_choices_revision":value.choices_revision}});return
		if rows.size()!=value.total:_fail(failure);return
	else:
		rows=[];first=0;snapshot=value.duplicate(true)
	phase=Phase.Ready
	if writing:applied.emit()
	changed.emit()
