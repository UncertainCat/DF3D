extends SceneTree
const Deaths = preload("res://scripts/actor_death_visuals.gd")
func _initialize():
	var deaths = Deaths.new()
	deaths.reset(1)
	var owner := Node3D.new()
	root.add_child(owner)
	var source := MultiMeshInstance3D.new()
	source.multimesh = MultiMesh.new()
	source.multimesh.mesh = BoxMesh.new()
	owner.add_child(source)
	deaths.remember(7, source, Transform3D.IDENTITY, Color(20, 13, 0, 0))
	deaths.update(owner, PackedInt64Array(), 1.0)
	assert(deaths.active.is_empty()) # Culling/removal is not death.
	assert(deaths.corpse_handoff([{"item_id":70,"unit_id":7},{"item_id":90,"unit_id":99}], 1.0) == PackedInt64Array([70]))
	deaths.observe([{"id":1,"kind":2,"victim_id":7}], 1.1)
	deaths.update(owner, PackedInt64Array([7]), 1.1)
	assert(deaths.active.is_empty()) # Native live instance must disappear first.
	deaths.update(owner, PackedInt64Array(), 1.2)
	assert(deaths.active.size() == 1 and deaths.rendered_deaths == 1)
	assert(deaths.corpse_handoff([], 1.2) == PackedInt64Array([70]))
	assert(deaths.active[7].node.multimesh.mesh == source.multimesh.mesh)
	deaths.observe([{"id":1,"kind":2,"victim_id":7}], 1.3)
	deaths.update(owner, PackedInt64Array(), 1.3)
	assert(deaths.rendered_deaths == 1)
	deaths.expire(1.3) # Pause uses unchanged animation time.
	assert(deaths.active.size() == 1)
	assert(deaths.corpse_handoff([], 1.3) == PackedInt64Array([70])) # Paused stays hidden.
	deaths.expire(3.0)
	assert(deaths.corpse_handoff([], 3.0).is_empty())
	assert(deaths.corpse_handoff([{"item_id":71,"unit_id":7}], 3.1).is_empty())
	assert(deaths.active.is_empty())
	deaths.observe([{"id":2,"kind":2,"victim_id":99}], 3.0)
	deaths.update(owner, PackedInt64Array(), 5.1)
	assert(deaths.active.is_empty() and deaths.pending.is_empty())
	deaths.reset(2)
	assert(deaths.cursor == 0 and deaths.appearances.is_empty())
	deaths.observe([{"id":3,"kind":2,"victim_id":7}], 5.2, false)
	assert(deaths.cursor == 3 and deaths.pending.is_empty()) # Strength Off skips retention.
	deaths.remember(8, source, Transform3D.IDENTITY, Color.WHITE)
	assert(deaths.corpse_handoff([{"item_id":80,"unit_id":8}], 6.0).size() == 1)
	assert(deaths.corpse_handoff([], 8.1).is_empty()) # Missing event cannot hide forever.
	assert(deaths.corpse_handoff([{"item_id":81,"unit_id":8}], 9.0).size() == 1)
	assert(deaths.corpse_handoff([], 9.0, false).is_empty())
	deaths.corpse_handoff([{"item_id":82,"unit_id":8}], 10.0)
	deaths.set_view_scope([1])
	assert(deaths.corpse_handoff([], 10.0).is_empty())
	# The last prepared appearance can predate GPU movement. Freeze at removal's
	# render tick while retaining floor/stack lift, including vertical movement.
	var span := {"from":Color(2.5,4.0,3.5,4092), "to":Color(3.5,6.0,4.5,4), "epochs":Vector2(2,3), "tick":12284.0}
	var stack_lift := Vector3(0,.37,0)
	deaths.remember(9,source,Transform3D.IDENTITY,Color(20,1,0,0),Vector2.ONE,.08,
		Vector3(2.5,4.0,3.5)+stack_lift,Color(2.0,.1,20,7),span)
	span.to = Color(100,100,100,4) # The retained span owns its endpoint values.
	deaths.observe([{"id":4,"kind":2,"victim_id":9}],11.0)
	deaths.update(owner,PackedInt64Array(),11.0,null,12288.0)
	var frozen: MultiMesh = deaths.active[9].node.multimesh
	assert(frozen.get_instance_transform(0).origin.is_equal_approx(Vector3(3.0,5.0,4.0)+stack_lift))
	assert(frozen.get_instance_color(0).a == 0.0) # Reused slots cannot move a corpse.
	assert(is_equal_approx(frozen.get_instance_color(0).r,2.0))
	deaths.update(owner,PackedInt64Array(),11.1,null,12292.0)
	assert(frozen.get_instance_transform(0).origin.is_equal_approx(Vector3(3.0,5.0,4.0)+stack_lift)) # Freeze once.
	var hold := {"from":Color(7,8,9,12),"to":Color(70,80,90,12),"epochs":Vector2(3,3),"tick":12300.0}
	assert(Deaths._motion_position(hold,13000.0) == Vector3(7,8,9))
	assert(Deaths._motion_position(deaths.appearances[9].motion,12000.0) == Vector3(2.5,4.0,3.5))
	assert(Deaths._motion_position(deaths.appearances[9].motion,13000.0) == Vector3(3.5,6.0,4.5))
	deaths.remember(10,source,Transform3D.IDENTITY,Color(20,1,0,0),Vector2.ONE,.08,
		Vector3(7,8,9)+stack_lift,Color(1,0,20,0),hold)
	deaths.observe([{"id":5,"kind":2,"victim_id":10,"tick":12500,"position":Vector3i(30,40,5)}],11.2)
	deaths.update(owner,PackedInt64Array(),11.2,null,12500.0)
	assert(deaths.active[10].node.multimesh.get_instance_transform(0).origin.is_equal_approx(Vector3(30.5,5,40.5)+stack_lift))
	deaths.set_view_scope([1,5,2,false]) # Floors 4 and 5 remain visible.
	for id in [11,12,13,14]:
		var previous_floor := 5 if id in [11,14] else 4
		deaths.remember(id,source,Transform3D(Basis.IDENTITY,Vector3(2.5,previous_floor+.1,2.5)),Color.WHITE)
	deaths.corpse_handoff([{"item_id":110,"unit_id":11}],12.0)
	deaths.observe([
		{"id":6,"kind":2,"victim_id":11,"position":Vector3i(2,2,6)},
		{"id":7,"kind":2,"victim_id":12,"position":Vector3i(2,2,3)},
		{"id":8,"kind":2,"victim_id":13,"position":Vector3i(2,2,4)},
		{"id":9,"kind":2,"victim_id":14,"position":Vector3i(2,2,5)}],12.0)
	deaths.update(owner,PackedInt64Array(),12.0)
	assert(not deaths.active.has(11) and not deaths.active.has(12))
	assert(deaths.active.has(13) and deaths.active.has(14))
	assert(deaths.pending.is_empty() and not deaths.appearances.has(11))
	assert(deaths.corpse_handoff([],12.0).is_empty()) # Rejection releases the corpse too.
	var bookkeeping = Deaths.new()
	bookkeeping.reset(3)
	var members := PackedInt64Array([20,21])
	bookkeeping.update(owner,members,0.0)
	for id in members: bookkeeping.remember(id,source,Transform3D.IDENTITY,Color.WHITE)
	for frame in 50: bookkeeping.update(owner,members,float(frame)*.01)
	assert(bookkeeping.membership_reconciliations == 1)
	assert(bookkeeping.missing_expiry_checks == 0) # Source changes do not scan live appearances.
	bookkeeping.update(owner,PackedInt64Array([20]),1.0)
	bookkeeping.expire(2.0)
	assert(bookkeeping.appearances.has(21))
	bookkeeping.update(owner,members,2.1) # Reappearing cancels the missing expiry.
	bookkeeping.expire(4.0)
	assert(bookkeeping.appearances.has(21))
	bookkeeping.update(owner,PackedInt64Array([20]),5.0)
	bookkeeping.expire(7.01) # Clock-only cleanup needs no later source delta.
	assert(not bookkeeping.appearances.has(21) and bookkeeping.appearances.has(20))
	bookkeeping.remember(22,source,Transform3D.IDENTITY,Color.WHITE)
	bookkeeping.expire(8.0)
	bookkeeping.expire(10.01)
	assert(not bookkeeping.appearances.has(22)) # Isolated callers may remember before membership.
	bookkeeping.set_view_scope([3,5,2,false])
	bookkeeping.remember(20,source,Transform3D.IDENTITY,Color.WHITE)
	bookkeeping.expire(100.0)
	assert(bookkeeping.appearances.has(20)) # View changes preserve known live membership.
	bookkeeping.reset(4)
	assert(bookkeeping.appearances.is_empty() and bookkeeping._member_ids.is_empty() and bookkeeping._missing_until.is_empty())
	print("ACTOR_DEATH_VISUALS_PASS")
	quit()
