local alt, combat, saves = false, false, 0
local frames = {}
local methods = {}
local function noop() end
for _, key in ipairs({ "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetSize", "SetFrameStrata",
    "SetAllPoints", "SetColorTexture", "ClearAllPoints" }) do methods[key] = noop end
function methods:EnableMouse(value) self.mouse = value end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetScript(key, callback) self.scripts[key] = callback end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetCenter() return 500 + (self.x or 0), 400 + (self.y or 0) end
function methods:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
function methods:SetText(text) self.text = text end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:CreateTexture() return setmetatable({}, { __index = methods }) end
function methods:CreateFontString() return setmetatable({}, { __index = methods }) end
function CreateFrame()
    local frame = setmetatable({ scripts = {}, events = {} }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end
UIParent = CreateFrame()
function IsAltKeyDown() return alt end
function InCombatLockdown() return combat end
local addon = { SaveSettings = function() saves = saves + 1 end }
assert(loadfile("src/Support/TimerBars.lua"))("SabotonEssentials", addon)
local bars = addon.TimerBars
local locked, x, y = true, nil, nil
local window, handle = CreateFrame(), CreateFrame()
bars.MakeMovable(window, function() return locked end, function(a, b) x, y = a, b end, handle)
local function modifier(value)
    alt = value
    for _, frame in ipairs(frames) do
        if frame.events.MODIFIER_STATE_CHANGED then frame.scripts.OnEvent(frame, "MODIFIER_STATE_CHANGED", "LALT", value and 1 or 0) end
    end
end
assert(not handle.mouse)
handle.scripts.OnDragStart()
handle.scripts.OnDragStop()
assert(not window.moving and saves == 0)
modifier(true)
assert(handle.mouse)
handle.scripts.OnDragStart()
assert(window.moving and locked, "Alt must bypass the lock without changing it")
modifier(false)
assert(handle.mouse, "releasing Alt mid-drag must retain the stop callback")
window.x, window.y = 140, -90
handle.scripts.OnDragStop()
assert(x == 140 and y == -90 and saves == 1 and not handle.mouse and locked)
combat = true
modifier(true)
handle.scripts.OnDragStart()
assert(not window.moving, "Alt must never permit combat movement")
combat = false
modifier(false)
locked = false
bars.RefreshMovable(handle)
assert(handle.mouse)
handle.scripts.OnDragStart()
assert(window.moving, "ordinary unlocked dragging must still work")
handle.scripts.OnDragStop()
local hover = CreateFrame()
bars.MakeMovable(window, function() return true end, noop, hover, true)
modifier(true)
modifier(false)
assert(hover.mouse, "tooltip handles must keep receiving hover events while locked")
local offsetX, offsetY = 200, 200
local anchor = bars.ToggleTextAnchor(nil, "Alert start", function() return offsetX, offsetY end,
    function(a, b) offsetX, offsetY = a, b end)
assert(anchor.shown and anchor.x == 200 and not anchor.mouse)
modifier(true)
anchor.scripts.OnDragStart()
anchor.x, anchor.y = -150, 80
anchor.scripts.OnDragStop()
assert(offsetX == -150 and offsetY == 80)
bars.ToggleTextAnchor(anchor)
assert(not anchor.shown, "anchors are explicitly toggled and session-only")
print("Shared modifier movement and text anchor tests passed")
