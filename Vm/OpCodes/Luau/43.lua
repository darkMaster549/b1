-- AND: R(A) := R(B) and R(C)
return function(inst, s, c, settings)
    local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
    return ("\tStack[%d] = Stack[%d] and Stack[%d]"):format(a,b,c2)
end
