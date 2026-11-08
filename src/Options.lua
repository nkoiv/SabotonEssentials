local ADDON_NAME, addon = ...

-- Builds one Settings panel from declarative option schemas exposed by other modules
-- (see each module's GetOptionsSchema), keeping all Settings-API/UI code out of them.
--
-- When the Settings API is unavailable, the offset sliders use a small fallback window.
local Options = {}

local settingsAvailable = rawget(_G, "Settings") ~= nil

local function saveOption(spec, value)
    spec.set(value)
    if addon.SaveSettings then addon.SaveSettings() end
end

-- Settings proxy variable keys are global across the client, so namespace them per addon+module+option.
local function toVariableKey(moduleKey, optionKey)
    return string.format("SABOTONESSENTIALS_%s_%s", string.upper(moduleKey), string.upper(optionKey))
end

local function createCheckbox(subcategory, moduleKey, spec)
    local setting = Settings.RegisterProxySetting(
        subcategory,
        toVariableKey(moduleKey, spec.key),
        Settings.VarType.Boolean,
        spec.label,
        spec.default or false,
        spec.get,
        function(value) saveOption(spec, value) end
    )

    Settings.CreateCheckbox(subcategory, setting, spec.tooltip)
end

local function createSlider(subcategory, moduleKey, spec)
    local setting = Settings.RegisterProxySetting(
        subcategory,
        toVariableKey(moduleKey, spec.key),
        Settings.VarType.Number,
        spec.label,
        spec.default or spec.min or 0,
        spec.get,
        function(value) saveOption(spec, value) end
    )

    local sliderOptions = Settings.CreateSliderOptions(spec.min, spec.max, spec.step)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format(spec.format or "%.1f", value)
    end)

    Settings.CreateSlider(subcategory, setting, sliderOptions, spec.tooltip)
end

local function createDropdown(subcategory, moduleKey, spec)
    local setting = Settings.RegisterProxySetting(
        subcategory,
        toVariableKey(moduleKey, spec.key),
        Settings.VarType.String,
        spec.label,
        spec.default,
        spec.get,
        function(value) saveOption(spec, value) end
    )

    -- spec.choices may be a static list or a function, so callers can compute choices dynamically
    -- (e.g. filtering by another option's current value) each time the dropdown is opened.
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        local choices = type(spec.choices) == "function" and spec.choices() or spec.choices
        for _, choice in ipairs(choices) do
            container:Add(choice.value, choice.label)
        end
        return container:GetData()
    end

    Settings.CreateDropdown(subcategory, setting, GetOptions, spec.tooltip)
end

local optionBuilders = {
    checkbox = createCheckbox,
    slider = createSlider,
    dropdown = createDropdown,
}

local function createFallbackPanel()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(360, 290)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    panel:EnableMouse(true)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Extra Attack")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local options = addon.modules.extraattack:GetOptionsSchema().options
    local row = 0
    local refreshers = {}
    for _, spec in ipairs(options) do
        if spec.key == "textOffsetX" or spec.key == "textOffsetY" or spec.key == "textArcDuration" or spec.key == "textFadeDuration" then
            row = row + 1
            local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("TOPLEFT", 30, -40 - row * 50)

            local slider = CreateFrame("Slider", nil, panel)
            slider:SetSize(290, 16)
            slider:SetPoint("TOPLEFT", 30, -57 - row * 50)
            slider:SetOrientation("HORIZONTAL")
            slider:SetMinMaxValues(spec.min, spec.max)
            slider:SetValueStep(spec.step)
            slider:SetObeyStepOnDrag(true)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            local track = slider:CreateTexture(nil, "BACKGROUND")
            track:SetPoint("LEFT")
            track:SetPoint("RIGHT")
            track:SetHeight(3)
            track:SetColorTexture(0.45, 0.45, 0.45, 1)
            slider:SetValue(spec.get())
            label:SetText(spec.label .. ": " .. string.format(spec.format, spec.get()))
            slider:SetScript("OnValueChanged", function(_, value)
                saveOption(spec, value)
                label:SetText(spec.label .. ": " .. string.format(spec.format, value))
            end)
            refreshers[#refreshers + 1] = function()
                slider:SetValue(spec.get())
                label:SetText(spec.label .. ": " .. string.format(spec.format, spec.get()))
            end
        end
    end
    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    return panel
end

-- Backs SabotonTextInputControlTemplate (src\Options.xml): an inline text-input row for the
-- vertical Settings list, since that API has no built-in free-text control of its own.
-- Defined only where the Settings API exists; on Forever the template never loads either.
if settingsAvailable then
    SabotonTextInputControlMixin = CreateFromMixins(SettingsControlMixin)

    function SabotonTextInputControlMixin:OnLoad()
        SettingsControlMixin.OnLoad(self)

        self.EditBox:SetScript("OnEnterPressed", function(editBox)
            self:GetSetting():SetValue(editBox:GetText())
            editBox:ClearFocus()
        end)
        self.EditBox:SetScript("OnEscapePressed", function(editBox)
            editBox:SetText(self:GetSetting():GetValue())
            editBox:ClearFocus()
        end)
    end

    function SabotonTextInputControlMixin:Init(initializer)
        SettingsControlMixin.Init(self, initializer)
        self.EditBox:SetText(self:GetSetting():GetValue())
    end

    function SabotonTextInputControlMixin:SetValue(value)
        self.EditBox:SetText(value)
    end
end

local function createTextInput(subcategory, moduleKey, spec)
    local setting = Settings.RegisterProxySetting(
        subcategory,
        toVariableKey(moduleKey, spec.key),
        Settings.VarType.String,
        spec.label,
        spec.default,
        spec.get,
        function(value) saveOption(spec, value) end
    )

    local data = Settings.CreateSettingInitializerData(setting, nil, spec.tooltip)
    local initializer = Settings.CreateElementInitializer("SabotonTextInputControlTemplate", data)
    Settings.RegisterInitializer(subcategory, initializer)
end

optionBuilders.text = createTextInput

local function buildModulePanel(rootCategory, moduleKey, schema)
    local subcategory = Settings.RegisterVerticalLayoutSubcategory(rootCategory, schema.name or moduleKey)

    for _, optionSpec in ipairs(schema.options or {}) do
        local build = optionBuilders[optionSpec.type]
        if build then
            build(subcategory, moduleKey, optionSpec)
        end
    end
end

function Options:OnEnable()
    if not settingsAvailable then
        return
    end

    local rootCategory = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

    -- Modules opt in by implementing GetOptionsSchema(); Options never reaches into module internals.
    for moduleKey, module in pairs(addon.modules) do
        if module.GetOptionsSchema then
            buildModulePanel(rootCategory, moduleKey, module:GetOptionsSchema())
        end
    end

    Settings.RegisterAddOnCategory(rootCategory)
    self.category = rootCategory
end

function Options:HandleCommand()
    if not settingsAvailable then
        self.fallbackPanel = self.fallbackPanel or createFallbackPanel()
        if self.fallbackPanel:IsShown() then self.fallbackPanel:Hide() else self.fallbackPanel:Show() end
        return
    end
    if not self.category then
        addon.Print("Options panel is unavailable; use /saboton <module> <command> instead.")
        return
    end

    Settings.OpenToCategory(self.category:GetID())
end

addon.RegisterModule("options", Options)
