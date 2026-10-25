extends "res://tests/layout_stage_render_test.gd"
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/trap.df3dfix")
 check(world.load_fixture(fixture),"trap fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(5,24,5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=7;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../build/trap-pixels.json"))
 for i in refs.size():
  await settle(i)
  var node=world.get_building_root().get_node_or_null("level_0/building_100")
  check((node!=null)==not refs[i].hashes.is_empty(),"trap visible exactly when native art exists "+str(i))
  if node!=null:
   var got=pixels(node);check(got==refs[i].hashes,"native trap pixels "+str(i)+" state "+str(refs[i].state)+" got "+str(got))
  if i%100==0:print("TRAP_CASE ",i)
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/trap-render.png"))
 for i in [0,refs.size()-1,1]:
  # FixtureReplay consumes forward only; a new source is required to revisit an earlier state.
  check(world.load_fixture(fixture),"trap reload")
  await settle(i)
  var node=world.get_building_root().get_node_or_null("level_0/building_100")
  check((node!=null)==not refs[i].hashes.is_empty(),"trap restored visibility")
  if node!=null:check(pixels(node)==refs[i].hashes,"trap reload pixels "+str(i))
 world.free();camera.free();await process_frame
 print("TRAP_RENDER_PASS" if failures.is_empty() else "TRAP_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
