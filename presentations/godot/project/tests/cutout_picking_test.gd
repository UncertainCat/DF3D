extends "res://tests/interaction_test.gd"
const Picking = preload("res://scripts/cutout_picking.gd")
class UnitWorld extends FakeWorld:
	var unit_bottom := Vector3(2.5,5.7,3.5)
	var owner_tile := Vector3i(2,3,5)
	func unit_cutout_positions(): return PackedVector3Array([unit_bottom])
	func unit_thicknesses(): return PackedFloat32Array([0.8])
	func unit_sprite_sizes(): return PackedVector2Array([Vector2.ONE])
	func unit_sprite_slots(): return PackedInt32Array([-1])
	func unit_sprite_regions(): return PackedColorArray([Color(0,0,1,1)])
	func unit_ids(): return PackedInt64Array([201])
	func unit_tile(_id): return owner_tile
func run():
	root.size=Vector2i(1200,792)
	var camera := Camera3D.new();root.add_child(camera)
	camera.position=Vector3(8,9,12)
	camera.look_at(Vector3(2.5,6.1,3.5))
	camera.current=true
	await process_frame
	# Foot height stays fixed through the centered-to-upright pitch transition.
	var geometry = preload("res://scripts/sprite_geometry.gd")
	var saved_basis := camera.basis
	for pitch in [0.0, -0.4, -0.8, -1.2, -PI/2.0]:
		camera.rotation = Vector3(pitch, 0, 0)
		for height in [0.5, 1.0, 3.0]:
			var anchored = geometry.billboard_transform(camera, Vector2(1,height), 0.12, Vector3(0,5,0))
			check(absf((anchored * Vector3(0,0,0.5)).y-5.0)<0.0001, "Billboard feet remain above their floor at every pitch/scale")
		camera.basis = saved_basis
	var w := UnitWorld.new()
	var point := camera.unproject_position(w.unit_bottom+Vector3.UP*0.4)
	var hits := Picking.pieces(w,camera,point,5)
	var best := Picking.nearest(hits)
	check(not best.is_empty() and best.kind==1 and best.id==201 and best.tile==w.owner_tile,"oblique visible unit hits its authoritative tile before floor")
	var floor_tile := Selection.project_tile(camera.project_ray_origin(point),camera.project_ray_normal(point),5,w.map_size(),Df3dWorld.floor_height())
	check(floor_tile!=w.owner_tile,"oblique regression ray would select an adjacent floor tile")
	if not best.is_empty():
		var front := {"kind":3,"id":9,"tile":Vector3i(3,3,5),"depth":best.depth*0.5}
		check(Picking.nearest(hits+[front]).kind==3,"nearer furniture wins over raised unit")
		front.kind=2
		check(Picking.nearest(hits+[front]).kind==2,"nearer item wins over raised unit")
	w.owner_tile=Vector3i(2,3,2)
	best=Picking.nearest(Picking.pieces(w,camera,point,2))
	check(not best.is_empty() and best.tile.z==2,"rendered height never replaces authoritative level during vertical movement")
	check(Picking.nearest(Picking.pieces(w,camera,point,5)).get("kind",0)!=1,"unit on another authoritative level is not selectable")
	w.cutout=true
	var mesh: ArrayMesh=w.sprite_cutout_mesh(0,Color(0,0,1,1))
	check(Picking.mesh_depth(mesh,Transform3D.IDENTITY,Vector3(0,2,0),Vector3.DOWN)==INF,"transparent contour hole misses")
	check(Picking.mesh_depth(mesh,Transform3D.IDENTITY,Vector3(0.4,2,0),Vector3.DOWN)<INF,"opaque contour arm hits")
	var slope := Basis.IDENTITY
	slope.x.y = .9
	var ray := Vector3(.4,2,0)
	var flat_depth := sqrt(Picking.mesh_depth(mesh,Transform3D.IDENTITY,ray,Vector3.DOWN))
	var slope_depth := sqrt(Picking.mesh_depth(mesh,Transform3D(slope,Vector3(0,.45,0)),ray,Vector3.DOWN))
	check(is_equal_approx(flat_depth-slope_depth,.45+.9*.4),"ramp picking hits raised sloping contour, not the old floor")
	camera.queue_free()
	await process_frame
	print("CUTOUT_PICKING_PASS" if failures==0 else "CUTOUT_PICKING_FAIL")
	quit(0 if failures==0 else 1)
