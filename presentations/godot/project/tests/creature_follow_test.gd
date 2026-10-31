extends "res://tests/building_contents_state_test.gd"
const Follow=preload("res://scripts/creature_follow.gd")
var positions: Array=[]

func setup() -> void:
	if model!=null:model.dispose();model.free();service.free()
	world=World.new();service=Service.new();service.configure(world);model=Follow.new();model.configure(service)
	positions=[];model.position_changed.connect(func(tile):positions.append(tile))

func position_reply(id:=1000,tile:=Vector3i(5,6,7),status:=C.ManagementStatus.Ok) -> void:
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":C.ManagementAction.CreatureLocate,
		"status":status,"production":{},"creature_position":{"unit_id":id,"position":tile}}
	service.poll()

func ready() -> void:
	setup();model.toggle(1000);service.poll();position_reply()

func run() -> void:
	ready();check(model.unit_id==1000 and positions==[Vector3i(5,6,7)],"first native position focuses once")
	check(world.calls[0].request=={"action":C.ManagementAction.CreatureLocate,"unit_id":1000},"follow reads without building identity")
	model._process(0.05);service.poll();check(world.calls.size()==1,"reads are paced")
	model._process(0.06);service.poll();model._process(10);service.poll()
	check(world.calls.size()==2,"one pending observation at a time")
	position_reply();check(positions.size()==1,"unchanged position does not reset camera")
	model._process(0.11);service.poll();position_reply(1000,Vector3i(8,9,10))
	check(positions==[Vector3i(5,6,7),Vector3i(8,9,10)],"changed native position moves camera")
	model.toggle(1000);check(model.unit_id==-1,"same camera button disables follow")
	for sent in [false,true]:
		setup();model.toggle(1000);var pending: int=model.ticket
		if sent:service.poll()
		var count: int=world.calls.size();model.stop();service.poll()
		if sent:position_reply()
		else:check(service.result(pending).outcome=="not_sent","stop cancels queued read")
		model._process(10);service.poll()
		check(model.unit_id==-1 and model.ticket==0 and positions.is_empty() and world.calls.size()==count,"stop retires late reply and polling")
	setup();model.toggle(1000);service.poll();model.toggle(1001);position_reply()
	check(model.unit_id==1001 and positions.is_empty(),"old target cannot focus after replacement")
	position_reply(1001,Vector3i(12,13,14));check(positions==[Vector3i(12,13,14)],"new target owns observation")
	for kind in ["wrong_id","invalid_position","rejected","epoch"]:
		ready();model._process(0.11);service.poll();var count: int=world.calls.size()
		match kind:
			"wrong_id":position_reply(1001)
			"invalid_position":position_reply(1000,Vector3i(-1,2,3))
			"rejected":position_reply(1000,Vector3i.ZERO,C.ManagementStatus.Rejected)
			"epoch":world.state.world_epoch=6;service.poll()
		model._process(10);service.poll()
		check(model.unit_id==-1 and model.ticket==0 and world.calls.size()==count,"failed/retired follow never retries: "+kind)
	model.dispose();model.free();service.free()
	if failures==0:print("CREATURE_FOLLOW_PASS")
	quit(0 if failures==0 else 1)
