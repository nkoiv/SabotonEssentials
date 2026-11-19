local now = 0
local frames = {}
local timers = {}
local module
local sounds = 0
local lastSoundPath
local burstTimers = {}

UIParent = {}
Enum = { PlayerSwingType = { MainHand = 0 } }
function GetTime() return now end
function issecretvalue(...) return false end
function PlaySoundFile(path, ...) sounds = sounds + 1 lastSoundPath = path return true end

C_Timer = {}
function C_Timer.NewTicker(_, callback)
    local timer = { callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
function C_Timer.NewTimer(_, callback)
    local timer = { callback = callback }
    function timer:Cancel() self.cancelled = true end
    burstTimers[#burstTimers + 1] = timer
    return timer
end
function C_Timer.After(_, callback) callback() end

function CreateFrame(...)
    local frame = { scripts = {} }
    function frame:SetSize(...) end
    function frame:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function frame:ClearAllPoints() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:CreateFontString(...)
        local text = {}
        function text:SetPoint(...) end
        function text:SetText(value) self.value = value end
        return text
    end
    frames[#frames + 1] = frame
    return frame
end

local addon = {
    Print = function() end,
    RegisterModule = function(_, value) module = value end,
}
assert(loadfile("src/Modules/ExtraAttack.lua"))("SabotonEssentials", addon)
module:OnEnable()
local options = module:GetOptionsSchema().options
assert(options[1].get() == true and options[1].default == true)
local sealOfCommandOption
local textEnabledOption, minBurstHitsOption
for _, option in ipairs(options) do
    if option.key == "countSealOfCommand" then sealOfCommandOption = option end
    if option.key == "textEnabled" then textEnabledOption = option end
    if option.key == "minBurstHits" then minBurstHitsOption = option end
end
assert(sealOfCommandOption and sealOfCommandOption.get() == false and sealOfCommandOption.default == false)
assert(textEnabledOption)
assert(minBurstHitsOption and minBurstHitsOption.get() == 1 and minBurstHitsOption.default == 1)
local display = frames[1]

module:HandleCommand("test")
assert(display.shown and display.x == 200 and display.y == 200)
assert(display.text.value == "x1 Ka-ching!")
display.scripts.OnUpdate(display, 0.45)
assert(math.abs(display.x - 280) < 0.001 and display.y > 200)
display.scripts.OnUpdate(display, 0.45)
assert(display.x == 360 and display.y == 145 and display.scripts.OnUpdate)

module:HandleCommand("test")
assert(display.x == 200 and display.y == 200 and display.text.value == "x2 Ka-ching!")
display.scripts.OnUpdate(display, 0.1)
module:HandleCommand("test")
assert(display.x == 200 and display.y == 200 and display.text.value == "x3 Ka-ching!")

local offsetX, offsetY
for _, option in ipairs(options) do
    if option.key == "textOffsetX" then offsetX = option end
    if option.key == "textOffsetY" then offsetY = option end
end
assert(offsetX and offsetY and offsetX.get() == 200 and offsetY.get() == 200)
assert(offsetX.default == 200 and offsetY.default == 200)
offsetX.set(200)
offsetY.set(-100)
assert(display.x == 200 and display.y == -100)
display.scripts.OnUpdate(display, 0.45)
assert(math.abs(display.x - 280) < 0.001 and math.abs(display.y - (-97.5)) < 0.001)
display.scripts.OnUpdate(display, 0.45)
assert(display.x == 360 and display.y == -155)
module:HandleCommand("xoffset -150")
module:HandleCommand("yoffset 80")
assert(offsetX.get() == -150 and offsetY.get() == 80)
assert(display.x == 10 and display.y == 25)
module:HandleCommand("xoffset 9999")
assert(offsetX.get() == -150)
module:HandleCommand("test")
assert(display.x == -150 and display.y == 80)

textEnabledOption.set(false)
assert(not display.shown and not display.scripts.OnUpdate)
textEnabledOption.set(true)
assert(display.shown)
now = 2
timers[1].callback()
assert(display.shown and timers[1].cancelled)
display.scripts.OnUpdate(display, 1.0)
assert(not display.shown and not display.scripts.OnUpdate)

module:HandleCommand("window 0.1")
module:HandleCommand("test")
assert(display.scripts.OnUpdate)
now = 2.2
timers[2].callback()
assert(display.shown and display.scripts.OnUpdate and timers[2].cancelled)
now = 3.5
display.scripts.OnUpdate(display, 1.3)
assert(not display.shown and not display.scripts.OnUpdate)

local movement, fade
for _, option in ipairs(options) do
    if option.key == "textArcDuration" then movement = option end
    if option.key == "textFadeDuration" then fade = option end
end
assert(movement and fade and movement.get() == 0.9 and fade.get() == 0.5)
movement.set(1.8)
fade.set(1.0)
module:HandleCommand("test")
now = 4.4
display.scripts.OnUpdate(display, 0.9)
assert(math.abs(display.x - (-70)) < 0.001 and display.alpha == 1)
now = 5.3
display.scripts.OnUpdate(display, 0.9)
assert(math.abs(display.x - 10) < 0.001 and math.abs(display.alpha - 1) < 0.001)
now = 5.8
display.scripts.OnUpdate(display, 0.5)
assert(math.abs(display.alpha - 0.5) < 0.001)
timers[3].callback()
module:HandleCommand("test")
assert(display.alpha == 1 and display.x == -150 and display.text.value == "x1 Ka-ching!")
now = 8.7
display.scripts.OnUpdate(display, 2.9)
assert(not display.shown and not display.scripts.OnUpdate)

local eventFrame = frames[2]
assert(eventFrame.events.PLAYER_SWING and eventFrame.events.SPELL_UPDATE_COOLDOWN)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
now = 10
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
now = 10.1
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
assert(display.shown)
local previousSounds = sounds
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == previousSounds + 1)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == previousSounds + 1)
now = 11
module:HandleCommand("test")
assert(display.text.value == "x1 Ka-ching!")

local soundOption
for _, option in ipairs(options) do
    if option.key == "soundKey" then soundOption = option end
end
local foundHuagh = false
for _, choice in ipairs(soundOption.choices) do
    if choice.value == "huagh" and choice.label == "HUAGH" then foundHuagh = true end
end
assert(foundHuagh)
module:HandleCommand("soundkey huagh")
assert(soundOption.get() == "huagh")
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(lastSoundPath == "Interface\\AddOns\\SabotonEssentials\\Media\\HumanMaleAggroA.ogg")

local function displayedComboCount()
    return tonumber(string.match(display.text.value, "^x(%d+) Ka%-ching!$"))
end
local comboBeforeWindfury = displayedComboCount()
local soundsBeforeWindfury = sounds
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 10608, nil, 0, nil)
assert(displayedComboCount() == comboBeforeWindfury + 1)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == soundsBeforeWindfury + 1)

eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516, nil, 0, nil)
assert(displayedComboCount() == comboBeforeWindfury + 2)
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 10610, nil, 0, nil)
assert(displayedComboCount() == comboBeforeWindfury + 3)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == soundsBeforeWindfury + 3)

eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 439440, nil, 0, nil)
assert(displayedComboCount() == comboBeforeWindfury + 5)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == soundsBeforeWindfury + 5)

local weaponRankSpellIDs = { 8232, 8235, 10486, 16362 }
for rank, spellID in ipairs(weaponRankSpellIDs) do
    eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", spellID, nil, 0, nil)
    assert(displayedComboCount() == comboBeforeWindfury + 5 + (rank * 2))
end
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == soundsBeforeWindfury + 13)

local comboAfterWindfury = displayedComboCount()
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 12345)
assert(displayedComboCount() == comboAfterWindfury)

local soundsBeforeSeal = sounds
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 20424, nil, 0, nil)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(displayedComboCount() == comboAfterWindfury)
assert(sounds == soundsBeforeSeal, "disabled Seal of Command detection must not play a sound")

sealOfCommandOption.set(true)
for _, spellID in ipairs({
    20375, 20915, 20918, 20919, 20920, -- Seal activation ranks
    20467, 20963, 20964, 20965, 20966, -- Judgement of Command ranks
}) do
    eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", spellID, nil, 0, nil)
end
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(displayedComboCount() == comboAfterWindfury)
assert(sounds == soundsBeforeSeal, "seal activation and Judgement must not play a sound")

eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 20424, nil, 0, nil)
assert(displayedComboCount() == comboAfterWindfury + 1)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == soundsBeforeSeal + 1, "a Seal of Command proc must play one sound")

sealOfCommandOption.set(false)
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 20424, nil, 0, nil)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(displayedComboCount() == comboAfterWindfury + 1 and sounds == soundsBeforeSeal + 1)

minBurstHitsOption.set(3)
local beforeThreshold = sounds
local comboBeforeThreshold = displayedComboCount()
local previousText = display.text.value
local previousAnimationStart = display.startedAt
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516)
local firstBurstTimer = burstTimers[#burstTimers]
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 10608)
assert(firstBurstTimer.cancelled)
burstTimers[#burstTimers].callback()
assert(sounds == beforeThreshold, "a burst below the minimum must be silent")
assert(display.text.value == previousText and display.startedAt == previousAnimationStart,
    "a burst below the minimum must not update or restart combo text")

eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 439440)
assert(display.text.value == previousText, "two hits must not show text when the minimum is three")
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516)
assert(displayedComboCount() == comboBeforeThreshold + 5, "a qualifying burst must show the full combo count")
burstTimers[#burstTimers].callback()
assert(sounds == beforeThreshold + 3, "a burst at the minimum must play the full cascade")

eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 439440)
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 439440)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == beforeThreshold + 7, "a burst above the minimum must play on combat end")

module:HandleCommand("minhits 2")
assert(minBurstHitsOption.get() == 2)
module:HandleCommand("minhits 2.5")
module:HandleCommand("minhits 0")
module:HandleCommand("minhits 11")
assert(minBurstHitsOption.get() == 2, "invalid thresholds must not change the setting")
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(sounds == beforeThreshold + 7, "separate bursts must not accumulate")
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 439440)
burstTimers[#burstTimers].callback()
assert(sounds == beforeThreshold + 9)

eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
now = 20
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
now = 20.05
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
burstTimers[#burstTimers].callback()
assert(sounds == beforeThreshold + 9, "a single early swing must be silent below the threshold")
local textBeforeSwingBurst = display.text.value
now = 22
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
now = 22.05
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
assert(display.text.value == textBeforeSwingBurst, "one early swing must not update text")
now = 22.1
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SWING", 2, 0)
assert(displayedComboCount() == 2, "a qualifying early-swing burst must show combo text")
burstTimers[#burstTimers].callback()
assert(sounds == beforeThreshold + 11, "a qualifying early-swing burst must play")

now = 25
textEnabledOption.set(false)
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516)
textEnabledOption.set(true)
assert(not display.shown, "enabling text must not reveal a new below-threshold combo")
eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 8516)
assert(display.shown and displayedComboCount() == 2, "text must appear when the burst reaches the minimum")

print("Extra Attack animation tests passed")