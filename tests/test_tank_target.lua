-- Tests for src/Modules/TankTarget.lua with mocked WoW APIs.
local module
local secretToken = {}

function issecretvalue(value)
    return value == secretToken or (type(value) == "table" and value.secret == true)
end

-- Frame/texture stubs -------------------------------------------------------
local function newTexture()
    local tex = { shown = true, alpha = 1 }
    function tex:SetAllPoints() end
    function tex:SetPoint() end
    function tex:SetSize() end
    function tex:SetTexture(path) self.path = path end
    function tex:SetTexCoord() end
    function tex:SetAtlas(atlas) self.atlas = atlas end
    function tex:SetVertexColor(r, g, b, a) self.r, self.g, self.b, self.vertexAlpha = r, g, b, a end
    function tex:SetBlendMode() end
    function tex:SetDesaturated() end
    function tex:SetAlpha(alpha) self.alpha = alpha end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    return tex
end

local unsupportedEvent
local function newFrame(parent)
    local frame = { parent = parent, shown = false, events = {}, scripts = {}, children = {} }
    function frame:RegisterEvent(event)
        if event == unsupportedEvent then error("Unsupported test event") end
        self.events[event] = true
    end
    function frame:SetScript(handler, callback) self.scripts[handler] = callback end
    function frame:SetSize() end
    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetPoint(point, relative) self.anchor = relative end
    function frame:ClearAllPoints() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetAlphaFromBoolean(value, yes, no)
        self.alphaFromBoolean = { value, yes, no }
        local nativeValue = value
        if issecretvalue(value) then nativeValue = value.value end
        self.alpha = nativeValue and yes or no
    end
    function frame:GetParent() return self.parent end
    function frame:CreateTexture() return newTexture() end
    function frame:CreateFontString()
        local text = newTexture()
        text.parent = self
        function text:GetParent() return self.parent end
        function text:SetText(value) self.text = value end
        function text:SetFormattedText(format, value)
            self.input = value
            self.text = string.format(format, issecretvalue(value) and value.value or value)
        end
        function text:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
        function text:SetAlphaFromBoolean(value, yes, no)
            self.alphaFromBoolean = { value, yes, no }
            local nativeValue = value
            if issecretvalue(value) then nativeValue = value.value end
            self.alpha = nativeValue and yes or no
        end
        return text
    end
    function frame:GetChildren()
        self.childReads = (self.childReads or 0) + 1
        return (unpack or table.unpack)(self.children)
    end
    return frame
end

local eventFrame
function CreateFrame(_, _, parent)
    local frame = newFrame(parent)
    eventFrame = eventFrame or frame
    return frame
end

-- World state ----------------------------------------------------------------
local healthBar = {
    IsVisible = function() return true end,
    GetObjectType = function() return "StatusBar" end,
    GetWidth = function() return 110 end,
}

local function newPlate(token)
    local plate = newFrame(nil)
    plate.namePlateUnitToken = token
    plate.UnitFrame = { healthBar = healthBar }
    return plate
end

local plate1 = newPlate("nameplate1")
local plate2 = newPlate("nameplate2")
local plates = { plate1, plate2 }
local platesByUnit = {}

C_NamePlate = {
    GetNamePlates = function() return plates end,
    GetNamePlateForUnit = function(unit) return platesByUnit[unit] end,
}

local tickerCallback
C_Timer = { NewTicker = function(_, callback) tickerCallback = callback return {} end }

local roles = { party1 = "TANK" }
local names = { player = "Me", party1 = "Tankgal" }
local surnames = {}
local guids = {}
local unitIsUnit = {}
local existing = { player = true, party1 = true }
local now = 0

function GetTime() return now end
function IsInGroup() return true end
function IsInRaid() return false end
local memberCount = 2
function GetNumGroupMembers() return memberCount end
function UnitGroupRolesAssigned(unit) return roles[unit] end
function UnitName(unit) return names[unit], surnames[unit] end
function UnitGUID(unit) return guids[unit] end
function GetRaidTargetIndex() error("Raid-marker APIs must not be used") end
function UnitExists(unit) return existing[unit] == true end
function UnitClass(unit)
    if unit == "party1" then return "Warrior", "WARRIOR" end
    return "Mage", "MAGE"
end
function UnitAffectingCombat() return false end
function UnitCanAttack() return true end
function UnitIsDeadOrGhost() return false end
function UnitIsUnit(a, b) return unitIsUnit[a .. "|" .. b] end

local messages = {}
local addon = { Print = function(message) messages[#messages + 1] = message end,
    RegisterModule = function(_, value) module = value end }
assert(loadfile("src/Modules/TankTarget.lua"))("SabotonEssentials", addon)
assert(module, "module registered")

for _, spec in ipairs(module:GetOptionsSchema().options) do
    if spec.key == "hostileOnly" then
        assert(spec.get() and spec.default == true, "hostility filter defaults on")
        spec.set(false)
    end
end

module:OnEnable()
assert(eventFrame.events.PLAYER_TARGET_CHANGED and eventFrame.events.NAME_PLATE_UNIT_ADDED)
assert(tickerCallback, "ticker registered")

-- 1) Role tank's target plate found by identity: mark shown (no glow).
platesByUnit["party1target"] = plate1
tickerCallback()
local mark = plate1.sabotonTankMark
assert(mark and mark.shown and mark.alpha == 1, "mark shown on tank's target plate")
assert(not mark.glow.shown, "no glow when the mob is not also the player's target")
assert(not (plate2.sabotonTankMark and plate2.sabotonTankMark.shown), "other plates unmarked")

-- 2) Player shares the tank's target: neutral breathing glow.
platesByUnit["target"] = plate1
tickerCallback()
assert(mark.shown and mark.glow.shown, "glow when the mob is also the player's target")
assert(mark.scripts.OnUpdate, "breathing pulse running")
mark.scripts.OnUpdate(mark, 0.1)
assert(mark.glow.alpha and mark.glow.alpha > 0, "glow pulses")

-- 3) Everything secret in combat: secret UnitIsUnit routed to SetAlphaFromBoolean.
platesByUnit["party1target"] = nil
platesByUnit["target"] = nil
guids["party1target"] = secretToken
unitIsUnit["nameplate1|party1target"] = secretToken
unitIsUnit["nameplate2|party1target"] = secretToken
tickerCallback()
assert(mark.shown, "mark shown via secret path")
assert(mark.shield.alphaFromBoolean and mark.shield.alphaFromBoolean[1] == secretToken
    and mark.shield.alphaFromBoolean[2] == 1 and mark.shield.alphaFromBoolean[3] == 0,
    "secret boolean passed to SetAlphaFromBoolean")

-- A client without a secret visibility sink must not mark every candidate.
local alphaFromBoolean = mark.shield.SetAlphaFromBoolean
mark.shield.SetAlphaFromBoolean = nil
tickerCallback()
assert(not mark.shown, "unsupported secret matches stay hidden")
mark.shield.SetAlphaFromBoolean = alphaFromBoolean

-- 4) GUID compare decides definitively when readable.
guids["party1target"] = "guid-2"
guids["nameplate1"] = "guid-1"
guids["nameplate2"] = "guid-2"
tickerCallback()
assert(not plate1.sabotonTankMark.shown, "non-matching GUID unmarked")
assert(plate2.sabotonTankMark and plate2.sabotonTankMark.shown, "matching GUID marked")

-- 5) Fallback: no plate matched, but the player's target is the tank's target.
guids["party1target"] = nil
guids["nameplate1"] = nil
guids["nameplate2"] = nil
unitIsUnit["nameplate1|party1target"] = false
unitIsUnit["nameplate2|party1target"] = false
unitIsUnit["target|party1target"] = true
platesByUnit["target"] = plate1
tickerCallback()
assert(plate1.sabotonTankMark.shown and plate1.sabotonTankMark.glow.shown, "fallback pulses the shared target")

-- A secret plate comparison is not a resolved match: readable shared-target
-- identity must still override its conditional shield visibility.
unitIsUnit["nameplate1|party1target"] = secretToken
unitIsUnit["nameplate2|party1target"] = secretToken
tickerCallback()
assert(mark.shown and mark.shield.shown and mark.shield.alpha == 1,
    "readable shared-target fallback overrides unresolved secret plate matching")
assert(mark.initialsText.text == "T.", "shared-target fallback retains the other tank's initials")

-- 6) Manual tank pick overrides role detection.
module:HandleCommand("tank Me")
unitIsUnit["target|playertarget"] = nil
unitIsUnit["nameplate2|playertarget"] = true
unitIsUnit["nameplate1|playertarget"] = false
unitIsUnit["nameplate1|party1target"] = nil
unitIsUnit["nameplate2|party1target"] = nil
unitIsUnit["target|party1target"] = nil
platesByUnit["target"] = plate2
tickerCallback()
assert(plate2.sabotonTankMark.shown and not plate1.sabotonTankMark.shown, "manual pick wins")
module:HandleCommand("tank clear")
platesByUnit["target"] = nil

-- 7) Disabling hides all marks and stops updates.
module:HandleCommand("enable")
assert(not plate1.sabotonTankMark.shown and not plate2.sabotonTankMark.shown, "disable hides marks")
platesByUnit["party1target"] = plate1
tickerCallback()
assert(not plate1.sabotonTankMark.shown, "no marking while disabled")
module:HandleCommand("enable")
tickerCallback()
assert(plate1.sabotonTankMark.shown, "re-enable resumes marking")

-- 8) Options schema round-trips and persistence state survives.
local schema = module:GetOptionsSchema()
assert(schema.name == "Tank Target" and #schema.options == 12)
for _, spec in ipairs(schema.options) do
    if spec.key == "markSize" then
        spec.set(28)
        assert(spec.get() == 28, "mark size option set")
    end
end
module:HandleCommand("debug")
local state = module:GetPersistentState()
assert(state.debug == true, "debug persisted")
module:LoadPersistentState({ debug = false })
assert(module:GetPersistentState().debug == false, "debug restored")

local function assertColor(texture, color)
    assert(texture.r == color[1] and texture.g == color[2] and texture.b == color[3],
        "unexpected texture color")
end
platesByUnit.playertarget = plate1

-- Self-tanks must not depend on the playertarget alias working in instances.
roles.player, roles.party1 = "TANK", nil
platesByUnit.target, platesByUnit.playertarget = plate1, nil
guids.playertarget = secretToken
unitIsUnit["nameplate1|playertarget"] = false
unitIsUnit["target|playertarget"] = secretToken
tickerCallback()
assert(mark.shown and mark.shield.shown and mark.shield.alpha == 1,
    "self-tank shield uses the canonical current-target plate")
assert(mark.initialsText.text == "M.", "self-tank initials accompany the shield")
roles.player, roles.party1 = "DAMAGER", "TANK"
guids.playertarget = nil
platesByUnit.playertarget = plate1

-- Threat text is shown on the player's current target independently of the shield.
module:HandleCommand("tank clear")
platesByUnit.target = plate1
local tanking, scaledThreat, rawThreat, leadThreat = false, 40, 55, 140
local threatFails = false
function UnitDetailedThreatSituation(unit, mob)
    assert(unit == "player" and mob == "target")
    if threatFails then error("Threat read failed") end
    return tanking, 0, scaledThreat, rawThreat, 1000
end
function UnitThreatPercentageOfLead(unit, mob)
    assert(unit == "player" and mob == "target")
    return leadThreat
end
local green, yellow, red = { 0.35, 1, 0.35 }, { 1, 0.85, 0.25 }, { 1, 0.25, 0.25 }
local expectedInitial = "T."
local expectedLabel = "Threat"
local function checkThreat(value, color)
    tickerCallback()
    local expected = value == "AGGRO" and value or expectedLabel .. " " .. value
    assert(mark.threatText.shown and mark.threatText.text == expected,
        "wrong threat label: " .. tostring(mark.threatText.text))
    assert(mark.initialsText.text == expectedInitial, "tank initials belong to the shield")
    assert(mark.initialsText:GetParent() == mark.shield, "initials follow shield visibility")
    assertColor(mark.threatText, color)
    assertColor(mark.tex, { 1, 1, 1 })
    assertColor(mark.glow, { 1, 1, 1 })
end
assert(eventFrame.events.UNIT_THREAT_LIST_UPDATE and eventFrame.events.UNIT_THREAT_SITUATION_UPDATE)
checkThreat("40%", green)
for _, example in ipairs({
    { 0, green }, { 49.9, green }, { 50, yellow }, { 80, yellow }, { 80.001, red }, { 100, red },
}) do
    scaledThreat = example[1]
    checkThreat(string.format("%.0f%%", scaledThreat), example[2])
end
module:HandleCommand("threatmode raw")
checkThreat("55%", yellow)
rawThreat = nil
checkThreat("?", { 0.65, 0.65, 0.65 })
rawThreat = 55
module:HandleCommand("threatmode scaled")

-- Confirmed DPS aggro is explicit and red even if percentage data is missing.
tanking, scaledThreat = true, 100
checkThreat("AGGRO", red)
scaledThreat = nil
checkThreat("AGGRO", red)
scaledThreat = 100
module:HandleCommand("tank Me")
expectedInitial = "M."
expectedLabel = "Lead"
for _, example in ipairs({
    { 119.9, red }, { 120, yellow }, { 140, yellow }, { 150, yellow }, { 150.001, green }, { 200, green },
}) do
    leadThreat = example[1]
    checkThreat(string.format("%.0f%%", leadThreat), example[2])
end
for _, invalid in ipairs({ 0, -1, math.huge, 0 / 0 }) do
    leadThreat = invalid
    checkThreat("?", { 0.65, 0.65, 0.65 })
end
leadThreat = nil
checkThreat("?", { 0.65, 0.65, 0.65 })

-- Selected tanks that lose aggro must not see a reassuring low-threat green.
module:HandleCommand("tank Me")
tanking, rawThreat, scaledThreat = false, 90, 75
expectedLabel = "Threat"
checkThreat("90%", red)
module:HandleCommand("tank clear")
expectedInitial = "T."

-- Configurable thresholds, ordered setters, and both command validation paths.
local specs = {}
for _, spec in ipairs(module:GetOptionsSchema().options) do specs[spec.key] = spec end
module:HandleCommand("thresholds 60 90")
scaledThreat = 55
checkThreat("55%", green)
module:HandleCommand("thresholds 90 60")
assert(specs.threatLow.get() == 60 and specs.threatHigh.get() == 90)
module:HandleCommand("tankthresholds 130 180")
module:HandleCommand("tank Me")
expectedInitial = "M."
tanking, leadThreat = true, 160
expectedLabel = "Lead"
checkThreat("160%", yellow)
module:HandleCommand("tankthresholds 0 999")
assert(specs.tankThreatLow.get() == 130 and specs.tankThreatHigh.get() == 180)
specs.threatLow.set(95)
assert(specs.threatLow.get() == 95 and specs.threatHigh.get() == 96)
specs.threatHigh.set(40)
assert(specs.threatLow.get() == 39 and specs.threatHigh.get() == 40)
module:HandleCommand("thresholds 50 80")
module:HandleCommand("tankthresholds 120 150")
module:HandleCommand("tank clear")
expectedInitial = "T."
expectedLabel = "Threat"

-- Native display sinks get secret values directly; Lua must never compare them.
local function secret(value)
    return setmetatable({ secret = true, value = value }, {
        __lt = function() error("Compared secret threat") end,
        __le = function() error("Compared secret threat") end,
        __add = function() error("Added secret threat") end,
        __concat = function() error("Formatted secret threat in Lua") end,
    })
end
local curveCount = 0
C_CurveUtil = {
    CreateColorCurve = function()
        curveCount = curveCount + 1
        error("Secret values require untainted execution")
    end,
}
local neutral = { 1, 1, 1 }
local secretMessageCount = #messages
tanking, scaledThreat = secret(true), 100
checkThreat("100%", red)
assert(mark.threatText.text ~= "AGGRO", "secret aggro is not asserted from Lua")
tanking = false
for _, value in ipairs({ 49.9, 50, 80, 80.00000000000001 }) do
    scaledThreat = secret(value)
    checkThreat(string.format("%.0f%%", value), neutral)
    assert(mark.threatText.input == scaledThreat)
end
assert(curveCount == 0 and #messages == secretMessageCount,
    "secret threat bypasses restricted curves without reporting an error")
module:HandleCommand("tank Me")
expectedInitial = "M."
tanking, leadThreat = true, secret(150)
expectedLabel = "Lead"
checkThreat("150%", neutral)
leadThreat = secret(150.00000000000003)
checkThreat("150%", neutral)
specs.tankThreatHigh.set(170)
checkThreat("150%", neutral)
assert(curveCount == 0, "threshold changes do not evaluate restricted values")

-- A secret aggro-holder flag selects layered labels via native alpha, not Lua branches.
tanking, leadThreat, scaledThreat, rawThreat = secret(true), secret(140), secret(75), secret(90)
tickerCallback()
assert(mark.leadText.shown and mark.leadText.text == "Lead 140%" and mark.leadText.alpha == 1)
assert(mark.threatText.alpha == 0)
assertColor(mark.leadText, neutral)
tanking = secret(false)
tickerCallback()
assert(mark.leadText.alpha == 0 and mark.threatText.alpha == 1)
assert(mark.threatText.text == "Threat 90%")
assertColor(mark.threatText, neutral)
module:HandleCommand("tank clear")
expectedInitial = "T."
expectedLabel = "Threat"
tanking, scaledThreat = false, 25
checkThreat("25%", green)
assert(mark.threatText.alpha == 1 and not mark.leadText.shown, "reset secret alpha state")

-- A secondary assigned tank also gets lead mode, even when another tank owns the shield.
module:HandleCommand("tank Tankgal")
roles.player = "TANK"
tanking, leadThreat = true, 140
expectedLabel = "Lead"
checkThreat("140%", yellow)
roles.player = secretToken
checkThreat("140%", yellow)
roles.player = "DAMAGER"
module:HandleCommand("tank clear")
tanking, scaledThreat = false, 25
expectedLabel = "Threat"
checkThreat("25%", green)

-- Secret percentages remain visible without curve APIs; formatter errors are reported.
scaledThreat = secret(60)
C_CurveUtil = nil
checkThreat("60%", neutral)
local formattedText = mark.threatText.SetFormattedText
function mark.threatText:SetFormattedText() error("Secret formatting rejected") end
secretMessageCount = #messages
checkThreat("?", { 0.65, 0.65, 0.65 })
assert(#messages == secretMessageCount + 1 and messages[#messages]:find("Secret formatting rejected", 1, true),
    "native formatting errors remain visible")
mark.threatText.SetFormattedText = formattedText
checkThreat("60%", neutral)

-- No stale percentage after missing data, API errors, disabled UI, or target swaps.
tanking = nil
checkThreat("?", { 0.65, 0.65, 0.65 })
tanking, threatFails = false, true
local messageCount = #messages
checkThreat("?", { 0.65, 0.65, 0.65 })
checkThreat("?", { 0.65, 0.65, 0.65 })
assert(#messages == messageCount + 1, "report repeated threat errors once, not every tick")
threatFails = false
scaledThreat = secret(60)
C_CurveUtil = nil
specs.threatLow.set(45)
checkThreat("60%", neutral)
scaledThreat = 25
checkThreat("25%", green)
platesByUnit.target = plate2
tickerCallback()
assert(not mark.threatText.shown and not mark.leadText.shown)
local otherMark = plate2.sabotonTankMark
assert(otherMark.shown and otherMark.threatText.shown and otherMark.threatText.text == "Threat 25%")
assert(not otherMark.shield.shown and not otherMark.glow.shown,
    "non-tank target gets threat without a shield or glow")
assert(otherMark.initialsText:GetParent() == otherMark.shield,
    "initials hide with the shield, not with the threat text")
assert(mark.shield.shown and not mark.glow.shown, "tank target retains its neutral shield")
platesByUnit.party1target = nil
unitIsUnit["nameplate2|party1target"] = secretToken
tickerCallback()
assert(otherMark.alpha == 1 and otherMark.threatText.shown,
    "secret shield visibility must not hide current-target threat")
assert(otherMark.shield.alphaFromBoolean[1] == secretToken)
otherMark.shield.SetAlphaFromBoolean = nil
tickerCallback()
assert(otherMark.shown and otherMark.threatText.shown and not otherMark.shield.shown,
    "missing secret shield sink still allows current-target text")
otherMark.shield.SetAlphaFromBoolean = alphaFromBoolean
unitIsUnit["nameplate2|party1target"] = false
tickerCallback()
assert(otherMark.threatText.shown and not otherMark.shield.shown,
    "text remains visible when the tank has no target")
module:HandleCommand("enable")
assert(not otherMark.shown, "disabling the module hides text-only marks")
module:HandleCommand("enable")
tickerCallback()
assert(otherMark.shown, "re-enabling restores current-target text")
specs.showThreat.set(false)
tickerCallback()
assert(not otherMark.shown, "disabling threat hides text-only marks")
specs.showThreat.set(true)
roles.party1 = nil
local originalClass = UnitClass
function UnitClass() return "Mage", "MAGE" end
tickerCallback()
assert(not otherMark.shown, "no tank means no current-target label")
UnitClass = originalClass
roles.party1 = "TANK"
platesByUnit.party1target = plate1
platesByUnit.target = plate1
 tickerCallback()
assert(not otherMark.shown and mark.shield.shown, "target swaps hide the old text-only mark")
module:HandleCommand("threat")
assert(not mark.threatText.shown and not mark.leadText.shown)
module:HandleCommand("threat")
checkThreat("25%", green)
specs.showThreat.set(false)
tickerCallback()
assert(not mark.threatText.shown)
assert(mark.shield.shown and mark.initialsText.text == "T.",
    "threat toggle does not disable shield initials")

specs.showThreat.set(true)
function RegionalUniqueNamesEnabled() return true end
names.party1 = "Preda Roar"
expectedInitial = "P.R."
scaledThreat = 141
checkThreat("141%", red)
names.party1 = "Aya Zha"
expectedInitial = "A.Z."
scaledThreat = 110
checkThreat("110%", red)
names.party1, surnames.party1 = "Aya", "Zha"
checkThreat("110%", red)
names.party1, surnames.party1 = "Preda", "Roar"
expectedInitial = "P.R."
checkThreat("110%", red)
names.party1, surnames.party1 = "Aya-Zha", nil
expectedInitial = "A.Z."
checkThreat("110%", red)
names.party1, surnames.party1 = "\195\137owyn", "\195\129ra"
expectedInitial = "\195\137.\195\129."
checkThreat("110%", red)
surnames.party1 = secretToken
expectedInitial = "\195\137."
checkThreat("110%", red)
surnames.party1 = "UNKNOWN"
UNKNOWNOBJECT = "UNKNOWN"
checkThreat("110%", red)
UNKNOWNOBJECT = nil
names.party1, surnames.party1 = "Aya", "RealmName"
function RegionalUniqueNamesEnabled() return false end
expectedInitial = "A."
checkThreat("110%", red)
function RegionalUniqueNamesEnabled() return secretToken end
checkThreat("110%", red)
function RegionalUniqueNamesEnabled() return true end
surnames.party1 = nil
names.party1 = "\195\137owyn"
expectedInitial = "\195\137."
checkThreat("110%", red)
names.party1 = secretToken
expectedInitial = "?"
checkThreat("110%", red)
names.party1 = nil
checkThreat("110%", red)
names.party1 = "Tankgal"
expectedInitial = "T."
checkThreat("110%", red)
platesByUnit.target = nil
tickerCallback()
assert(not mark.glow.shown, "restore original unshared-target halo behavior")
assert(not mark.threatText.shown and not mark.leadText.shown, "clearing target hides threat labels")

-- Child scanning visits each container once and follows the widest visible bar.
local originalUnitFrame = plate1.UnitFrame
plate1.UnitFrame = nil
local narrow = {
    GetObjectType = function() return "StatusBar" end,
    IsVisible = function() return true end,
    GetWidth = function() return 50 end,
}
local container = newFrame(plate1)
container.children = { healthBar }
plate1.children = { narrow, container }
plate1.childReads, container.childReads = 0, 0
tickerCallback()
assert(mark.anchorBar == healthBar and mark.anchor == healthBar)
assert(plate1.childReads == 1 and container.childReads == 1, "enumerate children only once per scan")
plate1.children, plate1.UnitFrame = {}, originalUnitFrame

-- Missing unit tokens still resolve through the existing nameplate-token map.
platesByUnit.party1target = nil
platesByUnit.nameplate1 = plate1
plate1.namePlateUnitToken = nil
guids.party1target, guids.nameplate1 = "same-mob", "same-mob"
tickerCallback()
assert(mark.shown, "missing plate token falls back to the mapped token")
plate1.namePlateUnitToken = "nameplate1"

-- Forever instance plates can expose their token only through UnitFrame.unit.
platesByUnit.nameplate1, platesByUnit.target = nil, plate2
plate1.namePlateUnitToken = nil
plate1.UnitFrame.unit = "nameplate1"
guids.party1target, guids.nameplate1 = secretToken, secretToken
unitIsUnit["nameplate1|party1target"] = secret(true)
unitIsUnit["target|party1target"] = false
tickerCallback()
assert(mark.shown and mark.shield.shown and mark.shield.alpha == 1,
    "non-current plate uses UnitFrame.unit when direct lookup and numbered map are unavailable")
assert(mark.initialsText.text == "T." and not mark.threatText.shown,
    "other tank's non-current target gets initials without player threat")
unitIsUnit["nameplate1|party1target"] = secret(false)
tickerCallback()
assert(mark.shield.alpha == 0, "non-current secret match follows tank target swaps")
plate1.namePlateUnitToken = secretToken
unitIsUnit["nameplate1|party1target"] = secret(true)
tickerCallback()
assert(mark.shield.alpha == 1, "secret primary token falls back to readable UnitFrame.unit")
plate1.UnitFrame.unit = secretToken
tickerCallback()
assert(not mark.shown, "unreadable tokens are not passed to unit APIs")
plate1.UnitFrame.unit = nil
plate1.namePlateUnitToken = "nameplate1"
guids.party1target, guids.nameplate1 = nil, nil
unitIsUnit["nameplate1|party1target"] = false
unitIsUnit["target|party1target"] = true

-- Hostility filters the whole widget, independently of shield matching.
local enemies = { target = false, party1target = true, nameplate1 = true, nameplate2 = false }
function UnitIsEnemy(source, unit)
    assert(source == "player")
    return enemies[unit]
end
platesByUnit.party1target, platesByUnit.target = plate1, plate2
assert(not specs.hostileOnly.get(), "hostility filter explicitly disabled for unfiltered tests")
tickerCallback()
assert(plate2.sabotonTankMark.shown, "default preserves friendly target text")
module:HandleCommand("hostile")
assert(specs.hostileOnly.get() and mark.shown and not plate2.sabotonTankMark.shown,
    "hostile shield remains while friendly current-target text hides")
enemies.party1target, enemies.target = false, true
tickerCallback()
assert(not mark.shown and plate2.sabotonTankMark.shown,
    "friendly shield hides while hostile current-target text remains")
platesByUnit.target = plate1
enemies.target = false
unitIsUnit["target|party1target"] = true
platesByUnit.party1target = nil
guids.party1target, guids.nameplate1 = nil, nil
unitIsUnit["nameplate1|party1target"] = false
tickerCallback()
assert(not mark.shown, "shared-target fallback cannot bypass hostility filter")
enemies.target = secret(true)
tickerCallback()
assert(mark.shown and mark.alphaFromBoolean[1] == enemies.target,
    "secret hostility uses native alpha on the whole widget")
assert(mark.alpha == 1, "secret hostile units remain visible")
enemies.target = secret(false)
tickerCallback()
assert(mark.alpha == 0, "secret non-enemies hide the shield, initials, and threat together")
local markAlpha = mark.SetAlphaFromBoolean
mark.SetAlphaFromBoolean = nil
tickerCallback()
assert(not mark.shown, "unsupported secret hostility stays hidden")
mark.SetAlphaFromBoolean = markAlpha
enemies.target = nil
tickerCallback()
assert(not mark.shown, "unknown hostility stays hidden")
function UnitIsEnemy() error("Hostility read failed") end
messageCount = #messages
tickerCallback()
assert(not mark.shown and #messages == messageCount + 1, "failed hostility hides and reports")
UnitIsEnemy = nil
tickerCallback()
assert(not mark.shown, "missing hostility API stays hidden")
specs.hostileOnly.set(false)
assert(mark.shown and mark.alpha == 1, "disabling filter restores the widget and clears secret alpha")

-- Multiple tanks share one comma-separated label, sorted by identity, not roster slot.
memberCount = 3
names.party1, names.party2 = "Preda", "Aya"
surnames.party1, surnames.party2 = "Roar", "Zha"
roles.party1, roles.party2, roles.player = "TANK", "TANK", "DAMAGER"
platesByUnit.party1target, platesByUnit.party2target = plate1, plate1
platesByUnit.target = plate2
unitIsUnit["target|party1target"] = false
unitIsUnit["target|party2target"] = false
tanking, scaledThreat = false, 25
tickerCallback()
assert(mark.shield.shown and mark.initialsText.text == "A.Z., P.R.",
    "one shield lists all matching tanks in stable identity order")
assert(plate2.sabotonTankMark.threatText.text == "Threat 25%",
    "multi-tank initials do not change player threat")
roles.player = "TANK"
platesByUnit.target = plate1
tanking, leadThreat = true, 140
tickerCallback()
assert(mark.initialsText.text == "A.Z., M., P.R." and mark.threatText.text == "Lead 140%",
    "self-tank uses canonical target and joins the shared label without changing lead semantics")
platesByUnit.target = plate2
tickerCallback()
assert(plate2.sabotonTankMark.shield.shown and plate2.sabotonTankMark.initialsText.text == "M.",
    "self-tank targeting another mob has its own shield")
roles.player, tanking = "DAMAGER", false
tickerCallback()
local originalMark = mark
names.party1, names.party2 = names.party2, names.party1
surnames.party1, surnames.party2 = surnames.party2, surnames.party1
tickerCallback()
assert(mark == originalMark and mark.initialsText.text == "A.Z., P.R.",
    "roster reordering neither duplicates the widget nor shuffles initials")
platesByUnit.party2target = plate2
tickerCallback()
assert(mark.initialsText.text == "A.Z." and plate2.sabotonTankMark.initialsText.text == "P.R.",
    "separate mobs receive their own tank initials")
assert(plate2.sabotonTankMark.shield.shown and plate2.sabotonTankMark.glow.shown)
roles.party1, roles.party2 = secretToken, secretToken
tickerCallback()
assert(mark.initialsText.text == "A.Z." and plate2.sabotonTankMark.initialsText.text == "P.R.",
    "all cached tank identities survive secret roles")
roles.party1, roles.party2 = "TANK", "DAMAGER"
tickerCallback()
assert(not plate2.sabotonTankMark.shield.shown, "readable role changes remove stale tanks")
roles.party2 = "TANK"
platesByUnit.party2target = plate1
tickerCallback()
memberCount = 2
tickerCallback()
assert(mark.initialsText.text == "A.Z.", "departed tanks are removed")
memberCount, roles.party2 = 3, secretToken
tickerCallback()
assert(mark.initialsText.text == "A.Z.", "departed tank cache is not reused on secret rejoin")
roles.party2 = "TANK"
tickerCallback()
module:HandleCommand("tank Aya")
assert(mark.initialsText.text == "A.Z.", "manual selection still limits tracking to the chosen tank")
module:HandleCommand("tank clear")
assert(mark.initialsText.text == "A.Z., P.R.", "clearing manual selection restores all tanks")

roles.party1, roles.party2 = "NONE", "NONE"
function GetPartyAssignment(_, unit) return unit == "party1" or unit == "party2" end
tickerCallback()
assert(mark.initialsText.text == "A.Z., P.R.", "all main-tank assignments are tracked without TANK roles")
GetPartyAssignment = nil
roles.party1, roles.party2 = "TANK", "TANK"
platesByUnit.party2target = nil
unitIsUnit["target|party2target"] = nil
guids.party2target, guids.nameplate2 = "second-mob", "second-mob"
tickerCallback()
assert(mark.initialsText.text == "A.Z." and plate2.sabotonTankMark.initialsText.text == "P.R.",
    "each tank independently falls back to readable GUID matching")
guids.party2target, guids.nameplate2 = nil, nil
unitIsUnit["nameplate1|party2target"] = false
unitIsUnit["nameplate2|party2target"] = false
unitIsUnit["target|party2target"] = true
tickerCallback()
assert(plate2.sabotonTankMark.shield.shown and plate2.sabotonTankMark.initialsText.text == "P.R.",
    "a resolved first tank cannot suppress another tank's shared-target fallback")
unitIsUnit["target|party2target"] = false
unitIsUnit["nameplate1|party2target"] = secret(true)
unitIsUnit["nameplate2|party2target"] = secret(false)
messageCount = #messages
tickerCallback()
assert(mark.initialsText.text == "A.Z." and not plate2.sabotonTankMark.shield.shown,
    "restricted multi-tank matches never invent combined initials")
local secretRow = mark.secretRows[1]
assert(secretRow.shown and secretRow.alpha == 1 and secretRow.text.text == "P.R.",
    "secret true shows another tank's independent shield row beside resolved initials")
assert(#messages == messageCount, "supported native secret rows do not warn")
tickerCallback()
unitIsUnit["nameplate1|party2target"] = secret(false)
unitIsUnit["target|party2target"] = secret(true)
tickerCallback()
assert(secretRow.alpha == 0, "target swaps hide the old secret row")
local otherSecretRow = plate2.sabotonTankMark.secretRows[1]
assert(otherSecretRow.shown and otherSecretRow.alpha == 1 and otherSecretRow.text.text == "P.R.",
    "canonical target comparison controls the current-target row")
assert(otherSecretRow:GetParent() == plate2.sabotonTankMark,
    "secret rows inherit the same hostile-only and module visibility as threat and resolved shields")
local nativeAlpha = otherSecretRow.SetAlphaFromBoolean
function otherSecretRow:SetAlphaFromBoolean() error("Secret alpha rejected") end
tickerCallback()
assert(not otherSecretRow.shown and messages[#messages]:find("Secret alpha rejected", 1, true),
    "rejected native rendering hides the row and explicitly reports the error")
otherSecretRow.SetAlphaFromBoolean = nil
tickerCallback()
assert(not otherSecretRow.shown, "missing native sink cannot show a guessed row")
otherSecretRow.SetAlphaFromBoolean = nativeAlpha
roles.party1 = "DAMAGER"
tickerCallback()
assert(plate2.sabotonTankMark.shield.shown and plate2.sabotonTankMark.shield.alpha == 1,
    "another player as the sole tank uses the canonical secret target comparison")
assert(plate2.sabotonTankMark.initialsText.text == "P.R." and not otherSecretRow.shown,
    "switching to single-tank mode clears multi-tank rows")
local singleAlpha = plate2.sabotonTankMark.shield.SetAlphaFromBoolean
function plate2.sabotonTankMark.shield:SetAlphaFromBoolean() error("Single secret alpha rejected") end
tickerCallback()
assert(not plate2.sabotonTankMark.shield.shown and plate2.sabotonTankMark.threatText.shown,
    "sole remote tank rendering rejection hides only the shield, preserving threat text")
plate2.sabotonTankMark.shield.SetAlphaFromBoolean = singleAlpha
roles.party1 = "TANK"
platesByUnit.party2target = plate1
tickerCallback()
assert(mark.initialsText.text == "A.Z., P.R." and not secretRow.shown,
    "resolved matches return to comma-separated initials without stale rows")

-- Raid tanks use the same aggregation, including a raid token that denotes the player.
local originalInRaid = IsInRaid
function IsInRaid() return true end
roles.raid1, roles.raid2 = "TANK", "TANK"
names.raid1, surnames.raid1 = "Me", nil
names.raid2, surnames.raid2 = "Aya", "Zha"
unitIsUnit["raid1|player"] = true
platesByUnit.target, platesByUnit.raid2target = plate1, plate1
platesByUnit.raid1target = nil
tickerCallback()
assert(mark.shield.shown and mark.initialsText.text == "A.Z., M.",
    "raid player alias uses canonical target and aggregates with the other tank")
IsInRaid = originalInRaid

-- Forced shields bypass matching, tokens, tank detection, and hostility.
local savedRoles, savedNames = roles, names
roles, names = {}, {}
local savedClass = UnitClass
function UnitClass() return "Mage", "MAGE" end
platesByUnit.target = nil
local savedPlate1Frame, savedPlate2Frame = plate1.UnitFrame, plate2.UnitFrame
plate1.namePlateUnitToken, plate2.namePlateUnitToken = nil, nil
plate1.UnitFrame, plate2.UnitFrame = nil, nil
platesByUnit.nameplate1, platesByUnit.nameplate2 = nil, nil
specs.hostileOnly.set(true)
module:HandleCommand("testshields")
for _, plate in ipairs(plates) do
    local widget = plate.sabotonTankMark
    assert(widget.shown and widget.alpha == 1 and widget.shield.shown and widget.shield.alpha == 1)
    assert(widget.initialsText.text == "TEST" and not widget.threatText.shown,
        "unconditional diagnostic renders on non-target plates without unit data")
end
assert(module:GetPersistentState().forceShields == nil, "forced shields must not persist")
module:HandleCommand("enable")
assert(not mark.shown, "module disable hides diagnostic shields")
module:HandleCommand("enable")
tickerCallback()
assert(mark.shown, "enabled diagnostic resumes")
module:HandleCommand("testshields")
assert(not mark.shown and not plate2.sabotonTankMark.shown, "diagnostic off restores real matching")

-- Each all-nameplate label queries its own unit, without requiring any tank.
plate1.UnitFrame, plate2.UnitFrame = savedPlate1Frame, savedPlate2Frame
plate1.UnitFrame.unit, plate2.UnitFrame.unit = "nameplate1", "nameplate2"
local savedDetailed, savedLead = UnitDetailedThreatSituation, UnitThreatPercentageOfLead
local reads = {}
function UnitDetailedThreatSituation(unit, mob)
    assert(unit == "player")
    reads[mob] = true
    if mob == "nameplate1" then return false, 0, 30, 45, 100 end
    assert(mob == "nameplate2", "must not reuse the player's target")
    return false, 0, 85, 95, 200
end
specs.hostileOnly.set(false)
assert(not specs.allThreat.get(), "all-nameplate threat defaults off")
module:HandleCommand("allthreat")
assert(reads.nameplate1 and reads.nameplate2)
assert(mark.threatText.text == "Threat 30%" and plate2.sabotonTankMark.threatText.text == "Threat 85%")
assert(not mark.shield.shown, "all-nameplate threat must not invent tank shields")
function UnitIsEnemy(_, unit) return unit == "nameplate1" end
specs.hostileOnly.set(true)
assert(mark.shown and not plate2.sabotonTankMark.shown,
    "all-nameplate threat respects hostile-only filtering per mob")
specs.hostileOnly.set(false)
roles.player = "TANK"
function UnitDetailedThreatSituation(unit, mob)
    assert(unit == "player")
    return true, 3, 100, 100, 1000
end
function UnitThreatPercentageOfLead(unit, mob)
    assert(unit == "player")
    if mob == "nameplate1" then return 160 end
    assert(mob == "nameplate2")
    return 125
end
tickerCallback()
assert(mark.threatText.text == "Lead 160%" and plate2.sabotonTankMark.threatText.text == "Lead 125%",
    "tank leads are independently queried per mob")
local attackable, dead = true, false
function UnitCanAttack(source, unit)
    assert(source == "player" and (unit == "nameplate1" or unit == "nameplate2"))
    return attackable
end
function UnitIsDeadOrGhost(unit)
    assert(unit == "nameplate1" or unit == "nameplate2")
    return dead
end
attackable = false
tickerCallback()
assert(not mark.threatText.shown and not mark.leadText.shown,
    "objects and non-attackable units have no threat labels")
attackable, dead = true, true
tickerCallback()
assert(not mark.threatText.shown and not mark.leadText.shown, "dead units have no threat labels")
attackable, dead = secret(true), secret(false)
tickerCallback()
assert(mark.threatAttackable.alpha == 1 and mark.threatAlive.alpha == 1 and mark.threatText.shown,
    "living attackable secret units render through independent gates")
function UnitDetailedThreatSituation() return secret(true), 3, 100, 100, 1000 end
tickerCallback()
assert(mark.threatText:GetParent() == mark.threatAlive and mark.leadText:GetParent() == mark.threatAlive
    and mark.threatAlive:GetParent() == mark.threatAttackable,
    "eligibility gates must parent both threat layers")
assert(mark.threatText.alpha == 0 and mark.leadText.alpha == 1 and mark.leadText.shown,
    "secret alive checks must preserve the separate secret tank lead selection")
dead = secret(true)
tickerCallback()
assert(mark.threatAlive.alpha == 0, "native dead check hides both threat layers")
attackable, dead = secret(false), secret(false)
tickerCallback()
assert(mark.threatAttackable.alpha == 0, "native attackability check hides object labels")
attackable, dead = true, false
tickerCallback()
assert(mark.threatAttackable.alpha == 1 and mark.threatAlive.alpha == 1,
    "readable checks reset stale secret eligibility alpha")
local eligibilitySink = mark.threatAlive.SetAlphaFromBoolean
function mark.threatAlive:SetAlphaFromBoolean() error("Eligibility alpha rejected") end
dead = secret(false)
messageCount = #messages
tickerCallback()
assert(not mark.threatText.shown and #messages > messageCount,
    "rejected eligibility rendering hides labels and reports the error")
mark.threatAlive.SetAlphaFromBoolean = eligibilitySink
attackable, dead = true, nil
tickerCallback()
assert(not mark.threatText.shown and not mark.leadText.shown, "unknown death state hides threat")
dead = false
UnitIsDeadOrGhost = nil
messageCount = #messages
tickerCallback()
assert(not mark.threatText.shown and #messages > messageCount, "missing eligibility API is reported")
function UnitCanAttack() return true end
function UnitIsDeadOrGhost() return false end
specs.showThreat.set(false)
tickerCallback()
assert((not mark.shown or not mark.threatText.shown)
    and (not plate2.sabotonTankMark.shown or not plate2.sabotonTankMark.threatText.shown),
    "master threat toggle applies to all-plate mode")
specs.showThreat.set(true)
plate2.UnitFrame.unit = nil
tickerCallback()
assert(not plate2.sabotonTankMark.threatText.shown,
    "missing plate token hides threat instead of labeling an unidentified object")
specs.allThreat.set(false)
roles, names, UnitClass = savedRoles, savedNames, savedClass
UnitDetailedThreatSituation, UnitThreatPercentageOfLead = savedDetailed, savedLead
plate1.UnitFrame.unit, plate2.UnitFrame.unit = nil, nil
plate1.namePlateUnitToken, plate2.namePlateUnitToken = "nameplate1", "nameplate2"

-- Guessing can be disabled without disabling explicit tanks or solo pets.
memberCount = 2
names.player, names.party1 = "Me", "Tankgal"
surnames.player, surnames.party1 = nil, nil
roles.player, roles.party1 = "DAMAGER", "DAMAGER"
platesByUnit.target, platesByUnit.party1target = plate2, plate1
local holdingThreat = true
function UnitDetailedThreatSituation(unit, mob)
    if unit == "party1" then return holdingThreat, 3, 100, 100, 1000 end
    return false, 0, 30, 30, 100
end
assert(specs.inferGroupTank.default and specs.inferGroupTank.get(), "guessing defaults on")
tickerCallback()
assert(mark.shown and mark.initialsText.text == "T.", "threat holder is guessed when enabled")
holdingThreat = false
now = now + 1
tickerCallback()
assert(mark.shown, "recent threat holder is remembered")
module:HandleCommand("guess")
assert(not specs.inferGroupTank.get() and not mark.shown, "disabling guessing immediately hides guessed shield")
assert(not plate2.sabotonTankMark.shown, "current-target threat remains hidden without a tank by default")
holdingThreat = true
tickerCallback()
assert(not mark.shown, "active threat cannot bypass disabled guessing")
holdingThreat = false
now = now + 1
local savedCombat = UnitAffectingCombat
function UnitAffectingCombat() return true end
specs.inferGroupTank.set(true)
assert(not mark.shown, "re-enabling cannot revive a threat holder cached before disabling")
UnitAffectingCombat = savedCombat
specs.inferGroupTank.set(true)
assert(mark.shown, "only tank-capable class is guessed outside combat")
specs.inferGroupTank.set(false)
module:HandleCommand("tank Tankgal")
assert(mark.shown, "manual selection works when guessing is disabled")
module:HandleCommand("tank clear")
roles.party1 = "TANK"
tickerCallback()
assert(mark.shown, "assigned TANK role works when guessing is disabled")
roles.party1 = secretToken
tickerCallback()
assert(mark.shown, "cached assigned role works when guessing is disabled")
roles.party1 = "DAMAGER"
function GetPartyAssignment(_, unit) return unit == "party1" end
tickerCallback()
assert(mark.shown, "main-tank assignment works when guessing is disabled")
GetPartyAssignment = nil
tickerCallback()
assert(not mark.shown, "removing explicit assignment hides shield")
specs.allThreat.set(true)
assert(plate2.sabotonTankMark.shown and plate2.sabotonTankMark.threatText.shown,
    "all-nameplate threat remains available without a detected tank")
specs.allThreat.set(false)
local savedInGroup = IsInGroup
function IsInGroup() return false end
existing.pet, names.pet = true, "Pet"
platesByUnit.pettarget = plate1
tickerCallback()
assert(mark.shown and mark.initialsText.text == "P.", "solo pet option remains independent")
specs.petSoloTank.set(false)
tickerCallback()
assert(not mark.shown, "solo pet option still controls pet detection")
specs.petSoloTank.set(true)
IsInGroup = savedInGroup
existing.pet, names.pet, platesByUnit.pettarget = nil, nil, nil
UnitDetailedThreatSituation = savedDetailed
specs.inferGroupTank.set(true)

-- Unsupported events are visible rather than silently swallowed.
unsupportedEvent = "UNIT_THREAT_LIST_UPDATE"
messageCount = #messages
module:OnEnable()
assert(#messages == messageCount + 1 and messages[#messages]:find(unsupportedEvent, 1, true))

print("Tank Target tests passed")
