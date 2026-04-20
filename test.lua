-- a Scripts you can Obfuscate --
-- for test --
math.randomseed(os.time())

local player = {
    name = "Adventurer",
    hp = 100,
    max_hp = 100,
    attack = 15,
    defense = 8,
    inventory = {}
}

local monsters = {
    {name = "Goblin", hp = 30, attack = 8, defense = 3, xp = 50},
    {name = "Orc", hp = 55, attack = 12, defense = 6, xp = 100},
    {name = "Troll", hp = 80, attack = 15, defense = 10, xp = 150},
    {name = "Dark Knight", hp = 70, attack = 18, defense = 12, xp = 200}
}

local function calculate_damage(attacker, defender)
    local base_damage = math.max(1, attacker.attack - defender.defense)
    return math.random(base_damage, base_damage + 5)
end

local function battle(monster)
    print("\n A wild " .. monster.name .. " appears! ")
    print(monster.name .. ": " .. monster.hp .. " HP | Attack: " .. monster.attack .. " | Defense: " .. monster.defense)
    
    local monster_hp = monster.hp
    local player_hp = player.hp
    
    while player_hp > 0 and monster_hp > 0 do
        -- Player turn
        local player_damage = calculate_damage(player, monster)
        monster_hp = monster_hp - player_damage
        print("You hit the " .. monster.name .. " for " .. player_damage .. " damage! (" .. math.max(0, monster_hp) .. " HP left)")
        
        if monster_hp <= 0 then
            print("\n Victory! You defeated the " .. monster.name .. "! ")
            print("Gained " .. monster.xp .. " XP!")
            return true
        end
        
        -- Monster turn
        local monster_damage = calculate_damage(monster, player)
        player_hp = player_hp - monster_damage
        print(monster.name .. " hits you for " .. monster_damage .. " damage! (" .. math.max(0, player_hp) .. " HP left)")
    end
    
    if player_hp <= 0 then
        print("\n You have been defeated by the " .. monster.name .. "... ")
        return false
    end
end

local function explore_dungeon()
    print("\n Entering the Dungeon... ")
    print("Your HP: " .. player.hp .. "/" .. player.max_hp)
    
    for floor = 1, 3 do
        print("\n--- Floor " .. floor .. " ---")
        
        local monster_choice = math.random(1, #monsters)
        local monster = monsters[monster_choice]
        
        local victory = battle(monster)
        
        if not victory then
            print("\nGame Over - You reached Floor " .. floor)
            return false
        end
        
        
        local heal = math.random(10, 20)
        player.hp = math.min(player.max_hp, player.hp + heal)
        print("You found a healing spring! Restored " .. heal .. " HP.")
    end
    
    print("\n🎉 Congratulations! You cleared the dungeon!")
    return true
end

-- Run the game
print("=== DUNGEON CRAWLER ===")
explore_dungeon()
print("\nFinal Stats:")
print("HP: " .. player.hp .. "/" .. player.max_hp)
