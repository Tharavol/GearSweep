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
  equals(printedMessages[1], "'yes' - expected 'on', 'off', 'slots', 'upgrades', or 'item <name>'.",
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
-- Upgrade best-per-slot selection (v0.4.0, #16)
--------------------------------------------------------------------------

stubs.loadModule(here .. "/../Classify.lua", "GearSweep", ns)
stubs.loadModule(here .. "/../Upgrade.lua", "GearSweep", ns)

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
  -- Confirmed live: a lone main-hand candidate (e.g. a wand) with no
  -- off-hand candidate found was wrongly averaged against an off-hand
  -- slot that was empty either way, halving its effective value. The
  -- off-hand isn't being lost by switching - it was already empty under
  -- the equipped two-hander - so this should compare directly.
  mockEquippedWeapons("item:staff", "INVTYPE_2HWEAPON", 256)

  local best = ns.Upgrade:SelectBest({ item("INVTYPE_RANGEDRIGHT", 292) })
  equals(#best, 1, "a lone main-hand candidate beats a weaker two-hander directly, not halved")
  equals(best[1].equipLoc, "INVTYPE_RANGEDRIGHT", "the main-hand candidate is selected")

  resetMockedEquipment()
end

do
  -- Same shape, but the lone candidate is too weak even at full (unhalved)
  -- value - the two-hander should still win.
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
  local slotsCalled, upgradesCalled = false, false
  ns.Upgrade.DumpEquippedSlots = function() slotsCalled = true end
  ns.Upgrade.DumpSelectedUpgrades = function() upgradesCalled = true end

  dispatch("debug slots")
  check(slotsCalled, "debug slots dispatches to Upgrade:DumpEquippedSlots")

  dispatch("debug upgrades")
  check(upgradesCalled, "debug upgrades dispatches to Upgrade:DumpSelectedUpgrades")
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

print(("%d passed, %d failed"):format(passed, failed))
for _, failure in ipairs(failures) do
  print("  FAIL: " .. failure)
end
os.exit(failed == 0 and 0 or 1)
