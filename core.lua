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

-- local handles for global functions
local b_and         = bit.band
local ct_after      = C_Timer.After
local floor         = math.floor
local get_cleu_info = CombatLogGetCurrentEventInfo
local get_locale    = GetLocale
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

local q_sample
local q_first = -1
local q_last  = -1
local q_idx_d = false -- just an index for quick table lookup
local q_idx_t = true
local q_pool  = {}
local q_size  = #q_pool

local function q_new(sz)
  q_size = sz
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
    pt[1], pt[2], pt[3], pt[4] = get_point(frame)
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

local function handle_command_font(args) -- configures some `frame_options` settings
  local field, value = extract_args(args)
  if field == nil then return l.message_font_usage end
  if options[field] == nil then return s_format(l.message_font_unknown_field, field) end
  if (value == nil) or (value == empty) then return s_format(l.message_font_dump, field, tostring(options[field])) end
  if field == fi_size then
    local v = tonumber(value)
    if v == nil then return s_format(l.message_font_bad_conversion, value) end
    if not validate_number_gt0(v) then return l.message_font_size_lt0 end
    value = v
  end
  options[field] = value
  set_font(text, options[fi_font], options[fi_size], options[fi_flags])
  return s_format(l.message_font_changed, field, tostring(value))
end

local function handle_command_format(args) -- configures `format_base`
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

local function handle_command_toggle(args)
  toggle()
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
  return empty
end

local prd = "SPELL_PERIODIC_DAMAGE"
local spl = "SPELL_DAMAGE"
local swn = "SWING_DAMAGE"
local rng = "RANGE_DAMAGE"

local function has_damage_payload(s)
  return (s == prd)
      or (s == spl)
      or (s == swn)
      or (s == rng)
end

local display_promise = false
local display_time = 0.0
local display_damage = 0.0

local function display()
  local damage_lo, time_lo = q_get_first()
  local tdiff = display_time - width
  while time_lo < tdiff do -- filter stale samples
    q_pop()
    damage_lo, time_lo = q_get_first()
  end
  local dps = (display_damage - damage_lo) / (display_time - time_lo)
  if validate_number_gt0(dps) then
    set_text(text, format_base, dps * multiplier)
  end
  display_promise = false -- promise fulfilled
end

local coam = COMBATLOG_OBJECT_AFFILIATION_MINE
local time, subevent, flags, dam_swing, dam_spell, _

local function handle_event_cleu()
  time, subevent, _, _, _, flags, _, _, _, _, _, dam_swing, _, _, dam_spell = get_cleu_info()
  if (not b_and(flags, coam)) or (not has_damage_payload(subevent)) then return end
  if dam_spell then
    damage = damage + dam_spell
  else
    damage = damage + dam_swing
  end
  q_push(damage, time)
  if not display_promise then
    display_time = time
    display_damage = damage
    ct_after(0.0, display) -- display on the next frame
    display_promise = true -- promise made
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
  if     event == event_player_regen_enabled  then handle_event_regen_enabled()
  elseif event == event_player_regen_disabled then handle_event_regen_disabled()
  elseif event == event_addon_loaded          then handle_event_addon_loaded(arg1)
  end
end)

local frame_cleu = CreateFrame("frame", "ddps_frame_cleu")
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
