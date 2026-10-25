extends SceneTree
const Hover=preload("res://scripts/tile_hover.gd")
const Contract=preload("res://scripts/management_contract.gd")
class HoverHarness extends Hover:
	func layout() -> void:pass
class HoverPanel extends Control:
	var entries:Array=[]
	func set_entries(value:Array):entries=value
class Actions extends RefCounted:
	var submitted=[]
	var detached=[]
	func submit(domain,request,observer):
		submitted.append({"domain":domain,"request":request,"observer":observer});return submitted.size()
	func detach(ticket):detached.append(ticket)
class Hud extends RefCounted:
	func ui_scale_vector():return Vector2.ONE
func _initialize():call_deferred("run")
func run():
	var hover=HoverHarness.new();hover.set_process(false)
	# Exercise the real request lifecycle without requiring game artwork.
	hover.panel=HoverPanel.new();hover.add_child(hover.panel)
	hover.actions=Actions.new();hover.hud=Hud.new()
	var a=Vector3i(118,45,165);var b=Vector3i(119,45,165)
	hover.observe(a,0.0);assert(hover.actions.submitted.size()==1)
	hover.observe(a,1.0);assert(hover.actions.submitted.size()==1)
	hover.observe(b,0.0);assert(hover.actions.detached==[1])
	var late=hover.actions.submitted[0].observer
	late.call(1,{"status":Contract.ManagementStatus.Ok,"world_hover":{"tile":a,"entries":[{"text":"STALE","foreground":1,"bright":true}]}},{})
	assert(hover.panel.entries.is_empty())
	hover.clear();hover.actions.submitted[1].observer.call(2,{"status":2,"world_hover":{"tile":b,"entries":[{"text":"STALE","foreground":1,"bright":true}]}},{})
	assert(hover.panel.entries.is_empty())
	hover.observe(a,0.0)
	hover.actions.submitted[2].observer.call(3,{"status":Contract.ManagementStatus.Ok},{})
	assert(not hover.panel.visible and hover.ticket==0)
	hover.observe(a,0.1);assert(hover.actions.submitted.size()==3)
	hover.observe(a,0.5);assert(hover.actions.submitted.size()==4)
	hover.clear();assert(hover.actions.detached==[1,2,4])
	hover.observe(a,0.0)
	var reply=hover.actions.submitted[4].observer
	reply.call(5,{"status":Contract.ManagementStatus.Ok,"world_hover":{"tile":a,"entries":[{"text":"Smooth dolomite Floor","foreground":1,"bright":true}]}},{})
	assert(hover.panel.visible and hover.panel.entries[0].text=="Smooth dolomite Floor" and hover.ticket==0)
	hover.observe(b,0.0)
	assert(not hover.panel.visible)
	reply.call(5,{"status":Contract.ManagementStatus.Ok,"world_hover":{"tile":a,"entries":[{"text":"STALE","foreground":1,"bright":true}]}},{})
	assert(not hover.panel.visible)
	hover.actions.submitted[5].observer.call(6,{"status":Contract.ManagementStatus.Ok,"world_hover":{"tile":a,"entries":[{"text":"WRONG TILE","foreground":1,"bright":true}]}},{})
	assert(not hover.panel.visible and hover.ticket==0)
	hover.clear()
	hover.free();print("TILE_HOVER_TEST_PASS");quit()
