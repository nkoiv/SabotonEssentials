local function noop() end
local addon = { modules = {}, SaveSettings = noop, Print = function(message) error(message) end }
function addon.RegisterModule(key, module) addon.modules[key] = module end
LOCALIZED_CLASS_NAMES_MALE = {}
for _, name in ipairs({ "ExtraAttack", "GatheringTimer", "TankTarget", "SqueakyToy", "SpyEnhancement", "MinimapButton" }) do
    assert(loadfile("src/Modules/" .. name .. ".lua"))("SabotonEssentials", addon)
end

local schemas, values, controls, categories, categoryOrder = {}, {}, {}, {}, {}
local writes = 0
for key, module in pairs(addon.modules) do
    local schema = module:GetOptionsSchema()
    schemas[key], values[key] = schema, {}
    for _, spec in ipairs(schema.options) do
        local optionKey = spec.key
        values[key][optionKey] = spec.get()
        spec.get = function() return values[key][optionKey] end
        spec.set = function(value) writes = writes + 1 values[key][optionKey] = value end
    end
    module.GetOptionsSchema = function() return schema end
end

local function initializer(template, data)
    local item = { template = template, data = data, predicates = {}, watched = {} }
    function item:AddModifyPredicate(predicate) table.insert(self.predicates, predicate) end
    function item:AddEvaluateStateCVar(key) self.watched[key] = true end
    function item:IsEnabled()
        for _, predicate in ipairs(self.predicates) do if not predicate() then return false end end
        return true
    end
    return item
end
local function register(category, item)
    table.insert(category.rows, item)
    if item.data.setting then controls[item.data.setting.key] = item end
    return item
end
Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function() return { rows = {} } end,
    RegisterVerticalLayoutSubcategory = function(_, name)
        local category = { name = name, rows = {} }
        categories[name] = category
        categoryOrder[#categoryOrder + 1] = name
        return category
    end,
    RegisterAddOnCategory = noop,
    RegisterProxySetting = function(_, key, kind, _, default, get, set)
        return { key = key, kind = kind, default = default, get = get, set = set }
    end,
    CreateElementInitializer = initializer,
    RegisterInitializer = register,
    CreateCheckbox = function(category, setting)
        return register(category, initializer("checkbox", { setting = setting }))
    end,
    CreateSlider = function(category, setting)
        return register(category, initializer("slider", { setting = setting }))
    end,
    CreateDropdown = function(category, setting)
        return register(category, initializer("dropdown", { setting = setting }))
    end,
    CreateSliderOptions = function() return { SetLabelFormatter = noop } end,
    CreateSettingInitializerData = function(setting) return { setting = setting } end,
}
function CreateSettingsButtonInitializer(_, text, callback)
    return initializer("button", { buttonText = text, buttonClick = callback })
end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
SettingsControlMixin = { EvaluateState = noop }
function CreateFromMixins() return {} end
assert(loadfile("src/Options.lua"))("SabotonEssentials", addon)
addon.modules.options:OnEnable()
assert(writes == 0, "building the UI must not change any saved preferences")
assert(table.concat(categoryOrder, ",") == "Extra Attack,Gathering Timer,Minimap Button,Spy Enhancement,Squeaky Toy,Tank Target",
    "module categories must have a stable order")
for key, schema in pairs(schemas) do
    local section, seen, count = nil, {}, 0
    for _, row in ipairs(categories[schema.name].rows) do
        if row.template == "SettingsListSectionHeaderTemplate" then
            section = row.data.name
            assert(not seen[section], "sections must be contiguous, not repeated")
            seen[section] = true
        elseif row.data.setting then
            count = count + 1
            local spec
            for _, candidate in ipairs(schema.options) do
                if row.data.setting.key == "SABOTONESSENTIALS_" .. key:upper() .. "_" .. candidate.key:upper() then spec = candidate end
            end
            assert(spec and spec.section == section, "every option must appear under its own section")
        end
    end
    assert(count == #schema.options, "each saved option must appear exactly once")
end
local function control(module, key)
    return assert(controls["SABOTONESSENTIALS_" .. module:upper() .. "_" .. key:upper()])
end
local function checkDependency(module, childKey, parentKey)
    local child = control(module, childKey)
    assert(child.watched["SABOTONESSENTIALS_" .. module:upper() .. "_" .. parentKey:upper()],
        "dependent controls must refresh when their proxy parent changes")
    values[module][parentKey] = true
    assert(child:IsEnabled())
    local saved = values[module][childKey]
    values[module][parentKey] = false
    assert(not child:IsEnabled())
    assert(values[module][childKey] == saved, "disabling a control must preserve its value")
    values[module][parentKey] = true
end
checkDependency("extraattack", "comboTextFormat", "textEnabled")
checkDependency("extraattack", "soundKey", "soundEnabled")
checkDependency("extraattack", "textOffsetX", "enabled")
checkDependency("tanktarget", "allThreat", "showThreat")
checkDependency("tanktarget", "threatLow", "showThreat")
checkDependency("tanktarget", "markSize", "enabled")
values.gather.enabled = true
checkDependency("gather", "minDuration", "minTimer")
checkDependency("gather", "maxSound", "maxTimer")
checkDependency("gather", "width", "enabled")
checkDependency("squeak", "triggerClass", "friendlyMages")
checkDependency("spyenhancement", "shareKOSReasons", "networkSyncEnabled")
values.extraattack.enabled, values.extraattack.textEnabled = false, true
assert(not control("extraattack", "comboTextFormat"):IsEnabled(), "master off must also disable nested controls")
local spy = categories["Spy Enhancement"].rows
assert(#spy == 5 and spy[5].data.buttonText == "Manage guild sync...",
    "Spy uses one native section, three preferences, and one management launcher")
local textControl = { EditBox = { SetEnabled = function(self, enabled) self.enabled = enabled end } }
function textControl:IsEnabled() return false end
function textControl:DisplayEnabled(enabled) self.labelEnabled = enabled end
SabotonTextInputControlMixin.EvaluateState(textControl)
assert(textControl.EditBox.enabled == false and textControl.labelEnabled == false,
    "disabled text controls must disable the actual edit box as well as its label")
assert(writes == 0)
print("Shared options layout and dependency tests passed")
