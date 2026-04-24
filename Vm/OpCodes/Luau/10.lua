-- GETIMPORT: R(A) := global import path from constant K(D)
return function(inst, shiftAmount, constant, settings)
    local d = inst.D or inst.Bx or 0
    local mappedIdx = _G.getMappedConstant(d)
    return ("\tStack[:A:] = Env[C[%d]]"):format(mappedIdx)
end
