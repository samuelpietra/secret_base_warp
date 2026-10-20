-- The mod against the real engine: every module and function it reaches is
-- still there (callOrFalse would otherwise hide the row without a word), the
-- warp kinds its teleport is built from still look as main.lua says, the
-- engine still raises the hook and event the mod listens to, and the row goes
-- in before SAVE through the real hook bus and ModUI.
local MOD = os.getenv("SBW_MOD") .. "/"
local ENGINE = os.getenv("SBW_ENGINE") .. "/"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then failures = failures + 1 end
end

-- What main.lua calls on each module, by the key it has in main.lua's ENGINE.
local CALLED = {
  audio = { "bikeMusic" },
  field = { "isLocked" },
  rse = { "flag" },
  runtime = { "getSession", "defer" },
  secretBase = { "base", "curMapIsSecretBase", "enter", "playerHasBase", "startScript", "trySetCur" },
  startMenu = { "close" },
  trainerHill = { "inChallenge" },
  warp = { "isBusy", "scripted" },
}

function love.load()
  local ok, err = pcall(function()
    package.path = ENGINE .. "?.lua;" .. ENGINE .. "?/init.lua;" .. package.path
    local source = slurp(MOD .. "main.lua")

    -- the modules, read from main.lua's own ENGINE table
    local modules = {}
    for key, path in source:match("local ENGINE = (%b{})"):gmatch('(%w+)%s*=%s*"([%w%._]+)"') do
      local loaded, module = pcall(require, path)
      modules[key] = loaded and type(module) == "table" and module or nil
      check(modules[key] ~= nil, "module " .. path)
    end
    for key, names in pairs(CALLED) do
      for _, name in ipairs(names) do
        check(modules[key] and type(modules[key][name]) == "function", "function " .. key .. "." .. name)
      end
    end
    local Player = modules.player
    check(Player and type(Player.biking) == "boolean" and type(Player.facing) == "string", "Player.biking and Player.facing")

    -- the two kinds TELEPORT_SPEC joins, and its fields among the engine's
    local kinds = modules.warp.SCRIPTED_KINDS
    check(type(kinds) == "table", "Warp.SCRIPTED_KINDS")
    local tile, teleport = kinds.rse_teleport_tile, kinds.warpteleport
    check(tile and tile.se == "SE_WARP_IN" and not tile.spinOut, "rse_teleport_tile: the departure sound, no spin-out")
    check(teleport and teleport.spinOut and teleport.spinIn and not teleport.se, "warpteleport: spins both ways, silent")
    local known = {}
    for _, kind in pairs(kinds) do for field in pairs(kind) do known[field] = true end end
    local unknown = {}
    for field in source:match("local TELEPORT_SPEC = (%b{})"):gmatch("(%w+)%s*=") do
      if not known[field] then unknown[#unknown + 1] = field end
    end
    check(#unknown == 0, "TELEPORT_SPEC uses only fields the engine's kinds use " .. table.concat(unknown, " "))

    -- what the engine raises, read from its source
    local startMenu = slurp(ENGINE .. "src/ui/game3/start_menu.lua")
    check(startMenu:find('ModRuntime.call("ui.start_menu.items"', 1, true) ~= nil, "the Start menu raises ui.start_menu.items")
    check(startMenu:find("pcall(e.onSelect", 1, true) ~= nil, "the Start menu calls a row's onSelect")
    local map = slurp(ENGINE .. "src/core/game3/map.lua")
    local emit = map:find('ModRuntime.emit("map.entered"', 1, true)
    check(emit and map:sub(emit, emit + 200):find("mapId", 1, true) ~= nil, "entering a map emits map.entered with its mapId")

    -- the row through the real hook bus and ModUI, with the player eligible
    local Hooks, Events, ModRuntime = require("src.mods.Hooks"), require("src.mods.Events"), require("src.mods.Runtime")
    local hooks, events = Hooks.new(), Events.new()
    ModRuntime.install(events, hooks, {})
    local session = { map = "EM_LITTLEROOT_TOWN" }
    modules.runtime.getSession = function() return session end
    modules.secretBase.playerHasBase = function() return true end
    modules.secretBase.curMapIsSecretBase = function() return false end
    local saved = {}
    local entry = assert(loadstring(source, "main.lua"))()
    entry({
      hooks = { wrap = function(_, name, fn) hooks:wrap(name, fn, 0, "secret_base_warp") end },
      events = { on = function(_, name, fn) events:on(name, fn, 0, "secret_base_warp") end },
      ui = require("src.ui.ModUI"),
      save = { get = function(_, k, d) if saved[k] == nil then return d end return saved[k] end,
        set = function(_, k, v) saved[k] = v end },
    })
    local vanilla = { { label = "POKéDEX" }, { label = "POKéMON" }, { label = "SAVE" }, { label = "EXIT" } }
    local rows = ModRuntime.call("ui.start_menu.items", function(_, items) return items end, {}, vanilla)
    local labels = {}
    for i, row in ipairs(rows) do labels[i] = row.label end
    check(table.concat(labels, ",") == "POKéDEX,POKéMON,BASE,SAVE,EXIT", "BASE goes in before SAVE: " .. table.concat(labels, ","))
    check(type(rows[3].onSelect) == "function", "the row carries its onSelect")
    saved.bikeReturnMap = "EM_LITTLEROOT_TOWN"
    events:emit("map.entered", { mapId = "EM_LITTLEROOT_TOWN" })
    check(Player.biking == true and saved.bikeReturnMap == false,
      "map.entered through the real event bus puts the player back on the real Player's bike")
    Player.biking = false
  end)
  if not ok then print("FAIL " .. tostring(err)); failures = failures + 1 end
  print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
  love.event.quit()
end
