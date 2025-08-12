local function loadChar()
    -- LocalScript dentro de StarterPlayerScripts
    local player = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- Espera a GUI carregar
    local screenGui = playerGui:WaitForChild("Preload") -- nome da sua ScreenGui
    local playButton = screenGui:WaitForChild("ChooseTeam").PirateButton -- nome do botão

    -- Simula clique assim que entrar
    task.wait(1) -- pequeno atraso para garantir que tudo carregou
    for _, connection in pairs(getconnections(playButton.MouseButton1Click)) do
        connection.Function() -- chama o que estaria no clique
    end 
    print("Player entrou no jogo!")
end

local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Espera a GUI carregar
local screenGui = playerGui:FindFirstChild("Preload") -- nome da sua ScreenGui
if not screenGui then
    print("Já clicou em play!")
else
    local playButton = screenGui:WaitForChild("ChooseTeam").PirateButton -- nome do botão
    while not playButton.Visible do
        task.wait(1)
    end
    print("Botões carregaram!")
end

loadChar()
