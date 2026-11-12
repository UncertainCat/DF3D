local out,probe,click,crime,info,capture=...
local json=require('json');local report=crime.witnesses[0];assert(report)
local original={type=report.type,accused=report.accused_id,witness=report.witness_id}
local function native_rows()
 local rows={}
 local function walk(w)
  if df.widget_text:is_instance(w)then
   local s=dfhack.df2utf(w.str)
   if s:sub(1,9)=='Witness: 'then rows[#rows+1]={witness=s,description=''}
   elseif #rows>0 and s:sub(1,6)=='Date: 'then rows[#rows].date=s
   elseif #rows>0 and s:sub(1,10)=='Reported: 'then rows[#rows].reported=s
   elseif #rows>0 and(s:sub(1,9)=='Accuses: 'or s:sub(1,12)=='Implicates: 'or s:sub(1,4)=='Saw 'or s=='Found the body.')then rows[#rows].description=s end
  end
  if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end end end
 end
 walk(info.justice);return rows
end
local samples={}
if os.getenv('DF3D_JUSTICE_WITNESS_LONG_NAME')=='1'then
 local names={};local seen={}
 local function save(name)
  local _,address=df.sizeof(name);if seen[address]then return end;seen[address]=true
  names[#names+1]={value=name,first=name.first_name,nickname=name.nickname}
 end
 local unit=assert(df.unit.find(report.witness_id));save(unit.name)
 for _,id in ipairs{report.witness_ihf.hfid,report.witness_ihf.visual_hfid,report.witness_ihf.historical_hfid}do
  local hf=df.historical_figure.find(id);if hf then save(hf.name)end
 end
 assert(#report.witness_ihf.all_witnessed_ident==0,'Long-name fixture requires no recorded alias')
 local ok,err=xpcall(function()
  for _,name in ipairs(names)do name.value.first_name=string.rep('Longwitness',9);name.value.nickname=''end
  click(100,202);click(100,166)
  local native=native_rows();local owned=probe('justice-witness-text-probe',9)
  assert(json.encode(native)==json.encode(owned),'Long witness text differs from native')
  local widgets={}
  local function walk(w)
   if df.widget_text_truncated:is_instance(w)and w.original_str:find('Longwitness',1,true)then
    assert(w.str==w.original_str and w.min_w==#w.original_str,'Native long caption unexpectedly shortened')
    widgets[#widgets+1]={original=dfhack.df2utf(w.original_str),text=dfhack.df2utf(w.str),min_w=w.min_w,rect={w.rect.x1,w.rect.y1,w.rect.x2,w.rect.y2}}
   end
   if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do if not df.widget_tabs:is_instance(w)or i-1==w.cur_idx then walk(c)end end end
  end
  walk(info.justice);assert(#widgets>0,'Long witness absent')
  local f=assert(io.open(out..'/justice-witness-long-name.json','w'));f:write(json.encode({native=native,owned=owned,widgets=widgets}));f:close()
  capture('justice-witness-long-name')
 end,debug.traceback)
 for _,name in ipairs(names)do name.value.first_name=name.first;name.value.nickname=name.nickname end
 click(100,202);click(100,166);assert(ok,err);return
end
local ok,err=xpcall(function()
 for _,kind in ipairs{-2,-1,0,1,2,3,4,5,6,7}do
  report.type=kind==-2 and original.type or(kind==7 and 6 or kind)
  report.accused_id=(kind==-2 or kind==7)and original.accused or -1
  click(100,202);click(100,166)
  local native=native_rows();local owned=probe('justice-witness-text-probe',9)
  samples[#samples+1]={scenario=kind,native=native,owned=owned}
  local f=assert(io.open(out..'/justice-witnesses.json','w'));f:write(json.encode(samples));f:close()
  assert(#native==#crime.witnesses,'Missing native witness rows')
  assert(json.encode(native)==json.encode(owned),'Native witness text/order differs for '..kind)
 end
end,debug.traceback)
report.type=original.type;report.accused_id=original.accused;report.witness_id=original.witness
click(100,202);click(100,166)
assert(ok,err)
