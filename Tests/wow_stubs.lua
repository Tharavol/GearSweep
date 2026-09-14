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

  -- Tests override this per case to simulate an item's upgrade-track/
  -- requirement tooltip data (Classify.lua's season/tier/usable checks).
  env.C_TooltipInfo = {
    GetHyperlink = function() return nil end,
  }

  env.CursorHasItem = function() return false end
  env.C_Container.PickupContainerItem = function() end

  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

  -- Minimal enough for Classify.lua's background scan tooltip (GetScanTooltip):
  -- NumLines counts consecutive _G[name.."TextLeft"..i] entries a test has set,
  -- so a test drives tooltip content by populating _G directly rather than
  -- through a second, parallel line-storage mechanism.
  env.UIParent = {}
  env.CreateFrame = function(_frameType, name)
    local frame = { name = name }
    function frame:GetName() return name end
    function frame:SetOwner() end
    function frame:SetHyperlink() end
    function frame:NumLines()
      local n = 0
      while env[name .. "TextLeft" .. (n + 1)] do
        n = n + 1
      end
      return n
    end
    return frame
  end

  -- Tests override these per case to simulate the player's class/spec
  -- (Classify.lua's spec-relevance check, Classify:IsSpecAppropriate).
  env.UnitClass = function() return nil end
  env.GetSpecialization = function() return nil end
  env.GetSpecializationInfo = function() return nil end

  -- Real Blizzard item classification enums, for Classify.lua's class
  -- proficiency table (#35).
  env.Enum = env.Enum or {}
  env.Enum.ItemClass = { Weapon = 2, Armor = 4 }
  env.Enum.ItemWeaponSubclass = {
    Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
    Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Bearclaw = 11, Catclaw = 12,
    Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16, Obsolete3 = 17, Crossbow = 18,
    Wand = 19, Fishingpole = 20,
  }
  env.Enum.ItemArmorSubclass = {
    Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Cosmetic = 5, Shield = 6,
    Libram = 7, Idol = 8, Totem = 9, Sigil = 10, Relic = 11,
  }

  -- Tests override this per-case; default keeps unrelated tests inert.
  env.UnitClassBase = function() return nil end

  -- Real Blizzard inventory slot IDs (GetInventorySlotInfo), stable since
  -- Classic. Every slot starts empty (GetInventoryItemLink returns nil);
  -- tests override it per-case to simulate equipped gear.
  local SLOT_IDS = {
    HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, BackSlot = 15, ChestSlot = 5,
    WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
    Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
    MainHandSlot = 16, SecondaryHandSlot = 17,
  }
  env.GetInventorySlotInfo = function(name) return SLOT_IDS[name] end
  env.GetInventoryItemLink = function() return nil end

  -- Tests override this to simulate a character with real average gear,
  -- so an empty-slot comparison isn't trivially beaten by junk (#36).
  env.GetAverageItemLevel = function() return 0, 0, 0 end

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
