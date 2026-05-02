-- NumberExpressions.lua
-- Replaces plain integer literals in generated VM code with
-- equivalent arithmetic expressions, e.g. 7 --> (3 + 4)
-- Runs as a post-process pass on the full generated tree string.
-- NumberExpressions.lua
local rng = math.random

local function makeExpr(n, depth)
    depth = depth or 0
    -- max nesting depth to avoid infinite recursion
    if depth > 2 then
        return tostring(n)
    end

    local strategy = rng(1, 8)

    if strategy == 1 then
        local a = rng(0, n)
        local b = n - a
        return ("(%s + %s)"):format(makeExpr(a, depth+1), makeExpr(b, depth+1))

    elseif strategy == 2 then
        local b = rng(1, 50)
        local a = n + b
        return ("(%s - %s)"):format(makeExpr(a, depth+1), makeExpr(b, depth+1))

    elseif strategy == 3 then
        local k = rng(2, 5)
        return ("(%s * %s / %s)"):format(makeExpr(n, depth+1), k, k)

    elseif strategy == 4 then
        local c = rng(1, 30)
        local total = n + c
        local a = rng(0, total)
        local b = total - a
        return ("((%s + %s) - %s)"):format(
            makeExpr(a, depth+1),
            makeExpr(b, depth+1),
            makeExpr(c, depth+1))

    elseif strategy == 5 then
        -- multiply by 1 disguised
        local k = rng(2, 9)
        return ("(%s * %d / %d)"):format(makeExpr(n, depth+1), k, k)

    elseif strategy == 6 then
        -- add and subtract same number
        local k = rng(1, 99)
        return ("(%s + %d - %d)"):format(makeExpr(n, depth+1), k, k)

    elseif strategy == 7 then
        -- double then halve
        return ("(%s * 2 / 2)"):format(makeExpr(n, depth+1))

    else
        -- nested add/sub chain
        local a = rng(1, 20)
        local b = rng(1, 20)
        local c = n + a - b
        -- make sure c is valid
        if c < 0 then return tostring(n) end
        return ("((%s + %s) - %s)"):format(
            makeExpr(c, depth+1),
            makeExpr(b, depth+1),
            makeExpr(a, depth+1))
    end
end

return function(code)
    -- replace array indices like p[3]
    code = code:gsub("%[(%d+)%]", function(num)
        local n = tonumber(num)
        if n == nil then return "[" .. num .. "]" end
        return "[" .. makeExpr(n) .. "]"
    end)

    -- replace pointer comparisons like pointer == 7
    code = code:gsub("(pointer%s*[=!<>]+%s*)(%d+)", function(op, num)
        local n = tonumber(num)
        if n == nil then return op .. num end
        return op .. makeExpr(n)
    end)

    -- replace pointer arithmetic like pointer + 1
    code = code:gsub("(pointer%s*[%+%-]%s*)(%d+)", function(op, num)
        local n = tonumber(num)
        if n == nil then return op .. num end
        return op .. makeExpr(n)
    end)

    -- replace plain number assignments like n = 5
    code = code:gsub("(%s*=%s*)(%d+)(%s*\n)", function(eq, num, nl)
        local n = tonumber(num)
        if n == nil then return eq .. num .. nl end
        return eq .. makeExpr(n) .. nl
    end)

    -- replace b[number] constant lookups
    code = code:gsub("b%[(%d+)%]", function(num)
        local n = tonumber(num)
        if n == nil then return "b[" .. num .. "]" end
        return "b[" .. makeExpr(n) .. "]"
    end)

    return code
end
