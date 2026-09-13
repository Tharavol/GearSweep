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

-- Whether the character can actually use the item (class/armor/weapon
-- proficiency, level, etc.) and whether it's relevant to the current spec,
-- reusing Blizzard's own tooltip signals (#8/#15) rather than a hand-rolled
-- proficiency table.
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
