extends RefCounted
# Native catalog receipt and one-shot creation. Owns no DF menu state.
signal changed
signal created(order: Dictionary)
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var revision: int=0
var rows: Array=[]
var ticket:=0
var generation:=0
var query:=""
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
	building_id=-1;revision=0;rows=[];query="";phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	building_id=id;phase=Phase.Reading;_read(0)
func _read(cursor: int) -> void:
	_send({"action":C.ManagementAction.WorkOrderCatalog,"workshop_id":building_id,"cursor":cursor,"expected_list_revision":revision,"query":query})
func set_query(value: String) -> void:
	if value==query or building_id<0 or phase not in [Phase.Ready,Phase.Reading]:return
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	query=value;revision=0;rows=[];phase=Phase.Reading;_read(0)
func choose(key: String) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for row in rows:
		if row.key==key:found=true;break
	if not found:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderCreate,"workshop_id":building_id,"recipe":key,"expected_revision":revision,"remaining":10})
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("work_orders",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	rows=[];revision=0;phase=next;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var applying: bool=sent.action==C.ManagementAction.WorkOrderCreate
	# The existing work-order envelope has no explicit uncertain-effect enum.
	# Conservatively retire every unsuccessful create; never offer an automatic
	# retry or restore its catalog authority after a rejection or lost reply.
	if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action:
		_fail(Phase.Unknown if applying else Phase.Rejected);return
	var value: Dictionary=result.get("work_order",{})
	if applying:
		var orders: Array=value.get("orders",[])
		if orders.size()!=1 or orders[0].get("id",-1)<0 or orders[0].get("workshop_id",-1)!=building_id or orders[0].get("total",-1)!=10:
			_fail(Phase.Unknown);return
		var receipt: Dictionary=orders[0].duplicate(true)
		close();created.emit(receipt);return
	var received_revision: int=value.get("list_revision",0)
	var page: Array=value.get("recipes",[])
	var next: int=value.get("next_cursor",0)
	var total: int=value.get("total",-1)
	if received_revision<=0 or (revision!=0 and revision!=received_revision) or total<0 or total>65536 or page.size()>128 or rows.size()+page.size()>total:
		_fail(Phase.Rejected);return
	for row in page:
		if not row is Dictionary or not row.get("key") is String or not row.get("name") is String:_fail(Phase.Rejected);return
	revision=received_revision;rows.append_array(page)
	if next!=0:
		if next!=rows.size() or next<=int(sent.cursor):_fail(Phase.Rejected);return
		_read(next);return
	if rows.size()!=total:_fail(Phase.Rejected);return
	phase=Phase.Ready;changed.emit()
