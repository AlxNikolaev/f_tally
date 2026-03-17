------------------------------------------------------------------------
-- FarmTally - Settings
-- Minimal settings registration (category only, for gear icon access).
------------------------------------------------------------------------
local _, ns = ...

function ns.InitSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Farm Tally")
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end
