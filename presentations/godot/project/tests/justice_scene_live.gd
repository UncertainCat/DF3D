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
		var native_thoughts: String=" ".join(sample.thoughts)
		var quote:=""
		for row in inspector.creature_sheet.records_for("identity"):
			if inspector.creature_sheet.fact_value(row,"record_type")=="overview_quote":quote+=str(inspector.creature_sheet.fact_value(row,"native_text",""))
		check(quote.is_empty()==str(sample.quote).is_empty(),"Overview quote eligibility differs from native")
		FileAccess.open(directory+"/overview-quote-%d.json"%int(sample.unit_id),FileAccess.WRITE).store_string(JSON.stringify({"native":sample.quote,"viewer":quote}))
		var elaborations:=0
		var memory_evidence: Array=[]
		for row in inspector.creature_sheet.records_for("emotions"):
			var flags:=int(inspector.creature_sheet.fact_value(row,"mood_flags",0))
			if int(inspector.creature_sheet.fact_value(row,"thought_id",-1)) in [-1,6] or int(inspector.creature_sheet.fact_value(row,"emotion_id",-2)) in [165,166]:continue
			if (flags&0x70)==0 or (flags&0x180)==0:continue
			var clause:=str(inspector.creature_sheet.fact_value(row,"native_recalled_circumstance",""))
			var start:=clause.find(", [C:5:")
			var suffix:=clause.substr(start) if start>=0 else ""
			memory_evidence.append({"id":row.id,"flags":flags,"clause":clause,"suffix":suffix,"whole_clause_matches":native_thoughts.contains(clause)})
			check(suffix.contains("and mulling over the recurring memory ") and native_thoughts.contains(clause),"Recalled emotion elaboration differs from native")
			elaborations+=1
		FileAccess.open(directory+"/overview-memory-%d.json"%int(sample.unit_id),FileAccess.WRITE).store_string(JSON.stringify(memory_evidence))
		check(elaborations>0 if int(sample.unit_id)==6970 else true,"Convict reference no longer exercises recalled emotion elaboration")
		await process_frame;await RenderingServer.frame_post_draw
		var overview_text=inspector.body.find_child("OverviewText",true,false)
		if check(overview_text!=null,"Overview native text control unavailable"):
			check(overview_text.columns==int(sample.thought_layout.columns),"Overview wrap width differs from native")
			for index in mini(3,overview_text.paragraphs.size()):
				var actual=overview_text.Layout.new().build(overview_text.paragraphs[index],overview_text.columns)
				var expected_lines: Array=sample.thought_layout.paragraphs[index]
				if not check(actual.size()==expected_lines.size(),"Overview paragraph line count differs from native"):continue
				for line in actual.size():check(actual[line].text==expected_lines[line].text,"Overview paragraph wraps differently from native")
			FileAccess.open(directory+"/overview-layout-%d.json"%int(sample.unit_id),FileAccess.WRITE).store_string(JSON.stringify({"position":overview_text.global_position,"size":overview_text.size,"columns":overview_text.columns,"visible_paragraphs":overview_text.visible_paragraphs,"lines":overview_text.lines}))
		root.get_texture().get_image().save_png(directory+"/justice-main-sheet-%d.png"%tab)
		key(KEY_ESCAPE);await process_frame;await drain()
		check(inspector.panel.visible==bool(sample.after_escape_sheet_open),"Sheet Escape differs from native")
		check(owner.panel.visible==bool(sample.after_escape_info_open),"Justice return visibility differs from native")
		check(scene._ui.host.active==(owner if sample.after_escape_info_open else null),"Sheet Escape retained wrong input owner")
	exercised=true
