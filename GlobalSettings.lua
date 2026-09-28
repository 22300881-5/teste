local GlobalSettings = {}

local Settings = {
	Default_FPSCap = 20,
	Default_FPSCap_Values = {10, 20, 30, 40, 50, 60},
	Min_FPSCap = 5,
	Max_FPSCap = 100,
}

function GlobalSettings.Create(tab, Library, RunService, FastMode, AntiAfkResult)
	-- tab: Tab
	-- Library: biblioteca da UI
	-- RunService: RunService
	-- FastMode: módulo FastMode
	-- AntiAfkResult: boolean

	local HubBox = tab:AddGroupbox({
		Side = "Left",
		Name = "Hub",
	})

	HubBox:AddButton({
		Text = "Unload Script",

		Func = function()
			Library:Unload()
		end,
	})

	local FPSBox = tab:AddGroupbox({
		Side = "Left",
		Name = "🚀 FPS",
	})

	FPSBox:AddDropdown("FPSCapDropdown", {
		Values = Settings.Default_FPSCap_Values,
		Default = Settings.Default_FPSCap,
		Multi = false,
		Text = "Cap Preset",
	})

	Library.Options.FPSCapDropdown:OnChanged(function(Value)
		Settings.Default_FPSCap = Value

		if Library.Options.FPSCapDropdown.Menu then
			Library.Options.FPSCapDropdown.Menu:Close()
		end
	end)

	FPSBox:AddSlider("FPSCapSlider", {
		Text = "Custom Cap",
		Default = Settings.Default_FPSCap,
		Min = Settings.Min_FPSCap,
		Max = Settings.Max_FPSCap,
		Rounding = 0,
	})

	Library.Options.FPSCapSlider:OnChanged(function(Value)
		Settings.Default_FPSCap = Value
	end)

	setfpscap(Settings.Default_FPSCap)

	FPSBox:AddButton({
		Text = "Set Cap",

		Func = function()
			setfpscap(Settings.Default_FPSCap)
		end,
	})

	local FPSLabel = FPSBox:AddLabel(
		'<font color="rgb(73, 230, 133)">FPS Cap: </font>0',
		false
	)

	local AutoSettingsBox = tab:AddGroupbox({
		Side = "Right",
		Name = "Auto Settings",
	})

	AutoSettingsBox:AddLabel(
		'<font color="rgb(73, 230, 133)">Roblox Anti AFK: </font>: '
			.. tostring(AntiAfkResult),
		true
	)

	local OptimizationSettingsBox = tab:AddGroupbox({
		Side = "Right",
		Name = "Otimization Settings",
	})

	local PerformanceModeToggle = OptimizationSettingsBox:AddToggle(
		"PerformanceMode",
		{
			Text = "Extreme Performance",
			Default = false,
		}
	)

	PerformanceModeToggle:OnChanged(function(Value)
		if Value then
			FastMode.Enable()
		else
			FastMode.Disable()
		end
	end)

	local RenderToggle = OptimizationSettingsBox:AddToggle(
		"RenderToggle",
		{
			Text = "Disable 3DRendering",
			Default = false,
		}
	)

	RenderToggle:OnChanged(function(Value)
		RunService:Set3dRenderingEnabled(not Value)
	end)

	return {
		FPSLabel = FPSLabel,
		Settings = Settings,
	}
end

return GlobalSettings
