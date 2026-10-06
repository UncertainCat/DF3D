extends SceneTree
const Format = preload("res://scripts/location_details_format.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../fixtures/areas/"+name)))
func _initialize() -> void:
	var values:=fixture("native_location_value.json")
	check(values.rows.size()==1341,"Native appraisal coverage missing")
	for row in values.rows:
		var formatted:=Format.appraised_value(int(row.value),int(row.appraisal))
		var displayed: String=(formatted.text+" "+formatted.after_currency).strip_edges()
		check(displayed==row.displayed,"Native appraisal mismatch: "+str(row))
	var appraisers:=fixture("native_location_appraiser.json")
	check(appraisers.rows.size()==30,"Native broker-selection coverage missing")
	for row in appraisers.rows:
		var formatted:=Format.appraised_value(int(row.value),int(row.appraisal))
		check((formatted.text+" "+formatted.after_currency).strip_edges()==row.displayed,"Native broker value mismatch: "+str(row))
	var supplies:=fixture("native_location_details.json")
	var kinds: Array=["goblets","instruments","paper","splints","thread","cloth","crutches","powder","buckets","soap"]
	check(supplies.supplies.size()==152,"Native supply coverage missing")
	for row in supplies.supplies:
		var desired: bool=str(row.field).begins_with("desired_")
		var field: String=str(row.field).trim_prefix("desired_" if desired else "count_")
		check(Format.supply_quantity(int(row.raw),kinds.find(field),desired)==int(row.displayed),"Native supply mismatch: "+str(row))
	check(Format.appraised_value(null,15).is_empty() and Format.appraised_value(12345,null).is_empty(),"Unknown appraisal facts must not become zero")
	check(Format.appraised_value(12345,-2).is_empty(),"Unknown sentinel must not become native no-appraiser")
	check(Format.supply_quantity(null,0,false)==null and Format.supply_quantity(0,-1,false)==null,"Unknown supply must stay unknown")
	var staff:=fixture("native_location_staff_labels.json")
	check(staff.cases.size()==40,"Native staff label coverage missing")
	var observed_roles: Dictionary={}
	for row in staff.occupation_labels:
		check(Format.occupation_label(int(row.role))==row.label,"Native occupation label mismatch: "+str(row))
		observed_roles[int(row.role)]=true
	check(observed_roles.size()==8,"All native Details occupation roles required")
	for role in [null,-1,3,4,6,11,"1",1.0]:
		check(Format.occupation_label(role)==null,"Unsupported role must not acquire invented copy")
	var staff_visual:=fixture("native_location_staff_visual.json")
	check(staff_visual.rows.size()==2946,"Native staff clipping coverage missing")
	for row in staff_visual.rows:
		check(Format.staff_holder_name(row.name,int(row.width))==row.displayed,"Native holder clipping mismatch: "+str(row))
	check(Format.staff_holder_name(null,14)==null,"Unknown holder name must remain unknown")
	var staff_layout:=fixture("native_location_staff_layout.json")
	check(staff_layout.rows.size()==50,"Native staff row-count coverage missing")
	for row in staff_layout.rows:
		var layout:=Format.staff_layout(int(row.kind),int(row.count))
		for field in ["first_y","capacity","width"]:
			check(layout[field]==int(row[field]),"Native staff layout mismatch: "+str(row))
		check(layout.visible_count==row.visible_y.size(),"Native visible staff row count mismatch")
		for i in row.visible_y.size():
			check(layout.first_y+i*3==int(row.visible_y[i]),"Native staff row spacing mismatch")
			check(Format.staff_holder_name(row.holders[i].name,layout.width)==row.holders[i].displayed,"Native scrollbar-dependent clipping mismatch")
	print("LOCATION_DETAILS_FORMAT_PASS" if failures==0 else "LOCATION_DETAILS_FORMAT_FAIL")
	quit(failures)
