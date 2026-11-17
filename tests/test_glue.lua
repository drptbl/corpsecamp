-- End-to-end glue test against a stubbed WoW API: luajit tests/test_glue.lua
-- Units live in `units[token]`; the test drives time and fires OnUpdate.

local now, units, sounds, chat, cvars = 0, {}, 0, {}, { nameplateMaxDistance = "20" }
local frames, inCombat = {}, false

local newFrame
local regions = {}
local function region()
    local f = { scripts = {}, attrs = {}, shown = true, enabled = true }
    regions[#regions + 1] = f
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:SetAttribute(k, v) self.attrs[k] = v end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetEnabled(v) self.enabled = v end
    function f:SetDesaturated(v) self.desaturated = v end
    function f:SetVertexColor(r, g, b) self.color = { r, g, b } end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true ; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function f:Hide() self.shown = false end
    function f:CreateFontString() return region() end
    function f:CreateTexture() return region() end
    return setmetatable(f, { __index = function() return function() end end })
end
newFrame = function(_, name)
    local f = region()
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

CreateFrame = newFrame
UIParent = {}
GetTime = function() return now end
InCombatLockdown = function() return inCombat end
GetNormalizedRealmName = function() return "Home" end
UnitExists = function(u) return units[u] ~= nil end
UnitName = function(u) local x = units[u] return x and x.name, x and x.realm end
UnitIsDeadOrGhost = function(u) return units[u] and units[u].dead or false end
UnitIsPlayer = function(u) return units[u] and units[u].player ~= false end
UnitIsEnemy = function(_, u) return units[u] and units[u].enemy ~= false end
PlaySound = function() sounds = sounds + 1 end
C_Timer = { After = function(_, fn) fn() end }
C_CVar = { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v end }
RaidNotice_AddMessage = function() end
FlashClientIcon = function() end
SlashCmdList = {}
Minimap = region()
function Minimap:GetWidth() return 140 end
function Minimap:GetCenter() return 100, 100 end
local minimapScale = 1
function Minimap:GetEffectiveScale() return minimapScale end
local cursor = { 0, 0 }
GetCursorPosition = function() return cursor[1], cursor[2] end
GameTooltip = region()
UISpecialFrames = {}
print = function(msg) chat[#chat + 1] = msg end

local ns = {}
assert(loadfile("CorpseCamp/Core.lua"))("CorpseCamp", ns)
assert(loadfile("CorpseCamp/CorpseCamp.lua"))("CorpseCamp", ns)
local driver
for _, f in ipairs(frames) do if f.scripts.OnUpdate then driver = f end end
assert(loadfile("CorpseCamp/UI.lua"))("CorpseCamp", ns)
local panel, minimapButton = _G.CorpseCampPanel, _G.CorpseCampMinimapButton
local function findButton(text)
    for _, f in ipairs(frames) do if f.text == text and f.scripts.OnClick then return f end end
    error("no button " .. text)
end
local function hasText(text)
    for _, r in ipairs(regions) do if r.text == text then return true end end
    return false
end
-- The minimap icon is the one region RefreshUI desaturates (found after the first refresh).
local function minimapIcon()
    for _, r in ipairs(regions) do if rawget(r, "desaturated") ~= nil then return r end end
end
local function fireAll(event, ...)
    for _, f in ipairs(frames) do if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
local function tick(dt) now = now + (dt or 0.25) ; driver.scripts.OnUpdate(driver, dt or 0.25) end
local function lastChat() return chat[#chat] or "" end

local passed, failed = 0, 0
local function test(name, fn)
    units, sounds, chat = {}, 0, {}
    SlashCmdList.CORPSECAMP("stop")
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1 ; io.write("FAIL " .. name .. ": " .. tostring(err) .. "\n") end
end
local function eq(a, b, what) if a ~= b then error((what or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

test("kill, release, run back, resurrect -> one alert", function()
    units.target = { name = "Rogue", dead = true }
    tick()
    assert(lastChat():find("camping Rogue%-Home"), lastChat())
    units.target = nil                       -- released: corpse unit gone
    tick() ; tick()
    eq(sounds, 0, "no alert while ghost")
    units.nameplate7 = { name = "Rogue" }    -- resurrected, nameplate appears
    tick() ; tick() ; tick()
    eq(sounds, 3, "alert plays 3 sounds once")
    assert(lastChat():find("RESURRECTED"), lastChat())
    eq(_G.CorpseCampTargetButton.attrs.macrotext, "/targetexact Rogue-Home")
end)

test("stop with corpse still targeted does not re-capture", function()
    units.target = { name = "Rogue", dead = true }
    tick()
    SlashCmdList.CORPSECAMP("stop")
    local n = #chat
    tick() ; tick()
    eq(#chat, n, "no re-capture chatter")
    eq(_G.CorpseCampStatus.shown, false, "status hidden")
end)

test("camp by name on a visibly alive player does not alert", function()
    units.nameplate1 = { name = "Paladin" }
    SlashCmdList.CORPSECAMP("Paladin")
    tick() ; tick()
    eq(sounds, 0)
end)

test("friendly or pet with the camped name does not alert", function()
    units.target = { name = "Gank", dead = true }
    tick()
    units.target = nil ; tick()
    units.nameplate2 = { name = "Gank", enemy = false }
    units.nameplate3 = { name = "Gank", player = false }
    units.nameplate4 = { name = "Gank", realm = "Elsewhere" }
    tick() ; tick()
    eq(sounds, 0)
end)

test("kill of another player while one is pending is announced once, not switched", function()
    units.target = { name = "First", dead = true } ; tick()
    units.target = nil ; tick()
    units.target = { name = "Second", dead = true } ; tick() ; tick() ; tick()
    local refusals = 0
    for _, m in ipairs(chat) do if m:find("not switching") then refusals = refusals + 1 end end
    eq(refusals, 1)
    units.target = nil ; units.nameplate1 = { name = "First" } ; tick()
    eq(sounds, 3, "First still alerts")
end)

test("setup raises nameplate distance but never lowers it", function()
    SlashCmdList.CORPSECAMP("setup")
    eq(cvars.nameplateMaxDistance, "41")
    cvars.nameplateMaxDistance = "60"
    SlashCmdList.CORPSECAMP("setup")
    eq(cvars.nameplateMaxDistance, "60")
    eq(cvars.nameplateShowAll, "1")
end)

test("target button update is deferred until out of combat", function()
    inCombat = true
    units.target = { name = "Warlock", dead = true } ; tick()
    assert(_G.CorpseCampTargetButton.attrs.macrotext ~= "/targetexact Warlock-Home", "changed in combat")
    inCombat = false
    driver.scripts.OnEvent(driver, "PLAYER_REGEN_ENABLED")
    eq(_G.CorpseCampTargetButton.attrs.macrotext, "/targetexact Warlock-Home")
end)

test("minimap left-click toggles the panel, right-click camps target", function()
    eq(panel:IsShown(), false, "panel starts hidden")
    minimapButton.scripts.OnClick(minimapButton, "LeftButton")
    eq(panel:IsShown(), true, "opened")
    minimapButton.scripts.OnClick(minimapButton, "LeftButton")
    eq(panel:IsShown(), false, "closed")
    units.target = { name = "Mage" }           -- alive (no dead flag)
    minimapButton.scripts.OnClick(minimapButton, "RightButton")
    assert(lastChat():find("camping Mage%-Home"), lastChat())
    eq(ns.core.state, "waiting")
end)

test("panel shows name, state and timer, and Stop follows camping", function()
    panel:Show()
    eq(findButton("Stop").enabled, false, "stop disabled when idle")
    units.target = { name = "Rogue", dead = true } ; tick()
    units.target = nil ; tick()               -- released
    tick(10)
    eq(hasText("Rogue-Home"), true, "name shown")
    eq(hasText("ghost or out of view"), true, "state shown")
    eq(hasText("0:10"), true, "timer shown")
    eq(findButton("Stop").enabled, true, "stop enabled while camping")
    findButton("Stop").scripts.OnClick()
    eq(ns.core.state, "idle")
    panel:Hide()
end)

test("panel buttons and name box run the shared actions", function()
    findButton("Test alert").scripts.OnClick()
    eq(sounds, 3, "test alert")
    local box = _G.CorpseCampNameBox
    box:SetText("Warrior")
    box.scripts.OnEnterPressed(box)
    eq(ns.core.name, "Warrior")
    eq(ns.core.state, "gone", "not visible -> ghost assumed")
    eq(box:GetText(), "", "box cleared")
    box:SetText("   ")
    findButton("Camp").scripts.OnClick()
    eq(ns.core.name, "Warrior", "blank name ignored")
    findButton("Nameplate setup").scripts.OnClick()
    eq(cvars.nameplateShowEnemies, "1")
end)

test("minimap icon is grey when idle, red after a resurrection", function()
    tick()
    local mmIcon = minimapIcon()
    eq(mmIcon.desaturated, true, "idle -> grey")
    SlashCmdList.CORPSECAMP("Hunter")
    tick()
    eq(mmIcon.desaturated, false, "camping -> colour")
    eq(mmIcon.color[2], 1, "not red yet")
    units.nameplate1 = { name = "Hunter" } ; tick()
    eq(ns.core.state, "alive")
    eq(mmIcon.color[2] < 0.5, true, "resurrected -> red")
end)

test("minimap geometry and saved angle", function()
    eq(math.floor(ns.CursorAngle(0, 0, 0, 10) + 0.5), 90)
    eq(math.floor(ns.CursorAngle(0, 0, -10, 0) + 0.5), 180)
    eq(math.floor(ns.CursorAngle(0, 0, 0, -10) + 0.5), 270)
    local x, y = ns.MinimapOffset(0, 80)
    eq(math.floor(x + 0.5), 80) ; eq(math.floor(y + 0.5), 0)

    CorpseCampDB = { minimap = { angle = 90 } }
    fireAll("ADDON_LOADED", "CorpseCamp")
    local p = minimapButton.point
    eq(p[1], "CENTER") ; eq(math.floor(p[4] + 0.5), 0) ; eq(math.floor(p[5] + 0.5), 75)

    cursor = { 100, 0 }                        -- straight below the minimap centre (100,100)
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    minimapButton.scripts.OnDragStop(minimapButton)
    eq(math.floor(CorpseCampDB.minimap.angle + 0.5), 270)
    minimapScale, cursor = 2, { 200, 400 }     -- UI scale 2: cursor pixels / 2 = (100,200), above
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    minimapButton.scripts.OnDragStop(minimapButton)
    minimapScale = 1
    eq(math.floor(CorpseCampDB.minimap.angle + 0.5), 90, "cursor divided by scale")
    cursor = { 0, 100 }                        -- left of centre
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    eq(math.floor(CorpseCampDB.minimap.angle + 0.5), 180, "drag saves angle")
    eq(minimapButton.scripts.OnUpdate ~= nil, true)
    minimapButton.scripts.OnDragStop(minimapButton)
    eq(minimapButton.scripts.OnUpdate, nil, "drag stops following")
end)

io.write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
