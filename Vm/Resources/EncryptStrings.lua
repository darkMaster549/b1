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

local BASE91 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_`{|}~"

local function base91Encode(input, salt)
    if not input or #input == 0 then return "~" end
    local src = {}
    for i = 1, #input do src[i] = string.byte(input, i) end
    local transformed = {}
    for i = 1, #src do
        local b = (src[i] + (i % 97) + (salt % 13)) % 256
        b = nibbleSwap(b)
        local prev = (i > 1) and transformed[i-1] or (0x5A + salt % 7)
        transformed[i] = xorBit(b, prev % 256)
    end
    local out = {}
    local v, b = 0, 1
    for i = 1, #transformed do
        v = v + transformed[i] * b
        b = b * 256
        if b > 8191 then
            local val = v % 8192
            if val > 88 then
                out[#out+1] = BASE91:sub((val%91)+1, (val%91)+1)
                out[#out+1] = BASE91:sub(math.floor(val/91)+1, math.floor(val/91)+1)
                v = math.floor(v / 8192)
                b = math.floor(b / 8192)
            else
                val = v % 16384
                out[#out+1] = BASE91:sub((val%91)+1, (val%91)+1)
                out[#out+1] = BASE91:sub(math.floor(val/91)+1, math.floor(val/91)+1)
                v = math.floor(v / 16384)
                b = math.floor(b / 16384)
            end
        end
    end
    if b > 1 then
        out[#out+1] = BASE91:sub((v%91)+1, (v%91)+1)
        if b > 90 or v > 90 then
            out[#out+1] = BASE91:sub(math.floor(v/91)+1, math.floor(v/91)+1)
        end
    end
    local result = table.concat(out)
    return (result == "" and "~" or result)
end

return function(scriptSource, wantsFunction)
    if wantsFunction == true then
        return function(str, salt)
            local encoded = base91Encode(str, salt)
            return encoded, encoded
        end
    end

    local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
        local salt = math.random(100, 9999)
        local encoded = base91Encode(match, salt)
        encoded = encoded:gsub("\\", "\\\\"):gsub('"', '\\"')
        return string.format('__decrypt_fn("%s",%d)', encoded, salt)
    end)

    return encryptedScript
end
