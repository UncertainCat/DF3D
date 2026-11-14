extends RefCounted
# Owns navigation receipts; detail panels consume only confirmed target identity.
signal changed
signal selected(kind: int,id: int,tile: Vector3i)
const C=preload("res://scripts/management_contract.gd")
const OP=C.SelectionOperation
enum Phase { Closed, Reading, Ready, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var snapshot: Dictionary={}
var tile:=Vector3i(-1,-1,-1)
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
	if service!=null and ticket!=0:service.detach(ticket)
	ticket=0;snapshot={};tile=Vector3i(-1,-1,-1);phase=Phase.Closed;changed.emit()
	# Bounded bridge ownership is replaced by the next OpenTile or world change.
	# No unobserved navigation request is submitted during local teardown.

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(point: Vector3i) -> void:
	close()
	if point.x<0 or point.y<0 or point.z<0 or point.x>32767 or point.y>32767 or point.z>32767:_fail(Phase.Rejected);return
	tile=point
	_send({"action":C.ManagementAction.Selection,"operation":OP.OpenTile,"origin":tile})

func choose_alternative(index: int) -> void:_choose(OP.SelectAlternative,"alternatives",index)
func choose_member(index: int) -> void:_choose(OP.SelectMember,"members",index)

func _choose(operation: int,field: String,index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.get(field,[]).size():return
	_send({"action":C.ManagementAction.Selection,"operation":operation,"receipt":snapshot.receipt,"index":index})

func _send(request: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation;phase=Phase.Reading
	ticket=service.submit("selection",request,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(value: Phase) -> void:
	phase=value;snapshot={};changed.emit()

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.Selection:_fail(Phase.Rejected);return
	var page: Dictionary=result.get("selection",{})
	if page.get("tile")!=tile or not page.get("complete",false) or typeof(page.get("open"))!=TYPE_BOOL:_fail(Phase.Rejected);return
	if not page.open:close();return
	if typeof(page.get("receipt"))!=TYPE_INT or page.receipt<=0 or typeof(page.get("kind"))!=TYPE_INT or typeof(page.get("id"))!=TYPE_INT:_fail(Phase.Rejected);return
	if typeof(page.get("alternatives"))!=TYPE_ARRAY or typeof(page.get("members"))!=TYPE_ARRAY:_fail(Phase.Rejected);return
	if sent.operation in [OP.SelectAlternative,OP.SelectMember]:
		var field: String="alternatives" if sent.operation==OP.SelectAlternative else "members"
		var target: Dictionary=snapshot[field][sent.index]
		if page.receipt==sent.receipt or page.kind!=target.kind or page.id!=target.id:_fail(Phase.Rejected);return
	snapshot=page.duplicate(true);phase=Phase.Ready
	var owner:=generation;changed.emit()
	if owner==generation:selected.emit(snapshot.kind,snapshot.id,tile)
