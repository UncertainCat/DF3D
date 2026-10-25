extends "res://tests/layout_stage_render_test.gd"
func run():
 root.size=Vector2i(512,512);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(10.5,24,10);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1)
 var rows=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/quern_rendering.json")).rows
 var previous=null
 for i in rows.size():
  await settle(495+i)
  var node=world.get_building_root().get_node_or_null("level_0/building_232");check(node!=null,"quern exists")
  if node==null:continue
  check(node.mesh!=previous,"quern stage/material refresh");previous=node.mesh
  var got=pixels(node);check(got==rows[i].hashes,"native quern pixels "+str(i)+" "+str(got))
 await settle(503);await FrameOracle.shot(self);root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/quern-planned.png"))
 check(world.load_fixture(fixture),"reload");await settle(501)
 var restored=world.get_building_root().get_node_or_null("level_0/building_232");check(restored!=null,"restored quern")
 if restored!=null:check(pixels(restored)==rows[6].hashes,"planned glass quern after reload")
 world.free();camera.free();await process_frame
 print("QUERN_RENDER_PASS" if failures.is_empty() else "QUERN_RENDER_FAIL");quit(0 if failures.is_empty() else 1)
