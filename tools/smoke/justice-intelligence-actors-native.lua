-- Controlled native oracle: owned evidence replaces the repository only in the
-- paused disposable clone. Actor labels are obtained from native semantic names.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local entity=df.global.plotinfo.main.fortress_entity;assert(entity)
local original=entity.evidence_repository;local repository=df.evidence_repositoryst:new();local files={}
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function reopen()
 gui.simulateInput(view,'LEAVESCREEN');settle();gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then click(711,430)end
 tab('Intelligence')
end
local ok,err=xpcall(function()
 local ids,seen={},{}
 for _,unit in ipairs(df.global.world.units.active)do
  if unit.hist_figure_id>=0 and not seen[unit.hist_figure_id] and unit.name.has_name then ids[#ids+1]=unit.hist_figure_id;seen[unit.hist_figure_id]=true;if #ids==4 then break end end
 end
 assert(#ids==4,'Actor fixture requires four named historical figures');table.sort(ids)
 for i,id in ipairs(ids)do
  local file=df.evidence_hf_filest:new();file.hfid=id;file.flags.whole=i==1 and 8 or 0;file.temp_flags.whole=123
  if i==3 then file.used_identity:insert('#',2147483647)end
  if i==4 then assert(#df.global.world.identities.all>0);file.used_identity:insert('#',df.global.world.identities.all[0].id)end
  repository.hf_file:insert('#',file);files[#files+1]=file
 end
 entity.evidence_repository=repository;reopen();click(220,148)
 local menu=df.global.game.main_interface.info.justice;assert(menu.counterintelligence_mode==df.counterintelligence_mode_type.ACTORS,'Actors tab did not open')
 for _,file in ipairs(files)do file.temp_flags.whole=123 end
 local before={};for _,file in ipairs(files)do local n,p=df.sizeof(file);before[#before+1]={n=n,p=p,data=bytes(p,n)}end
 local supplied=probe('justice-intelligence-actors-probe');local native={}
 for _,row in ipairs(menu.actor_entry)do
  local aliases={};for _,id in ipairs(row.alias_identity_id)do aliases[#aliases+1]=id end
  native[#native+1]={historical_figure=row.hf.id,identity=row.iden and row.iden.id or -1,name=dfhack.df2utf(row.list_name),aliases=aliases}
 end
 for _,entry in ipairs(before)do assert(bytes(entry.p,entry.n)==entry.data,'Actor provider modified evidence')end
 local data={native=native,provider=supplied,empty_filter=probe('justice-intelligence-actors-probe','zznomatch')}
 local f=assert(io.open(out..'/justice-intelligence-actors.json','w'));f:write(json.encode(data));f:close()
 assert(json.encode(native)==json.encode(supplied),'Native actor names/order/identity differ')
 assert(#data.empty_filter==0,'Actor empty search mismatch')
 capture('justice-intelligence-actors')
end,debug.traceback)
entity.evidence_repository=original;reopen()
while #repository.hf_file>0 do repository.hf_file:erase(#repository.hf_file-1)end
for _,file in ipairs(files)do file:delete()end
repository:delete();assert(ok,err)
