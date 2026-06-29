local function log(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  Toolkit.Log[level](table.concat(parts, " "))
end

log("info", "========== FTK auto smoke begin ==========")
log("info", "lua version:", _VERSION)

if not Toolkit or not Toolkit.Hook then
  log("error", "Toolkit.Hook is missing")
  return
end

log("info", "calling Toolkit.Hook.SelfTest()")
Toolkit.Hook.SelfTest()

if type(Toolkit.Hook.AutoSmokeTest) ~= "function" then
  log("error", "Toolkit.Hook.AutoSmokeTest is missing")
  return
end

log("info", "calling Toolkit.Hook.AutoSmokeTest()")
local ok = Toolkit.Hook.AutoSmokeTest()
log("info", "Toolkit.Hook.AutoSmokeTest returned:", ok)

log("info", "========== FTK auto smoke end ==========")

