-- BlockShuffle.lua
local nameGen = require("Resources.NameGenerator")

local function fisherYates(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function makeExpr(n, depth)
    depth = depth or 0
    if depth > 2 then return tostring(n) end

    local s = math.random(1, 6)

    if s == 1 then
        local a = math.random(0, n)
        local b = n - a
        return ("(%s + %s)"):format(makeExpr(a, depth+1), makeExpr(b, depth+1))

    elseif s == 2 then
        local b = math.random(1, 50)
        local a = n + b
        return ("(%s - %s)"):format(makeExpr(a, depth+1), makeExpr(b, depth+1))

    elseif s == 3 then
        local k = math.random(2, 5)
        return ("(%s * %d / %d)"):format(makeExpr(n, depth+1), k, k)

    elseif s == 4 then
        local k = math.random(1, 99)
        return ("(%s + %d - %d)"):format(makeExpr(n, depth+1), k, k)

    elseif s == 5 then
        return ("(%s * 2 / 2)"):format(makeExpr(n, depth+1))

    else
        local a = math.random(1, 20)
        local b = math.random(1, 20)
        local c = n + a - b
        if c < 0 then return tostring(n) end
        return ("((%s + %s) - %s)"):format(
            makeExpr(c, depth+1),
            makeExpr(b, depth+1),
            makeExpr(a, depth+1))
    end
end

return function(opcodeMap, numExprEnabled)
    nameGen.reset()

    -- collect blocks
    local blocks = {}
    for ptr, code in pairs(opcodeMap) do
        blocks[#blocks + 1] = {
            ptr  = ptr,
            code = code,
        }
    end

    -- shuffle physical order
    fisherYates(blocks)

    -- rebuild if/elseif chain
    -- if numExprEnabled, disguise pointer values too
    local chain = {}
    local isFirst = true
    for _, b in ipairs(blocks) do
        local ptrStr
        if numExprEnabled then
            ptrStr = makeExpr(b.ptr)
        else
            ptrStr = tostring(b.ptr)
        end

        chain[#chain + 1] = ("%s pointer == %s then\n%s"):format(
            isFirst and "if" or "elseif",
            ptrStr,
            b.code
        )
        isFirst = false
    end
    chain[#chain + 1] = "end"

    return table.concat(chain, "\n")
end
