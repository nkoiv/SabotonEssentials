local Harness = { clients = {}, now = 0, pending = {}, traffic = {}, timers = {} }
local current
unpack = unpack or table.unpack

Enum = {
    AddOnRestrictionType = { Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
    SendAddonMessageResult = {
        Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8,
        NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12,
    },
}
function GetTime() return Harness.now end
function time() return 2000000 + math.floor(Harness.now) end
function date() return "test date" end
function InCombatLockdown() return current.combat end
function IsInGuild() return current.guilded ~= false end
function GetGuildInfo() return current.guilded ~= false and (current.guild or "Test Guild") or nil end
function GetRealmName() return "Internal Realm" end
function GetNormalizedRealmName() return "InternalRealm" end
function RegionalUniqueNamesEnabled() return true end
function UnitName() return current.name:match("^([^%-]+)%-?(.*)$") end
function GetNumGuildMembers() return #Harness.clients end
function GetGuildRosterInfo(index)
    local client = Harness.clients[index]
    return client.rosterName or client.name, nil, nil, nil, nil, nil, "", "", not client.offline
end
C_RestrictedActions = { IsAddOnRestrictionActive = function() return current.chatRestricted end }
C_Timer = { After = function(delay, callback)
    Harness.timers[#Harness.timers + 1] = { client = current, at = Harness.now + delay, callback = callback }
end, NewTicker = function(_, callback)
    local ticker = { callback = callback }
    function ticker:Cancel() self.canceled = true end
    return ticker
end }
function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    current.frames[#current.frames + 1] = frame
    return frame
end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        assert(#prefix <= 16)
        current.registrations = (current.registrations or 0) + 1
        return not current.registrationFailed
    end,
    InChatMessagingLockdown = function() return current.lockdown end,
    AreOutgoingAddonChatMessagesRestricted = function() return current.outgoingRestricted end,
    SendAddonMessage = function(prefix, packet, channel)
        assert(not current.offline, "offline client attempted to send")
        current.apiCalls = (current.apiCalls or 0) + 1
        assert(#packet <= 255 and #prefix <= 16 and channel == "GUILD")
        assert(not current.combat and not current.lockdown and not current.chatRestricted,
            "sent during restriction")
        if current.lastSend then assert(Harness.now - current.lastSend >= 1.25, "send pacing exceeded") end
        current.lastSend = Harness.now
        local message = { sender = current, packet = packet, prefix = prefix, at = Harness.now, op = packet:sub(1, 1) }
        Harness.traffic[#Harness.traffic + 1] = message
        local result = Harness.result and Harness.result(message) or 0
        if result == 0 then Harness.pending[#Harness.pending + 1] = message end
        return result
    end,
}

function Harness:Select(client)
    current = client
    Spy, SpyPerCharDB = client.spy, client.db
end

function Harness:Reset()
    self.clients, self.pending, self.traffic, self.timers, self.now = {}, {}, {}, {}, 0
    self.drop, self.result = nil, nil
    math.randomseed(12345)
end

function Harness:Client(name)
    local client = { name = name, frames = {}, messages = {}, records = {}, confirmations = {}, enabled = true }
    self.clients[#self.clients + 1] = client
    self:Select(client)
    return client
end

function Harness:Event(client, event, ...)
    self:Select(client)
    for _, frame in ipairs(client.frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

function Harness:Run(seconds)
    for _ = 1, seconds * 4 do
        self.now = self.now + 0.25
        local timers = self.timers
        self.timers = {}
        for _, timer in ipairs(timers) do
            if timer.at <= self.now then self:Select(timer.client) timer.callback()
            else self.timers[#self.timers + 1] = timer end
        end
        for _, client in ipairs(self.clients) do
            self:Select(client)
            if client.engine and not client.offline then client.engine:Tick() end
        end
        local pending = self.pending
        self.pending = {}
        for _, message in ipairs(pending) do
            for _, client in ipairs(self.clients) do
                if not client.offline and not (self.drop and self.drop(message, client)) then
                    self:Event(client, "CHAT_MSG_ADDON", message.prefix, message.packet, "GUILD",
                        message.sender.senderName or message.sender.name)
                end
            end
        end
    end
end

function Harness:Start()
    for _, client in ipairs(self.clients) do
        self:Select(client)
        assert(client.engine:Start())
    end
end

function Harness:Begin(client)
    self:Select(client)
    return client.engine:Begin()
end

function Harness:Count(op)
    local count = 0
    for _, message in ipairs(self.traffic) do if message.op == op then count = count + 1 end end
    return count
end

function Harness:Provider(client, addon)
    client.engine = addon.GuildSync.New({
        prefix = "TestGuild3",
        identity = function(name) return name or client.name end,
        scope = function() return client.guilded ~= false and (client.scope or "Region PvP\tTest Guild") or nil end,
        enabled = function() return client.enabled end,
        ready = function() return client.ready ~= false end,
        key = function(record)
            if type(record) ~= "string" or #record > 130 then return nil end
            local kind, name = record:match("^([PG])\t(.*)$")
            if not name or #name == 0 or #name > 128 or name:find("[%c]") then return nil end
            return kind .. "\t" .. name:lower()
        end,
        snapshot = function()
            local records = {}
            for record in pairs(client.records) do records[#records + 1] = record end
            return records
        end,
        apply = function(record)
            assert(not client.combat and not client.lockdown and not client.chatRestricted, "applied while blocked")
            if client.reject then return false end
            local added = not client.records[record]
            client.records[record] = true
            client.applies = (client.applies or 0) + 1
            return true, added
        end,
        confirmed = function(peer, added) client.confirmations[#client.confirmations + 1] = { peer, added } end,
        notify = function(message) client.messages[#client.messages + 1] = message end,
    })
end

return Harness
