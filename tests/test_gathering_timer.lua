local now = 0
local frames, timers, scheduled, sounds, messages = {}, {}, {}, {}, {}
local loot = { 2770, 10620 }
local module

UIParent = {}
function GetTime() return now end
function issecretvalue() return false end
function GetNumLootItems() return #loot end
function GetLootSourceInfo() return "GameObject-1" end
function GetLootSlotLink(slot) return "item:" .. loot[slot] end
function GetLootSlotInfo(...) return nil, nil end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
function PlaySoundFile(path, ...) sounds[#sounds + 1] = path return true end
function UIFrameFadeOut(...) end
C_Timer = {
    NewTicker = function(_, callback) timers[#timers + 1] = callback end,
    After = function(_, callback) scheduled[#scheduled + 1] = callback end,
}

local methods = {}
local function noop() end
for _, name in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameLevel", "SetFrameStrata", "SetTexture", "SetBlendMode", "SetVertexColor", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetHeight", "SetWidth", "SetAlpha", "SetStatusBarColor", "SetText", "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForDrag", "RegisterEvent", "SetDrawLayer" }) do
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
assert(loadfile("src/Support/TimerBars.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Modules/GatheringTimer.lua"))("SabotonEssentials", addon)
module:OnEnable()
local events = frames[#frames]
local function fire(event, message) events.scripts.OnEvent(events, event, message) end
local options = {}
for _, spec in ipairs(module:GetOptionsSchema().options) do options[spec.key] = spec end
assert(options.enabled.default == false and options.enabled.get() == false)
options.locked.set(false)
assert(module.frame.shown and module.frame.minBar.shown, "unlock shows idle preview")
module:HandleCommand("clear")
assert(module.frame.shown, "clearing timers keeps the unlocked preview")
options.locked.set(true)
assert(not module.frame.shown, "locking hides the idle preview")

module:HandleCommand("min 10")
module:HandleCommand("max 20")
fire("LOOT_READY")
module:HandleCommand("status")
assert(messages[#messages - 1]:find("Active: none", 1, true))
options.enabled.set(true)
fire("LOOT_READY")
module:HandleCommand("status")
assert(messages[#messages - 1]:find("Thorium Ore", 1, true))
assert(messages[#messages - 1]:find("min 10s / max 20s", 1, true))

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
fire("LOOT_READY")
module:HandleCommand("status")
assert(messages[#messages - 1]:find("min 300s / max 20s", 1, true))
module:HandleCommand("test")
module:HandleCommand("status")
assert(messages[#messages - 1]:find("min 5s / max 10s", 1, true))

-- Celebration tracking is independent of timer tracking and sees every loot slot.
assert(options.celebrate_12363.get() and options.celebrate_248819.get() and options.celebrate_13468.get())
assert(not options.celebrate_10620.get())
local soundCount = #sounds
fire("LOOT_CLOSED")
loot = { 10620, 12363, 248819 }
fire("LOOT_READY")
fire("LOOT_OPENED")
assert(#sounds == soundCount, "opening a loot window alone must not celebrate")
local arcane = "|cffaabbcc|Hitem:12363:0|h[Arcane Crystal]|h|r"
local fel = "|Hitem:248819:0|h[Fel Crystal]|h"
fire("CHAT_MSG_LOOT", "Other player receives loot: " .. arcane .. ".")
assert(#sounds == soundCount, "another player's loot must not celebrate")
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 1 and sounds[#sounds]:find("kaching.mp3", 1, true))
local animation = frames[#frames]
assert(animation.shown and animation.scripts.OnUpdate and #animation.particles == 16)
animation.scripts.OnUpdate(animation, 1.8)
assert(not animation.shown, "sparkles expire")
fire("LOOT_OPENED")
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 1, "duplicate events in one window must not celebrate twice")
options.celebration_sound_248819.set("squeak")
fire("CHAT_MSG_LOOT", "You receive loot: " .. fel .. "x2.")
assert(#sounds == soundCount + 2 and sounds[#sounds]:find("squeak.mp3", 1, true))
fire("LOOT_CLOSED")
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "You receive item: " .. arcane .. ".")
assert(#sounds == soundCount + 3, "a later gather can celebrate again")
options.celebrate_12363.set(false)
fire("LOOT_CLOSED")
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 3, "disabled item does not celebrate")
options.celebrate_12363.set(true)
fire("LOOT_CLOSED")
function GetLootSourceInfo() return "Creature-1" end
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 3, "creature loot must not celebrate")
fire("LOOT_CLOSED")
function GetLootSourceInfo() return nil end
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 3 and messages[#messages]:find("Loot source is unavailable", 1, true))
function GetLootSourceInfo() return "GameObject-1" end
fire("LOOT_CLOSED")
fire("LOOT_READY")
fire("LOOT_CLOSED")
now = now + 1
fire("CHAT_MSG_LOOT", "You receive loot: " .. arcane .. ".")
assert(#sounds == soundCount + 4, "late loot confirmation after closing is accepted")
now = now + 2
fire("CHAT_MSG_LOOT", "You receive loot: " .. fel .. ".")
assert(#sounds == soundCount + 4, "stale loot windows cannot trigger later rewards")
LOOT_ITEM_SELF = "Erhalten: %1$s."
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "Erhalten: " .. arcane .. ".")
assert(#sounds == soundCount + 5, "localized positional formats are supported")
module:HandleCommand("celebrationsound Fel Crystal huagh")
assert(options.celebration_sound_248819.get() == "huagh")
module:HandleCommand("celebrate Fel Crystal")
assert(not options.celebrate_248819.get())
module:HandleCommand("testcelebration Fel Crystal")
assert(#sounds == soundCount + 6 and sounds[#sounds]:find("HumanMaleAggroA.ogg", 1, true))
module:HandleCommand("celebrate Mystic Herb")
module:HandleCommand("celebrationsound Mystic Herb none")
loot = { 99999 }
fire("LOOT_CLOSED")
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "Erhalten: |Hitem:99999:0|h[Mystic Herb]|h.")
assert(#sounds == soundCount + 6 and animation.shown,
    "custom name-only items can celebrate silently")
animation.scripts.OnUpdate(animation, 2)
options.enabled.set(false)
fire("LOOT_CLOSED")
fire("LOOT_READY")
fire("CHAT_MSG_LOOT", "Erhalten: " .. arcane .. ".")
assert(not animation.shown and #sounds == soundCount + 6, "disabled module does not celebrate")
print("Gathering Timer tests passed")