extends SceneTree
const Layout=preload("res://scripts/creature_health_layout.gd")
func _initialize() -> void:
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json")).chest_header_reference.unit_health_pages_reference
 var failures:=0
 var raw: Array=fixture.owned_probe_reference.pages
 for page_index in 5:
  var reference: Dictionary=fixture.formatted_text_reference.pages[page_index]
  for box_index in reference.boxes.size():
   var expected: Dictionary=reference.boxes[box_index]
   var actual: Array=Layout.new().build(raw[page_index].probe.rows[box_index],int(expected.width))
   if actual.size()!=expected.lines.size():push_error("Health line count differs: "+reference.name);failures+=1;continue
   for i in actual.size():
    var colors:=PackedInt32Array()
    for run in expected.lines[i].color_runs:
     for _j in int(run[1]):colors.append(int(run[0]))
    if actual[i].text!=expected.lines[i].text or actual[i].colors!=colors:
     push_error("Health native text/color differs: %s box%d line%d: %s" % [reference.name,box_index,i,actual[i].text]);failures+=1
 var additional_pages: Array=fixture.syndrome_history_reference.formatted_pages.duplicate()
 additional_pages.append_array(fixture.clinical_cases_reference.formatted_pages)
 additional_pages.append_array(fixture.description_cases_reference.formatted_pages)
 for reference in additional_pages:
  for box_index in reference.boxes.size():
   var expected: Dictionary=reference.boxes[box_index]
   var actual: Array=Layout.new().build(reference.rows[box_index],int(expected.width))
   if actual.size()!=expected.lines.size():push_error("Additional Health line count differs: "+reference.name);failures+=1;continue
   for i in actual.size():
    var colors:=PackedInt32Array()
    for run in expected.lines[i].color_runs:
     for _j in int(run[1]):colors.append(int(run[0]))
    if actual[i].text!=expected.lines[i].text or actual[i].colors!=colors:
     push_error("Additional Health native text/color differs: %s box%d line%d" % [reference.name,box_index,i]);failures+=1
 if failures==0:print("CREATURE_HEALTH_LAYOUT_PASS")
 quit(1 if failures else 0)
