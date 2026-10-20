-- Lists the globals each mod file reads or writes (LuaJIT bytecode GGET/GSET).
local MOD = os.getenv("SBW_MOD") .. "/"
local ALLOWED = { ipairs = true, pairs = true, pcall = true, error = true, tostring = true, tonumber = true,
  type = true, math = true, string = true, table = true, love = true, load = true, require = true,
  print = true, rawget = true, assert = true }
local function slurp(p) local f = io.open(p, "rb"); local s = f:read("*a"); f:close(); return s end
function love.load()
  local util = require("jit.util")
  local function opOf(src)
    local fn = loadstring(src)
    for pc = 1, util.funcinfo(fn).bytecodes - 1 do
      local ins = util.funcbc(fn, pc)
      local ok, k = pcall(util.funck, fn, -math.floor(ins / 65536) - 1)
      if ok and k == "zz_probe" then return ins % 256 end
    end
  end
  local GGET, GSET = opOf("return zz_probe"), opOf("zz_probe = 1")
  local function walk(fn, found)
    local info = util.funcinfo(fn)
    for pc = 1, info.bytecodes - 1 do
      local ins = util.funcbc(fn, pc)
      if not ins then break end
      local code = ins % 256
      local op = (code == GGET and "GGET") or (code == GSET and "GSET") or nil
      if op then
        local d = math.floor(ins / 65536)
        local name = util.funck(fn, -d - 1) or ("?const" .. d)
        found[name] = (found[name] or "") .. (op == "GSET" and " (write)" or "")
      end
    end
    for i = 1, info.gcconsts or 0 do
      local k = util.funck(fn, -i)
      if type(k) == "proto" or (type(k) ~= "string" and type(k) ~= "table" and k ~= nil and tostring(k):find("proto")) then walk(k, found) end
    end
  end
  for _, rel in ipairs({ "main.lua" }) do
    local chunk, err = loadstring(slurp(MOD .. rel), rel)
    if not chunk then print(rel, "COMPILE ERROR", err) else
      local found = {}
      walk(chunk, found)
      local odd = {}
      for name, w in pairs(found) do if not ALLOWED[name] or w ~= "" then odd[#odd + 1] = name .. w end end
      table.sort(odd)
      print(rel, #odd == 0 and "ok" or ("UNEXPECTED: " .. table.concat(odd, ", ")))
    end
  end
  love.event.quit()
end
