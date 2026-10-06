extends SceneTree
# Synthetic prototype formatting only; these strings are not native copy evidence.
func _initialize():
	assert(not preload("res://scripts/ui_availability.gd").TILE_HOVER_AVAILABLE)
	var hover = preload("res://scripts/tile_hover.gd")
	assert(hover.describe({}) == "")
	assert(hover.describe({"shape":"Empty"}) == "Open space")
	assert(hover.describe({"shape":"Floor","material":"GRANITE","smooth":true}) == "Smooth Granite floor")
	assert(hover.describe({"shape":"StairUpDown","material_kind":"Stone","engraved":true}) == "Engraved Stone stair up down")
	assert(hover.describe({"shape":"Floor","material_kind":"Soil","liquid":"Water","liquid_level":4}) == "Soil floor · Water 4/7")
	print("TILE_HOVER_TEST_PASS")
	quit()
