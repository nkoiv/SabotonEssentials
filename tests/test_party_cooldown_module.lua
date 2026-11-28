local now, wall, combat, blocked = 100, 10000, false, false
local alt = false
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
for _, name in ipairs({ "SetHeight", "SetWidth", "ClearAllPoints", "SetAllPoints", "SetFrameLevel",
    "SetMinMaxValues", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetDrawLayer",
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StopMovingOrSizing", "SetFrameStrata",
    "SetBackdrop", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture", "SetJustifyH", "SetWordWrap" }) do methods[name] = noop end
function methods:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
function methods:SetSize(w, h) self.width, self.height = w, h end
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
function methods:UnregisterAllEvents() self.events = {} end
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
function IsAltKeyDown() return alt end
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
C_Timer = { NewTicker = function(_, callback)
    local ticker = { callback = callback, cancelled = false }
    function ticker:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = ticker
    return ticker
end }
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
local function tick()
    for _, ticker in ipairs(tickers) do if not ticker.cancelled then ticker.callback() end end
end
local function slash(message) SlashCmdList.SABOTON("partycooldowns " .. message) end
local function said(fragment)
    for _, message in ipairs(messages) do if message:find(fragment, 1, true) then return true end end
    return false
end
local module = addon.modules.partycooldowns
local registrations, apiReads = 0, 0
local registerPrefix = C_ChatInfo.RegisterAddonMessagePrefix
C_ChatInfo.RegisterAddonMessagePrefix = function(...)
    registrations = registrations + 1
    return registerPrefix(...)
end
local wrapped = {}
for _, key in ipairs({ "IsInRaid", "IsInGroup", "GetNumSubgroupMembers", "UnitGUID", "UnitName", "UnitClass",
    "UnitLevel", "UnitIsConnected", "UnitIsDeadOrGhost" }) do
    local original = _G[key]
    wrapped[key] = original
    _G[key] = function(...) apiReads = apiReads + 1 return original(...) end
end
local lookup = C_Spell.GetSpellName
C_Spell.GetSpellName = function(...) apiReads = apiReads + 1 return lookup(...) end
fire("ADDON_LOADED", "SabotonEssentials")
assert(module.frame == nil and module.events and module.ticker)
assert(registrations == 1 and apiReads > 0, "default hidden display must still initialize background sharing")
tick()
now = 102 tick()
assert(#sends == 2 and sends[2][2]:find("29166:R:0:0", 1, true),
    "default settings must share own cooldowns without creating visual elements")
local _, defaultReports = addon.CooldownSync.Decode(sends[2][2])
local reportedHidden = false
for _, report in ipairs(defaultReports) do
    if report.id == 22812 and report.kind == "N" then reportedHidden = true end
end
assert(reportedHidden, "a hidden catalogue choice must still be included in the broadcaster's class snapshot")
assert(module.frame == nil)
addon.SaveSettings()
assert(SabotonEssentialsDB.modules.partycooldowns.enabled == false
    and SabotonEssentialsDB.modules.partycooldowns.sharing == true, "display and sharing must persist independently")
assert(SabotonEssentialsDB.modules.partycooldowns.visibility == "group")
for _, spell in ipairs(addon.PartyCooldowns.presets) do
    assert(SabotonEssentialsDB.modules.partycooldowns[spell.key] == (spell.default == true),
        spell.key .. " must save the catalogue default independently of sharing")
end
addon.ApplySettings({ modules = { partycooldowns = { enabled = false, sharing = true, layonhands = true,
    shieldwall = true, rebirth = false } } })
addon.SaveSettings()
assert(SabotonEssentialsDB.modules.partycooldowns.layonhands and SabotonEssentialsDB.modules.partycooldowns.shieldwall
    and not SabotonEssentialsDB.modules.partycooldowns.rebirth and SabotonEssentialsDB.modules.partycooldowns.soulstone,
    "upgrades must preserve explicit older visibility choices and apply defaults only to new settings")
assert(SabotonEssentialsDB.modules.partycooldowns.visibility == "group", "older settings must default to party or raid")
local visibility
for _, spec in ipairs(module:GetOptionsSchema().options) do
    if spec.key == "layonhands" or spec.key == "shieldwall" then spec.set(false) end
    if spec.key == "rebirth" then spec.set(true) end
    if spec.key == "visibility" then visibility = spec end
end
assert(visibility and visibility.get() == "group")
slash("sync off")
assert(not module.ticker and next(module.events.events) == nil)
local oldTicker = tickers[#tickers]
assert(oldTicker.cancelled)
sends, apiReads = {}, 0
local previousRegistrations = registrations
addon.ApplySettings({ modules = { partycooldowns = { enabled = false, sharing = false,
    state = { position = { x = 123, y = -45 },
        timers = { { guid = "Player-peer", key = "innervate", endsAt = wall + 300, duration = 360 } } } } } })
addon.SaveSettings()
assert(module.frame == nil and not module.ticker and registrations == previousRegistrations and apiReads == 0,
    "both toggles off must leave no active runtime or game queries")
assert(not SabotonEssentialsDB.modules.partycooldowns.enabled)
fire("GROUP_ROSTER_UPDATE")
fire("CHAT_MSG_ADDON", "SECD1", "R|1", "PARTY", "Leaf Green")
assert(apiReads == 0 and #sends == 0)
for key, original in pairs(wrapped) do _G[key] = original end
C_Spell.GetSpellName = lookup
slash("test")
assert(module.frame.shown)
assert(module.frame.x == 123 and module.frame.y == -45, "lazy window creation must retain restored position")
tick()
assert(#sends == 0 and registrations == previousRegistrations and next(module.events.events) == nil,
    "disabled preview must not register messaging or tracking events")
slash("test")
assert(module.ticker == nil and not module.frame.shown)
local peer = units.party1
units.party1 = nil
for _, mode in ipairs({ "always", "group", "raid" }) do
    visibility.set(mode)
    assert(not module.frame.shown, "visibility mode must not override the display toggle")
    slash("test")
    assert(module.frame.shown, "solo preview must ignore visibility mode " .. mode)
    slash("test")
    assert(not module.frame.shown and not module.ticker)
end
visibility.set("group")
units.party1 = peer
slash("enable")
assert(module.frame.shown and SabotonEssentialsDB.modules.partycooldowns.enabled)
units.party1 = nil
fire("GROUP_ROSTER_UPDATE")
assert(not module.frame.shown, "default mode must hide the tracker immediately when solo")
visibility.set("always")
assert(module.frame.shown, "always mode must allow solo rows")
visibility.set("raid")
assert(not module.frame.shown, "raid mode must hide solo")
units.party1 = peer
fire("GROUP_ROSTER_UPDATE")
assert(not module.frame.shown, "raid mode must hide in a party")
visibility.set("group")
assert(module.frame.shown, "group mode must show in a party")
local oldRaid = IsInRaid
IsInRaid = function() return true end
GetNumGroupMembers = function() return 1 end
units.raid1 = units.player
units.party1 = nil
fire("GROUP_ROSTER_UPDATE")
assert(module.frame.shown, "group mode must also show in a raid")
visibility.set("raid")
assert(module.frame.shown, "raid mode must show in a raid")
IsInRaid = oldRaid
units.party1, units.raid1 = peer, nil
fire("GROUP_ROSTER_UPDATE")
assert(not module.frame.shown, "leaving a raid for a party must hide raid-only display")
messages = {}
visibility.set("invalid")
assert(visibility.get() == "raid" and said("invalid visibility mode"), "invalid modes must be reported and rejected")
visibility.set("group")
slash("sync on")
now = 104
tick()
assert(#sends == 1 and sends[1][2] == "R|1")
now = 106 tick()
assert(#sends == 2 and sends[2][2]:find("29166:R:0:0", 1, true))
visibility.set("raid")
assert(not module.frame.shown, "raid-only display must remain hidden in a party")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 29166)
now = 107.5 tick()
assert(sends[#sends][2]:find("29166:E:", 1, true), "visibility filtering must not stop background sharing")
visibility.set("group")
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: estimated"), "visibility changes must retain cooldown records")
local activeTicker = module.ticker
slash("disable")
assert(not module.frame.shown and module.ticker == activeTicker,
    "turning off display must not restart/cancel reporting or clear cooldown records")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 29166)
now = 107.5 tick()
assert(sends[#sends][2]:find("29166:E:", 1, true), "own cast estimates must be shared while display is hidden")
slash("enable")
assert(module.ticker == activeTicker, "display toggling must preserve the background reporting timer")
now = 110
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:R:0:0,20484:U:0:0", "PARTY", "Leaf Green")
slash("status")
assert(said("Leaf-Green - Innervate: ready"))
fire("PLAYER_REGEN_DISABLED")
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: unknown"), "combat invalidates an earlier remote-ready claim")
now = 112
fire("CHAT_MSG_ADDON", "SECD1", "S|1|29166:C:700:900", "PARTY", "Leaf-Green-TestRealm")
messages = {} slash("status")
assert(said("Leaf-Green - Innervate: cooldown 11:40"))
now = 114
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
now = 115 tick()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: cooldown 2:59"), "cooldown rate must be respected")
cooldowns[29166] = secretValue
now = 116 tick()
messages = {} slash("status")
assert(said("Oak-Tree - Innervate: cooldown 2:58"), "restricted reads must preserve an active timer")
cooldowns[29166] = { startTime = 0, duration = 0, isEnabled = secretValue, isOnGCD = false }
now = 117 tick()
messages = {} slash("status")
assert(not said("Oak-Tree - Innervate: ready"), "a secret enable flag must not be treated as true")
blocked = true
now = 200 tick()
local sentCount = #sends
now = 220 tick()
assert(#sends == sentCount and said("chat lockdown"))
blocked = false
cooldowns[29166] = { startTime = 108, duration = 360, isEnabled = true, isOnGCD = false, modRate = 1 }
now = 221 tick()
local kind, reports = addon.CooldownSync.Decode(sends[#sends][2])
assert(kind == "state" and reports[1].remaining == 247)
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
slash("lock")
assert(not module.handle.mouse)
module.frame.moving = false
module.handle.scripts.OnDragStart(module.handle)
assert(not module.frame.moving)
alt = true
fire("MODIFIER_STATE_CHANGED", "LALT", 1)
assert(module.handle.mouse)
module.handle.scripts.OnDragStart(module.handle)
assert(module.frame.moving and SabotonEssentialsDB.modules.partycooldowns.locked)
module.frame.x, module.frame.y = 175, -50
alt = false
fire("MODIFIER_STATE_CHANGED", "LALT", 0)
assert(module.handle.mouse, "modifier release during a drag must not lose OnDragStop")
module.handle.scripts.OnDragStop(module.handle)
assert(not module.handle.mouse)
assert(SabotonEssentialsDB.modules.partycooldowns.state.position.x == 175)
alt, combat = true, true
module.frame.moving = false
module.handle.scripts.OnDragStart(module.handle)
assert(not module.frame.moving, "locked Alt dragging must still be blocked in combat")
alt, combat = false, false
fire("MODIFIER_STATE_CHANGED", "LALT", 0)

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
assert(module.ticker and next(module.events.events), "hiding visuals must retain background sharing")
slash("sync off")
assert(module.ticker == nil and next(module.events.events) == nil)
local inactiveSends, inactiveMessages, inactiveRegistrations = #sends, #messages, registrations
local inactiveTicker = tickers[#tickers]
assert(inactiveTicker.cancelled)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 29166)
fire("CHAT_MSG_ADDON", "SECD1", "R|1", "PARTY", "Leaf Green")
tick()
inactiveTicker.callback()
assert(#sends == inactiveSends and #messages == inactiveMessages and registrations == inactiveRegistrations,
    "disabled runtime and already-queued callbacks must not process events, send or print")
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
assert(#sliders == 2 and sliders[1].enabled, "appearance controls must be available for disabled local previews")
local check = assert(checks["Show Party Cooldowns (beta)"])
assert(checks["Share my cooldowns with group members"].enabled,
    "sharing config must stay usable while display is hidden")
assert(checks["Rebirth (DRUID)"].enabled and checks["Shield Wall (WARRIOR)"].enabled,
    "ability visibility must be configurable while the display is hidden")
local visibilityButton
for _, frame in ipairs(frames) do
    if frame.parent == window and frame.kind == "Button" and frame.text == "Party or raid" then visibilityButton = frame end
end
assert(visibilityButton and visibilityButton.enabled, "visibility must be configurable with display off")
visibilityButton.scripts.OnClick(visibilityButton)
assert(visibilityButton.text == "Raid only" and SabotonEssentialsDB.modules.partycooldowns.visibility == "raid")
visibilityButton.scripts.OnClick(visibilityButton)
assert(visibilityButton.text == "Always" and SabotonEssentialsDB.modules.partycooldowns.visibility == "always")
visibilityButton.scripts.OnClick(visibilityButton)
assert(visibilityButton.text == "Party or raid" and SabotonEssentialsDB.modules.partycooldowns.visibility == "group")
visibilityButton.scripts.OnClick(visibilityButton)
visibilityButton.scripts.OnClick(visibilityButton)
check:SetChecked(true)
check.scripts.OnClick(check)
assert(module.frame.shown and sliders[1].enabled)
sliders[1]:SetValue(500)
assert(SabotonEssentialsDB.modules.partycooldowns.width == 500)
local rebirth = assert(checks["Rebirth (DRUID)"])
assert(not rebirth.shown and rebirth.enabled, "utility choices start on their own page but are editable while hidden")
local nextSection
for _, frame in ipairs(frames) do
    if frame.parent == window and frame.kind == "Button" and frame.text == ">" then nextSection = frame end
end
assert(nextSection and nextSection.enabled)
nextSection.scripts.OnClick(nextSection)
assert(rebirth.shown and not check.shown, "fallback options must separate utility from general controls")
rebirth:SetChecked(false)
rebirth.scripts.OnClick(rebirth)
assert(not SabotonEssentialsDB.modules.partycooldowns.rebirth)
nextSection.scripts.OnClick(nextSection)
assert(checks["Shield Wall (WARRIOR)"].shown and not rebirth.shown)
nextSection.scripts.OnClick(nextSection)
assert(checks["Recklessness (WARRIOR)"].shown and not checks["Shield Wall (WARRIOR)"].shown)
assert(not nextSection.enabled)
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
assert(not module.previous.enabled and module.next.enabled, "first page must disable Previous")
module.next.scripts.OnClick(module.next)
assert(module.header.text:find("2/7", 1, true))
module.previous.scripts.OnClick(module.previous)
assert(module.header.text:find("1/7", 1, true))
IsInRaid = originalRaid
fire("GROUP_ROSTER_UPDATE")
tick()
assert(not module.next.shown and not module.previous.shown, "shrinking groups must reset pagination")
slash("disable")
local previewButton
for _, frame in ipairs(frames) do
    if frame.parent == window and frame.text == "Show / hide preview" then previewButton = frame end
end
assert(previewButton, "preview must be accessible in fallback config without enabling tracking")
local configHandle
for _, frame in ipairs(frames) do
    if frame.parent == window and frame.scripts.OnDragStart then configHandle = frame end
end
assert(configHandle, "fallback config must have a title drag handle")
configHandle.scripts.OnDragStart(configHandle)
assert(window.moving, "configuration drag handle must move the whole configuration window")
configHandle.scripts.OnDragStop(configHandle)
local beforePreview = #sends
previewButton.scripts.OnClick(previewButton)
assert(module.frame.shown and not SabotonEssentialsDB.modules.partycooldowns.enabled)
local lock = assert(checks["Lock window position"])
assert(lock.enabled, "disabled preview must remain movable through config")
lock:SetChecked(false)
lock.scripts.OnClick(lock)
assert(module.handle.mouse and module.header.text:find("drag", 1, true))
local boundedRows = 0
for _, frame in ipairs(frames) do
    if frame.entry and frame.shown then
        assert(frame.stateText and frame.stateText.text, "countdowns need a separate reserved status column")
        boundedRows = boundedRows + 1
    end
end
assert(boundedRows == 4, "preview must show all four states with reserved status columns")
tick()
assert(#sends == beforePreview)
combat = true
slash("resetposition")
assert(said("reset the position out of combat"))
combat = false
slash("resetposition")
assert(module.frame.x == 300 and module.frame.y == 0)
assert(SabotonEssentialsDB.modules.partycooldowns.state.position == nil)
previewButton.scripts.OnClick(previewButton)
assert(not module.frame.shown and not module.ticker)
units.player = { guid = "Player-warrior", name = "Wall", second = "Tank", class = "WARRIOR", level = 60 }
units.party1 = { guid = "Player-peerwall", name = "Other", second = "Tank", class = "WARRIOR", level = 60 }
known, cooldowns = { [871] = true }, {}
names[871] = "Shield Wall"
for _, spec in ipairs(module:GetOptionsSchema().options) do
    if spec.key == "shieldwall" then spec.set(true) end
end
local aura
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) assert(id == 871) return aura end }
now = 1000
slash("sync on")
assert(module.frame and not module.frame.shown, "sharing must not force display visibility")
tick()
slash("enable")
for _, spec in ipairs(module:GetOptionsSchema().options) do
    if spec.key == "width" then spec.set(200) end
    if spec.key == "height" then spec.set(16) end
end
local function wallRow(guid)
    for _, frame in ipairs(frames) do
        if frame.shown and frame.entry and frame.entry.guid == guid and frame.entry.spell.key == "shieldwall" then return frame end
    end
    error("missing Shield Wall row")
end
local row = wallRow("Player-warrior")
local peerRow = wallRow("Player-peerwall")
local windowHeight, playerY, peerY = module.frame.height, row.y, peerRow.y
assert(row.height == 32 and peerRow.height == 32 and row.effectText.text == "",
    "effect-capable abilities must reserve both text lines before they are active")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "wall-cast", 871)
cooldowns[871] = { startTime = now, duration = 240, isEnabled = true, isOnGCD = false, modRate = 1 }
aura = { expirationTime = now + 12, duration = 12 }
fire("UNIT_AURA", "player")
tick()
assert(module.frame.height == windowHeight and row.y == playerY and peerRow.y == peerY,
    "starting an effect must not resize the window or move any row")
assert(row.effectText.text == "Active 12s" and row.stateText.text == "CD 4:00")
assert(row.width == 200 and row.height == 32 and module.frame.height >= 22 + row.height * 2,
    "active text must fit inside the clamped window even at minimum width/row height")
now = 1002 tick()
row = wallRow("Player-warrior")
assert(row.effectText.text == "Active 10s" and row.stateText.text == "CD 3:58")
assert(math.abs(row.bar.value - 10 / 12) < 0.001, "bar fill must show effect duration while active")
local _, wallReports = addon.CooldownSync.Decode(sends[#sends][2])
assert(wallReports[1].id == 871 and wallReports[1].effectKind == "C", "aura timing must be shared in the background")
fire("CHAT_MSG_ADDON", "SECD1", "S|2|871:C:235:240:C:8:12", "PARTY", "Other-Tank")
row = wallRow("Player-peerwall")
tick()
assert(row.effectText.text == "Active 8s" and row.stateText.text == "CD 3:55")
combat = true
aura = { expirationTime = secretValue, duration = secretValue }
now = 1003 fire("UNIT_AURA", "player") tick()
assert(wallRow("Player-warrior").effectText.text == "~Active 9s",
    "restricted aura fields must preserve timing only as an estimate")
aura = nil
now = 1004 fire("UNIT_AURA", "player") tick()
assert(wallRow("Player-warrior").effectText.text == "~Active 8s", "nil in combat is not proof of aura removal")
combat = false
now = 1005 fire("UNIT_AURA", "player") tick()
row = wallRow("Player-warrior")
assert(row.effectText.text == "" and row.stateText.text == "3:55", "readable aura removal must keep the cooldown")
now = 1011 tick()
row = wallRow("Player-peerwall")
assert(row.effectText.text == "" and row.stateText.text == "3:46", "remote effect expiry must resume cooldown fill")
assert(module.frame.height == windowHeight and row.height == 32 and peerRow.height == 32
    and wallRow("Player-warrior").y == playerY and peerRow.y == peerY,
    "effect expiry must leave the window and row positions unchanged")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "next-cast", 871)
tick()
assert(wallRow("Player-peerwall").effectText.text == "~Active 12s", "non-reporting casts need Forever's estimated active duration")
assert(wallRow("Player-peerwall").stateText.text == "CD ~15:00", "cast-only cooldown must not assume protection talents")
slash("disable")
assert(not module.frame.shown and module.ticker)
now = 1013 tick()
assert(not module.frame.shown, "hidden sharing must stay hidden while effects are active")
slash("sync off")
assert(not module.ticker and next(module.events.events) == nil)
units.player = { guid = "Player-lock", name = "Lock", class = "WARLOCK", level = 60 }
units.party1 = nil
names[20707] = "Soulstone Resurrection"
local itemCount, itemStart, itemDuration = 0, 0, 0
C_Item = { GetItemCount = function(id) return id == 5232 and itemCount or 0 end }
C_Container = { GetItemCooldown = function(id)
    assert(id == 5232)
    return itemStart, itemDuration, 1
end }
now = 2000
slash("sync on")
slash("enable")
local function soulstoneRow()
    for _, frame in ipairs(frames) do
        if frame.shown and frame.entry and frame.entry.spell.key == "soulstone" then return frame end
    end
    error("missing default Soulstone row")
end
tick()
assert(soulstoneRow().stateText.text == "Unknown", "no Soulstone item is not proof of readiness")
itemCount = 1
fire("BAG_UPDATE_DELAYED")
tick()
assert(soulstoneRow().stateText.text == "Stone ready", "a ready item must not imply resurrection availability")
messages = {} slash("status")
assert(said("Soulstone application: stone ready"), "status output must not imply a stored resurrection")
itemStart, itemDuration = 2000, 1800
fire("BAG_UPDATE_COOLDOWN")
tick()
assert(soulstoneRow().stateText.text == "30:00")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "stone", 20707)
itemCount = 0
now = 2002 fire("BAG_UPDATE_DELAYED") tick()
assert(soulstoneRow().stateText.text == "~29:58", "consumed item must preserve cast-based cooldown estimate")
itemCount = 1
itemStart, itemDuration = secretValue, secretValue
now = 2003 fire("BAG_UPDATE_COOLDOWN") tick()
assert(soulstoneRow().stateText.text == "~29:57", "restricted item cooldown must never be treated as ready")
slash("disable")
slash("sync off")
print("Party cooldown module, framework and persistence tests passed")
