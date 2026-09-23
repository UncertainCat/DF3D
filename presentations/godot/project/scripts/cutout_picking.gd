extends RefCounted
# Entity kinds shared by pick results, inspect_entity and selection_panel.open_target.
const KIND_NONE := 0
const KIND_UNIT := 1
const KIND_ITEM := 2
const KIND_BUILDING := 3
# Ray tests use the same bottom-anchored contours and transforms as rendering.
# Candidate tiles remain authoritative even when their visuals interpolate.
static func mesh_depth(mesh: Mesh, transform: Transform3D, origin: Vector3, direction: Vector3, ceiling: float = INF, animation: Dictionary = {}) -> float:
	if mesh == null or absf(transform.basis.determinant())<0.000001: return INF
	if not animation.is_empty():
		transform.origin += preload("res://scripts/actor_animation_catalog.gd").world_offset(animation.code, animation.elapsed, animation.seed, animation.strength)
	var inverse := transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	if mesh.get_aabb().grow(0.5 if not animation.is_empty() else 0.0).intersects_ray(local_origin,local_direction) == null: return INF
	var nearest := INF
	var faces := mesh.get_faces()
	if not animation.is_empty():
		var catalog = preload("res://scripts/actor_animation_catalog.gd")
		for vertex in faces.size(): faces[vertex] = catalog.vertex(faces[vertex], animation.code, animation.elapsed, animation.seed, animation.strength)
	for i in range(0,faces.size()-2,3):
		var hit = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
		if hit != null and (transform * hit).y < ceiling: nearest = minf(nearest,origin.distance_squared_to(transform*hit))
	return nearest

static func nearest(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if float(candidate.get("depth",INF)) == INF: continue
		if best.is_empty() or candidate.depth < best.depth or (candidate.depth == best.depth and (candidate.id < best.id or (candidate.id == best.id and int(candidate.get("kind",0)) < int(best.get("kind",0))))): best = candidate
	return best

static func pieces(world, camera: Camera3D, screen: Vector2, top_z: int) -> Array:
	var candidates: Array = []
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var presentation = camera.get_meta("sprite_presentation") if camera.has_meta("sprite_presentation") else null
	var upright: bool = is_instance_valid(presentation) and presentation.sprites_oriented()
	var item_layout: Dictionary = world.item_physical_layout()
	for unit in [false,true]:
		if unit and not world.has_method("unit_tile"): continue
		var positions: PackedVector3Array = world.unit_cutout_positions() if unit else item_layout.positions
		var thicknesses: PackedFloat32Array = world.unit_thicknesses() if unit else item_layout.thicknesses
		var sizes: PackedVector2Array = world.unit_sprite_sizes() if unit else world.item_sprite_sizes()
		var scales: PackedColorArray = world.unit_scale_params() if unit and world.has_method("unit_scale_params") else PackedColorArray()
		var truescale: bool = unit and preload("res://scripts/presentation_settings.gd").truescale
		var ids: PackedInt64Array = world.unit_ids() if unit else world.item_ids()
		var slots: PackedInt32Array = world.unit_sprite_slots() if unit else world.item_sprite_slots()
		var ground_flags: PackedByteArray = PackedByteArray() if unit else world.item_ground_flags()
		var regions: PackedColorArray = world.unit_sprite_regions() if unit else world.item_sprite_regions()
		for i in positions.size():
			if i>=ids.size() or i>=slots.size() or i>=sizes.size() or i>=thicknesses.size() or i>=regions.size(): continue
			var piece_upright: bool = upright and (unit or i >= ground_flags.size() or ground_flags[i] == 0)
			var tile: Vector3i = world.unit_tile(ids[i]) if unit else world.item_tile(ids[i])
			if tile.x<0 or tile.z!=top_z or thicknesses[i]<=0.0 or camera.is_position_behind(positions[i]): continue
			var animation := {}
			if unit and camera.has_meta("actor_animation"):
				var state = camera.get_meta("actor_animation")
				var record = state.records.get(ids[i])
				if record != null and not record.animation.is_empty():
					animation = {"code":state.codes.get(record.animation, 0), "elapsed":state.clock-record.start, "seed":record.parameter, "strength":preload("res://scripts/presentation_settings.gd").animation_strength}
			var footprint := sizes[i] if slots[i]>=0 else Vector2(0.8,0.8) if unit else Vector2(0.3,0.3)
			var ground := Vector3.ZERO
			if world.has_method("ground_support"):
				ground = world.unit_ground_support(i) if unit else world.ground_support(Vector3(positions[i].x,tile.z,positions[i].z))
			if piece_upright and slots[i]>=0: ground = Vector3.ZERO
			if unit and slots[i] >= 0:
				footprint *= preload("res://scripts/actor_view_scale.gd").effective(scales[i].r if i < scales.size() else 1.0, truescale)
			var bounds := Rect2(camera.unproject_position(positions[i]),Vector2.ZERO)
			for x in [-0.5,0.5]:
				for z in [-0.5,0.5]:
					for y in [0.0,thicknesses[i]]:
						bounds = bounds.expand(camera.unproject_position(positions[i]+Vector3(x*footprint.x,y+ground.x*x*footprint.x+ground.z*z*footprint.y,z*footprint.y)))
			if animation.is_empty() and not piece_upright and not bounds.has_point(screen): continue
			var mesh: Mesh
			if slots[i]>=0: mesh = world.sprite_cutout_mesh(slots[i],regions[i])
			else:
				var box := BoxMesh.new()
				box.size = Vector3(1,0.12,1)
				mesh = box
			var basis := Basis.IDENTITY.scaled(Vector3(footprint.x,thicknesses[i]/0.12,footprint.y))
			basis.x.y = ground.x * footprint.x
			basis.z.y = ground.z * footprint.y
			var position := positions[i]
			var clip_anchor := Vector3(position.x,tile.z,position.z)
			# BoxMesh is centered; the contour mesh already starts at y=0.
			if slots[i]<0: position.y += thicknesses[i]*0.5
			var transform := Transform3D(basis, position)
			var ceiling := INF
			if piece_upright and slots[i] >= 0:
				transform = presentation.piece_transform(footprint, thicknesses[i], position)
				if truescale and i < scales.size():
					var lift: float = clampf(camera.global_basis.y.y,0.0,1.0) if presentation.billboard else (0.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.0)
					transform.origin += transform.basis.z * scales[i].g * lift
					transform.origin.y -= footprint.y * scales[i].g * lift * (1.0 - lift)
				var retained: Dictionary = camera.get_meta("actor_ceilings", {}) if unit else {}
				ceiling = retained[ids[i]].ceiling if retained.has(ids[i]) else presentation.piece_ceiling(mesh, transform, clip_anchor)
				var box: AABB = transform * mesh.get_aabb().grow(0.5 if not animation.is_empty() else 0.0)
				if not animation.is_empty():
					box.position += preload("res://scripts/actor_animation_catalog.gd").world_offset(animation.code, animation.elapsed, animation.seed, animation.strength)
				bounds = Rect2(camera.unproject_position(box.position), Vector2.ZERO)
				for corner in range(8): bounds = bounds.expand(camera.unproject_position(box.get_endpoint(corner)))
				if not bounds.has_point(screen): continue
			if upright and not piece_upright and slots[i] >= 0:
				if truescale and i < scales.size():
					var lift: float = clampf(camera.global_basis.y.y,0.0,1.0) if presentation.billboard else (0.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.0)
					transform.origin += transform.basis.z * scales[i].g * lift
				ceiling = presentation.piece_ceiling(mesh, transform, clip_anchor)
			var depth := mesh_depth(mesh,transform,origin,direction,ceiling,animation)
			if depth<INF: candidates.append({"kind":KIND_UNIT if unit else KIND_ITEM,"id":ids[i],"tile":tile,"visible":true,"bounds":bounds,"depth":depth})
	return candidates
