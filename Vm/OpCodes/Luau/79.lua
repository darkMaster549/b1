-- JUMPXEQKS: jump if R(A) == string K(AUX)
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local d = inst.D or inst.Bx or 0
    local aux = inst.AUX or 0
    local mappedIdx = _G.getMappedConstant(aux % 0x1000000)
    return ([=[
    if Stack[%d] == C[%d] then
        pointer = pointer + %d
    end
    ]=]):format(reg_a, mappedIdx, d)
end
