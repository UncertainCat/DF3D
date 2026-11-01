-- Controlled semantic relationships in an owned, paused, unsaved native lane.
-- All vector contents are restored before deleting fixture allocations.
local site,owner,view,pointer,record=...
local gui=require('gui')
local plot=df.global.plotinfo
local sheet=df.global.game.main_interface.view_sheets
local civ=assert(df.historical_entity.find(plot.civ_id))
local fortress=assert(df.historical_entity.find(plot.group_id))
assert(owner.type==df.historical_entity_type.SiteGovernment and owner~=civ and owner~=fortress)
local saved,created={},{}
local function save(list)
 local values={};for _,value in ipairs(list)do values[#values+1]=value end
 saved[#saved+1]={list=list,values=values}
end
local function replace(list,values)
 list:resize(0);for _,value in ipairs(values)do list:insert('#',value)end
end
local function new(kind)
 local value=kind:new();created[#created+1]=value;return value
end
local function install(list,value,key)
 local values={}
 for _,old in ipairs(list)do if old[key]~=value[key]then values[#values+1]=old end end
 values[#values+1]=value;table.sort(values,function(a,b)return a[key]<b[key]end)
 replace(list,values)
end
local function observe(name,expected)
 pointer(856,100);df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(sheet.unit_overview_expelling and sheet.unit_overview_expel_cannot_expel_reason==-1)
 record(name)
 local found=false;for _,id in ipairs(sheet.unit_overview_expel_dest_stid)do if id==site.id then found=true end end
 assert(found==expected,'Native destination eligibility differs: '..name)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 save(civ.site_links);save(owner.entity_links);save(owner.site_links)
 save(civ.positions.assignments);save(fortress.relations.diplomacy.state)
 -- Remove the independent market fallback and give this site a direct parent.
 replace(owner.site_links,{})
 local parent=new(df.entity_entity_link);parent.type=df.entity_entity_link_type.PARENT;parent.target=civ.id;parent.strength=100
 replace(owner.entity_links,{parent})
 local current=new(df.entity_site_link);current.target=plot.site_id;current.entity_id=civ.id;current.position_profile_id=2147483000
 local target=new(df.entity_site_link);target.target=site.id;target.entity_id=civ.id;target.position_profile_id=2147483000
 install(civ.site_links,current,'target');install(civ.site_links,target,'target')
 local relation=new(df.diplomacy_statest);relation.group_id=owner.id;relation.relation=df.diplomacy_state_type.Peace
 install(fortress.relations.diplomacy.state,relation,'group_id')
 observe('destination-shared-profile',true)
 target.position_profile_id=2147483001
 observe('destination-unmatched-profile',false)
 local assignment=new(df.entity_position_assignment);assignment.id=target.position_profile_id
 assignment.vassal_of_entity_id=civ.id;assignment.vassal_of_position_profile_id=current.position_profile_id
 install(civ.positions.assignments,assignment,'id')
 observe('destination-vassal-profile',true)
 assignment.vassal_of_entity_id=fortress.id
 observe('destination-vassal-wrong-entity',false)
 assignment.vassal_of_entity_id=civ.id;assignment.vassal_of_position_profile_id=-1
 observe('destination-vassal-wrong-profile',false)
 assignment.vassal_of_position_profile_id=current.position_profile_id;current.entity_id=fortress.id
 observe('destination-current-link-wrong-entity',false)
 current.entity_id=civ.id;current.position_profile_id=-1
 observe('destination-no-current-profile',false)
 relation.relation=df.diplomacy_state_type.AcceptingTribute
 observe('destination-tribute-same-civilization',true)
 local foreign
 for _,entity in ipairs(df.global.world.entities.all)do
  if entity.type==df.historical_entity_type.Civilization and entity.id~=civ.id then foreign=entity;break end
 end
 assert(foreign,'Expected another civilization')
 parent.target=foreign.id
 observe('destination-tribute-foreign-civilization',false)
 parent.target=civ.id;relation.relation=df.diplomacy_state_type.OfferingTribute
 observe('destination-offering-tribute',false)
end,debug.traceback)
if sheet.unit_overview_expelling then gui.simulateInput(view,'LEAVESCREEN')end
for i=#saved,1,-1 do replace(saved[i].list,saved[i].values)end
for i=#created,1,-1 do created[i]:delete()end
assert(ok,err)
observe('destination-branches-restored',false)
