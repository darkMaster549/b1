local rng = math.random

local function makeExpr(n, depth)
    depth = depth or 0
    if depth > 2 then return tostring(n) end

    local s = rng(1, 12)

    if s == 1 then
        local a = rng(0, n)
        local b = n - a
        return ("(%d + %d)"):format(a, b)

    elseif s == 2 then
        local b = rng(1, 50)
        local a = n + b
        return ("(%d - %d)"):format(a, b)

    elseif s == 3 then
        local k = rng(2, 5)
        return ("(%d * %d / %d)"):format(n, k, k)

    elseif s == 4 then
        local c = rng(1, 30)
        local total = n + c
        local a = rng(0, total)
        local b = total - a
        return ("((%d + %d) - %d)"):format(a, b, c)

    elseif s == 5 then
        local k = rng(1, 99)
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
        local k = rng(n+1, n+99)
        return ("F(%d, %s)"):format(k, makeExpr(n, depth+1))

    elseif s == 11 then
        return ("(true and %s or 0)"):format(makeExpr(n, depth+1))

    else
        return ("(false and 0 or %s)"):format(makeExpr(n, depth+1))
    end
end

return function(code)
    code = code:gsub("%[(%d+)%]", function(num)
        local n = tonumber(num)
        if n == nil then return "[" .. num .. "]" end
        return "[" .. makeExpr(n) .. "]"
    end)

    code = code:gsub("(pointer%s*[=!<>]+%s*)(%d+)", function(op, num)
        local n = tonumber(num)
        if n == nil then return op .. num end
        return op .. makeExpr(n)
    end)

    code = code:gsub("(pointer%s*[%+%-]%s*)(%d+)", function(op, num)
        local n = tonumber(num)
        if n == nil then return op .. num end
        return op .. makeExpr(n)
    end)

    code = code:gsub("(%s*=%s*)(%d+)(%s*\n)", function(eq, num, nl)
        local n = tonumber(num)
        if n == nil then return eq .. num .. nl end
        return eq .. makeExpr(n) .. nl
    end)

    code = code:gsub("b%[(%d+)%]", function(num)
        local n = tonumber(num)
        if n == nil then return "b[" .. num .. "]" end
        return "b[" .. makeExpr(n) .. "]"
    end)

    return code
end
