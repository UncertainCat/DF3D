extends RefCounted
# Membership depends on artwork and optional spatial cells, not interpolation.
# Store independent packed arrays: retaining native buffers would make the next
# native update copy them on write even when this partition has not changed.
var groups: Dictionary = {}
var markers: Array[int] = []
var removed_keys: Array = []
var changed_keys: Dictionary = {}
var _members: Dictionary = {}
var _ids := PackedInt64Array()
var _keys: Array[String] = []
var rebuilds := 0
var hits := 0
var keys_built := 0
var _ready := false
var _slots := PackedInt32Array()
var _regions := PackedColorArray()
var _cells: Array[Vector3i] = []
var _spatial := false
var _cell_xy := 16
var _cell_z := 1

func _cell(position: Vector3, cell_xy: int, cell_z: int) -> Vector3i:
	return Vector3i(floori(position.x / cell_xy), floori(position.y / cell_z), floori(position.z / cell_xy))

func update(slots: PackedInt32Array, regions: PackedColorArray, positions: PackedVector3Array,
		spatial: bool, cell_xy: int, cell_z: int, batch_key: Callable, ids := PackedInt64Array(), changes = null) -> bool:
	changed_keys.clear()
	removed_keys.clear()
	var same := _ready and _slots == slots and _regions == regions and _spatial == spatial and _ids == ids
	if same and spatial:
		same = _cell_xy == cell_xy and _cell_z == cell_z
		if same:
			for i in (range(slots.size()) if changes == null else changes):
				if slots[i] >= 0 and _cells[i] != _cell(positions[i], cell_xy, cell_z):
					same = false
					break
	if same:
		hits += 1
		return false
	# Stable source indices allow membership edits confined to affected groups.
	# The native delta covers artwork as well as motion; legacy callers without
	# a delta compare every row, but still construct keys only for changed rows.
	var config_same := _ready and _spatial == spatial and (not spatial or (_cell_xy == cell_xy and _cell_z == cell_z))
	if config_same and _ids == ids and _slots.size() == slots.size():
		var touched := {}
		for i in (range(slots.size()) if changes == null else changes):
			var cell := _cell(positions[i], cell_xy, cell_z) if spatial and slots[i] >= 0 else Vector3i.ZERO
			if _slots[i] == slots[i] and _regions[i] == regions[i] and (not spatial or slots[i] < 0 or _cells[i] == cell): continue
			var old: String = _keys[i]
			var key := "" if slots[i] < 0 else String(batch_key.call(slots[i], regions[i], cell))
			if slots[i] >= 0: keys_built += 1
			if spatial: _cells[i] = cell
			_keys[i] = key
			if old == key: continue
			var previous_list: Array = markers if old == "" else groups[old]
			previous_list.erase(i)
			if old != "" and previous_list.is_empty(): groups.erase(old)
			if key != "" and not groups.has(key): groups[key] = []
			var next_list: Array = markers if key == "" else groups[key]
			next_list.insert(next_list.bsearch(i), i)
			touched[old] = true
			touched[key] = true
		for key in touched:
			if key != "" and not groups.has(key):
				removed_keys.append(key)
				_members.erase(key)
			else:
				_update_members(key, ids)
	else:
		# Membership changes can shift every native array index. Rebuild index
		# lists in source order, reusing each surviving actor's texture/cell key.
		# This is deliberately a single linear pass, not a second ownership map.
		var previous := groups
		groups = {}
		markers = []
		var old_indices := {}
		if config_same:
			for i in _slots.size(): old_indices[_ids[i] if not _ids.is_empty() else i] = i
		var next_keys: Array[String] = []
		var next_cells: Array[Vector3i] = []
		next_keys.resize(slots.size())
		if spatial: next_cells.resize(slots.size())
		for i in slots.size():
			if slots[i] < 0:
				markers.append(i)
				continue
			var cell := _cell(positions[i], cell_xy, cell_z) if spatial else Vector3i.ZERO
			if spatial: next_cells[i] = cell
			var old: int = old_indices.get(ids[i] if not ids.is_empty() else i, -1)
			var key: String
			if old >= 0 and _slots[old] == slots[i] and _regions[old] == regions[i] and (not spatial or _cells[old] == cell):
				key = _keys[old]
			else:
				key = batch_key.call(slots[i], regions[i], cell)
				keys_built += 1
			next_keys[i] = key
			if not groups.has(key): groups[key] = []
			groups[key].append(i)
		for key in previous:
			if not groups.has(key):
				removed_keys.append(key)
				_members.erase(key)
		var all_keys: Array = groups.keys()
		all_keys.append("")
		for key in all_keys: _update_members(key, ids)
		_keys = next_keys
		_cells = next_cells
	_ids = ids.duplicate()
	_slots = slots.duplicate()
	_regions = regions.duplicate()
	_spatial = spatial
	_cell_xy = cell_xy
	_cell_z = cell_z
	_ready = true
	rebuilds += 1
	return true

func _update_members(key: String, ids: PackedInt64Array) -> void:
	var list: Array = markers if key == "" else groups[key]
	var members := PackedInt64Array()
	for i in list: members.append(ids[i] if not ids.is_empty() else i)
	if not _members.has(key) or _members[key] != members: changed_keys[key] = true
	_members[key] = members
