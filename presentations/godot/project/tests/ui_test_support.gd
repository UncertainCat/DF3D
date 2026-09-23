extends SceneTree
var failures := 0
class FakeWorld extends RefCounted:
	var calls: Array = []
	var state := {"world_epoch":42,"revision":1,"status":0}
	func is_live(): return false
	func resident_info_state(): return state
	func demand_resident_info(_value): pass
	func refresh_resident_info(): pass
	func unit_tile(_id): return Vector3i(-1,-1,-1)
class AssetWorld extends FakeWorld:
	var assets
	func ui_texture(selector: String, variant := -1): return assets.ui_texture(selector,variant)
	func ui_font_path(): return assets.ui_font_path()
class FakeInteraction extends Node:
	var panel := PanelContainer.new()
	var construction_active := false
	var shell_enabled := true
	var shell_blocked := false
	var audio: Node
	func _ready(): add_child(panel);panel.add_child(VBoxContainer.new())
	func cancel_selection(): pass
	func set_play_enabled(value): panel.visible=value
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
	if not value: failures+=1;push_error(message)
func run(): quit()
