local frames, controls, messages, lootName
local alt = false
function IsAltKeyDown() return alt end
local methods = {}
local function noop() end
methods.SetWordWrap = noop
for _, name in ipairs({ "SetSize", "SetFrameStrata", "SetFrameLevel", "SetHighlightTexture", "SetTexture", "SetTexCoord", "RegisterForClicks", "RegisterForDrag", "SetMovable", "SetClampedToScreen", "EnableMouse", "SetAllPoints", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetOrientation", "SetColorTexture", "SetHeight", "SetWidth", "SetAlpha", "SetStatusBarColor", "SetText", "SetDrawLayer", "StartMoving", "StopMovingOrSizing", "SetJustifyH", "SetJustifyV", "SetHitRectInsets", "SetEnabled", "SetChecked" }) do
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
function methods:IsShown() return self.shown end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:StartMoving() self.moving = true end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
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
function GetRealmName() return "TestRealm" end
function UnitName() return "TestPlayer" end
function time() return 100 end
function GetNumLootItems() return 1 end
function GetLootSourceInfo() return "GameObject-1" end
function GetLootSlotLink() return nil end
function GetLootSlotInfo() return nil, lootName end
function UIFrameFadeOut() end
C_Timer = { NewTicker = function() return { Cancel = noop } end, NewTimer = function() return { Cancel = noop } end, After = noop }
LibStub = {
    GetLibrary = function(_, name)
        if name == "AceAddon-3.0" then
            return { GetAddon = function() return { RegisterModuleOptions = noop } end }
        end
    end,
}
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, key) return key end })
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
SettingsControlMixin = {}
Menu = { ModifyMenu = noop }
function CreateFromMixins() return {} end
function CreateSettingsButtonInitializer() return {} end

local function category() return { GetID = function() return 1 end } end
Settings = {
    VarType = { Boolean = 1, Number = 2, String = 3 },
    RegisterVerticalLayoutCategory = category,
    RegisterVerticalLayoutSubcategory = category,
    RegisterCanvasLayoutSubcategory = category,
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
    for _, file in ipairs({ "src/Core.lua", "src/Support/Spells.lua", "src/Support/TimerBars.lua", "src/Support/PartyCooldowns.lua", "src/Support/CooldownSync.lua", "src/Modules/PartyCooldownTracker.lua", "src/Modules/SqueakyToy.lua", "src/Modules/ExtraAttack.lua", "src/Modules/GatheringTimer.lua", "src/Modules/MobTimer.lua", "src/Modules/TankTarget.lua", "src/Modules/TankHelper.lua", "src/Modules/MinimapButton.lua", "src/Modules/WowheadLink.lua", "src/Modules/ChatTabs.lua", "src/Support/GuildSync.lua", "src/Modules/SpyEnhancement.lua", "src/Options.lua" }) do
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

ChatFrame1 = {
    size = 12,
    writes = 0,
    IsShown = function() return true end,
    GetFont = function(self) return "Fonts\\CHAT.TTF", self.size, "" end,
    SetFont = function(self, _, size) self.size = size self.writes = self.writes + 1 end,
}
session({ version = 1, modules = {
    chattabs = { font = "default", customFontSize = false, fontSize = 14 },
} })
for _, frame in ipairs(frames) do
    if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.1) end
end
assert(ChatFrame1.size == 12 and ChatFrame1.writes == 0,
    "restoring disabled custom size must not change the client's chat font size")
ChatFrame1 = nil

local addon = session({ version = 1, modules = { minimap = { showButton = false },
    partycooldowns = { enabled = false, sharing = false } } })
assert(not control("MINIMAP", "SHOWBUTTON").get(), "existing minimap preference must restore")
assert(control("PARTYCOOLDOWNS", "VISIBILITY").get() == "group",
    "older cooldown settings without a visibility mode must default to party or raid")
assert(not control("WOWHEAD", "MENUENABLED").get(), "upgrades must default the Wowhead menu off")
assert(not control("CHATTABS", "ENABLED").get(), "chat-tab hiding must be disabled by default")
assert(not control("CHATTABS", "HIDEBUTTONS").get(), "chat-button hiding must be disabled by default")
assert(control("CHATTABS", "FONT").get() == "default", "chat tabs must preserve their default font")
assert(not control("CHATTABS", "CUSTOMFONTSIZE").get(), "chat message size override defaults off")
addon = session(nil)
assert(not control("WOWHEAD", "MENUENABLED").get(), "Wowhead portrait menu must default off")
slash("help")
assert(said("  missalerts"), "help must show the new command")
slash("missalerts start")
assert(said("Miss Alerts probe: started"))
assert(SabotonEssentialsDB.modules.tankhelper.enabled, "alert settings must be persisted")
assert(SabotonEssentialsDB.modules.tankhelper.state == nil, "diagnostic state must not be persisted")
slash("tankhelper stop")
assert(said("Miss Alerts probe: stopped"), "old command remains an alias")
slash("missalerts window 120")
slash("tankhelper add 12345")
slash("missalerts sound")
slash("missalerts soundkey thud")
slash("missalerts xoffset -300")
slash("missalerts movement 2")
C_Spell = {
    GetSpellInfo = function(name) if name == "Mock Strike" then return { spellID = 9876 } end end,
    GetSpellName = function(id) if id == 9876 or id == 9877 then return "Mock Strike" end end,
}
slash("missalerts add Mock Strike")
assert(SabotonEssentialsDB.modules.tankhelper.spellFamilies == "9876")
assert(SabotonEssentialsDB.modules.tankhelper.addSpell == nil, "action inputs must not be persisted")
assert(not control("SPYENHANCEMENT", "SHAREKOSREASONS").get(), "upgrades must not enable reason sharing")
control("SPYENHANCEMENT", "SHAREKOSREASONS").set(true)
slash("gather enable")
slash("gather add Mystic Herb herb 60 120")
slash("gather add Another Herb herb 70 140")
slash("mobtimer add High Chief Winterfall 3600 7200")
control("MOBTIMER", "WIDTH").set(245)
control("MOBTIMER", "DETECTIONENABLED").set(false)
slash("gather toggle Another Herb")
slash("gather toggle Iron")
slash("extraattack window 1.7")
slash("extraattack minhits 3")
slash("extraattack textformat Streak %d")
slash("squeak hostile")
slash("squeak debug")
slash("spyenhancement detect player ЇЁ")
control("EXTRAATTACK", "TEXTARCDURATION").set(1.8)
control("GATHER", "WIDTH").set(245)
control("GATHER", "CELEBRATE_12363").set(false)
control("GATHER", "CELEBRATION_SOUND_248819").set("squeak")
control("MINIMAP", "SHOWBUTTON").set(false)
control("WOWHEAD", "MENUENABLED").set(true)
control("CHATTABS", "ENABLED").set(false)
control("CHATTABS", "HIDEINPUT").set(true)
control("CHATTABS", "HIDEBUTTONS").set(true)
control("CHATTABS", "FONT").set("arial")
control("CHATTABS", "FONTSIZE").set(16)
control("CHATTABS", "CUSTOMFONTSIZE").set(true)
control("TANKTARGET", "THREATLOW").set(85)
control("TANKTARGET", "THREATHIGH").set(95)
control("TANKTARGET", "TANKTHREATLOW").set(200)
control("TANKTARGET", "TANKTHREATHIGH").set(250)
control("TANKTARGET", "THREATMODE").set("raw")
assert(control("TANKTARGET", "INFERGROUPTANK").get(), "group tank guessing defaults on")
slash("tanktarget guess")
assert(not control("TANKTARGET", "ALLTHREAT").get(), "all-nameplate threat defaults off")
slash("tanktarget allthreat")
assert(control("TANKTARGET", "HOSTILEONLY").get(), "hostile-only defaults on")
control("TANKTARGET", "HOSTILEONLY").set(false)
slash("tanktarget hostile")

local gather = addon.modules.gather.frame
slash("gather lock")
alt = true
fire("MODIFIER_STATE_CHANGED", "LALT", 1)
assert(gather.mouseEnabled, "locked timer frames must receive Alt dragging")
gather.scripts.OnDragStart(gather)
assert(gather.moving)
gather.x, gather.y = 125, -95
gather.scripts.OnDragStop(gather)
assert(control("GATHER", "LOCKED").get(), "Alt movement must not unlock the timer")
slash("missalerts move")
local anchor = addon.modules.tankhelper.textAnchor
assert(anchor:IsShown() and anchor.x == -300 and anchor.y == 200)
anchor.scripts.OnDragStart(anchor)
anchor.x, anchor.y = -300, 150
anchor.scripts.OnDragStop(anchor)
assert(SabotonEssentialsDB.modules.tankhelper.textOffsetY == 150)
slash("extraattack move")
anchor = addon.modules.extraattack.textAnchor
assert(anchor:IsShown() and anchor.x == 200 and anchor.y == 200)
anchor.scripts.OnDragStart(anchor)
anchor.x, anchor.y = 320, -80
anchor.scripts.OnDragStop(anchor)
assert(SabotonEssentialsDB.modules.extraattack.textOffsetX == 320)
assert(SabotonEssentialsDB.modules.extraattack.textOffsetY == -80)
control("EXTRAATTACK", "TEXTOFFSETX").set(340)
assert(anchor.x == 340, "sliders must reposition an open anchor")
slash("extraattack test")
assert(addon.modules.extraattack.comboDisplay.x == 340 and addon.modules.extraattack.comboDisplay.y == -80,
    "animation must begin at the newly configured anchor")
slash("extraattack move")
assert(not anchor:IsShown())
slash("missalerts move")
assert(not addon.modules.tankhelper.textAnchor:IsShown())
alt = false
fire("MODIFIER_STATE_CHANGED", "LALT", 0)
assert(not gather.mouseEnabled)
local button = addon.modules.minimap.button
button.scripts.OnDragStart(button)
button.scripts.OnUpdate(button)
button.scripts.OnDragStop(button)
local saved = SabotonEssentialsDB
assert(saved.modules.gather.state.minDurationOverride == false)
assert(saved.modules.gather.state.maxDurationOverride == false)
assert(saved.modules.spyenhancement.state.syncState.lastSyncTime == 0)
assert(saved.modules.spyenhancement.state.cyrillicCache["player:ЇЁ"].ukrainian[1] == "Ї")
assert(saved.modules.gather.state.position.x == 125 and saved.modules.gather.state.position.y == -95)
assert(math.abs(saved.modules.minimap.state.angle - 90) < 0.001)

addon = session(saved)
assert(addon.modules.extraattack.textAnchor == nil and addon.modules.tankhelper.textAnchor == nil,
    "positioning anchors must not be restored or enable visuals")
assert(control("EXTRAATTACK", "TEXTOFFSETX").get() == 340 and control("EXTRAATTACK", "TEXTOFFSETY").get() == -80)
assert(control("TANKHELPER", "TEXTOFFSETY").get() == 150)
assert(control("TANKHELPER", "FIGHTWINDOW").get() == 120)
assert(SabotonEssentialsDB.modules.tankhelper.spellList:find("12345", 1, true))
assert(not control("TANKHELPER", "SOUNDENABLED").get())
assert(control("TANKHELPER", "SOUNDKEY").get() == "thud")
assert(control("TANKHELPER", "TEXTOFFSETX").get() == -300)
assert(control("TANKHELPER", "TEXTARCDURATION").get() == 2)
assert(SabotonEssentialsDB.modules.tankhelper.spellFamilies == "9876", "all-rank entry must survive reload")
slash("missalerts spells")
assert(said("Mock Strike (all ranks; ID 9876)"))
slash("missalerts alertstatus")
assert(said("Miss Alerts enabled; window Unlimited"), "unlimited setting must survive reload and be reported")
assert(addon.modules.mobtimer:GetPersistentState().entries[1].name == "High Chief Winterfall")
assert(addon.modules.mobtimer:GetPersistentState().entries[1].minSeconds == 3600)
assert(control("MOBTIMER", "WIDTH").get() == 245)
assert(not control("MOBTIMER", "DETECTIONENABLED").get(), "disabled automatic detection must survive reload")
assert(control("SPYENHANCEMENT", "SHAREKOSREASONS").get(), "reason-sharing preference must survive reload")
assert(addon.modules.spyenhancement:GetPersistentState().syncState.lastSyncTime == 0)
slash("spyenhancement detect player ЇЁ")
assert(said("Mixed indicators (Ukrainian-compatible: Ї; Russian-compatible: Ё); inconclusive"),
    "spelling clues must survive reload")
assert(control("EXTRAATTACK", "COMBOWINDOW").get() == 1.7)
assert(control("EXTRAATTACK", "MINBURSTHITS").get() == 3)
control("EXTRAATTACK", "MINBURSTHITS").set(4)
assert(control("EXTRAATTACK", "COMBOTEXTFORMAT").get() == "Streak %d")
assert(control("EXTRAATTACK", "TEXTARCDURATION").get() == 1.8)
assert(control("SQUEAK", "ANYHOSTILEDEATH").get())
assert(addon.modules.squeak:GetPersistentState().debug)
assert(control("GATHER", "WIDTH").get() == 245)
assert(control("GATHER", "GATHER_2772").get())
assert(control("GATHER", "GATHER_CUSTOM_9").get())
assert(not control("GATHER", "GATHER_CUSTOM_10").get())
assert(not control("GATHER", "CELEBRATE_12363").get())
assert(control("GATHER", "CELEBRATION_SOUND_248819").get() == "squeak")
assert(not control("MINIMAP", "SHOWBUTTON").get())
assert(control("WOWHEAD", "MENUENABLED").get(), "Wowhead menu preference must survive reload")
assert(not control("CHATTABS", "ENABLED").get(), "chat tab preference must survive reload")
assert(control("CHATTABS", "HIDEINPUT").get(), "chat input preference must survive reload")
assert(control("CHATTABS", "HIDEBUTTONS").get(), "chat button preference must survive reload")
assert(control("CHATTABS", "FONT").get() == "arial" and control("CHATTABS", "FONTSIZE").get() == 16,
    "chat tab font preferences must survive reload")
assert(control("CHATTABS", "CUSTOMFONTSIZE").get(), "chat message size override survives reload")
assert(control("TANKTARGET", "THREATLOW").get() == 85)
assert(control("TANKTARGET", "THREATHIGH").get() == 95)
assert(control("TANKTARGET", "TANKTHREATLOW").get() == 200)
assert(control("TANKTARGET", "TANKTHREATHIGH").get() == 250)
assert(control("TANKTARGET", "THREATMODE").get() == "raw")
assert(not control("TANKTARGET", "INFERGROUPTANK").get(), "disabled tank guessing survives reload")
assert(control("TANKTARGET", "ALLTHREAT").get(), "all-nameplate threat survives reload")
assert(control("TANKTARGET", "HOSTILEONLY").get(), "hostile-only survives reload")
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
assert(control("EXTRAATTACK", "MINBURSTHITS").get() == 4)
lootName = "Mystic Herb"
fire("LOOT_READY")
slash("gather status")
assert(said("min 300s / max 450s"), "explicit duration overrides were not restored")
assert(SabotonEssentialsDB.modules.gather.state.position.x == 125)

addon = session(nil)
local menu
MenuUtil = { CreateContextMenu = function(owner, build)
    menu = {}
    local root = { CreateTitle = noop, CreateButton = function(_, label, callback) menu[label] = callback end }
    build(owner, root)
end }
button = addon.modules.minimap.button
local opened = false
local originalOpen = addon.modules.options.HandleCommand
addon.modules.options.HandleCommand = function() opened = true end
button.scripts.OnClick(button, "LeftButton")
assert(opened, "left click still opens options")
addon.modules.options.HandleCommand = originalOpen
button.scripts.OnClick(button, "RightButton")
assert(menu["Unlock bar movement"])
menu["Unlock bar movement"]()
assert(not control("GATHER", "LOCKED").get() and not control("MOBTIMER", "LOCKED").get())
assert(addon.modules.gather.frame.shown and addon.modules.mobtimer.frame.shown, "unlock exposes idle frames")
assert(addon.modules.gather.frame.mouseEnabled and addon.modules.mobtimer.frame.mouseEnabled)
InCombatLockdown = function() return true end
addon.modules.gather.frame.scripts.OnDragStart(addon.modules.gather.frame)
assert(not addon.modules.gather.frame.moving, "dragging is blocked in combat")
InCombatLockdown = function() return false end
addon.modules.gather.frame.scripts.OnDragStart(addon.modules.gather.frame)
assert(addon.modules.gather.frame.moving, "unlocked frames can be dragged")
InCombatLockdown = nil
local originalUnitName = UnitName
UnitGUID = function(unit) if unit == "target" then return "Creature-0-0-0-0-123-1" end end
UnitName = function(unit) if unit == "target" then return "Menu Mob" end return originalUnitName(unit) end
assert(menu["Add current target to mob timer"])
menu["Add current target to mob timer"]()
assert(SabotonEssentialsDB.modules.mobtimer.state.entries[1].name == "Menu Mob")
assert(SabotonEssentialsDB.modules.mobtimer.state.entries[1].minSeconds == 600)
UnitGUID, UnitName = nil, originalUnitName
addon.modules.mobtimer.frame.scripts.OnDragStart(addon.modules.mobtimer.frame)
addon.modules.mobtimer.frame.x, addon.modules.mobtimer.frame.y = 42, -80
addon.modules.mobtimer.frame.scripts.OnDragStop(addon.modules.mobtimer.frame)
saved = SabotonEssentialsDB
addon = session(saved)
assert(not control("GATHER", "LOCKED").get() and not control("MOBTIMER", "LOCKED").get())
assert(addon.modules.mobtimer.frame.shown and addon.modules.mobtimer.frame.x == 42 and addon.modules.mobtimer.frame.y == -80)
assert(addon.modules.mobtimer:GetPersistentState().entries[1].name == "Menu Mob")
button = addon.modules.minimap.button
button.scripts.OnClick(button, "RightButton")
assert(menu["Lock bar movement"])
menu["Lock bar movement"]()
assert(control("GATHER", "LOCKED").get() and control("MOBTIMER", "LOCKED").get())
assert(not addon.modules.gather.frame.shown and not addon.modules.mobtimer.frame.shown, "locking hides idle previews")
assert(not addon.modules.gather.frame.mouseEnabled and not addon.modules.mobtimer.frame.mouseEnabled)
assert(SabotonEssentialsDB.modules.gather.locked and SabotonEssentialsDB.modules.mobtimer.locked)
control("GATHER", "LOCKED").set(false)
button.scripts.OnClick(button, "RightButton")
assert(menu["Unlock bar movement"], "mixed state offers unlock")
menu["Unlock bar movement"]()
assert(not control("GATHER", "LOCKED").get() and not control("MOBTIMER", "LOCKED").get())
MenuUtil = nil
button.scripts.OnClick(button, "RightButton")
assert(said("Minimap menu unavailable"))

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
            if value ~= nil and not spec.hidden and not spec.transient then
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