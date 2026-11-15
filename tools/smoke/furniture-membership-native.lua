-- Paused disposable fixture. DFHack moves one temporary item; runtime only reads.
local out,view,records,buildings,select_map,capture=...
local json=require('json');local script=require('gui.script');local gui=require('gui')
local entry
for _,row in ipairs(buildings)do if row.type==3 then entry=row;break end end
assert(entry,'Membership probe needs a coffin')
local b=assert(df.building.find(entry.id));assert(#b.contained_items==2 and b.contained_items[1].use_mode==0)
local item=b.contained_items[1].item;local flags=item.flags.whole
local position={x=item.pos.x,y=item.pos.y,z=item.pos.z};local detached=false;local cancelled=false
local reference={building_id=b.id,item_id=item.id,scope='Paused controlled temporary-item removal/restoration; diagnostic clears in_building for DFHack moveToGround, then restores original flags. No burial simulation.'}
local function remove()
 -- detachItem rejects every in_building item, including temporary coffin
 -- contents. This is fixture setup only, never a product action path.
 local marked=item.flags.in_building;item.flags.in_building=false
 local moved=dfhack.items.moveToGround(item,{x=b.centerx,y=b.centery,z=b.z})
 if not moved then item.flags.in_building=marked end
 assert(moved,'Could not detach temporary item')
 detached=true;assert(#b.contained_items==1)
end
local function restore()
 if not detached then return end
 assert(dfhack.items.moveToBuilding(item,b,0,true),'Could not restore temporary item')
 item.flags.whole=flags;item.pos:assign(position);detached=false
 assert(#b.contained_items==2 and b.contained_items[1].item.id==item.id)
end
local function wait_marker(name)
 local deadline=dfhack.getTickCount()+90000
 while not cancelled do
  local f=io.open(out..'/'..name);if f then f:close();return end
  assert(dfhack.getTickCount()<deadline,'Membership handshake timeout: '..name);script.sleep(1,'frames')
 end
 error('Membership probe cancelled')
end
local ok,err=xpcall(function()
 if df.global.game.main_interface.view_sheets.open then gui.simulateInput(view,'LEAVESCREEN')end
 view:render(dfhack.getTickCount());select_map(b)
 remove();view:render(dfhack.getTickCount());capture('furniture-membership-absent')
 restore();view:render(dfhack.getTickCount());capture('furniture-membership-restored')
 local f=assert(io.open(out..'/furniture-expected.json','w'))
 f:write(json.encode({buildings={{id=b.id,type=3,tile=entry.tile,watch_membership=true,item_id=item.id}}}));f:close()
 for _,name in ipairs{'membership-ready','membership-absent-seen','membership-restored-seen','ack-workshop-wire','workshop-wire-result.json'}do os.remove(out..'/'..name)end
 local finished=false;local problem
 script.start(function()
  local ran,why=xpcall(function()
   wait_marker('membership-ready');remove();wait_marker('membership-absent-seen');restore();wait_marker('membership-restored-seen')
  end,debug.traceback)
  restore();finished=true;problem=not ran and why or nil
 end)
 capture('workshop-wire')
 assert(finished and not problem,problem or 'Membership viewer returned too soon')
 f=assert(io.open(out..'/workshop-wire-result.json'));reference.viewer=json.decode(f:read('*a'));f:close()
 assert(reference.viewer.success,'Membership viewer failed')
 reference.restored=#b.contained_items==2 and item.flags.whole==flags
 assert(reference.restored)
 for _,suffix in ipairs{'stdout.log','stderr.log','result.json'}do
  local input=assert(io.open(out..'/workshop-wire'..(suffix=='result.json' and '-' or '.')..suffix,'r'))
  local output=assert(io.open(out..'/membership-'..suffix,'w'));output:write(input:read('*a'));output:close();input:close()
 end
end,debug.traceback)
cancelled=true;restore();reference.success=ok;reference.error=ok and '' or tostring(err)
local f=assert(io.open(out..'/furniture-membership.json','w'));f:write(json.encode(reference));f:close()
records[#records+1]={name='furniture-membership',result=reference}
assert(ok,err)
