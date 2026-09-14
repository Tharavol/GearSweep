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

-- Quality/slot/item-level narrowing (#12) shared by both modes.
local function PassesCommonFilters(item, filters)
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

  return true
end

-- The baseline disenchant gate (#11) plus the user-adjustable toggles this
-- panel exposes (#12): independently switching Adventurer-tier and
-- previous-season inclusion on or off even though both are baseline-eligible.
local function PassesDisenchantFilters(item, filters)
  if not ns.Classify:IsDisenchantCandidate(item) then
    return false
  end

  if not PassesCommonFilters(item, filters) then
    return false
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

-- Upgrade mode's candidate gate (#15): usable by class/armor/weapon
-- proficiency and spec-appropriate, then the same quality/slot/ilvl
-- narrowing as disenchant mode.
local function PassesUpgradeFilters(item, filters)
  if not ns.Upgrade:IsCandidate(item) then
    return false
  end
  return PassesCommonFilters(item, filters)
end

--------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------

local ROW_HEIGHT = 20
local MAX_ROWS = 200

local frame, content, rows, statusText
local minLevelBox, maxLevelBox, levelLabel, refreshButton
local qualityCheckboxes, slotCheckboxes, adventurerCheckbox, previousSeasonCheckbox
local qualityHeader, slotHeader, seasonHeader
local disenchantModeCheckbox, upgradeModeCheckbox

local PADDING = 16
local LABEL_COLUMN = 100

-- "disenchant" or "upgrade" (#17). Not persisted - the panel always opens
-- on Disenchant, matching v0.3.0's behavior for players who never switch.
local currentMode = "disenchant"

local function BuildFilters()
  local settings = ns.db[currentMode]
  return {
    excludedQualities = settings.excludedQualities,
    excludedSlotGroups = settings.excludedSlotGroups,
    includeAdventurerTier = ns.db.disenchant.includeAdventurerTier,
    includePreviousSeason = ns.db.disenchant.includePreviousSeason,
    minLevel = tonumber(minLevelBox:GetText()) or settings.minLevel,
    maxLevel = tonumber(maxLevelBox:GetText()) or settings.maxLevel,
  }
end

local function GetOrCreateRow(index)
  local row = rows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, content)
  row:SetSize(560, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  -- SetBagItem (not SetHyperlink) so hovering a row shows exactly the same
  -- tooltip - including Blizzard's automatic equipped-item comparison
  -- pane - as hovering the item directly in bags/bank (#33).
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self.item.bagID, self.item.slot)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
-- In upgrade mode, every candidate is listed but only the best-per-slot
-- picks (#16) start checked - #17 asks that the rest stay visible and
-- selectable, not hidden, so the player can still grab a runner-up by hand.
function UI:Refresh()
  local filters = BuildFilters()
  local items = ns.Scanner:ScanAll()
  local shown = 0

  -- Deliberately not `(currentMode == "upgrade") and X or Y`: when X is
  -- false (the common case - most scanned items aren't upgrades), that
  -- idiom falls through to Y instead of staying false, silently letting
  -- disenchant-eligible junk back into the Upgrade mode results (#31).
  local matching = {}
  for _, item in ipairs(items) do
    local ok
    if currentMode == "upgrade" then
      ok = PassesUpgradeFilters(item, filters)
    else
      ok = PassesDisenchantFilters(item, filters)
    end
    if ok then
      table.insert(matching, item)
    end
  end

  local preChecked
  if currentMode == "upgrade" then
    preChecked = {}
    for _, item in ipairs(ns.Upgrade:SelectBest(matching)) do
      preChecked[item] = true
    end
  end

  for _, item in ipairs(matching) do
    shown = shown + 1
    if shown <= MAX_ROWS then
      local row = GetOrCreateRow(shown)
      row.item = item
      row.checkbox:SetChecked(preChecked == nil or preChecked[item] == true)
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

-- Checkboxes are created once, then positioned separately (PositionXxx
-- below) so a section's collapse toggle (#32) can re-run just the layout
-- pass without recreating any frames. Positions are always explicit (x, y)
-- offsets from `frame` directly, never chained off a previous element's
-- BOTTOMLEFT - that chaining was what produced guessed, wrong gaps
-- between sections.

local function CreateQualityCheckboxes(parent)
  local checkboxes = {}
  for _, def in ipairs(QUALITY_FILTERS) do
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.Text:SetText(def.label)
    cb:SetScript("OnClick", function(self)
      ns.db[currentMode].excludedQualities[def.quality] = (not self:GetChecked()) or nil
    end)
    checkboxes[def.quality] = cb
  end
  return checkboxes
end

-- Repositions the (already-created) quality checkboxes and returns the
-- bottom Y of the section, so the caller can lay out whatever comes next
-- without guessing how many rows it took.
local function PositionQualityCheckboxes(x, yTop)
  for i, def in ipairs(QUALITY_FILTERS) do
    qualityCheckboxes[def.quality]:SetPoint("TOPLEFT", frame, "TOPLEFT", x, yTop - (i - 1) * ROW_STEP)
  end
  return yTop - #QUALITY_FILTERS * ROW_STEP
end

local function CreateSlotCheckboxes(parent)
  local checkboxes = {}
  for _, group in ipairs(SLOT_GROUPS) do
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.Text:SetText(group.label)
    cb:SetScript("OnClick", function(self)
      ns.db[currentMode].excludedSlotGroups[group.id] = (not self:GetChecked()) or nil
    end)
    checkboxes[group.id] = cb
  end
  return checkboxes
end

-- Two columns of up to 7; returns the bottom Y of the taller column.
local function PositionSlotCheckboxes(x, yTop)
  local perColumn = 7
  local columnWidth = 110
  for i, group in ipairs(SLOT_GROUPS) do
    local col = math.floor((i - 1) / perColumn)
    local row = (i - 1) % perColumn
    slotCheckboxes[group.id]:SetPoint("TOPLEFT", frame, "TOPLEFT", x + col * columnWidth, yTop - row * ROW_STEP)
  end
  local rowCount = math.min(perColumn, #SLOT_GROUPS)
  return yTop - rowCount * ROW_STEP
end

-- A clickable section label that toggles its collapse state (#32) and
-- reflows everything below it, freeing space for the results list.
local function CreateSectionHeader(key, label)
  local button = CreateFrame("Button", nil, frame)
  button:SetSize(LABEL_COLUMN, 20)
  button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  text:SetPoint("LEFT", button, "LEFT", 0, 0)
  text:SetJustifyH("LEFT")
  button.text = text
  button.key = key
  button.label = label
  button:SetScript("OnClick", function(self)
    ns.db.uiCollapsed[self.key] = not ns.db.uiCollapsed[self.key]
    UI:RelayoutFrame()
  end)
  return button
end

local function UpdateSectionHeaderText(button)
  button.text:SetText((ns.db.uiCollapsed[button.key] and "+ " or "- ") .. button.label)
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

  -- Without an explicit strata this defaults to "MEDIUM", below the
  -- bag/bank container frames it's meant to be used alongside (#30) -
  -- confirmed live: with bags and the Warband Bank open, GearSweep
  -- rendered interleaved with them, with other addons' UI showing through
  -- in the gaps. "HIGH" plus SetToplevel matches those windows and raises
  -- this one on click, same as they do.
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)

  -- Registers this frame with Blizzard's default UI so Escape closes it
  -- like any other standard window (#29).
  tinsert(UISpecialFrames, "GearSweepFrame")

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)

  local modeLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  modeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)
  modeLabel:SetText("Mode")

  disenchantModeCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  disenchantModeCheckbox:SetSize(20, 20)
  disenchantModeCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, -32)
  disenchantModeCheckbox.Text:SetText("Disenchant")
  disenchantModeCheckbox:SetScript("OnClick", function() UI:SetMode("disenchant") end)

  upgradeModeCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  upgradeModeCheckbox:SetSize(20, 20)
  upgradeModeCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN + 130, -32)
  upgradeModeCheckbox.Text:SetText("Upgrade")
  upgradeModeCheckbox:SetScript("OnClick", function() UI:SetMode("upgrade") end)

  qualityHeader = CreateSectionHeader("quality", "Quality")
  qualityCheckboxes = CreateQualityCheckboxes(frame)

  slotHeader = CreateSectionHeader("slot", "Slot")
  slotCheckboxes = CreateSlotCheckboxes(frame)

  seasonHeader = CreateSectionHeader("season", "Season / Tier")

  adventurerCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  adventurerCheckbox:SetSize(20, 20)
  adventurerCheckbox.Text:SetText("Adventurer tier (current season)")
  adventurerCheckbox:SetScript("OnClick", function(self)
    ns.db.disenchant.includeAdventurerTier = self:GetChecked() and true or false
  end)

  previousSeasonCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  previousSeasonCheckbox:SetSize(20, 20)
  previousSeasonCheckbox.Text:SetText("Previous season / expansion")
  previousSeasonCheckbox:SetScript("OnClick", function(self)
    ns.db.disenchant.includePreviousSeason = self:GetChecked() and true or false
  end)

  levelLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  levelLabel:SetText("Item Level")

  minLevelBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  minLevelBox:SetSize(50, 20)
  minLevelBox:SetAutoFocus(false)
  minLevelBox:SetNumeric(true)
  minLevelBox:SetScript("OnEnterPressed", function(self)
    ns.db[currentMode].minLevel = tonumber(self:GetText()) or ns.DEFAULT_SETTINGS[currentMode].minLevel
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
    ns.db[currentMode].maxLevel = tonumber(self:GetText()) or ns.DEFAULT_SETTINGS[currentMode].maxLevel
    self:ClearFocus()
  end)

  refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(80, 22)
  refreshButton:SetText("Refresh")
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
    UI:SetMode(currentMode)
  end)
end

-- Repositions everything below the Mode row from scratch (#32): called on
-- every mode switch and every section collapse/expand toggle. Most widgets
-- below the sections chain off each other via relative anchors (Select
-- All/None off Refresh, statusText off Refresh, the scroll frame off
-- statusText) and never need repositioning directly - only each section's
-- own header/body and the two explicitly `frame`-anchored rows after them
-- (Item Level, Refresh) do.
function UI:RelayoutFrame()
  local y = -32 - ROW_STEP - 10

  -- A collapsed section still occupies its own header row - only the
  -- checkbox rows below it disappear - so `y` always drops by at least
  -- ROW_STEP here, via PositionXxxCheckboxes when expanded (its first row
  -- shares the header's row) or explicitly when collapsed. Omitting the
  -- explicit drop was why collapsing a section overlapped the next one.
  qualityHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  UpdateSectionHeaderText(qualityHeader)
  local qualityCollapsed = ns.db.uiCollapsed.quality
  for _, cb in pairs(qualityCheckboxes) do cb:SetShown(not qualityCollapsed) end
  if qualityCollapsed then
    y = y - ROW_STEP
  else
    y = PositionQualityCheckboxes(PADDING + LABEL_COLUMN, y)
  end
  y = y - 10

  slotHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  UpdateSectionHeaderText(slotHeader)
  local slotCollapsed = ns.db.uiCollapsed.slot
  for _, cb in pairs(slotCheckboxes) do cb:SetShown(not slotCollapsed) end
  if slotCollapsed then
    y = y - ROW_STEP
  else
    y = PositionSlotCheckboxes(PADDING + LABEL_COLUMN, y)
  end
  y = y - 10

  -- Season/Tier only means something in disenchant mode (#17); the header
  -- itself is hidden entirely in upgrade mode rather than just collapsed.
  local isDisenchant = currentMode == "disenchant"
  seasonHeader:SetShown(isDisenchant)
  if isDisenchant then
    seasonHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
    UpdateSectionHeaderText(seasonHeader)
    local seasonCollapsed = ns.db.uiCollapsed.season
    adventurerCheckbox:SetShown(not seasonCollapsed)
    previousSeasonCheckbox:SetShown(not seasonCollapsed)
    if seasonCollapsed then
      y = y - ROW_STEP
    else
      adventurerCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y)
      y = y - ROW_STEP
      previousSeasonCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y)
      y = y - ROW_STEP
    end
    y = y - 10
  else
    adventurerCheckbox:Hide()
    previousSeasonCheckbox:Hide()
  end

  levelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  minLevelBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + LABEL_COLUMN, y + 2)
  y = y - ROW_STEP - 10

  refreshButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
end

-- Switches the panel between disenchant and upgrade mode (#17): swaps which
-- candidate gate and saved filter values drive the results list.
function UI:SetMode(mode)
  currentMode = mode
  disenchantModeCheckbox:SetChecked(mode == "disenchant")
  upgradeModeCheckbox:SetChecked(mode == "upgrade")
  frame.title:SetText(ADDON_NAME .. (mode == "upgrade" and " - Upgrade" or " - Disenchant"))

  local isDisenchant = mode == "disenchant"
  local settings = ns.db[mode]
  for quality, cb in pairs(qualityCheckboxes) do
    cb:SetChecked(not settings.excludedQualities[quality])
  end
  for id, cb in pairs(slotCheckboxes) do
    cb:SetChecked(not settings.excludedSlotGroups[id])
  end
  if isDisenchant then
    adventurerCheckbox:SetChecked(ns.db.disenchant.includeAdventurerTier)
    previousSeasonCheckbox:SetChecked(ns.db.disenchant.includePreviousSeason)
  end
  minLevelBox:SetText(tostring(settings.minLevel))
  maxLevelBox:SetText(tostring(settings.maxLevel))

  self:RelayoutFrame()
  self:Refresh()
end

function UI:Show()
  if not frame then
    CreatePanel()
  end
  frame:Show()
end
