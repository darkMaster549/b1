-- ORK: R(A) := R(B) or K(C)
return function(inst, s, c, settings)
    local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local ci = _G.getReg(inst,"C")
    return ("\tStack[%d] = Stack[%d] or C[%d]"):format(a, b, _G.getMappedConstant(ci))
end
