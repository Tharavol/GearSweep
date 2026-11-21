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
-- No tooltip line or API exposes proficiency, so this is a hand-maintained
-- table, cross-referenced against the Unfit-1.0 library (GPL-3.0,
-- https://www.curseforge.com/wow/addons/unfit).
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

-- Each class's own armor type, matched exactly rather than "that type or
-- lighter": an upgrade needs a real stat gain, not merely equippable gear
-- (#40). Shields are checked separately.
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

-- Hidden tooltip for reading item text in the background. It receives the
-- same contextual annotations (e.g. "Best in Slot") as GameTooltip (#10).
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

-- The upgrade-track line (C_TooltipInfo line type 32) is present only while
-- an item's track is current; previous-season items lose it (#9).
-- Returns {name, currentLevel, maxLevel} or nil.
function Classify:GetUpgradeTrackInfo(link)
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

-- True when the item still carries an upgrade track (current season).
function Classify:IsCurrentSeason(link)
  return self:GetUpgradeTrackInfo(link) ~= nil
end

function Classify:IsAdventurerTier(link)
  local track = self:GetUpgradeTrackInfo(link)
  return track ~= nil and track.name == "Adventurer"
end

-- Reads the "usable" flag on requirement lines (type 43: level/skill/
-- reputation). Not C_Item.IsUsableItem: it reports unbound Warband Bank
-- gear as unusable (#35).
function Classify:IsUsable(link)
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

-- Debug dump (#35): an item's plain and structured tooltip lines.
function Classify:DumpTooltip(link)
  ns.Print("Plain tooltip lines:")
  for i, rawLine in ipairs(GetTooltipLines(link)) do
    print(("  %d: %s"):format(i, CleanLine(rawLine)))
  end

  local data = C_TooltipInfo.GetHyperlink(link)
  if data and data.lines then
    print("Structured tooltip lines:")
    for i, line in ipairs(data.lines) do
      print(("  %d: type=%s usable=%s leftText=%s"):format(
        i, tostring(line.type), tostring(line.usable), tostring(line.leftText)))
    end
  end

  local usable, noMana = C_Item.IsUsableItem(link)
  print(("C_Item.IsUsableItem: usable=%s noMana=%s"):format(tostring(usable), tostring(noMana)))

  print(("IsUsable: %s"):format(tostring(self:IsUsable(link))))
end

-- "Best in Slot" label lines (e.g. "Holy Paladin"), read from the plain
-- tooltip text since structured C_TooltipInfo data lacks them (#10).
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

-- True when the item has no "Best in Slot" annotation (most gear), or the
-- annotation names the character's current class and spec.
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

-- Uncommon, Rare, Epic. Poor and Common are never disenchant material.
local DISENCHANT_QUALITIES = { [2] = true, [3] = true, [4] = true }

function Classify:IsDisenchantEligibleQuality(quality)
  return DISENCHANT_QUALITIES[quality] == true
end

-- Disenchant candidate (#11): eligible quality, and either Adventurer tier
-- or from a previous season/expansion.
function Classify:IsDisenchantCandidate(item)
  if not self:IsDisenchantEligibleQuality(item.quality) then
    return false
  end

  local isAdventurer = self:IsAdventurerTier(item.hyperlink)
  local isPreviousSeason = not self:IsCurrentSeason(item.hyperlink)
  return isAdventurer or isPreviousSeason
end
