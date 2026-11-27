local _, addon = ...

local Module = {}
local Tracking, Transport = addon.PartyCooldowns, addon.CooldownSync
local tracker = Tracking.New()
local enabled, sharing, locked, showSelf = false, true, true, true
local width, height = 330, 20
local selected = { innervate = true, rebirth = true, layonhands = true }
local position, selfGUID, sync, restoredTimers
local unitGUID, aliases, rows, reported = {}, {}, {}, {}
local debug, debugLines, testMode, testStart = false, 0, false, 0
local counts = { casts = 0, hidden = 0 }
local nextPoll, savedSignature = 0, nil
local restricted = false
local page, PAGE_ROWS = 1, 12

local function secret(value) return issecretvalue and issecretvalue(value) end
local function escape(value) return tostring(value):gsub("|", "||") end
local function notify(message)
    if not reported[message] then
        reported[message] = true
        addon.Print("Party cooldowns: " .. message .. ".")
    end
end
local function trace(message)
    if not debug or debugLines >= 120 then return end
    debugLines = debugLines + 1
    addon.Print("Party cooldown debug: " .. escape(message))
    if debugLines == 120 then addon.Print("Party cooldown debug: 120-line limit reached.") end
end
local function save()
    if addon.SaveSettings then addon.SaveSettings() end
end
local function read(fn, label, ...)
    if type(fn) ~= "function" then notify(label .. " unavailable") return nil end
    local ok, value = pcall(fn, ...)
    if not ok then notify(label .. " failed") return nil end
    if secret(value) then return nil end
    return value
end
local function field(info, key)
    if secret(info) or type(info) ~= "table" or (issecrettable and issecrettable(info)) then return nil, false end
    local value = info[key]
    if not secret(value) then return value, true end
    return nil, false
end
local function validName(value)
    return not secret(value) and type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]")
end
local function alias(name, guid)
    if not validName(name) then return end
    name = name:gsub(" ", "-")
    if aliases[name] and aliases[name] ~= guid then aliases[name] = false
    elseif aliases[name] == nil then aliases[name] = guid end
end

local function channel()
    local instance = LE_PARTY_CATEGORY_INSTANCE
    if instance and read(IsInGroup, "IsInGroup", instance) == true
        and read(IsInGroup, "IsInGroup", LE_PARTY_CATEGORY_HOME) ~= true then return "INSTANCE_CHAT" end
    if read(IsInRaid, "IsInRaid") == true then return "RAID" end
    if read(IsInGroup, "IsInGroup") == true then return "PARTY" end
end

local function rebuildRoster()
    local units, roster = { "player" }, {}
    if read(IsInRaid, "IsInRaid") == true then
        local count = read(GetNumGroupMembers, "GetNumGroupMembers")
        if Tracking.Number(count, 0, 40) then
            for index = 1, count do units[#units + 1] = "raid" .. index end
        end
    else
        local count = read(GetNumSubgroupMembers, "GetNumSubgroupMembers")
        if Tracking.Number(count, 0, 4) then
            for index = 1, count do units[#units + 1] = "party" .. index end
        end
    end
    unitGUID, aliases = {}, {}
    for _, unit in ipairs(units) do
        local guid = read(UnitGUID, "UnitGUID", unit)
        if validName(guid) then
            unitGUID[unit] = guid
            if unit == "player" then selfGUID = guid end
            local old = tracker.roster[guid]
            local ok, name, second = pcall(UnitName, unit)
            if not ok then name, second = nil, nil notify("UnitName failed") end
            if not validName(name) then name = old and old.name end
            if validName(name) then
                if validName(second) and not name:find("-", 1, true) and not name:find(" ", 1, true) then
                    name = name .. "-" .. second
                end
                alias(name, guid)
                if validName(second) then
                    local first = name:match("^([^%- ]+)")
                    alias(first, guid)
                end
            end
            local class
            local classOK, _, classValue = pcall(UnitClass, unit)
            if classOK and not secret(classValue) and type(classValue) == "string" then class = classValue
            else class = old and old.class if not classOK then notify("UnitClass failed") end end
            local level = read(UnitLevel, "UnitLevel", unit)
            roster[guid] = { unit = unit, name = name or "?", class = class,
                level = Tracking.Number(level, 1, 100) and level or nil,
                online = read(UnitIsConnected, "UnitIsConnected", unit),
                dead = read(UnitIsDeadOrGhost, "UnitIsDeadOrGhost", unit) }
        end
    end
    tracker:SetRoster(roster)
    if not roster[selfGUID] then selfGUID = nil end
end

local function resolve(sender)
    if not validName(sender) then return nil end
    local name = sender:gsub(" ", "-")
    if aliases[name] then return aliases[name] end
    local realm = GetNormalizedRealmName and read(GetNormalizedRealmName, "GetNormalizedRealmName")
    if validName(realm) and name:sub(-#realm - 1) == "-" .. realm then
        return aliases[name:sub(1, -#realm - 2)] or nil
    end
end

local function spellIDs(spell)
    local ids = {}
    for _, id in ipairs(spell.ids) do ids[#ids + 1] = id end
    local name = addon.Spells.Name(spell.ids[1])
    local info = C_Spell and read(C_Spell.GetSpellInfo, "GetSpellInfo", name or spell.name)
    local id = field(info, "spellID")
    if Tracking.Number(id, 1, 1000000) and id == math.floor(id) then ids[#ids + 1] = id end
    return ids
end

local function knownSpell(spell)
    local knownAPI = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell or IsSpellKnown
    local complete = true
    for _, id in ipairs(spellIDs(spell)) do
        local known = read(knownAPI, "spellbook known-spell lookup", id)
        if known == true then return id, true end
        if known ~= false then complete = false end
    end
    if complete then return nil, false end
    return nil, nil
end

local function pollSelf(now)
    local member = selfGUID and tracker.roster[selfGUID]
    if not member then return end
    for _, spell in ipairs(Tracking.presets) do
        if member.class == spell.class then
            local id, known = knownSpell(spell)
            local kind, remaining, duration = "U", 0, 0
            if known == false then kind = "N"
            elseif known then
                local info = C_Spell and read(C_Spell.GetSpellCooldown, "GetSpellCooldown", id)
                local start, length = field(info, "startTime"), field(info, "duration")
                local rate, rateAccessible = field(info, "modRate")
                local onGCD, gcdAccessible = field(info, "isOnGCD")
                local isEnabled, enabledAccessible = field(info, "isEnabled")
                if rateAccessible and rate == nil then rate = 1 end
                if Tracking.Number(start, 0, math.huge) and Tracking.Number(length, 0, 7200)
                    and start <= now and rateAccessible and gcdAccessible and enabledAccessible
                    and Tracking.Number(rate, 0.01, 100) and isEnabled ~= false and onGCD ~= true then
                    duration = length / rate
                    remaining = math.max(0, start + duration - now)
                    if length == 0 or remaining == 0 then kind, remaining, duration = "R", 0, 0
                    elseif duration > 1.5 and duration <= 7200 then kind = "C"
                    else remaining, duration = 0, 0 end
                end
            end
            local recent = tracker.recent[selfGUID] and tracker.recent[selfGUID][spell.key]
            local state, left = tracker:State(selfGUID, spell.key, now)
            if (kind == "R" and recent and now - recent < 2)
                or (kind == "U" and left > 0 and (state == "cooldown" or state == "estimated")) then
                -- Cooldown updates can lag the cast, and restricted reads do not cancel a known timer.
            else
                if not tracker:Write(selfGUID, spell.key, kind, remaining, duration, "own client", now) then
                    notify("invalid own cooldown data; readiness is unknown")
                    tracker:Write(selfGUID, spell.key, "U", 0, 0, "own client", now)
                end
            end
        end
    end
end

local function onCast(unit, id, now)
    if secret(unit) or type(unit) ~= "string" or not unitGUID[unit] then return end
    if secret(id) then counts.hidden = counts.hidden + 1 trace("group cast has a restricted spell ID") return end
    if not Tracking.Number(id, 1, 1000000) then return end
    local guid, name = unitGUID[unit], addon.Spells.Name(id)
    for _, spell in ipairs(Tracking.presets) do
        local matches = false
        for _, rank in ipairs(spell.ids) do if rank == id then matches = true end end
        if not matches and name then matches = name == addon.Spells.Name(spell.ids[1]) end
        local member = tracker.roster[guid]
        if matches and member and member.class == spell.class then
            if tracker:Cast(guid, spell.key, spell.duration, now) then
                counts.casts = counts.casts + 1
                trace("observed " .. spell.key .. " cast; base-duration estimate")
                save()
            end
            nextPoll = 0
            return
        end
    end
end

local function timeText(seconds)
    local value = math.ceil(seconds)
    return string.format("%d:%02d", math.floor(value / 60), value % 60)
end
local colors = { ready = { 0.15, 0.7, 0.25 }, cooldown = { 0.2, 0.5, 0.9 },
    estimated = { 0.75, 0.5, 0.1 }, unknown = { 0.35, 0.35, 0.35 } }

local function entries(now)
    local out = {}
    if testMode then
        local left = 45 - (now - testStart) % 45
        return {
            { name = "Preview: ready", spell = Tracking.presets[1], state = "ready", left = 0 },
            { name = "Preview: reported", spell = Tracking.presets[2], state = "cooldown", left = left, duration = 45 },
            { name = "Preview: estimated", spell = Tracking.presets[3], state = "estimated", left = left, duration = 45 },
            { name = "Preview: unknown", spell = Tracking.presets[1], state = "unknown", left = 0 },
        }
    end
    for _, spell in ipairs(Tracking.presets) do
        if selected[spell.key] then
            for guid, member in pairs(tracker.roster) do
                if (showSelf or guid ~= selfGUID) and tracker:Eligible(guid, spell, now) then
                    local state, left, record = tracker:State(guid, spell.key, now)
                    out[#out + 1] = { guid = guid, name = member.name, spell = spell, state = state, left = left,
                        duration = record and record.duration, record = record,
                        unavailable = member.online == false and "Offline" or member.dead == true and "Dead" or nil }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.spell.key ~= b.spell.key then return a.spell.key < b.spell.key end
        if a.name ~= b.name then return a.name < b.name end
        return a.guid < b.guid
    end)
    return out
end

local function render(now)
    if not Module.frame then return end
    local list = (enabled or testMode) and entries(now) or {}
    local pages = math.max(1, math.ceil(#list / PAGE_ROWS))
    page = math.min(page, pages)
    local first = (page - 1) * PAGE_ROWS + 1
    local last = math.min(#list, first + PAGE_ROWS - 1)
    for _, row in ipairs(rows) do row:Hide() row.title:Hide() end
    for index = first, last do
        local entry, displayIndex = list[index], index - first + 1
        local row = rows[displayIndex]
        if not row then
            row = addon.TimerBars.Create(Module.frame, "", width, height, "HORIZONTAL")
            rows[displayIndex] = row
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if not GameTooltip or not self.entry then return end
                local item = self.entry
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(escape(item.name) .. " - " .. escape(addon.Spells.Label(item.spell.ids[1])))
                if item.record then
                    GameTooltip:AddLine("Source: " .. item.record.source .. "; observed " ..
                        math.floor(GetTime() - item.record.observedAt) .. "s ago", 1, 1, 1)
                else GameTooltip:AddLine("No current readable report. Unknown is not Ready.", 1, 1, 1) end
                GameTooltip:AddLine("Countdown expiry does not confirm readiness.", 1, 0.8, 0.2)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        row.entry = entry
        row:SetSize(width, height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", Module.frame, "TOPLEFT", 0, -(displayIndex - 1) * (height + 3))
        local label = entry.unavailable or ({ ready = "Reported ready", cooldown = timeText(entry.left),
            estimated = "~" .. timeText(entry.left), unknown = "Unknown" })[entry.state]
        row.text:SetText(escape(entry.name) .. " - " .. escape(addon.Spells.Label(entry.spell.ids[1])) .. ": " .. label)
        local color = colors[entry.unavailable and "unknown" or entry.state]
        row.bar:SetStatusBarColor(color[1], color[2], color[3])
        row.bar:SetValue(entry.left > 0 and math.min(1, entry.left / math.max(1, entry.duration)) or 1)
        row:Show()
    end
    Module.header:SetText("Party cooldowns" .. (testMode and " - PREVIEW" or "") ..
        (pages > 1 and " (" .. page .. "/" .. pages .. ")" or ""))
    Module.previous:SetShown(pages > 1)
    Module.next:SetShown(pages > 1)
    Module.frame:SetSize(width, math.max(1, math.min(#list, PAGE_ROWS) * (height + 3)))
    Module.frame:SetShown(#list > 0 or (enabled and not locked))
end

function Module:SetEnabled(value)
    if enabled == value then return end
    enabled, testMode = value, false
    savedSignature, restricted, page = nil, false, 1
    tracker.records, tracker.recent = {}, {}
    if sync then sync:Reset() if not enabled then sync:SetStatus("disabled") end end
    nextPoll = 0
    if enabled and self.frame then
        rebuildRoster()
        pollSelf(GetTime())
        if sync and not sync.registered then sync:Register() end
    end
    render(GetTime())
end

function Module:GetOptionsSchema()
    local options = {
        { type = "checkbox", key = "enabled", label = "Enable Party Cooldowns (beta)", section = "General",
          default = false, get = function() return enabled end, set = function(v) Module:SetEnabled(v) end,
          tooltip = "Tracks readable reports and estimated casts. Unknown does not mean Ready." },
        { type = "checkbox", key = "sharing", label = "Share my cooldowns with group members", section = "General",
          default = true, get = function() return sharing end,
          set = function(v)
              sharing = v
              if sync then sync:Reset() end
              tracker:InvalidateReady()
          end,
          tooltip = "Requires this module enabled on reporting players. Combat/chat restrictions may delay updates. Uses party/raid messages, not guild sync." },
        { type = "checkbox", key = "showSelf", label = "Include my character", section = "General",
          default = true, get = function() return showSelf end, set = function(v) showSelf = v render(GetTime()) end },
        { type = "checkbox", key = "locked", label = "Lock window position", section = "Appearance",
          default = true, get = function() return locked end,
          set = function(v) locked = v if Module.handle then Module.handle:EnableMouse(not v) end render(GetTime()) end },
        { type = "slider", key = "width", label = "Window width", section = "Appearance",
          min = 200, max = 600, step = 10, default = 330, format = "%dpx",
          get = function() return width end,
          set = function(v) if Tracking.Number(v, 200, 600) then width = v render(GetTime()) end end },
        { type = "slider", key = "height", label = "Row height", section = "Appearance",
          min = 16, max = 40, step = 1, default = 20, format = "%dpx",
          get = function() return height end,
          set = function(v) if Tracking.Number(v, 16, 40) then height = v render(GetTime()) end end },
    }
    for _, spell in ipairs(Tracking.presets) do
        options[#options + 1] = { type = "checkbox", key = spell.key, label = addon.Spells.Label(spell.ids[1]),
            section = "Tracked abilities", default = true,
            get = function() return selected[spell.key] end,
            set = function(v) selected[spell.key] = v render(GetTime()) end,
            tooltip = "Display this ability. Reporting includes every preset of your class even when its display is hidden." }
    end
    return { name = "Party Cooldowns (beta)", enabledKey = "enabled", options = options }
end

function Module:GetPersistentState()
    return { position = position, timers = tracker:Save(GetTime(), time()) }
end
function Module:LoadPersistentState(state)
    if type(state) ~= "table" then return end
    restoredTimers = state.timers
    local p = state.position
    if type(p) == "table" and Tracking.Number(p.x, -10000, 10000) and Tracking.Number(p.y, -10000, 10000) then
        position = { x = p.x, y = p.y }
        if self.frame then
            self.frame:ClearAllPoints()
            self.frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
        end
    end
end
function Module:FinishRestore()
    rebuildRoster()
    if enabled then
        if restoredTimers and not tracker:Restore(restoredTimers, GetTime(), time()) then notify("invalid saved cooldown timers discarded") end
        pollSelf(GetTime())
    end
    restoredTimers = nil
    if sync then sync:Register() end
    render(GetTime())
end

function Module:OnEnable()
    self.frame = CreateFrame("Frame", "SabotonPartyCooldownFrame", UIParent)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    self.handle = CreateFrame("Frame", nil, self.frame)
    self.handle:SetHeight(18)
    self.handle:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT")
    self.handle:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT")
    addon.TimerBars.MakeMovable(self.frame, function() return locked end,
        function(x, y) position = { x = x, y = y } end, self.handle)
    self.header = self.handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.header:SetPoint("LEFT", self.handle, "LEFT", 0, 0)
    self.previous = CreateFrame("Button", nil, self.handle, "UIPanelButtonTemplate")
    self.previous:SetSize(22, 18)
    self.previous:SetPoint("RIGHT", self.handle, "RIGHT", -26, 0)
    self.previous:SetText("<")
    self.previous:SetScript("OnClick", function() page = math.max(1, page - 1) render(GetTime()) end)
    self.next = CreateFrame("Button", nil, self.handle, "UIPanelButtonTemplate")
    self.next:SetSize(22, 18)
    self.next:SetPoint("RIGHT", self.handle, "RIGHT", 0, 0)
    self.next:SetText(">")
    self.next:SetScript("OnClick", function() page = page + 1 render(GetTime()) end)
    self.frame:Hide()
    sync = Transport.New({
        enabled = function() return enabled and sharing end,
        channel = channel, resolve = resolve, selfGUID = function() return selfGUID end,
        member = function(guid) return tracker.roster[guid] end,
        allowed = function(guid, id) return tracker.roster[guid].class == Tracking.Preset(id).class end,
        snapshot = function(now) return tracker:Snapshot(selfGUID, now) end,
        apply = function(guid, reports, now)
            -- Each packet is a full class snapshot; omitted entries are explicitly unknown.
            local incoming = {}
            for _, entry in ipairs(reports) do incoming[entry.id] = entry end
            for _, spell in ipairs(Tracking.presets) do
                if tracker.roster[guid].class == spell.class then
                    local entry = incoming[spell.ids[1]]
                    tracker:Write(guid, spell.key, entry and entry.kind or "U", entry and entry.remaining or 0,
                        entry and entry.duration or 0, "group report", now)
                end
            end
            save()
        end,
        gate = function()
            local reason
            if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then reason = "addon messaging unavailable" end
            if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and read(C_ChatInfo.InChatMessagingLockdown, "chat lockdown") == true then
                reason = "chat lockdown"
            end
            local chat = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
            if chat and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
                and read(C_RestrictedActions.IsAddOnRestrictionActive, "chat restriction", chat) == true then reason = "chat restriction" end
            if reason and not restricted then tracker:InvalidateReady(selfGUID) end
            restricted = reason ~= nil
            return reason
        end,
        notify = notify, trace = trace,
    })
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, a, b, c, d)
        if not enabled then return end
        local now = GetTime()
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "UNIT_CONNECTION"
            or event == "UNIT_LEVEL" then
            rebuildRoster()
            nextPoll = 0
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                sync.request, sync.signature = true, nil
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then onCast(a, c, now)
        elseif event == "CHAT_MSG_ADDON" then sync:Receive(a, b, c, d, now)
        elseif event == "PLAYER_REGEN_DISABLED" then tracker:InvalidateReady(selfGUID) nextPoll = 0
        elseif event == "PLAYER_REGEN_ENABLED" then rebuildRoster() nextPoll = 0 sync.signature = nil
        elseif event == "PLAYER_LOGOUT" then save()
        elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELLS_CHANGED" then nextPoll = 0 end
    end)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_CONNECTION", "UNIT_LEVEL",
        "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_ADDON", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT",
        "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED" }) do
        local ok = pcall(self.events.RegisterEvent, self.events, event)
        if not ok then notify("could not register " .. event) end
    end
    self.ticker = C_Timer.NewTicker(0.25, function()
        local now = GetTime()
        if enabled then
            if now >= nextPoll then
                pollSelf(now)
                nextPoll = now + 0.5
                local _, signature = tracker:Snapshot(selfGUID, now)
                if signature ~= savedSignature then save() savedSignature = signature end
            end
            sync:Tick(now)
        end
        render(now)
    end)
end

function Module:HandleCommand(message)
    local command, rest = (message or ""):match("^(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "options" then
        if addon.modules.options then addon.modules.options:HandleCommand("partycooldowns")
        else notify("options module unavailable") end
    elseif command == "enable" or command == "disable" then
        self:SetEnabled(command == "enable")
        addon.Print("Party cooldowns " .. (enabled and "enabled." or "disabled."))
    elseif command == "test" then
        testMode, testStart = not testMode, GetTime()
        render(GetTime())
        addon.Print("Party cooldown preview " .. (testMode and "on (simulated rows are never shared)." or "off."))
    elseif command == "lock" or command == "unlock" then
        locked = command == "lock"
        self.handle:EnableMouse(not locked)
        render(GetTime())
    elseif command == "sync" and (rest == "on" or rest == "off") then
        sharing = rest == "on"
        sync:Reset()
        tracker:InvalidateReady()
        addon.Print("Party cooldown sharing " .. (sharing and "on." or "off."))
    elseif command == "debug" then
        debug, debugLines = not debug, 0
        addon.Print("Party cooldown debug " .. (debug and "on (120-line cap)." or "off."))
    elseif command == "status" or (command == "sync" and rest == "status") then
        local peers = 0
        for _, peer in pairs(sync.peers) do if peer.lastState and GetTime() - peer.lastState < Tracking.FRESH_SECONDS then peers = peers + 1 end end
        addon.Print("Party cooldowns: " .. (enabled and "enabled" or "disabled") .. "; sharing " .. (sharing and "on" or "off") ..
            "; " .. sync.status .. "; fresh reporting peers=" .. peers .. ".")
        addon.Print("Observed casts=" .. counts.casts .. "; hidden cast IDs=" .. counts.hidden ..
            "; send attempts=" .. sync.sent .. "; received=" .. sync.received .. "; rejected=" .. sync.rejected .. ".")
        for _, entry in ipairs(entries(GetTime())) do
            addon.Print(escape(entry.name) .. " - " .. entry.spell.name .. ": " .. entry.state ..
                (entry.left > 0 and " " .. timeText(entry.left) or ""))
        end
    else
        addon.Print("Party cooldowns: options, enable|disable, status, test, lock|unlock, sync on|off|status, debug.")
    end
end

addon.RegisterModule("partycooldowns", Module)
