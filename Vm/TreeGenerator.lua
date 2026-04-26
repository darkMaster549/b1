-- i rebuilt this again --
-- i won't encrpt the header for now --
-- This Can now Obfuscte like Lauu Big Scripts --
math.randomseed(os.time())
package.path = package.path .. ";./Vm/?.lua"

return function(parsed)
	parsed = parsed[2]

	local settings   = require("Input.Settings")
	local encStr     = require("Resources.EncryptStrings")
	local encFn      = encStr(nil, true)
	local CFF        = require("Resources.ControlFlowFlattening")
	local header     = require("Resources.Templates.Header")
	local vm         = require("Resources.Templates.Vm")
	local decTpl     = require("Resources.Templates.DecryptStringsTemplate")
	local memeStr    = require("Resources.MemeStrings")
	local numExpr    = settings.NumberToExpressions and require("Resources.NumberExpressions") or nil

	local decKey, cShift = tostring(_G.Random(100,400)), tostring(_G.Random(3,10))
	print("CONSTANT SHIFT AMOUNT:", cShift)

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
			local fv = type(v)=="string" and ("%q"):format(v) or type(v)=="table" and dump(v,indent+1) or tostring(v)
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

	-- UPDATED: routes to Luau opcode folder when --luau flag is active
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
		for i = 1, len do
			chars[i] = string.char(math.random(65, 122))
		end
		return table.concat(chars)
	end

	local function randomJunkNumber()
		return tostring(math.random(1000, 999999))
	end

	local function getConsts(tc)
		local mixed = {}

		-- real constants first, order must not change
		for i = 1, #tc do
			table.insert(mixed, tc[i])
		end

		-- junk constants only at the end
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

		local encs     = {}
		local rawHexes = {}
		local salts    = {}
		local shifts   = {}

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
			local enc, rawHex = encFn(byted, salt)
			table.insert(encs,     enc)
			table.insert(rawHexes, rawHex)
			table.insert(salts,    tostring(salt))
		end

		return '"HEBREW!'
			.. table.concat(encs, "R")
			.. "R" .. table.concat(rawHexes, "R")
			.. "R" .. table.concat(salts, "R")
			.. "R" .. table.concat(shifts, "R")
			.. '"'
	end

	local function genOpcode(inst, idx, all)
		if inst.OpcodeName=="PSEUDO" or inst.Opcode==-1 then return "-- [PSEUDO] Handled by CLOSURE" end
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

		local r = replace(replace(replace(fmt,"a",tostring(getReg(inst,"A"))),"c",tostring(getReg(inst,"C"))),"b",tostring(getReg(inst,"B")))

		-- handle CLOSURE and NEWCLOSURE (Luau) proto scanning
		if inst.OpcodeName=="CLOSURE" or inst.OpcodeName=="NEWCLOSURE" or inst.OpcodeName=="DUPCLOSURE" then
			local parts, li, pc = {}, (idx or 0)+1, 0
			while all and all[li] and (all[li].OpcodeName=="PSEUDO" or all[li].Opcode==-1) do
				table.insert(parts,("[%s] = {%s, %s}"):format(pc, getReg(all[li],"C") or 0, getReg(all[li],"B")))
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
		local opcodeMap, out, isFirst = {}, "", true

		for i, inst in ipairs(curInsts) do
			if inst.OpcodeName~="PSEUDO" and inst.Opcode~=-1 then
				local gen = genOpcode(inst, i, curInsts)

				if math.random(1, 8) == 1 then
					local meme = memeStr()
					if settings.ControlFlowFlattening then
						gen = meme .. "\n" .. gen
					else
						out = out .. meme .. "\n"
					end
				end

				if settings.ControlFlowFlattening then
					opcodeMap[i] = gen
				else
					out = out..("%s pointer == %s then -- %s [%s]\n%s\n%s"):format(
						isFirst and "if" or "elseif", i,
						inst.Opcode, inst.OpcodeName or "unknown",
						gen, i==#curInsts and "end" or "")
				end
				isFirst = false
			end
		end

		if settings.ControlFlowFlattening then
			_G.display("--> Generating Control Flow Flattening"..(extra and " ("..extra..")" or ""),"yellow")
			local result = CFF:generateState(opcodeMap)
			return numExpr and numExpr(result) or result
		end
		return numExpr and numExpr(out) or out
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
				for _, c in ipairs(p.Constants) do
					table.insert(consts, c)
				end

				_G.currentMapId = protoMapId

				local ni = readInsts(require("Vm.Resources.ModifyInstructions")(p.Instructions, p.Constants, p.Prototypes), nil, "PROTOTYPE "..protoAt)

				for pat, val in pairs({
					["INST_"..name]           = ni,
					["CONSTANTS_"..name]      = "",
					["NUMBERPARAMS_"..name]   = tostring(p.NumUpvalues),
					["UPVALS_"..name]         = p.NumUpvalues,
					["STACK_LOCATION_"..name] = ex==nil and "prevStack" or "Upvalues",
				}) do tree = tree:gsub(pat, function() return val end) end

				if p.Prototypes and #p.Prototypes>0 then
					for _, sp in pairs(p.Prototypes) do nxt[#nxt+1]={proto=sp, extra="(SUB)"} end
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
	tree = vm:format(header, settings.LuaU_Syntax and ":any" or "", tree,
		settings.LuaU_Syntax and "pointer+=1" or "pointer = pointer + 1")
	tree = tree:gsub(":CONSTANT_SHIFTER:", tostring(cShift))

	return ([[%s
local __cShift = %s
local function __vm(Env, __d, __constFn)
local decrypt = __d
local __constants = __constFn()
%s
end
__vm((_ENV or getfenv()), __decrypt_fn, function() return __unpack_consts(%s, __cShift) end)]]):format(decTpl, cShift, tree, getConsts(consts))
end
