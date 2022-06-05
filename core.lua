-- the donage-beerware license (version 69):
--
-- donage-stormrage(us) wrote this code
-- as long as you retain this notice, you can do whatever you want with this code
-- if we meet someday, and you think this stuff is worth it, you can buy me a beer in return

-- constants
local addon_name = ...
local command_font   = "font"
local command_format = "format"
local command_locale = "locale"
local command_lock   = "lock"
local command_width  = "width"
local command_reset  = "reset"
local command_toggle = "toggle"
local command_unlock = "unlock"
local command_div    = "div"
local command_usage_string = table.concat({ command_font, command_format, command_locale, command_lock, command_reset, command_width, command_toggle, command_unlock, command_div }, " || ")
local empty = ""

local event_addon_loaded                = "ADDON_LOADED"
local event_combat_log_event_unfiltered = "COMBAT_LOG_EVENT_UNFILTERED"
local event_player_regen_disabled       = "PLAYER_REGEN_DISABLED"
local event_player_regen_enabled        = "PLAYER_REGEN_ENABLED"
local events = { event_addon_loaded, event_combat_log_event_unfiltered, event_player_regen_disabled, event_player_regen_enabled }

local flag_mine      = COMBATLOG_OBJECT_AFFILIATION_MINE
local message_prefix = addon_name .. " - "
local number_t       = type(0.0)
local center         = "CENTER"
local string_t       = type("")
local table_t        = type(_G)

-- indices for consistent and quick table lookup
local ci_enabled     = "enabled" -- config
local ci_width       = "width"
local ci_format_base = "format_base"
local ci_options     = "options"
local ci_pool_size   = "pool_size"
local ci_div_by_1e3  = "div_by_1e3"
local fi_draggable = "draggable" -- frame_options
local fi_font      = "font"
local fi_flags     = "flags"
local fi_size      = "size"
local fi_point     = "point"

-- local handles for global functions
local b_and         = bit.band
local ct_after      = C_Timer.After
local floor         = math.floor
local get_cleu_info = CombatLogGetCurrentEventInfo
local get_time      = GetTime
local get_locale    = GetLocale
local print         = print
local q_clear       = ddps_queue.clear
local q_first       = ddps_queue.first
local q_pop         = ddps_queue.pop
local q_push        = ddps_queue.push
local pcall         = pcall
local s_find        = string.find
local s_format      = string.format
local tonumber      = tonumber
local tostring      = tostring
local type          = type

-- state
local config      = nil
local damage      = 0.0
local div_by_1e3  = true
local enabled     = true
local format_base = "(%.2fK)"
local frame       = CreateFrame("frame", "ddps_frame")
local frame_cleu  = CreateFrame("frame", "ddps_frame_cleu")
local l           = ddps_locale[get_locale()] or ddps_locale["enUS"]
local multiplier  = 1.0 / 1e3
local options     = nil
local pool_size   = 8192
local text        = frame:CreateFontString()
local width       = 5.0

-- local handles for frame/fontstring functions
local enable_mouse          = frame.EnableMouse
local get_point             = frame.GetPoint
local hide_frame            = frame.Hide
local register_event        = frame.RegisterEvent
local register_for_drag     = frame.RegisterForDrag
local set_font              = text.SetFont
local set_height            = frame.SetHeight
local set_movable           = frame.SetMovable
local set_parent            = text.SetParent
local set_point             = frame.SetPoint
local set_script            = frame.SetScript
local set_text              = text.SetFormattedText
local set_width             = frame.SetWidth
local show_frame            = frame.Show
local drag_start_handle     = frame.StartMoving
local stop_moving_or_sizing = frame.StopMovingOrSizing
local unregister_event      = frame.UnregisterEvent

-- helper functions
local function validate_number_gt0(n) -- filters wow's weird nan situation
  return (n > 0.0) and not (n < 0.0)
end

local function extract_args(cmd)
  local _, _, c, a = s_find(cmd, "%s?(%w+)%s?(.*)") -- split string on space
  return c, a
end

local function drag_stop_handle()
  stop_moving_or_sizing(frame)
  local pt = options[fi_point]
  if type(pt) ~= table_t then
    pt = { get_point(frame) }
    options[fi_point] = pt
  else
    pt[1], pt[2], pt[3], pt[4], pt[5] = get_point(frame)
  end
end

local function lock_frame()
  enable_mouse(frame, false)
  set_movable(frame, false)
  register_for_drag(frame, nil)
  options[fi_draggable] = false
end

local function get_default_config() -- returns copies of default config tables
  return {
    [ci_div_by_1e3] = true,
    [ci_enabled] = true,
    [ci_format_base] = "(%.2fk)",
    [ci_options] = {
      [fi_draggable] = false,
      [fi_flags] = "outline",
      [fi_font] = "fonts/frizqt__.ttf",
      [fi_point] = { 
        [1] = "center",
        [2] = nil, 
        [3] = 0, 
        [4] = 0
      },
      [fi_size] = 10
    },
    [ci_pool_size] = 8192,
    [ci_width] = 5.0
  }
end

local function set_format(fmt)
  format_base = s_format("%s", fmt)
  config[ci_format_base] = s_format("%s", format_base)
end

local function register_all_events()
  for _, event in ipairs(events) do
    register_event(frame, event)
  end
end

local function unregister_all_events()
  for _, event in ipairs(events) do
    unregister_event(frame, event)
  end
end

local function toggle() -- toggles event registration and frame state; clears queue
  enabled = not enabled
  config[ci_enabled] = enabled
  if enabled then
    register_all_events()
  else
    unregister_all_events()
    hide_frame(frame)
  end
  q_clear()
  return enabled
end

local function unlock_frame()
  enable_mouse(frame, true)
  set_movable(frame, true)
  register_for_drag(frame, "leftbutton")
  options[fi_draggable] = true
end

local function refresh_frame()
  if enabled then
    register_all_events()
    show_frame(frame)
  else
    unregister_all_events()
    hide_frame(frame)
  end
  set_width(text, 90) -- these are arbitrary
  set_height(text, 30)
  set_width(frame, 90)
  set_height(frame, 30)
  set_font(text, options[fi_font], options[fi_size], options[fi_flags])
  set_parent(text, frame)
  local point = options[fi_point]
  set_point(text, center, 0, 0)
  set_point(frame, point[1] or center, point[2], point[3] or 0, point[4], point[5])
  set_script(frame, "OnDragStart", drag_start_handle)
  set_script(frame, "OnDragStop", drag_stop_handle)
  if options[fi_draggable] then
    unlock_frame()
    set_text(text, "%s", format_base)
  else
    lock_frame()
  end
end

local function handle_event_addon_loaded(arg1) -- get saved variables and perform initial setup
  if arg1 ~= addon_name then return end
  config = _G["ddps_config"]
  if config == nil then
    config = get_default_config()
    _G["ddps_config"] = config
  end
  ddps_queue.new(config[ci_pool_size])
  options = config[ci_options]
  enabled = config[ci_enabled]
  width = config[ci_width]
  div_by_1e3 = config[ci_div_by_1e3]
  format_base = s_format("%s", config[ci_format_base]) 
  refresh_frame()
end

local function handle_font_update(args) -- configures some `frame_options` settings
  local field, value = extract_args(args)
  if field == nil then return l.message_font_usage
  elseif options[field] == nil then return s_format(l.message_font_unknown_field, field)
  elseif (value == nil) or (value == empty) then return s_format(l.message_font_dump, field, tostring(options[field]))
  elseif field == fi_size then
    local v = tonumber(value)
    if v == nil then return s_format(l.message_font_bad_conversion, value)
    elseif not validate_number_gt0(v) then return l.message_font_size_lt0 end
    value = v
  end  
  options[field] = value
  set_font(text, options[fi_font], options[fi_size], options[fi_flags])
  return s_format(l.message_font_changed, field, tostring(value))
end

local function handle_format_update(args) -- configures `format_base`
  if (args == nil) or (args == empty) then return s_format(l.message_format_current, format_base) end
  set_format(args)
  if options[fi_draggable] then
    set_text(text, "%s", format_base)
  end
  return s_format(l.message_format_changed, args)
end

local function handle_command_lock(args)
  lock_frame()
  set_text(text, empty)
  if not enabled then 
    hide_frame(frame) 
  end
  return l.message_locked_frame
end

local function handle_command_toggle()
  if enabled then return l.message_enabled
  else return l.message_disabled end
end

local function handle_command_width(args)
  local w = tonumber(args)
  if w and validate_number_gt0(w) then
    width = w
    config[ci_width] = w
  end
  return s_format(l.message_width_changed, width)
end

local function handle_command_unlock(args)
  unlock_frame()
  set_text(text, "%s", format_base)
  show_frame(frame)
  return l.message_unlocked_frame
end

local function handle_command_locale(args)
  if (args == nil) or (args == empty) then
    args = get_locale()
  end
  local tmp = ddps_locale[args]
  if tmp == nil then return s_format(l.message_locale_fail, args) end
  l = tmp
  return s_format(l.message_locale_success, args)
end

local function handle_command_reset(args)
  _G["ddps_config"] = get_default_config()
  handle_event_addon_loaded(addon_name)
  return l.message_reset
end

local function handle_command_div(args)
  div_by_1e3 = not div_by_1e3
  config[ci_div_by_1e3] = div_by_1e3
  if div_by_1e3 then
    multiplier = 1.0 / 1e3
    return l.message_div_enabled
  else
    multiplier = 1.0
    return l.message_div_disabled
  end
end

local function handle_command_pool(args)
  local success, result = pcall(floor, args) -- floor can convert string to number
  if not success then return end
  if not validate_number_gt0(result) then return end
  config[ci_pool_size] = result
  handle_event_addon_loaded(addon_name)
end

local function is_affiliated_with_player(f)
  return b_and(f, flag_mine) ~= 0
end

local function has_damage_payload(s)
  return (s == "SPELL_PERIODIC_DAMAGE")
      or (s == "SPELL_DAMAGE")
      or (s == "SWING_DAMAGE")
      or (s == "RANGE_DAMAGE")
end


local time, subevent, flags, dam_swing, dam_spell, _
local damage_lo, time_lo, tdiff
local tlast = -1.0

local function handle_event_cleu()
  time, subevent, _, _, _, flags, _, _, _, _, _, dam_swing, _, _, dam_spell = get_cleu_info()
  if (not has_damage_payload(subevent)) or (not is_affiliated_with_player(flags)) then return end
  if dam_spell then
    damage = damage + dam_spell
  else
    damage = damage + dam_swing
  end
  q_push(damage, time)
  if time > tlast then
    damage_lo, time_lo = q_first()
    tdiff = time - width
    while time_lo < tdiff do -- filter stale samples
      damage_lo, time_lo = q_pop()
    end
    dps = (damage - damage_lo) / (time - time_lo)
    if validate_number_gt0(dps) then
      set_text(text, format_base, dps * multiplier)
    end
    tlast = time
  end
end

local function handle_event_regen_disabled()
  set_text(text, empty)
  show_frame(frame)
end

local function delay_handle()
  hide_frame(frame)
  q_clear()
  damage = 0
end

local function handle_event_regen_enabled()
  if not options[fi_draggable] then
    ct_after(width, delay_handle)
  else
    q_clear()
    damage = 0
    set_text(text, "%s", format_base)
  end
end

register_event(frame, event_addon_loaded)
set_script(frame, "OnEvent", function (_, event, arg1) 
  if     event == event_player_regen_enabled        then handle_event_regen_enabled()
  elseif event == event_player_regen_disabled       then handle_event_regen_disabled()
  elseif event == event_addon_loaded                then handle_event_addon_loaded(arg1)
  end
end)

register_event(frame_cleu, event_combat_log_event_unfiltered)
set_script(frame_cleu, "OnEvent", handle_event_cleu)

SLASH_DDPS1 = "/ddps"
SLASH_DDPS2 = "/donage"

SlashCmdList["DDPS"] = function(c) 
  local cmd, args = extract_args(c)
  local message = nil
  if     cmd == command_font   then message = handle_command_font(args)
  elseif cmd == command_format then message = handle_command_format(args)
  elseif cmd == command_lock   then message = handle_command_lock(args)
  elseif cmd == command_locale then message = handle_command_locale(args)
  elseif cmd == command_toggle then message = handle_command_toggle(args)
  elseif cmd == command_width  then message = handle_command_width(args)
  elseif cmd == command_unlock then message = handle_command_unlock(args)
  elseif cmd == command_reset  then message = handle_command_reset(args)
  elseif cmd == command_div    then message = handle_command_div(args)
  elseif cmd == command_pool   then message = handle_command_pool(args)
  else
    message = s_format(l.message_usage, command_usage_string)
  end
  print(message_prefix .. message)
end
