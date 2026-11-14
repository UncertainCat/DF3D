extends RefCounted
# Owns list receipts and selection intent; the action service owns sent writes.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Picking, Resolving, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var rows: Array=[]
var revision:=0
var give:=true
var picking:=false
var ticket:=0
var generation:=0
var _pending: Array=[]
var _total:=0
var _edit: Dictionary={}

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1
	var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
	building_id=-1;rows=[];revision=0;_pending=[];_edit={};picking=false;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	building_id=id;refresh()
func refresh() -> void:
	if building_id<0 or ticket!=0:return
	_pending=[];revision=0;phase=Phase.Reading;_read(0)
func _read(cursor: int) -> void:
	_send({"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.Links,"kind":2,"id":building_id,"cursor":cursor,"expected_list_revision":revision})
func begin_pick(direction: bool) -> void:
	if phase!=Phase.Ready:return
	give=direction;picking=true;phase=Phase.Picking;changed.emit()
func cancel_pick() -> void:
	if not picking:return
	# Cancel only the observer. A write already sent cannot be undone or replayed.
	generation+=1
	var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
	picking=false;_edit={};refresh()
func pick(tile: Vector3i) -> void:
	if phase!=Phase.Picking or tile.z<0:return
	phase=Phase.Resolving
	_send({"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LinkTarget,"kind":2,"id":building_id,"give":give,"origin":tile,"expected_revision":revision})
func unlink(row: Dictionary) -> void:
	if phase!=Phase.Ready or row not in rows or row.get("kind",-1)!=0:return
	_prepare_edit(row.id,int(row.direction)==1,true)
func _prepare_edit(id: int,direction: bool,remove: bool) -> void:
	_edit={"action":C.ManagementAction.AreaLink,"operation":C.AreaOperation.WorkshopLink,"kind":2,"id":building_id,"link_id":id,"give":direction,"unlink":remove,"expected_list_revision":revision}
	phase=Phase.Resolving
	_send({"action":C.ManagementAction.AreaInspect,"kind":0,"id":id})
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	_pending=[];_edit={};phase=next;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.AreaLink
	if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Rejected);return
	if result.get("action",-1)!=sent.action:_fail(Phase.Unknown if editing else Phase.Rejected);return
	var value: Dictionary=result.get("area",{})
	if editing:
		if value.get("operation",-1)!=C.AreaOperation.WorkshopLink:_fail(Phase.Unknown);return
		picking=false;_edit={};applied.emit();refresh();return
	if not _edit.is_empty():
		var piles: Array=result.get("areas",[])
		if piles.size()!=1 or piles[0].get("id",-1)!=_edit.link_id or piles[0].get("revision",0)<=0:_fail(Phase.Rejected);return
		_edit.expected_revision=piles[0].revision
		phase=Phase.Applying;_send(_edit.duplicate());return
	if value.get("area_id",-1)!=building_id or value.get("operation",-1)!=sent.operation or value.get("list_revision",0)<=0 or not value.get("links") is Array:
		_fail(Phase.Rejected);return
	if sent.operation==C.AreaOperation.LinkTarget:
		if value.list_revision!=revision or value.links.size()>1:_fail(Phase.Rejected);return
		if value.links.is_empty():phase=Phase.Picking;changed.emit();return
		var target: Dictionary=value.links[0]
		if target.get("kind",-1)!=0 or target.get("id",-1)<0 or target.get("direction",0)!=(1 if give else 2):_fail(Phase.Rejected);return
		_prepare_edit(target.id,give,false);return
	var total: int=value.get("build_total",-1)
	if total<0 or total>4096 or value.get("build_phase",-1)!=0 or value.get("build_done",-1)!=total:_fail(Phase.Rejected);return
	if sent.cursor==0:revision=value.list_revision;_total=total
	elif revision!=value.list_revision or _total!=total:_fail(Phase.Rejected);return
	if sent.cursor!=_pending.size() or value.links.size()!=mini(128,total-sent.cursor):_fail(Phase.Rejected);return
	_pending.append_array(value.links.duplicate(true))
	if value.get("next_cursor",0)!=0:
		if value.next_cursor!=_pending.size():_fail(Phase.Rejected);return
		_read(value.next_cursor);return
	if _pending.size()!=total:_fail(Phase.Rejected);return
	rows=_pending;_pending=[];phase=Phase.Ready;changed.emit()
