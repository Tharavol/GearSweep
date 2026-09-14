local ADDON_NAME, ns = ...

--------------------------------------------------------------------------
-- Slash command dispatch: /gearsweep (alias /gs)
--
-- A table of { name, help, handler } rather than an if-chain, so
-- PrintUsage is derived from the same data Dispatch uses instead of a
-- second hand-maintained command list that could drift out of sync
-- (matches ShoppingConverter/Commands.lua and Crosshairs/Slash.lua).
--------------------------------------------------------------------------

local Commands = {}
ns.Commands = Commands

local function OpenSweep() ns.UI:Show() end
local function OpenOptions() ns.Options:Open() end

-- Forward-declared so the "help" entry below can close over it before its
-- body (which needs COMMANDS to exist) is assigned further down.
local PrintUsage

-- "config" and "gui" are silent aliases of "options": each opens the
-- settings panel but carries no help text of its own, so PrintUsage
-- doesn't repeat the same line three times. The bare command opens the
-- main sweep window instead - that's the addon's actual feature.
local COMMANDS = {
  {
    name = "",
    help = { "|cffffff00/gs|r, |cffffff00/gearsweep|r - open the disenchant sweep window" },
    handler = OpenSweep,
  },
  {
    name = "options",
    help = {
      "|cffffff00/gs options|r, |cffffff00/gs config|r, |cffffff00/gs gui|r - open the settings panel",
    },
    handler = OpenOptions,
  },
  { name = "config", help = {}, handler = OpenOptions },
  { name = "gui", help = {}, handler = OpenOptions },
  {
    name = "debug",
    help = {
      "|cffffff00/gs debug [on|off]|r - toggle or set diagnostic messages",
      "|cffffff00/gs debug slots|r - print current item level in every equipment slot",
      "|cffffff00/gs debug upgrades|r - print the items Upgrade mode currently selects",
      "|cffffff00/gs debug weapons|r - print the two-hand vs. one-hand+offhand comparison",
      "|cffffff00/gs debug item <name>|r - print an item's raw tooltip data by name",
    },
    handler = function(_, rest)
      if rest == "on" then
        ns.db.debug = true
      elseif rest == "off" then
        ns.db.debug = false
      elseif rest == "" then
        ns.db.debug = not ns.db.debug
      elseif rest == "slots" then
        ns.Upgrade:DumpEquippedSlots()
        return
      elseif rest == "upgrades" then
        ns.Upgrade:DumpSelectedUpgrades()
        return
      elseif rest == "weapons" then
        ns.Upgrade:DumpWeaponComparison()
        return
      elseif rest:match("^item%s+%S") then
        local query = rest:match("^item%s+(.+)$")
        local found
        for _, item in ipairs(ns.Scanner:ScanAll()) do
          if item.name and item.name:lower():find(query, 1, true) then
            found = item
            break
          end
        end
        if found then
          ns.Print("%s: ilvl %d, quality %d, %s, source %s", found.name,
            found.itemLevel or 0, found.quality or -1, found.equipLoc or "?", found.source or "?")
          ns.Classify:DumpTooltip(found.hyperlink)
          return
        end

        -- Not in bags/bank - try equipped slots (#35: comparing a
        -- known-bound item's IsUsableItem result against unbound ones).
        local equippedLink, slotName = ns.Upgrade:FindEquippedLink(query)
        if equippedLink then
          ns.Print("Equipped in %s.", slotName)
          ns.Classify:DumpTooltip(equippedLink)
        else
          ns.Print("No item matching '%s' found in bags/bank or equipped.", query)
        end
        return
      else
        ns.Print("'%s' - expected 'on', 'off', 'slots', 'upgrades', 'weapons', or 'item <name>'.", rest)
        return
      end
      ns.Print("Debug messages are %s.", ns.db.debug and "|cff00ff00on|r" or "|cffff0000off|r")
    end,
  },
  {
    name = "autoopen",
    help = { "|cffffff00/gs autoopen [on|off]|r - toggle or set auto-open on visiting the bank" },
    handler = function(_, rest)
      if rest == "on" then
        ns.db.autoOpen = true
      elseif rest == "off" then
        ns.db.autoOpen = false
      elseif rest == "" then
        ns.db.autoOpen = not ns.db.autoOpen
      else
        ns.Print("'%s' - expected 'on' or 'off'.", rest)
        return
      end
      ns.Print("Auto-open on visiting the bank is %s.",
        ns.db.autoOpen and "|cff00ff00on|r" or "|cffff0000off|r")
    end,
  },
  {
    name = "status",
    help = { "|cffffff00/gs status|r - show current settings" },
    handler = function()
      ns.Print("%s settings:", ns.VERSION)
      print(("  Debug messages: %s"):format(ns.db.debug and "|cff00ff00on|r" or "|cffff0000off|r"))
      print(("  Auto-open on bank: %s"):format(ns.db.autoOpen and "|cff00ff00on|r" or "|cffff0000off|r"))
    end,
  },
  {
    name = "version",
    help = { "|cffffff00/gs version|r - show the addon version" },
    handler = function() ns.Print(ns.VERSION) end,
  },
  {
    name = "reset",
    help = { "|cffffff00/gs reset|r - restore settings to defaults" },
    handler = function()
      for key, value in pairs(ns.DEFAULT_SETTINGS) do
        ns.db[key] = ns.DeepCopy(value)
      end
      ns.Print("Settings restored to defaults.")
    end,
  },
  {
    name = "help",
    help = { "|cffffff00/gs help|r - show this list" },
    handler = function() PrintUsage() end,
  },
}

PrintUsage = function()
  ns.Print("%s commands:", ns.VERSION)
  for _, command in ipairs(COMMANDS) do
    for _, line in ipairs(command.help) do
      print("  " .. line)
    end
  end
end

local function Parse(input)
  local raw = input or ""
  local command, argument = raw:match("^%s*(%S*)%s*(.-)%s*$")
  return command:lower(), argument, argument:lower()
end

function Commands:Dispatch(input)
  local command, argument, rest = Parse(input)

  for _, entry in ipairs(COMMANDS) do
    if entry.name == command then
      entry.handler(argument, rest)
      return
    end
  end

  -- A typo must be visibly a typo, never a silent fallback.
  ns.Print("Unknown command: %s", command)
  PrintUsage()
end

SLASH_GEARSWEEP1 = "/gearsweep"
SLASH_GEARSWEEP2 = "/gs"
SlashCmdList["GEARSWEEP"] = function(msg) Commands:Dispatch(msg) end
