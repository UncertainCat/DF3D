extends "res://tests/native_options_save_live.gd"
# Owned protected lane only. The runner suspends native execution before the
# write is queued, then disables the producer before releasing the safe point.
func write_json(name: String, value) -> void:
	var file=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  "));file.close()
func run() -> void:
	output=OS.get_environment("DF3D_NATIVE_SAVE_ACCEPTANCE")
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var config=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("godot-config.json")))
	if not config is Dictionary or config.get("mode","")!="producer-loss":fail("Missing producer-loss protection");return
	root.size=Vector2i(1200,800)
	world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(str(config.df_path)):fail("Installed assets unavailable");return
	var state:Dictionary=world.poll_session()
	var deadline:=Time.get_ticks_msec()+30000
	while state.get("phase",4)!=3 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session()
	if state.get("active_save_id","")!=config.source or not state.get("paused",false) or not state.get("can_save_return",false):
		fail("Owned producer-loss source unavailable");return
	var epoch:int=state.fortress_epoch
	options=preload("res://scripts/native_options.gd").new();root.add_child(options);options.configure(world)
	session=preload("res://scripts/native_options_session.gd").new();root.add_child(session);session.configure(world,options);session.update_session(state)
	var outcomes:Array[String]=[]
	session.settled.connect(func(value):outcomes.append(value))
	options.open();await process_frame;await click_at(Vector2(600,310))
	deadline=Time.get_ticks_msec()+30000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout;state=world.poll_session();session.update_session(state)
	if options.page!=options.Page.RETURN_CHOICES or outcomes!=["succeeded"]:fail("Producer-loss catalog failed");return
	var target_row:=-1
	for index in session.catalog.destinations.size():
		if session.catalog.destinations[index].folder==config.destination_folder:target_row=index
	if target_row<0:fail("Protected existing target missing");return
	write_json("fixture-request.json",{"epoch":epoch,"catalog":session.catalog})
	deadline=Time.get_ticks_msec()+30000
	while not FileAccess.file_exists(output.path_join("hold-ready.json")) and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	if not FileAccess.file_exists(output.path_join("hold-ready.json")):fail("Native safe point unavailable");return
	await click_at(Vector2(600,options.return_choices.position.y+66+target_row*36))
	var sequence:int=session.pending_seq
	if sequence==0:fail("Protected save was not queued");return
	write_json("queued.json",{"sequence":sequence,"epoch":epoch})
	deadline=Time.get_ticks_msec()+30000
	while session.pending_seq!=0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout;state=world.poll_session();session.update_session(state)
	if session.pending_seq!=0 or outcomes!=["succeeded","unknown"] or state.get("request_status",0)!=4 or state.get("phase",0)!=4:
		fail("Stopped producer did not settle as unknown");return
	if state.get("request_seq",0)!=sequence or state.get("request_fortress_epoch",0)!=epoch or state.get("saved_save_id","")!="" or options.page!=options.Page.RETURN_CHOICES:
		fail("Stopped producer lost save identity or closed the draft");return
	write_json("lost.json",{"state":state,"outcomes":outcomes,"last_outcome":session.last_outcome,"page":options.page})
	deadline=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;state=world.poll_session();session.update_session(state)
		if state.get("phase",4)==1:break
	if state.get("phase",4)!=1 or session.pending_seq!=0 or outcomes!=["succeeded","unknown"] or state.get("request_seq",0)!=0 or state.get("saved_save_id","")!="":
		fail("Replacement title connection replayed or retained the old request");return
	if options.page!=options.Page.RETURN_CHOICES:fail("Replacement producer closed the unknown draft as success");return
	write_json("reconnected.json",{"state":state,"outcomes":outcomes,"last_outcome":session.last_outcome,"page":options.page})
	session.queue_free();options.queue_free();world.queue_free();await process_frame
	print("SESSION_PRODUCER_LOSS_LIVE_PASS");quit(0)
