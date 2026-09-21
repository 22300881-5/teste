local Performance = {}

local Enabled = false
local OriginalValues = {}

local Flags = {
    FFlagMovePrerender = "True",

    DFIntDebugFRMQualityLevelOverride = "1",

    FFlagDisablePostFx = "True",

    FIntRenderShadowIntensity = "0",

    DFIntCullFactorPixelThresholdShadowMapHighQuality = "2147483647",
    DFIntCullFactorPixelThresholdShadowMapLowQuality = "2147483647",

    DFIntCSGLevelOfDetailSwitchingDistance = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL12 = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL23 = "0",
    DFIntCSGLevelOfDetailSwitchingDistanceL34 = "0",

    FIntRenderLocalLightUpdatesMax = "8",
    FIntRenderLocalLightUpdatesMin = "6",
    FIntRenderLocalLightFadeInMs = "0",

    FIntTerrainArraySliceSize = "4",

    DFFlagTextureQualityOverrideEnabled = "True",
    DFIntTextureQualityOverride = "0",

    DFIntPerformanceControlTextureQualityBestUtility = "-1",

    FIntFRMMinGrassDistance = "0",
    FIntFRMMaxGrassDistance = "0",
    FIntRenderGrassDetailStrands = "0",

    DFIntMaxActiveAnimationTracks = "0",

    DFIntTextureCompositorActiveJobs = "0",

    FIntDebugTextureManagerSkipMips = "8",

    DFFlagDebugPauseVoxelizer = "True",

    FFlagFastGPULightCulling3 = "True",
    FFlagNewLightAttenuation = "True",
}

local function GetFlag(Name)
    local Success, Value = pcall(function()
        return getfflag(Name)
    end)

    if not Success then
        return nil
    end

    return Value
end

local function SetFlag(Name, Value)
    local Current = GetFlag(Name)

    if Current == nil then
        return false
    end

    if OriginalValues[Name] == nil then
        OriginalValues[Name] = Current
    end

    local Success = pcall(function()
        setfflag(Name, Value)
    end)

    return Success
end

function Performance.Enable()
    if Enabled then
        return
    end

    Enabled = true

    for Name, Value in pairs(Flags) do
        SetFlag(Name, Value)
    end
end

function Performance.Disable()
    if not Enabled then
        return
    end

    Enabled = false

    for Name, Value in pairs(OriginalValues) do
        pcall(function()
            setfflag(Name, Value)
        end)
    end

    table.clear(OriginalValues)
end

function Performance.Toggle()
    if Enabled then
        Performance.Disable()
    else
        Performance.Enable()
    end
end

function Performance.IsEnabled()
    return Enabled
end

function Performance.GetAvailableFlags()
    local Available = {}

    for Name in pairs(Flags) do
        if GetFlag(Name) ~= nil then
            Available[Name] = true
        end
    end

    return Available
end

return Performance
