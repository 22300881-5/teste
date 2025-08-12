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
    local success, result = pcall(function()
        local backpack = player:WaitForChild("Backpack", 5)
        local character = player.Character or player.CharacterAdded:Wait()

        -- Move qualquer tool da mão para o backpack
        for _, tool in pairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                tool.Parent = backpack
            end
        end

        -- Procura fruta no backpack
        for _, tool in pairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and string.find(tool.Name:lower(), "fruit") then
                print("Fruta encontrada: "..tool.Name)

                -- Equipa a fruta
                tool.Parent = character
                task.wait(0.2)
                tool:Activate()
                task.wait(1)

                -- Acessa UI de guardar
                local mainButton = MainUI:FindFirstChild("MainFrame")
                if not mainButton then
                    warn("MainFrame não encontrado!")
                    return false
                end

                local DialogueFrame = mainButton:FindFirstChild("Dialogue")
                if not DialogueFrame then
                    warn("Dialogue não encontrado!")
                    return false
                end

                local StoreButton = DialogueFrame:FindFirstChild("Option3")
                if not StoreButton then
                    warn("Option3 (Guardar) não encontrado!")
                    return false
                end

                -- Dispara evento de click
                for _, connection in pairs(getconnections(StoreButton.MouseButton1Click)) do
                    if connection.Function then
                        connection.Function()
                    elseif connection.Fire then
                        connection:Fire()
                    end
                end

                -- Aguarda fruta sair do inventário
                local startTime = tick()
                while backpack:FindFirstChild(tool.Name) or character:FindFirstChild(tool.Name) do
                    if tick() - startTime > 5 then
                        warn("Timeout ao tentar guardar fruta!")
                        return false
                    end
                    task.wait(0.2)
                end

                print("Fruta guardada com sucesso!")
                return true
            end
        end

        print("Nenhuma fruta para guardar.")
        return false
    end)

    if not success then
        warn("Erro no storeFruit: ", result)
        return false
    end

    return result
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
print("Script V0.0.2")

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
