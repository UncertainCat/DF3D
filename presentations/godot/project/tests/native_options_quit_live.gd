extends "res://tests/native_options_save_live.gd"
# Protected owned no-save effect lane. The runner proves in-memory changes are
# discarded, the same process reaches title, and the original save reloads intact.
func run() -> void:
	output=OS.get_environment("DF3D_NATIVE_SAVE_ACCEPTANCE")
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var config=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("godot-config.json")))
	if not config is Dictionary or config.get("mode","")!="quit-without-saving":fail("Missing protected Quit configuration");return
	root.size=Vector2i(1200,800)
	world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(str(config.df_path)):fail("Installed assets unavailable");return
	var state:Dictionary=world.poll_session()
	var deadline:=Time.get_ticks_msec()+30000
	while state.get("phase",4)!=3 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session()
	if state.get("active_save_id","")!=config.source or not state.get("paused",false) or not state.get("can_save_return",false):
		fail("Owned Quit source unavailable");return
	var epoch:int=state.fortress_epoch
	options=preload("res://scripts/native_options.gd").new();root.add_child(options);options.configure(world)
	session=preload("res://scripts/native_options_session.gd").new();root.add_child(session);session.configure(world,options);session.update_session(state)
	var outcomes:Array[String]=[]
	session.settled.connect(func(value):outcomes.append(value))
	options.open();await process_frame;await click_at(Vector2(600,454))
	if options.page!=options.Page.CONFIRMATION or options.confirmation.token!="QUIT_WITHOUT_SAVING" or session.pending_seq!=0:
		fail("Quit did not await native confirmation");return
	await key(KEY_ESCAPE)
	if options.page!=options.Page.CONFIRMATION or session.pending_seq!=0:fail("Escape changed Quit confirmation");return
	await click_at(Vector2(792,442))
	if options.page!=options.Page.MENU or session.pending_seq!=0 or not outcomes.is_empty():fail("Cancel dispatched Quit");return
	await click_at(Vector2(600,454));await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("godot-quit-confirmation.png"))
	await click_at(Vector2(392,442))
	var sequence:int=session.pending_seq
	if sequence==0 or not options.session_busy:fail("Confirmed Quit was not submitted");return
	await click_at(Vector2(392,442))
	if session.pending_seq!=sequence:fail("Repeated confirmation changed the Quit request");return
	deadline=Time.get_ticks_msec()+120000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout;state=world.poll_session();session.update_session(state)
	if session.pending_seq!=0 or outcomes!=["succeeded"] or options.page!=options.Page.CLOSED:
		fail("Quit did not close exactly once on native completion");return
	if state.get("phase",4)!=1 or state.get("fortress_epoch",1)!=0 or state.get("request_fortress_epoch",0)!=epoch or state.get("request_action",-1)!=9 or state.get("saved_save_id","")!="":
		fail("Quit receipt lost identity or invented a saved destination");return
	var file=FileAccess.open(output.path_join("godot-quit-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence":sequence,"outcomes":outcomes,"state":state},"  "));file.close()
	session.queue_free();options.queue_free();world.queue_free();await process_frame
	print("NATIVE_OPTIONS_QUIT_LIVE_PASS");quit(0)
