-- IBPasses.lua
-- Ported from IronBrew 2 C# to pure Lua
-- Passes: Bounce, TestFlip, EqMutate, TestSpam

local IBPasses = {}

-- ==================== HELPERS ====================

local function makeJMP(targetIdx)
	return {
		Opcode     = 22,
		OpcodeName = "JMP",
		A          = { i = 0, k = false },
		B          = { i = targetIdx, k = false },
		C          = { i = 0, k = false },
		_jmpTarget = targetIdx, -- raw index reference
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
	return t
end

local function buildMap(insts)
	local map = {}
	for i, inst in ipairs(insts) do
		map[inst] = i
	end
	return map
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

	local extras = {}
	for i = 1, #result do
		local inst = result[i]
		if inst.OpcodeName == "JMP" and inst._jmpTarget then
			local bounce = makeJMP(inst._jmpTarget)
			table.insert(extras, { after = i, jmp = bounce })
			inst._jmpTarget = nil -- will be patched below
			inst._bounceRef = bounce
		end
	end

	-- insert bounce JMPs from back to front so indices stay valid
	for j = #extras, 1, -1 do
		local e = extras[j]
		table.insert(result, e.after + 1, e.jmp)
		-- patch original to point to the new bounce JMP position
		e.jmp._insertedAt = e.after + 1
	end

	-- fix _jmpTarget on original JMPs to point to their bounce
	for i = 1, #result do
		local inst = result[i]
		if inst._bounceRef then
			-- find where bounce ended up
			for j = 1, #result do
				if result[j] == inst._bounceRef then
					inst._jmpTarget = j
					break
				end
			end
			inst._bounceRef = nil
		end
	end

	return result
end

-- ==================== TESTFLIP ====================
-- Randomly flips A register on EQ/LT/LE/TEST
-- and inserts a compensating JMP so semantics are preserved

function IBPasses.TestFlip(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	local i = #result
	while i >= 1 do
		local inst = result[i]
		local flip = math.random(0, 1) == 1

		if flip and (isCompare(inst) or inst.OpcodeName == "TEST") then
			-- flip A (0->1 or 1->0)
			local oldA = type(inst.A) == "table" and inst.A.i or inst.A
			local newA = oldA == 0 and 1 or 0
			if type(inst.A) == "table" then
				inst.A.i = newA
			else
				inst.A = newA
			end

			-- insert compensating JMP after the original skip-JMP (i+1)
			-- so we skip to i+2 (the original fallthrough) instead
			local skipTarget = i + 2
			if skipTarget <= #result + 1 then
				local compJMP = makeJMP(skipTarget)
				compJMP.OpcodeName = "JMP"
				compJMP.Opcode = 22
				table.insert(result, i + 1, compJMP)
			end
		end

		i = i - 1
	end

	return result
end

-- ==================== EQMUTATE ====================
-- Replaces EQ with equivalent: LT + JMP + LE + JMP + JMP
-- EQ A B C  =>  LT A B C / JMP->fallthrough / LE ~A B C / JMP->fallthrough / JMP->target

function IBPasses.EqMutate(insts)
	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	local i = 1
	while i <= #result do
		local inst = result[i]
		if inst.OpcodeName == "EQ" then
			local regA = type(inst.A) == "table" and inst.A.i or inst.A
			local regB = inst.B
			local regC = inst.C

			-- original skip JMP is at i+1, target of that JMP is the real branch target
			local skipJMP = result[i + 1]
			local branchTarget = skipJMP and skipJMP._jmpTarget or (i + 2)
			local fallthrough   = i + 2

			-- LT A B C  (same sense as EQ)
			local newLT = copyInst(inst)
			newLT.Opcode     = 24
			newLT.OpcodeName = "LT"
			newLT.A          = type(inst.A) == "table" and { i = regA, k = false } or regA

			-- JMP -> fallthrough
			local j1 = makeJMP(fallthrough + 3) -- will shift after inserts

			-- LE ~A B C
			local newLE = copyInst(inst)
			newLE.Opcode     = 25
			newLE.OpcodeName = "LE"
			local flippedA = regA == 0 and 1 or 0
			newLE.A = type(inst.A) == "table" and { i = flippedA, k = false } or flippedA

			-- JMP -> fallthrough
			local j2 = makeJMP(fallthrough + 3)

			-- JMP -> original branch target
			local j3 = makeJMP(branchTarget)

			-- replace EQ + skipJMP with the 5-instruction sequence
			table.remove(result, i)     -- remove EQ
			if result[i] and result[i].OpcodeName == "JMP" then
				table.remove(result, i) -- remove original skip JMP
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

	return result
end

-- ==================== TESTSPAM ====================
-- Recursively duplicates TEST/EQ/LT/LE branches into a tree
-- depth = how many recursion levels (IB uses 3)

function IBPasses.TestSpam(insts, depth)
	depth = depth or 2 -- keep it sane, IB uses 3 but that's huge

	local result = {}
	for i = 1, #insts do result[i] = insts[i] end

	local function addGroup(targetInsts, idx, inst)
		if idx < 2 then return {} end

		local copy1 = copyInst(inst)
		local copy2 = copyInst(inst)

		-- branch 1: cmp + JMP to fallthrough + JMP to junk (random earlier idx)
		local junkTarget = math.max(1, idx - math.random(1, math.max(1, idx - 1)))
		local j1_correct = makeJMP(idx + 2)
		local j1_junk    = makeJMP(junkTarget)

		-- branch 2: cmp + JMP to junk + JMP to correct
		local j2_junk    = makeJMP(junkTarget)
		local j2_correct = makeJMP(idx + 2)
		local j2_start   = makeJMP(#targetInsts + 4) -- points to copy2 block appended at end

		-- append group 1 at end
		table.insert(targetInsts, copy1)
		table.insert(targetInsts, j1_correct)
		table.insert(targetInsts, j1_junk)

		-- insert redirect before original idx+1 (the skip JMP)
		table.insert(targetInsts, idx + 1, j2_start)

		-- append group 2
		table.insert(targetInsts, copy2)
		table.insert(targetInsts, j2_junk)
		table.insert(targetInsts, j2_correct)

		return { copy1, copy2 }
	end

	for d = 1, depth do
		local targets = {}
		for i = 1, #result do
			local inst = result[i]
			if isCompare(inst) or isTest(inst) then
				table.insert(targets, i)
			end
		end

		-- process from back to front to keep indices stable
		local newTargets = {}
		for j = #targets, 1, -1 do
			local idx = targets[j]
			if idx >= 2 then
				local copies = addGroup(result, idx, result[idx])
				for _, c in ipairs(copies) do
					table.insert(newTargets, c)
				end
			end
		end
	end

	return result
end

return IBPasses
