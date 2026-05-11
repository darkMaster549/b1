-- Merged OpCodes
-- This File Is Part of B1 OBFUSCATOR 
-- What's new? ↓
-- GETIMPORT chain-index, NEWCLOSURE rawget upval copy, FORGLOOP control var fix
-- blob separator \n→|, unique names for pointer/Stack/Upvals/prevStack
-- Vm/Resources/Templates/DecryptStringsTemplate.lua — gmatch separator \n→|
-- removed "1I" from lIName pool (was generating invalid identifiers starting with digit)
-- — (via TreeGenerator gsub fix) word-boundary replacements
-- i fix a lot of bugs in not sure if all are fully fixed in still testing lot of scripts I've been fixing this like 2 or 3 days just to fix those file including this File.
-- it's hard to build Obfuscator just One person lol
local OpCodes = {}

-- ==================== LUA 5.1 ====================

OpCodes[51] = {}

OpCodes[51][0] = function(instruction, shiftAmount, constant, settings) -- MOVE
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = Stack[%d]"):format(reg_a, reg_b)
end

OpCodes[51][1] = function(inst, shift, const, settings) -- LOADK
	local reg_b = _G.getReg(inst, "B")
	local mappedIdx = _G.getMappedConstant(reg_b)
	return ("\tStack[:A:] = C[%d]"):format(mappedIdx)
end

OpCodes[51][2] = function(instruction, shiftAmount, constant, settings) -- LOADBOOL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	local reg_c = _G.getReg(instruction, "C")
	local boolVal = reg_b == 1 and "true" or "false"
	if reg_c ~= 0 then
		return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(reg_a, boolVal)
	else
		return ("\tStack[%d] = %s"):format(reg_a, boolVal)
	end
end

OpCodes[51][3] = function(instruction, shiftAmount, constant, settings) -- LOADNIL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	if reg_b == 0 then
		return ("\tStack[%d] = nil"):format(reg_a)
	else
		local nils = {}
		for i = 0, reg_b do
			nils[i + 1] = ("Stack[%d]"):format(reg_a + i)
		end
		return ("\t%s = nil"):format(table.concat(nils, ", "))
	end
end

OpCodes[51][4] = function(instruction, shiftAmount, constant, settings) -- GETUPVAL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = Upvalues[%d]"):format(reg_a, reg_b)
end

OpCodes[51][5] = function(inst, shift, constant, settings) -- GETGLOBAL
	local reg_b = _G.getReg(inst, "B")
	local mappedIdx = _G.getMappedConstant(reg_b)
	return ("\tStack[:A:] = Env[C[%d]]"):format(mappedIdx)
end

OpCodes[51][6] = function(inst, shiftAmount, constant, settings) -- GETTABLE
	local C = inst.C
	if C.k then
		local mappedIdx = _G.getMappedConstant(C.i)
		return ([==[
	Stack[:A:] = Stack[:B:][C[%d]]
	]==]):format(mappedIdx)
	else
		return ([==[
	Stack[:A:] = Stack[:B:][Stack[%d]]
	]==]):format(C.i)
	end
end

OpCodes[51][7] = function(inst, shift, constant, settings) -- SETGLOBAL
	local reg_b = _G.getReg(inst, "B")
	local mappedIdx = _G.getMappedConstant(reg_b)
	return ("\tEnv[C[%d]] = Stack[:A:]"):format(mappedIdx)
end

OpCodes[51][8] = function(instruction, shiftAmount, constant, settings) -- SETUPVAL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tUpvalues[%d] = Stack[%d]"):format(reg_b, reg_a)
end

OpCodes[51][9] = function(inst) -- SETTABLE
	local reg_b = _G.getReg(inst, "B", true)
	local reg_c = _G.getReg(inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:][%s] = %s"):format(b_access, c_access)
end

OpCodes[51][10] = "\tStack[:A:] = {}" -- NEWTABLE

OpCodes[51][11] = function(inst, shiftAmount, constant, settings) -- SELF
	local C = inst.C
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local c_access = C.k and ("C[%d]"):format(_G.getMappedConstant(C.i)) or ("Stack[%d]"):format(C.i)
	return ([==[
	Stack[%d] = Stack[%d]
	if Stack[%d] then
		Stack[%d] = Stack[%d][%s]
	end
	]==]):format(reg_a + 1, reg_b, reg_a + 1, reg_a, reg_b, c_access)
end

OpCodes[51][12] = function(Inst, shiftAmount, constant, settings) -- ADD
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s + %s"):format(b_access, c_access)
end

OpCodes[51][13] = function(Inst, shiftAmount, constant, settings) -- SUB
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s - %s"):format(b_access, c_access)
end

OpCodes[51][14] = function(Inst, shiftAmount, constant, settings) -- MUL
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s * %s"):format(b_access, c_access)
end

OpCodes[51][15] = function(Inst, shiftAmount, constant, settings) -- DIV
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s / %s"):format(b_access, c_access)
end

OpCodes[51][16] = function(Inst, shiftAmount, constant, settings) -- MOD
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s %% %s"):format(b_access, c_access)
end

OpCodes[51][17] = function(Inst, shiftAmount, constant, settings) -- POW
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B", true)
	local reg_c = _G.getReg(Inst, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	return ("\tStack[:A:] = %s ^ %s"):format(b_access, c_access)
end

OpCodes[51][18] = function(instruction, shiftAmount, constant, settings) -- UNM
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = -Stack[%d]"):format(reg_a, reg_b)
end

OpCodes[51][19] = function(instruction, shiftAmount, constant, settings) -- NOT
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = not Stack[%d]"):format(reg_a, reg_b)
end

OpCodes[51][20] = function(instruction, shiftAmount, constant, settings) -- LEN
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = #Stack[%d]"):format(reg_a, reg_b)
end

OpCodes[51][21] = function(instruction, shiftAmount, constant, settings) -- CONCAT
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	local reg_c = _G.getReg(instruction, "C")
	return ([==[
	local _out = ""
	for i = %d, %d do
		_out = _out .. Stack[i]
	end
	Stack[%d] = _out
	]==]):format(reg_b, reg_c, reg_a)
end

OpCodes[51][22] = function(inst, shiftAmount, constant, settings) -- JMP
	local output = ("pointer = pointer + :B: %s"):format(settings.Debug and "print('[VM]:','JMP -- >',pointer)" or "")
	if settings.LuaU_Syntax then
		output = ("pointer += :B:-1 %s"):format(settings.Debug and "print('[VM]:','JMP -- >',pointer)" or "")
	end
	return output
end

OpCodes[51][23] = function(instruction, shiftAmount, constant, settings) -- EQ
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B", true)
	local reg_c = _G.getReg(instruction, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	local op = reg_a > 0 and "~=" or "=="
	return ("\tif %s %s %s then pointer = pointer + 1 end"):format(b_access, op, c_access)
end

OpCodes[51][24] = function(instruction, shiftAmount, constant, settings) -- LT
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B", true)
	local reg_c = _G.getReg(instruction, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	local op = reg_a > 0 and ">" or "<"
	return ("\tif %s %s %s then pointer = pointer + 1 end"):format(b_access, op, c_access)
end

OpCodes[51][25] = function(instruction, shiftAmount, constant, settings) -- LE
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B", true)
	local reg_c = _G.getReg(instruction, "C", true)
	local b_access = reg_b.k and ("C[%d]"):format(_G.getMappedConstant(reg_b.i)) or ("Stack[%d]"):format(reg_b.i)
	local c_access = reg_c.k and ("C[%d]"):format(_G.getMappedConstant(reg_c.i)) or ("Stack[%d]"):format(reg_c.i)
	local op = reg_a > 0 and ">=" or "<="
	return ("\tif %s %s %s then pointer = pointer + 1 end"):format(b_access, op, c_access)
end

OpCodes[51][26] = function(Inst, shiftAmount, constant, settings) -- TEST
	local reg_a = _G.getReg(Inst, "A")
	local reg_c = _G.getReg(Inst, "C")
	local check = reg_c == 0 and ("Stack[%d]"):format(reg_a) or ("not Stack[%d]"):format(reg_a)
	return ("\tif %s then pointer = pointer + 1 end"):format(check)
end

OpCodes[51][27] = function(Inst, shiftAmount, constant, settings) -- TESTSET
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	local reg_c = _G.getReg(Inst, "C")
	local check = reg_c ~= 0 and "not" or ""
	return ([==[
	if (%s Stack[%d]) then
		pointer = pointer + 1
	else
		Stack[%d] = Stack[%d]
	end
	]==]):format(check, reg_b, reg_a, reg_b)
end

OpCodes[51][28] = function(Inst, shiftAmount, constant, settings) -- CALL
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	local reg_c = _G.getReg(Inst, "C")
	local args = {}
	if reg_b == 0 then
		return ([==[
	local Args = {}
	for i = :A: + 1, top do
		Args[i - :A:] = Stack[i]
	end
	local Results = {Stack[:A:](unpack(Args, 1, top - :A:))}
	%s
	]==]):format(reg_c < 1 and [==[
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil
		top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do
			Stack[:A: + i - 1] = Results[i]
		end
	end
	]==] or ([==[
	for i = 1, %d do
		Stack[:A: + i - 1] = Results[i]
	end
	]==]):format(reg_c - 1))
	end
	local argCount = reg_b - 1
	for i = 1, argCount do
		args[i] = ("Stack[%d]"):format(reg_a + i)
	end
	local argStr = table.concat(args, ", ")
	if reg_c < 1 then
		return ([==[
	local Results = {Stack[:A:](%s)}
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil
		top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do
			Stack[:A: + i - 1] = Results[i]
		end
	end
	]==]):format(argStr)
	elseif reg_c == 1 then
		return ("\tStack[:A:](%s)"):format(argStr)
	elseif reg_c == 2 then
		return ("\tStack[:A:] = Stack[:A:](%s)"):format(argStr)
	else
		local rets = {}
		for i = 0, reg_c - 2 do
			rets[i + 1] = ("Stack[%d]"):format(reg_a + i)
		end
		return ("\t%s = Stack[:A:](%s)"):format(table.concat(rets, ", "), argStr)
	end
end

OpCodes[51][29] = function(Inst, shiftAmount, constant, settings) -- TAILCALL
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	if reg_b == 0 then
		return ([==[
	local _args = {}
	for i = %d + 1, top do
		_args[i - %d] = Stack[i]
	end
	return Stack[%d](unpack(_args, 1, top - %d))
	]==]):format(reg_a, reg_a, reg_a, reg_a)
	end
	local args = {}
	for i = 1, reg_b - 1 do
		args[i] = ("Stack[%d]"):format(reg_a + i)
	end
	return ("\treturn Stack[%d](%s)"):format(reg_a, table.concat(args, ", "))
end

OpCodes[51][30] = function(instruction, shiftAmount, constant, settings) -- RETURN
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	if reg_b == 0 then
		return [==[
		local _out = {}
		local _n = 0
		for i = :A:, top do
			_n = _n + 1
			_out[_n] = Stack[i]
		end
		return unpack(_out, 1, _n)
	]==]
	elseif reg_b == 1 then
		return "\treturn"
	elseif reg_b == 2 then
		return ("\treturn Stack[%d]"):format(reg_a)
	else
		local rets = {}
		for i = 0, reg_b - 2 do
			rets[i + 1] = ("Stack[%d]"):format(reg_a + i)
		end
		return ("\treturn %s"):format(table.concat(rets, ", "))
	end
end

OpCodes[51][31] = function(instruction, shiftAmount, constant, settings) -- FORLOOP
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ([==[
	local _step = Stack[%d]
	local _limit = Stack[%d]
	local _index = Stack[%d] + _step
	Stack[%d] = _index
	if (_step > 0 and _index <= _limit) or (_step <= 0 and _index >= _limit) then
		pointer = pointer + %d
		Stack[%d] = _index
	end
	]==]):format(reg_a + 2, reg_a + 1, reg_a, reg_a, reg_b, reg_a + 3)
end

OpCodes[51][32] = function(instruction, shiftAmount, constant, settings) -- FORPREP
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ([==[
	local _init = tonumber(Stack[%d])
	local _limit = tonumber(Stack[%d])
	local _step = tonumber(Stack[%d])
	Stack[%d] = _init - _step
	Stack[%d] = _limit
	Stack[%d] = _step
	pointer = pointer + %d
	]==]):format(reg_a, reg_a + 1, reg_a + 2, reg_a, reg_a + 1, reg_a + 2, reg_b)
end

OpCodes[51][33] = function(instruction, shiftAmount, constant, settings) -- TFORLOOP
	local reg_a = _G.getReg(instruction, "A")
	local reg_c = _G.getReg(instruction, "C")
	return ([==[
	local _result = {Stack[%d](Stack[%d], Stack[%d])}
	for i = 1, %d do
		Stack[%d + i] = _result[i]
	end
	if Stack[%d] ~= nil then
		Stack[%d] = Stack[%d]
	else
		pointer = pointer + 1
	end
	]==]):format(reg_a, reg_a + 1, reg_a + 2, reg_c, reg_a + 2, reg_a + 3, reg_a + 2, reg_a + 3)
end

OpCodes[51][34] = function(Inst, shift, const) -- SETLIST
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	local reg_c = _G.getReg(Inst, "C")
	if reg_b == 0 then
		return ([==[
	local _limit = top - %d
	for i = 1, _limit do
		Stack[%d][(%d - 1) * 50 + i] = Stack[%d + i]
	end
	]==]):format(reg_a, reg_a, reg_c, reg_a)
	else
		return ([==[
	for i = 1, %d do
		Stack[%d][(%d - 1) * 50 + i] = Stack[%d + i]
	end
	]==]):format(reg_b, reg_a, reg_c, reg_a)
	end
end

OpCodes[51][35] = function(instruction, shiftAmount, constant, settings) -- CLOSE
	local reg_a = _G.getReg(instruction, "A")
	return ([==[
	for i = %d, #Stack do
		Stack[i] = nil
	end
	]==]):format(reg_a)
end

OpCodes[51][36] = function(inst, shiftAmount, constant, settings) -- CLOSURE
	return [==[
	local prevStack = Stack
	local prevUpvalues = Upvalues

	Stack[:A:] = function(...) -- PROTOTYPE :PROTOHERE:
		local Varargs, Stack, Temp, Upvalues, pointer, top, Map = {}, {}, {}, {}, 1, 0, :MAPPING:
		local Args = {...}
		local C = __constants

                for k, map in next, Map do
                        if map[1] == 0 then
                                Upvalues[k] = rawget(prevStack, map[2])
                        else
                                Upvalues[k] = rawget(prevUpvalues, map[2])
                        end
                end
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
]==]
end

OpCodes[51][37] = function(instruction, shiftAmount, constant, settings) -- VARARG
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	if reg_b == 0 then
		return ([==[
	top = %d + #Varargs - 1
	for i = 1, #Varargs do
		Stack[%d + i - 1] = Varargs[i]
	end
	]==]):format(reg_a, reg_a)
	else
		return ([==[
	for i = 1, %d do
		Stack[%d + i - 1] = Varargs[i]
	end
	]==]):format(reg_b - 1, reg_a)
	end
end

OpCodes[51]["INVALID"] = "--INVALID OPCODE (EMPTY)"

OpCodes[51]["_CRASH"] = function(inst, shiftAmount, constant, settings)
	if inst == "custom" then
		return {
			["A"] = shiftAmount.A + 1,
			["Opcode"] = "_CRASH",
			["OpcodeName"] = "_CRASH",
		}
	end
	if settings.Debug then
		return "print('[VM]:','CRASH_VM!') break"
	end
	return [==[
		pointer = pointer + 40^10
	]==]
end

-- ==================== LUAU ====================

OpCodes[52] = {}

OpCodes[52][0]  = "-- nop"                                           -- NOP
OpCodes[52][1]  = "-- break point (no-op)"                           -- BREAK
OpCodes[52][64] = "-- prepvarargs (no-op, handled at function entry)" -- PREPVARARGS
OpCodes[52][67] = "-- fastcall (handled by following CALL)"          -- FASTCALL
OpCodes[52][68] = "-- coverage (no-op)"                              -- COVERAGE
OpCodes[52][69] = "-- capture (pseudo, handled by NEWCLOSURE)"       -- CAPTURE
OpCodes[52][72] = "-- fastcall1 (handled by following CALL)"         -- FASTCALL1
OpCodes[52][73] = "-- fastcall2 (handled by following CALL)"         -- FASTCALL2
OpCodes[52][74] = "-- fastcall2k (handled by following CALL)"        -- FASTCALL2K
OpCodes[52][51] = "\tStack[:A:] = {}"                                -- NEWTABLE

OpCodes[52][2] = function(instruction, shiftAmount, constant, settings) -- LOADNIL
	local reg_a = _G.getReg(instruction, "A")
	return ("\tStack[%d] = nil"):format(reg_a)
end

OpCodes[52][3] = function(instruction, shiftAmount, constant, settings) -- LOADB
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	local reg_c = _G.getReg(instruction, "C")
	local val = reg_b ~= 0 and "true" or "false"
	if reg_c ~= 0 then
		return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(reg_a, val)
	else
		return ("\tStack[%d] = %s"):format(reg_a, val)
	end
end

OpCodes[52][4] = function(instruction, shiftAmount, constant, settings) -- LOADN
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	return ("\tStack[%d] = %d"):format(reg_a, d)
end

OpCodes[52][5] = function(inst, shiftAmount, constant, settings) -- LOADK
	local d = inst.D or inst.Bx or 0
	local mappedIdx = _G.getMappedConstant(d)
	return ("\tStack[:A:] = C[%d]"):format(mappedIdx)
end

OpCodes[52][6] = function(instruction, shiftAmount, constant, settings) -- MOVE
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = Stack[%d]"):format(reg_a, reg_b)
end

OpCodes[52][7] = function(instruction, shiftAmount, constant, settings) -- GETUPVAL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tStack[%d] = Upvalues[%d]"):format(reg_a, reg_b)
end

OpCodes[52][8] = function(instruction, shiftAmount, constant, settings) -- SETUPVAL
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	return ("\tUpvalues[%d] = Stack[%d]"):format(reg_b, reg_a)
end

OpCodes[52][9] = function(instruction, shiftAmount, constant, settings) -- CLOSEUPVALS
	local reg_a = _G.getReg(instruction, "A")
	return ([==[
	for i = %d, #Stack do
		Stack[i] = nil
	end
	]==]):format(reg_a)
end

OpCodes[52][10] = function(inst, shiftAmount, constant, settings) -- GETIMPORT
	local d = inst.D or inst.Bx or 0
	local mappedIdx = _G.getMappedConstant(d)
	local code = "\n\tdo\n\t\tlocal _imp = C[" .. tostring(mappedIdx) .. "]\n"
		.. "\t\tif type(_imp) == \"string\" then\n"
		.. "\t\t\tlocal _t = Env\n"
		.. "\t\t\tfor _k in (_imp .. \".\"):gmatch(\"([^.]+)%.\") do\n"
		.. "\t\t\t\tif type(_t) ~= \"table\" and type(_t) ~= \"userdata\" then _t = nil; break end\n"
		.. "\t\t\t\t_t = _t[_k]\n"
		.. "\t\t\tend\n"
		.. "\t\t\tStack[:A:] = _t\n"
		.. "\t\telse\n"
		.. "\t\t\tStack[:A:] = _imp\n"
		.. "\t\tend\n"
		.. "\tend\n"
	return code
end

OpCodes[52][11] = function(inst, shiftAmount, constant, settings) -- GETTABLE
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local reg_c = _G.getReg(inst, "C")
	return ("\tStack[%d] = Stack[%d][Stack[%d]]"):format(reg_a, reg_b, reg_c)
end

OpCodes[52][12] = function(inst, shiftAmount, constant, settings) -- SETTABLE
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local reg_c = _G.getReg(inst, "C")
	return ("\tStack[%d][Stack[%d]] = Stack[%d]"):format(reg_a, reg_b, reg_c)
end

OpCodes[52][13] = function(inst, shiftAmount, constant, settings) -- GETTABLEKS
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux)
	return ("\tStack[%d] = Stack[%d][C[%d]]"):format(reg_a, reg_b, mappedIdx)
end

OpCodes[52][14] = function(inst, shiftAmount, constant, settings) -- SETTABLEKS
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux)
	return ("\tStack[%d][C[%d]] = Stack[%d]"):format(reg_a, mappedIdx, reg_b)
end

OpCodes[52][15] = function(inst, shiftAmount, constant, settings) -- GETTABLEN
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local reg_c = _G.getReg(inst, "C")
	return ("\tStack[%d] = Stack[%d][%d]"):format(reg_a, reg_b, reg_c)
end

OpCodes[52][16] = function(inst, shiftAmount, constant, settings) -- SETTABLEN
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local reg_c = _G.getReg(inst, "C")
	return ("\tStack[%d][%d] = Stack[%d]"):format(reg_a, reg_c, reg_b)
end

OpCodes[52][17] = function(inst, shiftAmount, constant, settings) -- NEWCLOSURE
	return [==[
	local prevStack = Stack
	local prevUpvalues = Upvalues

	Stack[:A:] = function(...) -- PROTOTYPE :PROTOHERE:
		local Varargs, Stack, Temp, Upvalues, pointer, top, Map = {}, {}, {}, {}, 1, 0, :MAPPING:
		local Args = {...}
		local C = __constants

                for k, map in next, Map do
                        if map[1] == 0 then
                                Upvalues[k] = rawget(prevStack, map[2])
                        else
                                Upvalues[k] = rawget(prevUpvalues, map[2])
                        end
                end

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
]==]
end

OpCodes[52][18] = function(inst, shiftAmount, constant, settings) -- NAMECALL
	local reg_a = _G.getReg(inst, "A")
	local reg_b = _G.getReg(inst, "B")
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux)
	return ([==[
	Stack[%d] = Stack[%d]
	Stack[%d] = Stack[%d][C[%d]]
	]==]):format(reg_a + 1, reg_b, reg_a, reg_b, mappedIdx)
end

OpCodes[52][19] = function(Inst, shiftAmount, constant, settings) -- CALL
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	local reg_c = _G.getReg(Inst, "C")
	local args = {}
	if reg_b == 0 then
		return ([==[
	local Args = {}
	for i = :A: + 1, top do
		Args[i - :A:] = Stack[i]
	end
	local Results = {Stack[:A:](unpack(Args, 1, top - :A:))}
	%s
	]==]):format(reg_c < 1 and [==[
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil
		top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do
			Stack[:A: + i - 1] = Results[i]
		end
	end
	]==] or ([==[
	for i = 1, %d do
		Stack[:A: + i - 1] = Results[i]
	end
	]==]):format(reg_c - 1))
	end
	local argCount = reg_b - 1
	for i = 1, argCount do
		args[i] = ("Stack[%d]"):format(reg_a + i)
	end
	local argStr = table.concat(args, ", ")
	if reg_c < 1 then
		return ([==[
	local Results = {Stack[:A:](%s)}
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil
		top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do
			Stack[:A: + i - 1] = Results[i]
		end
	end
	]==]):format(argStr)
	elseif reg_c == 1 then
		return ("\tStack[:A:](%s)"):format(argStr)
	elseif reg_c == 2 then
		return ("\tStack[:A:] = Stack[:A:](%s)"):format(argStr)
	else
		local rets = {}
		for i = 0, reg_c - 2 do
			rets[i + 1] = ("Stack[%d]"):format(reg_a + i)
		end
		return ("\t%s = Stack[:A:](%s)"):format(table.concat(rets, ", "), argStr)
	end
end

OpCodes[52][20] = function(instruction, shiftAmount, constant, settings) -- RETURN
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	if reg_b == 0 then
		return [==[
		local _out = {}
		local _n = 0
		for i = :A:, top do
			_n = _n + 1
			_out[_n] = Stack[i]
		end
		return unpack(_out, 1, _n)
	]==]
	elseif reg_b == 1 then
		return "\treturn"
	elseif reg_b == 2 then
		return ("\treturn Stack[%d]"):format(reg_a)
	else
		local rets = {}
		for i = 0, reg_b - 2 do
			rets[i + 1] = ("Stack[%d]"):format(reg_a + i)
		end
		return ("\treturn %s"):format(table.concat(rets, ", "))
	end
end

OpCodes[52][21] = function(inst, shiftAmount, constant, settings) -- JUMP
	local e = inst.E or inst.sBx or 0
	return ("pointer = pointer + %d"):format(e)
end

OpCodes[52][22] = function(inst, shiftAmount, constant, settings) -- JUMPBACK
	local e = inst.E or inst.sBx or 0
	return ("pointer = pointer + %d"):format(e)
end

OpCodes[52][23] = function(inst, shiftAmount, constant, settings) -- JUMPIF
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	return ([==[
	if Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, d)
end

OpCodes[52][24] = function(inst, shiftAmount, constant, settings) -- JUMPIFNOT
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	return ([==[
	if not Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, d)
end

OpCodes[52][25] = function(inst, shiftAmount, constant, settings) -- JUMPIFEQ
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if Stack[%d] == Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][26] = function(inst, shiftAmount, constant, settings) -- JUMPIFLE
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if Stack[%d] <= Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][27] = function(inst, shiftAmount, constant, settings) -- JUMPIFLT
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if Stack[%d] < Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][28] = function(inst, shiftAmount, constant, settings) -- JUMPIFNOTEQ
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if Stack[%d] ~= Stack[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][29] = function(inst, shiftAmount, constant, settings) -- JUMPIFNOTLE
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if not (Stack[%d] <= Stack[%d]) then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][30] = function(inst, shiftAmount, constant, settings) -- JUMPIFNOTLT
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	return ([==[
	if not (Stack[%d] < Stack[%d]) then
		pointer = pointer + %d
	end
	]==]):format(reg_a, aux, d)
end

OpCodes[52][31] = function(inst, s, c, settings) -- ADD
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] + Stack[%d]"):format(a,b,c2)
end

OpCodes[52][32] = function(inst, s, c, settings) -- SUB
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] - Stack[%d]"):format(a,b,c2)
end

OpCodes[52][33] = function(inst, s, c, settings) -- MUL
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] * Stack[%d]"):format(a,b,c2)
end

OpCodes[52][34] = function(inst, s, c, settings) -- DIV
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] / Stack[%d]"):format(a,b,c2)
end

OpCodes[52][35] = function(inst, s, c, settings) -- MOD
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] %% Stack[%d]"):format(a,b,c2)
end

OpCodes[52][36] = function(inst, s, c, settings) -- POW
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] ^ Stack[%d]"):format(a,b,c2)
end

OpCodes[52][37] = function(inst, s, c, settings) -- ADDK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] + C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][38] = function(inst, s, c, settings) -- SUBK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] - C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][39] = function(inst, s, c, settings) -- MULK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] * C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][40] = function(inst, s, c, settings) -- DIVK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] / C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][41] = function(inst, s, c, settings) -- MODK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] %% C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][42] = function(inst, s, c, settings) -- POWK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] ^ C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][43] = function(inst, s, c, settings) -- AND
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] and Stack[%d]"):format(a,b,c2)
end

OpCodes[52][44] = function(inst, s, c, settings) -- OR
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] or Stack[%d]"):format(a,b,c2)
end

OpCodes[52][45] = function(inst, s, c, settings) -- ANDK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] and C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][46] = function(inst, s, c, settings) -- ORK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = Stack[%d] or C[%d]"):format(a, b, _G.getMappedConstant(ci))
end

OpCodes[52][47] = function(instruction, shiftAmount, constant, settings) -- CONCAT
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	local reg_c = _G.getReg(instruction, "C")
	return ([==[
	local _out = ""
	for i = %d, %d do
		_out = _out .. tostring(Stack[i])
	end
	Stack[%d] = _out
	]==]):format(reg_b, reg_c, reg_a)
end

OpCodes[52][48] = function(instruction, shiftAmount, constant, settings) -- NOT
	local a = _G.getReg(instruction,"A"); local b = _G.getReg(instruction,"B")
	return ("\tStack[%d] = not Stack[%d]"):format(a,b)
end

OpCodes[52][49] = function(instruction, shiftAmount, constant, settings) -- MINUS
	local a = _G.getReg(instruction,"A"); local b = _G.getReg(instruction,"B")
	return ("\tStack[%d] = -Stack[%d]"):format(a,b)
end

OpCodes[52][50] = function(instruction, shiftAmount, constant, settings) -- LENGTH
	local a = _G.getReg(instruction,"A"); local b = _G.getReg(instruction,"B")
	return ("\tStack[%d] = #Stack[%d]"):format(a,b)
end

OpCodes[52][52] = function(inst, shiftAmount, constant, settings) -- DUPTABLE
	local d = inst.D or inst.Bx or 0
	local mappedIdx = _G.getMappedConstant(d)
	return ([==[
	do
		local _tpl = C[%d]
		local _t = {}
		if type(_tpl) == "table" then
			for k,v in pairs(_tpl) do _t[k] = v end
		end
		Stack[:A:] = _t
	end
	]==]):format(mappedIdx)
end

OpCodes[52][53] = function(Inst, shift, const) -- SETLIST
	local reg_a = _G.getReg(Inst, "A")
	local reg_b = _G.getReg(Inst, "B")
	if reg_b == 0 then
		return ([==[
	local _limit = top - %d
	for i = 1, _limit do
		Stack[%d][i] = Stack[%d + i]
	end
	]==]):format(reg_a, reg_a, reg_a)
	else
		return ([==[
	for i = 1, %d do
		Stack[%d][i] = Stack[%d + i]
	end
	]==]):format(reg_b, reg_a, reg_a)
	end
end

OpCodes[52][54] = function(instruction, shiftAmount, constant, settings) -- FORNPREP
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	return ([==[
	local _init  = tonumber(Stack[%d])
	local _limit = tonumber(Stack[%d])
	local _step  = tonumber(Stack[%d])
	Stack[%d] = _init - _step
	Stack[%d] = _limit
	Stack[%d] = _step
	pointer = pointer + %d
	]==]):format(reg_a, reg_a+1, reg_a+2, reg_a, reg_a+1, reg_a+2, d)
end

OpCodes[52][55] = function(instruction, shiftAmount, constant, settings) -- FORNLOOP
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	return ([==[
	local _step  = Stack[%d]
	local _limit = Stack[%d]
	local _index = Stack[%d] + _step
	Stack[%d] = _index
	if (_step > 0 and _index <= _limit) or (_step <= 0 and _index >= _limit) then
		pointer = pointer + %d
		Stack[%d] = _index
	end
	]==]):format(reg_a+2, reg_a+1, reg_a, reg_a, d, reg_a+3)
end

OpCodes[52][56] = function(instruction, shiftAmount, constant, settings) -- FORGPREP
	local d = instruction.D or instruction.Bx or 0
	return ("pointer = pointer + %d"):format(d)
end

OpCodes[52][57] = function(instruction, shiftAmount, constant, settings) -- FORGLOOP
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	local aux = instruction.AUX or 1
	return ([==[
	local _result = {Stack[%d](Stack[%d], Stack[%d])}
	if _result[1] ~= nil then
		Stack[%d] = _result[1]
		for i = 1, %d do
			Stack[%d + i] = _result[i]
		end
		pointer = pointer + %d
	end
	]==]):format(reg_a, reg_a+1, reg_a+2, reg_a+2, aux, reg_a+2, d)
end

OpCodes[52][58] = function(instruction, shiftAmount, constant, settings) -- FORGPREP_INEXT
	local d = instruction.D or instruction.Bx or 0
	return ("pointer = pointer + %d"):format(d)
end

OpCodes[52][59] = function(instruction, shiftAmount, constant, settings) -- FORGLOOP_INEXT
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	return ([==[
	local _idx = Stack[%d] + 1
	local _val = Stack[%d][_idx]
	if _val ~= nil then
		Stack[%d] = _idx
		Stack[%d] = _val
		pointer = pointer + %d
	end
	]==]):format(reg_a+2, reg_a+1, reg_a+2, reg_a+3, d)
end

OpCodes[52][60] = function(instruction, shiftAmount, constant, settings) -- FORGPREP_NEXT
	local d = instruction.D or instruction.Bx or 0
	return ("pointer = pointer + %d"):format(d)
end

OpCodes[52][61] = function(instruction, shiftAmount, constant, settings) -- FORGLOOP_NEXT
	local reg_a = _G.getReg(instruction, "A")
	local d = instruction.D or instruction.Bx or 0
	return ([==[
	local _k, _v = next(Stack[%d], Stack[%d])
	if _k ~= nil then
		Stack[%d] = _k
		Stack[%d] = _v
		pointer = pointer + %d
	end
	]==]):format(reg_a+1, reg_a+2, reg_a+2, reg_a+3, d)
end

OpCodes[52][62] = function(instruction, shiftAmount, constant, settings) -- GETVARARGS
	local reg_a = _G.getReg(instruction, "A")
	local reg_b = _G.getReg(instruction, "B")
	if reg_b == 0 then
		return ([==[
	top = %d + #Varargs - 1
	for i = 1, #Varargs do
		Stack[%d + i - 1] = Varargs[i]
	end
	]==]):format(reg_a, reg_a)
	else
		return ([==[
	for i = 1, %d do
		Stack[%d + i - 1] = Varargs[i]
	end
	]==]):format(reg_b - 1, reg_a)
	end
end

OpCodes[52][63] = function(inst, shiftAmount, constant, settings) -- DUPCLOSURE
	return [==[
	local prevStack = Stack
	local prevUpvalues = Upvalues

	Stack[:A:] = function(...) -- PROTOTYPE :PROTOHERE:
		local Varargs, Stack, Temp, Upvalues, pointer, top, Map = {}, {}, {}, {}, 1, 0, :MAPPING:
		local Args = {...}
		local C = __constants

                for k, map in next, Map do
                        if map[1] == 0 then
                                Upvalues[k] = rawget(prevStack, map[2])
                        else
                                Upvalues[k] = rawget(prevUpvalues, map[2])
                        end
                end

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
]==]
end

OpCodes[52][65] = function(inst, shiftAmount, constant, settings) -- LOADKX
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux)
	return ("\tStack[:A:] = C[%d]"):format(mappedIdx)
end

OpCodes[52][66] = function(inst, shiftAmount, constant, settings) -- JUMPX
	local e = inst.E or inst.sBx or 0
	return ("pointer = pointer + %d"):format(e)
end

OpCodes[52][70] = function(inst, s, c, settings) -- SUBRK
	local a = _G.getReg(inst,"A"); local bi = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = C[%d] - Stack[%d]"):format(a, _G.getMappedConstant(bi), c2)
end

OpCodes[52][71] = function(inst, s, c, settings) -- DIVRK
	local a = _G.getReg(inst,"A"); local bi = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = C[%d] / Stack[%d]"):format(a, _G.getMappedConstant(bi), c2)
end

OpCodes[52][75] = function(instruction, shiftAmount, constant, settings) -- FORGPREP v3+
	local d = instruction.D or instruction.Bx or 0
	return ("pointer = pointer + %d"):format(d)
end

OpCodes[52][76] = function(inst, shiftAmount, constant, settings) -- JUMPXEQKNIL
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	local notFlag = aux >= 0x80000000
	local cmp = notFlag and "~= nil" or "== nil"
	return ([==[
	if Stack[%d] %s then
		pointer = pointer + %d
	end
	]==]):format(reg_a, cmp, d)
end

OpCodes[52][77] = function(inst, shiftAmount, constant, settings) -- JUMPXEQKB
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	local notFlag = (aux >= 0x80000000)
	local bval = ((aux % 2) == 1) and "true" or "false"
	local op = notFlag and "~=" or "=="
	return ([==[
	if Stack[%d] %s %s then
		pointer = pointer + %d
	end
	]==]):format(reg_a, op, bval, d)
end

OpCodes[52][78] = function(inst, shiftAmount, constant, settings) -- JUMPXEQKN
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux % 0x1000000)
	return ([==[
	if Stack[%d] == C[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, mappedIdx, d)
end

OpCodes[52][79] = function(inst, shiftAmount, constant, settings) -- JUMPXEQKS
	local reg_a = _G.getReg(inst, "A")
	local d = inst.D or inst.Bx or 0
	local aux = inst.AUX or 0
	local mappedIdx = _G.getMappedConstant(aux % 0x1000000)
	return ([==[
	if Stack[%d] == C[%d] then
		pointer = pointer + %d
	end
	]==]):format(reg_a, mappedIdx, d)
end

OpCodes[52][80] = function(inst, s, c, settings) -- IDIV
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
	return ("\tStack[%d] = math.floor(Stack[%d] / Stack[%d])"):format(a,b,c2)
end

OpCodes[52][81] = function(inst, s, c, settings) -- IDIVK
	local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
	return ("\tStack[%d] = math.floor(Stack[%d] / C[%d])"):format(a, b, _G.getMappedConstant(ci))
end

return OpCodes
