-- FORGPREP: prepare generic for, jump D
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    return ("pointer = pointer + %d"):format(d)
end
