extends SceneTree
const UI = preload("res://scripts/original_ui.gd")
var failures := 0
class MissingArt extends RefCounted:
	func ui_texture(_name: String, _variant := -1): return null
	func ui_font_path(): return ""
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var missing := UI.new()
	missing.configure(MissingArt.new())
	check(missing.theme.get_stylebox("panel","PanelContainer") is StyleBoxFlat, "missing art preserves readable error panel")
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "verified install assets load")
	var art := UI.new()
	art.configure(world)
	var normal: Texture2D = art.texture("BUTTON_RECTANGLE")
	check(normal != null and normal.get_size() == Vector2(24,36), "complete 3x3 original button layout")
	check(art.texture("BUTTON_DIG_DIG_INACTIVE").get_size() == Vector2(32,36), "complete dig art layout")
	check(world.ui_texture("DF3D_MISSING_TEST_ICON") == null, "unknown icon not guessed")
	check(world.ui_texture("BUTTON_RECTANGLE") == normal, "widget cache shares texture")
	var button := Button.new()
	button.text = "Melt"
	root.add_child(button)
	art.apply(button)
	check(button.icon != null and button.tooltip_text == "Melt", "original icon retains textual action tooltip")
	check(button.theme.default_font.get_string_size("Dig", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 0, "runtime bitmap font measures text")
	var font := button.theme.default_font as FontFile
	for character in "Dôren Atír éîòû":
		check(font.has_char(character.unicode_at(0)), "original font supports fortress name " + character)
	for code in [0x263C, 0x2261, 0x2642, 0x2640, 0x2191, 0x2302]:
		check(font.has_char(code), "original font supports native quality and status symbols")
	var image := font.get_texture_image(0, Vector2i(font.fixed_size,0), 0)
	var clear := 0
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a < 0.01: clear += 1
			else: opaque += 1
	check(clear > 0 and opaque > 0, "font background key is transparent; glyph ink retained")
	world.set_fixed_render_tick(10)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/interaction.df3dfix")), "building picking fixture loads")
	world.set_top_z(1)
	world.set_window_depth(1)
	for i in 6: world.poll()
	var hit: Dictionary = {}
	for x in 10:
		for y in 10:
			var candidate := world.pick_building(Vector3(8.05+x*0.1,4.0,11.05+y*0.1),Vector3.DOWN,1)
			if candidate.get("id",-1) == 101: hit = candidate
	check(hit.get("id",-1) == 101 and hit.get("tile",Vector3i(-1,-1,-1)) == Vector3i(8,11,1), "actual rendered door volume ray-picks authoritative tile/identity")
	check(world.pick_building(Vector3(8.5,4.0,11.5),Vector3.DOWN,2).is_empty(), "building mesh picking rejects other levels")
	world.free()
	button.free()
	print("original UI tests: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(failures)
