-- LZW compress --
-- UPDATED --
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

local function encrypt(str, key)
	local result = {}
	local keyLen = #key
	for i = 1, #str do
		local strByte = string.byte(str, i)
		local keyByte = string.byte(key, (i - 1) % keyLen + 1)
		table.insert(result, string.char(bit32.bxor(strByte, keyByte)))
	end
	return table.concat(result)
end

-- Derive a key from the raw (pre-XOR) LZW+hex blob and a numeric salt.
-- Must match __deriveKey in DecryptStringsTemplate.lua exactly.
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

-- Main function
return function(scriptSource, wantsFunction)
	if wantsFunction == true then
		-- Returns a function(str, salt) -> encoded, rawHex
		-- rawHex is stored in the blob for runtime key derivation (no key in output).
		return function(str, salt)
			local rawHex = hexEncode(lzwCompress(str))
			local key    = deriveKey(rawHex, salt)
			local xored  = encrypt(str, key)
			local encoded = hexEncode(lzwCompress(xored))
			return encoded, rawHex
		end
	end

	-- Per-string encryption for script source literals.
	-- Output: decrypt("encoded","rawHex",salt)  -- XOR key never written to output
	local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
		local salt   = math.random(100, 9999)
		local rawHex = hexEncode(lzwCompress(match))
		local key    = deriveKey(rawHex, salt)
		local xored  = encrypt(match, key)
		local encoded = hexEncode(lzwCompress(xored))
		return string.format('decrypt("%s","%s",%d)', encoded, rawHex, salt)
	end)

	return encryptedScript
end
