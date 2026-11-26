local _, addon = ...

local WowheadLink = {}
local popup
local menuEnabled = false
local menuErrors = {}

function WowheadLink:GetOptionsSchema()
    return {
        name = "Wowhead Creature Link",
        root = true,
        options = {
            {
                type = "checkbox",
                key = "menuEnabled",
                label = "Show Wowhead link in creature menus",
                tooltip = "Add a copyable Wowhead Forever link to creature target and focus portrait menus.",
                default = false,
                get = function() return menuEnabled end,
                set = function(value)
                    menuEnabled = value
                    if value then
                        for _, message in ipairs(menuErrors) do addon.Print(message) end
                    end
                end,
            },
        },
    }
end

local function creatureID(unit)
    if type(UnitGUID) ~= "function" then return nil, "UnitGUID is unavailable." end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil, "Could not read the unit GUID: " .. tostring(guid) end
    if issecretvalue and issecretvalue(guid) then return nil, "The unit GUID is restricted." end
    if type(guid) ~= "string" then return nil, "No readable unit GUID is available." end
    if not guid:match("^Creature%-") then return nil, "The unit is not a creature.", true end
    local id = guid:match("^Creature%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-[^%-]+$")
    if not id or not id:match("[1-9]") then return nil, "The creature GUID has an unrecognized format." end
    return id
end

local function showLink(id)
    if not popup then
        popup = CreateFrame("Frame", "SabotonWowheadLinkPopup", UIParent, "BackdropTemplate")
        popup:SetSize(430, 110)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Copy Wowhead link (Ctrl+C)")

        popup.editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        popup.editBox:SetSize(370, 24)
        popup.editBox:SetPoint("CENTER", 0, -5)
        popup.editBox:SetAutoFocus(false)
        popup.editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        popup.editBox:SetScript("OnEnterPressed", function() popup:Hide() end)
        popup:SetScript("OnHide", function() popup.editBox:ClearFocus() end)

        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        table.insert(UISpecialFrames, "SabotonWowheadLinkPopup")
    end
    popup.editBox:SetText("https://www.wowhead.com/forever/npc=" .. id)
    popup:Show()
    popup.editBox:SetFocus()
    popup.editBox:HighlightText()
end

local function openForUnit(unit)
    local id, reason = creatureID(unit)
    if not id then
        addon.Print("Wowhead link: " .. reason)
        return
    end
    showLink(id)
end

local function addMenuItem(owner, root, context)
    if not menuEnabled then return end
    if type(context) ~= "table" then return end
    local unit = context.unit
    if not ((unit == "target" and context.fromTargetFrame) or
            (unit == "focus" and context.fromFocusFrame)) then return end
    local id, reason, notCreature = creatureID(unit)
    if notCreature then return end
    root:CreateDivider()
    root:CreateButton("Copy Wowhead link", function()
        if not menuEnabled then return end
        if id then
            showLink(id)
        else
            addon.Print("Wowhead link: " .. reason)
        end
    end)
end

function WowheadLink:OnEnable()
    menuErrors = {}
    if not Menu or type(Menu.ModifyMenu) ~= "function" then
        menuErrors[#menuErrors + 1] = "Wowhead link: portrait menus are unavailable; use /saboton wowhead."
        return
    end
    for _, tag in ipairs({ "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }) do
        local ok, err = pcall(Menu.ModifyMenu, tag, addMenuItem)
        if not ok then
            menuErrors[#menuErrors + 1] = "Wowhead link: could not register " .. tag .. ": " .. tostring(err) .. ". Use /saboton wowhead."
        end
    end
end

function WowheadLink:HandleCommand(message)
    if message ~= "" then
        addon.Print("Usage: /saboton wowhead (shows a link for your target to copy).")
        return
    end
    openForUnit("target")
end

addon.RegisterModule("wowhead", WowheadLink)
