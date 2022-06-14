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
local command_pool   = "pool"
local command_width  = "width"
local command_reset  = "reset"
local command_toggle = "toggle"
local command_unlock = "unlock"
local command_div    = "div"
local command_usage_string = table.concat({ command_font, command_format, command_locale, command_lock, command_pool, command_reset, command_width, command_toggle, command_unlock, command_div }, " || ")
local empty = ""

local event_addon_loaded                = "ADDON_LOADED"
local event_combat_log_event_unfiltered = "COMBAT_LOG_EVENT_UNFILTERED"
local event_player_regen_disabled       = "PLAYER_REGEN_DISABLED"
local event_player_regen_enabled        = "PLAYER_REGEN_ENABLED"
local events = { event_addon_loaded, event_combat_log_event_unfiltered, event_player_regen_disabled, event_player_regen_enabled }

local message_prefix = addon_name .. " - "
local center         = "CENTER"
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

-- ternary statements below are useful for providing intellisense type hinting in vscode
local function no_op(...) end

-- local handles for global functions
local b_and         = bit.band or no_op
local ct_after      = C_Timer.After or no_op
local floor         = math.floor
local get_cleu_info = CombatLogGetCurrentEventInfo or no_op
local get_locale    = GetLocale or no_op
local print         = print

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
local l           = _G["ddps_locale"][get_locale()] or _G["ddps_locale"]["enUS"]
local multiplier  = 1.0 / 1e3
local options     = nil
local text        = frame:CreateFontString()
local width       = 5.0

-- local handles for frame/fontstring functions
local enable_mouse          = frame.EnableMouse or no_op
local get_point             = frame.GetPoint or no_op
local hide_frame            = frame.Hide or no_op
local register_event        = frame.RegisterEvent or no_op
local register_for_drag     = frame.RegisterForDrag or no_op
local set_font              = text.SetFont or no_op
local set_height            = frame.SetHeight or no_op
local set_movable           = frame.SetMovable or no_op
local set_parent            = text.SetParent or no_op
local set_point             = frame.SetPoint or no_op
local set_script            = frame.SetScript or no_op
local set_text              = text.SetFormattedText or no_op
local set_width             = frame.SetWidth or no_op
local show_frame            = frame.Show or no_op
local drag_start_handle     = frame.StartMoving or no_op
local stop_moving_or_sizing = frame.StopMovingOrSizing or no_op
local unregister_event      = frame.UnregisterEvent or no_op

local q_first = -1
local q_last  = -1
local q_idx_d = false -- just an index for quick table lookup
local q_idx_t = true
local q_pool  = {}
local q_size  = #q_pool
local q_sample

local function q_new(_sz)
  q_size = _sz
  for i = q_size,1,-1 do
    q_pool[i] = { [q_idx_d] = 0.0, [q_idx_t] = 0.0 }
  end
  q_first = 1
  q_last = 0
end

local function q_get_first()
  q_sample = q_pool[q_first]
  return q_sample[q_idx_d], q_sample[q_idx_t]
end

local function q_pop()
  if q_first == q_size then
    q_first = 1
  else
    q_first = q_first + 1
  end
end

local function q_push(d, t)
  if q_last == q_size then
    q_last = 1
  else
    q_last = q_last + 1
  end
  q_sample = q_pool[q_last]
  q_sample[q_idx_d] = d
  q_sample[q_idx_t]= t
end

local function q_clear()
  q_first = 1
  q_last = 0
  q_sample = q_pool[q_first]
  q_sample[q_idx_d] = 0.0
  q_sample[q_idx_t]= 0.0
end

-- helper functions
local function validate_number_gt0(_n) -- filters wow's weird nan situation
  return (_n > 0.0) and not (_n < 0.0)
end

local function extract_args(_cmd)
  local _, _, _c, _a = s_find(_cmd, "%s?(%w+)%s?(.*)") -- split string on space
  return _c, _a
end

local function drag_stop_handle()
  stop_moving_or_sizing(frame)
  local _pt = options[fi_point]
  if type(_pt) ~= table_t then
    options[fi_point] = { get_point(frame) }
  else
    _pt[1], _pt[2], _pt[3], _pt[4] = get_point(frame)
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
  local _pt = options[fi_point]
  set_point(text, center, 0, 0)
  set_point(frame, _pt[1] or center, _pt[2], _pt[3] or 0, _pt[4], _pt[5])
  set_script(frame, "OnDragStart", drag_start_handle)
  set_script(frame, "OnDragStop", drag_stop_handle)
  if options[fi_draggable] then
    unlock_frame()
    set_text(text, "%s", format_base)
  else
    lock_frame()
  end
end

local function handle_event_addon_loaded(_arg1) -- get saved variables and perform initial setup
  if _arg1 ~= addon_name then return end
  config = _G["ddps_config"]
  if not config then
    config = get_default_config()
    _G["ddps_config"] = config
  end
  q_new(config[ci_pool_size])
  options = config[ci_options]
  enabled = config[ci_enabled]
  width = config[ci_width]
  div_by_1e3 = config[ci_div_by_1e3]
  format_base = s_format("%s", config[ci_format_base])
  refresh_frame()
end

local function handle_command_font(_args) -- configures some `frame_options` settings
  local _field, _value = extract_args(_args)
  if _field == nil then return l.message_font_usage end
  if options[_field] == nil then return s_format(l.message_font_unknown_field, _field) end
  if (_value == nil) or (_value == empty) then return s_format(l.message_font_dump, _field, tostring(options[_field])) end
  if _field == fi_size then
    local _v = tonumber(_value)
    if _v == nil then return s_format(l.message_font_bad_conversion, _value) end
    if not validate_number_gt0(_v) then return l.message_font_size_lt0 end
    _value = _v
  end
  options[_field] = _value
  set_font(text, options[fi_font], options[fi_size], options[fi_flags])
  return s_format(l.message_font_changed, _field, tostring(_value))
end

local function handle_command_format(_args) -- configures `format_base`
  if (_args == nil) or (_args == empty) then return s_format(l.message_format_current, format_base) end
  set_format(_args)
  if options[fi_draggable] then
    set_text(text, "%s", format_base)
  end
  return s_format(l.message_format_changed, _args)
end

local function handle_command_lock(_)
  lock_frame()
  set_text(text, empty)
  if not enabled then
    hide_frame(frame)
  end
  return l.message_locked_frame
end

local function handle_command_toggle(_)
  toggle()
  if enabled then return l.message_enabled
  else return l.message_disabled end
end

local function handle_command_width(_args)
  local _w = tonumber(_args)
  if _w and validate_number_gt0(_w) then
    width = _w
    config[ci_width] = _w
  end
  return s_format(l.message_width_changed, width)
end

local function handle_command_unlock(_)
  unlock_frame()
  set_text(text, "%s", format_base)
  show_frame(frame)
  return l.message_unlocked_frame
end

local function handle_command_locale(_args)
  if (_args == nil) or (_args == empty) then
    _args = get_locale()
  end
  local _tmp = ddps_locale[_args]
  if _tmp == nil then return s_format(l.message_locale_fail, _args) end
  l = _tmp
  return s_format(l.message_locale_success, _args)
end

local function handle_command_reset(_)
  _G["ddps_config"] = get_default_config()
  handle_event_addon_loaded(addon_name)
  return l.message_reset
end

local function handle_command_div(_)
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

local function handle_command_pool(_args)
  local _success, _result = pcall(floor, _args) -- floor can convert string to number
  if not _success then return end
  if not validate_number_gt0(_result) then return end
  config[ci_pool_size] = _result
  handle_event_addon_loaded(addon_name)
  return empty
end

local _prd = "SPELL_PERIODIC_DAMAGE"
local _spl = "SPELL_DAMAGE"
local _swn = "SWING_DAMAGE"
local _rng = "RANGE_DAMAGE"

local function has_damage_payload(s)
  return (s == _prd)
      or (s == _spl)
      or (s == _swn)
      or (s == _rng)
end

local _display_promise = false
local _display_time = 0.0
local _display_damage = 0.0

local function display()
  local _damage_lo, _time_lo = q_get_first()
  local _tdiff = _display_time - width
  while _time_lo < _tdiff do -- filter stale samples
    q_pop()
    _damage_lo, _time_lo = q_get_first()
  end
  local _dps = (_display_damage - _damage_lo) / (_display_time - _time_lo)
  if validate_number_gt0(_dps) then
    set_text(text, format_base, _dps * multiplier)
  end
  _display_promise = false -- promise fulfilled
end

local _coam = COMBATLOG_OBJECT_AFFILIATION_MINE
local _time, _subevent, _flags, _dam_swing, _dam_spell, _

local function handle_event_cleu()
  _time, _subevent, _, _, _, _flags, _, _, _, _, _, _dam_swing, _, _, _dam_spell = get_cleu_info()
  if (not b_and(_flags, _coam)) or (not has_damage_payload(_subevent)) then return end
  if _dam_spell then
    damage = damage + _dam_spell
  else
    damage = damage + _dam_swing
  end
  q_push(damage, _time)
  if not _display_promise then
    _display_time = _time
    _display_damage = damage
    ct_after(0.0, display) -- display on the next frame
    _display_promise = true -- promise made
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
set_script(frame, "OnEvent", function (_, _event, _arg1) 
  if     _event == event_player_regen_enabled  then handle_event_regen_enabled()
  elseif _event == event_player_regen_disabled then handle_event_regen_disabled()
  elseif _event == event_addon_loaded          then handle_event_addon_loaded(_arg1)
  end
end)

local frame_cleu = CreateFrame("frame", "ddps_frame_cleu")
register_event(frame_cleu, event_combat_log_event_unfiltered)
set_script(frame_cleu, "OnEvent", handle_event_cleu)

SLASH_DDPS1 = "/ddps"
SLASH_DDPS2 = "/donage"

SlashCmdList["DDPS"] = function(_c) 
  local _cmd, _args = extract_args(_c)
  local _message = nil
  if     _cmd == command_font   then _message = handle_command_font(_args)
  elseif _cmd == command_format then _message = handle_command_format(_args)
  elseif _cmd == command_lock   then _message = handle_command_lock(_args)
  elseif _cmd == command_locale then _message = handle_command_locale(_args)
  elseif _cmd == command_toggle then _message = handle_command_toggle(_args)
  elseif _cmd == command_width  then _message = handle_command_width(_args)
  elseif _cmd == command_unlock then _message = handle_command_unlock(_args)
  elseif _cmd == command_reset  then _message = handle_command_reset(_args)
  elseif _cmd == command_div    then _message = handle_command_div(_args)
  elseif _cmd == command_pool   then _message = handle_command_pool(_args)
  else
    _message = s_format(l.message_usage, command_usage_string)
  end
  print(message_prefix .. _message)
end
