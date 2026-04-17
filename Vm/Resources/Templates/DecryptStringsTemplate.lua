return [=[
local __decrypt_fn = function(d, o)
	local codes = {}
	for token in d:gmatch("[^,]+") do
		local n = 0
		for c in token:gmatch(".") do
			local v = c:byte()
			if v >= 48 and v <= 57 then v = v - 48
			else v = v - 87 end
			n = n * 36 + v
		end
		table.insert(codes, n)
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
]=]
