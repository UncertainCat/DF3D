extends SceneTree
const Model=preload("res://scripts/reports_state.gd")
func _initialize() -> void:
 var model=Model.new();model.set_epoch(7);model.open()
 var counts: Array=[];counts.resize(25);counts.fill(0);counts[0]=2;counts[10]=1;counts[22]=1
 assert(model.accept(model.generation,7,{"view":1,"list_revision":17,"tab":1,"reports":[{"id":1}],"tab_counts":counts,"next_after_id":1}))
 assert(not model.choose_tab(2))
 assert(model.choose_tab(23));assert(model.tab_rows[2]==Model.INITIAL_ROWS[0])
 var stale: int=model.generation
 assert(model.choose_tab(11));assert(model.tab_rows[2]==Model.INITIAL_ROWS[1])
 assert(not model.accept(stale,7,{"view":2,"unit_category":0,"units":[]}))
 assert(model.choose_tab(23))
 assert(model.accept(model.generation,7,{"view":2,"unit_category":0,"units":[{"unit_id":17,"category":0}],"list_revision":9,"tab_counts":counts}))
 assert(not model.open_unit(18,0));assert(model.open_unit(17,0));assert(model.pending.request.from_end)
 var log_rows:Array=[]
 for id in range(100,164):log_rows.append({"id":id})
 assert(model.accept(model.generation,7,{"view":3,"list_revision":71,"unit_id":17,"unit_category":0,"reports":log_rows,"total":65,"next_before_id":100}))
 assert(model.log_first==47 and model.rows[model.log_first].id==147)
 assert(model.previous_page());assert(model.pending.request.before_id==100 and model.pending.request.expected_list_revision==71 and not model.pending.request.get("refresh",false))
 assert(model.accept(model.generation,7,{"view":3,"list_revision":71,"unit_id":17,"unit_category":0,"reports":[{"id":99}],"total":65,"next_after_id":99}))
 assert(model.rows.size()==65);assert(model.next_after==-1);assert(model.log_first==48 and model.rows[model.log_first].id==147)
 model.scroll_to(0);assert(model.log_first==0 and model.rows[0].id==99)
 model.scroll_to(48);assert(model.log_first==48 and model.rows[48].id==147)
 model.close();var arrangement: Array=model.tab_rows.duplicate(true);model.open()
 assert(model.selected_tab==23 and model.tab_rows==arrangement and model.unit_id==-1)
 stale=model.generation;model.set_epoch(8)
 assert(not model.accept(stale,7,{"view":2,"unit_category":0,"units":[]}));assert(model.rows.is_empty())
 model.open();model.rows=[{"id":7,"position_visible":true,"position":Vector3i(-1,9,10),"position2_visible":true,"position2":Vector3i(21,22,23),"zoom_type":1,"position_hidden":true}]
 var targets:Array=[];model.recenter_requested.connect(func(tile):targets.append(tile))
 assert(not model.recenter(8));assert(model.recenter(7));assert(not model.opened and targets==[Vector3i(-1,9,10)])
 model.open();model.rows=[{"id":7,"position2_visible":true,"position2":Vector3i(21,22,23)}]
 assert(not model.recenter(7));assert(model.recenter(7,true));assert(targets.back()==Vector3i(21,22,23))
 var paged=Model.new();paged.open()
 var chunk:Array=[]
 for i in 64:chunk.append({"id":i})
 assert(paged.accept(paged.generation,0,{"view":1,"list_revision":17,"tab":1,"reports":chunk,"total":160,"next_after_id":63}))
 paged.scroll_to(145);assert(paged.first_row==49 and paged.requested_row==145 and paged.pending.request.after_id==63)
 chunk=[]
 for i in range(64,128):chunk.append({"id":i})
 assert(paged.accept(paged.generation,0,{"view":1,"list_revision":17,"tab":1,"reports":chunk,"total":160,"next_after_id":127}))
 assert(paged.first_row==113 and paged.requested_row==145 and paged.pending.request.after_id==127)
 chunk=[]
 for i in range(128,160):chunk.append({"id":i})
 assert(paged.accept(paged.generation,0,{"view":1,"list_revision":17,"tab":1,"reports":chunk,"total":160}))
 assert(paged.first_row==145 and paged.pending.is_empty() and paged.rows[145].id==145)
 paged.close();paged.open()
 assert(paged.first_row==0 and paged.total==0)
 chunk=[]
 for i in 64:chunk.append({"id":i})
 paged.accept(paged.generation,0,{"view":1,"list_revision":17,"tab":1,"reports":chunk,"total":97,"next_after_id":63})
 paged.scroll_to(82);paged.reject(paged.generation)
 assert(paged.pending.is_empty() and paged.requested_row==49)
 var watcher=Model.new();watcher.open();watcher.rows=[{"unit_id":71,"category":1,"log_count":42}]
 assert(watcher.open_unit(71,1));assert(not watcher.pause_on_new)
 var pauses:Array=[];watcher.pause_requested.connect(func():pauses.append(true))
 assert(watcher.observe_log_length(71,1,43,0));assert(pauses.is_empty())
 watcher.toggle_pause_on_new()
 assert(watcher.observe_log_length(71,1,44,0));assert(pauses.size()==1)
 assert(not watcher.observe_log_length(71,1,44,0));assert(pauses.size()==1)
 assert(watcher.observe_log_length(71,1,43,0));assert(pauses.size()==2)
 assert(not watcher.observe_log_length(72,1,99,0));assert(not watcher.observe_log_length(71,1,99,1))
 watcher.close();assert(watcher.pause_on_new)
 assert(not watcher.observe_log_length(71,1,45,0))
 watcher.set_epoch(1);assert(not watcher.pause_on_new)
 # Live appends retain cached removed rows and follow the newest page, including
 # batches larger than one transport page. The fresh source total may be lower.
 var live=Model.new();live.open();live.pending={};live.unit_id=17;live.unit_category=0
 live.log_revision=71;live.rows=[]
 for i in 30:live.rows.append({"id":i})
 live.total=30;live.unit_log_length=30;live.log_requested=5;live.log_first=5
 live.refresh_new_reports();assert(live.pending.request.after_id==29 and live.pending.request.expected_list_revision==71 and live.pending.request.refresh)
 assert(live.accept(live.generation,0,{"view":3,"list_revision":71,"unit_id":17,"unit_category":0,"reports":[{"id":31}],"total":29,"next_after_id":31}))
 assert(live.total==31 and live.rows[29].id==29 and live.pending.request.after_id==31)
 assert(live.accept(live.generation,0,{"view":3,"list_revision":71,"unit_id":17,"unit_category":0,"reports":[{"id":32}],"total":30}))
 assert(live.total==32 and live.log_requested==15 and live.log_first==15 and live.pending.is_empty())
 # Native070752: even an expired-only append follows the cached newest row.
 live.scroll_to(5);live.refresh_new_reports()
 assert(live.accept(live.generation,0,{"view":3,"list_revision":71,"unit_id":17,"unit_category":0,"reports":[],"total":30}))
 assert(live.log_requested==15 and live.rows.size()==32)
 live.refresh_new_reports();live.reject(live.generation)
 assert(live.pending.is_empty() and live.rows.size()==32 and live.log_refresh_needed)
 # A source change during history paging must not inflate the cached snapshot.
 var partial=Model.new();partial.open();partial.rows=[{"unit_id":71,"category":1,"log_count":100}]
 partial.open_unit(71,1)
 chunk=[]
 for i in range(36,100):chunk.append({"id":i})
 partial.accept(partial.generation,0,{"view":3,"list_revision":71,"unit_id":71,"unit_category":1,"reports":chunk,"total":100,"next_before_id":36})
 partial.previous_page();assert(partial.observe_log_length(71,1,101,0))
 partial.refresh_new_reports();assert(partial.pending.mode=="prepend" and partial.log_refresh_needed)
 chunk=[]
 for i in 36:chunk.append({"id":i})
 partial.accept(partial.generation,0,{"view":3,"list_revision":71,"unit_id":71,"unit_category":1,"reports":chunk,"total":101})
 assert(partial.total==100 and partial.rows.size()==100 and partial.log_refresh_needed)
 partial.refresh_new_reports();assert(partial.pending.request.after_id==99)
 partial.reject(partial.generation);assert(partial.log_refresh_needed)
 partial.refresh_new_reports()
 partial.accept(partial.generation,0,{"view":3,"list_revision":71,"unit_id":71,"unit_category":1,"reports":[{"id":100}],"total":101})
 assert(partial.total==101 and partial.log_requested==84 and not partial.log_refresh_needed)
 partial.close();assert(not partial.log_refresh_needed)
 var tabs=Model.new();tabs.open()
 var enabled:Array=[];enabled.resize(25);enabled.fill(1)
 chunk=[]
 for i in 20:chunk.append({"id":i})
 tabs.accept(tabs.generation,0,{"view":1,"list_revision":17,"tab":1,"reports":chunk,"total":20,"tab_counts":enabled})
 tabs.scroll_to(2);tabs.choose_tab(16)
 var cancelled:Array=[];tabs.request_cancelled.connect(func():cancelled.append(true))
 var abandoned:int=tabs.generation
 tabs.choose_tab(1)
 assert(tabs.rows==chunk and tabs.first_row==2 and tabs.pending.is_empty() and cancelled.size()==1)
 assert(not tabs.accept(abandoned,0,{"view":1,"list_revision":17,"tab":16,"reports":[{"id":999}]}))
 tabs.close();tabs.open();assert(tabs.tab_cache.is_empty() and tabs.rows.is_empty() and tabs.first_row==0 and not tabs.pending.is_empty())
 # Never-visited tabs and later pages carry the open snapshot, independently of
 # unit-list revisions. Missing/foreign snapshot receipts cannot alter the rows.
 var snapshot=Model.new();snapshot.open()
 assert(snapshot.pending.request.expected_list_revision==0)
 assert(not snapshot.accept(snapshot.generation,0,{"view":1,"tab":1,"reports":[]}))
 snapshot.accept(snapshot.generation,0,{"view":1,"tab":1,"list_revision":41,"reports":[{"id":0}],"total":2,"next_after_id":0,"tab_counts":enabled})
 snapshot.choose_tab(23)
 snapshot.accept(snapshot.generation,0,{"view":2,"unit_category":0,"list_revision":99,"units":[],"tab_counts":[]})
 snapshot.choose_tab(16);assert(snapshot.pending.request.expected_list_revision==41)
 assert(not snapshot.accept(snapshot.generation,0,{"view":1,"tab":16,"list_revision":42,"reports":[{"id":999}]}))
 snapshot.choose_tab(1);snapshot.next_page();assert(snapshot.pending.request.expected_list_revision==41)
 snapshot.close();snapshot.selected_tab=23;snapshot.open()
 assert(snapshot.pending.mode=="snapshot" and snapshot.pending.request.tab==1)
 snapshot.accept(snapshot.generation,0,{"view":1,"tab":1,"list_revision":42,"reports":[],"tab_counts":enabled})
 assert(snapshot.pending.request.view==2 and snapshot.tab_revision==42)
 print("REPORTS_STATE_PASS");quit()
