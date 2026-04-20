-- // fix constant being empty and always nil

return [=[
local char,byte,sub,ttostring,pcall,unpack,concat,tonumber,setmeta,__metatable,__index,proxy,pnt,Constants,pairs,__newindex,next,dot,gsub,stringv,find,tfind = Env["string"]["char"],Env["string"]["byte"],Env["string"]["sub"],Env["tostring"],Env["pcall"],Env["table"]["unpack"] or Env["unpack"],Env["table"]["concat"],Env["tonumber"],Env["setmetatable"],"__metatable","__index",Env["newproxy"],Env["print"],__constants,Env["pairs"],"__newindex",Env["next"],".",Env["string"]["gsub"],"string",Env["string"]["find"],function(targetTable, value)
	for i,v in pairs(targetTable) do
		if v == value then
			return i
		end
	end
	return nil
end
local C = __constants
]=]
