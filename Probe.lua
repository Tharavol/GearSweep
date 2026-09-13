local ADDON_NAME = ...

--------------------------------------------------------------------------
-- Temporary diagnostic module for v0.2.0 live-API verification
-- (issues #6, #7, #9, #10). Not shipped past this milestone - remove once
-- those issues have real implementations backed by confirmed API/event
-- names instead of guesses.
--------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterAllEvents()
frame:SetScript("OnEvent", function(_, event, ...)
  if event:find("BANK") or event:find("INTERACTION") then
    print("GSProbe EVT:", event, ...)
  end
end)

SLASH_GSPROBE1 = "/gsprobe"
SlashCmdList["GSPROBE"] = function(msg)
  msg = (msg or ""):lower()

  if msg == "bags" then
    for i = 0, 20 do
      local n = C_Container and C_Container.GetContainerNumSlots(i)
      if n and n > 0 then
        print(("GSProbe bag %d: %d slots"):format(i, n))
      end
    end
    return
  end

  if msg == "api" then
    print("GSProbe C_Bank:", C_Bank and "exists" or "missing")
    if C_Bank then
      for k in pairs(C_Bank) do print("  C_Bank." .. k) end
    end
    print("GSProbe C_Container.PickupContainerItem:",
      (C_Container and C_Container.PickupContainerItem) and "exists" or "missing")
    print("GSProbe GetItemSpecInfo (global):", GetItemSpecInfo and "exists" or "missing")
    print("GSProbe C_Item.GetItemSpecInfo:",
      (C_Item and C_Item.GetItemSpecInfo) and "exists" or "missing")
    return
  end

  if msg == "item" then
    local _, link = GameTooltip:GetItem()
    if not link then
      print("GSProbe: no item under the tooltip - hover an item, then run this without moving the mouse")
      return
    end
    print("GSProbe item link:", link)
    for i = 1, GameTooltip:NumLines() do
      local fs = _G["GameTooltipTextLeft" .. i]
      if fs and fs:GetText() then
        print(("GSProbe tooltip[%d]: %s"):format(i, fs:GetText()))
      end
    end

    local getSpec = (C_Item and C_Item.GetItemSpecInfo) or GetItemSpecInfo
    if getSpec then
      local specs = { getSpec(link) }
      print("GSProbe specs:",
        #specs > 0 and table.concat(specs, ", ") or "(none - fits all specs, or API returned nothing)")
    end

    local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    print("GSProbe detailed ilvl:", ilvl)
    return
  end

  print("GSProbe commands: /gsprobe bags | /gsprobe api | /gsprobe item (hover an item first)")
end
