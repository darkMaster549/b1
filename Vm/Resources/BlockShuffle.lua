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

    local s = math.random(1, 12)

    if s == 1 then
        local a = math.random(0, n)
        local b = n - a
        return ("(%d + %d)"):format(a, b)

    elseif s == 2 then
        local b = math.random(1, 50)
        local a = n + b
        return ("(%d - %d)"):format(a, b)

    elseif s == 3 then
        local k = math.random(2, 5)
        return ("(%d * %d / %d)"):format(n, k, k)

    elseif s == 4 then
        local c = math.random(1, 30)
        local total = n + c
        local a = math.random(0, total)
        local b = total - a
        return ("((%d + %d) - %d)"):format(a, b, c)

    elseif s == 5 then
        local k = math.random(1, 99)
        return ("(%d + %d - %d)"):format(n, k, k)

    elseif s == 6 then
        return ("(%d * 2 / 2)"):format(n)

    elseif s == 7 then
        return ("B(%s)"):format(makeExpr(n, depth+1))

    elseif s == 8 then
        return ("A(%s)"):format(makeExpr(n, depth+1))

    elseif s == 9 then
        return ("E(%d, %s)"):format(0, makeExpr(n, depth+1))

    elseif s == 10 then
        local k = math.random(n+1, n+99)
        return ("F(%d, %s)"):format(k, makeExpr(n, depth+1))

    elseif s == 11 then
        return ("(true and %s or 0)"):format(makeExpr(n, depth+1))

    else
        return ("(false and 0 or %s)"):format(makeExpr(n, depth+1))
    end
end

return function(opcodeMap, numExprEnabled)
    nameGen.reset()

    local blocks = {}
    for ptr, code in pairs(opcodeMap) do
        blocks[#blocks + 1] = {
            ptr  = ptr,
            code = code,
        }
    end

    fisherYates(blocks)

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
