local ADDON_NAME, addon = ...

-- Plays a sound and tracks a combo streak when the player gets an extra attack (Windfury,
-- Hand of Justice, Ironfoe, Sword Specialization, etc.).
--
-- Detection note (measured on the WoW Forever beta client by forever-addon-kit):
-- the combat log cannot be registered by addons (COMBAT_LOG_EVENT(_UNFILTERED) taints the
-- addon and CombatLogGetCurrentEventInfo is gone), COMBAT_TEXT_UPDATE's "EXTRA_ATTACKS"
-- message never fires for real procs, and UNIT_COMBAT never fires for unit "player" (it
-- fires for "target", once per swing OUTCOME -- i.e. spaced by weapon speed -- so a burst
-- heuristic built on it can never see an extra attack). What DOES fire on this client is the
-- engine event PLAYER_SWING(swingDuration, swingType), for every auto attack, with plain
-- (non-secret) numbers. Extra attacks are delivered as main-hand swings, so a MainHand
-- PLAYER_SWING that arrives far earlier than the current swing duration is treated as an
-- extra attack. This is a timing heuristic and does not identify the triggering spell.
local ExtraAttack = {}

-- Sound choices selectable from the options dropdown; "key" is what soundKey stores.
local SOUND_OPTIONS = {
    { key = "none", label = "No sound", silent = true },
    { key = "kaching", label = "Ka-ching!", path = "Interface\\AddOns\\SabotonEssentials\\Media\\kaching.mp3" },
    { key = "squeak", label = "Squeaky Toy", path = "Interface\\AddOns\\SabotonEssentials\\Media\\squeak.mp3" },
}

local DEFAULT_COMBO_WINDOW = 1.0
local DEFAULT_COMBO_TEXT_FORMAT = "x%d Ka-ching!"
local TICKER_INTERVAL = 0.1
local DEFAULT_TEXT_ARC_DURATION = 0.9
local DEFAULT_TEXT_FADE_DURATION = 0.5
local DEFAULT_TEXT_OFFSET = 200
local TEXT_ARC_DISTANCE = 160
local TEXT_ARC_DROP = 55
local TEXT_ARC_HEIGHT = 30

-- MainHand swing-type value from Enum.PlayerSwingType, falling back to 0 per the kit's
-- documented enum (MainHand 0, OffHand 1, Ranged 2).
local MAIN_HAND = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand) or 0

local DEBUG = false
function ExtraAttack:GetPersistentState()
    return { debug = DEBUG }
end

function ExtraAttack:LoadPersistentState(state)
    if type(state) == "table" and type(state.debug) == "boolean" then DEBUG = state.debug end
end

local enabled = true
local comboWindow = DEFAULT_COMBO_WINDOW
local comboCount = 0
local comboExpireTime = 0
local ticker
local textEnabled = true
local comboTextFormat = DEFAULT_COMBO_TEXT_FORMAT
local textOffsetX = DEFAULT_TEXT_OFFSET
local textOffsetY = DEFAULT_TEXT_OFFSET
local textArcDuration = DEFAULT_TEXT_ARC_DURATION
local textFadeDuration = DEFAULT_TEXT_FADE_DURATION
local soundEnabled = true
local soundKey = "kaching"
local soundStagger = 0.09      -- seconds between the staggered sounds of a multi-hit burst
local burstSettleTime = 0.15   -- wait this long after the last burst hit before sounding it

-- Swing state for the detector. mhSwingDuration is learned from PLAYER_SWING itself, so it
-- tracks haste/flurry automatically and never touches UnitAttackSpeed (secret in combat).
local lastMHSwingAt = nil
local mhSwingDuration = nil

-- Burst state: how many early (extra-attack) swings have landed in the current burst. The
-- original auto attack that procced them arrives on-cadence, so it is not counted here. All
-- extra attacks from one proc land within a few ms of each other, so a short settle timer
-- after the last hit tells us the burst is complete and how big it was.
local burstHits = 0
local burstSettleTimer = nil

local function findSoundOption(key)
    for _, soundOption in ipairs(SOUND_OPTIONS) do
        if soundOption.key == key then
            return soundOption
        end
    end

    return SOUND_OPTIONS[1]
end

-- Plays the sound after `delay` seconds, pitched by `pitchSemitones` (0 = original). Pitching
-- up slightly on each successive sound of a burst gives the "ka-ka-ching" reverb feel.
-- PlaySoundFile's pitch argument is in semitones; clients without it ignore the extra arg.
local function playSoundAt(delay, pitchSemitones)
    if not soundEnabled then
        return
    end

    local soundOption = findSoundOption(soundKey)
    if soundOption.silent then
        return
    end
    local function play()
        local played = PlaySoundFile(soundOption.path, "Master", false, pitchSemitones)
        if not played then
            addon.Print("Could not play the " .. soundOption.label .. " sound. Check " .. soundOption.path .. ".")
        end
    end

    if delay > 0 then
        C_Timer.After(delay, play)
    else
        play()
    end
end

-- Called once the burst has settled (no new hits for `burstSettleTime`). Plays one sound per
-- hit: a single Windfury (1 hit) plays one normal ka-ching; a five-hit alignment plays a
-- staggered, rising ka-ka-ka-ka-ching.
local function playBurstCascade(hits)
    for i = 1, hits do
        playSoundAt((i - 1) * soundStagger, i - 1)  -- +1 semitone per sound
    end
end

-- Falls back to the default format if the customized one is missing its required %d, or is otherwise invalid.
local function formatComboText(count)
    local ok, formatted = pcall(string.format, comboTextFormat, count)
    if ok then
        return formatted
    end

    return string.format(DEFAULT_COMBO_TEXT_FORMAT, count)
end

local function updateComboDisplay()
    local display = ExtraAttack.comboDisplay
    if not textEnabled or comboCount <= 0 then
        display:SetScript("OnUpdate", nil)
        display:Hide()
        return
    end

    display.text:SetText(formatComboText(comboCount))
    display:Show()
end

local function resetCombo()
    comboCount = 0
    updateComboDisplay()
end

local function ensureTicker()
    if ticker then
        return
    end

    -- Patch 12.0.0 "Midnight": no combat log access, so nothing else drives this periodic check.
    ticker = C_Timer.NewTicker(TICKER_INTERVAL, function()
        if GetTime() >= comboExpireTime then
            comboCount = 0
            ticker:Cancel()
            ticker = nil
        end
    end)
end

local function createComboDisplay()
    local display = CreateFrame("Frame", nil, UIParent)
    display:SetSize(200, 40)
    display:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    display:Hide()

    local text = display:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    display.text = text

    return display
end

local function positionComboDisplay(display)
    local progress = math.min((display.arcElapsed or 0) / textArcDuration, 1)
    local offsetX = textOffsetX + TEXT_ARC_DISTANCE * progress
    local offsetY = textOffsetY - TEXT_ARC_DROP * progress + TEXT_ARC_HEIGHT * 4 * progress * (1 - progress)
    display:ClearAllPoints()
    display:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    return progress
end

local function animateComboDisplay(display, elapsed)
    display.arcElapsed = display.arcElapsed + elapsed
    local progress = positionComboDisplay(display)
    local fadeStart = math.max(comboExpireTime, display.startedAt + textArcDuration)
    local fadeProgress = math.max(0, (GetTime() - fadeStart) / textFadeDuration)
    display:SetAlpha(math.max(0, 1 - fadeProgress))
    if progress >= 1 and fadeProgress >= 1 then
        display:SetScript("OnUpdate", nil)
        display:Hide()
    end
end

local function restartComboAnimation()
    local display = ExtraAttack.comboDisplay
    display.arcElapsed = 0
    display.startedAt = GetTime()
    display:SetAlpha(1)
    positionComboDisplay(display)
    display:SetScript("OnUpdate", animateComboDisplay)
end

-- A burst is over when combat boundaries reset it (see the PLAYER_REGEN handlers) or when the
-- settle timer in handleProc completes without a new hit arriving.
local function resetBurst()
    burstHits = 0
    if burstSettleTimer then
        burstSettleTimer:Cancel()
        burstSettleTimer = nil
    end
end

local function flushBurst()
    local hits = burstHits
    resetBurst()
    playBurstCascade(hits)
    if DEBUG and hits > 0 then
        addon.Print("Burst settled: " .. hits .. " extra attack hit(s), cascade played.")
    end
end

-- One extra-attack hit landed. The combo text updates immediately; the sound waits for the
-- burst to settle so a multi-hit proc plays one cascade instead of overlapping sounds.
local function handleProc()
    if comboCount > 0 and GetTime() >= comboExpireTime then
        comboCount = 0
    end
    comboCount = comboCount + 1
    comboExpireTime = GetTime() + comboWindow
    updateComboDisplay()
    if textEnabled then
        restartComboAnimation()
    end
    ensureTicker()

    if burstSettleTimer then
        burstSettleTimer:Cancel()
    end
    burstSettleTimer = C_Timer.NewTimer(burstSettleTime, function()
        burstSettleTimer = nil
        flushBurst()
    end)

    if DEBUG then
        addon.Print("Extra attack hit " .. burstHits .. " in this burst. Combo: " .. comboCount)
    end
end

-- Core detector. PLAYER_SWING(swingDuration, swingType) fires once per auto attack with
-- plain numbers on this client. For a MainHand event: if it arrives far earlier than the
-- current swing duration allows, an extra attack landed -- vanilla extra attacks both deliver
-- as instant main-hand swings and reset the swing timer, so a normal auto-attack cadence can
-- normally cannot produce this. Other unusual timing changes can still affect detection.
--
-- False-positive guard: parry haste (a mob parrying you advances your swing timer by up to
-- 40%) also produces an early next swing. True extra attacks land at ~0-15% of the expected
-- interval (latency only), while a parry-hasted swing lands at 60-100%. Requiring the gap to
-- be under half the expected duration cleanly separates the two.
local EXTRA_ATTACK_MAX_GAP_FRACTION = 0.5

local function handleSwing(swingDuration, swingType)
    if issecretvalue(swingDuration) or issecretvalue(swingType) then
        return
    end
    if swingType ~= MAIN_HAND then
        return
    end

    local now = GetTime()

    if DEBUG then
        local gap = lastMHSwingAt and (now - lastMHSwingAt) or -1
        addon.Print(string.format("PLAYER_SWING mh: gap=%.3fs duration=%s",
            gap, tostring(swingDuration)))
    end

    local duration = tonumber(swingDuration)
    if duration and duration > 0 then
        mhSwingDuration = duration
    end

    if not enabled then
        lastMHSwingAt = now
        return
    end

    -- A swing arriving at less than half the expected interval is an extra attack. Normal
    -- swings arrive at ~100% of duration; parry-hasted swings at 60-100%; extra attacks at ~0%.
    local early = lastMHSwingAt and mhSwingDuration and (now - lastMHSwingAt) < (mhSwingDuration * EXTRA_ATTACK_MAX_GAP_FRACTION)
    if early then
        burstHits = burstHits + 1
        if DEBUG then
            addon.Print(string.format("Early main-hand swing: %.3fs into a %.2fs swing -> extra attack hit %d.",
                now - lastMHSwingAt, mhSwingDuration, burstHits))
        end
        handleProc()
    end

    lastMHSwingAt = now
end

local function printStatus()
    addon.Print("Enabled: " .. (enabled and "yes" or "no"))
    addon.Print("Sound: " .. (soundEnabled and findSoundOption(soundKey).label or "off"))
    addon.Print("Burst sounds: one ka-ching per hit, staggered " .. soundStagger .. "s and +1 semitone per hit")
    addon.Print("Text: " .. (textEnabled and ("'" .. comboTextFormat .. "'") or "off"))
    addon.Print(string.format("Text offset: horizontal %d, vertical %d", textOffsetX, textOffsetY))
    addon.Print(string.format("Text movement: %.1fs, fade: %.1fs", textArcDuration, textFadeDuration))
    addon.Print("Combo window: " .. comboWindow .. "s")
    addon.Print("Current combo: " .. comboCount)
    addon.Print("Detector: PLAYER_SWING early-swing (main-hand), duration "
        .. (mhSwingDuration and string.format("%.2fs", mhSwingDuration) or "not learned yet"))
end

-- Declarative schema consumed by the shared Options UI (src\Options.lua); no Settings-API code lives here.
function ExtraAttack:GetOptionsSchema()
    return {
        name = "Extra Attack",
        options = {
            {
                type = "checkbox",
                key = "enabled",
                label = "Enable Extra Attack",
                tooltip = "Master switch for the whole module (sound, combo text, and detection).",
                default = true,
                get = function() return enabled end,
                set = function(value)
                    enabled = value
                    if not enabled then
                        lastMHSwingAt = nil
                        resetBurst()
                        resetCombo()
                    end
                end,
            },
            {
                type = "slider",
                key = "comboWindow",
                label = "Combo streak window (seconds)",
                tooltip = "How long the combo streak keeps going without a new extra attack before it resets.",
                min = 0.1,
                max = 3.0,
                step = 0.1,
                default = DEFAULT_COMBO_WINDOW,
                format = "%.1fs",
                get = function() return comboWindow end,
                set = function(value) comboWindow = value end,
            },
            {
                type = "checkbox",
                key = "textEnabled",
                label = "Show combo text",
                tooltip = "Show the on-screen combo counter text.",
                default = true,
                get = function() return textEnabled end,
                set = function(value)
                    textEnabled = value
                    updateComboDisplay()
                    if textEnabled and comboCount > 0 then restartComboAnimation() end
                end,
            },
            {
                type = "checkbox",
                key = "soundEnabled",
                label = "Play sound",
                tooltip = "Play a sound on each extra attack proc.",
                default = true,
                get = function() return soundEnabled end,
                set = function(value) soundEnabled = value end,
            },
            {
                type = "dropdown",
                key = "soundKey",
                label = "Sound",
                tooltip = "Which sound plays when the trigger fires.",
                default = "kaching",
                choices = (function()
                    local choices = {}
                    for _, soundOption in ipairs(SOUND_OPTIONS) do
                        table.insert(choices, { value = soundOption.key, label = soundOption.label })
                    end
                    return choices
                end)(),
                get = function() return soundKey end,
                set = function(value) soundKey = value end,
            },
            {
                type = "slider",
                key = "soundStagger",
                label = "Burst stagger (seconds)",
                tooltip = "Seconds between the sounds of a multi-hit burst. A single extra attack plays one sound; N hits play N sounds, staggered and rising in pitch.",
                min = 0,
                max = 0.3,
                step = 0.01,
                default = 0.09,
                format = "%.2fs",
                get = function() return soundStagger end,
                set = function(value) soundStagger = value end,
            },
            {
                type = "text",
                key = "comboTextFormat",
                label = "Combo text (use %d for the combo count)",
                tooltip = "The on-screen combo text. %d is replaced with the combo count.",
                default = DEFAULT_COMBO_TEXT_FORMAT,
                get = function() return comboTextFormat end,
                set = function(value)
                    comboTextFormat = (value ~= nil and value ~= "") and value or DEFAULT_COMBO_TEXT_FORMAT
                    updateComboDisplay()
                end,
            },
            {
                type = "slider",
                key = "textOffsetX",
                label = "Combo text horizontal offset",
                tooltip = "Move the entire arc left or right from screen center.",
                min = -600, max = 600, step = 10, default = DEFAULT_TEXT_OFFSET, format = "%d",
                get = function() return textOffsetX end,
                set = function(value)
                    textOffsetX = value
                    positionComboDisplay(ExtraAttack.comboDisplay)
                end,
            },
            {
                type = "slider",
                key = "textOffsetY",
                label = "Combo text vertical offset",
                tooltip = "Move the entire arc up or down from screen center.",
                min = -400, max = 400, step = 10, default = DEFAULT_TEXT_OFFSET, format = "%d",
                get = function() return textOffsetY end,
                set = function(value)
                    textOffsetY = value
                    positionComboDisplay(ExtraAttack.comboDisplay)
                end,
            },
            {
                type = "slider",
                key = "textArcDuration",
                label = "Combo text movement time",
                tooltip = "Time in seconds to travel along the arc. Higher values move more slowly.",
                min = 0.2, max = 3.0, step = 0.1, default = DEFAULT_TEXT_ARC_DURATION, format = "%.1fs",
                get = function() return textArcDuration end,
                set = function(value) textArcDuration = value end,
            },
            {
                type = "slider",
                key = "textFadeDuration",
                label = "Combo text fade time",
                tooltip = "Time in seconds to fade after the arc and combo window finish.",
                min = 0.1, max = 3.0, step = 0.1, default = DEFAULT_TEXT_FADE_DURATION, format = "%.1fs",
                get = function() return textFadeDuration end,
                set = function(value) textFadeDuration = value end,
            },
        },
    }
end

function ExtraAttack:OnEnable()
    self.comboDisplay = createComboDisplay()

    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("PLAYER_SWING")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_SWING" then
            handleSwing(...)
            return
        end

        if event == "PLAYER_REGEN_DISABLED" then
            lastMHSwingAt = nil -- fresh fight: don't let the pre-combat state look like a burst
            resetBurst()
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            lastMHSwingAt = nil
            flushBurst()
            return
        end
    end)
end

function ExtraAttack:HandleCommand(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "test" then
        burstHits = burstHits + 1
        handleProc()
    elseif command == "enable" then
        enabled = not enabled
        if not enabled then
            lastMHSwingAt = nil
            resetBurst()
            resetCombo()
        end
        addon.Print("Extra Attack " .. (enabled and "enabled" or "disabled") .. ".")
    elseif command == "debug" then
        DEBUG = not DEBUG
        addon.Print("Debug " .. (DEBUG and "enabled" or "disabled") .. ".")
    elseif command == "window" then
        local seconds = tonumber(rest)
        if not seconds or seconds <= 0 then
            addon.Print("Usage: /saboton extraattack window <seconds>")
        else
            comboWindow = seconds
            addon.Print("Combo window set to " .. comboWindow .. "s.")
        end
    elseif command == "text" then
        textEnabled = not textEnabled
        updateComboDisplay()
        if textEnabled and comboCount > 0 then restartComboAnimation() end
        addon.Print("Combo text " .. (textEnabled and "enabled" or "disabled") .. ".")
    elseif command == "textformat" then
        if rest == "" then
            addon.Print("Usage: /saboton extraattack textformat <format, use %d for the combo count>")
        else
            comboTextFormat = rest
            updateComboDisplay()
            addon.Print("Combo text format set to '" .. rest .. "'.")
        end
    elseif command == "xoffset" or command == "yoffset" then
        local value = tonumber(rest)
        local limit = command == "xoffset" and 600 or 400
        if not value or value ~= value or value < -limit or value > limit then
            addon.Print("Usage: /saboton extraattack " .. command .. " <number from -" .. limit .. " to " .. limit .. ">")
        else
            value = math.floor(value / 10 + 0.5) * 10
            if command == "xoffset" then textOffsetX = value else textOffsetY = value end
            positionComboDisplay(self.comboDisplay)
            addon.Print("Combo text " .. command .. " set to " .. value .. ".")
        end
    elseif command == "sound" then
        soundEnabled = not soundEnabled
        addon.Print("Sound " .. (soundEnabled and "enabled" or "disabled") .. ".")
    elseif command == "soundkey" then
        local key = string.lower(rest)
        local soundOption = findSoundOption(key)
        if not soundOption or soundOption.key ~= key then
            addon.Print("Usage: /saboton extraattack soundkey <kaching|squeak>")
        else
            soundKey = soundOption.key
            addon.Print("Sound set to " .. soundOption.label .. ".")
        end
    elseif command == "stagger" then
        local seconds = tonumber(rest)
        if not seconds or seconds < 0 then
            addon.Print("Usage: /saboton extraattack stagger <seconds, 0 or more>")
        else
            soundStagger = seconds
            addon.Print("Burst stagger set to " .. soundStagger .. "s.")
        end
    elseif command == "status" then
        printStatus()
    else
        addon.Print("Commands: /saboton extraattack status, test, enable, debug, window <seconds>, text, textformat <format>, xoffset <number>, yoffset <number>, sound, soundkey <key>, stagger <seconds>")
    end
end

addon.RegisterModule("extraattack", ExtraAttack)
