extends "res://tests/farm_state_test.gd"
const Entry=preload("res://scripts/farm_name_entry.gd")
var entry
func setup() -> void:
	if model!=null:model.dispose()
	if service!=null:service.free()
	if entry!=null:entry.free()
	world=World.new();service=Service.new();root.add_child(service);service.configure(world);service.poll()
	model=Model.new();model.configure(service);ready()
	entry=Entry.new();root.add_child(entry);entry.set_process(false)
	entry.edited.connect(model.edit_name_entry);entry.submitted.connect(model.finish_name_entry)
	entry.begin(model.snapshot.custom_name);check(model.begin_name_entry(),"begin name ownership")
func type_text(value: String) -> void:
	for byte in value.to_utf8_buffer():
		var event:=InputEventKey.new();event.pressed=true;event.unicode=byte;entry.feed_key(event)
func named(value: String,revision:=9007199254740994,season:=1,id:=227) -> Dictionary:
	var observed:=facts(id,season);observed.custom_name=value;observed.header_name="Farm Plot" if value.is_empty() else value;observed.revision=revision;return observed
func run() -> void:
	setup();type_text("abc")
	check(model.snapshot.custom_name=="" and model.phase==Model.Phase.Applying,"local draft is not optimistic authority")
	model.choose_crop(-1);model.toggle_fertilization();model.rename("other");model.refresh();service.poll()
	check(world.calls.size()==2 and world.calls[-1].request.farm_name=="a","typing excludes concurrent controller commands")
	model.finish_name_entry();reply(named("a"),1)
	check(model.snapshot.custom_name=="a" and model.phase==Model.Phase.Applying and world.calls[-1].request.farm_name=="abc","confirmed interim receipt retains edit lock and drains final text")
	reply(named("abc",9007199254740995),1)
	check(model.name_session==null and model.phase==Model.Phase.Ready and model.snapshot.custom_name=="abc","Enter releases only after final confirmation")
	await process_frame
	for sent in [false,true]:
		setup();type_text("a")
		if sent:service.poll()
		type_text("bc");model.close();model.open(228,2);service.poll()
		check(world.calls[-1].request.farm_name=="a","close preserves first explicitly typed command")
		reply(named("a"),1);reply(named("abc",9007199254740995),1)
		check(model.phase==Model.Phase.Reading and model.snapshot.is_empty() and world.calls[-1].request.building_id==228,"old name receipts cannot revive a replacement sheet")
		reply(named("other",9007199254740996,2,228))
		check(model.snapshot.custom_name=="other" and model.phase==Model.Phase.Ready,"replacement read follows old typed drain")
		await process_frame
	setup();type_text("abc");service.poll();model.select_season(2)
	reply(named("a"),1);reply(named("abc",9007199254740995),1)
	check(world.calls[-1].request.season==2 and model.snapshot.is_empty(),"tab change retires old typing observer")
	reply(named("abc",9007199254740995,2));check(model.phase==Model.Phase.Ready,"new tab receives final name")
	await process_frame
	for outcome in [2,3,4]:
		setup();type_text("abc");service.poll();reply({},outcome)
		var phase=Model.Phase.Unknown if outcome==4 else Model.Phase.Stale if outcome==3 else Model.Phase.Rejected
		check(model.phase==phase and model.snapshot.is_empty() and model.name_session==null,"failed rename retires authority")
		type_text("d");service.poll();check(world.calls.size()==2,"failed draft cannot replay")
		await process_frame
	for sent in [false,true]:
		setup();type_text("abc")
		if sent:service.poll()
		world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
		check(model.phase==Model.Phase.Unavailable and model.name_session==null and model.snapshot.is_empty(),"epoch change retires controller and typing")
		check(world.calls.size()==1+int(sent),"epoch change must not send buffered text")
		await process_frame
	setup();model.finish_name_entry();check(model.phase==Model.Phase.Ready and world.calls.size()==1,"unchanged Enter is read-only")
	model.dispose();service.free();entry.free();await process_frame
	if failures==0:print("FARM_NAME_WORKFLOW_PASS")
	quit(1 if failures else 0)
