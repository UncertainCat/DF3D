extends SceneTree
var world
var child := 0
var status_path := ""

func finish(code: int, message: String) -> void:
	if not status_path.is_empty(): DirAccess.remove_absolute(status_path)
	if world != null: world.free()
	for i in 300:
		if child <= 0 or not OS.is_process_running(child): break
		await create_timer(0.01).timeout
	if child > 0 and OS.is_process_running(child):
		OS.kill(child)
		push_error("Session producer did not exit after status removal")
		code = 1
	print(message)
	quit(code)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var executable := ProjectSettings.globalize_path("res://../../../build/tools/management_contract_host.exe")
	if not FileAccess.file_exists(executable):
		await finish(77, "QA_INCOMPLETE: build management_contract_host first")
		return
	status_path = OS.get_user_data_dir().path_join("session-notifications-%d.txt" % OS.get_process_id())
	DirAccess.remove_absolute(status_path)
	child = OS.create_process(executable, ["--session-notifications", status_path], false)
	for i in 300:
		if FileAccess.file_exists(status_path) and not FileAccess.get_file_as_string(status_path).is_empty(): break
		await create_timer(0.01).timeout
	var ready := FileAccess.get_file_as_string(status_path) if FileAccess.file_exists(status_path) else "failed"
	if ready == "unsupported":
		await finish(77, "QA_INCOMPLETE: Windows shared memory required")
		return
	if ready != "ready":
		await finish(77 if ready == "incomplete" else 1, "QA_INCOMPLETE: session channel occupied" if ready == "incomplete" else "SESSION_HOST_START_FAILED")
		return
	world = ClassDB.instantiate("Df3dWorld")
	var state: Dictionary = world.poll_session()
	assert(state.fortress_valid and state.fortress_epoch is int and state.fortress_epoch == 9007199254740993)
	assert(state.active_notifications_complete)
	var groups: Array = state.active_notifications
	assert(groups.size() == 3)
	assert(groups[0] == {"category":20,"category_name":"JobFailed","report_ids":[0,41],"report_count":2,"unit_reports":[],"unit_report_count":0,"complete":true})
	assert(groups[1] == {"category":34,"category_name":"Combat","report_ids":[],"report_count":0,"unit_reports":[{"unit_id":17,"category":0},{"unit_id":18,"category":1}],"unit_report_count":2,"complete":true})
	var weather: Dictionary = groups[2]
	assert(weather.category == 24 and weather.category_name == "Weather")
	assert(weather.report_count == 300 and weather.report_ids.size() == 256 and not weather.complete)
	assert(weather.unit_reports.is_empty() and weather.unit_report_count == 0)
	for id in 256: assert(weather.report_ids[id] == id)
	await finish(0, "SESSION_NOTIFICATIONS_CONTRACT_TEST_PASS")
