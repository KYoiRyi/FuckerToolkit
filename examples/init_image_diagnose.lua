local function log(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  Toolkit.Log[level](table.concat(parts, " "))
end

log("info", "========== FTK image diagnose begin ==========")

local image_name = "UnityFramework"
local rva = 0x0

local base = Toolkit.Image.Base(image_name)
if not base then
  log("error", "image not found:", image_name)
  return
end

log("info", string.format("%s base=0x%x", image_name, base))

if rva == 0 then
  log("warn", "edit examples/init_image_diagnose.lua and set rva before testing a target function")
  log("info", "========== FTK image diagnose end ==========")
  return
end

local ok, address, bytes = Toolkit.Image.DiagnoseRva(image_name, rva, 16)
log("info", "diagnose result:", ok, address and string.format("0x%x", address) or "nil", bytes or "nil")

log("info", "========== FTK image diagnose end ==========")

