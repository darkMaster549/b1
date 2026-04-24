-- LOADB: R(A) := (bool)B; if C then pc++
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local reg_b = _G.getReg(instruction, "B")
    local reg_c = _G.getReg(instruction, "C")
    local val = reg_b ~= 0 and "true" or "false"
    if reg_c ~= 0 then
        return ("\tStack[%d] = %s\n\tpointer = pointer + 1"):format(reg_a, val)
    else
        return ("\tStack[%d] = %s"):format(reg_a, val)
    end
end
