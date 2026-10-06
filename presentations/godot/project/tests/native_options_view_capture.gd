extends SceneTree
var requests:Array[String]=[]
var dismissals:=0
var allow_input:=true
class BackObserver extends Node:
	var events:=0
	func _unhandled_input(event:InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:events+=1
		elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:events+=1
func click_at(point:Vector2,button:int=MOUSE_BUTTON_LEFT) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=button;event.pressed=true;Input.parse_input_event(event)
	await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event)
	await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(77); return
	root.size=Vector2i(1200,800)
	var assets:=Df3dWorld.new();root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/native_options_view.gd").new()
	root.add_child(view);view.configure(assets);view.layout_reference()
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image()
	var expected:=Image.create(504,384,false,Image.FORMAT_RGBA8)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_options_frame.json"))
	var mapping:Dictionary={}
	for entry in [["HOVER_RECTANGLE",119288],["BUTTON_CATEGORY_RECTANGLE",120311]]:
		var texture:Image=assets.ui_texture(entry[0]).get_image()
		for y in 3:
			for x in 3:mapping[entry[1]+y*64+x]=texture.get_region(Rect2i(x*8,y*12,8,12))
	for run in data.background_runs:
		var tile:=int(run[3])
		if not mapping.has(tile):push_error("Unmapped native Options tile");quit(1);return
		for offset in int(run[2]):expected.blit_rect(mapping[tile],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,(int(run[1])-20)*12))
	var font:=Image.load_from_file(assets.ui_font_path())
	font.convert(Image.FORMAT_RGBA8)
	# DF's bitmap uses black/magenta as background, not opaque glyph ink.
	for y in font.get_height():
		for x in font.get_width():
			var pixel:=font.get_pixel(x,y)
			var keyed:=pixel.r>0.99 and pixel.b>0.99 and pixel.g<0.01
			font.set_pixel(x,y,Color(1,1,1,0 if keyed else maxf(pixel.r,maxf(pixel.g,pixel.b))*pixel.a))
	for glyph in data.glyphs:
		if int(glyph[3])!=15:push_error("Unmapped native Options text color");quit(1);return
		var ch:=int(glyph[2])
		expected.blend_rect(font,Rect2i((ch%16)*8,(ch/16)*12,8,12),Vector2i((int(glyph[0])-43)*8,(int(glyph[1])-20)*12))
	var mismatch:=0
	for y in 384:
		for x in 504:
			var a:=actual.get_pixel(344+x,244+y);var b:=expected.get_pixel(x,y)
			if b.a<0.99:continue
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
	var directory:=ProjectSettings.globalize_path("res://../../../build/qa/native-options-render")
	DirAccess.make_dir_recursive_absolute(directory)
	actual.save_png(directory.path_join("actual.png"));expected.save_png(directory.path_join("expected.png"))
	if mismatch:push_error("Native Options pixel mismatch: %d"%mismatch);quit(1);return
	view.option_requested.connect(func(token):requests.append(token))
	view.dismissed.connect(func():dismissals+=1)
	view.input_allowed=func():return allow_input
	for sample in [[Vector2i(960,600),Vector2(224,144)],[Vector2i(1600,900),Vector2(544,288)]]:
		root.size=sample[0]
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		if view.position!=sample[1]:push_error("Options resize anchor mismatch");quit(1);return
		actual=root.get_texture().get_image()
		for y in 384:
			for x in 504:
				var a:=actual.get_pixel(int(view.position.x)+x,int(view.position.y)+y);var b:=expected.get_pixel(x,y)
				if b.a>=0.99 and absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:
					push_error("Resized Options pixel mismatch");quit(1);return
		await click_at(view.position+Vector2(252,66))
		if requests!=["SAVE_AND_QUIT"]:push_error("Resized Options pointer mismatch");quit(1);return
		requests.clear()
	root.size=Vector2i(1200,800)
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	for index in view.OPTIONS.size():await click_at(Vector2(600,310+index*36))
	var native=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_escape_dispatch.json"))
	var tokens:Array[String]=[]
	for option in native.native_options.options:tokens.append(option.token)
	if requests!=tokens:push_error("Native Options pointer target mismatch");quit(1);return
	await click_at(Vector2(360,260))
	if requests!=tokens:push_error("Options background issued action");quit(1);return
	await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape);await process_frame
	if dismissals!=2:push_error("Top-level Options dismissal mismatch");quit(1);return
	allow_input=false
	await click_at(Vector2(600,310));await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	Input.parse_input_event(escape);await process_frame
	if requests!=tokens or dismissals!=2:push_error("Child owner failed to block top-level Options input");quit(1);return
	allow_input=true;view.hide()
	await click_at(Vector2(600,310));Input.parse_input_event(escape);await process_frame
	if requests!=tokens or dismissals!=2:push_error("Hidden Options consumed input");quit(1);return
	var confirmation=preload("res://scripts/native_options_confirmation.gd").new()
	root.add_child(confirmation);confirmation.configure(assets);confirmation.layout_reference()
	var underlying:=BackObserver.new();root.add_child(underlying)
	var confirmations:Array[String]=[];var cancels:Array[bool]=[]
	confirmation.confirmed.connect(func(token):confirmations.append(token))
	confirmation.cancelled.connect(func():cancels.append(true))
	confirmation.input_allowed=func():return allow_input
	var confirmation_data=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_options_confirmations.json"))
	var button:Image=assets.ui_texture("HORIZONTAL_OPTION_REMOVE").get_image()
	for y in 3:
		for x in 3:mapping[130435+y*6+x]=button.get_region(Rect2i(x*8,y*12,8,12))
	for sample in confirmation_data.cases:
		confirmation.display(sample.token)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		actual=root.get_texture().get_image();expected=Image.create(504,120,false,Image.FORMAT_RGBA8)
		for run in sample.background_runs:
			if not mapping.has(int(run[3])):push_error("Unmapped native confirmation tile");quit(1);return
			for offset in int(run[2]):expected.blit_rect(mapping[int(run[3])],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,(int(run[1])-29)*12))
		for glyph in sample.glyphs:
			if int(glyph[3])!=15:push_error("Unmapped confirmation text color");quit(1);return
			var ch:=int(glyph[2])
			expected.blend_rect(font,Rect2i((ch%16)*8,(ch/16)*12,8,12),Vector2i((int(glyph[0])-43)*8,(int(glyph[1])-29)*12))
		mismatch=0
		for y in 120:
			for x in 504:
				var a:=actual.get_pixel(344+x,352+y);var b:=expected.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
		actual.save_png(directory.path_join(sample.token+".png"))
		if mismatch:push_error("Native confirmation pixel mismatch: %s %d"%[sample.token,mismatch]);quit(1);return
		for resized in [[Vector2i(960,600),Vector2(224,252)],[Vector2i(1600,900),Vector2(544,396)]]:
			root.size=resized[0]
			for i in 3:await process_frame;await RenderingServer.frame_post_draw
			if confirmation.position!=resized[1]:push_error("Confirmation resize anchor mismatch");quit(1);return
			actual=root.get_texture().get_image()
			for y in 120:
				for x in 504:
					var a:=actual.get_pixel(int(confirmation.position.x)+x,int(confirmation.position.y)+y);var b:=expected.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:
						push_error("Resized confirmation pixel mismatch");quit(1);return
			var prior_confirmations:=confirmations.size();var prior_cancels:=cancels.size()
			Input.parse_input_event(escape);await process_frame
			await click_at(Vector2(20,20),MOUSE_BUTTON_RIGHT)
			if underlying.events!=0 or confirmations.size()!=prior_confirmations or cancels.size()!=prior_cancels:
				push_error("Resized confirmation Back input mismatch");quit(1);return
			await click_at(confirmation.position+Vector2(40,90))
			await click_at(confirmation.position+Vector2(448,90))
			if confirmations.size()!=prior_confirmations+1 or confirmations.back()!=sample.token or cancels.size()!=prior_cancels+1:
				push_error("Resized confirmation pointer mismatch");quit(1);return
			confirmations.pop_back();cancels.pop_back()
		root.size=Vector2i(1200,800)
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var confirmations_before:=confirmations.size();var cancels_before:=cancels.size()
		Input.parse_input_event(escape);await process_frame
		await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
		if underlying.events!=0 or confirmations.size()!=confirmations_before or cancels.size()!=cancels_before or not confirmation.visible:
			push_error("Native confirmation Back input leaked, cancelled or confirmed");quit(1);return
		await click_at(Vector2(384,442));await click_at(Vector2(792,442))
		if confirmations.back()!=sample.token or cancels.size()!=confirmations.size():push_error("Confirmation pointer routing mismatch");quit(1);return
	allow_input=false
	await click_at(Vector2(384,442));await click_at(Vector2(792,442))
	if confirmations.size()!=confirmation_data.cases.size() or cancels.size()!=confirmation_data.cases.size():push_error("Pending confirmation accepted another input");quit(1);return
	allow_input=true;confirmation.display("unknown fixture token")
	await click_at(Vector2(384,442))
	if confirmation.visible or confirmations.size()!=confirmation_data.cases.size():push_error("Unknown confirmation remained actionable");quit(1);return
	Input.parse_input_event(escape);await process_frame
	await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	if underlying.events!=2:push_error("Hidden confirmation intercepted Back input");quit(1);return
	var naming=preload("res://scripts/native_save_name_view.gd").new()
	root.add_child(naming);naming.configure(assets);naming.layout_reference()
	var naming_data=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_save_name.json"))
	for sample in naming_data.cases:
		var entry:Dictionary=sample.input
		if entry.get("reset",false):naming.begin_entry()
		elif entry.has("text"):
			for character in str(entry.text):
				var typed:=InputEventKey.new();typed.pressed=true;typed.unicode=character.unicode_at(0)
				root.push_input(typed,true);typed.pressed=false;root.push_input(typed,true);await process_frame
		else:
			var typed:=InputEventKey.new();typed.pressed=true
			typed.keycode={"LEFT":KEY_LEFT,"HOME":KEY_HOME,"BACKSPACE":KEY_BACKSPACE}[entry.key]
			root.push_input(typed,true);typed.pressed=false;root.push_input(typed,true);await process_frame
		if naming.name_bytes!=PackedByteArray(sample.bytes):push_error("Native save-name byte editing mismatch step%d actual=%s expected=%s"%[int(sample.step),str(naming.name_bytes),str(sample.bytes)]);quit(1);return
		naming.ticks_override=0 if sample.cursor else 750;naming._process(0);naming.queue_redraw()
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		actual=root.get_texture().get_image();expected=Image.create(504,144,false,Image.FORMAT_RGBA8)
		for run in sample.background_runs:
			if not mapping.has(int(run[3])):push_error("Unmapped native save-name tile");quit(1);return
			for offset in int(run[2]):expected.blit_rect(mapping[int(run[3])],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,(int(run[1])-28)*12))
		for glyph in sample.glyphs:
			if int(glyph[3]) not in [11,15]:push_error("Unmapped save-name text color");quit(1);return
			var ch:=int(glyph[2])
			var ink:=font.get_region(Rect2i((ch%16)*8,(ch/16)*12,8,12))
			if int(glyph[3])==11:
				for y in 12:
					for x in 8:
						var color:=Color8(18,254,207);color.a=ink.get_pixel(x,y).a;ink.set_pixel(x,y,color)
			expected.blend_rect(ink,Rect2i(0,0,8,12),Vector2i((int(glyph[0])-43)*8,(int(glyph[1])-28)*12))
		mismatch=0
		for y in 144:
			for x in 504:
				var a:=actual.get_pixel(344+x,340+y);var b:=expected.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
		actual.save_png(directory.path_join("save_name_%d.png"%int(sample.step)))
		if mismatch:push_error("Native save-name pixel mismatch: %d %d"%[sample.step,mismatch]);quit(1);return
		if sample==naming_data.cases.back() and not await check_name_resize(naming,expected):quit(1);return
	for sample in naming_data.cursor_samples:
		naming.ticks_override=int(sample.before);naming._process(0)
		if naming.cursor_visible!=(int(sample.ch)==95):push_error("Native cursor timestamp mismatch");quit(1);return
	var name_cancels:Array[bool]=[]
	naming.cancelled.connect(func():name_cancels.append(true))
	Input.parse_input_event(escape);await process_frame
	await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	if underlying.events!=2 or not name_cancels.is_empty():push_error("Naming prompt leaked or dismissed Back input");quit(1);return
	await click_at(Vector2(792,426))
	if name_cancels.size()!=1:push_error("Native naming Cancel target mismatch");quit(1);return
	naming.queue_free()
	underlying.queue_free()
	confirmation.queue_free()
	view.queue_free();await process_frame
	for kind in ["empty","single","two"]:
		if not await check_small_save_return(assets,font,mapping,directory,kind):quit(1);return
	if not await check_multiple_save_return(assets,font,mapping,directory):quit(1);return
	if not await check_timeline_name(assets,font,mapping,directory):quit(1);return
	if not await check_composition(assets):quit(1);return
	assets.queue_free();await process_frame
	print("NATIVE_OPTIONS_VIEW_CAPTURE_PASS pixels=193536");quit(0)

func check_small_save_return(assets, font: Image, mapping: Dictionary, directory: String, kind:String) -> bool:
	var chooser=preload("res://scripts/native_save_return_view.gd").new()
	root.add_child(chooser);chooser.configure(assets);chooser.layout_reference()
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_save_return_%s.json"%kind))
	var folders:Array=[]
	for folder in data.get("folders",[]):folders.append(folder.name if folder is Dictionary else folder)
	var destinations:Array=[]
	for folder in folders:destinations.append({"id":"owned-"+folder,"folder":folder})
	if not chooser.set_destinations(destinations):return false
	var origin_y:int=data.origin_cells[1]
	var height:int=data.size_cells[1]*12
	var native_position:=Vector2(344,origin_y*12+4)
	if chooser.position!=native_position:
		push_error("Save-return screen placement differs from native character grid");return false
	var expected:=Image.create(504,height,false,Image.FORMAT_RGBA8)
	for run in data.background_runs:
		if not mapping.has(int(run[3])):push_error("Unmapped save-return background");return false
		for offset in int(run[2]):expected.blit_rect(mapping[int(run[3])],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,(int(run[1])-origin_y)*12))
	for glyph in data.glyphs:
		var colors:Dictionary={7:Color8(192,192,192),10:Color8(19,253,101),12:Color8(255,113,17),14:Color8(255,225,17),15:Color.WHITE}
		if not colors.has(int(glyph[3])):push_error("Unmapped save-return text color");return false
		var ch:=int(glyph[2])
		var ink:=font.get_region(Rect2i((ch%16)*8,(ch/16)*12,8,12))
		for y in 12:
			for x in 8:
				var color:Color=colors[int(glyph[3])];color.a=ink.get_pixel(x,y).a;ink.set_pixel(x,y,color)
		expected.blend_rect(ink,Rect2i(0,0,8,12),Vector2i((int(glyph[0])-43)*8,(int(glyph[1])-origin_y)*12))
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image()
	actual.save_png(directory.path_join("save_return_%s.png"%kind))
	var mismatch:=0
	for y in height:
		for x in 504:
			var a:=actual.get_pixel(344+x,int(native_position.y)+y);var b:=expected.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
	if mismatch:push_error("Native save-return pixel mismatch: %d"%mismatch);return false
	var selected:Array[String]=[]
	chooser.option_requested.connect(func(token):selected.append(token))
	chooser.destination_requested.connect(func(id):selected.append("destination:"+id))
	for index in chooser.entries.size():await click_at(Vector2(600,chooser.position.y+66+index*36))
	var expected_actions:Array[String]=["SAVE_TO_NEW_FOLDER_NEW_TIMELINE","SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE","RETURN"]
	for index in range(folders.size()-1,-1,-1):expected_actions.push_front("destination:owned-"+folders[index])
	if selected!=expected_actions:
		push_error("Save-return action mapping differs from native catalog");return false
	chooser.queue_free();await process_frame
	return true

func check_multiple_save_return(assets, font: Image, mapping: Dictionary, directory: String) -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_save_return_multiple.json"))
	var chooser=preload("res://scripts/native_save_return_view.gd").new()
	root.add_child(chooser);chooser.configure(assets)
	var destinations:Array=[]
	for index in data.folders.size():destinations.append({"id":"fixture-%d"%index,"folder":data.folders[index]})
	if not chooser.set_destinations(destinations):push_error("Native multiple catalog rejected");return false
	var expected:=Image.create(504,792,false,Image.FORMAT_RGBA8)
	for run in data.background_runs:
		if not mapping.has(int(run[3])):push_error("Unmapped multiple-destination background");return false
		for offset in int(run[2]):expected.blit_rect(mapping[int(run[3])],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,int(run[1])*12))
	for glyph in data.glyphs:
		if int(glyph[3]) not in [14,15]:push_error("Unmapped multiple-destination text color");return false
		var ch:=int(glyph[2]);var ink:=font.get_region(Rect2i((ch%16)*8,(ch/16)*12,8,12))
		if int(glyph[3])==14:
			for y in 12:
				for x in 8:
					var color:=Color8(255,225,17);color.a=ink.get_pixel(x,y).a;ink.set_pixel(x,y,color)
		expected.blend_rect(ink,Rect2i(0,0,8,12),Vector2i((int(glyph[0])-43)*8,int(glyph[1])*12))
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();var mismatch:=0
	actual.save_png(directory.path_join("save_return_multiple.png"))
	for y in 792:
		for x in 504:
			var a:=actual.get_pixel(344+x,4+y);var b:=expected.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
	if mismatch:push_error("Native multiple-destination pixel mismatch: %d"%mismatch);return false
	var selected:Array[String]=[]
	chooser.destination_requested.connect(func(id):selected.append(id))
	for index in destinations.size():
		var y:float=chooser.position.y+66+index*36
		if y>=16 and y<784:
			await click_at(Vector2(600,y))
			if selected.back()!=destinations[index].id:push_error("Clipped catalog lost destination identity");return false
	chooser.queue_free();await process_frame
	return true

func check_timeline_name(assets, font: Image, mapping: Dictionary, directory: String) -> bool:
	var naming=preload("res://scripts/native_timeline_name_view.gd").new()
	root.add_child(naming);naming.configure(assets);naming.layout_reference()
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_timeline_name.json"))
	var cancellations:Array[bool]=[]
	naming.cancelled.connect(func():cancellations.append(true))
	for sample in data.cases:
		var entry:Dictionary=sample.input
		if entry.get("reset",false):naming.begin_entry()
		if entry.has("key"):
			if entry.key=="RIGHT_CLICK":await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
			else:
				var key:=InputEventKey.new();key.pressed=true
				key.keycode={"BACKSPACE":KEY_BACKSPACE,"HOME":KEY_HOME,"ESCAPE":KEY_ESCAPE}[entry.key]
				root.push_input(key,true);key.pressed=false;root.push_input(key,true);await process_frame
		if entry.has("text"):
			for character in str(entry.text):
				var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0)
				root.push_input(key,true);key.pressed=false;root.push_input(key,true);await process_frame
		if naming.name_bytes!=PackedByteArray(sample.bytes) or not cancellations.is_empty():
			push_error("Timeline native bytes/Back differ at step%d"%int(sample.step));return false
		naming.ticks_override=0 if sample.cursor else 750;naming._process(0);naming.queue_redraw()
		var expected:=Image.create(504,144,false,Image.FORMAT_RGBA8)
		for run in sample.background_runs:
			if not mapping.has(int(run[3])):push_error("Unmapped timeline background");return false
			for offset in int(run[2]):expected.blit_rect(mapping[int(run[3])],Rect2i(0,0,8,12),Vector2i((int(run[0])+offset-43)*8,(int(run[1])-28)*12))
		for glyph in sample.glyphs:
			if int(glyph[3]) not in [11,15]:push_error("Unmapped timeline text color");return false
			var ch:=int(glyph[2]);var ink:=font.get_region(Rect2i((ch%16)*8,(ch/16)*12,8,12))
			if int(glyph[3])==11:
				for y in 12:
					for x in 8:
						var color:=Color8(18,254,207);color.a=ink.get_pixel(x,y).a;ink.set_pixel(x,y,color)
			expected.blend_rect(ink,Rect2i(0,0,8,12),Vector2i((int(glyph[0])-43)*8,(int(glyph[1])-28)*12))
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		var actual:=root.get_texture().get_image();var mismatch:=0
		actual.save_png(directory.path_join("timeline_name_%d.png"%int(sample.step)))
		for y in 144:
			for x in 504:
				var a:=actual.get_pixel(344+x,340+y);var b:=expected.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:mismatch+=1
		if mismatch:push_error("Native timeline pixel mismatch: %d step%d"%[mismatch,int(sample.step)]);return false
		if sample==data.cases.back():
			if not await check_name_resize(naming,expected):return false
			cancellations.clear()
	await click_at(Vector2(792,426))
	if cancellations.size()!=1:push_error("Timeline Cancel target mismatch");return false
	naming.queue_free();await process_frame
	return true

func check_composition(assets) -> bool:
	var owner=preload("res://scripts/native_options.gd").new()
	root.add_child(owner);owner.configure(assets)
	var closed:Array[bool]=[];var actions:Array[String]=[]
	var save_requests:Array[PackedByteArray]=[]
	owner.save_requested.connect(func(bytes):save_requests.append(bytes))
	owner.dismissed.connect(func():closed.append(true))
	owner.confirmed.connect(func(token):actions.append(token))
	owner.route_requested.connect(func(token):actions.append(token))
	owner.open();await process_frame
	# These are the native pointer targets from the component fixtures. The
	# composition must restore the menu after Cancel without leaking Back to it.
	for index in [2,3,4]:
		await click_at(Vector2(600,310+index*36))
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
		root.push_input(escape,true);escape.pressed=false;root.push_input(escape,true)
		await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
		# An underlying menu target outside the child must also remain inert.
		await click_at(Vector2(600,526))
		if owner.page!=owner.Page.CONFIRMATION or not closed.is_empty() or not actions.is_empty():
			push_error("Composed confirmation leaked input to menu");return false
		await click_at(Vector2(792,442))
		if owner.page!=owner.Page.MENU:
			push_error("Composed confirmation Cancel did not restore menu");return false
	await click_at(Vector2(600,346))
	var typed:=InputEventKey.new();typed.pressed=true;typed.unicode=97
	root.push_input(typed,true);typed.pressed=false;root.push_input(typed,true)
	var submit:=InputEventKey.new();submit.keycode=KEY_ENTER;submit.pressed=true
	root.push_input(submit,true);submit.pressed=false;root.push_input(submit,true)
	if save_requests.size()!=1 or save_requests[0]!=PackedByteArray([97]) or owner.page!=owner.Page.NAME:
		push_error("Naming submission lost bytes or closed before session acceptance");return false
	owner.show_overwrite();await process_frame
	submit.pressed=true;root.push_input(submit,true);submit.pressed=false;root.push_input(submit,true)
	if save_requests.size()!=1:
		push_error("Inactive naming child submitted through overwrite confirmation");return false
	typed.pressed=true;typed.unicode=98;root.push_input(typed,true)
	typed.pressed=false;root.push_input(typed,true)
	owner.open()
	await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	if owner.page!=owner.Page.CONFIRMATION or owner.naming.name_bytes!=PackedByteArray([97]):
		push_error("Overwrite child lost ownership or modified naming draft");return false
	await click_at(Vector2(792,442))
	if owner.page!=owner.Page.NAME or owner.naming.name_bytes!=PackedByteArray([97]):
		push_error("Overwrite Cancel failed to restore retained name");return false
	await click_at(Vector2(792,426))
	if owner.page!=owner.Page.MENU:
		push_error("Naming Cancel did not restore menu");return false
	await click_at(Vector2(600,346))
	if not owner.naming.name_bytes.is_empty():
		push_error("New naming entry retained previous cancelled draft");return false
	await click_at(Vector2(792,426))
	owner.input_allowed=func():return false
	await click_at(Vector2(600,526));await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	if owner.page!=owner.Page.MENU or not closed.is_empty():
		push_error("Denied Options owner accepted dismissal");return false
	owner.input_allowed=Callable()
	await click_at(Vector2(600,526))
	if owner.page!=owner.Page.CLOSED or closed.size()!=1 or not actions.is_empty():
		push_error("Composed Return failed or cancellation emitted session action");return false
	var timeline_requests:Array[PackedByteArray]=[]
	owner.timeline_requested.connect(func(bytes):timeline_requests.append(bytes))
	owner.open();await process_frame
	await click_at(Vector2(600,310))
	if actions!=["SAVE_AND_QUIT"] or owner.page!=owner.Page.MENU:
		push_error("SaveReturn bypassed its catalog request");return false
	owner.show_save_return([]);await process_frame
	await click_at(Vector2(600,382))
	if owner.page!=owner.Page.TIMELINE_NAME:
		push_error("New-timeline route did not acquire naming ownership");return false
	typed.pressed=true;typed.unicode=47;root.push_input(typed,true);typed.pressed=false;root.push_input(typed,true)
	var back:=InputEventKey.new();back.keycode=KEY_ESCAPE;back.pressed=true
	root.push_input(back,true);back.pressed=false;root.push_input(back,true)
	await click_at(Vector2(20,700),MOUSE_BUTTON_RIGHT)
	await click_at(Vector2(600,418))
	owner.show_save_return([])
	if owner.page!=owner.Page.TIMELINE_NAME or owner.timeline_naming.name_bytes!=PackedByteArray([47]) or actions.size()!=1 or closed.size()!=1:
		push_error("Timeline child lost draft or leaked input to chooser");return false
	submit.pressed=true;root.push_input(submit,true);submit.pressed=false;root.push_input(submit,true)
	if timeline_requests!=[PackedByteArray([47])] or save_requests.size()!=1:
		push_error("Timeline intent reached the manual-save route or lost bytes");return false
	await click_at(Vector2(792,426))
	if owner.page!=owner.Page.RETURN_CHOICES:
		push_error("Timeline Cancel did not restore destination chooser");return false
	owner.session_busy=true
	await click_at(Vector2(600,418))
	if actions.size()!=1:push_error("Busy owner accepted a destination action");return false
	owner.session_busy=false
	await click_at(Vector2(600,418))
	if actions!=["SAVE_AND_QUIT","SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE"]:
		push_error("Explicit same-timeline action lost identity");return false
	owner.close()
	owner.open();await process_frame
	var destinations:Array[String]=[]
	owner.destination_requested.connect(func(id):destinations.append(id))
	var catalog:Array=[{"id":"owned-region16","folder":"region16"}]
	if owner.show_save_return([{"id":"missing-folder"}]) or owner.page!=owner.Page.MENU:
		push_error("Invalid catalog was displayed as an empty chooser");return false
	if not owner.show_save_return(catalog):
		push_error("Valid destination catalog was rejected");return false
	# Later changes in a caller's array cannot retarget the displayed row.
	catalog[0].id="different-destination"
	owner.session_busy=true
	await click_at(Vector2(600,364))
	if not destinations.is_empty():push_error("Busy chooser sent a destination");return false
	owner.session_busy=false
	await click_at(Vector2(600,364))
	if destinations!=["owned-region16"] or owner.page!=owner.Page.RETURN_CHOICES:
		push_error("Destination click lost identity or assumed save success");return false
	await click_at(Vector2(600,400))
	if owner.show_save_return([]) or owner.page!=owner.Page.TIMELINE_NAME:
		push_error("Late catalog replaced the active naming child");return false
	await click_at(Vector2(600,364))
	if destinations.size()!=1:push_error("Inactive chooser sent a destination");return false
	await click_at(Vector2(792,426))
	if owner.return_choices.destination_ids!=["owned-region16"]:
		push_error("Timeline Cancel lost its destination catalog");return false
	await click_at(Vector2(600,472))
	owner.open()
	if not owner.show_save_return([]) or not owner.return_choices.destination_ids.is_empty():
		push_error("Empty catalog retained a previous destination");return false
	owner.close()
	owner.queue_free();await process_frame
	return true

func check_name_resize(naming, expected:Image) -> bool:
	var original_bytes:PackedByteArray=naming.name_bytes.duplicate()
	var cancellations:Array[bool]=[]
	var on_cancel:=func():cancellations.append(true)
	naming.cancelled.connect(on_cancel)
	for sample in [[Vector2i(960,600),Vector2(224,240)],[Vector2i(1600,900),Vector2(544,384)]]:
		root.size=sample[0]
		for i in 3:await process_frame;await RenderingServer.frame_post_draw
		if naming.position!=sample[1] or naming.name_bytes!=original_bytes:
			push_error("Naming resize changed anchor or draft bytes");return false
		var actual:=root.get_texture().get_image()
		for y in 144:
			for x in 504:
				var a:=actual.get_pixel(int(naming.position.x)+x,int(naming.position.y)+y);var b:=expected.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035:
					push_error("Resized naming pixel mismatch");return false
		var before:=cancellations.size()
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
		Input.parse_input_event(escape);await process_frame
		await click_at(Vector2(20,20),MOUSE_BUTTON_RIGHT)
		if cancellations.size()!=before or naming.name_bytes!=original_bytes:
			push_error("Resized naming Back changed draft or cancelled");return false
		await click_at(naming.position+Vector2(448,90))
		if cancellations.size()!=before+1:push_error("Resized naming Cancel pointer mismatch");return false
	naming.cancelled.disconnect(on_cancel)
	root.size=Vector2i(1200,800)
	for i in 3:await process_frame;await RenderingServer.frame_post_draw
	return true
