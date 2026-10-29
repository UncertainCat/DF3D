extends "res://tests/farm_name_workflow_test.gd"
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	setup();model.finish_name_entry();entry.finish()
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not check_assets(assets):return
	root.size=Vector2i(1200,800)
	var view=preload("res://scripts/farm_sheet_view.gd").new();root.add_child(view);view.configure(assets,model);view.layout(Vector2(root.size))
	await process_frame;await RenderingServer.frame_post_draw
	click(view.position+Vector2(384,30))
	check(view.name_entry.editing and model.name_session!=null,"actual rename button acquires typing session")
	for byte in "abc".to_utf8_buffer():
		var event:=InputEventKey.new();event.pressed=true;event.unicode=byte;view.feed_name_key(event)
	check(view.name_entry.value=="abc" and model.snapshot.custom_name=="","sheet draft remains separate from authority")
	service.poll()
	var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER;view.feed_name_key(enter)
	check(not view.name_entry.editing and model.phase==Model.Phase.Applying,"Enter ends visual editing while pending text drains")
	reply(named("a"),1);reply(named("abc",9007199254740995),1)
	check(model.phase==Model.Phase.Ready and view.title=="abc","sheet receives confirmed final title")
	await process_frame;await RenderingServer.frame_post_draw
	click(view.position+Vector2(384,30))
	var event:=InputEventKey.new();event.pressed=true;event.unicode=100;view.feed_name_key(event)
	service.poll();model.close();model.open(228,2)
	check(not view.name_entry.editing,"target retirement closes visual name draft")
	reply(named("abcd",9007199254740996),1);reply(named("other",9007199254740997,2,228))
	check(view.target==228 and view.title=="other" and not view.name_entry.editing,"late old name cannot overwrite replacement sheet")
	await process_frame;await RenderingServer.frame_post_draw
	click(view.position+Vector2(384,30))
	view.input_allowed=func():return false
	event.unicode=122;view.feed_name_key(event)
	check(view.name_entry.value=="other","sheet name input bypassed owner gate")
	view.input_allowed=Callable();view.feed_name_key(event);service.poll()
	view.queue_free();await process_frame
	reply(named("otherz",9007199254740998,2,228),1)
	check(model.phase==Model.Phase.Ready and model.snapshot.custom_name=="otherz","destroying view discarded explicit typed text")
	model.dispose();service.free();entry.free();assets.queue_free();await process_frame
	if failures==0:print("FARM_NAME_WORKFLOW_CAPTURE_PASS")
	quit(1 if failures else 0)
func check_assets(assets) -> bool:
	if assets.load_assets(OS.get_environment("DF3D_DF_PATH")):return true
	push_error("Farm assets unavailable");quit(1);return false
