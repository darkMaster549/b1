-- NameGenerator.lua
-- Generates mangled variable names for block IDs
-- Produces names like: _0xGHq2, _0xbR7k, __lIlIl, etc.

local rng = math.random

local HEX_CHARS = "0123456789abcdef"
local CONFUSE_POOL = {"l","I","1","O","0"} -- visually confusing chars

local function hexStr(len)
	local out = {}
	for i = 1, len do
		local idx = rng(1, #HEX_CHARS)
		out[i] = HEX_CHARS:sub(idx, idx)
	end
	return table.concat(out)
end

local function confuseStr(len)
	local out = {}
	for i = 1, len do
		out[i] = CONFUSE_POOL[rng(1, #CONFUSE_POOL)]
	end
	return table.concat(out)
end

local used = {}

local function generate()
	local name
	local attempts = 0
	repeat
		attempts = attempts + 1
		local style = rng(1, 3)
		if style == 1 then
			-- _0x style: _0xGHq2a
			name = "_0x" .. hexStr(rng(4, 7))
		elseif style == 2 then
			-- confuse style: __lIl1O
			name = "__" .. confuseStr(rng(4, 8))
		else
			-- mixed: _lI0x3f
			name = "_" .. confuseStr(rng(2, 4)) .. hexStr(rng(2, 4))
		end
		-- avoid duplicates
		if attempts > 1000 then
			name = name .. tostring(rng(1, 99999))
			break
		end
	until not used[name]
	used[name] = true
	return name
end

local function reset()
	used = {}
end

return {
	generate = generate,
	reset    = reset,
}
