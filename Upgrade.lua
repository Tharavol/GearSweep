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

-- Real inventory slot names (Blizzard's GetInventorySlotInfo) an equip
-- location's currently-equipped item level gets read from, for the "is
-- this actually higher than what I'm wearing" comparison below. Finger and
-- Trinket map to both of their physical slots. Off-hand-shaped equip locs
-- (shield/holdable/relic) all read the same SecondaryHandSlot: whichever
-- of them is equipped occupies that slot exclusively.
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

-- Every physical equipment slot, for the #28 debug dump - not otherwise
-- iterated over as a group, since IsUpgradeOverEquipped only looks up the
-- specific slot(s) an item's equipLoc maps to.
local ALL_INVENTORY_SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WaistSlot",
  "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
  "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

-- Returns the equipped item's level, its link, and the slot's numeric ID -
-- the link/ID are only for #28's debug dump, which needs to show what's
-- actually equipped, not just the number IsUpgradeOverEquipped computes.
local function GetEquippedItemLevel(slotName)
  local slotID = GetInventorySlotInfo(slotName)
  if not slotID then
    return 0, nil, nil
  end
  local link = GetInventoryItemLink("player", slotID)
  if not link then
    return 0, nil, slotID
  end
  local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  if not level then
    level = select(4, C_Item.GetItemInfo(link))
  end
  return level or 0, link, slotID
end

-- The equipped item level an equip location's candidates are compared
-- against: the lower of the two equipped items for dual-slot types
-- (finger/trinket), the one equipped item otherwise. A slot that's
-- genuinely empty (never equipped anything, e.g. a caster's off-hand)
-- falls back to the character's overall average equipped item level
-- rather than 0 (#36) - confirmed live that an ilvl 15 off-hand item
-- otherwise "won" against nothing, when it's obviously not a real
-- upgrade for a character wearing ilvl ~290 everywhere else.
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

  if baseline == 0 and GetAverageItemLevel then
    local _, avgEquipped = GetAverageItemLevel()
    baseline = avgEquipped or 0
  end

  return baseline
end

-- True when the item's own level beats the equipped item it would actually
-- replace (see GetBaselineItemLevel). This is the actual "is it an
-- upgrade" check (#16) - IsUsable/IsSpecAppropriate alone only say the
-- item is wearable, not that it's better than current gear (confirmed
-- live: an ilvl ~100-141 quest reward otherwise passed those checks and
-- was wrongly listed against ilvl 238 equipped gear).
function Upgrade:IsUpgradeOverEquipped(item)
  local baseline = self:GetBaselineItemLevel(item.equipLoc)
  if baseline == nil then
    return true
  end
  return (item.itemLevel or 0) > baseline
end

-- #28 debug dump: every equipment slot's currently-equipped item and level,
-- so a live report can be compared directly against what Upgrade mode is
-- (or isn't) treating as an upgrade.
function Upgrade:DumpEquippedSlots()
  ns.Print("Equipped item levels:")
  for _, slotName in ipairs(ALL_INVENTORY_SLOTS) do
    local level, link = GetEquippedItemLevel(slotName)
    print(("  %s: %s (ilvl %d)"):format(slotName, link or "(empty)", level))
  end
end

-- #28 debug dump: re-runs the exact same candidate/select pipeline the
-- sweep window's Upgrade mode uses, printing each selected item alongside
-- the equipped item level it was actually compared against.
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

-- #35 debug helper: finds an equipped item by case-insensitive substring,
-- for comparing a known-bound/known-usable item's C_Item.IsUsableItem
-- result against the false readings seen for unbound Warband Bank items.
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

-- True when a two-hand weapon currently occupies the main hand. Used by
-- SelectBest to score the two-hand/one-hand+offhand decision (#37) -
-- not a hard gate in IsCandidate, since a class that can go either way
-- might have a one-hand+offhand combo worth switching to.
local function IsMainHandTwoHanded()
  local slotID = GetInventorySlotInfo("MainHandSlot")
  local link = slotID and GetInventoryItemLink("player", slotID)
  if not link then
    return false
  end
  return select(9, C_Item.GetItemInfo(link)) == "INVTYPE_2HWEAPON"
end

-- Whether the character can actually use the item: class/armor/weapon
-- proficiency (#35 - a hand-maintained table, since no live signal covers
-- this for Warband Bank items), the tooltip's own requirement-line
-- "usable" flag (level/reputation/quest gates, #8/#15), whether it's
-- relevant to the current spec, and whether it's actually better than
-- what's equipped. Off-hand-slot items are not excluded just because a
-- two-hander is currently equipped (#37) - SelectBest decides whether
-- switching to a one-hand+offhand combo is actually worth it.
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

-- Given an already-filtered candidate set (see IsCandidate), returns the
-- items to pre-check as "the" upgrade pick for each slot: the single
-- highest item level per slot, except rings/trinkets (top two distinct
-- items) and the two-hand/one-hand+offhand pair (whichever combination
-- scores higher as a set, never both at once).
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

  -- Two-hand vs. one-hand+offhand (#37): scored as the average item level
  -- across both weapon slots - a two-hander counts as filling both at its
  -- own level - and compared against the average of what's actually
  -- equipped right now, so a hybrid class that can genuinely go either
  -- way gets whichever option is actually better, not a rule that always
  -- favors one shape over the other. Previously off-hand items were
  -- simply excluded outright whenever a two-hander was equipped - correct
  -- for classes that can't dual-wield at all, but too strong for classes
  -- that can.
  local bestTwoHand = BestOf(twoHand)
  local bestMainHand = BestOf(mainHand)
  local bestOffHand = BestOf(offHand)

  local equippedTwoHand = IsMainHandTwoHanded()
  local equippedMainLevel = GetEquippedItemLevel("MainHandSlot")
  local equippedOffLevel = GetEquippedItemLevel("SecondaryHandSlot")

  -- An off-hand candidate can't be equipped on its own while a two-hander
  -- stays equipped and no one-hand candidate exists to replace it - the
  -- physical off-hand slot is blocked in that case, regardless of level.
  if equippedTwoHand and not bestMainHand then
    bestOffHand = nil
  end

  local currentAverage = equippedTwoHand
    and equippedMainLevel
    or (equippedMainLevel + equippedOffLevel) / 2

  local twoHandAverage = bestTwoHand and bestTwoHand.itemLevel or nil

  local oneHandAverage
  if bestMainHand then
    if bestOffHand then
      oneHandAverage = (bestMainHand.itemLevel + bestOffHand.itemLevel) / 2
    elseif equippedTwoHand then
      -- No off-hand candidate, and the off-hand is already empty right
      -- now (blocked by the equipped two-hander) - switching to this
      -- main-hand item alone doesn't cost anything there, so compare it
      -- directly instead of diluting it against a slot that was never
      -- going to be filled either way (confirmed live: a 292 wand was
      -- wrongly weighed against a 256 staff as if losing an off-hand
      -- item it never had).
      oneHandAverage = bestMainHand.itemLevel
    else
      -- Already one-hand/dual-wield: the off-hand keeps whatever's
      -- currently equipped there if no better candidate was found for it.
      oneHandAverage = (bestMainHand.itemLevel + equippedOffLevel) / 2
    end
  end

  local bestAverage, bestOption = currentAverage, "current"
  if twoHandAverage and twoHandAverage > bestAverage then
    bestAverage, bestOption = twoHandAverage, "twoHand"
  end
  if oneHandAverage and oneHandAverage > bestAverage then
    bestOption = "oneHand"
  end

  if bestOption == "twoHand" then
    table.insert(selected, bestTwoHand)
  elseif bestOption == "oneHand" then
    table.insert(selected, bestMainHand)
    if bestOffHand then table.insert(selected, bestOffHand) end
  end

  return selected
end
