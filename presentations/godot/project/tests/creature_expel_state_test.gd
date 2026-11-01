extends "res://tests/farm_state_test.gd"
const Expel=preload("res://scripts/creature_expel_state.gd")
func setup_expel() -> void:
	if model!=null:model.dispose()
	if service!=null:service.free()
	world=World.new();service=Service.new();service.configure(world);service.poll()
	model=Expel.new();model.configure(service)
func preview(id:=86,sites:=false) -> Dictionary:
	return {"unit_id":id,"eligible":true,"reason":-1,"units":[{"id":id,"name":"Native unit"},{"id":102,"name":"Relative"}],"destinations":[{"id":-1,"name":""},{"id":8,"name":"Native site"}] if sites else []}
func expel_reply(value: Dictionary,outcome:=C.CreatureExpelOutcome.Ready,action: int=-1) -> void:
	var sent: Dictionary=world.calls[-1].request
	var payload: Dictionary={"outcome":outcome}
	if outcome==C.CreatureExpelOutcome.Ready:payload.preview=value
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action if action==-1 else action,
		"status":C.ManagementStatus.Ok if outcome in [C.CreatureExpelOutcome.Ready,C.CreatureExpelOutcome.Applied] else C.ManagementStatus.Rejected,"creature_expel":payload}
	service.poll()
func ready_expel(sites:=false) -> void:
	model.open(86);service.poll();expel_reply(preview(86,sites))
func run() -> void:
	for sites in [false,true]:
		setup_expel();ready_expel(sites)
		check(model.phase==(Expel.Phase.Choosing if sites else Expel.Phase.Confirming),"native chooser/group transition")
		if sites:
			check(not model.confirm() and not model.choose(999),"chooser needs an offered destination")
			check(model.choose(8) and model.phase==Expel.Phase.Confirming,"site chooses group confirmation")
		var isolated: Dictionary=model.snapshot();isolated.units[0].id=999;isolated.units.clear()
		check(model.snapshot().units.size()==2,"display copy cannot change confirmation authority")
		var events: Array=[];model.applied.connect(func(id):events.append(id))
		check(model.confirm() and not model.confirm() and not model.choose(-1),"only one final intent")
		service.poll()
		check(world.calls[-1].domain=="creature_expel" and world.calls[-1].request=={"action":C.ManagementAction.CreatureExpelApply,"unit_id":86,"destination_id":8 if sites else -1,"expected_unit_ids":[86,102]},"final intent uses exact native group")
		expel_reply({},C.CreatureExpelOutcome.Applied)
		check(model.phase==Expel.Phase.Completed and events==[86] and model.snapshot().is_empty() and not model.confirm(),"confirmed departure retires authority once")
	setup_expel();ready_expel(true);check(model.choose(-1) and model.destination_id==-1,"Expel sentinel remains selectable")
	for reason in range(11):
		setup_expel();model.open(86);service.poll();var refused:=preview();refused.reason=reason;expel_reply(refused)
		check(model.phase==Expel.Phase.Refused and model.snapshot().reason==reason and not model.confirm(),"native refusal prevents mutation")
	setup_expel();model.open(86);service.poll();var ineligible:=preview();ineligible.eligible=false;ineligible.units=[];expel_reply(ineligible)
	check(model.phase==Expel.Phase.Refused and not model.confirm(),"ineligible target cannot confirm")
	for outcome in [C.CreatureExpelOutcome.Rejected,C.CreatureExpelOutcome.Unsupported,C.CreatureExpelOutcome.Unknown]:
		setup_expel();ready_expel();model.confirm();service.poll();expel_reply({},outcome);service.poll()
		check(model.phase==(Expel.Phase.Unknown if outcome==C.CreatureExpelOutcome.Unknown else Expel.Phase.Rejected) and model.snapshot().is_empty() and not model.confirm() and world.calls.size()==2,"failed/uncertain action never replays")
	setup_expel();ready_expel();model.confirm();service.poll();service.poll(16.0)
	check(model.phase==Expel.Phase.Unknown and world.calls.size()==2,"transport timeout has no automatic retry")
	expel_reply({},C.CreatureExpelOutcome.Applied)
	check(model.phase==Expel.Phase.Unknown,"late success cannot reopen uncertain view")
	for sending_apply in [false,true]:
		for sent in [false,true]:
			setup_expel()
			if sending_apply:ready_expel();model.confirm()
			else:model.open(86)
			if sent:service.poll()
			var before: int=world.calls.size()
			model.close();service.poll()
			check(world.calls.size()==before and model.phase==Expel.Phase.Closed,"closing cancels unsent work and detaches sent work")
			if sent:expel_reply({} if sending_apply else preview(),C.CreatureExpelOutcome.Applied if sending_apply else C.CreatureExpelOutcome.Ready)
			check(model.phase==Expel.Phase.Closed and model.snapshot().is_empty(),"late completion cannot repopulate closed view")
	setup_expel();ready_expel();model.confirm();service.poll();model.open(87)
	expel_reply({},C.CreatureExpelOutcome.Applied);service.poll()
	check(model.unit_id==87 and model.phase==Expel.Phase.Reading and model.snapshot().is_empty(),"old mutation cannot populate replacement target")
	expel_reply(preview(87));check(model.phase==Expel.Phase.Confirming and model.snapshot().unit_id==87,"replacement owns fresh preview")
	for applying in [false,true]:
		setup_expel();ready_expel()
		if applying:model.confirm();service.poll()
		world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
		check(model.phase==Expel.Phase.Unavailable and model.snapshot().is_empty() and not model.confirm(),"epoch invalidation retires confirmation")
	setup_expel();model.open(86);service.poll();expel_reply(preview(87))
	check(model.phase==Expel.Phase.Rejected,"wrong target preview rejected")
	model.dispose();service.free();model=null;service=null
	if failures==0:print("CREATURE_EXPEL_STATE_PASS")
	quit(1 if failures else 0)
