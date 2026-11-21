local ADDON_NAME, ns = ...

local Scanner = {}
ns.Scanner = Scanner

-- Backpack (0) and equipped bags (1-4). The Reagent Bag (5) never holds gear.
local CHARACTER_BAG_IDS = { 0, 1, 2, 3, 4 }

-- Seconds WithdrawToBags waits for a move to confirm. Warband Bank moves
-- round-trip through the server; 1s was too short (#42).
local WITHDRAW_TIMEOUT = 3

-- Wearable-gear equip slots, as an allowlist: non-gear items also return a
-- non-empty equipLoc (e.g. "INVTYPE_NON_EQUIP_IGNORE" for potions, #8).
-- Excludes shirts, tabards and bags.
local EQUIPPABLE_SLOTS = {
  INVTYPE_HEAD = true,
  INVTYPE_NECK = true,
  INVTYPE_SHOULDER = true,
  INVTYPE_CLOAK = true,
  INVTYPE_CHEST = true,
  INVTYPE_ROBE = true,
  INVTYPE_WAIST = true,
  INVTYPE_LEGS = true,
  INVTYPE_FEET = true,
  INVTYPE_WRIST = true,
  INVTYPE_HAND = true,
  INVTYPE_FINGER = true,
  INVTYPE_TRINKET = true,
  INVTYPE_WEAPON = true,
  INVTYPE_SHIELD = true,
  INVTYPE_2HWEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_HOLDABLE = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
  INVTYPE_RELIC = true,
}

-- Every purchased tab of every viewable bank type. Bank tabs are ordinary
-- bag indices (#8). WoW Forever has no Warband Bank and only lists the
-- Character type.
local function GetBankLocations()
  local bankTypeNames = {}
  for name, value in pairs(Enum.BankType) do
    bankTypeNames[value] = name
  end

  local locations = {}
  for _, bankType in ipairs(C_Bank.FetchViewableBankTypes()) do
    local label = bankTypeNames[bankType] or ("Bank type " .. tostring(bankType))
    for _, bagID in ipairs(C_Bank.FetchPurchasedBankTabIDs(bankType)) do
      table.insert(locations, { bagID = bagID, source = label })
    end
  end

  return locations
end

-- Every bag/bank location worth scanning for gear, with a human-readable
-- source label for the results UI (#13).
function Scanner:GetLocations()
  local locations = {}
  for _, bagID in ipairs(CHARACTER_BAG_IDS) do
    table.insert(locations, { bagID = bagID, source = "Bags", inBags = true })
  end
  for _, entry in ipairs(GetBankLocations()) do
    table.insert(locations, entry)
  end
  return locations
end

-- Every equipment item across bags and every bank tab. Skips empty slots
-- and cosmetic-only slots (shirts/tabards) regardless of quality. Does not
-- classify season/tier/spec-relevance - see Classify.lua.
function Scanner:ScanAll()
  local items = {}
  local locations = self:GetLocations()

  for _, location in ipairs(locations) do
    local bagID = location.bagID
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0

    for slot = 1, numSlots do
      local info = C_Container.GetContainerItemInfo(bagID, slot)
      if info and info.hyperlink then
        local name, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID, subclassID =
          C_Item.GetItemInfo(info.hyperlink)
        if equipLoc and EQUIPPABLE_SLOTS[equipLoc] then
          local detailedLevel = C_Item.GetDetailedItemLevelInfo(info.hyperlink)
          table.insert(items, {
            bagID = bagID,
            slot = slot,
            -- The container's link carries this instance's bonus IDs
            -- (upgrade track); GetItemInfo's returned link may not.
            hyperlink = info.hyperlink,
            name = name,
            quality = quality,
            itemLevel = detailedLevel or itemLevel,
            equipLoc = equipLoc,
            -- For class/armor/weapon proficiency (#35).
            classID = classID,
            subclassID = subclassID,
            isBound = info.isBound,
            source = location.source,
            -- Pull Selected leaves items already in bags where they are (#43).
            inBags = location.inBags or false,
          })
        end
      end
    end
  end

  ns.Debug("Scanned %d location(s), found %d equippable item(s)", #locations, #items)
  return items
end

-- Moves one item from a bag/bank slot into the first empty bag slot via
-- pickup/place (#7); bank tabs are ordinary bag indices.
--
-- Asynchronous: container and cursor state read stale right after the
-- pickup calls (#41). Each ITEM_LOCK_CHANGED/BAG_UPDATE_DELAYED re-checks
-- the destination, and only the item sitting there unlocked counts as
-- success (#42). A timeout keeps a pull from hanging.
--
-- `reserved` (optional) is a set of "bag:slot" keys claimed by earlier
-- withdrawals in the same pull; the scan skips them and this call adds its
-- own destination, so in-flight moves never share a slot.
--
-- Calls callback(true) on success, or callback(false, reason) on failure.
function Scanner:WithdrawToBags(bagID, slot, callback, reserved)
  if CursorHasItem() then
    callback(false, "cursor is already holding something")
    return
  end

  -- The scan may be stale: the item moved or the bank closed (#25).
  if not C_Container.GetContainerItemInfo(bagID, slot) then
    callback(false, "item is no longer there")
    return
  end

  local emptyBag, emptySlot
  for _, id in ipairs(CHARACTER_BAG_IDS) do
    local numSlots = C_Container.GetContainerNumSlots(id) or 0
    for s = 1, numSlots do
      if not C_Container.GetContainerItemInfo(id, s) and not (reserved and reserved[id .. ":" .. s]) then
        emptyBag, emptySlot = id, s
        break
      end
    end
    if emptyBag then break end
  end

  if not emptyBag then
    callback(false, "bags full")
    return
  end

  local destKey = emptyBag .. ":" .. emptySlot
  if reserved then reserved[destKey] = true end

  ns.Debug("WithdrawToBags: bag %d slot %d -> bag %d slot %d", bagID, slot, emptyBag, emptySlot)
  C_Container.PickupContainerItem(bagID, slot)
  C_Container.PickupContainerItem(emptyBag, emptySlot)

  local watcher = CreateFrame("Frame")
  local settled = false

  local function Finish(ok, reason)
    settled = true
    watcher:UnregisterAllEvents()
    watcher:SetScript("OnEvent", nil)
    callback(ok, reason)
  end

  -- On timeout, a destination holding the item is accepted even if locked.
  local function Check(timedOut)
    if settled then return end

    local stillHolding = CursorHasItem()
    local dest = C_Container.GetContainerItemInfo(emptyBag, emptySlot)
    local landed = dest ~= nil and (timedOut or not dest.isLocked)
    ns.Debug("WithdrawToBags: check%s - cursor still holding: %s, destination occupied: %s, locked: %s",
      timedOut and " (timeout)" or "", tostring(stillHolding), tostring(dest ~= nil),
      tostring(dest ~= nil and dest.isLocked == true))

    if stillHolding then
      -- The destination wasn't empty after all: put the item back so the
      -- cursor doesn't block later withdrawals, and release the slot.
      C_Container.PickupContainerItem(bagID, slot)
      if reserved then reserved[destKey] = nil end
      Finish(false, "failed to place item")
    elseif landed then
      Finish(true)
    elseif timedOut then
      -- The move may still land, so the slot stays reserved.
      Finish(false, "move not confirmed")
    end
    -- Otherwise still in flight: keep waiting for the next event.
  end

  watcher:RegisterEvent("ITEM_LOCK_CHANGED")
  watcher:RegisterEvent("BAG_UPDATE_DELAYED")
  watcher:SetScript("OnEvent", function() Check(false) end)
  C_Timer.After(WITHDRAW_TIMEOUT, function() Check(true) end)
end
