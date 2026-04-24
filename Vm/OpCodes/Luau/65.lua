-- LOADKX: R(A) := K(AUX)
return function(inst, shiftAmount, constant, settings)
    local aux = inst.AUX or 0
    local mappedIdx = _G.getMappedConstant(aux)
    return ("\tStack[:A:] = C[%d]"):format(mappedIdx)
end
