local ADDON_NAME, ns = ...

--------------------------------------------------------------------------
-- Options panel
--
-- Skeleton only: a debug-logging toggle against ns.db.debug. Real filter
-- defaults and the auto-open toggle land in #20 (v0.5.0), once disenchant
-- and upgrade mode (#11-#18) exist to have defaults for.
--------------------------------------------------------------------------

local Options = {}
ns.Options = Options

local function CreatePanel()
  local panel = CreateFrame("Frame")
  panel.name = ADDON_NAME

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ADDON_NAME)

  local debugCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
  debugCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12)
  debugCheckbox.Text:SetText("Show diagnostic messages")
  debugCheckbox.tooltipText = "Show diagnostic messages"
  debugCheckbox.tooltipRequirement = "Print debug output while scanning and classifying items."
  debugCheckbox:SetScript("OnClick", function(self)
    ns.db.debug = self:GetChecked() and true or false
  end)

  panel:SetScript("OnShow", function()
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
