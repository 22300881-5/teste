local NPCs = {
    ["Sea 1"] = {
    --// Starter Island
        ["Soldier [Lv. 1]"] = {
            Location = CFrame.new(-1893,49,-4582),
            Folder_Path = "Mon"
        },
        ["Clown Pirate [Lv. 10]"] = {
            Location = CFrame.new(-1890, 49, -4440),
            Folder_Path = "Mon"
        },
        ["Smoky [Lv. 20]"] = {
            Location = CFrame.new(-2110, 49, -4746),
            Folder_Path = "Boss"
        },
        ["Tashi [Lv. 30]"] = {
            Location = CFrame.new(-2360, 49, -4516),
            Folder_Path = "Boss"
        },

    --// Pirate Island
        ["Clown Swordman [Lv. 50]"] = {
            Location = CFrame.new(-509, 65, -3498),
            Folder_Path = "Mon"
        },
        ["The Clown [Lv. 75]"] = {
            Location = CFrame.new(-509, 65, -3498),
            Folder_Path = "Boss"
        },

    --// Soldier Island
        ["Commander [Lv. 100]"] = {
            Location = CFrame.new(-2168, 49, -2509),
            Folder_Path = "Mon"
        },
        ["Captain [Lv. 120]"] = {
            Location = CFrame.new(-2168, 49, -2509),
            Folder_Path = "Boss"
        },
        ["The Barbaric [Lv. 145]"] = {
            Location = CFrame.new(-2376, 102, -2495),
            Folder_Path = "Boss"
        },

    --// Shark Island
        ["Fighter Fishman [Lv. 180]"] = {
            Location = CFrame.new(-653, 24, -1601),
            Folder_Path = "Mon"
        },
        ["Karate Fishman [Lv. 200]"] = {
            Location = CFrame.new(-653, 24, -1601),
            Folder_Path = "Boss"
        },
        ["Shark Man [Lv. 230]"] = {
            Location = CFrame.new(-653, 24, -1601),
            Folder_Path = "Boss"
        },

    --// Chef Ship
        ["Trainer Chef [Lv. 250]"] = {
            Location = CFrame.new(-4182, 17, -2947),
            Folder_Path = "Mon"
        },
        ["Dark Leg [Lv. 300]"] = {
            Location = CFrame.new(-4182, 17, -2947),
            Folder_Path = "Boss"
        },
        ["Dory [Lv. 350]"] = {
            Location = CFrame.new(-4338, 15, -2659),
            Folder_Path = "Boss"
        },

    --// Snow Island
        ["Snow Soldier [Lv. 400]"] = {
            Location = CFrame.new(-5424, 28, -1473),
            Folder_Path = "Mon"
        },
        ["King Snow [Lv. 450]"] = {
            Location = CFrame.new(-5424, 28, -1473),
            Folder_Path = "Boss"
        },
        ["Little Dear [Lv. 500]"] = {
            Location = CFrame.new(-5352, 22, -1077),
            Folder_Path = "Boss"
        },

    --// Desert Island
        ["Sand Bandit [Lv. 575]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Mon"
        },
        ["Desert Marauder [Lv. 675]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Mon"
        },
        ["Candle Man [Lv. 525]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Boss"
        },
        ["Bomb Man [Lv. 625]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Boss"
        },
        ["King of Sand [Lv. 725]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Boss"
        },

    --// Sky Island
        ["Sky Soldier [Lv. 800]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Mon"
        },
        ["Cloud Warrior [Lv. 900]"] = {
            Location = CFrame.new(-2981, 92, -576),
            Folder_Path = "Mon"
        },
        ["Ball Man [Lv. 850]"] = {
            Location = CFrame.new(-4821, 441, 1267),
            Folder_Path = "Boss"
        },
        ["Rumble Man [Lv. 950]"] = {
            Location = CFrame.new(-4821, 441, 1267),
            Folder_Path = "Boss"
        },

    --// Bubble Island
        ["High-class Soldier [Lv. 1050]"] = {
            Location = CFrame.new(1769, 43, 817),
            Folder_Path = "Mon"
        },
        ["Elite Soldier [Lv. 1000]"] = {
            Location = CFrame.new(1769, 43, 817),
            Folder_Path = "Mon"
        },
        ["Leader [Lv. 1100]"] = {
            Location = CFrame.new(1769, 43, 817),
            Folder_Path = "Boss"
        },
        ["Pasta [Lv. 1150]"] = {
            Location = CFrame.new(1769, 43, 817),
            Folder_Path = "Boss"
        },

    --// Lobby Island
        ["Wolf [Lv. 1250]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Boss"
        },
        ["Giraffe [Lv. 1300]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Boss"
        },
        ["Naval personnel [Lv. 1200]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Mon"
        },
        ["Nautical soldier [Lv. 1350]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Mon"
        },
        ["Naval soldier [Lv. 1400]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Mon"
        },
        ["Leo [Lv. 1450]"] = {
            Location = CFrame.new(-1238, 20, 2152),
            Folder_Path = "Boss"
        },

    --// Zombie Island
        ["Zombie [Lv. 1500]"] = {
            Location = CFrame.new(-2785, 15, 4182),
            Folder_Path = "Mon"
        },
        ["Elite Zombie [Lv. 1550]"] = {
            Location = CFrame.new(-2785, 15, 4182),
            Folder_Path = "Mon"
        },
        ["Revenant [Lv. 1600]"] = {
            Location = CFrame.new(-2785, 15, 4182),
            Folder_Path = "Mon"
        },
        ["Shadow Master [Lv. 1650]"] = {
            Location = CFrame.new(-2785, 15, 4182),
            Folder_Path = "Boss"
        },

    --// War Island
        ["New World Pirate [Lv. 1700]"] = {
            Location = CFrame.new(2277, 54, -1935),
            Folder_Path = "Mon"
        },
        ["Cutlass Pirate [Lv. 1750]"] = {
            Location = CFrame.new(2277, 54, -1935),
            Folder_Path = "Mon"
        },
        ["Rear Admiral [Lv. 1800]"] = {
            Location = CFrame.new(2277, 54, -1935),
            Folder_Path = "Mon"
        },
        ["True Karate Fishman [Lv. 1850]"] = {
            Location = CFrame.new(2277, 54, -1935),
            Folder_Path = "Boss"
        },
        ["Quake Woman [Lv. 1925]"] = {
            Location = CFrame.new(2277, 54, -1935),
            Folder_Path = "Boss"
        },

    --// Fishland
        ["Fishman [Lv. 2000]"] = {
            Location = CFrame.new(-1729, 40, 6366),
            Folder_Path = "Mon"
        },
        ["Soldier Fishman [Lv. 2150]"] = {
            Location = CFrame.new(-1729, 40, 6366),
            Folder_Path = "Mon"
        },
        ["Combat Fishman [Lv. 2050]"] = {
            Location = CFrame.new(-1729, 40, 6366),
            Folder_Path = "Boss"
        },
        ["Sword Fishman [Lv. 2100]"] = {
            Location = CFrame.new(-1729, 40, 6366),
            Folder_Path = "Boss"
        },
        ["Seasoned Fishman [Lv. 2200]"] = {
            Location = CFrame.new(-1729, 40, 6366),
            Folder_Path = "Boss"
        },
    },
    ["Sea 2"] = {

    },
    ["Sea 3"] = {

    },
}

local Materials = {
    ["Sea 1"] = {
        ["Fresh Fish"] = {
            ["Fighter Fishman [Lv. 180]"] = NPCs["Sea 1"]["Fighter Fishman [Lv. 180]"],
        },
        ["Rusted Scrap"] = {
            ["Clown Swordman [Lv. 50]"] = NPCs["Sea 1"]["Clown Swordman [Lv. 50]"],
            ["Snow Soldier [Lv. 400]"] = NPCs["Sea 1"]["Snow Soldier [Lv. 400]"],
        },        
        ["Leather"] = {
            ["Commander [Lv. 100]"] = NPCs["Sea 1"]["Commander [Lv. 100]"]
        },
        ["Shark Canine"] = {
            ["Shark Man [Lv. 230]"] = NPCs["Sea 1"]["Shark Man [Lv. 230]"],
            ["Karate Fishman [Lv. 200]"] = NPCs["Sea 1"]["Karate Fishman [Lv. 200]"]
        },
        ["Thief Rag"] = {
            ["Desert Marauder [Lv. 675]"] = NPCs["Sea 1"]["Desert Marauder [Lv. 675]"],
            ["Sand Bandit [Lv. 575]"] = NPCs["Sea 1"]["Sand Bandit [Lv. 575]"]
        },
        ["Feather"] = {
            ["Sky Soldier [Lv. 800]"] = NPCs["Sea 1"]["Sky Soldier [Lv. 800]"],
            ["Cloud Warrior [Lv. 900]"] = NPCs["Sea 1"]["Cloud Warrior [Lv. 900]"]
        },
        ["Gunpowder"] = {
            ["Nautical soldier [Lv. 1350]"] = NPCs["Sea 1"]["Nautical soldier [Lv. 1350]"],
            ["Naval personnel [Lv. 1200]"] = NPCs["Sea 1"]["Naval personnel [Lv. 1200]"],
            ["Naval soldier [Lv. 1400]"] = NPCs["Sea 1"]["Naval soldier [Lv. 1400]"]
        },
        ["Twilight Orb"] = {
            ["Shadow Master [Lv. 1650]"] = NPCs["Sea 1"]["Shadow Master [Lv. 1650]"]
        },
    },
    ["Sea 2"] = {

    },
    ["Sea 3"] = {

    },
}

local Quests = {
    ["Sea 1"] = {
        {lvl = 1, Name = "Kill 4 Soldiers", NPC = "Soldier [Lv. 1]"},
        {lvl = 10, Name = "Kill 5 Clown Pirates", NPC = "Clown Pirate [Lv. 10]"},
        {lvl = 20, Name = "Kill 1 Smoky", NPC = "Smoky [Lv. 20]"},
        {lvl = 50, Name = "Kill 1 Tashi", NPC = "Tashi [Lv. 30]"},

        {lvl = 75, Name = "Kill 1 The Clown", NPC = "The Clown [Lv. 75]"},

        {lvl = 120, Name = "Kill 1 Captain", NPC = "Captain [Lv. 120]"},
        {lvl = 145, Name = "Kill 1 The Barbaric", NPC = "The Barbaric [Lv. 145]"},

        {lvl = 230, Name = "Kill 1 Shark Man", NPC = "Shark Man [Lv. 230]"},

        {lvl = 250, Name = "Kill 4 Trainer Chef", NPC = "Trainer Chef [Lv. 250]"},
        {lvl = 300, Name = "Kill 1 Dark Leg", NPC = "Dark Leg [Lv. 300]"},
        {lvl = 350, Name = "Kill 1 Dory", NPC = "Dory [Lv. 350]"},

        {lvl = 450, Name = "Kill 1 King Snow", NPC = "King Snow [Lv. 450]"},
        {lvl = 500, Name = "Kill 1 Little Dear", NPC = "Little Dear [Lv. 500]"},

        {lvl = 550, Name = "Kill 1 Candle Man", NPC = "Candle Man [Lv. 525]"},
        {lvl = 625, Name = "Kill 1 Bomb Man", NPC = "Bomb Man [Lv. 625]"},
        {lvl = 725, Name = "Kill 1 King of Sand", NPC = "King of Sand [Lv. 725]"},

        {lvl = 800, Name = "Kill 1 Ball Man", NPC = "Ball Man [Lv. 850]"},
        {lvl = 950, Name = "Kill 1 Rumble Man", NPC = "Rumble Man [Lv. 950]"},

        {lvl = 1100, Name = "Kill 1 Leader", NPC = "Leader [Lv. 1100]"},
        {lvl = 1150, Name = "Kill 1 Pasta", NPC = "Pasta [Lv. 1150]"},

        {lvl = 1200, Name = "Kill 4 Naval personnel", NPC = "Naval personnel [Lv. 1200]"},
        {lvl = 1250, Name = "Kill 1 Wolf", NPC = "Wolf [Lv. 1250]"},
        {lvl = 1300, Name = "Kill 1 Giraffe", NPC = "Giraffe [Lv. 1300]"},
        {lvl = 1350, Name = "Kill 4 Nautical soldier", NPC = "Nautical soldier [Lv. 1350]"},
        {lvl = 1400, Name = "Kill 4 Naval soldier", NPC = "Naval soldier [Lv. 1400]"},
        {lvl = 1450, Name = "Kill 1 Leo", NPC = "Leo [Lv. 1450]"},

        {lvl = 1500, Name = "Kill 5 Zombies", NPC = "Zombie [Lv. 1500]"},
        {lvl = 1550, Name = "Kill 4 Elite Zombies", NPC = "Elite Zombie [Lv. 1550]"},
        {lvl = 1600, Name = "Kill 4 Revenant", NPC = "Revenant [Lv. 1600]"},
        {lvl = 1650, Name = "Kill 1 Shadow Master", NPC = "Shadow Master [Lv. 1650]"},

        {lvl = 1700, Name = "Kill 4 New World Pirates", NPC = "New World Pirate [Lv. 1700]"},
        {lvl = 1750, Name = "Kill 4 Cutlass Pirates", NPC = "Cutlass Pirate [Lv. 1750]"},
        {lvl = 1800, Name = "Kill 4 Rear Admirals", NPC = "Rear Admiral [Lv. 1800]"},
        {lvl = 1850, Name = "Kill 1 True Karate Fishman", NPC = "True Karate Fishman [Lv. 1850]"},
        {lvl = 1925, Name = "Kill 1 Quake Woman", NPC = "Quake Woman [Lv. 1925]"},

        {lvl = 2000, Name = "Kill 4 Fishmans", NPC = "Fishman [Lv. 2000]"},
        {lvl = 2050, Name = "Kill 1 Combat Fishman", NPC = "Combat Fishman [Lv. 2050]"},
        {lvl = 2100, Name = "Kill 1 Sword Fishman", NPC = "Sword Fishman [Lv. 2100]"},
        {lvl = 2150, Name = "Kill 1 Soldier Fishman", NPC = "Soldier Fishman [Lv. 2150]"},
        {lvl = 2200, Name = "Kill 1 Seasoned Fishman", NPC = "Seasoned Fishman [Lv. 2200]"},
    }
}

return {
    NPCs = NPCs,
    Materials = Materials,
    Quests = Quests,
}
