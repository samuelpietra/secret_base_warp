-- Secret Base Warp (id: secret_base_warp)
--
-- Adds one Start menu row that takes the player to their own Secret Base.
--
-- The return trip is vanilla and free: src/core/game3/rse/secret_base.lua's
-- SB.enter records the current position in session.dynamicWarp before warping,
-- which is what SB.warpOut reads when the player walks back out the door.
--
-- The transition is Emerald's own teleport warp (rse_teleport_tile: warp-in
-- sound, fade, spin on arrival).  SB.enter hardcodes the plain "warp" kind, so
-- the kind is swapped for the duration of that one call rather than copying
-- SB.enter's body -- its bookkeeping (numTimesEntered, dynamicWarp, entrance
-- lookup) leans on locals this mod cannot reach, and a copy would drift.
--
-- Needs the "engine_internals" permission: rse.secret_base and runtime are not
-- on the Gen3 mod facade list, so they are reached through require directly.

return function(mod)
  -- Engine modules are optional at load time: a version that moved or renamed
  -- one must disable the row, never break the Start menu for everything else.
  local function engine(name)
    local ok, m = pcall(require, name)
    if not ok or type(m) ~= "table" then return nil end
    return m
  end

  local function parts()
    local Runtime = engine("src.core.game3.runtime")
    local SB = engine("src.core.game3.rse.secret_base")
    if not (Runtime and SB) then return nil end
    if type(Runtime.getSession) ~= "function" then return nil end
    local sess = Runtime.getSession()
    if type(sess) ~= "table" then return nil end
    return Runtime, SB, sess
  end

  -- The row only appears when it would actually work, so there is no such
  -- thing as selecting it and nothing happening.
  local function available()
    local _, SB, sess = parts()
    if not SB then return false end
    local okHas, has = pcall(SB.playerHasBase, sess)
    if not okHas or not has then return false end
    local okIn, inside = pcall(SB.curMapIsSecretBase, sess)
    if not okIn or inside then return false end
    return true
  end

  -- Emerald's teleport-tile warp spins the player in on arrival but not out on
  -- departure, and FireRed's "warpteleport" spins both ways but carries no
  -- departure sound.  The spec fields are independent flags and the kinds table
  -- is only ever indexed by key, never enumerated, so the honest fix is to
  -- register one row that is both rather than settle for half of each.
  local TELEPORT_KIND = "secret_base_warp"
  local TELEPORT_SPEC = {
    se = "SE_WARP_IN",   -- departure
    spinOut = true,      -- departure, the part rse_teleport_tile lacks
    music = true,
    fadeOut = true,
    spinIn = true,       -- arrival; the engine pairs SE_WARP_OUT with it
  }

  -- Registered on use, not at load, so a kinds table rebuilt by a reload heals
  -- itself on the next trip instead of silently dropping back to a plain fade.
  local function teleportKind(Warp)
    local kinds = Warp and Warp.SCRIPTED_KINDS
    if type(kinds) ~= "table" then return nil end
    if type(kinds[TELEPORT_KIND]) ~= "table" then
      kinds[TELEPORT_KIND] = TELEPORT_SPEC
    end
    return TELEPORT_KIND
  end

  -- Warp.scripted is looked up on the table at call time by rse.secret_base,
  -- so replacing the field is enough, and it is put back in the same tick --
  -- including when SB.enter throws.  Without the kind, the plain fade is a
  -- perfectly good fallback, so this degrades instead of failing.
  local function enterWithTeleport(SB, sess)
    local Warp = engine("src.core.game3.warp")
    local kind = teleportKind(Warp)
    if not (kind and type(Warp.scripted) == "function") then
      return SB.enter(sess)
    end
    local original = Warp.scripted
    local swapped = false
    Warp.scripted = function(m, g, k, ...)
      if not swapped then
        swapped = true
        k = kind
      end
      return original(m, g, k, ...)
    end
    local ok = pcall(SB.enter, sess)
    Warp.scripted = original
    return ok
  end

  local function goToBase()
    local Runtime, SB, sess = parts()
    if not SB or not available() then return end

    -- trySetCur sets both SB._curId and VAR_CURRENT_SECRET_BASE, which is what
    -- SB.enter reads to resolve the entrance.  Index 0 is the player's base.
    local myId = SB.base(sess, 0).secretBaseId
    SB.trySetCur(myId, sess)

    local StartMenu = engine("src.ui.game3.start_menu")
    if StartMenu and type(StartMenu.close) == "function" then
      StartMenu.close(true)
    end

    -- Warping while the menu is still tearing down is asking for trouble, so
    -- hand the warp to the next frame when the engine offers that.
    local function warp()
      -- The spin-in animation decides where the player ends up looking, and
      -- warp.lua hands it savedFacing -- the direction held when the warp
      -- began -- not the destination facing, so overriding Warp.scripted's
      -- facing argument would be ignored.  Leaving it alone meant arriving
      -- face-down at the base entrance and walking straight back out on the
      -- next step.  Departing face-up is what makes the arrival face-up.
      local Player = engine("src.core.game3.player")
      local previous = Player and Player.facing
      if Player then Player.facing = "up" end
      if not enterWithTeleport(SB, sess) and Player and previous then
        Player.facing = previous
      end
    end
    if type(Runtime.defer) == "function" and Runtime.defer(warp) then return end
    warp()
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    if not available() then return out end

    local row = { id = "secret_base_warp", label = "BASE", onSelect = goToBase }

    if mod.ui and type(mod.ui.insertBefore) == "function" then
      return mod.ui.insertBefore(out, "SAVE", row)
    end
    out[#out + 1] = row
    return out
  end)
end
