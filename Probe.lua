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

  if msg == "banktabs" then
    for i = -4, -1 do
      local ok, n = pcall(C_Container.GetContainerNumSlots, i)
      print(("GSProbe bag %d: ok=%s slots=%s"):format(i, tostring(ok), tostring(n)))
    end

    local ok, types = pcall(C_Bank.FetchViewableBankTypes)
    print("GSProbe FetchViewableBankTypes ok=" .. tostring(ok), types and table.concat(types, ",") or tostring(types))

    if ok and types then
      for _, bankType in ipairs(types) do
        local ok2, numTabs = pcall(C_Bank.FetchNumPurchasedBankTabs, bankType)
        print(("GSProbe bankType %s: FetchNumPurchasedBankTabs ok=%s -> %s"):format(
          tostring(bankType), tostring(ok2), tostring(numTabs)))

        local ok3, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
        print(("GSProbe bankType %s: FetchPurchasedBankTabIDs ok=%s -> %s"):format(
          tostring(bankType), tostring(ok3), ids and table.concat(ids, ",") or tostring(ids)))
      end
    end
    return
  end

  if msg == "tooltip" then
    local _, link = GameTooltip:GetItem()
    if not link then
      print("GSProbe: no item under the tooltip - hover an item, then run this without moving the mouse")
      return
    end

    if not C_TooltipInfo then
      print("GSProbe: C_TooltipInfo does not exist")
      return
    end

    local data = C_TooltipInfo.GetHyperlink(link)
    if not data then
      print("GSProbe: C_TooltipInfo.GetHyperlink returned nothing")
      return
    end

    print("GSProbe tooltipData top-level keys:")
    for k, v in pairs(data) do
      if type(v) ~= "table" then
        print(("  %s = %s"):format(tostring(k), tostring(v)))
      else
        print(("  %s = <table>"):format(tostring(k)))
      end
    end

    if type(data.lines) == "table" then
      print(("GSProbe tooltipData.lines (%d):"):format(#data.lines))
      for i, line in ipairs(data.lines) do
        local parts = {}
        for k, v in pairs(line) do
          if type(v) ~= "table" then
            table.insert(parts, ("%s=%s"):format(tostring(k), tostring(v)))
          end
        end
        print(("  [%d] %s"):format(i, table.concat(parts, ", ")))
      end
    end
    return
  end

  if msg == "hidden" then
    local _, link = GameTooltip:GetItem()
    if not link then
      print("GSProbe: no item under the tooltip - hover an item, then run this without moving the mouse")
      return
    end

    -- A dedicated, never-shown tooltip: the real test for whether Scanner.lua
    -- can bulk-classify hundreds of bag/bank items in the background, since
    -- it can never rely on the live GameTooltip (that would require actually
    -- hovering every item, and flashes visibly if shown on screen).
    if not GearSweepScanTooltip then
      CreateFrame("GameTooltip", "GearSweepScanTooltip", nil, "GameTooltipTemplate")
    end
    GearSweepScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GearSweepScanTooltip:SetHyperlink(link)

    print(("GSProbe hidden tooltip lines (%d):"):format(GearSweepScanTooltip:NumLines()))
    for i = 1, GearSweepScanTooltip:NumLines() do
      local fs = _G["GearSweepScanTooltipTextLeft" .. i]
      if fs and fs:GetText() then
        print(("  [%d] %s"):format(i, fs:GetText()))
      end
    end
    GearSweepScanTooltip:Hide()
    return
  end

  print("GSProbe commands: bags | api | item | banktabs | tooltip | hidden")
end
