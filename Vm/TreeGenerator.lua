math.randomseed(os.time())
package.path = package.path .. ";./Vm/?.lua"

return function(parsed)
    parsed = parsed[2]

    local settings     = require("Input.Settings")
    local encStr       = require("Resources.EncryptStrings")
    local encFn        = encStr(nil, true)
    local CFF          = require("Resources.ControlFlowFlattening")
    local header       = require("Resources.Templates.Header")
    local vm           = require("Resources.Templates.Vm")
    local decTpl       = require("Resources.Templates.DecryptStringsTemplate")
    local memeStr      = require("Resources.MemeStrings")
    local numExpr      = settings.NumberToExpressions and require("Resources.NumberExpressions") or nil
    local blockShuffle = settings.BlockShuffle and require("Resources.BlockShuffle") or nil

    local decKey, cShift = tostring(_G.Random(100,400)), tostring(_G.Random(3,10))
    print("CONSTANT SHIFT AMOUNT:", cShift)

    local function randomName()
        local chars = "abcdefghijklmnopqrstuvwxyz"
        local t = {"_"}
        for i = 1, math.random(6, 12) do
            t[#t+1] = chars:sub(math.random(1,#chars), math.random(1,#chars))
        end
        return table.concat(t)
    end

    local nameDecryptFn  = randomName()
    local nameUnpackFn   = randomName()
    local nameB10Decode  = randomName()
    local nameXorBit     = randomName()
    local nameNibbleSwap = randomName()
    local nameVmFn       = randomName()
    local namePointer    = randomName()
    local nameStack      = randomName()
    local nameUpvals     = randomName()
    local namePrevStack  = randomName()
    _G.__decryptFnName   = nameDecryptFn

    local prefixes = {"LOL","BRODU","GAY","SHET","WOW","FREAK","BRAT","NOOOOOOOOOO"}
    local chosenPrefix = prefixes[math.random(1, #prefixes)] .. "!"

    decTpl = decTpl
        :gsub("__xorBit",            nameXorBit)
        :gsub("__nibbleSwap",        nameNibbleSwap)
        :gsub("__b10Decode",         nameB10Decode)
        :gsub("__DECRYPT_FN_NAME__", nameDecryptFn)
        :gsub("__UNPACK_FN_NAME__",  nameUnpackFn)

    local protoAt, tree, protosCount, scannedProtos = 0, "", 0, {}
    local shiftAmt = settings.ConstantProtection and _G.Random(10,20) or 0

    local function getReg(loc, name, full)
        name = name:upper()
        if full then return loc[name] end
        local t = loc[name] or loc[name.."x"] or loc["s"..name.."x"]
        return type(t) == "table" and t.i or t
    end
    _G.getReg = getReg

    local function dump(t, indent)
        indent = indent or 0
        local r = "{\n"
        for k, v in pairs(t) do
            local ki = string.rep(" ", indent+2)
            local fv = type(v)=="string" and ("%q"):format(v)
                or type(v)=="table" and dump(v,indent+1)
                or tostring(v)
            r = r..ki.."["..(type(k)=="string" and ("%q"):format(k) or tostring(k)).."] = "..fv..",\n"
        end
        return r..string.rep(" ",indent).."}"
    end

    local consts, protos = parsed.Constants, parsed.Prototypes
    local insts; insts, consts = require("Vm.Resources.ModifyInstructions")(parsed.Instructions, consts, protos)

    for _, label in ipairs({"CONSTANTS","INSTRUCTIONS","PROTOTYPES"}) do
        _G.display("---------------- "..label.." ---------------","yellow")
        _G.display(dump(label=="CONSTANTS" and consts or label=="INSTRUCTIONS" and insts or protos))
    end

    local function getOpcode(num, name)
        if settings.LuauMode then
            local ok, res = pcall(require, "Vm.OpCodes.Luau."..num)
            if ok then return res end
            _G.display(("--> LUAU_OP_MISSING: (%s, [%s])"):format(num, name), "yellow")
            return nil
        else
            local ok, res = pcall(require, "Vm.OpCodes."..num)
            if ok then return res end
            _G.display(("--> OP_MISSING: (%s, [%s])"):format(num, name), "red")
            return nil
        end
    end

    local replace = function(s,k,w) return s:gsub(":"..k:upper()..":",w) end

    local protoOffsets = {}

    local function getMappedIdx(orig, id)
        id = id or _G.currentMapId or "base"
        local offset = protoOffsets[id] or 0
        return orig + offset + 1
    end
    _G.getMappedConstant, _G.shiftAmount = getMappedIdx, shiftAmt

    local function randomJunkString()
        local len = math.random(4, 16)
        local chars = {}
        for i = 1, len do chars[i] = string.char(math.random(65, 122)) end
        return table.concat(chars)
    end

    local function randomJunkNumber()
        return tostring(math.random(1000, 999999))
    end

    local function nibbleSwap(b)
        return ((b % 16) * 16 + math.floor(b / 16)) % 256
    end

    local function xorBit(a, b)
        if bit32 then return bit32.bxor(a, b) end
        if bit then return bit.bxor(a, b) end
        local r, p = 0, 1
        while a > 0 or b > 0 do
            if a % 2 ~= b % 2 then r = r + p end
            a, b, p = math.floor(a/2), math.floor(b/2), p*2
        end
        return r
    end

    local function base10Encode(input, salt)
        if not input or #input == 0 then return "~" end
        local src = {}
        for i = 1, #input do src[i] = string.byte(input, i) end
        local transformed = {}
        for i = 1, #src do
            local b = (src[i] + (i % 97) + (salt % 13)) % 256
            b = nibbleSwap(b)
            local prev = (i > 1) and transformed[i-1] or (0x5A + salt % 7)
            transformed[i] = xorBit(b, prev % 256)
        end
        local out = {}
        for i = 1, #transformed do out[i] = string.format("%03d", transformed[i]) end
        local result = table.concat(out)
        return (result == "" and "~" or result)
    end

    local function junkBranch()
        local fakePtr = math.random(100000, 999999)
        local junkVar = randomName()
        return ("if "..namePointer.." == %d then local %s = nil end\n"):format(fakePtr, junkVar)
    end

    local function getConsts(tc)
        local mixed = {}
        for i = 1, #tc do table.insert(mixed, tc[i]) end

        local extraJunk = math.random(2, 5)
        for i = 1, extraJunk do
            local junkType = math.random(1, 2)
            local junk
            if junkType == 1 then
                junk = { Type = "string", Value = randomJunkString() }
            else
                junk = { Type = "number", Value = randomJunkNumber() }
            end
            table.insert(mixed, junk)
        end

        local encs, salts, shifts = {}, {}, {}

        for i = 1, #mixed do
            local c = mixed[i]
            local perShift = (tonumber(cShift) + i * 3) % 20 + 1
            table.insert(shifts, tostring(perShift))

            local raw = type(c) == "table" and tostring(c.Value) or tostring(c)
            local byted = raw:gsub(".", function(b)
                local v = b:byte() - perShift
                if v < 0 then v = v + 256 end
                return string.char(v)
            end)

            if c.Type == "number"  then byted = byted .. string.char(11) end
            if c.Type == "boolean" then byted = byted .. string.char(7)  end
            if c.Type == "nil"     then byted = byted .. string.char(6)  end

            local salt = math.random(100, 9999)
            local enc = encFn(byted, salt)
            enc = enc or "~"
            table.insert(encs,  enc)
            table.insert(salts, tostring(salt))
        end

        local total = #encs
        local raw = tostring(total) .. "\n"
            .. table.concat(encs,   "\n") .. "\n"
            .. table.concat(salts,  "\n") .. "\n"
            .. table.concat(shifts, "\n")

        local blob = base10Encode(raw, 0)
        return '"' .. chosenPrefix .. blob .. '"'
    end

    local function genOpcode(inst, idx, all)
        if inst.OpcodeName=="PSEUDO" or inst.Opcode==-1 then
            return "-- [PSEUDO] Handled by CLOSURE"
        end
        local fmt = getOpcode(inst.Opcode, inst.OpcodeName)
        if type(fmt)=="function" then
            local c
            if inst.Opcode==1 then
                local B, got = getReg(inst,"B"), nil
                got = consts[B+1]
                if B and got and got.Type=="number" then c=got end
            end
            fmt = fmt(inst, shiftAmt, c, settings)
        end
        if fmt==nil then return "-- ERROR GENERATING OPCODE" end

        local r = replace(replace(replace(fmt,
            "a", tostring(getReg(inst,"A"))),
            "c", tostring(getReg(inst,"C"))),
            "b", tostring(getReg(inst,"B")))

        if inst.OpcodeName=="CLOSURE" or inst.OpcodeName=="NEWCLOSURE" or inst.OpcodeName=="DUPCLOSURE" then
            local parts, li, pc = {}, (idx or 0)+1, 0
            while all and all[li] and (all[li].OpcodeName=="PSEUDO" or all[li].Opcode==-1) do
                table.insert(parts,("[%s] = {%s, %s}"):format(
                    pc, getReg(all[li],"C") or 0, getReg(all[li],"B")))
                pc=pc+1; li=li+1
            end
            r = replace(r,"MAPPING","{"..table.concat(parts,", ").."}")
            if not table.find(scannedProtos,inst) then
                table.insert(scannedProtos,inst)
                protosCount=protosCount+1
                r = replace(r,"PROTOHERE",tostring(protosCount))
            end
        end
        return r
    end

    local function readInsts(curInsts, _, extra)
        local opcodeMap = {}
        local chunkSize = 100
        local chunks = {}
        local currentChunk = {}
        local isFirst = true
        local branchCount = 0

        for i, inst in ipairs(curInsts) do
            if inst.OpcodeName~="PSEUDO" and inst.Opcode~=-1 then
                local gen = genOpcode(inst, i, curInsts)

                if math.random(1, 50) == 1 then
                    local meme = memeStr()
                    if settings.ControlFlowFlattening or settings.BlockShuffle then
                        gen = meme .. "\n" .. gen
                    else
                        table.insert(currentChunk, meme .. "\n")
                    end
                end

                if not (settings.ControlFlowFlattening or settings.BlockShuffle) then
                    if math.random(1, 4) == 1 then
                        table.insert(currentChunk, junkBranch())
                    end
                end

                if settings.BlockShuffle then
                    opcodeMap[i] = gen
                elseif settings.ControlFlowFlattening then
                    opcodeMap[i] = gen
                else
                    local branch = ("%s %s == %s then -- %s [%s]\n%s\n"):format(
                        isFirst and "if" or "elseif",
                        namePointer,
                        i,
                        inst.Opcode, inst.OpcodeName or "unknown",
                        gen)
                    table.insert(currentChunk, branch)
                    isFirst = false
                    branchCount = branchCount + 1

                    if branchCount >= chunkSize then
                        table.insert(currentChunk, "end\n")
                        table.insert(chunks, table.concat(currentChunk))
                        currentChunk = {}
                        isFirst = true
                        branchCount = 0
                    end
                end
            end
        end

        if not (settings.BlockShuffle or settings.ControlFlowFlattening) then
            if #currentChunk > 0 then
                table.insert(currentChunk, "end\n")
                table.insert(chunks, table.concat(currentChunk))
            end
        end

        if settings.BlockShuffle then
            _G.display("--> Generating Block Shuffle"..(extra and " ("..extra..")" or ""),"yellow")
            local result = blockShuffle(opcodeMap, settings.NumberToExpressions)
            result = result:gsub("pointer",   namePointer)
            result = result:gsub("Stack",     nameStack)
            result = result:gsub("Upvalues",  nameUpvals)
            result = result:gsub("prevStack", namePrevStack)
            return numExpr and numExpr(result) or result
        end

        if settings.ControlFlowFlattening then
            _G.display("--> Generating Control Flow Flattening"..(extra and " ("..extra..")" or ""),"yellow")
            local result = CFF:generateState(opcodeMap)
            result = result:gsub("pointer",   namePointer)
            result = result:gsub("Stack",     nameStack)
            result = result:gsub("Upvalues",  nameUpvals)
            result = result:gsub("prevStack", namePrevStack)
            return numExpr and numExpr(result) or result
        end

        local fnDefs = {}
        local calls = {}
        for _, chunk in ipairs(chunks) do
            local fnName = randomName()
            local chunkStr = chunk
            chunkStr = chunkStr:gsub("Stack",    nameStack)
            chunkStr = chunkStr:gsub("Upvalues", nameUpvals)
            chunkStr = chunkStr:gsub("prevStack",namePrevStack)
            table.insert(fnDefs, ("local function %s()\n%s\nend"):format(fnName, chunkStr))
            table.insert(calls, fnName .. "()")
        end

        local result = table.concat(fnDefs, "\n") .. "\n" .. table.concat(calls, "\n")
        return numExpr and numExpr(result) or result
    end

    local function processProtos()
        local cur, nxt = {}, {}
        for i=1,#protos do cur[#cur+1]={proto=protos[i]} end
        while #cur>0 do
            for _, pd in ipairs(cur) do
                local p, ex = pd.proto, pd.extra
                protoAt = protoAt+1
                local name = "PROTOTYPE"..protoAt.."HERE"
                _G.display("--> Reading prototype: "..protoAt..(ex or ""),"yellow")

                local offset = #consts
                local protoMapId = "proto_"..protoAt
                protoOffsets[protoMapId] = offset
                for _, c in ipairs(p.Constants) do table.insert(consts, c) end

                _G.currentMapId = protoMapId

                local ni = readInsts(
                    require("Vm.Resources.ModifyInstructions")(p.Instructions, p.Constants, p.Prototypes),
                    nil, "PROTOTYPE "..protoAt)

                for pat, val in pairs({
                    ["INST_"..name]           = ni,
                    ["CONSTANTS_"..name]      = "",
                    ["NUMBERPARAMS_"..name]   = tostring(p.NumUpvalues),
                    ["UPVALS_"..name]         = p.NumUpvalues,
                    ["STACK_LOCATION_"..name] = ex==nil and namePrevStack or nameUpvals,
                }) do tree = tree:gsub(pat, function() return val end) end

                if p.Prototypes and #p.Prototypes>0 then
                    for _, sp in pairs(p.Prototypes) do
                        nxt[#nxt+1]={proto=sp, extra="(SUB)"}
                    end
                end
            end
            cur, nxt = nxt, {}
        end
    end

    _G.currentMapId = "base"
    protoOffsets["base"] = 0
    tree = tree..readInsts(insts, consts)
    processProtos()

    header = header:gsub("CONSTANTS_HERE_BASEVM", "")
    header = header
        :gsub("Upvalues",  nameUpvals)
        :gsub("prevStack", namePrevStack)

    local vmTemplate = [[
%s
local %s = 1
local %s = {}
local %s = {}
local %s = %s
while true do
%s
%s = %s + 1
end
]]
    tree = vmTemplate:format(
        header,
        namePointer,
        nameStack,
        nameUpvals,
        namePrevStack, nameStack,
        tree,
        namePointer, namePointer)

    tree = tree:gsub(":CONSTANT_SHIFTER:", tostring(cShift))


return ([[%s
local __cShift = %s
local __env = getfenv and getfenv(1) or _ENV
local function %s(Env, __d, __constFn)
local decrypt = __d
local __constants = __constFn()
%s
end
%s(__env, %s, function() return %s(%s, __cShift) end)]]):format(
        decTpl,
        cShift,
        nameVmFn,
        tree,
        nameVmFn,
        nameDecryptFn,
        nameUnpackFn,
        getConsts(consts))

    
end
