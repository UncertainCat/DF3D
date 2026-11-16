-- Paused diagnostic session lifecycle against native pointer/keyboard actions.
local view,b,unit,trade,click=...
local gui=require('gui');local json=require('json')
local result={cases={}}
local function probe(action,...)
 local args={...};for i,v in ipairs(args)do args[i]=tostring(v)end
 local output,code=dfhack.run_command_silent('df3d','trade-session-probe',action,table.unpack(args))
 assert(code==0,output);return json.decode(output)
end
local function native()
 local sides={}
 for side=0,1 do
  local row={items={},flags={},amounts={},groups={},height=trade.i_height[side]}
  for i,item in ipairs(trade.good[side])do row.items[#row.items+1]=item.id;row.flags[#row.flags+1]=trade.goodflag[side][i].whole;row.amounts[#row.amounts+1]=trade.good_amount[side][i]end
  for i,kind in ipairs(trade.current_type_a_type[side])do row.groups[#row.groups+1]={type=kind,subtype=trade.current_type_a_subtype[side][i],expanded=trade.current_type_a_expanded[side][i],on=trade.current_type_a_on[side][i],flags=trade.current_type_a_flag[side][i].whole}end
  sides[#sides+1]=row
 end
 return sides
end
local function compare(label,row)
 if row.display_verified then
  assert(row.summary_verified and row.header_summary_verified,'Owned header/footer summary was not verified')
  for i,text in ipairs(row.header_lines)do
   local chars={};for x=17,118 do local tile=dfhack.screen.readTile(x,6+i);chars[#chars+1]=tile.ch>=32 and tile.ch<=255 and string.char(tile.ch)or' 'end
   local bytes=dfhack.utf2df(text);assert(bytes..string.rep(' ',102-#bytes)==table.concat(chars),'Session header differs from native')
  end
 end
 assert(row.status==0 and json.encode(row.sides)==json.encode(native()),'Session/native mismatch: '..label)
 assert(row.filters[1]==dfhack.df2utf(trade.item_filter[0]) and row.filters[2]==dfhack.df2utf(trade.item_filter[1]))
 result.cases[#result.cases+1]={label=label,state=row}
end
assert(trade.open and trade.havetalker==1 and #trade.good[0]>0 and #trade.mer.goods==0)
local item=trade.good[0][0];local flags=item.flags.whole
local position={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}
local title=trade.title;local appraisal=trade.handle_appraisal;local lists=trade.buildlists
local active=df.global.game.main_interface.view_sheets.active_id
local ok,err=xpcall(function()
 local row=probe('open',b.id,0);compare('open',row)
 local session,revision=row.session,row.revision
 click(468,238);row=probe('item',session,revision,0,item.id);compare('selected',row)
 assert(row.revision==revision+1);revision=row.revision
 assert(probe('item',session,revision-1,0,item.id).status==1)
 assert(probe('item',session,revision,0,2147483647).status==1)
 compare('stale-and-invalid-unchanged',probe('read',session,revision))
 click(100,166);for byte in ('iron'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
 view:render(dfhack.getTickCount());assert(trade.item_filter[0]=='IRON')
 row=probe('filter',session,revision,0,'IRON');compare('filtered',row);revision=row.revision
 for i=1,4 do gui.simulateInput(view,'STRING_A000')end
 view:render(dfhack.getTickCount());if trade.entering_item_filter[0]then click(100,166)end
 row=probe('filter',session,revision,0,'');compare('filter-cleared',row);revision=row.revision
 click(468,238);row=probe('item',session,revision,0,item.id);compare('selection-cleared',row);revision=row.revision
 compare('read-repeat',probe('read',session,revision))
 assert(probe('close',session).status==3)
 row=probe('open',b.id,0);assert(row.session~=session);compare('reopened',row)
 assert(probe('close',session).status==1 and probe('item',session,revision,0,item.id).status==1)
 session=row.session;revision=row.revision
 item.flags.trader=false
 assert(probe('read',session,revision).status==2,'Changed goods source retained old draft')
 item.flags.whole=flags
 assert(probe('read',session,revision).status==1)
 row=probe('open',b.id,0);compare('after-source-retirement',row)
 unit.pos.x=0;unit.pos.y=0;unit.pos.z=0
 assert(probe('read',row.session,row.revision).status==2,'Missing trader retained old draft')
 unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
 row=probe('open',b.id,0);compare('after-trader-retirement',row)
 assert(probe('epoch',row.session,row.revision).status==2)
 assert(probe('read',row.session,row.revision).status==1)
 assert(trade.title==title and trade.handle_appraisal==appraisal and trade.buildlists==lists and df.global.game.main_interface.view_sheets.active_id==active and #trade.mer.goods==0)
 result.stale_rejected=true;result.source_retired=true;result.trader_retired=true;result.epoch_retired=true
end,debug.traceback)
item.flags.whole=flags;unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
if not ok then error(err)end
return result
