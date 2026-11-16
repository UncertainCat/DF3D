extends SceneTree
const State=preload("res://scripts/cage_picker_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends RefCounted:
	signal session_changed
	var serial:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain,intent,observer) -> int:
		serial+=1;calls[serial]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return serial
	func detach(id) -> void:detached.append(id)
	func reply(id,patch: Dictionary={}) -> void:
		var call: Dictionary=calls[id];var sent: Dictionary=call.intent
		var edit: bool=sent.cage_operation==1
		var page={"building_id":sent.building_id,"operation":sent.cage_operation,"query":sent.query,"sort":sent.cage_sort,"descending":sent.cage_descending,"columns":27,"revision":9007199254740993,"cursor":sent.get("cursor",0),"next_cursor":0,"total":1,"removing":false,"rows":[{"id":9,"entity":0,"assigned":edit}],"outcome":C.FarmEditOutcome.Completed if edit else C.FarmEditOutcome.None}
		if edit:
			page.merge({"candidate_id":sent.cage_candidate_id,"entity":sent.cage_entity,"assigned":sent.cage_assigned})
		page.merge(patch,true)
		call.observer.call(id,{"status":C.ManagementStatus.Ok,"action":sent.action,"production":{"cage":page}},sent)
var failures:=0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:
	var service=Service.new();var state=State.new();state.configure(service)
	state.open(3);service.reply(state.ticket)
	check(state.phase==State.Phase.Ready and state.revision==9007199254740993,"Read retains exact revision")
	state.toggle_animal(0,9);var pending: int=state.ticket
	check(service.calls[pending].intent.expected_revision==9007199254740993,"Edit uses observed revision")
	service.reply(pending);check(state.rows[0].assigned,"Confirmed assignment refreshes rows")
	state.toggle_animal(0,9);pending=state.ticket
	service.reply(pending,{"outcome":C.FarmEditOutcome.Unknown})
	var count: int=service.serial;state.toggle_animal(0,9)
	check(state.phase==State.Phase.Unknown and service.serial==count,"Unknown effect never replays")
	state.open(3);pending=state.ticket;state.open(4);var replacement: int=state.ticket
	service.reply(pending)
	check(state.building_id==4 and state.ticket==replacement and service.detached.has(pending),"Late reply cannot replace a new picker")
	service.session_changed.emit();service.reply(replacement)
	check(state.phase==State.Phase.Unavailable and state.building_id==-1,"Epoch retirement rejects late replies")
	state.open(3);service.reply(state.ticket)
	state.queue_owner_search(PackedByteArray([195]));state.tick(0.2)
	check(service.calls[state.ticket].intent.query==String.chr(0x251c),"Native byte search survives partial UTF8 deletion")
	service.reply(state.ticket,{"building_id":4})
	check(state.phase==State.Phase.Rejected,"Wrong building receipt cannot supply rows")
	state.dispose()
	print("cage_picker_state_test: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
