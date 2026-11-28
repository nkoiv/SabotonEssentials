local ADDON_NAME, addon = ...

-- Starts two countdown bars (min / max respawn) when the player loots a tracked, enabled
-- gatherable (ore or herb) from a world node. Direct node-spawn detection is impossible on the
-- Forever client (no game-object enumeration, no spawn event, no minimap-blip read), so this is
-- timer-based: the loot event is the trigger, and the respawn window is a configurable duration.
--
-- Trigger design (verified against forever-addon-kit): LOOT_READY / LOOT_OPENED fire and
-- GetLootSlotInfo / GetLootSlotLink / GetLootSourceInfo return plain (non-secret) values. Nodes
-- come through with a GameObject loot source, which distinguishes them from mob corpses.
--
-- Re-looting the same node restarts the timer: a node is usually picked 3-4 times before it
-- despawns, and the true respawn window starts at the final pick, so the last loot wins.
local GatheringTimer = {}

local DEBUG = false
local enabled = false
local locked = true
local barWidth = 220
local barHeight = 18
local orientation = "HORIZONTAL" -- or "VERTICAL"

local SOUND_OPTIONS = addon.TimerBars.SOUNDS

local DEFAULT_MIN = 300
local DEFAULT_MAX = 540

local GATHERABLES = {
    { itemID = 2772,  name = "Iron Ore",            kind = "ore",  enabled = false },
    { itemID = 3858,  name = "Mithril Ore",         kind = "ore",  enabled = false },
    { itemID = 7911,  name = "Truesilver Ore",      kind = "ore",  enabled = true },
    { itemID = 10620, name = "Thorium Ore",         kind = "ore",  enabled = true },
    { itemID = 248815, name = "Heavy Thorium Ore",  kind = "ore",  enabled = true },
    { itemID = 11370, name = "Dark Iron Ore",       kind = "ore",  enabled = false },
    { itemID = 13465, name = "Mountain Silversage", kind = "herb", enabled = false },
    { itemID = 13468, name = "Black Lotus",         kind = "herb", enabled = true },
}
local BUILTIN_COUNT = #GATHERABLES

local RARE_ITEMS = {
    { itemID = 12363, name = "Arcane Crystal" },
    { itemID = 248819, name = "Fel Crystal" },
    { itemID = 13468, name = "Black Lotus" },
}
local celebrationSettings = {}
local lootSession
local celebrationFrame
local reportedCelebrationError = {}

local minSoundKey = "ding"
local maxSoundKey = "thud"
local minTimerEnabled = true
local maxTimerEnabled = true
local minDuration = DEFAULT_MIN
local maxDuration = DEFAULT_MAX
local minDurationOverride = false
local maxDurationOverride = false
local active = nil
local savedPosition = nil

local function secret(v) return issecretvalue and issecretvalue(v) end

local function findSoundOption(key)
    for _, o in ipairs(SOUND_OPTIONS) do if o.key == key then return o end end
    return SOUND_OPTIONS[1]
end

local function playSound(key)
    local o = findSoundOption(key)
    if o.silent then return end
    local played = PlaySoundFile(o.path, "Master")
    if not played then addon.Print("Could not play " .. o.label .. ". Check " .. o.path .. ".") end
end

local function findEntry(itemID, itemName)
    for _, e in ipairs(GATHERABLES) do
        if itemID and e.itemID == itemID then return e end
    end
    if itemName then
        local needle = itemName:lower()
        for _, e in ipairs(GATHERABLES) do
            if e.name:lower() == needle then return e end
        end
        for _, e in ipairs(GATHERABLES) do
            if needle:find(e.name:lower(), 1, true) then return e end
        end
    end
    return nil
end

local function celebrationEntries()
    local entries, seen = {}, {}
    for _, entry in ipairs(RARE_ITEMS) do
        entries[#entries + 1] = { key = tostring(entry.itemID), itemID = entry.itemID, name = entry.name, default = true }
        seen[entry.itemID] = true
    end
    for index, entry in ipairs(GATHERABLES) do
        if not entry.itemID or not seen[entry.itemID] then
            entries[#entries + 1] = {
                key = entry.itemID and tostring(entry.itemID) or ("custom_" .. index),
                itemID = entry.itemID, name = entry.name, default = false,
            }
            if entry.itemID then seen[entry.itemID] = true end
        end
    end
    return entries
end

local function celebrationSetting(entry)
    if not celebrationSettings[entry.key] then
        celebrationSettings[entry.key] = { enabled = entry.default, sound = "kaching" }
    end
    return celebrationSettings[entry.key]
end

local function celebrationError(message)
    if not reportedCelebrationError[message] then
        addon.Print("Gathering celebration: " .. message)
        reportedCelebrationError[message] = true
    end
end

local function celebrate(entry)
    if not celebrationFrame then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetAllPoints(UIParent)
        frame:SetFrameStrata("HIGH")
        frame:EnableMouse(false)
        frame.particles = {}
        for index = 1, 16 do
            local particle = frame:CreateTexture(nil, "OVERLAY")
            particle:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
            particle:SetBlendMode("ADD")
            particle:SetSize(index % 3 == 0 and 30 or 20, index % 3 == 0 and 30 or 20)
            particle:SetVertexColor(1, 0.65 + (index % 3) * 0.15, 0.25 + (index % 2) * 0.5)
            frame.particles[index] = particle
        end
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            local progress = math.min(self.elapsed / 1.8, 1)
            for index, particle in ipairs(self.particles) do
                local angle = (index - 1) * math.pi * 2 / #self.particles
                local distance = 55 + progress * (140 + (index % 4) * 25)
                particle:ClearAllPoints()
                particle:SetPoint("CENTER", self, "CENTER",
                    math.cos(angle) * distance, math.sin(angle) * distance - 70 * progress * progress)
                particle:SetAlpha((1 - progress) * (0.65 + 0.35 * math.abs(math.sin(self.elapsed * 8 + index))))
            end
            if progress >= 1 then self:Hide() end
        end)
        celebrationFrame = frame
    end
    celebrationFrame.elapsed = 0
    celebrationFrame:Show()
    playSound(celebrationSetting(entry).sound)
end

local function findCelebration(itemID, itemName)
    for _, entry in ipairs(celebrationEntries()) do
        if itemID and entry.itemID == itemID then return entry end
        if not entry.itemID and itemName and entry.name:lower() == itemName:lower() then return entry end
    end
end

-- Match the client's localized self-loot formats, including positional format arguments.
local function matchesLootFormat(message, format)
    if type(format) ~= "string" then return false end
    local pattern, index = "^", 1
    while index <= #format do
        local rest = format:sub(index)
        local placeholder = rest:match("^%%(%d+%$[sd])") or rest:match("^%%([sd])")
        if placeholder then
            pattern = pattern .. (placeholder:sub(-1) == "d" and "%d+" or ".+")
            index = index + #placeholder + 1
        elseif rest:sub(1, 2) == "%%" then
            pattern = pattern .. "%%"
            index = index + 2
        else
            pattern = pattern .. format:sub(index, index):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            index = index + 1
        end
    end
    return message:match(pattern .. "$") ~= nil
end

local function onCelebrationLoot(message)
    if not enabled or not lootSession or type(message) ~= "string" or secret(message) then return end
    if not lootSession.open and GetTime() > lootSession.expires then lootSession = nil return end
    local mine = matchesLootFormat(message, LOOT_ITEM_SELF) or matchesLootFormat(message, LOOT_ITEM_SELF_MULTIPLE)
        or matchesLootFormat(message, LOOT_ITEM_PUSHED_SELF) or matchesLootFormat(message, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
    if not mine then
        if type(LOOT_ITEM_SELF) ~= "string" and type(LOOT_ITEM_SELF_MULTIPLE) ~= "string"
            and type(LOOT_ITEM_PUSHED_SELF) ~= "string" and type(LOOT_ITEM_PUSHED_SELF_MULTIPLE) ~= "string" then
            celebrationError("Self-loot message formats are unavailable; celebrations cannot confirm received items.")
        end
        return
    end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    if not itemID then return end
    local pending = lootSession.items[itemID]
    if pending and not pending.received then
        pending.received = true
        if celebrationSetting(pending.entry).enabled then celebrate(pending.entry) end
    end
end
local TimerBars = addon.TimerBars
local FLASH_SECONDS = TimerBars.FLASH_SECONDS

local function layoutFrame()
    local f = GatheringTimer.frame
    if not f then return end
    local vertical = orientation == "VERTICAL"
    -- A bar shows only while its timer is enabled and has not completed.
    local minShown = minTimerEnabled and active ~= nil and active.minSeconds > 0 and (not active.minFired or GetTime() < active.minFlashUntil)
    local maxShown = maxTimerEnabled and active ~= nil and active.maxSeconds > 0 and (not active.maxFired or GetTime() < active.maxFlashUntil)
    local preview = not locked and not minShown and not maxShown
    if preview then
        minShown = true
        f.minBar.flash:Hide()
        TimerBars.Update(f.minBar, "Gathering timer (drag to move)", 1, 0)
    end
    local n = (minShown and 1 or 0) + (maxShown and 1 or 0)
    local w = vertical and barHeight or barWidth
    local h = vertical and barWidth or barHeight
    for _, b in ipairs({ f.minBar, f.maxBar }) do
        b:SetSize(w, h)
        b.bar:SetOrientation(orientation)
    end
    local y = 0
    f.minBar:ClearAllPoints()
    f.maxBar:ClearAllPoints()
    if minShown then
        f.minBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        f.minBar.title:SetPoint("BOTTOMLEFT", f.minBar, "TOPLEFT", 0, 2)
        y = y + h + 16
    end
    if maxShown then
        f.maxBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        f.maxBar.title:SetPoint("BOTTOMLEFT", f.maxBar, "TOPLEFT", 0, 2)
        y = y + h + 16
    end
    f:SetSize((n > 0) and w or 1, (n > 0) and (y - 16) or 1)
    f.minBar:SetShown(minShown)
    f.maxBar:SetShown(maxShown)
    f.minBar.title:SetShown(minShown)
    f.maxBar.title:SetShown(maxShown)
    f:SetShown(n > 0)
end

local function updateBars()
    local f = GatheringTimer.frame
    if not f then return end
    if not active then
        layoutFrame()
        return
    end

    local elapsed = GetTime() - active.startedAt
    local function update(holder, duration, fired)
        if fired then return end -- completed bars are hidden by layoutFrame
        TimerBars.Update(holder, active.entryName, duration, elapsed)
    end
    if minTimerEnabled and active.minSeconds > 0 then update(f.minBar, active.minSeconds, active.minFired) end
    if maxTimerEnabled and active.maxSeconds > 0 then update(f.maxBar, active.maxSeconds, active.maxFired) end
end

function GatheringTimer:IsLocked()
    return locked
end

function GatheringTimer:SetLocked(value)
    locked = value
    if self.frame then
        TimerBars.RefreshMovable(self.frame)
        layoutFrame()
    end
end

local function stopTimers()
    active = nil
    updateBars()
end

local function startTimers(entry, testMode)
    active = {
        entryName = entry.name,
        -- The global sliders override per-entry values; 0 disables that bar entirely.
        minSeconds = not testMode and minDurationOverride and minDuration or (entry.minSeconds or DEFAULT_MIN),
        maxSeconds = not testMode and maxDurationOverride and maxDuration or (entry.maxSeconds or DEFAULT_MAX),
        startedAt = GetTime(),
        minFired = false,
        maxFired = false,
        minFlashUntil = 0,
        maxFlashUntil = 0,
        finishToken = nil,
    }
    local f = GatheringTimer.frame
    if f then
        f.minBar.flash:Hide()
        f.maxBar.flash:Hide()
    end
    layoutFrame()
    updateBars()
    if DEBUG then addon.Print("Timer started for " .. entry.name .. ".") end
end

local function onTick()
    if not active then return end
    local elapsed = GetTime() - active.startedAt
    local f = GatheringTimer.frame
    if minTimerEnabled and active.minSeconds > 0 and not active.minFired and elapsed >= active.minSeconds then
        active.minFired = true
        active.minFlashUntil = GetTime() + FLASH_SECONDS
        playSound(minSoundKey)
        if f then TimerBars.Flash(f.minBar) end
        if DEBUG then addon.Print(active.entryName .. " min reached - node may be up.") end
    end
    if maxTimerEnabled and active.maxSeconds > 0 and not active.maxFired and elapsed >= active.maxSeconds then
        active.maxFired = true
        active.maxFlashUntil = GetTime() + FLASH_SECONDS
        playSound(maxSoundKey)
        if f then TimerBars.Flash(f.maxBar) end
        if DEBUG then addon.Print(active.entryName .. " max reached - node gone or taken.") end
    end
    -- Once every enabled timer has completed, the run is over: flash fades, then clear.
    local minDone = not minTimerEnabled or active.minSeconds <= 0 or active.minFired
    local maxDone = not maxTimerEnabled or active.maxSeconds <= 0 or active.maxFired
    if minDone and maxDone and not active.finishToken then
        local finished = active
        local token = {}
        active.finishToken = token
        C_Timer.After(FLASH_SECONDS, function()
            if active == finished and active.finishToken == token then stopTimers() end
        end)
    end
    layoutFrame()
    updateBars()
end

local function captureLoot()
    if not GetNumLootItems then return end
    local n = GetNumLootItems()
    if secret(n) or n == 0 then return end
    local sourceGUID
    if GetLootSourceInfo then
        local ok, guid = pcall(GetLootSourceInfo, 1)
        if ok and not secret(guid) then sourceGUID = guid end
    end
    if sourceGUID and not sourceGUID:match("^GameObject") then return end
    -- No loot-window dedup on purpose: re-looting the same node must restart the timer. Duplicate
    -- LOOT_READY / LOOT_OPENED fires for a single pick just reset it twice at the same instant.
    local timerEntry
    for slot = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local itemID = link and not secret(link) and tonumber(link:match("item:(%d+)")) or nil
        local name = GetLootSlotInfo and (select(2, GetLootSlotInfo(slot))) or nil
        if secret(name) then name = nil end
        local celebration = findCelebration(itemID, name)
        if celebration and celebrationSetting(celebration).enabled and itemID then
            local slotSource = sourceGUID
            if slot ~= 1 and GetLootSourceInfo then
                local ok, guid = pcall(GetLootSourceInfo, slot)
                slotSource = ok and not secret(guid) and guid or nil
            end
            if slotSource and slotSource:match("^GameObject") then
                if not lootSession.items[itemID] then lootSession.items[itemID] = { entry = celebration } end
            else
                celebrationError("Loot source is unavailable; cannot confirm this item came from a gathering node.")
            end
        end
        local entry = findEntry(itemID, name)
        if not timerEntry and entry and entry.enabled then timerEntry = entry end
    end
    if timerEntry then
        if DEBUG then addon.Print(string.format("Looted tracked %s: %s", timerEntry.kind, timerEntry.name)) end
        startTimers(timerEntry)
    end
end
function GatheringTimer:GetOptionsSchema()
    local soundChoices = {}
    for _, o in ipairs(SOUND_OPTIONS) do soundChoices[#soundChoices + 1] = { value = o.key, label = o.label } end
    local opts = {
        { type = "checkbox", key = "enabled", label = "Enable Gathering Timer", section = "General",
          tooltip = "Master switch for loot detection and the timer bars.",
          default = false, get = function() return enabled end, set = function(v) enabled = v end },
        { type = "checkbox", key = "locked", label = "Lock frame position", section = "Appearance",
          tooltip = "Alt + left-drag visible bars out of combat even when locked. Uncheck for ordinary dragging and idle placeholders.",
          default = true, get = function() return locked end,
          set = function(v) GatheringTimer:SetLocked(v) end },
        { type = "checkbox", key = "minTimer", label = "Show 'may be up' timer (min)", section = "Respawn timers",
          tooltip = "Bar that completes when the node may have respawned.",
          default = true, get = function() return minTimerEnabled end,
          set = function(v) minTimerEnabled = v if active then active.finishToken = nil end layoutFrame() updateBars() end },
        { type = "slider", key = "minDuration", label = "'May be up' duration", min = 0, max = 900, step = 5,
          section = "Respawn timers", dependsOn = "minTimer",
          tooltip = "Seconds until the node may have respawned. 0 disables this bar.",
          default = DEFAULT_MIN, format = "%ds", get = function() return minDuration end,
          set = function(v) minDuration = v minDurationOverride = true if active then active.minSeconds = v active.finishToken = nil layoutFrame() updateBars() end end },
        { type = "checkbox", key = "maxTimer", label = "Show 'gone / taken' timer (max)", section = "Respawn timers",
          tooltip = "Bar that completes when the node is gone or was taken.",
          default = true, get = function() return maxTimerEnabled end,
          set = function(v) maxTimerEnabled = v if active then active.finishToken = nil end layoutFrame() updateBars() end },
        { type = "slider", key = "maxDuration", label = "'Gone / taken' duration", min = 0, max = 900, step = 5,
          section = "Respawn timers", dependsOn = "maxTimer",
          tooltip = "Seconds until the node is gone or was taken. 0 disables this bar.",
          default = DEFAULT_MAX, format = "%ds", get = function() return maxDuration end,
          set = function(v) maxDuration = v maxDurationOverride = true if active then active.maxSeconds = v active.finishToken = nil layoutFrame() updateBars() end end },
        { type = "slider", key = "width", label = "Bar width", min = 60, max = 500, step = 5,
          section = "Appearance",
          default = barWidth, format = "%dpx", get = function() return barWidth end,
          set = function(v) barWidth = v layoutFrame() end },
        { type = "slider", key = "height", label = "Bar height", min = 8, max = 60, step = 1,
          section = "Appearance",
          default = barHeight, format = "%dpx", get = function() return barHeight end,
          set = function(v) barHeight = v layoutFrame() end },
        { type = "dropdown", key = "orientation", label = "Bar orientation",
          section = "Appearance",
          tooltip = "Horizontal or vertical fill.", default = "HORIZONTAL",
          choices = { { value = "HORIZONTAL", label = "Horizontal" }, { value = "VERTICAL", label = "Vertical" } },
          get = function() return orientation end,
          set = function(v) orientation = v layoutFrame() end },
        { type = "dropdown", key = "minSound", label = "Sound: node may be up",
          section = "Sounds", dependsOn = "minTimer",
          tooltip = "Played when the min timer completes.", default = "ding",
          choices = soundChoices,
          get = function() return minSoundKey end, set = function(v) minSoundKey = v end },
        { type = "dropdown", key = "maxSound", label = "Sound: node gone / taken",
          section = "Sounds", dependsOn = "maxTimer",
          tooltip = "Played when the max timer completes.", default = "thud",
          choices = soundChoices,
          get = function() return maxSoundKey end, set = function(v) maxSoundKey = v end },
    }
    for index, e in ipairs(GATHERABLES) do
        opts[#opts + 1] = {
            type = "checkbox",
            key = index <= BUILTIN_COUNT and ("gather_" .. tostring(e.itemID)) or ("gather_custom_" .. index),
            section = "Nodes to track",
            label = e.name .. " (" .. e.kind .. ")",
            tooltip = string.format("Track %s. Respawn %ds-%ds.", e.name, e.minSeconds or DEFAULT_MIN, e.maxSeconds or DEFAULT_MAX),
            default = e.enabled,
            get = function() return e.enabled end,
            set = function(v) e.enabled = v end,
        }
    end
    for _, entry in ipairs(celebrationEntries()) do
        local setting = celebrationSetting(entry)
        local enabledKey = "celebrate_" .. entry.key
        opts[#opts + 1] = {
            type = "checkbox", key = enabledKey, section = "Gathering celebrations",
            label = "Celebrate " .. entry.name, default = entry.default,
            tooltip = "Show sparkles and play the selected sound when you receive this item from a gathering node.",
            get = function() return setting.enabled end,
            set = function(value) setting.enabled = value end,
        }
        opts[#opts + 1] = {
            type = "dropdown", key = "celebration_sound_" .. entry.key, section = "Gathering celebrations",
            label = entry.name .. " celebration sound", default = "kaching", dependsOn = enabledKey,
            choices = soundChoices,
            get = function() return setting.sound end,
            set = function(value)
                local sound = findSoundOption(value)
                if sound.key == value then setting.sound = value
                else addon.Print("Unknown celebration sound: " .. tostring(value)) end
            end,
        }
    end
    return { name = "Gathering Timer", enabledKey = "enabled", options = opts }
end

function GatheringTimer:GetPersistentState()
    local entries = {}
    for index, entry in ipairs(GATHERABLES) do
        if index <= BUILTIN_COUNT then
            entries[index] = { enabled = entry.enabled }
        else
            entries[index] = { itemID = entry.itemID, name = entry.name, kind = entry.kind, enabled = entry.enabled, minSeconds = entry.minSeconds, maxSeconds = entry.maxSeconds }
        end
    end
    local position = savedPosition and { x = savedPosition.x, y = savedPosition.y } or nil
    return { entries = entries, minDurationOverride = minDurationOverride, maxDurationOverride = maxDurationOverride, debug = DEBUG, position = position }
end

function GatheringTimer:LoadPersistentState(state)
    if type(state) ~= "table" then return end
    if type(state.debug) == "boolean" then DEBUG = state.debug end
    if type(state.entries) == "table" then
        for index = 1, BUILTIN_COUNT do
            local entry = state.entries[index]
            if type(entry) == "table" and type(entry.enabled) == "boolean" then GATHERABLES[index].enabled = entry.enabled end
        end
        for index = BUILTIN_COUNT + 1, #state.entries do
            local entry = state.entries[index]
            if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" and (entry.kind == "ore" or entry.kind == "herb") and type(entry.enabled) == "boolean" and type(entry.minSeconds) == "number" and entry.minSeconds >= 0 and type(entry.maxSeconds) == "number" and entry.maxSeconds >= 0 and (entry.itemID == nil or type(entry.itemID) == "number") then
                GATHERABLES[#GATHERABLES + 1] = { itemID = entry.itemID, name = entry.name, kind = entry.kind, enabled = entry.enabled, minSeconds = entry.minSeconds, maxSeconds = entry.maxSeconds }
            end
        end
    end
    local position = state.position
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" and position.x == position.x and position.y == position.y and math.abs(position.x) < math.huge and math.abs(position.y) < math.huge then
        savedPosition = { x = position.x, y = position.y }
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    end
end

function GatheringTimer:FinishRestore(state)
    if type(state) ~= "table" then return end
    minDurationOverride = state.minDurationOverride == true
    maxDurationOverride = state.maxDurationOverride == true
end

local function printStatus()
    addon.Print("Enabled: " .. (enabled and "yes" or "no"))
    addon.Print("Bars: min=" .. (minTimerEnabled and "on" or "off") .. " max=" .. (maxTimerEnabled and "on" or "off"))
    addon.Print(string.format("Size %dx%d, %s, %s", barWidth, barHeight, orientation:lower(), locked and "locked" or "unlocked"))
    if active then
        local elapsed = GetTime() - active.startedAt
        addon.Print(string.format("Active: %s elapsed %ds (min %ds / max %ds)", active.entryName, elapsed, active.minSeconds, active.maxSeconds))
    else
        addon.Print("Active: none")
    end
    local on = {}
    for _, e in ipairs(GATHERABLES) do if e.enabled then on[#on + 1] = e.name end end
    addon.Print("Tracking: " .. (#on > 0 and table.concat(on, ", ") or "none"))
end

function GatheringTimer:HandleCommand(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "test" then
        startTimers({ name = "Test Node", minSeconds = 5, maxSeconds = 10 }, true)
        addon.Print("Test bars started (5s / 10s).")
    elseif command == "clear" then
        stopTimers()
        addon.Print("Timers cleared.")
    elseif command == "enable" then
        enabled = not enabled
        addon.Print("Gathering Timer " .. (enabled and "enabled" or "disabled") .. ".")
    elseif command == "debug" then
        DEBUG = not DEBUG
        addon.Print("Debug " .. (DEBUG and "enabled" or "disabled") .. ".")
    elseif command == "lock" then
        self:SetLocked(true)
        addon.Print("Frame locked.")
    elseif command == "unlock" then
        self:SetLocked(false)
        addon.Print("Frame unlocked - drag with left button (out of combat).")
    elseif command == "width" or command == "height" then
        local v = tonumber(rest)
        if not v or v <= 0 then addon.Print("Usage: /saboton gather " .. command .. " <positive px>") return end
        if command == "width" then barWidth = v else barHeight = v end
        layoutFrame()
        addon.Print(command .. " set to " .. v .. "px.")
    elseif command == "orient" then
        local v = string.lower(rest)
        if v == "h" or v == "horizontal" then orientation = "HORIZONTAL"
        elseif v == "v" or v == "vertical" then orientation = "VERTICAL"
        else addon.Print("Usage: /saboton gather orient <h|v>") return end
        layoutFrame()
        addon.Print("Orientation: " .. orientation:lower() .. ".")
    elseif command == "min" or command == "max" then
        local v = tonumber(rest)
        if not v or v < 0 then addon.Print("Usage: /saboton gather " .. command .. " <seconds, 0 or more>") return end
        if command == "min" then minDuration = v minDurationOverride = true else maxDuration = v maxDurationOverride = true end
        if active then
            if command == "min" then active.minSeconds = v else active.maxSeconds = v end
            active.finishToken = nil
            layoutFrame()
            updateBars()
        end
        addon.Print(command .. " duration set to " .. v .. "s.")
    elseif command == "minsound" or command == "maxsound" then
        local key = string.lower(rest)
        local o = findSoundOption(key)
        if not o or o.key ~= key then
            addon.Print("Usage: /saboton gather " .. command .. " <none|ding|thud|kaching|squeak|huagh>")
        else
            if command == "minsound" then minSoundKey = key else maxSoundKey = key end
            addon.Print(command .. " set to " .. o.label .. ".")
        end
    elseif command == "celebrate" or command == "celebrationsound" or command == "testcelebration" then
        local name, soundKey = rest, nil
        if command == "celebrationsound" then name, soundKey = rest:match("^(.-)%s+(%S+)%s*$") end
        local found
        if name then
            local needle = name:lower():match("^%s*(.-)%s*$")
            for _, entry in ipairs(celebrationEntries()) do
                if entry.key == needle or entry.name:lower() == needle then found = entry break end
            end
        end
        if not found then
            addon.Print("Usage: /saboton gather " .. command .. " <exact item name|id>"
                .. (command == "celebrationsound" and " <none|ding|thud|kaching|squeak|huagh>" or ""))
        elseif command == "testcelebration" then
            celebrate(found)
        elseif command == "celebrate" then
            local setting = celebrationSetting(found)
            setting.enabled = not setting.enabled
            addon.Print(found.name .. " celebration " .. (setting.enabled and "enabled" or "disabled") .. ".")
        else
            local sound = findSoundOption(soundKey:lower())
            if sound.key ~= soundKey:lower() then
                addon.Print("Unknown celebration sound: " .. soundKey)
            else
                celebrationSetting(found).sound = sound.key
                addon.Print(found.name .. " celebration sound: " .. sound.label .. ".")
            end
        end
    elseif command == "toggle" then
        local arg = rest:lower()
        if arg == "" then addon.Print("Usage: /saboton gather toggle <name|id>") return end
        local found
        for _, e in ipairs(GATHERABLES) do
            if tostring(e.itemID) == arg or e.name:lower():find(arg, 1, true) then found = e break end
        end
        if not found then addon.Print("No gatherable matches '" .. rest .. "'.") return end
        found.enabled = not found.enabled
        addon.Print(found.name .. " " .. (found.enabled and "enabled" or "disabled") .. ".")
    elseif command == "add" then
        local idOrName, kind, mn, mx = rest:match("^(.-)%s+(%S+)%s+(%d+)%s+(%d+)%s*$")
        kind = kind and kind:lower()
        if not idOrName or idOrName == "" or (kind ~= "ore" and kind ~= "herb") then
            addon.Print("Usage: /saboton gather add <itemID|name> <ore|herb> <min> <max>")
            return
        end
        local id = tonumber(idOrName)
        local name = id and ("Item " .. id) or idOrName
        GATHERABLES[#GATHERABLES + 1] = {
            itemID = id, name = name, kind = kind,
            enabled = true, minSeconds = tonumber(mn), maxSeconds = tonumber(mx),
        }
        addon.Print("Added " .. name .. " (" .. kind .. ", " .. mn .. "s-" .. mx .. "s), enabled.")
    elseif command == "list" then
        for _, e in ipairs(GATHERABLES) do
            addon.Print(string.format("%s %s (%s, %s) %ds-%ds", e.enabled and "+" or "-", e.name, e.kind, tostring(e.itemID), e.minSeconds or DEFAULT_MIN, e.maxSeconds or DEFAULT_MAX))
        end
    elseif command == "status" then
        printStatus()
    else
        addon.Print("Commands: /saboton gather status, test, clear, enable, debug, lock, unlock, width <px>, height <px>, orient <h|v>, min <s>, max <s>, minsound <key>, maxsound <key>, toggle <name|id>, add <id|name> <ore|herb> <min> <max>, list, celebrate <name|id>, celebrationsound <name|id> <key>, testcelebration <name|id>")
    end
end

function GatheringTimer:OnEnable()
    local f = CreateFrame("Frame", "SabotonGatherTimerFrame", UIParent)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    TimerBars.MakeMovable(f, function() return locked end, function(x, y) savedPosition = { x = x, y = y } end)
    f:Hide()
    self.frame = f

    f.minBar = TimerBars.Create(f, "Node may be up", barWidth, barHeight, orientation)
    f.maxBar = TimerBars.Create(f, "Node gone / taken", barWidth, barHeight, orientation)
    layoutFrame()

    local events = CreateFrame("Frame")
    events:RegisterEvent("LOOT_READY")
    pcall(events.RegisterEvent, events, "LOOT_OPENED")
    events:RegisterEvent("LOOT_CLOSED")
    events:RegisterEvent("CHAT_MSG_LOOT")
    events:SetScript("OnEvent", function(_, event, message)
        if event == "LOOT_CLOSED" then
            if lootSession then lootSession.open, lootSession.expires = false, GetTime() + 2 end
        elseif event == "CHAT_MSG_LOOT" then
            onCelebrationLoot(message)
        elseif enabled then
            if not lootSession or not lootSession.open then lootSession = { open = true, items = {} } end
            captureLoot()
        end
    end)

    C_Timer.NewTicker(0.25, onTick)
end

addon.RegisterModule("gather", GatheringTimer)