UIParent = {}
Settings = nil
local frames = {}
local module
local horizontal, vertical = 0, 0
local movement, fade = 0.9, 0.5

function CreateFrame(kind, ...)
    local frame = { kind = kind, scripts = {} }
    function frame:SetSize(...) end
    function frame:SetPoint(...) end
    function frame:SetFrameStrata(...) end
    function frame:SetBackdrop(...) end
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
        function text:SetText(value) self.value = value end
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
print("Fallback options tests passed")