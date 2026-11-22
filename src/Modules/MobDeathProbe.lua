local ADDON_NAME, addon = ...

local Probe = {}
local running = false
local watched
local counts
local registered
local elapsed = 0
local reportedErrors = {}
local MAX_LINES = 40
local lines = 0

local function report(message)
    if lines < MAX_LINES then
        addon.Print("Mob probe: " .. message)
        lines = lines + 1
        if lines == MAX_LINES then addon.Print("Mob probe: live output capped; use status or restart the probe.") end
    end
end

local function readUnit(api, unit, label)
    if type(api) ~= "function" then
        if not reportedErrors[label] then
            report(label .. " is unavailable.")
            reportedErrors[label] = true
        end
        return nil, "unavailable"
    end
    local ok, value = pcall(api, unit)
    if not ok then
        if not reportedErrors[label] then
            report(label .. " failed for " .. unit .. ".")
            reportedErrors[label] = true
        end
        return nil, "error"
    end
    if issecretvalue and issecretvalue(value) then return nil, "secret" end
    if value == nil then return nil, "missing" end
    return value, "readable"
end

local function guidOf(unit)
    local value, state = readUnit(UnitGUID, unit, "UnitGUID")
    if state == "readable" and type(value) ~= "string" then return nil, "invalid" end
    return value, state
end

local function deadOf(unit)
    local value, state = readUnit(UnitIsDeadOrGhost, unit, "UnitIsDeadOrGhost")
    if state == "readable" and type(value) ~= "boolean" then return nil, "invalid" end
    return value, state
end

local function liveUnit(guid)
    local units = { "target", "focus", "mouseover" }
    for index = 1, 40 do units[#units + 1] = "nameplate" .. index end
    for index = 1, 5 do units[#units + 1] = "boss" .. index end
    for _, unit in ipairs(units) do
        local candidate = guidOf(unit)
        if candidate and candidate == guid then return unit end
    end
end

local function observeState(source, unit, event)
    if not watched or not watched.guid then return end
    local guid = guidOf(unit)
    if not guid or guid ~= watched.guid then return end
    local dead, state = deadOf(unit)
    counts[source .. "Checks"] = counts[source .. "Checks"] + 1
    if state ~= "readable" then
        watched[source .. "Dead"] = nil
        if watched[source .. "State"] ~= state then
            report(source .. " " .. unit .. ": death state " .. state .. ".")
            watched[source .. "State"] = state
        end
        return
    end
    if watched[source .. "State"] ~= "readable" then
        report(source .. " " .. unit .. ": death state readable again.")
    end
    watched[source .. "State"] = "readable"
    local key = source .. "Dead"
    local previous = watched[key]
    if dead and previous ~= true then
        counts[source .. "Dead"] = counts[source .. "Dead"] + 1
        report((event or source) .. " " .. unit .. ": " .. (previous == false and "alive-to-dead transition" or "dead observed; prior state unknown") .. ".")
    elseif not dead and previous == true then
        report(source .. " " .. unit .. ": alive again.")
    end
    watched[key] = dead
end

local function onUnitDied(guid)
    counts.deaths = counts.deaths + 1
    if issecretvalue and issecretvalue(guid) then
        counts.secret = counts.secret + 1
        report("UNIT_DIED fired; event GUID is secret.")
    elseif guid == nil then
        counts.missing = counts.missing + 1
        report("UNIT_DIED fired; event GUID is missing.")
    elseif type(guid) ~= "string" then
        counts.invalid = counts.invalid + 1
        report("UNIT_DIED fired; event GUID has an unexpected type.")
    elseif watched and watched.guid and guid == watched.guid then
        counts.matches = counts.matches + 1
        local unit = liveUnit(guid)
        report("UNIT_DIED matched watched GUID; " .. (unit and ("live token: " .. unit) or "no live token; cached identity matched") .. ".")
    else
        counts.other = counts.other + 1
        report("UNIT_DIED fired with a readable GUID; not the watched GUID.")
    end
end

local function status()
    addon.Print("Mob probe: " .. (running and "running" or "stopped") .. ".")
    if not running then return end
    addon.Print("Mob probe: registered: " .. (#registered > 0 and table.concat(registered, ", ") or "none"))
    if watched then
        addon.Print("Mob probe: watched " .. watched.name .. "; GUID " .. watched.guidState .. "; initial death state " .. watched.initialState .. ".")
    else
        addon.Print("Mob probe: no watched target; use /saboton mobprobe watch.")
    end
    addon.Print(string.format("Mob probe: UNIT_DIED total=%d watched=%d other=%d secret=%d missing=%d invalid=%d.",
        counts.deaths, counts.matches, counts.other, counts.secret, counts.missing, counts.invalid))
    addon.Print(string.format("Mob probe: UNIT_HEALTH=%d, UNIT_FLAGS=%d, watched event checks=%d, dead observations=%d; poll checks=%d, dead observations=%d.",
        counts.healthEvents, counts.flagsEvents, counts.eventChecks, counts.eventDead, counts.pollChecks, counts.pollDead))
end

function Probe:OnEnable()
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, value)
        if not running then return end
        if event == "UNIT_DIED" then
            onUnitDied(value)
        elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
            local key = event == "UNIT_HEALTH" and "healthEvents" or "flagsEvents"
            counts[key] = counts[key] + 1
            if not (issecretvalue and issecretvalue(value)) and type(value) == "string" then
                observeState("event", value, event)
            end
        end
    end)
    self.frame:SetScript("OnUpdate", function(_, delta)
        if not running or not watched or not watched.guid then return end
        elapsed = elapsed + delta
        if elapsed < 0.5 then return end
        elapsed = 0
        local unit = liveUnit(watched.guid)
        if unit then
            if watched.lost then report("Watched GUID has a live token again: " .. unit .. ".") end
            watched.lost = false
            observeState("poll", unit)
        elseif not watched.lost then
            watched.lost = true
            watched.eventDead, watched.pollDead = nil, nil
            report("No live token for watched GUID; state transitions are now unknown.")
        end
    end)
end

function Probe:HandleCommand(message)
    local command = (message or ""):match("^%s*(%S*)"):lower()
    if command == "start" then
        if running then addon.Print("Mob probe: already running; stop first to reset.") return end
        running, watched, elapsed, lines = true, nil, 0, 0
        reportedErrors, registered = {}, {}
        counts = { deaths = 0, matches = 0, other = 0, secret = 0, missing = 0, invalid = 0,
            healthEvents = 0, flagsEvents = 0, eventChecks = 0, eventDead = 0, pollChecks = 0, pollDead = 0 }
        for _, event in ipairs({ "UNIT_DIED", "UNIT_HEALTH", "UNIT_FLAGS" }) do
            local ok, err = pcall(self.frame.RegisterEvent, self.frame, event)
            if ok then
                registered[#registered + 1] = event
            else
                addon.Print("Mob probe: could not register " .. event .. ": " .. tostring(err) .. ". That approach cannot be tested.")
            end
        end
        addon.Print("Mob probe: started. Target a living mob and use /saboton mobprobe watch.")
        status()
    elseif command == "stop" then
        if running then
            self.frame:UnregisterAllEvents()
            running, watched = false, nil
        end
        addon.Print("Mob probe: stopped; session results cleared.")
    elseif command == "watch" then
        if not running then addon.Print("Mob probe: start the probe first.") return end
        local guid, guidState = guidOf("target")
        local name, nameState = readUnit(UnitName, "target", "UnitName")
        local dead, deadState = deadOf("target")
        if nameState ~= "readable" or type(name) ~= "string" then name = "<" .. nameState .. " name>" end
        watched = { guid = guid, guidState = guidState, name = name:gsub("|", "||"),
            initialState = deadState == "readable" and (dead and "dead" or "alive") or deadState,
            eventDead = dead, pollDead = dead, eventState = deadState, pollState = deadState }
        addon.Print("Mob probe: watching " .. watched.name .. "; GUID " .. guidState .. "; death state " .. watched.initialState .. ".")
        if not guid then addon.Print("Mob probe: GUID matching and state tracking cannot work for this target; event totals still count.") end
        if dead == true then addon.Print("Mob probe: target is already dead; select a living mob for a transition test.") end
    elseif command == "status" then
        status()
    else
        addon.Print("Mob probe commands: start, watch, status, stop. Session-only diagnostic; no timers.")
    end
end

addon.RegisterModule("mobprobe", Probe)
