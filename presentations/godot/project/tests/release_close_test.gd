extends SceneTree
class Source extends RefCounted:
	var sent := 0
	func save_fortress(back: bool, name: String):
		assert(back and name.is_empty())
		sent += 1
		return 42
	func last_error(): return "test"
func _initialize(): call_deferred("run")
func run():
	var controller = preload("res://scripts/release_close.gd").new()
	controller.world = Source.new()
	root.add_child(controller)
	var closes := []
	controller.close_requested.connect(func(): closes.append(true))
	controller.update_session({"phase":3,"can_save_return":true})
	controller.save_and_close()
	assert(controller.pending == 42 and closes.is_empty())
	controller.update_session({"phase":6,"request_seq":42,"request_status":1})
	assert(closes.is_empty() and controller.leave.disabled)
	controller.update_session({"phase":1,"request_seq":99,"request_status":2})
	assert(closes.is_empty(), "Unrelated completion cannot close the viewer")
	controller.update_session({"phase":3,"request_seq":42,"request_status":3,"message":"rejected","can_save_return":true})
	assert(closes.is_empty() and controller.pending == 0 and not controller.leave.disabled)
	controller.save_and_close()
	controller.update_session({"phase":3,"request_seq":42,"request_status":2})
	assert(closes.is_empty(), "Receipt alone does not establish return to menu")
	controller.update_session({"phase":1,"request_seq":42,"request_status":2})
	assert(closes.size() == 1)
	controller.update_session({"phase":3,"can_save_return":true})
	controller.save_and_close()
	controller.update_session({"phase":4})
	assert(controller.pending == 0 and not controller.leave.disabled and controller.dialog.get_ok_button().disabled, "host loss releases close dialog without assuming save completion")
	assert(closes.size() == 1)
	controller.update_session({"phase":3,"can_save_return":true})
	controller.save_and_close()
	controller.requested_at = Time.get_ticks_msec() - 120001
	controller.update_session({"phase":6,"request_seq":42,"request_status":1})
	assert(controller.pending == 42 and not controller.leave.disabled and closes.size() == 1, "timeout allows explicit viewer exit without pretending save succeeded")
	controller.dialog.custom_action.emit("leave")
	assert(closes.size() == 2 and controller.world.sent == 4, "explicit exit does not replay save")
	controller.queue_free()
	await process_frame
	print("RELEASE_CLOSE_PASS")
	quit()
