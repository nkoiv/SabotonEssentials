local h = assert(loadfile("tests/guild_sync_harness.lua"))()
local reasonLocale = { KOSReasonOther = "Other" }
function LibStub(name)
    assert(name == "AceLocale-3.0")
    return { GetLocale = function() return Spy and Spy.reasonLocale or reasonLocale end }
end

function hooksecurefunc(target, method, hook)
    local original = target[method]
    target[method] = function(...)
        original(...)
        hook(...)
    end
end

local function said(client, fragment)
    for _, message in ipairs(client.messages) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end

local function client(name, players, guilds, saved, disabled, setup)
    local c = h:Client(name)
    c.db = { KOSData = players or {}, PlayerData = {}, IgnoreData = {} }
    c.central = {}
    c.guilds = guilds or {}
    c.adds, c.toggles, c.saves = 0, 0, 0
    c.spy = {
        StoreRealm = "Region PvP",
        StoreCharacter = name:gsub("-", " "),
        db = { profile = { ShareKOSBetweenCharacters = true } },
        PlayerName = function() return name end,
        GuildList = function() return c.guilds end,
        WatchedGuild = function(_, guild) return c.guilds[guild:lower()] end,
        AddKOSData = function(_, player)
            assert(not c.combat and not c.chatRestricted)
            c.db.KOSData[player] = time()
            c.adds = c.adds + 1
        end,
        RemoveKOSData = function(_, player)
            assert(not c.combat and not c.chatRestricted)
            c.db.KOSData[player] = nil
            local data = c.db.PlayerData[player]
            if data then data.kos, data.reason = nil, nil end
            c.removed = c.removed or {}
            c.removed[player] = true
        end,
        UpdatePlayerStatus = function(_, player, _, _, _, _, _, isEnemy)
            assert(not c.combat and not c.chatRestricted)
            local data = c.db.PlayerData[player] or {}
            c.db.PlayerData[player] = data
            data.name, data.isEnemy = player, isEnemy
            data.time = data.time or time()
        end,
        RemoveIgnoreData = function(_, player) c.db.IgnoreData[player] = nil end,
        ToggleKOSPlayer = function(self, kos, player)
            if kos then
                self:AddKOSData(player)
                self:UpdatePlayerStatus(player, nil, nil, nil, nil, nil, true)
                c.db.PlayerData[player].kos = 1
            else
                self:RemoveKOSData(player)
            end
        end,
        RegenerateKOSCentralList = function(_, player)
            local data = c.db.PlayerData[player] or {}
            assert((data.kos == 1 and c.db.KOSData[player]) or
                (not data.kos and not c.db.KOSData[player] and c.removed[player]))
            c.central[player] = data
        end,
        ToggleGuild = function(_, guild, reason)
            assert(not c.combat and not c.chatRestricted)
            local key = guild:lower()
            if c.guilds[key] then c.guilds[key] = nil
            else c.guilds[key] = { name = guild, reason = reason } end
            c.toggles = c.toggles + 1
        end,
        RegenerateKOSGuildList = function() end,
        RefreshCurrentList = function() end,
    }
    h:Select(c)
    local addon = {
        Print = function(message) c.messages[#c.messages + 1] = message end,
        RegisterModule = function(_, module) c.module = module end,
        SaveSettings = function() c.saves = c.saves + 1 c.saved = c.module:GetPersistentState() end,
    }
    c.addon = addon
    if setup then setup(c) end
    assert(loadfile("src/Support/GuildSync.lua"))("SabotonEssentials", addon)
    local new = addon.GuildSync.New
    addon.GuildSync.New = function(config)
        c.engine = new(config)
        return c.engine
    end
    assert(loadfile("src/Modules/SpyEnhancement.lua"))("SabotonEssentials", addon)
    c.module:OnEnable()
    assert(not c.registrations, "networking must wait for settings restore")
    if saved then c.module:LoadPersistentState(saved) end
    if disabled then c.module:GetOptionsSchema().options[1].set(false) end
    c.module:FinishRestore()
    for _, peer in ipairs(h.clients) do h:Event(peer, "GUILD_ROSTER_UPDATE") end
    return c
end

local function displayedReason(c, name)
    -- SpyStats and Spy's tooltip render the localized Other value, otherwise the key.
    local data, texts = c.db.PlayerData[name], {}
    local other = (c.spy.reasonLocale or reasonLocale).KOSReasonOther
    for label, value in pairs(data and data.reason or {}) do
        texts[#texts + 1] = label == other and value or label
    end
    table.sort(texts)
    return table.concat(texts, ", ")
end

h:Reset()
SabotonEssentialsDB = nil
local a = client("Alice-Surname", { ["Local-Target"] = 100 }, {
    ["friendly guild"] = { name = "Friendly Guild", reason = "private note" },
})
local b = client("Bob-Surname", { ["Remote-Target"] = 100 }, {
    ["remote guild"] = { name = "Remote Guild", reason = "do not share" },
})
h:Select(a)
assert(a.module:Broadcast())
assert(a.module:GetPersistentState().syncState.lastSyncTime == 0)
h:Run(240)
assert(a.db.KOSData["Remote-Target"] and b.db.KOSData["Local-Target"])
assert(a.db.PlayerData["Remote-Target"] and a.db.PlayerData["Remote-Target"].kos == 1,
    "import must create Spy menu metadata, not only KOSData membership")
assert(a.central["Remote-Target"] == a.db.PlayerData["Remote-Target"],
    "import must update Spy's central KoS store when sharing between characters")
assert(not a.db.KOSData["Remote-Target-InternalRealm"], "surname identity was changed")
assert(a.guilds["remote guild"] and a.guilds["remote guild"].reason == nil)
assert(a.guilds["friendly guild"].reason == "private note")
assert(a.saved.syncState.lastConfirmedTime > 0 and a.saves > 0)
assert(#a.saved.syncState.syncedWith == 1)
h:Select(a)
a.module:HandleCommand("debug")
assert(a.engine.debug and said(a, "Guild sync debug enabled"))
a.module:HandleCommand("debug")
assert(not a.engine.debug and said(a, "Guild sync debug disabled"))
for _, message in ipairs(h.traffic) do
    assert(not message.packet:find("private note", 1, true) and not message.packet:find("do not share", 1, true))
end

h:Select(a)
a.db.KOSData["Remote-Target"] = nil
a.guilds["remote guild"] = nil
assert(a.module:Broadcast())
h:Run(240)
assert(not a.db.KOSData["Remote-Target"] and not a.guilds["remote guild"], "removed imports resurrected")
assert(a.adds == 1 and a.toggles == 1)
h:Select(a)
local view = a.module:GetSyncView()
assert(view.canSync and not view.canCancel and view.summary:find("Last confirmed exchange:", 1, true))
local suppressed = a.module:GetSuppressedImports()
assert(#suppressed == 2 and suppressed[1].kind == "G" and suppressed[2].kind == "P")
a.module:GetOptionsSchema().dashboard.allow(suppressed[1].key)
assert(#a.module:GetSuppressedImports() == 1, "dashboard allow callback must clear real suppression")
local allowed, allowedCount = a.module:AllowAllSyncImports()
assert(allowed and allowedCount == 1 and #a.module:GetSuppressedImports() == 0,
    "bulk allow must clear remaining player and guild suppressions")
a.module:Broadcast()
h:Run(240)
assert(a.db.KOSData["Remote-Target"] and a.guilds["remote guild"])
assert(a.adds == 2 and a.toggles == 2, "toggle API removed an already watched guild")

h:Select(a)
a.module:HandleCommand("detect player Ёж")
assert(said(a, "Likely russian"))
a.module:HandleCommand("detect guild ГільдіяЇ")
assert(said(a, "Likely ukrainian"))
a.module:HandleCommand("detect player Анна")
assert(said(a, "language is unclear"))
a.module:HandleCommand("detect player Anna")
assert(said(a, "No Cyrillic letters"))
a.db.KOSData["КозакЇ"] = time()
a.db.PlayerData["КозакЇ"] = { guild = "ГільдіяЇ" }
a.module:HandleCommand("detectkos")
assert(said(a, "Player КозакЇ: ukrainian") and said(a, "Guild ГільдіяЇ: ukrainian"))
a.module:LoadPersistentState({
    data = {
        kosPersonal = {
            ["legacy"] = { playerName = "LegacyTarget", realm = "Internal Realm" },
            ["rejected"] = { playerName = "RejectedTarget", rejected = true },
        },
        kosSynced = {},
    },
})
assert(a.db.KOSData.LegacyTarget and not a.db.KOSData.RejectedTarget)
assert(a.module:GetPersistentState().data == nil)
a.combat = true
a.module:LoadPersistentState({ data = {
    kosPersonal = { ["deferred"] = { playerName = "Deferred-Legacy" } },
} })
assert(not a.db.KOSData["Deferred-Legacy"])
assert(a.module:GetPersistentState().data, "pending migration must survive saving during combat")
h:Event(a, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
a.combat = false
h:Event(a, "PLAYER_REGEN_ENABLED")
h:Run(1)
assert(not a.db.KOSData["Deferred-Legacy"])
h:Event(a, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
h:Run(1)
assert(a.db.KOSData["Deferred-Legacy"])
h:Select(a)
assert(a.module:GetPersistentState().data == nil)
a.module:HandleCommand("cancel")
assert(a.engine.round == nil)

h:Reset()
a = client("Alice-Surname", {}, {}, nil, true)
assert(not a.registrations and not a.engine.active)
h:Select(a)
view = a.module:GetSyncView()
assert(view.status == "disabled" and not view.canSync and not view.canCancel)
assert(not a.module:Broadcast())
a.module:GetOptionsSchema().options[1].set(true)
assert(a.registrations == 1)
a.module:GetOptionsSchema().options[1].set(false)
assert(not a.engine.active and not a.engine.ticker)

h:Reset()
local state = {
    syncState = { lastSyncTime = 99, syncedWith = {} },
    listState = {
        players = {
            ["Region PvP\tAlice Surname"] = {
                imported = { ["P\tremoved-target"] = true }, suppressed = {},
            },
        },
        guilds = {},
    },
}
a = client("Alice-Surname", {}, {}, state)
b = client("Bob-Surname", { ["Removed-Target"] = 1 })
h:Select(a)
a.module:Broadcast()
h:Run(200)
assert(not a.db.KOSData["Removed-Target"], "persisted removed imports must stay suppressed")
assert(a.saved.listState.players["Region PvP\tAlice Surname"].suppressed["P\tremoved-target"])

h:Reset()
local players = {}
for index = 1, 501 do players["Target-" .. index] = 1 end
a = client("Alice-Surname", players)
h:Select(a)
assert(not a.module:Broadcast())
assert(said(a, "500 players"))

for _, concurrent in ipairs({ false, true }) do
    for _, spacedRoster in ipairs({ false, true }) do
        h:Reset()
        local targets = {}
        for index = 1, 9 do targets["Target-" .. index] = 100 end
        a = client("Aya-Zha", targets)
        b = client("Lini-Hisko", { ["Target-1"] = 100 })
        a.senderName, b.senderName = "Aya Zha", "Lini Hisko"
        if spacedRoster then a.rosterName, b.rosterName = a.senderName, b.senderName end
        for _, peer in ipairs({ a, b }) do
            h:Event(peer, "GUILD_ROSTER_UPDATE")
            h:Select(peer)
            peer.module:HandleCommand("debug")
        end
        h:Select(a)
        assert(a.module:Broadcast())
        if concurrent then
            h:Select(b)
            assert(b.module:Broadcast())
        end
        h:Run(300)
        assert(a.saved and a.saved.syncState.lastConfirmedTime > 0
            and b.saved and b.saved.syncState.lastConfirmedTime > 0,
            "space-separated chat identities must complete with hyphenated Spy identities")
        local count = 0
        for name in pairs(b.db.KOSData) do
            count = count + 1
            assert(targets[name], "unexpected imported target identity")
        end
        assert(count == 9 and b.adds == 8 and a.adds == 0, "9/1 shared-target union must be exactly 9")
        for index = 2, 9 do
            local data = b.db.PlayerData["Target-" .. index]
            assert(data and data.kos == 1 and data.name == "Target-" .. index and data.isEnemy,
                "every new imported name must be represented in Spy's KoS menu data")
        end
        assert(said(a, "RX ignored: own broadcast") and said(b, "RX ignored: own broadcast"))
        assert(not said(a, "concurrent H: yielding own round"),
            "lexically first client must not yield to its own spaced broadcast")
    end
end

h:Reset()
local brokenImports = {
    syncState = { syncedWith = {} },
    listState = {
        players = {
            ["Region PvP\tLini Hisko"] = {
                imported = { ["P\tmissing-target"] = true, ["P\tknown-target"] = true,
                    ["P\tremoved-target"] = true },
                suppressed = {},
            },
        },
        guilds = {},
    },
}
a = client("Lini-Hisko", { ["Missing-Target"] = 100, ["Known-Target"] = 200 }, {}, brokenImports, true,
    function(c)
        c.combat = true
        c.db.PlayerData["Known-Target"] = {
            name = "Known-Target", class = "MAGE", level = 60, time = 50, reason = { private = true },
        }
        c.db.IgnoreData["Missing-Target"] = true
    end)
assert(not a.db.PlayerData["Missing-Target"], "repair must wait during local combat even with sync disabled")
a.combat = false
h:Event(a, "PLAYER_REGEN_ENABLED")
h:Run(1)
assert(a.db.PlayerData["Missing-Target"].kos == 1 and a.db.PlayerData["Missing-Target"].isEnemy)
assert(a.db.PlayerData["Known-Target"].kos == 1 and a.db.PlayerData["Known-Target"].class == "MAGE"
    and a.db.PlayerData["Known-Target"].level == 60 and a.db.PlayerData["Known-Target"].time == 50
    and a.db.PlayerData["Known-Target"].reason.private, "repair must preserve existing Spy metadata")
assert(a.db.KOSData["Missing-Target"] == 100 and a.db.KOSData["Known-Target"] == 200 and a.adds == 0,
    "repair must not re-add entries or reset their KoS timestamps")
assert(not a.db.IgnoreData["Missing-Target"] and a.central["Missing-Target"])
assert(not a.db.KOSData["Removed-Target"] and not a.db.PlayerData["Removed-Target"],
    "repair must never resurrect removed imports")
h:Select(a)
assert(a.module:GetPersistentState().listState.players["Region PvP\tLini Hisko"].suppressed["P\tremoved-target"])

h:Reset()
a = client("Alice-Surname")
b = client("Bob-Surname", { ["Rejected-Target"] = 100 })
a.spy.UpdatePlayerStatus = function() end
h:Select(a)
assert(a.module:Broadcast())
h:Run(240)
h:Select(a)
assert(said(a, "Spy did not create") and #a.module:GetPersistentState().syncState.syncedWith == 0,
    "a failed Spy metadata write must not produce confirmed success")
assert(not a.db.KOSData["Rejected-Target"], "failed display-data creation must not leave a phantom KoS entry")

local function sharing(c, value)
    h:Select(c)
    for _, spec in ipairs(c.module:GetOptionsSchema().options) do
        if spec.key == "shareKOSReasons" then
            if value ~= nil then spec.set(value) end
            return spec.get()
        end
    end
    error("reason-sharing option missing")
end

h:Reset()
a = client("Alice-Surname", { ["Shared-Target"] = 100 })
b = client("Bob-Surname", { ["Shared-Target"] = 100 })
a.db.PlayerData["Shared-Target"] = { reason = { Other = "Do not publish by default" } }
assert(sharing(a) == false)
assert(a.engine.config.prefix == "SabotonGuild4", "expanded records must isolate old clients")
assert(a.module:Broadcast())
h:Run(180)
assert(not b.db.PlayerData["Shared-Target"], "default-off sender leaked its reason")
sharing(a, true)
assert(a.module:Broadcast())
h:Run(240)
assert(displayedReason(b, "Shared-Target") == "Guild: Do not publish by default",
    "reason must fill an existing KoS entry even when names already match: "
        .. a.engine:GetStatus() .. " / " .. b.engine:GetStatus() .. " / " .. table.concat(a.messages, "; "))
assert(b.db.KOSData["Shared-Target"] == 100 and b.adds == 0,
    "reason-only import must not reset KoS membership or count as a new name")
assert(b.central["Shared-Target"].reason.Other == "Guild: Do not publish by default")
assert(sharing(b) == false, "receiving a reason must not enable outbound sharing")

h:Reset()
a = client("Alice-Surname", { ["Conflict-Target"] = 100, ["New-Target"] = 100 })
b = client("Bob-Surname", { ["Conflict-Target"] = 100 })
local original = { Other = "My own reason", ["Attacked me"] = true }
a.db.PlayerData["Conflict-Target"] = { reason = { Other = "Remote conflicting reason" } }
a.db.PlayerData["New-Target"] = { reason = { ["Attacked me"] = true, Other = "Remote new reason" } }
b.db.PlayerData["Conflict-Target"] = { reason = original, class = "MAGE" }
b.db.PlayerData["New-Target"] = { reason = { Other = "My reason before adding to KoS" } }
sharing(a, true)
sharing(b, true)
h:Select(a)
assert(a.module:Broadcast())
h:Run(300)
assert(b.db.PlayerData["Conflict-Target"].reason == original and original.Other == "My own reason",
    "incoming reasons must not merge into or replace the receiver's table")
assert(a.db.PlayerData["Conflict-Target"].reason.Other == "Remote conflicting reason",
    "bidirectional collisions must preserve each receiver independently")
assert(b.db.PlayerData["New-Target"].reason.Other == "My reason before adding to KoS",
    "a receiver reason wins even when the name was not previously in KoS")

h:Reset()
a = client("Alice-Surname", { ["Empty-Target"] = 100 })
b = client("Bob-Surname")
a.db.PlayerData["Empty-Target"] = { reason = { Other = "Shared custom text", ["Attacked me"] = true } }
b.db.PlayerData["Empty-Target"] = { reason = {} }
b.spy.reasonLocale = { KOSReasonOther = "Andere" }
sharing(a, true)
assert(a.module:Broadcast())
h:Run(300)
assert(b.db.PlayerData["Empty-Target"].reason.Andere == "Guild: Attacked me, Shared custom text"
    and displayedReason(b, "Empty-Target") == "Guild: Attacked me, Shared custom text",
    "empty reason tables must be filled and custom text must use receiver's Other label")
h:Select(b)
b.db.KOSData["Empty-Target"] = nil
b.module:GetPersistentState()
h:Select(a)
assert(a.module:Broadcast())
h:Run(300)
assert(not b.db.KOSData["Empty-Target"], "reason-bearing records must respect removed-import suppression")

h:Reset()
a = client("Alice-Surname", { ["Late-Target"] = 100 })
b = client("Bob-Surname", { ["Late-Target"] = 100 })
a.db.PlayerData["Late-Target"] = { reason = { Other = "Remote" } }
sharing(a, true)
local edited
h.drop = function(message, receiver)
    if not edited and message.sender == a and receiver == b and message.op == "D" then
        b.db.PlayerData["Late-Target"] = { reason = { Other = "Edited during transfer" } }
        edited = true
    end
end
assert(a.module:Broadcast())
h:Run(300)
assert(edited and b.db.PlayerData["Late-Target"].reason.Other == "Edited during transfer",
    "collision must be decided at apply time, not snapshot time")

h:Reset()
a = client("Alice-Surname", { ["Long-Target"] = 100 })
b = client("Bob-Surname")
local longReason = string.rep("Detailed reason.\n", 70) .. "\t|Hnot-a-log|h" .. string.char(0xD0, 0xAF)
local longLabel = "Preset: attacked while questing"
a.db.PlayerData["Long-Target"] = { reason = { Other = longReason, [longLabel] = true } }
sharing(a, true)
for _, peer in ipairs({ a, b }) do
    h:Select(peer)
    peer.module:HandleCommand("debug")
end
h:Select(a)
local droppedChunk
h.drop = function(message, receiver)
    if message.sender == a and receiver == b and message.op == "C" and not droppedChunk then
        droppedChunk = true
        return true
    end
end
assert(a.module:Broadcast())
h:Run(900)
assert(droppedChunk and displayedReason(b, "Long-Target") ==
    "Guild: " .. longReason:gsub("|", "||") .. ", " .. longLabel,
    "chunked preset/custom reasons must round-trip exactly despite a lost chunk")
assert(b.adds == 1 and #a.saved.syncState.syncedWith == 1 and #b.saved.syncState.syncedWith == 1)
for _, message in ipairs(h.traffic) do
    assert(#message.packet <= 255)
end
for _, message in ipairs(a.messages) do assert(not message:find("Detailed reason.", 1, true)) end
for _, message in ipairs(b.messages) do assert(not message:find("Detailed reason.", 1, true)) end
h:Select(a)
local snapshot = assert(a.engine:Snapshot())
local longRecord
for _, record in pairs(snapshot.records) do longRecord = record end
assert(longRecord and #longRecord > 255)
assert(not a.engine.config.key(longRecord .. "B999999999:00"), "oversized reason field must be rejected")
assert(not a.engine.config.key("P\tTarget-Name\tO2:zz"), "malformed reason hex must be rejected")
assert(not a.engine.config.key("G\tGuild\tB2:61"), "guild reasons must never be accepted")
assert(not a.engine.config.key("P\tTarget-Name\tB2:61B2:61"), "duplicate reasons must be rejected")
assert(not a.engine.config.key("P\tTarget-Name\tB10:4f74686572"),
    "Other must carry text, not a boolean that Spy's tooltip cannot render")
a.db.PlayerData["Long-Target"].reason = { Other = string.rep("x", 2045) }
assert(a.engine:Snapshot(), "exact 4,096-byte encoded reason field must be accepted")
a.db.PlayerData["Long-Target"].reason.Other = string.rep("x", 2046)
local overField, fieldError = a.engine:Snapshot()
assert(not overField and fieldError:find("4,096", 1, true), "encoded reason limit must include framing overhead")
a.db.PlayerData["Long-Target"].reason = { ["z"] = true, ["a"] = true }
local ordered = assert(a.engine:Snapshot()).digest
a.db.PlayerData["Long-Target"].reason = { ["a"] = true, ["z"] = true }
assert(a.engine:Snapshot().digest == ordered, "reason hash must be independent of table iteration order")
a.db.PlayerData["Long-Target"].reason = { Other = longReason }
a.db.PlayerData["Long-Target"].reason.Other = string.rep("x", 2049)
local oversized, err = a.engine:Snapshot()
assert(not oversized and err:find("2,048", 1, true), "oversized custom reasons must fail explicitly, not truncate")
sharing(a, false)
assert(a.engine:Snapshot(), "non-shared oversized reasons must not prevent names-only sync")

h:Reset()
a = client("Alice-Surname", { ["Optout-Target"] = 100 })
b = client("Bob-Surname")
a.db.PlayerData["Optout-Target"] = { reason = { Other = "Pending private snapshot" } }
sharing(a, true)
assert(a.module:Broadcast())
h:Run(16)
sharing(a, false)
assert(not a.engine.round and not next(a.engine.sessions) and #a.engine.controls == 0,
    "turning sharing off must invalidate frozen snapshots and pending chunks")
local before = #h.traffic
h:Run(240)
for index = before + 1, #h.traffic do
    local message = h.traffic[index]
    assert(message.sender ~= a or (message.op ~= "C" and message.op ~= "D"),
        "opt-out must stop sending pending reason payloads")
end

h:Reset()
a = client("Alice-Surname", { ["Forward-Target"] = 100 })
b = client("Bob-Surname")
local forwardReason = { Other = "Shared explanation", ["Attacked me"] = true }
a.db.PlayerData["Forward-Target"] = { reason = forwardReason }
h:Select(a)
assert(a.module:Broadcast())
h:Run(240)
assert(displayedReason(b, "Forward-Target") == "Guild: imported KoS (no shared reason)",
    "names-only imports need a visible origin marker")
sharing(b, true)
local placeholderDigest = assert(b.engine:Snapshot()).digest
h:Select(a)
assert(a.engine:Snapshot().digest == placeholderDigest, "placeholders must never become shared wire descriptions")
sharing(a, true)
assert(a.module:Broadcast())
h:Run(300)
assert(displayedReason(b, "Forward-Target") == "Guild: Attacked me, Shared explanation",
    "a generated names-only placeholder must not block a subsequently shared reason")
sharing(b, true)
local bSnapshot = assert(b.engine:Snapshot())
h:Select(a)
assert(a.engine:Snapshot().digest == bSnapshot.digest,
    "Guild display decoration must not change wire content or cause repeated prefixes")
local c = client("Cara-Surname")
h:Select(b)
assert(b.module:Broadcast())
h:Run(400)
assert(displayedReason(c, "Forward-Target") == "Guild: Attacked me, Shared explanation",
    "forwarding through another client must prefix exactly once")
h:Select(b)
b.db.PlayerData["Forward-Target"].reason.Other = "My edited reason"
local editedSnapshot = assert(b.engine:Snapshot())
h:Select(a)
assert(a.engine:Snapshot().digest ~= editedSnapshot.digest,
    "editing the displayed reason in place must publish the edit, not stale tracked wire text")
local hasEdit
for _, record in pairs(editedSnapshot.records) do
    if b.engine.config.contentKey(record):find("4d792065646974656420726561736f6e", 1, true) then hasEdit = true end
end
assert(hasEdit, "forwarded content must contain the player's edited explanation")
h:Select(a)
assert(a.module:Broadcast())
h:Run(300)
assert(displayedReason(b, "Forward-Target") == "My edited reason", "local edits to imported reasons must win")

h:Reset()
a = client("Alice-Surname", { ["Placeholder-Target"] = 100 })
b = client("Bob-Surname")
h:Select(a)
assert(a.module:Broadcast())
h:Run(240)
b.db.PlayerData["Placeholder-Target"].reason.Other = "I edited the placeholder"
a.db.PlayerData["Placeholder-Target"] = { reason = { Other = "Later remote reason" } }
sharing(a, true)
assert(a.module:Broadcast())
h:Run(300)
assert(displayedReason(b, "Placeholder-Target") == "I edited the placeholder",
    "an edited generated placeholder is a local reason and must never be replaced")

h:Reset()
a = client("Alice-Surname", {
    ["Imported-Target"] = 100, ["Private-Target"] = 100, ["Readded-Target"] = 100, ["Shared-Target"] = 100,
}, { watched = { name = "Watched" } })
b = client("Bob-Surname", { ["Local-Target"] = 100, ["Shared-Target"] = 100 })
local privateReason = { Other = "My private reason predating KoS" }
local looksImported = { Other = "Guild: My locally written note" }
b.db.PlayerData["Private-Target"] = { reason = privateReason, class = "MAGE" }
b.db.PlayerData["Local-Target"] = { reason = looksImported, kos = 1 }
a.db.PlayerData["Imported-Target"] = { reason = { Other = "Remote note" } }
a.db.PlayerData["Shared-Target"] = { reason = { Other = "Reason for an already-local target" } }
sharing(a, true)
assert(a.module:Broadcast())
h:Run(400)
h:Select(b)
assert(b.module:GetSyncView().summary:find("(3 imported)", 1, true))
assert(b.module:GetSyncView().canRemoveImports)
assert(displayedReason(b, "Shared-Target") == "Guild: Reason for an already-local target")
b.combat = true
assert(not b.module:GetSyncView().canRemoveImports and not b.module:RemoveImportedKOS())
assert(b.db.KOSData["Imported-Target"] and said(b, "Cannot remove imports"))
b.combat, b.chatRestricted = false, true
assert(not b.module:RemoveImportedKOS())
b.chatRestricted = false
-- Simulate explicitly re-adding a former import after its original timestamp.
b.db.KOSData["Readded-Target"] = time() + 1
local saved, database, guilds = b.module:GetPersistentState(), b.db, b.guilds
local importedKey = "Region PvP\tBob Surname"
assert(saved.listState.players[importedKey].reasons["P\timported-target"].wire ~= "")
h:Reset()
b = client("Bob-Surname", database.KOSData, guilds, saved, true, function(peer) peer.db = database end)
h:Select(b)
assert(b.module:GetSyncView().canRemoveImports, "cleanup must work after reload with guild sync disabled")
assert(displayedReason(b, "Imported-Target") == "Guild: Remote note")
local beforeReason = b.db.PlayerData["Shared-Target"].reason
b.module:GetOptionsSchema().dashboard.removeImports()
assert(not b.db.KOSData["Imported-Target"] and not b.db.KOSData["Private-Target"])
assert(b.db.KOSData["Local-Target"] and b.db.KOSData["Shared-Target"] and b.db.KOSData["Readded-Target"],
    "local names, shared local names, and later explicit re-adds must survive cleanup")
assert(b.db.PlayerData["Local-Target"].reason == looksImported,
    "a Guild prefix alone must never identify a removable import")
assert(b.db.PlayerData["Shared-Target"].reason == beforeReason,
    "importing a reason onto a local target must not change membership provenance")
assert(b.db.PlayerData["Private-Target"].reason == privateReason
    and b.db.PlayerData["Private-Target"].class == "MAGE", "cleanup must preserve pre-existing private metadata")
assert(not b.db.PlayerData["Imported-Target"].reason and not b.db.PlayerData["Imported-Target"].kos
    and not b.central["Imported-Target"].kos, "cleanup must remove generated reasons and Spy menu/central KoS flags")
assert(b.guilds.watched and not b.module:GetSyncView().canRemoveImports, "watched guilds must remain unchanged")
assert(#b.module:GetSuppressedImports() == 2 and said(b, "Removed 2 imported KoS players"))
assert(b.module:RemoveImportedKOS(), "cleanup must be idempotent")
a = client("Alice-Surname", { ["Imported-Target"] = 100, ["Private-Target"] = 100 })
h:Select(b)
b.module:GetOptionsSchema().options[1].set(true)
assert(b.module:Broadcast())
h:Run(10)
h:Select(b)
assert(b.module:GetSyncView().canCancel)
b.module:HandleCommand("removeimports")
assert(not b.engine.round and not next(b.engine.sessions), "cleanup must invalidate frozen sessions")
h:Run(300)
h:Select(b)
assert(b.module:Broadcast())
h:Run(300)
assert(not b.db.KOSData["Imported-Target"] and not b.db.KOSData["Private-Target"],
    "cleaned names must stay suppressed across later syncs")

h:Reset()
b = client("Bob-Surname")
h:Select(b)
assert(b.engine.config.apply("P\tSameSecond-Target"))
local sameTime = b.db.KOSData["SameSecond-Target"]
b.spy:ToggleKOSPlayer(false, "SameSecond-Target")
assert(#b.module:GetSuppressedImports() == 1, "manual removal must immediately record suppression")
b.spy:ToggleKOSPlayer(true, "SameSecond-Target")
assert(b.db.KOSData["SameSecond-Target"] == sameTime, "test must exercise an identical timestamp")
assert(#b.module:GetSuppressedImports() == 0)
assert(b.module:RemoveImportedKOS() and b.db.KOSData["SameSecond-Target"],
    "explicit local re-adds within the same second must survive cleanup")

h:Reset()
a = client("Alice-Surname", { ["Maximum-Target"] = 100 })
b = client("Bob-Surname")
a.db.PlayerData["Maximum-Target"] = { reason = { Other = string.rep("x", 2045) } }
sharing(a, true)
assert(a.module:Broadcast())
h:Run(1000)
assert(#displayedReason(b, "Maximum-Target") == 2052,
    "display decoration must not truncate an exact-limit original reason")
sharing(b, true)
local maxSnapshot = assert(b.engine:Snapshot())
h:Select(a)
assert(a.engine:Snapshot().digest == maxSnapshot.digest,
    "a generated display exceeding the custom-text limit must still forward its valid original content")

h:Reset()
local oldImports = {
    listState = { players = { ["Region PvP\tBob Surname"] = {
        imported = { ["P\tolder-target"] = true }, suppressed = {},
    } } },
}
b = client("Bob-Surname", { ["Older-Target"] = 100, ["Local-Target"] = 100 }, {}, oldImports)
h:Select(b)
local removeAPI = b.spy.RemoveKOSData
b.spy.RemoveKOSData = function() end
assert(not b.module:RemoveImportedKOS() and said(b, "Spy did not remove"),
    "failed native removals must report failure without claiming successful cleanup")
assert(b.module:GetSyncView().canRemoveImports)
b.spy.RemoveKOSData = removeAPI
assert(b.module:RemoveImportedKOS() and not b.db.KOSData["Older-Target"] and b.db.KOSData["Local-Target"],
    "older tracked imports without prefixed descriptions must also be removable")

h:Reset()
b = client("Bob-Surname", {
    ["NoData-Target"] = 100, ["Empty-Target"] = 100, ["Reason-Target"] = 100,
    ["Zone-Target"] = 100, ["Level-Target"] = 100, ["Class-Target"] = 100,
    ["Malformed-Target"] = 100,
})
h:Select(b)
b.db.PlayerData["Empty-Target"] = { zone = "", class = "", level = "" }
local legacyNote = { Other = "Old note without metadata" }
b.db.PlayerData["Reason-Target"] = { reason = legacyNote }
b.db.PlayerData["Zone-Target"] = { zone = "Elwynn Forest" }
b.db.PlayerData["Level-Target"] = { level = 1 }
b.db.PlayerData["Class-Target"] = { class = "MAGE" }
b.db.PlayerData["Malformed-Target"] = false
b.spy:ToggleKOSPlayer(true, "Explicit-Local")
assert(b.engine.config.apply("P\tTracked-Target"))
-- Explicit local ownership must survive persistence independently of import tracking.
local legacySaved, legacyDB = b.module:GetPersistentState(), b.db
h:Reset()
b = client("Bob-Surname", legacyDB.KOSData, {}, legacySaved, true, function(peer) peer.db = legacyDB end)
h:Select(b)
local legacyView = b.module:GetSyncView()
assert(legacyView.suspectedImports == 3, "only untracked entries missing all three fields are candidates")
assert(b.module:RemoveImportedKOS())
assert(not b.db.KOSData["Tracked-Target"] and b.db.KOSData["NoData-Target"]
    and b.db.KOSData["Empty-Target"] and b.db.KOSData["Reason-Target"],
    "default cleanup must never delete suspected entries")
assert(not b.module:GetSyncView().canRemoveImports and b.module:GetSyncView(true).canRemoveImports)
assert(b.module:GetSyncView().suspectedImports == 3, "merely viewing candidates must not flag them as confirmed imports")
b.db.PlayerData["Empty-Target"].class = "ROGUE"
assert(b.module:GetSyncView().suspectedImports == 2, "candidate detection must reflect newly learned metadata")
b.combat = true
assert(not b.module:RemoveImportedKOS(true) and b.db.KOSData["NoData-Target"],
    "legacy cleanup must honor combat restrictions")
b.combat = false
assert(b.module:RemoveImportedKOS(true))
assert(not b.db.KOSData["NoData-Target"] and not b.db.KOSData["Reason-Target"])
assert(b.db.PlayerData["Reason-Target"].reason == legacyNote, "legacy cleanup must preserve existing notes")
for _, name in ipairs({ "Empty-Target", "Zone-Target", "Level-Target", "Class-Target", "Explicit-Local", "Malformed-Target" }) do
    assert(b.db.KOSData[name], "cleanup removed protected/noncandidate entry: " .. name)
end
assert(#b.module:GetSuppressedImports() == 3 and b.module:GetSyncView().suspectedImports == 0)
assert(said(b, "2 suspected legacy entries"))
assert(b.engine.config.apply("P\tNoData-Target") and not b.db.KOSData["NoData-Target"],
    "suspected entries removed with opt-in must also stay suppressed")
b.module:HandleCommand("allowsync player NoData-Target")
assert(b.engine.config.apply("P\tNoData-Target") and b.db.KOSData["NoData-Target"],
    "explicit Allow again must permit a legacy name to return")

print("SpyEnhancement integration tests passed")
