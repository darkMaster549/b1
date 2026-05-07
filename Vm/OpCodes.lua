-- =============================================================================
-- Vm/OpCodes.lua
-- Unified opcode handler table for Lua 5.1 (opcodes 0-38) and Luau (0-81).
--
-- CUSTOM OPCODE IDs:
--   On every run a Fisher-Yates shuffle maps real opcode numbers to random
--   custom IDs.  The serialised bytecode stores the custom IDs, and the VM
--   dispatch table is keyed by those same custom IDs, so they match at
--   runtime.  An attacker sees no standard 0/1/2/… sequence — they see e.g.
--   37/14/62/… with no obvious pattern.
--
--   You can name your custom IDs anything in comments.  For example:
--     CustomID for MOVE  = 0x4T0  (stored as a number, e.g. 74)
--   Just document them below after generating a fixed map if you want stable
--   names across runs.  For maximum obfuscation leave the random shuffle on.
--
-- HOW TO USE:
--   In Pipeline.lua / TreeGenerator, replace:
--     local handler = OpCodeFiles[instruction.Opcode]
--   with:
--     local OpcodeModule = require("Vm.OpCodes")
--     local handler = OpcodeModule.getHandler(instruction.Opcode)
--     -- The Enums patch is applied automatically when you require this module.
-- =============================================================================

local settings = require("Input.Settings")

-- ---------------------------------------------------------------------------
-- Shuffle utility
-- ---------------------------------------------------------------------------
local function makeShuffle(count)
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))
    local perm = {}
    for i = 0, count - 1 do perm[i] = i end
    for i = count - 1, 1, -1 do
        local j = math.random(0, i)
        perm[i], perm[j] = perm[j], perm[i]
    end
    -- perm[realOpcode] = customID
    local inv = {}
    for real, cid in pairs(perm) do inv[cid] = real end
    -- inv[customID] = realOpcode
    return perm, inv
end

local LUA51_COUNT = 39
local LUAU_COUNT  = 82

local Lua51Perm, Lua51Inv = makeShuffle(LUA51_COUNT)
local LuauPerm,  LuauInv  = makeShuffle(LUAU_COUNT)

local ActivePerm = settings.LuauMode and LuauPerm or Lua51Perm
local ActiveInv  = settings.LuauMode and LuauInv  or Lua51Inv

-- ---------------------------------------------------------------------------
-- Code-gen helpers (previously _G.getReg / _G.getMappedConstant)
-- ---------------------------------------------------------------------------
local function getReg(inst, field, asRK)
    if asRK then
        local v = inst[field]
        if type(v) == "table" then return v end
        return { k = false, i = v }
    end
    local v = inst[field]
    if type(v) == "table" then return v.i end
    return v or 0
end

local function constAccess(rk)
    if rk.k then
        return ("C[%d]"):format(rk.i)
    else
        return ("Stack[%d]"):format(rk.i)
    end
end

-- ---------------------------------------------------------------------------
-- LUA 5.1 HANDLERS  (keyed by REAL opcode 0-38)
-- ---------------------------------------------------------------------------
local Lua51 = {}

-- 0: MOVE
Lua51[0] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = Stack[%d]"):format(a, b)
end

-- 1: LOADK
Lua51[1] = function(inst, shift, const, cfg)
    local bx = inst.Bx or getReg(inst, "B")
    return ("\tStack[:A:] = C[%d]"):format(bx)
end

-- 2: LOADBOOL
Lua51[2] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    local bval = b == 1 and "true" or "false"
    if c ~= 0 then
        return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(a, bval)
    end
    return ("\tStack[%d] = %s"):format(a, bval)
end

-- 3: LOADNIL
Lua51[3] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    if b == 0 then
        return ("\tStack[%d] = nil"):format(a)
    end
    local parts = {}
    for i = 0, b do parts[#parts+1] = ("Stack[%d]"):format(a + i) end
    return ("\t%s = nil"):format(table.concat(parts, ", "))
end

-- 4: GETUPVAL
Lua51[4] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = Upvalues[%d]"):format(a, b)
end

-- 5: GETGLOBAL
Lua51[5] = function(inst, shift, const, cfg)
    local bx = inst.Bx or getReg(inst, "B")
    return ("\tStack[:A:] = Env[C[%d]]"):format(bx)
end

-- 6: GETTABLE
Lua51[6] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local b  = getReg(inst, "B")
    local rc = getReg(inst, "C", true)
    return ("\tStack[%d] = Stack[%d][%s]"):format(a, b, constAccess(rc))
end

-- 7: SETGLOBAL
Lua51[7] = function(inst, shift, const, cfg)
    local bx = inst.Bx or getReg(inst, "B")
    return ("\tEnv[C[%d]] = Stack[:A:]"):format(bx)
end

-- 8: SETUPVAL
Lua51[8] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tUpvalues[%d] = Stack[%d]"):format(b, a)
end

-- 9: SETTABLE
Lua51[9] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[%d][%s] = %s"):format(a, constAccess(rb), constAccess(rc))
end

-- 10: NEWTABLE
Lua51[10] = function(inst, shift, const, cfg)
    return "\tStack[:A:] = {}"
end

-- 11: SELF
Lua51[11] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local b  = getReg(inst, "B")
    local rc = getReg(inst, "C", true)
    return ([=[
	Stack[%d] = Stack[%d]
	if Stack[%d] then
		Stack[%d] = Stack[%d][%s]
	end
	]=]):format(a+1, b, a+1, a, b, constAccess(rc))
end

-- 12: ADD
Lua51[12] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s + %s"):format(constAccess(rb), constAccess(rc))
end

-- 13: SUB
Lua51[13] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s - %s"):format(constAccess(rb), constAccess(rc))
end

-- 14: MUL
Lua51[14] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s * %s"):format(constAccess(rb), constAccess(rc))
end

-- 15: DIV
Lua51[15] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s / %s"):format(constAccess(rb), constAccess(rc))
end

-- 16: MOD
Lua51[16] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s %% %s"):format(constAccess(rb), constAccess(rc))
end

-- 17: POW
Lua51[17] = function(inst, shift, const, cfg)
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    return ("\tStack[:A:] = %s ^ %s"):format(constAccess(rb), constAccess(rc))
end

-- 18: UNM
Lua51[18] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = -Stack[%d]"):format(a, b)
end

-- 19: NOT
Lua51[19] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = not Stack[%d]"):format(a, b)
end

-- 20: LEN
Lua51[20] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = #Stack[%d]"):format(a, b)
end

-- 21: CONCAT
Lua51[21] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    return ([=[
	local _out = ""
	for _i = %d, %d do
		_out = _out .. Stack[_i]
	end
	Stack[%d] = _out
	]=]):format(b, c, a)
end

-- 22: JMP
Lua51[22] = function(inst, shift, const, cfg)
    local dbg = (cfg and cfg.Debug) and "print('[VM]:','JMP->',pointer)" or ""
    if cfg and cfg.LuaU_Syntax then
        return ("pointer += :B: - 1 " .. dbg)
    end
    return ("pointer = pointer + :B: " .. dbg)
end

-- 23: EQ
Lua51[23] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    local op = a > 0 and "~=" or "=="
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(constAccess(rb), op, constAccess(rc))
end

-- 24: LT
Lua51[24] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    local op = a > 0 and ">" or "<"
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(constAccess(rb), op, constAccess(rc))
end

-- 25: LE
Lua51[25] = function(inst, shift, const, cfg)
    local a  = getReg(inst, "A")
    local rb = getReg(inst, "B", true)
    local rc = getReg(inst, "C", true)
    local op = a > 0 and ">=" or "<="
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(constAccess(rb), op, constAccess(rc))
end

-- 26: TEST
Lua51[26] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local c = getReg(inst, "C")
    local chk = c == 0 and ("Stack[%d]"):format(a) or ("not Stack[%d]"):format(a)
    return ("\tif %s then pointer = pointer + 1 end"):format(chk)
end

-- 27: TESTSET
Lua51[27] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    local not_ = c ~= 0 and "not " or ""
    return ([=[
	if (%sStack[%d]) then
		pointer = pointer + 1
	else
		Stack[%d] = Stack[%d]
	end
	]=]):format(not_, b, a, b)
end

-- 28: CALL
Lua51[28] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")

    -- variable arg count from top
    if b == 0 then
        local ret
        if c < 1 then
            ret = [=[
	local _rlen = #_Results
	if _rlen == 0 then
		Stack[:A:] = nil; top = :A:
	else
		top = :A: + _rlen - 1
		for _ri = 1, _rlen do Stack[:A: + _ri - 1] = _Results[_ri] end
	end
	]=]
        else
            ret = ("	for _ri = 1, %d do Stack[:A: + _ri - 1] = _Results[_ri] end"):format(c - 1)
        end
        return ([=[
	local _CallArgs = {}
	for _ci = :A: + 1, top do _CallArgs[_ci - :A:] = Stack[_ci] end
	local _Results = {Stack[:A:](table.unpack(_CallArgs, 1, top - :A:))}
	%s
	]=]):format(ret)
    end

    -- fixed arg count
    local args = {}
    for i = 1, b - 1 do args[#args+1] = ("Stack[%d]"):format(a + i) end
    local argStr = table.concat(args, ", ")

    if c < 1 then
        return ([=[
	local _Results = {Stack[:A:](%s)}
	local _rlen = #_Results
	if _rlen == 0 then
		Stack[:A:] = nil; top = :A:
	else
		top = :A: + _rlen - 1
		for _ri = 1, _rlen do Stack[:A: + _ri - 1] = _Results[_ri] end
	end
	]=]):format(argStr)
    elseif c == 1 then
        return ("\tStack[:A:](%s)"):format(argStr)
    elseif c == 2 then
        return ("\tStack[:A:] = Stack[:A:](%s)"):format(argStr)
    else
        local rets = {}
        for i = 0, c - 2 do rets[#rets+1] = ("Stack[%d]"):format(a + i) end
        return ("\t%s = Stack[:A:](%s)"):format(table.concat(rets, ", "), argStr)
    end
end

-- 29: TAILCALL
Lua51[29] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    if b == 0 then
        return ([=[
	local _targs = {}
	for _ti = %d + 1, top do _targs[_ti - %d] = Stack[_ti] end
	return Stack[%d](table.unpack(_targs, 1, top - %d))
	]=]):format(a, a, a, a)
    end
    local args = {}
    for i = 1, b - 1 do args[#args+1] = ("Stack[%d]"):format(a + i) end
    return ("\treturn Stack[%d](%s)"):format(a, table.concat(args, ", "))
end

-- 30: RETURN
Lua51[30] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    if b == 0 then
        return [=[
	local _out = {}
	local _n = 0
	for _ri = :A:, top do
		_n = _n + 1
		_out[_n] = Stack[_ri]
	end
	return table.unpack(_out, 1, _n)
	]=]
    elseif b == 1 then
        return "\treturn"
    elseif b == 2 then
        return ("\treturn Stack[%d]"):format(a)
    else
        local rets = {}
        for i = 0, b - 2 do rets[#rets+1] = ("Stack[%d]"):format(a + i) end
        return ("\treturn %s"):format(table.concat(rets, ", "))
    end
end

-- 31: FORLOOP
Lua51[31] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ([=[
	Stack[%d] = Stack[%d] + Stack[%d]
	if Stack[%d] <= Stack[%d] then
		pointer = pointer + :B:
		Stack[%d] = Stack[%d]
	end
	]=]):format(a, a, a+2, a, a+1, a+3, a)
end

-- 32: FORPREP
Lua51[32] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ([=[
	Stack[%d] = Stack[%d] - Stack[%d]
	pointer = pointer + :B:
	]=]):format(a, a, a+2)
end

-- 33: TFORLOOP
Lua51[33] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local c = getReg(inst, "C")
    local rets = {}
    for i = 3, 2 + c do rets[#rets+1] = ("Stack[%d]"):format(a + i) end
    local retStr = table.concat(rets, ", ")
    return ([=[
	%s = Stack[%d](Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then
		Stack[%d] = Stack[%d]
	else
		pointer = pointer + 1
	end
	]=]):format(retStr, a, a+1, a+2, a+3, a+2, a+3)
end

-- 34: SETLIST
Lua51[34] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    if b == 0 then
        return ([=[
	local _base = (%d - 1) * 50
	for _si = :A: + 1, top do
		Stack[%d][_base + (_si - :A:)] = Stack[_si]
	end
	]=]):format(c, a)
    end
    local lines = {}
    for i = 1, b do
        lines[#lines+1] = ("Stack[%d][%d] = Stack[%d]"):format(a, (c-1)*50 + i, a + i)
    end
    return "\t" .. table.concat(lines, "\n\t")
end

-- 35: CLOSE
Lua51[35] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ("-- CLOSE upvalues >= Stack[%d]"):format(a)
end

-- 36: CLOSURE
Lua51[36] = function(inst, shift, const, cfg)
    local bx = inst.Bx or getReg(inst, "B")
    return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(bx)
end

-- 37: VARARG
Lua51[37] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    if b == 0 then
        return ([=[
	local _va = {...}
	top = %d + #_va - 1
	for _vi = 1, #_va do Stack[%d + _vi - 1] = _va[_vi] end
	]=]):format(a, a)
    end
    local parts = {}
    for i = 0, b - 1 do parts[#parts+1] = ("Stack[%d]"):format(a + i) end
    return ("\t%s = ..."):format(table.concat(parts, ", "))
end

-- 38: INVALID
Lua51[38] = function(inst, shift, const, cfg)
    return "\terror('invalid opcode')"
end

-- ---------------------------------------------------------------------------
-- LUAU HANDLERS  (keyed by REAL opcode 0-81)
-- ---------------------------------------------------------------------------
local Luau = {}

-- 0: NOP
Luau[0] = function(inst, shift, const, cfg)
    return "\t-- NOP"
end

-- 1: BREAK
Luau[1] = function(inst, shift, const, cfg)
    return "\t-- BREAK (debugger)"
end

-- 2: LOADNIL   R(A) = nil
Luau[2] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ("\tStack[%d] = nil"):format(a)
end

-- 3: LOADB   R(A) = (bool)B; if C then pc++
Luau[3] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    local bval = b ~= 0 and "true" or "false"
    if c ~= 0 then
        return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(a, bval)
    end
    return ("\tStack[%d] = %s"):format(a, bval)
end

-- 4: LOADN   R(A) = D (integer literal)
Luau[4] = function(inst, shift, const, cfg)
    local d = inst.D or inst.sBx or 0
    return ("\tStack[:A:] = %d"):format(d)
end

-- 5: LOADK   R(A) = K(D)
Luau[5] = function(inst, shift, const, cfg)
    local d = inst.D or inst.Bx or 0
    return ("\tStack[:A:] = C[%d]"):format(d)
end

-- 6: MOVE   R(A) = R(B)
Luau[6] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = Stack[%d]"):format(a, b)
end

-- 7: GETUPVAL   R(A) = UpValue[B]
Luau[7] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tStack[%d] = Upvalues[%d]"):format(a, b)
end

-- 8: SETUPVAL   UpValue[B] = R(A)
Luau[8] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("\tUpvalues[%d] = Stack[%d]"):format(b, a)
end

-- 9: CLOSEUPVALS
Luau[9] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ("-- CLOSEUPVALS >= Stack[%d]"):format(a)
end

-- 10: GETIMPORT   R(A) = Import[D]
Luau[10] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ("\tStack[:A:] = C[%d]"):format(d)
end

-- 11: GETTABLE   R(A) = R(B)[R(C)]
Luau[11] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d][Stack[%d]]"):format(a, b, c)
end

-- 12: SETTABLE   R(A)[R(B)] = R(C)
Luau[12] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    return ("\tStack[%d][Stack[%d]] = Stack[%d]"):format(a, b, c)
end

-- 13: GETTABLEKS   R(A) = R(B)[K(AUX)]
Luau[13] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local b   = getReg(inst, "B")
    local aux = inst.AUX or 0
    return ("\tStack[%d] = Stack[%d][C[%d]]"):format(a, b, aux)
end

-- 14: SETTABLEKS   R(A)[K(AUX)] = R(B)
Luau[14] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local b   = getReg(inst, "B")
    local aux = inst.AUX or 0
    return ("\tStack[%d][C[%d]] = Stack[%d]"):format(a, aux, b)
end

-- 15: GETTABLEN   R(A) = R(B)[C]
Luau[15] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d][%d]"):format(a, b, c)
end

-- 16: SETTABLEN   R(A)[C] = R(B)
Luau[16] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    return ("\tStack[%d][%d] = Stack[%d]"):format(a, c, b)
end

-- 17: NEWCLOSURE   R(A) = closure(Proto[D])
Luau[17] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(d)
end

-- 18: NAMECALL   R(A+1)=R(B); R(A)=R(B)[K(AUX)]
Luau[18] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local b   = getReg(inst, "B")
    local aux = inst.AUX or 0
    return ([=[
	Stack[%d] = Stack[%d]
	Stack[%d] = Stack[%d][C[%d]]
	]=]):format(a+1, b, a, b, aux)
end

-- 19: CALL   R(A),..,R(A+C-2) = R(A)(R(A+1),..,R(A+B-1))
Luau[19] = Lua51[28]  -- same call logic

-- 20: RETURN
Luau[20] = Lua51[30]

-- 21: JUMP   pc += E
Luau[21] = function(inst, shift, const, cfg)
    local e = inst.E or inst.D or 0
    local dbg = (cfg and cfg.Debug) and "print('[VM]:','JUMP->',pointer)" or ""
    return ("pointer = pointer + " .. e .. " " .. dbg)
end

-- 22: JUMPBACK   pc += E (backward)
Luau[22] = function(inst, shift, const, cfg)
    local e = inst.E or inst.D or 0
    return ("pointer = pointer + " .. e)
end

-- 23: JUMPIF   if R(A) then pc += D
Luau[23] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ("\tif Stack[%d] then pointer = pointer + %d end"):format(a, d)
end

-- 24: JUMPIFNOT   if not R(A) then pc += D
Luau[24] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ("\tif not Stack[%d] then pointer = pointer + %d end"):format(a, d)
end

-- 25: JUMPIFEQ
Luau[25] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif Stack[%d] == Stack[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 26: JUMPIFLE
Luau[26] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif Stack[%d] <= Stack[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 27: JUMPIFLT
Luau[27] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif Stack[%d] < Stack[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 28: JUMPIFNOTEQ
Luau[28] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif Stack[%d] ~= Stack[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 29: JUMPIFNOTLE
Luau[29] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif not (Stack[%d] <= Stack[%d]) then pointer = pointer + %d end"):format(a, aux, d)
end

-- 30: JUMPIFNOTLT
Luau[30] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 0
    return ("\tif not (Stack[%d] < Stack[%d]) then pointer = pointer + %d end"):format(a, aux, d)
end

-- 31: ADD   R(A) = R(B) + R(C)
Luau[31] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] + Stack[%d]"):format(a, b, c)
end

-- 32: SUB
Luau[32] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] - Stack[%d]"):format(a, b, c)
end

-- 33: MUL
Luau[33] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] * Stack[%d]"):format(a, b, c)
end

-- 34: DIV
Luau[34] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] / Stack[%d]"):format(a, b, c)
end

-- 35: MOD
Luau[35] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] %% Stack[%d]"):format(a, b, c)
end

-- 36: POW
Luau[36] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] ^ Stack[%d]"):format(a, b, c)
end

-- 37: ADDK   R(A) = R(B) + K(C)
Luau[37] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] + C[%d]"):format(a, b, c)
end

-- 38: SUBK
Luau[38] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] - C[%d]"):format(a, b, c)
end

-- 39: MULK
Luau[39] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] * C[%d]"):format(a, b, c)
end

-- 40: DIVK
Luau[40] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] / C[%d]"):format(a, b, c)
end

-- 41: MODK
Luau[41] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] %% C[%d]"):format(a, b, c)
end

-- 42: POWK
Luau[42] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] ^ C[%d]"):format(a, b, c)
end

-- 43: AND   R(A) = R(B) and R(C)
Luau[43] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] and Stack[%d]"):format(a, b, c)
end

-- 44: OR
Luau[44] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] or Stack[%d]"):format(a, b, c)
end

-- 45: ANDK   R(A) = R(B) and K(C)
Luau[45] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] and C[%d]"):format(a, b, c)
end

-- 46: ORK
Luau[46] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = Stack[%d] or C[%d]"):format(a, b, c)
end

-- 47: CONCAT   R(A) = R(B)..…..R(C)
Luau[47] = Lua51[21]

-- 48: NOT
Luau[48] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B")
    return ("\tStack[%d] = not Stack[%d]"):format(a, b)
end

-- 49: MINUS  R(A) = -R(B)
Luau[49] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B")
    return ("\tStack[%d] = -Stack[%d]"):format(a, b)
end

-- 50: LENGTH  R(A) = #R(B)
Luau[50] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B")
    return ("\tStack[%d] = #Stack[%d]"):format(a, b)
end

-- 51: NEWTABLE
Luau[51] = function(inst, shift, const, cfg)
    return "\tStack[:A:] = {}"
end

-- 52: DUPTABLE   R(A) = duplicate(K(D))
Luau[52] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ([=[
	do
		local _tmpl = C[%d]
		local _dup = {}
		for _k, _v in pairs(_tmpl) do _dup[_k] = _v end
		Stack[:A:] = _dup
	end
	]=]):format(d)
end

-- 53: SETLIST
Luau[53] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    local c = getReg(inst, "C")
    local lines = {}
    for i = 1, c do
        lines[#lines+1] = ("Stack[%d][%d] = Stack[%d]"):format(a, b - 1 + i, a + i)
    end
    return "\t" .. table.concat(lines, "\n\t")
end

-- 54: FORNPREP   prepare numeric for; jump D if invalid
Luau[54] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ([=[
	Stack[%d] = Stack[%d] - Stack[%d]
	if Stack[%d] == 0 then pointer = pointer + %d end
	]=]):format(a, a, a+2, a+2, d)
end

-- 55: FORNLOOP   numeric for step; jump D if not done
Luau[55] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ([=[
	Stack[%d] = Stack[%d] + Stack[%d]
	if Stack[%d] <= Stack[%d] then
		pointer = pointer + %d
		Stack[%d] = Stack[%d]
	end
	]=]):format(a, a, a+2, a, a+1, d, a+3, a)
end

-- 56: FORGPREP   prepare generic for, jump D
Luau[56] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ("pointer = pointer + " .. d)
end

-- 57: FORGLOOP   generic for step
Luau[57] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A")
    local d   = inst.D or 0
    local aux = inst.AUX or 1
    local rets = {}
    for i = 3, 2 + aux do rets[#rets+1] = ("Stack[%d]"):format(a + i) end
    return ([=[
	%s = Stack[%d](Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then
		Stack[%d] = Stack[%d]
		pointer = pointer + %d
	end
	]=]):format(table.concat(rets, ", "), a, a+1, a+2, a+3, a+2, a+3, d)
end

-- 58: FORGPREP_INEXT
Luau[58] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ("pointer = pointer + " .. d)
end

-- 59: FORGLOOP_INEXT
Luau[59] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ([=[
	Stack[%d], Stack[%d] = next(Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then pointer = pointer + %d end
	]=]):format(a+3, a+4, a+1, a+2, a+3, d)
end

-- 60: FORGPREP_NEXT
Luau[60] = Luau[58]

-- 61: FORGLOOP_NEXT
Luau[61] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local d = inst.D or 0
    return ([=[
	Stack[%d], Stack[%d] = next(Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then pointer = pointer + %d end
	]=]):format(a+3, a+4, a+1, a+2, a+3, d)
end

-- 62: GETVARARGS   R(A)..R(A+B-1) = vararg
Luau[62] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    if b == 0 then
        return ([=[
	local _va = {...}
	top = %d + #_va - 1
	for _vi = 1, #_va do Stack[%d + _vi - 1] = _va[_vi] end
	]=]):format(a, a)
    end
    local parts = {}
    for i = 0, b - 1 do parts[#parts+1] = ("Stack[%d]"):format(a + i) end
    return ("\t%s = ..."):format(table.concat(parts, ", "))
end

-- 63: DUPCLOSURE   R(A) = closure(Proto[D])
Luau[63] = function(inst, shift, const, cfg)
    local d = inst.D or 0
    return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(d)
end

-- 64: PREPVARARGS
Luau[64] = function(inst, shift, const, cfg)
    return "\t-- PREPVARARGS"
end

-- 65: LOADKX   R(A) = K(AUX)
Luau[65] = function(inst, shift, const, cfg)
    local aux = inst.AUX or 0
    return ("\tStack[:A:] = C[%d]"):format(aux)
end

-- 66: JUMPX   pc += E (extended)
Luau[66] = function(inst, shift, const, cfg)
    local e = inst.E or inst.D or 0
    return ("pointer = pointer + " .. e)
end

-- 67: FASTCALL   fast call to builtin A
Luau[67] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    return ("-- FASTCALL builtin " .. a)
end

-- 68: COVERAGE
Luau[68] = function(inst, shift, const, cfg)
    return "\t-- COVERAGE"
end

-- 69: CAPTURE   capture upvalue
Luau[69] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A")
    local b = getReg(inst, "B")
    return ("-- CAPTURE type=%d src=%d"):format(a, b)
end

-- 70: SUBRK   R(A) = K(B) - R(C)
Luau[70] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = C[%d] - Stack[%d]"):format(a, b, c)
end

-- 71: DIVRK   R(A) = K(B) / R(C)
Luau[71] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = C[%d] / Stack[%d]"):format(a, b, c)
end

-- 72: FASTCALL1
Luau[72] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B")
    return ("-- FASTCALL1 builtin=%d arg=Stack[%d]"):format(a, b)
end

-- 73: FASTCALL2
Luau[73] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A"); local b = getReg(inst, "B"); local aux = inst.AUX or 0
    return ("-- FASTCALL2 builtin=%d args=Stack[%d],Stack[%d]"):format(a, b, aux)
end

-- 74: FASTCALL2K
Luau[74] = function(inst, shift, const, cfg)
    local a   = getReg(inst, "A"); local b = getReg(inst, "B"); local aux = inst.AUX or 0
    return ("-- FASTCALL2K builtin=%d args=Stack[%d],C[%d]"):format(a, b, aux)
end

-- 75: FORGPREP (v3+)
Luau[75] = Luau[56]

-- 76: JUMPXEQKNIL
Luau[76] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local d = inst.D or 0; local aux = inst.AUX or 0
    local not_ = (aux ~= 0) and "not " or ""
    return ("\tif %s(Stack[%d] == nil) then pointer = pointer + %d end"):format(not_, a, d)
end

-- 77: JUMPXEQKB
Luau[77] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local d = inst.D or 0; local aux = inst.AUX or 0
    local bval = (aux % 2 == 1) and "true" or "false"
    local not_  = (aux >= 2) and "not " or ""
    return ("\tif %s(Stack[%d] == %s) then pointer = pointer + %d end"):format(not_, a, bval, d)
end

-- 78: JUMPXEQKN
Luau[78] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local d = inst.D or 0; local aux = inst.AUX or 0
    return ("\tif Stack[%d] == C[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 79: JUMPXEQKS
Luau[79] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local d = inst.D or 0; local aux = inst.AUX or 0
    return ("\tif Stack[%d] == C[%d] then pointer = pointer + %d end"):format(a, aux, d)
end

-- 80: IDIV   R(A) = floor(R(B) / R(C))
Luau[80] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = math.floor(Stack[%d] / Stack[%d])"):format(a, b, c)
end

-- 81: IDIVK   R(A) = floor(R(B) / K(C))
Luau[81] = function(inst, shift, const, cfg)
    local a = getReg(inst, "A"); local b = getReg(inst, "B"); local c = getReg(inst, "C")
    return ("\tStack[%d] = math.floor(Stack[%d] / C[%d])"):format(a, b, c)
end

-- ---------------------------------------------------------------------------
-- Build the SHUFFLED dispatch tables
-- realOpcode → customID via ActivePerm
-- The VM loop calls:  Handlers[customID](inst, ...)
-- ---------------------------------------------------------------------------
local function buildShuffledTable(realHandlers, perm)
    local t = {}
    for realOp, handler in pairs(realHandlers) do
        local cid = perm[realOp]
        if cid ~= nil then
            t[cid] = handler
        end
    end
    return t
end

local Lua51Dispatch = buildShuffledTable(Lua51, Lua51Perm)
local LuauDispatch  = buildShuffledTable(Luau,  LuauPerm)

local ActiveDispatch = settings.LuauMode and LuauDispatch or Lua51Dispatch

-- ---------------------------------------------------------------------------
-- Patch Enums so BytecodeParser writes custom IDs into each instruction
-- Call this ONCE before parsing starts (Pipeline.lua does it automatically
-- when it requires this module).
-- ---------------------------------------------------------------------------
local function patchEnums()
    local Enums = require("Bytecode.Enums")
    local perm  = settings.LuauMode and LuauPerm or Lua51Perm
    for realOp, entry in pairs(Enums) do
        local cid = perm[realOp]
        if cid ~= nil then
            entry.CustomID = cid   -- TreeGenerator reads inst.CustomID
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns the code-gen handler for a REAL opcode number.
-- Used by TreeGenerator when building the VM source.
local function getHandler(realOpcode)
    local t = settings.LuauMode and Luau or Lua51
    return t[realOpcode]
end

-- Returns the custom ID that will be stored in bytecode for a real opcode.
local function getCustomID(realOpcode)
    return ActivePerm[realOpcode]
end

-- Returns the real opcode for a custom ID (for the runtime VM decoder).
local function getRealOpcode(customID)
    return ActiveInv[customID]
end

-- The shuffled dispatch table — key it into your VM loop directly.
local function getDispatch()
    return ActiveDispatch
end

-- Expose shuffle maps for any module that needs them.
local function getShuffleMaps()
    return {
        lua51Perm = Lua51Perm,
        lua51Inv  = Lua51Inv,
        luauPerm  = LuauPerm,
        luauInv   = LuauInv,
        active    = ActivePerm,
        activeInv = ActiveInv,
    }
end

-- Auto-patch Enums on require so everything is wired up immediately.
patchEnums()

return {
    -- Code-gen (obfuscator side)
    getHandler    = getHandler,
    getCustomID   = getCustomID,
    getDispatch   = getDispatch,
    getShuffleMaps= getShuffleMaps,
    patchEnums    = patchEnums,

    -- Runtime (output VM side) — use getDispatch() table in the VM loop
    getRealOpcode = getRealOpcode,

    -- Raw handler tables (real-opcode-keyed) if you need them
    Lua51 = Lua51,
    Luau  = Luau,

    -- Shuffled dispatch tables (customID-keyed)
    Lua51Dispatch = Lua51Dispatch,
    LuauDispatch  = LuauDispatch,
}
