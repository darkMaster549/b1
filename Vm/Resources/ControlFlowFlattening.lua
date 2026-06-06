-- ControlFlowFlattening.lua
-- Original b1 CFF + IronBrew 2 concepts merged

math.randomseed(os.time())

local main = {}

-- Short aliases (matches Header.lua)
local A = math.abs
local B = math.floor
local D = math.ceil
local E = math.max
local F = math.min
local G = math.sqrt
local H = math.sin
local I = math.cos
local K = math.random

-- ==================== NAME GEN ====================

local function randVar()
	local pool = {"ll","lI","Il","II","lll","llI","lIl","Ill","lllI","llIl","lIll","Illl"}
	local base = pool[K(1, #pool)]
	local extra = K(2, 4)
	local chars = {}
	for i = 1, extra do
		chars[i] = (K(0,1) == 0) and "l" or "I"
	end
	return base .. table.concat(chars)
end

-- ==================== OPAQUE PREDICATES ====================

local function runtimeAlwaysTrue(v)
	local a = K(2, 30)
	local b = K(1, 10)
	local opts = {
		-- original
		string.format("(%s * 0) == 0", v),
		string.format("(%s - %s) == 0", v, v),
		string.format("%s == %s", v, v),
		string.format("((%s + %d) - %d) == %s", v, a, a, v),
		string.format("((%s * 1) + 0) == %s", v, v),
		string.format("(B(%s) - B(%s)) == 0", v, v),
		-- B (math.floor)
		string.format("B(%s * 1) == B(%s)", v, v),
		string.format("B(%s + %d) == B(%s) + %d", v, a, v, a),
		string.format("B(%s - %s) == 0", v, v),
		string.format("B((%s * 0) + %d) == %d", v, a, a),
		-- A (math.abs)
		string.format("A(%s - %s) == 0", v, v),
		string.format("A(%s * 0) == 0", v),
		string.format("A(B(%s) - B(%s)) == 0", v, v),
		string.format("A(%s * 0 + %d) == %d", v, a, a),
		-- H (math.sin) / I (math.cos)
		string.format("H(%s) == H(%s)", v, v),
		string.format("I(%s) == I(%s)", v, v),
		string.format("B(H(%s * 0)) == 0", v),
		string.format("A(H(%s) - H(%s)) == 0", v, v),
		string.format("A(I(%s) - I(%s)) == 0", v, v),
		-- G (math.sqrt)
		string.format("A(G((%s * 0 + %d)^2) - %d) < 1", v, a, a),
		string.format("B(G((%s*0+%d)^2)) == %d", v, b*b, b*b),
		-- E/F (math.max / math.min)
		string.format("E(%s, %s) == %s", v, v, v),
		string.format("F(%s, %s) == %s", v, v, v),
		string.format("E(%s * 0, 0) == 0", v),
		string.format("F(%s * 0 + %d, %d) == %d", v, a, a, a),
		-- combined
		string.format("B(A(%s - %s)) == 0", v, v),
		string.format("A(B(H(%s)) - B(H(%s))) == 0", v, v),
		string.format("E(A(%s * 0), 0) == 0", v),
		string.format("B(I(%s * 0)) == 1", v),
	}
	return opts[K(1, #opts)]
end

local function runtimeAlwaysFalse(v)
	local a = K(2, 30)
	local opts = {
		-- original
		string.format("%s ~= %s", v, v),
		string.format("(%s * 0) > 1", v),
		string.format("(%s + 0) < %s", v, v),
		string.format("(%s - %s) == 1", v, v),
		string.format("(%s * 0 + 1) < 0", v),
		string.format("((%s + 1) == %s)", v, v),
		-- B (math.floor)
		string.format("B(%s) ~= B(%s)", v, v),
		string.format("B(%s * 0) > 1", v),
		string.format("B(%s * 0 + 1) < 0", v),
		string.format("B(%s + 0) < B(%s)", v, v),
		-- A (math.abs)
		string.format("A(%s - %s) > 0", v, v),
		string.format("A(%s * 0) > 1", v),
		string.format("A(%s - %s) == 1", v, v),
		-- H (math.sin) / I (math.cos)
		string.format("H(%s) ~= H(%s)", v, v),
		string.format("I(%s) ~= I(%s)", v, v),
		string.format("B(H(%s * 0)) > 1", v),
		string.format("A(H(%s) - H(%s)) > 1", v, v),
		-- G (math.sqrt)
		string.format("G(%s * 0 + 1) < 0", v),
		string.format("B(G(%s * 0)) > 1", v),
		-- E/F (math.max / math.min)
		string.format("E(%s, %s) ~= %s", v, v, v),
		string.format("F(%s * 0, 0) > 1", v),
		string.format("E(%s * 0, 0) < 0", v),
		-- combined
		string.format("B(A(%s - %s)) > 0", v, v),
		string.format("A(I(%s) - I(%s)) > 1", v, v),
		string.format("F(A(%s * 0), 0) > 1", v),
		string.format("B(I(%s * 0)) == 0", v),
	}
	return opts[K(1, #opts)]
end

-- ==================== JUNK CODE ====================

local function getJunk(v)
	local lv1, lv2 = randVar(), randVar()
	local n = K(1, 99)
	local opts = {
		string.format("if %s then local %s = %s * 0 end", runtimeAlwaysFalse(v), lv1, v),
		string.format("do local %s = %s - %s local %s = %s + 0 end", lv1, v, v, lv2, lv1),
		string.format("if %s then local %s = nil end", runtimeAlwaysFalse(v), lv1),
		string.format("local %s = (%s * 0) + %d", lv1, v, n),
		string.format("if %s then if %s then local %s = %s end end", runtimeAlwaysFalse(v), runtimeAlwaysFalse(v), lv1, v),
		string.format("if %s then local %s = %s + %d end", runtimeAlwaysFalse(v), lv1, v, K(1,100)),
		string.format("do local %s = %s * 1 local %s = %s - 0 end", lv1, v, lv2, lv1),
		string.format("if %s then %s = %s + 0 end", runtimeAlwaysFalse(v), v, v),
		-- math alias junk
		string.format("if %s then local %s = B(%s * 0) end", runtimeAlwaysFalse(v), lv1, v),
		string.format("do local %s = A(%s - %s) local %s = B(%s) end", lv1, v, v, lv2, lv1),
		string.format("if %s then local %s = H(%s) * 0 end", runtimeAlwaysFalse(v), lv1, v),
		string.format("do local %s = G(%s * 0 + 1) - 1 end", lv1, v),
		string.format("if %s then local %s = I(%s) - I(%s) end", runtimeAlwaysFalse(v), lv1, v, v),
		string.format("do local %s = E(%s * 0, 0) local %s = F(%s, %s) end", lv1, v, lv2, v, v),
		string.format("if %s then local %s = A(B(%s) - B(%s)) end", runtimeAlwaysFalse(v), lv1, v, v),
	}
	return opts[K(1, #opts)]
end

-- ==================== POINTER CHECKS ====================

local function getPointerCheck(target)
	local style = K(1, 10)
	if style == 1 then
		local a, b = K(1, 50), K(2, 20)
		return string.format("((pointer + %d) * %d) == %d", a, b, (target + a) * b)
	elseif style == 2 then
		local a, b = K(2, 15), K(1, 30)
		local c = K(2, 8)
		return string.format("((pointer * %d + %d) * %d) == %d", a, b, c, (target * a + b) * c)
	elseif style == 3 then
		local pad = K(10, 200)
		return string.format("(pointer + %d) == %d", pad, target + pad)
	elseif style == 4 then
		local a = K(1, math.max(1, target - 1))
		local b = K(1, 80)
		return string.format("(pointer - %d + %d) == %d", a, b, target - a + b)
	elseif style == 5 then
		local m = K(3, 12)
		return string.format("(pointer * %d) == %d", m, target * m)
	elseif style == 6 then
		local a, b = K(1, 20), K(1, 20)
		return string.format("((pointer + %d) - %d) == %d", a, b, target + a - b)
	elseif style == 7 then
		local a = K(1, 50)
		return string.format("B(pointer + %d) == %d", a, B(target + a))
	elseif style == 8 then
		local a = K(1, 30)
		return string.format("A(pointer - %d) == %d", target, A(target - target))
	elseif style == 9 then
		local m = K(2, 10)
		return string.format("B(pointer * %d) == %d", m, B(target * m))
	else
		local a = K(1, 20)
		return string.format("A((pointer + %d) - %d) == 0", a, target + a)
	end
end

-- ==================== SHUFFLE ====================

local function shuffle(t)
	local out = {}
	for i, v in pairs(t) do out[#out+1] = {p=i, c=v} end
	for i = #out, 2, -1 do
		local j = K(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- ==================== BOUNCE JUNK STATE ====================

local function emitBounceChain(output, isFirst, maxPtr, count)
	count = count or K(1, 3)
	local lastCheck = nil
	for i = 1, count do
		local fakePtr = maxPtr + K(1000, 9999)
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

		local wrapStyle = K(1, 5)
		local wrapped

		if wrapStyle == 1 then
			wrapped = string.format(
				"if %s then local %s = %s * 0 end\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysFalse("pointer"), randVar(), "pointer", op
			)
		elseif wrapStyle == 2 then
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tdo\n\t\t\t\t\t\t%s\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tif %s then\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), op, runtimeAlwaysFalse("pointer"), junk2
			)
		elseif wrapStyle == 3 then
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tif %s then\n\t\t\t\t\t\t%s\n\t\t\t\t\telse\n\t\t\t\t\t\tdo\n\t\t\t\t\t\t\t%s\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), runtimeAlwaysFalse("pointer"), junk1, op
			)
		elseif wrapStyle == 4 then
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tif %s then\n\t\t\t\t\t\tdo\n\t\t\t\t\t\t\t%s\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), runtimeAlwaysTrue("pointer"), op
			)
		else
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

		if K(1, 3) ~= 1 then
			emitJunkState()
		end

		if K(1, 5) == 1 then
			isFirst = emitBounceChain(output, isFirst, maxPtr, K(2, 3))
		end
	end

	return table.concat(output, "\n") .. "\nend"
end

return main
