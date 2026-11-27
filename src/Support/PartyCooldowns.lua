local _, addon = ...

local Tracker = {}
addon.PartyCooldowns = Tracker

Tracker.MAX_SECONDS = 7200
Tracker.FRESH_SECONDS = 180
Tracker.presets = {
    { key = "innervate", name = "Innervate", class = "DRUID", minLevel = 40, duration = 360, ids = { 29166 } },
    { key = "rebirth", name = "Rebirth", class = "DRUID", minLevel = 20, duration = 1800,
      ids = { 20484, 20739, 20742, 20747, 20748 } },
    { key = "layonhands", name = "Lay on Hands", class = "PALADIN", minLevel = 10, duration = 3600,
      ids = { 633, 2800, 10310 } },
}

function Tracker.Number(value, minimum, maximum)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
        and value >= minimum and value <= maximum
end

function Tracker.Preset(key)
    for _, spell in ipairs(Tracker.presets) do
        if spell.key == key or spell.ids[1] == key then return spell end
    end
end

function Tracker.New()
    return setmetatable({ roster = {}, records = {}, recent = {} }, { __index = Tracker })
end

function Tracker:SetRoster(roster)
    self.roster = roster
    for guid in pairs(self.records) do
        if not roster[guid] then self.records[guid], self.recent[guid] = nil, nil end
    end
end

function Tracker:Write(guid, key, kind, remaining, duration, source, now)
    local spell, member = Tracker.Preset(key), self.roster[guid]
    if not spell or not member or member.class ~= spell.class then return false end
    if kind ~= "R" and kind ~= "C" and kind ~= "E" and kind ~= "U" and kind ~= "N" then return false end
    if not Tracker.Number(remaining, 0, Tracker.MAX_SECONDS)
        or not Tracker.Number(duration, 0, Tracker.MAX_SECONDS) then return false end
    if (kind == "C" or kind == "E") and (remaining <= 0 or remaining > duration) then return false end
    if kind ~= "C" and kind ~= "E" and (remaining ~= 0 or duration ~= 0) then return false end
    self.records[guid] = self.records[guid] or {}
    self.records[guid][spell.key] = {
        kind = kind, endsAt = now + remaining, duration = duration, source = source, observedAt = now,
    }
    return true
end

function Tracker:Cast(guid, key, duration, now)
    local spell = Tracker.Preset(key)
    if not spell or not self.roster[guid] then return false end
    self.recent[guid] = self.recent[guid] or {}
    local recent = self.recent[guid][spell.key]
    if recent and now - recent < 0.75 then return false end
    self.recent[guid][spell.key] = now
    return self:Write(guid, key, "E", duration, duration, "cast estimate", now)
end

function Tracker:InvalidateReady(exceptGUID)
    for guid, list in pairs(self.records) do
        if guid ~= exceptGUID then
            for _, record in pairs(list) do
                if record.kind == "R" then record.kind = "U" end
            end
        end
    end
end

function Tracker:State(guid, key, now)
    local list = self.records[guid]
    local record = list and list[key]
    if not record then return "unknown", 0, nil end
    local age = now - record.observedAt
    if record.kind == "C" or record.kind == "E" then
        local left = record.endsAt - now
        if left > 0 then
            return (record.kind == "E" or age >= Tracker.FRESH_SECONDS or age < 0) and "estimated" or "cooldown", left, record
        end
        return "unknown", 0, record
    end
    if age >= Tracker.FRESH_SECONDS or age < 0 then return "unknown", 0, record end
    if record.kind == "N" then return "notknown", 0, record end
    if record.kind == "R" then return "ready", 0, record end
    return "unknown", 0, record
end

function Tracker:Eligible(guid, spell, now)
    local member = self.roster[guid]
    if not member or member.class ~= spell.class then return false end
    if member.level and member.level < spell.minLevel then return false end
    return self:State(guid, spell.key, now) ~= "notknown"
end

function Tracker:Snapshot(guid, now)
    local out, signature = {}, {}
    for _, spell in ipairs(Tracker.presets) do
        local member = self.roster[guid]
        if member and member.class == spell.class then
            local state, left, record = self:State(guid, spell.key, now)
            local kind = ({ ready = "R", cooldown = "C", estimated = "E", notknown = "N", unknown = "U" })[state]
            local duration = left > 0 and math.ceil(record.duration) or 0
            out[#out + 1] = { id = spell.ids[1], kind = kind, remaining = math.ceil(left), duration = duration }
            signature[#signature + 1] = spell.key .. ":" .. kind .. ":" .. (left > 0 and record.endsAt or 0)
        end
    end
    return out, table.concat(signature, ",")
end

function Tracker:Save(now, wall)
    local out = {}
    for guid, list in pairs(self.records) do
        for key, record in pairs(list) do
            local left = record.endsAt - now
            if (record.kind == "C" or record.kind == "E") and left > 0 then
                out[#out + 1] = { guid = guid, key = key, endsAt = wall + left, duration = record.duration }
            end
        end
    end
    return out
end

function Tracker:Restore(saved, now, wall)
    if type(saved) ~= "table" or #saved > 120 then return false end
    for index = 1, #saved do
        local record = saved[index]
        if type(record) ~= "table" or type(record.guid) ~= "string" or #record.guid > 100
            or not Tracker.Preset(record.key) or not Tracker.Number(record.duration, 1, Tracker.MAX_SECONDS)
            or not Tracker.Number(record.endsAt, 0, 100000000000) then return false end
    end
    for _, record in ipairs(saved) do
        local left = record.endsAt - wall
        if left > 0 and left <= record.duration and self.roster[record.guid] then
            self:Write(record.guid, record.key, "E", left, record.duration, "restored estimate", now)
        end
    end
    return true
end
