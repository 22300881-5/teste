local MonsterFolder = workspace:WaitForChild("Monster")

local Data = {
    ["Carrot"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-4083, 57, -1.7),
            NPC = "Beast Pirate [Lv. 2250]"
        },
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-3973, 98, -351),
            NPC = "Beast Swordman [Lv. 2300]"
        },
    },
    ["Rusted Scrap"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-4568, 135, -879),
            NPC = "Powerful Beast Pirate [Lv. 2450]"
        },
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-4568, 135, -879),
            NPC = "Bandit Beast Pirate [Lv. 2400]"
        },
    },
    ["Samurai's Bandage"] = {
        {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(-5370, 134, 39),
            NPC = "Kitsune Samurai [Lv. 2650]"
        },
         {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(-5196, 85, -963),
            NPC = "Violet Samurai [Lv. 2500]"
        },
    },
    ["Pile of Bones"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-6290, 57, 6276),
            NPC = "Skull Pirate [Lv. 3050]"
        },
    },
    ["Essence of Fire"] = {
        {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(2071,14,1163),
            NPC = "Flame User [Lv. 3200]"
        },
    },
    ["Magma Crystal"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(2071,14,1163),
            NPC = "The Volcano [Lv. 3325]"
        },
    },
    ["Ice Crystal"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-686, 56, -2879),
            NPC = "Azlan [Lv. 3300]"
        },
    },
    ["Lost Ruby"] = {
        {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(2071,14,1163),
            NPC = "Anubis [Lv. 3150]"
        },
    },

    ["Dragon's Orb"] = {
        {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(-5944, 98, 7163),
            NPC = "Elite Skeleton [Lv. 3100]"
        },
    },
    ["Lucidus's Totem"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-9983, 130, 362),
            NPC = "Vice Admiral [Lv. 3500]"
        },
        {
            Path = MonsterFolder.Boss,
            Location = CFrame.new(-10717, 83, 991),
            NPC = "Hefty [Lv. 3550]"
        },
    },
}

return Data
