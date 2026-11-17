-- CorpseCamp core: pure state machine, no WoW API calls (unit-tested outside the game).
--
-- States for the camped player:
--   idle  : not camping anyone
--   dead  : their corpse is visible to us right now
--   gone  : not visible (released and running as a ghost, or just out of view)
--   waiting : camped while still alive; arms once they're seen dead
--   alive : seen alive after a death; alerted once, re-armed when seen dead again
--
-- Inputs are already sanitized by the glue: names are plain strings, life is
-- "dead", "alive" or "unknown" (unknown = the client hid the value from us).

local _, ns = ...
ns = ns or {}

local Core = {}
Core.__index = Core

function Core.new()
    return setmetatable({ state = "idle" }, Core)
end

-- "Name" or "Name-Realm" -> lower-cased base, normalized realm (or nil).
-- The client reports realms without spaces/hyphens ("AzjolNerub"), so typed
-- "Azjol-Nerub" or "Azjol Nerub" is normalized the same way.
local function split(full)
    local base, realm = full:match("^([^%-]+)%-(.+)$")
    if not base then base = full end
    if realm then realm = realm:gsub("[%s%-']", ""):lower() end
    return base:lower(), realm
end

-- Same character if base names match and, when both sides carry a realm, realms
-- match. The glue always attaches a realm to unit names; only typed names lack one.
function Core.SameName(a, b)
    if not a or not b then return false end
    local baseA, realmA = split(a)
    local baseB, realmB = split(b)
    if baseA ~= baseB then return false end
    return realmA == nil or realmB == nil or realmA == realmB
end

-- life: what we see of them right now.
--   "alive"   not dead yet: the alert arms once they're seen dead
--   "dead"    corpse in view
--   "unknown" visible but the client hides the flag: assume the corpse you're camping
--   "absent"  not visible anywhere (released, or out of view): next alive sighting alerts
function Core:Camp(name, life, now)
    self.name = name
    self.state = (life == "alive" and "waiting") or (life == "absent" and "gone") or "dead"
    self.since = now
end

function Core:Stop()
    self.state, self.name, self.since = "idle", nil, nil
end

function Core:IsCamping()
    return self.state ~= "idle"
end

function Core:Matches(name)
    return self:IsCamping() and Core.SameName(self.name, name)
end

-- A dead enemy player sits on our target. Start camping it unless we're
-- still waiting on a different player's resurrection (dead or gone).
-- Returns true when this started (or restarted) a camp.
function Core:OnKill(name, now)
    local replaceable = self.state == "idle" or self.state == "alive" or self.state == "waiting"
    if replaceable or Core.SameName(self.name, name) then
        if self.state == "dead" and Core.SameName(self.name, name) then return false end
        self:Camp(name, "dead", now)
        return true
    end
    return false
end

-- The camped player is visible on some unit token. Returns true exactly once
-- per death cycle: the moment they're seen alive again.
function Core:Sighting(life, now)
    if self.state == "idle" then return false end
    if life == "dead" then
        if self.state ~= "dead" then self.state, self.since = "dead", now end
        return false
    end
    if self.state == "alive" or self.state == "waiting" then return false end
    -- A ghost is invisible to enemies, so a "gone" player reappearing means a
    -- resurrection even when the client hides their dead/alive flag.
    if life == "alive" or (life == "unknown" and self.state == "gone") then
        self.state, self.since = "alive", now
        return true
    end
    return false
end

-- The camped player is on no unit token this scan.
function Core:NotSeen(now)
    if self.state == "dead" then self.state, self.since = "gone", now end
end

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local LABELS = {
    waiting = "waiting for the kill",
    dead  = "corpse in view",
    gone  = "ghost or out of view",
    alive = "RESURRECTED",
}

Core.Clock = clock      -- shared with the panel (UI.lua)
Core.LABELS = LABELS

function Core:Status(now)
    if self.state == "idle" then return nil end
    return ("%s: %s %s"):format(self.name, LABELS[self.state], clock(now - (self.since or now)))
end

ns.Core = Core
return Core
