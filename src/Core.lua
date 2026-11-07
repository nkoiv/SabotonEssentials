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
end

SLASH_SABOTON1 = "/saboton"
SlashCmdList.SABOTON = dispatch

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, _, loadedAddonName)
    if loadedAddonName ~= ADDON_NAME then
        return
    end

    for _, module in pairs(addon.modules) do
        if module.OnEnable then
            module:OnEnable()
        end
    end

    addon.Print("Loaded. Use /saboton help for details.")
    initFrame:UnregisterEvent("ADDON_LOADED")
end)
