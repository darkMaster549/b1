-- CLOSURE
return function(inst,shiftAmount,constant,settings)
	local output = ([=[
	local prevStack = Stack
	local prevUpvalues = Upvalues
	
	Stack[:A:] = function(...) -- PROTOTYPE :PROTOHERE:
		local Varargs, Stack, Temp, Upvalues, pointer, top, Map = {}, {}, {}, {}, 1, 0, :MAPPING:
		local Args = {...}
		local C = __constants
		
		-- fix upvalues
		if next(Map) then
			setmeta(Upvalues, {
			    [__index] = function(self, Key)
			        local map = Map[Key]
			        if not map then return nil end
			        if map[1] == 0 then
			            return prevStack[map[2]]
			        else
			            return prevUpvalues[map[2]]
			        end
			    end,
			    [__newindex] = function(self, Key, Value)
			        local map = Map[Key]
			        if not map then return end
			        if map[1] == 0 then
			            prevStack[map[2]] = Value
			        else
			            prevUpvalues[map[2]] = Value
			        end
			    end,
			    [__metatable] = {}
			})
		end
		-- Args
		local argCount = #Args
		for i = 1, argCount do
			Stack[i - 1] = Args[i]
			Varargs[i] = Args[i]
		end
		
		while true do
		INST_PROTOTYPE:PROTOHERE:HERE
		pointer = pointer+1
		end
	end
]=])
	
	return output
end
