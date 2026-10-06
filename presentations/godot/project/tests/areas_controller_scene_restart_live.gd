extends "res://tests/areas_controller_scene_live.gd"
# Main-scene producer replacement while a pointer-painted draft is local.
var invalidations := 0
var last_scene_state := []

func observe_scene() -> void:
	var state := [world.session_generation(),world.is_attached(),world.terrain_loaded(),scene._loader.entered,scene._loader.can_attach]
	if state == last_scene_state: return
	last_scene_state = state
	print("SCENE_RESTART_STATE ",state," layers=",scene._sprite_layers.size()," motion_pages=",scene._actor_motion.pages.size())

func wait_ui(predicate: Callable, label: String) -> bool:
	# The real scene owns model adoption and render-resource reconciliation.
	var deadline := Time.get_ticks_msec()+90000
	while not stopped and Time.get_ticks_msec()<deadline:
		actions.poll(); editor._process(0.02)
		if predicate.call(): return check(not editor.request_problem,label+": "+editor.message.text)
		await create_timer(0.02).timeout
	return check(false,label+" timed out; no command replay")

func open_fixture() -> void:
	var p: Dictionary = fixture.origin
	var tile := Vector3i(int(p.x)+21,int(p.y)+21,int(p.z))
	world.set_top_z(tile.z)
	scene.camera_rig.focus_on(Vector3(tile.x+0.5,tile.z+1.0,tile.y+0.5),30)
	var launcher: Button = scene._fortress_hud.navigation.Stockpiles
	for frame in 12:
		launcher.show(); scene._fortress_hud.layout(scene._fortress_hud.logical_view_size()); await process_frame
	launcher.show(); await click_control(launcher)
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"restart pointer launcher"): return
	await pointer_click(tile_screen(tile))
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"restart pointer inspect"): return

func pointer_areas() -> void:
	step = "scene restart setup"
	process_frame.connect(observe_scene)
	await open_fixture()
	if stopped: return
	if not await wait_ui(func(): return settled() and not editor.selected.is_empty(),"fixture stockpile"): return
	if not check(int(editor.selected.id) == int(fixture.pile),"restart fixture identity mismatch"): return
	var old_epoch := int(world.poll_session().get("fortress_epoch",0))
	actions.session_changed.connect(func(): invalidations += 1)
	await native("guard_before")
	await click_control(editor.stockpile_view.controls.repaint)
	var p: Dictionary = fixture.origin
	var extra := Vector3i(int(p.x)+23,int(p.y)+21,int(p.z))
	await pointer_click(tile_screen(extra))
	if not check(editor.paint_state.cells != editor.paint_state.original,"restart has no local draft"): return
	await capture("restart_draft")
	await native("guard_after")
	handshake += 1
	write_json("request-%d.json" % handshake,{"op":"reload"})
	var file := FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake)); file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt") == OK,"restart handshake failed"): return
	step = "controller producer replacement"
	var deadline := Time.get_ticks_msec()+690000
	var ack: Dictionary = {}
	while ack.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll_session(); actions.poll(0.02); editor._process(0.02)
		for state in ["failed","incomplete","ack"]:
			var path := directory+"/%s-%d" % [state,handshake]
			if not FileAccess.file_exists(path): continue
			var reply: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if state == "failed": check(false,"restart: "+str(reply.reason)); return
			if state == "incomplete": incomplete("restart: "+str(reply.reason),true); return
			ack = reply
		await create_timer(0.02).timeout
	if not check(not ack.is_empty(),"restart timed out; no intent replay"): return
	var epoch := int(str(ack.epoch))
	if not check(epoch != old_epoch and (epoch >> 32) == int(ack.pid),"replacement epoch identity invalid"): return
	deadline = Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll_session(); actions.poll(0.02); editor._process(0.02)
		if actions._epoch == epoch and actions._active == 0 and actions._queue.is_empty(): break
		await create_timer(0.02).timeout
	if not check(actions._epoch == epoch and actions._active == 0 and actions._queue.is_empty(),"replacement service not ready"): return
	if not check(invalidations > 0 and not editor.available and editor.selected.is_empty()
		and editor.paint_state.cells.is_empty() and editor.settings_state.pending.is_empty()
		and editor.request_ticket == 0 and editor.zone_types.is_empty() and editor.zone_draft.is_empty()
		and editor.zone_picker.item_count == 0 and editor.zone_menu.catalog.is_empty(),"old controller identity, catalog or draft survived restart"): return
	if not check(not editor.panel.visible and not editor.paint_view.tools.visible,"scene retained an old panel or paint toolbar"): return
	await capture("restart_retired")
	# Replacement must remain idle until explicit reopening; no old settings poll.
	var after_claim := int(actions._next_ticket)
	for frame in 30:
		actions.poll(0.02); editor._process(0.02); await create_timer(0.02).timeout
	if not check(int(actions._next_ticket) == after_claim,"old controller issued a fresh request after restart"): return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	await open_fixture()
	if stopped: return
	if not check(int(editor.selected.id) == int(fixture.pile) and int(editor.selected.revision)>0,"fresh area lacks authoritative identity"): return
	await click_control(editor.stockpile_view.controls.links_only)
	if not await wait_ui(settled,"fresh edit after restart"): return
	await native("snapshot",{"id":int(fixture.pile),"expected":{"links_only":false}})
	await capture("restart_reopened")
	await native("final")
	process_frame.disconnect(observe_scene)
	if not stopped: print("AREAS_SCENE_RESTART_PASS old_epoch=",old_epoch," new_epoch=",epoch)
