local InstanceUtils = {}

function InstanceUtils.GetPrimaryPart(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

function InstanceUtils.FindBasePart(instance)
	if not instance then
		return nil
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

function InstanceUtils.GetCFrame(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return nil
end

function InstanceUtils.GetModelCFrame(model)
	if not model then
		return nil
	end

	if not model:IsA("Model") then
		return nil
	end

	return model:GetPivot()
end

function InstanceUtils.GetPosition(instance)
	local cframe = InstanceUtils.GetCFrame(instance)

	return cframe and cframe.Position or nil
end

function InstanceUtils.GetSize(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.Size
	end

	if instance:IsA("Model") then
		local _, size = instance:GetBoundingBox()
		return size
	end

	return nil
end

function InstanceUtils.GetBoundingBox(instance)
	if not instance then
		return nil, nil
	end

	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return nil, nil
end

function InstanceUtils.GetModelParts(model)
	if not model then
		return {}
	end

	local parts = {}

	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			table.insert(parts, object)
		end
	end

	return parts
end

function InstanceUtils.FindHumanoid(instance)
	if not instance then
		return nil
	end

	return instance:FindFirstChildWhichIsA("Humanoid", true)
end

function InstanceUtils.FindChild(instance, name)
	if not instance or not name then
		return nil
	end

	return instance:FindFirstChild(name)
end

function InstanceUtils.FindDescendant(instance, name)
	if not instance or not name then
		return nil
	end

	return instance:FindFirstChild(name, true)
end

function InstanceUtils.HasChild(instance, name)
	if not instance or not name then
		return false
	end

	return instance:FindFirstChild(name) ~= nil
end

function InstanceUtils.GetChildrenOfClass(instance, className)
	if not instance or not className then
		return {}
	end

	local result = {}

	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA(className) then
			table.insert(result, child)
		end
	end

	return result
end

function InstanceUtils.GetDescendantsOfClass(instance, className)
	if not instance or not className then
		return {}
	end

	local result = {}

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA(className) then
			table.insert(result, descendant)
		end
	end

	return result
end

function InstanceUtils.IsModel(instance)
	return instance ~= nil and instance:IsA("Model")
end

function InstanceUtils.IsBasePart(instance)
	return instance ~= nil and instance:IsA("BasePart")
end

function InstanceUtils.IsTool(instance)
	return instance ~= nil and instance:IsA("Tool")
end

function InstanceUtils.HasPrimaryPart(instance)
	return instance ~= nil
		and instance:IsA("Model")
		and instance.PrimaryPart ~= nil
end

function InstanceUtils.IsDescendantOf(instance, ancestor)
	return instance ~= nil
		and ancestor ~= nil
		and instance:IsDescendantOf(ancestor)
end

function InstanceUtils.Exists(instance)
	return instance ~= nil and instance.Parent ~= nil
end

function InstanceUtils.GetTool(container, toolName)
	if not container or not toolName then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child.Name == toolName then
			return child
		end
	end

	return nil
end

function InstanceUtils.FindTool(container, toolName)
	if not container or not toolName then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and string.find(child.Name, toolName, 1, true) then
			return child
		end
	end

	return nil
end

function InstanceUtils.GetAttribute(instance, attribute, default)
	if not instance or not attribute then
		return default
	end

	local value = instance:GetAttribute(attribute)

	if value == nil then
		return default
	end

	return value
end

function InstanceUtils.SetAttribute(instance, attribute, value)
	if not instance or not attribute then
		return false
	end

	instance:SetAttribute(attribute, value)

	return true
end

function InstanceUtils.SafeDestroy(instance)
	if not instance or not instance.Parent then
		return false
	end

	instance:Destroy()

	return true
end

return InstanceUtils
