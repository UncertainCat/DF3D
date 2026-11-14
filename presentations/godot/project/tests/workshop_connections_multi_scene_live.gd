extends "res://tests/workshop_connections_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("workshop")
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	await pointer(Vector2(768,82))
	if not await connections_ready():return
	var reference: Array=expected.connections_reference.multiple.rows
	check(owner.connections.rows.size()==reference.size(),"Multiple link count differs")
	for index in mini(reference.size(),owner.connections.rows.size()):
		for field in ["id","direction","name"]:check(owner.connections.rows[index][field]==reference[index][field],"Multiple link ordering/caption differs")
	await connection_capture("multiple-top","multiple-top",420)
	await pointer(Vector2(368,452))
	await connection_capture("multiple-arrow","multiple-arrow",420)
	check(owner.connections_view.scrollbar.first==1,"Down arrow did not move one row")
	for i in 20:await pointer(Vector2(368,452))
	await connection_capture("multiple-bottom","multiple-bottom",420)
	check(owner.connections_view.scrollbar.first==3,"Scrollbar did not stop at last page")
	# Returning to the top must retain ordering and release dragging on closure.
	for i in 20:await pointer(Vector2(368,140))
	check(owner.connections_view.scrollbar.first==0,"Up arrow did not restore top")
	owner.close_panel();await drain();await process_frame
	check(not owner.connections_view.visible and not owner.connections_view.scrollbar.dragging,"Closing retained multirow input")
	exercised=true
