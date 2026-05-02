return [=[
local function __xorBit(__a,__b)
    if bit32 then return bit32.bxor(__a,__b) end
    if bit then return bit.bxor(__a,__b) end
    local __r,__p=0,1
    while __a>0 or __b>0 do
        if __a%2~=__b%2 then __r=__r+__p end
        __a,__b,__p=math.floor(__a/2),math.floor(__b/2),__p*2
    end
    return __r
end

local function __nibbleSwap(__b)
    return((__b%16)*16+math.floor(__b/16))%256
end

local function __b10Decode(__encoded,__salt)
    if not __encoded or __encoded=="~" then return "" end
    local __bytes={}
    for __i=1,#__encoded,3 do
        __bytes[#__bytes+1]=tonumber(__encoded:sub(__i,__i+2)) or 0
    end
    local __out={}
    for __i=1,#__bytes do
        local __byte=__bytes[__i]
        local __prev=((__i>1) and __bytes[__i-1] or (0x5A+__salt%7))%256
        __byte=__xorBit(__byte,__prev)
        __byte=__nibbleSwap(__byte)
        __byte=(__byte-(__i%97)-(__salt%13)+512)%256
        __out[__i]=string.char(__byte)
    end
    return table.concat(__out)
end

local __DECRYPT_FN_NAME__=function(__encoded,__salt)
    return __b10Decode(__encoded,__salt)
end

local function __UNPACK_FN_NAME__(__blob,__cShift)
    __blob=__blob:gsub("^%u+!","")
    local __raw=__b10Decode(__blob,0)
    if not __raw or #__raw==0 then return {} end
    local __lines={}
    for __line in (__raw.."\n"):gmatch("([^\n]*)\n") do
        __lines[#__lines+1]=__line
    end
    local __total=tonumber(__lines[1]) or 0
    local __encs,__salts,__shifts={},{},{}
    for __i=1,__total do
        __encs[__i]  =__lines[1+__i] or "~"
        __salts[__i] =__lines[1+__total+__i] or "0"
        __shifts[__i]=__lines[1+__total*2+__i] or "1"
    end
    local __out={}
    for __i=1,__total do
        local __perShift=tonumber(__shifts[__i]) or __cShift
        local __salt=tonumber(__salts[__i]) or 0
        local __dec=__b10Decode(__encs[__i],__salt)
        if __dec and #__dec>0 then
            local __len=#__dec
            local __last=__dec:byte(__len)
            if __last==11 then
                local __r=__dec:sub(1,__len-1)
                local __t={}
                for __j=1,#__r do
                    __t[__j]=string.char((__r:byte(__j)+__perShift)%256)
                end
                __out[__i]=tonumber(table.concat(__t))
            elseif __last==7 then
                __out[__i]=__dec:byte(1)==116
            elseif __last==6 then
                __out[__i]=nil
            else
                local __t={}
                for __j=1,__len do
                    __t[__j]=string.char((__dec:byte(__j)+__perShift)%256)
                end
                __out[__i]=table.concat(__t)
            end
        end
    end
    return __out
end
]=]
