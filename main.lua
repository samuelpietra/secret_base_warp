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
