extends "res://tests/areas_acceptance_live.gd"
func exercise() -> void:
	await seed_catalog()
	if stopped:return
	var setup:=await native("recognition_setup")
	var read: Dictionary={"action":Contract.ManagementAction.AreaInspect,"kind":1,
		"operation":Contract.AreaOperation.LocationRecognitionRead,"location_site_id":int(setup.site_id),"location_id":int(setup.location_id)}
	step="no-request UI control"
	await native("recognition_guard")
	await create_timer(0.15).timeout
	var control:=await native("recognition_unchanged")
	step="recognition read"
	await native("recognition_guard")
	var response:=await request(read)
	if stopped:return
	var snapshot: Dictionary=response.location_recognition
	await native("recognition_readback",{"snapshot":snapshot,"revision":str(snapshot.revision)})
	await native("recognition_unchanged")
	var apply:=read.duplicate(true);apply.action=Contract.ManagementAction.AreaUpdate
	apply.operation=Contract.AreaOperation.LocationRecognize;apply.expected_revision=snapshot.revision
	step="recognition stale"
	await native("recognition_threshold")
	await native("recognition_guard")
	var stale:=await request(apply,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale and not stale.has("location_recognition"),"stale outcome"):return
	await native("recognition_unchanged")
	await native("recognition_threshold",{"restore":true})
	step="recognition invalid targets"
	for key in ["location_id","location_site_id"]:
		var invalid:=apply.duplicate(true);invalid[key]=2147483647
		await native("recognition_guard")
		var rejected:=await request(invalid,"",true)
		if stopped:return
		if not check(rejected.location_edit_outcome==Contract.LocationEditOutcome.Rejected and not rejected.has("location_recognition"),"invalid target outcome"):return
		await native("recognition_unchanged")
	step="recognition ineligible"
	await native("recognition_tier",{"value":0})
	response=await request(read)
	if stopped:return
	var ineligible:=apply.duplicate(true);ineligible.expected_revision=response.location_recognition.revision
	await native("recognition_guard")
	var refused:=await request(ineligible,"",true)
	if stopped:return
	if not check(refused.location_edit_outcome==Contract.LocationEditOutcome.Rejected,"ineligible outcome"):return
	await native("recognition_unchanged")
	await native("recognition_tier",{"value":2})
	step="recognition apply"
	await native("recognition_guard")
	response=await request(apply)
	if stopped:return
	if not check(response.location_edit_outcome==Contract.LocationEditOutcome.Completed,"apply outcome"):return
	snapshot=response.location_recognition
	if not check(snapshot.rank==2 and snapshot.state==Contract.LocationRecognitionState.NoAction,"post-apply state"):return
	await native("recognition_readback",{"snapshot":snapshot,"revision":str(snapshot.revision)})
	var effects:=await native("recognition_applied")
	step="recognition repeat"
	await native("recognition_guard")
	stale=await request(apply,"",true)
	if stopped:return
	if not check(stale.location_edit_outcome==Contract.LocationEditOutcome.Stale,"old apply receipt"):return
	apply.expected_revision=snapshot.revision
	refused=await request(apply,"",true)
	if stopped:return
	if not check(refused.location_edit_outcome==Contract.LocationEditOutcome.Rejected,"completed repeat"):return
	await native("recognition_unchanged")
	write_json("recognition-evidence.json",{"before":setup.before,"after":effects.after,"no_request_ui_changed":control.ui_changed,"apply_ui_changed":effects.ui_changed,"stale_checks":2,"invalid_targets":2,"ineligible_checks":2})
