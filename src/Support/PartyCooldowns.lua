local _, addon = ...

local Tracker = {}
addon.PartyCooldowns = Tracker

Tracker.MAX_SECONDS = 7200
Tracker.FRESH_SECONDS = 180
Tracker.presets = {
    { key = "innervate", name = "Innervate", class = "DRUID", category = "Utility", default = true, minLevel = 40, duration = 360,
      effectDuration = 20, ids = { 29166 } },
    { key = "rebirth", name = "Rebirth", class = "DRUID", category = "Utility", default = true, minLevel = 20, duration = 1800,
      ids = { 20484, 20739, 20742, 20747, 20748 } },
    { key = "soulstone", name = "Soulstone Resurrection", label = "Soulstone application", class = "WARLOCK",
      category = "Utility", default = true, minLevel = 18, duration = 1800,
      ids = { 20707, 20762, 20763, 20764, 20765 }, items = { 5232, 16892, 16893, 16895, 16896 } },
    { key = "tranquility", name = "Tranquility", class = "DRUID", category = "Utility", minLevel = 30,
      duration = 300, ids = { 740, 8918, 9862, 9863 } },
    { key = "manatide", name = "Mana Tide Totem", class = "SHAMAN", category = "Utility", minLevel = 1,
      duration = 300, ids = { 16190, 17354, 17359 } },
    { key = "layonhands", name = "Lay on Hands", class = "PALADIN", category = "Defensive", minLevel = 10, duration = 1200,
      ids = { 633, 2800, 10310 } },
    { key = "shieldwall", name = "Shield Wall", class = "WARRIOR", category = "Defensive", minLevel = 28, duration = 900,
      effectDuration = 12, effectOnCaster = true, ids = { 871 } },
    { key = "frenziedregeneration", name = "Frenzied Regeneration", class = "DRUID", category = "Defensive",
      minLevel = 36, duration = 180, effectDuration = 10, effectOnCaster = true, ids = { 22842 } },
    { key = "barkskin", name = "Barkskin", class = "DRUID", category = "Defensive", minLevel = 44,
      duration = 60, effectDuration = 15, effectOnCaster = true, ids = { 22812 } },
    { key = "laststand", name = "Last Stand", class = "WARRIOR", category = "Defensive", minLevel = 1,
      duration = 180, effectDuration = 20, ids = { 12975 } },
    { key = "blessingofprotection", name = "Blessing of Protection", class = "PALADIN", category = "Defensive",
      minLevel = 10, duration = 300, ids = { 1022, 5599, 10278 } },
    { key = "divineshield", name = "Divine Shield", class = "PALADIN", category = "Defensive", minLevel = 34,
      duration = 300, effectDuration = 10, effectOnCaster = true, ids = { 642 } },
    { key = "deterrence", name = "Deterrence", class = "HUNTER", category = "Defensive", minLevel = 20,
      duration = 300, effectDuration = 10, effectOnCaster = true, ids = { 19263 } },
    { key = "vanish", name = "Vanish", class = "ROGUE", category = "Defensive", minLevel = 22,
      duration = 300, ids = { 1856, 1857 } },
    { key = "recklessness", name = "Recklessness", class = "WARRIOR", category = "Offensive", minLevel = 50,
      duration = 1800, effectDuration = 15, effectOnCaster = true, ids = { 1719 } },
    { key = "powerinfusion", name = "Power Infusion", class = "PRIEST", category = "Offensive", minLevel = 40,
      duration = 180, effectDuration = 15, ids = { 10060 } },
    { key = "arcanepower", name = "Arcane Power", class = "MAGE", category = "Offensive", minLevel = 1,
      duration = 180, effectDuration = 15, effectOnCaster = true, ids = { 12042 } },
    { key = "adrenalinerush", name = "Adrenaline Rush", class = "ROGUE", category = "Offensive", minLevel = 1,
      duration = 300, effectDuration = 15, effectOnCaster = true, ids = { 13750 } },
    { key = "bestialwrath", name = "Bestial Wrath", class = "HUNTER", category = "Offensive", minLevel = 40,
      duration = 120, effectDuration = 18, ids = { 19574 } },
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
    return setmetatable({ roster = {}, records = {}, effects = {}, recent = {} }, { __index = Tracker })
end

function Tracker:SetRoster(roster)
    self.roster = roster
    for guid in pairs(self.records) do
        if not roster[guid] then self.records[guid], self.recent[guid] = nil, nil end
    end
    for guid in pairs(self.effects) do
        if not roster[guid] then self.effects[guid] = nil end
    end
end

function Tracker:WriteEffect(guid, key, kind, remaining, duration, source, now)
    local spell, member = Tracker.Preset(key), self.roster[guid]
    if not spell or not spell.effectDuration or not member or member.class ~= spell.class then return false end
    if kind ~= "C" and kind ~= "E" and kind ~= "R" and kind ~= "U" then return false end
    if not Tracker.Number(remaining, 0, 120) or not Tracker.Number(duration, 0, 120) then return false end
    local active = kind == "C" or kind == "E"
    if active and (remaining <= 0 or remaining > duration) then return false end
    if not active and (remaining ~= 0 or duration ~= 0) then return false end
    self.effects[guid] = self.effects[guid] or {}
    local old = self.effects[guid][key]
    if kind == "U" and old and old.endsAt > now then
        old.kind = "E"
        return true
    end
    self.effects[guid][key] = {
        kind = kind, endsAt = now + remaining, duration = duration, source = source, observedAt = now,
    }
    return true
end

function Tracker:EffectState(guid, key, now)
    local record = self.effects[guid] and self.effects[guid][key]
    if not record then return "unknown", 0 end
    if record.kind == "C" or record.kind == "E" then
        local left = math.max(0, record.endsAt - now)
        if left > 0 then return record.kind == "C" and "active" or "estimated", left, record end
    elseif record.kind == "R" and now - record.observedAt < Tracker.FRESH_SECONDS and now >= record.observedAt then
        return "inactive", 0, record
    end
    return "unknown", 0, record
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
    local written = self:Write(guid, key, "E", duration, duration, "cast estimate", now)
    if written and spell.effectDuration then
        self:WriteEffect(guid, key, "E", spell.effectDuration, spell.effectDuration, "cast estimate", now)
    end
    return written
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
            if spell.effectDuration then
                local effectState, effectLeft, effect = self:EffectState(guid, spell.key, now)
                out[#out].effectKind = ({ active = "C", estimated = "E", inactive = "R", unknown = "U" })[effectState]
                out[#out].effectRemaining = math.ceil(effectLeft)
                out[#out].effectDuration = effectLeft > 0 and math.ceil(effect.duration) or 0
                signature[#signature + 1] = spell.key .. ":effect:" .. out[#out].effectKind ..
                    ":" .. (effectLeft > 0 and effect.endsAt or 0)
            end
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
    if type(saved) ~= "table" or #saved > #Tracker.presets * 40 then return false end
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
