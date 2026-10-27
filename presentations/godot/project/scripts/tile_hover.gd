extends CanvasLayer
# Native prose only. The service owns transport; this view owns hover identity.
const Contract=preload("res://scripts/management_contract.gd")
var world
var hud
var camera
var actions
var panel: Control
var target := Vector3i(-1,-1,-1)
var ticket := 0
var generation := 0
var refresh := 0.0
var obscured := false

func set_obscured(value: bool) -> void:
	obscured=value
	if value:clear()

func _ready() -> void:
	layer=1
	panel=preload("res://scripts/terrain_hover_view.gd").new();add_child(panel)
	panel.configure(world);panel.hide()
	if actions!=null: actions.session_changed.connect(clear)

func clear() -> void:
	generation+=1
	if ticket!=0 and actions!=null: actions.detach(ticket)
	ticket=0;target=Vector3i(-1,-1,-1);refresh=0.0
	if panel!=null: panel.hide()

func observe(tile:Vector3i,delta:float) -> void:
	if obscured:return
	if tile!=target:
		clear();target=tile
	if tile.x<0 or tile.y<0 or tile.z<0 or actions==null: return
	refresh-=delta
	if ticket!=0 or refresh>0.0: return
	var identity=generation
	ticket=actions.submit("hover",{"action":Contract.ManagementAction.WorldHover,"origin":tile},
		func(_ticket:int,result:Dictionary,_request:Dictionary): receive(identity,tile,result))
	refresh=0.5

func receive(identity:int,tile:Vector3i,result:Dictionary) -> void:
	if identity!=generation or tile!=target:return
	ticket=0
	var value:Dictionary=result.get("world_hover",{})
	if result.get("status",-1)!=Contract.ManagementStatus.Ok or value.get("tile",Vector3i(-1,-1,-1))!=target:
		panel.hide();return
	panel.set_entries(value.get("entries",[]))
	panel.visible=not panel.entries.is_empty()
	layout()

func layout() -> void:
	var factor:Vector2=hud.ui_scale_vector()
	scale=factor
	var view=get_viewport().get_visible_rect().size/factor
	panel.layout(view)

func _process(delta:float) -> void:
	if obscured:return
	if hud==null or not hud.visible or not hud.enabled or hud.menu_open() or hud.interaction.construction_active or not world.terrain_loaded():
		clear();return
	if get_viewport().gui_get_hovered_control()!=null:
		clear();return
	var mouse=get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse):clear();return
	var tile:Vector3i=world.pick_tile(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse),world.get_top_z())
	observe(tile,delta)
	if panel.visible:layout()

func _exit_tree() -> void:
	clear()
