local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
        local MainUI = playerGui:WaitForChild("MainUI") -- nome da ScreenGui principal
local droppedToolsFolder = workspace.Playability.DroppedTools
local placeId = game.PlaceId
local currentJobId = game.JobId

local loadTries = 0
local function loadChar()
    loadTries += 1
    local PreloadUI = playerGui:WaitForChild("Preload") 
    local PirateButton = PreloadUI:WaitForChild("ChooseTeam").PirateButton 

    task.wait(1) 
    for _, connection in pairs(getconnections(PirateButton.MouseButton1Click)) do
        connection.Function() -- chama o que estaria no clique
    end 
    print(loadTries.."x tentando dar play...")
end

local function searchFruits()
    local totalFruits = 0
    for _, tool in pairs(droppedToolsFolder:GetChildren()) do
        if string.find(tool.Name, "Fruit") then
            totalFruits += 1
            print(tool.Name.." spawnada!")
            if player and player.Character then
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")

                if rootPart then
                    rootPart.CFrame = tool.Handle.CFrame
                end
            end
        end
    end
    if totalFruits == 0 then  
        print("Não achou nenhuma fruta!")
    end
end

local function storeFruit()
    local backpack = player:WaitForChild("Backpack")
    local character = player.Character or player.CharacterAdded:Wait()

    for _, tool in pairs(backpack:GetChildren()) do
        print(tool.Name)
        if tool:IsA("Tool") and string.find(tool.Name:lower(), "fruit") then
            tool.Parent = character
            task.wait(0.1)
            tool:Activate()
            task.wait(1)
            local mainButton = MainUI:WaitForChild("MainFrame") 
                local DialogueFrame = mainButton:WaitForChild("Dialogue") 
                    local StoreButton = DialogueFrame:WaitForChild("Option3") 

            for _, connection in pairs(getconnections(StoreButton.MouseButton1Click)) do
                connection:Fire()
            end
            
            return true 
        end
    end
    return false
end

local function teleportToRandomServer()
    local success, servers = pcall(function()
        local url = "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Asc&limit=100"
        local response = game:HttpGet(url)
        return HttpService:JSONDecode(response)
    end)

    if success and servers and servers.data then
        local possibleServers = {}
        for _, server in ipairs(servers.data) do
            if server.playing < server.maxPlayers and server.id ~= currentJobId then
                table.insert(possibleServers, server.id)
            end
        end

        if #possibleServers > 0 then
            local randomServerId = possibleServers[math.random(1, #possibleServers)]
            TeleportService:TeleportToPlaceInstance(placeId, randomServerId, player)
        else
            warn("Nenhum servidor disponível diferente do atual.")
        end
    else
        warn("Falha ao buscar servidores.")
    end
end

task.wait(10) -- Esperar um pouco
if playerGui:FindFirstChild("Preload") then
    repeat
        loadChar()
        task.wait(.1)
    until playerGui:FindFirstChild("Cmdr") or playerGui:FindFirstChild("Custom Inventory")
    print("Jogo carregado!")
else 
    print("Player já deu start!")
end
searchFruits()
storeFruit()
task.wait(2.5)
while true do
    local ok = teleportToRandomServer()
    if ok then
        break
    end
    wait(3) -- espera 3s antes de tentar de novo
end
