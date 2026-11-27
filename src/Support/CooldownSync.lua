local _, addon = ...

local Sync = {}
addon.CooldownSync = Sync
Sync.PREFIX = "SECD1"
Sync.HEARTBEAT = 60
Sync.INTERVAL = 1.25
Sync.RETRY = 5

local function secret(value) return issecretvalue and issecretvalue(value) end
local function integer(value, maximum)
    return addon.PartyCooldowns.Number(value, 0, maximum) and value == math.floor(value)
end

function Sync.Encode(entries)
    if type(entries) ~= "table" or #entries > #addon.PartyCooldowns.presets then return nil end
    local parts, seen = {}, {}
    for _, entry in ipairs(entries) do
        local spell = addon.PartyCooldowns.Preset(entry.id)
        if not spell or seen[entry.id] then return nil end
        seen[entry.id] = true
        if not integer(entry.remaining, 7200) or not integer(entry.duration, 7200) then return nil end
        local active = entry.kind == "C" or entry.kind == "E"
        if active then
            if entry.remaining == 0 or entry.remaining > entry.duration then return nil end
        elseif (entry.kind ~= "R" and entry.kind ~= "U" and entry.kind ~= "N")
            or entry.remaining ~= 0 or entry.duration ~= 0 then return nil end
        parts[#parts + 1] = table.concat({ entry.id, entry.kind, entry.remaining, entry.duration }, ":")
    end
    local packet = "S|1|" .. table.concat(parts, ",")
    if #packet > 255 then return nil end
    return packet
end

function Sync.Decode(packet)
    if secret(packet) or type(packet) ~= "string" or #packet > 255 then return nil end
    if packet == "R|1" then return "request" end
    local body = packet:match("^S|1|(.*)$")
    if not body then return nil end
    if body == "" then return "state", {} end
    local entries = {}
    for part in (body .. ","):gmatch("(.-),") do
        local id, kind, remaining, duration = part:match("^(%d+):([RCEUN]):(%d+):(%d+)$")
        if not id or #id > 6 or #remaining > 4 or #duration > 4 then return nil end
        entries[#entries + 1] = { id = tonumber(id), kind = kind, remaining = tonumber(remaining), duration = tonumber(duration) }
    end
    if Sync.Encode(entries) ~= packet then return nil end
    return "state", entries
end

function Sync.New(config)
    return setmetatable({ config = config, peers = {}, status = "disabled", nextSend = 0,
        lastSend = -math.huge, sent = 0, received = 0, rejected = 0 }, { __index = Sync })
end

function Sync:SetStatus(status, notify)
    if self.status ~= status then
        self.status = status
        if notify then self.config.notify(status) end
    end
end

function Sync:Register()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        self:SetStatus("addon messaging unavailable", true)
        return false
    end
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Sync.PREFIX)
    self.registered = ok and result == true
    if not self.registered then self:SetStatus("could not register cooldown message prefix", true) end
    return self.registered
end

function Sync:Reset()
    self.peers, self.signature, self.request, self.replyAt, self.channel = {}, nil, nil, nil, nil
    self.lastSend = -math.huge
end

function Sync:Tick(now)
    if not self.config.enabled() then
        self:Reset()
        self:SetStatus("disabled")
        return
    end
    if not self.registered then return end
    local channel = self.config.channel()
    if not channel then
        self:Reset()
        self:SetStatus("not grouped")
        return
    end
    if self.channel ~= channel then
        self:Reset()
        self.channel, self.request = channel, true
    end
    for guid, peer in pairs(self.peers) do
        if not self.config.member(guid) then self.peers[guid] = nil end
    end
    local gate = self.config.gate()
    if gate then self:SetStatus("deferred: " .. gate, true) return end
    if now < self.nextSend then return end
    local entries, signature = self.config.snapshot(now)
    local packet
    if self.request then packet = "R|1"
    elseif signature ~= self.signature or now - self.lastSend >= Sync.HEARTBEAT
        or (self.replyAt and now >= self.replyAt) then packet = Sync.Encode(entries)
    else return end
    if not packet then self:SetStatus("invalid local cooldown snapshot", true) return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, Sync.PREFIX, packet, channel)
    self.sent = self.sent + 1
    self.config.trace("send " .. packet .. "; " .. (ok and not secret(result) and tostring(result) or "API error/restricted"))
    local results = Enum and Enum.SendAddonMessageResult or {}
    self.nextSend = now + Sync.INTERVAL
    if ok and not secret(result) and result == (results.Success or 0) then
        if self.request then self.request = false
        else self.signature, self.lastSend, self.replyAt = signature, now, nil end
        self:SetStatus("sharing (submission accepted; delivery not confirmed)")
    else
        self.nextSend = now + Sync.RETRY
        local retry = ok and not secret(result) and (result == (results.AddonMessageThrottle or 3)
            or result == (results.ChannelThrottle or 8) or result == (results.AddOnMessageLockdown or 11))
        self:SetStatus(retry and "deferred: server throttle/chat lockdown" or "cooldown message submission failed", true)
    end
end

function Sync:Receive(prefix, packet, channel, sender, now)
    if secret(prefix) or prefix ~= Sync.PREFIX or not self.config.enabled() then return end
    if secret(channel) or channel ~= self.config.channel() or secret(sender) then return end
    local guid = self.config.resolve(sender)
    if not guid or guid == self.config.selfGUID() then return end
    local kind, entries = Sync.Decode(packet)
    if not kind then
        self.rejected = self.rejected + 1
        self.config.trace("rejected malformed cooldown packet")
        return
    end
    local peer = self.peers[guid] or {}
    if peer.lastReceive and now - peer.lastReceive < 1 then
        self.rejected = self.rejected + 1
        self.config.trace("ignored cooldown packet rate limit")
        return
    end
    if kind == "state" then
        for _, entry in ipairs(entries) do
            if not self.config.allowed(guid, entry.id) then
                self.rejected = self.rejected + 1
                self.config.trace("rejected cooldown class mismatch")
                return
            end
        end
    end
    peer.lastReceive = now
    self.peers[guid] = peer
    self.received = self.received + 1
    if kind == "request" then
        self.replyAt = self.replyAt or (now + 1 + math.random() * 2)
    else
        peer.lastState = now
        self.config.apply(guid, entries, now)
    end
    self.config.trace("received cooldown " .. kind)
end
