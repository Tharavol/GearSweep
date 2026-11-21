local ADDON_NAME, ns = ...

local Upgrade = {}
ns.Upgrade = Upgrade

-- Uncommon (green), Rare (blue), Epic (purple) - same floor as disenchant
-- mode (#11): Poor/Common gear is never worth surfacing as an upgrade pick.
local RELEVANT_QUALITIES = { [2] = true, [3] = true, [4] = true }

-- Two-hand weapons compete against the one-hand+offhand combination as a
-- pair (#16), since equipping one occupies the slot the other needs; every
-- other equip slot is scored independently.
local TWO_HAND = { INVTYPE_2HWEAPON = true }
local MAIN_HAND = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
}
local OFF_HAND = {
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_SHIELD = true,
  INVTYPE_HOLDABLE = true,
}

-- Rings and trinkets are dual-slot in-game, so up to two distinct items can
-- both be genuine upgrades at once.
local DUAL_SLOT = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

-- Inventory slot(s) each equip location is compared against. Finger and
-- Trinket map to both physical slots.
local EQUIP_LOC_TO_INVENTORY_SLOTS = {
  INVTYPE_HEAD = { "HeadSlot" },
  INVTYPE_NECK = { "NeckSlot" },
  INVTYPE_SHOULDER = { "ShoulderSlot" },
  INVTYPE_CLOAK = { "BackSlot" },
  INVTYPE_CHEST = { "ChestSlot" },
  INVTYPE_ROBE = { "ChestSlot" },
  INVTYPE_WAIST = { "WaistSlot" },
  INVTYPE_LEGS = { "LegsSlot" },
  INVTYPE_FEET = { "FeetSlot" },
  INVTYPE_WRIST = { "WristSlot" },
  INVTYPE_HAND = { "HandsSlot" },
  INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
  INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
  INVTYPE_WEAPON = { "MainHandSlot" },
  INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
  INVTYPE_2HWEAPON = { "MainHandSlot" },
  INVTYPE_RANGED = { "MainHandSlot" },
  INVTYPE_RANGEDRIGHT = { "MainHandSlot" },
  INVTYPE_THROWN = { "MainHandSlot" },
  INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
  INVTYPE_SHIELD = { "SecondaryHandSlot" },
  INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
  INVTYPE_RELIC = { "SecondaryHandSlot" },
}

-- Every physical equipment slot, for the debug dumps (#28).
local ALL_INVENTORY_SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WaistSlot",
  "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
  "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

-- Returns the equipped item's level, link and slot ID (link/ID for #28).
local function GetEquippedItemLevel(slotName)
  local slotID = GetInventorySlotInfo(slotName)
  if not slotID then
    return 0, nil, nil
  end
  local link = GetInventoryItemLink("player", slotID)
  if not link then
    return 0, nil, slotID
  end
  local level = C_Item.GetDetailedItemLevelInfo(link)
  if not level then
    level = select(4, C_Item.GetItemInfo(link))
  end
  return level or 0, link, slotID
end

-- The equipped item level candidates are compared against: the lower of
-- the two for finger/trinket. An empty slot falls back to the average
-- equipped item level rather than 0 (#36).
function Upgrade:GetBaselineItemLevel(equipLoc)
  local slots = EQUIP_LOC_TO_INVENTORY_SLOTS[equipLoc]
  if not slots then
    return nil
  end

  local baseline
  for _, slotName in ipairs(slots) do
    local level = GetEquippedItemLevel(slotName)
    if not baseline or level < baseline then
      baseline = level
    end
  end
  baseline = baseline or 0

  if baseline == 0 then
    local _, avgEquipped = GetAverageItemLevel()
    baseline = avgEquipped or 0
  end

  return baseline
end

-- True when the item's level beats the equipped item it would replace (#16).
function Upgrade:IsUpgradeOverEquipped(item)
  local baseline = self:GetBaselineItemLevel(item.equipLoc)
  if baseline == nil then
    return true
  end
  return (item.itemLevel or 0) > baseline
end

-- Debug dump (#28): every slot's equipped item and level.
function Upgrade:DumpEquippedSlots()
  ns.Print("Equipped item levels:")
  for _, slotName in ipairs(ALL_INVENTORY_SLOTS) do
    local level, link = GetEquippedItemLevel(slotName)
    print(("  %s: %s (ilvl %d)"):format(slotName, link or "(empty)", level))
  end
end

-- Debug dump (#28): Upgrade mode's selections and their baselines.
function Upgrade:DumpSelectedUpgrades()
  local scanned = ns.Scanner:ScanAll()
  local candidates = {}
  for _, item in ipairs(scanned) do
    if self:IsCandidate(item) then
      table.insert(candidates, item)
    end
  end

  local best = self:SelectBest(candidates)
  ns.Print("%d upgrade(s) selected (of %d usable/spec-appropriate/higher-ilvl candidates):",
    #best, #candidates)
  for _, item in ipairs(best) do
    local baseline = self:GetBaselineItemLevel(item.equipLoc)
    print(("  %s: ilvl %d vs. equipped ilvl %s (%s, %s)"):format(
      item.name or item.hyperlink, item.itemLevel or 0, tostring(baseline),
      item.equipLoc or "?", item.source or "?"))
  end
end

-- Debug helper (#35): finds an equipped item by name substring.
function Upgrade:FindEquippedLink(query)
  for _, slotName in ipairs(ALL_INVENTORY_SLOTS) do
    local slotID = GetInventorySlotInfo(slotName)
    local link = slotID and GetInventoryItemLink("player", slotID)
    if link then
      local name = C_Item.GetItemInfo(link)
      if name and name:lower():find(query, 1, true) then
        return link, slotName
      end
    end
  end
  return nil
end

-- True when a two-hand weapon occupies the main hand (#37).
local function IsMainHandTwoHanded()
  local slotID = GetInventorySlotInfo("MainHandSlot")
  local link = slotID and GetInventoryItemLink("player", slotID)
  if not link then
    return false
  end
  return select(9, C_Item.GetItemInfo(link)) == "INVTYPE_2HWEAPON"
end

-- Proficient (#35), usable (#15), spec-appropriate, and better than what's
-- equipped. Off-hands stay eligible under an equipped two-hander;
-- SelectBest decides (#37).
function Upgrade:IsCandidate(item)
  if not RELEVANT_QUALITIES[item.quality] then
    return false
  end
  if not ns.Classify:IsClassProficient(item) then
    return false
  end
  if not ns.Classify:IsUsable(item.hyperlink) then
    return false
  end
  if not ns.Classify:IsSpecAppropriate(item.hyperlink) then
    return false
  end
  if not self:IsUpgradeOverEquipped(item) then
    return false
  end
  return true
end

local function BestOf(list)
  local best
  for _, item in ipairs(list) do
    if not best or item.itemLevel > best.itemLevel then
      best = item
    end
  end
  return best
end

local function TopTwo(list)
  local sorted = {}
  for _, item in ipairs(list) do
    table.insert(sorted, item)
  end
  table.sort(sorted, function(a, b) return a.itemLevel > b.itemLevel end)
  return sorted[1], sorted[2]
end

-- Two-hand vs. one-hand+offhand (#37), shared with DumpWeaponComparison
-- (#39). Scored as the average item level across both weapon slots,
-- against what's equipped now. A two-hander fills both slots at its own
-- level, matching how GetAverageItemLevel counts it.
--
-- Returns bestTwoHand, bestMainHand, bestOffHand (any may be nil;
-- bestOffHand is nil under an equipped two-hander with no main-hand
-- candidate), equippedTwoHand, equippedMainLevel, equippedOffLevel,
-- currentAverage, twoHandAverage, oneHandAverage (last two nilable), and
-- winner ("current", "twoHand", or "oneHand").
local function DecideWeapons(twoHand, mainHand, offHand)
  local bestTwoHand = BestOf(twoHand)
  local bestMainHand = BestOf(mainHand)
  local bestOffHand = BestOf(offHand)

  local equippedTwoHand = IsMainHandTwoHanded()
  local equippedMainLevel = GetEquippedItemLevel("MainHandSlot")
  local equippedOffLevel = GetEquippedItemLevel("SecondaryHandSlot")

  if equippedTwoHand and not bestMainHand then
    bestOffHand = nil
  end

  local currentAverage = equippedTwoHand
    and equippedMainLevel
    or (equippedMainLevel + equippedOffLevel) / 2

  local twoHandAverage = bestTwoHand and bestTwoHand.itemLevel or nil

  local oneHandAverage
  if bestMainHand then
    local offLevel = bestOffHand and bestOffHand.itemLevel or (not equippedTwoHand and equippedOffLevel or 0)
    oneHandAverage = (bestMainHand.itemLevel + offLevel) / 2
  end

  local bestAverage, winner = currentAverage, "current"
  if twoHandAverage and twoHandAverage > bestAverage then
    bestAverage, winner = twoHandAverage, "twoHand"
  end
  if oneHandAverage and oneHandAverage > bestAverage then
    winner = "oneHand"
  end

  return {
    bestTwoHand = bestTwoHand, bestMainHand = bestMainHand, bestOffHand = bestOffHand,
    equippedTwoHand = equippedTwoHand, equippedMainLevel = equippedMainLevel, equippedOffLevel = equippedOffLevel,
    currentAverage = currentAverage, twoHandAverage = twoHandAverage, oneHandAverage = oneHandAverage,
    winner = winner,
  }
end

-- The items to pre-check from a filtered candidate set: highest item level
-- per slot, top two for rings/trinkets, and the winning weapon set.
function Upgrade:SelectBest(candidates)
  local buckets = {}
  local twoHand, mainHand, offHand = {}, {}, {}

  for _, item in ipairs(candidates) do
    if TWO_HAND[item.equipLoc] then
      table.insert(twoHand, item)
    elseif MAIN_HAND[item.equipLoc] then
      table.insert(mainHand, item)
    elseif OFF_HAND[item.equipLoc] then
      table.insert(offHand, item)
    else
      buckets[item.equipLoc] = buckets[item.equipLoc] or {}
      table.insert(buckets[item.equipLoc], item)
    end
  end

  local selected = {}

  for equipLoc, list in pairs(buckets) do
    if DUAL_SLOT[equipLoc] then
      local first, second = TopTwo(list)
      if first then table.insert(selected, first) end
      if second then table.insert(selected, second) end
    else
      local best = BestOf(list)
      if best then table.insert(selected, best) end
    end
  end

  local decision = DecideWeapons(twoHand, mainHand, offHand)
  if decision.winner == "twoHand" then
    table.insert(selected, decision.bestTwoHand)
  elseif decision.winner == "oneHand" then
    table.insert(selected, decision.bestMainHand)
    if decision.bestOffHand then table.insert(selected, decision.bestOffHand) end
  end

  return selected
end

-- Debug dump (#39): DecideWeapons' inputs, scores and winner.
function Upgrade:DumpWeaponComparison()
  local scanned = ns.Scanner:ScanAll()
  local twoHand, mainHand, offHand = {}, {}, {}

  for _, item in ipairs(scanned) do
    if self:IsCandidate(item) then
      if TWO_HAND[item.equipLoc] then
        table.insert(twoHand, item)
      elseif MAIN_HAND[item.equipLoc] then
        table.insert(mainHand, item)
      elseif OFF_HAND[item.equipLoc] then
        table.insert(offHand, item)
      end
    end
  end

  local d = DecideWeapons(twoHand, mainHand, offHand)

  ns.Print("Weapon comparison:")
  print(("  Equipped: %s two-hand, main-hand ilvl %d, off-hand ilvl %d"):format(
    d.equippedTwoHand and "is" or "not", d.equippedMainLevel, d.equippedOffLevel))
  print(("  Current average: %.1f"):format(d.currentAverage))
  print(("  Two-hand candidate: %s (average %s)"):format(
    d.bestTwoHand and (d.bestTwoHand.name or d.bestTwoHand.hyperlink) or "none",
    d.twoHandAverage and ("%.1f"):format(d.twoHandAverage) or "n/a"))
  print(("  One-hand candidate: main-hand %s, off-hand %s (average %s)"):format(
    d.bestMainHand and (d.bestMainHand.name or d.bestMainHand.hyperlink) or "none",
    d.bestOffHand and (d.bestOffHand.name or d.bestOffHand.hyperlink) or "none",
    d.oneHandAverage and ("%.1f"):format(d.oneHandAverage) or "n/a"))
  print(("  Winner: %s"):format(d.winner))
end
