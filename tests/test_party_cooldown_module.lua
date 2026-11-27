local now, wall, combat, blocked = 100, 10000, false, false
local units = {
    player = { guid = "Player-me", name = "Oak", second = "Tree", class = "DRUID", level = 60 },
    party1 = { guid = "Player-peer", name = "Leaf", second = "Green", class = "DRUID", level = 60 },
}
local known, cooldowns, messages, sends, tickers, frames = { [29166] = true, [20484] = true }, {}, {}, {}, {}, {}
local secretValue = setmetatable({}, { __index = function() error("secret field accessed") end })
function issecretvalue(value) return value == secretValue end
function issecrettable(value) return value == secretValue end
local function noop() end
local methods = {}
for _, name in ipairs({ "SetSize", "SetHeight", "SetWidth", "ClearAllPoints", "SetAllPoints", "SetFrameLevel",
    "SetMinMaxValues", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetDrawLayer",
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StopMovingOrSizing", "SetFrameStrata",
    "SetBackdrop", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture" }) do methods[name] = noop end
function methods:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
function methods:GetCenter() return 500 + (self.x or 0), 400 + (self.y or 0) end
function methods:GetFrameLevel() return 1 end
function methods:GetStatusBarTexture() return self end
function methods:SetText(text) self.text = text if self.fontOwner then self.fontOwner.label = text end end
function methods:SetStatusBarColor(...) self.color = { ... } end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:SetScript(key, callback) self.scripts[key] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:IsShown() return self.shown end
function methods:StartMoving() self.moving = true end
function methods:CreateTexture() return setmetatable({ scripts = {}, events = {} }, { __index = methods }) end
function methods:CreateFontString()
    return setmetatable({ scripts = {}, events = {}, fontOwner = self }, { __index = methods })
end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {} }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end
function GetTime() return now end
function time() return wall end
function InCombatLockdown() return combat end
function IsInRaid() return false end
function IsInGroup() return units.party1 ~= nil end
function GetNumSubgroupMembers() return units.party2 and 2 or units.party1 and 1 or 0 end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitName(unit) local u = units[unit] if u then return u.name, u.second end end
function UnitClass(unit) local u = units[unit] if u then return u.class, u.class end end
function UnitLevel(unit) return units[unit] and units[unit].level end
function UnitIsConnected(unit) return units[unit] and units[unit].online ~= false end
function UnitIsDeadOrGhost(unit) return units[unit] and units[unit].dead == true end
function GetNormalizedRealmName() return "TestRealm" end
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
local names = { [29166] = "Innervate", [20484] = "Rebirth", [633] = "Lay on Hands", [20739] = "Rebirth" }
C_Spell = {
    GetSpellName = function(id) return names[id] end,
    GetSpellInfo = function(name)
        for id, value in pairs(names) do if name == value then return { spellID = id } end end
    end,
    GetSpellCooldown = function(id)
        return cooldowns[id] or { startTime = 0, duration = 0, isEnabled = true, isOnGCD = false, modRate = 1 }
    end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    InChatMessagingLockdown = function() return blocked end,
    SendAddonMessage = function(prefix, packet, channel) sends[#sends + 1] = { prefix, packet, channel } return 0 end,
}
C_Timer = { NewTicker = function(_, callback) tickers[#tickers + 1] = callback return { Cancel = noop } end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
UIParent = CreateFrame("Frame")
local addon = {}
for _, file in ipairs({ "src/Core.lua", "src/Support/Spells.lua", "src/Support/TimerBars.lua",
    "src/Support/PartyCooldowns.lua", "src/Support/CooldownSync.lua", "src/Modules/PartyCooldownTracker.lua",
    "src/Options.lua" }) do
    assert(loadfile(file))("SabotonEssentials", addon)
end
local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end
local function tick() for _, callback in ipairs(tickers) do callback() end end
local function slash(message) SlashCmdList.SABOTON("partycooldowns " .. message) end
local function said(fragment)
    for _, message in ipairs(messages) do if message:find(fragment, 1, true) then return true end end
    return false
end
local module = addon.modules.partycooldowns
fire("ADDON_LOADED", "SabotonEssentials")
assert(not module.frame.shown)
slash("test")
assert(module.frame.shown)
tick()
assert(#sends == 0, "disabled preview must never send network messages")
slash("test")
slash("enable")
assert(module.frame.shown and SabotonEssentialsDB.modules.partycooldowns.enabled)
tick()
assert(#sends == 1 and sends[1][2] == "R|1")
now = 102 tick()
assert(#sends == 2 and sends[2][2]:find("29166:R:0:0", 1, true))
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:R:0:0,20484:U:0:0", "PARTY", "Leaf Green")
slash("status")
assert(said("Leaf-Green - Innervate: ready"))
fire("PLAYER_REGEN_DISABLED")
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: unknown"), "combat invalidates an earlier remote-ready claim")
now = 104
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:C:700:900", "PARTY", "Leaf-Green-TestRealm")
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: cooldown 11:40"))
now = 106
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:U:0:0", "PARTY", "Leaf Green")
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: unknown"))
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", secretValue)
fire("UNIT_SPELLCAST_SUCCEEDED", secretValue, "cast", 29166)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 29166)
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: estimated 6:00") and said("hidden cast IDs=1"))

fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 29166)
tick()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: estimated"), "a lagging ready API result must not erase a fresh cast")
cooldowns[29166] = { startTime = now, duration = 360, isEnabled = true, isOnGCD = false, modRate = 2 }
now = 107 tick()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: cooldown 2:59"), "cooldown rate must be respected")
cooldowns[29166] = secretValue
now = 108 tick()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: cooldown 2:58"), "restricted reads must preserve an active timer")
cooldowns[29166] = { startTime = 0, duration = 0, isEnabled = secretValue, isOnGCD = false }
now = 109 tick()
messages = {} slash("status")
assert(not said("Oak-Tree - Innervate: ready"), "a secret enable flag must not be treated as true")
blocked = true
now = 200 tick()
local sentCount = #sends
now = 220 tick()
assert(#sends == sentCount and said("chat lockdown"))
blocked = false
cooldowns[29166] = { startTime = 106, duration = 360, isEnabled = true, isOnGCD = false, modRate = 1 }
now = 221 tick()
local kind, reports = addon.CooldownSync.Decode(sends[#sends][2])
assert(kind == "state" and reports[1].remaining == 245)
slash("unlock")
assert(module.handle.mouse)
module.handle.scripts.OnDragStart(module.handle)
assert(module.frame.moving, "drag handle must move the window, not itself")
module.handle.scripts.OnDragStop(module.handle)
assert(SabotonEssentialsDB.modules.partycooldowns.state.position)
combat = true
module.frame.moving = false
module.handle.scripts.OnDragStart(module.handle)
assert(not module.frame.moving)
combat = false

units.party2 = { guid = "Player-other", name = "Leaf", second = "Brown", class = "DRUID", level = 60 }
fire("GROUP_ROSTER_UPDATE")
now = 223
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:R:0:0", "PARTY", "Leaf")
messages = {} slash("status")
assert(said("Leaf-Brown - Innervate: unknown"), "ambiguous first names must not route reports")
units.party1, units.party2 = nil, nil
fire("GROUP_ROSTER_UPDATE")
messages = {} slash("status")
assert(not said("Leaf-Green"), "departed roster members and their records must be removed")

local saved = module:GetPersistentState()
assert(#saved.timers > 0)
slash("disable")
assert(not module.frame.shown)
module:LoadPersistentState(saved)
slash("enable")
module:FinishRestore()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: cooldown"), "own client must supersede restored estimates")
slash("sync off")
sentCount = #sends
now = 300 tick()
assert(#sends == sentCount)
slash("test")
addon.SaveSettings()
assert(not SabotonEssentialsDB.modules.partycooldowns.testMode, "preview must be session-only")
slash("disable")
assert(not module.frame.shown)
slash("options")
local window = addon.modules.options.moduleWindows.partycooldowns
assert(window:IsShown())
local checks, sliders = {}, {}
for _, frame in ipairs(frames) do
    if frame.parent == window then
        if frame.kind == "CheckButton" then checks[frame.label] = frame end
        if frame.kind == "Slider" then sliders[#sliders + 1] = frame end
    end
end
assert(#sliders == 2 and not sliders[1].enabled)
local check = assert(checks["Enable Party Cooldowns (beta)"])
check:SetChecked(true)
check.scripts.OnClick(check)
assert(module.frame.shown and sliders[1].enabled)
sliders[1]:SetValue(500)
assert(SabotonEssentialsDB.modules.partycooldowns.width == 500)
local rebirth = assert(checks["Rebirth"])
rebirth:SetChecked(false)
rebirth.scripts.OnClick(rebirth)
assert(not SabotonEssentialsDB.modules.partycooldowns.rebirth)
slash("options")
assert(not window:IsShown())
addon.modules.options:HandleCommand()
local root = addon.modules.options.fallbackPanel
assert(root:IsShown())
local launcher
for _, frame in ipairs(frames) do
    if frame.parent == root and frame.text == "Party Cooldowns: options" then launcher = frame end
end
assert(launcher)
launcher.scripts.OnClick(launcher)
assert(window:IsShown(), "root fallback panel must open the module's schema window")
units.party1 = { guid = "Player-peer", name = "Leaf", second = "Green", class = "DRUID", level = 60 }
local originalRaid = IsInRaid
function IsInRaid() return true end
function GetNumGroupMembers() return 40 end
for index = 1, 40 do
    units["raid" .. index] = { guid = "Player-raid" .. index, name = "Raider" .. index, class = "DRUID", level = 60 }
end
units.raid1 = units.player
for _, spec in ipairs(module:GetOptionsSchema().options) do if spec.key == "rebirth" then spec.set(true) end end
fire("GROUP_ROSTER_UPDATE")
tick()
assert(module.next.shown and module.header.text:find("1/7", 1, true), "large raids must use bounded row pages")
module.next.scripts.OnClick(module.next)
assert(module.header.text:find("2/7", 1, true))
module.previous.scripts.OnClick(module.previous)
assert(module.header.text:find("1/7", 1, true))
IsInRaid = originalRaid
fire("GROUP_ROSTER_UPDATE")
tick()
assert(not module.next.shown and not module.previous.shown, "shrinking groups must reset pagination")
print("Party cooldown module, framework and persistence tests passed")
