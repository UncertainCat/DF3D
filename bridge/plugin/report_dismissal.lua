local capture,dismiss,reset=...
assert(type(capture)=='function' and type(dismiss)=='function' and type(reset)=='function')
local owner,world
return function(request)
 local result
 if request.action==68 then
  result=capture();if result.ok then owner=request.client_id;world=request.epoch end
 elseif request.action==69 then
  if owner~=request.client_id or world~=request.epoch then return {ok=false,message="Alert dismissal owner changed"}end
  result=dismiss(request.report.expected_list_revision)
 else return {ok=false,message='Unsupported alert dismissal action'}end
 return {ok=result.ok,message=result.message or '',view=0,announcements_only=true,
  list_revision=result.receipt or (result.ok and request.report.expected_list_revision or 0),total=result.count or 0}
end
