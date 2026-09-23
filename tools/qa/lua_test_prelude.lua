    local native_ipairs=ipairs
    function vec(values)
     local v={_vec=true,_data=values or {}}
     return setmetatable(v,{__len=function(s)return #s._data end,__index=function(s,k)
      if type(k)=='number' then return s._data[k+1] end
      if k=='insert' then return function(t,i,x)table.insert(t._data,i=='#' and #t._data+1 or i+1,x)end end
      if k=='erase' then return function(t,i)table.remove(t._data,i+1)end end
      if k=='resize' then return function(t,n)while #t._data>n do table.remove(t._data)end end end
     end})
    end
    function ipairs(v)
     if type(v)=='table' and v._vec then local i=-1;return function()i=i+1;if i<#v then return i,v[i] end end end
     return native_ipairs(v)
    end
    function bits(names)
     local values={};return setmetatable({},{__index=function(_,k)
      if k=='whole' then local n=0;for i,name in native_ipairs(names)do if values[name]then n=n+2^(i-1)end end;return n end
      return values[k] or false
     end,__newindex=function(_,k,v)values[k]=v end})
    end
    function enum(names,start)
     local t={_last_item=#names-1+(start or 0)};for i,n in native_ipairs(names)do t[n]=i-1+(start or 0);t[i-1+(start or 0)]=n end;return t
    end
