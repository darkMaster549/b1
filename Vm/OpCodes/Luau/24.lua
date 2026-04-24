-- JUMPIFNOT: if not R(A) then pc += D
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local d = inst.D or inst.Bx or 0
    return ([=[
    if not Stack[%d] then
        pointer = pointer + %d
    end
    ]=]):format(reg_a, d)
end
