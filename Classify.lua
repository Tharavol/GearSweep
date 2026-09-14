local ADDON_NAME, ns = ...

local Classify = {}
ns.Classify = Classify

-- Strips WoW's inline texture (|T...|t) and color (|cXXXXXXXX...|r) escape
-- codes so tooltip text can be matched as plain words.
local function StripEscapes(text)
  text = text:gsub("|T.-|t", "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

local function CleanLine(rawLine)
  return strtrim(StripEscapes(rawLine or ""))
end

--------------------------------------------------------------------------
-- Class armor/weapon proficiency (#35)
--
-- No live signal exposes this: confirmed live that a shield's tooltip on
-- a Mage (plain and structured) carries no proficiency line at all, and
-- C_Item.IsUsableItem returns usable=false even for the player's own
-- equipped gear - not a proficiency check for anything, apparently. This
-- table is the only remaining option. Data cross-referenced against the
-- Unfit-1.0 library (GPL-3.0-licensed, embedded in Bagnon/AdiBags/etc,
-- https://www.curseforge.com/wow/addons/unfit) rather than re-derived
-- from memory, since getting this list subtly wrong would be worse than
-- not having the feature at all.
--------------------------------------------------------------------------

local W = Enum.ItemWeaponSubclass
local A = Enum.ItemArmorSubclass

local UNUSABLE_WEAPON_SUBCLASSES = {
  DEATHKNIGHT = { [W.Bows]=true, [W.Guns]=true, [W.Warglaive]=true, [W.Staff]=true, [W.Unarmed]=true,
    [W.Dagger]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  DEMONHUNTER = { [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Mace1H]=true, [W.Mace2H]=true,
    [W.Polearm]=true, [W.Sword2H]=true, [W.Staff]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  DRUID = { [W.Axe1H]=true, [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Sword1H]=true, [W.Sword2H]=true,
    [W.Warglaive]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  EVOKER = { [W.Bows]=true, [W.Guns]=true, [W.Polearm]=true, [W.Warglaive]=true, [W.Thrown]=true,
    [W.Crossbow]=true, [W.Wand]=true },
  HUNTER = { [W.Mace1H]=true, [W.Mace2H]=true, [W.Warglaive]=true, [W.Thrown]=true, [W.Wand]=true },
  MAGE = { [W.Axe1H]=true, [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Mace1H]=true, [W.Mace2H]=true,
    [W.Polearm]=true, [W.Sword2H]=true, [W.Warglaive]=true, [W.Unarmed]=true, [W.Thrown]=true, [W.Crossbow]=true },
  MONK = { [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Mace2H]=true, [W.Sword2H]=true, [W.Warglaive]=true,
    [W.Dagger]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  PALADIN = { [W.Bows]=true, [W.Guns]=true, [W.Warglaive]=true, [W.Staff]=true, [W.Unarmed]=true,
    [W.Dagger]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  PRIEST = { [W.Axe1H]=true, [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Mace2H]=true, [W.Polearm]=true,
    [W.Sword1H]=true, [W.Sword2H]=true, [W.Warglaive]=true, [W.Unarmed]=true, [W.Thrown]=true, [W.Crossbow]=true },
  ROGUE = { [W.Axe2H]=true, [W.Mace2H]=true, [W.Polearm]=true, [W.Sword2H]=true, [W.Warglaive]=true,
    [W.Staff]=true, [W.Wand]=true },
  SHAMAN = { [W.Bows]=true, [W.Guns]=true, [W.Polearm]=true, [W.Sword1H]=true, [W.Sword2H]=true,
    [W.Warglaive]=true, [W.Thrown]=true, [W.Crossbow]=true, [W.Wand]=true },
  WARLOCK = { [W.Axe1H]=true, [W.Axe2H]=true, [W.Bows]=true, [W.Guns]=true, [W.Mace1H]=true, [W.Mace2H]=true,
    [W.Polearm]=true, [W.Sword2H]=true, [W.Warglaive]=true, [W.Unarmed]=true, [W.Thrown]=true, [W.Crossbow]=true },
  WARRIOR = { [W.Warglaive]=true, [W.Wand]=true },
}

-- Each class's own real armor type - not "that type or anything lighter"
-- (confirmed live, #40: a Death Knight, plate's own class, was recommended
-- non-plate armor because the previous table only ever excluded the
-- heavier types above a class's own, e.g. excluding Mail/Plate for a
-- Leather class but never excluding Cloth for anyone above it - so every
-- plate class had essentially no armor-type restriction at all beyond
-- shields). An upgrade recommendation needs a real stat gain, not merely
-- technically-equippable gear, so this is an exact match against a
-- class's one real armor type, checked separately from shield usability.
local CLASS_ARMOR_TYPE = {
  DEATHKNIGHT = A.Plate,
  DEMONHUNTER = A.Leather,
  DRUID = A.Leather,
  EVOKER = A.Mail,
  HUNTER = A.Mail,
  MAGE = A.Cloth,
  MONK = A.Leather,
  PALADIN = A.Plate,
  PRIEST = A.Cloth,
  ROGUE = A.Leather,
  SHAMAN = A.Mail,
  WARLOCK = A.Cloth,
  WARRIOR = A.Plate,
}

-- Only Warrior, Paladin, and Shaman can equip a shield at all - independent
-- of armor type, since Death Knight (also plate) cannot.
local CAN_USE_SHIELD = {
  PALADIN = true, SHAMAN = true, WARRIOR = true,
}

-- The four real wearable armor tiers CLASS_ARMOR_TYPE gates on; anything
-- else (Cosmetic, or the old relic-ish off-hand subclasses) isn't a
-- class-restricted armor type at all.
local WEARABLE_ARMOR_TYPES = { [A.Cloth]=true, [A.Leather]=true, [A.Mail]=true, [A.Plate]=true }

-- Classes that cannot dual-wield: an off-hand weapon (INVTYPE_WEAPONOFFHAND
-- - a literal second weapon, not a shield/holdable/relic) is never usable
-- for them regardless of its own weapon subclass.
local CANNOT_DUAL_WIELD = {
  DRUID = true, EVOKER = true, MAGE = true, PALADIN = true, PRIEST = true, WARLOCK = true,
}

-- True unless the player's class lacks proficiency for this item's armor
-- type or weapon type. Unlisted classes/subclasses (e.g. holdable
-- off-hand items, which no class is ever restricted from) default usable.
function Classify:IsClassProficient(item)
  local class = UnitClassBase and UnitClassBase("player")
  if not class or not item.classID or not item.subclassID then
    return true
  end

  if item.classID == Enum.ItemClass.Weapon then
    if item.equipLoc == "INVTYPE_WEAPONOFFHAND" and CANNOT_DUAL_WIELD[class] then
      return false
    end
    local unusable = UNUSABLE_WEAPON_SUBCLASSES[class]
    return not (unusable and unusable[item.subclassID])
  end

  if item.classID == Enum.ItemClass.Armor then
    if item.subclassID == A.Shield then
      return CAN_USE_SHIELD[class] == true
    end
    local ownType = CLASS_ARMOR_TYPE[class]
    if not ownType or not WEARABLE_ARMOR_TYPES[item.subclassID] then
      return true
    end
    return item.subclassID == ownType
  end

  return true
end

-- A dedicated, never-shown tooltip for reading any item's tooltip text in
-- the background - the only way to classify hundreds of bag/bank items
-- without literally hovering each one. Confirmed live (#10): a tooltip
-- like this receives the same contextual annotations (e.g. "Best in Slot")
-- as the default GameTooltip, not just the raw item hyperlink data.
local scanTooltip

local function GetScanTooltip()
  if not scanTooltip then
    scanTooltip = CreateFrame("GameTooltip", "GearSweepClassifyTooltip", nil, "GameTooltipTemplate")
  end
  return scanTooltip
end

local function GetTooltipLines(link)
  local tooltip = GetScanTooltip()
  tooltip:SetOwner(UIParent, "ANCHOR_NONE")
  tooltip:SetHyperlink(link)

  local lines = {}
  for i = 1, tooltip:NumLines() do
    local fs = _G[tooltip:GetName() .. "TextLeft" .. i]
    lines[i] = fs and fs:GetText() or ""
  end
  return lines
end

-- The upgrade-track line (structured C_TooltipInfo line type 32) is
-- present only while an item's track is still current; a previous-season
-- item keeps its item level but loses this line entirely (confirmed live,
-- comparing this season's and last season's Adventurer-tier gear - #9).
-- Returns {name, currentLevel, maxLevel} or nil.
function Classify:GetUpgradeTrackInfo(link)
  if not C_TooltipInfo then
    return nil
  end

  local data = C_TooltipInfo.GetHyperlink(link)
  if not data or not data.lines then
    return nil
  end

  for _, line in ipairs(data.lines) do
    if line.type == 32 then
      local name = line.leftText and line.leftText:match("Upgrade Level: (%a+)")
      return {
        name = name,
        currentLevel = line.currentLevel,
        maxLevel = line.maxLevel,
      }
    end
  end

  return nil
end

-- True when the item still carries an upgrade track, i.e. it's from the
-- current season. False for previous-season or older-expansion gear.
function Classify:IsCurrentSeason(link)
  return self:GetUpgradeTrackInfo(link) ~= nil
end

function Classify:IsAdventurerTier(link)
  local track = self:GetUpgradeTrackInfo(link)
  return track ~= nil and track.name == "Adventurer"
end

-- C_Item.IsUsableItem looked like the real class/armor/weapon proficiency
-- signal (#35) - it correctly flagged a shield as unusable on a Mage -
-- but confirmed live it ALSO returns usable=false for a plain cloth chest
-- piece the same Mage can obviously wear, as long as the item is still
-- Warband-Bank-sourced ("Binds to Warband until equipped", not yet bound
-- to this character). It isn't a proficiency check for these items at
-- all - likely some form of ownership/binding gate - so it's not used
-- here. Scans structured requirement lines (type 43: level/skill/
-- reputation requirements) for Blizzard's own "usable" flag instead; see
-- #35 for the still-open problem of detecting armor/weapon proficiency
-- itself, which this tooltip data doesn't carry for these items either.
function Classify:IsUsable(link)
  if not C_TooltipInfo then
    return true
  end

  local data = C_TooltipInfo.GetHyperlink(link)
  if not data or not data.lines then
    return true
  end

  for _, line in ipairs(data.lines) do
    if line.type == 43 and line.usable == false then
      return false
    end
  end

  return true
end

-- #35 debug dump: raw tooltip data for one item (plain text plus every
-- structured C_TooltipInfo line's type/usable/leftText), so a live report
-- can show exactly what Blizzard's tooltip actually says about an item
-- IsUsable got wrong, rather than guessing at tooltip structure again.
function Classify:DumpTooltip(link)
  ns.Print("Plain tooltip lines:")
  for i, rawLine in ipairs(GetTooltipLines(link)) do
    print(("  %d: %s"):format(i, CleanLine(rawLine)))
  end

  if C_TooltipInfo then
    local data = C_TooltipInfo.GetHyperlink(link)
    if data and data.lines then
      print("Structured tooltip lines:")
      for i, line in ipairs(data.lines) do
        print(("  %d: type=%s usable=%s leftText=%s"):format(
          i, tostring(line.type), tostring(line.usable), tostring(line.leftText)))
      end
    end
  end

  if C_Item and C_Item.IsUsableItem then
    local usable, noMana = C_Item.IsUsableItem(link)
    print(("C_Item.IsUsableItem: usable=%s noMana=%s"):format(tostring(usable), tostring(noMana)))
  end

  print(("IsUsable: %s"):format(tostring(self:IsUsable(link))))
end

-- Raw "Best in Slot" label lines (e.g. "Holy Paladin"), read off a
-- background tooltip since this annotation isn't in the structured
-- C_TooltipInfo data (#10). Empty when the item has no such annotation -
-- most gear doesn't, and that alone isn't a sign of irrelevance.
function Classify:GetBestInSlotSpecs(link)
  local lines = GetTooltipLines(link)
  local specs = {}
  local inSection = false

  for _, rawLine in ipairs(lines) do
    local line = CleanLine(rawLine)
    if line == "Best in Slot" then
      inSection = true
    elseif inSection then
      if line == "" then
        break
      end
      table.insert(specs, line)
    end
  end

  return specs
end

-- True when the item either has no "Best in Slot" annotation at all (most
-- gear - not a signal either way), or its annotation includes the
-- character's current class and spec.
function Classify:IsSpecAppropriate(link)
  local specs = self:GetBestInSlotSpecs(link)
  if #specs == 0 then
    return true
  end

  local className = UnitClass("player")
  local specIndex = GetSpecialization()
  local specName = specIndex and select(2, GetSpecializationInfo(specIndex))
  if not specName or not className then
    return true
  end

  for _, label in ipairs(specs) do
    if label:find(specName, 1, true) and label:find(className, 1, true) then
      return true
    end
  end

  return false
end

-- Uncommon (green), Rare (blue), Epic (purple). Poor and Common (white) -
-- shirts included, since those are Common anyway - are never disenchant
-- material.
local DISENCHANT_QUALITIES = { [2] = true, [3] = true, [4] = true }

function Classify:IsDisenchantEligibleQuality(quality)
  return DISENCHANT_QUALITIES[quality] == true
end

-- The baseline definition of a disenchant candidate (#11): eligible
-- quality, and either Adventurer tier (current season's lowest track) or
-- from a previous season/expansion entirely. Never true for current-season
-- gear above Adventurer tier. Scanner only enumerates bags/bank contents,
-- never equipped-item slots, so a currently-equipped item can never reach
-- this check in the first place.
function Classify:IsDisenchantCandidate(item)
  if not self:IsDisenchantEligibleQuality(item.quality) then
    return false
  end

  local isAdventurer = self:IsAdventurerTier(item.hyperlink)
  local isPreviousSeason = not self:IsCurrentSeason(item.hyperlink)
  return isAdventurer or isPreviousSeason
end
