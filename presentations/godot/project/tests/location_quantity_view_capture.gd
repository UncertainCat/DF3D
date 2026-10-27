extends SceneTree
const View=preload("res://scripts/location_quantity_view.gd")
const C=preload("res://scripts/management_contract.gd")
class State:
	extends RefCounted
	signal changed
	enum Phase { Ready, Editing, Rejected }
	var phase:=Phase.Ready
	var generation:=0
	var snapshot: Dictionary={}
	var calls: Array=[]
	func edit_quantity(quantity,mode,value):
		calls.append([quantity,mode,value]);phase=Phase.Editing;changed.emit()
	func complete():
		phase=Phase.Ready;changed.emit()
func _initialize() -> void:call_deferred("run")
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
	await process_frame
func key(code: int,unicode:=0) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.unicode=unicode;event.pressed=true;root.push_input(event,true)
	await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state=State.new();var view=View.new();root.add_child(view);view.configure(assets,state);view.layout(Vector2(1200,800))
	var font:=Image.load_from_file(assets.ui_font_path())
	var palette={7:Color8(192,192,192),15:Color.WHITE}
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_body.json"))
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-quantity-render")
	DirAccess.make_dir_recursive_absolute(directory)
	var cases:=0
	for sample in data.cases:
		var d: Dictionary=sample.details.duplicate(true)
		for name in ["kind","written_objects","desired_copies","dance_floor_x","dance_floor_y"]:d[name]=int(d[name])
		for name in d.facilities:d.facilities[name]=int(d.facilities[name])
		for supply in d.supplies:
			for name in supply:supply[name]=int(supply[name])
		state.snapshot=d;state.generation+=1;state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		image.save_png(directory.path_join("location_%d.png"%int(d.id)))
		for row in view.rows:
			cases+=1
			for action in 3:
				var expected: Image=assets.ui_texture(View.ICONS[action]).get_image()
				assert(expected.get_size()==Vector2i(32,36))
				var point: Vector2i=Vector2i(view.position+view.button_rect(row,action).position)
				for y in 36:
					for x in 32:
						var color:=expected.get_pixel(x,y)
						if color.a<0.99:continue
						var actual:=image.get_pixel(point.x+x,point.y+y)
						assert(absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)<0.035,"quantity icon pixels")
			for native_row in sample.expected:
				if int(native_row.y)!=int(row.y):continue
				for index in native_row.cells.size():
					var cell: Dictionary=native_row.cells[index];var ch:=int(cell.ch)
					var color: Color=palette[int(cell.fg)+(8 if cell.bold else 0)]
					for y in 12:
						for x in 8:
							var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
							if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
							var actual:=image.get_pixel((int(native_row.x)+index)*8+x,int(native_row.y)*12+4+y)
							assert(absf(actual.r-color.r)+absf(actual.g-color.g)+absf(actual.b-color.b)<0.035,"native quantity glyph position/color")
			var before: int=state.calls.size()
			await click(view.position+view.button_rect(row,0).get_center())
			assert(view.workflow.editing==int(row.quantity) and view.workflow.text=="" and state.calls.size()==before)
			await key(KEY_3,51);assert(state.calls[-1]==[int(row.quantity),0,3]);state.complete()
			await click(view.position+view.button_rect(row,1).get_center())
			assert(state.calls[-1]==[int(row.quantity),1,0] and view.workflow.text=="3");state.complete()
			await key(KEY_LEFT);await key(KEY_4,52)
			assert(state.calls[-1]==[int(row.quantity),0,34]);state.complete()
			await click(Vector2(900,190));await key(KEY_5,53)
			assert(state.calls[-1]==[int(row.quantity),0,345]);state.complete()
			before=state.calls.size();await key(KEY_6,54);await key(KEY_A,97)
			assert(state.calls.size()==before and view.workflow.text=="345")
			await key(KEY_BACKSPACE);assert(state.calls[-1]==[int(row.quantity),0,34]);state.complete()
			await click(view.position+view.button_rect(row,2).get_center())
			assert(state.calls[-1]==[int(row.quantity),2,0]);state.complete()
			await key(KEY_ENTER);assert(view.workflow.editing==-1)
			view.actions_enabled=false;before=state.calls.size();await click(view.position+view.button_rect(row,1).get_center())
			assert(state.calls.size()==before);view.actions_enabled=true
	assert(cases==13,"quantity render field coverage")
	view.queue_free();assets.queue_free();await process_frame
	print("LOCATION_QUANTITY_VIEW_CAPTURE_PASS cases=",cases);quit(0)
