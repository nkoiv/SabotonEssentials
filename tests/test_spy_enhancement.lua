local h = assert(loadfile("tests/guild_sync_harness.lua"))()
local reasonLocale = { KOSReasonOther = "Other" }
function LibStub(name)
    assert(name == "AceLocale-3.0")
    return { GetLocale = function() return Spy and Spy.reasonLocale or reasonLocale end }
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
        UpdatePlayerStatus = function(_, player, _, _, _, _, _, isEnemy)
            assert(not c.combat and not c.chatRestricted)
            local data = c.db.PlayerData[player] or {}
            c.db.PlayerData[player] = data
            data.name, data.isEnemy = player, isEnemy
            data.time = data.time or time()
        end,
        RemoveIgnoreData = function(_, player) c.db.IgnoreData[player] = nil end,
        RegenerateKOSCentralList = function(_, player)
            local data = assert(c.db.PlayerData[player])
            assert(data.kos == 1 and c.db.KOSData[player])
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
a.module:HandleCommand("allowsync player Remote-Target")
a.module:HandleCommand("allowsync guild Remote Guild")
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
assert(b.db.PlayerData["Shared-Target"] and b.db.PlayerData["Shared-Target"].reason.Other == "Do not publish by default",
    "reason must fill an existing KoS entry even when names already match: "
        .. a.engine:GetStatus() .. " / " .. b.engine:GetStatus() .. " / " .. table.concat(a.messages, "; "))
assert(b.db.KOSData["Shared-Target"] == 100 and b.adds == 0,
    "reason-only import must not reset KoS membership or count as a new name")
assert(b.central["Shared-Target"].reason.Other == "Do not publish by default")
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
assert(b.db.PlayerData["Empty-Target"].reason.Andere == "Shared custom text"
    and b.db.PlayerData["Empty-Target"].reason["Attacked me"] == true,
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
assert(droppedChunk and b.db.PlayerData["Long-Target"].reason.Other == longReason
    and b.db.PlayerData["Long-Target"].reason[longLabel] == true,
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

print("SpyEnhancement integration tests passed")
