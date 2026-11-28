local addon = {}
assert(loadfile("src/Support/PartyCooldowns.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/CooldownSync.lua"))("SabotonEssentials", addon)
local T, S = addon.PartyCooldowns, addon.CooldownSync
local tracker = T.New()
tracker:SetRoster({ tank = { class = "WARRIOR", level = 60 }, druid = { class = "DRUID", level = 60 } })
local wall = T.Preset("shieldwall")
assert(wall.ids[1] == 871 and wall.effectDuration == 12 and wall.duration == 900)
assert(tracker:Cast("tank", "shieldwall", wall.duration, 100))
local cooldownState, cooldownLeft = tracker:State("tank", "shieldwall", 102)
assert(cooldownState == "estimated" and cooldownLeft == 898, "unreadable talent state must use the 15-minute base estimate")
local state, left = tracker:EffectState("tank", "shieldwall", 102)
assert(state == "estimated" and left == 10)
assert(not tracker:Cast("tank", "shieldwall", wall.duration, 100.5))
assert(tracker:Write("tank", "shieldwall", "C", 238, 240, "own cooldown", 102))
assert(tracker:WriteEffect("tank", "shieldwall", "C", 13, 15, "own aura", 102),
    "readable aura timing must preserve talent-adjusted duration")
state, left = tracker:EffectState("tank", "shieldwall", 104)
assert(state == "active" and left == 11)
local entries, signature = tracker:Snapshot("tank", 104)
assert(entries[1].remaining == 236 and entries[1].duration == 240 and
    entries[1].effectRemaining == 11 and entries[1].effectDuration == 15,
    "readable 4-minute talented cooldown must replace the untalented estimate")
local packet = assert(S.Encode({ entries[1] }))
assert(packet == "S|2|871:C:236:240:C:11:15")
local kind, decoded = S.Decode(packet)
assert(kind == "state" and decoded[1].effectKind == "C" and decoded[1].effectRemaining == 11)
local _, nextSignature = tracker:Snapshot("tank", 105)
assert(nextSignature == signature, "normal countdown ticks must not spam snapshots")
assert(tracker:WriteEffect("tank", "shieldwall", "U", 0, 0, "restricted", 105))
state, left = tracker:EffectState("tank", "shieldwall", 105)
assert(state == "estimated" and left == 10, "restricted data must downgrade rather than erase active timing")
assert(tracker:WriteEffect("tank", "shieldwall", "R", 0, 0, "removed aura", 106))
assert(tracker:EffectState("tank", "shieldwall", 106) == "inactive")
assert(tracker:State("tank", "shieldwall", 106) == "cooldown", "effect removal must not reset cooldown")
assert(tracker:Cast("druid", "innervate", 360, 200))
state, left = tracker:EffectState("druid", "innervate", 205)
assert(state == "estimated" and left == 15, "targeted buffs use cast estimates, not the caster's aura absence")
assert(tracker:EffectState("druid", "innervate", 220) == "unknown")
assert(tracker:State("druid", "innervate", 220) == "estimated", "effect expiry must leave cooldown running")
local expiryEntries, expirySignature = tracker:Snapshot("druid", 220)
assert(expiryEntries[1].effectKind == "U" and expiryEntries[1].effectRemaining == 0)
assert(expirySignature ~= select(2, tracker:Snapshot("druid", 205)), "effect expiry must trigger a new snapshot")
assert(not tracker:WriteEffect("druid", "shieldwall", "C", 5, 10, "bad", 0))
assert(not tracker:WriteEffect("tank", "shieldwall", "C", 16, 15, "bad", 0))
assert(not tracker:WriteEffect("tank", "shieldwall", "C", 121, 121, "bad", 0))
assert(not tracker:WriteEffect("tank", "shieldwall", "N", 0, 0, "bad", 0))
for _, bad in ipairs({
    "S|2|871:C:1800:1800:C:11:10", "S|2|871:C:1800:1800:C:0:10",
    "S|2|871:C:1800:1800:R:1:0", "S|2|871:C:1800:1800:C:121:121",
    "S|2|633:C:3600:3600:C:10:10", "S|1|871:C:1800:1800:C:10:10",
    "S|2|871:C:1800:1800", "S|2|871:C:1800:1800:C:010:10",
    "S|2|871:C:1800:1800:C:10:10,871:C:1800:1800:C:10:10",
}) do assert(not S.Decode(bad), bad) end
assert(S.Decode("S|1|871:C:1800:1800") == "state", "legacy cooldown-only reports must still be accepted")
local receiver = T.New()
receiver:SetRoster(tracker.roster)
local transport = S.New({
    enabled = function() return true end, channel = function() return "PARTY" end,
    selfGUID = function() return "druid" end,
    resolve = function(sender) return sender == "Tank" and "tank" end,
    allowed = function(guid, id) return receiver.roster[guid].class == T.Preset(id).class end,
    apply = function(guid, reports, now)
        for _, report in ipairs(reports) do
            local key = T.Preset(report.id).key
            assert(receiver:Write(guid, key, report.kind, report.remaining, report.duration, "peer", now))
            assert(receiver:WriteEffect(guid, key, report.effectKind or "U", report.effectRemaining or 0,
                report.effectDuration or 0, "peer", now))
        end
    end,
    trace = function() end,
})
transport:Receive(S.PREFIX, packet, "PARTY", "Tank", 104)
state, left = receiver:EffectState("tank", "shieldwall", 106)
assert(state == "active" and left == 9)
local before = receiver.records.tank.shieldwall.endsAt
transport:Receive(S.PREFIX, "S|2|871:C:1700:1800:C:16:15", "PARTY", "Tank", 106)
assert(transport.rejected == 1 and receiver.records.tank.shieldwall.endsAt == before,
    "malformed effect fields must reject the whole snapshot atomically")
transport:Receive(S.PREFIX, "S|1|871:C:233:240", "PARTY", "Tank", 107)
state, left = receiver:EffectState("tank", "shieldwall", 107)
assert(state == "estimated" and left == 8, "legacy reports cannot erase known active estimates")
transport:Receive(S.PREFIX, "S|2|871:C:232:240:R:0:0", "PARTY", "Tank", 108)
assert(receiver:EffectState("tank", "shieldwall", 108) == "inactive")
assert(receiver:State("tank", "shieldwall", 108) == "cooldown")
local restored = T.New()
restored:SetRoster(tracker.roster)
assert(restored:Restore(tracker:Save(206, 5000), 0, 5000))
assert(next(restored.effects) == nil, "short-lived effects must not be revived on reload")
tracker:SetRoster({})
assert(next(tracker.effects) == nil, "departed members' effects must be removed")
print("Party active-effect state and protocol tests passed")
