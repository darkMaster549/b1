-- FORGPREP_NEXT: prepare pairs-style for
return function(instruction, shiftAmount, constant, settings)
    local d = instruction.D or instruction.Bx or 0
    return ("pointer = pointer + %d"):format(d)
end
