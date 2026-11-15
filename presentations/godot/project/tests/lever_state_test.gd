extends SceneTree
const Model=preload("res://scripts/lever_state.gd")
const C=preload("res://scripts/management_contract.gd")
var failed:=false
class Service:
	extends RefCounted
	signal session_changed
	var next:=0
	var pending: Dictionary={}
	func submit(_domain,intent,callback):
		next+=1;pending[next]=[intent,callback];return next
	func detach(_ticket):pass # Exercise late delivery despite retirement.
	func reply(ticket,value: Dictionary,unknown: bool=false):
		var entry: Array=pending[ticket]
		entry[1].call(ticket,{"action":entry[0].action,"status":C.ManagementStatus.Ok,"outcome":"unknown" if unknown else "", "production":{"lever":value}},entry[0])
func check(ok: bool,message: String) -> void:
	if not ok:failed=true;push_error(message)
func state(op: int,target: int=-1) -> Dictionary:
	return {"building_id":55,"revision":9007199254740993,"operation":op,"outcome":0 if op<2 else 1,
		"source_mechanism":11,"target_mechanism":12,"source_name":"native source","target_name":"native target",
		"target_id":target,"job_id":-1 if op<2 else 30}
func _initialize() -> void:
	var service=Service.new();var model=Model.new();model.configure(service)
	model.open(55);service.reply(model.ticket,state(0));model.begin_link()
	var cancelled: int=model.ticket;model.cancel_link();service.reply(cancelled,state(0))
	check(model.phase==Model.Phase.Ready and not model.pending_link,"Cancelled initial lookup entered target mode")
	model.begin_link()
	check(service.pending[model.ticket][0].lever_operation==0,"Link click did not refresh native selection")
	service.reply(model.ticket,state(0));model.preview(Vector3i(1,2,3));var old: int=model.ticket
	model.preview(Vector3i(4,5,6));var current: int=model.ticket
	service.reply(old,state(1,8));model.link()
	check(model.ticket==current and service.next==current,"Old hover enabled a Link mutation")
	service.reply(current,state(1,9));model.link();var mutation: int=model.ticket
	var sent: Dictionary=service.pending[mutation][0]
	check(sent.lever_target_id==9 and sent.lever_x==4 and sent.lever_source_mechanism==11 and sent.expected_revision==9007199254740993,"Link lost its owned target or selection")
	model.link();model.pull();check(service.next==mutation,"Pending mutation was duplicated")
	service.reply(mutation,{},true);model.link();model.pull();model.begin_link()
	check(model.phase==Model.Phase.Unknown and service.next==mutation,"Unknown mutation was replayed")
	model.open(55);var reopened: int=model.ticket
	service.reply(mutation,state(3,9));check(model.ticket==reopened and model.phase==Model.Phase.Reading,"Late mutation replaced reopened state")
	service.reply(reopened,state(0));model.begin_link();service.reply(model.ticket,state(0))
	model.preview(Vector3i(8,9,10));old=model.ticket;model.cancel_link();service.reply(old,state(1,16))
	check(model.phase==Model.Phase.Ready and model.target.is_empty(),"Cancelled preview regained authority")
	model.pull();old=model.ticket;service.session_changed.emit();service.reply(old,state(2))
	check(model.phase==Model.Phase.Unavailable and model.building_id==-1,"Old-session receipt reopened the lever")
	model.dispose();print("LEVER_STATE_PASS" if not failed else "LEVER_STATE_FAIL");quit(1 if failed else 0)
