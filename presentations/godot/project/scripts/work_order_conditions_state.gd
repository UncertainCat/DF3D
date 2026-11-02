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
var draft_index: int=-1
var pending_threshold: int=-1
var filter_kind: int=-1
var filter_index: int=-1
var filter_rows: Array=[]
var filter_total:=0
var filter_first:=0
var filter_revision: int=0
var filter_query:=""
var filter_capacity:=15
func set_filter_capacity(value: int) -> void:
	filter_capacity=maxi(1,value)
	if filter_kind==3 and phase==Phase.Ready and ticket==0 and filter_rows.size()<mini(filter_capacity,filter_total-filter_first):_read()
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	filter_kind=-1;filter_index=-1;filter_rows=[];filter_total=0;filter_first=0;filter_revision=0;filter_query=""
	draft_index=-1;pending_threshold=-1
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;order_id=-1;snapshot={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(building: int,order: int) -> void:
	close()
	if (building<0 and building!=-2) or order<0:return
	building_id=building;order_id=order;_read()
func _read() -> void:
	phase=Phase.Reading
	if filter_kind==3:
		_send({"action":C.ManagementAction.WorkOrderCandidates,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_kind":1,"cursor":filter_first+filter_rows.size(),"expected_list_revision":filter_revision})
		return
	if filter_kind>=0:
		_send({"action":C.ManagementAction.WorkOrderCandidates,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_index":filter_index,"candidate_kind":filter_kind+3,"query":filter_query,"cursor":filter_first,"expected_list_revision":filter_revision})
		return
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id})
func open_dependencies() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	filter_kind=3;filter_index=-1;filter_rows=[];filter_query="";filter_first=0;filter_total=0;filter_revision=0;_read()
func edit_dependency(row: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or not snapshot.conditions.has(row) or row.kind!=1:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_kind":1,"condition_index":row.index,"target_order":row.target_order,"dependency":(int(row.dependency)+1)%2})
func open_filter(index: int,kind: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or kind<0 or kind>2:return
	var found:=false
	for row in snapshot.conditions:
		if row.kind==0 and row.index==index:found=true;break
	if not found:return
	filter_kind=kind;filter_index=index;filter_rows=[];filter_query="";filter_first=0;filter_total=0;filter_revision=0;_read()
func set_filter_query(value: String) -> void:
	if filter_kind<0 or value==filter_query or phase not in [Phase.Ready,Phase.Reading]:return
	filter_query=value;filter_first=0;filter_rows=[]
	if ticket==0:_read()
	changed.emit()
func seek_filter(first: int) -> void:
	if filter_kind<0 or phase not in [Phase.Ready,Phase.Reading]:return
	var next:=clampi(first,0,maxi(0,filter_total-1))
	if next==filter_first:return
	filter_first=next;filter_rows=[]
	if ticket==0:_read()
	changed.emit()
func choose_filter(id: int) -> void:
	if filter_kind<0 or phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for row in filter_rows:
		if row.id==id:found=true;break
	if not found:return
	phase=Phase.Applying
	if filter_kind==3:
		_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_kind":1,"target_order":id,"dependency":1,"expected_list_revision":filter_revision})
		return
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_index":filter_index,"candidate_kind":filter_kind+3,"filter_choice":id,"expected_list_revision":filter_revision})
func cycle_frequency() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"frequency":(int(snapshot.frequency)+1)%5})
func add_item_condition() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"compare":0,"threshold":0})
func add_suggestion(index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.suggested_conditions.size():return
	if not snapshot.suggested_conditions[index].get("editable",false):return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"suggestion_index":index})
func _fail(next: Phase) -> void:
	draft_index=-1;pending_threshold=-1
	snapshot={};filter_rows=[];phase=next;changed.emit()
func remove_condition(row: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or not snapshot.conditions.has(row):return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_kind":row.kind,"condition_index":row.index,"remove_condition":true})
func edit_amount(row: Dictionary,delta: int,cycle:=false) -> void:
	if phase!=Phase.Ready or ticket!=0 or not snapshot.conditions.has(row) or row.kind!=0:return
	var amount: int=row.threshold+delta
	if amount<0 or amount>2147483647:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_index":row.index,"compare":(int(row.compare)+1)%6 if cycle else row.compare,"threshold":amount})
func set_threshold(index: int,value: int) -> void:
	if value<0 or value>999999 or phase not in [Phase.Ready,Phase.Applying,Phase.Reading]:return
	if phase!=Phase.Ready and draft_index!=index:return
	var found:=false
	for row in snapshot.get("conditions",[]):
		if row.kind==0 and row.index==index:found=true;break
	if not found:return
	draft_index=index;pending_threshold=value;_flush_threshold()
func _flush_threshold() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	if pending_threshold<0:draft_index=-1;return
	var selected: Dictionary={}
	for row in snapshot.get("conditions",[]):
		if row.kind==0 and row.index==draft_index:selected=row;break
	if selected.is_empty():draft_index=-1;pending_threshold=-1;return
	var value:=pending_threshold;pending_threshold=-1
	if selected.threshold==value:draft_index=-1;return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCondition,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"condition_index":draft_index,"compare":selected.compare,"threshold":value})
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
	var dependency_read: bool=sent.action==C.ManagementAction.WorkOrderCandidates and sent.get("condition_kind",0)==1
	if rows.is_empty() or (not dependency_read and rows.size()!=1) or rows[0].get("id",-1)!=order_id or (building_id!=-2 and rows[0].get("workshop_id",-1)!=building_id) or rows[0].get("revision",0)<=0:
		_fail(Phase.Unknown if writing else Phase.Rejected);return
	if writing:
		if sent.action==C.ManagementAction.WorkOrderUpdate:
			if rows[0].get("frequency",-1)!=sent.frequency:_fail(Phase.Unknown);return
		elif sent.get("filter_choice",-1)>=0:
			if rows[0].get("conditions",[]).size()!=snapshot.conditions.size() or rows[0].frequency!=snapshot.frequency:_fail(Phase.Unknown);return
			snapshot=rows[0].duplicate(true)
			if filter_kind!=2:filter_kind=-1;filter_rows=[]
		elif sent.get("remove_condition",false):
			if rows[0].get("conditions",[]).size()!=snapshot.conditions.size()-1 or rows[0].get("frequency",-1)!=snapshot.frequency:_fail(Phase.Unknown);return
		elif sent.get("condition_kind",0)==1:
			var confirmed:=false
			for condition in rows[0].get("conditions",[]):
				if condition.kind==1 and condition.target_order==sent.target_order and condition.dependency==sent.dependency:confirmed=true
			if not confirmed or rows[0].conditions.size()!=snapshot.conditions.size()+(1 if sent.get("condition_index",-1)<0 else 0) or rows[0].frequency!=snapshot.frequency:_fail(Phase.Unknown);return
			filter_kind=-1;filter_rows=[]
		elif sent.get("condition_index",-1)>=0:
			var confirmed:=false
			for condition in rows[0].get("conditions",[]):
				if condition.kind==0 and condition.index==sent.condition_index:confirmed=condition.compare==sent.compare and condition.threshold==sent.threshold
			if not confirmed or rows[0].conditions.size()!=snapshot.conditions.size() or rows[0].frequency!=snapshot.frequency:_fail(Phase.Unknown);return
		elif rows[0].get("conditions",[]).size()!=snapshot.conditions.size()+1 or rows[0].get("frequency",-1)!=(1 if snapshot.frequency==0 else snapshot.frequency):
			_fail(Phase.Unknown);return
		applied.emit();_read();return
	if sent.action==C.ManagementAction.WorkOrderCandidates:
		var value: Dictionary=result.get("work_order",{})
		var page: Array=rows.slice(1) if dependency_read else value.get("choices",[])
		var revision: int=value.get("list_revision",0)
		var total: int=value.get("total",-1)
		if revision<=0 or (filter_revision!=0 and filter_revision!=revision) or total<0 or total>32768 or page.size()>128 or sent.cursor+page.size()>total:_fail(Phase.Rejected);return
		filter_revision=revision;snapshot=rows[0].duplicate(true)
		if sent.get("query","")!=filter_query or sent.cursor!=filter_first+(filter_rows.size() if dependency_read else 0):_read();return
		if dependency_read and total==0:filter_kind=-1;_read();return
		filter_total=total
		if dependency_read:
			if page.is_empty() and sent.cursor<total:_fail(Phase.Rejected);return
			filter_rows.append_array(page.duplicate(true))
			if filter_rows.size()<mini(filter_capacity,total-filter_first):_read();return
		else:filter_rows=page.duplicate(true)
		phase=Phase.Ready;changed.emit();return
	if not rows[0].get("suggested_conditions") is Array or rows[0].get("frequency",-1) not in [0,1,2,3,4]:_fail(Phase.Rejected);return
	snapshot=rows[0].duplicate(true);phase=Phase.Ready;_flush_threshold();changed.emit()
