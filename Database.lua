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
            Location = CFrame.new(-1890, 49, -4440),
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
        --[[ 
        
        ["Leather]"] = {
            ["Commander"] = NPCs["Commander"]
        },
        ["Shark Canine]"] = {
            ["Shark Man"] = NPCs["Shark Man"],
            ["Karate Fishman"] = NPCs["Karate Fishman"]
        },
        ["Thief Rag]"] = {
            ["Desert Marauder"] = NPCs["Desert Marauder"],
            ["Sand Bandit"] = NPCs["Sand Bandit"]
        },
        ["Feather]"] = {
            ["Sky Soldier"] = NPCs["Sky Soldier"],
            ["Cloud Warrior"] = NPCs["Cloud Warrior"]
        },
        ["Gunpowder]"] = {
            ["Nautical soldier"] = NPCs["Nautical soldier"],
            ["Naval personnel"] = NPCs["Naval personnel"],
            ["Naval soldier"] = NPCs["Naval soldier"]
        },
        ["Twilight Orb]"] = {
            ["Shadow Master"] = NPCs["Shadow Master"]
        },
        
        ]]
    },
    ["Sea 2"] = {

    },
    ["Sea 3"] = {

    },
}

return {
    NPCs = NPCs,
    Materials = Materials
}
