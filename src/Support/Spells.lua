local _, addon = ...

local Spells = {}
local reported = {}
local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function report(message)
    if not reported[message] then
        addon.Print("Spell lookup: " .. message)
        reported[message] = true
    end
end

function Spells.Name(id)
    if not C_Spell or not C_Spell.GetSpellName then
        report("C_Spell.GetSpellName is unavailable; names and rank matching cannot be resolved.")
        return nil
    end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if not ok then
        report("GetSpellName failed; some names and rank matches may be unavailable.")
        return nil
    end
    if secret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

function Spells.Label(id)
    return Spells.Name(id) or ("Spell " .. id)
end

function Spells.ResolveName(name)
    if not C_Spell or not C_Spell.GetSpellInfo then
        return nil, "Spell name lookup is unavailable on this client."
    end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if not ok then return nil, "Spell name lookup failed." end
    if secret(info) or (type(info) == "table" and issecrettable and issecrettable(info)) then
        return nil, "Spell lookup returned restricted data."
    end
    if type(info) ~= "table" then return nil, "Spell name not found; use the exact localized name or a spell ID." end
    local id = info.spellID
    if secret(id) or type(id) ~= "number" or id < 1 or id ~= math.floor(id) then
        return nil, "Spell lookup returned no readable spell ID."
    end
    if not Spells.Name(id) then return nil, "Spell name is unavailable or restricted; try again out of combat." end
    return id
end

addon.Spells = Spells
