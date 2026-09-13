local ADDON_NAME, ns = ...

-- Applied onto GearSweepDB by Core.lua on ADDON_LOADED for any key a saved
-- profile doesn't already have, so new settings get a default without
-- clobbering what a player already configured.
ns.DEFAULT_SETTINGS = {
  debug = false,
}
