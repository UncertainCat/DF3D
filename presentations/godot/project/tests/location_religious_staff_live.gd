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
	write_json("religious-staff-evidence.json",{"before":setup.before,"after":effects.after,"event":effects.event,"no_request_ui_changed":control.ui_changed,"apply_ui_changed":effects.ui_changed,"invalid_targets":5,"stale_checks":2,"vacant_rejections":1})
