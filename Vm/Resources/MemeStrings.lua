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

return function(count)
    count = count or 3
    local out = {}
    for i = 1, count do
        local m = memes[math.random(#memes)]
        out[i] = ('local _m'..i..' = "'..m..'"')
    end
    return table.concat(out, "\n")
end
