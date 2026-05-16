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

	local AllOpCodes = require("Vm.OpCodes")
	local LUA51_OPS  = AllOpCodes[51]
	local LUAU_OPS   = AllOpCodes[52]

	local cShift = _G.Random(3, 10)
	print("CONSTANT SHIFT AMOUNT:", cShift)

	local function xorSimple(a, b)
		local r, p = 0, 1
		while a > 0 or b > 0 do
			if a % 2 ~= b % 2 then r = r + p end
			a, b, p = math.floor(a/2), math.floor(b/2), p*2
		end
		return r
	end
	local part1 = _G.Random(100, 999)
	local part2 = _G.Random(100, 999)
	local part3 = xorSimple(xorSimple(cShift, part1), part2)

	local function randomName()
		local chars = "abcdefghijklmnopqrstuvwxyz"
		local t = {"_"}
		for i = 1, math.random(6, 12) do
			t[#t+1] = chars:sub(math.random(1,#chars), math.random(1,#chars))
		end
		return table.concat(t)
	end

	local function lIName()
		local pool = {"e","lI","Il","liI","l","l","I","l","l","l","I"}
		local base = pool[math.random(1, #pool)]
		local extra = math.random(1, 1)
		local chars = {}
		for i = 1, extra do
			chars[i] = (math.random(0,1) == 0) and "l" or "I"
		end
		return base .. table.concat(chars)
	end

	local nameDecryptFn  = randomName()
	local nameUnpackFn   = randomName()
	local nameB91Decode  = randomName()
	local nameB91Unpack  = randomName()
	local nameB91Charset = randomName()
	local nameB91Map     = randomName()
	local nameXorBit     = randomName()
	local nameNibbleSwap = randomName()
	local nameVmFn       = randomName()
	local function uniqueLIName(used)
		local n
		repeat n = lIName() until not used[n]
		used[n] = true
		return n
	end
	local _usedNames = {}
	local namePointer    = uniqueLIName(_usedNames)
	local nameStack      = uniqueLIName(_usedNames)
	local nameUpvals     = uniqueLIName(_usedNames)
	local namePrevStack  = uniqueLIName(_usedNames)
	local namePart1      = randomName()
	local namePart2      = randomName()
	local namePart3      = randomName()
	local nameXorFn      = randomName()
	local nameCShift     = randomName()
	local nameMakeSbox   = randomName()
	local nameInvSbox    = randomName()
	local nameDecConst   = randomName()

	_G.__decryptFnName    = nameDecryptFn
	_G.__vmProtectedNames = {namePointer, nameStack, nameUpvals, namePrevStack}

	local prefixes = {"LOL","BRODU","GAY","SHET","WOW","FREAK","BRAT","NOOOOOOOOOO"}
	local chosenPrefix = prefixes[math.random(1, #prefixes)] .. "!"

	decTpl = decTpl
		:gsub("__b91c",              nameB91Charset)
		:gsub("__b91m",              nameB91Map)
		:gsub("__xorBit",            nameXorBit)
		:gsub("__nibbleSwap",        nameNibbleSwap)
		:gsub("__b91Unpack",         nameB91Unpack)
		:gsub("__b91Decode",         nameB91Decode)
		:gsub("__DECRYPT_FN_NAME__", nameDecryptFn)
		:gsub("__UNPACK_FN_NAME__",  nameUnpackFn)
		:gsub("__makeSbox",          nameMakeSbox)
		:gsub("__makeInvSbox",       nameInvSbox)
		:gsub("__decodeConstant",    nameDecConst)

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
		local tbl = settings.LuauMode and LUAU_OPS or LUA51_OPS
		local res = tbl[num]
		if res ~= nil then return res end
		if settings.LuauMode then
			_G.display(("--> LUAU_OP_MISSING: (%s, [%s])"):format(num, name), "yellow")
		else
			_G.display(("--> OP_MISSING: (%s, [%s])"):format(num, name), "red")
		end
		return nil
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

	local BASE91 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_`{|}~"

	local function base91Encode(input, salt)
		if not input or #input == 0 then return "~" end
		local transformed = {}
		for i = 1, #input do
			local b = (string.byte(input, i) + (i % 97) + (salt % 13)) % 256
			b = nibbleSwap(b)
			local prev = (i > 1) and transformed[i-1] or (0x5A + salt % 7)
			transformed[i] = xorBit(b, prev % 256)
		end
		local out = {}
		local b91, n = 0, 0
		for i = 1, #transformed do
			b91 = b91 + transformed[i] * (2 ^ n)
			n = n + 8
			if n > 13 then
				local val = b91 % 8192
				if val > 88 then
					b91 = math.floor(b91 / 8192)
					n = n - 13
				else
					val = b91 % 16384
					b91 = math.floor(b91 / 16384)
					n = n - 14
				end
				out[#out+1] = BASE91:sub((val % 91) + 1, (val % 91) + 1)
				out[#out+1] = BASE91:sub(math.floor(val / 91) + 1, math.floor(val / 91) + 1)
			end
		end
		if n > 0 then
			out[#out+1] = BASE91:sub((b91 % 91) + 1, (b91 % 91) + 1)
			if n > 7 or b91 > 90 then
				out[#out+1] = BASE91:sub(math.floor(b91 / 91) + 1, math.floor(b91 / 91) + 1)
			end
		end
		local result = table.concat(out)
		return (result == "" and "~" or result)
	end

	local function makeSbox(salt)
		local s = {}
		for i = 0, 255 do s[i] = i end
		local r = salt
		for i = 255, 1, -1 do
			r = (r * 1664525 + 1013904223) % 4294967296
			local j = r % (i + 1)
			s[i], s[j] = s[j], s[i]
		end
		return s
	end

	local function encodeConstant(input, salt, idx)
		if not input or #input == 0 then return "~" end
		local sbox = makeSbox(salt)
		local bytes = {}
		local prev = salt % 256
		for i = 1, #input do
			local b   = input:byte(i)
			local key = (salt * 31 + idx * 17 + i * 7) % 256
			b = xorBit(b, key)
			b = sbox[b]
			b = xorBit(b, prev)
			prev = b
			bytes[i] = b
		end
		local out = {}
		local b91, n = 0, 0
		for i = 1, #bytes do
			b91 = b91 + bytes[i] * (2 ^ n)
			n = n + 8
			if n > 13 then
				local val = b91 % 8192
				if val > 88 then
					b91 = math.floor(b91 / 8192); n = n - 13
				else
					val = b91 % 16384
					b91 = math.floor(b91 / 16384); n = n - 14
				end
				out[#out+1] = BASE91:sub((val % 91) + 1, (val % 91) + 1)
				out[#out+1] = BASE91:sub(math.floor(val / 91) + 1, math.floor(val / 91) + 1)
			end
		end
		if n > 0 then
			out[#out+1] = BASE91:sub((b91 % 91) + 1, (b91 % 91) + 1)
			if n > 7 or b91 > 90 then
				out[#out+1] = BASE91:sub(math.floor(b91 / 91) + 1, math.floor(b91 / 91) + 1)
			end
		end
		local result = table.concat(out)
		return (result == "" and "~" or result)
	end

	local function junkBranch()
		local fakePtr = math.random(100000, 999999)
		local junkVar = randomName()
		return ("if "..namePointer.." == %d then local %s = nil end\n"):format(fakePtr, junkVar)
	end

	local SEP = "\1"

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

		local encs, salts, idxs = {}, {}, {}

		for i = 1, #mixed do
			local c    = mixed[i]
			local salt = math.random(100, 9999)
			local idx  = i

			local raw   = type(c) == "table" and tostring(c.Value) or tostring(c)
			local byted = raw

			if c.Type == "number"  then byted = byted .. string.char(11) end
			if c.Type == "boolean" then byted = byted .. string.char(7)  end
			if c.Type == "nil"     then byted = byted .. string.char(6)  end

			local enc = encodeConstant(byted, salt, idx)
			enc = enc or "~"
			table.insert(encs,  enc)
			table.insert(salts, tostring(salt))
			table.insert(idxs,  tostring(idx))
		end

		local total = #encs
		local raw = tostring(total) .. SEP
			.. table.concat(encs,  SEP) .. SEP
			.. table.concat(salts, SEP) .. SEP
			.. table.concat(idxs,  SEP)

		local outerSalt = math.random(1000, 9999)
		local blob = base91Encode(raw, outerSalt)
		return chosenPrefix .. string.format("%04d", outerSalt) .. blob
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
					pc, getReg(all[li],"A") or 0, getReg(all[li],"B")))
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
		local opcodeMap  = {}
		local chunkSize  = 100
		local chunks     = {}
		local currentChunk = {}
		local isFirst    = true
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
			result = result:gsub("prevStack", namePrevStack)
			result = result:gsub("Stack",     nameStack)
			result = result:gsub("Upvalues",  nameUpvals)
			result = result:gsub("pointer",   namePointer)
			return numExpr and numExpr(result) or result
		end

		if settings.ControlFlowFlattening then
			_G.display("--> Generating Control Flow Flattening"..(extra and " ("..extra..")" or ""),"yellow")
			local result = CFF:generateState(opcodeMap)
			result = result:gsub("prevStack", namePrevStack)
			result = result:gsub("Stack",     nameStack)
			result = result:gsub("Upvalues",  nameUpvals)
			result = result:gsub("pointer",   namePointer)
			return numExpr and numExpr(result) or result
		end

		local fnDefs = {}
		local calls  = {}
		for _, chunk in ipairs(chunks) do
			local fnName   = randomName()
			local chunkStr = chunk
			chunkStr = chunkStr:gsub("prevStack", namePrevStack)
			chunkStr = chunkStr:gsub("Stack",     nameStack)
			chunkStr = chunkStr:gsub("Upvalues",  nameUpvals)
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

				local offset     = #consts
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
		:gsub("prevStack", namePrevStack)
		:gsub("Upvalues",  nameUpvals)

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

	tree = tree:gsub(":CONSTANT_SHIFTER:", nameCShift)

	local splitKeyCode = string.format(
		"local function %s(a,b) local r,p=0,1 while a>0 or b>0 do if a%%2~=b%%2 then r=r+p end a,b,p=math.floor(a/2),math.floor(b/2),p*2 end return r end\n"..
		"local %s=%d\n"..
		"local %s=%d\n"..
		"local %s=%d\n"..
		"local %s=%s(%s(%s,%s),%s)\n",
		nameXorFn,
		namePart1, part1,
		namePart2, part2,
		namePart3, part3,
		nameCShift, nameXorFn, nameXorFn, namePart1, namePart2, namePart3
	)

	local blobRaw = getConsts(consts)

	local blobLen  = #blobRaw
	local cut1     = math.random(math.floor(blobLen * 0.2), math.floor(blobLen * 0.4))
	local cut2     = math.random(math.floor(blobLen * 0.5), math.floor(blobLen * 0.7))
	local piece1   = blobRaw:sub(1, cut1)
	local piece2   = blobRaw:sub(cut1+1, cut2)
	local piece3   = blobRaw:sub(cut2+1)

	local namePiece1  = randomName()
	local namePiece2  = randomName()
	local namePiece3  = randomName()
	local nameBlobVar = randomName()

	local blobSetup = string.format(
		"local %s=%q\nlocal %s=%q\nlocal %s=%q\nlocal %s=%s..%s..%s\n",
		namePiece1, piece1,
		namePiece2, piece2,
		namePiece3, piece3,
		nameBlobVar, namePiece1, namePiece2, namePiece3
	)

	return (([[%s
%s
%s
local __env = getfenv and getfenv(1) or _ENV
local function %s(Env, __d, __constFn)
local decrypt = __d
local __constants = __constFn()
%s
end
%s(__env, %s, function() return %s(%s, %s) end)]]):format(
		decTpl,
		splitKeyCode,
		blobSetup,
		nameVmFn,
		tree,
		nameVmFn,
		nameDecryptFn,
		nameUnpackFn,
		nameBlobVar,
		nameCShift))

end
