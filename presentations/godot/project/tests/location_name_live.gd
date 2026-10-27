extends "res://tests/areas_acceptance_live.gd"
# Typed semantic transport with independent native field/RNG readback.
func json_name(value: Dictionary) -> Dictionary:
	var result:=value.duplicate(true)
	result.first_name_bytes=Array(value.first_name_bytes)
	result.nickname_bytes=Array(value.nickname_bytes)
	return result

func exercise() -> void:
	await seed_catalog()
	if stopped:return
	var locations:=await native("name_locations")
	if not check(not locations.locations.is_empty(),"fixture locations missing"):return
	var cases:=0
	for location in locations.locations:
		var identity: Dictionary={"location_id":int(location.id)}
		var read: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
			"operation":Contract.AreaOperation.LocationNameRead,"location_site_id":int(location.site_id),"location_id":int(location.id)}
		step="name read %d" % int(location.id)
		await native("name_guard",identity)
		var reply:=await request(read)
		if stopped:return
		var snapshot: Dictionary=reply.location_name
		await verify_headers(snapshot)
		await native("name_read",{"location_id":int(location.id),"value":json_name(snapshot.value)})
		await native("name_unchanged",identity)
		# All components on the first location; a filtered page on every kind.
		for component in (range(7) if cases==0 else [0]):
			for query in (["","al"] if cases==0 else ["al"]):
				step="name choices %d component %d query %s" % [int(location.id),component,query]
				var intent:=read.duplicate(true);intent.operation=Contract.AreaOperation.LocationNameChoices
				intent.expected_revision=snapshot.revision
				intent.name_query={"component":component,"query_bytes":query.to_ascii_buffer(),"cursor":0}
				var rows: Array=[]
				while not stopped:
					var page_reply:=await request(intent)
					if stopped:return
					var page: Dictionary=page_reply.location_name_page
					if not check(page.snapshot==snapshot and page.cursor==rows.size(),"page identity/cursor"):return
					rows.append_array(page.choices)
					if not page.truncated:
						if not check(rows.size()==page.total and page.next_cursor==0,"terminal page"):return
						break
					if not check(page.next_cursor==rows.size() and not page.choices.is_empty(),"page progress"):return
					intent.name_query.cursor=page.next_cursor
				await native("name_choices",{"location_id":int(location.id),"component":component,"query":query,"choices":rows})
				await native("name_unchanged",identity)
				if stopped:return
				if rows.is_empty():continue
				# Clear and Select preserve every other native field and consume no RNG.
				for mode in [1,0]:
					await native("name_guard",identity)
					var edit:=read.duplicate(true);edit.action=Contract.ManagementAction.AreaUpdate
					edit.operation=Contract.AreaOperation.LocationNameEdit;edit.expected_revision=snapshot.revision
					edit.name_edit={"mode":mode,"target":component,"displayed":component,
						"word":rows[0].word if mode==1 else -1,"part":rows[0].part if mode==1 else -1,"query_bytes":query.to_ascii_buffer()}
					var result:=await request(edit)
					if stopped:return
					if not check(result.location_edit_outcome==Contract.LocationEditOutcome.Completed,"edit outcome"):return
					await verify_headers(result.location_name)
					await native("name_edit_check",{"location_id":int(location.id),"mode":mode,"target":component,
						"word":edit.name_edit.word,"part":edit.name_edit.part,"value":json_name(result.location_name.value)})
					if result.location_name.revision!=snapshot.revision:
						await native("name_guard",identity)
						var stale:=await request(edit,"",true)
						if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale and not stale.has("location_name"),"stale outcome"):return
						await native("name_unchanged",identity)
					snapshot=result.location_name
				await native("name_guard",identity)
		for mode in [2,3]:
			step="name random %d mode %d" % [int(location.id),mode]
			await native("name_guard",identity)
			var edit:=read.duplicate(true);edit.action=Contract.ManagementAction.AreaUpdate
			edit.operation=Contract.AreaOperation.LocationNameEdit;edit.expected_revision=snapshot.revision
			edit.name_edit={"mode":mode,"target":-1 if mode==3 else 6,"displayed":-1 if mode==3 else 0,
				"word":-1,"part":-1,"query_bytes":PackedByteArray()}
			var result:=await request(edit)
			if stopped:return
			if not check(result.location_edit_outcome==Contract.LocationEditOutcome.Completed,"random outcome"):return
			await verify_headers(result.location_name)
			await native("name_random_check",{"location_id":int(location.id),"mode":mode,"target":6,"displayed":0,
				"value":json_name(result.location_name.value)})
			if result.location_name.revision!=snapshot.revision:
				await native("name_guard",identity)
				var stale:=await request(edit,"",true)
				if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"stale random outcome"):return
				await native("name_unchanged",identity)
			snapshot=result.location_name
			await native("name_guard",identity)
			for key in ["location_id","location_site_id"]:
				var invalid:=edit.duplicate(true);invalid[key]=2147483647;invalid.expected_revision=snapshot.revision
				var rejected:=await request(invalid,"",true)
				if not check(rejected.location_edit_outcome==Contract.LocationEditOutcome.Rejected and not rejected.has("location_name"),"invalid random target"):return
				await native("name_unchanged",identity)
		cases+=1
	write_json("naming-evidence.json",{"locations":cases,"scope":"read, complete pages, all four edit modes, stale and invalid targets, native fields and RNG; exact Random oracle covered separately"})

func verify_headers(snapshot: Dictionary) -> void:
	await native("name_headers",{"location_id":snapshot.id,"native_header":snapshot.native_header,"english_header":snapshot.english_header})
