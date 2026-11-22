local module, frame
local messages = {}
local secret = {}
local units = {}
local unavailableEvent

function issecretvalue(value) return value == secret end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitIsDeadOrGhost(unit) return units[unit] and units[unit].dead end
function CreateFrame()
    frame = { events = {}, scripts = {} }
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:RegisterEvent(event)
        if event == unavailableEvent then error("event unavailable") end
        self.events[event] = true
    end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end
local addon = {
    Print = function(message) messages[#messages + 1] = message end,
    RegisterModule = function(name, value) assert(name == "mobprobe") module = value end,
}
local function has(text)
    for _, message in ipairs(messages) do
        if message:find(text, 1, true) then return true end
    end
    return false
end
local function clear() messages = {} end
local function event(name, value) frame.scripts.OnEvent(frame, name, value) end
local function tick() frame.scripts.OnUpdate(frame, 0.5) end

assert(loadfile("src/Modules/MobDeathProbe.lua"))("SabotonEssentials", addon)
module:OnEnable()
assert(next(frame.events) == nil)
module:HandleCommand("watch")
assert(has("start the probe first"))
clear()
module:HandleCommand("start")
assert(frame.events.UNIT_DIED and frame.events.UNIT_HEALTH and frame.events.UNIT_FLAGS)
units.target = { guid = "Creature-1", name = "High Chief Winterfall", dead = false }
module:HandleCommand("watch")
assert(has("GUID readable; death state alive"))
clear()
event("UNIT_DIED", secret)
event("UNIT_DIED", nil)
event("UNIT_DIED", 123)
event("UNIT_DIED", "other")
event("UNIT_DIED", "Creature-1")
assert(has("event GUID is secret"))
assert(has("event GUID is missing"))
assert(has("unexpected type"))
assert(has("not the watched GUID"))
assert(has("live token: target"))
clear()
units.target.dead = true
event("UNIT_HEALTH", "target")
tick()
assert(has("UNIT_HEALTH target: alive-to-dead transition"))
assert(has("poll target: alive-to-dead transition"))
clear()
event("UNIT_DIED", "Creature-1")
units.target = nil
event("UNIT_DIED", "Creature-1")
assert(has("no live token; cached identity matched"))
module:HandleCommand("status")
assert(has("total=7 watched=3 other=1 secret=1 missing=1 invalid=1"))
assert(has("UNIT_HEALTH=1, UNIT_FLAGS=0, watched event checks=1, dead observations=1; poll checks=1, dead observations=1"))
module:HandleCommand("stop")
assert(next(frame.events) == nil)

clear()
module:HandleCommand("start")
units.target = { guid = "Creature-3", name = "Mob", dead = false }
module:HandleCommand("watch")
units.target = nil
tick()
assert(has("No live token for watched GUID"))
clear()
units.target = { guid = "Creature-3", name = "Mob", dead = true }
tick()
event("UNIT_FLAGS", "target")
assert(has("dead observed; prior state unknown"))
assert(not has("alive-to-dead transition"))
module:HandleCommand("stop")

clear()
unavailableEvent = "UNIT_DIED"
module:HandleCommand("start")
assert(not frame.events.UNIT_DIED and frame.events.UNIT_FLAGS)
assert(has("could not register UNIT_DIED"))
units.target = { guid = "Creature-2", name = "Mob", dead = false }
module:HandleCommand("watch")
clear()
units.target.dead = secret
event("UNIT_FLAGS", "target")
assert(has("death state secret"))
clear()
units.target.dead = true
event("UNIT_FLAGS", "target")
assert(has("dead observed; prior state unknown"))
assert(not has("alive-to-dead transition"))
clear()
units.target.guid = secret
module:HandleCommand("watch")
assert(has("GUID secret"))
assert(has("GUID matching and state tracking cannot work"))
clear()
event("UNIT_DIED", secret)
module:HandleCommand("status")
assert(has("secret=1"))
module:HandleCommand("stop")
print("Mob death probe tests passed")
