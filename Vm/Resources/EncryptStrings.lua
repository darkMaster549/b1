-- LZW compress --
-- UPDATED: 5x encryption layers, key always runtime-derived, never raw --
-- this is only i see weekness for now when i try deobf our Obfuscator so i patch it --

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

-- Key is ALWAYS derived at runtime from (rawHex, salt). Never stored directly.
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

-- One layer: derive key from rawHex+salt at runtime, XOR, then LZW.
-- rawHex = LZW(original input) stored so runtime can re-derive the key.
-- encoded = LZW(XOR'd input) stored as the ciphertext.
local function encryptLayer(str, salt)
	local rawHex = hexEncode(lzwCompress(str))
	local key    = deriveKey(rawHex, salt)
	local xored  = xorCipher(str, key)
	local encoded = hexEncode(lzwCompress(xored))
	return encoded, rawHex
end

local LAYERS = 5

-- 5-layer encrypt. Layer 1 = innermost (encrypts raw str).
-- Layer 5 = outermost (what ends up stored in source).
-- Serialized as: L1enc|L1raw|L1salt|L2enc|L2raw|L2salt|...|L5enc|L5raw|L5salt
-- Runtime peels from L5 down to L1 to recover original.
-- KEY IS NEVER IN THE OUTPUT -- only rawHex+salt, from which key is re-derived.
local function encryptMultiLayer(str)
	local layers = {}

	-- Layer 1 encrypts the raw string
	local s1 = math.random(100, 9999)
	local e1, r1 = encryptLayer(str, s1)
	layers[1] = {enc=e1, raw=r1, salt=s1}

	-- Layers 2-5 each encrypt the previous layer's encoded output
	for l = 2, LAYERS do
		local sl = math.random(100, 9999)
		local el, rl = encryptLayer(layers[l-1].enc, sl)
		layers[l] = {enc=el, raw=rl, salt=sl}
	end

	-- Serialize all layer data (no keys, only enc+raw+salt per layer)
	local parts = {}
	for l = 1, LAYERS do
		table.insert(parts, layers[l].enc)
		table.insert(parts, layers[l].raw)
		table.insert(parts, tostring(layers[l].salt))
	end

	-- outermost encoded = layers[LAYERS].enc
	return table.concat(parts, "|"), layers[LAYERS].enc
end

return function(scriptSource, wantsFunction)
	if wantsFunction == true then
		-- Used by TreeGenerator for constant encryption.
		-- Returns: outerEnc (outermost layer hex), blob (full 5-layer descriptor)
		-- 'blob' stored as rawHex field in the constants blob so runtime
		-- knows it's multi-layer (contains "|" separators).
		return function(str, salt)
			math.randomseed(salt + os.time())
			local blob, outerEnc = encryptMultiLayer(str)
			return outerEnc, blob
		end
	end

	-- Per-string mode: replace "string" literals with __mlDecrypt("blob")
	local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
		local blob, _ = encryptMultiLayer(match)
		blob = blob:gsub("\\", "\\\\"):gsub('"', '\\"')
		return string.format('__mlDecrypt("%s")', blob)
	end)

	return encryptedScript
end
