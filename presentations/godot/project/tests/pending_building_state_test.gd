extends SceneTree
const Model=preload("res://scripts/pending_building_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Source extends RefCounted:
	signal session_changed
	var sequence:=0
	var callbacks: Dictionary={}
	var requests: Dictionary={}
	func submit(_domain,intent,callback) -> int:
		sequence+=1;callbacks[sequence]=callback;requests[sequence]=intent.duplicate(true);return sequence
	func detach(id) -> void:callbacks.erase(id)
	func reply(id,state,status=C.ManagementStatus.Ok) -> void:
		var callback: Callable=callbacks[id];callbacks.erase(id)
		callback.call(id,{"action":requests[id].action,"status":status,"production":{"pending_building":state}},requests[id])
var failed:=false
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func observation(stage: int) -> Dictionary:
	return {"id":965,"type":15,"revision":9007199254740993,"stage":stage,"max_stage":3,"job_id":68196,"suspended":true,"has_worker":false,"header_name":"Platinum Statue","removing":false,"forbidden":false}
func run_case(stage: int) -> void:
	var source=Source.new();var model=Model.new();model.configure(source)
	model.open(965);var late: Callable=source.callbacks[model.ticket];var ticket: int=model.ticket;var intent: Dictionary=source.requests[ticket]
	model.close();late.call(ticket,{"action":intent.action,"status":C.ManagementStatus.Ok,"production":{"pending_building":{"snapshot":observation(stage),"outcome":C.FarmEditOutcome.None,"removed":false,"removing":false}}},intent)
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"Late construction read revived closed state")
	model.open(965);source.reply(model.ticket,{"snapshot":observation(stage),"outcome":C.FarmEditOutcome.None,"removed":false,"removing":false})
	check(model.phase==Model.Phase.Ready and model.snapshot.revision==9007199254740993,"Construction read lost authority")
	var retired: Array=[];model.retired.connect(func(id,removing):retired.append([id,removing]))
	model.edit(Model.Operation.Cancel)
	check(source.requests[model.ticket].expected_revision==9007199254740993,"Construction intent lost revision precision")
	source.reply(model.ticket,{"outcome":C.FarmEditOutcome.Completed,"removed":stage==0,"removing":stage>0})
	check(model.phase==Model.Phase.Closed and model.building_id==-1 and model.snapshot.is_empty() and retired==[[965,stage>0]],"Cancellation retained old construction authority")
	model.open(965);source.reply(model.ticket,{"snapshot":observation(stage),"outcome":C.FarmEditOutcome.None,"removed":false,"removing":false})
	model.edit(Model.Operation.Suspend);var sent: int=source.sequence
	source.reply(model.ticket,{"outcome":C.FarmEditOutcome.Unknown,"removed":false,"removing":false},C.ManagementStatus.Rejected)
	model.edit(Model.Operation.Suspend)
	check(model.phase==Model.Phase.Unknown and model.snapshot.is_empty() and source.sequence==sent,"Unknown construction action retained authority or replayed")
	source.session_changed.emit();check(model.phase==Model.Phase.Unavailable and model.building_id==-1,"Session change retained construction target")
	model.dispose()
func _initialize() -> void:
	for stage in [0,1]:run_case(stage)
	var source=Source.new();var model=Model.new();model.configure(source)
	var removal:=observation(1);removal.removing=true;removal.suspended=false
	model.open(965);source.reply(model.ticket,{"snapshot":removal,"outcome":C.FarmEditOutcome.None,"removed":false,"removing":false})
	var sent: int=source.sequence
	model.edit(Model.Operation.Suspend);model.edit(Model.Operation.Cancel)
	check(source.sequence==sent,"Removal snapshot accepted construction actions")
	model.edit(Model.Operation.CancelRemoval)
	check(source.requests[model.ticket].pending_operation==3,"Cancel removal sent wrong operation")
	var idle:=removal.duplicate();idle.removing=false;idle.job_id=-1;idle.revision+=1
	source.reply(model.ticket,{"snapshot":idle,"outcome":C.FarmEditOutcome.Completed,"removed":false,"removing":false})
	check(model.phase==Model.Phase.Ready and model.snapshot==idle,"Cancel removal lost idle authority")
	sent=source.sequence;model.edit(Model.Operation.Suspend);model.edit(Model.Operation.Resume);model.edit(Model.Operation.CancelRemoval)
	check(source.sequence==sent,"Idle controls sent unsupported actions")
	for field in ["removing","suspended","has_worker"]:
		var malformed:=idle.duplicate();malformed[field]=true
		check(not Model.valid_snapshot(malformed,965),"Idle snapshot accepted false authority: "+field)
	model.edit(Model.Operation.Cancel)
	check(source.sequence==sent+1,"Idle building cannot queue removal")
	model.dispose()
	if not failed:print("PENDING_BUILDING_STATE_PASS")
	quit(1 if failed else 0)
