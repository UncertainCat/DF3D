extends SceneTree
class StubView:
	extends RefCounted
	var status := {"text":""}
	func refresh(): pass
	func hide(): pass
	func show_filter(_draft,_index,_label): pass
class AdvanceProbe:
	extends "res://scripts/construction.gd"
	var loaded_filter := -1
	func load_materials(index,_cursor=0): loaded_filter=index
	func update_buttons(): pass
class Probe:
	extends "res://scripts/construction.gd"
	var completed := 0
	var page := 0
	var loaded_filter := -1
	var closed := false
	func close_panel(): closed = true
	func update_buttons(): pass
	func finish_filter(_index): completed += 1
	func load_materials(index, cursor = 0): page = cursor; loaded_filter = index
	func place(): completed += 1
var failures := 0
func check(value: bool, label: String):
	if not value: failures += 1; push_error(label)
func _initialize(): call_deferred("run")
func run():
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json"))
	var history_probe:=Probe.new()
	for native in evidence.workshop_history_reference.cases:
		history_probe.draft.definition={"key":native.definition}
		if history_probe.draft.FixedRecipes.RECIPES[native.definition].last:
			history_probe.last_material={"definition":native.definition,"name":"fixture history","item_type":int(native.history.item_type)}
		else:history_probe.remember_material({"definition":native.definition})
		for target in native.targets:
			history_probe.draft.definition={"key":target.definition}
			var visible:bool=target.state.lines.any(func(line):return "Use last material" in str(line.text))
			check(history_probe.supports_last_material()==visible,"Native cross-recipe Last validity and search class: "+native.definition+" -> "+target.definition)
	history_probe.free()
	var advance:=AdvanceProbe.new();advance.material_view=StubView.new();advance.mode="materials"
	advance.draft.definition={"key":"Workshop:Ashery"};advance.draft.preview_valid=true
	for index in 3:
		advance.draft.filters.append({"index":index,"quantity":1})
		advance.draft.snapshots[index]={"revision":10+index,"next_cursor":0,"rows":[{"count":1}]}
	advance.draft.selections=[{"filter":0,"count":1}]
	advance.finish_filter(0)
	check(advance.filter_position==1 and advance.loaded_filter==-1 and advance.draft.preview_valid and advance.draft.selected_count(0)==1,"Manual Ashery advancement reuses pinned inputs and retains selected blocks")
	advance.free()
	for native in evidence.weapon_special_reference.shortages:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="after"
		probe.draft.definition={"key":native.definition};probe.draft.preview_valid=true
		probe.shortage_panel=PanelContainer.new();probe.shortage_text=Label.new();probe.footer=PanelContainer.new();probe.orientation_panel=PanelContainer.new()
		for child in [probe.shortage_panel,probe.shortage_text,probe.footer,probe.orientation_panel]:probe.add_child(child)
		for index in (2 if native.definition=="Trap:WeaponTrap" else 1):
			probe.draft.filters.append({"index":index,"quantity":1})
			probe.draft.snapshots[index]={"revision":index+1,"next_cursor":0,"rows":[]}
		probe.update_material_shortage()
		var expected:Array[String]=[]
		for line in native.closest.lines:
			var text:=str(line.text).strip_edges()
			if text.begins_with("Needs ") or text.begins_with("No access to "):expected.append(text)
			elif text.begins_with("- "):expected.append(" "+text)
		check(probe.shortage_text.text=="\n".join(expected),"Native variable weapon shortage copy: "+str(native.definition))
		probe.free()
	for partial in [false,true]:
		var shortage_cases:Array=evidence.variable_partial_shortages.cases if partial else evidence.variable_reference.shortages
		for native in shortage_cases:
			var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="after"
			probe.draft.definition={"key":native.definition};probe.draft.preview_valid=true
			probe.shortage_panel=PanelContainer.new();probe.shortage_text=Label.new();probe.footer=PanelContainer.new();probe.orientation_panel=PanelContainer.new()
			for child in [probe.shortage_panel,probe.shortage_text,probe.footer,probe.orientation_panel]:probe.add_child(child)
			var recipes:Array=evidence.variable_reference.cases.filter(func(c):return c.definition==native.definition)
			var recipe:Dictionary=recipes[int(str(native.case_name).get_slice("-",1))-1]
			for filter in recipe.filters:
				var index:=int(filter.index)
				probe.draft.filters.append({"index":index,"quantity":int(filter.required)})
				probe.draft.snapshots[index]={"revision":index+1,"next_cursor":0,"rows":[{"count":1 if partial and index==0 else 0}]}
			probe.update_material_shortage()
			var expected:Array[String]=[]
			for line in native.closest.lines:
				var text:=str(line.text).strip_edges()
				if text.begins_with("Needs ") or text.begins_with("No access to "):expected.append(text)
				elif text.begins_with("- "):expected.append(" "+text)
			check(probe.shortage_text.text=="\n".join(expected),"Native variable-size zero/partial shortage copy: "+str(native.case_name))
			probe.free()
	for native in evidence.workshop_reference.cases+evidence.utility_reference.cases+evidence.machine_reference.cases+evidence.final_workshop_reference.cases+evidence.variable_reference.cases+evidence.weapon_reference.cases+evidence.weapon_multigroup_reference.cases+evidence.reinforced_reference.cases+evidence.reinforced_overlap_reference.cases+evidence.reinforced_cursor_reference.cases:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="closest"
		probe.draft.definition={"key":native.definition};probe.draft.preview_valid=true
		for filter in native.filters:
			var index:=int(filter.index)
			probe.draft.filters.append({"index":index,"quantity":int(filter.required)})
			var rows:Array=[]
			for group in filter.groups:
				var sample:Dictionary={}
				for candidate in filter.candidates:
					if int(candidate.id)==int(group.ids[0]):sample=candidate;break
				var row:Dictionary={"count":group.ids.size(),"individual_id":-1,"last_name":sample.plural,"candidates":[]}
				for field in ["item_type","item_subtype","mat_type","mat_index"]:row[field]=int(sample[field])
				for id in group.ids:
					var distance:int=int(group.distance)
					for candidate in filter.candidates:
						if int(candidate.id)==int(id):distance=int(candidate.get("distance",group.distance));break
					row.candidates.append({"id":int(id),"distance":distance})
				rows.append(row)
			probe.draft.snapshots[index]={"revision":index+100,"rows":rows,"next_cursor":0}
		if probe.draft.filters.size()>1:
			var final_index:int=probe.draft.filters.size()-1
			var final_snapshot:Dictionary=probe.draft.snapshots[final_index]
			probe.draft.snapshots.erase(final_index);probe.apply_last_material(0)
			check(probe.loaded_filter==final_index and probe.completed==0 and probe.draft.selections.is_empty(),"Workshop collects all inputs before selecting")
			probe.draft.snapshots[final_index]=final_snapshot
		probe.apply_last_material(0)
		var chosen:Array=[]
		for selection in probe.draft.selections:chosen.append_array(selection.item_ids)
		chosen.sort()
		var expected:Array=native.closest_items.map(func(id):return int(id));expected.sort()
		check(chosen==expected and probe.completed==(0 if native.get("closest_requires_done",false) else 1),"Workshop Closest matches native exact items: "+native.definition)
		probe.last_material={"name":"granite","definition":native.definition,"item_type":4}
		check(probe.supports_last_material()==native.has_last,"Native workshop Last availability")
		probe.remember_material({"definition":native.definition,"selections":probe.draft.selections})
		if not native.has_last:check(probe.last_material.is_empty(),"Multi-input workshop invalidates earlier Last preference")
		probe.draft.selections.clear();probe.draft.snapshots[0].rows=[];probe.completed=0
		probe.apply_last_material(0)
		check(probe.completed==0 and probe.draft.selections.is_empty() and probe.closest_material_shortage(),"Workshop shortage cannot submit partial inputs")
		probe.material_strategy="after"
		check(probe.closest_material_shortage(),"Native workshop manual mode uses same shortage gate")
		probe.handle_back();check(probe.closed,"Workshop picker cancels to map")
		probe.free()
	for native in evidence.closest_capture.cases:
		var c := Probe.new(); c.material_view = StubView.new(); c.mode = "materials"
		c.material_strategy = "closest"
		c.draft.definition = {"key":"Construction:Track"}; c.draft.preview_valid = true
		c.draft.filters = [{"index":0,"quantity":5}]
		var rows: Array = native.rows.duplicate(true)
		for row in rows:
			for item in row.candidates: item.id = int(item.id); item.distance = int(item.distance)
		c.draft.snapshots[0] = {"revision":1,"rows":rows,"next_cursor":17}
		c.apply_last_material(0)
		check(c.page==17 and c.completed==0 and c.draft.selections.is_empty(),"Closest waits for complete paged snapshot")
		c.draft.snapshots[0].next_cursor = 0
		c.apply_last_material(0)
		var ids: Array = []
		for selection in c.draft.selections: ids.append_array(selection.item_ids)
		ids.sort()
		var expected: Array = []
		for id in native.expected_ids: expected.append(int(id))
		check(ids==expected and c.completed==1,"Closest matches native selected identities, including group and candidate ties")
		c.draft.selections.clear(); c.draft.filters[0].quantity = 0
		c.apply_last_material(0)
		check(c.completed==2 and c.draft.selections.is_empty(),"Closest completes zero-material overlap without selecting an item")
		c.free()
	var magma:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/magma_placement.json"))
	for native in magma.native_closest.cases:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="closest"
		probe.draft.definition={"key":native.definition};probe.draft.preview_valid=true
		for filter in native.filters:
			probe.draft.filters.append({"index":int(filter.filter),"quantity":1})
			probe.draft.snapshots[int(filter.filter)]={"revision":100+int(filter.filter),"next_cursor":0,"rows":[{"item_type":0,"item_subtype":-1,"mat_type":0,"mat_index":int(filter.filter),"count":1,"candidates":[{"id":int(filter.id),"distance":0}]}]}
		if probe.draft.filters.size()==2:
			var second:Dictionary=probe.draft.snapshots[1];probe.draft.snapshots.erase(1)
			probe.apply_last_material(0)
			check(probe.loaded_filter==1 and probe.completed==0 and probe.draft.selections.is_empty(),"Forge reads both inputs before selecting")
			probe.draft.snapshots[1]=second
		probe.apply_last_material(0)
		var chosen:Array=[]
		for selection in probe.draft.selections:chosen.append_array(selection.item_ids)
		check(chosen==native.expected.map(func(id):return int(id)) and probe.completed==1,"Magma Closest selects each native first group and submits once")
		probe.draft.selections.clear();probe.draft.snapshots[0].rows=[];probe.completed=0
		probe.apply_last_material(0)
		check(probe.completed==0 and probe.draft.selections.is_empty() and probe.closest_material_shortage(),"Magma shortage creates no partial selection or job")
		probe.free()
	var shortage: Dictionary = evidence.closest_shortage_capture
	var c := Probe.new(); c.material_view = StubView.new(); c.mode = "materials"
	c.material_strategy = "closest"
	c.draft.definition = {"key":"Construction:Track"}; c.draft.preview_valid = true
	c.draft.filters = [{"index":0,"quantity":int(shortage.required)}]
	var rows: Array = shortage.rows.duplicate(true)
	for row in rows:
		for item in row.candidates: item.id = int(item.id); item.distance = int(item.distance)
	c.draft.snapshots[0] = {"revision":1,"rows":rows,"next_cursor":0}
	c.apply_last_material(0)
	check(c.draft.selected_count(0)==int(shortage.provided) and c.completed==0 and not c.draft.can_place(),"Native shortage preselects available items without placing")
	for candidate in shortage.candidates:
		var selected := false
		for selection in c.draft.selections: selected = selected or selection.item_ids.has(int(candidate.id))
		check(selected==bool(candidate.selected),"Native shortage candidate selection matches")
	check(c.material_strategy=="closest" and c.mode=="materials","Native shortage retains Closest and picker state")
	check(c.closest_material_shortage(),"Completed shortage snapshot recognized")
	c.draft.snapshots[0].next_cursor = 17
	check(not c.closest_material_shortage(),"Incomplete page cannot establish a shortage")
	c.draft.snapshots[0].next_cursor = 0
	c.handle_back()
	check(c.closed and c.material_strategy=="closest","Native shortage cancel closes construction and retains Closest")
	c.free()
	var many := Probe.new(); many.material_view = StubView.new(); many.mode = "materials"
	many.material_strategy = "closest"; many.draft.definition = {"key":"Construction:Track"}; many.draft.preview_valid = true
	many.draft.filters = [{"index":0,"quantity":17}]
	var groups: Array = []
	for entry in evidence.seventeen_group_capture.selected:
		var identity: PackedStringArray = str(entry.identity).split(":")
		groups.append({"item_type":int(identity[0]),"item_subtype":int(identity[1]),"mat_type":int(identity[2]),"mat_index":int(identity[3]),"count":1,"candidates":[{"id":int(entry.id),"distance":0}]})
	many.draft.snapshots[0] = {"revision":42,"next_cursor":0,"rows":groups}
	many.apply_last_material(0)
	check(many.draft.selections.size()==17 and many.completed==1,"Native17 material groups complete one Track selection")
	many.free()
	var last := Probe.new(); last.material_view = StubView.new(); last.mode = "materials"
	last.material_strategy = "last"; last.draft.definition = {"key":"Construction:Track"}; last.draft.preview_valid = true
	last.draft.filters = [{"index":0,"quantity":5}]
	var history_rows: Array = evidence.closest_capture.cases[2].rows.duplicate(true)
	for row in history_rows:
		row.last_name=row.name # Captured multi-item generic row/history copy.
		for item in row.candidates: item.id=int(item.id); item.distance=int(item.distance)
	last.draft.snapshots[0] = {"revision":42,"next_cursor":0,"rows":history_rows}
	for index in [2,1,0]: last.draft.select_group(0,index,1 if index==0 else 2)
	last.remember_material({"definition":"Construction:Track","selections":last.draft.selections.duplicate(true)})
	var expected_history: Dictionary = evidence.last_mixed_capture.manual_reverse.before
	check(last.last_material.item_type==int(expected_history.last_itype) and last.last_material.mat_type==int(expected_history.last_mat) and last.last_material.mat_index==int(expected_history.last_matg),"Mixed Track Last follows final assigned item, not final group click")
	last.draft.selections.clear(); last.apply_last_material(0)
	check(last.material_strategy=="last" and last.draft.selected_count(0)==2 and last.completed==0,"Native Last preselects partial matching supply and remains in picker")
	last.handle_back()
	check(last.closed and last.material_strategy=="last","Native partial Last cancel exits to map retaining preference")
	last.closed = false
	last.draft.selections.clear(); history_rows.remove_at(2); last.apply_last_material(0)
	check(last.material_strategy=="last" and last.draft.selections.is_empty() and last.completed==0,"Native missing Last retains preference without substituting material")
	last.handle_back()
	check(last.closed and last.material_strategy=="last","Native missing Last cancel exits to map retaining preference")
	last.free()
	for selected_count in [0,2]:
		var manual := Probe.new(); manual.mode = "materials"; manual.material_strategy = "after"
		manual.draft.definition = {"key":"Construction:Track"}
		if selected_count>0: manual.draft.selections=[{"filter":0,"count":selected_count}]
		manual.handle_back()
		check(manual.closed and manual.material_strategy=="after","Native manual picker cancellation returns to map")
		manual.free()
	var terrain:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/stairs_placement.json"))
	for native in terrain.terrain_options_reference.cases+terrain.terrain_area_options_reference.cases:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="closest"
		var kind:String={"WALL":"Wall","FLOOR":"Floor","RAMP":"Ramp","FORTIFICATION":"Fortification","STAIR_UPDOWN":"Stairs"}[native.definition.kind]
		probe.draft.definition={"key":"Construction:"+kind};probe.draft.preview_valid=true
		probe.draft.filters=[{"index":0,"quantity":native.closest_effects.size()}]
		var terrain_rows:Array=native.rows.duplicate(true)
		for row in terrain_rows:
			row.last_name=row.name
			for item in row.candidates:item.id=int(item.id);item.distance=int(item.distance)
		probe.draft.snapshots[0]={"revision":42,"next_cursor":0,"rows":terrain_rows}
		probe.apply_last_material(0)
		var actual:Array=[]
		for selection in probe.draft.selections:actual.append_array(selection.item_ids)
		actual.sort()
		var expected:Array=native.closest_effects.map(func(item):return int(item.item_id));expected.sort()
		check(actual==expected and probe.completed==1,"Terrain Closest selects the native exact item set")
		var mixed:Array=[]
		for row in terrain_rows:
			row.last_name=row.name
			var selection:Dictionary=row.duplicate(true);selection.filter=0;selection.item_ids=[]
			for item in native.mixed_effects:
				if int(item.mat_index)==int(row.mat_index):selection.item_ids.append(int(item.item_id))
			selection.count=selection.item_ids.size();mixed.push_front(selection)
		probe.remember_material({"definition":"Construction:"+kind,"selections":mixed})
		check(probe.draft.identity(probe.last_material)==probe.draft.identity(native.last),"Terrain mixed Last follows native final item rather than final group click")
		probe.free()
	for native in terrain.terrain_last_reference.cases:
		if int(native.definition.available)>2:continue
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="last"
		var kind:String={"WALL":"Wall","FLOOR":"Floor","RAMP":"Ramp","FORTIFICATION":"Fortification","STAIR_UPDOWN":"Stairs"}[native.definition.kind]
		probe.draft.definition={"key":"Construction:"+kind};probe.draft.preview_valid=true
		probe.draft.filters=[{"index":0,"quantity":int(native.required)}]
		probe.last_material={"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":172,"name":"Granite blocks"}
		var matching:Dictionary=probe.last_material.duplicate(true);matching.count=int(native.definition.available);matching.candidates=[]
		for id in native.selected:matching.candidates.append({"id":int(id),"distance":0})
		var alternatives:Dictionary={"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":173,"count":16,"name":"synthetic replacement","candidates":[]}
		for id in range(60000,60016):alternatives.candidates.append({"id":id,"distance":0})
		var supplied:Array=[alternatives]
		if matching.count>0:supplied.append(matching)
		probe.draft.snapshots[0]={"revision":42,"next_cursor":0,"rows":supplied}
		probe.apply_last_material(0)
		var actual:Array=[]
		for selection in probe.draft.selections:actual.append_array(selection.item_ids)
		actual.sort()
		var expected:Array=native.selected.map(func(id):return int(id));expected.sort()
		check(actual==expected and probe.draft.selected_count(0)==int(native.provided),"Terrain Last preselects the native partial supply")
		check(probe.completed==0 and probe.material_strategy=="last" and not probe.draft.can_place(),"Terrain Last preserves preference and does not substitute available alternatives")
		probe.handle_back();check(probe.closed and probe.material_strategy=="last","Terrain Last cancellation returns to map retaining preference")
		probe.free()
	var bridge:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bridge_placement.json"))
	for native in bridge.native_material_options.cases:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="closest"
		probe.draft.definition={"key":"Bridge"};probe.draft.preview_valid=true
		probe.draft.filters=[{"index":0,"quantity":int(native.required)}]
		var bridge_rows:Array=native.rows.duplicate(true)
		for row in bridge_rows:
			for item in row.candidates:item.id=int(item.id);item.distance=int(item.distance)
		probe.draft.snapshots[0]={"revision":42,"next_cursor":0,"rows":bridge_rows}
		probe.apply_last_material(0)
		var actual:Array=[]
		for selection in probe.draft.selections:actual.append_array(selection.item_ids)
		actual.sort();var expected:Array=native.items.map(func(id):return int(id));expected.sort()
		check(actual==expected and probe.completed==1,"Bridge inherited Closest matches native exact selections")
		probe.material_strategy="after";probe.handle_back()
		check(probe.closed and probe.material_strategy=="after" and native.manual_cancel==["dwarfmode/Default"],"Bridge normal material Escape returns to map")
		probe.free()
	for native in bridge.native_last_material.cases:
		var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="last"
		probe.draft.definition={"key":"Bridge"};probe.draft.preview_valid=true;probe.draft.filters=[{"index":0,"quantity":3}]
		var granite:Dictionary={"item_type":2,"item_subtype":-1,"mat_type":0,"mat_index":172,"name":"granite blocks","last_name":"granite blocks","count":native.selected.size(),"candidates":[]}
		for id in native.selected:granite.candidates.append({"id":int(id),"distance":0})
		var limestone:Dictionary=granite.duplicate(true);limestone.mat_index=167;limestone.name="limestone blocks";limestone.last_name="limestone blocks";limestone.candidates=[]
		for id in native.items:
			if not native.selected.has(id):limestone.candidates.append({"id":int(id),"distance":0})
		limestone.count=limestone.candidates.size()
		probe.last_material=granite.duplicate(true)
		probe.draft.snapshots[0]={"revision":42,"next_cursor":0,"rows":[granite,limestone]}
		probe.apply_last_material(0)
		check(probe.draft.selected_count(0)==int(native.provided) and probe.material_strategy=="last","Bridge inherits Last and preselects only remembered supply")
		if limestone.count>0:probe.select_material(0,1,int(limestone.count))
		check(probe.completed==1,"Bridge explicit replacement completes partial Last")
		probe.remember_material({"definition":"Bridge","selections":probe.draft.selections.duplicate(true)})
		check(probe.draft.identity(probe.last_material)==probe.draft.identity(native.history),"Bridge remembers first assigned material, not last selected group")
		probe.free()
	var furniture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/furniture_material_copy.json"))
	for special in [false,true]:
		var native_cases:Array=(furniture.single_item_special_last_reference.cases if special else furniture.single_item_last_reference.cases).duplicate(true)
		native_cases.append_array(furniture.remaining_single_item_improved_reference.cases if special else furniture.remaining_single_item_reference.cases)
		for native in native_cases:
			var probe:=Probe.new();probe.material_view=StubView.new();probe.mode="materials";probe.material_strategy="after"
			probe.draft.definition={"key":native.definition};probe.draft.preview_valid=true;probe.draft.filters=[{"index":0,"quantity":1}]
			var row:Dictionary=native.history.duplicate(true)
			row.name="fixture displayed name";row.last_name=str(native.native_last_name).to_lower();row.count=1
			row.individual_id=int(native.expected_item) if special else -1
			row.candidates=[{"id":int(native.expected_item),"distance":0}]
			probe.draft.snapshots[0]={"revision":42,"next_cursor":0,"rows":[row]}
			check(probe.draft.select_item(0,0,int(native.expected_item)),"history setup selects exact native item")
			probe.remember_material({"definition":native.definition,"selections":probe.draft.selections.duplicate(true)})
			check(probe.last_material.get("name","")==row.last_name and not probe.last_material.has("individual_id"),"Last retains explicit native generic copy without standalone identity")
			check(probe.supports_last_material(),"all22 matching histories enable Last")
			probe.material_strategy="last";probe.draft.selections.clear();probe.apply_last_material(0)
			check(probe.completed==(0 if special else 1) and probe.material_strategy=="last","native Last selects ordinary rows but leaves improved standalone rows for explicit selection")
			probe.draft.snapshots[0].rows=[];probe.draft.selections.clear();probe.completed=0;probe.apply_last_material(0)
			check(probe.completed==0 and probe.closest_material_shortage() and probe.material_strategy=="last","missing single-item Last retains strategy and shows native shortage")
			probe.draft.snapshots[0].rows=[row];row.last_name="";probe.draft.select_item(0,0,int(native.expected_item))
			probe.remember_material({"definition":native.definition,"selections":probe.draft.selections.duplicate(true)})
			check(probe.last_material.is_empty(),"missing old-recording history copy never falls back to displayed name")
			probe.free()
	for native in furniture.installed_order_and_reservation.result.observations:
		if not native.has("kind"): continue
		var item := Probe.new(); item.material_view = StubView.new(); item.mode = "materials"
		item.material_strategy = "closest"; item.draft.definition = {"key":str(native.kind).capitalize()}
		item.draft.preview_valid = true; item.draft.filters = [{"index":0,"quantity":1}]
		item.draft.snapshots[0] = {"revision":42,"next_cursor":9,"rows":native.rows.duplicate(true)}
		item.apply_last_material(0)
		check(item.completed==0 and item.page==9 and item.draft.selections.is_empty(),"Furniture Closest waits for all material pages")
		item.draft.snapshots[0].next_cursor=0; item.apply_last_material(0)
		check(item.completed==1 and item.draft.selections.size()==1,"Furniture Closest completes the single native requirement")
		check(item.draft.identity(item.draft.selections[0])==item.draft.identity(native.rows[0]),"Furniture Closest selects the first navigation-ordered native group")
		item.draft.selections.clear(); item.completed=0; item.draft.snapshots[0].rows=[]
		item.apply_last_material(0)
		check(item.completed==0 and item.closest_material_shortage(),"Empty furniture supply never submits placement")
		item.handle_back(); check(item.closed and item.material_strategy=="closest","Furniture Closest cancellation preserves preference")
		item.free()
	var windmill: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/windmill.json"))
	var mill:=Probe.new(); mill.material_view=StubView.new(); mill.mode="materials"; mill.material_strategy="closest"
	mill.draft.definition={"key":"Windmill"}; mill.draft.preview_valid=true; mill.draft.filters=[{"index":0,"quantity":4}]
	var mill_rows:Array=[]
	for index in windmill.native_closest.capture.groups.size():
		mill_rows.append({"item_type":5,"item_subtype":-1,"mat_type":0,"mat_index":index,"count":2})
	mill.draft.snapshots[0]={"revision":1,"next_cursor":0,"rows":mill_rows}
	mill.apply_last_material(0)
	check(mill.completed==1 and mill.draft.selections.size()==2,"Windmill Closest fills the first two native groups")
	for index in 2:
		check(int(mill.draft.selections[index].count)==windmill.native_closest.capture.groups[index].selection.size(),"Windmill native group quantities match")
	mill.free()
	print("CONSTRUCTION_CLOSEST ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
