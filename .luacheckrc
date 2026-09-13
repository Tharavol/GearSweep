std = "lua51"
max_line_length = 120

-- WoW event handlers always receive (self, event, ...); ignore unused args
-- entirely since callbacks must match Blizzard's fixed signatures.
ignore = {
    "212",            -- unused argument
    "211/ADDON_NAME", -- every file starts `local ADDON_NAME, ns = ...`
}

globals = {
    -- SavedVariables declared in the .toc
    "GearSweepDB",

    "SLASH_GEARSWEEP1",
    "SLASH_GEARSWEEP2",
    "SlashCmdList",
}

read_globals = {
    -- Namespaced API tables
    "C_AddOns", "C_Bank", "C_Container", "C_Item", "C_PlayerInfo", "C_Timer", "Enum",

    -- Frame / UI globals
    "CreateFrame", "UIParent", "Settings",

    -- Addon metadata
    "GetAddOnMetadata", "GetBuildInfo", "IsAddOnLoaded",
}

-- The offline test harness installs its own WoW stubs into _G on purpose.
files["Tests/**"] = {
    ignore = {"111", "112", "113", "121", "122"},
}
