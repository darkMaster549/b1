return [=[
local __BASE91="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_`{|}~"
local __b91map={}
for __i=1,#__BASE91 do __b91map[string.byte(__BASE91,__i)+1]=__i-1 end

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

local function __b91Decode(__encoded,__salt)
    if not __encoded or __encoded=="~" then return "" end
    local __B={}
    for __i=1,#__encoded do
        __B[#__B+1]=__b91map[string.byte(__encoded,__i)+1] or 0
    end
    local __bytes={}
    local __v,__b,__d=0,1,-1
    for __i=1,#__B do
        if __d<0 then
            __d=__B[__i]
        else
            __d=__d+__B[__i]*91
            local __val=__d%8192
            if __val>88 then
                __v=__v+__val*__b
                __b=__b*8192
            else
                __val=__d%16384
                __v=__v+__val*__b
                __b=__b*16384
            end
            while __b>255 do
                __bytes[#__bytes+1]=__v%256
                __v=math.floor(__v/256)
                __b=math.floor(__b/256)
            end
            __d=-1
        end
    end
    if __d>-1 then __bytes[#__bytes+1]=(__v+__d*__b)%256 end
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

local function __decrypt_fn(__encoded,__salt)
    return __b91Decode(__encoded,__salt)
end

local function __unpack_consts(__blob,__cShift)
    __blob=__blob:gsub("^HEBREW!","")
    local __raw=__b91Decode(__blob,0)
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
        local __dec=__b91Decode(__encs[__i],__salt)
        if __dec and #__dec>0 then
            local __len=#__dec
            local __lastByte=__dec:byte(__len)
            if __lastByte==11 then
                local __raw2=__dec:sub(1,__len-1)
                local __t={}
                for __j=1,#__raw2 do
                    __t[__j]=string.char((__raw2:byte(__j)+__perShift)%256)
                end
                __out[__i]=tonumber(table.concat(__t))
            elseif __lastByte==7 then
                __out[__i]=__dec:byte(1)==116
            elseif __lastByte==6 then
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
