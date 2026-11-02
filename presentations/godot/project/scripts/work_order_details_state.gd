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
var query:=""
var art_base:=0
var visible_rows:=16
func has_art() -> bool:return snapshot.has("art")
func art_page() -> int:return int(snapshot.get("art",{}).get("page",-1))
func row_base() -> int:return art_base if has_art() else 0
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
	building_id=-1;order_id=-1;snapshot={};rows=[];first=0;art_base=0;query="";phase=Phase.Closed;changed.emit()
func open(building: int,order: int) -> void:
	close()
	if (building<0 and building!=-2) or order<0:return
	building_id=building;order_id=order;read_root()
func read_root() -> void:
	if ticket!=0:return
	first=0;rows=[];query="";phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"details":{}})
func select_option(index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.get("options",[]).size():return
	if snapshot.options[index].kind==1:_enter_art(index);return
	first=0;rows=[];query="";phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":index}})
func set_query(value: String) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or snapshot.get("selected_option",-1)<0 or value==query:return
	query=value;first=0;art_base=0;rows=[]
	if ticket==0:
		if has_art():_read_art(art_page())
		else:_read_choices()
	changed.emit()
func _read_choices(cursor:=0) -> void:
	phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"query":query,"cursor":cursor,"expected_choices_revision":snapshot.choices_revision}})
func seek(value: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.get("selected_option",-1)<0:return
	if has_art():
		if art_page()<0:return
		value=clampi(value,0,maxi(0,int(snapshot.art.total)-visible_rows))
		if value<art_base or mini(value+visible_rows,int(snapshot.art.total))>art_base+rows.size():_read_art(art_page(),value);return
		first=value;changed.emit();return
	first=clampi(value,0,maxi(0,rows.size()-1));changed.emit()
func choose(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for row in rows:
		if row.id==id:found=true;break
	if not found:return
	if has_art():
		if art_page()==-1:
			query="";first=0;art_base=0;rows=[]
			if id==0:_write_art(0,-1)
			else:_read_art(id)
		else:_write_art(art_page(),id)
		return
	if snapshot.options[snapshot.selected_option].kind==3 and id==0:_enter_art(snapshot.selected_option);return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"choice":id,"expected_choices_revision":snapshot.choices_revision}})
func _enter_art(option: int) -> void:
	first=0;art_base=0;rows=[];query="";phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":option,"art":{}}})
func _write_art(page: int,subject: int) -> void:
	phase=Phase.Applying
	var art: Dictionary={"page":page,"subject":subject}
	if page>0:art.merge({"query":query,"expected_list_revision":snapshot.art.list_revision})
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"art":art}})
func _read_art(page: int,cursor:=0) -> void:
	phase=Phase.Reading
	var art: Dictionary={"page":page,"query":query,"cursor":cursor}
	if cursor>0:art.expected_list_revision=snapshot.art.list_revision
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"art":art}})
func art_back() -> void:
	if ticket!=0 or not has_art() or art_page()<0:return
	query="";first=0;art_base=0;rows=[];_read_art(-1)
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
	var entering: bool=writing and sent.details.has("art") and sent.details.art.get("page",-1)==-1
	var selected: int=-1 if writing and not entering else sent.details.get("option",-1)
	if value.get("id",-1)!=order_id or value.get("revision",0)<=0 or value.get("selected_option",-2)!=selected or not value.get("options") is Array:_fail(failure);return
	if value.has("art"):
		if not sent.details.has("art"):_fail(failure);return
		var art: Dictionary=value.art
		var page: int=sent.details.art.get("page",-1)
		var cursor: int=sent.details.art.get("cursor",0)
		if art.get("page",-2)!=page or not art.get("rows") is Array or art.get("total",-1)<cursor+art.rows.size():_fail(failure);return
		if page>=0 and art.get("list_revision",0)<=0:_fail(failure);return
		if cursor>0 and (value.revision!=snapshot.revision or art.list_revision!=sent.details.art.expected_list_revision):_fail(failure);return
		snapshot=value.duplicate(true)
		if sent.details.art.get("query","")!=query:rows=[];_read_art(page);return
		rows=art.rows.duplicate(true);art_base=cursor;first=cursor;phase=Phase.Ready;changed.emit();return
	if sent.details.has("art") and (not writing or entering):_fail(failure);return
	if selected>=0:
		if sent.details.get("query","")!=query:
			snapshot=value.duplicate(true);rows=[];_read_choices();return
		var cursor: int=sent.details.get("cursor",0)
		if not value.get("choices") is Array or value.get("choices_revision",0)<=0 or cursor!=rows.size():_fail(failure);return
		if cursor>0 and (value.revision!=snapshot.revision or value.choices_revision!=snapshot.choices_revision):_fail(failure);return
		rows.append_array(value.choices.duplicate(true))
		if rows.size()>value.get("total",-1):_fail(failure);return
		snapshot=value.duplicate(true)
		var next: int=value.get("next_cursor",0)
		if next>0:
			if next!=rows.size() or value.choices.is_empty():_fail(failure);return
			_read_choices(next);return
		if rows.size()!=value.total:_fail(failure);return
	else:
		rows=[];first=0;snapshot=value.duplicate(true)
	phase=Phase.Ready
	if writing:applied.emit()
	changed.emit()
