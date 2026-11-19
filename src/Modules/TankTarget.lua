local _, addon = ...

-- Marks the nameplate of the group tank's current target with a shield icon:
-- neutral with a breathing glow when the mob is also *your* target.
-- Credit: the tank-detection and secret-safe nameplate-matching logic is based on
-- the ScryWoW addon (Combat.lua, "the tank's target"), which had this feature first.
local TankTarget = {}

local DEBUG = false
local forceShields = false

function TankTarget:GetPersistentState()
    return { debug = DEBUG }
end

function TankTarget:LoadPersistentState(state)
    if type(state) == "table" and type(state.debug) == "boolean" then DEBUG = state.debug end
end

local options = {
    enabled = true,
    hostileOnly = true,
    petSoloTank = true,
    inferGroupTank = true,
    markSize = 20,
    showThreat = true,
    allThreat = false,
    threatMode = "scaled",
    threatLow = 50,
    threatHigh = 80,
    tankThreatLow = 120,
    tankThreatHigh = 150,
}

-- Session-only manual tank pick (set via /saboton tanktarget tank <name>).
local pickedTankName = nil
-- Cached tank identities from readable TANK roles; roles can be secret in combat.
local roleTankNames = {}
-- Threat-derived tank, remembered for a short window across target swaps.
local lastHolderName, lastHolderTime = nil, 0
local lastError = nil
local reportedErrors = {}

local function reportError(context, message)
    message = context .. ": " .. tostring(message)
    lastError = message
    if DEBUG or not reportedErrors[message] then
        addon.Print("Tank Target " .. message)
        reportedErrors[message] = true
    end
end

local THREAT_MEMORY_SECONDS = 15
local TICKER_INTERVAL = 0.25
local MAX_NAMEPLATES = 40
local MARK_VERSION = 7

-- Classes that can be tanking in classic-era content; pets qualify separately.
local TANK_CLASSES = { WARRIOR = true, PALADIN = true, DRUID = true }

local SHIELD_ATLASES = { "groupfinder-icon-role-large-tank", "UI-LFG-RoleIcon-Tank", "roleicon-tank" }
local SHIELD_FALLBACK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function plain(value)
    return value ~= nil and not isSecret(value)
end

-- Visits player/party/raid members and their pets; callback returns true to stop.
local function forEachGroupUnit(callback)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            if callback("raid" .. index, false) then return end
            if callback("raidpet" .. index, true) then return end
        end
    else
        if callback("player", false) then return end
        if callback("pet", true) then return end
        for index = 1, math.max(0, GetNumGroupMembers() - 1) do
            if callback("party" .. index, false) then return end
            if callback("partypet" .. index, true) then return end
        end
    end
end

local function unitByName(name)
    local found
    forEachGroupUnit(function(unit, isPet)
        if not isPet then
            local ok, unitName = pcall(UnitName, unit)
            if ok and plain(unitName) and unitName == name then
                found = unit
                return true
            end
        end
    end)
    return found
end

local function unitExists(unit)
    local ok, exists = pcall(UnitExists, unit)
    return ok and plain(exists) and exists and true or false
end

local function isTankCapable(unit, isPet)
    if isPet then return unitExists(unit) end
    local ok, _, classToken = pcall(UnitClass, unit)
    return ok and plain(classToken) and TANK_CLASSES[classToken] or false
end

-- Among tank-capable units, find one that currently holds threat on something.
local function threatTank()
    local holder
    forEachGroupUnit(function(unit, isPet)
        if isTankCapable(unit, isPet) then
            local tanking = false
            if UnitDetailedThreatSituation then
                local ok, isTanking = pcall(UnitDetailedThreatSituation, unit, "target")
                if ok and plain(isTanking) and isTanking then tanking = true end
            end
            if not tanking and UnitThreatSituation then
                local ok, status = pcall(UnitThreatSituation, unit)
                if ok and plain(status) and type(status) == "number" and status >= 2 then tanking = true end
            end
            if tanking then
                holder = unit
                return true
            end
        end
    end)
    return holder
end

-- Without explicit tank assignments, retain the conservative single-tank heuristic.
local function fallbackTank()
    if not IsInGroup() then
        if options.petSoloTank and unitExists("pet") then return "pet", "solo pet" end
        return nil
    end
    if not options.inferGroupTank then return nil end

    local holder = threatTank()
    if holder then
        local ok, name = pcall(UnitName, holder)
        if ok and plain(name) then
            lastHolderName, lastHolderTime = name, GetTime()
        end
        return holder, "threat"
    end
    if lastHolderName and GetTime() - lastHolderTime < THREAT_MEMORY_SECONDS then
        local unit = unitByName(lastHolderName)
        if unit then return unit, "recent threat" end
    end

    local inCombat = false
    do
        local ok, affecting = pcall(UnitAffectingCombat, "player")
        if ok and plain(affecting) and affecting then inCombat = true end
    end
    if not inCombat then
        local only, count = nil, 0
        forEachGroupUnit(function(unit, isPet)
            if not isPet and unitExists(unit) and isTankCapable(unit, false) then
                count = count + 1
                only = unit
            end
        end)
        if count == 1 then return only, "only tank-capable class" end
    end

    return nil
end

local function tankIdentity(unit)
    local ok, name, surname = pcall(UnitName, unit)
    if not ok or not plain(name) or type(name) ~= "string" then return nil end
    return name .. (plain(surname) and type(surname) == "string" and (" " .. surname) or "")
end

local function groupTanks()
    if pickedTankName then
        local unit = unitByName(pickedTankName)
        if unit then return { unit }, "manual pick" end
    end
    if not IsInGroup() then
        local unit, reason = fallbackTank()
        return unit and { unit } or {}, reason
    end

    local tanks, assigned, cache = {}, {}, {}
    forEachGroupUnit(function(unit, isPet)
        if not isPet then
            local identity = tankIdentity(unit)
            if UnitGroupRolesAssigned then
                local ok, role = pcall(UnitGroupRolesAssigned, unit)
                if ok then
                    local tank = plain(role) and role == "TANK"
                    if isSecret(role) and identity then tank = roleTankNames[identity] end
                    if tank then
                        tanks[#tanks + 1] = unit
                        if identity then cache[identity] = true end
                    end
                end
            end
            if GetPartyAssignment then
                local ok, mainTank = pcall(GetPartyAssignment, "MAINTANK", unit)
                if ok and plain(mainTank) and mainTank then assigned[#assigned + 1] = unit end
            end
        end
    end)
    roleTankNames = cache
    local reason = "TANK roles (including cached)"
    if #tanks == 0 then tanks, reason = assigned, "main tank assignments" end
    if #tanks == 0 then
        local unit, fallback = fallbackTank()
        return unit and { unit } or {}, fallback
    end
    local identities = {}
    for _, unit in ipairs(tanks) do identities[unit] = tankIdentity(unit) or unit end
    table.sort(tanks, function(a, b)
        if identities[a] == identities[b] then return a < b end
        return identities[a] < identities[b]
    end)
    return tanks, reason
end

local function nameInitial(part)
    -- Keep the first UTF-8 character intact, including accented names.
    local initial = string.match(part, "^([\1-\127\194-\244][\128-\191]*)")
    return initial and (string.upper(initial) .. ".") or "?"
end

local function tankInitials(tank)
    if not tank then return "?" end
    local ok, name, surname = pcall(UnitName, tank)
    if not ok or isSecret(name) or type(name) ~= "string"
        or name == "" or (UNKNOWNOBJECT and name == UNKNOWNOBJECT) then return "?" end
    local okRegional, regional = false, false
    if RegionalUniqueNamesEnabled then
        okRegional, regional = pcall(RegionalUniqueNamesEnabled)
    end
    if okRegional and not isSecret(regional) and regional then
        -- Forever uses a surname in UnitName's second return, not a realm.
        local first, last = string.match(name, "^(%S-)[%s%-]+(%S+)$")
        if first then name = first end
        if not isSecret(surname) and type(surname) == "string" and surname ~= ""
            and (not UNKNOWNOBJECT or surname ~= UNKNOWNOBJECT) then
            return nameInitial(name) .. nameInitial(surname)
        elseif last then
            return nameInitial(name) .. nameInitial(last)
        end
    end
    return nameInitial(name)
end

local THREAT_GREEN = { 0.35, 1, 0.35 }
local THREAT_YELLOW = { 1, 0.85, 0.25 }
local THREAT_RED = { 1, 0.25, 0.25 }
local playerTankRole = false

local function unknownThreat(text)
    text:SetText((text.label or "Threat") .. " ?")
    text:SetTextColor(0.65, 0.65, 0.65)
end

local function renderThreat(text, percentage, tankColors, lead)
    text.label = lead and "Lead" or "Threat"
    local low = tankColors and options.tankThreatLow or options.threatLow
    local high = tankColors and options.tankThreatHigh or options.threatHigh
    if isSecret(percentage) then
        -- Forever rejects secret curve inputs in addon code; formatting remains native.
        text:SetTextColor(1, 1, 1)
    elseif type(percentage) == "number" and percentage == percentage
        and percentage >= 0 and percentage < math.huge and (not lead or percentage > 0) then
        local color = THREAT_YELLOW
        if percentage < low then color = tankColors and THREAT_RED or THREAT_GREEN
        elseif percentage > high then color = tankColors and THREAT_GREEN or THREAT_RED end
        text:SetTextColor(color[1], color[2], color[3])
    else
        unknownThreat(text)
        return
    end
    text:SetFormattedText(text.label .. " %.0f%%", percentage)
end

local function drawThreat(mark, playerTank, unit)
    if not unit then error("No readable unit token for this nameplate.") end
    if not UnitDetailedThreatSituation then error("UnitDetailedThreatSituation is unavailable.") end
    local isTanking, _, scaled, raw = UnitDetailedThreatSituation("player", unit)
    local percentage = scaled
    if options.threatMode == "raw" or playerTank then percentage = raw end

    if not playerTank then
        if not isSecret(isTanking) and isTanking == true then
            mark.threatText:SetText("AGGRO")
            mark.threatText:SetTextColor(THREAT_RED[1], THREAT_RED[2], THREAT_RED[3])
        elseif isSecret(isTanking) or isTanking ~= nil then
            renderThreat(mark.threatText, percentage, false, false)
        else
            unknownThreat(mark.threatText)
        end
    elseif isSecret(isTanking) then
        if not (mark.threatText.SetAlphaFromBoolean and mark.leadText.SetAlphaFromBoolean) then
            error("This client cannot select secret threat displays.")
        end
        renderThreat(mark.threatText, percentage, true, false)
        if not UnitThreatPercentageOfLead then error("UnitThreatPercentageOfLead is unavailable.") end
        local lead = UnitThreatPercentageOfLead("player", unit)
        renderThreat(mark.leadText, lead, true, true)
        mark.threatText:SetAlphaFromBoolean(isTanking, 0, 1)
        mark.leadText:SetAlphaFromBoolean(isTanking, 1, 0)
        mark.leadText:Show()
    elseif isTanking == true then
        mark.threatText.label = "Lead"
        if not UnitThreatPercentageOfLead then error("UnitThreatPercentageOfLead is unavailable.") end
        renderThreat(mark.threatText, UnitThreatPercentageOfLead("player", unit), true, true)
    elseif isTanking == false then
        renderThreat(mark.threatText, percentage, true, false)
    else
        unknownThreat(mark.threatText)
    end
end

local function setThreatGate(frame, value, invert)
    if isSecret(value) then
        if not frame.SetAlphaFromBoolean then error("This client cannot filter secret threat eligibility.") end
        frame:SetAlphaFromBoolean(value, invert and 0 or 1, invert and 1 or 0)
        frame:Show()
    elseif value == nil then
        frame:Hide()
    else
        frame:SetAlpha(1)
        if (value == true) ~= invert then frame:Show() else frame:Hide() end
    end
end

local function filterThreatUnit(mark, unit)
    if not unit then return false end
    if not UnitCanAttack or not UnitIsDeadOrGhost then
        error("This client lacks attackable/alive unit checks.")
    end
    local attackable = UnitCanAttack("player", unit)
    setThreatGate(mark.threatAttackable, attackable, false)
    if not isSecret(attackable) and attackable ~= true then return false end
    local dead = UnitIsDeadOrGhost(unit)
    setThreatGate(mark.threatAlive, dead, true)
    return isSecret(dead) or dead == false
end

local function refreshThreat(mark, displayThreat, playerTank, unit)
    mark.threatText:Hide()
    mark.leadText:Hide()
    mark.threatAttackable:Hide()
    mark.threatAlive:Hide()
    if not options.showThreat or not displayThreat then return end
    local eligible, allowed = pcall(filterThreatUnit, mark, unit)
    if not eligible then
        reportError("threat eligibility", allowed)
        return
    end
    if not allowed then return end
    mark.threatText.label = "Threat"
    mark.leadText.label = "Lead"
    mark.threatText:SetAlpha(1)
    mark.leadText:SetAlpha(1)
    local ok, err = pcall(drawThreat, mark, playerTank, unit)
    if not ok then
        mark.leadText:Hide()
        mark.threatText:SetAlpha(1)
        unknownThreat(mark.threatText)
        reportError("threat", err)
    end
    mark.threatText:Show()
end

local function applyShieldArt(texture)
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
        for _, atlas in ipairs(SHIELD_ATLASES) do
            local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
            if ok and info then
                texture:SetAtlas(atlas)
                return
            end
        end
    end
    texture:SetTexture(SHIELD_FALLBACK_TEXTURE)
    if GetTexCoordsForRole then
        local ok, a, b, c, d = pcall(GetTexCoordsForRole, "TANK")
        if ok and a then texture:SetTexCoord(a, b, c, d) end
    end
end

-- Probes nameplate-addon health-bar containers before scanning children, so the
-- mark anchors to whatever bar is actually visible (Plater/ElvUI/KUI/TidyPlates).
local BAR_CONTAINER_KEYS = { "UnitFrame", "unitFrame", "PlaterUnitFrame", "kui", "UnitFrameElvUI", "extended" }

local function containerBar(container)
    if type(container) ~= "table" then return nil end
    local bar = container.healthBar or container.HealthBar or container.Health or container.health
    if type(bar) == "table" and bar.IsVisible then
        local ok, visible = pcall(bar.IsVisible, bar)
        if ok and plain(visible) and visible then return bar end
    end
    return nil
end

local function scanForBar(frame, depth)
    if type(frame) ~= "table" or depth > 3 or not frame.GetChildren then return nil end
    local best, bestWidth = nil, 0
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" then
            local candidate
            if child.GetObjectType and child.IsVisible then
                local okType, objectType = pcall(child.GetObjectType, child)
                local okVisible, visible = pcall(child.IsVisible, child)
                if okType and objectType == "StatusBar" and okVisible and plain(visible) and visible then
                    candidate = child
                end
            end
            candidate = candidate or scanForBar(child, depth + 1)
            if candidate and candidate.GetWidth then
                local ok, width = pcall(candidate.GetWidth, candidate)
                if ok and plain(width) and width > bestWidth then
                    best, bestWidth = candidate, width
                end
            end
        end
    end
    return best
end

local function visibleBar(plate)
    for _, key in ipairs(BAR_CONTAINER_KEYS) do
        local bar = containerBar(plate[key])
        if bar then return bar end
    end
    return scanForBar(plate, 1)
end

local function pulseGlow(mark, elapsed)
    mark.pulse = mark.pulse + elapsed
    mark.glow:SetAlpha(0.35 + 0.3 * (1 + math.sin(mark.pulse * 4)) / 2)
end

-- One cached mark frame per plate, parented to the plate itself (not plate.UnitFrame)
-- so it survives nameplate addons hiding the default frame. Version-tagged so a
-- stale or reparented frame gets rebuilt.
local function getMark(plate)
    local mark = plate.sabotonTankMark
    if mark and (mark.version ~= MARK_VERSION or mark:GetParent() ~= plate) then
        mark:Hide()
        mark = nil
    end
    if not mark then
        mark = CreateFrame("Frame", nil, plate)
        mark.version = MARK_VERSION
        mark:SetFrameStrata("HIGH")
        mark:Hide()

        -- Shield visibility can be secret; keep the current-target label independent.
        mark.shield = CreateFrame("Frame", nil, mark)
        mark.shield:SetAllPoints(mark)

        -- Black offset copy acts as a drop shadow.
        mark.shadow = mark.shield:CreateTexture(nil, "BORDER")
        mark.shadow:SetPoint("TOPLEFT", mark, "TOPLEFT", 1.2, -1.2)
        mark.shadow:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 1.2, -1.2)
        applyShieldArt(mark.shadow)
        mark.shadow:SetVertexColor(0, 0, 0, 0.7)

        mark.tex = mark.shield:CreateTexture(nil, "ARTWORK")
        mark.tex:SetAllPoints(mark)
        applyShieldArt(mark.tex)

        mark.glow = mark.shield:CreateTexture(nil, "OVERLAY")
        mark.glow:SetPoint("CENTER", mark, "CENTER", 0, 0)
        applyShieldArt(mark.glow)
        mark.glow:SetBlendMode("ADD")
        mark.glow:SetVertexColor(1, 1, 1, 1)
        if mark.glow.SetDesaturated then pcall(mark.glow.SetDesaturated, mark.glow, true) end
        mark.glow:Hide()

        mark.initialsText = mark.shield:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mark.initialsText:SetPoint("TOP", mark, "BOTTOM", 0, -2)
        mark.initialsText:SetTextColor(1, 1, 1)

        -- Independent gates preserve the per-label secret aggro selection.
        mark.threatAttackable = CreateFrame("Frame", nil, mark)
        mark.threatAttackable:SetAllPoints(mark)
        mark.threatAlive = CreateFrame("Frame", nil, mark.threatAttackable)
        mark.threatAlive:SetAllPoints(mark)
        for _, key in ipairs({ "threatText", "leadText" }) do
            mark[key] = mark.threatAlive:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            mark[key]:SetPoint("BOTTOM", mark, "TOP", 0, 2)
            mark[key]:Hide()
        end

        plate.sabotonTankMark = mark
    end
    return mark
end

local function refreshMark(mark, shared)
    local size = options.markSize
    mark:SetSize(size, size)
    mark.glow:SetSize(size * 1.5, size * 1.5)

    local plate = mark:GetParent()
    local bar = visibleBar(plate)
    if bar ~= mark.anchorBar or not mark.anchored then
        mark:ClearAllPoints()
        if bar then
            mark:SetPoint("RIGHT", bar, "LEFT", -4, 0)
        else
            mark:SetPoint("CENTER", plate, "TOP", -48, 0)
        end
        mark.anchorBar, mark.anchored = bar, true
    end

    mark.tex:SetVertexColor(1, 1, 1)
    if shared then
        mark.glow:Show()
        if not mark.pulsing then
            mark.pulsing = true
            mark.pulse = 0
            mark:SetScript("OnUpdate", pulseGlow)
        end
    else
        mark.glow:Hide()
        if mark.pulsing then
            mark.pulsing = false
            mark:SetScript("OnUpdate", nil)
        end
    end
end

local function hideAllMarks()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        if plate.sabotonTankMark then plate.sabotonTankMark:Hide() end
    end
end

local function getPlateForUnit(unit)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok then return plate end
    return nil
end

-- Some plates lack namePlateUnitToken; map plates to tokens via GetNamePlateForUnit.
local function buildTokenMap()
    local map = {}
    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        local plate = getPlateForUnit(unit)
        if plate then map[plate] = unit end
    end
    return map
end

local function plateUnit(plate)
    local unit = plate.namePlateUnitToken
    if plain(unit) and type(unit) == "string" and unit ~= "" then return unit end
    local frame = plate.UnitFrame
    unit = frame and frame.unit
    if plain(unit) and type(unit) == "string" and unit ~= "" then return unit end
    return nil
end

local function filterHostile(mark, unit)
    if not options.hostileOnly then return end
    if not unit or not UnitIsEnemy then
        mark:Hide()
        reportError("hostility", "Cannot determine whether the nameplate is hostile.")
        return
    end
    local ok, enemy = pcall(UnitIsEnemy, "player", unit)
    if not ok then
        mark:Hide()
        reportError("hostility", enemy)
    elseif isSecret(enemy) then
        if mark.SetAlphaFromBoolean then
            local rendered, err = pcall(mark.SetAlphaFromBoolean, mark, enemy, 1, 0)
            if not rendered then
                mark:Hide()
                reportError("hostility", err)
            end
        else
            mark:Hide()
            reportError("hostility", "This client cannot display secret hostility checks.")
        end
    elseif enemy ~= true then
        mark:Hide()
    end
end

local function refreshSecretRows(mark, rows, resolved)
    mark.secretRows = mark.secretRows or {}
    for _, row in ipairs(mark.secretRows) do row:Hide() end
    for index, match in ipairs(rows or {}) do
        local row = mark.secretRows[index]
        if not row then
            row = CreateFrame("Frame", nil, mark)
            row.tex = row:CreateTexture(nil, "ARTWORK")
            row.tex:SetAllPoints(row)
            applyShieldArt(row.tex)
            row.tex:SetVertexColor(1, 1, 1)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row, "RIGHT", 3, 0)
            row.text:SetTextColor(1, 1, 1)
            mark.secretRows[index] = row
        end
        row:SetSize(options.markSize, options.markSize)
        row:ClearAllPoints()
        -- Fixed slots avoid inspecting secret visibility to pack the rows.
        row:SetPoint("TOP", mark, "TOP", 0,
            -(index - 1 + (resolved and 1 or 0)) * (options.markSize + 14))
        row.text:SetText(match.initials)
        row:Hide()
        if not row.SetAlphaFromBoolean then
            reportError("nameplate", "This client cannot display secret tank-target rows.")
        else
            local ok, err = pcall(row.SetAlphaFromBoolean, row, match.value, 1, 0)
            if ok then row:Show() else reportError("nameplate secret visibility", err) end
        end
    end
end

local function showMark(plate, currentTarget, showShield, secretMatch, initials, playerTank, unit, secretRows, threatUnit)
    local mark = getMark(plate)
    if secretMatch ~= nil and not mark.shield.SetAlphaFromBoolean then
        showShield, secretMatch = false, nil
        reportError("nameplate", "This client cannot display secret target matches.")
    end
    refreshMark(mark, currentTarget and (showShield or secretMatch ~= nil))
    mark.initialsText:SetText(initials)
    local displayThreat = currentTarget or options.allThreat
    refreshThreat(mark, displayThreat, playerTank, threatUnit)
    if secretMatch ~= nil then
        -- The game decides visibility from the secret boolean; Lua never reads it.
        mark.shield:Hide()
        local ok, err = pcall(mark.shield.SetAlphaFromBoolean, mark.shield, secretMatch, 1, 0)
        if ok then mark.shield:Show() else reportError("nameplate secret visibility", err) end
    else
        mark.shield:SetAlpha(1)
        if showShield then mark.shield:Show() else mark.shield:Hide() end
    end
    refreshSecretRows(mark, secretRows, showShield)
    mark:SetAlpha(1)
    if showShield or secretMatch ~= nil or (secretRows and #secretRows > 0)
        or (displayThreat and options.showThreat) then
        mark:Show()
    else
        mark:Hide()
    end
    filterHostile(mark, unit)
end

local function update()
    if not options.enabled then return end
    if not (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end

    if forceShields then
        for _, plate in ipairs(plates) do
            local mark = getMark(plate)
            refreshMark(mark, false)
            mark.initialsText:SetText("TEST")
            mark.shield:SetAlpha(1)
            mark.shield:Show()
            refreshSecretRows(mark)
            mark.threatText:Hide()
            mark.leadText:Hide()
            mark:SetAlpha(1)
            mark:Show()
        end
        return
    end

    local tanks = groupTanks()
    local targets = {}
    local playerTank = false
    for _, tank in ipairs(tanks) do
        local selfTank = tank == "player"
        if not selfTank then
            local okSame, same = pcall(UnitIsUnit, tank, "player")
            selfTank = okSame and not isSecret(same) and same == true
        end
        playerTank = playerTank or selfTank
        local unit = selfTank and "target" or (tank .. "target")
        local okGUID, guid = pcall(UnitGUID, unit)
        targets[#targets + 1] = {
            unit = unit, plate = getPlateForUnit(unit), initials = tankInitials(tank),
            guid = okGUID and plain(guid) and guid or nil,
        }
    end
    if UnitGroupRolesAssigned then
        local okRole, role = pcall(UnitGroupRolesAssigned, "player")
        if okRole and not isSecret(role) and type(role) == "string" then
            playerTankRole = role == "TANK"
        end
    end
    playerTank = playerTank or playerTankRole
    local myPlate = getPlateForUnit("target")
    for _, target in ipairs(targets) do
        if not target.plate and myPlate then
            local okSame, same = pcall(UnitIsUnit, "target", target.unit)
            if okSame then target.currentMatch = same end
        end
    end
    local tokenMap
    local plateMatches = {}
    for _, plate in ipairs(plates) do
        local unit = plateUnit(plate)
        if not unit then
            tokenMap = tokenMap or buildTokenMap()
            unit = tokenMap[plate]
        end

        local matches = { initials = {}, rows = {}, unit = unit }
        plateMatches[plate] = matches
        for index, target in ipairs(targets) do
            local show, secretMatch, decided = false, nil, false
            if target.plate then
                show, decided = plate == target.plate, true
            elseif plate == myPlate and target.currentMatch ~= nil then
                if isSecret(target.currentMatch) then
                    secretMatch = target.currentMatch
                else
                    show = target.currentMatch and true or false
                end
                decided = true
            elseif unit then
                if target.guid then
                    local okGUID, guid = pcall(UnitGUID, unit)
                    if okGUID and plain(guid) then
                        show, decided = guid == target.guid, true
                    end
                end
                if not decided then
                    local okSame, same = pcall(UnitIsUnit, unit, target.unit)
                    if okSame then
                        if plain(same) then
                            show = same and true or false
                        elseif same ~= nil then
                            secretMatch = same
                        end
                    end
                end
            end
            if show then
                matches.initials[index] = target.initials
                matches.filterUnit = target.unit
                target.matched = true
            elseif secretMatch ~= nil then
                if #targets == 1 then
                    matches.secret = secretMatch
                else
                    matches.rows[#matches.rows + 1] = { value = secretMatch, initials = target.initials }
                end
            end
        end
    end

    for index, target in ipairs(targets) do
        if not target.matched and myPlate then
            local okSame, same = pcall(UnitIsUnit, "target", target.unit)
            if okSame and plain(same) and same then
                local matches = plateMatches[myPlate]
                if not matches then
                    matches = { initials = {} }
                    plateMatches[myPlate] = matches
                end
                matches.initials[index] = target.initials
                matches.secret = nil
                target.matched = true
            end
        end
    end

    for plate, matches in pairs(plateMatches) do
        local initials = {}
        for index = 1, #targets do
            if matches.initials[index] then initials[#initials + 1] = matches.initials[index] end
        end
        local show = #initials > 0
        local currentTarget = plate == myPlate
        if show or matches.secret ~= nil or (matches.rows and #matches.rows > 0)
            or (options.showThreat and (options.allThreat or (#targets > 0 and currentTarget))) then
            local label = #targets == 1 and targets[1].initials or table.concat(initials, ", ")
            local filterUnit = currentTarget and "target" or matches.filterUnit or matches.unit
            local threatUnit = currentTarget and "target" or matches.unit
            showMark(plate, currentTarget, show, matches.secret, label, playerTank, filterUnit, matches.rows, threatUnit)
        elseif plate.sabotonTankMark then
            plate.sabotonTankMark:Hide()
        end
    end
end

local function safeUpdate()
    local ok, err = pcall(update)
    if not ok then
        reportError("update", err)
    end
end

local function setInferGroupTank(value)
    options.inferGroupTank = value
    if not value then lastHolderName, lastHolderTime = nil, 0 end
    safeUpdate()
end

local function printStatus()
    addon.Print("Tank target marks: " .. (options.enabled and "ON" or "off"))
    addon.Print("Forced shield diagnostic (session only): " .. (forceShields and "ON" or "off"))
    addon.Print("Hostile targets only: " .. (options.hostileOnly and "ON" or "off"))
    addon.Print("Solo pet counts as tank: " .. (options.petSoloTank and "ON" or "off"))
    addon.Print("Guess unassigned group tank: " .. (options.inferGroupTank and "ON" or "off"))
    addon.Print("Mark size: " .. tostring(options.markSize))
    addon.Print("Threat text: " .. (options.showThreat and "ON" or "off") .. " (" .. options.threatMode .. ")")
    addon.Print("Threat on all nameplates: " .. (options.allThreat and "ON" or "off"))
    addon.Print("Threat thresholds: " .. options.threatLow .. "/" .. options.threatHigh
        .. "%; tank lead: " .. options.tankThreatLow .. "/" .. options.tankThreatHigh .. "%.")
    addon.Print("Manually picked tank: " .. (pickedTankName or "none"))
    local tanks, reason = groupTanks()
    for _, tank in ipairs(tanks) do
        addon.Print("Current tank: " .. (tankIdentity(tank) or "?") .. " (" .. tank .. ", via " .. (reason or "?") .. ")")
    end
    if #tanks == 0 then
        addon.Print("Current tank: none detected")
    end
    if lastError then addon.Print("Last update error: " .. tostring(lastError)) end
end

local function setThreshold(tanking, lower, value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
        addon.Print("Threat thresholds must be finite numbers.")
        return
    end
    local lowKey = tanking and "tankThreatLow" or "threatLow"
    local highKey = tanking and "tankThreatHigh" or "threatHigh"
    local maximum = tanking and 500 or 100
    value = math.max(lower and 1 or 2, math.min(lower and maximum - 1 or maximum, math.floor(value)))
    if lower then
        options[lowKey] = value
        options[highKey] = math.max(options[highKey], value + 1)
    else
        options[highKey] = value
        options[lowKey] = math.min(options[lowKey], value - 1)
    end
end

local function thresholdOption(tanking, lower)
    local key = tanking and (lower and "tankThreatLow" or "tankThreatHigh")
        or (lower and "threatLow" or "threatHigh")
    return {
        type = "slider", key = key,
        label = (tanking and "Tank lead: " or "DPS threat: ") .. (lower and "lower threshold (%)" or "upper threshold (%)"),
        section = tanking and "Tank lead colors" or "DPS threat colors",
        dependsOn = "showThreat",
        tooltip = (tanking and "Red below the lower threshold, yellow through the upper threshold, green above."
            or "Green below the lower threshold, yellow through the upper threshold, red above.")
            .. " Restricted percentages use neutral white."
            .. " Moving a boundary past the other also adjusts the other boundary.",
        default = tanking and (lower and 120 or 150) or (lower and 50 or 80),
        min = lower and 1 or 2, max = tanking and (lower and 499 or 500) or (lower and 99 or 100),
        step = 1, format = "%d",
        get = function() return options[key] end,
        set = function(value) setThreshold(tanking, lower, value) end,
    }
end

-- Declarative schema consumed by the shared Options UI (src\Options.lua).
function TankTarget:GetOptionsSchema()
    return {
        name = "Tank Target",
        enabledKey = "enabled",
        options = {
            {
                type = "checkbox",
                key = "enabled",
                section = "General",
                label = "Enable Tank Target",
                tooltip = "Enable tank shields and optional threat labels. Show one neutral shield per target, with matching tanks' initials separated by commas. A pulse means you share that target, not that a tank holds aggro. Manual tank selection tracks only that tank.",
                default = true,
                get = function() return options.enabled end,
                set = function(value)
                    options.enabled = value
                    if not value then hideAllMarks() end
                end,
            },
            {
                type = "checkbox",
                key = "hostileOnly",
                section = "General",
                label = "Hostile targets only",
                tooltip = "Only show the shield, tank initials, and threat text on units the game identifies as enemies of you. Unknown hostility is hidden.",
                default = true,
                get = function() return options.hostileOnly end,
                set = function(value)
                    options.hostileOnly = value
                    safeUpdate()
                end,
            },
            {
                type = "checkbox",
                key = "inferGroupTank",
                section = "Tank detection",
                label = "Guess a tank when no group tank is assigned",
                tooltip = "When no manual, TANK-role, or main-tank assignment is available, infer one tank from threat (remembered briefly) or the only tank-capable class outside combat. Disable for groups without a tank. Solo pet handling is separate.",
                default = true,
                get = function() return options.inferGroupTank end,
                set = setInferGroupTank,
            },
            {
                type = "checkbox",
                key = "petSoloTank",
                section = "Tank detection",
                label = "Treat your pet as the tank while solo",
                tooltip = "When not in a group, mark your pet's target.",
                default = true,
                get = function() return options.petSoloTank end,
                set = function(value) options.petSoloTank = value end,
            },
            {
                type = "slider",
                key = "markSize",
                section = "Shields",
                label = "Mark size",
                tooltip = "Size of the shield icon in UI units.",
                default = 20,
                min = 12,
                max = 32,
                step = 1,
                format = "%d",
                get = function() return options.markSize end,
                set = function(value) options.markSize = value end,
            },
            {
                type = "checkbox", key = "showThreat", label = "Show your threat",
                section = "Threat",
                tooltip = "Show Threat 75% on your current target when a tank is detected, or on every plate with Show threat on all nameplates. Confirmed DPS aggro shows AGGRO; tanks holding aggro see Lead 140%. Unknown values show ?. Tank initials belong to the shield, not this percentage. Threat is never cached.",
                default = true,
                get = function() return options.showThreat end,
                set = function(value) options.showThreat = value end,
            },
            {
                type = "checkbox", key = "allThreat", label = "Show threat on all nameplates",
                section = "Threat", dependsOn = "showThreat",
                tooltip = "Requires Show your threat. Query your threat against each nameplate's own living, attackable unit, even without a detected tank. Objects, friendly units, and dead units have no threat label. Hostile-only filtering still applies. Unknown threat on eligible units shows ?.",
                default = false,
                get = function() return options.allThreat end,
                set = function(value)
                    options.allThreat = value
                    safeUpdate()
                end,
            },
            {
                type = "dropdown", key = "threatMode", label = "DPS threat percentage",
                section = "Threat", dependsOn = "showThreat",
                tooltip = "Scaled: 100% means you pull aggro. Raw: your threat relative to the current aggro holder. Tank lead always uses raw threat.",
                default = "scaled",
                choices = {
                    { value = "scaled", label = "Scaled (distance to pulling aggro)" },
                    { value = "raw", label = "Raw (relative to aggro holder)" },
                },
                get = function() return options.threatMode end,
                set = function(value)
                    if value ~= "scaled" and value ~= "raw" then
                        addon.Print("Threat mode must be scaled or raw.")
                        return
                    end
                    options.threatMode = value
                end,
            },
            thresholdOption(false, true),
            thresholdOption(false, false),
            thresholdOption(true, true),
            thresholdOption(true, false),
        },
    }
end

function TankTarget:OnEnable()
    self.frame = CreateFrame("Frame")
    local events = {
        "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "UNIT_PET",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    }
    for _, event in ipairs(events) do
        -- Registering an event this client lacks throws; guard each one.
        local ok, err = pcall(self.frame.RegisterEvent, self.frame, event)
        if not ok then reportError("event " .. event, err) end
    end
    self.frame:SetScript("OnEvent", safeUpdate)
    -- Events alone miss fast target swaps during pulls; keep a short ticker.
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(TICKER_INTERVAL, safeUpdate)
    end
end

function TankTarget:HandleCommand(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "status" then
        printStatus()
    elseif command == "testshields" then
        forceShields = not forceShields
        addon.Print("Forced shield diagnostic " .. (forceShields and "enabled" or "disabled")
            .. " (session only; bypasses tank matching and hostile filtering; requires module enabled).")
        safeUpdate()
    elseif command == "enable" then
        options.enabled = not options.enabled
        if not options.enabled then hideAllMarks() end
        addon.Print("Tank target marks " .. (options.enabled and "enabled" or "disabled") .. ".")
    elseif command == "pet" then
        options.petSoloTank = not options.petSoloTank
        addon.Print("Solo pet tank " .. (options.petSoloTank and "enabled" or "disabled") .. ".")
    elseif command == "guess" then
        setInferGroupTank(not options.inferGroupTank)
        addon.Print("Guess unassigned group tank " .. (options.inferGroupTank and "enabled" or "disabled") .. ".")
    elseif command == "hostile" then
        options.hostileOnly = not options.hostileOnly
        addon.Print("Hostile targets only " .. (options.hostileOnly and "enabled" or "disabled") .. ".")
        safeUpdate()
    elseif command == "threat" then
        options.showThreat = not options.showThreat
        addon.Print("Threat percentage " .. (options.showThreat and "enabled" or "disabled") .. ".")
        safeUpdate()
    elseif command == "allthreat" then
        options.allThreat = not options.allThreat
        addon.Print("Threat on all nameplates " .. (options.allThreat and "enabled" or "disabled")
            .. " (requires threat display enabled).")
        safeUpdate()
    elseif command == "threatmode" then
        if rest == "scaled" or rest == "raw" then
            options.threatMode = rest
            safeUpdate()
        else
            addon.Print("Usage: /saboton tanktarget threatmode <scaled|raw>")
        end
    elseif command == "thresholds" or command == "tankthresholds" then
        local low, high = string.match(rest, "^(%S+)%s+(%S+)$")
        low, high = tonumber(low), tonumber(high)
        local tanking = command == "tankthresholds"
        local maximum = tanking and 500 or 100
        if not low or not high or low ~= low or high ~= high or low < 1
            or high > maximum or low >= high or low ~= math.floor(low) or high ~= math.floor(high) then
            addon.Print("Usage: /saboton tanktarget " .. command .. " <lower> <upper> (integers 1-"
                .. maximum .. ", lower < upper)")
        else
            setThreshold(tanking, true, low)
            setThreshold(tanking, false, high)
            addon.Print("Threat thresholds set to " .. low .. "/" .. high .. "%.")
            safeUpdate()
        end
    elseif command == "size" then
        local size = tonumber(rest)
        if size and size >= 12 and size <= 32 then
            options.markSize = math.floor(size)
            addon.Print("Mark size set to " .. options.markSize .. ".")
        else
            addon.Print("Usage: /saboton tanktarget size <12-32>")
        end
    elseif command == "tank" then
        if rest == "" then
            addon.Print("Manually picked tank: " .. (pickedTankName or "none"))
            addon.Print("Usage: /saboton tanktarget tank <name|clear>")
        elseif string.lower(rest) == "clear" then
            pickedTankName = nil
            addon.Print("Manual tank pick cleared; automatic detection resumes.")
        else
            pickedTankName = rest
            addon.Print("Tank manually set to " .. rest .. " for this session (use 'tank clear' to undo).")
        end
        safeUpdate()
    elseif command == "debug" then
        DEBUG = not DEBUG
        addon.Print("Debug " .. (DEBUG and "enabled" or "disabled") .. ".")
    else
        addon.Print("Commands: /saboton tanktarget status, enable, hostile, guess, pet, size <12-32>, tank <name|clear>, debug, testshields, threat, allthreat, threatmode <scaled|raw>, thresholds <lower> <upper>, tankthresholds <lower> <upper>")
    end
end

addon.RegisterModule("tanktarget", TankTarget)
