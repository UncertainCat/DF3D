extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var world=Df3dWorld.new();root.add_child(world)
 assert(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/corpse-handoff.df3dfix")))
 world.set_replay_speed(0);world.poll();world.set_top_z(1);world.set_window_depth(1)
 for frame in 3: world.poll();await process_frame
 var changes=world.corpse_item_changes()
 assert(changes.size()==1 and changes[0].item_id==100 and changes[0].unit_id==77)
 assert(world.corpse_item_changes().is_empty())
 var before=world.item_ids();assert(before.size()==3)
 var positions=world.item_positions()
 var original=positions[before.find(100)]
 var original_thickness=world.item_thicknesses()[before.find(100)]
 var original_ordinal=world.item_stack_ordinals()[before.find(100)]
 world.set_hidden_corpses(PackedInt64Array([100,101,102]))
 assert(world.item_ids().size()==2 and not world.item_ids().has(100))
 assert(world.item_ids().has(101) and world.item_ids().has(102))
 var revision=world.item_render_revision()
 world.set_hidden_corpses(PackedInt64Array([100]))
 assert(world.item_render_revision()==revision)
 world.set_hidden_corpses(PackedInt64Array())
 assert(world.item_ids().size()==3)
 assert(world.item_positions()[world.item_ids().find(100)]==original)
 assert(world.item_thicknesses()[world.item_ids().find(100)]==original_thickness)
 assert(world.item_stack_ordinals()[world.item_ids().find(100)]==original_ordinal)
 # Repeated visual handoff must never move the semantic object within its stack.
 for cycle in 3:
  world.set_hidden_corpses(PackedInt64Array([100]))
  world.poll()
  world.set_hidden_corpses(PackedInt64Array())
  var index=world.item_ids().find(100)
  assert(world.item_positions()[index]==original)
  assert(world.item_thicknesses()[index]==original_thickness)
  assert(world.item_stack_ordinals()[index]==original_ordinal)
 world.queue_free()
 await process_frame
 print("CORPSE_HANDOFF_ADAPTER_PASS")
 quit()
