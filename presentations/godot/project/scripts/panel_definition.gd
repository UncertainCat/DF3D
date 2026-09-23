extends RefCounted
# Editable presentation recipes, not executable scripts or captured fort state.
# Native widget dumps remain development references outside the runtime loader.
const TYPES = ["label","texture","button","separator"]
var data: Dictionary = {}
var nodes: Dictionary = {}
var errors: Array[String] = []
var unsupported: Array[Dictionary] = []
# Optional consumer contract. Generic imported candidates may keep layout={}.
var contract: Dictionary = {}
var valid := false

func load_file(path: String, bindings: Array = [], actions: Array = []) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		clear()
		errors.append("Cannot open panel definition: "+path)
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		clear()
		errors.append("Invalid panel JSON: "+parser.get_error_message())
		return false
	return load_data(parser.data,bindings,actions)

func clear():
	valid = false
	data = {}
	nodes = {}
	errors.clear()
	unsupported.clear()

func load_data(source: Variant, bindings: Array = [], actions: Array = []) -> bool:
	clear()
	if not source is Dictionary:
		errors.append("Panel definition must be an object")
		return false
	if int(source.get("format_version",0)) != 1: errors.append("Unsupported panel format_version")
	if str(source.get("id","")).is_empty(): errors.append("Panel id is required")
	if not source.get("provenance",{}) is Dictionary or source.get("provenance",{}).is_empty(): errors.append("Reference provenance is required")
	if not source.get("layout",{}) is Dictionary: errors.append("Panel layout must be an object")
	if not source.get("unsupported_widgets",[]) is Array: errors.append("Unsupported widget report must be an array")
	if not source.get("tab_rows",[]) is Array: errors.append("Tab rows must be an array")
	if not errors.is_empty(): return false
	if not source.get("nodes",[]) is Array:
		errors.append("Panel nodes must be an array")
		return false
	for raw in source.get("unsupported_widgets",[]):
		if raw is Dictionary: unsupported.append(raw.duplicate(true))
	var seen := {}
	for raw in source.get("nodes",[]):
		if not raw is Dictionary:
			errors.append("Panel node must be an object")
			continue
		var id := str(raw.get("id",""))
		if id.is_empty() or seen.has(id):
			errors.append("Missing or duplicate node id: "+id)
			continue
		seen[id] = true
		if str(raw.get("type","")) not in TYPES:
			unsupported.append({"source_path":raw.get("source_path",id),"native_type":raw.get("type",""),"reason":"No presentation node mapping; omitted"})
			continue
		if not valid_rect(raw.get("rect",[])):
			errors.append("Invalid rectangle for "+id)
			continue
		for key in ["bottom_offset","min_y","row_step"]:
			if raw.has(key) and (not (raw[key] is int or raw[key] is float) or not is_finite(float(raw[key]))): errors.append("Invalid geometry field %s for %s" % [key,id])
		for pair in [["binding",bindings],["action",actions]]:
			var value := str(raw.get(pair[0],""))
			if not value.is_empty() and not pair[1].is_empty() and value not in pair[1]: errors.append("Unmapped %s for %s: %s" % [pair[0],id,value])
		if raw.has("binding") and raw.has("text"): errors.append("Dynamic binding cannot contain a captured text value: "+id)
		nodes[id] = raw.duplicate(true)
	var tab_ids := {}
	for row in source.get("tab_rows",[]):
		if not row is Array:
			errors.append("Tab row must be an array")
			continue
		for tab in row:
			if not tab is Dictionary or str(tab.get("id","")).is_empty() or not tab.has("label") or not tab.label is String:
				errors.append("Tab requires a stable id and static label")
				continue
			var id := str(tab.id)
			if tab_ids.has(id): errors.append("Duplicate tab id: "+id)
			tab_ids[id] = true
	validate_contract(source)
	if not errors.is_empty():
		nodes.clear()
		return false
	data = source.duplicate(true)
	valid = true
	return true

func validate_contract(source: Dictionary):
	var layout_data: Dictionary = source.get("layout",{})
	for key in contract.get("layout_numbers",[]):
		if not finite_number(layout_data.get(key)): errors.append("Required numeric layout field: "+key)
	for key in contract.get("layout_positive",[]):
		if not finite_number(layout_data.get(key)) or float(layout_data[key])<=0.0: errors.append("Required positive layout field: "+key)
	for key in contract.get("layout_strings",[]):
		if not layout_data.get(key) is String or str(layout_data[key]).is_empty(): errors.append("Required layout selector: "+key)
	for key in contract.get("layout_arrays",{}):
		var array = layout_data.get(key)
		if not array is Array or array.size()!=int(contract.layout_arrays[key]):
			errors.append("Wrong layout array shape: "+key)
			continue
		for value in array:
			if not finite_number(value): errors.append("Non-numeric layout array: "+key); break
	for id in contract.get("required_nodes",[]):
		if not nodes.has(id): errors.append("Required panel node missing: "+id)
	if bool(contract.get("require_tabs",false)) and tab_count(source.get("tab_rows",[]))==0: errors.append("Required panel tab rows missing")

static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func tab_count(rows: Array) -> int:
	var count := 0
	for row in rows:
		if row is Array: count += row.size()
	return count

static func valid_rect(value: Variant) -> bool:
	if not value is Array or value.size()!=4: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return float(value[2])>=0.0 and float(value[3])>=0.0

func node(id: String) -> Dictionary:
	return nodes.get(id,{})

func rect(id: String, body_size := Vector2.ZERO, row_index := 0) -> Rect2:
	var value := node(id)
	if value.is_empty(): return Rect2()
	var r: Array = value.rect
	var position := Vector2(float(r[0]),float(r[1]))
	var dimensions := Vector2(float(r[2]),float(r[3]))
	if value.has("bottom_offset"):
		position.y += maxf(float(value.get("min_y",0)),body_size.y-float(value.bottom_offset))
	position.y += row_index*float(value.get("row_step",0))
	if bool(value.get("grow_to_bottom",false)): dimensions.y = maxf(dimensions.y,body_size.y-position.y)
	return Rect2(position,dimensions)

func layout(key: String, fallback: Variant = null) -> Variant:
	return data.get("layout",{}).get(key,fallback)

func bound_text(id: String, values: Dictionary) -> String:
	var value := node(id)
	if value.has("binding"): return str(values.get(str(value.binding),""))
	return str(value.get("text",""))

func action(id: String) -> String:
	return str(node(id).get("action",""))
