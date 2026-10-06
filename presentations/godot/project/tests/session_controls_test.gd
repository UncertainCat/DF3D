extends SceneTree
const Controls = preload("res://scripts/session_controls.gd")
const Loader = preload("res://scripts/fort_loader.gd")
class FakeWorld:
	extends RefCounted
	var requests: Array = []
	func save_fortress(return_to_menu: bool, _name: String) -> int:
		requests.append(return_to_menu)
		return 42
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(Controls.calendar(105, 0) == "1 Granite, 105", "year start")
	check(Controls.calendar(105, 33599) == "28 Granite, 105", "last instant of month")
	check(Controls.calendar(105, 33600) == "1 Slate, 105", "next month")
	check(Controls.calendar(105, 403199) == "28 Obsidian, 105", "year end")
	var controls := Controls.new()
	controls.world = FakeWorld.new()
	root.add_child(controls)
	var s := {"phase":3,"fortress_valid":true,"paused":true,"year":105,"year_tick":0,"fort_name":"Testfort","can_save":true,"can_save_return":true}
	controls.update_session(s, true)
	check(controls.status.text.contains("Paused") and not controls.save.disabled, "actual paused status and availability")
	controls.save.pressed.emit()
	controls.request_save(false)
	check(controls.world.requests == [false] and controls.blocks_commands(), "save once and immediately block commands")
	s.merge({"phase":6,"request_seq":42,"request_status":1,"request_action":1,"message":"Saving fortress"}, true)
	controls.update_session(s, true)
	check(controls.save.disabled and controls.save_return.disabled, "saving disables duplicate actions")
	var loader := Loader.new()
	root.add_child(loader)
	loader.update_session(s, true)
	check(loader.entered and loader.can_attach, "save preserves loaded map")
	s.merge({"phase":3,"request_status":3,"message":"Save needs attention"}, true)
	controls.update_session(s, true)
	loader.update_session(s, true)
	check(not controls.blocks_commands() and loader.entered, "save rejection does not unload fortress")
	check(controls.feedback.text == "Save needs attention", "rejection is visible")
	s.paused = false
	controls.update_session(s, true)
	check(controls.status.text.contains("Running"), "native resume updates authoritative state")
	s.merge({"phase":7,"request_seq":0,"request_status":0,"can_save":false,"can_save_return":false},true)
	controls.update_session(s,true)
	check(controls.blocks_commands() and controls.save.disabled and controls.save_return.disabled, "Another client's native unload blocks management and save input")
	controls.update_session({"phase":4}, false)
	check(not controls.visible and controls.save.disabled, "disconnect clears ability to save")
	loader.free()
	controls.free()
	print("SESSION_CONTROLS_TEST failures=", failures)
	quit(1 if failures else 0)
