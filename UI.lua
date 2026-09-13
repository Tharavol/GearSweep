local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI

--------------------------------------------------------------------------
-- Filter definitions - the one canonical list of quality/slot-group
-- values; Config.lua's defaults deliberately don't duplicate this.
--------------------------------------------------------------------------

local QUALITY_FILTERS = {
  { quality = 2, label = "Uncommon" },
  { quality = 3, label = "Rare" },
  { quality = 4, label = "Epic" },
}

local SLOT_GROUPS = {
  { id = "HEAD", label = "Head", equipLocs = { "INVTYPE_HEAD" } },
  { id = "NECK", label = "Neck", equipLocs = { "INVTYPE_NECK" } },
  { id = "SHOULDER", label = "Shoulder", equipLocs = { "INVTYPE_SHOULDER" } },
  { id = "CLOAK", label = "Cloak", equipLocs = { "INVTYPE_CLOAK" } },
  { id = "CHEST", label = "Chest", equipLocs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
  { id = "WRIST", label = "Wrist", equipLocs = { "INVTYPE_WRIST" } },
  { id = "HANDS", label = "Hands", equipLocs = { "INVTYPE_HAND" } },
  { id = "WAIST", label = "Waist", equipLocs = { "INVTYPE_WAIST" } },
  { id = "LEGS", label = "Legs", equipLocs = { "INVTYPE_LEGS" } },
  { id = "FEET", label = "Feet", equipLocs = { "INVTYPE_FEET" } },
  { id = "FINGER", label = "Finger", equipLocs = { "INVTYPE_FINGER" } },
  { id = "TRINKET", label = "Trinket", equipLocs = { "INVTYPE_TRINKET" } },
  { id = "WEAPON", label = "Weapon", equipLocs = {
      "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
      "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN",
    } },
  { id = "OFFHAND", label = "Off Hand", equipLocs = { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RELIC" } },
}

local EQUIP_LOC_TO_GROUP = {}
for _, group in ipairs(SLOT_GROUPS) do
  for _, loc in ipairs(group.equipLocs) do
    EQUIP_LOC_TO_GROUP[loc] = group
  end
end

-- Tries the modern color API first, falls back to the long-standing global
-- table, and finally plain white - cosmetic only, never worth erroring on.
-- Confirmed live: C_Item.GetItemQualityColor returns plain r, g, b (...)
-- numbers directly, not a color table/object.
local function GetQualityColor(quality)
  if C_Item and C_Item.GetItemQualityColor then
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if r then return r, g, b end
  end
  if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local c = ITEM_QUALITY_COLORS[quality]
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

--------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------

-- The baseline gate (#11) plus the user-adjustable toggles this panel
-- exposes (#12): quality/slot narrowing, item level range, and
-- independently switching Adventurer-tier and previous-season inclusion
-- on or off even though both are baseline-eligible.
local function PassesFilters(item, filters)
  if not ns.Classify:IsDisenchantCandidate(item) then
    return false
  end

  if filters.excludedQualities[item.quality] then
    return false
  end

  local group = EQUIP_LOC_TO_GROUP[item.equipLoc]
  if group and filters.excludedSlotGroups[group.id] then
    return false
  end

  if item.itemLevel then
    if item.itemLevel < filters.minLevel or item.itemLevel > filters.maxLevel then
      return false
    end
  end

  local isAdventurer = ns.Classify:IsAdventurerTier(item.hyperlink)
  if isAdventurer and not filters.includeAdventurerTier then
    return false
  end
  if not isAdventurer and not filters.includePreviousSeason then
    return false
  end

  return true
end

--------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------

local ROW_HEIGHT = 20
local MAX_ROWS = 200

local frame, content, rows, statusText
local minLevelBox, maxLevelBox
local qualityCheckboxes, slotCheckboxes, adventurerCheckbox, previousSeasonCheckbox

local function BuildFilters()
  local disenchant = ns.db.disenchant
  return {
    excludedQualities = disenchant.excludedQualities,
    excludedSlotGroups = disenchant.excludedSlotGroups,
    includeAdventurerTier = disenchant.includeAdventurerTier,
    includePreviousSeason = disenchant.includePreviousSeason,
    minLevel = tonumber(minLevelBox:GetText()) or disenchant.minLevel,
    maxLevel = tonumber(maxLevelBox:GetText()) or disenchant.maxLevel,
  }
end

local function GetOrCreateRow(index)
  local row = rows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, content)
  row:SetSize(560, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.checkbox:SetSize(20, 20)
  row.checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row.checkbox, "RIGHT", 4, 0)

  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetWidth(220)
  row.name:SetJustifyH("LEFT")

  row.ilvl = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.ilvl:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
  row.ilvl:SetWidth(40)

  row.slot = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.slot:SetPoint("LEFT", row.ilvl, "RIGHT", 4, 0)
  row.slot:SetWidth(80)
  row.slot:SetJustifyH("LEFT")

  row.source = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.source:SetPoint("LEFT", row.slot, "RIGHT", 4, 0)
  row.source:SetWidth(100)
  row.source:SetJustifyH("LEFT")

  rows[index] = row
  return row
end

-- Re-scans and re-populates the results list from current filter values.
function UI:Refresh()
  local filters = BuildFilters()
  local items = ns.Scanner:ScanAll()
  local shown = 0

  for _, item in ipairs(items) do
    if PassesFilters(item, filters) then
      shown = shown + 1
      if shown <= MAX_ROWS then
        local row = GetOrCreateRow(shown)
        row.item = item
        row.checkbox:SetChecked(true)
        row.icon:SetTexture(select(10, C_Item.GetItemInfo(item.hyperlink)))
        local r, g, b = GetQualityColor(item.quality)
        row.name:SetText(item.name or item.hyperlink)
        row.name:SetTextColor(r, g, b)
        row.ilvl:SetText(tostring(item.itemLevel or "?"))
        local group = EQUIP_LOC_TO_GROUP[item.equipLoc]
        row.slot:SetText(group and group.label or item.equipLoc or "?")
        row.source:SetText(item.source or "?")
        row:Show()
      end
    end
  end

  for i = shown + 1, #rows do
    rows[i]:Hide()
    rows[i].item = nil
  end

  content:SetHeight(math.max(1, math.min(shown, MAX_ROWS) * ROW_HEIGHT))

  if shown > MAX_ROWS then
    statusText:SetText(("%d matching items (showing first %d - narrow your filters)"):format(shown, MAX_ROWS))
  else
    statusText:SetText(("%d matching items"):format(shown))
  end
end

local function SetAllChecked(checked)
  for _, row in ipairs(rows) do
    if row.item then
      row.checkbox:SetChecked(checked)
    end
  end
end

local function PullSelected()
  local moved, failed, skipped = 0, 0, 0
  for _, row in ipairs(rows) do
    if row.item and row.checkbox:GetChecked() then
      local ok, reason = ns.Scanner:WithdrawToBags(row.item.bagID, row.item.slot)
      if ok then
        moved = moved + 1
      elseif reason == "bags full" then
        failed = failed + 1
      else
        skipped = skipped + 1
      end
    end
  end

  if failed > 0 then
    ns.Print("Pulled %d item(s). Stopped: bags are full (%d remaining).", moved, failed)
  elseif skipped > 0 then
    ns.Print("Pulled %d item(s), skipped %d (cursor was busy - try again).", moved, skipped)
  else
    ns.Print("Pulled %d item(s).", moved)
  end

  UI:Refresh()
end

-- Fixed row height every section below uses, so a section's total height
-- is always (rows * ROW_STEP), computable up front instead of guessed.
local ROW_STEP = 24

-- All checkboxes are positioned as explicit (x, y) offsets from `frame`
-- directly, never chained off a previous element's BOTTOMLEFT - that
-- chaining was what produced guessed, wrong gaps between sections.

local function CreateQualityCheckboxes(parent, x, yTop)
  local checkboxes = {}
  for i, def in ipairs(QUALITY_FILTERS) do
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yTop - (i - 1) * ROW_STEP)
    cb.Text:SetText(def.label)
    cb:SetScript("OnClick", function(self)
      ns.db.disenchant.excludedQualities[def.quality] = (not self:GetChecked()) or nil
    end)
    checkboxes[def.quality] = cb
  end
  return checkboxes, yTop - #QUALITY_FILTERS * ROW_STEP
end

-- Two columns of up to 7; returns the checkboxes table and the bottom Y
-- of the taller column, so the caller can lay out whatever comes next
-- without guessing how many rows this section took.
local function CreateSlotCheckboxes(parent, x, yTop)
  local checkboxes = {}
  local perColumn = 7
  local columnWidth = 110
  for i, group in ipairs(SLOT_GROUPS) do
    local col = math.floor((i - 1) / perColumn)
    local row = (i - 1) % perColumn
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x + col * columnWidth, yTop - row * ROW_STEP)
    cb.Text:SetText(group.label)
    cb:SetScript("OnClick", function(self)
      ns.db.disenchant.excludedSlotGroups[group.id] = (not self:GetChecked()) or nil
    end)
    checkboxes[group.id] = cb
  end
  local rowCount = math.min(perColumn, #SLOT_GROUPS)
  return checkboxes, yTop - rowCount * ROW_STEP
end

local function CreatePanel()
  frame = CreateFrame("Frame", "GearSweepFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(620, 640)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
  frame.title:SetText(ADDON_NAME .. " - Disenchant")

  local PADDING = 16
  local LABEL_COLUMN = 100
  local y = -32

  local qualityLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  qualityLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  qualityLabel:SetText("Quality")
  qualityCheckboxes, y = CreateQualityCheckboxes(frame, PADDING + LABEL_COLUMN, y)
  y = y - 10

  local slotLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  slotLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  slotCheckboxes, y = CreateSlotCheckboxes(frame, PADDING + LABEL_COLUMN, y)
  slotLabel:SetText("Slot")
  y = y - 10

  local seasonLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  seasonLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  seasonLabel:SetText("Season / Tier")

  adventurerCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  adventurerCheckbox:SetSize(20, 20)
  adventurerCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y)
  adventurerCheckbox.Text:SetText("Adventurer tier (current season)")
  adventurerCheckbox:SetScript("OnClick", function(self)
    ns.db.disenchant.includeAdventurerTier = self:GetChecked() and true or false
  end)
  y = y - ROW_STEP

  previousSeasonCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  previousSeasonCheckbox:SetSize(20, 20)
  previousSeasonCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y)
  previousSeasonCheckbox.Text:SetText("Previous season / expansion")
  previousSeasonCheckbox:SetScript("OnClick", function(self)
    ns.db.disenchant.includePreviousSeason = self:GetChecked() and true or false
  end)
  y = y - ROW_STEP - 10

  local levelLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  levelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  levelLabel:SetText("Item Level")

  minLevelBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  minLevelBox:SetSize(50, 20)
  minLevelBox:SetAutoFocus(false)
  minLevelBox:SetNumeric(true)
  minLevelBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y + 2)
  minLevelBox:SetScript("OnEnterPressed", function(self)
    ns.db.disenchant.minLevel = tonumber(self:GetText()) or ns.DEFAULT_SETTINGS.disenchant.minLevel
    self:ClearFocus()
  end)

  local toLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  toLabel:SetPoint("LEFT", minLevelBox, "RIGHT", 6, 0)
  toLabel:SetText("to")

  maxLevelBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  maxLevelBox:SetSize(50, 20)
  maxLevelBox:SetAutoFocus(false)
  maxLevelBox:SetNumeric(true)
  maxLevelBox:SetPoint("LEFT", toLabel, "RIGHT", 6, 0)
  maxLevelBox:SetScript("OnEnterPressed", function(self)
    ns.db.disenchant.maxLevel = tonumber(self:GetText()) or ns.DEFAULT_SETTINGS.disenchant.maxLevel
    self:ClearFocus()
  end)
  y = y - ROW_STEP - 10

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(80, 22)
  refreshButton:SetText("Refresh")
  refreshButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  refreshButton:SetScript("OnClick", function() UI:Refresh() end)

  local selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectAllButton:SetSize(90, 22)
  selectAllButton:SetText("Select All")
  selectAllButton:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)
  selectAllButton:SetScript("OnClick", function() SetAllChecked(true) end)

  local selectNoneButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectNoneButton:SetSize(90, 22)
  selectNoneButton:SetText("Select None")
  selectNoneButton:SetPoint("LEFT", selectAllButton, "RIGHT", 8, 0)
  selectNoneButton:SetScript("OnClick", function() SetAllChecked(false) end)

  statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  statusText:SetPoint("TOPLEFT", refreshButton, "BOTTOMLEFT", 0, -8)
  statusText:SetText("0 matching items")

  local scrollFrame = CreateFrame("ScrollFrame", "GearSweepResultsScrollFrame", frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 44)

  content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(560, 1)
  scrollFrame:SetScrollChild(content)
  rows = {}

  local pullButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  pullButton:SetSize(140, 24)
  pullButton:SetText("Pull Selected")
  pullButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
  pullButton:SetScript("OnClick", PullSelected)

  frame:SetScript("OnShow", function()
    local disenchant = ns.db.disenchant
    for quality, cb in pairs(qualityCheckboxes) do
      cb:SetChecked(not disenchant.excludedQualities[quality])
    end
    for id, cb in pairs(slotCheckboxes) do
      cb:SetChecked(not disenchant.excludedSlotGroups[id])
    end
    adventurerCheckbox:SetChecked(disenchant.includeAdventurerTier)
    previousSeasonCheckbox:SetChecked(disenchant.includePreviousSeason)
    minLevelBox:SetText(tostring(disenchant.minLevel))
    maxLevelBox:SetText(tostring(disenchant.maxLevel))
    UI:Refresh()
  end)
end

function UI:Show()
  if not frame then
    CreatePanel()
  end
  frame:Show()
end
