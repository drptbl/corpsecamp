-- CorpseCamp: WoW glue. Reads unit tokens (Forever closes the combat log to
-- addons), feeds sanitized sightings to Core, and raises the alert.
--
-- Every unit read goes through read(): pcall'd, and a secret value counts as
-- "unreadable" instead of being compared or tested (that would throw).

local _, ns = ...
local Core = ns.Core
local core = Core.new()
ns.core = core

local PREFIX = "|cffff5555CorpseCamp|r "
local SCAN_INTERVAL = 0.2
local FIXED_TOKENS = { "target", "focus", "mouseover" }
local NAMEPLATE_TOKENS = {}
for i = 1, 40 do NAMEPLATE_TOKENS[i] = "nameplate" .. i end
local NAMEPLATE_CVARS = {
    { "nameplateShowEnemies", "1" },
    { "nameplateShowAll", "1" },        -- show nameplates out of combat too
}
local MIN_NAMEPLATE_DISTANCE = 41      -- raise to this if lower; never lower it
local LIFE_RANK = { dead = 1, unknown = 2, alive = 3 }

local function say(msg) print(PREFIX .. msg) end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- ok, first, second. ok is false if the API is missing, errored, or returned a secret.
local function read(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b = pcall(fn, ...)
    if not ok or isSecret(a) then return false end
    if isSecret(b) then b = nil end
    return true, a, b
end

-- true/false when readable, nil when not.
local function toBool(ok, v)
    if not ok then return nil end
    return v and true or false
end

local function ownRealm()
    local ok, realm = read(GetNormalizedRealmName)
    return ok and type(realm) == "string" and realm ~= "" and realm or nil
end

-- { name = "Name-Realm", life = "dead"|"alive"|"unknown", player = bool?, hostile = bool? } or nil
local function readUnit(unit)
    local okExists, exists = read(UnitExists, unit)
    if not okExists or not exists then return nil end
    local okName, name, realm = read(UnitName, unit)
    if not okName or type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    -- UnitName omits the realm for your own realm; attach it so a same-named
    -- player from another realm never matches.
    if type(realm) ~= "string" or realm == "" then realm = ownRealm() end
    if realm then name = name .. "-" .. realm end

    local okDead, dead = read(UnitIsDeadOrGhost, unit)
    local okPlayer, player = read(UnitIsPlayer, unit)
    -- Faction reaction, which should hold for corpses too (attackability may not).
    local okEnemy, enemy = read(UnitIsEnemy, "player", unit)
    local life = "unknown"
    if okDead then life = dead and "dead" or "alive" end
    return {
        name = name,
        life = life,
        player = toBool(okPlayer, player),
        hostile = toBool(okEnemy, enemy),
    }
end

-- Best view of the camped name across all unit tokens: "alive" > "unknown" > "dead",
-- or nil when not visible. Friendly units and non-players (pets) never count.
local function findLife(name)
    local best
    local function consider(unit)
        local u = readUnit(unit)
        if u and u.player ~= false and u.hostile ~= false and Core.SameName(name, u.name)
           and (not best or LIFE_RANK[u.life] > LIFE_RANK[best]) then
            best = u.life
        end
    end
    for _, unit in ipairs(FIXED_TOKENS) do consider(unit) end
    for _, unit in ipairs(NAMEPLATE_TOKENS) do consider(unit) end
    return best
end

local function getCVar(name)
    local ok, v = read((C_CVar and C_CVar.GetCVar) or GetCVar, name)
    return ok and v or nil
end

---------------------------------------------------------------------------
-- Status line (drag to move; position kept by the client's layout cache)
---------------------------------------------------------------------------
local status = CreateFrame("Frame", "CorpseCampStatus", UIParent)
status:SetSize(320, 24)
status:SetPoint("TOP", UIParent, "TOP", 0, -140)
status:SetClampedToScreen(true)
status:SetMovable(true)
status:EnableMouse(true)
status:RegisterForDrag("LeftButton")
status:SetScript("OnDragStart", status.StartMoving)
status:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(true)
end)
status.text = status:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
status.text:SetPoint("CENTER")
status:Hide()

local function refreshStatus(now)
    local line = core:Status(now)
    if not line then
        status:Hide()
    else
        if core.state == "alive" then
            status.text:SetTextColor(1, 0.2, 0.2)
        else
            status.text:SetTextColor(1, 0.82, 0)
        end
        status.text:SetText(line)
        status:Show()
    end
    -- Minimap icon + panel (UI.lua), last and isolated so a UI error can't stall the status line.
    if ns.RefreshUI then pcall(ns.RefreshUI, now) end
end

---------------------------------------------------------------------------
-- One-key "/targetexact <camped player>" (Key Bindings > AddOns > CorpseCamp).
-- Addons can't pick a target; this rewrites a secure macro you press yourself.
---------------------------------------------------------------------------
BINDING_HEADER_CORPSECAMP = "CorpseCamp"
_G["BINDING_NAME_CLICK CorpseCampTargetButton:LeftButton"] = "Target camped player"

local targetButton = CreateFrame("Button", "CorpseCampTargetButton", UIParent, "SecureActionButtonTemplate")
targetButton:SetAttribute("type", "macro")
targetButton:RegisterForClicks("AnyUp", "AnyDown")
local targetButtonStale = false

local function updateTargetButton()
    if InCombatLockdown() then targetButtonStale = true return end
    targetButton:SetAttribute("macrotext", core.name and ("/targetexact " .. core.name) or "")
    targetButtonStale = false
end

---------------------------------------------------------------------------
-- Alert
---------------------------------------------------------------------------
local function playAlertSound()
    local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    pcall(PlaySound, kit, "Master")
end

local function alert()
    local msg = core.name .. " RESURRECTED!"
    for i = 0, 2 do C_Timer.After(i * 0.7, playAlertSound) end
    local color = (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.2, b = 0.2 }
    if not pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, color) then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.2, 0.2)
    end
    pcall(FlashClientIcon)
    say("|cffff2020" .. msg .. "|r")
end

---------------------------------------------------------------------------
-- Scan: the single path every event and the ticker funnel into
---------------------------------------------------------------------------
local function startCamp(name, life, now, why)
    core:Camp(name, life, now)
    updateTargetButton()
    say(("camping %s (%s)"):format(name, why))
end

-- Corpse the user dropped with /ccamp stop, or a capture we refused; not
-- auto-captured or re-announced until the target changes.
local ignoredTarget

local function scan()
    local now = GetTime()

    -- Auto-capture: a dead enemy player on target becomes the camp.
    local t = readUnit("target")
    if ignoredTarget and not (t and Core.SameName(ignoredTarget, t.name)) then ignoredTarget = nil end
    if t and t.player and t.hostile and t.life == "dead" and not ignoredTarget then
        local wasName, wasState = core.name, core.state
        if core:OnKill(t.name, now) then
            if wasName ~= core.name then updateTargetButton() end
            -- Stay quiet when the same corpse just came back into view.
            if wasName ~= core.name or wasState == "idle" or wasState == "alive" then
                say(("camping %s (killed on target)"):format(t.name))
            end
        elseif not core:Matches(t.name) then
            ignoredTarget = t.name
            say(("still camping %s, not switching to %s (/ccamp to switch)"):format(core.name, t.name))
        end
    end

    if core:IsCamping() then
        local best = findLife(core.name)
        if best then
            if core:Sighting(best, now) then alert() end
        else
            core:NotSeen(now)
        end
    end

    refreshStatus(now)
end

local lastError = 0
local function safeScan()
    local ok, err = pcall(scan)
    if not ok and GetTime() - lastError > 10 then
        lastError = GetTime()
        say("scan error: " .. tostring(err))
    end
end

-- Events mark the scan dirty; OnUpdate runs at most one scan per frame,
-- and at least every SCAN_INTERVAL as a backstop for withheld events.
local driver = CreateFrame("Frame")
local dirty, sinceScan = true, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    sinceScan = sinceScan + elapsed
    if dirty or sinceScan >= SCAN_INTERVAL then
        dirty, sinceScan = false, 0
        safeScan()
    end
end)

local function setupNameplates()
    if InCombatLockdown() then say("leave combat first, then /ccamp setup") return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local wanted = {}
    for _, cv in ipairs(NAMEPLATE_CVARS) do wanted[#wanted + 1] = cv end
    local distance = tonumber(getCVar("nameplateMaxDistance") or "")
    if distance and distance < MIN_NAMEPLATE_DISTANCE then
        wanted[#wanted + 1] = { "nameplateMaxDistance", tostring(MIN_NAMEPLATE_DISTANCE) }
    end
    for _, cv in ipairs(wanted) do
        local ok, err = pcall(set, cv[1], cv[2])
        say(("%s -> %s%s"):format(cv[1], tostring(getCVar(cv[1])),
            ok and "" or (" (could not set: " .. tostring(err) .. ")")))
    end
    say("nameplateMaxDistance = " .. tostring(getCVar("nameplateMaxDistance")))
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                         "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_FLAGS" }) do
    pcall(driver.RegisterEvent, driver, event)
end
driver:SetScript("OnEvent", function(_, event, unit)
    -- UNIT_* fire constantly in groups; only target and nameplates matter.
    if (event == "UNIT_HEALTH" or event == "UNIT_FLAGS")
       and unit ~= "target" and not (core:IsCamping() and type(unit) == "string" and unit:find("^nameplate")) then
        return
    end
    if event == "PLAYER_LOGIN" then
        if getCVar("nameplateShowEnemies") ~= "1" or getCVar("nameplateShowAll") ~= "1" then
            say("enemy nameplates aren't always on, so detection range is limited. Type /ccamp setup")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if targetButtonStale then updateTargetButton() end
    end
    dirty = true
end)

---------------------------------------------------------------------------
-- Actions: the one implementation behind both the slash command and the panel
---------------------------------------------------------------------------
local Actions = {}
ns.Actions = Actions

-- Camp your target: dead arms now, alive arms on the kill.
function Actions.CampTarget()
    local now = GetTime()
    local t = readUnit("target")
    if not t or t.player == false or t.hostile == false then
        say("target an enemy player (or their corpse), or use /ccamp Name")
    else
        ignoredTarget = nil
        startCamp(t.name, t.life, now, "target, " .. t.life)
    end
    refreshStatus(now)
end

-- Camp by name. If they're visible right now, start from what we see;
-- otherwise assume they're a ghost on the way back.
function Actions.CampName(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return Actions.CampTarget() end
    local now = GetTime()
    local life = findLife(name) or "absent"
    startCamp(name, life, now, "by name, " .. life)
    refreshStatus(now)
end

function Actions.Stop()
    local now = GetTime()
    local t = readUnit("target")
    if t and core:Matches(t.name) then ignoredTarget = t.name end
    core:Stop() ; updateTargetButton() ; refreshStatus(now) ; say("stopped")
end

function Actions.Test()
    local real = core.name
    core.name = real or "Test"
    alert()
    core.name = real
end

Actions.SetupNameplates = setupNameplates

function Actions.Status()
    return core:Status(GetTime())
end

---------------------------------------------------------------------------
-- /ccamp            camp your target
-- /ccamp Name       camp a player by name
-- /ccamp stop | status | setup | test | ui
---------------------------------------------------------------------------
SLASH_CORPSECAMP1 = "/ccamp"
SLASH_CORPSECAMP2 = "/corpsecamp"
SlashCmdList.CORPSECAMP = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = msg:lower()
    if cmd == "stop" then Actions.Stop()
    elseif cmd == "status" then say(Actions.Status() or "not camping anyone")
    elseif cmd == "setup" then Actions.SetupNameplates()
    elseif cmd == "test" then Actions.Test()
    elseif cmd == "ui" then if ns.TogglePanel then ns.TogglePanel() end
    else Actions.CampName(msg)
    end
end
