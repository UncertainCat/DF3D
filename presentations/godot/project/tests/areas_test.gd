extends SceneTree
const Controller = preload("res://scripts/areas.gd")
var failures := 0


class FakeWorld:
	extends RefCounted
	var calls: Array = []
	var seq := 0
	var live := true
	var zone_overlays := false

	func set_zone_overlays_visible(value: bool):
		zone_overlays = value
	var state: Dictionary = {"world_epoch": 42, "revision": 1, "status": 0}

	func is_live():
		return live

	func reconnect_management():
		pass

	func poll_management():
		return state

	func get_top_z():
		return 2

	func map_size():
		return Vector3(48, 12, 48)

	func last_error():
		return "test unavailable"

	func management_request(_domain, data):
		return area_request(data)

	func area_request(data):
		calls.append(data.duplicate(true))
		seq += 1
		return seq


class FakeInteraction:
	extends Node3D
	var panel := PanelContainer.new()
	var shell_blocked := false
	var shell_enabled := false
	var construction_active := false
	var audio: Node

	func _ready():
		add_child(panel)
		panel.add_child(VBoxContainer.new())

	func set_play_enabled(value: bool):
		panel.visible = value

	func cancel_selection():
		pass


func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)


func _initialize():
	call_deferred("run")


func run():
	var w := FakeWorld.new()
	var interaction := FakeInteraction.new()
	root.add_child(interaction)
	var c := Controller.new()
	c.world = w
	c.interaction = interaction
	var service := preload("res://scripts/semantic_action_service.gd").new()
	service.configure(w)
	root.add_child(service)
	service.set_process(false)
	c.action_service = service
	c.ui_host = preload("res://scripts/ui_host.gd").new()
	c.ui_host.interaction = interaction
	root.add_child(c.ui_host)
	root.add_child(c)
	c.ui_host.register(c)
	c.set_process(false)
	c.open_panel()
	service.poll()
	check(not w.zone_overlays, "stockpile panel keeps zone overlays hidden")
	check(w.calls[-1].action == 0, "fresh connection claims read-only catalog")
	w.state = {"revision": 2, "world_epoch": 42, "request_seq": w.seq, "action": 0, "status": 2}
	service.poll()
	check(w.calls[-1].action == 7, "area catalog follows ownership claim")
	w.state = {
		"revision": 3,
		"world_epoch": 42,
		"request_seq": w.seq,
		"action": 7,
		"status": 2,
		"area_choices": [{"id": 2, "name": "Bedroom"}]
	}
	service.poll()
	check(c.available and c.zone_picker.item_count == 1, "native zone choices accepted")
	var pile: Dictionary = {
		"id": 31,
		"kind": 0,
		"name": "Custom pile",
		"origin": Vector3i(3, 4, 2),
		"width": 50,
		"height": 50,
		"extents": PackedByteArray(),
		"categories": 8202,
		"barrels": 1500,
		"bins": 1200,
		"wheelbarrows": 4,
		"links_only": true,
		"active": true,
		"owner_id": -1,
		"owner_name": "",
		"owner_allowed": false,
		"gives": [32],
		"takes": [33]
	}
	c.use_area(pile)
	check(
		(
			(
				c
				. footprint_edges(
					{
						"width": 3,
						"height": 3,
						"extents": PackedByteArray([1, 1, 1, 1, 0, 1, 1, 1, 1])
					}
				)
				. size()
			)
			== 16
		),
		"observed footprint outlines include holes and exclude internal edges"
	)
	var unchanged: Dictionary = c.edit_request()
	check(
		(
			unchanged.changed_categories == 0
			and not unchanged.has("barrels")
			and not unchanged.has("bins")
		),
		"large existing limits are not clamped into unrelated edits"
	)
	c.storage.bins.value = 1201
	var edit: Dictionary = c.edit_request()
	check(
		(
			edit.bins == 1201
			and edit.changed_categories == 0
			and not edit.has("barrels")
			and not edit.has("wheelbarrows")
		),
		"bins-only edit preserves unrelated values"
	)
	c.categories[13].button_pressed = false
	edit = c.edit_request()
	check(
		edit.changed_categories == 8192, "only toggled category is changed; fine filters never sent"
	)
	c.apply_edits()
	service.poll()
	var count := w.calls.size()
	c.remove_area()
	check(w.calls.size() == count, "one pending operation prevents duplicate mutation")
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.choices = [{"id": 32, "name": "Target"}]
	c.candidate_picker.add_item("Target")
	c.link(true, false)
	service.poll()
	check(
		w.calls[-1].id == 31 and w.calls[-1].link_id == 32 and w.calls[-1].give,
		"link keeps both selected identities"
	)
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.search.text = "Later citizen"
	c.search_candidates(1500)
	service.poll()
	check(
		w.calls[-1].cursor == 1500 and w.calls[-1].query == "Later citizen",
		"search and paging retain native cursor"
	)
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.new_area()
	c.kind_picker.select(1)
	c.new_area()
	check(w.zone_overlays, "zone editing shows original zone boundaries")
	c.origin = Vector3i(5, 6, 2)
	c.rectangle = Rect2i(5, 6, 3, 2)
	c.create_area()
	service.poll()
	check(
		(
			w.calls[-1].action == 10
			and w.calls[-1].zone_type == 2
			and w.calls[-1].width == 3
			and w.calls[-1].active == 1
		),
		"new zone typed rectangle and active state"
	)
	w.state = {"world_epoch": 99, "revision": 9, "status": 0}
	service.poll()
	check(
		c.request_ticket == 0 and not c.available and c.selected.is_empty(),
		"world change clears pending edit and selected identities"
	)
	c.ui_host.set_play_enabled(false)
	check(not w.zone_overlays, "save/menu hides zone overlays")
	check(
		not c.panel.visible and not interaction.panel.visible,
		"save/menu closes management and keeps gameplay hidden"
	)
	count = w.calls.size()
	c.send(
		{
			"action": 10,
			"kind": 0,
			"origin": Vector3i(1, 1, 1),
			"width": 1,
			"height": 1,
			"categories": 1
		}
	)
	check(w.calls.size() == count, "session gate blocks stale direct controller callbacks")
	c.ui_host.set_play_enabled(true)
	c.ui_host.activate(c)
	c.panel.show()
	c.send({"action": 10})
	service.poll()
	var closed_ticket: int = c.request_ticket
	c.close_panel()
	w.state = {"world_epoch":99,"revision":10,"request_seq":w.seq,"status":2,"action":10}
	count = w.calls.size()
	service.poll()
	check(c.request_ticket == 0 and not c.panel.visible and w.calls.size() == count and service.result(closed_ticket).status == 2, "service retains closed area mutation result without reopening or follow-up")
	c.open_panel()
	service.poll()
	check(c.message.text.contains("Previous request"),"Reopening areas exposes detached mutation receipt")
	c.dragging=true;c.drag_start=Vector3i(1,1,2)
	c.ui_host.set_overlay_blocked(true)
	check(not c.dragging,"Overlay cancels area drag without discarding request ticket")
	var before_overlay: int = w.calls.size()
	var release := InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	c._unhandled_input(release)
	check(w.calls.size()==before_overlay,"Overlay release cannot complete a map drag or submit an area")
	c.ui_host.set_overlay_blocked(false)
	c.free()
	interaction.free()
	print(
		"area controller tests: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures]
	)
	quit(failures)
