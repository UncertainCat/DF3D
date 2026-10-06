extends "res://tests/frame_profile.gd"
# Full licensed fixture scene: cache must preserve actual MultiMesh payloads.
var failures: Array=[]
func check(value: bool, message: String):
 if not value: failures.append(message); push_error(message)
func payloads() -> Array:
 # Compare an exact multiset of per-piece payloads, independent of batch/node
 # identity and member order. Includes texture identity, transforms and custom
 # data (ceiling clip); duplicates remain represented, preserving stack pieces.
 var out: Array=[]
 for entry in [[scene._sprite_layers,"unit"],[scene._item_layers,"item"],
   [{"marker":scene.units},"unit_marker"],[{"marker":scene.item_markers},"item_marker"]]:
  for node in entry[0].values():
   var mm: MultiMesh=node.multimesh
   if scene.ItemCapacity.visible_count(mm)==0: continue
   var stride:=12+(4 if mm.use_custom_data else 0)+(4 if mm.use_colors else 0)
   var buffer:=mm.buffer
   var resource_key:=str(mm.mesh.get_instance_id())
   for i in scene.ItemCapacity.visible_count(mm):
    out.append(entry[1]+":"+resource_key+":"+buffer.slice(i*stride,(i+1)*stride).to_byte_array().hex_encode())
 out.sort()
 return out

func validate_cells():
 var positions=scene.world.item_positions()
 var meshes={}
 var materials={}
 for group in scene.world.item_render_groups():
  if group.slot<0: continue
  var members: Dictionary={}
  for index in group.indices:
   check(not members.has(index),"cell partition has unique source indices")
   members[index]=true
   check(group.cell==scene._sprite_cell(positions[index]),"native and presentation use identical cell boundaries")
 for cache in [scene._sprite_layers,scene._item_layers]:
  for key in cache:
   var node=cache[key]
   var resource_key=key.get_slice(":",0)+":"+key.get_slice(":",1)
   if meshes.has(resource_key):
    check(meshes[resource_key]==node.multimesh.mesh,"contour meshes are shared across cells")
    check(materials[resource_key]==node.material_override,"materials are shared across cells")
   meshes[resource_key]=node.multimesh.mesh
   materials[resource_key]=node.material_override
func force_upload():
 scene._unit_revision_seen=-1
 scene._item_preparation.source_revision=-1
 scene._update_units()
 scene._update_items()
func run():
 preload("res://tests/recorded_fixture.gd").configure_scene()
 scene=load("res://scenes/main.tscn").instantiate()
 root.add_child(scene)
 # This oracle compares the complete source population across different cell
 # partitions. Demand/culling is tested separately; include offscreen payloads.
 scene._unit_demand.enabled=false
 var deadline=Time.get_ticks_msec()+90000
 while not ready_scene() and Time.get_ticks_msec()<deadline: await process_frame
 if not ready_scene(): push_error("Fixture scene not ready"); quit(1); return
 var seen={}
 var slots=scene.world.item_sprite_slots()
 var regions=scene.world.item_sprite_regions()
 for group in scene.world.item_render_groups():
  for index in group.indices:
   check(not seen.has(index),"native groups never duplicate an item")
   seen[index]=true
   check(slots[index]==group.slot,"native group keeps source texture slot")
   if group.slot>=0: check(regions[index]==group.region,"native group keeps exact source rectangle")
 check(seen.size()==scene.world.item_positions().size() and seen.size()>100,"native groups cover full real item set")
 for mode in ["free","billboard","df"]:
  scene.camera_rig.set_df_mode(mode=="df")
  scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
  for i in 15: await process_frame
  scene._instance_uploads.enabled=false
  force_upload()
  var original=payloads()
  scene._instance_uploads.enabled=true
  force_upload()
  check(original==payloads(),mode+" cached upload equals original complete buffers")
  var before: Dictionary=scene._instance_uploads.stats()
  var partitions_before: int=scene._unit_partitions.rebuilds
  var item_misses_before: int=scene._item_preparation.misses
  var item_hits_before: int=scene._item_preparation.hits
  var item_groups_before: int=scene._item_delta_groups
  force_upload()
  var after: Dictionary=scene._instance_uploads.stats()
  check(scene._unit_partitions.rebuilds==partitions_before,mode+" repeated source payload reuses unit partition")
  check(scene._item_preparation.misses==item_misses_before,mode+" unchanged items skip layer and engine setup")
  check(original==payloads(),mode+" repeated cached frame preserves complete buffers")
  check(after.transforms_written==before.transforms_written and after.custom_written==before.custom_written and after.colors_written==before.colors_written,mode+" stationary frame writes no instance payload")
  check(scene._item_delta_groups==item_groups_before and scene._item_preparation.hits==item_hits_before,mode+" current delta cursor skips all group preparation")
  # Recovery can request a complete manifest while prepared payloads remain
  # current. Every group should hit its cache without rewriting GPU payloads.
  var live_groups: int=scene.world.item_render_groups().size()
  scene._item_preparation.delta_revision=-1
  force_upload()
  after=scene._instance_uploads.stats()
  check(live_groups>0 and scene._item_delta_groups==item_groups_before+live_groups,mode+" recovery visits every live group")
  check(scene._item_preparation.hits==item_hits_before+live_groups and scene._item_preparation.misses==item_misses_before,mode+" full manifest reuses each current prepared group")
  check(after.transforms_written==before.transforms_written and after.custom_written==before.custom_written and after.colors_written==before.colors_written,mode+" full manifest cache hits write no instance payload")
  check(original==payloads(),mode+" full manifest recovery preserves complete buffers")
  for config in [[false,16,1],[true,16,1],[true,32,4],[true,8,1],[true,16,1]]:
   scene.configure_sprite_batches(config[0],config[1],config[2])
   force_upload()
   check(original==payloads(),mode+" spatial regrouping preserves every exact instance payload "+str(config))
   validate_cells()
 # Exercise actual changing payloads, removals, ID reuse and visibility through
 # the scene consumer, then compare each sparse result to a forced full upload.
 for mode in ["free","billboard","df"]:
  scene.camera_rig.set_df_mode(mode=="df")
  scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
  scene.world.set_replay_speed(0)
  scene.world.set_fixed_render_tick(-1)
  check(scene.world.load_fixture(ProjectSettings.globalize_path("res://../../../build/item-updates.df3dfix")),"dynamic fixture loads")
  scene.world.poll()
  scene.world.set_top_z(2)
  scene.world.set_window_depth(2)
  scene.world.set_presentation_region(Rect2i())
  for frame in 10:
   scene.world.set_replay_elapsed(frame*10.0+5.0)
   scene.world.poll()
   check(scene.world.item_positions().size()==[7,7,6,8,8,8,8,8,6,8][frame],"dynamic scene has expected item pieces: "+mode+" frame="+str(frame)+" actual="+str(scene.world.item_positions().size()))
   force_upload()
   var incremental=payloads()
   scene._instance_uploads.enabled=false
   force_upload()
   check(incremental==payloads(),mode+" dynamic delta equals full buffers at frame "+str(frame))
   scene._instance_uploads.enabled=true
   force_upload()
 root.remove_child(scene)
 scene.free()
 scene=null
 await process_frame
 print("INSTANCE_UPLOAD_SCENE_PASS" if failures.is_empty() else "INSTANCE_UPLOAD_SCENE_FAIL")
 quit(0 if failures.is_empty() else 1)
