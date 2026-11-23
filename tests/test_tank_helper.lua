local module, frame, alertFrame
local messages = {}
local sounds = {}
local soundSucceeds = true
local now = 100
local secret = {}
local unavailable

function issecretvalue(value) return value == secret end
function GetTime() return now end
function PlaySoundFile(path) sounds[#sounds + 1] = path return soundSucceeds end
UIParent = {}
function CreateFrame()
    local object = { events = {}, scripts = {} }
    function object:SetScript(name, callback) self.scripts[name] = callback end
    function object:RegisterEvent(event)
        if event == unavailable then error("event unavailable") end
        self.events[event] = true
    end
    function object:UnregisterAllEvents() self.events = {} end
    function object:SetSize() end
    function object:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function object:SetFrameStrata() end
    function object:SetClampedToScreen() end
    function object:SetBackdrop() end
    function object:SetBackdropColor() end
    function object:EnableMouse() end
    function object:SetAutoFocus() end
    function object:SetMaxLetters() end
    function object:ClearFocus() end
    function object:SetText(value) self.value = value end
    function object:GetText() return self.value or "" end
    function object:IsShown() return self.shown end
    function object:ClearAllPoints() end
    function object:SetAlpha(value) self.alpha = value end
    function object:Hide() self.shown = false end
    function object:Show() self.shown = true end
    function object:CreateFontString()
        local text = {}
        function text:SetPoint() end
        function text:SetWidth() end
        function text:SetJustifyH() end
        function text:SetText(value) self.value = value end
        return text
    end
    return object
end
local addon = {
    Print = function(message) messages[#messages + 1] = message end,
    RegisterModule = function(name, value) assert(name == "tankhelper") module = value end,
}
local spellNames = { [12345] = "Mock Strike", [12346] = "Mock Strike", [12347] = "Other Strike" }
C_Spell = {
    GetSpellName = function(id) return spellNames[id] end,
    GetSpellInfo = function(name)
        if name == "Mock Strike" then return { spellID = 12345 } end
    end,
}
local function has(text)
    for _, message in ipairs(messages) do
        if message:find(text, 1, true) then return true end
    end
    return false
end
local function clear() messages = {} end
local function event(name, ...)
    if alertFrame.events[name] then alertFrame.scripts.OnEvent(alertFrame, name, ...) end
    if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
end
local function option(key)
    for _, spec in ipairs(module:GetOptionsSchema().options) do
        if spec.key == key then return spec end
    end
    error("missing option " .. key)
end

assert(loadfile("src/Support/Spells.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/TimerBars.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Modules/TankHelper.lua"))("SabotonEssentials", addon)
module:OnEnable()
frame, alertFrame = module.frame, module.alertFrame
assert(next(frame.events) == nil)
module:HandleCommand("mark")
assert(has("start the probe first"))
clear()
unavailable = "COMBAT_TEXT_UPDATE"
module:HandleCommand("start")
assert(has("could not register COMBAT_TEXT_UPDATE"))
assert(frame.events.UNIT_COMBAT and frame.events.UNIT_SPELLCAST_SUCCEEDED)
assert(not frame.events.COMBAT_TEXT_UPDATE)
clear()
event("UNIT_SPELLCAST_SUCCEEDED", "target", "other-cast", 123)
event("UNIT_COMBAT", "party1", "WOUND", "", 0)
event("UNIT_COMBAT", secret, "WOUND", "", 0)
assert(#messages == 0, "unrelated and secret unit tokens must not be logged")
now = 102
event("PLAYER_REGEN_DISABLED")
now = 102.25
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 23922)
now = 102.30
event("UNIT_COMBAT", "target", "PARRY", "", 0, secret)
assert(has('+2.25s combat=0.25s: UNIT_SPELLCAST_SUCCEEDED 1="player" 2="cast-guid" 3=23922'))
assert(has('+2.30s combat=0.30s: UNIT_COMBAT 1="target" 2="PARRY" 3="" 4=0 5=<secret>'))
frame.scripts.OnEvent(frame, "COMBAT_TEXT_UPDATE", secret, "line\n|red")
assert(has('COMBAT_TEXT_UPDATE 1=<secret> 2="line ||red"'))
module:HandleCommand("mark")
assert(has("manual marker"))
now = 110
event("PLAYER_REGEN_ENABLED")
now = 111
event("PLAYER_TARGET_CHANGED")
assert(has("+11.00s: PLAYER_TARGET_CHANGED"))
module:HandleCommand("status")
assert(has("UNIT_SPELLCAST_SUCCEEDED=2"))
assert(has("UNIT_COMBAT=3"))
clear()
module:HandleCommand("start")
assert(has("already running"))
module:HandleCommand("stop")
assert(next(frame.events) == nil)
clear()
event("PLAYER_REGEN_DISABLED")
assert(#messages == 0)

unavailable = nil
module:HandleCommand("start")
assert(frame.events.COMBAT_TEXT_UPDATE)
clear()
for _ = 1, 125 do event("UNIT_COMBAT", "target", "WOUND", "", 1) end
assert(has("output capped"))
module:HandleCommand("status")
assert(has("UNIT_COMBAT=125"))
assert(has("120/120 event lines printed"))
module:HandleCommand("stop")
clear()
sounds = {}
now = 200
event("PLAYER_REGEN_DISABLED")
now = 202.25
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 11601)
now = 202.255
event("UNIT_COMBAT", "target", "DODGE", "", secret, 1)
assert(#sounds == 1 and sounds[1]:find("HumanMaleAggroA.ogg", 1, true))
assert(module.display.shown and module.display.text.value == "Spell 11601: DODGE")
assert(module.display.x == -200)
module.display.scripts.OnUpdate(module.display, 0.45)
assert(module.display.x == -280 and module.display.alpha == 1)
module.display.scripts.OnUpdate(module.display, 0.95)
assert(not module.display.shown and not module.display.scripts.OnUpdate)
event("UNIT_COMBAT", "target", "DODGE")
assert(#sounds == 1, "one cast must not produce multiple alerts")

local function cast(id) event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id or 23925) end
local function outcome(value) event("UNIT_COMBAT", "target", value) end
cast() outcome("MISS")
assert(#sounds == 2 and module.display.text.value == "Spell 23925: MISS")
cast() outcome("PARRY")
assert(#sounds == 3)
cast() outcome("WOUND") outcome("MISS")
assert(#sounds == 3, "a hit consumes the candidate cast")
cast() now = now + 0.011 outcome("MISS")
assert(#sounds == 3, "outside the correlation window")
cast() event("UNIT_COMBAT", "player", "DODGE") outcome("MISS")
assert(#sounds == 4, "incoming outcomes must not consume the cast")
cast() event("PLAYER_TARGET_CHANGED") outcome("MISS")
assert(#sounds == 4, "target changes invalidate the cast")
cast() event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 123) outcome("MISS")
assert(#sounds == 4, "untracked casts invalidate the prior cast")
cast() outcome(secret)
assert(#sounds == 4, "secret outcomes cannot be compared")
event("UNIT_SPELLCAST_SUCCEEDED", secret, "cast", 11601)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", secret)
outcome("MISS")
assert(#sounds == 4)
now = 220
cast() outcome("MISS")
assert(#sounds == 4, "20-second boundary is excluded")
option("fightWindow").set(30)
cast() outcome("MISS")
assert(#sounds == 5)
event("PLAYER_REGEN_ENABLED")
cast() outcome("MISS")
assert(#sounds == 5, "no alerts outside a known combat")
event("PLAYER_REGEN_DISABLED")
module:HandleCommand("enable")
cast() outcome("MISS")
assert(#sounds == 5)
module:HandleCommand("enable")
module:HandleCommand("add 12345")
cast(12345) outcome("MISS")
assert(#sounds == 6)
module:HandleCommand("remove 12345")
cast(12345) outcome("MISS")
assert(#sounds == 6)
local previous = option("spellList").get()
option("spellList").set("23922,invalid")
assert(option("spellList").get() == previous and has("comma-separated"))
option("spellList").set(" 12345, 12345, 11601 ")
assert(option("spellList").get() == "12345,11601")
option("textEnabled").set(false)
option("soundEnabled").set(false)
cast(12345) outcome("MISS")
assert(#sounds == 6 and not module.display.shown)
option("textEnabled").set(true)
option("soundEnabled").set(true)
module:HandleCommand("test")
assert(#sounds == 7 and module.display.shown)
event("PLAYER_REGEN_ENABLED")
now = 300
event("PLAYER_REGEN_DISABLED")
option("fightWindow").set(119)
assert(option("fightWindow").formatValue(119) == "119s")
assert(option("fightWindow").formatValue(120) == "Unlimited")
now = 418.99
cast(11601) outcome("MISS")
assert(#sounds == 8, "119-second window includes times before its boundary")
now = 419
cast(11601) outcome("MISS")
assert(#sounds == 8, "119-second window excludes its boundary")
module:HandleCommand("window 120")
assert(has("window: Unlimited"))
module:HandleCommand("alertstatus")
assert(has("window Unlimited"))
now = 600
cast(11601) outcome("MISS")
assert(#sounds == 9, "unlimited continues beyond 120 seconds")
event("PLAYER_REGEN_ENABLED")
cast(11601) outcome("MISS")
assert(#sounds == 9, "unlimited does not enable alerts outside combat")
module:HandleCommand("window 119")
assert(has("window: 119s"))
module:HandleCommand("add Mock Strike")
assert(option("spellFamilies").get() == "12345")
module:HandleCommand("add Mock Strike")
assert(option("spellFamilies").get() == "12345", "duplicate names do not add another family")
event("PLAYER_REGEN_DISABLED")
cast(12346) outcome("MISS")
assert(#sounds == 10 and module.display.text.value == "Mock Strike: MISS", "a different rank must match")
cast(12347) outcome("MISS")
assert(#sounds == 10, "a different named spell must not match")
module:HandleCommand("spells")
assert(has("Mock Strike (all ranks; ID 12345)"))
module:HandleCommand("remove Mock Strike")
assert(option("spellFamilies").get() == "")
assert(not option("spellList").get():find("12345", 1, true))
cast(12346) outcome("MISS")
assert(#sounds == 10)
module:HandleCommand("add Not a spell")
assert(has("Spell name not found"))
assert(option("spellFamilies").get() == "")
module:HandleCommand("add Mock Strike")
spellNames[12346] = nil
cast(12346) outcome("MISS")
assert(#sounds == 10 and has("all-rank matching may miss casts"), "unreadable names are reported")
module:HandleCommand("remove Mock Strike")
spellNames[11601] = "Revenge"
spellNames[12345] = "Mock Strike"
option("spellList").set("12345,11601")
local saves = 0
addon.SaveSettings = function() saves = saves + 1 end
module:HandleCommand("options")
local editor = module.spellEditor
assert(editor:IsShown() and editor.rows[1].text.value == "Mock Strike (1 rank)")
assert(editor.rows[2].text.value == "Revenge (1 rank)")
editor.input:SetText("Mock Strike")
editor.input.scripts.OnEnterPressed(editor.input)
assert(editor.input:GetText() == "" and saves == 1)
assert(editor.rows[1].text.value == "Mock Strike (all ranks + 1 ID)")
editor.rows[1].remove.scripts.OnClick(editor.rows[1].remove)
assert(option("spellFamilies").get() == "" and option("spellList").get() == "11601")
assert(saves == 2 and editor.rows[1].text.value == "Revenge (1 rank)")
editor.input:SetText("Not a spell")
editor.input.scripts.OnEnterPressed(editor.input)
assert(editor.input:GetText() == "Not a spell" and has("Spell name not found"))
option("spellList").set("1,2,3,4,5,6,7")
editor:Refresh()
assert(editor.pageLabel.value == "1 / 2")
editor.next.scripts.OnClick(editor.next)
assert(editor.pageLabel.value == "2 / 2" and editor.rows[1].text.value == "Spell 7 (1 rank)")
editor.rows[1].remove.scripts.OnClick(editor.rows[1].remove)
assert(editor.pageLabel.value == "1 / 1" and option("spellList").get() == "1,2,3,4,5,6")
editor.previous.scripts.OnClick(editor.previous)
assert(editor.pageLabel.value == "1 / 1")
for _, id in ipairs({ 23922, 23923, 23924, 23925 }) do spellNames[id] = "Shield Slam" end
for _, id in ipairs({ 6572, 6574, 7379, 11600, 11601 }) do spellNames[id] = "Revenge" end
option("spellList").set("23922,23923,23924,23925,6572,6574,7379,11600,11601")
editor:Refresh()
assert(editor.rows[1].text.value == "Shield Slam (4 ranks)")
assert(editor.rows[2].text.value == "Revenge (5 ranks)")
editor.rows[1].remove.scripts.OnClick(editor.rows[1].remove)
assert(option("spellList").get() == "6572,6574,7379,11600,11601")
module:HandleCommand("options")
assert(not editor:IsShown())
local soundCount = #sounds
assert(option("soundKey").get() == "huagh")
module:HandleCommand("soundkey thud")
module:HandleCommand("test")
assert(#sounds == soundCount + 1 and sounds[#sounds]:find("impact-thud.mp3", 1, true))
soundCount = #sounds
option("soundKey").set("none")
module:HandleCommand("test")
assert(#sounds == soundCount and module.display.shown)
option("soundKey").set("invalid")
assert(option("soundKey").get() == "none" and has("unknown sound"))
option("soundKey").set("kaching")
soundSucceeds = false
module:HandleCommand("test")
assert(has("could not play Ka-ching!"))
soundSucceeds = true
module:HandleCommand("xoffset -300")
module:HandleCommand("yoffset 100")
module:HandleCommand("movement 2")
module:HandleCommand("fade 1")
module:HandleCommand("test")
assert(module.display.x == -300 and module.display.y == 100)
module.display.scripts.OnUpdate(module.display, 1)
assert(module.display.x == -380 and module.display.alpha == 1)
module.display.scripts.OnUpdate(module.display, 1.5)
assert(math.abs(module.display.alpha - 0.5) < 0.001)
module.display.scripts.OnUpdate(module.display, 0.5)
assert(not module.display.shown)
module:HandleCommand("movement 0")
assert(option("textArcDuration").get() == 2 and has("Usage: /saboton missalerts movement"))
print("Tank helper diagnostic and alert tests passed")
