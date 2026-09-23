extends RefCounted
# Conservative camera-frustum intersection with the selected world-height slab.
# This selects preparation work; Godot still performs final instance culling.
const EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]

static func slab_bounds(corners: PackedVector3Array, low: float, high: float, margin: float) -> Rect2i:
	var points: Array[Vector3] = []
	for p in corners:
		if p.y >= low and p.y <= high: points.append(p)
	for edge in EDGES:
		var a := corners[edge[0]]
		var b := corners[edge[1]]
		if absf(b.y-a.y) < 0.000001: continue
		for height in [low,high]:
			var t: float = (height-a.y)/(b.y-a.y)
			if t >= 0.0 and t <= 1.0: points.append(a.lerp(b,t))
	if points.is_empty():
		# A small remote region represents an empty intersection; an empty Rect
		# is reserved by the native API for disabling demand selection.
		return Rect2i(-1048576,-1048576,1,1)
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for p in points:
		minimum = minimum.min(Vector2(p.x,p.z))
		maximum = maximum.max(Vector2(p.x,p.z))
	# Snap outward to block boundaries: small camera motion preserves demand.
	var first := Vector2i(floori((minimum.x-margin)/16.0)*16,floori((minimum.y-margin)/16.0)*16)
	var end := Vector2i(ceili((maximum.x+margin)/16.0)*16,ceili((maximum.y+margin)/16.0)*16)
	return Rect2i(first,end-first)

static func region(camera: Camera3D, top: int, depth: int, artwork_margin: int) -> Rect2i:
	var size := camera.get_viewport().get_visible_rect().size
	var corners := PackedVector3Array()
	for distance in [camera.near,camera.far]:
		for point in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
			corners.append(camera.project_position(point,distance))
	# Include upright artwork above the slab, nearby effect/shadow contributors,
	# and a block of prefetch. Camera demand never determines pile membership.
	return slab_bounds(corners,float(top-depth),float(top+1+artwork_margin),float(artwork_margin+16+depth*2))
