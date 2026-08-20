print("[NPCs] iniciou")

local MonsterFolder = workspace:WaitForChild("Monster")

print("[NPCs] Monster encontrado:", MonsterFolder)

local Data = {
    ["Carrot"] = {
        {
            Path = MonsterFolder.Mon,
            Location = CFrame.new(-4083, 57, -1.7),
            NPC = "Beast Pirate [Lv. 2250]"
        }
    }
}

print("[NPCs] tabela criada")

return Data
