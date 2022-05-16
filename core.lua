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
local command_usage_string = table.concat({ command_font, command_format, command_locale, command_lock, command_reset, command_width, command_toggle, command_unlock }, " || ")
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

-- indices for consistent and quick table lookup
local ci_enabled     = 1 -- config
local ci_width       = 2
local ci_format_base = 3
local ci_options     = 4
local fi_draggable = 1   -- frame_options
local fi_font      = "font"
local fi_flags     = "flags"
local fi_size      = "size"
local fi_point     = true

-- local handles for global functions
local b_and         = bit.band
local get_cleu_info = CombatLogGetCurrentEventInfo
local get_time      = GetTime
local get_locale    = GetLocale
local print         = print
local q_first       = ddps_queue.first
local q_pop         = ddps_queue.pop
local q_push        = ddps_queue.push
local s_find        = string.find
local s_format      = string.format
local t_concat      = table.concat
local tonumber      = tonumber
local tostring      = tostring
local type          = type

-- state
local config      = nil
local samples     = ddps_queue.new(1000)
local damage      = 0.0
local enabled     = true
local format_base = "(%.2fK)"
local frame       = CreateFrame("frame", "ddps_frame")
local options     = nil
local l           = ddps_locale[get_locale()] or ddps_locale["enUS"]
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

local function drag_stop_handle(f)
  stop_moving_or_sizing(f)
  options[fi_point] = { get_point(f) }
end

local function lock_frame()
  enable_mouse(frame, false)
  set_movable(frame, false)
  register_for_drag(frame, nil)
  options[fi_draggable] = false
end

local function set_default_config() -- returns copies of default config tables
  local t = {}
  t[ci_enabled] = true
  t[ci_width] = 5.0
  t[ci_format_base] = "(%.2fk)"
  local fo = t[ci_options]
  if fo == nil then
    fo = {}
    t[ci_options] = fo
  end
  fo[fi_font] = "fonts/frizqt__.ttf"
  fo[fi_flags] = "outline"
  fo[fi_size] = 10
  set_point(frame, center)
  fo[fi_point] = { get_point(frame) }
  fo[fi_draggable] = false
  return t, t, fo
end

local function set_format(fmt) -- sets `format_base` with sanity checking
  if type(fmt) == string_t then
    format_base = s_format("%s", fmt)
    config[ci_format_base] = s_format("%s", format_base)
  end
  return s_format("%s", format_base)
end

local function set_sample_width(w) -- sets `sample_width` with sanity checking
  if (type(w) == number_t) and validate_number_gt0(w) then
    width = w
    config[ci_width] = width
  end
  return width
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

local function toggle() -- toggles event registration and frame show state
  enabled = not enabled
  config[ci_enabled] = enabled
  if enabled then
    register_all_events()
    show_frame(frame)
  else
    unregister_all_events()
    hide_frame(frame)
  end
  return enabled
end

local function unlock_frame()
  enable_mouse(frame, true)
  set_movable(frame, true)
  register_for_drag(frame, "leftbutton")
  config[ci_options][fi_draggable] = true
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
  set_point(text, center, 0, 0)
  local point = options[fi_point]
  if point then
    set_point(frame, point[1] or center, point[2] or 0, point[3] or 0, point[4], point[5])
  else
    set_point(frame, center, 0, 0)
  end
  set_script(frame, "OnDragStart", drag_start_handle)
  set_script(frame, "OnDragStop", drag_stop_handle)
  if options[fi_draggable] then
    unlock_frame()
  else
    lock_frame()
  end
end

local function handle_addon_loaded(arg1) -- get saved variables and perform initial setup
  if arg1 ~= addon_name then return end
  if ddps_config == nil then
    ddps_config, config, options = set_default_config()
  else
    config = ddps_config
    options = ddps_config[ci_options]
  end
  enabled = config[ci_enabled]
  width = config[ci_width] 
  format_base = s_format("%s", config[ci_format_base])
  refresh_frame()
end

local function handle_font_update(args) -- configures some `frame_options` settings
  local _, _, field, value = s_find(args, "%s?(%w+)%s?(.*)")
  if field == nil then
    return l.message_font_usage
  elseif options[field] == nil then
    return s_format(l.message_font_unknown_field, field)
  elseif (vakue == nil) or (value == empty) then
    return s_format(l.message_font_dump, field, tostring(options[field]))
  elseif field == fi_size then
    local v = tonumber(value)
    if v == nil then
      return s_format(l.message_font_bad_conversion, value)
    elseif validate_number_gt0(v) then
      value = v
    else
      return l.message_font_size_lt0
    end
  end  
  options[field] = value
  set_font(text, options[fi_font], options[fi_size], options[fi_flags])
  return s_format(l.message_font_changed, field, tostring(value))
end

local function handle_format_update(args) -- configures `format_base`
  if (args == nil) or (args == empty) then 
    return s_format(l.message_format_current, format_base)
  elseif set_format(args) then
    if options[fi_draggable] then
      set_text(text, "%s", format_base)
    end
    return s_format(l.message_format_changed, args)
  else
    return l.message_format_fail .. args
  end
end

local function handle_lock(args)
  lock_frame()
  set_text(text, empty)
  if not enabled then 
    hide_frame(frame) 
  end
  return l.message_locked_frame
end

local function handle_toggle_update(args)
  toggle()
  if enabled then
    return l.message_enabled
  else
    return l.message_disabled
  end
end

local function handle_width_update(args)
  local n = tonumber(args)
  if n then
    set_sample_width(n)
  end
  return s_format(l.message_width_changed, width)
end

local function handle_unlock(args)
  unlock_frame()
  set_text(text, "%s", format_base)
  if not enabled then 
    show_frame(frame)
    set_text(text, "%s", format_base)
  end
  return l.message_unlocked_frame
end

local function handle_locale_update(args)
  if (args == nil) or (args == empty) then
    args = get_locale()
  end 
  local tmp = ddps_locale[args]
  if tmp == nil then 
    return s_format(l.message_locale_fail, args) 
  end
  l = tmp
  return s_format(l.message_locale_success, args)
end

local function handle_reset(args)
  ddps_config, config, options = set_default_config()
  return s_format("%s", l.message_reset)
end

local function handle_slash_command(c)
  local _, _, cmd, args = s_find(c, "%s?(%w+)%s?(.*)") -- split string on space
  local message = nil
  if     cmd == command_font   then message = handle_font_update(args)
  elseif cmd == command_format then message = handle_format_update(args)
  elseif cmd == command_lock   then message = handle_lock(args)
  elseif cmd == command_locale then message = handle_locale_update(args)
  elseif cmd == command_toggle then message = handle_toggle_update(args)
  elseif cmd == command_width  then message = handle_width_update(args)
  elseif cmd == command_unlock then message = handle_unlock(args)
  elseif cmd == command_reset  then message = handle_reset(args)
  else
    message = s_format(l.message_usage, command_usage_string)
  end
  print(message_prefix .. message)
end

local function is_affiliated_with_player(flags)
  return b_and(flags, flag_mine) ~= 0
end

local function has_damage_payload(subevent)
  return (subevent == "SPELL_PERIODIC_DAMAGE")
      or (subevent == "SPELL_DAMAGE")
      or (subevent == "SWING_DAMAGE")
      or (subevent == "RANGE_DAMAGE")
end

local function handle_cleu()
  local time, subevent, _, _, _, flags, _, _, _, _, _, dam_swing, _, _, dam_spell = get_cleu_info()
  if (not has_damage_payload(subevent)) or (not is_affiliated_with_player(flags)) then return end
  if dam_spell then
    damage = damage + dam_spell
  else
    damage = damage + dam_swing
  end
  q_push(damage, time)
  local damage_lo, time_lo = q_first()
  while time_lo  < (time - width) do -- filter stale samples
    damage_lo, time_lo = q_pop()
  end
  dps = (damage - damage_lo) / (time - time_lo)
  if validate_number_gt0(dps) then
    set_text(text, format_base, dps / 1e3)
  end 
end

local function handle_regen_disabled()
  show_frame(frame)
end

local function handle_regen_enabled()
  hide_frame(frame)
end

local function handle_event(_, event, ...)
  if     event == event_combat_log_event_unfiltered then handle_cleu(...)
  elseif event == event_player_regen_enabled        then handle_regen_enabled(...)
  elseif event == event_player_regen_disabled       then handle_regen_disabled(...)
  elseif event == event_addon_loaded                then handle_addon_loaded(...)
  end
end

register_event(frame, event_addon_loaded)
set_script(frame, "OnEvent", handle_event)

SLASH_DDPS1 = "/ddps"
SLASH_DDPS2 = "/donage"

SlashCmdList["DDPS"] = handle_slash_command
