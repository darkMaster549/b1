-- SETTABLEN: R(A)[C] := R(B)
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local reg_b = _G.getReg(inst, "B")
    local reg_c = _G.getReg(inst, "C")
    return ("\tStack[%d][%d] = Stack[%d]"):format(reg_a, reg_c, reg_b)
end
