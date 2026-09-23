extends SceneTree
const Presentation = preload("res://scripts/sprite_presentation.gd")
const Geometry = preload("res://scripts/sprite_geometry.gd")
const Preferences = preload("res://scripts/presentation_settings.gd")
class Owner:
	extends Node3D
	var _unit_revision_seen := 0
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; push_error(message)
func _initialize(): call_deferred("run")
func run():
	var owner := Owner.new()
	root.add_child(owner)
	var camera := Camera3D.new()
	owner.add_child(camera)
	var presentation := Presentation.new()
	owner.add_child(presentation)
	presentation._main = owner
	presentation._camera = camera
	var sprite := MultiMeshInstance3D.new()
	sprite.material_override = ShaderMaterial.new()
	var original = preload("res://shaders/unit_sprite.gdshader")
	sprite.material_override.shader = original
	owner.add_child(sprite)
	presentation.set_style("billboard")
	check(presentation.billboard and sprite.material_override.shader.resource_path.ends_with("billboard_sprite.gdshader"), "Billboard changes sprite material once")
	owner._unit_revision_seen = 42
	presentation.set_style("billboard")
	check(owner._unit_revision_seen == 42, "Repeated style is a no-op")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 0.12, 1)
	var envelope: AABB = presentation.billboard_bounds(mesh, Vector2(2,3), Vector3.ZERO)
	for yaw in [0.0, 0.7, 1.6, 3.0]:
		for pitch in [0.1, 0.6, 1.2, 1.57]:
			camera.position = Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))*10.0
			camera.look_at(Vector3.ZERO)
			for projection in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]:
				camera.projection = projection
				var pose := Geometry.billboard_transform(camera, Vector2(2,3), 0.12, Vector3.ZERO)
				check((-pose.basis.z).normalized().is_equal_approx(camera.global_basis.y), "Picking follows billboard pitch")
				for corner in 8:
					check(envelope.has_point(pose*mesh.get_aabb().get_endpoint(corner)), "Resident bounds contain all camera orientations")
	check(owner._unit_revision_seen == 42, "Camera motion has no sprite preparation callback")
	presentation.set_style("classic")
	check(not presentation.billboard and sprite.material_override.shader == original, "Classic restores the original shader")
	var path := "user://retired-style-migration-test.cfg"
	for legacy in [false, true]:
		var config := ConfigFile.new()
		config.set_value("graphics", "hd2d" if legacy else "style", true if legacy else "hd2d")
		check(config.save(path) == OK, "Migration fixture saved")
		Preferences.load_preferences(path)
		check(Preferences.visual_style == "billboard", "Retired lighting preference migrates to billboard")
	DirAccess.remove_absolute(path)
	owner.free()
	print("SPRITE_PRESENTATION_PASS" if failures == 0 else "SPRITE_PRESENTATION_FAIL")
	quit(0 if failures == 0 else 1)
