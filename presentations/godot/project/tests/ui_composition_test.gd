extends SceneTree
# Exercise the real main-scene wiring and lazy product registry, offline.
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1200,800)
	OS.set_environment("DF3D_FIXTURE", ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix"))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	check(scene._ui != null, "main scene composes UI")
	var ui = scene._ui
	check(ui.has_node("TileHover") and ui.get_node("TileHover").actions==ui.actions, "Native world hover uses the shared semantic service")
	# This test owns navigation/session transitions explicitly; asynchronous
	# fixture polling must not reset the panels during deferred HUD layout.
	ui.actions.set_process(false)
	check(ui.controllers.is_empty(), "startup constructs no dormant panels")
	check(ui.controller("retired") == null, "unknown factory is unavailable")
	var readout = ui.controller("readouts")
	check(readout == ui.controller("readouts"), "accepted controller is reused")
	ui.open_destination("Residents")
	check(ui.host.active == readout and readout.panel.visible, "resident route activates its view")
	check(scene._interaction.construction_active, "readout owns map input")
	ui.open_destination("Build / construction")
	var construction = ui.controller("construction")
	check(ui.host.active == construction and not readout.panel.visible, "opening editor replaces readout")
	var hud = scene._fortress_hud
	hud.update_state(true,true,{})
	check(hud.active_launcher == "Build / construction" and not hud.navigation["Build / construction"].disabled,"route ownership enables its own launcher toggle")
	check(hud.navigation.Dig.disabled and hud.navigation.Citizens.disabled,"other launchers cannot steal modal placement")
	check(hud.navigation["Build / construction"].icon == hud.ui.texture("BUTTON_LOWER_MENU"),"active Build uses native lower-menu arrow")
	hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == null and not construction.panel.visible,"own launcher closes placement and releases map input")
	hud.update_state(true,true,{})
	hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == construction and construction.panel.visible,"launcher routes back to the same construction controller")
	hud.toggle_settings(); hud.navigation["Build / construction"].pressed.emit()
	check(ui.host.active == construction and construction.panel.visible,"HUD overlay prevents toggle dispatch behind it")
	hud.close_menus()
	ui.open_destination("Stockpiles / zones")
	check(ui.host.active == ui.controller("areas") and not construction.panel.visible, "area route replaces editor")
	var areas = ui.controller("areas")
	check(areas.focus_requested.is_connected(ui.focus_tile),"area selector recenter reaches shared camera navigation")
	hud.update_state(true,true,{})
	check(hud.active_launcher == "Stockpiles" and not hud.navigation.Stockpiles.disabled,"stockpile owns its launcher toggle")
	check(hud.navigation.Stockpiles.icon == hud.ui.texture("BUTTON_LOWER_MENU"),"active stockpile uses native lower-menu arrow")
	hud.navigation.Stockpiles.pressed.emit()
	check(ui.host.active == null and not areas.panel.visible,"stockpile launcher closes its own mode")
	ui.open_destination("Zones")
	check(areas.kind_picker.selected == 1 and areas.launcher_destination == "Zones" and areas.panel.visible,"Zone route reuses area controller with zone kind")
	hud.update_state(true,true,{})
	hud.navigation.Zones.pressed.emit()
	check(ui.host.active == null and not areas.panel.visible and not scene._interaction.construction_active,"zone launcher closes its own mode and releases map input")
	for destination in ["Stockpiles","Zones"]:
		ui.open_destination(destination)
		areas._detach_draft(); areas.new_area()
		var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
		root.push_input(escape)
		check(ui.host.active == null and not areas.panel.visible and not scene._interaction.construction_active,"top-level Escape closes %s and releases map input" % destination)
	ui.open_destination("Stockpiles")
	check(areas.kind_picker.selected == 0 and areas.mode == "paint" and areas.panel.visible,"Stockpile route switches out of zone mode")
	hud.update_state(true,true,{})
	await process_frame
	hud.update_state(true,true,{})
	hud.layout(hud.logical_view_size()); areas._process(0)
	var anchor: Rect2 = hud.launcher_rect("Stockpiles")
	check(anchor.has_area() and is_equal_approx(areas.paint_view.tools.position.x,anchor.position.x),"paint tools use actual HUD launcher anchor: %s / %s visible=%s" % [anchor,areas.paint_view.tools.position,areas.paint_view.tools.visible])
	ui.actions.session_changed.emit()
	check(ui.host.active == null and not scene._interaction.construction_active, "session change releases local view")
	ui.host.set_play_enabled(false)
	ui.open_destination("Residents")
	check(ui.host.active == null, "disabled play refuses routes")
	check(ui.controllers.size() == 3, "inspector remains lazy")
	var workshop = ui.controller("workshop")
	workshop._process(0)
	check(workshop.selector.size.x==608 and workshop.selector.scrollbar.position.x==584,"workshop selector uses native76-cell width")
	check(workshop==ui.controller("workshop") and not workshop.play_enabled,"staged workshop shares factory and disabled-play lifecycle")
	check(workshop.unit_requested.get_connections().size()==1,"assigned portrait connects to creature navigation")
	check(workshop.item_owner.carrier_requested.is_connected(ui.open_item_carrier),"workshop items share carrier navigation")
	check(not ui.Registry.PANEL_ROUTES.values().has("workshop"),"unfinished workshop has no public launcher")
	ui.host.set_play_enabled(true)
	workshop.open_workshop(37,"BUILDING_ICON_WORKSHOP_STILL")
	check(ui.host.active==workshop and workshop.state.building_id==37,"composed workshop owns its target")
	workshop.workers.phase=workshop.workers.Phase.Ready
	workshop.selector.rows=[{"unit_id":7}]
	workshop.candidate_modes.ids=[7]
	workshop.candidate_modes.receipts={7:{"only_assigned_jobs":true}}
	workshop.selector.show()
	var mode_hover:=InputEventMouseMotion.new();mode_hover.position=Vector2(520,54)
	workshop.selector._gui_input(mode_hover);workshop.selector._process(0)
	check(hud.native_help.state.key=="specialization_1","selector mode hover uses native specialization tooltip")
	workshop.selector.hide()
	check(hud.native_help.state.key.is_empty(),"closing selector releases tooltip ownership")
	ui.actions.session_changed.emit()
	check(ui.host.active==null and workshop.state.building_id==-1 and workshop.workers.building_id==-1,"session change retires composed workshop")
	# A standalone list has no selected building to drive its retirement. Cover
	# each child while its first read is still queued in the real shared service.
	for child in ["list","conditions","details","picker"]:
		workshop.open_global_orders()
		check(ui.host.active==workshop and workshop.global_orders_mode,"standalone orders claim input")
		match child:
			"conditions":
				workshop.global_orders_view.hide();workshop.conditions_view.open(-2,27)
				workshop.conditions.filter_query="IRON"
			"details":
				workshop.global_orders_view.hide();workshop.details_view.open(-2,27)
				workshop.details.draft_dirty=true;workshop.details.draft_discard=true
				workshop.details.draft_value={"elements":[{"kind":1}],"relationships":[]}
			"picker":
				workshop.global_orders_view.hide();workshop.order_picker.open(-2,"","")
		var order_reads: Array=[]
		for model in [workshop.global_orders,workshop.conditions,workshop.details,workshop.order_choices]:
			if model.ticket!=0:order_reads.append(model.ticket)
		check(not order_reads.is_empty(),"standalone retirement starts with queued reads")
		ui.actions.session_changed.emit()
		await process_frame;await process_frame
		check(ui.host.active==null and not workshop.global_orders_mode and not scene._interaction.construction_active,"session change releases standalone "+child)
		for view in [workshop.global_orders_view,workshop.conditions_view,workshop.details_view,workshop.order_picker]:
			check(not view.visible,"session change hides standalone "+child)
		check(workshop.global_orders.ticket==0 and workshop.conditions.ticket==0 and workshop.details.ticket==0 and workshop.order_choices.ticket==0,"session change retires order reads")
		for ticket in order_reads:
			check(not ui.actions._queue.has(ticket) and not ui.actions._requests.has(ticket),"retired order read cannot dispatch later")
		check(workshop.conditions.order_id==-1 and workshop.conditions.filter_query.is_empty(),"session change clears condition target/search")
		check(workshop.details.order_id==-1 and not workshop.details.draft_dirty and not workshop.details.draft_discard and workshop.details.draft_value.elements.is_empty(),"session change clears artwork draft")
	for dimensions in [Vector2(1200,800),Vector2(1600,900)]:
		workshop.open_global_orders();workshop.global_orders_view.layout(dimensions)
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		click.position=Vector2(200,48 if dimensions.x==1200 else 24)
		workshop.global_orders_view._gui_input(click)
		check(ui.host.active==ui.controller("places"),"Places tab opens staged Places, not Zones")
		workshop.open_global_orders();workshop.global_orders_view.layout(dimensions)
		click.position=Vector2(24,48 if dimensions.x==1200 else 24)
		workshop.global_orders_view._gui_input(click)
		check(ui.host.active==ui.controller("residents") and not workshop.global_orders_view.visible,"Creatures tab routes and retires standalone orders")
		workshop.open_global_orders();workshop.global_orders_view.hide();workshop.conditions_view.open(-2,27);workshop.conditions_view.layout(dimensions)
		click.position=Vector2(352,48 if dimensions.x==1200 else 24)
		workshop.conditions_view._gui_input(click)
		check(ui.host.active==workshop and workshop.conditions_view.visible and workshop.conditions.order_id==27,"selected Work orders tab retains Conditions")
		click.position=Vector2(280,48 if dimensions.x==1200 else 24)
		workshop.conditions_view._gui_input(click)
		check(ui.host.active==ui.controller("work_details") and not workshop.conditions_view.visible and workshop.conditions.order_id==-1,"Labor tab routes and retires Conditions")
	var places=ui.controller("places")
	for dimensions in [Vector2(912,552),Vector2(1600,900)]:
		for target in [[24,"residents"],[136,"tasks"],[280,"work_details"],[352,"workshop"]]:
			places.open_panel();places.panel.layout(dimensions)
			var pending: int=places.state.ticket
			check(pending>0,"Places begins with a queued owned read")
			var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=Vector2(target[0],48 if dimensions.x<1240 else 24)
			places.panel._gui_input(click)
			check(ui.host.active==ui.controller(target[1]) and not places.panel.visible,"Places header reaches native controller "+target[1])
			check(places.state.phase==places.state.Phase.Closed and not ui.actions._requests.has(pending) and not ui.actions._queue.has(pending),"Information handoff retires Places read")
			if target[1]=="workshop":check(workshop.global_orders_mode,"Work orders opens global list without workshop target")
			var target_view=workshop.global_orders_view if target[1]=="workshop" else ui.controller(target[1]).panel
			target_view.layout(dimensions)
			click.position=Vector2(200,48 if dimensions.x<1240 else 24);target_view._gui_input(click)
			check(ui.host.active==places and not target_view.visible,"Information screen returns to Places "+target[1])
		places.open_panel();places.panel.layout(dimensions);places.state.select_tab(4)
		var pending: int=places.state.ticket
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		click.position=Vector2(200,48 if dimensions.x<1240 else 24);places.panel._gui_input(click)
		check(places.state.tab==4 and places.state.ticket==pending,"Selected Places header retains subtab/read")
		for point in ([Vector2(256,24),Vector2(328,24)] if dimensions.x<1240 else [Vector2(688,24),Vector2(760,24)]):
			click.position=point;places.panel._gui_input(click)
			check(ui.host.active==places and places.state.ticket==pending,"Unfinished information route stays gated")
		ui.host.set_overlay_blocked(true)
		places.information_requested.emit("Creatures")
		check(ui.host.active==places,"Overlay blocks information handoff")
		ui.host.set_overlay_blocked(false)
	var nobles=ui.controller("nobles")
	check(nobles==ui.controller("nobles") and not ui.Registry.allows_launcher("Nobles and administrators"),"Nobles factory is reused without public exposure")
	for dimensions in [Vector2(912,552),Vector2(1600,900)]:
		places.open_panel();places.panel.layout(dimensions)
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		click.position=Vector2(24 if dimensions.x<1240 else 456,24);places.panel._gui_input(click)
		check(ui.host.active==nobles and not places.panel.visible,"Native Nobles header opens composed owner")
		nobles.state._retire();nobles.state.phase=nobles.state.Phase.Ready;nobles.panel.layout(dimensions)
		var pending: int=nobles.state.ticket
		nobles.panel.information_requested.emit("Justice")
		check(ui.host.active==nobles and nobles.state.ticket==pending,"Unavailable Nobles destination does not dismiss or commit")
		click.position=Vector2(136,24);nobles.panel._gui_input(click)
		check(ui.host.active==ui.controller("tasks") and not nobles.panel.visible,"Completed Nobles handoff reaches Tasks after source release: width=%s phase=%s active=%s"%[dimensions.x,nobles.state.phase,ui.host.active])
		nobles.information_requested.emit("Places")
		check(ui.host.active==ui.controller("tasks"),"Closed Nobles cannot navigate with an unsolicited signal")
	for outcome in ["applied","unknown","reset"]:
		nobles.open_panel();nobles.state._retire();nobles.state.phase=nobles.state.Phase.Ready
		nobles.state._revision=123
		nobles.state.choices=[{"target":{"entity_id":865,"position_id":10,"assignment_id":6,"draft_slot":0},"expected_unit_id":-1,"unit_id":6598}]
		nobles.panel.information_requested.emit("Work orders")
		var pending: int=nobles.state.ticket
		check(pending>0 and ui.host.active==nobles and nobles.state.phase==nobles.state.Phase.Applying,"Composed handoff retains source until commit")
		var C=preload("res://scripts/management_contract.gd")
		check(ui.actions._requests[pending].request.action==C.ManagementAction.NoblesCommit,"Composed handoff submits appointment commit")
		var observer: Callable=ui.actions._requests[pending].observer
		if outcome=="reset":ui.host.reset_local_views()
		observer.call(pending,{"action":C.ManagementAction.NoblesCommit,"status":C.ManagementStatus.Ok,"nobles":{"outcome":C.NoblesOutcome.Applied},"outcome":"unknown" if outcome=="unknown" else "applied"},true)
		if outcome=="applied":check(ui.host.active==workshop and workshop.global_orders_mode,"Confirmed Nobles handoff opens global Work orders")
		elif outcome=="unknown":check(ui.host.active==nobles and nobles.state.phase==nobles.state.Phase.Unknown,"Unknown Nobles result retains owner and blocks navigation")
		else:check(ui.host.active==null,"Reset suppresses late Nobles navigation")
		ui.host.reset_local_views()
	nobles.open_panel();var noble_read: int=nobles.state.ticket;ui.actions.session_changed.emit()
	check(ui.host.active==null and not nobles.panel.visible and nobles.state.ticket==0 and not ui.actions._requests.has(noble_read),"Session change retires composed Nobles read")
	var standing=ui.controller("standing_orders")
	for dimensions in [Vector2(912,552),Vector2(1600,900)]:
		for page in ["standing","chores","kitchen","stone"]:
			standing.open_panel()
			match page:
				"chores":standing.open_chores()
				"kitchen":standing.open_kitchen()
				"stone":standing.open_stone_use()
			var model=standing.current_state()
			var labor_view=standing.panel if page=="standing" else standing.chores_panel if page=="chores" else standing.kitchen_panel if page=="kitchen" else standing.stone_panel
			labor_view.layout(dimensions)
			var pending: int=model.ticket
			var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=Vector2(280,48 if dimensions.x<1240 else 24);labor_view._gui_input(click)
			check(ui.host.active==standing and model.ticket==pending,"Selected Labor retains "+page)
			model.phase=model.Phase.Applying
			click.position=Vector2(200,48 if dimensions.x<1240 else 24);labor_view._gui_input(click)
			check(ui.host.active==standing,"Pending Labor mutation prevents handoff")
			model.phase=model.Phase.Reading;labor_view._gui_input(click)
			check(ui.host.active==places and not labor_view.visible,"Labor header opens Places from "+page)
			check(model.ticket==0 and not ui.actions._queue.has(pending) and not ui.actions._requests.has(pending),"Labor handoff retires read from "+page)
	ui.host.close_active()
	places.information_requested.emit("Tasks")
	check(ui.host.active==null,"Closed Places cannot steal input")
	check(not ui.Registry.PANEL_ROUTES.values().has("places"),"Internal handoffs do not expose Places launcher")
	print("ui_composition_test: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
