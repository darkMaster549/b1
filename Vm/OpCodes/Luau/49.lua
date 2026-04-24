-- MINUS: R(A) := -R(B)
return function(instruction, shiftAmount, constant, settings)
    local a = _G.getReg(instruction,"A"); local b = _G.getReg(instruction,"B")
    return ("\tStack[%d] = -Stack[%d]"):format(a,b)
end
