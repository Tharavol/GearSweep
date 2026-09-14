local ADDON_NAME, ns = ...

--------------------------------------------------------------------------
-- Options panel
--
-- Filter defaults/values live entirely in the sweep window itself (#12,
-- #17) - persisted per mode in ns.db.disenchant/ns.db.upgrade already, so
-- there's nothing to duplicate here. This panel just holds the toggles
-- that don't belong to any one mode: auto-open and debug logging (#20).
--------------------------------------------------------------------------

local Options = {}
ns.Options = Options

local function CreatePanel()
  local panel = CreateFrame("Frame")
  panel.name = ADDON_NAME

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ADDON_NAME)

  local autoOpenCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
  autoOpenCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12)
  autoOpenCheckbox.Text:SetText("Open automatically when visiting the bank")
  autoOpenCheckbox.tooltipText = "Open automatically when visiting the bank"
  autoOpenCheckbox.tooltipRequirement =
    "Opens the sweep window whenever you open your bank or Warband Bank."
  autoOpenCheckbox:SetScript("OnClick", function(self)
    ns.db.autoOpen = self:GetChecked() and true or false
  end)

  local debugCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
  debugCheckbox:SetPoint("TOPLEFT", autoOpenCheckbox, "BOTTOMLEFT", 0, -8)
  debugCheckbox.Text:SetText("Show diagnostic messages")
  debugCheckbox.tooltipText = "Show diagnostic messages"
  debugCheckbox.tooltipRequirement = "Print debug output while scanning and classifying items."
  debugCheckbox:SetScript("OnClick", function(self)
    ns.db.debug = self:GetChecked() and true or false
  end)

  panel:SetScript("OnShow", function()
    autoOpenCheckbox:SetChecked(ns.db.autoOpen and true or false)
    debugCheckbox:SetChecked(ns.db.debug and true or false)
  end)

  return panel
end

-- Registered once at load: the category needs to exist for the Settings
-- window to list it any time the player opens it.
function Options:Register()
  local panel = CreatePanel()
  local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
  Settings.RegisterAddOnCategory(category)
  self.category = category
end

-- Opens the Settings window straight to this panel, e.g. from /gs options.
function Options:Open()
  if self.category then
    Settings.OpenToCategory(self.category:GetID())
  end
end

Options:Register()
