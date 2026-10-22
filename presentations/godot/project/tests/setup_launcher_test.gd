extends "res://scripts/setup_launcher.gd"

# Driven only by the isolated C# integration runner; all mutations target its game copy.
func start() -> void:
	print("SETUP_TEST_START ", channel)
	await super.start()
	if OS.get_environment("DF3D_SETUP_REOPEN") == "1":
		require(page == "test_launched" and accepted and installed)
	else:
		require(page == "choose" and next_button.disabled)
		require(inspections.has(OS.get_environment("DF3D_SETUP_GAME")))
		await capture("choose")
		await target(OS.get_environment("DF3D_SETUP_GAME").path_join("missing"))
		require(next_button.disabled)
		await target(OS.get_environment("DF3D_SETUP_GAME"))
		require(not next_button.disabled and not accepted and not installed)
		require(notice.text.is_empty())
		await proceed()
		require(page == "acknowledge" and next_button.disabled)
		require(walkers.textures.size() == walkers.VARIANT_COUNT)
		await capture("acknowledge")
		acknowledgment.button_pressed = true
		await accept_notice()
		require(page == "ready" and accepted)
		await install()
		require(page == "done" and installed)
		choose()
		await target(OS.get_environment("DF3D_SETUP_GAME"))
		require(installed and accepted and not next_button.disabled)
		await proceed()
		require(page == "test_launched")
	if failed:
		quit(1)
		return
	print("SETUP_LAUNCHER_PASS")
	var report := FileAccess.open(OS.get_environment("DF3D_SETUP_REPORT"), FileAccess.WRITE)
	report.store_string("PASS")
	report.close()
	quit()

func launch() -> void:
	page = "test_launched"

var failed := false

func require(value: bool) -> void:
	if not value:
		failed = true
		push_error("Setup UI check failed")

func capture(label: String) -> void:
	for i in 4: await get_tree().process_frame
	require(card.size.x <= root.size.x and card.size.y <= root.size.y)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("DF3D_SETUP_REPORT").get_base_dir().path_join(label + ".png"))
