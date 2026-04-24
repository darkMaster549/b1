-- FORGLOOP_NEXT: pairs-style for step (next())
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    return ([=[
    local _k, _v = next(Stack[%d], Stack[%d])
    if _k ~= nil then
        Stack[%d] = _k
        Stack[%d] = _v
        pointer = pointer + %d
    end
    ]=]):format(reg_a+1, reg_a+2, reg_a+2, reg_a+3, d)
end
