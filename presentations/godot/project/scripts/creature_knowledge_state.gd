extends RefCounted
# One viewer-owned detail request. Scroll/navigation state belongs to the sheet.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var unit_id: int=-1
var kind: int=-1
var entry_id: int=-1
var ticket:=0
var generation:=0
var text: String=""

func configure(source) -> void:
	dispose();service=source
	if is_instance_valid(service):service.session_changed.connect(_invalidated)
func dispose() -> void:
	close()
	if is_instance_valid(service) and service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
	service=null
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if is_instance_valid(service) and previous!=0:service.detach(previous)
	unit_id=-1;kind=-1;entry_id=-1;text="";phase=Phase.Closed;changed.emit()
func open(unit: int,category: int,id: int) -> void:
	if phase==Phase.Reading and unit==unit_id and category==kind and id==entry_id:return
	close()
	if unit<0 or unit>2147483647 or category<14 or category>17 or id<0 or id>2147483647:
		_fail(Phase.Rejected);return
	unit_id=unit;kind=category;entry_id=id
	if not is_instance_valid(service):_fail(Phase.Unavailable);return
	phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("creature_knowledge",{"action":C.ManagementAction.CreatureKnowledgeRead,"unit_id":unit,"kind":category,"id":id},func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0;_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	if result.get("outcome","")=="unknown":_fail(Phase.Unavailable);return
	if result.get("action")!=C.ManagementAction.CreatureKnowledgeRead or not _identity(sent):
		_fail(Phase.Rejected);return
	var value: Variant=result.get("creature_knowledge")
	if not value is Dictionary or not _identity(value) or typeof(value.get("outcome"))!=TYPE_INT or typeof(value.get("text"))!=TYPE_STRING:
		_fail(Phase.Rejected);return
	var outcome: int=value.outcome
	if outcome==C.CreatureKnowledgeOutcome.Ready:
		if result.get("status")!=C.ManagementStatus.Ok or value.text.to_utf8_buffer().size()>65536 or value.text.to_utf8_buffer().has(0):
			_fail(Phase.Rejected);return
		text=value.text;phase=Phase.Ready;changed.emit();return
	if result.get("status")!=C.ManagementStatus.Rejected or not value.text.is_empty() or outcome not in [C.CreatureKnowledgeOutcome.Rejected,C.CreatureKnowledgeOutcome.Unavailable]:
		_fail(Phase.Rejected);return
	_fail(Phase.Unavailable if outcome==C.CreatureKnowledgeOutcome.Unavailable else Phase.Rejected)
func _identity(value: Dictionary) -> bool:
	return typeof(value.get("unit_id"))==TYPE_INT and value.unit_id==unit_id and typeof(value.get("kind"))==TYPE_INT and value.kind==kind and typeof(value.get("id"))==TYPE_INT and value.id==entry_id
func _fail(next: Phase) -> void:
	text="";phase=next;changed.emit()
func _invalidated() -> void:
	var active:=phase!=Phase.Closed
	close()
	if active:_fail(Phase.Unavailable)
