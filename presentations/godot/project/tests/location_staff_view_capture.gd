extends SceneTree
func _initialize() -> void:call_deferred("run")
func numbers(value):
 if typeof(value)==TYPE_FLOAT:return int(value)
 if value is Dictionary:
  for key in value:value[key]=numbers(value[key])
 elif value is Array:
  for i in value.size():value[i]=numbers(value[i])
 return value
func run() -> void:
 if DisplayServer.get_name()=="headless":quit(77);return
 root.size=Vector2i(1200,800)
 var world:=Df3dWorld.new();root.add_child(world)
 if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
 var view=preload("res://scripts/location_staff_view.gd").new();root.add_child(view);view.configure(world);view.layout(Vector2(1200,800))
 var font:=Image.load_from_file(world.ui_font_path())
 var mapping: Dictionary={}
 for item in [[127235,"LOCATION_OCCUPATION_REMOVE_WORKER",4,16],[127179,"LOCATION_ASSIGN_OCCUPATION",4,16],[119723,"BUTTON_RECTANGLE_DARK",3,64],[136343,"LOCATION_OCCUPATION_TAVERN_KEEPER",4,36],[136347,"LOCATION_OCCUPATION_PERFORMER",4,36],[136435,"LOCATION_OCCUPATION_SCHOLAR",4,36],[136439,"LOCATION_OCCUPATION_SCRIBE",4,36],[136447,"LOCATION_OCCUPATION_DOCTOR",4,36],[136451,"LOCATION_POSITION_TEMPLE",4,36]]:
  var texture: Image=world.ui_texture(item[1]).get_image()
  for y in 3:
   for x in item[2]:mapping[item[0]+y*item[3]+x]={"image":texture,"origin":Vector2i(x*8,y*12)}
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_render.json"))
 var actions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_actions.json"))
 data.cases.append_array(actions.cases)
 var directory:=ProjectSettings.globalize_path("res://../../../build/qa/location-staff-render");DirAccess.make_dir_recursive_absolute(directory)
 var index:=0
 for sample in data.cases:
  view.display(numbers(sample.details.duplicate(true)),int(sample.scroll))
  for i in 2:await process_frame;await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image()
  for cell in sample.cells:
   var tile:=int(cell.tile);var ch:=int(cell.ch)
   if not mapping.has(tile):push_error("Unmapped staff art "+str(cell));quit(1);return
   var source: Image=mapping[tile].image;var origin: Vector2i=mapping[tile].origin
   for y in 12:
    for x in 8:
     var expected:=source.get_pixel(origin.x+x,origin.y+y)
     if ch not in [0,32]:
      var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
      if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
      expected=Color.WHITE
     if expected.a<0.99:continue
     var actual:=image.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
     if absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)>0.035:push_error("Native staff render mismatch "+str(cell)+" pixel "+str(Vector2i(x,y)));quit(1);return
  image.save_png(directory.path_join("staff_%02d.png"%index));index+=1
 view.display({})
 if not view.rows.is_empty() or not view.geometry.is_empty():push_error("Staff close retained facts");quit(1);return
 view.queue_free();world.queue_free();await process_frame
 print("LOCATION_STAFF_VIEW_CAPTURE_PASS");quit(0)
