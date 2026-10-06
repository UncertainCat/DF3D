extends SceneTree
const Draft = preload("res://scripts/construction_draft.gd")
const View = preload("res://scripts/construction_material_view.gd")
class PaletteWorld:
	extends RefCounted
	var assets
	var overrides := {}
	func ui_texture(token, index = -1): return assets.ui_texture(token,index)
	func ui_font_path(): return assets.ui_font_path()
	func ui_palette_color(index): return overrides.get(index,assets.ui_palette_color(index))
	func construction_item_icon(kind, appearance): return assets.construction_item_icon(kind,appearance)
var failures := 0
var picks: Array = []
var pages: Array = []
var dones: Array = []

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func click_control(control: Control, button := MOUSE_BUTTON_LEFT) -> void:
	await process_frame
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
		event.button_index = button; event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		root.push_input(event,true)
		await process_frame

func run() -> void:
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	var draft := Draft.new()
	draft.definition = {"key":"TradeDepot","family":"TradeDepot"}
	draft.preview_valid = true
	draft.filters = [{"index":0,"quantity":3}]
	draft.snapshots[0] = {"revision":19,"next_cursor":2,"rows":[
		{"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":1,"name":"talc","caption":"","count":81},
		{"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":2,"name":"chert","caption":"","count":4}]}
	var source := PaletteWorld.new(); source.assets = assets
	var view := View.new(); root.add_child(view); view.configure(source)
	var furniture_fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/furniture_material_copy.json"))
	for captured in furniture_fixture.common_exact_picker.cases:
		var example=Draft.new();example.definition={"key":str(captured.kind).capitalize()};example.preview_valid=true
		example.filters=[{"index":0,"quantity":1}]
		var native_heading:=""
		for line in captured.lines:
			if str(line.text).contains("Select materials"):native_heading=str(line.text).strip_edges()
		view.show_filter(example,0,example.definition.key);view.resize_to_view(Vector2(1200,800))
		check(view.heading.text==native_heading,"verbatim native furniture heading")
		check(view._single_picker() and view._column_offset()==80 and view.size.x==472,"native furniture picker geometry")
	var palette := FileAccess.get_file_as_string(assets.assets_root().path_join("data/init/colors.txt"))
	var names := ["BLACK","BLUE","GREEN","CYAN","RED","MAGENTA","BROWN","LGRAY","DGRAY","LBLUE","LGREEN","LCYAN","LRED","LMAGENTA","YELLOW","WHITE"]
	for index in names.size():
		var rgb := []
		for channel in ["R","G","B"]:
			var token: String = "["+names[index]+"_"+channel+":"
			var start := palette.find(token)
			check(start>=0,"installed palette channel exists")
			rgb.append(float(palette.substr(start+token.length()).get_slice("]",0))/255.0)
		check(assets.ui_palette_color(index).is_equal_approx(Color(rgb[0],rgb[1],rgb[2])),"extension uses installed palette channel")
	check(assets.ui_palette_color(-1).a==0.0 and assets.ui_palette_color(16).a==0.0,"invalid palette index has no color")
	view.group_selected.connect(func(filter_index,row,count): picks.append([filter_index,row,count]))
	view.filter_done.connect(func(filter_index): dones.append(filter_index))
	view.show_filter(draft,0,"Trade Depot");view.resize_to_view(Vector2(1200,800))
	await process_frame
	check(view.heading.text == "Select materials for the Trade Depot." and view.amount.text == "Amount needed: 3", "native prompt and quantity")
	check(view.row_controls.size() == 2 and view.row_controls[0].pick.text == "talc [81]", "grouped names and counts without fabricated caption")
	check(view.rows.get_child(0).size.y == 36 and view.size.x == 472, "native material row height and panel width")
	view.row_controls[0].pick.pressed.emit()
	view.row_controls[0].all.pressed.emit()
	check(picks == [[0,0,1],[0,0,3]], "row click selects one and All caps at recipe need")
	draft.select_group(0,0,1); view.refresh()
	check(view.row_controls[0].pick.text == "talc  1/3" and not view.row_controls[0].none.disabled, "partial group progress remains selectable")
	view.row_controls[0].none.pressed.emit()
	check(picks.back() == [0,0,0], "None removes the group")
	check(not view.find_children("*","Button",true,false).any(func(b):return b.text == "More"), "transport paging adds no visible copy")
	view.search.text = "chert"; view._render_rows()
	check(view.row_controls.size() == 1 and view.row_controls[0].index == 1, "filtering preserves original row identity")
	view.row_controls[0].pick.pressed.emit()
	check(picks.back() == [0,1,1], "filtered selection addresses the correct group")
	view.set_locked(true)
	var before := picks.size(); view._pick(1,1); view._done()
	check(picks.size() == before and pages.is_empty() and dones.is_empty() and view.row_controls[0].pick.disabled, "outstanding request locks dispatch")
	view.set_locked(false); draft.definition.key = "Weapon"; draft.definition.family = "Weapon"; view.refresh()
	check(view.done.visible and view.amount.text == "Amount needed: 1 to 10" and not view.done.disabled, "variable native input exposes Done after minimum")
	view.done.pressed.emit(); check(dones == [0], "Done emits current filter only")
	view.search.clear(); draft.definition.key = "TradeDepot"; draft.definition.family = "TradeDepot"; view.refresh()
	if DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../../../build/qa/03-U")
		DirAccess.make_dir_recursive_absolute(directory)
		check(root.get_texture().get_image().save_png(directory.path_join("materials_trade_depot.png")) == OK,"GPU material capture")
	# Replay the captured native expanded Iron bars rows against production candidate
	# data. Synthetic aggregate names above are not native copy evidence.
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json"))
	var native_rows: Array = evidence.production_materials_capture.materials
	for item in evidence.picker_icon_capture.semantic_items:
		for group in native_rows:
			for candidate in group.candidates:
				if int(candidate.id)==int(item.id):
					candidate.appearance={"material_token":item.material,"subtype_raw":"","color_token":item.color_token,"stack":int(item.stack),"flags":32 if item.artifact else 0}
	draft.definition = {"key":"Construction:Track","family":"Construction"}
	draft.selections.clear(); draft.filters = [{"index":0,"quantity":5}]
	draft.snapshots[0] = {"revision":20,"next_cursor":0,"rows":native_rows.duplicate(true)}
	view.item_selected.connect(func(filter_index,row,id):
		picks.append([filter_index,row,id]); draft.select_item(filter_index,row,id); view.refresh())
	view.show_filter(draft,0,"Track")
	check(view.heading.text=="Select materials for the Track (NSEW).","verbatim native Track recipe heading")
	var iron := -1
	for i in native_rows.size():
		if native_rows[i].name == "iron bars": iron = i
	check(iron >= 0,"native Iron group exists")
	# Deliberately distinct fixture colors catch accidental fixed RGB or wrong roles.
	source.overrides={15:Color(.1,.2,.3),10:Color(.2,.3,.4),14:Color(.3,.4,.5),4:Color(.4,.5,.6),8:Color(.5,.6,.7)}
	view.refresh()
	var colored: Dictionary = view.row_controls[iron]
	check(colored.pick.get_theme_color("font_color")==source.overrides[15],"group text follows WHITE role")
	check(colored.pick.get_parent().get_node("Distance").get_theme_color("font_color")==source.overrides[10],"distance follows LGREEN role")
	check(colored.all.get_theme_color("font_color")==source.overrides[14] and colored.none.get_theme_color("font_color")==source.overrides[4],"actions follow YELLOW and RED roles")
	check(colored.none.get_theme_color("font_disabled_color")==source.overrides[8],"disabled action follows DGRAY role")
	source.overrides.clear(); view.refresh()
	check(view.row_controls[iron].pick.text == "Iron bars [2]","native capitalization and group count")
	check(view.row_controls[iron].expand.texture_normal == view.art.texture("BUTTON_EXPANDER_CLOSED"),"native closed expander art")
	view.row_controls[iron].expand.pressed.emit()
	var controls: Dictionary = view.row_controls[iron]
	check(controls.items.size()==2 and controls.items[0].id==3226 and controls.items[1].id==3225,"expanded native distance order and exact identities")
	check(controls.expand.texture_normal == view.art.texture("BUTTON_EXPANDER_OPEN"),"native open expander art")
	check(controls.items[1].pick.position==Vector2(56,0) and controls.items[1].pick.get_parent().get_node("Distance").text=="Dist: 2","native child text and distance column")
	check(controls.items[1].pick.get_parent().get_node("ItemIcon").position==Vector2(18,2),"native item artwork anchor")
	controls.items[1].pick.pressed.emit()
	check(draft.selected_ids(0,native_rows[iron])==[3225] and view.row_controls[iron].pick.text=="Iron bars...","specific row selects exact farther item and preserves native progress caption")
	view.row_controls[iron].items[1].pick.pressed.emit()
	check(draft.selected_ids(0,native_rows[iron])==[3225],"repeat specific click remains a no-op")
	view.row_controls[iron].expand.pressed.emit(); view.row_controls[iron].expand.pressed.emit()
	check(view.row_controls[iron].items.size()==2 and draft.selected_count(0)==1,"collapse/reopen retains selected identities")
	draft.select_group(0,iron,2); view.refresh()
	check(not view.row_controls[iron].pick.get_parent().get_node("Distance").visible and view.row_controls[iron].items[0].pick.get_parent().get_node("Distance").visible,"exhausted group hides distance while children retain theirs")
	view.search.text="iron"; view._render_rows()
	check(view.row_controls.size()==1 and view.row_controls[0].index==iron and view.row_controls[0].items.size()==2,"search preserves expansion and original group identity")
	view.set_locked(true); before=picks.size(); view._pick_item(iron,3226); view._expand(str(draft.identity(native_rows[iron])))
	check(picks.size()==before and view.row_controls[0].items.size()==2 and view.row_controls[0].expand.disabled,"pending request locks exact selection and expansion")
	view.set_locked(false)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../../../build/qa/03-U")
		check(root.get_texture().get_image().save_png(directory.path_join("materials_track_individual.png"))==OK,"GPU exact material capture")
	draft.snapshots[0].revision=21; view.refresh()
	check(view.row_controls[0].items.is_empty(),"replacement snapshot clears expansion identities")
	draft.selections.clear(); view.refresh()
	await click_control(view.row_controls[0].expand)
	check(view.row_controls[0].items.size()==2,"pointer expands visible filtered group")
	if view.row_controls[0].items.size()==2:
		await click_control(view.row_controls[0].items[1].pick)
		check(draft.selected_ids(0,native_rows[iron])==[3225],"pointer selects exact farther candidate")
		await click_control(view.row_controls[0].items[1].pick)
		check(draft.selected_ids(0,native_rows[iron])==[3225],"repeated pointer selection is idempotent")
		view.set_locked(true); before=picks.size()
		await click_control(view.row_controls[0].items[0].pick)
		check(picks.size()==before,"locked pointer selection emits no action")
		view.set_locked(false)
	var cancellations := []
	view.cancel_requested.connect(func(): cancellations.append(true))
	await click_control(view.search,MOUSE_BUTTON_RIGHT)
	check(cancellations.size()==1,"right click on search cancels once")
	draft.selections.clear(); draft.filters[0].quantity=0; view.refresh()
	check(not view.amount.visible and not view.row_controls[0].all.visible and not view.row_controls[0].none.visible,"native zero-material overlap hides quantity and batch controls")
	check(not view.row_controls[0].pick.disabled,"zero-material overlap keeps row selectable")
	var done_before := dones.size(); before=picks.size()
	await click_control(view.row_controls[0].pick)
	check(dones.size()==done_before+1 and picks.size()==before and draft.selections.is_empty(),"zero-material pointer click completes filter without selecting an item")
	view.set_locked(true)
	await click_control(view.row_controls[0].pick)
	check(dones.size()==done_before+1,"locked zero-material row cannot complete")
	view.set_locked(false)
	var windmill:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/windmill.json"))
	draft.definition={"key":"Windmill","family":"Windmill"}; draft.selections.clear(); draft.filters=[{"index":0,"quantity":4}]
	var logs:Dictionary={"item_type":5,"item_subtype":-1,"mat_type":419,"mat_index":0,"name":"cherry wood logs","count":4,"candidates":[]}
	for choice in windmill.native_picker.choices:
		if choice.kind=="Specific": logs.candidates.append({"id":int(choice.id),"name":choice.name,"distance":int(choice.distance)})
	draft.snapshots[0]={"revision":31,"next_cursor":0,"rows":[logs]}
	view.item_deselected.connect(func(filter_index,row,id): draft.deselect_item(filter_index,row,id); view.refresh())
	view.group_selected.connect(func(filter_index,row,count): draft.select_group(filter_index,row,count); view.refresh())
	view.show_filter(draft,0,"Windmill"); view.row_controls[0].expand.pressed.emit()
	for action in windmill.native_picker.actions:
		match str(action.label):
			"group_add_1","group_add_2": view.row_controls[0].pick.pressed.emit()
			"group_subtract": view.row_controls[0].subtract.pressed.emit()
			"specific_subtract_selected": view.row_controls[0].items[2].subtract.pressed.emit()
			"specific_add": view.row_controls[0].items[0].pick.pressed.emit()
			"specific_subtract_unselected":
				check(view.row_controls[0].items[1].subtract.disabled,"Unselected native item subtraction is disabled")
				await click_control(view.row_controls[0].items[1].subtract)
			"specific_subtract_selected_again": view.row_controls[0].items[0].subtract.pressed.emit()
		var expected:Array=action.selected.map(func(id):return int(id))
		check(draft.selected_ids(0,logs)==expected,"Native Windmill add/subtract identity replay: "+str(action.label))
	var magma:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/magma_placement.json"))
	draft.definition={"key":"Workshop:MagmaForge","family":"Workshop"};draft.selections.clear();draft.filters=[{"index":0,"quantity":1}]
	var anvils:Dictionary={"item_type":45,"item_subtype":-1,"mat_type":0,"mat_index":0,"name":"iron anvils","count":3,"candidates":[]}
	for choice in magma.native_picker.expanded.choices:
		if choice.kind=="Specific":anvils.candidates.append({"id":int(choice.id),"name":choice.name,"distance":int(choice.distance)})
	draft.snapshots[0]={"revision":32,"next_cursor":0,"rows":[anvils]}
	view.show_filter(draft,0,"Magma forge");view.row_controls[0].expand.pressed.emit()
	check(view.heading.text=="Select materials for the Magma Forge.","native forge heading")
	check(not view.row_controls[0].all.visible and not view.row_controls[0].none.visible and not view.row_controls[0].has("subtract"),"native single input omits batch/subtract controls")
	check(view.rows.get_child(0).find_child("Distance",true,false).position.x==320,"native single input distance column")
	check(view.row_controls[0].items[0].pick.text=="(iron anvil)","native decorated individual description")
	await click_control(view.row_controls[0].items[1].pick)
	check(draft.place_request().selections[0].item_ids==[48524],"exact anvil identity reaches Place")
	draft.definition={"key":"Bridge","family":"Bridge"};draft.selections.clear()
	view.show_filter(draft,0,"Bridge")
	check(view.heading.text=="Select materials for the Bridge.","native Bridge heading")
	check(not view.row_controls[0].all.visible and not view.row_controls[0].none.visible and not view.row_controls[0].has("subtract"),"native one-item Bridge omits batch/subtract controls")
	check(view.rows.get_child(0).find_child("Distance",true,false).position.x==304,"native one-item Bridge distance column")
	draft.filters=[{"index":0,"quantity":3}];view.show_filter(draft,0,"Bridge")
	check(view.row_controls[0].all.visible and view.row_controls[0].none.visible and view.row_controls[0].has("subtract"),"native multi-item Bridge exposes batch/subtract controls")
	check(view.rows.get_child(0).find_child("Distance",true,false).position.x==240,"native multi-item Bridge distance column")
	var terrain:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/stairs_placement.json"))
	for captured in terrain.terrain_picker_reference.cases:
		var v:Dictionary=captured.definition
		var kind:String={"WALL":"Wall","FLOOR":"Floor","RAMP":"Ramp","FORTIFICATION":"Fortification","STAIR_UPDOWN":"Stairs"}[v.kind]
		draft.definition={"key":"Construction:"+kind,"family":"Construction"};draft.selections.clear()
		draft.filters=[{"index":0,"quantity":int(v.width)*int(v.height)*int(v.depth)}]
		var row:Dictionary={"item_type":0,"item_subtype":-1,"mat_type":0,"mat_index":0,"name":captured.groups[0].name,"count":captured.candidates.size(),"candidates":[]}
		for choice in captured.expanded.choices:
			if choice.kind=="Specific":row.candidates.append({"id":int(choice.id),"name":choice.name,"distance":int(choice.distance)})
		draft.snapshots[0]={"revision":100,"rows":[row]}
		view.show_filter(draft,0,kind);view.resize_to_view(Vector2(1200,800));await process_frame;await process_frame
		var native_heading:=""
		for line in captured.lines:
			if str(line.text).contains("Select materials"):native_heading=str(line.text).strip_edges()
		check(view.heading.text==native_heading and view.size.x==472,"native terrain heading and panel width")
		var single:bool=int(v.width)*int(v.height)*int(v.depth)==1
		check(view.rows.get_child(0).find_child("Distance",true,false).position.x==(320 if single else 256),"collapsed native terrain distance column")
		view.row_controls[0].expand.pressed.emit();await process_frame;await process_frame
		check(view.rows.get_child(0).find_child("Distance",true,false).position.x==(304 if single else 240),"expanded scrolling shifts columns sixteen pixels")
		check(view.row_controls[0].all.visible!=single and view.row_controls[0].has("subtract")!=single,"terrain controls follow native one/many quantity")
	var special_fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/furniture_material_copy.json"))
	var standalone_cases:Array=special_fixture.special_item_reference.cases+special_fixture.additional_single_item_improved_reference.capture.cases
	for capture in standalone_cases:
		var kind:String=str(capture.definition) if capture.has("definition") else {"BED":"Bed","CHAIR":"Chair","TABLE":"Table","COFFIN":"Coffin","CABINET":"Cabinet","BOX":"Box","STATUE":"Statue","SLAB":"Slab"}[capture.kind]
		draft.definition={"key":kind,"family":kind};draft.selections.clear();draft.filters=[{"index":0,"quantity":1}]
		var standalone_rows:Array=[]
		for choice in capture.groups:
			if choice.kind!="Specific":continue
			var id:=int(choice.ids[0])
			var native:Dictionary={}
			for candidate in capture.candidates:
				if int(candidate.id)==id:native=candidate
			standalone_rows.append({"item_type":int(native.item_type),"item_subtype":int(native.item_subtype),"mat_type":int(native.mat_type),"mat_index":int(native.mat_index),"individual_id":id,"name":choice.name,"count":1,"candidates":[{"id":id,"name":choice.name,"distance":int(choice.distance)}]})
		draft.snapshots[0]={"revision":201,"rows":standalone_rows}
		view.show_filter(draft,0,kind);await process_frame
		check(view.row_controls.size()==standalone_rows.size(),"all native improved standalone rows")
		for control in view.row_controls:
			check(not control.has("expand") and not control.has("all") and not control.has("none"),"native standalone row has no group controls")
		view.row_controls[1].pick.pressed.emit()
		check(draft.selections.size()==1 and draft.selections[0].individual_id==standalone_rows[1].individual_id,"standalone click chooses its own exact identity")
	for capture in special_fixture.additional_single_item_reference.capture.cases:
		draft.definition={"key":capture.definition,"family":capture.definition};draft.selections.clear();draft.filters=[{"index":0,"quantity":1}]
		var single_rows:Array=[]
		for native in capture.groups:
			var first:Dictionary={}
			for candidate in capture.candidates:
				if int(candidate.id)==int(native.ids[0]):first=candidate
			var row:Dictionary={"item_type":int(first.item_type),"item_subtype":int(first.item_subtype),"mat_type":int(first.mat_type),"mat_index":int(first.mat_index),"name":native.name,"count":native.ids.size(),"candidates":[]}
			for id in native.ids:row.candidates.append({"id":int(id),"name":first.description,"distance":int(native.distance)})
			single_rows.append(row)
		draft.snapshots[0]={"revision":301,"rows":single_rows}
		view.show_filter(draft,0,capture.definition);view.resize_to_view(Vector2(1200,800));await process_frame
		var native_heading:=""
		for line in capture.lines:
			if str(line.text).contains("Select materials"):native_heading=str(line.text).strip_edges()
		check(view.heading.text==native_heading and view.size.x==472,"additional native single-item heading/width")
		check(not view.row_controls[0].all.visible and not view.row_controls[0].none.visible and not view.row_controls[0].has("subtract"),"single-item group controls match native")
		check(draft.select_item(0,0,int(single_rows[0].candidates[0].id)) and not draft.place_request().is_empty(),"additional family preserves exact selection in Place")
	var weapon:Dictionary=evidence.weapon_reference.cases[1]
	var filter:Dictionary=weapon.filters[0];var group:Dictionary=filter.groups[0];var sample:Dictionary=filter.candidates[0]
	draft.definition={"key":"Weapon","family":"Weapon"};draft.preview_valid=true;draft.selections.clear();draft.filters=[{"index":0,"quantity":1}]
	var row:Dictionary={"name":group.name,"count":group.ids.size(),"candidates":[]}
	for field in ["item_type","item_subtype","mat_type","mat_index"]:row[field]=int(sample[field])
	for id in group.expanded_ids:row.candidates.append({"id":int(id),"name":sample.description,"distance":int(group.distance)})
	draft.snapshots[0]={"revision":401,"next_cursor":0,"rows":[row]}
	view.show_filter(draft,0,"Upright weapon/spike");view.resize_to_view(Vector2(1200,800));await process_frame
	check(view.done.visible and view.done.disabled,"Native empty variable picker waits for minimum before Done")
	check(draft.select_group(0,0,3),"Native three-weapon selection")
	view.refresh();await process_frame
	check(not view.done.disabled and view.amount.text=="Amount needed: 1 to 10","Native variable picker retains Done after minimum")
	check(not view.row_controls[0].all.visible and not view.row_controls[0].none.visible and not view.row_controls[0].has("subtract"),"Native variable picker has no All/None/subtract")
	check(view.rows.get_child(0).find_children("*","Label",true,false).any(func(label):return label.text=="3/1"),"Native variable selected counter retains minimum denominator")
	# Thousands of semantic rows still use only the viewport's reusable controls.
	var large := {"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":1,"name":"fixture stone","count":5000,"candidates":[]}
	for index in 5000: large.candidates.append({"id":100000+index,"name":"fixture item %d" % index,"distance":index})
	draft.definition={"key":"Construction:Wall","family":"Construction"}; draft.selections.clear(); draft.filters=[{"index":0,"quantity":4}]
	draft.snapshots[0]={"revision":500,"next_cursor":0,"rows":[large]}
	view.show_filter(draft,0,"Wall"); await process_frame; await process_frame
	var widget_ids: Array = view._row_pool.map(func(widget): return widget.get_instance_id())
	view.row_controls[0].expand.pressed.emit(); await process_frame; await process_frame
	check(view._entries.size()==5001,"expanded scroll extent covers every exact item")
	check(view._row_pool.map(func(widget): return widget.get_instance_id())==widget_ids,"expanding large inventory allocates no extra row widgets")
	var held_pick: Button = view.row_controls[0].pick
	held_pick.button_down.emit(); before=picks.size()
	view.scroll.scroll_vertical=5001*36; await process_frame; await process_frame
	held_pick.pressed.emit()
	check(picks.size()==before,"release after row recycling cannot target a different item")
	check(view.row_controls[0].items.back().id==104999,"last visible row retains the last semantic identity")
	await click_control(view.row_controls[0].items.back().pick)
	check(draft.selected_ids(0,large)==[104999],"scrolled pointer selects exact final item")
	var old_pick: Button = view.row_controls[0].items.back().pick
	view.set_locked(true); before=picks.size(); old_pick.pressed.emit()
	check(picks.size()==before,"pooled controls obey pending lock without rebinding")
	view.hide(); old_pick.pressed.emit()
	check(picks.size()==before and view._entries.is_empty(),"hidden rows discard prior snapshot callbacks")
	draft.snapshots[0]={"revision":501,"next_cursor":0,"rows":[large]}; draft.selections.clear()
	view.set_locked(false); view.show_filter(draft,0,"Wall"); await process_frame
	check(view.row_controls[0].items.is_empty() and view.scroll.scroll_vertical==0,"replacement picker resets expansion and scroll identity")
	view.free(); assets.free()
	await process_frame
	print("CONSTRUCTION_MATERIAL ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
