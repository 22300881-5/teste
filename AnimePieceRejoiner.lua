local PLACE_ID_PERMITIDA = 134039915751463

if game.PlaceId ~= PLACE_ID_PERMITIDA then
	return
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VELOCIDADE_TWEEN = 125
local TEMPO_POR_KIRO = 5
local TEMPO_COLETA = 15
local TEMPO_STORAGE = 15
local FRUIT_ARRIVAL_WAIT = 4
local FRUIT_PICKUP_WAIT = 2
local FRUIT_HANDOFF_WAIT = 2

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player

repeat
	player = Players.LocalPlayer

	if not player then
		task.wait(0.1)
	end
until player

-- Evita múltiplos loops e UIs nesta sessão.
local env = getgenv and getgenv() or _G
local previous = env.AnimePieceRuntime
local autoLevel=env.AnimePieceAutoLevelUI
if autoLevel and autoLevel.Alive and (autoLevel.Pending or autoLevel.PriorityBusy or autoLevel.DesiredEnabled
    or autoLevel.Automation and autoLevel.Automation.Enabled) then
    warn("Rejoin: pause ou descarregue o AutoLevel antes de iniciar este script.")
    return
end
if previous then
	-- Reexecutar substitui a instância anterior, inclusive se ela travou.
	previous.Alive = false
	if previous.Library then pcall(function() previous.Library:Unload() end) end
	if previous.FarmThread then pcall(task.cancel, previous.FarmThread) end
	if previous.ControllerThread then pcall(task.cancel, previous.ControllerThread) end
    if previous.IdleConnection then previous.IdleConnection:Disconnect() end
    if previous.SpinConnection then previous.SpinConnection:Disconnect() end
	if previous.Tween then pcall(function() previous.Tween:Cancel() end) end
    if previous.CancelChestMovement then pcall(previous.CancelChestMovement) end
    if previous.CancelFruitMovement then pcall(previous.CancelFruitMovement) end
	for _, connection in ipairs(previous.FarmConnections or {}) do
		pcall(function() connection:Disconnect() end)
	end
	for _, connection in ipairs(previous.RejoinConnections or {}) do
		pcall(function() connection:Disconnect() end)
	end
end
local Runtime = {Alive = true, RejoinRequested = false, FarmDone = false,SpinTicket=previous and previous.SpinTicket}
Runtime.Version="server-controller-v11-diagnostic"
print("Main v11 | Novo controlador de servidores carregado.")
env.AnimePieceRuntime = Runtime
Runtime.IdleConnection=player.Idled:Connect(function()
    if not Runtime.Alive then return end
    local ok,err=pcall(function()
        local virtualUser=game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0,0))
    end)
    if not ok then warn("Main | Proteção contra inatividade indisponível:",err) end
end)

local function executarComLimite(seconds, operation, cancelCheck)
	local done = false
	local result
	local worker = task.spawn(function()
		result = table.pack(pcall(operation))
		done = true
	end)
	local deadline = os.clock() + seconds
	while not done and Runtime.Alive and os.clock() < deadline do
		if cancelCheck and cancelCheck() then break end
		task.wait(0.1)
	end
	if not done then
		pcall(task.cancel, worker)
		return false, "Operação interrompida ou tempo limite excedido."
	end
	return table.unpack(result, 1, result.n)
end

-- Interface e persistência Obsidian (separadas por conta e PlaceId).
local AutoChestsEnabled = true
local OnlyPurpleAtMoneyCap=true
local MONEY_CAP=1000000
local FruitStorageLimit = 1
local function canStoreFruit(name)
    local global=getrenv()._G
    local fruits=global and global.ClientInventory and global.ClientInventory.Items and global.ClientInventory.Items.Fruits
    if type(fruits)~="table" then return false,"Inventário ainda não carregado" end
    local count=0
    for _,item in pairs(fruits) do
        if item.Name==name then count+=tonumber(item.Amount) or 1 end
    end
    if count>=FruitStorageLimit then return false,"Sem slot configurado para "..name end
    return true
end
local AutoFruitSpinEnabled = true
local AutoRejoinEnabled = true
local RejoinRevision = 0
local Delivery={Enabled=false,JobId="",Receiver="",PublicJobId="",Interval=60,Selected={},PerFruit=1,Keep=0,Requested=false,Busy=false}
local deliveryFile="AnimePiece_VipDelivery_"..tostring(game.PlaceId).."_"..tostring(player.UserId)..".json"
Delivery.State={LastAt=0}
pcall(function()
    if type(isfile)=="function" and type(readfile)=="function" and isfile(deliveryFile) then
        local saved=HttpService:JSONDecode(readfile(deliveryFile))
        if type(saved)=="table" then
            Delivery.State.LastAt=tonumber(saved.LastAt) or 0
            if type(saved.Pending)=="table" and type(saved.Pending.Target)=="string" and type(saved.Pending.Items)=="table" then Delivery.State.Pending=saved.Pending end
        end
    end
end)
local function saveDeliveryState()
    assert(type(writefile)=="function","A entrega exige salvamento local para continuar após o teleporte.")
    writefile(deliveryFile,HttpService:JSONEncode(Delivery.State))
end
local function deliveryStatus(text)
    Delivery.Status=text
    if Delivery.Label then pcall(function() Delivery.Label:SetText(text) end) end
end
Runtime.Delivery=Delivery

-- Relatório periódico (servidores, frutas coletadas e ignoradas). Fica salvo em arquivo porque o
-- script reinicia a cada servidor; o período continua contando entre as trocas.
local Report={Enabled=true,Interval=30,Folder="AnimePiece",
    File="AnimePiece/Relatorio_"..game.PlaceId.."_"..player.UserId..".json"}
local function reportNew()
    -- LastServer evita recontar o servidor atual logo após zerar o período.
    return {Start=os.time(),Servers=0,Collected={},Ignored={},LastServer=game.JobId}
end
local function reportLoad()
    local data
    pcall(function()
        if type(isfile)=="function" and isfile(Report.File) then data=HttpService:JSONDecode(readfile(Report.File)) end
    end)
    if type(data)~="table" or type(data.Start)~="number" then
        local fresh=reportNew()
        fresh.LastServer=nil
        return fresh
    end
    data.Servers=tonumber(data.Servers) or 0
    if type(data.Collected)~="table" then data.Collected={} end
    if type(data.Ignored)~="table" then data.Ignored={} end
    return data
end
function Report.Save()
    if type(writefile)~="function" then return end
    pcall(function()
        if type(isfolder)=="function" and type(makefolder)=="function" and not isfolder(Report.Folder) then makefolder(Report.Folder) end
        writefile(Report.File,HttpService:JSONEncode(Report.State))
    end)
end
local function reportNome(nome)
    nome=tostring(nome or "?"):gsub("<[^>]+>",""):gsub("^%s+",""):gsub("%s+$","")
    return nome~="" and nome or "?"
end
local function reportSoma(lista)
    local total=0
    for _,quantidade in pairs(lista) do total+=quantidade end
    return total
end
local function reportLinhas(lista)
    local nomes={}
    for nome in pairs(lista) do nomes[#nomes+1]=nome end
    table.sort(nomes,function(a,b) return lista[a]>lista[b] or lista[a]==lista[b] and a<b end)
    local linhas={}
    for _,nome in ipairs(nomes) do linhas[#linhas+1]="• "..nome.." ×"..lista[nome] end
    return #linhas>0 and table.concat(linhas,"\n") or "Nenhuma"
end
Report.Linhas=reportLinhas
Report.Soma=reportSoma
function Report.Texto()
    local s=Report.State
    local minutos=math.floor((os.time()-s.Start)/60)
    return string.format("<b>⏱ Período atual:</b> %d / %d min\n<b>🌐 Servidores:</b> %d\n<b>🍈 Coletadas (%d):</b>\n%s\n<b>🚫 Ignoradas (%d):</b>\n%s",
        minutos,Report.Interval,s.Servers,reportSoma(s.Collected),reportLinhas(s.Collected),reportSoma(s.Ignored),reportLinhas(s.Ignored))
end
function Report.Refresh()
    if Report.Label then pcall(function() Report.Label:SetText(Report.Texto()) end) end
end
-- kind: "Server", "Collected" ou "Ignored".
function Report.Add(kind,nome)
    local s=Report.State
    if kind=="Server" then
        -- O registro do servidor roda mais de uma vez por entrada; conta cada JobId uma vez.
        if s.LastServer==game.JobId then return end
        s.LastServer=game.JobId
        s.Servers+=1
    else
        local lista=kind=="Collected" and s.Collected or s.Ignored
        nome=reportNome(nome)
        lista[nome]=(lista[nome] or 0)+1
    end
    Report.Save()
    Report.Refresh()
end
function Report.Reset()
    Report.State=reportNew()
    Report.Save()
    Report.Refresh()
end
Report.State=reportLoad()
Runtime.Report=Report

-- Uma falha ao baixar a UI não encerra a automação.
local function criarInterface()
	local saveDeliveryOptions
	local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
	local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
	Runtime.Library = Library
	local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
	local Window = Library:CreateWindow({
		Title = "AnimePiece",
		Footer = "Main v11 • Baús e entrega pública • Configurações por conta",
		AutoShow = false,
		Center = true,
		ToggleKeybind = Enum.KeyCode.RightControl,
	})
	local tab = Window:AddTab("Configurações", "settings")
    local chestTab = Window:AddTab("Baús", "package")
    local serversTab=Window:AddTab("Servidores","list")
    local savedServers=serversTab:AddGroupbox({Side="Left",Name="📋 Histórico de servidores"})
    local savedServerInfo=serversTab:AddGroupbox({Side="Right",Name="ℹ Como ler a lista"})
    Runtime.ServerActivity=savedServerInfo:AddLabel("Estado atual: preparando automação...",true)
    savedServerInfo:AddButton({Text="Copiar diagnóstico",Func=function()
        if not Runtime.GetServerDiagnostic then return end
        local report=HttpService:JSONEncode(Runtime.GetServerDiagnostic())
        if type(setclipboard)=="function" then setclipboard(report) end
        print("Main | DIAGNÓSTICO:",report)
    end})
    Runtime.SavedServersSummary=savedServers:AddLabel("Lista de atualização manual",true)
    Runtime.SavedServersList=savedServers:AddLabel("Clique em Atualizar lista para consultar o histórico local.",true)
    savedServers:AddButton({Text="Atualizar lista",Func=function()
        Runtime.ServerListRefreshAt=0
        if Runtime.RefreshSavedServers then Runtime.RefreshSavedServers() end
    end})
    Runtime.SavedServersPage=savedServers:AddLabel("Página 1",true)
    savedServers:AddButton({Text="← Página anterior",Func=function()
        Runtime.ServerListPage=math.max(1,(Runtime.ServerListPage or 1)-1)
        Runtime.ServerListRefreshAt=0
        if Runtime.RefreshSavedServers then Runtime.RefreshSavedServers() end
    end})
    savedServers:AddButton({Text="Próxima página →",Func=function()
        Runtime.ServerListPage=(Runtime.ServerListPage or 1)+1
        Runtime.ServerListRefreshAt=0
        if Runtime.RefreshSavedServers then Runtime.RefreshSavedServers() end
    end})
    savedServerInfo:AddLabel("<b>Histórico de servidores</b>\nAtualização manual pelos botões. Retorno por timer desativado nesta versão. Servidores com falha ficam bloqueados por 15 minutos.",true)
    Runtime.SavedServersStorage=savedServerInfo:AddLabel("Histórico local: aguardando leitura.",true)
    local deliveryTab=Window:AddTab("Entrega","gift")
    local deliveryBox=deliveryTab:AddGroupbox({Side="Left",Name="🍈 Entrega periódica"})
    local deliveryInfo=deliveryTab:AddGroupbox({Side="Right",Name="📍 Destino e acompanhamento"})
    deliveryBox:AddToggle("PlayerDeliveryEnabled",{Text="Ativar entrega ao recebedor",Default=false,
        Callback=function(value) Delivery.Enabled=value if value then Delivery.Error=nil end if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryBox:AddSlider("VipDeliveryInterval",{Text="Entregar a cada (min)",Default=60,Min=5,Max=240,Rounding=0,
        Callback=function(value) Delivery.Interval=value if saveDeliveryOptions then saveDeliveryOptions() end end})
    local fruitNames={}
    local g=getrenv()._G
    for name,data in pairs(g and g.GameData and g.GameData["Items Data"] or {}) do
        if data.Category=="Fruits" then table.insert(fruitNames,name) end
    end
    table.sort(fruitNames)
    deliveryBox:AddDropdown("VipDeliveryFruits",{Text="Frutas permitidas para entregar",Values=fruitNames,Default={},Multi=true,Searchable=true,
        Callback=function(value) Delivery.Selected=value if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryBox:AddSlider("VipDeliveryAmount",{Text="Máximo por tipo em cada entrega",Default=1,Min=1,Max=5,Rounding=0,
        Callback=function(value) Delivery.PerFruit=value if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryBox:AddSlider("VipDeliveryKeep",{Text="Guardar pelo menos esta quantidade por tipo",Default=0,Min=0,Max=5,Rounding=0,
        Callback=function(value) Delivery.Keep=value if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryBox:AddButton({Text="📦 Solicitar entrega agora",Func=function()
        if not Delivery.Enabled then deliveryStatus("Ative a entrega e configure as frutas e o destino primeiro.") return end
        Delivery.Requested=true
        deliveryStatus("Entrega solicitada; aguardando finalizar a varredura e o roll.")
    end})
    deliveryInfo:AddInput("PlayerDeliveryReceiver",{Text="Username do recebedor (não o nome de exibição)",Default="",Finished=true,
        Callback=function(value) Delivery.Receiver=value:match("^%s*@?(.-)%s*$") Delivery.ReceiverCache=nil if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryInfo:AddInput("PlayerDeliveryPublicJobId",{Text="JobId público do recebedor (se a localização automática falhar)",Default="",Finished=true,
        Callback=function(value) Delivery.PublicJobId=value:match("^%s*(.-)%s*$") if saveDeliveryOptions then saveDeliveryOptions() end end})
    deliveryInfo:AddButton({Text="📋 Copiar ID deste servidor",Func=function()
        if type(setclipboard)=="function" then setclipboard(game.JobId) end
        deliveryStatus("ID deste servidor copiado. Copie na conta recebedora, em um servidor público, e cole na coletora.")
    end})
    deliveryInfo:AddLabel("<b>Configuração inicial</b>\n1. Deixe o recebedor em um servidor público deste jogo.\n2. Digite o username dele e selecione as frutas.\n3. Se o Roblox não informar a localização, cole o JobId público dele.\n4. Ative a entrega.\n<font color=\"#F0C674\">Nenhuma fruta será retirada sem confirmar o recebedor no servidor de destino. Se ele mudar de servidor, atualize o JobId informado.</font>",true)
    Delivery.Label=deliveryInfo:AddLabel(Delivery.State.Pending and "Entrega pendente salva; aguardando destino correto." or "Entrega desligada. Nenhuma fruta será retirada sem ativar e selecionar.",true)
    deliveryInfo:AddLabel("<b>Como entrega</b>\nEntra no servidor público, confirma o username e o personagem do recebedor, aproxima-se dele e dropa apenas as frutas selecionadas. Depois retoma a busca.\nO Main precisa iniciar novamente após o teleporte.\n<font color=\"#F0C674\">Outras pessoas podem pegar as frutas do chão. O drop confirmado não garante que foi o recebedor quem pegou.</font>",true)
    deliveryInfo:AddButton({Text="⏹ Cancelar entrega pendente e pausar",Func=function()
        if Delivery.Busy then deliveryStatus("Descarregue o script antes de cancelar uma entrega em andamento.") return end
        Delivery.Enabled=false Delivery.Requested=false Delivery.Error=nil Delivery.JobId="" Delivery.State.Pending=nil
        pcall(saveDeliveryState)
        Library.Toggles.PlayerDeliveryEnabled:SetValue(false)
        Library.Toggles.AutoRejoinEnabled:SetValue(false)
        deliveryStatus("Entrega cancelada e rejoin pausado. Confira as frutas da mochila e do chão antes de continuar.")
    end})
    local reportTab=Window:AddTab("Relatório","clipboard-list")
    local reportBox=reportTab:AddGroupbox({Side="Left",Name="📊 Período atual"})
    local reportConfig=reportTab:AddGroupbox({Side="Right",Name="📨 Envio para o Discord"})
    Report.Label=reportBox:AddLabel(Report.Texto(),true)
    reportConfig:AddToggle("ReportEnabled",{Text="Enviar relatório ao Discord",Default=true,
        Callback=function(value) Report.Enabled=value if saveDeliveryOptions then saveDeliveryOptions() end end})
    reportConfig:AddSlider("ReportInterval",{Text="Intervalo do relatório (min)",Default=30,Min=5,Max=180,Rounding=0,
        Callback=function(value) Report.Interval=value Report.Refresh() if saveDeliveryOptions then saveDeliveryOptions() end end})
    reportConfig:AddButton({Text="📨 Enviar agora e iniciar novo período",Func=function()
        if Report.Send then task.spawn(Report.Send,true) end
    end})
    reportConfig:AddButton({Text="🗑 Zerar período sem enviar",Func=Report.Reset})
    Report.StatusLabel=reportConfig:AddLabel("Último envio: nenhum nesta execução.",true)
    reportConfig:AddLabel("O período continua contando entre trocas de servidor. Servidores de entrega não entram na contagem. Frutas ignoradas são as da lista de bloqueio (Kilo, Copy, Warrior, Bomb).",true)
	local movement = tab:AddGroupbox({Side = "Right", Name = "Movimento"})
	local config = tab:AddGroupbox({Side = "Right", Name = "Salvamento"})
	local saveLabel = config:AddLabel("Carregando configurações...", true)

	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetIgnoreIndexes({"FPSCap", "Disable3DRendering"})
	SaveManager:SetFolder("AnimePiece/Users/" .. tostring(player.UserId))
	SaveManager:SetSubFolder(tostring(game.PlaceId))

	local loading = true
	local closed = false
	local revision = 0
	local function salvarAgora()
		local ok, success, message = pcall(function()
			return SaveManager:Save("AutoSave")
		end)
		if not ok or not success then
			saveLabel:SetText("Falha ao salvar: " .. tostring(message or success))
			return
		end
		local markerOk, markerSuccess = pcall(function()
			return SaveManager:SaveAutoloadConfig("AutoSave")
		end)
		saveLabel:SetText(markerOk and markerSuccess
			and "Configurações salvas automaticamente."
			or "Configuração salva; falha ao definir carregamento automático.")
	end
	local function agendarSalvar()
		if loading or closed then return end
		revision += 1
		local current = revision
		task.delay(0.5, function()
			if not closed and current == revision then salvarAgora() end
		end)
	end

    saveDeliveryOptions=agendarSalvar
	movement:AddSlider("TweenSpeed", {
		Text = "Velocidade do tween", Default = VELOCIDADE_TWEEN,
		Min = 50, Max = 500, Rounding = 0,
	})
	movement:AddSlider("KiroWait", {
        Text = "Espera ao chegar na ilha (s)", Default = TEMPO_POR_KIRO,
		Min = 2, Max = 15, Rounding = 1,
	})
	movement:AddLabel("A velocidade se aplica ao próximo trajeto até um Handle.", true)
    movement:AddSlider("FruitArrivalWaitSeconds",{Text="⏳ Espera a 50 studs, antes do tween (s)",Default=4,Min=1,Max=10,Rounding=1})
    movement:AddSlider("FruitPickupWaitSeconds",{Text="🍈 Espera ao lado da fruta, antes do prompt (s)",Default=2,Min=.5,Max=10,Rounding=1})
    movement:AddSlider("FruitCombatHandoffSeconds",{Text="⏸ Pausa antes do spawn seguro (s)",Default=2,Min=1,Max=5,Rounding=1})
    Library.Options.FruitArrivalWaitSeconds:OnChanged(function(value) FRUIT_ARRIVAL_WAIT=value agendarSalvar() end)
    Library.Options.FruitPickupWaitSeconds:OnChanged(function(value) FRUIT_PICKUP_WAIT=value agendarSalvar() end)
    Library.Options.FruitCombatHandoffSeconds:OnChanged(function(value) FRUIT_HANDOFF_WAIT=value agendarSalvar() end)
    movement:AddLabel("<b>📍 Coleta de fruta</b>\n① Aguarda a pausa e vai ao spawn seguro.\n② Aproxima a 50 studs e espera.\n③ Faz o tween na velocidade configurada.\n④ Aguarda ao lado da fruta e só então coleta.",true)

	Library.Options.TweenSpeed:OnChanged(function(value)
        VELOCIDADE_TWEEN = math.clamp(tonumber(value) or 125, 50, 500)
		agendarSalvar()
	end)
	Library.Options.KiroWait:OnChanged(function(value)
		TEMPO_POR_KIRO = math.clamp(tonumber(value) or 5, 2, 15)
		if value ~= TEMPO_POR_KIRO then
			Library.Options.KiroWait:SetValue(TEMPO_POR_KIRO)
		end
		agendarSalvar()
	end)

    local economy = chestTab:AddGroupbox({Side="Left",Name="Farm de baús"})
    economy:AddToggle("AutoChestsEnabled",{Text="Coletar baús após verificar frutas",Default=true})
    economy:AddToggle("OnlyPurpleAtMoneyCap",{Text="Com $1M, coletar apenas Purple Chests",Default=true,
        Callback=function(value) OnlyPurpleAtMoneyCap=value agendarSalvar() end})
    economy:AddLabel("<b>💰 Ao atingir $1.000.000</b>\nIgnora os outros baús e continua buscando Purple Chests. Se o saldo cair, volta a coletar os demais.\n<font color=\"#9AA6B8\">Coleta por contato físico, com pausas entre baús.</font>",true)
    local rewards = chestTab:AddGroupbox({Side="Right",Name="Frutas e armazenamento"})
    rewards:AddToggle("AutoFruitSpinEnabled",{Text="Girar fruta a cada 1 hora (dinheiro do jogo)",Default=true})
    rewards:AddSlider("FruitStorageLimit",{Text="Limite guardado por tipo de fruta",Default=1,Min=1,Max=5,Rounding=0})
    Library.Options.FruitStorageLimit:OnChanged(function(value) FruitStorageLimit=math.clamp(tonumber(value) or 1,1,5) agendarSalvar() end)
    rewards:AddLabel("Proteção de slot: padrão 1 por tipo. Aumente somente se sua conta tiver slots extras.",true)
    rewards:AddLabel("<b>🎲 Roll com confirmação</b>\nAguarda a fruta aparecer na mochila ou no inventário antes de continuar a varredura e relogar.",true)
    rewards:AddButton({Text="⏹ Cancelar espera do roll",Func=function() Runtime.CancelSpin=true end})
    Library.Toggles.AutoChestsEnabled:OnChanged(function(value) AutoChestsEnabled=value agendarSalvar() end)
    Library.Toggles.AutoFruitSpinEnabled:OnChanged(function(value) AutoFruitSpinEnabled=value agendarSalvar() end)
    economy:AddLabel("Em cada ilha: espera carregar, verifica frutas, coleta baús e tenta guardar as frutas da mochila. O giro exige nível 50, saldo e cooldown disponível.",true)
    economy:AddLabel("Baú dourado pode dar dinheiro; o roxo pode dar fruta. Não compra slots nem usa Robux.",true)
    local chestStatus=chestTab:AddGroupbox({Side="Left",Name="Acompanhamento"})
    Runtime.ChestStatusLabel=chestStatus:AddLabel("Aguardando varredura...",true)
    Runtime.ChestCountLabel=chestStatus:AddLabel("Baús confirmados: 0 | Visitados: 0",true)
    Runtime.ChestMoneyLabel=chestStatus:AddLabel("Dinheiro dos baús: $0",true)
    local serverBox = tab:AddGroupbox({Side = "Left", Name = "Servidores"})
	local rejoinLabel = serverBox:AddLabel("Troca automática: ativada", false)
	Runtime.StatusLabel = serverBox:AddLabel("Preparando automação...", true)
	Runtime.ErrorLabel = serverBox:AddLabel("Último erro: nenhum", true)
	serverBox:AddToggle("AutoRejoinEnabled", {
		Text = "Trocar de servidor automaticamente",
		Default = AutoRejoinEnabled,
	})
	Library.Toggles.AutoRejoinEnabled:OnChanged(function(value)
		if AutoRejoinEnabled ~= value then RejoinRevision += 1 end
		AutoRejoinEnabled = value
		-- O toggle libera o rejoin, mas não cancela a checagem dos Kiros.
		rejoinLabel:SetText(value and "Troca automática: ativada" or "Troca automática: pausada")
		agendarSalvar()
	end)
	serverBox:AddLabel("Desligado: pausa novas trocas. Ligado: troca após concluir a busca/coleta.", true)
    serverBox:AddLabel("<b>🕒 Histórico de servidores</b>\nEvita servidores visitados nos últimos 15 minutos. Se todas as páginas só tiverem repetidos, tenta o visitado há mais tempo. Somente o servidor que falhou é ignorado por 15 minutos; outros podem ser tentados após 5 segundos. Consultas HTTP têm intervalo mínimo de 30 segundos.",true)
    serverBox:AddLabel("<b>Troca simples de servidor</b>\nBusca servidores públicos com vaga. Retornos por timer desativados. Mantém o histórico recente e o bloqueio de entradas que falharam.",true)

	config:AddButton({Text = "Salvar agora", Func = salvarAgora})
	config:AddLabel("Alterações são salvas automaticamente e carregadas na próxima execução.", true)
	config:AddButton({Text = "Ocultar janela", Func = function() Library:Toggle() end})
    Runtime.Unload=function() Library:Unload() end
    config:AddButton({Text = "Descarregar script", Func = Runtime.Unload})
	config:AddLabel("Ctrl direito ou botão Menu para mostrar a janela.", true)
	Library:AddDraggableButton("Menu", function() Library:Toggle() end, true, true)
	Library:OnUnload(function()
		closed = true
		Runtime.Alive = false
        if Runtime.IdleConnection then Runtime.IdleConnection:Disconnect() end
        AutoRejoinEnabled = false
        AutoChestsEnabled = false
        AutoFruitSpinEnabled = false
        if Runtime.InventoryConnection then Runtime.InventoryConnection:Disconnect() end
        if Runtime.SpinConnection then Runtime.SpinConnection:Disconnect() end
        if Runtime.ControllerThread then pcall(task.cancel,Runtime.ControllerThread) end
        if Runtime.HttpThread then pcall(task.cancel,Runtime.HttpThread) end
		if Runtime.FarmThread then pcall(task.cancel, Runtime.FarmThread) end
		if Runtime.Tween then pcall(function() Runtime.Tween:Cancel() end) end
        if Runtime.CancelChestMovement then pcall(Runtime.CancelChestMovement) end
        if Runtime.CancelFruitMovement then pcall(Runtime.CancelFruitMovement) end
        local character=Runtime.ArrivalCharacter
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if root and root.Anchored and Runtime.ArrivalOriginalAnchored==false then
            if Runtime.LastSafeCFrame then root.CFrame=Runtime.LastSafeCFrame end
            root.AssemblyLinearVelocity=Vector3.zero
            root.Anchored=false
        end
		for _, connection in ipairs(Runtime.FarmConnections or {}) do connection:Disconnect() end
		for _, connection in ipairs(Runtime.RejoinConnections or {}) do connection:Disconnect() end
		AutoRejoinEnabled = false
	end)

	-- Carrega somente depois de criar todos os controles e callbacks.
	local loaded, loadSuccess, loadMessage = pcall(function()
		return SaveManager:Load("AutoSave")
	end)
	loading = false
	if not loaded then
		saveLabel:SetText("Falha ao carregar: " .. tostring(loadSuccess))
	elseif not loadSuccess then
		saveLabel:SetText("Usando valores iniciais. " .. tostring(loadMessage or ""))
	end
	if loaded and loadSuccess then
		saveLabel:SetText("Configurações carregadas.")
	elseif loaded then
		salvarAgora()
	end
end

local uiOk, uiError
for tentativa = 1, 3 do
	uiOk, uiError = executarComLimite(45, criarInterface)
	if uiOk then break end
	if Runtime.Library then
		pcall(function() Runtime.Library:Unload() end)
		Runtime.Library = nil
	end
	-- Unload da tentativa parcial não encerra a tentativa seguinte.
	Runtime.Alive = true
	AutoRejoinEnabled = true
	Runtime.RejoinRequested = false
	Runtime.StatusLabel = nil
	task.wait(3)
end
if not uiOk then
	Runtime.Alive = false
    if Runtime.IdleConnection then Runtime.IdleConnection:Disconnect() end
	env.AnimePieceRuntime = nil
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "AnimePiece", Text = "UI não carregou. Execute novamente para tentar de novo.", Duration = 10,
		})
	end)
	return -- Não inicia farm sem seus controles.
end

local function atualizarStatus(text)
	if Runtime.LastStatus == text then return end
	Runtime.LastStatus = text
    if Runtime.ServerActivity then
        pcall(function() Runtime.ServerActivity:SetText("Estado atual: "..text) end)
    end
	if Runtime.StatusLabel then
		pcall(function() Runtime.StatusLabel:SetText(text) end)
	end
    if Runtime.ChestStatusLabel then
        pcall(function() Runtime.ChestStatusLabel:SetText(text) end)
    end
end

local function registrarErro(stage, message)
	Runtime.LastError = stage .. ": " .. tostring(message)
	if Runtime.ErrorLabel then
		pcall(function() Runtime.ErrorLabel:SetText("Último erro: " .. Runtime.LastError) end)
	end
end

-- Dependências do farm são carregadas no worker, sem bloquear o rejoin.
local backpack, characterFolder, world, interactive
local droppedTools, serverTime, physicalFruitsEvent

local function aguardarObjeto(parent, name)
	atualizarStatus("Carregando: " .. name)
	local item = parent:WaitForChild(name, 15)
	if not item then error("Objeto não carregou em 15s: " .. name) end
	return item
end

local function carregarDependencias()
	backpack = aguardarObjeto(player, "Backpack")
	characterFolder = aguardarObjeto(workspace, "ClientPlayer")
	world = aguardarObjeto(workspace, "World")
	interactive = aguardarObjeto(aguardarObjeto(aguardarObjeto(world, "IgnoreList"), "Npcs"), "Interactive")
	droppedTools = aguardarObjeto(aguardarObjeto(world, "Playability"), "DroppedTools")
	serverTime = aguardarObjeto(aguardarObjeto(ReplicatedStorage, "ServerInfo"), "ServerTime")
	physicalFruitsEvent = aguardarObjeto(aguardarObjeto(ReplicatedStorage, "Remotes"), "Physical Fruits Event")
end

local function personagemPronto(character)
	if not character
		or player.Character ~= character
        or not character.Parent then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if humanoid
		and humanoid.Health > 0
		and root
		and root:IsA("BasePart") then
		return humanoid, root
	end

	return nil
end

local function esperarSpawn()
	local deadline = os.clock() + 45
	while Runtime.Alive and os.clock() < deadline do
		local character = player.Character
		local humanoid, root = personagemPronto(character)
		if humanoid and root then return character, humanoid, root end
		task.wait(0.1)
	end
	error("Personagem não ficou pronto em 45s.")
end

local function aguardarPersonagemEstavel()
	local deadline = os.clock() + 60
	while Runtime.Alive and os.clock() < deadline do
		local character = esperarSpawn()
		task.wait(3)
		local humanoid, root = personagemPronto(character)
		if humanoid and root then return character, humanoid, root end
	end
	error("Personagem não estabilizou; seguindo para o rejoin.")
end

-- Mesmo webhook de inventário utilizado em KING_LEGACY/Sea_2.luau.
local FRUIT_WEBHOOK_URL = "https://discord.com/api/webhooks/1551358406344835122/jUlRuIxUAy4ZgCaPGNIMTY4c_c0gO6fhiTiM9BxMrBlgGAYZbuV8Liujechrk747HUzN"
local miticasNotificadas = {}
local notificacoesPendentes = 0

local function nomeMitica(nome)
	if type(nome) ~= "string" then return nil end
	local n = string.lower(nome):gsub("^%s+", ""):gsub("%s+$", "")
	n = n:gsub("%s+fruit$", "")
	if n == "infinity" then return "Infinity" end
	if n == "vessel" then return "Vessel" end
	return nil
end

local function notificarMitica(nome)
	local mitica = nomeMitica(nome)
	if not mitica or miticasNotificadas[mitica] then return end
	-- No máximo um aviso por tipo de fruta nesta execução.
	miticasNotificadas[mitica] = true
	notificacoesPendentes += 1
	task.spawn(function()
		pcall(function()
			local body = HttpService:JSONEncode({
				username = "AnimePiece",
				allowed_mentions = {parse = {}},
				embeds = {{
					title = "Fruta mítica encontrada",
					description = mitica,
					color = 10181046,

				}},
			})
			for tentativa = 1, 3 do
				local ok, response = pcall(function()
					return request({
						Url = FRUIT_WEBHOOK_URL,
						Method = "POST",
						Headers = {["Content-Type"] = "application/json"},
						Body = body,
					})
				end)
				if ok and response and response.StatusCode >= 200
					and response.StatusCode < 300 then return end
				if ok and response and response.StatusCode == 429 then
					local delay = 2
					pcall(function()
						delay = tonumber(HttpService:JSONDecode(response.Body).retry_after) or 2
					end)
					task.wait(math.max(delay, 1))
				elseif not ok or (response and response.StatusCode >= 500) then
					task.wait(2)
				else
					return
				end
			end
		end)
		notificacoesPendentes -= 1
	end)
end

-- Envia o relatório do período e começa um novo. Só zera depois que o Discord confirmar.
local function enviarWebhook(body)
    if type(request)~="function" then return false,"Executor sem request" end
    for _=1,3 do
        local ok,response=pcall(function()
            return request({Url=FRUIT_WEBHOOK_URL,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
        end)
        if ok and response and response.StatusCode>=200 and response.StatusCode<300 then return true end
        if ok and response and response.StatusCode==429 then
            local delay=2
            pcall(function() delay=tonumber(HttpService:JSONDecode(response.Body).retry_after) or 2 end)
            task.wait(math.max(delay,1))
        elseif not ok or (response and response.StatusCode>=500) then
            task.wait(2)
        else
            return false,"HTTP "..tostring(response and response.StatusCode)
        end
    end
    return false,"Sem resposta do Discord"
end
function Report.Send(manual)
    if Report.Sending then return end
    Report.Sending=true
    local s=Report.State
    local minutos=math.max(1,math.floor((os.time()-s.Start)/60))
    local function campo(texto) return #texto>1000 and texto:sub(1,997).."..." or texto end
    local body=HttpService:JSONEncode({
        username="AnimePiece",
        allowed_mentions={parse={}},
        embeds={{
            title="Relatório de farm — "..minutos.." min",
            description="Conta: **"..player.Name.."**"..(manual and " (envio manual)" or ""),
            color=3447003,
            fields={
                {name="🌐 Servidores visitados",value=tostring(s.Servers),inline=true},
                {name="🍈 Frutas coletadas",value=tostring(Report.Soma(s.Collected)),inline=true},
                {name="🚫 Frutas ignoradas",value=tostring(Report.Soma(s.Ignored)),inline=true},
                {name="Coletadas",value=campo(Report.Linhas(s.Collected))},
                {name="Ignoradas",value=campo(Report.Linhas(s.Ignored))},
            },
            timestamp=DateTime.now():ToIsoDate(),
        }},
    })
    local ok,err=enviarWebhook(body)
    Report.Sending=false
    if ok then
        Report.Reset()
        if Report.StatusLabel then pcall(function() Report.StatusLabel:SetText("Último envio: "..os.date("%H:%M").." ✓") end) end
    else
        -- Mantém os dados para tentar de novo em 5 minutos.
        Report.RetryAt=os.time()+300
        if Report.StatusLabel then pcall(function() Report.StatusLabel:SetText("Falha no envio ("..tostring(err).."); nova tentativa em 5 min.") end) end
    end
end
task.spawn(function()
    while Runtime.Alive do
        Report.Refresh()
        local due=os.time()-Report.State.Start>=Report.Interval*60
        if Report.Enabled and due and os.time()>=(Report.RetryAt or 0) then pcall(Report.Send,false) end
        task.wait(30)
    end
end)

local function verificarMiticaHandle(handle)
	local atual = handle
	while atual and atual ~= droppedTools do
		notificarMitica(atual.Name)
		for _, atributo in ipairs({"FruitName", "ItemName", "Fruit"}) do
			notificarMitica(atual:GetAttribute(atributo))
			local valor = atual:FindFirstChild(atributo)
			if valor and valor:IsA("StringValue") then notificarMitica(valor.Value) end
		end
		atual = atual.Parent
	end
	local prompt = handle:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then notificarMitica(prompt.ObjectText) end
end

local FRUTAS_BLOQUEADAS = {
	kilo = true,
	copy = true,
	warrior = true,
	bomb = true,
}

local function nomeBloqueado(nome)
	if type(nome) ~= "string" then return false end
	local normalizado = string.lower(nome):gsub("^%s+", ""):gsub("%s+$", "")
	normalizado = normalizado:gsub("%s+fruit$", "")
	return FRUTAS_BLOQUEADAS[normalizado] == true
end

local function identificarHandleBloqueado(handle)
	local atual = handle
	while atual and atual ~= droppedTools do
		if nomeBloqueado(atual.Name) then return true, atual.Name end
		for _, atributo in ipairs({"FruitName", "ItemName", "Fruit"}) do
			local nome = atual:GetAttribute(atributo)
			if nomeBloqueado(nome) then return true, nome end
			local valor = atual:FindFirstChild(atributo)
			if valor and valor:IsA("StringValue") and nomeBloqueado(valor.Value) then
				return true, valor.Value
			end
		end
		atual = atual.Parent
	end
	local prompt = handle:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt and nomeBloqueado(prompt.ObjectText) then
		return true, prompt.ObjectText
	end
	return false, nil
end

local blacklistAvisada = setmetatable({}, {__mode = "k"})

local function handleBloqueado(handle)
	local bloqueado, nomeFruta = identificarHandleBloqueado(handle)
	if bloqueado and blacklistAvisada[handle] ~= nomeFruta then
		blacklistAvisada[handle] = nomeFruta
		print("Fruta ignorada (blacklist): " .. nomeFruta)
		Report.Add("Ignored", nomeFruta)
	end
	return bloqueado
end

local function procurarHandle(attempted)
	for _, item in droppedTools:GetDescendants() do
		if item.Name == "Handle" and item:IsA("BasePart")
			and not (attempted and attempted[item]) then
            if not handleBloqueado(item) then verificarMiticaHandle(item) return item end
		end
	end

	return nil
end

-- Verified spawn coordinates survive streamed-out island instances.
local SPAWN_POSITIONS={
    Foosha=Vector3.new(278.1727600097656,12.344271659851074,-874.8125610351562),
    JungleIsland=Vector3.new(-853.4273071289062,12.344271659851074,80.88743591308594),
    WestIsland=Vector3.new(578.0479125976562,9.200078964233398,2876.027587890625),
    OnlineIsland=Vector3.new(3494.39208984375,38.338645935058594,2554.70263671875),
    SorcerersIsland=Vector3.new(4063.24853515625,14.25,178.9741668701172),
    ["Good House"]=Vector3.new(2805.0224609375,13.232160568237305,-2673.62744140625),
}
local function salvarLocalizacoesSpawn()
    local saved={}
    for name,position in pairs(SPAWN_POSITIONS) do saved[name]=CFrame.new(position) end
    local ignore=world and world:FindFirstChild("IgnoreList")
    local folder=ignore and ignore:FindFirstChild("Spawnpoint")
    if folder then
        for _,spawn in ipairs(folder:GetChildren()) do
            if saved[spawn.Name] and spawn:IsA("BasePart") then saved[spawn.Name]=spawn.CFrame end
        end
    end
    local result={}
    for _,name in ipairs({"Foosha","JungleIsland","WestIsland","OnlineIsland","SorcerersIsland","Good House"}) do
        table.insert(result,{Nome=name,Origem="Spawnpoint."..name,CFrame=saved[name]})
    end
    return result
end

local function ehFruta(item)
	return item:IsA("Tool")
		and string.find(string.lower(item.Name), "fruit", 1, true) ~= nil
end

local function registrarItensAtuais()
	local existentes = {}

	for _, item in backpack:GetChildren() do
		existentes[item] = true
	end

	local character = player.Character

	if character then
		for _, item in character:GetChildren() do
			existentes[item] = true
		end
	end

	return existentes
end

local function esperarNovaFruta(existentes, character)
	local deadline = os.clock() + TEMPO_COLETA

	repeat
		if not Runtime.Alive or not personagemPronto(character) then
			return nil
		end

		for _, item in backpack:GetChildren() do
			if ehFruta(item) and not existentes[item] then
				return item
			end
		end

		task.wait(0.1)
	until os.clock() >= deadline

	return nil
end

local storageTried
local function armazenarFruta(fruta, character)
	notificarMitica(fruta.Name)
	if fruta.Parent ~= backpack then
		return false
	end

	local nome = fruta.Name
    local allowed,reason=canStoreFruit(nome)
    if not allowed then Runtime.StorageStatus=reason.."; mantida na mochila" return true end
    if storageTried then storageTried[fruta]=true end

	physicalFruitsEvent:FireServer("Storage", nome)

	local deadline = os.clock() + TEMPO_STORAGE

	repeat
		if not Runtime.Alive then return false end
		local naBackpack = fruta:IsDescendantOf(backpack)
		local equipada = fruta:IsDescendantOf(character)

		if not naBackpack and not equipada then
			task.wait(1)
			return true
		end

		task.wait(0.1)
	until os.clock() >= deadline

	-- Continua para o rejoin mesmo se a fruta permanecer.
	return true
end


-- Shared economy work is serialized with the island sweep.
local storageQueue=setmetatable({}, {__mode="k"})
storageTried=setmetatable({}, {__mode="k"})
local visitedChests=setmetatable({}, {__mode="k"})
local function watchBackpack()
    if Runtime.InventoryConnection then Runtime.InventoryConnection:Disconnect() end
    local function enqueue(tool)
        if ehFruta(tool) then storageQueue[tool]=true end
    end
    Runtime.InventoryConnection=backpack.ChildAdded:Connect(enqueue)
    for _,tool in ipairs(backpack:GetChildren()) do enqueue(tool) end
end
local function flushFruitStorage()
    -- Include fruit received from chests, rolls, and manual pickups.
    for _,tool in ipairs(backpack:GetChildren()) do
        if ehFruta(tool) then storageQueue[tool]=true end
    end
    for tool in pairs(storageQueue) do
        if not Runtime.Alive then return end
        storageQueue[tool]=nil
        if tool.Parent==backpack and not storageTried[tool] then
            storageTried[tool]=true
            local allowed,reason=canStoreFruit(tool.Name)
            if not allowed then
                Runtime.StorageStatus=reason.."; mantida na mochila"
                continue
            end
            atualizarStatus("Tentando guardar: "..tool.Name)
            physicalFruitsEvent:FireServer("Storage",tool.Name)
            local deadline=os.clock()+3
            while Runtime.Alive and tool.Parent==backpack and os.clock()<deadline do task.wait(.1) end
            if tool.Parent==backpack then
                Runtime.StorageStatus="Fruta mantida na mochila; armazenamento não confirmado: "..tool.Name
            else
                Runtime.StorageStatus="Armazenada: "..tool.Name
            end
        end
    end
end
local function chestMoney()
    local ok,value=pcall(function() return getrenv()._G.GetModule("GetInfos").GetValue("Money") end)
    return ok and value or nil
end
local function isPurpleChest(chest)
    for _,name in ipairs({chest.Name,tostring(chest:GetAttribute("ChestType") or ""),tostring(chest:GetAttribute("Type") or "")}) do
        local lowered=name:lower()
        if lowered:find("purple",1,true) or lowered:find("roxo",1,true) then return true end
    end
    return false
end
local function chestAllowed(chest,money)
    return not OnlyPurpleAtMoneyCap or money and money.Value<MONEY_CAP or isPurpleChest(chest)
end
local function collectIslandChests(center,regions)
    if not AutoChestsEnabled then return end
    local folder=world.Playability:FindFirstChild("Chests")
    if not folder then return end
    local targets={}
    local money=chestMoney()
    for scanIndex,chest in ipairs(folder:GetChildren()) do
        if scanIndex%12==0 then task.wait() end
        if not Runtime.Alive or not AutoChestsEnabled then return end
        if chest:IsA("Model") and os.clock()>=(visitedChests[chest] or 0) and chestAllowed(chest,money) then
            local hit=chest:FindFirstChild("Hitbox") or chest.PrimaryPart
            if hit and hit:IsA("BasePart") then
                local closest,minimum=nil,math.huge
                for _,region in ipairs(regions or {}) do
                    local distance=(hit.Position-region.CFrame.Position).Magnitude
                    if distance<minimum then closest,minimum=region.CFrame.Position,distance end
                end
                local sameRegion=closest and (closest-center).Magnitude<1
                    or not closest and (hit.Position-center).Magnitude<=1000
                if sameRegion then
                    local visible={}
                    for _,part in ipairs(chest:GetDescendants()) do
                        if part:IsA("BasePart") and part~=hit and part.Transparency<.95 then table.insert(visible,part) end
                    end
                    if #visible>0 then table.insert(targets,{Chest=chest,Hit=hit,Visible=visible}) end
                end
            end
        end
    end
    table.sort(targets,function(a,b)
        local ap,bp=isPurpleChest(a.Chest),isPurpleChest(b.Chest)
        if ap~=bp then return ap end
        return (a.Hit.Position-center).Magnitude<(b.Hit.Position-center).Magnitude
    end)
    local islandDeadline=os.clock()+35
    for index,target in ipairs(targets) do
        if not Runtime.Alive or not AutoChestsEnabled or Runtime.FruitScanRequested or os.clock()>=islandDeadline then break end
        local chest,hit=target.Chest,target.Hit
        if chest.Parent and hit.Parent and chestAllowed(chest,money) then
            visitedChests[chest]=os.clock()+30
            atualizarStatus("Coletando baú "..index.."/"..#targets..": "..chest.Name)
            local character,_,root=esperarSpawn()
            money=chestMoney()
            if not chestAllowed(chest,money) then continue end
            local beforeMoney=money and money.Value
            local visible=target.Visible
            local collected=false
            local anchored=root.Anchored
            local safeCFrame=root.CFrame
            local collisions={}
            local restored=false
            local function restoreChestMovement()
                if restored then return end
                restored=true
                -- Sai da geometria antes de reativar as colisões do personagem.
                if root.Parent then
                    root.CFrame=safeCFrame
                    root.AssemblyLinearVelocity=Vector3.zero
                    root.AssemblyAngularVelocity=Vector3.zero
                    root.Anchored=anchored
                end
                for part,canCollide in pairs(collisions) do
                    if part.Parent then part.CanCollide=canCollide end
                end
            end
            Runtime.CancelChestMovement=restoreChestMovement
            Runtime.ChestPhase="Coletando "..chest.Name
            print("Baús | Iniciando:",chest.Name,"| saldo:",beforeMoney or "indisponível")
            local ok,err=pcall(function()
            for _,part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    collisions[part]=part.CanCollide
                    part.CanCollide=false
                end
            end
            for attempt=1,2 do
                if not Runtime.Alive or not AutoChestsEnabled or not hit.Parent or not personagemPronto(character)
                    or os.clock()>=islandDeadline then break end
                root.Anchored=false
                -- Sobreposição física: não mistura toque natural com firetouchinterest.
                root.CFrame=hit.CFrame*CFrame.new(0,math.min(1,hit.Size.Y*.25),0)
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
                task.wait(.4)
                local deadline=math.min(os.clock()+2.5,islandDeadline)
                repeat
                    if not chest.Parent or not hit.Parent or money and beforeMoney and money.Value>beforeMoney then collected=true end
                    for _,part in ipairs(visible) do
                        if not part.Parent or part.Transparency>=.95 then collected=true end
                    end
                    if collected then break end
                    task.wait(.15)
                until not Runtime.Alive or not AutoChestsEnabled or not personagemPronto(character) or os.clock()>=deadline
                if root.Parent and hit.Parent and personagemPronto(character) then
                    root.CFrame=hit.CFrame*CFrame.new(4,2,0)
                    root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
                end
                if collected then break end
                task.wait(.8)
            end
            end)
            restoreChestMovement()
            Runtime.CancelChestMovement=nil
            if collected then
                visitedChests[chest]=os.clock()+1200
                Runtime.ChestsCollected=(Runtime.ChestsCollected or 0)+1
                Runtime.ChestMoneyGained=(Runtime.ChestMoneyGained or 0)+math.max(0,money and beforeMoney and money.Value-beforeMoney or 0)
            else
                registrarErro("Baú",ok and ("Interação sem confirmação: "..chest.Name) or tostring(err))
            end
            Runtime.ChestPhase=nil
            print("Baús | Finalizado:",chest.Name,"| confirmado:",collected)
            if not personagemPronto(character) then break end
            Runtime.ChestsVisited=(Runtime.ChestsVisited or 0)+1
            pcall(function()
                if Runtime.ChestCountLabel then
                    Runtime.ChestCountLabel:SetText("Baús confirmados: "..tostring(Runtime.ChestsCollected or 0).." | Visitados: "..Runtime.ChestsVisited)
                end
                if Runtime.ChestMoneyLabel then
                    Runtime.ChestMoneyLabel:SetText("Dinheiro dos baús: $"..tostring(Runtime.ChestMoneyGained or 0))
                end
            end)
            task.wait(1.2)
        end
    end
end
local spinCache="AnimePiece_LastFruitSpin_"..tostring(player.UserId)..".json"
local spinRecord={LastSuccess=0,LastAttempt=0}
pcall(function()
    if type(isfile)=="function" and isfile(spinCache) then
        local saved=HttpService:JSONDecode(readfile(spinCache))
        if type(saved)=="table" then
            spinRecord.LastSuccess=tonumber(saved.LastSuccess) or 0
            spinRecord.LastAttempt=tonumber(saved.LastAttempt) or 0
        end
    end
end)
local function saveSpinRecord()
    pcall(function() if type(writefile)=="function" then writefile(spinCache,HttpService:JSONEncode(spinRecord)) end end)
end
local function economyGameCall(callback)
    local getId=getthreadidentity or getidentity
    local setId=setthreadidentity or setidentity
    local previous=getId and getId()
    if setId then setId(2) end
    local result=table.pack(pcall(callback))
    if previous and setId then setId(previous) end
    if not result[1] then error(result[2]) end
    return table.unpack(result,2,result.n)
end
local chegarNaIlha
local function storedFruitSnapshot()
    local global=getrenv()._G
    local items=global and global.ClientInventory and global.ClientInventory.Items and global.ClientInventory.Items.Fruits
    local counts={}
    for _,item in pairs(items or {}) do counts[item.Name]=(counts[item.Name] or 0)+(tonumber(item.Amount) or 1) end
    return counts
end
local function waitSpinDelivery()
    local ticket=Runtime.SpinTicket
    if not ticket then return end
    Runtime.SpinBusy=true
    local event=ReplicatedStorage.Remotes:FindFirstChild("Fruit Gacha")
    local connection=event and event.OnClientEvent:Connect(function(name) ticket.Response=name end)
    Runtime.SpinConnection=connection
    local delivered
    local deadline=os.clock()+90
    while Runtime.Alive and not Runtime.CancelSpin and AutoFruitSpinEnabled do
        local character=player.Character
        for _,folder in ipairs({backpack,character or backpack}) do
            for _,tool in ipairs(folder:GetChildren()) do
                if ehFruta(tool) and not ticket.Tools[tool] then delivered=tool.Name break end
            end
            if delivered then break end
        end
        for name,count in pairs(storedFruitSnapshot()) do
            if count>(ticket.Stored[name] or 0) then delivered=name break end
        end
        if delivered then break end
        if os.clock()>=deadline then
            ticket.TimedOut=true
            break
        end
        Runtime.SpinStatus="Aguardando entrega da fruta; varredura e rejoin pausados."
        atualizarStatus(Runtime.SpinStatus)
        task.wait(.2)
    end
    if connection then connection:Disconnect() end
    Runtime.SpinConnection=nil Runtime.SpinBusy=false
    if delivered then
        spinRecord.LastSuccess=os.time() saveSpinRecord()
        Runtime.SpinStatus="Fruta confirmada: "..delivered
        Runtime.SpinTicket=nil
        flushFruitStorage()
    elseif Runtime.Alive then
        Runtime.SpinTicket=nil
        Runtime.SpinStatus=ticket.TimedOut and "Roll sem entrega confirmada em 90s; rejoin liberado e novos giros bloqueados nesta execução."
            or "Espera do roll cancelada; nenhuma nova tentativa nesta execução."
        warn("Main |",Runtime.SpinStatus)
        Runtime.SpinCancelled=true
    end
end
local function tryHourlyFruitSpin()
    if Runtime.SpinTicket then waitSpinDelivery() return end
    if not AutoFruitSpinEnabled or not Runtime.Alive then return end
    if Runtime.SpinCancelled then return end
    local now=os.time()
    if now-spinRecord.LastSuccess<3600 or now-spinRecord.LastAttempt<60 then return end
    local global=getrenv()._G
    if not global or not global.GetModule then return end
    local info=economyGameCall(function() return global.GetModule("GetInfos") end)
    local stats=economyGameCall(function() return info.GetStats() end)
    local level=economyGameCall(function() return info.GetLevel() end)
    if not stats or level<50 then return end
    local infos=stats:FindFirstChild("Infos")
    local cooldown=infos and infos:FindFirstChild("LastFruitTimeSpin")
    if cooldown and cooldown.Value>0 then
        Runtime.SpinStatus="Giro aguardando cooldown: "..tostring(cooldown.Value).."s"
        return
    end
    local money=infos and infos:FindFirstChild("Money")
    local price=economyGameCall(function()
        return global.GetModule("GetFruitGachaPrice").GetPrice(level,player:GetAttribute("FirstFruitSpin") and true or false)
    end)
    if not money or money.Value<price then Runtime.SpinStatus="Saldo insuficiente para giro: $"..tostring(price) return end
    local npc=Runtime.FruitSpinNpc
    if npc and not npc.Parent then npc=nil end
    for _,folder in ipairs({interactive,ReplicatedStorage}) do
        if npc then break end
        local model=folder:FindFirstChild("Luzefe",true)
        if model and model:IsA("Model") and model:FindFirstChildWhichIsA("BasePart",true) then npc=model end
        task.wait()
    end
    Runtime.FruitSpinNpc=npc
    if not npc then Runtime.SpinStatus="Luzefe não carregado nesta ilha" return end
    local point=npc:GetPivot().Position
    if not chegarNaIlha({Nome="Luzefe",CFrame=CFrame.new(point+Vector3.new(0,4,4))},1,1) then return end
    task.wait(1)
    if not Runtime.Alive or not AutoFruitSpinEnabled then return end
    spinRecord.LastAttempt=os.time()
    saveSpinRecord()
    -- A confirmação depende da entrega; débito e cooldown não provam recebimento.
    Runtime.CancelSpin=false
    Runtime.SpinTicket={Tools=registrarItensAtuais(),Stored=storedFruitSnapshot(),RequestedAt=os.time()}
    atualizarStatus("Girando fruta com dinheiro do jogo: $"..price)
    ReplicatedStorage.Remotes["Dialogue Event"]:FireServer({"SpinFruit",""})
    waitSpinDelivery()
end
Runtime.FlushFruitStorage=flushFruitStorage
Runtime.TryHourlyFruitSpin=tryHourlyFruitSpin
Runtime.CollectIslandChests=collectIslandChests

local function coletarHandle(handle)
	if handleBloqueado(handle) then
		return false
	end
	local character, humanoid, root = esperarSpawn()

	if not handle:IsDescendantOf(droppedTools) then
		return false
	end
    local function valid()
        return Runtime.Alive and personagemPronto(character) and handle:IsDescendantOf(droppedTools)
    end
    local function waitFruit(seconds)
        local deadline=os.clock()+seconds
        while valid() and os.clock()<deadline do task.wait(.1) end
        return valid()
    end
    atualizarStatus("Pausando antes de buscar a fruta...")
    if not waitFruit(FRUIT_HANDOFF_WAIT) then return false end
    local nearest,distance
    local spawns=salvarLocalizacoesSpawn()
    for _,spawn in ipairs(spawns) do
        local d=(root.Position-spawn.CFrame.Position).Magnitude
        if not distance or d<distance then nearest,distance=spawn,d end
    end
    assert(nearest,"Nenhum spawn seguro disponível para a coleta.")
    if not chegarNaIlha(nearest,1,#spawns) or not waitFruit(1) then return false end
    local originalAnchored=root.Anchored
    local function cleanup()
        if Runtime.Tween then pcall(function() Runtime.Tween:Cancel() end) Runtime.Tween=nil end
        for _,connection in ipairs(Runtime.FarmConnections or {}) do pcall(function() connection:Disconnect() end) end
        Runtime.FarmConnections={}
        if root.Parent then
            root.Anchored=originalAnchored
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
        end
    end
    Runtime.CancelFruitMovement=cleanup
    local ok,result=pcall(function()
    -- Mantém a fruta estável antes de calcular a aproximação.
    local stableAt=os.clock()
    local lastPosition=handle.Position
    local stableDeadline=os.clock()+5
    repeat
        if not valid() then return false end
        if (handle.Position-lastPosition).Magnitude>.75 then lastPosition=handle.Position stableAt=os.clock() end
        task.wait(.1)
    until os.clock()-stableAt>=.4 or os.clock()>=stableDeadline
    assert(os.clock()-stableAt>=.4,"Fruta ainda em movimento; coleta adiada.")
    local initialDistance=(root.Position-handle.Position).Magnitude
    root.Anchored=true
    if initialDistance>50 then
        atualizarStatus("Aproximando até 50 studs da fruta...")
        local delta=root.Position-handle.Position
        local horizontal=Vector3.new(delta.X,0,delta.Z)
        local direction=horizontal.Magnitude>0 and horizontal.Unit or Vector3.xAxis
        root.CFrame=CFrame.new(handle.Position+direction*math.sqrt(50*50-8*8)+Vector3.new(0,8,0))*root.CFrame.Rotation
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        task.spawn(function() pcall(function() player:RequestStreamAroundAsync(handle.Position,5) end) end)
        if not waitFruit(FRUIT_ARRIVAL_WAIT) then return false end
        assert((root.Position-handle.Position).Magnitude<=55,"A aproximação de 50 studs não se manteve; tween cancelado.")
    elseif not waitFruit(FRUIT_ARRIVAL_WAIT) then return false
    end
    local target = handle.Position + Vector3.new(3, 0, 0)
	local duration = math.max(
		(root.Position - target).Magnitude / VELOCIDADE_TWEEN,
		0.1
	)

	if duration > 30 then error("Handle distante demais para um trajeto de até 30s.") end
    Runtime.LastFruitMove={InitialDistance=initialDistance,ApproachDistance=(root.Position-handle.Position).Magnitude,Speed=VELOCIDADE_TWEEN,Duration=duration}
	local tween = TweenService:Create(
		root,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{
			CFrame = CFrame.new(target) * root.CFrame.Rotation,
		}
	)

	local deathConnection = humanoid.Died:Connect(function()
		tween:Cancel()
	end)

	local characterConnection = player.CharacterRemoving:Connect(function(removed)
		if removed == character then
			tween:Cancel()
		end
	end)

	Runtime.Tween = tween
	Runtime.FarmConnections = {deathConnection, characterConnection}
	local finished = false
	local state
	local completedConnection = tween.Completed:Connect(function(playbackState)
		state = playbackState
		finished = true
	end)
	table.insert(Runtime.FarmConnections, completedConnection)
    root.Anchored=false
	tween:Play()
	local deadline = os.clock() + duration + 3
	while valid() and not finished and os.clock() < deadline do task.wait(0.1) end
	if not finished then tween:Cancel() end
	completedConnection:Disconnect()

	deathConnection:Disconnect()
	characterConnection:Disconnect()
	Runtime.Tween = nil
	Runtime.FarmConnections = {}

	if state ~= Enum.PlaybackState.Completed
		or not personagemPronto(character) then
		return false
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

    root.Anchored=true
    atualizarStatus("Ao lado da fruta: aguardando antes de coletar...")
    if not waitFruit(FRUIT_PICKUP_WAIT) then return false end

	if not handle:IsDescendantOf(droppedTools)
		or not personagemPronto(character) then
		return false
	end

	local prompt = handle:FindFirstChildWhichIsA("ProximityPrompt", true)

	if not prompt or not prompt.Enabled then
		return false
	end

	local promptPosition = handle.Position
	local parent = prompt.Parent

	if parent and parent:IsA("Attachment") then
		promptPosition = parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		promptPosition = parent.Position
	end

	if (root.Position - promptPosition).Magnitude > prompt.MaxActivationDistance then
		return false
	end

	local existentes = registrarItensAtuais()

	if handleBloqueado(handle) then return false end
    local prompted,promptError=executarComLimite(math.max(3,prompt.HoldDuration+1),function()
        if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            local completed=waitFruit(prompt.HoldDuration+.1)
            if prompt.Parent then prompt:InputHoldEnd() end
            assert(completed,"Coleta interrompida.")
        end
    end)
    assert(prompted,promptError)


	local fruta = esperarNovaFruta(existentes, character)

	if not fruta then
		return false
	end
	Report.Add("Collected", fruta.Name)

	return armazenarFruta(fruta, character)
    end)
    cleanup()
    Runtime.CancelFruitMovement=nil
    if not ok then error(result,0) end
    return result
end

-- BEGIN SERVER CONTROLLER
local ServerController=(function()
-- Pure Lua controller. Main.lua embeds this module so the executor needs one file.
local Controller = {}
Controller.__index = Controller

function Controller.new(jobId, visited, failed)
    return setmetatable({JobId=jobId, Visited=visited or {}, Failed=failed or {},
        Queue={}, Cursor=nil, Cursors={}, Fallback=nil, Current=nil, Query=nil,
        Sequence=0, NextQuery=0, ReadyAt=0, Unavailable=0, Retry=false,
        Phase="Idle", Message="Pronto para buscar outro servidor."}, Controller)
end

function Controller:prune(epoch)
    for _, records in ipairs({self.Visited, self.Failed}) do
        local ordered={}
        for id, at in pairs(records) do
            if type(id)~="string" or type(at)~="number" or at~=at or at>epoch or epoch-at>=900 then
                records[id]=nil
            else
                ordered[#ordered+1]={Id=id, At=at}
            end
        end
        table.sort(ordered,function(a,b) return a.At>b.At end)
        for i=201,#ordered do records[ordered[i].Id]=nil end
    end
end

function Controller:remove(id)
    self.Visited[id]=nil
    for i=#self.Queue,1,-1 do
        if self.Queue[i]==id then table.remove(self.Queue,i) end
    end
    if self.Fallback and self.Fallback.Id==id then self.Fallback=nil end
end

function Controller:reset(epoch)
    self.Queue={} self.Visited={} self.Failed={}
    self.Cursor=nil self.Cursors={} self.Fallback=nil self.Query=nil
    self.Visited[self.JobId]=epoch
    self.Unavailable=0
end

function Controller:begin(id, kind, now)
    if self.Current or self.Phase=="Uncertain" then return false end
    self.Sequence=self.Sequence+1
    self.Current={Id=id, Kind=kind or "Search", Token=self.Sequence,
        SendAt=now+(self.Retry and 0 or 1)}
    self.Phase="Preparing"
    self.Retry=false
    return true
end

function Controller:cancelPreparing()
    if self.Phase~="Preparing" then return false end
    self.Current=nil self.Phase="Idle"
    return true
end

function Controller:failure(message, now)
    local current=self.Current
    if (self.Phase~="Waiting" and self.Phase~="Uncertain") or not current then return false end
    self.Phase="Waiting"
    -- Both Roblox events describe one attempt. Keep one failure, prefer its details.
    if not current.Failure or message~="TeleportState.Failed" then current.Failure=tostring(message) end
    current.FailureAt=current.FailureAt or now
    return true
end

function Controller:progress()
    if self.Current and self.Phase=="Waiting" then self.Current.InProgress=true end
end

function Controller:queryResult(query, result, now, epoch)
    if self.Query~=query then return end
    self.Query=nil
    if not result.Ok then
        local delay=math.max(30,tonumber(result.RetryAfter) or 0)
        self.NextQuery=math.max(self.NextQuery,now+delay)
        self.Message=result.Error or "Falha ao consultar servidores."
        return
    end
    self:prune(epoch)
    local seen={}
    for _,server in ipairs(result.Servers or {}) do
        local id=server.id
        if type(id)=="string" and id~="" and id~=self.JobId and not self.Failed[id]
            and type(server.playing)=="number" and type(server.maxPlayers)=="number"
            and server.playing<server.maxPlayers and not seen[id] then
            seen[id]=true
            local visited=self.Visited[id]
            if not visited and #self.Queue<100 then
                self.Queue[#self.Queue+1]=id
            elseif visited and (not self.Fallback or visited<self.Fallback.At) then
                self.Fallback={Id=id,At=visited}
            end
        end
    end
    local cursor=result.Cursor
    if type(cursor)~="string" or cursor=="" or self.Cursors[cursor] then cursor=nil end
    self.Cursor=cursor
    if cursor then self.Cursors[cursor]=true end
    if not cursor then
        if #self.Queue==0 and self.Fallback then self.Queue[1]=self.Fallback.Id end
        self.Fallback=nil self.Cursors={}
    end
    -- Consulta bem-sucedida: a próxima página não precisa esperar 30 s se esta não trouxe destino novo.
    self.NextQuery=now+(cursor and 2 or 10)
    self.Message="Lista recebida: "..#self.Queue.." destino(s) disponível(is)."
end

function Controller:step(now, epoch, allowSearch)
    local current=self.Current
    if current then
        if self.Phase=="Preparing" then
            if now<current.SendAt then
                self.Message="Enviando teleporte em "..math.ceil(current.SendAt-now).."s."
                return
            end
            current.StartedAt=now
            self.Phase="Waiting"
            self.Message="Teleporte enviado; aguardando Roblox."
            return {Type="Teleport",Attempt=current}
        end
        if self.Phase=="Waiting" then
            if current.Failure and now-current.FailureAt>=0.25 then
                local message=current.Failure
                self.Current=nil self.Phase="Backoff" self.ReadyAt=now+5 self.Retry=true
                self:remove(current.Id)
                self.Failed[current.Id]=epoch
                local lower=message:lower()
                local unavailable=lower:find("server is no longer available",1,true)
                    or lower:find("server is no longer avaiable",1,true)
                    or lower:find("gameended",1,true)
                    or lower:find("could not find requested game instance",1,true)
                if unavailable then self.Unavailable=self.Unavailable+1 end
                local reset=self.Unavailable>=3
                if reset then self:reset(epoch) end
                self.Message="Falha confirmada. Nova tentativa em 5s."
                return {Type="Failure",Attempt=current,Message=message,Reset=reset}
            end
            if now-current.StartedAt>=60 then
                self.Phase="Uncertain"
                self.Message="Roblox não concluiu o teleporte em 60s. Trocas suspensas; reinicie o client."
                return {Type="Uncertain",Attempt=current}
            end
            self.Message="Aguardando resultado do teleporte ("..math.floor(now-current.StartedAt).."s)."
        end
        return
    end
    if now<self.ReadyAt then
        self.Message="Nova tentativa em "..math.ceil(self.ReadyAt-now).."s."
        return
    end
    self.Phase="Idle"
    if not allowSearch then return end
    self:prune(epoch)
    while #self.Queue>0 do
        local id=table.remove(self.Queue)
        if id~=self.JobId and not self.Failed[id] then
            self:begin(id,"Search",now)
            return self:step(now,epoch,allowSearch)
        end
    end
    if self.Query then
        if now-self.Query.StartedAt>=25 then
            self.Query=nil self.NextQuery=now+30
            self.Message="Consulta sem resposta em 25s; aguardando 30s."
            return {Type="QueryTimeout"}
        end
        self.Message="Consultando servidores públicos..."
        return
    end
    if now<self.NextQuery then
        self.Message="Sem destino em cache. Nova consulta em "..math.ceil(self.NextQuery-now).."s."
        return
    end
    self.Sequence=self.Sequence+1
    self.Query={Token=self.Sequence,StartedAt=now,Cursor=self.Cursor}
    self.NextQuery=now+30
    self.Message="Consultando servidores públicos..."
    return {Type="Query",Query=self.Query}
end

return Controller

end)()
local historyFile="AnimePiece_ServerHistory_"..game.PlaceId.."_"..player.UserId..".json"
local Hop=ServerController.new(game.JobId)
Runtime.ServerController=Hop
Runtime.ServerTrace={}
Runtime.DiagnosticFile="AnimePiece_MainDiagnostic_"..player.UserId..".json"
Runtime.GetServerDiagnostic=function()
    local active=Hop.Current
    return {
        Version=Runtime.Version,Phase=Hop.Phase,Status=Runtime.LastStatus,
        Block=Runtime.RejoinBlockReason,Destination=active and active.Id,
        AttemptAge=active and active.StartedAt and math.floor(os.clock()-active.StartedAt),
        QueryAge=Hop.Query and math.floor(os.clock()-Hop.Query.StartedAt),Queue=#Hop.Queue,
        FarmDone=Runtime.FarmDone,AutoRejoin=AutoRejoinEnabled,
        SpinBusy=Runtime.SpinBusy==true,SpinPending=Runtime.SpinTicket~=nil,
        DeliveryEnabled=Delivery.Enabled,DeliveryPending=Delivery.State.Pending~=nil,
        DeliveryError=Delivery.Error,LastRobloxEvent=Runtime.LastTeleportEvent,
        Controller=Runtime.ControllerThread and coroutine.status(Runtime.ControllerThread),
        Trace=Runtime.ServerTrace,
    }
end
local function traceServer(reason)
    local records=Runtime.ServerTrace
    records[#records+1]={Time=os.time(),Event=reason}
    if #records>30 then table.remove(records,1) end
    print("Main | Etapa:",reason)
    if type(writefile)=="function" then
        pcall(function() writefile(Runtime.DiagnosticFile,HttpService:JSONEncode(Runtime.GetServerDiagnostic())) end)
    end
end
local function saveServerHistory()
    Hop:prune(os.time())
    if type(writefile)~="function" then Runtime.ServerHistoryStatus="Histórico somente nesta execução." return end
    local ok,err=pcall(function()
        writefile(historyFile,HttpService:JSONEncode({Version=2,Visited=Hop.Visited,Failed=Hop.Failed}))
    end)
    Runtime.ServerHistoryStatus=ok and "Histórico salvo. Validade: 15 minutos." or "Falha ao salvar histórico: "..tostring(err)
end
-- Lista compartilhada entre todos os clients do mesmo executor (mesmo workspace).
local Shared={Folder="AnimePiece",File="AnimePiece/ServidoresCompartilhados_"..game.PlaceId..".json",
    VisitTTL=900,ClaimTTL=90,QueueTTL=120,NextPull=0}
local function sharedRead()
    local data
    pcall(function()
        if type(isfile)=="function" and isfile(Shared.File) then
            local raw=readfile(Shared.File)
            if type(raw)=="string" and #raw<=262144 then data=HttpService:JSONDecode(raw) end
        end
    end)
    if type(data)~="table" then data={} end
    for _,key in ipairs({"Visited","Failed","Claims"}) do if type(data[key])~="table" then data[key]={} end end
    if type(data.Queue)~="table" then data.Queue={} end
    data.QueueAt=tonumber(data.QueueAt) or 0
    return data
end
local function sharedPrune(data,epoch)
    for id,at in pairs(data.Visited) do if type(at)~="number" or epoch-at>=Shared.VisitTTL then data.Visited[id]=nil end end
    for id,at in pairs(data.Failed) do if type(at)~="number" or epoch-at>=Shared.VisitTTL then data.Failed[id]=nil end end
    for id,claim in pairs(data.Claims) do
        if type(claim)~="table" or type(claim.Until)~="number" or claim.Until<=epoch then data.Claims[id]=nil end
    end
    if epoch-data.QueueAt>=Shared.QueueTTL then data.Queue={} end
    local clean={}
    for _,id in ipairs(data.Queue) do
        if type(id)=="string" and not data.Visited[id] and not data.Failed[id] and not data.Claims[id] and #clean<100 then clean[#clean+1]=id end
    end
    data.Queue=clean
end
-- Lê, aplica a mudança e grava logo em seguida, para não sobrescrever o que outro client acabou de gravar.
local function sharedUpdate(mutate)
    if type(writefile)~="function" then return end
    local ok,err=pcall(function()
        if type(isfolder)=="function" and type(makefolder)=="function" and not isfolder(Shared.Folder) then makefolder(Shared.Folder) end
        local epoch=os.time()
        local data=sharedRead()
        sharedPrune(data,epoch)
        if mutate then mutate(data,epoch) end
        writefile(Shared.File,HttpService:JSONEncode(data))
    end)
    if not ok then warn("Main | Lista compartilhada:",err) end
end
-- Traz para este client o que os outros já visitaram, reservaram ou consultaram.
local function sharedPull(force)
    if not force and os.clock()<Shared.NextPull then return end
    Shared.NextPull=os.clock()+2
    local epoch=os.time()
    local data=sharedRead()
    sharedPrune(data,epoch)
    for id,at in pairs(data.Visited) do
        if not Hop.Visited[id] or Hop.Visited[id]<at then Hop.Visited[id]=at end
    end
    for id,at in pairs(data.Failed) do Hop.Failed[id]=Hop.Failed[id] or at end
    local blocked={}
    for id,claim in pairs(data.Claims) do if claim.UserId~=player.UserId then blocked[id]=true end end
    for i=#Hop.Queue,1,-1 do
        local id=Hop.Queue[i]
        -- O último item pode ser o fallback (servidor já visitado escolhido de propósito); ele é mantido.
        if blocked[id] or Hop.Failed[id] or data.Visited[id] and #Hop.Queue>1 then table.remove(Hop.Queue,i) end
    end
    if #Hop.Queue==0 and not Hop.Query then
        local seen={}
        for _,id in ipairs(Hop.Queue) do seen[id]=true end
        for _,id in ipairs(data.Queue) do
            if id~=game.JobId and not blocked[id] and not seen[id] and not Hop.Visited[id] and not Hop.Failed[id] then
                table.insert(Hop.Queue,1,id) seen[id]=true
            end
        end
    end
end
Runtime.SharedServers=Shared

do
    local ok,err=pcall(function()
        if type(isfile)~="function" or type(readfile)~="function" or not isfile(historyFile) then return end
        local raw=readfile(historyFile)
        assert(#raw<=65536,"Histórico antigo muito grande; iniciando novo.")
        local data=HttpService:JSONDecode(raw)
        assert(type(data)=="table","Histórico inválido.")
        if type(data.Visited)=="table" then Hop.Visited=data.Visited end
        if type(data.Failed)=="table" then Hop.Failed=data.Failed end
    end)
    if not ok then warn("Main | Histórico:",err) end
end
local function registrarServidorAtual()
    if Delivery.State.Pending and Delivery.State.Pending.Target==game.JobId then return end
    if Delivery.JobId==game.JobId then return end
    Hop.Visited[game.JobId]=os.time()
    saveServerHistory()
    Report.Add("Server")
    sharedUpdate(function(data,epoch)
        data.Visited[game.JobId]=epoch
        data.Claims[game.JobId]=nil
    end)
end
local function refreshSavedServers()
    if not Runtime.SavedServersList then return end
    Hop:prune(os.time())
    local rows={}
    for id,at in pairs(Hop.Visited) do rows[#rows+1]={Id=id,At=at} end
    table.sort(rows,function(a,b) return a.At>b.At end)
    local pages=math.max(1,math.ceil(#rows/8))
    local page=math.clamp(Runtime.ServerListPage or 1,1,pages)
    Runtime.ServerListPage=page
    local lines={}
    for i=(page-1)*8+1,math.min(page*8,#rows) do
        local row=rows[i]
        lines[#lines+1]=(row.Id==game.JobId and "📍 Atual: " or "Visitado: ")..row.Id
    end
    if #lines==0 then lines[1]="Nenhum servidor no histórico." end
    local getId=getthreadidentity or getidentity
    local setId=setthreadidentity or setidentity
    local identity=getId and getId()
    if setId then setId(7) end
    local ok,err=pcall(function()
        Runtime.SavedServersSummary:SetText("Visitados: "..#rows.." | Destinos em fila: "..#Hop.Queue)
        Runtime.SavedServersList:SetText(table.concat(lines,"\n\n"))
        Runtime.SavedServersPage:SetText("Página "..page.." / "..pages)
        Runtime.SavedServersStorage:SetText(Runtime.ServerHistoryStatus or "Histórico local carregado.")
    end)
    if identity and setId then setId(identity) end
    if not ok then Runtime.ServerListError=tostring(err) end
end
Runtime.RefreshSavedServers=refreshSavedServers
local function syncServerState()
    local active=Hop.Current
    Runtime.ServerRequestSent=active~=nil and (Hop.Phase=="Waiting" or Hop.Phase=="Uncertain")
    Runtime.TeleportCallPending=active~=nil
    Runtime.TeleportUncertain=Hop.Phase=="Uncertain"
    Runtime.TeleportDestination=active and active.Id or nil
end
local function stepServers(allowSearch)
    if allowSearch and not Hop.Current then sharedPull() end
    local action=Hop:step(os.clock(),os.time(),allowSearch)
    syncServerState()
    -- Reserva o destino assim que ele é escolhido, para outro client não ir para o mesmo servidor.
    local chosen=Hop.Current
    if chosen and chosen.Kind=="Search" and not chosen.SharedClaim then
        chosen.SharedClaim=true
        sharedUpdate(function(data,epoch)
            data.Claims[chosen.Id]={UserId=player.UserId,Until=epoch+Shared.ClaimTTL}
        end)
    end
    if not action then return end
    traceServer(action.Type)
    if action.Type=="Query" then
        local query=action.Query
        Runtime.HttpThread=task.spawn(function()
            local ok,result=pcall(function()
                local url="https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=100"
                if query.Cursor then url=url.."&cursor="..HttpService:UrlEncode(query.Cursor) end
                local response=request({Url=url,Method="GET",Timeout=20})
                assert(type(response)=="table","Resposta HTTP inválida.")
                if response.StatusCode==429 then
                    local waitSeconds=30
                    for key,value in pairs(response.Headers or {}) do
                        if tostring(key):lower()=="retry-after" then waitSeconds=math.max(waitSeconds,tonumber(value) or 0) end
                    end
                    return {Ok=false,RetryAfter=waitSeconds,Error="Roblox limitou as consultas HTTP."}
                end
                assert(response.StatusCode==200,"HTTP "..tostring(response.StatusCode))
                assert(type(response.Body)=="string" and #response.Body<=524288,"Resposta HTTP muito grande ou inválida.")
                local data=HttpService:JSONDecode(response.Body)
                assert(type(data)=="table" and type(data.data)=="table","Lista de servidores inválida.")
                return {Ok=true,Servers=data.data,Cursor=data.nextPageCursor}
            end)
            if not Runtime.Alive then return end
            Hop:queryResult(query,ok and result or {Ok=false,Error=tostring(result)},os.clock(),os.time())
            if ok and result.Ok then
                -- Compartilha a lista recebida: os outros clients usam este cache em vez de consultar a API de novo.
                sharedUpdate(function(data,epoch)
                    local seen={}
                    for _,id in ipairs(data.Queue) do seen[id]=true end
                    for _,id in ipairs(Hop.Queue) do
                        if not seen[id] and #data.Queue<100 then data.Queue[#data.Queue+1]=id seen[id]=true end
                    end
                    data.QueueAt=epoch
                end)
            end
        end)
    elseif action.Type=="QueryTimeout" then
        if Runtime.HttpThread then pcall(task.cancel,Runtime.HttpThread) Runtime.HttpThread=nil end
        registrarErro("Consulta",Hop.Message)
    elseif action.Type=="Teleport" then
        local attempt=action.Attempt
        print("Main | Teleporte enviado:",attempt.Id,"|",attempt.Kind)
        Runtime.TeleportThread=task.spawn(function()
            local ok,err=pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId,attempt.Id,player)
            end)
            if not Runtime.Alive or Hop.Current~=attempt then return end
            if not ok then Hop:failure(tostring(err),os.clock()) end
        end)
    elseif action.Type=="Failure" then
        local failedId=action.Attempt.Id
        sharedUpdate(function(data,epoch)
            data.Failed[failedId]=epoch
            data.Claims[failedId]=nil
        end)
        saveServerHistory()
        pcall(refreshSavedServers)
        registrarErro("Teleporte",action.Message)
        print("Main | Servidor removido após falha:",action.Attempt.Id,"| próxima busca em 5s.")
        if action.Reset then print("Main | 3 servidores indisponíveis: lista e histórico zerados; busca pública normal.") end
        if action.Attempt.Kind=="Delivery" then
            Delivery.Error="Entrada no recebedor falhou: "..action.Message..". Entrega preservada."
            deliveryStatus(Delivery.Error)
        end
    elseif action.Type=="Uncertain" then
        registrarErro("Teleporte",Hop.Message)
        if action.Attempt.Kind=="Delivery" then Delivery.Error=Hop.Message deliveryStatus(Delivery.Error) end
    end
end
registrarServidorAtual()
pcall(refreshSavedServers)
-- END SERVER CONTROLLER

local function tratarHandle(handle)
	if coletarHandle(handle) then
		return "storage_solicitado"
	end

	return "interrompido"
end

chegarNaIlha=function(registro,index,total)
    print("Main v11 | Carregando ilha:",tostring(registro.Nome or index))
    atualizarStatus("Visitando "..tostring(registro.Nome or index).." ("..index.."/"..total.."); aguardando chão carregar.")
    local character,humanoid,root=esperarSpawn()
    if Runtime.ArrivalCharacter~=character then
        Runtime.ArrivalCharacter=character
        Runtime.ArrivalOriginalAnchored=root.Anchored
    end
    local anchored=Runtime.ArrivalOriginalAnchored
    Runtime.LastSafeCFrame=Runtime.LastSafeCFrame or root.CFrame
    local target=registro.CFrame
    root.Anchored=true
    local ok,err=pcall(function()
        root.CFrame=target
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        -- Request streaming while gravity is disabled, with a bounded wait.
        task.spawn(function()
            pcall(function() player:RequestStreamAroundAsync(target.Position,15) end)
        end)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={character,world.IgnoreList,world.Playability.Characters,world.Playability.Enemys}
        params.IgnoreWater=false
        local floor
        local deadline=os.clock()+25
        local earliest=os.clock()+TEMPO_POR_KIRO
        while Runtime.Alive and os.clock()<deadline do
            assert(personagemPronto(character),"Personagem indisponível durante o carregamento.")
            floor=nil
            for _,offset in ipairs({Vector3.zero,Vector3.new(-3,0,0),Vector3.new(-6,0,0),Vector3.new(0,0,3),Vector3.new(0,0,-3)}) do
                local hit=workspace:Raycast(target.Position+offset+Vector3.new(0,8,0),Vector3.new(0,-70,0),params)
                if hit and hit.Material~=Enum.Material.Water and
                    (hit.Instance:IsA("Terrain") or hit.Instance:IsA("BasePart") and hit.Instance.CanCollide) then
                    floor=hit break
                end
            end
            if floor and os.clock()>=earliest then break end
            task.wait(.25)
        end
        assert(Runtime.Alive,"Varredura parada.")
        assert(floor,"Piso seguro não carregou; ilha ignorada.")
        local height=humanoid.HipHeight+root.Size.Y*.5+.5
        if humanoid.RigType==Enum.HumanoidRigType.R6 then
            local leg=character:FindFirstChild("Left Leg")
            height+=leg and leg.Size.Y or 2
        end
        root.CFrame=CFrame.new(floor.Position+Vector3.new(0,height,0))*target.Rotation
        Runtime.LastSafeCFrame=root.CFrame
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
    end)
    if root.Parent then
        -- On failure, keep the character above the missing floor until the next safe arrival.
        if ok then root.Anchored=anchored else root.Anchored=true end
    end
    if not ok then registrarErro("Carregamento da ilha",err) return false end
    print("Main v11 | Piso carregado:",tostring(registro.Nome or index))
    return true
end

local function verificarLocalizacoes(fruitsOnly)
    local localizacoes=salvarLocalizacoesSpawn()
    if #localizacoes==0 then registrarErro("Busca","Nenhum spawnpoint disponível.") end
    for index,registro in ipairs(localizacoes) do
        if not Runtime.Alive then break end
        if not chegarNaIlha(registro,index,#localizacoes) then
            pcall(flushFruitStorage)
            continue
        end
        -- Fruit check always precedes chests. One visit never skips its final storage pass.
        local attempted={}
        for _=1,20 do
            if not Runtime.Alive then break end
            local handle=procurarHandle(attempted)
            if not handle then break end
            attempted[handle]=true
            local ok,err=pcall(tratarHandle,handle)
            if not ok then registrarErro("Fruta",err) end
        end
        if not fruitsOnly then
            local chestOk,chestError=pcall(collectIslandChests,registro.CFrame.Position,localizacoes)
            if not chestOk then registrarErro("Baús",chestError) end
            local spinOk,spinError=pcall(tryHourlyFruitSpin)
            if not spinOk then registrarErro("Giro",spinError) end
        end
        local storageOk,storageError=pcall(flushFruitStorage)
        if not storageOk then registrarErro("Guardar frutas",storageError) end
    end
    flushFruitStorage()
    -- Ao terminar, aguarda num spawnpoint sorteado em vez de ficar sempre na última ilha visitada.
    if Runtime.Alive and #localizacoes>0 then
        local destino=localizacoes[math.random(1,#localizacoes)]
        print("Main | Varredura concluída; aguardando em:",tostring(destino.Nome))
        local ok,err=pcall(chegarNaIlha,destino,1,1)
        if not ok then registrarErro("Spawn final",err) end
        atualizarStatus("Varredura concluída; aguardando em "..tostring(destino.Nome)..".")
    end
    return "varredura_concluida"
end

-- Roblox callbacks report events; only stepServers changes the attempt lifecycle.
local failureConnection=TeleportService.TeleportInitFailed:Connect(function(who,result,message,placeId,options)
    if who~=player or not Runtime.Alive then return end
    Runtime.LastTeleportEvent={Type="TeleportInitFailed",Result=tostring(result),Message=tostring(message),Time=os.time()}
    if placeId and placeId~=game.PlaceId then return end
    local current=Hop.Current
    if not current then return end
    if options then
        local ok,id=pcall(function() return options.ServerInstanceId end)
        if ok and id and id~="" and id~=current.Id then return end
    end
    Hop:failure(tostring(result).." - "..tostring(message),os.clock())
end)
local stateConnection=player.OnTeleport:Connect(function(state)
    if not Runtime.Alive then return end
    Runtime.LastTeleportEvent={Type="OnTeleport",State=tostring(state),Time=os.time()}
    if state==Enum.TeleportState.InProgress then Hop:progress()
    elseif state==Enum.TeleportState.Failed then Hop:failure("TeleportState.Failed",os.clock()) end
end)
Runtime.RejoinConnections={failureConnection,stateConnection}
local function cancelPendingTeleport()
    local cancelled=Hop:cancelPreparing()
    syncServerState()
    return cancelled or Hop.Current==nil
end
local function fruitSpawnDetected()
    if Delivery.Busy or Delivery.State.Pending or game.JobId==Delivery.JobId then return end
    if not Runtime.Alive or os.clock()<(Runtime.LastFruitSpawnNotice or -math.huge)+3 then return end
    Runtime.LastFruitSpawnNotice=os.clock()
    Runtime.FruitScanRequested=true
    RejoinRevision+=1
    if cancelPendingTeleport() then
        print("Rejoin | Aviso de fruta: saída pendente cancelada; nova busca solicitada.")
        atualizarStatus("Aviso de fruta: permanecendo no servidor para procurar.")
    else
        print("Rejoin | Aviso de fruta recebido após enviar o teleporte ao Roblox; cancelamento não garantido.")
    end
end
local function isFruitSpawnText(text)
    local plain=text:gsub("<[^>]+>",""):lower()
    local fruit=plain:find("fruit",1,true) or plain:find("fruta",1,true)
    if not fruit or plain:find("despawn",1,true) or plain:find("disappear",1,true)
        or plain:find("desapare",1,true) or plain:find("nenhuma",1,true)
        or plain:find("não",1,true) or plain:find(" not ",1,true) then return false end
    return plain:find("spawned",1,true) or plain:find("spawnou",1,true) or plain:find("nasceu",1,true)
        or plain:find("apareceu",1,true) or plain:find("has appeared",1,true) or plain:find("surgiu",1,true)
end
local watchedNotices=setmetatable({}, {__mode="k"})
local function watchFruitNotice(label,existing)
    if not label:IsA("TextLabel") or watchedNotices[label] then return end
    watchedNotices[label]=true
    local recognized=false
    local function read()
        if Runtime.Alive and not recognized and isFruitSpawnText(label.Text) then recognized=true fruitSpawnDetected() end
    end
    local ancestor=label.Parent
    local notificationArea=false
    while ancestor and ancestor~=player.PlayerGui do
        local name=ancestor.Name:lower()
        if name:find("notif",1,true) or name:find("announcement",1,true) or name:find("alert",1,true) then notificationArea=true break end
        ancestor=ancestor.Parent
    end
    if notificationArea or label.Name=="Message" then
        local textConnection,destroyConnection
        local function forget(connection)
            if not connection then return end
            connection:Disconnect()
            local index=table.find(Runtime.RejoinConnections,connection)
            if index then table.remove(Runtime.RejoinConnections,index) end
        end
        textConnection=label:GetPropertyChangedSignal("Text"):Connect(read)
        destroyConnection=label.Destroying:Connect(function()
            forget(textConnection)
            forget(destroyConnection)
        end)
        table.insert(Runtime.RejoinConnections,textConnection)
        table.insert(Runtime.RejoinConnections,destroyConnection)
        if not existing then task.defer(read) end
    end
end
table.insert(Runtime.RejoinConnections,player.PlayerGui.DescendantAdded:Connect(watchFruitNotice))
-- Observa apenas avisos novos; textos antigos da interface não cancelam a saída.
for _,label in ipairs(player.PlayerGui:GetDescendants()) do watchFruitNotice(label,true) end

local function deliveryCount(name)
    local count=0
    for _,item in pairs(getrenv()._G.ClientInventory.Items.Fruits or {}) do
        if item.Name==name then count+=tonumber(item.Amount) or 1 end
    end
    return count
end
local function deliveryTool(name)
    for _,folder in ipairs({backpack,player.Character or backpack}) do
        local tool=folder:FindFirstChild(name)
        if tool and tool:IsA("Tool") then return tool end
    end
end
local function deliveryWait(check,seconds)
    local deadline=os.clock()+seconds
    repeat
        assert(Runtime.Alive and Delivery.Enabled,"Entrega interrompida; confira o estado salvo antes de retomar.")
        if check() then return true end
        task.wait(.1)
    until os.clock()>=deadline
    return false
end
local function resolveDeliveryReceiver()
    assert(Delivery.Receiver~="","Informe o username do recebedor.")
    local id=Players:GetUserIdFromNameAsync(Delivery.Receiver)
    assert(id~=player.UserId,"O recebedor precisa ser outra conta.")
    local receiver=Players:GetPlayerByUserId(id)
    if receiver then return id,receiver.Name,game.JobId end
    if Delivery.PublicJobId~="" then
        assert(Delivery.PublicJobId:match("^[%x]+%-%x+%-%x+%-%x+%-%x+$"),"JobId público inválido.")
        return id,Delivery.Receiver,Delivery.PublicJobId
    end
    local ok,_,message,placeId,jobId=pcall(function() return TeleportService:GetPlayerPlaceInstanceAsync(id) end)
    assert(ok and placeId==game.PlaceId and type(jobId)=="string" and jobId~="",
        "O Roblox não informou o servidor do recebedor. Copie o JobId na conta recebedora e preencha o campo de servidor público.")
    return id,Delivery.Receiver,jobId
end
local function deliveryReceiver(pending)
    local receiver=Players:GetPlayerByUserId(pending.ReceiverId)
    assert(receiver and receiver.Parent==Players,"O recebedor saiu ou não está neste servidor. Entrega pausada sem dropar.")
    local character=receiver.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    assert(root and humanoid and humanoid.Health>0,"Aguardando o personagem do recebedor estar carregado e vivo.")
    return receiver,root
end
local function moveNearDeliveryReceiver(pending)
    local present=Players:GetPlayerByUserId(pending.ReceiverId)
    assert(present and present.Parent==Players,"O recebedor não está neste servidor. Entrega pausada sem retirar frutas.")
    local remoteCharacter=present.Character
    if not remoteCharacter or not remoteCharacter:FindFirstChild("HumanoidRootPart") then
        deliveryStatus("Recebedor presente; carregando o personagem e a área de "..present.Name.."...")
        assert(deliveryWait(function() return present.Parent==Players and present.Character~=nil end,10),"Recebedor presente, mas o personagem ainda não apareceu.")
        remoteCharacter=present.Character
        -- O pivô continua disponível quando as partes do personagem estão fora do streaming.
        local position=remoteCharacter:GetPivot().Position
        assert(position.Magnitude>1 and position.Magnitude<1e7,"Recebedor presente, mas sua posição ainda não foi replicada. Aguarde e tente novamente.")
        task.spawn(function() pcall(function() player:RequestStreamAroundAsync(position,8) end) end)
        assert(chegarNaIlha({Nome="Área de "..present.Name,CFrame=CFrame.new(position+Vector3.new(4,3,0))},1,1),"Recebedor presente, mas não foi possível carregar o chão na área dele.")
        assert(deliveryWait(function()
            local c=present.Parent==Players and present.Character
            local root=c and c:FindFirstChild("HumanoidRootPart")
            local h=c and c:FindFirstChildOfClass("Humanoid")
            return root and h and h.Health>0
        end,15),"Recebedor presente; personagem ainda fora do streaming ou renascendo. Nenhuma fruta foi retirada.")
    end
    local receiver,receiverRoot=deliveryReceiver(pending)
    local character,humanoid,root=esperarSpawn()
    local point=(receiverRoot.CFrame*CFrame.new(4,0,0)).Position
    if (root.Position-point).Magnitude>12 then
        assert(chegarNaIlha({Nome="Recebedor "..receiver.Name,CFrame=CFrame.new(point)},1,1),"Não foi possível carregar o chão perto do recebedor.")
    end
    receiver,receiverRoot=deliveryReceiver(pending)
    assert(Runtime.Alive and Delivery.Enabled,"Entrega interrompida antes da aproximação.")
    root.CFrame=receiverRoot.CFrame*CFrame.new(4,0,0)
    root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
    return character,humanoid,root,receiverRoot
end
Runtime.PrepareDeliveryReceiver=function()
    local pending=Delivery.State.Pending
    assert(pending and pending.Kind=="Player" and pending.Target==game.JobId,"Sem entrega válida para este servidor.")
    return moveNearDeliveryReceiver(pending)
end
local function dropManifestAtReceiver()
    local pending=Delivery.State.Pending
    assert(pending and pending.Kind=="Player" and pending.Target==game.JobId,"Destino diferente do recebedor registrado; nenhuma fruta será retirada.")
    assert(not pending.InFlight,"Uma retirada ou drop anterior ficou sem confirmação. Confira manualmente e cancele a pendência para evitar duplicação.")
    assert(deliveryWait(function()
        local receiver=Players:GetPlayerByUserId(pending.ReceiverId)
        return receiver and receiver.Parent==Players
    end,15),"Recebedor ausente no destino. Nenhuma fruta foi retirada.")
    moveNearDeliveryReceiver(pending)
    for _,entry in ipairs(pending.Items) do
        while (entry.Done or 0)<entry.Amount do
            assert(Runtime.Alive and Delivery.Enabled and game.JobId==pending.Target,"Entrega pausada ou destino alterado.")
            local character,humanoid=moveNearDeliveryReceiver(pending)
            local tool=deliveryTool(entry.Name)
            if not tool then
                assert(deliveryCount(entry.Name)>Delivery.Keep,"Quantidade reservada atingida: "..entry.Name)
                pending.InFlight={Name=entry.Name,Stage="Withdraw"} saveDeliveryState()
                deliveryReceiver(pending)
                deliveryStatus("Retirando "..entry.Name.." para entregar a "..pending.ReceiverName.."...")
                ReplicatedStorage.Remotes["Inventory Event"]:FireServer("Equip",entry.Name)
                assert(deliveryWait(function() return deliveryTool(entry.Name)~=nil end,12),"Retirada sem confirmação: "..entry.Name)
                tool=deliveryTool(entry.Name)
                pending.InFlight=nil saveDeliveryState()
            end
            if tool.Parent~=character then humanoid:EquipTool(tool) end
            assert(deliveryWait(function() return tool.Parent==character end,5),"Fruta não equipada para dropar.")
            moveNearDeliveryReceiver(pending)
            local oldGround={}
            for _,item in ipairs(droppedTools:GetDescendants()) do oldGround[item]=true end
            deliveryStatus("Entregando "..entry.Name.." ao lado de "..pending.ReceiverName.."...")
            task.wait(1)
            assert(Runtime.Alive and Delivery.Enabled,"Entrega interrompida antes do drop.")
            local _,_,root,receiverRoot=moveNearDeliveryReceiver(pending)
            assert((root.Position-receiverRoot.Position).Magnitude<=10,"Recebedor distante; drop interrompido.")
            pending.InFlight={Name=entry.Name,Stage="Drop"} saveDeliveryState()
            physicalFruitsEvent:FireServer("Drop",entry.Name)
            local name=entry.Name:gsub(" Fruit$","")
            local confirmed=deliveryWait(function()
                if tool:IsDescendantOf(backpack) or tool:IsDescendantOf(character) then return false end
                for _,item in ipairs(droppedTools:GetDescendants()) do
                    if not oldGround[item] and item:IsA("ProximityPrompt") then
                        local actual=item.ObjectText:gsub("<[^>]+>",""):gsub(" Fruit$","")
                        if actual==name then return true end
                    end
                end
                return false
            end,10)
            assert(confirmed,"Drop sem confirmação no chão: "..entry.Name..". Entrega pausada, sem repetir o comando.")
            entry.Done=(entry.Done or 0)+1 pending.InFlight=nil saveDeliveryState()
            print("Entrega | Drop confirmado ao lado de",pending.ReceiverName,entry.Name,entry.Done.."/"..entry.Amount)
            task.wait(3)
        end
    end
    Delivery.State.LastAt=os.time() Delivery.State.Pending=nil saveDeliveryState()
    Delivery.Requested=false Runtime.FruitScanRequested=false
    deliveryStatus("Entrega concluída. Voltando à busca em servidores públicos.")
    Delivery.JobId=""
    print("Entrega | Drops concluídos ao lado do recebedor registrado.")
end
local function deliveryTick()
    if Delivery.Busy then return true end
    local pending=Delivery.State.Pending
    if pending and pending.InFlight then
        deliveryStatus("Retirada/drop sem confirmação. Revise a entrega antes de continuar.")
        return true
    end
    if not Delivery.Enabled then
        if pending then deliveryStatus("Entrega pausada; busca pública liberada.") end
        return false
    end
    if Delivery.Error then return false end
    if pending and (pending.Kind~="Player" or type(pending.ReceiverId)~="number") then
        deliveryStatus("Há uma entrega antiga de VIP salva. Cancele essa pendência antes de configurar a entrega ao recebedor.")
        return false
    end
    if not pending then
        if not Delivery.Requested and os.time()-(Delivery.State.LastAt or 0)<Delivery.Interval*60 then return false end
        local items={}
        for name,selected in pairs(Delivery.Selected) do
            local data=getrenv()._G.GameData["Items Data"][name]
            if selected and data and data.Category=="Fruits" then
                local amount=math.min(Delivery.PerFruit,math.max(0,deliveryCount(name)-Delivery.Keep))
                if amount>0 then table.insert(items,{Name=name,Amount=amount,Done=0}) end
            end
        end
        if #items==0 then deliveryStatus("Nenhuma fruta selecionada disponível acima da quantidade reservada.") return false end
        if os.clock()<(Delivery.NextLookup or 0) then return false end
        Delivery.NextLookup=os.clock()+30
        local found,id,name,jobId=pcall(resolveDeliveryReceiver)
        if not found then deliveryStatus(tostring(id)) return false end
        Delivery.JobId=jobId
        table.sort(items,function(a,b) return a.Name<b.Name end)
        pending={Kind="Player",Target=jobId,ReceiverId=id,ReceiverName=name,Items=items}
        Delivery.State.Pending=pending
        local ok,err=pcall(saveDeliveryState)
        if not ok then Delivery.State.Pending=nil Delivery.Error=tostring(err) deliveryStatus(Delivery.Error) return true end
    end
    if Hop.Current or os.clock()<Hop.ReadyAt then return true end
    if pending.Target~=game.JobId then
        deliveryStatus("Indo ao servidor público de "..pending.ReceiverName.."...")
        Hop:begin(pending.Target,"Delivery",os.clock())
        syncServerState()
        return true
    end
    Runtime.FruitScanRequested=false Runtime.FarmDone=false Delivery.Busy=true
    Runtime.FarmThread=task.spawn(function()
        local ok,err=pcall(dropManifestAtReceiver)
        Delivery.Busy=false Runtime.FarmDone=true
        if not ok then Delivery.Error=tostring(err) deliveryStatus("Entrega pausada: "..Delivery.Error) warn("Entrega |",Delivery.Error) end
    end)
    return true
end

local function passoRejoin()
    Runtime.RejoinBlockReason=nil
    if Hop.Current then
        if Hop.Phase=="Preparing" and Hop.Current.Kind=="Search"
            and (not AutoRejoinEnabled or Runtime.FruitScanRequested
                or (Delivery.Enabled and not Delivery.Error and Delivery.State.Pending
                    and Delivery.State.Pending.Kind=="Player"
                    and type(Delivery.State.Pending.ReceiverId)=="number")) then
            Hop:cancelPreparing()
            syncServerState()
        else
            stepServers(false)
            atualizarStatus(Hop.Message)
            return
        end
    end
    if os.clock()<Hop.ReadyAt then
        stepServers(false)
        atualizarStatus(Hop.Message)
        return
    end
    if Runtime.FarmDone and not Runtime.SpinBusy and not Runtime.SpinTicket
        and (Delivery.State.Pending or not Runtime.FruitScanRequested) then
        if deliveryTick() then
            Runtime.RejoinBlockReason=Delivery.Error or "Entrega ativa ou pendente."
            if Hop.Current then stepServers(false) atualizarStatus(Hop.Message)
            else atualizarStatus("Rejoin aguarda entrega: "..Runtime.RejoinBlockReason) end
            return
        end
    end
    if Runtime.FruitScanRequested and Runtime.FarmDone and not Runtime.SpinBusy and not Runtime.SpinTicket then
        Runtime.FruitScanRequested=false Runtime.FarmDone=false
        Runtime.FarmThread=task.spawn(function()
            local ok,err=executarComLimite(240,function()
                aguardarPersonagemEstavel()
                Runtime.FarmResult=verificarLocalizacoes(true)
                flushFruitStorage()
            end)
            if not ok then
                if Runtime.CancelChestMovement then pcall(Runtime.CancelChestMovement) Runtime.CancelChestMovement=nil end
                if Runtime.CancelFruitMovement then pcall(Runtime.CancelFruitMovement) Runtime.CancelFruitMovement=nil end
                registrarErro("Busca após aviso de fruta",err)
            end
            Runtime.FarmDone=true
        end)
        return
    end
    if not Runtime.FarmDone then
        Runtime.RejoinBlockReason="Busca/coleta ainda em execução."
        if Hop.Phase=="Backoff" then atualizarStatus("Espera encerrada; aguardando a busca/coleta terminar.") end
        return
    end
    if Runtime.SpinTicket or Runtime.SpinBusy then
        Runtime.RejoinBlockReason="Aguardando roll."
        atualizarStatus("Espera encerrada; rejoin aguarda confirmação do roll.")
        return
    end
    if not AutoRejoinEnabled then atualizarStatus("Troca de servidor pausada.") return end
    stepServers(true)
    atualizarStatus(Hop.Message)
end

Runtime.ControllerThread=task.spawn(function()
    while Runtime.Alive do
        local ok,err=pcall(passoRejoin)
        if not ok then
            registrarErro("Controlador",err)
            atualizarStatus("Erro interno no controlador. Veja Último erro; nova avaliação em 5s.")
            task.wait(5)
        else
            task.wait(.5)
        end
    end
end)


-- Remove o "Anti Enemy Weld" com Disconnect, de forma contínua: ele volta a cada respawn, pode usar
-- outros sinais e alguns executores não preenchem conexao.Script. Por isso varre vários sinais,
-- identifica a origem por mais de um caminho e repete a varredura enquanto o Main roda.
local ANTI_WELD_NAME = "Anti Enemy Weld"
local function origemDaConexao(conexao)
    local ok, origem = pcall(function() return conexao.Script end)
    if ok and typeof(origem) == "Instance" then return origem end
    local okF, fn = pcall(function() return conexao.Function end)
    if okF and type(fn) == "function" then
        local okEnv, env = pcall(getfenv, fn)
        if okEnv and type(env) == "table" and typeof(rawget(env, "script")) == "Instance" then return rawget(env, "script") end
        if debug and debug.info then
            local okSrc, source = pcall(debug.info, fn, "s")
            if okSrc and type(source) == "string" and source:find(ANTI_WELD_NAME, 1, true) then return source end
        end
    end
end
local function ehAntiWeld(origem)
    if typeof(origem) == "Instance" then return origem.Name == ANTI_WELD_NAME end
    return type(origem) == "string" and origem:find(ANTI_WELD_NAME, 1, true) ~= nil
end
local function varrerConexoesAntiWeld()
    if type(getconnections) ~= "function" then return 0 end
    local RunService = game:GetService("RunService")
    local removidas = 0
    for _, sinal in ipairs({"Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender"}) do
        local okS, evento = pcall(function() return RunService[sinal] end)
        if okS and evento then
            local okC, lista = pcall(getconnections, evento)
            for _, conexao in ipairs(okC and lista or {}) do
                if ehAntiWeld(origemDaConexao(conexao)) then
                    if pcall(function() conexao:Disconnect() end) then removidas += 1 end
                end
            end
        end
    end
    return removidas
end
local function RemoveConnection()
    if Runtime.AntiWeldWatcher then return end
    -- Após um respawn o script reconecta; varre logo em seguida, sem esperar o próximo ciclo.
    table.insert(Runtime.RejoinConnections, player.CharacterAdded:Connect(function()
        for _, atraso in ipairs({0.5, 1.5, 3}) do
            task.delay(atraso, function() if Runtime.Alive then pcall(varrerConexoesAntiWeld) end end)
        end
    end))
    -- Varredura periódica: a conexão é desfeita com Disconnect sempre que reaparecer.
    Runtime.AntiWeldWatcher = task.spawn(function()
        local total = 0
        while Runtime.Alive do
            local ok, removidas = pcall(varrerConexoesAntiWeld)
            if ok and removidas > 0 then
                total += removidas
                print("Main | Anti Enemy Weld: " .. removidas .. " conexão(ões) removida(s); total " .. total)
            end
            task.wait(1)
        end
    end)
end
-- Começa já, sem esperar o personagem e as dependências da busca.
pcall(RemoveConnection)

Runtime.FarmThread = task.spawn(function()
	atualizarStatus("Aguardando personagem...")
    
	local ok, farmError = executarComLimite(480,function()
		carregarDependencias()
        registrarServidorAtual()
        watchBackpack()
		aguardarPersonagemEstavel()

        RemoveConnection()

        if Delivery.State.Pending or game.JobId==Delivery.JobId then
            Runtime.FarmResult="aguardando_entrega_recebedor"
            return
        end
        if Runtime.SpinTicket then waitSpinDelivery() end
        atualizarStatus("Verificando spawnpoints das ilhas...")
		if serverTime.Value >= 1800 then
			Runtime.FarmResult = verificarLocalizacoes()
		else
			Runtime.FarmResult = "servidor_recente"
			atualizarStatus("Servidor abaixo de 30 minutos; seguindo para troca.")
		end
	end)
    if backpack and physicalFruitsEvent and not Delivery.State.Pending and game.JobId~=Delivery.JobId then pcall(flushFruitStorage) end
	Runtime.FarmDone = true
    if ok then atualizarStatus("Varredura concluída.") end
	if not ok then
		registrarErro("Busca/coleta", farmError)
        if Runtime.CancelChestMovement then pcall(Runtime.CancelChestMovement) Runtime.CancelChestMovement=nil end
        if Runtime.SpinConnection then Runtime.SpinConnection:Disconnect() Runtime.SpinConnection=nil end
        if Runtime.SpinBusy or Runtime.SpinTicket then
            Runtime.SpinBusy=false Runtime.SpinTicket=nil Runtime.SpinCancelled=true
        end
		local arrivalRoot=Runtime.ArrivalCharacter and Runtime.ArrivalCharacter:FindFirstChild("HumanoidRootPart")
        if arrivalRoot and Runtime.ArrivalOriginalAnchored==false then arrivalRoot.Anchored=false end
		if Runtime.Tween then pcall(function() Runtime.Tween:Cancel() end) end
        if Runtime.CancelFruitMovement then pcall(Runtime.CancelFruitMovement) Runtime.CancelFruitMovement=nil end
		for _, connection in ipairs(Runtime.FarmConnections or {}) do connection:Disconnect() end
		Runtime.FarmConnections = {}
		atualizarStatus("Busca interrompida. Seguindo para o rejoin quando habilitado.")
	end
end)
