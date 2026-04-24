-- JUMPX: pc += E (extended jump)
return function(inst, shiftAmount, constant, settings)
    local e = inst.E or inst.sBx or 0
    return ("pointer = pointer + %d"):format(e)
end
