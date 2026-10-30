-- Native header reference only, in a paused disposable fortress. No jobs run.
local unit,view=...
local saved_job=unit.job.current_job
local saved_profession=unit.custom_profession
local saved_nickname=unit.name.nickname
local json=require('json')
local job,cases
cases={}
local function observe(name)
 view:render(0)
 local rows={}
 for y=6,12 do
  local chars,colors={},{}
  for x=66,98 do
   local pen=dfhack.screen.readTile(x,y)
   chars[#chars+1]=pen.ch>=32 and string.char(pen.ch) or ' '
   colors[#colors+1]=pen.fg+(pen.bold and 8 or 0)
  end
  local text=table.concat(chars):gsub('%s+$','')
  while #colors>#text do table.remove(colors)end
  rows[#rows+1]={y=y,text=dfhack.df2utf(text),colors=colors}
 end
 local protected,seen={},{}
 local function protect(object)
  if object then
   local size,address=df.sizeof(object)
   if not seen[address]then seen[address]=true;protected[#protected+1]={object=object,size=size,address=address}end
  end
 end
 local function protect_figure(hf)
  if not hf then return end
  protect(hf)
  for _,link in ipairs(hf.entity_links)do
   protect(link)
   local entity=df.historical_entity.find(link.entity_id)
   if entity then
    protect(entity)
    for _,assignment in ipairs(entity.positions.assignments)do protect(assignment)end
    for _,position in ipairs(entity.positions.own)do protect(position)end
   end
  end
  for _,link in ipairs(hf.histfig_links)do protect(link)end
 end
 protect(unit);protect(df.global.game.main_interface.view_sheets);protect(df.global.plotinfo)
 local hf=df.historical_figure.find(unit.hist_figure_id);protect_figure(hf)
 if hf then for _,link in ipairs(hf.histfig_links)do
  if link:getType()==df.histfig_hf_link_type.SPOUSE then protect_figure(df.historical_figure.find(link.target_hf));break end
 end end
 local index=unit.enemy.histfig_vector_idx;unit.enemy.histfig_vector_idx=-1
 for _,copy in ipairs(protected)do copy.bytes=df.new('uint8_t',copy.size);dfhack.internal.memmove(copy.bytes,copy.address,copy.size)end
 local text,status=dfhack.run_command_silent('df3d','unit-header-position-probe',tostring(unit.id))
 local unchanged=true
 for _,copy in ipairs(protected)do
  if dfhack.internal.memcmp(copy.bytes,copy.address,copy.size)~=0 then unchanged=false end
  df.delete(copy.bytes)
 end
 unit.enemy.histfig_vector_idx=index
 assert(status==0,text);assert(unchanged,'header position reader mutated guarded state: '..name)
 local position=json.decode(text)
 assert(position.text==rows[3].text,'header position reader differs from native: '..name)
 -- The native render above has warmed semantic name lookup caches. Unlike the
 -- position-only reader, the shared name/color providers may warm those caches.
 for _,copy in ipairs(protected)do copy.bytes=df.new('uint8_t',copy.size);dfhack.internal.memmove(copy.bytes,copy.address,copy.size)end
 local name_text,name_status=dfhack.run_command_silent('df3d','unit-header-name-probe',tostring(unit.id))
 local name_unchanged=true
 for _,copy in ipairs(protected)do
  if dfhack.internal.memcmp(copy.bytes,copy.address,copy.size)~=0 then name_unchanged=false end
  df.delete(copy.bytes)
 end
 assert(name_status==0,name_text);assert(name_unchanged,'header name reader mutated warmed guarded state: '..name)
 local header=json.decode(name_text)
 local expected=dfhack.utf2df(header.combined):sub(1,33):gsub('%s+$','')
 assert(dfhack.df2utf(expected)==rows[1].text,'header name reader differs from native crop: '..name)
 local translated=dfhack.utf2df('"'..header.translated_name..'"'):sub(1,33):gsub('%s+$','')
 assert(dfhack.df2utf(translated)==rows[2].text,'header translated name differs from native: '..name)
 assert(header.effect==0,'name fixture requires steady color')
 local palette=header.color[1]+8*header.color[3]
 for _,color in ipairs(rows[1].colors)do assert(color==palette,'header name color differs from native: '..name)end
 cases[#cases+1]={name=name,rows=rows,position=position,reader_unchanged=unchanged,cold_histfig_index=true,
  header_name=header,name_reader_unchanged=name_unchanged,name_reference_columns=33}
end
local ok,err=xpcall(function()
 observe('original')
 unit.job.current_job=nil;observe('no-current-job')
 job=df.job:new();job.id=-1;job.job_type=df.job_type.Rest;job.pos:assign(unit.pos)
 unit.job.current_job=job;observe('rest')
 job.flags.on_break=true;observe('rest-on-break')
 job.flags.on_break=false;job.job_type=df.job_type.Sleep;observe('sleep')
 unit.job.current_job=nil
 unit.custom_profession='Header fixture';observe('custom-profession')
 unit.custom_profession=saved_profession
 unit.name.nickname='Header';observe('nickname')
end,debug.traceback)
unit.job.current_job=saved_job
unit.custom_profession=saved_profession
unit.name.nickname=saved_nickname
if job then df.delete(job)end
view:render(dfhack.getTickCount())
assert(ok,err)
return cases
