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

local function base91Encode(input, salt)
    if not input or #input == 0 then return "~" end
    local transformed = {}
    for i = 1, #input do
        local b = (string.byte(input, i) + (i % 97) + (salt % 13)) % 256
        b = nibbleSwap(b)
        local prev = (i > 1) and transformed[i-1] or (0x5A + salt % 7)
        transformed[i] = xorBit(b, prev % 256)
    end
    local out = {}
    local b91, n = 0, 0
    for i = 1, #transformed do
        b91 = b91 + transformed[i] * (2 ^ n)
        n = n + 8
        if n > 13 then
            local val = b91 % 8192
            if val > 88 then
                b91 = math.floor(b91 / 8192)
                n = n - 13
            else
                val = b91 % 16384
                b91 = math.floor(b91 / 16384)
                n = n - 14
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

local function encodeConstant(input, salt, idx)
    if not input or #input == 0 then return "~" end
    local sbox = makeSbox(salt)
    local out  = {}
    local prev = salt % 256
    for i = 1, #input do
        local b   = input:byte(i)
        local key = (salt * 31 + idx * 17 + i * 7) % 256
        b = xorBit(b, key)
        b = sbox[b]
        b = xorBit(b, prev)
        prev = b
        -- encode this single byte via base91
        local tmp = {}
        local acc, bits = b, 8
        if bits > 13 then
            local val = acc % 8192
            if val > 88 then
                acc = math.floor(acc / 8192); bits = bits - 13
            else
                val = acc % 16384
                acc = math.floor(acc / 16384); bits = bits - 14
            end
            tmp[#tmp+1] = BASE91:sub((val % 91) + 1, (val % 91) + 1)
            tmp[#tmp+1] = BASE91:sub(math.floor(val / 91) + 1, math.floor(val / 91) + 1)
        end
        if bits > 0 then
            tmp[#tmp+1] = BASE91:sub((acc % 91) + 1, (acc % 91) + 1)
            if bits > 7 or acc > 90 then
                tmp[#tmp+1] = BASE91:sub(math.floor(acc / 91) + 1, math.floor(acc / 91) + 1)
            end
        end
        out[i] = table.concat(tmp)
    end
    -- pack all bytes properly through base91
    -- redo: encode full transformed bytes as one base91 stream
    local bytes = {}
    local sbox2 = makeSbox(salt)
    local prev2 = salt % 256
    for i = 1, #input do
        local b2  = input:byte(i)
        local key = (salt * 31 + idx * 17 + i * 7) % 256
        b2 = xorBit(b2, key)
        b2 = sbox2[b2]
        b2 = xorBit(b2, prev2)
        prev2 = b2
        bytes[i] = b2
    end
    local out2 = {}
    local b91, n2 = 0, 0
    for i = 1, #bytes do
        b91 = b91 + bytes[i] * (2 ^ n2)
        n2 = n2 + 8
        if n2 > 13 then
            local val = b91 % 8192
            if val > 88 then
                b91 = math.floor(b91 / 8192); n2 = n2 - 13
            else
                val = b91 % 16384
                b91 = math.floor(b91 / 16384); n2 = n2 - 14
            end
            out2[#out2+1] = BASE91:sub((val % 91) + 1, (val % 91) + 1)
            out2[#out2+1] = BASE91:sub(math.floor(val / 91) + 1, math.floor(val / 91) + 1)
        end
    end
    if n2 > 0 then
        out2[#out2+1] = BASE91:sub((b91 % 91) + 1, (b91 % 91) + 1)
        if n2 > 7 or b91 > 90 then
            out2[#out2+1] = BASE91:sub(math.floor(b91 / 91) + 1, math.floor(b91 / 91) + 1)
        end
    end
    local result = table.concat(out2)
    return (result == "" and "~" or result)
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
