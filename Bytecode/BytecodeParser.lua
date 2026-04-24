local Enums = require("Bytecode.Enums")
local parser = require("Bytecode.BcUtils")
local settings = require("Input.Settings")

-- ============================================================
-- LUA 5.1 PARSER
-- ============================================================

local function decodeRK(x)
	if x >= 256 then
		return { k = true, i = x - 256 }
	end
	return { k = false, i = x }
end

local function decodeInstruction51(raw)
	local opcode = raw % 64
	local a = math.floor(raw / 64) % 256
	print("PARSER OPCODE --> ", opcode)
	local enum = Enums[opcode]
	if not enum then
		error("Unknown opcode: " .. tostring(opcode))
	end
	local mode = enum.Type
	local instruction = {
		Opcode = opcode,
		OpcodeName = enum.Mnemonic,
		A = a,
		Raw = raw
	}

	if mode == 'iABC' then
		instruction.B = decodeRK(math.floor(raw / 8388608) % 512)
		instruction.C = decodeRK(math.floor(raw / 16384) % 512)
	elseif mode == 'iABx' then
		instruction.Bx = math.floor(raw / 16384)
	elseif mode == 'iAsBx' then
		instruction.sBx = math.floor(raw / 16384) - 131071
	end

	return instruction
end

local function readHeader51()
	local header = {
		signature      = parser:ReadBytes(4),
		version        = parser:ReadByte(),
		format         = parser:ReadByte(),
		endianness     = parser:ReadByte(),
		intSize        = parser:ReadByte(),
		sizeTSize      = parser:ReadByte(),
		instructionSize= parser:ReadByte(),
		luaNumberSize  = parser:ReadByte(),
		integral       = parser:ReadByte(),
	}

	if header.signature ~= "\27Lua" then
		error("Invalid Lua signature")
	end
	if header.version ~= 0x51 then
		error("Unsupported Lua version (expected 5.1)")
	end
	if header.format ~= 0 then
		error("Unsupported format (expected official format 0)")
	end
	parser.sizeT = header.sizeTSize
	if header.endianness ~= 1 then
		error("Unsupported endianness (expected little-endian)")
	end
	if header.intSize ~= 4 or header.instructionSize ~= 4 then
		error("Unsupported int/instruction size (expected 4 bytes)")
	end

	return header
end

local function readFunction51(sourcename)
	local func = {
		Source = nil,
		LineDefined = 0,
		LastLineDefined = 0,
		NumUpvalues = 0,
		NumParams = 0,
		IsVararg = 0,
		MaxStackSize = 0,
		Instructions = {},
		Constants = {},
		Prototypes = {}
	}

	func.Source         = parser:ReadString() or sourcename
	func.LineDefined    = parser:ReadInt32()
	func.LastLineDefined= parser:ReadInt32()
	func.NumUpvalues    = parser:ReadByte()
	func.NumParams      = parser:ReadByte()
	func.IsVararg       = parser:ReadByte()
	func.MaxStackSize   = parser:ReadByte()

	local numInstr = parser:ReadInt32()
	for i = 1, numInstr do
		local raw = parser:ReadInt32()
		func.Instructions[i] = decodeInstruction51(raw)
		func.Instructions[i].Index = i
	end

	local numConsts = parser:ReadInt32()
	for i = 1, numConsts do
		local constant = {Index = i - 1}
		local constType = parser:ReadByte()

		if constType == 0 then
			constant.Type = 'nil'
			constant.Value = 'nil'
		elseif constType == 1 then
			constant.Type = 'boolean'
			constant.Value = parser:ReadByte() ~= 0
		elseif constType == 3 then
			constant.Type = 'number'
			constant.Value = parser:ReadDouble()
		elseif constType == 4 then
			constant.Type = 'string'
			constant.Value = parser:ReadString()
		end
		func.Constants[i] = constant
	end

	local numPrototypes = parser:ReadInt32()
	for i = 1, numPrototypes do
		func.Prototypes[i] = readFunction51(func.Source)
		func.Prototypes[i].Index = i - 1
	end

	local numLineInfo = parser:ReadInt32()
	for i = 1, numLineInfo do
		parser:ReadInt32()
	end

	local numLocals = parser:ReadInt32()
	for i = 1, numLocals do
		parser:ReadString()
		parser:ReadInt32()
		parser:ReadInt32()
	end

	local numUpvalueNames = parser:ReadInt32()
	for i = 1, numUpvalueNames do
		parser:ReadString()
	end

	return func
end

-- ============================================================
-- LUAU PARSER
-- Luau bytecode format (versions 3-6)
-- Header: 1 byte version, then functions encoded with varints
-- ============================================================

local function readVarInt(p)
	local result, shift = 0, 0
	repeat
		local byte = p:ReadByte()
		result = result + ((byte % 128) * (2 ^ shift))
		shift = shift + 7
		if byte < 128 then break end
	until false
	return result
end

local function decodeInstructionLuau(raw)
	local opcode = raw % 256
	local a      = math.floor(raw / 256) % 256
	local b      = math.floor(raw / 65536) % 256
	local c      = math.floor(raw / 16777216) % 256
	local d      = math.floor(raw / 65536) % 65536  -- unsigned 16-bit
	if d >= 32768 then d = d - 65536 end             -- sign extend to signed 16-bit

	local enum = Enums[opcode]
	if not enum then
		-- stub unknown as INVALID rather than crash
		enum = {Mnemonic = "INVALID", Type = "iABC"}
	end

	print("PARSER OPCODE [LUAU] --> ", opcode, enum.Mnemonic)

	local instruction = {
		Opcode     = opcode,
		OpcodeName = enum.Mnemonic,
		A          = a,
		Raw        = raw,
	}

	local mode = enum.Type
	if mode == "iABC" then
		instruction.B = {k = false, i = b}
		instruction.C = {k = false, i = c}
	elseif mode == "iAD" then
		instruction.Bx = d  -- reuse Bx field for D
		instruction.D  = d
	elseif mode == "iE" then
		local e = math.floor(raw / 256) % 16777216
		if e >= 8388608 then e = e - 16777216 end
		instruction.sBx = e
		instruction.E   = e
	end

	return instruction
end

local function readStringLuau(p)
	local len = readVarInt(p)
	if len == 0 then return nil end
	return p:ReadBytes(len)
end

local function readFunctionLuau(p, strings)
	local func = {
		Source        = nil,
		LineDefined   = 0,
		LastLineDefined= 0,
		NumUpvalues   = 0,
		NumParams     = 0,
		IsVararg      = 0,
		MaxStackSize  = 0,
		Instructions  = {},
		Constants     = {},
		Prototypes    = {}
	}

	-- max stack size
	func.MaxStackSize = p:ReadByte()
	func.NumParams    = p:ReadByte()
	func.NumUpvalues  = p:ReadByte()
	func.IsVararg     = p:ReadByte()

	-- flags (version 4+)
	local flags = p:ReadByte()

	-- typeinfo size (skip)
	local typeinfoSize = readVarInt(p)
	for i = 1, typeinfoSize do p:ReadByte() end

	-- instructions
	local numInstr = readVarInt(p)
	for i = 1, numInstr do
		local raw = p:ReadInt32()
		func.Instructions[i] = decodeInstructionLuau(raw)
		func.Instructions[i].Index = i

		-- read AUX word for opcodes that need it
		local op = func.Instructions[i].Opcode
		-- opcodes with AUX: GETIMPORT(10), GETTABLEKS(13), SETTABLEKS(14),
		-- NAMECALL(18), JUMPIFEQ(25), JUMPIFLE(26), JUMPIFLT(27),
		-- JUMPIFNOTEQ(28), JUMPIFNOTLE(29), JUMPIFNOTLT(30),
		-- FORGLOOP(57), FASTCALL2(73), FASTCALL2K(74),
		-- JUMPXEQKNIL(76), JUMPXEQKB(77), JUMPXEQKN(78), JUMPXEQKS(79)
		local auxOpcodes = {
			[10]=true,[13]=true,[14]=true,[18]=true,
			[25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,
			[57]=true,[73]=true,[74]=true,
			[76]=true,[77]=true,[78]=true,[79]=true,
		}
		if auxOpcodes[op] then
			i = i + 1
			local auxRaw = p:ReadInt32()
			func.Instructions[#func.Instructions].AUX = auxRaw
			-- insert a placeholder so instruction indices stay aligned
			func.Instructions[i] = {
				Opcode = -1,
				OpcodeName = "PSEUDO",
				A = 0, Raw = auxRaw,
				B = {k=false,i=0}, C = {k=false,i=0},
				Index = i
			}
		end
	end

	-- constants
	local numConsts = readVarInt(p)
	for i = 1, numConsts do
		local constant = {Index = i - 1}
		local constType = p:ReadByte()

		if constType == 0 then       -- nil
			constant.Type = 'nil'; constant.Value = 'nil'
		elseif constType == 1 then   -- boolean
			constant.Type = 'boolean'; constant.Value = p:ReadByte() ~= 0
		elseif constType == 2 then   -- number (double)
			constant.Type = 'number'; constant.Value = p:ReadDouble()
		elseif constType == 3 then   -- string (index into string table)
			local idx = readVarInt(p)
			constant.Type = 'string'
			constant.Value = strings[idx] or ("__str_"..idx)
		elseif constType == 4 then   -- import (chain of string indices)
			constant.Type = 'import'
			local count = p:ReadByte()
			local parts = {}
			for j = 1, count do
				local idx2 = readVarInt(p)
				parts[j] = strings[idx2] or ("__str_"..idx2)
			end
			constant.Value = table.concat(parts, ".")
		elseif constType == 5 then   -- table (template)
			constant.Type = 'table'
			local kcount = readVarInt(p)
			local keys = {}
			for j = 1, kcount do
				local kidx = readVarInt(p)
				keys[j] = strings[kidx] or ("__str_"..kidx)
			end
			constant.Value = "{" .. table.concat(keys, ", ") .. "}"
		elseif constType == 6 then   -- closure (proto index)
			constant.Type = 'closure'
			constant.Value = readVarInt(p)
		elseif constType == 7 then   -- vector
			constant.Type = 'vector'
			-- 4 floats: x, y, z, w
			local x = p:ReadFloat(); local y = p:ReadFloat()
			local z = p:ReadFloat(); local w = p:ReadFloat()
			constant.Value = ("Vector3.new(%g,%g,%g)"):format(x, y, z)
		end
		func.Constants[i] = constant
	end

	-- nested prototypes
	local numProtos = readVarInt(p)
	for i = 1, numProtos do
		func.Prototypes[i] = readFunctionLuau(p, strings)
		func.Prototypes[i].Index = i - 1
	end

	-- line info (skip)
	local hasLineInfo = p:ReadByte()
	if hasLineInfo ~= 0 then
		local lineGapLog2 = p:ReadByte()
		local intervals = math.floor((numInstr + (2^lineGapLog2) - 1) / (2^lineGapLog2))
		-- lineinfo: numInstr bytes
		for i = 1, numInstr do p:ReadByte() end
		-- abslineinfo: intervals * 4 bytes each
		for i = 1, intervals do p:ReadInt32() end
	end

	-- debug info (skip)
	local hasDebugInfo = p:ReadByte()
	if hasDebugInfo ~= 0 then
		local numLocals = readVarInt(p)
		for i = 1, numLocals do
			readStringLuau(p)  -- name
			readVarInt(p)       -- startpc
			readVarInt(p)       -- endpc
			p:ReadByte()        -- reg
		end
		local numUpvals = readVarInt(p)
		for i = 1, numUpvals do
			readStringLuau(p)
		end
	end

	-- source name
	local srcIdx = readVarInt(p)
	func.Source = strings[srcIdx] or "@luau-script"
	func.LineDefined = 0
	func.LastLineDefined = 0

	return func
end

local function parseLuau(bytecode)
	-- skip version byte (already checked in caller)
	local version = parser:ReadByte()
	if version == 0 then
		-- version 0 = error string from compiler
		local errMsg = parser:ReadBytes(#bytecode - 1)
		error("Luau bytecode compile error: " .. tostring(errMsg))
	end

	-- string table
	local numStrings = readVarInt(parser)
	local strings = {}
	for i = 1, numStrings do
		local len = readVarInt(parser)
		strings[i] = parser:ReadBytes(len)
	end

	-- number of protos in the chunk
	local numProtos = readVarInt(parser)
	local protos = {}
	for i = 1, numProtos do
		protos[i] = readFunctionLuau(parser, strings)
	end

	-- main proto index
	local mainIdx = readVarInt(parser)
	local main = protos[mainIdx + 1] or protos[1]
	main.Source = main.Source or "@luau-script"

	return {
		{signature="luau", version=version},
		main
	}
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

return function(bytecode)
	parser = parser.new(bytecode)

	if settings.LuauMode then
		_G.display("Parsing as Luau bytecode...", "cyan")
		return parseLuau(bytecode)
	else
		return {
			readHeader51(),
			readFunction51('@compiled-lua')
		}
	end
end
