-- LZW compress --
-- 1-layer encryption, key always runtime-derived, never raw --

local function lzwCompress(data)
	local dict = {}
	for i = 0, 255 do dict[string.char(i)] = i end
	local dictSize = 256
	local w = ""
	local result = {}
	for i = 1, #data do
		local c = data:sub(i,i)
		local wc = w..c
		if dict[wc] then
			w = wc
		else
			table.insert(result, dict[w])
			dict[wc] = dictSize
			dictSize = dictSize + 1
			w = c
		end
	end
	if w ~= "" then table.insert(result, dict[w]) end
	return result
end

local function hexEncode(codes)
	local parts = {}
	for _, code in ipairs(codes) do
		table.insert(parts, string.format("%04X", code))
	end
	return table.concat(parts)
end

local function deriveKey(rawHex, salt)
	local n = salt
	for i = 1, #rawHex do
		n = (n * 31 + rawHex:byte(i)) % 99991
	end
	local parts = {}
	local tmp = n
	for _ = 1, 6 do
		table.insert(parts, string.char(33 + (tmp % 89)))
		tmp = math.floor(tmp / 89)
	end
	return table.concat(parts)
end

local function xorCipher(str, key)
	local result = {}
	local keyLen = #key
	for i = 1, #str do
		local sb = string.byte(str, i)
		local kb = string.byte(key, (i - 1) % keyLen + 1)
		table.insert(result, string.char(bit32.bxor(sb, kb)))
	end
	return table.concat(result)
end

-- Single layer: derive key from rawHex+salt, XOR, then LZW
local function encryptLayer(str, salt)
	local rawHex = hexEncode(lzwCompress(str))
	local key    = deriveKey(rawHex, salt)
	local xored  = xorCipher(str, key)
	local encoded = hexEncode(lzwCompress(xored))
	return encoded, rawHex
end

return function(scriptSource, wantsFunction)
	if wantsFunction == true then
		return function(str, salt)
			math.randomseed(salt + os.time())
			local encoded, rawHex = encryptLayer(str, salt)
			return encoded, rawHex
		end
	end

	-- Per-string mode: replace "string" literals with decrypt call
	local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
		local salt = math.random(100, 9999)
		local encoded, rawHex = encryptLayer(match, salt)
		encoded = encoded:gsub("\\", "\\\\"):gsub('"', '\\"')
		rawHex  = rawHex:gsub("\\", "\\\\"):gsub('"', '\\"')
		return string.format('__decrypt_fn(__deriveKey("%s",%d),"%s")', rawHex, salt, encoded)
	end)

	return encryptedScript
end
