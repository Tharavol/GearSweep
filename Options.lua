local ADDON_NAME, ns = ...

--------------------------------------------------------------------------
-- Options panel
--
-- Filters live in the sweep window (#12, #17); this panel holds only the
-- mode-independent toggles: auto-open and debug logging (#20).
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

function Options:Register()
  local panel = CreatePanel()
  local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
  Settings.RegisterAddOnCategory(category)
  self.category = category
end

function Options:Open()
  Settings.OpenToCategory(self.category:GetID())
end

Options:Register()
