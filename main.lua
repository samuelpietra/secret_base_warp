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

  -- The row borrows Teleport's animation, so it borrows Teleport's rules:
  -- FieldMoves.teleportFromMenu refuses wherever isOutdoors is false.  Fails
  -- closed, because a question that cannot be answered is not a yes.
  local function teleportAllowedHere(Runtime)
    local FieldMoves = engine("src.core.game3.field_moves")
    local Map = engine("src.core.game3.map")
    local game = Runtime and Runtime._game
    local maps = game and game.data and game.data.maps
    local def = Map and maps and maps[Map.current]
    if not (def and callable(FieldMoves, "isOutdoors")) then return false end
    return FieldMoves.isOutdoors(tonumber(def.mapType)) == true
  end

  -- Everything the warp needs, or nil when it cannot run right now.
  local function ready()
    local Runtime = engine("src.core.game3.runtime")
    local SB = engine("src.core.game3.rse.secret_base")
    if not (SB and callable(Runtime, "getSession")) then return nil end

    local sess = Runtime.getSession()
    if type(sess) ~= "table" then return nil end

    -- Warp.scripted sets Warp._busy without ever checking it, so a warp
    -- already in flight has to be ruled out here instead.
    local Warp = engine("src.core.game3.warp")
    if callable(Warp, "isBusy") and Warp.isBusy() then return nil end

    local okBase, hasBase = pcall(SB.playerHasBase, sess)
    if not (okBase and hasBase) then return nil end

    local okMap, inside = pcall(SB.curMapIsSecretBase, sess)
    if not okMap or inside then return nil end

    if not teleportAllowedHere(Runtime) then return nil end

    return { SB = SB, sess = sess, Runtime = Runtime, Warp = Warp }
  end

  local function teleportKind(Warp)
    local kinds = Warp and Warp.SCRIPTED_KINDS
    if type(kinds) ~= "table" then return nil end
    if type(kinds[TELEPORT_KIND]) ~= "table" then
      kinds[TELEPORT_KIND] = TELEPORT_SPEC
    end
    return TELEPORT_KIND
  end

  local function enter(ctx)
    local kind = teleportKind(ctx.Warp)
    if not (kind and callable(ctx.Warp, "scripted")) then
      local ok, entered = pcall(ctx.SB.enter, ctx.sess)
      return ok and entered ~= false
    end

    -- rse.secret_base resolves Warp.scripted on the table at call time, so
    -- swapping the field reaches it.  Restored in the same tick either way,
    -- and SB.enter hardcodes the plain "warp" kind, hence the swap.
    local original = ctx.Warp.scripted
    local swapped = false
    ctx.Warp.scripted = function(m, g, k, ...)
      if not swapped then
        swapped = true
        k = kind
      end
      return original(m, g, k, ...)
    end

    local ok, entered = pcall(ctx.SB.enter, ctx.sess)
    ctx.Warp.scripted = original
    return ok and entered ~= false
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
      if not enter(ctx) and Player and previous then
        Player.facing = previous
      end
    end

    if callable(ctx.Runtime, "defer") and ctx.Runtime.defer(warp) then return end
    warp()
  end

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
