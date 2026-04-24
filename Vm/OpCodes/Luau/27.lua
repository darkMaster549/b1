-- JUMPIFLT: if R(A) < R(AUX) then pc += D
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local d = inst.D or inst.Bx or 0
    local aux = inst.AUX or 0
    return ([=[
    if Stack[%d] < Stack[%d] then
        pointer = pointer + %d
    end
    ]=]):format(reg_a, aux, d)
end
