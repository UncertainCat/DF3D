extends RefCounted
# Capture-only: encode unique immutable CPU images after the simulation pauses.
# A bounded worker set avoids serial PNG compression without touching rendering.
static func _write_lane(images: Array[Image], directory: String, lane: int, lanes: int) -> String:
	for i in range(lane, images.size(), lanes):
		var error := images[i].save_png(directory.path_join("%04d.png" % i))
		if error != OK: return "Cannot write capture frame %d: %s" % [i,error_string(error)]
	return ""

static func write(images: Array[Image], directory: String) -> String:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return "Cannot create capture directory: " + error_string(error)
	var count := mini(4, images.size())
	var workers: Array[Thread] = []
	var failure := ""
	for lane in count:
		var worker := Thread.new()
		error = worker.start(_write_lane.bind(images,directory,lane,count))
		if error == OK: workers.append(worker)
		else:
			failure = "Cannot start capture encoder: " + error_string(error)
			break
	for worker in workers:
		var result: String = worker.wait_to_finish()
		if not result.is_empty(): failure = result
	return failure
