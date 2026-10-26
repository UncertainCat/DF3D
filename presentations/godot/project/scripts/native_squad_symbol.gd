extends RefCounted
# Native40ac50's mask composition, using installed assets and saved RGB only.
var world
var cache: Dictionary = {}

func configure(source) -> void:
	world = source
	cache.clear()

func texture(facts: Dictionary) -> Texture2D:
	if world == null or not world.has_method("ui_texture"): return null
	if not facts.get("index") is int or facts.index < 0 or facts.index > 22: return null
	for key in ["foreground","background"]:
		if not facts.get(key) is Array or facts[key].size() != 3: return null
		for value in facts[key]:
			if not value is int or value < 0 or value > 255: return null
	var mask: Texture2D = world.ui_texture("CUSTOM_SYMBOL",facts.index)
	if mask == null or mask.get_size() != Vector2(32,32): return null
	var key := str([mask.get_rid().get_id(),facts.index,facts.foreground,facts.background])
	if cache.has(key): return cache[key]
	var source := mask.get_image()
	var pixels := PackedByteArray(); pixels.resize(32*32*4)
	for y in 32:
		for x in 32:
			var rgb: Array = facts.foreground if source.get_pixel(x,y).a > 0.0 else facts.background
			var offset := (y*32+x)*4
			for component in 3: pixels[offset+component] = rgb[component]
			pixels[offset+3] = 255
	var result := ImageTexture.create_from_image(Image.create_from_data(32,32,false,Image.FORMAT_RGBA8,pixels))
	if cache.size() >= 128: cache.erase(cache.keys()[0])
	cache[key] = result
	return result
