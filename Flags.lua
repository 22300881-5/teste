local Optimization = {}

local Enabled = false
local OriginalValues = {}

local Flags = {
    FFlagMovePrerender = "True",

    DFIntDebugFRMQualityLevelOverride = "1",

    FIntFRMMinGrassDistance = "0",
    FIntFRMMaxGrassDistance = "0",

    DFFlagTextureQualityOverrideEnabled = "True",
    DFIntTextureQualityOverride = "1",

    FFlagDisablePostFx = "True",

    FIntRenderShadowIntensity = "0",

    DFIntCSGLevelOfDetailSwitchingDistance = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL12 = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL23 = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL34 = "0",
}

local function SetFlag(Name, Value)
    local Success, Current = pcall(function()
        return getfflag(Name)
    end)

    if not Success or Current == nil then
        return false
    end

    if OriginalValues[Name] == nil then
        OriginalValues[Name] = Current
    end

    local Changed, Error = pcall(function()
        setfflag(Name, Value)
    end)

    if not Changed then
        warn("Falha ao alterar FFlag:", Name, Error)
        return false
    end

    return true
end

function Optimization.Enable()
    if Enabled then
        return
    end

    Enabled = true

    for Name, Value in pairs(Flags) do
        SetFlag(Name, Value)
    end
end

function Optimization.Disable()
    if not Enabled then
        return
    end

    Enabled = false

    for Name, OriginalValue in pairs(OriginalValues) do
        pcall(function()
            setfflag(Name, OriginalValue)
        end)
    end

    table.clear(OriginalValues)
end

function Optimization.Toggle()
    if Enabled then
        Optimization.Disable()
    else
        Optimization.Enable()
    end
end

function Optimization.IsEnabled()
    return Enabled
end

return Optimization
