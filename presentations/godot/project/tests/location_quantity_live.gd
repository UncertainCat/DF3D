extends "res://tests/areas_acceptance_live.gd"
# Real semantic transport plus independent native readback. No rendered UI claim.
func exercise() -> void:
	await seed_catalog()
	if stopped:return
	var locations:=await native("quantity_locations")
	var cases:=0
	for location in locations.get("locations",[]):
		var read: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
			"operation":Contract.AreaOperation.LocationDetails,"location_site_id":int(location.site_id),"location_id":int(location.id)}
		var page:=await request(read)
		if stopped:return
		var details: Dictionary=page.location_details
		var fields: Array={1:[0,1],2:[1],3:[2,10],4:[],5:[3,4,5,6,7,8,9]}.get(int(details.kind),[])
		for quantity in fields:
			cases+=1;step="quantity %d location %d" % [quantity,int(location.id)]
			var scale:int={4:15000,5:10000,7:150,9:150}.get(quantity,1)
			for mode in 3:
				page=await request(read)
				if stopped:return
				var intent:=read.duplicate();intent.action=Contract.ManagementAction.AreaUpdate
				intent.operation=Contract.AreaOperation.LocationQuantity;intent.expected_revision=page.location_details.revision
				intent.quantity_id=quantity;intent.quantity_mode=mode;intent.quantity_value=6 if mode==0 else 0
				var result:=await request(intent)
				if stopped:return
				var expected: int=(7 if mode==1 else 6)*scale
				if not check(result.location_edit_outcome==Contract.LocationEditOutcome.Completed,"quantity outcome"):return
				var actual: int=result.location_details.desired_copies if quantity==10 else result.location_details.supplies[quantity].desired
				if not check(actual==expected,"refreshed quantity"):return
				await native("quantity_check",{"location_id":int(location.id),"quantity_id":quantity,"value":expected})
				if stopped:return
				# Reuse the old revision only when the successful edit changed it.
				if result.location_details.revision!=intent.expected_revision:
					var rejected:=await request(intent,"",true)
					if not check(rejected.get("location_edit_outcome")==Contract.LocationEditOutcome.Stale and not rejected.has("location_details"),"stale quantity receipt"):return
			# Seed a raw remainder, then verify step preservation through transport.
			await native("quantity_seed",{"location_id":int(location.id),"quantity_id":quantity,"value":1})
			page=await request(read)
			if stopped:return
			var intent:=read.duplicate();intent.action=Contract.ManagementAction.AreaUpdate
			intent.operation=Contract.AreaOperation.LocationQuantity;intent.expected_revision=page.location_details.revision
			intent.quantity_id=quantity;intent.quantity_mode=Contract.LocationQuantityMode.Decrease;intent.quantity_value=0
			var result:=await request(intent)
			if stopped:return
			if not check(result.location_edit_outcome==Contract.LocationEditOutcome.Completed,"partial quantity receipt"):return
			await native("quantity_check",{"location_id":int(location.id),"quantity_id":quantity,"value":1-scale})
			if stopped:return
	if check(cases==13,"quantity field coverage"):print("LOCATION_QUANTITY_TRANSPORT_PASS cases=",cases)
