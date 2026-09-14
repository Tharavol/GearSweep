local ADDON_NAME, ns = ...

local Scanner = {}
ns.Scanner = Scanner

-- Character bags: 0 is the backpack, 1-4 are equipped bag slots. Bag 5 is
-- the Reagent Bag - crafting materials only, never gear - and is
-- deliberately excluded.
local CHARACTER_BAG_IDS = { 0, 1, 2, 3, 4 }

-- Real wearable-gear equip slots. An allowlist rather than a blacklist:
-- confirmed live (#8) that C_Item.GetItemInfo's 9th return value is a real,
-- non-empty sentinel string for plenty of non-gear items too (e.g. a
-- potion returns "INVTYPE_NON_EQUIP_IGNORE"), so excluding just a couple of
-- known-bad values let everything else - potions, quest tokens, the
-- Hearthstone - through. Deliberately excludes INVTYPE_BODY (shirt) and
-- INVTYPE_TABARD per spec, and INVTYPE_BAG (bags themselves aren't gear).
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

-- Enumerates every purchased bank tab across every currently-viewable bank
-- type (character bank, Warband/Account bank, ...) rather than hardcoding
-- bag IDs, so it keeps working as more tabs get purchased. Confirmed live
-- via C_Bank.FetchViewableBankTypes/FetchPurchasedBankTabIDs (#8): there is
-- no separate legacy bank container (negative bag indices are all empty),
-- every bank tab is an ordinary bag index, split across two bank types.
local function GetBankLocations()
  local locations = {}
  if not (C_Bank and C_Bank.FetchViewableBankTypes) then
    return locations
  end

  local bankTypeNames = {}
  if Enum and Enum.BankType then
    for name, value in pairs(Enum.BankType) do
      bankTypeNames[value] = name
    end
  end

  local ok, bankTypes = pcall(C_Bank.FetchViewableBankTypes)
  if not ok or not bankTypes then
    return locations
  end

  for _, bankType in ipairs(bankTypes) do
    local label = bankTypeNames[bankType] or ("Bank type " .. tostring(bankType))
    local okIDs, tabIDs = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
    if okIDs and tabIDs then
      for _, bagID in ipairs(tabIDs) do
        table.insert(locations, { bagID = bagID, source = label })
      end
    end
  end

  return locations
end

-- Every bag/bank location worth scanning for gear, with a human-readable
-- source label for the results UI (#13).
function Scanner:GetLocations()
  local locations = {}
  for _, bagID in ipairs(CHARACTER_BAG_IDS) do
    table.insert(locations, { bagID = bagID, source = "Bags" })
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
          local detailedLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(info.hyperlink)
          table.insert(items, {
            bagID = bagID,
            slot = slot,
            -- info.hyperlink (not GetItemInfo's returned link) so
            -- Classify.lua reads this exact instance's bonus IDs
            -- (upgrade track/level) rather than whatever generic link
            -- GetItemInfo cached the first time this item was seen.
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
          })
        end
      end
    end
  end

  ns.Debug("Scanned %d location(s), found %d equippable item(s)", #locations, #items)
  return items
end

-- Moves one item from a bag/bank slot into the first empty bag slot, using
-- the classic pickup-cursor/place-cursor pattern (#7): the same mechanism
-- works uniformly across bags, bank, and Warband Bank tabs, since bank tabs
-- are ordinary bag indices (see #8's findings). Live functional smoke-test
-- (round-tripping a slot with itself) confirmed the pickup/place mechanics;
-- full behavior under a real cross-location move still gets exercised for
-- real once the Pull button (#14/#18) is built.
-- Returns true on success, or false plus a reason string.
function Scanner:WithdrawToBags(bagID, slot)
  if CursorHasItem() then
    return false, "cursor is already holding something"
  end

  local emptyBag, emptySlot
  for _, id in ipairs(CHARACTER_BAG_IDS) do
    local numSlots = C_Container.GetContainerNumSlots(id) or 0
    for s = 1, numSlots do
      if not C_Container.GetContainerItemInfo(id, s) then
        emptyBag, emptySlot = id, s
        break
      end
    end
    if emptyBag then break end
  end

  if not emptyBag then
    return false, "bags full"
  end

  C_Container.PickupContainerItem(bagID, slot)
  C_Container.PickupContainerItem(emptyBag, emptySlot)
  return true
end
