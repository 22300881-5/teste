 local player = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

local loadTries = 0
local function loadChar()
    loadTries += 1
    local PreloadUI = playerGui:WaitForChild("Preload") -- nome da sua ScreenGui
    local PirateButton = PreloadUI:WaitForChild("ChooseTeam").PirateButton -- nome do botão

    -- Simula clique assim que entrar
    task.wait(1) -- pequeno atraso para garantir que tudo carregou
    for _, connection in pairs(getconnections(PirateButton.MouseButton1Click)) do
        connection.Function() -- chama o que estaria no clique
    end 
    print(loadTries.."x tentando dar play...")
end

while not playerGui:FindFirstChild("Cmdr") or playerGui:FindFirstChild("Custom Inventory") do
    loadChar()
    task.wait(1)
end
print("Deu play!")
