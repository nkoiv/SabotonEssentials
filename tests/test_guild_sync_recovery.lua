local h = assert(loadfile("tests/guild_sync_harness.lua"))()
local addon = {}
assert(loadfile("src/Support/GuildSync.lua"))("SabotonEssentials", addon)

local function start(count)
    h:Reset()
    for index = 1, count do
        local client = h:Client(string.format("Member%02d-Surname", index))
        client.records["P\tShared-Target"] = true
        client.records["P\tTarget-" .. index] = true
        h:Provider(client, addon)
    end
    h:Start()
    return h.clients[1], h.clients[2]
end

local function drained(client)
    assert(not client.engine.round and not next(client.engine.sessions)
        and #client.engine.controls == 0 and client.engine.queuedBytes == 0,
        client.name .. " did not drain: " .. client.engine:GetStatus())
end

local a, b = start(20)
for _, client in ipairs(h.clients) do
    for _ = 1, 5 do assert(h:Begin(client)) end
end
h:Run(1800)
for _, client in ipairs(h.clients) do drained(client) end
assert(h:Count("H") <= 20, "repeated button presses must coalesce into one discovery per client")
for index = 1, 20 do
    assert(a.records["P\tTarget-" .. index], "initiator lost a distinct peer beyond its offer limit")
end

a, b = start(2)
h:Select(a)
local session = assert(a.engine:NewSession(b.name, "000000000001"))
session.started = true
session.received = 1
b.offline = true
for _ = 1, 5 do
    h:Run(30)
    h:Select(a)
    a.engine:Receive(a.engine:Packet("B", session.id, a.name, 1, a.engine.scope), "GUILD", b.name)
end
h:Run(29)
assert(a.engine.sessions[b.name], "idle timeout fired before 180 seconds")
h:Run(1)
drained(a)
assert(#a.confirmations == 0, "silent session must never be confirmed")

a, b = start(2)
h:Select(a)
session = assert(a.engine:NewSession(b.name, "000000000002"))
b.offline = true
h:Run(100)
a.combat = true
h:Run(300)
assert(a.engine.sessions[b.name], "local restriction must not consume the idle budget")
a.combat = false
h:Run(79)
assert(a.engine.sessions[b.name])
h:Run(1)
drained(a)

a, b = start(3)
local c = h.clients[3]
h:Begin(a)
for _ = 1, 120 do
    h:Run(1)
    if b.engine.sessions[a.name] and a.records["P\tTarget-2"] then break end
end
assert(b.engine.sessions[a.name], "expected an in-flight exchange")
assert(h:Begin(b) and not b.engine.round, "manual start must coalesce with an inbound exchange")
b.offline = true
h:Run(300)
drained(a)
assert(a.records["P\tTarget-3"] and #a.confirmations == 1,
    "disconnected peer must not prevent another peer from confirming")
assert(a.confirmations[1][1] == c.name)
b.offline = false
h:Run(1)
for _, client in ipairs(h.clients) do h:Event(client, "GUILD_ROSTER_UPDATE") end
assert(h:Begin(b))
h:Run(300)
drained(b)
for index = 1, 3 do assert(b.records["P\tTarget-" .. index], "reconnected peer failed to reconcile") end

a, b = start(3)
h:Begin(a)
for _ = 1, 120 do
    h:Run(1)
    if b.engine.sessions[a.name] and a.records["P\tTarget-2"] then break end
end
assert(a.engine.sessions[b.name], "expected an in-flight exchange for roster cleanup")
b.offline = true
h:Event(a, "GUILD_ROSTER_UPDATE")
assert(not a.engine.sessions[b.name], "explicit disconnect must release the session immediately")
h:Run(300)
drained(a)
assert(a.records["P\tTarget-3"] and #a.confirmations == 1)

a, b = start(2)
h:Begin(a)
h:Run(3)
a.offline = true
h:Run(200)
drained(b)
assert(b.engine.status == "idle: no peer started an exchange",
    "abandoned discovery responder must not stay labeled as responding forever: " .. b.engine:GetStatus())

a, b = start(20)
for _, client in ipairs(h.clients) do assert(h:Begin(client)) end
b.offline = true
for _, client in ipairs(h.clients) do
    if not client.offline then h:Event(client, "GUILD_ROSTER_UPDATE") end
end
h:Run(1800)
for _, client in ipairs(h.clients) do
    if not client.offline then drained(client) end
end
for index = 3, 20 do assert(a.records["P\tTarget-" .. index]) end
assert(not a.records["P\tTarget-2"], "disconnected peer must not have contributed unsent data")

a, b = start(20)
local frames = 0
h.drop = function(message, receiver)
    if message.lossTested == nil then
        frames = frames + 1
        message.lossTested = frames % 17 == 0
    end
    return receiver ~= message.sender and message.lossTested
end
for index, client in ipairs(h.clients) do
    h.timers[#h.timers + 1] = {
        client = client, at = (index % 5) * 0.5,
        callback = function() assert(h:Begin(client)) end,
    }
end
h:Run(2400)
local confirmations = 0
for _, client in ipairs(h.clients) do
    drained(client)
    confirmations = confirmations + #client.confirmations
end
assert(confirmations > 0 and frames < 5000, "lossy burst must make progress without unbounded traffic")

a, b = start(2)
h:Select(a)
session = assert(a.engine:NewSession(b.name, "000000000003"))
session.started = true
assert(a.engine:Enqueue(session, "D", "P\tQueued-Target"))
assert(a.engine:Control("O", "000000000004", "Other-Peer", "offer"))
a.engine.controls[1].readyAt = 0
h:Run(0.25)
assert(h.traffic[1].op == "O", "ready discovery must receive a turn despite queued data")
h:Run(1.25)
assert(h.traffic[2].op == "D", "discovery must yield the next send opportunity to data")

a, b = start(2)
h:Select(a)
assert(a.engine:Control("O", "000000000005", "Delayed-Peer", "offer"))
assert(a.engine:Control("O", "000000000006", "Ready-Peer", "offer"))
a.engine.controls[1].readyAt, a.engine.controls[2].readyAt = 5, 0
h:Run(0.25)
assert(h.traffic[1].packet:find("Ready-Peer", 1, true),
    "delayed control at the head must not block a ready reply")

a, b = start(2)
h:Select(a)
for index = 1, 32 do
    local peer = "Peer-" .. index
    for revision = 1, 10 do
        assert(a.engine:Control("O", string.format("%012x", revision), peer, "offer"))
    end
end
assert(#a.engine.controls == 32, "outdated offers for the same peer must be replaced, not accumulated")
assert(a.engine:Control("H", "000000000001", nil, "discovery"), "reserve room for local discovery")
assert(not a.engine:Control("O", "000000000001", "Overflow-Peer", "offer"))
assert(#a.engine.controls == 33)

print("GuildSync burst/recovery tests passed")
