-- Protected semantic fixture; no native menu data enters the owned provider.
local out,view,probe,settle,click,captions=...
local gui=require('gui');local json=require('json')
local target=assert(df.crime.find(9),'Justice fixture case missing')
local saved={};local keys={'mode','site','entity','accused','criminal','discovered_year','discovered_time'}
for _,key in ipairs(keys)do saved[key]=target[key]end
saved.flags=target.flags.whole
local modes={};local count=0
for _,crime in ipairs(df.global.world.crimes.all)do modes[#modes+1]={crime=crime,mode=crime.mode};count=count+1 end
assert(count<=19,'Unique-title fixture supports at most19 crimes')
local function reset()
 for _,key in ipairs(keys)do target[key]=saved[key]end
 target.flags.whole=saved.flags
 target.accused=-1;target.criminal=-1;target.discovered_year=df.global.cur_year;target.discovered_time=df.global.cur_year_tick
 for index,entry in ipairs(modes)do entry.crime.mode=index-1 end
end
local samples={}
local function observe(name,change)
 gui.simulateInput(view,'LEAVESCREEN');settle();reset();change()
 local supplied=probe('justice-cases-probe')
 gui.simulateInput(view,'D_JUSTICE');settle()
 local native={}
 for index,label in ipairs{'Open cases','Closed cases','Cold cases'}do
  click(label);native[index]=captions()
  local expected={};for _,row in ipairs(supplied[index])do expected[#expected+1]=row.caption end
  assert(json.encode(native[index])==json.encode(expected),'Justice membership/order differs for '..name..' / '..label)
 end
 samples[#samples+1]={name=name,provider=supplied,native=native}
 local f=assert(io.open(out..'/justice-cases.json','w'));f:write(json.encode{crime_id=target.id,cases=samples});f:close()
end
local ok,err=xpcall(function()
 observe('unique-title-order',function()end)
 observe('undiscovered',function()target.flags.discovered=false end)
 observe('foreign-site',function()target.site=target.site+1 end)
 observe('foreign-entity',function()target.entity=target.entity+1 end)
 observe('site-minus-one',function()target.site=-1 end)
 observe('entity-minus-one',function()target.entity=-1 end)
 observe('no-trial',function()target.flags.needs_trial=false end)
 observe('sentenced-needs-trial',function()target.flags.sentenced=true end)
 local unit=assert(df.global.world.units.all[0])
 observe('existing-accused',function()target.accused=unit.id end)
 observe('existing-criminal-only',function()target.criminal=unit.id end)
 observe('missing-accused',function()target.accused=2147483647 end)
 observe('anniversary-not-reached',function()target.discovered_year=df.global.cur_year-1;target.discovered_time=df.global.cur_year_tick+1 end)
 observe('anniversary-equal',function()target.discovered_year=df.global.cur_year-1 end)
 observe('older-year',function()target.discovered_year=df.global.cur_year-2 end)
 observe('unknown-year',function()target.discovered_year=-1 end)
 observe('future-year',function()target.discovered_year=df.global.cur_year+1 end)
end,debug.traceback)
for _,key in ipairs(keys)do target[key]=saved[key]end
target.flags.whole=saved.flags
for _,entry in ipairs(modes)do entry.crime.mode=entry.mode end
assert(ok,err)
