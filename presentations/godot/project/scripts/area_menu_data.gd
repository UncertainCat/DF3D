extends RefCounted
# Native menu order is separate from wire category bits and observed zone IDs.
const PATH := "res://panels/area_menus.json"

static func read() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary else {}

static func category_labels_by_bit(data: Dictionary) -> Array[String]:
	var labels: Array[String] = []
	labels.resize(17)
	for row in data.get("categories", []):
		var bit := int(row.bit)
		if bit >= 0 and bit < labels.size(): labels[bit] = str(row.label)
	return labels

static func observed_zones(data: Dictionary, catalog: Array) -> Array:
	var by_name: Dictionary = {}
	for row in catalog: by_name[str(row.name)] = row
	var result: Array = []
	for definition in data.get("zones", []):
		if not by_name.has(str(definition.name)): continue
		var observed: Dictionary = by_name[str(definition.name)]
		var row: Dictionary = definition.duplicate(true)
		row.id = int(observed.id)
		row.label = str(observed.get("label", definition.label))
		result.append(row)
	return result
