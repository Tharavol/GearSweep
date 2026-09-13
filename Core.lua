local ADDON_NAME, ns = ...

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "dev"

function ns.Print(fmt, ...)
  local message = select("#", ...) > 0 and fmt:format(...) or fmt
  print("|cff33ff99" .. ADDON_NAME .. "|r: " .. message)
end

function ns.Debug(fmt, ...)
  if not (ns.db and ns.db.debug) then
    return
  end
  ns.Print("|cff888888[debug]|r " .. fmt, ...)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
  if event == "ADDON_LOADED" and addon == ADDON_NAME then
    GearSweepDB = GearSweepDB or {}
    ns.db = GearSweepDB
    for key, value in pairs(ns.DEFAULT_SETTINGS) do
      if ns.db[key] == nil then
        ns.db[key] = value
      end
    end
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
