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

-- C_Item.IsUsableItem is the real class/armor/weapon proficiency signal
-- (#35): confirmed live that a shield's tooltip on a Mage carries no
-- requirement line at all (no "Classes:" text, structured or plain) - the
-- only type-43 line was "Requires Level 90", usable=true - yet
-- IsUsableItem correctly reported usable=false. Tooltip requirement lines
-- (level/reputation/quest-gated items, still real and still worth
-- catching) are checked as a second, independent gate.
function Classify:IsUsable(link)
  if C_Item and C_Item.IsUsableItem then
    local usable = C_Item.IsUsableItem(link)
    if usable == false then
      return false
    end
  end

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
