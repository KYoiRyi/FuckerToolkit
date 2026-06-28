local function log(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local message = table.concat(parts, " ")

  if Toolkit and Toolkit.Log and Toolkit.Log[level] then
    Toolkit.Log[level](message)
  else
    print("[fallback-" .. level .. "] " .. message)
  end
end

log("info", "========== FTK Lua hook selftest begin ==========")
log("info", "lua version:", _VERSION)
log("info", "Toolkit exists:", Toolkit ~= nil)
log("info", "Toolkit.Log exists:", Toolkit and Toolkit.Log ~= nil)
log("info", "Toolkit.Hook exists:", Toolkit and Toolkit.Hook ~= nil)

if not Toolkit then
  log("error", "Toolkit table is missing; native bindings were not registered")
  return
end

if not Toolkit.Hook or type(Toolkit.Hook.SelfTest) ~= "function" then
  log("error", "Toolkit.Hook.SelfTest is missing; hook Lua binding is not available")
  return
end

log("info", "calling Toolkit.Hook.SelfTest()")
local ok, err = pcall(Toolkit.Hook.SelfTest)
log("info", "Toolkit.Hook.SelfTest pcall result:", ok)
if not ok then
  log("error", "Toolkit.Hook.SelfTest Lua error:", err)
else
  log("info", "Toolkit.Hook.SelfTest returned to Lua")
end

log("info", "========== FTK Lua hook selftest end ==========")
