extends RefCounted
# CPU counterpart of billboard shader geometry for bounds and picking.
# Fully camera-facing cards, including pitch. Same transform is used by picking.
static func billboard_transform(camera: Camera3D, size: Vector2, thickness: float, position: Vector3) -> Transform3D:
	var right := camera.global_basis.x.normalized()
	var up := camera.global_basis.y.normalized()
	var front := right.cross(up).normalized()
	var axes := Basis(right * size.x, front * maxf(0.015, minf(thickness, 0.045)) / 0.12, -up * size.y)
	# Center in a top-down view; bottom-anchor continuously as the camera tilts.
	var lift := clampf(up.dot(Vector3.UP), 0.0, 1.0)
	return Transform3D(axes, position - axes.z * 0.5 * lift + Vector3.UP * size.y * 0.5 * lift * (1.0 - lift))

var world
var _native_ceiling := false
var _revision: Array = []
var _columns: Dictionary = {}

func configure(source) -> void:
	world = source
	_revision.clear()
	_columns.clear()
	_native_ceiling = world.has_method("sprite_ceiling")

func refresh() -> bool:
	# Only the reference source's dictionary needs clearing here. Production
	# clipping owns spatial dependencies natively; this is never a render dirty key.
	var key := [world.terrain_revision(), world.session_generation(), world.get_top_z()]
	if key == _revision: return false
	_revision = key
	_columns.clear()
	return true

func ceiling_for(bounds: AABB, floor_z: int) -> float:
	if _native_ceiling: return world.sprite_ceiling(bounds, floor_z)
	refresh()
	# A conservative horizontal clip plane: the lowest occupied column above
	# any part of the card. This also protects wide sprites under partial roofs.
	var ceiling := 1000000.0
	var end := bounds.end
	for x in range(floori(bounds.position.x + 0.0001), floori(end.x - 0.0001) + 1):
		for y in range(floori(bounds.position.z + 0.0001), floori(end.z - 0.0001) + 1):
			# Sliced-away terrain must not decapitate artwork on the active floor.
			for z in range(floor_z + 1, mini(ceili(end.y), world.get_top_z()) + 1):
				var tile := Vector3i(x, y, z)
				if not _columns.has(tile):
					var info: Dictionary = world.tile_hover_info(tile)
					# Unobserved/hidden terrain is conservative, never a hole
					# through which to expose unseen space. Leaves are not ceilings.
					_columns[tile] = info.get("shape", "Unknown") not in ["Empty", "RampTop", "TreeBranch", "TreeTwig"]
				if _columns[tile]:
					ceiling = minf(ceiling, z - 0.006)
					break
	return ceiling
