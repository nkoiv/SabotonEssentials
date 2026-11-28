local ADDON_NAME, addon = ...

local TimerBars = {}
addon.TimerBars = TimerBars

TimerBars.FLASH_SECONDS = 1.5
TimerBars.SOUNDS = {
    { key = "none", label = "No sound", silent = true },
    { key = "ding", label = "Bell chime (may be up)", path = "Interface\\AddOns\\SabotonEssentials\\Media\\clear-bell-chime.mp3" },
    { key = "thud", label = "Impact thud (gone / taken)", path = "Interface\\AddOns\\SabotonEssentials\\Media\\impact-thud.mp3" },
    { key = "kaching", label = "Ka-ching!", path = "Interface\\AddOns\\SabotonEssentials\\Media\\kaching.mp3" },
    { key = "squeak", label = "Squeaky Toy", path = "Interface\\AddOns\\SabotonEssentials\\Media\\squeak.mp3" },
    { key = "huagh", label = "HUAGH", path = "Interface\\AddOns\\SabotonEssentials\\Media\\HumanMaleAggroA.ogg" },
}

function TimerBars.Create(parent, label, width, height, orientation)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetAllPoints()
    bar:SetFrameLevel(math.max(holder:GetFrameLevel() - 1, 0))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetDrawLayer("BACKGROUND")
    bar:SetOrientation(orientation)
    holder.bar = bar
    for _, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = holder:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0, 0, 0, 0.8)
        if point == "TOP" then
            edge:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", -1, 0)
            edge:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 1, 0)
            edge:SetHeight(1)
        elseif point == "BOTTOM" then
            edge:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -1, 0)
            edge:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 1, 0)
            edge:SetHeight(1)
        elseif point == "LEFT" then
            edge:SetPoint("TOPRIGHT", holder, "TOPLEFT", 0, 1)
            edge:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", 0, -1)
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPLEFT", holder, "TOPRIGHT", 0, 1)
            edge:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 0, -1)
            edge:SetWidth(1)
        end
    end
    local flash = holder:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1, 1, 1, 0.6)
    flash:Hide()
    holder.flash = flash
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    holder.text = text
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText(label)
    holder.title = title
    return holder
end

function TimerBars.Flash(holder)
    holder.flash:Show()
    holder.flash:SetAlpha(0.9)
    UIFrameFadeOut(holder.flash, TimerBars.FLASH_SECONDS, 0.9, 0)
end

function TimerBars.Update(holder, name, duration, elapsed)
    local frac = duration > 0 and math.min(elapsed / duration, 1) or 1
    holder.bar:SetValue(frac)
    holder.bar:SetStatusBarColor(0.2, 0.6, 1)
    local remaining = math.ceil(math.max(duration - elapsed, 0))
    holder.text:SetText(name .. " " .. string.format("%d:%02d", math.floor(remaining / 60), remaining % 60))
end

local movableHandles, modifierFrame = {}, nil

function TimerBars.RefreshMovable(handle)
    local config = movableHandles[handle]
    if config then
        handle:EnableMouse(config.keepMouse or not config.isLocked() or (IsAltKeyDown and IsAltKeyDown()) or config.dragging == true)
    end
end

function TimerBars.MakeMovable(frame, isLocked, savePosition, dragHandle, keepMouse)
    local handle = dragHandle or frame
    local config = { isLocked = isLocked, dragging = false, keepMouse = keepMouse }
    movableHandles[handle] = config
    if not modifierFrame then
        modifierFrame = CreateFrame("Frame")
        modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
        modifierFrame:SetScript("OnEvent", function()
            for registered in pairs(movableHandles) do TimerBars.RefreshMovable(registered) end
        end)
    end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    TimerBars.RefreshMovable(handle)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if (not isLocked() or (IsAltKeyDown and IsAltKeyDown())) and not (InCombatLockdown and InCombatLockdown()) then
            config.dragging = true
            frame:StartMoving()
        end
    end)
    handle:SetScript("OnDragStop", function()
        if not config.dragging then return end
        config.dragging = false
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if x and y and parentX and parentY then savePosition(x - parentX, y - parentY) end
        TimerBars.RefreshMovable(handle)
        if addon.SaveSettings then addon.SaveSettings() end
    end)
end

function TimerBars.RefreshTextAnchor(anchor)
    if not anchor or not anchor:IsShown() or movableHandles[anchor].dragging then return end
    local x, y = anchor.getPosition()
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function TimerBars.ToggleTextAnchor(anchor, label, getPosition, setPosition)
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(260, 42)
        anchor:SetFrameStrata("DIALOG")
        local background = anchor:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.1, 0.3, 0.5, 0.9)
        local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("CENTER")
        text:SetText(label .. "\nAlt + left-drag (out of combat)")
        anchor.getPosition = getPosition
        TimerBars.MakeMovable(anchor, function() return true end, function(x, y)
            setPosition(x, y)
            TimerBars.RefreshTextAnchor(anchor)
        end)
        anchor:Hide()
    end
    if anchor:IsShown() then anchor:Hide()
    else anchor:Show() TimerBars.RefreshTextAnchor(anchor) end
    return anchor
end
