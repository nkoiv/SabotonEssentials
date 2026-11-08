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
local enabled = true
local locked = true
local barWidth = 220
local barHeight = 18
local orientation = "HORIZONTAL" -- or "VERTICAL"

local SOUND_OPTIONS = {
    { key = "none", label = "No sound", silent = true },
    { key = "ding", label = "Bell chime (may be up)", path = "Interface\\AddOns\\SabotonEssentials\\Media\\clear-bell-chime.mp3" },
    { key = "thud", label = "Impact thud (gone / taken)", path = "Interface\\AddOns\\SabotonEssentials\\Media\\impact-thud.mp3" },
    { key = "kaching", label = "Ka-ching!", path = "Interface\\AddOns\\SabotonEssentials\\Media\\kaching.mp3" },
    { key = "squeak", label = "Squeaky Toy", path = "Interface\\AddOns\\SabotonEssentials\\Media\\squeak.mp3" },
}

local DEFAULT_MIN = 300
local DEFAULT_MAX = 540

local GATHERABLES = {
    { itemID = 2770,  name = "Copper Ore",          kind = "ore",  enabled = false },
    { itemID = 2771,  name = "Tin Ore",             kind = "ore",  enabled = false },
    { itemID = 2772,  name = "Iron Ore",            kind = "ore",  enabled = false },
    { itemID = 3858,  name = "Mithril Ore",         kind = "ore",  enabled = false },
    { itemID = 7911,  name = "Truesilver Ore",      kind = "ore",  enabled = true },
    { itemID = 10620, name = "Thorium Ore",         kind = "ore",  enabled = true },
    { itemID = 12363, name = "Arcane Crystal",      kind = "ore",  enabled = true },
    { itemID = 11370, name = "Dark Iron Ore",       kind = "ore",  enabled = false },
    { itemID = 2447,  name = "Peacebloom",          kind = "herb", enabled = false },
    { itemID = 765,   name = "Silverleaf",          kind = "herb", enabled = false },
    { itemID = 2449,  name = "Earthroot",           kind = "herb", enabled = false },
    { itemID = 785,   name = "Mageroyal",           kind = "herb", enabled = false },
    { itemID = 2450,  name = "Briarthorn",          kind = "herb", enabled = false },
    { itemID = 3355,  name = "Wild Steelbloom",     kind = "herb", enabled = false },
    { itemID = 3821,  name = "Goldthorn",           kind = "herb", enabled = false },
    { itemID = 8838,  name = "Sungrass",            kind = "herb", enabled = false },
    { itemID = 13465, name = "Mountain Silversage", kind = "herb", enabled = false },
    { itemID = 13468, name = "Black Lotus",         kind = "herb", enabled = true },
}
local BUILTIN_COUNT = #GATHERABLES

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
local function makeBar(parent, label)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(barWidth, barHeight)

    -- Keep the StatusBar on a lower frame level than the text/flash and draw its fill on the
    -- BACKGROUND layer, so the label stays readable over the filled portion of the bar.
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetAllPoints()
    bar:SetFrameLevel(math.max(holder:GetFrameLevel() - 1, 0))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetDrawLayer("BACKGROUND")
    bar:SetOrientation(orientation)
    holder.bar = bar

    -- Light outline marking the bar's total length, so the unfilled remainder is still visible.
    for _, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = holder:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0, 0, 0, 0.8)
        if point == "TOP" then
            edge:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", -1, 0)
            edge:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 1, 0)
            edge:SetHeight(1)
        elseif point == "BOTTOM" then
            edge:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -1, 0)
            edge:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 1, 0)
            edge:SetHeight(1)
        elseif point == "LEFT" then
            edge:SetPoint("TOPRIGHT", holder, "TOPLEFT", 0, 1)
            edge:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", 0, -1)
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPLEFT", holder, "TOPRIGHT", 0, 1)
            edge:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 0, -1)
            edge:SetWidth(1)
        end
    end

    -- Brief white flash overlaid when the timer completes, then the whole bar hides.
    local flash = holder:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1, 1, 1, 0.6)
    flash:Hide()
    holder.flash = flash

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    holder.text = text

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText(label)
    holder.title = title
    return holder
end

local FLASH_SECONDS = 1.5
local function flashBar(holder)
    holder.flash:Show()
    holder.flash:SetAlpha(0.9)
    UIFrameFadeOut(holder.flash, FLASH_SECONDS, 0.9, 0)
end

local function layoutFrame()
    local f = GatheringTimer.frame
    if not f then return end
    local vertical = orientation == "VERTICAL"
    -- A bar shows only while its timer is enabled and has not completed.
    local minShown = minTimerEnabled and active ~= nil and active.minSeconds > 0 and (not active.minFired or GetTime() < active.minFlashUntil)
    local maxShown = maxTimerEnabled and active ~= nil and active.maxSeconds > 0 and (not active.maxFired or GetTime() < active.maxFlashUntil)
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
        f.minBar:SetShown(false)
        f.maxBar:SetShown(false)
        f.minBar.title:SetShown(false)
        f.maxBar.title:SetShown(false)
        f:SetShown(false)
        return
    end
    local elapsed = GetTime() - active.startedAt
    local function update(holder, duration, fired)
        if fired then return end -- completed bars are hidden by layoutFrame
        local frac = duration > 0 and math.min(elapsed / duration, 1) or 1
        holder.bar:SetValue(frac)
        holder.bar:SetStatusBarColor(0.2, 0.6, 1)
        local remaining = math.ceil(math.max(duration - elapsed, 0))
        holder.text:SetText(active.entryName .. " " .. string.format("%d:%02d", math.floor(remaining / 60), remaining % 60))
    end
    update(f.minBar, active.minSeconds, active.minFired)
    update(f.maxBar, active.maxSeconds, active.maxFired)
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
        if f then flashBar(f.minBar) end
        if DEBUG then addon.Print(active.entryName .. " min reached - node may be up.") end
    end
    if maxTimerEnabled and active.maxSeconds > 0 and not active.maxFired and elapsed >= active.maxSeconds then
        active.maxFired = true
        active.maxFlashUntil = GetTime() + FLASH_SECONDS
        playSound(maxSoundKey)
        if f then flashBar(f.maxBar) end
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
    for slot = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local itemID = link and not secret(link) and tonumber(link:match("item:(%d+)")) or nil
        local name = GetLootSlotInfo and (select(2, GetLootSlotInfo(slot))) or nil
        if secret(name) then name = nil end
        local entry = findEntry(itemID, name)
        if entry and entry.enabled then
            if DEBUG then addon.Print(string.format("Looted tracked %s: %s (id %s)", entry.kind, entry.name, tostring(itemID))) end
            startTimers(entry)
            return
        end
    end
end
function GatheringTimer:GetOptionsSchema()
    local soundChoices = {}
    for _, o in ipairs(SOUND_OPTIONS) do soundChoices[#soundChoices + 1] = { value = o.key, label = o.label } end
    local opts = {
        { type = "checkbox", key = "enabled", label = "Enable Gathering Timer",
          tooltip = "Master switch for loot detection and the timer bars.",
          default = true, get = function() return enabled end, set = function(v) enabled = v end },
        { type = "checkbox", key = "locked", label = "Lock frame position",
          tooltip = "Uncheck to drag the timer bars around with the left mouse button (out of combat).",
          default = true, get = function() return locked end,
          set = function(v)
              locked = v
              if GatheringTimer.frame then GatheringTimer.frame:EnableMouse(not v) end
          end },
        { type = "checkbox", key = "minTimer", label = "Show 'may be up' timer (min)",
          tooltip = "Bar that completes when the node may have respawned.",
          default = true, get = function() return minTimerEnabled end,
          set = function(v) minTimerEnabled = v if active then active.finishToken = nil end layoutFrame() updateBars() end },
        { type = "slider", key = "minDuration", label = "'May be up' duration", min = 0, max = 900, step = 5,
          tooltip = "Seconds until the node may have respawned. 0 disables this bar.",
          default = DEFAULT_MIN, format = "%ds", get = function() return minDuration end,
          set = function(v) minDuration = v minDurationOverride = true if active then active.minSeconds = v active.finishToken = nil layoutFrame() updateBars() end end },
        { type = "checkbox", key = "maxTimer", label = "Show 'gone / taken' timer (max)",
          tooltip = "Bar that completes when the node is gone or was taken.",
          default = true, get = function() return maxTimerEnabled end,
          set = function(v) maxTimerEnabled = v if active then active.finishToken = nil end layoutFrame() updateBars() end },
        { type = "slider", key = "maxDuration", label = "'Gone / taken' duration", min = 0, max = 900, step = 5,
          tooltip = "Seconds until the node is gone or was taken. 0 disables this bar.",
          default = DEFAULT_MAX, format = "%ds", get = function() return maxDuration end,
          set = function(v) maxDuration = v maxDurationOverride = true if active then active.maxSeconds = v active.finishToken = nil layoutFrame() updateBars() end end },
        { type = "slider", key = "width", label = "Bar width", min = 60, max = 500, step = 5,
          default = barWidth, format = "%dpx", get = function() return barWidth end,
          set = function(v) barWidth = v layoutFrame() end },
        { type = "slider", key = "height", label = "Bar height", min = 8, max = 60, step = 1,
          default = barHeight, format = "%dpx", get = function() return barHeight end,
          set = function(v) barHeight = v layoutFrame() end },
        { type = "dropdown", key = "orientation", label = "Bar orientation",
          tooltip = "Horizontal or vertical fill.", default = "HORIZONTAL",
          choices = { { value = "HORIZONTAL", label = "Horizontal" }, { value = "VERTICAL", label = "Vertical" } },
          get = function() return orientation end,
          set = function(v) orientation = v layoutFrame() end },
        { type = "dropdown", key = "minSound", label = "Sound: node may be up",
          tooltip = "Played when the min timer completes.", default = "ding",
          choices = soundChoices,
          get = function() return minSoundKey end, set = function(v) minSoundKey = v end },
        { type = "dropdown", key = "maxSound", label = "Sound: node gone / taken",
          tooltip = "Played when the max timer completes.", default = "thud",
          choices = soundChoices,
          get = function() return maxSoundKey end, set = function(v) maxSoundKey = v end },
    }
    for index, e in ipairs(GATHERABLES) do
        opts[#opts + 1] = {
            type = "checkbox",
            key = index <= BUILTIN_COUNT and ("gather_" .. tostring(e.itemID)) or ("gather_custom_" .. index),
            label = e.name .. " (" .. e.kind .. ")",
            tooltip = string.format("Track %s. Respawn %ds-%ds.", e.name, e.minSeconds or DEFAULT_MIN, e.maxSeconds or DEFAULT_MAX),
            default = e.enabled,
            get = function() return e.enabled end,
            set = function(v) e.enabled = v end,
        }
    end
    return { name = "Gathering Timer", options = opts }
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
        locked = true
        self.frame:EnableMouse(false)
        addon.Print("Frame locked.")
    elseif command == "unlock" then
        locked = false
        self.frame:EnableMouse(true)
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
            addon.Print("Usage: /saboton gather " .. command .. " <none|ding|thud|kaching|squeak>")
        else
            if command == "minsound" then minSoundKey = key else maxSoundKey = key end
            addon.Print(command .. " set to " .. o.label .. ".")
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
        addon.Print("Commands: /saboton gather status, test, clear, enable, debug, lock, unlock, width <px>, height <px>, orient <h|v>, min <s>, max <s>, minsound <key>, maxsound <key>, toggle <name|id>, add <id|name> <ore|herb> <min> <max>, list")
    end
end

function GatheringTimer:OnEnable()
    local f = CreateFrame("Frame", "SabotonGatherTimerFrame", UIParent)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if x and y and parentX and parentY then savedPosition = { x = x - parentX, y = y - parentY } end
        if addon.SaveSettings then addon.SaveSettings() end
    end)
    f:Hide()
    self.frame = f

    f.minBar = makeBar(f, "Node may be up")
    f.maxBar = makeBar(f, "Node gone / taken")
    layoutFrame()

    local events = CreateFrame("Frame")
    events:RegisterEvent("LOOT_READY")
    pcall(events.RegisterEvent, events, "LOOT_OPENED")
    events:SetScript("OnEvent", function()
        if enabled then captureLoot() end
    end)

    C_Timer.NewTicker(0.25, onTick)
end

addon.RegisterModule("gather", GatheringTimer)