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
        ns.db[key] = ns.DeepCopy(value)
      end
    end
    self:UnregisterEvent("ADDON_LOADED")
  end
end)

-- Confirmed live (#6): opening the bank fires BANKFRAME_OPENED regardless
-- of whether the player lands on the character bank or Warband Bank tab -
-- switching tabs within an already-open bank frame does not re-fire it.
-- Real UI wiring (auto-open, gated by an options toggle) lands in #19;
-- this just confirms the hook works.
local bankFrame = CreateFrame("Frame")
bankFrame:RegisterEvent("BANKFRAME_OPENED")
bankFrame:SetScript("OnEvent", function()
  ns.Debug("Bank opened")
end)
