extends "res://scripts/cage_sheet_view.gd"
# Native196637/19836c/18b841; semantic choices and effects remain bridge-owned.
const NameColor=preload("res://scripts/native_name_color.gd")
const BAIT_VALUES=[48,49,44,-1]
const BAIT_ART=["MEAT","FISH","GEM","NONE"]
func bait_rect(index: int) -> Rect2:return Rect2(16+24*index,132,24,36)
func hive_rect(install: bool) -> Rect2:return Rect2(16,72 if install else 108,24,36)
func _process(delta: float) -> void:
	super._process(delta)
	if state!=null and is_visible_in_tree() and int(state.snapshot.get("nest",{}).get("name_color",{}).get("effect",0))>0:queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if not removing and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var trap: Dictionary=state.snapshot.get("trap",{})
		if trap.get("state",-1)==1:
			for index in 4:
				if bait_rect(index).has_point(event.position):state.set_trap_bait(BAIT_VALUES[index]);accept_event();return
		var hive: Dictionary=state.snapshot.get("hive",{})
		if not hive.is_empty():
			for install in [true,false]:
				if hive_rect(install).has_point(event.position):state.set_hive_setting(install,(hive.flags & (1 if install else 2))==0);accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if removing or state.snapshot.is_empty() or colors.size()!=16 or theme.default_font==null:return
	var nest: Dictionary=state.snapshot.get("nest",{})
	if not nest.is_empty():
		_body_text(nest.status,Vector2(16,96))
		if nest.claimant_id>=0:
			var ink:=NameColor.choose(nest.name_color,Time.get_ticks_msec(),randi_range(0,1) if nest.name_color.effect==3 else 0)
			if not ink.is_empty():_body_text(nest.name,Vector2(16,108),int(ink[0])+8*int(ink[2]))
	var trap: Dictionary=state.snapshot.get("trap",{})
	if not trap.is_empty():
		_body_text(trap.status,Vector2(16,96))
		if trap.state>=2:_body_text(trap.name,Vector2(16,108))
		elif trap.state==1:
			for index in 4:
				var texture: Texture2D=art.texture("BUILDING_INFO_ANIMAL_TRAP_"+BAIT_ART[index]+("_ACTIVE" if trap.bait_type==BAIT_VALUES[index] else ""))
				if texture!=null:draw_texture_rect(texture,bait_rect(index),false)
	var hive: Dictionary=state.snapshot.get("hive",{})
	if hive.is_empty():return
	var install: bool=(hive.flags&1)!=0
	var gather: bool=(hive.flags&2)!=0
	for installing in [true,false]:
		var enabled: bool=install if installing else gather
		var texture: Texture2D=art.texture("BUILDING_INFO_ACTIVE" if enabled else "BUILDING_INFO_INACTIVE")
		if texture!=null:draw_texture_rect(texture,hive_rect(installing),false)
	_body_text("Install colony when ready" if install else "Do not install colony",Vector2(48,96))
	if install:
		_body_text("   * Requires wild colony or",Vector2(48,108),7)
		_body_text("   * Existing hive",Vector2(48,120),7)
	_body_text("Gather any products" if gather else "Do not gather products",Vector2(48,132))
	_body_text("   * Destroys colony" if gather else "   * Saves colony for split",Vector2(48,144),7)
	if gather:_body_text("   * Requires a jug",Vector2(48,156),7)
	_body_text("Outdoor access" if hive.outdoor_access else "No outdoor access",Vector2(16,180),10 if hive.outdoor_access else 12)
	_body_text("Ready to be split" if (hive.flags&4)!=0 else "Not ready to be split",Vector2(16,204),10 if (hive.flags&4)!=0 else 8)
	if hive.crowding>0:
		_body_text("Too many hives",Vector2(16,228),12 if hive.crowding==2 else 14)
		_body_text("* No output" if hive.crowding==2 else "* Output restricted",Vector2(16,240),4 if hive.crowding==2 else 6)
