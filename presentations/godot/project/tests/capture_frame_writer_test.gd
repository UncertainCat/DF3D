extends SceneTree
func _initialize():
	var images: Array[Image] = []
	for i in 9:
		var frame := Image.create(8,8,false,Image.FORMAT_RGBA8)
		frame.fill(Color(float(i)/8,0.25,0.5))
		images.append(frame)
	var directory := ProjectSettings.globalize_path("user://capture-writer-test")
	var error: String = preload("res://tests/capture_frame_writer.gd").write(images,directory)
	var ok := error.is_empty()
	for i in images.size():
		var path: String = directory.path_join("%04d.png" % i)
		var loaded := Image.load_from_file(path)
		ok = ok and loaded != null and loaded.get_data() == images[i].get_data()
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("CAPTURE_FRAME_WRITER_PASS" if ok else "CAPTURE_FRAME_WRITER_FAIL: " + error)
	quit(0 if ok else 1)
