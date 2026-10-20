-- The mod's paths on stand-ins for the engine modules it reaches: when the
-- BASE row shows (README, Eligibility), what selecting it does, the teleport
-- kind and its one-warp override, the fallback when the entry script cannot
-- start, and the bike kept for the return leg.
local MOD = os.getenv("SBW_MOD") .. "/"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then failures = failures + 1 end
end

-- ------- stand-ins

local session
local Runtime = { deferred = nil }
function Runtime.getSession() return session end
function Runtime.defer(fn) Runtime.deferred = fn; return true end

local Field = { locked = false }
function Field.isLocked() return Field.locked end

local Rse = { flags = {} }
function Rse.flag(name) return Rse.flags[name] == true end

local Hill = { running = false }
function Hill.inChallenge() return Hill.running end

local Player = { biking = false, facing = "down" }

local Audio = { bikeMusicCalls = 0 }
function Audio.bikeMusic() Audio.bikeMusicCalls = Audio.bikeMusicCalls + 1 end

local StartMenu = { closed = false }
function StartMenu.close(silent) StartMenu.closed = silent end

local BASE_MAP = "EM_SECRET_BASE_RED_CAVE1"
local SB = { hasBase = true, scriptStarts = true, enters = true, scripts = {}, entered = 0 }
function SB.playerHasBase() return SB.hasBase end
function SB.curMapIsSecretBase(s, mapId)
  if SB.curMapThrows then error("no map data") end
  return (mapId or s.map) == BASE_MAP
end
function SB.base(_, index) return index == 0 and { secretBaseId = 42 } or nil end
function SB.trySetCur(id) SB.cur = id end
function SB.startScript(label) SB.scripts[#SB.scripts + 1] = label; return SB.scriptStarts end
function SB.enter() SB.entered = SB.entered + 1; return SB.enters end

local warped = {}
local Warp = { busy = false, SCRIPTED_KINDS = { warp = { se = "SE_EXIT" } } }
function Warp.isBusy() return Warp.busy end
local function vanillaScripted(_, _, kind, destMap) warped[#warped + 1] = kind .. "->" .. destMap end
Warp.scripted = vanillaScripted

-- ------- the mod

local itemsHook, mapEntered
local saved = {}
local insertBefore = function(items, anchor, item)
  for i, row in ipairs(items) do
    if row.label == anchor then table.insert(items, i, item); return items end
  end
  items[#items + 1] = item
  return items
end
local fakeMod = {
  hooks = { wrap = function(_, name, fn) if name == "ui.start_menu.items" then itemsHook = fn end end },
  events = { on = function(_, name, fn) if name == "map.entered" then mapEntered = fn end end },
  ui = { insertBefore = insertBefore },
  save = { get = function(_, k, d) if saved[k] == nil then return d end return saved[k] end,
    set = function(_, k, v) saved[k] = v end },
}

local function menu()
  local rows = itemsHook(function(_, items) return items end, {},
    { { label = "POKéMON" }, { label = "SAVE" }, { label = "EXIT" } })
  local labels = {}
  for i, row in ipairs(rows) do labels[i] = row.label end
  return table.concat(labels, ","), rows
end
local function shows() return (menu():find("BASE", 1, true)) ~= nil end

local function choose()
  local _, rows = menu()
  for _, row in ipairs(rows) do if row.label == "BASE" then row.onSelect() end end
end
local function runDeferred()
  if Runtime.deferred then local fn = Runtime.deferred; Runtime.deferred = nil; fn() end
end
local function select() choose(); runDeferred() end

local function fresh()
  session = { map = "EM_RUSTBORO_CITY", frontier = { challengeStatus = 0 } }
  Field.locked, Warp.busy, Hill.running, Rse.flags = false, false, false, {}
  SB.hasBase, SB.curMapThrows, SB.scriptStarts, SB.enters, SB.scripts, SB.entered, SB.cur = true, false, true, true, {}, 0, nil
  Player.biking, Player.facing, Player.surfing = false, "down", nil
  StartMenu.closed, Warp.scripted, warped, Audio.bikeMusicCalls = false, vanillaScripted, {}, 0
  for k in pairs(saved) do saved[k] = nil end
end

function love.load()
  local ok, err = pcall(function()
    for path, module in pairs({
      ["src.core.game3.audio"] = Audio, ["src.core.game3.field"] = Field, ["src.core.game3.player"] = Player,
      ["src.core.game3.runtime"] = Runtime, ["src.core.game3.rse.init"] = Rse,
      ["src.core.game3.rse.secret_base"] = SB, ["src.ui.game3.start_menu"] = StartMenu,
      ["src.core.game3.rse.trainer_hill"] = Hill, ["src.core.game3.warp"] = Warp,
    }) do package.loaded[path] = module end
    assert(loadstring(slurp(MOD .. "main.lua"), "main.lua"))()(fakeMod)

    -- --- where the row shows
    fresh()
    check(menu() == "POKéMON,BASE,SAVE,EXIT", "eligible: BASE sits just above SAVE (" .. menu() .. ")")
    local hidden = {
      { "no Secret Base yet", function() SB.hasBase = false end },
      { "already inside a Secret Base", function() session.map = BASE_MAP end },
      { "whether the player is in a base is unknown", function() SB.curMapThrows = true end },
      { "a script or forced movement runs", function() Field.locked = true end },
      { "a warp is in flight", function() Warp.busy = true end },
      { "aboard the boat or the S.S. Tidal", function() Rse.flags.FLAG_SYS_CRUISE_MODE = true end },
      { "a Frontier or Battle Tent challenge runs", function() session.frontier.challengeStatus = 1 end },
      { "a Trainer Hill run", function() Hill.running = true end },
      { "no session", function() session = nil end },
    }
    for _, case in ipairs(hidden) do
      fresh(); case[2]()
      check(not shows(), "hidden: " .. case[1])
    end
    for _, map in ipairs({ "SIDNEYS_ROOM", "PHOEBES_ROOM", "GLACIAS_ROOM", "DRAKES_ROOM", "CHAMPIONS_ROOM",
      "HALL1", "HALL2", "HALL3", "HALL4", "HALL5", "HALL_OF_FAME" }) do
      fresh(); session.map = "EM_EVER_GRANDE_CITY_" .. map
      check(not shows(), "hidden: sealed Elite Four room " .. map)
    end
    for _, map in ipairs({ "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F", "EM_EVER_GRANDE_CITY_POKEMON_LEAGUE_2F",
      "EM_EVER_GRANDE_CITY_POKEMON_CENTER_1F", "EM_BATTLE_FRONTIER_OUTSIDE_WEST" }) do
      fresh(); session.map = map
      check(shows(), "shown: " .. map .. ", which the player can walk out of")
    end
    fresh(); Field.isLocked = function() error("renamed internals") end
    check(shows(), "a throwing engine query counts as false, not as a broken menu")
    Field.isLocked = function() return Field.locked end
    fresh(); fakeMod.ui.insertBefore = nil
    check(menu() == "POKéMON,SAVE,EXIT,BASE", "without ModUI.insertBefore the row goes last")
    fakeMod.ui.insertBefore = insertBefore

    -- --- selecting it
    fresh()
    choose()
    check(#SB.scripts == 0 and Runtime.deferred ~= nil, "the warp waits for the Start menu to finish closing")
    runDeferred()
    check(SB.cur == 42, "the player's own base (index 0) becomes the current one")
    check(StartMenu.closed == true, "the Start menu closes silently")
    check(table.concat(SB.scripts, ",") == "SecretBase_EventScript_Enter", "the game's own entry script runs")
    check(Player.facing == "up", "the player departs facing up, so they arrive facing away from the door")
    local spec = Warp.SCRIPTED_KINDS.secret_base_warp
    check(spec and spec.se == "SE_WARP_IN" and spec.spinOut and spec.spinIn, "the teleport kind: the warp sound and a spin both ways")
    Warp.scripted({}, {}, "warp", BASE_MAP)
    check(warped[1] == "secret_base_warp->" .. BASE_MAP, "the entry script's warp into the base uses the teleport kind")
    check(Warp.scripted == vanillaScripted, "and the override is gone after that one warp")
    Warp.scripted({}, {}, "warp", "EM_RUSTBORO_CITY")
    check(warped[2] == "warp->EM_RUSTBORO_CITY", "later warps keep their own kind")

    fresh()
    select()
    Warp.scripted({}, {}, "warpdoor", "EM_RUSTBORO_CITY")
    check(warped[1] == "warpdoor->EM_RUSTBORO_CITY" and Warp.scripted == vanillaScripted,
      "a first warp elsewhere keeps its kind and still removes the override")
    fresh(); select(); select()
    check(Warp.SCRIPTED_KINDS.secret_base_warp == spec, "the kind is registered once")

    fresh(); SB.scriptStarts = false
    select()
    check(SB.entered == 1 and Warp.scripted == vanillaScripted, "no entry script: SB.enter warps instead, and the override is removed")
    fresh(); SB.scriptStarts, SB.enters, Player.biking = false, false, true
    select()
    check(Player.facing == "down" and saved.bikeReturnMap == false, "nothing warps: the facing is restored and no bike is kept")

    -- --- the bike, for the return leg
    fresh(); Player.biking = true
    select()
    check(saved.bikeReturnMap == "EM_RUSTBORO_CITY", "riding: the map left from is remembered, in the mod's save")
    Player.biking = false
    mapEntered({ mapId = BASE_MAP })
    check(saved.bikeReturnMap == "EM_RUSTBORO_CITY" and not Player.biking, "arriving in the base keeps waiting")
    mapEntered({ mapId = "EM_RUSTBORO_CITY" })
    check(Player.biking and Audio.bikeMusicCalls == 1, "back where they left from: on the bike again, with its music")
    check(saved.bikeReturnMap == false, "and the record is cleared")
    fresh(); saved.bikeReturnMap = "EM_RUSTBORO_CITY"
    mapEntered({ mapId = "EM_LILYCOVE_CITY" })
    check(not Player.biking and saved.bikeReturnMap == false, "leaving the base another way drops the stale record")
    fresh(); saved.bikeReturnMap = "EM_RUSTBORO_CITY"; Player.surfing = true
    mapEntered({ mapId = "EM_RUSTBORO_CITY" })
    check(not Player.biking, "never onto the bike while surfing")
    fresh(); Player.biking = false
    select()
    check(saved.bikeReturnMap == false, "on foot: no bike to remember")
  end)
  if not ok then print("FAIL " .. tostring(err)); failures = failures + 1 end
  print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
  love.event.quit()
end
