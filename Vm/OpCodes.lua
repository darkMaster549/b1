-- =============================================================================
-- Vm/OpCodes.lua  —  Unified opcode handlers + custom ID shuffle
--
-- HOW IT WORKS:
--   On every obfuscation run, a Fisher-Yates shuffle maps each real opcode
--   number to a random "custom ID".  The serialised bytecode stores custom IDs,
--   and the runtime VM dispatch table is keyed by those same custom IDs, so
--   they always match.  An attacker sees no standard 0/1/2/... sequence.
--
-- HOW TO USE IN H.lua / TreeGenerator:
--   local OC = require("Vm.OpCodes")
--   -- get the custom ID for a real opcode before emitting bytecode:
--   local cid = OC.toCustom(inst.Opcode)
--   -- get the handler code string for a real opcode:
--   local code = OC.handle(inst.Opcode, inst, shift, const, settings)
--   -- get the full dispatch table string to embed in the output VM:
--   local dispatchSrc = OC.dispatchTableSource()
-- =============================================================================

local settings = require("Input.Settings")

-- ---------------------------------------------------------------------------
-- 1. Shuffle helpers
-- ---------------------------------------------------------------------------
local function makeShuffle(count)
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))
    local perm, inv = {}, {}
    for i = 0, count - 1 do perm[i] = i end
    for i = count - 1, 1, -1 do
        local j = math.random(0, i)
        perm[i], perm[j] = perm[j], perm[i]
    end
    for real, cid in pairs(perm) do inv[cid] = real end
    return perm, inv  -- perm[real] = customID,  inv[customID] = real
end

local LUA51_COUNT = 39   -- opcodes 0-38
local LUAU_COUNT  = 82   -- opcodes 0-81

local Lua51Perm, Lua51Inv = makeShuffle(LUA51_COUNT)
local LuauPerm,  LuauInv  = makeShuffle(LUAU_COUNT)

local ActivePerm = settings.LuauMode and LuauPerm or Lua51Perm
local ActiveInv  = settings.LuauMode and LuauInv  or Lua51Inv

-- ---------------------------------------------------------------------------
-- 2. Helper used in handlers (mirrors old _G.getReg / _G.getMappedConstant)
-- ---------------------------------------------------------------------------
local function getReg(inst, field, asRK)
    if asRK then
        local v = inst[field]
        if type(v) == "table" then return v end
        return { k = false, i = v or 0 }
    end
    local v = inst[field]
    if type(v) == "table" then return v.i end
    return v or 0
end

local function ca(rk)   -- constant access string
    if rk.k then return ("C[%d]"):format(rk.i) end
    return ("Stack[%d]"):format(rk.i)
end

-- ---------------------------------------------------------------------------
-- 3. LUA 5.1 handlers  (keyed by REAL opcode 0-38)
-- ---------------------------------------------------------------------------
local L51 = {}

-- 0 MOVE
L51[0] = function(inst, shift, const, cfg)
    return ("\tStack[%d] = Stack[%d]"):format(getReg(inst,"A"), getReg(inst,"B"))
end
-- 1 LOADK
L51[1] = function(inst, shift, const, cfg)
    return ("\tStack[:A:] = C[%d]"):format(inst.Bx or getReg(inst,"B"))
end
-- 2 LOADBOOL
L51[2] = function(inst, shift, const, cfg)
    local a,b,c = getReg(inst,"A"), getReg(inst,"B"), getReg(inst,"C")
    local bv = b==1 and "true" or "false"
    if c~=0 then return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(a,bv) end
    return ("\tStack[%d] = %s"):format(a,bv)
end
-- 3 LOADNIL
L51[3] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    if b==0 then return ("\tStack[%d] = nil"):format(a) end
    local t={}; for i=0,b do t[#t+1]=("Stack[%d]"):format(a+i) end
    return ("\t%s = nil"):format(table.concat(t,", "))
end
-- 4 GETUPVAL
L51[4] = function(inst, shift, const, cfg)
    return ("\tStack[%d] = Upvalues[%d]"):format(getReg(inst,"A"), getReg(inst,"B"))
end
-- 5 GETGLOBAL
L51[5] = function(inst, shift, const, cfg)
    return ("\tStack[:A:] = Env[C[%d]]"):format(inst.Bx or getReg(inst,"B"))
end
-- 6 GETTABLE
L51[6] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    return ("\tStack[%d] = Stack[%d][%s]"):format(a, b, ca(getReg(inst,"C",true)))
end
-- 7 SETGLOBAL
L51[7] = function(inst, shift, const, cfg)
    return ("\tEnv[C[%d]] = Stack[:A:]"):format(inst.Bx or getReg(inst,"B"))
end
-- 8 SETUPVAL
L51[8] = function(inst, shift, const, cfg)
    return ("\tUpvalues[%d] = Stack[%d]"):format(getReg(inst,"B"), getReg(inst,"A"))
end
-- 9 SETTABLE
L51[9] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    return ("\tStack[%d][%s] = %s"):format(a, ca(getReg(inst,"B",true)), ca(getReg(inst,"C",true)))
end
-- 10 NEWTABLE
L51[10] = function(inst, shift, const, cfg) return "\tStack[:A:] = {}" end
-- 11 SELF
L51[11] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    return ([=[
	Stack[%d] = Stack[%d]
	if Stack[%d] then
		Stack[%d] = Stack[%d][%s]
	end
	]=]):format(a+1,b, a+1, a,b, ca(getReg(inst,"C",true)))
end
-- 12-17 Arithmetic
local arithSym = {[12]="+",[13]="-",[14]="*",[15]="/",[16]="%%",[17]="^"}
for op,sym in pairs(arithSym) do
    local s=sym
    L51[op] = function(inst, shift, const, cfg)
        return ("\tStack[:A:] = %s %s %s"):format(ca(getReg(inst,"B",true)), s, ca(getReg(inst,"C",true)))
    end
end
-- 18 UNM
L51[18] = function(inst, shift, const, cfg)
    return ("\tStack[%d] = -Stack[%d]"):format(getReg(inst,"A"), getReg(inst,"B"))
end
-- 19 NOT
L51[19] = function(inst, shift, const, cfg)
    return ("\tStack[%d] = not Stack[%d]"):format(getReg(inst,"A"), getReg(inst,"B"))
end
-- 20 LEN
L51[20] = function(inst, shift, const, cfg)
    return ("\tStack[%d] = #Stack[%d]"):format(getReg(inst,"A"), getReg(inst,"B"))
end
-- 21 CONCAT
L51[21] = function(inst, shift, const, cfg)
    local a,b,c = getReg(inst,"A"), getReg(inst,"B"), getReg(inst,"C")
    return ([=[
	local _out = ""
	for i = %d, %d do _out = _out .. Stack[i] end
	Stack[%d] = _out
	]=]):format(b,c,a)
end
-- 22 JMP
L51[22] = function(inst, shift, const, cfg)
    local dbg = (cfg and cfg.Debug) and "print('[VM]:','JMP->',pointer)" or ""
    if cfg and cfg.LuaU_Syntax then
        return ("pointer += :B: - 1 "..dbg)
    end
    return ("pointer = pointer + :B: "..dbg)
end
-- 23 EQ
L51[23] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    local op = a>0 and "~=" or "=="
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(ca(getReg(inst,"B",true)), op, ca(getReg(inst,"C",true)))
end
-- 24 LT
L51[24] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    local op = a>0 and ">" or "<"
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(ca(getReg(inst,"B",true)), op, ca(getReg(inst,"C",true)))
end
-- 25 LE
L51[25] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    local op = a>0 and ">=" or "<="
    return ("\tif %s %s %s then pointer = pointer + 1 end"):format(ca(getReg(inst,"B",true)), op, ca(getReg(inst,"C",true)))
end
-- 26 TEST
L51[26] = function(inst, shift, const, cfg)
    local a,c = getReg(inst,"A"), getReg(inst,"C")
    local chk = c==0 and ("Stack[%d]"):format(a) or ("not Stack[%d]"):format(a)
    return ("\tif %s then pointer = pointer + 1 end"):format(chk)
end
-- 27 TESTSET
L51[27] = function(inst, shift, const, cfg)
    local a,b,c = getReg(inst,"A"), getReg(inst,"B"), getReg(inst,"C")
    local not_ = c~=0 and "not " or ""
    return ([=[
	if (%sStack[%d]) then
		pointer = pointer + 1
	else
		Stack[%d] = Stack[%d]
	end
	]=]):format(not_,b, a,b)
end
-- 28 CALL
L51[28] = function(inst, shift, const, cfg)
    local a,b,c = getReg(inst,"A"), getReg(inst,"B"), getReg(inst,"C")
    if b==0 then
        local ret
        if c<1 then
            ret = [=[
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil; top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do Stack[:A: + i - 1] = Results[i] end
	end
	]=]
        else
            ret = ("	for i = 1, %d do Stack[:A: + i - 1] = Results[i] end"):format(c-1)
        end
        return ([=[
	local Args = {}
	for i = :A: + 1, top do Args[i - :A:] = Stack[i] end
	local Results = {Stack[:A:](unpack(Args, 1, top - :A:))}
	%s
	]=]):format(ret)
    end
    local args={}
    for i=1,b-1 do args[#args+1]=("Stack[%d]"):format(a+i) end
    local argStr = table.concat(args,", ")
    if c<1 then
        return ([=[
	local Results = {Stack[:A:](%s)}
	local len = #Results
	if len == 0 then
		Stack[:A:] = nil; top = :A:
	else
		top = :A: + len - 1
		for i = 1, len do Stack[:A: + i - 1] = Results[i] end
	end
	]=]):format(argStr)
    elseif c==1 then
        return ("\tStack[:A:](%s)"):format(argStr)
    elseif c==2 then
        return ("\tStack[:A:] = Stack[:A:](%s)"):format(argStr)
    else
        local rets={}
        for i=0,c-2 do rets[#rets+1]=("Stack[%d]"):format(a+i) end
        return ("\t%s = Stack[:A:](%s)"):format(table.concat(rets,", "), argStr)
    end
end
-- 29 TAILCALL
L51[29] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    if b==0 then
        return ([=[
	local _args = {}
	for i = %d + 1, top do _args[i - %d] = Stack[i] end
	return Stack[%d](unpack(_args, 1, top - %d))
	]=]):format(a,a,a,a)
    end
    local args={}
    for i=1,b-1 do args[#args+1]=("Stack[%d]"):format(a+i) end
    return ("\treturn Stack[%d](%s)"):format(a, table.concat(args,", "))
end
-- 30 RETURN
L51[30] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    if b==0 then
        return [=[
	local _out = {}; local _n = 0
	for i = :A:, top do _n=_n+1; _out[_n] = Stack[i] end
	return unpack(_out, 1, _n)
	]=]
    elseif b==1 then return "\treturn"
    elseif b==2 then return ("\treturn Stack[%d]"):format(a)
    else
        local rets={}
        for i=0,b-2 do rets[#rets+1]=("Stack[%d]"):format(a+i) end
        return ("\treturn %s"):format(table.concat(rets,", "))
    end
end
-- 31 FORLOOP
L51[31] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    return ([=[
	Stack[%d] = Stack[%d] + Stack[%d]
	if Stack[%d] <= Stack[%d] then
		pointer = pointer + :B:
		Stack[%d] = Stack[%d]
	end
	]=]):format(a,a,a+2, a,a+1, a+3,a)
end
-- 32 FORPREP
L51[32] = function(inst, shift, const, cfg)
    local a = getReg(inst,"A")
    return ([=[
	Stack[%d] = Stack[%d] - Stack[%d]
	pointer = pointer + :B:
	]=]):format(a,a,a+2)
end
-- 33 TFORLOOP
L51[33] = function(inst, shift, const, cfg)
    local a,c = getReg(inst,"A"), getReg(inst,"C")
    local rets={}
    for i=3,2+c do rets[#rets+1]=("Stack[%d]"):format(a+i) end
    return ([=[
	%s = Stack[%d](Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then
		Stack[%d] = Stack[%d]
	else
		pointer = pointer + 1
	end
	]=]):format(table.concat(rets,", "), a,a+1,a+2, a+3, a+2,a+3)
end
-- 34 SETLIST
L51[34] = function(inst, shift, const, cfg)
    local a,b,c = getReg(inst,"A"), getReg(inst,"B"), getReg(inst,"C")
    if b==0 then
        return ([=[
	local _base = (%d - 1) * 50
	for _si = :A: + 1, top do
		Stack[%d][_base + (_si - :A:)] = Stack[_si]
	end
	]=]):format(c,a)
    end
    local lines={}
    for i=1,b do lines[#lines+1]=("Stack[%d][%d] = Stack[%d]"):format(a,(c-1)*50+i,a+i) end
    return "\t"..table.concat(lines,"\n\t")
end
-- 35 CLOSE
L51[35] = function(inst, shift, const, cfg)
    return ("-- CLOSE upvalues >= Stack[%d]"):format(getReg(inst,"A"))
end
-- 36 CLOSURE
L51[36] = function(inst, shift, const, cfg)
    return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(inst.Bx or getReg(inst,"B"))
end
-- 37 VARARG
L51[37] = function(inst, shift, const, cfg)
    local a,b = getReg(inst,"A"), getReg(inst,"B")
    if b==0 then
        return ([=[
	local _va = {...}
	top = %d + #_va - 1
	for _vi = 1, #_va do Stack[%d + _vi - 1] = _va[_vi] end
	]=]):format(a,a)
    end
    local parts={}
    for i=0,b-1 do parts[#parts+1]=("Stack[%d]"):format(a+i) end
    return ("\t%s = ..."):format(table.concat(parts,", "))
end
-- 38 INVALID
L51[38] = function(inst, shift, const, cfg)
    return "\terror('invalid opcode')"
end

-- ---------------------------------------------------------------------------
-- 4. LUAU handlers  (keyed by REAL opcode 0-81)
-- ---------------------------------------------------------------------------
local LU = {}

LU[0]  = function(i,s,c,cfg) return "\t-- NOP" end
LU[1]  = function(i,s,c,cfg) return "\t-- BREAK" end
LU[2]  = function(i,s,c,cfg) return ("\tStack[%d] = nil"):format(getReg(i,"A")) end
LU[3]  = function(i,s,c,cfg)
    local a,b,cv = getReg(i,"A"), getReg(i,"B"), getReg(i,"C")
    local bv = b~=0 and "true" or "false"
    if cv~=0 then return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(a,bv) end
    return ("\tStack[%d] = %s"):format(a,bv)
end
LU[4]  = function(i,s,c,cfg) return ("\tStack[:A:] = %d"):format(i.D or i.sBx or 0) end
LU[5]  = function(i,s,c,cfg) return ("\tStack[:A:] = C[%d]"):format(i.D or i.Bx or 0) end
LU[6]  = function(i,s,c,cfg) return ("\tStack[%d] = Stack[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[7]  = function(i,s,c,cfg) return ("\tStack[%d] = Upvalues[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[8]  = function(i,s,c,cfg) return ("\tUpvalues[%d] = Stack[%d]"):format(getReg(i,"B"), getReg(i,"A")) end
LU[9]  = function(i,s,c,cfg) return ("-- CLOSEUPVALS >= Stack[%d]"):format(getReg(i,"A")) end
LU[10] = function(i,s,c,cfg) return ("\tStack[:A:] = C[%d]"):format(i.D or 0) end
LU[11] = function(i,s,c,cfg)
    local a,b,cv = getReg(i,"A"), getReg(i,"B"), getReg(i,"C")
    return ("\tStack[%d] = Stack[%d][Stack[%d]]"):format(a,b,cv)
end
LU[12] = function(i,s,c,cfg)
    local a,b,cv = getReg(i,"A"), getReg(i,"B"), getReg(i,"C")
    return ("\tStack[%d][Stack[%d]] = Stack[%d]"):format(a,b,cv)
end
LU[13] = function(i,s,c,cfg)
    return ("\tStack[%d] = Stack[%d][C[%d]]"):format(getReg(i,"A"), getReg(i,"B"), i.AUX or 0)
end
LU[14] = function(i,s,c,cfg)
    return ("\tStack[%d][C[%d]] = Stack[%d]"):format(getReg(i,"A"), i.AUX or 0, getReg(i,"B"))
end
LU[15] = function(i,s,c,cfg)
    return ("\tStack[%d] = Stack[%d][%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C"))
end
LU[16] = function(i,s,c,cfg)
    return ("\tStack[%d][%d] = Stack[%d]"):format(getReg(i,"A"), getReg(i,"C"), getReg(i,"B"))
end
LU[17] = function(i,s,c,cfg) return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(i.D or 0) end
LU[18] = function(i,s,c,cfg)
    local a,b = getReg(i,"A"), getReg(i,"B")
    return ([=[
	Stack[%d] = Stack[%d]
	Stack[%d] = Stack[%d][C[%d]]
	]=]):format(a+1,b, a,b, i.AUX or 0)
end
LU[19] = L51[28]   -- CALL same logic
LU[20] = L51[30]   -- RETURN same logic
LU[21] = function(i,s,c,cfg)
    local dbg = (cfg and cfg.Debug) and "print('[VM]:','JUMP->',pointer)" or ""
    return ("pointer = pointer + "..(i.E or i.D or 0).." "..dbg)
end
LU[22] = function(i,s,c,cfg) return ("pointer = pointer + "..(i.E or i.D or 0)) end
LU[23] = function(i,s,c,cfg) return ("\tif Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.D or 0) end
LU[24] = function(i,s,c,cfg) return ("\tif not Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.D or 0) end
LU[25] = function(i,s,c,cfg) return ("\tif Stack[%d] == Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[26] = function(i,s,c,cfg) return ("\tif Stack[%d] <= Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[27] = function(i,s,c,cfg) return ("\tif Stack[%d] < Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[28] = function(i,s,c,cfg) return ("\tif Stack[%d] ~= Stack[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[29] = function(i,s,c,cfg) return ("\tif not (Stack[%d] <= Stack[%d]) then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[30] = function(i,s,c,cfg) return ("\tif not (Stack[%d] < Stack[%d]) then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end

local luauArith = {[31]="+",[32]="-",[33]="*",[34]="/",[35]="%%",[36]="^"}
for op,sym in pairs(luauArith) do
    local s2=sym
    LU[op] = function(i,_,c,cfg)
        return ("\tStack[%d] = Stack[%d] %s Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), s2, getReg(i,"C"))
    end
end
local luauArithK = {[37]="+",[38]="-",[39]="*",[40]="/",[41]="%%",[42]="^"}
for op,sym in pairs(luauArithK) do
    local s2=sym
    LU[op] = function(i,_,c,cfg)
        return ("\tStack[%d] = Stack[%d] %s C[%d]"):format(getReg(i,"A"), getReg(i,"B"), s2, getReg(i,"C"))
    end
end
LU[43] = function(i,s,c,cfg) return ("\tStack[%d] = Stack[%d] and Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[44] = function(i,s,c,cfg) return ("\tStack[%d] = Stack[%d] or Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[45] = function(i,s,c,cfg) return ("\tStack[%d] = Stack[%d] and C[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[46] = function(i,s,c,cfg) return ("\tStack[%d] = Stack[%d] or C[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[47] = L51[21]  -- CONCAT
LU[48] = function(i,s,c,cfg) return ("\tStack[%d] = not Stack[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[49] = function(i,s,c,cfg) return ("\tStack[%d] = -Stack[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[50] = function(i,s,c,cfg) return ("\tStack[%d] = #Stack[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[51] = function(i,s,c,cfg) return "\tStack[:A:] = {}" end
LU[52] = function(i,s,c,cfg)
    return ([=[
	do
		local _tmpl = C[%d]; local _dup = {}
		for _k,_v in pairs(_tmpl) do _dup[_k]=_v end
		Stack[:A:] = _dup
	end
	]=]):format(i.D or 0)
end
LU[53] = function(i,s,c,cfg)
    local a,b,cv = getReg(i,"A"), getReg(i,"B"), getReg(i,"C")
    local lines={}
    for k=1,cv do lines[#lines+1]=("Stack[%d][%d] = Stack[%d]"):format(a, b-1+k, a+k) end
    return "\t"..table.concat(lines,"\n\t")
end
LU[54] = function(i,s,c,cfg)
    local a,d = getReg(i,"A"), i.D or 0
    return ([=[
	Stack[%d] = Stack[%d] - Stack[%d]
	if Stack[%d] == 0 then pointer = pointer + %d end
	]=]):format(a,a,a+2, a+2,d)
end
LU[55] = function(i,s,c,cfg)
    local a,d = getReg(i,"A"), i.D or 0
    return ([=[
	Stack[%d] = Stack[%d] + Stack[%d]
	if Stack[%d] <= Stack[%d] then
		pointer = pointer + %d
		Stack[%d] = Stack[%d]
	end
	]=]):format(a,a,a+2, a,a+1, d, a+3,a)
end
LU[56] = function(i,s,c,cfg) return ("pointer = pointer + "..(i.D or 0)) end
LU[57] = function(i,s,c,cfg)
    local a,d,aux = getReg(i,"A"), i.D or 0, i.AUX or 1
    local rets={}
    for k=3,2+aux do rets[#rets+1]=("Stack[%d]"):format(a+k) end
    return ([=[
	%s = Stack[%d](Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then
		Stack[%d] = Stack[%d]
		pointer = pointer + %d
	end
	]=]):format(table.concat(rets,", "), a,a+1,a+2, a+3, a+2,a+3, d)
end
LU[58] = LU[56]; LU[59] = function(i,s,c,cfg)
    local a,d = getReg(i,"A"), i.D or 0
    return ([=[
	Stack[%d], Stack[%d] = next(Stack[%d], Stack[%d])
	if Stack[%d] ~= nil then pointer = pointer + %d end
	]=]):format(a+3,a+4, a+1,a+2, a+3, d)
end
LU[60] = LU[56]; LU[61] = LU[59]
LU[62] = L51[37]  -- GETVARARGS same
LU[63] = function(i,s,c,cfg) return ("\tStack[:A:] = Protos[%d](Env, Upvalues)"):format(i.D or 0) end
LU[64] = function(i,s,c,cfg) return "\t-- PREPVARARGS" end
LU[65] = function(i,s,c,cfg) return ("\tStack[:A:] = C[%d]"):format(i.AUX or 0) end
LU[66] = function(i,s,c,cfg) return ("pointer = pointer + "..(i.E or i.D or 0)) end
LU[67] = function(i,s,c,cfg) return ("-- FASTCALL builtin "..getReg(i,"A")) end
LU[68] = function(i,s,c,cfg) return "\t-- COVERAGE" end
LU[69] = function(i,s,c,cfg) return ("-- CAPTURE type=%d src=%d"):format(getReg(i,"A"), getReg(i,"B")) end
LU[70] = function(i,s,c,cfg) return ("\tStack[%d] = C[%d] - Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[71] = function(i,s,c,cfg) return ("\tStack[%d] = C[%d] / Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[72] = function(i,s,c,cfg) return ("-- FASTCALL1 builtin=%d arg=Stack[%d]"):format(getReg(i,"A"), getReg(i,"B")) end
LU[73] = function(i,s,c,cfg) return ("-- FASTCALL2 builtin=%d args=Stack[%d],Stack[%d]"):format(getReg(i,"A"), getReg(i,"B"), i.AUX or 0) end
LU[74] = function(i,s,c,cfg) return ("-- FASTCALL2K builtin=%d args=Stack[%d],C[%d]"):format(getReg(i,"A"), getReg(i,"B"), i.AUX or 0) end
LU[75] = LU[56]
LU[76] = function(i,s,c,cfg)
    local a,d,aux = getReg(i,"A"), i.D or 0, i.AUX or 0
    local not_ = aux~=0 and "not " or ""
    return ("\tif %s(Stack[%d] == nil) then pointer = pointer + %d end"):format(not_,a,d)
end
LU[77] = function(i,s,c,cfg)
    local a,d,aux = getReg(i,"A"), i.D or 0, i.AUX or 0
    local bv = (aux%2==1) and "true" or "false"
    local not_ = (aux>=2) and "not " or ""
    return ("\tif %s(Stack[%d] == %s) then pointer = pointer + %d end"):format(not_,a,bv,d)
end
LU[78] = function(i,s,c,cfg) return ("\tif Stack[%d] == C[%d] then pointer = pointer + %d end"):format(getReg(i,"A"), i.AUX or 0, i.D or 0) end
LU[79] = LU[78]
LU[80] = function(i,s,c,cfg) return ("\tStack[%d] = math.floor(Stack[%d] / Stack[%d])"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end
LU[81] = function(i,s,c,cfg) return ("\tStack[%d] = math.floor(Stack[%d] / C[%d])"):format(getReg(i,"A"), getReg(i,"B"), getReg(i,"C")) end

-- ---------------------------------------------------------------------------
-- 5. Public API
-- ---------------------------------------------------------------------------

-- Get the custom ID for a real opcode number
local function toCustom(realOp)
    return ActivePerm[realOp]
end

-- Get the real opcode for a custom ID
local function toReal(customID)
    return ActiveInv[customID]
end

-- Get the handler code string for a real opcode
local function handle(realOp, inst, shift, const, cfg)
    local tbl = settings.LuauMode and LU or L51
    local fn = tbl[realOp]
    if fn then return fn(inst, shift, const, cfg) end
    return ("-- unknown opcode %d"):format(realOp)
end

-- Patch Enums so BytecodeParser stores CustomID on each instruction
local function patchEnums()
    local ok, Enums = pcall(require, "Bytecode.Enums")
    if not ok then return end
    for realOp, entry in pairs(Enums) do
        entry.CustomID = ActivePerm[realOp]
    end
end

-- Source snippet for the VM dispatch table (embed in output script)
local function dispatchTableSource()
    local perm = ActivePerm
    local lines = { "local _dispatch = {" }
    for realOp = 0, (settings.LuauMode and LUAU_COUNT-1 or LUA51_COUNT-1) do
        local cid = perm[realOp]
        lines[#lines+1] = ("[%d] = _h%d,"):format(cid, realOp)
    end
    lines[#lines+1] = "}"
    return table.concat(lines, "\n")
end

-- Auto-patch on require
patchEnums()

return {
    toCustom           = toCustom,
    toReal             = toReal,
    handle             = handle,
    patchEnums         = patchEnums,
    dispatchTableSource= dispatchTableSource,

    -- Raw handler tables (real-opcode-keyed)
    Lua51 = L51,
    Luau  = LU,

    -- Shuffle maps
    Lua51Perm = Lua51Perm,
    Lua51Inv  = Lua51Inv,
    LuauPerm  = LuauPerm,
    LuauInv   = LuauInv,
    ActivePerm = ActivePerm,
    ActiveInv  = ActiveInv,
}
