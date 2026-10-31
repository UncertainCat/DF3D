extends "res://tests/farm_state_test.gd"
const Header=preload("res://scripts/creature_header_state.gd")
func header_facts(id:=86,nickname:="",profession:="",revision:=9007199254740993) -> Dictionary:
	return {"unit_id":id,"historical_figure_id":102,"has_figure":true,"nickname":nickname,"profession":profession,"figure_nickname":nickname,"revision":revision}
func setup_header() -> void:
	if model!=null:model.dispose()
	if service!=null:service.free()
	world=World.new();service=Service.new();root.add_child(service);service.configure(world);service.poll()
	model=Header.new();model.configure(service)
func header_reply(value: Dictionary,outcome:=1) -> void:
	var sent: Dictionary=world.calls[-1].request
	var payload: Dictionary={"outcome":outcome,"mutated":sent.action==C.ManagementAction.CreatureHeaderEdit}
	if outcome==1:payload.snapshot=value
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":sent.action,
		"status":C.ManagementStatus.Ok if outcome==1 else C.ManagementStatus.Rejected,"creature_header":payload}
	service.poll()
func ready_header() -> void:
	model.open(86);service.poll();header_reply(header_facts());check(model.phase==Header.Phase.Ready,"header read ready")
func run() -> void:
	setup_header();ready_header();check(model.begin(),"header editor begins")
	var events: Array=[];model.applied.connect(func():events.append(true))
	model.edit(false,"A");model.edit(false,"AB");model.edit(false,"ABC");model.edit(true,"Miner");model.finish()
	service.poll();check(world.calls[-1].request.name=="A","first typed intent sent")
	header_reply(header_facts(86,"A","",9007199254740994))
	check(world.calls[-1].request.name=="ABC" and world.calls[-1].request.expected_revision==9007199254740994,"coalesced nickname uses confirmed revision")
	header_reply(header_facts(86,"ABC","",9007199254740995))
	check(world.calls[-1].request.profession and world.calls[-1].request.name=="Miner","field switch preserves explicit intent order")
	header_reply(header_facts(86,"ABC","Miner",9007199254740996))
	check(model.phase==Header.Phase.Ready and events.size()==3,"editor finishes after both fields drain")
	await process_frame
	for sent in [false,true]:
		setup_header();ready_header();model.begin();model.edit(false,"A");model.edit(false,"AB")
		if sent:service.poll()
		model.open(87);service.poll()
		header_reply(header_facts(86,"A","",9007199254740994))
		header_reply(header_facts(86,"AB","",9007199254740995))
		check(model.unit_id==87 and model.snapshot.is_empty() and model.phase==Header.Phase.Reading,"old completion cannot populate new target")
		check(world.calls[-1].request.unit_id==87 and world.calls[-1].request.action==C.ManagementAction.CreatureHeaderRead,"new target read follows old typed intents")
		header_reply(header_facts(87));check(model.snapshot.unit_id==87,"new selection owns new authority")
		await process_frame
	for outcome in [0,2,3]:
		setup_header();ready_header();model.begin();model.edit(false,"A");service.poll();model.edit(false,"AB")
		header_reply({},outcome);service.poll()
		check(world.calls.size()==2 and model.snapshot.is_empty() and model.name_session==null,"failed edit discards buffered text without replay")
		await process_frame
	for key in ["unit_id","nickname","profession","figure_nickname","historical_figure_id"]:
		setup_header();ready_header();model.begin();model.edit(false,"A");service.poll();model.edit(false,"AB")
		var bad:=header_facts(86,"A","",9007199254740994)
		bad[key]=87 if key in ["unit_id","historical_figure_id"] else "unexpected"
		header_reply(bad);check(model.phase==Header.Phase.Unknown and world.calls.size()==2,"contradictory receipt cannot authorize continuation")
		await process_frame
	for sent in [false,true]:
		setup_header();ready_header();model.begin();model.edit(false,"A")
		if sent:service.poll()
		model.edit(true,"Miner")
		world.state={"world_epoch":6,"revision":99,"status":0};service.poll()
		check(model.phase==Header.Phase.Unavailable and model.snapshot.is_empty() and world.calls.size()==1+int(sent),"epoch change retires draft without continuation")
		await process_frame
	setup_header();model.open(86);model.close();service.poll();check(world.calls.is_empty(),"queued read detaches on close")
	model.dispose()
	var editor=preload("res://scripts/creature_customize_editor.gd").new();root.add_child(editor);editor.configure(service);model=editor.state
	editor.observe_captions(1,{"name":"Native name","profession":"Native profession"})
	editor.open(86);service.poll();header_reply(header_facts())
	check(editor.opened and editor.field==-1 and editor.caption(0,0)=="Native name","Customize opens with native fallback")
	editor.focus(false)
	var letter:=InputEventKey.new();letter.pressed=true;letter.unicode=81;letter.keycode=KEY_Q
	editor.feed_key(letter);editor.focus(true);letter.unicode=82;letter.keycode=KEY_R;editor.feed_key(letter)
	check(editor.values==["Q","R"] and editor.field==1,"last clicked field receives typing")
	check(editor.caption(1,0)=="R_" and editor.caption(1,500)=="R","native cursor phase")
	var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER;editor.feed_key(enter)
	check(editor.opened and editor.field==-1,"Enter ends field without closing Customize")
	check(not editor.fallback_valid,"unconfirmed typing cannot reuse old fallback captions")
	service.poll();header_reply(header_facts(86,"Q","",9007199254740994));header_reply(header_facts(86,"Q","R",9007199254740995))
	check(not editor.fallback_valid,"confirmed edits invalidate old fallback captions")
	editor.observe_captions(1,{"name":"Native name","profession":"Native profession"});check(not editor.fallback_valid,"old publication cannot reauthorize fallback")
	editor.observe_captions(2,{"name":"Q","profession":"R"});check(editor.fallback_valid,"fresh publication supplies fallback")
	editor.focus(false);letter.unicode=0;letter.keycode=KEY_BACKSPACE;editor.feed_key(letter)
	service.poll();header_reply({},2)
	check(not editor.opened and editor.values==["",""] and editor.field==-1,"stale write retires editor draft")
	editor.queue_free();await process_frame;model=null
	service.free();service=null
	if failures==0:print("CREATURE_HEADER_STATE_PASS")
	quit(1 if failures else 0)
