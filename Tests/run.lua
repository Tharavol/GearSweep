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

ns.DEFAULT_SETTINGS = { debug = false }
ns.db = { debug = false }

local optionsOpened
ns.Options = {
  Open = function(_self)
    optionsOpened = true
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
  optionsOpened = false
  dispatch("")
  check(optionsOpened, "an empty command opens the settings panel")
  equals(#printedMessages, 0, "opening the panel prints nothing")
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
  equals(printedMessages[1], "'yes' - expected 'on' or 'off'.",
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
end

--------------------------------------------------------------------------

print(("%d passed, %d failed"):format(passed, failed))
for _, failure in ipairs(failures) do
  print("  FAIL: " .. failure)
end
os.exit(failed == 0 and 0 or 1)
