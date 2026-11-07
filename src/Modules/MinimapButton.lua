local ADDON_NAME, addon = ...

-- Draggable minimap button that opens the shared Options panel.
local MinimapButton = {}

local ICON_TEXTURE = "Interface\\Icons\\Spell_Nature_ThunderClap"
local RADIUS = 80
local DEFAULT_ANGLE = 225

local shown = true
local angle = DEFAULT_ANGLE

local function updatePosition(button)
    local x = math.cos(math.rad(angle)) * RADIUS
    local y = math.sin(math.rad(angle)) * RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function createButton()
    local button = CreateFrame("Button", "SabotonEssentialsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetSize(20, 20)
    -- Matches the border's TOPLEFT anchor below so the icon sits inside the ring's hole
    -- instead of centering on the button (which sits ~11px off from the ring's visual center).
    icon:SetPoint("TOPLEFT", 6, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            angle = math.deg(math.atan2(py - my, px - mx))
            updatePosition(button)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function()
        addon.modules.options:HandleCommand()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Saboton Essentials")
        GameTooltip:AddLine("Click to open options", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

-- Declarative schema consumed by the shared Options UI (src\Options.lua); no Settings-API code lives here.
function MinimapButton:GetOptionsSchema()
    return {
        name = "Minimap Button",
        options = {
            {
                type = "checkbox",
                key = "showButton",
                label = "Show minimap button",
                tooltip = "Show a draggable minimap button that opens the options panel.",
                default = true,
                get = function() return shown end,
                set = function(value)
                    shown = value
                    self.button:SetShown(shown)
                end,
            },
        },
    }
end

function MinimapButton:OnEnable()
    self.button = createButton()
    updatePosition(self.button)
    self.button:SetShown(shown)
end

function MinimapButton:HandleCommand()
    shown = not shown
    self.button:SetShown(shown)
    addon.Print("Minimap button " .. (shown and "shown" or "hidden") .. ".")
end

addon.RegisterModule("minimap", MinimapButton)
