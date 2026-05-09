-- IBPasses.lua
-- Passes: Bounce, TestFlip, EqMutate, TestSpam
-- Fix by darkMaster549
local IBPasses = {}

-- ==================== HELPERS ====================

-- ALL opcodes that store a PC-relative branch offset.
-- These must all be absorbed into _jmpTarget before any inserts,
-- so shiftTargets() keeps them correct, then fixed back after.
local BRANCH_OPS = {
	-- Lua 5.1
	JMP      = { field = "sBx" },
	FORLOOP  = { field = "sBx" },
	FORPREP  = { field = "sBx" },
	-- Luau
	JUMP             = { field = "sBx" },
	JUMPBACK         = { field = "sBx" },
	JUMPX            = { field = "sBx" },
	FORNPREP         = { field = "D" },
	FORNLOOP         = { field = "D" },
	FORGPREP         = { field = "D" },
	FORGLOOP         = { field = "D" },
	FORGPREP_INEXT   = { field = "D" },
	FORGLOOP_INEXT   = { field = "D" },
	FORGPREP_NEXT    = { field = "D" },
	FORGLOOP_NEXT    = { field = "D" },
}

-- Convert all branch instructions from relative offset to absolute _jmpTarget.
-- sBx = target - pos - 1  =>  target = pos + 1 + sBx
local function absorbBranchOps(insts)
	for i, inst in ipairs(insts) do
		local info = BRANCH_OPS[inst.OpcodeName]
		if info and inst._jmpTarget == nil then
			local offset = inst[info.field]
			if type(offset) == "number" then
				inst._jmpTarget    = i + 1 + offset
				inst._branchField  = info.field  -- remember which field to restore
				inst[info.field]   = nil
			end
		end
	end
end

-- After ALL inserts are done, convert _jmpTarget back to relative offset.
local function fixBranchOffsets(insts)
	for i, inst in ipairs(insts) do
		if inst._jmpTarget ~= nil then
			local field = inst._branchField or "sBx"
			local offset = inst._jmpTarget - i - 1
			inst[field]        = offset
			inst.sBx           = offset  -- always keep sBx in sync (getReg reads it)
			inst._jmpTarget    = nil
			inst._branchField  = nil
		end
	end
end

-- When an instruction is inserted at insertPos, shift every _jmpTarget
-- that points at or past that position up by 1.
local function shiftTargets(insts, insertPos)
	for _, inst in ipairs(insts) do
		if inst._jmpTarget ~= nil and inst._jmpTarget >= insertPos then
			inst._jmpTarget = inst._jmpTarget + 1
		end
	end
end

local function makeJMP(absTarget)
	return {
		Opcode        = 22,
		OpcodeName    = "JMP",
		A             = 0,
		sBx           = 0,
		_jmpTarget    = absTarget,
		_branchField  = "sBx",
	}
end

local function copyInst(inst)
	local t = {}
	for k, v in pairs(inst) do
		if type(v) == "table" then
			local inner = {}
			for k2, v2 in pairs(v) do inner[k2] = v2 end
			t[k] = inner
		else
			t[k] = v
		end
	end
	t._jmpTarget   = nil
	t._branchField = nil
	return t
end

local function isCompare(inst)
	local n = inst.OpcodeName
	return n == "EQ" or n == "LT" or n == "LE"
end

local function isTest(inst)
	local n = inst.OpcodeName
	return n == "TEST" or n == "TESTSET"
end

-- ==================== BOUNCE ====================
-- JMP -> target  becomes  JMP -> bounceJMP -> target

function IBPasses.Bounce(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	absorbBranchOps(result)

	-- Snapshot JMP positions only (not FORLOOP etc — no bounce needed for those)
	local jmpPositions = {}
	for i = 1, #result do
		if result[i].OpcodeName == "JMP"
		or result[i].OpcodeName == "JUMP"
		or result[i].OpcodeName == "JUMPBACK"
		or result[i].OpcodeName == "JUMPX" then
			table.insert(jmpPositions, i)
		end
	end

	-- Back-to-front so inserts don't shift unprocessed positions
	for j = #jmpPositions, 1, -1 do
		local i    = jmpPositions[j]
		local orig = result[i]

		-- Insert bounce at i+1; shift everything >= i+1 first
		shiftTargets(result, i + 1)

		local bounce = makeJMP(orig._jmpTarget)  -- bounce goes to old target (already shifted)
		table.insert(result, i + 1, bounce)

		orig._jmpTarget = i + 1  -- original now points to the bounce
	end

	fixBranchOffsets(result)
	return result
end

-- ==================== TESTFLIP ====================
-- Flips A on compare/test, inserts compensating JMP to preserve semantics.
--
-- Before:                     After:
--   i     CMP  A=0              i     CMP  A=1        (flipped)
--   i+1   skip-JMP -> T         i+1   compJMP -> i+3  (new)
--   i+2   fallthrough           i+2   skip-JMP -> T   (shifted)
--                               i+3   fallthrough     (shifted)

function IBPasses.TestFlip(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	absorbBranchOps(result)

	local i = #result
	while i >= 1 do
		local inst = result[i]
		if (isCompare(inst) or inst.OpcodeName == "TEST") and math.random(0, 1) == 1 then

			-- Flip A
			if type(inst.A) == "table" then
				inst.A.i = inst.A.i == 0 and 1 or 0
			else
				inst.A = inst.A == 0 and 1 or 0
			end

			-- Shift all targets >= i+1, then insert compensating JMP
			shiftTargets(result, i + 1)
			-- Fallthrough is now at i+3 (was i+2, shifted to i+3)
			table.insert(result, i + 1, makeJMP(i + 3))
		end
		i = i - 1
	end

	fixBranchOffsets(result)
	return result
end

-- ==================== EQMUTATE ====================
-- EQ A B C + skip-JMP->T  =>  LT A / JMP->fall / LE ~A / JMP->fall / JMP->T

function IBPasses.EqMutate(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	absorbBranchOps(result)

	local i = 1
	while i <= #result do
		local inst = result[i]
		if inst.OpcodeName == "EQ" then
			local regA      = type(inst.A) == "table" and inst.A.i or inst.A
			local skipJMP   = result[i + 1]
			local branchTgt = skipJMP and skipJMP._jmpTarget or (i + 2)

			-- Remove EQ and skip-JMP (2 instructions)
			table.remove(result, i)
			if result[i] and result[i].OpcodeName == "JMP" then
				table.remove(result, i)
			end

			-- After removing 2 at position i, targets > i shift down by 2
			for _, other in ipairs(result) do
				if other._jmpTarget ~= nil and other._jmpTarget > i then
					other._jmpTarget = other._jmpTarget - 2
				end
			end
			if branchTgt > i then branchTgt = branchTgt - 2 end

			-- Insert 5 instructions at i; targets >= i shift up by 5
			for _, other in ipairs(result) do
				if other._jmpTarget ~= nil and other._jmpTarget >= i then
					other._jmpTarget = other._jmpTarget + 5
				end
			end
			if branchTgt >= i then branchTgt = branchTgt + 5 end

			local fallTgt = i + 5  -- fallthrough is right after our 5 new instructions

			local newLT = copyInst(inst)
			newLT.Opcode = 24; newLT.OpcodeName = "LT"
			newLT.A = type(inst.A) == "table" and {i=regA, k=false} or regA

			local newLE = copyInst(inst)
			newLE.Opcode = 25; newLE.OpcodeName = "LE"
			local flipped = regA == 0 and 1 or 0
			newLE.A = type(inst.A) == "table" and {i=flipped, k=false} or flipped

			table.insert(result, i,     newLT)
			table.insert(result, i + 1, makeJMP(fallTgt))
			table.insert(result, i + 2, newLE)
			table.insert(result, i + 3, makeJMP(fallTgt))
			table.insert(result, i + 4, makeJMP(branchTgt))

			i = i + 5
		else
			i = i + 1
		end
	end

	fixBranchOffsets(result)
	return result
end

-- ==================== TESTSPAM ====================
-- Duplicates compare/test into redundant branch trees.
--
-- For compare at idx, after transformation:
--   idx     original compare
--   idx+1   j_start -> copy1        (inserted here, shifts everything above)
--   idx+2   fallthrough ...
--   ...
--   N+2     copy1
--   N+3     j1_fall -> idx+2
--   N+4     j1_junk -> junkTarget
--   N+5     copy2
--   N+6     j2_junk -> junkTarget
--   N+7     j2_fall -> idx+2

function IBPasses.TestSpam(insts, depth)
	depth = depth or 2

	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	absorbBranchOps(result)

	for d = 1, depth do
		local targets = {}
		for i = 1, #result do
			if isCompare(result[i]) or isTest(result[i]) then
				table.insert(targets, i)
			end
		end

		for j = #targets, 1, -1 do
			local idx = targets[j]
			if idx < 2 then goto continue end

			local N    = #result
			local orig = result[idx]
			local junkTarget = math.max(1, idx - math.random(1, math.max(1, idx - 1)))

			-- Step 1: append 6 items at N+1..N+6
			-- Step 2: insert j_start at idx+1, shifting N+1..N+6 to N+2..N+7
			-- So: fallthrough = idx+2, copy1 = N+2, copy2 = N+5

			local fallthroughAfter = idx + 2
			local copy1Pos         = N + 2
			-- copy2 is at N+4 before insert, N+5 after (copy1, j1_fall, j1_junk, copy2)

			-- Step 1: append
			table.insert(result, copyInst(orig))          -- N+1 -> N+2 after insert
			table.insert(result, makeJMP(fallthroughAfter)) -- N+2 -> N+3  (j1_fall)
			table.insert(result, makeJMP(junkTarget))       -- N+3 -> N+4  (j1_junk)
			table.insert(result, copyInst(orig))            -- N+4 -> N+5  (copy2)
			table.insert(result, makeJMP(junkTarget))       -- N+5 -> N+6  (j2_junk)
			table.insert(result, makeJMP(fallthroughAfter)) -- N+6 -> N+7  (j2_fall)

			-- Step 2: shift all targets >= idx+1, then insert j_start
			shiftTargets(result, idx + 1)
			table.insert(result, idx + 1, makeJMP(copy1Pos))

			::continue::
		end
	end

	fixBranchOffsets(result)
	return result
end

return IBPasses
