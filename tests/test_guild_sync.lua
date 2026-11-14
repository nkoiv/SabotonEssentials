local h = assert(loadfile("tests/guild_sync_harness.lua"))()
local addon = {}
assert(loadfile("src/Support/GuildSync.lua"))("SabotonEssentials", addon)

local function pair(aRecords, bRecords)
    h:Reset()
    local a, b = h:Client("Alice-Surname"), h:Client("Bob-Surname")
    a.records, b.records = aRecords or {}, bRecords or {}
    h:Provider(a, addon)
    h:Provider(b, addon)
    h:Start()
    return a, b
end

local a, b = pair({ ["P\tLocal-Target"] = true }, { ["G\tRemote Guild"] = true })
assert(h:Begin(a))
h:Run(180)
assert(a.records["G\tRemote Guild"] and b.records["P\tLocal-Target"])
assert(#a.confirmations == 1 and #b.confirmations == 1, a.engine:GetStatus() .. " / " .. b.engine:GetStatus())
assert(h:Count("D") == 2)
assert(a.engine.queuedBytes == 0 and b.engine.queuedBytes == 0)

a, b = pair({ ["P\tSame-Target"] = true }, { ["P\tSame-Target"] = true })
h:Begin(a)
h:Run(80)
assert(#a.confirmations == 1 and #b.confirmations == 1)
assert(h:Count("D") == 0 and h:Count("M") == 0)

a, b = pair({ ["P\tSame-Target"] = true }, { ["P\tSame-Target"] = true, ["P\tNew-Target"] = true })
h:Begin(a)
h:Run(180)
assert(a.records["P\tNew-Target"] and h:Count("D") == 1)

a, b = pair({}, { ["P\tDeferred-Target"] = true })
a.combat = true
h:Begin(a)
assert(h:Begin(a), "repeated start should coalesce")
h:Run(60)
assert(#h.traffic == 0 and #a.confirmations == 0 and not a.apiCalls)
a.combat = false
h:Event(a, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
h:Run(30)
assert(#h.traffic == 0, "Activating must block even though predicate is false")
h:Event(a, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
h:Run(180)
assert(a.records["P\tDeferred-Target"] and #a.confirmations == 1)

a, b = pair({}, { ["P\tPause-Target"] = true })
h:Begin(a)
h:Run(25)
a.combat = true
local sends = #h.traffic
h:Run(20)
for index = sends + 1, #h.traffic do assert(h.traffic[index].sender ~= a) end
assert(not a.records["P\tPause-Target"])
a.combat = false
a.chatRestricted = true
h:Event(a, "PLAYER_REGEN_ENABLED")
h:Run(10)
assert(not a.records["P\tPause-Target"])
a.chatRestricted = false
h:Run(180)
assert(a.records["P\tPause-Target"] and #a.confirmations == 1)

a, b = pair({}, { ["P\tRetry-Target"] = true })
local dropped = {}
h.drop = function(message, receiver)
    if receiver == a and message.sender == b and (message.op == "D" or message.op == "A") and not dropped[message.op] then
        dropped[message.op] = true
        return true
    end
end
h:Begin(a)
h:Run(240)
assert(a.records["P\tRetry-Target"] and #a.confirmations == 1 and #b.confirmations == 1,
    a.engine:GetStatus() .. " / " .. b.engine:GetStatus() .. " / " .. table.concat(a.messages, "; "))
assert(a.applies == 1, "duplicate pages must not reapply")

a, b = pair({}, { ["P\tThrottle-Target"] = true })
local rejections = 0
h.result = function()
    if rejections < 3 then
        rejections = rejections + 1
        return rejections == 1 and 3 or rejections == 2 and 8 or 11
    end
end
h:Begin(a)
h:Run(240)
assert(a.records["P\tThrottle-Target"] and #a.confirmations == 1)

a, b = pair({}, { ["P\tNoReceipt-Target"] = true })
h.drop = function(message, receiver) return receiver ~= message.sender end
h:Begin(a)
h:Run(100)
assert(#a.confirmations == 0 and not a.records["P\tNoReceipt-Target"])
assert(a.engine.status == "no confirmed peers")

a, b = pair({}, { ["P\tOffline-Target"] = true })
h:Begin(a)
h:Run(15)
b.offline = true
h:Run(260)
assert(#a.confirmations == 0 and a.engine.round == nil)

a, b = pair({}, { ["P\tDisabled-Target"] = true })
h:Begin(a)
h:Run(20)
h:Select(a)
a.enabled = false
a.engine:Stop()
h:Run(100)
assert(#a.confirmations == 0 and not next(a.engine.sessions) and not a.engine.ticker)
assert(not a.records["P\tDisabled-Target"])

a, b = pair({}, {})
h:Event(a, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
h:Select(a)
a.engine:Stop()
assert(a.engine:Start())
h:Begin(a)
h:Run(100)
assert(#a.confirmations == 1, "restriction state must be refreshed after re-enabling")

a, b = pair({}, {})
h.result = function() return 10 end
h:Begin(a)
h:Run(20)
assert(#a.confirmations == 0 and a.engine.status == "failed")

a, b = pair({}, {})
h:Begin(a)
h:Run(15)
a.scope = "Region PvE\tOther Guild"
h:Run(2)
assert(not next(a.engine.sessions) and not a.engine.round)

a, b = pair({}, { ["P\tRefused-Target"] = true })
a.reject = true
h:Begin(a)
h:Run(180)
assert(#a.confirmations == 0 and #b.confirmations == 0)

a, b = pair({}, {})
h:Begin(a)
h:Run(15)
local before = h:Count("D")
h:Select(a)
a.engine:Receive(string.rep("x", 256), "GUILD", b.name)
a.engine:Receive("D\t000000000001\tAlice-Surname\t1\tP\tInjected", "WHISPER", b.name)
a.engine:Receive("D\t000000000001\tAlice-Surname\t1\tP\tInjected", "GUILD", "Outsider-Surname")
h:Run(80)
assert(not a.records["P\tInjected"] and h:Count("D") == before)

a, b = pair({ ["P\tAlice-Target"] = true }, { ["P\tBob-Target"] = true })
assert(h:Begin(a) and h:Begin(b))
h:Run(240)
assert(a.records["P\tBob-Target"] and b.records["P\tAlice-Target"])
assert(#a.confirmations == 1 and #b.confirmations == 1, "concurrent initiation failed")

a, b = pair({ ["P\tPrivateLocal-Target"] = true }, { ["P\tPrivateRemote-Target"] = true })
h:Select(a)
a.engine:SetDebug(true)
h:Select(b)
b.engine:SetDebug(true)
assert(h:Begin(a) and h:Begin(b))
a.engine.controls[1].readyAt, b.engine.controls[1].readyAt = 0, 0
h:Run(240)
assert(#a.confirmations == 1 and #b.confirmations == 1, "debug changed concurrent reconciliation")
local trace = table.concat(a.messages, "\n")
assert(trace:find("self=Alice-Surname", 1, true) and trace:find("TX H", 1, true)
    and trace:find("RX ignored: own broadcast", 1, true)
    and trace:find("concurrent H: keeping own round", 1, true))
assert(table.concat(b.messages, "\n"):find("concurrent H: yielding own round", 1, true))
assert(not trace:find("PrivateLocal", 1, true) and not trace:find("PrivateRemote", 1, true),
    "debug must not log list record payloads")
assert(a.engine.sendCalls > 0 and a.engine.receivedFrames > 0)
h:Select(a)
a.engine:Trace("%s", "|Hunsafe|htext|h")
assert(a.messages[#a.messages]:find("||Hunsafe||htext||h", 1, true))
for _ = 1, 250 do a.engine:Trace("bounded") end
assert(a.engine.debugLines == 200 and a.messages[#a.messages]:find("200-line limit reached", 1, true))
local messageCount = #a.messages
a.engine:Trace("must not print")
assert(#a.messages == messageCount)
a.engine:SetDebug(false)
messageCount = #a.messages
a.engine:Trace("disabled")
assert(#a.messages == messageCount)
a.engine:SetDebug(true)
assert(a.engine.debugLines == 2, "re-enabling must reset debug budget")

a, b = pair({}, { ["P\tFinal-Target"] = true })
local finishSequence, finalAckDropped
h.drop = function(message, receiver)
    if message.sender == a and message.op == "F" then
        finishSequence = message.packet:match("^F\t[^\t]+\t[^\t]+\t(%d+)")
    end
    if message.sender == b and receiver == a and message.op == "A" and finishSequence
        and message.packet:match("^A\t[^\t]+\t[^\t]+\t(%d+)") == finishSequence and not finalAckDropped then
        finalAckDropped = true
        return true
    end
end
h:Begin(a)
h:Run(240)
assert(finalAckDropped and #a.confirmations == 1 and #b.confirmations == 1, "lost final ACK was not recovered")

a, b = pair({}, { ["P\tTampered-Target"] = true })
h.drop = function(message, receiver)
    if message.op == "D" and receiver == a then
        message.packet = message.packet:gsub("Tampered%-Target", "Unrequested-Target")
    end
end
h:Begin(a)
h:Run(240)
assert(not a.records["P\tUnrequested-Target"] and #a.confirmations == 0)

a, b = pair({}, { ["P\tDifferentScope-Target"] = true })
b.scope = "Region PvE\tTest Guild"
h:Run(1)
h:Begin(a)
h:Run(50)
assert(#a.confirmations == 0 and not a.records["P\tDifferentScope-Target"])

a, b = pair({}, { ["P\tRealmFlag-Target"] = true })
a.outgoingRestricted, b.outgoingRestricted = true, true
h:Begin(a)
h:Run(150)
assert(#a.confirmations == 1 and #b.confirmations == 1 and a.records["P\tRealmFlag-Target"],
    "realm-wide restriction flag must not preempt a successful native guild exchange")

a, b = pair({}, {})
a.outgoingRestricted, b.outgoingRestricted = true, true
h.result = function() return 10 end
h:Begin(a)
h:Run(20)
assert(#a.confirmations == 0 and a.engine.status == "failed",
    "actual native send rejection must still fail visibly")

a, b = pair({}, {})
h:Select(a)
local session = assert(a.engine:NewSession(b.name, "000000000001"))
for _ = 1, 2048 do assert(a.engine:Enqueue(session, "D", "P\tBounded")) end
assert(not a.engine:Enqueue(session, "D", "P\tOverflow"))
assert(a.engine.queuedBytes == 0 and not next(a.engine.sessions))
session = assert(a.engine:NewSession(b.name, "000000000002"))
assert(not a.engine:Enqueue(session, "D", string.rep("x", 256)))
assert(a.engine.queuedBytes == 0)

a, b = pair({}, {})
session = assert(a.engine:NewSession(b.name, "000000000004"))
local second = assert(a.engine:NewSession("Carol-Surname", "000000000005"))
assert(not a.engine:NewSession("Dan-Surname", "000000000006"), "concurrent session limit exceeded")
for _ = 1, 2048 do assert(a.engine:Enqueue(session, "D", string.rep("x", 200))) end
for _ = 1, 573 do assert(a.engine:Enqueue(second, "D", string.rep("x", 200))) end
assert(a.engine.queuedBytes == 524200)
assert(not a.engine:Enqueue(second, "D", string.rep("x", 200)), "total queued-byte limit exceeded")
assert(a.engine.queuedBytes == 409600 and a.engine.sessions[b.name])
a.engine:Cancel()
assert(a.engine.queuedBytes == 0)
h:Select(a)
a.combat = true
for _ = 1, 5 do
    h.now = h.now + 1
    for _ = 1, 20 do a.engine:Receive("invalid", "GUILD", b.name) end
end
assert(#a.engine.inbox == 64 and not a.apiCalls, "blocked inbox must be bounded")

a, b = pair({}, {})
session = assert(a.engine:NewSession(b.name, "000000000003"))
session.started, session.manifestSent, session.remoteDigest = true, true, session.snapshot.digest
assert(not a.engine:Handle(session, "Q", "not-a-fingerprint"))
assert(not a.engine:Handle(session, "D", "P\tUnrequested"))
assert(not a.engine:Handle(session, "E", session.snapshot.digest))

a, b = pair({}, {})
h:Begin(a)
h:Run(10)
for index = 1, 1001 do a.records["P\tTooMany-" .. index] = true end
h:Run(30)
assert(not a.engine.round and #a.confirmations == 0)
local limitMessages = 0
for _, message in ipairs(a.messages) do if message:find("1,000", 1, true) then limitMessages = limitMessages + 1 end end
assert(limitMessages == 1, "a changed local snapshot must fail without a repeated notification loop")

h:Reset()
a = h:Client("Alice-Surname")
b = h:Client("Bob-Surname")
local c, d = h:Client("Carol-Surname"), h:Client("Dan-Surname")
b.records["P\tBob-Target"], c.records["P\tCarol-Target"], d.records["P\tBob-Target"] = true, true, true
for _, peer in ipairs(h.clients) do h:Provider(peer, addon) end
h:Start()
h:Begin(a)
h:Run(400)
assert(a.records["P\tBob-Target"] and a.records["P\tCarol-Target"])
assert(#a.confirmations == 2, "distinct offers must be reconciled, identical offers coalesced")

a, b = pair({}, {})
local longName = string.rep("a", 48) .. "-" .. string.rep("b", 47)
a.name = longName
a.engine:Stop()
h:Select(a)
assert(a.engine:Start())
h:Event(b, "GUILD_ROSTER_UPDATE")
b.records["P\t" .. string.rep("N", 128)] = true
b.records["G\t" .. string.rep(string.char(0xD0, 0x87), 64)] = true
h:Begin(a)
h:Run(240)
assert(#a.confirmations == 1, "maximum routing/record lengths did not fit")

a, b = pair({}, {})
for index = 1, 1000 do b.records["P\tTarget-" .. index] = true end
h:Begin(a)
h:Run(9000)
assert(#a.confirmations == 1 and #b.confirmations == 1, a.engine:GetStatus())
assert(a.records["P\tTarget-1000"] and h:Count("D") == 1000)
assert(a.engine.queuedBytes == 0 and b.engine.queuedBytes == 0)

a, b = pair({}, {})
for index = 1, 1001 do a.records["P\tTarget-" .. index] = true end
assert(not h:Begin(a), "record limit must be enforced")

local largeRecord = "P\t" .. string.rep("x", 8190)
a, b = pair({}, { [largeRecord] = true })
a.engine.config.key = function(record) return record end
b.engine.config.key = a.engine.config.key
local chunkLost
h.drop = function(message, receiver)
    if message.op == "C" and receiver == a and not chunkLost then chunkLost = true return true end
end
h:Begin(a)
h:Run(1000)
assert(chunkLost and a.records[largeRecord] and a.applies == 1
    and #a.confirmations == 1 and #b.confirmations == 1, "8,192-byte record must reassemble and confirm exactly once")

a, b = pair({}, { [largeRecord .. "x"] = true })
a.engine.config.key = function(record) return record end
b.engine.config.key = a.engine.config.key
h:Select(b)
local oversized, err = b.engine:Snapshot()
assert(not oversized and err:find("oversized", 1, true), "8,193-byte records must fail before transfer")

a, b = pair({}, { [largeRecord] = true })
a.engine.config.key = function(record) return record end
b.engine.config.key = a.engine.config.key
local tampered
h.drop = function(message, receiver)
    if message.op == "C" and receiver == a and not tampered then
        message.packet = message.packet:sub(1, -2) .. "y"
        tampered = true
    end
end
h:Begin(a)
h:Run(1000)
assert(tampered and not next(a.records) and #a.confirmations == 0,
    "tampered chunk assembly must fail its manifest fingerprint before applying")

a, b = pair({}, {})
h:Select(a)
session = assert(a.engine:NewSession(b.name, "000000000099"))
session.started, session.manifestDone = true, true
session.wanted.test = true
assert(not a.engine:Handle(session, "C", ""), "empty continuation must be rejected")
session.partial = string.rep("x", 8191)
assert(not a.engine:Handle(session, "C", "x"), "unfinished record assembly must remain below its byte limit")
assert(not a.engine:Handle(session, "D", "xx"), "final assembly must respect its byte limit")
assert(not a.engine:Handle(session, "T", ""), "terminator must reject an incomplete record")
a.engine:Cancel()

-- Requested records are streamed one at a time instead of expanding all chunks into the send queue.
a, b = pair({}, {})
h:Select(a)
session = assert(a.engine:NewSession(b.name, "000000000098"))
session.requestsDone, session.pendingRecords = true, {}
for index = 1, 500 do
    local id = tostring(index)
    session.snapshot.records[id] = largeRecord
    session.pendingRecords[index] = id
end
a.engine:PumpRecords(session)
assert(session.tail < 100 and a.engine.queuedBytes == #largeRecord,
    "large snapshots must not enqueue all reason chunks at once")
local queued = session.tail
a.engine:PumpRecords(session)
assert(session.tail == queued, "streaming must wait for outstanding queued chunks")
a.engine:Cancel()

print("GuildSync two-client tests passed")
