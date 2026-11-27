local _, addon = ...

local ChatTabs = {}
local enabled = false
local hideInput = false
local font = "default"
local customFontSize = false
local fontSize = 12
local driver
local elapsed = 0
local POLL_INTERVAL = 0.1
local FONT_CHOICES = {
    { value = "default", label = "Default" },
    { value = "friz", label = "Friz Quadrata" },
    { value = "arial", label = "Arial Narrow" },
    { value = "morpheus", label = "Morpheus" },
    { value = "skurri", label = "Skurri" },
}
local FONT_PATHS = {
    friz = "Fonts\\FRIZQT__.TTF",
    arial = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF",
    skurri = "Fonts\\SKURRI.TTF",
}
local originalFonts = {}
local editBoxStates = {}
local reportedFontErrors = {}

local function isMouseOver(frame)
    return frame and frame.IsMouseOver and frame:IsMouseOver()
end

local function reportFontError(message)
    if not reportedFontErrors[message] then
        reportedFontErrors[message] = true
        addon.Print("Chat Tabs: " .. message)
    end
end

local function isActiveChatWindow(index, frame)
    if FCF_IsChatWindowIndexActive then
        return FCF_IsChatWindowIndexActive(index)
    end
    if GetChatWindowInfo then
        local _, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
        return shown or docked or frame.isDocked
    end
    return frame.isDocked or (frame.IsShown and frame:IsShown())
end

local function sameFontPath(left, right)
    return type(left) == "string" and type(right) == "string"
        and left:lower():gsub("/", "\\") == right:lower():gsub("/", "\\")
end

local function updateFonts()
    local customizing = font ~= "default" or customFontSize
    local count = tonumber(NUM_CHAT_WINDOWS) or 10
    for index = 1, count do
        local frame = _G["ChatFrame" .. index]
        if frame and isActiveChatWindow(index, frame) and (customizing or originalFonts[frame]) then
            if not frame.GetFont or not frame.SetFont then
                reportFontError("chat window " .. index .. " does not support font changes.")
            else
                local currentPath, currentSize, currentFlags = frame:GetFont()
                if currentPath and currentSize then
                    local original = originalFonts[frame]
                    if not original then
                        original = { path = currentPath, size = currentSize, flags = currentFlags }
                        originalFonts[frame] = original
                    end
                    local path = FONT_PATHS[font] or original.path
                    local size = customFontSize and fontSize or original.size
                    if not sameFontPath(currentPath, path) or currentSize ~= size or currentFlags ~= original.flags then
                        frame:SetFont(path, size, original.flags)
                        local appliedPath, appliedSize = frame:GetFont()
                        if not sameFontPath(appliedPath, path) or appliedSize ~= size then
                            reportFontError("could not apply the selected font or size to chat window " .. index .. ".")
                        elseif not customizing then
                            originalFonts[frame] = nil
                        end
                    elseif not customizing then
                        originalFonts[frame] = nil
                    end
                else
                    reportFontError("could not read the font of chat window " .. index .. ".")
                end
            end
        end
    end
end

local function updateEditBoxes()
    local count = tonumber(NUM_CHAT_WINDOWS) or 10
    for index = 1, count do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and editBox.SetAlpha then
            local state = editBoxStates[editBox]
            if not state then
                state = { alpha = editBox.GetAlpha and editBox:GetAlpha() or 1 }
                editBoxStates[editBox] = state
                if editBox.HookScript then
                    editBox:HookScript("OnEditFocusGained", function()
                        state.focused = true
                        editBox:SetAlpha(state.alpha)
                    end)
                    editBox:HookScript("OnEditFocusLost", function()
                        state.focused = false
                        editBox:SetAlpha(hideInput and 0 or state.alpha)
                    end)
                end
            end
            if editBox.HasFocus then
                state.focused = editBox:HasFocus()
            end
            local alpha = hideInput and not state.focused and 0 or state.alpha
            if not editBox.GetAlpha or editBox:GetAlpha() ~= alpha then
                editBox:SetAlpha(alpha)
            end
        end
    end
end

local function updateTabs()
    local count = tonumber(NUM_CHAT_WINDOWS) or 10
    for index = 1, count do
        local chatFrame = _G["ChatFrame" .. index]
        local tab = _G["ChatFrame" .. index .. "Tab"]
        if tab and tab.SetAlpha then
            local shown = not enabled or isMouseOver(chatFrame) or isMouseOver(tab)
            if tab.sabotonChatTabsShown ~= shown then
                tab:SetAlpha(shown and 1 or 0)
                tab.sabotonChatTabsShown = shown
            end
        end
    end
    updateFonts()
    updateEditBoxes()
end

local function setFont(value)
    if value ~= "default" and not FONT_PATHS[value] then
        reportFontError("unknown chat message font: " .. tostring(value) .. ".")
        return false
    end
    font = value
    updateFonts()
    return true
end

local function setFontSize(value)
    if type(value) ~= "number" or value ~= value or value < 8 or value > 24 or value % 1 ~= 0 then
        reportFontError("chat message font size must be an integer from 8 to 24.")
        return false
    end
    fontSize = value
    updateFonts()
    return true
end

function ChatTabs:GetOptionsSchema()
    return {
        name = "Chat Tabs",
        options = {
            {
                type = "checkbox",
                key = "enabled",
                label = "Hide chat tabs until hovered",
                tooltip = "Hide each chat window's tab until the cursor is over that window or its tab.",
                default = false,
                get = function() return enabled end,
                set = function(value)
                    enabled = value
                    updateTabs()
                end,
            },
            {
                type = "checkbox",
                key = "hideInput",
                label = "Hide chat input box until typing",
                tooltip = "Hide each chat input box while it is not focused. Clicking the input area or using the chat key shows it while you type.",
                default = false,
                get = function() return hideInput end,
                set = function(value)
                    hideInput = value
                    updateEditBoxes()
                end,
            },
            {
                type = "dropdown",
                key = "font",
                label = "Chat message font",
                tooltip = "Choose a font for chat messages, or use each window's original font.",
                default = "default",
                choices = FONT_CHOICES,
                get = function() return font end,
                set = setFont,
            },
            {
                type = "checkbox",
                key = "customFontSize",
                label = "Use custom chat message font size",
                tooltip = "Override the font size of chat messages in all chat windows.",
                default = false,
                get = function() return customFontSize end,
                set = function(value)
                    customFontSize = value
                    updateFonts()
                end,
            },
            {
                type = "slider",
                key = "fontSize",
                label = "Chat message font size",
                tooltip = "Set the font size for chat messages in all chat windows.",
                dependsOn = "customFontSize",
                min = 8,
                max = 24,
                step = 1,
                format = "%d",
                default = 12,
                get = function() return fontSize end,
                set = setFontSize,
            },
        },
    }
end

function ChatTabs:OnEnable()
    updateEditBoxes()
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < POLL_INTERVAL then return end
        elapsed = 0
        updateTabs()
    end)
    updateTabs()
end

function ChatTabs:HandleCommand(message)
    message = string.lower((message or ""):match("^%s*(.-)%s*$"))
    local command, value = message:match("^(%S+)%s+(%S+)$")
    if command == "font" then
        if setFont(value) then addon.Print("Chat message font: " .. value .. ".") end
        return
    elseif command == "size" then
        if value == "default" then
            customFontSize = false
            updateFonts()
            addon.Print("Chat message size restored to each window's original size.")
        elseif setFontSize(tonumber(value)) then
            customFontSize = true
            updateFonts()
            addon.Print("Chat message font size: " .. fontSize .. ".")
        end
        return
    end
    if message == "" or message == "toggle" then
        enabled = not enabled
    elseif message == "enable" then
        enabled = true
    elseif message == "disable" then
        enabled = false
    elseif message == "status" then
        addon.Print("Chat-tab hiding " .. (enabled and "enabled" or "disabled") .. ".")
        return
    else
        addon.Print("Usage: /saboton chattabs [enable|disable|toggle|status|font <default|friz|arial|morpheus|skurri>|size <default|8-24>]")
        return
    end
    updateTabs()
    addon.Print("Chat-tab hiding " .. (enabled and "enabled" or "disabled") .. ".")
end

addon.RegisterModule("chattabs", ChatTabs)
