-- FORGLOOP_INEXT: ipairs-style for step
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    return ([=[
    local _idx = Stack[%d] + 1
    local _val = Stack[%d][_idx]
    if _val ~= nil then
        Stack[%d] = _idx
        Stack[%d] = _val
        pointer = pointer + %d
    end
    ]=]):format(reg_a+2, reg_a+1, reg_a+2, reg_a+3, d)
end
