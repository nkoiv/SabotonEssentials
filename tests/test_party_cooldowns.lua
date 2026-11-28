local addon = {}
assert(loadfile("src/Support/PartyCooldowns.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/CooldownSync.lua"))("SabotonEssentials", addon)
local T, S = addon.PartyCooldowns, addon.CooldownSync
local expectedPresets = {
    innervate = { duration = 360, effectDuration = 20, minLevel = 40, class = "DRUID", ids = { 29166 } },
    rebirth = { duration = 1800, minLevel = 20, class = "DRUID", ids = { 20484, 20739, 20742, 20747, 20748 } },
    layonhands = { duration = 1200, minLevel = 10, class = "PALADIN", ids = { 633, 2800, 10310 } },
    shieldwall = { duration = 900, effectDuration = 12, minLevel = 28, class = "WARRIOR", ids = { 871 } },
}
for key, expected in pairs(expectedPresets) do
    local spell = assert(T.Preset(key))
    assert(spell.duration == expected.duration and spell.effectDuration == expected.effectDuration,
        key .. " must match Wowhead Forever's base timing")
    assert(spell.minLevel == expected.minLevel and spell.class == expected.class)
    assert(#spell.ids == #expected.ids)
    for index, id in ipairs(expected.ids) do assert(spell.ids[index] == id) end
end
local classEntries, seenKeys, seenIDs, defaults = {}, {}, {}, {}
for _, spell in ipairs(T.presets) do
    assert(not seenKeys[spell.key] and not seenIDs[spell.ids[1]], "catalogue keys and primary IDs must be unique")
    seenKeys[spell.key], seenIDs[spell.ids[1]] = true, true
    assert(spell.category == "Utility" or spell.category == "Defensive" or spell.category == "Offensive")
    if spell.default then defaults[spell.key] = true end
    local entriesForClass = classEntries[spell.class] or {}
    classEntries[spell.class] = entriesForClass
    local entry = { id = spell.ids[1], kind = "C", remaining = 7200, duration = 7200 }
    if spell.effectDuration then
        entry.effectKind, entry.effectRemaining, entry.effectDuration = "C", 120, 120
    end
    entriesForClass[#entriesForClass + 1] = entry
end
assert(defaults.innervate and defaults.rebirth and defaults.soulstone)
local defaultCount = 0
for _ in pairs(defaults) do defaultCount = defaultCount + 1 end
assert(defaultCount == 3, "only combat resurrection and Innervate may be selected by default")
for class, entriesForClass in pairs(classEntries) do
    local snapshot = assert(S.Encode(entriesForClass), class .. " worst-case snapshot must fit the transport")
    assert(#snapshot <= 255)
    local decodedKind, decodedEntries = S.Decode(snapshot)
    assert(decodedKind == "state" and #decodedEntries == #entriesForClass)
end
local tracker = T.New()
tracker:SetRoster({ druid = { class = "DRUID", level = 60 }, paladin = { class = "PALADIN", level = 60 } })
assert(tracker:Cast("paladin", "layonhands", T.Preset("layonhands").duration, 0))
local layState, layLeft = tracker:State("paladin", "layonhands", 60)
assert(layState == "estimated" and layLeft == 1140, "Lay on Hands cast estimate must count down from 20 minutes")
assert(tracker:State("druid", "innervate", 0) == "unknown")
assert(tracker:Write("druid", "innervate", "R", 0, 0, "group report", 0))
assert(tracker:State("druid", "innervate", 179.99) == "ready")
assert(tracker:State("druid", "innervate", 180) == "unknown")
tracker:Write("druid", "innervate", "U", 0, 0, "group report", 10)
assert(tracker:State("druid", "innervate", 10) == "unknown")
tracker:Write("druid", "innervate", "R", 0, 0, "group report", 20)
tracker:InvalidateReady()
assert(tracker:State("druid", "innervate", 20) == "unknown")
assert(tracker:Write("druid", "innervate", "C", 700, 900, "group report", 100))
local state, left = tracker:State("druid", "innervate", 200)
assert(state == "cooldown" and left == 600, "reports must not be clamped to the 360s preset")
assert(tracker:State("druid", "innervate", 280) == "estimated", "stale reports must lose authoritative status")
assert(tracker:State("druid", "innervate", 800) == "unknown", "expiry is not proof of readiness")
assert(tracker:Cast("druid", "innervate", 360, 900))
assert(not tracker:Cast("druid", "innervate", 360, 900.74))
assert(tracker:State("druid", "innervate", 901) == "estimated")
assert(tracker:State("druid", "innervate", 1260) == "unknown")
assert(not tracker:Write("paladin", "innervate", "R", 0, 0, "bad", 0))
assert(not tracker:Write("druid", "innervate", "C", 8000, 8000, "bad", 0))
assert(not tracker:Write("druid", "innervate", "C", 10, 5, "bad", 0))
assert(not tracker:Write("druid", "innervate", "R", 1, 0, "bad", 0))
assert(not T.Number(0 / 0, 0, 7200) and not T.Number(math.huge, 0, math.huge))
tracker:Write("druid", "rebirth", "N", 0, 0, "group report", 0)
assert(not tracker:Eligible("druid", T.presets[2], 10))
assert(tracker:Eligible("druid", T.presets[2], 180), "expired knowledge must not permanently hide a player")
tracker:Write("druid", "innervate", "C", 300, 360, "group report", 1000)
local saved = tracker:Save(1000, 5000)
local restored = T.New()
restored:SetRoster(tracker.roster)
assert(restored:Restore(saved, 10, 5100))
state, left = restored:State("druid", "innervate", 10)
assert(state == "estimated" and left == 200, "restored timers must lose authoritative status")
assert(not restored:Restore({ saved[1], { guid = "druid", key = "bad" } }, 10, 5100))
tracker:SetRoster({})
assert(next(tracker.records) == nil and next(tracker.recent) == nil)

local entries = {
    { id = 29166, kind = "C", remaining = 700, duration = 900 },
    { id = 20484, kind = "U", remaining = 0, duration = 0 },
}
local packet = assert(S.Encode(entries))
local kind, decoded = S.Decode(packet)
assert(kind == "state" and decoded[1].remaining == 700)
assert(#packet <= 255 and S.Decode("R|1") == "request")
for _, bad in ipairs({ "S|2|", "S|1|29166:R:1:0", "S|1|29166:C:0:360", "S|1|29166:C:361:360",
    "S|1|29166:X:0:0", "S|1|999999:R:0:0", "S|1|29166:R:0:0,", "S|1|29166:R:0:0,29166:R:0:0",
    "S|1|029166:R:0:0", "S|1|29166:C:7201:7201", string.rep("x", 256) }) do
    assert(not S.Decode(bad), bad)
end
local hidden = {}
function issecretvalue(value) return value == hidden end
assert(not S.Decode(hidden))

local now, allowed, gate, result = 0, true, nil, 0
local sent, applied, notices = {}, {}, {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) assert(prefix == S.PREFIX) return true end,
    SendAddonMessage = function(prefix, message, channel)
        sent[#sent + 1] = { prefix, message, channel, now }
        return result
    end,
}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, AddOnMessageLockdown = 11 } }
local reporting = T.New()
reporting:SetRoster({ me = { class = "DRUID" }, peer = { class = "DRUID" } })
reporting:Write("me", "innervate", "C", 360, 360, "own client", 0)
local sync = S.New({
    enabled = function() return allowed end,
    channel = function() return "PARTY" end,
    member = function(guid) return reporting.roster[guid] end,
    resolve = function(name) if name == "Leaf" then return "peer" elseif name == "Me" then return "me" end end,
    selfGUID = function() return "me" end,
    snapshot = function(t) return reporting:Snapshot("me", t) end,
    apply = function(guid, values) applied[#applied + 1] = { guid, values } end,
    allowed = function(_, id) return T.Preset(id).class == "DRUID" end,
    gate = function() return gate end,
    notify = function(message) notices[#notices + 1] = message end,
    trace = function() end,
})
assert(sync:Register())
sync:Tick(now)
assert(#sent == 1 and sent[1][2] == "R|1")
now = 1 sync:Tick(now)
assert(#sent == 1, "send pacing must cover request and state packets")
now = 1.25 sync:Tick(now)
assert(#sent == 2)
kind, decoded = S.Decode(sent[2][2])
assert(decoded[1].remaining == 359)
gate = "chat lockdown"
now = 70 sync:Tick(now)
assert(#sent == 2 and sync.status == "deferred: chat lockdown")
gate, result = nil, 11
sync:Tick(now)
assert(#sent == 3 and sync.nextSend == 75)
now = 74.99 sync:Tick(now)
assert(#sent == 3)
result, now = 0, 75
sync:Tick(now)
kind, decoded = S.Decode(sent[4][2])
assert(decoded[1].remaining == 285, "retry must regenerate remaining time, not replay an old packet")
assert(sync.status:find("delivery not confirmed", 1, true))
sync:Receive(S.PREFIX, packet, "PARTY", "outsider", 80)
sync:Receive(S.PREFIX, packet, "GUILD", "Leaf", 80)
sync:Receive(S.PREFIX, packet, "PARTY", "Me", 80)
sync:Receive(S.PREFIX, packet, "PARTY", hidden, 80)
assert(#applied == 0)
sync:Receive(S.PREFIX, packet, "PARTY", "Leaf", 80)
assert(#applied == 1 and sync.peers.peer.lastState == 80)
sync:Receive(S.PREFIX, packet, "PARTY", "Leaf", 80.5)
assert(#applied == 1 and sync.rejected == 1)
sync:Receive(S.PREFIX, "S|1|633:R:0:0", "PARTY", "Leaf", 82)
assert(#applied == 1 and sync.rejected == 2)
sync:Receive(S.PREFIX, "R|1", "PARTY", "Leaf", 84)
assert(sync.replyAt >= 85 and sync.replyAt <= 87)
reporting:SetRoster({ me = { class = "DRUID" } })
now = 90 sync:Tick(now)
assert(not sync.peers.peer)
allowed = false
now = 91 sync:Tick(now)
assert(sync.status == "disabled" and sync.channel == nil)
assert(#notices > 0)

local clients, queue, sender = {}, {}, nil
local roster = { a = { class = "DRUID", level = 60 }, b = { class = "PALADIN", level = 60 } }
C_ChatInfo.SendAddonMessage = function(prefix, message, channel)
    queue[#queue + 1] = { prefix, message, channel, sender }
    return 0
end
for _, guid in ipairs({ "a", "b" }) do
    local client = { tracker = T.New(), blocked = false }
    client.tracker:SetRoster(roster)
    client.tracker:Write(guid, guid == "a" and "innervate" or "layonhands", "R", 0, 0, "own client", 0)
    client.sync = S.New({
        enabled = function() return true end, channel = function() return "PARTY" end,
        selfGUID = function() return guid end,
        member = function(peer) return roster[peer] end,
        resolve = function(peer) return roster[peer] and peer end,
        allowed = function(peer, id) return roster[peer].class == T.Preset(id).class end,
        snapshot = function(t) return client.tracker:Snapshot(guid, t) end,
        apply = function(peer, values, t)
            for _, entry in ipairs(values) do
                client.tracker:Write(peer, T.Preset(entry.id).key, entry.kind, entry.remaining, entry.duration, "group report", t)
            end
        end,
        gate = function() if client.blocked then return "chat lockdown" end end,
        notify = function() end, trace = function() end,
    })
    assert(client.sync:Register())
    clients[guid] = client
end
local function exchange(t)
    for _, guid in ipairs({ "a", "b" }) do sender = guid clients[guid].sync:Tick(t) end
    local pending = queue
    queue = {}
    for _, message in ipairs(pending) do
        for _, client in pairs(clients) do client.sync:Receive(message[1], message[2], message[3], message[4], t) end
    end
end
exchange(0)
exchange(2)
assert(clients.a.tracker:State("b", "layonhands", 2) == "ready")
assert(clients.b.tracker:State("a", "innervate", 2) == "ready")
clients.b.blocked = true
clients.b.tracker:Write("b", "layonhands", "C", 900, 1000, "own client", 10)
clients.a.tracker:InvalidateReady("a")
exchange(10)
assert(clients.a.tracker:State("b", "layonhands", 10) == "unknown", "a hidden cast must not leave the receiver claiming ready")
clients.b.blocked = false
exchange(30)
state, left = clients.a.tracker:State("b", "layonhands", 30)
assert(state == "cooldown" and left == 880, "two-client recovery must use current remaining time")
assert(clients.a.tracker:State("b", "layonhands", 210) == "estimated")
assert(clients.a.tracker:State("b", "layonhands", 910) == "unknown")
print("Party cooldown state and transport tests passed")
