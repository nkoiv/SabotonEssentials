local frames, module, canvas, opened, saves
local enabled, notifications, sharing, running, syncs, cancels, suppressed, removals, includedSuspected
local function noop() end
UIParent = {}
SettingsControlMixin = {}
function CreateFromMixins() return {} end

function CreateFrame(kind, _, parent)
    local frame = { kind = kind, parent = parent, scripts = {}, enabled = true }
    for _, method in ipairs({ "SetSize", "SetPoint", "SetFrameStrata", "SetClampedToScreen",
        "SetBackdrop", "EnableMouse", "SetHitRectInsets" }) do frame[method] = noop end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:SetText(text) self.text = text end
    function frame:SetEnabled(value) self.enabled = not not value end
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked end
    function frame:IsShown() return self.shown end
    function frame:Hide() self.shown = false end
    function frame:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    function frame:CreateFontString()
        local text = {}
        for _, method in ipairs({ "SetPoint", "SetWidth", "SetHeight", "SetJustifyH", "SetJustifyV" }) do text[method] = noop end
        function text:SetText(value) self.text = value end
        return text
    end
    frames[#frames + 1] = frame
    return frame
end

local function run(modern)
    frames, module, canvas, opened, saves = {}, nil, nil, nil, 0
    enabled, notifications, running, syncs, cancels = true, true, false, 0, 0
    sharing = false
    removals = 0
    includedSuspected = false
    suppressed = {}
    for index = 1, 6 do suppressed[index] = { key = "P\tName" .. index, label = "Player: Name" .. index } end
    local schema = {
        name = "Spy Enhancement",
        options = {
            { type = "checkbox", key = "networkSyncEnabled", label = "Enable guild sync", tooltip = "Send and receive", default = true,
                get = function() return enabled end, set = function(value) enabled = value end },
            { type = "checkbox", key = "showSyncNotifications", label = "Completion notices", default = true,
                get = function() return notifications end, set = function(value) notifications = value end },
            { type = "checkbox", key = "shareKOSReasons", label = "Share KoS reasons", default = false,
                get = function() return sharing end, set = function(value) sharing = value end },
        },
        dashboard = {
            description = "Names only.",
            view = function(includeSuspected)
                return { status = running and "exchanging" or "idle", summary = "Lists: 1 / 2", progress = "Waiting",
                    canSync = enabled and not running, canCancel = running, suspectedImports = 2,
                    canRemoveImports = removals == 0 or includeSuspected }
            end,
            suppressed = function() return suppressed end,
            sync = function() syncs = syncs + 1 running = true end,
            cancel = function() cancels = cancels + 1 running = false end,
            removeImports = function(includeSuspected)
                removals = removals + 1 running = false includedSuspected = includeSuspected
            end,
            allow = function(key)
                for index, entry in ipairs(suppressed) do
                    if entry.key == key then table.remove(suppressed, index) saves = saves + 1 return true end
                end
            end,
            allowAll = function()
                local count = #suppressed
                suppressed = {}
                if count > 0 then saves = saves + 1 end
                return count > 0, count
            end,
        },
    }
    if modern then
        local function category() return { GetID = function() return 42 end } end
        Settings = {
            VarType = { Boolean = 1 }, RegisterVerticalLayoutCategory = category,
            RegisterCanvasLayoutSubcategory = function(_, panel) canvas = panel return category() end,
            RegisterProxySetting = noop, RegisterAddOnCategory = noop,
            OpenToCategory = function(id) opened = id end,
        }
    else Settings = nil end
    local addon = {
        modules = { spyenhancement = { GetOptionsSchema = function() return schema end } },
        SaveSettings = function() saves = saves + 1 end,
        RegisterModule = function(_, value) module = value end,
        Print = function(message) error(message) end,
    }
    if not modern then
        addon.modules.extraattack = { GetOptionsSchema = function() return { options = {} } end }
    end
    assert(loadfile("src/Options.lua"))("SabotonEssentials", addon)
    module:OnEnable()
    if modern then module:HandleCommand("spyenhancement")
    else
        module:HandleCommand()
        local launch
        for _, frame in ipairs(frames) do
            if frame.text == "Spy Enhancement: sync and options" then launch = frame end
        end
        assert(launch, "shared fallback options must expose the Spy dashboard")
        launch.scripts.OnClick()
    end
    local panel
    if modern then
        assert(opened == 42)
        panel = canvas
        panel:Show()
    else
        assert(module.spyWindow:IsShown())
        panel = module.spyWindow.dashboard
    end
    assert(panel.sync.enabled and not panel.cancel.enabled)
    assert(not panel.includeSuspected:GetChecked(), "legacy cleanup must default off")
    assert(panel.includeSuspected.text.text == "Include suspected old imports (2 candidates)")
    assert(panel.checkboxes[1].control.checked and panel.checkboxes[2].control.checked)
    assert(not panel.checkboxes[3].control.checked, "reason sharing must default off")
    assert(panel.allowAll.enabled, "bulk allow must be enabled while suppressed names exist")
    assert(panel.rows[1].key == "P\tName1" and panel.rows[4].key == "P\tName4")
    assert(panel.next.enabled and not panel.previous.enabled)
    panel.next.scripts.OnClick()
    assert(panel.page == 2 and panel.rows[1].key == "P\tName5" and not panel.rows[3].allow.shown)
    panel.rows[1].allow.scripts.OnClick()
    panel.rows[1].allow.scripts.OnClick()
    assert(#suppressed == 4 and panel.page == 1, "allow must refresh/clamp the last page")
    assert(saves == 2)
    panel.allowAll.scripts.OnClick()
    assert(#suppressed == 0 and not panel.allowAll.enabled and saves == 3,
        "bulk allow must clear all suppressed names and save once")
    local check = panel.checkboxes[1].control
    check.checked = false
    check.scripts.OnClick(check)
    assert(not enabled and not panel.sync.enabled and saves == 4)
    enabled = true
    panel.scripts.OnUpdate(panel, 1)
    panel.sync.scripts.OnClick()
    assert(syncs == 1 and not panel.sync.enabled and panel.cancel.enabled)
    panel.cancel.scripts.OnClick()
    assert(cancels == 1 and panel.sync.enabled and not panel.cancel.enabled)
    notifications = false
    panel.scripts.OnUpdate(panel, 1)
    assert(not panel.checkboxes[2].control.checked, "external setting change must refresh")
    local share = panel.checkboxes[3].control
    share.checked = true
    share.scripts.OnClick(share)
    assert(sharing and saves == 5, "reason-sharing control must save in modern and fallback UI")
    suppressed = { { key = "G\tUnsafe", label = "Guild: |Hlink|hName|h" } }
    panel:Refresh()
    assert(panel.rows[1].text.text == "Guild: ||Hlink||hName||h", "external names must not inject UI markup")
    assert(panel.allowAll.enabled, "bulk allow must refresh for newly suppressed names")
    suppressed = {}
    panel:Refresh()
    assert(panel.pageLabel.text == "No suppressed imports." and not panel.rows[1].allow.shown
        and not panel.allowAll.enabled)
    assert(panel.removeImports.enabled)
    panel.removeImports.scripts.OnClick()
    assert(removals == 1 and not panel.removeImports.enabled,
        "remove-imports button must execute and refresh in both dashboards")
    assert(not includedSuspected, "default cleanup must not include heuristic candidates")
    panel.includeSuspected:SetChecked(true)
    panel.includeSuspected.scripts.OnClick()
    assert(panel.removeImports.enabled, "opt-in must enable candidate-only cleanup")
    panel.removeImports.scripts.OnClick()
    assert(includedSuspected and removals == 2 and not panel.includeSuspected:GetChecked()
        and not panel.removeImports.enabled, "opt-in must apply once and reset")
    panel.includeSuspected:SetChecked(true)
    panel:Hide()
    panel:Show()
    assert(not panel.includeSuspected:GetChecked(), "reopening the dashboard must reset destructive opt-in")
    if not modern then
        module:HandleCommand("spyenhancement")
        assert(not module.spyWindow:IsShown())
        module:HandleCommand("spyenhancement")
        assert(module.spyWindow:IsShown())
    end
end

run(false)
run(true)
print("Spy options modern/fallback UI tests passed")
