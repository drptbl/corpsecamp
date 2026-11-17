-- CampProbe: answers "what can an addon see about an enemy player on WoW Forever?"
-- Every read is pcall'd and checked with issecretvalue, and secret values are never
-- printed, compared or tested; only their type is reported.

CampProbeLog = CampProbeLog or {}

local MAX_LOG = 3000
local verbose = true          -- log nameplate add/remove for player units
local lastLife = {}           -- unit token -> "dead"/"alive" (non-secret only)

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

local function describe(v)
    if isSecret(v) then return "<secret " .. type(v) .. ">" end
    if v == nil then return "nil" end
    return type(v) .. ":" .. tostring(v)
end

local function log(line)
    local stamp = date("%H:%M:%S")
    local combat = InCombatLockdown() and " [combat]" or ""
    local full = stamp .. combat .. " " .. line
    CampProbeLog[#CampProbeLog + 1] = full
    if #CampProbeLog > MAX_LOG then table.remove(CampProbeLog, 1) end
    print("|cff33ff99CampProbe|r " .. combat .. " " .. line)
end

-- Calls fn(...) and describes every return value, or the error.
local function probeCall(label, fn, ...)
    if type(fn) ~= "function" then return label .. "=<missing api>" end
    local res = { n = 0 }
    local function pack(...) res.n = select("#", ...) ; for i = 1, res.n do res[i] = select(i, ...) end end
    pack(pcall(fn, ...))
    if not res[1] then return label .. "=<error " .. tostring(res[2]) .. ">" end
    local parts = {}
    for i = 2, math.max(res.n, 2) do parts[#parts + 1] = describe(res[i]) end
    return label .. "=" .. table.concat(parts, ",")
end

-- Non-secret boolean read for filtering; nil when unreadable or secret.
local function safeBool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v and true or false
end

local function dumpUnit(unit, why)
    log(("%s %s | %s | %s | %s | %s | %s | %s | %s | %s | %s"):format(
        why, unit,
        probeCall("exists", UnitExists, unit),
        probeCall("name", UnitName, unit),
        probeCall("guid", UnitGUID, unit),
        probeCall("player", UnitIsPlayer, unit),
        probeCall("enemy", UnitIsEnemy, "player", unit),
        probeCall("canAttack", UnitCanAttack, "player", unit),
        probeCall("dead", UnitIsDead, unit),
        probeCall("deadOrGhost", UnitIsDeadOrGhost, unit),
        probeCall("health", UnitHealth, unit)))
end

local function dumpEnvironment()
    log(probeCall("build", GetBuildInfo))
    local apis = {
        "issecretvalue", "canaccessvalue", "UnitName", "UnitGUID", "UnitIsDeadOrGhost",
        "PlaySound", "PlaySoundFile", "FlashClientIcon", "RaidNotice_AddMessage",
        "InCombatLockdown", "EditMacro",
    }
    local present = {}
    for _, name in ipairs(apis) do
        present[#present + 1] = name .. "=" .. (type(_G[name]) == "function" and "yes" or "NO")
    end
    present[#present + 1] = "C_NamePlate.GetNamePlates=" ..
        ((C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") and "yes" or "NO")
    present[#present + 1] = "C_CVar.SetCVar=" ..
        ((C_CVar and type(C_CVar.SetCVar) == "function") and "yes" or "NO")
    present[#present + 1] = "SOUNDKIT.RAID_WARNING=" ..
        describe(SOUNDKIT and SOUNDKIT.RAID_WARNING)
    log("apis " .. table.concat(present, " "))

    local cvars = { "nameplateShowEnemies", "nameplateShowAll", "nameplateMaxDistance",
                    "secretCombatRestrictionsForced" }
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    local values = {}
    for _, cv in ipairs(cvars) do values[#values + 1] = probeCall(cv, getCVar, cv) end
    log("cvars " .. table.concat(values, " "))

    local f = CreateFrame("Frame")
    local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
    log("combatlog register=" .. (ok and "ALLOWED" or ("blocked: " .. tostring(err))))
    if ok then f:UnregisterAllEvents() end
end

local function isPlayerUnit(unit)
    -- Enemy players only; unknown (secret/error) counts as "maybe" so it still gets logged.
    return safeBool(UnitIsPlayer, unit) ~= false and safeBool(UnitIsEnemy, "player", unit) ~= false
end

local function trackLife(unit, why)
    local dead = safeBool(UnitIsDeadOrGhost, unit)
    local life = (dead == true and "dead") or (dead == false and "alive") or "unknown"
    if lastLife[unit] ~= life then
        if lastLife[unit] ~= nil or life == "dead" then
            log(("LIFE %s %s -> %s (%s)"):format(unit, tostring(lastLife[unit]), life, why))
            dumpUnit(unit, "life-change")
        end
        lastLife[unit] = life
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_FLAGS")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        log("---- session start ----")
        dumpEnvironment()
    elseif event == "PLAYER_TARGET_CHANGED" then
        lastLife.target = nil
        if safeBool(UnitExists, "target") then dumpUnit("target", "target") ; trackLife("target", event) end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if event == "NAME_PLATE_UNIT_REMOVED" then lastLife[unit] = nil end
        if verbose and isPlayerUnit(unit) then dumpUnit(unit, event) end
        if event == "NAME_PLATE_UNIT_ADDED" then lastLife[unit] = nil ; trackLife(unit, event) end
    elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        if unit and (unit == "target" or unit:find("^nameplate")) and isPlayerUnit(unit) then
            trackLife(unit, event)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        log("entered combat")
    elseif event == "PLAYER_REGEN_ENABLED" then
        log("left combat")
    end
end)

SLASH_CAMPPROBE1 = "/probe"
SlashCmdList.CAMPPROBE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "clear" then
        wipe(CampProbeLog) ; print("CampProbe: log cleared")
    elseif msg == "quiet" then
        verbose = false ; print("CampProbe: nameplate logging off")
    elseif msg == "loud" then
        verbose = true ; print("CampProbe: nameplate logging on")
    elseif msg == "env" then
        dumpEnvironment()
    elseif msg == "plates" then
        for i = 1, 40 do
            local u = "nameplate" .. i
            if safeBool(UnitExists, u) and isPlayerUnit(u) then dumpUnit(u, "scan") end
        end
    else
        if safeBool(UnitExists, "target") then dumpUnit("target", "manual") else print("CampProbe: no target") end
        if safeBool(UnitExists, "mouseover") then dumpUnit("mouseover", "manual") end
    end
end
