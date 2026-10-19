extends MeshInstance3D
# Alpha surfaces that cross a building's footprint cannot share an arbitrary
# material-sorted batch. Keep a draw per installation; Godot sorts its bounds
# against the camera. Native's north-spilling artwork also has a top-view lift
# and a south-over-north tie-break, matching the shader's foreground convention.
var _row := 0.0
var _lift := 0.0

func _ready() -> void:
	# Run after the camera controller, including the frame that changes modes.
	process_priority = 100
	sorting_use_aabb_center = true
	_row = float(get_meta("df3d_sort_row", 0.0))
	_lift = float(get_meta("df3d_sort_lift", 0.0))

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var top_down := camera.global_basis.z.y > 0.9999
	# Camera-relative rows keep the tie-break small around the visible scene.
	# This changes renderer sort state only; meshes/materials stay resident.
	var offset := _lift + (_row-camera.global_position.z)*0.001 if top_down else 0.0
	if sorting_offset != offset: sorting_offset = offset
