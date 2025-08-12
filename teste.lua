 local player = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

local function loadChar()
    local PreloadUI = playerGui:WaitForChild("Preload") -- nome da sua ScreenGui
    local PirateButton = PreloadUI:WaitForChild("ChooseTeam").PirateButton -- nome do botão

    -- Simula clique assim que entrar
    task.wait(1) -- pequeno atraso para garantir que tudo carregou
    for _, connection in pairs(getconnections(PirateButton.MouseButton1Click)) do
        connection.Function() -- chama o que estaria no clique
    end 
    print("Player entrou no jogo!")
end

while not playerGui:FindFirstChild("Cmdr") or playerGui:FindFirstChild("Cmdr") do
    print("Ainda não deu play!")
    loadChar()
    task.wait(1)
end
print("no jogo!")
