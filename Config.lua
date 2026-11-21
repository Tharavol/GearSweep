local ADDON_NAME, ns = ...

-- Used wherever a default is assigned into ns.db, so nested default tables
-- are never shared with (and mutated through) the saved settings.
function ns.DeepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = ns.DeepCopy(v)
  end
  return copy
end

-- Merged into GearSweepDB on ADDON_LOADED for any missing key (Core.lua).
-- Exclusion sets default empty; UI.lua owns the list of qualities/slots.
ns.DEFAULT_SETTINGS = {
  debug = false,
  -- Open the sweep window when the bank opens (#19).
  autoOpen = true,
  -- Per-section collapse state for the filter sections (#32).
  uiCollapsed = {
    quality = false,
    slot = false,
    season = false,
  },
  disenchant = {
    excludedQualities = {},
    excludedSlotGroups = {},
    includeAdventurerTier = true,
    includePreviousSeason = true,
    minLevel = 1,
    maxLevel = 999,
  },
  upgrade = {
    excludedQualities = {},
    excludedSlotGroups = {},
    minLevel = 1,
    maxLevel = 999,
  },
}
