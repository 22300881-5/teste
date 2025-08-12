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
    local maxTentativas = 2 -- cada execução do storeFruit tenta 2 vezes
    local tentativa = 0
    while tentativa < maxTentativas do
        tentativa += 1
        print(string.format("[storeFruit] Tentativa interna %d de %d", tentativa, maxTentativas))
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then
            warn("[storeFruit] Backpack não encontrada")
            task.wait(1)
            continue
        end
        local character = player.Character or player.CharacterAdded:Wait()
        for _, tool in pairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and string.find(tool.Name:lower(), "fruit") then
                tool.Parent = character
                task.wait(0.2)
                pcall(function() tool:Activate() end)
                print("[storeFruit] Equipou e usou:", tool.Name)
                task.wait(2)
                local playerGui = player:FindFirstChild("PlayerGui")
                if not playerGui then return true end
                local mainGui = playerGui:FindFirstChild("MainUI")
                if not mainGui then return true end
                local mainButton = mainGui:FindFirstChild("MainFrame")
                if not mainButton then return true end
                local optionsFrame = mainButton:FindFirstChild("Dialogue")
                if not optionsFrame then return true end
                task.wait(2)
                local optionButton = optionsFrame:FindFirstChild("Option3")
                if not optionButton then return true end
                if type(getconnections) == "function" then
                    local ok, conns = pcall(function()
                        return getconnections(optionButton.MouseButton1Click)
                    end)
                    if ok and conns then
                        for _, connection in pairs(conns) do
                            if type(connection.Function) == "function" then
                                pcall(connection.Function)
                            end
                        end
                    else
                        warn("[storeFruit] getconnections retornou nil ou falhou")
                    end
                end
                if string.find(tool.Name:lower(), "poison") or string.find(tool.Name:lower(), "orbit") then
                    print("[storeFruit] Achou mítica")
                    mythicalFound = true
                end
                return true
            end
        end
        print("[storeFruit] Nenhuma fruta encontrada no backpack. Tentando novamente...")
        task.wait(1.5)
    end
    print("[storeFruit] Nenhuma fruta encontrada após " .. maxTentativas .. " tentativas internas.")
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

task.wait(2) -- Pequeno delay antes de tudo, só pra evitar corrida
print("Script V0.0.1")

if playerGui:FindFirstChild("Preload") then
    repeat
        loadChar()
        task.wait(0.1)
    until playerGui:FindFirstChild("Cmdr") or playerGui:FindFirstChild("Custom Inventory")
    print("Jogo carregado!")
else
    print("Player já deu start!")
end

task.wait(10)
searchFruits()
task.wait(10)
storeFruit()
task.wait(10)

while true do
    local ok = teleportToRandomServer()
    if ok then
        break
    end
    task.wait(3)
end
