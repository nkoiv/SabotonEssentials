local ADDON_NAME, addon = ...

-- SpyEnhancement module: Integrates with Spy addon for guild-wide enhancements
-- Phase 1: Core KoS (Kill On Sight) Sync system
-- TODO: Phase 2: Guild tagging system
-- TODO: Phase 3: Cyrillic nationality detection

local SpyEnhancement = {}
local spyAvailable = false

-- ============================================================================
-- PHASE 1: KoS SYNC SYSTEM
-- ============================================================================

-- Configuration
local options = {
    enabled = true,
    syncMode = "both", -- "automatic", "manual", "both"
    showSyncNotifications = true,
}

-- KoS subsystem (Phase 1)
local KoSSync = {}

-- ============================================================================
-- DATA STRUCTURE UTILITIES
-- ============================================================================

-- Normalize player name for storage (player-realm format)
local function getNormalizedKey(playerName, realm)
    realm = realm or GetRealmName()
    return string.lower(playerName .. "-" .. realm)
end

-- Create a KoS entry with all metadata
local function createKosEntry(playerName, realm, source, sourceGuildie, notes)
    realm = realm or GetRealmName()
    return {
        playerName = playerName,
        realm = realm,
        
        -- Core metadata
        source = source or "personal",      -- "personal", "guild", "global"
        addedBy = sourceGuildie or UnitName("player"),  -- Who added this
        addedAt = time(),                   -- Unix timestamp
        notes = notes or "",
        
        -- Sync tracking
        sourceGuild = nil,                  -- Populated later if applicable
        syncFrom = sourceGuildie,           -- Which guildie we got this from
        
        -- Local override
        rejected = false,
        rejectedAt = nil,
        rejectionReason = nil,
        
        -- Phase 3: Cyrillic analysis (TODO)
        cyrillicNationality = nil,          -- "russian", "ukrainian", "unclear"
    }
end

-- Get or initialize database for this module
local function getDB()
    if not SabotonEssentialsDB then
        SabotonEssentialsDB = {}
    end
    if not SabotonEssentialsDB.spyenhancement then
        SabotonEssentialsDB.spyenhancement = {
            version = 1,
            kosPersonal = {},       -- Player's own KoS entries
            kosSynced = {},         -- Entries received from guildies
            kosRejected = {},       -- Rejected entries (by key, boolean flag)
            hosileGuilds = {},      -- TODO: Phase 2 - Guild entries
            guildMembers = {},      -- TODO: Phase 2 - Guild membership tracking
            cyrillicCache = {},     -- TODO: Phase 3 - Cached analysis
            syncState = {
                lastSyncTime = 0,
                syncedWith = {},
            }
        }
    end
    return SabotonEssentialsDB.spyenhancement
end

-- ============================================================================
-- KOS SYNC API
-- ============================================================================

-- Add a player to personal KoS
function KoSSync:Add(playerName, realm, notes)
    if not playerName or playerName == "" then
        addon.Print("SpyEnhancement: Invalid player name.")
        return false
    end
    
    local db = getDB()
    local key = getNormalizedKey(playerName, realm)
    
    -- Create entry
    local entry = createKosEntry(playerName, realm, "personal", nil, notes)
    db.kosPersonal[key] = entry
    
    addon.Print(string.format("SpyEnhancement: Added %s to personal KoS", playerName))
    return true
end

-- Remove from personal KoS
function KoSSync:Remove(playerName, realm)
    if not playerName or playerName == "" then
        addon.Print("SpyEnhancement: Invalid player name.")
        return false
    end
    
    local db = getDB()
    local key = getNormalizedKey(playerName, realm)
    
    if db.kosPersonal[key] then
        db.kosPersonal[key] = nil
        addon.Print(string.format("SpyEnhancement: Removed %s from personal KoS", playerName))
        return true
    end
    
    addon.Print(string.format("SpyEnhancement: %s not found in personal KoS", playerName))
    return false
end

-- Accept a synced/rejected entry (add to active KoS)
function KoSSync:Accept(playerName, realm)
    if not playerName or playerName == "" then
        addon.Print("SpyEnhancement: Invalid player name.")
        return false
    end
    
    local db = getDB()
    local key = getNormalizedKey(playerName, realm)
    
    -- Clear rejection flag
    if db.kosRejected[key] then
        db.kosRejected[key] = nil
        addon.Print(string.format("SpyEnhancement: Re-accepted %s", playerName))
        return true
    end
    
    addon.Print(string.format("SpyEnhancement: %s was not rejected", playerName))
    return false
end

-- Reject a synced entry (keep data but flag as ignored locally)
function KoSSync:Reject(playerName, realm, reason)
    if not playerName or playerName == "" then
        addon.Print("SpyEnhancement: Invalid player name.")
        return false
    end
    
    local db = getDB()
    local key = getNormalizedKey(playerName, realm)
    
    -- Check if entry exists
    if not (db.kosPersonal[key] or db.kosSynced[key]) then
        addon.Print(string.format("SpyEnhancement: %s not found in KoS", playerName))
        return false
    end
    
    db.kosRejected[key] = true
    
    -- Update the entry if it exists
    if db.kosPersonal[key] then
        db.kosPersonal[key].rejected = true
        db.kosPersonal[key].rejectedAt = time()
        db.kosPersonal[key].rejectionReason = reason or "User rejected"
    elseif db.kosSynced[key] then
        db.kosSynced[key].rejected = true
        db.kosSynced[key].rejectedAt = time()
        db.kosSynced[key].rejectionReason = reason or "User rejected"
    end
    
    addon.Print(string.format("SpyEnhancement: Rejected %s (%s)", playerName, reason or "no reason"))
    return true
end

-- Get a KoS entry (searches personal first, then synced, respecting rejections)
function KoSSync:Get(playerName, realm)
    local db = getDB()
    local key = getNormalizedKey(playerName, realm)
    
    -- If rejected, don't return it
    if db.kosRejected[key] then
        return nil
    end
    
    -- Return personal first, then synced
    return db.kosPersonal[key] or db.kosSynced[key]
end

-- Check if player is on KoS (simple boolean, respects rejections)
function KoSSync:IsOnKoS(playerName, realm)
    return self:Get(playerName, realm) ~= nil
end

-- Get count of active KoS entries
function KoSSync:GetCount()
    local db = getDB()
    local count = 0
    
    -- Count personal entries
    for key in pairs(db.kosPersonal) do
        if not db.kosRejected[key] then
            count = count + 1
        end
    end
    
    -- Count synced entries (only if not also in personal)
    for key in pairs(db.kosSynced) do
        if not db.kosRejected[key] and not db.kosPersonal[key] then
            count = count + 1
        end
    end
    
    return count
end

-- Get all active KoS entries (for UI display)
function KoSSync:GetAll()
    local db = getDB()
    local result = {}
    
    -- Add personal
    for key, entry in pairs(db.kosPersonal) do
        if not db.kosRejected[key] then
            table.insert(result, entry)
        end
    end
    
    -- Add synced (only if not also in personal)
    for key, entry in pairs(db.kosSynced) do
        if not db.kosRejected[key] and not db.kosPersonal[key] then
            table.insert(result, entry)
        end
    end
    
    return result
end

-- List stats for debugging/status
function KoSSync:GetStats()
    local db = getDB()
    local personalCount = 0
    local syncedCount = 0
    local rejectedCount = 0
    
    for _ in pairs(db.kosPersonal) do personalCount = personalCount + 1 end
    for _ in pairs(db.kosSynced) do syncedCount = syncedCount + 1 end
    for _ in pairs(db.kosRejected) do rejectedCount = rejectedCount + 1 end
    
    return {
        personal = personalCount,
        synced = syncedCount,
        active = self:GetCount(),
        rejected = rejectedCount,
        lastSync = db.syncState.lastSyncTime,
    }
end

-- ============================================================================
-- MANUAL SYNC (Phase 1 only - no network yet)
-- ============================================================================

function KoSSync:ManualSync()
    addon.Print("SpyEnhancement: Manual sync triggered (network not yet implemented)")
    
    local db = getDB()
    db.syncState.lastSyncTime = time()
    
    -- TODO: Phase 4 - Implement AceComm-based sync with guildies
    -- For now, just show stats
    local stats = self:GetStats()
    addon.Print(string.format("KoS Status: %d active (personal: %d, synced: %d, rejected: %d)",
        stats.active, stats.personal, stats.synced, stats.rejected))
end

-- ============================================================================
-- MODULE INTEGRATION
-- ============================================================================

function SpyEnhancement:GetPersistentState()
    return { enabled = options.enabled, syncMode = options.syncMode }
end

function SpyEnhancement:LoadPersistentState(state)
    if type(state) == "table" then
        if type(state.enabled) == "boolean" then options.enabled = state.enabled end
        if type(state.syncMode) == "string" then options.syncMode = state.syncMode end
    end
end

function SpyEnhancement:GetOptionsSchema()
    return {
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "SpyEnhancement Enabled",
                get = function() return options.enabled end,
                set = function(val) options.enabled = val end,
            },
        }
    }
end

function SpyEnhancement:OnEnable()
    -- Check if Spy is available
    if not LibStub then
        addon.Print("SpyEnhancement: LibStub not found. Module disabled.")
        return
    end

    local aceAddon = LibStub:GetLibrary("AceAddon-3.0", true)
    if not aceAddon then
        addon.Print("SpyEnhancement: AceAddon-3.0 not found. Module disabled.")
        return
    end

    local spy = aceAddon:GetAddon("Spy", true)
    if not spy then
        addon.Print("SpyEnhancement: Spy addon not detected. Module disabled.")
        return
    end

    spyAvailable = true
    addon.Print("SpyEnhancement: Loaded (Phase 1: KoS Sync)")

    -- Initialize database
    getDB()
    
    -- Register with Spy's options if available
    if spy.RegisterModuleOptions and options.enabled then
        spy:RegisterModuleOptions("SabotonEnhancements", self:GetSpyOptionsTable(), "Sabaton Enhancements")
    end
end

function SpyEnhancement:GetSpyOptionsTable()
    return {
        type = "group",
        name = "Sabaton Enhancements",
        desc = "Enhancement options for Spy integration",
        args = {
            header = {
                type = "header",
                name = "Sabaton Enhancements for Spy",
                order = 1,
            },
            kosInfo = {
                type = "description",
                name = string.format("Phase 1: KoS Sync Active\nCurrent KoS entries: %d", KoSSync:GetCount()),
                order = 2,
            },
            kosStats = {
                type = "header",
                name = "KoS Statistics",
                order = 10,
            },
            kosStatsDesc = {
                type = "description",
                name = function()
                    local stats = KoSSync:GetStats()
                    return string.format("Personal: %d | Synced: %d | Active: %d | Rejected: %d",
                        stats.personal, stats.synced, stats.active, stats.rejected)
                end,
                order = 11,
            },
            phase2Info = {
                type = "header",
                name = "Phase 2: Guild Tagging (Coming Soon)",
                order = 20,
            },
            phase3Info = {
                type = "header",
                name = "Phase 3: Cyrillic Detection (Coming Soon)",
                order = 30,
            },
        }
    }
end

function SpyEnhancement:HandleCommand(args)
    if not spyAvailable then
        addon.Print("SpyEnhancement: Spy addon is not loaded.")
        return
    end

    local subcommand, rest = string.match(args or "", "^(%S*)%s*(.*)$")
    subcommand = string.lower(subcommand or ""):match("^(%S*)") or ""

    if subcommand == "" or subcommand == "help" then
        self:PrintHelp()
        return
    end

    if subcommand == "status" then
        local stats = KoSSync:GetStats()
        addon.Print("SpyEnhancement Status:")
        addon.Print(string.format("  Active KoS: %d", stats.active))
        addon.Print(string.format("  Personal: %d | Synced: %d | Rejected: %d", 
            stats.personal, stats.synced, stats.rejected))
        addon.Print(string.format("  Last sync: %s", 
            stats.lastSync > 0 and date("%Y-%m-%d %H:%M:%S", stats.lastSync) or "Never"))
        return
    end

    if subcommand == "sync" then
        KoSSync:ManualSync()
        return
    end

    if subcommand == "add" then
        local playerName = string.match(rest, "^(%S+)")
        if not playerName then
            addon.Print("Usage: /saboton spyenhancement add <name> [notes]")
            return
        end
        local notes = string.match(rest, "^%S+%s+(.+)$") or ""
        KoSSync:Add(playerName, nil, notes)
        return
    end

    if subcommand == "remove" or subcommand == "rm" then
        local playerName = string.match(rest, "^(%S+)")
        if not playerName then
            addon.Print("Usage: /saboton spyenhancement remove <name>")
            return
        end
        KoSSync:Remove(playerName)
        return
    end

    if subcommand == "reject" then
        local playerName = string.match(rest, "^(%S+)")
        if not playerName then
            addon.Print("Usage: /saboton spyenhancement reject <name> [reason]")
            return
        end
        local reason = string.match(rest, "^%S+%s+(.+)$") or ""
        KoSSync:Reject(playerName, nil, reason)
        return
    end

    if subcommand == "accept" then
        local playerName = string.match(rest, "^(%S+)")
        if not playerName then
            addon.Print("Usage: /saboton spyenhancement accept <name>")
            return
        end
        KoSSync:Accept(playerName)
        return
    end

    if subcommand == "list" then
        local entries = KoSSync:GetAll()
        if #entries == 0 then
            addon.Print("No KoS entries")
            return
        end
        addon.Print(string.format("KoS List (%d entries):", #entries))
        for i, entry in ipairs(entries) do
            local source = entry.source == "personal" and "[Personal]" or "[Synced]"
            addon.Print(string.format("  %d. %s %s (added by %s)", i, entry.playerName, source, entry.addedBy))
            if entry.notes ~= "" then
                addon.Print(string.format("     Notes: %s", entry.notes))
            end
        end
        return
    end

    addon.Print("Unknown command. Use '/saboton spyenhancement help'")
end

function SpyEnhancement:PrintHelp()
    addon.Print("SpyEnhancement Commands (Phase 1: KoS Sync):")
    addon.Print("  /saboton spyenhancement status      - Show KoS statistics")
    addon.Print("  /saboton spyenhancement sync        - Manual sync with guildies")
    addon.Print("  /saboton spyenhancement add <name>  - Add player to personal KoS")
    addon.Print("  /saboton spyenhancement remove <n>  - Remove from personal KoS")
    addon.Print("  /saboton spyenhancement list        - List all KoS entries")
    addon.Print("  /saboton spyenhancement reject <n>  - Reject synced entry")
    addon.Print("  /saboton spyenhancement accept <n>  - Re-accept rejected entry")
    addon.Print("  /saboton spyenhancement help        - Show this help")
end

addon.RegisterModule("spyenhancement", SpyEnhancement)
