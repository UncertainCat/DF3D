extends RefCounted
# Runtime-only original DF widgets. Raw selectors/layouts are owned by the
# shared asset index; this layer deals only with Godot control styling.
var world
var theme := Theme.new()
var textures: Dictionary = {}
# Warnings are per-process: every panel instantiates its own theme.
static var _warned_assets_unavailable := false
static var _warned_border_missing := false
# DFHack's DF2UTF mapping for graphical CP437 bytes 1..31 (quality/sex/arrows).
const CP437_SYMBOLS = [0x263A,0x263B,0x2665,0x2666,0x2663,0x2660,0x2022,0x25D8,0x25CB,0x25D9,0x2642,0x2640,0x266A,0x266B,0x263C,0x25BA,0x25C4,0x2195,0x203C,0xB6,0xA7,0x25AC,0x21A8,0x2191,0x2193,0x2192,0x2190,0x221F,0x2194,0x25B2,0x25BC]
# Unicode codepoints of CP437 bytes 128..255 (Python's standard cp437 table).
const CP437_HIGH = [199,252,233,226,228,224,229,231,234,235,232,239,238,236,196,197,201,230,198,244,246,242,251,249,255,214,220,162,163,165,8359,402,225,237,243,250,241,209,170,186,191,8976,172,189,188,161,171,187,9617,9618,9619,9474,9508,9569,9570,9558,9557,9571,9553,9559,9565,9564,9563,9488,9492,9524,9516,9500,9472,9532,9566,9567,9562,9556,9577,9574,9568,9552,9580,9575,9576,9572,9573,9561,9560,9554,9555,9579,9578,9496,9484,9608,9604,9612,9616,9600,945,223,915,960,931,963,181,964,934,920,937,948,8734,966,949,8745,8801,177,8805,8804,8992,8993,247,8776,176,8729,183,8730,8319,178,9632,160]
const TOOL_ART = {
	"Dig": "BUTTON_DIG_DIG_INACTIVE", "Channel": "BUTTON_DIG_CHANNEL_INACTIVE",
	"Ramp": "BUTTON_DIG_RAMP_INACTIVE", "Stairs up": "BUTTON_DIG_STAIRS_INACTIVE",
	"Stairs down": "BUTTON_DIG_STAIRS_INACTIVE", "Stairs up/down": "BUTTON_DIG_STAIRS_INACTIVE",
	"Chop trees": "BUTTON_DES_CHOP_INACTIVE", "Clear chop": "BUTTON_DES_ERASE",
	"Gather plants": "BUTTON_DES_GATHER_INACTIVE", "Clear gather": "BUTTON_DES_ERASE",
	"Smooth": "BUTTON_DES_SMOOTH_SMOOTH_INACTIVE", "Engrave": "BUTTON_DES_SMOOTH_ENGRAVE_INACTIVE",
	"Remove": "BUTTON_DES_ERASE", "Inspect buildings": "BUTTON_BUILDING_INACTIVE"
}
const BUTTON_ART = {"Pause": "BUTTON_PAUSE_ACTIVE", "Resume": "BUTTON_PLAY_ACTIVE", "Forbid": "SHORT_FORBID_ACTIVE", "Reclaim": "SHORT_FORBID", "Dump": "SHORT_DUMP_ACTIVE", "Cancel dump": "SHORT_DUMP", "Melt": "SHORT_MELT_ACTIVE", "Cancel melt": "SHORT_MELT", "Forbid passage": "SHORT_FORBID_ACTIVE", "Allow passage": "SHORT_FORBID"}

func texture(name: String) -> Texture2D:
	if world == null or not world.has_method("ui_texture"): return null
	if not textures.has(name): textures[name] = world.ui_texture(name)
	return textures[name]

func make_style(name: String, edge := 5.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture(name)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, edge)
		style.set_content_margin(side, edge + 3.0)
	return style

func configure(source) -> void:
	world = source
	theme.default_font_size = 16
	if world == null or not world.has_method("ui_texture") or not world.has_method("ui_font_path"):
		if not _warned_assets_unavailable:
			_warned_assets_unavailable = true
			push_warning("Original DF interface assets unavailable; keeping readable default controls")
		return
	var font := bitmap_font(world.ui_font_path())
	if font != null: theme.default_font = font
	var normal := make_style("BUTTON_RECTANGLE")
	var selected := make_style("BUTTON_RECTANGLE_SELECTED")
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, selected)
		theme.set_stylebox("pressed", type, selected)
		var disabled := normal.duplicate() as StyleBoxTexture
		disabled.modulate_color = Color(0.5, 0.5, 0.5)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_constant("h_separation", type, 6)
	var panel_style := native_panel()
	for type in ["PanelContainer", "PopupPanel", "PopupMenu"]: theme.set_stylebox("panel", type, panel_style)
	for type in ["Label", "Button", "OptionButton", "LineEdit", "PopupMenu"]:
		theme.set_color("font_color", type, Color(0.92, 0.89, 0.79))
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", selected)
	# Native inventories have a plain inset. Stretching a tiny button across
	# the whole list produces large wood grain behind every row.
	var list_background := StyleBoxFlat.new()
	list_background.bg_color = Color(0.04, 0.04, 0.04, 1)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		list_background.set_content_margin(side, 4)
	theme.set_stylebox("panel", "ItemList", list_background)
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)

func native_panel() -> StyleBox:
	# Corners are two-dimensional layouts; straight borders are one-dimensional
	# original named variants, in the pinned raw's ascending strip order.
	var required := [texture("BORDER_TOP_LEFT"),texture("BORDER_TOP_RIGHT"),texture("BORDER_BOTTOM_LEFT"),texture("BORDER_BOTTOM_RIGHT")]
	for name in ["BORDER_TOP","BORDER_BOTTOM","BORDER_LEFT","BORDER_RIGHT"]:
		for i in (3 if name in ["BORDER_TOP","BORDER_BOTTOM"] else 4):
			required.append(world.ui_texture(name,i))
	for part in required:
		if part == null:
			if not _warned_border_missing:
				_warned_border_missing = true
				push_warning("Original DF border art missing; using readable fallback panel")
			var fallback := StyleBoxFlat.new()
			fallback.bg_color = Color(0.04,0.04,0.04,1)
			for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: fallback.set_content_margin(side,10)
			return fallback
	var tl := texture("BORDER_TOP_LEFT").get_image()
	var tr := texture("BORDER_TOP_RIGHT").get_image()
	var bl := texture("BORDER_BOTTOM_LEFT").get_image()
	var br := texture("BORDER_BOTTOM_RIGHT").get_image()
	var w := tl.get_width()
	var h := tl.get_height()
	var image := Image.create(w * 2 + 8, h * 2 + 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04,0.04,0.04,1))
	image.blit_rect(tl, Rect2i(0,0,w,h), Vector2i.ZERO)
	image.blit_rect(tr, Rect2i(0,0,w,h), Vector2i(w+8,0))
	image.blit_rect(bl, Rect2i(0,0,w,h), Vector2i(0,h+12))
	image.blit_rect(br, Rect2i(0,0,w,h), Vector2i(w+8,h+12))
	for i in 3:
		image.blit_rect(world.ui_texture("BORDER_TOP",i).get_image(),Rect2i(0,0,8,12),Vector2i(w,i*12))
		image.blit_rect(world.ui_texture("BORDER_BOTTOM",i).get_image(),Rect2i(0,0,8,12),Vector2i(w,h+12+i*12))
	for i in 4:
		image.blit_rect(world.ui_texture("BORDER_LEFT",i).get_image(),Rect2i(0,0,8,12),Vector2i(i*8,h))
		image.blit_rect(world.ui_texture("BORDER_RIGHT",i).get_image(),Rect2i(0,0,8,12),Vector2i(w+8+i*8,h))
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.set_texture_margin(SIDE_LEFT,w)
	style.set_texture_margin(SIDE_RIGHT,w)
	style.set_texture_margin(SIDE_TOP,h)
	style.set_texture_margin(SIDE_BOTTOM,h)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(side,w)
	for side in [SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,h)
	return style

func apply(root: Node) -> void:
	if root is Control:
		root.theme = theme
		root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if root is PanelContainer:
		root.remove_theme_stylebox_override("panel")
	if root is Button and BUTTON_ART.has(root.text):
		root.icon = texture(BUTTON_ART[root.text])
		root.add_theme_constant_override("icon_max_width", 24)
		root.tooltip_text = root.text if root.tooltip_text.is_empty() else root.tooltip_text
	if root is OptionButton and root.name == "ToolPicker":
		for i in root.item_count:
			var label: String = root.get_item_text(i)
			if TOOL_ART.has(label): root.set_item_icon(i, texture(TOOL_ART[label]))
	for child in root.get_children(): apply(child)

# A shallow HUD frame uses only the installed straight border strips. The
# ornate 32x36 corners belong to large dialogs and cannot fit a thin status bar.
func compact_panel() -> StyleBox:
	var large = native_panel()
	if not large is StyleBoxTexture: return large
	var source = large.texture.get_image()
	var horizontal = source.get_region(Rect2i(32, 0, 8, 36))
	var vertical = source.get_region(Rect2i(0, 36, 32, 12))
	var ys: Array[int] = []
	var xs: Array[int] = []
	for y in horizontal.get_height():
		var pixel = horizontal.get_pixel(4, y)
		if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.2: ys.append(y)
	for x in vertical.get_width():
		var pixel = vertical.get_pixel(x, 6)
		if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.2: xs.append(x)
	if ys.is_empty() or xs.is_empty(): return make_style("BUTTON_RECTANGLE")
	var h = ys.back() - ys.front() + 1
	var w = xs.back() - xs.front() + 1
	var output = Image.create(w * 2 + 8, h * 2 + 12, false, Image.FORMAT_RGBA8)
	output.fill(Color(0.04, 0.04, 0.04, 1))
	for x in output.get_width():
		for y in h:
			output.set_pixel(x, y, horizontal.get_pixel(x % 8, ys.front() + y))
			output.set_pixel(x, output.get_height() - 1 - y, horizontal.get_pixel(x % 8, ys.front() + y))
	for y in output.get_height():
		for x in w:
			output.set_pixel(x, y, vertical.get_pixel(xs.front() + x, y % 12))
			output.set_pixel(output.get_width() - 1 - x, y, vertical.get_pixel(xs.front() + x, y % 12))
	var style = StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(output)
	for side in [SIDE_LEFT, SIDE_RIGHT]: style.set_texture_margin(side, w)
	for side in [SIDE_TOP, SIDE_BOTTOM]: style.set_texture_margin(side, h)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 8)
	return style

static func bitmap_font(path: String) -> FontFile:
	if path.is_empty() or not FileAccess.file_exists(path): return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	var cell := Vector2i(image.get_width() / 16, image.get_height() / 16)
	if cell.x < 1 or cell.y < 1: return null
	# DF's bitmap alphabet is 16x16 CP437, including accented fortress names.
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var keyed := pixel.r > 0.99 and pixel.b > 0.99 and pixel.g < 0.01
			image.set_pixel(x, y, Color(1, 1, 1, 0.0 if keyed else maxf(pixel.r, maxf(pixel.g, pixel.b)) * pixel.a))
	var font := FontFile.new()
	font.font_name = "Dwarf Fortress installed bitmap"
	font.fixed_size = cell.y
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var cache_size := Vector2i(cell.y, 0)
	font.set_texture_image(0, cache_size, 0, image)
	font.set_cache_ascent(0, cell.y, cell.y)
	font.set_cache_descent(0, cell.y, 0)
	for glyph in range(32, 127): _glyph(font, glyph, glyph, cell, cache_size)
	for i in CP437_SYMBOLS.size(): _glyph(font, CP437_SYMBOLS[i], i+1, cell, cache_size)
	_glyph(font, 0x2302, 127, cell, cache_size)
	for i in CP437_HIGH.size(): _glyph(font, CP437_HIGH[i], 128+i, cell, cache_size)
	# Unicode punctuation outside CP437 uses a legible ASCII approximation.
	for mapping in [[215, 120], [8212, 45], [8211, 45]]: _glyph(font, mapping[0], mapping[1], cell, cache_size)
	return font

static func _glyph(font: FontFile, code: int, tile: int, cell: Vector2i, size: Vector2i) -> void:
	font.set_glyph_advance(0, cell.y, code, Vector2(cell.x, 0))
	font.set_glyph_offset(0, size, code, Vector2(0, -cell.y))
	font.set_glyph_size(0, size, code, Vector2(cell))
	font.set_glyph_uv_rect(0, size, code, Rect2(Vector2((tile % 16) * cell.x, (tile / 16) * cell.y), Vector2(cell)))
	font.set_glyph_texture_idx(0, size, code, 0)
