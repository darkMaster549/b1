-- JUMPXEQKNIL: jump if R(A) == nil (AUX high bit = NOT flag)
return function(inst, shiftAmount, constant, settings)
    local reg_a = _G.getReg(inst, "A")
    local d = inst.D or inst.Bx or 0
    local aux = inst.AUX or 0
    local notFlag = aux >= 0x80000000
    local cmp = notFlag and "~= nil" or "== nil"
    return ([=[
    if Stack[%d] %s then
        pointer = pointer + %d
    end
    ]=]):format(reg_a, cmp, d)
end
