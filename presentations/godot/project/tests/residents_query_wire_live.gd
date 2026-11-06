extends "res://tests/item_carrier_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-list-reference.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Residents bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Residents catalog failed"):quit(1);return
	var results: Array=[]
	var sorts: Dictionary={"initial":0,"Cat":0,"Name":1,"Prof":2,"Stress":3,"Job":4}
	for snapshot: Dictionary in expected.snapshots:
		var label: String=snapshot.name
		var query: String=snapshot.get("query","")
		var intent: Dictionary={"action":C.ManagementAction.ResidentsQuery,"sort":sorts[label.get_slice("-",0)],"descending":label.ends_with("-2"),"query_bytes":query.to_utf8_buffer()}
		var response:=await request("residents",intent)
		var ids: PackedInt32Array=response.get("residents",{}).get("unit_ids",PackedInt32Array())
		var matches: bool=response.get("status")==C.ManagementStatus.Ok and response.has("residents") and ids==PackedInt32Array(snapshot.ids)
		check(matches,"Residents wire differs: "+label)
		results.append({"name":label,"count":ids.size(),"matches":matches})
	var row_comparisons: Array=[]
	if FileAccess.file_exists(directory+"/residents-row-reference.json"):
		var row_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/residents-row-reference.json"))
		var samples: Array=row_reference.samples
		if samples[0].has("portrait_prefix"):
			check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Residents portrait assets unavailable")
		samples.reverse()
		var ids:=PackedInt32Array()
		for sample: Dictionary in samples:ids.append(int(sample.id))
		var response:=await request("residents_rows",{"action":C.ManagementAction.ResidentsRowsRead,"unit_ids":ids,"columns":30,"show_gender":false})
		var rows: Array=response.get("residents_rows",{}).get("rows",[])
		check(response.get("status")==C.ManagementStatus.Ok and rows.size()==samples.size(),"Residents row batch failed")
		for i in mini(rows.size(),samples.size()):
			var expected_row: Dictionary=samples[i].provider
			var actual: Dictionary=rows[i]
			var matches: bool=actual.id==expected_row.id
			for field: String in ["combined","name","profession","first_line","second_line"]:
				matches=matches and actual[field]==expected_row[field]
			# JSON numbers are floats; nested Variant container equality is type
			# sensitive, unlike scalar numeric comparison.
			for field: String in ["caption","fg","bg","bright"]:
				matches=matches and actual.activity[field]==expected_row.activity[field]
			matches=matches and actual.get("happiness",-1)==expected_row.happiness
			matches=matches and actual.name_color.effect==expected_row.name_color.effect
			for field: String in ["color","alternate"]:
				for component in 3:
					matches=matches and actual.name_color[field][component]==expected_row.name_color[field][component]
			if samples[i].has("portrait_prefix"):
				var prefix: String=directory+"/"+samples[i].portrait_prefix
				var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(prefix+".json"))
				var expected_image:=Image.create_from_data(int(metadata.width),int(metadata.height),false,Image.FORMAT_RGBA8,FileAccess.get_file_as_bytes(prefix+".rgba"))
				var texture: Texture2D=world.candidate_icon(actual.get("sheet_icon",{}))
				var bad:=0
				if texture==null or Vector2i(texture.get_size())!=expected_image.get_size():bad=-1
				else:
					var actual_image:=texture.get_image()
					for y in expected_image.get_height():
						for x in expected_image.get_width():
							var a:=actual_image.get_pixel(x,y);var e:=expected_image.get_pixel(x,y)
							if a.a<0.03 and e.a<0.03:continue
							if absf(a.r-e.r)+absf(a.g-e.g)+absf(a.b-e.b)+absf(a.a-e.a)>0.02:bad+=1
				check(bad==0,"Residents portrait differs: "+str(actual.id)+" pixels="+str(bad))
			check(matches,"Residents row content differs: "+str(expected_row.id))
			row_comparisons.append({"id":actual.id,"matches":matches,"actual":actual})
		var rejected:=await request("residents_rows",{"action":C.ManagementAction.ResidentsRowsRead,"unit_ids":PackedInt32Array([ids[0],2147483647]),"columns":30,"show_gender":false})
		check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.has("residents_rows"),"Unavailable resident returned a partial batch")
		for bad_ids in [PackedInt32Array(),PackedInt32Array([ids[0],ids[0]]),[ids[0]]]:
			check(world.management_request("residents_rows",{"action":C.ManagementAction.ResidentsRowsRead,"unit_ids":bad_ids,"columns":30,"show_gender":false})==0,"Malformed row batch accepted")
	for bad: Dictionary in [
		{"action":C.ManagementAction.ResidentsQuery,"sort":5,"descending":false,"query_bytes":PackedByteArray()},
		{"action":C.ManagementAction.ResidentsQuery,"sort":0,"descending":false,"query_bytes":PackedByteArray([0])},
		{"action":C.ManagementAction.ResidentsQuery,"sort":0,"descending":false,"query_bytes":[]},
	]:
		check(world.management_request("residents",bad)==0,"Malformed Residents query accepted")
	var cleared:=await request("construction",{"action":C.ManagementAction.Catalog})
	check(cleared.get("status")==C.ManagementStatus.Ok and not cleared.has("residents") and not cleared.has("residents_rows"),"Unrelated reply retained Residents result")
	var file:=FileAccess.open(directory+"/residents-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"comparisons":results,"row_comparisons":row_comparisons}));file.close()
	world.queue_free();await process_frame
	quit(1 if failed else 0)
