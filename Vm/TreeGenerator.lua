math.randomseed(os.time())
package.path = package.path .. ";" .. "./Vm/?.lua"

return function(parsed)
	parsed = parsed[2]

	local header     = require("Resources.Templates.Header")
	local vm         = require("Resources.Templates.Vm")
	local settings   = require("Input.Settings")
	local encStr     = require("Resources.EncryptStrings")
	local encFn      = require("Resources.EncryptStrings")(nil, true)
	local decTpl     = require("Resources.Templates.DecryptStringsTemplate")
	local CFF        = require("Resources.ControlFlowFlattening")
	local junkConsts = require("Resources.Templates.FakeConstants")

	local decKey     = tostring(_G.Random(100, 400))
	local cShift     = tostring(_G.Random(3, 10))

	print("CONSTANT SHIFT AMOUNT:", cShift)

	if settings.EncryptStrings then header = encStr(header, decKey) end

	local protoAt, tree, protosCount, scannedProtos = 0, "", 0, {}
	local shiftAmt = settings.ConstantProtection and _G.Random(10, 20) or 0

	local function getReg(loc, name, full)
		name = name:upper()
		if full then return loc[name] end
		local t = loc[name] or loc[name.."x"] or loc["s"..name.."x"]
		return type(t) == "table" and t.i or t
	end

	local function dump(t, indent)
		indent = indent or 0
		local function val(v, lvl)
			lvl = lvl or 0
			if type(v) == "string" then return ("%q"):format(v)
			elseif type(v) == "table" then return dump(v, lvl + 1)
			else return tostring(v) end
		end
		local r = "{\n"
		for k, v in pairs(t) do
			local ki = string.rep(" ", indent + 2)
			r = r .. ki .. "[" .. (type(k)=="string" and ("%q"):format(k) or tostring(k)) .. "] = " .. val(v, indent + 2) .. ",\n"
		end
		return r .. string.rep(" ", indent) .. "}"
	end

	_G.getReg = getReg

	local consts, protos = parsed.Constants, parsed.Prototypes
	local insts; insts, consts = require("Vm.Resources.ModifyInstructions")(parsed.Instructions, consts, protos)

	_G.display("---------------- CONSTANTS ---------------", "yellow") _G.display(dump(consts))
	_G.display("---------------- INSTRUCTIONS ---------------", "yellow") _G.display(dump(insts))
	_G.display("---------------- PROTOTYPES ---------------", "yellow") _G.display(dump(protos))

	local function getOpcode(num, name)
		local ok, res = pcall(require, "Vm.OpCodes." .. tostring(num))
		if ok then return res end
		_G.display(("--> OP_MISSING: (%s, [%s])"):format(num, name), "red")
	end

	local function replace(s, k, w) return s:gsub(":"..k:upper()..":", w) end

	local function genJunk() return tostring(junkConsts[math.random(1, #junkConsts)]) end

	local function shuffleConsts(tc)
		local shuffled, indexMap = {}, {}
		local junkCount = math.random(2, 6)
		local total = #tc + junkCount
		local pos = {}
		for i = 1, total do pos[i] = i end
		for i = total, 2, -1 do
			local j = math.random(1, i)
			pos[i], pos[j] = pos[j], pos[i]
		end
		for i = 1, #tc do
			shuffled[pos[i]] = tc[i]
			indexMap[i] = pos[i]
		end
		for i = #tc + 1, total do
			shuffled[pos[i]] = genJunk()
		end
		return shuffled, indexMap
	end

	_G.constantMaps, _G.currentMapId = {}, "base"

	local function prepareMap(tc, id)
		local s, m = shuffleConsts(tc)
		_G.constantMaps[id or "base"] = { shuffled = s, indexMap = m }
		return s, m
	end

	local function getConsts(tc, id)
		id = id or _G.currentMapId or "base"
		local map = _G.constantMaps[id]
		local shuffled = map and map.shuffled or shuffleConsts(tc)
		local out = ""
		for i = 1, #shuffled do
			local c = shuffled[i]
			if not c then
				out = out .. '(decrypt("", "' .. tostring(math.random(100, 3000)) .. '")),'
			else
				local raw = type(c) == "table" and tostring(c.Value) or tostring(c)
				local byted = raw:gsub(".", function(b) return string.char(b:byte() - cShift) end)
				if c.Type == "number"  then byted = byted .. string.char(11) end
				if c.Type == "boolean" then byted = byted .. string.char(7)  end
				if c.Type == "nil"     then byted = byted .. string.char(6)  end
				local key = tostring(math.random(100, 3000))
				local enc = encFn(byted, key)
				local safe = ""
				for ci = 1, #enc do safe = safe .. ("\\%03d"):format(enc:byte(ci)) end
				out = out .. ('%s(decrypt("%s", "%s"))%s,'):format(
					tonumber(c) and "(" or "", safe, key, tonumber(c) and ")" or "")
			end
		end
		return out
	end

	local function getMappedIdx(orig, id)
		id = id or _G.currentMapId or "base"
		local m = _G.constantMaps[id]
		if m and m.indexMap and m.indexMap[orig + 1] then return m.indexMap[orig + 1] end
		return orig + 1
	end

	_G.getMappedConstant = getMappedIdx
	_G.shiftAmount = shiftAmt

	local function genOpcode(inst, idx, all)
		if inst.OpcodeName == "PSEUDO" or inst.Opcode == -1 then
			return "-- [PSEUDO] Handled by CLOSURE"
		end
		local fmt = getOpcode(inst.Opcode, inst.OpcodeName)
		if type(fmt) == "function" then
			local c = nil
			if inst.Opcode == 1 then
				local B = getReg(inst, "B")
				local got = consts[B + 1]
				if B and got and got.Type == "number" then c = got end
			end
			fmt = fmt(inst, shiftAmt, c, settings)
		end
		if fmt == nil then return "-- ERROR GENERATING OPCODE" end

		local r = replace(fmt, "a", tostring(getReg(inst, "A")))
		r = replace(r, "c", tostring(getReg(inst, "C")))
		r = replace(r, "b", tostring(getReg(inst, "B")))

		if inst.OpcodeName == "CLOSURE" then
			local parts = {}
			if all and idx then
				local li, pc = idx + 1, 0
				while true do
					local n = all[li]
					if not n or (n.OpcodeName ~= "PSEUDO" and n.Opcode ~= -1) then break end
					table.insert(parts, ("[%s] = {%s, %s}"):format(pc, getReg(n,"C") or 0, getReg(n,"B")))
					pc = pc + 1; li = li + 1
				end
			end
			r = replace(r, "MAPPING", "{" .. table.concat(parts, ", ") .. "}")
			if not table.find(scannedProtos, inst) then
				table.insert(scannedProtos, inst)
				protosCount = protosCount + 1
				r = replace(r, "PROTOHERE", tostring(protosCount))
			end
		end
		return r
	end

	local function readInsts(curInsts, _, extra)
		local opcodeMap, out, isFirst = {}, "", true
		local function add(s) out = out .. s end

		for i, inst in ipairs(curInsts) do
			if inst.OpcodeName ~= "PSEUDO" and inst.Opcode ~= -1 then
				local gen = genOpcode(inst, i, curInsts)
				if settings.ControlFlowFlattening then
					opcodeMap[i] = gen
				else
					add(("%s pointer == %s then -- %s [%s]\n%s\n%s"):format(
						isFirst and "if" or "elseif", i,
						inst.Opcode, inst.OpcodeName or "unknown",
						gen, i == #curInsts and "end" or ""))
				end
				isFirst = false
			end
		end

		if settings.ControlFlowFlattening then
			_G.display("--> Generating Control Flow Flattening" .. (extra and " ("..extra..")" or ""), "yellow")
			return CFF:generateState(opcodeMap)
		end
		return out
	end

	local function processProtos()
		local cur, nxt = {}, {}
		for i = 1, #protos do cur[#cur+1] = { proto = protos[i] } end

		while #cur > 0 do
			for _, pd in ipairs(cur) do
				local p, ex = pd.proto, pd.extra
				protoAt = protoAt + 1
				local name  = "PROTOTYPE" .. protoAt .. "HERE"
				local mapId = "proto_" .. protoAt

				_G.display("--> Reading prototype: " .. protoAt .. (ex or ""), "yellow")
				_G.currentMapId = mapId
				prepareMap(p.Constants, mapId)

				local ni = readInsts(require("Vm.Resources.ModifyInstructions")(p.Instructions, p.Constants, p.Prototypes), nil, "PROTOTYPE "..protoAt)
				local nc = getConsts(p.Constants, mapId)

				tree = tree:gsub("INST_"..name,       function() return ni end)
				tree = tree:gsub("CONSTANTS_"..name,  function() return nc end)
				tree = tree:gsub("NUMBERPARAMS_"..name, tostring(p.NumUpvalues))
				tree = tree:gsub("UPVALS_"..name,     p.NumUpvalues)
				tree = tree:gsub("STACK_LOCATION_"..name, ex == nil and "prevStack" or "Upvalues")

				if p.Prototypes and #p.Prototypes > 0 then
					for _, sp in pairs(p.Prototypes) do
						nxt[#nxt+1] = { proto = sp, extra = "(SUB)" }
					end
				end
			end
			cur, nxt = nxt, {}
		end
	end

	_G.currentMapId = "base"
	prepareMap(consts, "base")

	tree = tree .. readInsts(insts, consts)
	processProtos()

	header = header:gsub("CONSTANTS_HERE_BASEVM", getConsts(consts, "base"))
	tree = vm:format(
		header,
		settings.LuaU_Syntax and ":any" or "",
		tree,
		settings.LuaU_Syntax and "pointer+=1" or "pointer = pointer + 1"
	)
	tree = tree:gsub(":CONSTANT_SHIFTER:", tostring(cShift))

	tree = ([[return (("%s") and (function() return(function(Env,Constants,shiftKey,decrypt)%s %s end)((_ENV or getfenv()),{},0%s) end)())]]):format(
		settings.Watermark,
		settings.LuaU_Syntax and ":any" or "",
		tree,
		"," .. decTpl
	)

	return tree
end
