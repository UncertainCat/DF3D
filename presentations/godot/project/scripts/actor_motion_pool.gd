extends RefCounted
# Stable slots, small independently uploaded pages. No work on clock-only frames.
const PAGE_SIZE := 32
var texture := Texture2DArray.new()
var pages: Array[Image] = []
var slots: Dictionary = {}
var free_slots: Array[int] = []
var next_slot := 0
var generation := -1
var dirty: Dictionary = {}
var uploads := 0
var upload_bytes := 0
func reset(value: int) -> void:
	if value == generation: return
	generation = value
	slots.clear(); free_slots.clear(); next_slot = 0
func slot_for(id: int) -> int:
	if slots.has(id): return slots[id]
	var slot: int = free_slots.pop_back() if not free_slots.is_empty() else next_slot
	if slot == next_slot: next_slot += 1
	slots[id] = slot
	return slot
func retain(ids: PackedInt64Array) -> void:
	var live := {}
	for id in ids: live[id] = true
	for id in slots.keys():
		if not live.has(id):
			free_slots.append(slots[id]); slots.erase(id)
func write(id: int, first: Color, last: Color, epochs: Vector2, tile: Vector3, ordinal: int) -> int:
	var slot := slot_for(id)
	var page := slot / PAGE_SIZE
	while pages.size() <= page:
		pages.append(Image.create(4, PAGE_SIZE, false, Image.FORMAT_RGBAF))
		dirty[-1] = true
	var row := slot % PAGE_SIZE
	var values := [first, last, Color(epochs.x, epochs.y, ordinal, 0), Color(tile.x, tile.y, tile.z, 1)]
	for column in 4:
		if pages[page].get_pixel(column, row) != values[column]:
			pages[page].set_pixel(column, row, values[column]); dirty[page] = true
	return slot + 1
func flush() -> void:
	if dirty.is_empty(): return
	if dirty.has(-1):
		texture.create_from_images(pages)
		uploads += pages.size(); upload_bytes += pages.size() * PAGE_SIZE * 4 * 16
	else:
		for page in dirty:
			texture.update_layer(pages[page], page)
			uploads += 1; upload_bytes += PAGE_SIZE * 4 * 16
	dirty.clear()
func bind_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("actor_motion_texture", texture)
	material.set_shader_parameter("actor_motion_enabled", true)
