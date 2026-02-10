-- Anti-Tamper Template
return [=[
local _, e = pcall(function() 
	aa.cc() -- Force an error
end) 

if tonumber(e:match("%d+")) > 1 or e:find("san") then -- Simple line check
    return error("Tamper detected")
end

]=]