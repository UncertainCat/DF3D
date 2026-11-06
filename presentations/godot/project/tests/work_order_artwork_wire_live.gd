extends "res://tests/workshop_order_wire_live.gd"
func capture(flow: String,stage: String) -> void:
 for _frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/work-order-artwork-"+flow+"-"+stage+"-live.png")
func run() -> void:
 directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
 var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-order-artwork-expected.json"))
 world=Df3dWorld.new();root.add_child(world)
 if not check(world.attach(),"Dye bridge attach failed"):quit(1);return
 var deadline:=Time.get_ticks_msec()+5000
 while Time.get_ticks_msec()<deadline:
  world.poll()
  if world.poll_management().get("transport_alive",false):break
  await create_timer(0.01).timeout
 var bootstrap:=await request("construction",{"action":C.ManagementAction.Catalog})
 if not check(bootstrap.get("status")==C.ManagementStatus.Ok and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Dye bootstrap/assets failed"):quit(1);return
 var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
 root.size=Vector2i(912,552) if plan.get("categories",false) else Vector2i(1200,800)
 # Settle the separate renderer's viewport resize before creating canvas items.
 for _frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
 var state=preload("res://scripts/work_order_details_state.gd").new();state.configure(service)
 var view=preload("res://scripts/work_order_details_view.gd").new();root.add_child(view);view.configure_details(world,state)
 view.cancelled.connect(state.close);state.applied.connect(state.close)
 view.open(-2,int(plan.id));view.layout(Vector2(root.size))
 if not check(await settle(service,func():return state.phase==state.Phase.Ready),"Artwork Details failed"):quit(1);return
 await process_frame;click(Vector2(200,106+int(plan.option)*36))
 if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.snapshot.selected_option==int(plan.option)),"Improvement chooser failed"):quit(1);return
 click(Vector2(200,142))
 if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.has_art()),"Artwork root failed"):quit(1);return
 if plan.get("artist",false):
  await capture("artist","before")
  var artist_row: int=-1
  for index in state.rows.size():
   if state.rows[index].id==0:artist_row=index
  if not check(artist_row>=0,"Artist choice is missing from the native menu"):quit(1);return
  click(Vector2(200,154+artist_row*36))
  if not check(await settle(service,func():return state.phase==state.Phase.Closed),"Artist choice did not close Details after confirmation; phase="+str(state.phase)+" ticket="+str(state.ticket)):quit(1);return
  check(not view.visible,"Artist choice left Details visible")
 elif plan.get("categories",false):
  root.size=Vector2i(912,552)
  await create_timer(0.3).timeout
  view.layout(Vector2(912,552));await process_frame
  click(view.position+Vector2(100,260))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==6),"New artwork at minimum failed"):quit(1);return
  for category in view.DRAFT_CATEGORIES:
   var page: int=category[0]
   if page>13:continue
   click(view.position+Vector2(category[2]*Vector2i(8,12))+Vector2(12,18))
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==page),"Artwork category failed: "+str(page)):quit(1);return
   var numbered: bool=page in [7,9,10,11,12]
   check(view.page_rows==(7 if numbered else 8),"Category capacity differs from native: "+str(page))
   if state.snapshot.art.total>view.page_rows:
    check(view.scrollbar.visible,"Category scrollbar missing")
    click(view.position+view.scrollbar.position+Vector2(8,view.scrollbar.size.y-6))
    check(state.first==1,"Category scrollbar did not advance")
    click(view.position+view.scrollbar.position+Vector2(8,6))
    check(state.first==0,"Category scrollbar did not return")
   click(view.position+Vector2(view.size.x-64,view.size.y-30))
   check(state.draft_quantity==(2 if numbered else 1),"Category quantity input differs from native: "+str(page))
   click(view.position+Vector2(312,view.size.y-30))
   check(view.quantity_focused==numbered,"Category quantity focus differs from native: "+str(page))
   number_key(KEY_ENTER)
   if page in [8,13]:await capture("category-"+str(page),"minimum")
   click(view.position+Vector2(32,378))
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==6),"Category Cancel failed"):quit(1);return
   check(not view.quantity_focused,"Quantity focus survived Cancel")
  click(view.position+Vector2(144,378))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==-1),"Empty draft Back failed"):quit(1);return
 elif plan.has("subjects"):
  for subject in plan.subjects:
   click(Vector2(200,154+(int(subject.page)-1)*36))
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==int(subject.page)),"Subject list failed"):quit(1);return
   if state.snapshot.art.total>view.page_rows:
    check(view.scrollbar.visible,"Artwork scrollbar hidden despite overflowing rows")
    click(view.position+view.scrollbar.position+Vector2(8,view.scrollbar.size.y-6))
    check(state.first==1,"Artwork scrollbar down arrow did not move one row")
    click(view.position+view.scrollbar.position+Vector2(8,6))
    check(state.first==0,"Artwork scrollbar up arrow did not restore first row")
   var motion:=InputEventMouseMotion.new();motion.position=Vector2(200,190);motion.global_position=motion.position;root.push_input(motion,true)
   if not check(await settle(service,func():return state.preview_ticket==0 and not state.preview_lines.is_empty()),"Subject preview failed"):quit(1);return
   check(state.preview_lines==subject.preview,"Subject preview differs from native")
   await capture("subject-"+str(int(subject.page)),"hover")
   motion=InputEventMouseMotion.new();motion.position=Vector2(200,110);motion.global_position=motion.position;root.push_input(motion,true)
   check(state.preview_lines.is_empty(),"Subject preview survived pointer leave")
   var back_event:=InputEventMouseButton.new();back_event.button_index=MOUSE_BUTTON_RIGHT;back_event.pressed=true;root.push_input(back_event,true)
   back_event=back_event.duplicate();back_event.pressed=false;root.push_input(back_event,true)
   if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==-1),"Subject Back failed"):quit(1);return
 else:
  click(Vector2(200,298))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==6),"New artwork failed"):quit(1);return
  click(Vector2(70,154))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==7),"Creature picker failed"):quit(1);return
  click(Vector2(300,190))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==6 and state.draft_value.elements.size()==1),"Draft addition failed"):quit(1);return
  click(Vector2(168,418));check(state.draft_discard,"Discard confirmation missing")
  await capture("discard","page")
  click(Vector2(200,190));check(not state.draft_discard and state.draft_value.elements.size()==1,"Keep working lost draft")
  click(Vector2(168,418));number_key(KEY_ESCAPE)
  check(state.draft_discard,"Escape dismissed native confirmation")
  var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;root.push_input(right,true)
  right=right.duplicate();right.pressed=false;root.push_input(right,true)
  check(state.draft_discard,"Right click dismissed native confirmation")
  click(Vector2(200,142))
  if not check(await settle(service,func():return state.phase==state.Phase.Ready and state.art_page()==-1),"Discard did not return to artwork root"):quit(1);return
  check(state.draft_value.elements.is_empty() and state.draft_value.relationships.is_empty(),"Discard retained draft content")
 var file:=FileAccess.open(directory+"/work-order-artwork-wire-result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"success":not failed,"subjects":plan.has("subjects"),"artist":plan.get("artist",false),"categories":plan.get("categories",false),"discarded":not plan.has("subjects") and not plan.get("artist",false) and not plan.get("categories",false)}));file.close()
 state.dispose();view.queue_free();service.queue_free();await process_frame
 world.detach_live();world.queue_free();await process_frame
 quit(1 if failed else 0)
