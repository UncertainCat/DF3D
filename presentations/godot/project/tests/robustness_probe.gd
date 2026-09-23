extends "res://tests/interaction_test.gd"
# Adversarial QA observations, not a passing correctness regression suite.
# Runs production handlers with fake game state, never attaches to live DF.
func run():
	var fake := FakeWorld.new()
	fake.live = true
	var controller := TestController.new()
	controller.world = fake
	root.add_child(controller)
	controller.set_process(false)
	controller.select_tool(1)
	mouse(controller, Vector2(200,300), true)
	controller.set_play_enabled(false)
	var retained: bool = controller._dragging
	# Release occurs while processing/input delivery is disabled. On resume,
	# an unrelated mouse motion must not revive the interrupted rectangle.
	controller.set_play_enabled(true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(800,700)
	controller._unhandled_input(motion)
	print("QA_PROBE ", JSON.stringify({"case":"disable_mid_drag", "retained_drag":retained,"resumed_preview":str(controller._preview),"bug":retained and controller._preview.size == Vector2i(7,5)}))
	controller.cancel_selection()
	controller.free()
	var loader = preload("res://scripts/fort_loader.gd").new()
	root.add_child(loader)
	loader.update_session({"phase":1,"request_seq":41,"request_action":0,"request_status":3,"message":"Load rejected"}, false)
	# A manual native load creates a fresh valid world but does not replace this
	# client's durable rejected receipt. SessionClient overlays that old receipt.
	loader.update_session({"phase":3,"fortress_valid":true,"fortress_epoch":999,"request_seq":41,"request_action":0,"request_status":3,"message":"Load rejected"}, true)
	print("QA_PROBE ",JSON.stringify({"case":"manual_load_after_rejection","can_attach":loader.can_attach,"entered":loader.entered,"bug":not loader.can_attach}))
	loader.free()
	await process_frame
	print("ROBUSTNESS_PROBE_COMPLETE")
	quit()
