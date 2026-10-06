extends RefCounted
# Local placement intent only. DF supplies footprints, recipes and material snapshots.
const FixedRecipes = preload("res://scripts/construction_fixed_recipes.gd")
const Contract = preload("res://scripts/management_contract.gd")
# Native defaults and selection rules: fixtures/construction/pressure_plate.json.
const PRESSURE_DEFAULT = {"units":false,"water":false,"magma":false,"citizens":false,"resets":true,"track":false,
	"unit_min":5000,"unit_max":200000,"water_min":1,"water_max":7,"magma_min":1,"magma_max":7,"track_min":1,"track_max":2000}
var pressure_plate: Dictionary = PRESSURE_DEFAULT.duplicate()
var definition: Dictionary = {}
var origin := Vector3i(-1, -1, -1)
var material_anchor := Vector3i(-1,-1,-1)
var track_destination := Vector3i(-1,-1,-1)
var track_path: Array[Vector3i] = []
var dimensions := Vector3i.ONE
var direction := 0
var retracting := false
var roller_speed := 50000
var track_friction := 50000
var track_dump_direction := 0
var preview_valid := false
var filters: Array = []
var valid_mask := PackedByteArray()
var pieces := PackedByteArray()
var snapshots: Dictionary = {}
var selections: Array = []
var error := ""

func clear() -> void:
	definition.clear()
	origin = Vector3i(-1, -1, -1)
	material_anchor = Vector3i(-1,-1,-1)
	track_destination = Vector3i(-1,-1,-1)
	dimensions = Vector3i.ONE
	direction = 0
	retracting = false
	roller_speed = 50000
	track_friction = 50000; track_dump_direction = 0
	pressure_plate = PRESSURE_DEFAULT.duplicate()
	invalidate()

func invalidate() -> void:
	preview_valid = false
	track_path.clear()
	filters.clear(); valid_mask.clear(); pieces.clear()
	snapshots.clear(); selections.clear(); error = ""

func choose(row: Dictionary) -> bool:
	clear()
	if not row.get("supported", false):
		error = str(row.get("reason", ""))
		return false
	definition = row.duplicate(true)
	return orient(1 if definition.get("family", "") in ["WaterWheel","AxleHorizontal"] else 0)

func orient(value: int, retract: bool = false) -> bool:
	var index := 4 if retract else value
	if definition.is_empty() or index < 0 or index > 7 or (int(definition.orientations) & (1 << index)) == 0: return false
	for footprint in definition.footprints:
		if int(footprint.direction) != index: continue
		direction = value; retracting = retract
		dimensions = Vector3i(int(footprint.width), int(footprint.height), 1)
		invalidate()
		return true
	return false

func is_magma_building() -> bool:
	return definition.get("key","") in ["Workshop:MagmaForge","Furnace:MagmaSmelter","Furnace:MagmaGlassFurnace","Furnace:MagmaKiln"]

func is_terrain_construction() -> bool:
	return definition.get("key","") in ["Construction:ReinforcedWall","Construction:Wall","Construction:Floor","Construction:Ramp","Construction:Fortification","Construction:Stairs"]

func is_connected_track() -> bool:
	return str(definition.get("key","")) == "Construction:Track"

func set_site(first: Vector3i, last: Vector3i) -> bool:
	if definition.is_empty() or first.z < 0 or last.z < 0: return false
	if is_connected_track():
		invalidate()
		if first.x < 0 or first.y < 0 or last.x < 0 or last.y < 0 or first == last: return false
		origin = first; track_destination = last; dimensions = Vector3i.ONE
		direction = 0; retracting = false
		return true
	var next_origin := first
	var next_dimensions := dimensions
	if int(definition.area_mode) == 1:
		for footprint in definition.footprints:
			if int(footprint.direction) == (4 if retracting else direction):
				next_origin.x -= int(footprint.center_x)
				next_origin.y -= int(footprint.center_y)
	else:
		next_origin = Vector3i(mini(first.x, last.x), mini(first.y, last.y), mini(first.z, last.z))
		next_dimensions = Vector3i(absi(first.x - last.x) + 1, absi(first.y - last.y) + 1, absi(first.z - last.z) + 1)
		var family := str(definition.get("family",""))
		if family in ["AxleHorizontal","Rollers"]:
			var vertical := direction != 0 if family == "AxleHorizontal" else direction % 2 == 0
			if vertical: next_dimensions.x = 1; next_origin.x = first.x
			else: next_dimensions.y = 1; next_origin.y = first.y
	if next_dimensions.x > int(definition.max_width) or next_dimensions.y > int(definition.max_height) or next_dimensions.z > int(definition.max_depth) or next_dimensions.x * next_dimensions.y * next_dimensions.z > 1024:
		invalidate(); error = "Selection exceeds the supported footprint"
		return false
	origin = next_origin; dimensions = next_dimensions; material_anchor = last
	invalidate()
	return true

func set_pressure_flag(flag: String, value: bool) -> bool:
	if flag not in ["units","water","magma","citizens","resets","track"] or pressure_plate[flag] == value: return false
	pressure_plate[flag] = value; invalidate(); return true

func choose_pressure_fluid(kind: String, value: int) -> bool:
	if kind not in ["water","magma"] or value < 0 or value > 7: return false
	var low := kind + "_min"; var high := kind + "_max"
	var before: Dictionary = pressure_plate.duplicate()
	if value < int(pressure_plate[low]): pressure_plate[low] = value
	elif value > int(pressure_plate[high]): pressure_plate[high] = value
	else: pressure_plate[low] = value; pressure_plate[high] = value
	if pressure_plate == before: return false
	invalidate(); return true

func adjust_pressure_cart(endpoint: String, step: int) -> bool:
	if endpoint not in ["min","max"] or step not in [-1,1]: return false
	var key := "track_" + endpoint
	var value := int(pressure_plate[key])
	var index: int = 0 if value == 1 else value / 50
	index = clampi(index + step,0,40)
	var next := 1 if index == 0 else index * 50
	if next == value: return false
	pressure_plate[key] = next
	if endpoint == "min": pressure_plate.track_max = maxi(int(pressure_plate.track_max),next)
	else: pressure_plate.track_min = mini(int(pressure_plate.track_min),next)
	invalidate(); return true

func choose_pressure_creature(size: int) -> bool:
	if size < 1000 or size > 200000 or size % 1000 != 0: return false
	var before: Dictionary = pressure_plate.duplicate()
	if size < int(pressure_plate.unit_min): pressure_plate.unit_min = size
	elif size > int(pressure_plate.unit_max): pressure_plate.unit_max = size + 999
	else: pressure_plate.unit_min = size; pressure_plate.unit_max = size + 999
	if pressure_plate == before: return false
	invalidate(); return true

func request(action: int) -> Dictionary:
	var intent := {"action":action, "definition":str(definition.get("key", "")), "origin":origin,
		"width":dimensions.x, "height":dimensions.y, "depth":dimensions.z,
		"direction":direction, "retracting":retracting}
	if is_terrain_construction(): intent.material_anchor = material_anchor if material_anchor.z >= 0 else origin
	if is_connected_track() and action in [Contract.ManagementAction.Preview,Contract.ManagementAction.Place,Contract.ManagementAction.ConstructionMaterials]:
		intent.connected_track_destination = track_destination
	if definition.get("family", "") == "Rollers": intent.roller_speed = roller_speed
	if definition.get("key", "") == "Trap:TrackStop":
		intent.track_stop = {"friction":track_friction,"dump_direction":track_dump_direction}
	if definition.get("key", "") == "Trap:PressurePlate" and action in [1,2]:
		intent.pressure_plate = pressure_plate.duplicate()
	return intent

func accept_preview(state: Dictionary) -> bool:
	invalidate()
	if int(state.get("status", Contract.ManagementStatus.Rejected)) != Contract.ManagementStatus.Ok or not state.get("placement_valid", false):
		error = str(state.get("message", ""))
		return false
	var construction: Dictionary = state.get("construction", {})
	if is_connected_track():
		var track: Dictionary = construction.get("connected_track",{})
		var path: Array = track.get("path",[])
		if int(track.get("status",-1)) != 0 or path.size() < 2 or path.size() > 16384: return false
		if path.front() != origin or path.back() != track_destination: return false
		var seen: Dictionary = {}
		for tile in path:
			if typeof(tile) != TYPE_VECTOR3I or tile.x < 0 or tile.y < 0 or tile.z < 0 or seen.has(tile): return false
			seen[tile] = true
		for tile in path: track_path.append(tile)
	filters = construction.get("filters", []).duplicate(true)
	valid_mask = PackedByteArray(construction.get("valid_mask", []))
	pieces = PackedByteArray(construction.get("pieces", []))
	preview_valid = true
	return true

func material_request(filter_index: int, cursor: int = 0) -> Dictionary:
	var query := {"action":Contract.ManagementAction.ConstructionMaterials, "definition":str(definition.get("key", "")), "origin":origin, "filter":filter_index, "cursor":cursor}
	# Variable footprints change native reachability, distances and list identity.
	# Multi-level construction admission needs the volume and last selected corner.
	query.width = dimensions.x; query.height = dimensions.y
	query.direction = direction
	query.depth = dimensions.z if is_terrain_construction() else 1
	if is_terrain_construction(): query.material_anchor = material_anchor if material_anchor.z >= 0 else origin
	if is_connected_track(): query.connected_track_destination = track_destination
	if cursor > 0 and snapshots.has(filter_index): query.expected_list_revision = int(snapshots[filter_index].revision)
	return query

# "pending" is a completed read receipt describing an incremental builder.
# Its caller may poll the read at a bounded interval; Place is never polled by resending.
func accept_materials(state: Dictionary, query: Dictionary, take_rows := false) -> String:
	var filter_index := int(query.filter)
	if not preview_valid or query.origin != origin or str(query.definition) != str(definition.key): return "obsolete"
	if definition.get("key", "") == "ScrewPump" and int(query.get("direction",0)) != direction: return "obsolete"
	if is_terrain_construction() and (query.get("material_anchor",origin) != (material_anchor if material_anchor.z >= 0 else origin) or int(query.get("depth",1)) != dimensions.z): return "obsolete"
	if is_connected_track() and query.get("connected_track_destination",Vector3i(-1,-1,-1)) != track_destination: return "obsolete"
	if int(state.get("status", Contract.ManagementStatus.Rejected)) != Contract.ManagementStatus.Ok:
		invalidate(); error = str(state.get("message", "")); return "failed"
	var data: Dictionary = state.get("construction", {})
	if int(data.get("filter", -1)) != filter_index:
		invalidate(); error = "Material reply does not match the recipe"; return "failed"
	if int(data.get("build_phase", 0)) == 3:
		invalidate(); error = str(state.get("message", "")); return "failed"
	if int(data.get("build_phase", 0)) != 0: return "pending"
	var cursor := int(query.get("cursor", 0))
	var revision := int(data.get("list_revision", 0))
	if not snapshots.has(filter_index):
		if cursor != 0 or revision <= 0:
			invalidate(); error = "Material snapshot unavailable"; return "failed"
		snapshots[filter_index] = {"revision":revision, "rows":[], "cursors":[], "next_cursor":0, "total":int(data.get("total", 0))}
	var page: Dictionary = snapshots[filter_index]
	if int(page.revision) != revision or page.cursors.has(cursor) or (cursor != 0 and cursor != int(page.next_cursor)):
		invalidate(); error = "Material list changed; choose the site again"; return "failed"
	page.cursors.append(cursor)
	for row in data.get("materials", []):
		for previous in page.rows:
			if identity(previous) == identity(row):
				invalidate(); error = "Material page repeated a group"; return "failed"
		# The construction controller receives an isolated, one-shot service
		# payload and transfers its rows here. Other callers retain copy isolation.
		page.rows.append(row if take_rows else row.duplicate(true))
	page.next_cursor = int(state.get("next_cursor", 0))
	return "ready"

static func identity(row: Dictionary) -> Array:
	return [int(row.item_type), int(row.item_subtype), int(row.mat_type), int(row.mat_index), int(row.get("individual_id",-1))]

func needed(filter_index: int) -> int:
	for row in filters:
		if int(row.index) == filter_index: return int(row.quantity)
	return 0

func variable_count(filter_index: int) -> bool:
	return definition.get("key", "") == "Weapon" or (definition.get("key", "") == "Trap:WeaponTrap" and filter_index == 1)

func selected_count(filter_index: int) -> int:
	var count := 0
	for row in selections:
		if int(row.filter) == filter_index: count += int(row.count)
	return count

func group_count(filter_index: int, row: Dictionary) -> int:
	for selected in selections:
		if int(selected.filter) == filter_index and identity(selected) == identity(row): return int(selected.count)
	return 0

# Item IDs are owned by this draft and cleared with its snapshot. Native evidence:
# material_candidates.json selection_kernel_capture / individual_picker_capture.
func selected_ids(filter_index: int, row: Dictionary) -> Array:
	for selected in selections:
		if int(selected.filter) == filter_index and identity(selected) == identity(row):
			return selected.get("item_ids", []).duplicate()
	return []

func group_distance(filter_index: int, row: Dictionary) -> int:
	var chosen := selected_ids(filter_index,row)
	var distance := -1
	for item in row.get("candidates",[]):
		if not chosen.has(int(item.id)):
			var cost := int(item.distance)
			distance = cost if distance < 0 else mini(distance,cost)
	return distance

func _store_selection(filter_index: int, row: Dictionary, count: int, ids: Array) -> void:
	for index in range(selections.size() - 1, -1, -1):
		if int(selections[index].filter) == filter_index and identity(selections[index]) == identity(row): selections.remove_at(index)
	if count > 0:
		var selection := {"filter":filter_index, "count":count, "expected_list_revision":int(snapshots[filter_index].revision)}
		for field in ["item_type", "item_subtype", "mat_type", "mat_index"]: selection[field] = int(row[field])
		selection.individual_id = int(row.get("individual_id",-1))
		if row.has("candidates"):
			ids.sort(); selection.item_ids = ids.duplicate()
		selections.append(selection)

# Reinforced Wall inputs overlap: bars used as building materials disappear
# from the following metal-bar picker. Keep the pinned source rows immutable.
func available_row(filter_index: int, source: Dictionary) -> Dictionary:
	if definition.get("key","")!="Construction:ReinforcedWall" or not source.has("candidates"): return source
	var used := {}
	for selection in selections:
		if int(selection.filter)!=filter_index:
			for id in selection.get("item_ids",[]): used[int(id)]=true
	if used.is_empty(): return source
	var row: Dictionary = source.duplicate()
	row.candidates = source.candidates.filter(func(item):return not used.has(int(item.id)))
	row.count = row.candidates.size()
	return row

func select_group(filter_index: int, row_index: int, count: int) -> bool:
	if not preview_valid or not snapshots.has(filter_index): return false
	var snapshot: Dictionary = snapshots[filter_index]
	if row_index < 0 or row_index >= snapshot.rows.size(): return false
	var row: Dictionary = available_row(filter_index,snapshot.rows[row_index])
	var old_count := group_count(filter_index, row)
	var limit := 10 if variable_count(filter_index) else needed(filter_index)
	if count < 0 or count > int(row.count) or selected_count(filter_index) - old_count + count > limit: return false
	if old_count == 0 and count > 0 and selections.size() >= (16384 if is_connected_track() else 16):
		# Transport bounds are not native player-facing copy.
		error = ""; return false
	var ids := selected_ids(filter_index,row)
	if row.has("candidates"):
		if ids.size() != old_count: return false
		while ids.size() != count:
			var adding := ids.size() < count
			var best_id := -1
			var best_cost := -1
			for item in row.candidates:
				var id := int(item.id); var cost := int(item.distance)
				if ids.has(id) == adding: continue
				if best_id < 0 or (adding and cost < best_cost) or (not adding and cost > best_cost) or (cost == best_cost and id > best_id):
					best_id = id; best_cost = cost
			if best_id < 0: return false
			if adding: ids.append(best_id)
			else: ids.erase(best_id)
	_store_selection(filter_index,row,count,ids)
	return true

func select_item(filter_index: int, row_index: int, item_id: int) -> bool:
	if not preview_valid or not snapshots.has(filter_index): return false
	var rows: Array = snapshots[filter_index].rows
	if row_index < 0 or row_index >= rows.size(): return false
	var row: Dictionary = available_row(filter_index,rows[row_index])
	var member := false
	for item in row.get("candidates",[]):
		if int(item.id) == item_id: member = true; break
	if not member: return false
	var ids := selected_ids(filter_index,row)
	if ids.has(item_id): return true # Native repeat click is a no-op.
	var limit := 10 if variable_count(filter_index) else needed(filter_index)
	if selected_count(filter_index) >= limit or (ids.is_empty() and selections.size() >= (16384 if is_connected_track() else 16)): return false
	ids.append(item_id)
	_store_selection(filter_index,row,ids.size(),ids)
	return true

func covered(filter_index: int) -> bool:
	var count := selected_count(filter_index)
	return count >= 1 and count <= 10 if variable_count(filter_index) else count == needed(filter_index)

func deselect_item(filter_index: int, row_index: int, item_id: int) -> bool:
	if not preview_valid or not snapshots.has(filter_index): return false
	var rows: Array = snapshots[filter_index].rows
	if row_index < 0 or row_index >= rows.size(): return false
	var row: Dictionary = rows[row_index]
	var ids := selected_ids(filter_index,row)
	if not ids.has(item_id): return false
	ids.erase(item_id)
	_store_selection(filter_index,row,ids.size(),ids)
	return true

func can_place() -> bool:
	if not preview_valid: return false
	var used := {}
	for selection in selections:
		for id in selection.get("item_ids",[]):
			if used.has(int(id)): return false
			used[int(id)]=true
	for row in filters:
		if not covered(int(row.index)): return false
	return true

func is_single_furniture() -> bool:
	return definition.get("key","") in ["Bed","Chair","Table","Coffin","Cabinet","Box","Statue","Slab"]

func is_single_item_building() -> bool:
	return is_single_furniture() or definition.get("key","") in ["TractionBench","Bookcase","DisplayFurniture","OfferingPlace","Instrument","Door","Hatch","Cage","Chain","Armorstand","Weaponrack","GrateWall","GrateFloor","Floodgate","NestBox","Hive","Workshop:Quern","AnimalTrap","WindowGlass","Trap:PressurePlate"]

func is_fixed_recipe() -> bool:
	return FixedRecipes.RECIPES.has(definition.get("key",""))

func place_request() -> Dictionary:
	if not can_place(): return {}
	if is_connected_track():
		if track_path.size() < 2 or track_path.front() != origin or track_path.back() != track_destination: return {}
		for selected in selections:
			if not selected.has("item_ids") or selected.item_ids.size() != int(selected.count): return {}
	elif definition.get("key","") not in ["Windmill","Bridge"] and not is_magma_building() and not is_fixed_recipe() and not is_single_item_building() and not is_terrain_construction():
		# Aggregate constructors still cannot accept exact identities.
		for selected in selections:
			if selected.has("item_ids"): return {}
	var query := request(Contract.ManagementAction.Place)
	query.selections = selections.duplicate(true)
	query.expected_list_revision = int(selections[0].expected_list_revision) if not selections.is_empty() else 0
	return query
