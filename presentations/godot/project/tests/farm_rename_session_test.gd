extends "res://tests/farm_state_test.gd"
const Rename=preload("res://scripts/farm_rename_session.gd")

func setup() -> void:
	if service!=null:service.free()
	world=World.new();service=Service.new();root.add_child(service);service.configure(world);service.poll()

func session(observed:=facts()):
	var value=Rename.new();service.add_child(value);value.configure(service,observed);return value

func named(value: String,revision: int=9007199254740994) -> Dictionary:
	var observed:=facts();observed.custom_name=value;observed.header_name="Farm Plot" if value.is_empty() else value;observed.revision=revision;return observed

func run() -> void:
	setup();var owned=session();var events: Array=[]
	owned.changed.connect(func(snapshot):events.append(snapshot.custom_name);snapshot.custom_name="observer mutation")
	owned.finished.connect(func():events.append("finished"))
	owned.edit("A");owned.edit("AB");owned.edit("ABC");owned.finish()
	check(not owned.edit("discarded"),"ending rejects later text")
	service.submit("production",{"action":C.ManagementAction.ProductionInspect,"building_id":228,"season":0},Callable())
	service.poll();check(world.calls.size()==1 and world.calls[-1].request.farm_name=="A","first explicit edit survives finish before send")
	reply(named("A"),1)
	check(world.calls.size()==2 and world.calls[-1].request.farm_name=="ABC" and world.calls[-1].request.expected_revision==9007199254740994,"latest desired text continues ahead of later queued actions")
	check(owned.snapshot.custom_name=="A","observer cannot change session authority")
	reply(named("ABC",9007199254740995),1)
	check(events==["A","ABC","finished"] and owned.stopped,"finish drains text before completion")
	check(world.calls[-1].request.building_id==228,"queued interaction resumes after text drain")
	await process_frame

	setup();owned=session();events=[]
	owned.finished.connect(func():events.append("finished"))
	owned.finish();check(world.calls.is_empty() and events==["finished"],"unchanged finish does not write")
	await process_frame
	setup();owned=session();owned.edit("x".repeat(91));check(owned.ticket==0,"oversized draft is not sent")
	owned.edit("A");service.poll();owned.edit("");owned.finish();reply(named("A"),1)
	check(world.calls[-1].request.farm_name=="","backspace to original is preserved after earlier edit is sent")
	reply(named("",9007199254740995),1);check(owned.stopped,"cleared final draft completes")
	await process_frame

	for outcome in [2,3,4]:
		setup();owned=session();events=[];owned.failed.connect(func(result):events.append(result))
		owned.edit("A");service.poll();owned.edit("AB");owned.finish();reply({},outcome)
		check(owned.stopped and owned.snapshot.is_empty() and owned.desired.is_empty() and events.size()==1,"failed text session retires draft and authority")
		service.poll();check(world.calls.size()==1,"failure cannot replay buffered text")
		await process_frame
	for field in ["custom_name","building_id","selected_season","header_name","removing"]:
		setup();owned=session();events=[];owned.failed.connect(func(result):events.append(result))
		owned.edit("A");service.poll();owned.edit("AB")
		var bad:=named("A")
		match field:
			"custom_name":bad.custom_name="wrong"
			"building_id":bad.building_id=228
			"selected_season":bad.selected_season=2
			"header_name":bad.erase("header_name")
			"removing":bad.removing=true
		reply(bad,1)
		check(owned.stopped and events.size()==1 and events[0].outcome=="unknown" and world.calls.size()==1,"malformed completion cannot authorize continuation")
		await process_frame
	for sent in [false,true]:
		setup();owned=session();owned.edit("A")
		if sent:service.poll()
		owned.edit("AB");owned.finish()
		world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
		check(owned.stopped and owned.snapshot.is_empty() and world.calls.size()==int(sent),"epoch change retires queued/sent text without continuation")
		await process_frame
	# A changed observer can synchronously type/finish. It must still use the
	# receipt's one-shot continuation, with no duplicate normal submission.
	setup();owned=session();var retained=owned
	owned.changed.connect(func(_snapshot):retained.edit("AB");retained.finish())
	owned.edit("A");service.poll();reply(named("A"),1)
	check(world.calls.size()==2 and world.calls[-1].request.farm_name=="AB","reentrant changed observer keeps single continuation")
	reply(named("AB",9007199254740995),1);check(owned.stopped,"reentrant finish completes")
	await process_frame
	service.free();service=null
	if failures==0:print("FARM_RENAME_SESSION_PASS")
	quit(1 if failures else 0)
