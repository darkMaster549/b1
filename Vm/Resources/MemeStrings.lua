--[[ I'm so bored and don't know what to add Layer and I'm also thinking of deserializer and studying 
other's techniques..
i just add this to ragebait the skidders :D
]]

local memes = {
    "Stop skidding bro",
    "use luraph!",
    "nooooo!",
    "freaking",
    "bro really tried to deobf this",
    "skill issue",
    "go outside",
    "this wont help u",
    "ur so cooked",
    "just give up",
    "W SPEED!",
    "KING NASiR",
}

local function toEscape(s)
    local out = {}
    for i = 1, #s do
        out[i] = string.format("\\%d", s:byte(i))
    end
    return table.concat(out)
end

return function(count)
    count = count or 3
    local out = {}
    for i = 1, count do
        local m = memes[math.random(#memes)]
        local chance = math.random(1, 3)

        if chance == 1 then
            -- encode as \xx\xx\xx escape sequence
            out[i] = ('local _m'..i..' = "'..toEscape(m)..'"')
        else
            out[i] = ('local _m'..i..' = "'..m..'"')
        end
    end
    return table.concat(out, "\n")
end
