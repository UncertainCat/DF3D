extends SceneTree
const Registry = preload("res://scripts/ui_availability.gd")
func _initialize(): call_deferred("run")
func run():
	var composition=preload("res://scripts/fortress_ui.gd").new()
	root.add_child(composition)
	assert(composition.controllers.is_empty(), "Product composition starts with zero hidden or eager controllers")
	for title in ["Stocks","Kitchen","Nobles and administrators","Tile details","Trade","Petitions","Production / farms","Tasks","Places","Objects","Justice"]:
		assert(not Registry.allows(title), "Retired route fails closed: "+title)
		assert(not Registry.PANEL_ROUTES.has(title), "Retired route has no factory")
	for id in ["stocks","kitchen","appointments","native_selection","trade","agreements","notifications","production","rough_panels","citizens","work_orders"]:
		assert(composition.controller(id)==null, "Retired controller cannot be instantiated: "+id)
	assert(composition.controllers.is_empty() and composition.get_child_count()==0, "Rejected destinations do not construct any runtime nodes")
	for title in ["Build / construction","Stockpiles / zones","Residents","Work Details","Work orders","Reports"]:
		assert(Registry.allows(title) and Registry.PANEL_SCRIPTS.has(Registry.PANEL_ROUTES[title]), "Accepted route has exactly one registered factory")
	assert(Registry.PANEL_SCRIPTS.size()==6,"Accepted controllers only")
	composition.free()
	print("ADAPTER_RETIREMENT_PASS")
	quit()
