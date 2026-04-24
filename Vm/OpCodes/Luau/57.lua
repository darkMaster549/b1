-- FORGLOOP: generic for loop step
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    local aux = instruction.AUX or 1
    return ([=[
    local _result = {Stack[%d](Stack[%d], Stack[%d])}
    for i = 1, %d do
        Stack[%d + i] = _result[i]
    end
    if Stack[%d] ~= nil then
        Stack[%d] = Stack[%d]
        pointer = pointer + %d
    end
    ]=]):format(reg_a, reg_a+1, reg_a+2, aux, reg_a+2, reg_a+3, reg_a+2, reg_a+3, d)
end
