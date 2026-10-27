extends Control
signal showing_changed(showing: bool)
const State=preload("res://scripts/native_hover_state.gd")
# Verbatim native204218 wrapping at the supported 24-cell minimap width.
const ACCESS_HELP = [
	["This option allows","visitors from outside","the fortress to enter","this location."],
	["This option allows","long-term residents of","the fortress to enter","this location."],
	["This option indicates","that the location is","only open to fortress","citizens."],
	["This option indicates","that the location is","only open to members."]]
const OWNER_RECENTER_HELP = ["Leave this menu and","recenter on this","creature."]
const OWNER_FILTER_HELP = ["Filter the unit list by","name or job."]
# Native staffindicatorhelp102205 and staffindicators091520 text-cell captures.
const STAFF_HELP={
	"tavern_keeper":["This creature is a","tavern keeper."],
	"performer":["This creature is a","performer."],
	"scholar":["This creature is a","scholar."],
	"scribe":["This creature is a","scribe."],
	"mercenary":["This creature is a","mercenary."],
	"monster_slayer":["This creature is a","monster slayer."],
	"doctor":["This creature is a","doctor."],
	"workshop":["This creature is","assigned to a specific","workshop."],
	"work_detail":["This creature is","assigned to a work","detail."]}
# Native specializationhover085117, hover259/260, exact24-cell wrapping.
const SPECIALIZATION_HELP = [
	["This worker is not","specialized and will do","any free tasks that","become available.","Click to toggle."],
	["This worker is","specialized and will","only do tasks that","match their workshop","assignments, work","details, and","occupations.  Click to","toggle."]]
const CONTAINMENT_HELP = [
	["The creature is chained."], ["The creature is caged."],
	["The creature is set to","be chained."], ["The creature is set to","be caged."]]
# Native squad renderer3ac631..3ac655, hover349..352; captured wrapping.
const SQUAD_HELP = {
	1:["Toggle whether the","squad will sleep here."],
	2:["Toggle whether the","squad will train here."],
	4:["Toggle whether the","soldiers will store","their individually","assigned weapons and","armor here."],
	8:["Toggle whether the","squad will store","squad-level equipment","here, such as","ammunition."]}
var state=State.new()
var art=preload("res://scripts/original_ui.gd").new()
var displayed := ""
var palette: Array[Color] = []
var widget_owner := 0
var widget_frame: Texture2D

func configure(source) -> void:
	art.configure(source);theme=art.theme
	if source.has_method("assets_root"):
		palette=art.installed_palette(source.assets_root())
		var bitmap:=Image.load_from_file(source.assets_root().path_join("data/art/border.png"))
		if bitmap!=null: widget_frame=ImageTexture.create_from_image(bitmap)
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=Vector2(200,216);hide()

func enter_access(owner: int, mode: int) -> void:
	if mode in [0,1,2,3]: state.enter(owner,str(mode),Time.get_ticks_msec())
	_process(0)

func enter_specialization(owner: int, specialized: bool) -> void:
	state.enter(owner,"specialization_"+str(int(specialized)),Time.get_ticks_msec());_process(0)

func enter_staff_indicator(owner: int, kind: String) -> void:
	if STAFF_HELP.has(kind):state.enter(owner,"staff_"+kind,Time.get_ticks_msec());_process(0)

func leave(owner: int) -> void:
	if widget_owner==owner: widget_owner=0
	state.leave(owner,Time.get_ticks_msec());_process(0)

func enter_owner_recenter(owner: int) -> void:
	state.enter(owner,"owner_recenter",Time.get_ticks_msec());_process(0)

func enter_containment(owner: int, relation: int) -> void:
	if relation in [1,2,3,4]: state.enter(owner,"containment_"+str(relation),Time.get_ticks_msec())
	_process(0)

func enter_squad_use(owner: int, use: int) -> void:
	if SQUAD_HELP.has(use): state.enter(owner,"squad_"+str(use),Time.get_ticks_msec())
	_process(0)

func enter_owner_filter(owner: int) -> void:
	# Native textbox widget logic activates immediately; it does not warm the
	# independent main-interface hover-instruction timer used by recenter.
	widget_owner=owner;_process(0)

func reset() -> void:
	widget_owner=0;state.reset();_process(0)

func layout(view: Vector2) -> void:
	position=Vector2(view.x-200,fposmod(view.y,12)*0.5)

func _process(_delta: float) -> void:
	var next: String=state.advance(Time.get_ticks_msec())
	if widget_owner!=0: next="owner_filter"
	if next==displayed: return
	displayed=next;visible=not displayed.is_empty();queue_redraw();showing_changed.emit(visible)

func _draw() -> void:
	if displayed.is_empty(): return
	var frame: Texture2D=widget_frame if displayed=="owner_filter" else art.texture("HOVER_RECTANGLE")
	if frame==null or theme.default_font==null: return
	# Native minimap frame clips its top and right borders at the screen edge.
	# Left/middle cells repeat for17 rows; row17 is the existing bottom border.
	for y in 18:
		for x in 25:
			var frame_y := 0 if displayed=="owner_filter" and y==0 else (24 if y==17 else 12)
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(0 if x==0 else 8,frame_y,8,12))
	var lines: Array
	if displayed.begins_with("specialization_"): lines=SPECIALIZATION_HELP[int(displayed.trim_prefix("specialization_"))]
	elif displayed.begins_with("staff_"): lines=STAFF_HELP[displayed.trim_prefix("staff_")]
	elif displayed.begins_with("squad_"): lines=SQUAD_HELP[int(displayed.trim_prefix("squad_"))]
	elif displayed.begins_with("containment_"): lines=CONTAINMENT_HELP[int(displayed.trim_prefix("containment_"))-1]
	else: lines=OWNER_RECENTER_HELP if displayed=="owner_recenter" else (OWNER_FILTER_HELP if displayed=="owner_filter" else ACCESS_HELP[int(displayed)])
	var offset := 1 if displayed=="owner_filter" else 0
	for row in lines.size():
		theme.default_font.draw_string(get_canvas_item(),Vector2(8,(row+1+offset)*12),lines[row],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	if displayed in ["owner_recenter","owner_filter"] and palette.size()==16:
		var baseline := 204 if displayed=="owner_filter" else 60
		theme.default_font.draw_string(get_canvas_item(),Vector2(8,baseline),"Hotkey: ",HORIZONTAL_ALIGNMENT_LEFT,-1,12,palette[15 if displayed=="owner_filter" else 7])
		theme.default_font.draw_string(get_canvas_item(),Vector2(72,baseline),"Ctrl+f" if displayed=="owner_filter" else "Ctrl+c",HORIZONTAL_ALIGNMENT_LEFT,-1,12,palette[10])
