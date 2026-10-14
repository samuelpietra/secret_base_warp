-- Secret Base Warp (id: secret_base_warp)
--
-- Adds a Start menu row that takes the player into their own Secret Base.
-- Walking back out the door returns them to where they left from, which is
-- vanilla: SB.enter stores the departure point in session.dynamicWarp, and
-- SB.warpOut reads it.
--
-- Needs "engine_internals": runtime, rse.secret_base, warp and player are not
-- on the Gen3 mod facade list, so they are reached through require.

return function(mod)
  local TELEPORT_KIND = "secret_base_warp"

  -- Emerald's rse_teleport_tile has the departure sound but no spinOut, and
  -- FireRed's warpteleport has both spins but no sound.  SCRIPTED_KINDS is
  -- only ever indexed by key, never enumerated, so adding a row is safe.
  local TELEPORT_SPEC = {
    se = "SE_WARP_IN",
    spinOut = true,
    music = true,
    fadeOut = true,
    spinIn = true, -- the engine plays SE_WARP_OUT as part of this
  }

  local function engine(name)
    local ok, module = pcall(require, name)
    if not ok or type(module) ~= "table" then return nil end
    return module
  end

  local function callable(t, key)
    return t ~= nil and type(t[key]) == "function"
  end

  -- Once the door shuts behind the player in the Elite Four there is no PC, no
  -- Pokemon Center and no way back to the lobby except winning or losing; the
  -- halls are the sealed corridors between rooms.  PokemonLeague_1F/2F and the
  -- Ever Grande Pokemon Center are deliberately absent -- those can be walked
  -- out of.  Standing in one of these rooms is the condition itself, which is
  -- why this beats VAR_ELITE_4_STATE: no reset to depend on.
  local ELITE_FOUR_MAPS = {
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

  -- The warp is a round trip -- SB.enter stores the departure point and the
  -- base door walks it back -- so the question is not "may the player leave
  -- this map" but "is the game in the middle of something".
  local function midSomething(sess)
    local Field = engine("src.core.game3.field")
    if callable(Field, "isLocked") and Field.isLocked() then return true end

    -- Warp.scripted sets Warp._busy without ever checking it.
    local Warp = engine("src.core.game3.warp")
    if callable(Warp, "isBusy") and Warp.isBusy() then return true end

    -- Mr. Briney's boat and the S.S. Tidal: scripted start to finish, and
    -- applyInitialAvatar treats the state as a special case of its own.
    local Rse = engine("src.core.game3.rse.init")
    if callable(Rse, "flag") and Rse.flag("FLAG_SYS_CRUISE_MODE", sess) then
      return true
    end

    -- Frontier facilities and Battle Tents cut the player off from the PC on
    -- purpose, and a Secret Base has one.  challengeStatus is 0 between runs,
    -- so the lobbies and the surrounding town stay usable.
    local frontier = sess.frontier
    if type(frontier) == "table"
        and (tonumber(frontier.challengeStatus) or 0) ~= 0 then
      return true
    end

    if ELITE_FOUR_MAPS[sess.map] then return true end

    local Hill = engine("src.core.game3.rse.trainer_hill")
    if callable(Hill, "inChallenge") then
      local ok, running = pcall(Hill.inChallenge, sess)
      if ok and running then return true end
    end

    return false
  end

  -- Everything the warp needs, or nil when it cannot run right now.
  local function ready()
    local Runtime = engine("src.core.game3.runtime")
    local SB = engine("src.core.game3.rse.secret_base")
    if not (SB and callable(Runtime, "getSession")) then return nil end

    local sess = Runtime.getSession()
    if type(sess) ~= "table" then return nil end

    local okBase, hasBase = pcall(SB.playerHasBase, sess)
    if not (okBase and hasBase) then return nil end

    -- Entering from inside a base overwrites session.dynamicWarp, the single
    -- slot holding the first base's way out, stranding the player indoors.
    local okMap, inside = pcall(SB.curMapIsSecretBase, sess)
    if not okMap or inside then return nil end

    if midSomething(sess) then return nil end

    return {
      SB = SB, sess = sess, Runtime = Runtime,
      Warp = engine("src.core.game3.warp"),
    }
  end

  local function teleportKind(Warp)
    local kinds = Warp and Warp.SCRIPTED_KINDS
    if type(kinds) ~= "table" then return nil end
    if type(kinds[TELEPORT_KIND]) ~= "table" then
      kinds[TELEPORT_KIND] = TELEPORT_SPEC
    end
    return TELEPORT_KIND
  end

  -- The vanilla entry runs a script, not SB.enter: the native wraps the warp
  -- in waitWarp and the script resumes at waitstate to finish setting the room
  -- up.  Calling SB.enter by hand got the warp and skipped the rest, which is
  -- what left the base PC unpainted but still solid.
  local ENTER_SCRIPT = "SecretBase_EventScript_Enter"

  -- The script warps some frames later, so the kind swap cannot be undone on
  -- the next line the way a direct call allowed.  It disarms itself when the
  -- warp fires, and only rewrites the kind for a secret-base destination, so a
  -- script that never warps leaves nothing harmful behind.
  local function armTeleportKind(ctx)
    local kind = teleportKind(ctx.Warp)
    if not (kind and callable(ctx.Warp, "scripted")) then return function() end end

    local Warp = ctx.Warp
    local original = Warp.scripted
    local function disarm()
      if Warp.scripted ~= original then Warp.scripted = original end
    end

    Warp.scripted = function(m, g, k, destMap, ...)
      disarm()
      local ok, isBase = pcall(ctx.SB.curMapIsSecretBase, ctx.sess, destMap)
      if ok and isBase then k = kind end
      return original(m, g, k, destMap, ...)
    end
    return disarm
  end

  local function enter(ctx)
    local disarm = armTeleportKind(ctx)

    if callable(ctx.SB, "startScript") then
      local ok, started = pcall(ctx.SB.startScript, ENTER_SCRIPT)
      if ok and started then return true end
    end

    -- Fallback only: this is the path that leaves the PC unpainted.
    local ok, entered = pcall(ctx.SB.enter, ctx.sess)
    disarm()
    return ok and entered ~= false
  end

  -- The return trip is the base door, taken whenever the player feels like it
  -- and possibly after a save, so the bike has to outlive this session rather
  -- than sit in a local.  map.lua recomputes keepBike from the destination and
  -- never writes Player.biking on the way back, so nothing else remounts.
  local PENDING_BIKE = "pendingBike"

  local function rememberBike(sess)
    local Player = engine("src.core.game3.player")
    local riding = Player ~= nil and Player.biking == true
    mod.save:set(PENDING_BIKE, riding and sess.map or false)
  end

  local function forgetBike()
    mod.save:set(PENDING_BIKE, false)
  end

  local function restoreBike(mapId)
    local pending = mod.save:get(PENDING_BIKE, false)
    if type(pending) ~= "string" or type(mapId) ~= "string" then return end

    -- Arriving in the base is the first half of the trip; keep waiting.
    local Runtime = engine("src.core.game3.runtime")
    local SB = engine("src.core.game3.rse.secret_base")
    local sess = callable(Runtime, "getSession") and Runtime.getSession() or nil
    if SB and type(sess) == "table" then
      local ok, inside = pcall(SB.curMapIsSecretBase, sess, mapId)
      if ok and inside then return end
    end

    -- Anywhere else settles it: either this is the way back, or the player
    -- left the base by some other route and the record is stale.
    forgetBike()
    if mapId ~= pending then return end

    local Player = engine("src.core.game3.player")
    if not Player or Player.surfing or Player.underwater then return end
    Player.biking = true

    local Audio = engine("src.core.game3.audio")
    if callable(Audio, "bikeMusic") then pcall(Audio.bikeMusic, true, true) end
  end

  local function goToBase()
    local ctx = ready()
    if not ctx then return end

    -- Index 0 is the player's own base.  trySetCur sets SB._curId and
    -- VAR_CURRENT_SECRET_BASE, which is what SB.enter reads for the entrance.
    ctx.SB.trySetCur(ctx.SB.base(ctx.sess, 0).secretBaseId, ctx.sess)

    local StartMenu = engine("src.ui.game3.start_menu")
    if callable(StartMenu, "close") then StartMenu.close(true) end

    local function warp()
      -- warp.lua hands the spin-in animation the facing held when the warp
      -- began, not the destination facing, so arriving face-up means
      -- departing face-up.  Face-down put the door one step ahead.
      local Player = engine("src.core.game3.player")
      local previous = Player and Player.facing
      if Player then Player.facing = "up" end
      rememberBike(ctx.sess)
      if not enter(ctx) then
        forgetBike()
        if Player and previous then Player.facing = previous end
      end
    end

    if callable(ctx.Runtime, "defer") and ctx.Runtime.defer(warp) then return end
    warp()
  end

  mod.events:on("map.entered", function(ev)
    restoreBike(ev and ev.mapId)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not ready() then return out end

    local row = { id = "secret_base_warp", label = "BASE", onSelect = goToBase }
    if callable(mod.ui, "insertBefore") then
      return mod.ui.insertBefore(out, "SAVE", row)
    end
    out[#out + 1] = row
    return out
  end)
end
