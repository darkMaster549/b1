-- LZW compress --
-- i will use Hex method soon --
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

-- Base36 encode a list of numbers
local function base36Encode(codes)
	local parts = {}
	for _, code in ipairs(codes) do
		local s = ""
		if code == 0 then
			s = "0"
		else
			local n = code
			while n > 0 do
				local rem = n % 36
				s = (rem < 10 and tostring(rem) or string.char(87 + rem)) .. s
				n = math.floor(n / 36)
			end
		end
		table.insert(parts, s)
	end
	return table.concat(parts, ",")
end

-- Base36 decode
local function base36Decode(str)
	local codes = {}
	for token in str:gmatch("[^,]+") do
		local n = 0
		for c in token:gmatch(".") do
			local v = c:byte()
			if v >= 48 and v <= 57 then v = v - 48
			else v = v - 87 end
			n = n * 36 + v
		end
		table.insert(codes, n)
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
		-- Returns a function: XOR then LZW then Base36
		return function(str, key)
			local xored = encrypt(str, key)
			local codes = lzwCompress(xored)
			return base36Encode(codes)
		end
	end

	local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
		local key = tostring(math.random(100, 3000))
		local xored = encrypt(match, key)
		local codes = lzwCompress(xored)
		local encoded = base36Encode(codes)
		return string.format('decrypt("%s","%s")', encoded, key)
	end)

	return encryptedScript
end
