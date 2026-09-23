extends RefCounted
# Demand never invalidates payloads. Hidden groups retain a stale bit until
# their latest source data is needed, independently of native delta retention.
var groups: Dictionary = {}
var planes: Array[Plane] = []
var view_key: Array = []
var enabled := true # Diagnostic full-residency oracle.
func update_view(camera: Camera3D) -> bool:
	var key := [camera.global_transform, camera.projection, camera.size, camera.fov, camera.near, camera.far, camera.get_viewport().size]
	if key == view_key: return false
	view_key = key
	planes = camera.get_frustum()
	var needs_prepare := false
	for record in groups.values():
		var demanded := visible(record.bounds)
		var layer = record.layer.get_ref() if record.layer != null else null
		if layer != null: layer.visible = demanded
		needs_prepare = needs_prepare or (demanded and record.stale)
	return needs_prepare
func visible(bounds: AABB) -> bool:
	if not enabled: return true
	for plane in planes:
		var closest := Vector3(bounds.position.x if plane.normal.x >= 0 else bounds.end.x,
			bounds.position.y if plane.normal.y >= 0 else bounds.end.y,
			bounds.position.z if plane.normal.z >= 0 else bounds.end.z)
		if plane.distance_to(closest) > 0: return false
	return true
func changed(key: String, bounds: AABB) -> void:
	var old: Dictionary = groups.get(key, {})
	groups[key] = {"bounds":bounds,"stale":true,"layer":old.get("layer")}
func stale(key: String) -> bool:
	return groups.has(key) and groups[key].stale
func prepared(key: String, layer: MultiMeshInstance3D) -> void:
	groups[key].stale = false
	groups[key].layer = weakref(layer)
	layer.visible = true
func remove(key: String) -> void:
	groups.erase(key)
