-- LOADN: R(A) := D (signed integer literal)
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    return ("\tStack[%d] = %d"):format(reg_a, d)
end
