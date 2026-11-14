local _, addon = ...

local SpyEnhancement = {}
local spy
local sync
local settingsRestored = false
local initializationFrame
local pendingLegacyData
local hookedSpy

local options = {
    enabled = true,
    networkSyncEnabled = true,
    showSyncNotifications = true,
    shareKOSReasons = false,
}

local persistentState = {
    syncState = {
        lastSyncTime = 0,
        syncedWith = {},
    },
    cyrillicCache = {},
}

local MAX_SYNC_ENTRIES = 500
local MAX_NAME_LENGTH = 128
local MAX_REASON_BYTES = 4096

local function otherReasonLabel()
    local locale = LibStub and LibStub("AceLocale-3.0", true)
    locale = locale and locale:GetLocale("Spy", true)
    return locale and locale.KOSReasonOther
end

local function hex(value)
    return (value:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end

local function encodeReason(reason)
    if issecretvalue and issecretvalue(reason) then return nil, "Spy has a restricted KoS reason." end
    if reason == nil then return "" end
    if type(reason) ~= "table" then
        return nil, "Spy has an unsupported KoS reason."
    end
    local parts, custom = {}, false
    for label, value in pairs(reason) do
        if (issecretvalue and (issecretvalue(label) or issecretvalue(value)))
            or type(label) ~= "string" or #label == 0 or #label > 512 or label:find("%z") then
            return nil, "Spy has an invalid KoS reason label."
        end
        local tag, text = "B", label
        if type(value) == "string" then
            if custom or #value == 0 or #value > 2048 or value:find("%z") or label ~= otherReasonLabel() then
                return nil, "Spy has an invalid or oversized custom KoS reason (maximum 2,048 bytes)."
            end
            custom, tag, text = true, "O", value
        elseif value ~= true or label == otherReasonLabel() then
            return nil, "Spy has an unsupported KoS reason value."
        end
        text = hex(text)
        parts[#parts + 1] = tag .. #text .. ":" .. text
        if #parts > 64 then return nil, "Spy has too many KoS reasons (maximum 64)." end
    end
    table.sort(parts)
    local encoded = table.concat(parts)
    if #encoded > MAX_REASON_BYTES then return nil, "Spy KoS reasons exceed the 4,096-byte sync limit." end
    return encoded
end

local function decodeReason(encoded)
    if #encoded == 0 or #encoded > MAX_REASON_BYTES then return nil end
    local reason, offset, count = {}, 1, 0
    while offset <= #encoded do
        local tag, length, start = encoded:match("^([BO])(%d+):()", offset)
        length = tonumber(length)
        if not tag or not length or length == 0 or length % 2 ~= 0
            or length > 4096 or start + length - 1 > #encoded then return nil end
        local text = encoded:sub(start, start + length - 1)
        if text:find("[^0-9a-f]") then return nil end
        text = text:gsub("%x%x", function(byte) return string.char(tonumber(byte, 16)) end)
        local label = tag == "B" and text or otherReasonLabel()
        if not label or reason[label] ~= nil then return nil end
        reason[label] = tag == "B" and true or text
        offset, count = start + length, count + 1
        if count > 64 then return nil end
    end
    if encodeReason(reason) ~= encoded then return nil end
    return reason
end

local function getPersistentState()
    if type(persistentState.syncState) ~= "table" then
        persistentState.syncState = { lastSyncTime = 0, syncedWith = {} }
    end
    if type(persistentState.syncState.lastSyncTime) ~= "number" then
        persistentState.syncState.lastSyncTime = 0
    end
    local confirmed = persistentState.syncState.lastConfirmedTime
    if type(confirmed) ~= "number" or confirmed ~= confirmed or confirmed < 0 or confirmed == math.huge then
        persistentState.syncState.lastConfirmedTime = 0
    end
    if type(persistentState.syncState.syncedWith) ~= "table" then
        persistentState.syncState.syncedWith = {}
    end
    if type(persistentState.cyrillicCache) ~= "table" then
        persistentState.cyrillicCache = {}
    end
    if type(persistentState.listState) ~= "table" then
        persistentState.listState = { players = {}, guilds = {} }
    end
    for _, kind in ipairs({ "players", "guilds" }) do
        if type(persistentState.listState[kind]) ~= "table" then persistentState.listState[kind] = {} end
    end
    return persistentState
end

local function trim(value)
    return (value:gsub("^%s*(.-)%s*$", "%1"))
end

local function validName(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string"
        and #value > 0
        and #value <= MAX_NAME_LENGTH
        and not value:find("[%c]")
end

local function getSpyPlayerList()
    if type(SpyPerCharDB) ~= "table" or type(SpyPerCharDB.KOSData) ~= "table" then
        return nil
    end
    return SpyPerCharDB.KOSData
end

local function getWatchedGuilds()
    if not spy or type(spy.GuildList) ~= "function" then
        return nil
    end
    local guilds = spy:GuildList()
    return type(guilds) == "table" and guilds or nil
end

local function guildKey(guildName)
    return trim(guildName):lower()
end

local function watchedGuild(guildName, guilds)
    if spy and type(spy.WatchedGuild) == "function" then
        return spy:WatchedGuild(guildName)
    end
    return guilds[guildKey(guildName)]
end

local function importsRestricted()
    local chat = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
    return (InCombatLockdown and InCombatLockdown()) or (sync and sync.restriction)
        or (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
        or (chat and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
            and C_RestrictedActions.IsAddOnRestrictionActive(chat))
end

local function refreshSpyLists()
    if type(spy.RegenerateKOSGuildList) == "function" then spy:RegenerateKOSGuildList() end
    if type(spy.RefreshCurrentList) == "function" then spy:RefreshCurrentList() end
    if SpyStats and type(SpyStats.Recalulate) == "function" then SpyStats:Recalulate() end
end

local function updateSpyKOSPlayer(name, add, reason, replaceReason)
    if importsRestricted() then return false end
    local share = spy.db and spy.db.profile and spy.db.profile.ShareKOSBetweenCharacters
    if share and type(spy.RegenerateKOSCentralList) ~= "function" then
        addon.Print("SpyEnhancement: Spy's central KoS update API is unavailable; sync was not applied.")
        return false
    end
    -- Mirror ToggleKOSPlayer's data updates without its chat/sound side effects.
    spy:UpdatePlayerStatus(name, nil, nil, nil, nil, nil, true, nil, nil)
    local data = SpyPerCharDB.PlayerData[name]
    if type(data) ~= "table" or data.name ~= name or type(data.time) ~= "number" or data.isEnemy ~= true then
        addon.Print("SpyEnhancement: Spy did not create the imported KoS player's display data; sync was not applied.")
        return false
    end
    if add then spy:AddKOSData(name) end
    if not getSpyPlayerList()[name] then
        addon.Print("SpyEnhancement: Spy did not add the imported KoS player; sync was not applied.")
        return false
    end
    spy:RemoveIgnoreData(name)
    data.kos = 1
    -- Any existing non-empty reason wins, whether written locally or imported earlier.
    if reason and (data.reason == nil or (type(data.reason) == "table" and next(data.reason) == nil)
        or (replaceReason and data.reason == replaceReason)) then
        data.reason = reason
    end
    if share then spy:RegenerateKOSCentralList(name) end
    refreshSpyLists()
    return true
end

local function migrateLegacyPlayerLists(legacyData)
    local playerList = getSpyPlayerList()
    if type(legacyData) ~= "table" or not playerList or importsRestricted() then return false end

    local rejected = type(legacyData.kosRejected) == "table" and legacyData.kosRejected or {}
    local imported = 0
    for _, list in ipairs({ legacyData.kosPersonal or {}, legacyData.kosSynced or {} }) do
        if type(list) == "table" then
            for key, entry in pairs(list) do
                if type(entry) == "table" and not rejected[key] and not entry.rejected then
                    local name = entry.playerName
                    if validName(name) then
                        local realm = entry.realm
                        if type(realm) == "string" and realm ~= "" and realm ~= GetRealmName()
                            and not name:find("-", 1, true) then
                            name = name .. "-" .. realm
                        end
                        if not playerList[name] then
                            if not updateSpyKOSPlayer(name, true) then return false end
                            imported = imported + 1
                        end
                    end
                end
            end
        end
    end

    if imported > 0 then
        if type(spy.RegenerateKOSGuildList) == "function" then spy:RegenerateKOSGuildList() end
        if type(spy.RefreshCurrentList) == "function" then spy:RefreshCurrentList() end
        addon.Print(string.format("SpyEnhancement: Imported %d legacy KoS entr%s into Spy.",
            imported, imported == 1 and "y" or "ies"))
    end
    return true
end

local function identity(name)
    if name == nil then
        if spy and type(spy.PlayerName) == "function" then
            name = spy:PlayerName("player")
        else
            local first, second = UnitName("player")
            if not validName(first) then return nil end
            name = first
            if validName(second) then name = first .. "-" .. second end
        end
    end
    if not validName(name) then return nil end
    -- On Forever the second name component is a surname, not an internal realm.
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        -- Guild chat uses "First Last"; Spy and some roster APIs use "First-Last".
        return (name:gsub(" ", "-"))
    end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
        name = name .. "-" .. realm
    end
    return name
end

local function listScope()
    return spy and (spy.StoreRealm or spy.RealmName) or GetRealmName()
end

local function syncScope()
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not validName(guild) then return nil end
    return listScope() .. "\t" .. guild
end

local function parseRecord(record)
    if type(record) ~= "string" then return nil end
    local kind, name, suffix = record:match("^([PG])\t([^\t]+)(.*)$")
    if not validName(name) or trim(name) ~= name then return nil end
    local reason
    if suffix ~= "" then
        if kind ~= "P" or suffix:sub(1, 1) ~= "\t" then return nil end
        reason = decodeReason(suffix:sub(2))
        if not reason then return nil end
    end
    return kind, name, reason, suffix
end

local function recordKey(record)
    local kind, name = parseRecord(record)
    if not kind then return nil end
    if kind == "P" then
        local canonical = identity(name)
        return canonical and ("P\t" .. canonical:lower())
    end

    return kind == "G" and ("G\t" .. guildKey(name)) or nil
end

local function recordContentKey(record)
    local key = recordKey(record)
    local _, _, _, suffix = parseRecord(record)
    return key and (key .. suffix)
end

local function listBookkeeping(kind)
    local state = getPersistentState().listState
    local key = listScope()
    local entries
    if kind == "P" then
        key = key .. "\t" .. (spy.StoreCharacter or identity() or "?")
        entries = state.players
    else
        entries = state.guilds
    end
    if type(entries[key]) ~= "table" then entries[key] = {} end
    local entry = entries[key]
    if type(entry.imported) ~= "table" then entry.imported = {} end
    if type(entry.suppressed) ~= "table" then entry.suppressed = {} end
    if type(entry.reasons) ~= "table" then entry.reasons = {} end
    if type(entry.localEntries) ~= "table" then entry.localEntries = {} end
    return entry
end

local function sameReason(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for label, value in pairs(left) do if right[label] ~= value then return false end end
    for label, value in pairs(right) do if left[label] ~= value then return false end end
    return true
end

local function importedPlayers()
    local book, present = listBookkeeping("P"), {}
    for name, added in pairs(getSpyPlayerList()) do
        local key = type(name) == "string" and recordKey("P\t" .. name)
        if key then
            present[key] = name
            local imported = book.imported[key]
            if imported == true then
                book.imported[key] = added
            elseif imported and imported ~= added then
                -- A later explicit re-add belongs to the player, not the old import.
                book.imported[key] = nil
                book.localEntries[key] = added
            end
        end
    end
    local entries = {}
    for key in pairs(book.imported) do
        if present[key] then
            entries[#entries + 1] = { key = key, name = present[key] }
        else
            book.imported[key], book.suppressed[key] = nil, true
            book.reasons[key] = nil
        end
    end
    for key in pairs(book.reasons) do
        if not present[key] then book.reasons[key] = nil end
    end
    for key in pairs(book.localEntries) do
        if not present[key] then book.localEntries[key] = nil end
    end
    table.sort(entries, function(a, b) return a.key < b.key end)
    return entries
end

local function suspectedImports()
    local book, entries = listBookkeeping("P"), {}
    local function missing(value)
        if issecretvalue and issecretvalue(value) then return false end
        return value == nil or value == ""
    end
    for name, added in pairs(getSpyPlayerList()) do
        local key = type(name) == "string" and recordKey("P\t" .. name)
        local data = SpyPerCharDB.PlayerData[name]
        if key and not book.imported[key] and book.localEntries[key] ~= added
            and not (issecretvalue and issecretvalue(data))
            and (data == nil or (type(data) == "table"
                and missing(data.zone) and missing(data.level) and missing(data.class))) then
            entries[#entries + 1] = { key = key, name = name }
        end
    end
    table.sort(entries, function(a, b) return a.key < b.key end)
    return entries
end

local function prepareImportedReason(name, key, reason, newMember)
    local book = listBookkeeping("P")
    local data = SpyPerCharDB.PlayerData[name]
    local current = data and data.reason
    local tracked = book.reasons[key]
    local placeholder = tracked and tracked.wire == "" and sameReason(current, tracked.display)
    if current ~= nil and not (type(current) == "table" and next(current) == nil) and not placeholder then
        return nil
    end
    if not reason and (not newMember or placeholder) then return nil end
    local label = otherReasonLabel()
    if not label then return nil, nil, nil, "Spy's localized Other reason label is unavailable." end
    local wire, err = encodeReason(reason)
    if not wire then return nil, nil, nil, err end
    local texts = {}
    for key, value in pairs(reason or {}) do
        texts[#texts + 1] = value == true and key or value
    end
    table.sort(texts)
    local text = #texts > 0 and table.concat(texts, ", ") or "imported KoS (no shared reason)"
    local display = { [label] = "Guild: " .. text:gsub("|", "||") }
    return display, { wire = wire, display = { [label] = display[label] } }, placeholder and current or nil
end

local function localRecords()
    local players, guilds = getSpyPlayerList(), getWatchedGuilds()
    if not players or not guilds then return nil, "Spy's lists are unavailable." end
    importedPlayers()
    local records, present = {}, {}
    local playerCount, guildCount = 0, 0
    for name in pairs(players) do
        local record = type(name) == "string" and "P\t" .. name
        local key = record and recordKey(record)
        if not key then return nil, "Spy contains a player name that cannot be synced." end
        if settingsRestored and not importsRestricted() and listBookkeeping("P").imported[key] then
            local data = SpyPerCharDB.PlayerData[name]
            if type(data) ~= "table" or data.kos ~= 1 or data.name ~= name
                or type(data.time) ~= "number" or data.isEnemy ~= true then
                if not updateSpyKOSPlayer(name, false) then
                    return nil, "Spy's imported KoS display data could not be repaired."
                end
            end
        end
        if options.shareKOSReasons then
            local data = SpyPerCharDB.PlayerData[name]
            local reason = data and data.reason
            local tracked = listBookkeeping("P").reasons[key]
            local encoded, err
            if tracked and type(tracked.wire) == "string" and sameReason(reason, tracked.display) then
                encoded = tracked.wire
            else
                encoded, err = encodeReason(reason)
            end
            if not encoded then return nil, err end
            if encoded ~= "" then record = record .. "\t" .. encoded end
        end
        if not present[key] then
            records[#records + 1], present[key] = record, name
            playerCount = playerCount + 1
        end
    end
    for key, entry in pairs(guilds) do
        local name = type(entry) == "table" and entry.name or key
        local record = type(name) == "string" and "G\t" .. name
        local canonical = record and recordKey(record)
        if not canonical then return nil, "Spy contains a guild name that cannot be synced." end
        if not present[canonical] then
            records[#records + 1], present[canonical] = record, true
            guildCount = guildCount + 1
        end
    end
    if playerCount > MAX_SYNC_ENTRIES or guildCount > MAX_SYNC_ENTRIES then
        return nil, "Spy sync supports at most 500 players and 500 guilds."
    end
    for _, kind in ipairs({ "P", "G" }) do
        local book = listBookkeeping(kind)
        for key in pairs(book.imported) do
            if not present[key] then
                book.imported[key], book.suppressed[key] = nil, true
            end
        end
        for key in pairs(book.suppressed) do
            if present[key] then book.suppressed[key] = nil end
        end
    end
    return records, present
end

local function applyRecord(record)
    local key = recordKey(record)
    if not key then return false end
    local records, present = localRecords()
    if not records then return false end
    local kind, name, reason = parseRecord(record)
    local book = listBookkeeping(kind)
    if book.suppressed[key] then return true, false end
    if present[key] then
        if kind == "P" and reason then
            local actualName = present[key]
            local display, tracked, replace, err = prepareImportedReason(actualName, key, reason, false)
            if err then addon.Print("SpyEnhancement: " .. err) return false end
            if display then
                if not updateSpyKOSPlayer(actualName, false, display, replace) then return false end
                book.reasons[key] = tracked
                if addon.SaveSettings then addon.SaveSettings() end
            end
        end
        return true, false
    end
    local count, metadata = 0, 0
    for _, current in ipairs(records) do if current:sub(1, 1) == kind then count = count + 1 end end
    for _ in pairs(book.imported) do metadata = metadata + 1 end
    for _ in pairs(book.suppressed) do metadata = metadata + 1 end
    if count >= MAX_SYNC_ENTRIES or metadata >= 1000 then
        addon.Print("SpyEnhancement: Import limit reached; sync was not applied.")
        return false
    end
    if kind == "P" then
        local display, tracked, replace, err = prepareImportedReason(name, key, reason, true)
        if err then addon.Print("SpyEnhancement: " .. err) return false end
        if not updateSpyKOSPlayer(name, true, display, replace) then return false end
        book.reasons[key] = tracked
    else
        if not watchedGuild(name, getWatchedGuilds()) then spy:ToggleGuild(name, nil, true) end
    end
    book.imported[key] = kind == "P" and getSpyPlayerList()[name] or true
    if addon.SaveSettings then addon.SaveSettings() end
    return true, true
end

local function isCyrillicCodepoint(codepoint)
    return codepoint >= 0x0400 and codepoint <= 0x052F
end

local RUSSIAN_SPECIFIC = {
    [0x0401] = true, [0x0451] = true, -- Ё
    [0x042B] = true, [0x044B] = true, -- Ы
    [0x042D] = true, [0x044D] = true, -- Э
    [0x042A] = true, [0x044A] = true, -- Ъ
}

local UKRAINIAN_SPECIFIC = {
    [0x0404] = true, [0x0454] = true, -- Є
    [0x0406] = true, [0x0456] = true, -- І
    [0x0407] = true, [0x0457] = true, -- Ї
    [0x0490] = true, [0x0491] = true, -- Ґ
}

local function analyzeCyrillic(text)
    local result = { nationality = nil, cyrillic = 0, russian = 0, ukrainian = 0 }
    local index = 1
    while index <= #text do
        local first, second = text:byte(index, index + 1)
        if first and second and first >= 0xD0 and first <= 0xD3
            and second >= 0x80 and second <= 0xBF then
            local codepoint = (first - 0xC0) * 64 + second - 0x80
            if isCyrillicCodepoint(codepoint) then
                result.cyrillic = result.cyrillic + 1
                if RUSSIAN_SPECIFIC[codepoint] then
                    result.russian = result.russian + 1
                end
                if UKRAINIAN_SPECIFIC[codepoint] then
                    result.ukrainian = result.ukrainian + 1
                end
            end
            index = index + 2
        else
            index = index + 1
        end
    end

    if result.cyrillic > 0 then
        if result.russian > result.ukrainian then
            result.nationality = "russian"
        elseif result.ukrainian > result.russian then
            result.nationality = "ukrainian"
        else
            result.nationality = "unclear"
        end
    end
    return result
end

local function analyzeText(text, kind)
    if type(text) ~= "string" or text == "" then return nil end
    local key = (kind or "player") .. ":" .. text:lower()
    local cache = getPersistentState().cyrillicCache
    local cached = cache[key]
    if type(cached) == "table" then return cached end

    local result = analyzeCyrillic(text)
    cache[key] = result
    return result
end

local function countCache()
    local counts = { russian = 0, ukrainian = 0, unclear = 0, total = 0 }
    for _, result in pairs(getPersistentState().cyrillicCache) do
        if type(result) == "table" and result.nationality then
            counts[result.nationality] = (counts[result.nationality] or 0) + 1
            counts.total = counts.total + 1
        end
    end
    return counts
end

local function recordSync(sender)
    local syncState = getPersistentState().syncState
    local alreadySynced = false
    for _, name in ipairs(syncState.syncedWith) do
        if name == sender then
            alreadySynced = true
            break
        end
    end
    if not alreadySynced and #syncState.syncedWith < 64 then
        syncState.syncedWith[#syncState.syncedWith + 1] = sender
    end
end

function SpyEnhancement:Broadcast()
    if not sync then addon.Print("SpyEnhancement: Spy is not ready.") return false end
    if settingsRestored and options.networkSyncEnabled and not sync.active and not sync:Start() then return false end
    return sync:Begin()
end

function SpyEnhancement:GetPersistentState()
    if spy and getSpyPlayerList() and getWatchedGuilds() then localRecords() end
    local state = getPersistentState()
    state.data = pendingLegacyData
    return state
end

function SpyEnhancement:LoadPersistentState(state)
    if type(state) ~= "table" then return end

    persistentState = {
        syncState = type(state.syncState) == "table" and state.syncState or { lastSyncTime = 0, syncedWith = {} },
        cyrillicCache = type(state.cyrillicCache) == "table" and state.cyrillicCache or {},
        listState = type(state.listState) == "table" and state.listState or nil,
    }
    if type(state.data) == "table" then
        persistentState.syncState = type(state.data.syncState) == "table"
            and state.data.syncState or persistentState.syncState
        pendingLegacyData = state.data
        if spy and migrateLegacyPlayerLists(pendingLegacyData) then
            pendingLegacyData = nil
        end
    end
end

function SpyEnhancement:GetSyncView(includeSuspected)
    local ready = spy and getSpyPlayerList() and getWatchedGuilds()
    local progress = sync and sync:GetProgress() or { status = "Spy unavailable", active = false }
    local players, guilds = 0, 0
    for _ in pairs(getSpyPlayerList() or {}) do players = players + 1 end
    for _ in pairs(getWatchedGuilds() or {}) do guilds = guilds + 1 end
    local confirmed = getPersistentState().syncState.lastConfirmedTime
    local imported = ready and #importedPlayers() or 0
    local suspected = ready and #suspectedImports() or 0
    return {
        status = not options.networkSyncEnabled and "disabled" or progress.status,
        summary = string.format("Spy lists: %d KoS players (%d imported), %d watched guilds.\nLast confirmed exchange: %s",
            players, imported, guilds, confirmed > 0 and date("%Y-%m-%d %H:%M:%S", confirmed) or "Never"),
        progress = string.format("%d active exchange(s); %d imported, %d requested names remaining.\n%d peer exchange(s) confirmed in the last initiated round.",
            progress.sessions or 0, progress.received or 0, progress.pending or 0, progress.peers or 0),
        canSync = not not (ready and settingsRestored and options.networkSyncEnabled and not progress.active
            and IsInGuild and IsInGuild()),
        canCancel = progress.active,
        suspectedImports = suspected,
        canRemoveImports = not not (ready and settingsRestored
            and (imported > 0 or (includeSuspected == true and suspected > 0)) and not importsRestricted()
            and type(spy.RemoveKOSData) == "function"),
    }
end

function SpyEnhancement:RemoveImportedKOS(includeSuspected)
    if not spy or not getSpyPlayerList() or not settingsRestored or type(spy.RemoveKOSData) ~= "function" then
        addon.Print("SpyEnhancement: Spy's KoS removal API is unavailable.")
        return false
    end
    if importsRestricted() then
        addon.Print("SpyEnhancement: Cannot remove imports during combat/chat restrictions; try again afterward.")
        return false
    end
    local share = spy.db and spy.db.profile and spy.db.profile.ShareKOSBetweenCharacters
    if share and type(spy.RegenerateKOSCentralList) ~= "function" then
        addon.Print("SpyEnhancement: Spy's central KoS update API is unavailable; imports were not removed.")
        return false
    end
    if sync then sync:Cancel("imported KoS removed") end
    local book, removed, suspectedRemoved = listBookkeeping("P"), 0, 0
    local entries = importedPlayers()
    if includeSuspected == true then
        for _, entry in ipairs(suspectedImports()) do
            entry.suspected = true
            entries[#entries + 1] = entry
        end
    end
    for _, entry in ipairs(entries) do
        local data = SpyPerCharDB.PlayerData[entry.name]
        local reason = data and data.reason
        local tracked = book.reasons[entry.key]
        local preserve = not (tracked and sameReason(reason, tracked.display))
        spy:RemoveKOSData(entry.name)
        if getSpyPlayerList()[entry.name] or (data and data.kos) then
            addon.Print("SpyEnhancement: Spy did not remove an imported KoS player; cleanup stopped.")
            if addon.SaveSettings then addon.SaveSettings() end
            refreshSpyLists()
            return false
        end
        if data and preserve then data.reason = reason end
        if share then spy:RegenerateKOSCentralList(entry.name) end
        book.imported[entry.key], book.reasons[entry.key], book.suppressed[entry.key] = nil, nil, true
        removed = removed + 1
        if entry.suspected then suspectedRemoved = suspectedRemoved + 1 end
    end
    refreshSpyLists()
    if addon.SaveSettings then addon.SaveSettings() end
    addon.Print(string.format("SpyEnhancement: Removed %d imported KoS players (%d suspected legacy entries). Other entries and watched guilds kept. Removed names stay suppressed.",
        removed, suspectedRemoved))
    return true
end

function SpyEnhancement:GetSuppressedImports()
    if not spy or not getSpyPlayerList() or not getWatchedGuilds() then return {} end
    localRecords()
    local entries = {}
    for _, kind in ipairs({ "P", "G" }) do
        for key in pairs(listBookkeeping(kind).suppressed) do
            if type(key) == "string" and key:sub(1, 2) == kind .. "\t" then
                entries[#entries + 1] = {
                    key = key, kind = kind, name = key:sub(3),
                    label = (kind == "P" and "Player: " or "Guild: ") .. key:sub(3),
                }
            end
        end
    end
    table.sort(entries, function(a, b) return a.key < b.key end)
    return entries
end

function SpyEnhancement:AllowSyncImport(key)
    if not recordKey(key) or not spy then return false end
    localRecords()
    local kind = key:sub(1, 1)
    listBookkeeping(kind).suppressed[recordKey(key)] = nil
    if addon.SaveSettings then addon.SaveSettings() end
    return true
end

function SpyEnhancement:AllowAllSyncImports()
    if not spy or not getSpyPlayerList() or not getWatchedGuilds() then return false, 0 end
    localRecords()
    local count = 0
    for _, kind in ipairs({ "P", "G" }) do
        local suppressed = listBookkeeping(kind).suppressed
        for key in pairs(suppressed) do
            suppressed[key] = nil
            count = count + 1
        end
    end
    if count > 0 and addon.SaveSettings then addon.SaveSettings() end
    return count > 0, count
end

function SpyEnhancement:GetOptionsSchema()
    return {
        name = "Spy Enhancement",
        dashboard = {
            description = "Reconcile Spy lists with v4 guild peers. KoS reason sharing is opt-in; incoming reasons preserve your notes. Guild reasons stay local. Remove imported KoS keeps local entries and suppresses removed names. Restrictions defer sync. Edit lists in Spy.",
            view = function(includeSuspected) return self:GetSyncView(includeSuspected) end,
            suppressed = function() return self:GetSuppressedImports() end,
            allow = function(key) return self:AllowSyncImport(key) end,
            allowAll = function() return self:AllowAllSyncImports() end,
            sync = function() self:Broadcast() end,
            cancel = function() if sync then sync:Cancel() end end,
            removeImports = function(includeSuspected) return self:RemoveImportedKOS(includeSuspected) end,
        },
        options = {
            {
                type = "checkbox",
                key = "networkSyncEnabled",
                label = "Enable guild sync",
                tooltip = "Allows manual sync, replies to guild peers, and additive imports. All peers need v4. Sending and imports wait during combat/chat restrictions. Incoming KoS reasons never replace your notes or a previously received real reason.",
                default = true,
                get = function() return options.networkSyncEnabled end,
                set = function(value)
                    options.networkSyncEnabled = value
                    if sync then
                        if value and settingsRestored then sync:Start() else sync:Stop() end
                    end
                end,
            },
            {
                type = "checkbox",
                key = "shareKOSReasons",
                label = "Share KoS reasons",
                tooltip = "Off by default. Share player KoS preset reasons and custom Other text with guild peers, including for names they already have. Does not share guild reasons. Received text is labeled Guild; existing notes win, except our unchanged names-only placeholder. Changing this cancels pending work so old snapshots cannot leak reasons.",
                default = false,
                get = function() return options.shareKOSReasons end,
                set = function(value)
                    if options.shareKOSReasons ~= value and sync then sync:Cancel("reason sharing changed; start a new sync") end
                    options.shareKOSReasons = value
                end,
            },
            {
                type = "checkbox",
                key = "showSyncNotifications",
                label = "Show completion notifications",
                tooltip = "Show routine peer and round completion messages. Errors and explicit command feedback remain visible.",
                default = true,
                get = function() return options.showSyncNotifications end,
                set = function(value) options.showSyncNotifications = value end,
            },
        },
    }
end

local function initializeSpyIntegration()
    spy = _G.Spy
    if type(spy) ~= "table" or not getSpyPlayerList() or not getWatchedGuilds()
        or type(SpyPerCharDB.PlayerData) ~= "table"
        or type(spy.AddKOSData) ~= "function" or type(spy.UpdatePlayerStatus) ~= "function"
        or type(spy.RemoveIgnoreData) ~= "function" or type(spy.ToggleGuild) ~= "function" then return false end

    if hookedSpy ~= spy and hooksecurefunc and type(spy.ToggleKOSPlayer) == "function" then
        hooksecurefunc(spy, "ToggleKOSPlayer", function(_, kos, name)
            if not settingsRestored or not validName(name) then return end
            local key = recordKey("P\t" .. name)
            if not key then return end
            local book = listBookkeeping("P")
            -- Explicit Spy UI actions own the membership, even within the same timestamp.
            if kos and getSpyPlayerList()[name] then
                book.imported[key], book.suppressed[key] = nil, nil
                book.localEntries[key] = getSpyPlayerList()[name]
            elseif not kos and not getSpyPlayerList()[name] and book.imported[key] then
                book.imported[key], book.reasons[key], book.suppressed[key] = nil, nil, true
            end
            if addon.SaveSettings then addon.SaveSettings() end
        end)
        hookedSpy = spy
    end

    if not sync then
        sync = addon.GuildSync.New({
            prefix = "SabotonGuild4",
            identity = identity,
            scope = syncScope,
            key = recordKey,
            contentKey = recordContentKey,
            snapshot = localRecords,
            apply = applyRecord,
            enabled = function() return settingsRestored and options.networkSyncEnabled end,
            ready = function() return getSpyPlayerList() ~= nil and getWatchedGuilds() ~= nil end,
            notify = function(message, routine)
                if not routine or options.showSyncNotifications then addon.Print("SpyEnhancement: " .. message) end
            end,
            confirmed = function(sender, added)
                local state = getPersistentState().syncState
                state.lastSyncTime, state.lastConfirmedTime = time(), time()
                recordSync(sender)
                if addon.SaveSettings then addon.SaveSettings() end
                if options.showSyncNotifications then
                    addon.Print(string.format("SpyEnhancement: Confirmed exchange with %s; imported %d entries.", sender, added))
                end
            end,
        })
    end
    if settingsRestored and options.networkSyncEnabled then sync:Start() end

    if pendingLegacyData and migrateLegacyPlayerLists(pendingLegacyData) then
        pendingLegacyData = nil
    end
    if settingsRestored and not importsRestricted() then
        local records, err = localRecords()
        if not records then addon.Print("SpyEnhancement: " .. err) end
    end
    return true
end

function SpyEnhancement:FinishRestore()
    settingsRestored = true
    initializeSpyIntegration()
end

function SpyEnhancement:OnEnable()
    getPersistentState()
    if not pendingLegacyData and type(SabotonEssentialsDB) == "table"
        and type(SabotonEssentialsDB.spyenhancement) == "table" then
        pendingLegacyData = SabotonEssentialsDB.spyenhancement
    end
    initializeSpyIntegration()

    initializationFrame = CreateFrame("Frame")
    initializationFrame:RegisterEvent("ADDON_LOADED")
    initializationFrame:RegisterEvent("PLAYER_LOGIN")
    initializationFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    initializationFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    initializationFrame:SetScript("OnEvent", function(_, event, loadedAddon, state)
        if event == "PLAYER_LOGIN" or loadedAddon == "Spy"
            or event == "PLAYER_REGEN_ENABLED" or (event == "ADDON_RESTRICTION_STATE_CHANGED"
                and Enum and state == Enum.AddOnRestrictionState.Inactive) then
            local function initialize()
                if initializeSpyIntegration() then
                    initializationFrame:UnregisterEvent("ADDON_LOADED")
                    initializationFrame:UnregisterEvent("PLAYER_LOGIN")
                end
            end
            if C_Timer and C_Timer.After then C_Timer.After(0, initialize) else initialize() end
        end
    end)
end

function SpyEnhancement:OnDisable()
    if sync then sync:Stop() end
    if initializationFrame then initializationFrame:UnregisterAllEvents() end
end

local function printStatus()
    local players = getSpyPlayerList() or {}
    local guilds = getWatchedGuilds() or {}
    local syncState = getPersistentState().syncState
    local counts = countCache()
    local playerCount, guildCount = 0, 0
    for _ in pairs(players) do playerCount = playerCount + 1 end
    for _ in pairs(guilds) do guildCount = guildCount + 1 end
    addon.Print(string.format("Spy lists: %d KoS players, %d watched guilds.", playerCount, guildCount))
    addon.Print(string.format("Last confirmed exchange: %s; known peers: %d.",
        (syncState.lastConfirmedTime or 0) > 0 and date("%Y-%m-%d %H:%M:%S", syncState.lastConfirmedTime) or "Never",
        #syncState.syncedWith))
    addon.Print("Guild sync: " .. (sync and sync:GetStatus() or "Spy unavailable"))
    addon.Print("KoS reason sharing: " .. (options.shareKOSReasons and "on" or "off")
        .. " (outgoing); incoming reasons fill empty fields or unchanged generated placeholders.")
    addon.Print(string.format("Cyrillic cache: %d Russian, %d Ukrainian, %d unclear.",
        counts.russian, counts.ukrainian, counts.unclear))
end

local function detectAndPrint(kind, text)
    local result = analyzeText(text, kind)
    if not result then
        addon.Print("Usage: /saboton spyenhancement detect [player|guild] <name>")
    elseif not result.nationality then
        addon.Print(string.format("%s: No Cyrillic letters detected.", text))
    elseif result.nationality == "unclear" then
        addon.Print(string.format("%s: Cyrillic detected, but the language is unclear.", text))
    else
        addon.Print(string.format("%s: Likely %s based on language-specific Cyrillic letters.", text, result.nationality))
    end
end

local function detectSpyLists(onlyGuilds)
    local found = 0
    if not onlyGuilds then
        local playerList = getSpyPlayerList()
        if not playerList then
            addon.Print("SpyEnhancement: Spy's KoS list is unavailable.")
            return
        end
        for name in pairs(playerList) do
            local result = analyzeText(name, "player")
            if result and result.nationality then
                found = found + 1
                addon.Print(string.format("Player %s: %s", name, result.nationality))
            end
            local playerData = type(SpyPerCharDB.PlayerData) == "table" and SpyPerCharDB.PlayerData[name]
            local guildName = type(playerData) == "table" and playerData.guild
            if validName(guildName) then
                result = analyzeText(guildName, "guild")
                if result and result.nationality then
                    found = found + 1
                    addon.Print(string.format("Guild %s: %s", guildName, result.nationality))
                end
            end
        end
    end

    local guilds = getWatchedGuilds()
    if guilds then
        for key, entry in pairs(guilds) do
            local name = type(entry) == "table" and entry.name or key
            if validName(name) then
                local result = analyzeText(name, "guild")
                if result and result.nationality then
                    found = found + 1
                    addon.Print(string.format("Guild %s: %s", name, result.nationality))
                end
            end
        end
    end

    if found == 0 then addon.Print("No Cyrillic names found in the selected Spy lists.") end
end

function SpyEnhancement:HandleCommand(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "" or command == "help" then
        addon.Print("SpyEnhancement: options | sync | cancel | removeimports | status | debug | allowsync [player|guild] <name> | detect [player|guild] <name> | detectkos | detectguilds | cyrillicstats | clearcyrillicache")
    elseif command == "options" then
        if addon.modules and addon.modules.options then addon.modules.options:HandleCommand("spyenhancement")
        else addon.Print("SpyEnhancement: Options are unavailable.") end
    elseif command == "sync" then
        self:Broadcast()
    elseif command == "removeimports" then
        self:RemoveImportedKOS()
    elseif command == "debug" then
        if sync then sync:SetDebug(not sync.debug)
        else addon.Print("SpyEnhancement: Sync debug unavailable; Spy is not ready.") end
    elseif command == "cancel" then
        if sync then sync:Cancel() end
        addon.Print("SpyEnhancement: Pending guild sync canceled.")
    elseif command == "allowsync" then
        local kind, name = rest:match("^(%S+)%s+(.+)$")
        local code = kind == "player" and "P" or kind == "guild" and "G"
        local key = code and recordKey(code .. "\t" .. trim(name))
        if not key or not spy then
            addon.Print("Usage: /saboton spyenhancement allowsync [player|guild] <name>")
        else
            self:AllowSyncImport(key)
            addon.Print("SpyEnhancement: This name may be imported on the next sync.")
        end
    elseif command == "status" then
        printStatus()
    elseif command == "detect" then
        local kind, text = rest:match("^(%S+)%s+(.+)$")
        kind = kind and kind:lower()
        if kind ~= "player" and kind ~= "guild" then
            kind, text = "player", rest
        end
        detectAndPrint(kind, trim(text or ""))
    elseif command == "detectkos" then
        detectSpyLists(false)
    elseif command == "detectguilds" then
        detectSpyLists(true)
    elseif command == "cyrillicstats" then
        local counts = countCache()
        addon.Print(string.format("Cyrillic cache: %d Russian, %d Ukrainian, %d unclear, %d total.",
            counts.russian, counts.ukrainian, counts.unclear, counts.total))
    elseif command == "clearcyrillicache" then
        getPersistentState().cyrillicCache = {}
        addon.Print("SpyEnhancement: Cyrillic cache cleared.")
    else
        addon.Print("Unknown command. Use '/saboton spyenhancement help'.")
    end
end

addon.RegisterModule("spyenhancement", SpyEnhancement)
