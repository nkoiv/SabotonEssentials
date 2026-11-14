local ADDON_NAME, addon = ...

-- Builds one Settings panel from declarative option schemas exposed by other modules
-- (see each module's GetOptionsSchema), keeping all Settings-API/UI code out of them.
--
-- Without Settings, retain the offset sliders and expose module dashboards in fallback windows.
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

local function registerCheckbox(subcategory, moduleKey, spec)
    return Settings.RegisterProxySetting(
        subcategory,
        toVariableKey(moduleKey, spec.key),
        Settings.VarType.Boolean,
        spec.label,
        spec.default or false,
        spec.get,
        function(value) saveOption(spec, value) end
    )
end

local function createCheckbox(subcategory, moduleKey, spec)
    Settings.CreateCheckbox(subcategory, registerCheckbox(subcategory, moduleKey, spec), spec.tooltip)
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

local function displayText(value)
    return tostring(value):gsub("|", "||")
end

local function tooltip(control, text)
    control:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function createDashboard(parent, schema)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(540, 626)
    local dashboard = schema.dashboard
    local function label(text, y, height, font)
        local item = panel:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        item:SetPoint("TOPLEFT", 12, y)
        item:SetWidth(510)
        item:SetHeight(height)
        item:SetJustifyH("LEFT")
        item:SetJustifyV("TOP")
        item:SetText(text)
        return item
    end
    label(schema.name, -12, 24, "GameFontNormalLarge")
    label(dashboard.description, -42, 62)
    panel.checkboxes = {}
    for index, spec in ipairs(schema.options or {}) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", 10, -108 - (index - 1) * 28)
        local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(spec.label)
        check:SetHitRectInsets(0, -330, 0, 0)
        tooltip(check, spec.tooltip or spec.label)
        check:SetScript("OnClick", function(self)
            saveOption(spec, self:GetChecked() == true)
            panel:Refresh()
        end)
        panel.checkboxes[index] = { control = check, spec = spec }
    end
    local function button(text, x, y, width, callback)
        local control = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        control:SetSize(width, 24)
        control:SetPoint("TOPLEFT", x, y)
        control:SetText(text)
        control:SetScript("OnClick", callback)
        return control
    end
    panel.sync = button("Sync Now", 12, -192, 120, function() dashboard.sync() panel:Refresh() end)
    panel.cancel = button("Cancel", 142, -192, 100, function() dashboard.cancel() panel:Refresh() end)
    panel.removeImports = button("Remove imported KoS", 252, -192, 180, function()
        dashboard.removeImports(panel.includeSuspected:GetChecked() == true)
        panel.includeSuspected:SetChecked(false)
        panel:Refresh()
    end)
    panel.includeSuspected = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.includeSuspected:SetSize(26, 26)
    panel.includeSuspected:SetPoint("TOPLEFT", 10, -220)
    panel.includeSuspected:SetHitRectInsets(0, -460, 0, 0)
    panel.includeSuspected.text = panel.includeSuspected:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.includeSuspected.text:SetPoint("LEFT", panel.includeSuspected, "RIGHT", 4, 0)
    panel.includeSuspected:SetScript("OnClick", function() panel:Refresh() end)
    tooltip(panel.includeSuspected, "One cleanup only; off by default. Also removes untracked KoS names with no zone, level, or class. These may be locally added players, not imports. Explicit local adds observed by this addon are excluded. Review Spy's list first; removal also applies Spy's cross-character rules.")
    label("Warning: suspected entries may be local. Review Spy before removal.", -249, 22, "GameFontNormal")
    tooltip(panel.sync, "Reconcile names and optionally shared KoS reasons with v4 guild peers. Existing receiver reasons win. Combat/chat restrictions queue the work.")
    tooltip(panel.cancel, "Cancel local pending work. Names already imported remain in Spy.")
    tooltip(panel.removeImports, "Remove tracked guild-imported KoS players from Spy, cancel pending sync, and suppress their return. Optionally includes suspected old imports when checked below; those can be local players. Watched guilds are kept. Spy's cross-character KoS removal rules still apply.")
    panel.status = label("", -284, 44, "GameFontNormal")
    panel.summary = label("", -331, 40)
    panel.progress = label("", -376, 44)
    label("Removed imports (kept out of future syncs)", -430, 22, "GameFontNormal")
    panel.allowAll = button("Allow all", 400, -426, 112, function()
        dashboard.allowAll()
        panel:Refresh()
    end)
    tooltip(panel.allowAll, "Permit all suppressed player and guild names to be imported on the next sync. This does not immediately add them to Spy.")
    panel.rows = {}
    for index = 1, 4 do
        local row = {}
        row.text = label("", -457 - (index - 1) * 28, 24)
        row.text:SetWidth(370)
        row.allow = button("Allow again", 400, -453 - (index - 1) * 28, 112, function()
            if row.key then dashboard.allow(row.key) panel:Refresh() end
        end)
        tooltip(row.allow, "Permit this name to be imported on the next sync. This does not immediately add it to Spy.")
        panel.rows[index] = row
    end
    panel.page, panel.pages = 1, 1
    panel.previous = button("Previous", 12, -574, 100, function()
        panel.page = math.max(1, panel.page - 1)
        panel:Refresh()
    end)
    panel.next = button("Next", 122, -574, 100, function()
        panel.page = math.min(panel.pages, panel.page + 1)
        panel:Refresh()
    end)
    panel.pageLabel = label("", -604, 22)
    function panel:Refresh()
        local view = dashboard.view(self.includeSuspected:GetChecked() == true)
        self.includeSuspected.text:SetText(string.format("Include suspected old imports (%d candidates)", view.suspectedImports or 0))
        for _, entry in ipairs(self.checkboxes) do entry.control:SetChecked(entry.spec.get()) end
        self.sync:SetEnabled(view.canSync)
        self.cancel:SetEnabled(view.canCancel)
        self.removeImports:SetEnabled(view.canRemoveImports)
        self.status:SetText(displayText("Status: " .. view.status))
        self.summary:SetText(displayText(view.summary))
        self.progress:SetText(displayText(view.progress))
        local entries = dashboard.suppressed()
        self.allowAll:SetEnabled(#entries > 0)
        self.pages = math.max(1, math.ceil(#entries / #self.rows))
        self.page = math.min(self.page, self.pages)
        for index, row in ipairs(self.rows) do
            local entry = entries[(self.page - 1) * #self.rows + index]
            row.key = entry and entry.key
            row.text:SetText(entry and displayText(entry.label) or "")
            row.allow:SetShown(entry ~= nil)
        end
        self.previous:SetEnabled(self.page > 1)
        self.next:SetEnabled(self.page < self.pages)
        self.pageLabel:SetText(#entries == 0 and "No suppressed imports."
            or string.format("Page %d / %d (%d names)", self.page, self.pages, #entries))
    end
    panel:SetScript("OnShow", function(self)
        self.elapsed = 0
        self.includeSuspected:SetChecked(false)
        self:Refresh()
    end)
    panel:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
    end)
    return panel
end

local function createDashboardWindow(schema)
    local window = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window:SetSize(570, 666)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    window:EnableMouse(true)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local dashboard = createDashboard(window, schema)
    dashboard:SetPoint("TOPLEFT", 12, -22)
    window.dashboard = dashboard
    window:Hide()
    window:SetScript("OnShow", function() dashboard:Refresh() end)
    return window
end

local function createFallbackPanel()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(360, addon.modules.spyenhancement and 335 or 290)
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
    if addon.modules.spyenhancement then
        local spy = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        spy:SetSize(290, 24)
        spy:SetPoint("BOTTOM", 0, 24)
        spy:SetText("Spy Enhancement: sync and options")
        spy:SetScript("OnClick", function() Options:HandleCommand("spyenhancement") end)
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
    if schema.dashboard and Settings.RegisterCanvasLayoutSubcategory then
        local panel = createDashboard(UIParent, schema)
        panel:Hide()
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(rootCategory, panel, schema.name)
        for _, spec in ipairs(schema.options or {}) do
            if spec.type == "checkbox" then registerCheckbox(subcategory, moduleKey, spec) end
        end
        Options.moduleCategories = Options.moduleCategories or {}
        Options.moduleCategories[moduleKey] = subcategory
        return
    end
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

function Options:HandleCommand(message)
    if message == "spyenhancement" then
        local category = self.moduleCategories and self.moduleCategories.spyenhancement
        if category then Settings.OpenToCategory(category:GetID()) return end
        local module = addon.modules.spyenhancement
        if not module then addon.Print("Spy Enhancement options are unavailable.") return end
        self.spyWindow = self.spyWindow or createDashboardWindow(module:GetOptionsSchema())
        if self.spyWindow:IsShown() then self.spyWindow:Hide() else self.spyWindow:Show() end
        return
    end
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
