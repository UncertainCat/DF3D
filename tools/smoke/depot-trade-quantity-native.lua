-- Paused native UI oracle: determine whether this build exposes stack quantities.
local view,trade,click,capture,id=...
local index;for i,item in ipairs(trade.good[1])do if item.id==id then index=i;break end end
assert(index);local item=trade.good[1][index]
local stack=item:getStackSize();assert(stack>1,'Quantity oracle needs an actual stack')
local modifier=df.reinterpret_cast('uint8_t',dfhack.internal.getImageBase()+0x238d0b8)
local previous=modifier.value;local selected=trade.goodflag[1][index].selected
local scroll=trade.scroll_position_item[1];local row=0;local target
for g,kind in ipairs(trade.current_type_a_type[1])do if trade.current_type_a_on[1][g]then
 row=row+3
 for i,good in ipairs(trade.good[1])do if good:getType()==kind and good:getSubtype()==trade.current_type_a_subtype[1][g]then
  if i==index then target=row end;row=row+3
 end end
end end
assert(target);trade.scroll_position_item[1]=target-3;view:render(dfhack.getTickCount())
local result={item=item.id,stack=stack,cases={}}
local ok,err=xpcall(function()
 for _,test in ipairs{{'checkbox',932,0},{'row',650,0},{'shift-checkbox',932,1},{'control-checkbox',932,2}}do
  modifier.value=test[3];local before=trade.goodflag[1][index].selected
  click(test[2],238);modifier.value=previous
  assert(trade.goodflag[1][index].selected~=before,'Native stack click did not toggle selection')
  assert(trade.good_amount[1][index]==0 and trade.entering_amount==0 and item:getStackSize()==stack,'Unexpected quantity editing')
  result.cases[#result.cases+1]={label=test[1],selected=trade.goodflag[1][index].selected,amount=trade.good_amount[1][index],entering_amount=trade.entering_amount,stack=item:getStackSize()}
 end
 capture('depot-trade-whole-stack')
end,debug.traceback)
modifier.value=previous
if trade.goodflag[1][index].selected~=selected then click(932,238)end
trade.scroll_position_item[1]=scroll;view:render(dfhack.getTickCount())
assert(item:getStackSize()==stack and trade.goodflag[1][index].selected==selected)
assert(ok,err);return result
