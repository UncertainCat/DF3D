extends SceneTree
const Format = preload("res://scripts/location_staff_candidates_format.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:failures+=1;push_error(reason)
func _initialize() -> void:
	var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_selector_ui.json"))
	var count:=0
	var captions:=0
	var rows: Array=[]
	for list in evidence.defaults:rows.append_array(list.rows)
	for controlled in evidence.rating_cases:rows.append(controlled.row)
	for row in rows:
		var skills: Array=[]
		for skill in row.skills:
			skills.append({"id":int(skill.id),"rating":int(skill.rating),"weight":int(skill.weight),"experience":int(skill.experience)})
		var original:=skills.duplicate(true)
		var lines=Format.skill_lines(skills)
		check(lines==row.displayed_skills,"native skill text/order differs for unit %d"%int(row.unit_id))
		check(skills==original,"formatting changed observed skill facts")
		count+=1;captions+=row.displayed_skills.size()
	check(count==1157,"native fixture row coverage missing")
	for invalid in [[{}],[{"id":999,"rating":1,"weight":1}],[{"id":58,"rating":-1,"weight":1}],
		[{"id":58,"rating":1,"weight":0}],[{"id":58,"rating":1.0,"weight":1}],
		[{"id":58,"rating":1,"weight":1},{"id":58,"rating":2,"weight":1}]]:
		check(Format.skill_lines(invalid)==null,"unknown or malformed facts must not invent copy")
	check(Format.skill_lines([])==[],"empty native skills remain empty")
	var colors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_name_colors.json"))
	var coverage: Dictionary={}
	for sample in colors.cases:
		var base:=int(sample.base_color)
		var legendary:=int(sample.skill_rating)>=15
		var observed:=int(sample.observed_color)
		var matched:=false
		# Native rendering and GetTickCount have one Windows timer quantum of
		# uncertainty. Keep that recorded bound explicit, not an arbitrary retry.
		for tick in range(int(sample.tick_before)-int(colors.tick_uncertainty_ms),int(sample.tick_after)+int(colors.tick_uncertainty_ms)+1):
			if Format.name_color_index(base,legendary,tick)==observed:matched=true;break
		check(matched,"native name color/phase differs: "+str(sample))
		var key:=str(base)+":"+str(legendary)
		if not coverage.has(key):coverage[key]=[]
		if not coverage[key].has(observed):coverage[key].append(observed)
	check(colors.cases.size()==1024 and coverage.size()==32,"native color coverage missing")
	for base in 16:
		check(coverage.get(str(base)+":true",[]).size()==2,"both native legendary phases required")
		check(coverage.get(str(base)+":false",[]).size()==1,"ordinary name color must remain stable")
	var names: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_names.json"))
	check(names.rows.size()==195,"native named-row color coverage missing")
	for row in names.rows:
		var name_lines=Format.name_lines(row.base_name,row.native_profession)
		check(name_lines!=null and [name_lines[0].rstrip(" "),name_lines[1].rstrip(" ")]==row.lines,"native name wrapping/capitalization differs for unit "+str(row.unit_id))
		# Earlier ordinary/selected rows have no retained timer. Check the
		# allowed colors; the timed fixture above checks the animation phase.
		var possible: Array=[Format.name_color_index(int(row.profession_color),row.legendary,0),Format.name_color_index(int(row.profession_color),row.legendary,500)]
		for line in row.cells:
			for cell in line:
				if int(cell[0]) in [0,32]:continue
				check(possible.has(int(cell[1])+(8 if cell[2] else 0)),"native row color differs for unit "+str(row.unit_id))
	for invalid in [null,-1,16,1.0,"1"]:
		check(Format.name_color_index(invalid,false,0)==-1,"unknown color must remain unknown")
	check(Format.name_color_index(7,true,-1)==-1,"invalid clock must remain unknown")
	var abbreviation: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_name_abbreviation.json"))
	check(abbreviation.cases.size()==107,"native abbreviation coverage missing")
	for sample in abbreviation.cases:
		var actual=Format.name_lines(sample.name,sample.profession)
		check(actual!=null and [actual[0].rstrip(" "),actual[1].rstrip(" ")]==sample.lines,"native abbreviation/capitalization differs: "+str(sample))
	for invalid in [[null,"Smith"],["Ab",null],["Ab",""]]:
		check(Format.name_lines(invalid[0],invalid[1])==null,"unknown name/profession must not invent copy")
	check(Format.name_lines("Ab","Smith",0)==null,"invalid field width accepted")
	print("LOCATION_STAFF_CANDIDATES_FORMAT_PASS rows=%d captions=%d"%[count,captions] if failures==0 else "LOCATION_STAFF_CANDIDATES_FORMAT_FAIL")
	quit(failures)
