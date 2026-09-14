-- Offline tests for the parts of GearSweep that don't need the game client.
--
--   lua Tests/run.lua        (run from the addon folder)

local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local stubs = require("wow_stubs")
stubs.install(_G)

--------------------------------------------------------------------------
-- Tiny test harness
--------------------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function check(condition, name, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name .. (detail and ("\n      " .. detail) or ""))
  end
end

local function equals(actual, expected, name)
  check(actual == expected, name,
    ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

--------------------------------------------------------------------------
-- Module loading
--------------------------------------------------------------------------

local printedMessages = {}

local ns = {
  ADDON_NAME = "GearSweep",
  VERSION = "test",
  Print = function(fmt, ...)
    table.insert(printedMessages, select("#", ...) > 0 and fmt:format(...) or fmt)
  end,
  Debug = function() end,
}

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = deepCopy(v) end
  return copy
end
ns.DeepCopy = deepCopy

ns.DEFAULT_SETTINGS = {
  debug = false,
  autoOpen = true,
  disenchant = { excludedQualities = {}, includeAdventurerTier = true },
}
ns.db = deepCopy(ns.DEFAULT_SETTINGS)

local optionsOpened, sweepOpened
ns.Options = {
  Open = function(_self)
    optionsOpened = true
  end,
}
ns.UI = {
  Show = function(_self)
    sweepOpened = true
  end,
}

stubs.loadModule(here .. "/../Commands.lua", "GearSweep", ns)

local originalPrint = print
local plainLines

-- Dispatches one command, capturing both ns.Print (into printedMessages)
-- and the bare print() calls PrintUsage uses (into plainLines).
local function dispatch(input)
  printedMessages = {}
  plainLines = {}
  print = function(msg) table.insert(plainLines, msg) end
  ns.Commands:Dispatch(input)
  print = originalPrint
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

do
  dispatch("bogus")
  equals(printedMessages[1], "Unknown command: bogus",
    "an unknown command says what was unrecognised")
  check(#plainLines > 0, "falls back to usage")
end

do
  dispatch("help")
  equals(printedMessages[1], "test commands:", "help prints only the usage header, no error")
end

do
  sweepOpened = false
  dispatch("")
  check(sweepOpened, "an empty command opens the sweep window")
  equals(#printedMessages, 0, "opening the sweep window prints nothing")
end

do
  optionsOpened = false
  dispatch("options")
  check(optionsOpened, "the options command opens the settings panel")
end

do
  optionsOpened = false
  dispatch("config")
  check(optionsOpened, "the config alias opens the settings panel")
end

do
  optionsOpened = false
  dispatch("gui")
  check(optionsOpened, "the gui alias opens the settings panel")
end

do
  dispatch("debug on")
  equals(ns.db.debug, true, "debug on enables diagnostic messages")
  dispatch("debug off")
  equals(ns.db.debug, false, "debug off disables diagnostic messages")
end

do
  ns.db.debug = false
  dispatch("debug")
  equals(ns.db.debug, true, "bare debug toggles the current state")
  dispatch("debug")
  equals(ns.db.debug, false, "bare debug toggles back")
end

do
  ns.db.debug = true
  dispatch("debug yes")
  equals(ns.db.debug, true, "an invalid value leaves the setting unchanged")
  equals(printedMessages[1], "'yes' - expected 'on', 'off', 'slots', 'upgrades', 'weapons', or 'item <name>'.",
    "an invalid value is rejected with a specific error")
  ns.db.debug = false
end

do
  dispatch("autoopen on")
  equals(ns.db.autoOpen, true, "autoopen on enables auto-open")
  dispatch("autoopen off")
  equals(ns.db.autoOpen, false, "autoopen off disables auto-open")
end

do
  ns.db.autoOpen = false
  dispatch("autoopen")
  equals(ns.db.autoOpen, true, "bare autoopen toggles the current state")
  dispatch("autoopen")
  equals(ns.db.autoOpen, false, "bare autoopen toggles back")
end

do
  ns.db.autoOpen = true
  dispatch("autoopen yes")
  equals(ns.db.autoOpen, true, "an invalid value leaves autoopen unchanged")
  equals(printedMessages[1], "'yes' - expected 'on' or 'off'.",
    "an invalid autoopen value is rejected with a specific error")
end

do
  ns.db.debug = true
  dispatch("status")
  equals(printedMessages[1], "test settings:", "status prints a header via ns.Print")
end

do
  dispatch("version")
  equals(printedMessages[1], "test", "version prints the addon version")
end

do
  ns.db.debug = true
  dispatch("reset")
  equals(ns.db.debug, false, "reset restores debug to its default")
  equals(printedMessages[1], "Settings restored to defaults.", "reset confirms what it did")

  -- A reset that assigns a nested default table by reference would let a
  -- later mutation of ns.db.disenchant corrupt DEFAULT_SETTINGS.disenchant
  -- itself, silently breaking every future reset.
  ns.db.disenchant.excludedQualities[2] = true
  check(ns.DEFAULT_SETTINGS.disenchant.excludedQualities[2] == nil,
    "reset deep-copies nested default tables instead of sharing them")
end

--------------------------------------------------------------------------
-- Scanner.lua (#23)
--------------------------------------------------------------------------

stubs.loadModule(here .. "/../Scanner.lua", "GearSweep", ns)

-- Builds C_Container stubs from { [bagID] = { [slot] = { hyperlink=, isBound= } } };
-- any bag/slot not listed has 0 slots / an empty slot, matching a real bag.
local function mockContainers(bagContents)
  C_Container.GetContainerNumSlots = function(bagID)
    local slots = bagContents[bagID]
    if not slots then return 0 end
    local max = 0
    for slot in pairs(slots) do
      if slot > max then max = slot end
    end
    return max
  end
  C_Container.GetContainerItemInfo = function(bagID, slot)
    local slots = bagContents[bagID]
    return slots and slots[slot]
  end
end

-- Builds C_Item.GetItemInfo from { [hyperlink] = { name, quality, itemLevel,
-- equipLoc, classID, subclassID } }, matching GetItemInfo's real return
-- positions (1 name, 3 quality, 4 itemLevel, 9 equipLoc, 12 classID, 13 subclassID).
local function mockItemInfo(infoByLink, detailedLevelByLink)
  C_Item.GetItemInfo = function(link)
    local info = infoByLink[link]
    if not info then return nil end
    return info[1], link, info[2], info[3], 90, "?", "?", 1, info[4], "icon", 0, info[5], info[6]
  end
  C_Item.GetDetailedItemLevelInfo = function(link)
    return detailedLevelByLink and detailedLevelByLink[link]
  end
end

local function resetScannerMocks()
  C_Container.GetContainerNumSlots = function() return 0 end
  C_Container.GetContainerItemInfo = function() return nil end
  C_Item.GetItemInfo = function() return nil end
  C_Item.GetDetailedItemLevelInfo = function() return nil end
  C_Bank = nil
  Enum.BankType = nil
end

do
  -- No bank purchased/open (C_Bank absent entirely on some clients): only
  -- the 5 character bag IDs are scanned, backpack plus the 4 equipped bags.
  local locations = ns.Scanner:GetLocations()
  equals(#locations, 5, "with no bank, only the character's bags are locations")
  for i, bagID in ipairs({ 0, 1, 2, 3, 4 }) do
    equals(locations[i].bagID, bagID, "bag location " .. i .. " has the expected bag ID")
    equals(locations[i].source, "Bags", "bag locations are labeled 'Bags'")
  end
end

do
  -- Every purchased tab of every viewable bank type is a location, labeled
  -- with its bank type's real name via Enum.BankType.
  C_Bank = {
    FetchViewableBankTypes = function() return { 1, 2 } end,
    FetchPurchasedBankTabIDs = function(bankType)
      if bankType == 1 then return { 6 } end
      if bankType == 2 then return { 7, 8 } end
      return {}
    end,
  }
  Enum.BankType = { Character = 1, Account = 2 }

  local locations = ns.Scanner:GetLocations()
  equals(#locations, 8, "bag locations plus every purchased bank tab")
  equals(locations[6].bagID, 6, "the character bank tab's bag ID is included")
  equals(locations[6].source, "Character", "the character bank tab is labeled by its real bank type name")
  equals(locations[7].bagID, 7, "the first Warband Bank tab's bag ID is included")
  equals(locations[7].source, "Account", "Warband Bank tabs are labeled by their real bank type name")
  equals(locations[8].bagID, 8, "a second purchased tab of the same bank type is included")

  resetScannerMocks()
end

do
  -- A bank type with no matching Enum.BankType entry still gets a location,
  -- just without a friendly name.
  C_Bank = {
    FetchViewableBankTypes = function() return { 99 } end,
    FetchPurchasedBankTabIDs = function() return { 6 } end,
  }
  Enum.BankType = { Character = 1 }

  local locations = ns.Scanner:GetLocations()
  equals(locations[6].source, "Bank type 99",
    "an unrecognised bank type still gets a location, labeled generically")

  resetScannerMocks()
end

do
  -- ScanAll enumerates real gear, skips empty slots and non-gear items
  -- (a potion's equipLoc, and the cosmetic-only shirt/tabard slots), and
  -- prefers the detailed (upgraded) item level over GetItemInfo's own.
  mockContainers({
    [0] = {
      [1] = { hyperlink = "item:sword", isBound = true },
      [2] = { hyperlink = "item:potion", isBound = false },
      -- Empty slot 3: GetContainerItemInfo returns nil.
      [4] = { hyperlink = "item:shirt", isBound = false },
    },
  })
  mockItemInfo({
    ["item:sword"] = { "Sword", 4, 200, "INVTYPE_WEAPON", 2, 7 },
    ["item:potion"] = { "Potion", 1, 1, "INVTYPE_NON_EQUIP_IGNORE", 0, 0 },
    ["item:shirt"] = { "Shirt", 1, 1, "INVTYPE_BODY", 4, 0 },
  }, {
    ["item:sword"] = 210,
  })

  local items = ns.Scanner:ScanAll()
  equals(#items, 1, "only the real gear item is scanned - the potion and shirt are excluded")
  local sword = items[1]
  equals(sword.hyperlink, "item:sword", "the scanned item keeps the container slot's own hyperlink")
  equals(sword.name, "Sword", "the scanned item's name comes from GetItemInfo")
  equals(sword.quality, 4, "the scanned item's quality comes from GetItemInfo")
  equals(sword.itemLevel, 210, "the detailed item level wins over GetItemInfo's own item level")
  equals(sword.equipLoc, "INVTYPE_WEAPON", "the scanned item's equip location comes from GetItemInfo")
  equals(sword.classID, 2, "the scanned item's classID comes from GetItemInfo")
  equals(sword.subclassID, 7, "the scanned item's subclassID comes from GetItemInfo")
  equals(sword.isBound, true, "the scanned item's bound state comes from the container slot")
  equals(sword.bagID, 0, "the scanned item's bag ID is recorded")
  equals(sword.slot, 1, "the scanned item's slot is recorded")
  equals(sword.source, "Bags", "the scanned item's source label comes from its location")

  resetScannerMocks()
end

do
  -- No detailed item level available (GetDetailedItemLevelInfo returns
  -- nil): falls back to GetItemInfo's own item level.
  mockContainers({ [0] = { [1] = { hyperlink = "item:sword", isBound = false } } })
  mockItemInfo({ ["item:sword"] = { "Sword", 4, 200, "INVTYPE_WEAPON", 2, 7 } })

  local items = ns.Scanner:ScanAll()
  equals(items[1].itemLevel, 200, "with no detailed level available, GetItemInfo's item level is used")

  resetScannerMocks()
end

do
  -- WithdrawToBags refuses to act while the cursor is already holding
  -- something, rather than dropping or swapping it unexpectedly.
  CursorHasItem = function() return true end
  local ok, reason = ns.Scanner:WithdrawToBags(0, 1)
  check(not ok, "WithdrawToBags refuses to run while the cursor holds an item")
  equals(reason, "cursor is already holding something", "WithdrawToBags explains why it refused")
  CursorHasItem = function() return false end
end

do
  -- Every bag slot is full: there's nowhere to place the withdrawn item.
  mockContainers({
    [0] = { [1] = { hyperlink = "item:a" } },
    [1] = { [1] = { hyperlink = "item:b" } },
    [2] = { [1] = { hyperlink = "item:c" } },
    [3] = { [1] = { hyperlink = "item:d" } },
    [4] = { [1] = { hyperlink = "item:e" } },
    [6] = { [1] = { hyperlink = "item:bank" } },
  })
  local ok, reason = ns.Scanner:WithdrawToBags(6, 1)
  check(not ok, "WithdrawToBags refuses to run when every bag slot is full")
  equals(reason, "bags full", "WithdrawToBags explains why it refused")

  resetScannerMocks()
end

do
  -- The source slot no longer holds anything by the time this runs - the
  -- bank was closed, the player disconnected mid-pull, or the item was
  -- already moved some other way (#25). WithdrawToBags must say so rather
  -- than silently touching the cursor for nothing.
  mockContainers({ [0] = { [1] = { hyperlink = "item:a" } } })
  local ok, reason = ns.Scanner:WithdrawToBags(6, 1)
  check(not ok, "WithdrawToBags refuses to run when the source slot is empty")
  equals(reason, "item is no longer there", "WithdrawToBags explains why it refused")

  local pickups = 0
  C_Container.PickupContainerItem = function() pickups = pickups + 1 end
  ns.Scanner:WithdrawToBags(6, 1)
  equals(pickups, 0, "WithdrawToBags never touches the cursor when the source slot is already empty")
  C_Container.PickupContainerItem = function() end

  resetScannerMocks()
end

do
  -- Success: picks up the source slot, then places it in the first empty
  -- bag slot found (bag 0 has an empty slot 2; slot 1 is occupied).
  mockContainers({ [0] = { [1] = { hyperlink = "item:a" } }, [6] = { [3] = { hyperlink = "item:bank" } } })
  C_Container.GetContainerNumSlots = function(bagID) return bagID == 0 and 2 or 0 end

  local pickups = {}
  C_Container.PickupContainerItem = function(bagID, slot)
    table.insert(pickups, { bagID = bagID, slot = slot })
  end

  local ok = ns.Scanner:WithdrawToBags(6, 3)
  check(ok, "WithdrawToBags succeeds when an empty bag slot exists")
  equals(#pickups, 2, "WithdrawToBags picks up the source item, then the empty destination slot")
  equals(pickups[1].bagID, 6, "the first pickup is the source bag")
  equals(pickups[1].slot, 3, "the first pickup is the source slot")
  equals(pickups[2].bagID, 0, "the second pickup is the empty destination bag")
  equals(pickups[2].slot, 2, "the second pickup is the empty destination slot")

  resetScannerMocks()
  C_Container.PickupContainerItem = function() end
end

--------------------------------------------------------------------------
-- Classify.lua: season/tier classification and disenchant eligibility (#23)
--------------------------------------------------------------------------

stubs.loadModule(here .. "/../Classify.lua", "GearSweep", ns)
stubs.loadModule(here .. "/../Upgrade.lua", "GearSweep", ns)

-- Simulates C_TooltipInfo.GetHyperlink's structured line data: an upgrade-
-- track line (type 32) when the item still has one (current season), tagged
-- with the track name Classify.lua matches against ("Adventurer" or not).
local function mockUpgradeTrack(trackName)
  C_TooltipInfo.GetHyperlink = function()
    return { lines = { { type = 32, leftText = "Upgrade Level: " .. trackName, currentLevel = 1, maxLevel = 8 } } }
  end
end

local function mockNoUpgradeTrack()
  C_TooltipInfo.GetHyperlink = function()
    return { lines = {} }
  end
end

local function mockUsable(usable)
  C_TooltipInfo.GetHyperlink = function()
    return { lines = { { type = 43, usable = usable, leftText = "Requires Level 80" } } }
  end
end

local function resetTooltipMock()
  C_TooltipInfo.GetHyperlink = function() return nil end
end

do
  mockUpgradeTrack("Adventurer")
  check(ns.Classify:IsCurrentSeason("item:1"), "an item with an upgrade track is current-season")
  check(ns.Classify:IsAdventurerTier("item:1"), "an Adventurer-track item is Adventurer tier")
  resetTooltipMock()
end

do
  mockUpgradeTrack("Champion")
  check(ns.Classify:IsCurrentSeason("item:1"), "a Champion-track item is still current-season")
  check(not ns.Classify:IsAdventurerTier("item:1"), "a Champion-track item is not Adventurer tier")
  resetTooltipMock()
end

do
  mockNoUpgradeTrack()
  check(not ns.Classify:IsCurrentSeason("item:1"),
    "an item with no upgrade track at all is not current-season")
  check(not ns.Classify:IsAdventurerTier("item:1"),
    "an item with no upgrade track is not Adventurer tier")
  resetTooltipMock()
end

do
  -- GetHyperlink returning nil outright (no data at all, distinct from an
  -- empty lines table) hits the same "no track info" branch.
  check(not ns.Classify:IsCurrentSeason("item:1"),
    "with no tooltip data available at all, an item is not treated as current-season")
end

do
  mockUsable(false)
  check(not ns.Classify:IsUsable("item:1"), "a requirement line with usable=false is not usable")
  resetTooltipMock()
end

do
  mockUsable(true)
  check(ns.Classify:IsUsable("item:1"), "a requirement line with usable=true is usable")
  resetTooltipMock()
end

do
  mockNoUpgradeTrack()
  check(ns.Classify:IsUsable("item:1"), "an item with no requirement line at all is usable")
  resetTooltipMock()
end

do
  check(ns.Classify:IsDisenchantEligibleQuality(2), "Uncommon is disenchant-eligible")
  check(ns.Classify:IsDisenchantEligibleQuality(3), "Rare is disenchant-eligible")
  check(ns.Classify:IsDisenchantEligibleQuality(4), "Epic is disenchant-eligible")
  check(not ns.Classify:IsDisenchantEligibleQuality(0), "Poor is not disenchant-eligible")
  check(not ns.Classify:IsDisenchantEligibleQuality(1), "Common is not disenchant-eligible")
end

local function disenchantItem(quality)
  return { quality = quality, hyperlink = "item:1" }
end

do
  mockUpgradeTrack("Adventurer")
  check(ns.Classify:IsDisenchantCandidate(disenchantItem(3)),
    "a Rare Adventurer-tier item is a disenchant candidate")
  resetTooltipMock()
end

do
  mockNoUpgradeTrack()
  check(ns.Classify:IsDisenchantCandidate(disenchantItem(4)),
    "an Epic previous-season item (no upgrade track) is a disenchant candidate")
  resetTooltipMock()
end

do
  mockUpgradeTrack("Champion")
  check(not ns.Classify:IsDisenchantCandidate(disenchantItem(4)),
    "a current-season Epic item above Adventurer tier is not a disenchant candidate")
  resetTooltipMock()
end

do
  mockNoUpgradeTrack()
  check(not ns.Classify:IsDisenchantCandidate(disenchantItem(1)),
    "a Common-quality item is never a disenchant candidate, even from a previous season")
  resetTooltipMock()
end

--------------------------------------------------------------------------
-- Classify.lua: "Best in Slot" spec-relevance (#23)
--------------------------------------------------------------------------

-- Populates the background scan tooltip's lines (see wow_stubs.lua's
-- CreateFrame) as Classify:GetBestInSlotSpecs reads them: consecutive
-- _G[tooltipName .. "TextLeft" .. i] font strings.
local TOOLTIP_NAME = "GearSweepClassifyTooltip"

local function mockTooltipLines(lines)
  for i, text in ipairs(lines) do
    _G[TOOLTIP_NAME .. "TextLeft" .. i] = { GetText = function() return text end }
  end
  _G[TOOLTIP_NAME .. "TextLeft" .. (#lines + 1)] = nil
end

do
  mockTooltipLines({ "Epic", "Item Level 480" })
  local specs = ns.Classify:GetBestInSlotSpecs("item:1")
  equals(#specs, 0, "an item with no 'Best in Slot' annotation has no listed specs")
end

do
  mockTooltipLines({
    "Epic", "Item Level 480", "Best in Slot", "Holy Paladin", "Protection Paladin", "", "Requires Level 80",
  })
  local specs = ns.Classify:GetBestInSlotSpecs("item:1")
  equals(#specs, 2, "specs are read until the blank line that ends the 'Best in Slot' section")
  equals(specs[1], "Holy Paladin", "the first listed spec is read")
  equals(specs[2], "Protection Paladin", "the second listed spec is read")
end

do
  -- No annotation at all: not a signal either way, so it's never grounds to
  -- exclude an otherwise-usable item.
  mockTooltipLines({ "Epic", "Item Level 480" })
  check(ns.Classify:IsSpecAppropriate("item:1"),
    "an item with no 'Best in Slot' annotation is spec-appropriate by default")
end

do
  mockTooltipLines({ "Best in Slot", "Holy Paladin", "" })
  UnitClass = function() return "Paladin" end
  GetSpecialization = function() return 1 end
  GetSpecializationInfo = function() return nil, "Holy" end
  check(ns.Classify:IsSpecAppropriate("item:1"),
    "an item annotated for the player's actual class and spec is spec-appropriate")

  GetSpecializationInfo = function() return nil, "Protection" end
  check(not ns.Classify:IsSpecAppropriate("item:1"),
    "an item annotated only for a different spec of the same class is not spec-appropriate")

  UnitClass = function() return "Warrior" end
  GetSpecializationInfo = function() return nil, "Holy" end
  check(not ns.Classify:IsSpecAppropriate("item:1"),
    "an item annotated for the same spec name but a different class is not spec-appropriate")

  UnitClass = function() return nil end
  GetSpecialization = function() return nil end
  GetSpecializationInfo = function() return nil end
end

--------------------------------------------------------------------------
-- Upgrade best-per-slot selection (v0.4.0, #16)
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Class armor/weapon proficiency (v0.4.0, #35)
--------------------------------------------------------------------------

local function classifiedItem(classID, subclassID, equipLoc)
  return { classID = classID, subclassID = subclassID, equipLoc = equipLoc }
end

do
  UnitClassBase = function() return "MAGE" end
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 6, "INVTYPE_SHIELD")),
    "a Mage cannot equip a shield")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 4, "INVTYPE_CHEST")),
    "a Mage cannot equip plate armor")
  check(ns.Classify:IsClassProficient(classifiedItem(4, 1, "INVTYPE_CHEST")),
    "a Mage can equip cloth armor")
  check(ns.Classify:IsClassProficient(classifiedItem(2, 19, "INVTYPE_WEAPON")),
    "a Mage can equip a wand")
  check(not ns.Classify:IsClassProficient(classifiedItem(2, 1, "INVTYPE_2HWEAPON")),
    "a Mage cannot equip a two-hand axe")
  check(not ns.Classify:IsClassProficient(classifiedItem(2, 19, "INVTYPE_WEAPONOFFHAND")),
    "a Mage cannot dual-wield, so an off-hand weapon is unusable regardless of its own subclass")
end

do
  UnitClassBase = function() return "WARRIOR" end
  check(ns.Classify:IsClassProficient(classifiedItem(4, 4, "INVTYPE_CHEST")),
    "a Warrior can equip plate armor")
  check(ns.Classify:IsClassProficient(classifiedItem(4, 6, "INVTYPE_SHIELD")),
    "a Warrior can equip a shield")
  check(not ns.Classify:IsClassProficient(classifiedItem(2, 19, "INVTYPE_WEAPON")),
    "a Warrior cannot equip a wand")
  -- #40: a Plate class must be restricted to Plate armor specifically, not
  -- merely "Plate or anything lighter" - a real upgrade recommendation
  -- needs an actual stat gain.
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 1, "INVTYPE_CHEST")),
    "a Warrior cannot equip cloth armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 2, "INVTYPE_CHEST")),
    "a Warrior cannot equip leather armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 3, "INVTYPE_CHEST")),
    "a Warrior cannot equip mail armor")
end

do
  -- #40: confirmed live - a Death Knight (also a Plate class) was
  -- recommended non-plate armor, because the previous table only ever
  -- excluded armor types heavier than a class's own, and Plate has
  -- nothing heavier to exclude.
  UnitClassBase = function() return "DEATHKNIGHT" end
  check(ns.Classify:IsClassProficient(classifiedItem(4, 4, "INVTYPE_CHEST")),
    "a Death Knight can equip plate armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 1, "INVTYPE_CHEST")),
    "a Death Knight cannot equip cloth armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 2, "INVTYPE_CHEST")),
    "a Death Knight cannot equip leather armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 3, "INVTYPE_CHEST")),
    "a Death Knight cannot equip mail armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 6, "INVTYPE_SHIELD")),
    "a Death Knight cannot equip a shield, unlike the other Plate classes")
end

do
  -- Same latent gap as #40, for the Mail and Leather tiers.
  UnitClassBase = function() return "HUNTER" end
  check(ns.Classify:IsClassProficient(classifiedItem(4, 3, "INVTYPE_CHEST")), "a Hunter can equip mail armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 1, "INVTYPE_CHEST")), "a Hunter cannot equip cloth armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 2, "INVTYPE_CHEST")),
    "a Hunter cannot equip leather armor")

  UnitClassBase = function() return "DRUID" end
  check(ns.Classify:IsClassProficient(classifiedItem(4, 2, "INVTYPE_CHEST")), "a Druid can equip leather armor")
  check(not ns.Classify:IsClassProficient(classifiedItem(4, 1, "INVTYPE_CHEST")), "a Druid cannot equip cloth armor")
end

do
  UnitClassBase = function() return nil end
  check(ns.Classify:IsClassProficient(classifiedItem(4, 6, "INVTYPE_SHIELD")),
    "an unrecognised class defaults to usable rather than hiding everything")
end

local function item(equipLoc, itemLevel)
  return { equipLoc = equipLoc, itemLevel = itemLevel }
end

do
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_HEAD", 480),
    item("INVTYPE_HEAD", 450),
  })
  equals(#best, 1, "a single-slot upgrade picks only one item")
  equals(best[1].itemLevel, 480, "a single-slot upgrade picks the higher item level")
end

do
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_FINGER", 470),
    item("INVTYPE_FINGER", 480),
    item("INVTYPE_FINGER", 400),
  })
  equals(#best, 2, "rings (dual-slot) pick the top two distinct items")
  local levels = { best[1].itemLevel, best[2].itemLevel }
  table.sort(levels, function(a, b) return a > b end)
  equals(levels[1], 480, "rings: the highest item level is selected")
  equals(levels[2], 470, "rings: the second-highest item level is selected")
end

do
  -- No off-hand candidate exists, so the two-hand item is simply the
  -- highest-level thing that can go in a weapon slot.
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_2HWEAPON", 500),
    item("INVTYPE_WEAPONMAINHAND", 350),
  })
  equals(#best, 1, "two-hand beats a much weaker lone main-hand item")
  equals(best[1].equipLoc, "INVTYPE_2HWEAPON", "the two-hand item is selected")
end

do
  -- #37: scored by average across both weapon slots, not summed - a
  -- one-hand+offhand pair only wins when its average is actually higher,
  -- not just because a real off-hand candidate happens to exist.
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_2HWEAPON", 500),
    item("INVTYPE_WEAPONMAINHAND", 400),
    item("INVTYPE_SHIELD", 400),
  })
  equals(#best, 1, "a two-hand item beats a weaker one-hand+offhand pair by average (500 vs 400)")
  equals(best[1].equipLoc, "INVTYPE_2HWEAPON", "the two-hand item is selected")
end

do
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_2HWEAPON", 400),
    item("INVTYPE_WEAPONMAINHAND", 480),
    item("INVTYPE_SHIELD", 480),
  })
  equals(#best, 2, "a genuinely stronger one-hand+offhand pair beats a weaker two-hand item (480 vs 400)")
  check(best[1].equipLoc ~= "INVTYPE_2HWEAPON" and best[2].equipLoc ~= "INVTYPE_2HWEAPON",
    "the two-hand item is not selected alongside the pair")
end

do
  local best = ns.Upgrade:SelectBest({ item("INVTYPE_WEAPONMAINHAND", 460) })
  equals(#best, 1, "a lone main-hand candidate is selected on its own")
  equals(best[1].equipLoc, "INVTYPE_WEAPONMAINHAND", "the main-hand item is selected")
end

--------------------------------------------------------------------------
-- Two-hand vs. one-hand+offhand vs. currently equipped (v0.5.0, #37)
--------------------------------------------------------------------------

local function mockEquippedWeapons(mainLink, mainEquipLoc, mainLevel, offLevel)
  GetInventoryItemLink = function(_, slotID)
    if slotID == GetInventorySlotInfo("MainHandSlot") then return mainLink end
    if offLevel and slotID == GetInventorySlotInfo("SecondaryHandSlot") then return "item:equipped-off" end
    return nil
  end
  C_Item.GetItemInfo = function(link)
    if link == mainLink then
      return "Equipped", link, 4, mainLevel, 90, "Weapon", "?", 1, mainEquipLoc
    end
    return nil
  end
  C_Item.GetDetailedItemLevelInfo = function(link)
    if link == mainLink then return mainLevel end
    if link == "item:equipped-off" then return offLevel end
    return nil
  end
end

local function resetMockedEquipment()
  GetInventoryItemLink = function() return nil end
  C_Item.GetItemInfo = function() return nil end
  C_Item.GetDetailedItemLevelInfo = function() return nil end
end

do
  -- Currently wielding a two-hander (ilvl 500): a much weaker
  -- one-hand+offhand pair (average 300) should not be suggested.
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 500)

  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_WEAPONMAINHAND", 300),
    item("INVTYPE_SHIELD", 300),
  })
  equals(#best, 0, "a weaker one-hand+offhand pair is not suggested over an equipped two-hander")

  resetMockedEquipment()
end

do
  -- Currently wielding a weak two-hander (ilvl 300): a genuinely stronger
  -- one-hand+offhand pair (average 450) should be suggested.
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 300)

  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_WEAPONMAINHAND", 450),
    item("INVTYPE_SHIELD", 450),
  })
  equals(#best, 2, "a genuinely stronger one-hand+offhand pair is suggested over a weak equipped two-hander")

  resetMockedEquipment()
end

do
  -- A strong off-hand candidate alone, with no one-hand candidate to pair
  -- it with, still can't be equipped while a two-hander stays equipped.
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 300)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_SHIELD", 500) })
  equals(#best, 0, "an off-hand item alone is never suggested while a two-hander is equipped")

  resetMockedEquipment()
end

do
  -- Confirmed live via GetAverageItemLevel: a two-hand weapon counts
  -- TWICE toward overall average item level (once per weapon slot).
  -- Swapping a 253 two-hander for a bare 253 one-hand weapon (no
  -- off-hand) dropped real overall average item level by 17 - a
  -- genuinely worse outcome, not a wash - so a lone main-hand candidate
  -- with no off-hand really is only worth half its own level here. A 292
  -- wand does NOT beat a 256 two-hander this way (146 < 256).
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 256)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_RANGEDRIGHT", 292) })
  equals(#best, 0, "a lone main-hand candidate with no off-hand is halved, so it doesn't beat a two-hander")

  resetMockedEquipment()
end

do
  -- A lone main-hand candidate CAN still win if it's strong enough to
  -- clear the halved bar (more than double the equipped two-hander).
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 200)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_RANGEDRIGHT", 450) })
  equals(#best, 1, "a lone main-hand candidate wins when it clears the halved bar (225 > 200)")
  equals(best[1].equipLoc, "INVTYPE_RANGEDRIGHT", "the main-hand candidate is selected")

  resetMockedEquipment()
end

do
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 300)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_RANGEDRIGHT", 250) })
  equals(#best, 0, "a lone main-hand candidate weaker than the equipped two-hander is not suggested")

  resetMockedEquipment()
end

do
  -- Vice versa: currently dual-wielding (average 300). A weaker two-hand
  -- candidate (280) should not be suggested.
  mockEquippedWeapons("item:mainhand", "INVTYPE_WEAPONMAINHAND", 300, 300)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_2HWEAPON", 280) })
  equals(#best, 0, "a weaker two-hand item is not suggested over an equipped one-hand+offhand pair")

  resetMockedEquipment()
end

do
  -- Vice versa: currently dual-wielding (average 300). A genuinely
  -- stronger two-hand candidate (350) should be suggested.
  mockEquippedWeapons("item:mainhand", "INVTYPE_WEAPONMAINHAND", 300, 300)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_2HWEAPON", 350) })
  equals(#best, 1, "a genuinely stronger two-hand item is suggested over an equipped one-hand+offhand pair")
  equals(best[1].equipLoc, "INVTYPE_2HWEAPON", "the two-hand item is selected")

  resetMockedEquipment()
end

--------------------------------------------------------------------------
-- Upgrade vs. currently-equipped gear (v0.4.0, #16 correctness fix)
--------------------------------------------------------------------------

ns.Classify.IsUsable = function() return true end
ns.Classify.IsSpecAppropriate = function() return true end

do
  -- Empty slot (GetInventoryItemLink returns nil by default), and no
  -- meaningful average equipped level to fall back on either: anything
  -- real counts as an upgrade.
  local candidate = item("INVTYPE_HEAD", 100)
  candidate.hyperlink = "item:1"
  candidate.quality = 4
  check(ns.Upgrade:IsCandidate(candidate), "any real item is an upgrade over an empty slot")
end

do
  -- #36: an empty slot on a character who otherwise wears real gear
  -- (e.g. a caster who never equips an off-hand item) falls back to the
  -- character's average equipped item level, not literal 0 - so a
  -- trivially low-level item doesn't "win" against nothing.
  GetAverageItemLevel = function() return 250, 250, 250 end

  local junk = item("INVTYPE_HOLDABLE", 15)
  junk.hyperlink = "item:junk"
  junk.quality = 2
  check(not ns.Upgrade:IsCandidate(junk),
    "a trivially low-level item on a permanently-empty slot is not an upgrade")

  local real = item("INVTYPE_HOLDABLE", 280)
  real.hyperlink = "item:real"
  real.quality = 4
  check(ns.Upgrade:IsCandidate(real),
    "a genuinely strong item on a permanently-empty slot is still an upgrade")

  GetAverageItemLevel = function() return 0, 0, 0 end
end

do
  -- #37: off-hand-slot items are no longer excluded from IsCandidate just
  -- because a two-hander is equipped - whether switching is actually
  -- worth it is SelectBest's job (see the average-comparison tests
  -- above), not a blanket exclusion here.
  GetInventoryItemLink = function(_, slotID)
    if slotID == GetInventorySlotInfo("MainHandSlot") then return "item:staff" end
    return nil
  end
  C_Item.GetItemInfo = function(link)
    if link == "item:staff" then
      return "Staff", link, 4, 292, 90, "Weapon", "Staves", 1, "INVTYPE_2HWEAPON"
    end
    return nil
  end
  C_Item.GetDetailedItemLevelInfo = function(link)
    if link == "item:staff" then return 292 end
    return nil
  end
  GetAverageItemLevel = function() return 290, 290, 290 end

  local shield = item("INVTYPE_SHIELD", 300)
  shield.hyperlink = "item:shield"
  shield.quality = 4
  check(ns.Upgrade:IsCandidate(shield),
    "a strong shield can still be a candidate while a two-hand weapon is equipped")

  -- A one-hand main-hand candidate is still fine - it would simply
  -- replace the two-hander, not stack alongside it.
  local mainHandCandidate = item("INVTYPE_WEAPONMAINHAND", 300)
  mainHandCandidate.hyperlink = "item:1h"
  mainHandCandidate.quality = 4
  check(ns.Upgrade:IsCandidate(mainHandCandidate),
    "a one-hand main-hand item is still a valid candidate over an equipped two-hander")

  GetAverageItemLevel = function() return 0, 0, 0 end

  GetInventoryItemLink = function() return nil end
  C_Item.GetItemInfo = function() return nil end
end

do
  GetInventoryItemLink = function() return "item:equipped" end
  C_Item.GetDetailedItemLevelInfo = function() return 200 end

  local higher = item("INVTYPE_HEAD", 250)
  higher.hyperlink = "item:1"
  higher.quality = 4
  check(ns.Upgrade:IsCandidate(higher), "an item above the equipped level is an upgrade")

  local lower = item("INVTYPE_HEAD", 150)
  lower.hyperlink = "item:2"
  lower.quality = 4
  check(not ns.Upgrade:IsCandidate(lower),
    "an item below the equipped level is not an upgrade, even if otherwise usable")

  GetInventoryItemLink = function() return nil end
  C_Item.GetDetailedItemLevelInfo = function() return nil end
end

do
  -- Dual-slot: baseline is the WORSE of the two equipped rings, so an item
  -- that would only beat one of them still counts as an upgrade.
  GetInventoryItemLink = function(_, slotID)
    if slotID == GetInventorySlotInfo("Finger0Slot") then return "item:strong-ring" end
    if slotID == GetInventorySlotInfo("Finger1Slot") then return "item:weak-ring" end
    return nil
  end
  C_Item.GetDetailedItemLevelInfo = function(link)
    if link == "item:strong-ring" then return 300 end
    if link == "item:weak-ring" then return 100 end
    return nil
  end

  local candidate = item("INVTYPE_FINGER", 200)
  candidate.hyperlink = "item:new-ring"
  candidate.quality = 3
  check(ns.Upgrade:IsCandidate(candidate),
    "a ring beating only the weaker of two equipped rings still counts as an upgrade")

  GetInventoryItemLink = function() return nil end
  C_Item.GetDetailedItemLevelInfo = function() return nil end
end

do
  -- #28: debug subcommands dispatch to Upgrade.lua's dump helpers rather
  -- than being silently swallowed like an unrecognised debug argument.
  local slotsCalled, upgradesCalled, weaponsCalled = false, false, false
  ns.Upgrade.DumpEquippedSlots = function() slotsCalled = true end
  ns.Upgrade.DumpSelectedUpgrades = function() upgradesCalled = true end
  ns.Upgrade.DumpWeaponComparison = function() weaponsCalled = true end

  dispatch("debug slots")
  check(slotsCalled, "debug slots dispatches to Upgrade:DumpEquippedSlots")

  dispatch("debug upgrades")
  check(upgradesCalled, "debug upgrades dispatches to Upgrade:DumpSelectedUpgrades")

  dispatch("debug weapons")
  check(weaponsCalled, "debug weapons dispatches to Upgrade:DumpWeaponComparison")
end

do
  -- #35: debug item <name> finds a matching item by case-insensitive
  -- substring and dumps its tooltip data.
  ns.Scanner = {
    ScanAll = function()
      return {
        { name = "Bramblebarricade", hyperlink = "item:1", quality = 4,
          equipLoc = "INVTYPE_SHIELD", source = "Account" },
      }
    end,
  }
  local dumpedLink
  ns.Classify.DumpTooltip = function(_, link) dumpedLink = link end
  ns.Upgrade.FindEquippedLink = function() return nil end

  dispatch("debug item bramble")
  equals(dumpedLink, "item:1", "debug item finds a case-insensitive substring match and dumps its tooltip")

  dumpedLink = nil
  dispatch("debug item nonexistent")
  check(dumpedLink == nil, "debug item reports nothing found rather than dumping a wrong item")
  equals(printedMessages[1], "No item matching 'nonexistent' found in bags/bank or equipped.",
    "debug item explains when no match is found")

  ns.Upgrade.FindEquippedLink = function() return "item:equipped-1", "HeadSlot" end
  dispatch("debug item nonexistent")
  equals(dumpedLink, "item:equipped-1", "debug item falls back to searching equipped slots")
end

--------------------------------------------------------------------------
-- UI.lua: quality/slot/item-level filtering (#23)
--------------------------------------------------------------------------

stubs.loadModule(here .. "/../UI.lua", "GearSweep", ns)

do
  local filters = { excludedQualities = { [2] = true }, excludedSlotGroups = {}, minLevel = 1, maxLevel = 999 }
  local uncommon = { quality = 2, equipLoc = "INVTYPE_HEAD", itemLevel = 100 }
  check(not ns.UI.PassesCommonFilters(uncommon, filters), "an excluded quality fails the common filter")
end

do
  local filters = { excludedQualities = {}, excludedSlotGroups = { WEAPON = true }, minLevel = 1, maxLevel = 999 }
  local sword = { quality = 4, equipLoc = "INVTYPE_WEAPON", itemLevel = 100 }
  check(not ns.UI.PassesCommonFilters(sword, filters), "an excluded slot group fails the common filter")

  local offhandSword = { quality = 4, equipLoc = "INVTYPE_WEAPONOFFHAND", itemLevel = 100 }
  check(ns.UI.PassesCommonFilters(offhandSword, filters),
    "an off-hand weapon is grouped separately from the Weapon slot group, so it's unaffected")
end

do
  local filters = { excludedQualities = {}, excludedSlotGroups = {}, minLevel = 200, maxLevel = 300 }
  check(not ns.UI.PassesCommonFilters({ quality = 4, equipLoc = "INVTYPE_HEAD", itemLevel = 199 }, filters),
    "an item below minLevel fails the common filter")
  check(not ns.UI.PassesCommonFilters({ quality = 4, equipLoc = "INVTYPE_HEAD", itemLevel = 301 }, filters),
    "an item above maxLevel fails the common filter")
  check(ns.UI.PassesCommonFilters({ quality = 4, equipLoc = "INVTYPE_HEAD", itemLevel = 250 }, filters),
    "an item within the level range passes the common filter")
  check(ns.UI.PassesCommonFilters({ quality = 4, equipLoc = "INVTYPE_HEAD" }, filters),
    "an item with no item level at all bypasses the level range check")
end

do
  mockUpgradeTrack("Adventurer")
  local filters = { excludedQualities = {}, excludedSlotGroups = {}, minLevel = 1, maxLevel = 999,
    includeAdventurerTier = true, includePreviousSeason = true }
  local candidate = { quality = 3, equipLoc = "INVTYPE_HEAD", itemLevel = 100, hyperlink = "item:1" }
  check(ns.UI.PassesDisenchantFilters(candidate, filters),
    "an Adventurer-tier item passes disenchant filters when Adventurer inclusion is on")

  filters.includeAdventurerTier = false
  check(not ns.UI.PassesDisenchantFilters(candidate, filters),
    "an Adventurer-tier item is excluded from disenchant filters when Adventurer inclusion is off")
  resetTooltipMock()
end

do
  mockNoUpgradeTrack()
  local filters = { excludedQualities = {}, excludedSlotGroups = {}, minLevel = 1, maxLevel = 999,
    includeAdventurerTier = true, includePreviousSeason = true }
  local candidate = { quality = 4, equipLoc = "INVTYPE_CHEST", itemLevel = 100, hyperlink = "item:2" }
  check(ns.UI.PassesDisenchantFilters(candidate, filters),
    "a previous-season item passes disenchant filters when previous-season inclusion is on")

  filters.includePreviousSeason = false
  check(not ns.UI.PassesDisenchantFilters(candidate, filters),
    "a previous-season item is excluded from disenchant filters when previous-season inclusion is off")
  resetTooltipMock()
end

do
  mockUpgradeTrack("Champion")
  local filters = { excludedQualities = {}, excludedSlotGroups = {}, minLevel = 1, maxLevel = 999,
    includeAdventurerTier = true, includePreviousSeason = true }
  local candidate = { quality = 4, equipLoc = "INVTYPE_CHEST", itemLevel = 100, hyperlink = "item:3" }
  check(not ns.UI.PassesDisenchantFilters(candidate, filters),
    "a current-season item above Adventurer tier never passes disenchant filters")
  resetTooltipMock()
end

do
  -- ns.Classify.IsUsable/IsSpecAppropriate are stubbed true for the rest of
  -- this file (see the "Upgrade vs. currently-equipped gear" section above),
  -- isolating this to class proficiency, item level, and slot filtering.
  UnitClassBase = function() return "MAGE" end
  GetInventoryItemLink = function() return nil end
  GetAverageItemLevel = function() return 0, 0, 0 end

  local filters = { excludedQualities = {}, excludedSlotGroups = {}, minLevel = 1, maxLevel = 999 }

  local shield = { quality = 4, equipLoc = "INVTYPE_SHIELD", itemLevel = 100,
    classID = 4, subclassID = 6, hyperlink = "item:shield" }
  check(not ns.UI.PassesUpgradeFilters(shield, filters),
    "a class-inappropriate item (a shield for a Mage) never passes upgrade filters")

  local cloth = { quality = 4, equipLoc = "INVTYPE_CHEST", itemLevel = 100,
    classID = 4, subclassID = 1, hyperlink = "item:cloth" }
  check(ns.UI.PassesUpgradeFilters(cloth, filters),
    "a usable item genuinely higher than the (empty) equipped slot passes upgrade filters")

  filters.excludedSlotGroups = { CHEST = true }
  check(not ns.UI.PassesUpgradeFilters(cloth, filters),
    "an otherwise-valid upgrade is still excluded by an excluded slot group")

  UnitClassBase = function() return nil end
end

--------------------------------------------------------------------------
-- Bind state does not affect classification (#25, confirmed live by #35)
--------------------------------------------------------------------------

do
  -- Item bind state has no bearing on class/armor/weapon proficiency,
  -- usability, or disenchant eligibility (#35's finding, live-confirmed
  -- against C_Item.IsUsableItem's misleading result for unbound Warband
  -- Bank items). Scanner records isBound purely for display; classification
  -- must treat a freshly-unbound Warband Bank item exactly like an
  -- already-bound one.
  mockNoUpgradeTrack()
  local bound = { quality = 4, hyperlink = "item:bound", classID = 4, subclassID = 1, isBound = true }
  local unbound = { quality = 4, hyperlink = "item:unbound", classID = 4, subclassID = 1, isBound = false }

  equals(ns.Classify:IsDisenchantCandidate(bound), ns.Classify:IsDisenchantCandidate(unbound),
    "disenchant eligibility does not depend on whether the item is bound")
  equals(ns.Classify:IsUsable(bound.hyperlink), ns.Classify:IsUsable(unbound.hyperlink),
    "usability does not depend on whether the item is bound")

  UnitClassBase = function() return "WARRIOR" end
  equals(ns.Classify:IsClassProficient(bound), ns.Classify:IsClassProficient(unbound),
    "class/armor proficiency does not depend on whether the item is bound")
  UnitClassBase = function() return nil end

  resetTooltipMock()
end

--------------------------------------------------------------------------
-- UI.lua: Pull Selected edge cases (#25)
--------------------------------------------------------------------------

local function fakeRow(rowItem, checked)
  return {
    item = rowItem,
    checkbox = {
      checked = checked,
      GetChecked = function(self) return self.checked end,
      SetChecked = function(self, v) self.checked = v end,
    },
  }
end

-- PullSelected calls UI:Refresh() at the end, which needs the full panel
-- (BuildFilters reads minLevelBox/maxLevelBox) that CreatePanel never runs
-- in these tests - stubbed out since these tests are only about the pull
-- loop's own counting/reporting, not the refreshed results list.
ns.UI.Refresh = function() end

do
  -- Bag space can't free up mid-pull (#25): once one item fails with "bags
  -- full", every other checked item is counted as not-pulled directly,
  -- rather than repeating the identical failing bag scan for each in turn.
  local calls = 0
  ns.Scanner = {
    WithdrawToBags = function(_, bagID)
      calls = calls + 1
      if bagID == 1 then return true end
      return false, "bags full"
    end,
  }

  ns.UI:SetRowsForTesting({
    fakeRow({ bagID = 1, slot = 1, name = "Sword" }, true),
    fakeRow({ bagID = 2, slot = 1, name = "Shield" }, true),
    fakeRow({ bagID = 3, slot = 1, name = "Helm" }, true),
    fakeRow({ bagID = 4, slot = 1, name = "Boots" }, false), -- unchecked: never attempted
  })

  local before = #printedMessages
  ns.UI.PullSelected()
  stubs.drainTimers()
  equals(calls, 2, "PullSelected stops calling WithdrawToBags after the first 'bags full' failure")
  equals(printedMessages[before + 1], "Pulled 1 item(s). Stopped: bags are full (2 remaining).",
    "PullSelected counts every remaining checked item as not-pulled, not just the one that failed")
end

do
  -- A failure that isn't "cursor busy" (e.g. the bank closed mid-pull, #25)
  -- must be reported as what it actually is, not a generic, misleading
  -- "cursor was busy" message.
  ns.Scanner = {
    WithdrawToBags = function() return false, "item is no longer there" end,
  }
  ns.UI:SetRowsForTesting({ fakeRow({ bagID = 6, slot = 1, name = "Ring" }, true) })

  local before = #printedMessages
  ns.UI.PullSelected()
  stubs.drainTimers()
  equals(printedMessages[before + 1], "Pulled 0 item(s), skipped 1 (item is no longer there).",
    "PullSelected reports the actual skip reason instead of an assumed cursor-busy message")
end

do
  -- #41: confirmed live - pulling 2 items reported "Pulled 2 item(s)" but
  -- only 1 actually arrived, because both withdrawals were issued back to
  -- back in the same instant. Each withdrawal must now wait a tick (via
  -- C_Timer.After) before the next one is issued, rather than firing them
  -- all in one synchronous pass.
  local callOrder = {}
  ns.Scanner = {
    WithdrawToBags = function(_, bagID)
      table.insert(callOrder, bagID)
      return true
    end,
  }
  ns.UI:SetRowsForTesting({
    fakeRow({ bagID = 1, slot = 1, name = "Sword" }, true),
    fakeRow({ bagID = 2, slot = 1, name = "Shield" }, true),
  })

  local before = #printedMessages
  ns.UI.PullSelected()
  equals(#callOrder, 1, "PullSelected does not issue the second withdrawal in the same instant as the first")

  stubs.drainTimers()
  equals(#callOrder, 2, "PullSelected issues the second withdrawal once a tick has passed")
  equals(printedMessages[before + 1], "Pulled 2 item(s).", "both items are counted once both withdrawals ran")
end

--------------------------------------------------------------------------

print(("%d passed, %d failed"):format(passed, failed))
for _, failure in ipairs(failures) do
  print("  FAIL: " .. failure)
end
os.exit(failed == 0 and 0 or 1)
