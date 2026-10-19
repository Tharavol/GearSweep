local ADDON_NAME, ns = ...

local Scanner = {}
ns.Scanner = Scanner

-- Character bags: 0 is the backpack, 1-4 are equipped bag slots. Bag 5 is
-- the Reagent Bag - crafting materials only, never gear - and is
-- deliberately excluded.
local CHARACTER_BAG_IDS = { 0, 1, 2, 3, 4 }

-- Seconds WithdrawToBags waits for a move to confirm before giving up.
-- Warband Bank moves round-trip through the server; the original 1s
-- window was confirmed live to be too short for them (#42).
local WITHDRAW_TIMEOUT = 3

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
            -- Already in the character's bags: Pull Selected leaves it
            -- where it is rather than shuffling it to another bag slot (#43).
            inBags = location.inBags or false,
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
-- are ordinary bag indices (see #8's findings).
--
-- Asynchronous (#41, confirmed live via debug trace): CursorHasItem and
-- GetContainerItemInfo both still read pre-transaction state immediately
-- after the PickupContainerItem calls return - even a slot's own "did the
-- pickup empty it" check read stale - so a synchronous return right after
-- issuing them let a second withdrawal, issued as soon as the first
-- returned, compute an empty-slot scan against data that hadn't caught up
-- yet, sending both items to the same slot. Waiting for ITEM_LOCK_CHANGED
-- (the same signal other addons doing bulk container moves wait on, e.g.
-- Fence's batch auction module) before trusting these reads again is the
-- actual fix; a short timeout is a safety net in case that event doesn't
-- fire for some edge case, so a pull can never hang indefinitely.
--
-- The first ITEM_LOCK_CHANGED isn't the end of the move, though (#42,
-- confirmed live via debug trace): Warband Bank withdrawals go through the
-- server, and settling on the first lock event (or a 1s timeout) counted
-- moves as done while the destination slot still read empty. The next
-- withdrawal then picked that same slot, and when both moves landed the
-- items swapped, sending one back into the bank. Each lock/bag event now
-- re-checks whether the destination actually holds the item, unlocked, and
-- only that counts as success.
--
-- `reserved` (optional) is a set of "bag:slot" keys already claimed by
-- earlier withdrawals in the same pull. The empty-slot scan skips them and
-- this call adds its own destination, so two in-flight moves can never
-- target the same slot even if container state hasn't caught up yet.
--
-- Calls callback(true) on success, or callback(false, reason) on failure.
function Scanner:WithdrawToBags(bagID, slot, callback, reserved)
  if CursorHasItem() then
    callback(false, "cursor is already holding something")
    return
  end

  -- The results list is built from a scan that can be seconds old by the
  -- time Pull Selected runs each row (#25): the item may have already been
  -- moved, or the source slot may no longer be reachable at all (the bank
  -- was closed, or the player disconnected mid-pull). Confirming the item
  -- is still there before touching the cursor turns that into a clear,
  -- reported skip instead of a pickup call that does nothing or leaves the
  -- cursor holding nothing useful.
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

  -- timedOut: the safety net fired rather than an event. A destination that
  -- holds the item but still reads locked is accepted then, rather than
  -- reported as failed for an item that's sitting in the bag.
  local function Check(timedOut)
    if settled then return end

    local stillHolding = CursorHasItem()
    local dest = C_Container.GetContainerItemInfo(emptyBag, emptySlot)
    local landed = dest ~= nil and (timedOut or not dest.isLocked)
    ns.Debug("WithdrawToBags: check%s - cursor still holding: %s, destination occupied: %s, locked: %s",
      timedOut and " (timeout)" or "", tostring(stillHolding), tostring(dest ~= nil),
      tostring(dest ~= nil and dest.isLocked == true))

    if stillHolding then
      -- The destination slot wasn't actually empty once the transaction
      -- settled - put the item back rather than leave the cursor stuck
      -- holding it, which would otherwise cascade into every later
      -- withdrawal in the same pull failing with "cursor is already
      -- holding something". The slot is released since nothing is headed
      -- there.
      C_Container.PickupContainerItem(bagID, slot)
      if reserved then reserved[destKey] = nil end
      Finish(false, "failed to place item")
    elseif landed then
      Finish(true)
    elseif timedOut then
      -- The move may still complete later, so the slot stays reserved for
      -- the rest of the pull; it just can't be counted as pulled.
      Finish(false, "move not confirmed")
    end
    -- Otherwise still in flight: keep waiting for the next event.
  end

  watcher:RegisterEvent("ITEM_LOCK_CHANGED")
  watcher:RegisterEvent("BAG_UPDATE_DELAYED")
  watcher:SetScript("OnEvent", function() Check(false) end)
  C_Timer.After(WITHDRAW_TIMEOUT, function() Check(true) end)
end
