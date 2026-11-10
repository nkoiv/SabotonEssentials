local ADDON_NAME, addon = ...

-- SpyEnhancement module: Integrates with Spy addon for guild-wide enhancements
-- Phase 1: Core KoS (Kill On Sight) Sync system
-- Phase 2: Guild tagging system
-- Phase 3: Cyrillic nationality detection (IN PROGRESS)

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
    guildTaggingEnabled = true,
}

-- KoS subsystem (Phase 1)
local KoSSync = {}

-- ============================================================================
-- PHASE 2: GUILD TAGGING SYSTEM
-- ============================================================================

-- Guild tagging subsystem (Phase 2)
local GuildTag = {}

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
-- GUILD TAGGING API (Phase 2)
-- ============================================================================

-- Create a guild entry
local function createGuildEntry(guildName, notes)
    return {
        guildName = guildName,
        addedBy = UnitName("player"),
        addedAt = time(),
        notes = notes or "",
        memberCount = 0,           -- Tracked members
        lastSeen = 0,              -- Last time a member was detected
        rejected = false,          -- Local override
    }
end

-- Normalize guild name for storage
local function getNormalizedGuildKey(guildName)
    return string.lower(guildName)
end

-- Add a guild to hostile list
function GuildTag:Add(guildName, notes)
    if not guildName or guildName == "" then
        addon.Print("SpyEnhancement: Invalid guild name.")
        return false
    end

    local db = getDB()
    local key = getNormalizedGuildKey(guildName)

    -- Create entry
    local entry = createGuildEntry(guildName, notes)
    db.hosileGuilds[key] = entry

    addon.Print(string.format("SpyEnhancement: Added guild %s to hostile list", guildName))
    return true
end

-- Remove a guild from hostile list
function GuildTag:Remove(guildName)
    if not guildName or guildName == "" then
        addon.Print("SpyEnhancement: Invalid guild name.")
        return false
    end

    local db = getDB()
    local key = getNormalizedGuildKey(guildName)

    if db.hosileGuilds[key] then
        db.hosileGuilds[key] = nil
        addon.Print(string.format("SpyEnhancement: Removed guild %s from hostile list", guildName))
        
        -- Also remove associated members
        if db.guildMembers[key] then
            db.guildMembers[key] = nil
        end
        return true
    end

    addon.Print(string.format("SpyEnhancement: Guild %s not found", guildName))
    return false
end

-- Reject a hostile guild locally (keep data but ignore)
function GuildTag:Reject(guildName, reason)
    if not guildName or guildName == "" then
        addon.Print("SpyEnhancement: Invalid guild name.")
        return false
    end

    local db = getDB()
    local key = getNormalizedGuildKey(guildName)

    if db.hosileGuilds[key] then
        db.hosileGuilds[key].rejected = true
        addon.Print(string.format("SpyEnhancement: Rejected guild %s (%s)", guildName, reason or "no reason"))
        return true
    end

    addon.Print(string.format("SpyEnhancement: Guild %s not found", guildName))
    return false
end

-- Accept a rejected guild
function GuildTag:Accept(guildName)
    if not guildName or guildName == "" then
        addon.Print("SpyEnhancement: Invalid guild name.")
        return false
    end

    local db = getDB()
    local key = getNormalizedGuildKey(guildName)

    if db.hosileGuilds[key] and db.hosileGuilds[key].rejected then
        db.hosileGuilds[key].rejected = false
        addon.Print(string.format("SpyEnhancement: Re-accepted guild %s", guildName))
        return true
    end

    addon.Print(string.format("SpyEnhancement: Guild %s not rejected or not found", guildName))
    return false
end

-- Get a guild entry
function GuildTag:Get(guildName)
    local db = getDB()
    local key = getNormalizedGuildKey(guildName)
    local entry = db.hosileGuilds[key]

    -- Don't return rejected entries
    if entry and not entry.rejected then
        return entry
    end

    return nil
end

-- Check if guild is flagged as hostile
function GuildTag:IsHostile(guildName)
    return self:Get(guildName) ~= nil
end

-- Register a guild member (auto-called when player detected in Spy)
function GuildTag:RegisterMember(guildName, playerName, realm)
    if not guildName or not playerName then
        return false
    end

    local db = getDB()
    local guildKey = getNormalizedGuildKey(guildName)
    local playerKey = getNormalizedKey(playerName, realm)

    -- Only track if guild is marked hostile
    if not db.hosileGuilds[guildKey] then
        return false
    end

    -- Initialize guild members table
    if not db.guildMembers[guildKey] then
        db.guildMembers[guildKey] = {}
    end

    -- Track member
    local now = time()
    db.guildMembers[guildKey][playerKey] = {
        playerName = playerName,
        realm = realm,
        detected = db.guildMembers[guildKey][playerKey] and db.guildMembers[guildKey][playerKey].detected or now,
        updated = now,
    }

    -- Update guild's lastSeen and memberCount
    db.hosileGuilds[guildKey].lastSeen = now
    db.hosileGuilds[guildKey].memberCount = 0
    for _ in pairs(db.guildMembers[guildKey]) do
        db.hosileGuilds[guildKey].memberCount = db.hosileGuilds[guildKey].memberCount + 1
    end

    return true
end

-- Get all members of a hostile guild
function GuildTag:GetMembers(guildName)
    local db = getDB()
    local key = getNormalizedGuildKey(guildName)

    if not db.guildMembers[key] then
        return {}
    end

    local result = {}
    for playerKey, member in pairs(db.guildMembers[key]) do
        table.insert(result, member)
    end
    return result
end

-- Get all active hostile guilds
function GuildTag:GetAll()
    local db = getDB()
    local result = {}

    for key, entry in pairs(db.hosileGuilds) do
        if not entry.rejected then
            table.insert(result, entry)
        end
    end

    return result
end

-- Get guild stats
function GuildTag:GetStats()
    local db = getDB()
    local allCount = 0
    local rejectedCount = 0
    local totalMembers = 0

    for _, entry in pairs(db.hosileGuilds) do
        if entry.rejected then
            rejectedCount = rejectedCount + 1
        else
            allCount = allCount + 1
            totalMembers = totalMembers + entry.memberCount
        end
    end

    return {
        active = allCount,
        rejected = rejectedCount,
        totalGuilds = allCount + rejectedCount,
        trackedMembers = totalMembers,
    }
end

-- ============================================================================
-- PHASE 3: CYRILLIC NATIONALITY DETECTION
-- ============================================================================

-- Cyrillic detection subsystem (Phase 3)
local CyrillicDetector = {}

-- Character sets for Russian and Ukrainian
-- Based on Unicode Cyrillic block and language-specific characters
local RUSSIAN_SPECIFIC = {
    ['Ё'] = true, ['ё'] = true,  -- Russian yo
    ['Ы'] = true, ['ы'] = true,  -- Russian y
    ['Э'] = true, ['э'] = true,  -- Russian e (backwards)
}

local UKRAINIAN_SPECIFIC = {
    ['Ї'] = true, ['ї'] = true,  -- Ukrainian yi
    ['Є'] = true, ['є'] = true,  -- Ukrainian ye
    ['Ґ'] = true, ['ґ'] = true,  -- Ukrainian ge
    ['І'] = true, ['і'] = true,  -- Ukrainian i
}

-- Common Cyrillic characters (shared between Russian and Ukrainian)
local COMMON_CYRILLIC = {
    ['А'] = true, ['а'] = true, ['Б'] = true, ['б'] = true, ['В'] = true, ['в'] = true,
    ['Г'] = true, ['г'] = true, ['Д'] = true, ['д'] = true, ['Е'] = true, ['е'] = true,
    ['Ж'] = true, ['ж'] = true, ['З'] = true, ['з'] = true, ['И'] = true, ['и'] = true,
    ['Й'] = true, ['й'] = true, ['К'] = true, ['к'] = true, ['Л'] = true, ['л'] = true,
    ['М'] = true, ['м'] = true, ['Н'] = true, ['н'] = true, ['О'] = true, ['о'] = true,
    ['П'] = true, ['п'] = true, ['Р'] = true, ['р'] = true, ['С'] = true, ['с'] = true,
    ['Т'] = true, ['т'] = true, ['У'] = true, ['у'] = true, ['Ф'] = true, ['ф'] = true,
    ['Х'] = true, ['х'] = true, ['Ц'] = true, ['ц'] = true, ['Ч'] = true, ['ч'] = true,
    ['Ш'] = true, ['ш'] = true, ['Щ'] = true, ['щ'] = true, ['Ъ'] = true, ['ъ'] = true,
    ['Ь'] = true, ['ь'] = true, ['Ю'] = true, ['ю'] = true,
}

-- Detect nationality of player name based on Cyrillic characters
-- Returns: "russian", "ukrainian", "unclear", or nil (no Cyrillic)
function CyrillicDetector:Detect(playerName)
    if not playerName or playerName == "" then
        return nil
    end

    -- Check cache first
    local db = getDB()
    if db.cyrillicCache[playerName] then
        return db.cyrillicCache[playerName]
    end

    local russianScore = 0
    local ukrainianScore = 0
    local cyrillicCount = 0

    -- Scan each character in the name
    for i = 1, #playerName do
        local char = playerName:sub(i, i)

        -- Check for Russian-specific
        if RUSSIAN_SPECIFIC[char] then
            russianScore = russianScore + 1
            cyrillicCount = cyrillicCount + 1
        end

        -- Check for Ukrainian-specific
        if UKRAINIAN_SPECIFIC[char] then
            ukrainianScore = ukrainianScore + 1
            cyrillicCount = cyrillicCount + 1
        end

        -- Check for common Cyrillic
        if COMMON_CYRILLIC[char] then
            cyrillicCount = cyrillicCount + 1
        end
    end

    -- If no Cyrillic found, return nil
    if cyrillicCount == 0 then
        return nil
    end

    -- Determine nationality based on scores
    local result
    if russianScore > ukrainianScore then
        result = "russian"
    elseif ukrainianScore > russianScore then
        result = "ukrainian"
    else
        -- Equal scores or only common characters = unclear
        result = "unclear"
    end

    -- Cache the result
    db.cyrillicCache[playerName] = result
    return result
end

-- Get cached nationality result
function CyrillicDetector:GetCached(playerName)
    if not playerName then return nil end
    local db = getDB()
    return db.cyrillicCache[playerName]
end

-- Clear cache for a specific player
function CyrillicDetector:ClearCache(playerName)
    if not playerName then return end
    local db = getDB()
    db.cyrillicCache[playerName] = nil
end

-- Clear all cached results
function CyrillicDetector:ClearAllCache()
    local db = getDB()
    db.cyrillicCache = {}
end

-- Get stats on Cyrillic players detected
function CyrillicDetector:GetStats()
    local db = getDB()
    local russianCount = 0
    local ukrainianCount = 0
    local unclearCount = 0

    for _, nationality in pairs(db.cyrillicCache) do
        if nationality == "russian" then
            russianCount = russianCount + 1
        elseif nationality == "ukrainian" then
            ukrainianCount = ukrainianCount + 1
        elseif nationality == "unclear" then
            unclearCount = unclearCount + 1
        end
    end

    return {
        russian = russianCount,
        ukrainian = ukrainianCount,
        unclear = unclearCount,
        total = russianCount + ukrainianCount + unclearCount,
    }
end

-- Batch detect players (e.g., from KoS list)
function CyrillicDetector:DetectBatch(playerNames)
    if not playerNames or #playerNames == 0 then
        return {}
    end

    local results = {}
    for _, playerName in ipairs(playerNames) do
        local nationality = self:Detect(playerName)
        if nationality then
            if not results[nationality] then
                results[nationality] = {}
            end
            table.insert(results[nationality], playerName)
        end
    end

    return results
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
    addon.Print("SpyEnhancement: Loaded (Phase 1: KoS Sync + Phase 2: Guild Tagging + Phase 3: Cyrillic)")

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
            phase2Header = {
                type = "header",
                name = "Phase 2: Guild Tagging (ACTIVE)",
                order = 20,
            },
            guildStats = {
                type = "description",
                name = function()
                    local stats = GuildTag:GetStats()
                    return string.format("Hostile Guilds: %d | Tracked Members: %d | Rejected: %d",
                        stats.active, stats.trackedMembers, stats.rejected)
                end,
                order = 21,
            },
            phase3Header = {
                type = "header",
                name = "Phase 3: Cyrillic Detection (ACTIVE)",
                order = 30,
            },
            cyrillicStats = {
                type = "description",
                name = function()
                    local stats = CyrillicDetector:GetStats()
                    return string.format("Russian (🇷🇺): %d | Ukrainian (🇺🇦): %d | Unclear (❓): %d | Cached: %d",
                        stats.russian, stats.ukrainian, stats.unclear, stats.total)
                end,
                order = 31,
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

    -- ========================================================================
    -- GUILD TAGGING COMMANDS (Phase 2)
    -- ========================================================================

    if subcommand == "addguild" then
        local guildName = string.match(rest, "^(%S+)")
        if not guildName then
            addon.Print("Usage: /saboton spyenhancement addguild <guildname> [notes]")
            return
        end
        local notes = string.match(rest, "^%S+%s+(.+)$") or ""
        GuildTag:Add(guildName, notes)
        return
    end

    if subcommand == "removeguild" or subcommand == "rmguild" then
        local guildName = string.match(rest, "^(%S+)")
        if not guildName then
            addon.Print("Usage: /saboton spyenhancement removeguild <guildname>")
            return
        end
        GuildTag:Remove(guildName)
        return
    end

    if subcommand == "rejectguild" then
        local guildName = string.match(rest, "^(%S+)")
        if not guildName then
            addon.Print("Usage: /saboton spyenhancement rejectguild <guildname> [reason]")
            return
        end
        local reason = string.match(rest, "^%S+%s+(.+)$") or ""
        GuildTag:Reject(guildName, reason)
        return
    end

    if subcommand == "acceptguild" then
        local guildName = string.match(rest, "^(%S+)")
        if not guildName then
            addon.Print("Usage: /saboton spyenhancement acceptguild <guildname>")
            return
        end
        GuildTag:Accept(guildName)
        return
    end

    if subcommand == "guildlist" then
        local guilds = GuildTag:GetAll()
        if #guilds == 0 then
            addon.Print("No hostile guilds")
            return
        end
        addon.Print(string.format("Hostile Guilds (%d):", #guilds))
        for i, guild in ipairs(guilds) do
            addon.Print(string.format("  %d. [%s] %d members, last seen: %s ago",
                i,
                guild.guildName,
                guild.memberCount,
                guild.lastSeen > 0 and math.floor((time() - guild.lastSeen) / 60) .. "m" or "never"))
            if guild.notes ~= "" then
                addon.Print(string.format("     Notes: %s", guild.notes))
            end
        end
        return
    end

    if subcommand == "guildmembers" then
        local guildName = string.match(rest, "^(%S+)")
        if not guildName then
            addon.Print("Usage: /saboton spyenhancement guildmembers <guildname>")
            return
        end
        
        local members = GuildTag:GetMembers(guildName)
        if #members == 0 then
            addon.Print(string.format("No members tracked for guild %s", guildName))
            return
        end
        
        addon.Print(string.format("Members of [%s] (%d):", guildName, #members))
        for i, member in ipairs(members) do
            local seenAgo = math.floor((time() - member.updated) / 60)
            addon.Print(string.format("  %d. %s (last seen: %dm ago)", i, member.playerName, seenAgo))
        end
        return
    end

    -- ========================================================================
    -- CYRILLIC DETECTION COMMANDS (Phase 3)
    -- ========================================================================

    if subcommand == "detect" then
        local playerName = string.match(rest, "^(%S+)")
        if not playerName then
            addon.Print("Usage: /saboton spyenhancement detect <name>")
            return
        end

        local result = CyrillicDetector:Detect(playerName)
        if result == nil then
            addon.Print(string.format("%s: No Cyrillic characters detected", playerName))
        elseif result == "russian" then
            addon.Print(string.format("%s: Likely Russian 🇷🇺", playerName))
        elseif result == "ukrainian" then
            addon.Print(string.format("%s: Likely Ukrainian 🇺🇦", playerName))
        elseif result == "unclear" then
            addon.Print(string.format("%s: Unclear/Mixed Cyrillic ❓", playerName))
        end
        return
    end

    if subcommand == "cyrillicstats" then
        local stats = CyrillicDetector:GetStats()
        addon.Print("Cyrillic Detection Statistics:")
        addon.Print(string.format("  Russian (🇷🇺): %d", stats.russian))
        addon.Print(string.format("  Ukrainian (🇺🇦): %d", stats.ukrainian))
        addon.Print(string.format("  Unclear (❓): %d", stats.unclear))
        addon.Print(string.format("  Total cached: %d", stats.total))
        return
    end

    if subcommand == "clearcyrillicache" then
        CyrillicDetector:ClearAllCache()
        addon.Print("SpyEnhancement: Cyrillic cache cleared")
        return
    end

    if subcommand == "detectkos" then
        -- Detect all KoS entries
        local entries = KoSSync:GetAll()
        if #entries == 0 then
            addon.Print("No KoS entries to scan")
            return
        end

        addon.Print(string.format("Scanning %d KoS entries for Cyrillic...", #entries))
        local batch = {}
        for _, entry in ipairs(entries) do
            table.insert(batch, entry.playerName)
        end

        local results = CyrillicDetector:DetectBatch(batch)
        for nationality, players in pairs(results) do
            local flag = nationality == "russian" and "🇷🇺" or nationality == "ukrainian" and "🇺🇦" or "❓"
            addon.Print(string.format("%s (%s): %d players", flag, nationality, #players))
            for i, playerName in ipairs(players) do
                if i <= 5 then  -- Show first 5
                    addon.Print(string.format("  - %s", playerName))
                end
            end
            if #players > 5 then
                addon.Print(string.format("  ... and %d more", #players - 5))
            end
        end
        return
    end

    addon.Print("Unknown command. Use '/saboton spyenhancement help'")
end

function SpyEnhancement:PrintHelp()
    addon.Print("SpyEnhancement Commands (Phase 1: KoS Sync + Phase 2: Guild Tagging + Phase 3: Cyrillic):")
    addon.Print("")
    addon.Print("  KoS Commands:")
    addon.Print("    /saboton spyenhancement status           - Show KoS statistics")
    addon.Print("    /saboton spyenhancement sync             - Manual sync with guildies")
    addon.Print("    /saboton spyenhancement add <name>       - Add player to personal KoS")
    addon.Print("    /saboton spyenhancement remove <name>    - Remove from personal KoS")
    addon.Print("    /saboton spyenhancement list             - List all KoS entries")
    addon.Print("    /saboton spyenhancement reject <name>    - Reject synced entry")
    addon.Print("    /saboton spyenhancement accept <name>    - Re-accept rejected entry")
    addon.Print("")
    addon.Print("  Guild Commands (Phase 2):")
    addon.Print("    /saboton spyenhancement addguild <name>      - Mark guild as hostile")
    addon.Print("    /saboton spyenhancement removeguild <name>   - Remove guild from list")
    addon.Print("    /saboton spyenhancement guildlist            - List all hostile guilds")
    addon.Print("    /saboton spyenhancement guildmembers <name>  - Show tracked members")
    addon.Print("    /saboton spyenhancement rejectguild <name>   - Reject guild locally")
    addon.Print("    /saboton spyenhancement acceptguild <name>   - Re-accept guild")
    addon.Print("")
    addon.Print("  Cyrillic Detection Commands (Phase 3):")
    addon.Print("    /saboton spyenhancement detect <name>        - Detect player nationality (🇷🇺/🇺🇦/❓)")
    addon.Print("    /saboton spyenhancement cyrillicstats         - Show Cyrillic detection statistics")
    addon.Print("    /saboton spyenhancement detectkos             - Scan all KoS entries for Cyrillic")
    addon.Print("    /saboton spyenhancement clearcyrillicache     - Clear cached results")
    addon.Print("")
    addon.Print("    /saboton spyenhancement help                  - Show this help")
end

addon.RegisterModule("spyenhancement", SpyEnhancement)
