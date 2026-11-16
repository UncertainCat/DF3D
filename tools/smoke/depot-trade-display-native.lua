-- Disposable oracle: compare the owned page to native vectors and visible cells.
local trade,display=...
local gps=df.global.gps
local result={sides={},visible_captions=0}
local function cells(x,y,count)
 local value={};for column=x,x+count-1 do local ch=dfhack.screen.readTile(column,y).ch;value[#value+1]=ch>=32 and string.char(ch)or' 'end
 return table.concat(value)
end
for side=0,1 do
 local expected={}
 for group,kind in ipairs(trade.current_type_a_type[side])do if trade.current_type_a_on[side][group]then
  expected[#expected+1]={group=true,id=-1,parent=-1,type=kind,subtype=trade.current_type_a_subtype[side][group],flags=trade.current_type_a_flag[side][group].whole,expanded=trade.current_type_a_expanded[side][group]}
  if trade.current_type_a_expanded[side][group]then
   local children=true;local parent=-1
   for i,item in ipairs(trade.good[side])do
    local flags=trade.goodflag[side][i];local visible
    if flags.contained then visible=children
    else visible=item:getType()==kind and item:getSubtype()==trade.current_type_a_subtype[side][group];children=visible and not flags.container_collapsed;parent=visible and item.id or -1 end
    if visible then expected[#expected+1]={group=false,id=item.id,parent=flags.contained and parent or -1,type=item:getType(),subtype=item:getSubtype(),flags=flags.whole,expanded=not flags.container_collapsed}end
   end
  end
 end end
 local page=assert(display[side+1]);assert(page.total==#expected and #page.rows==#expected and #expected*3==trade.i_height[side] and page.bounded_page_verified)
 for index,row in ipairs(page.rows)do
  for key,value in pairs(expected[index])do assert(row[key]==value,'Trade page '..key..' differs at '..side..':'..index)end
  assert(type(row.caption)=='string' and #row.caption>0)
  local y=16+(index-1)*3
  if trade.havetalker==1 and trade.stillunloading==0 and y+1<=54 then
   local x=(side==0 and 6 or 65)+(row.group and 2 or 7)+(row.parent>=0 and 2 or 0)
   local text=dfhack.utf2df(row.caption):gsub('[%z\1-\31]',' ')
   local count=math.min(#text,12)
   assert(cells(x,y,count)==text:sub(1,count),'Native caption prefix differs: '..side..':'..index..' '..row.caption..' observed '..dfhack.df2utf(cells(x,y,count)))
   result.visible_captions=result.visible_captions+1
  end
 end
 result.sides[side+1]=page
end
return result
