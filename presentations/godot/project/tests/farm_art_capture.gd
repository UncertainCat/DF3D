extends SceneTree
# Installed art only; native fixture retains hashes, never extracted sprites.
func _initialize() -> void:call_deferred("run")
func fail(message: String) -> void:
	push_error(message);quit(1)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(480,300)
	var world:=Df3dWorld.new();root.add_child(world)
	var install:=OS.get_environment("DF3D_DF_PATH")
	if not world.load_assets(install):fail("Farm artwork assets unavailable");return
	if world.farm_crop_icon("")!=null or world.farm_crop_icon("A".repeat(129))!=null:
		fail("Invalid farm raw identity accepted");return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var source:=Image.load_from_file(install.path_join("data/vanilla/vanilla_plants_graphics/graphics/images/plant_standard.png"))
	var background:=Color8(73,56,74)
	var canvas:=Control.new();root.add_child(canvas)
	var icons: Array=[]
	for i in fixture.artwork_reference.crops.size():
		var row: Dictionary=fixture.artwork_reference.crops[i]
		var icon: Texture2D=world.farm_crop_icon(row.raw_id)
		if icon==null or icon.get_size()!=Vector2(32,32):fail("Missing native crop icon "+row.raw_id);return
		icons.append(icon)
		var base:=ColorRect.new();canvas.add_child(base);base.color=background
		base.position=Vector2(16+i*64,16);base.size=Vector2(32,32)
		var picture:=TextureRect.new();base.add_child(picture);picture.texture=icon
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.size=Vector2(32,32)
	await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	var compared:=0
	for i in icons.size():
		var row: Dictionary=fixture.artwork_reference.crops[i]
		var reference: Dictionary=fixture.artwork_pixel_reference.crops[i]
		var texture: Image=icons[i].get_image()
		var opaque:=PackedByteArray()
		for y in 32:
			for x in 32:
				var original:=source.get_pixel(int(row.source.x)*32+x,int(row.source.y)*32+y)
				var actual:=texture.get_pixel(x,y)
				if absf(original.a-actual.a)>0.001 or (original.a>0 and original!=actual):
					fail("Farm icon changed installed color/alpha "+row.raw_id);return
				var pixel:=rendered.get_pixel(16+i*64+x,16+y)
				var expected:=background.lerp(original,original.a)
				for component in 3:
					if absf(pixel[component]-expected[component])>1.01/255.0:
						fail("Farm icon composition differs "+row.raw_id);return
				if original.a==1:
					for component in 3:opaque.append(roundi(pixel[component]*255))
				compared+=1
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(opaque)
		if opaque.size()!=int(reference.opaque_pixel_count)*3 or hash.finish().hex_encode()!=reference.opaque_rgb_sha256:
			fail("Farm icon differs from native opaque pixels "+row.raw_id);return
	if world.ui_texture("FARMPLOT")==null or world.ui_texture("BUILDING_ICON_FARM_PLOT")==null:
		fail("Missing farm fallow/header artwork");return
	if rendered.save_png(ProjectSettings.globalize_path("res://../../../build/farm-art-icons.png"))!=OK:
		fail("Could not retain farm artwork capture");return
	canvas.queue_free();world.queue_free();icons.clear();await process_frame
	print("FARM_ART_CAPTURE_PASS pixels=",compared);quit(0)
