extends SceneTree

const Contract = preload("res://scripts/management_contract.gd")
var world
var directory: String

func _initialize() -> void:
	run.call_deferred()

func finish(success: bool, reason: String) -> void:
	var file := FileAccess.open(directory + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": success, "reason": reason}))
	print("CONNECTED_TRACK_PREVIEW_PASS" if success else "CONNECTED_TRACK_PREVIEW_FAIL: " + reason)
	if world:
		world.queue_free()
	await process_frame
	quit(0 if success else 1)

func position(value: Dictionary) -> Vector3i:
	return Vector3i(int(value.x), int(value.y), int(value.z))

func run() -> void:
	directory = OS.get_environment("DF3D_TRACK_PREVIEW_ACCEPTANCE")
	if directory.is_empty():
		quit(77)
		return
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(directory + "/preview-cases.json"))
	world = Df3dWorld.new()
	root.add_child(world)
	if not world.attach():
		await finish(false, "attach failed")
		return
	var deadline := Time.get_ticks_msec() + 30000
	var ready := false
	while Time.get_ticks_msec() < deadline:
		world.poll()
		if world.poll_management().get("transport_alive", false):
			ready = true
			break
		await create_timer(0.01).timeout
	if not ready:
		await finish(false, "management transport unavailable")
		return
	var catalog_seq: int = world.management_request("construction", {"action": 0})
	if catalog_seq <= 0:
		await finish(false, "catalog request refused: " + world.last_error())
		return
	deadline = Time.get_ticks_msec() + 30000
	ready = false
	while Time.get_ticks_msec() < deadline:
		world.poll()
		var catalog: Dictionary = world.poll_management()
		if int(catalog.get("request_seq", 0)) == catalog_seq and int(catalog.get("status", 0)) == Contract.ManagementStatus.Ok:
			ready = true
			break
		await create_timer(0.01).timeout
	if not ready:
		await finish(false, "catalog receipt missing; no replay")
		return
	var receipts: Array = []
	var mismatches: Array = []
	for row in cases:
		var seq: int = world.management_request("construction", {
			"action": 1, "definition": "Construction:Track", "origin": position(row.start),
			"connected_track_destination": position(row.destination)})
		if seq <= 0:
			await finish(false, "request refused: " + world.last_error())
			return
		deadline = Time.get_ticks_msec() + 30000
		var receipt: Dictionary = {}
		while Time.get_ticks_msec() < deadline:
			world.poll()
			var state: Dictionary = world.poll_management()
			if int(state.get("request_seq", 0)) == seq and int(state.get("status", 0)) not in [Contract.ManagementStatus.Idle, Contract.ManagementStatus.Pending]:
				receipt = state
				break
			await create_timer(0.01).timeout
		if receipt.is_empty() or int(receipt.status) != Contract.ManagementStatus.Ok:
			await finish(false, "missing or unsuccessful receipt; no replay: " + str(receipt))
			return
		var track: Dictionary = receipt.get("construction", {}).get("connected_track", {})
		var expected: Array = []
		for p in row.path:
			expected.append(position(p))
		if int(track.get("status", -1)) != int(row.get("status", 0)) or track.get("path", []) != expected:
			mismatches.append({"start": str(row.start), "destination": str(row.destination), "actual": str(track), "expected": str(expected), "expected_status": int(row.get("status", 0))})
		if row.has("required") and (not receipt.placement_valid or int(receipt.required) != int(row.required)):
			await finish(false, "native material requirement mismatch")
			return
		receipts.append({"seq": seq, "tiles": expected.size(), "required": receipt.required})
	var file := FileAccess.open(directory + "/receipts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(receipts))
	file.close()
	if not mismatches.is_empty():
		file = FileAccess.open(directory + "/mismatches.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(mismatches))
		file.close()
		await finish(false, "%d ordered native path mismatches" % mismatches.size())
		return
	await finish(true, "%d native paths matched" % receipts.size())
