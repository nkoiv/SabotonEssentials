local module, eventFrame
local sounds = 0
local secret = {}
local secretChecks = 0
local guids = { player = "player", party1 = "party", target = secret, focus = "enemy" }
function issecretvalue(value)
    if value == secret then secretChecks = secretChecks + 1 return true end
    return false
end
function UnitGUID(unit) return guids[unit] end
function GetNumGroupMembers() return 2 end
function IsInRaid() return false end
function UnitClass(...) return "Mage", "MAGE" end
function UnitIsFriend(...) return false end
function PlaySoundFile(...) sounds = sounds + 1 return true end
function CreateFrame()
    eventFrame = {}
    function eventFrame:RegisterEvent() end
    function eventFrame:SetScript(_, callback) self.callback = callback end
    return eventFrame
end
local addon = { Print = function() end, RegisterModule = function(_, value) module = value end }
assert(loadfile("src/Modules/SqueakyToy.lua"))("SabotonEssentials", addon)
module:OnEnable()
eventFrame.callback(eventFrame, "UNIT_DIED", "party")
assert(sounds == 1)
module:HandleCommand("hostile")
eventFrame.callback(eventFrame, "UNIT_DIED", "enemy")
assert(sounds == 2 and secretChecks > 0)
eventFrame.callback(eventFrame, "UNIT_DIED", secret)
assert(sounds == 2)
print("Squeaky Toy tests passed")