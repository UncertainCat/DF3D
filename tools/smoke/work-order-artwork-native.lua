-- Native oracle only, run by the protected owned unsaved lane.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local m=df.global.game.main_interface
local function key(k)gui.simulateInput(view,k);view:render(dfhack.getTickCount())end
local function mouse(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
 df.global.enabler.mouse_lbut_lift=0;key('_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function values(vector)local result={};for _,v in ipairs(vector)do result[#result+1]=v end;return result end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local row={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;row[#row+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(row)):gsub('%s+$','')}
 end
 return result
end
local observations={}
local function click_label(label,x_override)
 for _,row in ipairs(lines())do local x=row.text:find(label,1,true);if x then mouse(x_override or ((x-1)*8+4),row.y*12+6);return true end end
 return false
end
local function back()
 df.global.enabler.mouse_rbut_lift=0;key('_MOUSE_R')
 df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1
end
local function shot(name)
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
 observations[#observations+1]={name=name,lines=lines(),page=m.image_creator.current_option,open=m.image_creator.open}
 local f=assert(io.open(out..'/work-order-artwork-reference.json','w'));f:write(json.encode(observations));f:close()
 f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'artwork capture timeout');script.sleep(1,'frames')end
end
key('D_ORDERS');assert(m.info.open)
assert(click_label('Encrust',584),'Fixture needs visible Encrust order')
local details=m.job_details;assert(details.open and details.wq)
local order=details.wq;local before={spec=order.specdata.hist_figure_id,typ=order.art_spec.type,id=order.art_spec.id,subid=order.art_spec.subid}
local option;for i,kind in ipairs(details.option)do if kind==3 then option=i;break end end
assert(option);mouse(200,106+option*36);assert(details.current_option==3)
mouse(200,142);local art=m.image_creator;assert(art.open)
before={spec=order.specdata.hist_figure_id,typ=order.art_spec.type,id=order.art_spec.id,subid=order.art_spec.subid}
assert(click_label('Specify a new image'));assert(art.current_option==6)
assert(click_label('Creature'));assert(art.current_option==7)
mouse(300,190);assert(art.current_option==6 and #art.new_image.elements==1)
back();shot('work-order-artwork-discard')
assert(click_label('Keep working'),'Keep working absent');assert(art.open and #art.new_image.elements==1)
shot('work-order-artwork-kept')
back();key('LEAVESCREEN');shot('work-order-artwork-discard-escape')
assert(click_label('Keep working'),'Escape changed confirmation')
back();back();shot('work-order-artwork-discard-right')
-- Record whether a second right click cancels confirmation or leaves it visible.
local pending=false;for _,row in ipairs(lines())do if row.text:find('Keep working',1,true)then pending=true end end
if not pending then back()end
assert(click_label('Leave editor and discard data'),'Discard control absent')
shot('work-order-artwork-discarded')
assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Discard changed order')
if os.getenv('DF3D_WORK_ORDER_ARTWORK_WIRE')=='1' then
 local f=assert(io.open(out..'/work-order-artwork-expected.json','w'));f:write(json.encode({id=order.id,option=option}));f:close()
 -- The launcher uses the same owned process lifetime and a bounded30 FPS client.
 f=assert(io.open(out..'/shot.tmp','w'));f:write('work-order-artwork-wire');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+65000
 while true do local ack=io.open(out..'/ack-work-order-artwork-wire');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'artwork viewer timeout');script.sleep(1,'frames')end
 assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Viewer discard changed order')
 f=assert(io.open(out..'/work-order-artwork-wire-result.json'));local result=json.decode(f:read('*a'));f:close();assert(result.success,'Artwork viewer failed')
end
records[#records+1]={name='work-order-artwork-discard',screens=#observations,second_right_keeps_confirmation=pending,order_unchanged=true}
