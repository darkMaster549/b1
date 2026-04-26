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

local varNames = {"a","b","c","d","e","f","g","h","k","p","q","r"}

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
        local vname = varNames[math.random(#varNames)] .. tostring(math.random(100,999))
        out[i] = ('local '..vname..' = "'..toEscape(m)..'"')
    end
    return table.concat(out, "\n")
end
