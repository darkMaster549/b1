-- NumberExpressions.lua
-- Replaces plain integer literals in generated VM code with
-- equivalent arithmetic expressions, e.g. 7 --> (3 + 4)
-- Runs as a post-process pass on the full generated tree string.

local rng = math.random

local function makeExpr(n)
	local strategy = rng(1, 4)

	if strategy == 1 then
		local a = rng(0, n)
		local b = n - a
		return ("(%d + %d)"):format(a, b)

	elseif strategy == 2 then
		local b = rng(1, 50)
		local a = n + b
		return ("(%d - %d)"):format(a, b)

	elseif strategy == 3 then
		local k = rng(2, 5)
		return ("(%d * %d / %d)"):format(n, k, k)

	else
		local c = rng(1, 30)
		local total = n + c
		local a = rng(0, total)
		local b = total - a
		return ("((%d + %d) - %d)"):format(a, b, c)
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

	return code
end
