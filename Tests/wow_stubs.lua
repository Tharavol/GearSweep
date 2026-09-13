-- Minimal stand-ins for the World of Warcraft API, enough to load the addon's
-- non-UI modules outside the game. Only what those modules actually touch is
-- implemented; anything else deliberately stays absent so a test that starts
-- depending on it fails loudly rather than silently passing.

local stubs = {}

local pendingTimers = {}

function stubs.install(env)
  env.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
  end

  env.GetBuildInfo = function()
    return "12.0.7", "60000", "Jul 26 2026", 120007
  end

  env.C_Timer = {
    After = function(_, callback)
      table.insert(pendingTimers, callback)
    end,
  }

  env.C_Item = {
    GetDetailedItemLevelInfo = function() return nil end,
    GetItemInfo = function() return nil end,
  }

  env.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
  }

  env.C_Bank = nil

  env.SlashCmdList = {}

  return env
end

function stubs.drainTimers(limit)
  local ran = 0
  while #pendingTimers > 0 and ran < (limit or 10000) do
    local callback = table.remove(pendingTimers, 1)
    callback()
    ran = ran + 1
  end
  return ran
end

function stubs.resetTimers()
  pendingTimers = {}
end

-- Loads an addon file the way WoW does, passing (addonName, privateTable) as
-- the vararg the file's `local ADDON_NAME, ns = ...` picks up.
function stubs.loadModule(path, addonName, ns)
  local chunk, err = loadfile(path)
  if not chunk then
    error("failed to load " .. path .. ": " .. tostring(err))
  end
  return chunk(addonName, ns)
end

return stubs
