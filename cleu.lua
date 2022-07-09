-- local handles
local q_push = ddps_queue.push
local q_first = ddps_queue.first
local b_and = bit.band
local get_cleu_info = CombatLogGetCurrentEventInfo

-- constants
local flag_mine = COMBATLOG_OBJECT_AFFILIATION_MINE

-- config
local width = ddps_config.width
local multiplier = ddps_config.multiplier

-- state
local latest_time = -1.0
local damage = 0.0

local function validate_number_gt0(n) -- filters wow's weird nan situation
  return (n > 0.0) and not (n < 0.0)
end

local function has_damage_payload(s)
  return (s == "SPELL_PERIODIC_DAMAGE")
      or (s == "SPELL_DAMAGE")
      or (s == "SWING_DAMAGE")
      or (s == "RANGE_DAMAGE")
end

local subevent, flags, dam_swing, dam_spell, _

local function handle_event_cleu()
  latest_time, subevent, _, _, _, flags, _, _, _, _, _, dam_swing, _, _, dam_spell = get_cleu_info()
  if (not has_damage_payload(subevent)) or (not b_and(flags, flag_mine)) then return end
  if dam_spell then
    damage = damage + dam_spell
  else
    damage = damage + dam_swing
  end
  q_push(damage, time)
end

local function get_average()
  local damage_lo, time_lo = q_first()
  local tdiff = latest_time - width
  while time_lo < tdiff do -- filter stale samples
    damage_lo, time_lo = q_pop()
  end
  dps = (damage - damage_lo) / (time - time_lo)
  if validate_number_gt0(dps) then
    return dps * multiplier
  end
  return nil
end

local frame = CreateFrame("frame", "ddps_cleu_handler")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", handle_event_cleu)
frame.get_average = get_average
