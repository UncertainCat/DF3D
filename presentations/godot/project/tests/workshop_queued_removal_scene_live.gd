extends "res://tests/workshop_header_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("workshop")
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	var reference: Dictionary=expected.header_reference.queued
	var before: Array=owner.tasks.jobs()
	if not check(before.size()==2,"Queued production fixture missing"):return
	for i in 2:check(before[i].id==int(reference.viewer_before_ids[i]),"Initial queued identity differs")
	check(before[0].worker_id==int(reference.worker_id) and before[0].active,"Assigned production worker missing")
	await pointer(Vector2(832,82))
	if not await workshop_ready():return
	check(owner.state.snapshot.removing and not owner.panel.tasks.visible,"Remove retained editable production queue")
	await capture_header("queued-remove")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await workshop_ready():return
	check(not owner.state.snapshot.removing and owner.tasks.jobs().is_empty(),"Cancel removal revived discarded jobs")
	await capture_header("queued-cancel")
	owner.close_panel();await drain();await process_frame
	check(scene._ui.host.active==null,"Workshop input owner remained active")
	exercised=true
