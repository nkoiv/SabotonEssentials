local frames, controls, messages, lootName
local methods = {}
local function noop() end
for _, name in ipairs({ "SetSize", "SetFrameStrata", "SetFrameLevel", "SetHighlightTexture", "SetTexture", "SetTexCoord", "RegisterForDrag", "SetMovable", "SetClampedToScreen", "EnableMouse", "SetAllPoints", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetHeight", "SetWidth", "SetAlpha", "SetStatusBarColor", "SetText", "SetDrawLayer", "StartMoving", "StopMovingOrSizing" }) do
    methods[name] = noop
end
function methods:SetPoint(point, relative, relativePoint, x, y) self.x, self.y = x or 0, y or 0 end
function methods:ClearAllPoints() end
function methods:GetCenter() return 500 + (self.x or 0), 400 + (self.y or 0) end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:GetStatusBarTexture() return self end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:CreateTexture() return setmetatable({ scripts = {}, events = {} }, { __index = methods }) end
function methods:CreateFontString() return setmetatable({ scripts = {}, events = {} }, { __index = methods }) end
function CreateFrame()
    local frame = setmetatable({ scripts = {}, events = {} }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end

math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
function GetCursorPosition() return 500, 500 end
function GetTime() return 0 end
function issecretvalue() return false end
function PlaySoundFile() return true end
function GetNumLootItems() return 1 end
function GetLootSourceInfo() return "GameObject-1" end
function GetLootSlotLink() return nil end
function GetLootSlotInfo() return nil, lootName end
function UIFrameFadeOut() end
C_Timer = { NewTicker = function() return { Cancel = noop } end, NewTimer = function() return { Cancel = noop } end, After = noop }
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, key) return key end })
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
SettingsControlMixin = {}
function CreateFromMixins() return {} end

local function category() return { GetID = function() return 1 end } end
Settings = {
    VarType = { Boolean = 1, Number = 2, String = 3 },
    RegisterVerticalLayoutCategory = category,
    RegisterVerticalLayoutSubcategory = category,
    RegisterAddOnCategory = noop,
    CreateCheckbox = noop,
    CreateSlider = noop,
    CreateDropdown = noop,
    CreateSliderOptions = function() return { SetLabelFormatter = noop } end,
    CreateSettingInitializerData = function() return {} end,
    CreateElementInitializer = function() return {} end,
    RegisterInitializer = noop,
    RegisterProxySetting = function(_, key, _, _, _, get, set)
        local setting = { get = get, set = set }
        controls[key] = setting
        return setting
    end,
}

local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

local function session(saved)
    frames, controls, messages = {}, {}, {}
    UIParent = setmetatable({ scripts = {}, events = {} }, { __index = methods })
    Minimap = setmetatable({ scripts = {}, events = {} }, { __index = methods })
    SlashCmdList = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    SabotonEssentialsDB = saved
    local addon = {}
    for _, file in ipairs({ "src/Core.lua", "src/Modules/SqueakyToy.lua", "src/Modules/ExtraAttack.lua", "src/Modules/GatheringTimer.lua", "src/Modules/MinimapButton.lua", "src/Options.lua" }) do
        assert(loadfile(file))("SabotonEssentials", addon)
    end
    fire("ADDON_LOADED", "SabotonEssentials")
    return addon
end

local function slash(message) SlashCmdList.SABOTON(message) end
local function control(module, key) return assert(controls["SABOTONESSENTIALS_" .. module .. "_" .. key]) end
local function said(fragment)
    for _, message in ipairs(messages) do if message:find(fragment, 1, true) then return true end end
    return false
end

local addon = session(nil)
slash("gather enable")
slash("gather add Mystic Herb herb 60 120")
slash("gather add Another Herb herb 70 140")
slash("gather toggle Another Herb")
slash("gather toggle Copper")
slash("extraattack window 1.7")
slash("extraattack textformat Streak %d")
slash("squeak hostile")
slash("squeak debug")
control("EXTRAATTACK", "TEXTARCDURATION").set(1.8)
control("GATHER", "WIDTH").set(245)
control("MINIMAP", "SHOWBUTTON").set(false)

local gather = addon.modules.gather.frame
gather.x, gather.y = 125, -95
gather.scripts.OnDragStop(gather)
local button = addon.modules.minimap.button
button.scripts.OnDragStart(button)
button.scripts.OnUpdate(button)
button.scripts.OnDragStop(button)
local saved = SabotonEssentialsDB
assert(saved.modules.gather.state.minDurationOverride == false)
assert(saved.modules.gather.state.maxDurationOverride == false)
assert(saved.modules.gather.state.position.x == 125 and saved.modules.gather.state.position.y == -95)
assert(math.abs(saved.modules.minimap.state.angle - 90) < 0.001)

addon = session(saved)
assert(control("EXTRAATTACK", "COMBOWINDOW").get() == 1.7)
assert(control("EXTRAATTACK", "COMBOTEXTFORMAT").get() == "Streak %d")
assert(control("EXTRAATTACK", "TEXTARCDURATION").get() == 1.8)
assert(control("SQUEAK", "ANYHOSTILEDEATH").get())
assert(addon.modules.squeak:GetPersistentState().debug)
assert(control("GATHER", "WIDTH").get() == 245)
assert(control("GATHER", "GATHER_2770").get())
assert(control("GATHER", "GATHER_CUSTOM_19").get())
assert(not control("GATHER", "GATHER_CUSTOM_20").get())
assert(not control("MINIMAP", "SHOWBUTTON").get())
assert(addon.modules.gather.frame.x == 125 and addon.modules.gather.frame.y == -95)
assert(math.abs(addon.modules.minimap:GetPersistentState().angle - 90) < 0.001)
lootName = "Mystic Herb"
fire("LOOT_READY")
slash("gather status")
assert(said("min 60s / max 120s"), "untouched duration overrides changed per-entry timers")

slash("gather min 300")
control("GATHER", "MAXDURATION").set(450)
assert(SabotonEssentialsDB.modules.gather.state.minDurationOverride)
assert(SabotonEssentialsDB.modules.gather.state.maxDurationOverride)
saved = SabotonEssentialsDB
addon = session(saved)
lootName = "Mystic Herb"
fire("LOOT_READY")
slash("gather status")
assert(said("min 300s / max 450s"), "explicit duration overrides were not restored")
assert(SabotonEssentialsDB.modules.gather.state.position.x == 125)

addon = session(nil)
local expected = {}
for name, module in pairs(addon.modules) do
    if module.GetOptionsSchema then
        expected[name] = {}
        for _, spec in ipairs(module:GetOptionsSchema().options) do
            local value
            if spec.type == "checkbox" then
                value = not spec.get()
            elseif spec.type == "slider" then
                value = math.min(spec.max, spec.get() + spec.step)
            elseif spec.type == "dropdown" then
                local choices = type(spec.choices) == "function" and spec.choices() or spec.choices
                for _, choice in ipairs(choices) do
                    if choice.value ~= spec.get() then value = choice.value break end
                end
                value = value or spec.get()
            elseif spec.type == "text" then
                value = "Saved %d"
            end
            if value ~= nil then
                control(name:upper(), spec.key:upper()).set(value)
                expected[name][spec.key] = spec.get()
            end
        end
    end
end
saved = SabotonEssentialsDB
addon = session(saved)
for name, values in pairs(expected) do
    for key, value in pairs(values) do
        assert(control(name:upper(), key:upper()).get() == value, name .. "." .. key .. " did not round-trip")
    end
end

GetBuildInfo = function() return "1.60.1", "69893", "", 16001 end
session(nil)
assert(said("settings persistence is not guaranteed"))
GetBuildInfo = nil
print("Persistence relog tests passed")