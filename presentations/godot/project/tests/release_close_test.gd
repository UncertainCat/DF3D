extends SceneTree
class Source extends RefCounted:
	var sent := 0
	func save_fortress(_back: bool, _name: String):
		sent += 1
		return 42
func _initialize(): call_deferred("run")
func run():
	# Closing must not submit/replay a save, including while a writer is pending
	# or its outcome is unknown. The external simulation owns its own lifetime.
	for state in [{"phase":1},{"phase":3,"can_save_return":true},
			{"phase":6,"request_seq":42,"request_status":1},
			{"phase":4,"request_seq":42,"request_status":4}]:
		var controller = preload("res://scripts/release_close.gd").new()
		var source=Source.new()
		controller.world=source
		root.add_child(controller)
		var closes := []
		controller.close_requested.connect(func(): closes.append(true))
		controller.update_session(state)
		assert(closes.is_empty(),"Session changes do not request viewer exit")
		controller._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		controller._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		assert(closes.size()==1 and source.sent==0,"Viewer exit is idempotent and sends no save")
		controller.queue_free()
		await process_frame
	print("RELEASE_CLOSE_PASS")
	quit()
