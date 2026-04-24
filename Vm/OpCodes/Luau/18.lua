-- NAMECALL: R(A+1) := R(B); R(A) := R(B)[K(AUX)]
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local reg_b = _G.getReg(inst, "B")
    local aux = inst.AUX or 0
    local mappedIdx = _G.getMappedConstant(aux)
    return ([=[
    Stack[%d] = Stack[%d]
    Stack[%d] = Stack[%d][C[%d]]
    ]=]):format(reg_a + 1, reg_b, reg_a, reg_b, mappedIdx)
end
