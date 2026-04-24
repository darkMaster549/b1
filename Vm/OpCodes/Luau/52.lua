-- DUPTABLE: R(A) := copy of template table K(D)
return function(inst, shiftAmount, constant, settings)
    local d = inst.D or inst.Bx or 0
    local mappedIdx = _G.getMappedConstant(d)
    -- shallow copy the template
    return ([=[
    do
        local _tpl = C[%d]
        local _t = {}
        if type(_tpl) == "table" then
            for k,v in pairs(_tpl) do _t[k] = v end
        end
        Stack[:A:] = _t
    end
    ]=]):format(mappedIdx)
end
