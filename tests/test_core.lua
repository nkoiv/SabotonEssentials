SlashCmdList = {}
local initFrame
function CreateFrame()
    initFrame = {}
    function initFrame:RegisterEvent() end
    function initFrame:UnregisterEvent() end
    function initFrame:SetScript(_, callback) self.callback = callback end
    return initFrame
end
DEFAULT_CHAT_FRAME = { AddMessage = function(...) end }
local addon = {}
assert(loadfile("src/Core.lua"))("SabotonEssentials", addon)
local initialized = false
addon.RegisterModule("extraattack", { OnEnable = function() initialized = true end })
addon.RegisterModule("options", { OnEnable = function() assert(initialized) end })
initFrame.callback(initFrame, "ADDON_LOADED", "SabotonEssentials")
print("Core initialization tests passed")