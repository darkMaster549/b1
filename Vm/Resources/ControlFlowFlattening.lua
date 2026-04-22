math.randomseed(os.time())

local main = {}

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

local function runtimeAlwaysTrue(v)
	local a = math.random(2, 30)
	local opts = {
		string.format("(%s * 0) == 0", v),
		string.format("(%s - %s) == 0", v, v),
		string.format("%s == %s", v, v),
		string.format("((%s + %d) - %d) == %s", v, a, a, v),
	}
	return opts[math.random(1, #opts)]
end

local function runtimeAlwaysFalse(v)
	local opts = {
		string.format("%s ~= %s", v, v),
		string.format("(%s * 0) > 1", v),
		string.format("(%s + 0) < %s", v, v),
		string.format("(%s - %s) == 1", v, v),
	}
	return opts[math.random(1, #opts)]
end

local function getJunk(v)
	local lv1, lv2 = randVar(), randVar()
	local n = math.random(1, 99)
	local opts = {
		string.format("if %s then local %s = %s * 0 end", runtimeAlwaysFalse(v), lv1, v),
		string.format("do local %s = %s - %s local %s = %s + 0 end", lv1, v, v, lv2, lv1),
		string.format("if %s then local %s = nil end", runtimeAlwaysFalse(v), lv1),
		string.format("local %s = (%s * 0) + %d", lv1, v, n),
		string.format("if %s then if %s then local %s = %s end end", runtimeAlwaysFalse(v), runtimeAlwaysFalse(v), lv1, v),
	}
	return opts[math.random(1, #opts)]
end

local function getPointerCheck(target)
	local style = math.random(1, 4)
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
	else
		local a = math.random(1, math.max(1, target - 1))
		local b = math.random(1, 80)
		return string.format("(pointer - %d + %d) == %d", a, b, target - a + b)
	end
end

local function shuffle(t)
	local out = {}
	for i, v in pairs(t) do out[#out+1] = {p=i, c=v} end
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

function main:generateState(opcodeMap)
	local output = {}
	local isFirst = true

	-- Find max ptr so junk states use out-of-range values
	local maxPtr = 0
	for k in pairs(opcodeMap) do
		if k > maxPtr then maxPtr = k end
	end

	local function emitJunkState()
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
	end

	for idx, data in ipairs(shuffle(opcodeMap)) do
		local ptr, op = data.p, data.c

		if not op or op == "" or op:match("^%s*$") then
			op = getJunk("pointer")
		end

		local check  = getPointerCheck(ptr)
		local junk1  = getJunk("pointer")
		local junk2  = getJunk("pointer")

		local wrapStyle = math.random(1, 3)
		local wrapped

		if wrapStyle == 1 then
			-- dead branch before real op
			wrapped = string.format(
				"if %s then\n\t\t\t\t\t%s\n\t\t\t\tend\n\t\t\t\tdo\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysFalse("pointer"), junk1, op
			)
		elseif wrapStyle == 2 then
			-- real op inside always-true, junk inside always-false after
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tdo\n\t\t\t\t\t\t%s\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tif %s then\n\t\t\t\t\t%s\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), op, runtimeAlwaysFalse("pointer"), junk2
			)
		else
			-- nested: always-true -> always-false (junk) else (real op)
			wrapped = string.format(
				"if %s then\n\t\t\t\t\tif %s then\n\t\t\t\t\t\t%s\n\t\t\t\t\telse\n\t\t\t\t\t\tdo\n\t\t\t\t\t\t\t%s\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend",
				runtimeAlwaysTrue("pointer"), runtimeAlwaysFalse("pointer"), junk1, op
			)
		end

		local line = string.format(
			"%s %s then\n\t\t\t%s",
			isFirst and "if" or "elseif", check, wrapped
		)
		table.insert(output, line)
		isFirst = false

		-- inject junk state after every 2-3 real states
		if math.random(1, 3) ~= 1 then
			emitJunkState()
		end
	end

	return table.concat(output, "\n") .. "\nend"
end

return main
