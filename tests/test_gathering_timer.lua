local now = 0
local frames, timers, scheduled, sounds, messages = {}, {}, {}, {}, {}
local loot = { 2770, 12363 }
local module

UIParent = {}
function GetTime() return now end
function issecretvalue() return false end
function GetNumLootItems() return #loot end
function GetLootSourceInfo() return "GameObject-1" end
function GetLootSlotLink(slot) return "item:" .. loot[slot] end
function GetLootSlotInfo(...) return nil, nil end
function PlaySoundFile(path, ...) sounds[#sounds + 1] = path return true end
function UIFrameFadeOut(...) end
C_Timer = {
    NewTicker = function(_, callback) timers[#timers + 1] = callback end,
    After = function(_, callback) scheduled[#scheduled + 1] = callback end,
}

local methods = {}
local function noop() end
for _, name in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameLevel", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetHeight", "SetWidth", "SetAlpha", "SetStatusBarColor", "SetText", "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForDrag", "RegisterEvent", "SetDrawLayer" }) do
    methods[name] = noop
end
function methods:GetFrameLevel() return 1 end
function methods:GetStatusBarTexture() return self end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:CreateTexture() return setmetatable({ scripts = {} }, { __index = methods }) end
function methods:CreateFontString() return setmetatable({ scripts = {} }, { __index = methods }) end
function CreateFrame()
    local frame = setmetatable({ scripts = {} }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end

local addon = {
    Print = function(message) messages[#messages + 1] = message end,
    RegisterModule = function(_, value) module = value end,
}
assert(loadfile("src/Modules/GatheringTimer.lua"))("SabotonEssentials", addon)
module:OnEnable()
module:HandleCommand("min 10")
module:HandleCommand("max 20")
frames[#frames].scripts.OnEvent()
module:HandleCommand("status")
assert(messages[#messages - 1]:find("Arcane Crystal", 1, true))
assert(messages[#messages - 1]:find("min 10s / max 20s", 1, true))

local options = {}
for _, spec in ipairs(module:GetOptionsSchema().options) do options[spec.key] = spec end
options.minDuration.set(0)
assert(not module.frame.minBar.shown and not module.frame.minBar.title.shown and module.frame.maxBar.shown and module.frame.maxBar.title.shown)
now = 10
timers[1]()
assert(#sounds == 0)
now = 20
timers[1]()
assert(#sounds == 1 and module.frame.maxBar.shown and module.frame.maxBar.flash.shown)
timers[1]()
assert(#scheduled == 1)
options.minDuration.set(30)
scheduled[1]()
assert(module.frame.minBar.shown)
now = 30
timers[1]()
assert(#sounds == 2 and module.frame.minBar.shown)
now = 32
scheduled[2]()
assert(not module.frame.shown)
module:HandleCommand("add Mystic Herb herb 60 120")
module:HandleCommand("list")
assert(messages[#messages]:find("Mystic Herb", 1, true))
module:HandleCommand("min 300")
loot = { 0 }
function GetLootSlotInfo(...) return nil, "Mystic Herb" end
frames[#frames].scripts.OnEvent()
module:HandleCommand("status")
assert(messages[#messages - 1]:find("min 300s / max 20s", 1, true))
module:HandleCommand("test")
module:HandleCommand("status")
assert(messages[#messages - 1]:find("min 5s / max 10s", 1, true))
print("Gathering Timer tests passed")