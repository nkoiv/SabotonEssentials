local _, addon = ...

local GuildSync = {}
addon.GuildSync = GuildSync

local MAX_RECORDS = 1000
local MAX_FRAME = 255
local MAX_RECORD_BYTES = 8192
local MAX_PEERS = 32
local MAX_SESSIONS = 2
local MAX_QUEUE = 2048
local MAX_QUEUED_BYTES = 524288
local SEND_INTERVAL = 1.25
local RETRY_SECONDS = 12
local MAX_ATTEMPTS = 4
local SESSION_LIFETIME = 7200
local IDLE_SECONDS = 180
local OFFER_SECONDS = 12
local DONE_LIFETIME = SESSION_LIFETIME

local function safe(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
        and not value:find("[%c]")
end

local function fingerprint(value)
    local a, b = 5381.0, 7919.0
    for index = 1, #value do
        local byte = value:byte(index)
        a = (a * 31.0 + byte) % 2147483629
        b = (b * 131.0 + byte) % 2147483587
    end
    return string.format("%08x%08x", a, b)
end

local function validDigest(value)
    return type(value) == "string" and #value == 16 and not value:find("[^0-9a-f]")
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function size(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local function splitIDs(payload)
    if #payload == 0 or #payload % 16 ~= 0 then return nil end
    local ids = {}
    for index = 1, #payload, 16 do
        local id = payload:sub(index, index + 15)
        if not validDigest(id) then return nil end
        ids[#ids + 1] = id
    end
    return ids
end

function GuildSync.New(config)
    assert(safe(config.prefix, 16), "GuildSync requires a valid prefix")
    local self = {
        config = config, sessions = {}, offers = {}, controls = {}, completed = {},
        inbox = {}, serial = 0, queuedBytes = 0, nextSend = 0, status = "idle",
        active = false, rate = {}, restriction = false, confirmed = 0,
        sendCalls = 0, receivedFrames = 0,
    }
    return setmetatable(self, { __index = GuildSync })
end

function GuildSync:Notify(message, routine)
    if self.lastNotice == message and GetTime() - self.lastNoticeAt < 10 then return end
    self.lastNotice, self.lastNoticeAt = message, GetTime()
    self.config.notify(message, routine)
end

function GuildSync:Trace(format, ...)
    if not self.debug or self.debugLines >= 200 then return end
    self.debugLines = self.debugLines + 1
    local message = string.format(format, ...):gsub("|", "||"):gsub("[%c]", " ")
    self.config.notify("Sync debug: " .. message, false)
    if self.debugLines == 200 then
        self.config.notify("Sync debug: 200-line limit reached; toggle debug off/on to capture more.", false)
    end
end

function GuildSync:SetDebug(enabled)
    self.debug, self.debugLines, self.debugGate = enabled, 0, nil
    self.config.notify("Guild sync debug " .. (enabled and "enabled (200-line limit)." or "disabled."), false)
    if enabled then
        self:RefreshRoster()
        self:Trace("self=%s; roster=%d; self-in-roster=%s; scope=%s; active=%s; gate=%s",
            tostring(self.me), size(self.roster), tostring(self.roster[self.me] == true),
            tostring(self.scopeValue), tostring(self.active), self:Gate() or "clear")
        self:Trace("state=%s; send calls=%d; received frames=%d", self.status, self.sendCalls, self.receivedFrames)
    end
end

function GuildSync:Snapshot()
    local records, err = self.config.snapshot()
    if not records then return nil, err end
    local map, keys = {}, {}
    for _, record in ipairs(records) do
        local key = self.config.key(record)
        if not key then return nil, "Invalid local sync record." end
        local content = key
        if self.config.contentKey then content = self.config.contentKey(record) end
        if type(content) ~= "string" or #record > MAX_RECORD_BYTES then return nil, "Invalid or oversized local sync record." end
        local id = fingerprint(content)
        if keys[id] and keys[id] ~= content then return nil, "Sync fingerprint collision." end
        keys[id], map[id] = content, record
    end
    local ids = sortedKeys(map)
    if #ids > MAX_RECORDS then return nil, "Sync supports at most 1,000 records." end
    return { records = map, ids = ids, digest = fingerprint(table.concat(ids)) }
end

function GuildSync:Gate()
    if not self.config.enabled() then return "disabled" end
    if not self.config.ready() then return "Spy lists are not ready" end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return "addon messaging is unavailable" end
    if not IsInGuild or not IsInGuild() then return "not in a guild" end
    if self.config.scope() ~= self.scopeValue then return "guild/list scope changed" end
    if self.restriction or (InCombatLockdown and InCombatLockdown()) then return "combat/chat restriction" end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return "chat lockdown"
    end
    local chat = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
    if chat and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
        and C_RestrictedActions.IsAddOnRestrictionActive(chat) then
        return "chat restriction"
    end
end

function GuildSync:RefreshRoster()
    local members = GetNumGuildMembers and GetNumGuildMembers() or 0
    local roster, offline = {}, {}
    for index = 1, members do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        local identity = self.config.identity(name)
        if safe(identity, 96) then
            roster[identity] = true
            if not (issecretvalue and issecretvalue(online)) and online == false then offline[identity] = true end
        end
    end
    self.roster = roster
    for peer in pairs(self.rate) do if not roster[peer] then self.rate[peer] = nil end end
    for peer, session in pairs(self.sessions) do
        if offline[peer] or (members > 0 and not roster[peer]) then
            self:Fail(session, "Guild peer disconnected or left the guild.")
        end
    end
    for peer in pairs(self.offers) do
        if offline[peer] or (members > 0 and not roster[peer]) then self.offers[peer] = nil end
    end
    if self.round then
        for peer in pairs(self.round.offers or {}) do
            if offline[peer] or (members > 0 and not roster[peer]) then self.round.tried[peer] = true end
        end
    end
    for index = #self.controls, 1, -1 do
        local peer = self.controls[index].peer
        if peer and (offline[peer] or (members > 0 and not roster[peer])) then
            table.remove(self.controls, index)
        end
    end
end

function GuildSync:Packet(op, id, peer, sequence, payload)
    local packet = table.concat({ op, id, peer or "", tostring(sequence or 0), payload or "" }, "\t")
    if #packet > MAX_FRAME then return nil end
    return packet
end

function GuildSync:Control(op, id, peer, payload)
    local packet = self:Packet(op, id, peer, 0, payload)
    if not packet then return false end
    for _, item in ipairs(self.controls) do
        if item.packet == packet then return true end
        if op == "O" and item.op == op and item.peer == peer then
            item.packet, item.id = packet, id
            return true
        end
    end
    if #self.controls >= MAX_PEERS + 1 then
        self:Trace("control queue full: op=%s peer=%s", op, tostring(peer))
        return false
    end
    self.controls[#self.controls + 1] = {
        packet = packet, op = op, id = id, peer = peer, attempts = 0,
        readyAt = GetTime() + (op == "O" and math.random(1, 5) or math.random() * 2),
    }
    return true
end

function GuildSync:Enqueue(session, op, payload)
    payload = payload or ""
    if session.tail - session.head + 1 >= MAX_QUEUE
        or self.queuedBytes + #payload > MAX_QUEUED_BYTES
        or not self:Packet(op, session.id, session.peer, 99999, payload) then
        self:Fail(session, "Sync queue or frame limit exceeded.")
        return false
    end
    session.tail = session.tail + 1
    session.queue[session.tail] = { op = op, payload = payload, attempts = 0 }
    self.queuedBytes = self.queuedBytes + #payload
    return true
end

function GuildSync:QueueIDs(session, op, ids)
    local payload = ""
    for _, id in ipairs(ids) do
        if not self:Packet(op, session.id, session.peer, 99999, payload .. id) then
            if not self:Enqueue(session, op, payload) then return false end
            payload = ""
        end
        payload = payload .. id
    end
    return payload == "" or self:Enqueue(session, op, payload)
end

function GuildSync:QueueRecord(session, record)
    if #record > MAX_RECORD_BYTES then
        self:Fail(session, "Sync record exceeds 8,192 bytes.")
        return false
    end
    local header = self:Packet("D", session.id, session.peer, 99999, "")
    local capacity = MAX_FRAME - #header
    local offset = 1
    while #record - offset + 1 > capacity do
        if not self:Enqueue(session, "C", record:sub(offset, offset + capacity - 1)) then return false end
        offset = offset + capacity
    end
    return self:Enqueue(session, "D", record:sub(offset))
end

function GuildSync:PumpRecords(session)
    if not session.requestsDone or session.dataSent or session.head <= session.tail then return end
    local index = session.nextRecord or 1
    local id = session.pendingRecords and session.pendingRecords[index]
    if id then
        session.nextRecord = index + 1
        self:QueueRecord(session, session.snapshot.records[id])
    else
        session.dataSent = true
        self:Enqueue(session, "T")
    end
end

function GuildSync:Remove(session)
    for index = session.head, session.tail do
        self.queuedBytes = self.queuedBytes - #session.queue[index].payload
    end
    self.sessions[session.peer] = nil
    self.offers[session.peer] = nil
    for index = #self.controls, 1, -1 do
        if self.controls[index].peer == session.peer then table.remove(self.controls, index) end
    end
end

function GuildSync:Fail(session, reason)
    self:Remove(session)
    self.status = "failed: " .. reason
    self:Notify(reason .. " (" .. session.peer .. ")")
    if self.round then self.round.tried[session.peer] = true end
end

function GuildSync:Cancel(reason)
    self:Trace("cancel: %s", reason or "requested")
    self.sessions, self.offers, self.controls, self.inbox, self.completed = {}, {}, {}, {}, {}
    self.queuedBytes, self.round = 0, nil
    self.pausedAt, self.responseDeadline = nil, nil
    self.status = reason or "canceled"
end

function GuildSync:NewSession(peer, id)
    if self.sessions[peer] or size(self.sessions) >= MAX_SESSIONS then return nil end
    local snapshot, err = self:Snapshot()
    if not snapshot then return nil, err end
    local session = {
        peer = peer, id = id, snapshot = snapshot, queue = {}, head = 1, tail = 0,
        sent = 0, received = 0, created = GetTime(), lastProgress = GetTime(), manifest = {}, wanted = {},
        requested = {}, added = 0,
    }
    self.sessions[peer] = session
    self.responseDeadline = nil
    self.status = "exchanging with " .. peer
    self:Trace("session opened: peer=%s id=%s", peer, id)
    return session
end

function GuildSync:Begin()
    if not self.active then
        self:Notify("Guild sync is unavailable until Spy and settings are ready.")
        return false
    end
    if not self.config.enabled() then self:Notify("Guild sync is disabled.") return false end
    if not IsInGuild() then self:Notify("Join a guild before syncing.") return false end
    if not self.scope or not safe(self.me, 96) then
        self:Notify("Guild/list scope or character identity is unavailable.")
        return false
    end
    if self.round or next(self.sessions) then self:Notify("A guild sync is already queued or running.") return true end
    local snapshot, err = self:Snapshot()
    if not snapshot then self:Notify(err) return false end
    self:RefreshRoster()
    if not next(self.roster) then self:Notify("Guild roster is not available yet.") return false end
    self.serial = self.serial % 65535 + 1
    local id = string.format("%08x%04x", time() % 2147483647, self.serial)
    self.offers = {}
    self.confirmed = 0
    self.responseDeadline = nil
    self.round = { id = id, tried = {}, digests = {}, created = GetTime() }
    if not self:Control("H", id, nil, self.scope .. snapshot.digest) then
        self.round = nil
        self:Notify("Could not queue guild discovery.")
        return false
    end
    self.status = "queued"
    self:Trace("discovery queued: id=%s self=%s scope=%s roster=%d", id, self.me, self.scope, size(self.roster))
    self:Notify("Guild sync queued; waiting for available guild members.")
    return true
end

function GuildSync:Complete(session)
    if not session.peerFinished or not session.finishAcknowledged or session.head <= session.tail
        or (session.manifestSent and not session.dataSent) then return end
    self.completed[session.peer .. session.id] = {
        peer = session.peer, id = session.id, received = session.received, ack = session.ack,
        expires = GetTime() + DONE_LIFETIME,
    }
    if size(self.completed) > MAX_PEERS then
        local oldestKey, oldest
        for key, entry in pairs(self.completed) do
            if not oldest or entry.expires < oldest then oldestKey, oldest = key, entry.expires end
        end
        self.completed[oldestKey] = nil
    end
    self:Remove(session)
    self.config.confirmed(session.peer, session.added)
    if self.round and session.id == self.round.id then
        self.round.tried[session.peer] = true
        self.round.digests[session.remoteDigest] = true
        self.confirmed = self.confirmed + 1
    end
    self.status = "confirmed with " .. session.peer
end

function GuildSync:Handle(session, op, payload)
    if op == "B" then
        if session.started or payload ~= self.scope then return false end
        session.started = true
        return self:Enqueue(session, "S", session.snapshot.digest)
    elseif not session.started then
        return false
    elseif op == "S" then
        if session.remoteDigest or not validDigest(payload) then return false end
        session.remoteDigest = payload
        if payload == session.snapshot.digest then
            return self:Enqueue(session, "F", payload)
        end
        session.needsManifest = true
        return self:Enqueue(session, "N")
    elseif op == "N" then
        if session.manifestSent or not session.remoteDigest or payload ~= "" then return false end
        session.manifestSent = true
        return self:QueueIDs(session, "M", session.snapshot.ids)
            and self:Enqueue(session, "E", session.snapshot.digest)
    elseif op == "M" then
        if not session.needsManifest or session.manifestDone then return false end
        local ids = splitIDs(payload)
        if not ids or size(session.manifest) + #ids > MAX_RECORDS then return false end
        for _, id in ipairs(ids) do
            if session.manifest[id] then return false end
            session.manifest[id] = true
        end
        return true
    elseif op == "E" then
        if not session.needsManifest or session.manifestDone or payload ~= session.remoteDigest then return false end
        local ids = sortedKeys(session.manifest)
        if fingerprint(table.concat(ids)) ~= payload then return false end
        session.manifestDone = true
        local missing = {}
        for _, id in ipairs(ids) do
            if not session.snapshot.records[id] then
                session.wanted[id] = true
                missing[#missing + 1] = id
            end
        end
        return self:QueueIDs(session, "Q", missing) and self:Enqueue(session, "R")
    elseif op == "Q" then
        if not session.manifestSent or session.requestsDone then return false end
        local ids = splitIDs(payload)
        if not ids then return false end
        local seen = {}
        for _, id in ipairs(ids) do
            if not session.snapshot.records[id] or session.requested[id] or seen[id] then return false end
            seen[id] = true
        end
        for _, id in ipairs(ids) do
            session.requested[id] = true
            session.pendingRecords = session.pendingRecords or {}
            session.pendingRecords[#session.pendingRecords + 1] = id
        end
        return true
    elseif op == "R" then
        if not session.manifestSent or session.requestsDone or payload ~= "" then return false end
        session.requestsDone = true
        return true
    elseif op == "C" then
        if not session.manifestDone or not next(session.wanted) or #payload == 0 then return false end
        local partial = (session.partial or "") .. payload
        if #partial >= MAX_RECORD_BYTES then return false end
        session.partial = partial
        return true
    elseif op == "D" then
        if not session.manifestDone then return false end
        payload = (session.partial or "") .. payload
        if #payload > MAX_RECORD_BYTES then return false end
        local key = self.config.key(payload)
        local content = key
        if key and self.config.contentKey then content = self.config.contentKey(payload) end
        local id = type(content) == "string" and fingerprint(content)
        if not id or not session.wanted[id] then return false end
        local ok, added = self.config.apply(payload)
        if not ok then return false end
        session.partial = nil
        session.wanted[id] = nil
        if added then session.added = session.added + 1 end
        return true
    elseif op == "T" then
        if not session.manifestDone or next(session.wanted) or session.partial or session.dataDone or payload ~= "" then return false end
        session.dataDone = true
        return self:Enqueue(session, "F", session.remoteDigest)
    elseif op == "F" then
        if session.peerFinished or not session.remoteDigest or payload ~= session.snapshot.digest
            or (session.manifestSent and not session.requestsDone) then return false end
        session.peerFinished = true
        return true
    end
    return false
end

function GuildSync:Receive(packet, channel, sender)
    if not self.active or not self.config.enabled() or channel ~= "GUILD"
        or (issecretvalue and (issecretvalue(packet) or issecretvalue(sender)))
        or type(packet) ~= "string" or #packet > MAX_FRAME then return end
    self.receivedFrames = self.receivedFrames + 1
    local peer = self.config.identity(sender)
    self:Trace("RX %s sender=%s identity=%s self=%s", packet:sub(1, 1), tostring(sender), tostring(peer), tostring(self.me))
    if not safe(peer, 96) then self:Trace("RX ignored: invalid identity") return end
    if peer == self.me then self:Trace("RX ignored: own broadcast") return end
    if not self.roster[peer] then self:Trace("RX ignored: sender absent from roster") return end
    local rate = self.rate[peer]
    local now = GetTime()
    if not rate or now - rate.start >= 1 then rate = { start = now, count = 0 } self.rate[peer] = rate end
    rate.count = rate.count + 1
    if rate.count > 20 then return end
    local blocked = self:Gate()
    if blocked then
        self:Trace("RX deferred: %s", blocked)
        if #self.inbox < 64 then self.inbox[#self.inbox + 1] = { packet, channel, sender } end
        return
    end
    self:Process(packet, peer)
end

function GuildSync:Process(packet, peer)
    local op, id, target, seq, payload = packet:match("^(%u)\t(%x+)\t([^\t]*)\t(%d+)\t(.*)$")
    seq = tonumber(seq)
    if not op or #id ~= 12 or not seq or seq > 99999 then
        self:Trace("RX ignored: invalid envelope")
        return
    end
    if target ~= "" and target ~= self.me then
        self:Trace("RX ignored: target=%s differs from self=%s", target, self.me)
        return
    end
    self:Trace("RX parsed: op=%s id=%s target=%s seq=%d peer=%s", op, id, target, seq, peer)
    if op == "H" then
        if target ~= "" or seq ~= 0 or #payload ~= 32 or payload:sub(1, 16) ~= self.scope
            or not validDigest(payload:sub(17)) then
            self:Trace("H ignored: invalid discovery or scope mismatch (local=%s remote=%s)", tostring(self.scope), payload:sub(1, 16))
            return
        end
        if self.round then
            -- Simultaneous initiators agree on one direction before opening a session.
            if self.me < peer or next(self.sessions) then
                self:Trace("concurrent H: keeping own round; self=%s peer=%s", self.me, peer)
                return
            end
            self:Trace("concurrent H: yielding own round; self=%s peer=%s", self.me, peer)
            self.round = nil
            self.controls = {}
            self.status = "responding to concurrent sync"
            self.responseDeadline = GetTime() + IDLE_SECONDS
        end
        local cached = self.offers[peer]
        if cached and cached.id == id and cached.expires >= GetTime() then
            self:Control("O", id, peer, self.scope .. cached.digest)
            return
        end
        if size(self.offers) < MAX_PEERS or self.offers[peer] then
            local snapshot, err = self:Snapshot()
            if not snapshot then self:Notify(err) return end
            self.offers[peer] = { id = id, digest = snapshot.digest, expires = GetTime() + SESSION_LIFETIME }
            self:Control("O", id, peer, self.scope .. snapshot.digest)
            if not self.round and not next(self.sessions) then
                self.status = "offering sync to guild peers"
                self.responseDeadline = GetTime() + IDLE_SECONDS
            end
        end
        return
    elseif op == "O" then
        if target ~= self.me or seq ~= 0 or not self.round or self.round.id ~= id
            or #payload ~= 32 or payload:sub(1, 16) ~= self.scope or not validDigest(payload:sub(17)) then
            self:Trace("O ignored: unexpected round, scope, or offer")
            return
        end
        if size(self.round.offers or {}) < MAX_PEERS then
            self.round.offers = self.round.offers or {}
            self.round.offers[peer] = payload:sub(17)
            self:Trace("offer accepted: peer=%s id=%s", peer, id)
        end
        return
    end
    if target ~= self.me or seq < 1 then return end
    local session = self.sessions[peer]
    if not session and op == "B" and seq == 1 and payload == self.scope then
        local offer = self.offers[peer]
        if not offer or offer.id ~= id or offer.expires < GetTime() then return end
        local err
        session, err = self:NewSession(peer, id)
        if err then self:Notify(err) self.offers[peer] = nil end
    end
    if not session or session.id ~= id then
        local done = self.completed[peer .. id]
        if done and op ~= "A" and seq <= done.received then done.ack = seq end
        return
    end
    if op == "A" then
        local item = session.queue[session.head]
        if not item or not item.sequence or item.sequence ~= seq or payload ~= "" then return end
        if item.op == "F" then session.finishAcknowledged = true end
        session.lastProgress = GetTime()
        self.queuedBytes = self.queuedBytes - #item.payload
        session.queue[session.head] = nil
        session.head = session.head + 1
        self:Complete(session)
        return
    end
    if seq <= session.received then session.ack = seq return end
    if seq ~= session.received + 1 then return end
    if not self:Handle(session, op, payload) then
        if self.sessions[peer] then self:Fail(session, "Invalid or unapplicable sync page.") end
        return
    end
    session.received, session.ack = seq, seq
    session.lastProgress = GetTime()
    self:Complete(session)
end

function GuildSync:ChoosePeer(now)
    local round = self.round
    if not round or not round.advertised or now - round.advertised < OFFER_SECONDS then return end
    for _, session in pairs(self.sessions) do if session.id == round.id then return end end
    for _, peer in ipairs(sortedKeys(round.offers or {})) do
        local digest = round.offers[peer]
        if not round.tried[peer] and not round.digests[digest] then
            local session, err = self:NewSession(peer, round.id)
            if not session then
                if err then
                    round.tried[peer] = true
                    self:Notify(err)
                end
                return
            end
            session.started = true
            self:Enqueue(session, "B", self.scope)
            self:Enqueue(session, "S", session.snapshot.digest)
            self.status = "exchanging with " .. peer
            return
        end
    end
    self.round = nil
    if self.confirmed == 0 then
        self.status = "no confirmed peers"
        self:Notify("No guild peer confirmed a sync; peers may be offline, busy, restricted, or using an older protocol.")
    else
        self.status = "complete"
        self:Notify("Guild sync complete: " .. self.confirmed .. " peer exchange(s) confirmed.", true)
    end
end

function GuildSync:Send(packet)
    self.sendCalls = self.sendCalls + 1
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, self.config.prefix, packet, "GUILD")
    self:Trace("TX %s bytes=%d API-ok=%s result=%s", packet:sub(1, 1), #packet, tostring(ok), tostring(result))
    if not ok then return "failed", "Addon message API error: " .. tostring(result) end
    local results = Enum and Enum.SendAddonMessageResult or {}
    if result == (results.Success or 0) then return "sent" end
    if result == (results.AddonMessageThrottle or 3) or result == (results.ChannelThrottle or 8) then
        self.nextSend = GetTime() + 5
        return "retry"
    end
    if result == (results.AddOnMessageLockdown or 11) then
        self.nextSend = GetTime() + 5
        self.status = "deferred: server chat lockdown"
        return "retry"
    end
    return "failed", "Addon message submission failed (result " .. tostring(result) .. ")."
end

function GuildSync:Tick()
    if not self.active then return end
    local now = GetTime()
    local scope = self.config.scope()
    if scope ~= self.scopeValue then
        self:Cancel("guild/list scope changed")
        self.scopeValue, self.scope = scope, scope and fingerprint(scope)
        self:RefreshRoster()
        return
    end
    for _, session in pairs(self.sessions) do
        if now - session.created > SESSION_LIFETIME then self:Fail(session, "Sync session expired.") end
    end
    if self.round and now - self.round.created > SESSION_LIFETIME then
        self:Cancel("expired")
        self:Notify("Guild sync expired.")
    end
    for key, entry in pairs(self.completed) do
        if entry.expires < now then self.completed[key] = nil end
    end
    local blocked = self:Gate()
    if blocked ~= self.debugGate then
        self:Trace("gate=%s", blocked or "clear")
        self.debugGate = blocked
    end
    if blocked or not self.scope then
        self.pausedAt = self.pausedAt or now
        self.status = "deferred: " .. (blocked or "guild/list scope unavailable")
        return
    end
    if self.pausedAt then
        local delay = now - self.pausedAt
        for _, session in pairs(self.sessions) do
            session.lastProgress = session.lastProgress + delay
            local item = session.queue[session.head]
            if item and item.lastSent then item.lastSent = item.lastSent + delay end
        end
        if self.round and self.round.advertised then self.round.advertised = self.round.advertised + delay end
        if self.responseDeadline then self.responseDeadline = self.responseDeadline + delay end
        self.pausedAt = nil
        self.nextSend = math.max(self.nextSend, now + 0.5 + math.random() * 1.5)
        self.status = "resuming"
    end
    for _, session in pairs(self.sessions) do
        if now - session.lastProgress >= IDLE_SECONDS then
            self:Fail(session, "Guild peer made no progress for 3 minutes; sync with this peer stopped.")
        end
    end
    if self.responseDeadline and now >= self.responseDeadline then
        self.responseDeadline = nil
        if not self.round and not next(self.sessions) then
            self.status = "idle: no peer started an exchange"
            self:Notify("No guild peer started an exchange; use Sync Now to retry.", true)
        end
    end
    for peer, offer in pairs(self.offers) do
        if offer.expires < now then self.offers[peer] = nil end
    end
    local inbox = self.inbox
    self.inbox = {}
    for _, item in ipairs(inbox) do self:Receive(unpack(item)) end
    self:ChoosePeer(now)
    for _, session in pairs(self.sessions) do self:PumpRecords(session) end
    if now < self.nextSend then return end
    local packet, owner, item, ack
    for _, session in pairs(self.sessions) do
        if session.ack then
            owner, ack = session, session.ack
            packet = self:Packet("A", session.id, session.peer, ack)
            break
        end
    end
    if not packet then
        for _, entry in pairs(self.completed) do
            if entry.ack then
                owner, ack = entry, entry.ack
                packet = self:Packet("A", entry.id, entry.peer, ack)
                break
            end
        end
    end
    -- Alternate discovery and data when both are ready; acknowledgments stay first.
    if not packet and not self.lastWasControl then
        for _, control in ipairs(self.controls) do
            if control.readyAt <= now then
                item, packet = control, control.packet
                break
            end
        end
    end
    if not packet then
        for _, session in pairs(self.sessions) do
            local candidate = session.queue[session.head]
            if candidate and (not candidate.lastSent
                or now - candidate.lastSent >= RETRY_SECONDS * 2 ^ math.max(0, candidate.attempts - 1)) then
                if candidate.attempts >= MAX_ATTEMPTS then
                    self:Fail(session, "Peer did not acknowledge a sync page.")
                    return
                end
                if not candidate.sequence then
                    session.sent = session.sent + 1
                    candidate.sequence = session.sent
                end
                owner, item = session, candidate
                packet = self:Packet(item.op, session.id, session.peer, item.sequence, item.payload)
                break
            end
        end
    end
    if not packet then
        for _, control in ipairs(self.controls) do
            if control.readyAt <= now then
                item, packet = control, control.packet
                break
            end
        end
    end
    if not packet then return end
    self.nextSend = now + SEND_INTERVAL
    local result, err = self:Send(packet)
    if result == "retry" then
        item = item or owner
        item.failures = (item.failures or 0) + 1
        self.nextSend = now + math.min(60, 5 * 2 ^ (item.failures - 1))
        if item.failures >= 12 then
            if owner and not ack then self:Fail(owner, "Repeated server throttling/lockdown.")
            else self:Cancel("failed") self:Notify("Guild sync stopped after repeated server rejection.") end
        end
        return
    elseif result == "failed" then
        if owner and not ack then self:Fail(owner, err)
        else self:Cancel("failed") self:Notify(err) end
        return
    end
    self.lastWasControl = owner == nil
    if ack then owner.ack = nil
    elseif owner then
        item.attempts, item.lastSent = item.attempts + 1, now
    else
        for index, control in ipairs(self.controls) do
            if control == item then table.remove(self.controls, index) break end
        end
        if item.op == "H" and self.round and item.id == self.round.id then self.round.advertised = now end
    end
    if owner then owner.failures = nil end
end

function GuildSync:Start()
    if self.active then return true end
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_Timer or not C_Timer.NewTicker then
        self.status = "unavailable: messaging/timer API missing"
        self:Notify(self.status)
        return false
    end
    self.me = self.config.identity()
    if not safe(self.me, 96) then
        self.status = "unavailable: character identity is unreadable or too long"
        self:Notify(self.status)
        return false
    end
    if not C_ChatInfo.RegisterAddonMessagePrefix(self.config.prefix) then
        self.status = "unavailable: prefix registration failed"
        self:Notify(self.status)
        return false
    end
    self.active = true
    self.restriction = false
    self.scopeValue = self.config.scope()
    self.scope = self.scopeValue and fingerprint(self.scopeValue)
    self:RefreshRoster()
    self.frame = self.frame or CreateFrame("Frame")
    for _, event in ipairs({ "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
        "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        self.frame:RegisterEvent(event)
    end
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, packet, channel, sender = ...
            if prefix == self.config.prefix then self:Receive(packet, channel, sender) end
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            local restriction, state = ...
            local types = Enum and Enum.AddOnRestrictionType or {}
            if restriction == types.Chat then
                self.restriction = state ~= Enum.AddOnRestrictionState.Inactive
            end
        elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
            self:RefreshRoster()
        end
    end)
    self.ticker = C_Timer.NewTicker(0.25, function() self:Tick() end)
    return true
end

function GuildSync:Stop()
    self:Cancel("disabled")
    self.active = false
    if self.ticker then self.ticker:Cancel() self.ticker = nil end
    if self.frame then self.frame:UnregisterAllEvents() end
end

function GuildSync:GetStatus()
    return string.format("%s; %d session(s), %d queued bytes; %d send calls, %d received frames",
        self.status, size(self.sessions), self.queuedBytes, self.sendCalls, self.receivedFrames)
end

function GuildSync:GetProgress()
    local progress = {
        status = self.status, active = self.round ~= nil or next(self.sessions) ~= nil,
        sessions = size(self.sessions), peers = self.confirmed, received = 0, pending = 0,
    }
    for _, session in pairs(self.sessions) do
        progress.received = progress.received + session.added
        progress.pending = progress.pending + size(session.wanted)
    end
    local blocked = self.active and self:Gate()
    if blocked then progress.status = "deferred: " .. blocked end
    return progress
end
