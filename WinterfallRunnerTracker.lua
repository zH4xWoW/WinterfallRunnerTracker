local ADDON_NAME = ...
local f = CreateFrame("Frame")

-- ===== Defaults =====
local DEFAULTS = {
  enabled = true,
  announce = true,
  sound = false,

  zoneOnly = true,
  zoneName = "Winterspring",

  respawnSeconds = 90,       -- 1:30 from spawn
  runnersPerWave = 3,
  earlyWarningSeconds = 10,

  ui = {
    shown = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 200,
    scale = 1.0,
  },

  debug = false,
}

WFRTrackerDB = WFRTrackerDB or {}

local function CopyDefaults(src, dst)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function Msg(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7ddcffWFR|r: " .. text)
end

local function Debug(text)
  if WFRTrackerDB.debug then
    Msg("|cffffcc00DEBUG|r " .. text)
  end
end

local function Announce(text)
  if WFRTrackerDB.announce then Msg(text) end
end

local function PlayPing()
  if not WFRTrackerDB.sound then return end
  PlaySound(8959)
end

local function FormatTime(secs)
  if not secs then return "--:--" end
  if secs < 0 then secs = 0 end
  local m = math.floor(secs / 60)
  local s = math.floor(secs % 60)
  return string.format("%d:%02d", m, s)
end

local function InTargetZone()
  if not WFRTrackerDB.zoneOnly then return true end
  local zone = GetRealZoneText() or GetZoneText()
  return zone == WFRTrackerDB.zoneName
end

local RUNNER_NAME = "Winterfall Runner"

-- ===== State =====
local state = {
  aliveGuids = {},
  aliveCount = 0,

  lastSpawnAt = nil,
  nextSpawnAt = nil,
  warned = false,
}

local function RecountAlive()
  local n = 0
  for _ in pairs(state.aliveGuids) do n = n + 1 end
  state.aliveCount = n
end

local function SetSpawnNow(reason)
  state.lastSpawnAt = GetTime()
  state.nextSpawnAt = state.lastSpawnAt + (WFRTrackerDB.respawnSeconds or 90)
  state.warned = false

  if reason then
    Announce(("Spawn time set (%s). Next spawn in ~%s."):format(reason, FormatTime(WFRTrackerDB.respawnSeconds)))
  else
    Announce(("Spawn time set. Next spawn in ~%s."):format(FormatTime(WFRTrackerDB.respawnSeconds)))
  end
  PlayPing()
end

-- ===== UI =====
-- IMPORTANT FIX: BackdropTemplate for SetBackdrop support on Classic 1.15.x
local ui = CreateFrame("Frame", "WFRTrackerFrame", UIParent, "BackdropTemplate")
ui:SetSize(240, 70)
ui:SetScale(1.0)
ui:SetClampedToScreen(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetMovable(true)

ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
ui:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
  WFRTrackerDB.ui.point = point
  WFRTrackerDB.ui.relativePoint = relativePoint
  WFRTrackerDB.ui.x = math.floor(xOfs + 0.5)
  WFRTrackerDB.ui.y = math.floor(yOfs + 0.5)
end)

ui:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
ui:SetBackdropColor(0, 0, 0, 0.7)

ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ui.title:SetPoint("TOPLEFT", 10, -8)
ui.title:SetText("Winterfall Runner Tracker")

ui.line1 = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ui.line1:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -6)

ui.line2 = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ui.line2:SetPoint("TOPLEFT", ui.line1, "BOTTOMLEFT", 0, -4)

ui.hint = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ui.hint:SetPoint("BOTTOMRIGHT", -10, 8)
ui.hint:SetText("Drag • /wfr help")

-- Big banner (no backdrop needed)
local banner = CreateFrame("Frame", nil, UIParent)
banner:SetSize(600, 120)
banner:SetPoint("CENTER", 0, 120)
banner:Hide()
banner.alpha = 0

banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
banner.text:SetPoint("CENTER")
banner.text:SetText("SPAWNING!")
banner.text:SetAlpha(0)

local function ShowBanner(message)
  banner.text:SetText(message or "SPAWNING!")
  banner:Show()
  banner.alpha = 1
  banner.text:SetAlpha(1)
end

banner:SetScript("OnUpdate", function(self, elapsed)
  if not self:IsShown() then return end
  self.alpha = self.alpha - (elapsed / 1.2)
  if self.alpha <= 0 then
    self:Hide()
    self.text:SetAlpha(0)
    return
  end
  self.text:SetAlpha(self.alpha)
end)

local function ApplyUISavedPos()
  WFRTrackerDB.ui = WFRTrackerDB.ui or CopyDefaults(DEFAULTS.ui, {})

  ui:ClearAllPoints()
  ui:SetPoint(
    WFRTrackerDB.ui.point or "CENTER",
    UIParent,
    WFRTrackerDB.ui.relativePoint or "CENTER",
    WFRTrackerDB.ui.x or 0,
    WFRTrackerDB.ui.y or 200
  )
  ui:SetScale(WFRTrackerDB.ui.scale or 1.0)
end

local function UpdateUI()
  if not WFRTrackerDB.ui.shown then ui:Hide() return end
  ui:Show()

  ui.line1:SetText(string.format("Alive in range: %d/%d", state.aliveCount, WFRTrackerDB.runnersPerWave or 3))

  if state.nextSpawnAt then
    local remain = state.nextSpawnAt - GetTime()
    ui.line2:SetText("Next spawn in: " .. FormatTime(remain))
  else
    ui.line2:SetText("Next spawn in: --:--")
  end
end

-- ===== Nameplate tracking =====
local function IsRunnerUnit(unit)
  if not unit or not UnitExists(unit) then return false end
  local name = UnitName(unit)
  return name == RUNNER_NAME
end

local function OnNameplateAdded(unit)
  if not WFRTrackerDB.enabled then return end
  if not InTargetZone() then return end
  if not IsRunnerUnit(unit) then return end

  local guid = UnitGUID(unit)
  if not guid then return end

  local wasZero = (state.aliveCount == 0)

  state.aliveGuids[guid] = true
  RecountAlive()

  Debug(("NAME_PLATE_UNIT_ADDED: %s alive=%d"):format(guid, state.aliveCount))

  if wasZero and state.aliveCount >= 1 then
    SetSpawnNow("detected")
    Announce("Winterfall Runners detected (spawn cycle started).")
  end

  UpdateUI()
end

local function OnNameplateRemoved(unit)
  if not WFRTrackerDB.enabled then return end
  if not InTargetZone() then return end
  if not IsRunnerUnit(unit) then return end

  local guid = UnitGUID(unit)
  if guid then
    state.aliveGuids[guid] = nil
    RecountAlive()
    Debug(("NAME_PLATE_UNIT_REMOVED: %s alive=%d"):format(guid, state.aliveCount))
    UpdateUI()
  end
end

-- ===== Timer tick =====
local ticker = 0
f:SetScript("OnUpdate", function(_, elapsed)
  ticker = ticker + elapsed
  if ticker < 0.2 then return end
  ticker = 0

  if not WFRTrackerDB.enabled then return end
  if not InTargetZone() then return end

  if state.nextSpawnAt then
    local remain = state.nextSpawnAt - GetTime()
    local warnAt = WFRTrackerDB.earlyWarningSeconds or 10

    if (not state.warned) and remain <= warnAt and remain > 0 then
      state.warned = true
      Announce("Runners incoming in ~" .. FormatTime(remain) .. "!")
      PlayPing()
    end

    if remain <= 0 then
      state.nextSpawnAt = nil
      state.warned = false
      Announce("Runners should be spawning now!")
      ShowBanner("SPAWNING!")
      PlayPing()
    end
  end

  UpdateUI()
end)

-- ===== Slash commands =====
SLASH_WFRTRACKER1 = "/wfr"
SlashCmdList.WFRTRACKER = function(msg)
  msg = msg or ""
  local lmsg = msg:lower()

  if lmsg == "spawn" then
    SetSpawnNow("manual")
  elseif lmsg == "reset" then
    state.aliveGuids = {}
    state.aliveCount = 0
    state.lastSpawnAt = nil
    state.nextSpawnAt = nil
    state.warned = false
    Msg("State reset.")
  elseif lmsg == "status" then
    Msg("Enabled=" .. tostring(WFRTrackerDB.enabled)
      .. " zoneOnly=" .. tostring(WFRTrackerDB.zoneOnly)
      .. " zone=" .. tostring(WFRTrackerDB.zoneName)
      .. " alive=" .. tostring(state.aliveCount)
      .. " respawn=" .. tostring(WFRTrackerDB.respawnSeconds)
      .. " warn=" .. tostring(WFRTrackerDB.earlyWarningSeconds))
    if state.nextSpawnAt then
      Msg("Next spawn in ~" .. FormatTime(state.nextSpawnAt - GetTime()))
    end
  elseif lmsg == "help" or lmsg == "" then
    Msg("Commands:")
    Msg("/wfr spawn   (set spawn time to now)")
    Msg("/wfr status")
    Msg("/wfr reset")
  else
    Msg("Try /wfr help")
  end

  UpdateUI()
end

-- ===== Events =====
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    WFRTrackerDB = CopyDefaults(DEFAULTS, WFRTrackerDB)

  elseif event == "PLAYER_LOGIN" then
    WFRTrackerDB = CopyDefaults(DEFAULTS, WFRTrackerDB)
    ApplyUISavedPos()
    UpdateUI()
    Msg("Loaded. Spawn-based tracking enabled. Use /wfr spawn for perfect timing.")

  elseif event == "NAME_PLATE_UNIT_ADDED" then
    OnNameplateAdded(arg1)

  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    OnNameplateRemoved(arg1)
  end
end)
