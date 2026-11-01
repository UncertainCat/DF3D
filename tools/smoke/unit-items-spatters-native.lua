-- Native formatter boundary cases on an owned paused clone; restore every input.
local unit,pointer,read=...
assert(#unit.body.spatters==1,'Expected single-spatter fixture')
local spatter=unit.body.spatters[0]
local saved={size=spatter.base.size,part=spatter.body_part_id,flags=spatter.flags.whole}
local function restore()
 spatter.base.size=saved.size;spatter.body_part_id=saved.part;spatter.flags.whole=saved.flags
end
local function line(y)
 local text={}
 for x=61,111 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256) or ' 'end
 return dfhack.df2utf(table.concat(text)):match('^%s*(.-)%s*$')
end
local cases={}
local ok,err=xpcall(function()
 for _,case in ipairs{{'size-24',24},{'size-25',25},{'size-49',49},{'size-50',50},
   {'no-body-part',saved.size,-1},{'internal',saved.size,nil,true}}do
  restore();spatter.base.size=case[2]
  if case[3]then spatter.body_part_id=case[3]end
  if case[4]then spatter.flags.external=false end
  local result=read();pointer(400,400)
  local y=18+#unit.inventory*3
  local row=result.spatters[1]
  local caption,part=line(y),line(y+1)
  cases[#cases+1]={name=case[1],native_caption=caption,native_body_part=part,
   reader=row,reader_count=#result.spatters,guards_unchanged=result.guards_unchanged}
  if case[4]then assert(#result.spatters==0 and caption=='' and part=='','Internal spatter visible')
  else
   assert(#result.spatters==1 and row.caption==caption,'Spatter caption differs: '..case[1])
   assert(row.body_part_caption==part,'Spatter body part differs: '..case[1])
  end
 end
end,debug.traceback)
restore();pointer(400,400)
assert(ok,err)
return cases
