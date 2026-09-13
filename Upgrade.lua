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

local function GetEquippedItemLevel(slotName)
  local slotID = GetInventorySlotInfo(slotName)
  if not slotID then
    return 0
  end
  local link = GetInventoryItemLink("player", slotID)
  if not link then
    return 0
  end
  local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  if not level then
    level = select(4, C_Item.GetItemInfo(link))
  end
  return level or 0
end

-- True when the item's own level beats the equipped item it would actually
-- replace - the lower of the two equipped items for dual-slot types
-- (finger/trinket), the one equipped item otherwise. An empty slot reads
-- as item level 0, so anything real counts as an upgrade there. This is
-- the actual "is it an upgrade" check (#16) - IsUsable/IsSpecAppropriate
-- alone only say the item is wearable, not that it's better than current
-- gear (confirmed live: an ilvl ~100-141 quest reward otherwise passed
-- those checks and was wrongly listed against ilvl 238 equipped gear).
function Upgrade:IsUpgradeOverEquipped(item)
  local slots = EQUIP_LOC_TO_INVENTORY_SLOTS[item.equipLoc]
  if not slots then
    return true
  end

  local baseline
  for _, slotName in ipairs(slots) do
    local level = GetEquippedItemLevel(slotName)
    if not baseline or level < baseline then
      baseline = level
    end
  end

  return (item.itemLevel or 0) > (baseline or 0)
end

-- Whether the character can actually use the item (class/armor/weapon
-- proficiency, level, etc.), whether it's relevant to the current spec -
-- reusing Blizzard's own tooltip signals (#8/#15) rather than a hand-rolled
-- proficiency table - and whether it's actually better than what's equipped.
function Upgrade:IsCandidate(item)
  if not RELEVANT_QUALITIES[item.quality] then
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

  -- Scored as total item level filled rather than per-item, since a real
  -- off-hand candidate means the one-hand+offhand pair covers two
  -- independent gear slots the two-hand item would otherwise leave one of
  -- untouched; two-hand only wins when there's no off-hand candidate to
  -- pair with (the sum then reduces to the lone main-hand item's level).
  local bestTwoHand = BestOf(twoHand)
  local bestMainHand = BestOf(mainHand)
  local bestOffHand = BestOf(offHand)
  local hasOneHand = bestMainHand or bestOffHand

  if bestTwoHand and (not hasOneHand or bestTwoHand.itemLevel >= (
      (bestMainHand and bestMainHand.itemLevel or 0) + (bestOffHand and bestOffHand.itemLevel or 0))) then
    table.insert(selected, bestTwoHand)
  elseif hasOneHand then
    if bestMainHand then table.insert(selected, bestMainHand) end
    if bestOffHand then table.insert(selected, bestOffHand) end
  end

  return selected
end
