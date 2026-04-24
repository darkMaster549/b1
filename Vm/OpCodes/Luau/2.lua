-- LOADNIL: R(A) := nil
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    return ("\tStack[%d] = nil"):format(reg_a)
end
