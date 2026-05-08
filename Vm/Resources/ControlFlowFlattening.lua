-- ControlFlowFlattening.lua
-- Original b1 CFF + IronBrew 2 concepts merged

math.randomseed(os.time())

local main = {}

-- ==================== NAME GEN ====================

local function randVar()
	local pool = {"ll","lI","Il","II","lll","llI","lIl","Ill","lllI","llIl","lIll","Illl"}
	local base = pool[math.random(1, #pool)]
	local extra = math.random(2, 4)
	local chars = {}
	for i = 1, extra do
		chars[i] = (math.random(0,1) == 0) and "l" or "I"
	end
	return base .. table.concat(chars)
end

-- ==================== OPAQUE PREDICATES ====================

local function runtimeAlwaysTrue(v)
	local a = math.random(2, 30)
	local opts = {
		string.format("(%s * 0) == 0", v),
		string.format("(%s - %s) == 0", v, v),
		string.format("%s == %s", v, v),
		string.format("((%s + %d) - %d) == %s", v, a, a, v),
		string.format("((%s * 1) + 0) == %s", v, v),
		string.format("(math.floor(%s) - math.floor(%s)) == 0", v, v),
	}
	return opts[math.random(1, #opts)]
end

local function runtimeAlwaysFalse(v)
	local opts = {
		string.format("%s ~= %s", v, v),
		string.format("(%s * 0) > 1", v),
		string.format("(%s + 0) < %s", v, v),
		string.format("(%s - %s) == 1", v, v),
		string.format("(%s * 0 + 1) < 0", v),
		string.format("((%s + 1) == %s)", v, v),
	}
	return opts[math.random(1, #opts)]
end

-- ==================== JUNK CODE ====================

local function getJunk(v)
	local lv1, lv2 = randVar(), randVar()
	local n = math.random(1, 99)
	local opts = {
		string.format("if %s then local %s = %s * 0 end", runtimeAlwaysFalse(v), lv1, v),
		string.format("do local %s = %s - %s local %s = %s + 0 end", lv1, v, v, lv2, lv1),
		string.format("if %s then local %s = nil end", runtimeAlwaysFalse(v), lv1),
		string.format("local %s = (%s * 0) + %d", lv1, v, n),
		string.format("if %s then if %s then local %s = %s end end", runtimeAlwaysFalse(v), runtimeAlwaysFalse(v), lv1, v),
		-- IronBrew style: believable-looking dead branches
		string.format("if %s then local %s = %s + %d end", runtimeAlwaysFalse(v), lv1, v, math.random(1,100)),
		string.format("do local %s = %s * 1 local %s = %s - 0 end", lv1, v, lv2, lv1),
		string.format("if %s then %s = %s + 0 end", runtimeAlwaysFalse(v), v, v),
	}
	return opts[math.random(1, #opts)]
end

-- ==================== POINTER CHECKS ====================
-- IronBrew uses: eq check, mul+add check, xor-style
-- We combine both styles

local function getPointerCheck(target)
	local style = math.random(1, 6)
	if style == 1 then
		local a, b = math.random(1, 50), math.random(2, 20)
		return string.format("((pointer + %d) * %d) == %d", a, b, (target + a) * b)
	elseif style == 2 then
		local a, b = math.random(2, 15), math.random(1, 30)
		local c = math.random(2, 8)
		return string.format("((pointer * %d + %d) * %d) == %d", a, b, c, (target * a + b) * c)
	elseif style == 3 then
		local pad = math.random(10, 200)
		return string.format("(pointer + %d) == %d", pad, target + pad)
	elseif style == 4 then
		local a = math.random(1, math.max(1, target - 1))
		local b = math.random(1, 80)
		return string.format("(pointer - %d + %d) == %d", a, b, target - a + b)
	elseif style == 5 then
		-- IronBrew style: mul check
		local m = math.random(3, 12)
		return string.format("(pointer * %d) == %d", m, target * m)
	else
		-- IronBrew style: nested add
		local a, b = math.random(1, 20), math.random(1, 20)
		return string.format("((pointer + %d) - %d) == %d", a, b, target + a - b)
	end
end

-- ==================== SHUFFLE ====================

local function shuffle(t)
	local out = {}
	for i, v in pairs(t) do out[#out+1] = {p=i, c=v} end
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- ==================== BOUNCE JUNK STATE ====================
-- IronBrew's Bounce concept: junk states that chain to each other

local function emitBounceChain(output, isFirst, maxPtr, count)
	count = count or math.random(1, 3)
	local lastCheck = nil
	for i = 1, count do
		local fakePtr = maxPtr + math.random(1000, 9999)
		local check = getPointerCheck(fakePtr)
		local j1 = getJunk("pointer")
		local j2 = getJunk("pointer")
		local line = string.format(
			"%s %s then\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\t\t%s\n\t\t\t\tend",
			isFirst and "if" or "elseif", check, j1, j2
		)
		table.insert(output, line)
		isFirst = false
		lastCheck = check
	end
	return isFirst
end

-- ==================== MAIN GENERATE ====================

function main:generateState(opcodeMap)
	local output = {}
	local isFirst = true

	local maxPtr = 0
	for k in pairs(opcodeMap) do
		if k > maxPtr then maxPtr = k end
	end

	local function emitJunkState()
		isFirst = emitBounceChain(output, isFirst, maxPtr, 1)
	end

	for idx, data in ipairs(shuffle(opcodeMap)) do
		local ptr, op = data.p, data.c

		if not op or op == "" or op:match("^%s*$") then
			op = getJunk("pointer")
		end

		local check  = getPointerCheck(ptr)
		local junk1  = getJunk("pointer")
		local junk2  = getJunk("pointer")

		local wrapStyle = math.random(1, 5)
		local wrapped

		if wrapStyle == 1 then
			-- dead branch before real op (original style)
			wrapped = string.format(
				"if %s then local %s = %s * 0 end\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysFalse("pointer"), randVar(), "pointer", op
			)
		elseif wrapStyle == 2 then
			-- real op inside always-true, junk inside always-false after
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tdo\n\t\t\t\t\t\t%s\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tif %s then\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), op, runtimeAlwaysFalse("pointer"), junk2
			)
		elseif wrapStyle == 3 then
			-- nested always-true -> always-false (junk) else (real op)
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tif %s then\n\t\t\t\t\t\t%s\n\t\t\t\t\telse\n\t\t\t\t\t\tdo\n\t\t\t\t\t\t\t%s\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), runtimeAlwaysFalse("pointer"), junk1, op
			)
		elseif wrapStyle == 4 then
			-- IronBrew Bounce style: double-wrapped in two always-true checks
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tif %s then\n\t\t\t\t\t\tdo\n\t\t\t\t\t\t\t%s\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), runtimeAlwaysTrue("pointer"), op
			)
		else
			-- IronBrew TestFlip style: junk on both sides
			wrapped = string.format(
				"if %s then\n\t\t\t\t\t%s\n\t\t\t\tend\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\tend\n\t\t\t\tif %s then\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysFalse("pointer"), junk1, op,
				runtimeAlwaysFalse("pointer"), junk2
			)
		end

		local line = string.format(
			"%s %s then\n\t\t\t%s",
			isFirst and "if" or "elseif", check, wrapped
		)
		table.insert(output, line)
		isFirst = false

		-- inject junk/bounce states between real ones
		if math.random(1, 3) ~= 1 then
			emitJunkState()
		end

		-- IronBrew: occasionally inject a bounce chain (2-3 linked junk states)
		if math.random(1, 5) == 1 then
			isFirst = emitBounceChain(output, isFirst, maxPtr, math.random(2, 3))
		end
	end

	return table.concat(output, "\n") .. "\nend"
end

return main
