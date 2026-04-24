-- LOADK: R(A) := K(D)
return function(inst, shiftAmount, constant, settings)
    local d = inst.D or inst.Bx or 0
    local mappedIdx = _G.getMappedConstant(d)
    return ("\tStack[:A:] = C[%d]"):format(mappedIdx)
end
