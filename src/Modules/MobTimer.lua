local ADDON_NAME, addon = ...

local MobTimer = {}
local bars = addon.TimerBars
local entries, active, holders, spareHolders = {}, {}, {}, {}
local nextID = 1
local selected = 1
local detectionEnabled = true
local locked, width, height, orientation = true, 220, 18, "HORIZONTAL"
local minEnabled, maxEnabled = true, true
local minSound, maxSound = "ding", "thud"
local position
local MAX_ENTRIES, MAX_SECONDS = 30, 604800
local DEFAULT_MIN, DEFAULT_MAX = 600, 900
local sounds = bars.SOUNDS
local observed, deaths, reportedErrors = {}, {}, {}
local lastScan = -1
local detectionAvailable = false
local counts = { matched = 0, unmatched = 0, secret = 0, duplicate = 0 }
local CACHE_SECONDS, CACHE_LIMIT = 1800, 256

local function sound(key)
    for _, item in ipairs(sounds) do
        if item.key == key then
            if item.path and not PlaySoundFile(item.path, "Master") then addon.Print("Could not play " .. item.label .. ".") end
            return
        end
    end
    addon.Print("Unknown mob timer sound: " .. tostring(key))
end

local function escape(text) return text:gsub("|", "||") end
local function save() if addon.SaveSettings then addon.SaveSettings() end end
local function validNumber(value)
    return type(value) == "number" and value == value and value >= 1 and value <= MAX_SECONDS and value == math.floor(value)
end

local function validate(name, minSeconds, maxSeconds, ignoreID)
    if type(name) ~= "string" then return nil, "Enter a mob name." end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 100 or name:find("[%c|]") then return nil, "Enter a mob name of 1-100 characters without control characters or |." end
    if not validNumber(minSeconds) or not validNumber(maxSeconds) or minSeconds > maxSeconds then
        return nil, "Enter whole seconds from 1 to 604800, with minimum no greater than maximum."
    end
    for _, entry in ipairs(entries) do
        if entry.id ~= ignoreID and entry.name:lower() == name:lower() then return nil, "That mob name already exists." end
    end
    return name
end

local function getHolders(id)
    if not holders[id] then
        holders[id] = table.remove(spareHolders) or {
            min = bars.Create(MobTimer.frame, "Mob may be up", width, height, orientation),
            max = bars.Create(MobTimer.frame, "Mob expected by", width, height, orientation),
        }
    end
    return holders[id]
end

local function hidePair(pair)
    for _, holder in pairs(pair) do holder:Hide() holder.title:Hide() holder.flash:Hide() end
end

local function render()
    if not MobTimer.frame then return end
    local now, y = GetTime(), 0
    local vertical = orientation == "VERTICAL"
    local w, h = vertical and height or width, vertical and width or height
    for _, pair in pairs(holders) do
        for _, holder in pairs(pair) do holder:Hide() holder.title:Hide() end
    end
    for _, entry in ipairs(entries) do
        local timer = active[entry.id]
        if timer then
            local pair = getHolders(entry.id)
            for _, kind in ipairs({ "min", "max" }) do
                local holder, stage = pair[kind], timer[kind]
                local visible = (kind == "min" and minEnabled or kind == "max" and maxEnabled)
                    and (not stage.fired or now < stage.flashUntil)
                if visible then
                    holder:SetSize(w, h)
                    holder.bar:SetOrientation(orientation)
                    holder:ClearAllPoints()
                    holder:SetPoint("TOPLEFT", MobTimer.frame, "TOPLEFT", 0, -y)
                    holder.title:ClearAllPoints()
                    holder.title:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
                    holder:Show()
                    holder.title:Show()
                    if not stage.fired then bars.Update(holder, escape(timer.name), stage.seconds, now - timer.startedAt) end
                    y = y + h + 16
                end
            end
        end
    end
    if y == 0 and not locked then
        local holder = MobTimer.preview
        if not holder then
            holder = bars.Create(MobTimer.frame, "Mob timer", width, height, orientation)
            MobTimer.preview = holder
        end
        holder:SetSize(w, h)
        holder.bar:SetOrientation(orientation)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", MobTimer.frame, "TOPLEFT", 0, 0)
        holder.title:ClearAllPoints()
        holder.title:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
        bars.Update(holder, "Mob timer (drag to move)", 1, 0)
        holder:Show()
        holder.title:Show()
        y = h + 16
    elseif MobTimer.preview then
        MobTimer.preview:Hide()
        MobTimer.preview.title:Hide()
    end
    MobTimer.frame:SetSize(y > 0 and w or 1, y > 0 and y - 16 or 1)
    MobTimer.frame:SetShown(y > 0)
end

local function start(entry, test)
    local pair = getHolders(entry.id)
    hidePair(pair)
    active[entry.id] = {
        name = entry.name, startedAt = GetTime(),
        min = { seconds = test and 5 or entry.minSeconds, fired = false, flashUntil = 0 },
        max = { seconds = test and 10 or entry.maxSeconds, fired = false, flashUntil = 0 },
    }
    render()
end

local function reportDetectionError(key, message)
    if not reportedErrors[key] then
        reportedErrors[key] = true
        addon.Print("Mob timer detection: " .. message)
    end
end

local function readableUnitValue(api, unit, label)
    if type(api) ~= "function" then
        reportDetectionError(label .. ":unavailable", label .. " is unavailable.")
        return nil
    end
    local ok, value = pcall(api, unit)
    if not ok then
        reportDetectionError(label .. ":error", label .. " failed: " .. tostring(value))
        return nil
    end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function findByName(name)
    if type(name) ~= "string" then return nil end
    local needle = name:lower()
    for _, entry in ipairs(entries) do
        if entry.name:lower() == needle then return entry end
    end
end

local function remember(cache, guid, record)
    local count, oldest, oldestTime = 0, nil, nil
    for key, value in pairs(cache) do
        if value.expires <= GetTime() then
            cache[key] = nil
        else
            count = count + 1
            if not oldestTime or value.expires < oldestTime then oldest, oldestTime = key, value.expires end
        end
    end
    if not cache[guid] and count >= CACHE_LIMIT then cache[oldest] = nil end
    cache[guid] = record
end

local function observe(unit)
    local guid = readableUnitValue(UnitGUID, unit, "UnitGUID")
    if type(guid) ~= "string" or not guid:match("^Creature%-") then return end
    local name = readableUnitValue(UnitName, unit, "UnitName")
    local entry = findByName(name)
    if entry then
        remember(observed, guid, { name = entry.name, expires = GetTime() + CACHE_SECONDS })
    end
end

local function scanUnits()
    if not detectionEnabled or not detectionAvailable or #entries == 0 then return end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do observe(unit) end
    for index = 1, 40 do observe("nameplate" .. index) end
    for index = 1, 5 do observe("boss" .. index) end
end

local function onDeath(guid)
    if not detectionEnabled or #entries == 0 then return end
    if issecretvalue and issecretvalue(guid) then counts.secret = counts.secret + 1 return end
    if type(guid) ~= "string" or not guid:match("^Creature%-") then return end
    local now = GetTime()
    if deaths[guid] and deaths[guid].expires > now then counts.duplicate = counts.duplicate + 1 return end
    local record = observed[guid]
    if not record or record.expires <= now then
        scanUnits()
        record = observed[guid]
    end
    local entry = record and record.expires > now and findByName(record.name)
    if not entry then counts.unmatched = counts.unmatched + 1 return end
    remember(deaths, guid, { expires = now + CACHE_SECONDS })
    observed[guid] = nil
    counts.matched = counts.matched + 1
    start(entry, false)
    addon.Print("Mob timer: death detected for " .. escape(entry.name) .. "; timer started.")
end

local function tick()
    local now = GetTime()
    if now - lastScan >= 1 then
        lastScan = now
        scanUnits()
    end
    for id, timer in pairs(active) do
        local elapsed = now - timer.startedAt
        local pair = getHolders(id)
        for _, kind in ipairs({ "min", "max" }) do
            local stage = timer[kind]
            local enabled = kind == "min" and minEnabled or kind == "max" and maxEnabled
            if enabled and not stage.fired and elapsed >= stage.seconds then
                stage.fired, stage.flashUntil = true, now + bars.FLASH_SECONDS
                sound(kind == "min" and minSound or maxSound)
                bars.Flash(pair[kind])
            end
        end
        local minDone = not minEnabled or timer.min.fired and now >= timer.min.flashUntil
        local maxDone = not maxEnabled or timer.max.fired and now >= timer.max.flashUntil
        if minDone and maxDone then active[id] = nil hidePair(pair) end
    end
    render()
end

function MobTimer:IsLocked()
    return locked
end

function MobTimer:SetLocked(value)
    locked = value
    if self.frame then
        self.frame:EnableMouse(not value)
        render()
    end
end

function MobTimer:GetOptionsSchema()
    local choices = {}
    for _, item in ipairs(sounds) do
        local label = item.key == "thud" and "Impact thud" or item.label
        choices[#choices + 1] = { value = item.key, label = label }
    end
    return {
        name = "Mob Spawn Timer",
        action = { label = "Tracked mobs", button = "Manage mobs...", run = function() MobTimer:ToggleEditor() end,
            tooltip = "Add, edit and preview tracked mob timers." },
        options = {
            { type = "checkbox", key = "detectionEnabled", label = "Enable automatic death detection", section = "Detection", default = true,
                tooltip = "Start timers when UNIT_DIED matches a previously observed mob. Limited to readable nearby units.",
                get = function() return detectionEnabled end, set = function(v)
                    detectionEnabled = v
                    if not v then observed = {} else lastScan = -1 end
                end },
            { type = "checkbox", key = "locked", label = "Lock frame position", section = "Appearance", default = true,
                get = function() return locked end, set = function(v) MobTimer:SetLocked(v) end },
            { type = "slider", key = "width", label = "Bar width", section = "Appearance", min = 60, max = 500, step = 5, default = 220, format = "%dpx",
                get = function() return width end, set = function(v) if type(v) == "number" and v >= 60 and v <= 500 then width = v render() else addon.Print("Invalid mob timer width.") end end },
            { type = "slider", key = "height", label = "Bar height", section = "Appearance", min = 8, max = 60, step = 1, default = 18, format = "%dpx",
                get = function() return height end, set = function(v) if type(v) == "number" and v >= 8 and v <= 60 then height = v render() else addon.Print("Invalid mob timer height.") end end },
            { type = "dropdown", key = "orientation", label = "Bar orientation", section = "Appearance", default = "HORIZONTAL",
                choices = { { value = "HORIZONTAL", label = "Horizontal" }, { value = "VERTICAL", label = "Vertical" } },
                get = function() return orientation end, set = function(v) if v == "HORIZONTAL" or v == "VERTICAL" then orientation = v render() else addon.Print("Invalid mob timer orientation.") end end },
            { type = "checkbox", key = "minEnabled", label = "Show minimum timer", section = "Timers", default = true,
                get = function() return minEnabled end, set = function(v) minEnabled = v render() end },
            { type = "checkbox", key = "maxEnabled", label = "Show maximum timer", section = "Timers", default = true,
                get = function() return maxEnabled end, set = function(v) maxEnabled = v render() end },
            { type = "dropdown", key = "minSound", label = "Minimum timer sound", section = "Sounds", default = "ding", choices = choices,
                get = function() return minSound end, set = function(v) for _, s in ipairs(sounds) do if s.key == v then minSound = v return end end addon.Print("Invalid minimum timer sound.") end },
            { type = "dropdown", key = "maxSound", label = "Maximum timer sound", section = "Sounds", default = "thud", choices = choices,
                get = function() return maxSound end, set = function(v) for _, s in ipairs(sounds) do if s.key == v then maxSound = v return end end addon.Print("Invalid maximum timer sound.") end },
        },
    }
end

function MobTimer:GetPersistentState()
    local copy = {}
    for _, entry in ipairs(entries) do
        copy[#copy + 1] = { id = entry.id, name = entry.name, minSeconds = entry.minSeconds, maxSeconds = entry.maxSeconds }
    end
    return { entries = copy, nextID = nextID, position = position and { x = position.x, y = position.y } or nil }
end

function MobTimer:LoadPersistentState(state)
    if type(state) ~= "table" then return end
    entries, active, nextID = {}, {}, 1
    if type(state.entries) == "table" then
        local ids = {}
        for _, entry in ipairs(state.entries) do
            if #entries >= MAX_ENTRIES then addon.Print("Mob timer: saved list exceeds 30 entries; remaining entries were not loaded.") break end
            if type(entry) == "table" and type(entry.id) == "number" and entry.id == math.floor(entry.id) and entry.id > 0 and entry.id < 1000000000 and not ids[entry.id] then
                local name = validate(entry.name, entry.minSeconds, entry.maxSeconds)
                if name then
                    entries[#entries + 1] = { id = entry.id, name = name, minSeconds = entry.minSeconds, maxSeconds = entry.maxSeconds }
                    ids[entry.id] = true
                    nextID = math.max(nextID, entry.id + 1)
                else addon.Print("Mob timer: an invalid saved entry was not loaded.") end
            else addon.Print("Mob timer: an invalid saved entry was not loaded.") end
        end
    end
    local p = state.position
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
        and p.x == p.x and p.y == p.y and math.abs(p.x) < math.huge and math.abs(p.y) < math.huge then
        position = { x = p.x, y = p.y }
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    end
end

local function put(name, minSeconds, maxSeconds, id)
    local clean, err = validate(name, minSeconds, maxSeconds, id)
    if not clean then addon.Print("Mob timer: " .. err) return false end
    if id then
        for _, entry in ipairs(entries) do
            if entry.id == id then entry.name, entry.minSeconds, entry.maxSeconds = clean, minSeconds, maxSeconds save() return true end
        end

        addon.Print("Mob timer: selected entry no longer exists.")
        return false
    end
    if #entries >= MAX_ENTRIES then addon.Print("Mob timer: maximum of 30 entries reached.") return false end
    entries[#entries + 1] = { id = nextID, name = clean, minSeconds = minSeconds, maxSeconds = maxSeconds }
    nextID = nextID + 1
    selected = #entries
    save()
    return true
end

function MobTimer:AddCurrentTarget()
    local guid = readableUnitValue(UnitGUID, "target", "UnitGUID")
    if type(guid) ~= "string" or not guid:match("^Creature%-") then
        addon.Print("Mob timer: select a creature with a readable identity first.")
        return false
    end
    local name = readableUnitValue(UnitName, "target", "UnitName")
    if type(name) ~= "string" then
        addon.Print("Mob timer: the target's name is unavailable or unreadable.")
        return false
    end
    if not put(name, DEFAULT_MIN, DEFAULT_MAX) then return false end
    if detectionEnabled and detectionAvailable then observe("target") end
    if self.editor and self.editor:IsShown() then self.editor:Refresh() end
    addon.Print("Mob timer: added " .. escape(name) .. " (600s-900s).")
    return true
end

local function remove(index)
    local entry = entries[index]
    if not entry then addon.Print("Mob timer: select an entry first.") return end
    active[entry.id] = nil
    if holders[entry.id] then
        hidePair(holders[entry.id])
        spareHolders[#spareHolders + 1] = holders[entry.id]
        holders[entry.id] = nil
    end
    table.remove(entries, index)
    selected = math.max(1, math.min(index, #entries))
    save()
    render()
end

function MobTimer:ToggleEditor()
    if not self.editor then self.editor = self:CreateEditor() end
    if self.editor:IsShown() then self.editor:Hide() else self.editor:Refresh() self.editor:Show() end
end

function MobTimer:CreateEditor()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(500, 400)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    panel:SetBackdropColor(0.06, 0.05, 0.04, 1)
    panel:EnableMouse(true)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local function label(text, x, y)
        local font = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        font:SetPoint("TOPLEFT", x, y)
        font:SetText(text)
        return font
    end
    label("Mob Spawn Timer", 20, -20)
    panel.selection = label("", 20, -55)
    local function button(text, x, y, w, callback)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", callback)
        return b
    end
    local function edit(x, y, w, maxLetters)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetSize(w, 24)
        box:SetPoint("TOPLEFT", x, y)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return box
    end
    label("Mob name", 20, -102)
    panel.name = edit(120, -96, 330, 100)
    label("Minimum (seconds)", 20, -150)
    label("Maximum (seconds)", 20, -225)
    panel.minimum = edit(190, -144, 110, 6)
    panel.maximum = edit(190, -219, 110, 6)
    label("1-604800; slider step 60s. Type exact seconds.", 20, -302)
    local function slider(y, box)
        local control = CreateFrame("Slider", nil, panel)
        control:SetSize(410, 16)
        control:SetPoint("TOPLEFT", 25, y)
        control:SetOrientation("HORIZONTAL")
        control:SetMinMaxValues(1, MAX_SECONDS)
        control:SetValueStep(60)
        control:SetObeyStepOnDrag(true)
        control:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local track = control:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(3)
        track:SetColorTexture(0.45, 0.45, 0.45, 1)
        control:SetScript("OnValueChanged", function(_, value)
            if not panel.refreshing then box:SetText(tostring(math.floor(value))) end
        end)
        return control
    end
    panel.minSlider = slider(-184, panel.minimum)
    panel.maxSlider = slider(-259, panel.maximum)
    function panel:Refresh()
        local entry = entries[selected]
        self.refreshing = true
        self.selection:SetText(entry and string.format("%d / %d: %s", selected, #entries, escape(entry.name)) or "New mob")
        self.name:SetText(entry and entry.name or "")
        self.minimum:SetText(tostring(entry and entry.minSeconds or DEFAULT_MIN))
        self.maximum:SetText(tostring(entry and entry.maxSeconds or DEFAULT_MAX))
        self.minSlider:SetValue(entry and entry.minSeconds or DEFAULT_MIN)
        self.maxSlider:SetValue(entry and entry.maxSeconds or DEFAULT_MAX)
        self.refreshing = false
    end
    button("<", 20, -70, 40, function() if #entries > 0 then selected = selected > 1 and selected - 1 or #entries panel:Refresh() end end)
    button(">", 65, -70, 40, function() if #entries > 0 then selected = selected < #entries and selected + 1 or 1 panel:Refresh() end end)
    button("New", 115, -70, 65, function() selected = #entries + 1 panel:Refresh() end)
    button("Add target", 185, -70, 100, function() MobTimer:AddCurrentTarget() end)
    button("Save", 20, -340, 75, function()
        local entry = entries[selected]
        if put(panel.name:GetText(), tonumber(panel.minimum:GetText()), tonumber(panel.maximum:GetText()), entry and entry.id) then
            panel:Refresh()
            addon.Print("Mob timer: entry saved.")
        end
    end)
    button("Remove", 100, -340, 75, function() remove(selected) panel:Refresh() end)
    button("Test 5s/10s", 180, -340, 115, function()
        if entries[selected] then start(entries[selected], true) else addon.Print("Mob timer: save an entry before testing.") end
    end)
    button("Start manual", 300, -340, 115, function()
        if entries[selected] then start(entries[selected], false) else addon.Print("Mob timer: save an entry first.") end
    end)
    panel:Hide()
    return panel
end

function MobTimer:OnEnable()
    local frame = CreateFrame("Frame", "SabotonMobTimerFrame", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    bars.MakeMovable(frame, function() return locked end, function(x, y) position = { x = x, y = y } end)
    frame:Hide()
    self.frame = frame
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, value)
        if event == "UNIT_DIED" then
            onDeath(value)
        elseif detectionEnabled and detectionAvailable and #entries > 0 then
            if event == "PLAYER_TARGET_CHANGED" then observe("target")
            elseif event == "PLAYER_FOCUS_CHANGED" then observe("focus")
            elseif event == "UPDATE_MOUSEOVER_UNIT" then observe("mouseover")
            elseif event == "NAME_PLATE_UNIT_ADDED" and not (issecretvalue and issecretvalue(value)) and type(value) == "string" then observe(value) end
        end
    end)
    for _, event in ipairs({ "UNIT_DIED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
        local ok, err = pcall(self.events.RegisterEvent, self.events, event)
        if event == "UNIT_DIED" then detectionAvailable = ok end
        if not ok then reportDetectionError("event " .. event, "could not register " .. event .. ": " .. tostring(err)) end
    end
    C_Timer.NewTicker(0.25, tick)
end

function MobTimer:HandleCommand(message)
    local command, rest = (message or ""):match("^(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "options" then self:ToggleEditor()
    elseif command == "target" then self:AddCurrentTarget()
    elseif command == "add" or command == "edit" then
        local name, mn, mx = rest:match("^(.-)%s+(%d+)%s+(%d+)$")
        local found
        if command == "edit" and name then
            for _, entry in ipairs(entries) do if entry.name:lower() == name:lower() then found = entry end end
            if not found then addon.Print("Mob timer: mob not found.") return end
        end
        if not name then addon.Print("Usage: /saboton mobtimer " .. command .. " <name> <min seconds> <max seconds>") return end
        if put(name, tonumber(mn), tonumber(mx), found and found.id) then addon.Print("Mob timer: saved " .. escape(name) .. ".") end
    elseif command == "list" then
        if #entries == 0 then addon.Print("Mob timer: no entries.") end
        for _, entry in ipairs(entries) do addon.Print(string.format("Mob timer: %s %ds-%ds", escape(entry.name), entry.minSeconds, entry.maxSeconds)) end
    elseif command == "test" or command == "start" or command == "remove" then
        local index
        for i, entry in ipairs(entries) do if entry.name:lower() == rest:lower() then index = i break end end
        if not index then addon.Print("Mob timer: mob not found; use its exact name.") return end
        if command == "remove" then remove(index) else start(entries[index], command == "test") addon.Print("Mob timer: manual " .. command .. " started for " .. escape(entries[index].name) .. ".") end
    elseif command == "clear" then
        active = {}
        for _, pair in pairs(holders) do hidePair(pair) end
        render()
        addon.Print("Mob timer: active timers cleared.")
    elseif command == "enable" then
        detectionEnabled = not detectionEnabled
        if not detectionEnabled then observed = {} else lastScan = -1 scanUnits() end
        addon.Print("Mob timer: automatic death detection " .. (detectionEnabled and "enabled." or "disabled."))
        if detectionEnabled and not detectionAvailable then addon.Print("Mob timer: UNIT_DIED registration failed; automatic detection is unavailable.") end
    elseif command == "status" then
        addon.Print("Mob timer: automatic detection " .. (detectionEnabled and "enabled" or "disabled") .. "; UNIT_DIED " .. (detectionAvailable and "registered." or "unavailable."))
        addon.Print(string.format("Mob timer: deaths matched=%d unmatched=%d secret=%d duplicate=%d (session).",
            counts.matched, counts.unmatched, counts.secret, counts.duplicate))
        addon.Print("Mob timer: " .. #entries .. " configured mobs; identities are observed from nearby readable unit tokens.")
    elseif command == "lock" or command == "unlock" then
        self:SetLocked(command == "lock")
        addon.Print("Mob timer: frame " .. (locked and "locked." or "unlocked; drag out of combat."))
    elseif command == "width" or command == "height" then
        local value = tonumber(rest)
        local low, high = command == "width" and 60 or 8, command == "width" and 500 or 60
        if not value or value ~= value or value < low or value > high then addon.Print("Mob timer: " .. command .. " must be between " .. low .. " and " .. high .. ".") return end
        if command == "width" then width = value else height = value end
        render()
        addon.Print("Mob timer: " .. command .. " set to " .. value .. ".")
    elseif command == "orient" then
        local value = rest:lower()
        if value == "h" or value == "horizontal" then orientation = "HORIZONTAL"
        elseif value == "v" or value == "vertical" then orientation = "VERTICAL"
        else addon.Print("Mob timer: use orient <h|v>.") return end
        render()
    elseif command == "minsound" or command == "maxsound" then
        local key = rest:lower()
        for _, item in ipairs(sounds) do
            if item.key == key then
                if command == "minsound" then minSound = key else maxSound = key end
                addon.Print("Mob timer: " .. command .. " set to " .. item.label .. ".")
                return
            end
        end
        addon.Print("Mob timer: choose none, ding, thud, kaching, squeak or huagh.")
    elseif command == "minbar" or command == "maxbar" then
        if command == "minbar" then minEnabled = not minEnabled else maxEnabled = not maxEnabled end
        render()
        addon.Print("Mob timer: " .. command .. " " .. ((command == "minbar" and minEnabled or command == "maxbar" and maxEnabled) and "on." or "off."))
    else addon.Print("Mob timer: options, target, enable, status, add/edit <name> <min seconds> <max seconds>, list, test/start/remove <exact name>, clear, lock/unlock, width/height, orient, minbar/maxbar, minsound/maxsound.") end
end

addon.RegisterModule("mobtimer", MobTimer)
