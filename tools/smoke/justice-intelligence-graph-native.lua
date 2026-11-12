-- Compare the owned collector with native Justice in a disposable paused clone.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local entity=df.global.plotinfo.main.fortress_entity;assert(entity)
local original=entity.evidence_repository;local repository=df.evidence_repositoryst:new();local files={}
local reports=df.global.world.status.interrogation_reports;local report_count=#reports;local added_reports={}
local layout_org,layout_original;local layout_added={}
local function reopen()
 gui.simulateInput(view,'LEAVESCREEN');settle();gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then
  g.precise_mouse_x=711;g.precise_mouse_y=430;g.mouse_x=711//8;g.mouse_y=430//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 end
 tab('Intelligence')
end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function index(values,pointer)
 if not pointer then return -1 end
 for i,value in ipairs(values)do if value==pointer then return i end end
 error('Native graph edge is outside owning list')
end
local function ids(values)local result={};for _,value in ipairs(values)do result[#result+1]=value end;return result end
local function native_graph(menu)
 local result={actors={},organizations={},plots={}}
 for _,row in ipairs(menu.base_actor_entry)do
  local orgs,plots={},{}
  for _,value in ipairs(row.associated_org)do orgs[#orgs+1]=index(menu.base_organization_entry,value)end
  for _,value in ipairs(row.associated_plot)do plots[#plots+1]=index(menu.base_plot_entry,value)end
  local lines={};for _,line in ipairs(row.main_text_box.text)do lines[#lines+1]=dfhack.df2utf(line.value)end
  result.actors[#result.actors+1]={lines=lines,historical_figure=row.hf and row.hf.id or -1,identity=row.iden and row.iden.id or -1,name=dfhack.df2utf(row.list_name),aliases=ids(row.alias_identity_id),principal_organization=index(menu.base_organization_entry,row.principle_org),organizations=orgs,plots=plots}
 end
 for _,row in ipairs(menu.base_organization_entry)do
  local value={name=dfhack.df2utf(row.list_name),principal_actor=index(menu.base_actor_entry,row.principle_actor_entry),nodes={}}
  for _,node in ipairs(row.node)do
   value.nodes[#value.nodes+1]={actor=index(menu.base_actor_entry,node.actor_entry),parent=index(row.node,node.master),sort=node.sort_id,tier=node.tier,descendants=node.descendant_sum,label=dfhack.df2utf(node.label),name=dfhack.df2utf(node.name),status=dfhack.df2utf(node.status),foreground=node.fcol,background=node.bcol,bright=node.br}
  end
  result.organizations[#result.organizations+1]=value
 end
 for _,row in ipairs(menu.base_plot_entry)do
  local org=-1
  for i,value in ipairs(menu.base_organization_entry)do if value.list_name==row.organization_name then assert(org==-1,'Ambiguous fixture organization name');org=i end end
  assert(row.organization_name=='' or org>=0,'Fixture organization caption is clipped or unresolved')
  result.plots[#result.plots+1]={agreement=row.agreement and row.agreement.id or -1,master=row.master_hfid,name=dfhack.df2utf(row.list_name),organization=org}
 end
 return result
end
local ok,err=xpcall(function()
 if os.getenv('DF3D_JUSTICE_GRAPH_MIXED')=='1' then
  assert(report_count==0,'Mixed Intelligence fixture requires empty report baseline')
  local report=df.interrogation_report:new();report.title='Synthetic mixed Intelligence report';report.officer_name='Synthetic officer'
  report.officer_hf=-1;report.subject_hf=-1;report.subject_identity_id=-1;report.flags.whole=0
  local line=df.new('string');line.value='Synthetic report detail for navigation verification.';report.details:insert('#',line)
  reports:insert('#',report);added_reports[#added_reports+1]=report
 end
 entity.evidence_repository=repository
 local empty=probe('justice-intelligence-graph-probe')
 assert(#empty.actors==0 and #empty.organizations==0 and #empty.plots==0,'Empty evidence invented graph entries')
 local chosen;local agreements={}
 for _,agreement in ipairs(df.global.world.agreements.all)do
  local intrigue=false
  for _,detail in ipairs(agreement.details)do if detail.type>=5 and detail.type<=15 then intrigue=true;break end end
  if intrigue and #agreement.parties>=2 then
   local count=0;for _,party in ipairs(agreement.parties)do for _,id in ipairs(party.histfig_ids)do if df.historical_figure.find(id)then count=count+1 end end end
   if count>=2 then
    agreements[#agreements+1]=agreement;chosen=chosen or agreement
    if os.getenv('DF3D_JUSTICE_GRAPH_CONNECTED')~='1' or #agreements>=(os.getenv('DF3D_JUSTICE_GRAPH_WIDE')=='1' and 96 or 12)then break end
   end
  end
 end
 assert(chosen,'Fixture requires an existing intrigue agreement with two historical figures')
 local hfids,seen={},{}
 local associations={}
 for _,agreement in ipairs(agreements)do
  repository.foiled_plot_agreements:insert('#',agreement.id)
  for _,party in ipairs(agreement.parties)do for _,id in ipairs(party.histfig_ids)do
   if df.historical_figure.find(id)then
    if not seen[id]then hfids[#hfids+1]=id;seen[id]=true;associations[id]={}end
    associations[id][agreement.id]=true
   end
  end end
 end
 table.sort(hfids)
 for _,id in ipairs(hfids)do
  local file=df.evidence_hf_filest:new();file.hfid=id;file.flags.whole=8
  if os.getenv('DF3D_JUSTICE_GRAPH_ALIASES')=='1' and #files==0 then file.used_identity:insert('#',df.global.world.identities.all[0].id)end
  for _,agreement in ipairs(agreements)do if associations[id][agreement.id]then file.agreement:insert('#',agreement.id)end end
  repository.hf_file:insert('#',file);files[#files+1]=file
 end
 if os.getenv('DF3D_JUSTICE_GRAPH_LARGE')=='1' then
  for _,figure in ipairs(df.global.world.history.figures)do
   if not seen[figure.id] and figure.name.has_name then
    local file=df.evidence_hf_filest:new();file.hfid=figure.id;file.flags.whole=8
    repository.hf_file:insert('#',file);files[#files+1]=file;hfids[#hfids+1]=figure.id;seen[figure.id]=true
    if #files>=20 then break end
   end
  end
 end
 entity.evidence_repository=repository;reopen()
 local menu=df.global.game.main_interface.info.justice
 click(220,148);assert(menu.counterintelligence_mode==1);local native=native_graph(menu)
 assert(#native.plots>0 and #native.organizations>0,'Fixture did not produce a populated graph')
 local guards={}
 local function guard(value)local n,p=df.sizeof(value);guards[#guards+1]={n=n,p=p,data=bytes(p,n)}end
 for _,file in ipairs(files)do file.temp_flags.whole=123;guard(file)end
 for _,id in ipairs(hfids)do guard(df.historical_figure.find(id))end
 guard(repository);guard(entity);guard(menu);for _,agreement in ipairs(agreements)do guard(agreement)end
 local supplied=probe('justice-intelligence-graph-probe')
 assert(df.global.plotinfo.main.fortress_entity==entity,'Entity pointer not restored')
 for _,entry in ipairs(guards)do assert(bytes(entry.p,entry.n)==entry.data,'Graph provider modified source evidence/entity/menu/agreement')end
 local data={agreement=chosen.id,empty=empty,native=native,provider=supplied}
 local f=assert(io.open(out..'/justice-intelligence-graph.json','w'));f:write(json.encode(data));f:close()
 assert(json.encode(native)==json.encode(supplied),'Native graph facts differ')
 if os.getenv('DF3D_JUSTICE_WIRE_GRAPH')=='1' then
  local script=require('gui.script')
  local wire=assert(io.open(out..'/justice-wire-reference.json','w'));wire:write(json.encode({graph=supplied}));wire:close()
  wire=assert(io.open(out..'/shot.tmp','w'));wire:write('justice-wire');wire:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
  local deadline=dfhack.getTickCount()+120000
  while true do local ack=io.open(out..'/ack-justice-wire');if ack then ack:close();break end
   assert(dfhack.getTickCount()<deadline,'Intelligence graph wire timeout');script.sleep(1,'frames')
  end
  for _,entry in ipairs(guards)do assert(bytes(entry.p,entry.n)==entry.data,'Graph wire changed native source')end
 end
 capture('justice-intelligence-graph')
 if os.getenv('DF3D_JUSTICE_GRAPH_PRESENTATION')=='1' then
  local states={}
  local function record(name)
   local state={mode=menu.counterintelligence_mode,selected=menu.counterintelligence_selected,scroll=menu.scroll_position_counterintelligence,selected_node=-1,viewing_report=menu.viewing_interrogation_report~=nil,actors={},organizations={},plots={},lines={}}
   if menu.selected_counterintelligence_oen and menu.counterintelligence_selected>=0 and menu.counterintelligence_selected<#menu.organization_entry then state.selected_node=index(menu.organization_entry[menu.counterintelligence_selected].node,menu.selected_counterintelligence_oen)end
   for _,row in ipairs(menu.actor_entry)do
    local lines={};for _,line in ipairs(row.main_text_box.text)do lines[#lines+1]=dfhack.df2utf(line.value)end
    state.actors[#state.actors+1]={name=dfhack.df2utf(row.p_list_name),lines=lines}
   end
   for _,org in ipairs(menu.organization_entry)do
    local nodes={};for _,node in ipairs(org.node)do nodes[#nodes+1]={x=node.x,tier=node.tier,descendants=node.descendant_sum,name=dfhack.df2utf(node.name),label=dfhack.df2utf(node.label),status=dfhack.df2utf(node.status)}end
    state.organizations[#state.organizations+1]={name=dfhack.df2utf(org.p_list_name),nodes=nodes}
   end
   for _,plot in ipairs(menu.plot_entry)do state.plots[#state.plots+1]={name=dfhack.df2utf(plot.p_list_name),organization=dfhack.df2utf(plot.organization_name)}end
   for y=0,g.dimy-1 do local chars={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=t.ch>=32 and t.ch<=255 and string.char(t.ch)or' 'end;state.lines[#state.lines+1]=dfhack.df2utf(table.concat(chars))end
   states[name]=state;capture('justice-graph-'..name)
  end
  click(220,148);assert(menu.counterintelligence_mode==1,'Actors tab missed');record('actors')
  if os.getenv('DF3D_JUSTICE_GRAPH_WHEEL')=='1' then
   for _,step in ipairs{{'CONTEXT_SCROLL_DOWN','actors-wheel'},{'CONTEXT_SCROLL_PAGEDOWN','actors-wheel-page'}}do
    g.precise_mouse_x=200;g.precise_mouse_y=250;g.mouse_x=25;g.mouse_y=20;df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    gui.simulateInput(view,step[1]);settle();record(step[2])
   end
   click(952,730);record('actors-arrow-down')
   click(324,148);click(220,148)
  end
  if os.getenv('DF3D_JUSTICE_GRAPH_LARGE')=='1' then
   gui.simulateInput(view,'STANDARDSCROLL_DOWN');settle();record('actors-scroll-down')
   gui.simulateInput(view,'STANDARDSCROLL_PAGEDOWN');settle();record('actors-scroll-page')
   click(944,716);record('actors-scroll-arrow')
   click(324,148);click(220,148)
  end
  click(64,250);record('actor-selected')
  click(324,148);assert(menu.counterintelligence_mode==2,'Organizations tab missed');record('organizations')
  if os.getenv('DF3D_JUSTICE_GRAPH_CONNECTED')=='1' then
   click(944,716);record('organizations-scroll')
   click(96,690);record('organization-last')
  end
  if os.getenv('DF3D_JUSTICE_GRAPH_NAVIGATION')=='1' then
   click(496,340);assert(menu.selected_counterintelligence_oen==menu.organization_entry[0].node[1]);record('node-selected')
   click(96,220);assert(menu.selected_counterintelligence_oen==menu.organization_entry[0].node[1],'Blank organization click changed selection');record('node-blank')
   click(496,412);assert(menu.selected_counterintelligence_oen==menu.organization_entry[0].node[2]);record('node-last')
   gui.simulateInput(view,'CURSOR_UP');settle();record('node-key-up')
   click(220,148);record('actors-return')
   gui.simulateInput(view,'CURSOR_DOWN');settle();record('actors-key-down')
   click(324,148);record('organizations-return')
  end
  click(440,148);assert(menu.counterintelligence_mode==3,'Plots tab missed');record('plots')
  if os.getenv('DF3D_JUSTICE_GRAPH_MIXED')=='1' then
   click(96,148);record('reports')
   click(120,190);assert(menu.viewing_interrogation_report==added_reports[1]);record('report-detail')
   -- Diagnostic-only cache invalidation distinguishes DF's two text builders.
   menu.interrogation_report_box_width=0;view:render(dfhack.getTickCount());record('report-render-rebuild')
   menu.interrogation_report_box_width=0;gui.simulateInput(view,'CURSOR_DOWN');settle();record('report-input-rebuild')
   click(220,148);record('report-to-actors')
   click(96,148);record('reports-return')
   if os.getenv('DF3D_JUSTICE_REPORT_BACK')=='1' then
    click(120,190);gui.simulateInput(view,'LEAVESCREEN');settle()
    record('report-back');states['report-back'].panel_open=df.global.game.main_interface.info.open
    if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle();tab('Intelligence')end
   end
  end
  if os.getenv('DF3D_JUSTICE_GRAPH_RESIZE')=='1' then
   local function resize(name)
    local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..name);f:close()
    assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
    local deadline=dfhack.getTickCount()+30000
    while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
     assert(dfhack.getTickCount()<deadline,'Graph resize timeout');require('gui.script').sleep(1,'frames')end
    assert(os.remove(out..'/owner-input-ack'));settle()
   end
   click(324,148)
   if os.getenv('DF3D_JUSTICE_GRAPH_CONNECTED')=='1' then
    click(944,716);click(96,690);click(532,568);record('organization-last-node')
   end
   resize('minimum');record('organizations-minimum')
   resize('default');record('organizations-restored')
  end
  if os.getenv('DF3D_JUSTICE_GRAPH_LAYOUT_WIDE')=='1' then
   click(324,148);assert(#menu.organization_entry==1,'Wide layout fixture requires one organization')
   layout_org=menu.organization_entry[0];layout_original={}
   for _,node in ipairs(layout_org.node)do layout_original[#layout_original+1]=node end
   local root=layout_original[1];local template=layout_original[#layout_original]
   while #layout_org.node>0 do layout_org.node:erase(#layout_org.node-1)end
   layout_org.node:insert('#',root)
   -- Layout-only oracle inputs, after semantic provider/wire comparisons.
   -- Reuse real captions/actors; no gameplay relationships are changed.
   for i=1,32 do
    local node=df.organization_entry_nodest:new();node.actor_entry=template.actor_entry;node.master=root;node.tier=2;node.sort_id=template.sort_id
    node.label=template.label;node.name=template.name;node.status=template.status;node.fcol=template.fcol;node.bcol=template.bcol;node.br=template.br
    layout_added[#layout_added+1]=node;layout_org.node:insert('#',node)
   end
   layout_org.flag.whole=layout_org.flag.whole&~1
   menu.selected_counterintelligence_oen=root;settle();record('layout-wide')
   click(924,340);record('layout-wide-right')
   click(896,340);record('layout-wide-last')
   click(96,340);record('layout-wide-left')
  end
  local output=assert(io.open(out..'/justice-graph-presentation.json','w'));output:write(json.encode(states));output:close()
 end
end,debug.traceback)
if layout_org then
 while #layout_org.node>0 do layout_org.node:erase(#layout_org.node-1)end
 for _,node in ipairs(layout_original)do layout_org.node:insert('#',node)end
 layout_org.flag.whole=layout_org.flag.whole&~1
 df.global.game.main_interface.info.justice.selected_counterintelligence_oen=layout_original[1]
 for _,node in ipairs(layout_added)do node:delete()end
end
if #added_reports>0 then
 gui.simulateInput(view,'LEAVESCREEN');settle()
 while #reports>report_count do reports:erase(#reports-1)end
 for _,report in ipairs(added_reports)do
  while #report.details>0 do local line=report.details[#report.details-1];report.details:erase(#report.details-1);line:delete()end
  report:delete()
 end
 gui.simulateInput(view,'D_JUSTICE');settle()
end
entity.evidence_repository=original;reopen()
while #repository.hf_file>0 do repository.hf_file:erase(#repository.hf_file-1)end
for _,file in ipairs(files)do file:delete()end
repository:delete();assert(ok,err)
