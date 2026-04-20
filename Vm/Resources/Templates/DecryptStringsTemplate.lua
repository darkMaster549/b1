return [=[
local __decrypt_fn = function(d, o)
	local codes = {}
	for i = 1, #d, 4 do
		local chunk = d:sub(i, i+3)
		table.insert(codes, tonumber(chunk, 16))
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
local decrypt = __decrypt_fn

local function __unpack_consts(blob, cShift)
	blob = blob:gsub("^HEBREW!", "")
	local segs = {}
	for s in blob:gmatch("[^R]+") do table.insert(segs, s) end
	local total = #segs / 2
	local out = {}
	for i = 1, total do
		local dec = __decrypt_fn(segs[i], segs[i + total])
		local len = #dec
		local lastByte = dec:byte(len)
		if lastByte == 11 then
			local raw = dec:sub(1, len - 1)
			local shifted = {}
			for j = 1, #raw do
				shifted[j] = string.char(raw:byte(j) + cShift)
			end
			out[i] = tonumber(table.concat(shifted))
		elseif lastByte == 7 then
			out[i] = dec:byte(1) == 116
		elseif lastByte == 6 then
			out[i] = nil
		else
			local shifted = {}
			for j = 1, len do
				shifted[j] = string.char(dec:byte(j) + cShift)
			end
			out[i] = table.concat(shifted)
		end
	end
	return out
end
]=]
