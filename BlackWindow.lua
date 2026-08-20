local BlackWindow = {}

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Enabled = false
local DisabledObjects = {}
local ProcessedObjects = {}
local EffectsConnection

local function DisableVisual(obj)
    if not obj or not obj.Parent or ProcessedObjects[obj] then
        return
    end

    ProcessedObjects[obj] = true

    if obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("PointLight")
        or obj:IsA("SpotLight")
        or obj:IsA("SurfaceLight")
        or obj:IsA("Fire")
        or obj:IsA("Smoke")
        or obj:IsA("Sparkles") then

        DisabledObjects[obj] = {
            Type = "Enabled",
            Value = obj.Enabled
        }

        obj.Enabled = false

    elseif obj:IsA("BloomEffect")
        or obj:IsA("BlurEffect")
        or obj:IsA("ColorCorrectionEffect")
        or obj:IsA("DepthOfFieldEffect")
        or obj:IsA("SunRaysEffect") then

        DisabledObjects[obj] = {
            Type = "Enabled",
            Value = obj.Enabled
        }

        obj.Enabled = false

    elseif obj:IsA("Decal") or obj:IsA("Texture") then

        DisabledObjects[obj] = {
            Type = "Transparency",
            Value = obj.Transparency
        }

        obj.Transparency = 1
    end
end

local function DisableMapVisuals()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not DisabledObjects[obj] then
            DisabledObjects[obj] = {
                Type = "BasePart",
                Material = obj.Material,
                CastShadow = obj.CastShadow,
                Reflectance = obj.Reflectance
            }

            obj.Material = Enum.Material.SmoothPlastic
            obj.CastShadow = false
            obj.Reflectance = 0
        end
    end
end

local function DisableLighting()
    DisabledObjects.__Lighting = {
        GlobalShadows = Lighting.GlobalShadows,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
    }

    Lighting.GlobalShadows = false
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0

    for _, obj in ipairs(Lighting:GetChildren()) do
        DisableVisual(obj)
    end
end

local function EnableEffectsCleaner()
    local EffectsFolder = Workspace:FindFirstChild("Effects")

    if not EffectsFolder then
        return
    end

    for _, obj in ipairs(EffectsFolder:GetDescendants()) do
        DisableVisual(obj)
    end

    if EffectsConnection then
        EffectsConnection:Disconnect()
    end

    EffectsConnection = EffectsFolder.DescendantAdded:Connect(function(obj)
        if Enabled then
            DisableVisual(obj)
        end
    end)
end

local function DisableEffectsCleaner()
    if EffectsConnection then
        EffectsConnection:Disconnect()
        EffectsConnection = nil
    end
end

function BlackWindow.Enable()
    if Enabled then
        return
    end

    Enabled = true

    DisableMapVisuals()
    DisableLighting()

    for _, obj in ipairs(Workspace:GetDescendants()) do
        DisableVisual(obj)
    end

    EnableEffectsCleaner()
end

function BlackWindow.Disable()
    if not Enabled then
        return
    end

    Enabled = false

    DisableEffectsCleaner()

    for obj, data in pairs(DisabledObjects) do
        if obj ~= "__Lighting" and obj and obj.Parent then
            if data.Type == "Enabled" then
                obj.Enabled = data.Value

            elseif data.Type == "BasePart" then
                obj.Material = data.Material
                obj.CastShadow = data.CastShadow
                obj.Reflectance = data.Reflectance

            elseif data.Type == "Transparency" then
                obj.Transparency = data.Value
            end
        end
    end

    if DisabledObjects.__Lighting then
        local data = DisabledObjects.__Lighting

        Lighting.GlobalShadows = data.GlobalShadows
        Lighting.EnvironmentDiffuseScale = data.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = data.EnvironmentSpecularScale
    end

    table.clear(DisabledObjects)
    table.clear(ProcessedObjects)
end

function BlackWindow.IsEnabled()
    return Enabled
end

return BlackWindow
