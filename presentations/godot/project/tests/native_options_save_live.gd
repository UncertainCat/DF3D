extends SceneTree
# Invoked only by an owned lane after backup verification and an absent-name check.
var world
var options
var session
var output := ""
var failure := ""
func _initialize() -> void: call_deferred("run")
func fail(reason: String) -> void:
	failure = reason
	push_error(reason)
	quit(1)
func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	root.push_input(event,true);await process_frame
	event.pressed=false;root.push_input(event,true);await process_frame
func key(code: int, unicode_value: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode=code;event.unicode=unicode_value;event.pressed=true
	root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
	await process_frame
func run() -> void:
	output=OS.get_environment("DF3D_NATIVE_SAVE_ACCEPTANCE")
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var config=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("godot-config.json")))
	if not config is Dictionary or not str(config.get("name", "")).begins_with("df3d.godot-"):
		fail("Missing owned save configuration");return
	root.size=Vector2i(1200,800)
	world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(str(config.df_path)):fail("Installed assets unavailable");return
	var state:Dictionary=world.poll_session()
	var deadline:=Time.get_ticks_msec()+30000
	while state.get("phase",4)!=3 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
		state=world.poll_session()
	if not state.get("fortress_valid",false) or not state.get("paused",false) or state.get("active_save_id","")!=config.source or not state.get("can_save",false):
		fail("Owned source is not ready and paused");return
	options=preload("res://scripts/native_options.gd").new()
	root.add_child(options);options.configure(world)
	session=preload("res://scripts/native_options_session.gd").new()
	root.add_child(session);session.configure(world,options);session.update_session(state)
	var outcomes:Array[String]=[]
	session.settled.connect(func(value):outcomes.append(value))
	options.open();await process_frame
	await click_at(Vector2(600,346))
	if options.page!=options.Page.NAME or not options.naming.name_bytes.is_empty():
		fail("Save and continue did not open empty native naming prompt");return
	for character in str(config.name):await key(0,character.unicode_at(0))
	if options.naming.name_bytes!=str(config.name).to_utf8_buffer():
		fail("Native naming input changed destination bytes");return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("godot-before-save.png"))
	await key(KEY_ENTER)
	var sequence:int=session.pending_seq
	if sequence==0 or not options.session_busy or options.page!=options.Page.NAME:
		fail("Save request did not retain pending ownership");return
	await key(KEY_ENTER)
	if session.pending_seq!=sequence:fail("Repeated Enter changed pending save");return
	deadline=Time.get_ticks_msec()+180000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
		state=world.poll_session();session.update_session(state)
	if session.pending_seq!=0 or outcomes!=["succeeded"] or options.page!=options.Page.CLOSED:
		fail("Save did not settle exactly once and close Options");return
	if state.get("saved_save_id","")!=config.destination or not state.get("paused",false):
		fail("Save receipt destination or pause differs");return
	var file=FileAccess.open(output.path_join("godot-save-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence":sequence,"outcomes":outcomes,"state":state},"  "));file.close()
	session.queue_free();options.queue_free();world.queue_free();await process_frame
	print("NATIVE_OPTIONS_SAVE_LIVE_PASS")
	quit(0)
