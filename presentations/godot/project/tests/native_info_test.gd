extends "res://tests/ui_test_support.gd"
func run():
	preload("res://scripts/presentation_settings.gd").loaded = true
	preload("res://scripts/presentation_settings.gd").ui_scale = 1.0
	var assets:=Df3dWorld.new();root.add_child(assets)
	check(assets.load_assets(OS.get_environment("DF3D_DF_PATH")),"Original Info assets load")
	var world:=AssetWorld.new();world.assets=assets
	var interaction:=FakeInteraction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var view=preload("res://scripts/read_only_info.gd").new();view.world=world;view.interaction=interaction;root.add_child(view);host.register(view);view.set_process(false)
	for size in [Vector2i(960,640),Vector2i(1920,1080)]:
		root.size=size
		for page in ["Residents","Work Details","Work orders"]:
			view.set_info_page(page);view.open_panel();view._process(0)
			await process_frame;await process_frame
			view._process(0)
			var frame=view.info_frame
			var expected:Rect2 = Rect2(32,72,704,532) if size.x==960 else Rect2(32,72,1664,972)
			if page!="Residents": expected=preload("res://scripts/fortress_hud.gd").info_rect(Vector2(size))
			check(view.panel.get_rect()==expected,"Accepted Info page uses retained bounded frame: "+page)
			var border:StyleBoxTexture=view.panel.get_theme_stylebox("panel")
			check(border.texture.get_image().get_data()==assets.ui_texture("HOVER_RECTANGLE").get_image().get_data(),"Native border retains installed pixels")
			check(frame.main_tabs.get_child_count()==8,"Native main-tab count")
			check(frame.subtabs.visible==(page!="Work orders"),"Native submenu hierarchy")
			check(not frame.buttons["Tasks"].visible and not frame.buttons["Places"].visible,"Unavailable destinations hidden")
			var selected:Button=frame.buttons["Creatures" if page=="Residents" else ("Labor" if page=="Work Details" else page)]
			var style:StyleBoxTexture=selected.get_theme_stylebox("normal")
			check(style.texture.get_image().get_data()==assets.ui_texture("SHORT_TAB_SELECTED").get_image().get_data(),"Selected main tab retains installed pixels")
			view.close_panel()
	view.free();host.free();interaction.free();assets.free()
	print("NATIVE_INFO_PASS" if failures==0 else "NATIVE_INFO_FAIL")
	quit(failures)
