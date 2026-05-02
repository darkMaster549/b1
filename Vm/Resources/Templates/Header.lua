-- Header: all Env bindings are plain assignments inside the VM sandbox.
-- The decrypt engine (__mlDecrypt_fn etc.) is already defined above this
-- in the output, so we CAN call __mlDecrypt here if needed.
-- Variable names are kept short/obfuscated by the minifier.
-- This Make math.sin etc short to only one letter.

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

-- math aliases
local A=math.abs
local B=math.floor
local D=math.ceil
local E=math.max
local F=math.min
local G=math.sqrt
local H=math.sin
local I=math.cos
local J=math.tan
local K=math.random
local L=math.huge
local M=math.pi
]=]
