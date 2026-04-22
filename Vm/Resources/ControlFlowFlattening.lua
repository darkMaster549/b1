math.randomseed(os.time())

local main = {}

-- Shuffle
local function shuffle(t)
	local out = {}
	for i, v in pairs(t) do
		out[#out+1] = { p = i, c = v }
	end
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Random identifier that looks like a real variable name
local function randVar()
	local prefixes = {"l","ll","lI","Il","II","lll","llI","lIl","Ill"}
	local p = prefixes[math.random(1, #prefixes)]
	local len = math.random(3, 7)
	local chars = {}
	for i = 1, len do
		chars[i] = (math.random(0,1) == 0) and "l" or "I"
	end
	return p .. table.concat(chars)
end

-- Opaque predicate: always true, but looks complex
-- Returns a condition string that always evaluates to true
local function alwaysTrue()
	local a = math.random(2, 15)
	local b = math.random(1, a - 1)
	local opts = {
		-- a^2 - b^2 == (a+b)*(a-b)  -> always true
		string.format("(%d * %d) == (%d * %d)", a+b, a-b, a*a-b*b, 1),
		-- n % 2 == n % 2  -> always true
		string.format("(%d %% 2) == (%d %% 2)", a, a),
		-- bit trick: n & 0 == 0  -> always true
		string.format("(%d * 0) == 0", math.random(1, 9999)),
		-- a + b == b + a  -> always true (commutativity)
		string.format("(%d + %d) == (%d + %d)", a, b, b, a),
	}
	return opts[math.random(1, #opts)]
end

-- Opaque predicate: always false
local function alwaysFalse()
	local a = math.random(2, 50)
	local opts = {
		-- a^2 < 0  -> always false
		string.format("(%d * %d) < 0", a, a),
		-- 0 ~= 0  -> always false
		string.format("(0) ~= (0)"),
		-- a > a  -> always false
		string.format("%d > %d", a, a),
		-- a + 1 == a  -> always false
		string.format("(%d + 1) == %d", a, a),
	}
	return opts[math.random(1, #opts)]
end

-- Junk that looks plausible but is truly dead
local function getJunk()
	local v1, v2 = randVar(), randVar()
	local n1, n2 = math.random(1, 20), math.random(1, 20)
	local junkOpts = {
		-- Dead assignment under always-false guard
		string.format("if %s then local %s = %d end", alwaysFalse(), v1, math.random(1,999)),
		-- Nested dead block
		string.format("do local %s = %d local %s = %s + %d end", v1, n1, v2, v1, n2),
		-- Tautology check that does nothing
		string.format("local %s = %s", v1, alwaysTrue() and "true" or "false"),
		-- Math that goes nowhere
		string.format("local %s = (%d + %d) * %d", v1, n1, n2, math.random(1,10)),
		-- Double negation no-op
		string.format("local %s = not not %s", v1, alwaysTrue()),
		-- Unreachable nested condition
		string.format("if %s then if %s then local %s = nil end end", alwaysFalse(), alwaysTrue(), v1),
	}
	return junkOpts[math.random(1, #junkOpts)]
end

-- Build a pointer check that hides the real target value using 3-operand math
-- e.g. ((pointer + a) * b) - c == result  where result is precomputed
local function getPointerCheck(target)
	local style = math.random(1, 4)
	if style == 1 then
		-- ((pointer + a) * b) == result
		local a = math.random(1, 100)
		local b = math.random(2, 50)
		local result = (target + a) * b
		return string.format("((pointer + %d) * %d) == %d", a, b, result)
	elseif style == 2 then
		-- (pointer * a + b) * c == result
		local a = math.random(2, 20)
		local b = math.random(1, 50)
		local c = math.random(2, 10)
		local result = (target * a + b) * c
		return string.format("((pointer * %d + %d) * %d) == %d", a, b, c, result)
	elseif style == 3 then
		-- pointer + (a * b) == target + (a * b)
		local a = math.random(2, 30)
		local b = math.random(2, 30)
		local pad = a * b
		return string.format("(pointer + %d) == %d", pad, target + pad)
	else
		-- (pointer - a + b) == target - a + b
		local a = math.random(1, target - 1 > 0 and target - 1 or 1)
		local b = math.random(1, 100)
		local result = target - a + b
		return string.format("(pointer - %d + %d) == %d", a, b, result)
	end
end


local function wrapOpcode(op)
	local style = math.random(1, 3)
	local junk1, junk2 = getJunk(), getJunk()

	if style == 1 then
		
		return string.format(
			"if %s then\n\t\t\t%s\n\t\tend\n\t\tif %s then\n\t\t\tdo\n\t\t\t\t%s\n\t\t\tend\n\t\tend",
			alwaysFalse(), junk1, alwaysTrue(), op
		)
	elseif style == 2 then
		
		return string.format(
			"do\n\t\t\t%s\n\t\tend\n\t\tif %s then\n\t\t\t%s\n\t\tend",
			op, alwaysFalse(), junk2
		)
	else
		
		return string.format(
			"if %s then\n\t\t\tif %s then\n\t\t\t\t%s\n\t\t\telse\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\tend\n\t\t\tend\n\t\tend",
			alwaysTrue(), alwaysFalse(), junk1, op
		)
	end
end

function main:generateState(opcodeMap)
	local output = {}

	for i, data in ipairs(shuffle(opcodeMap)) do
		local ptr, op = data.p, data.c

		if not op or op == "" or op:match("^%s*$") then
			op = getJunk()
		end

		local check   = getPointerCheck(ptr)
		local wrapped = wrapOpcode(op)

		local line = string.format(
			"%s %s then\n\t%s",
			i == 1 and "if" or "elseif",
			check,
			wrapped
		)
		table.insert(output, line)
	end

	return table.concat(output, "\n") .. "\nend"
end

return main
