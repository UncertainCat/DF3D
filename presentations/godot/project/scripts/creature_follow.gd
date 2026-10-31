extends Node
# Viewer-owned follow identity outlives unit sheets. Each read owns one ticket.
signal changed
signal position_changed(tile: Vector3i)
const C=preload("res://scripts/management_contract.gd")
const INTERVAL:=0.1
var service
var unit_id: int=-1
var ticket:=0
var generation:=0
var remaining:=0.0
var last_position: Variant=null

func configure(source) -> void:
	dispose();service=source
	service.session_changed.connect(stop)

func dispose() -> void:
	stop()
	if is_instance_valid(service) and service.session_changed.is_connected(stop):service.session_changed.disconnect(stop)
	service=null

func stop() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if is_instance_valid(service) and previous!=0:service.detach(previous)
	unit_id=-1;last_position=null;remaining=0;changed.emit()

func toggle(id: int) -> void:
	if id==unit_id:stop();return
	stop()
	if id<0 or id>2147483647 or not is_instance_valid(service):return
	unit_id=id;changed.emit();_read()

func _process(delta: float) -> void:
	if unit_id<0 or ticket!=0:return
	remaining-=delta
	if remaining<=0:_read()

func _read() -> void:
	if unit_id<0 or ticket!=0:return
	var owner:=generation
	ticket=service.submit("creature_follow",{"action":C.ManagementAction.CreatureLocate,"unit_id":unit_id},func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:stop()

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0;remaining=INTERVAL
	var value: Dictionary=result.get("creature_position",{})
	if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.CreatureLocate:
		stop();return
	if result.has("creature_header") or typeof(value.get("unit_id"))!=TYPE_INT or value.unit_id!=unit_id or value.unit_id!=sent.unit_id or typeof(value.get("position"))!=TYPE_VECTOR3I:
		stop();return
	var tile: Vector3i=value.position
	if tile.x<0 or tile.y<0 or tile.z<0 or tile.x>32767 or tile.y>32767 or tile.z>32767:stop();return
	if last_position==null or last_position!=tile:
		last_position=tile;position_changed.emit(tile)

func _exit_tree() -> void:dispose()
