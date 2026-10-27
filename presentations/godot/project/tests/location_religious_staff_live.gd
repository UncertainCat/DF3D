extends "res://tests/areas_acceptance_live.gd"
func exercise() -> void:
	await seed_catalog()
	if stopped:return
	var setup:=await native("religious_setup")
	var read: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
		"operation":Contract.AreaOperation.LocationReligiousStaffRead,"location_site_id":int(setup.site_id),"location_id":int(setup.location_id),
		"religious_entity_id":int(setup.entity_id),"religious_assignment_id":int(setup.assignment_id)}
	step="religious no-request control"
	await native("religious_guard")
	await create_timer(0.15).timeout
	var control:=await native("religious_unchanged")
	step="religious read"
	await native("religious_guard")
	var response:=await request(read)
	if stopped:return
	var snapshot: Dictionary=response.location_religious_staff
	if not check(snapshot.removable and snapshot.holder_id==int(setup.holder_id),"held assignment receipt"):return
	await native("religious_readback",{"snapshot":snapshot,"revision":str(snapshot.revision)})
	await native("religious_unchanged")
	var apply:=read.duplicate(true);apply.action=Contract.ManagementAction.AreaUpdate
	apply.operation=Contract.AreaOperation.LocationReligiousStaffRemove;apply.expected_revision=snapshot.revision;apply.religious_holder_id=snapshot.holder_id
	step="religious stale"
	await native("religious_change")
	await native("religious_guard")
	var stale:=await request(apply,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale and not stale.has("location_religious_staff"),"stale outcome"):return
	await native("religious_unchanged")
	await native("religious_change",{"restore":true})
	step="religious invalid identities"
	for key in ["location_id","location_site_id","religious_entity_id","religious_assignment_id","religious_holder_id"]:
		var invalid:=apply.duplicate(true);invalid[key]=2147483647
		await native("religious_guard")
		var rejected:=await request(invalid,"",true)
		if stopped:return
		if not check(rejected.location_edit_outcome==Contract.LocationEditOutcome.Rejected and not rejected.has("location_religious_staff"),"invalid target outcome"):return
		await native("religious_unchanged")
	step="religious removal"
	await native("religious_guard")
	response=await request(apply)
	if stopped:return
	if not check(response.location_edit_outcome==Contract.LocationEditOutcome.Completed,"completed outcome"):return
	snapshot=response.location_religious_staff
	if not check(not snapshot.removable and snapshot.holder_id==-1 and snapshot.unit_id==-1,"vacant receipt"):return
	await native("religious_readback",{"snapshot":snapshot,"revision":str(snapshot.revision)})
	var effects:=await native("religious_applied")
	step="religious repeat"
	await native("religious_guard")
	stale=await request(apply,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"completed old receipt"):return
	apply.expected_revision=snapshot.revision
	var refused:=await request(apply,"",true)
	if stopped:return
	if not check(refused.location_edit_outcome==Contract.LocationEditOutcome.Rejected,"completed fresh receipt"):return
	await native("religious_unchanged")
	step="religious candidate list"
	var list_request:=read.duplicate(true);list_request.operation=Contract.AreaOperation.LocationReligiousCandidates
	response=await request(list_request)
	if stopped:return
	var page: Dictionary=response.location_religious_candidates
	if not check(page.target.holder_id==-1 and page.total>0 and page.next_cursor==0,"complete vacant candidate list"):return
	await native("religious_candidates_readback",{"rows":page.rows})
	var selected_request:=read.duplicate(true);selected_request.operation=Contract.AreaOperation.LocationReligiousAssignmentRead
	selected_request.unit_id=page.rows[0].unit_id;selected_request.religious_holder_id=-1;selected_request.expected_list_revision=page.revision
	response=await request(selected_request)
	if stopped:return
	var selected: Dictionary=response.location_religious_assignment
	await native("religious_assignment_readback",{"unit_id":selected.unit_id,"histfig_id":selected.histfig_id,"nemesis_id":selected.nemesis_id,"revision":str(selected.revision)})
	var assign_request:=selected_request.duplicate(true);assign_request.action=Contract.ManagementAction.AreaUpdate
	assign_request.operation=Contract.AreaOperation.LocationReligiousAssign;assign_request.expected_revision=selected.revision
	step="religious selected dependency stale"
	await native("religious_assignment_change",{"unit_id":selected.unit_id})
	await native("religious_guard")
	stale=await request(assign_request,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"selected dependency refusal"):return
	await native("religious_unchanged")
	await native("religious_assignment_change",{"unit_id":selected.unit_id,"restore":true})
	step="religious list target stale"
	await native("religious_change")
	stale=await request(assign_request,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"list target refusal"):return
	await native("religious_change",{"restore":true})
	stale=await request(assign_request,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"restored target must not revive list"):return
	response=await request(list_request)
	if stopped:return
	page=response.location_religious_candidates;selected_request.expected_list_revision=page.revision
	response=await request(selected_request)
	if stopped:return
	selected=response.location_religious_assignment;assign_request.expected_list_revision=page.revision;assign_request.expected_revision=selected.revision
	step="religious assignment"
	await native("religious_guard")
	response=await request(assign_request)
	if stopped:return
	if not check(response.location_edit_outcome==Contract.LocationEditOutcome.Completed,"assignment completed"):return
	await native("religious_assignment_applied",{"unit_id":selected.unit_id,"histfig_id":selected.histfig_id})
	await native("religious_readback",{"snapshot":response.location_religious_staff,"revision":str(response.location_religious_staff.revision)})
	step="religious assignment replay"
	await native("religious_guard")
	stale=await request(assign_request,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"assignment replay refusal"):return
	await native("religious_unchanged")
	write_json("religious-assignment-evidence.json",{"unit_id":selected.unit_id,"histfig_id":selected.histfig_id,"candidate_count":page.total,"stale_checks":4,"completed":true})
	write_json("religious-staff-evidence.json",{"before":setup.before,"after":effects.after,"event":effects.event,"no_request_ui_changed":control.ui_changed,"apply_ui_changed":effects.ui_changed,"invalid_targets":5,"stale_checks":2,"vacant_rejections":1})
