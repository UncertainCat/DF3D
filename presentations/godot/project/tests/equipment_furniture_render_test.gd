extends "res://tests/bars_render_test.gd"
func run():
 root.size=Vector2i(768,768);world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 var fixture=ProjectSettings.globalize_path("res://../../../build/bars.df3dfix");check(world.load_fixture(fixture),"fixture loads")
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(9,24,9);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.current=true
 await settle(0);world.set_top_z(0);world.set_window_depth(1);var initial=await FrameOracle.shot(self)
 var refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json"))
 var opening_refs=refs.completed_opening_native_reference.rgba_sha256
 var furniture_refs=refs.completed_furniture_native_reference.rgba_sha256
 var equipment_refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json")).planned_equipment_furniture.rgba_sha256
 for i in equipment_refs.size():
  await settle(6+opening_refs.size()+furniture_refs.size()+i);inspect_opening(equipment_refs[i])
 var chain_refs=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bars_rendering.json")).completed_chain_native_reference.rgba_sha256
 for i in chain_refs.size():
  await settle(6+opening_refs.size()+furniture_refs.size()+equipment_refs.size()+i);inspect_opening(chain_refs[i])
 var ordinary_refs=refs.completed_ordinary_native_reference.rgba_sha256
 for i in ordinary_refs.size():
  await settle(6+opening_refs.size()+furniture_refs.size()+equipment_refs.size()+chain_refs.size()+i);inspect_opening(ordinary_refs[i])
 await FrameOracle.shot(self)
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/equipment-furniture.png"))
 check(world.load_fixture(fixture),"equipment reload");await settle(0);check(initial==await FrameOracle.shot(self),"equipment or restraint state survived reload")
 world.free();camera.free();await process_frame
 print("EQUIPMENT_FURNITURE_PASS" if failures.is_empty() else "EQUIPMENT_FURNITURE_FAIL");quit(0 if failures.is_empty() else 1)
