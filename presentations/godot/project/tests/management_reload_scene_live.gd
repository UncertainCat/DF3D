extends "res://tests/chest_scene_live.gd"
const NAMES=["Tasks","Objects","Justice"]
const IDS=["tasks","objects","justice"]
const KEYS=["job_id","artifact_id","crime_id"]
var observations: Array=[]
func finish_reload(reason: String) -> void:
	var file:=FileAccess.open(directory+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"failed" if failed else "passed","reason":reason,"rounds":observations}));file.close()
	if is_instance_valid(scene):scene.queue_free();await process_frame
	quit(1 if failed else 0)
func settle(model) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		if model.phase==model.Phase.Ready:return true
		await create_timer(0.02).timeout
	return check(false,"Management surface did not become ready: "+str(model.phase))
func ready_main() -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		if scene._loader.entered and scene._ui.host.play_enabled and not actions._needs_claim and not actions._transport_lost and actions._generation==world.session_generation():return true
		await create_timer(0.05).timeout
	return check(false,"Main scene did not recover play authority")
func read_surfaces(label: String) -> Array:
	var membership: Array=[]
	for i in IDS.size():
		await pointer(scene._fortress_hud.launcher_rect(NAMES[i]).get_center())
		var panel_owner=scene._ui.controller(IDS[i])
		if not await settle(panel_owner.state):return []
		check(scene._ui.host.active==panel_owner and panel_owner.panel.visible,"HUD did not open "+NAMES[i])
		var membership_key: String=KEYS[i]
		membership.append(panel_owner.state.rows.map(func(row):return row.get(membership_key,-1)))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/"+label+"-"+IDS[i]+".png")
		key(KEY_ESCAPE);await process_frame
		check(not panel_owner.panel.visible and scene._ui.host.active==null,"Escape retained "+NAMES[i])
	return membership
func run() -> void:
	directory=OS.get_environment("DF3D_RELOAD_LANE")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	OS.set_environment("DF3D_FIXTURE","")
	var prefs=preload("res://scripts/presentation_settings.gd");prefs.loaded=true;prefs.ui_scale=1.0;prefs.camera_mode="df"
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world;actions=scene._ui.actions
	if not await ready_main():await finish_reload("initial main scene unavailable");return
	var baseline:=await read_surfaces("before")
	if failed:await finish_reload("initial public reads failed");return
	for round_index in range(1,3):
		var active_name: String="Tasks" if round_index==1 else "Justice"
		await pointer(scene._fortress_hud.launcher_rect(active_name).get_center())
		var active_owner=scene._ui.controller("tasks" if round_index==1 else "justice")
		if not await settle(active_owner.state):await finish_reload("pre-reload open failed");return
		var generation: int=active_owner.state.generation
		var old_epoch: int=int(world.poll_session().get("fortress_epoch",0))
		var file:=FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE);file.store_string(str(round_index));file.close()
		if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt")==OK,"Reload request publication failed"):await finish_reload("handshake failed");return
		var deadline:=Time.get_ticks_msec()+960000;var ack: Dictionary={}
		while ack.is_empty() and Time.get_ticks_msec()<deadline:
			for status in ["failed","incomplete","ack"]:
				var path:=directory+"/%s-%d"%[status,round_index]
				if not FileAccess.file_exists(path):continue
				var reply: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
				if not check(status=="ack","Native reload failed: "+str(reply)):await finish_reload("native reload failed");return
				ack=reply
			await create_timer(0.05).timeout
		if not check(not ack.is_empty(),"Reload timed out"):await finish_reload("reload timed out");return
		if not await ready_main():await finish_reload("main scene recovery failed");return
		var epoch: int=int(world.poll_session().get("fortress_epoch",0))
		check(epoch!=old_epoch and epoch==int(str(ack.epoch)),"Main scene retained old epoch")
		check(active_owner.state.generation>generation and active_owner.state.ticket==0 and active_owner.state.rows.is_empty(),"Reload retained old management authority")
		check(not active_owner.panel.visible and scene._ui.host.active==null,"Reload reopened stale panel")
		var fresh:=await read_surfaces("after-"+str(round_index))
		check(fresh==baseline,"Save-free reload changed public membership")
		observations.append({"round":round_index,"epoch":str(epoch),"active_before":active_name,"counts":fresh.map(func(rows):return rows.size())})
		if failed:await finish_reload("public recovery failed");return
	await finish_reload("two rendered main-scene reloads verified")
