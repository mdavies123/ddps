local frame = CreateFrame("frame", "ddps_frame")
local text = frame:CreateFontString()
local pairs = pairs

local events = { "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local function register_all_events()
  for _, e in pairs(events) do
    frame:RegisterEvent(e)
  end
end

local function unregister_all_events()
  for _, e in pairs(events) do
    frame:UnregisterEvent(e)
  end
end

local function unlock_frame()
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("leftbutton")
  ddps_config.draggable = true
end

local function lock_frame()
  frame:EnableMouse(false)
  frame:SetMovable(false)
  frame:RegisterForDrag(nil)
  ddps_config.draggable = false
end

local function drag_stop_handle()
  frame:StopMovingOrSizing()
  local pt = ddps_config.point
  if type(pt) ~= "table" then
    ddps_config.point = { frame:GetPoint() }
  else
    pt[1], pt[2], pt[3], pt[4], pt[5] = frame:GetPoint()
  end
end

local function refresh_frame()
  if enabled then
    register_all_events()
    frame:Show()
  else
    unregister_all_events()
    frame:Hide()
  end
  text:SetWidth(90)
  text:SetHeight(30)
  text:SetFont(ddps_config.font, ddps_config.size, ddps_config.flags)
  text:SetParent(ddps_frame)
  local pt = ddps_config.point
  frame:SetPoint(pt[1] or "center", pt[2], pt[3] or 0, pt[4], pt[5])
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", drag_stop_handle)
  if ddps_config.draggable then
    unlock_frame()
    text:SetFormattedText("%s", ddps_config.format_base)
  else
    lock_frame()
  end
end
