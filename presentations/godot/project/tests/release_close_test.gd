extends SceneTree
class Source extends RefCounted:
	var assets
	func ui_texture(key, index=0): return assets.ui_texture(key,index)
	func ui_font_path(): return assets.ui_font_path()
	var sent := 0
	func save_fortress(_back: bool, _name: String):
		sent += 1
		return 42
func _initialize(): call_deferred("run")
func run():
	var assets := Df3dWorld.new()
	root.add_child(assets)
	assert(assets.load_assets(OS.get_environment("DF3D_DF_PATH")))
	for state in [{"phase":1},{"phase":3,"can_save_return":true},
			{"phase":6,"request_seq":42,"request_status":1},
			{"phase":4,"request_seq":42,"request_status":4}]:
		var controller = preload("res://scripts/release_close.gd").new()
		var source=Source.new()
		source.assets=assets
		controller.world=source
		root.add_child(controller)
		var closes := []
		controller.close_requested.connect(func(): closes.append(true))
		controller.update_session(state)
		controller._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		assert(closes.is_empty() and controller.confirmation.visible,"Window close asks before discarding progress")
		var click := InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(440,90)
		controller.prompt._gui_input(click)
		assert(not controller.confirmation.visible,"Native Cancel closes the exit overlay")
		assert(closes.is_empty(),"Cancel leaves the session running")
		controller.request_close()
		if state.get("phase",0)==6:
			click.position=Vector2(40,90)
			controller.prompt._gui_input(click)
			assert(closes.is_empty() and not controller.prompt.accepts_confirmation(),"Cannot terminate during a pending save")
			controller.update_session({"phase":3,"request_status":2})
		click.position=Vector2(40,90)
		controller.prompt._gui_input(click)
		controller.prompt._gui_input(click)
		assert(closes.size()==1 and source.sent==0,"Explicit exit is idempotent and sends no implicit save")
		controller.queue_free()
		await process_frame
	assets.free()
	print("RELEASE_CLOSE_PASS")
	quit()
