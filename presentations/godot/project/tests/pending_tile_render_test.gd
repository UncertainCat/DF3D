extends "res://tests/farm_road_render_test.gd"
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/pending-tile.df3dfix")
 check(world.load_fixture(fixture),"pending tile fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(7,24,7);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../build/pending-tile-pixels.json"))
 for i in refs.size():
  await settle(i);check_case(refs[i],i)
  if i%100==0:print("PENDING_TILE_CASE ",i)
 await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/pending-tile-render.png"))
 for i in [0,refs.size()-1,1]:
  check(world.load_fixture(fixture),"pending tile reload")
  await settle(i);check_case(refs[i],i)
 world.free();camera.free();await process_frame
 print("PENDING_TILE_RENDER_PASS" if failures.is_empty() else "PENDING_TILE_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
