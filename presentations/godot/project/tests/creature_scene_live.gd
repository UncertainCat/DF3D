extends "res://tests/workshop_order_wire_live.gd"
# Protected public main-scene acceptance, without product-gate overrides.
var owner
var service

func tab_click(view,index: int) -> void:
	var x:=8
	for caption in ["Residents","Pets/Livestock","Other","Dead/Missing"].slice(0,index):x+=(caption.length()+4)*8
	click(view.position+Vector2(x+16,view.list_top()-48))

func ready() -> bool:
	return await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and not owner.pet_open())

func pet_ready() -> bool:
	return await settle(service,func():return owner.pet_state.phase==owner.pet_state.Phase.Ready)

func wheel(view,steps: int) -> void:
	for index in absi(steps):
		var event:=InputEventMouseButton.new();event.pressed=true
		event.button_index=MOUSE_BUTTON_WHEEL_DOWN if steps>0 else MOUSE_BUTTON_WHEEL_UP
		event.position=view.position+Vector2(400,view.content_top()+18)
		root.push_input(event,true)
		if not check(await pet_ready(),"Pet pane scroll failed"):return

func pet_actions() -> void:
	var covered: Dictionary={}
	for page in 20:
		for index in owner.panel.page_rows:
			var row: Dictionary=owner.state.row_at(owner.state.first+index)
			var key: int=owner.panel.RosterState.row_key(row) if not row.is_empty() else -1
			for control: Dictionary in owner.panel.PetRow.controls(row,owner.panel.list_top()+index*36):
				var family:=str(row.kind)+":"+str(control.action)
				if control.action==C.PetAction.Trainer or covered.has(family):continue
				var point: Vector2=owner.panel.position+control.rect.get_center()
				click(point)
				if not check(await ready(),"Pet button edit failed; no retry"):return
				var changed: Dictionary=owner.state.rows.get(key,{})
				var observed: Array=changed.get("pet",{}).get("controls",[]).filter(func(value):return value.action==control.action)
				if not check(observed.size()==1 and observed[0].value!=control.control.value,"Pet button readback differs"):return
				var help_id: int=owner.panel.PetHelp.observed(observed[0])
				if not check(help_id>=0,"Pet shortcut has no native help evidence"):return
				# Restore through the native pointer-context keyboard shortcut.
				for pressed in [true,false]:
					var event:=InputEventKey.new();event.keycode=owner.panel.PetHelp.ENTRIES[help_id].key
					event.ctrl_pressed=true;event.pressed=pressed;root.push_input(event,true)
				if not check(await ready(),"Pet shortcut edit failed; no retry"):return
				observed=owner.state.rows.get(key,{}).get("pet",{}).get("controls",[]).filter(func(value):return value.action==control.action)
				check(observed.size()==1 and observed[0].value==control.control.value,"Pet shortcut restoration differs")
				covered[family]=true
		if owner.state.first+owner.state.capacity>=owner.state.ids.size():break
		number_key(KEY_PAGEDOWN)
		if not check(await ready(),"Pet action paging failed"):return
	check(covered.size()==6 and covered.has("1:1"),"Expected five unit and one item edit families missing")
	print("Main-scene pet action families: ",covered.keys())

func other_and_dead(scene) -> void:
	var activity_index:=-1
	for index in owner.state.capacity:
		if owner.state.row_at(index).has("activity_target"):activity_index=index;break
	if not check(activity_index>=0,"Other activity fixture missing"):return
	click(owner.panel.position+Vector2(636,owner.panel.list_top()+activity_index*36+18))
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.ActivityReady),"Other activity did not open"):return
	check(not owner.state.activity_page.get("words",[]).is_empty(),"Other activity empty")
	for dimensions in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.ActivityReady),"Other activity resize failed"):return
	click(owner.panel.position+owner.panel.activity_close_rect().get_center())
	if not check(await ready(),"Other activity Close failed"):return
	var target: Dictionary=owner.state.row_at(owner.state.first)
	click(owner.panel.position+Vector2(348,owner.panel.list_top()+18))
	var inspector=scene._ui.controller("inspector")
	if not check(await settle(service,func():return scene._ui.host.active==inspector),"Other creature-sheet handoff failed"):return
	check(inspector.selected.get("id",-1)==int(target.id),"Other opened wrong creature")
	scene._ui.host.close_active();await process_frame
	click(scene._fortress_hud.launcher_rect("Citizens").get_center())
	if not check(await ready(),"Citizens reopen after Other failed"):return
	tab_click(owner.panel,3)
	if not check(await ready() and owner.state.tab==3,"Dead tab failed"):return
	var original: PackedInt32Array=owner.state.ids.duplicate()
	number_key(KEY_PAGEDOWN)
	if not check(await ready() and owner.state.first>0,"Dead paging failed"):return
	for index in owner.state.capacity:
		var row: Dictionary=owner.state.row_at(owner.state.first+index)
		if not row.is_empty():check(not row.can_inspect and not row.has("position"),"Dead exposes unsupported navigation")
	click(owner.panel.position+Vector2(348,owner.panel.list_top()+18))
	await process_frame
	check(scene._ui.host.active==owner and owner.state.phase==owner.state.Phase.Ready,"Dead blank navigation handed off")
	for dimensions in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await ready(),"Dead resize failed"):return
		check(owner.state.ids==original,"Dead resize changed membership")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/creature-scene-dead.png")

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	Engine.max_fps=30;OS.set_environment("DF3D_FIXTURE","")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	root.size=Vector2i(1200,800)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+60000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(scene._loader.entered,"Creature main scene did not enter"):quit(1);return
	service=scene._ui.actions;service.set_process(false)
	owner=scene._ui.controller("residents")
	click(scene._fortress_hud.launcher_rect("Citizens").get_center())
	if not check(await ready(),"Citizens did not open"):quit(1);return
	tab_click(owner.panel,1)
	if not check(await ready() and owner.state.tab==1,"Pets tab did not open"):quit(1);return
	# Reach the controlled trainer animal through ordinary roster scrolling.
	var trainer_point:=Vector2.ZERO
	var animal_id:=-1
	for page in 20:
		for index in owner.panel.page_rows:
			var row: Dictionary=owner.state.row_at(owner.state.first+index)
			for control: Dictionary in owner.panel.PetRow.controls(row,owner.panel.list_top()+index*36):
				if control.action==C.PetAction.Trainer:
					trainer_point=owner.panel.position+control.rect.get_center();animal_id=int(row.id);break
			if animal_id>=0:break
		if animal_id>=0:break
		number_key(KEY_PAGEDOWN)
		if not check(await ready(),"Pets paging failed"):quit(1);return
	if not check(animal_id>=0,"Trainer fixture not reachable"):quit(1);return
	click(trainer_point)
	if not check(await pet_ready(),"Trainer picker did not open"):quit(1);return
	check(owner.pet_state.animal_id==animal_id and not owner.panel.visible,"Trainer owner mismatch")
	await wheel(owner.pet_panel,70)
	if not check(owner.pet_state.first>=64,"Trainer later page not reached"):quit(1);return
	for dimensions in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await pet_ready(),"Trainer resize failed"):quit(1);return
		for entry: Dictionary in owner.pet_panel.displayed:check(not entry.row.is_empty(),"Trainer visible page has missing rows")
	var choice: Dictionary=owner.pet_panel.displayed[0]
	var trainer_id:=int(choice.row.id)
	click(owner.pet_panel.position+Vector2(100,choice.y+18))
	if not check(await ready(),"Trainer selection did not return to roster; no retry"):quit(1);return
	click(trainer_point)
	if not check(await pet_ready(),"Trainer reopen failed"):quit(1);return
	check(owner.pet_state.snapshot.trainer_id==trainer_id and owner.pet_state.snapshot.assigned,"Trainer assignment readback differs")
	# The protected fixture starts unassigned. Restore through the native None
	# choice so the enclosing oracle can independently verify all pet effects.
	click(owner.pet_panel.position+Vector2(100,owner.pet_panel.content_top()+90))
	if not check(await ready(),"Trainer None did not restore roster; no retry"):quit(1);return
	click(trainer_point)
	if not check(await pet_ready(),"Restored trainer reopen failed"):quit(1);return
	check(not owner.pet_state.snapshot.assigned,"Trainer None readback differs")
	number_key(KEY_ESCAPE)
	if not check(await ready(),"Trainer Back failed"):quit(1);return
	click(owner.panel.position+owner.panel.activity_close_rect().get_center())
	if not check(await pet_ready() and not owner.pet_panel.is_trainers(),"Knowledge did not open"):quit(1);return
	await wheel(owner.pet_panel,35)
	check(owner.pet_state.first==35,"Knowledge later page not reached")
	for dimensions in [Vector2i(912,552),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await pet_ready(),"Knowledge resize failed"):quit(1);return
		for entry: Dictionary in owner.pet_panel.displayed:check(not entry.row.is_empty(),"Knowledge visible page has missing rows")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/creature-scene-knowledge.png")
	tab_click(owner.pet_panel,2)
	if not check(await ready() and owner.state.tab==2,"Knowledge to Other failed"):quit(1);return
	await other_and_dead(scene)
	if failed:quit(1);return
	for index in [3,0,1]:
		tab_click(owner.panel,index)
		if not check(await ready() and owner.state.tab==index,"Creature tab return failed"):quit(1);return
	await pet_actions()
	# War/hunting toggles can create a native training assignment even when
	# toggled back off. Retire that fixture effect through None as well.
	tab_click(owner.panel,0)
	if not check(await ready(),"Cleanup Residents return failed"):quit(1);return
	tab_click(owner.panel,1)
	if not check(await ready(),"Cleanup Pets return failed"):quit(1);return
	click(trainer_point)
	if not check(await pet_ready(),"Training cleanup picker failed"):quit(1);return
	click(owner.pet_panel.position+Vector2(100,owner.pet_panel.content_top()+90))
	if not check(await ready(),"Training cleanup None failed; no retry"):quit(1);return
	number_key(KEY_ESCAPE);await process_frame
	check(scene._ui.host.active==null,"Creature close retained input")
	var file:=FileAccess.open(directory+"/creature-list-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"animal_id":animal_id,"trainer_id":trainer_id,"main_scene":true}));file.close()
	scene.queue_free();await process_frame
	quit(1 if failed else 0)
