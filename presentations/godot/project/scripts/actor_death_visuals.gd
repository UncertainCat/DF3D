extends RefCounted
## Brief, confirmed death poses retain the last visible mesh after semantic removal.
## Missing actors alone never cause a death. No geometry is regenerated.
const HOLD_SECONDS := 1.6
const MAX_DEATHS := 64
var appearances := {}
var pending := {}
var active := {}
var corpses := {} # Exact item ID -> observed owner, never a tile heuristic.
var generation := -1
var cursor := 0
var rendered_deaths := 0
var view_scope: Array = []
var _member_ids := PackedInt64Array()
var _live: Dictionary = {}
var _missing_until: Dictionary = {}
var membership_reconciliations := 0
var missing_expiry_checks := 0

func reset(value: int):
	if value == generation: return
	for entry in active.values(): entry.node.queue_free()
	corpses.clear()
	appearances.clear()
	pending.clear()
	active.clear()
	_member_ids.clear()
	_live.clear()
	_missing_until.clear()
	membership_reconciliations = 0
	missing_expiry_checks = 0
	cursor = 0
	rendered_deaths = 0
	generation = value
	view_scope.clear()

func set_view_scope(value: Array) -> bool:
	if value == view_scope: return false
	# A changed cutaway/style invalidates cached transforms and roof ceilings.
	for entry in active.values(): entry.node.queue_free()
	active.clear()
	corpses.clear()
	appearances.clear()
	pending.clear()
	_missing_until.clear()
	view_scope = value
	return true

func remember(id: int, layer: MultiMeshInstance3D, pose: Transform3D, custom: Color, size := Vector2.ONE, thickness := .12, position := Vector3.INF, scale_params := Color(1,0,0,1), motion: Dictionary = {}):
	var anchor: Vector3 = position if position.is_finite() else pose.origin
	var offset := Vector3.ZERO
	if not motion.is_empty(): offset = anchor - _motion_position(motion, float(motion.tick))
	# A frozen appearance must never read a reusable live actor motion slot.
	var frozen_scale := scale_params
	frozen_scale.a = 0.0
	appearances[id] = {"mesh":layer.multimesh.mesh, "material":layer.material_override,
		"scale_params":frozen_scale, "custom":custom, "size":size,
		"thickness":thickness, "position":anchor, "motion":motion.duplicate(), "motion_offset":offset}
	if _live.has(id): _missing_until.erase(id)
	else: _missing_until[id] = INF # Start grace when the presentation clock is available.

static func _motion_position(motion: Dictionary, tick: float) -> Vector3:
	# The same split-tick interval evaluated by actor_motion.gdshaderinc. Retain
	# endpoints, not a live pool address, so removal can safely recycle that slot.
	var first: Color = motion.from
	var last: Color = motion.to
	var epochs: Vector2 = motion.epochs
	var start: float = epochs.x * 4096.0 + first.a
	var end: float = epochs.y * 4096.0 + last.a
	var phase := clampf((tick - start) / (end - start), 0.0, 1.0) if end > start else 0.0
	return Vector3(first.r, first.g, first.b).lerp(Vector3(last.r, last.g, last.b), phase)

func observe(events: Array, clock: float, animate := true):
	for event in events:
		cursor = maxi(cursor, int(event.id))
		if animate and int(event.kind) == 2 and not active.has(int(event.victim_id)):
			var tile: Vector3i = event.get("position", Vector3i(-1,-1,-1))
			var position := Vector3(tile.x + .5, tile.z, tile.y + .5) if tile.x >= 0 and tile.y >= 0 and tile.z >= 0 else Vector3.INF
			pending[int(event.victim_id)] = {"clock":clock,"position":position,"tick":float(event.get("tick",-1))}

func update(owner: Node, ids: PackedInt64Array, clock: float, presentation = null, render_tick: float = NAN):
	_reconcile_membership(ids, clock)
	expire(clock)
	for id in pending.keys():
		var event: Dictionary = pending[id]
		if clock - event.clock > 2.0:
			pending.erase(id)
			continue
		if _live.has(id) or not appearances.has(id) or active.size() >= MAX_DEATHS: continue
		var look: Dictionary = appearances[id]
		if is_finite(render_tick) and not look.motion.is_empty():
			# Stack/floor lift is retained separately from semantic interpolation.
			look.position = _motion_position(look.motion, render_tick) + look.motion_offset
			var end: float = look.motion.epochs.y * 4096.0 + look.motion.to.a
			if event.tick > end and event.position.is_finite():
				# A culled group may retain an older segment. Its confirmed death
				# location is available even when no newer visual was prepared.
				look.position = event.position + look.motion_offset
		var death_position: Vector3 = event.position if event.position.is_finite() else look.position
		if not _inside_window(death_position):
			pending.erase(id)
			appearances.erase(id)
			_missing_until.erase(id)
			for item in corpses.keys():
				if corpses[item].unit == id: corpses.erase(item)
			continue
		var node := MultiMeshInstance3D.new()
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_custom_data = true
		mesh.use_colors = true
		mesh.mesh = look.mesh
		mesh.instance_count = 1
		mesh.set_instance_color(0, look.scale_params)
		var custom: Color = look.custom
		custom.g = 15.0
		custom.b = clock
		custom.a = 0.0
		node.multimesh = mesh
		node.material_override = look.material
		node.extra_cull_margin = 2.0
		owner.add_child(node)
		active[id] = {"node":node, "start":clock, "look":look, "custom":custom}
		_refresh_pose(active[id], presentation)
		rendered_deaths += 1
		pending.erase(id)

func _reconcile_membership(ids: PackedInt64Array, clock: float) -> void:
	if ids == _member_ids: return
	# Native array equality handles unchanged membership without rebuilding a
	# dictionary or touching live appearances on each source-only update.
	membership_reconciliations += 1
	_member_ids = ids.duplicate()
	var previous := _live
	_live = {}
	for id in ids:
		_live[id] = true
		_missing_until.erase(id)
	for id in previous:
		if not _live.has(id) and appearances.has(id): _missing_until[id] = clock + 2.0

func _inside_window(position: Vector3) -> bool:
	# Isolated callers may omit scope. The world supplies generation/top/depth,
	# followed by presentation preferences; only the elevation window matters.
	if view_scope.size() < 3: return true
	var top := int(view_scope[1])
	var depth := int(view_scope[2])
	if top < 0 or depth <= 0: return true
	var z := floori(position.y)
	return z <= top and z > top - depth

func expire(clock: float):
	for id in active.keys():
		if clock - active[id].start >= HOLD_SECONDS:
			active[id].node.queue_free()
			active.erase(id)
			appearances.erase(id) # A later corpse arrival must not restart the grace period.
			_missing_until.erase(id)
	# Only departures participate in expiry work. Thousands of retained live
	# appearances are irrelevant to this clock-only path.
	for id in _missing_until.keys():
		missing_expiry_checks += 1
		if _missing_until[id] == INF: _missing_until[id] = clock + 2.0
		elif clock > _missing_until[id]:
			appearances.erase(id)
			_missing_until.erase(id)

func _refresh_pose(entry: Dictionary, presentation):
	var look: Dictionary = entry.look
	var pose := Transform3D(Basis.IDENTITY.scaled(Vector3(look.size.x, look.thickness / .12, look.size.y)), look.position)
	var custom: Color = entry.custom
	if presentation != null:
		entry.node.multimesh.custom_aabb = presentation.billboard_bounds(look.mesh, look.size * maxf(1.0,look.scale_params.r), look.position)
	if presentation != null and presentation.sprites_oriented():
		custom.r = presentation.piece_ceiling(look.mesh, pose, look.position)
		var scaled_pose := Transform3D(pose.basis.scaled(Vector3(look.scale_params.r,1,look.scale_params.r)),look.position)
		look.scale_params.b = presentation.piece_ceiling(look.mesh, scaled_pose, look.position)
	entry.node.multimesh.set_instance_color(0,look.scale_params)
	entry.node.multimesh.set_instance_transform(0, pose)
	entry.node.multimesh.set_instance_custom_data(0, custom)


func corpse_handoff(changes: Array, clock: float, animate := true) -> PackedInt64Array:
	if not animate:
		corpses.clear()
		return PackedInt64Array()
	for change in changes:
		var id := int(change.item_id)
		var unit := int(change.unit_id)
		# Fresh corpse ownership permits a short wait for the buffered death event.
		# It never starts a death pose by itself. Unobserved actors remain visible.
		if not corpses.has(id) and (appearances.has(unit) or active.has(unit)) and corpses.size() < MAX_DEATHS:
			corpses[id] = {"unit":unit, "start":clock, "played":active.has(unit)}
	for id in corpses.keys():
		var entry: Dictionary = corpses[id]
		if active.has(entry.unit):
			entry.played = true
		elif entry.played or clock - entry.start >= 2.0:
			corpses.erase(id)
	return PackedInt64Array(corpses.keys())
