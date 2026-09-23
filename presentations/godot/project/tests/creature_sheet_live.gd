extends "res://tests/mesh_batch_motion_live.gd"
func label_evidence(node: Node, result: Array):
 if node is Label and not node.text.is_empty():
  # Catch container squeeze regressions (e.g. a right-hand category wrapping
  # one character per line). The reference viewport has room for these rows.
  if node.text.length()>8: assert(node.size.x>=64,"Text squeezed: "+node.text)
  result.append({"text":node.text,"width":node.size.x,"height":node.size.y})
 elif node is RichTextLabel:
  result.append({"text":node.get_parsed_text(),"width":node.size.x,"height":node.size.y})
 for child in node.get_children(): label_evidence(child,result)
func thought_coverage(sheet, sex: int) -> Dictionary:
 var formatter=load("res://scripts/creature_thought_text.gd")
 var data: Dictionary=formatter.prepare(sheet.owner.world)
 var missing := {}
 var eligible := 0
 var rendered := 0
 for row in sheet.records_for("emotions"):
  var thought := int(sheet.fact_value(row,"thought_id",-1))
  var emotion := int(sheet.fact_value(row,"emotion_id",-2))
  if thought in [-1,6] or emotion in [165,166]: continue
  eligible+=1
  if not formatter.sentence(sheet,row,sex,data).is_empty(): rendered+=1
  else:
   var key := str(thought)+"/"+str(sheet.fact_value(row,"subthought_id",-1))
   missing[key]=int(missing.get(key,0))+1
 return {"eligible":eligible,"rendered":rendered,"omitted_by_thought_subthought":missing}
func run():
 # Match the native reference client, not its decorated Windows rectangle.
 root.size=Vector2i(1200,792)
 scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
 var deadline=Time.get_ticks_msec()+120000
 while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
 if not scene._loader.entered: push_error("Creature sheet load failed");quit(1);return
 if not await set_paused(true): quit(1);return
 await go_level(128);await settle()
 var evidence={}
 for id in [86,310]:
  var row: Dictionary=scene.world.inspect_entity(1,id)
  assert(not row.is_empty(),"Reference creature visible")
  await go_level(row.tile.z)
  scene.camera_rig.focus_on(Vector3(row.tile.x+.5,row.tile.z,row.tile.y+.5),12)
  await scene._ui.controller("inspector").open_target(row.tile,1,id)
  deadline=Time.get_ticks_msec()+30000
  var state: Dictionary=scene.world.creature_info_state(id)
  while not state.get("complete",false) and Time.get_ticks_msec()<deadline:
   await create_timer(.1).timeout
   state=scene.world.creature_info_state(id)
  if not state.get("complete",false):
   var failure=FileAccess.open(output+"-failure.json",FileAccess.WRITE);failure.store_string(JSON.stringify(state,"  "))
   push_error("Creature facts incomplete: "+str(state.get("error","")));quit(1);return
  assert(state.detail.sections.size()==25,"All semantic domains published")
  var counts={}
  for section in state.detail.sections:
   counts[section.key]={"count":section.records.size(),"available":section.available,"truncated":section.truncated,"reason":section.reason}
   if not section.available or section.truncated:
    var failure=FileAccess.open(output+"-failure.json",FileAccess.WRITE)
    failure.store_string(JSON.stringify(state,"  "))
    push_error("Reference domain failed: "+str(id)+" / "+str(section.key)+" / "+str(section.reason))
    quit(1);return
  evidence[str(id)]={"name":state.detail.name,"sections":counts,"pages":[],"labels":{},"tabs":{}}
  var view=scene._ui.controller("inspector")
  var bounds: Rect2=view.panel.get_global_rect()
  evidence[str(id)].capture={"viewport":[root.size.x,root.size.y],"panel":[bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y]}
  # Development evidence for omitted native clauses; never read by runtime UI.
  evidence[str(id)].semantic=state.detail.sections.filter(func(value): return value.key in ["emotions","memories"])
  var sheet=view.creature_sheet
  for group in sheet.recipe.rows:
   for tab in group:
    sheet.change_tab(tab)
    var nested: Array=sheet.recipe.subtabs[tab].keys() if sheet.recipe.subtabs.has(tab) else [""]
    for sub in nested:
     if not sub.is_empty(): sheet.change_tab(sub,true)
     for i in 3: await process_frame
     # Let queued theme/atlas work settle before asynchronous GPU readback.
     # Semantic state is already paused; this is capture-only pacing.
     await create_timer(.2).timeout
     assert(view.panel.visible and view.selected.id==id,"Local navigation preserves creature identity")
     var name=str(id)+"-"+tab.to_snake_case()+("-"+sub.to_snake_case() if not sub.is_empty() else "")
     var labels: Array=[]
     label_evidence(sheet.scroll,labels)
     for label in labels:
      if str(label.text).contains("[C:"):
       push_error("Native color markup escaped into visible text: "+name);quit(1);return
     evidence[str(id)].labels[name]=labels
     var tabs: Array=[]
     for control in view.body.get_children():
      if control is Button: tabs.append({"text":control.text,"color":control.get_theme_color("font_color").to_html(),"y":control.position.y})
     evidence[str(id)].tabs[name]=tabs
     if tab=="Thoughts" and sub=="Recent thoughts": evidence[str(id)].thought_coverage=thought_coverage(sheet,int(state.detail.get("sex",-1)))
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png(output+"-"+name+".png")
     evidence[str(id)].pages.append(name)
  view.close_panel()
 var file=FileAccess.open(output+"-data.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "))
 print("CREATURE_SHEET_LIVE_PASS");quit()
