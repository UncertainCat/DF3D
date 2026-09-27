extends SceneTree
const Construction = preload("res://scripts/construction.gd")


class FakeWorld:
	extends Node
	var calls: Array = []
	var result: Dictionary = {}
	var live := true

	func is_live():
		return live

	func reconnect_management():
		pass

	func poll_management():
		var state = result.duplicate(true)
		state["revision"] = 1
		return state

	func management_request(_domain, r):
		calls.append(r.duplicate(true))
		return calls.size()

	func last_error():
		return "test rejection"

	func get_top_z():
		return 1

	func floor_height():
		return 0.1


class FakeInteraction:
	extends Node
	var shell_blocked := false
	var shell_enabled := false
	var construction_active := false
	var panel := PanelContainer.new()

	func _init():
		panel.add_child(VBoxContainer.new())
		add_child(panel)

	func set_play_enabled(value: bool):
		panel.visible = value

	func cancel_selection():
		pass


var failures := 0


func check(ok: bool, text: String):
	if not ok:
		failures += 1
		push_error(text)


func _initialize():
	call_deferred("run")


func run():
	var w := FakeWorld.new()
	root.add_child(w)
	var i := FakeInteraction.new()
	root.add_child(i)
	var c := Construction.new()
	c.world = w
	c.interaction = i
	c.camera = Camera3D.new()
	root.add_child(c.camera)
	var service := preload("res://scripts/semantic_action_service.gd").new()
	service.configure(w)
	root.add_child(service)
	service.set_process(false)
	c.action_service = service
	c.ui_host = preload("res://scripts/ui_host.gd").new()
	c.ui_host.interaction = i
	root.add_child(c.ui_host)
	root.add_child(c)
	c.ui_host.register(c)
	c.set_process(false)
	c.open_panel()
	service.poll()
	check(i.construction_active and w.calls.back().action == 0, "opening claims read-only catalog")
	w.result = {
		"world_epoch": 5,
		"request_seq": w.calls.size(),
		"status": 2,
		"action": 0,
		"catalog":
		[
			{
				"key": "Chair",
				"name": "Chair",
				"width": 1,
				"height": 1,
				"supported": true,
				"reason": ""
			}
		]
	}
	service.poll()
	check(c.catalog.size() == 1, "catalog loaded")
	c.origin = Vector3i(2, 3, 1)
	c.preview()
	service.poll()
	check(
		w.calls.back().action == 1 and not w.calls.back().has("items"),
		"preview has no material reservation"
	)
	w.result = {
		"world_epoch": 5,
		"request_seq": w.calls.size(),
		"status": 2,
		"action": 1,
		"placement_valid": true,
		"required": 1,
		"next_cursor": 512,
		"inputs": [{"id": 7, "description": "granite chair", "quantity": 1}]
	}
	service.poll()
	check(
		not c.place_button.disabled and not c.next_button.disabled,
		"native eligibility enables placement and paging"
	)
	c.place()
	service.poll()
	check(
		w.calls.back().items == [7] and w.calls.back().origin == Vector3i(2, 3, 1),
		"place carries selected real item and checked origin"
	)
	w.result = {
		"world_epoch": 5,
		"request_seq": w.calls.size(),
		"status": 2,
		"action": 2,
		"building_id": 42,
		"build_stage": 0,
		"max_stage": 3,
		"jobs": 1
	}
	c.refresh_time = 100
	service.poll()
	check(
		c.placed_sites.has(42) and c.inspected_id == 42, "native job tracked by building identity"
	)
	c.origin = Vector3i(3, 3, 1)
	c.preview()
	service.poll()
	c.cancel_site()
	w.result = {
		"world_epoch": 5,
		"request_seq": w.calls.size(),
		"status": 2,
		"action": 1,
		"placement_valid": true,
		"inputs": [{"id": 7, "description": "chair", "quantity": 1}]
	}
	service.poll()
	check(not c.ready_to_place, "cancelled preview cannot rearm placement")
	c.close_panel()
	check(not i.construction_active, "close restores map controls")
	c.open_panel()
	service.poll()
	var abandoned := w.calls.size()
	c.close_panel()
	c.open_panel()
	service.poll()
	check(c.request_ticket > abandoned and c.panel.visible, "reopen immediately queues a new draft while old request drains")
	w.result = {"world_epoch":5,"request_seq":abandoned,"status":2,"action":0,"catalog":c.catalog}
	service.poll()
	await process_frame
	check(
		c.request_ticket > abandoned and w.calls.back().action == 0,
		"service consumes closed receipt then dispatches the reopened query"
	)
	# The current catalog request completes before the next mutation starts.
	w.result = {"world_epoch":5,"revision":8,"request_seq":w.calls.size(),"status":2,"action":0,"catalog":c.catalog}
	service.poll()
	c.send({"action":4,"building_id":42})
	service.poll()
	var detached_mutation: int = c.request_ticket
	c.close_panel()
	w.result = {"world_epoch":5,"revision":9,"request_seq":w.calls.size(),"status":2,"action":4,"message":"Building removed"}
	service.poll()
	c.open_panel()
	service.poll()
	check(c.message.text.contains("Building removed") and service.last_detached_mutation("construction").ticket==detached_mutation,"Reopening surfaces detached mutation result")
	w.result = {"world_epoch":5,"revision":10,"request_seq":w.calls.size(),"status":2,"action":0,"catalog":c.catalog}
	service.poll()
	check(c.message.text.contains("Building removed"),"Catalog reply preserves prior mutation outcome")
	c.send({"action":4,"building_id":43})
	service.poll()
	service.poll(service.timeout_seconds+1.0)
	check(c.request_ticket==0 and c.message.text.contains("unknown"),"Open mutation timeout consumes view ticket and reports uncertainty")
	c.close_panel()
	w.result = {"world_epoch":5,"revision":11,"request_seq":w.calls.size(),"status":2,"action":4,"message":"Late removal confirmed"}
	service.poll()
	c.open_panel()
	service.poll()
	check(c.message.text.contains("Late removal confirmed") and not c.message.text.contains("outcome unknown"),"Timeout while open then close/late reply/reopen exposes definitive result")
	w.result = {"world_epoch":5,"revision":12,"request_seq":w.calls.size(),"status":2,"action":0,"catalog":c.catalog}
	service.poll()
	var sent_before: int = w.calls.size()
	c.ui_host.set_overlay_blocked(true)
	var click := InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	c._unhandled_input(click)
	check(w.calls.size()==sent_before and c.request_ticket==0,"Overlay blocks construction map click before camera/picking or request")
	c.ui_host.set_overlay_blocked(false)
	c.set_play_enabled(false)
	check(not c.panel.visible and not i.construction_active, "saving and menu disable construction")
	var count := w.calls.size()
	c.open_panel()
	service.poll()
	check(w.calls.size() == count, "disabled gameplay cannot reopen construction")
	print("CONSTRUCTION_TEST ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
