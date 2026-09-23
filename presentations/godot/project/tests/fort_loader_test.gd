extends SceneTree
const Loader = preload("res://scripts/fort_loader.gd")
class FakeWorld:
	extends RefCounted
	var requests: Array = []
	func load_fortress(id: String) -> int:
		requests.append(id)
		return 41
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var loader := Loader.new()
	loader.world = FakeWorld.new()
	root.add_child(loader)
	loader.update_session({"phase": 4}, false)
	check(loader.visible and loader.load_button.disabled, "missing producer is visible and cannot load")
	var saves := [{"id":"install/save/region1", "fort":"Oakhome", "world":"The Amber Realm", "year":105}, {"id":"appdata/save/region1", "fort":"Oakhome", "world":"The Amber Realm", "year":106}]
	loader.update_session({"phase":1, "saves":saves}, false)
	loader.list.item_selected.emit(1)
	check(loader.selected_id == saves[1].id and loader.detail.text.contains("appdata"), "duplicate basename retains exact identity")
	loader.load_button.pressed.emit()
	loader.request_load()
	check(loader.world.requests == [saves[1].id], "one semantic command, duplicate suppressed")
	loader.update_session({"phase":3, "request_seq":40, "request_status":2, "saves":saves}, true)
	check(not loader.entered and loader.pending_seq == 41, "unrelated success cannot finish request")
	loader.update_session({"phase":3, "request_seq":41, "request_status":2, "saves":saves}, false)
	check(loader.can_attach and not loader.entered and loader.visible, "matching success still waits for terrain")
	loader.update_session({"phase":3}, false, "live snapshot failed validation: invalid footprint")
	check(loader.message.text.contains("invalid footprint") and loader.can_attach and not loader.entered, "preparation errors are visible without interrupting synchronization retries")
	loader.update_session({"phase":3}, false)
	check(not loader.message.text.contains("invalid footprint"), "recovery clears preparation error")
	loader.update_session({"phase":3, "request_seq":41, "request_status":2, "saves":saves}, true)
	check(loader.entered and not loader.visible, "success and terrain expose play")
	loader.update_session({"phase":3, "request_seq":41, "request_status":2, "saves":saves}, false)
	check(loader.entered, "normal chunk rebuild does not reopen loader")
	loader.update_session({"phase":3, "request_seq":41, "request_status":3, "message":"Wrong save", "saves":saves}, true)
	check(not loader.entered and loader.message.text == "Wrong save", "durable rejection wins over Ready on reconnect")
	loader.update_session({"phase":3,"fortress_valid":true,"fortress_epoch":8,"request_fortress_epoch":8,"request_seq":41,"request_action":0,"request_status":3,"message":"Wrong save"}, true)
	check(not loader.can_attach, "rejection still blocks its own world")
	loader.update_session({"phase":3,"fortress_valid":true,"fortress_epoch":9,"request_fortress_epoch":8,"request_seq":41,"request_action":0,"request_status":3,"message":"Wrong save"}, false)
	check(loader.can_attach and not loader.entered and not loader.message.text.contains("Wrong save"), "new native world supersedes old failure and waits for terrain")
	loader.update_session({"phase":3,"fortress_valid":true,"fortress_epoch":9,"request_fortress_epoch":8,"request_seq":41,"request_action":0,"request_status":3}, true)
	check(loader.entered, "new native world attaches after terrain ready")
	loader.update_session({"phase":1, "request_seq":41, "request_status":3, "saves":saves}, false)
	check(not loader.load_button.disabled, "rejected request can retry from menu")
	loader.request_load()
	loader.update_session({"phase":4}, false)
	check(loader.pending_seq == 0 and loader.visible, "dead producer releases local pending state")
	loader.update_session({"phase":1, "saves":[]}, false)
	check(loader.selected_id == "" and loader.load_button.disabled, "removed save cannot be submitted")
	loader.update_session({"phase":3, "error":"Invalid session buffer"}, true)
	check(not loader.entered and loader.message.text == "Invalid session buffer", "invalid session fails visibly and cannot expose stale play")
	loader.update_session({"phase":1, "request_seq":50, "request_status":2, "request_action":2, "saved_save_id":saves[1].id, "message":"Saved", "saves":saves}, false)
	check(loader.selected_id == saves[1].id and loader.message.text == "Saved", "return selects exact saved identity")
	loader.list.item_selected.emit(0)
	loader.update_session({"phase":1, "request_seq":50, "request_status":2, "request_action":2, "saved_save_id":saves[1].id, "saves":saves}, false)
	check(loader.selected_id == saves[0].id, "repeated durable save result does not override user selection")
	loader.free()
	print("FORT_LOADER_TEST failures=", failures)
	quit(1 if failures else 0)
