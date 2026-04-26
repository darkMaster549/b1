-- BlockShuffle.lua
-- Shuffles physical order of elseif blocks only, no function wrapping
-- Function wrapping breaks local variable scope across jumps

local nameGen = require("Resources.NameGenerator")

local function fisherYates(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
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

	-- shuffle physical order of the elseif chain
	fisherYates(blocks)

	-- rebuild if/elseif in shuffled order
	-- pointer values stay real so all jumps (JMP, FORPREP, FORLOOP etc) still work
	local chain  = {}
	local isFirst = true
	for _, b in ipairs(blocks) do
		chain[#chain + 1] = ("%s pointer == %d then\n%s"):format(
			isFirst and "if" or "elseif",
			b.ptr,
			b.code
		)
		isFirst = false
	end
	chain[#chain + 1] = "end"

	return table.concat(chain, "\n")
end
