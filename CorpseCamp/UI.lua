-- CorpseCamp UI: a draggable minimap button and the camp panel.
-- Every button goes through ns.Actions (CorpseCamp.lua), the same code as /ccamp.
-- Refreshed by the scan driver through ns.RefreshUI, so there's no second timer.

local addonName, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DEFAULT_ANGLE = 200
local IDLE_LABEL = "not camping"
local STATE_COLOR = {
    idle    = { 0.55, 0.55, 0.55 },
    waiting = { 0.80, 0.80, 0.80 },
    dead    = { 1.00, 0.82, 0.00 },
    gone    = { 0.45, 0.70, 1.00 },
    alive   = { 1.00, 0.20, 0.20 },
}
local ACCENT = { 0.55, 0.08, 0.08 }

local function db()
    CorpseCampDB = CorpseCampDB or {}
    CorpseCampDB.minimap = CorpseCampDB.minimap or { angle = DEFAULT_ANGLE }
    return CorpseCampDB
end

---------------------------------------------------------------------------
-- Minimap geometry (pure; tested)
---------------------------------------------------------------------------
-- Degrees (0 = east, counter-clockwise) of the cursor around the minimap centre.
function ns.CursorAngle(cx, cy, px, py)
    return math.deg(math.atan2(py - cy, px - cx)) % 360
end

-- Button centre offset from the minimap centre for an angle and radius.
function ns.MinimapOffset(angle, radius)
    local a = math.rad(angle)
    return math.cos(a) * radius, math.sin(a) * radius
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mm = CreateFrame("Button", "CorpseCampMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetPoint("TOPLEFT")
local mmBackground = mm:CreateTexture(nil, "BACKGROUND")
mmBackground:SetSize(20, 20)
mmBackground:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBackground:SetPoint("TOPLEFT", 7, -5)
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetTexture(ICON)
mmIcon:SetPoint("TOPLEFT", 7, -6)

local function placeMinimapButton()
    local angle = (CorpseCampDB and CorpseCampDB.minimap and CorpseCampDB.minimap.angle) or DEFAULT_ANGLE
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    local x, y = ns.MinimapOffset(angle, radius)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
placeMinimapButton()

local function followCursor()
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    db().minimap.angle = ns.CursorAngle(cx, cy, px / scale, py / scale)
    placeMinimapButton()
end

mm:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:LockHighlight()
    self:SetScript("OnUpdate", followCursor)
end)
mm:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end)
mm:SetScript("OnClick", function(_, button)
    if button == "RightButton" then ns.Actions.CampTarget() else ns.TogglePanel() end
end)
mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("CorpseCamp", 1, 0.3, 0.3)
    GameTooltip:AddLine(ns.Actions.Status() or "Not camping anyone", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open panel", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: camp your target", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "CorpseCampPanel", UIParent)
panel:SetSize(300, 240)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
panel:SetFrameStrata("DIALOG")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(true)
end)
panel:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "CorpseCampPanel") end  -- Esc closes it

local function fill(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Background and 1px accent border (no BackdropTemplate dependency).
fill(panel, "BACKGROUND", 0.05, 0.05, 0.07, 0.94):SetAllPoints()
for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local t = fill(panel, "BORDER", ACCENT[1], ACCENT[2], ACCENT[3], 1)
    t:SetPoint(edge[1]) ; t:SetPoint(edge[2])
    if edge[3] then t:SetWidth(edge[3]) else t:SetHeight(edge[4]) end
end

-- Header
local header = fill(panel, "ARTWORK", ACCENT[1] * 0.6, ACCENT[2] * 0.6, ACCENT[3] * 0.6, 0.95)
header:SetPoint("TOPLEFT", 1, -1) ; header:SetPoint("TOPRIGHT", -1, -1) ; header:SetHeight(28)
local headerIcon = panel:CreateTexture(nil, "OVERLAY")
headerIcon:SetSize(18, 18) ; headerIcon:SetTexture(ICON) ; headerIcon:SetPoint("TOPLEFT", 8, -6)
local title = panel:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT, 14, "OUTLINE") ; title:SetTextColor(1, 0.85, 0.85)
title:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0) ; title:SetText("CorpseCamp")
local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 1)

-- Status card
local card = fill(panel, "ARTWORK", 0.10, 0.10, 0.13, 1)
card:SetPoint("TOPLEFT", 10, -38) ; card:SetPoint("TOPRIGHT", -10, -38) ; card:SetHeight(64)
local stripe = fill(panel, "OVERLAY", 1, 1, 1, 1)
stripe:SetPoint("TOPLEFT", card, "TOPLEFT") ; stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT") ; stripe:SetWidth(3)

local nameText = panel:CreateFontString(nil, "OVERLAY")
nameText:SetFont(FONT, 15, "OUTLINE") ; nameText:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
nameText:SetJustifyH("LEFT") ; nameText:SetWidth(170)
local stateText = panel:CreateFontString(nil, "OVERLAY")
stateText:SetFont(FONT, 12, "") ; stateText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
local timerText = panel:CreateFontString(nil, "OVERLAY")
timerText:SetFont(FONT, 26, "OUTLINE") ; timerText:SetPoint("RIGHT", card, "RIGHT", -12, 0)
timerText:SetJustifyH("RIGHT")

-- Buttons
local function button(label, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 24) ; b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local campTargetButton = button("Camp target", 136, function() ns.Actions.CampTarget() end)
campTargetButton:SetPoint("TOPLEFT", 10, -112)
local stopButton = button("Stop", 136, function() ns.Actions.Stop() end)
stopButton:SetPoint("TOPRIGHT", -10, -112)

local nameBox = CreateFrame("EditBox", "CorpseCampNameBox", panel, "InputBoxTemplate")
nameBox:SetSize(180, 22) ; nameBox:SetPoint("TOPLEFT", 16, -146)
nameBox:SetAutoFocus(false) ; nameBox:SetMaxLetters(60)
local placeholder = nameBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
placeholder:SetPoint("LEFT", 2, 0) ; placeholder:SetText("Player name")
local function campFromBox()
    local text = nameBox:GetText() or ""
    if text:match("%S") then ns.Actions.CampName(text) end
    nameBox:SetText("") ; nameBox:ClearFocus()
end
nameBox:SetScript("OnEnterPressed", campFromBox)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
nameBox:SetScript("OnTextChanged", function(self)
    if (self:GetText() or "") == "" then placeholder:Show() else placeholder:Hide() end
end)
local campNameButton = button("Camp", 82, campFromBox)
campNameButton:SetPoint("TOPRIGHT", -10, -145)

local testButton = button("Test alert", 136, function() ns.Actions.Test() end)
testButton:SetPoint("TOPLEFT", 10, -180)
local setupButton = button("Nameplate setup", 136, function() ns.Actions.SetupNameplates() end)
setupButton:SetPoint("TOPRIGHT", -10, -180)

local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOM", 0, 12) ; hint:SetWidth(280)
hint:SetText("Target key: Key Bindings > AddOns > CorpseCamp")

---------------------------------------------------------------------------
-- Refresh (called from the scan driver ~5x/s and on show)
---------------------------------------------------------------------------
function ns.RefreshUI(now)
    local core = ns.core
    local state = core.state
    local color = STATE_COLOR[state] or STATE_COLOR.idle

    mmIcon:SetDesaturated(state == "idle")
    if state == "alive" then mmIcon:SetVertexColor(1, 0.35, 0.35) else mmIcon:SetVertexColor(1, 1, 1) end

    if not panel:IsShown() then return end
    nameText:SetText(core.name or "Nobody")
    stateText:SetText(ns.Core.LABELS[state] or IDLE_LABEL)
    stateText:SetTextColor(color[1], color[2], color[3])
    stripe:SetColorTexture(color[1], color[2], color[3], 1)
    timerText:SetText(core.since and ns.Core.Clock(now - core.since) or "")
    timerText:SetTextColor(color[1], color[2], color[3])
    stopButton:SetEnabled(core:IsCamping())
end

function ns.TogglePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end
panel:SetScript("OnShow", function() ns.RefreshUI(GetTime()) end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    db()
    placeMinimapButton()
    self:UnregisterEvent("ADDON_LOADED")
end)
