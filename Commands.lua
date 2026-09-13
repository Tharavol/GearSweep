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

local function OpenPanel() ns.Options:Open() end

-- Forward-declared so the "help" entry below can close over it before its
-- body (which needs COMMANDS to exist) is assigned further down.
local PrintUsage

-- "", "config" and "gui" are silent aliases of "options": each opens the
-- panel but carries no help text of its own, so PrintUsage doesn't repeat
-- the same line four times.
local COMMANDS = {
  { name = "", help = {}, handler = OpenPanel },
  {
    name = "options",
    help = {
      "|cffffff00/gs|r, |cffffff00/gs options|r, |cffffff00/gs config|r, "
        .. "|cffffff00/gs gui|r - open the settings panel",
    },
    handler = OpenPanel,
  },
  { name = "config", help = {}, handler = OpenPanel },
  { name = "gui", help = {}, handler = OpenPanel },
  {
    name = "debug",
    help = { "|cffffff00/gs debug [on|off]|r - toggle or set diagnostic messages" },
    handler = function(_, rest)
      if rest == "on" then
        ns.db.debug = true
      elseif rest == "off" then
        ns.db.debug = false
      elseif rest == "" then
        ns.db.debug = not ns.db.debug
      else
        ns.Print("'%s' - expected 'on' or 'off'.", rest)
        return
      end
      ns.Print("Debug messages are %s.", ns.db.debug and "|cff00ff00on|r" or "|cffff0000off|r")
    end,
  },
  {
    name = "status",
    help = { "|cffffff00/gs status|r - show current settings" },
    handler = function()
      ns.Print("%s settings:", ns.VERSION)
      print(("  Debug messages: %s"):format(ns.db.debug and "|cff00ff00on|r" or "|cffff0000off|r"))
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
        ns.db[key] = value
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
