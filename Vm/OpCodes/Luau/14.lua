-- SETTABLEKS: R(A)[K(AUX)] := R(B)
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local reg_b = _G.getReg(inst, "B")
    local aux = inst.AUX or 0
    local mappedIdx = _G.getMappedConstant(aux)
    return ("\tStack[%d][C[%d]] = Stack[%d]"):format(reg_a, mappedIdx, reg_b)
end
