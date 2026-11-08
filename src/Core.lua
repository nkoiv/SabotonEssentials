local ADDON_NAME, addon = ...

-- Shared namespace/registry so feature modules (see src/Modules/) stay in their own files.
addon.modules = {}

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSaboton Essentials|r: " .. message)
end

-- Modules call this at file scope to register themselves before ADDON_LOADED fires.
function addon.RegisterModule(name, module)
    addon.modules[name] = module
end

local persistenceReady = false
local applyingSettings = false

function addon.SaveSettings()
    if not persistenceReady or applyingSettings then return end
    local data = { version = 1, modules = {} }
    for name, module in pairs(addon.modules) do
        if module.GetOptionsSchema then
            local values = {}
            for _, spec in ipairs(module:GetOptionsSchema().options or {}) do
                if spec.get and spec.key then values[spec.key] = spec.get() end
            end
            data.modules[name] = values
        end
        if module.GetPersistentState then
            data.modules[name] = data.modules[name] or {}
            data.modules[name].state = module:GetPersistentState()
        end
    end
    SabotonEssentialsDB = data
end

function addon.ApplySettings(data)
    data = type(data) == "table" and data or {}
    applyingSettings = true
    local modules = type(data.modules) == "table" and data.modules or {}
    for name, module in pairs(addon.modules) do
        local values = modules[name]
        if type(values) == "table" then
            if module.LoadPersistentState then module:LoadPersistentState(values.state) end
            if module.GetOptionsSchema then
                for _, spec in ipairs(module:GetOptionsSchema().options or {}) do
                    local value = values[spec.key]
                    local expected = spec.type == "checkbox" and "boolean" or spec.type == "slider" and "number" or "string"
                    if spec.set and type(value) == expected and (expected ~= "number" or (value == value and math.abs(value) < math.huge)) then spec.set(value) end
                end
            end
            if module.FinishRestore then module:FinishRestore(values.state) end
        end
    end
    applyingSettings = false
    persistenceReady = true
end

local function printHelp()
    addon.Print("Commands: /saboton <module> <command>")
    for name in pairs(addon.modules) do
        addon.Print("  " .. name)
    end
end

local function dispatch(message)
    local moduleName, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    moduleName = string.lower(moduleName or "")

    if moduleName == "" or moduleName == "help" then
        printHelp()
        return
    end

    local module = addon.modules[moduleName]
    if not module then
        addon.Print("Unknown module: " .. moduleName)
        printHelp()
        return
    end

    module:HandleCommand(rest)
    addon.SaveSettings()
end

SLASH_SABOTON1 = "/saboton"
SlashCmdList.SABOTON = dispatch

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, _, loadedAddonName)
    if loadedAddonName ~= ADDON_NAME then
        return
    end

    for name, module in pairs(addon.modules) do
        if name ~= "options" and module.OnEnable then
            module:OnEnable()
        end
    end
    addon.ApplySettings(SabotonEssentialsDB)
    if addon.modules.options and addon.modules.options.OnEnable then
        addon.modules.options:OnEnable()
    end

    addon.Print("Loaded. Use /saboton help for details.")
    if GetBuildInfo and select(4, GetBuildInfo()) == 16001 then
        addon.Print("Warning: Forever may not reload SavedVariables after relog; settings persistence is not guaranteed. No macro mirror is available.")
    end
    initFrame:UnregisterEvent("ADDON_LOADED")
end)
