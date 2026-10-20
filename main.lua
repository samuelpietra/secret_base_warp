-- Secret Base Warp (id: secret_base_warp)
--
-- Adds a Start menu row that takes the player into their own Secret Base.
-- Walking back out the door returns them to where they left from, which is
-- vanilla behaviour: the entry script records the departure point in
-- session.dynamicWarp and SB.warpOut reads it back.

return function(mod)
  local MOD_ID = "secret_base_warp"
  local MENU_LABEL = "BASE"
  local MENU_ANCHOR_LABEL = "SAVE"
  local ENTRY_SCRIPT = "SecretBase_EventScript_Enter"
  local BIKE_RETURN_MAP = "bikeReturnMap"

  -- Every engine module this mod reaches into, which is also what the
  -- "engine_internals" permission in the manifest covers.  None of these are
  -- on the Gen 3 mod facade list, so each is resolved by require.
  local ENGINE = {
    audio       = "src.core.game3.audio",
    field       = "src.core.game3.field",
    player      = "src.core.game3.player",
    runtime     = "src.core.game3.runtime",
    rse         = "src.core.game3.rse.init",
    secretBase  = "src.core.game3.rse.secret_base",
    startMenu   = "src.ui.game3.start_menu",
    trainerHill = "src.core.game3.rse.trainer_hill",
    warp        = "src.core.game3.warp",
  }

  -- Emerald's rse_teleport_tile carries the departure sound but no spin-out,
  -- and FireRed's warpteleport spins both ways but is silent.  The kinds table
  -- is only ever indexed by key, never enumerated, so registering one row that
  -- is both is safe.
  local TELEPORT_SPEC = {
    se = "SE_WARP_IN",
    spinOut = true,
    music = true,
    fadeOut = true,
    spinIn = true, -- the engine plays SE_WARP_OUT as part of this
  }

  -- The sealed rooms of the Elite Four gauntlet: no PC, no Pokemon Center and
  -- no way back to the lobby except winning or losing.  PokemonLeague_1F/2F
  -- and the Ever Grande Pokemon Center are absent on purpose, because the
  -- player can still walk out of those.
  local SEALED_ELITE_FOUR_MAPS = {
    EM_EVER_GRANDE_CITY_SIDNEYS_ROOM   = true,
    EM_EVER_GRANDE_CITY_PHOEBES_ROOM   = true,
    EM_EVER_GRANDE_CITY_GLACIAS_ROOM   = true,
    EM_EVER_GRANDE_CITY_DRAKES_ROOM    = true,
    EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM = true,
    EM_EVER_GRANDE_CITY_HALL1          = true,
    EM_EVER_GRANDE_CITY_HALL2          = true,
    EM_EVER_GRANDE_CITY_HALL3          = true,
    EM_EVER_GRANDE_CITY_HALL4          = true,
    EM_EVER_GRANDE_CITY_HALL5          = true,
    EM_EVER_GRANDE_CITY_HALL_OF_FAME   = true,
  }

  local function engineModule(path)
    local loaded, module = pcall(require, path)
    if not loaded or type(module) ~= "table" then return nil end
    return module
  end

  local function hasFunction(container, name)
    return container ~= nil and type(container[name]) == "function"
  end

  -- An engine query that may be missing or may throw on a version this mod was
  -- not written against.  Answering false in either case is what every caller
  -- wants, so they do not each repeat the check.
  local function callOrFalse(container, name, ...)
    if not hasFunction(container, name) then return false end
    local called, result = pcall(container[name], ...)
    return called and result or false
  end

  local function currentSession()
    local Runtime = engineModule(ENGINE.runtime)
    if not hasFunction(Runtime, "getSession") then return nil end
    local session = Runtime.getSession()
    if type(session) ~= "table" then return nil end
    return session, Runtime
  end

  -- The trip is a round trip, so the question is never "may the player leave
  -- this map" but "is the game in the middle of something".
  local function isMidSequence(session)
    if callOrFalse(engineModule(ENGINE.field), "isLocked") then return true end

    -- Warp.scripted sets Warp._busy without ever checking it.
    if callOrFalse(engineModule(ENGINE.warp), "isBusy") then return true end

    -- Mr. Briney's boat and the S.S. Tidal are scripted start to finish.
    local Rse = engineModule(ENGINE.rse)
    if callOrFalse(Rse, "flag", "FLAG_SYS_CRUISE_MODE", session) then return true end

    -- Frontier facilities and Battle Tents cut the player off from the PC on
    -- purpose, and a Secret Base has one.  challengeStatus is 0 between runs,
    -- so the lobbies and the surrounding town stay usable.
    local frontier = session.frontier
    if type(frontier) == "table"
        and (tonumber(frontier.challengeStatus) or 0) ~= 0 then
      return true
    end

    if SEALED_ELITE_FOUR_MAPS[session.map] then return true end

    return callOrFalse(engineModule(ENGINE.trainerHill), "inChallenge", session)
  end

  -- Everything the warp needs, or nil when it cannot run right now.
  local function warpContext()
    local session, Runtime = currentSession()
    local SecretBase = engineModule(ENGINE.secretBase)
    if not (session and SecretBase) then return nil end

    if not callOrFalse(SecretBase, "playerHasBase", session) then return nil end

    -- The one engine query answered fail-closed rather than through
    -- callOrFalse: if it throws, whether the player is already in a base is
    -- unknown, and entering one from another overwrites session.dynamicWarp,
    -- the single slot holding the first base's way out.
    local known, alreadyInside = pcall(SecretBase.curMapIsSecretBase, session)
    if not known or alreadyInside then return nil end

    if isMidSequence(session) then return nil end

    return {
      SecretBase = SecretBase,
      Runtime = Runtime,
      Warp = engineModule(ENGINE.warp),
      session = session,
    }
  end

  local function registerTeleportKind(Warp)
    local kinds = Warp and Warp.SCRIPTED_KINDS
    if type(kinds) ~= "table" then return nil end
    if type(kinds[MOD_ID]) ~= "table" then kinds[MOD_ID] = TELEPORT_SPEC end
    return MOD_ID
  end

  -- The entry script warps a few frames later, so the kind cannot be put back
  -- on the next line.  The override removes itself the moment the warp fires
  -- and only rewrites the kind for a Secret Base destination, so a script that
  -- never warps leaves nothing harmful behind.
  local function overrideNextWarpKind(context)
    local Warp = context.Warp
    local kind = registerTeleportKind(Warp)
    if not (kind and hasFunction(Warp, "scripted")) then return function() end end

    local vanillaScripted = Warp.scripted
    local function cancel()
      if Warp.scripted ~= vanillaScripted then Warp.scripted = vanillaScripted end
    end

    Warp.scripted = function(warpMod, game, requestedKind, destinationMap, ...)
      cancel()
      if callOrFalse(context.SecretBase, "curMapIsSecretBase",
          context.session, destinationMap) then
        requestedKind = kind
      end
      return vanillaScripted(warpMod, game, requestedKind, destinationMap, ...)
    end
    return cancel
  end

  -- The vanilla entry runs a script rather than SB.enter: the native wraps the
  -- warp in waitWarp and the script resumes at waitstate to finish dressing
  -- the room.  Calling SB.enter directly performs the warp and skips the rest,
  -- which leaves the base PC unpainted but still solid.
  local function enterOwnBase(context)
    local cancelOverride = overrideNextWarpKind(context)

    if callOrFalse(context.SecretBase, "startScript", ENTRY_SCRIPT) then
      return true
    end

    local warped, entered = pcall(context.SecretBase.enter, context.session)
    cancelOverride()
    return warped and entered ~= false
  end

  -- The return leg is the base door, taken whenever the player feels like it
  -- and possibly after a save, so the bike has to outlive this session.
  -- map.lua recomputes keepBike from the destination and never writes
  -- Player.biking on the way back, so nothing else remounts the player.
  local function rememberBike(session)
    local Player = engineModule(ENGINE.player)
    local riding = Player ~= nil and Player.biking == true
    mod.save:set(BIKE_RETURN_MAP, riding and session.map or false)
  end

  local function forgetBike()
    mod.save:set(BIKE_RETURN_MAP, false)
  end

  local function remountBikeOnReturn(arrivedMap)
    local returnMap = mod.save:get(BIKE_RETURN_MAP, false)
    if type(returnMap) ~= "string" or type(arrivedMap) ~= "string" then return end

    -- Arriving in the base is the outbound leg; keep waiting for the return.
    local session = currentSession()
    local SecretBase = engineModule(ENGINE.secretBase)
    if session
        and callOrFalse(SecretBase, "curMapIsSecretBase", session, arrivedMap) then
      return
    end

    -- Any other map settles it: either this is the way back, or the player
    -- left the base by another route and the record is stale.
    forgetBike()
    if arrivedMap ~= returnMap then return end

    local Player = engineModule(ENGINE.player)
    if not Player or Player.surfing or Player.underwater then return end
    Player.biking = true
    callOrFalse(engineModule(ENGINE.audio), "bikeMusic", true, true)
  end

  local function goToOwnBase()
    local context = warpContext()
    if not context then return end

    -- Index 0 is the player's own base.  trySetCur sets both SB._curId and
    -- VAR_CURRENT_SECRET_BASE, which the entry script reads for the entrance.
    -- Its answer is ignored: it reports a missing id, and playerHasBase has
    -- just found this one.
    local ownBase = callOrFalse(context.SecretBase, "base", context.session, 0)
    if type(ownBase) ~= "table" then return end
    callOrFalse(context.SecretBase, "trySetCur", ownBase.secretBaseId, context.session)

    local StartMenu = engineModule(ENGINE.startMenu)
    if hasFunction(StartMenu, "close") then StartMenu.close(true) end

    local function depart()
      -- warp.lua hands the spin-in animation the facing held when the warp
      -- began rather than the destination facing, so arriving face-up means
      -- departing face-up.  Face-down left the player one step from the door.
      local Player = engineModule(ENGINE.player)
      local previousFacing = Player and Player.facing
      if Player then Player.facing = "up" end

      rememberBike(context.session)
      if not enterOwnBase(context) then
        forgetBike()
        if Player and previousFacing then Player.facing = previousFacing end
      end
    end

    -- Warping while the Start menu is still tearing down invites trouble.
    local Runtime = context.Runtime
    if hasFunction(Runtime, "defer") and Runtime.defer(depart) then return end
    depart()
  end

  mod.events:on("map.entered", function(event)
    remountBikeOnReturn(event and event.mapId)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(callNext, game, items)
    local rows = callNext(game, items)
    if type(rows) ~= "table" or not warpContext() then return rows end

    local row = { id = MOD_ID, label = MENU_LABEL, onSelect = goToOwnBase }
    if hasFunction(mod.ui, "insertBefore") then
      return mod.ui.insertBefore(rows, MENU_ANCHOR_LABEL, row)
    end
    rows[#rows + 1] = row
    return rows
  end)
end
