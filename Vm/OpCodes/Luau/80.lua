-- IDIV: R(A) := floor(R(B) / R(C))
return function(inst, s, c, settings)
    local a = _G.getReg(inst,"A"); local b = _G.getReg(inst,"B"); local c2 = _G.getReg(inst,"C")
    return ("\tStack[%d] = math.floor(Stack[%d] / Stack[%d])"):format(a,b,c2)
end
