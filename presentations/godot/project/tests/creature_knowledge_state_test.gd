extends "res://tests/farm_state_test.gd"
const Knowledge=preload("res://scripts/creature_knowledge_state.gd")
class LinkWorld:
	extends RefCounted
	var state: Dictionary={"world_epoch":5,"revision":1,"status":0}
	var calls: Array=[]
	var live:=true
	var generation:=1
	func reconnect_management():pass
	func session_generation():return generation
	func is_live():return live
	func last_error():return ""
	func poll_management():
		var value:=state.duplicate(true);value.transport_alive=live;return value
	func management_request(domain,request):
		calls.append({"domain":domain,"request":request.duplicate(true)});return calls.size()
func setup_knowledge() -> void:
	if model!=null:model.dispose()
	if service!=null:service.free()
	world=LinkWorld.new();service=Service.new();service.configure(world);service.poll()
	model=Knowledge.new();model.configure(service)
func payload(kind:=14,id:=42,unit:=86) -> Dictionary:
	return {"unit_id":unit,"kind":kind,"id":id,"outcome":C.CreatureKnowledgeOutcome.Ready,"text":"[B]Synthetic detail"}
func knowledge_reply(value: Variant,overrides: Dictionary={}) -> void:
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":C.ManagementAction.CreatureKnowledgeRead,"status":C.ManagementStatus.Ok,"creature_knowledge":value}
	world.state.merge(overrides,true);service.poll()
func run() -> void:
	for kind in range(14,18):
		setup_knowledge();model.open(86,kind,42);var ticket: int=model.ticket;model.open(86,kind,42);service.poll()
		check(model.ticket==ticket and world.calls.size()==1 and world.calls[0].domain=="creature_knowledge","duplicate pending selection shares one request")
		check(world.calls[0].request=={"action":C.ManagementAction.CreatureKnowledgeRead,"unit_id":86,"kind":kind,"id":42},"request owns full native identity")
		knowledge_reply(payload(kind));check(model.phase==Knowledge.Phase.Ready and model.text=="[B]Synthetic detail","matched native kind publishes detail")
		model.open(86,kind,43);check(model.text.is_empty() and model.phase==Knowledge.Phase.Reading,"replacement retires previous text immediately")
	for identity in [[-1,14,42],[2147483648,14,42],[86,13,42],[86,18,42],[86,14,-1],[86,14,2147483648]]:
		setup_knowledge();model.open(identity[0],identity[1],identity[2]);service.poll()
		check(model.phase==Knowledge.Phase.Rejected and world.calls.is_empty(),"invalid identity never reaches transport")
	for sent in [false,true]:
		setup_knowledge();model.open(86,14,42)
		if sent:service.poll()
		model.close();service.poll();check(world.calls.size()==(1 if sent else 0),"close cancels queued work and detaches sent work")
		if sent:knowledge_reply(payload())
		check(model.phase==Knowledge.Phase.Closed and model.text.is_empty(),"late reply cannot reopen closed detail")
	for replacement in [[87,14,42],[86,15,42],[86,14,43]]:
		setup_knowledge();model.open(86,14,42);service.poll();model.open(replacement[0],replacement[1],replacement[2])
		knowledge_reply(payload());service.poll()
		check(model.phase==Knowledge.Phase.Reading and model.text.is_empty(),"old unit/kind/entry cannot populate replacement")
		knowledge_reply(payload(replacement[1],replacement[2],replacement[0]))
		check(model.phase==Knowledge.Phase.Ready,"replacement accepts its own response")
	for field in ["unit_id","kind","id","outcome","text"]:
		setup_knowledge();model.open(86,14,42);service.poll();var value:=payload();value.erase(field);knowledge_reply(value)
		check(model.phase==Knowledge.Phase.Rejected and model.text.is_empty(),"missing response field rejected")
	for value in [null,42,payload(15),payload(14,43),payload(14,42,87)]:
		setup_knowledge();model.open(86,14,42);service.poll();knowledge_reply(value)
		check(model.phase==Knowledge.Phase.Rejected and model.text.is_empty(),"malformed or mismatched detail rejected")
	for count in [32768,32769]:
		setup_knowledge();model.open(86,14,42);service.poll();var value:=payload();value.text="é".repeat(count);knowledge_reply(value)
		check(model.phase==(Knowledge.Phase.Ready if count==32768 else Knowledge.Phase.Rejected),"detail bound counts UTF8 bytes")
	for outcome in [C.CreatureKnowledgeOutcome.Rejected,C.CreatureKnowledgeOutcome.Unavailable]:
		setup_knowledge();model.open(86,14,42);service.poll();var value:=payload();value.outcome=outcome;value.text="";knowledge_reply(value,{"status":C.ManagementStatus.Rejected});service.poll()
		check(model.phase==(Knowledge.Phase.Rejected if outcome==C.CreatureKnowledgeOutcome.Rejected else Knowledge.Phase.Unavailable) and model.text.is_empty() and world.calls.size()==1,"typed refusal clears text without retry")
	setup_knowledge();model.open(86,14,42);service.poll();service.poll(16.0);knowledge_reply(payload())
	check(model.phase==Knowledge.Phase.Unavailable and model.text.is_empty() and world.calls.size()==1,"timeout and late success never replay or revive detail")
	for pending in [false,true]:
		setup_knowledge();model.open(86,14,42);service.poll()
		if not pending:knowledge_reply(payload())
		world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
		check(model.phase==Knowledge.Phase.Unavailable and model.text.is_empty() and model.unit_id==-1,"session change retires pending and displayed detail")
	setup_knowledge();model.open(86,14,42);service.poll();model.dispose();knowledge_reply(payload())
	check(model.phase==Knowledge.Phase.Closed and model.text.is_empty(),"disposed owner cannot receive old completion")
	setup_knowledge();model.open(86,14,42);model.open(87,17,43);service.poll()
	check(world.calls.size()==1 and world.calls[0].request.unit_id==87 and world.calls[0].request.kind==17,"queued replacement cancels old identity before sending")
	for overrides in [{"unit_id":86.0},{"kind":14.0},{"id":42.0},{"outcome":1.0},{"outcome":255},{"text":42},{"outcome":C.CreatureKnowledgeOutcome.Unavailable}]:
		setup_knowledge();model.open(86,14,42);service.poll();var value:=payload();value.merge(overrides,true);knowledge_reply(value)
		check(model.phase==Knowledge.Phase.Rejected and model.text.is_empty(),"wrong types and contradictory outcome cannot publish text")
	setup_knowledge();model.open(86,14,42);service.poll();knowledge_reply(payload(),{"status":C.ManagementStatus.Rejected})
	check(model.phase==Knowledge.Phase.Rejected and model.text.is_empty(),"ready payload requires successful envelope")
	for disconnect in [false,true]:
		setup_knowledge();model.open(86,14,42);service.poll();knowledge_reply(payload())
		if disconnect:world.live=false
		else:world.generation+=1
		service.poll()
		check(model.phase==Knowledge.Phase.Unavailable and model.text.is_empty(),"disconnect or same-epoch session replacement clears displayed detail")
		world.live=true;service.poll();service.poll()
		check(world.calls.filter(func(call):return call.domain=="creature_knowledge").size()==1 and model.text.is_empty(),"reconnect may claim Catalog but never replays old detail request")
	setup_knowledge();world.live=false;service.poll();model.open(86,14,42)
	check(model.phase==Knowledge.Phase.Unavailable and model.ticket==0 and world.calls.is_empty(),"lost transport refuses submission")
	model.dispose();model.configure(null);model.open(86,14,42)
	check(model.phase==Knowledge.Phase.Unavailable and model.text.is_empty(),"missing service cannot publish detail")
	model.dispose()
	model=null;service.free();service=null
	if failures==0:print("CREATURE_KNOWLEDGE_STATE_PASS")
	quit(1 if failures else 0)
