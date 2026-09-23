extends SceneTree
const Selection = preload("res://scripts/interaction_state.gd")
const Controller = preload("res://scripts/interaction.gd")
var failures := 0

class FakeAudio extends Node:
	var cues: Array = []
	func cue(kind: String): cues.append(kind)

class FakeWorld extends RefCounted:
	var generation := 0
	func session_generation(): return generation
	var live := false
	var top := 5
	var seq := 100
	var calls: Array = []
	var results: Array = []
	var items: Array = [{"id": 7, "name": "Bar", "stack": 5, "forbidden": false, "dump": false}, {"id": 9, "name": "Weapon", "stack": 1, "forbidden": true, "dump": false}]
	func get_top_z(): return top
	func map_size(): return Vector3(48, 12, 48)
	func terrain_loaded(): return true
	func is_live(): return live
	func is_attached(): return true
	func item_positions(): return PackedVector3Array([Vector3(2.5, 5.7, 3.5), Vector3(2.5, 5.7, 3.5), Vector3(2.5, 6.7, 3.5)])
	func item_sprite_sizes(): return PackedVector2Array([Vector2.ONE, Vector2.ONE, Vector2.ONE])
	var thickness := 0.12
	func item_thicknesses(): return PackedFloat32Array([thickness, thickness, thickness])
	func item_physical_layout(): return {"positions":item_positions(),"thicknesses":item_thicknesses()}
	var cutout := false
	var cached_mesh: ArrayMesh
	func item_sprite_slots(): return PackedInt32Array([0,0,0]) if cutout else PackedInt32Array([-1,-1,-1])
	func sprite_cutout_mesh(_slot, _region):
		if cached_mesh != null: return cached_mesh
		var vertices := PackedVector3Array()
		var box := BoxMesh.new()
		box.size = Vector3(1.0/3.0, 0.12, 1.0/3.0)
		for z in 3:
			for x in 3:
				if x == 1 and z == 1: continue
				for v in box.get_faces(): vertices.append(v + Vector3((x-1)/3.0,0.06,(z-1)/3.0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		cached_mesh = ArrayMesh.new()
		cached_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return cached_mesh
	func item_sprite_regions(): return PackedColorArray([Color(0,0,1,1),Color(0,0,1,1),Color(0,0,1,1)])
	func item_ground_flags(): return PackedByteArray([0, 0, 0])
	func item_ids(): return PackedInt64Array([9, 7, 12])
	func item_tile(id): return Vector3i(2, 3, 6 if id == 12 else 5)
	func selection_height(_tile): return 1.0
	var terrain_version := 0
	var marker_queries := 0
	var markers: Array = []
	func terrain_revision(): return terrain_version
	func designation_tiles(_z):
		marker_queries += 1
		return markers.duplicate(true)
	var buildings: Array = [{"id": 40, "name": "Door", "forbidden": false, "can_forbid": true, "complete": true}, {"id": 41, "name": "Stockpile", "forbidden": false, "can_forbid": false, "complete": true}]
	func buildings_at_tile(tile): return buildings if tile.z == top else []
	func set_building_flags(id, forbidden):
		calls.append(["building", id, forbidden])
		seq += 1
		return seq
	func designate_chop(rect, z, enable, priority=4, marker=false, max_z=-1):
		calls.append(["chop", rect, z, enable, priority, marker, max_z])
		seq += 1
		return seq
	func designate_gather(rect, z, enable, priority=4, marker=false, max_z=-1):
		calls.append(["gather", rect, z, enable, priority, marker, max_z])
		seq += 1
		return seq
	func drain_command_results():
		var out := results
		results = []
		return out
	func items_at_tile(tile): return items if tile.z == top else []
	func last_error(): return "test send failure"
	func designate_dig(rect, z, kind, priority=4, marker=false, mode=0, max_z=-1):
		calls.append(["dig", rect, z, kind, priority, marker, mode, max_z])
		seq += 1
		return seq
	func designate_smooth(rect, z, kind, priority=4, marker=false, max_z=-1):
		calls.append(["smooth", rect, z, kind, priority, marker, max_z])
		seq += 1
		return seq
	func designate_stairs(rect,z1,z2,priority=4,marker=false):
		calls.append(["stairs",rect,z1,z2,priority,marker])
		seq += 1
		return seq
	var track_preview_queries := 0
	func preview_track(_rect,_z,_east=false,_south=false,_end_z=-1):
		track_preview_queries += 1
		return []
	func designate_track(rect,z,east=false,south=false,priority=4,marker=false,end_z=-1):
		calls.append(["track",rect,z,east,south,priority,marker,end_z])
		seq += 1
		return seq
	func set_item_flags(id, forbidden, dump, melt):
		calls.append(["item", id, forbidden, dump, melt])
		seq += 1
		return seq
	func send_set_pause(paused):
		calls.append(["pause", paused])
		seq += 1
		return seq

# Input-handler tests isolate screen-to-tile from perspective, tested below.
class TestController extends Controller:
	func _pick(screen: Vector2) -> Vector3i:
		return Vector3i(int(screen.x / 100), int(screen.y / 100), world.top)

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func mouse(controller, pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	controller._unhandled_input(event)

func corners(controller, first: Vector2, second: Vector2) -> void:
	mouse(controller, first, true)
	mouse(controller, second, false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Df3dWorld.DIG_REMOVE == 6 and Df3dWorld.SMOOTH_REMOVE == 2, "erase binding preserves cancellation semantics")
	check(Selection.rectangle(Vector2i(8, 7), Vector2i(2, 3), Vector2i(48, 48)) == Rect2i(2, 3, 7, 5), "inclusive reversed rectangle")
	check(Selection.rectangle(Vector2i(-3, 60), Vector2i(100, -5), Vector2i(48, 48)) == Rect2i(0, 0, 48, 48), "clamp rectangle")
	check(Selection.rectangle(Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO) == Rect2i(), "empty map")
	var size := Vector3(48, 12, 48)
	check(Selection.project_tile(Vector3(4.3, 20, 8.8), Vector3.DOWN, 5, size, 1) == Vector3i(4, 8, 5), "DF axis conversion")
	for z in [-1, 12]:
		check(Selection.project_tile(Vector3(4, 20, 8), Vector3.DOWN, z, size, 1).z == -1, "reject z boundary")
	check(Selection.project_tile(Vector3(48, 20, 8), Vector3.DOWN, 5, size, 1).z == -1, "reject outside map")
	check(Selection.project_tile(Vector3.ZERO, Vector3.RIGHT, 5, size, 1).z == -1, "parallel ray")
	var candidates := [
		{"id": 9, "tile": Vector3i(2, 3, 5), "visible": true, "bounds": Rect2(10, 10, 20, 20), "depth": 50.0},
		{"id": 7, "tile": Vector3i(2, 3, 5), "visible": true, "bounds": Rect2(10, 10, 20, 20), "depth": 50.0},
		{"id": 1, "tile": Vector3i(2, 3, 5), "visible": false, "bounds": Rect2(10, 10, 20, 20), "depth": 1.0},
		{"id": 2, "tile": Vector3i(2, 3, 6), "visible": true, "bounds": Rect2(10, 10, 20, 20), "depth": 2.0}]
	check(Selection.choose_item(candidates, Vector2(20, 20), 5).id == 7, "overlap deterministic, hidden and above-slice excluded")
	check(Selection.choose_item(candidates, Vector2(40, 20), 5).is_empty(), "outside displayed bounds")
	var state = Selection.new()
	state.submitted(10, "dig")
	state.submitted(11, "smooth")
	state.receive([{"seq": 99, "status": 0, "message": "other consumer"}])
	check(state.pending.size() == 2, "unrelated result does not acknowledge")
	state.receive([{"seq": 11, "status": 1, "message": "not smoothable"}])
	check(state.pending.has(10) and not state.pending.has(11), "out of order rejection matches seq")
	check(state.history[0].contains("Rejected #11") and state.history[0].contains("not smoothable"), "result retains message")
	state.receive([{"seq": 10, "status": 0, "message": "4 tiles"}])
	check(state.pending.is_empty() and state.history[0].contains("Accepted #10"), "successful result")
	var history_size: int = state.history.size()
	state.receive([{"seq": 10, "status": 0, "message": "duplicate"}])
	check(state.history.size() == history_size and not state.history[0].contains("duplicate"), "duplicate ignored")
	state.submitted(12, "missing receipt", 100)
	state.expire(100 + Selection.RECEIPT_TIMEOUT_MS - 1)
	check(state.pending.has(12), "pending retained before receipt deadline")
	state.expire(100 + Selection.RECEIPT_TIMEOUT_MS)
	check(state.pending.is_empty() and state.history[0].contains("No confirmation"), "missed receipt releases waiting UI without claiming rejection")
	check(state.receive([{"seq":12,"status":0,"message":"late"}]).is_empty(), "expired receipt cannot acknowledge a newer request")

	var fake := FakeWorld.new()
	var controller := TestController.new()
	controller.world = fake
	root.add_child(controller)
	await process_frame
	controller.select_tool(1)
	mouse(controller,Vector2(200,300),true)
	controller._right_armed = true
	controller.set_play_enabled(false)
	check(not controller._dragging and not controller._right_armed and not controller._preview.has_area(), "disabling cancels all gesture ownership")
	mouse(controller,Vector2(800,700),false)
	controller.set_play_enabled(true)
	var interrupted_motion := InputEventMouseMotion.new()
	interrupted_motion.position = Vector2(800,700)
	controller._unhandled_input(interrupted_motion)
	check(not controller._preview.has_area() and fake.calls.is_empty(), "resume cannot revive interrupted rectangle")
	mouse(controller,Vector2(200,300),true)
	check(controller._dragging, "fresh drag works after resume")
	controller.cancel_selection()
	# Periodic polling must neither rescan a frozen map nor replace its mesh.
	controller._process(0.36)
	var marker_queries := fake.marker_queries
	var marker_mesh: Mesh = controller._lines.mesh
	for n in 8: controller._process(0.36)
	check(fake.marker_queries == marker_queries and controller._lines.mesh == marker_mesh, "paused marker polling reuses query and overlay")
	fake.terrain_version += 1
	controller._process(0.36)
	check(fake.marker_queries == marker_queries + 1 and controller._lines.mesh == marker_mesh, "terrain change rescans but unchanged markers retain geometry")
	fake.markers = [{"tile": Vector3i(2,3,5), "kind": 1, "height": 1.0}]
	fake.terrain_version += 1
	controller._process(0.36)
	check(controller._markers == fake.markers and controller._lines.mesh != marker_mesh, "paused authoritative designation change updates overlay")
	marker_mesh = null
	marker_queries = fake.marker_queries
	fake.top = 6
	fake.markers = [{"tile": Vector3i(4,3,6), "kind": 2, "height": 0.2}]
	controller._process(0.0)
	check(fake.marker_queries == marker_queries + 1 and controller._markers == fake.markers, "level switch invalidates markers even at unchanged terrain revision")
	marker_queries = fake.marker_queries
	fake.generation += 1
	fake.markers = []
	controller._process(0.0)
	check(fake.marker_queries == marker_queries + 1 and controller._markers.is_empty(), "session reset clears and rescans cached markers")
	fake.top = 5
	controller._process(0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(2.5, 12, 15)
	camera.look_at(Vector3(2.5, 5.7, 3.5))
	controller.camera = camera
	check(controller._pick_piece(camera.unproject_position(Vector3(2.5, 5.7, 3.5))).id == 7, "actual displayed quad projection picks deterministic item")
	fake.cutout = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	camera.position = Vector3(2.5,12,3.5)
	camera.look_at(Vector3(2.5,5.7,3.5), Vector3.FORWARD)
	check(controller._pick_piece(camera.unproject_position(Vector3(2.5,5.82,3.5))).is_empty(), "cutout transparent hole is not pickable")
	check(controller._pick_piece(camera.unproject_position(Vector3(2.83,5.82,3.5))).get("id",-1) == 7, "opaque ground silhouette picks depth then ID")
	camera.position = Vector3(2.5,5.76,8)
	camera.look_at(Vector3(2.5,5.76,3.5))
	check(controller._pick_piece(camera.unproject_position(Vector3(2.5,5.76,4.0))).get("id",-1) == 7, "grazing ray picks actual extrusion side")
	fake.thickness = 0.01
	camera.position.y = 5.705
	camera.look_at(Vector3(2.5,5.705,3.5))
	check(controller._pick_piece(camera.unproject_position(Vector3(2.5,5.705,4.0))).get("id",-1) == 7, "compressed cutout side remains pickable")
	fake.cutout = false
	check(controller._pick_piece(camera.unproject_position(Vector3(2.5,5.705,3.65))).get("id",-1) == 7, "compressed marker bounds and geometry match")
	fake.cached_mesh = null
	fake.thickness = 0.12
	controller.camera = null # Drop the reference before the node is freed.
	camera.free()
	controller.tool_picker.select(1)
	mouse(controller, Vector2(800,700), true)
	check(controller._dragging and controller._preview == Rect2i(8,7,1,1) and fake.calls.is_empty(), "mouse down previews a singleton without submitting")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(600,500)
	controller._unhandled_input(motion)
	check(controller._preview == Rect2i(6,5,3,3) and controller._dragging, "held pointer motion expands rectangle")
	mouse(controller, Vector2(600,500), false)
	check(controller._preview == Rect2i(6, 5, 3, 3), "handler reversed drag rectangle preview")
	check(fake.calls.is_empty(), "offline designation never sends")
	check(controller.state.history[0].contains("Offline"), "offline feedback")
	fake.live = true
	for index in range(1, 9):
		controller.tool_picker.select(index)
		corners(controller, Vector2(800,700), Vector2(600,500))
	check(fake.calls.size() == 9, "all tools, remove sends both families")
	check(fake.calls[7][0] == "dig" and fake.calls[7][3] == Df3dWorld.DIG_REMOVE, "remove dig")
	check(fake.calls[8][0] == "smooth" and fake.calls[8][3] == Df3dWorld.SMOOTH_REMOVE, "remove smooth/engrave")
	for index in range(9, 14):
		controller.tool_picker.select(index)
		corners(controller, Vector2(800,700), Vector2(600,500))
	check(fake.calls[9][3] == Df3dWorld.DIG_RAMP_UP, "ramp uses ramp semantic command")
	check(fake.calls[10][0] == "chop" and fake.calls[10][3] == true and fake.calls[11][3] == false, "chop and clear chop")
	check(fake.calls[12][0] == "gather" and fake.calls[12][3] == true and fake.calls[13][3] == false, "gather and clear gather")
	var count := fake.calls.size()
	mouse(controller, Vector2(800, 700), true)
	fake.top = 6
	mouse(controller, Vector2(600, 500), false)
	check(fake.calls.size() == count + 1 and fake.calls[-1][2] == 5 and fake.calls[-1][-1] == 6 and not controller._dragging, "release captures a volume even before process observes z change")
	count = fake.calls.size()
	mouse(controller, Vector2(800, 700), true)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	controller._unhandled_input(escape)
	mouse(controller, Vector2(600, 500), false)
	check(fake.calls.size() == count, "Escape cancels")
	controller.select_tool(1)
	mouse(controller, Vector2(800,700), true)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	controller._unhandled_input(right)
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(12,0)
	controller._input(orbit)
	right.pressed = false
	controller._unhandled_input(right)
	check(controller._preview.has_area(), "right drag preserves selection for free camera orbit")
	right.pressed = true
	controller._unhandled_input(right)
	right.pressed = false
	controller._unhandled_input(right)
	check(not controller._preview.has_area() and controller.tool_picker.selected == 1, "right click first backs out of rectangle")
	right.pressed = true
	controller._unhandled_input(right)
	right.pressed = false
	controller._unhandled_input(right)
	check(controller.tool_picker.selected == 0 and fake.calls.size() == count, "second right click leaves tool without changing orders")
	controller.select_tool(1)
	mouse(controller, Vector2(800, 700), true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = Vector2(20, 20)
	release.pressed = false
	controller._input(release)
	check(not controller._dragging, "release over UI cancels")
	# Actual viewport dispatch: control consumes world mouse clicks.
	controller.tool_picker.select(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(20, 20)
	click.pressed = true
	root.push_input(click)
	check(not controller._dragging and fake.calls.size() == count, "UI click never arms world tool")
	controller.tool_picker.select(0)
	mouse(controller, Vector2(800, 700), true)
	check(controller.item_picker.item_count == 2, "stack picker contains each distinct item")
	check(controller.item_picker.get_item_text(0).contains("\u00d75") and controller.item_picker.get_item_text(1).contains("#9"), "stack count and identity visible")
	controller.item_picker.select(1)
	controller._item_flags(1, -1)
	check(fake.calls[-1][1] == 9 and fake.calls[-1][2] == Df3dWorld.FLAG_SET, "chosen stacked item gets command")
	controller._item_flags(-1, -1, 1)
	check(fake.calls[-1] == ["item", 9, Df3dWorld.FLAG_UNCHANGED, Df3dWorld.FLAG_UNCHANGED, Df3dWorld.FLAG_SET], "melt preserves other flags")
	controller._item_flags(-1, -1, 0)
	check(fake.calls[-1][4] == Df3dWorld.FLAG_CLEAR, "cancel melt")
	check(controller.building_picker.item_count == 2 and controller.building_row.visible, "building inspector includes overlapping buildings")
	controller._building_flags(true)
	check(fake.calls[-1] == ["building", 40, Df3dWorld.FLAG_SET], "door forbid targets selected identity")
	fake.buildings[0].forbidden = true
	controller._refresh_buildings()
	check(controller.building_row.get_child(0).disabled and not controller.building_row.get_child(1).disabled, "observed forbidden state controls actions")
	controller.building_picker.select(1)
	controller._refresh_building_actions()
	check(not controller.building_row.visible, "non door/hatch never offers forbid")
	controller.building_picker.select(0)
	var before_gone := fake.calls.size()
	fake.buildings = []
	controller._building_flags(false)
	check(fake.calls.size() == before_gone, "removed building never commanded")
	fake.items.append({"id": 99, "name": "Bar", "stack": 50, "forbidden": false, "dump": false})
	mouse(controller, Vector2(800, 700), true)
	controller.item_picker.select(2)
	controller._item_flags(-1, 1)
	check(controller.item_picker.item_count == 3 and fake.calls[-1][1] == 99, "every stacked identity remains selectable and commandable")
	# selected == -1 must never address _items[-1] (the last entry) and command it.
	controller.item_picker.select(-1)
	count = fake.calls.size()
	for flags in [[1, -1, -1], [-1, 1, -1], [-1, -1, 1]]:
		controller._item_flags(flags[0], flags[1], flags[2])
	check(fake.calls.size() == count and controller._selected_item() == null and not controller._items.is_empty(), "no item selection sends no flag command")
	controller.building_picker.select(-1)
	controller._refresh_building_actions()
	controller._building_flags(true)
	check(fake.calls.size() == count and controller._selected_building() == null and not controller.building_row.visible, "no building selection sends no flag command and offers no actions")
	controller.item_picker.select(0) # The building picker is empty here (removed above).
	count = fake.calls.size()
	fake.items = []
	controller._item_flags(-1, 1)
	check(fake.calls.size() == count, "moved item never commanded")
	fake.live = false
	controller._pause(true)
	check(fake.calls.size() == count, "offline pause never sent")
	fake.live = true
	controller._pause(true)
	controller._pause(false)
	check(fake.calls[-2] == ["pause", true] and fake.calls[-1] == ["pause", false], "explicit pause/resume, no guessed toggle")
	controller._submit(0, "test")
	check(controller.state.history[0].contains("Not sent"), "send failure feedback")
	check(not controller.state.pending.is_empty(), "commands pending before session change")
	var fake_audio := FakeAudio.new()
	controller.audio = fake_audio
	controller._session = fake.generation
	var pending_seq: int = controller.state.pending.keys()[0]
	fake.results = [{"seq": pending_seq, "status": 0, "message": "ok"}, {"seq": pending_seq, "status": 0}, {"seq": 987654, "status": 0}]
	controller._process(0.0)
	check(fake_audio.cues == ["accepted"], "controller sounds only matched real result, no duplicate/unrelated cues")
	controller.audio = null
	fake_audio.free()
	# The fortress HUD hides the inspector during designation. Its old rectangle
	# must not swallow release events before _unhandled_input can submit them.
	var hidden_panel_point := controller.panel.get_global_rect().position + Vector2(20, 20)
	controller.panel.hide()
	await process_frame
	for tool in [1, 10]:
		controller.select_tool(tool)
		var before_input := fake.calls.size()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = hidden_panel_point
		press.pressed = true
		root.push_input(press)
		check(controller._dragging, "world press inside hidden inspector starts designation")
		var end_press := press.duplicate() as InputEventMouseButton
		end_press.pressed = false
		root.push_input(end_press)
		check(fake.calls.size() == before_input + 1, "full input dispatch submits %s through hidden inspector rectangle" % controller.TOOLS[tool])
		check(not controller._dragging, "submitted world drag ends normally")
	# Every gesture carries client-local options. Repeated clicks are independent.
	controller.marker_only = true
	controller.mining_mode = 2
	controller.priority.value = 2
	for tool in [1,6,10,12,16,17,18,19,20]:
		controller.select_tool(tool)
		var before := fake.calls.size()
		corners(controller, Vector2(800,700),Vector2(600,500))
		check(fake.calls.size() == before + 1 and not controller._dragging, "one gesture one semantic action %d" % tool)
		check(controller.tool_picker.selected == tool, "tool remains selected after placement")
		if tool in [6,10,12]: check(fake.calls[-1][4] == 2 and fake.calls[-1][5] == true, "priority and marker transmitted by every family")
		if tool == 1: check(fake.calls[-1].slice(4,7) == [2,true,2], "dig priority marker and mode are explicit")
	controller.select_tool(15)
	var before_stairs := fake.calls.size()
	corners(controller, Vector2(800,700),Vector2(600,500))
	check(fake.calls.size() == before_stairs, "same-level stairs rejected locally")
	mouse(controller,Vector2(800,700),true)
	var first_z := fake.top
	fake.top += 2
	controller._process(0.0)
	check(controller._dragging, "stair span survives level changes")
	mouse(controller,Vector2(600,500),false)
	check(fake.calls[-1][0] == "stairs" and fake.calls[-1][2] == first_z and fake.calls[-1][3] == fake.top, "stair span submitted atomically")
	for tool in [1,6,10,12,19,20]:
		controller.select_tool(tool)
		mouse(controller,Vector2(800,700),true)
		var upper_z := fake.top
		fake.top -= 1
		controller._process(0.0)
		check(controller._dragging, "volume survives elevation change for tool %d" % tool)
		mouse(controller,Vector2(600,500),false)
		check(fake.calls[-1][2] == fake.top and fake.calls[-1][-1] == upper_z, "descending volume normalizes endpoints")
	controller.select_tool(18)
	mouse(controller,Vector2(800,700),true)
	fake.top += 1
	controller._process(0.0)
	check(controller._dragging, "track keeps its start across elevation changes")
	var preview_queries := fake.track_preview_queries
	controller._update_preview()
	controller._update_preview()
	check(fake.track_preview_queries == preview_queries, "unchanged track gesture retains cached route")
	mouse(controller,Vector2(600,500),false)
	check(fake.calls[-1][0] == "track" and fake.calls[-1][2] == fake.top - 1 and fake.calls[-1][-1] == fake.top, "track transmits directed 3D endpoints")
	mouse(controller,Vector2(600,500),true)
	fake.top -= 1
	controller._process(0.0)
	mouse(controller,Vector2(800,700),false)
	check(fake.calls[-1][2] == fake.top + 1 and fake.calls[-1][-1] == fake.top, "descending track preserves endpoint direction")
	controller._unhandled_input(escape)
	check(controller.tool_picker.selected == 0, "Escape without a drag leaves the tool")
	controller._dragging = true
	fake.generation += 1
	controller._process(0.0)
	check(controller.state.pending.is_empty() and controller.state.history.is_empty(), "session reset retires old pending/results")
	check(not controller._dragging and controller._items.is_empty() and controller._markers.is_empty(), "session reset clears selection and markers")
	controller.free()
	fake = null

	# Real fixture -> world model -> bound query path, no assets or DF process.
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_fixed_render_tick(1000)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix")), "load demo fixture")
	var items := world.items_at_tile(Vector3i(17, 31, 5))
	check(items.size() == 1 and items[0].stack == 5, "real item stack query")
	check(world.items_at_tile(Vector3i(17, 31, 6)).is_empty(), "no above-slice items")
	check(world.items_at_tile(Vector3i(-1, 31, 5)).is_empty(), "unknown/out of bounds item tile")
	check(world.items_at_tile(Vector3i(0, 0, 0)).is_empty(), "hidden terrain selection empty")
	check(world.designation_tiles(-1).is_empty() and world.designation_tiles(12).is_empty(), "designation z bounds")
	world.poll()
	check(world.built_block_count() > 0, "old session terrain built")
	var old_generation := world.session_generation()
	world.set_fixed_render_tick(10)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")), "load interaction regression fixture")
	check(world.session_generation() > old_generation, "fixture replacement invalidates renderer session")
	world.set_top_z(1)
	world.set_window_depth(1)
	world.poll()
	check(world.get_top_z() < 3, "old level invalidated for new map")
	check(world.items_at_tile(Vector3i(17, 31, 5)).is_empty(), "old session item absent")
	items = world.items_at_tile(Vector3i(2, 3, 1))
	check(items.size() == 2 and items[0].id == 7 and items[1].id == 9, "real stack IDs sorted independent of insertion")
	check(items[0].forbidden and items[1].stack == 5, "real observed flags and stack")
	check(world.items_at_tile(Vector3i(5, 2, 1)).is_empty(), "real hidden item excluded")
	check(world.item_tile(11) == Vector3i(-1, -1, -1), "hidden piece cannot be picked")
	check(world.item_tile(12) == Vector3i(2, 3, 2), "piece query preserves level")
	var door := world.buildings_at_tile(Vector3i(8,11,1))
	check(door.size() == 1 and door[0].id == 101 and door[0].forbidden and door[0].can_forbid, "real forbidden door state")
	var hatch := world.buildings_at_tile(Vector3i(12,11,1))
	check(hatch.size() == 1 and hatch[0].id == 106 and not hatch[0].forbidden and hatch[0].can_forbid, "real hatch state")
	check(world.buildings_at_tile(Vector3i(8,11,2)).is_empty(), "building query honors z level")
	check(world.buildings_at_tile(Vector3i(5,2,1)).is_empty(), "building query excludes hidden terrain")
	var markers := world.designation_tiles(1)
	check(markers.size() == 4, "current-slice pending orders include unexplored mining cells")
	for i in 3:
		check(markers[i].kind == i + 1 and markers[i].tile.z == 1, "dig/smooth/engrave markers distinguished")
	if markers.size() == 4:
		check(markers[3].tile == Vector3i(5,2,1) and markers[3].kind == 1, "hidden mining order survives authoritative marker query")
		check(markers[3].height == 1.0, "hidden floor designation uses opaque cap height rather than revealing floor shape")
		check(markers[3].operation == 1 and world.tile_hover_info(Vector3i(5,2,1)).is_empty(), "mining marker exposes exact known operation, no hidden terrain details")
	world.poll()
	check(world.designation_tiles(1) == markers, "paused unchanged mining plans persist across subsequent polls")
	check(world.pick_tile(Vector3(2.5, 10, 3.5), Vector3.DOWN, 1) == Vector3i(2, 3, 1), "real floor ray pick")
	check(world.pick_tile(Vector3(2.5, 10, 3.5), Vector3.UP, 1).z == -1, "reject upward pick")
	check(world.pick_tile(Vector3(2.5, 10, 3.5), Vector3.DOWN, 3).z == -1, "pick z boundary")
	check(world.items_at_tile(Vector3i(5,8,1)).size() == 3, "visual cap retains every real item")
	var render_ids := world.item_ids()
	check(render_ids.count(20) == 2 and render_ids.count(21) == 2 and render_ids.count(22) == 2, "each quantity stack contributes two layers")
	check(render_ids.count(23) == 1 and render_ids.count(24) == 1 and render_ids.count(25) == 1, "separate same-kind singles each contribute a layer")
	var layout: Dictionary = world.item_physical_layout()
	var positions: PackedVector3Array = layout.positions
	var thicknesses: PackedFloat32Array = layout.thicknesses
	var previous_top := -1.0
	for i in render_ids.size():
		if world.item_tile(render_ids[i]) == Vector3i(5,8,1):
			check(positions[i].y > previous_top and thicknesses[i] > 0, "six physically separate quantity layers")
			previous_top = positions[i].y + thicknesses[i]
	var max_top := 0.0
	for i in render_ids.size():
		if world.item_tile(render_ids[i]) == Vector3i(11,8,1):
			check(thicknesses[i] < 0.12, "mixed quantity pile compressed")
			max_top = maxf(max_top, positions[i].y + thicknesses[i])
	check(max_top < 2.0, "real pile below next floor underside")
	var supported := render_ids.find(30)
	check(supported >= 0 and positions[supported].y > 1 + world.floor_height() + 0.1, "installed furniture below item pile")
	var unit_positions := world.unit_cutout_positions()
	var unit_thicknesses := world.unit_thicknesses()
	var semantic_positions := world.unit_positions()
	var unit_ids := world.unit_ids()
	check(unit_ids == PackedInt64Array([101,102,103,104,105,106,109]), "delayed-present departed unit retained; latest arrival included; latest above-slice and below-window excluded")
	check(unit_positions.size() == unit_ids.size() and unit_thicknesses.size() == unit_ids.size(), "unit depth arrays align with explicit identities")
	var frame_heights := {}
	for i in unit_ids.size(): frame_heights[unit_ids[i]] = unit_positions[i].y
	for step in 21:
		world.set_fixed_render_tick(10.0 + step * 0.1)
		world.poll()
		semantic_positions = world.unit_positions()
		unit_positions = world.unit_cutout_positions()
		unit_thicknesses = world.unit_thicknesses()
		unit_ids = world.unit_ids()
		positions = world.item_physical_layout().positions
		thicknesses = world.item_physical_layout().thicknesses
		render_ids = world.item_ids()
		var expected_ids := PackedInt64Array([101,102,103,104,105,106,109]) if step < 20 else PackedInt64Array([101,102,103,104,105,109])
		check(unit_ids == expected_ids, "unit 106 departs exactly at delayed tick 12; unrelated identities remain")
		check(unit_positions.size() == unit_ids.size() and unit_thicknesses.size() == unit_ids.size() and semantic_positions.size() == unit_ids.size(), "unit arrays remain aligned through departure")
		var index_by_id := {}
		for i in unit_ids.size():
			index_by_id[unit_ids[i]] = i
			# A semantic departure may legitimately renormalize its tile's pile.
			# Before that boundary, interpolation alone cannot alter allocation.
			if step < 20:
				check(is_equal_approx(unit_positions[i].y, frame_heights[unit_ids[i]]), "interpolated center never changes authoritative tile allocation")
			check(is_equal_approx(unit_positions[i].x, semantic_positions[i].x) and is_equal_approx(unit_positions[i].z, semantic_positions[i].z), "horizontal interpolation preserved")
			check(unit_thicknesses[i] > 0 and unit_thicknesses[i] <= 0.12001, "all physical unit layers have positive bounded thickness")
			check(unit_positions[i].y + unit_thicknesses[i] < 2.0, "combined piles below next floor underside, including after departure")
		for item_index in positions.size():
			if render_ids[item_index] in [20,21,22]:
				check(unit_positions[index_by_id[102]].y > positions[item_index].y + thicknesses[item_index], "unit 102 above every quantity layer in its authoritative tile")
			if render_ids[item_index] >= 30 and render_ids[item_index] <= 35:
				check(unit_positions[index_by_id[104]].y > positions[item_index].y + thicknesses[item_index], "unit 104 above items above installed furniture")
		check(is_equal_approx(unit_positions[index_by_id[103]].y, 1 + world.floor_height() + 0.005), "neighbouring tile does not inherit support")
		check(unit_positions[index_by_id[105]].y > unit_positions[index_by_id[102]].y + unit_thicknesses[index_by_id[102]], "same-tile units 102 and 105 stack in stable ID order")
		if index_by_id.has(106):
			check(unit_positions[index_by_id[106]].y > unit_positions[index_by_id[105]].y + unit_thicknesses[index_by_id[105]], "delayed departing unit 106 retains its top layer until departure")
		check(unit_positions[index_by_id[109]].y > unit_positions[index_by_id[104]].y + unit_thicknesses[index_by_id[104]], "new frame arrival 109 participates before delayed animation catches up")
	world.set_top_z(0)
	world.poll()
	check(world.unit_cutout_positions().size() == 1 and world.item_physical_layout().positions.is_empty(), "slice change retires old pile and reveals only lower-floor unit")
	# Release scene-owned meshes before the separate renderer's shutdown starts.
	world.queue_free()
	await process_frame
	await process_frame
	print("interaction tests: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
