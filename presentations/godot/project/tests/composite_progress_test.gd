extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var world := Df3dWorld.new();root.add_child(world)
 assert(world.load_assets(OS.get_environment("DF3D_DF_PATH")))
 assert(world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")))
 world.set_fixed_render_tick(1000)
 world.set_composite_budget_ms(0.000001)
 world.poll();world.set_top_z(127);world.set_window_depth(24)
 var finished=false
 for step in 1000:
  var before=world.composite_build_count()
  world.poll()
  if world.composite_pending_count()==0 and world.item_composite_pending_count()==0:
   finished=true;break
  assert(world.composite_build_count()>before,"Deferred art must make progress despite tiny budget")
 assert(finished and world.composite_build_count()>0)
 # Semantic evaluation may advance fractionally without resolving unchanged art.
 var stats=world.presentation_perf_stats()
 var slots=world.unit_sprite_slots()
 var regions=world.unit_sprite_regions()
 var scales=world.unit_scale_params()
 var count=world.unit_ids().size()
 for step in range(1,9):
  world.set_fixed_render_tick(1000.0+step*0.125)
  world.poll()
  assert(world.unit_sprite_slots()==slots and world.unit_sprite_regions()==regions and world.unit_scale_params()==scales)
 var warm=world.presentation_perf_stats()
 assert(warm.unit_art_misses==stats.unit_art_misses,"Fractional evaluation must not resolve unchanged unit art")
 assert(warm.unit_art_hits==stats.unit_art_hits+count,"Only the crossed integer boundary prepares units; fractional clocks reuse resident intervals")
 world.queue_free();await process_frame
 print("COMPOSITE_PROGRESS_PASS")
 quit()
