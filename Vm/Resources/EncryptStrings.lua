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

local function base10Encode(input, salt)
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
    for i = 1, #transformed do
        out[i] = string.format("%03d", transformed[i])
    end
    local result = table.concat(out)
    return (result == "" and "~" or result)
end

return function(scriptSource, wantsFunction)
    if wantsFunction == true then
        return function(str, salt)
            local encoded = base10Encode(str, salt)
            return encoded, encoded
        end
    end

    local encryptedScript = scriptSource:gsub('"(.-)"', function(match)
        local salt = math.random(100, 9999)
        local encoded = base10Encode(match, salt)
        encoded = encoded:gsub("\\", "\\\\"):gsub('"', '\\"')
        return string.format('__decrypt_fn("%s",%d)', encoded, salt)
    end)

    return encryptedScript
end
