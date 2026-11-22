extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/creature-tabs-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Creature list bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Creature list catalog failed"):quit(1);return
	var results: Array=[]
	for snapshot: Dictionary in expected:
		var tab:=int(snapshot.tab)
		if tab==0:continue
		var intent: Dictionary={"action":C.ManagementAction.CreatureListQuery,"tab":tab,"sort":0,"descending":false,"query_bytes":str(snapshot.query).to_utf8_buffer()}
		var response:=await request("creature_list",intent)
		var value: Dictionary=response.get("creature_list",{})
		var rows: Array=value.get("entries",[])
		var matches: bool=response.get("status")==C.ManagementStatus.Ok and value.get("tab",-1)==tab and rows.size()==snapshot.rows.size()
		for i in mini(rows.size(),snapshot.rows.size()):
			matches=matches and int(rows[i].kind)==int(snapshot.rows[i].kind) and int(rows[i].id)==int(snapshot.rows[i].id)
		check(matches,"Creature list wire differs: tab "+str(tab)+" query "+str(snapshot.query))
		results.append({"tab":tab,"query":snapshot.query,"count":rows.size(),"matches":matches})
	for tab in [0,4]:
		check(world.management_request("creature_list",{"action":C.ManagementAction.CreatureListQuery,"tab":tab,"sort":0,"descending":false,"query_bytes":PackedByteArray()})==0,"Invalid tab admitted")
	for sort in [3,5]:
		check(world.management_request("creature_list",{"action":C.ManagementAction.CreatureListQuery,"tab":2,"sort":sort,"descending":false,"query_bytes":PackedByteArray()})==0,"Invalid Other sort admitted")
	var cleared:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(not cleared.has("creature_list"),"Unrelated reply retained creature list")
	if OS.get_environment("DF3D_CREATURE_WORKFLOWS_WIRE")=="1":
		await workflows()
	var file:=FileAccess.open(directory+"/creature-list-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"results":results}));file.close()
	world.detach_live();world.queue_free();await process_frame
	quit(1 if failed else 0)

func read_rows(tab: int,targets: Array) -> Array:
	var response:=await request("creature_list_rows",{"action":C.ManagementAction.CreatureListRowsRead,"tab":tab,"targets":targets,"columns":30})
	check(response.get("status")==C.ManagementStatus.Ok,"Creature rows rejected: "+str(response.get("message","")))
	return response.get("creature_list_rows",{}).get("rows",[])

func check_warning(row: Dictionary,grazer: bool) -> void:
	check(row.has("name_warning")==grazer,"Native grazer warning presence differs")
	if grazer:
		var warning: Dictionary=row.get("name_warning",{})
		check(warning.get("text")=="Grazer: requires pasture" and warning.get("foreground")==2 and warning.get("background")==0 and warning.get("bright")==true,"Native grazer warning differs")

func workflows() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/creature-workflows-wire-reference.json"))
	var editable: Array=[]
	var trainer_cases: Array=[]
	var counts: Dictionary={}
	for tab in [1,2,3]:
		var expected: Array=reference.tabs[str(tab)]
		counts[str(tab)]=0
		for offset in range(0,expected.size(),64):
			var targets: Array=[]
			for v: Dictionary in expected.slice(offset,offset+64):targets.append({"kind":int(v.kind),"id":int(v.id)})
			var rows:=await read_rows(tab,targets)
			if not check(rows.size()==targets.size(),"Creature row batch incomplete"):return
			for i in rows.size():
				var row: Dictionary=rows[i];var native: Dictionary=expected[offset+i];var value: Dictionary=native.text
				check(row.kind==int(native.kind) and row.id==int(native.id),"Creature row identity differs")
				check(row.can_inspect==(tab!=3) and row.has("position")== (tab!=3),"Creature row navigation differs")
				if tab!=3:check(row.position==Vector3i(int(native.position[0]),int(native.position[1]),int(native.position[2])),"Creature raw position differs")
				if row.kind==0:
					check_warning(row,native.grazer)
					check(row.first_line==value.first_line and row.second_line==value.second_line,"Creature name differs")
					for key in ["color","alternate"]:check(PackedInt32Array(row.name_color[key])==PackedInt32Array(value.name_color[key]),"Creature name color differs")
					check(row.name_color.effect==int(value.name_color.effect),"Creature name effect differs")
					check(row.activity.text==value.activity.caption and row.activity.foreground==int(value.activity.fg) and row.activity.background==int(value.activity.bg) and row.activity.bright==value.activity.bright,"Creature activity differs")
				else:
					check(row.first_line==value.caption and row.second_line=="" and PackedInt32Array(row.name_color.color)==PackedInt32Array(value.color),"Creature item name differs")
					check(row.activity.text==value.activity and row.activity.foreground==int(value.activity_color[0]) and row.activity.bright==bool(value.activity_color[2]),"Creature item activity differs")
					var art: Dictionary=row.get("portrait",{})
					if check(art.get("layers",[]).size()==1,"Creature item selector missing"):
						var layer: Array=art.layers[0]
						check(art.tile_pages[layer[0]]==native.art.page and layer[1]==int(native.art.x) and layer[2]==int(native.art.y),"Creature item selector differs")
				check(row.has("pet")==(tab==1),"Pet controls on wrong tab")
				if tab==1:
					var pet: Dictionary=row.pet
					check(pet.revision==int(native.pet.revision),"Pet receipt differs")
					check(pet.captions.size()==native.controls.captions.size() and pet.owners.size()==native.owners.size() and pet.controls.size()==native.controls.actions.size(),"Pet control counts differ")
					for j in mini(pet.captions.size(),native.controls.captions.size()):
						check(pet.captions[j].text==native.controls.captions[j] and pet.captions[j].foreground==int(native.controls.caption_colors[j][0]),"Pet caption differs")
					for j in mini(pet.owners.size(),native.owners.size()):
						check(pet.owners[j].id==int(native.owners[j].id) and pet.owners[j].first_line==native.owners[j].first_line and pet.owners[j].second_line==native.owners[j].second_line,"Pet owner differs")
					for control: Dictionary in pet.controls:
						check(control.value==native.pet.values[control.action],"Pet action value differs")
						if control.action<=2:editable.append({"target":targets[i],"control":control,"revision":pet.revision})
					if native.has("trainers"):trainer_cases.append({"id":row.id,"revision":pet.revision,"native":native.trainers,"header":native.get("trainer_header","")})
				counts[str(tab)]+=1
	for sample: Dictionary in trainer_cases:
		var ids:=PackedInt32Array()
		for row: Dictionary in sample.native:ids.append(int(row.id))
		for offset in range(0,maxi(1,ids.size()),64):
			var response:=await request("pet_trainers",{"action":C.ManagementAction.PetTrainersRead,"animal_id":sample.id,"expected_revision":sample.revision,"columns":30,"unit_ids":ids.slice(offset,offset+64)})
			var state: Dictionary=response.get("pet_trainers",{})
			if not check(response.get("status")==C.ManagementStatus.Ok and state.get("unit_ids")==ids,"Trainer order differs"):return
			if not sample.header.is_empty():check(state.header==sample.header,"Trainer heading differs from captured native widget: expected="+sample.header+" observed="+state.header)
			for i in state.rows.size():
				check(state.rows[i].id==ids[offset+i] and state.rows[i].skills==sample.native[offset+i].skills,"Trainer skills differ")
				check_warning(state.rows[i],sample.native[offset+i].grazer)
		if failed:return
		if not check(not ids.is_empty(),"Trainer fixture has no candidate"):return
		for mode in [C.PetTrainerMode.Any,C.PetTrainerMode.Unassigned,C.PetTrainerMode.Individual,C.PetTrainerMode.None]:
			var target: Dictionary={"kind":0,"id":sample.id}
			var current:=await read_rows(1,[target]);if current.is_empty():return
			var trainer_id: int=ids[0] if mode==C.PetTrainerMode.Individual else -1
			var result:=await request("pet_trainer",{"action":C.ManagementAction.PetTrainerApply,"animal_id":sample.id,"expected_revision":current[0].pet.revision,"mode":mode,"trainer_id":trainer_id})
			if not check(result.get("status")==C.ManagementStatus.Ok and result.get("pet_edit",{}).get("outcome")==C.PetOutcome.Applied,"Trainer edit failed; no replay"):return
			current=await read_rows(1,[target]);if current.is_empty():return
			var observed:=await request("pet_trainers",{"action":C.ManagementAction.PetTrainersRead,"animal_id":sample.id,"expected_revision":current[0].pet.revision,"columns":30,"unit_ids":PackedInt32Array()})
			var state: Dictionary=observed.get("pet_trainers",{})
			if not check(observed.get("status")==C.ManagementStatus.Ok,"Trainer readback rejected"):return
			check(state.assigned==(mode!=C.PetTrainerMode.None) and state.trainer_id==trainer_id and state.any_trainer==(mode==C.PetTrainerMode.Any) and state.unassigned_only==(mode==C.PetTrainerMode.Unassigned),"Trainer readback differs")
	var knowledge: Array=[];var revision:=0
	while knowledge.size()<reference.knowledge.size():
		var response:=await request("pet_knowledge",{"action":C.ManagementAction.PetKnowledgeRead,"expected_revision":revision,"offset":knowledge.size(),"limit":16})
		var state: Dictionary=response.get("pet_knowledge",{})
		if not check(response.get("status")==C.ManagementStatus.Ok and not state.get("rows",[]).is_empty(),"Knowledge page rejected"):return
		check(revision==0 or revision==state.revision,"Knowledge receipt changed across pages");revision=state.revision;knowledge.append_array(state.rows)
	check(knowledge.size()==reference.knowledge.size(),"Knowledge count differs")
	for i in mini(knowledge.size(),reference.knowledge.size()):
		var row: Dictionary=knowledge[i];var native: Dictionary=reference.knowledge[i]
		check(row.race==int(native.race) and row.level==int(native.level) and row.name==native.name and row.knowledge.text==native.caption and row.knowledge.foreground==int(native.foreground) and row.knowledge.bright==native.bright,"Knowledge row differs")
	var stale:=await request("pet_knowledge",{"action":C.ManagementAction.PetKnowledgeRead,"expected_revision":1 if revision!=1 else 2,"offset":16,"limit":16})
	check(stale.get("status")==C.ManagementStatus.Rejected and not stale.has("pet_knowledge"),"Stale knowledge page admitted")
	var edits:=0;var seen: Dictionary={}
	for sample: Dictionary in editable:
		if failed:return
		var key:=str(sample.target.kind)+":"+str(sample.control.action)
		if seen.has(key):continue
		seen[key]=true
		var current:=await read_rows(1,[sample.target]);if current.is_empty():return
		var intent: Dictionary={"action":C.ManagementAction.PetActionApply,"target":sample.target,"expected_revision":current[0].pet.revision,"pet_action":sample.control.action,"desired":not sample.control.value}
		var result:=await request("pet_action",intent)
		if not check(result.get("status")==C.ManagementStatus.Ok and result.get("pet_edit",{}).get("outcome")==C.PetOutcome.Applied,"Pet edit failed; no replay"):return
		var replay:=await request("pet_action",intent)
		check(replay.get("status")==C.ManagementStatus.Rejected and replay.get("pet_edit",{}).get("outcome")==C.PetOutcome.Stale,"Stale pet edit admitted")
		current=await read_rows(1,[sample.target]);if current.is_empty():return
		intent.expected_revision=current[0].pet.revision;intent.desired=sample.control.value
		result=await request("pet_action",intent)
		if not check(result.get("status")==C.ManagementStatus.Ok,"Pet restore failed; no replay"):return
		edits+=1
	var cleared:=await request("construction",{"action":C.ManagementAction.Catalog})
	for key in ["creature_list_rows","pet_edit","pet_trainers","pet_knowledge"]:check(not cleared.has(key),"Unrelated reply retained "+key)
	var file:=FileAccess.open(directory+"/creature-workflows-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"counts":counts,"trainer_cases":trainer_cases.size(),"knowledge_rows":knowledge.size(),"edit_families":edits}));file.close()
