-- JUMPXEQKB: jump if R(A) == bool constant
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local d = inst.D or inst.Bx or 0
    local aux = inst.AUX or 0
    local notFlag = (aux >= 0x80000000)
    local bval = ((aux % 2) == 1) and "true" or "false"
    local op = notFlag and "~=" or "=="
    return ([=[
    if Stack[%d] %s %s then
        pointer = pointer + %d
    end
    ]=]):format(reg_a, op, bval, d)
end
