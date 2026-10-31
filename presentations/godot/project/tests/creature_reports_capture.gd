extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(77);return
 root.size=Vector2i(1200,800)
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
 var state=preload("res://scripts/reports_state.gd").new();state.open_creature_history(1017)
 var rows:Array=[]
 for i in 22:rows.append({"id":i,"text":"Synthetic unit combat history row "+str(i+1),"color":3,"bright":true,"position_visible":true,"position":Vector3i(1,1,1)})
 state.accept(state.generation,0,{"view":3,"unit_id":1017,"unit_category":0,"list_revision":1,"reports":rows,"total":22})
 state.pause_on_new=true
 var view=preload("res://scripts/reports_view.gd").new();root.add_child(view);view.configure(world,state,world.assets_root())
 for i in 3:await process_frame;await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
 var directory:=ProjectSettings.globalize_path("res://../../../build/qa/creature-reports-images")
 DirAccess.make_dir_recursive_absolute(directory);image.save_png(directory+"/populated.png")
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
 for sample in fixture.chest_header_reference.unit_reports_populated_reference.rgb_regions:
  var r:Array=sample.rect
  var region:=Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))
  var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(region).get_data())
  if hash.finish().hex_encode()!=sample.sha256:
   push_error("Direct Combat log native pixels differ: "+str(region));quit(1);return
 for sample in fixture.chest_header_reference.unit_reports_resize_reference.cases:
  root.size=Vector2i(int(sample.viewport[0]),int(sample.viewport[1]))
  for i in 3:await process_frame;await RenderingServer.frame_post_draw
  image=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
  image.save_png(directory+"/resize-"+sample.label+".png")
  assert(state.log_requested==int(sample.first) and state.visible_log_rows()==int(sample.visible))
  var r:Array=sample.region
  var region:=Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))
  var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(region).get_data())
  if hash.finish().hex_encode()!=sample.rgb_sha256:
   push_error("Direct Combat resize pixels differ: "+sample.label);quit(1);return
 var top:Dictionary=fixture.chest_header_reference.unit_reports_resize_reference.wide_top
 root.size=Vector2i(1600,900)
 for i in 2:await process_frame
 state.scroll_to(0)
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 image=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
 image.save_png(directory+"/wide-top.png")
 assert(state.log_requested==0 and state.visible_log_rows()==18)
 for sample in top.rgb_regions:
  var r:Array=sample.rect
  var top_hash:=HashingContext.new();top_hash.start(HashingContext.HASH_SHA256)
  top_hash.update(image.get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))).get_data())
  if top_hash.finish().hex_encode()!=sample.sha256:
   push_error("Wide Combat top-page pixels differ");quit(1);return
 view.queue_free();world.queue_free();await process_frame
 print("CREATURE_REPORTS_CAPTURE_PASS");quit(0)
