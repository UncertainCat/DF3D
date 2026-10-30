-- Native header reference only, in a paused disposable fortress. No jobs run.
local unit,view=...
local saved_job=unit.job.current_job
local saved_profession=unit.custom_profession
local saved_nickname=unit.name.nickname
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
 cases[#cases+1]={name=name,rows=rows}
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
