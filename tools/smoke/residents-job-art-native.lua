-- Protected native oracle only. Runtime providers must never read this menu.
local out,view,info,job,button,evidence,owner=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local m=df.global.game.main_interface;local art=m.image_creator;local g=df.global.gps
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function label(text)
 for _,line in ipairs(lines())do local x=line.text:find(text,1,true);if x then click(x-1,line.y);return end end
 error('Missing artwork label: '..text)
end
local function effect()return {type=job.art_spec.type,id=job.art_spec.id,subid=job.art_spec.subid,requirements=#job.job_items.elements,specdata=job.specdata.hist_figure_id,art_open=art.open,details_open=m.job_details.open,info_open=info.open}end
evidence.building_id=m.job_details.bld.id
evidence.artwork={};local result=evidence.artwork
local function save()
 local f=assert(io.open(out..'/residents-job-art-reference.json','w'));f:write(json.encode(evidence));f:close()
end
local function shot(name)
 save();local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Job art capture timeout');script.sleep(1,'frames')end
end
settle()
if os.getenv('DF3D_RESIDENTS_JOB_ART_BEGIN')=='1' then
 assert(m.job_details.current_option==3 and not art.open,'Expected native improvement picker');click(10,11)
end
assert(art.open and art.ics.jb==job and not art.ics.wq,'Job did not open job-backed artwork')
result.context=art.context;result.header=dfhack.df2utf(art.header);result.root=lines();result.before=effect()
local wire_original=owner.job.current_job
if os.getenv('DF3D_RESIDENTS_JOB_ART_WIRE')=='1' then
 owner.job.current_job=job
 if os.getenv('DF3D_RESIDENTS_JOB_ART_BEGIN')=='1' then job.specdata.improvement=3 end
end
shot('residents-job-art-root')
owner.job.current_job=wire_original
if os.getenv('DF3D_RESIDENTS_JOB_ART_WIRE')=='1' then result.wire_effect=effect() end
if os.getenv('DF3D_RESIDENTS_JOB_ART_PROVIDER')=='1' then
 result.provider={}
 for kind,caption in ipairs({'Related to historical figure','Related to site','Related to civilization or other group'})do
  -- Cold owned read before native populates that subject list.
  local old=owner.job.current_job;owner.job.current_job=job
  local ok,text,rc=pcall(dfhack.run_command_silent,'df3d','residents-job-art-subjects-probe',tostring(owner.id),tostring(kind))
  owner.job.current_job=old
  assert(ok and rc==0,'Owned job art subject read failed: '..tostring(text))
  local observed=json.decode(text)
  assert(art.open and art.current_option==-1 and art.ics.jb==job,'Owned read changed native artwork state')
  assert(observed.caption==result.header and observed.job_id==job.id,'Owned job art header/identity differs')
  label(caption)
  local rows=kind==1 and art.hf or kind==2 and art.st or art.ent
  assert(#observed.ids==#rows,'Owned subject count differs')
  for i,row in ipairs(rows)do assert(observed.ids[i+1]==row.id,'Owned subject order differs')end
  result.provider[#result.provider+1]={kind=kind,count=#rows,revision=observed.revision,list_revision=observed.list_revision,matched=true}
  df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
  df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
  assert(art.open and art.current_option==-1,'Subject Back did not return to artwork root')
 end
end
if os.getenv('DF3D_RESIDENTS_JOB_ART_PAGES')=='1' then
 local function read(page,cursor,columns)
  local old=owner.job.current_job;owner.job.current_job=job
  local ok,text,rc=pcall(dfhack.run_command_silent,'df3d','residents-job-art-page-probe',tostring(owner.id),tostring(page),tostring(cursor),tostring(columns))
  owner.job.current_job=old;assert(ok and rc==0,'Owned artwork page failed: '..tostring(text));return json.decode(text)
 end
 result.pages={};local root=read(-1,0,0)
 assert(root.caption==result.header and #root.rows==6,'Owned artwork root differs')
 for _,row in ipairs(root.rows)do
  local found=false;for _,line in ipairs(result.root)do if line.text:find(row.caption,1,true)then found=true;break end end
  assert(found,'Owned artwork root caption not native')
 end
 for _,page in ipairs({1,2,3,5})do
  local caption=page==1 and 'Related to historical figure' or page==2 and 'Related to site' or page==3 and 'Related to civilization or other group' or 'Existing image'
  local first=read(page,0,0);label(caption)
  local rows=page==1 and art.hf or page==2 and art.st or page==3 and art.ent or art.art_image
  assert(first.total==#rows and #first.rows==math.min(128,#rows),'Owned artwork page count differs')
  for i,row in ipairs(first.rows)do assert(row.id==(page==5 and i-1 or rows[i-1].id),'Owned artwork page ID differs')end
  if first.next_cursor>0 then
   local next=read(page,first.next_cursor,0)
   assert(next.list_revision==first.list_revision and next.total==first.total,'Artwork page revision drift')
   for i,row in ipairs(next.rows)do assert(row.id==(page==5 and first.next_cursor+i-1 or rows[first.next_cursor+i-1].id),'Second artwork page ID differs')end
  end
  local preview={};local columns=0
  if #rows>0 then
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=200;g.precise_mouse_y=190;g.mouse_x=25;g.mouse_y=15;view:render(dfhack.getTickCount())
   columns=art.last_selected_box_width
   for _,line in ipairs(art.selected_box.text)do preview[#preview+1]=dfhack.df2utf(line.value)end
   assert(columns>0,'Native hover did not produce preview width')
   local hovered=read(page,0,columns)
   assert(json.encode(hovered.preview)==json.encode(preview),'Owned native preview differs')
   assert(hovered.stale_list_rejected,'Artwork page accepted stale list receipt')
  end
  result.pages[#result.pages+1]={page=page,total=first.total,rows=#first.rows,next_cursor=first.next_cursor,columns=columns,preview=preview,matched=true}
  df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
  df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
  assert(art.open and art.current_option==-1,'Artwork page Back failed')
 end
end
local function adapter(kind,id)
 if os.getenv('DF3D_RESIDENTS_JOB_ART_EFFECTS')~='1' then return nil end
 local old=owner.job.current_job;owner.job.current_job=job
 local ok,text,rc=pcall(dfhack.run_command_silent,'df3d','residents-job-art-copy-probe',tostring(owner.id),tostring(kind),tostring(id))
 owner.job.current_job=old;assert(ok and rc==0,'Owned artwork effect adapter failed: '..tostring(text))
 local value=json.decode(text)
 for _,field in ipairs({'applied','stale_revision_rejected','wrong_job_rejected','wrong_holder_rejected','rejections_unchanged','source_unchanged'})do assert(value[field],'Artwork adapter failed '..field)end
 if kind~=0 then assert(value.stale_list_rejected,'Artwork stale list accepted')end
 if kind~=-1 then assert(value.missing_subject_rejected,'Missing artwork subject accepted')end
 return value
end
local function compare(value,actual)
 if not value then return end
 for key,wanted in pairs(value.after)do assert(actual[key]==wanted,'Native artwork effect differs: '..key)end
end
label('Related to historical figure')
assert(art.current_option==1 and #art.hf>0,'Figure page did not open')
result.figures={};for _,hf in ipairs(art.hf)do result.figures[#result.figures+1]=hf.id end
result.figure_lines=lines();shot('residents-job-art-figures')
local chosen=art.hf[0].id
if result.wire_effect then
 assert(result.wire_effect.type==0 and result.wire_effect.id==chosen and result.wire_effect.subid==result.before.subid,'Wire figure assignment differs from native')
 if os.getenv('DF3D_RESIDENTS_JOB_ART_BEGIN')=='1' then assert(result.wire_effect.specdata==0,'Wire Image entry did not apply')end
end
-- Native first subject row below the filter, verified in captured layout.
local figure_adapter=adapter(1,chosen)
click(10,14)
result.figure_effect=effect();result.figure_choice=chosen;result.figure_adapter=figure_adapter;compare(figure_adapter,result.figure_effect)
assert(job.art_spec.type==0 and job.art_spec.id==chosen and job.art_spec.subid==result.before.subid,'Figure selection effect differs')
assert(not art.open and not m.job_details.open and info.open,'Figure selection did not return to Residents')
local function reopen_art()
 click(button.rect.x1+1,button.rect.y1+1)
 if not art.open and m.job_details.current_option==3 then click(10,11) end
 assert(art.open and art.ics.jb==job,'Artwork did not reopen')
end
reopen_art()
if os.getenv('DF3D_RESIDENTS_JOB_ART_EFFECTS')=='1' then
 result.other_effects={}
 for _,kind in ipairs({2,3,5})do
  label(kind==2 and 'Related to site' or kind==3 and 'Related to civilization or other group' or 'Existing image')
  local rows=kind==2 and art.st or kind==3 and art.ent or art.art_image;assert(#rows>0,'Missing native artwork effect choice')
  local subject=kind==5 and 0 or rows[0].id
  local expected=adapter(kind,subject);click(10,14);local actual=effect();compare(expected,actual)
  assert(not art.open and not m.job_details.open and info.open,'Artwork selection did not return to Residents')
  result.other_effects[#result.other_effects+1]={kind=kind,subject=subject,adapter=expected,effect=actual}
  reopen_art()
 end
end
local artist_adapter=adapter(0,-1)
label('Allow artist to choose')
result.artist_effect=effect();result.artist_adapter=artist_adapter;compare(artist_adapter,result.artist_effect)
assert(job.art_spec.type==-1 and job.art_spec.id==-1 and job.art_spec.subid==-1 and not art.open,'Artist choice did not clear specification')
reopen_art()
gui.simulateInput(view,'LEAVESCREEN');settle();result.escape=effect();save()
assert(art.open and info.open,'Artwork Escape changed the native editor')
df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
result.right_click=effect();save()
assert(not art.open and not m.job_details.open and info.open,'Artwork right click did not return to Residents')

if os.getenv('DF3D_RESIDENTS_JOB_ART_EFFECTS')=='1' then
 -- Change only the unlinked diagnostic job; exercise Image's separate entry edit.
 job.job_type=df.job_type.EncrustWithGems;job.specdata.improvement=3
 job.art_spec.type=0;job.art_spec.id=owner.hist_figure_id;job.art_spec.subid=7
 click(button.rect.x1+1,button.rect.y1+1)
 assert(m.job_details.open and m.job_details.current_option==3 and not art.open,'Improvement type page did not open')
 local expected=adapter(-1,-1);click(10,11)
 result.begin_image={adapter=expected,effect=effect(),context=art.context};compare(expected,result.begin_image.effect)
 assert(art.open and art.context==2 and job.specdata.improvement==0 and job.art_spec.subid==7,'Image entry did not preserve native artwork')
 df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
 df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
 result.begin_image.back=effect();save()
 assert(not art.open and not m.job_details.open and info.open and job.specdata.improvement==0,'Image Back lost its entry effect')
end
