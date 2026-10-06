extends "res://tests/areas_acceptance_live.gd"
# Actual bridge -> session model -> HUD labels. Native text comes from the
# protected verifier; this headless lane makes no rendered GPU parity claim.
func exercise() -> void:
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")), "Installed assets load"): return
	var rig = preload("res://scripts/orbit_camera.gd").new()
	var camera := Camera3D.new(); camera.name="Camera3D";rig.add_child(camera);root.add_child(rig)
	var interaction = preload("res://tests/fortress_hud_test.gd").Interaction.new();root.add_child(interaction)
	var hud = preload("res://scripts/fortress_hud.gd").new()
	hud.world=world;hud.interaction=interaction;hud.camera_rig=rig;root.add_child(hud)
	var observations: Array=[]
	for pair in [[14,0],[14,100],[135,100],[135,1000],[10001,10000],[10001,100000],[0,0],[10,0],[999,0],[2147483647,1000]]:
		step="native HUD count %s" % [pair]
		await native("hud_set", {"value":pair[0],"precision":pair[1]})
		if stopped: break
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-%d.json" % handshake))
		var deadline:=Time.get_ticks_msec()+10000
		var matched:=false
		while Time.get_ticks_msec()<deadline:
			world.poll()
			var session: Dictionary=world.poll_session()
			var summary: Dictionary=session.get("fortress_summary",{})
			if summary.get("bookkeeper_precision",-1)==pair[1] and JSON.parse_string(JSON.stringify(summary.get("resource_counts",[])))==expected.counts:
				if not check(session.get("paused",false),"Session remains paused"): break
				hud.update_state(true,true,session)
				matched=check(hud.resource_counts[1].text==expected.drink,"HUD Drink differs from native: "+hud.resource_counts[1].text+" versus "+str(expected.drink))
				for i in [0,2,3,4,5,6]: check(hud.resource_counts[i].text=="None","Zero resource uses native None")
				observations.append({"native":expected,"session":summary,"drink":hud.resource_counts[1].text})
				break
			await create_timer(0.02).timeout
		if not check(matched,"Count/precision did not reach HUD through session transport"): break
	write_json("hud-comparison.json",observations)
	hud.free();interaction.free();rig.free()
	if not stopped: await native("hud_restore")
	if not stopped: print("HUD_RESOURCE_LIVE_PASS")
