-- SUBRK: R(A) := K(B) - R(C)
return function(inst, s, c, settings)
    local a = _G.getReg(inst,"A"); local bi = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
    return ("\tStack[%d] = C[%d] - Stack[%d]"):format(a, _G.getMappedConstant(bi), c2)
end
