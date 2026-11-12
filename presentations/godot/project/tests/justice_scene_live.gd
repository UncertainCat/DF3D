extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "justice-sheet-navigation.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("justice")
	for sample in expected.samples:
		owner.open_panel();await drain()
		var tab:=3 if sample.tab=="Fortress guard" else 4
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(tab).get_center());await drain()
		var roster=owner.state.guard if tab==3 else owner.state.convicts
		if not check(roster.phase==roster.Phase.Ready and not roster.rows.is_empty(),"Justice scene roster unavailable"):return
		check(roster.rows[0].unit_id==int(sample.unit_id),"Justice scene target differs from native")
		await pointer(owner.panel.get_global_transform_with_canvas()*(owner.panel.guard_rect(0).position+Vector2(332,18)));await drain()
		var inspector=scene._ui.controller("inspector")
		if not check(scene._ui.host.active==inspector and inspector.panel.visible and inspector.selected.get("id")==int(sample.unit_id),"Justice sheet click did not open exact creature in main scene"):return
		var deadline:=Time.get_ticks_msec()+10000
		while inspector.creature_display.get("detail",{}).is_empty() and Time.get_ticks_msec()<deadline:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		check(not inspector.creature_display.get("detail",{}).is_empty(),"Justice creature sheet details did not load")
		for row in inspector.creature_sheet.records_for("skills"):
			var group:=int(inspector.creature_sheet.fact_value(row,"overview_group",-1))
			check(sample.skill_groups.has(str(row.id)) and group==int(sample.skill_groups.get(str(row.id),-2)),"Overview skill group differs from native collection")
		check(owner.panel.visible==bool(sample.info_open),"Justice visibility behind native sheet differs")
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/justice-main-sheet-%d.png"%tab)
		key(KEY_ESCAPE);await process_frame;await drain()
		check(inspector.panel.visible==bool(sample.after_escape_sheet_open),"Sheet Escape differs from native")
		check(owner.panel.visible==bool(sample.after_escape_info_open),"Justice return visibility differs from native")
		check(scene._ui.host.active==(owner if sample.after_escape_info_open else null),"Sheet Escape retained wrong input owner")
	exercised=true
