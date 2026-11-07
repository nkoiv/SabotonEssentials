local ADDON_NAME, addon = ...

-- Plays a squeaky-toy sound when a unit dies, based on configurable death-type triggers.
local SqueakyToy = {}

local DEBUG = false

-- Sound choices selectable from the options dropdown; "key" is what options.soundKey stores.
local SOUND_OPTIONS = {
    { key = "none", label = "No sound", silent = true },
    { key = "squeak", label = "Squeaky Toy", path = "Interface\\AddOns\\SabotonEssentials\\Media\\squeak.mp3" },
    { key = "kaching", label = "Ka-ching!", path = "Interface\\AddOns\\SabotonEssentials\\Media\\kaching.mp3" },
}

-- Classes selectable from the options dropdown for the friendly-death trigger.
local CORE_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Not present in WoW Forever; valid per the class API but hidden from the dropdown/slash command by default.
local UNAVAILABLE_CLASS_TOKENS = { "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }

-- Testing toggles: the original ask (friendly class in party/raid) plus broader triggers for easier testing.
local options = {
    friendlyMages = true,
    anyHostileDeath = false,
    anyFriendlyDeath = false,
    triggerClass = "MAGE",
    soundKey = "squeak",
    showUnavailableClasses = false,
}

local function getAvailableClassTokens()
    if not options.showUnavailableClasses then
        return CORE_CLASS_TOKENS
    end

    local tokens = {}
    for _, token in ipairs(CORE_CLASS_TOKENS) do
        table.insert(tokens, token)
    end
    for _, token in ipairs(UNAVAILABLE_CLASS_TOKENS) do
        table.insert(tokens, token)
    end
    return tokens
end

local function findSoundOption(key)
    for _, soundOption in ipairs(SOUND_OPTIONS) do
        if soundOption.key == key then
            return soundOption
        end
    end

    return SOUND_OPTIONS[1]
end

-- Extra unit tokens to scan for non-group deaths (hostile/any-friendly testing modes).
local SCAN_UNIT_TOKENS = { "target", "focus", "mouseover" }
local MAX_NAMEPLATES = 40
local MAX_BOSS_UNITS = 5
local MAX_ARENA_UNITS = 5

local function findGroupUnitByGUID(guid)
    if UnitGUID("player") == guid then
        return "player"
    end

    local groupSize = GetNumGroupMembers()
    local unitPrefix = IsInRaid() and "raid" or "party"
    local unitCount = IsInRaid() and groupSize or groupSize - 1

    for index = 1, unitCount do
        local unit = unitPrefix .. index
        if UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

-- Broader lookup used only by the hostile/any-friendly testing toggles, since those
-- units are not guaranteed to be in the player's party or raid.
local function findAnyUnitByGUID(guid)
    local groupUnit = findGroupUnitByGUID(guid)
    if groupUnit then
        return groupUnit
    end

    for _, unit in ipairs(SCAN_UNIT_TOKENS) do
        if UnitGUID(unit) == guid then
            return unit
        end
    end

    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        if UnitGUID(unit) == guid then
            return unit
        end
    end

    for index = 1, MAX_BOSS_UNITS do
        local unit = "boss" .. index
        if UnitGUID(unit) == guid then
            return unit
        end
    end

    for index = 1, MAX_ARENA_UNITS do
        local unit = "arena" .. index
        if UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

local function isTriggerClass(unit)
    local className = select(2, UnitClass(unit))
    return className == options.triggerClass
end

local function playSqueak()
    local soundOption = findSoundOption(options.soundKey)
    if soundOption.silent then
        return
    end
    local played = PlaySoundFile(soundOption.path, "Master")
    if not played then
        addon.Print("Could not play the " .. soundOption.label .. " sound. Check " .. soundOption.path .. ".")
    end
end

local function handleUnitDied(unitGUID)
    if not unitGUID then
        return
    end

    -- Patch 12.0 "Secret Values": GUIDs for units that aren't player-controlled or in the
    -- party/raid are secret and cannot be compared with ==. Such a GUID can never match a
    -- group member's GUID anyway, so it's safe to bail out before any comparison happens.
    if issecretvalue(unitGUID) then
        return
    end

    if options.friendlyMages then
        local groupUnit = findGroupUnitByGUID(unitGUID)
        if groupUnit and isTriggerClass(groupUnit) then
            if DEBUG then
                addon.Print("Friendly " .. options.triggerClass .. " death detected: " .. (UnitName(groupUnit) or "unknown"))
            end
            playSqueak()
            return
        end
    end

    if options.anyHostileDeath or options.anyFriendlyDeath then
        local unit = findAnyUnitByGUID(unitGUID)
        if not unit then
            return
        end

        local isFriendly = UnitIsFriend("player", unit)
        if (options.anyHostileDeath and not isFriendly) or (options.anyFriendlyDeath and isFriendly) then
            if DEBUG then
                addon.Print("Unit death detected: " .. (UnitName(unit) or "unknown"))
            end
            playSqueak()
        end
    end
end

local function printStatus()
    addon.Print("Friendly class (party/raid) trigger: " .. (options.friendlyMages and "ON" or "off") .. " (class: " .. options.triggerClass .. ")")
    addon.Print("Any hostile unit death trigger: " .. (options.anyHostileDeath and "ON" or "off"))
    addon.Print("Any friendly unit death trigger: " .. (options.anyFriendlyDeath and "ON" or "off"))
    addon.Print("Sound: " .. findSoundOption(options.soundKey).label)
end

-- Declarative schema consumed by the shared Options UI (src\Options.lua); no Settings-API code lives here.
function SqueakyToy:GetOptionsSchema()
    return {
        name = "Squeaky Toy",
        options = {
            {
                type = "checkbox",
                key = "friendlyMages",
                label = "Friendly character death (party/raid)",
                tooltip = "Play the squeak when a Mage in your party or raid dies.",
                default = true,
                get = function() return options.friendlyMages end,
                set = function(value) options.friendlyMages = value end,
            },
            {
                type = "checkbox",
                key = "anyHostileDeath",
                label = "Any hostile unit death (testing)",
                tooltip = "Play the squeak when any hostile unit dies. Intended for testing.",
                default = false,
                get = function() return options.anyHostileDeath end,
                set = function(value) options.anyHostileDeath = value end,
            },
            {
                type = "checkbox",
                key = "anyFriendlyDeath",
                label = "Any friendly unit death (testing)",
                tooltip = "Play the squeak when any friendly unit dies. Intended for testing.",
                default = false,
                get = function() return options.anyFriendlyDeath end,
                set = function(value) options.anyFriendlyDeath = value end,
            },
            {
                type = "dropdown",
                key = "triggerClass",
                label = "Class to watch for (party/raid death)",
                tooltip = "Which class's death triggers the sound.",
                default = "MAGE",
                choices = function()
                    local choices = {}
                    for _, classToken in ipairs(getAvailableClassTokens()) do
                        table.insert(choices, { value = classToken, label = LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken })
                    end
                    return choices
                end,
                get = function() return options.triggerClass end,
                set = function(value) options.triggerClass = value end,
            },
            {
                type = "checkbox",
                key = "showUnavailableClasses",
                label = "Show classes not in WoW Forever",
                tooltip = "Also list Death Knight, Monk, Demon Hunter, and Evoker in the class dropdown above.",
                default = false,
                get = function() return options.showUnavailableClasses end,
                set = function(value) options.showUnavailableClasses = value end,
            },
            {
                type = "dropdown",
                key = "soundKey",
                label = "Sound",
                tooltip = "Which sound plays when the trigger fires.",
                default = "squeak",
                choices = (function()
                    local choices = {}
                    for _, soundOption in ipairs(SOUND_OPTIONS) do
                        table.insert(choices, { value = soundOption.key, label = soundOption.label })
                    end
                    return choices
                end)(),
                get = function() return options.soundKey end,
                set = function(value) options.soundKey = value end,
            },
        },
    }
end

function SqueakyToy:OnEnable()
    -- Patch 12.0.0 (Midnight) moved UNIT_DIED off the combat log; addons can no longer register CLEU at all.
    -- On Forever, registering an event this client lacks throws and would abort this handler, so guard it.
    self.frame = CreateFrame("Frame")
    local ok = pcall(self.frame.RegisterEvent, self.frame, "UNIT_DIED")
    if not ok then
        addon.Print("UNIT_DIED is not available on this client; Squeaky Toy is inactive.")
        return
    end
    self.frame:SetScript("OnEvent", function(_, _, unitGUID)
        handleUnitDied(unitGUID)
    end)
end

function SqueakyToy:HandleCommand(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "test" then
        playSqueak()
    elseif command == "debug" then
        DEBUG = not DEBUG
        addon.Print("Debug " .. (DEBUG and "enabled" or "disabled") .. ".")
    elseif command == "mages" then
        options.friendlyMages = not options.friendlyMages
        addon.Print("Friendly mage trigger " .. (options.friendlyMages and "enabled" or "disabled") .. ".")
    elseif command == "hostile" then
        options.anyHostileDeath = not options.anyHostileDeath
        addon.Print("Any hostile unit death trigger " .. (options.anyHostileDeath and "enabled" or "disabled") .. ".")
    elseif command == "friendly" then
        options.anyFriendlyDeath = not options.anyFriendlyDeath
        addon.Print("Any friendly unit death trigger " .. (options.anyFriendlyDeath and "enabled" or "disabled") .. ".")
    elseif command == "class" then
        local classToken = string.upper(rest)
        local availableTokens = getAvailableClassTokens()
        if not tContains(availableTokens, classToken) then
            addon.Print("Usage: /saboton squeak class <" .. table.concat(availableTokens, "|") .. ">")
        else
            options.triggerClass = classToken
            addon.Print("Trigger class set to " .. classToken .. ".")
        end
    elseif command == "sound" then
        local soundKey = string.lower(rest)
        local soundOption = findSoundOption(soundKey)
        if not soundOption or soundOption.key ~= soundKey then
            addon.Print("Usage: /saboton squeak sound <none|squeak|kaching>")
        else
            options.soundKey = soundOption.key
            addon.Print("Sound set to " .. soundOption.label .. ".")
        end
    elseif command == "status" then
        printStatus()
    else
        addon.Print("Commands: /saboton squeak status, test, debug, mages, hostile, friendly, class <token>, sound <key>")
    end
end

addon.RegisterModule("squeak", SqueakyToy)
