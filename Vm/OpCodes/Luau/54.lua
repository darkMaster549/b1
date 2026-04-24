-- FORNPREP: prepare numeric for; R(A)=init, R(A+1)=limit, R(A+2)=step
return function(instruction, shiftAmount, constant, settings)
    local reg_a = _G.getReg(instruction, "A")
    local d = instruction.D or instruction.Bx or 0
    return ([=[
    local _init  = tonumber(Stack[%d])
    local _limit = tonumber(Stack[%d])
    local _step  = tonumber(Stack[%d])
    Stack[%d] = _init - _step
    Stack[%d] = _limit
    Stack[%d] = _step
    pointer = pointer + %d
    ]=]):format(reg_a, reg_a+1, reg_a+2, reg_a, reg_a+1, reg_a+2, d)
end
