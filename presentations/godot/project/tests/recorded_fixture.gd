extends RefCounted
# Camera and clock metadata belong to the recording, not individual test cases.
const PATH = "res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix"
const MANIFEST = "res://../../../fixtures/recorded/mature_fort_pause_53.16.manifest.json"
static func view() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)).view
static func top_z() -> int:
	return int(view().top_z)
static func tick() -> int:
	return int(view().tick)
static func focus() -> Vector3:
	var pose := view()
	return Vector3(pose.x, pose.top_z + 1, pose.y)
static func configure_scene() -> void:
	var pose := view()
	OS.set_environment("DF3D_FIXTURE", ProjectSettings.globalize_path(PATH))
	OS.set_environment("DF3D_FIXTURE_TICK", str(tick()))
	OS.set_environment("DF3D_TOP_Z", str(top_z()))
	OS.set_environment("DF3D_CAM_FOCUS", "%s,%s,%s" % [pose.x, pose.y, pose.top_z])
	OS.set_environment("DF3D_CAM_DIST", str(pose.distance))
