local ADDON_NAME, ns = ...

-- Applied onto GearSweepDB by Core.lua on ADDON_LOADED for any key a saved
-- profile doesn't already have, so new settings get a default without
-- clobbering what a player already configured.
--
-- excludedQualities/excludedSlotGroups default empty (nothing excluded)
-- rather than listing every quality/slot as "true": it means UI.lua owns
-- the one canonical list of quality/slot-group values, instead of that
-- list being duplicated (and able to drift out of sync) here too.
-- Used wherever a default gets assigned into ns.db (initial merge, reset):
-- a plain `ns.db[key] = value` would copy a nested default table by
-- reference, so the first filter checkbox click would mutate
-- DEFAULT_SETTINGS itself and permanently corrupt what "reset" resets to.
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

ns.DEFAULT_SETTINGS = {
  debug = false,
  -- Per-section collapse state for the sweep window's filter sections
  -- (#32): all expanded by default, matching prior versions' fixed layout.
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
