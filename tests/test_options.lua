local function noop() end
local addon = { modules = {}, SaveSettings = noop, Print = function(message) error(message) end }
function addon.RegisterModule(key, module) addon.modules[key] = module end
assert(loadfile("src/Support/Spells.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/TimerBars.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/PartyCooldowns.lua"))("SabotonEssentials", addon)
assert(loadfile("src/Support/CooldownSync.lua"))("SabotonEssentials", addon)
C_Spell = { GetSpellName = function(id) return tostring(id) end }
LOCALIZED_CLASS_NAMES_MALE = {}
for _, name in ipairs({ "ChatTabs", "ExtraAttack", "GatheringTimer", "MobTimer", "PartyCooldownTracker", "TankTarget", "TankHelper", "SqueakyToy", "SpyEnhancement", "MinimapButton", "WowheadLink" }) do
    assert(loadfile("src/Modules/" .. name .. ".lua"))("SabotonEssentials", addon)
end

local schemas, values, controls, categories, categoryOrder = {}, {}, {}, {}, {}
local rootCategory = { rows = {} }
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
    RegisterVerticalLayoutCategory = function() return rootCategory end,
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
    CreateSlider = function(category, setting, sliderOptions)
        return register(category, initializer("slider", { setting = setting, sliderOptions = sliderOptions }))
    end,
    CreateDropdown = function(category, setting)
        return register(category, initializer("dropdown", { setting = setting }))
    end,
    CreateSliderOptions = function()
        return { SetLabelFormatter = function(self, _, formatter) self.formatter = formatter end }
    end,
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
assert(table.concat(categoryOrder, ",") == "Chat Tabs,Extra Attack,Gathering Timer,Mob Spawn Timer,Party Cooldowns (beta),Spy Enhancement,Squeaky Toy,Miss Alerts,Tank Target",
    "module categories must have a stable order")
assert(not categories["Minimap Button"] and not categories["Wowhead Creature Link"])
assert(#rootCategory.rows == 2, "general settings belong on the root category")
assert(controls.SABOTONESSENTIALS_PARTYCOOLDOWNS_ENABLED.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_PARTYCOOLDOWNS_SHARING.data.setting.default == true)
assert(controls.SABOTONESSENTIALS_MINIMAP_SHOWBUTTON.data.setting.default == true)
assert(controls.SABOTONESSENTIALS_WOWHEAD_MENUENABLED.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_CHATTABS_ENABLED.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_CHATTABS_HIDEINPUT.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_CHATTABS_HIDEBUTTONS.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_CHATTABS_FONT.data.setting.default == "default")
assert(controls.SABOTONESSENTIALS_CHATTABS_CUSTOMFONTSIZE.data.setting.default == false)
assert(controls.SABOTONESSENTIALS_CHATTABS_FONTSIZE.data.setting.default == 12)
assert(#categories["Chat Tabs"].rows == 6, "chat tab options belong on their own settings page")
controls.SABOTONESSENTIALS_MINIMAP_SHOWBUTTON.data.setting.set(false)
controls.SABOTONESSENTIALS_WOWHEAD_MENUENABLED.data.setting.set(true)
controls.SABOTONESSENTIALS_CHATTABS_ENABLED.data.setting.set(true)
assert(not values.minimap.showButton and values.wowhead.menuEnabled and values.chattabs.enabled)
local foundMobAction = false
for _, row in ipairs(categories["Mob Spawn Timer"].rows) do
    if row.template == "button" and row.data.buttonText == "Manage mobs..." then foundMobAction = true end
end
assert(foundMobAction, "mob management must be reachable in native settings")
local foundSpellAction = false
for _, row in ipairs(categories["Miss Alerts"].rows) do
    if row.template == "button" and row.data.buttonText == "Manage spells..." then foundSpellAction = true end
end
assert(foundSpellAction, "spell management must be reachable in native settings")
assert(not controls["SABOTONESSENTIALS_TANKHELPER_SPELLLIST"], "raw IDs must not be shown in settings")
for key, schema in pairs(schemas) do
    local section, seen, count = nil, {}, 0
    for _, row in ipairs(schema.root and {} or categories[schema.name].rows) do
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
    local visible = 0
    for _, spec in ipairs(schema.options) do if not spec.hidden then visible = visible + 1 end end
    if not schema.root then assert(count == visible, "each visible option must appear exactly once") end
end
local function control(module, key)
    return assert(controls["SABOTONESSENTIALS_" .. module:upper() .. "_" .. key:upper()])
end
assert(control("tankhelper", "fightWindow").data.sliderOptions.formatter(120) == "Unlimited")
assert(control("tankhelper", "fightWindow").data.sliderOptions.formatter(119) == "119s")
assert(control("extraattack", "comboWindow").data.sliderOptions.formatter(1) == "1.0s")
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
checkDependency("tankhelper", "soundKey", "soundEnabled")
checkDependency("tankhelper", "textArcDuration", "textEnabled")
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
checkDependency("chattabs", "fontSize", "customFontSize")
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
assert(writes == 3, "explicit root-setting changes may write preferences")
print("Shared options layout and dependency tests passed")
