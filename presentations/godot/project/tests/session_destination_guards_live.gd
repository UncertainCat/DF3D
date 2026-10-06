extends SceneTree
# Protected lane only: attempted writes must reject, but backups are still required.
var output := ""
var failed := false
func _initialize() -> void: call_deferred("run")
func fail(reason: String) -> void:
	failed=true;push_error(reason);quit(1)
func write_json(name: String, value) -> void:
	var file=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  "));file.close()
func await_receipt(client, sequence: int, action: int) -> Dictionary:
	if sequence==0:fail("Protected guard request was not sent");return {}
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		var state:Dictionary=client.poll_session()
		if state.get("request_seq",0)==sequence and state.get("request_action",-1)==action and state.get("request_status",0) in [2,3,4]:return state
		await create_timer(0.05).timeout
	fail("Protected guard receipt timed out");return {}
func run() -> void:
	output=OS.get_environment("DF3D_NATIVE_SAVE_ACCEPTANCE")
	if output.is_empty():quit(77);return
	var config=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("godot-config.json")))
	if not config is Dictionary or config.get("mode","")!="destination-guards":fail("Missing protected guard configuration");return
	var first:=Df3dWorld.new();var second:=Df3dWorld.new()
	root.add_child(first);root.add_child(second)
	var initial:Dictionary=first.poll_session()
	var deadline:=Time.get_ticks_msec()+30000
	while initial.get("phase",4)!=3 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout;initial=first.poll_session()
	if initial.get("phase",4)!=3 or initial.get("active_save_id","")!=config.source or not initial.get("paused",false):
		fail("Protected guard source is not ready");return
	var epoch:int=initial.fortress_epoch
	var read_a:=await await_receipt(first,first.read_save_destinations(epoch),8)
	if failed:return
	if read_a.get("request_status",0)!=2 or not read_a.has("save_destinations"):fail("First catalog failed");return
	var catalog_a:Dictionary=read_a.save_destinations
	var target_a:=""
	for destination in catalog_a.destinations:
		if destination.folder==config.destination_folder:target_a=destination.id
	if target_a.is_empty():fail("Owned guard destination absent");return
	second.poll_session()
	var read_b:=await await_receipt(second,second.read_save_destinations(epoch),8)
	if failed:return
	if read_b.get("request_status",0)!=2 or not read_b.has("save_destinations"):fail("Competing catalog failed");return
	var catalog_b:Dictionary=read_b.save_destinations
	first.poll_session()
	var stale_owner:=await await_receipt(first,first.save_return_explicit(epoch,catalog_a.receipt,1,target_a,PackedByteArray()),2)
	if failed:return
	if stale_owner.get("request_status",0)!=3 or stale_owner.get("saved_save_id","")!="":fail("Superseded catalog dispatched a save");return
	write_json("competing-client.json",{"first_catalog":catalog_a,"second_catalog":catalog_b,"receipt":stale_owner})
	# The runner now changes only the loaded header's timeline name in memory.
	write_json("fixture-request.json",{"epoch":epoch,"catalog":catalog_b})
	deadline=Time.get_ticks_msec()+60000
	while not FileAccess.file_exists(output.path_join("fixture-ready.json")) and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	if not FileAccess.file_exists(output.path_join("fixture-ready.json")):fail("Native eligibility fixture unavailable");return
	var target_b:=""
	for destination in catalog_b.destinations:
		if destination.folder==config.destination_folder:target_b=destination.id
	second.poll_session()
	var stale_folders:=await await_receipt(second,second.save_return_explicit(epoch,catalog_b.receipt,1,target_b,PackedByteArray()),2)
	if failed:return
	if stale_folders.get("request_status",0)!=3 or stale_folders.get("saved_save_id","")!="":fail("Changed native catalog fell back or dispatched a save");return
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		var state:Dictionary=second.poll_session()
		if state.get("phase",4)==3 and state.get("can_save_return",false):break
		await create_timer(0.05).timeout
	var final_state:Dictionary=second.poll_session()
	if final_state.get("phase",4)!=3 or not final_state.get("can_save_return",false):fail("Rejected catalog left native menus owned");return
	write_json("changed-catalog.json",{"receipt":stale_folders,"final_state":final_state})
	first.queue_free();second.queue_free();await process_frame
	print("SESSION_DESTINATION_GUARDS_LIVE_PASS");quit(0)
