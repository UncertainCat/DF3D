-- Protected paused-clone oracle: exercise native and owned toggles, restore all
-- pending reports before returning. Do not create a job or advance simulation.
local view,probe,settle,click,capture,unit_id=...
local json=require('json');local crime=df.crime.find(9)
local function reports()
 local rows={}
 for _,r in ipairs(crime.reports)do
  local identities={};for _,id in ipairs(r.all_witnessed_ident)do identities[#identities+1]=id end
  rows[#rows+1]={hfid=r.hfid,visual_hfid=r.visual_hfid,historical_hfid=r.historical_hfid,identities=identities}
 end
 return rows
end
local function selected()
 for _,r in ipairs(probe('justice-candidate-facts-probe',9))do if r.unit_id==unit_id then return (r.flags&1)~=0 end end
 error('Interrogation unit vanished')
end
local before=reports();assert(not selected(),'Fixture requires unselected first candidate')
click(808,190);assert(selected(),'Native interrogation checkbox did not schedule')
local native_on=reports();assert(#native_on==#before+1,'Native interrogation did not add exactly one report')
capture('justice-interrogation-selected')
click(808,190);assert(not selected(),'Native interrogation checkbox did not cancel')
local native_off=reports();assert(json.encode(native_off)==json.encode(before),'Native interrogation did not restore reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==2,'Owned interrogation scheduling failed')
local owned_on=reports();assert(selected(),'Owned interrogation was not selected')
assert(json.encode(owned_on)==json.encode(native_on),'Owned interrogation report differs from native')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==1,'Stale repeated interrogation was not rejected')
assert(json.encode(reports())==json.encode(owned_on),'Rejected interrogation changed reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'1'},true)==2,'Owned interrogation cancellation failed')
local owned_off=reports();assert(not selected(),'Owned interrogation stayed selected')
assert(json.encode(owned_off)==json.encode(before),'Owned interrogation did not restore reports')
return {crime_id=9,unit_id=unit_id,before=before,native_on=native_on,native_off=native_off,owned_on=owned_on,owned_off=owned_off,stale_toggle_rejected=true}
