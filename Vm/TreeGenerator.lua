math.randomseed(os.time())
package.path = package.path .. ";./Vm/?.lua"

return function(parsed)
	parsed = parsed[2]

	local settings  = require("Input.Settings")
	local encStr    = require("Resources.EncryptStrings")
	local encFn     = encStr(nil, true)
	local CFF       = require("Resources.ControlFlowFlattening")
	local junkConsts= require("Resources.Templates.FakeConstants")
	local header    = require("Resources.Templates.Header")
	local vm        = require("Resources.Templates.Vm")
	local decTpl    = require("Resources.Templates.DecryptStringsTemplate")

	local decKey, cShift = tostring(_G.Random(100,400)), tostring(_G.Random(3,10))
	print("CONSTANT SHIFT AMOUNT:", cShift)
	if settings.EncryptStrings then header = encStr(header, decKey) end

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

	local function getOpcode(num, name)
		local ok, res = pcall(require, "Vm.OpCodes."..num)
		if ok then return res end
		_G.display(("--> OP_MISSING: (%s, [%s])"):format(num, name), "red")
	end

	local replace  = function(s,k,w) return s:gsub(":"..k:upper()..":",w) end
	local genJunk  = function() return tostring(junkConsts[math.random(1,#junkConsts)]) end

	local function shuffleConsts(tc)
		local junkCount = math.random(2,6)
		local total = #tc + junkCount
		local pos = {}
		for i=1,total do pos[i]=i end
		for i=total,2,-1 do local j=math.random(1,i); pos[i],pos[j]=pos[j],pos[i] end
		local shuffled, indexMap = {}, {}
		for i=1,#tc do shuffled[pos[i]]=tc[i]; indexMap[i]=pos[i] end
		for i=#tc+1,total do shuffled[pos[i]]=genJunk() end
		return shuffled, indexMap
	end

	_G.constantMaps, _G.currentMapId = {}, "base"

	local function prepareMap(tc, id)
		local s, m = shuffleConsts(tc)
		_G.constantMaps[id or "base"] = { shuffled=s, indexMap=m }
		return s, m
	end

	local function getConsts(tc, id)
		id = id or _G.currentMapId or "base"
		local map = _G.constantMaps[id]
		local shuffled = map and map.shuffled or shuffleConsts(tc)
		local out = ""
		for i=1,#shuffled do
			local c = shuffled[i]
			if not c then
				out = out..'(decrypt("","'..math.random(100,3000)..'")),'
			else
				local raw = type(c)=="table" and tostring(c.Value) or tostring(c)
				local byted = raw:gsub(".", function(b) return string.char(b:byte()-cShift) end)
				if c.Type=="number"  then byted=byted..string.char(11) end
				if c.Type=="boolean" then byted=byted..string.char(7)  end
				if c.Type=="nil"     then byted=byted..string.char(6)  end
				local key = tostring(math.random(100,3000))
				local enc, safe = encFn(byted,key), ""
				for ci=1,#enc do safe=safe..("\\%03d"):format(enc:byte(ci)) end
				out = out..('%s(decrypt("%s","%s"))%s,'):format(
					tonumber(c) and "(" or "", safe, key, tonumber(c) and ")" or "")
			end
		end
		return out
	end

	local function getMappedIdx(orig, id)
		id = id or _G.currentMapId or "base"
		local m = _G.constantMaps[id]
		return m and m.indexMap and m.indexMap[orig+1] or orig+1
	end
	_G.getMappedConstant, _G.shiftAmount = getMappedIdx, shiftAmt

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

		if inst.OpcodeName=="CLOSURE" then
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
			return CFF:generateState(opcodeMap)
		end
		return out
	end

	local function processProtos()
		local cur, nxt = {}, {}
		for i=1,#protos do cur[#cur+1]={proto=protos[i]} end
		while #cur>0 do
			for _, pd in ipairs(cur) do
				local p, ex = pd.proto, pd.extra
				protoAt = protoAt+1
				local name, mapId = "PROTOTYPE"..protoAt.."HERE", "proto_"..protoAt
				_G.display("--> Reading prototype: "..protoAt..(ex or ""),"yellow")
				_G.currentMapId = mapId
				prepareMap(p.Constants, mapId)
				local ni = readInsts(require("Vm.Resources.ModifyInstructions")(p.Instructions, p.Constants, p.Prototypes), nil, "PROTOTYPE "..protoAt)
				local nc = getConsts(p.Constants, mapId)
				for pat, val in pairs({
					["INST_"..name]            = ni,
					["CONSTANTS_"..name]       = nc,
					["NUMBERPARAMS_"..name]    = tostring(p.NumUpvalues),
					["UPVALS_"..name]          = p.NumUpvalues,
					["STACK_LOCATION_"..name]  = ex==nil and "prevStack" or "Upvalues",
				}) do tree = tree:gsub(pat, function() return val end) end
				if p.Prototypes and #p.Prototypes>0 then
					for _, sp in pairs(p.Prototypes) do nxt[#nxt+1]={proto=sp, extra="(SUB)"} end
				end
			end
			cur, nxt = nxt, {}
		end
	end

	_G.currentMapId = "base"
	prepareMap(consts,"base")
	tree = tree..readInsts(insts,consts)
	processProtos()

	header = header:gsub("CONSTANTS_HERE_BASEVM", getConsts(consts,"base"))
	tree = vm:format(header, settings.LuaU_Syntax and ":any" or "", tree,
		settings.LuaU_Syntax and "pointer+=1" or "pointer = pointer + 1")
	tree = tree:gsub(":CONSTANT_SHIFTER:", tostring(cShift))

	return ([[return (("%s") and (function() return(function(Env,Constants,shiftKey,decrypt)%s %s end)((_ENV or getfenv()),{},0%s) end)())]]):format(
		settings.Watermark, settings.LuaU_Syntax and ":any" or "", tree, ","..decTpl)
end
