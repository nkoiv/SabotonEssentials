UIParent = {}
Settings = nil
local frames = {}
local module
local horizontal, vertical = 0, 0
local movement, fade = 0.9, 0.5
local mobOpened = false
local spellOpened = false
local minimapShown, wowheadEnabled, chatTabsEnabled, chatInputHidden, chatCustomSize = true, false, false, false, false
local chatButtonsHidden = false
local saves = 0

function CreateFrame(kind, ...)
    local frame = { kind = kind, scripts = {} }
    function frame:SetSize(...) end
    function frame:SetPoint(...) end
    function frame:SetFrameStrata(...) end
    function frame:SetBackdrop(...) end
    function frame:SetText(value) self.text = value end
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked end
    function frame:EnableMouse(...) end
    function frame:Hide() self.shown = false end
    function frame:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:IsShown() return self.shown end
    function frame:SetOrientation(...) end
    function frame:SetMinMaxValues(...) end
    function frame:SetValueStep(...) end
    function frame:SetObeyStepOnDrag(...) end
    function frame:SetThumbTexture(...) end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function frame:CreateFontString(...)
        local text = {}
        function text:SetPoint(...) end
        function text:SetText(value) self.value = value frame.label = value end
        return text
    end
    function frame:CreateTexture(...)
        local texture = {}
        function texture:SetPoint(...) end
        function texture:SetHeight(...) end
        function texture:SetColorTexture(...) end
        return texture
    end
    frames[#frames + 1] = frame
    return frame
end

local addon = {
    modules = {
        chattabs = { GetOptionsSchema = function() return { options = {
            { type = "checkbox", label = "Hide chat tabs until hovered", get = function() return chatTabsEnabled end, set = function(v) chatTabsEnabled = v end },
            { type = "checkbox", label = "Hide chat input box until typing", get = function() return chatInputHidden end, set = function(v) chatInputHidden = v end },
            { type = "checkbox", label = "Hide chat buttons", get = function() return chatButtonsHidden end, set = function(v) chatButtonsHidden = v end },
            { type = "checkbox", label = "Use custom chat message font size", get = function() return chatCustomSize end, set = function(v) chatCustomSize = v end },
        } } end },
        minimap = { GetOptionsSchema = function() return { options = {
            { type = "checkbox", label = "Show minimap button", get = function() return minimapShown end, set = function(v) minimapShown = v end },
        } } end },
        wowhead = { GetOptionsSchema = function() return { options = {
            { type = "checkbox", label = "Show Wowhead link in creature menus", get = function() return wowheadEnabled end, set = function(v) wowheadEnabled = v end },
        } } end },
        mobtimer = { ToggleEditor = function() mobOpened = true end },
        tankhelper = { ToggleSpellEditor = function() spellOpened = true end },
        extraattack = {
            GetOptionsSchema = function()
                return { options = {
                    { key = "textOffsetX", label = "Horizontal", min = -600, max = 600, step = 10, format = "%d", get = function() return horizontal end, set = function(value) horizontal = value end },
                    { key = "textOffsetY", label = "Vertical", min = -400, max = 400, step = 10, format = "%d", get = function() return vertical end, set = function(value) vertical = value end },
                    { key = "textArcDuration", label = "Movement", min = 0.2, max = 3, step = 0.1, format = "%.1fs", get = function() return movement end, set = function(value) movement = value end },
                    { key = "textFadeDuration", label = "Fade", min = 0.1, max = 3, step = 0.1, format = "%.1fs", get = function() return fade end, set = function(value) fade = value end },
                } }
            end,
        },
    },
    RegisterModule = function(_, value) module = value end,
    SaveSettings = function() saves = saves + 1 end,
    Print = function() end,
}
assert(loadfile("src/Options.lua"))("SabotonEssentials", addon)
module:OnEnable()
module:HandleCommand()
local panel = frames[1]
local sliders = {}
for _, frame in ipairs(frames) do
    if frame.kind == "Slider" then sliders[#sliders + 1] = frame end
end
assert(panel:IsShown() and #sliders == 4)
local checkboxes = {}
for _, frame in ipairs(frames) do
    if frame.kind == "CheckButton" then checkboxes[frame.label] = frame end
end
local minimapCheck = assert(checkboxes["Show minimap button"])
local wowheadCheck = assert(checkboxes["Show Wowhead link in creature menus"])
local chatTabsCheck = assert(checkboxes["Hide chat tabs until hovered"])
local chatInputCheck = assert(checkboxes["Hide chat input box until typing"])
local chatButtonsCheck = assert(checkboxes["Hide chat buttons"])
local sizeCheck = assert(checkboxes["Use custom chat message font size"])
assert(minimapCheck.checked and not wowheadCheck.checked and not chatTabsCheck.checked and not chatInputCheck.checked and not sizeCheck.checked)
assert(not chatButtonsCheck.checked)
minimapCheck:SetChecked(false)
minimapCheck.scripts.OnClick(minimapCheck)
wowheadCheck:SetChecked(true)
wowheadCheck.scripts.OnClick(wowheadCheck)
chatTabsCheck:SetChecked(false)
chatTabsCheck.scripts.OnClick(chatTabsCheck)
chatInputCheck:SetChecked(true)
chatInputCheck.scripts.OnClick(chatInputCheck)
chatButtonsCheck:SetChecked(true)
chatButtonsCheck.scripts.OnClick(chatButtonsCheck)
sizeCheck:SetChecked(true)
sizeCheck.scripts.OnClick(sizeCheck)
assert(not minimapShown and wowheadEnabled and not chatTabsEnabled and chatInputHidden and chatButtonsHidden and chatCustomSize and saves >= 6)
for _, frame in ipairs(frames) do
    if frame.text == "Mob Spawn Timer: manage mobs" then frame.scripts.OnClick(frame) end
    if frame.text == "Miss Alerts: manage spells" then frame.scripts.OnClick(frame) end
end
assert(mobOpened, "fallback options must open the mob editor")
assert(spellOpened, "fallback options must open the spell editor")
sliders[1]:SetValue(200)
sliders[2]:SetValue(-100)
assert(horizontal == 200 and vertical == -100)
sliders[3]:SetValue(1.5)
sliders[4]:SetValue(0.8)
assert(movement == 1.5 and fade == 0.8)
module:HandleCommand()
assert(not panel:IsShown())
horizontal, vertical = -150, 80
module:HandleCommand()
assert(panel:IsShown() and sliders[1].value == -150 and sliders[2].value == 80)
assert(sliders[3].value == 1.5 and sliders[4].value == 0.8)
assert(not minimapCheck.checked and wowheadCheck.checked and not chatTabsCheck.checked and chatInputCheck.checked and sizeCheck.checked)
assert(chatButtonsCheck.checked)
print("Fallback options tests passed")