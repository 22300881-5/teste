if game.PlaceId ~= 134039915751463 then
    warn("AutoLevel: entre no Anime Piece antes de executar.")
    return
end

-- Obsidian UI, matching the library used in KING_LEGACY/Sea_1.luau.
local control=getgenv()
local previous=control.AnimePieceAutoLevelUI
if previous and previous.Alive then
    if previous.Library then previous.Library:Toggle() end
    return
end

local CONFIG = {
    CombatMode = "Auto",
    ResetStatsOnModeChange = true,
    Fruit = "Auto", -- Uses the equipped fruit, or the fighting style when no fruit is available.
    Clearance = 2, -- Espaço livre acima do boss, em studs.
    UseM1 = true,
    AutoHaki = true,
    RecoverCombat = true,
    Sword = {
        Enabled = true,
        Name = "Katana",
        AutoBuy = true,
        ResetUnusedDamageStats = true,
        ShopPosition = Vector3.new(406.2994,11.3896,-1044.9919),
    },
    Gather = {
        Enabled = true,
        MaxEnemies = 5,
        Radius = 50,
        TagSeconds = 2.2,
        RallySeconds = 6,
        ClusterRadius = 12,
        MinHealthRatio = 0.55,
    },
    AutoStats = {
        Enabled = true,
        -- Target balance of the used stats; existing investments are preserved.
        Weights = {Defense = 0.50, Damage = 0.30, Stamina = 0.20},
        LowHealthRatio = 0.40,
        LowStaminaRatio = 0.25,
        MaxBatch = 10,
        Interval = 1,
    },
    DefaultHold = 0.3,
    DelayAfterSkill = 0.6,
    HoldTimes = {
        ["Fire Fist"] = 0.3,
        ["Fireflies"] = 1,
        ["Flame Pillar"] = 3,
        ["Blazing Sun"] = 2,
    },
    -- false disables an individual skill.
    EnabledSkills = { ["Flame Up"] = false, ["Flame Pillar"] = false },
}

local Runtime={
    Alive=true, Ready=false, Pending=false, DesiredEnabled=true,
    StopRequested=false, Config=CONFIG, Completed=false, StatsRevision=0, ForceStatsReset=false,
}
control.AnimePieceAutoLevelUI=Runtime
Runtime.UpdateVersion="tremor-live-v1"
Runtime.UpdateSupport=(function()
local Support={}
Support.FruitChests={"Common Fruit Chest","Legendary Fruit Chest","Mythical Fruit Chest"}
function Support.isPhysicalFruit(data,name)
    local item=data and data["Items Data"] and data["Items Data"][name]
    return item~=nil and item.Category=="Fruits"
end
function Support.isFruitChest(name)
    for _,chest in ipairs(Support.FruitChests) do if chest==name then return true end end
    return false
end
function Support.bossNames(data)
    local names={}
    for name,enemy in pairs(data["Enemys Data"] or {}) do
        if enemy.Boss then names[#names+1]=name end
    end
    table.sort(names)
    return names
end
function Support.holdDuration(config,name,details)
    local duration=config.HoldTimes[name]
    if duration==nil then
        duration=details.HoldTime or math.max(config.DefaultHold,(details.MouseFollowTime or 0)+0.05)
    end
    return math.max(0.05,math.min(9,duration))
end
function Support.bossDescription(data,names)
    local lines={}
    for _,name in ipairs(names) do
        local enemy=data["Enemys Data"][name]
        if enemy then
            local drops={}
            for item,chance in pairs(enemy.Drops or {}) do
                drops[#drops+1]=item.." "..tostring(chance).."%"
            end
            table.sort(drops)
            lines[#lines+1]="<b>"..name.."</b> • nível "..tostring(enemy.RecomendedLevel or 0)
                .."\n"..tostring(enemy.Island or "Ilha desconhecida").." • intervalo do catálogo: "
                ..tostring((enemy.RespawnTime or 0)/60).." min\n"..table.concat(drops," • ")
        end
    end
    return table.concat(lines,"\n\n")
end
return Support

end)()
Runtime.Diagnostics={Recoveries=0,History={}}
Runtime.TargetRetryAt=setmetatable({}, {__mode="k"})
local function recordRecovery(reason,action)
    local d=Runtime.Diagnostics
    d.Recoveries+=1
    d.LastFailure=reason
    d.LastAction=action
    d.LastAt=os.clock()
    table.insert(d.History,1,{Reason=reason,Action=action,At=d.LastAt})
    if #d.History>20 then table.remove(d.History) end
end
Runtime.FarmMode="Auto"
Runtime.MoneyQuest="030"
Runtime.MasteryQuest="020"
Runtime.SelectedDrop="Nevercore"
Runtime.SelectedDrops={Nevercore=true}
Runtime.ItemSources={}
Runtime.ItemAmounts={}
Runtime.ItemDefaultAmount=1
Runtime.ItemPriority={}
Runtime.ItemQueueEnabled=true
Runtime.MoneyGoal={Enabled=false,Amount=100000,Basis="Saldo total"}
Runtime.MasteryGoal={Enabled=false,Amount=100}
Runtime.SummonBosses={["Cursed Prodigy"]=true}
Runtime.SummonPriority={"Cursed Prodigy","Dual Swordsman","Beast User"}
Runtime.ItemEnemy="Pro Player"
Runtime.ItemWithQuest=true
Runtime.FruitStorageLimit=1
Runtime.FruitHandoffDelay=2
Runtime.FruitArrivalDelay=4
Runtime.FruitPickupDelay=2
Runtime.FruitBetweenPickupsDelay=5
Runtime.AutoFruitRollEnabled=true
Runtime.PriorityPolicy={Fruit="Interrupt",Roll="Interrupt"}
Runtime.DeferredBosses={}
local function priorityCanRun(kind)
    if Runtime.PriorityPolicy[kind]~="Finish" then Runtime.DeferredBosses[kind]=nil return true end
    local target=Runtime.DeferredBosses[kind]
    if target then
        local h=target.Parent and target:FindFirstChildOfClass("Humanoid")
        return not h or h.Health<=0
    end
    target=Runtime.Pending and Runtime.CombatTarget
    local h=target and target.Parent and target:FindFirstChildOfClass("Humanoid")
    local g=getrenv()._G
    local data=target and g.GameData["Enemys Data"][target:GetAttribute("RealName") or target.Name]
    if h and h.Health>0 and data and data.Boss then
        Runtime.DeferredBosses[kind]=target
        return false
    end
    return true
end
local function automaticRollDue()
    if not Runtime.AutoFruitRollEnabled then Runtime.DeferredBosses.Roll=nil return false end
    if not Runtime.Alive or not Runtime.Ready or not Runtime.AutoFruitRollEnabled or Runtime.FruitRollBusy then return false end
    if os.clock()<(Runtime.FruitRollRetryAt or 0) then return false end
    local ok,state=pcall(Runtime.GetFruitRollState)
    if not ok or not state.ReadyForRoll then Runtime.DeferredBosses.Roll=nil return false end
    return priorityCanRun("Roll")
end
Runtime.FruitCollectorVersion="approach50-v2"
Runtime.HakiGoal=3
Runtime.HakiFarmMaterials=true
Runtime.BossTargets={["Old Fighter"]=true}
Runtime.CustomBossName=""
Runtime.BossNotices={}
local bossIslandPositions={
    ["Tremor Island"]=Vector3.new(-1373.74707,10.36897,1370.02185),
    Foosha=Vector3.new(278.17276,12.34427,-874.81256),
    JungleIsland=Vector3.new(-853.42731,12.34427,80.88744),
    WestIsland=Vector3.new(578.04791,9.20008,2876.02759),
    OnlineIsland=Vector3.new(3494.39209,38.33865,2554.70264),
    SorcerersIsland=Vector3.new(4063.24854,14.25,178.97417),
    ["Good House"]=Vector3.new(2805.02246,13.23216,-2673.62744),
}
Runtime.SummonBoss="Cursed Prodigy"
Runtime.AutoSummonBoss=false
Runtime.FarmSummonMaterial=true
local Scheduler={
    Enabled=false,Fruits=true,Chests=true,Background="Mastery",ChestInterval=120,
    NextChestCheck=0,Current=nil,LastError=nil,
}
Runtime.Automation=Scheduler
local function itemCount(global,name)
    local total=0
    for _,items in pairs(global and global.ClientInventory and global.ClientInventory.Items or {}) do
        for _,item in pairs(items) do
            if item.Name==name then total+=tonumber(item.Amount) or 1 end
        end
    end
    return total
end
local function orderedSelection(selected,priority)
    local names,ranks={},{}
    for index,name in ipairs(priority or {}) do ranks[name]=index end
    for name,enabled in pairs(selected) do if enabled then table.insert(names,name) end end
    table.sort(names,function(a,b)
        local ar,br=ranks[a] or math.huge,ranks[b] or math.huge
        if ar~=br then return ar<br end
        return a<b
    end)
    return names
end
local function itemGoal(global,name)
    local data=global.GameData["Items Data"][name]
    if data and (data.Category=="Swords" or data.Category=="Acessories" or data.Category=="FightStyles") then return 1 end
    return Runtime.ItemAmounts[name] or Runtime.ItemDefaultAmount
end
local function parsePriority(text,catalog)
    local names,seen={},{}
    for raw in text:gmatch("[^;]+") do
        local name=raw:match("^%s*(.-)%s*$")
        assert(catalog[name],"Nome inválido na prioridade: "..name)
        if not seen[name] then table.insert(names,name) seen[name]=true end
    end
    return names
end
local function moveSelectedPriority(selected,priority,name,delta)
    local names=orderedSelection(selected,priority)
    local index=table.find(names,name)
    if not index then return priority end
    local other=math.clamp(index+delta,1,#names)
    names[index],names[other]=names[other],names[index]
    for _,disabled in ipairs(priority) do if not selected[disabled] then table.insert(names,disabled) end end
    return names
end
Runtime.GetItemGoal=function(name) return itemGoal(getrenv()._G,name) end
Runtime.ItemMethod="Drop"
Runtime.AcquisitionName="Shadow Blade"
Runtime.UnlockName="Black Leg"
Runtime.UnlockEquip=true
Runtime.UnlockFarmMaterials=true
Runtime.Reroll={Kind="Race",Races={},Colors={},MaxAttempts=5,Attempts=0,MaxBananas=300,SpentBananas=0,FarmBananas=false,UseBananas=false}
local acquisitionRecipes={
    ["Shadow Blade"]={NPC="Shadow Swordsman",Price=25000,Materials={{"Magic Ball",2}},Event={"Shadow Swordsman","Buy"}},
    ["Dual Sword"]={NPC="Master Blacksmith",Price=25000,Materials={{"Shadow Blade",1},{"Emerald Blade",1},{"Magic Ball",5},{"Dual Essence",1}},Event={"Master Blacksmith","Buy"}},
    ["Crystal Necklace"]={NPC="Jewelry Specialist",Price=10000,Materials={{"Crystal",15},{"Wood Log",50}},Event={"Jewelry Specialist","Buy"}},
    ["Black Leg"]={Kind="Unlock",Style=true,NPC="Sanjiro",Price=15000,Event={"Sanjiro","Buy"},Equip={"Sanjiro","Equip"}},
    ["Robotic Style"]={Kind="Unlock",Style=true,NPC="Robot Trainer",Price=15000,Materials={{"Robotic Gear",45},{"Robotic Core",5}},Event={"RobotTrainer","Buy"},Equip={"RobotTrainer","Equip"}},
    ["Divergent Style"]={Kind="Unlock",Style=true,NPC="Jojo",Price=35000,Materials={{"Cursed Gem",1},{"Sorcerer Card",1}},Event={"Jojo","Buy"},Equip={"Jojo","Equip"}},
    ["Flash Step"]={Kind="Unlock",BuildKey="Flash Step",NPC="Flash Step Trainer",Price=5500,Materials={{"Bandit Soul",15},{"Higaro bandit Soul",15},{"Higaro Soul",5}},Event={"Flash Step","Buy"}},
    ["Ki Dash"]={Kind="Unlock",BuildKey="UnlockedKiDash",Level=200,NPC="Poor Men",Price=10000,Materials={{"Bronze Key",1},{"Silver Key",1},{"Gold Key",1}},Event={"UnlockKiDash","BuyKiDash"},EquipNPC="Yuki",Equip={"UnlockKiDash","EquipKiDash"}},
}
-- O estoque e o custo em bananas vêm do client; nunca usa Game Pass Event.
for _,name in ipairs({"Banana Sword","Monkey Crown","Monkey Cape","Race Reroll","Haki Color Reroll","Reset Stats"}) do
    acquisitionRecipes[name]={NPC="Monkey Trader",MonkeyTrade=true,Price=0}
end
-- Posições verificadas no catálogo físico das lojas; preços são lidos do jogo.
local acquisitionShops={
    ["Tremor Island Pose"]=Vector3.new(-1379.43701,10.62119,1448.89771),
    ["Katana"]=Vector3.new(406.2994384765625,11.38956356048584,-1044.991943359375),
    ["Iron Hoe"]=Vector3.new(124.72117614746094,11.938720703125,-1143.1693115234375),
    ["Axe"]=Vector3.new(-37.5271110534668,11.169857025146484,-1073.8900146484375),
    ["Starter Island Pose"]=Vector3.new(270.9772644042969,11.572649955749512,-1010.753173828125),
    ["Scouter"]=Vector3.new(320.98406982421875,0.774202823638916,2798.326171875),
    ["Future Sword"]=Vector3.new(321.19189453125,6.513886451721191,2778.83544921875),
    ["Wrench"]=Vector3.new(328.5882873535156,6.06666898727417,2781.802490234375),
    ["West Island Pose"]=Vector3.new(328.2483215332031,6.4169416427612305,2794.95361328125),
    ["Female Uniform"]=Vector3.new(4097.7421875,12.584539413452148,341.9189147949219),
    ["Male Uniform"]=Vector3.new(4122.03515625,12.539115905761719,341.92681884765625),
    ["Iron Spear"]=Vector3.new(4093.781005859375,12.849645614624023,330.9104309082031),
    ["Raven Axe"]=Vector3.new(4127.05029296875,13.056303024291992,328.52386474609375),
    ["Sorcerers Island Pose"]=Vector3.new(4115.109375,11.807878494262695,337.0479736328125),
    ["Pickaxe"]=Vector3.new(3593.70849609375,32.82278060913086,2527.551025390625),
    ["Basic Dark Cloak"]=Vector3.new(3626.133056640625,34.306156158447266,2523.886474609375),
    ["Online Island Pose"]=Vector3.new(3483.559326171875,33.242801666259766,2619.530029296875),
    ["Jungle Island Pose"]=Vector3.new(-859.3575439453125,12.296022415161133,91.32001495361328),
    ["Good House Pose"]=Vector3.new(2793.759033203125,13.0787353515625,-2675.343017578125),
}
Runtime.AcquisitionRecipes=acquisitionRecipes
Runtime.AcquisitionShops=acquisitionShops
local function acquisitionOwned(global,name)
    local recipe=acquisitionRecipes[name]
    if not recipe or recipe.Kind~="Unlock" then return itemCount(global,name)>0 end
    local stats=global.GetModule("GetInfos").GetStats()
    if not stats then return false end
    if recipe.Style then
        local unlocks=stats:FindFirstChild("Unlockeds")
        local styles=unlocks and unlocks:FindFirstChild("FightingStyles")
        return styles and styles:FindFirstChild(name)~=nil or false
    end
    local build=stats:FindFirstChild("Build")
    local value=build and build:FindFirstChild(recipe.BuildKey)
    return value and value.Value==true or false
end
Runtime.AcquisitionOwned=function(name) return acquisitionOwned(getrenv()._G,name) end
local function rerollColorName(global)
    local color=game.Players.LocalPlayer:GetAttribute("HakiColor")
    if typeof(color)~="Color3" then return nil end
    for name,value in pairs(global.GameData["HakiColors Data"] or {}) do
        if typeof(value)=="Color3" and math.abs(value.R-color.R)+math.abs(value.G-color.G)+math.abs(value.B-color.B)<0.015 then return name end
    end
end
Runtime.GetHakiColor=function() return rerollColorName(getrenv()._G) end
local Players=game:GetService("Players")
local player=Players.LocalPlayer
local function announcedWorldBoss()
    for name,at in pairs(Runtime.BossNotices) do
        if os.clock()-at<=120 and (Runtime.BossTargets[name] or Runtime.CustomBossName==name) then return name end
    end
end
Runtime.BossNoticeConnections={}
local function watchBossNotice(label)
    if label.Name~="BossName" or not label:IsA("TextLabel") then return end
    local function read()
        if not Runtime.Alive then return end
        local name=label.Text:gsub("<[^>]+>","")
        local g=getrenv()._G
        local data=g and g.GameData and g.GameData["Enemys Data"][name]
        if data and data.Boss then Runtime.BossNotices[name]=os.clock() end
    end
    table.insert(Runtime.BossNoticeConnections,label:GetPropertyChangedSignal("Text"):Connect(read))
    task.defer(read)
end
table.insert(Runtime.BossNoticeConnections,player.PlayerGui.DescendantAdded:Connect(watchBossNotice))
for _,label in ipairs(player.PlayerGui:GetDescendants()) do watchBossNotice(label) end
local function readyWorldBoss()
    local global=getrenv()._G
    local data=global and global.GameData and global.GameData["Enemys Data"]
    if not data then return end
    local function selected(model)
        local name=model:GetAttribute("RealName") or model.Name
        local extra=Runtime.CustomBossName
        local wanted=Runtime.BossTargets[name] or (extra~="" and (name:lower()==extra:lower() or model.Name:lower()==extra:lower()))
        local stats=data[name]
        local h=model:FindFirstChildOfClass("Humanoid")
        return wanted and h and h.Health>0 and model:FindFirstChild("HumanoidRootPart")
            and os.clock()>=(Runtime.TargetRetryAt[model] or 0)
            and (not stats or (player:GetAttribute("Level") or 0)>=(stats.RecomendedLevel or 0))
    end
    local current=Runtime.WorldBossTarget
    if current and current.Parent and selected(current) then return current end
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local best,distance
    for _,model in ipairs(workspace.World.Playability.Enemys:GetChildren()) do
        if model:IsA("Model") and selected(model) then
            local d=root and (root.Position-model.HumanoidRootPart.Position).Magnitude or 0
            if not distance or d<distance then best,distance=model,d end
        end
    end
    Runtime.WorldBossTarget=best
    return best
end
local AntiAfk_Result=pcall(function()
    local connection=getconnections(player.Idled)[1]
    if connection then connection:Disable() end
end)
Runtime.AntiAfk=AntiAfk_Result
local startFarm, stopFarm
local Library, SaveManager
local farmToggle
local saveRevision=0
local function queueSave()
    if not Runtime.Ready or not Runtime.Alive or not SaveManager then return end
    saveRevision+=1
    local revision=saveRevision
    task.delay(0.8,function()
        if Runtime.Alive and revision==saveRevision then
            local ok,err=pcall(function()
                SaveManager:Save("AutoSave")
                SaveManager:SaveAutoloadConfig("AutoSave")
            end)
            if not ok then warn("AutoLevel | Não foi possível salvar a configuração:",err) end
        end
    end)
end

local function runAutoLevel()
local player = game:GetService("Players").LocalPlayer
local rs = game:GetService("ReplicatedStorage")
local enemies = workspace.World.Playability.Enemys
local env, control = getrenv(), getgenv()
local global = env._G
local setIdentity = setthreadidentity or setidentity
local getIdentity = getthreadidentity or getidentity
local combatCategory = "Fruits"
local nextBuildCheck = 0
if control.AutoLevelRunning then warn("O automático já está rodando.") return end
control.AutoLevelRunning = true
control.StopAutoLevel = false

local skills, mouse, originalGet, aimedGet, m1, held, aimRoot
local hookedAim, originalAim
local m1Held = false
local nextUse = {}
local runService = game:GetService("RunService")
local hover
local hoverConnection
local renderBinding = "RobotKingStableHover"
local function stopHover()
    runService:UnbindFromRenderStep(renderBinding)
    if hoverConnection then hoverConnection:Disconnect() hoverConnection = nil end
    local previous = hover
    hover = nil
    if previous then
        if previous.support then previous.support:Destroy() end
        if previous.attachment then previous.attachment:Destroy() end
        for align, enabled in pairs(previous.alignStates) do
            if align.Parent then align.Enabled = enabled end
        end
        if previous.root.Parent then previous.root.Anchored = previous.anchored end
        if previous.humanoid.Parent then previous.humanoid.AutoRotate = previous.autoRotate end
    end
end
local function startHover(character, humanoid, root, boss, bossRoot)
    if hover and hover.root == root and hover.target == bossRoot then return end
    stopHover()
    -- Measure once in the downward-facing pose, keeping the torso clear without
    -- using the character's full standing height as the separation distance.
    local function verticalHalf(part, cf)
        return (math.abs(cf.RightVector.Y)*part.Size.X
            + math.abs(cf.UpVector.Y)*part.Size.Y
            + math.abs(cf.LookVector.Y)*part.Size.Z)*0.5
    end
    local bossTop = bossRoot.Position.Y
    for _, part in ipairs(boss:GetChildren()) do
        if part:IsA("BasePart") then
            bossTop = math.max(bossTop, part.Position.Y + verticalHalf(part,part.CFrame))
        end
    end
    local downward = CFrame.lookAt(Vector3.zero,Vector3.new(0,-1,0),Vector3.zAxis)
    local lowest = -root.Size.Z*0.5
    for _, name in ipairs({"Torso","UpperTorso","LowerTorso","Head"}) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local projected = downward * root.CFrame:ToObjectSpace(part.CFrame)
            lowest = math.min(lowest,projected.Position.Y-verticalHalf(part,projected))
        end
    end
    local radius = math.max(0.5,-lowest)
    local attachment = Instance.new("Attachment")
    attachment.Name = "RobotQuestHoverAttachment"
    attachment.Parent = root
    local support = Instance.new("AlignPosition")
    support.Name = "RobotQuestHoverSupport"
    support.Mode = Enum.PositionAlignmentMode.OneAttachment
    support.Attachment0 = attachment
    support.MaxForce = 1e9
    support.MaxVelocity = 100
    support.Responsiveness = 200
    support.RigidityEnabled = true
    support.Position = root.Position
    support.Parent = root
    hover = {
        support = support, attachment = attachment, alignStates = {},
        root = root, target = bossRoot, humanoid = humanoid,
        anchored = root.Anchored, autoRotate = humanoid.AutoRotate,
        height = bossTop - bossRoot.Position.Y + radius + CONFIG.Clearance,
    }
    local function updateHover()
        local state = hover
        if not state then return end
        if not Runtime.Alive or control.StopAutoLevel or not state.root.Parent or not state.target.Parent
            or state.humanoid.Health <= 0 then
            stopHover()
            return
        end
        state.root.Anchored = false
        local mouseAlign = state.root:FindFirstChild("MouseAlign")
        if mouseAlign then
            if state.alignStates[mouseAlign] == nil then state.alignStates[mouseAlign] = mouseAlign.Enabled end
            mouseAlign.Enabled = false
        end
        state.humanoid.AutoRotate = false
        local target = state.focus and state.focus.Parent and state.focus.Position or state.target.Position
        local position = target + Vector3.new(0, state.height, 0)
        -- The game turns M1 into dialogue while inside an interactive NPC region.
        local npc = global.NpcModel
        state.avoidNpcRoot = (npc and npc.Parent and npc:FindFirstChild("HumanoidRootPart")) or state.avoidNpcRoot
        local npcRoot = state.avoidNpcRoot
        if npcRoot and not npcRoot.Parent then npcRoot = nil end
        if npcRoot and (position - npcRoot.Position).Magnitude < 14 then
            local delta = position - npcRoot.Position
            local horizontal = Vector3.new(delta.X, 0, delta.Z)
            local direction = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.xAxis
            local vertical = position.Y - npcRoot.Position.Y
            local minimum = math.sqrt(math.max(0, 14*14 - vertical*vertical)) + 1
            position = Vector3.new(npcRoot.Position.X, position.Y, npcRoot.Position.Z) + direction*minimum
        end
        state.support.Position = position
        state.root.CFrame = CFrame.lookAt(position, target, Vector3.zAxis)
        state.root.AssemblyLinearVelocity = Vector3.zero
        state.root.AssemblyAngularVelocity = Vector3.zero
    end
    updateHover()
    hoverConnection = runService.PreSimulation:Connect(updateHover)
    -- Apply after camera/mouse-follow scripts as well as before physics.
    runService:BindToRenderStep(renderBinding, Enum.RenderPriority.Last.Value + 1, updateHover)
end
local function gameCall(callback)
    local previous = getIdentity()
    local ok, result = pcall(function() setIdentity(2) return callback() end)
    setIdentity(previous)
    if not ok then error(tostring(result), 0) end
    return result
end
local function checkStop()
    assert(Runtime.Alive and not control.StopAutoLevel, "Parado pelo usuário.")
end
local function waitUntil(callback, timeout)
    local deadline = os.clock() + timeout
    repeat
        checkStop()
        if callback() then return true end
        task.wait(0.1)
    until os.clock() >= deadline
    return false
end
local function releaseM1()
    if m1Held then
        m1Held = false
        gameCall(function() m1.Release() end)
    end
end
local function releaseSkill()
    local current = held
    held = nil
    if current then
        gameCall(function() skills.UseSkill(current.name, current.data, "Release", CONFIG.Fruit) end)
    end
end
local function stopAttacks()
    releaseM1()
    releaseSkill()
end
local function findBoss()
    for _, model in ipairs(enemies:GetChildren()) do
        if model:IsA("Model") and (model.Name == "Robot King" or model:GetAttribute("RealName") == "Robot King") then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then return model, root end
        end
    end
end


-- Progression from level 1 to the current GameData maximum.
local connections = {}
local progressValue, questValue, levelValue, infos, cooldown
local currentSession, combatTarget, lastHealth
local statValues
local statsResetPending = false
local lastStatsCategory
local lastStatsRevision = -1
local nextSwordSetupCheck = 0
local nextEquip, nextCast, nextM1 = 0, 0, 0
local missingFruitSince
local clearGather
local orders
local promptTimes = setmetatable({}, {__mode = "k"})
local function resetCombat()
    Runtime.CombatTarget=nil
    if clearGather then clearGather() end
    stopAttacks()
    stopHover()
    aimRoot, combatTarget = nil, nil
end
Runtime.CleanupCombat=resetCombat
local function activeQuest()
    local id = questValue.Value
    if id ~= "" and id ~= "None" then return id end
end
local function module(name)
    return gameCall(function() return global.GetModule(name) end)
end
local function characterParts()
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return c, h, r end
end
local function teleportTo(cf)
    local c, h, r
    assert(waitUntil(function() c, h, r = characterParts() return r end, 40), "Personagem indisponível.")
    r.Anchored=false
    c:PivotTo(cf)
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.35)
end
local function chooseQuest()
    if Runtime.FarmMode~="Auto" then
        if Runtime.FarmMode=="Money" and Runtime.MoneyGoal.Enabled then
            local money=gameCall(function() return infos.GetValue("Money") end).Value
            Runtime.MoneyGoalStart=Runtime.MoneyGoalStart or money
            local current=Runtime.MoneyGoal.Basis=="Ganho da sessão" and math.max(0,money-(Runtime.MoneyGoalStart or money)) or money
            Runtime.GoalProgress="Dinheiro: $"..current.." / $"..Runtime.MoneyGoal.Amount
            if current>=Runtime.MoneyGoal.Amount then
                Runtime.CompletionMessage="Meta de dinheiro atingida: $"..current
                return nil
            end
        end
        local id=Runtime.FarmMode=="Money" and Runtime.MoneyQuest or Runtime.MasteryQuest
        local data=global.GameData["Quest Data"][id]
        assert(data and levelValue.Value>=data.Level,"Nível insuficiente para a utilidade selecionada.")
        if Runtime.FarmMode=="Mastery" then
            local maximum=global.GameData["Balancing Data"].MaxMastery
            local goal=Runtime.MasteryGoal.Enabled and math.min(maximum,Runtime.MasteryGoal.Amount) or maximum
            local current=gameCall(function() return infos.GetMastery(CONFIG.Fruit) end)
            Runtime.GoalProgress="Mastery "..CONFIG.Fruit..": "..current.." / "..goal
            if current>=goal then
                Runtime.CompletionMessage="Meta de mastery atingida: "..CONFIG.Fruit.." ("..current..")"
                return nil
            end
        end
        return id
    end
    local level = tonumber(levelValue.Value)
    local maximum = global.GameData["Balancing Data"].MaxLevel
    if level >= maximum then return nil end
    local best, highest = nil, -math.huge
    for id, q in pairs(global.GameData["Quest Data"]) do
        if not q.HistoryQuest and q.Level >= 0 and q.Level <= level and q.Level > highest then
            best, highest = id, q.Level
        end
    end
    return best
end
local nextSewerScout = 0
local function useSewerPortal(name, arrived)
    resetCombat()
    local event=rs.Remotes["Teleport Event"]
    local invited=false
    local connection=event.OnClientEvent:Connect(function(action,id)
        if action=="Join" and id==name then invited=true end
    end)
    local ok,err=pcall(function()
        for attempt=1,3 do
            checkStop()
            if arrived() then return end
            local portal=workspace.World.Zones.Teleport:FindFirstChild(name)
            assert(portal,"Portal indisponível: "..name)
            invited=false
            -- Re-enter the trigger so a previous invitation cannot leave us stuck.
            teleportTo(portal.CFrame*CFrame.new(0,0,25))
            task.wait(0.5)
            teleportTo(portal.CFrame)
            waitUntil(function() return invited or arrived() end,6)
            if arrived() then return end
            for confirmation=1,3 do
                event:FireServer(name)
                if waitUntil(arrived,4) then return end
            end
            warn("AutoLevel | Tentando novamente o portal:",name,attempt)
        end
        error("Travessia do portal não confirmada: "..name)
    end)
    connection:Disconnect()
    if not ok then error(err,0) end
    task.wait(0.5)
end
local function enterSewer()
    if player:GetAttribute("CurrentLocation") == "Sewer" then return end
    useSewerPortal("Swear",function() return player:GetAttribute("CurrentLocation")=="Sewer" end)
end
local function leaveSewer()
    if player:GetAttribute("CurrentLocation") ~= "Sewer" then return end
    useSewerPortal("BackSorcererIsland",function() return player:GetAttribute("CurrentLocation")~="Sewer" end)
end

local toolPrerequisites = {
    ["002"] = "Iron Hoe", ["004"] = "Axe", ["005"] = "Iron Hoe", ["012"] = "Wrench",
}
local toolPurchaseQuests = {
    ["Iron Hoe"] = "Buy Iron Hoe", Axe = "Buy Axe", Wrench = "Buy Wrench", Pickaxe = "Buy Pickaxe",
}
local function inventoryHas(name)
    local inventory = global.ClientInventory
    for _, items in pairs(inventory and inventory.Items or {}) do
        for _, item in pairs(items) do
            if item.Name == name and (item.Amount or 1) > 0 then return true end
        end
    end
    return false
end
local function findTool(name)
    local c = player.Character
    return (c and c:FindFirstChild(name)) or player.Backpack:FindFirstChild(name)
end
local function ensureTool(name)
    local ready = findTool(name)
    if ready then return ready end
    if not inventoryHas(name) then
        resetCombat()
        local purchase = global.GameData["Quest Data"][toolPurchaseQuests[name]]
        local data = global.GameData["Items Data"][name]
        assert(purchase and data, "Dados de compra indisponíveis: " .. name)
        local money = gameCall(function() return infos.GetValue("Money") end)
        assert(not money or money.Value >= data.Price, "Dinheiro insuficiente para " .. name .. " ($" .. data.Price .. ").")
        teleportTo(CFrame.new(purchase.Position + Vector3.new(0,3,3)))
        task.wait(0.5)
        rs.Remotes["ItemBuyer Event"]:FireServer(name)
        assert(waitUntil(function() return inventoryHas(name) or findTool(name) end,10), "Compra não confirmada: " .. name)
        print("AutoLevel | Ferramenta comprada:", name)
    end
    if not findTool(name) then
        rs.Remotes["Inventory Event"]:FireServer("Equip", name)
        assert(waitUntil(function() return findTool(name) end,10), "Ferramenta não equipada no inventário: " .. name)
    end
    return findTool(name)
end
local function equipUtility(name)
    local tool = ensureTool(name)
    local c,h = characterParts()
    if not c then return nil end
    if tool.Parent ~= c then h:EquipTool(tool) task.wait(0.35) end
    return tool
end

local ensurePickaxe
local function ensureQuest(id, force)
    if toolPrerequisites[id] then ensureTool(toolPrerequisites[id]) end
    if id ~= "027" then leaveSewer() end
    if id == "023" then ensurePickaxe() end
    if not force and activeQuest() == id then return end
    resetCombat()
    assert(waitUntil(function() return not player:GetAttribute("InDialogue") end, 10), "Conversa não terminou.")
    if activeQuest() then
        rs.Remotes["Quest Event"]:FireServer("Quit")
        assert(waitUntil(function() return not activeQuest() end, 10), "Cancelamento não confirmado.")
    end
    if player:GetAttribute("LastQuest") == id then
        rs.Remotes["Quest Event"]:FireServer("Repeat")
    else
        rs.Remotes["Dialogue Event"]:FireServer({"Quest", id})
    end
    assert(waitUntil(function() return activeQuest() == id end, 10), "Missão não confirmada: " .. id)
    currentSession = id
    promptTimes = setmetatable({}, {__mode = "k"})
    task.wait(0.5)
    print("AutoLevel | Quest:", id, "| Nível:", levelValue.Value)
end
local function promptPosition(prompt)
    local p = prompt.Parent
    if p:IsA("Attachment") then return p.WorldPosition end
    if p:IsA("BasePart") then return p.Position end
    if p:IsA("Model") then return p:GetPivot().Position end
end
local function activatePrompt(prompt, heal)
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    if os.clock() < (promptTimes[prompt] or 0) then return false end
    local position = promptPosition(prompt)
    assert(position, "Posição do prompt indisponível.")
    teleportTo(CFrame.new(position + Vector3.new(0, 0, 3)))
    if not prompt.Parent or not prompt.Enabled then return false end
    promptTimes[prompt] = os.clock() + (heal and 7 or 2)
    if heal then
        firesignal(prompt.PromptButtonHoldBegan, player)
        local ok, err = pcall(function()
            local deadline = os.clock() + 5.5
            repeat checkStop() task.wait(0.1) until not prompt.Parent or os.clock() >= deadline
        end)
        if prompt.Parent then firesignal(prompt.PromptButtonHoldEnded, player) end
        if not ok then error(err) end
    else
        firesignal(prompt.Triggered, player)
        task.wait(0.45)
    end
    return true
end
local function firstPrompt(folder)
    if not folder then return end
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and os.clock() >= (promptTimes[d] or 0) then return d end
    end
end
local function folderPath(...)
    local result = workspace.World.Islands
    for _, name in ipairs({...}) do
        result = result and result:FindFirstChild(name)
    end
    return result
end
local function talk(name, accept)
    local npc
    for _, d in ipairs(workspace.World.IgnoreList.Npcs.Interactive:GetDescendants()) do
        if d:IsA("Model") and d.Name == name and d:FindFirstChild("HumanoidRootPart") then npc = d break end
    end
    assert(npc, "NPC não encontrado: " .. name)
    teleportTo(npc.HumanoidRootPart.CFrame * CFrame.new(0, 0, -4))
    assert(waitUntil(function() return player:GetAttribute("InNpcRegion") == name end, 6), "Região do NPC indisponível: " .. name)
    gameCall(function() global.StartDialogue(name, npc) end)
    if accept and player:GetAttribute("InDialogue") then
        gameCall(function() global.ForceYesDialogue() end)
    end
    assert(waitUntil(function() return not player:GetAttribute("InDialogue") end, 10), "Diálogo não terminou.")
    task.wait(0.3)
end

local colors = {
    {name="Blue",flag="JaEntregouOAzul"}, {name="Pink",flag="JaEntregouORosa"},
    {name="Red",flag="JaEntregouOVermelho"}, {name="Yellow",flag="JaEntregouOAmarelo"},
}
local function elementsStep()
    local carried = player:GetAttribute("ActualElement")
    if carried then
        local color = carried:match("^(%w+) Element$")
        assert(color, "Elemento desconhecido.")
        talk("Normal Scientist " .. color)
        return
    end
    local folder = folderPath("West-Island", "Elements")
    for _, c in ipairs(colors) do
        if not player:GetAttribute(c.flag) then
            local item = folder and folder:FindFirstChild(c.name .. " Element")
            local prompt = item and item:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and activatePrompt(prompt) then
                assert(waitUntil(function() return player:GetAttribute("ActualElement") end, 5), "Coleta de elemento não confirmada.")
                talk("Normal Scientist " .. c.name)
            end
            return
        end
    end
end
local function readOrders()
    if orders then return orders end
    local result = {}
    for _, model in ipairs(workspace:GetChildren()) do
        if model.Name == "Tables" then
            for index = 1, 4 do
                local t = model:FindFirstChild("Table " .. index, true)
                local text = t and t:FindFirstChild("FoodName", true)
                if text and text:IsA("TextLabel") then result[index] = text.Text end
            end
        end
    end
    if next(result) then return result end
end
local function foodStep()
    local root = folderPath("West-Island", "Quest De Comida")
    local foods, tables = root and root:FindFirstChild("Foods"), root and root:FindFirstChild("Mesas")
    if not foods or not tables then return end
    local requested = readOrders()
    if not requested then return end
    local carried
    for _, food in ipairs(foods:GetChildren()) do
        if food:GetAttribute("Ready") and food:FindFirstChild("WeldTopYuki", true) then carried = food break end
    end
    if carried then
        for _, tablePoint in ipairs(tables:GetChildren()) do
            if requested[tonumber(tablePoint.Name)] == carried.Name then
                local prompt = tablePoint:FindFirstChildWhichIsA("ProximityPrompt")
                if prompt and prompt.Enabled then activatePrompt(prompt) return end
            end
        end
        error("Mesa compatível com o prato carregado não encontrada.")
    end
    for _, tablePoint in ipairs(tables:GetChildren()) do
        local prompt = tablePoint:FindFirstChildWhichIsA("ProximityPrompt")
        local foodName = requested[tonumber(tablePoint.Name)]
        if prompt and prompt.Enabled and foodName then
            for _, food in ipairs(foods:GetChildren()) do
                if food.Name == foodName and not food:GetAttribute("Ready") then
                    local pick = food:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if pick then activatePrompt(pick) return end
                end
            end
        end
    end
end
ensurePickaxe = function()
    local function owned()
        local inventory=global.ClientInventory
        for _,item in pairs(inventory and inventory.Items and inventory.Items.Items or {}) do
            if item.Name=="Pickaxe" then return true end
        end
        local c=player.Character
        return player.Backpack:FindFirstChild("Pickaxe")~=nil or (c and c:FindFirstChild("Pickaxe")~=nil)
    end
    local function toolReady()
        local c=player.Character
        return player.Backpack:FindFirstChild("Pickaxe") or (c and c:FindFirstChild("Pickaxe"))
    end
    if toolReady() then return end
    if not owned() then
        resetCombat()
        local items=workspace.World.Playability:FindFirstChild("Items")
        local island=items and items:FindFirstChild("OnlineIsland")
        local shop=island and island:FindFirstChild("Pickaxe")
        local position=shop and shop:GetPivot().Position
            or global.GameData["Quest Data"]["Buy Pickaxe"].Position
        teleportTo(CFrame.new(position+Vector3.new(0,3,3)))
        local money=gameCall(function() return infos.GetValue("Money") end)
        local price=global.GameData["Items Data"].Pickaxe.Price
        assert(not money or money.Value>=price,"Dinheiro insuficiente para a Pickaxe ($"..price..").")
        rs.Remotes["ItemBuyer Event"]:FireServer("Pickaxe")
        assert(waitUntil(owned,10),"Compra da Pickaxe não confirmada.")
        print("AutoLevel | Pickaxe comprada.")
    end
    if not toolReady() then
        rs.Remotes["Inventory Event"]:FireServer("Equip","Pickaxe")
        assert(waitUntil(toolReady,10),"Pickaxe comprada, mas equipamento não confirmado.")
    end
end
local function oreStep()
    ensurePickaxe()
    local c,h,r = characterParts()
    if not r then task.wait(0.5) return end
    local tool = c:FindFirstChild("Pickaxe") or player.Backpack:FindFirstChild("Pickaxe")
    if not tool then return end
    local nearest, distance = nil, math.huge
    for _, ore in ipairs(game:GetService("CollectionService"):GetTagged("CanBreakOre")) do
        if ore:IsA("Model") and ore.Parent and ore.PrimaryPart and not ore:GetAttribute("Died") then
            local d = (r.Position - ore.PrimaryPart.Position).Magnitude
            if d < distance then nearest,distance = ore,d end
        end
    end
    if not nearest then task.wait(0.5) return end
    teleportTo(CFrame.new(nearest.PrimaryPart.Position + Vector3.new(0,0,4), nearest.PrimaryPart.Position))
    if tool.Parent ~= c then h:EquipTool(tool) task.wait(0.4) end
    gameCall(function() module("Items Actions").Use("Pickaxe", tool) end)
    task.wait(1.1)
end

local collectionSupport
local function clearCollectionSupport()
    if not collectionSupport then return end
    local state = collectionSupport
    collectionSupport = nil
    if state.connection then state.connection:Disconnect() end
    if state.support then state.support:Destroy() end
    if state.attachment then state.attachment:Destroy() end
    if state.humanoid.Parent then state.humanoid.AutoRotate = state.autoRotate end
end
local function activateServerPrompt(prompt, treeTop)
    if not prompt or not prompt.Parent or not prompt.Enabled then return end
    local point = promptPosition(prompt)
    assert(point, "Posição de coleta indisponível.")
    local c,h,r = characterParts()
    if not r then return end
    local offset = treeTop and Vector3.new(0,math.min(3,prompt.MaxActivationDistance*0.55),0) or Vector3.new(0,0,3)
    local position = point + offset
    if treeTop then
        clearCollectionSupport()
        local attachment = Instance.new("Attachment",r)
        local support = Instance.new("AlignPosition")
        support.Mode = Enum.PositionAlignmentMode.OneAttachment
        support.Attachment0 = attachment
        support.MaxForce = 1e9
        support.Responsiveness = 200
        support.RigidityEnabled = true
        support.Position = position
        support.Parent = r
        collectionSupport = {support=support,attachment=attachment,humanoid=h,autoRotate=h.AutoRotate}
        collectionSupport.connection = runService.PreSimulation:Connect(function()
            if r.Parent and h.Health > 0 then
                support.Position = position
                r.CFrame = CFrame.new(position)
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
                h.AutoRotate = false
            end
        end)
    end
    local ok, err = pcall(function()
        teleportTo(CFrame.new(position))
        task.wait(0.5)
        checkStop()
        if not prompt.Parent then return end
        if type(fireproximityprompt) == "function" then
            fireproximityprompt(prompt, prompt.HoldDuration)
            task.wait(math.max(0.4,prompt.HoldDuration+0.15))
        else
            prompt:InputHoldBegin()
            local success, failure = pcall(function()
                local deadline = os.clock()+prompt.HoldDuration+0.15
                repeat checkStop() task.wait(0.05) until os.clock()>=deadline
            end)
            if prompt.Parent then prompt:InputHoldEnd() end
            if not success then error(failure) end
        end
    end)
    clearCollectionSupport()
    if not ok then error(err) end
end
local function gardenStep()
    equipUtility("Iron Hoe")
    local folder = folderPath("Foosha-Island","FruitsSpawns","Fruits")
    if not folder then return end
    local center = global.GameData["Quest Data"]["002"].Position
    local _,_,root = characterParts()
    if not root then return end
    local selected, distance
    for _, fruit in ipairs(folder:GetChildren()) do
        if fruit:IsA("BasePart") and fruit:GetAttribute("Type") == "Ok"
            and (fruit.Position-center).Magnitude < 110 then
            local prompt = fruit:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and prompt.Enabled and os.clock() >= (promptTimes[prompt] or 0) then
                local d = (root.Position-fruit.Position).Magnitude
                if not distance or d < distance then selected,distance=prompt,d end
            end
        end
    end
    if selected then
        promptTimes[selected] = os.clock()+3
        activateServerPrompt(selected,true)
    end
end
local function woodStep(anyTree)
    local tool = equipUtility("Axe")
    local c,_,root = characterParts()
    if not root or not tool then return end
    local selected, distance
    for _, tree in ipairs(game:GetService("CollectionService"):GetTagged("CanBreakTree")) do
        if tree:IsA("Model") and tree.Parent and tree.PrimaryPart
            and (anyTree or tree:GetAttribute("QuestTree")) and not tree:GetAttribute("Died") then
            local d = (root.Position-tree.PrimaryPart.Position).Magnitude
            if not distance or d < distance then selected,distance=tree,d end
        end
    end
    if selected then
        local position=selected.PrimaryPart.Position
        teleportTo(CFrame.new(position+Vector3.new(0,0,4),position))
        gameCall(function() module("Items Actions").Use("Axe",tool) end)
        task.wait(0.9)
    end
end
local function farmStep()
    local progress = progressValue.Value
    if progress < 10 then
        equipUtility("Iron Hoe")
        local wheat = folderPath("Foosha-Island","Wheat")
        if not wheat then return end
        for _, item in ipairs(wheat:GetChildren()) do
            if not item:GetAttribute("Collected") and item:FindFirstChildOfClass("Highlight") then
                local prompt=item:FindFirstChildWhichIsA("ProximityPrompt")
                if prompt and prompt.Enabled then activatePrompt(prompt) return end
            end
        end
    elseif progress == 10 then
        talk("Rose",true)
        assert(waitUntil(function() return progressValue.Value>10 or not activeQuest() end,6),"Compra da ração não confirmada.")
    else
        local c,h = characterParts()
        if not c then return end
        local feed=findTool("Horse Feed")
        if not feed then
            waitUntil(function() return findTool("Horse Feed") or activeQuest()~="005" end,3)
            if activeQuest()~="005" then return end
            feed=findTool("Horse Feed")
            if not feed then
                warn("AutoLevel | Ração perdida; reiniciando a fazenda para preparar outra.")
                ensureQuest("005",true)
                return
            end
            c,h=characterParts()
            if not c then return end
        end
        if feed.Parent~=c then h:EquipTool(feed) task.wait(0.3) end
        local prompt=firstPrompt(folderPath("Foosha-Island","Horses"))
        if prompt then activateServerPrompt(prompt,false) end
    end
end
local function bananaStep()
    local prompt=firstPrompt(folderPath("Jungles-Island","Coletar Banana Quest"))
    if prompt then activatePrompt(prompt) end
end
local function hydrantsStep()
    equipUtility("Wrench")
    local prompt=firstPrompt(folderPath("West-Island","Hidrantes","Hidrantes"))
    if prompt then activatePrompt(prompt) end
end

local handlers = {
    ["002"] = gardenStep,
    ["004"] = woodStep,
    ["005"] = farmStep,
    ["008"] = bananaStep,
    ["012"] = hydrantsStep,
    ElementsQuest = elementsStep,
    ["015"] = foodStep,
    ["018"] = function()
        if player:GetAttribute("PegouTodasAsCaixas") or progressValue.Value >= 4 then talk("Jaquin") return end
        local prompt = firstPrompt(folderPath("West-Island","Quest Truck","Folder"))
        if prompt then activatePrompt(prompt) end
    end,
    ["022"] = function()
        if (player:GetAttribute("FlowersQuest") or 0) >= 10 or progressValue.Value >= 10 then talk("Hima") return end
        local prompt = firstPrompt(folderPath("Online-Island","Flowers Quest"))
        if prompt then activatePrompt(prompt) end
    end,
    ["023"] = oreStep,
    ["025"] = function()
        local prompt = firstPrompt(folderPath("Sorcerers-Island","Curse Dools Quest"))
        if prompt then activatePrompt(prompt) end
    end,
    ["028"] = function()
        local prompt = firstPrompt(folderPath("Sorcerers-Island","Heal Sorcerers Quest"))
        if prompt then activatePrompt(prompt,true) end
    end,
    ["030"] = function()
        local prompt = firstPrompt(folderPath("Sorcerers-Island","Tower Curse Quest"))
        if prompt then activatePrompt(prompt) end
    end,
}

local function ensureSwordBuild()
    local config = CONFIG.Sword
    if CONFIG.CombatMode ~= "Auto" or not config.Enabled or held or os.clock() < nextSwordSetupCheck then return end
    nextSwordSetupCheck = os.clock()+2
    local data = global.GameData["Items Data"][config.Name]
    assert(data and global.GameData["AttackableItems Data"].Swords[config.Name], "Espada configurada indisponível.")
    if not inventoryHas(config.Name) and not findTool(config.Name) then
        if not config.AutoBuy then return end
        local money=gameCall(function() return infos.GetValue("Money") end)
        if not money or money.Value < data.Price then return end
        resetCombat()
        local shop
        for _,object in ipairs(workspace.World.Playability.Items:GetDescendants()) do
            if object:IsA("Model") and object.Name==config.Name then shop=object break end
        end
        local position=shop and shop:GetPivot().Position or config.ShopPosition
        teleportTo(CFrame.new(position+Vector3.new(0,3,3)))
        task.wait(0.5)
        rs.Remotes["ItemBuyer Event"]:FireServer(config.Name)
        assert(waitUntil(function() return inventoryHas(config.Name) or findTool(config.Name) end,10),
            "Compra da espada não confirmada.")
        print("AutoLevel | Espada comprada:",config.Name)
    end
    if not findTool(config.Name) then
        rs.Remotes["Inventory Event"]:FireServer("Equip",config.Name)
        assert(waitUntil(function() return findTool(config.Name) end,10),"Espada não liberada no inventário.")
    end
    if config.ResetUnusedDamageStats and CONFIG.AutoStats.Enabled then
        local melee=gameCall(function() return infos.GetValue("FightStyles","Stats") end)
        local fruit=gameCall(function() return infos.GetValue("Fruits","Stats") end)
        local points=gameCall(function() return infos.GetValue("StatsPoints","Stats") end)
        assert(melee and fruit and points,"Stats não carregaram para preparar a espada.")
        local swordPoints=gameCall(function() return infos.GetValue("Swords","Stats") end)
        -- Changing the UI mode must never repeatedly reset a previously established sword build.
        if swordPoints and swordPoints.Value>0 then control.AnimePieceSwordResetDone=true end
        if not control.AnimePieceSwordResetDone and (melee.Value>0 or fruit.Value>0) then
            resetCombat()
            local available=points.Value
            rs.Remotes["Stats Event"]:FireServer("Reset Stats")
            assert(waitUntil(function()
                return melee.Value==0 and fruit.Value==0 and points.Value>=available
            end,10),"Reset gratuito dos stats não confirmado.")
            statValues=nil
            statsResetPending=true
            control.AnimePieceSwordResetDone=true
            print("AutoLevel | Stats resetados; dano será direcionado somente para espada.")
        end
    end
end

local skillList = {}

local function refreshCombatBuild(force)
    if not force and os.clock()<nextBuildCheck then return Runtime.ActiveEquipment~=nil end
    nextBuildCheck=os.clock()+1
    local build=gameCall(function() return infos.GetBuild() end) or {}
    local items=global.GameData["AttackableItems Data"]
    local name, category
    local mode=CONFIG.CombatMode
    if mode=="Sword" then
        if build.Sword and items.Swords[build.Sword] then
            name,category=build.Sword,"Swords"
        elseif inventoryHas(CONFIG.Sword.Name) or findTool(CONFIG.Sword.Name) then
            name,category=CONFIG.Sword.Name,"Swords"
        end
    elseif mode=="Melee" then
        name=build.FightStyle
        if not name or not items.FightStyles[name] then name="Melee" end
        category="FightStyles"
    elseif mode=="Fruit" then
        if build.Fruit and items.Fruits[build.Fruit] then name,category=build.Fruit,"Fruits" end
    elseif CONFIG.Sword.Enabled and (inventoryHas(CONFIG.Sword.Name) or findTool(CONFIG.Sword.Name)) then
        name,category=CONFIG.Sword.Name,"Swords"
    elseif build.Fruit and items.Fruits[build.Fruit] then
        name,category=build.Fruit,"Fruits"
    else
        name=build.FightStyle
        if not name or not items.FightStyles[name] then name="Melee" end
        category="FightStyles"
    end
    if not name then
        resetCombat()
        Runtime.WaitingForTool=mode=="Fruit" and "Equipe uma fruta para usar este modo." or "Equipe uma espada para usar este modo."
        Runtime.ActiveEquipment=nil
        return false
    end
    Runtime.WaitingForTool=nil
    Runtime.ActiveEquipment=name
    Runtime.ActiveCategory=category
    if not force and CONFIG.Fruit==name and combatCategory==category then return true end
    stopAttacks()
    if clearGather then clearGather() end
    CONFIG.Fruit,combatCategory=name,category
    skillList={}
    local data=items[category] and items[category][name]
    assert(data,"Estilo de combate indisponível: "..tostring(name))
    for skill,details in pairs(data.Skills or {}) do
        if (details.Damage or 0)>0 and CONFIG.EnabledSkills[skill]~=false then
            table.insert(skillList,{name=skill,data=details})
        end
    end
    table.sort(skillList,function(a,b) return (a.data.Index or 0)<(b.data.Index or 0) end)
    print("AutoLevel | Combate:",name,category)
    return true
end

local function ensureSelectedStats()
    if not CONFIG.AutoStats.Enabled or not CONFIG.ResetStatsOnModeChange then return end
    local revision=Runtime.StatsRevision or 0
    if lastStatsCategory==combatCategory and lastStatsRevision==revision and not Runtime.ForceStatsReset then return end
    local chosen=combatCategory=="Swords" and "Swords" or (combatCategory=="Fruits" and "Fruits" or "FightStyles")
    local wrong=0
    for _,name in ipairs({"Swords","Fruits","FightStyles"}) do
        local value=gameCall(function() return infos.GetValue(name,"Stats") end)
        assert(value,"Atributos de dano não carregaram.")
        if name~=chosen then wrong+=value.Value end
    end
    if wrong>0 or Runtime.ForceStatsReset then
        resetCombat()
        -- Distribute the recovered points before returning to enemies.
        teleportTo(CFrame.new(CONFIG.Sword.ShopPosition+Vector3.new(0,3,3)))
        local points=gameCall(function() return infos.GetValue("StatsPoints","Stats") end)
        local available=points.Value
        rs.Remotes["Stats Event"]:FireServer("Reset Stats")
        assert(waitUntil(function()
            local sum=0
            for _,name in ipairs({"Defense","Swords","Fruits","FightStyles","Stamina"}) do
                local value=gameCall(function() return infos.GetValue(name,"Stats") end)
                if not value then return false end
                sum+=value.Value
            end
            local remaining=gameCall(function() return infos.GetValue("StatsPoints","Stats") end)
            return sum==0 and remaining and remaining.Value>=available
        end,10),"O jogo não confirmou o reset para "..chosen.."; farm interrompido para preservar a build.")
        statValues=nil
        statsResetPending=true
        print("AutoLevel | Reset confirmado. Dano direcionado para:",chosen)
    end
    Runtime.ForceStatsReset=false
    lastStatsCategory,lastStatsRevision=combatCategory,revision
end

local function findEnemy(q)
    local targets = type(q.Target) == "table" and q.Target or {q.Target}
    if combatTarget and combatTarget.Parent then
        local h = combatTarget:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 and os.clock()>=(Runtime.TargetRetryAt[combatTarget] or 0) and table.find(targets, combatTarget:GetAttribute("RealName") or combatTarget.Name) then
            return combatTarget, combatTarget:FindFirstChild("HumanoidRootPart")
        end
    end
    local _,_,r = characterParts()
    local selected, selectedRoot, distance = nil,nil,math.huge
    for _, model in ipairs(enemies:GetChildren()) do
        if model:IsA("Model") and table.find(targets, model:GetAttribute("RealName") or model.Name) then
            local h = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if h and root and h.Health > 0 and os.clock()>=(Runtime.TargetRetryAt[model] or 0) then
                local d = r and (r.Position-root.Position).Magnitude or 0
                if d < distance then selected,selectedRoot,distance = model,root,d end
            end
        end
    end
    return selected,selectedRoot
end

local gatherState
local nextGather = 0
clearGather = function()
    if gatherState and gatherState.marker then gatherState.marker:Destroy() end
    gatherState = nil
    if hover then hover.focus = nil end
    control.AutoLevelGatherStatus = nil
end
local function gatherStep(q, c, h, r, enemy, enemyRoot)
    local config = CONFIG.Gather
    local remaining = math.max(0, (q.Progress or 1) - progressValue.Value)
    if not config.Enabled or not CONFIG.UseM1 or type(q.Target) ~= "string" or (q.Progress or 1) < 3
        or enemy:GetAttribute("Boss") or h.Health / math.max(h.MaxHealth,1) < config.MinHealthRatio then
        if gatherState then releaseM1() clearGather() nextGather = os.clock()+15 end
        return false
    end
    if gatherState and (gatherState.quest ~= activeQuest() or gatherState.character ~= c) then
        clearGather()
    end
    if not gatherState then
        if remaining < 2 or held or not CONFIG.UseM1 or os.clock() < nextGather then return false end
        local candidates = {}
        for _, model in ipairs(enemies:GetChildren()) do
            if model:IsA("Model") and not model:GetAttribute("Boss")
                and (model:GetAttribute("RealName") or model.Name) == q.Target then
                local mh = model:FindFirstChildOfClass("Humanoid")
                local mr = model:FindFirstChild("HumanoidRootPart")
                if mh and mr and mh.Health > 0 then
                    local distance = (mr.Position - enemyRoot.Position).Magnitude
                    local data = global.GameData["Enemys Data"][q.Target] or {}
                    local radius = math.min(config.Radius, (data.Range or 90)*0.55)
                    if distance <= radius then
                        table.insert(candidates,{model=model,root=mr,humanoid=mh,distance=distance})
                    end
                end
            end
        end
        table.sort(candidates,function(a,b) return a.distance<b.distance end)
        while #candidates > math.min(config.MaxEnemies,remaining) do table.remove(candidates) end
        if #candidates < 2 then nextGather=os.clock()+3 return false end
        local center = Vector3.zero
        for _,candidate in ipairs(candidates) do center+=candidate.root.Position end
        center/=#candidates
        local marker=Instance.new("Part")
        marker.Name="AutoLevelRallyPoint"
        marker.Size=Vector3.one
        marker.Transparency=1
        marker.Anchored=true
        marker.CanCollide=false
        marker.CanTouch=false
        marker.CanQuery=false
        marker.Position=center
        marker.Parent=workspace
        gatherState={
            quest=activeQuest(),character=c,candidates=candidates,marker=marker,
            phase="tag",index=1,phaseStart=os.clock(),tagStart=nil,
        }
        print("AutoLevel | Atraindo grupo:",#candidates,q.Target)
    end
    local state=gatherState
    local alive=0
    for _,candidate in ipairs(state.candidates) do
        if candidate.root.Parent and candidate.humanoid.Parent and candidate.humanoid.Health>0 then alive+=1 end
    end
    if alive==0 then
        releaseM1() clearGather() nextGather=os.clock()+1 return false
    end
    control.AutoLevelGatherStatus={Phase=state.phase,Count=alive,Index=state.index,Quest=state.quest}
    if state.phase=="tag" then
        releaseSkill()
        if hover then hover.focus=nil hover.tagOffset=nil end
        local candidate=state.candidates[state.index]
        if not candidate then
            releaseM1()
            state.phase="rally" state.phaseStart=os.clock()
            return true
        end
        if not candidate.root.Parent or not candidate.humanoid.Parent or candidate.humanoid.Health<=0 then
            releaseM1() state.index+=1 state.tagStart=nil return true
        end
        if not state.tagStart then
            releaseM1()
            state.tagStart=os.clock()
            state.initialHealth=candidate.humanoid.Health
            local delta=r.Position-candidate.root.Position
            local horizontal=Vector3.new(delta.X,0,delta.Z)
            state.tagOffset=(horizontal.Magnitude>0.1 and horizontal.Unit or Vector3.zAxis)*4
        end
        combatTarget,aimRoot=candidate.model,candidate.root
        startHover(c,h,r,candidate.model,candidate.root)
        if hover then hover.tagOffset=state.tagOffset end
        if global.CanAttack~=false and not player:GetAttribute("HoldSkill") and os.clock()>=nextM1 then
            m1Held=true gameCall(function() m1.Hold() end) nextM1=os.clock()+0.5
        end
        if candidate.humanoid.Health<state.initialHealth or os.clock()-state.tagStart>=config.TagSeconds then
            releaseM1()
            state.index+=1 state.tagStart=nil
        end
        return true
    end
    -- Rally at the fixed point, then follow the actual target so M1 stays in range.
    startHover(c,h,r,enemy,enemyRoot)
    if hover then
        hover.focus=state.phase=="rally" and state.marker or nil
        hover.tagOffset=nil
    end
    if state.phase=="rally" then
        releaseM1()
        local clustered=0
        for _,candidate in ipairs(state.candidates) do
            if candidate.root.Parent and candidate.humanoid.Parent and candidate.humanoid.Health>0 then
                local delta=candidate.root.Position-state.marker.Position
                if Vector3.new(delta.X,0,delta.Z).Magnitude<=config.ClusterRadius then clustered+=1 end
            end
        end
        if clustered>=alive or os.clock()-state.phaseStart>=config.RallySeconds then
            state.phase="fight" state.phaseStart=os.clock()
            print("AutoLevel | Ataque em área:",clustered,"alvos reunidos de",alive)
        end
        return true
    end
    if os.clock()-state.phaseStart>30 or remaining<1 then
        clearGather() nextGather=os.clock()+5
    end
    return false
end

local nextHakiActivation=0
local function autoHakiTick()
    if not CONFIG.AutoHaki or os.clock()<nextHakiActivation then return end
    nextHakiActivation=os.clock()+3
    local c=player.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health<=0 or c:GetAttribute("ArmamentHaki")==true then return end
    local stats=gameCall(function() return infos.GetStats() end)
    local build=stats and stats:FindFirstChild("Build")
    local owned=build and build:FindFirstChild("ArmamentHaki")
    if not owned or not owned.Value then return end
    checkStop()
    rs.Remotes["Armament Haki Event"]:FireServer()
end
local combatWatch=setmetatable({}, {__mode="k"})
local function combatStep(q)
    local c,h,r = characterParts()
    if not CONFIG.UseM1 then releaseM1() end
    local enemy, enemyRoot = findEnemy(q)
    if not r or not enemyRoot then resetCombat() task.wait(0.3) return end
    local targetHealth=enemy:FindFirstChildOfClass("Humanoid")
    if targetHealth and CONFIG.RecoverCombat then
        local now=os.clock()
        local watch=combatWatch[enemy]
        if not watch then
            watch={Health=targetHealth.Health,At=now,Attempts=0}
            combatWatch[enemy]=watch
        elseif targetHealth.Health<watch.Health then
            watch.Health,watch.At,watch.Attempts=targetHealth.Health,now,0
            Runtime.Diagnostics.LastProgress=now
        end
        if combatTarget~=enemy then watch.At,watch.FarAt=now,nil end
        watch.Health=targetHealth.Health
        if (r.Position-enemyRoot.Position).Magnitude>25 then watch.FarAt=watch.FarAt or now
        else watch.FarAt=nil end
        if now-watch.At>30 or watch.FarAt and now-watch.FarAt>12 then
            local reason=watch.FarAt and "Personagem não alcançou o alvo" or "Alvo sem receber dano por 30 segundos"
            watch.Attempts+=1
            watch.At,watch.FarAt=now,nil
            resetCombat()
            nextEquip,nextM1,nextCast=0,0,0
            if watch.Attempts>=3 then
                Runtime.TargetRetryAt[enemy]=now+60
                watch.Attempts=0
                recordRecovery(reason,"Alvo em espera por 60 segundos; procurando outra oportunidade")
                return
            end
            recordRecovery(reason,"Reequipando e reposicionando acima de "..enemy.Name.." ("..watch.Attempts.."/3)")
            h:UnequipTools()
            teleportTo(CFrame.new(enemyRoot.Position+Vector3.new(0,enemyRoot.Size.Y/2+8,0)))
            return
        end
    end
    if combatTarget ~= enemy then releaseSkill() releaseM1() end
    combatTarget, aimRoot = enemy,enemyRoot
    Runtime.CombatTarget=enemy
    autoHakiTick()
    assert(not c:GetAttribute("Fly"), "Desative o voo da fruta.")
    startHover(c,h,r,enemy,enemyRoot)
    if not c:FindFirstChild(CONFIG.Fruit) then
        stopAttacks()
        local tool = player.Backpack:FindFirstChild(CONFIG.Fruit)
        if not tool then
            -- Tools can arrive after the character respawns or be reparented while equipping.
            stopHover()
            missingFruitSince = missingFruitSince or os.clock()
            assert(os.clock() - missingFruitSince < 20,"Fruta não encontrada: "..CONFIG.Fruit)
            return
        end
        missingFruitSince = nil
        if os.clock() >= nextEquip then h:EquipTool(tool) nextEquip=os.clock()+1 end
        return
    end
    missingFruitSince = nil
    if player:GetAttribute("ActualTool")~=CONFIG.Fruit or not player:GetAttribute("HasAttackItem") then
        stopAttacks()
        if os.clock()>=nextEquip then
            local equipped=c:FindFirstChild(CONFIG.Fruit)
            if equipped then
                gameCall(function() module("Tool Service").UpdateTool(equipped,"Equip") end)
            end
            nextEquip=os.clock()+1
        end
        return
    end
    if player:GetAttribute("InDialogue") or player:GetAttribute("InNpcRegion") then
        stopAttacks() return
    end
    if gatherStep(q,c,h,r,enemy,enemyRoot) then return end
    if held then
        releaseM1()
        if os.clock()>=held.releaseAt then releaseSkill() nextCast=os.clock()+CONFIG.DelayAfterSkill end
    elseif not player:GetAttribute("HoldSkill") and global.CanAttack~=false then
        if CONFIG.UseM1 and os.clock()>=nextM1 then
            m1Held=true gameCall(function() m1.Hold() end) nextM1=os.clock()+0.5
        end
        if os.clock()>=nextCast then
            local mastery=gameCall(function() return infos.GetMastery(CONFIG.Fruit) end)
            local stamina=gameCall(function() return infos.GetStamina() end)
            for _,entry in ipairs(skillList) do
                local name,data=entry.name,entry.data
                if mastery>=(data.Mastery or 0) and stamina>=(data.Stamina or 0) and os.clock()>=(nextUse[name] or 0)
                    and not gameCall(function() return cooldown.Has(c,name) end) then
                    releaseM1()
                    local duration=Runtime.UpdateSupport.holdDuration(CONFIG,name,data)
                    if data.Hold then held={name=name,data=data,releaseAt=os.clock()+duration} end
                    gameCall(function() skills.UseSkill(name,data,"Hold",CONFIG.Fruit) end)
                    nextUse[name]=os.clock()+(data.Hold and duration or 0)+(data.Cooldown or 1)+0.5
                    nextCast=os.clock()+CONFIG.DelayAfterSkill
                    break
                end
            end
        end
    else releaseM1() end
end

local itemSession,itemScoutAt,itemDamageAt,itemHealth,itemTarget,itemCounted
local itemQueueNextScout,itemQueueScoutIndex=0,0
local function itemFarmStep()
    local pending={}
    local selected=0
    for _,name in ipairs(orderedSelection(Runtime.SelectedDrops,Runtime.ItemPriority)) do
        selected+=1
        if itemCount(global,name)<itemGoal(global,name) then table.insert(pending,name) end
    end
    assert(selected>0,"Selecione pelo menos um item para farmar.")
    Runtime.ItemsRemaining=#pending
    if #pending==0 then
        resetCombat()
        Runtime.ItemState="Todas as metas dos itens selecionados foram atingidas"
        Runtime.CompletionMessage=Runtime.ItemState
        Runtime.Completed=true
        return true
    end
    if itemTarget then
        local health=itemTarget:FindFirstChildOfClass("Humanoid")
        if health and health.Health<=0 and not itemCounted then
            Runtime.ItemKills=(Runtime.ItemKills or 0)+1
            itemCounted=true
            resetCombat()
            task.wait(.7)
            return false
        end
    end
    local chosen,candidates
    local active=combatTarget and combatTarget.Parent and combatTarget:FindFirstChildOfClass("Humanoid")
    if table.find(pending,Runtime.SelectedDrop) and active and active.Health>0
        and os.clock()>=(Runtime.TargetRetryAt[combatTarget] or 0) then
        chosen={Name=Runtime.SelectedDrop,Enemy=Runtime.ItemEnemy}
    end
    candidates={}
    for _,name in ipairs(pending) do
        local sources={}
        for _,source in ipairs(Runtime.ItemCatalog[name] or {}) do table.insert(sources,source) end
        local preferred=Runtime.ItemSources[name]
        table.sort(sources,function(a,b)
            if (a.Enemy==preferred)~=(b.Enemy==preferred) then return a.Enemy==preferred end
            if a.Level~=b.Level then return a.Level<b.Level end
            return a.Enemy<b.Enemy
        end)
        for _,source in ipairs(sources) do
            if source.Level<=levelValue.Value then
                local option={Name=name,Enemy=source.Enemy}
                table.insert(candidates,option)
                if not chosen and (not Runtime.ItemQueueEnabled or findEnemy({Target=source.Enemy})) then chosen=option end
            end
        end
    end
    Runtime.ItemQueueState=#pending.." item(ns) pendente(s); prioridade aplicada aos alvos disponíveis"
    if not chosen then
        resetCombat()
        if #candidates==0 then
            Runtime.ItemState="Os itens pendentes exigem um nível maior."
            task.wait(.5)
            return false
        end
        if os.clock()<itemQueueNextScout then
            Runtime.ItemState="Aguardando alvos; próxima verificação em "..math.ceil(itemQueueNextScout-os.clock()).." s"
            task.wait(.3)
            return false
        end
        itemQueueScoutIndex=itemQueueScoutIndex%#candidates+1
        chosen=candidates[itemQueueScoutIndex]
        itemQueueNextScout=os.clock()+20
        itemScoutAt=0
    end
    if Runtime.SelectedDrop~=chosen.Name or Runtime.ItemEnemy~=chosen.Enemy then
        Runtime.SelectDropForFarm(chosen.Name,chosen.Enemy)
    end
    local name,enemyName=Runtime.SelectedDrop,Runtime.ItemEnemy
    local data=global.GameData["Enemys Data"][enemyName]
    assert(data and data.Drops and data.Drops[name],"Escolha um item e uma fonte de drop válidos.")
    assert(levelValue.Value>=(data.RecomendedLevel or 0),"Nível insuficiente para "..enemyName)
    local count=itemCount(global,name)
    Runtime.ItemCount=count
    if count>=itemGoal(global,name) then
        resetCombat()
        Runtime.ItemState="Item no inventário"
        print("Itens | Item confirmado no inventário:",name,count)
        return false
    end
    local key=name.."|"..enemyName
    if itemSession~=key then
        resetCombat()
        itemSession=key
        itemScoutAt=0
        itemDamageAt=os.clock()
        itemHealth,itemTarget,itemCounted=nil,nil,false
        Runtime.ItemKills=0
    end
    if itemTarget then
        local humanoid=itemTarget:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health<=0 and not itemCounted then
            Runtime.ItemKills+=1
            itemCounted=true
            -- Let the replicated inventory receive the drop before attacking again.
            resetCombat()
            task.wait(0.7)
            return false
        end
    end
    local questId,questData
    if Runtime.ItemWithQuest then
        for id,q in pairs(global.GameData["Quest Data"]) do
            if not q.HistoryQuest and not q.CustomQuest and q.Level<=levelValue.Value and q.Target==enemyName then
                if not questData or q.Level>questData.Level then questId,questData=id,q end
            end
        end
    end
    if data.Island=="Sewer" then enterSewer() else leaveSewer() end
    local query={Target=enemyName,Progress=1}
    local enemy,root=findEnemy(query)
    if not root then
        resetCombat()
        Runtime.ItemState="Aguardando "..enemyName.." aparecer"
        if os.clock()>=(itemScoutAt or 0) then
            local spawnFolder=workspace.World.IgnoreList:FindFirstChild("Enemys Spawn")
            local spawn=spawnFolder and spawnFolder:FindFirstChild(enemyName)
            local position=spawn and spawn:IsA("BasePart") and spawn.Position or questData and questData.Position
            if not position then
                for _,q in pairs(global.GameData["Quest Data"]) do
                    local other=type(q.Target)=="string" and global.GameData["Enemys Data"][q.Target]
                    if other and data.Island and other.Island==data.Island and typeof(q.Position)=="Vector3" then
                        position=q.Position
                        break
                    end
                end
            end
            if not position and data.Island then
                local islandSpawns=workspace.World.IgnoreList:FindFirstChild("Spawnpoint")
                local islandSpawn=islandSpawns and islandSpawns:FindFirstChild(data.Island)
                position=islandSpawn and islandSpawn:IsA("BasePart") and islandSpawn.Position
                    or bossIslandPositions[data.Island]
            end
            if position then
                teleportTo(CFrame.new(position+Vector3.new(0,5,0)))
                task.wait(1)
            else
                Runtime.ItemState="Aguardando spawn especial: "..enemyName
            end
            itemScoutAt=os.clock()+20
        end
        task.wait(0.5)
        return false
    end
    if questId then ensureQuest(questId) end
    if itemTarget~=enemy then
        itemTarget,itemHealth,itemDamageAt,itemCounted=enemy,enemy.Humanoid.Health,os.clock(),false
    end
    local health=enemy.Humanoid.Health
    if health<itemHealth then itemDamageAt=os.clock() end
    itemHealth=health
    Runtime.ItemState="Combatendo "..enemyName
    combatStep(query)
    if os.clock()-itemDamageAt>30 then
        -- Reposition and retry; never impose a kill limit or discard the chosen item.
        resetCombat()
        nextEquip,nextM1,nextCast=0,0,0
        itemDamageAt=os.clock()
    end
    return false
end

local progressionScout={}
local function fightProgressionEnemy(name)
    local data=global.GameData["Enemys Data"][name]
    if data and data.Island=="Sewer" then enterSewer() else leaveSewer() end
    local query={Target=name,Progress=1}
    if not findEnemy(query) then
        resetCombat()
        if os.clock()>=(progressionScout[name] or 0) then
            local folder=workspace.World.IgnoreList:FindFirstChild("Enemys Spawn")
            local spawn=folder and folder:FindFirstChild(name)
            local position=spawn and spawn:IsA("BasePart") and spawn.Position
            if not position then
                for _,q in pairs(global.GameData["Quest Data"]) do
                    if q.Target==name then position=q.Position break end
                end
            end
            if not position and data and data.Island then
                local spawns=workspace.World.IgnoreList:FindFirstChild("Spawnpoint")
                local island=spawns and spawns:FindFirstChild(data.Island)
                position=island and island.Position or bossIslandPositions[data.Island]
            end
            if position then teleportTo(CFrame.new(position+Vector3.new(0,4,0))) task.wait(1) end
            progressionScout[name]=os.clock()+20
        end
        Runtime.BossState="Aguardando "..name.." aparecer"
        return false
    end
    Runtime.BossState="Combatendo "..name
    combatStep(query)
    return true
end
local trySummonBoss,summonQueueStep
local nextBossScout,bossScoutIndex=0,0
local function bossFarmStep()
    -- Boss escolhido e carregado vem antes de farmar materiais de invocação.
    local boss=readyWorldBoss()
    if boss then
        Runtime.WorldBossScout=nil
        local name=boss:GetAttribute("RealName") or boss.Name
        Runtime.BossNotices[name]=nil
        fightProgressionEnemy(name)
        return true
    end
    local notice
    for name,at in pairs(Runtime.BossNotices) do
        if os.clock()-at>120 then Runtime.BossNotices[name]=nil
        elseif Runtime.BossTargets[name] or Runtime.CustomBossName==name then notice=name break end
    end
    if notice and not Runtime.WorldBossScout then
        resetCombat()
        progressionScout[notice]=nil
        Runtime.WorldBossScout={Name=notice,Until=os.clock()+7}
        Runtime.BossNotices[notice]=nil
        fightProgressionEnemy(notice)
        return true
    end
    local scouting=Runtime.WorldBossScout
    if scouting then
        if os.clock()<scouting.Until then
            Runtime.BossState="Carregando a área de "..scouting.Name.." antes de procurar outros alvos"
            task.wait(.25)
            return true
        end
        Runtime.WorldBossScout=nil
    end
    local active=combatTarget and combatTarget.Parent and combatTarget:FindFirstChildOfClass("Humanoid")
    if active and active.Health>0 and os.clock()>=(Runtime.TargetRetryAt[combatTarget] or 0) then
        local name=combatTarget:GetAttribute("RealName") or combatTarget.Name
        local keep=Runtime.BossTargets[name]
        if Runtime.AutoSummonBoss then
            local sources={["Cursed Prodigy"]="White Panda",["Dual Swordsman"]="Emerald Swordsman",["Beast User"]="Frieza"}
            local materials={["Cursed Prodigy"]="Prodigy Orb",["Dual Swordsman"]="Dual Orb",["Beast User"]="Mad Chip"}
            for boss,enabled in pairs(Runtime.SummonBosses) do
                -- Com o material já no inventário, larga a fonte e vai invocar.
                local hasItem=materials[boss] and (findTool(materials[boss]) or itemCount(global,materials[boss])>0)
                if enabled and (name==boss or sources[boss]==name and not hasItem) then keep=true end
            end
        end
        if keep then fightProgressionEnemy(name) return true end
    end
    if not boss then
        if Runtime.FarmMode=="Bosses" and os.clock()>=nextBossScout then
            local candidates={}
            for name,enabled in pairs(Runtime.BossTargets) do
                local data=global.GameData["Enemys Data"][name]
                if enabled and data and levelValue.Value>=(data.RecomendedLevel or 0) then
                    table.insert(candidates,name)
                end
            end
            local extra=Runtime.CustomBossName
            local extraData=global.GameData["Enemys Data"][extra]
            if extraData and not Runtime.BossTargets[extra] and levelValue.Value>=(extraData.RecomendedLevel or 0) then table.insert(candidates,extra) end
            table.sort(candidates)
            if #candidates>0 then
                bossScoutIndex=bossScoutIndex%#candidates+1
                nextBossScout=os.clock()+20
                resetCombat()
                Runtime.WorldBossScout={Name=candidates[bossScoutIndex],Until=os.clock()+7}
                fightProgressionEnemy(candidates[bossScoutIndex])
                Runtime.BossState="Verificando spawn: "..candidates[bossScoutIndex]
                return false
            end
        end
        if Runtime.AutoSummonBoss and summonQueueStep and summonQueueStep() then return true end
        resetCombat()
        Runtime.BossState="Aguardando os bosses selecionados aparecerem no client"
        task.wait(.5)
        return false
    end
    fightProgressionEnemy(boss:GetAttribute("RealName") or boss.Name)
    return true
end
local hakiNpcPositions={
    ["Purple Men"]=Vector3.new(4690.1298828125,7.3234453201293945,589.501220703125),
    ["Glitch Men"]=Vector3.new(-1180.3992919921875,9.363519668579102,60.28862380981445),
    Ronks=Vector3.new(-122.6120376586914,6.918270111083984,-986.1283569335938),
    ["Miss Water"]=Vector3.new(116.1204833984375,7.118257522583008,-879.981201171875),
    AnnyecookieGM=Vector3.new(302.8396301269531,6.918270111083984,-1041.3275146484375),
    Sanjiro=Vector3.new(332.703125,8.636311,-1525.867188),
    ["Robot Trainer"]=Vector3.new(922.858643,7.723563,3587.249023),
    Jojo=Vector3.new(4317.605957,9.62524,178.897842),
    ["Flash Step Trainer"]=Vector3.new(648.13385,13.9601,-977.011108),
    ["Poor Men"]=Vector3.new(1145.473267,1.025978,3221.104004),
    ["Jewelry Specialist"]=Vector3.new(3575.980957,33.541794,3057.435547),
}
local function hakiNpcPosition(name)
    for _,folder in ipairs({workspace.World.IgnoreList.Npcs.Interactive,rs}) do
        for _,model in ipairs(folder:GetDescendants()) do
            if model:IsA("Model") and model.Name==name and model:FindFirstChildWhichIsA("BasePart",true) then
                local root=model:FindFirstChild("HumanoidRootPart")
                return root and root.Position or model:GetPivot().Position
            end
        end
    end
    return hakiNpcPositions[name]
end
local function hakiNpcEvent(npc,event,confirmed,beforeSend)
    checkStop()
    if confirmed() then return end
    resetCombat()
    leaveSewer()
    local position=hakiNpcPosition(npc)
    assert(position,"NPC não encontrado: "..npc)
    teleportTo(CFrame.new(position+Vector3.new(0,3,4)))
    task.wait(1)
    checkStop()
    if confirmed() then return end
    if beforeSend then beforeSend() end
    rs.Remotes["Dialogue Event"]:FireServer(event)
    assert(waitUntil(confirmed,8),"O servidor não confirmou a etapa com "..npc)
end
local function hakiQuest(id)
    if activeQuest()==id then return end
    if activeQuest() then
        resetCombat()
        rs.Remotes["Quest Event"]:FireServer("Quit")
        assert(waitUntil(function() return not activeQuest() end,8),"Não foi possível liberar a quest atual.")
    end
    hakiNpcEvent("Purple Men",{"Quest",id},function() return activeQuest()==id end)
end
local summonRecipes={
    ["Cursed Prodigy"]={NPC="Noko",Item="Prodigy Orb",Source="White Panda",Event={"Noko","SpawnProdigy"}},
    ["Dual Swordsman"]={NPC="Seraphina",Item="Dual Orb",Source="Emerald Swordsman",Event={"Seraphina","SpawnDual"}},
    ["Beast User"]={NPC="Mad Scientist",Item="Mad Chip",Source="Frieza",Event={"BrollyRaid","Start"},Raid=true},
}
local nextSummonAttempt={}
trySummonBoss=function(name)
    local recipe=summonRecipes[name]
    assert(recipe,"Invocação não configurada para "..tostring(name))
    local data=global.GameData["Enemys Data"][name]
    assert(levelValue.Value>=(data.RecomendedLevel or 0),"Nível insuficiente para "..name)
    if findEnemy({Target=name}) then return fightProgressionEnemy(name) end
    if recipe.Raid and rs:FindFirstChild("BrollyRaid") then
        resetCombat()
        Runtime.BossState="Portal do Beast aberto; procurando entrada"
        local raid=workspace.World.Raids:FindFirstChild("Brolly Raid")
        local portal=raid and (raid:FindFirstChild("Portal",true) or raid:FindFirstChild("Teleport",true))
        if not portal and raid then
            for _,part in ipairs(raid:GetDescendants()) do
                if part:IsA("BasePart") and part:FindFirstChildWhichIsA("TouchTransmitter") then portal=part break end
            end
        end
        if portal then
            local position=portal:IsA("BasePart") and portal.Position or portal:IsA("Model") and portal:GetPivot().Position
            if position then
                teleportTo(CFrame.new(position))
                local prompt=portal:FindFirstChildWhichIsA("ProximityPrompt",true)
                if prompt and type(fireproximityprompt)=="function" then fireproximityprompt(prompt) end
                task.wait(2)
            end
        else
            Runtime.BossState="Portal do Beast ativo; entrada ainda não identificada no client"
            task.wait(.5)
        end
        return false
    end
    if not Runtime.AutoSummonBoss then return false end
    if not findTool(recipe.Item) and itemCount(global,recipe.Item)<1 then
        Runtime.BossState="Falta "..recipe.Item.." para invocar "..name
        if Runtime.FarmSummonMaterial then return fightProgressionEnemy(recipe.Source) end
        resetCombat()
        task.wait(.5)
        return false
    end
    if os.clock()<(nextSummonAttempt[name] or 0) then resetCombat() task.wait(.3) return false end
    nextSummonAttempt[name]=os.clock()+15
    if not findTool(recipe.Item) then
        rs.Remotes["Inventory Event"]:FireServer("Equip",recipe.Item)
        assert(waitUntil(function() return findTool(recipe.Item) end,8),"Material não chegou à mochila: "..recipe.Item)
    end
    Runtime.BossState="Invocando "..name.." com 1x "..recipe.Item
    hakiNpcEvent(recipe.NPC,recipe.Event,function()
        return findEnemy({Target=name}) or recipe.Raid and rs:FindFirstChild("BrollyRaid")
    end)
    return false
end
local summonRetryAt={}
local nextSummonScout,summonScoutIndex,nextPortalCheck,summonScoutUntil=0,0,0,0
summonQueueStep=function()
    local names=orderedSelection(Runtime.SummonBosses,Runtime.SummonPriority)
    local eligible={}
    for _,name in ipairs(names) do
        local data=global.GameData["Enemys Data"][name]
        if summonRecipes[name] and data and levelValue.Value>=(data.RecomendedLevel or 0)
            and os.clock()>=(summonRetryAt[name] or 0) then table.insert(eligible,name) end
    end
    local function attempt(name)
        local ok,result=pcall(trySummonBoss,name)
        if not ok then
            if control.StopAutoLevel or not Runtime.Alive then error(result) end
            summonRetryAt[name]=os.clock()+60
            recordRecovery(tostring(result),"Invocação em espera por 60 s; tentando outro objetivo")
        end
        return true
    end
    local current=combatTarget and combatTarget.Parent and combatTarget:FindFirstChildOfClass("Humanoid")
    if current and current.Health>0 and os.clock()>=(Runtime.TargetRetryAt[combatTarget] or 0) then
        local name=combatTarget:GetAttribute("RealName") or combatTarget.Name
        for _,boss in ipairs(eligible) do
            local item=summonRecipes[boss].Item
            local hasItem=findTool(item) or itemCount(global,item)>0
            if name==boss or name==summonRecipes[boss].Source and not hasItem then fightProgressionEnemy(name) return true end
        end
    end
    -- Bosses already alive are handled before spending another invocation item.
    for _,name in ipairs(eligible) do if findEnemy({Target=name}) then return attempt(name) end end
    for _,name in ipairs(eligible) do
        local recipe=summonRecipes[name]
        local activeRaid=recipe.Raid and rs:FindFirstChild("BrollyRaid")
        if not activeRaid and os.clock()>=(nextSummonAttempt[name] or 0) and (findTool(recipe.Item) or itemCount(global,recipe.Item)>0) then
            Runtime.SummonQueueState="Prioridade: invocar "..name
            return attempt(name)
        end
    end
    for _,name in ipairs(eligible) do
        local recipe=summonRecipes[name]
        if Runtime.FarmSummonMaterial and not findTool(recipe.Item) and itemCount(global,recipe.Item)<1 and not (recipe.Raid and rs:FindFirstChild("BrollyRaid"))
            and findEnemy({Target=recipe.Source}) then
            Runtime.SummonQueueState="Buscando "..recipe.Item.." em "..recipe.Source.." para "..name
            fightProgressionEnemy(recipe.Source)
            return true
        end
    end
    if os.clock()>=nextPortalCheck then
        for _,name in ipairs(eligible) do
            if summonRecipes[name].Raid and rs:FindFirstChild("BrollyRaid") then
                nextPortalCheck=os.clock()+20
                Runtime.SummonQueueState="Verificando portal de "..name
                return attempt(name)
            end
        end
    end
    Runtime.SummonQueueState="Sem boss ou fonte de material disponível; verificando outros objetivos"
    if os.clock()<summonScoutUntil then
        Runtime.SummonQueueState="Aguardando os inimigos da área carregarem..."
        task.wait(.3)
        return true
    end
    if Runtime.FarmSummonMaterial and #eligible>0 and os.clock()>=nextSummonScout then
        summonScoutIndex=summonScoutIndex%#eligible+1
        nextSummonScout=os.clock()+20
        local name=eligible[summonScoutIndex]
        local recipe=summonRecipes[name]
        if not findTool(recipe.Item) and itemCount(global,recipe.Item)<1 and not (recipe.Raid and rs:FindFirstChild("BrollyRaid")) then
            Runtime.SummonQueueState="Verificando spawn de "..recipe.Source.." para "..name
            fightProgressionEnemy(recipe.Source)
            summonScoutUntil=os.clock()+3
            return true
        end
    end
    return false
end
local function hakiMoneyStep(required)
    local money=gameCall(function() return infos.GetValue("Money") end)
    if money.Value>=required then return true end
    Runtime.HakiState="Farmando dinheiro: $"..money.Value.." / $"..required
    local id=Runtime.MoneyQuest
    local q=global.GameData["Quest Data"][id]
    if not q or q.Level>levelValue.Value then id="ElementsQuest" end
    ensureQuest(id)
    resetCombat()
    handlers[id]()
    return false
end
local function acquisitionMoneyStep(required,name)
    local money=gameCall(function() return infos.GetValue("Money") end)
    if money.Value>=required then return true end
    Runtime.ItemState="Farmando dinheiro: $"..money.Value.." / $"..required.." para "..name
    local id=Runtime.MoneyQuest
    local q=global.GameData["Quest Data"][id]
    if not q or q.Level>levelValue.Value then
        local highest=-math.huge
        id=nil
        for candidate,data in pairs(global.GameData["Quest Data"]) do
            if not data.HistoryQuest and data.Level>=0 and data.Level<=levelValue.Value and data.Level>highest
                and (handlers[candidate] or findEnemy(data)) then id,highest=candidate,data.Level end
        end
    end
    assert(id,"Nenhuma quest disponível para farmar dinheiro.")
    ensureQuest(id)
    if handlers[id] then resetCombat() handlers[id]() else combatStep(global.GameData["Quest Data"][id]) end
    return false
end
local nextResourceScout=0
local function acquisitionMaterialStep(required,amount)
    local have=itemCount(global,required)
    if have>=amount then return true end
    if required=="Wood Log" or required=="Crystal" then
        resetCombat()
        leaveSewer()
        if required=="Wood Log" and activeQuest()=="004" then
            rs.Remotes["Quest Event"]:FireServer("Quit")
            assert(waitUntil(function() return activeQuest()~="004" end,8),"Não foi possível liberar a coleta de madeira do inventário.")
        end
        local tags=game:GetService("CollectionService"):GetTagged(required=="Crystal" and "CanBreakOre" or "CanBreakTree")
        local loaded=false
        for _,model in ipairs(tags) do if model.Parent and model:IsA("Model") and model.PrimaryPart then loaded=true break end end
        if not loaded and os.clock()>=nextResourceScout then
            nextResourceScout=os.clock()+15
            local q=global.GameData["Quest Data"][required=="Crystal" and "023" or "004"]
            teleportTo(CFrame.new(q.Position+Vector3.new(0,3,0)))
            task.wait(1.5)
        end
        if required=="Crystal" then oreStep() else woodStep(true) end
        return false
    end
    local best,bestScore
    for enemy,stats in pairs(global.GameData["Enemys Data"]) do
        local chance=stats.Drops and stats.Drops[required]
        if type(chance)=="number" and chance>0 and stats.Health
            and levelValue.Value>=(stats.RecomendedLevel or 0) then
            local score=(findEnemy({Target=enemy}) and 1000000 or 0)+chance/math.max(1,stats.Health)
            if not bestScore or score>bestScore then best,bestScore=enemy,score end
        end
    end
    assert(best,"Nenhuma fonte acessível de "..required.." neste nível.")
    if Runtime.AutoSummonBoss and summonRecipes[best] and not findEnemy({Target=best}) then trySummonBoss(best)
    else fightProgressionEnemy(best) end
    return false
end
local function monkeyTradeReady(name)
    local stock=rs:FindFirstChild("MonkeyTraderStock")
    return stock and stock:FindFirstChild(name) and hakiNpcPosition("Monkey Trader")
end
local function acquisitionStep(name,depth)
    depth=depth or 0
    assert(depth<8,"Ciclo nos requisitos de "..tostring(name))
    local pending=Runtime.PurchasePending
    if pending then
        assert(waitUntil(pending.Confirmed,10),"Compra anterior sem confirmação: "..pending.Name..". Nenhuma nova compra foi enviada.")
        Runtime.PurchasePending=nil
    end
    if acquisitionOwned(global,name) then
        if depth==0 then
            resetCombat()
            Runtime.Completed=true
            Runtime.ItemState="Objetivo confirmado no client"
            Runtime.CompletionMessage="Item obtido: "..name
        end
        return true
    end
    local recipe=acquisitionRecipes[name]
    local shop=acquisitionShops[name]
    local data=global.GameData["Items Data"][name]
    assert(recipe or (shop and data and type(data.Price)=="number"),"Compra não configurada: "..tostring(name))
    if recipe and recipe.Level then assert(levelValue.Value>=recipe.Level,name.." exige nível "..recipe.Level..".") end
    local materials=recipe and recipe.Materials or {}
    if recipe and recipe.MonkeyTrade then
        assert(data and type(data.BananaPrice)=="number","Preço em bananas indisponível: "..name)
        materials={{"Banana",data.BananaPrice}}
    end
    for _,material in ipairs(materials) do
        local required,amount=material[1],material[2]
        local have=itemCount(global,required)
        if have<amount then
            Runtime.ItemState="Buscando "..required..": "..have.." / "..amount.." para "..name
            assert(not recipe or recipe.Kind~="Unlock" or Runtime.UnlockFarmMaterials,"Falta "..required..". Ative Buscar materiais faltantes ou obtenha manualmente.")
            if acquisitionRecipes[required] or acquisitionShops[required] then
                acquisitionStep(required,depth+1)
                return false
            end
            acquisitionMaterialStep(required,amount)
            Runtime.ItemState="Buscando "..required..": "..have.." / "..amount.." | "..tostring(Runtime.BossState)
            return false
        end
    end
    local price=recipe and recipe.Price or data.Price
    if not acquisitionMoneyStep(price,name) then return false end
    checkStop()
    Runtime.ItemState="Comprando "..name.." por $"..price
    local function confirmed() return acquisitionOwned(global,name) end
    local function beginPurchase() Runtime.PurchasePending={Name=name,Confirmed=confirmed} end
    if recipe and recipe.MonkeyTrade then
        assert(not data.NoRealItem,"Use o objetivo Raça e cor para rerolls. Reset Stats é feito em Combate.")
        if not monkeyTradeReady(name) then
            resetCombat() Runtime.ItemState="Aguardando Monkey Trader e estoque de "..name task.wait(1) return false
        end
        resetCombat() leaveSewer()
        teleportTo(CFrame.new(hakiNpcPosition(recipe.NPC)+Vector3.new(0,3,4)))
        task.wait(1) checkStop()
        if not acquisitionOwned(global,name) then beginPurchase() rs.Remotes["MonkeyTrader Event"]:FireServer(name) end
        assert(waitUntil(function() return acquisitionOwned(global,name) end,10),"Troca não confirmada: "..name..". Interrompido para evitar gastos repetidos.")
    elseif recipe then
        hakiNpcEvent(recipe.NPC,recipe.Event,confirmed,beginPurchase)
    else
        resetCombat()
        leaveSewer()
        teleportTo(CFrame.new(shop+Vector3.new(0,3,3)))
        task.wait(1)
        checkStop()
        if itemCount(global,name)==0 then beginPurchase() rs.Remotes["ItemBuyer Event"]:FireServer(name) end
        assert(waitUntil(function() return itemCount(global,name)>0 end,10),"Compra não confirmada: "..name..". Interrompido para evitar gastos repetidos.")
    end
    print("AutoLevel | Item adquirido:",name)
    return acquisitionStep(name,depth)
end
local function unlockStep()
    local name=Runtime.UnlockName
    local recipe=acquisitionRecipes[name]
    assert(recipe and recipe.Kind=="Unlock","Escolha um desbloqueio válido.")
    if not acquisitionStep(name,1) then return false end
    if Runtime.UnlockEquip and recipe.Equip then
        local function equipped()
            local stats=gameCall(function() return infos.GetStats() end)
            return recipe.Style and stats.Build.ActualFightingStyle.Value==name
                or name=="Ki Dash" and stats.Build.DashType.Value=="KiDash"
        end
        hakiNpcEvent(recipe.EquipNPC or recipe.NPC,recipe.Equip,equipped)
    end
    resetCombat()
    Runtime.Completed=true
    Runtime.CompletionMessage="Desbloqueio concluído: "..name
    Runtime.ItemState=Runtime.CompletionMessage
    return true
end
local function rerollStep()
    local state=Runtime.Reroll
    local function points()
        return gameCall(function() return infos.GetValue("RaceRerollPoints","Stats") end).Value
    end
    -- Guarda a solicitação entre pausas: retomar nunca envia outra antes de resolver esta.
    if state.Pending then
        local ticket=state.Pending
        local function received()
            if ticket.Kind=="RaceToken" then return points()>ticket.Points end
            if ticket.Kind=="Race" then
                local current=gameCall(function() return infos.GetValue("ActualRace") end).Value
                return points()<ticket.Points and (current~=ticket.Before or ticket.Ack or os.clock()-ticket.At>=8)
            end
            return itemCount(global,"Banana")<ticket.Bananas and player:GetAttribute("HakiColor")~=nil and os.clock()-ticket.At>=3
        end
        assert(waitUntil(received,35),"Reroll sem confirmação do servidor. Solicitação preservada; nenhum novo gasto será enviado.")
        if ticket.Kind=="Race" then
            -- O ponto pode diminuir antes de a nova raça ser replicada.
            local deadline=os.clock()+3
            repeat checkStop() task.wait(.1) until os.clock()>=deadline
        end
        state.Pending=nil
        return false
    end
    local isRace=state.Kind=="Race"
    local selected=isRace and state.Races or state.Colors
    assert(next(selected),"Selecione pelo menos um resultado desejado em Raça e cor.")
    local current=isRace and gameCall(function() return infos.GetValue("ActualRace") end).Value or rerollColorName(global)
    assert(current,"O client ainda não informou a cor do Haki. Nenhuma banana foi gasta.")
    if selected[current] then
        resetCombat()
        Runtime.Completed=true
        Runtime.CompletionMessage=(isRace and "Raça" or "Cor do Haki").." desejada obtida: "..current
        state.Status=Runtime.CompletionMessage
        return true
    end
    if state.Attempts>=state.MaxAttempts then
        Runtime.Completed=true
        Runtime.CompletionMessage="Limite de rerolls atingido: "..state.Attempts.." / "..state.MaxAttempts
        state.Status=Runtime.CompletionMessage
        resetCombat()
        return true
    end
    if isRace then assert(player:GetAttribute("CanGacha")~=false,"O servidor desativou o reroll de raça nesta sessão.") end
    local available=isRace and points() or 0
    if isRace and available>0 then
        resetCombat()
        checkStop()
        state.Pending={Kind="Race",Points=available,Before=current,At=os.clock()}
        state.Attempts+=1
        state.Status="Aguardando resultado da raça • tentativa "..state.Attempts
        rs.Remotes["Race Event"]:FireServer("Spin Race")
        return false
    end
    assert(state.UseBananas,"Sem reroll disponível. Permita usar bananas para comprar tentativas no Monkey Trader.")
    local item=isRace and "Race Reroll" or "Haki Color Reroll"
    local data=global.GameData["Items Data"][item]
    local price=data and data.BananaPrice
    assert(type(price)=="number" and price>0,"Custo do reroll indisponível.")
    if state.SpentBananas+price>state.MaxBananas then
        Runtime.Completed=true
        Runtime.CompletionMessage="Limite de bananas atingido: "..state.SpentBananas.." / "..state.MaxBananas
        state.Status=Runtime.CompletionMessage resetCombat() return true
    end
    if itemCount(global,"Banana")<price then
        assert(state.FarmBananas,"Bananas insuficientes. Ative Farmar bananas faltantes ou obtenha manualmente.")
        state.Status="Farmando bananas: "..itemCount(global,"Banana").." / "..price
        acquisitionMaterialStep("Banana",price)
        return false
    end
    if not monkeyTradeReady(item) then
        resetCombat() state.Status="Aguardando Monkey Trader e estoque de "..item task.wait(1) return false
    end
    resetCombat() leaveSewer()
    teleportTo(CFrame.new(hakiNpcPosition("Monkey Trader")+Vector3.new(0,3,4)))
    task.wait(1) checkStop()
    if not monkeyTradeReady(item) then state.Status="Estoque mudou; aguardando vendedor." return false end
    assert(itemCount(global,"Banana")>=price,"Saldo de bananas mudou antes da troca.")
    state.Pending={Kind=isRace and "RaceToken" or "Color",Points=points(),Bananas=itemCount(global,"Banana"),Before=current,At=os.clock()}
    state.SpentBananas+=price
    if not isRace then state.Attempts+=1 end
    state.Status="Aguardando "..item.." • bananas usadas: "..state.SpentBananas
    rs.Remotes["MonkeyTrader Event"]:FireServer(item)
    return false
end
local hakiBossScout=0
local function hakiStep()
    local stats=gameCall(function() return infos.GetStats() end)
    local build=stats and stats:FindFirstChild("Build")
    assert(build and build:FindFirstChild("ArmamentHaki") and build:FindFirstChild("HakiLevel"),"Dados do Haki indisponíveis.")
    local owned=build.ArmamentHaki.Value
    local version=owned and build.HakiLevel.Value or 0
    Runtime.HakiVersion=version
    if version>=Runtime.HakiGoal then
        resetCombat()
        Runtime.HakiState="Objetivo concluído: Haki V"..version
        Runtime.CompletionMessage=Runtime.HakiState
        Runtime.Completed=true
        return true
    end
    assert(levelValue.Value>=200,"O Haki V1 exige nível 200.")
    local history=stats:FindFirstChild("History Quest")
    local function done(id) local value=history and history:FindFirstChild(id) return value and value.Value end
    local function count(name) return itemCount(global,name) end
    if not owned then
        if not done("ArmamentHakiQuest1") then
            Runtime.HakiState="V1: causar 100.000 de dano | "..tostring(progressValue.Value)
            hakiQuest("ArmamentHakiQuest1")
            fightProgressionEnemy("Special Student")
        elseif not done("ArmamentHakiQuest2") then
            Runtime.HakiState="V1: preparar 5 Banana Splits | "..count("Banana Split").."/5"
            if not hakiMoneyStep(1000) then return false end
            hakiQuest("ArmamentHakiQuest2")
            if count("Banana Split")>=5 then
                hakiNpcEvent("Purple Men",{"ArmamentHaki","BananaSplityVerify"},function() return done("ArmamentHakiQuest2") end)
            elseif count("Banana")<5 then
                fightProgressionEnemy("Monkey")
            elseif count("Water Bucket")<2 then
                local before=count("Water Bucket")
                hakiNpcEvent("Miss Water",{"Miss Water","Buy"},function() return count("Water Bucket")>before end)
            else
                local before=count("Banana Split")
                hakiNpcEvent("AnnyecookieGM",{"AnnyeCookieGM","Buy"},function() return count("Banana Split")>before end)
            end
        elseif not done("ArmamentHakiQuest3") then
            Runtime.HakiState="V1: derrotar 25 bosses | "..tostring(progressValue.Value).."/25"
            hakiQuest("ArmamentHakiQuest3")
            local selected
            for name,data in pairs(global.GameData["Enemys Data"]) do
                if data.Boss and (data.RecomendedLevel or 0)<=levelValue.Value and findEnemy({Target=name}) then
                    if not selected or data.Health<global.GameData["Enemys Data"][selected].Health then selected=name end
                end
            end
            local rotation={"Higaro","King Monkey","Robot King","Crimson King","Frieza","White Panda"}
            if not selected then
                if os.clock()>=hakiBossScout then
                    Runtime.HakiBossIndex=(Runtime.HakiBossIndex or 0)%#rotation+1
                    hakiBossScout=os.clock()+20
                end
                selected=rotation[Runtime.HakiBossIndex or 1]
            end
            fightProgressionEnemy(selected)
        else
            Runtime.HakiState="Aprendendo Haki V1: $50.000"
            if hakiMoneyStep(50000) then
                hakiNpcEvent("Purple Men",{"ArmamentHaki","Learn"},function() return build.ArmamentHaki.Value end)
            end
        end
    else
        local price=version==1 and 35000 or 50000
        Runtime.HakiState="V"..(version+1)..": Armament Crystal "..count("Armament Crystal").."/1 | Magic Ball "..count("Magic Ball").."/1"
        if count("Armament Crystal")<1 or count("Magic Ball")<1 then
            if not Runtime.HakiFarmMaterials then resetCombat() task.wait(.5) return false end
            if count("Magic Ball")<1 then fightProgressionEnemy("Old Fighter")
            elseif Runtime.AutoSummonBoss then trySummonBoss("Beast User")
            else
                Runtime.HakiState="Falta Armament Crystal: aguardando Beast User. Permita invocações para usar Mad Chip."
                fightProgressionEnemy("Beast User")
            end
        elseif hakiMoneyStep(price) then
            local npc=version==1 and "Glitch Men" or "Ronks"
            local action=version==1 and "UpgradeHakiV2" or "UpgradeHakiV3"
            hakiNpcEvent(npc,{"ArmamentHaki",action},function() return build.HakiLevel.Value>version end)
        end
    end
    return false
end

local nextStatsCheck, staminaPressureUntil, defensePressureUntil = 0, 0, 0
local lowStaminaSamples = 0
local previousHealth, previousHumanoid
local function autoStatsTick(force)
    local config = CONFIG.AutoStats
    if not config.Enabled or held or (not force and os.clock() < nextStatsCheck) then return end
    nextStatsCheck = os.clock() + config.Interval
    local c, h = characterParts()
    local now = os.clock()
    if statsResetPending then defensePressureUntil=0 staminaPressureUntil=0 lowStaminaSamples=0 end
    if h and not statsResetPending then
        local ratio = h.Health / math.max(h.MaxHealth, 1)
        if ratio < config.LowHealthRatio
            or (h == previousHumanoid and previousHealth and previousHealth - h.Health > h.MaxHealth * 0.15) then
            defensePressureUntil = now + 30
        end
        previousHumanoid, previousHealth = h, h.Health
    end
    if not statsResetPending and combatTarget and c and player:GetAttribute("ActualTool") == CONFIG.Fruit then
        local resource = gameCall(function() return {infos.GetStamina()} end)
        local current, maximum = resource[1], resource[2]
        if maximum and maximum > 0 and current / maximum < config.LowStaminaRatio then
            lowStaminaSamples += 1
            if lowStaminaSamples >= 2 then staminaPressureUntil = now + 30 end
        else
            lowStaminaSamples = 0
        end
    end
    if not statValues then
        statValues = {}
        for _, name in ipairs({"Defense","Fruits","FightStyles","Swords","Stamina","StatsPoints"}) do
            statValues[name] = gameCall(function() return infos.GetValue(name,"Stats") end)
            assert(statValues[name], "Stat indisponível: " .. name)
        end
    end
    local free = math.floor(statValues.StatsPoints.Value)
    if free <= 0 then return end
    local cap = global.GameData["Balancing Data"].MaxPoints
    local damageStat = combatCategory == "Swords" and "Swords" or (combatCategory == "Fruits" and "Fruits" or "FightStyles")
    local weights = {Defense=config.Weights.Defense,Stamina=config.Weights.Stamina,[damageStat]=config.Weights.Damage}
    local simulated, plan, total = {}, {}, 0
    local order = {"Defense", "Stamina", damageStat}
    for _, name in ipairs(order) do
        simulated[name] = statValues[name].Value
        total += simulated[name]
    end
    local batch = math.min(free, config.MaxBatch)
    for index = 1, batch do
        local selected, largest = nil, -math.huge
        if now < staminaPressureUntil and index <= math.max(1,math.floor(batch*0.4))
            and simulated.Stamina < cap then
            selected = "Stamina"
        elseif now < defensePressureUntil and index <= math.max(1,math.floor(batch*0.6))
            and simulated.Defense < cap then
            selected = "Defense"
        else
            local weightTotal = 0
            for _,name in ipairs(order) do
                if simulated[name] < cap then weightTotal += weights[name] or 0 end
            end
            if weightTotal <= 0 then break end
            for _, name in ipairs(order) do
                if simulated[name] < cap and (weights[name] or 0) > 0 then
                    local deficit = (total + 1) * weights[name] / weightTotal - simulated[name]
                    if deficit > largest then selected, largest = name, deficit end
                end
            end
        end
        if not selected then break end
        simulated[selected] += 1
        plan[selected] = (plan[selected] or 0) + 1
        total += 1
    end
    for _, name in ipairs(order) do
        local requested = plan[name]
        if requested then
            checkStop()
            local before = statValues[name].Value
            local available = math.floor(statValues.StatsPoints.Value)
            local amount = math.min(requested, available, cap - before)
            if amount > 0 then
                rs.Remotes["Stats Event"]:FireServer("UsePoints", name, amount)
                local accepted = waitUntil(function()
                    return statValues[name].Value >= before + amount
                end, 4)
                if not accepted then
                    warn("AutoStats | Distribuição não confirmada:",name)
                    nextStatsCheck = os.clock() + 15
                    return
                end
                print("AutoStats |",name,"+",amount,"=",statValues[name].Value)
            end
        end
    end
    control.AutoStatsStatus = {
        Defense = statValues.Defense.Value,
        Fruits = statValues.Fruits.Value,
        FightStyles = statValues.FightStyles.Value,
        Swords = statValues.Swords.Value,
        Stamina = statValues.Stamina.Value,
        FreePoints = statValues.StatsPoints.Value,
        LowHealth = now < defensePressureUntil,
        LowStamina = now < staminaPressureUntil,
    }
end


local function finishSwordReset()
    if not statsResetPending then return end
    local points=gameCall(function() return infos.GetValue("StatsPoints","Stats") end)
    while points and points.Value>0 do
        checkStop()
        local before=points.Value
        autoStatsTick(true)
        assert(points.Value<before,"Distribuição após o reset não avançou; farm pausado.")
    end
    statsResetPending=false
end

local success, err = pcall(function()
    assert(not control.RobotFruitRunning and not control.ElementsQuestRunning, "Pare os automáticos anteriores antes de iniciar AutoLevel.")
    assert(type(setIdentity)=="function" and type(getIdentity)=="function","Controle de identidade indisponível.")
    assert(type(firesignal)=="function" and type(hookfunction)=="function","firesignal/hookfunction indisponíveis.")
    assert(waitUntil(function()
        global = env._G
        return global and global.GameData and type(global.GetModule) == "function"
    end, 40), "Aguarde o jogo e o personagem carregarem antes de executar.")
    assert(waitUntil(function()
        infos=infos or module("GetInfos")
        cooldown=cooldown or module("Cooldown")
        skills=skills or module("Skills Action")
        mouse=mouse or module("GetMousePosition")
        return infos and cooldown and skills and mouse
    end,40),"Módulos de combate ainda não carregaram.")
    assert(waitUntil(function()
        levelValue=gameCall(function() return infos.GetValue("Level") end)
        questValue=gameCall(function() return infos.GetValue("QuestId") end)
        progressValue=gameCall(function() return infos.GetValue("Progress") end)
        return levelValue and questValue and progressValue
    end,40),"Valores da conta ainda não carregaram.")
    assert(tonumber(levelValue.Value)>=0,"Aguarde o personagem carregar.")
    local keys=env.shared or shared
    m1=keys and keys.Keys and keys.Keys.M1
    assert(not CONFIG.UseM1 or m1,"M1 indisponível.")
    ensureSwordBuild()
    if refreshCombatBuild(true) then ensureSelectedStats() finishSwordReset() end
    originalGet=mouse.Get
    hookedAim=originalGet
    originalAim=hookfunction(hookedAim,function(...)
        if aimRoot and aimRoot.Parent then return aimRoot.Position end
        return originalAim(...)
    end)
    aimedGet=function(...)
        if aimRoot and aimRoot.Parent then return aimRoot.Position end
        return originalAim(...)
    end
    mouse.Get=aimedGet
    local foodEvent=rs.Remotes["Specials Remotes"]:FindFirstChild("Jaquin Event")
    if foodEvent then
        table.insert(connections,foodEvent.OnClientEvent:Connect(function(action,data)
            if action=="Start" then orders=data elseif action=="End" then orders=nil end
        end))
    end
    local watchedQuest, watchedProgress, lastAdvance = nil,nil,os.clock()
    table.insert(connections,rs.Remotes["Race Event"].OnClientEvent:Connect(function(action)
        local ticket=Runtime.Reroll.Pending
        if action=="Update" and ticket and ticket.Kind=="Race" then ticket.Ack=true end
    end))
    local stalls = {}
    local damageTarget, damageHealth
    local scoutedQuest, nextScout = nil, 0
    while true do
        checkStop()
        autoHakiTick()
        ensureSwordBuild()
        if not refreshCombatBuild() then
            resetCombat()
            task.wait(0.5)
            continue
        end
        ensureSelectedStats()
        finishSwordReset()
        autoStatsTick()
        if Scheduler.Enabled and Scheduler.Bosses and (readyWorldBoss() or announcedWorldBoss() or Runtime.WorldBossScout) then
            bossFarmStep()
            task.wait(.15)
            continue
        end
        if Runtime.FarmMode=="Bosses" then
            if Runtime.WatchBossesOnly and not readyWorldBoss() and not announcedWorldBoss() and not Runtime.WorldBossScout then resetCombat() break end
            bossFarmStep()
            task.wait(.15)
            continue
        end
        if Runtime.FarmMode=="Haki" then
            if hakiStep() then break end
            task.wait(.15)
            continue
        end
        if Runtime.FarmMode=="Unlocks" or Runtime.FarmMode=="Rerolls" then
            if Runtime.FarmMode=="Unlocks" and unlockStep() or Runtime.FarmMode=="Rerolls" and rerollStep() then break end
            task.wait(.15)
            continue
        end
        if Runtime.FarmMode=="Items" then
            local done
            if Runtime.ItemMethod=="Purchase" then done=acquisitionStep(Runtime.AcquisitionName)
            else done=itemFarmStep() end
            if done then break end
            task.wait(0.15)
            continue
        end
        local recommended=chooseQuest()
        if not recommended then
            autoStatsTick(true)
            Runtime.Completed=true
            print("AutoLevel |",Runtime.CompletionMessage or ("Nível máximo atingido: "..levelValue.Value))
            break
        end
        local data=global.GameData["Quest Data"][recommended]
        if recommended == "027" and (findEnemy(data) or os.clock() >= nextSewerScout) then
            enterSewer()
            nextSewerScout = os.clock() + 30
        elseif recommended ~= "027" then
            leaveSewer()
        end
        -- Enemies on distant islands are not present in the client until the area loads.
        if recommended ~= "027" and not handlers[recommended] and not findEnemy(data)
            and (scoutedQuest ~= recommended or os.clock() >= nextScout) then
            resetCombat()
            if typeof(data.Position) == "Vector3" then
                teleportTo(CFrame.new(data.Position + Vector3.new(0, 3, 0)))
                task.wait(1.5)
            end
            scoutedQuest, nextScout = recommended, os.clock() + 30
        end
        local selected=recommended
        local preserveProgress = activeQuest() == recommended and progressValue.Value > 0
        if Runtime.FarmMode=="Auto" and not handlers[recommended] and not findEnemy(data) and not preserveProgress then
            -- Farm a known custom quest while the recommended combat target is absent.
            local best=-math.huge
            for id,handler in pairs(handlers) do
                local q=global.GameData["Quest Data"][id]
                if q and q.Level<=levelValue.Value and q.Level<data.Level and q.Level>best then
                    selected,best=id,q.Level
                end
            end
        end
        -- Finish a carried element/plate before abandoning an active fallback quest.
        if activeQuest() and activeQuest()~=selected then
            if activeQuest()=="ElementsQuest" and player:GetAttribute("ActualElement") then elementsStep()
            elseif activeQuest()=="015" then
                local foods=folderPath("West-Island","Quest De Comida","Foods")
                local carrying=false
                if foods then for _,food in ipairs(foods:GetChildren()) do
                    if food:GetAttribute("Ready") and food:FindFirstChild("WeldTopYuki",true) then carrying=true break end
                end end
                if carrying then foodStep() end
            end
        end
        ensureQuest(selected)
        local value=progressValue.Value
        if watchedQuest~=selected or watchedProgress~=value then
            if watchedQuest == selected and watchedProgress and value > watchedProgress then stalls[selected] = 0 end
            watchedQuest,watchedProgress,lastAdvance=selected,value,os.clock()
            control.AutoLevelStatus={Level=levelValue.Value,Quest=selected,Progress=value,Recommended=recommended}
        end
        local handler=handlers[selected]
        if handler then resetCombat() handler()
        else combatStep(global.GameData["Quest Data"][selected]) end
        if not handler and combatTarget then
            local health = combatTarget:FindFirstChildOfClass("Humanoid")
            if health then
                if damageTarget == combatTarget and damageHealth and health.Health < damageHealth then
                    lastAdvance = os.clock()
                    stalls[selected] = 0
                end
                damageTarget, damageHealth = combatTarget, health.Health
            end
        end
        local waitingForRemainingTarget = not handler and activeQuest() == selected
            and progressValue.Value > 0 and not findEnemy(global.GameData["Quest Data"][selected])
        if waitingForRemainingTarget then
            -- Never discard partial combat progress merely because the next target is respawning.
            lastAdvance = os.clock()
            if control.AutoLevelStatus then control.AutoLevelStatus.WaitingForSpawn = true end
        elseif control.AutoLevelStatus then
            control.AutoLevelStatus.WaitingForSpawn = false
        end
        if activeQuest()==selected and os.clock()-lastAdvance>90 then
            if not handler then
                resetCombat()
                nextEquip,nextM1,nextCast=0,0,0
                recordRecovery("Missão sem progresso recente: "..selected,"Combate reiniciado, preservando a missão e seu progresso")
                lastAdvance=os.clock()
                task.wait(.15)
                continue
            end
            stalls[selected] = (stalls[selected] or 0) + 1
            assert(stalls[selected]<=3,"Sem progresso na missão "..selected..". Verifique AutoLevelStatus.")
            warn("AutoLevel | Reiniciando missão sem progresso:",selected)
            ensureQuest(selected,true)
            lastAdvance=os.clock()
        end
        task.wait(0.15)
    end
end)
pcall(clearCollectionSupport)
if clearGather then pcall(clearGather) end
pcall(releaseM1)
pcall(releaseSkill)
pcall(stopHover)
aimRoot=nil
for _,connection in ipairs(connections) do connection:Disconnect() end
if mouse and aimedGet and mouse.Get==aimedGet then mouse.Get=originalGet end
if hookedAim and originalAim then pcall(function() hookfunction(hookedAim,originalAim) end) end
control.AutoLevelRunning=false
Runtime.LastError=not success and not control.StopAutoLevel and Runtime.Alive and tostring(err) or nil
if not success then warn("AutoLevel interrompido: "..tostring(err)) end
-- Stop with: getgenv().StopAutoLevel = true
end

local function setStatusText(label,text)
    local setIdentity=setthreadidentity or setidentity
    local getIdentity=getthreadidentity or getidentity
    local previous=type(getIdentity)=="function" and getIdentity() or nil
    if type(setIdentity)=="function" then setIdentity(7) end
    local ok,result=pcall(label.SetText,label,text)
    if previous and type(setIdentity)=="function" then setIdentity(previous) end
    if not ok then error(result) end
end

local function waitForFruitHandoff(cancelled)
    Runtime.FruitStatus="Encerrando ataques e movimento do farm..."
    local started=os.clock()
    local deadline=started+12
    while (Runtime.Pending or control.AutoLevelRunning) and not cancelled() and os.clock()<deadline do task.wait(.1) end
    if cancelled() then return false end
    assert(not Runtime.Pending and not control.AutoLevelRunning,"O farm anterior ainda está encerrando; fruta adiada.")
    if Runtime.CleanupCombat then
        local ok,err=pcall(Runtime.CleanupCombat)
        assert(ok,"Não foi possível liberar o combate: "..tostring(err))
    end
    local releasedAt=os.clock()
    local stableSince
    repeat
        if cancelled() then return false end
        local c=player.Character
        local root=c and c:FindFirstChild("HumanoidRootPart")
        local human=c and c:FindFirstChildOfClass("Humanoid")
        assert(root and human and human.Health>0,"Personagem indisponível durante a transição para a fruta.")
        local support=c:FindFirstChild("RobotQuestHoverSupport",true)
        local held=player:GetAttribute("HoldSkill") or c:GetAttribute("HoldSkill")
        local v=root.AssemblyLinearVelocity
        local horizontal=Vector3.new(v.X,0,v.Z).Magnitude
        local ready=not held and not c:GetAttribute("Fly") and not support and horizontal<8
        if ready then stableSince=stableSince or os.clock() else stableSince=nil end
        Runtime.FruitStatus=held and "Aguardando a skill terminar antes de ir à fruta..."
            or "Estabilizando personagem antes da coleta..."
        if stableSince and os.clock()-stableSince>=.5 and os.clock()-releasedAt>=Runtime.FruitHandoffDelay then
            Runtime.LastFruitHandoff={Elapsed=os.clock()-started,HorizontalSpeed=horizontal,CombatStopped=true}
            return true
        end
        task.wait(.1)
    until os.clock()>=deadline
    error("O personagem ainda está sob efeito de movimento, skill ou voo; coleta adiada.")
end
local function stageFruitAtSpawn(cancelled)
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local human=c and c:FindFirstChildOfClass("Humanoid")
    assert(root and human and human.Health>0,"Personagem indisponível para ir ao spawn seguro.")
    local folder=workspace.World.IgnoreList:FindFirstChild("Spawnpoint")
    local spawn,distance
    for _,part in ipairs(folder and folder:GetChildren() or {}) do
        if part:IsA("BasePart") then
            local d=(part.Position-root.Position).Magnitude
            if not distance or d<distance then spawn,distance=part,d end
        end
    end
    assert(spawn,"Nenhum spawnpoint seguro foi encontrado.")
    Runtime.FruitStatus="Indo ao spawn seguro: "..spawn.Name
    local origin,anchored=root.CFrame,root.Anchored
    local landed=false
    local function cleanup()
        if root.Parent then
            if not landed then root.CFrame=origin end
            root.Anchored=anchored
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
        end
    end
    Runtime.CancelFruitStaging=cleanup
    local ok,err=pcall(function()
        root.Anchored=true
        root.CFrame=CFrame.new(spawn.Position+Vector3.new(0,4,0))
        task.spawn(function() pcall(function() player:RequestStreamAroundAsync(spawn.Position,6) end) end)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={c,workspace.World.IgnoreList,workspace.World.Playability.Enemys}
        local floor
        local deadline=os.clock()+8
        repeat
            if cancelled() then return end
            floor=workspace:Raycast(root.Position+Vector3.new(0,4,0),Vector3.new(0,-50,0),params)
            if floor and floor.Material~=Enum.Material.Water and (floor.Instance:IsA("Terrain") or floor.Instance.CanCollide) then break end
            floor=nil task.wait(.2)
        until os.clock()>=deadline
        assert(floor,"O chão do spawn não carregou; coleta adiada.")
        if cancelled() then return end
        local height=human.HipHeight+root.Size.Y/2+(human.RigType==Enum.HumanoidRigType.R6 and 2 or 0)
        root.CFrame=CFrame.new(floor.Position+Vector3.new(0,height,0))
        local untilTime=os.clock()+1
        Runtime.FruitStatus="Aguardando no spawn seguro antes de buscar a fruta..."
        while not cancelled() and os.clock()<untilTime do task.wait(.1) end
        if cancelled() then return end
        landed=true
        Runtime.LastFruitSafeSpawn={Name=spawn.Name,Position=spawn.Position}
    end)
    cleanup()
    Runtime.CancelFruitStaging=nil
    if not ok then error(err) end
    return landed
end
local function collectDevilFruits(priorityOwned)
    if Runtime.FruitCollecting or Runtime.FruitRollBusy then return end
    if Runtime.PriorityBusy and not priorityOwned then
        Runtime.FruitStatus="Aguarde a operação atual terminar antes de coletar frutas."
        return
    end
    local dropped=workspace.World.Playability:FindFirstChild("DroppedTools")
    local fruitData=getrenv()._G.GameData["AttackableItems Data"].Fruits
    local found=false
    for _,prompt in ipairs(dropped and dropped:GetDescendants() or {}) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled
            and fruitData[prompt.ObjectText:gsub("<[^>]+>",""):gsub(" Fruit$","")] then found=true break end
    end
    if not found then Runtime.FruitStatus="Nenhuma devil fruit disponível para coletar." return end
    local ownsPriority=not Runtime.PriorityBusy
    local resume=Runtime.Pending or Runtime.DesiredEnabled
    if ownsPriority then Runtime.PriorityBusy=true end
    Runtime.FruitCollecting=true
    Runtime.FruitCancel=false
    Runtime.DesiredEnabled=false
    control.StopAutoLevel=true
    if farmToggle then farmToggle:SetValue(false) end
    local currentTween,currentRoot,wasAnchored
    local collectionDeadline=os.clock()+35+Runtime.FruitPickupDelay*2
    local function cancelled()
        return Runtime.FruitCancel or not Runtime.Alive or os.clock()>=collectionDeadline or automaticRollDue()
    end
    local function cleanMovement()
        if currentTween then currentTween:Cancel() currentTween=nil end
        if currentRoot and currentRoot.Parent then
            currentRoot.Anchored=wasAnchored
            currentRoot.AssemblyLinearVelocity=Vector3.zero
        end
        currentRoot=nil
    end
    Runtime.CancelFruitMovement=cleanMovement
    local function inventorySnapshot()
        local result={}
        local global=getrenv()._G
        for _,item in pairs(global.ClientInventory and global.ClientInventory.Items and global.ClientInventory.Items.Fruits or {}) do
            result[item.Name]=(result[item.Name] or 0)+(tonumber(item.Amount) or 1)
        end
        for _,folder in ipairs({player.Backpack,player.Character}) do
            if folder then
                for _,tool in ipairs(folder:GetChildren()) do
                    if tool:IsA("Tool") and Runtime.UpdateSupport.isPhysicalFruit(getrenv()._G.GameData,tool.Name) then
                        result[tool.Name]=(result[tool.Name] or 0)+1
                    end
                end
            end
        end
        return result
    end
    local ok,err=pcall(function()
        if not waitForFruitHandoff(cancelled) then return end
        if not stageFruitAtSpawn(cancelled) then return end
        collectionDeadline=os.clock()+35+Runtime.FruitPickupDelay*2
        local folder=workspace.World.Playability:FindFirstChild("DroppedTools")
        assert(folder,"Pasta de itens no chão indisponível.")
        local fruitData=getrenv()._G.GameData["AttackableItems Data"].Fruits
        local attempted={}
        Runtime.FruitsCollected=0
        while not cancelled() do
            local character=player.Character
            local root=character and character:FindFirstChild("HumanoidRootPart")
            local humanoid=character and character:FindFirstChildOfClass("Humanoid")
            assert(root and humanoid and humanoid.Health>0,"Personagem indisponível para coletar frutas.")
            local selected,part,distance
            for _,prompt in ipairs(folder:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") and prompt.Enabled and not attempted[prompt] then
                    local name=prompt.ObjectText:gsub("<[^>]+>",""):gsub(" Fruit$","")
                    local parent=prompt.Parent
                    local base=parent:IsA("BasePart") and parent or parent:FindFirstAncestorWhichIsA("BasePart")
                    if fruitData[name] and base then
                        local d=(root.Position-base.Position).Magnitude
                        if not distance or d<distance then selected,part,distance=prompt,base,d end
                    end
                end
            end
            if not selected then
                Runtime.FruitStatus=Runtime.FruitsCollected>0 and ("Coleta concluída: "..Runtime.FruitsCollected.." fruta(s)") or "Nenhuma devil fruit disponível para coletar."
                break
            end
            if Runtime.LastFruitCollectedAt then
                local readyAt=Runtime.LastFruitCollectedAt+Runtime.FruitBetweenPickupsDelay
                collectionDeadline+=math.max(0,readyAt-os.clock())
                while not cancelled() and os.clock()<readyAt do
                    Runtime.FruitStatus="Outra fruta encontrada: aguardando intervalo entre coletas..."
                    task.wait(.1)
                end
                if cancelled() then break end
                if not selected.Parent or not part.Parent or not selected.Enabled then continue end
            end
            attempted[selected]=true
            Runtime.FruitStatus="Confirmando a fruta antes de iniciar o movimento..."
            local settleDeadline=os.clock()+3
            local stableSince,lastPosition=os.clock(),part.Position
            repeat
                if cancelled() or not selected.Parent or not part.Parent then break end
                if (part.Position-lastPosition).Magnitude>1 then stableSince=os.clock() end
                lastPosition=part.Position
                task.wait(.1)
            until os.clock()-stableSince>=.4 or os.clock()>=settleDeadline
            if cancelled() then break end
            if not selected.Parent or not part.Parent or not selected.Enabled then continue end
            assert(os.clock()-stableSince>=.4,"A fruta ainda está em movimento; nova tentativa depois.")
            if Runtime.LastFruitTransferAt then
                local delayUntil=Runtime.LastFruitTransferAt+Runtime.FruitHandoffDelay
                while not cancelled() and os.clock()<delayUntil do
                    Runtime.FruitStatus="Aguardando intervalo seguro entre frutas..."
                    task.wait(.1)
                end
            end
            if cancelled() then break end
            distance=(root.Position-part.Position).Magnitude
            local before=inventorySnapshot()
            Runtime.FruitStatus="Indo por tween até "..selected.ObjectText
            currentRoot,wasAnchored=root,root.Anchored
            if distance>50 then
                Runtime.FruitStatus="Aproximando até 50 studs de "..selected.ObjectText
                local delta=root.Position-part.Position
                local horizontal=Vector3.new(delta.X,0,delta.Z)
                local direction=horizontal.Magnitude>0 and horizontal.Unit or Vector3.xAxis
                root.Anchored=true
                root.CFrame=CFrame.new(part.Position+direction*math.sqrt(50*50-8*8)+Vector3.new(0,8,0))*root.CFrame.Rotation
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
                task.spawn(function() pcall(function() player:RequestStreamAroundAsync(part.Position,5) end) end)
                local waitUntil=os.clock()+Runtime.FruitArrivalDelay
                Runtime.FruitStatus="Esperando estabilizar a aproximação da fruta..."
                while not cancelled() and os.clock()<waitUntil do task.wait(.1) end
                if cancelled() then break end
                assert(root.Parent and humanoid.Health>0 and selected.Parent,"Coleta interrompida durante a aproximação.")
                assert((root.Position-part.Position).Magnitude<=55,"A aproximação de 50 studs não se manteve; tween cancelado.")
            else
                local waitUntil=os.clock()+Runtime.FruitArrivalDelay
                Runtime.FruitStatus="Aguardando antes do tween final..."
                while not cancelled() and os.clock()<waitUntil do task.wait(.1) end
                if cancelled() then break end
            end
            local existingTools={}
            for _,tool in ipairs(player.Backpack:GetChildren()) do existingTools[tool]=true end
            for _,tool in ipairs(character:GetChildren()) do existingTools[tool]=true end
            local destination=part.Position+Vector3.new(3,0,0)
            local tweenDistance=(root.Position-destination).Magnitude
            local speed=Runtime.FruitTweenSpeed or 125
            local duration=math.max(.1,tweenDistance/speed)
            Runtime.LastFruitMove={Fruit=selected.ObjectText,InitialDistance=distance,ApproachDistance=(root.Position-part.Position).Magnitude,Distance=tweenDistance,Speed=speed,Duration=duration}
            Runtime.FruitStatus="Tween final até "..selected.ObjectText.." ("..math.floor(tweenDistance).." studs)"
            print("Frutas | Tween:",selected.ObjectText,"distância",tweenDistance,"velocidade",speed,"segundos",duration)
            currentTween=game:GetService("TweenService"):Create(root,
                TweenInfo.new(duration,Enum.EasingStyle.Linear),
                {CFrame=CFrame.new(destination)*root.CFrame.Rotation})
            local finished,state=false,nil
            local connection=currentTween.Completed:Connect(function(playbackState) finished=true state=playbackState end)
            root.Anchored=false
            currentTween:Play()
            Runtime.LastFruitTransferAt=os.clock()
            local deadline=os.clock()+duration+3
            while not finished and not cancelled() and selected.Parent and humanoid.Health>0 and root.Parent and os.clock()<deadline do task.wait(.1) end
            connection:Disconnect()
            cleanMovement()
            if cancelled() then break end
            assert(humanoid.Health>0 and root.Parent,"Personagem morreu durante a coleta.")
            task.wait(.2)
            local promptPosition=selected.Parent and (selected.Parent:IsA("Attachment") and selected.Parent.WorldPosition or part.Position)
            if state==Enum.PlaybackState.Completed and selected.Parent and selected.Enabled and promptPosition
                and (root.Position-promptPosition).Magnitude<=selected.MaxActivationDistance then
                Runtime.FruitStatus="Coletando "..selected.ObjectText
                currentRoot,wasAnchored=root,root.Anchored
                root.Anchored=true
                root.AssemblyLinearVelocity=Vector3.zero
                for attempt=1,2 do
                    if cancelled() or not selected.Parent then break end
                    Runtime.FruitStatus="Ao lado da fruta: aguardando antes de coletar..."
                    local readyAt=os.clock()+Runtime.FruitPickupDelay
                    while not cancelled() and selected.Parent and selected.Enabled and root.Parent and humanoid.Health>0 and os.clock()<readyAt do task.wait(.1) end
                    if cancelled() or not selected.Parent or not selected.Enabled then break end
                    assert(root.Parent and humanoid.Health>0,"Personagem indisponível antes de coletar a fruta.")
                    local point=selected.Parent:IsA("Attachment") and selected.Parent.WorldPosition or part.Position
                    if (root.Position-point).Magnitude>selected.MaxActivationDistance then break end
                    Runtime.FruitStatus="Coletando "..selected.ObjectText
                    if type(fireproximityprompt)=="function" then
                        local done,promptError=false,nil
                        local worker=task.defer(function()
                            local success,result=pcall(fireproximityprompt,selected)
                            if not success then promptError=result end
                            done=true
                        end)
                        local deadline=os.clock()+2
                        while not done and not cancelled() and os.clock()<deadline do task.wait(.05) end
                        if not done then pcall(task.cancel,worker) end
                        assert(done and not promptError,"Ativação do prompt não respondeu no prazo.")
                    else
                        selected:InputHoldBegin()
                        task.wait(selected.HoldDuration+.1)
                        if selected.Parent then selected:InputHoldEnd() end
                    end
                    local pickupDeadline=os.clock()+3
                    local newFruit
                    repeat
                        for _,tool in ipairs(player.Backpack:GetChildren()) do
                            if tool:IsA("Tool") and Runtime.UpdateSupport.isPhysicalFruit(getrenv()._G.GameData,tool.Name) and not existingTools[tool] then
                                newFruit=tool break
                            end
                        end
                        if newFruit or cancelled() or not character.Parent then break end
                        task.wait(.1)
                    until os.clock()>=pickupDeadline
                    local storedCount=0
                    if newFruit then
                        Runtime.LastFruitCollectedAt=os.clock()
                        local inventory=getrenv()._G.ClientInventory
                        local stored=inventory and inventory.Items and inventory.Items.Fruits
                        if type(stored)=="table" then
                            for _,entry in pairs(stored) do
                                if entry.Name==newFruit.Name then storedCount+=tonumber(entry.Amount) or 1 end
                            end
                        else
                            storedCount=math.huge
                        end
                    end
                    if newFruit and not cancelled() and storedCount<(Runtime.FruitStorageLimit or 1) then
                        Runtime.FruitStatus="Armazenando "..newFruit.Name
                        local remotes=game:GetService("ReplicatedStorage").Remotes
                        local storage=remotes:FindFirstChild("Physical Fruits Event",true)
                        assert(storage,"Evento de armazenamento de frutas indisponível.")
                        storage:FireServer("Storage",newFruit.Name)
                        local storageDeadline=os.clock()+15
                        while newFruit:IsDescendantOf(player.Backpack) and not cancelled() and os.clock()<storageDeadline do task.wait(.1) end
                        task.wait(1)
                    end
                    local gained=false
                    for name,count in pairs(inventorySnapshot()) do
                        if count>(before[name] or 0) then gained=true break end
                    end
                    if gained then
                        Runtime.LastFruitCollectedAt=os.clock()
                        Runtime.FruitsCollected+=1
                        print("Frutas | Coleta confirmada:",selected.ObjectText)
                        break
                    end
                    if attempt==2 and not cancelled() then
                        recordRecovery("Fruta sem confirmação de coleta: "..selected.ObjectText,"Liberando movimento e retomando o farm; nova tentativa após o intervalo")
                    end
                end
                cleanMovement()
            end
        end
    end)
    cleanMovement()
    if Runtime.CancelFruitStaging then pcall(Runtime.CancelFruitStaging) Runtime.CancelFruitStaging=nil end
    Runtime.CancelFruitMovement=nil
    if not ok then
        Runtime.FruitStatus="Coleta interrompida: "..tostring(err)
        recordRecovery(tostring(err),"Coleta encerrada e movimento liberado")
    elseif os.clock()>=collectionDeadline then
        Runtime.FruitStatus="Tempo máximo da coleta atingido; retomando o farm."
        recordRecovery("Coleta excedeu o tempo máximo","Coleta encerrada e movimento liberado")
    elseif cancelled() then Runtime.FruitStatus="Coleta parada." end
    Runtime.FruitCollecting=false
    if ownsPriority then
        Runtime.PriorityBusy=false
        if resume and Runtime.Alive and not Runtime.FruitCancel and not automaticRollDue() then Runtime.SelectFarmMode(Runtime.FarmMode) end
    end
end
Runtime.CollectDevilFruits=collectDevilFruits

local fruitRetries=setmetatable({}, {__mode="k"})
local chestRetries=setmetatable({}, {__mode="k"})
local priorityStorageTried=setmetatable({}, {__mode="k"})
local function storePriorityBackpackFruits(manual)
    local global=getrenv()._G
    local fruits=global and global.ClientInventory and global.ClientInventory.Items and global.ClientInventory.Items.Fruits
    if type(fruits)~="table" then return end
    for _,tool in ipairs(player.Backpack:GetChildren()) do
        if not Runtime.Alive or not manual and not Scheduler.Enabled then break end
        if tool:IsA("Tool") and Runtime.UpdateSupport.isPhysicalFruit(getrenv()._G.GameData,tool.Name) and not priorityStorageTried[tool] then
            priorityStorageTried[tool]=true
            local count=0
            for _,entry in pairs(fruits) do if entry.Name==tool.Name then count+=tonumber(entry.Amount) or 1 end end
            if count<(Runtime.FruitStorageLimit or 1) then
                game.ReplicatedStorage.Remotes["Physical Fruits Event"]:FireServer("Storage",tool.Name)
                local deadline=os.clock()+2
                while tool.Parent==player.Backpack and os.clock()<deadline and Runtime.Alive do task.wait(.1) end
            end
        end
    end
end
local function priorityFruitPrompts()
    local result={}
    local global=getrenv()._G
    local data=global and global.GameData and global.GameData["AttackableItems Data"].Fruits
    local folder=workspace.World.Playability:FindFirstChild("DroppedTools")
    if not folder or not data then return result end
    for _,prompt in ipairs(folder:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled
            and os.clock()>=(fruitRetries[prompt] or 0)
            and data[prompt.ObjectText:gsub("<[^>]+>",""):gsub(" Fruit$","")] then
            table.insert(result,prompt)
        end
    end
    return result
end
local function availablePriorityChests()
    local result={}
    local time=game.ReplicatedStorage:FindFirstChild("ServerInfo")
    time=time and time:FindFirstChild("ServerTime")
    if time and time.Value<1200 then return result end
    local folder=workspace.World.Playability:FindFirstChild("Chests")
    if not folder then return result end
    for _,chest in ipairs(folder:GetChildren()) do
        local hit=chest:FindFirstChild("Hitbox") or chest:IsA("Model") and chest.PrimaryPart
        if hit and os.clock()>=(chestRetries[chest] or 0) then
            local visible=false
            for _,part in ipairs(chest:GetDescendants()) do
                if part:IsA("MeshPart") and part.Transparency<.95 then visible=true break end
            end
            if visible then table.insert(result,{Model=chest,Hit=hit}) end
        end
    end
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then table.sort(result,function(a,b) return (a.Hit.Position-root.Position).Magnitude<(b.Hit.Position-root.Position).Magnitude end) end
    return result
end
local function automationCancelled()
    return not Runtime.Alive or not Scheduler.Enabled or automaticRollDue()
end
local function finishingBoss()
    local target=Runtime.CombatTarget
    if not Runtime.Pending or not target or not target.Parent then return false end
    local humanoid=target:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return false end
    local global=getrenv()._G
    local data=global.GameData["Enemys Data"][target:GetAttribute("RealName") or target.Name]
    return Runtime.FarmMode=="Bosses" or data and data.Boss or false
end
local function pauseForPriority()
    Runtime.DesiredEnabled=false
    stopFarm()
    local deadline=os.clock()+20
    while (Runtime.Pending or control.AutoLevelRunning) and not automationCancelled() and os.clock()<deadline do task.wait(.1) end
    assert(not Runtime.Pending and not control.AutoLevelRunning,"O farm principal ainda está parando.")
end
local function collectPriorityChest(target)
    local chest,hit=target.Model,target.Hit
    if not hit.Parent or not chest.Parent then return end
    chestRetries[chest]=os.clock()+60
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    assert(root and humanoid and humanoid.Health>0,"Personagem indisponível.")
    local origin,anchored=root.CFrame,root.Anchored
    local ok,err=pcall(function()
        root.Anchored=true
        root.CFrame=hit.CFrame*CFrame.new(0,4,0)
        task.spawn(function() pcall(function() player:RequestStreamAroundAsync(hit.Position,8) end) end)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={character,workspace.World.IgnoreList,workspace.World.Playability.Characters,workspace.World.Playability.Enemys,chest}
        local deadline=os.clock()+10
        local floor
        repeat
            assert(humanoid.Health>0 and root.Parent,"Personagem indisponível durante a chegada.")
            floor=workspace:Raycast(hit.Position+Vector3.new(0,6,0),Vector3.new(0,-45,0),params)
            if floor and floor.Material~=Enum.Material.Water and
                (floor.Instance:IsA("Terrain") or floor.Instance:IsA("BasePart") and floor.Instance.CanCollide) then break end
            floor=nil
            task.wait(.2)
        until automationCancelled() or os.clock()>=deadline
        if automationCancelled() then return end
        assert(floor,"Piso do baú não carregou.")
        root.Anchored=false
        root.CFrame=hit.CFrame*CFrame.new(0,3,0)
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        local visible={}
        for _,part in ipairs(chest:GetDescendants()) do
            if part:IsA("MeshPart") and part.Transparency<.95 then visible[part]=true end
        end
        task.wait(.3)
        if automationCancelled() or not hit.Parent then return end
        if type(firetouchinterest)=="function" then
            firetouchinterest(root,hit,0)
            task.wait(.1)
            if root.Parent and hit.Parent then firetouchinterest(root,hit,1) end
        end
        local collected=false
        deadline=os.clock()+2
        repeat
            if not chest.Parent or not hit.Parent then collected=true end
            for part in pairs(visible) do if not part.Parent or part.Transparency>=.95 then collected=true end end
            if collected then break end
            task.wait(.1)
        until automationCancelled() or os.clock()>=deadline
        if collected then
            Scheduler.ChestsCollected=(Scheduler.ChestsCollected or 0)+1
            chestRetries[chest]=os.clock()+1200
        end
    end)
    if root.Parent then
        if not ok or root.Anchored then root.CFrame=origin end
        root.Anchored=anchored
        root.AssemblyLinearVelocity=Vector3.zero
    end
    if not ok then error(err) end
end
local function runAutomation()
    while Runtime.Alive do
        if automaticRollDue() and not Runtime.PriorityBusy and not Runtime.FruitCollecting then
            local main=control.AnimePieceRuntime
            if main and main.Alive and (not main.FarmDone or main.ControllerThread) then
                Runtime.FruitRollStatus="Descarregue o Main do rejoin para usar o roll automático."
            else
                Runtime.DeferredBosses.Roll=nil
                local ok,err=pcall(Runtime.RollFruit,true)
                if not ok then Runtime.FruitRollStatus="Roll automático: "..tostring(err) end
            end
        end
        if Scheduler.Enabled and Runtime.Ready and not Runtime.FruitCollecting and not Runtime.FruitRollBusy then
            local main=control.AnimePieceRuntime
            if main and main.Alive and (not main.FarmDone or main.ControllerThread) then
                Scheduler.LastError="Descarregue o Main do rejoin antes de usar a automação combinada."
                task.wait(1)
                continue
            end
            local fruits=Scheduler.Fruits and priorityFruitPrompts() or {}
            if #fruits==0 then Runtime.DeferredBosses.Fruit=nil
            elseif not priorityCanRun("Fruit") then fruits={} end
            local chests={}
            if #fruits==0 and Scheduler.Chests and not finishingBoss() and not (Scheduler.Bosses and (readyWorldBoss() or announcedWorldBoss() or Runtime.WorldBossScout)) and os.clock()>=Scheduler.NextChestCheck then
                chests=availablePriorityChests()
                Scheduler.NextChestCheck=os.clock()+Scheduler.ChestInterval
            end
            if #fruits>0 or #chests>0 then
                Runtime.PriorityBusy=true
                Scheduler.Current=#fruits>0 and "Coletando frutas" or "Coletando baús"
                local ok,err=pcall(function()
                    pauseForPriority()
                    if automationCancelled() then return end
                    if #fruits>0 then
                        Runtime.DeferredBosses.Fruit=nil
                        for _,prompt in ipairs(fruits) do fruitRetries[prompt]=os.clock()+60 end
                        collectDevilFruits(true)
                    else
                        -- Small batches let newly spawned fruits interrupt between chests.
                        for index=1,math.min(3,#chests) do
                            if automationCancelled() or Scheduler.Fruits and #priorityFruitPrompts()>0 and priorityCanRun("Fruit") or Scheduler.Bosses and (readyWorldBoss() or announcedWorldBoss() or Runtime.WorldBossScout) then break end
                            collectPriorityChest(chests[index])
                        end
                        if #chests>3 then Scheduler.NextChestCheck=os.clock()+2 end
                    end
                    storePriorityBackpackFruits()
                end)
                Scheduler.LastError=not ok and tostring(err) or nil
                Runtime.PriorityBusy=false
                Scheduler.Current=nil
            end
            if Scheduler.Enabled and Scheduler.Bosses and not Runtime.Pending and not Runtime.PriorityBusy and not Runtime.FruitCollecting and not automaticRollDue() and (readyWorldBoss() or announcedWorldBoss()) then
                if not Scheduler.BackgroundPaused and Scheduler.FinishedBackground~=Scheduler.Background then
                    Runtime.SelectFarmMode(Scheduler.Background)
                elseif not Scheduler.BackgroundPaused then
                    -- Só vigia bosses quando o farm de fundo terminou; pausa/troca manual do usuário é respeitada.
                    Runtime.WatchBossesOnly=true
                    Runtime.FarmMode="Bosses"
                    startFarm()
                end
            end
            if Scheduler.Enabled and not Runtime.PriorityBusy and not Runtime.Pending and not Runtime.FruitCollecting
                and not automaticRollDue()
                and not Runtime.LastError and not Scheduler.BackgroundPaused and Scheduler.FinishedBackground~=Scheduler.Background then
                Runtime.SelectFarmMode(Scheduler.Background)
            end
        end
        task.wait(1)
    end
end

local function fruitShopCall(callback)
    local setIdentity=setthreadidentity or setidentity
    local getIdentity=getthreadidentity or getidentity
    local before=getIdentity and getIdentity()
    if setIdentity then setIdentity(2) end
    local results=table.pack(pcall(callback))
    if before and setIdentity then setIdentity(before) end
    if not results[1] then error(results[2]) end
    return table.unpack(results,2,results.n)
end
local fruitRollNpcPoints,fruitRollNpcNextCheck={},0
local function fruitRollNpcDistance()
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    if os.clock()>=fruitRollNpcNextCheck then
        fruitRollNpcNextCheck=os.clock()+10
        fruitRollNpcPoints={Vector3.new(250.278656,9.918270,-1204.934570)}
        for _,folder in ipairs({workspace.World.IgnoreList.Npcs.Interactive,game:GetService("ReplicatedStorage")}) do
            for _,model in ipairs(folder:GetDescendants()) do
                if model:IsA("Model") and model.Name=="Luzefe" then
                    local part=model:FindFirstChild("HumanoidRootPart")
                    table.insert(fruitRollNpcPoints,part and part.Position or model:GetPivot().Position)
                end
            end
        end
    end
    local distance=math.huge
    for _,point in ipairs(fruitRollNpcPoints) do distance=math.min(distance,(root.Position-point).Magnitude) end
    return distance
end
local function fruitRollState()
    return fruitShopCall(function()
        local g=getrenv()._G
        local info=g.GetModule("GetInfos")
        local stats=info.GetStats()
        local level=info.GetLevel()
        local values=stats and stats:FindFirstChild("Infos")
        local money=values and values:FindFirstChild("Money")
        local cooldown=values and values:FindFirstChild("LastFruitTimeSpin")
        local price=g.GetModule("GetFruitGachaPrice").GetPrice(level,player:GetAttribute("FirstFruitSpin") and true or false)
        local wait=math.max(cooldown and cooldown.Value or 0,math.max(0,60-(os.clock()-(Runtime.LastFruitRollAttempt or -math.huge))),math.max(0,(Runtime.FruitRollRetryAt or 0)-os.clock()))
        local distance=fruitRollNpcDistance()
        local near=distance and distance<=12
        local reason=level<50 and "Exige nível 50"
            or wait>0 and ("Aguarde "..math.ceil(wait).." s")
            or (not money or money.Value<price) and "Saldo insuficiente"
            or not distance and "Aguarde o personagem carregar"
            or not near and "Aproxime-se do Luzefe; giro à distância não confirmado"
            or "Disponível perto do Luzefe"
        return {Available=level>=50 and wait<=0 and money and money.Value>=price and near,
            ReadyForRoll=level>=50 and wait<=0 and money and money.Value>=price or false,
            Price=price,Money=money and money.Value or 0,Cooldown=wait,ServerCooldown=cooldown and cooldown.Value or 0,Reason=reason,Values=values,NpcDistance=distance}
    end)
end
local function fruitStockText()
    local stock=game:GetService("ReplicatedStorage").Shared:FindFirstChild("Fruit Stock")
    if not stock then return "Estoque ainda não carregou." end
    local data=getrenv()._G.GameData["Fruits Data"]
    local names={}
    for _,entry in ipairs(stock:GetChildren()) do if data[entry.Name] then table.insert(names,entry.Name) end end
    table.sort(names,function(a,b) return (data[a].Index or 0)<(data[b].Index or 0) end)
    local lines={'<b>📋 Disponíveis agora</b>'}
    for _,name in ipairs(names) do table.insert(lines,'<font color="#8DDEA1">● '..name..'</font> • $'..tostring(data[name].Price or "—")) end
    if #names==0 then table.insert(lines,"Nenhuma fruta disponível.") end
    local remaining=math.max(0,math.floor(stock:GetAttribute("StockUpdateTime") or 0))
    table.insert(lines,string.format("\n⏱ Renova em %02d:%02d",math.floor(remaining/60),remaining%60))
    return table.concat(lines,"\n")
end
Runtime.GetFruitRollState=fruitRollState
Runtime.GetFruitStockText=fruitStockText
local function openFruitStock()
    Runtime.ShowFruitStock=true
    Runtime.FruitStockError=nil
    local frames=player.PlayerGui:FindFirstChild("Interfaces")
    frames=frames and frames:FindFirstChild("Frames")
    local shop=frames and frames:FindFirstChild("Fruit Shop")
    assert(shop,"A loja de frutas ainda não carregou.")
    if not shop.Visible then
        fruitShopCall(function()
            local g=getrenv()._G
            assert(type(g.OpenInterface)=="function","A abertura da loja ainda não está disponível.")
            g.OpenInterface("Fruit Shop")
        end)
    end
    local deadline=os.clock()+3
    while Runtime.Alive and not shop.Visible and os.clock()<deadline do task.wait(.05) end
    assert(shop.Visible,"O jogo não abriu a loja de frutas.")
    if Runtime.Alive then Runtime.Library:Toggle(false) end
end
Runtime.OpenFruitStock=openFruitStock
local function moveToRollNpc(cancelled)
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local human=c and c:FindFirstChildOfClass("Humanoid")
    assert(root and human and human.Health>0,"Personagem indisponível para o roll.")
    fruitRollNpcDistance()
    local point,distance
    for _,position in ipairs(fruitRollNpcPoints) do
        local d=(position-root.Position).Magnitude
        if not distance or d<distance then point,distance=position,d end
    end
    assert(point,"Luzefe não encontrado.")
    if distance<=8 then return end
    local origin,anchored=root.CFrame,root.Anchored
    local arrived=false
    local function cleanup()
        if root.Parent then
            if not arrived then root.CFrame=origin end
            root.Anchored=anchored
            root.AssemblyLinearVelocity=Vector3.zero
        end
    end
    Runtime.CancelFruitRollTravel=cleanup
    local ok,err=pcall(function()
        Runtime.FruitRollStatus="Indo ao Luzefe; aguardando o chão carregar..."
        root.Anchored=true
        root.CFrame=CFrame.new(point+Vector3.new(0,4,4))
        root.AssemblyLinearVelocity=Vector3.zero
        task.spawn(function() pcall(function() player:RequestStreamAroundAsync(point,6) end) end)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={c,workspace.World.IgnoreList,workspace.World.Playability.Enemys}
        local floor
        local deadline=os.clock()+8
        repeat
            if cancelled() then return end
            floor=workspace:Raycast(root.Position+Vector3.new(0,5,0),Vector3.new(0,-35,0),params)
            if floor and floor.Material~=Enum.Material.Water and (floor.Instance:IsA("Terrain") or floor.Instance.CanCollide) then break end
            floor=nil task.wait(.2)
        until os.clock()>=deadline
        assert(floor,"O chão perto do Luzefe não carregou.")
        if cancelled() then return end
        local height=human.HipHeight+root.Size.Y/2+(human.RigType==Enum.HumanoidRigType.R6 and 2 or 0)
        root.CFrame=CFrame.lookAt(floor.Position+Vector3.new(0,height,0),point)
        arrived=true
    end)
    cleanup()
    Runtime.CancelFruitRollTravel=nil
    if not ok then error(err) end
    task.wait(.6)
end
local function rollFruit(automatic)
    if Runtime.FruitRollBusy then return end
    if Runtime.PriorityBusy or Runtime.FruitCollecting then Runtime.FruitRollStatus="Aguarde a coleta atual terminar." return end
    local state=fruitRollState()
    if not (automatic and state.ReadyForRoll or not automatic and state.Available) then Runtime.FruitRollStatus=state.Reason return end
    Runtime.FruitRollBusy=true
    Runtime.ActiveFruitRollAuto=automatic and true or false
    Runtime.FruitRollCancelled=false
    Runtime.PriorityBusy=true
    Runtime.FruitRollHold=false
    local combined=Scheduler.Enabled
    local resume=(Runtime.Pending or Runtime.DesiredEnabled) and not Runtime.WatchBossesOnly or combined and not Scheduler.BackgroundPaused
    local resumeMode=Runtime.UX and Runtime.UX.SelectedMode() or Runtime.FarmMode
    Runtime.FruitRollResumePlan={Enabled=resume,Mode=resumeMode}
    local connection,received,sent,unconfirmed
    local function cancelled()
        return not Runtime.Alive or Runtime.FruitRollCancelled or combined and not Scheduler.Enabled
    end
    local function snapshot()
        local result={}
        local g=getrenv()._G
        for _,entry in pairs(g.ClientInventory.Items.Fruits or {}) do result[entry.Name]=(result[entry.Name] or 0)+(tonumber(entry.Amount) or 1) end
        for _,folder in ipairs({player.Backpack,player.Character}) do
            for _,tool in ipairs(folder:GetChildren()) do
                local data=g.GameData["Items Data"][tool.Name]
                if tool:IsA("Tool") and data and data.Category=="Fruits" then result[tool.Name]=(result[tool.Name] or 0)+1 end
            end
        end
        return result
    end
    local beforeFruits
    local function detectReceipt()
        if received then return true end
        local after=fruitRollState()
        if Runtime.LastFruitRollRequest then
            Runtime.LastFruitRollRequest.MoneyAfter=after.Money
            Runtime.LastFruitRollRequest.CooldownAfter=after.ServerCooldown
            if sent and (after.Money<state.Money or after.ServerCooldown>state.ServerCooldown) then
                Runtime.LastFruitRollRequest.Acknowledged=true
            end
        end
        if sent and beforeFruits and (after.Money<state.Money or after.ServerCooldown>state.ServerCooldown) then
            for name,count in pairs(snapshot()) do
                if count>(beforeFruits[name] or 0) then received=name return true end
            end
        end
        return false
    end
    local function unacknowledgedExpired()
        local request=Runtime.LastFruitRollRequest
        if not sent or not request or request.Acknowledged or os.clock()-request.At<45 then return false end
        local ok,current=pcall(fruitRollState)
        return ok and current.Money>=request.MoneyBefore and current.ServerCooldown<=request.CooldownBefore
    end
    local function cleanup()
        if connection then connection:Disconnect() connection=nil end
        if Runtime.CancelFruitRollTravel then pcall(Runtime.CancelFruitRollTravel) end
    end
    Runtime.CancelFruitRoll=function() Runtime.FruitRollCancelled=true cleanup() end
    Scheduler.Current="🎲 Roll prioritário"
    local ok,err=pcall(function()
        Runtime.FruitRollStatus="Pausando todos os farms para o roll..."
        Runtime.DesiredEnabled=false
        stopFarm()
        local deadline=os.clock()+20
        while Runtime.Pending and not cancelled() and os.clock()<deadline do task.wait(.1) end
        assert(not Runtime.Pending,"O farm anterior não terminou no prazo.")
        if cancelled() then return end
        if automatic then moveToRollNpc(cancelled) end
        if cancelled() then return end
        state=fruitRollState()
        assert(state.Available,state.Reason)
        beforeFruits=snapshot()
        connection=game.ReplicatedStorage.Remotes["Fruit Gacha"].OnClientEvent:Connect(function(name) if name then received=name end end)
        Runtime.LastFruitRollAttempt=os.clock()
        Runtime.FruitRollStatus="Girando por $"..state.Price.." perto do Luzefe..."
        Runtime.LastFruitRollRequest={MoneyBefore=state.Money,CooldownBefore=state.ServerCooldown,Distance=state.NpcDistance,At=os.clock()}
        sent=true
        game.ReplicatedStorage.Remotes["Dialogue Event"]:FireServer({"SpinFruit",""})
        deadline=os.clock()+12
        while not cancelled() do
            local detected,result=pcall(detectReceipt)
            if detected and result then break end
            if detected and unacknowledgedExpired() then unconfirmed=true return end
            if os.clock()>=deadline then
                Runtime.FruitRollHold=true
                Runtime.FruitRollStatus="Aguardando a fruta; farms pausados. Nenhum novo giro será enviado."
            end
            task.wait(.2)
        end
        if cancelled() then return end
        Runtime.FruitRollHold=false
        Runtime.FruitRollStatus="✓ Fruta recebida: "..tostring(received)
        Runtime.LastFruitRollRequest.Received=received
        deadline=os.clock()+7
        while not cancelled() and os.clock()<deadline do task.wait(.2) end
        if not cancelled() then storePriorityBackpackFruits(true) end
    end)
    if not ok and not cancelled() then
        recordRecovery(tostring(err),"Reavaliando o aceite do roll antes de liberar ou manter a prioridade")
        if not sent or unacknowledgedExpired() then
            unconfirmed=true
        else
        Runtime.FruitRollHold=true
        Runtime.FruitRollStatus="Roll bloqueado: "..tostring(err)..". Farms pausados; cancele a prioridade para liberar."
        while not cancelled() do
            if sent then local success,result=pcall(detectReceipt) if success and result then ok=true break end end
            if unacknowledgedExpired() then unconfirmed=true break end
            task.wait(.25)
        end
        if received and not cancelled() then
            Runtime.FruitRollStatus="✓ Fruta recebida: "..tostring(received)
            pcall(storePriorityBackpackFruits,true)
        end
        end
    end
    if unconfirmed and not cancelled() then
        Runtime.FruitRollRetryAt=os.clock()+300
        if Runtime.LastFruitRollRequest then Runtime.LastFruitRollRequest.Unconfirmed=true end
        Runtime.FruitRollStatus="Roll sem confirmação de aceite: sem débito ou cooldown. Farm retomado; próxima tentativa em 5 minutos."
        recordRecovery("Roll não confirmou aceite em 45 segundos","Liberando prioridade e adiando nova tentativa por 5 minutos")
    end
    cleanup()
    Runtime.CancelFruitRoll=nil
    Runtime.FruitRollBusy=false
    Runtime.ActiveFruitRollAuto=false
    Runtime.FruitRollHold=false
    Runtime.PriorityBusy=false
    Scheduler.Current=nil
    if cancelled() then Runtime.FruitRollStatus="Prioridade de roll cancelada; farms pausados."
    elseif resume and (received or unconfirmed) then Runtime.SelectFarmMode(resumeMode) end
end
Runtime.RollFruit=rollFruit

-- Explicit, single-use chest action. It never purchases a chest or a Robux slot.
Runtime.FruitChestSelection="Common Fruit Chest"
local function openSelectedFruitChest()
    if Runtime.FruitChestBusy or Runtime.PriorityBusy or Runtime.FruitCollecting or Runtime.FruitRollBusy then
        Runtime.FruitChestStatus="Aguarde a tarefa prioritária terminar." return
    end
    if Runtime.FruitChestPending then
        Runtime.FruitChestStatus="Abertura anterior sem confirmação. Confira o inventário; nenhum comando será repetido." return
    end
    local name=Runtime.FruitChestSelection
    assert(Runtime.UpdateSupport.isFruitChest(name),"Baú inválido.")
    local g=getrenv()._G
    local before=itemCount(g,name)
    if before<=0 then Runtime.FruitChestStatus="Você não possui "..name.."." return end
    local resume=Runtime.Pending and not Runtime.WatchBossesOnly
    local mode=Runtime.FarmMode
    local combined=Scheduler.Enabled
    Runtime.FruitChestBusy=true Runtime.PriorityBusy=true Scheduler.Enabled=false
    local ok,err=pcall(function()
        stopFarm()
        local deadline=os.clock()+15
        while Runtime.Pending and Runtime.Alive and os.clock()<deadline do task.wait(.1) end
        assert(Runtime.Alive and not Runtime.Pending,"Farm não parou; baú não foi consumido.")
        resetCombat()
        local char=player.Character
        local humanoid=char and char:FindFirstChildOfClass("Humanoid")
        assert(humanoid and humanoid.Health>0,"Personagem indisponível.")
        local tool=char:FindFirstChild(name) or player.Backpack:FindFirstChild(name)
        if not tool then
            game.ReplicatedStorage.Remotes["Inventory Event"]:FireServer("Equip",name)
            deadline=os.clock()+8
            repeat
                tool=char:FindFirstChild(name) or player.Backpack:FindFirstChild(name)
                if tool then break end
                task.wait(.1)
            until not Runtime.Alive or os.clock()>=deadline
        end
        assert(tool and tool:IsA("Tool"),"Baú não equipado; abertura cancelada.")
        if tool.Parent~=char then humanoid:EquipTool(tool) task.wait(.5) end
        assert(Runtime.Alive and tool.Parent==char,"Baú não está no personagem.")
        local existing={}
        for _,folder in ipairs({player.Backpack,char}) do
            for _,value in ipairs(folder:GetChildren()) do existing[value]=true end
        end
        Runtime.FruitChestPending={Name=name,Count=before,At=os.clock()}
        Runtime.FruitChestStatus="Aguardando o resultado de "..name.."..."
        game.ReplicatedStorage.Remotes["Items Event"]:FireServer(name,"Use")
        deadline=os.clock()+20
        local received
        repeat
            for _,folder in ipairs({player.Backpack,char}) do
                for _,value in ipairs(folder:GetChildren()) do
                    if value:IsA("Tool") and not existing[value]
                        and Runtime.UpdateSupport.isPhysicalFruit(g.GameData,value.Name) then received=value.Name break end
                end
            end
            if received then break end
            task.wait(.2)
        until not Runtime.Alive or os.clock()>=deadline
        assert(received,"Sem confirmação de fruta recebida; verifique o inventário antes de outra abertura.")
        Runtime.FruitChestPending=nil
        Runtime.FruitChestStatus="Fruta recebida: "..received..". Tentando guardar se houver espaço."
        pcall(storePriorityBackpackFruits,true)
    end)
    Runtime.PriorityBusy=false Runtime.FruitChestBusy=false Scheduler.Enabled=combined
    if not ok then Runtime.FruitChestStatus=tostring(err) end
    if Runtime.Alive and resume and not Runtime.Pending then Runtime.SelectFarmMode(mode) end
end
Runtime.OpenSelectedFruitChest=openSelectedFruitChest

local function nextHakiRequirements(version)
    if version==0 then
        return '<b><font color="#80C7FF">Próximo: Haki V1 • Nível 200+</font></b>\n⚔ Causar 100.000 de dano\n🍨 Entregar 5 Banana Splits\n👹 Derrotar 25 bosses\n💰 Aprender por $50.000'
    elseif version==1 or version==2 then
        return '<b><font color="#80C7FF">Próximo: Haki V'..(version+1)..'</font></b>\n💎 1 Armament Crystal\n🔮 1 Magic Ball\n💰 $'..(version==1 and "35.000" or "50.000")
    end
    return ""
end
Runtime.GetNextHakiRequirements=nextHakiRequirements
local function createInterface()
    local Repository="https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    Library=loadstring(game:HttpGet(Repository.."Library.lua"))()
    SaveManager=loadstring(game:HttpGet(Repository.."addons/SaveManager.lua"))()
    Runtime.Library=Library
    local Window=Library:CreateWindow({
        Title="Anime Piece | Funções",
        Footer="Farm • Interrupções • Combate • Tremor",
        Icon=0,
        AutoShow=true,
        Center=true,
    })
    Runtime.Window=Window
    local toggleButton=Library:AddDraggableButton("Menu",function() Library:Toggle() end,true,true)
    local lockButton=Library:AddDraggableButton("Lock",function(self)
        Library.CantDragForced=not Library.CantDragForced
        self:SetText(Library.CantDragForced and "Unlock" or "Lock")
    end,true,true)
    toggleButton.Button.Position=UDim2.fromOffset(6,6)
    lockButton.Button.Position=UDim2.fromOffset(toggleButton.Button.Size.X.Offset+12,6)

    local farmTab=Window:AddTab("Farm","play")
    local automationTab=Window:AddTab("Interrupções","layers")
    local combatTab=Window:AddTab("Combate","swords")
    local fruitTab=Window:AddTab("Frutas","apple")
    local configTab=Window:AddTab("Configurações","settings")
    local UX={Groups={},Editors={},Advanced=false,Loading=true}
    Runtime.UX=UX
    local function goalBox(side,name,mode,advanced)
        local box=farmTab:AddGroupbox({Side=side,Name=name})
        table.insert(UX.Groups,{Box=box,Mode=mode,Advanced=advanced,Name=name})
        box:SetVisible(false)
        return box
    end
    UX.Box=goalBox
    UX.ModeLabels={Auto="Auto Level",Money="Dinheiro",Mastery="Mastery",Items="Itens",Haki="Haki",Bosses="Bosses",Unlocks="Desbloqueios",Rerolls="Raça e cor"}
    UX.SelectedMode=function()
        local option=Library.Options.FarmExecutionMode
        for key,label in pairs(UX.ModeLabels) do if option and option.Value==label then return key end end
        return Runtime.FarmMode
    end
    UX.Refresh=function()
        local mode=UX.SelectedMode()
        local key=mode.."|"..Runtime.ItemMethod.."|"..tostring(UX.Advanced).."|"..CONFIG.CombatMode
            .."|"..Runtime.Reroll.Kind.."|"..tostring(Runtime.Reroll.UseBananas)
            .."|"..tostring(Runtime.MoneyGoal.Enabled).."|"..tostring(Runtime.MasteryGoal.Enabled)
            .."|"..tostring(Runtime.PriorityBusy or Runtime.FruitCollecting or Runtime.FruitRollBusy)
        if UX.VisibilityKey==key then return end
        UX.VisibilityKey=key
        for _,entry in ipairs(UX.Groups) do
            local show=entry.Mode==mode or entry.Mode=="Always"
                or entry.Mode=="ItemsDrop" and mode=="Items" and Runtime.ItemMethod=="Drop"
                or entry.Mode=="ItemsPurchase" and mode=="Items" and Runtime.ItemMethod=="Purchase"
                or entry.Mode=="Utility" and (mode=="Money" or mode=="Mastery")
            entry.Box:SetVisible(show and (not entry.Advanced or UX.Advanced))
        end
        UX.AutomaticBox:SetVisible(CONFIG.CombatMode=="Auto")
        local priorityBusy=Runtime.PriorityBusy or Runtime.FruitCollecting or Runtime.FruitRollBusy or false
        Library.Options.FarmExecutionMode:SetDisabled(priorityBusy)
        farmToggle:SetDisabled(priorityBusy)
        if UX.QuestLabel then UX.QuestLabel:SetVisible(mode=="Auto" or mode=="Money" or mode=="Mastery" or mode=="Haki") end
        for _,entry in ipairs({{"RerollDesiredRaces",Runtime.Reroll.Kind=="Race"},{"RerollDesiredColors",Runtime.Reroll.Kind=="Color"},{"RerollBananaLimit",Runtime.Reroll.UseBananas}}) do
            local option=Library.Options[entry[1]]
            if option then option:SetVisible(entry[2]) end
        end
        if Library.Toggles.RerollFarmBananas then Library.Toggles.RerollFarmBananas:SetVisible(Runtime.Reroll.UseBananas) end
        for _,entry in ipairs({{"MoneyGoalBasis",Runtime.MoneyGoal.Enabled},{"MoneyGoalAmount",Runtime.MoneyGoal.Enabled},{"MasteryGoalAmount",Runtime.MasteryGoal.Enabled},{"ItemDefaultAmount",UX.Advanced},{"WorldBossExtraName",UX.Advanced}}) do
            local option=Library.Options[entry[1]]
            if option then option:SetVisible(entry[2]) end
        end
        for _,id in ipairs({"SummonPriorityOrder","ItemPriorityOrder","ItemQuantityOverrides"}) do
            if Library.Options[id] then Library.Options[id]:SetVisible(false) end
        end
    end
    UX.AddPriorityEditor=function(box,id,selection,order,rawId)
        local editor={Selection=selection,Order=order,RawId=rawId}
        editor.Focus=box:AddDropdown(id.."Focus",{
            Values={},Text="Selecionar alvo da fila",Searchable=true,
            Callback=function() if UX.GoalTarget==editor.Focus then UX.SyncGoalEditor() end end,
        })
        local function move(delta)
            local names=moveSelectedPriority(selection(),order(),editor.Focus.Value,delta)
            Library.Options[rawId]:SetValue(table.concat(names,"; "))
            editor.Signature=nil
        end
        box:AddButton({Text="↑ Subir na prioridade",Func=function() move(-1) end})
        box:AddButton({Text="↓ Descer na prioridade",Func=function() move(1) end})
        editor.Label=box:AddLabel("Selecione os alvos primeiro.",true)
        table.insert(UX.Editors,editor)
    end
    UX.RefreshEditors=function()
        for _,editor in ipairs(UX.Editors) do
            local names=orderedSelection(editor.Selection(),editor.Order())
            local signature=table.concat(names,";")
            if editor.Signature~=signature then
                editor.Signature=signature
                editor.Focus:SetValues(names)
                if not table.find(names,editor.Focus.Value) then editor.Focus:SetValue(names[1]) end
                local rows={"<b>Ordem entre alvos disponíveis</b>"}
                for index,name in ipairs(names) do table.insert(rows,index..". "..name) end
                if #names==0 then table.insert(rows,"Nenhum alvo selecionado.") end
                setStatusText(editor.Label,table.concat(rows,"\n"))
            end
        end
    end
    UX.RefreshExtras=function()
        local enabled=Scheduler.Enabled
        local preset=UX.CustomExtras and UX.Advanced and "Personalizado"
            or not enabled and "Desligados"
            or Scheduler.Fruits and Scheduler.Chests and Scheduler.Bosses and "Frutas, baús e bosses"
            or Scheduler.Fruits and Scheduler.Chests and not Scheduler.Bosses and "Frutas e baús"
            or Scheduler.Fruits and not Scheduler.Chests and not Scheduler.Bosses and "Só frutas"
            or "Personalizado"
        if UX.ExtrasPreset.Value~=preset then
            UX.UpdatingPreset=true
            UX.ExtrasPreset:SetValue(preset)
            UX.UpdatingPreset=false
        end
        for _,id in ipairs({"CombinedAutomationEnabled","CombinedFruitCollect","CombinedWorldBosses","CombinedChestCollect"}) do
            Library.Toggles[id]:SetVisible(UX.Advanced)
        end
        Library.Options.CombinedChestInterval:SetVisible(UX.Advanced)
        if UX.OpportunityBosses then UX.OpportunityBosses:SetVisible(enabled and Scheduler.Bosses) end
    end
    UX.ApplyExtras=function(value)
        if UX.Loading or UX.UpdatingPreset then return end
        if value=="Personalizado" then
            UX.CustomExtras=true
            Library.Toggles.UXAdvancedSettings:SetValue(true)
            return
        end
        UX.CustomExtras=false
        local resume=Runtime.Pending or Runtime.DesiredEnabled or Scheduler.Enabled and not Scheduler.BackgroundPaused
        Library.Toggles.CombinedFruitCollect:SetValue(value~="Desligados")
        Library.Toggles.CombinedChestCollect:SetValue(value=="Frutas e baús" or value=="Frutas, baús e bosses")
        Library.Toggles.CombinedWorldBosses:SetValue(value=="Frutas, baús e bosses")
        Library.Toggles.CombinedAutomationEnabled:SetValue(value~="Desligados")
        Scheduler.BackgroundPaused=not resume
        if value=="Desligados" and resume then Runtime.SelectFarmMode(UX.SelectedMode()) end
    end
    UX.StopAll=function()
        Library.Toggles.AutoFruitRollPriority:SetValue(false)
        if Runtime.CancelFruitRoll then Runtime.CancelFruitRoll() end
        Library.Toggles.CombinedAutomationEnabled:SetValue(false)
        Runtime.FruitCancel=true
        farmToggle:SetValue(false)
    end
    UX.SyncGoalEditor=function()
        if not UX.GoalTarget or not UX.GoalAmount then return end
        local names=orderedSelection(Runtime.SelectedDrops,Runtime.ItemPriority)
        local signature=table.concat(names,";")
        if UX.GoalSelection~=signature then
            UX.GoalSelection=signature
            UX.GoalTarget:SetValues(names)
            if not table.find(names,UX.GoalTarget.Value) then UX.GoalTarget:SetValue(names[1]) end
        end
        local name=UX.GoalTarget.Value
        UX.GoalAmount:SetVisible(name~=nil)
        if name then
            local amount=Runtime.GetItemGoal(name)
            if tonumber(UX.GoalAmount.Value)~=amount then
                UX.UpdatingGoal=true UX.GoalAmount:SetValue(tostring(amount)) UX.UpdatingGoal=false
            end
        end
    end
    UX.SetItemAmount=function(value)
        if UX.Loading or UX.UpdatingGoal or not UX.GoalTarget.Value then return end
        Runtime.ItemAmounts[UX.GoalTarget.Value]=math.clamp(math.floor(tonumber(value) or 1),1,100000)
        local names={}
        for name in pairs(Runtime.ItemAmounts) do table.insert(names,name) end
        table.sort(names)
        local pairsText={}
        for _,name in ipairs(names) do table.insert(pairsText,name.."="..Runtime.ItemAmounts[name]) end
        Library.Options.ItemQuantityOverrides:SetValue(table.concat(pairsText,"; "))
    end
    local farm=farmTab:AddGroupbox({Side="Left",Name="▶ Começar por aqui"})
    local combat=combatTab:AddGroupbox({Side="Left",Name="⚔ Como lutar"})
    local automatic=combatTab:AddGroupbox({Side="Right",Name="🗡 Espada inicial"})
    UX.AutomaticBox=automatic
    local attributes=combatTab:AddGroupbox({Side="Right",Name="⚙ Pontos e atributos"})
    attributes:SetCollapsed(true)
    local status=farmTab:AddGroupbox({Side="Right",Name="📊 Status e plano"})
    UX.Summary=status:AddLabel("Preparando resumo...",true)
    farm:AddLabel('<font color="#9AA6B8">Escolha o objetivo e use o botão de ativação abaixo.</font>',true)
    UX.Guide=farm:AddLabel("Escolha o objetivo para ver as opções.",true)
    local currentModeLabel=farm:AddLabel('<b>🎯 Modo atual:</b> Auto Level',true)
    local stateLabel=status:AddLabel("<b>⏳ Preparando...</b>",true)
    local levelLabel=status:AddLabel("Nível: —",true)
    local questLabel=status:AddLabel("Missão: —",true)
    UX.QuestLabel=questLabel
    local buildStatus=combatTab:AddGroupbox({Side="Right",Name="📊 Equipamento e pontos"})
    local equipmentLabel=buildStatus:AddLabel("Equipamento: —",true)
    local statsLabel=buildStatus:AddLabel("Pontos: —",true)
    Runtime.Labels={State=stateLabel,Level=levelLabel,Quest=questLabel,Equipment=equipmentLabel,Stats=statsLabel}

    local selectFarmMode,farmModeSelector
    local farmModeLabels={Auto="Auto Level",Money="Dinheiro",Mastery="Mastery",Items="Itens",Haki="Haki",Bosses="Bosses",Unlocks="Desbloqueios",Rerolls="Raça e cor"}
    farmModeSelector=farm:AddDropdown("FarmExecutionMode",{
        Values={"Auto Level","Dinheiro","Mastery","Itens","Haki","Bosses","Desbloqueios","Raça e cor"},
        Default=1,Text="1. O que você quer farmar?",Multi=false,
        DisabledTooltip="Aguarde a ação prioritária terminar. Para encerrar tudo, use Parar tudo.",
        Callback=function(value)
            local selected
            for key,label in pairs(farmModeLabels) do if label==value then selected=key break end end
            if not selected or Runtime.FarmMode==selected then return end
            if Runtime.Ready then
                Runtime.DesiredEnabled=false
                stopFarm()
                farmToggle:SetValue(false)
            end
            Runtime.FarmMode=selected
            Runtime.WatchBossesOnly=false
            Runtime.WorldBossScout=nil
            Runtime.DeferredBosses={}
            Runtime.Completed=false
            Runtime.CompletionMessage=nil
            if Scheduler.Enabled then
                Scheduler.Background=selected
                if Runtime.Ready then Scheduler.BackgroundPaused=true end
                Scheduler.FinishedBackground=nil
                local option=Library.Options.CombinedBackgroundMode
                if option and option.Value~=value then option:SetValue(value) end
            end
            queueSave()
        end,
    })
    farmToggle=farm:AddToggle("AutoLevelEnabled",{
        Text="3. Iniciar / pausar este farm",Default=true,
        DisabledTooltip="Aguarde a coleta ou o roll terminar. Parar tudo continua disponível.",
        Callback=function(value)
            Runtime.DesiredEnabled=value
            if Scheduler.Enabled and not Runtime.PriorityBusy and not Runtime.FruitCollecting then
                Scheduler.BackgroundPaused=not value
            end
            if Runtime.Ready then
                if value then startFarm() else stopFarm() end
                queueSave()
            end
        end,
    })
    UX.Restart=function()
        Runtime.DesiredEnabled=true
        if Runtime.Pending then
            stopFarm()
            Runtime.DesiredEnabled=true
        else
            farmToggle:SetValue(true)
            startFarm()
        end
    end
    farm:AddButton({Text="⏹ Parar tudo",Func=UX.StopAll})

    selectFarmMode=function(selected)
        if Runtime.FarmMode~=selected then Runtime.DeferredBosses={} end
        if selected=="Money" and (Runtime.FarmMode~=selected or Runtime.Completed) then Runtime.MoneyGoalStart=nil end
        Runtime.FarmMode=selected
        if farmModeSelector and farmModeSelector.Value~=farmModeLabels[selected] then
            farmModeSelector:SetValue(farmModeLabels[selected])
        end
        Runtime.WatchBossesOnly=false
        if Scheduler.Enabled then
            Scheduler.Background=selected
            Scheduler.FinishedBackground=nil
            Scheduler.BackgroundPaused=false
            local labels={Auto="Auto Level",Money="Dinheiro",Mastery="Mastery",Items="Itens",Haki="Haki",Bosses="Bosses",Unlocks="Desbloqueios",Rerolls="Raça e cor"}
            local option=Library and Library.Options.CombinedBackgroundMode
            if option and option.Value~=labels[selected] then option:SetValue(labels[selected]) end
            if Runtime.PriorityBusy then return end
        end
        if Runtime.FruitCollecting then
            Runtime.FruitCancel=true
            task.spawn(function()
                while Runtime.FruitCollecting and Runtime.Alive do task.wait(.1) end
                if Runtime.Alive then selectFarmMode(selected) end
            end)
            return
        end
        Runtime.FarmMode=selected
        Runtime.Completed=false
        Runtime.CompletionMessage=nil
        Runtime.DesiredEnabled=true
        if Runtime.Pending then
            stopFarm()
            Runtime.DesiredEnabled=true
        else
            farmToggle:SetValue(true)
        end
    end
    Runtime.SelectFarmMode=selectFarmMode
    farm:AddLabel('<font color="#9AA6B8">Pausar este farm mantém as tarefas extras. <b>Parar tudo</b> encerra também coletas e roll.</font>',true)
    UX.UnlockBox=goalBox("Left","🔓 Aprender estilos e movimento","Unlocks")
    UX.UnlockInfo=goalBox("Right","📋 Requisitos do desbloqueio","Unlocks")
    UX.UnlockLabel=UX.UnlockInfo:AddLabel("Carregando requisitos...",true)
    UX.UnlockStatus=UX.UnlockInfo:AddLabel("Escolha uma técnica e inicie o farm.",true)
    UX.UnlockBox:AddDropdown("UnlockTarget",{
        Values={"Black Leg","Robotic Style","Divergent Style","Flash Step","Ki Dash"},Default=1,Text="🎯 O que aprender",
        Callback=function(value) Runtime.UnlockName=value Runtime.ItemState=nil queueSave() end,
    })
    UX.UnlockBox:AddToggle("UnlockFarmMaterials",{
        Text="📦 Buscar materiais faltantes",Default=true,
        Callback=function(value) Runtime.UnlockFarmMaterials=value queueSave() end,
    })
    UX.UnlockBox:AddToggle("UnlockEquipAfter",{
        Text="✓ Equipar depois de aprender",Default=true,
        Callback=function(value) Runtime.UnlockEquip=value queueSave() end,
    })
    UX.UnlockBox:AddLabel('<b>Como funciona</b>\n1. Busca os materiais que faltam.\n2. Farma o dinheiro necessário.\n3. Visita o treinador e confirma o desbloqueio.\n<font color="#9AA6B8">Equipar um estilo troca o estilo Melee atual. O tipo de farm continua sendo o escolhido em Combate.</font>',true)
    UX.RerollBox=goalBox("Left","🎲 Resultado desejado","Rerolls")
    UX.RerollInfo=goalBox("Right","📊 Resultado e orçamento","Rerolls")
    UX.RerollLabel=UX.RerollInfo:AddLabel("Nenhuma tentativa realizada.",true)
    UX.RerollBox:AddDropdown("RerollKind",{
        Values={"Raça","Cor do Haki"},Default=1,Text="🎯 O que mudar",
        Callback=function(value)
            if Runtime.Ready and not UX.Loading then farmToggle:SetValue(false) end
            Runtime.Reroll.Kind=value=="Raça" and "Race" or "Color"
            Runtime.Reroll.Status=nil queueSave()
        end,
    })
    UX.RaceNames={} UX.ColorNames={}
    for name in pairs(getrenv()._G.GameData["Races Data"] or {}) do table.insert(UX.RaceNames,name) end
    for name in pairs(getrenv()._G.GameData["HakiColors Data"] or {}) do table.insert(UX.ColorNames,name) end
    table.sort(UX.RaceNames) table.sort(UX.ColorNames)
    UX.RerollBox:AddDropdown("RerollDesiredRaces",{
        Values=UX.RaceNames,Default={},Multi=true,Text="✓ Parar em qualquer uma destas raças",Searchable=true,
        Callback=function(value) Runtime.Reroll.Races=value queueSave() end,
    })
    UX.RerollBox:AddDropdown("RerollDesiredColors",{
        Values=UX.ColorNames,Default={},Multi=true,Text="✓ Parar em qualquer uma destas cores",Searchable=true,
        Callback=function(value) Runtime.Reroll.Colors=value queueSave() end,
    })
    UX.RerollBox:AddInput("RerollAttemptLimit",{
        Default="5",Numeric=true,Finished=true,Text="🛑 Máximo de tentativas nesta sessão",
        Callback=function(value) Runtime.Reroll.MaxAttempts=math.clamp(math.floor(tonumber(value) or 5),1,500) queueSave() end,
    })
    UX.RerollBox:AddToggle("RerollUseBananas",{
        Text="🍌 Permitir gastar bananas no Monkey Trader",Default=false,
        Callback=function(value) Runtime.Reroll.UseBananas=value queueSave() end,
    })
    UX.RerollBox:AddInput("RerollBananaLimit",{
        Default="300",Numeric=true,Finished=true,Text="🛑 Máximo de bananas nesta sessão",
        Callback=function(value) Runtime.Reroll.MaxBananas=math.clamp(math.floor(tonumber(value) or 0),0,100000) queueSave() end,
    })
    UX.RerollBox:AddToggle("RerollFarmBananas",{
        Text="⚔ Farmar bananas faltantes",Default=false,
        Callback=function(value) Runtime.Reroll.FarmBananas=value queueSave() end,
    })
    UX.RerollInfo:AddButton({Text="↻ Zerar contadores da sessão",Func=function()
        if Runtime.Pending or Runtime.DesiredEnabled or Runtime.Reroll.Pending then
            Library:Notify("Pause o farm e aguarde a tentativa pendente antes de zerar os contadores.",5) return
        end
        Runtime.Reroll.Attempts=0 Runtime.Reroll.SpentBananas=0 Runtime.Reroll.Status=nil
        Runtime.Completed=false Scheduler.FinishedBackground=nil
    end})
    UX.RerollInfo:AddLabel('<b>🛑 Quando para?</b>\nAo conseguir um resultado selecionado ou atingir um dos limites.\n<font color="#F0C674">Reroll troca a raça ou a cor atual.</font>\n<font color="#9AA6B8">Raça usa os pontos disponíveis primeiro. Bananas só são gastas com sua opção ligada e com o vendedor disponível. A cor é alterada pela própria troca.</font>',true)
    local hakiBox=goalBox("Left","🛡 Evoluir Haki","Haki")
    local hakiStatus=goalBox("Right","📍 Progresso do Haki","Haki")
    local hakiLabel=hakiStatus:AddLabel("Haki: aguardando",true)
    local hakiMaterials=hakiStatus:AddLabel("Materiais: —",true)
    local hakiRequirements=goalBox("Right","📚 Requisitos e custos","Haki",true)
    hakiBox:AddDropdown("HakiGoal",{
        Values={"V1","V2","V3"},Default=3,Multi=false,Text="Evoluir até",
        Callback=function(value) Runtime.HakiGoal=tonumber(value:match("%d")) or 3 queueSave() end,
    })
    hakiBox:AddToggle("HakiFarmMaterials",{
        Text="📦 Buscar materiais faltantes",Default=true,
        Callback=function(value) Runtime.HakiFarmMaterials=value queueSave() end,
    })
    UX.HakiSummon=hakiBox:AddToggle("UXHakiSummonPermission",{
        Text="Permitir invocações",Default=false,
        Callback=function(value)
            if UX.Loading or UX.SyncingSummon then return end
            UX.SyncingSummon=true Library.Toggles.AutoSummonBoss:SetValue(value) UX.SyncingSummon=false
        end,
    })
    local hakiNextRequirements=hakiBox:AddLabel("",true)
    Runtime.HakiNextRequirementsLabel=hakiNextRequirements
    hakiRequirements:AddLabel("<b><font color=\"#80C7FF\">② Haki V2</font></b>\n💎 1 Armament Crystal + 1 Magic Ball\n💰 $35.000\n\n<b><font color=\"#80C7FF\">③ Haki V3</font></b>\n💎 Mais 1 de cada material\n💰 $50.000\n<font color=\"#F0C674\">As melhorias consomem dinheiro e materiais.</font>",true)
    hakiRequirements:AddLabel("<b>📦 Onde buscar</b>\nMagic Ball → <b>Old Fighter</b>\nArmament Crystal → <b>Beast User</b>\n<font color=\"#9AA6B8\">Permita invocações para usar o Mad Chip no Beast.</font>",true)
    local bossBox=goalBox("Left","👹 Bosses no mapa","Bosses")
    local bossStatus=goalBox("Right","📊 Progresso dos bosses","Bosses")
    local bossLabel=bossStatus:AddLabel("Aguardando boss",true)
    bossStatus:AddLabel("<b>Atualização: bosses e drops</b>\n"..Runtime.UpdateSupport.bossDescription(getrenv()._G.GameData,{"Old White","Light User","Restricted Sorcerer"}),true)
    bossStatus:AddLabel('<font color="#9AA6B8">Intervalos e chances vêm do catálogo atual do client. O servidor decide o spawn real; o farm procura bosses vivos e avisos, sem depender de um timer presumido.</font>',true)

    local bossNames={}
    for name,data in pairs(getrenv()._G.GameData["Enemys Data"]) do
        if data.Boss then table.insert(bossNames,name) end
    end
    table.sort(bossNames)
    bossBox:AddDropdown("WorldBossTargets",{
        Values=bossNames,Default={"Old Fighter"},Multi=true,Searchable=true,Text="Bosses que já estão no mapa",
        Callback=function(value)
            Runtime.BossTargets=value
            if UX.OpportunityBosses and not UX.SyncingBosses then
                UX.SyncingBosses=true UX.OpportunityBosses:SetValue(value) UX.SyncingBosses=false
            end
            queueSave()
        end,
    })
    bossBox:AddInput("WorldBossExtraName",{
        Text="🔎 Outro nome exato (opcional)",Default="",Finished=true,
        Callback=function(value) Runtime.CustomBossName=value:gsub("^%s+",""):gsub("%s+$","") queueSave() end,
    })
    local summonBox=goalBox("Left","🔮 Invocar bosses","Bosses")
    summonBox:AddDropdown("SummonBossTarget",{
        Values={"Cursed Prodigy","Dual Swordsman","Beast User"},Default={"Cursed Prodigy"},Multi=true,Text="🔮 Bosses para invocar (vários)",
        Callback=function(value)
            Runtime.SummonBosses={}
            for name,enabled in pairs(type(value)=="table" and value or {}) do if enabled then Runtime.SummonBosses[name]=true end end
            queueSave()
        end,
    })
    summonBox:AddInput("SummonPriorityOrder",{
        Text="① Prioridade (nomes separados por ;)",
        Default="Cursed Prodigy; Dual Swordsman; Beast User",Finished=true,
        Callback=function(value)
            local ok,result=pcall(parsePriority,value,{["Cursed Prodigy"]=true,["Dual Swordsman"]=true,["Beast User"]=true})
            if ok then Runtime.SummonPriority=result Runtime.SummonQueueError=nil
            else Runtime.SummonQueueError=tostring(result) end
            queueSave()
        end,
    })
    local summonQueueLabel=bossStatus:AddLabel("🔮 Fila de invocação: aguardando",true)
    UX.AddPriorityEditor(summonBox,"SummonPriorityPicker",function() return Runtime.SummonBosses end,function() return Runtime.SummonPriority end,"SummonPriorityOrder")
    summonBox:AddLabel('<b>🔀 Ordem da fila</b>\nBoss vivo → invocação pronta → fonte de material viva. A prioridade acima ordena cada etapa.\n<font color="#9AA6B8">Se faltar o alvo, tenta outro selecionado. Mantém o combate em andamento e verifica os spawns a cada 20 s.</font>',true)
    summonBox:AddToggle("AutoSummonBoss",{
        Text="⚠ Permitir invocações",Default=false,
        Callback=function(value)
            Runtime.AutoSummonBoss=value
            if UX.HakiSummon and not UX.SyncingSummon then UX.SyncingSummon=true UX.HakiSummon:SetValue(value) UX.SyncingSummon=false end
            queueSave()
        end,
    })
    summonBox:AddToggle("FarmSummonMaterial",{
        Text="📦 Buscar material de invocação",Default=true,
        Callback=function(value) Runtime.FarmSummonMaterial=value queueSave() end,
    })
    summonBox:AddLabel("<b><font color=\"#80C7FF\">Materiais de invocação</font></b>\n🔮 Noko • <b>Prodigy Orb</b> → Cursed Prodigy\n🔮 Seraphina • <b>Dual Orb</b> → Dual Swordsman\n🔮 Mad Scientist • <b>Mad Chip</b> → portal do Beast\n<font color=\"#F0C674\">Cada invocação consome o material.</font>",true)
    summonBox:AddLabel("<b>🛡 Integração com Haki</b>\nPode invocar o Beast para buscar Armament Crystal.\n<font color=\"#F0C674\">A entrada no portal ainda precisa ser validada em uma raid ativa.</font>",true)
    bossStatus:AddLabel("<font color=\"#9AA6B8\">Usa o equipamento escolhido em Combate. Para aproveitar estes bosses durante outro objetivo, use Interrupções.</font>",true)
    bossStatus:AddLabel("<b>📍 Spawn</b>\nOld Fighter é o alvo padrão. O modo Bosses verifica os pontos de spawn.\n<font color=\"#9AA6B8\">Alguns alvos podem não estar disponíveis neste servidor.</font>",true)
    local automationBox=automationTab:AddGroupbox({Side="Left",Name="🔀 Prioridades"})
    UX.ExtrasPreset=automationBox:AddDropdown("UXExtrasPreset",{
        Values={"Desligados","Só frutas","Frutas e baús","Frutas, baús e bosses","Personalizado"},
        Default=5,Text="Atividades extras",Callback=function(value) UX.ApplyExtras(value) end,
    })
    automationBox:AddLabel('<font color="#9AA6B8">Escolha um conjunto pronto. O roll automático é ligado separadamente abaixo. Essas tarefas pausam o farm principal e depois devolvem o controle.</font>',true)
    local backgroundBox=goalBox("Right","Configuração interna","Never")
    local automationStatus=automationTab:AddGroupbox({Side="Right",Name="📊 Acompanhamento"})
    local automationLabel=automationStatus:AddLabel("Automação combinada desligada.",true)
    local priorityPolicyBox=automationTab:AddGroupbox({Side="Left",Name="⚖ Interrupções do combate"})
    priorityPolicyBox:AddLabel('<b>Quando um boss já está em combate:</b>\nEscolha separadamente o comportamento de frutas e roll.',true)
    for _,entry in ipairs({{"Fruit","🍈 Fruta apareceu","FruitBossPriorityPolicy"},{"Roll","🎲 Roll disponível","RollBossPriorityPolicy"}}) do
        local key=entry[1]
        priorityPolicyBox:AddDropdown(entry[3],{
            Values={"Interromper boss","Terminar boss atual"},Default=1,Text=entry[2],
            Callback=function(value)
                Runtime.PriorityPolicy[key]=value=="Terminar boss atual" and "Finish" or "Interrupt"
                Runtime.DeferredBosses[key]=nil
                queueSave()
            end,
        })
    end
    priorityPolicyBox:AddLabel('<b>Interromper:</b> pausa o boss e segue a transição segura.\n<b>Terminar:</b> aguarda somente o boss atual morrer, sem esperar pelos próximos.\n<font color="#9AA6B8">Fora de combate com boss, executa normalmente. Entre ações liberadas, o roll tem preferência. Os botões manuais executam na hora.</font>',true)
    local activityBox=configTab:AddGroupbox({Side="Right",Name="🩺 Diagnóstico da sessão"})
    activityBox:SetCollapsed(true)
    local activityPhase=activityBox:AddLabel("Atividade: aguardando",true)
    local activityTarget=activityBox:AddLabel("Alvo: —",true)
    local activityReason=activityBox:AddLabel("Detalhe: —",true)
    local activityNext=activityBox:AddLabel("Próximo: —",true)
    local activityFailure=activityBox:AddLabel("Última falha: nenhuma",true)
    local activityRecovery=activityBox:AddLabel("Recuperações: 0",true)
    local recoveryBox=configTab:AddGroupbox({Side="Left",Name="🛠 Recuperação automática"})
    recoveryBox:SetCollapsed(true)
    recoveryBox:AddToggle("RecoverStalledCombat",{
        Text="🛠 Recuperar combate travado",Default=true,
        Callback=function(value) CONFIG.RecoverCombat=value queueSave() end,
    })
    recoveryBox:AddLabel("<b><font color=\"#80C7FF\">Recuperação automática</font></b>\n⚔ Sem dano por <b>30 s</b> ou longe por <b>12 s</b>: reequipa e reposiciona.\n⏳ Após 3 tentativas: espera <b>60 s</b> naquele alvo.\n🍈 Coleta: limite de <b>35 s</b>.\n<font color=\"#9AA6B8\">A recuperação do combate preserva a missão.</font>",true)
    recoveryBox:AddButton({Text="🧹 Limpar histórico de falhas",Func=function()
        Runtime.Diagnostics={Recoveries=0,History={}}
    end})
    automationBox:AddToggle("CombinedAutomationEnabled",{
        Text="▶ Ativar prioridades automáticas",Default=false,
        Callback=function(value)
            Scheduler.Enabled=value
            Scheduler.LastError=nil
            Scheduler.FinishedBackground=nil
            Scheduler.BackgroundPaused=false
            Scheduler.NextChestCheck=0
            if not value then
                Runtime.DeferredBosses.Fruit=nil
                Runtime.FruitCancel=true
                Runtime.DesiredEnabled=false
                if Runtime.Ready then stopFarm() end
            end
            queueSave()
        end,
    })
    automationBox:AddToggle("CombinedFruitCollect",{
        Text="① 🍈 Frutas que aparecerem",Default=true,
        Callback=function(value) Scheduler.Fruits=value if not value then Runtime.DeferredBosses.Fruit=nil end queueSave() end,
    })
    automationBox:AddToggle("CombinedWorldBosses",{
        Text="② 👹 Bosses selecionados",Default=false,
        Callback=function(value) Scheduler.Bosses=value queueSave() end,
    })
    UX.OpportunityBosses=automationBox:AddDropdown("UXOpportunityBossTargets",{
        Values=bossNames,Default={"Old Fighter"},Multi=true,Searchable=true,Text="Quais bosses aproveitar?",
        Callback=function(value)
            if UX.Loading or UX.SyncingBosses then return end
            UX.SyncingBosses=true
            Library.Options.WorldBossTargets:SetValue(value)
            UX.SyncingBosses=false
        end,
    })
    automationBox:AddToggle("CombinedChestCollect",{
        Text="③ 📦 Baús disponíveis",Default=true,
        Callback=function(value) Scheduler.Chests=value Scheduler.NextChestCheck=0 queueSave() end,
    })
    automationBox:AddSlider("CombinedChestInterval",{
        Text="⏱ Checar baús a cada (s)",Default=120,Min=30,Max=600,Rounding=0,
        Callback=function(value) Scheduler.ChestInterval=value queueSave() end,
    })
    automationBox:AddLabel("<b>🍈 Frutas respeitam a escolha de interrupção abaixo.</b>\n👹 Termina o boss atual antes dos baús.\n<font color=\"#9AA6B8\">Baús: servidor com 20 min ou mais. Após coletar, espera 20 min para tentar o mesmo baú.</font>",true)
    local backgroundNames={["Auto Level"]="Auto",Dinheiro="Money",Mastery="Mastery",Itens="Items",Haki="Haki",Bosses="Bosses",["Desbloqueios"]="Unlocks",["Raça e cor"]="Rerolls"}
    backgroundBox:AddDropdown("CombinedBackgroundMode",{
        Values={"Mastery","Dinheiro","Itens","Haki","Bosses","Auto Level","Desbloqueios","Raça e cor"},Default=1,Multi=false,Text="④ 🎯 Objetivo principal",
        Callback=function(value)
            Scheduler.Background=backgroundNames[value] or "Mastery"
            Scheduler.FinishedBackground=nil
            if Runtime.Ready and Scheduler.Enabled and not Runtime.PriorityBusy and Runtime.FarmMode~=Scheduler.Background then
                selectFarmMode(Scheduler.Background)
            end
            queueSave()
        end,
    })
    backgroundBox:AddLabel("<b>↩ Retomada automática</b>\nApós cada coleta, volta ao objetivo escolhido.\n<font color=\"#9AA6B8\">Configure equipamento em Auto Level e os alvos nas abas correspondentes.</font>",true)
    backgroundBox:AddLabel("<b>⏸ Pausar farm:</b> pausa o objetivo principal.\n<b><font color=\"#F0C674\">⏹ Parar tudo:</font></b> também desativa a busca por frutas e baús.",true)
    backgroundBox:AddLabel("<font color=\"#F0C674\">Use este sistema com o Main do rejoin descarregado.</font>",true)
    local itemChoiceBox=goalBox("Left","🎁 Tipo de busca","Items")
    local itemBox=goalBox("Left","🎁 Itens desejados","ItemsDrop")
    local itemAdvanced=goalBox("Left","⚙ Fontes dos drops","ItemsDrop",true)
    local itemInfo=goalBox("Right","📋 Progresso dos itens","Items")
    local purchaseBox=goalBox("Left","🛒 Compra ou troca","ItemsPurchase")
    purchaseBox:AddLabel('<font color="#9AA6B8">Para usar este grupo, escolha <b>Compras e trocas</b> em Forma de obter.</font>',true)
    local itemLabel=itemInfo:AddLabel("Item: —",true)
    local sourceLabel=itemInfo:AddLabel("Fonte: —",true)
    local itemStatusLabel=itemInfo:AddLabel("Status: aguardando",true)
    local itemSessionLabel=itemInfo:AddLabel("Inventário: 0 | Abates: 0",true)
    local catalog,dropNames={},{}
    local dataGlobal=getrenv()._G
    itemChoiceBox:AddDropdown("UtilityItemMethod",{
        Values={"Drop de inimigos","Compras e trocas"},Default=1,Text="🧭 Forma de obter",
        Callback=function(value)
            Runtime.ItemMethod=value=="Compras e trocas" and "Purchase" or "Drop"
            Runtime.ItemState=nil
            queueSave()
        end,
    })
    local purchaseNames={}
    for name,recipe in pairs(acquisitionRecipes) do
        local data=dataGlobal.GameData["Items Data"][name]
        if recipe.Kind~="Unlock" and not (data and data.NoRealItem) then table.insert(purchaseNames,name) end
    end
    for name in pairs(acquisitionShops) do
        local data=dataGlobal.GameData["Items Data"][name]
        if data and type(data.Price)=="number" then table.insert(purchaseNames,name) end
    end
    table.sort(purchaseNames)
    local purchaseDropdown=purchaseBox:AddDropdown("UtilityPurchaseItem",{
        Values=purchaseNames,Default=table.find(purchaseNames,Runtime.AcquisitionName) or 1,
        Text="🛒 Compra ou troca desejada",Searchable=true,
        Callback=function(value) Runtime.AcquisitionName=value Runtime.ItemState=nil queueSave() end,
    })
    local purchaseCost=purchaseBox:AddLabel("Custo da compra: —",true)
    purchaseBox:AddLabel("<b><font color=\"#F0C674\">⚠ Trocas consomem os materiais.</font></b>\nDual Sword também exige Shadow Blade e Emerald Blade.\n<font color=\"#9AA6B8\">Invocações usam a permissão do objetivo Bosses.</font>",true)
    for enemy,data in pairs(dataGlobal.GameData["Enemys Data"]) do
        if data.Health then
            for drop,chance in pairs(data.Drops or {}) do
                if type(chance)=="number" and chance>0 then
                    if not catalog[drop] then catalog[drop]={} table.insert(dropNames,drop) end
                    table.insert(catalog[drop],{Enemy=enemy,Chance=chance,Level=data.RecomendedLevel or 0,Health=data.Health})
                end
            end
        end
    end
    table.sort(dropNames)
    for _,sources in pairs(catalog) do
        table.sort(sources,function(a,b)
            if a.Level~=b.Level then return a.Level<b.Level end
            if a.Chance~=b.Chance then return a.Chance>b.Chance end
            return a.Enemy<b.Enemy
        end)
    end
    local sourceOptions,sourceMap={},{}
    local sourceDropdown
    local function selectDrop(name)
        if not catalog[name] then return end
        Runtime.SelectedDrop=name
        Runtime.SourceEditingDrop=name
        sourceOptions,sourceMap={},{}
        for _,source in ipairs(catalog[name]) do
            local text=source.Enemy.." | "..source.Chance.."% | nível "..source.Level
            table.insert(sourceOptions,text)
            sourceMap[text]=source
        end
        Runtime.ItemEnemy=Runtime.ItemSources[name] or catalog[name][1].Enemy
        local sourceValue=sourceOptions[1]
        for text,source in pairs(sourceMap) do
            if source.Enemy==Runtime.ItemEnemy then sourceValue=text break end
        end
        Runtime.ItemState=nil
        if sourceDropdown then
            sourceDropdown:SetValues(sourceOptions)
            sourceDropdown:SetValue(sourceValue)
        end
        queueSave()
    end
    Runtime.SelectDropForFarm=function(name,enemy)
        assert(catalog[name],"Item de drop inválido: "..tostring(name))
        Runtime.SelectedDrop=name
        Runtime.ItemEnemy=enemy or Runtime.ItemSources[name] or catalog[name][1].Enemy
        Runtime.ItemState=nil
    end
    selectDrop(Runtime.SelectedDrop)
    local dropDropdown=itemBox:AddDropdown("UtilityDropItem",{
        Values=dropNames,Default={Runtime.SelectedDrop},Multi=true,
        Text="🎁 Drops desejados (vários)",Searchable=true,
        Callback=function(values)
            local chosen={}
            for name,enabled in pairs(type(values)=="table" and values or {}) do
                if enabled and catalog[name] then chosen[name]=true end
            end
            Runtime.SelectedDrops=chosen
            local names={}
            for name in pairs(chosen) do table.insert(names,name) end
            table.sort(names)
            if not chosen[Runtime.SelectedDrop] and names[1] then selectDrop(names[1]) end
            Scheduler.FinishedBackground=nil
            queueSave()
        end,
    })
    local sourceItemDropdown=itemAdvanced:AddDropdown("UtilityDropSourceItem",{
        Values=dropNames,Default=table.find(dropNames,Runtime.SelectedDrop) or 1,
        Text="🔧 Editar a fonte deste item",Searchable=true,
        Callback=function(name)
            if catalog[name] then
                local current,enemy=Runtime.SelectedDrop,Runtime.ItemEnemy
                selectDrop(name)
                Runtime.SelectedDrop,Runtime.ItemEnemy=current,enemy
            end
        end,
    })
    local ownershipSignature
    local function refreshItemOwnership()
        local icons,signature={},{}
        for _,name in ipairs(dropNames) do
            local owned=itemCount(dataGlobal,name)>0
            icons[name]=owned and "check" or "circle"
            table.insert(signature,owned and "1" or "0")
        end
        local key=table.concat(signature)
        if key==ownershipSignature then return end
        ownershipSignature=key
        dropDropdown.ValueImages=icons
        dropDropdown:SetValues(dropNames)
    end
    Runtime.RefreshItemOwnership=refreshItemOwnership
    itemBox:AddLabel("<font color=\"#8DDEA1\"><b>✓ Já possui</b></font> • ○ Ainda falta\n<font color=\"#9AA6B8\">Atualiza com o inventário.</font>",true)
    sourceDropdown=itemAdvanced:AddDropdown("UtilityDropSource",{
        Values=sourceOptions,Default=1,Multi=false,Text="👹 Fonte preferida do drop",
        Callback=function(value)
            local source=sourceMap[value]
            if source then
                local name=Runtime.SourceEditingDrop or Runtime.SelectedDrop
                Runtime.ItemSources[name]=source.Enemy
                if Runtime.SelectedDrop==name then Runtime.ItemEnemy=source.Enemy end
                queueSave()
            end
        end,
    })
    itemAdvanced:AddToggle("UtilityItemQuest",{
        Text="📜 Fazer missão do alvo, se disponível",Default=true,
        Callback=function(value) Runtime.ItemWithQuest=value queueSave() end,
    })
    itemBox:AddLabel("<b>① Selecione os itens.</b>\n<b>② Inicie a busca.</b>\nPula os já possuídos e farma um por vez.\n<font color=\"#8DDEA1\">✓ Encerra quando conseguir todos.</font>",true)
    itemInfo:AddLabel("<font color=\"#9AA6B8\">🎲 A chance é por abate; não garante drop após uma quantidade fixa.</font>",true)
    itemInfo:AddLabel("<b>⏳ Sem alvo disponível?</b>\nAguarda o respawn. Para invocar bosses especiais, permita invocações em Farm → Bosses.",true)
    Runtime.ItemControls={Drop=dropDropdown,Source=sourceDropdown,SourceItem=sourceItemDropdown,Purchase=purchaseDropdown}
    Runtime.ItemCatalog=catalog
    local itemGoalsBox=goalBox("Right","🎯 Quantidades e fila","ItemsDrop")
    local itemQueueLabel=itemGoalsBox:AddLabel("Selecione os drops desejados.",true)
    itemGoalsBox:AddToggle("ItemQueueAvailability",{
        Text="Pular alvos que não nasceram",Default=true,
        Callback=function(value) Runtime.ItemQueueEnabled=value queueSave() end,
    })
    itemGoalsBox:AddInput("ItemPriorityOrder",{
        Text="① Prioridade dos drops (separar por ;)",Default="",Finished=true,
        Callback=function(value)
            local ok,result=pcall(parsePriority,value,catalog)
            if ok then Runtime.ItemPriority=result Runtime.ItemQueueError=nil else Runtime.ItemQueueError=tostring(result) end
            queueSave()
        end,
    })
    UX.AddPriorityEditor(itemGoalsBox,"DropPriorityPicker",function() return Runtime.SelectedDrops end,function() return Runtime.ItemPriority end,"ItemPriorityOrder")
    UX.GoalTarget=UX.Editors[#UX.Editors].Focus
    UX.GoalAmount=itemGoalsBox:AddInput("UXItemAmountEditor",{
        Text="Quantidade desejada",Default="1",Numeric=true,Finished=true,
        Callback=function(value) UX.SetItemAmount(value) end,
    })
    itemGoalsBox:AddInput("ItemDefaultAmount",{
        Text="🎒 Quantidade padrão por material",Default="1",Numeric=true,Finished=true,
        Callback=function(value)
            Runtime.ItemDefaultAmount=math.clamp(math.floor(tonumber(value) or 1),1,100000)
            Scheduler.FinishedBackground=nil
            queueSave()
        end,
    })
    itemGoalsBox:AddInput("ItemQuantityOverrides",{
        Text="📦 Metas específicas (Nome=quantidade; ...)",Default="",Finished=true,
        Callback=function(value)
            local ok,result=pcall(function()
                local goals={}
                for raw in value:gmatch("[^;]+") do
                    local name,amount=raw:match("^%s*(.-)%s*=%s*(%d+)%s*$")
                    assert(name and catalog[name],"Meta inválida: "..raw)
                    amount=tonumber(amount)
                    assert(amount>=1 and amount<=100000,"Quantidade deve ser de 1 a 100000.")
                    goals[name]=amount
                end
                return goals
            end)
            if ok then Runtime.ItemAmounts=result Runtime.ItemGoalError=nil
            else Runtime.ItemGoalError=tostring(result) end
            Scheduler.FinishedBackground=nil
            queueSave()
        end,
    })
    itemGoalsBox:AddLabel('<font color="#9AA6B8">Selecione um alvo da fila para ajustar sua quantidade ou subir/descer a prioridade. Conta o total no inventário. Espadas, acessórios e estilos têm meta de 1.</font>',true)
    local moneyBox=goalBox("Left","💰 Dinheiro e meta","Money")
    local masteryBox=goalBox("Left","⭐ Mastery e meta","Mastery")
    moneyBox:AddToggle("MoneyGoalEnabled",{
        Text="🎯 Parar na meta de dinheiro",Default=false,
        Callback=function(value) Runtime.MoneyGoal.Enabled=value Scheduler.FinishedBackground=nil queueSave() end,
    })
    moneyBox:AddDropdown("MoneyGoalBasis",{
        Values={"Saldo total","Ganho da sessão"},Default=1,Text="Contar dinheiro por",
        Callback=function(value)
            if Runtime.MoneyGoal.Basis~=value then Runtime.MoneyGoalStart=nil end
            Runtime.MoneyGoal.Basis=value queueSave()
        end,
    })
    moneyBox:AddInput("MoneyGoalAmount",{
        Text="💰 Valor da meta",Default="100000",Numeric=true,Finished=true,
        Callback=function(value) Runtime.MoneyGoal.Amount=math.clamp(math.floor(tonumber(value) or 100000),1,1000000000) Scheduler.FinishedBackground=nil queueSave() end,
    })
    local moneyGoalLabel=moneyBox:AddLabel("Meta de dinheiro desativada.",true)
    moneyBox:AddLabel('<font color="#9AA6B8">Ganho da sessão conta o saldo líquido desde o início do objetivo, preservando pausas e coletas. Gastos reduzem esse ganho.</font>',true)
    masteryBox:AddToggle("MasteryGoalEnabled",{
        Text="🎯 Parar na mastery escolhida",Default=false,
        Callback=function(value) Runtime.MasteryGoal.Enabled=value Scheduler.FinishedBackground=nil queueSave() end,
    })
    masteryBox:AddInput("MasteryGoalAmount",{
        Text="⭐ Mastery desejada",Default="100",Numeric=true,Finished=true,
        Callback=function(value) Runtime.MasteryGoal.Amount=math.clamp(math.floor(tonumber(value) or 100),1,tonumber(dataGlobal.GameData["Balancing Data"].MaxMastery) or 100000) Scheduler.FinishedBackground=nil queueSave() end,
    })
    local masteryGoalLabel=masteryBox:AddLabel("Sem meta: vai até a mastery máxima.",true)
    local utilityStatus=goalBox("Right","📊 Resultado do farm","Utility")
    local fruitChestBox=fruitTab:AddGroupbox({Side="Left",Name="🎁 Baús de fruta"})
    fruitChestBox:AddDropdown("FruitChestSelection",{
        Values=Runtime.UpdateSupport.FruitChests,Default=1,Text="Baú do inventário para abrir",
        Callback=function(value) Runtime.FruitChestSelection=value end,
    })
    local fruitChestStatus=fruitChestBox:AddLabel("Abre uma unidade por clique. Não compra baús.",true)
    fruitChestBox:AddButton({Text="Abrir 1 baú selecionado",Func=function()
        task.spawn(function()
            local ok,err=pcall(openSelectedFruitChest)
            if not ok then Runtime.FruitChestStatus=tostring(err) end
        end)
    end})
    fruitChestBox:AddLabel('<font color="#9AA6B8">O farm pausa durante a abertura. Aguarda a fruta aparecer e tenta guardar respeitando o limite. Sem confirmação, não repete o comando. Para obter baús, selecione os drops no objetivo Itens.</font>',true)
    local updateBox=configTab:AddGroupbox({Side="Right",Name="🌊 Atualização Tremor"})
    updateBox:AddLabel("<b>Light</b>\nCompatível com M1 e skills do equipamento selecionado em Combate. Light Speed é movimento e não entra na rotação de dano.\n\n<b>Tremor Island Pose</b>\nDisponível em Itens → Compras e trocas, com preço lido do jogo.",true)
    local banana=getrenv()._G.GameData["Boats Data"]["Banana Boat"]
    updateBox:AddLabel("<b>Banana Boat</b>\nPreço do client: $"..tostring(banana and banana.Price or "?")..". A compra permanece manual na loja do jogo.",true)
    updateBox:AddButton({Text="Abrir loja de barcos",Func=function()
        local ok,err=pcall(function()
            local g=getrenv()._G
            assert(type(g.OpenInterface)=="function","Interface de barcos indisponível.")
            g.OpenInterface("Shipwright")
        end)
        if not ok then Runtime.LastError=tostring(err) end
    end})
    updateBox:AddLabel('<font color="#9AA6B8">King of Curses Outfit, Unlimited Sorcerer e Polarized Sunglasses são itens de bundles da loja. Não há compra automática de Robux.</font>',true)
    local fruitBox=fruitTab:AddGroupbox({Side="Right",Name="⚙ Coleta e armazenamento"})
    fruitBox:SetCollapsed(true)
    local fruitShopBox=fruitTab:AddGroupbox({Side="Left",Name="🍈 Consultar e roletar"})
    local stockLabel=fruitShopBox:AddLabel('<font color="#9AA6B8">Consulte o estoque para ver as frutas disponíveis e os preços.</font>',true)
    fruitShopBox:AddButton({Text="📋 Abrir stock de frutas",Func=function()
        task.spawn(function()
            local ok,result=pcall(openFruitStock)
            if not ok then
                Runtime.FruitStockError=tostring(result)
                setStatusText(stockLabel,"Não foi possível abrir o stock: "..tostring(result))
            end
        end)
    end})
    fruitShopBox:AddLabel('<font color="#9AA6B8">Abre a loja do jogo e oculta este menu. Use <b>Menu</b> para voltar às funções.</font>',true)
    local rollLabel=fruitShopBox:AddLabel("🎲 Verificando disponibilidade do roll...",true)
    local rollResult=fruitShopBox:AddLabel("Nenhum roll solicitado.",true)
    automationBox:AddToggle("AutoFruitRollPriority",{
        Text="🎲 Roll automático",Default=true,
        Callback=function(value)
            Runtime.AutoFruitRollEnabled=value
            if not value then Runtime.DeferredBosses.Roll=nil end
            if not value and Runtime.ActiveFruitRollAuto and Runtime.CancelFruitRoll then Runtime.CancelFruitRoll() end
            queueSave()
        end,
    })
    fruitShopBox:AddButton({Text="⏹ Cancelar prioridade de roll",Func=function()
        Library.Toggles.AutoFruitRollPriority:SetValue(false)
        if Runtime.CancelFruitRoll then Runtime.CancelFruitRoll() end
    end})
    fruitShopBox:AddButton({Text="🎲 Roletar aqui (perto do Luzefe)",Func=function()
        task.spawn(function()
            local ok,err=pcall(rollFruit)
            if not ok then Runtime.FruitRollStatus="Roll indisponível: "..tostring(err) end
        end)
    end})
    fruitShopBox:AddLabel('<b>① 🎲 Roll automático.</b>\nCom nível, saldo e cooldown liberados, respeita a política de boss em <b>Interrupções</b>; depois pausa os sistemas e vai ao Luzefe. Funciona mesmo com a automação combinada desligada.\n<font color="#F0C674">Só retoma após confirmar a fruta. Se houver débito ou cooldown, aguarda a fruta sem repetir o giro. Sem aceite confirmado em 45s, retoma o farm e adia nova tentativa por 5 min.</font>\n<font color="#9AA6B8">Tenta guardar respeitando seus slots. O botão manual exige já estar perto do NPC.</font>',true)
    local fruitStatus=fruitBox:AddLabel("Coleta independente, sem relogar.",true)
    fruitBox:AddSlider("UtilityFruitTweenSpeedV3",{
        Text="💨 Velocidade de chegada (studs/s)",Default=125,Min=30,Max=300,Rounding=0,
        Callback=function(value) Runtime.FruitTweenSpeed=value queueSave() end,
    })
    fruitBox:AddSlider("FruitCombatHandoffSeconds",{
        Text="⏸ Pausa após parar de bater (s)",Default=2,Min=1,Max=5,Rounding=1,
        Callback=function(value) Runtime.FruitHandoffDelay=value queueSave() end,
    })
    fruitBox:AddSlider("FruitArrivalWaitSeconds",{
        Text="⏳ Espera a 50 studs, antes do tween (s)",Default=4,Min=1,Max=10,Rounding=1,
        Callback=function(value) Runtime.FruitArrivalDelay=value queueSave() end,
    })
    fruitBox:AddSlider("FruitPickupWaitSeconds",{
        Text="🍈 Espera ao lado da fruta, antes do prompt (s)",Default=2,Min=.5,Max=10,Rounding=1,
        Callback=function(value) Runtime.FruitPickupDelay=value queueSave() end,
    })
    fruitBox:AddSlider("FruitBetweenPickupsWaitSeconds",{
        Text="🍈 Intervalo antes de buscar outra fruta (s)",Default=5,Min=1,Max=15,Rounding=1,
        Callback=function(value) Runtime.FruitBetweenPickupsDelay=value queueSave() end,
    })
    fruitBox:AddLabel('<font color="#9AA6B8">O intervalo entre coletas só é aplicado se outra fruta for encontrada. Sem outra fruta, retoma o farm normalmente.</font>',true)
    fruitBox:AddLabel('<b>📍 Ordem da coleta</b>\n① Para os ataques e aguarda a pausa.\n② Vai ao spawn seguro e espera o chão carregar.\n③ Aproxima a 50 studs e aguarda.\n④ Faz o tween final.\n⑤ Aguarda ao lado da fruta e ativa a coleta.',true)
    fruitBox:AddSlider("UtilityFruitStorageLimit",{
        Text="🎒 Slots por tipo de fruta",Default=1,Min=1,Max=5,Rounding=0,
        Callback=function(value) Runtime.FruitStorageLimit=math.clamp(tonumber(value) or 1,1,5) queueSave() end,
    })
    fruitBox:AddLabel("<b>🎒 Armazenamento</b>\nPadrão: <b>1 por tipo</b>.\n<font color=\"#F0C674\">Aumente somente se tiver slots extras. Não tenta guardar quando atinge esse limite.</font>",true)
    fruitBox:AddButton({Text="▶ Coletar frutas agora",Func=function() task.spawn(collectDevilFruits) end})
    fruitBox:AddButton({Text="⏸ Parar coleta",Func=function() Runtime.FruitCancel=true end})
    fruitBox:AddLabel("<b>📍 Como chega à fruta</b>\n① Teleporta até <b>50 studs</b>, se estiver longe.\n② Percorre o restante na velocidade escolhida.\n③ Coleta e tenta guardar se houver slot.\n<font color=\"#9AA6B8\">Funciona sem rejoin.</font>",true)
    local utilityLabel=utilityStatus:AddLabel("Modo: Auto Level",true)
    local moneyLabel=utilityStatus:AddLabel("Dinheiro ganho: —",true)
    local masteryLabel=utilityStatus:AddLabel("Mastery: —",true)
    local moneyChoices={["Elements Quest (100+)"]="ElementsQuest",["Curse Tower (235+)"]="030",["Cursed Dolls (180+)"]="025",["Heal Sorcerers (215+)"]="028"}
    moneyBox:AddDropdown("UtilityMoneyQuest",{
        Values={"Curse Tower (235+)","Elements Quest (100+)","Cursed Dolls (180+)","Heal Sorcerers (215+)"},Default=1,
        Text="📜 Missão de dinheiro",Multi=false,
        Callback=function(value) Runtime.MoneyQuest=moneyChoices[value] or "030" queueSave() end,
    })
    moneyBox:AddLabel("<b><font color=\"#80C7FF\">🟢 Nível 100+</font></b>\nElements Quest • <b>$500</b>\nEntregar as quatro cores aos cientistas.",true)
    moneyBox:AddLabel("<b><font color=\"#80C7FF\">🔵 Nível 235+</font></b>\nCurse Tower • <b>$1.550</b>\nAtivar os quatro pontos da torre.",true)
    moneyBox:AddLabel("<font color=\"#9AA6B8\">Repete a missão no nível máximo. Respeita o nível mínimo da missão selecionada.</font>",true)
    local masteryChoices={["Corrupted Player (135+)"]="020",["Knight Monkey (60+)"]="009",["Jujutsu Student (165+)"]="024",["Special Student (190+)"]="026"}
    masteryBox:AddDropdown("UtilityMasteryQuest",{
        Values={"Corrupted Player (135+)","Knight Monkey (60+)","Jujutsu Student (165+)","Special Student (190+)"},Default=1,
        Text="👹 Alvo de mastery",Multi=false,
        Callback=function(value) Runtime.MasteryQuest=masteryChoices[value] or "020" queueSave() end,
    })
    masteryBox:AddLabel("<b><font color=\"#80C7FF\">🟢 Acessível • Nível 60+</font></b>\nKnight Monkey • <b>240 HP</b>\n⭐ 35 EXP de mastery por inimigo.",true)
    masteryBox:AddLabel("<b><font color=\"#80C7FF\">🔵 Avançado • Nível 135+</font></b>\nCorrupted Player • <b>600 HP</b>\n⭐ 80 EXP por inimigo.\n<font color=\"#9AA6B8\">Ambos reaparecem em 4 segundos.</font>",true)
    masteryBox:AddLabel("<b>⚔ Qual mastery vai upar?</b>\nA do equipamento escolhido em <b>Combate</b>.\n<font color=\"#8DDEA1\">✓ Para ao chegar na meta ou na mastery máxima.</font>",true)
    masteryBox:AddLabel("<font color=\"#F0C674\">🔥 Na Flame, M1 conta para Melee; as skills contam para a fruta.</font>",true)
    utilityStatus:AddLabel("<font color=\"#9AA6B8\">Um farm por vez. Ao trocar o modo, o anterior é encerrado primeiro.</font>",true)
    utilityStatus:AddLabel('<font color="#9AA6B8">Ao atingir uma meta, encerra o farm principal. Frutas, baús e bosses de prioridade continuam se estiverem habilitados.</font>',true)

    local names={["Automático"]="Auto",Sword="Sword",Melee="Melee",Fruta="Fruit"}
    local mode=combat:AddDropdown("AutoLevelCombatMode",{
        Values={"Automático","Sword","Melee","Fruta"},Default=1,Multi=false,Text="⚔ Equipamento de combate",
        Callback=function(value)
            local selected=names[value] or "Auto"
            if CONFIG.CombatMode~=selected then Runtime.StatsRevision+=1 end
            CONFIG.CombatMode=selected
            queueSave()
        end,
    })
    combat:AddToggle("AutoLevelHaki",{
        Text="🛡 Ativar Haki aprendido",Default=true,
        Callback=function(value) CONFIG.AutoHaki=value queueSave() end,
    })
    combat:AddToggle("AutoLevelM1",{
        Text="👊 Usar ataque básico (M1)",Default=CONFIG.UseM1,
        Callback=function(value) CONFIG.UseM1=value queueSave() end,
    })
    combat:AddToggle("AutoLevelGather",{
        Text="Agrupar inimigos",Default=CONFIG.Gather.Enabled,
        Callback=function(value) CONFIG.Gather.Enabled=value queueSave() end,
    })
    attributes:AddToggle("AutoLevelStats",{
        Text="Distribuir pontos automaticamente",Default=CONFIG.AutoStats.Enabled,
        Callback=function(value) CONFIG.AutoStats.Enabled=value Runtime.StatsRevision+=1 queueSave() end,
    })
    combat:AddLabel('<font color="#9AA6B8">Essas opções valem para todos os modos de farm.</font>',true)
    automatic:AddLabel('<b><font color="#80C7FF">Quando o combate está em Automático:</font></b>',true)
    automatic:AddLabel('① Começa com <b>Melee</b>.\n② Junta dinheiro e compra a <b>Katana</b>.\n③ Passa a farmar com <b>Sword</b>.',true)
    automatic:AddToggle("AutoLevelBuyKatana",{
        Text="Comprar Katana automaticamente",Default=CONFIG.Sword.AutoBuy,
        Callback=function(value) CONFIG.Sword.AutoBuy=value queueSave() end,
    })
    attributes:AddToggle("AutoLevelSwordReset",{
        Text="↻ Resetar pontos ao trocar combate",Default=CONFIG.ResetStatsOnModeChange,
        Callback=function(value)
            CONFIG.ResetStatsOnModeChange=value
            CONFIG.Sword.ResetUnusedDamageStats=value
            Runtime.StatsRevision+=1
            queueSave()
        end,
    })
    automatic:AddLabel('<font color="#9AA6B8">Com Sword, Melee ou Fruta escolhidos manualmente, não compra a Katana por esta opção.</font>',true)
    attributes:AddLabel('<b><font color="#80C7FF">Distribuição base</font></b>\n🛡 Defesa: <b>50%</b>\n⚔ Dano do combate escolhido: <b>30%</b>\n⚡ Stamina: <b>20%</b>',true)
    attributes:AddLabel('<font color="#F0C674">Com o reset ligado, trocar o combate pode redistribuir seus pontos.</font>',true)
    Runtime.Controls={Farm=farmToggle,CombatMode=mode,FarmMode=farmModeSelector}

    local sessionBox=configTab:AddGroupbox({Side="Right",Name="⏻ Sessão do script"})
    sessionBox:AddLabel('<b><font color="#F0C674">Descarregar script</font></b>\nEncerra os farms e as coletas, libera o movimento e fecha a interface.',true)
    Runtime.Unload=function() Library:Unload() end
    sessionBox:AddButton({Text="⏻ Descarregar script (Unload)",Func=Runtime.Unload})
    sessionBox:AddButton({Text="↻ Reiniciar farm atual",Func=UX.Restart})
    sessionBox:AddLabel('<font color="#9AA6B8">Suas configurações salvas continuam disponíveis na próxima execução.</font>',true)
    local profileGuide=configTab:AddGroupbox({Side="Left",Name="💾 Perfis e configurações"})
    profileGuide:AddToggle("UXAdvancedSettings",{
        Text="Mostrar opções avançadas",Default=false,
        Callback=function(value) UX.Advanced=value UX.VisibilityKey=nil queueSave() end,
    })
    profileGuide:AddLabel('<b>Salvar:</b> guarda as opções em um perfil.\n<b>Carregar:</b> aplica um perfil salvo.\n<b>Autoload:</b> escolhe o perfil para a próxima execução.',true)

    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder("AnimePiece/Users/"..tostring(game.Players.LocalPlayer.UserId).."/AutoLevelUI")
    SaveManager:SetSubFolder(tostring(game.PlaceId))
    SaveManager:BuildConfigSection(configTab)

    local function protectControl(object)
        for _,method in ipairs({"SetValue","SetValues","SetVisible","SetDisabled"}) do
            local original=object[method]
            if type(original)=="function" then
                object[method]=function(self,...)
                    local setIdentity=setthreadidentity or setidentity
                    local getIdentity=getthreadidentity or getidentity
                    local previous=type(getIdentity)=="function" and getIdentity() or nil
                    if type(setIdentity)=="function" then setIdentity(7) end
                    local result=table.pack(pcall(original,self,...))
                    if previous and type(setIdentity)=="function" then setIdentity(previous) end
                    if not result[1] then error(result[2]) end
                    return table.unpack(result,2,result.n)
                end
            end
        end
    end
    for _,object in pairs(Library.Toggles) do protectControl(object) end
    for _,object in pairs(Library.Options) do protectControl(object) end

    pcall(function() SaveManager:LoadAutoloadConfig() end)
    -- Obsidian schedules option callbacks; apply the saved combat mode before starting.
    task.wait(0.5)
    UX.Loading=false
    Scheduler.BackgroundPaused=not farmToggle.Value
    if Library.Options.CombinedBackgroundMode.Value~=farmModeSelector.Value then
        Library.Options.CombinedBackgroundMode:SetValue(farmModeSelector.Value)
    end
    UX.SyncingBosses=true UX.OpportunityBosses:SetValue(Runtime.BossTargets) UX.SyncingBosses=false
    UX.SyncingSummon=true UX.HakiSummon:SetValue(Runtime.AutoSummonBoss) UX.SyncingSummon=false
    UX.Refresh()
    UX.RefreshEditors()
    UX.SyncGoalEditor()
    UX.RefreshExtras()

    Library:OnUnload(function()
        Scheduler.Enabled=false
        for _,connection in ipairs(Runtime.BossNoticeConnections) do connection:Disconnect() end
        Runtime.FruitCancel=true
        Runtime.Alive=false
        Runtime.DesiredEnabled=false
        control.StopAutoLevel=true
        if Runtime.CancelFruitMovement then pcall(Runtime.CancelFruitMovement) end
        if Runtime.CancelFruitStaging then pcall(Runtime.CancelFruitStaging) end
        if Runtime.CleanupCombat then pcall(Runtime.CleanupCombat) end
        if Runtime.CancelFruitRoll then pcall(Runtime.CancelFruitRoll) end
        if control.AnimePieceAutoLevelUI==Runtime then control.AnimePieceAutoLevelUI=nil end
    end)
    task.spawn(function()
        -- Obsidian's text measurement may require Plugin capability in this executor.
        local setUIIdentity=setthreadidentity or setidentity
        if type(setUIIdentity)=="function" then setUIIdentity(7) end
        while Runtime.Alive do
            local ok,err=pcall(function()
                UX.Refresh()
                UX.RefreshEditors()
                UX.SyncGoalEditor()
                UX.RefreshExtras()
                local gameGlobal=getrenv()._G
                local info=gameGlobal and gameGlobal.GetModule and gameGlobal.GetModule("GetInfos")
                if info then
                    local level=info.GetValue("Level")
                    local quest=info.GetValue("QuestId")
                    local progress=info.GetValue("Progress")
                    local maximum=gameGlobal.GameData and gameGlobal.GameData["Balancing Data"].MaxLevel
                    local modeNames={Auto="Auto Level",Money="Dinheiro",Mastery="Mastery",Items="Itens",Haki="Haki",Bosses="Bosses",Unlocks="Desbloqueios",Rerolls="Raça e cor"}
                    local selected=UX.SelectedMode()
                    local guides={
                        Auto="Sobe de nível com as missões disponíveis. Usa o equipamento escolhido em Combate.",
                        Money="Escolha a missão abaixo. Ative uma meta se quiser parar em um valor específico.",
                        Mastery="Escolha os inimigos e a meta. A mastery será a do equipamento escolhido em Combate.",
                        Items="Escolha drops ou compras. Selecione os itens e ajuste quantidades e ordem na fila.",
                        Haki="Escolha a versão desejada. O sistema segue as etapas e busca os materiais permitidos.",
                        Bosses="Escolha bosses do mapa e/ou de invocação. Invocar exige permitir o gasto de materiais.",
                        Unlocks="Escolha o estilo ou movimento. Confira os requisitos antes de iniciar; dinheiro e materiais são consumidos ao aprender.",
                        Rerolls="Selecione os resultados aceitos e os limites. Para ao conseguir qualquer resultado selecionado ou ao atingir o orçamento.",
                    }
                    setStatusText(UX.Guide,'<b>2. Configure o objetivo abaixo.</b>\n<font color="#9AA6B8">'..tostring(guides[selected] or "")..' Trocar o objetivo pausa o farm; ative novamente quando terminar de configurar.</font>')
                    local plan={"<b>Seu plano</b>","🎯 Objetivo: "..(modeNames[selected] or selected),
                        "⚔ Equipamento: "..tostring(Runtime.ActiveEquipment or CONFIG.CombatMode),
                        "📦 Coletas / bosses: "..tostring(UX.ExtrasPreset.Value),
                        "🎲 Roll automático: "..(Runtime.AutoFruitRollEnabled and "ligado" or "desligado")}
                    setStatusText(UX.Summary,table.concat(plan,"\n"))
                    setStatusText(currentModeLabel,'<b>🎯 Modo atual:</b> <font color="#80C7FF">'..(modeNames[Runtime.FarmMode] or "Auto Level")..'</font>')
                    local stats=info.GetStats()
                    local build=stats and stats:FindFirstChild("Build")
                    local unlockRecipe=acquisitionRecipes[Runtime.UnlockName]
                    local unlockOwned=acquisitionOwned(gameGlobal,Runtime.UnlockName)
                    local unlockRows={(unlockOwned and "✓ Já aprendido: " or "○ Aprender: ")..Runtime.UnlockName}
                    if not unlockOwned then
                        if unlockRecipe.Level then table.insert(unlockRows,"⭐ Nível "..unlockRecipe.Level.."+") end
                        table.insert(unlockRows,"💰 $"..unlockRecipe.Price)
                        for _,material in ipairs(unlockRecipe.Materials or {}) do
                            local have=itemCount(gameGlobal,material[1])
                            table.insert(unlockRows,(have>=material[2] and "✓ " or "○ ")..material[1]..": "..have.."/"..material[2])
                        end
                    end
                    setStatusText(UX.UnlockLabel,"<b>🔓 Técnica e requisitos</b>\n"..table.concat(unlockRows,"\n"))
                    setStatusText(UX.UnlockStatus,"<b>📍 Etapa atual</b>\n"..(Runtime.FarmMode=="Unlocks" and (Runtime.LastError or Runtime.ItemState or "Pronto para iniciar") or "Desbloqueios pausados"))
                    local reroll=Runtime.Reroll
                    local race=build and build:FindFirstChild("ActualRace")
                    local racePoints=info.GetValue("RaceRerollPoints","Stats")
                    local desired=orderedSelection(reroll.Kind=="Race" and reroll.Races or reroll.Colors,{})
                    local rerollData=gameGlobal.GameData["Items Data"][reroll.Kind=="Race" and "Race Reroll" or "Haki Color Reroll"]
                    setStatusText(UX.RerollLabel,"<b>🎲 Estado atual</b>\nRaça: "..tostring(race and race.Value or "—")
                        .."\nCor: "..tostring(rerollColorName(gameGlobal) or "Não informada pelo client")
                        .."\n🎯 Aceita: "..(#desired>0 and table.concat(desired,", ") or "Selecione um resultado")
                        .."\n\n<b>🧾 Orçamento da sessão</b>\nTentativas: "..reroll.Attempts.."/"..reroll.MaxAttempts
                        .."\nBananas gastas: "..reroll.SpentBananas.."/"..reroll.MaxBananas
                        .."\n🍌 Inventário: "..itemCount(gameGlobal,"Banana").." | Custo: "..tostring(rerollData and rerollData.BananaPrice or "—")
                        .."\nPontos de raça: "..tostring(racePoints and racePoints.Value or 0)
                        .."\n\n"..tostring(Runtime.FarmMode=="Rerolls" and Runtime.LastError or reroll.Status or "Configure e inicie este objetivo."))
                    local version=build and build:FindFirstChild("ArmamentHaki") and build.ArmamentHaki.Value and build.HakiLevel.Value or 0
                    local requirements=nextHakiRequirements(version)
                    setStatusText(hakiNextRequirements,requirements)
                    hakiNextRequirements:SetVisible(requirements~="")
                    setStatusText(hakiLabel,"<b>🛡 Haki atual:</b> V"..version.."\n"..tostring(Runtime.HakiState or "Aguardando início"))
                    setStatusText(hakiMaterials,"<b>📦 Materiais</b>\n💎 Armament Crystal: "..itemCount(gameGlobal,"Armament Crystal").."\n🔮 Magic Ball: "..itemCount(gameGlobal,"Magic Ball").."\n🍨 Banana Split: "..itemCount(gameGlobal,"Banana Split"))
                    setStatusText(bossLabel,"<b>👹 Status</b>\n"..tostring(Runtime.BossState or "Aguardando boss"))
                    local summonNames=orderedSelection(Runtime.SummonBosses,Runtime.SummonPriority)
                    setStatusText(summonQueueLabel,"<b>🔮 Fila selecionada</b>\n"..(#summonNames>0 and table.concat(summonNames," → ") or "Nenhum boss selecionado")
                        .."\n"..tostring(Runtime.SummonQueueError or Runtime.SummonQueueState or "Ative a invocação para usar seus materiais."))
                    refreshItemOwnership()
                    local buying=Runtime.ItemMethod=="Purchase"
                    local chosen=buying and Runtime.AcquisitionName or Runtime.SelectedDrop
                    local target=Runtime.ItemEnemy
                    local enemyData=gameGlobal.GameData["Enemys Data"][target]
                    local chance=enemyData and enemyData.Drops and enemyData.Drops[chosen]
                    setStatusText(itemLabel,"<b>🎁 Item atual:</b> "..tostring(chosen))
                    local recipe=acquisitionRecipes[Runtime.AcquisitionName]
                    local shopData=gameGlobal.GameData["Items Data"][Runtime.AcquisitionName]
                    local requirements={"$"..tostring(recipe and recipe.Price or shopData and shopData.Price or "—")}
                    if recipe and recipe.MonkeyTrade then
                        requirements={"🍌 "..tostring(shopData and shopData.BananaPrice or "—").." bananas", "Estoque: "..(game:GetService("ReplicatedStorage"):FindFirstChild("MonkeyTraderStock") and "Vendedor disponível" or "Aguardando vendedor")}
                    end
                    for _,material in ipairs(recipe and recipe.Materials or {}) do
                        table.insert(requirements,material[1].." "..itemCount(gameGlobal,material[1]).."/"..material[2])
                    end
                    setStatusText(purchaseCost,"<b>💰 Custo de "..Runtime.AcquisitionName.."</b>\n"..table.concat(requirements,"\n"))
                    setStatusText(sourceLabel,buying and ("<b>🛒 Vendedor:</b> "..(recipe and recipe.NPC or "Loja de itens")) or ("<b>👹 Fonte:</b> "..tostring(target).."\n🎲 Chance por abate: "..tostring(chance or "—").."%"))
                    setStatusText(itemStatusLabel,"<b>📍 Status:</b>\n"..(Runtime.FarmMode=="Items" and (Runtime.LastError or Runtime.ItemState or "Preparando") or "Modo Itens parado"))
                    setStatusText(itemSessionLabel,"<b>🎒 Inventário:</b> "..tostring(itemCount(gameGlobal,chosen))
                        ..(buying and "" or ("/"..itemGoal(gameGlobal,chosen))).." | Abates: "..tostring(Runtime.ItemKills or 0))
                    local queueLines={"<b>🎯 Metas selecionadas</b>"}
                    for _,name in ipairs(orderedSelection(Runtime.SelectedDrops,Runtime.ItemPriority)) do
                        local amount,goal=itemCount(gameGlobal,name),itemGoal(gameGlobal,name)
                        table.insert(queueLines,(amount>=goal and "✓ " or "○ ")..name.." • "..amount.."/"..goal)
                    end
                    table.insert(queueLines,tostring(Runtime.ItemGoalError or Runtime.ItemQueueError or Runtime.ItemQueueState or "Pronto para iniciar"))
                    setStatusText(itemQueueLabel,table.concat(queueLines,"\n"))
                    setStatusText(utilityLabel,"<b>🎯 Objetivo:</b> "..(modeNames[Runtime.FarmMode] or "Auto Level"))
                    local cash=info.GetValue("Money")
                    local goalMoney=cash and cash.Value or 0
                    if Runtime.MoneyGoal.Basis=="Ganho da sessão" then goalMoney=math.max(0,goalMoney-(Runtime.MoneyGoalStart or goalMoney)) end
                    setStatusText(moneyGoalLabel,Runtime.MoneyGoal.Enabled
                        and ("<b>🎯 "..Runtime.MoneyGoal.Basis..":</b> $"..goalMoney.." / $"..Runtime.MoneyGoal.Amount)
                        or '<font color="#9AA6B8">Meta desativada: continua farmando dinheiro.</font>')
                    local elapsed=math.max(1,os.clock()-(Runtime.SessionStart or os.clock()))
                    local gained=cash and Runtime.StartMoney and cash.Value-Runtime.StartMoney or 0
                    setStatusText(moneyLabel,"Saldo da sessão: $"..tostring(gained).."\n⏱ $/min: "..tostring(math.floor(gained*60/elapsed)))
                    local item=Runtime.ActiveEquipment
                    local mastery=item and info.GetMastery(item)
                    local masteryTarget=Runtime.MasteryGoal.Enabled and math.min(Runtime.MasteryGoal.Amount,gameGlobal.GameData["Balancing Data"].MaxMastery) or gameGlobal.GameData["Balancing Data"].MaxMastery
                    setStatusText(masteryGoalLabel,"<b>🎯 Meta de "..tostring(item or "combate selecionado")..":</b> "..tostring(mastery or 0).." / "..masteryTarget)
                    setStatusText(masteryLabel,"<b>⭐ Mastery</b>\n"..tostring(item or "—")..": "..tostring(mastery or "—").." / "..tostring(gameGlobal.GameData["Balancing Data"].MaxMastery))
                    setStatusText(levelLabel,"<b>⭐ Nível:</b> "..tostring(level and level.Value or "—").." / "..tostring(maximum or "—"))
                    local id=quest and quest.Value
                    local data=id and gameGlobal.GameData and gameGlobal.GameData["Quest Data"][id]
                    setStatusText(questLabel,"<b>📜 Missão:</b>\n"..(data and data.QuestNick or "Nenhuma")
                        ..(data and (" ("..tostring(progress and progress.Value or 0).."/"..tostring(data.Progress)..")") or ""))
                    local labels={}
                    for _,entry in ipairs({{"Defense","Defesa"},{"Swords","Sword"},{"FightStyles","Melee"},{"Fruits","Fruta"},{"Stamina","Stamina"}}) do
                        local stat=info.GetValue(entry[1],"Stats")
                        if stat then table.insert(labels,entry[2]..": "..tostring(stat.Value)) end
                    end
                    setStatusText(statsLabel,"<b>📈 Pontos atuais</b>\n"..table.concat(labels," • "))
                end
                setStatusText(equipmentLabel,"<b>⚔ Equipamento:</b> "..tostring(Runtime.ActiveEquipment or "—"))
                if Runtime.ShowFruitStock then
                    setStatusText(stockLabel,Runtime.FruitStockError and ("Não foi possível abrir o stock: "..Runtime.FruitStockError) or fruitStockText())
                end
                local rollOK,roll=pcall(fruitRollState)
                setStatusText(rollLabel,rollOK and ("<b>🎲 Roll:</b> "..roll.Reason.."\n💰 Custo: $"..roll.Price.." | Saldo: $"..roll.Money) or "Disponibilidade do roll ainda não carregou.")
                setStatusText(rollResult,"<b>📍 Último roll</b>\n"..tostring(Runtime.FruitRollStatus or "Nenhum roll solicitado."))
                setStatusText(fruitChestStatus,Runtime.FruitChestStatus or "Selecione um baú e abra uma unidade por vez.")
                setStatusText(fruitStatus,"<b>🍈 Coleta</b>\n"..tostring(Runtime.FruitStatus or "Coleta independente, sem relogar."))
                local automationText=not Scheduler.Enabled and "Automação combinada desligada."
                    or Scheduler.LastError or Scheduler.Current
                    or ("Farm principal: "..tostring(Scheduler.Background).." | Baús coletados: "..tostring(Scheduler.ChestsCollected or 0))
                if Scheduler.Enabled and Scheduler.FinishedBackground==Scheduler.Background then
                    automationText="Farm principal concluído; continuando a observar frutas e baús."
                elseif Scheduler.Enabled and Scheduler.BackgroundPaused and not Scheduler.Current then
                    automationText="Farm principal pausado; observando frutas e baús."
                end
                setStatusText(automationLabel,"<b>🔀 Automação</b>\n"..automationText)
                local deferred={}
                for kind,target in pairs(Runtime.DeferredBosses) do
                    local h=target.Parent and target:FindFirstChildOfClass("Humanoid")
                    if h and h.Health>0 then
                        table.insert(deferred,(kind=="Fruit" and "🍈 Fruta" or "🎲 Roll").." aguarda "..target.Name.." ("..math.ceil(h.Health).." HP)")
                    end
                end
                if #deferred>0 then setStatusText(automationLabel,"<b>⏳ Aguardando terminar o boss</b>\n"..table.concat(deferred,"\n")) end
                local target=Runtime.CombatTarget
                local health=target and target.Parent and target:FindFirstChildOfClass("Humanoid")
                local fighting=Runtime.Pending and health and health.Health>0
                local phase=Runtime.FruitRollBusy and "Roll prioritário"
                    or Runtime.FruitCollecting and "Coletando fruta"
                    or Scheduler.Current or fighting and "Combatendo"
                    or Runtime.Pending and "Buscando objetivo"
                    or Runtime.Completed and "Objetivo concluído" or "Pausado"
                local detail=Runtime.FruitRollBusy and Runtime.FruitRollStatus
                    or Runtime.FruitCollecting and Runtime.FruitStatus
                    or Runtime.FarmMode=="Haki" and Runtime.HakiState
                    or Runtime.FarmMode=="Items" and Runtime.ItemState
                    or Runtime.FarmMode=="Unlocks" and Runtime.ItemState
                    or Runtime.FarmMode=="Rerolls" and Runtime.Reroll.Status
                    or Runtime.FarmMode=="Bosses" and Runtime.BossState
                    or Runtime.WaitingForTool or Runtime.CompletionMessage
                local nextAction=Runtime.FruitRollHold and "Aguardar confirmação da fruta ou cancelar a prioridade"
                    or (Runtime.FruitCollecting or Runtime.FruitRollBusy or Scheduler.Current)
                    and ("Retomar "..tostring(Scheduler.Background))
                    or fighting and "Finalizar o alvo; depois verificar prioridades"
                    or Runtime.Pending and "Aguardar o objetivo ou spawn disponível"
                    or "Ativar o farm ou a automação"
                if Runtime.FruitCollecting then nextAction="Retomar "..tostring(Scheduler.Background) end
                local diagnostics=Runtime.Diagnostics
                setStatusText(activityPhase,"<b>▶ Atividade:</b> "..phase.." | Modo: "..tostring(Runtime.FarmMode))
                setStatusText(activityTarget,"<b>🎯 Alvo:</b> "..(fighting and (target.Name.." | Vida: "..math.ceil(health.Health)) or "—"))
                setStatusText(activityReason,"<b>📍 Detalhe:</b>\n"..tostring(detail or automationText))
                setStatusText(activityNext,"<b>↪ Próximo:</b>\n"..tostring(nextAction))
                setStatusText(activityFailure,"<b><font color=\"#F0C674\">⚠ Última falha:</font></b>\n"..tostring(Runtime.LastError or diagnostics.LastFailure or Scheduler.LastError or "nenhuma"))
                setStatusText(activityRecovery,"<b>🛠 Recuperações:</b> "..diagnostics.Recoveries.."\n"..tostring(diagnostics.LastAction or "Nenhuma necessária"))
                local state=Runtime.Pending and "Farmando" or "Pausado"
                if Runtime.FruitRollBusy then state=Runtime.FruitRollStatus or "Roll prioritário"
                elseif Runtime.FruitCollecting then state=Runtime.FruitStatus or "Coletando fruta"
                elseif Scheduler.Current then state=Scheduler.Current
                elseif Runtime.WaitingForTool then state=Runtime.WaitingForTool
                elseif Runtime.Completed then state=Runtime.CompletionMessage or "Nível máximo atingido"
                elseif Runtime.LastError then state="Interrompido: "..Runtime.LastError
                elseif Runtime.Pending and control.StopAutoLevel then state="Parando..." end
                local stateColor=Runtime.LastError and "#FF8585" or Runtime.Pending and "#8DDEA1" or "#F0C674"
                local safeState=state:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
                setStatusText(stateLabel,'<b>● Status:</b> <font color="'..stateColor..'">'..safeState..'</font>')
            end)
            if ok then Runtime.StatusError=nil else Runtime.StatusError=tostring(err) end
            task.wait(0.5)
        end
    end)
end

stopFarm=function()
    Runtime.StopRequested=true
    control.StopAutoLevel=true
end
startFarm=function()
    if not Runtime.Alive or Runtime.Pending or Runtime.PriorityBusy or Runtime.FruitRollBusy then return end
    if automaticRollDue() then return end
    if Runtime.Completed and Runtime.FarmMode=="Money" then Runtime.MoneyGoalStart=nil end
    local watchingOnly=Runtime.WatchBossesOnly==true
    Runtime.DesiredEnabled=true
    Runtime.Pending=true
    Runtime.StopRequested=false
    Runtime.LastError=nil
    Runtime.Completed=false
    Runtime.CompletionMessage=nil
    Runtime.SessionStart=os.clock()
    local global=getrenv()._G
    local info=global and global.GetModule and global.GetModule("GetInfos")
    local cash=info and info.GetValue("Money")
    Runtime.StartMoney=cash and cash.Value
    if Runtime.FarmMode=="Money" and not Runtime.MoneyGoalStart then Runtime.MoneyGoalStart=Runtime.StartMoney end
    Runtime.WaitingForTool=nil
    task.spawn(function()
        local ok,err=pcall(runAutoLevel)
        if not ok then
            control.AutoLevelRunning=false
            Runtime.LastError=tostring(err)
            warn("AutoLevel | "..tostring(err))
        end
        if Runtime.Completed then Scheduler.FinishedBackground=Runtime.FarmMode end
        Runtime.WatchBossesOnly=false
        Runtime.Pending=false
        local restart=Runtime.Alive and Runtime.DesiredEnabled and Runtime.StopRequested
        Runtime.StopRequested=false
        if restart then
            task.defer(startFarm)
        elseif Runtime.Alive and farmToggle then
            Runtime.DesiredEnabled=false
            -- Encerrar uma tarefa extra não altera a ativação/pausa do objetivo principal.
            if not watchingOnly then farmToggle:SetValue(false) end
        end
    end)
end
Runtime.Start=startFarm
Runtime.Stop=function() if farmToggle then farmToggle:SetValue(false) else stopFarm() end end

local interfaceIdentity=(getthreadidentity or getidentity) and (getthreadidentity or getidentity)()
if setthreadidentity or setidentity then (setthreadidentity or setidentity)(7) end
local ok,err=pcall(createInterface)
if interfaceIdentity and (setthreadidentity or setidentity) then (setthreadidentity or setidentity)(interfaceIdentity) end
if not ok then
    Runtime.Alive=false
    if Library then pcall(function() Library:Unload() end) end
    control.AnimePieceAutoLevelUI=nil
    warn("AutoLevel | Interface não carregou: "..tostring(err))
    return
end

-- Stop an older, headless copy cleanly before handing control to the UI.
if control.AutoLevelRunning then
    control.StopAutoLevel=true
    local deadline=os.clock()+15
    while control.AutoLevelRunning and os.clock()<deadline do task.wait(0.1) end
end
Runtime.Ready=true
Runtime.DesiredEnabled=farmToggle.Value
if control.AutoLevelRunning then
    farmToggle:SetValue(false)
    Runtime.LastError="A execução anterior ainda está parando. Ative o farm quando ela terminar."
elseif farmToggle.Value and not Scheduler.Enabled then
    startFarm()
end
task.spawn(runAutomation)

local function RemoveConnection()
    local RunService = game:GetService("RunService")
    for indice, conexao in ipairs(getconnections(RunService.Heartbeat)) do
        local origem = conexao.Script

        if origem and origem.Name == "Anti Enemy Weld" then
            conexao:Disconnect()
        end
    end
end
task.spawn(RemoveConnection)
