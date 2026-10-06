extends RefCounted
# One retained tab, unit-log or alert-group row. No partial string is published as a complete report.
var tab:int
var unit_id:int
var unit_category:int
var notification_category:int
var alert_button:bool
var revision:int
var metadata:Dictionary
var prefix:PackedByteArray
var bytes:=PackedByteArray()
var total:=-1
var complete:=false
func _init(row:Dictionary,selected_tab:int,snapshot_revision:int,unit:int=-1,category:int=-1,group:int=-1,button:bool=false) -> void:
 tab=selected_tab;revision=snapshot_revision;unit_id=unit;unit_category=category
 notification_category=group;alert_button=button
 metadata=row.duplicate(true);metadata.erase("text");metadata.erase("text_complete")
 prefix=str(row.get("text","")).to_utf8_buffer()
func request() -> Dictionary:
 var data:Dictionary={"action":35,"view":5,"tab":tab,"id":int(metadata.id),"cursor":bytes.size(),"expected_list_revision":revision}
 if unit_id>=0:data.unit_id=unit_id;data.unit_category=unit_category
 if notification_category>=0:data.notification_category=notification_category
 if alert_button:data.alert_button=true
 return data
func accept(reply:Dictionary) -> bool:
 if complete or int(reply.get("view",-1))!=5 or int(reply.get("tab",-1))!=tab or int(reply.get("list_revision",0))!=revision:return false
 if int(reply.get("unit_id",-1))!=unit_id or int(reply.get("unit_category",-1))!=unit_category:return false
 if int(reply.get("notification_category",-1))!=notification_category or bool(reply.get("alert_button",false))!=alert_button:return false
 var incoming:Array=reply.get("reports",[])
 if incoming.size()!=1 or not reply.get("units",[]).is_empty() or not reply.get("missing_ids",[]).is_empty():return false
 var row:Dictionary=incoming[0];var facts:Dictionary=row.duplicate(true)
 facts.erase("text");facts.erase("text_complete")
 if facts!=metadata:return false
 var cursor:int=int(reply.get("cursor",-1));var length:int=int(reply.get("total",-1))
 var next:int=int(reply.get("next_cursor",-1));var chunk:PackedByteArray=str(row.get("text","")).to_utf8_buffer()
 if cursor!=bytes.size() or length<0 or length>33554432 or chunk.size()>16384 or (total>=0 and length!=total):return false
 var end:int=cursor+chunk.size()
 if end>length or (length>0 and chunk.is_empty()) or next!=(end if end<length else 0):return false
 if bool(row.get("text_complete",false))!=(cursor==0 and end==length):return false
 if cursor==0 and (chunk.size()<prefix.size() or chunk.slice(0,prefix.size())!=prefix):return false
 total=length;bytes.append_array(chunk);complete=next==0
 return true
func result() -> Dictionary:
 if not complete:return {}
 var value:Dictionary=metadata.duplicate(true)
 value.text=bytes.get_string_from_utf8();value.text_complete=true
 return value
