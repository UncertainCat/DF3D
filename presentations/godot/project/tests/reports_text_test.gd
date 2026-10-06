extends SceneTree
const Model=preload("res://scripts/reports_state.gd")
func tab_reply(rows:Array) -> Dictionary:
 var counts:Array=[];counts.resize(25);counts.fill(1);counts[0]=rows.size()
 return {"view":1,"tab":1,"list_revision":17,"reports":rows,"tab_counts":counts,"total":rows.size()}
func row(id:int,text:String,complete:bool=false) -> Dictionary:
 return {"id":id,"text":text,"text_complete":complete,"color":3}
func page(id:int,text:String,cursor:int,next:int,total:int) -> Dictionary:
 return {"view":5,"tab":1,"list_revision":17,"cursor":cursor,"next_cursor":next,"total":total,"reports":[row(id,text,cursor==0 and next==0)]}
func accept(model,reply:Dictionary) -> bool:return model.accept(model.generation,model.epoch,reply)
func start():
 var model=Model.new();model.open()
 assert(accept(model,tab_reply([row(1,"a".repeat(16383)),row(2,"b".repeat(16384))])))
 assert(model.rows.is_empty() and model.pending.request=={"action":35,"view":5,"tab":1,"id":1,"cursor":0,"expected_list_revision":17})
 return model
func _initialize():
 var model=start()
 var first:Dictionary=page(1,"a".repeat(16383),0,16383,16391)
 var last:Dictionary=page(1,"☺ tail",16383,0,16391)
 for key in ["tab","list_revision","cursor"]:
  var bad:Dictionary=first.duplicate(true);bad[key]=int(bad[key])+1
  assert(not accept(model,bad))
 var bad:Dictionary=first.duplicate(true);bad.reports[0].color=2
 assert(not accept(model,bad))
 bad=first.duplicate(true);bad.reports[0].text="x".repeat(16383)
 assert(not accept(model,bad))
 assert(accept(model,first));assert(model.rows.is_empty() and model.pending.request.cursor==16383)
 bad=last.duplicate(true);bad.total=16392
 assert(not accept(model,bad))
 assert(accept(model,last));assert(model.pending.request.id==2 and model.rows.is_empty())
 assert(accept(model,page(2,"b".repeat(16384),0,16384,16388)))
 assert(accept(model,page(2,"TAIL",16384,0,16388)))
 assert(model.pending.is_empty() and model.rows.size()==2)
 assert(model.rows[0].text=="a".repeat(16383)+"☺ tail" and model.rows[1].text=="b".repeat(16384)+"TAIL")
 assert(model.rows[0].text_complete and model.rows[1].text_complete)
 # A fetched page is committed atomically; existing rows remain during append.
 model.next_after=2;model.total=3;assert(model.next_page())
 var reply:Dictionary=tab_reply([row(3,"c".repeat(16384))]);reply.total=3;reply.tab_counts[0]=3
 assert(accept(model,reply));assert(model.rows.size()==2)
 assert(accept(model,page(3,"c".repeat(16384),0,16384,16385)))
 assert(accept(model,page(3,"!",16384,0,16385)))
 assert(model.rows.size()==3 and model.rows[2].text.ends_with("!"))
 # Resolved rows stay in per-tab cache without fresh Text captures.
 assert(model.choose_tab(2))
 assert(accept(model,{"view":1,"tab":2,"list_revision":17,"reports":[row(4,"small",true)],"total":1}))
 assert(model.choose_tab(1));assert(model.rows.size()==3 and model.pending.is_empty())
 for action in ["close","epoch","tab","reject"]:
  model=start();assert(accept(model,first));var late:int=model.generation;var epoch:int=model.epoch
  if action=="close":model.close()
  elif action=="epoch":model.set_epoch(9)
  elif action=="tab":
   model.counts.resize(25);model.counts.fill(1);assert(model.choose_tab(2))
  else:model.reject(late)
  assert(model._text_assembly==null and model._text_reply.is_empty())
  assert(not model.accept(late,epoch,last))
 # Unit-tab bootstrap captures ordinary snapshot identity, not unused full text.
 model=Model.new();model.selected_tab=24;model.open()
 assert(accept(model,tab_reply([row(1,"a".repeat(16383))])))
 assert(model.pending.request.view==2 and model._text_assembly==null)
 ordinary_recovery()
 failed_tab_navigation()
 unit_text()
 print("REPORTS_TEXT_PASS");quit()

func unit_page(id:int,text:String,cursor:int,next:int,total:int) -> Dictionary:
 var value:Dictionary=page(id,text,cursor,next,total)
 value.tab=0;value.unit_id=71;value.unit_category=1;value.list_revision=23
 return value

func unit_text() -> void:
 var model=Model.new();model.open();model.rows=[{"unit_id":71,"category":1}]
 assert(model.open_unit(71,1))
 var reply:Dictionary={"view":3,"unit_id":71,"unit_category":1,"list_revision":23,"reports":[row(1,"a")],"total":1}
 assert(accept(model,reply))
 assert(model.log_revision==23 and model.pending.request.unit_id==71 and model.pending.request.expected_list_revision==23)
 var first:Dictionary=unit_page(1,"a".repeat(16383),0,16383,16391)
 var last:Dictionary=unit_page(1,"☺ tail",16383,0,16391)
 for key in ["unit_id","unit_category","tab","list_revision"]:
  var bad:Dictionary=first.duplicate(true);bad[key]=int(bad[key])+1
  assert(not accept(model,bad))
 assert(accept(model,first));assert(model.rows.is_empty() and model.log_initial_needed)
 model.reject(model.generation)
 assert(model.log_initial_needed and model.log_revision==23 and model._text_assembly==null)
 model.retry_initial_log()
 assert(model.pending.request.expected_list_revision==23 and model.pending.request.from_end and not model.pending.request.get("refresh",false))
 assert(accept(model,reply));assert(accept(model,first))
 assert(accept(model,last));assert(not model.log_initial_needed)
 assert(model.rows[0].text=="a".repeat(16383)+"☺ tail")
 model.refresh_new_reports()
 assert(model.pending.request.refresh and model.pending.request.expected_list_revision==23)
 reply.reports=[row(2,"a")];reply.total=2
 assert(accept(model,reply));assert(model.rows.size()==1)
 first.reports[0].id=2;last.reports[0].id=2
 assert(accept(model,first));assert(accept(model,last))
 assert(model.rows.size()==2 and not model.log_refresh_needed and model.rows[1].text_complete)
 model.refresh_new_reports();reply.reports=[row(3,"a")]
 assert(accept(model,reply));first.reports[0].id=3
 assert(accept(model,first));var late:int=model.generation
 model.close();assert(model.log_revision==0 and model._text_assembly==null)
 assert(not model.accept(late,model.epoch,last))

func ordinary_recovery() -> void:
 var model=Model.new();model.open()
 assert(accept(model,tab_reply([row(1,"a")])) )
 var first:Dictionary=page(1,"a".repeat(16383),0,16383,16391)
 var last:Dictionary=page(1,"☺ tail",16383,0,16391)
 assert(accept(model,first));model.reject(model.generation)
 assert(model.rows.is_empty() and model.read_retry.request.expected_list_revision==17 and model._text_assembly==null)
 assert(model.retry_read());assert(model.pending.request.view==1 and model.pending.request.expected_list_revision==17)
 assert(accept(model,tab_reply([row(1,"a")])));assert(accept(model,first));assert(accept(model,last))
 model.next_after=1;model.total=2;assert(model.next_page())
 var requested:Dictionary=model.pending.request.duplicate(true)
 model.reject(model.generation);assert(model.retry_read())
 assert(model.pending.mode=="append" and model.pending.request==requested and model.rows.size()==1)
 var reply:Dictionary=tab_reply([row(2,"small",true)]);reply.total=2
 assert(accept(model,reply));assert(model.rows.size()==2)
 model.next_after=2;model.next_page();model.reject(model.generation)
 model.scroll_to(0);assert(not model.retry_read())
 model.next_after=2;model.next_page();model.reject(model.generation)
 model.close();assert(not model.retry_read() and model.read_retry.is_empty())
 # Unit-list continuation uses its own revision, not the ordinary tab snapshot.
 model=Model.new();model.opened=true;model.tab_revision=17;model.selected_tab=23;model._request_selection()
 var units:Array=[]
 for i in 64:units.append({"unit_id":i,"category":0})
 assert(accept(model,{"view":2,"unit_category":0,"list_revision":51,"units":units,"total":65,"next_cursor":64}))
 assert(model.next_page());requested=model.pending.request.duplicate(true)
 model.reject(model.generation);assert(model.retry_read() and model.pending.request==requested)
 assert(not accept(model,{"view":2,"unit_category":0,"list_revision":52,"units":[{"unit_id":64,"category":0}],"total":65}))
 assert(accept(model,{"view":2,"unit_category":0,"list_revision":51,"units":[{"unit_id":64,"category":0}],"total":65}))
 assert(model.rows.size()==65)

func failed_tab_navigation() -> void:
 var model=Model.new();model.open()
 assert(accept(model,tab_reply([row(1,"small",true)])))
 model.counts.fill(1)
 assert(model.choose_tab(2))
 model.reject(model.generation)
 var demand:Dictionary=model.read_retry.duplicate(true)
 model.scroll_to(0)
 assert(model.read_retry==demand and model.pending.is_empty())
 assert(model.choose_tab(1) and model.rows[0].id==1)
 assert(not model.tab_cache.has(2))
 assert(model.choose_tab(2) and model.pending.request.tab==2)
 # A failed Text assembly is also an unfinished initial tab, never an empty cache.
 assert(accept(model,{"view":1,"tab":2,"list_revision":17,"reports":[row(2,"a")],"total":1}))
 assert(model.pending.mode=="text")
 model.reject(model.generation);model.scroll_to(0)
 assert(model.read_retry.mode=="replace")
 assert(model.choose_tab(1) and not model.tab_cache.has(2))
 assert(model.choose_tab(2) and model.pending.request.tab==2)
 assert(accept(model,{"view":1,"tab":2,"list_revision":17,"reports":[row(2,"complete",true)],"total":1}))
 assert(model.choose_tab(1));assert(model.choose_tab(2))
 assert(model.pending.is_empty() and model.rows[0].text=="complete")
