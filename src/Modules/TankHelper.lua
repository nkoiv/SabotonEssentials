local _, addon = ...

local TankHelper = {}
local DEFAULT_SPELLS = "23922,23923,23924,23925,6572,6574,7379,11600,11601"
local CORRELATION_WINDOW = 0.01
local UNLIMITED_WINDOW = 120
local SOUND_OPTIONS = addon.TimerBars.SOUNDS
local enabled, soundEnabled, textEnabled = true, true, true
local sayEnabled = false
local soundKey = "huagh"
local textOffsetX, textOffsetY = -200, 200
local textArcDuration, textFadeDuration = 0.9, 0.5
local fightWindow = 20
local spellList = DEFAULT_SPELLS
local trackedSpells = {}
local familyList = ""
local spellFamilies = {}
local fightStartedAt, pendingCast
local familyLookupWarned = false

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function parseIds(value)
    if type(value) ~= "string" or value:match("[^%d,%s]") or value:match("^%s*,")
        or value:match(",%s*,") or value:match(",%s*$") then
        addon.Print("Miss Alerts: enter comma-separated positive spell IDs, or leave the list empty.")
        return nil
    end
    local ids, seen = {}, {}
    for token in value:gmatch("[^,]+") do
        local id = token:match("^%s*(%d+)%s*$")
        id = id and tonumber(id)
        if not id or id < 1 or id > 2147483647 then
            addon.Print("Miss Alerts: enter comma-separated positive spell IDs, or leave the list empty.")
            return nil
        end
        if not seen[id] then
            ids[#ids + 1], seen[id] = tostring(id), true
        end
    end
    return table.concat(ids, ","), seen
end

local function setSpells(value)
    local list, ids = parseIds(value)
    if not list then return false end
    spellList, trackedSpells = list, ids
    pendingCast = nil
    return true
end

local function setFamilies(value)
    local list, ids = parseIds(value)
    if not list then return false end
    familyList, spellFamilies = list, ids
    pendingCast = nil
    return true
end
setSpells(DEFAULT_SPELLS)

local function familyMatches(id)
    if not next(spellFamilies) then return false end
    local name = addon.Spells.Name(id)
    if not name then
        if not familyLookupWarned then
            addon.Print("Miss Alerts: a spell name is unavailable; all-rank matching may miss casts.")
            familyLookupWarned = true
        end
        return false
    end
    for familyId in pairs(spellFamilies) do
        local familyName = addon.Spells.Name(familyId)
        if familyName and familyName == name then return true end
        if not familyName and not familyLookupWarned then
            addon.Print("Miss Alerts: a tracked spell name is unavailable; all-rank matching may miss casts.")
            familyLookupWarned = true
        end
    end
    return false
end

local function trackedDescription()
    local entries = {}
    for id in spellList:gmatch("%d+") do
        entries[#entries + 1] = addon.Spells.Label(tonumber(id)) .. " (ID " .. id .. ")"
    end
    for id in familyList:gmatch("%d+") do
        entries[#entries + 1] = addon.Spells.Label(tonumber(id)) .. " (all ranks; ID " .. id .. ")"
    end
    return entries
end

local function changeSpell(command, value)
    value = (value or ""):match("^%s*(.-)%s*$")
    if value == "" then return end
    local digits = value:match("^%d+$")
    local id = digits and tonumber(digits)
    if digits and (not id or id < 1 or id > 2147483647) then
        addon.Print("Miss Alerts: invalid spell ID.")
        return
    end
    if not digits then
        local err
        id, err = addon.Spells.ResolveName(value)
        if not id then addon.Print("Miss Alerts: " .. err) return end
    end
    local current = digits and trackedSpells or spellFamilies
    local list = digits and spellList or familyList
    local setter = digits and setSpells or setFamilies
    local name = addon.Spells.Label(id)
    if command == "add" then
        if current[id] or (not digits and familyMatches(id)) then
            addon.Print("Miss Alerts: " .. name .. " is already tracked.")
            return
        end
        setter((list ~= "" and list .. "," or "") .. id)
        addon.Print("Miss Alerts: tracking " .. name .. (digits and (" (ID " .. id .. ").") or " (all ranks)."))
    else
        local removed = false
        local unresolved = false
        local function removeMatches(source, set, match)
            local keep = {}
            for token in source:gmatch("%d+") do
                if match(tonumber(token)) then removed = true else keep[#keep + 1] = token end
            end
            set(table.concat(keep, ","))
        end
        if digits then
            removeMatches(spellList, setSpells, function(candidate) return candidate == id end)
        else
            local function matches(candidate)
                local candidateName = addon.Spells.Name(candidate)
                if not candidateName then unresolved = true end
                return candidateName == name
            end
            removeMatches(spellList, setSpells, matches)
            removeMatches(familyList, setFamilies, matches)
        end
        addon.Print("Miss Alerts: " .. (removed and "removed " or "not tracking ") .. name
            .. (digits and (" (ID " .. id .. ").") or " (all matching ranks)."))
        if unresolved then addon.Print("Miss Alerts: some tracked names could not be resolved and were kept; review the spell list.") end
    end
end

local function spellGroups()
    local groups, byName = {}, {}
    local function add(list, family)
        for token in list:gmatch("%d+") do
            local id = tonumber(token)
            local name = addon.Spells.Name(id)
            local key = name and ("name:" .. name) or ("id:" .. id)
            local group = byName[key]
            if not group then
                group = { name = name or ("Spell " .. id), ids = {}, families = {} }
                byName[key] = group
                groups[#groups + 1] = group
            end
            local destination = family and group.families or group.ids
            destination[id] = true
        end
    end
    add(spellList, false)
    add(familyList, true)
    return groups
end

local function removeGroup(group)
    local function filter(list, remove)
        local kept = {}
        for token in list:gmatch("%d+") do
            if not remove[tonumber(token)] then kept[#kept + 1] = token end
        end
        return table.concat(kept, ",")
    end
    setSpells(filter(spellList, group.ids))
    setFamilies(filter(familyList, group.families))
    if addon.SaveSettings then addon.SaveSettings() end
    addon.Print("Miss Alerts: removed " .. group.name:gsub("|", "||") .. " and its listed ranks.")
end

function TankHelper:ToggleSpellEditor()
    if not self.spellEditor then self.spellEditor = self:CreateSpellEditor() end
    if self.spellEditor:IsShown() then
        self.spellEditor:Hide()
    else
        self.spellEditor:Refresh()
        self.spellEditor:Show()
    end
end

function TankHelper:CreateSpellEditor()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(520, 390)
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
        local item = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        item:SetPoint("TOPLEFT", x, y)
        item:SetText(text)
        return item
    end
    local function button(text, x, y, width, callback)
        local item = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        item:SetSize(width, 24)
        item:SetPoint("TOPLEFT", x, y)
        item:SetText(text)
        item:SetScript("OnClick", callback)
        return item
    end
    label("Miss Alerts - tracked spells", 20, -20)
    label("Add a localized spell name (all ranks) or one spell ID:", 20, -53)
    panel.input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.input:SetSize(330, 24)
    panel.input:SetPoint("TOPLEFT", 25, -78)
    panel.input:SetAutoFocus(false)
    panel.input:SetMaxLetters(100)
    panel.input:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local function addSpell()
        local input = panel.input:GetText()
        if input:match("^%s*$") then addon.Print("Miss Alerts: enter a spell name or ID.") return end
        local beforeSpells, beforeFamilies = spellList, familyList
        changeSpell("add", input)
        if addon.SaveSettings then addon.SaveSettings() end
        if spellList ~= beforeSpells or familyList ~= beforeFamilies then panel.input:SetText("") end
        panel.input:ClearFocus()
        panel:Refresh()
    end
    panel.input:SetScript("OnEnterPressed", addSpell)
    button("Add", 365, -78, 100, addSpell)
    label("Tracked spells (Remove clears all listed ranks):", 20, -120)
    panel.rows = {}
    panel.page = 1
    for index = 1, 6 do
        local row = { text = label("", 25, -144 - (index - 1) * 29) }
        row.text:SetWidth(350)
        row.text:SetJustifyH("LEFT")
        row.remove = button("Remove", 390, -137 - (index - 1) * 29, 90, function()
            if row.group then removeGroup(row.group) panel:Refresh() end
        end)
        panel.rows[index] = row
    end
    panel.pageLabel = label("", 220, -337)
    panel.previous = button("<", 155, -330, 45, function() panel.page = panel.page - 1 panel:Refresh() end)
    panel.next = button(">", 320, -330, 45, function() panel.page = panel.page + 1 panel:Refresh() end)
    function panel:Refresh()
        local groups = spellGroups()
        local pages = math.max(1, math.ceil(#groups / 6))
        self.page = math.max(1, math.min(self.page, pages))
        self.pageLabel:SetText(self.page .. " / " .. pages)
        for index, row in ipairs(self.rows) do
            local group = groups[(self.page - 1) * 6 + index]
            row.group = group
            if group then
                local count = 0
                for _ in pairs(group.ids) do count = count + 1 end
                local suffix = next(group.families) and "all ranks" or (count == 1 and "1 rank" or count .. " ranks")
                if next(group.families) and count > 0 then
                    suffix = suffix .. " + " .. count .. (count == 1 and " ID" or " IDs")
                end
                row.text:SetText(group.name:gsub("|", "||") .. " (" .. suffix .. ")")
                row.remove:Show()
            else
                row.text:SetText("")
                row.remove:Hide()
            end
        end
    end
    panel:Hide()
    return panel
end

local function findSound(key)
    for _, sound in ipairs(SOUND_OPTIONS) do
        if sound.key == key then return sound end
    end
end

local function setSound(key)
    if not findSound(key) then
        addon.Print("Miss Alerts: unknown sound; choose none, ding, thud, kaching, squeak or huagh.")
        return false
    end
    soundKey = key
    return true
end

local function animate(display, elapsed)
    display.elapsed = display.elapsed + elapsed
    local progress = math.min(display.elapsed / textArcDuration, 1)
    display:ClearAllPoints()
    display:SetPoint("CENTER", UIParent, "CENTER", textOffsetX - 160 * progress,
        textOffsetY - 55 * progress + 30 * 4 * progress * (1 - progress))
    display:SetAlpha(math.max(0, 1 - math.max(0, display.elapsed - textArcDuration) / textFadeDuration))
    if display.elapsed >= textArcDuration + textFadeDuration then
        display:SetScript("OnUpdate", nil)
        display:Hide()
    end
end

local function alert(id, outcome, test)
    local label = addon.Spells.Label(id) .. ": " .. outcome
    if sayEnabled and not test then
        SendChatMessage(label, "SAY")
    end
    if textEnabled then
        local display = TankHelper.display
        display.text:SetText(label)
        display.elapsed = 0
        display:SetAlpha(1)
        animate(display, 0)
        display:SetScript("OnUpdate", animate)
        display:Show()
    end
    local sound = findSound(soundKey)
    if soundEnabled and not sound.silent and not PlaySoundFile(sound.path, "Master") then
        addon.Print("Miss Alerts: could not play " .. sound.label .. ". Check " .. sound.path .. ".")
    end
end

local function windowLabel(value)
    if value == UNLIMITED_WINDOW then return "Unlimited" end
    return string.format("%ds", value)
end

local function inAlertWindow(now)
    return fightStartedAt and (fightWindow == UNLIMITED_WINDOW or now - fightStartedAt < fightWindow)
end

local function handleAlertEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        fightStartedAt, pendingCast = GetTime(), nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        fightStartedAt, pendingCast = nil, nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        pendingCast = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, id = ...
        if secret(unit) or unit ~= "player" then return end
        pendingCast = nil
        local now = GetTime()
        if enabled and inAlertWindow(now)
            and not secret(id) and type(id) == "number" and (trackedSpells[id] or familyMatches(id)) then
            pendingCast = { id = id, time = now }
        end
    elseif event == "UNIT_COMBAT" then
        local unit, outcome = ...
        if secret(unit) or unit ~= "target" or not pendingCast then return end
        local cast = pendingCast
        pendingCast = nil
        local now = GetTime()
        if enabled and inAlertWindow(now)
            and now >= cast.time and now - cast.time <= CORRELATION_WINDOW
            and not secret(outcome) and (outcome == "MISS" or outcome == "DODGE" or outcome == "PARRY") then
            alert(cast.id, outcome)
        end
    end
end

function TankHelper:GetOptionsSchema()
    return {
        name = "Miss Alerts",
        enabledKey = "enabled",
        options = {
            { type = "checkbox", key = "enabled", section = "General", label = "Enable Miss Alerts",
                tooltip = "Experimental: correlate your casts with target outcomes; attribution is not guaranteed.",
                default = true, get = function() return enabled end,
                set = function(value) enabled = value pendingCast = nil end },
            { type = "slider", key = "fightWindow", section = "General", label = "Alert window (seconds)",
                tooltip = "Only alert during this many seconds after entering combat. The maximum setting is unlimited.",
                min = 1, max = UNLIMITED_WINDOW, step = 1, default = 20, formatValue = windowLabel,
                get = function() return fightWindow end,
                set = function(value) fightWindow = math.max(1, math.min(UNLIMITED_WINDOW, math.floor(value + 0.5))) end },
            { type = "text", key = "spellList", section = "General", label = "Tracked spell IDs",
                hidden = true,
                default = DEFAULT_SPELLS, get = function() return spellList end, set = setSpells },
            { type = "text", key = "spellFamilies", section = "General", hidden = true,
                get = function() return familyList end, set = setFamilies },
            { type = "checkbox", key = "textEnabled", section = "Alerts", label = "Show alert text",
                tooltip = "Show an animated alert moving left.", default = true,
                get = function() return textEnabled end,
                set = function(value)
                    textEnabled = value
                    if not value and TankHelper.display then
                        TankHelper.display:SetScript("OnUpdate", nil)
                        TankHelper.display:Hide()
                    end
                end },
            { type = "checkbox", key = "sayEnabled", section = "Alerts", label = "Announce misses in Say chat",
                tooltip = "Send the spell and miss outcome in Say chat, showing a speech bubble above your character. Nearby players can see it.",
                default = false, get = function() return sayEnabled end,
                set = function(value) sayEnabled = value end },
            { type = "slider", key = "textOffsetX", section = "Alerts", dependsOn = "textEnabled",
                label = "Alert text horizontal offset", tooltip = "Move the entire arc left or right from screen center.",
                min = -600, max = 600, step = 10, default = -200, format = "%d",
                get = function() return textOffsetX end,
                set = function(value)
                    textOffsetX = math.max(-600, math.min(600, value))
                    addon.TimerBars.RefreshTextAnchor(TankHelper.textAnchor)
                end },
            { type = "slider", key = "textOffsetY", section = "Alerts", dependsOn = "textEnabled",
                label = "Alert text vertical offset", tooltip = "Move the entire arc up or down from screen center.",
                min = -400, max = 400, step = 10, default = 200, format = "%d",
                get = function() return textOffsetY end,
                set = function(value)
                    textOffsetY = math.max(-400, math.min(400, value))
                    addon.TimerBars.RefreshTextAnchor(TankHelper.textAnchor)
                end },
            { type = "slider", key = "textArcDuration", section = "Alerts", dependsOn = "textEnabled",
                label = "Alert text movement time", tooltip = "Time in seconds to travel along the arc.",
                min = 0.2, max = 3.0, step = 0.1, default = 0.9, format = "%.1fs",
                get = function() return textArcDuration end,
                set = function(value) textArcDuration = math.max(0.2, math.min(3, value)) end },
            { type = "slider", key = "textFadeDuration", section = "Alerts", dependsOn = "textEnabled",
                label = "Alert text fade time", tooltip = "Time in seconds to fade after the movement finishes.",
                min = 0.1, max = 3.0, step = 0.1, default = 0.5, format = "%.1fs",
                get = function() return textFadeDuration end,
                set = function(value) textFadeDuration = math.max(0.1, math.min(3, value)) end },
            { type = "checkbox", key = "soundEnabled", section = "Alerts", label = "Play alert sound",
                tooltip = "Play the selected sound when an alert fires.", default = true,
                get = function() return soundEnabled end, set = function(value) soundEnabled = value end },
            { type = "dropdown", key = "soundKey", section = "Alerts", dependsOn = "soundEnabled",
                label = "Alert sound", tooltip = "Choose the sound played for a missed attack.",
                default = "huagh", choices = (function()
                    local choices = {}
                    for _, sound in ipairs(SOUND_OPTIONS) do
                        choices[#choices + 1] = { value = sound.key, label = sound.label }
                    end
                    return choices
                end)(), get = function() return soundKey end, set = setSound },
        },
        action = {
            section = "General",
            label = "Tracked spells",
            button = "Manage spells...",
            tooltip = "View, add and remove tracked spells and ranks.",
            run = function() TankHelper:ToggleSpellEditor() end,
        },
        actions = {
            { section = "Alerts", label = "Text position", button = "Show / hide text anchor",
                tooltip = "Alt + left-drag the stationary arc start out of combat. Click again to hide it.",
                run = function() TankHelper:HandleCommand("move") end },
        },
    }
end

local running = false
local startedAt
local combatAt
local registered
local counts
local lines = 0
local MAX_LINES = 120
local EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_COMBAT",
    "COMBAT_TEXT_UPDATE",
}

local function describe(value)
    if secret(value) then return "<secret>" end
    local kind = type(value)
    if kind == "nil" then return "<nil>" end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "string" then return "<" .. kind .. ">" end
    value = value:gsub("[%c]", " "):gsub("|", "||")
    if #value > 80 then value = value:sub(1, 80) .. "..." end
    return '"' .. value .. '"'
end

local function log(message)
    if lines >= MAX_LINES then return end
    lines = lines + 1
    local now = GetTime()
    local combat = combatAt and string.format(" combat=%.2fs", now - combatAt) or ""
    addon.Print(string.format("Miss Alerts probe +%.2fs%s: %s", now - startedAt, combat, message))
    if lines == MAX_LINES then addon.Print("Miss Alerts probe: output capped; counts continue. Stop and start to reset.") end
end

local function logArgs(event, ...)
    local parts = {}
    for i = 1, math.min(select("#", ...), 8) do
        parts[#parts + 1] = i .. "=" .. describe(select(i, ...))
    end
    log(event .. (next(parts) and (" " .. table.concat(parts, " ")) or ""))
end

local function status()
    addon.Print("Miss Alerts probe: " .. (running and "running" or "stopped") .. ".")
    if not running then return end
    addon.Print("Miss Alerts probe: registered: " .. (#registered > 0 and table.concat(registered, ", ") or "none"))
    local parts = {}
    for _, event in ipairs(EVENTS) do parts[#parts + 1] = event .. "=" .. counts[event] end
    addon.Print("Miss Alerts probe: event counts: " .. table.concat(parts, ", ") .. ".")
    addon.Print("Miss Alerts probe: " .. lines .. "/" .. MAX_LINES .. " event lines printed.")
end

function TankHelper:OnEnable()
    self.display = CreateFrame("Frame", nil, UIParent)
    self.display:SetSize(200, 40)
    self.display:SetPoint("CENTER", UIParent, "CENTER", -200, 200)
    self.display:Hide()
    self.display.text = self.display:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    self.display.text:SetPoint("CENTER")

    self.alertFrame = CreateFrame("Frame")
    self.alertFrame:SetScript("OnEvent", function(_, event, ...) handleAlertEvent(event, ...) end)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_COMBAT" }) do
        local ok, err = pcall(self.alertFrame.RegisterEvent, self.alertFrame, event)
        if not ok then addon.Print("Miss Alerts: could not register " .. event .. ": " .. tostring(err) .. ". Alerts may not work.") end
    end

    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if not running then return end
        counts[event] = counts[event] + 1
        if event == "PLAYER_REGEN_DISABLED" then
            combatAt = GetTime()
            log(event)
        elseif event == "PLAYER_REGEN_ENABLED" then
            log(event)
            combatAt = nil
        elseif event == "PLAYER_TARGET_CHANGED" then
            log(event)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit = ...
            if not secret(unit) and unit == "player" then logArgs(event, ...) end
        elseif event == "UNIT_COMBAT" then
            local unit = ...
            if not secret(unit) and (unit == "player" or unit == "target") then logArgs(event, ...) end
        elseif event == "COMBAT_TEXT_UPDATE" then
            logArgs(event, ...)
        end
    end)
end

function TankHelper:HandleCommand(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "move" then
        self.textAnchor = addon.TimerBars.ToggleTextAnchor(self.textAnchor, "Miss Alerts text start",
            function() return textOffsetX, textOffsetY end,
            function(x, y)
                textOffsetX = math.max(-600, math.min(600, math.floor(x / 10 + 0.5) * 10))
                textOffsetY = math.max(-400, math.min(400, math.floor(y / 10 + 0.5) * 10))
            end)
        addon.Print("Miss Alerts text anchor " .. (self.textAnchor:IsShown() and "shown; Alt + left-drag out of combat." or "hidden."))
    elseif command == "start" then
        if running then addon.Print("Miss Alerts probe: already running; stop first to reset.") return end
        startedAt, combatAt, lines = GetTime(), nil, 0
        registered, counts = {}, {}
        running = true
        for _, event in ipairs(EVENTS) do
            counts[event] = 0
            local ok, err = pcall(self.frame.RegisterEvent, self.frame, event)
            if ok then
                registered[#registered + 1] = event
            else
                addon.Print("Miss Alerts probe: could not register " .. event .. ": " .. tostring(err) .. ".")
            end
        end
        addon.Print("Miss Alerts probe: started; combat timing begins at the next PLAYER_REGEN_DISABLED event.")
        status()
    elseif command == "stop" then
        if running then
            self.frame:UnregisterAllEvents()
            running = false
        end
        addon.Print("Miss Alerts probe: stopped; session results cleared.")
    elseif command == "status" then
        status()
    elseif command == "mark" then
        if running then log("manual marker") else addon.Print("Miss Alerts probe: start the probe first.") end
    elseif command == "enable" then
        enabled, pendingCast = not enabled, nil
        addon.Print("Miss Alerts " .. (enabled and "enabled" or "disabled") .. ".")
    elseif command == "sound" then
        soundEnabled = not soundEnabled
        addon.Print("Miss Alerts sound " .. (soundEnabled and "enabled" or "disabled") .. ".")
    elseif command == "say" then
        sayEnabled = not sayEnabled
        addon.Print("Miss Alerts Say chat " .. (sayEnabled and "enabled" or "disabled") .. ".")
    elseif command == "soundkey" then
        local key = rest:lower()
        if setSound(key) then addon.Print("Miss Alerts sound set to " .. findSound(key).label .. ".") end
    elseif command == "xoffset" or command == "yoffset" then
        local value = tonumber(rest)
        local limit = command == "xoffset" and 600 or 400
        if not value or value ~= value or value < -limit or value > limit then
            addon.Print("Usage: /saboton missalerts " .. command .. " <number from -" .. limit .. " to " .. limit .. ">")
        else
            value = math.floor(value / 10 + 0.5) * 10
            if command == "xoffset" then textOffsetX = value else textOffsetY = value end
            addon.TimerBars.RefreshTextAnchor(self.textAnchor)
            addon.Print("Miss Alerts " .. command .. " set to " .. value .. ".")
        end
    elseif command == "movement" or command == "fade" then
        local value = tonumber(rest)
        local minimum = command == "movement" and 0.2 or 0.1
        if not value or value ~= value or value < minimum or value > 3 then
            addon.Print("Usage: /saboton missalerts " .. command .. " <seconds from " .. minimum .. " to 3>")
        else
            if command == "movement" then textArcDuration = value else textFadeDuration = value end
            addon.Print("Miss Alerts " .. command .. " set to " .. value .. "s.")
        end
    elseif command == "text" then
        textEnabled = not textEnabled
        if not textEnabled then
            self.display:SetScript("OnUpdate", nil)
            self.display:Hide()
        end
        addon.Print("Miss Alerts text " .. (textEnabled and "enabled" or "disabled") .. ".")
    elseif command == "window" then
        local value = tonumber(rest)
        if not value or value ~= value or value < 1 or value > 120 or value ~= math.floor(value) then
            addon.Print("Usage: /saboton missalerts window <whole seconds, 1-119, or 120 for unlimited>")
        else
            fightWindow = value
            addon.Print("Miss Alerts window: " .. windowLabel(value) .. ".")
        end
    elseif command == "spells" then
        local entries = trackedDescription()
        addon.Print("Miss Alerts tracked spells: " .. (#entries > 0 and table.concat(entries, ", ") or "(none)") .. ".")
    elseif command == "options" then
        self:ToggleSpellEditor()
    elseif command == "add" or command == "remove" then
        if rest == "" then addon.Print("Usage: /saboton missalerts " .. command .. " <spell name or ID>")
        else changeSpell(command, rest) end
        if self.spellEditor and self.spellEditor:IsShown() then self.spellEditor:Refresh() end
    elseif command == "test" then
        alert(11601, "DODGE", true)
    elseif command == "alertstatus" then
        addon.Print("Miss Alerts " .. (enabled and "enabled" or "disabled") .. "; window "
            .. windowLabel(fightWindow) .. "; use /saboton missalerts spells to list tracked spells.")
        addon.Print("Miss Alerts Say chat: " .. (sayEnabled and "on" or "off") .. ".")
        addon.Print("Miss Alerts sound: " .. (soundEnabled and findSound(soundKey).label or "off")
            .. "; text: " .. (textEnabled and "on" or "off") .. "; offset: "
            .. textOffsetX .. ", " .. textOffsetY .. "; movement: " .. textArcDuration .. "s; fade: " .. textFadeDuration .. "s.")
    else
        addon.Print("Miss Alerts: enable, sound, say, soundkey <key>, text, move, xoffset, yoffset, movement, fade, window, spells, add, remove, test, alertstatus. Probe: start, status, mark, stop.")
    end
end

addon.RegisterModule("tankhelper", TankHelper)
