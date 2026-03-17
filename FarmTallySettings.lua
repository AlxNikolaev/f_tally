------------------------------------------------------------------------
-- FarmTally - Settings
-- Minimal settings registration (category only, for gear icon access).
------------------------------------------------------------------------
local _, ns = ...

function ns.InitSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Farm Tally")
    if not category then return end
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end
