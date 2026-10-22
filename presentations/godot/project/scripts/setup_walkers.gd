extends Node2D

# Decorative adult dwarves, composed from the selected installation's DEFAULT
# layer definitions. These are illustrations, not units from a running fortress.
const WalkAnimation = preload("res://scripts/actor_animation_catalog.gd")
const VARIANT_COUNT := 96
var textures: Array[Texture2D] = []
var walkers: Array[Dictionary] = []
var next_arrival := 0.5
var elapsed := 0.0

func load_art(installation: String) -> void:
	for walker in walkers: walker.sprite.queue_free()
	walkers.clear()
	textures.clear()
	var folder := installation.path_join("data/vanilla/vanilla_creatures_graphics/graphics")
	var definition := folder.path_join("graphics_creatures_dwarf.txt")
	if not FileAccess.file_exists(definition): return
	var raw := FileAccess.get_file_as_string(definition).get_slice("[LAYER_SET:DEFAULT]", 1)
	var layer_pattern := RegEx.create_from_string("\\[LAYER:([^:]+):([^:]+):(\\d+):(\\d+)\\]([^\\[]*(?:\\[(?!LAYER:)[^\\]]*\\][^\\[]*)*)")
	var palette_pattern := RegEx.create_from_string("\\[USE_PALETTE:([^:]+):(\\d+)\\]")
	var layers := {}
	for match in layer_pattern.search_all(raw):
		var palette := palette_pattern.search(match.get_string(5))
		var name := match.get_string(1)
		for sex in ["FEMALE", "MALE"]:
			if match.get_string(5).contains("[CONDITION_CASTE:" + sex + "]"): name += "_" + sex
		layers[name] = {"page": match.get_string(2), "cell": Vector2i(int(match.get_string(3)), int(match.get_string(4))), "palette": palette.get_string(1) if palette else "", "row": int(palette.get_string(2)) if palette else 0}
	var pages := {}
	var page_raw := FileAccess.get_file_as_string(folder.path_join("tile_page_creatures.txt"))
	var page_pattern := RegEx.create_from_string("\\[TILE_PAGE:(DWARF_[^\\]]+)\\]\\s*\\[FILE:([^\\]]+)\\]\\s*\\[TILE_DIM:(\\d+):(\\d+)\\]")
	for match in page_pattern.search_all(page_raw):
		if match.get_string(1) not in ["DWARF_BODY", "DWARF_HAIR", "DWARF_WEARABLES"]: continue
		pages[match.get_string(1)] = {"image": Image.load_from_file(folder.path_join(match.get_string(2))), "size": Vector2i(int(match.get_string(3)), int(match.get_string(4)))}
	var palettes := {}
	var palette_files := RegEx.create_from_string("\\[LS_PALETTE:([^\\]]+)\\]\\s*\\[LS_PALETTE_FILE:([^\\]]+)\\]")
	for match in palette_files.search_all(raw):
		palettes[match.get_string(1)] = Image.load_from_file(folder.path_join(match.get_string(2)))
	for variant in VARIANT_COUNT:
		var names := appearance(variant)
		var result := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var valid := true
		for name in names:
			var sex := "FEMALE" if variant >= 48 else "MALE"
			if layers.has(name + "_" + sex): name += "_" + sex
			if not layers.has(name) or not pages.has(layers[name].page):
				valid = false
				break
			var layer: Dictionary = layers[name]
			var sheet: Dictionary = pages[layer.page]
			if sheet.image == null or sheet.size != Vector2i(32, 32):
				valid = false
				break
			var tile: Image = sheet.image.get_region(Rect2i(layer.cell * sheet.size, sheet.size))
			if palettes.has(layer.palette):
				var palette: Image = palettes[layer.palette]
				if palette == null or layer.row >= palette.get_height():
					valid = false
					break
				var colors := {}
				for x in palette.get_width(): colors[palette.get_pixel(x, 0).to_rgba32()] = palette.get_pixel(x, layer.row)
				for y in 32:
					for x in 32:
						var color := tile.get_pixel(x, y)
						var key := Color(color.r, color.g, color.b, 1).to_rgba32()
						if color.a > 0 and colors.has(key):
							var replacement: Color = colors[key]
							replacement.a = color.a
							tile.set_pixel(x, y, replacement)
			result.blend_rect(tile, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		if valid: textures.append(ImageTexture.create_from_image(result))
	next_arrival = 0.5

func appearance(variant: int) -> Array:
	var female := variant >= 48
	variant %= 48
	var outfit := variant % 8
	var hair: String = ["BLACK", "RED", "BLOND", "LBROWN", "DBROWN", "WHITE"][variant / 8]
	var skin: String = ["LIGHT", "LMID", "DMID", "DARK"][(variant / 3) % 4]
	var cloth: String = ["LBLUE", "LGREEN", "LRED", "BROWN", "YELLOW", "WHITE"][(variant / 2) % 6]
	var hair_style: String = ["SHORT_COMBED", "MID_UNKEMPT", "LONG_BRAIDED", "MID_DOUBLE_BRAIDS"][variant % 4]
	var beard: String = ["BEARD_SHORT_COMBED", "BEARD_MID_UNKEMPT", "BEARD_LONG_BRAIDED", "BEARD_MID_DOUBLE_BRAIDS"][(variant / 4) % 4]
	var sleeve := "_PLATE_STANDARD" if outfit == 7 else "_MAIL_STANDARD" if outfit == 6 else "_" + cloth
	var legs := "_GREAVES_STANDARD" if outfit == 7 else "_LEGGINGS_STANDARD" if outfit == 6 else "_" + cloth
	var boots := "_HIGH_STANDARD" if outfit >= 5 else "_" + cloth
	var torso: String = ["SIMPLE_" + cloth, "VEST_" + cloth, "SIMPLE_" + cloth, "SIMPLE_" + cloth, "VEST_" + cloth, "LEATHER_STANDARD", "MAIL_STANDARD", "PLATE_STANDARD"][outfit]
	var waist := "ROBE_" if outfit == 3 else "TUNIC_"
	var names: Array = []
	if outfit in [2, 3, 5]: names.append("CLOTHING_CAPE_" + cloth)
	names.append_array([skin + "_RIGHT_SHOULDER", "CLOTHING_RA" + sleeve, skin + "_RIGHT_HAND", skin + "_RIGHT_LEG", "CLOTHING_RL" + legs, skin + "_RIGHT_FOOT", "CLOTHING_RF" + boots, skin + "_LEFT_LEG", "CLOTHING_LL" + legs, skin + "_LEFT_FOOT", "CLOTHING_LF" + boots, "CLOTHING_WAIST_" + waist + cloth, skin + "_BODY", "CLOTHING_TORSO_" + torso, skin + "_LEFT_SHOULDER", "CLOTHING_LA" + sleeve, skin + "_FACE_M%d" % (variant % 4 + 1), hair_style + "_" + hair])
	if outfit == 1: names.append("CLOTHING_CAP_" + cloth)
	elif outfit == 3: names.append("CLOTHING_HOOD_" + cloth)
	elif outfit == 4: names.append("CLOTHING_TURBAN_" + cloth)
	elif outfit >= 6: names.append("CLOTHING_CAP_METAL")
	if female:
		for index in names.size(): names[index] = names[index].replace("_FACE_M", "_FACE_F")
	else: names.append(beard + "_" + hair)
	names.append(skin + "_LEFT_HAND")
	return names

func _process(delta: float) -> void:
	if not visible or textures.is_empty(): return
	elapsed += delta
	next_arrival -= delta
	if next_arrival <= 0 and walkers.size() < 3:
		var sprite := Sprite2D.new()
		sprite.texture = textures.pick_random()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.offset = Vector2(0, -16)
		add_child(sprite)
		var direction := -1 if randf() < 0.5 else 1
		walkers.append({"sprite": sprite, "x": -40.0 if direction > 0 else get_viewport_rect().size.x + 40, "speed": randf_range(35, 52) * direction, "seed": randf()})
		next_arrival = randf_range(6, 12)
	for index in range(walkers.size() - 1, -1, -1):
		var walker := walkers[index]
		walker.x += walker.speed * delta
		var pose := WalkAnimation.pose("walk", elapsed, walker.seed)
		walker.sprite.position = Vector2(walker.x, get_viewport_rect().size.y - 14 - pose.offset.y * 64)
		walker.sprite.rotation = -pose.rotation
		# Native adult dwarf artwork faces left; mirror the whole composition
		# for rightward travel, including its clothing and beard.
		walker.sprite.flip_h = walker.speed > 0
		walker.sprite.scale = pose.scale * 2
		if walker.x < -80 or walker.x > get_viewport_rect().size.x + 80:
			walker.sprite.queue_free()
			walkers.remove_at(index)
