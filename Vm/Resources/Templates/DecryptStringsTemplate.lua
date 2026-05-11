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

local function __makeSbox(__salt)
    local __s={}
    for __i=0,255 do __s[__i]=__i end
    local __r=__salt
    for __i=255,1,-1 do
        __r=(__r*1664525+1013904223)%4294967296
        local __j=__r%(__i+1)
        __s[__i],__s[__j]=__s[__j],__s[__i]
    end
    return __s
end

local function __makeInvSbox(__sbox)
    local __inv={}
    for __i=0,255 do __inv[__sbox[__i]]=__i end
    return __inv
end

local function __decodeConstant(__encoded,__salt,__idx)
    if not __encoded or __encoded=="~" then return "" end
    local __bytes={}
    for __i=1,#__encoded,3 do
        __bytes[#__bytes+1]=tonumber(__encoded:sub(__i,__i+2)) or 0
    end
    local __sbox=__makeSbox(__salt)
    local __inv=__makeInvSbox(__sbox)
    local __out={}
    local __prev=__salt%256
    for __i=1,#__bytes do
        local __b=__bytes[__i]
        local __unchained=__xorBit(__b,__prev)
        __prev=__b
        local __unsub=__inv[__unchained]
        local __key=(__salt*31+__idx*17+__i*7)%256
        __out[__i]=string.char(__xorBit(__unsub,__key))
    end
    return table.concat(__out)
end

local function __UNPACK_FN_NAME__(__blob,__cShift)
    local __afterPrefix=__blob:gsub("^%u+!","")
    local __outerSalt=tonumber(__afterPrefix:sub(1,4)) or 0
    local __data=__afterPrefix:sub(5)
    local __raw=__b10Decode(__data,__outerSalt)
    if not __raw or #__raw==0 then return {} end
    local __lines={}
    for __line in (__raw.."|"):gmatch("([^|]*)%|") do
        __lines[#__lines+1]=__line
    end
    local __total=tonumber(__lines[1]) or 0
    local __encs,__salts,__idxs={},{},{}
    for __i=1,__total do
        __encs[__i] =__lines[1+__i] or "~"
        __salts[__i]=__lines[1+__total+__i] or "0"
        __idxs[__i] =__lines[1+__total*2+__i] or tostring(__i)
    end
    local __out={}
    for __i=1,__total do
        local __salt=tonumber(__salts[__i]) or 0
        local __idx=tonumber(__idxs[__i]) or __i
        local __dec=__decodeConstant(__encs[__i],__salt,__idx)
        if __dec and #__dec>0 then
            local __len=#__dec
            local __last=__dec:byte(__len)
            if __last==11 then
                __out[__i]=tonumber(__dec:sub(1,__len-1))
            elseif __last==7 then
                __out[__i]=__dec:byte(1)==116
            elseif __last==6 then
                __out[__i]=nil
            else
                __out[__i]=__dec:sub(1,__len)
            end
        end
    end
    return __out
end
]=]
