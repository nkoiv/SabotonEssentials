local module
local messages, callbacks, frames = {}, {}, {}
local units = {}
local secret = {}

function issecretvalue(value) return value == secret end
function UnitGUID(unit)
    if units[unit] == "error" then error("unit unavailable") end
    return units[unit]
end
UIParent = {}
UISpecialFrames = {}
Menu = { ModifyMenu = function(tag, callback) callbacks[tag] = callback end }
function CreateFrame(kind, name)
    local frame = { kind = kind, name = name, scripts = {} }
    frames[#frames + 1] = frame
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetFrameStrata() end
    function frame:EnableMouse() end
    function frame:SetMovable() end
    function frame:RegisterForDrag() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetBackdrop() end
    function frame:SetAutoFocus() end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetText(text) self.text = text end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:HighlightText() self.highlighted = true end
    function frame:Show() self.shown = true end
    function frame:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frame:CreateFontString()
        return { SetPoint = function() end, SetText = function() end }
    end
    return frame
end
local addon = {
    Print = function(message) messages[#messages + 1] = message end,
    RegisterModule = function(name, value) assert(name == "wowhead") module = value end,
}
local function hasMessage(text)
    for _, message in ipairs(messages) do
        if message:find(text, 1, true) then return true end
    end
    return false
end
local function makeMenu(tag, context)
    local root = { dividers = 0 }
    function root:CreateDivider() self.dividers = self.dividers + 1 end
    function root:CreateButton(label, callback) self.label, self.callback = label, callback end
    callbacks[tag](nil, root, context)
    return root
end

assert(loadfile("src/Modules/WowheadLink.lua"))("SabotonEssentials", addon)
module:OnEnable()
assert(callbacks.MENU_UNIT_TARGET and callbacks.MENU_UNIT_FOCUS)
units.target = "Creature-0-123-456-789-448-0000ABCDEF"
local option = module:GetOptionsSchema().options[1]
assert(option.default == false and option.get() == false)
assert(not makeMenu("MENU_UNIT_TARGET", { unit = "target", fromTargetFrame = true }).callback)
option.set(true)
local targetMenu = makeMenu("MENU_UNIT_TARGET", { unit = "target", fromTargetFrame = true })
assert(targetMenu.label == "Copy Wowhead link" and targetMenu.dividers == 1)
option.set(false)
targetMenu.callback()
assert(#frames == 0, "disabling must also suppress already-created menu entries")
option.set(true)
units.target = "Creature-0-123-456-789-999-0000ABCDEF"
targetMenu.callback()
local popup = frames[1]
assert(popup.editBox.text == "https://www.wowhead.com/forever/npc=448")
assert(popup.shown and popup.editBox.focused and popup.editBox.highlighted)
assert(UISpecialFrames[1] == "SabotonWowheadLinkPopup")
popup.editBox.scripts.OnEscapePressed()
assert(not popup.shown and not popup.editBox.focused)

units.focus = "Creature-0-123-456-789-1234-0000ABCDEF"
local focusMenu = makeMenu("MENU_UNIT_FOCUS", { unit = "focus", fromFocusFrame = true })
focusMenu.callback()
assert(popup.editBox.text == "https://www.wowhead.com/forever/npc=1234")
assert(#UISpecialFrames == 1)
module:HandleCommand("")
assert(popup.editBox.text == "https://www.wowhead.com/forever/npc=999")
module:HandleCommand("help")
assert(hasMessage("Usage:"))

units.focus = "Player-123-00000001"
assert(not makeMenu("MENU_UNIT_FOCUS", { unit = "focus", fromFocusFrame = true }).callback)
assert(not makeMenu("MENU_UNIT_TARGET", { unit = "target" }).callback)
assert(not makeMenu("MENU_UNIT_TARGET", nil).callback)
units.target = secret
local restricted = makeMenu("MENU_UNIT_TARGET", { unit = "target", fromTargetFrame = true })
restricted.callback()
assert(hasMessage("GUID is restricted"))
units.target = "Creature-0-123-456-789-bad-0000"
module:HandleCommand("")
assert(hasMessage("unrecognized format"))
units.target = "Creature-0-123-456-789-0-0000"
module:HandleCommand("")
assert(hasMessage("unrecognized format"))
units.target = nil
module:HandleCommand("")
assert(hasMessage("No readable unit GUID"))
units.target = "error"
module:HandleCommand("")
assert(hasMessage("Could not read the unit GUID"))
units.target = "Player-123-00000001"
module:HandleCommand("")
assert(hasMessage("not a creature"))
option.set(false)
units.target = "Creature-0-123-456-789-448-0000ABCDEF"
module:HandleCommand("")
assert(popup.editBox.text == "https://www.wowhead.com/forever/npc=448", "slash lookup remains available with the menu off")

Menu = nil
module:OnEnable()
option.set(true)
assert(hasMessage("portrait menus are unavailable"))
Menu = { ModifyMenu = function(tag) error("registration failed: " .. tag) end }
module:OnEnable()
option.set(true)
assert(hasMessage("could not register MENU_UNIT_TARGET"))
assert(hasMessage("could not register MENU_UNIT_FOCUS"))
print("Wowhead link tests passed")
