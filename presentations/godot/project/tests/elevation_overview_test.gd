extends SceneTree
const Overview = preload("res://scripts/elevation_overview.gd")
var requested := -1
class Hud extends RefCounted:
	var summary := {"elevation_offset": -100}
	var minimap := {"allowed": true}
	func elevation_rect(): return Rect2(0,0,16,500)
func _initialize(): call_deferred("run")
func run():
	assert(Overview.level_at(12, 500, 200) == 199)
	assert(Overview.level_at(488, 500, 200) == 0)
	assert(Overview.level_at(250, 500, 200) == 100)
	assert(Overview.level_at(-100, 1, 1) == 0)
	var world := Df3dWorld.new()
	root.add_child(world)
	assert(world.load_assets(OS.get_environment("DF3D_DF_PATH")))
	assert(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")))
	world.poll()
	assert(int(world.elevation_overview(-1, 0).surface_z) == -1)
	assert(int(world.elevation_overview(0, 0).level_count) > 0)
	var overview := Overview.new()
	overview.world = world
	overview.hud = Hud.new()
	overview.camera_rig = Node3D.new()
	root.add_child(overview.camera_rig)
	root.add_child(overview)
	for key in overview.art:
		if overview.art[key] is Array:
			for texture in overview.art[key]: assert(texture != null, key)
		else: assert(overview.art[key] != null, key)
	overview.level_requested.connect(func(level): requested = level)
	await process_frame
	overview.size = Vector2(16,500)
	overview.data = {"level_count": 200, "surface_z": 70}
	overview.navigate(250)
	assert(requested == 100)
	overview.hud.minimap.allowed = false
	overview.navigate(400)
	assert(requested == 100)
	print("ELEVATION_OVERVIEW_PASS")
	quit()
