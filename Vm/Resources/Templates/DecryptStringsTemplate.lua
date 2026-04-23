return [=[
-- 5-layer LZW+XOR runtime decrypt. Key NEVER stored -- always derived from rawHex+salt.

local __decrypt_fn = function(d, o)
	local codes = {}
	for i = 1, #d, 4 do
		table.insert(codes, tonumber(d:sub(i, i+3), 16))
	end
	local dict = {}
	for i = 0, 255 do dict[i] = string.char(i) end
	local dictSize = 256
	local w = string.char(codes[1])
	local result = {w}
	for i = 2, #codes do
		local k = codes[i]
		local entry
		if dict[k] then entry = dict[k]
		elseif k == dictSize then entry = w .. w:sub(1,1)
		end
		table.insert(result, entry)
		dict[dictSize] = w .. entry:sub(1,1)
		dictSize = dictSize + 1
		w = entry
	end
	local lzwOut = table.concat(result)
	local keyLen = #o
	local out = {}
	for i = 1, #lzwOut do
		local sb = lzwOut:byte(i)
		local kb = o:byte((i-1) % keyLen + 1)
		local x, t, l, bit = 0, sb, kb, 1
		for _ = 1, 8 do
			if t%2 ~= l%2 then x = x + bit end
			t = (t - t%2) / 2
			l = (l - l%2) / 2
			bit = bit * 2
		end
		table.insert(out, string.char(x))
	end
	return table.concat(out)
end

-- Derive XOR key from rawHex+salt at runtime. Never stored directly.
-- Must match deriveKey in EncryptStrings.lua exactly.
local __deriveKey = function(rawHex, salt)
	local n = salt
	for i = 1, #rawHex do
		n = (n * 31 + rawHex:byte(i)) % 99991
	end
	local parts = {}
	local tmp = n
	for _ = 1, 6 do
		parts[#parts+1] = string.char(33 + (tmp % 89))
		tmp = math.floor(tmp / 89)
	end
	return table.concat(parts)
end

-- Peel all 5 layers from a blob serialized as:
--   L1enc|L1raw|L1salt|L2enc|L2raw|L2salt|...|L5enc|L5raw|L5salt
-- L1 = innermost, L5 = outermost. Peel from L5 -> L1.
local __mlDecrypt_fn = function(blob)
	local segs = {}
	for s in blob:gmatch("[^|]+") do
		table.insert(segs, s)
	end
	local LAYERS = 5
	local layers = {}
	for l = 1, LAYERS do
		local b = (l - 1) * 3
		layers[l] = {
			enc  = segs[b + 1],
			raw  = segs[b + 2],
			salt = tonumber(segs[b + 3]),
		}
	end
	-- Start from outermost encoded, peel inward
	local current = layers[LAYERS].enc
	for l = LAYERS, 1, -1 do
		current = __decrypt_fn(current, __deriveKey(layers[l].raw, layers[l].salt))
	end
	return current
end

-- Single-layer decrypt for backward compat (used internally by __unpack_consts fallback)
local decrypt = function(d, rawHex, salt)
	return __decrypt_fn(d, __deriveKey(rawHex, salt))
end

-- Exposed for use inside the VM body (string literal decryption)
local __mlDecrypt = __mlDecrypt_fn

-- Unpack constants from the HEBREW! blob.
-- When rawHex contains "|", it's a 5-layer blob -- use __mlDecrypt_fn directly.
-- Otherwise fall back to single-layer.
local function __unpack_consts(blob, cShift)
	blob = blob:gsub("^HEBREW!", "")

	local segs = {}
	for s in blob:gmatch("[^R]+") do table.insert(segs, s) end
	local total = #segs / 4

	local encs, rawHexes, salts, shifts = {}, {}, {}, {}
	for i = 1, total do
		encs[i]     = segs[i]
		rawHexes[i] = segs[i + total]
		salts[i]    = tonumber(segs[i + total * 2])
		shifts[i]   = tonumber(segs[i + total * 3])
	end

	local out = {}
	for i = 1, total do
		local perShift = shifts[i] or cShift
		local dec
		if rawHexes[i] and rawHexes[i]:find("|") then
			-- 5-layer path: rawHexes[i] is the full layer blob
			dec = __mlDecrypt_fn(rawHexes[i])
		else
			-- single-layer fallback
			dec = __decrypt_fn(encs[i], __deriveKey(rawHexes[i], salts[i]))
		end
		local len = #dec
		local lastByte = dec:byte(len)
		if lastByte == 11 then
			local raw = dec:sub(1, len - 1)
			local shifted = {}
			for j = 1, #raw do
				shifted[j] = string.char((raw:byte(j) + perShift) % 256)
			end
			out[i] = tonumber(table.concat(shifted))
		elseif lastByte == 7 then
			out[i] = dec:byte(1) == 116
		elseif lastByte == 6 then
			out[i] = nil
		else
			local shifted = {}
			for j = 1, len do
				shifted[j] = string.char((dec:byte(j) + perShift) % 256)
			end
			out[i] = table.concat(shifted)
		end
	end
	return out
end
]=]
