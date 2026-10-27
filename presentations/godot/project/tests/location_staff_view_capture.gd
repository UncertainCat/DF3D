extends SceneTree
const DetailsView=preload("res://scripts/location_details_view.gd")
class Receipts:
 extends RefCounted
 var values: Dictionary={}
 func receipt(row: Dictionary) -> Dictionary:return values.get(row.names.holder_id,{})
var removed: Array=[]
var specialized: Array=[]
func check_indicator_crops(image: Image, reference: Dictionary) -> void:
 for sample in reference.crops:
  var r: Array=sample.rect
  var crop:=image.get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])));crop.convert(Image.FORMAT_RGB8)
  var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
  assert(hash.finish().hex_encode()==sample.sha256,"native indicator crop "+sample.name)
func click(point: Vector2) -> void:
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await process_frame
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
 # Current supported-build RGB reference004035 resolves this older tile ID
 # to the standard background, not the darker reconstruction.
 var mapping: Dictionary={}
 for item in [[127235,"LOCATION_OCCUPATION_REMOVE_WORKER",4,16],[127179,"LOCATION_ASSIGN_OCCUPATION",4,16],[119723,"BUTTON_RECTANGLE",3,64],[136343,"LOCATION_OCCUPATION_TAVERN_KEEPER",4,36],[136347,"LOCATION_OCCUPATION_PERFORMER",4,36],[136435,"LOCATION_OCCUPATION_SCHOLAR",4,36],[136439,"LOCATION_OCCUPATION_SCRIBE",4,36],[136447,"LOCATION_OCCUPATION_DOCTOR",4,36],[136451,"LOCATION_POSITION_TEMPLE",4,36]]:
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
 var composition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_composition.json"))
 view.display(numbers(composition.cases[0].details.duplicate(true)));view.actions_enabled=true
 view.removal_requested.connect(func(id):removed.append(id))
 for dimensions in [Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]:
  root.size=dimensions;view.layout(Vector2(dimensions));await process_frame
  var before:=removed.size()
  # Native Temple0 second row is occupied ordinary performer87.
  var point:=Vector2(dimensions.x-256,((29-1)+3)*12+dimensions.y%12*0.5+18)
  await click(point);assert(removed.size()==before+1 and removed[-1]==87,"resized remove hitbox")
  if dimensions.x!=1200:
   await click(Vector2(944,point.y));assert(removed.size()==before+1,"old remove position inactive")
 var receipts=Receipts.new();view.specialization_reader=receipts
 receipts.values={5813:{"eligible":true,"specialized":true},6536:{"eligible":true,"specialized":false}}
 view.specialization_requested.connect(func(row,facts):specialized.append({"row":row,"facts":facts}))
 view.queue_redraw()
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join("specialization.png"))
 for point in [Vector2(784,358),Vector2(784,394)]:await click(point)
 assert(specialized.size()==2 and specialized[0].row.names.holder_id==5813 and specialized[0].facts.specialized and specialized[1].row.names.holder_id==6536 and not specialized[1].facts.specialized,"native specialization row hitboxes")
 view.actions_enabled=false;await click(Vector2(784,358));assert(specialized.size()==2,"disabled gesture")
 view.actions_enabled=true;receipts.values[5813].eligible=false;await click(Vector2(784,358));assert(specialized.size()==2,"native ineligibility prevents gesture")
 var assignment_receipts=Receipts.new();view.assignments_reader=assignment_receipts
 var assignments: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_details.json"))
 for sample in assignments.staff_indicator_reference.semantic_reference.all_sources:
  assignment_receipts.values[int(sample.unit_id)]=numbers(sample.duplicate(true))
 view.queue_redraw()
 for i in 2:await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join("assignments.png"))
 check_indicator_crops(root.get_texture().get_image(),assignments.staff_indicator_reference.render_reference)
 var slots: Array=view.assignment_slots(view.rows[1])
 assert(slots.size()==4 and slots[0].column==52 and slots[3].column==64,"native four indicator slots")
 var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800));view.hover_help=help
 for point in [Vector2(816,394),Vector2(816,358)]:
  var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
  await create_timer(0.6).timeout;await process_frame;await RenderingServer.frame_post_draw
  assert(help.displayed==("staff_performer" if point.y==394 else "staff_work_detail"),"approved visible indicator hover")
  root.get_texture().get_image().save_png(directory.path_join("assignment_hover_%d.png"%int(point.y)))
  check_indicator_crops(root.get_texture().get_image(),assignments.staff_indicator_reference.render_reference)
 var portrait:=InputEventMouseMotion.new();portrait.position=Vector2(592,394);portrait.global_position=portrait.position;root.push_input(portrait,true)
 await process_frame
 assert(not help.displayed.begins_with("staff_"),"portrait does not activate assignment help")
 for sample in assignments.staff_indicator_reference.art_reference.cases:
  assignment_receipts.values[6536]={"entries":numbers(sample.entries.duplicate(true))};view.queue_redraw()
  for i in 2:await process_frame;await RenderingServer.frame_post_draw
  if "-custom-" in sample.name:root.get_texture().get_image().save_png(directory.path_join(sample.name+".png"))
  check_indicator_crops(root.get_texture().get_image(),{"crops":[sample]})
 var help_keys={261:"tavern_keeper",262:"performer",263:"scholar",264:"scribe",265:"mercenary",266:"monster_slayer",267:"doctor",268:"workshop"}
 for sample in assignments.staff_indicator_reference.help_reference.cases:
  if int(sample.hover)<0:continue
  var entry: Dictionary={"kind":0,"id":87,"type":int(sample.get("role",1)),"subtype":-1,"custom":-1,"custom_code":"","name":""}
  if sample.has("building_type"):
   entry.kind=1 if int(sample.building_type)==13 else 2;entry.type=int(sample.building_type);entry.subtype=int(sample.subtype)
  assignment_receipts.values[6536]={"entries":[entry]};view.queue_redraw()
  for i in 2:await process_frame;await RenderingServer.frame_post_draw
  var before_hover:=root.get_texture().get_image().get_region(Rect2i(800,376,32,36)).get_data()
  var move:=InputEventMouseMotion.new();move.position=Vector2(816,394);move.global_position=move.position;root.push_input(move,true)
  await create_timer(0.6).timeout;await process_frame;await RenderingServer.frame_post_draw
  assert(help.displayed=="staff_"+help_keys[int(sample.hover)],"native staff help role "+sample.name)
  assert(root.get_texture().get_image().get_region(Rect2i(800,376,32,36)).get_data()==before_hover,"approved stable hover art "+sample.name)
 receipts.values.clear();await click(Vector2(784,394));assert(specialized.size()==2,"missing receipt prevents gesture")
 view.display({})
 if not view.rows.is_empty() or not view.geometry.is_empty():push_error("Staff close retained facts");quit(1);return
 view.queue_free();world.queue_free();await process_frame
 print("LOCATION_STAFF_VIEW_CAPTURE_PASS");quit(0)
