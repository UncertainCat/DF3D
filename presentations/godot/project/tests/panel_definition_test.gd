extends "res://tests/ui_test_support.gd"
const Definition = preload("res://scripts/panel_definition.gd")
const DEFINITION_PATH = "res://panels/native_selection.json"
const BINDINGS = ["row.icon","row.name","selection.container_name","selection.description","selection.door_status","selection.icon","selection.job","selection.overview.age_sex","selection.overview.citizenship","selection.overview.current_thought","selection.overview.hauling","selection.overview.health","selection.overview.labor_skills","selection.overview.military","selection.overview.recent_thoughts","selection.overview.traits","selection.overview.unmet_needs","selection.portrait","selection.subtitle","selection.title","selection.weight_value"]
const ACTIONS = ["selection.inspect_item","selection.view_container"]
const DEFINITION_CONTRACT = {"layout_positive":["panel_width"],"layout_arrays":{"frame_margins":2,"body_insets":4,"feedback_rect":4,"tabs_origin":2},"required_nodes":["common.fallback_title"],"require_tabs":true}
func run():
	var definition := Definition.new()
	assert(definition.load_file(DEFINITION_PATH,BINDINGS,ACTIONS))
	assert(definition.data.provenance.authoring=="manual-reference-recipe")
	assert(definition.rect("unit.title")==Rect2(104,8,336,24))
	assert(definition.rect("building.item_name",Vector2(472,684),2)==Rect2(48,492,280,32))
	assert(definition.rect("unit.recent_thoughts",Vector2(472,684)).size.y==180)
	assert(definition.data.tab_rows[0][0].label=="Relations" and definition.data.tab_rows[1][0].label=="Overview")
	assert(definition.bound_text("unit.title",{"selection.title":"First fortress"})=="First fortress")
	assert(definition.bound_text("unit.title",{"selection.title":"Another fortress"})=="Another fortress")
	var editable := definition.data.duplicate(true)
	for node in editable.nodes:
		if node.id=="unit.title": node.rect=[120,10,300,24]
	assert(definition.load_data(editable,BINDINGS,ACTIONS))
	assert(definition.rect("unit.title").position==Vector2(120,10),"geometry is editable without changing controller code")
	var unknown := editable.duplicate(true)
	unknown.nodes.append({"id":"unknown","type":"widget_unmapped","rect":[0,0,10,10],"source_path":"Info/Unknown"})
	assert(definition.load_data(unknown))
	assert(not definition.nodes.has("unknown") and definition.unsupported.size()==1,"unknown native widgets are reported, never guessed")
	var invalid := editable.duplicate(true)
	invalid.nodes.append(invalid.nodes[0].duplicate(true))
	assert(not definition.load_data(invalid),"duplicate ids reject")
	invalid=editable.duplicate(true);invalid.nodes[0].rect=[0,0,-1,24]
	assert(not definition.load_data(invalid),"invalid geometry rejects")
	invalid=editable.duplicate(true);invalid.nodes[0].action="native.eval_arbitrary"
	assert(not definition.load_data(invalid,BINDINGS,ACTIONS),"unmapped actions reject")
	invalid=editable.duplicate(true);invalid.nodes[0].text="Captured citizen name"
	assert(not definition.load_data(invalid),"dynamic nodes cannot contain captured values")
	invalid=editable.duplicate(true);invalid.tab_rows={}
	assert(not definition.load_data(invalid),"wrong tab_rows type rejects")
	invalid=editable.duplicate(true);invalid.tab_rows[1][0].id=invalid.tab_rows[0][0].id
	assert(not definition.load_data(invalid),"duplicate tab identities reject across rows")
	var candidate := {"format_version":1,"id":"generic-import","provenance":{"status":"candidate"},"layout":{},"nodes":[]}
	assert(definition.load_data(candidate),"generic importer can keep an empty layout")
	definition.contract=DEFINITION_CONTRACT
	for field in ["frame_margins","body_insets","feedback_rect","tabs_origin"]:
		invalid=editable.duplicate(true);invalid.layout.erase(field)
		assert(not definition.load_data(invalid),"missing selection layout array rejects: "+field)
	invalid=editable.duplicate(true);invalid.layout.frame_margins=[8]
	assert(not definition.load_data(invalid),"wrong layout array shape rejects")
	invalid=editable.duplicate(true);invalid.layout.body_insets=[8,"twelve",8,12]
	assert(not definition.load_data(invalid),"non-numeric layout array rejects")
	invalid=editable.duplicate(true);invalid.layout.panel_width=0
	assert(not definition.load_data(invalid),"nonpositive panel width rejects")
	invalid=editable.duplicate(true);invalid.nodes.remove_at(0)
	assert(not definition.load_data(invalid),"missing required node rejects")
	assert(not definition.valid and definition.nodes.has("common.fallback_title")==false, "Malformed recipe clears usable state")
	print("PANEL_DEFINITION_TEST_PASS")
	quit()
