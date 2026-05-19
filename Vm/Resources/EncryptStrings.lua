local BASE91 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_`{|}~"

local function nibbleSwap(b)
    return ((b % 16) * 16 + math.floor(b / 16)) % 256
end

local function xorBit(a, b)
    if bit32 then return bit32.bxor(a, b) end
    if bit then return bit.bxor(a, b) end
    local r, p = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then r = r + p end
        a, b, p = math.floor(a/2), math.floor(b/2), p*2
    end
    return r
end

local function bytesToB91(bytes)
    local b91, n = 0, 0
    local out = {}
    for i = 1, #bytes do
        b91 = b91 + bytes[i] * (2 ^ n)
        n = n + 8
        if n > 13 then
            local val = b91 % 8192
            if val > 88 then
                b91 = math.floor(b91 / 8192); n = n - 13
            else
                val = b91 % 16384
                b91 = math.floor(b91 / 16384); n = n - 14
            end
            out[#out+1] = BASE91:sub((val % 91) + 1, (val % 91) + 1)
            out[#out+1] = BASE91:sub(math.floor(val / 91) + 1, math.floor(val / 91) + 1)
        end
    end
    if n > 0 then
        out[#out+1] = BASE91:sub((b91 % 91) + 1, (b91 % 91) + 1)
        if n > 7 or b91 > 90 then
            out[#out+1] = BASE91:sub(math.floor(b91 / 91) + 1, math.floor(b91 / 91) + 1)
        end
    end
    local result = table.concat(out)
    return (result == "" and "~" or result)
end

local function b91ToBytes(encoded)
    local map = {}
    for i = 1, #BASE91 do map[BASE91:byte(i) + 1] = i - 1 end
    local raw = {}
    local acc, bits, d = 0, 0, -1
    for i = 1, #encoded do
        local v = map[encoded:byte(i) + 1] or 0
        if d < 0 then
            d = v
        else
            d = d + v * 91
            local h = d % 8192
            if h > 88 then
                acc = acc + h * (2^bits); bits = bits + 13
            else
                acc = acc + (d % 16384) * (2^bits); bits = bits + 14
            end
            while bits > 7 do
                raw[#raw+1] = acc % 256
                acc = math.floor(acc / 256)
                bits = bits - 8
            end
            d = -1
        end
    end
    if d > -1 then raw[#raw+1] = (acc + d * (2^bits)) % 256 end
    return raw
end

local function base91Encode(input, salt)
    if not input or #input == 0 then return "~" end
    local transformed = {}
    for i = 1, #input do
        local b = (string.byte(input, i) + (i % 97) + (salt % 13)) % 256
        b = nibbleSwap(b)
        local prev = (i > 1) and transformed[i-1] or (0x5A + salt % 7)
        transformed[i] = xorBit(b, prev % 256)
    end
    return bytesToB91(transformed)
end

local function makeSbox(salt)
    local s = {}
    for i = 0, 255 do s[i] = i end
    local r = salt
    for i = 255, 1, -1 do
        r = (r * 1664525 + 1013904223) % 4294967296
        local j = r % (i + 1)
        s[i], s[j] = s[j], s[i]
    end
    return s
end

-- encodes a byte array, returns a byte array (no b91 yet)
local function encodeLayerBytes(inputBytes, salt, idx)
    local sbox = makeSbox(salt)
    local out = {}
    local prev = salt % 256
    for i = 1, #inputBytes do
        local b   = inputBytes[i]
        local key = (salt * 31 + idx * 17 + i * 7) % 256
        b = xorBit(b, key)
        b = sbox[b]
        b = xorBit(b, prev)
        prev = b
        out[i] = b
    end
    return out
end

local function encodeConstant(input, salt, idx)
    if not input or #input == 0 then return "~" end
    -- derive 3 independent salts
    local s1 = (salt % 9000) + 100
    local s2 = ((salt * 31 + idx * 7) % 9000) + 100
    local s3 = ((salt * 17 + idx * 13) % 9000) + 100
    -- convert input string to bytes
    local bytes = {}
    for i = 1, #input do bytes[i] = input:byte(i) end
    -- apply 3 layers on raw bytes
    local l1 = encodeLayerBytes(bytes, s1, idx)
    local l2 = encodeLayerBytes(l1,    s2, idx)
    local l3 = encodeLayerBytes(l2,    s3, idx)
    -- base91 encode the final bytes
    local encoded = bytesToB91(l3)
    -- prepend 3 salts as 4-digit each
    return string.format("%04d%04d%04d", s1, s2, s3) .. encoded
end

_G.__decryptFnName = _G.__decryptFnName or (function()
    local chars = "abcdefghijklmnopqrstuvwxyz"
    local t = {"_"}
    for i = 1, math.random(6,12) do
        t[#t+1] = chars:sub(math.random(1,#chars), math.random(1,#chars))
    end
    return table.concat(t)
end)()

return function(scriptSource, wantsFunction)
    if wantsFunction == true then
        return function(str, salt)
            local encoded = base91Encode(str, salt)
            return encoded, encoded
        end
    end

    local fnName = _G.__decryptFnName
    local encryptedScript = scriptSource:gsub('\"(.-)\"', function(match)
        local salt = math.random(100, 9999)
        local encoded = base91Encode(match, salt)
        encoded = encoded:gsub("\\", "\\\\"):gsub('"', '\\"')
        return string.format('%s("%s",%d)', fnName, encoded, salt)
    end)

    return encryptedScript
end
