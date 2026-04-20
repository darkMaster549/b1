-- Vm Template
return [=[
%s
%s
		-- VM function
		return (function()
			local Stack = {}
			local Temp = {}
			local Upvalues = {}
			local pointer = 1
			local top = 0
			local Checks = :INSERTENVLOG:

			-- VM STARTS HERE
			while true do
				%s
				%s
			end
		end)()

]=]
