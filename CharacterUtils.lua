local CharacterUtils = {}

function CharacterUtils.GetCharacter(player)
	-- player: Player
	return player and player.Character
end

function CharacterUtils.GetCharacterOrWait(player, timeout)
	-- player: Player
	-- timeout: number? | tempo máximo de espera

	if not player then
		return nil
	end

	if player.Character then
		return player.Character
	end

	if timeout then
		return player.CharacterAdded:Wait(timeout)
	end

	return player.CharacterAdded:Wait()
end

function CharacterUtils.IsCharacter(character)
	-- character: Model
	return character ~= nil
		and character:IsA("Model")
		and character:FindFirstChildWhichIsA("Humanoid") ~= nil
end

function CharacterUtils.GetHumanoid(character)
	-- character: Model
	if not character then
		return nil
	end

	return character:FindFirstChildWhichIsA("Humanoid")
end

function CharacterUtils.GetHumanoidRootPart(character)
	-- character: Model
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

function CharacterUtils.IsAlive(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid ~= nil
		and humanoid.Health > 0
		and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

function CharacterUtils.IsDead(character)
	-- character: Model
	return not CharacterUtils.IsAlive(character)
end

function CharacterUtils.GetHealth(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid and humanoid.Health or 0
end

function CharacterUtils.GetMaxHealth(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid and humanoid.MaxHealth or 0
end

function CharacterUtils.GetHealthPercent(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid or humanoid.MaxHealth <= 0 then
		return 0
	end

	return humanoid.Health / humanoid.MaxHealth
end

function CharacterUtils.GetPosition(character)
	-- character: Model
	local rootPart = CharacterUtils.GetHumanoidRootPart(character)

	return rootPart and rootPart.Position or nil
end

function CharacterUtils.GetCFrame(character)
	-- character: Model
	local rootPart = CharacterUtils.GetHumanoidRootPart(character)

	return rootPart and rootPart.CFrame or nil
end

function CharacterUtils.SetCFrame(character, cframe)
	-- character: Model
	-- cframe: CFrame
	local rootPart = CharacterUtils.GetHumanoidRootPart(character)

	if not rootPart or not cframe then
		return false
	end

	rootPart.CFrame = cframe

	return true
end

function CharacterUtils.GetDistance(character1, character2)
	-- character1: Model
	-- character2: Model
	local position1 = CharacterUtils.GetPosition(character1)
	local position2 = CharacterUtils.GetPosition(character2)

	if not position1 or not position2 then
		return nil
	end

	return (position1 - position2).Magnitude
end

function CharacterUtils.GetWalkSpeed(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid and humanoid.WalkSpeed or nil
end

function CharacterUtils.SetWalkSpeed(character, speed)
	-- character: Model
	-- speed: number
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid then
		return false
	end

	humanoid.WalkSpeed = speed

	return true
end

function CharacterUtils.GetJumpPower(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid and humanoid.JumpPower or nil
end

function CharacterUtils.SetJumpPower(character, power)
	-- character: Model
	-- power: number
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid then
		return false
	end

	humanoid.JumpPower = power

	return true
end

function CharacterUtils.GetState(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid and humanoid:GetState() or nil
end

function CharacterUtils.IsGrounded(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid then
		return false
	end

	local state = humanoid:GetState()

	return state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
		or state == Enum.HumanoidStateType.Landed
end

function CharacterUtils.IsInAir(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid then
		return false
	end

	local state = humanoid:GetState()

	return state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.FallingDown
end

function CharacterUtils.IsSwimming(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	return humanoid ~= nil
		and humanoid:GetState() == Enum.HumanoidStateType.Swimming
end

function CharacterUtils.GetBodyPart(character, name)
	-- character: Model
	-- name: string | nome da parte do corpo
	if not character or not name then
		return nil
	end

	return character:FindFirstChild(name)
end

function CharacterUtils.GetHead(character)
	-- character: Model
	return CharacterUtils.GetBodyPart(character, "Head")
end

function CharacterUtils.GetTorso(character)
	-- character: Model
	return CharacterUtils.GetBodyPart(character, "UpperTorso")
		or CharacterUtils.GetBodyPart(character, "Torso")
end

function CharacterUtils.GetRootPart(character)
	-- character: Model
	return CharacterUtils.GetHumanoidRootPart(character)
end

function CharacterUtils.GetEquippedTool(character)
	-- character: Model
	if not character then
		return nil
	end

	for _, object in ipairs(character:GetChildren()) do
		if object:IsA("Tool") then
			return object
		end
	end

	return nil
end

function CharacterUtils.IsToolEquipped(character, toolName)
	-- character: Model
	-- toolName: string? | nome da Tool
	local tool = CharacterUtils.GetEquippedTool(character)

	if not tool then
		return false
	end

	if not toolName then
		return true
	end

	return tool.Name == toolName
end

function CharacterUtils.EquipTool(character, tool)
	-- character: Model
	-- tool: Tool
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid or not tool or not tool:IsA("Tool") then
		return false
	end

	humanoid:EquipTool(tool)

	return true
end

function CharacterUtils.UnequipTools(character)
	-- character: Model
	local humanoid = CharacterUtils.GetHumanoid(character)

	if not humanoid then
		return false
	end

	humanoid:UnequipTools()

	return true
end

function CharacterUtils.Exists(character)
	-- character: Model
	return character ~= nil and character.Parent ~= nil
end

function CharacterUtils.IsValid(character)
	-- character: Model
	return CharacterUtils.Exists(character)
		and CharacterUtils.GetHumanoid(character) ~= nil
		and CharacterUtils.GetHumanoidRootPart(character) ~= nil
end

return CharacterUtils
