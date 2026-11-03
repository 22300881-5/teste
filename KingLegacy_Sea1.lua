--!nocheck
local Repository = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(Repository .. "Library.lua"))()
local SaveManager = loadstring(game:HttpGet(Repository .. "addons/SaveManager.lua"))()
local Window = Library:CreateWindow({
    Title = "",
    Footer = "",
    Icon = 0,
    AutoShow = false,
})

--// adicionar botões de minimizar/lock no pc também
local ToggleButton = Library:AddDraggableButton("Toggle", function()
	Library:Toggle()
end, true, true)

local LockButton = Library:AddDraggableButton("Lock", function(self)
	Library.CantDragForced = not Library.CantDragForced
	self:SetText(Library.CantDragForced and "Unlock" or "Lock")
end, true, true)

ToggleButton.Button.Position = UDim2.fromOffset(6, 6)
LockButton.Button.Position = UDim2.fromOffset(ToggleButton.Button.Size.X.Offset + 12, 6)

local SCRIPT_RUNNING = true
local AUTO_SAVE_CONFIG = "AutoSave"
local OPTIONS = Library.Options
local TOGGLES = Library.Toggles
local TABS = {
    GlobalSettings = Window:AddTab("Global Settings", "bolt"),
    Settings = Window:AddTab("Settings", "settings"),
    Farm = Window:AddTab("Farm", "bot"),
    Utils = Window:AddTab("Utils", "settings"),
    Config = Window:AddTab("Config", "settings"),
}
local DEFAULT_SETTINGS = {
    MaterialDealerItemsToBuy = {"Hydra's Tail", "Crab Meat", "Serpent Fin", "Sea King's Fin", "Sea's Wraith", "Severed Kraken", "Kraken's Ink", "Sea King's Blood" },
    AutoLevelUp = false,
	AutoCollectFruits = false,
    AutoFarmNPC = false,
    AutoShanks = true,
    AutoSeaSerpent = true,
    AutoFarmMaterial = false,
    M1Settings = {"Sword","Fighting Style",},
    DefaultM1Settings = {"Sword",},
    FarmSettings = {"Sword","Fighting Style","Devil Fruit",},
    FruitsToBuy = {"DragonDragon","PhoenixPhoenix","ToyToy","DoughDough","MelodyMelody","GateGate","PterPter","DemonDemon","TreeTree",},
    AutoBuyFruits = true,
    SwordSkills = {"Z","X",},
    DFSkills = {"Z","X","C","V",},
    FightingStyleSkills = {"Z","X",},
}

--// Services
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local AntiAfk_Result, _ = pcall(function()
    local connection = getconnections(player.Idled)[1]
    connection:Disable()
end)

local alreadyKicked = false

local function checkPlayer(targetPlayer)
	if alreadyKicked then return end

    local WHITELIST = loadstring(game:HttpGet("https://raw.githubusercontent.com/22300881-5/teste/main/IDsWhiteList.lua"))()
	if not WHITELIST[targetPlayer.UserId] then
		alreadyKicked = true
		player:Kick("Player não autorizado detectado no servidor.".. "\nPlayer: " .. targetPlayer.Name.. "\nUserId: " .. targetPlayer.UserId)
	end
end

local SUPABASE_URL = "https://sytspupabqwpotszbawb.supabase.co"
local SUPABASE_ANON_KEY = "sb_publishable_JLcgUPPsLgfLLA371WvWUw_vSB-Ok3s"

local requestFn = request or http_request or (syn and syn.request)
if not requestFn then
    warn("[HEARTBEAT] Função HTTP não encontrada no executor.")
    return
end



local function canSendInventoryDiscord()
	local ok, response = pcall(function()
		return requestFn({
			Url = SUPABASE_URL .. "/rest/v1/rpc/can_send_inventory_discord",

			Method = "POST",

			Headers = {
				["apikey"] = SUPABASE_ANON_KEY,
				["Authorization"] = "Bearer " .. SUPABASE_ANON_KEY,
				["Content-Type"] = "application/json"
			},

			Body = HttpService:JSONEncode({
				p_roblox_user_id = player.UserId
			})
		})
	end)

	if not ok then
		warn(
			"[SUPABASE] Erro na requisição:",
			response
		)

		return false
	end

	if not response then
		warn("[SUPABASE] Resposta vazia")
		return false
	end

	local status =
		response.StatusCode
		or response.Status
		or 0

	print("[SUPABASE] HTTP:", status)
	print("[SUPABASE] Body:", response.Body or "")

	if status < 200 or status >= 300 then
		warn("[SUPABASE] Consulta recusada")
		return false
	end

	local decodeOk, result = pcall(function()
		return HttpService:JSONDecode(
			response.Body or ""
		)
	end)

	if not decodeOk then
		warn(
			"[SUPABASE] Não foi possível ler a resposta:",
			response.Body
		)

		return false
	end

	return result == true
end

local function markInventoryDiscordSent()
	local ok, response = pcall(function()
		return requestFn({
			Url = SUPABASE_URL .. "/rest/v1/rpc/mark_inventory_discord_sent",
			Method = "POST",

			Headers = {
				["apikey"] = SUPABASE_ANON_KEY,
				["Authorization"] = "Bearer " .. SUPABASE_ANON_KEY,
				["Content-Type"] = "application/json"
			},

			Body = HttpService:JSONEncode({
				p_roblox_user_id = player.UserId
			})
		})
	end)

	if not ok then
		warn("[INVENTORY] Erro ao registrar envio:", response)
		return false
	end

	if not response then
		warn("[INVENTORY] Resposta vazia ao registrar envio")
		return false
	end

	local status = response.StatusCode or response.Status or 0
	local body = response.Body or response.body or ""

	print("[INVENTORY] MARK HTTP:", status)
	print("[INVENTORY] MARK Body:", body)

	if status >= 200 and status < 300 then
		print(
			"[INVENTORY] ✅ Envio registrado no Supabase | UserId:",
			player.UserId
		)

		return true
	end

	warn(
		"[INVENTORY] ❌ Falha ao registrar envio | HTTP:",
		status,
		"| Body:",
		body
	)

	return false
end

local MaterialList = require(
	ReplicatedStorage
		:WaitForChild("Chest")
		:WaitForChild("Modules")
		:WaitForChild("MaterialList")
)

local INVENTORY_WEBHOOK_URL = "https://discord.com/api/webhooks/1551358406344835122/jUlRuIxUAy4ZgCaPGNIMTY4c_c0gO6fhiTiM9BxMrBlgGAYZbuV8Liujechrk747HUzN"

local allowedMaterials = {
	"Angellic's Feather",
	"Aqua Gem",
	"Carrot",
	"Coral",
	"Crab Meat",
	"Dragon Fang",
	"Dragon Scale",
	"Dragon's Orb",
	"Essence of Fire",
	"Fresh Fish",
	"Gunpowder",
	"Hydra's Tail",
	"Iron Ingot",
	"Kraken's Ink",
	"Leather",
	"Log",
	"Lost Ruby",
	"Phoenix's Tear",
	"Pile of Bones",
	"Rusted Scrap",
	"Samurai's Badage",
	"Sea Artifact",
	"Sea King's Blood",
	"Sea King's Fin",
	"Sea's Wraith",
	"Serpent Fin",
	"Severed Kraken",
	"Shark's Canine",
	"Shark's Fin",
	"Thief's rag",
	"Twilight's Orb",
	"Vampire's Vital fluid"
}

local allowedLookup = {}

for _, name in ipairs(allowedMaterials) do
	allowedLookup[name] = true
end

local tierInfo = {
	Mythical = {
		Icon = "🩷",
		Name = "Mythic",
		Order = 6
	},

	Legendary = {
		Icon = "🔴",
		Name = "Legendary",
		Order = 5
	},

	Epic = {
		Icon = "🟣",
		Name = "Epic",
		Order = 4
	},

	Rare = {
		Icon = "🔵",
		Name = "Rare",
		Order = 3
	},

	Uncommon = {
		Icon = "🟢",
		Name = "Uncommon",
		Order = 2
	},

	Common = {
		Icon = "🩶",
		Name = "Common",
		Order = 1
	}
}

local function getCurrentInventoryMaterials()
	local materialObject = player
		:WaitForChild("PlayerStats")
		:WaitForChild("Material")

	local materialValue = materialObject.Value

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(materialValue)
	end)

	if not decodeOk or type(decoded) ~= "table" then
		warn("[INVENTORY] Material.Value inválido")
		return nil
	end

	local currentMaterials = {}

	for _, name in ipairs(allowedMaterials) do
		currentMaterials[name] = tonumber(decoded[name]) or 0
	end

	return currentMaterials
end

local function getInventorySnapshot()
	local ok, response = pcall(function()
		return requestFn({
			Url = SUPABASE_URL .. "/rest/v1/rpc/get_inventory_snapshot",
			Method = "POST",

			Headers = {
				["apikey"] = SUPABASE_ANON_KEY,
				["Authorization"] = "Bearer " .. SUPABASE_ANON_KEY,
				["Content-Type"] = "application/json"
			},

			Body = HttpService:JSONEncode({
				p_roblox_user_id = player.UserId
			})
		})
	end)

	if not ok then
		warn("[INVENTORY] Erro ao buscar snapshot:", response)
		return false, nil
	end

	if not response then
		warn("[INVENTORY] Resposta vazia ao buscar snapshot")
		return false, nil
	end

	local status = response.StatusCode or response.Status or 0
	local body = response.Body or response.body or ""

	if status < 200 or status >= 300 then
		warn(
			"[INVENTORY] Falha ao buscar snapshot | HTTP:",
			status,
			"| Body:",
			body
		)

		return false, nil
	end

	if body == "" or body == "null" then
		print("[INVENTORY] Nenhum snapshot anterior encontrado")
		return true, nil
	end

	local decodeOk, result = pcall(function()
		return HttpService:JSONDecode(body)
	end)

	if not decodeOk or type(result) ~= "table" then
		warn("[INVENTORY] Snapshot inválido:", body)
		return false, nil
	end

	if type(result.materials) ~= "table" then
		return true, nil
	end

	print("[INVENTORY] ✅ Snapshot anterior carregado")

	return true, result.materials
end

local function saveInventorySnapshot(materials)
	local ok, response = pcall(function()
		return requestFn({
			Url = SUPABASE_URL .. "/rest/v1/rpc/save_inventory_snapshot",
			Method = "POST",

			Headers = {
				["apikey"] = SUPABASE_ANON_KEY,
				["Authorization"] = "Bearer " .. SUPABASE_ANON_KEY,
				["Content-Type"] = "application/json"
			},

			Body = HttpService:JSONEncode({
				p_roblox_user_id = player.UserId,
				p_materials = materials
			})
		})
	end)

	if not ok then
		warn("[INVENTORY] Erro ao salvar snapshot:", response)
		return false
	end

	if not response then
		warn("[INVENTORY] Resposta vazia ao salvar snapshot")
		return false
	end

	local status = response.StatusCode or response.Status or 0
	local body = response.Body or response.body or ""

	if status >= 200 and status < 300 then
		print(
			"[INVENTORY] ✅ Snapshot atualizado | UserId:",
			player.UserId
		)

		return true
	end

	warn(
		"[INVENTORY] Falha ao salvar snapshot | HTTP:",
		status,
		"| Body:",
		body
	)

	return false
end

local function sendInventoryToDiscord(currentMaterials, previousMaterials)
	local materialList = {}

	for _, name in ipairs(allowedMaterials) do
		local currentAmount = tonumber(currentMaterials[name]) or 0

		local previousAmount = nil

		if previousMaterials then
			previousAmount = tonumber(previousMaterials[name]) or 0
		end

		-- Mostra se possui atualmente ou se possuía no snapshot anterior.
		-- Assim também aparece um item que caiu para 0.
		if currentAmount > 0
			or (previousAmount ~= nil and previousAmount > 0) then

			local moduleInfo = MaterialList[name]
			local tier = "Unknown"

			if moduleInfo and moduleInfo.Tier then
				tier = tostring(moduleInfo.Tier)
			end

			local difference = nil

			if previousAmount ~= nil then
				difference = currentAmount - previousAmount
			end

			table.insert(materialList, {
				Name = name,
				Amount = currentAmount,
				PreviousAmount = previousAmount,
				Difference = difference,
				Tier = tier
			})
		end
	end

	table.sort(materialList, function(a, b)
		local aInfo = tierInfo[a.Tier]
		local bInfo = tierInfo[b.Tier]

		local aOrder = aInfo and aInfo.Order or 0
		local bOrder = bInfo and bInfo.Order or 0

		if aOrder ~= bOrder then
			return aOrder > bOrder
		end

		return a.Name:lower() < b.Name:lower()
	end)

	if #materialList == 0 then
		warn("[INVENTORY] Nenhum material permitido encontrado")
		return false
	end

	local lines = {}
	local lastTier = nil

	if not previousMaterials then
		table.insert(
			lines,
			"*Primeiro snapshot — ainda não existe comparativo anterior.*"
		)

		table.insert(lines, "")
	end

	for _, material in ipairs(materialList) do
		local info = tierInfo[material.Tier]

		local icon = info and info.Icon or "⚫"
		local tierName = info and info.Name or material.Tier

		if material.Tier ~= lastTier then
			if #lines > 0 then
				table.insert(lines, "")
			end

			table.insert(
				lines,
				string.format(
					"### %s %s",
					icon,
					tierName
				)
			)

			lastTier = material.Tier
		end

		if material.PreviousAmount == nil then

			table.insert(
				lines,
				string.format(
					"**%s** — `%s`",
					material.Name,
					tostring(material.Amount)
				)
			)

		elseif material.Difference > 0 then
            table.insert(
                lines,
                string.format(
                    "**%s** — `%s` **(+%s)**",
                    material.Name,
                    tostring(material.Amount),
                    tostring(material.Difference)
                )
            )

		elseif material.Difference < 0 then
            table.insert(
                lines,
                string.format(
                    "**%s** — `%s` **(%s)**",
                    material.Name,
                    tostring(material.Amount),
                    tostring(material.Difference)
                )
            )

		else

			table.insert(
				lines,
				string.format(
					"**%s** — `%s`",
					material.Name,
					tostring(material.Amount)
				)
			)
		end
	end

	local description = table.concat(lines, "\n")

	if #description > 4000 then
		description =
			description:sub(1, 3950)
			.. "\n\n⚠️ *Lista cortada pelo limite do Discord.*"
	end

	local payload = {
		username = "King Legacy Inventory",

		embeds = {
			{
				title = "📦 Inventário de Materiais",

				description = description,

				color = 10181046,

				fields = {
					{
						name = "👤 Player",
						value = player.Name,
						inline = true
					},

					{
						name = "🆔 UserId",
						value = tostring(player.UserId),
						inline = true
					},

					{
						name = "📦 Materiais",
						value = tostring(#materialList),
						inline = true
					}
				},

				footer = {
					text = "King Legacy • Materials"
				},

				timestamp = os.date(
					"!%Y-%m-%dT%H:%M:%SZ"
				)
			}
		}
	}

	local ok, response = pcall(function()
		return requestFn({
			Url = INVENTORY_WEBHOOK_URL,

			Method = "POST",

			Headers = {
				["Content-Type"] = "application/json"
			},

			Body = HttpService:JSONEncode(payload)
		})
	end)

	if not ok then
		warn(
			"[INVENTORY] Erro ao enviar Discord:",
			response
		)

		return false
	end

	if not response then
		warn("[INVENTORY] Discord retornou resposta vazia")
		return false
	end

	local status =
		response.StatusCode
		or response.Status
		or 0

	print("[INVENTORY] Discord HTTP:", status)

	if status >= 200 and status < 300 then
		print(
			"[INVENTORY] ✅ Discord recebeu inventário |",
			#materialList,
			"materiais"
		)

		return true
	end

	warn(
		"[INVENTORY] ❌ Discord recusou | HTTP:",
		status,
		"| Body:",
		response.Body or response.body or ""
	)

	return false
end


task.spawn(function()
	while SCRIPT_RUNNING do
		print(
			"[INVENTORY] Consultando cooldown | UserId:",
			player.UserId
		)

		local canSend = canSendInventoryDiscord()

		if canSend then
			local currentMaterials = getCurrentInventoryMaterials()

			if currentMaterials then
				local snapshotOk, previousMaterials =
					getInventorySnapshot()

				if snapshotOk then
					print(
						"[INVENTORY] ✅ Cooldown liberado. Enviando inventário..."
					)

					local discordSent = sendInventoryToDiscord(
						currentMaterials,
						previousMaterials
					)

					if discordSent then
						local marked =
							markInventoryDiscordSent()

						if marked then
							local snapshotSaved =
								saveInventorySnapshot(
									currentMaterials
								)

							if snapshotSaved then
								print(
									"[INVENTORY] ✅ PROCESSO COMPLETO | próximo envio após 2 horas"
								)
							else
								warn(
									"[INVENTORY] ⚠️ Cooldown registrado, mas snapshot não foi salvo"
								)
							end
						else
							warn(
								"[INVENTORY] ⚠️ Discord recebeu, mas cooldown não foi registrado. Snapshot NÃO será alterado."
							)
						end
					else
						warn(
							"[INVENTORY] Discord falhou. Cooldown e snapshot NÃO serão alterados."
						)
					end
				else
					warn(
						"[INVENTORY] Não foi possível consultar snapshot. Envio cancelado para preservar o comparativo."
					)
				end
			end
		else
			print(
				"[INVENTORY] ⏳ Cooldown de 2 horas ainda ativo"
			)
		end

		task.wait(60)
	end
end)




local function sendHeartbeat()
	local ok, response = pcall(function()
		return requestFn({
			Url = SUPABASE_URL .. "/rest/v1/rpc/heartbeat_player",
			Method = "POST",

			Headers = {
				["Content-Type"] = "application/json",
				["apikey"] = SUPABASE_ANON_KEY,
				["Authorization"] = "Bearer " .. SUPABASE_ANON_KEY,
			},

			Body = HttpService:JSONEncode({
				p_roblox_user_id = player.UserId
			})
		})
	end)

	if not ok then
		warn("[HEARTBEAT] Erro na requisição:", response)
		return
	end

	if not response then
		warn("[HEARTBEAT] Resposta vazia")
		return
	end

	local statusCode =
		response.StatusCode
		or response.Status
		or 0

	if statusCode >= 200 and statusCode < 300 then
		print(
			"[HEARTBEAT] OK |",
			player.Name,
			"| UserId:",
			player.UserId
		)
	else
		warn(
			"[HEARTBEAT] Falhou | HTTP:",
			statusCode,
			"| Body:",
			response.Body or response.body or ""
		)
	end
end

sendHeartbeat()
task.spawn(function()
	while SCRIPT_RUNNING do
		task.wait(30)

		if SCRIPT_RUNNING then
			sendHeartbeat()
		end
	end
end)

for _, targetPlayer in ipairs(Players:GetPlayers()) do
	checkPlayer(targetPlayer)
	if alreadyKicked then break end
end

Players.PlayerAdded:Connect(function(targetPlayer)
	checkPlayer(targetPlayer)
end)

local PlayerGui = player:WaitForChild("PlayerGui")
-- Início
local loadingGUI = PlayerGui:WaitForChild("LoadingGUI", 10) 
repeat 
    task.wait(1)
	if loadingGUI then 
		local button = loadingGUI:FindFirstChild("Play") 
		if button then
			firesignal(button.MouseButton1Click)
		end
	end
until not PlayerGui:FindFirstChild("LoadingGUI") 

local PlayerStats = player:WaitForChild("PlayerStats")
local WeaponName = PlayerStats.sword.Value
local STOCK_VALUE = PlayerStats.MaterialDealer

local MonsterFolder = workspace:WaitForChild("Monster")
local MainLoopTimer = 1
local UsingSkills = false
local M1_PENDING = false
local SKILL_MAX_WAIT = 2
local SKILL_KEY_HOLD = 0.06
local SKILL_PULSE_DELAY = 0.10
local SKILL_NEXT_DELAY = 0.25
local INPUT_KEY_CODES = {
    Z = Enum.KeyCode.Z,
    X = Enum.KeyCode.X,
    C = Enum.KeyCode.C,
    V = Enum.KeyCode.V,
}
local holdTime = 0.1
local currentFollow
local Skills_Cooldown = false
local MaterialDealer = ReplicatedStorage.Chest.Remotes.Functions.MaterialDealer
local MonsterFolder = workspace:WaitForChild("Monster")
local IslandsFolder = workspace:WaitForChild("Island")
local AreasFolder = workspace:WaitForChild("Areas")
local EffectsFolder = workspace:WaitForChild("Effects")

local Database = loadstring(game:HttpGet("https://raw.githubusercontent.com/22300881-5/teste/main/Database.lua"))()
local InstanceUtils = loadstring(game:HttpGet("https://raw.githubusercontent.com/22300881-5/teste/main/InstanceUtils.lua"))()
local CharacterUtils = loadstring(game:HttpGet("https://raw.githubusercontent.com/22300881-5/teste/main/CharacterUtils.lua"))()
local GlobalSettingsTAB = loadstring(game:HttpGet("https://raw.githubusercontent.com/22300881-5/teste/main/GlobalSettings.lua"))()
local GlobalSettings = GlobalSettingsTAB.Create(TABS.GlobalSettings,Library,AntiAfk_Result)
local FPSLabel = GlobalSettings.FPSLabel
local SwordEquipped = WeaponName

local NPCsData = Database.NPCs["Sea 1"]
local NPCsList = {}
for NPCName, _ in pairs(NPCsData) do
    table.insert(NPCsList, NPCName)
end
local Quests = Database.Quests["Sea 1"]
local MaterialsData = Database.Materials["Sea 1"]

local MaterialsList = {}
for MaterialName, _ in pairs(MaterialsData) do
    table.insert(MaterialsList, MaterialName)
end
local MaterialDealerDefault = {}
for _, MaterialName in ipairs(DEFAULT_SETTINGS.MaterialDealerItemsToBuy) do
    MaterialDealerDefault[MaterialName] = true
end
local PlayerSwords = {}
for _, sword in pairs(player.Inventory:GetChildren()) do
    if sword.Name ~= "Basic Rod" then
        table.insert(PlayerSwords, sword.Name)
    end
end

local SKILLS_OPTIONS = {
    ["Sword"] = {
        Name = "SwordName",
        Prefix = "SW",
        Tool_Settings = "SwordSkills",
    },
    ["Fighting Style"] = {
        Name = "FightingStyle",
        Prefix = "FS",
        Tool_Settings = "FightingStyleSkills",
    },
    ["Devil Fruit"] = {
        Name = "DFName",
        Prefix = "DF",
        Tool_Settings = "DFSkills",
    },
}


local function SaveCurrentConfig()
    local Success, Error = pcall(function()
        SaveManager:Save(AUTO_SAVE_CONFIG)
        SaveManager:SaveAutoloadConfig(AUTO_SAVE_CONFIG)
    end)

    if Success then
        print("[CONFIG] Configurações salvas automaticamente.")
    else
        warn("[CONFIG] Erro ao salvar:", Error)
    end
end

local function Click(button)
	local holdTime = 0.1

	local pos = button.AbsolutePosition + Vector2.new(0,55)
	local size = button.AbsoluteSize

	local x = pos.X + size.X / 2
	local y = pos.Y + size.Y / 2

	VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
	task.wait(holdTime)
	VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function CentralizarClick()
    local screenSize = workspace.CurrentCamera.ViewportSize
    local x = screenSize.X / 2
    local y = screenSize.Y / 2

	VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
	task.wait(holdTime)
	VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function WaitForNPC(Folder, NPCName, Timeout)
    local Start = os.clock()

    while os.clock() - Start < Timeout do
        for _, NPC in ipairs(Folder:GetChildren()) do
            if NPC.Name == NPCName and not CharacterUtils.IsDead(NPC) then
                return NPC
            end
        end
        task.wait(0.2)
    end

    return nil
end

local function GetFollowPart(target)
	if not target then return nil end
	if target:IsA("BasePart") then return target end
	if target:IsA("Model") then
		return target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart")
			or target:FindFirstChildWhichIsA("BasePart")
	end
end

local function StopFollowing(follow)
	if follow and currentFollow ~= follow then return end

	local oldFollow = currentFollow
	currentFollow = nil
	if not oldFollow then return end

	if oldFollow.Connection then
		oldFollow.Connection:Disconnect()
	end

	local character = oldFollow.Character
	local humanoid = character and CharacterUtils.GetHumanoid(character)
	local hrp = character and CharacterUtils.GetHumanoidRootPart(character)

	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function FollowNPC(target, offset)
	StopFollowing()

	local character = CharacterUtils.GetCharacter(player)
	local humanoid = CharacterUtils.GetHumanoid(character)
	local hrp = CharacterUtils.GetHumanoidRootPart(character)

	if not character or not humanoid or not hrp or not target then
		return nil
	end

	local follow = {
		Character = character,
		Target = target,
	}

	currentFollow = follow
	humanoid.AutoRotate = false

	local function Update()
		if currentFollow ~= follow then return end

		if not character.Parent or not target.Parent or not CharacterUtils.IsAlive(character) then
			StopFollowing(follow)
			return
		end

		local targetHumanoid = target:IsA("Model") and target:FindFirstChildOfClass("Humanoid")
		if targetHumanoid and targetHumanoid.Health <= 0 then
			StopFollowing(follow)
			return
		end

		hrp = CharacterUtils.GetHumanoidRootPart(character)
		local targetPart = GetFollowPart(target)

		if not hrp or not targetPart or not targetPart.Parent then
			StopFollowing(follow)
			return
		end

		hrp.CFrame = targetPart.CFrame * offset
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	Update()
	follow.Connection = RunService.Heartbeat:Connect(Update)

	return follow
end

local function EquipTool(toolName)
    for _, Tool in pairs(player.Backpack:GetChildren()) do
        if Tool:IsA("Tool") and string.find(Tool.Name,toolName) then
            CharacterUtils.EquipTool(CharacterUtils.GetCharacter(player), Tool)
        end
    end
end

local function CheckBuso()
    local CharacterWorkshop = workspace:FindFirstChild("CharacterWorkshop")
    if CharacterWorkshop and not CharacterWorkshop:FindFirstChild(player.Name .. "ArmamentGroup") then
        ReplicatedStorage.Chest.Remotes.Events.Armament:FireServer()
    end
end

local function CheckKen()
    if not Lighting:FindFirstChild("KenColor") then
        local gui = player.PlayerGui:FindFirstChild("MainGui")

        if not gui then
            return
        end
        local KenBtn = gui.MobileMove:FindFirstChild("Ken")
        if not KenBtn then
            return
        end
        for _, connection in pairs(getconnections(KenBtn.MouseButton1Click)) do
            connection:Fire()
        end
    end
end

local function ChecksToAttack()
    CheckBuso()
    CheckKen()
end

local function M1_Attack()
    if M1_PENDING or UsingSkills then
        return
    end

    if PlayerStats.SwordName.Value ~= OPTIONS.SwordSelected.Value then
        ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer(
            "EquipWeapon",
            {
                ["WeaponName"] = OPTIONS.SwordSelected.Value,
                ["Type"] = "Primary",
            }
        )
    end

    M1_PENDING = true

    local M1_OPTIONS = {
        ["Sword"] = {
            Name = PlayerStats.SwordName.Value,
            Prefix = "SW",
        },

        ["Fighting Style"] = {
            Name = PlayerStats.FightingStyle.Value,
            Prefix = "FS",
        },

        ["Devil Fruit"] = {
            Name = PlayerStats.DFName.Value,
            Prefix = "DF",
        },
    }

    for M1_Option, _ in pairs(OPTIONS.M1Settings.Value) do
        if M1_OPTIONS[M1_Option] then
            EquipTool(M1_OPTIONS[M1_Option].Name)

            ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
                `{M1_OPTIONS[M1_Option].Prefix}_{M1_OPTIONS[M1_Option].Name}_M1`
            )
        end

        task.wait()
    end

    M1_PENDING = false
end

local function InvokeSkillWithPulse(Arg, MouseHit, SkillKey)
    local KeyCode = INPUT_KEY_CODES[SkillKey]
    if not KeyCode then return false, "invalid_key" end

    local Finished = false
    local Success = false
    local Result
    local Pulses = 0
    local Started = os.clock()

    task.spawn(function()
        Success, Result = pcall(function()
            return ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(Arg, {
                Type = "Down",
                MouseHit = MouseHit
            })
        end)

        Finished = true
    end)

    RunService.Heartbeat:Wait()

    while not Finished do
        if os.clock() - Started >= SKILL_MAX_WAIT then
            VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
            warn("[SKILL] Timeout:", Arg)
            return false, "timeout"
        end

        Pulses += 1

        VirtualInputManager:SendKeyEvent(true, KeyCode, false, game)

        local HoldStart = os.clock()
        while not Finished and os.clock() - HoldStart < SKILL_KEY_HOLD do
            task.wait()
        end

        VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)

        if Finished then break end

        local DelayStart = os.clock()
        while not Finished and os.clock() - DelayStart < SKILL_PULSE_DELAY do
            task.wait()
        end
    end

    VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
    return Success, Result
end

local function SKILLS_Trigger(Target)
    if Skills_Cooldown or M1_PENDING or UsingSkills then return end

    Skills_Cooldown = true
    UsingSkills = true

    local ok, err = xpcall(function()
        local Character = CharacterUtils.GetCharacter(player)
        if not Character then return end

        for SkillType, Enabled in pairs(OPTIONS.FarmSettings.Value) do
            if Enabled == false then continue end

            local SkillData = SKILLS_OPTIONS[SkillType]
            if not SkillData then continue end

            local Stat = PlayerStats:FindFirstChild(SkillData.Name)
            if not Stat then continue end

            local ToolName = Stat.Value
            if not ToolName or ToolName == "None" then continue end

            EquipTool(ToolName)
            task.wait(0.05)

            local Option = OPTIONS[SkillData.Tool_Settings]
            if not Option then continue end

            for SkillKey, SkillEnabled in pairs(Option.Value) do
                if not CharacterUtils.IsAlive(Target) then return end
                if SkillEnabled == false then continue end
                if not CharacterUtils.IsAlive(Character) then return end

                task.wait(SKILL_NEXT_DELAY)

                local HRP = CharacterUtils.GetHumanoidRootPart(Character)
                if not HRP then return end

                local Arg = `{SkillData.Prefix}_{ToolName}_{SkillKey}`
                local Success, Result = InvokeSkillWithPulse(Arg, HRP.CFrame, SkillKey)

                if Result == "timeout" then return end

                if not Success then
                    warn("[SKILL] Falha:", Arg, Result)
                end
            end

            task.wait(0.25)
        end
    end, debug.traceback)

    UsingSkills = false
    if not ok then warn("[SKILL] Erro:", err) end
    task.delay(5, function()
        Skills_Cooldown = false
    end)
end

local function checkMeleeStats()
    if PlayerStats.Melee.Value < 100 and PlayerStats.Points.Value > 0 then
        local difference = 100 - PlayerStats.Melee.Value
        local pointsToUse = math.min(difference, PlayerStats.Points.Value)

        Players.LocalPlayer.PlayerGui.MainGui.StarterFrame.StatsFrame.RemoteEvent:FireServer("Melee", pointsToUse)
    end
end

local function GetQuest(level)
    if PlayerStats.Points.Value > 0 then
        if level < 50 then
            checkMeleeStats()
        else
            repeat
                Players.LocalPlayer.PlayerGui.MainGui.StarterFrame.StatsFrame.RemoteEvent:FireServer("Sword", 5)
                Players.LocalPlayer.PlayerGui.MainGui.StarterFrame.StatsFrame.RemoteEvent:FireServer("Defense", 5)
                task.wait(.1)
            until PlayerStats.Points.Value <= 0
        end
    end

    local selected = Quests[1]

    for _, quest in ipairs(Quests) do
        if level >= quest.lvl then
            selected = quest
        end
    end

    return selected
end

local function SetQuest(quest)
    if player.CurrentQuest.Value ~= quest.Name then
        ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("CancelQuest", {})
        ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", quest.Name)
    end
end

local function AutoFarmMaterial()
    local AutoFarmMaterial_Result, AutoFarmMaterial_Error = pcall(function()
        if not OPTIONS.MaterialsList or not TOGGLES.AutoFarmMaterial.Value then return end

        local Character = CharacterUtils.GetCharacter(player)

        for MaterialName, _ in pairs(OPTIONS.MaterialsList.Value) do
            for NPCName, FarmPoint in pairs(MaterialsData[MaterialName]) do
                if not TOGGLES.AutoFarmMaterial.Value or CharacterUtils.IsDead(Character) then
                    break
                end

                Character:PivotTo(FarmPoint.Location)
                local FolderPath = MonsterFolder:FindFirstChild(FarmPoint.Folder_Path)
                local NPC = WaitForNPC(FolderPath, NPCName, 10)
                if not NPC then
                    continue
                end

                ChecksToAttack()
                FollowNPC(NPC, CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(-90), 0, 0))

                local Humanoid = NPC:FindFirstChild("Humanoid")

                local lastHealth = Humanoid.Health
                local lastDamageTime = tick()

                while true do
                    if not TOGGLES.AutoFarmMaterial.Value or not CharacterUtils.IsAlive(Character) or not CharacterUtils.IsAlive(NPC) then
                        break
                    end

                    if Humanoid.Health < lastHealth then
                        lastHealth = Humanoid.Health
                        lastDamageTime = tick()
                    elseif Humanoid.Health > lastHealth then
                        lastHealth = Humanoid.Health
                    end

                    if tick() - lastDamageTime > 30 then
                        warn("[WATCHDOG] NPC sem receber dano por 30s: ".. NPC.Name)
                        break
                    end

                    M1_Attack()
                    SKILLS_Trigger(NPC)

                    task.wait(.1)
                end
                StopFollowing()
                task.wait(0.25)
            end
            task.wait(0.25)
        end
    end)

    if not AutoFarmMaterial_Result then
        warn("Erro no AutoFarmMaterial:", AutoFarmMaterial_Error)
    end
end

local function AutoLevelUp()
    if not TOGGLES.AutoLevelUp.Value then return end

    local AutoLevelUp_Result, AutoLevelUp_Error = pcall(function()
        local Level = PlayerStats.lvl.Value
        local Quest = GetQuest(Level)
        SetQuest(Quest)

        if not NPCsData[Quest.NPC] then return end

        local Character = CharacterUtils.GetCharacter(player)
        Character:PivotTo(NPCsData[Quest.NPC].Location)

        local PathFolder = NPCsData[Quest.NPC].Folder_Path
        local TargetNPC = WaitForNPC(MonsterFolder:FindFirstChild(PathFolder), Quest.NPC, 10)
        if not TargetNPC then 
            print("not target", Quest.NPC)
            return 
        end

        for _, NPC in pairs(MonsterFolder:FindFirstChild(PathFolder):GetChildren()) do
            if NPC.Name == Quest.NPC then
                if not TOGGLES.AutoLevelUp.Value or not CharacterUtils.IsAlive(Character) then
                    break
                end

                ChecksToAttack()
                FollowNPC(NPC, CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(-90), 0, 0))

                local Humanoid = NPC:FindFirstChild("Humanoid")

                local lastHealth = Humanoid.Health
                local lastDamageTime = tick()

                while true do
                    if not TOGGLES.AutoLevelUp.Value or not CharacterUtils.IsAlive(Character) or not CharacterUtils.IsAlive(NPC) then
                        break
                    end

                    if Humanoid.Health < lastHealth then
                        lastHealth = Humanoid.Health
                        lastDamageTime = tick()
                    elseif Humanoid.Health > lastHealth then
                        lastHealth = Humanoid.Health
                    end

                    if tick() - lastDamageTime > 30 then
                        warn("[WATCHDOG] NPC sem receber dano por 30s: ".. NPC.Name)
                        break
                    end

                    M1_Attack()
                    SKILLS_Trigger(NPC)
                    task.wait()
                end
                StopFollowing()
            end
            task.wait(0.1)
        end
    end)

    if not AutoLevelUp_Result then
        warn("Erro no AutoLevelUp:", AutoLevelUp_Error)
    end
end



local FarmSettingsBox = TABS.Settings:AddGroupbox({Side = "Left", Name = "Farm Settings",})
FarmSettingsBox:AddDropdown("FarmSettings", {
    Values = DEFAULT_SETTINGS.FarmSettings,
    Default = DEFAULT_SETTINGS.FarmSettings,
    Multi = true,
    Text = "Tools To Use",
})
FarmSettingsBox:AddDropdown("M1Settings", {
    Values = DEFAULT_SETTINGS.M1Settings,
    Default = DEFAULT_SETTINGS.DefaultM1Settings,
    Multi = true,
    Text = "M1 Tool",
})
FarmSettingsBox:AddDropdown("SwordSelected", {
    Values = PlayerSwords,
    Default = SwordEquipped,
    Multi = false,
    Text = "Sword Selected",
})

local SkillsSettingsBox = TABS.Settings:AddGroupbox({Side = "Right", Name = "Skills Settings",})
SkillsSettingsBox:AddDropdown("SwordSkills", {
    Values = DEFAULT_SETTINGS.SwordSkills,
    Default = DEFAULT_SETTINGS.SwordSkills,
    Multi = true,
    Text = "Sword Skills",
})
SkillsSettingsBox:AddDropdown("FightingStyleSkills", {
    Values = DEFAULT_SETTINGS.FightingStyleSkills,
    Default = DEFAULT_SETTINGS.FightingStyleSkills,
    Multi = true,
    Text = "Fighing Style Skills",
})
SkillsSettingsBox:AddDropdown("DFSkills", {
    Values = DEFAULT_SETTINGS.DFSkills,
    Default = DEFAULT_SETTINGS.DFSkills,
    Multi = true,
    Text = "Devil Fruit Skills",
})


local BossesBox = TABS.Farm:AddGroupbox({Side = "Left",Name = "BOSSES",})
BossesBox:AddToggle("AutoShanks", {
    Text = "1. Auto Shanks",
    Default = DEFAULT_SETTINGS.AutoShanks,
})
BossesBox:AddLabel("🎁 DROPS\n• Saber (Sword)",true)

BossesBox:AddToggle("AutoSeaSerpent", {
    Text = "2. Auto Serpent",
    Default = DEFAULT_SETTINGS.AutoSeaSerpent
})
BossesBox:AddLabel("🎁 DROPS\n• Sea Fin (Item)\n• Acrodagger (Sword)\n• Acromask (Accessory)",true)


local BoxB = TABS.Farm:AddGroupbox({Side = "Right", Name = "FARMS",})
BoxB:AddDropdown("MaterialsList", {
    Values = MaterialsList,
    Default = {},
    Multi = true,
    Text = "Materials List",
})
BoxB:AddToggle("AutoFarmMaterial", {Text = "Auto Material Farm", Default = DEFAULT_SETTINGS.AutoFarmMaterial})

BoxB:AddDropdown("NPCsList", {
    Values = NPCsList,
    Default = {},
    Multi = true,
    Text = "NPCs List",
})
BoxB:AddToggle("AutoFarmNPC", {Text = "Auto NPC Farm", Default = DEFAULT_SETTINGS.AutoFarmNPC})
BoxB:AddToggle("AutoLevelUp", {Text = "Auto Level Up", Default = DEFAULT_SETTINGS.AutoLevelUp})


local FruitsBox = TABS.Farm:AddGroupbox({Side = "Right", Name = "FRUIT SYSTEMS",})
FruitsBox:AddToggle("AutoCollectFruits", {Text = "Auto Collect Fruits", Default = DEFAULT_SETTINGS.AutoCollectFruits})
FruitsBox:AddToggle("AutoBuyFruits", {Text = "Auto Buy Fruits", Default = DEFAULT_SETTINGS.AutoBuyFruits})



local Sea2Box = TABS.Farm:AddGroupbox({Side = "Right", Name = "Sea 2",})
Sea2Box:AddButton({Text = "Unlock Sea 2",
    Func = function()
        player.Character:PivotTo(CFrame.new(2585,95,-1875))
        task.wait(2.5)
        ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(workspace.AllNPC.Traveler)
        task.wait(2.5)
        local TravelerGUI = PlayerGui:WaitForChild("Traveler")
        firesignal(TravelerGUI.Dialogue.Accept.MouseButton1Click)
    end,
})

local UtilsBox = TABS.Utils:AddGroupbox({Side = "Left", Name = "Utils",})
UtilsBox:AddButton({Text = "Buy Buso Haki",
    Func = function()
        player.Character:PivotTo(CFrame.new(1961, 43, 912))
        task.wait(1.5)
        ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(workspace.AllNPC.BusoShop)
        task.wait(2.5)
        local button = PlayerGui.BusoShop.Dialogue.Accept
        Click(button)
    end,
})
local BusoOwnedLabel = UtilsBox:AddLabel(
    '<font color="rgb(255, 200, 0)"><b>PRICE:</b></font> 1.5M / ' ..
    '<font color="rgb(0, 255, 100)"><b>OWNED:</b></font> ' ..
    tostring(PlayerStats.BusoShopValue.Value == "BusoHaki"),
    true
)
PlayerStats.BusoShopValue.Changed:Connect(function(newValue)
    BusoOwnedLabel:SetText(
        '<font color="rgb(255, 200, 0)"><b>PRICE:</b></font> 1.5M / ' ..
        '<font color="rgb(0, 255, 100)"><b>OWNED:</b></font> ' ..
        tostring(newValue == "BusoHaki")
    )
end)


UtilsBox:AddButton({Text = "Buy Ken Haki",
    Func = function()
        player.Character:PivotTo(CFrame.new(-4986, 441, 1189))
        task.wait(1.5)
        ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(workspace.AllNPC.KenShop)
        task.wait(2.5)
        local button = PlayerGui.KenShop.Dialogue.Accept
        Click(button)
    end,
})
local KenOwnedLabel = UtilsBox:AddLabel(
    '<font color="rgb(255, 200, 0)"><b>PRICE:</b></font> 500k / ' ..
    '<font color="rgb(0, 255, 100)"><b>OWNED:</b></font> ' ..
    tostring(PlayerStats.KenShopValue.Value == "KenHaki"),
    true
)
PlayerStats.KenShopValue.Changed:Connect(function(newValue)
    KenOwnedLabel:SetText(
        '<font color="rgb(255, 200, 0)"><b>PRICE:</b></font> 1.5M / ' ..
        '<font color="rgb(0, 255, 100)"><b>OWNED:</b></font> ' ..
        tostring(newValue == "KenHaki")
    )
end)

UtilsBox:AddButton({Text = "Buy Basic Rod",
    Func = function()
        player.Character:PivotTo(CFrame.new(-5979,33,1890))
        task.wait(1)
        mouse1click()
        task.wait(1)
        mouse1click()
        task.wait(2.5)
        Click(PlayerGui.MaterialCraftingDialogue.Dialogue.Accept)
        task.wait(2.5)
        local CraftingUI2 = PlayerGui:WaitForChild("CraftingUI2")
        Click(CraftingUI2.Frame.MainFrame.ItemFrame)
        task.wait(1)
        Click(CraftingUI2.Frame.MainFrame.ChooseFrame.ScrollingFrame["Basic Rod"])
        task.wait(1)
        Click(CraftingUI2.Frame.MainFrame.CraftButton)
    end,
})
UtilsBox:AddLabel('<font color="rgb(255, 200, 0)"><b>REQ:</b></font> 10 Rusted Scrap / 40 Log',true)


local MaterialDealerBox = TABS.Utils:AddGroupbox({Side = "Right", Name = "Material Dealer",})
MaterialDealerBox:AddDropdown("MaterialDealerList", {
    Values = DEFAULT_SETTINGS.MaterialDealerItemsToBuy,
    Default = MaterialDealerDefault,
    Multi = true,
    Text = "Items To Buy",
})
MaterialDealerBox:AddButton({Text = "Open Material Dealer",
    Func = function()
        ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("SpecialShopGui", {GuiName = "Material Dealer"})
        ReplicatedStorage.Chest.Remotes.Functions.MaterialDealer:InvokeServer("Get")
    end,
})


local SeaSerpentBusy = false
local SerpentFollowing = false

local FishingConnection = nil
local FishingStarted = false
local CurrentFishingTween = nil
local FishingRenderConnection

local FishPositionConnection
local BarPositionConnection
local FISH_BIND = "SeaSerpentFishLock"



function CheckFruits()
    local CheckFruits_Result, CheckFruits_Error = pcall(function()
        if not TOGGLES.AutoCollectFruits.Value then
            -- Continua verificando o inventário mesmo sem AutoCollectFruits
        else
			local Character = CharacterUtils.GetCharacter(player)
            local AllSpawnedDFsFolder = workspace.AllspawnDF

            for _, Fruit in pairs(AllSpawnedDFsFolder:GetChildren()) do
                local Handle = Fruit:FindFirstChild("Handle")

                if Handle then
                    Character:PivotTo(Handle.CFrame)
                    task.wait(1)
                end
            end
        end

        local Backpack = PlayerGui.Backpack
        local SlotsInventory = Backpack.Slots
        local GameInventory = Backpack.InventoryFrame
        local SlotsGameInventory = GameInventory.ScrollingFrame
        local FruitStorage = PlayerStats.FruitStorage.Value
        local FruitsData
        local DecodeSuccess, DecodeResult = pcall(function()
            return HttpService:JSONDecode(PlayerStats.FruitStore.Value)
        end)

        if not DecodeSuccess then
            warn("Erro ao decodificar FruitStore:", DecodeResult)
            return
        end

        FruitsData = DecodeResult

        local function StoreFruit(SlotSelected)
            local StoreFruit_Result, StoreFruit_Error = pcall(function()
                CentralizarClick()
                firesignal(SlotSelected.MouseButton1Click)
                task.wait(1)
                local Character = CharacterUtils.GetCharacter(player)
                for _, Fruit in pairs(Character:GetChildren()) do
                    if Fruit:IsA("Tool") and string.find(Fruit.Name, "Fruit") then
                        mouse1click()
                        task.wait(2)
                        Click(PlayerGui.EatFruitBecky.Dialogue.Collect)
                        task.wait(1)
                        break
                    end
                end
            end)

            if not StoreFruit_Result then
                warn("Erro no store fruit:", StoreFruit_Error)
            end
        end

        local function SelectInventory(InventoryUI)
            for _, Slot in pairs(InventoryUI:GetChildren()) do
                if not Slot:IsA("ImageButton") then continue end

                local ToolName = Slot:FindFirstChild("ToolName")
                if not ToolName then continue end

                local FruitName = ToolName.Text
                if not string.find(FruitName, "Fruit") then continue end

                local Amount = FruitsData[FruitName]
                if Amount == nil or Amount < FruitStorage then
                    StoreFruit(Slot)
                end
            end
        end

        SelectInventory(SlotsInventory)
        task.wait(1)
        SelectInventory(SlotsGameInventory)
    end)

    if not CheckFruits_Result then
        warn("Erro no check fruits: ", CheckFruits_Error)
    end
end

local function IsSeaSerpentActive()
	return MonsterFolder.Boss:FindFirstChild("Serpent")
		or EffectsFolder:FindFirstChild("SerpentWhirlpool")
		or PlayerGui:FindFirstChild("FishingUI")
		or FishingStarted
		or SerpentFollowing
end

local function StopFishing()
    if FishingConnection then
        FishingConnection:Disconnect()
        FishingConnection = nil
    end

    if CurrentFishingTween then
        CurrentFishingTween:Cancel()
        CurrentFishingTween = nil
    end

    if FishingRenderConnection then
        FishingRenderConnection = nil
    end

    FishingStarted = false
end

local function StopFishingLock()
	if FishPositionConnection then
		FishPositionConnection:Disconnect()
		FishPositionConnection = nil
	end

	if BarPositionConnection then
		BarPositionConnection:Disconnect()
		BarPositionConnection = nil
	end

	pcall(function()
		RunService:UnbindFromRenderStep(FISH_BIND)
	end)

	FishingStarted = false
end

local function StartFishing(fishingUI)
	if FishingStarted or not fishingUI or not fishingUI.Parent then return end

	local Background = fishingUI:FindFirstChild("FishingBackground")
	local FishBar = Background and Background:FindFirstChild("FishingBar")
	local FishLabel = Background and Background:FindFirstChild("FishLabel")
	if not FishBar or not FishLabel then return end

	FishingStarted = true
	local Correcting = false

	local function LockFish()
		if Correcting or not fishingUI.Parent then return end

		Correcting = true
		FishLabel.AnchorPoint = FishBar.AnchorPoint
		FishLabel.Position = FishBar.Position
		Correcting = false
	end

	FishPositionConnection = FishLabel:GetPropertyChangedSignal("Position"):Connect(LockFish)
	BarPositionConnection = FishBar:GetPropertyChangedSignal("Position"):Connect(LockFish)

	RunService:BindToRenderStep(FISH_BIND, Enum.RenderPriority.Last.Value, function()
		if not fishingUI.Parent
			or not TOGGLES.AutoSeaSerpent.Value
			or MonsterFolder.Boss:FindFirstChild("Serpent") then

			StopFishingLock()
			return
		end

		LockFish()
	end)

	LockFish()
end

local function SetupFishingConnection()
	if FishingConnection then return end

	FishingConnection = PlayerGui.ChildAdded:Connect(function(gui)
		if gui:IsA("ScreenGui") and gui.Name == "FishingUI" then
			StartFishing(gui)
		end
	end)

	local Existing = PlayerGui:FindFirstChild("FishingUI")
	if Existing then
		StartFishing(Existing)
	end
end

local function AutoSeaSerpent()
    if not TOGGLES.AutoSeaSerpent.Value then
        return
    end
    if SeaSerpentBusy then
        return
    end
    if not FishingConnection then
        SetupFishingConnection()
    end

    SeaSerpentBusy = true
    local ok, err = pcall(function()
        local Character = CharacterUtils.GetCharacter(player)
        if CharacterUtils.IsDead(Character) then return end

        local CharRootPart = Character:FindFirstChild("HumanoidRootPart")
        if not CharRootPart then
            return
        end

        local BossFolder = MonsterFolder.Boss
        local SeaSerpent = BossFolder:FindFirstChild("Serpent")

        if AreasFolder:FindFirstChild("SerpentLocation") then
            Character:PivotTo(CFrame.new(AreasFolder.SerpentLocation.Position)* CFrame.new(0, 150, -400))

            SeaSerpent = BossFolder:FindFirstChild("Serpent")
            if SeaSerpent then
                ChecksToAttack()
                FollowNPC(SeaSerpent, CFrame.new(0, 7, 0) * CFrame.Angles(math.rad(-90), 0, 0))

                SerpentFollowing = true
                local Humanoid = SeaSerpent:FindFirstChild("Humanoid")
                local LastHealth = Humanoid and Humanoid.Health or 0
                local LastDamage = tick()
                while TOGGLES.AutoSeaSerpent.Value and CharacterUtils.IsAlive(Character) and CharacterUtils.IsAlive(SeaSerpent) do
                    if Humanoid then
                        if Humanoid.Health < LastHealth then
                            LastHealth = Humanoid.Health
                            LastDamage = tick()

                        elseif Humanoid.Health > LastHealth then
                            LastHealth = Humanoid.Health
                        end
                    end

                    -- Watchdog
                    if tick() - LastDamage > 30 then
                        warn("[WATCHDOG] Serpent sem tomar dano por 30s")
                        break
                    end
                    M1_Attack()
                    SKILLS_Trigger(SeaSerpent)
                    task.wait(0.1)
                end
                StopFollowing()
                SerpentFollowing = false
            end
            return
        end

        local Whirlpool = EffectsFolder:FindFirstChild("SerpentWhirlpool")
        if not Whirlpool then
            return
        end

        -- Equipa Basic Rod
        if PlayerStats.SwordName.Value ~= "Basic Rod" then
            ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer(
                "EquipWeapon", {WeaponName = "Basic Rod", Type = "Primary"}
            )
            task.wait(1)
        end
        EquipTool("Basic Rod")

        if not SerpentFollowing then
            SerpentFollowing = true
            task.spawn(function()
                FollowNPC(Whirlpool,  CFrame.new(-10, 0, 0) )
                repeat
                    task.wait(0.1)
                until not TOGGLES.AutoSeaSerpent.Value or not CharacterUtils.IsAlive(Character) or BossFolder:FindFirstChild("Serpent")
                StopFollowing()
                SerpentFollowing = false
            end)
        end

        task.wait(1)
        if not TOGGLES.AutoSeaSerpent.Value then
            return
        end
        -- Lança a vara
        ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
            "SW_Basic Rod_M1", {MouseHit = CharRootPart.CFrame, Charge = 100 }
        )
    end)

    if not ok then
        warn("Erro no AutoFarmSeaSerpent:", err)
    end
    SeaSerpentBusy = false
end

local function AutoFarmNPC()
    local AutoNPCFarm_Result, AutoNPCFarm_Error = pcall(function()
        if not OPTIONS.NPCsList or not TOGGLES.AutoFarmNPC.Value then return end

        local Character = CharacterUtils.GetCharacter(player)

        for NPCName, _ in pairs(OPTIONS.NPCsList.Value) do
            local NPCData = NPCsData[NPCName]
            if not NPCData then return end

            if not TOGGLES.AutoFarmNPC.Value or CharacterUtils.IsDead(Character) then
                break
            end

            Character:PivotTo(NPCData.Location)
            local FolderPath = MonsterFolder:FindFirstChild(NPCData.Folder_Path)
            local NPC = WaitForNPC(FolderPath, NPCName, 10)
            if not NPC then
                continue
            end

            ChecksToAttack()
            FollowNPC(NPC, CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(-90), 0, 0))

            local Humanoid = NPC:FindFirstChild("Humanoid")

            local lastHealth = Humanoid.Health
            local lastDamageTime = tick()

            while true do
                if not TOGGLES.AutoFarmNPC.Value or not CharacterUtils.IsAlive(Character) or not CharacterUtils.IsAlive(NPC) then
                    break
                end

                if Humanoid.Health < lastHealth then
                    lastHealth = Humanoid.Health
                    lastDamageTime = tick()
                elseif Humanoid.Health > lastHealth then
                    lastHealth = Humanoid.Health
                end

                if tick() - lastDamageTime > 30 then
                    warn("[WATCHDOG] NPC sem receber dano por 30s: ".. NPC.Name)
                    break
                end

                M1_Attack()
                SKILLS_Trigger(NPC)

                task.wait(.1)
            end
            StopFollowing()
            task.wait(0.25)
        end
        task.wait(0.25)
    end)

    if not AutoNPCFarm_Result then
        warn("Erro no AutoFarmMaterial:", AutoNPCFarm_Error)
    end
end

local function AutoShanks()
    local Shanks = MonsterFolder.Boss:FindFirstChild("Expert Swordman [Lv. 3000]")
    if TOGGLES.AutoShanks.Value and Shanks then
        --// AUTO BIG MOM
        local AutoShanks_Result, AutoShanks_Error = pcall(function()
            local Character = CharacterUtils.GetCharacter(player)
            if not CharacterUtils.IsAlive(Character) then return end

            local BossLocation
            if Shanks then
                BossLocation = InstanceUtils.GetModelCFrame(Shanks)
            end
            Character:PivotTo(BossLocation)

            task.wait(1)

            ChecksToAttack()
            FollowNPC(Shanks, CFrame.new(0,8,0) * CFrame.Angles(math.rad(-90),0,0))

            while task.wait(0.1) do
                if not TOGGLES.AutoShanks.Value then break end
                if not CharacterUtils.IsAlive(Character) or not CharacterUtils.IsAlive(Shanks) then break end

                M1_Attack()
                SKILLS_Trigger(Shanks)
            end
            StopFollowing()
        end)

        if not AutoShanks_Result then
            warn("Error auto shanks: ", AutoShanks_Error)
        end
    end
end

local function AutoBuyFruits()
    local AutoBuyFruits, AutoBuyFruits_Error = pcall(function()
        if TOGGLES.AutoBuyFruits.Value then
            local dfShop = ReplicatedStorage.Chest.Remotes.Functions.GetDFShop:InvokeServer() 
            for dfName, _ in pairs(dfShop) do
                if table.find(DEFAULT_SETTINGS.FruitsToBuy, dfName) then
                    ReplicatedStorage.Chest.Remotes.Functions.BuyFruitStock:InvokeServer(dfName)
                    task.wait(5)
                    CheckFruits()
                end
            end
        end
    end)

    if not AutoBuyFruits then
        warn("Erro na auto buy de frutas:", AutoBuyFruits_Error)
    end
end




SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetFolder("MeuHub")
SaveManager:SetSubFolder(tostring(game.PlaceId))
SaveManager:BuildConfigSection(TABS.Config)
task.wait(0.5) -- CARREGA A CONFIG ANTES DE INICIAR O RESTO DO SCRIPT
local success, err = pcall(function()
    SaveManager:LoadAutoloadConfig()
end)

if not success then
    print("[CONFIG] Autoload processado.")
else
    warn("[CONFIG] Erro ao carregar autoload:", err)
end

task.spawn(function()
    while SCRIPT_RUNNING do
        task.wait(0.5)
        FPSLabel:SetText('<font color="rgb(73, 230, 133)">FPS Cap: </font>'.. tostring(getfpscap()))
    end
end)

task.spawn(function()
	while SCRIPT_RUNNING and task.wait(MainLoopTimer) do
		local ok, err = xpcall(function()
			CheckFruits()
			if TOGGLES.AutoSeaSerpent.Value and IsSeaSerpentActive() then
				AutoSeaSerpent()
				return
			end

			AutoShanks()

			if TOGGLES.AutoLevelUp.Value then
				AutoLevelUp()
            elseif TOGGLES.AutoFarmNPC.Value then
                AutoFarmNPC()
            else
				AutoFarmMaterial()
			end

			AutoSeaSerpent()
			AutoBuyFruits()
		end, debug.traceback)

		if not ok then
			warn("LOOP PRINCIPAL MORREU:", err)
		end
	end
end)

--// AUTO BLACK MARKET ITEM BUYER
local function CheckBlackMarket()
    local success, Data = pcall(function()
        return HttpService:JSONDecode(STOCK_VALUE.Value)
    end)

    if not success then return end
    if type(Data) ~= "table" then return end
    if not Data.Stocks then return end

    for MaterialName, _ in pairs(OPTIONS.MaterialDealerList.Value) do
        local Stock = tonumber(Data.Stocks[MaterialName]) or 0
        if Stock > 0 then
            print("[BLACK MARKET] Comprando:",MaterialName,"Quantidade:",Stock)
            local _, _ = pcall(function()
                return MaterialDealer:InvokeServer("Buy", {
                    Stacks = Stock,
                    MaterialName = MaterialName
                })
            end)
            task.wait(1)
        end
    end
end

CheckBlackMarket()
local BackMarketConnection = STOCK_VALUE.Changed:Connect(function(NewValue)
    print("[BLACK MARKET] STOCK_VALUE mudou!")
    CheckBlackMarket()
end)

--// AUTO PARTY INVITE / ADD
task.spawn(function()
    while SCRIPT_RUNNING and task.wait(30) do
		ReplicatedStorage.Chest.Remotes.Functions.BuyKey:InvokeServer("Copper Key", 10)
        ReplicatedStorage.Chest.Remotes.Functions.MaterialDealer:InvokeServer("Get")

        for _, playerOnServer in pairs(Players:GetChildren()) do
            local sucess, err = pcall(function()
                 ReplicatedStorage.Chest.Remotes.Functions.Ally:InvokeServer({
                    ["Action"] = "Invite",
                    ["Target"] = playerOnServer.Name
                })
                task.wait(0.1)
                ReplicatedStorage.Chest.Remotes.Functions.Ally:InvokeServer({
                    ["Action"] = "Accept",
                    ["Target"] = playerOnServer.Name,
                })
            end)
            if not sucess then
                warn("Erro no auto party invite: " .. err)
            end
        end
        task.wait(30)
    end
    print("AUTO PARTY STOPPED!")
end)

Library:OnUnload(function()
    SaveCurrentConfig()
    if BackMarketConnection ~= nil then
        BackMarketConnection:Disconnect()
    end
    SCRIPT_RUNNING = false
    StopFollowing()
    StopFishing()
end)
