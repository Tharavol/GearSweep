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

ns.Classify = {}
stubs.loadModule(here .. "/../Upgrade.lua", "GearSweep", ns)

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
  -- A real one-hand+offhand pair fills two independent slots, so it wins
  -- over a two-hand item even when the two-hand's own level is higher.
  local best = ns.Upgrade:SelectBest({
    item("INVTYPE_2HWEAPON", 500),
    item("INVTYPE_WEAPONMAINHAND", 400),
    item("INVTYPE_SHIELD", 400),
  })
  equals(#best, 2, "a genuine one-hand+offhand pair beats a two-hand item")
  check(best[1].equipLoc ~= "INVTYPE_2HWEAPON" and best[2].equipLoc ~= "INVTYPE_2HWEAPON",
    "the two-hand item is not selected alongside the pair")
end

do
  local best = ns.Upgrade:SelectBest({ item("INVTYPE_WEAPONMAINHAND", 460) })
  equals(#best, 1, "a lone main-hand candidate is selected on its own")
  equals(best[1].equipLoc, "INVTYPE_WEAPONMAINHAND", "the main-hand item is selected")
end

--------------------------------------------------------------------------
-- Upgrade vs. currently-equipped gear (v0.4.0, #16 correctness fix)
--------------------------------------------------------------------------

ns.Classify.IsUsable = function() return true end
ns.Classify.IsSpecAppropriate = function() return true end

do
  -- Empty slot (GetInventoryItemLink returns nil by default): anything
  -- real counts as an upgrade.
  local candidate = item("INVTYPE_HEAD", 100)
  candidate.hyperlink = "item:1"
  candidate.quality = 4
  check(ns.Upgrade:IsCandidate(candidate), "any real item is an upgrade over an empty slot")
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

  dispatch("debug item bramble")
  equals(dumpedLink, "item:1", "debug item finds a case-insensitive substring match and dumps its tooltip")

  dumpedLink = nil
  dispatch("debug item nonexistent")
  check(dumpedLink == nil, "debug item reports nothing found rather than dumping a wrong item")
  equals(printedMessages[1], "No item matching 'nonexistent' found in bags/bank.",
    "debug item explains when no match is found")
end

--------------------------------------------------------------------------

print(("%d passed, %d failed"):format(passed, failed))
for _, failure in ipairs(failures) do
  print("  FAIL: " .. failure)
end
os.exit(failed == 0 and 0 or 1)
