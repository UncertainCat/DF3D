extends RefCounted
# Published terrain batches own the GPU buffers. Source inspection uses the
# retained CPU surfaces after those buffers have been retired.
static func retired(mesh) -> bool:
 return mesh.get_meta("df3d_source_surfaces_retired",false)
static func count(mesh) -> int:
 return mesh.get_meta("df3d_batch_arrays",[]).size() if retired(mesh) else mesh.get_surface_count()
static func arrays(mesh,index: int) -> Array:
 return mesh.get_meta("df3d_batch_arrays")[index] if retired(mesh) else mesh.surface_get_arrays(index)
static func material(mesh,index: int) -> Material:
 return mesh.get_meta("df3d_source_materials")[index] if retired(mesh) else mesh.surface_get_material(index)
static func bounds(mesh) -> AABB:
 return mesh.get_meta("df3d_source_aabb",mesh.get_aabb()) if retired(mesh) else mesh.get_aabb()
