extends "res://tests/native_options_save_live.gd"
# Protected writer only. Runner owns backups, save isolation, native verification
# and reload. This exercises actual pointer routing through the composed owner.
func run() -> void:
	output=OS.get_environment("DF3D_NATIVE_SAVE_ACCEPTANCE")
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var config=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("godot-config.json")))
	if not config is Dictionary or config.get("mode","") not in ["new-folder","existing","new-timeline"] or config.get("source","")=="":
		fail("Missing protected return configuration");return
	if config.mode=="new-timeline" and not str(config.get("timeline_name","")).begins_with("df3d.godot-timeline-"):
		fail("Missing owned timeline metadata");return
	root.size=Vector2i(1200,800)
	world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(str(config.df_path)):fail("Installed assets unavailable");return
	var state:Dictionary=world.poll_session()
	var deadline:=Time.get_ticks_msec()+30000
	while state.get("phase",4)!=3 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session()
	if not state.get("fortress_valid",false) or not state.get("paused",false) or state.get("active_save_id","")!=config.source or not state.get("can_save_return",false):
		fail("Owned source is not ready for SaveReturn");return
	var epoch:int=state.fortress_epoch
	options=preload("res://scripts/native_options.gd").new();root.add_child(options);options.configure(world)
	session=preload("res://scripts/native_options_session.gd").new();root.add_child(session);session.configure(world,options);session.update_session(state)
	var outcomes:Array[String]=[]
	session.settled.connect(func(value):outcomes.append(value))
	options.open();await process_frame
	await click_at(Vector2(600,310))
	if session.pending_seq==0 or options.page!=options.Page.MENU or not options.session_busy:
		fail("SaveReturn did not wait for a destination catalog");return
	deadline=Time.get_ticks_msec()+30000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session();session.update_session(state)
	if options.page!=options.Page.RETURN_CHOICES or outcomes!=["succeeded"] or options.return_choices.destination_ids.size()!=int(config.get("expected_destinations",1)):
		fail("Current destination catalog did not open");return
	var catalog:Dictionary=session.catalog.duplicate(true)
	var folders:Array=[]
	for row in catalog.destinations:folders.append(row.folder)
	if str(config.source).get_file() not in folders:
		fail("Catalog destination does not identify source timeline");return
	# Cancelling a local timeline draft must not send any save or lose the catalog.
	var first_row_y:float=options.return_choices.position.y+66
	await click_at(Vector2(600,first_row_y+36*folders.size()))
	if options.page!=options.Page.TIMELINE_NAME:fail("Timeline prompt did not open");return
	await key(0,47)
	await key(KEY_ESCAPE)
	if options.page!=options.Page.TIMELINE_NAME:fail("Escape dismissed native timeline prompt");return
	await click_at(Vector2(792,426))
	if options.page!=options.Page.RETURN_CHOICES or session.pending_seq!=0 or outcomes.size()!=1 or session.catalog!=catalog:
		fail("Cancelled timeline changed save ownership or catalog");return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("godot-return-chooser.png"))
	var chosen_row:int=folders.size()+1
	if config.mode=="existing":
		chosen_row=folders.find(str(config.get("destination","")).get_file())
		if chosen_row<0:fail("Requested existing destination is absent");return
	elif config.mode=="new-timeline":chosen_row=folders.size()
	var chosen_point:=Vector2(600,first_row_y+36*chosen_row)
	await click_at(chosen_point)
	if config.mode=="new-timeline":
		if options.page!=options.Page.TIMELINE_NAME or session.pending_seq!=0:
			fail("New timeline did not await metadata");return
		for character in str(config.timeline_name):await key(0,character.unicode_at(0))
		if options.timeline_naming.name_bytes!=str(config.timeline_name).to_utf8_buffer():
			fail("Timeline metadata changed before submission");return
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("godot-timeline-name.png"))
		await key(KEY_ENTER)
	var sequence:int=session.pending_seq
	if sequence==0 or not options.session_busy:fail("Destination choice did not send explicit intent");return
	if config.mode=="new-timeline":await key(KEY_ENTER)
	else:await click_at(chosen_point)
	if session.pending_seq!=sequence:fail("Repeated destination click changed pending request");return
	deadline=Time.get_ticks_msec()+180000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session();session.update_session(state)
	if session.pending_seq!=0 or outcomes!=["succeeded","succeeded"] or options.page!=options.Page.CLOSED:
		fail("SaveReturn did not settle once and close Options");return
	if state.get("phase",4)!=1 or state.get("request_fortress_epoch",0)!=epoch or state.get("saved_save_id","")=="" or state.saved_save_id==config.source:
		fail("SaveReturn receipt lacks the new destination or originating epoch");return
	if config.mode=="existing" and state.saved_save_id!=config.destination:
		fail("Existing-destination receipt did not match the chosen folder");return
	var file=FileAccess.open(output.path_join("godot-save-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence":sequence,"outcomes":outcomes,"catalog":catalog,"mode":config.mode,"chosen_row":chosen_row,"state":state},"  "));file.close()
	session.queue_free();options.queue_free();world.queue_free();await process_frame
	print("NATIVE_OPTIONS_RETURN_LIVE_PASS");quit(0)
