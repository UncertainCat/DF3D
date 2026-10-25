extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value: failures+=1;push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json"))
	var facts: Dictionary={}
	for item in fixture.picker_icon_capture.semantic_items: facts[int(item.id)]=item
	# No bridge connection or terrain stream exists: icons depend only on owned
	# semantic candidate facts and verified installed assets.
	for row in fixture.picker_icon_capture.comparisons:
		var item: Dictionary=facts[int(row.id)]
		var appearance := {"material_token":item.material,"subtype_raw":"","color_token":item.color_token,
			"stack":int(item.stack),"flags":32 if item.artifact else 0}
		var icon: Texture2D=world.construction_item_icon(int(item.item_type),appearance)
		check(icon!=null,"captured item icon unavailable")
		if icon==null:continue
		var pixels:=icon.get_image();pixels.convert(Image.FORMAT_RGBA8)
		pixels.clear_mipmaps()
		check(pixels.get_size()==Vector2i(32,32),"native picker dimensions")
		var bytes:=pixels.get_data()
		for i in range(0,bytes.size(),4):
			if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		check(hash.finish().hex_encode()==row.canonical_rgba_sha256,"native visible pixels differ for "+str(row.id))
		var valid:=appearance.duplicate(true)
		for mutation in [{"stack":0},{"stack":1.5},{"flags":1},{"material_token":""},{"color_token":"UNKNOWN_FIXTURE_COLOR"},{"subtype_raw":123}]:
			var invalid:=valid.duplicate(true);invalid.merge(mutation,true)
			check(world.construction_item_icon(int(item.item_type),invalid)==null,"malformed appearance must not invent an icon")
	var bed := {"material_token":"INORGANIC:GRANITE","subtype_raw":"","color_token":"","stack":1,"flags":0,
		"bedding":{"sheet":0,"pillow":1,"base_color":"CLEAR","sheet_color":"CHARTREUSE"}}
	check(world.construction_item_icon(8,bed)!=null,"owned bedding facts must not hide bed icons")
	var bedding_fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bed_bedding.json"))
	for row in bedding_fixture.renderer.comparisons:
		var source:=bed.duplicate(true)
		source.bedding=row.bedding.duplicate(true)
		source.bedding.sheet=int(source.bedding.sheet);source.bedding.pillow=int(source.bedding.pillow)
		var texture:Texture2D=world.construction_item_icon(8,source)
		check(texture!=null,"native bedding icon available")
		if texture==null:continue
		var pixels:=texture.get_image();pixels.convert(Image.FORMAT_RGBA8)
		var opaque:=PackedByteArray()
		for y in range(32):
			for x in range(32):
				var pixel:=pixels.get_pixel(x,y)
				if pixel.a8==255:opaque.append_array(PackedByteArray([x,y,pixel.r8,pixel.g8,pixel.b8]))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(opaque)
		check(opaque.size()==int(row.opaque_pixels)*5,"native bedding opaque coverage")
		check(hash.finish().hex_encode()==row.native_opaque_sha256,"native bedding opaque pixels")
	check(world.construction_item_icon(0,bed)==null,"bedding is bed-only")
	for mutation in [{"sheet":2},{"pillow":3},{"sheet":0.5},{"base_color":123},{"sheet_color":"x".repeat(129)},{"extra":0}]:
		var invalid:=bed.duplicate(true);invalid.bedding.merge(mutation,true)
		check(world.construction_item_icon(8,invalid)==null,"malformed bedding rejected")
	var instrument_fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/instrument_rendering.json"))
	for row in instrument_fixture.native_material_picker.icon_regression:
		var source={"material_token":row.material,"subtype_raw":"FIXTURE_INSTRUMENT","color_token":"","stack":1,"flags":0,
			"instrument":{"family":int(row.family),"placed":int(row.placed)}}
		var icon:Texture2D=world.construction_item_icon(13,source)
		check(icon!=null,"native instrument candidate icon available")
		if icon==null:continue
		var pixels=icon.get_image();pixels.convert(Image.FORMAT_RGBA8);pixels.clear_mipmaps()
		var bytes=pixels.get_data()
		for i in range(0,bytes.size(),4):
			if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
		var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
		check(digest.finish().hex_encode()==row.canonical_rgba_sha256,"native Instrument picker artwork")
		check(world.construction_item_icon(8,source)==null,"instrument facts are instrument-only")
		for mutation in [{"family":-1},{"family":4},{"placed":-1},{"placed":2},{"family":0.5},{"placed":true},{"extra":0}]:
			var invalid=source.duplicate(true);invalid.instrument.merge(mutation,true)
			check(world.construction_item_icon(13,invalid)==null,"invalid instrument facts rejected")
	var slab_fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/slab_rendering.json"))
	for row in slab_fixture.native_material_picker.icon_regression:
		var source={"material_token":"INORGANIC:GRANITE","subtype_raw":"","color_token":"","stack":1,"flags":0,"slab_engraving":int(row.engraving)}
		var icon:Texture2D=world.construction_item_icon(87,source,row.group)
		check(icon!=null,"native slab icon available")
		if icon==null:continue
		var pixels=icon.get_image();pixels.convert(Image.FORMAT_RGBA8);pixels.clear_mipmaps();var bytes=pixels.get_data()
		for i in range(0,bytes.size(),4):
			if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
		var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
		check(digest.finish().hex_encode()==row.canonical_rgba_sha256,"native slab picker artwork")
		check(world.construction_item_icon(8,source)==null,"slab facts are slab-only")
		for invalid_value in [-2,27,0.5,true]:
			var invalid=source.duplicate(true);invalid.slab_engraving=invalid_value
			check(world.construction_item_icon(87,invalid)==null,"invalid slab facts rejected")
	var gems:Dictionary=fixture.cut_gem_native_reference
	for shape in gems.shape_comparisons:
		for row in shape.variants:
			var source={"material_token":"INORGANIC:FIXTURE_UNCOLORED","subtype_raw":"","color_token":"","stack":1,"flags":0,"gem_shape_raw":shape.shape}
			var icon:Texture2D=world.construction_item_icon(1,source,false,int(gems.variant_test_ids[int(row.variant)]))
			check(icon_hash(icon)==row.rgba_sha256,"native cut-gem composite "+shape.shape+"/"+str(row.variant))
	for row in gems.picker_comparisons:
		var source={"material_token":"INORGANIC:RUBY","subtype_raw":"","color_token":"SCARLET","stack":1,"flags":0}
		if int(row.id)>=0:source.gem_shape_raw=row.shape
		var icon:Texture2D=world.construction_item_icon(1,source,int(row.id)<0,int(row.id))
		check(icon_hash(icon)==row.rgba_sha256,"native ruby picker icon")
		source.color_token=""
		check(icon_hash(world.construction_item_icon(1,source,int(row.id)<0,int(row.id)))==row.rgba_sha256,"native material color when item has no color override")
		if int(row.id)>=0:
			source.stack=10
			check(icon_hash(world.construction_item_icon(1,source,false,int(row.id)))==row.rgba_sha256,"gem arrangement independent of stack")
			check(world.construction_item_icon(8,source)==null,"gem shape is cut-gem-only")
	check(world.construction_item_icon(-1,{})==null,"unknown item kind")
	world.free();await process_frame
	print("CONSTRUCTION_ITEM_ICON ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)

func icon_hash(icon:Texture2D)->String:
	if icon==null:return ""
	var pixels=icon.get_image();pixels.convert(Image.FORMAT_RGBA8);pixels.clear_mipmaps();var bytes=pixels.get_data()
	for i in range(0,bytes.size(),4):
		if bytes[i+3]==0:bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0
	var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
	return digest.finish().hex_encode()
