-- IBPasses.lua
-- Ported from IronBrew 2 C# to pure Lua
-- Passes: Bounce, TestFlip, EqMutate, TestSpam

local IBPasses = {}

-- ==================== HELPERS ====================

-- makeJMP stores _jmpTarget as absolute index.
-- At the end of each pass, fixJmpOffsets() converts all _jmpTarget
-- values into relative sBx offsets that the VM actually reads.
local function makeJMP(targetIdx)
	return {
		Opcode     = 22,
		OpcodeName = "JMP",
		A          = 0,
		sBx        = 0,        -- will be fixed by fixJmpOffsets()
		_jmpTarget = targetIdx, -- absolute instruction index
	}
end

-- After all insertions are done, walk the list and convert every
-- _jmpTarget (absolute) into the relative sBx the VM expects:
--   sBx = target - currentPos - 1
-- (pointer is incremented BEFORE the JMP sBx is added, so -1)
local function fixJmpOffsets(insts)
	for i, inst in ipairs(insts) do
		if inst._jmpTarget then
			inst.sBx = inst._jmpTarget - i - 1
			inst._jmpTarget = nil
		end
	end
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
-- Every JMP gets redirected through a new intermediate JMP
-- JMP -> target  becomes  JMP -> newJMP -> target

function IBPasses.Bounce(insts)
	local result = {}
	for i = 1, #insts do
		result[i] = insts[i]
	end

	-- First pass: tag existing JMPs with their current absolute target.
	-- Real JMPs from the parser use sBx (relative). Convert to absolute.
	for i, inst in ipairs(result) do
		if inst.OpcodeName == "JMP" and not inst._jmpTarget then
			local sbx = type(inst.sBx) == "number" and inst.sBx or 0
			inst._jmpTarget = i + 1 + sbx
		end
	end

	local extras = {}
	for i = 1, #result do
		local inst = result[i]
		if inst.OpcodeName == "JMP" and inst._jmpTarget then
			local bounce = makeJMP(inst._jmpTarget)
			table.insert(extras, { after = i, bounce = bounce })
			inst._bounceRef = bounce
			inst._jmpTarget = nil
		end
	end

	-- Insert bounce JMPs back-to-front so earlier indices stay stable
	for j = #extras, 1, -1 do
		local e = extras[j]
		table.insert(result, e.after + 1, e.bounce)
	end

	-- Now find where each bounce ended up and set the original JMP to point to it
	for i = 1, #result do
		local inst = result[i]
		if inst._bounceRef then
			for j = 1, #result do
				if result[j] == inst._bounceRef then
					inst._jmpTarget = j
					break
				end
			end
			inst._bounceRef = nil
		end
	end

	fixJmpOffsets(result)
	return result
end

-- ==================== TESTFLIP ====================
-- Randomly flips A on EQ/LT/LE/TEST and inserts a compensating JMP
-- so the branch semantics are preserved.
--
-- Original layout:
--   i     compare/test
--   i+1   skip-JMP  (jumps over i+2 if condition NOT met)
--   i+2   fallthrough
--
-- After flip, the sense is inverted, so we insert a new JMP at i+1
-- that jumps to the fallthrough, and shift the old skip-JMP to i+2.
-- New layout:
--   i     compare/test (A flipped)
--   i+1   compJMP  -> fallthrough (now at i+3 after insert)
--   i+2   old skip-JMP (still jumps past one instruction)
--   i+3   fallthrough

function IBPasses.TestFlip(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	-- Convert existing JMP sBx to absolute _jmpTarget first
	for i, inst in ipairs(result) do
		if inst.OpcodeName == "JMP" and not inst._jmpTarget then
			local sbx = type(inst.sBx) == "number" and inst.sBx or 0
			inst._jmpTarget = i + 1 + sbx
		end
	end

	-- Iterate backwards so inserted instructions don't shift
	-- the indices of instructions we haven't reached yet
	local i = #result
	while i >= 1 do
		local inst = result[i]
		local flip = math.random(0, 1) == 1

		if flip and (isCompare(inst) or inst.OpcodeName == "TEST") then
			-- Flip A register
			local oldA = type(inst.A) == "table" and inst.A.i or inst.A
			local newA = oldA == 0 and 1 or 0
			if type(inst.A) == "table" then
				inst.A.i = newA
			else
				inst.A = newA
			end

			-- Insert compensating JMP at i+1.
			-- After this insert the fallthrough instruction moves from i+2 to i+3.
			-- All _jmpTargets >= i+1 in the list shift up by 1 too -- fix them.
			for k = 1, #result do
				local other = result[k]
				if other._jmpTarget and other._jmpTarget >= i + 1 then
					other._jmpTarget = other._jmpTarget + 1
				end
			end

			local compJMP = makeJMP(i + 3) -- fallthrough is now at i+3
			table.insert(result, i + 1, compJMP)
		end

		i = i - 1
	end

	fixJmpOffsets(result)
	return result
end

-- ==================== EQMUTATE ====================
-- Replaces EQ with equivalent: LT + JMP + LE + JMP + JMP

function IBPasses.EqMutate(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	-- Convert existing JMP sBx to absolute _jmpTarget first
	for i, inst in ipairs(result) do
		if inst.OpcodeName == "JMP" and not inst._jmpTarget then
			local sbx = type(inst.sBx) == "number" and inst.sBx or 0
			inst._jmpTarget = i + 1 + sbx
		end
	end

	local i = 1
	while i <= #result do
		local inst = result[i]
		if inst.OpcodeName == "EQ" then
			local regA    = type(inst.A) == "table" and inst.A.i or inst.A
			local skipJMP = result[i + 1]
			local branchTarget = skipJMP and skipJMP._jmpTarget or (i + 2)
			-- fallthrough: after removing 2 and inserting 5, net +3
			local fallthrough = i + 5

			local newLT = copyInst(inst)
			newLT.Opcode     = 24
			newLT.OpcodeName = "LT"
			newLT.A          = type(inst.A) == "table" and { i = regA, k = false } or regA

			local j1 = makeJMP(fallthrough)

			local newLE = copyInst(inst)
			newLE.Opcode     = 25
			newLE.OpcodeName = "LE"
			local flippedA   = regA == 0 and 1 or 0
			newLE.A          = type(inst.A) == "table" and { i = flippedA, k = false } or flippedA

			local j2 = makeJMP(fallthrough)
			local j3 = makeJMP(branchTarget)

			table.remove(result, i)     -- remove EQ
			if result[i] and result[i].OpcodeName == "JMP" then
				table.remove(result, i) -- remove skip-JMP
			end

			table.insert(result, i,     newLT)
			table.insert(result, i + 1, j1)
			table.insert(result, i + 2, newLE)
			table.insert(result, i + 3, j2)
			table.insert(result, i + 4, j3)

			i = i + 5
		else
			i = i + 1
		end
	end

	fixJmpOffsets(result)
	return result
end

-- ==================== TESTSPAM ====================
-- Duplicates TEST/EQ/LT/LE branches into redundant trees.
-- All JMP targets are tracked as absolute indices and converted
-- to relative sBx only at the very end via fixJmpOffsets().

function IBPasses.TestSpam(insts, depth)
	depth = depth or 2

	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	-- Convert existing JMP sBx to absolute _jmpTarget first
	for i, inst in ipairs(result) do
		if inst.OpcodeName == "JMP" and not inst._jmpTarget then
			local sbx = type(inst.sBx) == "number" and inst.sBx or 0
			inst._jmpTarget = i + 1 + sbx
		end
	end

	for d = 1, depth do
		local targets = {}
		for i = 1, #result do
			if isCompare(result[i]) or isTest(result[i]) then
				table.insert(targets, i)
			end
		end

		-- Process back-to-front so earlier indices stay stable
		for j = #targets, 1, -1 do
			local idx = targets[j]
			if idx < 2 then goto continue end

			local orig = result[idx]
			local junkTarget = math.max(1, idx - math.random(1, math.max(1, idx - 1)))

			-- Layout we are building (all indices are AFTER all inserts below):
			--
			--  idx       original compare         (unchanged)
			--  idx+1     j2_start  -> copy1 block (new insert)
			--  idx+2     original fallthrough      (shifted up by 1)
			--  ...
			--  N+1       copy1   (duplicate compare)
			--  N+2       j1_fall -> idx+2
			--  N+3       j1_junk -> junkTarget
			--  N+4       copy2   (duplicate compare)
			--  N+5       j2_junk -> junkTarget
			--  N+6       j2_fall -> idx+2
			--
			-- where N = #result before any inserts this iteration.

			local N = #result

			local copy1  = copyInst(orig)
			local copy2  = copyInst(orig)

			-- Targets after inserts:
			--   inserting j2_start at idx+1 shifts everything above by 1
			--   so fallthrough (was idx+1 before) becomes idx+2
			local fallthroughAfter = idx + 2
			local copy1Pos         = N + 2  -- after j2_start insert shifts N+1 -> N+2? No:
			-- append 6 items first (copy1..j2_fall), then insert j2_start.
			-- So copy1 lands at N+1, then insert at idx+1 shifts it to N+2.
			-- Actually: appending puts copy1 at N+1 before the insert.
			-- After insert at idx+1 (idx+1 <= N), all indices > idx shift by 1.
			-- N+1 > idx always (idx < N), so copy1 ends at N+2.

			local j1_fall  = makeJMP(fallthroughAfter)
			local j1_junk  = makeJMP(junkTarget)        -- junk doesn't shift (it's <= idx)
			local j2_junk  = makeJMP(junkTarget)
			local j2_fall  = makeJMP(fallthroughAfter)
			local j2_start = makeJMP(copy1Pos)          -- -> copy1 after shift

			-- Append copy1 block (positions N+1, N+2, N+3 before insert)
			table.insert(result, copy1)
			table.insert(result, j1_fall)
			table.insert(result, j1_junk)

			-- Append copy2 block (positions N+4, N+5, N+6 before insert)
			table.insert(result, copy2)
			table.insert(result, j2_junk)
			table.insert(result, j2_fall)

			-- Insert redirect at idx+1 — shifts everything above idx by 1
			-- including the appended blocks (N+1..N+6 become N+2..N+7)
			table.insert(result, idx + 1, j2_start)

			-- Fix up any _jmpTargets that pointed above idx (they all shifted +1)
			-- j2_start itself already has the correct post-shift target (copy1Pos = N+2)
			-- j1_fall and j2_fall both pointed to fallthroughAfter = idx+2, which
			-- is also already the correct post-shift index.
			-- junkTarget <= idx so it did NOT shift — j1_junk and j2_junk are fine.

			::continue::
		end
	end

	fixJmpOffsets(result)
	return result
end

return IBPasses
