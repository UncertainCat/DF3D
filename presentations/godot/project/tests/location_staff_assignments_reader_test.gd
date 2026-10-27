extends SceneTree
const Reader=preload("res://scripts/location_staff_assignments_reader.gd")
const Gesture=preload("res://scripts/location_specialization_workflow.gd")
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	signal session_changed
	var calls: Array=[]
	var detached: Array=[]
	func submit(domain,intent,callback):
		calls.append({"domain":domain,"intent":intent,"callback":callback});return calls.size()
	func detach(id):detached.append(id)
	func reply(id,facts,status=C.ManagementStatus.Ok):
		var call: Dictionary=calls[id-1]
		call.callback.call(id,{"status":status,"action":call.intent.action,"area":{"operation":call.intent.operation,"location_staff_assignments":facts}},call.intent)
class Details:
	extends RefCounted
	signal changed
	enum Phase { Ready, Refreshing, Closed }
	var phase:=Phase.Ready
	var generation:=1
	var identity: Dictionary={"site_id":651,"id":0}
	var snapshot: Dictionary={"revision":11,"staff":{"rows":[]}}
	var service=Service.new()
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func facts(row: Dictionary) -> Dictionary:
	var value:=Gesture.row_target(row)
	value.merge({"site_id":651,"location_id":0,"revision":9007199254740993,"entries":[{"kind":3,"id":10,"type":10,"subtype":-1,"custom":-1,"name":"Metalworks","custom_code":""}]})
	return value
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var details=Details.new();var service=details.service;var reader=Reader.new();reader.configure(details)
	var ordinary: Dictionary={"source":0,"occupation_id":87,"histfig_id":9375,"names":{"holder_kind":1,"holder_id":5813}}
	var religious: Dictionary={"source":1,"entity_id":383,"assignment_id":2,"histfig_id":10379,"unit_id":-1,"names":{"holder_kind":1,"holder_id":6536}}
	var historical:=religious.duplicate(true);historical.names={"holder_kind":2,"holder_id":10379}
	var foreign:=ordinary.duplicate(true);foreign.occupation_id=99
	details.snapshot.staff.rows=[ordinary,religious,historical]
	reader.display([ordinary,religious,historical,foreign,ordinary])
	check(service.calls.size()==1 and reader.rows.size()==2,"only current visible resolvable rows; one pending request")
	reader.display([ordinary,religious]);check(service.calls.size()==1,"redraw does not duplicate pending read")
	service.reply(1,facts(ordinary))
	check(service.calls.size()==2 and service.calls[-1].intent.unit_id==6536,"religious unit resolved from native names; serial second read")
	var empty:=facts(religious);empty.entries=[]
	service.reply(2,empty)
	check(reader.receipt(ordinary).get("revision")==9007199254740993 and reader.receipt(religious).entries.is_empty(),"typed wide revisions and empty membership retained")
	var copy:=reader.receipt(ordinary);copy.entries[0].name="changed"
	check(reader.receipt(ordinary).entries[0].name=="Metalworks","caller cannot mutate retained facts")
	reader.display([ordinary,religious]);check(service.calls.size()==2,"completed pass does not poll")
	# Refresh may retain the same Details revision while assignments change.
	details.phase=Details.Phase.Refreshing;details.changed.emit()
	check(reader.receipt(ordinary).is_empty(),"refresh retires old facts even with unchanged revision")
	details.phase=Details.Phase.Ready;details.changed.emit();reader.display([ordinary])
	var malformed:=facts(ordinary);malformed.histfig_id=99
	service.reply(3,malformed);reader.display([ordinary])
	check(reader.receipt(ordinary).is_empty() and service.calls.size()==3,"mismatched receipt is not displayed or retried")
	reader.display([religious]);var late: int=service.calls.size();reader.display([ordinary])
	check(late in service.detached,"scroll cancels previous window")
	service.reply(late,facts(religious))
	check(reader.receipt(religious).is_empty() and reader.ticket==late+1,"late reply cannot publish or advance replacement window")
	service.reply(late+1,{},C.ManagementStatus.Rejected);reader.display([ordinary])
	check(service.calls.size()==late+1,"rejection does not retry on redraw")
	reader.clear();reader.display([ordinary,religious]);var current: int=service.calls.size()
	var close_on_receipt: Callable=func():
		details.phase=Details.Phase.Closed;details.changed.emit()
	reader.changed.connect(close_on_receipt);service.reply(current,facts(ordinary));reader.changed.disconnect(close_on_receipt)
	check(service.calls.size()==current and reader.rows.is_empty(),"synchronous closure prevents second dispatch")
	details.phase=Details.Phase.Ready;reader.display([ordinary]);current=service.calls.size()
	service.session_changed.emit();service.reply(current,facts(ordinary))
	check(reader.rows.is_empty() and current in service.detached,"session retirement ignores late receipt")
	reader.dispose()
	for entries in [null,{},[{}],[{"kind":4,"id":1,"type":1,"subtype":-1,"custom":-1,"name":"","custom_code":""}],
		[{"kind":0,"id":1,"type":1,"subtype":-1,"custom":-1,"name":"invented","custom_code":""}],
		[{"kind":3,"id":1,"type":1,"subtype":0,"custom":-1,"name":"detail","custom_code":""}]]:
		check(not reader._valid_entries(entries),"malformed assignment entries refused")
	check(reader._valid_entries([]),"empty vector is a valid observation")
	var ordered: Array=[]
	for kind in 4:ordered.append({"kind":kind,"id":kind,"type":kind,"subtype":-1,"custom":-1,"name":"","custom_code":""})
	check(reader._valid_entries(ordered),"all four sources accepted in native order")
	ordered.reverse();check(not reader._valid_entries(ordered),"descending source order refused")
	if failures==0:print("LOCATION_STAFF_ASSIGNMENTS_READER_PASS")
	quit(1 if failures else 0)


