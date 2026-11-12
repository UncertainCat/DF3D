-- Compare the owned collector with native Justice in a disposable paused clone.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local entity=df.global.plotinfo.main.fortress_entity;assert(entity)
local original=entity.evidence_repository;local repository=df.evidence_repositoryst:new();local files={}
local function reopen()
 gui.simulateInput(view,'LEAVESCREEN');settle();gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then
  g.precise_mouse_x=711;g.precise_mouse_y=430;g.mouse_x=711//8;g.mouse_y=430//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 end
 tab('Intelligence')
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
  result.actors[#result.actors+1]={historical_figure=row.hf and row.hf.id or -1,identity=row.iden and row.iden.id or -1,name=dfhack.df2utf(row.list_name),aliases=ids(row.alias_identity_id),principal_organization=index(menu.base_organization_entry,row.principle_org),organizations=orgs,plots=plots}
 end
 for _,row in ipairs(menu.base_organization_entry)do
  local value={name=dfhack.df2utf(row.list_name),principal_actor=index(menu.base_actor_entry,row.principle_actor_entry),nodes={}}
  for _,node in ipairs(row.node)do
   value.nodes[#value.nodes+1]={actor=index(menu.base_actor_entry,node.actor_entry),parent=index(row.node,node.master),sort=node.sort_id,tier=node.tier,descendants=node.descendant_sum,label=dfhack.df2utf(node.label),name=dfhack.df2utf(node.name),status=dfhack.df2utf(node.status),foreground=node.fcol,background=node.bcol,bright=node.br}
  end
  result.organizations[#result.organizations+1]=value
 end
 for _,row in ipairs(menu.base_plot_entry)do result.plots[#result.plots+1]={agreement=row.agreement and row.agreement.id or -1,master=row.master_hfid,name=dfhack.df2utf(row.list_name)}end
 return result
end
local ok,err=xpcall(function()
 entity.evidence_repository=repository
 local empty=probe('justice-intelligence-graph-probe')
 assert(#empty.actors==0 and #empty.organizations==0 and #empty.plots==0,'Empty evidence invented graph entries')
 local chosen
 for _,agreement in ipairs(df.global.world.agreements.all)do
  local intrigue=false
  for _,detail in ipairs(agreement.details)do if detail.type>=5 and detail.type<=15 then intrigue=true;break end end
  if intrigue and #agreement.parties>=2 then
   local count=0;for _,party in ipairs(agreement.parties)do for _,id in ipairs(party.histfig_ids)do if df.historical_figure.find(id)then count=count+1 end end end
   if count>=2 then chosen=agreement;break end
  end
 end
 assert(chosen,'Fixture requires an existing intrigue agreement with two historical figures')
 local hfids,seen={},{}
 for _,party in ipairs(chosen.parties)do for _,id in ipairs(party.histfig_ids)do if not seen[id] and df.historical_figure.find(id)then hfids[#hfids+1]=id;seen[id]=true end end end
 table.sort(hfids)
 for _,id in ipairs(hfids)do
  local file=df.evidence_hf_filest:new();file.hfid=id;file.flags.whole=8
  file.agreement:insert('#',chosen.id)
  repository.hf_file:insert('#',file);files[#files+1]=file
 end
 repository.foiled_plot_agreements:insert('#',chosen.id)
 entity.evidence_repository=repository;reopen()
 local menu=df.global.game.main_interface.info.justice
 local native=native_graph(menu)
 assert(#native.plots>0 and #native.organizations>0,'Fixture did not produce a populated graph')
 local guards={}
 local function guard(value)local n,p=df.sizeof(value);guards[#guards+1]={n=n,p=p,data=bytes(p,n)}end
 for _,file in ipairs(files)do file.temp_flags.whole=123;guard(file)end
 for _,id in ipairs(hfids)do guard(df.historical_figure.find(id))end
 guard(repository);guard(entity);guard(menu);guard(chosen)
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
end,debug.traceback)
entity.evidence_repository=original;reopen()
while #repository.hf_file>0 do repository.hf_file:erase(#repository.hf_file-1)end
for _,file in ipairs(files)do file:delete()end
repository:delete();assert(ok,err)
