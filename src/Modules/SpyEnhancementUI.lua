-- SpyEnhancementUI module: UI and Spy integration for SpyEnhancement
-- Provides main window, status panel, minimap button, and Spy addon hooks

local ADDON_NAME, addon = ...
local SpyEnhancementUI = {}

-- UI state
local mainWindow = nil
local miniButton = nil
local spyAvailable = false
local spyModule = nil

local function getSpyEnhancementDB()
    local database = SabotonEssentialsDB
    if type(database) ~= "table" then return nil end

    local modules = database.modules
    local moduleSettings = type(modules) == "table" and modules.spyenhancement
    local state = type(moduleSettings) == "table" and moduleSettings.state
    if type(state) == "table" and type(state.data) == "table" then
        return state.data
    end
    return database.spyenhancement
end

-- ============================================================================
-- UTILITY: FORMAT AND DISPLAY
-- ============================================================================

local function formatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then return "never" end
    local diff = time() - timestamp
    if diff < 60 then return "just now" end
    if diff < 3600 then return string.format("%dm ago", diff / 60) end
    if diff < 86400 then return string.format("%dh ago", diff / 3600) end
    return string.format("%dd ago", diff / 86400)
end

local function getNationalityEmoji(nationality)
    if nationality == "russian" then return "🇷🇺" end
    if nationality == "ukrainian" then return "🇺🇦" end
    return "❓"
end

-- ============================================================================
-- SPY ADDON INTEGRATION
-- ============================================================================

local function initializeSpyIntegration()
    if not _G.Spy then return false end
    
    spyAvailable = true
    spyModule = _G.Spy
    
    -- Register our module with Spy's options
    if spyModule.RegisterModuleOptions then
        spyModule:RegisterModuleOptions("SpyEnhancement", {
            name = "Spy Enhancement",
            desc = "KoS sync, guild tagging, and nationality detection",
        })
    end
    
    -- Hook into Spy's player info display if available
    if spyModule.RegisterInfoHook then
        spyModule:RegisterInfoHook("SpyEnhancement", function(playerName, realm)
            return getSpyPlayerInfo(playerName, realm)
        end)
    end
    
    addon.Print("SpyEnhancement: Spy addon integration active")
    return true
end

-- Get info to display in Spy for a player
local function getSpyPlayerInfo(playerName, realm)
    realm = realm or GetRealmName()
    local spyenhancement = getSpyEnhancementDB()
    if not spyenhancement then return nil end
    
    local infoLines = {}
    local key = string.lower(playerName .. "-" .. realm)
    
    -- Check if in personal KoS
    if spyenhancement.kosPersonal and spyenhancement.kosPersonal[key] then
        local entry = spyenhancement.kosPersonal[key]
        table.insert(infoLines, "|cffff0000[Personal KoS]|r")
        if entry.notes and entry.notes ~= "" then
            table.insert(infoLines, "Note: " .. entry.notes)
        end
    end
    
    -- Check if in synced KoS
    if spyenhancement.kosSynced and spyenhancement.kosSynced[key] then
        local entry = spyenhancement.kosSynced[key]
        table.insert(infoLines, string.format("|cffff9900[Synced from %s]|r", entry.syncFrom or "guild"))
        if entry.notes and entry.notes ~= "" then
            table.insert(infoLines, "Note: " .. entry.notes)
        end
    end
    
    -- Check guild status
    if spyenhancement.hosileGuilds then
        -- Try to find player's guild from members list
        for guildName, members in pairs(spyenhancement.guildMembers or {}) do
            if members[key] then
                local guildEntry = spyenhancement.hosileGuilds[string.lower(guildName)]
                if guildEntry then
                    table.insert(infoLines, string.format("|cffcc0000[Hostile Guild: %s]|r", guildName))
                    break
                end
            end
        end
    end
    
    -- Show Cyrillic detection
    if spyenhancement.cyrillicCache and spyenhancement.cyrillicCache[key] then
        local nationality = spyenhancement.cyrillicCache[key]
        table.insert(infoLines, string.format("Nationality: %s %s", getNationalityEmoji(nationality), nationality))
    end
    
    return infoLines and #infoLines > 0 and table.concat(infoLines, "\n") or nil
end

-- ============================================================================
-- MAIN WINDOW UI
-- ============================================================================

local function createMainWindow()
    if mainWindow then return mainWindow end
    
    local frame = CreateFrame("Frame", "SpyEnhancementMainWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    frame.title = frame:GetTitle()
    frame.title:SetText("SpyEnhancement")
    
    -- Create scrollable content area
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetSize(550, 400)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    
    -- Footer with action buttons
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 25)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 25)
    refreshBtn:SetPoint("BOTTOMRIGHT", closeBtn, "BOTTOMLEFT", -5, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() updateMainWindowContent(editBox) end)
    
    frame.editBox = editBox
    frame:Hide()
    
    mainWindow = frame
    return frame
end

local function updateMainWindowContent(editBox)
    if not editBox then return end
    
    local db = getSpyEnhancementDB() or {}
    local lines = {}
    
    table.insert(lines, "=== SPYENHANCEMENT STATUS ===\n")
    
    -- Connection status
    table.insert(lines, "\n[NETWORK STATUS]")
    local syncState = db.syncState or {}
    local lastSync = formatTimestamp(syncState.lastSyncTime)
    local syncCount = table.getn(syncState.syncedWith or {})
    table.insert(lines, string.format("Last Broadcast: %s", lastSync))
    table.insert(lines, string.format("Synced with: %d guildies", syncCount))
    
    -- KoS Summary
    table.insert(lines, "\n[KOS LISTS]")
    local personal = db.kosPersonal or {}
    local synced = db.kosSynced or {}
    local rejected = db.kosRejected or {}
    table.insert(lines, string.format("Personal KoS: %d entries", table.getn(personal)))
    table.insert(lines, string.format("Synced KoS: %d entries", table.getn(synced)))
    table.insert(lines, string.format("Rejected: %d entries", table.getn(rejected)))
    
    -- Guild Status
    table.insert(lines, "\n[HOSTILE GUILDS]")
    local guilds = db.hosileGuilds or {}
    local guildCount = table.getn(guilds)
    if guildCount > 0 then
        table.insert(lines, string.format("Total: %d hostile guilds", guildCount))
        for guildName, entry in pairs(guilds) do
            local members = db.guildMembers and db.guildMembers[string.lower(guildName)] or {}
            local memberCount = table.getn(members)
            table.insert(lines, string.format("  • %s (%d members tracked)", guildName, memberCount))
        end
    else
        table.insert(lines, "No hostile guilds tagged")
    end
    
    -- Cyrillic Detection Cache
    table.insert(lines, "\n[NATIONALITY DETECTION]")
    local cache = db.cyrillicCache or {}
    local russian = 0
    local ukrainian = 0
    local unclear = 0
    for _, nat in pairs(cache) do
        if nat == "russian" then russian = russian + 1
        elseif nat == "ukrainian" then ukrainian = ukrainian + 1
        else unclear = unclear + 1
        end
    end
    table.insert(lines, string.format("🇷🇺 Russian: %d", russian))
    table.insert(lines, string.format("🇺🇦 Ukrainian: %d", ukrainian))
    table.insert(lines, string.format("❓ Unclear: %d", unclear))
    
    -- Recent entries
    table.insert(lines, "\n[RECENT ENTRIES]")
    local recentCount = 0
    local maxRecent = 10
    for key, entry in pairs(personal) do
        if recentCount >= maxRecent then break end
        local nat = cache[key] and getNationalityEmoji(cache[key]) or ""
        table.insert(lines, string.format("%s %s (%s ago) - %s", 
            nat, entry.playerName, formatTimestamp(entry.addedAt), entry.notes or ""))
        recentCount = recentCount + 1
    end
    
    table.insert(lines, "\n=== Use /saboton spyenhancement for commands ===")
    
    editBox:SetText(table.concat(lines, "\n"))
    editBox:HighlightText(0, 0)
end

local function showMainWindow()
    local frame = createMainWindow()
    updateMainWindowContent(frame.editBox)
    frame:Show()
end

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local function createMinimapButton()
    if miniButton then return miniButton end
    
    local btn = CreateFrame("Button", "SpyEnhancementMinimapBtn", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameLevel(8)
    btn:SetHighestClickedFrameLevel()
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Ability_Spy")
    btn:SetNormalTexture(icon)
    
    -- Button positioning
    local angle = math.rad(225)
    btn:SetPoint("CENTER", Minimap, "CENTER", 52 * math.cos(angle), 52 * math.sin(angle))
    
    -- Tooltips
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Spy Enhancement", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Show main window", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Broadcast KoS", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handlers
    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            showMainWindow()
        elseif button == "RightButton" then
            -- Trigger manual sync broadcast
            if SpyEnhancementModule and SpyEnhancementModule.HandleCommand then
                SpyEnhancementModule:HandleCommand("sync")
            end
        end
    end)
    
    miniButton = btn
    return btn
end

-- ============================================================================
-- UNIT FRAME TOOLTIP HOOKS
-- ============================================================================

local function hookUnitFrameTooltips()
    -- Hook GameTooltip to show KoS status when hovering player names
    local originalSetUnit = GameTooltip.SetUnit
    function GameTooltip:SetUnit(unit, ...)
        local result = originalSetUnit(self, unit, ...)
        
        if unit then
            local playerName = UnitName(unit)
            local realm = GetRealmName()
            if playerName then
                local info = getSpyPlayerInfo(playerName, realm)
                if info then
                    self:AddLine(" ")
                    for line in string.gmatch(info, "[^\n]+") do
                        self:AddLine(line)
                    end
                    self:Show()
                end
            end
        end
        
        return result
    end
end

-- ============================================================================
-- STATUS PANEL (COMPACT INFO)
-- ============================================================================

local function createStatusPanel()
    local frame = CreateFrame("Frame", "SpyEnhancementStatusPanel", UIParent)
    frame:SetSize(250, 100)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    title:SetText("SpyEnhancement")
    
    -- Content area
    local content = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    content:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    content:SetJustifyH("LEFT")
    content:SetJustifyV("TOP")
    
    frame.content = content
    frame:Hide()
    
    return frame
end

local statusPanel = nil

local function updateStatusPanel()
    if not statusPanel then
        statusPanel = createStatusPanel()
    end
    
    local db = getSpyEnhancementDB() or {}
    local personal = table.getn(db.kosPersonal or {})
    local synced = table.getn(db.kosSynced or {})
    local guilds = table.getn(db.hosileGuilds or {})
    local syncState = db.syncState or {}
    local syncedCount = table.getn(syncState.syncedWith or {})
    
    local text = string.format(
        "KoS: %d+%d | Guilds: %d | Synced: %d",
        personal, synced, guilds, syncedCount
    )
    
    statusPanel.content:SetText(text)
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

function SpyEnhancementUI:OnEnable()
    addon.Print("SpyEnhancementUI: Initializing UI components...")
    
    -- Initialize Spy integration
    if _G.Spy then
        initializeSpyIntegration()
    else
        addon.Print("SpyEnhancementUI: Spy addon not found (optional)")
    end
    
    -- Create UI elements
    createMainWindow()
    createMinimapButton()
    hookUnitFrameTooltips()
    
    addon.Print("SpyEnhancementUI: UI ready! Use /saboton spyenhancement ui to open window")
end

function SpyEnhancementUI:HandleCommand(message)
    message = string.lower(message or "")
    
    if message == "ui" or message == "window" or message == "" then
        showMainWindow()
        return
    end
    
    if message == "status" then
        updateStatusPanel()
        statusPanel:Show()
        return
    end
    
    if message == "minimap" then
        if miniButton then
            if miniButton:IsShown() then
                miniButton:Hide()
                addon.Print("Minimap button hidden")
            else
                miniButton:Show()
                addon.Print("Minimap button shown")
            end
        end
        return
    end
    
    if message == "tooltips" then
        hookUnitFrameTooltips()
        addon.Print("Tooltip hooks reinitialized")
        return
    end
    
    addon.Print("SpyEnhancementUI commands:")
    addon.Print("  ui/window - Show main window")
    addon.Print("  status - Show status panel")
    addon.Print("  minimap - Toggle minimap button")
    addon.Print("  tooltips - Reinitialize tooltip hooks")
end

-- Export for testing
SpyEnhancementUI.getSpyPlayerInfo = getSpyPlayerInfo
SpyEnhancementUI.updateMainWindowContent = updateMainWindowContent

addon.RegisterModule("spyenhancementui", SpyEnhancementUI)
