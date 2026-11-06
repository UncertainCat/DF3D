-- Native diagnostic oracle: the job is a deep clone of an actual queued job.
local out,view,info,job,button,evidence,owner,source=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local details=df.global.game.main_interface.job_details
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function lines()
 local rows={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  rows[#rows+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return rows
end
local function snapshot(target)
 local value={type=target.job_type,material={target.mat_type,target.mat_index},requirements={}}
 for _,item in ipairs(target.job_items.elements)do value.requirements[#value.requirements+1]={item_type=item.item_type,mat_type=item.mat_type,mat_index=item.mat_index,quantity=item.quantity,flags1=item.flags1.whole,flags2=item.flags2.whole,flags3=item.flags3.whole,details=item.job_details_flags.whole,saved_type=item.job_details_mat_type,saved_index=item.job_details_mat_index}end
 return value
end
local function probe(option)
 local previous=owner.job.current_job;owner.job.current_job=job
 local args={'df3d','residents-job-settings-probe',tostring(owner.id)};if option then args[#args+1]=tostring(option)end
 local ok,text,rc=pcall(dfhack.run_command_silent,table.unpack(args));owner.job.current_job=previous
 assert(ok and rc==0,'Production provider failed: '..tostring(text));return json.decode(text)
end
local source_before=json.encode(snapshot(source))
evidence.source_job_id=source.id;evidence.before=snapshot(job);evidence.provider=probe();evidence.pages={}
assert(details.open and details.jb==job and not details.wq and #details.option>1,'Production root did not open')
evidence.root=lines();assert(#details.option==#evidence.provider.options,'Production option count differs')
local function save()
 local f=assert(io.open(out..'/residents-job-production-reference.json','w'));f:write(json.encode(evidence));f:close()
end
local function shot(name)
 save();local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Production capture timeout');script.sleep(1,'frames')end
end
shot('residents-job-production-root')
for i,option in ipairs(evidence.provider.options)do
 assert(details.option[i-1]==option.kind and details.option_index[i-1]==option.index,'Production option differs')
 if option.kind==0 then
  local found=false
  for _,line in ipairs(lines())do local x=line.text:find(option.caption,1,true);if x then click(x-1,line.y);found=true;break end end
  assert(found and details.current_option==0 and details.current_option_index==option.index,'Native input option did not open')
  local actual=probe(i-1)
  assert(#actual.materials==#details.material,'Production material count differs')
  for j,row in ipairs(actual.materials)do assert(row.type==details.material[j-1] and row.index==details.matgloss[j-1] and row.count==details.material_count[j-1],'Production material ordering/count differs')end
  evidence.pages[#evidence.pages+1]={option=i-1,provider=actual,lines=lines()};shot('residents-job-production-input-'..(i-1))
  gui.simulateInput(view,'LEAVESCREEN');settle()
  if not details.open then click(button.rect.x1+1,button.rect.y1+1)end
  assert(details.open and details.current_option==-1,'Production Back did not restore root')
 end
end
evidence.after=snapshot(job);evidence.source_unchanged=json.encode(snapshot(source))==source_before
assert(evidence.source_unchanged and json.encode(evidence.before)==json.encode(evidence.after),'Production navigation changed job requirements')
save()
if os.getenv('DF3D_RESIDENTS_JOB_PRODUCTION_WIRE')=='1' then
 local previous=owner.job.current_job;owner.job.current_job=job
 shot('residents-job-production-wire');owner.job.current_job=previous
 assert(json.encode(snapshot(job))==json.encode(evidence.before),'Production navigation client changed requirements')
end
gui.simulateInput(view,'LEAVESCREEN');settle()
