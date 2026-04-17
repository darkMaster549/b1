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

-- Hex encode a list of numbers (each number as 4 hex chars)
local function hexEncode(codes)
	local parts = {}
	for _, code in ipairs(codes) do
		table.insert(parts, string.format("%04X", code))
	end
	return table.concat(parts)
end

-- Hex decode back to list of numbers
local function hexDecode(str)
	local codes = {}
	for i = 1, #str, 4 do
		local chunk = str:sub(i, i+3)
		table.insert(codes, tonumber(chunk, 16))
	end
	return codes
end

-- LZW decompress
local function lzwDecompress(codes)
	local dict = {}
	for i = 0, 255 do dict[i] = string.char(i) end
	local dictSize = 256
	local w = string.char(codes[1])
	local result = {w}
	for i = 2, #codes do
		local k = codes[i]
		local entry
		if dict[k] then
			entry = dict[k]
		elseif k == dictSize then
			entry = w .. w:sub(1,1)
		end
		table.insert(result, entry)
		dict[dictSize] = w .. entry:sub(1,1)
		dictSize = dictSize + 1
		w = entry
	end
	return table.concat(result)
end

-- XOR encrypt
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

-- Main function
return function(scriptSource, wantsFunction)
	if wantsFunction == true then
		-- Returns a function: XOR then LZW then Hex
		return function(str, key)
			local xored = encrypt(str, key)
			local codes = lzwCompress(xored)
			return hexEncode(codes)
		end
	end

	local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
		local key = tostring(math.random(100, 3000))
		local xored = encrypt(match, key)
		local codes = lzwCompress(xored)
		local encoded = hexEncode(codes)
		return string.format('decrypt("%s","%s")', encoded, key)
	end)

	return encryptedScript
end
