local out,probe,click,crime,info=...
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
