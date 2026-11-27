local frames = {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    frames[#frames + 1] = frame
    return frame
end

local function chatFrame(path, size, flags)
    return {
        hovered = false,
        path = path or "Fonts\\CHAT.TTF",
        size = size or 14,
        flags = flags or "OUTLINE",
        active = true,
        writes = 0,
        IsMouseOver = function(self) return self.hovered end,
        GetFont = function(self) return self.path, self.size, self.flags end,
        SetFont = function(self, path, size, fontFlags)
            self.path, self.size, self.flags = path, size, fontFlags
            self.writes = self.writes + 1
        end,
    }
end

local function tab()
    return {
        hovered = false,
        IsMouseOver = function(self) return self.hovered end,
        SetAlpha = function(self, value) self.alpha = value end,
    }
end

NUM_CHAT_WINDOWS = 2
ChatFrame1, ChatFrame2 = chatFrame(), chatFrame("Fonts\\OTHER.TTF", 18, "THICKOUTLINE")
function FCF_IsChatWindowIndexActive(index)
    local frame = _G["ChatFrame" .. index]
    return frame and frame.active
end
ChatFrame1Tab, ChatFrame2Tab = tab(), tab()

local function tabText()
    return {
        path = "Fonts\\BASE.TTF",
        size = 12,
        flags = "OUTLINE",
        GetFont = function(self) return self.path, self.size, self.flags end,
        SetFont = function(self, path, size, flags)
            self.path, self.size, self.flags = path, size, flags
            return true
        end,
    }
end
local firstTabText, secondTabText = tabText(), tabText()
function ChatFrame1Tab:GetFontString() return firstTabText end
ChatFrame2Tab.Text = secondTabText

local function editBox()
    return {
        alpha = 1,
        focused = false,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, value) self.alpha = value end,
        HasFocus = function(self) return self.focused end,
        HookScript = function(self, name, callback) self.hooks = self.hooks or {} self.hooks[name] = callback end,
    }
end
ChatFrame1EditBox, ChatFrame2EditBox = editBox(), editBox()

local addon = { modules = {}, messages = {} }
function addon.RegisterModule(name, module) addon.modules[name] = module end
function addon.Print(message) addon.messages[#addon.messages + 1] = message end
assert(loadfile("src/Modules/ChatTabs.lua"))("SabotonEssentials", addon)

local module = addon.modules.chattabs
module:OnEnable()
assert(ChatFrame1Tab.alpha == 1 and ChatFrame2Tab.alpha == 1, "chat-tab hiding is off by default")
assert(firstTabText.path == "Fonts\\BASE.TTF" and firstTabText.size == 12,
    "font settings preserve the client's defaults")
assert(ChatFrame1.writes == 0 and ChatFrame2.writes == 0, "default settings do not touch chat fonts")
local options = module:GetOptionsSchema().options
assert(options[1].default == false and options[2].default == false
    and options[3].default == "default" and options[4].default == false and options[5].default == 12)
assert(ChatFrame1EditBox.alpha == 1 and ChatFrame2EditBox.alpha == 1, "input hiding is off by default")
options[2].set(true)
assert(ChatFrame1EditBox.alpha == 0 and ChatFrame2EditBox.alpha == 0, "inactive input boxes hide when enabled")
ChatFrame1EditBox.focused = true
ChatFrame1EditBox.hooks.OnEditFocusGained()
assert(ChatFrame1EditBox.alpha == 1 and ChatFrame2EditBox.alpha == 0, "focused input remains visible")
ChatFrame1EditBox.focused = false
ChatFrame1EditBox.hooks.OnEditFocusLost()
assert(ChatFrame1EditBox.alpha == 0, "input hides when typing ends")
options[2].set(false)
assert(ChatFrame1EditBox.alpha == 1 and ChatFrame2EditBox.alpha == 1, "disabling input hiding restores alpha")
options[1].set(true)
assert(ChatFrame1Tab.alpha == 0 and ChatFrame2Tab.alpha == 0, "enabling the option hides tabs")
local driver = frames[1]

ChatFrame1.hovered = true
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame1Tab.alpha == 1 and ChatFrame2Tab.alpha == 0, "hovering one window shows only its tab")

ChatFrame1.hovered, ChatFrame1Tab.hovered = false, true
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame1Tab.alpha == 1, "hovering the tab keeps it visible")

ChatFrame1Tab.hovered = false
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame1Tab.alpha == 0, "tabs hide after leaving the window")

options[1].set(false)
assert(ChatFrame1Tab.alpha == 1 and ChatFrame2Tab.alpha == 1, "disabling the feature shows all tabs")
module:HandleCommand("toggle")
assert(ChatFrame1Tab.alpha == 0 and ChatFrame2Tab.alpha == 0, "slash toggle enables hiding without cursor")
module:HandleCommand("STATUS")
assert(addon.messages[#addon.messages]:find("enabled", 1, true), "status reports the setting")
local messagesBeforeFontChange = #addon.messages
options[3].set("arial")
assert(#addon.messages == messagesBeforeFontChange, "a successful SetFont with no return value must not report failure")
assert(ChatFrame1.path == "Fonts\\ARIALN.TTF" and ChatFrame1.size == 14 and ChatFrame1.flags == "OUTLINE")
assert(ChatFrame2.path == "Fonts\\ARIALN.TTF" and ChatFrame2.size == 18 and ChatFrame2.flags == "THICKOUTLINE",
    "font choice changes chat messages without changing per-window sizes or flags")
options[5].set(16)
assert(ChatFrame1.size == 14, "size changes stay inactive until opted in")
options[4].set(true)
assert(ChatFrame1.size == 16 and ChatFrame2.size == 16, "custom size applies to all chat windows")
assert(firstTabText.path == "Fonts\\BASE.TTF" and firstTabText.size == 12 and secondTabText.size == 12,
    "message settings do not alter tab labels")
options[3].set("default")
assert(ChatFrame1.path == "Fonts\\CHAT.TTF" and ChatFrame1.size == 16 and ChatFrame2.path == "Fonts\\OTHER.TTF",
    "default font choice restores the client's face while retaining selected size")

NUM_CHAT_WINDOWS = 3
ChatFrame3 = chatFrame("Fonts\\THIRD.TTF", 11)
ChatFrame3Tab = tab()
ChatFrame3.active = false
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame3.size == 11 and ChatFrame3.writes == 0, "unused chat frames are not modified")
ChatFrame3.active = true
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame3.size == 16 and ChatFrame3.path == "Fonts\\THIRD.TTF",
    "late-created chat windows receive the selected size")
ChatFrame3.active = false
options[4].set(false)
assert(ChatFrame1.size == 14 and ChatFrame2.size == 18 and ChatFrame3.size == 16,
    "disabling restores active windows without touching inactive frames")
FCF_IsChatWindowIndexActive = nil
function GetChatWindowInfo(index)
    local frame = _G["ChatFrame" .. index]
    return nil, nil, nil, nil, nil, nil, frame.active, nil, false
end
ChatFrame3.active = true
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame3.size == 11, "a window restored after becoming active uses its original size")
ChatFrame1.size = 17
driver.scripts.OnUpdate(driver, 0.1)
assert(ChatFrame1.size == 17, "client font changes remain intact with overrides disabled")
options[3].set("invalid")
assert(options[3].get() == "default" and addon.messages[#addon.messages]:find("unknown chat message font", 1, true))
module:HandleCommand("size 20")
assert(ChatFrame1.size == 20 and options[4].get(), "slash command enables custom size")
module:HandleCommand("size default")
assert(ChatFrame1.size == 17 and not options[4].get(), "slash command restores original sizes")
module:HandleCommand("font morpheus")
assert(ChatFrame1.path == "Fonts\\MORPHEUS.TTF", "slash font command changes chat messages")
module:HandleCommand("font default")
function ChatFrame1:SetFont() end
options[4].set(true)
assert(addon.messages[#addon.messages]:find("could not apply", 1, true), "rejected font changes are reported")
local count = #addon.messages
driver.scripts.OnUpdate(driver, 0.1)
assert(#addon.messages == count, "repeated font failures do not spam chat")

print("Chat tab tests passed")
