local messages = {}
local addon = { Print = function(message) messages[#messages + 1] = message end }
local secret = {}
function issecretvalue(value) return value == secret end
function issecrettable(value) return value == secret end
assert(loadfile("src/Support/Spells.lua"))("SabotonEssentials", addon)
C_Spell = {
    GetSpellName = function(id)
        if id == 10 then return "Shield Slam" end
        if id == 11 then return secret end
        if id == 12 then error("lookup failed") end
    end,
    GetSpellInfo = function(name)
        if name == "Shield Slam" then return { spellID = 10 } end
        if name == "secret" then return secret end
        if name == "bad id" then return { spellID = secret } end
        if name == "error" then error("failed") end
    end,
}
assert(addon.Spells.Label(10) == "Shield Slam")
assert(addon.Spells.Label(11) == "Spell 11")
assert(addon.Spells.ResolveName("Shield Slam") == 10)
assert(select(2, addon.Spells.ResolveName("missing")):find("not found"))
assert(select(2, addon.Spells.ResolveName("secret")):find("restricted"))
assert(select(2, addon.Spells.ResolveName("bad id")):find("readable"))
assert(select(2, addon.Spells.ResolveName("error")):find("failed"))
assert(addon.Spells.Name(12) == nil)
assert(addon.Spells.Name(12) == nil and #messages == 1, "lookup failures are reported once")
C_Spell = nil
assert(select(2, addon.Spells.ResolveName("anything")):find("unavailable"))
print("Shared spell helper tests passed")
