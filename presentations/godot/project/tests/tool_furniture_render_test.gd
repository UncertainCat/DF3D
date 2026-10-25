extends "res://tests/bars_render_test.gd"
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(9,24,9);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);var initial=await FrameOracle.shot(self)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json"))
 var offset=6+refs.completed_opening_native_reference.rgba_sha256.size()+refs.completed_furniture_native_reference.rgba_sha256.size()+refs.planned_equipment_furniture.rgba_sha256.size()+refs.completed_chain_native_reference.rgba_sha256.size()+refs.completed_ordinary_native_reference.rgba_sha256.size()
 var tool_refs=refs.tool_furniture_native_reference.rgba_sha256
 for i in tool_refs.size():
  await settle(offset+i);inspect_opening(tool_refs[i])
 var bed_refs=refs.completed_bed_component_reference.rgba_sha256
 for i in bed_refs.size():
  await settle(offset+tool_refs.size()+i);inspect_opening(bed_refs[i])
 await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/tool-furniture.png"))
 check(world.load_fixture(fixture),"tool reload");await settle(0);check(initial==await FrameOracle.shot(self),"tool furniture state survived reload")
 world.free();camera.free();await process_frame
 print("TOOL_FURNITURE_PASS" if failures.is_empty() else "TOOL_FURNITURE_FAIL");quit(0 if failures.is_empty() else 1)
