extends SceneTree
class Interaction extends Node:
	var construction_active := false
	var shell_blocked := false
	var shell_enabled := false
	var panel := PanelContainer.new()
	var cancelled := 0
	var enabled := true
	func _ready(): add_child(panel)
	func cancel_selection(): cancelled += 1
	func set_play_enabled(value): enabled = value
class View extends Node:
	var ui_host
	var modal_input := true
	var panel := PanelContainer.new()
	var closes := 0
	var pending_ticket := 17
	var play_enabled := true
	func _ready(): add_child(panel);panel.hide()
	func set_play_enabled(value):
		play_enabled=value
		if not value: close_panel()
	func open_panel():
		if ui_host.activate(self): panel.show()
	func close_panel():
		if panel.visible: closes += 1
		panel.hide()
		ui_host.release(self)
func _initialize(): call_deferred("run")
func run():
	var interaction := Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var first:=View.new();var second:=View.new();var inspector:=View.new();inspector.modal_input=false
	for view in [first,second,inspector]: root.add_child(view);host.register(view)
	first.open_panel()
	assert(first.panel.visible and host.active==first and interaction.construction_active)
	var cancellations:=interaction.cancelled
	second.open_panel()
	assert(not first.panel.visible and second.panel.visible and host.active==second and first.closes==1)
	assert(first.pending_ticket==17 and interaction.cancelled==cancellations+1,"Switch is immediate while old request is in flight; gesture cancelled once")
	first.close_panel()
	assert(host.active==second and interaction.construction_active,"Hidden close cannot release active owner")
	inspector.open_panel()
	assert(not second.panel.visible and inspector.panel.visible and not interaction.construction_active,"Inspector preserves map inspection input")
	host.set_overlay_blocked(true)
	first.open_panel()
	assert(host.active==inspector and interaction.shell_blocked,"Overlay denies panel activation and blocks map")
	host.set_overlay_blocked(false)
	first.open_panel()
	host.reset_local_views()
	assert(host.active==null and not first.panel.visible and not interaction.construction_active and first.pending_ticket==17,"Session/reset closes view without touching submitted request")
	second.open_panel();host.set_play_enabled(false);first.open_panel()
	assert(host.active==null and not second.panel.visible and not first.panel.visible and not interaction.enabled and not interaction.panel.visible,"Session play lock closes all views and blocks new opens")
	host.set_play_enabled(true);first.open_panel()
	assert(host.active==first and first.panel.visible and interaction.enabled)
	first.free()
	assert(host.active==null and not interaction.construction_active,"Freed active view releases ownership")
	second.free();inspector.free();host.free();interaction.free()
	print("UI_HOST_TEST_PASS")
	quit()
