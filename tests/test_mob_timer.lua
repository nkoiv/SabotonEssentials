local now, ticker, module = 0, nil, nil
local sounds, messages, frames = {}, {}, {}
local methods = {}
local function noop() end
for _, key in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameLevel", "SetFrameStrata",
    "SetTexture", "SetBlendMode", "SetVertexColor", "SetMinMaxValues", "SetStatusBarTexture", "SetOrientation",
    "SetColorTexture", "SetHeight", "SetWidth", "SetAlpha", "SetStatusBarColor", "SetMovable",
    "SetClampedToScreen", "EnableMouse", "RegisterForDrag", "SetDrawLayer", "SetBackdrop",
    "SetAutoFocus", "SetMaxLetters", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture", "ClearFocus", "StopMovingOrSizing" }) do methods[key] = noop end
function methods:GetCenter() return 0, 0 end
function methods:GetFrameLevel() return 1 end
function methods:GetStatusBarTexture() return self end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function methods:SetValue(value) self.value = value if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetShown(value) self.shown = value end
function methods:SetScript(key, callback) self.scripts[key] = callback end
function methods:RegisterEvent(event) self.events = self.events or {} self.events[event] = true end
function methods:CreateTexture() return setmetatable({ scripts = {} }, { __index = methods }) end
function methods:CreateFontString() return setmetatable({ scripts = {} }, { __index = methods }) end
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ scripts = {}, parent = parent, template = template }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end
UIParent = setmetatable({ scripts = {} }, { __index = methods })
function GetTime() return now end
function PlaySoundFile(path) sounds[#sounds + 1] = path return true end
function UIFrameFadeOut() end
C_Timer = { NewTicker = function(_, callback) ticker = callback end }
local addon = { Print = function(message) messages[#messages + 1] = message end, SaveSettings = noop,
    RegisterModule = function(name, value) assert(name == "mobtimer") module = value end }
local function said(text)
    for _, message in ipairs(messages) do if message:find(text, 1, true) then return true end end
    return false
end
local function click(label)
    for _, frame in ipairs(frames) do
        if frame.template == "UIPanelButtonTemplate" and frame.text == label then frame.scripts.OnClick(frame) return end
    end
    error("button not found: " .. label)
end
assert(loadfile("src/Support/TimerBars.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Modules/MobTimer.lua"))("SabotonEssentials", addon)
module:OnEnable()
module:HandleCommand("add High Chief Winterfall 300 540")
module:HandleCommand("add Other Mob 20 40")
assert(#module:GetPersistentState().entries == 2)
module:HandleCommand("add HIGH CHIEF WINTERFALL 1 2")
module:HandleCommand("add Invalid 50 10")
assert(#module:GetPersistentState().entries == 2 and said("already exists") and said("minimum no greater"))
module:HandleCommand("test High Chief Winterfall")
module:HandleCommand("test Other Mob")
assert(module.frame.shown)
now = 5 ticker()
assert(#sounds == 2 and sounds[1]:find("clear-bell", 1, true))
now = 6 ticker()
assert(#sounds == 2)
now = 10 ticker()
assert(#sounds == 4 and sounds[3]:find("impact-thud", 1, true))
now = 12 ticker()
assert(not module.frame.shown)
module:HandleCommand("start High Chief Winterfall")
now = 20 ticker()
assert(module.frame.shown and #sounds == 4)
module:HandleCommand("edit High Chief Winterfall 10 20")
now = 30 ticker()
assert(#sounds == 4, "editing an entry must not change an active snapshot")
module:HandleCommand("start High Chief Winterfall")
now = 40 ticker()
assert(#sounds == 5)
module:HandleCommand("clear")
assert(not module.frame.shown)

module:ToggleEditor()
local panel = module.editor
assert(panel:IsShown())
assert(panel.backdrop.bgFile == "Interface\\Buttons\\WHITE8X8" and panel.backdropColor[4] == 1,
    "editor background must be opaque over settings")
click("New")
assert(panel.minimum:GetText() == "600" and panel.maximum:GetText() == "900")
panel.name:SetText("Test Mob")
panel.minSlider:SetValue(121)
assert(panel.minimum:GetText() == "121", "sliders must update their duration fields")
panel.minimum:SetText("15")
panel.maximum:SetText("45")
click("Save")
assert(#module:GetPersistentState().entries == 3)
click("Test 5s/10s")
assert(module.frame.shown)
click("Remove")
assert(#module:GetPersistentState().entries == 2 and not module.frame.shown)
local saved = module:GetPersistentState()
module:LoadPersistentState(saved)
assert(#module:GetPersistentState().entries == 2)
module:HandleCommand("list")
assert(said("High Chief Winterfall 10s-20s"))
module:HandleCommand("lock")
module:HandleCommand("width 500")
module:HandleCommand("width 501")
assert(said("width must be between"))

local units, secret = {}, {}
function issecretvalue(value) return value == secret end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitName(unit) return units[unit] and units[unit].name end
local function fire(event, value) module.events.scripts.OnEvent(module.events, event, value) end
module:HandleCommand("target")
assert(said("select a creature"))
units.target = { guid = "Player-0-1", name = "Player" }
assert(not module:AddCurrentTarget())
units.target = { guid = secret, name = "Secret" }
assert(not module:AddCurrentTarget())
units.target = { guid = "Creature-0-0-0-0-130-1", name = secret }
assert(not module:AddCurrentTarget() and said("name is unavailable"))
units.target = { guid = "Creature-0-0-0-0-130-1", name = "Target Mob" }
click("Add target")
local targetEntry = module:GetPersistentState().entries[3]
assert(targetEntry.name == "Target Mob" and targetEntry.minSeconds == 600 and targetEntry.maxSeconds == 900)
assert(panel.name:GetText() == "Target Mob")
assert(not module:AddCurrentTarget() and #module:GetPersistentState().entries == 3)
units.target = nil
fire("UNIT_DIED", "Creature-0-0-0-0-130-1")
assert(module.frame.shown, "newly added target is immediately observed")
module:HandleCommand("remove Target Mob")
assert(not module.frame.shown)
module:HandleCommand("unlock")
assert(module.frame.shown and module.preview.shown)
module:HandleCommand("start Other Mob")
assert(module.frame.shown and not module.preview.shown, "active bars replace preview")
module:HandleCommand("clear")
assert(module.frame.shown and module.preview.shown)
module:HandleCommand("lock")
assert(not module.frame.shown)
now = 100
units.target = { guid = "Creature-0-0-0-0-123-1", name = "high chief winterfall" }
fire("PLAYER_TARGET_CHANGED")
units.target = nil
now = 101
local soundCount = #sounds
fire("UNIT_DIED", "Creature-0-0-0-0-123-1")
assert(module.frame.shown and said("death detected for High Chief Winterfall"))
now = 106
fire("UNIT_DIED", "Creature-0-0-0-0-123-1")
now = 111
ticker()
assert(#sounds == soundCount + 1, "duplicate death must not restart the timer")
module:HandleCommand("clear")
units.nameplate1 = { guid = "Creature-0-0-0-0-124-2", name = "Other Mob" }
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
fire("UNIT_DIED", "Creature-0-0-0-0-124-2")
assert(module.frame.shown, "nameplate identity should start a timer")
module:HandleCommand("clear")
units.nameplate1 = nil
units.focus = { guid = "Creature-0-0-0-0-125-3", name = "Other Mob" }
fire("UNIT_DIED", "Creature-0-0-0-0-125-3")
assert(module.frame.shown, "death should resolve a still-visible unit")
module:HandleCommand("clear")
units.focus = nil
fire("UNIT_DIED", secret)
fire("UNIT_DIED", "Player-0-1")
fire("UNIT_DIED", "Creature-0-0-0-0-999-9")
assert(not module.frame.shown)
units.target = { guid = secret, name = "Other Mob" }
fire("PLAYER_TARGET_CHANGED")
units.target = { guid = "Creature-0-0-0-0-126-4", name = secret }
fire("PLAYER_TARGET_CHANGED")
units.target = nil
fire("UNIT_DIED", "Creature-0-0-0-0-126-4")
assert(not module.frame.shown, "secret identity must not match")
units.target = { guid = "Creature-0-0-0-0-127-5", name = "Other Mob" }
fire("PLAYER_TARGET_CHANGED")
units.target = nil
now = now + 1801
fire("UNIT_DIED", "Creature-0-0-0-0-127-5")
assert(not module.frame.shown, "expired identity must not match")
module:HandleCommand("enable")
units.target = { guid = "Creature-0-0-0-0-128-6", name = "Other Mob" }
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_DIED", "Creature-0-0-0-0-128-6")
assert(not module.frame.shown, "disabled detection must not start timers")
module:HandleCommand("enable")
units.target = nil
fire("UNIT_DIED", "Creature-0-0-0-0-128-6")
assert(module.frame.shown, "reenabling detection should observe current units")
module:HandleCommand("status")
assert(said("UNIT_DIED registered"))
assert(said("matched=5 unmatched=3 secret=1 duplicate=1"))
function UnitGUID() error("unit API unavailable") end
units.target = { guid = "Creature-0-0-0-0-129-7", name = "Other Mob" }
fire("PLAYER_TARGET_CHANGED")
assert(said("UnitGUID failed:"), "unit API failures must be reported")
function methods:RegisterEvent(event)
    if event == "UNIT_DIED" then error("unsupported event") end
    self.events = self.events or {}
    self.events[event] = true
end
assert(loadfile("src/Modules/MobTimer.lua"))("SabotonEssentials", addon)
module:OnEnable()
module:HandleCommand("status")
assert(said("could not register UNIT_DIED") and said("UNIT_DIED unavailable"))
module:HandleCommand("add Manual Only 10 20")
module:HandleCommand("start Manual Only")
assert(module.frame.shown, "manual timers remain available when death registration fails")
function UnitGUID() return "Creature-0-0-0-0-200-1" end
function UnitName() return "Command Mob" end
module:HandleCommand("target")
assert(module:GetPersistentState().entries[2].name == "Command Mob")
for index = 3, 30 do module:HandleCommand("add Mob " .. index .. " 600 900") end
function UnitName() return "Over Limit" end
assert(not module:AddCurrentTarget() and #module:GetPersistentState().entries == 30 and said("maximum of 30"))
print("Mob timer tests passed")
